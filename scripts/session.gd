extends Node
## 전역: 고른 모드와 키 설정.
## chef = 혼자 셰프, dog = 혼자 강아지, duo = 둘이서 (강아지 WASD / 셰프 방향키)

var mode := "chef"
var args := {}  # 개발용 명령줄 옵션

func _ready() -> void:
	_bind("p1_up", [KEY_W])
	_bind("p1_down", [KEY_S])
	_bind("p1_left", [KEY_A])
	_bind("p1_right", [KEY_D])
	_bind("p1_act", [KEY_SPACE])
	_bind("p1_skill", [KEY_E])
	_bind("p2_up", [KEY_UP])
	_bind("p2_down", [KEY_DOWN])
	_bind("p2_left", [KEY_LEFT])
	_bind("p2_right", [KEY_RIGHT])
	_bind("p2_act", [KEY_ENTER, KEY_KP_ENTER, KEY_KP_0])
	_bind("p2_skill", [KEY_SHIFT, KEY_KP_PERIOD], true)
	_debug_args()

## 개발용: godot --path . scenes/main.tscn -- --mode=dog --shot=res://shot.png --wait=3
## 지정한 모드로 바로 시작하고, 몇 초 뒤 화면을 저장하고 끈다.
func _debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
	if args.has("mode"):
		mode = args["mode"]
	if args.has("shot"):
		await get_tree().create_timer(float(args.get("wait", "3"))).timeout
		get_viewport().get_texture().get_image().save_png(args["shot"])
		get_tree().quit()

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
