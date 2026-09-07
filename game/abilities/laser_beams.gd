class_name LaserBeams
extends Node3D

## The two beams a player's eyes are firing, and the burn where they land.
##
## Kept apart from [LaserEyes] because the ability only exists on the machine
## whose player is firing, and everybody else has to see the beam too. This is
## the part both paths share: the local ability aims it every physics tick so it
## tracks the head smoothly, and the beam packet aims it on remote peers ten
## times a second. Either way it puts itself away shortly after the last aim it
## was given, so a player who disconnects mid-beam does not leave one hanging in
## the air.
##
## Unshaded and emissive, the same choice [LaserBolt] makes and for the same
## reason: everything else in this world is drawn in pencil, and light reads as
## light only if it is not shaded like the rest.

const COLOR := Color(1.0, 0.32, 0.22)
## What the middle of a beam is, as opposed to the glow around it. Nearly white:
## a laser is over-exposed at its centre, and a core in the same red as the glow
## reads as a plastic rod rather than as something too bright to look at.
const CORE_COLOR := Color(1.0, 0.74, 0.58)
## Half-width of the glow. Two beams at this size read as a pair from behind the
## player's shoulder, which is where the game is played from; thinner and they
## merge into one line by the time they converge.
const RADIUS := 0.1
## How much of that width the white centre takes. Small: the core is what says
## the beam is too bright to look at, and the red around it is what says the beam
## is red, so a core wide enough to see on its own is a beam that is white.
const CORE_SHARE := 0.3
## Seconds a beam stays up after the last aim. A shade over one damage tick at
## ten hertz, so a dropped packet thins the beam rather than blinking it.
const HOLD := 0.16
const FOLLOW_EYES := 0
const FOLLOW_HANDS_MERGED := 1

## How many short cylinders make a wobbling beam. Straight beams use the first
## one only. The wave is drawn along the shot, not by swinging the whole line.
const WAVE_SEGS := 20

## Core then glow, for each eye. Each entry is a chain of segments.
var _beams: Array[Array] = []
var _lamp: OmniLight3D
var _alive := 0.0
var _core_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _colour := COLOR
var _width_scale := 1.0
var _wobble := 0.0
var _follow := FOLLOW_EYES
var _from_left := Vector3.ZERO
var _from_right := Vector3.ZERO
var _target := Vector3.ZERO
var _targets: PackedVector3Array = PackedVector3Array()
var _paths: Array[PackedVector3Array] = []
var _core_mesh: CylinderMesh
var _glow_mesh: CylinderMesh
var _pairs := 1
## Last soot mark this beam laid. Swept fire would otherwise stamp a decal
## every damage tick; one every three-quarters of a metre is enough to read.
var _scorch_at := Vector3.INF
var _wobble_rolled := false
var _heading := PackedFloat32Array([0.0, 0.0])
var _twist := PackedFloat32Array([0.0, 0.0])
var _cycles := PackedFloat32Array([3.6, 4.1])
var _spin := PackedFloat32Array([12.0, -10.5])
var _far_cast := 0.0


func _ready() -> void:
	# Two passes over one line: an opaque core that reads against anything, and
	# an additive sheath around it that does not. Additive alone disappears
	# against bright ground, which is most of the ground there is.
	_core_material = _material(CORE_COLOR, 4.0, false)
	_glow_material = _material(COLOR, 2.4, true)
	_core_mesh = _beam_mesh(RADIUS * CORE_SHARE, _core_material)
	_glow_mesh = _beam_mesh(RADIUS, _glow_material)
	for _eye in 2:
		_beams.append(_beam_chain(_core_mesh))
		_beams.append(_beam_chain(_glow_mesh))
	_pairs = 1

	_lamp = OmniLight3D.new()
	_lamp.light_color = COLOR
	_lamp.light_energy = 3.4
	_lamp.omni_range = 5.5
	add_child(_lamp)

	# Beams are placed in world space, so they must not inherit the player's
	# rotation on top of the placement. They also must not interpolate from a
	# previous pose: the first visible frame would otherwise swing out of the
	# chest or last shot before locking onto the eyes.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_hide()
	set_process(false)


