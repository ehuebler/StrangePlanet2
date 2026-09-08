class_name LandPatchOverlay
extends Node3D

## Tilde map of [LandPartition]: patch border ribbons on the ground, names at
## high altitude. Street names lie on the ground inside a mapped city.

const GROUP := &"land_patch_overlay"
const FONT: FontFile = preload("res://fonts/Bungee-Regular.ttf")
const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")
const STORE := preload("res://game/city/patch_city_store.gd")
const CrawlerCityRingScript := preload("res://game/crawler/crawler_city_ring.gd")

## Typical territory width, metres. About a twelfth of the first cut, so
## ten to fifteen of these fit in one of those larger cells.
@export var target_span := 1300.0
## Named overlay cells inside each territory. Half the first cut, so the
## tilde map reads as neighbourhoods without moving cities or spawn tables.
@export var cell_span := 650.0
## Keep-out around each Giant Mountain landmark, metres of surface arc.
@export var mountain_clearance := 1000.0
## Ribbon half-width, metres. A painted line on the ground, not a road.
@export var border_half_width := 5.0
## Metres the ribbon sits above the analytical surface, so it does not z-fight
## the terrain mesh.
@export var border_lift := 2.0
## Arc length between draped samples, metres. Short enough that the ribbon
## follows hills instead of spanning them as a chord.
@export var border_step := 6.0

var partition := LandPartition.new()
var _enabled := false
var _baked := false
var _borders: MeshInstance3D
var _labels: Array[Label3D] = []
var _cities: Dictionary = {}
var _flat_dirs: Dictionary = {}
var _high_dirs: Dictionary = {}


func _ready() -> void:
	name = "LandPatches"
	add_to_group(GROUP)
	visible = false
	set_process(false)
	call_deferred(&"_rebuild")


func set_overlay_enabled(on: bool) -> void:
	_enabled = on
	visible = on and _baked
	set_process(on and _baked)
	if is_instance_valid(_borders):
		_borders.visible = on
	_refresh_city_maps()
	_refresh_patch_labels()


func render_live_city(patch_id: int) -> bool:
	if not _baked or patch_id < 0 or patch_id >= partition.patches.size():
		return false
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return false
	var bake_id := _city_key(patch_id)
	var held := _city_at(patch_id)
	if held != null:
		_cities.erase(bake_id)
		held.free()
	var generator := PatchCityGenerator.new()
	var plan := generator.generate(planet.shape, partition, patch_id)
	if plan.districts.is_empty():
		return false
	var city := PatchCity.new()
	city.apply(plan, planet.shape)
	add_child(city)
	_cities[bake_id] = city
	return _finish_live_city(city, planet)


func render_yard_city(patch_id: int) -> bool:
	if not _baked or patch_id < 0 or patch_id >= partition.patches.size():
		return false
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return false
	var bake_id := _city_key(patch_id)
	var held := _city_at(patch_id)
	if held != null:
		_cities.erase(bake_id)
		held.free()
	var generator := PatchCityGenerator.new()
	var plan := generator.generate(planet.shape, partition, patch_id)
	if plan.districts.is_empty():
		return false
	var city := YardCity.new()
	city.apply(plan, planet.shape)
	add_child(city)
	_cities[bake_id] = city
	return _finish_live_city(city, planet)


func place_baked_city(patch_id: int, refresh_maps := true) -> bool:
	if not _baked or patch_id < 0 or patch_id >= partition.patches.size():
		return false
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return false
	var bake_id := _city_key(patch_id)
	var patch_name := _bake_name(patch_id)
	if not STORE.has_phase(bake_id, PatchCity.PHASE_PAINTED, patch_name):
		return false
	var held := _city_at(patch_id)
	if held != null:
		if held.phase >= PatchCity.PHASE_PAINTED and held.from_bake:
			return false
		_cities.erase(bake_id)
		held.free()
	var baked := STORE.instantiate_phase(
		bake_id, PatchCity.PHASE_PAINTED, planet.shape, patch_name,
		STORE.LAYOUT_FIRST_PLANET, planet)
	if baked == null:
		return false
	baked.from_bake = true
	_cities[bake_id] = baked
	baked.clear_flora()
	if refresh_maps:
		_refresh_city_maps()
	ensure_crawler_waypoints()
	return true


