extends CharacterBody3D
## 강아지. 사람이 조종하거나(is_ai = false) AI가 조종한다.
## 핫도그로 변장해 숨고, 몰래 소시지를 먹는다. 본능(킁킁, 꼬리)을 못 참으면 들킨다.

const SNIFF_RANGE := 2.4
const EAT_TIME := {"rack": 1.5, "decoy": 1.5, "fridge": 2.2, "customer": 1.5}
const BARK_CD := 12.0
const FRIDGE_STOCK := 3

var game: Node
var is_ai := true
var prefix := "p1_"
var speed := 4.0

var hidden := false
var slot := -1              # 진열대 칸에 숨었으면 칸 번호
var sniff := 0.0            # 0~100. 숨은 채로 음식 옆에 있으면 오른다
var tail := 0.0             # 0~100. "착한 아이지~?"를 들으면 오른다
var tail_pending := 0.0
var revealed_t := 0.0       # 짖은 뒤 잠깐 셰프 눈에도 보인다
var fridge_left := FRIDGE_STOCK
var bark_cd := 0.0
var stopped := false
var seen := false

var eat_left := 0.0
var eat_done: Callable
var paw_t := 0.0
var paw_left := 0

# AI
var think_t := 0.0
var ai_goal := Vector3.ZERO
var ai_has_goal := false
var ai_goal_action: Callable
var ai_hide_t := 0.0
var mash_t := 0.0
var ai_start_t := 5.0       # 처음 몇 초는 트럭 안 눈치를 본다

# 연습(튜토리얼)용
var scripted := false       # AI가 스스로 움직이지 않는다
var calm_sniff := false     # 킁킁 게이지가 차도 터지지 않는다
var calm_tail := false      # 꼬리 게이지가 차도 터지지 않는다

# 온라인 손님 쪽: 방장이 보낸 상태를 그대로 보여 주기만 한다
var puppet := false

@onready var body_model: Node3D = $Model
@onready var disguise: Node3D = $Disguise
@onready var tail_node: Node3D = $Disguise/Tail
@onready var shape: CollisionShape3D = $Shape
@onready var agent: NavigationAgent3D = $Agent
@onready var say_label: Label3D = $Say
@onready var me_label: Label3D = $Me
@onready var bar_label: Label3D = $Bar
var ap: AnimationPlayer
var say_t := 0.0
var wiggle := 0.0

func setup(g: Node, ai: bool, input_prefix: String) -> void:
	game = g
	is_ai = ai
	prefix = input_prefix
	speed = 3.6 if ai else 4.0

func _ready() -> void:
	ap = Anim.setup(body_model)
	Anim.play(ap, "Idle")
	disguise.visible = false
	say_label.text = ""
	bar_label.text = ""
	set_seen(false)

func in_slot() -> bool:
	return slot >= 0

func body_point() -> Vector3:
	return global_position + Vector3(0, 0.3, 0)

## loud면 셰프 화면에도 보인다 (짖는 소리). 아니면 강아지 화면에만.
func say(text: String, t := 1.5, loud := false) -> void:
	if OS.is_debug_build() and Session.args.has("log"):
		print("[dog] t=%d %s" % [int(game.GAME_TIME - game.time_left), text])
	say_label.text = text
	say_label.layers = 1 | 2 if loud else 2
	say_t = t

func stop() -> void:
	stopped = true
	velocity = Vector3.ZERO
	eat_left = 0.0
	bar_label.text = ""

## 셰프 눈에 보이는지에 따라 몸의 렌더 레이어를 바꾼다.
## 레이어 1: 셰프 화면에도 보임 / 레이어 2: 강아지 화면에만 보임
func set_seen(v: bool, always_visible := false) -> void:
	v = v or revealed_t > 0.0
	seen = v
	# 1인칭 셰프는 눈앞에 보이는 대로 그리면 되니 늘 보이게 둔다
	var layer := 1 | 2 if (v or always_visible) else 2
	for m in body_model.find_children("*", "VisualInstance3D", true, false):
		m.layers = layer

