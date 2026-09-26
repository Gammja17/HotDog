extends SceneTree
# 스토어용 장면을 꾸며서 찍는다. godot --path . --resolution 1920x1080 -s tools/shot_store.gd -- --scene=cook
var g: Node

func _initialize() -> void:
	_run.call_deferred()

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func save(name: String) -> void:
	get_root().get_texture().get_image().save_png("res://shot_store_%s.png" % name)

func _run() -> void:
	var scene := "cook"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene = a.trim_prefix("--scene=")
	get_root().get_node("Session").mode = "dog" if scene == "plaza" else "chef"
	g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await wait(0.6)
	g.spawn_t = 999.0
	match scene:
		"cook":  # 1인칭: 그릴에서 소시지를 굽는 중
			g.chef.global_position = g.stations["grill"].global_position
			g.chef.set_hand("bun")
			g.chef.act()
			await wait(1.3)
			g.chef.cook_lock = 0.0
			g.chef.cook_needle = g.chef.cook_zone
			g.chef.act()
			await wait(0.15)
			save(scene)
		"window":  # 1인칭: 창구 너머 줄 선 손님과 장터
			for i in 3:
				g.spawn_customer()
				g.customers[-1].global_position = g._queue_pos(i)
			for i in 4:
				g.spawn_eating_customer(i * 2)
			g.chef.global_position = g.stations["window"].global_position + Vector3(0, 0, 0.6)
			g.chef.set_hand("hotdog")
			await wait(3.6)  # 시작 안내 문구가 사라질 때까지
			for c in g.customers:
				c.say_label.text = ""
			g.chef.set_look(0.0, -0.05)
			await wait(0.3)
			save(scene)
		"plaza":  # 위에서: 테이블에서 먹는 손님들 옆에 핫도그로 변장한 강아지
			for i in 6:
				g.spawn_eating_customer(i)
			var c = g.eating_customers()[0]
			g.dog.global_position = c.global_position + Vector3(0.9, 0, 0.9)
			await wait(0.4)
			g.dog.hide_now()
			await wait(3.0)
			save(scene)
	quit()