func has_baked_city(patch_id: int) -> bool:
	if patch_id < 0 or patch_id >= partition.patches.size():
		return false
	return STORE.has_phase(
		_city_key(patch_id), PatchCity.PHASE_PAINTED, _bake_name(patch_id))


func ensure_ready() -> bool:
	if not _baked:
		_rebuild()
	return _baked


func pick_spread_patches(count: int) -> Array[int]:
	if not ensure_ready() or count <= 0:
		return []
	var candidates: Array[int] = []
	for patch in partition.patches:
		if patch.span < 420.0:
			continue
		candidates.append(patch.id)
	if candidates.is_empty():
		for patch in partition.patches:
			candidates.append(patch.id)
	if candidates.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var chosen: Array[int] = []
	chosen.append(candidates[rng.randi() % candidates.size()])
	while chosen.size() < mini(count, candidates.size()):
		var best := -1
		var best_gap := -1.0
		for patch_id in candidates:
			if chosen.has(patch_id):
				continue
			var dir := partition.patches[patch_id].direction
			var nearest := 4.0
			for other_id in chosen:
				nearest = minf(
					nearest,
					dir.distance_to(partition.patches[other_id].direction)
				)
			if nearest > best_gap:
				best_gap = nearest
				best = patch_id
		if best < 0:
			break
		chosen.append(best)
	return chosen


func place_cities(patch_ids: Array) -> int:
	if not ensure_ready():
		return 0
	var placed := 0
	for raw: Variant in patch_ids:
		var patch_id := int(raw)
		if has_city(patch_id):
			placed += 1
			continue
		if has_baked_city(patch_id) and place_baked_city(patch_id, false):
			placed += 1
			continue
		if render_live_city(patch_id):
			placed += 1
	if placed > 0:
		_refresh_city_maps()
		ensure_crawler_waypoints()
	return placed


func place_all_baked_cities() -> int:
	if not _baked:
		return 0
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return 0
	var placed := 0
	var skipped := 0
	var seen: Dictionary = {}
	for patch in partition.patches:
		var key := _city_key(patch.id)
		if seen.has(key):
			continue
		seen[key] = true
		if not has_baked_city(patch.id):
			continue
		if place_baked_city(patch.id, false):
			placed += 1
		else:
			skipped += 1
	if placed > 0:
		_refresh_city_maps()
		ensure_crawler_waypoints()
	return placed


func _finish_live_city(city: PatchCity, planet: Planet) -> bool:
	var advanced := false
	while city.phase < PatchCity.PHASE_PAINTED:
		if not _advance_live_city(city, planet):
			break
		advanced = true
	return advanced


func _advance_live_city(city: PatchCity, planet: Planet) -> bool:
	if city.advance(planet.shape):
		if city.phase == PatchCity.PHASE_PAVED:
			city.reparent(planet)
			city.clear_flora()
		_refresh_city_maps()
		return true
	return false


func has_city(patch_id: int) -> bool:
	return _city_at(patch_id) != null


func city_phase(patch_id: int) -> int:
	var city := _city_at(patch_id)
	return city.phase if city != null else -1


func city_for_patch(patch_id: int) -> PatchCity:
	return _city_at(patch_id)


func patch_id_named(wanted: String) -> int:
	var exact := patch_id_named_exact(wanted)
	if exact >= 0:
		return exact
	var clean := wanted.strip_edges().to_lower()
	if clean.is_empty() or not ensure_ready():
		return -1
	for patch in partition.patches:
		if patch.name.strip_edges().to_lower().begins_with(clean):
			return patch.id
	return -1


func patch_id_named_exact(wanted: String) -> int:
	var clean := wanted.strip_edges().to_lower()
	if clean.is_empty() or not ensure_ready():
		return -1
	for patch in partition.patches:
		if patch.name.strip_edges().to_lower() == clean:
			return patch.id
	return -1


## Keep cell of a first-cut territory — the leftover after compass children.
func rest_cell_named(territory_name: String) -> int:
	if not ensure_ready():
		return -1
	var clean := territory_name.strip_edges()
	for home in partition.territories:
		if home.name == clean:
			return partition.first_cell_of(home.id)
	return patch_id_named_exact(clean)