## 붙잡혔을 때 연출: 집게에 들려 공중에서 버둥댄다.
func caught() -> void:
	stop()
	revealed_t = 99.0
	_unhide_visual()
	set_seen(true)
	say("깨갱!!", 99.0, true)
	game.sfx("yelp", global_position, 2.0, 1.25)
	Anim.play(ap, "Jump_Loop")
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y + 1.6, 0.35).set_trans(Tween.TRANS_BACK)

## 쫓겨났다가 뒷문으로 다시 들어온다
func respawn(at: Vector3, line := "(슬금슬금...)") -> void:
	stopped = false
	visible = true
	hidden = false
	slot = -1
	shape.disabled = false
	body_model.visible = true
	disguise.visible = false
	sniff = 0.0
	tail = 0.0
	tail_pending = 0.0
	revealed_t = 0.0
	eat_left = 0.0
	eat_done = Callable()
	bar_label.text = ""
	global_position = at
	say(line, 2.0)
	ai_has_goal = false
	ai_start_t = 3.0
	Anim.play(ap, "Idle")

# ---------------------------------------------------------------- 숨기

func toggle_hide() -> void:
	if eat_left > 0.0:
		return
	if hidden:
		unhide()
	else:
		hide_now()

func hide_now() -> void:
	hidden = true
	velocity = Vector3.ZERO
	var s: int = game.rack.nearest(global_position, "empty", 1.4)
	if s >= 0:
		slot = s
		game.rack.place(s, self)
		shape.disabled = true
		var tw := create_tween()
		tw.tween_property(self, "global_position", game.rack.slot_pos(s), 0.2)
	body_model.visible = false
	disguise.visible = true
	disguise.rotation.y = 0.0 if slot >= 0 else randf_range(-0.5, 0.5)
	Anim.play(ap, "Idle")

func unhide() -> void:
	if slot >= 0:
		game.rack.take(slot)
		var p: Vector3 = game.rack.slot_pos(slot)
		# 셰프에게서 먼 쪽으로 뛰어내린다
		var front := Vector3(p.x, 0, 1.6)
		var back := Vector3(p.x, 0, -0.4)
		var chef_p: Vector3 = game.chef.global_position
		var to := front if front.distance_to(chef_p) > back.distance_to(chef_p) else back
		slot = -1
		shape.disabled = false
		var tw := create_tween()
		tw.tween_property(self, "global_position", to, 0.2)
	_unhide_visual()

func _unhide_visual() -> void:
	hidden = false
	body_model.visible = true
	disguise.visible = false

# ---------------------------------------------------------------- 먹기

## 가까운 먹을 것. {kind, pos, target}
func _food_near(dist := 1.4) -> Dictionary:
	# 손님 손에 든 핫도그가 먼저 (바로 옆 바닥 핫도그보다 탐난다)
	for c in game.eating_customers():
		if _flat(global_position, c.global_position) < dist:
			return {"kind": "customer", "pos": c.global_position, "target": c}
	var rack = game.rack
	var s: int = rack.nearest(global_position, "hotdog", dist)
	if s >= 0:
		return {"kind": "rack", "pos": rack.slot_pos(s), "target": s}
	for d in game.decoys:
		if d.get_meta("edible", false) and not d.get_meta("bitten") and _flat(global_position, d.global_position) < dist - 0.2:
			return {"kind": "decoy", "pos": d.global_position, "target": d}
	var fr: Node3D = game.stations["fridge"]
	if fridge_left > 0 and _flat(global_position, fr.global_position) < dist + 0.1:
		return {"kind": "fridge", "pos": fr.global_position, "target": null}
	return {}

