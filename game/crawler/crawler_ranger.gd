class_name CrawlerRanger
extends CrawlerMob

## Bell-shaped flyer. Holds a spherical standoff and lobs a led shot at where
## the player will be, not where they are. After it matches the player's speed
## it rides that same velocity and drifts in their frame.

const SHOT := preload("res://game/crawler/crawler_ranger_shot.gd")
const MODEL := preload("res://assets/runtime/fauna/models/knell_bell.glb")
const PAINT := preload("res://assets/runtime/biomes/paint/knell_bell_paint.png")

const HEIGHT := 13.8
const RADIUS := 3.15
const HIT_PAD := 2.6
const AUTHORED_HEIGHT := 2.40
const SHOT_GRAVITY := 16.0
const BASE_FIRE := 1.35
const BODY_BLUE := Color(0.16, 0.42, 0.94)
const BODY_RED := Color(0.92, 0.07, 0.12)
const RIM_BLUE := Color(0.40, 0.78, 1.0)
const RIM_RED := Color(1.0, 0.22, 0.28)
var _fire_left := 0.0
var _drift_clock := 0.0
var _aim_left := 0.0
var _pending_shot := false
var _hold_cached := -1.0


func _ready() -> void:
	_base_health = 70.0
	_base_damage = 14.0
	_base_speed = 42.0
	_faces_motion = true
	super._ready()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var side := hit_box()
	box.size = Vector3(side, side, side)
	shape.shape = box
	add_child(shape)
	_attach_creature(MODEL, PAINT, AUTHORED_HEIGHT, HEIGHT, BODY_BLUE)
	_paint_mood(0.0)


func wild_kind() -> String:
	return "ranger"


func combat_display_name() -> String:
	return "Ranger"


func combat_position() -> Vector3:
	return global_position


func combat_radius() -> float:
	return hit_box() * 0.5


func combat_aabb() -> AABB:
	var half := hit_box() * 0.5
	var at := combat_position()
	return AABB(at - Vector3.ONE * half, Vector3.ONE * (half * 2.0))


func hit_radius() -> float:
	return RADIUS + HIT_PAD


func hit_height() -> float:
	return HEIGHT + HIT_PAD * 2.0


func hit_box() -> float:
	return maxf(hit_height(), hit_radius() * 2.0)


func flyer_floor() -> float:
	return hit_height() * 0.5 + 2.0


func _wander_point() -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(mob_id) * 41 + _patrol_serial * 73) & 0x7fffffff)
	var yaw := rng.randf() * TAU
	var reach := rng.randf_range(22.0, CrawlerRules.PATROL_RADIUS)
	var at := hang_origin + (east * cos(yaw) + north * sin(yaw)) * reach
	return _clamp_flyer_band(at)


func _tick_ai(delta: float) -> void:
	var player := _hunt_target(delta)
	if player == null:
		_abort_aim()
		_patrol(delta, 0.58)
		return
	var at := _combat_position_of(player)
	var offset := global_position - at
	var distance := offset.length()
	var player_speed := _player_speed(player)
	var hold := lerpf(
		CrawlerRules.ranger_standoff_min(_rank()),
		CrawlerRules.ranger_standoff_max(_rank()),
		_hold_share()
	)
	var desired := _hover_hold(at, hold)
	var gap := global_position.distance_to(desired)
	if _aiming():
		_hold_to_aim(player, desired, delta)
	elif _is_matched(player, player_speed, gap, hold):
		_drift_in_frame(player, desired, delta)
	else:
		_close_on(desired, gap, hold, distance, player_speed, delta)
	_keep_off_crown(player)
	_try_fire(player, _flat_gap(player), delta)


func _rank() -> int:
	return CrawlerRules.ranger_rank(threat_level)


func _is_matched(player: Node, player_speed: float, gap: float, hold: float) -> bool:
	var target := minf(
		player_speed, CrawlerRules.ranger_chase_speed(player_speed, _rank(), false))
	if absf(_cruise - target) > CrawlerRules.ranger_match_slack(player_speed, _rank()):
		return false
	var flat := _flat_gap(player)
	if flat < CrawlerRules.RANGER_CROWN_CLEAR:
		return false
	return gap <= hold * 1.2 \
		or (flat >= CrawlerRules.ranger_standoff_min(_rank()) * 0.85 \
			and flat <= CrawlerRules.ranger_standoff_max(_rank()) * 1.2)