func compass_cell_named(territory_name: String, compass: String) -> int:
	var wanted := "%s %s" % [
		territory_name.strip_edges(),
		compass.strip_edges(),
	]
	var found := patch_id_named_exact(wanted)
	if found >= 0:
		return found
	if not ensure_ready():
		return -1
	var recipe := territory_name.strip_edges()
	var suffix := compass.strip_edges().to_lower()
	for patch in partition.patches:
		if patch.recipe_name == recipe \
				and patch.name.to_lower().ends_with(suffix):
			return patch.id
	return -1


func patch_named(wanted: String):
	var patch_id := patch_id_named(wanted)
	if patch_id < 0 or patch_id >= partition.patches.size():
		return null
	return partition.patches[patch_id]


func patch_id_at(world: Vector3) -> int:
	if not ensure_ready() or not world.is_finite():
		return -1
	var planet := get_parent() as Planet
	if planet == null:
		return -1
	var local := planet.to_local(world)
	if local.length_squared() < 0.0001:
		return -1
	return partition.owner_at(local)


func patch_name_at(world: Vector3) -> String:
	var patch_id := patch_id_at(world)
	if patch_id < 0 or patch_id >= partition.patches.size():
		return ""
	return str(partition.patches[patch_id].name)


func surface_transform_for_patch(patch_id: int, clearance := 1.2) -> Transform3D:
	if not ensure_ready() or patch_id < 0 or patch_id >= partition.patches.size():
		return Transform3D()
	var planet := get_parent() as Planet
	if planet == null:
		return Transform3D()
	return _surface_transform_at(planet, partition.patches[patch_id].direction, clearance)


func flat_surface_transform_for_patch(patch_id: int, clearance := 1.2) -> Transform3D:
	if not ensure_ready() or patch_id < 0 or patch_id >= partition.patches.size():
		return Transform3D()
	var planet := get_parent() as Planet
	if planet == null:
		return Transform3D()
	return _surface_transform_at(planet, flat_direction_for_patch(patch_id), clearance)


func high_surface_transform_for_patch(patch_id: int, clearance := 1.2) -> Transform3D:
	if not ensure_ready() or patch_id < 0 or patch_id >= partition.patches.size():
		return Transform3D()
	var planet := get_parent() as Planet
	if planet == null:
		return Transform3D()
	return _surface_transform_at(planet, high_direction_for_patch(patch_id), clearance)


func surface_transform_for_direction(direction: Vector3, clearance := 1.2) -> Transform3D:
	if not ensure_ready() or direction.length_squared() < 0.0001:
		return Transform3D()
	var planet := get_parent() as Planet
	if planet == null:
		return Transform3D()
	return _surface_transform_at(planet, direction, clearance)


func crawler_start_patch_id() -> int:
	if CrawlerRun.active():
		var at := crawler_spawn_transform(0.0)
		if at.origin.length_squared() > 1.0:
			return patch_id_at(at.origin)
	var patch_id := rest_cell_named(CrawlerRules.START_PATCH)
	if patch_id < 0:
		patch_id = patch_id_named(CrawlerRules.START_PATCH)
	return patch_id


func crawler_spawn_transform(clearance := 1.2) -> Transform3D:
	if CrawlerRun.active():
		var seated := surface_transform_for_direction(CrawlerRun.spawn_direction(), clearance)
		if seated.origin.length_squared() > 1.0:
			return seated
	var patch_id := crawler_start_patch_id()
	if patch_id >= 0 and not CrawlerRun.active():
		var seated := high_surface_transform_for_patch(patch_id, clearance)
		if seated.origin.length_squared() > 1.0:
			return seated
	return surface_transform_for_direction(CrawlerRules.spawn_direction(), clearance)


func crawler_city_transform(clearance := 0.35) -> Transform3D:
	return surface_transform_for_direction(CrawlerRules.city_direction(), clearance)


func flat_surface_transform_away_from(
		patch_id: int,
		from_dir: Vector3,
		extra_metres := 420.0,
		clearance := 1.2
	) -> Transform3D:
	if not ensure_ready() or patch_id < 0 or patch_id >= partition.patches.size():
		return Transform3D()
	var planet := get_parent() as Planet
	if planet == null:
		return Transform3D()
	var inland := flat_direction_for_patch(patch_id)
	var nudged := _nudge_direction_away(
		planet, patch_id, inland, from_dir, extra_metres)
	return _surface_transform_at(planet, nudged, clearance)