func try_eat() -> void:
	if hidden or eat_left > 0.0:
		return
	var f := _food_near()
	if f.is_empty():
		return
	eat_left = EAT_TIME[f.kind]
	velocity = Vector3.ZERO
	_face(f.pos - global_position)
	Anim.play(ap, "Idle_Eating")
	game.sfx("chew", global_position, -3.0, randf_range(0.95, 1.1))
	eat_done = func(): _finish_eat(f)

func _finish_eat(f: Dictionary) -> void:
	var rack = game.rack
	match f.kind:
		"rack":
			var it = rack.items[f.target]
			if not (it is Node3D and it.has_meta("hotdog")) or it.get_meta("bitten"):
				return
			rack.set_bitten(it, true)
		"decoy":
			rack.set_bitten(f.target, true)
		"fridge":
			fridge_left -= 1
		"customer":
			if not is_instance_valid(f.target) or not f.target.has_food():
				return
			game.customer_robbed(f.target)
	game.add_trace(global_position + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2)), "crumbs")
	paw_left = 5
	paw_t = 0.0
	say("냠!", 0.8)
	game.dog_ate()

func _tick_eat(delta: float) -> void:
	eat_left -= delta
	bar_label.text = "냠" + ".".repeat(int(Time.get_ticks_msec() / 200) % 4)
	if eat_left <= 0.0:
		eat_left = 0.0
		bar_label.text = ""
		var cb := eat_done
		eat_done = Callable()
		if cb.is_valid():
			cb.call()

func _cancel_eat() -> void:
	eat_left = 0.0
	bar_label.text = ""
	eat_done = Callable()

# ---------------------------------------------------------------- 본능

func hear_call(pos: Vector3) -> void:
	if _flat(global_position, pos) < 6.0:
		if hidden:
			tail_pending += 130.0  # 가만있으면 "왈!". E를 세 번쯤 연타해야 참는다
		else:
			say("(움찔)", 1.0)

func _instincts(delta: float) -> void:
	var near_food := false
	if hidden:
		near_food = _smells_food()
	sniff = clampf(sniff + (14.0 if near_food else -20.0) * delta, 0.0, 100.0)
	var rise := minf(tail_pending, 100.0 * delta)
	tail_pending -= rise
	tail = clampf(tail + rise - 6.0 * delta, 0.0, 100.0)
	if not hidden:
		tail = maxf(tail - 20.0 * delta, 0.0)
	if calm_sniff:
		sniff = minf(sniff, 95.0)
	if calm_tail:
		tail = minf(tail, 95.0)
	if hidden and tail >= 100.0:
		_burst("왈!!", 12.0)
	elif hidden and sniff >= 100.0:
		_burst("킁킁킁!", 6.0)

func _smells_food() -> bool:
	var rack = game.rack
	for i in rack.items.size():
		var it = rack.items[i]
		if it is Node3D and it.has_meta("hotdog") and not it.get_meta("bitten") \
				and _flat(global_position, rack.slot_pos(i)) < SNIFF_RANGE:
			return true
	for d in game.decoys:
		if d.get_meta("edible", false) and not d.get_meta("bitten") and _flat(global_position, d.global_position) < SNIFF_RANGE:
			return true
	var fr: Node3D = game.stations["fridge"]
	if fridge_left > 0 and _flat(global_position, fr.global_position) < SNIFF_RANGE:
		return true
	var chef = game.chef
	if chef.work_left > 0.0 and chef._near_station("grill") and _flat(global_position, game.stations["grill"].global_position) < 3.0:
		return true
	return false

func _burst(text: String, radius: float) -> void:
	unhide()
	sniff = 30.0
	tail = 0.0
	tail_pending = 0.0
	revealed_t = 2.0
	say(text, 1.6, true)
	if radius > 8.0:
		game.sfx("bark", global_position, 3.0, 1.1)
	else:
		game.sfx("sniff", global_position, 3.0, 1.2)
	game.make_noise(global_position, radius)