## Draws both beams from the two eyes onto one point. The optional colour lets
## another eye-beam ability share the exact presentation without inheriting
## Laser Eyes' red damage effect.
func aim(left_eye: Vector3, right_eye: Vector3, at: Vector3,
		colour: Color = COLOR, width_scale := 1.0, wobble := 0.0,
		follow := FOLLOW_EYES, far_cast := 0.0) -> void:
	aim_many(left_eye, right_eye, PackedVector3Array([at]), colour, width_scale,
		wobble, follow, far_cast)


func aim_many(left_eye: Vector3, right_eye: Vector3, targets: PackedVector3Array,
		colour: Color = COLOR, width_scale := 1.0, wobble := 0.0,
		follow := FOLLOW_EYES, far_cast := 0.0, paths: Array = []) -> void:
	if _beams.is_empty():
		return
	_from_left = left_eye
	_from_right = right_eye
	_targets = PackedVector3Array()
	for at: Vector3 in targets:
		if at.is_finite():
			_targets.append(at)
	if _targets.is_empty():
		return
	_paths.clear()
	for path_variant: Variant in paths:
		if path_variant is PackedVector3Array \
				and (path_variant as PackedVector3Array).size() >= 2:
			_paths.append(path_variant)
	if _paths.size() != _targets.size():
		_paths.clear()
	_target = _targets[int(_targets.size() / 2)]
	_ensure_pairs(_targets.size())
	_follow = follow
	_far_cast = maxf(far_cast, 0.0)
	_wobble = maxf(wobble, 0.0)
	if _wobble > 0.0:
		if not _wobble_rolled:
			_roll_wobble()
	else:
		_wobble_rolled = false
	_set_colour(colour)
	_width_scale = clampf(width_scale, 0.35, 4.5)
	_draw_now()
	_lamp.global_position = _target
	_lamp.visible = true
	_lamp.omni_range = 5.5 * _width_scale
	_lamp.light_energy = (3.4 if colour == COLOR else 2.0) * _width_scale
	_alive = HOLD
	set_process(true)


func _set_colour(colour: Color) -> void:
	colour = Color(colour.r, colour.g, colour.b, 1.0)
	if colour == _colour:
		return
	_colour = colour
	var core_colour := CORE_COLOR if colour == COLOR \
		else colour.lerp(Color.WHITE, 0.22)
	_core_material.albedo_color = core_colour
	_core_material.emission = core_colour
	_glow_material.albedo_color = Color(colour, 0.72)
	_glow_material.emission = colour
	_lamp.light_color = colour
	var laser_eyes := colour == COLOR
	_core_material.emission_energy_multiplier = 4.0 if laser_eyes else 1.8
	_glow_material.emission_energy_multiplier = 2.4 if laser_eyes else 1.2
	_lamp.light_energy = 3.4 if laser_eyes else 2.0


## Takes the beams down now, for the firing player letting go.
func stop() -> void:
	_alive = 0.0
	_wobble_rolled = false
	_scorch_at = Vector3.INF
	_paths.clear()
	_hide()
	set_process(false)


func path_points(eye := 0, toward := Vector3.INF) -> PackedVector3Array:
	var from := _from_left if (eye & 1) == 0 else _from_right
	var to := _target
	var path := PackedVector3Array()
	if toward.is_finite() and not _targets.is_empty():
		var best := 0
		var score := INF
		for index in _targets.size():
			var away := _targets[index].distance_squared_to(toward)
			if away < score:
				score = away
				best = index
		to = _targets[best]
		if best < _paths.size():
			path = _paths[best]
	elif not _targets.is_empty():
		to = _targets[0]
		if not _paths.is_empty():
			path = _paths[0]
	elif not _paths.is_empty():
		path = _paths[0]
	if path.size() >= 2:
		var bounced := PackedVector3Array()
		bounced.append(from)
		for index in range(1, path.size()):
			bounced.append(path[index])
		return bounced
	if _wobble <= 0.001:
		return PackedVector3Array([from, to])
	return _wave_points(from, to, eye & 1)


