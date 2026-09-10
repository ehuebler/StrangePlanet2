class_name CrawlerWeaver
extends CrawlerRobot

## Ground hunter. Hops into the player's camera to catch up, then plants,
## charges a red beam on the player, and burns Laser Eyes. Off-screen hops
## swing in front of the look first so the laser never starts from behind.

const EYES := preload("res://game/abilities/laser_beams.gd")

const HEIGHT := 1.74
const WIDTH := 1.15
const WEAVER_SCALE := 0.68
const PINCER_REACH := 2.05
const BEAM_SECONDS := 1.0
const BEAM_STEP := 0.1
const BEAM_DPS := 3.5
const BEAM_RADIUS := 0.45
const HOP_AIR := 0.34
const HOP_REST := 0.10
const SHOT_WHILE_RUNNING := 18.0
const SHOW_AHEAD := 12.0
const SHOW_SIDE := 3.4
const SHOW_READY := 5.5
const HOOK_SIDE := 10.0
const HOOK_AHEAD := 6.0
const VIEW_DOT := 0.42


var _hop_left := 0.0
var _aim_left := 0.0
var _beam_left := 0.0
var _beam_since := 0.0
var _beam_prey: Node
var _head: Node3D
var _beams: LaserBeams


func _ready() -> void:
	_base_health = 4.0
	_base_damage = 6.0
	_base_speed = 8.6
	super._ready()
	var model := find_child("Creature", true, false)
	if model != null:
		_head = MODELS.bind_socket(model, "head")
	_beams = EYES.new()
	_beams.name = "WeaverEyes"
	add_child(_beams)


func wild_kind() -> String:
	return "weaver"


func body_height() -> float:
	return HEIGHT * WEAVER_SCALE


func body_width() -> float:
	return WIDTH * WEAVER_SCALE


func flies() -> bool:
	return false


func charging() -> bool:
	return _aim_left > 0.0


func firing() -> bool:
	return _beam_left > 0.0


func beaming() -> bool:
	return charging() or firing()


func hopping() -> bool:
	return not beaming() and _hop_left > HOP_REST


func set_director_lod(lod: int) -> void:
	super.set_director_lod(lod)
	if beaming():
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if beaming():
		_service_beam(delta)


func _tick_idle(delta: float) -> void:
	_act = ""
	_hop_left = 0.0
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
	_fire_left = maxf(_fire_left - delta, 0.0)
	snap_to_ground()
	if beaming():
		_hold_beam(delta)
		return
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	var at := _combat_position_of(player)
	var along := _flat_toward(at)
	var gap := along.length()
	var pinch := PINCER_REACH * WEAVER_SCALE + _reach_of(player)
	if gap <= pinch:
		_faces_motion = true
		_match_speed(move_speed(), delta, 0.7, 8.0)
		if along.length_squared() > 0.0001:
			_steer_toward(along.normalized() * _cruise, delta, 12.0)
		_try_pincer(player, pinch)
		return
	_tick_hunt_motion(player, delta)
	if _shot_ready(player, gap):
		_try_beam(player)


func _tick_far(delta: float) -> void:
	if beaming():
		velocity = Vector3.ZERO
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_tick_hunt_motion(player, delta)
		return
	_tick_idle(delta)


func _tick_cold(delta: float, steer := true) -> void:
	if beaming():
		return
	super._tick_cold(delta, steer)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked() or beaming():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	if player != null and _apply_agro(player, step, in_city):
		_tick_hunt_motion(player, step)
	else:
		_tick_idle(step)


func _desired_clip() -> String:
	if _alive and beaming():
		return CLIP_TURRET
	if _alive and hopping():
		return CLIP_LEAP
	return super._desired_clip()


func _player_running(player: Node) -> bool:
	return CrawlerRules.rhino_running(_prey_speed(player))


func _prey_speed(player: Node) -> float:
	var up := _up()
	var motion := _player_velocity(player)
	motion -= up * motion.dot(up)
	return maxf(_player_speed(player), motion.length())


func _shot_ready(player: Node, gap: float) -> bool:
	if _fire_left > 0.0:
		return false
	if not in_camera(player):
		return false
	var far := CrawlerHunt.shot_max(wild_kind(), threat_level)
	if gap > far:
		return false
	return true


