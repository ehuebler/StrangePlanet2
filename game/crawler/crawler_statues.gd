class_name CrawlerStatues
extends Node3D

## Scatters crawler shrines on inland ground. Three sit on the spawn-to-city
## walk so a run meets them; the rest pack the named cells.

const OPENING_COUNT := 3
const MIN_SEPARATION := 250.0
const OPENING_SEPARATION := 150.0
const FIELD_SEPARATION := 96.0
const SITE_KEEP := 130.0
const OPENING_PER_PATCH := 8
const FIELD_PER_PATCH := 6
const TARGET_COUNT := 420
const OPENING_CORRIDOR := 120.0
const PLACE_TRIES := 240

var _place_tries := 0
var _watch_left := 0.0


func _ready() -> void:
	name = "CrawlerStatues"
	set_process(true)
	if CrawlerRules.active():
		call_deferred(&"ensure_placed")


func _process(delta: float) -> void:
	_watch_left -= delta
	if _watch_left > 0.0:
		return
	_watch_left = 0.25
	_wake_near()


func _wake_near() -> void:
	var at := Vector3.INF
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			at = camera.global_position
	var reach2 := 80.0 * 80.0
	for child in get_children():
		var statue := child as CrawlerStatue
		if statue == null:
			continue
		var near := at.is_finite() \
			and statue.global_position.distance_squared_to(at) <= reach2
		statue.set_physics_process(statue.should_simulate(near))


func ensure_placed() -> bool:
	if not CrawlerRules.active():
		return true
	var overlay := _overlay()
	var overlay_ready := overlay != null and overlay.ensure_ready()
	var seed := _seed()
	if seed == 0:
		_retry_place()
		return false
	var picks := pick_directions(overlay if overlay_ready else null, seed)
	if picks.size() < OPENING_COUNT:
		_retry_place()
		return false
	if not _matches_layout(picks.size()):
		_rebuild(picks, overlay)
	if overlay_ready:
		return true
	_retry_place()
	return false


func _retry_place() -> void:
	_place_tries += 1
	if _place_tries >= PLACE_TRIES:
		return
	call_deferred(&"ensure_placed")


static func pick_directions(
		overlay: LandPatchOverlay,
		seed: int
	) -> PackedVector3Array:
	var chosen := opening_directions()
	if overlay == null or not overlay.ensure_ready():
		return chosen
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else 1
	var radius := _planet_radius(overlay)
	var opening_dot := cos(OPENING_SEPARATION / radius)
	var field_dot := cos(FIELD_SEPARATION / radius)
	var site_dot := cos(SITE_KEEP / radius)
	var spawn := CrawlerRules.spawn_direction()
	var start_id := overlay.crawler_start_patch_id()
	if start_id >= 0:
		var pad: Vector3 = overlay.flat_direction_for_patch(start_id)
		if pad.length_squared() >= 0.25:
			spawn = pad.normalized()
	var city := CrawlerRules.city_direction()
	var city_id := overlay.patch_id_named(CrawlerRules.CITY_PATCH)
	if city_id >= 0:
		var inland: Vector3 = overlay.flat_direction_for_patch(city_id)
		if inland.length_squared() >= 0.25:
			city = inland.normalized()
	var near: Array[Vector3] = []
	var far: Array[Vector3] = []
	for patch in _statue_patches(overlay.partition):
		var patch_name := str(patch.recipe_name)
		if patch_name.is_empty():
			patch_name = str(patch.name)
		if _blocked_patch(patch_name):
			continue
		var cell_id := overlay.partition.first_cell_of(patch.id)
		if cell_id < 0:
			cell_id = patch.id
		if CrawlerRules.opening_route_patch(patch_name):
			for at: Vector3 in _dense_dirs(
					overlay, cell_id, radius, OPENING_SEPARATION, OPENING_PER_PATCH):
				near.append(at)
		else:
			for at: Vector3 in _dense_dirs(
					overlay, cell_id, radius, FIELD_SEPARATION, FIELD_PER_PATCH):
				far.append(at)
	_shuffle(near, rng)
	_shuffle(far, rng)
	for at: Vector3 in near:
		if at.dot(spawn) > site_dot or at.dot(city) > site_dot:
			continue
		if not _far_enough(chosen, at, opening_dot):
			continue
		chosen.append(at)
		if chosen.size() >= TARGET_COUNT:
			return chosen
	for at: Vector3 in far:
		if at.dot(spawn) > site_dot or at.dot(city) > site_dot:
			continue
		if not _far_enough(chosen, at, field_dot):
			continue
		chosen.append(at)
		if chosen.size() >= TARGET_COUNT:
			break
	return chosen


static func opening_directions() -> PackedVector3Array:
	var from := CrawlerRules.spawn_direction()
	var toward := CrawlerRules.city_direction()
	var chosen := PackedVector3Array()
	for index in OPENING_COUNT:
		var t := 0.22 + 0.28 * float(index)
		chosen.append(from.slerp(toward, t).normalized())
	return chosen


static func count_along_opening(
		dirs: PackedVector3Array,
		radius := 8000.0
	) -> int:
	var from := CrawlerRules.spawn_direction()
	var toward := CrawlerRules.city_direction()
	var found := 0
	for at: Vector3 in dirs:
		if _on_opening_walk(from, toward, at, radius):
			found += 1
	return found


static func kind_at(index: int) -> String:
	if CrawlerStatue.KINDS.is_empty():
		return CrawlerStatue.KIND_MISC
	return String(CrawlerStatue.KINDS[index % CrawlerStatue.KINDS.size()])


