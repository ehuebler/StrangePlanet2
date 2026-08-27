extends Node

## Reproducible, read-only survey for Bigfoot's forest arena.
##
## The search reads the exact PlanetShape resource and ForestGiants population
## instanced by game/world.tscn. It never adds a scar, changes a city, flattens a
## pad, or writes a resource. Candidate habitat is accepted by GroundCover's own
## habitat_reason ladder, and patch strength uses the same seeded FastNoiseLite
## and PlantSpecies.patch_level gate as the runtime scatter.
##
##     godot --headless --path . dev/_bigfoot_site.tscn -- --survey-only
##     godot --headless --path . dev/_bigfoot_site.tscn

const WORLD_PATH := "res://game/world.tscn"
const SITE_SCRIPT_PATH := "res://game/enemies/bigfoot/bigfoot_site.gd"
const BOSS_SCENE_PATH := "res://game/enemies/bigfoot/bigfoot.tscn"

const TARGET_ARC_DEGREES := 72.0
const SEARCH_ARC_MIN := 70.0
const SEARCH_ARC_MAX := 74.0
const SEARCH_ARC_STEP := 0.5
const BEARING_STEPS := 360
const COARSE_KEEP := 16
const REFINED_KEEP := 24
const REFINEMENT_STEP := 30.0
const REFINEMENT_STEPS := 3

## A 200 m diameter is large enough to test an arena and its approaches rather
## than merely finding one flat place to stand the capsule.
const NEIGHBORHOOD_RADIUS := 100.0
const DETAIL_STEP := 25.0
const CENTRE_FOOTPRINT_RADIUS := 12.0
const TERRAIN_SPACING := 1.5
const DRY_ELEVATION := 8.0
const WALKABLE_SLOPE := 18.0
const DENSE_FOREST_LEVEL := 0.28

const MIN_SETTLEMENT_CLEARANCE := 2000.0
const MIN_VOLCANO_EDGE_CLEARANCE := 1200.0
const MIN_HABITAT_SHARE := 0.60
const MIN_FOREST_SCORE := 0.22
const MIN_DENSE_SHARE := 0.35
const MIN_DRY_SHARE := 0.96
const MIN_USABLE_SHARE := 0.85
const MAX_CENTRE_SLOPE := 8.0
const MAX_P90_SLOPE := 16.0
const MAX_NEIGHBOR_SLOPE := 24.0
const MAX_FOOTPRINT_SPREAD := 3.0

var _failures := 0
var _shape: PlanetShape
var _planet: Planet
var _forest: GroundCover
var _colony := Vector3.ZERO
var _settlements: Array[Dictionary] = []
var _patches: Array[FastNoiseLite] = []


func _ready() -> void:
	var packed := load(WORLD_PATH) as PackedScene
	if packed == null:
		_fail("could not load " + WORLD_PATH)
		get_tree().quit(_failures)
		return
	var world := packed.instantiate()
	_planet = world.get_node_or_null("Planet") as Planet
	_forest = world.get_node_or_null("Planet/BiomePopulations/ForestGiants") \
		as GroundCover
	var colony_anchor := world.get_node_or_null("Planet/VacationersLanding") as SurfaceAnchor
	if _planet == null or _planet.shape == null:
		_fail("world has no configured PlanetShape")
	if _forest == null or _forest.species.is_empty():
		_fail("world has no ForestGiants GroundCover species")
	if colony_anchor == null:
		_fail("world has no VacationersLanding direction")
	if _failures > 0:
		world.free()
		get_tree().quit(_failures)
		return

	_shape = _planet.shape
	_shape.prepare()
	_colony = colony_anchor.direction.normalized()
	_bind_forest()
	_collect_clearances()

	var scars_before := _shape.scars.count()
	var terrain_before := _terrain_checksum()
	var winner := _search()
	var terrain_after := _terrain_checksum()
	_check(_shape.scars.count() == scars_before,
		"survey did not add terrain scars")
	_check(is_equal_approx(terrain_before, terrain_after),
		"survey left the terrain field unchanged")

	if winner.is_empty():
		_fail("no forest arena met the survey limits")
	else:
		print("\nWINNER")
		_say(winner, "winner")
		if not OS.get_cmdline_user_args().has("--survey-only"):
			_verify_baked(world, winner)

	world.free()
	if _failures == 0:
		print("\nBIGFOOT SITE VALIDATION PASSED")
	else:
		printerr("\nBIGFOOT SITE VALIDATION FAILED: %d issue(s)" % _failures)
	get_tree().quit(_failures)