func _nudge_direction_away(
		planet: Planet,
		patch_id: int,
		inland: Vector3,
		from_dir: Vector3,
		extra_metres: float
	) -> Vector3:
	var at := inland.normalized() if inland.length_squared() > 0.25 else Vector3.UP
	if extra_metres <= 0.0 or from_dir.length_squared() < 0.0001:
		return at
	var from := from_dir.normalized()
	var shape := planet.shape
	var spacing := planet.finest_spacing()
	var radius := maxf(shape.radius, 1.0)
	var step := 36.0
	var travelled := 0.0
	var last := at
	var half := CrawlerRules.CITY_RING_RADIUS
	while travelled < extra_metres:
		var tangent := at - from * at.dot(from)
		if tangent.length_squared() < 0.0001:
			break
		var nxt := (at + tangent.normalized() * (step / radius)).normalized()
		if not _monument_pad_ok(shape, partition, patch_id, nxt, spacing, half):
			break
		last = nxt
		at = nxt
		travelled += step
	return last


func high_direction_for_patch(patch_id: int) -> Vector3:
	if _high_dirs.has(patch_id):
		return _high_dirs[patch_id]
	var fallback := Vector3.UP
	if patch_id >= 0 and patch_id < partition.patches.size():
		fallback = partition.patches[patch_id].direction
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		_high_dirs[patch_id] = fallback
		return fallback
	var chosen := _pick_high_direction(planet, patch_id, fallback)
	_high_dirs[patch_id] = chosen
	return chosen


func flat_direction_for_patch(patch_id: int) -> Vector3:
	if _flat_dirs.has(patch_id):
		return _flat_dirs[patch_id]
	var fallback := Vector3.UP
	if patch_id >= 0 and patch_id < partition.patches.size():
		fallback = partition.patches[patch_id].direction
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		_flat_dirs[patch_id] = fallback
		return fallback
	var chosen := _pick_flat_direction(planet, patch_id, fallback)
	_flat_dirs[patch_id] = chosen
	return chosen


static func spawn_slope_score(slope_degrees: float, pad_degrees: float, elevation: float) -> float:
	if elevation < 8.0:
		return INF
	return maxf(slope_degrees, pad_degrees)


static func peak_score(elevation: float, river := 0.0, lake := 0.0) -> float:
	if elevation < 8.0 or river > 0.25 or lake > 0.45:
		return -INF
	return elevation


func _pick_flat_direction(planet: Planet, patch_id: int, fallback: Vector3) -> Vector3:
	var dirs := partition.directions_of(patch_id)
	if dirs.is_empty():
		return fallback
	var shape := planet.shape
	var spacing := planet.finest_spacing()
	var stride := maxi(1, int(ceil(float(dirs.size()) / 96.0)))
	var best := fallback
	var best_score := INF
	var best_elev := -INF
	var index := 0
	while index < dirs.size():
		var direction: Vector3 = dirs[index]
		index += stride
		if direction.length_squared() < 0.25:
			continue
		var elev := shape.elevation(direction, spacing)
		var parts := shape.sample(direction)
		if float(parts.get("river", 0.0)) > 0.25 \
				or float(parts.get("lake", 0.0)) > 0.45:
			continue
		var slope := _slope_degrees(shape, direction, spacing)
		var pad := _pad_slope_degrees(shape, direction, spacing)
		var score := spawn_slope_score(slope, pad, elev)
		if score > best_score + 0.05:
			continue
		if score < best_score - 0.05 or elev > best_elev:
			best_score = score
			best_elev = elev
			best = direction.normalized()
	return best


