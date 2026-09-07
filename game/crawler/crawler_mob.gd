class_name CrawlerMob
extends CharacterBody3D

## Shared combatant for crawler siege enemies. Host owns health and motion;
## other peers interpolate the compact state the horde publishes.
##
## Unique hunt and fire live in `_tick_ai`. The director only runs that on
## nearby bodies that still have think budget. New kinds should not override
## `_physics_process` or query the height field every tick. Start a windup
## with `_begin_attack` so the swarm shares an attack token.

signal died

const GROUP := &"crawler_mobs"
const ENEMY_SHADER: Shader = preload("res://shaders/crawler/crawler_enemy.gdshader")
const MobSense := preload("res://game/crawler/crawler_mob_sense.gd")
const STATE_SYNC_INTERVAL := 0.1
const CLIENT_FOLLOW_SPEED := 18.0
const DAMAGE_FLASH_SECONDS := 0.32
const PATROL_RETARGET := 4.8
const RIM := Color("ef151f")
const CLIP_IDLE := "Idle"
const CLIP_WALK := "Walk"
const CLIP_RUN := "Run"
const CLIP_ATTACK := "Attack"
const CLIP_HIT := "HitReact"
const CLIP_BLEND := 0.12
const WALK_CLIP_SPEED := 8.0
const RUN_CLIP_SPEED := 22.0

var mob_id := ""
var city_id := -1
var garrison_slot := -1
var persistent := false
var threat_level := 0
var chase := false
var ever_chased := false
var idle_seconds := 0.0
var hang_origin := Vector3.ZERO
var dismissed := false
var last_source_peer := 0
var statuses := CombatStatuses.new()
var _poison_float := 0.0
var _frost_float := 0.0

var _alive := true
var _base_health := 48.0
var _health := 48.0
var _maximum_health := 48.0
var _patch_health_scale := 1.0
var _base_damage := 12.0
var _base_speed := 22.0
var _cruise := 0.0
var _flash_left := 0.0
var _sync_left := 0.0
var _patrol_left := 0.0
var _patrol_serial := 0
var _patrol_goal := Vector3.ZERO
var _planet: Planet
var _horde: Node
var _visual: MeshInstance3D
var _material: ShaderMaterial
var _materials: Array[ShaderMaterial] = []
var _animator: AnimationPlayer
var _current_clip := ""
var _network_clip := ""
var _faces_motion := false
var _attack_left := 0.0
var _spotted_left := 0.0
var _network_transform := Transform3D.IDENTITY
var _network_velocity := Vector3.ZERO
var _has_network_transform := false
var _orbit_dir := Vector3.ZERO
var _sensed_player: Node3D
var _sensed_frame := -1
var _cached_up := Vector3.ZERO
var _cached_up_at := Vector3.INF
var _cached_alt := 0.0
var _cached_alt_at := Vector3.INF
var _clip_names: Dictionary = {}


func configure(id: String, at: Transform3D, level: int, should_chase: bool,
		owner: Node = null, owned_city := -1, slot := -1,
		patch_health_scale := 1.0) -> void:
	mob_id = id
	threat_level = maxi(level, 0)
	chase = should_chase
	ever_chased = should_chase
	idle_seconds = 0.0
	_horde = owner
	city_id = owned_city
	garrison_slot = slot
	_patch_health_scale = maxf(patch_health_scale, 0.01)
	_initial_place(at)


func _initial_place(at: Transform3D) -> void:
	if at.origin.is_finite():
		transform = at
	hang_origin = at.origin if at.origin.is_finite() else Vector3.ZERO


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 0
	floor_snap_length = 0.0
	_planet = _find_planet()
	_apply_threat_stats(false)
	_build_body()
	add_to_group(DamageHit.COMBATANT_GROUP)
	add_to_group(GROUP)
	MobSense.note_spawned(self)
	_network_transform = global_transform
	if hang_origin == Vector3.ZERO:
		hang_origin = global_position
	_patrol_goal = hang_origin


func spot(seconds: float) -> void:
	_spotted_left = maxf(_spotted_left, seconds)


func is_spotted() -> bool:
	return _spotted_left > 0.0


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	_spotted_left = maxf(_spotted_left - delta, 0.0)
	_update_flash()
	_update_clips()


