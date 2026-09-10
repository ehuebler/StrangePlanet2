class_name EnergyVfx
extends Node3D

## A sphere or cylinder wearing [constant SHADER]. Authored energy GLBs are
## not used: the hull is a Godot primitive and the fire lives in the material.
##
## Beams are a unit cylinder on +Y, muzzle at the origin. [method place_beam]
## maps that span onto [param from] → [param to]. Projectiles scale uniformly.

enum Kind {
	PROJECTILE,
	BEAM_CORE,
	BEAM_STREAMS,
}

const SHADER := preload("res://shaders/vivid/energy_glow.gdshader")
const BEAM_LENGTH := 1.0
const BEAM_WIDTH := 0.5
const PROJECTILE_RADIUS := 0.5

const TINT_RED := Color(1.0, 0.32, 0.22)
const TINT_DARK_RED := Color(0.46, 0.04, 0.06)
const TINT_BLUE := Color(0.24, 0.71, 1.0)
const TINT_PURPLE := Color(0.72, 0.22, 1.0)
const TINT_GREEN := Color(0.20, 0.92, 0.22)
const TINT_PINK := Color(1.0, 0.36, 0.74)
const TINT_WHITE := Color(1.0, 1.0, 1.0)

var kind := Kind.PROJECTILE
var _visual: Node3D
var _tint := Color.WHITE
var _invert := false
var _opacity := 1.0
var _span_length := BEAM_LENGTH
var _span_min_y := 0.0
var _span_width := BEAM_WIDTH
var _core_mat: ShaderMaterial
var _glow_mat: ShaderMaterial


static func make(kind: Kind, tint := Color.WHITE, invert := false) -> EnergyVfx:
	var effect := EnergyVfx.new()
	effect.kind = kind
	effect._tint = tint
	effect._invert = invert
	return effect


static func glow_material(
		fire: Color,
		core: Color,
		shape_beam := false,
		energy := 3.4,
		flicker := 0.55,
		core_size := 0.30,
		layer := 1.0,
		invert := false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"fire_color", fire)
	material.set_shader_parameter(&"core_color", core)
	material.set_shader_parameter(&"energy", energy)
	material.set_shader_parameter(&"flicker", flicker)
	material.set_shader_parameter(&"core_size", core_size)
	material.set_shader_parameter(&"shape", 1.0 if shape_beam else 0.0)
	material.set_shader_parameter(&"layer", layer)
	material.set_shader_parameter(&"invert", 1.0 if invert else 0.0)
	material.set_shader_parameter(&"seed", 0.0)
	material.set_shader_parameter(&"opacity", 1.0)
	return material


static func paint_glow(
		material: ShaderMaterial,
		fire: Color,
		core: Color,
		invert := false) -> void:
	if material == null:
		return
	material.set_shader_parameter(&"fire_color", fire)
	material.set_shader_parameter(&"core_color", core)
	material.set_shader_parameter(&"invert", 1.0 if invert else 0.0)


func _ready() -> void:
	_visual = Node3D.new()
	_visual.name = "EnergyMesh"
	add_child(_visual)
	_span_length = BEAM_LENGTH
	_span_min_y = 0.0
	_span_width = BEAM_WIDTH
	if kind == Kind.PROJECTILE:
		_build_orb()
	else:
		_build_beam()
	_apply_tint(_tint, _invert)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func current_tint() -> Color:
	return _tint


func uses_glow_shader() -> bool:
	return _glow_mat != null and _glow_mat.shader == SHADER


func set_tint(tint: Color, invert := false) -> void:
	_tint = Color(tint.r, tint.g, tint.b, 1.0)
	_invert = invert
	_apply_tint(_tint, _invert)


func current_opacity() -> float:
	return _opacity


func set_opacity(opacity: float) -> void:
	_opacity = clampf(opacity, 0.0, 1.0)
	_paint_opacity()


func set_ball_radius(radius: float) -> void:
	var scale_to := maxf(radius, 0.02) / PROJECTILE_RADIUS
	scale = Vector3.ONE * scale_to


func place_beam(from: Vector3, to: Vector3, world_radius := BEAM_WIDTH) -> bool:
	var along := to - from
	var span := along.length()
	if span < 0.001:
		visible = false
		return false
	var up := along / span
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		visible = false
		return false
	var width := maxf(world_radius, 0.01) / _span_width
	side = side.normalized() * width
	var scale_y := span / _span_length
	global_transform = Transform3D(
		Basis(side, up * scale_y, side.cross(up).normalized() * width),
		from - up * (_span_min_y * scale_y))
	visible = true
	reset_physics_interpolation()
	return true


func point_along(along: Vector3) -> void:
	if along.length_squared() < 0.000001:
		return
	var up := Vector3.UP
	if absf(along.normalized().dot(up)) > 0.98:
		up = Vector3.RIGHT
	look_at(global_position + along, up)
	rotate_object_local(Vector3.RIGHT, -PI * 0.5)


func _build_orb() -> void:
	_core_mat = glow_material(
		_tint, _core_colour(_tint, _invert), false,
		5.4, 0.38, 0.28, 0.0, _invert)
	_glow_mat = glow_material(
		_tint, _core_colour(_tint, _invert), false,
		3.2, 0.62, 0.22, 1.0, _invert)
	_add_sphere("Core", 0.16, _core_mat)
	_add_sphere("Glow", 0.50, _glow_mat)


func _build_beam() -> void:
	var streams := kind == Kind.BEAM_STREAMS
	_core_mat = glow_material(
		_tint, _core_colour(_tint, _invert), true,
		4.8, 0.38, 0.26, 0.0, _invert)
	_glow_mat = glow_material(
		_tint, _core_colour(_tint, _invert), true,
		3.0, 0.70 if streams else 0.48, 0.22, 1.0, _invert)
	_add_cylinder("Core", 0.20, _core_mat)
	_add_cylinder("Glow", 0.50, _glow_mat)


func _add_sphere(mesh_name: String, radius: float, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 12
	var node := MeshInstance3D.new()
	node.name = mesh_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(node)


func _add_cylinder(mesh_name: String, radius: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = BEAM_LENGTH
	mesh.radial_segments = 14
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.name = mesh_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unit cylinder, muzzle at Y=0, tip at Y=1.
	node.position = Vector3(0.0, BEAM_LENGTH * 0.5, 0.0)
	_visual.add_child(node)


func _apply_tint(tint: Color, invert: bool) -> void:
	var fire := tint
	var core := _core_colour(tint, invert)
	var phase := float(abs(get_instance_id()) % 47)
	paint_glow(_core_mat, fire, core, invert)
	paint_glow(_glow_mat, fire, core, invert)
	if _core_mat != null:
		_core_mat.set_shader_parameter(&"seed", phase)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter(&"seed", phase + 11.0)
	_paint_opacity()


func _paint_opacity() -> void:
	if _core_mat != null:
		_core_mat.set_shader_parameter(&"opacity", _opacity)
	if _glow_mat != null:
		_glow_mat.set_shader_parameter(&"opacity", _opacity)


func _core_colour(tint: Color, invert: bool) -> Color:
	if invert:
		return Color(1.0 - tint.r, 1.0 - tint.g, 1.0 - tint.b)
	# Almost white-hot. A core that is only a pale tint reads as a painted blob.
	return tint.lerp(Color(1.0, 0.96, 0.84), 0.82)
