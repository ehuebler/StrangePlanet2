class_name CrawlerHorde
extends Node

## Host-authored field pack plus the one-shot castle goblin garrison.
## Field tiles currently keep two of each Glorb 150 m out, inbound and
## deagroed, until a body reaches 50 m. Older ring packs stay behind
## CrawlerRules.glorb_field for tests. Goblins never spawn on the player
## rings.
## Goblins preseed inside Stormwatch and wake together when a player
## nears the keep. They never spawn on the player ring.
## Entering a city wipes the whole field while nobody is still fighting
## outside. Coop keeps the pack around a partner who is still in the
## wild. Offices still clear a 100 m circle. The teleporter holds the
## field until a player steps off, then it is just scenery.

const GROUP := &"crawler_horde"
const TRAINING := preload("res://game/crawler/crawler_training.gd")

static func instance(tree: SceneTree = null) -> CrawlerHorde:
	var host := tree if tree != null else Engine.get_main_loop() as SceneTree
	if host == null:
		return null
	return host.get_first_node_in_group(GROUP) as CrawlerHorde


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
const KESTREL := preload("res://game/crawler/crawler_kestrel.gd")
const BASTION := preload("res://game/crawler/crawler_bastion.gd")
const BASTION_SHELL := preload("res://game/crawler/crawler_bastion_shell.gd")
const WEAVER := preload("res://game/crawler/crawler_weaver.gd")
const SCOUT := preload("res://game/crawler/crawler_scout.gd")
const GRAY := preload("res://game/crawler/crawler_gray.gd")
const TANGLEMAW := preload("res://game/crawler/crawler_tanglemaw.gd")
const GLORB_JELLYFISH := preload("res://game/crawler/crawler_glorb_jellyfish.gd")
const GLORB_RHINO := preload("res://game/crawler/crawler_glorb_rhino.gd")
const GLORB_EYEBALL := preload("res://game/crawler/crawler_glorb_eyeball.gd")
const GLORB_PUNCHING := preload("res://game/crawler/crawler_glorb_punching.gd")
const GLORB_ONE_ARMED := preload("res://game/crawler/crawler_glorb_one_armed.gd")
const GLORB_SPIDER := preload("res://game/crawler/crawler_glorb_spider.gd")
const GLORB_ANGEL := preload("res://game/crawler/crawler_glorb_angel.gd")
const GRAY_SHOT := preload("res://game/crawler/crawler_gray_shot.gd")
const ROBOT_LASER := preload("res://game/crawler/crawler_robot_laser.gd")
const MobSense := preload("res://game/crawler/crawler_mob_sense.gd")
const CASTLE_GARRISON := preload("res://game/crawler/crawler_castle_garrison.gd")
const INTERIOR_HOMES := preload("res://game/crawler/crawler_interior_homes.gd")

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
var _garrison_queue: Array[Dictionary] = []
var _scan_at: PackedVector3Array = PackedVector3Array()
var _scan_kind: PackedStringArray = PackedStringArray()
var _patch_cache: Dictionary = {}
var _office_patch: Dictionary = {}
var _armed: Dictionary = {}
var _seen_patch: Dictionary = {}
var _pack_heading: Dictionary = {}
var _fill_pack_name := ""
var _reap_cursor := 0
var _glorb_menu_serial := 0
var _overlay_held: LandPatchOverlay


func _held_mob(id: Variant) -> CrawlerMob:
	var held: Variant = _mobs.get(id)
	if not is_instance_valid(held):
		return null
	return held as CrawlerMob


func _as_mob(held: Variant) -> CrawlerMob:
	if not is_instance_valid(held):
		return null
	return held as CrawlerMob


func _ready() -> void:
	name = "CrawlerHorde"
	add_to_group(GROUP)
	process_physics_priority = -20
	set_process(true)
	set_physics_process(true)
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


func is_patch_armed(patch_id: int) -> bool:
	return bool(_armed.get(patch_id, false))


func armed_patch_count() -> int:
	return _armed.size()


func fill_test_patch(patch_id: int, homes: Array, kind := "ranger",
		level := 1) -> int:
	if patch_id < 0 or is_patch_armed(patch_id):
		return 0
	var made := 0
	for home_variant: Variant in homes:
		if typeof(home_variant) != TYPE_VECTOR3:
			continue
		var home := home_variant as Vector3
		made += _enqueue_wild(kind, home, level, patch_id, 1.0)
	_armed[patch_id] = true
	return made


func spawn_test_mob(kind := "ranger", at := Vector3(0.0, 12.0, 0.0),
		should_chase := false, level := 1) -> CrawlerMob:
	var id := "cm%d" % _next_mob
	_next_mob += 1
	return _make_mob(id, kind, _pose_at(at), level, should_chase, -1, -1)


func spawn_glorb_ahead(player: Node3D, kind: String, agro: bool) -> CrawlerMob:
	if player == null or not CrawlerRules.is_glorb_kind(kind):
		return null
	var at := glorb_ahead_point(player, kind, agro, _glorb_menu_serial)
	_glorb_menu_serial += 1
	if not at.is_finite():
		return null
	var mob := spawn_test_mob(kind, at, agro, 1)
	if mob == null:
		return null
	var inbound := Vector3.ZERO
	if not agro:
		var up := _up_at(at)
		inbound = player.global_position - at
		inbound -= up * inbound.dot(up)
		if inbound.length_squared() > 0.0001:
			inbound = inbound.normalized()
			mob.set_inbound(inbound)
	if _has_listeners():
		_spawn_mob_batch_rpc.rpc([{
			"id": mob.mob_id,
			"kind": kind,
			"origin": mob.global_position,
			"level": mob.threat_level,
			"city": -1,
			"slot": -1,
			"chase": agro,
			"health_scale": 1.0,
			"inbound": inbound,
		}])
	return mob


func glorb_ahead_point(player: Node3D, kind: String, agro: bool,
		serial := 0) -> Vector3:
	if player == null:
		return Vector3(NAN, NAN, NAN)
	var from := player.global_position
	var planet := _planet()
	var up := _up_at(from)
	var ahead := _look_ahead(player, up)
	var right := up.cross(ahead)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var reach := CrawlerRules.glorb_menu_range(agro)
	var side := float(serial) * 2.4
	var guess := from + ahead * reach + right * side
	if planet != null and planet.has_method(&"mesh_position") \
			and planet.has_method(&"to_local"):
		var local: Vector3 = planet.to_local(guess)
		if local.length_squared() > 0.0001:
			var surface: Vector3 = planet.mesh_position(local)
			if surface.is_finite():
				guess = surface
				if planet.has_method(&"up_at"):
					up = planet.up_at(guess)
					if up.length_squared() < 0.0001:
						up = _up_at(guess)
	return guess + up * _lift_for(kind, serial)


func spawn_training_field(centre: Transform3D, level := 1) -> int:
	clear_training()
	var kinds := TRAINING.kinds()
	var count := kinds.size()
	var batch: Array = []
	var made := 0
	for index in count:
		var at := TRAINING.grid_point(centre, index, count)
		if not at.is_finite():
			continue
		var pose := _pose_at(at)
		var id := "ct%d" % _next_mob
		_next_mob += 1
		var mob := _make_mob(id, kinds[index], pose, level, false, -1, -1)
		if mob == null:
			continue
		mob.become_training(pose)
		made += 1
		batch.append({
			"id": id,
			"kind": kinds[index],
			"origin": pose.origin,
			"level": level,
			"city": -1,
			"slot": -1,
			"chase": false,
			"health_scale": 1.0,
			"training": true,
		})
		if batch.size() >= SPAWN_PER_FRAME and _has_listeners():
			_spawn_mob_batch_rpc.rpc(batch)
			batch.clear()
	if not batch.is_empty() and _has_listeners():
		_spawn_mob_batch_rpc.rpc(batch)
	return made


func set_training_level(level: int) -> int:
	var next := TRAINING.clamp_level(level)
	var changed := 0
	for mob_variant: Variant in _mobs.values():
		var mob := _as_mob(mob_variant)
		if mob == null or not is_instance_valid(mob) or not mob.is_training():
			continue
		mob.set_threat_level(next)
		mob.refill_health()
		changed += 1
		publish_mob_state(mob)
	return changed


func clear_training() -> void:
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var mob := _held_mob(id_variant)
		if mob != null and mob.is_training():
			gone.append(str(id_variant))
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)


func training_count() -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := _as_mob(mob_variant)
		if mob != null and is_instance_valid(mob) and mob.is_training():
			count += 1
	return count


func training_mobs() -> Array[CrawlerMob]:
	var out: Array[CrawlerMob] = []
	for mob_variant: Variant in _mobs.values():
		var mob := _as_mob(mob_variant)
		if mob != null and is_instance_valid(mob) and mob.is_training():
			out.append(mob)
	return out


func spawn_drop_mob(kind: String, at: Vector3, level := 1) -> CrawlerMob:
	var id := "cm%d" % _next_mob
	_next_mob += 1
	var xform := _pose_at(at)
	var mob := _make_mob(id, kind, xform, level, true, -1, -1)
	if mob != null and mob.has_method(&"begin_drop"):
		mob.call(&"begin_drop")
	if _has_listeners():
		_spawn_drop_rpc.rpc(id, kind, xform, level)
	return mob


func garrison_live_count() -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		if not is_instance_valid(mob_variant):
			continue
		var mob := _as_mob(mob_variant)
		if mob != null and mob.is_persistent():
			count += 1
	return count


func spawn_castle_garrison_at(at: Vector3, count := -1) -> int:
	if _castle_seeded:
		return 0
	_castle_seeded = true
	return _place_garrison(at, count)


func queue_castle_homes(homes: PackedVector3Array) -> int:
	if homes.is_empty():
		return 0
	if _castle_seeded and not CrawlerRun.active() \
			and (garrison_live_count() > 0 or _queued_garrison_count() > 0):
		return 0
	var made := _enqueue_garrison_homes(homes)
	if made > 0:
		_castle_seeded = true
	return made


