class_name CrawlerMob
extends CharacterBody3D

## Shared combatant for crawler siege enemies. Host owns health and motion;
## other peers interpolate the compact state the horde publishes.
##
## Unique fire lives in `_tick_ai`. Field packs share agro, pursue, deagro,
## and reagro through [CrawlerHunt]. The director only plans shots on nearby
## bodies that still have think budget. Idle roam lives in `_tick_idle`.
## Start a windup with `_begin_attack` so the swarm shares an attack token.

signal died

const GROUP := &"crawler_mobs"
const ENEMY_SHADER: Shader = preload("res://shaders/crawler/crawler_enemy.gdshader")
const ENEMY_OUTLINE_SHADER: Shader = preload("res://shaders/crawler/crawler_enemy_outline.gdshader")
const MobSense := preload("res://game/crawler/crawler_mob_sense.gd")
const STATE_SYNC_INTERVAL := 0.1
const CLIENT_FOLLOW_SPEED := 18.0
const DAMAGE_FLASH_SECONDS := 0.32
const PATROL_RETARGET := 4.8
const RIM := Color("ef151f")
const CLIP_IDLE := "Idle"
const CLIP_WALK := "Walk"
const CLIP_RUN := "Run"
const CLIP_FLY := "Fly"
const CLIP_CAST := "Cast"
const CLIP_ATTACK := "Attack"
const CLIP_HIT := "HitReact"
const CLIP_BLEND := 0.12
const WALK_CLIP_SPEED := 8.0
const RUN_CLIP_SPEED := 22.0
## Extra metres around the mesh pill so a grazing laser still counts.
const HIT_SKIN := 0.22

var mob_id := ""
var city_id := -1
var garrison_slot := -1
var persistent := false
var training := false
var threat_level := 0
var chase := false
var ever_chased := false
var hunt_stance: CrawlerHunt.Stance = CrawlerHunt.Stance.IDLE
var idle_seconds := 0.0
var hang_origin := Vector3.ZERO
var inbound_heading := Vector3.ZERO
var show_range_tag := false
var dismissed := false
var directed_frame := -1
var director_push := Vector3.ZERO
var director_sep := Vector3.ZERO
var _director_lod := -1
var last_source_peer := 0
var statuses := CombatStatuses.new()
var _poison_float := 0.0
var _frost_float := 0.0

var _alive := true
var _base_health := 6.0
var _health := 6.0
var _maximum_health := 6.0
var _patch_health_scale := 1.0
var _base_damage := 8.0
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
## Authored demon GLBs face +Z (mouth, bite lunge). Godot looking_at uses -Z
## unless this is set.
var _uses_model_front := false
var _attack_left := 0.0
var _spotted_left := 0.0
var _network_transform := Transform3D.IDENTITY
var _network_velocity := Vector3.ZERO
var _has_network_transform := false
var _orbit_dir := Vector3.ZERO
var _sensed_player: Node3D
var _sensed_frame := -1
var _status_frame := -1
var _frozen_now := false
var _charmed_now := false
var _row_level := -999
var _row_speed := -1.0
var _row_agro := 0.0
var _row_deagro := 0.0
var _row_fire := 0.0
var _row_agro_mode := ""
var _cached_up := Vector3.ZERO
var _cached_up_at := Vector3.INF
var _cached_alt := 0.0
var _cached_alt_at := Vector3.INF
var _ground_from := Vector3.INF
var _ground_hit := Vector3.INF
var _snap_frame := -1
var _ground_query: PhysicsRayQueryParameters3D
var _ground_skip: Array[RID] = []
var _kind_is_glorb := false
var _far_view_serial := 0
var _drift_clock := 0.0
var _hold_cached := -1.0
var _hunt_airborne := false
var _hunt_strafe := Vector3.ZERO
var _hunt_strafe_left := 0.0
var _clip_names: Dictionary = {}
var _last_flash := -1.0
var _outline_height := 0.0
## Mesh-local AABB used for the laser/ability pill. Not a physics collider.
var _hit_local := AABB()
var _hit_ready := false
var _stand_height := 0.0
var _skinned_mats: Array[StandardMaterial3D] = []
var _skinned_energy: Array[float] = []
var _skinned_emit: Array[Color] = []


func configure(id: String, at: Transform3D, level: int, should_chase: bool,
		owner: Node = null, owned_city := -1, slot := -1,
		patch_health_scale := 1.0) -> void:
	mob_id = id
	threat_level = maxi(level, 0)
	chase = should_chase
	ever_chased = should_chase
	hunt_stance = CrawlerHunt.Stance.AGRO if should_chase \
		else CrawlerHunt.Stance.IDLE
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
	_refresh_hit_bounds()
	_scale_enemy_outline(_outline_height if _outline_height > 0.01 \
		else maxf(combat_radius() * 2.0, 1.6))
	add_to_group(DamageHit.COMBATANT_GROUP)
	add_to_group(GROUP)
	MobSense.note_spawned(self)
	_network_transform = global_transform
	if hang_origin == Vector3.ZERO:
		hang_origin = global_position
	_patrol_goal = hang_origin
	_kind_is_glorb = CrawlerRules.is_glorb_kind(wild_kind())
	if _kind_is_glorb:
		show_range_tag = true
		_mount_training_range_tag()
		set_process(true)
	_update_clips()


func spot(seconds: float) -> void:
	_spotted_left = maxf(_spotted_left, seconds)


func is_spotted() -> bool:
	return _spotted_left > 0.0


func is_glorb() -> bool:
	return _kind_is_glorb


func _refresh_far_view() -> bool:
	_far_view_serial += 1
	return (_far_view_serial & 7) == 0


func _process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	_spotted_left = maxf(_spotted_left - delta, 0.0)
	_update_flash()
	var cold := _director_lod == CrawlerRules.MOB_LOD_COLD
	if not cold or _refresh_far_view():
		_update_clips()
		if training or show_range_tag:
			_update_training_range_tag()
	if cold and _flash_left <= 0.0 and _spotted_left <= 0.0 \
			and not training and not show_range_tag and _animator == null:
		set_process(false)


func _physics_process(delta: float) -> void:
	if not _is_host():
		_follow_network(delta)
		if training or show_range_tag:
			_update_training_range_tag()
		return
	if training:
		_tick_statuses(delta)
		velocity = Vector3.ZERO
		chase = false
		hunt_stance = CrawlerHunt.Stance.IDLE
		_update_training_range_tag()
		if _alive:
			_publish_state(delta)
		return
	if not _alive:
		return
	var clock := Time.get_ticks_usec()
	var lod := _director_lod
	if directed_frame != Engine.get_physics_frames() or lod < 0:
		lod = MobSense.lod_at(global_position)
	if lod == CrawlerRules.MOB_LOD_COLD:
		var directed := MobSense.was_directed(self)
		if directed:
			_integrate_director(delta)
		else:
			_tick_cold(delta, true)
			_integrate_director(delta)
		var stride := maxi(CrawlerRules.MOB_COLD_STRIDE, 1)
		if (Engine.get_physics_frames() + get_instance_id()) % stride == 0:
			if directed:
				_tick_statuses(delta * float(stride))
			_publish_state(delta)
			MobSense.note_tick(
				self, Time.get_ticks_usec() - clock, lod, false, _attacking())
		return
	_attack_left = maxf(_attack_left - delta, 0.0)
	_tick_statuses(delta)
	if not _alive:
		MobSense.note_tick(
			self, Time.get_ticks_usec() - clock, lod, false, _attacking())
		return
	var hot := lod == CrawlerRules.MOB_LOD_HOT
	var thought := false
	if _movement_locked():
		velocity = Vector3.ZERO
	else:
		# Director marks every hot body directed, then only a few get a
		# think token. Idle walkers used to skip both the planner and the
		# far tick, so a gray next to the player kept patrolling.
		if hot and not chase and not is_charmed():
			var prey := _nearest_player()
			if prey != null:
				tick_agro(prey, delta)
		if hot and MobSense.take_think(self, chase or is_charmed()):
			var think_clock := Time.get_ticks_usec()
			_tick_ai(delta)
			MobSense.note_think_usec(Time.get_ticks_usec() - think_clock)
			thought = true
			var field_slow := MobSense.field_slow(self, global_position)
			if field_slow < 0.999:
				velocity *= field_slow
		else:
			_tick_far(delta)
	if thought:
		_respect_flyer_ceiling(delta)
		_keep_clear_of_terrain(false)
		_keep_out_of_safe_zones()
	else:
		_director_climb()
	if director_push.length_squared() > 0.0001 and not _movement_locked():
		velocity += director_push
		director_push = Vector3.ZERO
	if not _movement_locked() and (
			thought or lod == CrawlerRules.MOB_LOD_WARM or hunting()):
		if hunt_stance == CrawlerHunt.Stance.AGRO:
			_face_combat_player(delta)
		elif _faces_motion:
			_face_motion(delta)
	# Mask is 0, so move_and_slide would not collide. Integrate the same way
	# far and near so a crowd does not pay a physics-server slide each tick.
	if velocity.length_squared() > 0.0001:
		global_position += velocity * delta
	# Walkers have no collision mask. Snap every move so a slope cannot
	# swallow them or leave them walking the cycle in the air.
	if thought or not flies():
		_keep_clear_of_terrain(true)
	_publish_state(delta)
	MobSense.note_tick(
		self, Time.get_ticks_usec() - clock, lod, thought, _attacking())


func _tick_ai(_delta: float) -> void:
	pass


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	_patrol(delta)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		var along := _seek_along(player)
		if along.length_squared() < 0.04:
			return
		_match_speed(move_speed(), delta, 1.2, 16.0)
		_steer_toward(along.normalized() * _cruise, delta, 10.0)
		return
	_tick_idle(delta)


