class_name CrawlerHorde
extends Node

## Host-authored field pack plus the one-shot castle goblin garrison.
## Wild homes sit in a ring around the player. When the player is moving
## fast, an extra pack is seeded farther ahead of travel. Ready homes are
## stamped on the surface ahead of time so a fast flight does not solve
## ten height-field guesses per mob in the same tick it instantiates them.
## Instantiation is dripped a couple of bodies per frame so speed does not
## hitch. They spawn far enough out to stay calm, then agro when the run
## reaches them. Player level and siege clears do not restat a pack already
## on the ground. They drop agro at range and vanish after they idle. A kill
## keeps that pad empty for a few seconds and the pack waits before filling.
## Goblins are preset at Stormwatch and never refill.

const GROUP := &"crawler_horde"
const SPAWN_PER_FRAME := 16
const SPAWN_TRIES := 3
const SEED_PER_TICK := 8
const PATCH_CACHE_SPAN := 48.0
const FLYER_LIFT := 22.0
const RIFT_HULK := preload("res://game/crawler/crawler_rift_hulk.gd")
const RHINO := preload("res://game/crawler/crawler_rhino.gd")
const GLOAM := preload("res://game/crawler/crawler_gloam.gd")
const VESPER := preload("res://game/crawler/crawler_vesper.gd")
const THRENODY := preload("res://game/crawler/crawler_threnody.gd")
const GRUK := preload("res://game/crawler/crawler_gruk.gd")
const NIX := preload("res://game/crawler/crawler_nix.gd")
const VEX := preload("res://game/crawler/crawler_vex.gd")
const VEX_MORTAR := preload("res://game/crawler/crawler_vex_mortar.gd")
const MobSense := preload("res://game/crawler/crawler_mob_sense.gd")

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
var _castle_seeded := false
var _ready_homes: Array[Dictionary] = []
var _build_queue: Array[Dictionary] = []
var _scan_at: PackedVector3Array = PackedVector3Array()
var _scan_kind: PackedStringArray = PackedStringArray()
var _patch_cache: Dictionary = {}


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


func queued_spawn_count() -> int:
	return _build_queue.size()


func spawn_test_mob(kind := "ranger", at := Vector3(0.0, 12.0, 0.0),
		should_chase := false, level := 1) -> CrawlerMob:
	var id := "cm%d" % _next_mob
	_next_mob += 1
	return _make_mob(id, kind, _pose_at(at), level, should_chase, -1, -1)


func garrison_live_count() -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob != null and mob.is_persistent():
			count += 1
	return count


func spawn_castle_garrison_at(at: Vector3, count := -1) -> int:
	if _castle_seeded:
		return 0
	_castle_seeded = true
	return _place_garrison(at, count)


func _ensure_castle_garrison() -> void:
	if _castle_seeded or CrawlerMeta._test_payload != null:
		return
	var site := PatchMonument.find_id(CrawlerProgress.QUEST_CASTLE)
	if site == null:
		return
	_castle_seeded = true
	_place_garrison(site.global_position)


func _place_garrison(at: Vector3, count := -1) -> int:
	if not at.is_finite():
		return 0
	var want := CrawlerRules.GOBLIN_GARRISON if count < 0 else maxi(count, 0)
	if want <= 0:
		return 0
	var planet := _planet()
	var overlay := _overlay()
	var patch_id := -1
	if overlay != null:
		patch_id = overlay.patch_id_named(CrawlerRules.CASTLE_PATCH)
	var level := _level_for(patch_id, overlay)
	var batch: Array = []
	var made := 0
	for index in want:
		var home := _garrison_home(at, index, planet)
		if not home.is_finite():
			continue
		var kind := CrawlerRules.goblin_garrison_kind(index)
		var id := "cg%d" % _next_mob
		_next_mob += 1
		var mob := _make_mob(id, kind, _pose_at(home), level, false, patch_id, index)
		if mob == null:
			continue
		mob.persistent = true
		mob.hang_origin = home
		made += 1
		batch.append({
			"id": id,
			"kind": kind,
			"origin": home,
			"level": level,
			"city": patch_id,
			"slot": index,
			"chase": false,
			"health_scale": 1.0,
		})
		if batch.size() >= SPAWN_PER_FRAME and _has_listeners():
			_spawn_mob_batch_rpc.rpc(batch)
			batch.clear()
	if not batch.is_empty() and _has_listeners():
		_spawn_mob_batch_rpc.rpc(batch)
	return made


