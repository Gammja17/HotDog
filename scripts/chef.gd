extends CharacterBody3D
## 셰프. 사람이 조종하거나(is_ai = false) AI가 조종한다.
## 평소에는 핫도그를 만들어 팔고, 흔적을 보면 의심이 쌓이고, 의심이 가득 차면 트럭을 뒤진다.

const RackScript := preload("res://scripts/rack.gd")
const VIEW_RANGE := 6.5
const VIEW_HALF_ANGLE := 45.0
const WORK_TIME := {"bread": 0.8, "grill": 2.0, "sauce": 0.8, "poke": 0.5}
const HAND_TEXT := {"": "빈손", "bun": "빵", "grilled": "소시지 넣은 빵", "hotdog": "핫도그"}

var game: Node
var is_ai := false
var prefix := "p1_"
var speed := 3.6

var hand := ""            # "" / bun / grilled / hotdog
var hand_bitten := false
var facing := Vector3(0, 0, -1)
var call_cd := 0.0
var stopped := false

# 작업(조리, 찌르기) 진행
var work_left := 0.0
var work_total := 0.0
var work_done: Callable

# AI 상태
var mode := "work"        # work / chase / search
var suspicion := 0.0
var expected_rack := 0    # 내가 진열대에 올려 둔 핫도그 수 (늘어나면 수상하다)
var goal_pos := Vector3.ZERO
var goal_action: Callable
var has_goal := false
var think_t := 0.0
var last_seen := Vector3.ZERO
var lost_t := 0.0
var notice_t := 0.0
var search_t := 0.0
var search_list: Array = []
var known_traces := {}
var rack_alarm := false
var idle_turn := 0.0

@onready var model: Node3D = $Model
@onready var agent: NavigationAgent3D = $Agent
@onready var say_label: Label3D = $Say
@onready var bar_label: Label3D = $Bar
@onready var mark_label: Label3D = $Mark
@onready var held: Node3D = $Held
@onready var cone: MeshInstance3D = $Cone
var ap: AnimationPlayer
var say_t := 0.0

func setup(g: Node, ai: bool, input_prefix: String) -> void:
	game = g
	is_ai = ai
	prefix = input_prefix
	speed = 3.0 if ai else 3.8
	mark_label.visible = ai

func _ready() -> void:
	ap = Anim.setup(model)
	Anim.play(ap, "Idle")
	_build_cone()
	bar_label.text = ""
	say_label.text = ""
	mark_label.text = ""

func _build_cone() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	var a0 := deg_to_rad(-VIEW_HALF_ANGLE)
	var a1 := deg_to_rad(VIEW_HALF_ANGLE)
	for i in steps:
		var ta := lerpf(a0, a1, float(i) / steps)
		var tb := lerpf(a0, a1, float(i + 1) / steps)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(tb), 0, -cos(tb)) * VIEW_RANGE)
		st.add_vertex(Vector3(sin(ta), 0, -cos(ta)) * VIEW_RANGE)
	cone.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 0.95, 0.4, 0.13)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material_override = mat
	cone.position.y = 0.04

# ---------------------------------------------------------------- 공용

func say(text: String, t := 2.0) -> void:
	if OS.is_debug_build() and Session.args.has("log"):
		print("[chef] t=%d %s" % [int(game.GAME_TIME - game.time_left), text])
	say_label.text = text
	say_t = t

func can_see(p: Vector3) -> bool:
	var to := p - global_position
	to.y = 0
	var d := to.length()
	if d > VIEW_RANGE:
		return false
	if d > 0.7 and facing.angle_to(to.normalized()) > deg_to_rad(VIEW_HALF_ANGLE):
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.5, 0), p + Vector3(0, 0.3, 0), 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func stop() -> void:
	stopped = true
	velocity = Vector3.ZERO
	work_left = 0.0
	bar_label.text = ""

func set_hand(h: String, bitten := false) -> void:
	hand = h
	hand_bitten = bitten
	for c in held.get_children():
		c.queue_free()
	var m: Node3D
	match h:
		"bun":
			m = load("res://assets/food/bread.glb").instantiate()
			m.scale = Vector3.ONE * 1.4
		"grilled":
			m = load("res://assets/food/hot-dog-raw.glb").instantiate()
			m.scale = Vector3.ONE * 1.0
		"hotdog":
			m = RackScript.new_hotdog(bitten)
			m.scale = Vector3.ONE * 0.75
	if m:
		held.add_child(m)

func _face(dir: Vector3) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	facing = facing.slerp(dir.normalized(), 0.25).normalized()
	rotation.y = atan2(-facing.x, -facing.z)

func _start_work(kind: String, done: Callable) -> void:
	work_total = WORK_TIME[kind]
	work_left = work_total
	work_done = done
	Anim.play(ap, "Working")