func queue_castle_garrison(site: Node3D = null, count := -1) -> int:
	if site == null:
		var sites := _castle_sites()
		site = sites[0] if not sites.is_empty() else null
	if site == null:
		return 0
	var homes: PackedVector3Array = CASTLE_GARRISON.homes_for(site)
	if homes.is_empty():
		return 0
	var want := homes.size() if CrawlerRun.active() else CrawlerRules.GOBLIN_GARRISON
	if count >= 0:
		want = maxi(count, 0)
	return queue_castle_homes(INTERIOR_HOMES.fit(homes, want))


func _ensure_castle_garrison() -> void:
	# Adobe castle sites do not spawn a garrison while the new mass settles.
	return


func _castle_sites() -> Array[PatchMonument]:
	var found: Array[PatchMonument] = []
	if not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(PatchMonument.KEEP_GROUP):
		var site := node_variant as PatchMonument
		if site != null and CrawlerRules.is_castle_id(site.monument_id):
			found.append(site)
	if found.is_empty():
		var authored := PatchMonument.find_id(CrawlerProgress.QUEST_CASTLE)
		if authored != null:
			found.append(authored)
	return found


func _player_near_castle(site: Node3D) -> bool:
	if site == null:
		return false
	var reach := CrawlerRules.GOBLIN_WAKE_RANGE
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player != null and player.global_position.distance_to(site.global_position) <= reach:
			return true
	return false


func _place_garrison(at: Vector3, count := -1) -> int:
	if not at.is_finite():
		return 0
	var homes := _homes_for_place(at, count)
	if homes.is_empty():
		return 0
	var overlay := _overlay()
	var patch_id := -1
	if overlay != null:
		patch_id = overlay.patch_id_named(CrawlerRules.CASTLE_PATCH)
	var level := _level_for(patch_id, overlay)
	var batch: Array = []
	var made := 0
	for index in homes.size():
		var home := homes[index]
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


func _queue_garrison(at: Vector3, count := -1) -> int:
	return queue_castle_homes(_homes_for_place(at, count))


func _homes_for_place(at: Vector3, count := -1) -> PackedVector3Array:
	var want := CrawlerRules.GOBLIN_GARRISON if count < 0 else maxi(count, 0)
	if want <= 0 or not at.is_finite():
		return PackedVector3Array()
	var site := PatchMonument.find_id(CrawlerProgress.QUEST_CASTLE)
	if site != null and at.distance_to(site.global_position) <= 24.0:
		var harvested: PackedVector3Array = CASTLE_GARRISON.homes_for(site)
		if not harvested.is_empty():
			return INTERIOR_HOMES.fit(harvested, want)
	return _ring_homes(at, want)


func _ring_homes(at: Vector3, want: int) -> PackedVector3Array:
	var homes := PackedVector3Array()
	var planet := _planet()
	for index in maxi(want, 0):
		var home := _garrison_home(at, index, planet)
		if home.is_finite():
			homes.append(home)
	return homes


func _enqueue_garrison_homes(homes: PackedVector3Array) -> int:
	var overlay := _overlay()
	var patch_id := -1
	if overlay != null:
		patch_id = overlay.patch_id_named(CrawlerRules.CASTLE_PATCH)
	var level := _level_for(patch_id, overlay)
	var made := 0
	for index in homes.size():
		var home := homes[index]
		if not home.is_finite():
			continue
		var kind := CrawlerRules.goblin_garrison_kind(index)
		var id := "cg%d" % _next_mob
		_next_mob += 1
		_garrison_queue.append({
			"id": id,
			"kind": kind,
			"origin": home,
			"level": level,
			"city": patch_id,
			"slot": index,
			"chase": false,
			"health_scale": 1.0,
			"persistent": true,
			"hang": home,
		})
		made += 1
	return made


func _queued_garrison_count() -> int:
	var count := _garrison_queue.size()
	for row: Dictionary in _build_queue:
		if bool(row.get("persistent", false)):
			count += 1
	return count


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
	var surface := planet.mesh_position(local)
	return surface + planet.up_at(surface) * 1.05


func horde_snapshot() -> Dictionary:
	var mobs: Array = []
	for mob_variant: Variant in _mobs.values():
		var mob := _as_mob(mob_variant)
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
			"training": mob.is_training(),
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
		if bool(row.get("training", false)):
			mob.become_training(mob.global_transform)
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
	if not (id.begins_with("cm") or id.begins_with("cg") or id.begins_with("ct")):
		return
	_next_mob = maxi(_next_mob, int(id.substr(2)) + 1)


func clear_wild() -> void:
	if not _is_host():
		return
	_ready_homes.clear()
	_build_queue.clear()
	_garrison_queue.clear()
	_scan_at.clear()
	_scan_kind.clear()
	_armed.clear()
	_seen_patch.clear()
	_office_patch.clear()
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
		if not _mobs.is_empty() or not _build_queue.is_empty() \
				or not _garrison_queue.is_empty():
			clear_wild()
		return
	if CrawlerRules.training_active():
		return
	if _start_origin.length_squared() < 1.0 or _start_dir.length_squared() < 0.0001:
		_remember_start()
	_ensure_castle_garrison()
	_drain_builds()
	_stream_left -= delta
	if _stream_left > 0.0:
		return
	_stream_left = 0.22
	_ensure_robot_site()
	_clear_castle_wilds()
	_clear_site_patch_mobs()
	_clear_off_combo_wilds()
	_reap_far_and_idle()
	_prune_kills()
	_index_wild()
	_trim_ready_homes()
	if not _arrival_holds():
		_fill_around_players()
		_watch_field_rings()


func _physics_process(delta: float) -> void:
	if not CrawlerRules.active() or not _is_host():
		return
	if CrawlerRules.sandbox_no_mobs() or CrawlerRules.duel_active() \
			or CrawlerRules.training_active():
		return
	MobSense.begin_frame(get_tree())
	MobSense.direct_horde(delta)


func _remember_start() -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		return
	var start_id := overlay.crawler_start_patch_id()
	if start_id >= 0 and start_id < overlay.partition.patches.size():
		var start: LandPartition.Patch = overlay.partition.patches[start_id]
		var home := overlay.partition.territory_of(start.id)
		_start_dir = home.direction if home != null else start.direction
		var planet := _planet()
		if planet != null and not _arrival_holds():
			_arm_from_patch(planet, overlay, start_id, null)
	var spawn := _spawn_pad()
	if spawn != null:
		_start_origin = spawn.player_spawn_transform().origin
		return
	var pad := overlay.crawler_spawn_transform(1.35)
	if pad.origin.length_squared() > 1.0:
		_start_origin = pad.origin


func _fill_around_players() -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		return
	var planet := _planet()
	if planet == null:
		return
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		if _player_is_safe(player, overlay) or _refill_blocked(player):
			continue
		var patch_id := overlay.patch_id_at(player.global_position)
		var owner := player.get_instance_id()
		if int(_seen_patch.get(owner, -2)) == patch_id:
			continue
		if patch_id < 0:
			_seen_patch[owner] = patch_id
			continue
		_arm_from_patch(planet, overlay, patch_id, player)
		if _group_armed(overlay, patch_id):
			_seen_patch[owner] = patch_id


func _fill_player_rings() -> void:
	_watch_field_rings()


func _fill_bastion_grid() -> void:
	_watch_field_rings()


func _fill_bastions() -> void:
	pass


func _fill_combo_mass(planet: Planet, player: Node3D, patch_name: String,
		patch_id: int, level: int, health_scale: float) -> void:
	if CrawlerRules.glorb_field:
		_fill_glorb_roster(planet, player, patch_id, level, health_scale)
		return
	_fill_field_rings(planet, player, patch_name, patch_id, level, health_scale)


func _watch_field_rings() -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		return
	var planet := _planet()
	if planet == null:
		return
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		if _player_is_safe(player, overlay) or _refill_blocked(player):
			continue
		if CrawlerRules.in_castle_keep(player.global_position):
			continue
		var record := _patch_record(player, overlay)
		var patch_name := str(record.get("name", ""))
		var patch_id := int(record.get("id", -1))
		if not CrawlerRules.glorb_field and CrawlerRules.castle_grounds(patch_name):
			continue
		var here := _distance_from_start(player.global_position)
		var level := _level_for(patch_id, overlay)
		var health_scale := float(
			CrawlerRules.patch_recipe(patch_name, here).get("health_scale", 1.0))
		if CrawlerRules.glorb_field:
			_fill_glorb_roster(planet, player, patch_id, level, health_scale)
			continue
		_trim_ring_overflow(player)
		_fill_field_rings(planet, player, patch_name, patch_id, level, health_scale)


func _fill_glorb_roster(planet: Planet, player: Node3D, patch_id: int,
		level: int, health_scale: float) -> void:
	if planet == null or player == null:
		return
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	var slot := 0
	for kind: String in CrawlerRules.glorb_roster_kinds():
		var each := CrawlerRules.glorb_each_for(kind)
		var have := _count_kind_all(kind)
		for copy in each:
			if copy < have:
				slot += 1
				continue
			if _build_queue.size() >= CrawlerRules.MOB_SPAWN_QUEUE:
				return
			var home := _stamp_glorb(planet, player, kind, slot)
			if not home.is_finite():
				slot += 1
				continue
			var inbound := at - home
			inbound -= up * inbound.dot(up)
			if inbound.length_squared() < 0.0001:
				inbound = -_radial_heading(up, slot)
			_enqueue_glorb(
				kind, home, level, patch_id, health_scale, inbound.normalized())
			slot += 1