func _close_on(
		desired: Vector3,
		gap: float,
		hold: float,
		distance: float,
		player_speed: float,
		delta: float
	) -> void:
	var urgent := gap > hold * 0.55 \
		or distance > CrawlerRules.ranger_standoff_max(_rank())
	var wanted_speed := maxf(
		CrawlerRules.ranger_chase_speed(player_speed, _rank(), urgent),
		move_speed())
	_match_speed(
		wanted_speed, delta,
		CrawlerRules.ranger_match_lag(_rank()),
		CrawlerRules.ranger_match_floor(_rank()))
	var along := desired - global_position
	var heading := along.normalized() if along.length_squared() > 0.04 \
		else _orbit_bias()
	_steer_toward(heading * _cruise, delta, 15.0)


func _drift_in_frame(player: Node, desired: Vector3, delta: float) -> void:
	var player_speed := _player_speed(player)
	_match_speed(
		CrawlerRules.ranger_chase_speed(player_speed, _rank(), false),
		delta,
		CrawlerRules.ranger_match_lag(_rank()),
		CrawlerRules.ranger_match_floor(_rank()))
	_drift_clock += delta
	var frame := _player_velocity(player)
	var up := _up()
	var ahead := frame - up * frame.dot(up)
	if ahead.length_squared() < 4.0:
		ahead = -_orbit_bias()
		ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		ahead = up.cross(Vector3.RIGHT)
	ahead = ahead.normalized()
	var side := up.cross(ahead)
	if side.length_squared() < 0.0001:
		side = up.cross(Vector3.FORWARD)
	side = side.normalized()
	var sway := maxf(_cruise * 0.09, 11.0)
	var phase := _hold_share() * TAU
	var bob := ahead * sin(_drift_clock * 1.28 + phase) * sway \
		+ side * sin(_drift_clock * 0.84 + phase * 1.7) * (sway * 1.15)
	var spring := (desired - global_position) * 1.15
	var ride := frame + bob + spring
	velocity = velocity.lerp(
		ride, clampf(CrawlerRules.ranger_match_lock(_rank()) * delta, 0.0, 1.0))
	_push_off_terrain(player, desired)


func _flat_gap(player: Node) -> float:
	var along := global_position - _combat_position_of(player)
	along -= _up() * along.dot(_up())
	return along.length()


func _hover_hold(at: Vector3, hold: float) -> Vector3:
	var up := _up()
	var reach := maxf(hold, CrawlerRules.RANGER_CROWN_CLEAR)
	var bias := _orbit_bias()
	bias -= up * bias.dot(up)
	if bias.length_squared() < 0.0001:
		bias = up.cross(Vector3.RIGHT)
	if bias.length_squared() < 0.0001:
		bias = Vector3.FORWARD
	bias = bias.normalized()
	var desired := _clamp_flyer_band(at + bias * reach)
	var along := desired - at
	var rise := along.dot(up)
	var flat := along - up * rise
	if flat.length() >= reach:
		return desired
	var out := flat if flat.length_squared() > 0.2 else bias
	out -= up * out.dot(up)
	if out.length_squared() < 0.0001:
		return desired
	return _clamp_flyer_band(at + out.normalized() * reach + up * rise)


func _push_off_terrain(player: Node, desired: Vector3) -> void:
	var up := _up()
	var floor_h := flyer_floor()
	var altitude := surface_altitude()
	var down := -velocity.dot(up)
	if down > 0.0 and altitude <= floor_h + 4.0:
		velocity += up * down
	if altitude >= floor_h + 2.4:
		return
	var away := global_position - _combat_position_of(player)
	away -= up * away.dot(up)
	if away.length_squared() < 0.2:
		away = desired - global_position
		away -= up * away.dot(up)
	if away.length_squared() > 0.2:
		velocity += away.normalized() * maxf(20.0, _cruise * 0.28)
	velocity += up * maxf((floor_h + 2.4 - altitude) * 7.0, 12.0)


func _hold_share() -> float:
	if _hold_cached >= 0.0:
		return _hold_cached
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(mob_id) & 0x7fffffff) + 4
	_hold_cached = rng.randf()
	return _hold_cached


func _aiming() -> bool:
	return _aim_left > 0.0


func _abort_aim() -> void:
	_aim_left = 0.0
	_pending_shot = false
	_faces_motion = true


func _keep_off_crown(player: Node) -> void:
	var at := _combat_position_of(player)
	var up := _up()
	var along := global_position - at
	var rise := along.dot(up)
	var flat := along - up * rise
	var clear := CrawlerRules.RANGER_CROWN_CLEAR
	if flat.length() >= clear:
		return
	var out := flat
	if out.length_squared() < 0.2:
		out = _orbit_bias()
		out -= up * out.dot(up)
	if out.length_squared() < 0.0001:
		out = up.cross(Vector3.RIGHT)
	if out.length_squared() < 0.0001:
		return
	var shove := (clear - flat.length()) / clear
	velocity += out.normalized() * maxf(22.0, _cruise * 0.28) * (0.7 + shove * 1.4)
	if rise > 2.0:
		velocity += up * minf(rise * 1.6, 12.0)


