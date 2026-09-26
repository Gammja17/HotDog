extends Node3D
## 한 판을 관리한다: 시간, 별점, 먹은 소시지, 손님, 흔적, 소리, 승패, 화면 구성.

const RackScript := preload("res://scripts/rack.gd")
const TutorialScript := preload("res://scripts/tutorial.gd")
const CUSTOMER := preload("res://scenes/customer.tscn")
const SFX := {
	"bark": preload("res://assets/sfx/bark.wav"),
	"yelp": preload("res://assets/sfx/yelp.wav"),
	"sniff": preload("res://assets/sfx/sniff.wav"),
	"chew": preload("res://assets/sfx/chew.wav"),
	"step": [
		preload("res://assets/sfx/footstep_carpet_000.ogg"), preload("res://assets/sfx/footstep_carpet_001.ogg"),
		preload("res://assets/sfx/footstep_carpet_002.ogg"), preload("res://assets/sfx/footstep_carpet_003.ogg"),
	],
}
const GAME_TIME := 180.0
const EAT_GOAL := 5
const SALES_GOAL := 10      # 셰프: 3분 안에 이만큼 팔아야 이긴다
const DOG_CAM_OFFSET := Vector3(0, 10.5, 7.2)  # 강아지 화면 카메라 (강아지를 따라간다)
const WRONG_POKE_STARS := 0.5
const MAX_STARS := 5.0

