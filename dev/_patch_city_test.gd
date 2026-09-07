extends Node

## Headless check that a patch can be laid out as districts plus one loop road.
##
##     godot --headless --path . dev/_patch_city_test.tscn

const CityMinimap := preload("res://game/city/city_minimap.gd")
const BuildingCatalog := preload("res://game/city/city_building_catalog.gd")

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
	var patch_id := _largest_patch(partition)
	_expect(patch_id >= 0, "partition produced a patch to lay out")
	var generator := PatchCityGenerator.new()
	var plan := generator.generate(shape, partition, patch_id)
	_check(plan, partition, patch_id, shape)
	var city := PatchCity.new()
	add_child(city)
	city.apply(plan, shape)
	_expect(city.phase == PatchCity.PHASE_LAYOUT, "first draw is the layout")
	_expect(city.advance(shape), "second step paves the layout")
	_expect(city.phase == PatchCity.PHASE_PAVED, "city is paved")
	_expect(city.get_node_or_null("Highway") != null, "paved highway mesh exists")
	_expect(city.get_node_or_null("HighwayBody") != null, "highway has collision")
	_expect(city.get_node_or_null("DistrictGround") != null, "district ground mesh exists")
	_expect(city.get_node_or_null("DistrictGroundBody") != null,
		"district slabs have collision")
	_expect_outward_tops(city, "DistrictGround")
	_expect_outward_tops(city, "Highway")
	_expect_road_above_pad(city, plan, shape)
	_expect_highway_deck(city, shape)
	_expect_pad_clears_ground(city, shape)
	_expect_pad_not_floating(city, shape)
	_expect_districts_not_buried(city, shape)
	_expect_district_aprons(city, shape)
	_expect_apron_uses_terrain_tint(city, shape)
	_expect(city.advance(shape), "third step draws the city map")
	_expect(city.phase == PatchCity.PHASE_MAPPED, "city is mapped")
	_expect_mapped(city, plan, shape)
	print("patch_city_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _largest_patch(partition: LandPartition) -> int:
	var best := -1
	var best_area := -1.0
	for home in partition.territories:
		if home.area > best_area:
			best_area = home.area
			best = home.id
	if best >= 0:
		var cell := partition.first_cell_of(best)
		if cell >= 0:
			return cell
	for patch in partition.patches:
		if patch.area > best_area:
			best_area = patch.area
			best = patch.id
	return best


func _check(
		plan: PatchCityGenerator.Plan,
		partition: LandPartition,
		patch_id: int,
		shape: PlanetShape
	) -> void:
	var home_id := partition.territory_id_of(patch_id)
	_expect(plan.patch_id == home_id, "plan is for the requested patch")
	_expect(not plan.districts.is_empty(), "the patch was cut into districts")
	var patch := partition.territory_of(patch_id)
	if patch == null:
		patch = partition.patches[patch_id]
	var radius := shape.radius
	for district in plan.districts:
		_expect(not district.name.is_empty(), "every district is named")
		_expect(district.dirs.size() >= PatchCityGenerator.MIN_GROUP,
			"%s is at least %d tiles" % [
				district.name, PatchCityGenerator.MIN_GROUP])
		for direction in district.dirs:
			_expect(partition.belongs_to(direction, patch_id),
				"%s stays inside the patch" % district.name)
	_expect_districts_clear_spikes(plan, shape)
	_expect(not plan.exits.is_empty(), "the loop has district exits")
	for exit in plan.exits:
		var run := exit.road.angle_to(exit.land) * shape.radius
		_expect(run > 60.0, "each exit leaves the highway (%.0f m)" % run)
		_expect(shape.elevation(exit.road, 22.0) >= 0.0, "exit mouth stays above water")
		_expect(shape.elevation(exit.land, 22.0) >= 0.0, "exit landing stays above water")
	_expect(plan.loop.size() >= 24, "city road is a race circuit")
	if plan.loop.size() >= 3:
		_expect(plan.loop[0].dot(plan.loop[plan.loop.size() - 1]) > 0.98,
			"city road is a closed loop")
		var farthest := 0.0
		for direction in plan.loop:
			farthest = maxf(farthest, patch.direction.angle_to(direction))
			_expect(shape.elevation(direction, 22.0) >= 0.0,
				"city road stays above the water")
		for direction in plan.extension:
			_expect(shape.elevation(direction, 22.0) >= 0.0,
				"road spur stays above the water")
		var loop_width := farthest * 2.0 * radius
		_expect(loop_width > patch.span * 0.35,
			"loop circumnavigates the patch (%.0f m vs patch %.0f m)"
			% [loop_width, patch.span])
	var ranks: Dictionary = {}
	for street in plan.streets:
		_expect(street.dirs.size() >= 2, "every street has a run")
		ranks[street.rank] = int(ranks.get(street.rank, 0)) + 1
	print("patch_city_test: %s — %d districts, loop %d, stub %d, streets %d"
		% [
			plan.patch_name,
			plan.districts.size(),
			plan.loop.size(),
			plan.extension.size(),
			plan.streets.size(),
		])
	print("patch_city_test:   %d highway exits" % plan.exits.size())
	for district in plan.districts:
		print("patch_city_test:   %s  span %.0f m"
			% [district.name, district.span])


func _expect_mapped(
		city: PatchCity,
		plan: PatchCityGenerator.Plan,
		shape: PlanetShape
	) -> void:
	var wanted := plan.districts.size() + plan.exits.size() + 1
	_expect(city.places.size() >= wanted,
		"map names every district, exit and the road (%d places, wanted >= %d)"
		% [city.places.size(), wanted])
	_expect(not plan.road_name.is_empty(), "the city road has a name")
	var ids: Dictionary = {}
	var kinds: Dictionary = {}
	for place in city.places:
		_expect(not place.id.is_empty(), "every mapped place has an id")
		_expect(not place.name.is_empty(), "every mapped place has a name")
		_expect(not place.node_name.is_empty(), "every mapped place has a landmark name")
		_expect(place.direction.length_squared() > 0.5, "%s has coordinates" % place.name)
		_expect(not ids.has(place.id), "place ids are unique (%s)" % place.id)
		ids[place.id] = true
		kinds[place.kind] = int(kinds.get(place.kind, 0)) + 1
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_DISTRICT, 0)) == plan.districts.size(),
		"every district is in the gazetteer")
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_EXIT, 0)) == plan.exits.size(),
		"every exit is in the gazetteer")
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_ROAD, 0)) == 1, "the city road is in the gazetteer")
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_STREET, 0)) > 0, "streets are named on the map")
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_BUILDING, 0)) > 0, "buildings are named on the map")
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_LANDMARK, 0)) > 0,
		"each district has a unique building")
	_expect(int(kinds.get(PatchCity.CityPlace.KIND_TOWN_CENTER, 0)) == 1,
		"the biggest district has one town center")
	for exit in plan.exits:
		_expect(not exit.name.is_empty(), "every exit is named")
	var mapped := city.get_node_or_null("CityMap") as Node3D
	_expect(mapped != null, "mapped city keeps a CityMap node")
	if mapped != null:
		_expect(mapped.get_node_or_null("MapLines") == null,
			"city map does not stroke roads in the world")
		var names := mapped.get_node_or_null("StreetNames") as Node3D
		_expect(names != null and names.get_child_count() > 0,
			"street names lie on the ground")
		if names != null and names.get_child_count() > 0:
			var sample := names.get_child(0) as Label3D
			_expect(sample != null and sample.billboard == BaseMaterial3D.BILLBOARD_DISABLED,
				"street names stay flattened on the ground")
		var marks := mapped.get_node_or_null("SpecialMarks") as Node3D
		_expect(marks != null and marks.get_child_count() > 0,
			"special buildings carry diamond marks")
	_expect(not city.minimap.is_empty(), "mini-map cached the mapped strokes")
	_expect((city.minimap.get("districts", []) as Array).size() > 0,
		"mini-map has district outlines")
	_expect((city.minimap.get("streets", []) as Array).size() > 0,
		"mini-map has inner streets")
	_expect(int(city.minimap.get("town_district", -1)) >= 0,
		"mini-map knows which district holds the town hall")
	_expect(city.minimap_view_metres(8.0) < city.minimap_view_metres(400.0),
		"higher altitude zooms the mini-map out")
	_expect(city.contains_world(city.places[0].direction * 8000.0),
		"a mapped place counts as inside the city")
	_expect(CityMinimap.name_visible(PatchCity.CityPlace.KIND_LANDMARK, 20.0, 80.0),
		"hall names appear on the local map")
	_expect(not CityMinimap.name_visible(PatchCity.CityPlace.KIND_LANDMARK, 20.0, 500.0),
		"hall names hide when the map is zoomed out")
	_expect(CityMinimap.name_visible(PatchCity.CityPlace.KIND_TOWN_CENTER, 20.0, 80.0),
		"the town center is named on the local map")
	_expect(not CityMinimap.name_visible(PatchCity.CityPlace.KIND_BUILDING, 20.0, 80.0),
		"ordinary buildings stay unnamed on the mini-map")
	_expect(CityMinimap.name_visible(PatchCity.CityPlace.KIND_DISTRICT, 120.0, 500.0),
		"district names remain on the wide map")
	_expect(not CityMinimap.name_visible(PatchCity.CityPlace.KIND_STREET, 40.0, 80.0),
		"street names stay off the mini-map")
	_expect(CityMinimap.district_overview(400.0),
		"high altitude uses the district overview")
	_expect(not CityMinimap.district_overview(80.0),
		"low altitude stays inside the district")
	var streets := city.get_node_or_null("FabricStreets") as MeshInstance3D
	_expect(streets != null and streets.mesh != null, "district streets were drawn")
	_expect_street_junctions(city)
	var buildings := city.get_node_or_null("FabricBuildings") as MeshInstance3D
	_expect(buildings != null and buildings.mesh != null, "district buildings were drawn")
	_expect(city.get_node_or_null("FabricStreetsBody") == null,
		"ghost streets have no collision")
	_expect(city.get_node_or_null("FabricBuildingsBody") == null,
		"ghost buildings have no collision")
	_expect_street_above_pad(city, shape)
	_expect_fabric_on_pad(city)
	_expect_buildings_rigid_on_slab(city, shape)
	_expect_districts_fill_lots(city)
	_expect_streets_clear_highway(city)
	_expect_varied_headings(city)
	_expect_packed_house_districts(city)
	_expect_medium_apartment_packs(city)
	_expect_district_landmarks(city, plan)
	_expect_town_center(city)
	_expect_mega_towers(city)
	_expect_buildings_clear_roads(city)
	_expect_buildings_not_overlapping(city)
	_expect_blunt_roofs(city)
	_expect_building_records(city)
	_expect_authored_designs(city)
	_expect(city.advance(shape), "fourth step builds the mapped city")
	_expect(city.phase == PatchCity.PHASE_BUILT, "city is built")
	_expect_built_city(city, shape)
	_expect(city.advance(shape), "fifth step paints the built city")
	_expect(city.phase == PatchCity.PHASE_PAINTED, "city is painted")
	_expect_painted_city(city)
	_expect_destructible_city(city)
	_expect_pavement_breaks(city)
	_expect(not city.advance(shape), "paint is the last city phase")
	print("patch_city_test:   mapped %s — %d places, road '%s'"
		% [plan.patch_name, city.places.size(), plan.road_name])
	print("patch_city_test:     streets %d  alleys %d  buildings %d  halls %d  town center %d"
		% [
			int(kinds.get(PatchCity.CityPlace.KIND_STREET, 0)),
			int(kinds.get(PatchCity.CityPlace.KIND_ALLEY, 0)),
			int(kinds.get(PatchCity.CityPlace.KIND_BUILDING, 0)),
			int(kinds.get(PatchCity.CityPlace.KIND_LANDMARK, 0)),
			int(kinds.get(PatchCity.CityPlace.KIND_TOWN_CENTER, 0)),
		])


