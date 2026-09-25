extends SceneTree
# 1인칭 셰프가 그릴에서 굽는 화면을 찍는다. godot --path . -s tools/shot_cook.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	get_root().get_node("Session").mode = "chef"
	var g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await create_timer(0.5).timeout
	g.chef.global_position = g.stations["grill"].global_position
	g.chef.set_hand("bun")
	g.chef.act()
	await create_timer(1.4).timeout
	get_root().get_texture().get_image().save_png("res://shot_cook.png")
	g.chef.work_left = 0.0
	g.chef.cook_kind = ""
	g.chef.global_position = Vector3(1.5, 0, 3.0)
	g.chef.set_look(PI * 0.85, -0.3)
	await create_timer(0.6).timeout
	get_root().get_texture().get_image().save_png("res://shot_room.png")
	quit()
