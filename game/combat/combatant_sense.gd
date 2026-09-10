class_name CombatantSense
extends RefCounted

## One physics-frame board of live combatants for shots, homing, and lingering
## clouds.
##
## Each projectile used to walk the combatant group and call combat_position,
## combat_faction, and is_alive on every body, every tick. A bubble swarm
## turns that into O(shots × bodies). This gathers the live set once; shots
## then read cached points and radii. Positions stay live so aim and hits
## do not change.

const CELL := 8.0
const LINEAR_CAP := 36
const FLAG_ENEMY := 1
const FLAG_PLAYER := 2
const FLAG_MOB := 4
const FLAG_CHARMED := 8
const FLAG_CAPSULE := 16
const FLAG_NETWORK_PLAYER := 32

static var _frame := -1
static var _group_count := -1
static var _player_count := -1
static var _count := 0
static var _nodes: Array[Node] = []
static var _worlds: Array = []
static var _ids: PackedInt64Array = PackedInt64Array()
static var _at: PackedVector3Array = PackedVector3Array()
static var _radius: PackedFloat32Array = PackedFloat32Array()
static var _faction: PackedInt32Array = PackedInt32Array()
static var _flags: PackedInt32Array = PackedInt32Array()
static var _cap_a: PackedVector3Array = PackedVector3Array()
static var _cap_b: PackedVector3Array = PackedVector3Array()
static var _cap_r: PackedFloat32Array = PackedFloat32Array()
static var _cells: Dictionary = {}
static var _index_of: Dictionary = {}
static var _scratch: PackedInt32Array = PackedInt32Array()


static func invalidate() -> void:
	_frame = -1
	_group_count = -1
	_player_count = -1
	_count = 0
	_nodes.clear()
	_worlds.clear()
	_ids.resize(0)
	_at.resize(0)
	_radius.resize(0)
	_faction.resize(0)
	_flags.resize(0)
	_cap_a.resize(0)
	_cap_b.resize(0)
	_cap_r.resize(0)
	_cells.clear()
	_index_of.clear()
	_scratch.resize(0)


static func ensure(anywhere: Node) -> void:
	if anywhere == null or not anywhere.is_inside_tree():
		return
	var tree := anywhere.get_tree()
	if tree == null:
		return
	var frame := Engine.get_physics_frames()
	var group_n := tree.get_node_count_in_group(DamageHit.COMBATANT_GROUP)
	var player_n := tree.get_node_count_in_group(CrawlerMobSense.PLAYER_GROUP)
	if frame == _frame and group_n == _group_count \
			and player_n == _player_count and _snapshot_live():
		return
	_rebuild(tree, frame, group_n, player_n)


static func count() -> int:
	return _count


static func node_at(index: int) -> Node:
	if index < 0 or index >= _count:
		return null
	var node := _nodes[index]
	if node == null or not is_instance_valid(node):
		return null
	return node


static func world_at(index: int) -> GameWorld:
	if index < 0 or index >= _count:
		return null
	return _worlds[index] as GameWorld


static func position_at(index: int) -> Vector3:
	if index < 0 or index >= _count:
		return Vector3.ZERO
	return _at[index]


static func radius_at(index: int) -> float:
	if index < 0 or index >= _count:
		return 0.4
	return _radius[index]


static func flags_at(index: int) -> int:
	if index < 0 or index >= _count:
		return 0
	return _flags[index]


static func point_of(node: Node) -> Vector3:
	var index := _index_of_node(node)
	if index >= 0:
		return _at[index]
	return _live_point(node)


static func radius_of(node: Node) -> float:
	var index := _index_of_node(node)
	if index >= 0:
		return _radius[index]
	return _live_radius(node)


static func aim_point(node: Node) -> Vector3:
	var index := _index_of_node(node)
	if index >= 0:
		if (_flags[index] & FLAG_CAPSULE) != 0:
			return (_cap_a[index] + _cap_b[index]) * 0.5
		return _at[index]
	var pill := DamageHit.combat_capsule_of(node)
	if not pill.is_empty():
		var a: Vector3 = pill["a"]
		var b: Vector3 = pill["b"]
		if a.is_finite() and b.is_finite():
			return (a + b) * 0.5
	return _live_point(node)


static func nearest_enemy(anywhere: Node, from: Vector3, reach: float,
		skip: Variant = null, along := Vector3.ZERO, keep := -1.0,
		min_span := 0.0) -> Node:
	return nearest(anywhere, from, reach, skip, DamageHit.Faction.ENEMY,
		along, keep, false, false, false, false, min_span)