func _physics_process(delta: float) -> void:
	if not _is_host():
		_follow_network(delta)
		return
	if not _alive:
		return
	var clock := Time.get_ticks_usec()
	MobSense.begin_frame(get_tree())
	var lod := MobSense.lod_of(self)
	if lod == CrawlerRules.MOB_LOD_COLD:
		_tick_cold(delta)
		MobSense.note_tick(self, Time.get_ticks_usec() - clock)
		return
	_attack_left = maxf(_attack_left - delta, 0.0)
	_tick_statuses(delta)
	if not _alive:
		MobSense.note_tick(self, Time.get_ticks_usec() - clock)
		return
	var hot := lod == CrawlerRules.MOB_LOD_HOT
	if is_frozen():
		velocity = Vector3.ZERO
	elif hot and MobSense.take_think(self, chase or is_charmed()):
		_tick_ai(delta)
		var field_slow := MobSense.field_slow(self, global_position)
		if field_slow < 0.999:
			velocity *= field_slow
	else:
		_tick_far(delta)
	if hot:
		_respect_flyer_ceiling(delta)
		_keep_clear_of_terrain(false)
		if _faces_motion and not is_frozen():
			_face_motion(delta)
		_keep_out_of_safe_zones()
	# Mask is 0, so move_and_slide would not collide. Integrate the same way
	# far and near so a crowd does not pay a physics-server slide each tick.
	if velocity.length_squared() > 0.0001:
		global_position += velocity * delta
	if hot:
		_keep_clear_of_terrain(true)
	_publish_state(delta)
	MobSense.note_tick(self, Time.get_ticks_usec() - clock)


func _tick_ai(_delta: float) -> void:
	pass


func _tick_far(delta: float) -> void:
	var player := _nearest_player()
	if player == null or not tick_agro(player, delta):
		velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
		return
	var along := _combat_position_of(player) - global_position
	if along.length_squared() < 0.04:
		return
	_match_speed(move_speed(), delta, 1.2, 16.0)
	_steer_toward(along.normalized() * _cruise, delta, 10.0)


func _tick_cold(delta: float) -> void:
	var stride := maxi(CrawlerRules.MOB_COLD_STRIDE, 1)
	if (Engine.get_physics_frames() + get_instance_id()) % stride != 0:
		velocity = Vector3.ZERO
		return
	var step := delta * float(stride)
	_attack_left = maxf(_attack_left - step, 0.0)
	_tick_statuses(step)
	var player := _nearest_player()
	tick_agro(player, step)
	velocity = Vector3.ZERO
	_publish_state(step)


func _build_body() -> void:
	pass


func patch_health_scale() -> float:
	return _patch_health_scale


func set_threat_level(level: int) -> void:
	if level == threat_level:
		return
	threat_level = maxi(level, 0)
	_apply_threat_stats(true)


func _apply_threat_stats(rescale_current: bool) -> void:
	var row := CrawlerMobs.stats(wild_kind(), threat_level)
	var catalog_health := float(row.get("health", _base_health))
	if not is_finite(catalog_health) or catalog_health <= 0.0:
		catalog_health = _base_health
	var health_scale := _patch_health_scale
	if row.is_empty():
		health_scale *= CrawlerRules.threat_health(threat_level)
	var next_max := maxf(catalog_health * health_scale, 1.0)
	if rescale_current and _maximum_health > 0.0:
		var share := _health / _maximum_health
		_maximum_health = next_max
		_health = clampf(share * next_max, 0.0, next_max)
	else:
		_maximum_health = next_max
		_health = next_max


func damage() -> float:
	var row := CrawlerMobs.stats(wild_kind(), threat_level)
	if not row.is_empty() and row.has("damage"):
		return maxf(float(row.get("damage", _base_damage)), 0.0)
	return _base_damage * CrawlerRules.threat_damage(threat_level)


func move_speed() -> float:
	var row := CrawlerMobs.stats(wild_kind(), threat_level)
	if not row.is_empty() and row.has("speed"):
		return maxf(float(row.get("speed", _base_speed)), 0.0)
	return _base_speed * CrawlerRules.threat_speed(threat_level)


