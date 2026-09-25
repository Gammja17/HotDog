extends Node3D
## 한 판을 관리한다: 시간, 별점, 먹은 소시지, 손님, 흔적, 소리, 승패, 화면 구성.

const RackScript := preload("res://scripts/rack.gd")
const CUSTOMER := preload("res://scenes/customer.tscn")
const GAME_TIME := 180.0
const EAT_GOAL := 5
const MAX_STARS := 5.0

const ENDINGS := {
	"grab": ["셰프 승리!", "집게에 들린 강아지와 사장님의 눈이 마주쳤다.\n둘 다 비명을 질렀다."],
	"rack": ["셰프 승리!", "진열대에서 집어 든 핫도그가 \"왈!\" 하고 짖었다.\n사장님은 핫도그를 떨어뜨릴 뻔했다."],
	"time": ["셰프 승리!", "퇴근 시간이다. 강아지는 배가 덜 찬 채로\n트럭 구석에서 잠이 들었다."],
	"full": ["강아지 승리!", "배가 빵빵해진 강아지가 뒷문으로 유유히 빠져나갔다.\n사장님은 아직도 소시지 개수를 세고 있다."],
	"stars": ["강아지 승리!", "손님이 다 떠났다. 오늘 달린 리뷰:\n\"핫도그에서 털 나옴. 별 하나도 아까움.\""],
}

@onready var chef = $Chef
@onready var dog = $Dog
@onready var rack = $Truck/Rack
@onready var markers: Node3D = $Truck/Markers
@onready var hud = $HUD
@onready var cam: Camera3D = $Camera

var time_left := GAME_TIME
var stars := MAX_STARS
var eaten := 0
var over := false
var customers: Array = []
var traces: Array = []
var decoys: Array = []
var stations := {}
var spawn_t := 4.0

func _ready() -> void:
	for st in get_tree().get_nodes_in_group("station"):
		stations[st.kind] = st
	var mode: String = Session.mode
	# watch: AI끼리 (개발용 관전)
	chef.setup(self, mode in ["dog", "watch"], "p2_" if mode == "duo" else "p1_")
	dog.setup(self, mode in ["chef", "watch"], "p1_")
	chef.global_position = markers.get_node("ChefSpawn").global_position
	dog.global_position = markers.get_node("DogSpawn").global_position

	for m in get_tree().get_nodes_in_group("decoy_spot"):
		var h: Node3D = RackScript.new_hotdog()
		$Decoys.add_child(h)
		h.global_position = m.global_position
		h.rotation.y = randf_range(-0.6, 0.6)
		decoys.append(h)
	for i in [0, 4]:
		rack.place(i, RackScript.new_hotdog())
	chef.expected_rack = 2

	cam.look_at_from_position(Vector3(0, 12.5, 8.5), Vector3(0, 0, -0.8))
	if Session.args.has("cam"):  # 개발용: --cam=x,y,z,tx,ty,tz
		var v: PackedFloat64Array = Session.args["cam"].split_floats(",")
		cam.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
	# 화면: 셰프 화면은 레이어 1만, 강아지 화면은 전부 보인다
	match mode:
		"chef":
			cam.cull_mask = 1
		"dog", "watch":
			cam.cull_mask = 1 | 2
		"duo":
			cam.current = false
			hud.setup_split(cam.global_transform)
	hud.setup(self, mode)
	banner({
		"chef": "핫도그를 팔자! 그런데 오늘따라 뭔가 이상하다...",
		"dog": "배고프다... 들키지 말고 소시지 5개를 먹자!",
		"duo": "왼쪽 셰프(방향키) vs 오른쪽 강아지(WASD)",
	}.get(mode, ""))
	# 내비게이션 맵이 준비될 때까지 AI를 한 프레임 멈춘다
	chef.stopped = true
	dog.stopped = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	chef.stopped = false
	dog.stopped = false

func _process(delta: float) -> void:
	if over:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		end_game("time")
		return
	spawn_t -= delta
	if spawn_t <= 0.0:
		spawn_t = randf_range(10.0, 16.0)
		if customers.size() < 3:
			_spawn_customer()
	dog.set_seen(chef.can_see(dog.body_point()))
	hud.refresh()

# ---------------------------------------------------------------- 손님

func _queue_pos(i: int) -> Vector3:
	return markers.get_node("Queue%d" % i).global_position

func customer_exit() -> Vector3:
	return markers.get_node("CustomerOut").global_position

func _spawn_customer() -> void:
	var c = CUSTOMER.instantiate()
	c.game = self
	$Customers.add_child(c)
	c.global_position = customer_exit()
	customers.append(c)
	_reflow()

func _reflow() -> void:
	for i in customers.size():
		customers[i].target = _queue_pos(i)

func front_customer():
	if customers.size() > 0 and customers[0].ready_to_order():
		return customers[0]
	return null

func serve(bitten: bool) -> void:
	var c = customers.pop_front()
	c.serve(bitten)
	_reflow()
	if bitten:
		_lose_star()
		chef.on_complaint()
	else:
		stars = minf(stars + 0.5, MAX_STARS)

func customer_gave_up(c) -> void:
	customers.erase(c)
	_reflow()
	_lose_star()

func _lose_star() -> void:
	stars -= 1.0
	if stars <= 0.0:
		stars = 0.0
		end_game("stars")

# ---------------------------------------------------------------- 흔적, 소리

func add_trace(pos: Vector3, kind: String) -> void:
	var t := Node3D.new()
	$Traces.add_child(t)
	t.global_position = Vector3(pos.x, 0.03, pos.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if kind == "paw":
		t.set_meta("line", "이거... 발자국?")
		t.set_meta("weight", 10.0)
		mat.albedo_color = Color("#c0262a")  # 케첩 발자국
		for off in [Vector3(0, 0, 0.06), Vector3(-0.07, 0, -0.05), Vector3(0, 0, -0.08), Vector3(0.07, 0, -0.05)]:
			_disc(t, off, 0.05 if off.z != 0.06 else 0.08, mat)
		t.rotation.y = dog.body_model.rotation.y
	else:
		t.set_meta("line", ["이 부스러기는 뭐야?", "누가 여기서 뭘 먹었어?"].pick_random())
		t.set_meta("weight", 25.0)
		mat.albedo_color = Color("#8a5a2b")
		for i in 6:
			_disc(t, Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25)), randf_range(0.04, 0.08), mat)
	traces.append(t)

func _disc(parent: Node3D, off: Vector3, r: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.01
	cm.material = mat
	mi.mesh = cm
	mi.position = off
	parent.add_child(mi)

func make_noise(pos: Vector3, radius: float) -> void:
	chef.hear(pos, radius)

func chef_call(pos: Vector3) -> void:
	dog.hear_call(pos)

func nearest_decoy(pos: Vector3, dist: float):
	for d in decoys:
		if Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length() < dist:
			return d
	return null

# ---------------------------------------------------------------- 승패

func catch_dog(how: String) -> void:
	if over:
		return
	dog.caught()
	end_game(how)

func dog_ate() -> void:
	eaten += 1
	if eaten >= EAT_GOAL:
		end_game("full")

func end_game(reason: String) -> void:
	if over:
		return
	over = true
	chef.stop()
	if reason != "grab" and reason != "rack":
		dog.stop()
	var e: Array = ENDINGS[reason]
	print("[end] ", reason, " t=", int(GAME_TIME - time_left), " eaten=", eaten, " stars=", stars)
	hud.show_result(e[0], e[1], e[0].begins_with("셰프"))

func banner(text: String) -> void:
	print("[banner] t=", int(GAME_TIME - time_left), " ", text)
	hud.banner(text)
