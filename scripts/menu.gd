extends Control
## 첫 화면: 모드 고르기. 혼자 하기를 처음 고르면 연습부터 할지 묻는다.

const DESC := {
	"chef": "핫도그 트럭 사장님이 되어 장사를 하자.\n그런데 바닥에 부스러기가... 진열대 핫도그가 하나 늘었나?",
	"dog": "배고픈 강아지가 되어 핫도그로 변장하자.\n사장님 눈을 피해 소시지 5개를 먹으면 승리!",
	"duo": "왼쪽 화면은 셰프(방향키), 오른쪽 화면은 강아지(WASD).\n셰프는 상대 화면을 훔쳐보지 않기로 약속!",
	"tut_chef": "조리부터 강아지 잡기까지, 한 단계씩 해 보는 연습 영업.",
	"tut_dog": "숨기, 몰래 먹기, 본능 참기를 한 단계씩 해 보는 연습.",
}

var pending := ""   # 연습을 물어본 모드

func _ready() -> void:
	var buttons := {"chef": %Chef, "dog": %Dog, "duo": %Duo, "tut_chef": %PracticeChef, "tut_dog": %PracticeDog}
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

func _pick(m: String) -> void:
	if m in ["chef", "dog"] and not Session.tutorial_seen(m):
		pending = m
		%Ask.visible = true
		%AskYes.grab_focus()
		return
	_start(m)

func _start(m: String) -> void:
	Session.mode = m
	get_tree().change_scene_to_file("res://scenes/main.tscn")