func _stamp_glorb(planet: Planet, player: Node3D, kind: String,
		index: int) -> Vector3:
	if planet == null or player == null:
		return Vector3(NAN, NAN, NAN)
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	var circle := CrawlerRules.glorb_circle_slots()
	var base_yaw := float(index) * TAU / float(circle)
	for attempt in 8:
		var yaw := base_yaw + float(attempt) * 0.31
		var surface := _project_surface(
			planet, at, up, Vector3.ZERO, yaw, CrawlerRules.GLORB_SPAWN)
		if not surface.is_finite() or not _home_clear(surface, kind):
			continue
		var home := surface + planet.up_at(surface) * _lift_for(kind, index)
		if home.is_finite():
			return home
	return Vector3(NAN, NAN, NAN)


func _radial_heading(up: Vector3, index: int) -> Vector3:
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var circle := CrawlerRules.glorb_circle_slots()
	var yaw := float(index) * TAU / float(circle)
	return (east * cos(yaw) + north * sin(yaw)).normalized()


func _enqueue_glorb(kind: String, home: Vector3, level: int, patch_id: int,
		health_scale: float, inbound: Vector3) -> int:
	if not home.is_finite() or _build_queue.size() >= CrawlerRules.MOB_SPAWN_QUEUE:
		return 0
	if CrawlerRules.in_castle_keep(home):
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
		"inbound": inbound,
	}
	_build_queue.append(row)
	_scan_at.append(home)
	_scan_kind.append(kind)
	return 1


func _fill_field_rings(planet: Planet, player: Node3D, patch_name: String,
		patch_id: int, level: int, health_scale: float) -> void:
	if planet == null or player == null:
		return
	var pack := CrawlerRules.field_kinds(
		patch_name, _distance_from_start(player.global_position),
		player.global_position)
	if pack.is_empty():
		return
	_fill_pack_name = patch_name
	var counts := _ring_counts(player.global_position)
	var hunted := _player_is_hunted(player)
	var budget := CrawlerHunt.SPAWN_TICK if hunted \
		else CrawlerRules.FIELD_RING_SPAWN_TICK
	for ring in [
		CrawlerRules.FIELD_RING_CLOSE,
		CrawlerRules.FIELD_RING_MID,
		CrawlerRules.FIELD_RING_FAR
	]:
		if budget <= 0:
			break
		var have := int(counts[ring])
		var floor_n := CrawlerRules.field_ring_min(ring)
		var fill := CrawlerRules.field_ring_min(ring) if hunted \
			else CrawlerRules.field_ring_fill(ring)
		if have >= fill:
			continue
		var want := 2 if have < floor_n else 1
		want = mini(want, mini(fill - have, budget))
		var kinds := CrawlerRules.pack_kinds_for_ring(ring, pack)
		if kinds.is_empty():
			continue
		budget -= _spawn_ring_homes(
			planet, player, ring, kinds, want, level, patch_id, health_scale)
	_fill_pack_name = ""


func _spawn_ring_homes(planet: Planet, player: Node3D, ring: int,
		kinds: PackedStringArray, want: int, level: int, patch_id: int,
		health_scale: float) -> int:
	var made := 0
	var band := CrawlerRules.field_ring_band(ring)
	for _step in want:
		if _build_queue.size() >= CrawlerRules.MOB_SPAWN_QUEUE:
			break
		var kind := _pick_ring_kind(kinds, level, player.global_position)
		if kind.is_empty():
			break
		var home := _stamp_pack(
			planet, player, kind, Vector3.ZERO, band.x, band.y)
		if not home.is_finite():
			_spawn_serial += 1
			continue
		var chase_flag := 1 if CrawlerRules.field_ring_spawn_agro(
			ring, kind, _spawn_serial) else 0
		if _enqueue_wild(
				kind, home, level, patch_id, health_scale,
				Vector3(NAN, NAN, NAN), chase_flag) <= 0:
			break
		made += 1
		var flock := CrawlerRules.field_ring_flock(kind)
		if flock > 1:
			_spawn_kind_flock(
				planet, home, kind, level, patch_id, health_scale, flock,
				chase_flag)
		_spawn_serial += 1
	return made


func _pick_ring_kind(kinds: PackedStringArray, level: int, at: Vector3) -> String:
	var open: PackedStringArray = PackedStringArray()
	var reach := CrawlerRules.field_ring_out()
	for kind: String in kinds:
		if _kind_blocked(kind):
			continue
		if _count_kind_near(at, reach, kind) >= CrawlerRules.kind_cap(kind, level):
			continue
		open.append(kind)
	if open.is_empty():
		return ""
	var total := 0
	for kind: String in open:
		total += maxi(CrawlerRules.spawn_weight(kind), 1)
	var pick := posmod(_spawn_serial * 17 + 3, maxi(total, 1))
	for kind: String in open:
		pick -= maxi(CrawlerRules.spawn_weight(kind), 1)
		if pick < 0:
			return kind
	return open[0]


func _ring_counts(at: Vector3) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	for id_variant: Variant in _mobs.keys():
		var mob := _held_mob(id_variant)
		if mob == null or mob.is_persistent():
			continue
		var ring := CrawlerRules.field_ring_of(mob.global_position.distance_to(at))
		if ring >= 0 and ring <= 2:
			counts[ring] += 1
	for row: Dictionary in _build_queue:
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3 or not origin.is_finite():
			continue
		var ring := CrawlerRules.field_ring_of(origin.distance_to(at))
		if ring >= 0 and ring <= 2:
			counts[ring] += 1
	return counts


func _trim_ring_overflow(_player: Node3D) -> void:
	# Rings only place new homes. Bodies that walk out of the band, or that
	# stay on a tile the player just left, keep living until stream-out.
	pass


func _spawn_kind_flock(planet: Planet, home: Vector3, kind: String, level: int,
		patch_id: int, health_scale: float, flock: int,
		chase_override := -1) -> void:
	if kind == "gloam":
		_spawn_gloam_flock(
			planet, home, level, patch_id, health_scale, flock, chase_override)
	elif kind == "tanglemaw":
		_spawn_tanglemaw_flock(
			planet, home, level, patch_id, health_scale, flock, chase_override)
	elif kind == "weaver":
		_spawn_weaver_flock(
			planet, home, level, patch_id, health_scale, flock, chase_override)


func _mass_heading(planet: Planet, player: Node3D) -> Vector3:
	var owner := player.get_instance_id()
	var up := planet.up_at(player.global_position) if planet.has_method(&"up_at") \
		else Vector3.UP
	var travel := CrawlerRules.spawn_going(_player_velocity(player), up)
	if travel.length_squared() > 0.0001:
		_pack_heading[owner] = travel
		return travel
	var held: Variant = _pack_heading.get(owner, Vector3.ZERO)
	if held is Vector3 and (held as Vector3).length_squared() > 0.0001:
		return held
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var yaw := float(_spawn_serial) * CrawlerRules.START_RING_STEP
	var heading := (east * cos(yaw) + north * sin(yaw)).normalized()
	_pack_heading[owner] = heading
	return heading


func _stamp_pack(planet: Planet, player: Node3D, kind: String, heading: Vector3,
		near: float, far: float) -> Vector3:
	if planet == null or player == null:
		return Vector3(NAN, NAN, NAN)
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	for attempt in 6:
		_spawn_serial += 1
		var yaw := float(_spawn_serial) * CrawlerRules.START_RING_STEP \
			+ float(attempt) * 0.41
		var t := float(posmod(_spawn_serial * 13 + attempt * 7, 97)) / 96.0
		var reach := lerpf(near, far, t)
		var surface := _project_surface(planet, at, up, heading, yaw, reach)
		if not surface.is_finite() or not _home_clear(surface, kind):
			continue
		var home := surface + planet.up_at(surface) * _lift_for(kind, _spawn_serial)
		if _pack_point_ok(home, player, planet, kind, near, far):
			return home
	return Vector3(NAN, NAN, NAN)


func _pack_point_ok(at: Vector3, player: Node3D, planet: Planet, kind: String,
		near: float, far: float) -> bool:
	if player == null or not at.is_finite() or not _home_clear(at, kind):
		return false
	var overlay := _overlay()
	if overlay != null and overlay.keeps_mobs_out(at):
		return false
	var up := Vector3.UP
	if planet != null and planet.has_method(&"up_at"):
		up = planet.up_at(player.global_position)
	if not CrawlerRules.bastion_in_band(at, player.global_position, near, far, up):
		return false
	return _count_kind_near(at, CrawlerRules.BASTION_GRID, kind) <= 0