func _hold_to_aim(player: Node, desired: Vector3, delta: float) -> void:
	_faces_motion = false
	var frame := _player_velocity(player)
	_match_speed(frame.length(), delta, 1.4, 8.0)
	var spring := (desired - global_position) * 1.35
	velocity = velocity.lerp(
		frame + spring, clampf(4.2 * delta, 0.0, 1.0))
	var ahead := _combat_position_of(player) - global_position
	var up := _up()
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	var desired_basis := Basis.looking_at(ahead.normalized(), up).orthonormalized()
	if desired_basis.determinant() < 0.0:
		desired_basis.x = -desired_basis.x
	var current := global_transform.basis.orthonormalized()
	if current.determinant() < 0.0:
		current.x = -current.x
	global_transform.basis = Basis(
		current.get_rotation_quaternion().slerp(
			desired_basis.get_rotation_quaternion(),
			clampf(delta * 8.0, 0.0, 1.0))).orthonormalized()


func _try_fire(player: Node, distance: float, delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	if _aiming():
		_aim_left = maxf(_aim_left - delta, 0.0)
		if _aim_left > 0.0:
			return
		if _pending_shot:
			_release_shot(player)
		return
	_faces_motion = true
	if _fire_left > 0.0:
		return
	if distance < CrawlerRules.ranger_engage_min(_rank()) \
			or distance > CrawlerRules.ranger_engage_max(_rank()):
		return
	var aim := CrawlerMobs.number(
		"ranger", _rank(), "aim_seconds", CrawlerRules.RANGER_AIM_SECONDS)
	if not _begin_attack(aim):
		return
	_pending_shot = true
	_aim_left = aim


func _release_shot(player: Node) -> void:
	_pending_shot = false
	_faces_motion = true
	var from := combat_position()
	var target := _combat_position_of(player)
	var shot_speed := CrawlerRules.ranger_shot_speed(_player_speed(player), _rank())
	var launch := CrawlerRules.lead_launch(
		from, target, _player_velocity(player), shot_speed, SHOT_GRAVITY, _up())
	if launch.is_zero_approx():
		return
	_fire_left = fire_scale()
	var ball_radius := CrawlerRules.ranger_shot_ball(_rank())
	var hit_radius := CrawlerRules.ranger_shot_hit(_rank())
	_spawn_shot(from, launch, shot_speed, ball_radius, hit_radius)
	if _horde != null and _horde.has_method(&"publish_ranger_shot"):
		_horde.call(
			&"publish_ranger_shot", from, launch, damage(), shot_speed,
			ball_radius, hit_radius)


func _spawn_shot(
		from: Vector3, launch: Vector3, shot_speed: float,
		ball_radius: float, hit_radius: float
	) -> void:
	var ball := SHOT.new()
	ball.damage = damage()
	ball.gravity = SHOT_GRAVITY
	ball.shot_speed = shot_speed
	ball.ball_radius = ball_radius
	ball.hit_radius = hit_radius
	if _planet != null:
		if not ball.launch(_planet, from, launch, self):
			ball.free()
		return
	var world := DamageHit.game_world_of(self)
	if world == null or not ball.launch_anywhere(world, from, launch, self):
		ball.free()


func _update_flash() -> void:
	var warn := 0.0
	if _aiming():
		warn = 1.0 - _aim_left / maxf(CrawlerMobs.number(
			"ranger", _rank(), "aim_seconds", CrawlerRules.RANGER_AIM_SECONDS), 0.05)
	var hurt := _flash_left > 0.0
	_paint_mood(1.0 if hurt else warn)
	var flash := 0.92 if hurt else warn * 0.82
	for material in _materials:
		if material != null:
			material.set_shader_parameter(&"flash", flash)


func _paint_mood(warn: float) -> void:
	var share := clampf(warn, 0.0, 1.0)
	var colour := BODY_BLUE.lerp(BODY_RED, share)
	var rim := RIM_BLUE.lerp(RIM_RED, share)
	for material in _materials:
		if material == null:
			continue
		material.set_shader_parameter(&"albedo", colour)
		material.set_shader_parameter(&"rim_color", rim)
		material.set_shader_parameter(&"paint_mix", lerpf(0.38, 0.22, share))
		material.set_shader_parameter(&"rim_strength", lerpf(2.15, 2.7, share))