func _hop_chase(player: Node, delta: float) -> void:
	_faces_motion = true
	var at := hop_goal(player)
	var along := _flat_toward(at)
	if along.length_squared() < 0.0001:
		return
	var heading := along.normalized()
	var gap := _flat_toward(_combat_position_of(player)).length()
	var pace := CrawlerRules.rhino_chase_speed(
		_prey_speed(player), threat_level, gap > 14.0)
	_hop_left = maxf(_hop_left - delta, 0.0)
	if _hop_left <= 0.0:
		_hop_left = HOP_AIR + HOP_REST
	var burst := pace * (1.55 if hopping() else 0.55)
	_act = CLIP_LEAP if hopping() else ""
	_match_speed(burst, delta, 1.8, 16.0)
	_steer_toward(heading * _cruise, delta, 14.0)


func in_camera(player: Node) -> bool:
	if player == null:
		return false
	var to := combat_position() - _view_origin(player)
	if to.length_squared() < 1.2:
		return true
	return to.normalized().dot(_player_view(player)) >= VIEW_DOT


func hop_station(player: Node) -> Vector3:
	var origin := _view_origin(player)
	var lift := _view_up(player)
	var look := _flat_look(player)
	var right := look.cross(lift)
	if right.length_squared() < 0.0001:
		right = lift.cross(Vector3.RIGHT)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var perch := origin + look * SHOW_AHEAD + right * SHOW_SIDE * _flank_sign()
	return _ground_perch(perch)


func hop_goal(player: Node) -> Vector3:
	if in_camera(player):
		return _combat_position_of(player)
	var station := hop_station(player)
	if global_position.distance_to(station) <= SHOW_READY:
		return station
	var origin := _view_origin(player)
	var look := _flat_look(player)
	var lift := _view_up(player)
	var right := look.cross(lift)
	if right.length_squared() < 0.0001:
		return station
	right = right.normalized()
	var away := global_position - origin
	away -= lift * away.dot(lift)
	var side := signf(away.dot(right))
	if is_zero_approx(side):
		side = _flank_sign()
	return _ground_perch(origin + right * side * HOOK_SIDE + look * HOOK_AHEAD)


func _ground_perch(at: Vector3) -> Vector3:
	if not at.is_finite():
		return at
	var perch := at
	var up := _up()
	perch -= up * (perch - global_position).dot(up)
	if _planet == null:
		return perch
	var surface := ground_surface(perch)
	if surface.is_finite() and surface.distance_to(perch) < 12.0:
		up = _planet.up_at(surface)
		return surface + up * ground_clearance()
	return perch


func _flat_look(player: Node) -> Vector3:
	var lift := _view_up(player)
	var look := _player_view(player)
	look -= lift * look.dot(lift)
	if look.length_squared() < 0.0001:
		look = _flat_toward(_combat_position_of(player))
	if look.length_squared() < 0.0001:
		look = Vector3.FORWARD
	return look.normalized()


func _flank_sign() -> float:
	return -1.0 if (hash(mob_id) & 1) == 0 else 1.0


func _view_origin(player: Node) -> Vector3:
	var camera := _player_camera(player)
	if camera != null:
		return camera.global_position
	return _combat_position_of(player)


func _player_view(player: Node) -> Vector3:
	if player != null and player.has_method(&"look_direction"):
		var look: Variant = player.call(&"look_direction")
		if look is Vector3 and (look as Vector3).is_finite() \
				and (look as Vector3).length_squared() > 0.0001:
			return (look as Vector3).normalized()
	var lift := _view_up(player)
	var motion := _player_velocity(player)
	motion -= lift * motion.dot(lift)
	if motion.length_squared() > 0.36:
		return motion.normalized()
	if player is Node3D:
		var facing := -(player as Node3D).global_transform.basis.z
		if facing.length_squared() > 0.0001:
			return facing.normalized()
	return Vector3.FORWARD


func _view_up(player: Node) -> Vector3:
	var camera := _player_camera(player)
	if camera != null:
		var lift := camera.global_basis.y
		if lift.length_squared() > 0.0001:
			return lift.normalized()
	if player is Node3D:
		var lift := (player as Node3D).global_transform.basis.y
		if lift.length_squared() > 0.0001:
			return lift.normalized()
	return _up()


func _player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	var held: Variant = player.get(&"camera")
	return held as Camera3D if held is Camera3D else null


func _charge_wait() -> float:
	return CrawlerMobs.number(
		wild_kind(), threat_level, "aim_seconds", CrawlerRules.WEAVER_CHARGE)


func charge_share() -> float:
	var wait := _charge_wait()
	if wait <= 0.001 or not charging():
		return 0.0
	return 1.0 - clampf(_aim_left / wait, 0.0, 1.0)