func fire_scale() -> float:
	var interval := CrawlerMobs.number(wild_kind(), threat_level, "fire", 0.0)
	if interval > 0.0:
		return interval
	return CrawlerRules.threat_fire(threat_level)


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _alive or not _is_host() or not _accepts_hit(hit):
		return 0.0
	var status_applied := CrawlerElements.apply_to_combatant(self, hit)
	var actual := minf(maxf(hit.amount, 0.0) if is_finite(hit.amount) else 0.0, _health)
	if actual <= 0.0 and not status_applied:
		return 0.0
	if actual > 0.0:
		_health -= actual
		_flash_left = DAMAGE_FLASH_SECONDS
	if hit.source_peer > 0:
		last_source_peer = hit.source_peer
	chase = true
	ever_chased = true
	idle_seconds = 0.0
	if is_charmed():
		MobSense.note_charmed(self, true)
	if hit.world_impulse.is_finite():
		velocity += hit.world_impulse
	if _health <= 0.0:
		_die()
	_force_publish()
	return actual


func _accepts_hit(hit: DamageHit) -> bool:
	if hit.faction == DamageHit.Faction.PLAYER:
		return true
	return hit.faction == DamageHit.Faction.ENEMY and is_charmed()


func is_charmed() -> bool:
	return statuses.has(CombatStatuses.CHARM)


func is_frozen() -> bool:
	return statuses.movement_locked()


func outgoing_faction() -> int:
	return DamageHit.Faction.PLAYER if is_charmed() \
		else DamageHit.Faction.ENEMY


func _tick_statuses(delta: float) -> void:
	if statuses.has(CombatStatuses.POISON):
		var dps := statuses.strength(CombatStatuses.POISON)
		if dps > 0.0 and _alive:
			var dealt := minf(dps * delta, _health)
			_health = maxf(_health - dealt, 0.0)
			if dealt > 0.0:
				_poison_float += dealt
				if _poison_float >= 1.0:
					_emit_status_float(DamageNumberEvent.Kind.POISON, _poison_float)
					_poison_float = 0.0
			if _flash_left <= 0.0:
				_flash_left = DAMAGE_FLASH_SECONDS * 0.45
			if _health <= 0.0:
				_die()
				return
	if statuses.has(CombatStatuses.FREEZE):
		var frost := statuses.strength(CombatStatuses.FREEZE)
		if frost > 0.0 and _alive:
			var chilled := minf(frost * delta, _health)
			_health = maxf(_health - chilled, 0.0)
			if chilled > 0.0:
				_frost_float += chilled
				if _frost_float >= 1.0:
					_emit_status_float(DamageNumberEvent.Kind.FREEZE, _frost_float)
					_frost_float = 0.0
			if _flash_left <= 0.0:
				_flash_left = DAMAGE_FLASH_SECONDS * 0.45
			if _health <= 0.0:
				_die()
				return
	var had_charm := is_charmed()
	var had_poison := statuses.has(CombatStatuses.POISON)
	var had_freeze := statuses.has(CombatStatuses.FREEZE)
	statuses.tick(delta)
	if statuses.consume_pulse(CombatStatuses.CHARM, CombatStatuses.CHARM_PULSE):
		_emit_status_float(DamageNumberEvent.Kind.CHARM, 1.0)
	if statuses.consume_shock_pulse():
		_emit_status_float(DamageNumberEvent.Kind.SHOCK, 1.0)
	if had_poison and not statuses.has(CombatStatuses.POISON) and _poison_float > 0.0:
		_emit_status_float(DamageNumberEvent.Kind.POISON, _poison_float)
		_poison_float = 0.0
	if had_freeze and not statuses.has(CombatStatuses.FREEZE) and _frost_float > 0.0:
		_emit_status_float(DamageNumberEvent.Kind.FREEZE, _frost_float)
		_frost_float = 0.0
	if had_charm and not is_charmed():
		MobSense.note_charmed(self, false)
		chase = true
		ever_chased = true
		idle_seconds = 0.0


func _exit_tree() -> void:
	MobSense.note_gone(self)


func dismiss() -> void:
	if dismissed:
		return
	dismissed = true
	_alive = false
	velocity = Vector3.ZERO
	MobSense.note_gone(self)
	queue_free()


func _die() -> void:
	if not _alive or dismissed:
		return
	_alive = false
	velocity = Vector3.ZERO
	MobSense.note_gone(self)
	_play_death_burst()
	died.emit()
	_force_publish()
	queue_free()


func _play_death_burst() -> void:
	CrawlerBurst.death(
		_effect_world(), combat_position(), _up(),
		maxf(combat_radius() * 2.6, 2.4), wild_kind())


