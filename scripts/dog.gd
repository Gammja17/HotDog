extends CharacterBody3D
## 강아지. 사람이 조종하거나(is_ai = false) AI가 조종한다.
## 핫도그로 변장해 숨고, 몰래 소시지를 먹는다. 본능(킁킁, 꼬리)을 못 참으면 들킨다.

const SNIFF_RANGE := 2.4
const EAT_TIME := {"rack": 1.5, "decoy": 1.5, "fridge": 2.2}
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
func set_seen(v: bool) -> void:
	v = v or revealed_t > 0.0
	seen = v
	var layer := 1 | 2 if v else 2
	for m in body_model.find_children("*", "VisualInstance3D", true, false):
		m.layers = layer

## 붙잡혔을 때 연출: 집게에 들려 공중에서 버둥댄다.
func caught() -> void:
	stop()
	revealed_t = 99.0
	_unhide_visual()
	set_seen(true)
	say("깨갱!!", 99.0, true)
	Anim.play(ap, "Jump_Loop")
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y + 1.6, 0.35).set_trans(Tween.TRANS_BACK)

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
	var rack = game.rack
	var s: int = rack.nearest(global_position, "hotdog", dist)
	if s >= 0:
		return {"kind": "rack", "pos": rack.slot_pos(s), "target": s}
	for d in game.decoys:
		if not d.get_meta("bitten") and _flat(global_position, d.global_position) < dist - 0.2:
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
			tail_pending += 75.0
		else:
			say("(움찔)", 1.0)

func _instincts(delta: float) -> void:
	var near_food := false
	if hidden:
		near_food = _smells_food()
	sniff = clampf(sniff + (14.0 if near_food else -20.0) * delta, 0.0, 100.0)
	var rise := minf(tail_pending, 60.0 * delta)
	tail_pending -= rise
	tail = clampf(tail + rise - 6.0 * delta, 0.0, 100.0)
	if not hidden:
		tail = maxf(tail - 20.0 * delta, 0.0)
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
		if not d.get_meta("bitten") and _flat(global_position, d.global_position) < SNIFF_RANGE:
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
	game.make_noise(global_position, radius)

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

func _physics_process(delta: float) -> void:
	if stopped:
		return
	revealed_t = maxf(revealed_t - delta, 0.0)
	_instincts(delta)
	_paws(delta)
	if eat_left > 0.0:
		_tick_eat(delta)
		if not is_ai and Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down").length() > 0.1:
			_cancel_eat()
		return
	if is_ai:
		_ai(delta)
	else:
		_player()

func _player() -> void:
	if Input.is_action_just_pressed(prefix + "act"):
		toggle_hide()
	if Input.is_action_just_pressed(prefix + "skill"):
		if hidden:
			hold_tail()
		else:
			try_eat()
	if hidden:
		velocity = Vector3.ZERO
		return
	var v := Input.get_vector(prefix + "left", prefix + "right", prefix + "up", prefix + "down")
	var dir := Vector3(v.x, 0, v.y)
	velocity = dir * speed
	move_and_slide()
	if dir.length() > 0.1:
		_face(dir)
		Anim.play(ap, "Run", 1.2)
	else:
		Anim.play(ap, "Idle")

func _face(dir: Vector3) -> void:
	dir.y = 0
	if dir.length() < 0.01:
		return
	body_model.rotation.y = lerp_angle(body_model.rotation.y, atan2(dir.x, dir.z), 0.3)

func _paws(delta: float) -> void:
	if paw_left <= 0 or hidden:
		return
	paw_t -= delta
	if paw_t <= 0.0 and velocity.length() > 0.5:
		paw_t = 0.45
		paw_left -= 1
		game.add_trace(global_position, "paw")

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ---------------------------------------------------------------- AI

func _ai(delta: float) -> void:
	var chef = game.chef
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
		if not d.get_meta("bitten"):
			opts.append({"stand": d.global_position + Vector3(0.5, 0, 0.3), "pos": d.global_position})
	if fridge_left > 0:
		var fr: Vector3 = game.stations["fridge"].global_position
		opts.append({"stand": fr, "pos": fr})
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
