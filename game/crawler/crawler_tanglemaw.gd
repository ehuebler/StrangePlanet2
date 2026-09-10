class_name CrawlerTanglemaw
extends CrawlerAlien

## Mass ground biter. Chases from any side, including behind, and cannot
## keep up with a runner. Bites apply stacking Slow.

const HEIGHT := 1.68
const WIDTH := 0.92
const ROAM_RETARGET := 0.55


var _bite_left := 0.0


func _ready() -> void:
	_base_health = 4.0
	_base_damage = 3.0
	_base_speed = 5.8
	super._ready()


func wild_kind() -> String:
	return "tanglemaw"


func muzzle_bone() -> String:
	return "socket_mouth"


func body_height() -> float:
	return HEIGHT * BODY_SCALE


func body_width() -> float:
	return WIDTH * 1.15


func flies() -> bool:
	return _hunt_airborne


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _movement_locked():
		return
	if chase:
		_face_prey()
	elif _faces_motion:
		_face_motion(delta)


func director_cold_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	if player != null and chase:
		steer = true
		step = maxf(step, delta)
	super.director_cold_tick(delta, step, steer, player, in_city)


func director_warm_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	if player != null and chase:
		steer = true
		step = maxf(step, delta)
	super.director_warm_tick(delta, step, steer, player, in_city)


func _tick_idle(delta: float) -> void:
	_roam(delta)


func _tick_ai(delta: float) -> void:
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_chase(player, delta, true)


func _tick_far(delta: float) -> void:
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_chase(player, delta, false)
		return
	_tick_idle(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	_bite_left = maxf(_bite_left - step, 0.0)
	if player != null and tick_agro(player, step):
		_chase(player, step, false)
	else:
		_tick_idle(step)


func _roam(delta: float) -> void:
	_faces_motion = true
	if _director_lod == CrawlerRules.MOB_LOD_HOT:
		snap_to_ground()
	_match_speed(move_speed(), delta, 0.35, 28.0)
	_patrol_left -= delta
	var along := _flat_toward(_patrol_goal)
	if _patrol_left <= 0.0 or along.length() < 2.4:
		_retarget_roam()
		along = _flat_toward(_patrol_goal)
	if along.length_squared() < 0.12:
		_retarget_roam()
		along = _flat_toward(_patrol_goal)
	if along.length_squared() < 0.12:
		return
	_steer_toward(along.normalized() * _cruise, delta, 16.0)


func _retarget_roam() -> void:
	_patrol_serial += 1
	_patrol_left = ROAM_RETARGET + float(_patrol_serial % 5) * 0.11
	_patrol_goal = _flock_wander()


func _face_prey() -> void:
	var player := _nearest_player()
	if player == null:
		return
	var look := _flat_toward(_combat_position_of(player))
	if look.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(look.normalized(), _up())


func _chase(player: Node, delta: float, think: bool) -> void:
	_tick_hunt_motion(player, delta)
	if hunt_stance == CrawlerHunt.Stance.PURSUE:
		return
	if think and not flies():
		snap_to_ground()
	var at := _combat_position_of(player)
	var gap := global_position.distance_to(at)
	var reach := CrawlerRules.TANGLEMAW_BITE_REACH + _reach_of(player)
	if gap <= reach and _bite_left <= 0.0:
		_bite(player, reach)


func _bite(player: Node, reach: float) -> void:
	if not _begin_attack(0.42):
		return
	_act = CLIP_BITE
	_bite_left = CrawlerMobs.number(
		wild_kind(), threat_level, "fire", CrawlerRules.TANGLEMAW_BITE)
	var hit := DamageHit.impact(combat_position(), reach + 0.35, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_tanglemaw_bite"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
	hit.with_status(CombatStatuses.SLOW, CrawlerRules.TANGLEMAW_SLOW)
	hit.status_stack = true
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		player.call(&"apply_damage", hit)


func _flock_wander() -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(mob_id) * 29 + _patrol_serial * 67) & 0x7fffffff)
	var yaw := rng.randf() * TAU
	var reach := rng.randf_range(12.0, 28.0)
	var at := hang_origin + (east * cos(yaw) + north * sin(yaw)) * reach
	var surface := ground_surface(at)
	if surface.is_finite():
		if _planet != null:
			up = _planet.up_at(surface)
		at = surface + up * ground_clearance()
	return at
