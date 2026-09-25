extends CanvasLayer
## 화면 위 정보: 남은 시간, 별점, 먹은 소시지, 셰프 손, 강아지 본능 게이지, 결과 창.

const HINTS := {
	"chef_p1": "WASD 이동 · Space 행동 (빵/그릴/소스/진열/판매/집게) · E \"누가 착한 아이지~?\"",
	"chef_p2": "방향키 이동 · Enter 행동 · 오른쪽 Shift \"누가 착한 아이지~?\"",
	"dog": "WASD 이동 · Space 변장/나오기 · E 먹기 (숨었을 때는 연타해서 꼬리 참기)",
}
const NEXT := {"": "빵 → 그릴 → 소스 순서로 만들자", "bun": "그릴로!", "grilled": "소스로!", "hotdog": "진열대나 판매 창구로!"}

var game: Node
var mode := ""
var banner_t := 0.0

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
	chef_box.visible = m != "dog"
	dog_box.visible = m != "chef"
	chef_hint.text = HINTS["chef_p2" if m == "duo" else "chef_p1"]
	dog_hint.text = HINTS["dog"]
	result.visible = false
	split.visible = m == "duo"
	%Retry.pressed.connect(func(): get_tree().reload_current_scene())
	%Menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))

## 둘이서: 왼쪽은 셰프 눈(레이어 1), 오른쪽은 강아지 눈(전부)
func setup_split(xf: Transform3D) -> void:
	for pair in [[%ChefCam, 1], [%DogCam, 1 | 2]]:
		var c: Camera3D = pair[0]
		c.global_transform = xf
		c.cull_mask = pair[1]
		c.current = true

func banner(text: String) -> void:
	banner_label.text = text
	banner_label.modulate.a = 1.0
	banner_t = 3.5

func _process(delta: float) -> void:
	if banner_t > 0.0:
		banner_t -= delta
		if banner_t < 0.6:
			banner_label.modulate.a = maxf(banner_t / 0.6, 0.0)
	if result.visible and Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()

func refresh() -> void:
	var t := int(ceil(game.time_left))
	time_label.text = "남은 시간 %d:%02d" % [t / 60, t % 60]
	var full := int(game.stars)
	var half: bool = game.stars - full >= 0.5
	stars_label.text = "★".repeat(full) + ("☆" if half else "") + "·".repeat(5 - full - int(half))
	eaten_label.text = "먹힌 소시지 %d / %d" % [game.eaten, game.EAT_GOAL]
	var chef = game.chef
	if chef_box.visible:
		var bitten := " (한 입 먹힘!)" if chef.hand_bitten and chef.hand == "hotdog" else ""
		hand_label.text = "손: %s%s  —  %s" % [chef.HAND_TEXT[chef.hand], bitten, NEXT[chef.hand]]
		call_label.text = "부르기 준비됨" if chef.call_cd <= 0.0 else "부르기 %d초" % ceil(chef.call_cd)
	var dog = game.dog
	if dog_box.visible:
		sniff_bar.value = dog.sniff
		tail_bar.value = dog.tail
		if dog.hidden:
			dog_state.text = "변장 중" + (" (진열대)" if dog.in_slot() else "")
		elif dog.seen:
			dog_state.text = "들켰다! 도망쳐!"
		else:
			dog_state.text = "몰래 움직이는 중"

func show_result(title: String, body: String, chef_won: bool) -> void:
	result.visible = true
	var me := ""
	if mode == "chef":
		me = "이겼다! " if chef_won else "졌다... "
	elif mode == "dog":
		me = "이겼다! " if not chef_won else "졌다... "
	result_title.text = me + title
	result_body.text = body
	%Retry.grab_focus()
