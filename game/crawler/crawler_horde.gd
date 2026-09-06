class_name CrawlerHorde
extends Node

## Host-authored field pack. Homes sit in a ring around the player. When the
## player is moving fast, an extra pack is seeded farther ahead of travel.
## They spawn far enough out to stay calm, then agro when the run reaches
## them. Player level and siege clears do not restat a pack already on the
## ground. They drop agro at range and vanish after they idle. A kill keeps
## that pad empty for a few seconds and the pack waits before filling.

const GROUP := &"crawler_horde"
const SPAWN_PER_FRAME := 16
const SPAWN_TRIES := 10
const FLYER_LIFT := 22.0
const RIFT_HULK := preload("res://game/crawler/crawler_rift_hulk.gd")
const RHINO := preload("res://game/crawler/crawler_rhino.gd")
const CITY_RING := preload("res://game/crawler/crawler_city_ring.gd")

var _city_clears := 0
var _threat := 0
var _next_mob := 1
var _spawn_serial := 0
var _mobs: Dictionary = {}
var _stream_left := 0.0
var _start_dir := Vector3.UP
var _start_origin := Vector3.ZERO
var _kill_marks: Array[Dictionary] = []
var _refill_until: Dictionary = {}


func _ready() -> void:
	name = "CrawlerHorde"
	add_to_group(GROUP)
	set_process(true)
	if not _is_host():
		_request_siege_sync.rpc_id(1)


func city_clears() -> int:
	return _city_clears


func threat_level() -> int:
	return _threat


func raise_threat() -> void:
	_city_clears += 1
	_threat += 1
	_publish_siege()


func wild_live_count() -> int:
	return _mobs.size()


func spawn_test_mob(kind := "ranger", at := Vector3(0.0, 12.0, 0.0),
		should_chase := false, level := 1) -> CrawlerMob:
	var id := "cm%d" % _next_mob
	_next_mob += 1
	return _make_mob(id, kind, _pose_at(at), level, should_chase, -1, -1)


func _process(delta: float) -> void:
	if not CrawlerRules.active() or not _is_host():
		return
	_remember_start()
	_reap_far_and_idle()
	_prune_kills()
	_stream_left -= delta
	if _stream_left > 0.0:
		return
	_stream_left = 0.22
	_fill_around_players()


func _remember_start() -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		return
	var start = overlay.patch_named(CrawlerRules.START_PATCH)
	if start != null:
		_start_dir = start.direction
	var spawn := _spawn_pad()
	if spawn != null:
		_start_origin = spawn.player_spawn_transform().origin
		return
	var pad := overlay.crawler_spawn_transform(1.35)
	if pad.origin.length_squared() > 1.0:
		_start_origin = pad.origin


func _fill_around_players() -> void:
	var planet := _planet()
	if planet == null:
		return
	var overlay := _overlay()
	var budget := SPAWN_PER_FRAME
	var batch: Array = []
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null or budget <= 0:
			continue
		if _player_is_safe(player, overlay):
			continue
		if _refill_blocked(player):
			continue
		var patch_id := _patch_id_of(player, overlay)
		var patch_name := _patch_name_of(player, overlay)
		var level := _level_for(patch_id, overlay)
		var here := _distance_from_start(player.global_position)
		var recipe := CrawlerRules.patch_recipe(patch_name, here)
		var live := _count_near(player.global_position, CrawlerRules.PACK_KEEP)
		var need := maxi(CrawlerRules.pack_limit(recipe.get("kinds", CrawlerRules.WILD_KINDS), level) - live, 0)
		var health_scale := float(recipe.get("health_scale", 1.0))
		for _step in need:
			if budget <= 0:
				break
			if not _spawn_home(
					planet, player, recipe, patch_name, patch_id, level,
					health_scale, true, batch):
				break
			budget -= 1
		budget = _fill_lead(
			planet, player, recipe, patch_name, patch_id, level,
			health_scale, budget, batch)
	if not batch.is_empty() and _has_listeners():
		_spawn_mob_batch_rpc.rpc(batch)


