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
var _aim_left := 0.0
var _pending_shot := false


func _ready() -> void:
	_base_health = 6.0
	_base_damage = 8.0
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
	return hit_height() * 0.5 + 4.0


func flyer_ceiling() -> float:
	return maxf(super.flyer_ceiling(), flyer_floor() + 8.0)


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


func _tick_idle(delta: float) -> void:
	_abort_aim()
	_patrol(delta, 0.58)


func _tick_ai(delta: float) -> void:
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	var at := _combat_position_of(player)
	var hold := lerpf(_track_hold_min(), _track_hold_max(), _hold_share())
	var desired := _hover_hold(at, hold)
	if _aiming():
		_hold_to_aim(player, desired, delta)
		_keep_off_crown(player)
	else:
		_flyer_track(player, delta)
	_try_fire(player, _flat_gap(player), delta)


func _rank() -> int:
	return CrawlerRules.ranger_rank(threat_level)


func _track_rank() -> int:
	return _rank()


func _track_hold_min() -> float:
	return CrawlerRules.ranger_standoff_min(_rank())


func _track_hold_max() -> float:
	return CrawlerRules.ranger_standoff_max(_rank())


func _aiming() -> bool:
	return _aim_left > 0.0


func _abort_aim() -> void:
	_aim_left = 0.0
	_pending_shot = false
	_faces_motion = true


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