func _expect_blunt_roofs(city: PatchCity) -> void:
	var peaked := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var variant := int(row.get("variant", -1))
		if variant != PatchCity.VARIANT_GABLE \
				and variant != PatchCity.VARIANT_POINT_HALF \
				and variant != PatchCity.VARIANT_SLANT_HALF:
			continue
		if not city._lot_on_slab(row):
			continue
		peaked += 1
		var span := minf(float(row.get("width", 8.0)), float(row.get("depth", 8.0)))
		var rise := float(row.get("stories", 2.0)) * 3.15
		var body := city._lot_wall_rise(row)
		var peak := city._peak_cap_height(row, rise - body)
		_expect(peak <= span * 0.55 + 0.05,
			"pointed roofs stay shorter than the plan (%.1f m roof on %.1f m span)"
			% [peak, span])
		_expect(peak <= rise * 0.30 + 0.05,
			"the roof is a cap, not half the tower (%.1f / %.1f)"
			% [peak, rise])
	if peaked > 0:
		print("patch_city_test:     blunt roofs on %d gable/point buildings" % peaked)


func _expect_building_records(city: PatchCity) -> void:
	var small_counts := {}
	var large_counts := {}
	var small_n := 0
	var large_n := 0
	var named := 0
	var small_ok := [
		PatchCity.VARIANT_RECT,
		PatchCity.VARIANT_CYLINDER,
		PatchCity.VARIANT_RECT_CAP,
		PatchCity.VARIANT_GABLE,
		PatchCity.VARIANT_ROUND_END,
	]
	var large_ok := [
		PatchCity.VARIANT_RECT,
		PatchCity.VARIANT_TAPER,
		PatchCity.VARIANT_POINT_HALF,
		PatchCity.VARIANT_SLANT_HALF,
		PatchCity.VARIANT_CYL_HALF,
	]
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var variant := int(row.get("variant", -1))
		var typology := int(row.get("typology", -1))
		_expect(variant >= PatchCity.VARIANT_RECT and variant <= PatchCity.VARIANT_CYL_HALF,
			"each mapped building picked a variant")
		if typology < 4:
			small_n += 1
			_expect(variant in small_ok, "small and medium buildings use house variants")
			small_counts[variant] = int(small_counts.get(variant, 0)) + 1
		else:
			large_n += 1
			_expect(variant in large_ok, "large and skyscraper buildings use tower variants")
			large_counts[variant] = int(large_counts.get(variant, 0)) + 1
		_expect(float(row.get("max_health", 0.0)) > 0.0, "mapped buildings have health")
		_expect(not String(row.get("name", "")).is_empty(), "mapped buildings are named")
		if not String(row.get("name", "")).is_empty():
			named += 1
	if small_n >= 5:
		for item in small_ok:
			_expect(int(small_counts.get(int(item), 0)) > 0,
				"city shows every small/medium building variant")
		var small_cyl := int(small_counts.get(PatchCity.VARIANT_CYLINDER, 0))
		_expect(small_cyl > 0, "some small buildings stay cylinders")
		_expect(small_cyl * 5 <= small_n,
			"cylinders stay less frequent among small buildings (%d / %d)"
			% [small_cyl, small_n])
	if large_n >= 5:
		for item in large_ok:
			_expect(int(large_counts.get(int(item), 0)) > 0,
				"city shows every large/skyscraper building variant")
	var recorded := 0
	for place in city.places:
		if place.kind != PatchCity.CityPlace.KIND_BUILDING \
				and place.kind != PatchCity.CityPlace.KIND_LANDMARK \
				and place.kind != PatchCity.CityPlace.KIND_TOWN_CENTER:
			continue
		recorded += 1
		_expect(place.max_health > 0.0, "gazetteer buildings store health")
		_expect(place.typology >= 0, "gazetteer buildings store a type")
		_expect(place.latitude != 0.0 or place.longitude != 0.0 \
				or place.direction.length_squared() > 0.5,
			"gazetteer buildings store a location")
		_expect(place.variant >= PatchCity.VARIANT_RECT \
				and place.variant <= PatchCity.VARIANT_CYL_HALF,
			"gazetteer buildings store a variant")
	_expect(recorded == named, "every mapped building is in the gazetteer")


func _expect_authored_designs(city: PatchCity) -> void:
	var designed := 0
	var variant_mass := 0
	var walkable := 0
	var specials: Dictionary = {}
	var mass_ids: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var design := String(row.get("design", ""))
		if design.is_empty():
			variant_mass += 1
			var variant := int(row.get("variant", -1))
			mass_ids[variant] = int(mass_ids.get(variant, 0)) + 1
			continue
		designed += 1
		if bool(row.get("walkable", false)) or BuildingCatalog.is_walkable(design):
			walkable += 1
			specials[design] = true
	_expect(designed > 0, "mapped lots pull authored designs")
	_expect(variant_mass > 0, "old variant masses still place beside authored hulls")
	if designed + variant_mass >= 40:
		_expect(walkable >= 3, "a mapped city keeps several walk-in specials")
		_expect(mass_ids.size() >= 3, "several old variant shapes still stand as themselves")
	print("patch_city_test:     authored designs %d  variant masses %d  walk-in specials %d (%s)"
		% [designed, variant_mass, walkable, ", ".join(specials.keys())])


func _expect_built_city(city: PatchCity, shape: PlanetShape) -> void:
	_expect_buildings_not_overlapping(city)
	var solid := city.get_node_or_null("CityBuildings") as MeshInstance3D
	_expect(solid != null and solid.mesh != null, "built buildings were drawn solid")
	_expect(city.get_node_or_null("CityBuildingsBody") != null,
		"solid buildings have collision")
	var ghosts := city.get_node_or_null("FabricBuildings") as MeshInstance3D
	_expect(ghosts == null or not ghosts.visible, "ghost buildings hide after build")
	var streets := city.get_node_or_null("FabricStreets") as MeshInstance3D
	_expect(streets == null or not streets.visible, "ghost streets hide after build")
	var paint := city.get_node_or_null("PavementPaint") as MeshInstance3D
	_expect(paint != null and paint.mesh != null, "pavement was painted")
	_expect(city.get_node_or_null("PavementPaintBody") != null,
		"painted ground and roads have collision")
	if paint != null and paint.mesh != null:
		var arrays := paint.mesh.surface_get_arrays(0)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var road := 0
		var walk := 0
		for colour in colors:
			if colour.r + colour.g + colour.b < 0.4:
				road += 1
			elif colour.r > 0.7 and colour.b > 0.6:
				walk += 1
		_expect(road > 0, "road pavement is black")
		_expect(walk > 0, "open pavement is light pink")
	var apron := city.get_node_or_null("CityApron") as MeshInstance3D
	_expect(apron != null and apron.mesh != null, "district edges slope down to terrain")
	_expect(city.get_node_or_null("CityApronBody") != null, "district aprons have collision")
	var ground := city.get_node_or_null("DistrictGround") as MeshInstance3D
	_expect(ground == null or not ground.visible, "slab hides under painted pavement")
	if apron != null and apron.mesh != null:
		var apron_arrays := apron.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = apron_arrays[Mesh.ARRAY_VERTEX]
		var buried := 0
		for point in verts:
			var span := point.length()
			if span < 1.0:
				continue
			var ground_h := shape.elevation(point / span, 0.0)
			if span - city._radius < ground_h + 0.8:
				buried += 1
		_expect(buried > 0, "district aprons reach the terrain")
	_expect_buildings_on_slab(city, shape)
	_expect_buildings_rigid_on_slab(city, shape)
	var lamps := city.get_node_or_null("CityLamps") as Node3D
	_expect(lamps != null, "street lamps were placed")
	_expect(city._lamp_spots.size() > 8, "lamps stand along the roads")
	var bulbs := lamps.get_node_or_null("Bulbs") as MultiMeshInstance3D if lamps != null else null
	_expect(bulbs != null and bulbs.multimesh != null, "lamps have lit bulbs")
	_expect(lamps.get_node_or_null("Arms") == null,
		"streetlights are a pole and bulb, not an arm over the road")
	_expect_street_above_pad(city, shape)