func _tick_cold(delta: float, steer := true) -> void:
	var stride := maxi(CrawlerRules.MOB_COLD_STRIDE, 1)
	if (Engine.get_physics_frames() + get_instance_id()) % stride == 0:
		var step := delta * float(stride)
		_attack_left = maxf(_attack_left - step, 0.0)
		_tick_statuses(step)
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	if not steer:
		return
	if _maybe_glorb_inbound(delta):
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		var along := _seek_along(player)
		if along.length_squared() >= 0.04:
			_match_speed(move_speed(), delta, 1.2, 16.0)
			_steer_toward(along.normalized() * _cruise, delta, 10.0)
		return
	_tick_idle(delta)


func _integrate_director(delta: float, snap := true) -> void:
	var frozen := _movement_locked()
	if director_push.length_squared() > 0.0001 and not frozen:
		velocity += director_push
	director_push = Vector3.ZERO
	if snap and not frozen and not flies():
		_director_climb()
	if not frozen and velocity.length_squared() > 0.0001:
		global_position += velocity * delta
	if snap and not frozen and not flies():
		_keep_clear_of_terrain(true)


func _coast_director(delta: float) -> void:
	var frozen := _movement_locked()
	if director_push.length_squared() > 0.0001 and not frozen:
		velocity += director_push
	director_push = Vector3.ZERO
	if frozen or velocity.length_squared() < 0.0001:
		return
	global_position += velocity * delta
	if flies():
		_keep_flyer_loft()
	elif _director_lod == CrawlerRules.MOB_LOD_HOT:
		_keep_clear_of_terrain(true)


func _movement_locked() -> bool:
	return false if statuses.is_empty() else is_frozen()


func _build_body() -> void:
	pass


func patch_health_scale() -> float:
	return _patch_health_scale


func set_threat_level(level: int) -> void:
	if level == threat_level:
		return
	threat_level = maxi(level, 0)
	_apply_threat_stats(true)


func refill_health() -> void:
	_health = _maximum_health
	_force_publish()


func _apply_threat_stats(rescale_current: bool) -> void:
	var row := CrawlerMobs.stats(wild_kind(), threat_level)
	var catalog_health := float(row.get("health", _base_health))
	if not is_finite(catalog_health) or catalog_health <= 0.0:
		catalog_health = _base_health
	var health_scale := _patch_health_scale
	if row.is_empty():
		health_scale *= CrawlerRules.threat_health(threat_level)
	var next_max := maxf(catalog_health * health_scale, 1.0)
	_row_level = -999
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
	_pull_row()
	var pace := 1.0 if statuses.is_empty() else statuses.move_scale()
	return _row_speed * pace


func fire_scale() -> float:
	_pull_row()
	if _row_fire > 0.0:
		return _row_fire
	return CrawlerRules.threat_fire(threat_level)


func _pull_row() -> void:
	if _row_level == threat_level and _row_speed >= 0.0:
		return
	var kind := wild_kind()
	_row_level = threat_level
	var row := CrawlerMobs.stats(kind, threat_level)
	if not row.is_empty() and row.has("speed"):
		_row_speed = maxf(float(row.get("speed", _base_speed)), 0.0)
	else:
		_row_speed = _base_speed * CrawlerRules.threat_speed(threat_level)
	_row_fire = CrawlerMobs.number(kind, threat_level, "fire", 0.0)
	_row_agro = CrawlerMobs.number(
		kind, threat_level, "agro_range", CrawlerRules.AGRO_RANGE)
	_row_deagro = CrawlerMobs.number(
		kind, threat_level, "deagro_range", CrawlerRules.DEAGRO_RANGE)
	_row_agro_mode = CrawlerMobs.agro_mode(kind, threat_level)


func receive_reflected_damage(amount: float, source_peer: int) -> void:
	if not _is_host() or amount <= 0.0 or not _alive:
		return
	var hit := DamageHit.impact(combat_position(), combat_radius(), amount)
	hit.faction = DamageHit.Faction.PLAYER
	hit.source_peer = source_peer
	hit.ability_id = "cape_reflect"
	var source := _player_for_peer(source_peer)
	if source != null:
		hit.set_source(source, source_peer)
	var dealt := apply_damage(hit)
	if dealt > 0.0 and source != null \
			and source.has_method(&"combat_damage_dealt"):
		source.call(&"combat_damage_dealt", self, dealt, hit)


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _alive or not _is_host() or not _accepts_hit(hit):
		return 0.0
	var status_applied := CrawlerElements.apply_to_combatant(self, hit)
	_status_frame = -1
	var actual := minf(maxf(hit.amount, 0.0) if is_finite(hit.amount) else 0.0, _health)
	if actual <= 0.0 and not status_applied:
		return 0.0
	if actual > 0.0:
		_health -= actual
		_flash_left = DAMAGE_FLASH_SECONDS
		if _director_lod == CrawlerRules.MOB_LOD_COLD:
			set_process(true)
	if hit.source_peer > 0:
		last_source_peer = hit.source_peer
	if training:
		chase = false
		ever_chased = false
	else:
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
	_pull_status()
	return _charmed_now


func is_frozen() -> bool:
	_pull_status()
	return _frozen_now


func _pull_status() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _status_frame:
		return
	_status_frame = frame
	if statuses.is_empty():
		_charmed_now = false
		_frozen_now = false
		return
	_charmed_now = statuses.has(CombatStatuses.CHARM)
	_frozen_now = statuses.movement_locked()


func outgoing_faction() -> int:
	return DamageHit.Faction.PLAYER if is_charmed() \
		else DamageHit.Faction.ENEMY


func _tick_statuses(delta: float) -> void:
	if statuses.is_empty():
		return
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
	if statuses.has(CombatStatuses.FREEZE) or statuses.has(CombatStatuses.SLOW):
		var frost := statuses.strength(CombatStatuses.FREEZE)
		if frost <= 0.0:
			frost = statuses.strength(CombatStatuses.SLOW)
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
	var had_freeze := statuses.has(CombatStatuses.FREEZE) \
		or statuses.has(CombatStatuses.SLOW)
	statuses.tick(delta)
	_status_frame = -1
	if statuses.consume_pulse(CombatStatuses.CHARM, CombatStatuses.CHARM_PULSE):
		_emit_status_float(DamageNumberEvent.Kind.CHARM, 1.0)
	if statuses.consume_shock_pulse():
		_emit_status_float(DamageNumberEvent.Kind.SHOCK, 1.0)
	if had_poison and not statuses.has(CombatStatuses.POISON) and _poison_float > 0.0:
		_emit_status_float(DamageNumberEvent.Kind.POISON, _poison_float)
		_poison_float = 0.0
	if had_freeze and not statuses.has(CombatStatuses.FREEZE) \
			and not statuses.has(CombatStatuses.SLOW) and _frost_float > 0.0:
		_emit_status_float(DamageNumberEvent.Kind.FREEZE, _frost_float)
		_frost_float = 0.0
	if had_charm and not is_charmed():
		MobSense.note_charmed(self, false)
		chase = true
		ever_chased = true
		idle_seconds = 0.0


func _exit_tree() -> void:
	MobSense.note_gone(self)


func set_inbound(heading: Vector3) -> void:
	inbound_heading = heading
	if inbound_heading.length_squared() > 0.0001:
		inbound_heading = inbound_heading.normalized()
	if CrawlerRules.is_glorb_kind(wild_kind()):
		show_range_tag = true
		_mount_training_range_tag()
		set_process(true)


func glorb_inbound() -> bool:
	return _kind_is_glorb and not chase and not hunting() \
		and inbound_heading.length_squared() > 0.0001


func _maybe_glorb_inbound(delta: float) -> bool:
	if not _kind_is_glorb or chase or hunting():
		return false
	if _director_lod == CrawlerRules.MOB_LOD_HOT:
		var player := _nearest_player()
		if player != null:
			tick_agro(player, delta)
		if chase or hunting():
			return false
	if inbound_heading.length_squared() < 0.0001:
		return false
	_run_glorb_inbound(delta)
	return true


func _run_glorb_inbound(delta: float) -> void:
	var up := _up()
	var heading := inbound_heading - up * inbound_heading.dot(up)
	if heading.length_squared() < 0.0001:
		heading = inbound_heading
	heading = heading.normalized()
	inbound_heading = heading
	var lag := CrawlerRules.GLORB_FLYER_INBOUND_LAG \
		if CrawlerRules.is_glorb_soft_flyer(wild_kind()) else 1.6
	var floor_rate := CrawlerRules.GLORB_FLYER_INBOUND_FLOOR \
		if CrawlerRules.is_glorb_soft_flyer(wild_kind()) else 12.0
	var steer := CrawlerRules.GLORB_FLYER_INBOUND_STEER \
		if CrawlerRules.is_glorb_soft_flyer(wild_kind()) else 8.0
	_match_speed(move_speed(), delta, lag, floor_rate)
	_steer_toward(heading * _cruise, delta, steer)
	var keep := velocity
	velocity = heading * maxf(keep.length(), 1.2)
	_face_motion(delta)
	velocity = keep


func _paint_glorb_white() -> void:
	for material in _materials:
		if material == null:
			continue
		material.set_shader_parameter(&"albedo", Color.WHITE)
		material.set_shader_parameter(&"paint_mix", 0.0)
		material.set_shader_parameter(&"vertex_mix", 0.0)
		material.set_shader_parameter(&"emit_color", Color(0, 0, 0, 1))
		material.set_shader_parameter(&"emit_energy", 0.0)