func _rebuild(picks: PackedVector3Array, overlay: LandPatchOverlay) -> void:
	_clear_statues()
	for index in picks.size():
		_place(kind_at(index), picks[index], index, overlay)
	_wake_near()


func _place(
		kind: String,
		direction: Vector3,
		slot: int,
		_overlay: LandPatchOverlay
	) -> void:
	if get_node_or_null("CrawlerStatue_%s_%d" % [kind, slot]) != null:
		return
	var statue := CrawlerStatue.new()
	statue.configure(kind, direction, slot)
	add_child(statue)


func _matches_layout(expected: int) -> bool:
	if expected <= 0 or get_child_count() != expected:
		return false
	return get_node_or_null("CrawlerStatue_%s_0" % kind_at(0)) != null


func _clear_statues() -> void:
	var held: Array[Node] = []
	for child in get_children():
		held.append(child)
	for child: Node in held:
		remove_child(child)
		child.free()


func _seed() -> int:
	var listed := int(CrawlerProgress.session_payload.get("statue_seed", 0))
	if listed != 0:
		return listed
	var tree := get_tree()
	if tree != null:
		for node_variant: Variant in tree.get_nodes_in_group(&"network_players"):
			var player := node_variant as OnlinePlayer
			if player != null and player.crawler_progress != null:
				return player.crawler_progress.ensure_statue_seed()
	var fresh := CrawlerProgress.new()
	fresh.from_dict(CrawlerProgress.session_payload)
	return fresh.ensure_statue_seed()


func _overlay() -> LandPatchOverlay:
	var planet := get_parent() as Planet
	if planet != null:
		var named := planet.get_node_or_null("LandPatches") as LandPatchOverlay
		if named != null:
			return named
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(LandPatchOverlay.GROUP) as LandPatchOverlay


static func _dense_dirs(
		overlay: LandPatchOverlay,
		patch_id: int,
		radius: float,
		separation: float,
		limit: int
	) -> Array[Vector3]:
	var picked: Array[Vector3] = []
	var inland: Vector3 = overlay.flat_direction_for_patch(patch_id)
	if inland.length_squared() >= 0.25:
		picked.append(inland.normalized())
	var dirs := overlay.partition.directions_of(patch_id)
	if dirs.is_empty() or picked.size() >= limit:
		return picked
	var min_dot := cos(separation / maxf(radius, 1.0))
	var stride := maxi(1, int(ceil(float(dirs.size()) / float(maxi(limit * 10, 48)))))
	var index := 0
	while index < dirs.size() and picked.size() < limit:
		var at: Vector3 = dirs[index]
		index += stride
		if at.length_squared() < 0.25:
			continue
		var unit := at.normalized()
		if not _far_enough_list(picked, unit, min_dot):
			continue
		picked.append(unit)
	return picked


static func _statue_patches(partition: LandPartition) -> Array:
	if partition != null and partition.patches.size() > 0:
		return partition.patches
	if partition != null:
		return partition.territories
	return []


static func _blocked_patch(name: String) -> bool:
	var clean := name.strip_edges()
	if CrawlerRules.reserved_patch(clean):
		return true
	return clean == CrawlerRules.TOWER_PATCH \
		or clean == CrawlerRules.CASTLE_PATCH \
		or clean.begins_with(CrawlerRules.TOWER_PATCH + " ") \
		or clean.begins_with(CrawlerRules.CASTLE_PATCH + " ")


static func _on_opening_walk(
		from: Vector3,
		toward: Vector3,
		at: Vector3,
		radius: float
	) -> bool:
	var t := _arc_t(from, toward, at)
	if t < 0.08 or t > 0.92:
		return false
	return _arc_metres(from, toward, at, radius) <= OPENING_CORRIDOR


static func _arc_t(from: Vector3, toward: Vector3, at: Vector3) -> float:
	var axis := from.cross(toward)
	if axis.length_squared() < 0.000001:
		return 0.0
	var span := from.angle_to(toward)
	if span < 0.000001:
		return 0.0
	var normal := axis.normalized()
	var projected := (at - normal * at.dot(normal)).normalized()
	if projected.length_squared() < 0.25:
		return 0.0
	var signed := from.angle_to(projected)
	if from.cross(projected).dot(normal) < 0.0:
		signed = -signed
	return signed / span


static func _arc_metres(
		from: Vector3,
		toward: Vector3,
		at: Vector3,
		radius: float
	) -> float:
	var axis := from.cross(toward)
	if axis.length_squared() < 0.000001:
		return at.angle_to(from) * radius
	var sine := clampf(at.dot(axis.normalized()), -1.0, 1.0)
	return absf(asin(sine)) * radius


static func _far_enough(
		chosen: PackedVector3Array,
		at: Vector3,
		min_dot: float
	) -> bool:
	for other: Vector3 in chosen:
		if at.dot(other) > min_dot:
			return false
	return true


static func _far_enough_list(
		chosen: Array[Vector3],
		at: Vector3,
		min_dot: float
	) -> bool:
	for other: Vector3 in chosen:
		if at.dot(other) > min_dot:
			return false
	return true


static func _shuffle(items: Array[Vector3], rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held: Vector3 = items[index]
		items[index] = items[swap]
		items[swap] = held


static func _planet_radius(overlay: LandPatchOverlay) -> float:
	var planet := overlay.get_parent() as Planet if overlay != null else null
	if planet != null and planet.shape != null:
		return maxf(planet.shape.radius, 1.0)
	return 8000.0