func _tick_work(delta: float) -> void:
	work_left -= delta
	var n := int(8.0 * (1.0 - work_left / work_total))
	bar_label.text = "=".repeat(clampi(n, 0, 8)) + "-".repeat(clampi(8 - n, 0, 8))
	if work_left <= 0.0:
		bar_label.text = ""
		work_left = 0.0
		var cb := work_done
		work_done = Callable()
		if cb.is_valid():
			cb.call()

func _near_station(kind: String, dist := 1.3) -> bool:
	var st: Node3D = game.stations.get(kind)
	return st != null and _flat(global_position, st.global_position) < dist

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ---------------------------------------------------------------- 행동 (사람, AI 공용)

## 스페이스 한 번. 상황에 맞는 행동 하나를 한다.
func act() -> void:
	if work_left > 0.0:
		return
	var dog = game.dog
	# 1) 바로 앞에 강아지가 있으면 (숨었든 아니든) 잡는다
	if not dog.in_slot() and _flat(global_position, dog.global_position) < 1.1:
		game.catch_dog("grab")
		return
	var rack = game.rack
	match hand:
		"hotdog":
			if _near_station("window", 1.5) and game.front_customer() != null:
				game.serve(hand_bitten)
				set_hand("")
				return
			var e: int = rack.nearest(global_position, "empty")
			if e >= 0:
				rack.place(e, RackScript.new_hotdog(hand_bitten))
				expected_rack += 1
				set_hand("")
				return
			if not is_ai:
				say("손님이 없네.", 1.2)
		"bun":
			if _near_station("grill"):
				_start_work("grill", func(): set_hand("grilled"))
				return
			say("그릴에 가야지.", 1.2)
		"grilled":
			if _near_station("sauce"):
				_start_work("sauce", func(): set_hand("hotdog"))
				return
			say("소스를 뿌려야지.", 1.2)
		"":
			var f: int = rack.nearest(global_position, "full")
			if f >= 0:
				_take_from_rack(f)
				return
			if _near_station("bread"):
				_start_work("bread", func(): set_hand("bun"))
				return
			var d: Node3D = game.nearest_decoy(global_position, 1.3)
			if d != null:
				_start_work("poke", func(): say("그냥 핫도그네.", 1.2))
				return

## AI용: 정해 둔 칸에 올린다 (그새 찼으면 다른 빈칸)
func _place_in(i: int) -> void:
	var rack = game.rack
	if rack.items[i] != null:
		i = rack.nearest(global_position, "empty", 2.5)
	if i < 0 or hand != "hotdog":
		return
	rack.place(i, RackScript.new_hotdog(hand_bitten))
	expected_rack += 1
	set_hand("")

func _take_from_rack(i: int) -> void:
	var it = game.rack.take(i)
	if it == game.dog:
		game.catch_dog("rack")
		return
	expected_rack = maxi(expected_rack - 1, 0)
	var bitten: bool = it.get_meta("bitten")
	it.queue_free()
	if is_ai and bitten and randf() < 0.6:
		say("누가 이걸 먹었어?!", 2.0)
		_raise(45.0, game.rack.global_position)
		return
	set_hand("hotdog", bitten)

## 스킬: "누가 착한 아이지~?" 숨어 있는 강아지의 꼬리가 들썩인다.
func call_dog() -> void:
	if call_cd > 0.0:
		return
	call_cd = 10.0
	say("누가 착한 아이지~?", 2.2)
	game.chef_call(global_position)

## 소리를 들었다 (강아지가 짖거나 킁킁거림).
func hear(pos: Vector3, radius: float) -> void:
	if _flat(global_position, pos) > radius:
		return
	if is_ai:
		say("방금 무슨 소리지?", 1.6)
		_raise(55.0, pos)

## 손님이 털 나왔다고 항의했다.
func on_complaint() -> void:
	if is_ai:
		_raise(40.0, game.rack.global_position)

# ---------------------------------------------------------------- 매 프레임

func _physics_process(delta: float) -> void:
	if say_t > 0.0:
		say_t -= delta
		if say_t <= 0.0:
			say_label.text = ""
	call_cd = maxf(call_cd - delta, 0.0)
	if stopped:
		return
	if is_ai:
		_ai(delta)
	else:
		_player(delta)

func _player(delta: float) -> void:
	var v := Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
	var dir := Vector3(v.x, 0, v.y)
	if work_left > 0.0:
		if dir.length() > 0.1:
			work_left = 0.0
			bar_label.text = ""
			work_done = Callable()
		else:
			_tick_work(delta)
			velocity = Vector3.ZERO
			return
	velocity = dir * speed
	move_and_slide()
	if dir.length() > 0.1:
		_face(dir)
		Anim.play(ap, "Walk", 1.3)
	else:
		Anim.play(ap, "Idle")
	if Input.is_action_just_pressed(prefix + "act"):
		act()
	if Input.is_action_just_pressed(prefix + "skill"):
		call_dog()