func _apply_glorb_ethereal() -> void:
	_materials.clear()
	var creature := get_node_or_null("Creature") as Node
	if creature == null:
		return
	for node_variant: Variant in creature.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		var material := ShaderMaterial.new()
		material.shader = CrawlerGlorb.SKIN_SHADER
		material.set_shader_parameter(&"rim_strength", 0.0)
		material.set_shader_parameter(&"flash", 0.0)
		mesh.material_override = material
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(surface, null)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_materials.append(material)
		_material = material
		if _visual == null:
			_visual = mesh
	_scale_enemy_outline(CrawlerGlorb.height(wild_kind()))


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


func is_training() -> bool:
	return training


func become_training(home := Transform3D.IDENTITY) -> void:
	training = true
	persistent = true
	chase = false
	ever_chased = false
	idle_seconds = 0.0
	if home.origin.length_squared() > 0.01:
		hang_origin = home.origin
		global_transform = home
		reset_physics_interpolation()
	elif hang_origin.length_squared() < 0.01:
		hang_origin = global_position
	_mount_training_range_tag()
	set_process(true)


func _mount_training_range_tag() -> void:
	if get_node_or_null("TrainingRange") != null:
		_update_training_range_tag()
		return
	var tag := Label3D.new()
	tag.name = "TrainingRange"
	tag.pixel_size = 0.022
	tag.font_size = 64
	tag.outline_size = 18
	tag.modulate = Color("f4f6ff")
	tag.outline_modulate = Color(0.04, 0.03, 0.08, 0.92)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	add_child(tag)
	_update_training_range_tag()


func _update_training_range_tag() -> void:
	var tag := get_node_or_null("TrainingRange") as Label3D
	if tag == null:
		return
	var lift := 3.8 if show_range_tag and not training else 2.2
	tag.position = Vector3(0.0, maxf(ground_clearance() * 2.8 + 1.2, lift), 0.0)
	var metres := 0
	if is_inside_tree():
		var player := _local_player()
		if player != null:
			metres = roundi(global_position.distance_to(player.global_position))
	if show_range_tag and not training:
		tag.text = "%d m" % metres
		return
	tag.text = "%s\n%d m" % [
		CrawlerMobs.title(wild_kind(), threat_level),
		metres,
	]


func _local_player() -> Node3D:
	if NetworkManager == null or NetworkManager.active_world == null:
		return _nearest_player()
	var world := NetworkManager.active_world
	if world.has_method(&"local_player"):
		var local: Variant = world.call(&"local_player")
		if local is Node3D:
			return local as Node3D
	return _nearest_player()


func flies() -> bool:
	return CrawlerRules.flies(wild_kind())


func flyer_ceiling() -> float:
	return CrawlerMobs.number(
		wild_kind(), threat_level, "flyer_ceiling",
		CrawlerRules.flyer_ceiling(maxi(threat_level, 1)))


func flyer_floor() -> float:
	return combat_radius() + 1.6


func ground_clearance() -> float:
	if _kind_is_glorb and not flies():
		return CrawlerGlorb.height(wild_kind()) * 0.5
	if _stand_height > 0.2:
		return _stand_height * 0.5
	if has_method("body_height"):
		return maxf(float(call("body_height")) * 0.5, 0.55)
	return 0.85


func mesh_surface(at := Vector3.INF) -> Vector3:
	var point := at if at.is_finite() else global_position
	if _planet == null or _planet.shape == null:
		return Vector3.INF
	var local := _planet.to_local(point)
	if local.length_squared() < 0.0001:
		local = Vector3.UP
	return _planet.mesh_position(local)


func ground_surface(at := Vector3.INF) -> Vector3:
	var point := at if at.is_finite() else global_position
	if not _should_probe_ground():
		var mesh := mesh_surface(point)
		if mesh.is_finite():
			return mesh
	var hit := _probe_ground(point)
	if hit.is_finite():
		return hit
	return mesh_surface(point)


func snap_to_ground() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _snap_frame \
			and global_position.distance_squared_to(_cached_alt_at) < 0.04:
		return
	var surface := ground_surface()
	if not surface.is_finite():
		return
	var up := _up()
	if _planet != null:
		up = _planet.up_at(surface)
	# Only the radial. Assigning `surface + up * clearance` rewinds a walker
	# when the probe cache still holds last frame's hit, which is why a
	# gloam flock played the run cycle without closing.
	var height := (global_position - surface).dot(up)
	global_position += up * (ground_clearance() - height)
	velocity -= up * velocity.dot(up)
	_cached_alt = ground_clearance()
	_cached_alt_at = global_position
	_snap_frame = frame


func surface_altitude(at := Vector3.INF) -> float:
	var point := at if at.is_finite() else global_position
	if not at.is_finite() and point.distance_squared_to(_cached_alt_at) < 0.04:
		return _cached_alt
	var surface := ground_surface(point)
	if not surface.is_finite():
		return 0.0
	var up := _up()
	if _planet != null:
		up = _planet.up_at(surface)
	var altitude := (point - surface).dot(up)
	if not at.is_finite():
		_cached_alt = altitude
		_cached_alt_at = point
	return altitude


func _should_probe_ground() -> bool:
	return _director_lod != CrawlerRules.MOB_LOD_WARM \
		and _director_lod != CrawlerRules.MOB_LOD_COLD


func _probe_ground(from: Vector3) -> Vector3:
	# 12 cm matches one walk frame at field speed, so a runner does not
	# recast every physics tick. Shared cells reuse a neighbour's hit in
	# a pile-up without changing the snap plane those bodies already share.
	if from.distance_squared_to(_ground_from) <= 0.0144 and _ground_hit.is_finite():
		return _ground_hit
	var shared := MobSense.peek_ground(from)
	if shared.is_finite():
		_ground_from = from
		_ground_hit = shared
		return shared
	if not is_inside_tree() or get_world_3d() == null:
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	if space == null:
		return Vector3.INF
	var up := _up()
	if _planet != null:
		up = _planet.up_at(from)
	var skip: Array[RID] = []
	_append_collider_rids(self, skip)
	if _ground_query == null:
		_ground_query = PhysicsRayQueryParameters3D.new()
		_ground_query.collide_with_areas = false
	var at := Vector3.INF
	var hint := mesh_surface(from)
	if _planet != null and hint.is_finite():
		at = _probe_hint_band(space, from, hint, up, skip)
	else:
		at = _probe_near_body(space, from, up, skip)
	if not at.is_finite():
		return Vector3.INF
	_ground_from = from
	_ground_hit = at
	MobSense.store_ground(from, at)
	return at


func _probe_hint_band(
		space: PhysicsDirectSpaceState3D, from: Vector3, hint: Vector3,
		up: Vector3, skip: Array[RID]) -> Vector3:
	# The band-limited mesh is the hill the player walks. Cast from above
	# that hint so a walker already inside the slope still sees the top.
	# Hits far above the hint are roofs and trees; skip those.
	var high := from
	if (hint - from).dot(up) > 0.0:
		high = hint
	var above := maxf(ground_clearance() + 2.6, 3.4)
	if flies():
		above = maxf(8.0, flyer_floor() + 2.0)
	var start := high + up * above
	var stop := hint - up * 8.0
	var tries := 0
	while tries < 8:
		tries += 1
		_ground_query.from = start
		_ground_query.to = stop
		_ground_query.exclude = skip
		var hit := space.intersect_ray(_ground_query)
		if hit.is_empty():
			return hint
		var collider := hit.get("collider") as Object
		if _ignore_ground_collider(collider):
			if collider is CollisionObject3D:
				var body := collider as CollisionObject3D
				var rid := body.get_rid()
				if rid.is_valid() and not skip.has(rid):
					skip.append(rid)
			continue
		var at: Vector3 = hit.get("position", Vector3.INF)
		if not at.is_finite():
			return hint
		if not flies() and (at - hint).dot(up) > 2.4:
			start = at - up * 0.18
			continue
		return at
	return hint


func _probe_near_body(
		space: PhysicsDirectSpaceState3D, from: Vector3, up: Vector3,
		skip: Array[RID]) -> Vector3:
	# No planet mesh to compare. Start just above the body so a roof in
	# the siege pad test is skipped and the floor under it is kept.
	var probe := maxf(ground_clearance() + 0.55, 1.5)
	if flies():
		probe = maxf(8.0, flyer_floor() + 2.0)
	var start := from + up * probe
	var stop := from - up * 80.0
	var tries := 0
	while tries < 8:
		tries += 1
		_ground_query.from = start
		_ground_query.to = stop
		_ground_query.exclude = skip
		var hit := space.intersect_ray(_ground_query)
		if hit.is_empty():
			return Vector3.INF
		var collider := hit.get("collider") as Object
		if _ignore_ground_collider(collider):
			if collider is CollisionObject3D:
				var body := collider as CollisionObject3D
				var rid := body.get_rid()
				if rid.is_valid() and not skip.has(rid):
					skip.append(rid)
			continue
		var at: Vector3 = hit.get("position", Vector3.INF)
		if not at.is_finite():
			return Vector3.INF
		if not flies() and (at - from).dot(up) > 0.4:
			start = at - up * 0.18
			continue
		return at
	return Vector3.INF


func _append_collider_rids(node: Node, skip: Array[RID]) -> void:
	if node == self:
		if _ground_skip.is_empty():
			_collect_collider_rids(self, _ground_skip)
		for rid: RID in _ground_skip:
			if rid.is_valid() and not skip.has(rid):
				skip.append(rid)
		return
	_collect_collider_rids(node, skip)