func _effect_world() -> Node:
	if _planet != null:
		return _planet
	var world := DamageHit.game_world_of(self)
	if world != null:
		return world
	return get_parent()


func combat_faction() -> int:
	return DamageHit.Faction.ENEMY


func combat_peer_id() -> int:
	return 0


func wild_kind() -> String:
	return "ranger"


func is_persistent() -> bool:
	return persistent


func flies() -> bool:
	return CrawlerRules.flies(wild_kind())


func flyer_ceiling() -> float:
	return CrawlerMobs.number(
		wild_kind(), threat_level, "flyer_ceiling",
		CrawlerRules.flyer_ceiling(maxi(threat_level, 1)))


func flyer_floor() -> float:
	return combat_radius() + 1.6


func surface_altitude(at := Vector3.INF) -> float:
	var point := at if at.is_finite() else global_position
	if _planet == null:
		return 0.0
	if not at.is_finite() and point.distance_squared_to(_cached_alt_at) < 0.04:
		return _cached_alt
	var local := _planet.to_local(point)
	if local.length_squared() < 0.0001:
		local = _up()
	var surface := _planet.surface_position(local)
	var altitude := (point - surface).dot(_planet.up_at(surface))
	if not at.is_finite():
		_cached_alt = altitude
		_cached_alt_at = point
	return altitude


func _clamp_below_ceiling(at: Vector3) -> Vector3:
	return _clamp_flyer_band(at)


func _clamp_flyer_band(at: Vector3) -> Vector3:
	if not flies() or not at.is_finite() or _planet == null:
		return at
	var altitude := surface_altitude(at)
	var loft := clampf(altitude, flyer_floor(), maxf(flyer_ceiling(), flyer_floor()))
	if is_equal_approx(altitude, loft):
		return at
	return at + _up() * (loft - altitude)


func _respect_flyer_ceiling(_delta: float) -> void:
	if not flies() or _planet == null:
		return
	var floor_h := flyer_floor()
	var ceiling := maxf(flyer_ceiling(), floor_h + 1.5)
	var altitude := surface_altitude()
	if altitude <= ceiling + 0.35:
		return
	var up := _up()
	var rise := velocity.dot(up)
	if rise > 0.0:
		velocity -= up * rise
	var room := maxf(altitude - floor_h, 0.0)
	var sink := clampf((altitude - ceiling) * 3.2, 10.0, 48.0)
	velocity -= up * minf(sink, room * 6.0 + 4.0)


func _keep_clear_of_terrain(snap: bool) -> void:
	if not flies() or _planet == null:
		return
	var up := _up()
	var floor_h := flyer_floor()
	var altitude := surface_altitude()
	if snap and altitude < floor_h:
		global_position += up * (floor_h - altitude)
		altitude = floor_h
	var down := -velocity.dot(up)
	if altitude < floor_h:
		if down > 0.0:
			velocity += up * down
		velocity += up * maxf((floor_h - altitude) * 8.0, 14.0)
		return
	var headroom := altitude - floor_h
	if down > 0.0 and headroom < 3.5:
		velocity += up * down * clampf(1.0 - headroom / 3.5, 0.0, 1.0)
	if headroom < 1.2:
		velocity += up * (12.0 * (1.2 - headroom))


func combat_display_name() -> String:
	return "Crawler"


func combat_position() -> Vector3:
	return global_position + _up() * 0.6


func combat_radius() -> float:
	return 0.7


func warp_to(at: Vector3) -> void:
	if not at.is_finite():
		return
	var dest := at
	if _planet != null:
		var local := _planet.to_local(at)
		if local.length_squared() > 0.0001:
			var surface := _planet.surface_position(local)
			var up := _planet.up_at(surface)
			if flies():
				dest = _clamp_flyer_band(at)
			else:
				dest = surface + up * maxf(combat_radius(), 0.55)
	global_position = dest
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_force_publish()


func combat_aabb() -> AABB:
	var half := combat_radius()
	var at := combat_position()
	return AABB(at - Vector3.ONE * half, Vector3.ONE * (half * 2.0))


func health() -> float:
	return _health


func maximum_health() -> float:
	return _maximum_health


func is_alive() -> bool:
	return _alive


