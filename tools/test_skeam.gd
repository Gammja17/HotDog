extends SceneTree
# SKEAM 도전 과제가 사람이 한 일에만, 맞는 id 로 불리는지 확인한다.
# 실행: godot --headless --path . -s tools/test_skeam.gd
var g: Node
var fails := 0
var log: Array = []

func _initialize() -> void:
	Engine.set_meta("skeam_log", log)
	_run.call_deferred()

func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1

func wait(sec: float) -> void:
	await create_timer(sec).timeout

func load_mode(m: String) -> void:
	if g:
		g.queue_free()
		await wait(0.2)
	log.clear()
	get_root().get_node("Session").mode = m
	g = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(g)
	await wait(0.3)

func _run() -> void:
	await load_mode("chef")  # 사람 셰프, AI 강아지
	g.spawn_t = 999.0
	g.spawn_customer()
	g.customers[0].global_position = g._queue_pos(0)
	await wait(0.2)
	g.chef.global_position = g.stations["window"].global_position
	g.chef.set_hand("hotdog")
	g.chef.act()
	check(log.has("first_sale"), "사람 셰프가 팔면 first_sale")
	g.dog_ate()
	check(not log.has("first_bite"), "AI 강아지가 먹은 건 세지 않는다")
	g.sold = 9
	g.stars = 5.0
	g.spawn_customer()
	g.customers[0].global_position = g._queue_pos(0)
	await wait(0.2)
	g.chef.set_hand("hotdog")
	g.chef.act()
	check(log.has("chef_win") and log.has("chef_flawless"), "10개 팔고 별 다섯이면 chef_win, chef_flawless")

	await load_mode("dog")  # 사람 강아지, AI 셰프
	g.dog_ate()
	check(log.has("first_bite"), "사람 강아지가 먹으면 first_bite")
	g.dog.global_position = Vector3(0.86, 0, 1.55)
	g.dog.hide_now()
	check(log.has("rack_hide"), "진열대 빈칸에 숨으면 rack_hide")
	g.end_game("time")
	check(log.has("dog_sabotage") and not log.has("chef_win"), "시간이 다 가면 강아지 쪽 dog_sabotage만")

	await load_mode("watch")  # AI끼리
	g.dog_ate()
	g.end_game("full")
	check(log.is_empty(), "AI끼리 관전은 아무것도 세지 않는다")
	print("FAILS: ", fails)
	quit(fails)