func _garrison_home(at: Vector3, index: int, planet: Planet) -> Vector3:
	var up := at.normalized() if at.length_squared() > 0.01 else Vector3.UP
	if planet != null and planet.has_method(&"up_at"):
		up = planet.up_at(at)
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var yaw := CrawlerRules.GOBLIN_GOLDEN * float(index)
	var reach := CrawlerRules.goblin_garrison_reach(index)
	var guess := at + (east * cos(yaw) + north * sin(yaw)) * reach
	if planet == null:
		return guess + up * 1.05
	var local := planet.to_local(guess)
	if local.length_squared() < 0.0001:
		local = up
	var surface := planet.surface_position(local)
	return surface + planet.up_at(surface) * 1.05


func horde_snapshot() -> Dictionary:
	var mobs: Array = []
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not is_instance_valid(mob) or not mob.is_alive():
			continue
		mobs.append({
			"id": mob.mob_id,
			"kind": _kind_of(mob),
			"origin": mob.global_position,
			"transform": mob.global_transform,
			"level": mob.threat_level,
			"city": mob.city_id,
			"slot": mob.garrison_slot,
			"chase": mob.chase,
			"ever": mob.ever_chased,
			"health_scale": mob.patch_health_scale(),
			"health": mob.health(),
			"maximum": mob.maximum_health(),
			"hang": mob.hang_origin,
			"persistent": mob.is_persistent(),
		})
	return {
		"clears": _city_clears,
		"threat": _threat,
		"castle": _castle_seeded,
		"next": _next_mob,
		"mobs": mobs,
	}


func apply_horde_snapshot(wire: Dictionary) -> void:
	if wire.is_empty():
		return
	_city_clears = maxi(int(wire.get("clears", 0)), 0)
	_threat = maxi(int(wire.get("threat", 0)), 0)
	_castle_seeded = bool(wire.get("castle", false))
	_next_mob = maxi(int(wire.get("next", _next_mob)), 1)
	clear_wild()
	var mobs: Variant = wire.get("mobs", [])
	if not (mobs is Array):
		return
	for row_variant: Variant in mobs:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row := row_variant as Dictionary
		var id := str(row.get("id", ""))
		if id.is_empty() or _mobs.has(id):
			continue
		var xf := Transform3D.IDENTITY
		var xf_raw: Variant = row.get("transform", null)
		if xf_raw is Transform3D:
			xf = xf_raw
		if xf.origin.length_squared() < 0.01:
			var origin_raw: Variant = row.get("origin", Vector3.ZERO)
			if origin_raw is Vector3:
				xf = _pose_at(origin_raw)
		if xf.origin.length_squared() < 0.01:
			continue
		var mob := _make_mob(
			id,
			str(row.get("kind", "ranger")),
			xf,
			int(row.get("level", 1)),
			bool(row.get("chase", false)),
			int(row.get("city", -1)),
			int(row.get("slot", -1)),
			float(row.get("health_scale", 1.0)))
		if mob == null:
			continue
		mob.persistent = bool(row.get("persistent", mob.city_id >= 0))
		mob.ever_chased = bool(row.get("ever", mob.ever_chased))
		var hang_raw: Variant = row.get("hang", mob.hang_origin)
		if hang_raw is Vector3 and (hang_raw as Vector3).is_finite():
			mob.hang_origin = hang_raw
		var hp := float(row.get("health", mob.health()))
		var maximum := float(row.get("maximum", mob.maximum_health()))
		if is_finite(hp) or is_finite(maximum):
			mob.apply_network_state(
				mob.global_transform,
				Vector3.ZERO,
				hp if is_finite(hp) else mob.health(),
				maximum if is_finite(maximum) else mob.maximum_health())
		_bump_next_mob(id)
	_publish_siege()


func _bump_next_mob(id: String) -> void:
	if id.length() < 3:
		return
	if not (id.begins_with("cm") or id.begins_with("cg")):
		return
	_next_mob = maxi(_next_mob, int(id.substr(2)) + 1)


func clear_wild() -> void:
	if not _is_host():
		return
	_ready_homes.clear()
	_build_queue.clear()
	_scan_at.clear()
	_scan_kind.clear()
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		gone.append(str(id_variant))
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)


