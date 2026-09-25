extends Node
## 연습 영업 (튜토리얼). 한 단계씩 해 보면서 배운다. 시간 제한은 없다.
## 단계마다 text(안내), enter(시작할 때 할 일), done(끝났는지), hint(상황별 한 줄 더)를 가진다.

const PANEL := preload("res://scenes/tutorial_panel.tscn")

var game: Node
var kind := ""              # chef / dog
var steps: Array = []
var i := -1
var step_t := 0.0
var flash_t := 0.0
var finished := false
var ev := {}                # 이번 단계에서 일어난 일 (served, call, ate, caught, noise)
var mem := {}               # 단계 사이에 기억할 값
var panel: Control

func setup(g: Node, k: String) -> void:
	game = g
	kind = k
	panel = PANEL.instantiate()
	game.hud.add_child(panel)
	# 아래쪽, 내 정보 창의 반대편에 둔다 (위쪽 조리대를 가리지 않게)
	var right := k == "chef"
	panel.anchor_left = 1.0 if right else 0.0
	panel.anchor_right = panel.anchor_left
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -690.0 if right else 10.0
	panel.offset_right = -10.0 if right else 690.0
	panel.offset_top = -140.0
	panel.offset_bottom = -10.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.get_node("%Skip").pressed.connect(_skip)
	steps = _chef_steps() if k == "chef" else _dog_steps()
	_prepare()
	_next()

func event(name: String) -> void:
	ev[name] = true
	if name == "caught" or name == "noise":
		ev[name + "_t"] = step_t

func _process(delta: float) -> void:
	if finished or i < 0:
		return
	step_t += delta
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			_next()
		return
	var s: Dictionary = steps[i]
	var hint := ""
	if s.has("hint"):
		hint = s.hint.call()
	_show(s.text + ("\n" + hint if hint != "" else ""), false)
	if s.done.call():
		flash_t = 1.1
		_show("좋아요!", true)

func _next() -> void:
	i += 1
	ev.clear()
	step_t = 0.0
	if i >= steps.size():
		_finish()
		return
	var s: Dictionary = steps[i]
	if s.has("enter"):
		s.enter.call()

func _show(text: String, good: bool) -> void:
	panel.get_node("%Step").text = "연습 %d / %d" % [mini(i + 1, steps.size()), steps.size()]
	var l: Label = panel.get_node("%Text")
	l.text = text
	l.modulate = Color(0.55, 1, 0.55) if good else Color.WHITE

func _finish() -> void:
	finished = true
	panel.visible = false
	Session.mark_tutorial_seen(kind)
	var body: String = {
		"chef": "진짜 영업에서는 강아지가 알아서 숨고, 먹고, 도망친다.\n흔적을 따라가고, 진열대 핫도그 개수도 세어 보자.\n3분 안에 잡으면 승리!",
		"dog": "소시지 5개를 먹으면 승리.\n진짜 사장님은 흔적을 쫓아오고, 수상한 핫도그를 찔러 보고,\n눈에 띄면 쫓아온다. 행운을 빈다!",
	}[kind]
	game.hud.show_tutorial_done("연습 끝!", body, kind)

func _skip() -> void:
	Session.mark_tutorial_seen(kind)
	Session.mode = kind
	get_tree().reload_current_scene()

# ---------------------------------------------------------------- 공용

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _prepare() -> void:
	var chef = game.chef
	var dog = game.dog
	if kind == "chef":
		dog.scripted = true
		dog.calm_sniff = true
		dog.calm_tail = true
		dog.visible = false
		dog.global_position = Vector3(4.0, 0, 2.9)
	else:
		chef.scripted = true
		chef.global_position = game.stations["bread"].global_position
		chef.script_face = Vector3(0, 0, -1)
		chef.facing = Vector3(0, 0, -1)
		chef.script_working = true
		dog.calm_sniff = true
		dog.calm_tail = true

# ---------------------------------------------------------------- 셰프 편

