extends Node
## 전역: 고른 모드와 키 설정.
## chef = 혼자 셰프, dog = 혼자 강아지, duo = 둘이서 (강아지 WASD / 셰프 방향키)

var mode := "chef"
## 모드: chef / dog / duo / tut_chef / tut_dog (연습) / watch (개발용 AI끼리)

const SAVE_PATH := "user://save.cfg"
var save := ConfigFile.new()
var args := {}  # 개발용 명령줄 옵션
var invite_code := ""  # 초대 링크(?join=코드)로 열었을 때

func _ready() -> void:
	save.load(SAVE_PATH)
	_bind("p1_up", [KEY_W])
	_bind("p1_down", [KEY_S])
	_bind("p1_left", [KEY_A])
	_bind("p1_right", [KEY_D])
	_bind("p1_act", [KEY_SPACE])
	_bind("p1_skill", [KEY_E])
	_bind("p1_bark", [KEY_Q])
	_bind("p2_up", [KEY_UP])
	_bind("p2_down", [KEY_DOWN])
	_bind("p2_left", [KEY_LEFT])
	_bind("p2_right", [KEY_RIGHT])
	_bind("p2_act", [KEY_ENTER, KEY_KP_ENTER, KEY_KP_0])
	_bind("p2_skill", [KEY_SHIFT, KEY_KP_PERIOD], true)
	_debug_args()

## 개발용: godot --path . -- --play --mode=dog --shot=res://shot.png --wait=3
## 지정한 모드로 바로 시작하고, 몇 초 뒤 화면을 저장하고 끈다.
func _debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("mode"):
		mode = args["mode"]
	if args.has("net-host"):  # 개발용: 바로 방 만들기 (역할 chef/dog)
		Net.host.call_deferred(args["net-host"])
	if args.has("net-join"):  # 개발용: 바로 방 들어가기
		Net.join.call_deferred(args["net-join"])
	if args.has("play"):  # 메뉴를 건너뛰고 바로 한 판
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
	if args.has("shot") or args.has("wait"):  # --wait만 주면 화면 없이(headless) 돌리고 끝낸다
		await get_tree().create_timer(float(args.get("wait", "3"))).timeout
		if args.has("shot"):
			get_viewport().get_texture().get_image().save_png(args["shot"])
		get_tree().quit()

## 연습을 끝냈거나, 처음 물었을 때 "바로 시작"을 골랐는지
func tutorial_seen(kind: String) -> bool:
	return save.get_value("tutorial", kind, false)

func mark_tutorial_seen(kind: String) -> void:
	save.set_value("tutorial", kind, true)
	save.save(SAVE_PATH)

func _bind(action: String, keys: Array, right_shift := false) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		if right_shift and k == KEY_SHIFT:
			ev.location = KEY_LOCATION_RIGHT
		InputMap.action_add_event(action, ev)