func _collect_collider_rids(node: Node, skip: Array[RID]) -> void:
	if node is CollisionObject3D:
		var rid := (node as CollisionObject3D).get_rid()
		if rid.is_valid() and not skip.has(rid):
			skip.append(rid)
	if node == null:
		return
	for child: Node in node.get_children():
		_collect_collider_rids(child, skip)


func _ignore_ground_collider(collider: Object) -> bool:
	if collider is CharacterBody3D:
		return true
	var walk := collider as Node
	while walk != null:
		if walk is CrawlerMob or walk is OnlinePlayer:
			return true
		if walk.is_in_group(DamageHit.COMBATANT_GROUP):
			return true
		walk = walk.get_parent()
	return false


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
	if not flies():
		if snap:
			snap_to_ground()
		return
	if _planet == null:
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
	if snap:
		_nudge_off_slope()


func _nudge_off_slope() -> void:
	if not flies() or not is_inside_tree() or get_world_3d() == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var up := _up()
	var ahead := velocity - up * velocity.dot(up)
	if ahead.length_squared() < 0.36:
		return
	var reach := maxf(combat_radius() + 3.2, 6.0)
	var query := PhysicsRayQueryParameters3D.create(
		global_position + up * 1.4,
		global_position + ahead.normalized() * reach)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") is CharacterBody3D:
		return
	var normal: Vector3 = hit.get("normal", up)
	if normal.length_squared() < 0.0001:
		normal = up
	normal = normal.normalized()
	var into := -velocity.dot(normal)
	if into > 0.0:
		velocity += normal * (into + maxf(10.0, _cruise * 0.22))
	velocity += up * maxf(into, 8.0)
	var at: Vector3 = hit.get("position", global_position)
	if not at.is_finite():
		return
	var pad := maxf(combat_radius() * 0.28, 2.0)
	var sunk := pad - global_position.distance_to(at)
	if sunk > 0.0:
		global_position += normal * sunk


func combat_display_name() -> String:
	return "Crawler"


func combat_position() -> Vector3:
	if _hit_ready:
		return to_global(_hit_local.position + _hit_local.size * 0.5)
	return global_position + _up() * 0.6


func combat_radius() -> float:
	if _hit_ready:
		var pill := _pill_from_local(_hit_local)
		return maxf(float(pill.get("radius", 0.7)), 0.22)
	return 0.7


func recycle_to(at: Vector3) -> void:
	chase = false
	ever_chased = false
	idle_seconds = 0.0
	director_push = Vector3.ZERO
	director_sep = Vector3.ZERO
	_director_lod = -1
	_ground_from = Vector3.INF
	_ground_hit = Vector3.INF
	_snap_frame = -1
	if at.is_finite():
		hang_origin = at
		_patrol_goal = at
	warp_to(at)


func set_director_lod(lod: int) -> void:
	if not _is_host() or not _alive:
		return
	if lod == _director_lod:
		return
	_director_lod = lod
	set_physics_process(lod == CrawlerRules.MOB_LOD_HOT)
	set_process(lod != CrawlerRules.MOB_LOD_COLD \
		or _flash_left > 0.0 or _spotted_left > 0.0 \
		or training or show_range_tag or _animator != null)


func director_cold_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	var clock := Time.get_ticks_usec()
	director_push = director_sep
	if steer:
		director_far_steer(step, player, in_city)
		_integrate_director(delta, true)
		_attack_left = maxf(_attack_left - step, 0.0)
		_tick_statuses(step)
		_publish_state(delta)
	else:
		_coast_director(delta)
	MobSense.note_tick(
		self, Time.get_ticks_usec() - clock, CrawlerRules.MOB_LOD_COLD, false, _attacking())


func director_warm_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	var clock := Time.get_ticks_usec()
	_attack_left = maxf(_attack_left - delta, 0.0)
	_tick_statuses(delta)
	director_push = director_sep
	if steer:
		director_far_steer(step, player, in_city)
		if not _movement_locked():
			if hunt_stance == CrawlerHunt.Stance.AGRO:
				_face_combat_player(delta)
			elif _faces_motion:
				_face_motion(delta)
		_integrate_director(delta, true)
		_publish_state(delta)
	else:
		_coast_director(delta)
	MobSense.note_tick(
		self, Time.get_ticks_usec() - clock, CrawlerRules.MOB_LOD_WARM, false, _attacking())


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	if _maybe_glorb_inbound(step):
		if flies():
			_director_climb()
		return
	if player != null and _apply_agro(player, step, in_city):
		if CrawlerHunt.uses_hunt(wild_kind()):
			_tick_hunt_motion(player, step)
		else:
			var along := _seek_along(player)
			if along.length_squared() >= 0.04:
				_match_speed(move_speed(), step, 1.2, 16.0)
				_steer_toward(along.normalized() * _cruise, step, 10.0)
	else:
		_tick_idle(step)
	if flies():
		_director_climb()


func _director_climb() -> void:
	if _movement_locked():
		return
	if flies():
		_keep_flyer_loft()
		return
	var up := _up()
	var altitude := _guess_altitude()
	var want := ground_clearance()
	var rise := velocity.dot(up)
	if altitude > want + 0.45:
		if rise > 0.0:
			velocity -= up * rise
		velocity -= up * clampf((altitude - want) * 7.0, 3.0, 20.0)
		return
	if rise < 0.0:
		velocity -= up * rise


func stands_off() -> bool:
	return CrawlerMobs.attack_mode(wild_kind(), maxi(threat_level, 1)) == "standoff"


func _seek_along(player: Node) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if stands_off():
		return _standoff_goal(player) - global_position
	return _combat_position_of(player) - global_position


func _standoff_goal(player: Node) -> Vector3:
	var at := _combat_position_of(player)
	var hold := maxf(
		CrawlerMobs.number(
			wild_kind(), maxi(threat_level, 1), "standoff_min",
			CrawlerRules.RANGER_STANDOFF_MIN),
		CrawlerRules.RANGER_CROWN_CLEAR)
	var up := _loft_axis()
	var along := global_position - at
	var flat := along - up * along.dot(up)
	if flat.length_squared() < 0.2:
		flat = _orbit_bias()
		flat -= up * flat.dot(up)
	if flat.length_squared() < 0.0001:
		flat = up.cross(Vector3.RIGHT)
	if flat.length_squared() < 0.0001:
		return _clamp_flyer_band(at + up * flyer_floor())
	return _clamp_flyer_band(at + flat.normalized() * hold)


func _loft_axis() -> Vector3:
	return _up() if _planet != null else Vector3.UP


func _track_rank() -> int:
	return maxi(threat_level, 1)


func _track_hold_min() -> float:
	if CrawlerHunt.uses_hunt(wild_kind()):
		return CrawlerHunt.hold_min(wild_kind())
	return CrawlerMobs.number(
		wild_kind(), _track_rank(), "standoff_min", CrawlerRules.RANGER_STANDOFF_MIN)


func _track_hold_max() -> float:
	if CrawlerHunt.uses_hunt(wild_kind()):
		return CrawlerHunt.hold_max(wild_kind())
	return CrawlerMobs.number(
		wild_kind(), _track_rank(), "standoff_max",
		CrawlerRules.RANGER_STANDOFF_MAX)


func _flyer_match_lag() -> float:
	if CrawlerRules.is_glorb_soft_flyer(wild_kind()):
		return CrawlerRules.GLORB_FLYER_MATCH_LAG
	return CrawlerRules.ranger_match_lag(_track_rank())


func _flyer_match_floor() -> float:
	if CrawlerRules.is_glorb_soft_flyer(wild_kind()):
		return CrawlerRules.GLORB_FLYER_MATCH_FLOOR
	return CrawlerRules.ranger_match_floor(_track_rank())


func _flyer_match_lock() -> float:
	if CrawlerRules.is_glorb_soft_flyer(wild_kind()):
		return CrawlerRules.GLORB_FLYER_MATCH_LOCK
	return CrawlerRules.ranger_match_lock(_track_rank())


func _flyer_close_steer() -> float:
	if CrawlerRules.is_glorb_soft_flyer(wild_kind()):
		return CrawlerRules.GLORB_FLYER_CLOSE_STEER
	return 15.0


func _flyer_track(player: Node, delta: float) -> void:
	if CrawlerRules.is_glorb_soft_flyer(wild_kind()):
		_ring_track(player, delta)
		_keep_off_crown(player)
		return
	var at := _combat_position_of(player)
	var distance := global_position.distance_to(at)
	var player_speed := _player_speed(player)
	var hold := lerpf(_track_hold_min(), _track_hold_max(), _hold_share())
	var desired := _hover_hold(at, hold)
	var gap := global_position.distance_to(desired)
	if _is_matched(player, player_speed, gap, hold):
		_drift_in_frame(player, desired, delta)
	else:
		_close_on(player, desired, gap, hold, distance, player_speed, delta)
	_keep_off_crown(player)


func _hold_share() -> float:
	if _hold_cached >= 0.0:
		return _hold_cached
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(mob_id) & 0x7fffffff) + 4
	_hold_cached = rng.randf()
	return _hold_cached


func _flat_gap(player: Node) -> float:
	var along := global_position - _combat_position_of(player)
	var up := _loft_axis()
	along -= up * along.dot(up)
	return along.length()