func _pick_high_direction(planet: Planet, patch_id: int, fallback: Vector3) -> Vector3:
	var dirs := partition.directions_of(patch_id)
	if dirs.is_empty():
		return fallback
	var shape := planet.shape
	var spacing := planet.finest_spacing()
	var stride := maxi(1, int(ceil(float(dirs.size()) / 128.0)))
	var best := fallback
	var best_elev := -INF
	var best_slope := INF
	var index := 0
	while index < dirs.size():
		var direction: Vector3 = dirs[index]
		index += stride
		if direction.length_squared() < 0.25:
			continue
		var elev := shape.elevation(direction, spacing)
		var parts := shape.sample(direction)
		var score := peak_score(
			elev, float(parts.get("river", 0.0)), float(parts.get("lake", 0.0)))
		if score < 0.0:
			continue
		var slope := _pad_slope_degrees(shape, direction, spacing)
		if score > best_elev + 0.25 \
				or (score >= best_elev - 0.25 and slope < best_slope - 0.5):
			best_elev = score
			best_slope = slope
			best = direction.normalized()
	return best


func shore_direction_for_patch(patch_id: int, half_span := 52.0) -> Vector3:
	if not ensure_ready() or patch_id < 0 or patch_id >= partition.patches.size():
		return Vector3.UP
	var inland := flat_direction_for_patch(patch_id)
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return inland
	return _pick_shore_direction(planet, patch_id, inland, half_span)


func _pick_shore_direction(
		planet: Planet,
		patch_id: int,
		inland: Vector3,
		half_span: float
	) -> Vector3:
	var shape := planet.shape
	var spacing := planet.finest_spacing()
	var radius := maxf(shape.radius, 1.0)
	var start := inland.normalized() if inland.length_squared() > 0.25 else Vector3.UP
	var best := start
	var best_score := INF
	var dirs := partition.directions_of(patch_id)
	var stride := maxi(1, int(ceil(float(dirs.size()) / 96.0)))
	var index := 0
	while index < dirs.size():
		var sample: Vector3 = dirs[index]
		index += stride
		if not _monument_pad_ok(shape, partition, patch_id, sample, spacing, half_span):
			continue
		var sample_elev := shape.elevation(sample, spacing)
		var sample_score: float = sample_elev \
				+ _pad_slope_degrees(shape, sample, spacing) * 0.2
		if sample_score < best_score:
			best_score = sample_score
			best = sample.normalized()
	var toward := _inland_axis(start)
	for shore in _shore_border_dirs(patch_id):
		var axis := start - shore
		axis -= shore * axis.dot(shore)
		if axis.length_squared() < 0.0001:
			axis = toward
		else:
			axis = axis.normalized()
		var pulls: Array[float] = [68.0, 90.0, 120.0, 160.0, 210.0]
		for pull in pulls:
			var candidate: Vector3 = (shore + axis * (pull / radius)).normalized()
			if not _monument_pad_ok(shape, partition, patch_id, candidate, spacing, half_span):
				continue
			var elev := shape.elevation(candidate, spacing)
			var score: float = elev + _pad_slope_degrees(shape, candidate, spacing) * 0.2
			if score < best_score:
				best_score = score
				best = candidate
	if best_score >= INF:
		best = start
	return _walk_toward_water(shape, partition, patch_id, best, spacing, half_span)


func _shore_border_dirs(patch_id: int) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	for chain in partition.border_chains:
		if chain.patch_b != -1 or chain.patch_a != patch_id:
			continue
		if chain.dirs.is_empty():
			continue
		var stride := maxi(1, int(ceil(float(chain.dirs.size()) / 10.0)))
		var index := 0
		while index < chain.dirs.size():
			var direction: Vector3 = chain.dirs[index]
			if direction.length_squared() > 0.25:
				dirs.append(direction.normalized())
			index += stride
	return dirs


func _walk_toward_water(
		shape: PlanetShape,
		cut: LandPartition,
		patch_id: int,
		start: Vector3,
		spacing: float,
		half_span: float
	) -> Vector3:
	var radius := maxf(shape.radius, 1.0)
	var at := start.normalized()
	var step := 32.0 / radius
	for _pass in 16:
		var east := at.cross(Vector3.RIGHT)
		if east.length_squared() < 0.01:
			east = at.cross(Vector3.FORWARD)
		east = east.normalized()
		var north := at.cross(east).normalized()
		var best := at
		var best_elev := shape.elevation(at, spacing)
		for spoke in 8:
			var yaw := TAU * float(spoke) / 8.0
			var nxt := (at + (east * cos(yaw) + north * sin(yaw)) * step).normalized()
			if not _monument_pad_ok(shape, cut, patch_id, nxt, spacing, half_span):
				continue
			var elev := shape.elevation(nxt, spacing)
			if elev < best_elev - 0.6:
				best_elev = elev
				best = nxt
		if best.dot(at) > 0.999999:
			break
		at = best
	return at