func _bind_forest() -> void:
	## These are the three values GroundCover resolves from its Planet in _ready.
	## Binding them directly keeps this harness read-only and avoids starting the
	## world's terrain/flora streaming merely to ask the public habitat diagnostic.
	_forest.set("_shape", _shape)
	_forest.set("_radius", _shape.radius)
	_forest.set("_spacing", TERRAIN_SPACING)
	for plant: PlantSpecies in _forest.species:
		var patch := FastNoiseLite.new()
		patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		patch.seed = plant.random_seed
		patch.frequency = 1.0 / maxf(plant.patch_size, 1.0)
		_patches.append(patch)


func _collect_clearances() -> void:
	_settlements.append({"name": "VacationersLanding", "direction": _colony})
	for plan: CityPlan in Settlements.plans():
		_settlements.append({
			"name": plan.title,
			"direction": plan.centre.normalized(),
		})


func _search() -> Dictionary:
	print("Bigfoot arena survey: %.1f +/- %.1f degrees from VacationersLanding, "
		% [TARGET_ARC_DEGREES, SEARCH_ARC_MAX - TARGET_ARC_DEGREES]
		+ "ForestGiants habitat, 200 m neighborhood")
	print("  species: %s" % ", ".join(_species_names()))

	var coarse: Array[Dictionary] = []
	var arc_steps := roundi((SEARCH_ARC_MAX - SEARCH_ARC_MIN) \
		/ SEARCH_ARC_STEP) + 1
	for arc_index in arc_steps:
		var arc := SEARCH_ARC_MIN + float(arc_index) * SEARCH_ARC_STEP
		for bearing_index in BEARING_STEPS:
			var direction := _on_colony_ring(
				arc, 360.0 * float(bearing_index) / float(BEARING_STEPS))
			if not _basic_allowed(direction):
				continue
			var measured := _measure(direction, _coarse_offsets(), false)
			if float(measured["dry_share"]) < 0.75 \
					or float(measured["usable_share"]) < 0.65 \
					or float(measured["habitat_share"]) < 0.35:
				continue
			coarse.append(measured)
	coarse.sort_custom(_better)
	print("  coarse survivors: %d of %d ring candidates" % [
		coarse.size(), arc_steps * BEARING_STEPS])
	if coarse.is_empty():
		return {}

	var seeds: Array[Dictionary] = []
	for candidate: Dictionary in coarse:
		if seeds.size() >= COARSE_KEEP:
			break
		var direction: Vector3 = candidate["direction"]
		var separate := true
		for kept: Dictionary in seeds:
			if direction.angle_to(kept["direction"]) * _shape.radius < 150.0:
				separate = false
				break
		if separate:
			seeds.append(candidate)

	var refined: Array[Dictionary] = []
	for seed: Dictionary in seeds:
		var centre: Vector3 = seed["direction"]
		for row in range(-REFINEMENT_STEPS, REFINEMENT_STEPS + 1):
			for column in range(-REFINEMENT_STEPS, REFINEMENT_STEPS + 1):
				var direction := _at_offset(centre, Vector2(column, row) \
					* REFINEMENT_STEP)
				if not _basic_allowed(direction):
					continue
				var measured := _measure(direction, _coarse_offsets(), false)
				if float(measured["dry_share"]) >= 0.75 \
						and float(measured["usable_share"]) >= 0.65 \
						and float(measured["habitat_share"]) >= 0.35:
					refined.append(measured)
	refined.sort_custom(_better)

	var detailed: Array[Dictionary] = []
	for candidate: Dictionary in refined:
		if detailed.size() >= REFINED_KEEP:
			break
		var direction: Vector3 = candidate["direction"]
		var duplicate := false
		for kept: Dictionary in detailed:
			if direction.angle_to(kept["direction"]) * _shape.radius < 25.0:
				duplicate = true
				break
		if duplicate:
			continue
		detailed.append(_measure(direction, _detail_offsets(), true))
	detailed.sort_custom(_better)

	print("\nDetailed candidates, best first:")
	for index in mini(8, detailed.size()):
		_say(detailed[index], "#%d" % (index + 1))
	for candidate: Dictionary in detailed:
		if bool(candidate["qualified"]):
			return candidate
	return {}