func apply_network_state(at: Transform3D, along: Vector3, hp: float, maximum: float,
		clip := "") -> void:
	_network_transform = at
	_network_velocity = along if along.is_finite() else Vector3.ZERO
	_has_network_transform = true
	if maximum > 0.0:
		_maximum_health = maximum
	if hp < _health - 0.01:
		_flash_left = DAMAGE_FLASH_SECONDS
	_health = clampf(hp, 0.0, _maximum_health)
	_network_clip = clip


func state_wire() -> Dictionary:
	return {
		"id": mob_id,
		"xform": global_transform,
		"vel": velocity,
		"hp": _health,
		"max": _maximum_health,
		"alive": _alive,
		"threat": threat_level,
		"chase": chase,
		"clip": _desired_clip(),
	}


func _follow_network(delta: float) -> void:
	if not _has_network_transform:
		return
	global_transform = global_transform.interpolate_with(
		_network_transform, clampf(CLIENT_FOLLOW_SPEED * delta, 0.0, 1.0))
	velocity = _network_velocity


func _publish_state(delta: float) -> void:
	_sync_left -= delta
	if _sync_left > 0.0:
		return
	_sync_left = STATE_SYNC_INTERVAL
	_force_publish()


func _force_publish() -> void:
	if _horde != null and _horde.has_method(&"publish_mob_state"):
		_horde.call(&"publish_mob_state", self)


func _emit_status_float(kind: int, amount: float) -> void:
	var player := _player_for_peer(last_source_peer)
	if player == null:
		player = _nearest_player()
	if player == null or not player.has_method(&"combat_world_float"):
		return
	var merge := "mob-%d-%d" % [get_instance_id(), kind]
	player.call(&"combat_world_float", kind, amount, combat_position(), merge)


func _player_for_peer(peer: int) -> Node3D:
	if peer <= 0 or not is_inside_tree():
		return null
	MobSense.begin_frame(get_tree())
	for player: Node3D in MobSense.players():
		if is_instance_valid(player) and player.has_method(&"combat_peer_id") \
				and int(player.call(&"combat_peer_id")) == peer:
			return player
	return null


func _nearest_player() -> Node3D:
	var frame := Engine.get_physics_frames()
	if _sensed_frame == frame:
		return _sensed_player if is_instance_valid(_sensed_player) else null
	_sensed_frame = frame
	_sensed_player = MobSense.nearest_player(self)
	return _sensed_player


func _hunt_target(delta: float) -> Node3D:
	if is_charmed():
		chase = true
		ever_chased = true
		idle_seconds = 0.0
		return _nearest_other_mob()
	var bait := _nearest_charmed_mob()
	if bait != null \
			and global_position.distance_to(_combat_position_of(bait)) \
				<= CrawlerRules.PERCEPTION:
		chase = true
		ever_chased = true
		idle_seconds = 0.0
		return bait
	var player := _nearest_player()
	if player == null or not tick_agro(player, delta):
		return null
	return player


func _combat_target() -> Node3D:
	if is_charmed():
		return _nearest_other_mob()
	var bait := _nearest_charmed_mob()
	if bait != null \
			and global_position.distance_to(_combat_position_of(bait)) \
				<= CrawlerRules.PERCEPTION:
		return bait
	return _nearest_player()


func _nearest_other_mob() -> CrawlerMob:
	return _nearest_mob(false)


func _nearest_charmed_mob() -> CrawlerMob:
	return _nearest_mob(true)


func _nearest_mob(charmed_only: bool) -> CrawlerMob:
	var found := MobSense.nearest_charmed(self) if charmed_only \
		else MobSense.nearest_other(self)
	if not is_instance_valid(found):
		return null
	return found as CrawlerMob


func _player_speed(player: Node) -> float:
	if player != null and player.has_method(&"flight_speed"):
		return maxf(float(player.call(&"flight_speed")), 0.0)
	var lead: Variant = player.get(&"velocity") if player != null else null
	return (lead as Vector3).length() if lead is Vector3 else 0.0


func _player_velocity(player: Node) -> Vector3:
	var lead: Variant = player.get(&"velocity") if player != null else null
	return lead as Vector3 if lead is Vector3 and (lead as Vector3).is_finite() \
		else Vector3.ZERO


