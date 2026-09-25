extends Control
## 첫 화면: 모드 고르기.

const DESC := {
	"chef": "핫도그 트럭 사장님이 되어 장사를 하자.\n그런데 바닥에 부스러기가... 진열대 핫도그가 하나 늘었나?",
	"dog": "배고픈 강아지가 되어 핫도그로 변장하자.\n사장님 눈을 피해 소시지 5개를 먹으면 승리!",
	"duo": "왼쪽 화면은 셰프(방향키), 오른쪽 화면은 강아지(WASD).\n셰프는 상대 화면을 훔쳐보지 않기로 약속!",
}

func _ready() -> void:
	for m in ["chef", "dog", "duo"]:
		var b: Button = get_node("%" + m.capitalize())
		b.pressed.connect(_start.bind(m))
		b.mouse_entered.connect(func(): %Desc.text = DESC[m])
		b.focus_entered.connect(func(): %Desc.text = DESC[m])
	%Chef.grab_focus()

func _start(m: String) -> void:
	Session.mode = m
	get_tree().change_scene_to_file("res://scenes/main.tscn")
