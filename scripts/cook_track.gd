extends Control
## 조리 손맛 막대: 초록 칸, 왔다 갔다 하는 바늘, 아래쪽에 익은 정도.

var chef: Node

func _draw() -> void:
	if chef == null:
		return
	var w := size.x
	var bar := Rect2(0, 0, w, 26)
	draw_rect(bar, Color(0.25, 0.18, 0.12))
	if chef.cook_kind != "":
		var zw: float = chef.COOK[chef.cook_kind].zone * w
		var zx: float = chef.cook_zone * w - zw / 2.0
		draw_rect(Rect2(zx, 0, zw, 26), Color(0.35, 0.8, 0.35))
		var nx: float = chef.cook_needle * w
		draw_rect(Rect2(nx - 3, -4, 6, 34), Color(1, 0.95, 0.85))
	# 익은 정도
	var done: float = 1.0 - chef.work_left / maxf(chef.work_total, 0.01)
	draw_rect(Rect2(0, 34, w, 10), Color(0.25, 0.18, 0.12))
	draw_rect(Rect2(0, 34, w * clampf(done, 0.0, 1.0), 10), Color(0.95, 0.6, 0.2))