func _combat_position_of(target: Node) -> Vector3:
	if not is_instance_valid(target):
		return global_position
	if target.has_method(&"combat_position"):
		var at: Variant = target.call(&"combat_position")
		if at is Vector3:
			return at
	var body := target as Node3D
	return body.global_position if body != null else global_position


func sees_player(player: Node3D) -> bool:
	if player == null:
		return false
	return global_position.distance_to(_combat_position_of(player)) \
		<= CrawlerRules.PERCEPTION


func tick_agro(player: Node3D, delta: float) -> bool:
	var gap := INF
	if player != null:
		gap = global_position.distance_to(_combat_position_of(player))
	var was_chasing := chase
	if player == null:
		chase = false
	elif MobSense.player_in_city(player):
		chase = false
	elif chase and gap > CrawlerMobs.number(
			wild_kind(), threat_level, "deagro_range", CrawlerRules.DEAGRO_RANGE):
		chase = false
	elif not chase and CrawlerMobs.agro_mode(wild_kind(), threat_level) != "calm" \
			and gap <= CrawlerMobs.number(
				wild_kind(), threat_level, "agro_range", CrawlerRules.AGRO_RANGE):
		chase = true
	if chase:
		ever_chased = true
		idle_seconds = 0.0
	elif ever_chased:
		idle_seconds += maxf(delta, 0.0)
		if was_chasing and not chase:
			hang_origin = global_position
	return chase


func _match_speed(wanted: float, delta: float, lag := 0.55, floor_rate := 48.0) -> void:
	var rate := maxf(absf(wanted - _cruise) * lag, floor_rate)
	_cruise = move_toward(_cruise, maxf(wanted, 0.0), rate * delta)


func _steer_toward(wanted: Vector3, delta: float, accel := 18.0) -> void:
	if not wanted.is_finite():
		return
	velocity = velocity.move_toward(wanted, accel * maxf(_cruise, 8.0) * delta)


func _keep_out_of_safe_zones() -> void:
	MobSense.keep_clear(self)


func _up() -> Vector3:
	if global_position.distance_squared_to(_cached_up_at) < 1.0 \
			and _cached_up.length_squared() > 0.0001:
		return _cached_up
	var up := Vector3.UP
	if _planet != null:
		var radial := _planet.up_at(global_position)
		if radial.length_squared() > 0.0001:
			up = radial.normalized()
	elif global_position.length_squared() > 0.01:
		up = global_position.normalized()
	_cached_up = up
	_cached_up_at = global_position
	return up


func _find_planet() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		if walk is GameWorld:
			var found := (walk as GameWorld).planet()
			if found != null:
				return found
		walk = walk.get_parent()
	return null


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _patrol(delta: float, pace := 0.38) -> void:
	_match_speed(move_speed() * pace, delta, 1.6)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or global_position.distance_to(_patrol_goal) < 3.2:
		_patrol_serial += 1
		_patrol_left = PATROL_RETARGET + float(_patrol_serial % 7) * 0.35
		_patrol_goal = _wander_point()
	var along := _patrol_goal - global_position
	if along.length_squared() < 0.2:
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 10.0)


func _wander_point() -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(mob_id) * 31 + _patrol_serial * 97) & 0x7fffffff)
	var yaw := rng.randf() * TAU
	var lift := rng.randf_range(-0.18, 0.28)
	var reach := rng.randf_range(CrawlerRules.PATROL_RADIUS * 0.35, CrawlerRules.PATROL_RADIUS)
	var dir := east * cos(yaw) + north * sin(yaw) + up * lift
	if dir.length_squared() < 0.0001:
		dir = east
	return _clamp_flyer_band(hang_origin + dir.normalized() * reach)


func _orbit_bias() -> Vector3:
	if _orbit_dir.length_squared() > 0.0001:
		return _orbit_dir
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(mob_id) & 0x7fffffff) * 17 + 91
	var dir := Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	)
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	_orbit_dir = dir.normalized()
	return _orbit_dir


func _make_mesh(mesh: Mesh, colour: Color, _energy := 1.4) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _enemy_material(colour, null, 0.0)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	if _visual == null:
		_visual = visual
	return visual