func _expect_painted_city(city: PatchCity) -> void:
	_expect(city.get_node_or_null("CityBuildingsBody") != null,
		"painted buildings keep collision")
	var solid := 0
	for item in city.destructible_buildings():
		var building := item as Node
		if building == null:
			continue
		var body := building.get_node_or_null("Body") as StaticBody3D
		if body == null or (body.collision_layer & 1) == 0:
			continue
		if body.get_child_count() == 0:
			continue
		var collider := body.get_child(0) as CollisionShape3D
		if collider != null and collider.shape != null:
			solid += 1
	_expect(solid > 0 and solid == city.destructible_buildings().size(),
		"every painted lot has a solid collider (%d / %d)"
		% [solid, city.destructible_buildings().size()])
	var combined := city.get_node_or_null("CityBuildingsBody") as StaticBody3D
	_expect(combined == null or combined.collision_layer == 0,
		"batched hull collision yields to per-lot bodies")
	var hull := city.get_node_or_null("CityBuildings") as MeshInstance3D
	_expect(hull == null or not hull.visible, "unpainted hull hides after paint")
	var small := city.get_node_or_null("CityPaintSmall") as MeshInstance3D
	var large := city.get_node_or_null("CityPaintLarge") as MeshInstance3D
	_expect(small != null and small.mesh != null, "small buildings were painted")
	_expect(large != null and large.mesh != null, "large buildings were painted")
	var small_mat := small.material_override as ShaderMaterial if small != null else null
	var large_mat := large.material_override as ShaderMaterial if large != null else null
	_expect(small_mat != null, "small buildings use the wall shader")
	_expect(large_mat != null, "large buildings use the wall shader")
	if small_mat != null:
		_expect(float(small_mat.get_shader_parameter(&"roughness_val")) > 0.6,
			"small buildings stay rough")
		_expect(float(small_mat.get_shader_parameter(&"metallic_val")) < 0.2,
			"small buildings stay dull")
	if large_mat != null:
		_expect(float(large_mat.get_shader_parameter(&"roughness_val")) > 0.2,
			"large building fallback is not chrome-smooth")
		_expect(float(large_mat.get_shader_parameter(&"metallic_val")) < 0.2,
			"large buildings catch daylight instead of going black metal")
		var lum_min := 1.0
		var lum_max := 0.0
		for item in city.destructible_buildings():
			var building := item as Node
			if building == null or not building.has_method(&"is_large") \
					or not bool(building.call(&"is_large")):
				continue
			var mesh: Mesh = building.call(&"hull_mesh")
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			var arrays: Array = mesh.surface_get_arrays(0)
			var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var step := maxi(int(cols.size() / 40), 1)
			var index := 0
			while index < cols.size():
				var tint: Color = cols[index]
				var lum := tint.r * 0.22 + tint.g * 0.67 + tint.b * 0.11
				lum_min = minf(lum_min, lum)
				lum_max = maxf(lum_max, lum)
				index += step
		_expect(lum_max - lum_min > 0.18,
			"painted towers are not one colour (%.2f .. %.2f)" % [lum_min, lum_max])
	var win_s := city.get_node_or_null("CityWindowsSmall") as MeshInstance3D
	var win_l := city.get_node_or_null("CityWindowsLarge") as MeshInstance3D
	_expect(win_s != null and win_s.mesh != null, "small buildings have windows")
	_expect(win_l != null and win_l.mesh != null, "large buildings have windows")
	var glow_s := win_s.material_override as ShaderMaterial if win_s != null else null
	var glow_l := win_l.material_override as ShaderMaterial if win_l != null else null
	_expect(glow_s != null and glow_s.shader == PatchCity.WINDOW_SHADER,
		"small windows use the night-glow shader")
	_expect(glow_l != null and glow_l.shader == PatchCity.WINDOW_SHADER,
		"large windows use the night-glow shader")
	if glow_s != null and glow_l != null:
		var warm := _as_color(glow_s.get_shader_parameter(&"fallback_glow"))
		var cool := _as_color(glow_l.get_shader_parameter(&"fallback_glow"))
		var cool_sat := maxf(cool.r, maxf(cool.g, cool.b)) - minf(cool.r, minf(cool.g, cool.b))
		var warm_sat := maxf(warm.r, maxf(warm.g, warm.b)) - minf(warm.r, minf(warm.g, warm.b))
		_expect(cool_sat > warm_sat,
			"large windows fall back to neon, not white office light")
	var white_panes := 0
	var neon_panes := 0
	var neon_trim_faces := 0
	for item in city.destructible_buildings():
		var building := item as Node
		if building == null or not building.has_method(&"is_large") \
				or not bool(building.call(&"is_large")):
			continue
		var glass: Mesh = building.call(&"glass_mesh")
		if glass != null and glass.get_surface_count() > 0:
			var panes: PackedColorArray = glass.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var pane_step := maxi(int(panes.size() / 30), 1)
			var pane_index := 0
			while pane_index < panes.size():
				var pane: Color = panes[pane_index]
				var sat := maxf(pane.r, maxf(pane.g, pane.b)) - minf(pane.r, minf(pane.g, pane.b))
				var pane_lum := pane.r * 0.22 + pane.g * 0.67 + pane.b * 0.11
				if sat > 0.28:
					neon_panes += 1
				elif pane_lum > 0.75:
					white_panes += 1
				pane_index += pane_step
		var shell: Mesh = building.call(&"hull_mesh")
		if shell != null and shell.get_surface_count() > 0:
			var cols: PackedColorArray = shell.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var hull_step := maxi(int(cols.size() / 40), 1)
			var hull_index := 0
			while hull_index < cols.size():
				var trim: Color = cols[hull_index]
				if absi(int(round(trim.a * 20.0)) - PatchCity.PAINT_NEON) == 0:
					neon_trim_faces += 1
				hull_index += hull_step
	_expect(white_panes * 2 < neon_panes,
		"skyscraper windows are coloured, not white (%d white / %d neon)" % [
			white_panes, neon_panes])
	_expect(neon_panes > 0, "skyscraper windows light neon colours")
	_expect(neon_trim_faces > 0, "skyscrapers carry neon trim bands")
	var warm_house := 0
	var house_seen := 0
	for item in city.destructible_buildings():
		var house := item as Node
		if house == null or not house.has_method(&"is_large") \
				or bool(house.call(&"is_large")):
			continue
		var panes: Mesh = house.call(&"glass_mesh") if house.has_method(&"glass_mesh") else null
		if panes == null or panes.get_surface_count() == 0:
			continue
		var cols: PackedColorArray = panes.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var step := maxi(int(cols.size() / 24), 1)
		var index := 0
		while index < cols.size():
			var pane: Color = cols[index]
			if pane.r - pane.b > 0.22 and pane.r > 0.55:
				warm_house += 1
				house_seen += 1
				break
			index += step
		if house_seen >= 8:
			break
	_expect(warm_house > 0, "houses glow warm interior light")
	var cyl_half := 0
	var cyl_rings := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if int(row.get("variant", -1)) != PatchCity.VARIANT_CYL_HALF:
			continue
		if not city._lot_on_slab(row):
			continue
		cyl_half += 1
		var rings: Array = city._lot_facade_rings(row)
		var upper := 0
		for ring in rings:
			var piece: Dictionary = ring
			if float(piece.get("lift", 0.0)) > 1.0 and not bool(piece.get("door", true)):
				upper += 1
		if upper > 0:
			cyl_rings += 1
		var rise := float(row.get("stories", 0.0)) * 3.15
		_expect(absf(city._lot_wall_rise(row) - rise * 0.52) < 0.08,
			"cylinder-on-rect glass stops where the rect hull stops")
	_expect(cyl_half == 0 or cyl_rings == cyl_half,
		"rect-base cylinder towers paint windows on the drum (%d / %d)"
		% [cyl_rings, cyl_half])
	var mixed := 0
	var mixed_ok := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var variant := int(row.get("variant", -1))
		if variant != PatchCity.VARIANT_CYL_HALF and variant != PatchCity.VARIANT_RECT_CAP:
			continue
		if not city._lot_on_slab(row):
			continue
		mixed += 1
		var body := 0
		var drum := 0
		for ring in city._lot_facade_rings(row):
			var piece: Dictionary = ring
			if bool(piece.get("round", false)):
				drum += 1
			elif float(piece.get("lift", 0.0)) < 0.2:
				body += 1
		if body > 0 and drum > 0:
			mixed_ok += 1
	_expect(mixed == 0 or mixed_ok == mixed,
		"rect-plus-cylinder buildings glaze each mass (%d / %d)" % [mixed_ok, mixed])
	var taper_n := 0
	var taper_setbacks := 0
	var tall_n := 0
	var tall_ok := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if not city._lot_on_slab(row):
			continue
		var variant := int(row.get("variant", -1))
		if variant == PatchCity.VARIANT_TAPER:
			taper_n += 1
			var max_lift := 0.0
			for ring in city._lot_facade_rings(row):
				var piece: Dictionary = ring
				max_lift = maxf(max_lift, float(piece.get("lift", 0.0)))
			if max_lift > 3.0:
				taper_setbacks += 1
		if int(row.get("typology", 0)) < 4 or float(row.get("stories", 0.0)) < 16.0:
			continue
		if variant == PatchCity.VARIANT_POINT_HALF or variant == PatchCity.VARIANT_SLANT_HALF:
			continue
		tall_n += 1
		var bands := 0
		for ring in city._lot_facade_rings(row):
			var piece: Dictionary = ring
			bands += city._facade_story_count(float(piece.get("height", 0.0)), 2.15)
		if bands >= 14:
			tall_ok += 1
	_expect(taper_n == 0 or taper_setbacks == taper_n,
		"taper towers glaze each setback (%d / %d)" % [taper_setbacks, taper_n])
	_expect(tall_n == 0 or tall_ok == tall_n,
		"skyscrapers keep a window row per storey (%d / %d)" % [tall_ok, tall_n])
	var styled := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if int(row.get("paint_style", -1)) >= 0:
			styled += 1
	_expect(styled > 20, "buildings received paint styles")
	var variant_painted := 0
	var variant_styled := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if not String(row.get("design", "")).is_empty():
			continue
		if not String(row.get("special", "")).is_empty():
			continue
		variant_painted += 1
		if CityBuildingCatalog.VARIANT_PAINT_STYLES.has(String(row.get("paint_name", ""))):
			variant_styled += 1
	_expect(variant_painted == 0 or variant_styled == variant_painted,
		"old variant masses picked one of five colour paints (%d / %d)"
		% [variant_styled, variant_painted])
	_expect_sky_paint(city)
	var paint := city.get_node_or_null("PavementPaint") as MeshInstance3D
	_expect(paint != null and paint.mesh != null, "walks were repainted")
	var ground_mat := paint.material_override as ShaderMaterial if paint != null else null
	_expect(ground_mat != null, "pavement uses the ground map shader")
	if ground_mat != null:
		_expect(ground_mat.get_shader_parameter(&"ground_map") != null,
			"pavement samples a mapped png")
		_expect(float(ground_mat.get_shader_parameter(&"has_lamps")) > 0.5,
			"painted pavement samples streetlight pools")
		_expect(ground_mat.get_shader_parameter(&"lamp_map") != null,
			"streetlight pools are a baked map")
	_expect(city._ground_image != null, "district ground was baked to a png")
	if city._ground_image != null:
		_expect(city._ground_image.get_width() >= PatchCity.GROUND_TEX_MIN,
			"ground map is high resolution")
	if paint != null and paint.mesh != null:
		var arrays := paint.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		_expect(uvs.size() > 100, "pavement tops carry ground-map uvs")
	var road := 0
	var checked_road := 0
	for item in city._road_index:
		if checked_road >= 18:
			break
		var row: Dictionary = item
		var mid: Vector2 = ((row["a"] as Vector2) + (row["b"] as Vector2)) * 0.5
		var key := Vector2i(
			roundi(mid.x / city._pad_cell), roundi(mid.y / city._pad_cell))
		if not city._pad_tops.has(key):
			continue
		checked_road += 1
		var colour := city._ground_map_color(mid)
		if colour.r + colour.g + colour.b < 0.35:
			road += 1
	_expect(checked_road >= 8 and road >= checked_road - 3,
		"roads stay dark on the ground map (%d / %d)" % [road, checked_road])
	var open := 0
	var shaded := 0
	var shade_n := 0
	for lot in city.fabric.get("lots", []):
		if shade_n >= 10:
			break
		var row: Dictionary = lot
		if not city._lot_on_slab(row):
			continue
		var centre: Vector2 = row.get("centre", Vector2.ZERO)
		var along: Vector2 = row.get("along", Vector2.RIGHT)
		if along.length_squared() < 0.0001:
			along = Vector2.RIGHT
		along = along.normalized()
		var half_w := float(row.get("width", 8.0)) * 0.5
		var half_d := float(row.get("depth", 8.0)) * 0.5
		var far_uv: Vector2 = centre + along * (half_w + half_d + 12.0)
		var near_key := Vector2i(
			roundi(centre.x / city._pad_cell), roundi(centre.y / city._pad_cell))
		var far_key := Vector2i(
			roundi(far_uv.x / city._pad_cell), roundi(far_uv.y / city._pad_cell))
		if not city._pad_tops.has(near_key) or not city._pad_tops.has(far_key):
			continue
		if city._road_signed(centre) < 1.2 or city._road_signed(far_uv) < 2.4:
			continue
		shade_n += 1
		var near_c := city._ground_map_color(centre)
		var far_c := city._ground_map_color(far_uv)
		var near_l := near_c.r + near_c.g + near_c.b
		var far_l := far_c.r + far_c.g + far_c.b
		if far_l > 0.28:
			open += 1
		if near_l + 0.05 < far_l:
			shaded += 1
	_expect(open >= 4, "open pavement keeps district colour")
	_expect(shaded >= 4, "ground darkens beside buildings (%d / %d)"
		% [shaded, shade_n])
	var apron := city.get_node_or_null("CityApron") as MeshInstance3D
	_expect(apron != null and apron.mesh != null, "painted city keeps sloped district edges")
	print("patch_city_test:     painted ground and facades")


