class_name CrawlerMobSense
extends RefCounted

## Shared per-physics-frame reads and a swarm director for crawler mobs.
##
## Each body used to walk the player, charm, field, and keep-out groups
## every tick. With a crowd that is O(n) group scans per mob. This board
## gathers those lists once, then every hunter reads the same snapshot.
## Positions stay live so agro range and attacks do not change.
##
## Far bodies stay cheap: LOD, a think budget, and an attack token keep
## unique shot logic on the nearest hunters so a denser field does not
## plan every attack on the same physics frame.

const MOB_GROUP := &"crawler_mobs"
const PLAYER_GROUP := &"network_players"
const SAFE_GROUP := &"crawler_safe_zones"
const RING_GROUP := &"crawler_city_rings"
const FIELD_GROUP := &"ability_fields"
const LINGER_GROUP := &"crawler_lingers"
const MONUMENT_GROUP := &"patch_monuments"
const OVERLAY_GROUP := &"land_patch_overlay"

static var _physics_frame := -1
static var _players: Array = []
static var _live_mobs: Array = []
static var _charmed: Array = []
static var _safe_boxes: Array = []
static var _city_rings: Array = []
static var _fields: Array = []
static var _clouds: Array = []
static var _monuments: Array = []
static var _overlay: Node
static var _ticked := 0
static var _chasing := 0
static var _ai_usec := 0
static var _last_live := -1
static var _last_chase := -1
static var _think_left := 0
static var _attack_left := 0
static var _player_at := Vector3.ZERO