func _hover_hold(at: Vector3, hold: float) -> Vector3:
	if CrawlerRules.is_glorb_soft_flyer(wild_kind()):
		return _ring_hold(at, hold)
	var up := _loft_axis()
	var reach := maxf(hold, CrawlerRules.RANGER_CROWN_CLEAR)
	var along := global_position - at
	var rise := along.dot(up)
	var bias := along - up * rise
	if bias.length_squared() < 0.2:
		bias = _orbit_bias()
		bias -= up * bias.dot(up)
	if bias.length_squared() < 0.0001:
		bias = up.cross(Vector3.RIGHT)
	if bias.length_squared() < 0.0001:
		bias = Vector3.FORWARD
	bias = bias.normalized()
	var desired := _clamp_flyer_band(at + bias * reach)
	var held := desired - at
	rise = held.dot(up)
	var flat := held - up * rise
	if flat.length() >= reach:
		return desired
	var out := flat if flat.length_squared() > 0.2 else bias
	out -= up * out.dot(up)
	if out.length_squared() < 0.0001:
		return desired
	return _clamp_flyer_band(at + out.normalized() * reach + up * rise)


func _ring_seed() -> float:
	return (float(hash(mob_id) & 0xffff) / 65535.0) * TAU


func _ring_spin() -> float:
	var sign := -1.0 if ((hash(mob_id) >> 3) & 1) == 0 else 1.0
	return CrawlerRules.GLORB_RING_STRAFE * sign


func _ring_angle() -> float:
	return _ring_seed() + _drift_clock * _ring_spin()


func _ring_axis(up: Vector3) -> Vector3:
	var lift := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var east := lift.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = lift.cross(Vector3.FORWARD)
	if east.length_squared() < 0.0001:
		return Vector3.FORWARD
	return east.normalized()


func _ring_dir(up: Vector3) -> Vector3:
	var lift := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var east := _ring_axis(lift)
	var north := lift.cross(east)
	if north.length_squared() < 0.0001:
		return east
	north = north.normalized()
	var yaw := _ring_angle()
	return east * cos(yaw) + north * sin(yaw)


func _ring_hold(at: Vector3, hold: float) -> Vector3:
	var up := _loft_axis()
	var reach := maxf(hold, CrawlerHunt.CROWN_CLEAR)
	var bias := _ring_dir(up)
	if bias.length_squared() < 0.0001:
		bias = Vector3.FORWARD
	return _clamp_flyer_band(at + bias.normalized() * reach)


func _ring_track(player: Node, delta: float) -> void:
	var step := maxf(delta, 0.0)
	_drift_clock += step
	var at := _combat_position_of(player)
	var hold := lerpf(_track_hold_min(), _track_hold_max(), _hold_share())
	var desired := _ring_hold(at, hold)
	var gap := global_position.distance_to(desired)
	if gap <= 5.5:
		_ring_ride(player, at, desired, hold, step)
		return
	_ring_close(player, desired, gap, step)


func _ring_close(player: Node, desired: Vector3, gap: float, delta: float) -> void:
	var player_speed := _player_speed(player)
	var extra := clampf(gap * 0.42, 6.0, CrawlerRules.GLORB_RING_CATCH)
	var wanted := maxf(player_speed + extra, move_speed())
	_match_speed(wanted, delta, _flyer_match_lag(), _flyer_match_floor())
	var intercept := desired + _player_velocity(player) * 0.22
	var along := intercept - global_position
	var up := _loft_axis()
	along -= up * along.dot(up) * 0.15
	var heading := along.normalized() if along.length_squared() > 0.04 \
		else _ring_dir(up)
	_steer_toward(heading * _cruise, delta, 12.0)


func _ring_ride(player: Node, at: Vector3, desired: Vector3, hold: float, delta: float) -> void:
	var frame := _player_velocity(player)
	_match_speed(frame.length(), delta, _flyer_match_lag(), _flyer_match_floor())
	var up := _loft_axis()
	var radial := desired - at
	radial -= up * radial.dot(up)
	var tangent := Vector3.ZERO
	if radial.length_squared() > 0.04:
		tangent = up.cross(radial.normalized()) * _ring_spin() * maxf(hold, 1.0)
	var spring := (desired - global_position) * 2.6
	var ride := frame + tangent + spring
	velocity = velocity.lerp(
		ride, clampf(CrawlerRules.GLORB_RING_LOCK * delta, 0.0, 1.0))
	_push_off_terrain(player, desired)


func _is_matched(player: Node, player_speed: float, gap: float, hold: float) -> bool:
	var rank := _track_rank()
	var target := minf(
		player_speed, CrawlerRules.ranger_chase_speed(player_speed, rank, false))
	if absf(_cruise - target) > CrawlerRules.ranger_match_slack(player_speed, rank):
		return false
	var flat := _flat_gap(player)
	if flat < CrawlerRules.RANGER_CROWN_CLEAR:
		return false
	return gap <= hold * 1.2 \
		or (flat >= _track_hold_min() * 0.85 and flat <= _track_hold_max() * 1.2)


func _close_on(
		player: Node,
		desired: Vector3,
		gap: float,
		hold: float,
		distance: float,
		player_speed: float,
		delta: float
	) -> void:
	var rank := _track_rank()
	var urgent := gap > hold * 0.55 or distance > _track_hold_max()
	var wanted_speed := maxf(
		CrawlerRules.ranger_chase_speed(player_speed, rank, urgent),
		move_speed())
	_match_speed(
		wanted_speed, delta,
		_flyer_match_lag(),
		_flyer_match_floor())
	var along := desired - global_position
	var to_player := _combat_position_of(player) - global_position
	var up := _loft_axis()
	var flat_to := to_player - up * to_player.dot(up)
	if flat_to.length() < _track_hold_min() and along.dot(to_player) > 0.0:
		if flat_to.length_squared() > 0.2:
			along = -flat_to
		else:
			along = _orbit_bias()
			along -= up * along.dot(up)
	var heading := along.normalized() if along.length_squared() > 0.04 \
		else _orbit_bias()
	_steer_toward(heading * _cruise, delta, _flyer_close_steer())


func _drift_in_frame(player: Node, desired: Vector3, delta: float) -> void:
	var rank := _track_rank()
	var player_speed := _player_speed(player)
	_match_speed(
		CrawlerRules.ranger_chase_speed(player_speed, rank, false),
		delta,
		_flyer_match_lag(),
		_flyer_match_floor())
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
	var bob := _hunt_strafe_offset(player, ahead, side, up, sway, delta)
	var spring := (desired - global_position) * 1.15
	var ride := frame + bob + spring
	velocity = velocity.lerp(
		ride, clampf(_flyer_match_lock() * delta, 0.0, 1.0))
	_push_off_terrain(player, desired)


func _push_off_terrain(player: Node, desired: Vector3) -> void:
	var up := _loft_axis()
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


func _keep_off_crown(player: Node) -> void:
	var at := _combat_position_of(player)
	var up := _loft_axis()
	var along := global_position - at
	var rise := along.dot(up)
	var flat := along - up * rise
	var clear := CrawlerHunt.CROWN_CLEAR if CrawlerHunt.uses_hunt(wild_kind()) \
		else CrawlerRules.RANGER_CROWN_CLEAR
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


func _guess_altitude() -> float:
	if not _cached_alt_at.is_finite() \
			or global_position.distance_squared_to(_cached_alt_at) > 64.0:
		return surface_altitude()
	var guessed := _cached_alt
	if global_position.distance_squared_to(_cached_alt_at) >= 0.04:
		guessed = _cached_alt + (global_position - _cached_alt_at).dot(_up())
	if not flies() and _snap_frame != Engine.get_physics_frames():
		var mesh := mesh_surface()
		if mesh.is_finite():
			var mesh_alt := (global_position - mesh).dot(_up())
			if absf(mesh_alt - guessed) > 0.6:
				return surface_altitude()
	return guessed


func _keep_flyer_loft() -> void:
	var floor_h := flyer_floor()
	var altitude := _guess_altitude()
	var up := _up()
	if altitude < floor_h:
		var down := -velocity.dot(up)
		if down > 0.0:
			velocity += up * down
		velocity += up * maxf((floor_h - altitude) * 6.0, 10.0)
		return
	var headroom := altitude - floor_h
	if headroom < 3.0:
		var down := -velocity.dot(up)
		if down > 0.0:
			velocity += up * down * clampf(1.0 - headroom / 3.0, 0.0, 1.0)


func warp_to(at: Vector3) -> void:
	if not at.is_finite():
		return
	var dest := at
	if flies():
		dest = _clamp_flyer_band(at)
	else:
		var surface := ground_surface(at)
		if surface.is_finite():
			var up := _up()
			if _planet != null:
				up = _planet.up_at(surface)
			dest = surface + up * ground_clearance()
	global_position = dest
	velocity = Vector3.ZERO
	if flies():
		_cached_alt_at = Vector3.INF
	else:
		_cached_alt = ground_clearance()
		_cached_alt_at = dest
	reset_physics_interpolation()
	_force_publish()


func combat_aabb() -> AABB:
	if _hit_ready:
		var a := to_global(_hit_local.position)
		var b := to_global(_hit_local.end)
		var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
		var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
		return AABB(lo, hi - lo).grow(HIT_SKIN)
	var half := combat_radius()
	var at := combat_position()
	return AABB(at - Vector3.ONE * half, Vector3.ONE * (half * 2.0))


func combat_capsule() -> Dictionary:
	if _hit_ready:
		return _pill_from_local(_hit_local)
	var at := combat_position()
	return {"a": at, "b": at, "radius": combat_radius()}


func _refresh_hit_bounds() -> void:
	if not is_inside_tree():
		_hit_ready = false
		return
	var root := find_child("Creature", false, false) as Node3D
	if root == null:
		_hit_ready = false
		return
	var bounds := _posed_bounds(root, self)
	if bounds.size.length() < 0.08:
		_hit_ready = false
		return
	_hit_local = bounds
	_hit_ready = true