## 짖기 (Q): 근처 손님이 겁먹는다. 줄 선 손님은 떠나고(매출 손해), 먹던 손님은 핫도그를 떨어뜨린다.
## 대신 크게 짖으니 셰프에게 위치가 들린다.
func bark() -> void:
	if bark_cd > 0.0 or hidden or eat_left > 0.0 or stopped:
		return
	bark_cd = BARK_CD
	say("왈왈!!", 1.4, true)
	game.dog_bark(global_position)

## 셰프가 뒷문 밖으로 나와 "저리 가!": 가까이 있던 강아지는 멀리 달아난다 (AI), 사람은 말풍선만
func shooed(from: Vector3) -> void:
	if _flat(global_position, from) > 6.0 or stopped:
		return
	say("(움찔!)", 1.2)
	if is_ai and not hidden:
		_ai_go_hide(game.chef)

## 잡혀서 장터로 던져진다. 잠깐 어질어질하다가 다시 움직인다
func thrown(to: Vector3) -> void:
	var tw := create_tween()
	tw.tween_property(self, "global_position", global_position.lerp(to, 0.5) + Vector3(0, 2.2, 0), 0.35)
	tw.tween_property(self, "global_position", to, 0.35)
	await tw.finished
	say("(어질어질...)", 2.0, true)
	await get_tree().create_timer(2.0).timeout
	if game.over:
		return
	respawn(to, "(슬금슬금...)")

## 꼬리 참기: 숨어 있을 때 E 연타
func hold_tail() -> void:
	tail = maxf(tail - 9.0, 0.0)
	tail_pending = maxf(tail_pending - 9.0, 0.0)

# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if say_t > 0.0:
		say_t -= delta
		if say_t <= 0.0:
			say_label.text = ""
	# 꼬리 흔들기: 꼬리 게이지가 높을수록 크게 흔든다 (눈썰미 좋은 셰프는 알아챈다)
	wiggle += delta * 14.0
	var amp := 0.0
	if tail > 20.0:
		amp = (tail - 20.0) / 80.0 * 0.9
	tail_node.rotation.y = sin(wiggle) * amp
	me_label.visible = hidden and not is_ai
	$Ring.visible = not is_ai

func _physics_process(delta: float) -> void:
	if stopped or puppet:
		return
	revealed_t = maxf(revealed_t - delta, 0.0)
	bark_cd = maxf(bark_cd - delta, 0.0)
	_instincts(delta)
	_paws(delta)
	_sounds(delta)
	if eat_left > 0.0:
		_tick_eat(delta)
		if not is_ai and _move_input().length() > 0.1:
			_cancel_eat()
		return
	if is_ai:
		_ai(delta)
	else:
		_player()

func _player() -> void:
	if _pressed("bark"):
		bark()
	if _pressed("act"):
		toggle_hide()
	if _pressed("skill"):
		if hidden:
			hold_tail()
		else:
			try_eat()
	if hidden:
		velocity = Vector3.ZERO
		return
	var v := _move_input()
	var dir := Vector3(v.x, 0, v.y)
	velocity = dir * speed
	move_and_slide()
	if dir.length() > 0.1:
		_face(dir)
		Anim.play(ap, "Run", 1.2)
	else:
		Anim.play(ap, "Idle")

## 입력: 이 컴퓨터 키보드(p1_/p2_) 또는 온라인 손님(net_)
func _move_input() -> Vector2:
	if prefix == "net_":
		return Net.remote_move
	return Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")

func _pressed(action: String) -> bool:
	if prefix == "net_":
		return Net.consume(action)
	return Input.is_action_just_pressed(prefix + action)

func _face(dir: Vector3) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	body_model.rotation.y = lerp_angle(body_model.rotation.y, atan2(dir.x, dir.z), 0.3)

