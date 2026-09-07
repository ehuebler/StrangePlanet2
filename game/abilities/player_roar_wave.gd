class_name PlayerRoarWave
extends MeshInstance3D

## Expanding roar shell shared by Roar, Toxic Blast, Charming Aura, and Freeze
## Blast. Gameplay radius is host-authoritative; this follows [member radius].

const SHADER := preload("res://game/enemies/bigfoot/bigfoot_roar_wave.gdshader")
const DRAW_LIMIT := 80.0

var origin := Vector3.ZERO
var radius := 0.0
var wave_color := Color(0.95, 0.55, 0.12)

var _material: ShaderMaterial


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if DisplayServer.get_name() == "headless":
		visible = false
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(
		&"wave_color", Vector3(wave_color.r, wave_color.g, wave_color.b))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	sphere.material = _material
	mesh = sphere
	top_level = true
	visible = false


func set_color(color: Color) -> void:
	wave_color = color
	if _material != null:
		_material.set_shader_parameter(
			&"wave_color", Vector3(color.r, color.g, color.b))


func set_wave(at: Vector3, wave_radius: float) -> void:
	origin = at
	radius = maxf(wave_radius, 0.0)
	if DisplayServer.get_name() == "headless":
		return
	if radius > DRAW_LIMIT:
		visible = false
		return
	global_position = at
	scale = Vector3.ONE * radius
	if _material != null:
		_material.set_shader_parameter(
			&"strength", clampf(radius / 16.0, 0.0, 1.0))
	visible = radius > 0.05


func clear() -> void:
	radius = 0.0
	visible = false
