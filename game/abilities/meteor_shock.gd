class_name MeteorShock
extends Node3D

## The bow shock standing off a meteor punch's fist.
##
## Kept apart from [MeteorPunch] for the same reason [LaserBeams] is kept apart
## from [LaserEyes]: the ability only exists on the machine whose player threw
## the punch, and everybody else has to see it too. What both paths share is a
## stance — [constant OnlinePlayer.Stance.METEOR] replicates like any other — so
## this is driven from the player's presentation pass rather than from the
## ability, and a remote punch is drawn by the same code as a local one.
##
## The shape is the hit box. The fist damages a cylinder of [member radius]
## across, so the shock is a dome of exactly that radius: what the player can
## see coming is what the punch is about to cut, and there is no second number
## to keep the two in step.

const SHADER := preload("res://shaders/vivid/vivid_shock.gdshader")

## Seconds the shell takes to arrive at the launch and to clear after the
## landing. Short enough to belong to the punch, long enough that it is a shock
## forming rather than a decal being switched on.
const RISE := 0.09
const FALL := 0.16

## How far the dome is drawn out along the travel direction, as a share of its
## radius, at the slowest and fastest the punch goes.
##
## A blunt body at low speed carries a shallow cap standing well off its nose;
## the faster it goes the further back the shock lies down against it, which is
## the same thing a Mach cone narrowing is. Driving it off speed means the shape
## itself reads as acceleration, and the punch spends its first third
## accelerating.
const BLUNT := 0.35
const DRAWN := 1.15
## The speeds those two belong to.
const SLOW := 60.0
const FAST := 200.0

## Where the rim sits relative to the fist, as a share of the radius. Slightly
## behind, so the fist is inside the shell it is pushing rather than in front of
## it.
const SET_BACK := 0.3

## Segments around the shock and along it. Coarse: it is a smooth shell of
## nearly uniform colour, and the one edge anybody sees is its silhouette.
const SPOKES := 40
const RINGS := 14

## Metres across, matched to the fist's damage cylinder by whoever builds this.
var radius := 4.0

var _shell: MeshInstance3D
var _material: ShaderMaterial
var _lamp: OmniLight3D
var _extras: Array[MeshInstance3D] = []
## What the shader is being given now, eased toward [member _wanted].
var _strength := 0.0
var _wanted := 0.0
var _copies := 1


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER

	_shell = MeshInstance3D.new()
	_shell.mesh = _build_dome()
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A shell drawn with no depth write has nothing to sort itself against, and
	# at four metres across it straddles the near ground constantly. Sorting it
	# by the fist rather than by the mesh's own centre keeps it from flicking in
	# front of and behind the terrain as the dome is stretched.
	_shell.sorting_offset = -1.0
	add_child(_shell)

	# Enough to put a red edge on the ground and the plants the fist is about to
	# go through, and no more. A shock eight metres across sits a lamp right on
	# top of the near terrain, so anything generous enough to see from a
	# distance is a flood that washes the whole frame pink.
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.24, 0.12)
	_lamp.light_energy = 0.0
	_lamp.omni_range = 6.0
	_lamp.shadow_enabled = false
	add_child(_lamp)

	# Placed in world space against the fist, so the player's own rotation must
	# not be applied on top of it.
	top_level = true
	visible = false


func set_tint(color: Color) -> void:
	if _material != null:
		_material.set_shader_parameter(&"tint", Vector3(color.r, color.g, color.b))
	if _lamp != null:
		_lamp.light_color = color


## The shock surface: a paraboloid of revolution, nose at +Y, opening out to a
## rim of radius one in the XZ plane. Unit sized in both, so [method aim] can
## put the hit box's radius across it and the speed's draw-out along it.
##
## Built here rather than taken from [SphereMesh] for two reasons. The shader
## places the travelling bands and both end fades by how far along the surface a
## fragment is, and that has to be a number this code decides rather than
## whatever UV a primitive happens to lay down. And it is the right shape: the
## shock standing off a blunt body is a paraboloid, rounder at the nose than a
## cone and flatter at the skirt than a sphere.
func _build_dome() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for ring in RINGS + 1:
		# Zero at the nose, one at the rim. Carried to the shader in V.
		var along := float(ring) / float(RINGS)
		for spoke in SPOKES + 1:
			var turn := TAU * float(spoke) / float(SPOKES)
			var across := Vector3(cos(turn), 0.0, sin(turn))
			vertices.append(across * along + Vector3.UP * (1.0 - along * along))
			# Perpendicular to the meridian, which for this curve is the radial
			# direction weighted by twice the distance out plus the axis.
			normals.append(
				(across * (2.0 * along) + Vector3.UP).normalized())
			uvs.append(Vector2(float(spoke) / float(SPOKES), along))
	var stride := SPOKES + 1
	for ring in RINGS:
		for spoke in SPOKES:
			var corner := ring * stride + spoke
			indices.append_array(PackedInt32Array([
				corner, corner + stride, corner + 1,
				corner + 1, corner + stride, corner + stride + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh


## Stands the shock off a fist travelling in a direction at a speed. Called
## every frame the punch is in the air, on every peer.
func aim(fist: Vector3, along: Vector3, speed: float, copies := 1) -> void:
	var forward := along.normalized()
	if forward.length_squared() < 0.5:
		return
	var side := forward.cross(
		Vector3.UP if absf(forward.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		return
	side = side.normalized()
	var reach := radius * lerpf(BLUNT, DRAWN,
		clampf(inverse_lerp(SLOW, FAST, speed), 0.0, 1.0))
	# The mesh's own +Y is its nose, so the basis puts that along the travel
	# direction and carries the dome's size in the same step. The two across
	# axes are the hit box's radius exactly; only the axial one moves.
	var basis := Basis(side * radius, forward * reach, side.cross(forward) * radius)
	global_transform = Transform3D(
		basis, fist - forward * (radius * SET_BACK))
	_lamp.global_position = fist + forward * (reach * 0.5)
	_copies = clampi(copies, 1, CrawlerRules.MULTI_SHOTS_MAX)
	_ensure_extras(_copies - 1)
	for index in _extras.size():
		var extra := _extras[index]
		if index < _copies - 1:
			extra.global_transform = Transform3D(
				basis,
				fist + forward * CrawlerRules.MULTI_PUNCH_GAP * float(index + 1)
					- forward * (radius * SET_BACK))
			extra.visible = true
		else:
			extra.visible = false
	_wanted = 1.0
	visible = true
	set_process(true)


func _ensure_extras(count: int) -> void:
	if _shell == null:
		return
	while _extras.size() < count:
		var extra := MeshInstance3D.new()
		extra.mesh = _shell.mesh
		extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		extra.sorting_offset = -1.0
		extra.visible = false
		add_child(extra)
		_extras.append(extra)


## Lets the shock go. It is not switched off: the air the punch was pushing does
## not stop existing on the frame the fist stops.
func stop() -> void:
	_wanted = 0.0


func _process(delta: float) -> void:
	var rate := RISE if _wanted > _strength else FALL
	_strength = move_toward(_strength, _wanted, delta / rate)
	_material.set_shader_parameter(&"strength", _strength)
	_lamp.light_energy = _strength * 0.7
	if _strength > 0.0 or _wanted > 0.0:
		return
	visible = false
	set_process(false)