static func nearest_mob(anywhere: Node, from: Vector3, reach: float,
		skip: Variant = null, skip_charmed := true) -> Node:
	return nearest(anywhere, from, reach, skip, -1, Vector3.ZERO, -1.0,
		false, false, true, skip_charmed, 0.0)


static func nearest(anywhere: Node, from: Vector3, reach: float,
		skip: Variant = null, want_faction := DamageHit.Faction.ENEMY,
		along := Vector3.ZERO, keep := -1.0, same_world := false,
		use_capsule := false, mobs_only := false,
		skip_charmed := false, min_span := 0.0,
		players_only := false) -> Node:
	if anywhere == null or not from.is_finite() or reach <= 0.0:
		return null
	skip = _live_node(skip)
	ensure(anywhere)
	var face := along.normalized() if along.length_squared() > 0.000001 \
		else Vector3.ZERO
	var reach2 := reach * reach
	var min2 := min_span * min_span
	var want_world := DamageHit.game_world_of(anywhere) if same_world else null
	_fill_near(from, reach)
	var best: Node = null
	var best2 := reach2
	for slot in _scratch.size():
		var index := _scratch[slot]
		if not _passes(index, skip, want_faction, want_world, mobs_only,
				players_only, skip_charmed):
			continue
		var at := _aim_at(index, use_capsule)
		var away := at - from
		var span2 := away.length_squared()
		if span2 > best2 or span2 < min2:
			continue
		if keep > -0.999 and face != Vector3.ZERO:
			var span := sqrt(span2)
			if span < 0.0001 or away.dot(face) < keep * span:
				continue
		best = _nodes[index]
		best2 = span2
	return best


static func first_along(anywhere: Node, from: Vector3, to: Vector3,
		pad: float, skip: Variant = null, skip_ids: Dictionary = {},
		want_faction := DamageHit.Faction.ENEMY, same_world := false,
		mobs_only := false, players_only := false,
		skip_charmed := false) -> Node:
	if anywhere == null or not from.is_finite() or not to.is_finite():
		return null
	skip = _live_node(skip)
	ensure(anywhere)
	var extra := maxf(pad, 0.0) + 6.0
	var want_world := DamageHit.game_world_of(anywhere) if same_world else null
	_fill_segment(from, to, extra)
	_scratch.sort()
	for slot in _scratch.size():
		var index := _scratch[slot]
		if not _passes(index, skip, want_faction, want_world, mobs_only,
				players_only, skip_charmed):
			continue
		var id := _ids[index]
		if skip_ids.has(id):
			continue
		var bounds := _radius[index] + maxf(pad, 0.0)
		if _sphere_hits(from, to, _at[index], bounds):
			return _nodes[index]
	return null


static func first_capsule_along(anywhere: Node, from: Vector3, to: Vector3,
		pad := 0.35, want_faction := DamageHit.Faction.ENEMY,
		same_world := true) -> Dictionary:
	if anywhere == null or not from.is_finite() or not to.is_finite():
		return {}
	ensure(anywhere)
	var extra := from.distance_to(to) + maxf(pad, 0.0) + 8.0
	var want_world := DamageHit.game_world_of(anywhere) if same_world else null
	_fill_near((from + to) * 0.5, extra)
	var best: Node
	var best_at := Vector3.ZERO
	var best_span := from.distance_to(to)
	for slot in _scratch.size():
		var index := _scratch[slot]
		if not _passes(index, anywhere, want_faction, want_world, false,
				false, false):
			continue
		var a := _at[index]
		var b := a
		var radius := _radius[index]
		if (_flags[index] & FLAG_CAPSULE) != 0:
			a = _cap_a[index]
			b = _cap_b[index]
			radius = _cap_r[index]
		if not a.is_finite() or not b.is_finite():
			continue
		var pair := DamageHit.closest_points_on_segments(from, to, a, b)
		if pair[0].distance_to(pair[1]) > radius + maxf(pad, 0.0):
			continue
		var span := from.distance_to(pair[0])
		if span >= best_span:
			continue
		best = _nodes[index]
		best_at = pair[0]
		best_span = span
	if best == null:
		return {}
	return {"at": best_at, "combatant": best}


static func first_shot_along(anywhere: Node, from: Vector3, to: Vector3,
		pad: float, skip: Variant, charmed: bool) -> Node:
	if charmed:
		return first_along(anywhere, from, to, pad, skip, {}, -1, false,
			true, false, false)
	return first_along(anywhere, from, to, pad, skip, {},
		-1, false, false, true, false)