func _expect_buildings_on_slab(city: PatchCity, shape: PlanetShape) -> void:
	var under := 0
	var checked := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if not city._lot_on_slab(row):
			continue
		checked += 1
		var direction := city._from_uv(row["centre"]).normalized()
		var pad := city._pad_top_at(direction)
		var mark := city._deck_mark(shape, direction, PatchCity.STREET_LIFT)
		var height := mark.length() - city._radius
		if is_nan(pad) or height + 0.05 < pad:
			under += 1
	_expect(checked > 0, "built lots were seated on pavement")
	_expect(under == 0, "buildings stay on the slab, not under it (%d under)" % under)


func _expect_buildings_rigid_on_slab(city: PatchCity, shape: PlanetShape) -> void:
	var sheared := 0
	var checked := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if not city._lot_on_slab(row):
			continue
		var home := city._lot_slab_h(row)
		if is_nan(home):
			continue
		var want := home + PatchCity.STREET_LIFT
		var spots: Array = [row.get("centre", Vector2.ZERO)]
		for piece in row.get("footprints", []):
			var poly: PackedVector2Array = piece
			for point in poly:
				spots.append(point)
		for uv in spots:
			checked += 1
			var mark := city._lot_deck_mark(shape, row, uv)
			if absf(mark.length() - city._radius - want) > 0.08:
				sheared += 1
	_expect(checked > 0, "lot corners were seated on one slab height")
	_expect(sheared == 0, "buildings stay level on their lot slab (%d sheared)" % sheared)

	var sample: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if city._lot_on_slab(row):
			sample = row.duplicate(true)
			break
	if sample.is_empty():
		return
	sample.erase("pad_h")
	var cell := city._pad_cell
	var centre: Vector2 = sample.get("centre", Vector2.ZERO)
	var home_key := Vector2i(roundi(centre.x / cell), roundi(centre.y / cell))
	var neighbour := Vector2i(home_key.x + 1, home_key.y)
	var had := city._pad_tops.has(neighbour)
	var old := float(city._pad_tops[neighbour]) if had else 0.0
	var home := city._lot_slab_h(sample)
	city._pad_tops[neighbour] = home + 18.0
	var corner := Vector2(float(neighbour.x) * cell, float(neighbour.y) * cell)
	var footprints: Array = [PackedVector2Array([centre, corner])]
	sample["footprints"] = footprints
	sample.erase("pad_h")
	var locked := city._lot_deck_mark(shape, sample, corner)
	var unlocked := city._deck_mark(shape, city._from_uv(corner), PatchCity.STREET_LIFT)
	var still_home := absf(locked.length() - city._radius - home - PatchCity.STREET_LIFT) < 0.08
	var jumped := unlocked.length() - city._radius > home + PatchCity.STREET_LIFT + 8.0
	_expect(still_home, "a higher neighbour terrace does not lift the hull")
	_expect(jumped, "the old per-corner mark would have climbed the terrace")
	_expect(not city._lot_on_slab(sample), "lots that sit under a higher slab are skipped")
	if had:
		city._pad_tops[neighbour] = old
	else:
		city._pad_tops.erase(neighbour)


func _expect_district_landmarks(city: PatchCity, plan: PatchCityGenerator.Plan) -> void:
	var halls: Dictionary = {}
	var used: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		used[int(row["district_id"])] = true
		if not bool(row.get("landmark", false)):
			continue
		var district_id: int = int(row["district_id"])
		_expect(not halls.has(district_id), "one unique building per district")
		halls[district_id] = row
		_expect(float(row["width"]) >= 8.0, "district special has a footprint")
		_expect(float(row["stories"]) >= 1.0, "district special has height")
		_expect(bool(row.get("walkable", false)),
			"the district special is an enterable building")
		_expect(BuildingCatalog.SPECIALS.has(String(row.get("design", ""))),
			"the district special is a walk-in (%s)" % String(row.get("design", "")))
		_expect(not String(row["name"]).ends_with("Hall"),
			"unique building uses the special's name")
	_expect(halls.size() == used.size(),
		"every built district has a unique building (%d halls, %d districts)"
		% [halls.size(), used.size()])
	var kinds: Dictionary = {}
	for district_id in halls:
		kinds[String((halls[district_id] as Dictionary).get("design", ""))] = true
	if halls.size() >= 4:
		_expect(kinds.size() >= mini(halls.size(), 4),
			"district specials mix the walk-in buildings (%d kinds)" % kinds.size())
	print("patch_city_test:     district specials %s" % ", ".join(kinds.keys()))
	var small_w := 1.0e9
	var large_w := 0.0
	var small_span := 1.0e9
	var large_span := 0.0
	for district in plan.districts:
		if not halls.has(district.id):
			continue
		var width := float((halls[district.id] as Dictionary)["width"])
		if district.span < small_span:
			small_span = district.span
			small_w = width
		if district.span > large_span:
			large_span = district.span
			large_w = width
	if large_span > small_span * 1.8:
		_expect(large_w >= small_w,
			"larger districts get a larger unique building (%.0f vs %.0f)"
			% [large_w, small_w])


func _expect_town_center(city: PatchCity) -> void:
	var centre: Dictionary = {}
	var halls: Dictionary = {}
	var areas: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var district_id: int = int(row["district_id"])
		if bool(row.get("town_center", false)):
			_expect(centre.is_empty(), "only one town center")
			centre = row
		if bool(row.get("landmark", false)):
			halls[district_id] = row
	_expect(not centre.is_empty(), "the city has a town center")
	if centre.is_empty():
		return
	_expect(String(centre["name"]).contains("Town Center"),
		"town center is named as a town center")
	_expect(float(centre["width"]) >= 28.0, "town center is a large footprint")
	_expect(float(centre["stories"]) >= 8.0, "town center is tall")
	var biggest_hall := -1
	var biggest_hall_w := -1.0
	for district_id in halls:
		var width := float((halls[district_id] as Dictionary)["width"])
		if width > biggest_hall_w:
			biggest_hall_w = width
			biggest_hall = int(district_id)
	_expect(int(centre["district_id"]) == biggest_hall,
		"town center is in the largest district")
	if halls.has(int(centre["district_id"])):
		_expect(float(centre["width"]) > float((halls[int(centre["district_id"])] as Dictionary)["width"]),
			"town center is bigger than the district hall")


func _expect_mega_towers(city: PatchCity) -> void:
	var halls: Dictionary = {}
	var megas: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var district_id: int = int(row["district_id"])
		if bool(row.get("landmark", false)):
			halls[district_id] = row
		if bool(row.get("mega", false)):
			var list: Array = megas.get(district_id, [])
			list.append(row)
			megas[district_id] = list
	_expect(megas.size() >= 1 and megas.size() <= 2,
		"at most two districts have mega towers (%d)" % megas.size())
	var biggest := -1
	var biggest_w := -1.0
	for district_id in halls:
		var width := float((halls[district_id] as Dictionary)["width"])
		if width > biggest_w:
			biggest_w = width
			biggest = int(district_id)
	_expect(megas.has(biggest), "the largest district has the main skyline")
	for district_id in megas:
		var cluster: Array = megas[district_id]
		_expect(cluster.size() >= 3 and cluster.size() <= 5,
			"mega towers come in a cluster of 3 to 5 (%d in district %s)"
			% [cluster.size(), district_id])
		var acc := Vector2.ZERO
		for lot in cluster:
			acc += Vector2((lot as Dictionary)["centre"])
		var mid := acc / float(cluster.size())
		var farthest := 0.0
		for lot in cluster:
			farthest = maxf(farthest, Vector2((lot as Dictionary)["centre"]).distance_to(mid))
			var mega_w := float((lot as Dictionary).get("width", 1.0))
			var mega_d := float((lot as Dictionary).get("depth", 1.0))
			_expect(maxf(mega_w, mega_d) / maxf(minf(mega_w, mega_d), 0.1) <= 1.2,
				"mega towers keep an even footprint (%.1f x %.1f)" % [mega_w, mega_d])
		_expect(farthest <= 110.0,
			"mega towers sit close together (%.0f m from cluster centre)" % farthest)
	if halls.has(biggest) and megas.has(biggest):
		var downtown: Array = megas[biggest]
		var hall_h := float((halls[biggest] as Dictionary)["stories"])
		var tower_h := float((downtown[0] as Dictionary)["stories"])
		_expect(tower_h >= hall_h * 5.4,
			"mega towers are about 6x the district hall (%.0f vs hall %.0f)"
			% [tower_h, hall_h])
	_expect_skyline_shoulders(city, megas)
	var extra := 0
	for district_id in megas:
		if int(district_id) == biggest:
			continue
		extra += (megas[district_id] as Array).size()
	print("patch_city_test:     mega towers %d districts, downtown %d, elsewhere %d"
		% [megas.size(), (megas.get(biggest, []) as Array).size(), extra])


func _expect_skyline_shoulders(city: PatchCity, megas: Dictionary) -> void:
	var cores: Array = []
	for district_id in megas:
		for lot in megas[district_id]:
			var mega: Dictionary = lot
			cores.append({
				"at": mega["centre"],
				"h": float(mega["stories"]),
			})
	var checked := 0
	var short := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if bool(row.get("mega", false)):
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		var at: Vector2 = row["centre"]
		var nearest := 1.0e12
		var peak := 0.0
		for core in cores:
			var info: Dictionary = core
			var away: float = at.distance_to(info["at"])
			if away < nearest:
				nearest = away
				peak = float(info["h"])
		if nearest > 40.0 or peak < 8.0:
			continue
		checked += 1
		if float(row["stories"]) < peak * 0.45:
			short += 1
	_expect(checked > 0, "buildings stand beside the mega cluster")
	_expect(short == 0,
		"no small building sits next to a mega tower (%d of %d)" % [short, checked])
	_expect_skyline_outskirts(city, cores)


func _expect_skyline_outskirts(city: PatchCity, cores: Array) -> void:
	var rim := 0
	var midrise := 0
	var cover := 0.0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if bool(row.get("mega", false)) or bool(row.get("landmark", false)) \
				or bool(row.get("town_center", false)):
			continue
		var at: Vector2 = row["centre"]
		var nearest := 1.0e12
		for core in cores:
			nearest = minf(nearest, at.distance_to((core as Dictionary)["at"]))
		if nearest < 46.0 or nearest > 150.0:
			continue
		rim += 1
		cover += float(row.get("coverage", 0.0))
		var typology := int(row.get("typology", 0))
		if typology >= PatchCity.TYPE_APARTMENT and typology <= PatchCity.TYPE_TOWER:
			midrise += 1
	_expect(rim >= 8, "skyscraper outskirts have a building ring (%d)" % rim)
	if rim > 0:
		_expect(midrise * 2 >= rim,
			"outskirts are mostly apartments, shops and mid-rises (%d / %d)"
			% [midrise, rim])
		_expect(cover / float(rim) >= 0.58,
			"outskirt lots fill their blocks (%.2f)" % (cover / float(rim)))


