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
## plan every attack on the same physics frame. Seek, climb, and
## separation run once for the whole pack.

const MOB_GROUP := &"crawler_mobs"
const PLAYER_GROUP := &"network_players"
const SAFE_GROUP := &"crawler_safe_zones"
const RING_GROUP := &"crawler_city_rings"
const FIELD_GROUP := &"ability_fields"
const LINGER_GROUP := &"crawler_lingers"
const MONUMENT_GROUP := &"patch_monuments"
const OVERLAY_GROUP := &"land_patch_overlay"
const PAD_GROUP := &"crawler_spawn_pads"
const BOSS_GROUP := &"crawler_boss"
const THINK_LOG_GAP := 1.5
const GROUND_SHARE := 0.22

static var _physics_frame := -1
static var _players: Array = []
static var _live_mobs: Array = []
static var _charmed: Array = []
static var _safe_boxes: Array = []
static var _city_rings: Array = []
static var _fields: Array = []
static var _clouds: Array = []
static var _monuments: Array = []
static var _spawn_pads: Array = []
static var _bosses: Array = []
static var _overlay: Node
static var _ticked := 0
static var _chasing := 0
static var _ai_usec := 0
static var _last_live := -1
static var _last_chase := -1
static var _think_left := 0
static var _attack_left := 0
static var _think_cap := 0
static var _attack_cap := 0
static var _window_think_cap := 0
static var _window_attack_cap := 0
static var _player_at := Vector3.ZERO
static var _think_usec := 0
static var _hot := 0
static var _warm := 0
static var _cold := 0
static var _windup := 0
static var _frame_think_ok := 0
static var _frame_think_denied := 0
static var _frame_attack_ok := 0
static var _frame_attack_denied := 0
static var _pile := 0
static var _phys_pairs := 0
static var _phys_bodies := 0
static var _window_started := -1.0
static var _window_frames := 0
static var _window_think_ok := 0
static var _window_think_denied := 0
static var _window_attack_ok := 0
static var _window_attack_denied := 0
static var _window_live_sum := 0
static var _window_chase_sum := 0
static var _window_windup_sum := 0
static var _window_hot_sum := 0
static var _window_warm_sum := 0
static var _window_cold_sum := 0
static var _window_pile_sum := 0
static var _window_ai_usec := 0
static var _window_think_usec := 0
static var _peak_live := 0
static var _peak_chase := 0
static var _peak_windup := 0
static var _peak_pile := 0
static var _peak_pairs := 0
static var _peak_bodies := 0
static var _peak_ai_ms := 0.0
static var _think_kinds: Dictionary = {}
static var _attack_kinds: Dictionary = {}
static var _deny_think_kinds: Dictionary = {}
static var _deny_attack_kinds: Dictionary = {}
static var _directed_frame := -1
static var _static_frame := -1
static var _city_frame := -1
static var _pad_frame := -1
static var _keep_frame := -1
static var _player_city := {}
static var _player_pad := {}
static var _player_keep := {}
static var _ground_share_frame := -1
static var _ground_share: Dictionary = {}


