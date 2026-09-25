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
	await create_timer(1.0).timeout
	g.chef.cook_lock = 0.0
	g.chef.cook_needle = g.chef.cook_zone
	g.chef.act()
	await create_timer(0.1).timeout
	get_root().get_texture().get_image().save_png("res://shot_cook.png")
	quit()