## 발소리(달릴 때)와 참는 콧소리(숨어서 킁킁 게이지가 찰 때). 1인칭 셰프는 소리로 등 뒤를 안다.
var _step_t := 0.0
var _sniff_t := 2.0
func _sounds(delta: float) -> void:
	_step_t -= delta
	if not hidden and velocity.length() > 0.5 and _step_t <= 0.0:
		_step_t = 0.26
		game.sfx("step", global_position, -4.0, randf_range(1.6, 1.9))
	_sniff_t -= delta
	if hidden and sniff > 40.0 and _sniff_t <= 0.0:
		_sniff_t = randf_range(1.2, 2.6) * (1.6 - sniff / 100.0)
		game.sfx("sniff", global_position, -12.0 + sniff / 100.0 * 10.0, 1.35)

func _paws(delta: float) -> void:
	if paw_left <= 0 or hidden:
		return
	paw_t -= delta
	if paw_t <= 0.0 and velocity.length() > 0.5:
		paw_t = 0.45
		paw_left -= 1
		game.add_trace(global_position, "paw")

# ---------------------------------------------------------------- 온라인

func net_state() -> Dictionary:
	return {
		"p": [global_position.x, global_position.y, global_position.z], "mr": body_model.rotation.y,
		"a": ap.get_meta("cur", ["Idle", 1.0]) if ap else ["Idle", 1.0],
		"hd": hidden, "sl": slot, "dr": disguise.rotation.y, "tl": tail, "sn": sniff,
		"sy": say_label.text, "sl2": say_label.layers, "b": bar_label.text, "seen": seen, "v": visible,
	}

func apply_net(d: Dictionary, snap: bool) -> void:
	var p := Vector3(d.p[0], d.p[1], d.p[2])
	global_position = p if snap else global_position.lerp(p, 0.35)
	body_model.rotation.y = lerp_angle(body_model.rotation.y, d.mr, 1.0 if snap else 0.35)
	Anim.play(ap, d.a[0], d.a[1])
	hidden = d.hd
	slot = d.sl
	body_model.visible = not hidden
	disguise.visible = hidden
	disguise.rotation.y = d.dr
	tail = d.tl
	sniff = d.sn
	say_label.text = d.sy
	say_label.layers = int(d.sl2)
	bar_label.text = d.b
	visible = d.v
	set_seen(d.seen)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ---------------------------------------------------------------- AI

func _ai(delta: float) -> void:
	var chef = game.chef
	if scripted:
		velocity = Vector3.ZERO
		return
	if ai_start_t > 0.0:
		ai_start_t -= delta
		Anim.play(ap, "Idle")
		return
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.2
		_ai_think(chef)
	if hidden:
		velocity = Vector3.ZERO
		# 꼬리가 들썩이면 참아 본다 (가끔 실패한다)
		mash_t -= delta
		if tail > 40.0 and mash_t <= 0.0:
			mash_t = 0.22
			if randf() < 0.75:
				hold_tail()
		return
	if ai_has_goal:
		agent.target_position = ai_goal
		if _flat(global_position, ai_goal) < 0.7 or (agent.is_navigation_finished() and _flat(global_position, ai_goal) < 1.5):
			ai_has_goal = false
			velocity = Vector3.ZERO
			var cb := ai_goal_action
			ai_goal_action = Callable()
			if cb.is_valid():
				cb.call()
			return
		var nxt := agent.get_next_path_position()
		var dir := nxt - global_position
		dir.y = 0
		dir = dir.normalized()
		var fleeing: bool = chef.mode == "chase"
		velocity = dir * (speed + (0.7 if fleeing else 0.0))
		move_and_slide()
		_face(dir)
		Anim.play(ap, "Run", 1.4 if fleeing else 1.1)
	else:
		Anim.play(ap, "Idle")

func _ai_set_goal(p: Vector3, action := Callable()) -> void:
	ai_goal = p
	ai_goal_action = action
	ai_has_goal = true

