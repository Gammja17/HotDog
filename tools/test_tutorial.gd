extends SceneTree
# 연습 두 편을 처음부터 끝까지 자동으로 해 보고, 단계가 막히지 않는지 확인한다.
# 실행: godot --path . -s tools/test_tutorial.gd
var g: Node
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func wait(sec: float) -> void:
	await create_timer(sec).timeout

## 지금 단계가 끝날 때까지 (최대 limit초) 기다린다
func until_step(n: int, limit := 15.0) -> bool:
	var t := 0.0
	while g.tutorial.i < n and t < limit:
		await wait(0.1)
		t += 0.1
	var ok: bool = g.tutorial.i >= n
	print(("  ok   " if ok else "  FAIL ") + "단계 %d 통과" % n)
	if not ok:
		fails += 1
		print("       멈춘 곳: ", g.tutorial.panel.get_node("%Text").text.replace("\n", " / "))
	return ok

func load_mode(m: String) -> void:
	if g:
		g.queue_free()
		await wait(0.2)
	get_root().get_node("Session").mode = m
	g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await wait(0.3)

func _run() -> void:
	print("== 셰프 연습")
	await load_mode("tut_chef")
	var chef = g.chef
	var st = g.stations
	chef.global_position = st["bread"].global_position; chef.act()
	await until_step(1)
	chef.global_position = st["grill"].global_position; chef.act()
	await until_step(2)
	chef.global_position = st["sauce"].global_position; chef.act()
	await until_step(3)
	await wait(4.0)  # 손님이 창구까지 걸어온다
	chef.global_position = st["window"].global_position; chef.act()
	await until_step(4)
	for k in ["bread", "grill", "sauce"]:
		chef.global_position = st[k].global_position; chef.act()
		await wait(2.3)
	chef.global_position = Vector3(0, 0, 1.65); chef.act()
	await until_step(5)
	chef.global_position = Vector3(4.2, 0, 1.6)
	await until_step(6)
	chef.call_dog()
	await until_step(7)
	chef.global_position = g.dog.global_position + Vector3(-0.6, 0, 0)
	chef.act()
	await until_step(8)
	print(("  ok   " if g.hud.result.visible else "  FAIL ") + "연습 끝 창")
	if not g.hud.result.visible: fails += 1

	print("== 강아지 연습")
	await load_mode("tut_dog")
	var dog = g.dog
	chef = g.chef
	dog.global_position += Vector3(-2, 0, 0)
	await until_step(1)
	dog.global_position = Vector3(0.86, 0, 1.55)
	await until_step(2)
	dog.try_eat()
	await until_step(3)
	await until_step(4, 8.0)
	dog.toggle_hide()
	await until_step(5)
	await until_step(6, 9.0)
	await wait(3.0)  # 진열대 빈칸 = 핫도그 옆이라 킁킁이 찬다
	dog.toggle_hide()
	await until_step(7)
	# 마지막: 사장님 근처에 숨고, 부르면 꼬리를 참는다
	dog.global_position = Vector3(-0.2, 0, 1.6)
	dog.toggle_hide()
	# 먼저 연타를 안 하면: "왈!" 하고 들켜서 다시 해야 한다
	var t := 0.0
	while not g.tutorial.mem.get("failed", false) and t < 10.0:
		await wait(0.1)
		t += 0.1
	var failed_ok: bool = g.tutorial.mem.get("failed", false) and not dog.hidden and g.tutorial.i == 7
	print(("  ok   " if failed_ok else "  FAIL ") + "연타 안 하면 들키고 같은 단계에 남는다")
	if not failed_ok: fails += 1
	await wait(0.5)
	dog.toggle_hide()
	t = 0.0
	while g.tutorial.i < 8 and t < 20.0:
		if dog.hidden and dog.tail_pending + dog.tail > 20.0:
			dog.hold_tail()
		await wait(0.1)
		t += 0.1
	var ok: bool = g.tutorial.i >= 8
	print(("  ok   " if ok else "  FAIL ") + "단계 8 통과 (꼬리 참기)")
	if not ok:
		fails += 1
		print("       멈춘 곳: ", g.tutorial.panel.get_node("%Text").text.replace("\n", " / "))
	print(("  ok   " if g.hud.result.visible else "  FAIL ") + "연습 끝 창")
	if not g.hud.result.visible: fails += 1
	print("FAILS: ", fails)
	quit(fails)