func _process(delta: float) -> void:
	if not CrawlerRules.active() or not _is_host():
		return
	if CrawlerRules.sandbox_no_mobs() or CrawlerRules.duel_active():
		if not _mobs.is_empty() or not _build_queue.is_empty():
			clear_wild()
		return
	if _start_origin.length_squared() < 1.0 or _start_dir.length_squared() < 0.0001:
		_remember_start()
	_ensure_castle_garrison()
	_drain_builds()
	_stream_left -= delta
	if _stream_left > 0.0:
		return
	_stream_left = 0.22
	_reap_far_and_idle()
	_prune_kills()
	_index_wild()
	_trim_ready_homes()
	_fill_around_players()


func _remember_start() -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		return
	var start = overlay.patch_named(CrawlerRules.START_PATCH)
	if start != null:
		var home := overlay.partition.territory_of(start.id)
		_start_dir = home.direction if home != null else start.direction
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
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		if _player_is_safe(player, overlay):
			continue
		var velocity := _player_velocity(player)
		var up := planet.up_at(player.global_position) if planet.has_method(&"up_at") \
			else Vector3.UP
		_seed_ready_homes(planet, player, up, velocity)
		if budget <= 0 or _refill_blocked(player):
			continue
		var patch := _patch_record(player, overlay)
		var patch_id := int(patch.get("id", -1))
		var patch_name := str(patch.get("name", ""))
		var level := _level_for(patch_id, overlay)
		var here := _distance_from_start(player.global_position)
		var recipe := CrawlerRules.patch_recipe(patch_name, here)
		var kinds := CrawlerRules.field_kinds(
			patch_name, here, player.global_position)
		var health_scale := float(recipe.get("health_scale", 1.0))
		var speed := velocity.length()
		if not CrawlerRules.uses_lead_pack(speed):
			var live := _count_near(player.global_position, CrawlerRules.PACK_KEEP)
			var need := maxi(CrawlerRules.pack_limit(kinds, level) - live, 0)
			for _step in need:
				if budget <= 0:
					break
				var made := _spawn_home(
						planet, player, recipe, patch_name, patch_id, level,
						health_scale, true)
				if made <= 0:
					break
				budget -= made
		budget = _fill_lead(
			planet, player, recipe, patch_name, patch_id, level,
			health_scale, budget)


func _reap_far_and_idle() -> void:
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _mobs.get(id) as CrawlerMob
		if mob == null or not is_instance_valid(mob):
			gone.append(id)
			continue
		if mob.is_persistent():
			continue
		if MobSense.keepout_blocks(self, mob.global_position):
			gone.append(id)
			continue
		if MobSense.monument_blocks(self, mob.global_position) \
				and not mob.chase and not mob.ever_chased:
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
		patch_id: int, level: int, health_scale: float, budget: int
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
	var band := CrawlerRules.spawn_stream_range(speed)
	var have := _count_ahead(player.global_position, travel, up, band)
	var need := maxi(want - have, 0)
	for _step in need:
		if budget <= 0:
			break
		var made := _spawn_home(
				planet, player, recipe, patch_name, patch_id, level,
				health_scale, false)
		if made <= 0:
			break
		budget -= made
	return budget


func _spawn_home(
		planet: Planet, player: Node3D, recipe: Dictionary, patch_name: String,
		patch_id: int, level: int, health_scale: float, ring: bool
	) -> int:
	# Near/far is how far the player has walked, not where the home sits.
	# Homes spawn 90m+ out, so a probe-distance check would pull Vesper
	# beams onto the start pad and crowd out the ranger lobs.
	var kind := _pick_kind(
		player.global_position, patch_name,
		_distance_from_start(player.global_position),
		level, player, planet, ring)
	if kind.is_empty():
		return 0
	var home := _take_ready_home(player, planet, ring)
	if home.is_finite():
		home += planet.up_at(home) * _lift_for(kind, _spawn_serial)
		if not _spawn_point_ok(home, player, planet, kind, ring):
			home = Vector3(NAN, NAN, NAN)
	if not home.is_finite():
		home = _stamp_around(planet, player, kind, ring)
	if not home.is_finite():
		return 0
	var made := _enqueue_wild(kind, home, level, patch_id, health_scale)
	if made <= 0:
		return 0
	if kind == "gloam":
		made += _spawn_gloam_flock(planet, home, level, patch_id, health_scale)
	return made