func _stamp_bastion(planet: Planet, player: Node3D,
		near := CrawlerRules.BASTION_RESERVE_NEAR,
		far := CrawlerRules.BASTION_RESERVE_FAR) -> Vector3:
	if planet == null or player == null:
		return Vector3(NAN, NAN, NAN)
	var at := player.global_position
	var up := planet.up_at(at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = at.normalized() if at.length_squared() > 0.0001 else Vector3.UP
	for attempt in 6:
		_spawn_serial += 1
		var yaw := float(_spawn_serial) * CrawlerRules.START_RING_STEP \
			+ float(attempt) * 0.41
		var t := float(posmod(_spawn_serial * 13 + attempt * 7, 97)) / 96.0
		var reach := lerpf(near, far, t)
		var surface := _project_surface(planet, at, up, Vector3.ZERO, yaw, reach)
		if not surface.is_finite():
			continue
		var home := surface + planet.up_at(surface) * _lift_for("bastion", _spawn_serial)
		if _bastion_point_ok(home, player, planet, near, far):
			return home
	return Vector3(NAN, NAN, NAN)


func _bastion_point_ok(at: Vector3, player: Node3D, planet: Planet,
		near := CrawlerRules.BASTION_RESERVE_NEAR,
		far := CrawlerRules.BASTION_RESERVE_FAR) -> bool:
	if player == null or not at.is_finite() or not _home_clear(at, "bastion"):
		return false
	var overlay := _overlay()
	if overlay != null and overlay.keeps_mobs_out(at):
		return false
	var up := Vector3.UP
	if planet != null and planet.has_method(&"up_at"):
		up = planet.up_at(player.global_position)
	if not CrawlerRules.bastion_in_band(at, player.global_position, near, far, up):
		return false
	return _count_kind_near(at, CrawlerRules.BASTION_GRID, "bastion") <= 0


func _spawn_ring_home(planet: Planet, overlay: LandPatchOverlay,
		player: Node3D) -> int:
	if planet == null or player == null:
		return 0
	var record := _patch_record(player, overlay)
	var patch_name := str(record.get("name", ""))
	var patch_id := int(record.get("id", -1))
	if CrawlerRules.castle_grounds(patch_name) \
			or CrawlerRules.in_castle_keep(player.global_position):
		return 0
	var here := _distance_from_start(player.global_position)
	var recipe := CrawlerRules.patch_recipe(patch_name, here)
	return _spawn_home(
		planet, player, recipe, patch_name, patch_id,
		_level_for(patch_id, overlay),
		float(recipe.get("health_scale", 1.0)),
		true)


func _recycle_mob(mob: CrawlerMob) -> bool:
	if mob == null or not is_instance_valid(mob) or mob.is_persistent():
		return false
	var overlay := _overlay()
	var planet := _planet()
	if planet == null:
		return false
	var nearest: Node3D
	var nearest_gap := INF
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		if _player_is_safe(player, overlay):
			continue
		var gap := player.global_position.distance_to(mob.global_position)
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = player
	if nearest == null:
		return false
	if mob.has_method(&"fusing") and bool(mob.call(&"fusing")):
		return true
	var kind := _kind_of(mob)
	var home := Vector3(NAN, NAN, NAN)
	if CrawlerRules.uses_pack_mass(kind):
		var reserve := CrawlerRules.pack_band(false)
		home = _stamp_pack(
			planet, nearest, kind, _mass_heading(planet, nearest),
			reserve.x, reserve.y)
	else:
		home = _stamp_around(planet, nearest, kind, true)
	if not home.is_finite():
		return false
	if overlay != null and overlay.keeps_mobs_out(home):
		return false
	if CrawlerRules.in_castle_keep(home) \
			or CrawlerRules.in_castle_keep(nearest.global_position):
		return false
	var allowed := _field_kinds_for(nearest)
	if allowed.is_empty() or not allowed.has(kind):
		return false
	mob.recycle_to(home)
	return true


func _arm_from_patch(planet: Planet, overlay: LandPatchOverlay, patch_id: int,
		player: Node3D) -> void:
	if planet == null or overlay == null or overlay.partition == null or patch_id < 0:
		return
	_arm_one_patch(planet, overlay, patch_id, player)
	var combo := CrawlerRules.patch_combo(_patch_name_from_id(patch_id))
	for other in overlay.partition.neighbors_of(patch_id):
		if CrawlerRules.patch_combo(_patch_name_from_id(other)) != combo:
			continue
		_arm_one_patch(planet, overlay, other, player)


func _group_armed(overlay: LandPatchOverlay, patch_id: int) -> bool:
	if not is_patch_armed(patch_id):
		return false
	if overlay == null or overlay.partition == null:
		return true
	var combo := CrawlerRules.patch_combo(_patch_name_from_id(patch_id))
	for other in overlay.partition.neighbors_of(patch_id):
		if other < 0:
			continue
		if CrawlerRules.patch_combo(_patch_name_from_id(other)) != combo:
			continue
		if not is_patch_armed(other):
			return false
	return true


func _arm_one_patch(planet: Planet, overlay: LandPatchOverlay, patch_id: int,
		player: Node3D) -> void:
	if patch_id < 0 or is_patch_armed(patch_id):
		return
	if overlay == null or overlay.partition == null \
			or patch_id >= overlay.partition.patches.size():
		return
	var patch_name := overlay.partition.recipe_name_of(patch_id)
	if patch_name.is_empty():
		patch_name = str(overlay.partition.patches[patch_id].name)
	if CrawlerRules.castle_grounds(patch_name):
		_armed[patch_id] = true
		_ensure_castle_garrison()
		return
	if _fill_patch(planet, overlay, patch_id, patch_name, player):
		_armed[patch_id] = true


func _fill_patch(planet: Planet, overlay: LandPatchOverlay, patch_id: int,
		patch_name: String, player: Node3D) -> bool:
	if planet == null:
		return false
	var facing: LandPartition.Patch = overlay.partition.patches[patch_id]
	var center := planet.surface_position(facing.direction)
	if overlay.keeps_mobs_out(center) or CrawlerRules.in_castle_keep(center):
		return true
	var here := _distance_from_start(center)
	var recipe := CrawlerRules.patch_recipe(patch_name, here)
	var kinds := _roster_for_patch(patch_name, here, center, player)
	if kinds.is_empty():
		return true
	var combo := CrawlerRules.patch_combo(patch_name)
	if combo == CrawlerRules.PATCH_COMBO_ROBOT \
			or combo == CrawlerRules.PATCH_COMBO_DEMON \
			or combo == CrawlerRules.PATCH_COMBO_ALIEN \
			or combo == CrawlerRules.PATCH_COMBO_WILD:
		return true
	var level := _level_for(patch_id, overlay)
	var health_scale := float(recipe.get("health_scale", 1.0))
	var want := CrawlerRules.pack_limit(kinds, level)
	if want <= 0:
		return true
	var dirs := overlay.partition.cell_directions_of(patch_id)
	if dirs.is_empty():
		dirs.append(facing.direction)
	var placed := 0
	var attempts := 0
	var max_attempts := want * 3
	while placed < want and attempts < max_attempts:
		attempts += 1
		if _build_queue.size() >= CrawlerRules.MOB_SPAWN_QUEUE:
			return false
		var dir: Vector3 = dirs[attempts % dirs.size()]
		var spin := float(_spawn_serial + attempts) * 0.41
		var jitter := dir.cross(Vector3.UP)
		if jitter.length_squared() < 0.0001:
			jitter = dir.cross(Vector3.RIGHT)
		if jitter.length_squared() > 0.0001:
			dir = (dir + jitter.normalized() * 0.035 * sin(spin)).normalized()
		var surface := planet.mesh_position(dir)
		if not surface.is_finite() or MobSense.keepout_blocks(self, surface) \
				or _kill_blocks(surface) or CrawlerRules.in_castle_keep(surface) \
				or _tree_arena_clears(surface):
			continue
		if player != null \
				and surface.distance_squared_to(player.global_position) < 16.0:
			continue
		var kind := _pick_kind_for_patch(
			surface, patch_name, here, level, patch_id, kinds)
		if kind.is_empty():
			break
		if _monument_blocks(surface) and not CrawlerRules.is_demon_kind(kind) \
				and not CrawlerRules.is_robot_kind(kind):
			continue
		if CrawlerRules.in_office_tower(surface):
			continue
		var home := surface + planet.up_at(surface) * _lift_for(kind, _spawn_serial)
		var made := _enqueue_wild(kind, home, level, patch_id, health_scale)
		if made <= 0:
			return false
		placed += made
		if kind == "gloam":
			placed += _spawn_gloam_flock(planet, home, level, patch_id, health_scale)
		_spawn_serial += 1
	return true


func _roster_for_patch(patch_name: String, from_start: float, center: Vector3,
		_player: Node3D) -> PackedStringArray:
	var kinds := CrawlerRules.field_kinds(patch_name, from_start, center)
	var open: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		if kind != "bastion":
			open.append(kind)
	return open


func _ensure_demon_keeps() -> void:
	_ensure_robot_site()


func _ensure_robot_site() -> void:
	# Adobe office sites do not seed a robot pack while the new mass settles.
	return


func _top_up_demon_site(planet: Planet, overlay: LandPatchOverlay, player: Node3D,
		quest_id: String, patch_name: String) -> void:
	var site := PatchMonument.find_id(quest_id)
	if site == null or player == null:
		return
	if player.global_position.distance_to(site.global_position) \
			> CrawlerRules.DEMON_SITE_RANGE:
		return
	var patch_id := -1
	if overlay != null:
		patch_id = overlay.patch_id_named(patch_name)
		if patch_id < 0:
			patch_id = overlay.patch_id_at(site.global_position)
	var here := _distance_from_start(site.global_position)
	var level := _level_for(patch_id, overlay)
	var recipe := CrawlerRules.patch_recipe(patch_name, here)
	var health_scale := float(recipe.get("health_scale", 1.0))
	_fill_combo_mass(planet, player, patch_name, patch_id, level, health_scale)


func _stamp_near_site(planet: Planet, site_at: Vector3, kind: String,
		player: Node3D) -> Vector3:
	if planet == null or not site_at.is_finite():
		return Vector3(NAN, NAN, NAN)
	var up := planet.up_at(site_at) if planet.has_method(&"up_at") else Vector3.UP
	if up.length_squared() < 0.0001:
		up = site_at.normalized() if site_at.length_squared() > 0.0001 else Vector3.UP
	for attempt in 8:
		_spawn_serial += 1
		var yaw := float(_spawn_serial) * CrawlerRules.START_RING_STEP
		var reach := lerpf(28.0, 170.0, float(attempt) / 7.0)
		var surface := _project_surface(planet, site_at, up, Vector3.ZERO, yaw, reach)
		if not surface.is_finite() or not _home_clear(surface, kind):
			continue
		if player != null \
				and surface.distance_squared_to(player.global_position) < 16.0:
			continue
		return surface + planet.up_at(surface) * _lift_for(kind, _spawn_serial)
	return Vector3(NAN, NAN, NAN)


func _pick_kind_for_patch(at: Vector3, patch_name: String, from_start: float,
		level: int, patch_id: int,
		roster: PackedStringArray = PackedStringArray()) -> String:
	var kinds := roster if not roster.is_empty() \
		else CrawlerRules.field_kinds(patch_name, from_start, at)
	var open: PackedStringArray = PackedStringArray()
	for kind: String in kinds:
		if kind == "bastion":
			continue
		if CrawlerRules.is_demon_kind(kind) \
				and not CrawlerRules.can_field_demons(patch_name, at):
			continue
		if _kind_blocked(kind):
			continue
		if _count_kind_in_patch(patch_id, kind) < CrawlerRules.kind_cap(kind, level):
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


func _count_kind_in_patch(patch_id: int, kind: String) -> int:
	if patch_id < 0:
		return 0
	var count := 0
	for mob_variant: Variant in _mobs.values():
		var mob := _as_mob(mob_variant)
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		if mob.city_id == patch_id and _kind_of(mob) == kind:
			count += 1
	for row: Dictionary in _build_queue:
		if int(row.get("city", -1)) == patch_id \
				and str(row.get("kind", "ranger")) == kind:
			count += 1
	return count


func _count_kind_all(kind: String) -> int:
	var count := 0
	for mob_variant: Variant in _mobs.values():
		if not is_instance_valid(mob_variant):
			continue
		var mob := _as_mob(mob_variant)
		if mob == null or mob.is_persistent():
			continue
		if _kind_of(mob) == kind:
			count += 1
	for row: Dictionary in _build_queue:
		if str(row.get("kind", "ranger")) == kind:
			count += 1
	return count


func _patch_has_bodies(patch_id: int) -> bool:
	if patch_id < 0:
		return false
	for mob_variant: Variant in _mobs.values():
		var mob := _as_mob(mob_variant)
		if mob != null and is_instance_valid(mob) and mob.city_id == patch_id:
			return true
	for row: Dictionary in _build_queue:
		if int(row.get("city", -1)) == patch_id:
			return true
	return false


func _maybe_unarm_patch(patch_id: int) -> void:
	if patch_id < 0 or not is_patch_armed(patch_id):
		return
	if _patch_has_bodies(patch_id):
		return
	_armed.erase(patch_id)
	var drop: Array = []
	for owner_variant: Variant in _seen_patch.keys():
		if int(_seen_patch[owner_variant]) == patch_id:
			drop.append(owner_variant)
	for owner_variant: Variant in drop:
		_seen_patch.erase(owner_variant)


func _clear_castle_wilds() -> void:
	var center := CrawlerRules.castle_keep_center()
	var have_keep := center.is_finite()
	var guests: Array[Vector3] = []
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player != null and CrawlerRules.in_castle_keep(player.global_position):
			guests.append(player.global_position)
	if not have_keep and guests.is_empty():
		return
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _held_mob(id)
		if mob == null:
			gone.append(id)
			continue
		if mob.is_persistent():
			continue
		if (have_keep and CrawlerRules.in_castle_keep(mob.global_position)) \
				or (not guests.is_empty() and mob.chase):
			gone.append(id)
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)
	var kept: Array[Dictionary] = []
	for row: Dictionary in _build_queue:
		if bool(row.get("persistent", false)):
			kept.append(row)
			continue
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3 or not origin.is_finite():
			continue
		if have_keep and CrawlerRules.in_castle_keep(origin):
			continue
		var near_guest := false
		for at: Vector3 in guests:
			if origin.distance_to(at) <= CrawlerRules.PACK_KEEP:
				near_guest = true
				break
		if near_guest:
			continue
		kept.append(row)
	_build_queue = kept