func _monument_pad_ok(
		shape: PlanetShape,
		cut: LandPartition,
		patch_id: int,
		direction: Vector3,
		spacing: float,
		half_span: float
	) -> bool:
	if direction.length_squared() < 0.25:
		return false
	var up := direction.normalized()
	if not cut.belongs_to(up, patch_id):
		return false
	var elev := shape.elevation(up, spacing)
	if elev < 8.0:
		return false
	var parts := shape.sample(up)
	if float(parts.get("river", 0.0)) > 0.25 \
			or float(parts.get("lake", 0.0)) > 0.45:
		return false
	if _pad_slope_degrees(shape, up, spacing) > 8.0:
		return false
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var ring := maxf(half_span, 8.0) / maxf(shape.radius, 1.0)
	for step in 8:
		var yaw := TAU * float(step) / 8.0
		var sample := (up + (east * cos(yaw) + north * sin(yaw)) * ring).normalized()
		if shape.elevation(sample, spacing) < 4.0:
			return false
	return true


func _inland_axis(up: Vector3) -> Vector3:
	var hint := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var axis := hint - up * hint.dot(up)
	if axis.length_squared() < 0.0001:
		return Vector3.RIGHT
	return axis.normalized()


func _slope_degrees(shape: PlanetShape, direction: Vector3, spacing: float) -> float:
	var up := direction.normalized()
	var normal := shape.normal_at(up, spacing)
	return rad_to_deg(acos(clampf(normal.dot(up), -1.0, 1.0)))


func _pad_slope_degrees(shape: PlanetShape, direction: Vector3, spacing: float) -> float:
	var steepest := _slope_degrees(shape, direction, spacing)
	var up := direction.normalized()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var radius := maxf(shape.radius, 1.0)
	var ring := 7.0 / radius
	for step in 6:
		var yaw := TAU * float(step) / 6.0
		var sample := (up + (east * cos(yaw) + north * sin(yaw)) * ring).normalized()
		steepest = maxf(steepest, _slope_degrees(shape, sample, spacing))
	return steepest


func _surface_transform_at(planet: Planet, direction: Vector3, clearance: float) -> Transform3D:
	var facing := direction.normalized() if direction.length_squared() > 0.0001 \
		else Vector3.UP
	var at := planet.surface_position(facing)
	var up := planet.up_at(at)
	at += up * clearance
	var forward := Vector3.FORWARD
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	if right.length_squared() < 0.0001:
		return Transform3D(Basis.IDENTITY, at)
	return Transform3D(
		Basis(right, up, right.cross(up).normalized()).orthonormalized(),
		at
	)


func keeps_mobs_out(at: Vector3) -> bool:
	if not at.is_finite():
		return false
	if is_inside_tree() and CrawlerCityRingScript.clears_patch_mobs_any(get_tree(), at):
		return true
	for held in all_cities():
		var city := held as PatchCity
		if city == null:
			continue
		if city.contains_world(at):
			return true
		var reach := city.city_extent() + CrawlerRules.CITY_SAFE_PAD
		if at.distance_to(city.world_centre()) <= reach:
			return true
	return false


func push_out_of_cities(at: Vector3, pad := 1.2) -> Vector3:
	var pushed := at
	if is_inside_tree():
		pushed = CrawlerCityRingScript.push_out_any(get_tree(), pushed, pad)
	for held in all_cities():
		var city := held as PatchCity
		if city == null:
			continue
		var reach := city.city_extent() + CrawlerRules.CITY_SAFE_PAD + pad
		if not city.contains_world(pushed) \
				and pushed.distance_to(city.world_centre()) > reach:
			continue
		var centre := city.world_centre()
		var up := city.world_up()
		var radial := pushed - centre
		radial -= up * radial.dot(up)
		if radial.length_squared() < 0.0001:
			radial = city.world_east() if city.has_method(&"world_east") else Vector3.RIGHT
			radial -= up * radial.dot(up)
		if radial.length_squared() < 0.0001:
			radial = Vector3.RIGHT
		var height := (pushed - centre).dot(up)
		pushed = centre + radial.normalized() * reach + up * height
	return pushed


