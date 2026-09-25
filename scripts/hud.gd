extends CanvasLayer
## 화면 위 정보: 남은 시간, 별점, 먹은 소시지, 셰프 손, 강아지 본능 게이지, 결과 창.

const HINTS := {
	"chef_p1": "마우스 둘러보기 (화면 클릭, Esc 풀기)  /  WASD 걷기  /  Space 행동  /  E \"누가 착한 아이지~?\"",
	"chef_p2": "방향키 위아래 걷기, 좌우 돌기  /  Enter 행동  /  오른쪽 Shift \"누가 착한 아이지~?\"",
	"dog": "WASD 이동  /  Space 변장·나오기  /  E 먹기 (숨었을 땐 연타로 꼬리 참기)  /  Q 짖기 (손님 겁주기)",
}
const NEXT := {"": "빵, 그릴, 소스 순서로 만들자", "bun": "그릴로!", "grilled": "소스로!", "hotdog": "진열대나 판매 창구로!"}

var game: Node
var mode := ""
var banner_t := 0.0
var next_mode := ""   # 연습이 끝나면 "진짜 영업 시작" 버튼이 여는 모드

@onready var time_label: Label = %Time
@onready var stars_label: Label = %Stars
@onready var eaten_label: Label = %Eaten
@onready var banner_label: Label = %Banner
@onready var chef_box: Control = %ChefBox
@onready var hand_label: Label = %Hand
@onready var call_label: Label = %Call
@onready var chef_hint: Label = %ChefHint
@onready var dog_box: Control = %DogBox
@onready var sniff_bar: ProgressBar = %SniffBar
@onready var tail_bar: ProgressBar = %TailBar
@onready var dog_hint: Label = %DogHint
@onready var dog_state: Label = %DogState
@onready var result: Control = %Result
@onready var result_title: Label = %ResultTitle
@onready var result_body: Label = %ResultBody
@onready var split: Control = %Split

func setup(g: Node, m: String) -> void:
	game = g
	mode = m
	chef_box.visible = m in ["chef", "duo", "watch", "tut_chef"]
	dog_box.visible = m in ["dog", "duo", "watch", "tut_dog"]
	chef_hint.text = HINTS["chef_p2" if m == "duo" else "chef_p1"]
	dog_hint.text = HINTS["dog"]
	result.visible = false
	split.visible = m == "duo"
	%Retry.pressed.connect(_retry)
	%Menu.pressed.connect(func():
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)

## 둘이서: 왼쪽은 셰프 눈(레이어 1), 오른쪽은 강아지 눈(전부)
func setup_split(xf: Transform3D) -> void:
	for pair in [[%ChefCam, 1 | 8], [%DogCam, 1 | 2 | 4]]:
		var c: Camera3D = pair[0]
		c.global_transform = xf
		c.cull_mask = pair[1]
		c.current = true

func chef_cam() -> Camera3D:
	return %ChefCam

func dog_cam() -> Camera3D:
	return %DogCam

## 1인칭 셰프 화면 요소 (가운데 점, Space 안내, 내 말, 조리 손맛 창)
func enable_fp(chef: Node, left_half := false) -> void:
	var fp := preload("res://scenes/fp_hud.tscn").instantiate()
	add_child(fp)
	move_child(fp, 1)  # 분할 화면 위, 나머지 창 아래
	if left_half:
		fp.anchor_right = 0.5  # 둘이서: 왼쪽 셰프 화면에만
	fp.chef = chef

func banner(text: String) -> void:
	banner_label.text = text
	banner_label.modulate.a = 1.0
	banner_t = 3.5

func _process(delta: float) -> void:
	if banner_t > 0.0:
		banner_t -= delta
		if banner_t < 0.6:
			banner_label.modulate.a = maxf(banner_t / 0.6, 0.0)
	if result.visible and %Retry.visible and next_mode == "" and Input.is_physical_key_pressed(KEY_R):
		_retry()

func _retry() -> void:
	if next_mode != "":
		Session.mode = next_mode
	if game.online:
		Net.send({"k": "restart"})  # 상대 화면도 같이 새 판으로
	get_tree().reload_current_scene()

## 온라인 상대가 나갔을 때
func show_left() -> void:
	result.visible = true
	result_title.text = "친구가 나갔어요"
	result_body.text = "연결이 끊겼거나 친구가 게임을 껐어요.\n처음 화면에서 방을 다시 만들어 주세요."
	%Retry.visible = false
	%Menu.grab_focus()

func refresh() -> void:
	var t := int(ceil(game.time_left))
	time_label.text = "연습 중" if game.tutorial != null else "남은 시간 %d:%02d" % [t / 60, t % 60]
	var full := int(game.stars)
	stars_label.text = "★".repeat(full) + "☆".repeat(5 - full)
	eaten_label.text = "먹힌 소시지 %d / %d" % [game.eaten, game.EAT_GOAL]
	%Sold.text = "판매 %d / %d" % [game.sold, game.SALES_GOAL]
	%Caught.text = "잡은 횟수 %d" % game.caught
	var chef = game.chef
	if chef_box.visible:
		var bitten := " (한 입 먹힘!)" if chef.hand_bitten and chef.hand == "hotdog" else ""
		hand_label.text = "손: %s%s  /  %s" % [chef.HAND_TEXT[chef.hand], bitten, NEXT[chef.hand]]
		call_label.text = "부르기 준비됨" if chef.call_cd <= 0.0 else "부르기 %d초" % ceil(chef.call_cd)
	var dog = game.dog
	if dog_box.visible:
		sniff_bar.value = dog.sniff
		tail_bar.value = dog.tail
		var bark := "  |  Q 짖기 준비됨" if dog.bark_cd <= 0.0 else "  |  Q 짖기 %d초" % ceil(dog.bark_cd)
		if dog.hidden:
			dog_state.text = "변장 중" + (" (진열대)" if dog.in_slot() else "") + bark
		elif dog.seen:
			dog_state.text = "들켰다! 도망쳐!" + bark
		else:
			dog_state.text = ("몰래 움직이는 중" if game.chef.in_truck(dog.global_position) else "장터 구경 중") + bark

func show_result(title: String, body: String, chef_won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	result.visible = true
	var me := ""
	if mode == "chef":
		me = "이겼다! " if chef_won else "졌다... "
	elif mode == "dog":
		me = "이겼다! " if not chef_won else "졌다... "
	result_title.text = me + title
	result_body.text = body
	%Retry.grab_focus()

func show_tutorial_done(title: String, body: String, kind: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	next_mode = kind
	result.visible = true
	result_title.text = title
	result_body.text = body
	%Retry.text = "진짜 영업 시작"
	%Retry.grab_focus()