func should_clear_all_field() -> bool:
	var players := _players()
	if players.is_empty():
		return false
	var hosted := 0
	var live := 0
	for player_variant: Variant in players:
		var player := player_variant as Node3D
		if player == null:
			continue
		live += 1
		if _player_in_city_hold(player):
			hosted += 1
	return hosted > 0 and hosted >= live


func dismiss_all_field() -> void:
	_dismiss_all_field_mobs()


func _player_in_city_hold(player: Node3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method(&"in_crawler_city") and bool(player.call(&"in_crawler_city")):
		return true
	if MobSense.player_in_city(player):
		return true
	if not is_inside_tree():
		return false
	for zone_variant: Variant in get_tree().get_nodes_in_group(CrawlerCityRing.GROUP):
		var ring := zone_variant as CrawlerCityRing
		if ring != null and ring.blocks_near(player.global_position):
			return true
	return false


func _dismiss_all_field_mobs() -> void:
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _held_mob(id)
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		gone.append(id)
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)
	var kept: Array[Dictionary] = []
	for row: Dictionary in _build_queue:
		if bool(row.get("persistent", false)):
			kept.append(row)
	_build_queue = kept
	_ready_homes.clear()
	_seen_patch.clear()


func _clear_site_patch_mobs() -> void:
	if not is_inside_tree():
		return
	if should_clear_all_field():
		_dismiss_all_field_mobs()
		return
	var centers := PackedVector3Array()
	var rings: Array[CrawlerCityRing] = []
	var players := _players()
	for zone_variant: Variant in get_tree().get_nodes_in_group(CrawlerCityRing.GROUP):
		var ring := zone_variant as CrawlerCityRing
		if ring == null:
			continue
		var hosted := PackedVector3Array()
		for player_variant: Variant in players:
			var player := player_variant as Node3D
			if player != null and ring.blocks_near(player.global_position):
				hosted.append(player.global_position)
		if hosted.is_empty():
			rings.append(ring)
			continue
		_dismiss_patch_mobs_near(hosted, CrawlerRules.SITE_CLEAR_RADIUS)
		_dismiss_patch_mobs_near(
			PackedVector3Array([ring.global_position]),
			ring.keepout_radius() + CrawlerRules.AGRO_RANGE)
	for site_variant: Variant in get_tree().get_nodes_in_group(PatchMonument.KEEP_GROUP):
		var site := site_variant as PatchMonument
		if site != null and CrawlerRules.is_office_id(site.monument_id):
			centers.append(site.global_position)
	_dismiss_patch_mobs_near(centers, CrawlerRules.SITE_CLEAR_RADIUS, true)
	if rings.is_empty():
		return
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _held_mob(id)
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		for ring: CrawlerCityRing in rings:
			if ring.contains_point(mob.global_position) \
					or ring.blocks_near(mob.global_position):
				gone.append(id)
				break
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)


func dismiss_near(at: Vector3, radius: float) -> void:
	if not at.is_finite() or radius <= 0.0:
		return
	_dismiss_patch_mobs_near(PackedVector3Array([at]), radius)


func _dismiss_patch_mobs_near(centers: PackedVector3Array, radius: float,
		skip_robots := false) -> void:
	if centers.is_empty() or radius <= 0.0:
		return
	var reach2 := radius * radius
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _held_mob(id)
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		if skip_robots and CrawlerRules.is_robot_kind(_kind_of(mob)):
			continue
		for center: Vector3 in centers:
			if mob.global_position.distance_squared_to(center) <= reach2:
				gone.append(id)
				break
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)
	var kept: Array[Dictionary] = []
	for row: Dictionary in _build_queue:
		if bool(row.get("persistent", false)) \
				or (skip_robots and CrawlerRules.is_robot_kind(str(row.get("kind", "")))):
			kept.append(row)
			continue
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3 or not origin.is_finite():
			continue
		var blocked := false
		for center: Vector3 in centers:
			if origin.distance_squared_to(center) <= reach2:
				blocked = true
				break
		if not blocked:
			kept.append(row)
	_build_queue = kept
	var homes: Array[Dictionary] = []
	for row: Dictionary in _ready_homes:
		var home: Vector3 = row.get("at", Vector3.ZERO)
		if typeof(home) != TYPE_VECTOR3 or not home.is_finite():
			continue
		var blocked := false
		for center: Vector3 in centers:
			if home.distance_squared_to(center) <= reach2:
				blocked = true
				break
		if not blocked:
			homes.append(row)
	_ready_homes = homes


func _clear_off_combo_wilds() -> void:
	var rings: Array[Dictionary] = []
	var overlay := _overlay()
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null or _player_is_safe(player, overlay):
			continue
		rings.append({
			"at": player.global_position,
			"kinds": _field_kinds_for(player),
			"patch_id": _patch_id_of(player, overlay),
		})
	if rings.is_empty():
		return
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _held_mob(id)
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		if _off_combo_near(mob.global_position, mob.wild_kind(), rings):
			gone.append(id)
	for id: String in gone:
		_dismiss_mob(id)
		if _has_listeners():
			_despawn_mob_rpc.rpc(id)
	var kept: Array[Dictionary] = []
	for row: Dictionary in _build_queue:
		if bool(row.get("persistent", false)):
			kept.append(row)
			continue
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) != TYPE_VECTOR3 or not origin.is_finite():
			continue
		if _off_combo_near(origin, str(row.get("kind", "")), rings):
			continue
		kept.append(row)
	_build_queue = kept


func _off_combo_near(at: Vector3, kind: String, rings: Array[Dictionary],
		mob_patch := -1) -> bool:
	if not at.is_finite() or kind.is_empty():
		return false
	var ring_out := CrawlerRules.field_ring_out()
	var ring_out2 := ring_out * ring_out
	var home := mob_patch
	var resolved := mob_patch >= 0
	for row: Dictionary in rings:
		var here: Vector3 = row.get("at", Vector3.INF)
		if not here.is_finite() or at.distance_squared_to(here) > ring_out2:
			continue
		var kinds: PackedStringArray = row.get("kinds", PackedStringArray())
		if kinds.is_empty() or kinds.has(kind):
			continue
		if not resolved:
			home = _field_patch_id(at)
			resolved = true
		var player_patch := int(row.get("patch_id", -1))
		if player_patch < 0:
			player_patch = _field_patch_id(here)
		# Leave the pack on the tile you walked off. Only retire wrong kinds
		# that followed onto this player's current patch.
		if player_patch >= 0 and home >= 0 and player_patch != home:
			continue
		return true
	return false


func _field_patch_id(at: Vector3) -> int:
	if not at.is_finite():
		return -1
	var overlay := _overlay()
	if overlay == null or overlay.partition == null or not overlay.ensure_ready():
		return -1
	return overlay.patch_id_at(at)