func _expect_street_junctions(city: PatchCity) -> void:
	var junctions: Array = city.fabric.get("junctions", [])
	_expect(junctions.size() > 0, "inner streets record intersections")
	var streets: Array = city.fabric.get("streets", [])
	var lonely := 0
	for junction in junctions:
		var at: Vector2 = (junction as Dictionary)["at"]
		var arms := 0
		for street in streets:
			var path: PackedVector2Array = (street as Dictionary)["uv"]
			var on := false
			for point in path:
				if point.distance_to(at) <= 1.8:
					on = true
					break
			if on:
				arms += 1
		if arms < 2:
			lonely += 1
	_expect(lonely == 0, "every intersection joins at least two streets (%d)" % lonely)
	print("patch_city_test:     inner street junctions %d" % junctions.size())


func _expect_buildings_clear_roads(city: PatchCity) -> void:
	var streets: Array = city.fabric.get("streets", [])
	var arteries: Dictionary = city.fabric.get("arteries", {})
	var paths: Array = []
	for street in streets:
		var info: Dictionary = street
		paths.append({
			"uv": info["uv"],
			"half": float(info["half"]),
			"mid": info["mid"],
			"reach": 90.0,
			"label": "inner streets",
		})
	var highway: PackedVector2Array = arteries.get("highway", PackedVector2Array())
	if highway.size() >= 2:
		paths.append({
			"uv": highway,
			"half": float(arteries.get("highway_half", 8.0)),
			"mid": _poly_mid(highway),
			"reach": 10000.0,
			"label": "city road",
		})
	var spur: PackedVector2Array = arteries.get("spur", PackedVector2Array())
	if spur.size() >= 2:
		paths.append({
			"uv": spur,
			"half": float(arteries.get("spur_half", 6.0)),
			"mid": _poly_mid(spur),
			"reach": 10000.0,
			"label": "city road spur",
		})
	for path in arteries.get("exits", []):
		var exit_uv: PackedVector2Array = path
		if exit_uv.size() < 2:
			continue
		paths.append({
			"uv": exit_uv,
			"half": float(arteries.get("exit_half", 6.2)),
			"mid": _poly_mid(exit_uv),
			"reach": 400.0,
			"label": "exit roads",
		})
	var hits: Dictionary = {}
	var checked := 0
	var thin := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var footprints: Array = row.get("footprints", [])
		if footprints.is_empty():
			continue
		for piece in footprints:
			var poly: PackedVector2Array = piece
			if poly.size() < 3:
				continue
			if city._poly_inradius(poly) < 1.55:
				thin += 1
				continue
			var mid := _poly_mid(poly)
			checked += 1
			for path in paths:
				var info: Dictionary = path
				if mid.distance_to(info["mid"]) > float(info["reach"]):
					continue
				if _point_to_path(mid, info["uv"]) + 0.35 < float(info["half"]):
					var label := String(info["label"])
					hits[label] = int(hits.get(label, 0)) + 1
					break
	_expect(checked > 0, "clipped footprints were stored")
	_expect(thin == 0, "building footprints are not paper-thin slices (%d)" % thin)
	_expect(hits.is_empty(), "building footprints stay off roads (%s)"
		% ", ".join(_hit_labels(hits)))
	var hull_hits: Dictionary = {}
	var hull_n := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if float(row.get("width", 0.0)) < 2.4 or float(row.get("depth", 0.0)) < 2.4:
			continue
		var centre: Vector2 = row.get("centre", Vector2.ZERO)
		var along: Vector2 = row.get("along", Vector2.RIGHT)
		if along.length_squared() < 0.0001:
			along = Vector2.RIGHT
		along = along.normalized()
		var across: Vector2 = row.get("across", Vector2(-along.y, along.x))
		if across.length_squared() < 0.0001:
			across = Vector2(-along.y, along.x)
		across = across.normalized()
		var hw := float(row["width"]) * 0.5
		var hd := float(row["depth"]) * 0.5
		var corners := [
			centre + along * hw + across * hd,
			centre + along * hw - across * hd,
			centre - along * hw + across * hd,
			centre - along * hw - across * hd,
		]
		hull_n += 1
		for path in paths:
			var info: Dictionary = path
			if centre.distance_to(info["mid"]) > float(info["reach"]):
				continue
			var over := false
			for corner in corners:
				if _point_to_path(corner, info["uv"]) + 0.2 < float(info["half"]):
					over = true
					break
			if over:
				hull_hits[String(info["label"])] = int(hull_hits.get(String(info["label"]), 0)) + 1
				break
	_expect(hull_n > 0, "building hulls were measured against roads")
	_expect(hull_hits.is_empty(), "authored and lot hulls stay off roads (%s)"
		% ", ".join(_hit_labels(hull_hits)))


func _expect_buildings_not_overlapping(city: PatchCity) -> void:
	var lots: Array = city.fabric.get("lots", [])
	var overlaps := 0
	var n := lots.size()
	var polys: Array = []
	var boxes: Array = []
	polys.resize(n)
	boxes.resize(n)
	var bins: Dictionary = {}
	var cell := 32.0
	for index in n:
		var row: Dictionary = lots[index]
		var pieces: Array = city._lot_mesh_polys(row)
		polys[index] = pieces
		var box: Rect2 = city._pieces_aabb(pieces)
		boxes[index] = box
		if pieces.is_empty():
			continue
		var x0 := int(floor(box.position.x / cell))
		var y0 := int(floor(box.position.y / cell))
		var x1 := int(floor(box.end.x / cell))
		var y1 := int(floor(box.end.y / cell))
		for ox in range(x0, x1 + 1):
			for oy in range(y0, y1 + 1):
				var key := Vector2i(ox, oy)
				var bucket: Array = bins.get(key, [])
				bucket.append(index)
				bins[key] = bucket
	for index in n:
		if (polys[index] as Array).is_empty():
			continue
		var box: Rect2 = boxes[index]
		var seen: Dictionary = {}
		var x0 := int(floor(box.position.x / cell))
		var y0 := int(floor(box.position.y / cell))
		var x1 := int(floor(box.end.x / cell))
		var y1 := int(floor(box.end.y / cell))
		for ox in range(x0, x1 + 1):
			for oy in range(y0, y1 + 1):
				var bucket: Array = bins.get(Vector2i(ox, oy), [])
				for other_i in bucket:
					var other: int = int(other_i)
					if other <= index or seen.has(other):
						continue
					seen[other] = true
					var other_box: Rect2 = boxes[other]
					if not box.intersects(other_box):
						continue
					if city._pieces_overlap(polys[index], polys[other], 4.0):
						overlaps += 1
	_expect(overlaps == 0, "building meshes do not overlap (%d pairs)" % overlaps)
	print("patch_city_test:     overlapping buildings %d" % overlaps)


func _poly_mid(poly: PackedVector2Array) -> Vector2:
	var mid := Vector2.ZERO
	if poly.is_empty():
		return mid
	for point in poly:
		mid += point
	return mid / float(poly.size())


func _hit_labels(hits: Dictionary) -> PackedStringArray:
	var labels := PackedStringArray()
	for label in hits:
		labels.append("%s %d" % [String(label), int(hits[label])])
	return labels


func _point_to_path(at: Vector2, path: PackedVector2Array) -> float:
	var nearest := 1.0e12
	if path.size() <= 1:
		return at.distance_to(path[0]) if path.size() == 1 else nearest
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var ab := b - a
		var run := ab.length_squared()
		var t := 0.0
		if run >= 0.0001:
			t = clampf((at - a).dot(ab) / run, 0.0, 1.0)
		nearest = minf(nearest, at.distance_to(a.lerp(b, t)))
	return nearest


func _expect_street_above_pad(city: PatchCity, shape: PlanetShape) -> void:
	var streets: Array = city.fabric.get("streets", [])
	if streets.is_empty():
		return
	var checked := 0
	var high := 0
	for street in streets:
		var mid: Vector2 = (street as Dictionary)["mid"]
		var direction := city._from_uv(mid).normalized()
		var pad := city._pad_top_at(direction)
		if is_nan(pad):
			continue
		var mark := city._deck_mark(shape, direction, PatchCity.STREET_LIFT)
		var height := mark.length() - city._radius
		checked += 1
		_expect(height + 0.01 >= pad, "fabric streets sit above the pad")
		if height > pad + PatchCity.STREET_LIFT + 0.4:
			high += 1
	_expect(checked > 0, "street mids sat on a pad")
	_expect(high == 0, "inner streets stay on the pad, not the hillside (%d floated)" % high)


func _expect_fabric_on_pad(city: PatchCity) -> void:
	var cell := city._pad_cell
	if cell <= 0.1 or city._pad_tops.is_empty():
		_fail("mapped fabric needs paved pad cells")
		return
	var street_miss := 0
	var street_n := 0
	for street in city.fabric.get("streets", []):
		var path: PackedVector2Array = (street as Dictionary)["uv"]
		if path.size() < 2:
			continue
		for index in path.size():
			street_n += 1
			var uv: Vector2 = path[index]
			var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
			if not city._pad_tops.has(key):
				street_miss += 1
	_expect(street_n > 0, "mapped streets have UV samples")
	_expect(street_miss * 20 <= street_n,
		"streets stay on paved cells (%d / %d off the pad)" % [street_miss, street_n])
	var lot_miss := 0
	var lot_n := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		lot_n += 1
		var centre: Vector2 = row["centre"]
		var key := Vector2i(roundi(centre.x / cell), roundi(centre.y / cell))
		if not city._pad_tops.has(key):
			lot_miss += 1
	_expect(lot_n > 0, "mapped lots have centres")
	_expect(lot_miss == 0, "buildings stay on paved cells (%d off the pad)" % lot_miss)


func _expect_districts_fill_lots(city: PatchCity) -> void:
	var cell := city._pad_cell
	if cell <= 0.1 or city._pad_tops.is_empty():
		_fail("district fill needs paved pad cells")
		return
	var blocked: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var pieces: Array = row.get("footprints", [])
		if pieces.is_empty():
			pieces = [city._lot_rect_uv(row)]
		for piece in pieces:
			_stamp_poly_cells(blocked, piece, cell, 1.8)
	var arteries: Dictionary = city.fabric.get("arteries", {})
	_stamp_path_cells(
		blocked, arteries.get("highway", PackedVector2Array()),
		float(arteries.get("highway_half", 8.0)), cell, true)
	_stamp_path_cells(
		blocked, arteries.get("spur", PackedVector2Array()),
		float(arteries.get("spur_half", 6.0)), cell, false)
	for path in arteries.get("exits", []):
		_stamp_path_cells(blocked, path, float(arteries.get("exit_half", 6.2)), cell, false)
	for street in city.fabric.get("streets", []):
		var info: Dictionary = street
		_stamp_path_cells(blocked, info["uv"], float(info["half"]), cell, false)
	var empty: Dictionary = {}
	for key in city._pad_tops:
		var at: Vector2i = key
		if blocked.has(at):
			continue
		if not city._pad_owner.has(at):
			continue
		if not _pad_interior_cell(city, at):
			continue
		empty[at] = true
	var worst := 0.0
	var worst_span := 0.0
	for blob in _cell_blobs(empty):
		var area := float(blob.size()) * cell * cell
		var box := _cell_blob_bounds(blob, cell)
		var span := minf(box.z - box.x, box.w - box.y)
		if span < 20.0:
			continue
		if area > worst:
			worst = area
			worst_span = span
	_expect(worst < 1000.0,
		"paved district leftover is too big for empty yards (%.0f m², span %.0f m)"
		% [worst, worst_span])