func _posed_bounds(root: Node3D, space: Node3D = null, grow := 0.18) -> AABB:
	if root == null or not root.is_inside_tree():
		return AABB()
	var frame := space if space != null else self
	var inverse := frame.global_transform.affine_inverse()
	var bounds := AABB()
	var started := false
	for node_variant: Variant in root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node_variant as Skeleton3D
		if skeleton == null:
			continue
		var box := _skeleton_aabb(skeleton, grow)
		if box.size.length() < 0.05:
			continue
		box = inverse * skeleton.global_transform * box
		if started:
			bounds = bounds.merge(box)
		else:
			bounds = box
			started = true
	if started:
		return bounds
	for node_variant: Variant in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null or mesh.mesh == null or _skips_hit_mesh(mesh):
			continue
		var box := inverse * mesh.global_transform * mesh.get_aabb()
		if started:
			bounds = bounds.merge(box)
		else:
			bounds = box
			started = true
	return bounds


func _skeleton_aabb(skeleton: Skeleton3D, grow := 0.18) -> AABB:
	var bounds := AABB()
	var started := false
	for bone in skeleton.get_bone_count():
		var at := skeleton.get_bone_global_pose(bone).origin
		if started:
			bounds = bounds.expand(at)
		else:
			bounds = AABB(at, Vector3.ZERO)
			started = true
	if started:
		return bounds.grow(grow) if grow > 0.0 else bounds
	return AABB()


func _skips_hit_mesh(mesh: Node) -> bool:
	var folded := str(mesh.name).to_lower()
	return folded.contains("energy") or folded.contains("beam") \
		or folded.contains("glow") or folded.contains("vfx") \
		or folded.contains("shock")


func _pill_from_local(box: AABB) -> Dictionary:
	var center := box.position + box.size * 0.5
	var size := box.size
	var axis := 0
	if size.y >= size.x and size.y >= size.z:
		axis = 1
	elif size.z >= size.x:
		axis = 2
	var half_long := size[axis] * 0.5
	var cross := size.x
	if axis == 0:
		cross = maxf(size.y, size.z)
	elif axis == 1:
		cross = maxf(size.x, size.z)
	else:
		cross = maxf(size.x, size.y)
	var radius := maxf(cross * 0.5, 0.18) + HIT_SKIN
	var span := half_long - radius
	var step := Vector3.ZERO
	step[axis] = 1.0
	var a := center
	var b := center
	if span >= 0.08:
		a = center - step * span
		b = center + step * span
	else:
		radius = maxf(half_long, radius)
	return {"a": to_global(a), "b": to_global(b), "radius": radius}


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
	MobSense.ensure_frame(get_tree())
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


func is_boss_minion() -> bool:
	return false


func tick_agro(player: Node3D, delta: float) -> bool:
	var blocked := player != null and MobSense.player_in_city(player)
	if not blocked and not is_persistent() and player != null \
			and MobSense.player_in_castle_keep(player):
		blocked = true
	if not blocked and not is_boss_minion() and player != null \
			and _tree_boss_shields(player):
		blocked = true
	return _apply_agro(player, delta, blocked)


func _tree_boss_shields(player: Node) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	return MobSense.boss_protects(player)


func _apply_agro(player: Node3D, delta: float, in_city: bool) -> bool:
	if CrawlerHunt.uses_hunt(wild_kind()):
		return _apply_hunt(player, delta, in_city)
	_pull_row()
	var blocked := in_city or MobSense.player_on_spawn_pad(player)
	var gap := INF
	if player != null:
		gap = global_position.distance_to(player.global_position)
	var was_chasing := chase
	if player == null:
		chase = false
	elif blocked:
		chase = false
	elif chase and gap > _row_deagro:
		chase = false
	elif not chase and _row_agro_mode != "calm" and gap <= _row_agro:
		chase = true
	if chase:
		ever_chased = true
		idle_seconds = 0.0
		if not was_chasing:
			_on_agro_started()
	elif ever_chased:
		idle_seconds += maxf(delta, 0.0)
		if was_chasing and not chase:
			hang_origin = global_position
	return chase


func hunting() -> bool:
	return CrawlerHunt.hunting(hunt_stance)


func _apply_hunt(player: Node3D, delta: float, in_city: bool) -> bool:
	_pull_row()
	var blocked := in_city or MobSense.player_on_spawn_pad(player)
	var gap := INF
	if player != null:
		gap = global_position.distance_to(player.global_position)
	var was_chasing := chase
	var was := hunt_stance
	var drop := _hunt_drop()
	var rewake := _hunt_rewake()
	if player == null or blocked:
		hunt_stance = CrawlerHunt.Stance.DEAGRO if ever_chased \
			else CrawlerHunt.Stance.IDLE
	else:
		if chase and hunt_stance == CrawlerHunt.Stance.IDLE:
			hunt_stance = CrawlerHunt.Stance.AGRO
		match hunt_stance:
			CrawlerHunt.Stance.IDLE:
				if _should_first_agro(gap):
					hunt_stance = CrawlerHunt.Stance.AGRO
			CrawlerHunt.Stance.DEAGRO:
				if gap <= rewake:
					hunt_stance = CrawlerHunt.Stance.REAGRO
			CrawlerHunt.Stance.REAGRO:
				if gap > drop:
					hunt_stance = CrawlerHunt.Stance.DEAGRO
				else:
					hunt_stance = CrawlerHunt.Stance.AGRO
			CrawlerHunt.Stance.AGRO:
				if gap > drop:
					hunt_stance = CrawlerHunt.Stance.DEAGRO
				elif _should_pursue(player, gap):
					hunt_stance = CrawlerHunt.Stance.PURSUE
			CrawlerHunt.Stance.PURSUE:
				if gap > drop:
					hunt_stance = CrawlerHunt.Stance.DEAGRO
				elif _pursue_settled(player, gap):
					hunt_stance = CrawlerHunt.Stance.AGRO
		if hunt_stance == CrawlerHunt.Stance.REAGRO:
			hunt_stance = CrawlerHunt.Stance.AGRO if gap <= drop \
				else CrawlerHunt.Stance.DEAGRO
		if hunt_stance == CrawlerHunt.Stance.AGRO and _should_pursue(player, gap):
			hunt_stance = CrawlerHunt.Stance.PURSUE
	chase = CrawlerHunt.hunting(hunt_stance)
	if chase:
		ever_chased = true
		idle_seconds = 0.0
		if not was_chasing or was != CrawlerHunt.Stance.AGRO \
				and hunt_stance == CrawlerHunt.Stance.AGRO:
			if hunt_stance == CrawlerHunt.Stance.AGRO:
				_on_agro_started()
	elif ever_chased:
		idle_seconds += maxf(delta, 0.0)
		if was_chasing and not chase:
			hang_origin = global_position
			_hunt_set_air(false)
			if CrawlerRules.is_glorb_kind(wild_kind()):
				dismiss()
	return chase


func _hunt_drop() -> float:
	_pull_row()
	if CrawlerRules.is_glorb_kind(wild_kind()):
		return CrawlerRules.GLORB_DROP
	return CrawlerHunt.drop_gap(wild_kind(), _row_deagro)


func _hunt_wake() -> float:
	_pull_row()
	return CrawlerHunt.wake_gap(wild_kind(), _row_agro)


func _hunt_rewake() -> float:
	_pull_row()
	return CrawlerHunt.rewake_gap(wild_kind(), _row_agro)


func _should_first_agro(gap: float) -> bool:
	if _row_agro_mode == "calm":
		return false
	if CrawlerRules.is_glorb_kind(wild_kind()):
		return gap <= CrawlerRules.GLORB_AGRO
	if CrawlerHunt.role(wild_kind()) == CrawlerHunt.Role.FLY_RANGE \
			or wild_kind() == "bastion":
		return gap <= _hunt_wake()
	if CrawlerRules.field_ring_of(gap) == CrawlerRules.FIELD_RING_CLOSE:
		return true
	return gap <= maxf(_hunt_wake(), CrawlerHunt.FIRST_AGRO)


func _should_pursue(player: Node, gap: float) -> bool:
	var kind := wild_kind()
	if kind == CrawlerGlorb.KIND_SPIDER:
		return gap > CrawlerGlorbSpider.SHOT_RANGE
	if CrawlerRules.is_glorb_kind(kind):
		if CrawlerHunt.role(kind) == CrawlerHunt.Role.FLY_RANGE:
			return gap < CrawlerHunt.shot_min(kind, threat_level) \
				or gap > CrawlerHunt.shot_max(kind, threat_level) \
				or _player_fleeing(player)
		return _player_fleeing(player)
	match CrawlerHunt.role(kind):
		CrawlerHunt.Role.MELEE:
			return _player_fleeing(player)
		CrawlerHunt.Role.FLY_RANGE:
			return gap < CrawlerHunt.shot_min(kind, threat_level) \
				or gap > CrawlerHunt.shot_max(kind, threat_level)
		CrawlerHunt.Role.GROUND_RANGE:
			return kind == "rhino" and _player_fleeing(player)
	return false


func _pursue_settled(player: Node, gap: float) -> bool:
	var kind := wild_kind()
	match CrawlerHunt.role(kind):
		CrawlerHunt.Role.MELEE:
			return not _player_fleeing(player) \
				and gap <= CrawlerHunt.PURSUIT_LEAD + 4.0 \
				and (not _hunt_airborne or _near_hunt_perch(player))
		CrawlerHunt.Role.FLY_RANGE:
			return gap >= CrawlerHunt.shot_min(kind, threat_level) \
				and gap <= CrawlerHunt.shot_max(kind, threat_level)
		CrawlerHunt.Role.GROUND_RANGE:
			if kind == CrawlerGlorb.KIND_SPIDER:
				return gap <= CrawlerGlorbSpider.STOP_RANGE
			return kind == "rhino" and not _player_fleeing(player) \
				and gap <= CrawlerHunt.hold_max(kind)
	return true