func _reap_far_and_idle() -> void:
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _mobs.get(id) as CrawlerMob
		if mob == null or not is_instance_valid(mob):
			gone.append(id)
			continue
		if _city_blocks(mob.global_position) \
				or CrawlerSafeBox.blocks_any(get_tree(), mob.global_position) \
				or PatchMonument.blocks_any(get_tree(), mob.global_position):
			gone.append(id)
			continue
		var distance := _nearest_player_distance(mob.global_position)
		if distance >= CrawlerRules.WILD_STREAM_OUT:
			gone.append(id)
			continue
		if CrawlerRules.should_despawn_idle(
				mob.ever_chased, mob.chase, mob.idle_seconds):
			gone.append(id)
	for id in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)


func _fill_lead(
		planet: Planet, player: Node3D, recipe: Dictionary, patch_name: String,
		patch_id: int, level: int, health_scale: float, budget: int, batch: Array
	) -> int:
	var velocity := _player_velocity(player)
	var speed := velocity.length()
	var want := CrawlerRules.spawn_lead_count(speed)
	if want <= 0 or budget <= 0:
		return budget
	var up := planet.up_at(player.global_position) if planet.has_method(&"up_at") \
		else Vector3.UP
	var travel := CrawlerRules.spawn_going(velocity, up)
	if travel.length_squared() < 0.0001:
		return budget
	var band := CrawlerRules.spawn_lead_range(speed)
	var have := _count_ahead(player.global_position, travel, up, band)
	var need := maxi(want - have, 0)
	for _step in need:
		if budget <= 0:
			break
		if not _spawn_home(
				planet, player, recipe, patch_name, patch_id, level,
				health_scale, false, batch):
			break
		budget -= 1
	return budget


func _spawn_home(
		planet: Planet, player: Node3D, recipe: Dictionary, patch_name: String,
		patch_id: int, level: int, health_scale: float, ring: bool, batch: Array
	) -> bool:
	_spawn_serial += 1
	var probe := _around_player(
		planet, player, "ranger", recipe, _spawn_serial, ring)
	if not probe.is_finite():
		return false
	var kind := _pick_kind(
		player.global_position, patch_name, _distance_from_start(probe),
		level, player, planet, ring)
	if kind.is_empty():
		return false
	var home := _around_player(
		planet, player, kind, recipe, _spawn_serial, ring)
	if not home.is_finite():
		return false
	var id := "cm%d" % _next_mob
	_next_mob += 1
	_make_mob(id, kind, _pose_at(home), level, false, patch_id, -1, health_scale)
	batch.append({
		"id": id,
		"kind": kind,
		"origin": home,
		"level": level,
		"city": patch_id,
		"slot": -1,
		"chase": false,
		"health_scale": health_scale,
	})
	return true


func _around_player(planet: Planet, player: Node3D, kind: String,
		_recipe: Dictionary, serial: int, ring := true) -> Vector3:
	if ring:
		return _ring_around_player(planet, player, kind, serial)
	return _ahead_of_player(planet, player, kind, serial)


func _ring_around_player(planet: Planet, player: Node3D, kind: String,
		serial: int) -> Vector3:
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	var band := CrawlerRules.spawn_ring_range()
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(player.get_instance_id()) * 811 + serial * 59) & 0x7fffffff)
	for attempt in SPAWN_TRIES:
		var yaw := float(serial) * CrawlerRules.START_RING_STEP \
			+ rng.randf_range(-0.14, 0.14) + float(attempt) * 0.37
		var reach := rng.randf_range(band.x, band.y)
		var guess := CrawlerRules.spawn_ring_point(at, up, yaw, reach)
		var local := planet.to_local(guess)
		if local.length_squared() < 0.0001:
			local = up
		var surface := planet.surface_position(local)
		var home := surface + planet.up_at(surface) * _lift_for(kind, rng)
		if _spawn_point_ok(home, player, planet, kind, true):
			return home
	return Vector3(NAN, NAN, NAN)