static func shot_collect(anywhere: Node, skip: Variant, charmed: bool) -> Array[Node]:
	if charmed:
		return collect(anywhere, skip, -1, false, true, false, false)
	return collect(anywhere, skip, -1, false, false, true, false)


static func collect(anywhere: Node, skip: Variant = null,
		want_faction := DamageHit.Faction.ENEMY, same_world := false,
		mobs_only := false, players_only := false,
		skip_charmed := false) -> Array[Node]:
	var found: Array[Node] = []
	if anywhere == null or not anywhere.is_inside_tree():
		return found
	skip = _live_node(skip)
	ensure(anywhere)
	var want_world := DamageHit.game_world_of(anywhere) if same_world else null
	for index in _count:
		if not _passes(index, skip, want_faction, want_world, mobs_only,
				players_only, skip_charmed):
			continue
		found.append(_nodes[index])
	return found


static func append_collision_rids(exclude: Array[RID]) -> void:
	for index in _count:
		var node := _nodes[index]
		if node != null and is_instance_valid(node):
			_append_rids(node, exclude)


static func _snapshot_live() -> bool:
	if _count != _nodes.size():
		return false
	for index in _count:
		var node := _nodes[index]
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			return false
	return true


static func _rebuild(tree: SceneTree, frame: int, group_n: int,
		player_n := -1) -> void:
	_frame = frame
	_group_count = group_n
	_player_count = player_n
	_nodes.clear()
	_worlds.clear()
	_index_of.clear()
	_cells.clear()
	if tree == null:
		_count = 0
		return
	var raw: Array = tree.get_nodes_in_group(DamageHit.COMBATANT_GROUP)
	var extras: Array = tree.get_nodes_in_group(CrawlerMobSense.PLAYER_GROUP)
	var size := raw.size() + extras.size()
	_ids.resize(size)
	_at.resize(size)
	_radius.resize(size)
	_faction.resize(size)
	_flags.resize(size)
	_cap_a.resize(size)
	_cap_b.resize(size)
	_cap_r.resize(size)
	var write := 0
	for node_variant: Variant in raw:
		write = _write_node(node_variant as Node, write, false)
	for node_variant: Variant in extras:
		write = _write_node(node_variant as Node, write, true)
	_count = write
	_ids.resize(write)
	_at.resize(write)
	_radius.resize(write)
	_faction.resize(write)
	_flags.resize(write)
	_cap_a.resize(write)
	_cap_b.resize(write)
	_cap_r.resize(write)


static func _write_node(node: Node, write: int, as_player: bool) -> int:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return write
	if _index_of.has(node.get_instance_id()):
		return write
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return write
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return write
	if not as_player and not node.has_method(&"combat_faction"):
		return write
	var faction := DamageHit.Faction.PLAYER if as_player \
		else int(node.call(&"combat_faction"))
	if node.has_method(&"combat_faction"):
		faction = int(node.call(&"combat_faction"))
	var flags := 0
	if faction == DamageHit.Faction.ENEMY:
		flags |= FLAG_ENEMY
	elif faction == DamageHit.Faction.PLAYER:
		flags |= FLAG_PLAYER
	if node is CrawlerMob or node.is_in_group(CrawlerMob.GROUP):
		flags |= FLAG_MOB
		if node.has_method(&"is_charmed") and bool(node.call(&"is_charmed")):
			flags |= FLAG_CHARMED
	if as_player or node.is_in_group(CrawlerMobSense.PLAYER_GROUP):
		flags |= FLAG_NETWORK_PLAYER
	var at := _live_point(node)
	if not at.is_finite():
		return write
	var radius := _live_radius(node)
	var pill := DamageHit.combat_capsule_of(node)
	_nodes.append(node)
	_worlds.append(DamageHit.game_world_of(node))
	_ids[write] = node.get_instance_id()
	_at[write] = at
	_radius[write] = radius
	_faction[write] = faction
	if not pill.is_empty():
		flags |= FLAG_CAPSULE
		_cap_a[write] = pill["a"]
		_cap_b[write] = pill["b"]
		_cap_r[write] = float(pill["radius"])
	else:
		_cap_a[write] = at
		_cap_b[write] = at
		_cap_r[write] = radius
	_flags[write] = flags
	_index_of[_ids[write]] = write
	var key := _cell_of(at)
	if not _cells.has(key):
		_cells[key] = PackedInt32Array()
	var bucket: PackedInt32Array = _cells[key]
	bucket.append(write)
	_cells[key] = bucket
	return write + 1


