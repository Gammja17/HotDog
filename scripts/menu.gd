extends Control
## 첫 화면: 모드 고르기. 혼자 하기를 처음 고르면 연습부터 할지 묻는다.

const DESC := {
	"chef": "1인칭 핫도그 트럭 사장님. 3분 안에 10개를 팔자.\n그런데 등 뒤에서 킁킁 소리가... 잡아서 밖으로 던져도 또 온다!",
	"dog": "배고픈 강아지가 되어 장터와 트럭을 누비자. 소시지 5개를 먹거나,\n짖어서 손님을 쫓아 사장님이 10개를 못 팔게 하면 승리!",
	"duo": "왼쪽 화면은 셰프(방향키), 오른쪽 화면은 강아지(WASD).\n셰프는 상대 화면을 훔쳐보지 않기로 약속!",
	"online": "각자 자기 컴퓨터에서, 방 코드로 친구와 같이 한다.\n한 명은 셰프, 한 명은 강아지.",
	"tut_chef": "조리부터 강아지 잡기까지, 한 단계씩 해 보는 연습 영업.",
	"tut_dog": "숨기, 몰래 먹기, 본능 참기를 한 단계씩 해 보는 연습.",
}

var pending := ""   # 연습을 물어본 모드

func _ready() -> void:
	var buttons := {"chef": %Chef, "dog": %Dog, "duo": %Duo, "online": %Online, "tut_chef": %PracticeChef, "tut_dog": %PracticeDog}
	for m in buttons:
		var b: Button = buttons[m]
		b.pressed.connect(_pick.bind(m))
		b.mouse_entered.connect(func(): %Desc.text = DESC[m])
		b.focus_entered.connect(func(): %Desc.text = DESC[m])
	%AskYes.pressed.connect(func(): _start("tut_" + pending))
	%AskNo.pressed.connect(func():
		Session.mark_tutorial_seen(pending)
		_start(pending)
	)
	%Chef.grab_focus()
	# 초대 링크로 열었으면 바로 온라인 방으로
	if OS.has_feature("web"):
		var dh := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('devhost') || ''", true))
		if dh != "" and not Net.online:
			Session.args["devhost"] = dh
			get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")
			return
	var code := Net.invited_code()
	if code != "" and not Net.online:
		Session.invite_code = code
		JavaScriptBridge.eval("history.replaceState(null, '', location.pathname)")  # 새로고침해도 또 들어가지 않게
		get_tree().change_scene_to_file.call_deferred("res://scenes/lobby.tscn")

func _pick(m: String) -> void:
	if m == "online":
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		return
	if m in ["chef", "dog"] and not Session.tutorial_seen(m):
		pending = m
		%Ask.visible = true
		%AskYes.grab_focus()
		return
	_start(m)

func _start(m: String) -> void:
	Session.mode = m
	get_tree().change_scene_to_file("res://scenes/main.tscn")
