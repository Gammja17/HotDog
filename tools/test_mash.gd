extends SceneTree
# 소스 손맛 게임에서 Space를 막 누르면(연타) 끝나는지 확인한다.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	get_root().get_node("Session").mode = "chef"
	var g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await create_timer(0.5).timeout
	var chef = g.chef
	chef.set_hand("grilled")
	chef.global_position = g.stations["sauce"].global_position
	chef.act()
	var t := 0.0
	while chef.hand != "hotdog" and t < 12.0:
		chef.act()  # 초당 약 6번 연타
		await create_timer(0.16).timeout
		t += 0.16
	print("연타 결과: ", chef.hand, " (%.1f초)" % t)
	var ok1: bool = chef.hand == "hotdog" and t < 4.5
	# 초록 칸에서 딱 한 번 잘 누르면 바로 완성된다 (굽기, 소스)
	var ok2 := true
	for k in ["grill", "sauce"]:
		chef.set_hand("bun" if k == "grill" else "grilled")
		chef.global_position = g.stations[k].global_position
		await create_timer(0.1).timeout
		chef.act()
		var want: String = "grilled" if k == "grill" else "hotdog"
		var tt := 0.0
		while chef.hand != want and tt < 8.0:
			if chef.cook_lock <= 0.0:
				chef.cook_needle = chef.cook_zone
				chef.act()
			await create_timer(0.05).timeout
			tt += 0.05
		print("  초록 칸만 노리기 %s: %s (%.1f초)" % [k, chef.hand, tt])
		ok2 = ok2 and chef.hand == want
	print("FAILS: ", 0 if ok1 and ok2 else 1)
	quit()