func _chef_steps() -> Array:
	var chef = game.chef
	var dog = game.dog
	var crumbs := Vector3(4.4, 0, 1.3)
	return [
		{
			"text": "개업 첫날이다! 먼저 핫도그를 만들어 보자.\n반짝이는 노란 매트(빵) 위로 가서 Space를 누르자. 이동은 WASD.",
			"done": func(): return chef.hand == "bun",
		},
		{
			"text": "빵을 들었다. 이번엔 빨간 매트(그릴)에서 Space.\n다 구워질 때까지 가만히 기다리자. 움직이면 멈춘다.",
			"done": func(): return chef.hand == "grilled",
		},
		{
			"text": "주황 매트(소스)에서 Space를 누르면 케첩을 뿌려 완성!",
			"done": func(): return chef.hand == "hotdog",
		},
		{
			"text": "첫 손님이 왔다! 초록 매트(판매 창구)에서 Space로 건네자.",
			"enter": func(): game.spawn_customer(),
			"done": func(): return ev.has("served"),
		},
		{
			"text": "손님이 몰릴 때를 대비해 미리 만들어 두면 좋다.\n하나 더 만들어서, 진열대(가운데 빨간 판) 앞에서 Space로 빈칸에 올리자.",
			"enter": func(): mem["rack"] = game.rack.count_items(),
			"done": func(): return game.rack.count_items() > mem["rack"],
		},
		{
			"text": "...어? 트럭 오른쪽 아래 구석에서 무슨 소리가 났다.\n가서 바닥을 살펴보자.",
			"enter": func():
				dog.visible = true
				dog.hide_now()
				game.add_trace(crumbs, "crumbs")
				for k in 4:
					game.add_trace(crumbs.lerp(dog.global_position, (k + 1) / 5.0), "paw")
				chef.say("...방금 무슨 소리지?", 2.0),
			"done": func(): return _flat(chef.global_position, crumbs) < 2.2,
		},
		{
			"text": "부스러기와 케첩 발자국이다. 누가 여기서 뭘 먹었다!\n근처 바닥에 굴러다니는 핫도그 중 하나는... 핫도그가 아닐지도?\nE를 눌러 \"누가 착한 아이지~?\"를 외쳐 보자.",
			"done": func(): return ev.has("call") and dog.tail > 30.0,
			"hint": func(): return "(너무 멀면 안 들린다. 핫도그들 가까이에서 외치자)" if ev.has("call") else "",
		},
		{
			"text": "꼬리가 살랑거리는 핫도그가 있다! 저게 강아지다.\n바로 옆으로 가서 Space로 집게질!",
			"done": func(): return ev.has("caught"),
			"hint": func(): return "(꼬리가 잠잠해졌다. E로 다시 불러 보자)" if dog.tail < 25.0 else "",
		},
	]

# ---------------------------------------------------------------- 강아지 편