# ---------------------------------------------------------------- AI

func _ai(delta: float) -> void:
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.15
		_perceive(0.15)
		if mode == "work":
			suspicion = maxf(suspicion - 1.5 * 0.15, 0.0)
			if suspicion >= 100.0:
				_start_search()
	_update_mark()

	if work_left > 0.0:
		_tick_work(delta)
		velocity = Vector3.ZERO
		return

	match mode:
		"chase":
			var dog = game.dog
			if _flat(global_position, dog.global_position) < 0.9 and not dog.in_slot():
				game.catch_dog("grab")
				return
			_move_to(last_seen, 3.9, delta)
			if lost_t > 0.9:
				mode = "search"
				search_t = 12.0
				_build_search_list(last_seen)
				say("어디 갔지...?", 1.6)
		"search":
			search_t -= delta
			if search_t <= 0.0:
				_end_search()
				return
			if not has_goal:
				_next_search_goal()
			_follow_goal(delta, 3.4)
		"work":
			if not has_goal:
				_plan_work()
			_follow_goal(delta, speed)

func _move_to(p: Vector3, spd: float, _delta: float) -> bool:
	agent.target_position = p
	if _flat(global_position, p) < 0.5:
		velocity = Vector3.ZERO
		Anim.play(ap, "Idle")
		return true
	var nxt := agent.get_next_path_position()
	var dir := nxt - global_position
	dir.y = 0
	if dir.length() < 0.05:
		dir = p - global_position
		dir.y = 0
	dir = dir.normalized()
	velocity = dir * spd
	move_and_slide()
	_face(dir)
	Anim.play(ap, "Run" if spd > 3.5 else "Walk", 1.2)
	return false

func _set_goal(p: Vector3, action: Callable) -> void:
	goal_pos = p
	goal_action = action
	has_goal = true

func _follow_goal(delta: float, spd: float) -> void:
	if not has_goal:
		_look_around(delta)
		return
	var close := _flat(global_position, goal_pos) < 1.0
	if not close:
		agent.target_position = goal_pos
		close = agent.is_navigation_finished() and _flat(global_position, goal_pos) < 1.6
	if close:
		velocity = Vector3.ZERO
		_face(goal_pos - global_position)
		has_goal = false
		var cb := goal_action
		goal_action = Callable()
		if cb.is_valid():
			cb.call()
		return
	_move_to(goal_pos, spd, delta)

func _look_around(delta: float) -> void:
	idle_turn += delta
	_face(Vector3(sin(idle_turn * 0.8), 0, -cos(idle_turn * 0.8)))
	Anim.play(ap, "Idle")

func _station_pos(kind: String) -> Vector3:
	return game.stations[kind].global_position

func _rack_stand(i: int) -> Vector3:
	var p: Vector3 = game.rack.slot_pos(i)
	# 진열대 앞쪽(카메라 쪽)이나 뒤쪽 중 가까운 쪽에 선다
	var front := Vector3(p.x, 0, 1.65)
	var back := Vector3(p.x, 0, -0.45)
	return front if _flat(global_position, front) < _flat(global_position, back) else back

func _plan_work() -> void:
	var rack = game.rack
	match hand:
		"hotdog":
			if game.front_customer() != null:
				_set_goal(_station_pos("window"), act)
			elif rack.has_empty():
				var e: int = rack.nearest(global_position, "empty", 99.0)
				_set_goal(_rack_stand(e), func(): _place_in(e))
			else:
				_set_goal(_station_pos("window"), func(): pass)
		"bun":
			_set_goal(_station_pos("grill"), act)
		"grilled":
			_set_goal(_station_pos("sauce"), act)
		"":
			if game.front_customer() != null and rack.count_items() > 0:
				var full := []
				for i in rack.items.size():
					if rack.items[i] != null:
						full.append(i)
				var pick: int = full.pick_random()
				_set_goal(_rack_stand(pick), func():
					if rack.items[pick] != null:
						_take_from_rack(pick)
				)
			elif expected_rack < 4:
				_set_goal(_station_pos("bread"), act)
			else:
				has_goal = false

