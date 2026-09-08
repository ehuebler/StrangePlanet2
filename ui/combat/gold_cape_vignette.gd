class_name GoldCapeVignette
extends ColorRect

## Gold edge wash that pulses while the gold cape is bouncing hits.

const SHADER := preload("res://ui/combat/overdrive_vignette.gdshader")

var _material: ShaderMaterial
var _phase := 0.0


func _init() -> void:
	name = "GoldCapeVignette"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"tint", Color(1.0, 0.82, 0.22, 1.0))
	material = _material
	visible = false


func refresh(player: Node, menu_open: bool, delta: float) -> void:
	var on := not menu_open and player != null \
			and player.has_method(&"gold_cape_active") \
			and bool(player.call(&"gold_cape_active"))
	visible = on
	if not on or _material == null:
		return
	_phase += delta
	var pulse := 0.5 + 0.5 * sin(_phase * TAU * 2.4)
	_material.set_shader_parameter(&"pulse", pulse)
