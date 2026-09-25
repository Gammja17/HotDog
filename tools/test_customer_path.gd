extends SceneTree
# 손님이 장터 테이블까지 걸어갈 때 테이블을 뚫고 지나가지 않는지 확인한다.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	get_root().get_node("Session").mode = "chef"
	var g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await create_timer(0.5).timeout
	var tables: Array = []
	for n in g.get_node("Truck/Nav").get_children():
		if n.name.begins_with("Table"):
			tables.append(n.global_position + Vector3(0.69, 0, -0.8))  # 원점이 모서리라 가운데로
	g.spawn_t = 999.0  # 게임이 알아서 손님을 부르지 않게
	g.dog.stopped = true  # 강아지가 손님을 건드리지 않게
	g.dog.visible = false
	for c in g.customers.duplicate():
		c.queue_free()
	g.customers.clear()
	for i in 6:
		g.spawn_customer()
	var cs: Array = g.customers.duplicate()
	g.customers.clear()
	for i in cs.size():
		var c = cs[i]
		c.global_position = g._queue_pos(0) + Vector3(i * 0.3, 0, 0)
		c.food.visible = true
		c.eat_spot = g.claim_eat_spot(c)
		c.state = "to_eat"
		c.target = c.eat_spot.global_position
	var worst := 99.0
	var arrived := 0
	for t in 120:
		await create_timer(0.1).timeout
		for c in cs:
			for tp in tables:
				worst = minf(worst, Vector2(c.global_position.x - tp.x, c.global_position.z - tp.z).length())
	for c in cs:
		if c.state == "eating":
			arrived += 1
		else:
			print("  못 온 손님: 상태=%s 위치=%s 목표=%s 다음=%s 끝남=%s" % [c.state, c.global_position.snapped(Vector3.ONE*0.1), c.target.snapped(Vector3.ONE*0.1), c.agent.get_next_path_position().snapped(Vector3.ONE*0.1), c.agent.is_navigation_finished()])
	print("테이블 가운데와 가장 가까웠던 거리: %.2f (테이블 반지름 0.69)" % worst)
	print("테이블에 도착한 손님: %d / %d" % [arrived, cs.size()])
	# 먹고 떠나는 손님은 출입구에서 떨지 않고 사라져야 한다
	for c in cs:
		c.eat_t = 0.0
	var gone := 0
	for t in 150:
		await create_timer(0.1).timeout
	for c in cs:
		if not is_instance_valid(c):
			gone += 1
		else:
			print("  남은 손님: 상태=%s 위치=%s 목표=%s 길끝=%s" % [c.state, c.global_position.snapped(Vector3.ONE*0.1), c.target.snapped(Vector3.ONE*0.1), c.agent.get_final_position().snapped(Vector3.ONE*0.1)])
	print("다 먹고 장터 밖으로 나간 손님: %d / %d" % [gone, cs.size()])
	print("FAILS: ", 0 if worst > 0.7 and arrived == cs.size() and gone == cs.size() else 1)
	quit()