func _ahead_of_player(planet: Planet, player: Node3D, kind: String,
		serial: int) -> Vector3:
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	var velocity := _player_velocity(player)
	var travel := CrawlerRules.spawn_going(velocity, up)
	if travel.length_squared() < 0.0001:
		return Vector3(NAN, NAN, NAN)
	var band := CrawlerRules.spawn_lead_range(velocity.length())
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(player.get_instance_id()) * 811 + serial * 59) & 0x7fffffff)
	for attempt in SPAWN_TRIES:
		var yaw := rng.randf_range(-CrawlerRules.SPAWN_CONE, CrawlerRules.SPAWN_CONE)
		var reach := rng.randf_range(band.x, band.y)
		var guess := CrawlerRules.spawn_ahead_point(
			at, travel.rotated(up, yaw), up, reach)
		var local := planet.to_local(guess)
		if local.length_squared() < 0.0001:
			local = up
		var surface := planet.surface_position(local)
		var home := surface + planet.up_at(surface) * _lift_for(kind, rng)
		if _spawn_point_ok(home, player, planet, kind):
			return home
	return Vector3(NAN, NAN, NAN)


func _spawn_point_ok(at: Vector3, player: Node3D, planet: Planet,
		_kind := "", ring := false) -> bool:
	if not at.is_finite():
		return false
	if CrawlerSafeBox.blocks_any(get_tree(), at) \
			or PatchMonument.blocks_any(get_tree(), at) \
			or _city_blocks(at):
		return false
	if _kill_blocks(at):
		return false
	var up := Vector3.UP
	if planet != null and planet.has_method(&"up_at"):
		up = planet.up_at(player.global_position)
	if ring:
		return not CrawlerRules.spawn_too_close(
			at, player.global_position, Vector3.ZERO, up)
	return not CrawlerRules.spawn_blocked_by_player(
		at, player.global_position, _player_velocity(player), up, Vector3.ZERO)


func _lift_for(kind: String, rng: RandomNumberGenerator) -> float:
	if kind == "rift_hulk":
		return 3.4
	if kind == "rhino":
		return 1.9
	if kind == "rammer":
		return rng.randf_range(1.6, 9.0)
	return FLYER_LIFT + rng.randf_range(0.0, 16.0)


func _distance_from_start(at: Vector3) -> float:
	if _start_origin.length_squared() < 1.0:
		return -1.0
	return at.distance_to(_start_origin)


func _pick_kind(at: Vector3, patch_name: String, from_start: float,
		level: int, player: Node3D = null, planet: Planet = null,
		ring := true) -> String:
	var kinds: PackedStringArray = CrawlerRules.patch_recipe(
		patch_name, from_start).get("kinds", CrawlerRules.WILD_KINDS)
	var open: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		var used := _count_kind_near(at, CrawlerRules.PACK_KEEP, kind)
		var cap := CrawlerRules.kind_cap(kind, level)
		if not ring and player != null:
			var up := planet.up_at(player.global_position) \
				if planet != null and planet.has_method(&"up_at") else Vector3.UP
			var travel := CrawlerRules.spawn_going(_player_velocity(player), up)
			var band := CrawlerRules.spawn_lead_range(_player_velocity(player).length())
			used = _count_kind_ahead(
				player.global_position, travel, up, band, kind)
			cap = CrawlerRules.SPAWN_LEAD_KIND
		if used < cap:
			open.append(kind)
	if open.is_empty():
		return ""
	return open[posmod(_spawn_serial, open.size())]


func _count_ahead(at: Vector3, travel: Vector3, up: Vector3, band: Vector2) -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not is_instance_valid(mob):
			continue
		if _in_lead_band(mob.global_position, at, travel, up, band):
			count += 1
	return count