static func _live_node(node: Variant) -> Node:
	if node == null or typeof(node) != TYPE_OBJECT:
		return null
	if not is_instance_valid(node):
		return null
	return node as Node


static func _passes(index: int, skip: Variant, want_faction: int,
		want_world: GameWorld, mobs_only: bool, players_only: bool,
		skip_charmed: bool) -> bool:
	if index < 0 or index >= _count:
		return false
	var node := _nodes[index]
	if node == null or not is_instance_valid(node) or node == skip:
		return false
	if want_world != null and _worlds[index] != want_world:
		return false
	if want_faction >= 0 and _faction[index] != want_faction:
		return false
	var flags := _flags[index]
	if mobs_only and (flags & FLAG_MOB) == 0:
		return false
	if players_only and (flags & FLAG_NETWORK_PLAYER) == 0:
		return false
	if skip_charmed and (flags & FLAG_CHARMED) != 0:
		return false
	return true


static func _aim_at(index: int, use_capsule: bool) -> Vector3:
	if use_capsule and (_flags[index] & FLAG_CAPSULE) != 0:
		return (_cap_a[index] + _cap_b[index]) * 0.5
	return _at[index]


static func _fill_near(from: Vector3, reach: float) -> void:
	_scratch.resize(0)
	if _count <= 0:
		return
	if _count <= LINEAR_CAP or reach > CELL * 2.5:
		_scratch.resize(_count)
		for index in _count:
			_scratch[index] = index
		return
	var span := maxf(reach, 0.0)
	var min_c := _cell_of(from - Vector3.ONE * span)
	var max_c := _cell_of(from + Vector3.ONE * span)
	for x in range(min_c.x, max_c.x + 1):
		for y in range(min_c.y, max_c.y + 1):
			for z in range(min_c.z, max_c.z + 1):
				_append_cell(Vector3i(x, y, z))


static func _fill_segment(from: Vector3, to: Vector3, pad: float) -> void:
	_scratch.resize(0)
	if _count <= 0:
		return
	var grow := Vector3.ONE * maxf(pad, 0.0)
	var lo := Vector3(
		minf(from.x, to.x), minf(from.y, to.y), minf(from.z, to.z)) - grow
	var hi := Vector3(
		maxf(from.x, to.x), maxf(from.y, to.y), maxf(from.z, to.z)) + grow
	var span := hi - lo
	if _count <= LINEAR_CAP or span.x > CELL * 5.0 or span.y > CELL * 5.0 \
			or span.z > CELL * 5.0:
		_scratch.resize(_count)
		for index in _count:
			_scratch[index] = index
		return
	var min_c := _cell_of(lo)
	var max_c := _cell_of(hi)
	for x in range(min_c.x, max_c.x + 1):
		for y in range(min_c.y, max_c.y + 1):
			for z in range(min_c.z, max_c.z + 1):
				_append_cell(Vector3i(x, y, z))


static func _append_cell(key: Vector3i) -> void:
	var bucket_variant: Variant = _cells.get(key)
	if bucket_variant == null:
		return
	var bucket: PackedInt32Array = bucket_variant
	for slot in bucket.size():
		_scratch.append(bucket[slot])


static func _cell_of(at: Vector3) -> Vector3i:
	return Vector3i(
		floori(at.x / CELL), floori(at.y / CELL), floori(at.z / CELL))


static func _sphere_hits(from: Vector3, to: Vector3, at: Vector3,
		pad: float) -> bool:
	var limit := maxf(pad, 0.0)
	return DamageHit.closest_on_segment(from, to, at).distance_squared_to(at) \
		<= limit * limit


static func _index_of_node(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	return int(_index_of.get(node.get_instance_id(), -1))


static func _live_point(node: Node) -> Vector3:
	if node != null and node.has_method(&"combat_position"):
		var at: Variant = node.call(&"combat_position")
		if at is Vector3 and (at as Vector3).is_finite():
			return at
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3(INF, INF, INF)


static func _live_radius(node: Node) -> float:
	if node != null and node.has_method(&"combat_radius"):
		return maxf(float(node.call(&"combat_radius")), 0.0)
	return 0.4


static func _append_rids(node: Node, exclude: Array[RID]) -> void:
	if node is CollisionObject3D:
		var rid := (node as CollisionObject3D).get_rid()
		if rid.is_valid() and not exclude.has(rid):
			exclude.append(rid)
	for child in node.get_children():
		_append_rids(child, exclude)
