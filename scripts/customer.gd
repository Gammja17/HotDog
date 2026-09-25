extends Node3D
## 손님. 창구 앞 줄에 서서 핫도그를 기다린다. 오래 기다리면 화내고 떠난다.

const PATIENCE := 45.0
const ORDERS := ["핫도그 하나요!", "하나 주세요~", "케첩 많이요!", "빨리요, 버스 와요!"]

var game: Node
var target := Vector3.ZERO
var patience := PATIENCE
var leaving := false
var served := false

@onready var model: Node3D = $Model
@onready var say_label: Label3D = $Say
@onready var wait_label: Label3D = $Wait
@onready var hat: MeshInstance3D = $Hat
var ap: AnimationPlayer
var say_t := 0.0

func _ready() -> void:
	ap = Anim.setup(model)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(randf(), 0.6, 0.9)
	hat.material_override = mat
	wait_label.text = ""

func say(text: String, t := 2.0) -> void:
	say_label.text = text
	say_t = t

## 줄 맨 앞에 도착해서 주문할 수 있는 상태인가
func ready_to_order() -> bool:
	return not leaving and position.distance_to(target) < 0.3

func serve(bitten: bool) -> void:
	served = true
	if bitten:
		say(["사장님! 여기 털 나왔어요!", "이거 누가 먹다 준 거예요?!", "반쪽밖에 없잖아요!"].pick_random(), 2.5)
	else:
		say(["고마워요!", "냄새 좋다~", "잘 먹을게요!"].pick_random(), 1.8)
	leave()

func leave() -> void:
	leaving = true
	wait_label.text = ""
	target = game.customer_exit()

func _process(delta: float) -> void:
	if say_t > 0.0:
		say_t -= delta
		if say_t <= 0.0:
			say_label.text = ""
	var to := target - position
	to.y = 0
	if to.length() > 0.1:
		var step := to.normalized() * 2.4 * delta
		position += step if step.length() < to.length() else to
		model.rotation.y = atan2(to.x, to.z)
		Anim.play(ap, "Walk")
	else:
		Anim.play(ap, "Idle")
		model.rotation.y = lerp_angle(model.rotation.y, 0.0, 0.1)
		if leaving:
			queue_free()
			return
	if leaving or game.over:
		return
	if ready_to_order() and game.front_customer() == self:
		if say_label.text == "" and patience > PATIENCE - 1.0:
			say(ORDERS.pick_random(), 2.2)
		patience -= delta
		var n := int(ceil(patience / PATIENCE * 6.0))
		wait_label.text = "●".repeat(maxi(n, 0)) + "○".repeat(6 - maxi(n, 0))
		wait_label.modulate = Color(0.4, 1, 0.4).lerp(Color(1, 0.3, 0.2), 1.0 - patience / PATIENCE)
		if patience <= 0.0:
			say(["안 기다려!", "여기 장사 안 해요?!", "별점 하나 드릴게요."].pick_random(), 2.5)
			game.customer_gave_up(self)
			leave()
