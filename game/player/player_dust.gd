class_name PlayerDust
extends Node3D

## White ground dust for movement and player-caused impacts.
##
## Two continuous emitters follow the soles of the animated feet. Their
## particles use world coordinates, so each puff stays where the foot kicked it
## up instead of following the body and the pair reads as a trail. A small pool
## of one-shot emitters handles take-off, landing and weapon impacts without
## allocating a particle system on every event.

const FOOT_BONES: Array[StringName] = [&"LeftFoot", &"RightFoot"]
const FOOT_SIDES: Array[float] = [-1.0, 1.0]
## The foot bones begin at the ankles, about 8.5 cm above the soles on the
## shipped character. Dropping along the planet normal puts each emitter under
## the foot instead of above and outside it.
const FOOT_SOLE_DROP := 0.085
const FALLBACK_FOOT_HALF_SPACING := 0.125
const FALLBACK_SOLE_CLEARANCE := 0.018
const TRAIL_POOL := 2
## Shared by ground rings and impact clouds. Eight lets a sustained laser reuse
## slots without immediately cutting off the much longer meteor plume.
const BURST_POOL := 8
const LASER_CLOUD_INTERVAL_MSEC := 160
const LASER_CLOUD_RELOCATE := 0.65

var burst_count := 0
var impact_count := 0
var laser_impact_count := 0
var trail_start_count := 0

var _body: CharacterBody3D
var _bound_character: Node3D
var _skeleton: Skeleton3D
var _foot_ids := PackedInt32Array([-1, -1])
var _trails: Array[GPUParticles3D] = []
var _trail_processes: Array[ParticleProcessMaterial] = []
var _bursts: Array[GPUParticles3D] = []
var _burst_processes: Array[ParticleProcessMaterial] = []
var _burst_cursor := 0
var _dust_mesh: QuadMesh
var _laser_cloud_msec := -LASER_CLOUD_INTERVAL_MSEC
var _laser_cloud_at := Vector3.INF


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_dust_mesh = _make_dust_mesh()
	var trail_fade := _fade_ramp(0.06, 0.52, 0.8)
	var trail_growth := _growth_curve(0.4, 1.0, 2.0)
	for index in TRAIL_POOL:
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = 0.06
		# Up and back from the sole. No lateral component: the old mirrored X
		# kick made the dust appear from the outside edges of the feet.
		process.direction = Vector3(0.0, 0.48, 0.7).normalized()
		process.spread = 22.0
		process.initial_velocity_min = 0.45
		process.initial_velocity_max = 1.15
		process.gravity = Vector3.DOWN * 0.7
		process.damping_min = 1.4
		process.damping_max = 2.8
		process.scale_min = 0.16
		process.scale_max = 0.34
		process.scale_curve = trail_growth
		process.color = Color(1.0, 1.0, 1.0, 0.82)
		process.color_ramp = trail_fade

		var trail := GPUParticles3D.new()
		trail.name = "LeftFootTrail" if index == 0 else "RightFootTrail"
		trail.amount = 42
		trail.lifetime = 0.68
		trail.preprocess = 0.12
		trail.randomness = 0.72
		trail.local_coords = false
		trail.fixed_fps = 30
		trail.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
		trail.visibility_aabb = AABB(
			Vector3(-12.0, -4.0, -12.0), Vector3(24.0, 8.0, 24.0))
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trail.process_material = process
		trail.draw_pass_1 = _dust_mesh
		trail.emitting = false
		add_child(trail, false, Node.INTERNAL_MODE_BACK)
		_trail_processes.append(process)
		_trails.append(trail)

	var burst_fade := _fade_ramp(0.035, 0.58, 0.76)
	var burst_growth := _growth_curve(0.25, 1.0, 2.35)
	for index in BURST_POOL:
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		process.emission_ring_axis = Vector3.UP
		process.emission_ring_height = 0.035
		process.emission_ring_radius = 0.5
		process.emission_ring_inner_radius = 0.28
		process.direction = Vector3.UP
		process.spread = 68.0
		process.initial_velocity_min = 1.1
		process.initial_velocity_max = 2.4
		process.radial_accel_min = 3.2
		process.radial_accel_max = 6.2
		process.gravity = Vector3.DOWN * 2.0
		process.damping_min = 1.1
		process.damping_max = 2.2
		process.scale_min = 0.16
		process.scale_max = 0.34
		process.scale_curve = burst_growth
		process.color = Color(1.0, 1.0, 1.0, 0.78)
		process.color_ramp = burst_fade

		var burst := GPUParticles3D.new()
		burst.name = "DustBurst%d" % index
		burst.amount = 32
		burst.lifetime = 0.78
		burst.one_shot = true
		burst.explosiveness = 1.0
		burst.randomness = 0.7
		burst.local_coords = false
		burst.fixed_fps = 30
		burst.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
		burst.visibility_aabb = AABB(
			Vector3(-22.0, -8.0, -22.0), Vector3(44.0, 30.0, 44.0))
		burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		burst.process_material = process
		burst.draw_pass_1 = _dust_mesh
		burst.emitting = false
		add_child(burst, false, Node.INTERNAL_MODE_BACK)
		_burst_processes.append(process)
		_bursts.append(burst)