## 눈으로 본 것을 처리한다.
func _perceive(dt: float) -> void:
	var dog = game.dog
	var dpos: Vector3 = dog.global_position
	var sees: bool = can_see(dog.body_point())
	if not dog.hidden and sees:
		if mode != "chase":
			say("야! 거기 너!!", 1.6)
			work_left = 0.0
			bar_label.text = ""
			has_goal = false
		mode = "chase"
		suspicion = 100.0
		last_seen = dpos
		lost_t = 0.0
	elif mode == "chase":
		lost_t += dt
		if dog.hidden and sees:
			# 눈앞에서 핫도그로 변신했다: 그 자리를 찌른다
			mode = "search"
			search_t = 10.0
			search_list = [dpos]
			has_goal = false

	# 숨은 강아지가 이상한 곳에 있거나 꼬리를 흔들면 눈치챈다
	if dog.hidden and not dog.in_slot() and sees and mode != "chase":
		var d := _flat(global_position, dpos)
		var odd: bool = game.nearest_decoy(dpos, 1.0) == null
		if (odd and d < 5.0) or (dog.tail > 55.0 and d < 4.0):
			notice_t += dt
			if notice_t > (0.8 if odd else 1.2):
				notice_t = 0.0
				say("저 핫도그... 원래 저기 있었나?", 1.8)
				_poke_here(dpos)
		else:
			notice_t = maxf(notice_t - dt, 0.0)

	# 진열대 핫도그가 내가 올린 것보다 많다
	var rack = game.rack
	if rack.count_items() > expected_rack and can_see(rack.global_position + Vector3(0, 0.6, 0)) \
			and _flat(global_position, rack.global_position) < 5.0:
		if not rack_alarm:
			rack_alarm = true
			say("핫도그가... 하나 늘었네?", 1.8)
			_raise(50.0, rack.global_position)
	elif rack.count_items() <= expected_rack:
		rack_alarm = false

	# 흔적
	for t in game.traces:
		if not is_instance_valid(t) or known_traces.has(t.get_instance_id()):
			continue
		if can_see(t.global_position):
			known_traces[t.get_instance_id()] = true
			if say_t <= 0.0:
				say(t.get_meta("line", "이게 뭐지?"), 1.6)
			_raise(t.get_meta("weight", 25.0), t.global_position)

func _raise(amount: float, clue: Vector3) -> void:
	suspicion = minf(suspicion + amount, 100.0)
	last_seen = clue

func _poke_here(p: Vector3) -> void:
	work_left = 0.0
	mode = "search" if mode == "work" else mode
	if search_t <= 0.0:
		search_t = 8.0
	search_list.push_front(p)
	has_goal = false

func _start_search() -> void:
	mode = "search"
	search_t = 14.0
	has_goal = false
	work_left = 0.0
	bar_label.text = ""
	_build_search_list(last_seen)
	game.banner("영업 일시 중지! 사장님이 트럭을 뒤지기 시작했다")
	say("분명 뭔가 있어...", 2.0)

func _build_search_list(center: Vector3) -> void:
	var cands: Array = []
	for d in game.decoys:
		if _flat(d.global_position, center) < 5.0:
			cands.append(d.global_position)
	var rack = game.rack
	if _flat(rack.global_position, center) < 5.0:
		for i in rack.items.size():
			if rack.items[i] != null:
				cands.append(rack.slot_pos(i))
	for m in get_tree().get_nodes_in_group("hide_spot"):
		if _flat(m.global_position, center) < 4.0:
			cands.append(m.global_position)
	cands.sort_custom(func(a, b): return _flat(a, center) < _flat(b, center))
	search_list = cands.slice(0, 5)
	search_list.push_front(center)

func _next_search_goal() -> void:
	if search_list.is_empty():
		_end_search()
		return
	var p: Vector3 = search_list.pop_front()
	var stand := p
	var rack = game.rack
	var on_rack: bool = _flat(p, rack.global_position) < 1.6 and p.y > 0.5
	if on_rack:
		stand = Vector3(p.x, 0, 1.65) if global_position.z > 0.6 else Vector3(p.x, 0, -0.45)
	_set_goal(stand, func(): _search_at(p))

func _search_at(p: Vector3) -> void:
	if call_cd <= 0.0 and randf() < 0.5:
		call_dog()
	_start_work("poke", func(): _poke_result(p))

func _poke_result(p: Vector3) -> void:
	var dog = game.dog
	if Vector2(dog.global_position.x - p.x, dog.global_position.z - p.z).length() < 1.2:
		if dog.in_slot():
			game.catch_dog("rack")
		elif _flat(global_position, dog.global_position) < 1.8:
			game.catch_dog("grab")
		return
	say(["그냥 핫도그네.", "여긴 아니야.", "음... 기분 탓인가."].pick_random(), 1.2)

func _end_search() -> void:
	mode = "work"
	suspicion = 35.0
	search_list.clear()
	has_goal = false
	game.banner("사장님이 다시 장사를 시작했다")

func _update_mark() -> void:
	if mode == "chase":
		mark_label.text = "!!"
		mark_label.modulate = Color(1, 0.25, 0.2)
	elif mode == "search":
		mark_label.text = "?!"
		mark_label.modulate = Color(1, 0.6, 0.2)
	elif suspicion > 25.0:
		mark_label.text = "?"
		mark_label.modulate = Color(1, 1, 0.4).lerp(Color(1, 0.5, 0.2), suspicion / 100.0)
	else:
		mark_label.text = ""
