class_name EnergyVfx
extends Node3D

## Instantiates one of the three authored energy GLBs and retints it.
##
## Beams are authored along +Y at a fixed length. [method place_beam] stretches
## that axis between two world points. Projectiles scale uniformly.

enum Kind {
	PROJECTILE,
	BEAM_CORE,
	BEAM_STREAMS,
}

const PROJECTILE_SCENE := preload("res://assets/runtime/vfx/energy/energy_projectile.glb")
const BEAM_CORE_SCENE := preload("res://assets/runtime/vfx/energy/energy_beam_core.glb")
const BEAM_STREAMS_SCENE := preload("res://assets/runtime/vfx/energy/energy_beam_streams.glb")

const BEAM_LENGTH := 3.2
const STREAM_LENGTH := 3.4
const BEAM_WIDTH := 0.18
const PROJECTILE_RADIUS := 0.42

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
var _painted := false


static func make(kind: Kind, tint := Color.WHITE, invert := false) -> EnergyVfx:
	var effect := EnergyVfx.new()
	effect.kind = kind
	effect._tint = tint
	effect._invert = invert
	return effect


func _ready() -> void:
	var packed := _scene_for(kind)
	if packed == null:
		return
	_visual = packed.instantiate() as Node3D
	if _visual == null:
		return
	_visual.name = "EnergyMesh"
	add_child(_visual)
	_loop_animations(_visual)
	_disable_shadows(_visual)
	_apply_tint(_tint, _invert)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func current_tint() -> Color:
	return _tint


func set_tint(tint: Color, invert := false) -> void:
	_tint = Color(tint.r, tint.g, tint.b, 1.0)
	_invert = invert
	if _visual != null:
		_apply_tint(_tint, _invert)


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
	var width := maxf(world_radius, 0.01) / BEAM_WIDTH
	side = side.normalized() * width
	global_transform = Transform3D(
		Basis(side, up * (span / _authored_length()),
			side.cross(up).normalized() * width),
		from + along * 0.5)
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


func _authored_length() -> float:
	return STREAM_LENGTH if kind == Kind.BEAM_STREAMS else BEAM_LENGTH


static func _scene_for(kind: Kind) -> PackedScene:
	match kind:
		Kind.BEAM_CORE:
			return BEAM_CORE_SCENE
		Kind.BEAM_STREAMS:
			return BEAM_STREAMS_SCENE
		_:
			return PROJECTILE_SCENE


func _apply_tint(tint: Color, invert: bool) -> void:
	if _visual == null:
		return
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var core := _is_core_mesh(mesh)
		var colour := _mesh_colour(tint, invert, core)
		var material := mesh.material_override as StandardMaterial3D
		if material == null:
			material = _copy_material(mesh)
			mesh.material_override = material
		if material == null:
			continue
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.albedo_color = Color(colour, material.albedo_color.a if material.albedo_color.a > 0.0 else 1.0)
		material.emission = colour
		if invert and core:
			material.emission_energy_multiplier = maxf(material.emission_energy_multiplier, 2.4)
		elif core:
			material.emission_energy_multiplier = maxf(material.emission_energy_multiplier, 5.5)
		else:
			material.emission_energy_multiplier = maxf(material.emission_energy_multiplier, 3.2)
	_painted = true


func _mesh_colour(tint: Color, invert: bool, core: bool) -> Color:
	if invert:
		if core:
			return Color(1.0 - tint.r, 1.0 - tint.g, 1.0 - tint.b)
		return tint
	if core:
		return tint.lerp(Color.WHITE, 0.62)
	return tint


func _is_core_mesh(mesh: MeshInstance3D) -> bool:
	var folded := mesh.name.to_lower()
	return folded.contains("core") or folded.contains("blade") or folded.contains("hot")


func _copy_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	var source: Material = mesh.material_override
	if source == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		source = mesh.get_active_material(0)
	if source is StandardMaterial3D:
		return (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	var made := StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.emission_enabled = true
	return made


func _loop_animations(root: Node) -> void:
	for node: Node in root.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player == null or player.get_animation_list().is_empty():
			continue
		var name := StringName(player.get_animation_list()[0])
		var clip := player.get_animation(name)
		if clip != null:
			clip.loop_mode = Animation.LOOP_LINEAR
		player.play(name)


func _disable_shadows(root: Node) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		if geo != null:
			geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