func _count_kind_ahead(at: Vector3, travel: Vector3, up: Vector3, band: Vector2,
		kind: String) -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not is_instance_valid(mob):
			continue
		if _kind_of(mob) != kind:
			continue
		if _in_lead_band(mob.global_position, at, travel, up, band):
			count += 1
	return count


func _in_lead_band(home: Vector3, at: Vector3, travel: Vector3, up: Vector3,
		band: Vector2) -> bool:
	var away := home.distance_to(at)
	if away < band.x or away > band.y:
		return false
	return CrawlerRules.spawn_in_travel_cone(home, at, travel, up)


func _count_kind_near(at: Vector3, reach: float, kind: String) -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not is_instance_valid(mob):
			continue
		if _kind_of(mob) != kind:
			continue
		if mob.global_position.distance_to(at) <= reach:
			count += 1
	return count


func _player_is_safe(player: Node3D, overlay: LandPatchOverlay) -> bool:
	if player.has_method(&"in_crawler_city") and bool(player.call(&"in_crawler_city")):
		return true
	if player.has_method(&"in_crawler_safe_zone") \
			and bool(player.call(&"in_crawler_safe_zone")):
		return true
	if CrawlerSafeBox.contains_any(player):
		return true
	if overlay != null and overlay.keeps_mobs_out(player.global_position):
		return true
	return CrawlerRules.safe_patch(_patch_name_of(player, overlay))


func _patch_id_of(player: Node3D, overlay: LandPatchOverlay) -> int:
	if overlay == null:
		return -1
	return overlay.patch_id_at(player.global_position)


func _patch_name_of(player: Node3D, overlay: LandPatchOverlay) -> String:
	if overlay == null:
		return ""
	return overlay.patch_name_at(player.global_position)


func _level_for(patch_id: int, overlay: LandPatchOverlay) -> int:
	var facing := _start_dir
	if overlay != null and patch_id >= 0 \
			and patch_id < overlay.partition.patches.size():
		facing = overlay.partition.patches[patch_id].direction
	return CrawlerRules.field_mob_level(_start_dir, facing)


func _count_near(at: Vector3, reach: float) -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not is_instance_valid(mob):
			continue
		if mob.global_position.distance_to(at) <= reach:
			count += 1
	return count


func _city_blocks(at: Vector3) -> bool:
	if CITY_RING.blocks_near_any(get_tree(), at):
		return true
	var overlay := _overlay()
	return overlay != null and overlay.keeps_mobs_out(at)


func _nearest_player_distance(at: Vector3) -> float:
	var best := INF
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		best = minf(best, player.global_position.distance_to(at))
	return best


func _players() -> Array:
	if not is_inside_tree():
		return []
	var found: Array = []
	for player_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := player_variant as Node3D
		if player == null:
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		found.append(player)
	return found


func _make_mob(id: String, kind: String, xform: Transform3D, level: int,
		should_chase: bool, owned_city := -1, slot := -1,
		health_scale := 1.0) -> CrawlerMob:
	var mob: CrawlerMob
	if kind == "rammer":
		mob = CrawlerRammer.new()
	elif kind == "rift_hulk":
		mob = RIFT_HULK.new()
	elif kind == "rhino":
		mob = RHINO.new()
	else:
		mob = CrawlerRanger.new()
	mob.configure(
		id, xform, level, should_chase, self, owned_city, slot, health_scale)
	mob.died.connect(_on_mob_died.bind(mob))
	add_child(mob)
	_mobs[id] = mob
	return mob


func _on_mob_died(mob: CrawlerMob) -> void:
	if mob == null or mob.dismissed:
		return
	_mobs.erase(mob.mob_id)
	if _is_host():
		_note_kill(mob.global_position)
		_award_kill(mob)
		if _has_listeners():
			_mob_death_burst_rpc.rpc(
				mob.combat_position(), mob._up(),
				maxf(mob.combat_radius() * 2.6, 2.4), mob.wild_kind())
			_despawn_mob_rpc.rpc(mob.mob_id)


