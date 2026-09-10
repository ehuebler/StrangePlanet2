class_name CrawlerGlorbSpider
extends CrawlerWeaver

## Ethereal spider Glorb. Plants and charges a laser as soon as it agros.
## Outside shot range it accelerates toward the player, then plants again.
## The shot itself is a locked sweep: feet stay put, the body tilts to the
## player's height, look and laser travel the same arc, and the player sits
## at the middle of that pass.

const SHOT_RANGE := 20.0
const STOP_RANGE := 15.0
const PURSUE_SPEED := 15.0
const PURSUE_LAG := 0.42
const PURSUE_FLOOR := 5.0
const SWEEP_HALF := 0.58
const SWEEP_REACH := 32.0
const BEAM_OVERSHOOT := 6.0
const PITCH_LIMIT := 0.85
const PITCH_LEVEL := 0.07

var _sweep_center := Vector3.FORWARD
var _sweep_range := 16.0
var _sweep_up := Vector3.UP
var _sweep_pitch := 0.0
var _sweep_sign := 1.0
var _sweeping := false


func wild_kind() -> String:
	return CrawlerGlorb.KIND_SPIDER


func combat_display_name() -> String:
	return "Glorb Spider"


func body_height() -> float:
	return CrawlerGlorb.height(wild_kind())


func body_width() -> float:
	return CrawlerGlorb.height(wild_kind()) * 0.72


func move_speed() -> float:
	return minf(super.move_speed(), PURSUE_SPEED)


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_idle(delta)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	_fire_left = maxf(_fire_left - delta, 0.0)
	snap_to_ground()
	if beaming():
		_hold_beam(delta)
		return
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_tick_hunt_motion(player, delta)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	if beaming():
		_hold_beam(delta)
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_tick_hunt_motion(player, delta)
		return
	_tick_idle(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _maybe_glorb_inbound(maxf(delta, 0.0)):
		return
	if _movement_locked() or beaming():
		if beaming():
			_hold_beam(maxf(delta, 0.0))
		else:
			velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	if player != null and _apply_agro(player, step, in_city):
		_tick_hunt_motion(player, step)
	else:
		_tick_idle(step)


func _tick_hunt_motion(player: Node, delta: float) -> void:
	if player == null:
		return
	_hop_left = 0.0
	if beaming():
		_hold_beam(delta)
		return
	var gap := _shot_gap(player)
	if _should_plant_shot(gap):
		_plant_and_aim(player, delta)
		if _shot_ready(player, gap):
			_try_beam(player)
		return
	_run_at_player(player, delta)


func _shot_gap(player: Node) -> float:
	if player == null:
		return INF
	return global_position.distance_to(_combat_position_of(player))


func _should_plant_shot(gap: float) -> bool:
	if hunt_stance == CrawlerHunt.Stance.PURSUE:
		return gap <= STOP_RANGE
	return gap <= SHOT_RANGE


func _plant_and_aim(player: Node, _delta: float) -> void:
	_faces_motion = false
	_hop_left = 0.0
	_cruise = 0.0
	velocity = Vector3.ZERO
	if player == null:
		return
	var look := _aim_along(player)
	if look.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(look, _up())


func _chase_along(player: Node) -> Vector3:
	var along := _flat_toward(_combat_position_of(player))
	if along.length_squared() > 0.04:
		return along
	along = _combat_position_of(player) - global_position
	along.y = 0.0
	return along


func _run_at_player(player: Node, delta: float) -> void:
	_faces_motion = true
	_hop_left = 0.0
	var along := _chase_along(player)
	_match_speed(PURSUE_SPEED, delta, PURSUE_LAG, PURSUE_FLOOR)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 9.0)
	velocity -= _up() * velocity.dot(_up())


func _shot_ready(player: Node, gap: float) -> bool:
	if _fire_left > 0.0 or beaming():
		return false
	if hunt_stance == CrawlerHunt.Stance.PURSUE:
		return gap <= STOP_RANGE
	return gap <= SHOT_RANGE


func _try_beam(player: Node) -> void:
	_lock_sweep(player)
	super._try_beam(player)


func _hold_beam(delta: float) -> void:
	_faces_motion = false
	_hop_left = 0.0
	_cruise = 0.0
	velocity = Vector3.ZERO
	director_push = Vector3.ZERO
	if not _sweeping:
		var player := _beam_prey if is_instance_valid(_beam_prey) else _nearest_player()
		_lock_sweep(player)
	var look := sweep_heading()
	if look.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(look, _up())


func _face_combat_player(_delta: float) -> void:
	if beaming():
		_hold_beam(0.0)
		return
	super._face_combat_player(_delta)