func _field_kinds_for(player: Node3D) -> PackedStringArray:
	if player == null:
		return PackedStringArray()
	return CrawlerRules.field_kinds(
		_patch_name_of(player, _overlay()),
		_distance_from_start(player.global_position),
		player.global_position)


func _reap_far_and_idle() -> void:
	var gone: Array[String] = []
	var ids: Array = _mobs.keys()
	var n := ids.size()
	var window := mini(24, n)
	var start := 0 if n <= 0 else posmod(_reap_cursor, n)
	if n > 0:
		_reap_cursor = start + window
	for i in n:
		var id := str(ids[i])
		var mob := _held_mob(id)
		if mob == null or not is_instance_valid(mob):
			gone.append(id)
			continue
		if mob.is_persistent():
			continue
		if mob.has_method(&"fusing") and bool(mob.call(&"fusing")):
			continue
		var in_window := window <= 0 or posmod(i - start + n, n) < window
		if in_window:
			if MobSense.keepout_blocks(self, mob.global_position):
				gone.append(id)
				continue
			if _tree_arena_clears(mob.global_position):
				gone.append(id)
				continue
			if _monument_blocks(mob.global_position) \
					and not mob.chase and not mob.ever_chased \
					and not CrawlerRules.is_demon_kind(_kind_of(mob)) \
					and not CrawlerRules.is_robot_kind(_kind_of(mob)):
				gone.append(id)
				continue
			if CrawlerRules.in_office_site_clear(mob.global_position):
				gone.append(id)
				continue
		var distance := _nearest_player_distance(mob.global_position)
		if distance > CrawlerRules.WILD_STREAM_OUT:
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
	var home := Vector3(NAN, NAN, NAN)
	if kind != "weaver":
		home = _take_ready_home(player, planet, ring)
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
	elif kind == "tanglemaw":
		made += _spawn_tanglemaw_flock(planet, home, level, patch_id, health_scale)
	elif kind == "weaver":
		made += _spawn_weaver_flock(planet, home, level, patch_id, health_scale)
	return made


func _spawn_gloam_flock(planet: Planet, home: Vector3, level: int, patch_id: int,
		health_scale: float, flock := CrawlerRules.GLOAM_FLOCK,
		chase_override := -1) -> int:
	var used := _count_kind_in_patch(patch_id, "gloam") if patch_id >= 0 \
		else _count_kind_near(home, CrawlerRules.PACK_KEEP, "gloam")
	var cap := CrawlerRules.kind_cap("gloam", level)
	var mates := mini(maxi(flock, 1) - 1, maxi(cap - used, 0))
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
		var reach := 2.8 + float(index) * 0.55
		var guess := home + (east * cos(yaw) + north * sin(yaw)) * reach
		var perch := guess
		if planet != null:
			var local := planet.to_local(guess)
			if local.length_squared() < 0.0001:
				local = up
			var surface := planet.mesh_position(local)
			perch = surface + planet.up_at(surface) * 1.4
		made += _enqueue_wild(
			"gloam", perch, level, patch_id, health_scale, home, chase_override)
	return made


func _spawn_tanglemaw_flock(planet: Planet, home: Vector3, level: int,
		patch_id: int, health_scale: float,
		flock := CrawlerRules.TANGLEMAW_FLOCK, chase_override := -1) -> int:
	var used := _count_kind_in_patch(patch_id, "tanglemaw") if patch_id >= 0 \
		else _count_kind_near(home, CrawlerRules.PACK_KEEP, "tanglemaw")
	var cap := CrawlerRules.kind_cap("tanglemaw", level)
	var mates := mini(maxi(flock, 1) - 1, maxi(cap - used, 0))
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
		var yaw := TAU * float(index) / float(mates) + float(_spawn_serial) * 0.17
		var reach := 3.4 + float(index) * 0.85
		var guess := home + (east * cos(yaw) + north * sin(yaw)) * reach
		var perch := guess
		if planet != null:
			var local := planet.to_local(guess)
			if local.length_squared() < 0.0001:
				local = up
			var surface := planet.mesh_position(local)
			perch = surface + planet.up_at(surface) * 1.4
		made += _enqueue_wild(
			"tanglemaw", perch, level, patch_id, health_scale, home, chase_override)
	return made


func _spawn_weaver_flock(planet: Planet, home: Vector3, level: int,
		patch_id: int, health_scale: float,
		flock := CrawlerRules.WEAVER_FLOCK, chase_override := -1) -> int:
	var used := _count_kind_in_patch(patch_id, "weaver") if patch_id >= 0 \
		else _count_kind_near(home, CrawlerRules.PACK_KEEP, "weaver")
	var cap := CrawlerRules.kind_cap("weaver", level)
	var mates := mini(maxi(flock, 1) - 1, maxi(cap - used, 0))
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
		var yaw := TAU * float(index) / float(mates) + float(_spawn_serial) * 0.19
		var reach := 2.4 + float(index) * 0.7
		var guess := home + (east * cos(yaw) + north * sin(yaw)) * reach
		var perch := guess
		if planet != null:
			var local := planet.to_local(guess)
			if local.length_squared() < 0.0001:
				local = up
			var surface := planet.mesh_position(local)
			perch = surface + planet.up_at(surface) * 1.4
		made += _enqueue_wild(
			"weaver", perch, level, patch_id, health_scale, home, chase_override)
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
	if CrawlerRules.uses_pack_mass(kind):
		band = CrawlerRules.pack_band(true)
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
		if not surface.is_finite() or not _home_clear(surface, kind):
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
	return planet.mesh_position(local)


func _monument_blocks(at: Vector3) -> bool:
	if MobSense.monument_blocks(self, at):
		return true
	return is_inside_tree() and PatchMonument.blocks_any(get_tree(), at)


func _tree_arena_clears(at: Vector3) -> bool:
	if not at.is_finite() or not is_inside_tree():
		return false
	for node_variant: Variant in get_tree().get_nodes_in_group(
			BossAdapter.CRAWLER_GROUP):
		var boss := node_variant as Node3D
		if boss == null or not boss.has_method(&"blocks_field_spawns") \
				or not bool(boss.call(&"blocks_field_spawns")):
			continue
		var reach := CrawlerRules.TREE_BATTLE_RADIUS
		if boss.has_method(&"battle_radius"):
			reach = maxf(float(boss.call(&"battle_radius")), 1.0)
		if boss.global_position.distance_to(at) <= reach:
			return true
	return false


func _home_clear(at: Vector3, kind := "") -> bool:
	if not at.is_finite():
		return false
	if MobSense.keepout_blocks(self, at):
		return false
	if _tree_arena_clears(at):
		return false
	if CrawlerRules.in_castle_keep(at) and not CrawlerRules.is_goblin_kind(kind):
		return false
	if CrawlerRules.in_office_tower(at):
		return false
	if CrawlerRules.in_office_site_clear(at) \
			and not CrawlerRules.office_site_allows(kind):
		return false
	if _monument_blocks(at) \
			and not CrawlerRules.is_demon_kind(kind) \
			and not CrawlerRules.is_robot_kind(kind) \
			and not CrawlerRules.is_goblin_kind(kind) \
			and not CrawlerRules.is_glorb_kind(kind):
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
		if not home.is_finite() or CrawlerRules.in_castle_keep(home):
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
		kind := "", ring := false) -> bool:
	if not at.is_finite():
		return false
	if MobSense.keepout_blocks(self, at):
		return false
	if _tree_arena_clears(at):
		return false
	if CrawlerRules.in_castle_keep(at) and not CrawlerRules.is_goblin_kind(kind):
		return false
	if CrawlerRules.in_office_tower(at):
		return false
	if CrawlerRules.in_office_site_clear(at) \
			and not CrawlerRules.office_site_allows(kind):
		return false
	if _monument_blocks(at) \
			and not CrawlerRules.is_demon_kind(kind) \
			and not CrawlerRules.is_robot_kind(kind) \
			and not CrawlerRules.is_goblin_kind(kind) \
			and not CrawlerRules.is_glorb_kind(kind):
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
	if CrawlerRules.is_glorb_kind(kind):
		if kind == "glorb_jellyfish" or kind == "glorb_angel":
			return 5.5
		if kind == "glorb_eyeball":
			return lerpf(22.0, 44.0, t)
		return 1.4
	if CrawlerRules.is_goblin_kind(kind):
		return 1.05
	if kind == "rift_hulk":
		return 3.4
	if kind == "rhino":
		return 1.9
	if kind == "gloam" or kind == "bastion" or kind == "weaver" \
			or kind == "gray" or kind == "tanglemaw":
		return 1.4
	if kind == "kestrel" or kind == "scout":
		return lerpf(7.0, 13.0, t)
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
		if kind == "bastion":
			continue
		if _kind_blocked(kind):
			continue
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
		var mob := _as_mob(mob_variant)
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


func _count_kind_state_near(at: Vector3, reach: float, kind: String,
		chasing: bool) -> int:
	var count := 0
	var reach2 := reach * reach
	for id_variant: Variant in _mobs.keys():
		var mob := _held_mob(id_variant)
		if mob == null or _kind_of(mob) != kind or mob.chase != chasing:
			continue
		if mob.global_position.distance_squared_to(at) <= reach2:
			count += 1
	for row: Dictionary in _build_queue:
		if str(row.get("kind", "")) != kind:
			continue
		if bool(row.get("chase", false)) != chasing:
			continue
		var origin: Vector3 = row.get("origin", Vector3.ZERO)
		if typeof(origin) == TYPE_VECTOR3 and origin.distance_squared_to(at) <= reach2:
			count += 1
	return count