func _note_kill(at: Vector3) -> void:
	if not at.is_finite():
		return
	var now := Time.get_ticks_msec()
	_kill_marks.append({
		"at": at,
		"until": now + int(CrawlerRules.KILL_COOLDOWN * 1000.0),
	})
	var refill := now + int(CrawlerRules.KILL_REFILL * 1000.0)
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		if player.global_position.distance_to(at) <= CrawlerRules.PACK_KEEP:
			_refill_until[player.get_instance_id()] = refill


func _prune_kills() -> void:
	var now := Time.get_ticks_msec()
	var kept: Array[Dictionary] = []
	for mark: Dictionary in _kill_marks:
		if now < int(mark.get("until", 0)):
			kept.append(mark)
	_kill_marks = kept
	var live: Dictionary = {}
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		var id := player.get_instance_id()
		var until := int(_refill_until.get(id, 0))
		if now < until:
			live[id] = until
	_refill_until = live


func _kill_blocks(at: Vector3) -> bool:
	_prune_kills()
	var now := Time.get_ticks_msec()
	for mark: Dictionary in _kill_marks:
		var kill_at: Vector3 = mark.get("at", Vector3.ZERO)
		var age := float(int(mark.get("until", now)) - now) / 1000.0
		age = CrawlerRules.KILL_COOLDOWN - age
		if CrawlerRules.spawn_blocked_by_kill(at, kill_at, age):
			return true
	return false


func _refill_blocked(player: Node3D) -> bool:
	if player == null:
		return true
	return Time.get_ticks_msec() < int(_refill_until.get(player.get_instance_id(), 0))


func _player_velocity(player: Node3D) -> Vector3:
	if player is CharacterBody3D:
		return (player as CharacterBody3D).velocity
	return Vector3.ZERO


func _award_kill(mob: CrawlerMob) -> void:
	if mob == null or not is_inside_tree():
		return
	var peer := mob.last_source_peer
	if peer <= 0:
		return
	for player_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := player_variant as OnlinePlayer
		if player == null or player.peer_id != peer:
			continue
		if player.has_method(&"award_crawler_kill"):
			player.call(
				&"award_crawler_kill",
				mob.threat_level,
				mob.wild_kind(),
				mob.combat_position())
		return


func _dismiss_mob(id: String) -> void:
	var mob := _mobs.get(id) as CrawlerMob
	_mobs.erase(id)
	if mob != null:
		mob.dismiss()


func publish_mob_state(mob: CrawlerMob) -> void:
	if not _is_host() or mob == null or not _has_listeners():
		return
	_mob_state_rpc.rpc(mob.mob_id, mob.global_transform, mob.velocity,
		mob.health(), mob.maximum_health(), mob.current_clip())


func publish_ranger_shot(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.16, hit_radius := 0.62) -> void:
	if _has_listeners():
		_ranger_shot_rpc.rpc(from, launch, damage, shot_speed, ball_radius, hit_radius)


func publish_rhino_meteor(at: Vector3, radius: float) -> void:
	_play_rhino_meteor(at, radius)
	if _has_listeners():
		_rhino_meteor_rpc.rpc(at, radius)


func _play_rhino_meteor(at: Vector3, radius: float) -> void:
	EnergyExplosion.burst(
		get_parent(), at, maxf(radius, 0.8), Color(1.0, 0.22, 0.10), 0.42)


func _kind_of(mob: CrawlerMob) -> String:
	if mob != null and mob.has_method(&"wild_kind"):
		return str(mob.call(&"wild_kind"))
	if mob is CrawlerRammer:
		return "rammer"
	if mob is CrawlerRhino:
		return "rhino"
	if mob is CrawlerRiftHulk:
		return "rift_hulk"
	return "ranger"


