class_name LightningBolts
extends Node3D

## One jagged bolt that snaps from the face onto a chain of targets.
##
## Laser Eyes draws two smooth cylinders. Lightning is a single origin and a
## polyline that rebuilds every aim so the path looks like it is searching,
## then locking onto the next body.

const COLOR := Color(0.48, 0.86, 1.0)
const CORE_COLOR := Color(0.96, 0.98, 1.0)
const RADIUS := 0.07
const CORE_SHARE := 0.34
const HOLD := 0.14
const SEGS := 8
const MAX_HOPS := 8

var _core: Array[Array] = []
var _glow: Array[Array] = []
var _lamp: OmniLight3D
var _alive := 0.0
var _core_material: ShaderMaterial
var _glow_material: ShaderMaterial
var _colour := COLOR
var _width_scale := 1.0
var _from := Vector3.ZERO
var _hops: PackedVector3Array = PackedVector3Array()
var _chains: Array = []
var _core_mesh: CylinderMesh
var _glow_mesh: CylinderMesh
var _jag := PackedFloat32Array()
var _snap_left := 0.0
var _far_cast := 0.0


func _ready() -> void:
	_core_material = EnergyVfx.glow_material(
		COLOR, CORE_COLOR, true, 5.2, 0.35, 0.24, 0.0)
	_glow_material = EnergyVfx.glow_material(
		COLOR, CORE_COLOR, true, 2.8, 0.62, 0.22, 1.0)
	_core_mesh = _beam_mesh(RADIUS * CORE_SHARE, _core_material)
	_glow_mesh = _beam_mesh(RADIUS, _glow_material)
	for _hop in MAX_HOPS:
		_core.append(_beam_chain(_core_mesh))
		_glow.append(_beam_chain(_glow_mesh))
	_lamp = OmniLight3D.new()
	_lamp.light_color = COLOR
	_lamp.light_energy = 4.2
	_lamp.omni_range = 6.5
	add_child(_lamp)
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_hide()
	set_process(false)


func aim(from: Vector3, hops: PackedVector3Array, colour := COLOR,
		width_scale := 1.0, far_cast := 0.0) -> void:
	aim_many(from, [hops], colour, width_scale, far_cast)


func aim_many(from: Vector3, chains: Array, colour := COLOR,
		width_scale := 1.0, far_cast := 0.0) -> void:
	_from = from
	_far_cast = maxf(far_cast, 0.0)
	_chains = []
	_hops = PackedVector3Array()
	for item: Variant in chains:
		var hops := PackedVector3Array()
		if item is PackedVector3Array:
			hops = (item as PackedVector3Array).duplicate()
		elif item is Array:
			for point: Variant in item:
				if point is Vector3 and (point as Vector3).is_finite():
					hops.append(point)
		if hops.is_empty():
			continue
		_chains.append(hops)
		if _hops.is_empty():
			_hops = hops
	_set_colour(colour)
	_width_scale = clampf(width_scale, 0.28, 3.5)
	if _snap_left <= 0.0:
		_roll_jag()
		_snap_left = 0.05
	_draw_now()
	if not _hops.is_empty():
		_lamp.global_position = _hops[_hops.size() - 1]
	_lamp.visible = not _hops.is_empty()
	_lamp.omni_range = 6.5 * _width_scale
	_lamp.light_energy = 4.2 * _width_scale
	_alive = HOLD
	set_process(true)


func stop() -> void:
	_alive = 0.0
	_hops = PackedVector3Array()
	_chains.clear()
	_hide()
	set_process(false)


func _process(delta: float) -> void:
	_alive -= delta
	_snap_left = maxf(_snap_left - delta, 0.0)
	if _alive > 0.0:
		_follow_face()
		if _snap_left <= 0.0:
			_roll_jag()
			_snap_left = 0.05
		_draw_now()
		return
	_hide()
	set_process(false)


func _follow_face() -> void:
	var shooter := get_parent() as OnlinePlayer
	if shooter == null:
		return
	var eyes := shooter.eye_points()
	if eyes.size() < 2:
		return
	_from = (eyes[0] + eyes[1]) * 0.5
	if _far_cast <= 0.001:
		return
	var along := shooter.aim_direction(_from)
	if along.length_squared() < 0.000001:
		return
	_from += along.normalized() * _far_cast


