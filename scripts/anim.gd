class_name Anim
## glb 모델의 AnimationPlayer를 찾아서 이름 끝부분(Idle, Walk ...)으로 재생한다.

static func setup(model: Node) -> AnimationPlayer:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return null
	var ap: AnimationPlayer = found[0]
	for n in ap.get_animation_list():
		for loop in ["Idle", "Walk", "Run", "Working", "Idle_Eating"]:
			if n.ends_with("|" + loop):
				ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	return ap

static func play(ap: AnimationPlayer, suffix: String, speed := 1.0) -> void:
	if ap == null:
		return
	for n in ap.get_animation_list():
		if n.ends_with("|" + suffix):
			if ap.current_animation != n:
				ap.play(n, 0.15, speed)
			return