func _try_beam(player: Node) -> void:
	if charging() or firing():
		return
	var aim := _charge_wait()
	if not _begin_attack(aim + BEAM_SECONDS + 0.2):
		return
	_act = CLIP_TURRET
	_faces_motion = false
	_hop_left = 0.0
	_aim_left = maxf(aim, 0.05)
	_beam_left = 0.0
	_beam_since = 0.0
	_beam_prey = player
	velocity = Vector3.ZERO
	set_physics_process(true)
	_hold_beam(0.0)
	_draw_charge(0.0)


func _hold_beam(delta: float) -> void:
	_faces_motion = false
	if delta > 0.0:
		_match_speed(0.0, delta, 4.0, 40.0)
		velocity = velocity.move_toward(Vector3.ZERO, 28.0 * delta)
	var player := _beam_prey if is_instance_valid(_beam_prey) else _nearest_player()
	if player == null:
		return
	var look := _flat_toward(_combat_position_of(player))
	if look.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(look.normalized(), _up())


func _draw_charge(share: float) -> void:
	if _beams == null:
		return
	var player := _beam_prey if is_instance_valid(_beam_prey) else _nearest_player()
	if player == null:
		return
	var thick := lerpf(0.22, 0.88, clampf(share, 0.0, 1.0))
	if share > 0.88:
		thick = 1.05
	var eyes := _eye_points()
	_beams.aim(
		eyes[0], eyes[1], _beam_aim_at(player),
		LaserBeams.COLOR, thick, 0.0, LaserBeams.FOLLOW_EYES)


func _start_fire() -> void:
	_aim_left = 0.0
	_beam_left = BEAM_SECONDS
	_beam_since = BEAM_STEP


func _service_beam(delta: float) -> void:
	if _movement_locked():
		_stop_beam()
		return
	var player := _beam_prey if is_instance_valid(_beam_prey) else _nearest_player()
	if player == null:
		_stop_beam()
		return
	_hold_beam(delta)
	if charging():
		_aim_left = maxf(_aim_left - delta, 0.0)
		_draw_charge(charge_share())
		if _aim_left > 0.0:
			return
		_start_fire()
	_beam_left = maxf(_beam_left - delta, 0.0)
	if _beam_left <= 0.0:
		_stop_beam()
		return
	var at := _beam_aim_at(player)
	var eyes := _eye_points()
	if _beams != null:
		_beams.aim(
			eyes[0], eyes[1], at, LaserBeams.COLOR, 1.0, 0.0,
			LaserBeams.FOLLOW_EYES)
	_beam_since += delta
	if _beam_since < BEAM_STEP:
		return
	_beam_since -= BEAM_STEP
	_cut_beam(eyes, at, player)


func _beam_aim_at(player: Node) -> Vector3:
	return _combat_position_of(player)


func _cut_beam(eyes: Array[Vector3], at: Vector3, player: Node) -> void:
	var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var hit := DamageHit.beam(from, at, BEAM_RADIUS, damage() * BEAM_DPS * BEAM_STEP)
	hit.faction = outgoing_faction()
	hit.ability_id = "laser_eyes"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		if hit.reaches(
				_combat_position_of(player),
				float(player.call(&"combat_radius")) if player.has_method(
					&"combat_radius") else 0.4):
			player.call(&"apply_damage", hit.resolved_for(player))


func _stop_beam() -> void:
	_aim_left = 0.0
	_beam_left = 0.0
	_beam_since = 0.0
	_beam_prey = null
	_act = ""
	_faces_motion = true
	_fire_left = maxf(_fire_left, fire_scale())
	if _beams != null:
		_beams.stop()
	set_physics_process(_director_lod == CrawlerRules.MOB_LOD_HOT)


func _eye_points() -> Array[Vector3]:
	var origin := combat_position() + _up() * 0.22
	if _head is Node3D:
		origin = _head.global_position
	var right := global_transform.basis.x
	var ahead := -global_transform.basis.z
	right -= _up() * right.dot(_up())
	ahead -= _up() * ahead.dot(_up())
	if right.length_squared() < 0.0001:
		right = _up().cross(ahead)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	if ahead.length_squared() < 0.0001:
		ahead = -_up().cross(right)
	right = right.normalized() * 0.14
	ahead = ahead.normalized() * 0.10
	return [origin - right + ahead, origin + right + ahead]


func _try_pincer(player: Node, reach: float) -> void:
	if not _begin_attack(1.2):
		return
	_act = CLIP_PINCER
	_hop_left = 0.0
	_melee(player, reach + 0.35, "crawler_weaver_pincer")
