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
## How far the drawn muzzle sits past the socket. The glow is additive and
## blooms; starting it on the face lights the whole skull, and from a shoulder
## camera that reads as the beam leaving the back of the head. First person
## also needs the start past the near clip, or the same glow fills the view
## from inside the cranium.
const MUZZLE_CLEARANCE := 0.12
const CAMERA_NEAR_PAD := 0.08

## How many short stretches make a wobbling beam. Straight beams use the first
## one only. The wave is drawn along the shot, not by swinging the whole line.
const WAVE_SEGS := 8
## Homing and bounce paths can carry more corners than a wobble. Cap so a
## curved shot does not spawn a cylinder for every authored point.
const PATH_SEGS_MAX := 12

## One EnergyVfx chain per eye-and-target. Each entry is a chain of segments.
var _beams: Array[Array] = []
var _lamp: OmniLight3D
var _alive := 0.0
var _colour := COLOR
var _invert := false
var _width_scale := 1.0
var _wobble := 0.0
var _follow := FOLLOW_EYES
var _from_left := Vector3.ZERO
var _from_right := Vector3.ZERO
var _target := Vector3.ZERO
var _targets: PackedVector3Array = PackedVector3Array()
var _paths: Array[PackedVector3Array] = []
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
var _layers: Dictionary = {}


func _ready() -> void:
	# One fiery cylinder chain per eye. Straight shots only ever light the
	# first of each chain.
	for _eye in 2:
		_beams.append([])
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
		follow := FOLLOW_EYES, far_cast := 0.0, invert := false) -> void:
	aim_many(left_eye, right_eye, PackedVector3Array([at]), colour, width_scale,
		wobble, follow, far_cast, [], invert)


func aim_many(left_eye: Vector3, right_eye: Vector3, targets: PackedVector3Array,
		colour: Color = COLOR, width_scale := 1.0, wobble := 0.0,
		follow := FOLLOW_EYES, far_cast := 0.0, paths: Array = [],
		invert := false, layer := -1) -> void:
	if _beams.is_empty():
		return
	var cleaned := PackedVector3Array()
	for at: Vector3 in targets:
		if at.is_finite():
			cleaned.append(at)
	if cleaned.is_empty():
		return
	var traces: Array[PackedVector3Array] = []
	for path_variant: Variant in paths:
		if path_variant is PackedVector3Array \
				and (path_variant as PackedVector3Array).size() >= 2:
			traces.append(path_variant)
	if traces.size() != cleaned.size():
		traces.clear()
	var row := {
		"left": left_eye,
		"right": right_eye,
		"targets": cleaned,
		"paths": traces,
		"colour": colour,
		"width": width_scale,
		"wobble": wobble,
		"follow": follow,
		"far": far_cast,
		"invert": invert,
	}
	if layer < 0:
		_layers.clear()
		_layers[-1] = row
	else:
		_layers.erase(-1)
		_layers[layer] = row
	_show_layers()


func _show_layers() -> void:
	var merged := PackedVector3Array()
	var traces: Array[PackedVector3Array] = []
	var keep_paths := true
	var last: Dictionary = {}
	for key: Variant in _layers:
		var row: Dictionary = _layers[key]
		if row.is_empty():
			continue
		last = row
		var layer_targets: PackedVector3Array = row.get(
			"targets", PackedVector3Array())
		var layer_paths: Array = row.get("paths", [])
		if layer_paths.size() != layer_targets.size():
			keep_paths = false
		for at: Vector3 in layer_targets:
			merged.append(at)
		for path_variant: Variant in layer_paths:
			if path_variant is PackedVector3Array:
				traces.append(path_variant)
	if merged.is_empty() or last.is_empty():
		return
	_from_left = last.get("left", Vector3.ZERO)
	_from_right = last.get("right", Vector3.ZERO)
	_targets = merged
	_paths.clear()
	if keep_paths and traces.size() == merged.size():
		_paths.append_array(traces)
	_target = _targets[int(_targets.size() / 2)]
	_ensure_pairs(_targets.size())
	_follow = int(last.get("follow", FOLLOW_EYES))
	_far_cast = maxf(float(last.get("far", 0.0)), 0.0)
	_wobble = maxf(float(last.get("wobble", 0.0)), 0.0)
	if _wobble > 0.0:
		if not _wobble_rolled:
			_roll_wobble()
	else:
		_wobble_rolled = false
	_set_colour(last.get("colour", COLOR), bool(last.get("invert", false)))
	# World radius is [constant RADIUS] times this scale. Kame passes
	# combat radius / RADIUS so the drawn cylinder matches the hit.
	# A hard 4.5 cap used to freeze a boosted kame at basketball size
	# while the trench and mob capsule kept growing.
	_width_scale = clampf(float(last.get("width", 1.0)), 0.2, 200.0)
	_draw_now()
	if _lamp != null and is_inside_tree():
		_lamp.global_position = _target
		_lamp.visible = true
		_lamp.omni_range = 5.5 * _width_scale
		_lamp.light_energy = (3.4 if _colour == COLOR else 2.0) * _width_scale
	_alive = HOLD
	set_process(true)