func _dog_steps() -> Array:
	var chef = game.chef
	var dog = game.dog
	var rack = game.rack
	return [
		{
			"text": "배고픈 강아지가 푸드트럭에 몰래 들어왔다.\nWASD로 움직여 보자. 초록 원이 바로 나다.",
			"enter": func(): mem["start"] = dog.global_position,
			"done": func(): return _flat(dog.global_position, mem["start"]) > 1.5,
		},
		{
			"text": "노란 부채꼴은 사장님 눈에 보이는 범위다. 저 안에 들어가면 들킨다.\n지금 사장님은 조리대만 보고 있다. 부채꼴을 피해 진열대(가운데 빨간 판) 앞까지 가 보자.",
			"done": func(): return rack.nearest(dog.global_position, "hotdog", 1.4) >= 0,
			"hint": func(): return "앗, 부채꼴 안이다! 얼른 빠져나가자." if chef.can_see(dog.body_point()) else "",
		},
		{
			"text": "진열대 핫도그 옆에서 E를 누르면 한 입 먹는다.\n먹는 동안은 움직이면 안 된다.",
			"done": func(): return ev.has("ate"),
		},
		{
			"text": "먹은 자리에는 부스러기가, 잠깐 동안은 케첩 발자국이 남는다.\n사장님이 이걸 보면 의심하기 시작한다.",
			"done": func(): return step_t > 5.0,
		},
		{
			"text": "앗, 사장님이 돌아본다!\nSpace를 누르면 그 자리에서 핫도그로 변장한다. 진열대 빈칸 옆이면 빈칸에 쏙 들어간다.",
			"enter": func():
				chef.script_working = false
				chef.script_face = (rack.global_position - chef.global_position).normalized()
				chef.say("음?", 1.2),
			"done": func(): return dog.hidden,
			"hint": func(): return "들킬 뻔했다! 진짜 영업이었으면 쫓아왔을 거다." if not dog.hidden and chef.can_see(dog.body_point()) else "",
		},
		{
			"text": "사장님은 진열대에 올린 핫도그 개수를 기억한다. 빈칸에 숨으면 하나가 늘어 보인다.\n바닥에 숨을 때는 원래 굴러다니던 핫도그 옆이 덜 수상하다.",
			"enter": func():
				chef.say("핫도그가... 하나 늘었네?" if dog.in_slot() else "저 핫도그... 원래 저기 있었나?", 2.5),
			"done": func(): return step_t > 6.0,
		},
		{
			"text": "음식 옆에 숨어 있으면 냄새를 참기 힘들다. 오른쪽 아래 '킁킁' 게이지를 보자.\n가득 차면 킁킁거려서 들킨다! 음식 옆에 숨었다가 게이지가 반쯤 차면 Space로 나오자.",
			"enter": func():
				chef.script_face = Vector3(0, 0, -1)
				chef.script_working = true
				mem["sniffed"] = false,
			"done": func():
				if dog.sniff >= 50.0:
					mem["sniffed"] = true
				return mem["sniffed"] and not dog.hidden,
			"hint": func():
				if mem["sniffed"]:
					return "지금이다! Space로 나오자."
				if dog.hidden and dog.sniff < 5.0:
					return "(여기엔 음식 냄새가 없다. 핫도그나 냉장고 옆에 숨어 보자)"
				return "",
		},
		{
			"text": "마지막! 사장님이 \"누가 착한 아이지~?\"를 외치면 숨어 있어도 꼬리가 들썩인다.\n사장님 근처에서 Space로 숨고, 사장님이 부르면 E를 연타해서 꼬리를 참자.",
			"enter": func():
				chef.script_working = false
				chef.script_goal = Vector3(0, 0, -0.45)
				dog.calm_tail = false
				mem["called_t"] = -1.0,
			"done": func():
				var near: bool = _flat(dog.global_position, chef.global_position) < 5.5
				if dog.hidden and near and mem["called_t"] < 0.0 and step_t > 2.0:
					chef.script_face = dog.global_position - chef.global_position
					chef.call_cd = 0.0
					chef.call_dog()
					mem["called_t"] = step_t
				if ev.has("noise"):
					ev.erase("noise")
					mem["called_t"] = -1.0
					mem["failed"] = true
				# 부른 뒤 들키지 않고, 꼬리가 다 가라앉을 때까지 버티면 성공
				return mem["called_t"] >= 0.0 and step_t - mem["called_t"] > 2.5 and dog.hidden \
					and dog.tail_pending <= 0.0 and dog.tail < 30.0,
			"hint": func():
				if mem.get("failed", false) and not dog.hidden:
					return "\"왈!\" 들켜 버렸다. 다시 Space로 숨어서 해 보자."
				if not dog.hidden:
					return ""
				if _flat(dog.global_position, chef.global_position) >= 5.5:
					return "(너무 멀다. 진열대 근처의 사장님 가까이에 숨자)"
				if mem["called_t"] >= 0.0:
					return "E 연타! 꼬리를 참아라!"
				return "",
		},
	]
