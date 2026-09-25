extends Node3D
## 셰프가 일하는 자리. kind: fridge / bread / grill / sauce / window
## 셰프가 든 것을 받는 자리는 바닥 매트가 은은하게 빛난다 (set_highlight).
@export var kind := ""

var lit := false
var _t := 0.0

func set_highlight(on: bool) -> void:
	lit = on

func _process(delta: float) -> void:
	var mat: StandardMaterial3D = $Mat.material_override
	if lit:
		_t += delta
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = 0.35 + 0.35 * sin(_t * 5.0)
	elif mat.emission_enabled:
		mat.emission_enabled = false