func _set_colour(colour: Color, invert := false) -> void:
	colour = Color(colour.r, colour.g, colour.b, 1.0)
	if colour == _colour and invert == _invert:
		return
	_colour = colour
	_invert = invert
	for chain: Array in _beams:
		for beam: Variant in chain:
			var effect := beam as EnergyVfx
			if effect != null:
				effect.set_tint(colour, invert)
	if _lamp != null:
		_lamp.light_color = colour
		_lamp.light_energy = 3.4 if colour == COLOR else 2.0


func is_lit() -> bool:
	return _alive > 0.0


func pair_count() -> int:
	return _targets.size()


## Takes the beams down now, for the firing player letting go.
## A non-negative [param layer] drops only that slot's pair so two Laser
## Eyes can share the drawer.
func stop(layer := -1) -> void:
	if layer >= 0 and is_inside_tree():
		_layers.erase(layer)
		if not _layers.is_empty():
			_show_layers()
			return
	_layers.clear()
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
		bounced.append(_clear_muzzle(from, path[1]))
		for index in range(1, path.size()):
			bounced.append(path[index])
		return bounced
	if _wobble <= 0.001:
		return PackedVector3Array([_clear_muzzle(from, to), to])
	return _wave_points(_clear_muzzle(from, to), to, eye & 1)


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
		_beams.append([])
		_beams.append([])
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
	if chain < 0 or chain >= _beams.size():
		return
	var points := PackedVector3Array()
	points.append(from)
	for index in range(1, path.size()):
		points.append(path[index])
	if points.size() >= 2:
		points[0] = _clear_muzzle(points[0], points[1])
	var segs := points.size() - 1
	if segs <= 1:
		_draw_eye(eye, from, points[points.size() - 1] if points.size() > 1 \
			else from, slot)
		return
	if segs > PATH_SEGS_MAX:
		points = _resample_path(points, PATH_SEGS_MAX)
		segs = points.size() - 1
	var beams: Array = _beams[chain]
	_ensure_chain(beams, segs)
	for index in beams.size():
		if index < segs:
			_place(beams[index], points[index], points[index + 1])
		else:
			(beams[index] as EnergyVfx).visible = false


func _hide_eye(slot: int) -> void:
	if slot < 0 or slot >= _beams.size():
		return
	var beams: Array = _beams[slot]
	for beam: Variant in beams:
		(beam as EnergyVfx).visible = false


func _draw_eye(eye: int, from: Vector3, to: Vector3, slot := -1) -> void:
	var chain := eye if slot < 0 else slot
	if chain < 0 or chain >= _beams.size():
		return
	var beams: Array = _beams[chain]
	from = _clear_muzzle(from, to)
	if _wobble <= 0.001:
		_ensure_chain(beams, 1)
		_place(beams[0], from, to)
		for index in range(1, beams.size()):
			(beams[index] as EnergyVfx).visible = false
		return
	var points := _wave_points(from, to, eye)
	_ensure_chain(beams, WAVE_SEGS)
	for index in beams.size():
		if index < WAVE_SEGS:
			_place(beams[index], points[index], points[index + 1])
		else:
			(beams[index] as EnergyVfx).visible = false


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


func _clear_muzzle(from: Vector3, to: Vector3) -> Vector3:
	var along := to - from
	var span := along.length()
	if span < 0.05:
		return from
	var dir := along / span
	var inset := MUZZLE_CLEARANCE
	var shooter := get_parent() as OnlinePlayer
	if shooter != null and shooter.camera != null and shooter.camera.current:
		var cam := shooter.camera
		var cam_forward := -cam.global_basis.z
		var toward := dir.dot(cam_forward)
		if toward > 0.05:
			var need := cam.near + CAMERA_NEAR_PAD \
				- (from - cam.global_position).dot(cam_forward)
			inset = maxf(inset, need / toward)
	return from + dir * clampf(inset, 0.0, span * 0.35)


## Stretches one authored core-beam between two points. The GLB stands along
## its own +Y from the muzzle, so the placement scales that axis to the span
## and never fattens the glow as the shot gets longer.
func _place(beam: EnergyVfx, from: Vector3, to: Vector3) -> void:
	if beam == null:
		return
	beam.place_beam(from, to, RADIUS * _width_scale)


func _hide() -> void:
	for chain: Array in _beams:
		for beam: Variant in chain:
			(beam as EnergyVfx).visible = false
	if _lamp != null:
		_lamp.visible = false


func _ensure_chain(chain: Array, count: int) -> void:
	while chain.size() < count:
		chain.append(_make_beam())


func _make_beam() -> EnergyVfx:
	var beam := EnergyVfx.make(EnergyVfx.Kind.BEAM_CORE, _colour, _invert)
	beam.visible = false
	beam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(beam)
	return beam


func _resample_path(points: PackedVector3Array, segs: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(segs + 1)
	var last := float(points.size() - 1)
	for index in out.size():
		var src := (float(index) / float(segs)) * last
		var a := clampi(int(src), 0, points.size() - 1)
		var b := mini(a + 1, points.size() - 1)
		out[index] = points[a].lerp(points[b], src - float(a))
	return out