func _measure(direction: Vector3, offsets: Array[Vector2],
		detailed: bool) -> Dictionary:
	var slopes := PackedFloat32Array()
	var elevations := PackedFloat32Array()
	var dry_count := 0
	var usable_count := 0
	var dense_count := 0
	var habitat_weight := 0.0
	var patch_weight := 0.0
	var total_weight := 0.0
	var density_total := 0.0
	for plant: PlantSpecies in _forest.species:
		density_total += plant.per_square_metre

	for offset: Vector2 in offsets:
		var at := _at_offset(direction, offset)
		var height := _shape.elevation(at, TERRAIN_SPACING)
		var parts := _shape.sample(at)
		var dry := height >= DRY_ELEVATION \
			and float(parts.get("river", 0.0)) <= 0.0 \
			and float(parts.get("lake", 0.0)) <= 0.0
		var slope := _slope(at)
		elevations.append(height)
		slopes.append(slope)
		if dry:
			dry_count += 1
		if dry and slope <= WALKABLE_SLOPE:
			usable_count += 1

		var point_forest := 0.0
		for species_index in _forest.species.size():
			var plant := _forest.species[species_index]
			var weight := plant.per_square_metre
			total_weight += weight
			if _forest.habitat_reason(plant, at) != &"grows":
				continue
			habitat_weight += weight
			var patch := _patch_strength(species_index, plant, at)
			patch_weight += weight * patch
			point_forest += weight * patch
		if density_total > 0.0 \
				and point_forest / density_total >= DENSE_FOREST_LEVEL:
			dense_count += 1

	slopes.sort()
	var count := maxi(offsets.size(), 1)
	var center_height := _shape.elevation(direction, TERRAIN_SPACING)
	var p90_index := clampi(ceili(float(slopes.size()) * 0.9) - 1,
		0, maxi(slopes.size() - 1, 0))
	var footprint_spread := _footprint_spread(direction) if detailed else 0.0
	var settlement := _nearest_settlement(direction)
	var volcano_distance := direction.angle_to(_shape.volcano_axis()) \
		* _shape.radius
	var measured := {
		"direction": direction,
		"arc": rad_to_deg(direction.angle_to(_colony)),
		"elevation": center_height,
		"elevation_min": _minimum(elevations),
		"elevation_max": _maximum(elevations),
		"dry_share": float(dry_count) / float(count),
		"usable_share": float(usable_count) / float(count),
		"center_slope": _slope(direction),
		"average_slope": _average(slopes),
		"p90_slope": slopes[p90_index] if not slopes.is_empty() else INF,
		"max_slope": _maximum(slopes),
		"footprint_spread": footprint_spread,
		"habitat_share": habitat_weight / maxf(total_weight, 0.000001),
		"patch_share": patch_weight / maxf(habitat_weight, 0.000001),
		"forest_score": patch_weight / maxf(total_weight, 0.000001),
		"dense_share": float(dense_count) / float(count),
		"settlement_name": settlement["name"],
		"settlement_clearance": settlement["distance"],
		"volcano_distance": volcano_distance,
		"volcano_clearance": volcano_distance - _shape.volcano_radius,
		"samples": offsets.size(),
		"detailed": detailed,
	}
	measured["score"] = _score(measured)
	measured["qualified"] = detailed and _qualifies(measured)
	return measured


func _score(candidate: Dictionary) -> float:
	return float(candidate["forest_score"]) * 100.0 \
		+ float(candidate["habitat_share"]) * 30.0 \
		+ float(candidate["dense_share"]) * 20.0 \
		+ float(candidate["usable_share"]) * 20.0 \
		+ float(candidate["dry_share"]) * 15.0 \
		- float(candidate["p90_slope"]) * 0.8 \
		- absf(float(candidate["arc"]) - TARGET_ARC_DEGREES) * 4.0 \
		- float(candidate["footprint_spread"]) * 1.5