## True when a new soot mark should be laid at [param at]. Held still, the
## first call wins and later ticks leave the existing decal alone.
func take_scorch(at: Vector3, spacing: float) -> bool:
	if not at.is_finite():
		return false
	if _scorch_at.is_finite() and at.distance_to(_scorch_at) < spacing:
		return false
	_scorch_at = at
	return true


func _process(delta: float) -> void:
	_alive -= delta
	if _alive > 0.0:
		_follow_eyes()
		_draw_now()
		return
	_hide()
	set_process(false)


## The rendered head is often a frame ahead of the last physics aim. Reading
## the live eye sockets every draw keeps the beam glued to the face instead of
## hanging off last tick's pose for a moment.
func _follow_eyes() -> void:
	var shooter := get_parent() as OnlinePlayer
	if shooter == null:
		return
	if _follow == FOLLOW_HANDS_MERGED:
		var hands := shooter.hand_points()
		if hands.size() < 2:
			return
		var mid: Vector3 = (hands[0] + hands[1]) * 0.5
		_from_left = mid
		_from_right = mid
	else:
		var eyes := shooter.eye_points()
		if eyes.size() < 2:
			return
		_from_left = eyes[0]
		_from_right = eyes[1]
	if _far_cast <= 0.001:
		return
	var origin := (_from_left + _from_right) * 0.5
	var along := shooter.aim_direction(origin)
	if along.length_squared() < 0.000001 and _target.is_finite():
		along = _target - origin
	if along.length_squared() < 0.000001:
		return
	along = along.normalized() * _far_cast
	_from_left += along
	_from_right += along


func _ensure_pairs(count: int) -> void:
	var wanted := maxi(count, 1)
	while _pairs < wanted:
		_beams.append(_beam_chain(_core_mesh))
		_beams.append(_beam_chain(_glow_mesh))
		_beams.append(_beam_chain(_core_mesh))
		_beams.append(_beam_chain(_glow_mesh))
		_pairs += 1


func _draw_now() -> void:
	var used := _targets.size()
	for pair in _pairs:
		if pair < used:
			var path := PackedVector3Array()
			if pair < _paths.size():
				path = _paths[pair]
			if path.size() >= 2:
				_draw_path(0, _from_left, path, pair * 2)
				_draw_path(1, _from_right, path, pair * 2 + 1)
			else:
				_draw_eye(0, _from_left, _targets[pair], pair * 2)
				_draw_eye(1, _from_right, _targets[pair], pair * 2 + 1)
		else:
			_hide_eye(pair * 2)
			_hide_eye(pair * 2 + 1)


func _draw_path(eye: int, from: Vector3, path: PackedVector3Array,
		slot := -1) -> void:
	var chain := eye if slot < 0 else slot
	if chain < 0 or chain * 2 + 1 >= _beams.size():
		return
	var core: Array = _beams[chain * 2]
	var glow: Array = _beams[chain * 2 + 1]
	var points := PackedVector3Array()
	points.append(from)
	for index in range(1, path.size()):
		points.append(path[index])
	var segs := points.size() - 1
	if segs <= 1:
		_draw_eye(eye, from, points[points.size() - 1] if points.size() > 1 \
			else from, slot)
		return
	for index in WAVE_SEGS:
		if index < segs:
			_place(core[index], points[index], points[index + 1])
			_place(glow[index], points[index], points[index + 1])
		else:
			(core[index] as MeshInstance3D).visible = false
			(glow[index] as MeshInstance3D).visible = false


func _hide_eye(slot: int) -> void:
	if slot < 0 or slot * 2 + 1 >= _beams.size():
		return
	var core: Array = _beams[slot * 2]
	var glow: Array = _beams[slot * 2 + 1]
	for index in WAVE_SEGS:
		(core[index] as MeshInstance3D).visible = false
		(glow[index] as MeshInstance3D).visible = false


