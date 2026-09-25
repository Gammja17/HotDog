extends Control
## 1인칭 셰프 화면 요소: 가운데 점, "Space: 빵 꺼내기" 같은 안내, 내가 한 말, 조리 손맛 창.

var chef: Node

func _process(_delta: float) -> void:
	if chef == null:
		return
	%Prompt.text = chef.prompt_text()
	%Subtitle.text = chef.say_label.text
	var cooking: bool = chef.cook_kind != "" and chef.work_left > 0.0
	%Cook.visible = cooking or (chef.work_left > 0.0 and chef.work_kind != "poke")
	if not %Cook.visible:
		return
	if cooking:
		%CookTitle.text = chef.COOK[chef.cook_kind].text
		%Flash.text = chef.cook_flash if chef.cook_flash_t > 0.0 else ""
		%Flash.modulate = Color(0.5, 1, 0.5) if chef.cook_flash == "좋아!" else Color(1, 0.5, 0.4)
	else:
		%CookTitle.text = "빵 꺼내는 중..."
		%Flash.text = ""
	%Track.chef = chef
	%Track.queue_redraw()
