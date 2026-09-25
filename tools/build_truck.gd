extends SceneTree
# 트럭 + 바깥 장터 맵(scenes/truck.tscn)을 만드는 도구.
# 트럭 안(x -6..6, z -4..4)은 셰프 구역, 둘레의 장터(x -14..15, z -16..8)는 강아지 구역.
# 트럭 오른쪽 벽에 뒷문(z 1.9..3.3)이 있어 강아지가 드나든다.
# 실행: godot --headless --path . -s tools/build_truck.gd
# 가구 배치를 바꾸고 싶으면 여기 좌표를 고치고 다시 실행한다. (에디터에서 직접 고쳐도 된다)

const S := 2.0          # Kenney 가구 배율 (냉장고 0.92 → 1.84)
const HOTDOG_S := 1.4   # 진열대 핫도그 배율 (강아지 몸길이와 맞춘다)

var top: Node3D
var nav: NavigationRegion3D

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	top = Node3D.new()
	top.name = "Truck"
	get_root().add_child(top)

	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2b2f3a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#fff4e0")
	e.ambient_light_energy = 0.36
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	_add(top, env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	_add(top, sun)

	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.0
	nm.agent_max_climb = 0.25
	nav.navigation_mesh = nm
	_add(top, nav)

	_floor()
	_walls()
	_fp_shell()
	_kitchen()
	_rack()
	_clutter()
	_plaza()
	_markers()

	await process_frame
	await process_frame
	nav.bake_navigation_mesh(false)
	print("nav polygons: ", nav.navigation_mesh.get_polygon_count())

	var packed := PackedScene.new()
	var err := packed.pack(top)
	if err == OK:
		err = ResourceSaver.save(packed, "res://scenes/truck.tscn")
	print("saved truck.tscn: ", err)
	quit()

func _add(parent: Node, n: Node) -> Node:
	parent.add_child(n)
	n.owner = top
	return n

func _box_body(name: String, parent: Node, center: Vector3, size: Vector3, color = null) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = name
	b.position = center
	_add(parent, b)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	_add(b, cs)
	if color != null:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		bm.material = mat
		mi.mesh = bm
		_add(b, mi)
	return b

func _model_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var c: Node = m
		while c != n:
			if c is Node3D:
				t = c.transform * t
			c = c.get_parent()
		var b: AABB = t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# 가구 하나를 놓는다. pos는 모델 원점 위치. collide면 모델 크기만큼 충돌 상자를 붙인다.
func _prop(path: String, name: String, parent: Node, pos: Vector3, rot_y := 0.0, sc := S, collide := true) -> Node3D:
	var model: Node3D = load(path).instantiate()
	model.name = "Model"
	model.scale = Vector3.ONE * sc
	var holder: Node3D
	if collide:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = name
	holder.position = pos
	holder.rotation.y = deg_to_rad(rot_y)
	_add(parent, holder)
	_add(holder, model)
	if collide:
		var box := _model_aabb(model)
		box = AABB(box.position * sc, box.size * sc)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = box.size
		cs.shape = sh
		cs.position = box.get_center()
		_add(holder, cs)
	return holder

func _floor() -> void:
	# 트럭 바닥 12 x 8 (x -6..6, z -4..4): 두 톤 체크무늬. 바깥은 어두운 길바닥
	var floor_a := _mat(Color("#e3c690"))
	var floor_b := _mat(Color("#cda66a"))
	for ix in range(6):
		for iz in range(4):
			var tile := MeshInstance3D.new()
			tile.name = "Floor_%d_%d" % [ix, iz]
			var tm := PlaneMesh.new()
			tm.size = Vector2(2, 2)
			tile.mesh = tm
			tile.material_override = floor_a if (ix + iz) % 2 == 0 else floor_b
			tile.position = Vector3(-5 + ix * 2, 0.0, -3 + iz * 2)
			_add(top, tile)
	_box_body("Ground", nav, Vector3(0.5, -0.1, -4), Vector3(29, 0.2, 24))
	var plaza := MeshInstance3D.new()
	plaza.name = "PlazaFloor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(29, 24)
	plaza.mesh = pm
	plaza.material_override = _mat(Color("#8f8778"))
	plaza.position = Vector3(0.5, -0.01, -4)
	_add(top, plaza)
	var grass := MeshInstance3D.new()
	grass.name = "Grass"
	var gm := PlaneMesh.new()
	gm.size = Vector2(70, 60)
	grass.mesh = gm
	grass.material_override = _mat(Color("#4f6b3c"))
	grass.position = Vector3(0.5, -0.03, -4)
	_add(top, grass)

func _walls() -> void:
	var wall_col := Color("#e2a63a")  # 노란 푸드트럭 벽 (바닥보다 진하게)
	_box_body("WallLeft", nav, Vector3(-6.15, 0.6, 0), Vector3(0.3, 1.2, 8.3), wall_col)
	# 오른쪽 벽: 뒷문(z 1.9..3.3)을 비워 둔다
	_box_body("WallRightA", nav, Vector3(6.15, 0.6, -1.125), Vector3(0.3, 1.2, 6.05), wall_col)
	_box_body("WallRightB", nav, Vector3(6.15, 0.6, 3.725), Vector3(0.3, 1.2, 0.85), wall_col)
	_box_body("WallBackL", nav, Vector3(-3.075, 1.1, -4.15), Vector3(6.15, 2.2, 0.3), wall_col)
	_box_body("WallBackR", nav, Vector3(4.9, 1.1, -4.15), Vector3(2.5, 2.2, 0.3), wall_col)
	# 앞쪽은 카메라 쪽이라 벽 대신 낮은 턱과 보이지 않는 막
	_box_body("FrontStep", nav, Vector3(0, 0.1, 4.15), Vector3(12.6, 0.2, 0.3), Color("#b8962f"))
	var guard := _box_body("FrontGuard", top, Vector3(0, 1.0, 4.15), Vector3(12.6, 2.0, 0.3))
	guard.collision_layer = 1
	# 창구 위 차양
	var aw := MeshInstance3D.new()
	aw.name = "Awning"
	var bm := BoxMesh.new()
	bm.size = Vector3(3.6, 0.08, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#d9423a")
	bm.material = mat
	aw.mesh = bm
	aw.position = Vector3(1.72, 2.3, -4.3)
	_add(top, aw)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _flat_box(name: String, parent: Node, pos: Vector3, size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	_add(parent, mi)
	return mi

const STATION_COLOR := {
	"fridge": Color("#7fbfe6"), "bread": Color("#f2c230"), "grill": Color("#e0503a"),
	"sauce": Color("#f08a30"), "window": Color("#4fb860"),
}

## 1인칭 셰프 화면에만 보이는 트럭 껍데기: 앞벽, 높은 옆벽, 천장.
## 위에서 내려다보는 카메라를 가리지 않도록 렌더 레이어 8에만 둔다. (충돌은 기존 벽과 막이 맡는다)
func _fp_shell() -> void:
	var g := Node3D.new()
	g.name = "FirstPersonShell"
	_add(top, g)
	var wall := Color("#b98a3a")
	var parts := [
		["Front", Vector3(0, 1.4, 4.15), Vector3(12.6, 2.8, 0.3), wall],
		["LeftUpper", Vector3(-6.15, 2.0, 0), Vector3(0.3, 1.6, 8.3), wall],
		["RightUpperA", Vector3(6.15, 2.0, -1.125), Vector3(0.3, 1.6, 6.05), wall],
		["RightUpperB", Vector3(6.15, 2.0, 3.725), Vector3(0.3, 1.6, 0.85), wall],
		["DoorTop", Vector3(6.15, 2.6, 2.6), Vector3(0.3, 0.4, 1.4), wall],
		["BackLeftUpper", Vector3(-3.075, 2.5, -4.15), Vector3(6.15, 0.6, 0.3), wall],
		["BackRightUpper", Vector3(4.9, 2.5, -4.15), Vector3(2.5, 0.6, 0.3), wall],
		["Ceiling", Vector3(0, 2.85, 0), Vector3(12.6, 0.1, 8.6), Color("#8c6a3a")],
	]
	for p in parts:
		var mi := _flat_box(p[0], g, p[1], p[2], p[3])
		mi.layers = 8
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _station(kind: String, at: Vector3, label: String) -> void:
	var st := Node3D.new()
	st.name = "Station_" + kind
	st.set_script(load("res://scripts/station.gd"))
	st.set("kind", kind)
	st.position = at
	st.add_to_group("station", true)
	_add(top, st)
	var c: Color = STATION_COLOR[kind]
	_flat_box("Mat", st, Vector3(0, 0.012, 0.05), Vector3(0.84, 0.02, 0.8), c)
	var l := Label3D.new()
	l.name = "Sign"
	l.font = load("res://assets/fonts/DoHyeon-Regular.ttf")
	l.text = label
	l.font_size = 72
	l.outline_size = 18
	l.modulate = c.lightened(0.45)
	l.outline_modulate = c.darkened(0.6)
	l.position = Vector3(0, 2.3, -0.5)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.layers = 2  # 위에서 보는 화면용 큰 간판
	_add(st, l)
	# 1인칭 셰프 화면용: 조리대 앞에 붙은 작은 간판
	var f := Label3D.new()
	f.name = "SignFP"
	f.font = l.font
	f.text = label
	f.font_size = 44
	f.outline_size = 12
	f.modulate = l.modulate
	f.outline_modulate = l.outline_modulate
	f.pixel_size = 0.004
	f.position = Vector3(0, 1.75, -1.2) if kind != "window" else Vector3(0, 2.05, -1.3)
	f.layers = 8
	_add(st, f)

func _kitchen() -> void:
	var back := -4.0 + 0.9  # 가구 원점 z (뒤판이 벽에 붙도록)
	_prop("res://assets/furniture/kitchenFridge.glb", "Fridge", nav, Vector3(-5.95, 0, -4.0 + 0.56))
	_prop("res://assets/furniture/kitchenCabinet.glb", "BreadCounter", nav, Vector3(-5.0, 0, back))
	_prop("res://assets/furniture/kitchenStove.glb", "Grill", nav, Vector3(-4.0, 0, back))
	_prop("res://assets/furniture/kitchenCabinet.glb", "SauceCounter", nav, Vector3(-3.0, 0, back))
	_prop("res://assets/furniture/kitchenSink.glb", "Sink", nav, Vector3(-2.0, 0, back))
	_prop("res://assets/furniture/kitchenCabinetUpper.glb", "Upper1", top, Vector3(-5.0, 1.5, -4.0 + 0.42), 0, S, false)
	_prop("res://assets/furniture/kitchenCabinetUpper.glb", "Upper2", top, Vector3(-3.0, 1.5, -4.0 + 0.42), 0, S, false)
	# 조리대 위 소품
	for i in range(3):
		_prop("res://assets/food/bread.glb", "Bread%d" % i, top, Vector3(-4.6, 0.92 + i * 0.07, -3.55), i * 20, 1.6, false)
	_prop("res://assets/food/frying-pan.glb", "Pan", top, Vector3(-3.55, 0.92, -3.3), 90, 1.0, false)
	_prop("res://assets/food/bottle-ketchup.glb", "Ketchup", top, Vector3(-2.75, 0.92, -3.55), 0, 0.35, false)
	_prop("res://assets/food/bottle-musterd.glb", "Mustard", top, Vector3(-2.45, 0.92, -3.55), 0, 0.35, false)
	# 판매 창구: 바 카운터 네 칸
	for i in range(4):
		_prop("res://assets/furniture/kitchenBar.glb", "Bar%d" % i, nav, Vector3(0.0 + i * 0.86, 0, -4.0 + 0.42))
	_prop("res://assets/furniture/kitchenBarEnd.glb", "BarEnd", nav, Vector3(3.44, 0, -4.0 + 0.42))

	_station("fridge", Vector3(-5.52, 0, -2.6), "냉장고")
	_station("bread", Vector3(-4.57, 0, -2.6), "빵")
	_station("grill", Vector3(-3.57, 0, -2.6), "그릴")
	_station("sauce", Vector3(-2.57, 0, -2.6), "소스")
	_station("window", Vector3(1.72, 0, -2.9), "판매 창구")
	(top.get_node("Station_window/Mat") as MeshInstance3D).mesh.size = Vector3(3.2, 0.02, 0.8)

func _rack() -> void:
	# 가운데 섬: 진열대 (핫도그 6칸). 강아지가 빈칸에 숨을 수 있다.
	var rack := Node3D.new()
	rack.name = "Rack"
	rack.set_script(load("res://scripts/rack.gd"))
	rack.position = Vector3(0, 0, 0.6)
	rack.add_to_group("rack", true)
	_add(top, rack)
	for i in range(3):
		_prop("res://assets/furniture/kitchenCabinet.glb", "RackBase%d" % i, nav, Vector3(-1.29 + i * 0.86, 0, 0.6 + 0.45))
	var slots := Node3D.new()
	slots.name = "Slots"
	_add(rack, slots)
	var n := 0
	for row in range(2):
		for col in range(3):
			var m := Marker3D.new()
			m.name = "Slot%d" % n
			m.position = Vector3(-0.86 + col * 0.86, 0.92, -0.2 + row * 0.5)
			_add(slots, m)
			# 칸 접시: 빈칸도 한눈에 보이게
			_flat_box("Plate", m, Vector3(0, -0.005, 0), Vector3(0.78, 0.012, 0.42), Color("#fff4d8"))
			n += 1
	_flat_box("Warmer", rack, Vector3(0, 0.905, 0.05), Vector3(2.62, 0.02, 1.0), Color("#c9362e"))
	var l := Label3D.new()
	l.name = "Sign"
	l.font = load("res://assets/fonts/DoHyeon-Regular.ttf")
	l.text = "진열대"
	l.font_size = 72
	l.outline_size = 18
	l.modulate = Color("#ffd9d0")
	l.outline_modulate = Color("#5a1410")
	l.position = Vector3(0, 1.8, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.layers = 2
	_add(rack, l)
	var f := Label3D.new()
	f.name = "SignFP"
	f.font = l.font
	f.text = "진열대"
	f.font_size = 44
	f.outline_size = 12
	f.modulate = l.modulate
	f.outline_modulate = l.outline_modulate
	f.pixel_size = 0.004
	f.position = Vector3(0, 1.35, 0.05)
	f.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	f.layers = 8
	_add(rack, f)

func _clutter() -> void:
	_prop("res://assets/furniture/trashcan.glb", "Trash", nav, Vector3(5.3, 0, 0.4), 0, 1.3)
	_prop("res://assets/furniture/cardboardBoxClosed.glb", "Box1", nav, Vector3(5.0, 0, -1.2), 10)
	_prop("res://assets/furniture/cardboardBoxOpen.glb", "Box2", nav, Vector3(4.6, 0, -2.2), -15)
	_prop("res://assets/furniture/cardboardBoxClosed.glb", "Box3", nav, Vector3(-5.6, 0, 1.4), 5)
	_prop("res://assets/furniture/cardboardBoxClosed.glb", "Box4", nav, Vector3(-5.5, 0, 2.6), -20)
	_prop("res://assets/furniture/stoolBar.glb", "Stool1", nav, Vector3(3.0, 0, 1.8), 30)
	_prop("res://assets/furniture/stoolBar.glb", "Stool2", nav, Vector3(-2.8, 0, 2.6), -10)

const TABLES := [Vector3(-8.0, 0, -8.0), Vector3(-3.5, 0, -10.5), Vector3(2.5, 0, -11.0), Vector3(8.0, 0, -9.0), Vector3(10.8, 0, -3.8)]
const N := 3.0  # Nature Kit 배율 (덤불 0.24 → 0.72)

## 트럭 밖 장터: 스탠드 테이블, 덤불, 나무, 쓰레기통, 옆 가게 천막, 가로등, 울타리
func _plaza() -> void:
	var p := Node3D.new()
	p.name = "Plaza"
	_add(top, p)
	for i in TABLES.size():
		_prop("res://assets/plaza/tableRound.glb", "Table%d" % i, nav, TABLES[i] + Vector3(-0.69, 0.54, 0.8), 0, S)
	_prop("res://assets/plaza/bench.glb", "Bench0", nav, Vector3(-11.8, 0, -4.4), 90)
	_prop("res://assets/plaza/bench.glb", "Bench1", nav, Vector3(12.8, 0, 4.4), -90)
	_prop("res://assets/plaza/bench.glb", "Bench2", nav, Vector3(-0.4, 0, 7.2), 180)
	var bins := [Vector3(-7.0, 0, -5.2), Vector3(7.2, 0, -5.5), Vector3(13.0, 0, -13.0), Vector3(-12.5, 0, -14.0), Vector3(8.5, 0, 6.4), Vector3(-9.2, 0, 6.2)]
	for i in bins.size():
		_prop("res://assets/furniture/trashcan.glb", "Bin%d" % i, nav, bins[i], i * 25, 1.3)
	var bushes := [Vector3(-12.0, 0, -9.0), Vector3(-6.0, 0, -14.0), Vector3(0.5, 0, -14.5), Vector3(13.5, 0, -7.5),
		Vector3(13.3, 0, 1.0), Vector3(-12.5, 0, 1.0), Vector3(-9.5, 0, 4.8), Vector3(10.5, 0, 4.8),
		Vector3(5.0, 0, -7.4), Vector3(-4.0, 0, -6.9), Vector3(-1.0, 0, -8.2), Vector3(6.0, 0, -13.8),
		Vector3(-13.0, 0, -5.8), Vector3(9.5, 0, -12.2)]
	var kinds := ["plant_bushLarge", "plant_bush", "plant_bushSmall"]
	for i in bushes.size():
		_prop("res://assets/plaza/%s.glb" % kinds[i % 3], "Bush%d" % i, nav, bushes[i], i * 40, N)
	# 나무: 잎이 넓어서 줄기만 부딪치게
	var trees := [Vector3(-13.2, 0, -15.2), Vector3(14.2, 0, -15.2), Vector3(-13.2, 0, 7.2), Vector3(14.2, 0, 7.2),
		Vector3(-10.5, 0, -11.8), Vector3(11.8, 0, -11.0)]
	for i in trees.size():
		var t := _prop("res://assets/plaza/%s.glb" % ["tree_default", "tree_oak"][i % 2], "Tree%d" % i, p, trees[i], i * 30, 2.5, false)
		_box_body("TreeTrunk%d" % i, nav, trees[i] + Vector3(0, 0.8, 0), Vector3(0.45, 1.6, 0.45))
	# 옆 가게 천막 두 곳 (구경거리이자 가림막)
	_prop("res://assets/plaza/tent_detailedOpen.glb", "Stall0", nav, Vector3(-10.6, 0, -1.4), 90, 4.0)
	_prop("res://assets/plaza/tent_detailedOpen.glb", "Stall1", nav, Vector3(4.8, 0, -15.0), 0, 4.0)
	_prop("res://assets/plaza/pottedPlant.glb", "Pot0", nav, Vector3(7.1, 0, 1.0), 0, S)
	_prop("res://assets/plaza/pottedPlant.glb", "Pot1", nav, Vector3(7.1, 0, 4.3), 0, S)
	for i in 3:
		_prop("res://assets/plaza/lampRoundFloor.glb", "Lamp%d" % i, p, [Vector3(-6.8, 0, -7.4), Vector3(6.9, 0, -7.2), Vector3(-0.2, 0, -12.8)][i], 0, 3.0, false)
	# 꽃과 돌 (장식)
	for i in 14:
		var at := Vector3(randf_range(-13.5, 14.5), 0, randf_range(-15.5, 7.5))
		if absf(at.x) < 7.0 and absf(at.z) < 5.0:
			continue
		_prop("res://assets/plaza/%s.glb" % ["flower_redA", "flower_yellowA", "rock_smallA"][i % 3], "Deco%d" % i, p, at, i * 50, N, false)
	# 울타리 (보이기만) + 보이지 않는 경계 벽
	for x in range(-14, 15, 3):
		_prop("res://assets/plaza/fence_simple.glb", "FenceN%d" % x, p, Vector3(x + 1.5, 0, -16.1), 0, N, false)
		_prop("res://assets/plaza/fence_simple.glb", "FenceS%d" % x, p, Vector3(x + 1.5, 0, 8.1), 0, N, false)
	for z in range(-16, 8, 3):
		if z in [-8]:
			continue  # 손님이 드나드는 길
		_prop("res://assets/plaza/fence_simple.glb", "FenceW%d" % z, p, Vector3(-14.1, 0, z + 1.5), 90, N, false)
		_prop("res://assets/plaza/fence_simple.glb", "FenceE%d" % z, p, Vector3(15.1, 0, z + 1.5), 90, N, false)
	_box_body("EdgeN", nav, Vector3(0.5, 1.0, -16.3), Vector3(30, 2.0, 0.3))
	_box_body("EdgeS", nav, Vector3(0.5, 1.0, 8.3), Vector3(30, 2.0, 0.3))
	_box_body("EdgeW", nav, Vector3(-14.3, 1.0, -4), Vector3(0.3, 2.0, 25))
	_box_body("EdgeE", nav, Vector3(15.3, 1.0, -4), Vector3(0.3, 2.0, 25))

func _markers() -> void:
	var g := Node3D.new()
	g.name = "Markers"
	_add(top, g)
	var pts := {
		"ChefSpawn": Vector3(-2.0, 0, -1.6),
		"DogSpawn": Vector3(9.0, 0, 2.6),
		"DoorInside": Vector3(5.2, 0, 2.6),
		"DoorOutside": Vector3(7.4, 0, 2.6),
		"Queue0": Vector3(1.72, 0, -4.9),
		"Queue1": Vector3(2.9, 0, -5.4),
		"Queue2": Vector3(4.1, 0, -5.8),
		"CustomerOut": Vector3(15.6, 0, -6.5),
		"CustomerOut2": Vector3(-14.6, 0, -6.5),
	}
	for k in pts:
		var m := Marker3D.new()
		m.name = k
		m.position = pts[k]
		_add(g, m)
	# 바닥에 굴러다니는 진짜 핫도그 (강아지가 옆에 숨으면 티가 덜 난다)
	# 트럭 안 6개 + 장터 22개. 강아지는 이 사이에 섞여 숨는다
	var decoys := [
		Vector3(4.5, 0, 2.3), Vector3(-4.8, 0, 2.2), Vector3(2.4, 0, 3.0), Vector3(4.2, 0, -1.4),
		Vector3(-3.8, 0, 0.9), Vector3(3.2, 0, -0.4),
		Vector3(-7.3, 0, -7.2), Vector3(-8.8, 0, -8.9), Vector3(-3.0, 0, -9.6), Vector3(-4.4, 0, -11.3),
		Vector3(3.3, 0, -10.2), Vector3(1.8, 0, -11.9), Vector3(8.8, 0, -8.4), Vector3(7.4, 0, -9.9),
		Vector3(10.2, 0, -4.4), Vector3(-6.5, 0, -5.9), Vector3(6.4, 0, -6.1), Vector3(-11.4, 0, -9.6),
		Vector3(-5.3, 0, -13.6), Vector3(1.2, 0, -13.9), Vector3(12.8, 0, -7.0), Vector3(12.6, 0, 1.6),
		Vector3(-11.8, 0, 1.7), Vector3(-8.9, 0, 5.4), Vector3(9.9, 0, 5.4), Vector3(0.8, 0, 6.2),
		Vector3(12.3, 0, -12.4), Vector3(-11.9, 0, -13.3),
	]
	for i in decoys.size():
		var m := Marker3D.new()
		m.name = "Decoy%d" % i
		m.position = decoys[i]
		m.add_to_group("decoy_spot", true)
		_add(g, m)
	# 손님이 핫도그를 들고 서서 먹는 자리 (스탠드 테이블 양옆)
	for t in TABLES.size():
		for side in [-1.0, 1.0]:
			var m := Marker3D.new()
			m.name = "Eat%d_%d" % [t, 0 if side < 0 else 1]
			m.position = TABLES[t] + Vector3(side * 1.05, 0, 0.1)
			m.add_to_group("eat_spot", true)
			_add(g, m)
	# AI 강아지가 숨으러 가는 구석
	var hides := [Vector3(4.6, 0, 1.6), Vector3(-4.9, 0, 1.9), Vector3(2.0, 0, 3.2), Vector3(3.8, 0, -1.0), Vector3(-1.2, 0, 3.2),
		Vector3(-7.0, 0, -6.6), Vector3(-3.4, 0, -10.2), Vector3(2.8, 0, -11.6), Vector3(8.2, 0, -9.3),
		Vector3(-11.0, 0, -9.0), Vector3(12.2, 0, -6.6), Vector3(12.0, 0, 2.2), Vector3(-11.2, 0, 2.2),
		Vector3(-8.4, 0, 5.8), Vector3(9.4, 0, 5.8), Vector3(0.3, 0, -13.4), Vector3(-5.8, 0, -13.2)]
	for i in hides.size():
		var m := Marker3D.new()
		m.name = "Hide%d" % i
		m.position = hides[i]
		m.add_to_group("hide_spot", true)
		_add(g, m)