func _pose_at(at: Vector3) -> Transform3D:
	var up := at.normalized() if at.length_squared() > 0.01 else Vector3.UP
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	east = north.cross(up).normalized()
	return Transform3D(Basis(east, up, north), at)


func _overlay() -> LandPatchOverlay:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
		as LandPatchOverlay


func _spawn_pad() -> CrawlerSpawnPad:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(CrawlerSpawnPad.GROUP) \
		as CrawlerSpawnPad


func _planet() -> Planet:
	var world := get_parent() as GameWorld
	if world != null:
		return world.planet()
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"planet") as Planet


func _publish_siege() -> void:
	if _has_listeners():
		_apply_siege_rpc.rpc(_city_clears, _threat)


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _has_listeners() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.get_peers().is_empty() == false


@rpc("any_peer", "reliable")
func _request_siege_sync() -> void:
	if not _is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	_apply_siege_rpc.rpc_id(peer, _city_clears, _threat)
	var batch: Array = []
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null:
			continue
		batch.append({
			"id": mob.mob_id,
			"kind": _kind_of(mob),
			"origin": mob.global_position,
			"level": mob.threat_level,
			"city": mob.city_id,
			"slot": mob.garrison_slot,
			"chase": mob.chase,
			"health_scale": mob.patch_health_scale(),
		})
		if batch.size() >= SPAWN_PER_FRAME:
			_spawn_mob_batch_rpc.rpc_id(peer, batch)
			batch.clear()
	if not batch.is_empty():
		_spawn_mob_batch_rpc.rpc_id(peer, batch)


@rpc("authority", "reliable")
func _apply_siege_rpc(clears: int, threat: int) -> void:
	_city_clears = maxi(clears, 0)
	_threat = maxi(threat, 0)


@rpc("authority", "reliable")
func _spawn_mob_rpc(id: String, kind: String, xform: Transform3D, level: int,
		should_chase: bool, owned_city := -1, slot := -1) -> void:
	if _is_host() or _mobs.has(id):
		return
	_make_mob(id, kind, xform, level, should_chase, owned_city, slot)


@rpc("authority", "reliable")
func _spawn_mob_batch_rpc(batch: Array) -> void:
	if _is_host():
		return
	for row_variant: Variant in batch:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row := row_variant as Dictionary
		var id := str(row.get("id", ""))
		if id.is_empty() or _mobs.has(id):
			continue
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3:
			continue
		_make_mob(
			id,
			str(row.get("kind", "ranger")),
			_pose_at(origin),
			int(row.get("level", 1)),
			bool(row.get("chase", false)),
			int(row.get("city", -1)),
			int(row.get("slot", -1)),
			float(row.get("health_scale", 1.0))
		)


@rpc("authority", "reliable")
func _mob_death_burst_rpc(at: Vector3, up: Vector3, size: float, kind: String) -> void:
	if _is_host():
		return
	CrawlerBurst.death(get_parent(), at, up, size, kind)


@rpc("authority", "reliable")
func _despawn_mob_rpc(id: String) -> void:
	_dismiss_mob(id)


@rpc("authority", "unreliable")
func _mob_state_rpc(id: String, xform: Transform3D, along: Vector3, hp: float,
		maximum: float, clip := "") -> void:
	var mob := _mobs.get(id) as CrawlerMob
	if mob != null:
		mob.apply_network_state(xform, along, hp, maximum, clip)


@rpc("authority", "reliable")
func _ranger_shot_rpc(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.16, hit_radius := 0.62) -> void:
	if _is_host():
		return
	var ball := CrawlerRangerShot.new()
	ball.damage = damage
	ball.shot_speed = shot_speed
	ball.ball_radius = ball_radius
	ball.hit_radius = hit_radius
	var world := get_parent()
	if world == null or not ball.launch_anywhere(world, from, launch, null):
		ball.free()


@rpc("authority", "reliable")
func _rhino_meteor_rpc(at: Vector3, radius: float) -> void:
	if _is_host():
		return
	_play_rhino_meteor(at, radius)
