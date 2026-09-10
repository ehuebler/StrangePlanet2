extends Node

## Adobe city, office, and castle seating.
##
##     godot --headless --path . dev/_adobe_site_test.tscn

var _failures := 0


func _ready() -> void:
	_check_catalog()
	_check_palettes()
	await _check_city_scatter()
	await _check_monuments()
	print("adobe_site_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_catalog() -> void:
	_expect(CrawlerAdobeSite.CITY_BUILDINGS.size() == 1
			and CrawlerAdobeSite.CITY_BUILDINGS[0] == CrawlerAdobeSite.VILLAGE_MODEL,
		"the city catalog is the blob village")
	_expect(is_equal_approx(CrawlerAdobeSite.CITY_SCALE, 1.5),
		"city adobe is fifty percent larger")
	_expect(BuildingFoundation.is_path_mesh(
			"GRAY ADOBE | 14 shaped pads + 23 winding connections")
			and BuildingFoundation.is_path_mesh(
			"Seamless union of all pads and lanes"),
		"the authored gray path is recognized as a path mesh")
	_expect(not BuildingFoundation.is_path_mesh("01 Leaning Loaf"),
		"adobe buildings are not treated as path meshes")
	_expect(BuildingFoundation.is_shell_mesh("01 Leaning Loaf")
			and BuildingFoundation.is_shell_mesh("12 Skylight Commons")
			and BuildingFoundation.is_shell_mesh(
				"10 Pavilion Corporation / Four-Level Blob HQ")
			and BuildingFoundation.is_shell_mesh("09 Continuous blob castle shell"),
		"house, office, and castle shells keep doorway collision")
	_expect(not BuildingFoundation.is_shell_mesh("02 Plateau seat 1")
			and not BuildingFoundation.is_shell_mesh("GRAY ADOBE | 14 shaped pads"),
		"furniture and paths are not treated as shells")
	_expect(CrawlerAdobeSite.city_ready(), "city adobe GLBs are imported")
	_expect(CrawlerAdobeSite.monuments_ready(), "office and castle adobe GLBs are imported")


func _check_palettes() -> void:
	var city := CrawlerAdobeSite.palette_for("city")
	var later := CrawlerAdobeSite.palette_for(CrawlerRules.CITY_CRESCENT_SITE_ID)
	var office := CrawlerAdobeSite.palette_for(CrawlerProgress.QUEST_TOWER)
	var castle := CrawlerAdobeSite.palette_for(CrawlerProgress.QUEST_CASTLE)
	_expect(city.size() == 3 and later.size() == 3, "each site has three adobe colours")
	_expect(city[0] != later[0] or city[1] != later[1] or city[2] != later[2],
		"two cities do not share a palette")
	_expect(office[0] != castle[0] or office[1] != castle[1] or office[2] != castle[2],
		"office and castle roll different palettes")


func _check_city_scatter() -> void:
	var ring := CrawlerCityRing.new()
	ring.force_village = true
	add_child(ring)
	await get_tree().process_frame
	_expect(ring.get_node_or_null("Village") != null, "the ring seats a village")
	_expect(CrawlerAdobeSite.building_count(ring) == 1,
		"the ring seats the blob village")
	_expect(ring.find_child("CityWall", true, false) == null,
		"adobe seating replaces the stand-in walls")
	_expect(ring.find_child("VillageFolk", true, false) == null,
		"adobe cities do not seat meeps")
	_expect(ring.find_child("StallSign_hats", true, false) == null,
		"adobe cities do not float stall tiles")
	var painted := 0
	var paths := 0
	for child in ring.get_node("Village").get_children():
		if not str(child.name).begins_with("adobe_"):
			continue
		if _has_adobe_paint(child):
			painted += 1
		paths += _count_path_meshes(child)
	_expect(painted == 1, "the blob village keeps the adobe plaster")
	_expect(paths >= 1, "the blob village keeps its authored gray path")
	var path_faces := 0
	for child in ring.get_node("Village").get_children():
		if child is Node3D:
			path_faces += BuildingFoundation.path_face_count(child as Node3D)
	_expect(path_faces > 20, "the gray path has floor faces that can drop to terrain")
	var scaled := 0
	for child in ring.get_node("Village").get_children():
		if not str(child.name).begins_with("adobe_"):
			continue
		if child is Node3D and is_equal_approx((child as Node3D).scale.x, CrawlerAdobeSite.CITY_SCALE):
			scaled += 1
	_expect(scaled == 1, "the blob village sits fifty percent larger")
	var village_body: Node3D = null
	for child in ring.get_node("Village").get_children():
		if child is Node3D and str(child.name).begins_with("adobe_"):
			village_body = child as Node3D
			break
	_expect(village_body != null
			and village_body.get_node_or_null(PatchMonuments.WALK_BODY) != null,
		"the village keeps one walk body")
	_expect(_concave_count(village_body) >= 10,
		"village houses keep doorway holes in walk collision")
	_expect(_convex_count(village_body) > 0,
		"village furniture still uses cheap hulls")
	_expect(_find_named(village_body, "skylight commons") != null,
		"the village includes skylight commons")
	_expect(village_body.get_node_or_null(BuildingFoundation.SKIRT_NAME) == null,
		"the village does not lay a boxed pad under the paths")
	await get_tree().physics_frame
	_expect(_doorway_reaches_inside(village_body, "leaning loaf"),
		"a city doorway lets a walker into the house")
	ring.queue_free()
	await get_tree().process_frame


func _check_monuments() -> void:
	for path: String in [CrawlerAdobeSite.OFFICE_MODEL, CrawlerAdobeSite.CASTLE_MODEL]:
		var packed := load(path) as PackedScene
		_expect(packed != null, "%s loads" % path.get_file())
		if packed == null:
			continue
		var body := packed.instantiate() as Node3D
		_expect(body != null, "%s instantiates" % path.get_file())
		if body == null:
			continue
		add_child(body)
		CrawlerAdobeSite.prepare(body, path.get_file(), null)
		await get_tree().process_frame
		_expect(_has_adobe_paint(body), "%s keeps the adobe plaster" % path.get_file())
		_expect(_has_walk_collision(body)
				and body.get_node_or_null(PatchMonuments.WALK_BODY) != null,
			"%s has walkable collision" % path.get_file())
		_expect(_concave_count(body) >= 1,
			"%s keeps doorway holes on the shell" % path.get_file())
		_expect(is_equal_approx(body.scale.x, CrawlerAdobeSite.MONUMENT_SCALE),
			"%s sits seven percent larger" % path.get_file())
		body.queue_free()
	await get_tree().process_frame


func _find_named(node: Node, needle: String) -> Node:
	if node == null:
		return null
	if String(node.name).to_lower().contains(needle):
		return node
	for child in node.get_children():
		var found := _find_named(child, needle)
		if found != null:
			return found
	return null


func _count_path_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and BuildingFoundation.is_path_mesh(node.name):
		count += 1
	for child in node.get_children():
		count += _count_path_meshes(child)
	return count


func _has_walk_collision(node: Node) -> bool:
	if node is CollisionShape3D:
		var collider := node as CollisionShape3D
		if not collider.disabled and collider.shape != null:
			return true
	for child in node.get_children():
		if _has_walk_collision(child):
			return true
	return false


func _concave_count(node: Node) -> int:
	var count := 0
	if node is CollisionShape3D \
			and (node as CollisionShape3D).shape is ConcavePolygonShape3D:
		count += 1
	for child in node.get_children():
		count += _concave_count(child)
	return count


func _convex_count(node: Node) -> int:
	var count := 0
	if node is CollisionShape3D \
			and (node as CollisionShape3D).shape is ConvexPolygonShape3D:
		count += 1
	for child in node.get_children():
		count += _convex_count(child)
	return count


func _doorway_reaches_inside(root: Node3D, hull_name: String) -> bool:
	var mesh_i := _find_named(root, hull_name) as MeshInstance3D
	if mesh_i == null or mesh_i.mesh == null or not root.is_inside_tree():
		return false
	var aabb := mesh_i.global_transform * mesh_i.mesh.get_aabb()
	var center := aabb.get_center()
	center.y = aabb.position.y + minf(1.2, aabb.size.y * 0.35)
	var reach := maxf(aabb.size.x, aabb.size.z) * 0.55 + 2.0
	var space := root.get_world_3d().direct_space_state
	for index in 16:
		var angle := float(index) * TAU / 16.0
		var away := Vector3(cos(angle), 0.0, sin(angle))
		var from := center + away * reach
		from.y = center.y
		var query := PhysicsRayQueryParameters3D.create(from, center)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var at: Vector3 = hit.get("position", from)
		if from.distance_to(at) > from.distance_to(center) * 0.92:
			return true
	return false


func _has_adobe_paint(root: Node) -> bool:
	if root is MeshInstance3D:
		var mesh_i := root as MeshInstance3D
		var count := mesh_i.mesh.get_surface_count() if mesh_i.mesh != null else 0
		for surface in count:
			var material := mesh_i.get_active_material(surface)
			if material is ShaderMaterial \
					and (material as ShaderMaterial).shader == CrawlerAdobeSite.SHADER:
				return true
	for child in root.get_children():
		if _has_adobe_paint(child):
			return true
	return false


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("adobe_site_test failed: %s" % label)