func all_cities() -> Array:
	var out: Array = []
	for patch_id in _cities:
		var city := _city_at(int(patch_id))
		if city != null:
			out.append(city)
	return out


func ensure_crawler_waypoints() -> void:
	if not CrawlerRules.active():
		return
	for held in all_cities():
		var city := held as PatchCity
		if city != null:
			city.ensure_crawler_waypoint()


func _city_key(patch_id: int) -> int:
	var tid := partition.territory_id_of(patch_id)
	return tid if tid >= 0 else patch_id


func _bake_name(patch_id: int) -> String:
	var named := partition.recipe_name_of(patch_id)
	if not named.is_empty():
		return named
	if patch_id >= 0 and patch_id < partition.patches.size():
		return partition.patches[patch_id].name
	return ""


func _city_at(patch_id: int) -> PatchCity:
	var key := _city_key(patch_id)
	if not _cities.has(key):
		if not _cities.has(patch_id):
			return null
		key = patch_id
	var held: Variant = _cities[key]
	if not is_instance_valid(held):
		_cities.erase(key)
		return null
	return held as PatchCity


func _process(_delta: float) -> void:
	_refresh_city_maps()
	_refresh_patch_labels()


func _refresh_city_maps() -> void:
	var eye := Vector3.ZERO
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		eye = cam.global_position
	for patch_id in _cities:
		var city := _city_at(int(patch_id))
		if city != null:
			city.refresh_map(_enabled, eye)


func _refresh_patch_labels() -> void:
	var show := _enabled and _camera_altitude() >= PatchCity.PATCH_NAME_ALT
	for label in _labels:
		if is_instance_valid(label):
			label.visible = show
	if is_instance_valid(_borders):
		_borders.visible = _enabled


func _camera_altitude() -> float:
	if not is_inside_tree():
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return 0.0
	var local := planet.to_local(cam.global_position)
	if local.length_squared() < 1.0:
		return 0.0
	var up := local.normalized()
	return local.length() - planet.shape.radius - planet.shape.elevation(
		up, planet.spacing_underfoot())


func _rebuild() -> void:
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return
	planet.shape.prepare()
	var mountains := PackedVector3Array()
	for child in planet.get_children():
		if not is_instance_valid(child):
			continue
		var landmark := child as Landmark
		if landmark == null:
			continue
		if String(landmark.name).begins_with("GiantMountain"):
			if landmark.direction.length_squared() > 0.001:
				mountains.append(landmark.direction.normalized())
	_flat_dirs.clear()
	_high_dirs.clear()
	partition.bake(
		planet.shape, mountains, mountain_clearance, target_span, cell_span)
	_build_borders(planet)
	_build_labels(planet)
	_baked = true
	visible = _enabled
	if is_instance_valid(_borders):
		_borders.visible = _enabled


func _build_borders(planet: Planet) -> void:
	if is_instance_valid(_borders):
		_borders.queue_free()
	if partition.border_chains.is_empty() or planet.shape == null:
		return
	var shape := planet.shape
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for chain in partition.border_chains:
		var draped := PackedVector3Array()
		if chain.patch_a >= 0 and chain.patch_b >= 0:
			draped = _drape_bisector(shape, chain)
		else:
			draped = _drape_chain(shape, chain.dirs, chain.closed)
		_emit_ribbon(st, draped)
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(
		PALETTE.accent.r, PALETTE.accent.g, PALETTE.accent.b, 0.92)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	_borders = MeshInstance3D.new()
	_borders.name = "Borders"
	_borders.mesh = mesh
	_borders.material_override = material
	_borders.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_borders)


func _drape_bisector(shape: PlanetShape, chain: LandPartition.BorderChain) -> PackedVector3Array:
	var seed_a := partition.patches[chain.patch_a].seed
	var seed_b := partition.patches[chain.patch_b].seed
	var normal := seed_a - seed_b
	if normal.length_squared() < 0.0000001 or chain.dirs.size() < 2:
		return _drape_chain(shape, chain.dirs, chain.closed)
	if chain.closed:
		return _drape_bisector_loop(shape, chain.dirs, normal)
	var a := _on_bisector(chain.dirs[0], normal)
	var b := _on_bisector(chain.dirs[chain.dirs.size() - 1], normal)
	return _drape_slerp(shape, a, b)