func _qualifies(candidate: Dictionary) -> bool:
	return absf(float(candidate["arc"]) - TARGET_ARC_DEGREES) <= 2.0 \
		and float(candidate["habitat_share"]) >= MIN_HABITAT_SHARE \
		and float(candidate["forest_score"]) >= MIN_FOREST_SCORE \
		and float(candidate["dense_share"]) >= MIN_DENSE_SHARE \
		and float(candidate["dry_share"]) >= MIN_DRY_SHARE \
		and float(candidate["usable_share"]) >= MIN_USABLE_SHARE \
		and float(candidate["center_slope"]) <= MAX_CENTRE_SLOPE \
		and float(candidate["p90_slope"]) <= MAX_P90_SLOPE \
		and float(candidate["max_slope"]) <= MAX_NEIGHBOR_SLOPE \
		and float(candidate["footprint_spread"]) <= MAX_FOOTPRINT_SPREAD \
		and float(candidate["elevation_min"]) >= DRY_ELEVATION \
		and float(candidate["settlement_clearance"]) \
			>= MIN_SETTLEMENT_CLEARANCE \
		and float(candidate["volcano_clearance"]) \
			>= MIN_VOLCANO_EDGE_CLEARANCE


func _basic_allowed(direction: Vector3) -> bool:
	var arc := rad_to_deg(direction.angle_to(_colony))
	if arc < SEARCH_ARC_MIN - 0.8 or arc > SEARCH_ARC_MAX + 0.8:
		return false
	var parts := _shape.sample(direction)
	var height := _shape.elevation(direction, TERRAIN_SPACING)
	if height < DRY_ELEVATION \
			or float(parts.get("river", 0.0)) > 0.0 \
			or float(parts.get("lake", 0.0)) > 0.0 \
			or _slope(direction) > WALKABLE_SLOPE:
		return false
	if float(_nearest_settlement(direction)["distance"]) \
			< MIN_SETTLEMENT_CLEARANCE:
		return false
	var volcano_clearance := direction.angle_to(_shape.volcano_axis()) \
		* _shape.radius - _shape.volcano_radius
	return volcano_clearance >= MIN_VOLCANO_EDGE_CLEARANCE


func _patch_strength(index: int, plant: PlantSpecies, at: Vector3) -> float:
	var here := at * _shape.radius
	var level := PlantSpecies.patch_level(plant.bare_share)
	return smoothstep(level, level + PlantSpecies.PATCH_EDGE,
		_patches[index].get_noise_3d(here.x, here.y, here.z))


func _nearest_settlement(direction: Vector3) -> Dictionary:
	var nearest := {"name": "", "distance": INF}
	for settlement: Dictionary in _settlements:
		var distance := direction.angle_to(settlement["direction"]) * _shape.radius
		if distance < float(nearest["distance"]):
			nearest = {
				"name": settlement["name"],
				"distance": distance,
			}
	return nearest


func _coarse_offsets() -> Array[Vector2]:
	var offsets: Array[Vector2] = [Vector2.ZERO]
	for radius in [50.0, NEIGHBORHOOD_RADIUS]:
		for index in 8:
			var turn := TAU * float(index) / 8.0
			offsets.append(Vector2(cos(turn), sin(turn)) * radius)
	return offsets


func _detail_offsets() -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var reach := roundi(NEIGHBORHOOD_RADIUS / DETAIL_STEP)
	for row in range(-reach, reach + 1):
		for column in range(-reach, reach + 1):
			var offset := Vector2(column, row) * DETAIL_STEP
			if offset.length() <= NEIGHBORHOOD_RADIUS + 0.01:
				offsets.append(offset)
	return offsets


func _footprint_spread(direction: Vector3) -> float:
	var low := INF
	var high := -INF
	for index in 16:
		var turn := TAU * float(index) / 16.0
		var at := _at_offset(direction, Vector2(cos(turn), sin(turn)) \
			* CENTRE_FOOTPRINT_RADIUS)
		var height := _shape.elevation(at, TERRAIN_SPACING)
		low = minf(low, height)
		high = maxf(high, height)
	return high - low


func _slope(direction: Vector3) -> float:
	var normal := _shape.normal_at(direction, TERRAIN_SPACING)
	return rad_to_deg(acos(clampf(normal.dot(direction), -1.0, 1.0)))


func _on_colony_ring(arc_degrees: float, bearing_degrees: float) -> Vector3:
	var frame := _frame(_colony)
	var arc := deg_to_rad(arc_degrees)
	var bearing := deg_to_rad(bearing_degrees)
	var tangent := frame[0] * cos(bearing) + frame[1] * sin(bearing)
	return (_colony * cos(arc) + tangent * sin(arc)).normalized()