const ENDINGS := {
	"sold": ["셰프 승리!", "오늘 매출 목표 달성!\n사장님은 트럭 어딘가에서 들리는 킁킁 소리를 못 들은 척하기로 했다."],
	"time": ["강아지 승리!", "퇴근 시간인데 매출이 모자라다.\n사장님이 빈 금고를 보며 한숨 쉬는 사이, 트럭 구석에서 트림 소리가 났다."],
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
var sold := 0
var caught := 0
var over := false
var customers: Array = []
var traces: Array = []
var decoys: Array = []
var stations := {}
var spawn_t := 4.0
var tutorial: Node = null   # 연습 모드일 때만

# 온라인: 방장이 게임을 돌리고 손님에게 상태를 보낸다. 손님은 받은 대로 그린다.
var online := false
var guest := false
var my_role := ""
var snap_n := 0
var snap_t := 0.0
var last_snap = null
var net_fc := false          # 손님 쪽: 창구에 주문 기다리는 손님이 있는지
var net_customers := {}      # 손님 쪽: 손님 id → 인형
var next_customer_id := 1
var in_a := 0
var in_s := 0
var in_b := 0    # 손님 강아지: 짖기 누른 횟수
var in_cg := 0   # 손님 셰프: 초록 칸에서 누른 횟수
var in_cb := 0   # 손님 셰프: 칸 밖에서 누른 횟수
var in_t := 0.0
var last_in := Vector2.ZERO
var last_look := Vector2.ZERO

var fp_cam: Camera3D = null   # 이 화면에서 1인칭 셰프 눈으로 보는 카메라
var follow_cam: Camera3D = null   # 강아지를 따라가는 위쪽 카메라
var eat_spots := {}           # 장터 테이블 자리 → 먹는 손님 (없으면 null)
var base_decoys := 0          # 맵에 처음부터 있던 바닥 핫도그 수 (그 뒤는 손님이 떨어뜨린 것)
var sizzle: AudioStreamPlayer3D
var pan_sausage: Node3D       # 굽는 동안 팬 위에 올라가는 소시지

func _ready() -> void:
	for st in get_tree().get_nodes_in_group("station"):
		stations[st.kind] = st
	var mode: String = Session.mode
	online = mode == "online"
	if online:
		guest = not Net.is_host
		my_role = Net.role
		# 내 캐릭터는 이 키보드로, 상대 캐릭터는 네트워크 입력으로 (손님 쪽은 둘 다 인형)
		chef.setup(self, false, "p1_" if my_role == "chef" else "net_")
		dog.setup(self, false, "p1_" if my_role == "dog" else "net_")
		chef.puppet = guest
		dog.puppet = guest
		Net.message.connect(_on_net_message)
		Net.peer_left.connect(_on_peer_left)
	else:
		# watch: AI끼리 (개발용 관전)
		chef.setup(self, mode in ["dog", "watch", "tut_dog"], "p2_" if mode == "duo" else "p1_")
		dog.setup(self, mode in ["chef", "watch", "tut_chef"], "p1_")
	chef.global_position = markers.get_node("ChefSpawn").global_position
	dog.global_position = markers.get_node("DogSpawn").global_position

	var tilt := [-0.4, 0.3, -0.2, 0.5]  # 온라인 두 화면이 같도록 고정 각도
	for m in get_tree().get_nodes_in_group("decoy_spot"):
		var h: Node3D = RackScript.new_hotdog()
		$Decoys.add_child(h)
		h.global_position = m.global_position
		h.rotation.y = tilt[decoys.size() % tilt.size()]
		h.set_meta("edible", false)  # 바닥에 굴러다니던 건 흙투성이: 숨는 곳일 뿐, 먹지 않는다
		decoys.append(h)
	base_decoys = decoys.size()
	for m in get_tree().get_nodes_in_group("eat_spot"):
		eat_spots[m] = null
	for i in [0, 4]:
		rack.place(i, RackScript.new_hotdog())
	chef.expected_rack = 2

	cam.look_at_from_position(Vector3(0, 11.2, 7.9), Vector3(0, 0, -0.45))
	_setup_audio()
	_tone_down_for_web()
	if Session.args.has("cam"):  # 개발용: --cam=x,y,z,tx,ty,tz
		var v: PackedFloat64Array = Session.args["cam"].split_floats(",")
		cam.look_at_from_position(Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5]))
	# 화면: 셰프 화면은 레이어 1만, 강아지 화면은 전부 보인다
	if online:
		mode = my_role
	# 셰프(사람)는 1인칭: 레이어 1과 8만 본다. 강아지 쪽 화면은 위에서 1, 2, 4 (셰프 몸 = 4)
	match mode:
		"chef", "tut_chef":
			fp_cam = cam
		"dog", "watch", "tut_dog":
			cam.cull_mask = 1 | 2 | 4
			follow_cam = cam
		"duo":
			cam.current = false
			hud.setup_split(cam.global_transform)
			fp_cam = hud.chef_cam()
			follow_cam = hud.dog_cam()
	if fp_cam:
		fp_cam.cull_mask = 1 | 8  # 레이어 8 = 1인칭 셰프 화면에만 보이는 작은 간판
		fp_cam.fov = 72.0
		fp_cam.near = 0.05
		chef.set_look(0.45, -0.2)  # 조리대 쪽을 보고 시작
		hud.enable_fp(chef, mode == "duo")
	if guest and my_role == "chef":
		chef.local_look = true
	hud.setup(self, mode)
	if mode.begins_with("tut_"):
		tutorial = TutorialScript.new()
		add_child(tutorial)
		tutorial.setup(self, mode.trim_prefix("tut_"))
	else:
		banner({
			"chef": "3분 안에 핫도그 10개를 팔자! 그런데 오늘따라 뭔가 이상하다...",
			"dog": "소시지 5개를 먹거나, 사장님이 10개를 못 팔게 방해하자! (Q로 짖으면 손님이 도망간다)",
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
	if fp_cam:
		fp_cam.global_transform = chef.eye.global_transform
	if follow_cam:
		_follow_dog(delta)
	_update_sizzle()
	if guest:
		_guest_process(delta)
		return
	if online:
		snap_t -= delta
		if snap_t <= 0.0:
			snap_t = 1.0 / 15.0
			Net.send(_net_snapshot())
	if over:
		return
	if tutorial == null:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			end_game("time")  # 매출 목표를 못 채웠다
			return
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = randf_range(8.0, 12.0)
			if customers.size() < 3:
				spawn_customer()
	dog.set_seen(chef.can_see(dog.body_point()), chef.fp)
	_update_highlights()
	hud.refresh()

## 사람이 셰프일 때: 지금 든 것을 받는 자리만 빛낸다 (빵을 들면 그릴, 핫도그를 들면 진열대와 창구)
func _update_highlights() -> void:
	var want: Array = []
	var local_chef: bool = not chef.is_ai and (not online or my_role == "chef")
	if local_chef:
		match chef.hand:
			"": want = ["bread"]
			"bun": want = ["grill"]
			"grilled": want = ["sauce"]
			"hotdog": want = ["window"] if has_front_customer() else []
	for k in stations:
		stations[k].set_highlight(k in want)
	rack.set_highlight(local_chef and chef.hand == "hotdog")

# ---------------------------------------------------------------- 손님

func _queue_pos(i: int) -> Vector3:
	if i <= 2:
		return markers.get_node("Queue%d" % i).global_position
	# 줄이 길어지면 셋째 자리 뒤로 이어 선다
	return markers.get_node("Queue2").global_position + Vector3(1.2, 0, -0.4) * (i - 2)

## 가까운 장터 출입구 (동쪽, 서쪽)
func customer_exit(from := Vector3(99, 0, 0)) -> Vector3:
	var a: Vector3 = markers.get_node("CustomerOut").global_position
	var b: Vector3 = markers.get_node("CustomerOut2").global_position
	return a if from.distance_to(a) <= from.distance_to(b) else b

func spawn_customer() -> void:
	var c = CUSTOMER.instantiate()
	c.game = self
	c.net_id = next_customer_id
	next_customer_id += 1
	$Customers.add_child(c)
	c.global_position = customer_exit(Vector3(randf_range(-20, 20), 0, 0))
	customers.append(c)
	_reflow()

func _reflow() -> void:
	for i in customers.size():
		customers[i].target = _queue_pos(i)

func has_front_customer() -> bool:
	return front_customer() != null or net_fc

func front_customer():
	if customers.size() > 0 and customers[0].ready_to_order():
		return customers[0]
	return null

func serve(bitten: bool) -> void:
	var c = customers.pop_front()
	c.serve(bitten)
	_reflow()
	_tut_event("served")
	if bitten:
		_lose_star()
		chef.on_complaint()
	else:
		stars = minf(stars + 0.5, MAX_STARS)
		sold += 1
		if tutorial == null and sold >= SALES_GOAL:
			end_game("sold")

func claim_eat_spot(c) -> Node3D:
	var free: Array = []
	for m in eat_spots:
		if eat_spots[m] == null:
			free.append(m)
	if free.is_empty():
		return null
	var m: Node3D = free.pick_random()
	eat_spots[m] = c
	return m

func release_eat_spot(m: Node3D) -> void:
	if eat_spots.has(m):
		eat_spots[m] = null

func eating_customers() -> Array:
	var out: Array = []
	for c in $Customers.get_children():
		if not c.puppet and c.has_food():
			out.append(c)
	return out

func customers_near(p: Vector3, r: float) -> int:
	var n := 0
	for c in $Customers.get_children():
		if c.state in ["queue", "eating", "to_eat"] and Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < r:
			n += 1
	return n

## 짖기: 근처 손님이 겁먹고, 셰프에게 소리가 들린다
func dog_bark(p: Vector3) -> void:
	_tut_event("bark")
	sfx("bark", p, 4.0, 1.05)
	make_noise(p, 14.0)
	for c in $Customers.get_children():
		if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < 5.0:
			c.scared()

func customer_scared(c) -> void:
	customers.erase(c)
	_reflow()
	chef.on_disturbance(c.global_position)
	_tut_event("scared")

## 강아지가 테이블 손님 핫도그를 뺏어 먹었다
func customer_robbed(c) -> void:
	c.stolen()
	make_noise(c.global_position, 10.0)
	chef.on_disturbance(c.global_position)
	banner("손님 핫도그를 강아지가 뺏어 먹었다! (별점 -0.5)")
	_lose_star(0.5)

## 손님이 떨어뜨린 핫도그: 바닥 핫도그가 하나 늘어난다 (강아지 먹이이자 숨을 곳)
## 연습용: 장터 테이블에서 핫도그를 먹고 있는 손님을 바로 세운다
func spawn_eating_customer(spot_index := 0) -> Node:
	var c = CUSTOMER.instantiate()
	c.game = self
	c.net_id = next_customer_id
	next_customer_id += 1
	$Customers.add_child(c)
	var spot: Node3D = eat_spots.keys()[spot_index % eat_spots.size()]
	eat_spots[spot] = c
	c.eat_spot = spot
	c.global_position = spot.global_position
	c.target = spot.global_position
	c.state = "eating"
	c.eat_t = 999.0
	c.food.visible = true
	return c

func add_decoy(p: Vector3, rot := randf_range(-1.0, 1.0)) -> void:
	var h: Node3D = RackScript.new_hotdog()
	$Decoys.add_child(h)
	h.global_position = Vector3(p.x, 0, p.z)
	h.rotation.y = rot
	h.set_meta("edible", true)  # 방금 떨어뜨린 건 먹을 수 있다
	decoys.append(h)

func _follow_dog(delta: float) -> void:
	var target: Vector3 = dog.global_position if dog.visible else chef.global_position
	target.y = 0
	var want := target + DOG_CAM_OFFSET
	if follow_cam.global_position.distance_to(want) > 25.0:
		follow_cam.global_position = want
	else:
		follow_cam.global_position = follow_cam.global_position.lerp(want, 1.0 - exp(-5.0 * delta))
	follow_cam.look_at(follow_cam.global_position - DOG_CAM_OFFSET, Vector3.UP)

func customer_gave_up(c) -> void:
	customers.erase(c)
	_reflow()
	_lose_star()

## 멀쩡한 핫도그를 찔렀다: 찌그러지고, 보던 손님들이 수군거린다
func wrong_poke(pos: Vector3) -> void:
	var d = nearest_decoy(pos, 0.8)
	if d != null:
		d.scale.y = 0.55
	var c = front_customer()
	if c != null:
		c.say(["방금 핫도그 찌르셨어요...?", "위생 괜찮은 거죠?", "저 핫도그 왜 찔러요?"].pick_random(), 2.2)
	banner("멀쩡한 핫도그를 찔렀다! 손님들이 수군거린다 (별점 -0.5)")
	_lose_star(WRONG_POKE_STARS)

func _lose_star(amount := 1.0) -> void:
	stars -= amount
	if tutorial == null and stars <= 0.0:
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
	if online and not guest:
		Net.send({"k": "tr", "x": pos.x, "z": pos.z, "kind": kind})

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
	_tut_event("noise")

func chef_call(pos: Vector3) -> void:
	dog.hear_call(pos)
	_tut_event("call")

func _tut_event(name: String) -> void:
	if tutorial != null:
		tutorial.event(name)

func nearest_decoy(pos: Vector3, dist: float):
	for d in decoys:
		if Vector2(d.global_position.x - pos.x, d.global_position.z - pos.z).length() < dist:
			return d
	return null

# ---------------------------------------------------------------- 승패

func catch_dog(how: String) -> void:
	if over or dog.stopped or not dog.visible:
		return  # 이미 잡혀서 버둥대거나 던져지는 중
	if tutorial != null:
		dog.caught()
		over = true
		chef.stop()
		_tut_event("caught")
		return
	# 잡기는 승리가 아니다: 먹은 소시지 두 개를 뱉게 하고, 장터로 던진다
	caught += 1
	eaten = maxi(eaten - 2, 0)
	dog.caught()
	if dog.slot >= 0:
		rack.items[dog.slot] = null
		dog.slot = -1
	chef.after_catch()
	banner("강아지를 잡아 밖으로 던졌다! 먹은 소시지 두 개를 뱉어 냈다 (%d번째)" % caught)
	await get_tree().create_timer(0.9).timeout
	if over or not is_inside_tree():
		return
	var land: Vector3 = markers.get_node("DoorOutside").global_position + Vector3(randf_range(2.0, 4.0), 0, randf_range(-2.0, 2.0))
	dog.thrown(land)

func dog_ate() -> void:
	eaten += 1
	_tut_event("ate")
	if tutorial == null and eaten >= EAT_GOAL:
		end_game("full")

func end_game(reason: String) -> void:
	if over:
		return
	over = true
	chef.stop()
	if reason != "grab" and reason != "rack":
		dog.stop()
	if online and not guest:
		Net.send({"k": "end", "r": reason})
	var e: Array = ENDINGS[reason]
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[end] ", reason, " t=", int(GAME_TIME - time_left), " eaten=", eaten, " stars=", stars)
	hud.show_result(e[0], e[1], e[0].begins_with("셰프"))

func banner(text: String) -> void:
	print("[banner] t=", int(GAME_TIME - time_left), " ", text)
	hud.banner(text)
	if online and not guest:
		Net.send({"k": "banner", "t": text})

# ---------------------------------------------------------------- 온라인

func _net_snapshot() -> Dictionary:
	snap_n += 1
	var cs := []
	for c in $Customers.get_children():
		cs.append(c.net_state())
	var rk := []
	for it in rack.items:
		rk.append(0 if it == null else (3 if it == dog else (2 if it.get_meta("bitten") else 1)))
	var dc := []
	for d in decoys:
		dc.append(d.get_meta("bitten"))
	return {
		"k": "snap", "n": snap_n, "tl": time_left, "st": stars, "ea": eaten, "so": sold, "ca": caught, "fc": front_customer() != null,
		"dx": _extra_decoys(),
		"c": chef.net_state(), "d": dog.net_state(), "cu": cs, "rk": rk, "dc": dc,
	}

func _extra_decoys() -> Array:
	var out: Array = []
	for i in range(base_decoys, decoys.size()):
		out.append([decoys[i].global_position.x, decoys[i].global_position.z, decoys[i].rotation.y])
	return out

func _guest_process(delta: float) -> void:
	var s = Net.snapshot
	if s != null and s != last_snap:
		_net_apply(s, last_snap == null)
		last_snap = s
	# 내 입력을 방장에게 보낸다 (버튼은 누른 횟수로 보내서 놓치지 않게)
	var v := Input.get_vector("p1_left", "p1_right", "p1_up", "p1_down")
	if Session.args.has("fake-move"):  # 개발용
		var f: PackedFloat64Array = Session.args["fake-move"].split_floats(",")
		v = Vector2(f[0], f[1])
	var changed := v != last_in
	var look := Vector2.ZERO
	if my_role == "chef":
		if chef.work_left > 0.0:
			chef.look_at_work(delta)  # 방장과 똑같이 조리대만 본다
		look = Vector2(chef.rotation.y, chef.pitch)
		changed = changed or look.distance_to(last_look) > 0.01
	var pressed_act := Input.is_action_just_pressed("p1_act") or (Session.args.has("fake-act") and Engine.get_process_frames() % 60 == 0)
	if my_role == "chef" and chef.cook_kind != "" and chef.work_left > 0.0:
		# 조리 중: 바늘은 이 화면에서 움직이고, 판정도 여기서 해서 결과만 보낸다
		chef.cook_t += delta
		chef.cook_lock -= delta
		chef.cook_needle = pingpong(chef.cook_t * chef.COOK[chef.cook_kind].speed, 1.0)
		if pressed_act and chef.cook_lock <= 0.0:
			chef.cook_lock = chef.COOK_LOCK
			if chef.cook_hit():
				in_cg += 1
			else:
				in_cb += 1
			changed = true
	elif pressed_act:
		in_a += 1
		changed = true
	if Input.is_action_just_pressed("p1_skill"):
		in_s += 1
		changed = true
	if Input.is_action_just_pressed("p1_bark"):
		in_b += 1
		changed = true
	in_t -= delta
	if changed or in_t <= 0.0:
		in_t = 0.05
		last_in = v
		last_look = look
		Net.send({"k": "in", "mx": v.x, "my": v.y, "a": in_a, "s": in_s, "yw": look.x, "pt": look.y, "cg": in_cg, "cb": in_cb, "bk": in_b})
	_update_highlights()
	hud.refresh()

func _net_apply(s: Dictionary, first: bool) -> void:
	time_left = s.tl
	stars = s.st
	eaten = int(s.ea)
	sold = int(s.so)
	caught = int(s.ca)
	net_fc = s.fc
	chef.apply_net(s.c, first)
	dog.apply_net(s.d, first)
	for i in rack.items.size():
		var code := int(s.rk[i])
		var it = rack.items[i]
		var cur := 0 if it == null else (3 if it == dog else (2 if it.get_meta("bitten") else 1))
		if cur == code:
			continue
		var old = rack.take(i)
		if old is Node3D and old != dog:
			old.queue_free()
		if code == 1 or code == 2:
			rack.place(i, RackScript.new_hotdog(code == 2))
		elif code == 3:
			rack.items[i] = dog
	# 손님이 떨어뜨려 새로 생긴 바닥 핫도그
	while decoys.size() < base_decoys + s.dx.size():
		var e: Array = s.dx[decoys.size() - base_decoys]
		add_decoy(Vector3(e[0], 0, e[1]), e[2])
	for i in mini(decoys.size(), s.dc.size()):
		if decoys[i].get_meta("bitten") != s.dc[i]:
			rack.set_bitten(decoys[i], s.dc[i])
	var alive := {}
	for d in s.cu:
		var id := int(d[0])
		alive[id] = true
		var c = net_customers.get(id)
		if c == null:
			c = CUSTOMER.instantiate()
			c.game = self
			c.puppet = true
			c.hue = d[8]
			$Customers.add_child(c)
			c.position = Vector3(d[1], 0, d[2])
			net_customers[id] = c
		c.apply_net(d)
	for id in net_customers.keys():
		if not alive.has(id):
			net_customers[id].queue_free()
			net_customers.erase(id)

func _on_net_message(d: Dictionary) -> void:
	match d.k:
		"tr":
			add_trace(Vector3(d.x, 0, d.z), d.kind)
		"sfx":
			sfx(d.n, Vector3(d.x, d.y, d.z), d.db, d.p, false)
		"banner":
			hud.banner(d.t)
		"end":
			over = true
			var e: Array = ENDINGS[d.r]
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.show_result(e[0], e[1], e[0].begins_with("셰프"))

func _on_peer_left() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	over = true
	chef.stop()
	dog.stop()
	hud.show_left()

# ---------------------------------------------------------------- 1인칭 마우스, 소리, 밝기

func _unhandled_input(event: InputEvent) -> void:
	if fp_cam == null:
		return
	if event is InputEventMouseButton and event.pressed and not over:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # 화면을 클릭하면 마우스로 둘러본다
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 효과음을 그 자리에서 튼다 (방향이 있는 소리). 온라인이면 손님 화면에도 보낸다.
func sfx(name: String, pos: Vector3, db := 0.0, pitch := 1.0, send := true) -> void:
	var s = SFX[name]
	if s is Array:
		s = s.pick_random()
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 3.0
	p.max_distance = 16.0
	$Sfx.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
	if send and online and not guest:
		Net.send({"k": "sfx", "n": name, "x": pos.x, "y": pos.y, "z": pos.z, "db": db, "p": pitch})

func _setup_audio() -> void:
	var holder := Node3D.new()
	holder.name = "Sfx"
	add_child(holder)
	sizzle = AudioStreamPlayer3D.new()
	sizzle.stream = preload("res://assets/sfx/sizzle.wav")
	sizzle.volume_db = -6.0
	sizzle.unit_size = 3.0
	sizzle.max_distance = 14.0
	sizzle.finished.connect(func(): sizzle.play())  # 굽는 동안 계속
	holder.add_child(sizzle)
	sizzle.global_position = stations["grill"].global_position + Vector3(0, 1.0, -0.8)
	pan_sausage = preload("res://assets/food/sausage.glb").instantiate()
	pan_sausage.scale = Vector3.ONE * 0.9
	pan_sausage.visible = false
	holder.add_child(pan_sausage)
	pan_sausage.global_position = Vector3(-3.55, 1.0, -3.3)

## 그릴에서 굽는 동안 지글지글 (손님 화면은 받은 셰프 상태로 판단)
func _update_sizzle() -> void:
	var on: bool = chef.work_kind == "grill" and chef.work_left > 0.0
	# 팬 위 소시지: 굽는 동안 보이고, 잘 누를 때마다 뒤집힌다. 익을수록 살짝 커지며 통통해진다
	pan_sausage.visible = on
	if on:
		pan_sausage.rotation.z = lerp_angle(pan_sausage.rotation.z, PI * chef.cook_flips, 0.3)
		pan_sausage.position.y = 1.0 + (0.06 if absf(angle_difference(pan_sausage.rotation.z, PI * chef.cook_flips)) > 0.3 else 0.0)
		var done: float = 1.0 - chef.work_left / maxf(chef.work_total, 0.01)
		pan_sausage.scale = Vector3.ONE * (0.85 + 0.15 * done)
	if on and not sizzle.playing:
		sizzle.play()
	elif not on and sizzle.playing:
		sizzle.stop()

## 웹(브라우저) 화면은 같은 조명에서도 더 밝게 나와서 한 번 더 낮춘다
func _tone_down_for_web() -> void:
	if not OS.has_feature("web"):
		return
	var env: Environment = $Truck/Env.environment
	env.ambient_light_energy *= 0.6
	$Truck/Sun.light_energy *= 0.62