func _spawn_gloam_flock(planet: Planet, home: Vector3, level: int, patch_id: int,
		health_scale: float) -> int:
	var used := _count_kind_near(home, CrawlerRules.PACK_KEEP, "gloam")
	var cap := CrawlerRules.kind_cap("gloam", level)
	var mates := mini(CrawlerRules.GLOAM_FLOCK - 1, maxi(cap - used, 0))
	if mates <= 0:
		return 0
	var up := Vector3.UP
	if planet != null and planet.has_method(&"up_at"):
		up = planet.up_at(home)
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var made := 0
	for index in mates:
		var yaw := TAU * float(index) / float(mates) + float(_spawn_serial) * 0.21
		var reach := 4.2 + float(index) * 1.1
		var guess := home + (east * cos(yaw) + north * sin(yaw)) * reach
		var perch := guess
		if planet != null:
			var local := planet.to_local(guess)
			if local.length_squared() < 0.0001:
				local = up
			var surface := planet.surface_position(local)
			perch = surface + planet.up_at(surface) * 1.4
		made += _enqueue_wild(
			"gloam", perch, level, patch_id, health_scale, home)
	return made


func _seed_ready_homes(planet: Planet, player: Node3D, up: Vector3,
		velocity: Vector3) -> void:
	if planet == null or player == null:
		return
	var owner := player.get_instance_id()
	var have := 0
	for row: Dictionary in _ready_homes:
		if int(row.get("owner", 0)) == owner:
			have += 1
	var need := mini(
		SEED_PER_TICK,
		maxi(CrawlerRules.spawn_ready_count(velocity.length()) - have, 0)
	)
	if need <= 0:
		return
	var at := player.global_position
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	var travel := CrawlerRules.spawn_going(velocity, up)
	var band := CrawlerRules.spawn_ring_range()
	if travel.length_squared() > 0.0001:
		band = CrawlerRules.spawn_stream_range(velocity.length())
	for _step in need:
		_spawn_serial += 1
		var yaw := float(_spawn_serial) * CrawlerRules.START_RING_STEP
		var heading := Vector3.ZERO
		if travel.length_squared() > 0.0001:
			yaw = float(posmod(_spawn_serial, 7) - 3) * (CrawlerRules.SPAWN_CONE / 3.0)
			heading = travel
		var t := float(posmod(_spawn_serial * 17, 97)) / 96.0
		var reach := lerpf(band.x, band.y, t)
		var home := _project_surface(planet, at, up, heading, yaw, reach)
		if home.is_finite() and _home_clear(home):
			_ready_homes.append({"at": home, "owner": owner})


func _take_ready_home(player: Node3D, planet: Planet, ring: bool) -> Vector3:
	if player == null:
		return Vector3(NAN, NAN, NAN)
	var owner := player.get_instance_id()
	var at := player.global_position
	var up := Vector3.UP
	if planet != null and planet.has_method(&"up_at"):
		up = planet.up_at(at)
	var velocity := _player_velocity(player)
	var band := CrawlerRules.spawn_ring_range() if ring \
		else CrawlerRules.spawn_stream_range(velocity.length())
	var keep: Array[Dictionary] = []
	var found := Vector3(NAN, NAN, NAN)
	for row: Dictionary in _ready_homes:
		var home: Vector3 = row.get("at", Vector3.ZERO)
		if found.is_finite() or int(row.get("owner", 0)) != owner:
			keep.append(row)
			continue
		if not home.is_finite() or not _home_clear(home):
			continue
		var away := home.distance_to(at)
		if ring:
			if away < CrawlerRules.SPAWN_MIN * 0.85 or away > CrawlerRules.PACK_KEEP \
					or CrawlerRules.spawn_too_close(home, at, Vector3.ZERO, up):
				keep.append(row)
				continue
			found = home
			continue
		if away < band.x or away > band.y \
				or CrawlerRules.spawn_blocked_by_player(home, at, velocity, up):
			keep.append(row)
			continue
		found = home
	_ready_homes = keep
	return found


