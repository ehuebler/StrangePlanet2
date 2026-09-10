extends Node

## Headless checks for the land-partition that city building starts from.
##
##     godot --headless --path . dev/_land_patch_test.tscn

var MOUNTAINS := PackedVector3Array([
	Vector3(-0.270521, -0.3052884, -0.9130266),
	Vector3(0.6848267, 0.0168872, 0.7285103),
	Vector3(0.2574172, -0.2996968, -0.9186503),
	Vector3(0.4474815, -0.0008659, -0.8942928),
])

var _failures := 0


func _ready() -> void:
	var shape := PlanetShape.new()
	shape.settled = false
	shape.prepare()
	var partition := LandPartition.new()
	partition.bake(shape, MOUNTAINS, 1000.0, 1300.0)
	_check(partition, shape)
	print("land_patch_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check(partition: LandPartition, shape: PlanetShape) -> void:
	_expect(partition.vertices.size() > 1000,
		"icosphere has a useful number of vertices")
	_expect(partition.buildable_count > 0, "some of the globe is buildable land")
	_expect(partition.patches.size() > 0, "buildable land was cut into patches")
	_expect(partition.territories.size() > 0
			and partition.patches.size() > partition.territories.size(),
		"the first cut was split into smaller named cells")
	_expect(partition.owners.size() == partition.vertices.size(),
		"every vertex has an owner slot")
	var named: Dictionary = {}
	var owned := 0
	for index in partition.vertices.size():
		var owner := partition.owners[index]
		var direction := partition.vertices[index]
		if owner < 0:
			continue
		owned += 1
		_expect(owner < partition.patches.size(),
			"owner %d is a real patch" % owner)
		if shape.elevation(direction, 0.0) < 0.0:
			_fail("a patch claimed underwater vertex %d" % index)
		if shape.frost(direction) > LandPartition.FROST_LIMIT:
			_fail("a patch claimed ice-cap vertex %d" % index)
		if shape.volcano_influence(direction) > LandPartition.VOLCANO_LIMIT:
			_fail("a patch claimed volcano vertex %d" % index)
	_expect(owned == partition.buildable_count,
		"every buildable vertex belongs to a patch, with no extras")
	var homes: Dictionary = {}
	for home in partition.territories:
		homes[home.id] = home.name
	for patch in partition.patches:
		_expect(not patch.name.is_empty(), "every patch has a name")
		_expect(not named.has(patch.name), "patch names are unique")
		named[patch.name] = true
		_expect(patch.area > 0.0, "%s covers some ground" % patch.name)
		_expect(not patch.recipe_name.is_empty()
				and homes.has(patch.parent_id)
				and str(homes[patch.parent_id]) == patch.recipe_name,
			"%s keeps its territory recipe" % patch.name)
	for home in partition.territories:
		_expect(partition.first_cell_of(home.id) >= 0
				and partition.recipe_name_of(partition.first_cell_of(home.id))
					== home.name,
			"%s still has a cell for spawn and cities" % home.name)
	_expect(partition.border_chains.size() >= 1,
		"patches have borders to draw")
	_check_owner_lookup(partition)
	for chain in partition.border_chains:
		_expect(chain.dirs.size() >= 2,
			"each border chain has at least one segment")
		_expect(chain.patch_a >= 0, "every chain has a patch on one side")
	for patch in partition.patches:
		_expect(patch.seed.length_squared() > 0.5,
			"%s has a Voronoi seed" % patch.name)
	print("land_patch_test: %d cells in %d territories, %.0f km², %d vertices, %d edges"
		% [
			partition.patches.size(),
			partition.territories.size(),
			partition.buildable_area / 1_000_000.0,
			partition.vertices.size(),
			partition.border_edge_count(),
		])
	var spawn_rest: LandPartition.Patch = null
	var lee_rest: LandPartition.Patch = null
	var crescent: LandPartition.Patch = null
	for patch in partition.patches:
		if patch.name == "Tide Margin 4":
			spawn_rest = patch
		elif patch.name == "Wind Gap 4":
			lee_rest = patch
		elif patch.name == "Far Beacon 4 Northwest":
			crescent = patch
		print("land_patch_test:   %s  %.0f km²  span %.0f m"
			% [patch.name, patch.area / 1_000_000.0, patch.span])
	_expect(spawn_rest != null, "Tide Margin 4 rest cell exists for the spawn pad")
	_expect(lee_rest != null, "Wind Gap 4 rest cell exists for the second later city")
	_expect(crescent != null, "Far Beacon 4 Northwest exists for Crescent Market")
	if spawn_rest != null:
		_expect(partition.first_cell_of(spawn_rest.parent_id) == spawn_rest.id,
			"Tide Margin 4 rest is the keep cell")
	if lee_rest != null:
		_expect(partition.first_cell_of(lee_rest.parent_id) == lee_rest.id,
			"Wind Gap 4 rest is the keep cell")


func _check_owner_lookup(partition: LandPartition) -> void:
	var samples: PackedVector3Array = PackedVector3Array()
	for home in partition.territories:
		samples.append(home.direction)
	for patch in partition.patches:
		samples.append(patch.direction)
		samples.append(patch.seed)
	var axes := PackedVector3Array([
		Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT,
		Vector3.FORWARD, Vector3.BACK,
		Vector3(0.18, 0.62, 0.76), Vector3(-0.41, 0.22, -0.88),
		Vector3(0.91, -0.14, 0.39), Vector3(-0.07, -0.83, 0.55),
	])
	for axis in axes:
		samples.append(axis)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for _i in 80:
		samples.append(Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		))
	var checked := 0
	for sample in samples:
		if not sample.is_finite() or sample.length_squared() < 0.0001:
			continue
		var fast := partition.owner_at(sample)
		var slow := partition.owner_at_scan(sample)
		_expect(fast == slow,
			"owner_at matches the vertex scan at %s" % sample)
		checked += 1
		if _failures > 0:
			break
	_expect(checked > 40, "owner_at was checked on a useful sample set")


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	push_error("land_patch_test: FAIL  %s" % message)