func _player_fleeing(player: Node) -> bool:
	if player == null:
		return false
	var away := _combat_position_of(player) - global_position
	var up := _up()
	away -= up * away.dot(up)
	var motion := _player_velocity(player)
	motion -= up * motion.dot(up)
	if away.length_squared() < 0.04:
		return motion.length() > move_speed() + 1.0
	var recede := motion.dot(away.normalized())
	return recede > move_speed() + 1.0


func _near_hunt_perch(player: Node) -> bool:
	return global_position.distance_to(_hunt_ahead_perch(player)) \
		<= CrawlerHunt.MELEE_LAND


func _tick_hunt_motion(player: Node, delta: float) -> void:
	if player == null:
		return
	match CrawlerHunt.role(wild_kind()):
		CrawlerHunt.Role.MELEE:
			if hunt_stance == CrawlerHunt.Stance.PURSUE:
				_hunt_cut_ahead(player, delta)
			else:
				_hunt_charge(player, delta)
		CrawlerHunt.Role.FLY_RANGE:
			_flyer_track(player, delta)
		CrawlerHunt.Role.GROUND_RANGE:
			if hunt_stance == CrawlerHunt.Stance.PURSUE and wild_kind() == "rhino":
				_hunt_ground_catchup(player, delta)
			else:
				_hunt_ground_hold(player, delta)


func _hunt_charge(player: Node, delta: float) -> void:
	_hunt_set_air(false)
	var at := _combat_position_of(player)
	var along := at - global_position
	var up := _up()
	if not flies():
		along -= up * along.dot(up)
	_match_speed(move_speed(), delta, 0.45, 12.0)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 14.0)


func _hunt_cut_ahead(player: Node, delta: float) -> void:
	var perch := _hunt_ahead_perch(player)
	var loft := _need_hunt_lift(perch)
	if loft:
		_hunt_set_air(true)
	var wanted := CrawlerHunt.pursuit_speed(
		wild_kind(), _player_speed(player), move_speed())
	_match_speed(wanted, delta, 1.8, 22.0)
	var along := perch - global_position
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 13.0)
	if global_position.distance_to(perch) <= CrawlerHunt.MELEE_LAND:
		_hunt_set_air(false)


func _need_hunt_lift(perch: Vector3) -> bool:
	return (perch - global_position).dot(_up()) > 1.2


func _hunt_ahead_perch(player: Node) -> Vector3:
	var at := _combat_position_of(player)
	var up := _loft_axis()
	var look := _player_velocity(player)
	look -= up * look.dot(up)
	if look.length_squared() < 0.36 and player != null \
			and player.has_method(&"look_direction"):
		var facing: Variant = player.call(&"look_direction")
		if facing is Vector3:
			look = (facing as Vector3)
			look -= up * look.dot(up)
	if look.length_squared() < 0.0001:
		look = at - global_position
		look -= up * look.dot(up)
	if look.length_squared() < 0.0001:
		look = Vector3.FORWARD
	look = look.normalized()
	var right := look.cross(up)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var flank := -1.0 if (hash(mob_id) & 1) == 0 else 1.0
	var perch := at + look * CrawlerHunt.PURSUIT_LEAD \
		+ up * CrawlerHunt.PURSUIT_EYE + right * flank * 2.4
	var surface := ground_surface(perch)
	if surface.is_finite() and _planet != null:
		up = _planet.up_at(surface)
		perch = surface + up * CrawlerHunt.PURSUIT_EYE
	return perch


func _hunt_ground_hold(player: Node, delta: float) -> void:
	var at := _combat_position_of(player)
	var hold := lerpf(
		CrawlerHunt.hold_min(wild_kind()),
		CrawlerHunt.hold_max(wild_kind()),
		_hold_share())
	var along := global_position - at
	var up := _up()
	along -= up * along.dot(up)
	if along.length_squared() < 0.2:
		along = _orbit_bias()
		along -= up * along.dot(up)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	along = along.normalized()
	var desired := at + along * hold
	var pace := move_speed() * (0.55 + _hold_share() * 0.7)
	_match_speed(pace, delta, 1.1, 10.0)
	var heading := desired - global_position
	heading -= up * heading.dot(up)
	if heading.length_squared() < 0.12:
		velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
		return
	_steer_toward(heading.normalized() * _cruise, delta, 11.0)


func _hunt_ground_catchup(player: Node, delta: float) -> void:
	var perch := _hunt_ahead_perch(player)
	var along := perch - global_position
	along -= _up() * along.dot(_up())
	var wanted := CrawlerHunt.pursuit_speed(
		wild_kind(), _player_speed(player), move_speed())
	_match_speed(wanted, delta, 1.4, 14.0)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 12.0)


func _hunt_set_air(on: bool) -> void:
	if _hunt_airborne == on:
		return
	var was_flying := flies()
	_hunt_airborne = on
	if on and not was_flying:
		global_position += _up() * 1.2
		return
	if not on and not flies():
		snap_to_ground()
		velocity -= _up() * velocity.dot(_up())


func _hunt_strafe_offset(
		_player: Node, ahead: Vector3, side: Vector3, up: Vector3,
		sway: float, delta: float
	) -> Vector3:
	_hunt_strafe_left = maxf(_hunt_strafe_left - delta, 0.0)
	if _hunt_strafe_left <= 0.0 or _hunt_strafe.length_squared() < 0.0001:
		_hunt_strafe_left = CrawlerHunt.STRAFE_SECONDS \
			+ _hold_share() * 0.8
		var pick := posmod(hash(mob_id) + int(_drift_clock * 3.0), 3)
		if pick == 0:
			_hunt_strafe = side
		elif pick == 1:
			_hunt_strafe = up
		else:
			_hunt_strafe = (side + up).normalized()
	var phase := _hold_share() * TAU
	return _hunt_strafe * sin(_drift_clock * 1.1 + phase) * sway \
		+ ahead * sin(_drift_clock * 0.62 + phase) * (sway * 0.35)


func _face_combat_player(delta: float) -> void:
	var player := _nearest_player()
	if player == null:
		return
	var ahead := _combat_position_of(player) - global_position
	var up := _up()
	if not flies():
		ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	var desired := _look_basis(ahead.normalized(), up)
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
			clampf(delta * 9.0, 0.0, 1.0))).orthonormalized()


func _on_agro_started() -> void:
	pass


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
	if not flies():
		var up := _up()
		along -= up * along.dot(up)
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
	var dir := east * cos(yaw) + north * sin(yaw)
	if flies():
		dir += up * lift
	if dir.length_squared() < 0.0001:
		dir = east
	var at := hang_origin + dir.normalized() * reach
	if not flies():
		var surface := ground_surface(at)
		if surface.is_finite():
			var rise := _up()
			if _planet != null:
				rise = _planet.up_at(surface)
			return surface + rise * ground_clearance()
	return _clamp_flyer_band(at)


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
	_stand_height = visual_height
	_plant_visual(root, visual_height)
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node_variant as MeshInstance3D
		if mesh_instance == null:
			continue
		mesh_instance.material_override = _enemy_material(colour, paint, 1.0)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _visual == null:
			_visual = mesh_instance
	_scale_enemy_outline(visual_height)
	_bind_animator(model)
	return root