static func begin_frame(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame != _physics_frame:
		_publish()
		var rescan := _physics_frame < 0
		_physics_frame = frame
		_ticked = 0
		_chasing = 0
		_ai_usec = 0
		_think_left = CrawlerRules.MOB_THINK_BUDGET
		_attack_left = CrawlerRules.MOB_ATTACK_BUDGET
		_refresh(tree, rescan)
		return


static func invalidate() -> void:
	_physics_frame = -1


static func players() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for item: Variant in _players:
		var player := _node3d(item)
		if player != null:
			found.append(player)
	return found


static func charmed_count() -> int:
	return _charmed.size()


static func live_count() -> int:
	return _live_mobs.size()


static func nearest_player(from: Node3D) -> Node3D:
	if not _living(from) or not from.is_inside_tree():
		return null
	begin_frame(from.get_tree())
	var nearest: Node3D
	var nearest_squared := INF
	var from_world := DamageHit.game_world_of(from)
	for item: Variant in _players:
		var player := _node3d(item)
		if player == null:
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		if not DamageHit.in_same_world(from, player) and from_world != null:
			continue
		var away := from.global_position.distance_squared_to(player.global_position)
		if away < nearest_squared:
			nearest_squared = away
			nearest = player
	return nearest


static func player_in_city(player: Node3D) -> bool:
	if not _living(player) or not player.is_inside_tree():
		return false
	begin_frame(player.get_tree())
	var saw_live := false
	for item: Variant in _city_rings:
		var ring := _city_ring(item)
		if ring == null:
			continue
		saw_live = true
		if ring.contains_player(player):
			return true
	if not saw_live:
		return CrawlerCityRing.contains_any(player)
	return false


static func nearest_charmed(from: Node) -> Node:
	if not _living(from) or not from.is_inside_tree():
		return null
	begin_frame(from.get_tree())
	if _charmed.is_empty():
		return null
	return _nearest_from(from, _charmed, true)


static func nearest_other(from: Node) -> Node:
	if not _living(from) or not from.is_inside_tree():
		return null
	begin_frame(from.get_tree())
	return _nearest_from(from, _live_mobs, false)


static func field_slow(from: Node, at: Vector3) -> float:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return 1.0
	begin_frame(from.get_tree())
	var field_scale := 1.0
	var linger_scale := 1.0
	for item: Variant in _fields:
		var field := _field(item)
		if field != null and field.contains(at):
			field_scale = minf(field_scale, field.speed_mul())
	for item: Variant in _clouds:
		var cloud := _cloud(item)
		if cloud != null and cloud.contains(at):
			linger_scale = minf(linger_scale, cloud.speed_mul())
	return field_scale * linger_scale


static func keepout_blocks(from: Node, at: Vector3) -> bool:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return false
	begin_frame(from.get_tree())
	for item: Variant in _safe_boxes:
		var zone := _safe_box(item)
		if zone != null and zone.blocks_point(at):
			return true
	for item: Variant in _city_rings:
		var ring := _city_ring(item)
		if ring != null and ring.blocks_near(at):
			return true
	var overlay := _overlay_node()
	return overlay != null and overlay.keeps_mobs_out(at)


static func monument_blocks(from: Node, at: Vector3) -> bool:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return false
	begin_frame(from.get_tree())
	for item: Variant in _monuments:
		var site := _monument(item)
		if site != null and site.blocks_spawn(at):
			return true
	return false


static func keep_clear(mob: Node3D) -> void:
	if not _living(mob) or not mob.is_inside_tree():
		return
	begin_frame(mob.get_tree())
	var body := _body(mob)
	var at := mob.global_position
	var pad := 0.7
	if mob.has_method(&"combat_radius"):
		pad = float(mob.call(&"combat_radius"))
	var velocity := Vector3.ZERO
	if body != null:
		velocity = body.velocity
	for item: Variant in _safe_boxes:
		var zone := _safe_box(item)
		if zone == null or not zone.blocks_point(at):
			continue
		var away := zone.push_out(at, pad + 1.2)
		mob.global_position = away
		at = away
		var out := (at - zone.zone_centre()).normalized()
		if out.length_squared() > 0.0001:
			velocity = out * maxf(velocity.length(), 8.0)
	for item: Variant in _city_rings:
		var ring := _city_ring(item)
		if ring == null or not ring.blocks_near(at):
			continue
		var cleared := ring.push_out(at, pad + 1.6)
		mob.global_position = cleared
		at = cleared
		var centre := ring.zone_centre()
		var up := ring.world_up()
		var out_ring := at - centre
		out_ring -= up * out_ring.dot(up)
		if out_ring.length_squared() > 0.0001:
			velocity = out_ring.normalized() * maxf(velocity.length(), 8.0)
	var overlay := _overlay_node()
	if overlay == null or not overlay.keeps_mobs_out(at):
		if body != null:
			body.velocity = velocity
		return
	var pushed := overlay.push_out_of_cities(at, pad + 1.6)
	var out_city := pushed - at
	mob.global_position = pushed
	if out_city.length_squared() > 0.0001:
		velocity = out_city.normalized() * maxf(velocity.length(), 8.0)
	if body != null:
		body.velocity = velocity


static func note_spawned(mob: Node) -> void:
	if not _living(mob):
		return
	if not _live_mobs.has(mob):
		_live_mobs.append(mob)
	if mob.has_method(&"is_charmed") and bool(mob.call(&"is_charmed")) \
			and not _charmed.has(mob):
		_charmed.append(mob)
	_write_gauges()


static func note_gone(mob: Node) -> void:
	if mob == null:
		return
	_live_mobs.erase(mob)
	_charmed.erase(mob)
	_write_gauges()


static func note_charmed(mob: Node, on: bool) -> void:
	if not _living(mob):
		return
	if on:
		note_spawned(mob)
		if not _charmed.has(mob):
			_charmed.append(mob)
	else:
		_charmed.erase(mob)
	_write_gauges()


static func note_tick(mob: Node, usec: int) -> void:
	_ticked += 1
	if _living(mob) and bool(mob.get("chase")):
		_chasing += 1
	_ai_usec += maxi(usec, 0)
	_write_gauges()


static func player_anchor() -> Vector3:
	return _player_at


static func lod_of(from: Node3D) -> int:
	if not _living(from) or not from.is_inside_tree():
		return CrawlerRules.MOB_LOD_COLD
	begin_frame(from.get_tree())
	return CrawlerRules.mob_lod(from.global_position.distance_to(_player_at))


static func take_think(_mob: Node, chasing: bool) -> bool:
	if _think_left <= 0:
		return false
	if not chasing and _think_left <= 2:
		return false
	_think_left -= 1
	return true


static func take_attack(_kind: String = "") -> bool:
	if _attack_left <= 0:
		return false
	_attack_left -= 1
	return true


static func think_left() -> int:
	return _think_left


static func attack_left() -> int:
	return _attack_left


static func _nearest_from(from: Node, pack: Array, charmed_only: bool) -> Node:
	var nearest: Node
	var nearest_squared := INF
	var from_world := DamageHit.game_world_of(from)
	var origin := Vector3.ZERO
	var from_body := _node3d(from)
	if from_body != null:
		origin = from_body.global_position
	for item: Variant in pack:
		var mob := _node(item)
		if mob == null or mob == from:
			continue
		if mob.has_method(&"is_alive") and not bool(mob.call(&"is_alive")):
			continue
		if not DamageHit.in_same_world(from, mob) and from_world != null:
			continue
		if charmed_only and mob.has_method(&"is_charmed") \
				and not bool(mob.call(&"is_charmed")):
			continue
		var body := _node3d(mob)
		if body == null:
			continue
		var away := origin.distance_squared_to(body.global_position)
		if away < nearest_squared:
			nearest_squared = away
			nearest = mob
	return nearest


static func _refresh(tree: SceneTree, rescan := false) -> void:
	_players.clear()
	_fields.clear()
	_clouds.clear()
	if tree == null:
		_player_at = Vector3.ZERO
		_write_gauges()
		return
	for player_variant: Variant in tree.get_nodes_in_group(PLAYER_GROUP):
		var player := _node3d(player_variant)
		if player == null:
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		_players.append(player)
	_anchor_players()
	for field_variant: Variant in tree.get_nodes_in_group(FIELD_GROUP):
		var field := _field(field_variant)
		if field != null:
			_fields.append(field)
	for cloud_variant: Variant in tree.get_nodes_in_group(LINGER_GROUP):
		var cloud := _cloud(cloud_variant)
		if cloud != null:
			_clouds.append(cloud)
	_refresh_static(tree)
	if rescan:
		_rescan_mobs(tree)
	else:
		_prune_mobs()
	_write_gauges()


static func _anchor_players() -> void:
	if _players.is_empty():
		_player_at = Vector3.ZERO
		return
	var player := _node3d(_players[0])
	if player == null:
		_player_at = Vector3.ZERO
		return
	if player.has_method(&"combat_position"):
		var at: Variant = player.call(&"combat_position")
		if at is Vector3 and (at as Vector3).is_finite():
			_player_at = at
			return
	_player_at = player.global_position


static func _refresh_static(tree: SceneTree) -> void:
	_safe_boxes.clear()
	_city_rings.clear()
	_monuments.clear()
	_overlay = null
	for zone_variant: Variant in tree.get_nodes_in_group(SAFE_GROUP):
		var zone := _safe_box(zone_variant)
		if zone != null:
			_safe_boxes.append(zone)
	for ring_variant: Variant in tree.get_nodes_in_group(RING_GROUP):
		var ring := _city_ring(ring_variant)
		if ring != null:
			_city_rings.append(ring)
	for site_variant: Variant in tree.get_nodes_in_group(MONUMENT_GROUP):
		var site := _monument(site_variant)
		if site != null:
			_monuments.append(site)
	var overlay_variant: Variant = tree.get_first_node_in_group(OVERLAY_GROUP)
	_overlay = _node(overlay_variant)


static func _rescan_mobs(tree: SceneTree) -> void:
	_live_mobs.clear()
	_charmed.clear()
	for node_variant: Variant in tree.get_nodes_in_group(MOB_GROUP):
		var mob := _node(node_variant)
		if mob == null or (mob.has_method(&"is_alive") and not bool(mob.call(&"is_alive"))):
			continue
		_live_mobs.append(mob)
		if mob.has_method(&"is_charmed") and bool(mob.call(&"is_charmed")):
			_charmed.append(mob)


static func _prune_mobs() -> void:
	if _live_mobs.is_empty() and _charmed.is_empty():
		return
	var keep: Array = []
	for item: Variant in _live_mobs:
		var mob := _node(item)
		if mob == null or not mob.is_inside_tree():
			continue
		if mob.has_method(&"is_alive") and not bool(mob.call(&"is_alive")):
			continue
		keep.append(mob)
	_live_mobs = keep
	var bait: Array = []
	for item: Variant in _charmed:
		var mob := _node(item)
		if mob == null or not _live_mobs.has(mob):
			continue
		bait.append(mob)
	_charmed = bait


static func _living(node: Variant) -> bool:
	return node != null and is_instance_valid(node)


static func _node(node: Variant) -> Node:
	if not _living(node):
		return null
	return node as Node


static func _node3d(node: Variant) -> Node3D:
	if not _living(node):
		return null
	return node as Node3D


static func _body(node: Variant) -> CharacterBody3D:
	if not _living(node):
		return null
	return node as CharacterBody3D


static func _city_ring(node: Variant) -> CrawlerCityRing:
	if not _living(node):
		return null
	return node as CrawlerCityRing


static func _safe_box(node: Variant) -> CrawlerSafeBox:
	if not _living(node):
		return null
	return node as CrawlerSafeBox


static func _field(node: Variant) -> CrawlerFieldVolume:
	if not _living(node):
		return null
	return node as CrawlerFieldVolume


static func _cloud(node: Variant) -> CrawlerLingerCloud:
	if not _living(node):
		return null
	return node as CrawlerLingerCloud


static func _monument(node: Variant) -> PatchMonument:
	if not _living(node):
		return null
	return node as PatchMonument


static func _overlay_node() -> LandPatchOverlay:
	if not _living(_overlay):
		_overlay = null
		return null
	return _overlay as LandPatchOverlay


static func _write_gauges() -> void:
	LagTracker.set_gauge("mobs", float(_live_mobs.size()))
	LagTracker.set_gauge("mob_ai", float(_ai_usec) * 0.001)


static func _publish() -> void:
	if _physics_frame < 0:
		return
	var live := _live_mobs.size()
	var ai_ms := float(_ai_usec) * 0.001
	_write_gauges()
	if live != _last_live and (_last_live < 0 or absi(live - _last_live) >= 8):
		LagTracker.note_throttled("mobs", "mob_count",
			"%d crawler mobs  %d chasing  %d charmed" % [
				live, _chasing, _charmed.size()], 0.35)
	if _chasing != _last_chase and (_last_chase < 0 or absi(_chasing - _last_chase) >= 6):
		LagTracker.note_throttled("mobs", "mob_chase",
			"%d chasing the player (%d live)" % [_chasing, live], 0.35)
	if ai_ms >= 4.0:
		LagTracker.note_throttled("mobs", "mob_ai",
			"mob targeting %.1f ms  %d live  %d chase" % [ai_ms, live, _chasing],
			0.4, {
				"ai_ms": snappedf(ai_ms, 0.01),
				"live": live,
				"ticked": _ticked,
				"chase": _chasing,
				"charm": _charmed.size(),
				"players": _players.size(),
			})
	_last_live = live
	_last_chase = _chasing