func _stamp_around(planet: Planet, player: Node3D, kind: String, ring: bool) -> Vector3:
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	var velocity := _player_velocity(player)
	var travel := CrawlerRules.spawn_going(velocity, up)
	if not ring and travel.length_squared() < 0.0001:
		return Vector3(NAN, NAN, NAN)
	var band := CrawlerRules.spawn_ring_range() if ring \
		else CrawlerRules.spawn_stream_range(velocity.length())
	for attempt in SPAWN_TRIES:
		_spawn_serial += 1
		var yaw := float(_spawn_serial) * CrawlerRules.START_RING_STEP \
			+ float(attempt) * 0.37
		var heading := Vector3.ZERO
		if not ring:
			yaw = float(posmod(_spawn_serial + attempt, 7) - 3) \
				* (CrawlerRules.SPAWN_CONE / 3.0)
			heading = travel
		var t := float(posmod(_spawn_serial * 13 + attempt * 7, 97)) / 96.0
		var reach := lerpf(band.x, band.y, t)
		var surface := _project_surface(planet, at, up, heading, yaw, reach)
		if not surface.is_finite() or not _home_clear(surface):
			continue
		var home := surface + planet.up_at(surface) * _lift_for(kind, _spawn_serial)
		if _spawn_point_ok(home, player, planet, kind, ring):
			return home
	return Vector3(NAN, NAN, NAN)


func _project_surface(planet: Planet, from: Vector3, up: Vector3, heading: Vector3,
		yaw: float, reach: float) -> Vector3:
	if planet == null:
		return Vector3(NAN, NAN, NAN)
	var guess := CrawlerRules.spawn_ring_point(from, up, yaw, reach)
	if heading.length_squared() > 0.0001:
		guess = CrawlerRules.spawn_ahead_point(
			from, heading.rotated(up, yaw), up, reach)
	var local := planet.to_local(guess)
	if local.length_squared() < 0.0001:
		local = up
	return planet.surface_position(local)


func _home_clear(at: Vector3) -> bool:
	if not at.is_finite():
		return false
	if MobSense.keepout_blocks(self, at) or MobSense.monument_blocks(self, at):
		return false
	return not _kill_blocks(at)


func _trim_ready_homes() -> void:
	var live: Dictionary = {}
	var travel_of: Dictionary = {}
	var up_of: Dictionary = {}
	var planet := _planet()
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		var owner := player.get_instance_id()
		live[owner] = player
		var up := Vector3.UP
		if planet != null and planet.has_method(&"up_at"):
			up = planet.up_at(player.global_position)
		up_of[owner] = up
		travel_of[owner] = CrawlerRules.spawn_going(_player_velocity(player), up)
	var keep: Array[Dictionary] = []
	var out2 := CrawlerRules.WILD_STREAM_OUT * CrawlerRules.WILD_STREAM_OUT
	var close2 := 70.0 * 70.0
	var behind2 := 110.0 * 110.0
	for row: Dictionary in _ready_homes:
		var owner := int(row.get("owner", 0))
		var player := live.get(owner) as Node3D
		if player == null:
			continue
		var home: Vector3 = row.get("at", Vector3.ZERO)
		if not home.is_finite():
			continue
		var at := player.global_position
		var away2 := home.distance_squared_to(at)
		if away2 > out2 or away2 < close2:
			continue
		var travel: Vector3 = travel_of.get(owner, Vector3.ZERO)
		if travel.length_squared() > 0.0001:
			var up: Vector3 = up_of.get(owner, Vector3.UP)
			var delta := home - at
			delta -= up * delta.dot(up)
			if delta.dot(travel) < 0.0 and away2 > behind2:
				continue
		keep.append(row)
	_ready_homes = keep
	var next_patch: Dictionary = {}
	for owner_variant: Variant in live.keys():
		var owner := int(owner_variant)
		if _patch_cache.has(owner):
			next_patch[owner] = _patch_cache[owner]
	_patch_cache = next_patch


func _spawn_point_ok(at: Vector3, player: Node3D, planet: Planet,
		_kind := "", ring := false) -> bool:
	if not at.is_finite():
		return false
	if MobSense.keepout_blocks(self, at) or MobSense.monument_blocks(self, at):
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


