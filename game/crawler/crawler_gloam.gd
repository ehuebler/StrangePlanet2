class_name CrawlerGloam
extends CrawlerMob

## Small two-winged demon. Swarms on foot at a jog and bites over and over.
## When the player runs, the flock flies ahead, lands in the way, and bites.

const BODY := preload("res://game/crawler/crawler_demon_body.gd")
const PAINT_PATH := "res://assets/runtime/biomes/paint/gloam_paint.png"
const HEIGHT := 2.2
const WIDTH := 0.85
const INK := Color(0.22, 0.07, 0.08)


var _airborne := false
var _bite_left := 0.0
var _flank := 1.0


func _ready() -> void:
	_base_health = 4.0
	_base_damage = 3.0
	_base_speed = 9.0
	_faces_motion = true
	_uses_model_front = true
	super._ready()
	_flank = -1.0 if (hash(mob_id) & 1) == 0 else 1.0


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, WIDTH * 0.78)
	shape.shape = box
	add_child(shape)
	var packed := CrawlerDemonModels.scene(wild_kind())
	if packed != null:
		_attach_skinned(packed, HEIGHT)
	else:
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


func ground_clearance() -> float:
	return HEIGHT * 0.5


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_ATTACK:
		return PackedStringArray(["Bite", "Strike", CLIP_ATTACK])
	return super._clip_aliases(clip)


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


func _tick_idle(delta: float) -> void:
	_roam(delta)


func _tick_ai(delta: float) -> void:
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_pursue(player, delta, true)


func _tick_far(delta: float) -> void:
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_pursue(player, delta, false)
		return
	_tick_idle(delta)


func director_cold_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	if player != null and (chase or hunting()):
		steer = true
		step = maxf(step, delta)
	super.director_cold_tick(delta, step, steer, player, in_city)


func director_warm_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	if player != null and (chase or hunting()):
		steer = true
		step = maxf(step, delta)
	super.director_warm_tick(delta, step, steer, player, in_city)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	_bite_left = maxf(_bite_left - step, 0.0)
	if player != null and _apply_agro(player, step, in_city):
		_pursue(player, step, false)
	else:
		_tick_idle(step)
	if flies():
		_director_climb()


func _pursue(player: Node, delta: float, _think: bool) -> void:
	var at := _combat_position_of(player)
	var rise := (at - global_position).dot(_up())
	var cut := hunt_stance == CrawlerHunt.Stance.PURSUE \
		or rise > 2.8 \
		or _player_fleeing(player)
	if cut:
		_hunt_set_air(true)
		_chase_air(player, delta)
		return
	_hunt_set_air(false)
	_chase_ground(player, delta)


func _hunt_set_air(on: bool) -> void:
	if _hunt_airborne == on and _airborne == on:
		return
	_hunt_airborne = on
	if on:
		_takeoff()
	else:
		_land()


func _roam(delta: float) -> void:
	if _airborne:
		_land()
	if _director_lod == CrawlerRules.MOB_LOD_HOT:
		snap_to_ground()
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
	var at := _combat_position_of(player)
	var gap := global_position.distance_to(at)
	_match_speed(move_speed(), delta, 0.45, 18.0)
	var along := _tangent_toward(at)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 14.0)
	var reach := CrawlerRules.GLOAM_BITE_REACH
	if player != null and player.has_method(&"combat_radius"):
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
	var up := _loft_axis()
	var look := _player_ahead(player)
	var right := look.cross(up)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var ahead := CrawlerRules.GLOAM_LAND_GAP
	var motion := _player_velocity(player)
	motion -= up * motion.dot(up)
	if motion.length() > CrawlerRules.GLOAM_RUN_SPEED:
		ahead += clampf(motion.length() * 0.22, 0.0, 6.0)
	var perch := at + look * ahead + right * _flank * CrawlerRules.GLOAM_CUT_SIDE
	if _planet == null:
		return perch
	var surface := ground_surface(perch)
	if surface.is_finite() and surface.distance_to(perch) < 12.0:
		up = _planet.up_at(surface)
		perch = surface + up * flyer_floor()
	return perch


func _player_ahead(player: Node) -> Vector3:
	var lift := _loft_axis()
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
	snap_to_ground()
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
	var surface := mesh_surface(at)
	if not surface.is_finite():
		surface = ground_surface(at)
	if surface.is_finite():
		if _planet != null:
			up = _planet.up_at(surface)
		at = surface + up * ground_clearance()
	return at


func _tangent_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _stick_to_surface() -> void:
	if _airborne:
		return
	snap_to_ground()