func _attach_creature(scene: PackedScene, paint: Texture2D, authored_height: float,
		visual_height: float, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Creature"
	add_child(root)
	var model := scene.instantiate()
	root.add_child(model)
	var scale := visual_height / maxf(authored_height, 0.01)
	root.scale = Vector3.ONE * scale
	root.position.y = -visual_height * 0.5
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node_variant as MeshInstance3D
		if mesh_instance == null:
			continue
		mesh_instance.material_override = _enemy_material(colour, paint, 1.0)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _visual == null:
			_visual = mesh_instance
	_bind_animator(model)
	return root


func _enemy_material(colour: Color, paint: Texture2D, paint_mix: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ENEMY_SHADER
	material.set_shader_parameter(&"albedo", colour)
	material.set_shader_parameter(&"rim_color", RIM)
	material.set_shader_parameter(&"rim_power", 2.15)
	material.set_shader_parameter(&"rim_strength", 1.9)
	material.set_shader_parameter(&"flash", 0.0)
	material.set_shader_parameter(&"paint_mix", paint_mix)
	material.set_shader_parameter(&"vertex_mix", 0.2 if paint != null else 0.0)
	if paint != null:
		material.set_shader_parameter(&"paint", paint)
	_materials.append(material)
	_material = material
	return material


func _bind_animator(model: Node) -> void:
	_animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animator == null:
		return
	_animator.playback_default_blend_time = CLIP_BLEND
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN]:
		var resolved := _resolve_clip(clip)
		if not resolved.is_empty() and _animator.has_animation(resolved):
			_animator.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR


func _resolve_clip(clip: String) -> String:
	if _animator == null or clip.is_empty():
		return ""
	if _clip_names.has(clip):
		return str(_clip_names[clip])
	var resolved := ""
	if _animator.has_animation(clip):
		resolved = clip
	else:
		for listed in _animator.get_animation_list():
			if listed == clip or listed.ends_with("/" + clip):
				resolved = listed
				break
	_clip_names[clip] = resolved
	return resolved


func _begin_attack(seconds: float) -> bool:
	if not MobSense.take_attack(wild_kind()):
		return false
	_attack_left = maxf(seconds, 0.05)
	return true


func _attacking() -> bool:
	return _attack_left > 0.0


func current_clip() -> String:
	return _desired_clip()


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	var speed := velocity.length()
	if speed >= RUN_CLIP_SPEED:
		return CLIP_RUN
	if speed >= WALK_CLIP_SPEED:
		return CLIP_WALK
	return CLIP_IDLE


func _update_clips() -> void:
	if _animator == null:
		return
	var clip := _network_clip if not _is_host() and not _network_clip.is_empty() \
		else _desired_clip()
	var resolved := _resolve_clip(clip)
	if resolved.is_empty():
		return
	var rate := 1.0
	if clip == CLIP_WALK:
		rate = clampf(velocity.length() / WALK_CLIP_SPEED, 0.55, 1.8)
	elif clip == CLIP_RUN:
		rate = clampf(velocity.length() / RUN_CLIP_SPEED, 0.55, 1.8)
	if resolved != _current_clip:
		_current_clip = resolved
		_animator.play(resolved, CLIP_BLEND)
	var scale := maxf(rate, 0.05)
	if not is_equal_approx(_animator.speed_scale, scale):
		_animator.speed_scale = scale


func _face_motion(delta: float) -> void:
	var up := _up()
	var ahead := velocity
	if ahead.length_squared() < 1.0:
		var player := _nearest_player()
		if player != null:
			ahead = _combat_position_of(player) - global_position
		else:
			ahead = _patrol_goal - global_position
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	var desired := Basis.looking_at(ahead.normalized(), up).orthonormalized()
	if desired.determinant() < 0.0:
		desired.x = -desired.x
	if absf(desired.determinant()) < 0.01:
		return
	var current := global_transform.basis.orthonormalized()
	if current.determinant() < 0.0:
		current.x = -current.x
	if absf(current.determinant()) < 0.01:
		global_transform.basis = desired
		return
	global_transform.basis = Basis(
		current.get_rotation_quaternion().slerp(
			desired.get_rotation_quaternion(),
			clampf(delta * 7.0, 0.0, 1.0))).orthonormalized()


func _update_flash() -> void:
	var flash := 0.0
	if _flash_left > 0.0:
		flash = clampf(_flash_left / DAMAGE_FLASH_SECONDS, 0.0, 1.0)
		flash = maxf(flash, 0.72)
	for material in _materials:
		if material != null:
			material.set_shader_parameter(&"flash", flash)