func _ai_think(chef) -> void:
	var seen_now: bool = chef.can_see(body_point())
	if hidden:
		ai_hide_t -= 0.2
		var chef_far: bool = _flat(global_position, chef.global_position) > 3.0
		if sniff > 75.0 and not seen_now:
			unhide()
			_ai_go_hide(chef)
		elif ai_hide_t <= 0.0 and not seen_now and chef_far and chef.mode != "chase":
			unhide()
		return
	if eat_left > 0.0:
		return
	# 셰프가 보고 있거나 쫓아오면: 시야 밖이면 숨고, 아니면 도망
	if chef.mode == "chase" or seen_now:
		if seen_now and chef.mode != "chase" and randf() < 0.7:
			hide_now()
			ai_hide_t = randf_range(4.0, 8.0)
			return
		# 시야에서 벗어나도 바로 숨지 않고 먼 구석까지 달린다 (도착하면 숨는다)
		if not ai_has_goal:
			_ai_go_hide(chef)
		return
	# 셰프가 트럭 안에 있고 근처에 손님이 몰려 있으면 짖어서 쫓아 버린다
	if bark_cd <= 0.0 and chef.in_truck(chef.global_position) and game.customers_near(global_position, 5.0) >= 2 and randf() < 0.5:
		bark()
	if ai_has_goal:
		return
	# 먹을 것 고르기: 셰프에게서 멀고 셰프 등 뒤인 것
	var food := _ai_pick_food(chef)
	if food.is_empty():
		_ai_go_hide(chef)
		return
	_ai_set_goal(food.stand, func():
		try_eat()
		if eat_left <= 0.0:
			_ai_go_hide(chef)
		else:
			var prev := eat_done
			eat_done = func():
				prev.call()
				_ai_go_hide(chef)
	)

func _ai_pick_food(chef) -> Dictionary:
	var opts: Array = []
	var rack = game.rack
	for i in rack.items.size():
		var it = rack.items[i]
		if it is Node3D and it.has_meta("hotdog") and not it.get_meta("bitten"):
			var p: Vector3 = rack.slot_pos(i)
			var stand := Vector3(p.x, 0, 1.55) if chef.global_position.z < 0.6 else Vector3(p.x, 0, -0.35)
			opts.append({"stand": stand, "pos": p})
	for d in game.decoys:
		if d.get_meta("edible", false) and not d.get_meta("bitten"):
			opts.append({"stand": d.global_position + Vector3(0.5, 0, 0.3), "pos": d.global_position})
	if fridge_left > 0:
		var fr: Vector3 = game.stations["fridge"].global_position
		opts.append({"stand": fr, "pos": fr})
	for c in game.eating_customers():
		opts.append({"stand": c.global_position + Vector3(0.6, 0, 0.5), "pos": c.global_position})
	var best := {}
	var best_score := -INF
	for o in opts:
		var d: float = _flat(o.pos, chef.global_position)
		if d < 2.5:
			continue
		var score := d - _flat(o.stand, global_position) * 0.4 + randf() * 2.0
		if chef.can_see(o.pos):
			score -= 4.0
		if score > best_score:
			best_score = score
			best = o
	return best

func _ai_go_hide(chef) -> void:
	var spots: Array = []
	for m in get_tree().get_nodes_in_group("hide_spot"):
		spots.append(m.global_position)
	var rack = game.rack
	if _flat(chef.global_position, rack.global_position) > 4.0:
		var e: int = rack.nearest(global_position, "empty", 99.0)
		if e >= 0:
			var p: Vector3 = rack.slot_pos(e)
			spots.append(Vector3(p.x, 0, 1.55 if global_position.z > 0.6 else -0.35))
	var best: Vector3 = spots[0]
	var best_score := -INF
	for s in spots:
		var score: float = _flat(s, chef.global_position) - _flat(s, global_position) * 0.3 + randf()
		if score > best_score:
			best_score = score
			best = s
	_ai_set_goal(best, func():
		if not chef.can_see(body_point()) or chef.mode != "chase":
			hide_now()
			ai_hide_t = randf_range(5.0, 11.0)
	)