func _player_is_safe(player: Node3D, overlay: LandPatchOverlay) -> bool:
	if _player_in_city_hold(player):
		return true
	if player.has_method(&"in_crawler_city") and bool(player.call(&"in_crawler_city")):
		return true
	if player.has_method(&"in_crawler_safe_zone") \
			and bool(player.call(&"in_crawler_safe_zone")):
		return true
	if CrawlerSafeBox.contains_any(player):
		return true
	if overlay != null and overlay.keeps_mobs_out(player.global_position):
		return true
	if CrawlerRules.in_castle_keep(player.global_position):
		return true
	if MobSense.player_on_spawn_pad(player):
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


func _patch_name_from_id(patch_id: int) -> String:
	var overlay := _overlay()
	if overlay == null or overlay.partition == null or patch_id < 0 \
			or patch_id >= overlay.partition.patches.size():
		return ""
	var patch_name := overlay.partition.recipe_name_of(patch_id)
	if patch_name.is_empty():
		patch_name = str(overlay.partition.patches[patch_id].name)
	return patch_name


func _office_sites() -> Array[PatchMonument]:
	var found: Array[PatchMonument] = []
	if not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(PatchMonument.KEEP_GROUP):
		var site := node_variant as PatchMonument
		if site != null and CrawlerRules.is_office_id(site.monument_id):
			found.append(site)
	if found.is_empty():
		var authored := PatchMonument.find_id(CrawlerProgress.QUEST_TOWER)
		if authored != null:
			found.append(authored)
	return found


func _office_patch_record(office: PatchMonument, overlay: LandPatchOverlay) -> Dictionary:
	if office == null:
		return {"id": -1, "name": ""}
	var key := office.get_instance_id()
	var cached: Variant = _office_patch.get(key)
	if cached is Dictionary:
		return cached
	var patch_id := -1
	if overlay != null:
		patch_id = overlay.patch_id_at(office.global_position)
	var row := {
		"id": patch_id,
		"name": _patch_name_from_id(patch_id),
	}
	_office_patch[key] = row
	return row


func _level_for(patch_id: int, overlay: LandPatchOverlay) -> int:
	var facing := _start_dir
	var patch_name := _patch_name_from_id(patch_id)
	if CrawlerRun.active() and not patch_name.is_empty():
		return CrawlerRun.level_for_patch(patch_name)
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


func _player_is_hunted(player: Node3D) -> bool:
	if player == null:
		return false
	var at := player.global_position
	for id_variant: Variant in _mobs.keys():
		var mob := _held_mob(id_variant)
		if mob == null or mob.is_persistent() or not mob.chase:
			continue
		if mob.global_position.distance_to(at) <= CrawlerHunt.DEAGRO + 20.0:
			return true
	return false


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
	MobSense.ensure_frame(get_tree())
	return MobSense.players()


func _enqueue_wild(kind: String, home: Vector3, level: int, patch_id: int,
		health_scale: float, hang := Vector3(NAN, NAN, NAN),
		chase_override := -1) -> int:
	if not home.is_finite() or _build_queue.size() >= CrawlerRules.MOB_SPAWN_QUEUE:
		return 0
	if CrawlerRules.is_goblin_kind(kind) or CrawlerRules.in_castle_keep(home):
		return 0
	var combo_name := _fill_pack_name if not _fill_pack_name.is_empty() \
		else _patch_name_from_id(patch_id)
	if not CrawlerRules.combo_allows_kind(
			CrawlerRules.patch_combo(combo_name), kind):
		return 0
	if _kind_blocked(kind):
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
	if chase_override >= 0:
		row["chase"] = chase_override != 0
	else:
		row["chase"] = false if kind == "bastion" \
			else CrawlerRules.spawn_is_agro(_next_mob)
	_build_queue.append(row)
	_scan_at.append(home)
	_scan_kind.append(kind)
	return 1


func _spawn_build_budget() -> int:
	var extra := 0
	for row: Dictionary in _build_queue:
		if bool(row.get("persistent", false)):
			extra += 1
			if extra >= 6:
				break
	return CrawlerRules.MOB_SPAWN_BUILD + extra


func _drain_builds() -> void:
	if _garrison_queue.is_empty() and _build_queue.is_empty():
		return
	var batch: Array = []
	_drain_queue(_garrison_queue, CrawlerRules.GOBLIN_SPAWN_BURST, batch)
	_drain_queue(_build_queue, _spawn_build_budget(), batch)
	if not batch.is_empty() and _has_listeners():
		_spawn_mob_batch_rpc.rpc(batch)


func _drain_queue(queue: Array[Dictionary], left: int, batch: Array) -> void:
	while left > 0 and not queue.is_empty():
		var row: Dictionary = queue.pop_front()
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
		var inbound: Variant = row.get("inbound", Vector3.ZERO)
		if mob != null and inbound is Vector3 \
				and (inbound as Vector3).length_squared() > 0.0001:
			mob.set_inbound(inbound)
		if mob != null and bool(row.get("persistent", false)):
			mob.persistent = true
		batch.append(row)
		left -= 1
		if str(row.get("kind", "")) == "threnody":
			left = 0


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
	elif kind == "kestrel":
		mob = KESTREL.new()
	elif kind == "bastion":
		mob = BASTION.new()
	elif kind == "weaver":
		mob = WEAVER.new()
	elif kind == "scout":
		mob = SCOUT.new()
	elif kind == "gray":
		mob = GRAY.new()
	elif kind == "tanglemaw":
		mob = TANGLEMAW.new()
	elif kind == "glorb_jellyfish":
		mob = GLORB_JELLYFISH.new()
	elif kind == "glorb_rhino":
		mob = GLORB_RHINO.new()
	elif kind == "glorb_eyeball":
		mob = GLORB_EYEBALL.new()
	elif kind == "glorb_punching":
		mob = GLORB_PUNCHING.new()
	elif kind == "glorb_one_armed":
		mob = GLORB_ONE_ARMED.new()
	elif kind == "glorb_spider":
		mob = GLORB_SPIDER.new()
	elif kind == "glorb_angel":
		mob = GLORB_ANGEL.new()
	else:
		mob = CrawlerRanger.new()
	mob.configure(
		id, xform, level, should_chase, self, owned_city, slot, health_scale)
	mob.died.connect(_on_mob_died.bind(mob))
	mob.tree_exiting.connect(_forget_mob.bind(id), CONNECT_ONE_SHOT)
	add_child(mob)
	_mobs[id] = mob
	return mob


func _forget_mob(id: String) -> void:
	if not id.is_empty():
		_mobs.erase(id)


func _on_mob_died(mob: Variant) -> void:
	var body := _as_mob(mob)
	if body == null or body.dismissed:
		return
	var patch_id := body.city_id
	var training := body.is_training()
	var kind := body.wild_kind()
	var level := body.threat_level
	var home := body.hang_origin
	_forget_mob(body.mob_id)
	_maybe_unarm_patch(patch_id)
	if _is_host():
		if training:
			if _has_listeners():
				_mob_death_burst_rpc.rpc(
					body.combat_position(), body._up(),
					maxf(body.combat_radius() * 2.6, 2.4), kind)
				_despawn_mob_rpc.rpc(body.mob_id)
			_respawn_training_mob(kind, home, level)
			return
		if kind == "scout":
			spawn_drop_mob("gray", body.global_position, body.threat_level)
		if not body.is_persistent():
			_note_kill(body.global_position)
		_award_kill(body)
		if _has_listeners():
			_mob_death_burst_rpc.rpc(
				body.combat_position(), body._up(),
				maxf(body.combat_radius() * 2.6, 2.4), kind)
			_despawn_mob_rpc.rpc(body.mob_id)


func _respawn_training_mob(kind: String, home: Vector3, level: int) -> void:
	if not CrawlerRules.training_active() or not home.is_finite():
		return
	var pose := _pose_at(home)
	var id := "ct%d" % _next_mob
	_next_mob += 1
	var mob := _make_mob(id, kind, pose, level, false, -1, -1)
	if mob == null:
		return
	mob.become_training(pose)
	if _has_listeners():
		_spawn_mob_batch_rpc.rpc([{
			"id": id,
			"kind": kind,
			"origin": pose.origin,
			"level": level,
			"city": -1,
			"slot": -1,
			"chase": false,
			"health_scale": 1.0,
			"training": true,
		}])


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
	MobSense.ensure_frame(get_tree())
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


func apply_glorb_roster() -> void:
	if not CrawlerRules.glorb_field:
		return
	_trim_glorb_roster()


func _trim_glorb_roster() -> void:
	var from := Vector3(NAN, NAN, NAN)
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player != null:
			from = player.global_position
			break
	for kind: String in CrawlerRules.GLORB_KINDS:
		_trim_kind_to(kind, CrawlerRules.kind_cap(kind, 1), from)


func _trim_kind_to(kind: String, cap: int, from: Vector3) -> void:
	var have := _count_kind_all(kind)
	if have <= cap:
		return
	var kept: Array[Dictionary] = []
	for row: Dictionary in _build_queue:
		if str(row.get("kind", "")) == kind and have > cap:
			have -= 1
			continue
		kept.append(row)
	_build_queue = kept
	if have <= cap:
		return
	var bodies: Array[CrawlerMob] = []
	for id_variant: Variant in _mobs.keys():
		var mob := _held_mob(id_variant)
		if mob == null or not is_instance_valid(mob) or mob.is_persistent():
			continue
		if _kind_of(mob) != kind:
			continue
		bodies.append(mob)
	bodies.sort_custom(func(left: CrawlerMob, right: CrawlerMob) -> bool:
		if left.chase != right.chase:
			return not left.chase
		if not from.is_finite():
			return false
		return left.global_position.distance_squared_to(from) \
			> right.global_position.distance_squared_to(from)
	)
	for mob: CrawlerMob in bodies:
		if have <= cap:
			break
		dismiss_mob(mob.mob_id)
		have -= 1


func dismiss_mob(id: String) -> void:
	if id.is_empty() or not _mobs.has(id):
		return
	_dismiss_mob(id)
	if _has_listeners():
		_despawn_mob_rpc.rpc(id)