func _stamp_poly_cells(
		blocked: Dictionary,
		poly: PackedVector2Array,
		cell: float,
		margin: float
	) -> void:
	if poly.size() < 3:
		return
	var box := Rect2(poly[0], Vector2.ZERO)
	for point in poly:
		box = box.expand(point)
	box = box.grow(margin + cell * 0.5)
	var x0 := int(floor(box.position.x / cell))
	var y0 := int(floor(box.position.y / cell))
	var x1 := int(ceil(box.end.x / cell))
	var y1 := int(ceil(box.end.y / cell))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var key := Vector2i(x, y)
			if blocked.has(key):
				continue
			var uv := Vector2(float(x) * cell, float(y) * cell)
			if _point_to_poly(uv, poly) <= margin:
				blocked[key] = true


func _stamp_path_cells(
		blocked: Dictionary,
		path: PackedVector2Array,
		half: float,
		cell: float,
		closed: bool
	) -> void:
	if path.size() < 2 or half <= 0.1:
		return
	var reach := int(ceili((half + 2.2) / maxf(cell, 0.1)))
	var count := path.size()
	var n := count if closed and count >= 3 else count - 1
	if closed and count >= 3 and path[0].distance_to(path[count - 1]) < 2.0:
		n = count - 1
	for index in n:
		var a: Vector2 = path[index]
		var b: Vector2 = path[(index + 1) % count]
		var run := a.distance_to(b)
		var pieces := maxi(1, int(ceili(run / maxf(cell * 0.5, 1.0))))
		for piece in pieces + 1:
			var at := a.lerp(b, float(piece) / float(pieces))
			var cx := roundi(at.x / cell)
			var cy := roundi(at.y / cell)
			for ox in range(-reach, reach + 1):
				for oy in range(-reach, reach + 1):
					var key := Vector2i(cx + ox, cy + oy)
					if blocked.has(key):
						continue
					var uv := Vector2(float(key.x) * cell, float(key.y) * cell)
					if uv.distance_to(at) <= half + 2.2:
						blocked[key] = true


func _pad_interior_cell(city: PatchCity, key: Vector2i) -> bool:
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			if not city._pad_tops.has(Vector2i(key.x + ox, key.y + oy)):
				return false
	return true


func _cell_blobs(cells: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for start in cells:
		if seen.has(start):
			continue
		var blob: Dictionary = {}
		var stack: Array = [start]
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			if seen.has(at) or not cells.has(at):
				continue
			seen[at] = true
			blob[at] = true
			stack.append(Vector2i(at.x + 1, at.y))
			stack.append(Vector2i(at.x - 1, at.y))
			stack.append(Vector2i(at.x, at.y + 1))
			stack.append(Vector2i(at.x, at.y - 1))
		if blob.size() >= 2:
			out.append(blob)
	return out


func _cell_blob_bounds(blob: Dictionary, cell: float) -> Vector4:
	var min_x := 1.0e9
	var min_y := 1.0e9
	var max_x := -1.0e9
	var max_y := -1.0e9
	for key in blob:
		var at: Vector2i = key
		var x := float(at.x) * cell
		var y := float(at.y) * cell
		min_x = minf(min_x, x)
		min_y = minf(min_y, y)
		max_x = maxf(max_x, x)
		max_y = maxf(max_y, y)
	return Vector4(min_x, min_y, max_x, max_y)


func _point_to_poly(at: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 1.0e9
	if Geometry2D.is_point_in_polygon(at, poly):
		return 0.0
	var best := 1.0e9
	for index in poly.size():
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var ab := b - a
		var run := ab.length_squared()
		if run < 0.0001:
			best = minf(best, at.distance_to(a))
			continue
		var t := clampf((at - a).dot(ab) / run, 0.0, 1.0)
		best = minf(best, at.distance_to(a.lerp(b, t)))
	return best


func _expect_streets_clear_highway(city: PatchCity) -> void:
	var arteries: Dictionary = city.fabric.get("arteries", {})
	var highway: PackedVector2Array = arteries.get("highway", PackedVector2Array())
	if highway.size() < 2:
		return
	var half := float(arteries.get("highway_half", 8.0))
	var wrapped := highway.duplicate()
	if highway[0].distance_to(highway[highway.size() - 1]) > 1.5:
		wrapped.append(highway[0])
	var hits := 0
	var checked := 0
	for street in city.fabric.get("streets", []):
		var row: Dictionary = street
		var path: PackedVector2Array = row["uv"]
		for index in path.size():
			checked += 1
			if _point_to_path(path[index], wrapped) + 0.2 < half:
				hits += 1
	_expect(checked > 0, "inner streets were sampled against the city road")
	_expect(hits == 0,
		"inner streets stay off the city road (%d samples sat on it)" % hits)


func _expect_districts_clear_spikes(
		plan: PatchCityGenerator.Plan,
		shape: PlanetShape
	) -> void:
	var hits := 0
	var checked := 0
	var half := PatchCityGenerator.CELL * 0.42
	var offsets := PackedVector2Array()
	offsets.append(Vector2.ZERO)
	offsets.append(Vector2(-half, 0.0))
	offsets.append(Vector2(half, 0.0))
	offsets.append(Vector2(0.0, -half))
	offsets.append(Vector2(0.0, half))
	offsets.append(Vector2(-half, -half))
	offsets.append(Vector2(half, -half))
	offsets.append(Vector2(half, half))
	offsets.append(Vector2(-half, half))
	for district in plan.districts:
		for direction in district.dirs:
			checked += 1
			var up := direction.normalized()
			var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
			var north := up.cross(east)
			var floor_h := shape.elevation(up, PatchCityGenerator.CELL)
			var peak := floor_h
			for offset in offsets:
				var at := (up + (east * offset.x + north * offset.y) / shape.radius).normalized()
				peak = maxf(peak, shape.elevation(at, 0.0))
			if peak - floor_h > PatchCityGenerator.SPIKE_RELIEF:
				hits += 1
	_expect(checked > 0, "district tiles were surveyed for hoodoo spikes")
	_expect(hits == 0,
		"district tiles stay off hoodoo spikes (%d sat on them)" % hits)


func _expect_districts_not_buried(city: PatchCity, shape: PlanetShape) -> void:
	var cell := city._pad_cell
	if city._pad_tops.is_empty() or cell <= 0.1:
		return
	var by_district: Dictionary = {}
	for key in city._pad_owner:
		var district_id: int = int(city._pad_owner[key])
		var keys: Array = by_district.get(district_id, [])
		keys.append(key)
		by_district[district_id] = keys
	if by_district.is_empty():
		for key in city._pad_tops:
			var keys: Array = by_district.get(0, [])
			keys.append(key)
			by_district[0] = keys
	for district_id in by_district:
		var keys: Array = by_district[district_id]
		if keys.is_empty():
			continue
		var buried := 0
		for key in keys:
			var at: Vector2i = key
			var pad := float(city._pad_tops[at])
			var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
			var ground := shape.elevation(city._from_uv(origin), 0.0)
			if ground > pad + 0.2:
				buried += 1
		_expect(float(buried) / float(keys.size()) <= PatchCity.BURIED_SHARE,
			"district %d pad is not mostly underground (%d / %d buried)" % [
				int(district_id), buried, keys.size()])


func _expect_varied_headings(city: PatchCity) -> void:
	var lots: Array = city.fabric.get("lots", [])
	if lots.size() < 8:
		return
	var headings: Dictionary = {}
	for lot in lots:
		var along: Vector2 = (lot as Dictionary)["along"]
		if along.length_squared() < 0.0001:
			continue
		var octant := int(roundi(fposmod(along.angle() + TAU, TAU) / (TAU * 0.125))) % 8
		headings[octant] = true
	_expect(headings.size() >= 3,
		"buildings follow more than one street heading (%d)" % headings.size())


func _expect_packed_house_districts(city: PatchCity) -> void:
	var house_ids: Dictionary = {}
	var mixed: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)) \
				or bool(row.get("mega", false)):
			continue
		var district_id := int(row.get("district_id", -1))
		if int(row.get("typology", 0)) <= PatchCity.TYPE_SHOP \
				and int(row.get("typology", 0)) != PatchCity.TYPE_APARTMENT:
			house_ids[district_id] = true
		elif int(row.get("typology", 0)) >= PatchCity.TYPE_TOWER:
			mixed[district_id] = true
	var pure := 0
	for district_id in house_ids:
		if not mixed.has(district_id):
			pure += 1
	if pure <= 0:
		return
	var tight_n := 0
	var tight_w := 0.0
	var tight_c := 0.0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var district_id := int(row.get("district_id", -1))
		if mixed.has(district_id) or not house_ids.has(district_id):
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		if int(row.get("typology", 0)) > PatchCity.TYPE_SHOP:
			continue
		if int(row.get("typology", 0)) == PatchCity.TYPE_APARTMENT:
			continue
		if bool(row.get("tight", false)):
			tight_n += 1
			tight_w += float(row.get("width", 0.0))
			tight_c += float(row.get("coverage", 0.0))
	_expect(tight_n > 0, "small districts pack houses and shops tightly")
	if tight_n > 0:
		_expect(tight_w / float(tight_n) <= 11.0,
			"tight house lots stay narrow (%.1f m)" % (tight_w / float(tight_n)))
		_expect(tight_c / float(tight_n) >= 0.62,
			"tight house lots cover more of the block (%.2f)"
			% (tight_c / float(tight_n)))
	var street_h := 0.0
	var street_n := 0
	for street in city.fabric.get("streets", []):
		var row: Dictionary = street
		var district_id := int(row.get("district_id", -1))
		if mixed.has(district_id) or not house_ids.has(district_id):
			continue
		if int(row.get("rank", 1)) != 1:
			continue
		street_n += 1
		street_h += float(row.get("half", 3.1))
	if street_n > 0:
		_expect(street_h / float(street_n) <= 2.2,
			"house-district streets stay thin (%.2f m half)"
			% (street_h / float(street_n)))


func _expect_medium_apartment_packs(city: PatchCity) -> void:
	var megas: Dictionary = {}
	var tight_n: Dictionary = {}
	var lot_n: Dictionary = {}
	var packs: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		var district_id := int(row.get("district_id", -1))
		lot_n[district_id] = int(lot_n.get(district_id, 0)) + 1
		if bool(row.get("mega", false)):
			megas[district_id] = true
		if bool(row.get("tight", false)):
			tight_n[district_id] = int(tight_n.get(district_id, 0)) + 1
		if not bool(row.get("apartment_pack", false)):
			continue
		var list: Array = packs.get(district_id, [])
		list.append(row)
		packs[district_id] = list
	var midrise := 0
	var packed_n := 0
	for district_id in lot_n:
		if megas.has(district_id):
			continue
		var n := int(lot_n[district_id])
		if n < 8:
			continue
		if int(tight_n.get(district_id, 0)) * 2 >= n:
			continue
		midrise += 1
		var cluster: Array = packs.get(district_id, [])
		_expect(cluster.size() >= 3,
			"medium district %s packs a few large apartments (%d)"
			% [district_id, cluster.size()])
		if cluster.size() < 2:
			continue
		packed_n += cluster.size()
		var nn := 0.0
		var wide := 0.0
		var tall := 0.0
		for pack_i in cluster.size():
			var row: Dictionary = cluster[pack_i]
			_expect(int(row.get("typology", 0)) == PatchCity.TYPE_APARTMENT,
				"the packed buildings are apartments")
			wide += float(row.get("width", 0.0))
			tall += float(row.get("stories", 0.0))
			var here: Vector2 = row["centre"]
			var nearest := 1.0e9
			for other_i in cluster.size():
				if other_i == pack_i:
					continue
				nearest = minf(nearest, here.distance_to((cluster[other_i] as Dictionary)["centre"]))
			nn += nearest
		nn /= float(cluster.size())
		_expect(nn <= 32.0,
			"medium-district apartments sit in a pack (%.1f m apart)" % nn)
		_expect(wide / float(cluster.size()) >= 12.0,
			"packed apartments are larger walk-ups (%.1f m)"
			% (wide / float(cluster.size())))
		_expect(tall / float(cluster.size()) >= 6.5,
			"packed apartments are mid-rise (%.1f stories)"
			% (tall / float(cluster.size())))
	if midrise <= 0:
		return
	print("patch_city_test:     medium apartment packs %d districts, %d buildings"
		% [midrise, packed_n])