func _at_offset(direction: Vector3, offset: Vector2) -> Vector3:
	if offset.length_squared() < 0.000001:
		return direction
	var frame := _frame(direction)
	var distance := offset.length()
	var tangent := (frame[0] * offset.x + frame[1] * offset.y) / distance
	var arc := distance / _shape.radius
	return (direction * cos(arc) + tangent * sin(arc)).normalized()


func _frame(up: Vector3) -> Array[Vector3]:
	var hint := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var east := up.cross(hint).normalized()
	return [east, up.cross(east).normalized()]


func _terrain_checksum() -> float:
	var checksum := 0.0
	for index in 24:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / 24.0
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		var turn := PI * (1.0 + sqrt(5.0)) * float(index)
		var direction := Vector3(cos(turn) * ring, y, sin(turn) * ring)
		checksum += _shape.elevation(direction, TERRAIN_SPACING) \
			* float(index + 1)
	return checksum


func _species_names() -> PackedStringArray:
	var names := PackedStringArray()
	for plant: PlantSpecies in _forest.species:
		names.append(plant.resource_name)
	return names


func _better(a: Dictionary, b: Dictionary) -> bool:
	return float(a["score"]) > float(b["score"])


func _minimum(values: PackedFloat32Array) -> float:
	var value := INF
	for item: float in values:
		value = minf(value, item)
	return value


func _maximum(values: PackedFloat32Array) -> float:
	var value := -INF
	for item: float in values:
		value = maxf(value, item)
	return value


func _average(values: PackedFloat32Array) -> float:
	var total := 0.0
	for item: float in values:
		total += item
	return total / maxf(float(values.size()), 1.0)


func _say(candidate: Dictionary, label: String) -> void:
	var direction: Vector3 = candidate["direction"]
	print(("  %s Vector3(%.9f, %.9f, %.9f) arc=%.3f deg score=%.2f "
		+ "forest=%.1f%% habitat=%.1f%% patch=%.1f%% dense=%.1f%% "
		+ "elev=%.1f m [%.1f, %.1f] dry=%.1f%% usable=%.1f%% "
		+ "slope centre/avg/p90/max=%.2f/%.2f/%.2f/%.2f deg "
		+ "footprint=%.2f m settlement=%s %.0f m "
		+ "volcano centre/edge=%.0f/%.0f m samples=%d qualified=%s") % [
		label, direction.x, direction.y, direction.z,
		candidate["arc"], candidate["score"],
		float(candidate["forest_score"]) * 100.0,
		float(candidate["habitat_share"]) * 100.0,
		float(candidate["patch_share"]) * 100.0,
		float(candidate["dense_share"]) * 100.0,
		candidate["elevation"], candidate["elevation_min"],
		candidate["elevation_max"], float(candidate["dry_share"]) * 100.0,
		float(candidate["usable_share"]) * 100.0,
		candidate["center_slope"], candidate["average_slope"],
		candidate["p90_slope"], candidate["max_slope"],
		candidate["footprint_spread"], candidate["settlement_name"],
		candidate["settlement_clearance"], candidate["volcano_distance"],
		candidate["volcano_clearance"], candidate["samples"],
		candidate["qualified"],
	])


func _verify_baked(world: Node, winner: Dictionary) -> void:
	print("\nVerifying baked site and boss shell:")
	var site := world.get_node_or_null("Planet/BigfootTerritory")
	_check(site != null, "world contains Planet/BigfootTerritory")
	if site == null:
		return
	_check(site is SurfaceAnchor, "territory is SurfaceAnchor-compatible")
	_check(site is Landmark, "territory is a public Landmark")
	var landmark := site as Landmark
	_check(landmark.waypoint and landmark.title == "Bigfoot",
		"territory exposes the enabled Bigfoot waypoint")
	_check(landmark.hide_beyond == 0.0,
		"Bigfoot waypoint has no far-distance cutoff")
	_check(site.get_script() != null \
		and site.get_script().resource_path == SITE_SCRIPT_PATH,
		"territory uses the baked site script")

	var anchor := site as SurfaceAnchor
	var wanted: Vector3 = winner["direction"]
	var baked_distance := anchor.direction.normalized().angle_to(wanted) \
		* _shape.radius
	_check(baked_distance <= 0.05,
		"baked direction reproduces survey winner (%.3f m)" % baked_distance)
	anchor.place()
	var placed_up := anchor.position.normalized()
	_check(placed_up.angle_to(anchor.direction.normalized()) * _shape.radius < 0.05,
		"anchor stands in its baked direction")
	var expected_radius := _shape.radius + _shape.elevation(
		anchor.direction.normalized(), _planet.finest_spacing())
	_check(absf(anchor.position.length() - expected_radius) < 0.05,
		"anchor stands on the current PlanetShape")

	if site.has_method("survey_metrics"):
		var baked: Dictionary = site.call("survey_metrics")
		_check(absf(float(baked.get("arc_degrees", -1.0))
			- float(winner["arc"])) < 0.01, "baked arc metric matches survey")
		_check(absf(float(baked.get("forest_score", -1.0))
			- float(winner["forest_score"])) < 0.001,
			"baked forest metric matches survey")
		_check(absf(float(baked.get("usable_share", -1.0))
			- float(winner["usable_share"])) < 0.001,
			"baked neighborhood metric matches survey")
	else:
		_fail("site script has no human-readable survey metrics")

	var boss := site.get_node_or_null("Bigfoot")
	_check(boss is CharacterBody3D,
		"site instances a CharacterBody3D Bigfoot shell")
	if boss is CharacterBody3D:
		_verify_boss(boss as CharacterBody3D)