func _draw_now() -> void:
	var needed := 0
	for chain_variant: Variant in _chains:
		needed += (chain_variant as PackedVector3Array).size()
	_ensure_hops(maxi(needed, MAX_HOPS))
	var slot := 0
	for chain_variant: Variant in _chains:
		var hops: PackedVector3Array = chain_variant
		var last := _from
		for hop in hops:
			_draw_hop(slot, last, hop)
			last = hop
			slot += 1
	for leftover in range(slot, _core.size()):
		_hide_hop(leftover)


func _ensure_hops(count: int) -> void:
	while _core.size() < count:
		_core.append(_beam_chain(_core_mesh))
		_glow.append(_beam_chain(_glow_mesh))


func _draw_hop(hop: int, from: Vector3, to: Vector3) -> void:
	var points := _jag_points(from, to, hop)
	for index in SEGS:
		_place(_core[hop][index], points[index], points[index + 1])
		_place(_glow[hop][index], points[index], points[index + 1])


func _hide_hop(hop: int) -> void:
	for index in SEGS:
		(_core[hop][index] as MeshInstance3D).visible = false
		(_glow[hop][index] as MeshInstance3D).visible = false


func _jag_points(from: Vector3, to: Vector3, hop: int) -> PackedVector3Array:
	var along := to - from
	var span := along.length()
	var points := PackedVector3Array()
	points.resize(SEGS + 1)
	if span < 0.001:
		for index in points.size():
			points[index] = from
		return points
	var dir := along / span
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		for index in points.size():
			points[index] = from.lerp(to, float(index) / float(SEGS))
		return points
	side = side.normalized()
	var lift := side.cross(dir).normalized()
	var amplitude := minf(0.55 + span * 0.035, 1.8)
	for index in points.size():
		var t := float(index) / float(SEGS)
		if index == 0:
			points[index] = from
			continue
		if index == points.size() - 1:
			points[index] = to
			continue
		var slot := (hop * SEGS + index) % _jag.size() if not _jag.is_empty() else 0
		var kick := _jag[slot] if not _jag.is_empty() else 0.0
		var twist := _jag[(slot + 3) % _jag.size()] if _jag.size() > 3 else 0.0
		var envelope := sin(t * PI)
		points[index] = from + along * t \
			+ side * kick * amplitude * envelope \
			+ lift * twist * amplitude * envelope * 0.7
	return points


func _roll_jag() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_jag.resize(SEGS * MAX_HOPS)
	for index in _jag.size():
		_jag[index] = rng.randf_range(-1.0, 1.0)


func _set_colour(colour: Color) -> void:
	colour = Color(colour.r, colour.g, colour.b, 1.0)
	if colour == _colour:
		return
	_colour = colour
	var core_colour := colour.lerp(Color.WHITE, 0.55)
	EnergyVfx.paint_glow(_core_material, colour, core_colour)
	EnergyVfx.paint_glow(_glow_material, colour, core_colour)
	_lamp.light_color = colour


func _place(beam: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var along := to - from
	var span := along.length()
	if span < 0.001:
		beam.visible = false
		return
	var up := along / span
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		beam.visible = false
		return
	side = side.normalized() * _width_scale
	beam.global_transform = Transform3D(
		Basis(side, up * span, side.cross(up).normalized() * _width_scale),
		from + along * 0.5)
	beam.visible = true
	beam.reset_physics_interpolation()


func _hide() -> void:
	for hop in _core.size():
		_hide_hop(hop)
	if _lamp != null:
		_lamp.visible = false


func _beam_chain(mesh: CylinderMesh) -> Array:
	var chain: Array = []
	for _index in SEGS:
		chain.append(_beam_node(mesh))
	return chain


func _beam_mesh(radius: float, material: Material) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.45
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 0
	mesh.material = material
	return mesh


func _beam_node(mesh: CylinderMesh) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	beam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(beam)
	return beam