func _expect_outward_tops(city: PatchCity, mesh_name: String) -> void:
	var instance := city.get_node_or_null(mesh_name) as MeshInstance3D
	_expect(instance != null and instance.mesh != null, "%s mesh exists" % mesh_name)
	if instance == null or instance.mesh == null:
		return
	var arrays := instance.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_expect(verts.size() >= 6, "%s has triangles" % mesh_name)
	var farthest := 0.0
	for point in verts:
		farthest = maxf(farthest, point.length())
	var band := farthest - 1.2
	var outward := 0
	var inward := 0
	var index := 0
	while index + 2 < verts.size():
		var a: Vector3 = verts[index]
		var b: Vector3 = verts[index + 1]
		var c: Vector3 = verts[index + 2]
		var mid := (a + b + c) / 3.0
		index += 3
		if mid.length() < band:
			continue
		if (b - a).cross(c - a).dot(mid) > 0.0:
			outward += 1
		else:
			inward += 1
	_expect(outward + inward > 0, "%s has top faces to check" % mesh_name)
	_expect(outward > inward,
		"%s tops face outward (%d out, %d in)" % [mesh_name, outward, inward])


func _expect_road_above_pad(
		city: PatchCity,
		plan: PatchCityGenerator.Plan,
		shape: PlanetShape
	) -> void:
	if plan.loop.is_empty():
		return
	var sample: Vector3 = plan.loop[plan.loop.size() / 2]
	var pad := city._pad_top_at(sample)
	if is_nan(pad):
		return
	var elev := shape.elevation(sample, 8.0)
	_expect(pad > elev, "pad sits above the local terrain")
	var highway := city.get_node_or_null("Highway") as MeshInstance3D
	if highway == null or highway.mesh == null:
		return
	var arrays := highway.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nearest := INF
	var height := 0.0
	for point in verts:
		var away := point.normalized().angle_to(sample)
		if away < nearest:
			nearest = away
			height = point.length() - city._radius
	_expect(height + 0.05 >= pad,
		"highway stays above the pad (road %.2f, pad %.2f)" % [height, pad])


func _expect_highway_deck(city: PatchCity, shape: PlanetShape) -> void:
	var dirs: PackedVector3Array = city._highway_dirs
	var deck: PackedFloat32Array = city._highway_deck
	var n := dirs.size()
	if n < 8 or deck.size() != n:
		_fail("paved highway recorded a deck to patch")
		return
	var buried := 0
	var steep := 0
	var worst := 0.0
	var span := PatchCity.HIGHWAY_PATCH_SPAN
	var cap := PatchCity.HIGHWAY_GRADE + 0.05
	for index in n:
		var floor_h := maxf(
			shape.elevation(dirs[index], 2.0) + PatchCity.HIGHWAY_MIN_LIFT,
			city._road_over_pad(dirs[index]))
		if deck[index] + 0.08 < floor_h:
			buried += 1
		var left := city._reach_along(dirs, index, -1, true, span)
		var right := city._reach_along(dirs, index, 1, true, span)
		for side in [left, right]:
			var run := float(side["run"])
			if run < 8.0:
				continue
			var grade := absf(deck[index] - deck[int(side["at"])]) / run
			worst = maxf(worst, grade)
			if grade > cap:
				steep += 1
	_expect(buried == 0,
		"highway stays above terrain and paving (%d samples were buried)" % buried)
	_expect(steep == 0,
		"highway deck stays under %.2f grade in a %.0f m window (%d steep, worst %.2f)"
		% [cap, span, steep, worst])


func _expect_pad_clears_ground(city: PatchCity, shape: PlanetShape) -> void:
	var cell := city._pad_cell
	if city._pad_tops.is_empty() or cell <= 0.1:
		_fail("paved districts recorded pad cells")
		return
	var over := 0.0
	var checked := 0
	var inset := cell * 0.35
	for key in city._pad_tops:
		var at: Vector2i = key
		var pad := float(city._pad_tops[at])
		var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
		for ox in [-inset, 0.0, inset]:
			for oy in [-inset, 0.0, inset]:
				var ground := shape.elevation(city._from_uv(origin + Vector2(ox, oy)), 0.0)
				checked += 1
				over = maxf(over, ground - pad)
	_expect(checked > 0, "pad cells were surveyed for spike tips")
	_expect(over <= 0.05,
		"pad sits above the true surface, including hoodoo tips (over by %.2f m)" % over)


func _expect_pad_not_floating(city: PatchCity, shape: PlanetShape) -> void:
	var cell := city._pad_cell
	if city._pad_tops.is_empty() or cell <= 0.1:
		return
	var floated := 0
	var total := 0
	for key in city._pad_tops:
		var at: Vector2i = key
		var pad := float(city._pad_tops[at])
		var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
		var ground := shape.elevation(city._from_uv(origin), 0.0)
		total += 1
		if pad - ground > PatchCity.PAD_FLOAT + 1.0:
			floated += 1
	_expect(total > 0, "pad cells exist to check float")
	_expect(floated * 3 <= total,
		"pads more than 20 m above ground are split (%d / %d still float)" % [
			floated, total])


func _expect_district_aprons(city: PatchCity, shape: PlanetShape) -> void:
	var mesh := city.get_node_or_null("CityApron") as MeshInstance3D
	_expect(mesh != null and mesh.mesh != null, "paved districts slope down to the terrain")
	_expect(city.get_node_or_null("CityApronBody") != null, "district aprons have collision")
	var apron_mat := mesh.material_override as ShaderMaterial if mesh != null else null
	_expect(
		apron_mat != null and apron_mat.shader == PatchCity.APRON_SHADER,
		"district aprons use the two-sided planet ground shader")
	if apron_mat != null:
		_expect(
			float(apron_mat.get_shader_parameter(&"ground_lift")) >= 0.2,
			"district aprons lift off the interpolated planet mesh")
	_expect(city.get_node_or_null("CityRamps") == null, "districts no longer grow jutting ramps")
	if mesh == null or mesh.mesh == null:
		return
	var arrays := mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_expect(verts.size() >= 48, "apron wraps the district rims (%d verts)" % verts.size())
	var facing_out := 0
	var facing_in := 0
	var index_data := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		index_data = arrays[Mesh.ARRAY_INDEX]
	var tri_count := index_data.size() / 3 if index_data.size() >= 3 else verts.size() / 3
	var tri_step := maxi(1, int(tri_count / 80))
	for tri in range(0, tri_count, tri_step):
		var ia := 0
		var ib := 0
		var ic := 0
		if index_data.size() >= 3:
			ia = index_data[tri * 3]
			ib = index_data[tri * 3 + 1]
			ic = index_data[tri * 3 + 2]
		else:
			ia = tri * 3
			ib = tri * 3 + 1
			ic = tri * 3 + 2
		if ic >= verts.size():
			break
		var a: Vector3 = verts[ia]
		var b: Vector3 = verts[ib]
		var c: Vector3 = verts[ic]
		var mid := (a + b + c) * (1.0 / 3.0)
		if (b - a).cross(c - a).dot(mid) >= 0.0:
			facing_out += 1
		else:
			facing_in += 1
	_expect(facing_out > 0 and facing_in > 0,
		"apron is two-sided (%d out, %d in)" % [facing_out, facing_in])
	var near_pad := 0
	var near_ground := 0
	var above_gap := 0
	var step := maxi(1, int(verts.size() / 80))
	for index in range(0, verts.size(), step):
		var point: Vector3 = verts[index]
		var span := point.length()
		if span < 1.0:
			continue
		var up := point / span
		var height := span - city._radius
		var ground := shape.elevation(up, 0.0)
		if shape.has_method(&"natural_elevation"):
			ground = maxf(ground, float(shape.natural_elevation(up, 0.0)))
		var pad := city._pad_top_at(up)
		if not is_nan(pad) and absf(height - pad) < 1.4:
			near_pad += 1
		if absf(height - ground) < 2.2:
			near_ground += 1
		if height > ground + 0.25 and (is_nan(pad) or height < pad - 0.35):
			above_gap += 1
	_expect(near_pad > 0, "apron meets the paved slab")
	_expect(near_ground > 0, "apron meets the terrain")
	_expect(above_gap > 0, "apron occupies the gap under the pad")
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var pavement_like := 0
	var matched := 0
	var coloured := 0
	for index in range(0, cols.size(), step):
		coloured += 1
		var sample: Color = cols[index]
		var walk_d := Vector3(
			sample.r - PatchCity.PAVEMENT_WALK.r,
			sample.g - PatchCity.PAVEMENT_WALK.g,
			sample.b - PatchCity.PAVEMENT_WALK.b).length()
		var road_d := Vector3(
			sample.r - PatchCity.PAVEMENT_ROAD.r,
			sample.g - PatchCity.PAVEMENT_ROAD.g,
			sample.b - PatchCity.PAVEMENT_ROAD.b).length()
		if walk_d < 0.14 or road_d < 0.08:
			pavement_like += 1
		var point: Vector3 = verts[index]
		if point.length_squared() < 1.0:
			continue
		var want := shape.biome_color_at(point.normalized(), 0.0)
		var tint_d := Vector3(
			sample.r - want.r, sample.g - want.g, sample.b - want.b).length()
		if tint_d < 0.08:
			matched += 1
	_expect(coloured > 0, "apron carries vertex colour")
	_expect(pavement_like * 8 < coloured,
		"apron is biome ground, not pavement paint (%d / %d)" % [
			pavement_like, coloured])
	_expect(matched * 2 >= coloured,
		"apron tint is the terrain colour at that heading (%d / %d)" % [
			matched, coloured])
	print("patch_city_test:     district apron %d verts" % verts.size())