## Follows the animated feet and switches their world-space trails together.
##
## [param travel] is tangent velocity. It gives the emitters a frame whose +Z
## points behind the runner, so each puff is kicked slightly up and back.
func update_trails(character: Node3D, up: Vector3, travel: Vector3,
		speed: float, sprinting: bool) -> void:
	if _trails.is_empty() or _body == null:
		return
	_bind_character(character)
	var outward := up.normalized() if up.length_squared() > 0.001 \
		else _body.global_basis.y.normalized()
	var right := _body.global_basis.x
	right = (right - outward * right.dot(outward)).normalized()
	if right.length_squared() < 0.5:
		right = outward.cross(Vector3.FORWARD).normalized()
	var back := -travel.normalized() if travel.length_squared() > 0.01 \
		else _body.global_basis.z.normalized()
	back = (back - outward * back.dot(outward)).normalized()
	if back.length_squared() < 0.5:
		back = right.cross(outward).normalized()
	var frame := Basis(right, outward, back).orthonormalized()
	var wanted := sprinting and _body.is_visible_in_tree()
	var density := clampf(0.56 + speed / 90.0, 0.56, 1.0)

	for index in _trails.size():
		var trail := _trails[index]
		var point := _foot_point(index, outward, right)
		trail.global_transform = Transform3D(frame, point)
		trail.amount_ratio = density
		_trail_processes[index].gravity = -outward * 0.7
		if wanted and not trail.emitting:
			trail.restart()
			trail_start_count += 1
		trail.emitting = wanted


## Throws an expanding white ring from the ground.
##
## [param strength] is deliberately a small presentation scale, not an impact
## speed: 0.7 is a jump, about 1.2 a long fall, and 2 a Hero landing.
func pop_ground(at: Vector3, up: Vector3, strength := 1.0) -> void:
	if _bursts.is_empty() or not at.is_finite():
		return
	var power := clampf(strength, 0.55, 2.25)
	var outward := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var side := outward.cross(
		Vector3.UP if absf(outward.y) < 0.9 else Vector3.RIGHT).normalized()
	var frame := Basis(side, outward, side.cross(outward)).orthonormalized()
	var slot := _burst_cursor
	_burst_cursor = (_burst_cursor + 1) % _bursts.size()
	var burst := _bursts[slot]
	var process := _burst_processes[slot]

	process.emission_ring_height = 0.035
	process.emission_ring_radius = 0.34 + power * 0.17
	process.emission_ring_inner_radius = maxf(
		process.emission_ring_radius - (0.16 + power * 0.035), 0.08)
	process.direction = Vector3.UP
	process.spread = 68.0
	process.initial_velocity_min = 0.85 + power * 0.5
	process.initial_velocity_max = 1.65 + power * 1.0
	process.radial_accel_min = 2.3 + power * 1.25
	process.radial_accel_max = 4.4 + power * 2.4
	process.gravity = -outward * (1.35 + power * 0.45)
	process.damping_min = 1.1
	process.damping_max = 2.2
	process.scale_min = 0.13 + power * 0.035
	process.scale_max = 0.26 + power * 0.09
	process.color = Color(1.0, 1.0, 1.0, 0.64 + power * 0.09)
	burst.amount = clampi(22 + roundi(power * 12.0), 28, 50)
	burst.lifetime = 0.58 + power * 0.16
	burst.explosiveness = 1.0
	burst.global_transform = Transform3D(frame, at + outward * 0.025)
	burst.restart()
	burst.emitting = true
	burst_count += 1