static func begin_frame(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _physics_frame:
		return
	_publish()
	var rescan := _physics_frame < 0
	_physics_frame = frame
	_ticked = 0
	_chasing = 0
	_ai_usec = 0
	_think_usec = 0
	_hot = 0
	_warm = 0
	_cold = 0
	_windup = 0
	_frame_think_ok = 0
	_frame_think_denied = 0
	_frame_attack_ok = 0
	_frame_attack_denied = 0
	_think_cap = CrawlerRules.think_budget_for(maxi(_last_chase, 0))
	_attack_cap = CrawlerRules.attack_budget_for(maxi(_last_chase, 0))
	_think_left = _think_cap
	_attack_left = _attack_cap
	_refresh(tree, rescan, frame)


static func ensure_frame(tree: SceneTree) -> void:
	if _physics_frame != Engine.get_physics_frames():
		begin_frame(tree)


static func invalidate() -> void:
	_physics_frame = -1
	_last_chase = -1
	_last_live = -1
	_directed_frame = -1
	_static_frame = -1
	_city_frame = -1
	_pad_frame = -1
	_keep_frame = -1
	_player_city.clear()
	_player_pad.clear()
	_player_keep.clear()
	_ground_share_frame = -1
	_ground_share.clear()
	_reset_think_window(-1.0)
	CombatantSense.invalidate()


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
	ensure_frame(from.get_tree())
	return _nearest_cached_player(from.global_position)


static func player_in_castle_keep(player: Node3D) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var frame := Engine.get_physics_frames()
	if frame != _keep_frame:
		_keep_frame = frame
		_player_keep.clear()
	var id := player.get_instance_id()
	if _player_keep.has(id):
		return bool(_player_keep[id])
	var inside := CrawlerRules.in_castle_keep(player.global_position)
	_player_keep[id] = inside
	return inside


static func player_in_city(player: Node3D) -> bool:
	if not _living(player) or not player.is_inside_tree():
		return false
	ensure_frame(player.get_tree())
	var frame := Engine.get_physics_frames()
	if frame != _city_frame:
		_city_frame = frame
		_player_city.clear()
	var id := player.get_instance_id()
	if _player_city.has(id):
		return bool(_player_city[id])
	var inside := false
	var saw_live := false
	for item: Variant in _city_rings:
		var ring := _city_ring(item)
		if ring == null:
			continue
		saw_live = true
		if ring.contains_player(player):
			inside = true
			break
	if not saw_live:
		inside = CrawlerCityRing.contains_any(player)
	_player_city[id] = inside
	return inside


static func player_on_spawn_pad(player: Node3D) -> bool:
	if not _living(player) or not player.is_inside_tree():
		return false
	ensure_frame(player.get_tree())
	var frame := Engine.get_physics_frames()
	if frame != _pad_frame:
		_pad_frame = frame
		_player_pad.clear()
	var id := player.get_instance_id()
	if _player_pad.has(id):
		return bool(_player_pad[id])
	var inside := false
	for item: Variant in _spawn_pads:
		var pad := _spawn_pad(item)
		if pad != null and pad.shelters_standing(player.global_position):
			inside = true
			break
	_player_pad[id] = inside
	return inside


static func pad_holds_field() -> bool:
	for item: Variant in _spawn_pads:
		var pad := _spawn_pad(item)
		if pad != null and pad.holds_field():
			return true
	return false


static func boss_protects(player: Node) -> bool:
	if not _living(player):
		return false
	for item: Variant in _bosses:
		var boss := _node(item)
		if boss != null and boss.has_method(&"protects") \
				and bool(boss.call(&"protects", player)):
			return true
	return false


static func nearest_charmed(from: Node) -> Node:
	if not _living(from) or not from.is_inside_tree():
		return null
	ensure_frame(from.get_tree())
	if _charmed.is_empty():
		return null
	return _nearest_from(from, _charmed, true)


static func nearest_other(from: Node) -> Node:
	if not _living(from) or not from.is_inside_tree():
		return null
	ensure_frame(from.get_tree())
	return _nearest_from(from, _live_mobs, false)


static func field_scale(from: Node, at: Vector3) -> float:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return 1.0
	var tree := from.get_tree()
	ensure_frame(tree)
	_sync_fields(tree)
	var scale := 1.0
	for item: Variant in _fields:
		var field := _field(item)
		if field != null and field.contains(at):
			scale = minf(scale, field.speed_mul())
	return scale


static func linger_scale(from: Node, at: Vector3) -> float:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return 1.0
	var tree := from.get_tree()
	ensure_frame(tree)
	_sync_clouds(tree)
	var scale := 1.0
	for item: Variant in _clouds:
		var cloud := _cloud(item)
		if cloud != null and cloud.contains(at):
			scale = minf(scale, cloud.speed_mul())
	return scale


static func field_slow(from: Node, at: Vector3) -> float:
	return field_scale(from, at) * linger_scale(from, at)


static func keepout_blocks(from: Node, at: Vector3) -> bool:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return false
	ensure_frame(from.get_tree())
	for item: Variant in _safe_boxes:
		var zone := _safe_box(item)
		if zone != null and zone.blocks_point(at):
			return true
	for item: Variant in _city_rings:
		var ring := _city_ring(item)
		if ring != null and ring.clears_patch_mobs_at(at, _players):
			return true
	var overlay := _overlay_node()
	return overlay != null and overlay.keeps_mobs_out(at)


static func monument_blocks(from: Node, at: Vector3) -> bool:
	if not _living(from) or not from.is_inside_tree() or not at.is_finite():
		return false
	ensure_frame(from.get_tree())
	for item: Variant in _monuments:
		var site := _monument(item)
		if site != null and site.blocks_spawn(at):
			return true
	return false


static func keep_clear(mob: Node3D) -> void:
	if not _living(mob) or not mob.is_inside_tree():
		return
	ensure_frame(mob.get_tree())
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


static func note_gone(mob: Node) -> void:
	if mob == null:
		return
	_live_mobs.erase(mob)
	_charmed.erase(mob)


static func note_charmed(mob: Node, on: bool) -> void:
	if not _living(mob):
		return
	if on:
		note_spawned(mob)
		if not _charmed.has(mob):
			_charmed.append(mob)
	else:
		_charmed.erase(mob)


static func note_tick(
		mob: Node,
		usec: int,
		lod := -1,
		_thought := false,
		attacking := false
	) -> void:
	_ticked += 1
	if _living(mob) and bool(mob.get("chase")):
		_chasing += 1
	if attacking:
		_windup += 1
	if lod == CrawlerRules.MOB_LOD_HOT:
		_hot += 1
	elif lod == CrawlerRules.MOB_LOD_WARM:
		_warm += 1
	elif lod == CrawlerRules.MOB_LOD_COLD:
		_cold += 1
	_ai_usec += maxi(usec, 0)


static func note_think_usec(usec: int) -> void:
	_think_usec += maxi(usec, 0)


static func player_anchor() -> Vector3:
	return _player_at


static func lod_of(from: Node3D) -> int:
	if not _living(from) or not from.is_inside_tree():
		return CrawlerRules.MOB_LOD_COLD
	ensure_frame(from.get_tree())
	return lod_at(from.global_position)


static func lod_at(at: Vector3) -> int:
	return CrawlerRules.mob_lod_gap2(at.distance_squared_to(_player_at))


static func peek_ground(from: Vector3) -> Vector3:
	if not from.is_finite():
		return Vector3.INF
	var frame := Engine.get_physics_frames()
	if frame != _ground_share_frame:
		_ground_share_frame = frame
		_ground_share.clear()
	return _ground_share.get(_ground_key(from), Vector3.INF)


static func store_ground(from: Vector3, hit: Vector3) -> void:
	if not from.is_finite() or not hit.is_finite():
		return
	var frame := Engine.get_physics_frames()
	if frame != _ground_share_frame:
		_ground_share_frame = frame
		_ground_share.clear()
	_ground_share[_ground_key(from)] = hit


static func _ground_key(from: Vector3) -> Vector3i:
	var span := GROUND_SHARE
	return Vector3i(
		floori(from.x / span), floori(from.y / span), floori(from.z / span))


static func take_think(mob: Node, chasing: bool) -> bool:
	var kind := _kind_of(mob)
	if _think_left <= 0 or (not chasing and _think_left <= 2):
		_frame_think_denied += 1
		_window_think_denied += 1
		_count_kind(_deny_think_kinds, kind)
		return false
	_think_left -= 1
	_frame_think_ok += 1
	_window_think_ok += 1
	_count_kind(_think_kinds, kind)
	return true


static func was_directed(mob: Node) -> bool:
	if mob == null or not (mob is CrawlerMob):
		return false
	return (mob as CrawlerMob).directed_frame == _directed_frame \
		and _directed_frame == Engine.get_physics_frames()


static func shot_targets(charmed: bool) -> Array:
	return _live_mobs if charmed else _players


static func any_chasing_kind(kind: String, except: Node = null) -> bool:
	return chasing_kind_count(kind, except) > 0


static func chasing_kind_count(kind: String, except: Node = null) -> int:
	if kind.is_empty():
		return 0
	var count := 0
	for item: Variant in _live_mobs:
		var mob := _node(item) as CrawlerMob
		if mob == null or mob == except or not mob.is_alive():
			continue
		if mob.wild_kind() == kind and mob.chase:
			count += 1
	return count


static func rouse_kinds(kinds: PackedStringArray, except: Node = null) -> void:
	if kinds.is_empty():
		return
	for item: Variant in _live_mobs:
		var mob := _node(item) as CrawlerMob
		if mob == null or mob == except or not mob.is_alive():
			continue
		if not mob.is_persistent() or not kinds.has(mob.wild_kind()):
			continue
		mob.chase = true
		mob.ever_chased = true
		mob.idle_seconds = 0.0


static func each_kind(kind: String, except: Node = null) -> Array:
	var out: Array = []
	if kind.is_empty():
		return out
	for item: Variant in _live_mobs:
		var mob := _node(item) as CrawlerMob
		if mob == null or mob == except or not mob.is_alive():
			continue
		if mob.wild_kind() == kind:
			out.append(mob)
	return out


## One loop writes seek, climb, and separation for the whole pack. Unique
## aim/fire still lives on the think-token bodies.
static func direct_horde(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _directed_frame:
		return
	_directed_frame = frame
	var pack: Array[CrawlerMob] = []
	var cells := {}
	for item: Variant in _live_mobs:
		var mob := item as CrawlerMob
		if mob == null or not is_instance_valid(mob) or not mob.is_alive():
			continue
		pack.append(mob)
		var key := _horde_cell(mob.global_position)
		if not cells.has(key):
			cells[key] = []
		var occupants: Array = cells[key]
		occupants.append(mob)
	if pack.is_empty():
		return
	var stride := maxi(CrawlerRules.MOB_COLD_STRIDE, 1)
	var warm_stride := maxi(CrawlerRules.MOB_WARM_STRIDE, 1)
	var hunt := _nearest_cached_player(_player_at)
	var hunt_at := hunt.global_position if hunt != null else _player_at
	var hunt_city := hunt != null and (
		player_in_city(hunt) or player_on_spawn_pad(hunt))
	var reach := CrawlerRules.HORDE_SEPARATION
	var reach2 := reach * reach
	var sep_cap := CrawlerRules.HORDE_SEPARATION_CAP
	var sep_cap2 := sep_cap * sep_cap
	var sep_push := CrawlerRules.HORDE_SEPARATION_PUSH
	for mob in pack:
		var at := mob.global_position
		var lod := CrawlerRules.mob_lod_gap2(at.distance_squared_to(_player_at))
		var slot := _directed_frame + mob.get_instance_id()
		var need_sep := lod == CrawlerRules.MOB_LOD_HOT \
			or (lod == CrawlerRules.MOB_LOD_WARM and slot % warm_stride == 0) \
			or (lod == CrawlerRules.MOB_LOD_COLD and slot % stride == 0)
		if need_sep:
			var push := Vector3.ZERO
			var here := _horde_cell(at)
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					for oz in range(-1, 2):
						var neighbor: Variant = cells.get(
							here + Vector3i(ox, oy, oz))
						if neighbor == null:
							continue
						var nearby: Array = neighbor
						for other_variant: Variant in nearby:
							var other := other_variant as CrawlerMob
							if other == null or other == mob:
								continue
							var along := at - other.global_position
							var away2 := along.length_squared()
							if away2 < 0.0001 or away2 > reach2:
								continue
							var away := sqrt(away2)
							push += along * ((reach - away) / away)
			var separate := push * sep_push
			if separate.length_squared() > sep_cap2:
				separate = separate.normalized() * sep_cap
			mob.director_sep = separate
		mob.director_push = mob.director_sep
		mob.directed_frame = _directed_frame
		mob.set_director_lod(lod)
		if hunt != null and not hunt_city and not mob.chase \
				and not mob.persistent:
			var gap2 := at.distance_squared_to(hunt_at)
			if CrawlerRules.field_ring_should_engage_gap2(gap2, mob.wild_kind()):
				mob.chase = true
				mob.ever_chased = true
				mob.idle_seconds = 0.0
				if mob.hunt_stance == CrawlerHunt.Stance.IDLE \
						or mob.hunt_stance == CrawlerHunt.Stance.DEAGRO:
					mob.hunt_stance = CrawlerHunt.Stance.AGRO
		if lod == CrawlerRules.MOB_LOD_COLD:
			var inbound := mob.is_glorb() and not mob.chase \
				and mob.inbound_heading.length_squared() > 0.0001
			var period := stride if (mob.chase or inbound) else stride * 2
			var steer := slot % period == 0
			if inbound and mob.velocity.length_squared() < 0.25:
				steer = true
			if not steer and mob.velocity.length_squared() < 0.010 \
					and mob.director_sep.length_squared() < 0.0001:
				continue
			var step := delta * float(period) if steer else 0.0
			mob.director_cold_tick(delta, step, steer, hunt, hunt_city)
			continue
		if lod == CrawlerRules.MOB_LOD_WARM:
			var inbound := mob.is_glorb() and not mob.chase \
				and mob.inbound_heading.length_squared() > 0.0001
			var warm_period := warm_stride if (mob.chase or inbound) else warm_stride * 2
			var warm_steer := slot % warm_period == 0
			if inbound and mob.velocity.length_squared() < 0.25:
				warm_steer = true
			if not warm_steer and mob.velocity.length_squared() < 0.010 \
					and mob.director_sep.length_squared() < 0.0001:
				continue
			var warm_step := delta * float(warm_period) if warm_steer else 0.0
			mob.director_warm_tick(delta, warm_step, warm_steer, hunt, hunt_city)
			continue


static func _horde_cell(at: Vector3) -> Vector3i:
	var span := maxf(CrawlerRules.HORDE_CELL, 0.5)
	return Vector3i(
		floori(at.x / span), floori(at.y / span), floori(at.z / span))


static func _nearest_cached_player(from: Vector3) -> Node3D:
	var nearest: Node3D
	var nearest2 := INF
	for item: Variant in _players:
		var player := _node3d(item)
		if player == null:
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		if player_on_spawn_pad(player):
			continue
		var away := player.global_position.distance_squared_to(from)
		if away < nearest2:
			nearest2 = away
			nearest = player
	return nearest


static func take_attack(kind: String = "") -> bool:
	# Bite tokens only pace the close swarm. Rangers, vespers, and guns
	# are few enough that a gloam flock must not eat their windup.
	var role := CrawlerHunt.role(kind)
	if role == CrawlerHunt.Role.FLY_RANGE \
			or role == CrawlerHunt.Role.GROUND_RANGE:
		_frame_attack_ok += 1
		_window_attack_ok += 1
		_count_kind(_attack_kinds, kind)
		return true
	if _attack_left <= 0:
		_frame_attack_denied += 1
		_window_attack_denied += 1
		_count_kind(_deny_attack_kinds, kind)
		return false
	_attack_left -= 1
	_frame_attack_ok += 1
	_window_attack_ok += 1
	_count_kind(_attack_kinds, kind)
	return true


static func director_counts() -> Dictionary:
	return {
		"think_ok": _window_think_ok,
		"think_denied": _window_think_denied,
		"attack_ok": _window_attack_ok,
		"attack_denied": _window_attack_denied,
		"frames": _window_frames,
		"frame_think_ok": _frame_think_ok,
		"frame_think_denied": _frame_think_denied,
		"frame_attack_ok": _frame_attack_ok,
		"frame_attack_denied": _frame_attack_denied,
		"think_budget": _think_cap,
		"attack_budget": _attack_cap,
		"chase": _chasing,
		"ai_usec": _ai_usec,
		"pile": _count_pile(),
		"phys_pairs": _phys_pairs,
		"phys_bodies": _phys_bodies,
		"think_kinds": _think_kinds.duplicate(),
		"attack_kinds": _attack_kinds.duplicate(),
		"deny_think_kinds": _deny_think_kinds.duplicate(),
		"deny_attack_kinds": _deny_attack_kinds.duplicate(),
	}


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


static func _sync_fields(tree: SceneTree) -> void:
	if tree == null:
		return
	if tree.get_node_count_in_group(FIELD_GROUP) == _fields.size():
		return
	_fields.clear()
	for field_variant: Variant in tree.get_nodes_in_group(FIELD_GROUP):
		var field := _field(field_variant)
		if field != null:
			_fields.append(field)


static func _sync_clouds(tree: SceneTree) -> void:
	if tree == null:
		return
	if tree.get_node_count_in_group(LINGER_GROUP) == _clouds.size():
		return
	_clouds.clear()
	for cloud_variant: Variant in tree.get_nodes_in_group(LINGER_GROUP):
		var cloud := _cloud(cloud_variant)
		if cloud != null:
			_clouds.append(cloud)


static func _refresh(tree: SceneTree, rescan := false, frame := -1) -> void:
	_players.clear()
	_fields.clear()
	_clouds.clear()
	if tree == null:
		_player_at = Vector3.ZERO
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
	if rescan or _static_frame < 0 \
			or (frame - _static_frame) >= 8 or _city_rings.is_empty():
		_refresh_static(tree)
		_static_frame = maxi(frame, 0)
	if rescan:
		_rescan_mobs(tree)
	else:
		_prune_mobs()
	_spawn_pads.clear()
	for pad_variant: Variant in tree.get_nodes_in_group(PAD_GROUP):
		var pad := _spawn_pad(pad_variant)
		if pad != null:
			_spawn_pads.append(pad)
	_watch_spawn_pads()


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
	_spawn_pads.clear()
	_bosses.clear()
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
	for pad_variant: Variant in tree.get_nodes_in_group(PAD_GROUP):
		var pad := _spawn_pad(pad_variant)
		if pad != null:
			_spawn_pads.append(pad)
	for boss_variant: Variant in tree.get_nodes_in_group(BOSS_GROUP):
		var boss := _node(boss_variant)
		if boss != null:
			_bosses.append(boss)
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


static func _spawn_pad(node: Variant) -> CrawlerSpawnPad:
	if not _living(node):
		return null
	return node as CrawlerSpawnPad


static func _watch_spawn_pads() -> void:
	if _spawn_pads.is_empty():
		return
	for item: Variant in _spawn_pads:
		var pad := _spawn_pad(item)
		if pad == null or not pad.holds_field():
			continue
		for player_item: Variant in _players:
			var player := _node3d(player_item)
			if player != null:
				pad.notice_player(player.global_position)


static func _overlay_node() -> LandPatchOverlay:
	if not _living(_overlay):
		_overlay = null
		return null
	return _overlay as LandPatchOverlay


static func _publish() -> void:
	if _physics_frame < 0:
		return
	_window_frames += 1
	if (_window_frames & 7) == 0:
		_pile = _count_pile()
	_phys_pairs = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	_phys_bodies = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	_last_live = _live_mobs.size()
	_last_chase = _chasing
	var now := float(Time.get_ticks_msec()) * 0.001
	if _window_started < 0.0:
		_window_started = now
	if now - _window_started >= THINK_LOG_GAP:
		_reset_think_window(now)


static func _reset_think_window(now: float) -> void:
	_window_started = now
	_window_frames = 0
	_window_think_ok = 0
	_window_think_denied = 0
	_window_attack_ok = 0
	_window_attack_denied = 0
	_window_live_sum = 0
	_window_chase_sum = 0
	_window_windup_sum = 0
	_window_hot_sum = 0
	_window_warm_sum = 0
	_window_cold_sum = 0
	_window_pile_sum = 0
	_window_ai_usec = 0
	_window_think_usec = 0
	_window_think_cap = 0
	_window_attack_cap = 0
	_peak_live = 0
	_peak_chase = 0
	_peak_windup = 0
	_peak_pile = 0
	_peak_pairs = 0
	_peak_bodies = 0
	_peak_ai_ms = 0.0
	_think_kinds.clear()
	_attack_kinds.clear()
	_deny_think_kinds.clear()
	_deny_attack_kinds.clear()


static func _count_pile() -> int:
	if _live_mobs.is_empty():
		return 0
	if _players.is_empty() and _player_at == Vector3.ZERO:
		return 0
	var piled := 0
	var reach2 := 3.61
	for item: Variant in _live_mobs:
		var mob := _node3d(item)
		if mob != null \
				and mob.global_position.distance_squared_to(_player_at) <= reach2:
			piled += 1
	return piled


static func _kind_of(mob: Node) -> String:
	if not _living(mob) or not mob.has_method(&"wild_kind"):
		return ""
	return str(mob.call(&"wild_kind"))


static func _count_kind(bag: Dictionary, kind: String) -> void:
	var key := kind if not kind.is_empty() else "?"
	bag[key] = int(bag.get(key, 0)) + 1
