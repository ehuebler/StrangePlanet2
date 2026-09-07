class_name FieldVignette
extends ColorRect

## Full-screen wash while the local camera sits inside a Field sphere.

const SHADER := preload("res://ui/combat/field_vignette.gdshader")

var _material: ShaderMaterial
var _phase := 0.0


func _init() -> void:
	name = "FieldVignette"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color.WHITE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material = _material
	visible = false


func refresh(player: Node, menu_open: bool, delta: float) -> void:
	if menu_open or player == null or not player is Node3D:
		visible = false
		return
	var at: Vector3 = (player as Node3D).global_position
	if player.has_method(&"combat_position"):
		at = player.call(&"combat_position")
	var wash := CrawlerFieldVolume.wash_at(player, at)
	var linger := CrawlerLingerCloud.wash_at(player, at)
	if linger.a > wash.a:
		wash = linger
	var on := wash.a > 0.01
	visible = on
	if not on or _material == null:
		return
	_phase += maxf(delta, 0.0)
	_material.set_shader_parameter(&"tint", Color(wash.r, wash.g, wash.b, 1.0))
	_material.set_shader_parameter(&"strength", clampf(wash.a / 0.34, 0.0, 1.0))
	_material.set_shader_parameter(&"phase", _phase)
