extends SceneTree
# 트럭 내부 맵(scenes/truck.tscn)을 만드는 도구.
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
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_add(top, env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.1
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
	_kitchen()
	_rack()
	_clutter()
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
	# 트럭 바닥 12 x 8 (x -6..6, z -4..4), 바깥 길바닥
	for ix in range(6):
		for iz in range(4):
			_prop("res://assets/furniture/floorFull.glb", "Floor_%d_%d" % [ix, iz], top,
				Vector3(-6 + ix * 2, 0, -4 + iz * 2 + 2), 0.0, S, false)
	_box_body("Ground", nav, Vector3(0, -0.1, 0), Vector3(12, 0.2, 8))
	var street := MeshInstance3D.new()
	street.name = "Street"
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 30)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#585c66")
	pm.material = mat
	street.mesh = pm
	street.position = Vector3(0, -0.02, 0)
	_add(top, street)

func _walls() -> void:
	var wall_col := Color("#e8c46a")  # 노란 푸드트럭 벽
	_box_body("WallLeft", nav, Vector3(-6.15, 0.6, 0), Vector3(0.3, 1.2, 8.3), wall_col)
	_box_body("WallRight", nav, Vector3(6.15, 0.6, 0), Vector3(0.3, 1.2, 8.3), wall_col)
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

func _station(kind: String, at: Vector3, label: String) -> void:
	var st := Node3D.new()
	st.name = "Station_" + kind
	st.set_script(load("res://scripts/station.gd"))
	st.set("kind", kind)
	st.position = at
	st.add_to_group("station", true)
	_add(top, st)
	var l := Label3D.new()
	l.name = "Sign"
	l.text = label
	l.font_size = 40
	l.outline_size = 10
	l.position = Vector3(0, 2.1, -0.4)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_add(st, l)

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
			n += 1
	var l := Label3D.new()
	l.name = "Sign"
	l.text = "진열대"
	l.font_size = 40
	l.outline_size = 10
	l.position = Vector3(0, 1.9, 0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_add(rack, l)

func _clutter() -> void:
	_prop("res://assets/furniture/trashcan.glb", "Trash", nav, Vector3(5.3, 0, 2.2), 0, 1.3)
	_prop("res://assets/furniture/cardboardBoxClosed.glb", "Box1", nav, Vector3(5.0, 0, -1.2), 10)
	_prop("res://assets/furniture/cardboardBoxOpen.glb", "Box2", nav, Vector3(4.6, 0, -2.2), -15)
	_prop("res://assets/furniture/cardboardBoxClosed.glb", "Box3", nav, Vector3(-5.6, 0, 1.4), 5)
	_prop("res://assets/furniture/cardboardBoxClosed.glb", "Box4", nav, Vector3(-5.5, 0, 2.6), -20)
	_prop("res://assets/furniture/stoolBar.glb", "Stool1", nav, Vector3(3.0, 0, 1.8), 30)
	_prop("res://assets/furniture/stoolBar.glb", "Stool2", nav, Vector3(-2.8, 0, 2.6), -10)

func _markers() -> void:
	var g := Node3D.new()
	g.name = "Markers"
	_add(top, g)
	var pts := {
		"ChefSpawn": Vector3(-2.0, 0, -1.6),
		"DogSpawn": Vector3(3.6, 0, 2.6),
		"Queue0": Vector3(1.72, 0, -4.9),
		"Queue1": Vector3(2.9, 0, -5.4),
		"Queue2": Vector3(4.1, 0, -5.8),
		"CustomerOut": Vector3(9.0, 0, -6.0),
	}
	for k in pts:
		var m := Marker3D.new()
		m.name = k
		m.position = pts[k]
		_add(g, m)
	# 바닥에 굴러다니는 진짜 핫도그 (강아지가 옆에 숨으면 티가 덜 난다)
	var decoys := {
		"Decoy0": Vector3(4.5, 0, 2.3),
		"Decoy1": Vector3(-4.8, 0, 2.2),
		"Decoy2": Vector3(2.4, 0, 3.0),
		"Decoy3": Vector3(4.2, 0, -1.4),
	}
	for k in decoys:
		var m := Marker3D.new()
		m.name = k
		m.position = decoys[k]
		m.add_to_group("decoy_spot", true)
		_add(g, m)
	# AI 강아지가 숨으러 가는 구석
	var hides := [Vector3(4.6, 0, 1.6), Vector3(-4.9, 0, 1.9), Vector3(2.0, 0, 3.2), Vector3(3.8, 0, -1.0), Vector3(-1.2, 0, 3.2)]
	for i in hides.size():
		var m := Marker3D.new()
		m.name = "Hide%d" % i
		m.position = hides[i]
		m.add_to_group("hide_spot", true)
		_add(g, m)
