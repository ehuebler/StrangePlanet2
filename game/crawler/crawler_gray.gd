class_name CrawlerGray
extends CrawlerAlien

## Ground rifleman. Closes to a standoff, aims, then lobs a slow green
## homing orb. Scout wrecks also drop one from the air.

const SHOT := preload("res://game/crawler/crawler_gray_shot.gd")
const HEIGHT := 1.82
const WIDTH := 0.62
const DROP_GRAVITY := 22.0

var _aim_left := 0.0
var _pending_shot := false
var _dropping := false


func _ready() -> void:
	_base_health = 5.0
	_base_damage = 7.0
	_base_speed = 7.4
	super._ready()


func wild_kind() -> String:
	return "gray"


func muzzle_bone() -> String:
	return "socket_muzzle"


func body_height() -> float:
	return HEIGHT * BODY_SCALE


func body_width() -> float:
	return WIDTH * BODY_SCALE


func flies() -> bool:
	return false


func begin_drop() -> void:
	_dropping = true
	_faces_motion = false
	set_physics_process(true)


func _keep_clear_of_terrain(snap: bool) -> void:
	if _dropping:
		return
	super._keep_clear_of_terrain(snap)


func _director_climb() -> void:
	if _dropping:
		return
	super._director_climb()


func dropping() -> bool:
	return _dropping


func _tick_idle(delta: float) -> void:
	if _dropping:
		_fall(delta)
		return
	_abort_aim()
	snap_to_ground()
	_match_speed(move_speed() * 0.42, delta, 1.4)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or _flat_toward(_patrol_goal).length() < 2.2:
		_patrol_serial += 1
		_patrol_left = PATROL_RETARGET + float(_patrol_serial % 7) * 0.35
		_patrol_goal = _wander_point()
	var along := _flat_toward(_patrol_goal)
	if along.length_squared() < 0.2:
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 10.0)


func _tick_ai(delta: float) -> void:
	if _dropping:
		_fall(delta)
		return
	_fire_left = maxf(_fire_left - delta, 0.0)
	snap_to_ground()
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	if _aiming():
		_hold_aim(player, delta)
		_try_fire(player, delta)
		return
	_close_and_aim(player, delta)


func _tick_far(delta: float) -> void:
	if _dropping:
		_fall(delta)
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_close_and_aim(player, delta)
		return
	_tick_idle(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	if _dropping:
		_fall(delta)
		return
	var step := maxf(delta, 0.0)
	if player != null and _apply_agro(player, step, in_city):
		_close_and_aim(player, step)
	else:
		_tick_idle(step)


func _close_and_aim(player: Node, delta: float) -> void:
	_faces_motion = true
	var at := _combat_position_of(player)
	var along := _flat_toward(at)
	var gap := along.length()
	var near := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_min", 12.0)
	var far := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_max", 28.0)
	if gap > far:
		_match_speed(move_speed(), delta, 1.2, 12.0)
		if along.length_squared() > 0.0001:
			_steer_toward(along.normalized() * _cruise, delta, 12.0)
		return
	if gap < near:
		_match_speed(move_speed() * 0.7, delta, 1.1, 10.0)
		if along.length_squared() > 0.0001:
			_steer_toward(-along.normalized() * _cruise, delta, 10.0)
		return
	velocity = velocity.move_toward(Vector3.ZERO, 16.0 * delta)
	_try_fire(player, delta)


func _aiming() -> bool:
	return _aim_left > 0.0


func _abort_aim() -> void:
	_aim_left = 0.0
	_pending_shot = false
	_act = ""
	_faces_motion = true


func _hold_aim(player: Node, delta: float) -> void:
	_faces_motion = false
	_act = CLIP_AIM
	_match_speed(0.0, delta, 4.0, 28.0)
	velocity = velocity.move_toward(Vector3.ZERO, 24.0 * delta)
	var look := _flat_toward(_combat_position_of(player))
	if look.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(look.normalized(), _up())


func _try_fire(player: Node, delta: float) -> void:
	if _aiming():
		_aim_left = maxf(_aim_left - delta, 0.0)
		if _aim_left > 0.0:
			return
		if _pending_shot:
			_release_shot(player)
		return
	if _fire_left > 0.0:
		return
	var gap := _flat_gap(player)
	var near := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_min", 12.0)
	var far := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_max", 28.0)
	if gap < near or gap > far:
		return
	var aim := CrawlerMobs.number(
		wild_kind(), threat_level, "aim_seconds", CrawlerRules.GRAY_AIM)
	if not _begin_attack(aim):
		return
	_pending_shot = true
	_aim_left = aim
	_act = CLIP_AIM


func _release_shot(player: Node) -> void:
	_pending_shot = false
	_faces_motion = true
	_act = ""
	var from := muzzle_point()
	var target := _combat_position_of(player)
	var shot_speed := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_speed", CrawlerRules.GRAY_SHOT_SPEED)
	var heading := target - from
	if heading.length_squared() < 0.0001:
		heading = global_transform.basis.z
	_fire_left = fire_scale()
	var ball_radius := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_ball", 0.58)
	var hit_radius := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_hit", 1.3)
	_spawn_shot(from, heading, shot_speed, ball_radius, hit_radius, player)
	if _horde != null and _horde.has_method(&"publish_gray_shot"):
		_horde.call(
			&"publish_gray_shot", from, heading.normalized() * shot_speed,
			damage(), shot_speed, ball_radius, hit_radius)


func _spawn_shot(
		from: Vector3, along: Vector3, shot_speed: float,
		ball_radius: float, hit_radius: float, player: Node
	) -> void:
	var ball := SHOT.new()
	ball.damage = damage()
	ball.shot_speed = shot_speed
	ball.ball_radius = ball_radius
	ball.hit_radius = hit_radius
	ball.prey = player
	ball.homing_left = CrawlerRules.GRAY_HOMING
	var world: Node = _planet
	if world == null:
		world = DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	if world == null or not ball.launch_anywhere(world, from, along, self):
		ball.free()


func _fall(delta: float) -> void:
	var up := _up()
	velocity -= up * DROP_GRAVITY * delta
	var surface := ground_surface(global_position)
	if not surface.is_finite():
		return
	if (global_position - surface).dot(up) <= ground_clearance() + 0.35:
		snap_to_ground()
		velocity -= up * velocity.dot(up)
		_dropping = false
		_faces_motion = true
