extends Node3D
## 손님. 창구 앞 줄에 서서 핫도그를 기다린다. 오래 기다리면 화내고 떠난다.
## 핫도그를 받으면 장터 스탠드 테이블에서 서서 먹다가 떠난다. 그동안 강아지가 노린다.

const PATIENCE := 45.0
const EAT_TIME := 12.0
const ORDERS := ["핫도그 하나요!", "하나 주세요~", "케첩 많이요!", "빨리요, 버스 와요!"]

var game: Node
var target := Vector3.ZERO
var patience := PATIENCE
var leaving := false
var served := false
var hue := randf()
var state := "queue"         # queue / to_eat / eating / leaving
var eat_spot: Node3D
var eat_t := 0.0
var puppet := false     # 온라인 손님 쪽: 방장이 보낸 상태만 보여 준다
var net_id := 0

@onready var model: Node3D = $Model
@onready var say_label: Label3D = $Say
@onready var wait_label: Label3D = $Wait
@onready var hat: MeshInstance3D = $Hat
@onready var food: Node3D = $Food
@onready var agent: NavigationAgent3D = $Agent
var ap: AnimationPlayer
var say_t := 0.0

func _ready() -> void:
	ap = Anim.setup(model)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(hue, 0.6, 0.9)
	hat.material_override = mat
	wait_label.text = ""

func net_state() -> Array:
	return [net_id, position.x, position.z, model.rotation.y, ap.get_meta("cur", ["Idle", 1.0]) if ap else ["Idle", 1.0],
		say_label.text, wait_label.text, wait_label.modulate.to_html(), hue, food.visible]

func apply_net(d: Array) -> void:
	position = position.lerp(Vector3(d[1], 0, d[2]), 0.35)
	model.rotation.y = lerp_angle(model.rotation.y, d[3], 0.35)
	Anim.play(ap, d[4][0], d[4][1])
	say_label.text = d[5]
	wait_label.text = d[6]
	wait_label.modulate = Color.html(d[7])
	food.visible = d[9]

func say(text: String, t := 2.0) -> void:
	say_label.text = text
	say_t = t

## 줄 맨 앞에 도착해서 주문할 수 있는 상태인가
func ready_to_order() -> bool:
	return state == "queue" and position.distance_to(target) < 0.3

## 테이블에서 핫도그를 들고 먹는 중 (강아지가 뺏을 수 있다)
func has_food() -> bool:
	return state == "eating" and food.visible

func serve(bitten: bool) -> void:
	served = true
	if bitten:
		say(["사장님! 여기 털 나왔어요!", "이거 누가 먹다 준 거예요?!", "반쪽밖에 없잖아요!"].pick_random(), 2.5)
		leave()
		return
	say(["고마워요!", "냄새 좋다~", "잘 먹을게요!"].pick_random(), 1.8)
	food.visible = true
	eat_spot = game.claim_eat_spot(self)
	if eat_spot == null:
		leave()
		return
	state = "to_eat"
	target = eat_spot.global_position

## 강아지가 핫도그를 뺏어 먹었다
func stolen() -> void:
	food.visible = false
	say(["내 핫도그!!", "야, 이 개가!", "엄마, 개가 먹었어!"].pick_random(), 2.5)
	leave()

## 강아지가 짖어서 겁먹었다. 줄 선 손님은 떠나고, 먹던 손님은 핫도그를 떨어뜨린다
func scared() -> void:
	if state == "leaving":
		return
	if state == "queue":
		say(["으악, 개다!", "개 무서워요!", "여기 개 있어요?!"].pick_random(), 2.0)
		game.customer_scared(self)
	elif food.visible:
		say(["꺄악! 내 핫도그!", "깜짝이야!"].pick_random(), 2.0)
		food.visible = false
		game.add_decoy(global_position + Vector3(randf_range(-0.4, 0.4), 0, 0.6))
	leave()

func leave() -> void:
	leaving = true
	state = "leaving"
	wait_label.text = ""
	if eat_spot:
		game.release_eat_spot(eat_spot)
		eat_spot = null
	target = game.customer_exit(global_position)

func _process(delta: float) -> void:
	if puppet:
		return
	if say_t > 0.0:
		say_t -= delta
		if say_t <= 0.0:
			say_label.text = ""
	# 길찾기로 테이블, 덤불을 돌아서 걷는다 (장터 밖 출입구는 길 밖이라 마지막엔 곧장 간다)
	var to := target - position
	to.y = 0
	if to.length() > 0.1:
		agent.target_position = target
		var nxt := agent.get_next_path_position()
		var dir := nxt - position
		dir.y = 0
		# 길 끝(장터 출입구처럼 길 밖 목적지 바로 앞)에 닿았으면 곧장 간다. 안 그러면 길 끝과 목적지 사이에서 떤다
		var end := agent.get_final_position()
		var end_gap := Vector2(target.x - end.x, target.z - end.z).length()
		if agent.is_navigation_finished() or dir.length() < 0.05 or to.length() < end_gap + 0.4:
			dir = to
		var step := dir.normalized() * 2.4 * delta
		position += step if step.length() < to.length() else to
		model.rotation.y = atan2(dir.x, dir.z)
		Anim.play(ap, "Walk")
	else:
		Anim.play(ap, "Idle")
		model.rotation.y = lerp_angle(model.rotation.y, 0.0, 0.1)
		if leaving:
			queue_free()
			return
		if state == "to_eat":
			state = "eating"
			eat_t = EAT_TIME
	if state == "eating":
		eat_t -= delta
		if eat_t <= 0.0:
			food.visible = false
			say(["잘 먹었다~", "맛있네!"].pick_random(), 1.5)
			leave()
		return
	if leaving or game.over or state != "queue":
		return
	if ready_to_order() and game.front_customer() == self:
		if say_label.text == "" and patience > PATIENCE - 1.0:
			say(ORDERS.pick_random(), 2.2)
		patience -= delta
		var n := int(ceil(patience / PATIENCE * 6.0))
		wait_label.text = "=".repeat(maxi(n, 0)) + "-".repeat(6 - maxi(n, 0))
		wait_label.modulate = Color(0.4, 1, 0.4).lerp(Color(1, 0.3, 0.2), 1.0 - patience / PATIENCE)
		if patience <= 0.0:
			say(["안 기다려!", "여기 장사 안 해요?!", "별점 하나 드릴게요."].pick_random(), 2.5)
			game.customer_gave_up(self)
			leave()