func _verify_boss(boss: CharacterBody3D) -> void:
	_check(boss.is_in_group(&"bigfoot_boss"),
		"boss shell declares the bigfoot_boss group")
	_check(boss.position.length() < 0.001,
		"boss shell is at the site anchor origin")
	var model := boss.get_node_or_null("Model") as Node3D
	_check(model != null, "boss shell contains the runtime Model")
	if model == null:
		return
	_check(model.scale.distance_to(Vector3.ONE) < 0.001,
		"model keeps its authored true-metre scale")
	_check((-model.basis.z).normalized().dot(Vector3.FORWARD) > 0.999,
		"model keeps authored Godot -Z facing")
	_check(_first_mesh(model) != null and _first_skeleton(model) != null,
		"runtime GLB mesh and skeleton are present")
	var bounds := _mesh_bounds(model)
	_check(absf(bounds.size.y - 3.2) < 0.08 \
		and absf(bounds.position.y) < 0.05,
		"visual bounds are grounded and approximately 3.2 m tall")

	var collision := boss.get_node_or_null("CollisionShape3D") as CollisionShape3D
	_check(collision != null and collision.shape is CapsuleShape3D,
		"boss shell has a capsule collision shape")
	if collision != null and collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		var bottom := collision.position.y - capsule.height * 0.5
		var top := collision.position.y + capsule.height * 0.5
		_check(absf(bottom) < 0.08 and absf(top - 3.2) < 0.15 \
			and capsule.radius >= 0.55 and capsule.radius <= 0.9,
			"collision capsule is sized and grounded to the model")

	for marker_name in [&"Mouth", &"RightFist", &"LeftFist", &"GrabSocket"]:
		_check(boss.find_child(String(marker_name), true, false) is Marker3D,
			"boss shell contains %s Marker3D" % marker_name)
	var right := boss.find_child("RightFist", true, false) as Marker3D
	var left := boss.find_child("LeftFist", true, false) as Marker3D
	if right != null and left != null:
		_check(right.position.x > 0.0 and left.position.x < 0.0,
			"fist markers use the model's anatomical sides")


func _mesh_bounds(root: Node3D) -> AABB:
	var state := {"has": false, "bounds": AABB()}
	_collect_mesh_bounds(root, Transform3D.IDENTITY, state)
	return state["bounds"]


func _collect_mesh_bounds(node: Node, into_root: Transform3D,
		state: Dictionary) -> void:
	var transform := into_root
	if node is Node3D and node != null:
		transform = into_root * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			var bounds := _transform_aabb(mesh.get_aabb(), transform)
			if bool(state["has"]):
				state["bounds"] = (state["bounds"] as AABB).merge(bounds)
			else:
				state["has"] = true
				state["bounds"] = bounds
	for child in node.get_children():
		_collect_mesh_bounds(child, transform, state)


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var made := AABB(transform * bounds.position, Vector3.ZERO)
	for x in 2:
		for y in 2:
			for z in 2:
				var corner := bounds.position + bounds.size * Vector3(x, y, z)
				made = made.expand(transform * corner)
	return made


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _first_skeleton(child)
		if found != null:
			return found
	return null


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property["name"]) == property_name:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS  " + message)
	else:
		_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)
