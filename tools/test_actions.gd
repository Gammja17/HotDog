extends SceneTree
# 사람이 누르는 행동(셰프 조리/진열/판매, 강아지 변장/먹기)이 오류 없이 도는지 확인한다.
# 실행: godot --path . -s tools/test_actions.gd
var g: Node
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func _run() -> void:
	get_root().get_node("Session").mode = "duo"
	g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await wait(0.3)
	var chef = g.chef
	var dog = g.dog
	dog.global_position = Vector3(5, 0, 3)

	chef.global_position = g.stations["bread"].global_position
	chef.act()
	await wait(1.0)
	check(chef.hand == "bun", "빵을 집는다")
	chef.global_position = g.stations["grill"].global_position
	chef.act()
	await wait(5.3)  # 1인칭 셰프: 손맛 게임을 안 하면 5초에 익는다
	check(chef.hand == "grilled", "그릴에 굽는다")
	# 손맛: 초록 칸에서 누르면 빨리 익고, 밖에서 누르면 늦어진다
	chef.set_hand("bun")
	chef.global_position = g.stations["grill"].global_position
	chef.act()
	await wait(0.2)
	var left0: float = chef.work_left
	chef.cook_needle = chef.cook_zone
	chef.act()
	check(chef.work_left < left0 - 1.0, "초록 칸에서 누르면 빨리 익는다")
	await wait(0.4)  # 연타 방지 시간
	left0 = chef.work_left
	chef.cook_needle = fmod(chef.cook_zone + 0.5, 1.0)
	chef.act()
	check(chef.work_left > left0, "초록 칸 밖에서 누르면 늦어진다")
	await wait(4.0)
	check(chef.hand == "grilled", "손맛 게임 뒤에도 구워진다")
	chef.global_position = g.stations["sauce"].global_position
	chef.act()
	await wait(2.4)
	check(chef.hand == "hotdog", "소스를 뿌린다")
	var before: int = g.rack.count_items()
	chef.global_position = Vector3(0, 0, 1.65)
	chef.act()
	check(g.rack.count_items() == before + 1 and chef.hand == "", "진열대에 올린다")
	chef.act()
	check(chef.hand == "hotdog", "진열대에서 집는다")

	g.spawn_customer()
	for i in g.customers.size():
		g.customers[i].global_position = g._queue_pos(i)
	await wait(0.2)
	var n: int = g.customers.size()
	chef.global_position = g.stations["window"].global_position
	chef.act()
	check(chef.hand == "" and g.customers.size() == n - 1, "손님에게 판다")

	# 강아지: 진열대 옆에서 먹고, 빈칸에 숨고, 부르기에 꼬리가 반응한다
	dog.global_position = Vector3(0, 0, 1.55)
	var eaten: int = g.eaten
	dog.try_eat()
	await wait(1.7)
	check(g.eaten == eaten + 1, "강아지가 진열대 핫도그를 먹는다")
	check(g.traces.size() > 0, "부스러기 흔적이 남는다")
	dog.toggle_hide()
	await wait(0.3)
	check(dog.hidden and dog.in_slot(), "진열대 빈칸에 숨는다")
	chef.global_position = Vector3(0, 0, 2.2)
	chef.call_dog()
	await wait(0.5)
	check(dog.tail > 10.0, "\"착한 아이지~?\"에 꼬리가 들썩인다")
	dog.hold_tail()
	dog.toggle_hide()
	await wait(0.3)
	check(not dog.hidden and not dog.in_slot(), "진열대에서 뛰어내린다")

	chef.global_position = dog.global_position + Vector3(0.8, 0, 0)
	chef.set_look(-PI / 2.0, -0.3)  # 등을 돌리고 있으면 (+x를 봄)
	chef.act()
	check(g.caught == 0, "등 뒤 강아지는 못 잡는다")
	chef.set_look(PI / 2.0, -0.3)  # 돌아서 강아지(-x)를 보면
	var eaten0: int = g.eaten
	chef.act()
	check(g.caught == 1 and not g.over, "보고 있는 바로 앞 강아지를 잡아도 게임은 계속된다")
	check(g.eaten == maxi(eaten0 - 1, 0), "잡히면 먹은 소시지 하나를 뱉는다")
	await wait(1.8)
	check(not g.chef.in_truck(dog.global_position), "잡힌 강아지는 장터로 던져진다")
	await wait(2.5)
	check(not dog.stopped, "어질어질한 뒤 다시 움직인다")

	# 헛찌르기: 멀쩡한 바닥 핫도그를 찌르면 별점 -0.5
	var decoy: Node3D = g.decoys[1]
	chef.global_position = decoy.global_position + Vector3(0, 0, 1.0)
	chef.set_look(0.0, -0.5)  # -z (핫도그 쪽)
	var stars0: float = g.stars
	chef.act()
	await wait(0.8)
	check(is_equal_approx(g.stars, stars0 - 0.5), "멀쩡한 핫도그를 찌르면 별점 -0.5")

	# 장터: 테이블에서 먹는 손님 핫도그를 뺏는다
	for c in g.customers.duplicate():
		c.queue_free()
	g.customers.clear()
	g.spawn_customer()
	var cu = g.customers[0]
	cu.global_position = g._queue_pos(0)
	await wait(0.2)
	chef.global_position = g.stations["window"].global_position
	chef.set_hand("hotdog")
	chef.act()
	var tt := 0.0
	while not cu.has_food() and tt < 12.0:
		await wait(0.2)
		tt += 0.2
	check(cu.has_food(), "핫도그를 산 손님은 장터 테이블에서 먹는다")
	dog.global_position = cu.global_position + Vector3(0.6, 0, 0.5)
	var eaten1: int = g.eaten
	stars0 = g.stars
	dog.try_eat()
	await wait(1.8)
	check(g.eaten == eaten1 + 1 and g.stars < stars0 and not cu.has_food(), "강아지가 손님 핫도그를 뺏어 먹는다 (별점 -0.5)")

	# 짖기: 줄 선 손님이 겁먹고 떠난다
	g.spawn_customer()
	var q = g.customers[g.customers.size() - 1]
	q.global_position = g._queue_pos(g.customers.size() - 1)
	await wait(0.2)
	dog.global_position = q.global_position + Vector3(1.5, 0, 0)
	dog.bark_cd = 0.0
	dog.bark()
	await wait(0.2)
	check(not g.customers.has(q) and q.state == "leaving", "짖으면 줄 선 손님이 겁먹고 떠난다")
	check(dog.bark_cd > 0.0, "짖기는 한동안 다시 못 한다")
	print("FAILS: ", fails)
	quit(fails)