func _expect_apron_uses_terrain_tint(city: PatchCity, shape: PlanetShape) -> void:
	# Dress used to stamp walk/asphalt on the top of the ramp. The lip is
	# the case that has to stay planet-coloured once the pad is painted.
	city._dressed = true
	var uv := Vector2(18.0, 12.0)
	var ink := city._apron_ink(shape, uv, 0.0)
	var want := shape.biome_color_at(city._from_uv(uv), 0.0)
	var tint_d := Vector3(ink.r - want.r, ink.g - want.g, ink.b - want.b).length()
	var walk_d := Vector3(
		ink.r - PatchCity.PAVEMENT_WALK.r,
		ink.g - PatchCity.PAVEMENT_WALK.g,
		ink.b - PatchCity.PAVEMENT_WALK.b).length()
	var road_d := Vector3(
		ink.r - PatchCity.PAVEMENT_ROAD.r,
		ink.g - PatchCity.PAVEMENT_ROAD.g,
		ink.b - PatchCity.PAVEMENT_ROAD.b).length()
	_expect(tint_d < 0.02, "painted apron ink is the local terrain tint")
	_expect(walk_d > 0.16 and road_d > 0.10,
		"painted apron ink is not pad pavement")
	city._dressed = false


func _expect_sky_paint(city: PatchCity) -> void:
	var families: Dictionary = {}
	var mega_styles: Dictionary = {}
	var bright := 0
	var dark := 0
	var sky := 0
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if int(row.get("typology", 0)) < 4:
			continue
		var style := int(row.get("paint_style", -1))
		if style < PatchCity.PAINT_SKY_DARK or style > PatchCity.PAINT_SKY_ORANGE:
			continue
		families[style] = int(families.get(style, 0)) + 1
		sky += 1
		var tint: Color = row.get("paint_tint", Color.BLACK)
		var lum := tint.r * 0.22 + tint.g * 0.67 + tint.b * 0.11
		if lum >= 0.58:
			bright += 1
		if lum <= 0.36:
			dark += 1
		if bool(row.get("mega", false)):
			var district_id: int = int(row.get("district_id", -1))
			var list: Array = mega_styles.get(district_id, [])
			list.append(style)
			mega_styles[district_id] = list
	_expect(sky > 8, "skyscrapers received facade families")
	_expect(families.size() >= 4, "skyline uses dark, silver, copper and orange (%d)"
		% families.size())
	_expect(bright > 0 and dark > 0,
		"skyscrapers mix bright and dark packs (%d bright, %d dark)" % [bright, dark])
	for district_id in mega_styles:
		var styles: Array = mega_styles[district_id]
		var same := true
		for style in styles:
			if int(style) != int(styles[0]):
				same = false
				break
		_expect(same, "mega towers in a district share a facade pack")
	var neon_lots := 0
	var neon_hues: Dictionary = {}
	for lot in city.fabric.get("lots", []):
		var row: Dictionary = lot
		if int(row.get("typology", 0)) < 4:
			continue
		var neon: Color = row.get("paint_neon", Color.BLACK)
		var sat := maxf(neon.r, maxf(neon.g, neon.b)) - minf(neon.r, minf(neon.g, neon.b))
		if sat < 0.28:
			continue
		neon_lots += 1
		var bucket := int(floor(neon.h * 8.0))
		neon_hues[bucket] = int(neon_hues.get(bucket, 0)) + 1
	_expect(neon_lots >= maxi(sky - 1, 1),
		"skyscrapers get a neon trim colour (%d / %d)" % [neon_lots, sky])
	_expect(neon_hues.size() >= 3,
		"neon trims are not one colour (%d hues)" % neon_hues.size())
	print("patch_city_test:     sky paint dark %d  silver %d  copper %d  orange %d"
		% [
			int(families.get(PatchCity.PAINT_SKY_DARK, 0)),
			int(families.get(PatchCity.PAINT_SKY_SILVER, 0)),
			int(families.get(PatchCity.PAINT_SKY_COPPER, 0)),
			int(families.get(PatchCity.PAINT_SKY_ORANGE, 0)),
		])


func _expect_destructible_city(city: PatchCity) -> void:
	var lots: Array = city.destructible_buildings()
	_expect(not lots.is_empty(), "painted lots are destructible buildings")
	_expect(city.get_node_or_null("CityLots") != null,
		"destructible lots live under CityLots")
	var house: Node3D
	var sky: Node3D
	for item in lots:
		var building := item as Node3D
		if building == null or not building.has_method(&"typology"):
			continue
		if sky == null and int(building.call(&"typology")) >= PatchCity.TYPE_SKY:
			sky = building
		elif house == null and not bool(building.call(&"is_large")):
			house = building
	_expect(house != null, "a small building can take damage")
	if house == null:
		return
	var before := float(house.call(&"health"))
	var tap := DamageHit.impact(
		house.call(&"combat_position"),
		float(house.call(&"combat_radius")) + 1.2,
		before * 0.12)
	tap.faction = DamageHit.Faction.PLAYER
	var lost := float(house.call(&"apply_hit", tap))
	_expect(lost > 0.0 and float(house.call(&"health")) < before,
		"an attack reduces building health")
	_expect(bool(house.call(&"has_hit_flash")), "a hit building flashes red")
	if sky != null:
		var before_crown := float(sky.call(&"health"))
		var crown := DamageHit.impact(sky.call(&"roof_point"), 3.0, 28.0)
		crown.faction = DamageHit.Faction.PLAYER
		var crown_lost := float(sky.call(&"apply_hit", crown))
		_expect(crown_lost > 0.0 and float(sky.call(&"health")) < before_crown,
			"a hit on the crown damages a tall building")
	var hurt_hit := DamageHit.impact(
		house.call(&"combat_position"),
		float(house.call(&"combat_radius")) + 1.2,
		maxf(float(house.call(&"health")) - float(house.call(&"max_health")) * 0.59, 1.0))
	hurt_hit.faction = DamageHit.Faction.PLAYER
	house.call(&"apply_hit", hurt_hit)
	_expect(bool(house.call(&"is_hurt")) and bool(house.call(&"has_smoke")),
		"a building at 60% health cracks and smokes")
	if sky != null:
		var shear_hit := DamageHit.impact(
			sky.call(&"combat_position"),
			float(sky.call(&"combat_radius")) + 2.0,
			maxf(float(sky.call(&"health")) - float(sky.call(&"max_health")) * 0.49, 1.0))
		shear_hit.faction = DamageHit.Faction.PLAYER
		sky.call(&"apply_hit", shear_hit)
		_expect(bool(sky.call(&"is_sheared")) and bool(sky.call(&"has_smoke")),
			"a skyscraper at 50% health loses its crown and smokes")
		_expect(float(sky.call(&"_visual_stories")) < float(sky.call(&"original_stories")) * 0.7,
			"the broken tower stands lower than the intact crown")
	var neighbor: Node3D
	var nearest := 1.0e9
	for item in lots:
		var building := item as Node3D
		if building == null or building == house:
			continue
		if building.has_method(&"is_wrecked") and bool(building.call(&"is_wrecked")):
			continue
		if not building.has_method(&"combat_position"):
			continue
		var away := (building.call(&"combat_position") as Vector3).distance_to(
			house.call(&"combat_position") as Vector3)
		if away < nearest:
			nearest = away
			neighbor = building
	var neighbor_hp := float(neighbor.call(&"health")) if neighbor != null else 0.0
	var kill := DamageHit.impact(
		house.call(&"combat_position"),
		float(house.call(&"combat_radius")) + 1.2,
		float(house.call(&"health")) + 40.0)
	kill.faction = DamageHit.Faction.PLAYER
	house.call(&"apply_hit", kill)
	_expect(bool(house.call(&"is_wrecked")) and bool(house.call(&"has_smoke")),
		"a destroyed building leaves smoldering remains")
	var blasts := 0
	var clouds := 0
	for child in city.get_children():
		var fx := child as EnergyExplosion
		if fx == null:
			continue
		blasts += 1
		if fx.has_cloud():
			clouds += 1
	_expect(blasts > 0, "a collapsing building detonates")
	_expect(clouds == 0, "the collapse fireball has no mushroom cloud")
	var blast: DamageHit = house.call(&"collapse_hit")
	_expect(blast != null and blast.radius >= 6.0 and blast.amount > 20.0,
		"the death blast scales with the building")
	city.flush_building_blasts()
	if neighbor != null and nearest <= float(house.call(&"explode_radius")) + float(neighbor.call(&"combat_radius")):
		_expect(float(neighbor.call(&"health")) < neighbor_hp,
			"a collapsing building damages its neighbours")


func _expect_pavement_breaks(city: PatchCity) -> void:
	_expect_pavement_deck_collision(city)
	_expect(city.get_node_or_null("PavementPaintBody") != null,
		"painted pavement keeps a solid collider")
	var cell := city._pad_cell
	_expect(cell > 0.1 and not city._pad_tops.is_empty(),
		"the city has a paved deck")
	var key := Vector2i.ZERO
	for item in city._pad_tops:
		key = item
		break
	var uv := Vector2(float(key.x) * cell, float(key.y) * cell)
	var direction := city._from_uv(uv).normalized()
	_expect(city.has_intact_pavement(direction),
		"fresh pavement is a solid deck")
	var light := TerrainScars.Scar.new()
	light.direction = direction
	light.radius = 3.0
	light.depth = 0.2
	var blocked := city.absorb_scar(light)
	_expect(blocked > 0.15 and city.pavement_hole_count() == 0,
		"a shallow hit is stopped by the slab")
	_expect(city.has_intact_pavement(direction),
		"the deck stays closed under a shallow hit")
	var punch := TerrainScars.Scar.new()
	punch.direction = direction
	punch.radius = 8.0
	punch.depth = 2.5
	var absorbed := city.absorb_scar(punch)
	_expect(is_equal_approx(absorbed, PatchCity.PAVEMENT_THICK),
		"a meteor-scale punch spends its first metres on the slab")
	_expect(city.pavement_hole_count() == 0, "the pavement does not break")
	_expect(city.has_intact_pavement(direction),
		"the deck stays closed under a deep hit")
	_expect(city.get_node_or_null("PavementRubble") == null,
		"intact pavement leaves no rubble")


func _expect_pavement_deck_collision(city: PatchCity) -> void:
	var body := city.get_node_or_null("PavementPaintBody") as StaticBody3D
	if body == null:
		return
	var two_sided := 0
	var chunks := 0
	var buried := 0
	var faces := 0
	var shape := city._planet_shape
	for child in body.get_children():
		var collider := child as CollisionShape3D
		if collider == null:
			continue
		var concave := collider.shape as ConcavePolygonShape3D
		if concave == null:
			continue
		chunks += 1
		if concave.backface_collision:
			two_sided += 1
		if shape == null:
			continue
		var tris := concave.get_faces()
		var index := 0
		while index + 2 < tris.size():
			var mid := (tris[index] + tris[index + 1] + tris[index + 2]) / 3.0
			index += 3
			var span := mid.length()
			if span < 1.0:
				continue
			faces += 1
			var ground := city._radius + shape.elevation(mid / span, 0.0)
			if span < ground - 0.85:
				buried += 1
	_expect(chunks > 0, "pavement collision is chunked")
	_expect(two_sided == chunks, "pavement chunks collide from both sides")
	_expect(faces > 0, "pavement collision has faces")
	_expect(buried * 4 < faces,
		"pavement collision stays a deck rather than a volume inside the planet (%d buried / %d)"
		% [buried, faces])


func _as_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is Vector3:
		var rgb := value as Vector3
		return Color(rgb.x, rgb.y, rgb.z)
	return Color.BLACK


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_fail(message)


func _fail(message: String) -> void:
	_failures += 1
	push_error("patch_city_test: FAIL  %s" % message)
