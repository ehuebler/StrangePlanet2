class_name CrawlerTanglemaw
extends CrawlerAlien

## Mass ground biter. Chases from any side, including behind, and cannot
## keep up with a runner. Bites apply stacking Slow.

const HEIGHT := 1.68
const WIDTH := 0.92


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
	return false


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
	if player != null and _apply_agro(player, step, in_city):
		_chase(player, step, false)
	else:
		_tick_idle(step)


func _roam(delta: float) -> void:
	snap_to_ground()
	_match_speed(move_speed() * 0.42, delta, 1.1, 6.0)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or global_position.distance_to(_patrol_goal) < 2.4:
		_patrol_left = PATROL_RETARGET + float(hash(mob_id) % 9) * 0.12
		_patrol_goal = _flock_wander()
	var along := _flat_toward(_patrol_goal)
	if along.length_squared() < 0.12:
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 9.0)


func _chase(player: Node, delta: float, think: bool) -> void:
	if think:
		snap_to_ground()
	var at := _combat_position_of(player)
	var along := _flat_toward(at)
	var gap := global_position.distance_to(at)
	_match_speed(move_speed(), delta, 0.55, 8.0)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 11.0)
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
	var reach := rng.randf_range(5.0, 16.0)
	var at := hang_origin + (east * cos(yaw) + north * sin(yaw)) * reach
	var surface := ground_surface(at)
	if surface.is_finite():
		if _planet != null:
			up = _planet.up_at(surface)
		at = surface + up * ground_clearance()
	return at