func _draw_eye(eye: int, from: Vector3, to: Vector3, slot := -1) -> void:
	var chain := eye if slot < 0 else slot
	if chain < 0 or chain * 2 + 1 >= _beams.size():
		return
	var core: Array = _beams[chain * 2]
	var glow: Array = _beams[chain * 2 + 1]
	if _wobble <= 0.001:
		_place(core[0], from, to)
		_place(glow[0], from, to)
		for index in range(1, WAVE_SEGS):
			(core[index] as MeshInstance3D).visible = false
			(glow[index] as MeshInstance3D).visible = false
		return
	var points := _wave_points(from, to, eye)
	for index in WAVE_SEGS:
		_place(core[index], points[index], points[index + 1])
		_place(glow[index], points[index], points[index + 1])


func _wave_points(from: Vector3, to: Vector3, eye: int) -> PackedVector3Array:
	var along := to - from
	var span := along.length()
	var points := PackedVector3Array()
	points.resize(WAVE_SEGS + 1)
	if span < 0.001:
		for index in points.size():
			points[index] = from
		return points
	var dir := along / span
	var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		for index in points.size():
			points[index] = from.lerp(to, float(index) / float(WAVE_SEGS))
		return points
	side = side.normalized()
	var lift := side.cross(dir).normalized()
	var heading := side.rotated(dir, _heading[eye]).normalized()
	var twist := side.rotated(dir, _twist[eye]).normalized()
	var time := Time.get_ticks_msec() * 0.001
	var amplitude := minf(1.45 + span * 0.02, 2.6) * _wobble
	var phase0 := time * _spin[eye]
	var cycles := _cycles[eye]
	for index in points.size():
		var t := float(index) / float(WAVE_SEGS)
		var envelope := sin(t * PI)
		var phase := t * TAU * cycles + phase0
		points[index] = from + along * t \
			+ heading * sin(phase) * amplitude * envelope \
			+ twist * cos(phase * 0.68 + 0.4) * amplitude * envelope * 0.9
	return points


func _roll_wobble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_heading[0] = rng.randf() * TAU
	_heading[1] = _heading[0] + rng.randf_range(TAU * 0.32, TAU * 0.68)
	_twist[0] = _heading[0] + rng.randf_range(0.7, 2.3)
	_twist[1] = _heading[1] + rng.randf_range(0.7, 2.3)
	_cycles[0] = rng.randf_range(3.4, 4.8)
	_cycles[1] = rng.randf_range(3.4, 4.8)
	_spin[0] = rng.randf_range(10.0, 16.0)
	_spin[1] = -rng.randf_range(10.0, 16.0)
	if rng.randf() < 0.5:
		var swap := _spin[0]
		_spin[0] = _spin[1]
		_spin[1] = swap
	_wobble_rolled = true


## Stretches one beam between two points. A cylinder stands along its own +Y, so
## the placement is a basis whose Y runs down the beam and whose scale carries
## the length — which also means the beam does not get fatter as it gets longer.
## Width is applied here; setting `scale` on the node is overwritten by this
## transform and would never show.
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
	for chain: Array in _beams:
		for beam: Variant in chain:
			(beam as MeshInstance3D).visible = false
	if _lamp != null:
		_lamp.visible = false


func _beam_chain(mesh: CylinderMesh) -> Array:
	var chain: Array = []
	for _index in WAVE_SEGS:
		chain.append(_beam_node(mesh))
	return chain


func _beam_mesh(radius: float, material: StandardMaterial3D) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	# Tapered towards the far end, which is the end that is converging on a
	# point: two beams that met at full width would meet as a blunt join.
	mesh.top_radius = radius * 0.55
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 6
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


func _material(tint: Color, energy: float,
		additive: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	material.disable_receive_shadows = true
	if not additive:
		return material
	# Additive, so two beams crossing brighten rather than cutting a seam into
	# each other. Held back from full strength: added at full value onto ground
	# this bright the red saturates to white, which is the one colour a beam
	# whose whole job is to look like heat must not be.
	material.albedo_color = Color(tint, 0.72)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return material
