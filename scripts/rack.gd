extends Node3D
## 가운데 진열대. 칸마다 핫도그, 숨은 강아지, 또는 빈칸(null)이 들어간다.

const HOTDOG := preload("res://assets/food/hot-dog.glb")
const HOTDOG_SCALE := 1.4

var slots: Array[Marker3D] = []
var items: Array = []

func _ready() -> void:
	if not has_node("Slots"):
		return  # 맵 만드는 도구에서 칸이 붙기 전에 불린 경우
	for c in $Slots.get_children():
		slots.append(c)
		items.append(null)

## 핫도그 한 개를 만든다. 강아지가 한 입 먹은 건 짧아진다.
static func new_hotdog(bitten := false) -> Node3D:
	var h := Node3D.new()
	var m: Node3D = HOTDOG.instantiate()
	m.scale = Vector3.ONE * HOTDOG_SCALE
	h.add_child(m)
	h.set_meta("hotdog", true)
	set_bitten(h, bitten)
	return h

static func set_bitten(h: Node3D, bitten: bool) -> void:
	h.set_meta("bitten", bitten)
	var m: Node3D = h.get_child(0)
	m.scale.x = HOTDOG_SCALE * (0.62 if bitten else 1.0)
	m.position.x = -0.16 if bitten else 0.0

## 셰프가 핫도그를 들고 있으면 빈칸 접시가 은은하게 빛난다.
func set_highlight(on: bool) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in slots.size():
		var mat: StandardMaterial3D = slots[i].get_node("Plate").material_override
		mat.emission_enabled = on and items[i] == null
		mat.emission = Color("#ffe08a")
		mat.emission_energy_multiplier = 0.4 + 0.3 * sin(t * 5.0)

func slot_pos(i: int) -> Vector3:
	return slots[i].global_position

## pos에서 가장 가까운 칸. want: "empty" 빈칸 / "full" 뭔가 있는 칸 / "hotdog" 안 먹힌 진짜 핫도그
func nearest(pos: Vector3, want: String, max_dist := 1.5) -> int:
	var best := -1
	var best_d := max_dist
	for i in slots.size():
		var it = items[i]
		var ok := false
		match want:
			"empty": ok = it == null
			"full": ok = it != null
			"hotdog": ok = it is Node3D and it.has_meta("hotdog") and not it.get_meta("bitten")
		if not ok:
			continue
		var d := Vector2(pos.x - slots[i].global_position.x, pos.z - slots[i].global_position.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

func place(i: int, item: Node3D) -> void:
	items[i] = item
	if item.has_meta("hotdog"):
		if item.get_parent():
			item.get_parent().remove_child(item)
		slots[i].add_child(item)
		item.position = Vector3.ZERO
		item.rotation = Vector3.ZERO

func take(i: int):
	var it = items[i]
	items[i] = null
	if it is Node3D and it.has_meta("hotdog"):
		slots[i].remove_child(it)
	return it

func count_items() -> int:
	var n := 0
	for it in items:
		if it != null:
			n += 1
	return n

func has_empty() -> bool:
	return items.has(null)
