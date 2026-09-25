extends Control
## 온라인 방 만들기 / 들어가기. 짝이 지어지면 Net이 알아서 게임을 시작한다.

func _ready() -> void:
	%HostChef.pressed.connect(func(): _host("chef"))
	%HostDog.pressed.connect(func(): _host("dog"))
	%Join.pressed.connect(_join)
	%CodeInput.text_submitted.connect(func(_t): _join())
	%CodeInput.text_changed.connect(func(t):
		var col: int = %CodeInput.caret_column
		%CodeInput.text = t.to_upper()
		%CodeInput.caret_column = col
	)
	%Back.pressed.connect(func():
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)
	Net.status.connect(func(t): %Status.text = t)
	Net.failed.connect(func(t):
		%Status.text = t
		_busy(false)
	)
	Net.room_created.connect(func(code):
		%Code.text = code
		%Code.visible = true
		%Status.text = "친구에게 코드 [%s]를 알려 주세요. 친구가 들어오면 바로 시작해요." % code
	)
	Net.paired.connect(func(): %Status.text = "연결됐어요! 시작합니다...")
	%HostChef.grab_focus()

func _host(role: String) -> void:
	_busy(true)
	%Code.visible = false
	Net.host(role)

func _join() -> void:
	var code: String = %CodeInput.text.strip_edges().to_upper()
	if code.length() != 4:
		%Status.text = "코드는 4글자예요."
		return
	_busy(true)
	Net.join(code)

func _busy(on: bool) -> void:
	for b in [%HostChef, %HostDog, %Join]:
		b.disabled = on