func dismiss_idle_kind(kind: String, except: Node = null) -> void:
	if kind.is_empty():
		return
	var gone: Array[String] = []
	for id_variant: Variant in _mobs.keys():
		var id := str(id_variant)
		var mob := _held_mob(id)
		if mob == null or mob == except or not is_instance_valid(mob):
			continue
		if mob.wild_kind() != kind or mob.chase or mob.dismissed:
			continue
		gone.append(id)
	var kept: Array[Dictionary] = []
	for row: Dictionary in _build_queue:
		if str(row.get("kind", "")) == kind:
			continue
		kept.append(row)
	_build_queue = kept
	for id: String in gone:
		dismiss_mob(id)


func _kind_blocked(kind: String) -> bool:
	if kind != "threnody":
		return false
	if not MobSense.each_kind("threnody").is_empty():
		return true
	for id_variant: Variant in _mobs.keys():
		var mob := _held_mob(id_variant)
		if mob != null and _kind_of(mob) == "threnody":
			return true
	for row: Dictionary in _build_queue:
		if str(row.get("kind", "")) == "threnody":
			return true
	return false


func _dismiss_mob(id: String) -> void:
	var mob := _held_mob(id)
	var patch_id := mob.city_id if mob != null else -1
	_forget_mob(id)
	if mob != null:
		mob.dismiss()
	_maybe_unarm_patch(patch_id)


func publish_mob_state(mob: CrawlerMob) -> void:
	if not _is_host() or mob == null or not _has_listeners():
		return
	_mob_state_rpc.rpc(mob.mob_id, mob.global_transform, mob.velocity,
		mob.health(), mob.maximum_health(), mob.current_clip())


func publish_ranger_shot(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.16, hit_radius := 0.62) -> void:
	if _has_listeners():
		_ranger_shot_rpc.rpc(from, launch, damage, shot_speed, ball_radius, hit_radius)


func publish_gray_shot(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.58, hit_radius := 1.3) -> void:
	if _has_listeners():
		_gray_shot_rpc.rpc(from, launch, damage, shot_speed, ball_radius, hit_radius)


func publish_scout_beam(from: Vector3, to: Vector3) -> void:
	if _has_listeners():
		_scout_beam_rpc.rpc(from, to)


func publish_vex_mortar(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.42, hit_radius := 1.15) -> void:
	if _has_listeners():
		_vex_mortar_rpc.rpc(from, launch, damage, shot_speed, ball_radius, hit_radius)


func publish_bastion_shell(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.36, hit_radius := 2.2,
		impact_at := Vector3.INF) -> void:
	if _has_listeners():
		_bastion_shell_rpc.rpc(
			from, launch, damage, shot_speed, ball_radius, hit_radius, impact_at)


func publish_bastion_burst(at: Vector3, radius: float) -> void:
	_play_bastion_burst(at, radius)
	if _has_listeners():
		_bastion_burst_rpc.rpc(at, radius)


func _play_bastion_burst(at: Vector3, radius: float) -> void:
	EnergyExplosion.burst(
		get_parent(), at, maxf(radius, 1.2), Color(1.0, 0.18, 0.08), 0.5)


func publish_robot_laser(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius: float, hit_radius: float,
		glow: Color) -> void:
	if _has_listeners():
		_robot_laser_rpc.rpc(
			from, launch, damage, shot_speed, ball_radius, hit_radius, glow)


func publish_rhino_meteor(at: Vector3, radius: float) -> void:
	_play_rhino_meteor(at, radius)
	if _has_listeners():
		_rhino_meteor_rpc.rpc(at, radius)


func _play_rhino_meteor(_at: Vector3, _radius: float) -> void:
	# The strike is the meteor-punch cone on the horn. A red ground burst
	# used to fire here and read as a shockwave instead of that cone.
	pass


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
	var look := _nearest_player_at(at)
	var ahead := Vector3.ZERO
	if look.is_finite():
		ahead = look - at
		ahead -= up * ahead.dot(up)
	var east := Vector3.ZERO
	var north := Vector3.ZERO
	if ahead.length_squared() > 0.0001:
		north = ahead.normalized()
		east = up.cross(north)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.RIGHT)
		if east.length_squared() < 0.01:
			east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	north = east.cross(up).normalized()
	return Transform3D(Basis(east, up, north), at)


func _nearest_player_at(at: Vector3) -> Vector3:
	var best := Vector3(NAN, NAN, NAN)
	var best2 := INF
	for player_variant: Variant in _players():
		var player := player_variant as Node3D
		if player == null:
			continue
		var away := player.global_position.distance_squared_to(at)
		if away < best2:
			best2 = away
			best = player.global_position
	return best


func _overlay() -> LandPatchOverlay:
	if is_instance_valid(_overlay_held):
		return _overlay_held
	if not is_inside_tree():
		_overlay_held = null
		return null
	_overlay_held = get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
		as LandPatchOverlay
	return _overlay_held


func _spawn_pad() -> CrawlerSpawnPad:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(CrawlerSpawnPad.GROUP) \
		as CrawlerSpawnPad


func _arrival_holds() -> bool:
	var spawn := _spawn_pad()
	if spawn == null:
		return false
	if spawn.holds_field():
		for player_variant: Variant in _players():
			var player := player_variant as Node3D
			if player != null:
				spawn.notice_player(player.global_position)
	return spawn.holds_field()


func _planet() -> Planet:
	var world := get_parent() as GameWorld
	if world != null:
		return world.planet()
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"planet") as Planet


func _up_at(at: Vector3) -> Vector3:
	var planet := _planet()
	if planet != null and planet.has_method(&"up_at") and at.is_finite():
		var up: Vector3 = planet.up_at(at)
		if up.length_squared() > 0.0001:
			return up.normalized()
	return Vector3.UP


func _look_ahead(player: Node3D, up: Vector3) -> Vector3:
	var look := Vector3.ZERO
	if player != null and player.has_method(&"look_direction"):
		look = player.call(&"look_direction") as Vector3
	if look.length_squared() < 0.0001 and player != null:
		look = -player.global_transform.basis.z
	var rise := up if up.length_squared() > 0.0001 else Vector3.UP
	look -= rise * look.dot(rise)
	if look.length_squared() < 0.0001:
		look = rise.cross(Vector3.RIGHT)
	if look.length_squared() < 0.0001:
		look = Vector3.FORWARD
	return look.normalized()


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
		var mob := _as_mob(mob_variant)
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
func _spawn_drop_rpc(id: String, kind: String, xform: Transform3D,
		level: int) -> void:
	if _is_host() or _mobs.has(id):
		return
	var mob := _make_mob(id, kind, xform, level, true, -1, -1)
	if mob != null and mob.has_method(&"begin_drop"):
		mob.call(&"begin_drop")


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
		var mob := _make_mob(
			id,
			str(row.get("kind", "ranger")),
			_pose_at(origin),
			int(row.get("level", 1)),
			bool(row.get("chase", false)),
			int(row.get("city", -1)),
			int(row.get("slot", -1)),
			float(row.get("health_scale", 1.0))
		)
		if mob != null and bool(row.get("training", false)):
			mob.become_training(mob.global_transform)
		var inbound: Variant = row.get("inbound", Vector3.ZERO)
		if mob != null and inbound is Vector3 \
				and (inbound as Vector3).length_squared() > 0.0001:
			mob.set_inbound(inbound as Vector3)


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
	var mob := _held_mob(id)
	if mob != null:
		mob.apply_network_state(xform, along, hp, maximum, clip)


@rpc("authority", "reliable")
func _gray_shot_rpc(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.58, hit_radius := 1.3) -> void:
	if _is_host():
		return
	var ball := GRAY_SHOT.new()
	ball.damage = damage
	ball.shot_speed = shot_speed
	ball.ball_radius = ball_radius
	ball.hit_radius = hit_radius
	var world := get_parent()
	if world == null or not ball.launch_anywhere(world, from, launch, null):
		ball.free()


@rpc("authority", "reliable")
func _scout_beam_rpc(from: Vector3, to: Vector3) -> void:
	if _is_host():
		return
	var world := get_parent()
	if world == null:
		return
	var beam := EnergyVfx.make(EnergyVfx.Kind.BEAM_CORE, EnergyVfx.TINT_PINK)
	beam.name = "ScoutPulse"
	world.add_child(beam)
	beam.place_beam(from, to, 0.42)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.12).timeout.connect(beam.queue_free)
	else:
		beam.queue_free()


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
func _robot_laser_rpc(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius: float, hit_radius: float,
		glow: Color) -> void:
	if _is_host():
		return
	var bolt := ROBOT_LASER.new()
	bolt.damage = damage
	bolt.shot_speed = shot_speed
	bolt.ball_radius = ball_radius
	bolt.hit_radius = hit_radius
	bolt.glow_color = glow
	bolt.core_color = glow.lightened(0.35)
	var world := get_parent()
	if world == null or not bolt.launch_anywhere(world, from, launch, null):
		bolt.free()


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


@rpc("authority", "reliable")
func _bastion_shell_rpc(from: Vector3, launch: Vector3, damage: float,
		shot_speed: float, ball_radius := 0.36, hit_radius := 2.2,
		impact_at := Vector3.INF) -> void:
	if _is_host():
		return
	var ball := BASTION_SHELL.new()
	ball.damage = damage
	ball.gravity = CrawlerRules.BASTION_GRAVITY
	ball.shot_speed = shot_speed
	ball.ball_radius = ball_radius
	ball.hit_radius = hit_radius
	ball.impact_at = impact_at
	var world := get_parent()
	if world == null or not ball.launch_anywhere(world, from, launch, null):
		ball.free()


@rpc("authority", "reliable")
func _bastion_burst_rpc(at: Vector3, radius: float) -> void:
	if _is_host():
		return
	_play_bastion_burst(at, radius)