func _lift_for(kind: String, serial := 0) -> float:
	var t := float(posmod(serial * 19 + 5, 97)) / 96.0
	if CrawlerRules.is_goblin_kind(kind):
		return 1.05
	if kind == "rift_hulk":
		return 3.4
	if kind == "rhino":
		return 1.9
	if kind == "gloam":
		return 1.4
	if kind == "vesper":
		return lerpf(8.0, 14.0, t)
	if kind == "threnody":
		return lerpf(16.0, 24.0, t)
	if kind == "rammer":
		return lerpf(1.6, 9.0, t)
	return FLYER_LIFT + 16.0 * t


func _distance_from_start(at: Vector3) -> float:
	if _start_origin.length_squared() < 1.0:
		return -1.0
	return at.distance_to(_start_origin)


func _pick_kind(at: Vector3, patch_name: String, from_start: float,
		level: int, player: Node3D = null, planet: Planet = null,
		ring := true) -> String:
	var kinds := CrawlerRules.field_kinds(patch_name, from_start, at)
	var open: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		var used := _count_kind_near(at, CrawlerRules.PACK_KEEP, kind)
		var cap := CrawlerRules.kind_cap(kind, level)
		if not ring and player != null:
			var up := planet.up_at(player.global_position) \
				if planet != null and planet.has_method(&"up_at") else Vector3.UP
			var travel := CrawlerRules.spawn_going(_player_velocity(player), up)
			var band := CrawlerRules.spawn_stream_range(_player_velocity(player).length())
			used = _count_kind_ahead(
				player.global_position, travel, up, band, kind)
			cap = CrawlerRules.SPAWN_LEAD_KIND
		if used < cap:
			open.append(kind)
	if open.is_empty():
		return ""
	var total := 0
	for kind: String in open:
		total += maxi(CrawlerRules.spawn_weight(kind), 1)
	var pick := posmod(_spawn_serial * 17 + 3, total)
	for kind: String in open:
		pick -= maxi(CrawlerRules.spawn_weight(kind), 1)
		if pick < 0:
			return kind
	return open[0]


func _index_wild() -> void:
	_scan_at.clear()
	_scan_kind.clear()
	for mob_variant: Variant in _mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		_scan_at.append(mob.global_position)
		_scan_kind.append(_kind_of(mob))
	for row: Dictionary in _build_queue:
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3 or not origin.is_finite():
			continue
		_scan_at.append(origin)
		_scan_kind.append(str(row.get("kind", "ranger")))


func _count_ahead(at: Vector3, travel: Vector3, up: Vector3, band: Vector2) -> int:
	var count := 0
	for index in _scan_at.size():
		if _in_lead_band(_scan_at[index], at, travel, up, band):
			count += 1
	return count


func _count_kind_ahead(at: Vector3, travel: Vector3, up: Vector3, band: Vector2,
		kind: String) -> int:
	var count := 0
	for index in _scan_at.size():
		if _scan_kind[index] != kind:
			continue
		if _in_lead_band(_scan_at[index], at, travel, up, band):
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
	var reach2 := reach * reach
	for index in _scan_at.size():
		if _scan_kind[index] != kind:
			continue
		if _scan_at[index].distance_squared_to(at) <= reach2:
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


func _patch_record(player: Node3D, overlay: LandPatchOverlay) -> Dictionary:
	if player == null:
		return {"id": -1, "name": ""}
	var owner := player.get_instance_id()
	var at := player.global_position
	var cached: Dictionary = _patch_cache.get(owner, {})
	if not cached.is_empty():
		var was: Vector3 = cached.get("at", Vector3.ZERO)
		if at.distance_squared_to(was) <= PATCH_CACHE_SPAN * PATCH_CACHE_SPAN:
			return cached
	var patch_id := -1
	var patch_name := ""
	if overlay != null:
		patch_id = overlay.patch_id_at(at)
		if patch_id >= 0 and overlay.partition != null \
				and patch_id < overlay.partition.patches.size():
			patch_name = overlay.partition.recipe_name_of(patch_id)
			if patch_name.is_empty():
				patch_name = str(overlay.partition.patches[patch_id].name)
	var row := {"id": patch_id, "name": patch_name, "at": at}
	_patch_cache[owner] = row
	return row


func _patch_id_of(player: Node3D, overlay: LandPatchOverlay) -> int:
	return int(_patch_record(player, overlay).get("id", -1))


func _patch_name_of(player: Node3D, overlay: LandPatchOverlay) -> String:
	return str(_patch_record(player, overlay).get("name", ""))