func _drape_bisector_loop(
		shape: PlanetShape,
		dirs: PackedVector3Array,
		normal: Vector3
	) -> PackedVector3Array:
	var axis := normal.normalized()
	var pole := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(pole).normalized()
	var v := axis.cross(u)
	var angles: PackedFloat32Array = PackedFloat32Array()
	angles.resize(dirs.size())
	for index in dirs.size():
		var on := _on_bisector(dirs[index], normal)
		angles[index] = atan2(on.dot(v), on.dot(u))
	var sorted := Array(angles)
	sorted.sort()
	var gap := -1.0
	var gap_after := 0
	for index in sorted.size():
		var next_ang: float = float(sorted[(index + 1) % sorted.size()])
		var at: float = float(sorted[index])
		var span := next_ang - at
		if index == sorted.size() - 1:
			span = next_ang + TAU - at
		if span > gap:
			gap = span
			gap_after = index
	var from: float = float(sorted[(gap_after + 1) % sorted.size()])
	var to: float = float(sorted[gap_after])
	if gap_after == sorted.size() - 1:
		to += TAU
	if to < from:
		to += TAU
	var start := (u * cos(from) + v * sin(from)).normalized()
	var stop := (u * cos(to) + v * sin(to)).normalized()
	return _drape_slerp(shape, start, stop)


func _on_bisector(direction: Vector3, normal: Vector3) -> Vector3:
	var axis := normal.normalized()
	var on := direction - axis * direction.dot(axis)
	if on.length_squared() < 0.0000001:
		return direction.normalized()
	return on.normalized()


func _drape_slerp(shape: PlanetShape, a: Vector3, b: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var arc := a.angle_to(b) * shape.radius
	var pieces := maxi(1, int(ceili(arc / maxf(border_step, 1.0))))
	for piece in pieces + 1:
		var t := float(piece) / float(pieces)
		points.append(_surface_mark(shape, a.slerp(b, t)))
	return points


func _drape_chain(
		shape: PlanetShape,
		dirs: PackedVector3Array,
		closed: bool
	) -> PackedVector3Array:
	var points := PackedVector3Array()
	var count := dirs.size()
	if count < 2:
		return points
	var segments := count if closed else count - 1
	var step := maxf(border_step, 1.0)
	for index in segments:
		var a := dirs[index]
		var b := dirs[(index + 1) % count]
		var arc := a.angle_to(b) * shape.radius
		var pieces := maxi(1, int(ceili(arc / step)))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			points.append(_surface_mark(shape, a.slerp(b, t)))
	if not closed:
		points.append(_surface_mark(shape, dirs[count - 1]))
	return points


func _surface_mark(shape: PlanetShape, direction: Vector3) -> Vector3:
	var up := direction.normalized()
	return shape.surface_point(up) + up * border_lift


func _emit_ribbon(st: SurfaceTool, points: PackedVector3Array) -> void:
	var count := points.size()
	if count < 2:
		return
	for index in count - 1:
		var pa := points[index]
		var pb := points[index + 1]
		var chord := pb - pa
		if chord.length_squared() < 0.01:
			continue
		var up := ((pa + pb) * 0.5).normalized()
		var side := up.cross(chord)
		if side.length_squared() < 0.0001:
			continue
		side = side.normalized() * border_half_width
		st.add_vertex(pa - side)
		st.add_vertex(pa + side)
		st.add_vertex(pb + side)
		st.add_vertex(pa - side)
		st.add_vertex(pb + side)
		st.add_vertex(pb - side)


func _build_labels(planet: Planet) -> void:
	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()
	var shape := planet.shape
	for patch in partition.patches:
		var up := patch.direction.normalized()
		var at := shape.surface_point(up)
		var height := clampf(patch.span * 0.11, 28.0, 120.0)
		var label := Label3D.new()
		label.text = patch.name.to_upper()
		label.font = FONT
		label.font_size = 28
		label.pixel_size = height / 28.0
		label.modulate = PALETTE.accent
		label.outline_size = 8
		label.outline_modulate = PALETTE.ink
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = false
		label.visible = false
		label.position = at + up * (height * 0.32 + 16.0)
		add_child(label)
		_labels.append(label)
