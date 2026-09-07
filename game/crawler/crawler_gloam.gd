class_name CrawlerGloam
extends CrawlerMob

## Small two-winged demon. Roams on the ground in flocks. Bites up close,
## then takes off if the player pulls away and lands on a flank to bite again.

const BODY := preload("res://game/crawler/crawler_demon_body.gd")
const PAINT_PATH := "res://assets/runtime/biomes/paint/gloam_paint.png"
const HEIGHT := 2.2
const WIDTH := 0.85
const INK := Color(0.22, 0.07, 0.08)


var _airborne := false
var _bite_left := 0.0
var _flank := 1.0


func _ready() -> void:
	_base_health = 36.0
	_base_damage = 8.0
	_base_speed = 9.0
	_faces_motion = true
	super._ready()
	_flank = -1.0 if (hash(mob_id) & 1) == 0 else 1.0


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, WIDTH * 0.78)
	shape.shape = box
	add_child(shape)
	BODY.build(self, 2, HEIGHT, INK, BODY.load_paint(PAINT_PATH))


func wild_kind() -> String:
	return "gloam"


func combat_display_name() -> String:
	return "Gloam"


func combat_position() -> Vector3:
	return global_position + _up() * (HEIGHT * 0.28)


func combat_radius() -> float:
	return WIDTH * 0.55


func is_airborne() -> bool:
	return _airborne


func flies() -> bool:
	return _airborne


func flyer_floor() -> float:
	return HEIGHT * 0.7 + 1.4


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _airborne:
		return BODY.CLIP_FLY
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	return super._desired_clip()


func _tick_ai(delta: float) -> void:
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_roam(delta)
		return
	if _airborne:
		_chase_air(player, delta)
	else:
		_chase_ground(player, delta)


func _roam(delta: float) -> void:
	if _airborne:
		_land()
	_stick_to_surface()
	_match_speed(move_speed() * 0.42, delta, 1.1, 6.0)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or global_position.distance_to(_patrol_goal) < 2.4:
		_patrol_left = PATROL_RETARGET + float(hash(mob_id) % 9) * 0.12
		_patrol_goal = _flock_wander()
	var along := _tangent_toward(_patrol_goal)
	if along.length_squared() < 0.12:
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 9.0)


func _chase_ground(player: Node, delta: float) -> void:
	_stick_to_surface()
	var at := _combat_position_of(player)
	var gap := global_position.distance_to(at)
	var player_speed := _player_speed(player)
	if gap > CrawlerRules.GLOAM_FLEE_GAP or player_speed > move_speed() * 1.35:
		_takeoff()
		_chase_air(player, delta)
		return
	var wanted := minf(move_speed(), player_speed * 0.62 + 2.4)
	_match_speed(wanted, delta, 0.32, 4.0)
	var along := _tangent_toward(at)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 10.0)
	var reach := CrawlerRules.GLOAM_BITE_REACH
	if player.has_method(&"combat_radius"):
		reach += float(player.call(&"combat_radius"))
	if gap <= reach and _bite_left <= 0.0:
		_bite(player)


func _chase_air(player: Node, delta: float) -> void:
	var perch := _land_perch(player)
	var player_speed := _player_speed(player)
	var wanted := maxf(player_speed * CrawlerRules.GLOAM_AIR_MATCH, move_speed() * 1.8)
	_match_speed(wanted, delta, 2.4, 36.0)
	var along := perch - global_position
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 14.0)
	if global_position.distance_to(perch) <= 2.2:
		_land()


func _land_perch(player: Node) -> Vector3:
	var at := _combat_position_of(player)
	var up := _up()
	var look := _player_ahead(player)
	var right := look.cross(up)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var perch := at + look * CrawlerRules.GLOAM_LAND_GAP \
		+ right * _flank * (CrawlerRules.GLOAM_LAND_GAP * 0.55)
	if _planet != null:
		var local := _planet.to_local(perch)
		if local.length_squared() > 0.0001:
			var surface := _planet.surface_position(local)
			perch = surface + _planet.up_at(surface) * flyer_floor()
	return perch


func _player_ahead(player: Node) -> Vector3:
	var lift := _up()
	var motion := _player_velocity(player)
	motion -= lift * motion.dot(lift)
	if motion.length_squared() > 0.36:
		return motion.normalized()
	if player != null and player.has_method(&"look_direction"):
		var look: Variant = player.call(&"look_direction")
		if look is Vector3 and (look as Vector3).length_squared() > 0.0001:
			var flat := (look as Vector3) - lift * (look as Vector3).dot(lift)
			if flat.length_squared() > 0.0001:
				return flat.normalized()
	return _tangent_toward(_combat_position_of(player)).normalized()


func _takeoff() -> void:
	_airborne = true
	if _planet != null:
		global_position += _up() * 1.2


func _land() -> void:
	_airborne = false
	_stick_to_surface()
	velocity -= _up() * velocity.dot(_up())


func _bite(player: Node) -> void:
	if not _begin_attack(0.36):
		return
	_bite_left = CrawlerMobs.number(
		wild_kind(), threat_level, "fire", CrawlerRules.GLOAM_BITE_SECONDS)
	var reach := CrawlerRules.GLOAM_BITE_REACH + 0.6
	var hit := DamageHit.impact(combat_position(), reach, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_gloam_bite"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
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
	if _planet != null:
		var local := _planet.to_local(at)
		if local.length_squared() > 0.0001:
			var surface := _planet.surface_position(local)
			at = surface + _planet.up_at(surface) * (HEIGHT * 0.5)
	return at


func _tangent_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _stick_to_surface() -> void:
	if _airborne or _planet == null:
		return
	var local := _planet.to_local(global_position)
	if local.length_squared() < 0.0001:
		local = Vector3.UP
	var surface := _planet.surface_position(local)
	var up := _planet.up_at(surface)
	global_position = surface + up * (HEIGHT * 0.5)
	velocity -= up * velocity.dot(up)