func _beam_aim_at(player: Node) -> Vector3:
	if _sweeping:
		return sweep_point()
	return super._beam_aim_at(player)


func _lock_sweep(player: Node) -> void:
	if player == null:
		return
	var at := _combat_position_of(player)
	var parts := _split_aim(at)
	var along: Vector3 = parts[0]
	if along.length_squared() < 0.0001:
		along = global_transform.basis.z if _uses_model_front \
			else -global_transform.basis.z
		along -= _up() * along.dot(_up())
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	_sweep_center = along.normalized()
	_sweep_up = _up()
	_sweep_pitch = float(parts[1])
	_sweep_range = clampf(
		combat_position().distance_to(at) + BEAM_OVERSHOOT,
		10.0, SWEEP_REACH)
	_sweep_sign = _flank_sign()
	_sweeping = true


func sweep_share() -> float:
	if charging() or not firing():
		return 0.0
	var span := maxf(BEAM_SECONDS, 0.05)
	return clampf(1.0 - _beam_left / span, 0.0, 1.0)


func sweep_heading() -> Vector3:
	var center := _sweep_center
	if center.length_squared() < 0.0001:
		center = Vector3.FORWARD
	var lift := _sweep_up if _sweep_up.length_squared() > 0.0001 else _up()
	var angle := lerpf(-SWEEP_HALF, SWEEP_HALF, sweep_share()) * _sweep_sign
	return _compose_heading(center, _sweep_pitch, lift, angle)


func sweep_point() -> Vector3:
	return combat_position() + sweep_heading() * _sweep_range


func _stop_beam() -> void:
	_sweeping = false
	_sweep_pitch = 0.0
	super._stop_beam()


func _aim_along(player: Node) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var parts := _split_aim(_combat_position_of(player))
	var center: Vector3 = parts[0]
	if center.length_squared() < 0.0001:
		return Vector3.ZERO
	return _compose_heading(center, float(parts[1]), _up(), 0.0)


func _split_aim(at: Vector3) -> Array:
	var lift := _up()
	var along := at - combat_position()
	if along.length_squared() < 0.0001:
		along = at - global_position
	var rise := along.dot(lift)
	var flat := along - lift * rise
	if flat.length_squared() < 0.04:
		flat = _flat_toward(at)
	if flat.length_squared() < 0.0001:
		flat = global_transform.basis.z if _uses_model_front \
			else -global_transform.basis.z
		flat -= lift * flat.dot(lift)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	var pitch := clampf(atan2(rise, maxf(flat.length(), 0.001)), -PITCH_LIMIT, PITCH_LIMIT)
	if absf(pitch) < PITCH_LEVEL:
		pitch = 0.0
	return [flat.normalized(), pitch]


func _compose_heading(center: Vector3, pitch: float, lift: Vector3, yaw: float) -> Vector3:
	var up := lift.normalized() if lift.length_squared() > 0.0001 else Vector3.UP
	var heading := center
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	heading = heading.normalized().rotated(up, yaw)
	heading -= up * heading.dot(up)
	if heading.length_squared() < 0.0001:
		return center.normalized() if center.length_squared() > 0.0001 else Vector3.FORWARD
	heading = heading.normalized()
	return (heading * cos(pitch) + up * sin(pitch)).normalized()


func _eye_points() -> Array[Vector3]:
	var origin := combat_position() + _up() * 0.22
	if _head is Node3D:
		origin = _head.global_position
	var right := global_transform.basis.x
	var ahead := global_transform.basis.z if _uses_model_front \
		else -global_transform.basis.z
	if right.length_squared() < 0.0001:
		right = _up().cross(ahead)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	if ahead.length_squared() < 0.0001:
		ahead = -_up().cross(right)
	right = right.normalized() * 0.14
	ahead = ahead.normalized() * 0.10
	return [origin - right + ahead, origin + right + ahead]


func _on_agro_started() -> void:
	var player := _nearest_player()
	if player == null:
		return
	var gap := _shot_gap(player)
	if _should_plant_shot(gap) and _shot_ready(player, gap):
		_try_beam(player)


func _desired_clip() -> String:
	if _alive and beaming():
		return CLIP_TURRET
	if _alive and (hunt_stance == CrawlerHunt.Stance.PURSUE \
			or velocity.length() > 0.8):
		return CLIP_RUN
	return super._desired_clip()


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_TURRET or clip == CLIP_CAST or clip == CLIP_ATTACK:
		return PackedStringArray(["Ranged_Spit", clip])
	if clip == CLIP_LEAP or clip == CLIP_PINCER:
		return PackedStringArray(["Melee", clip])
	return super._clip_aliases(clip)