func _attach_skinned(scene: PackedScene, visual_height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Creature"
	add_child(root)
	var model := scene.instantiate()
	root.add_child(model)
	_stand_height = visual_height
	_fit_visual(root, visual_height)
	if CrawlerRules.is_glorb_kind(wild_kind()):
		_bind_animator(model)
		return root
	_collect_skinned_materials(model)
	_scale_enemy_outline(visual_height)
	_bind_animator(model)
	return root


func _fit_visual(root: Node3D, visual_height: float) -> void:
	var planted := _posed_bounds(root, root, 0.0)
	var bounds := _model_bounds(root)
	if planted.size.y <= 0.05:
		planted = bounds
	var scale := visual_height / maxf(bounds.size.y, 0.01)
	root.scale = Vector3.ONE * scale
	var mid := planted.position + planted.size * 0.5
	if CrawlerRules.is_glorb_kind(wild_kind()):
		root.position.x = -mid.x * scale
		root.position.z = -mid.z * scale
		if flies():
			root.position.y = -mid.y * scale
		else:
			root.position.y = -ground_clearance() - planted.position.y * scale
		return
	root.position.y = -visual_height * 0.5 - planted.position.y * scale


func _plant_visual(root: Node3D, visual_height: float) -> void:
	var saved := root.scale
	root.scale = Vector3.ONE
	var planted := _posed_bounds(root, root, 0.0)
	if planted.size.y <= 0.05:
		planted = _model_bounds(root)
	root.scale = saved
	root.position.y = -visual_height * 0.5 - planted.position.y * saved.y


func _model_bounds(root: Node3D) -> AABB:
	if root == null or not root.is_inside_tree():
		return AABB(Vector3.ZERO, Vector3(0.0, 1.8, 0.0))
	var bounds := _posed_bounds(root, root)
	if bounds.size.y <= 0.05:
		return AABB(Vector3.ZERO, Vector3(0.0, 1.8, 0.0))
	return bounds


func _collect_skinned_materials(model: Node) -> void:
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		if not is_instance_valid(node_variant):
			continue
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _visual == null:
			_visual = mesh
		_adopt_authored_mesh(mesh)


func _adopt_authored_mesh(mesh: MeshInstance3D) -> void:
	if mesh == null or mesh.mesh == null:
		return
	# One override would paint every Blender slot with surface 0. Demons
	# store obsidian there, so the whole body went black.
	mesh.material_override = null
	var count := mesh.mesh.get_surface_count()
	for surface in count:
		var material := mesh.get_active_material(surface)
		if material is BaseMaterial3D:
			var copy := _authored_enemy_material(material as BaseMaterial3D)
			mesh.set_surface_override_material(surface, copy)
		elif material is ShaderMaterial:
			var existing := material as ShaderMaterial
			if existing.shader == ENEMY_SHADER:
				var shader_copy := existing.duplicate() as ShaderMaterial
				_bind_enemy_outline(shader_copy)
				mesh.set_surface_override_material(surface, shader_copy)
				_materials.append(shader_copy)
				_material = shader_copy
			else:
				var colour: Variant = existing.get_shader_parameter(&"albedo")
				var paint: Variant = existing.get_shader_parameter(&"paint")
				var ink := Color(0.18, 0.06, 0.07)
				if colour is Color:
					ink = colour as Color
				var tex := paint as Texture2D
				mesh.set_surface_override_material(surface,
					_enemy_material(ink, tex, 1.0 if tex != null else 0.0))


func _authored_enemy_material(source: BaseMaterial3D) -> ShaderMaterial:
	var colour := source.albedo_color
	if colour.a < 0.02:
		colour.a = 1.0
	var paint := source.albedo_texture
	var material := _enemy_material(colour, paint, 1.0 if paint != null else 0.0)
	var glow := source.emission
	if source.emission_enabled and (glow.r + glow.g + glow.b) > 0.04:
		material.set_shader_parameter(&"emit_color", glow)
		material.set_shader_parameter(&"emit_energy",
			maxf(source.emission_energy_multiplier, 1.2))
	return material


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
	material.set_shader_parameter(&"emit_color", Color(0, 0, 0, 1))
	material.set_shader_parameter(&"emit_energy", 0.0)
	if paint != null:
		material.set_shader_parameter(&"paint", paint)
	_bind_enemy_outline(material)
	_materials.append(material)
	_material = material
	return material


func _bind_enemy_outline(material: ShaderMaterial) -> void:
	if material == null or material.next_pass != null:
		return
	var outline := ShaderMaterial.new()
	outline.shader = ENEMY_OUTLINE_SHADER
	outline.set_shader_parameter(&"outline_color", RIM)
	outline.set_shader_parameter(&"outline_width", 0.045)
	material.next_pass = outline


func _scale_enemy_outline(visual_height: float) -> void:
	_outline_height = maxf(visual_height, 0.5)
	var grow := 1.0
	var root := get_node_or_null("Creature") as Node3D
	if root == null:
		root = get_node_or_null("Demon") as Node3D
	if root != null:
		grow = maxf(absf(root.scale.y), 0.01)
	var world_width := clampf(_outline_height * 0.016, 0.036, 0.18)
	var width := world_width / grow
	for material in _materials:
		if material == null:
			continue
		var outline := material.next_pass as ShaderMaterial
		if outline == null or outline.shader != ENEMY_OUTLINE_SHADER:
			continue
		outline.set_shader_parameter(&"outline_width", width)


func _bind_animator(model: Node) -> void:
	_animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animator == null:
		return
	_animator.active = true
	_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_animator.playback_default_blend_time = CLIP_BLEND
	for clip in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_FLY]:
		var resolved := _resolve_clip(clip)
		if not resolved.is_empty() and _animator.has_animation(resolved):
			_animator.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR
	_update_clips()


func _resolve_clip(clip: String) -> String:
	if _animator == null or clip.is_empty():
		return ""
	if _clip_names.has(clip):
		return str(_clip_names[clip])
	var resolved := ""
	for alias: String in _clip_aliases(clip):
		var hit := _match_clip_name(alias)
		if not hit.is_empty():
			resolved = hit
			break
	_clip_names[clip] = resolved
	return resolved


func _clip_aliases(clip: String) -> PackedStringArray:
	match clip:
		CLIP_ATTACK:
			return PackedStringArray([CLIP_ATTACK, "Strike", "Bite", "Cast_Projectile"])
		CLIP_CAST:
			return PackedStringArray([CLIP_CAST, "Cast_Projectile", "Strike"])
		CLIP_HIT:
			return PackedStringArray([CLIP_HIT, "Hit", "HitReact"])
		CLIP_FLY:
			return PackedStringArray([CLIP_FLY, CLIP_RUN, "Hover"])
		CLIP_WALK:
			return PackedStringArray([CLIP_WALK, "Walk", "walking"])
		CLIP_RUN:
			return PackedStringArray([CLIP_RUN, "Run", "running"])
		CLIP_IDLE:
			return PackedStringArray([CLIP_IDLE, "Idle", "Hover"])
	return PackedStringArray([clip])


func _match_clip_name(need: String) -> String:
	if _animator == null or need.is_empty():
		return ""
	var folded := need.to_lower()
	var exact := ""
	var best := ""
	var best_len := 0.2
	for listed: String in _animator.get_animation_list():
		if not _clip_name_matches(listed, folded):
			continue
		var animation := _animator.get_animation(listed)
		if animation == null:
			continue
		var length := animation.length
		var keys := 0
		for track in animation.get_track_count():
			keys = maxi(keys, animation.track_get_key_count(track))
		if keys < 3:
			continue
		var tail := listed.get_file().to_lower()
		if tail == folded and length > 0.2:
			exact = listed
		if length > best_len:
			best_len = length
			best = listed
	if not exact.is_empty():
		return exact
	return best


func _clip_name_matches(listed: String, folded: String) -> bool:
	var tail := listed.get_file().to_lower()
	if _clip_tail_matches(tail, folded):
		return true
	var stem := tail.rstrip("0123456789").rstrip("_-")
	return stem != tail and _clip_tail_matches(stem, folded)


func _clip_tail_matches(tail: String, folded: String) -> bool:
	return tail == folded or tail.ends_with("/" + folded) \
		or tail.ends_with("__" + folded) or tail.ends_with("|" + folded) \
		or tail.ends_with("_" + folded)


func _begin_attack(seconds: float) -> bool:
	if not MobSense.take_attack(wild_kind()):
		return false
	_attack_left = maxf(seconds, 0.05)
	return true


func _attacking() -> bool:
	return _attack_left > 0.0


func current_clip() -> String:
	return _glorb_travel_clip(_desired_clip())


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


func _glorb_travel_clip(clip: String) -> String:
	if not CrawlerRules.is_glorb_kind(wild_kind()):
		return clip
	if clip != CLIP_IDLE and clip != CLIP_WALK and clip != CLIP_RUN \
			and clip != CLIP_FLY:
		return clip
	var speed := velocity.length()
	if speed < 0.55 and inbound_heading.length_squared() < 0.0001:
		return clip
	if flies():
		return CLIP_FLY if speed >= RUN_CLIP_SPEED * 0.35 else (
			CLIP_WALK if speed >= 0.55 or glorb_inbound() else CLIP_IDLE)
	if speed >= maxf(move_speed() * 1.15, RUN_CLIP_SPEED * 0.55):
		return CLIP_RUN
	if speed >= 0.55 or glorb_inbound():
		return CLIP_WALK
	return CLIP_IDLE


func _update_clips() -> void:
	if _animator == null:
		return
	var clip := _network_clip if not _is_host() and not _network_clip.is_empty() \
		else _desired_clip()
	clip = _glorb_travel_clip(clip)
	var resolved := _resolve_clip(clip)
	if resolved.is_empty():
		return
	var rate := 1.0
	if clip == CLIP_WALK:
		rate = clampf(velocity.length() / WALK_CLIP_SPEED, 0.55, 1.8)
	elif clip == CLIP_RUN:
		rate = clampf(velocity.length() / RUN_CLIP_SPEED, 0.55, 1.8)
	if resolved != _current_clip or not _animator.is_playing():
		_current_clip = resolved
		_animator.play(resolved, CLIP_BLEND)
	var scale := maxf(rate, 0.05)
	if not is_equal_approx(_animator.speed_scale, scale):
		_animator.speed_scale = scale


func _look_basis(ahead: Vector3, up: Vector3) -> Basis:
	return Basis.looking_at(ahead.normalized(), up, _uses_model_front).orthonormalized()


func _face_motion(delta: float) -> void:
	var up := _up()
	var ahead := velocity
	if _attacking():
		var target := _combat_target()
		if target != null:
			ahead = _combat_position_of(target) - global_position
	elif ahead.length_squared() < 1.0:
		var player := _nearest_player()
		if player != null:
			ahead = _combat_position_of(player) - global_position
		else:
			ahead = _patrol_goal - global_position
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	var desired := _look_basis(ahead, up)
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
	if is_equal_approx(flash, _last_flash):
		return
	_last_flash = flash
	for material in _materials:
		if material != null:
			material.set_shader_parameter(&"flash", flash)
	for index in _skinned_mats.size():
		var material := _skinned_mats[index]
		if material == null:
			continue
		var rest := _skinned_energy[index] if index < _skinned_energy.size() else 0.0
		var rest_color := _skinned_emit[index] if index < _skinned_emit.size() \
			else material.emission
		material.emission_enabled = flash > 0.04 or rest > 0.02
		material.emission = Color(1.0, 0.28, 0.18) if flash > 0.04 else rest_color
		material.emission_energy_multiplier = lerpf(rest, 3.4, flash)