## Kicks a shallow disc of white dust up around a weapon impact.
##
## Radius is the affected ground, not a particle size. A laser uses less than a
## metre; Meteor hands over its six-to-twelve-metre crater radius. All of them are
## clamped before they reach counts, scale or bounds.
##
## The upper bound is well short of the widest blast in the game. A nuke reaches a
## hundred metres and this is the skirt of dust at the foot of it, not the blast
## itself — spread over the whole radius the same handful of puffs would be a few
## specks scattered across a field.
func impact_cloud(at: Vector3, up: Vector3, radius: float,
		strength := 1.0) -> void:
	if _bursts.is_empty() or not at.is_finite():
		return
	var span := clampf(radius, 0.3, 80.0)
	var power := clampf(strength, 0.3, 2.5)
	var outward := up.normalized() if up.length_squared() > 0.001 else Vector3.UP
	var side := outward.cross(
		Vector3.UP if absf(outward.y) < 0.9 else Vector3.RIGHT).normalized()
	var frame := Basis(side, outward, side.cross(outward)).orthonormalized()
	var slot := _burst_cursor
	_burst_cursor = (_burst_cursor + 1) % _bursts.size()
	var burst := _bursts[slot]
	var process := _burst_processes[slot]

	# Inner radius zero fills the ring into a shallow disc: dust rises from the
	# whole struck patch instead of drawing only its circumference.
	process.emission_ring_height = minf(0.06 + span * 0.045, 0.55)
	process.emission_ring_radius = span
	process.emission_ring_inner_radius = 0.0
	process.direction = Vector3.UP
	process.spread = 76.0
	process.initial_velocity_min = 0.65 + power * 0.65 + sqrt(span) * 0.12
	process.initial_velocity_max = 1.35 + power * 1.35 + sqrt(span) * 0.42
	process.radial_accel_min = 1.2 + power * 0.9
	process.radial_accel_max = 2.8 + power * 2.0
	process.gravity = -outward * (0.85 + power * 0.35)
	process.damping_min = 0.75
	process.damping_max = 1.65
	process.scale_min = clampf(0.1 + span * 0.055, 0.12, 1.9)
	process.scale_max = clampf(0.2 + span * 0.13 + power * 0.08, 0.26, 4.8)
	process.color = Color(1.0, 1.0, 1.0, clampf(0.62 + power * 0.08, 0.0, 0.86))
	burst.amount = clampi(roundi(12.0 + span * 6.0 + power * 9.0), 16, 210)
	burst.lifetime = clampf(0.48 + span * 0.095 + power * 0.2, 0.62, 3.4)
	# Almost one-shot rather than exactly one: the fraction of a second over
	# which the puffs leave makes a cloud billow instead of becoming one frame
	# of evenly-spaced white dots.
	burst.explosiveness = 0.9
	burst.global_transform = Transform3D(frame, at + outward * 0.045)
	burst.restart()
	burst.emitting = true
	impact_count += 1


## Rate-limited form for a sustained beam. A moving point may emit immediately,
## while a beam held still gets a fresh puff roughly five times a second.
func laser_impact(at: Vector3, up: Vector3, radius := 0.6,
		strength := 0.55, immediate := false) -> bool:
	if not at.is_finite():
		return false
	if not immediate:
		var now := Time.get_ticks_msec()
		var moved := _laser_cloud_at == Vector3.INF \
			or at.distance_to(_laser_cloud_at) >= LASER_CLOUD_RELOCATE
		if now - _laser_cloud_msec < LASER_CLOUD_INTERVAL_MSEC and not moved:
			return false
		_laser_cloud_msec = now
		_laser_cloud_at = at
	impact_cloud(at, up, radius, strength)
	laser_impact_count += 1
	return true


func trail_emitters() -> Array[GPUParticles3D]:
	return _trails


func burst_emitters() -> Array[GPUParticles3D]:
	return _bursts


func _bind_character(character: Node3D) -> void:
	if character == _bound_character and is_instance_valid(_skeleton):
		return
	_bound_character = character
	_skeleton = Wardrobe.skeleton_of(character) if character != null else null
	_foot_ids = PackedInt32Array([-1, -1])
	if _skeleton == null:
		return
	for index in FOOT_BONES.size():
		_foot_ids[index] = CharacterRig.find_bone(_skeleton, FOOT_BONES[index])


func _foot_point(index: int, up: Vector3, right: Vector3) -> Vector3:
	var side := FOOT_SIDES[index]
	var bone := _foot_ids[index] if index < _foot_ids.size() else -1
	if _skeleton != null and bone >= 0:
		var pose := _skeleton.get_bone_global_pose(bone)
		return _skeleton.global_transform * pose.origin - up * FOOT_SOLE_DROP
	return _body.global_position + right * side * FALLBACK_FOOT_HALF_SPACING \
		+ up * FALLBACK_SOLE_CLEARANCE


func _fade_ramp(appear: float, soften: float, middle_alpha: float) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, appear, soften, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, middle_alpha),
		Color(1.0, 1.0, 1.0, middle_alpha * 0.48),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _growth_curve(first: float, middle: float, last: float) -> CurveTexture:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = maxf(last, 1.0)
	curve.add_point(Vector2(0.0, first))
	curve.add_point(Vector2(0.22, middle))
	curve.add_point(Vector2(1.0, last))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


func _make_dust_mesh() -> QuadMesh:
	const SIZE := 48
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(SIZE) \
				* 2.0 - Vector2.ONE
			var radius := point.length()
			var angle := atan2(point.y, point.x)
			# Broad lobes break the perfect disc without introducing tiny noise
			# that would shimmer when a puff is only a few pixels wide.
			var edge := 0.78 + sin(angle * 5.0 + 0.6) * 0.055 \
				+ sin(angle * 3.0 - 1.1) * 0.045
			var alpha := 1.0 - smoothstep(0.28, edge, radius)
			alpha *= 1.0 - smoothstep(0.72, 1.0, radius)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	var texture := ImageTexture.create_from_image(image)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.98, 0.99, 1.0, 0.92)
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.disable_receive_shadows = true
	material.render_priority = 4
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	return quad