func _level_for(patch_id: int, overlay: LandPatchOverlay) -> int:
	var facing := _start_dir
	if overlay != null and patch_id >= 0 \
			and patch_id < overlay.partition.patches.size():
		var home := overlay.partition.territory_of(patch_id)
		facing = home.direction if home != null \
				else overlay.partition.patches[patch_id].direction
	return CrawlerRules.field_mob_level(_start_dir, facing)


func _count_near(at: Vector3, reach: float) -> int:
	var count := 0
	var reach2 := reach * reach
	for index in _scan_at.size():
		if _scan_at[index].distance_squared_to(at) <= reach2:
			count += 1
	return count


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
	MobSense.begin_frame(get_tree())
	return MobSense.players()


func _enqueue_wild(kind: String, home: Vector3, level: int, patch_id: int,
		health_scale: float, hang := Vector3(NAN, NAN, NAN)) -> int:
	if not home.is_finite() or _build_queue.size() >= CrawlerRules.MOB_SPAWN_QUEUE:
		return 0
	var id := "cm%d" % _next_mob
	_next_mob += 1
	var row := {
		"id": id,
		"kind": kind,
		"origin": home,
		"level": level,
		"city": patch_id,
		"slot": -1,
		"chase": false,
		"health_scale": health_scale,
	}
	if hang.is_finite():
		row["hang"] = hang
	_build_queue.append(row)
	_scan_at.append(home)
	_scan_kind.append(kind)
	return 1


func _drain_builds() -> void:
	if _build_queue.is_empty():
		return
	var batch: Array = []
	var left := CrawlerRules.MOB_SPAWN_BUILD
	while left > 0 and not _build_queue.is_empty():
		var row: Dictionary = _build_queue.pop_front()
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3 or not origin.is_finite():
			continue
		var mob := _make_mob(
			str(row.get("id", "")),
			str(row.get("kind", "ranger")),
			_pose_at(origin),
			int(row.get("level", 1)),
			bool(row.get("chase", false)),
			int(row.get("city", -1)),
			int(row.get("slot", -1)),
			float(row.get("health_scale", 1.0)))
		var hang: Variant = row.get("hang", Vector3(NAN, NAN, NAN))
		if mob != null and hang is Vector3 and (hang as Vector3).is_finite():
			mob.hang_origin = hang
		batch.append(row)
		left -= 1
	if not batch.is_empty() and _has_listeners():
		_spawn_mob_batch_rpc.rpc(batch)


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
	elif kind == "gloam":
		mob = GLOAM.new()
	elif kind == "vesper":
		mob = VESPER.new()
	elif kind == "threnody":
		mob = THRENODY.new()
	elif kind == "gruk":
		mob = GRUK.new()
	elif kind == "nix":
		mob = NIX.new()
	elif kind == "vex":
		mob = VEX.new()
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
		if not mob.is_persistent():
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
	MobSense.begin_frame(get_tree())
	for player_node: Node3D in MobSense.players():
		var player := player_node as OnlinePlayer
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


func publish_vex_mortar(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.42, hit_radius := 1.15) -> void:
	if _has_listeners():
		_vex_mortar_rpc.rpc(from, launch, damage, shot_speed, ball_radius, hit_radius)


func publish_rhino_meteor(at: Vector3, radius: float) -> void:
	_play_rhino_meteor(at, radius)
	if _has_listeners():
		_rhino_meteor_rpc.rpc(at, radius)


func _play_rhino_meteor(at: Vector3, radius: float) -> void:
	EnergyExplosion.burst(
		get_parent(), at, maxf(radius, 0.8), Color(1.0, 0.22, 0.10), 0.42)


func _kind_of(mob: CrawlerMob) -> String:
	if not is_instance_valid(mob):
		return "ranger"
	if mob.has_method(&"wild_kind"):
		return str(mob.call(&"wild_kind"))
	if mob is CrawlerRammer:
		return "rammer"
	if mob is CrawlerRhino:
		return "rhino"
	if mob is CrawlerRiftHulk:
		return "rift_hulk"
	if mob is CrawlerGruk:
		return "gruk"
	if mob is CrawlerNix:
		return "nix"
	if mob is CrawlerVex:
		return "vex"
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
func _vex_mortar_rpc(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.42, hit_radius := 1.15) -> void:
	if _is_host():
		return
	var ball := VEX_MORTAR.new()
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
