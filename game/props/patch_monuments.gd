class_name PatchMonuments
extends Node3D

## Places the adobe office and castle on their land patches when the planet
## loads. House shells keep the visible mesh so doorways stay open. Streets
## are a box grid. Furniture stays a cheap hull. Crawler runs place their
## own copies; this host is the session-mode fallback.

const TOWER_MODEL := "res://assets/runtime/environment/adobe/adobe_office.glb"
const CASTLE_MODEL := "res://assets/runtime/environment/adobe/adobe_castle.glb"
const KEEP_OUT := 180.0
const TOWER_HALF_SPAN := 52.0
const WALK_BODY := "WalkBody"
const PATH_CELL := 1.5


func _ready() -> void:
	name = "PatchMonuments"
	call_deferred(&"_ensure_sites", 0)


func _ensure_sites(tries: int) -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		if tries < 12:
			call_deferred(&"_ensure_sites", tries + 1)
		return
	if CrawlerRun.active():
		return
	_place_site(
		CrawlerProgress.QUEST_TOWER,
		"Meridian Tower",
		CrawlerRules.TOWER_PATCH,
		TOWER_MODEL,
		CrawlerRules.OFFICE_WAYPOINT_TINT,
		overlay
	)
	_place_site(
		CrawlerProgress.QUEST_CASTLE,
		"Stormwatch Castle",
		CrawlerRules.CASTLE_PATCH,
		CASTLE_MODEL,
		CrawlerRules.CASTLE_WAYPOINT_TINT,
		overlay
	)
	_apply_session_quests()


func _place_site(
		monument_id: String,
		title: String,
		patch_name: String,
		model_path: String,
		tint: Color,
		overlay: LandPatchOverlay
	) -> void:
	if get_node_or_null(monument_id) != null:
		return
	var patch_id := overlay.patch_id_named(patch_name)
	if patch_id < 0:
		push_warning("PatchMonuments: missing patch %s" % patch_name)
		return
	var inland := overlay.flat_direction_for_patch(patch_id)
	if inland.length_squared() < 0.25:
		push_warning("PatchMonuments: no pad on %s" % patch_name)
		return
	var direction := inland
	if monument_id == CrawlerProgress.QUEST_TOWER:
		direction = overlay.shore_direction_for_patch(patch_id, TOWER_HALF_SPAN)
	var site := PatchMonument.new()
	site.name = monument_id
	site.monument_id = monument_id
	site.title = title
	site.tint = tint
	site.waypoint = false
	site.keepout_radius = KEEP_OUT
	site.hide_beyond = 0.0
	site.show_beyond = 0.0
	site.aimed_beyond = 0.0
	site.direction = direction
	site.clearance = 0.0
	add_child(site)
	_attach_model(site, model_path)


func _attach_model(site: PatchMonument, model_path: String) -> void:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		push_warning("PatchMonuments: missing model %s" % model_path)
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_warning("PatchMonuments: could not load %s" % model_path)
		return
	var body := packed.instantiate() as Node3D
	if body == null:
		push_warning("PatchMonuments: empty model %s" % model_path)
		return
	body.name = "Model"
	site.add_child(body)
	CrawlerAdobeSite.prepare(body, site.monument_id, site.planet_host())
	BuildingFloraClear.register_node(
		site,
		body,
		site.direction,
		CrawlerAdobeSite.footprint_metres(body),
		CrawlerAdobeSite.FLORA_PAD)


static func wire_interior_collision(root: Node) -> void:
	_drop_envelope(root)
	_harden_trimesh(root)
	_drop_underfill(root)
	if _has_trimesh(root):
		return
	for mesh_i in _mesh_instances(root):
		if not _is_colonly(mesh_i.name) or _is_underfill_proxy(mesh_i.name):
			continue
		_trimesh_from_mesh(mesh_i)
	if not _has_trimesh(root):
		push_warning("PatchMonuments: %s has no wall or floor collision" % root.name)


static func _drop_envelope(root: Node) -> void:
	var held := root.get_parent()
	if held != null:
		var box := held.find_child("MonumentCollision", true, false)
		if box != null:
			box.free()


## Dirt and turf under a plaza are authored as thick volumes. Left solid they
## sit in the walker's capsule and shove them around the streets. Godot strips
## `-colonly` so the body is named like the proxy (`00 Organic meadow`); painted
## surfaces keep a material suffix after `|` and stay visible.
static func _is_underfill_proxy(node_name: String) -> bool:
	var folded := node_name.to_lower()
	return folded.contains("meadow") and not folded.contains("|")


static func _drop_underfill(node: Node) -> void:
	if _is_underfill_proxy(node.name):
		_disable_collision_tree(node)
		return
	for child in node.get_children():
		_drop_underfill(child)


static func _disable_collision_tree(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is MeshInstance3D and _is_underfill_proxy(node.name):
		(node as MeshInstance3D).visible = false
	for child in node.get_children():
		_disable_collision_tree(child)


static func _harden_trimesh(node: Node) -> void:
	if node is CollisionShape3D:
		var shape := (node as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D:
			(shape as ConcavePolygonShape3D).backface_collision = true
		var body := node.get_parent() as StaticBody3D
		if body != null:
			body.collision_layer = 1
			body.collision_mask = 0
	for child in node.get_children():
		_harden_trimesh(child)


static func _has_trimesh(node: Node) -> bool:
	if node is CollisionShape3D:
		var collider := node as CollisionShape3D
		if not collider.disabled and collider.shape is ConcavePolygonShape3D:
			if not _is_underfill_proxy(node.name):
				var held := node.get_parent()
				if held == null or not _is_underfill_proxy(held.name):
					return true
	for child in node.get_children():
		if _has_trimesh(child):
			return true
	return false


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_mesh_instances(child))
	return found


static func _is_colonly(node_name: String) -> bool:
	var folded := node_name.to_lower()
	return folded.ends_with("-colonly") \
			or folded.ends_with("_colonly") \
			or folded.ends_with("$colonly") \
			or folded.contains("colonly")


static func wire_visible_collision(root: Node) -> void:
	_drop_envelope(root)
	_harden_trimesh(root)
	if _has_authored_colonly(root):
		return
	_clear_walk_body(root)
	_wire_walk_collision(root)
	if not _has_walk_shape(root):
		push_warning("PatchMonuments: %s has no walkable collision" % root.name)


static func _has_authored_colonly(root: Node) -> bool:
	for mesh_i in _mesh_instances(root):
		if _is_colonly(mesh_i.name):
			return true
	return false


static func _clear_walk_body(root: Node) -> void:
	var held := root.get_node_or_null(WALK_BODY)
	if held != null:
		held.free()


static func _wire_walk_collision(root: Node) -> void:
	if root == null:
		return
	var body := StaticBody3D.new()
	body.name = WALK_BODY
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	_add_walk_shapes(root, Transform3D.IDENTITY, body)
	if body.get_child_count() == 0:
		body.free()


static func _add_walk_shapes(node: Node, xform: Transform3D, body: StaticBody3D) -> void:
	if node is MeshInstance3D:
		var mesh_i := node as MeshInstance3D
		if _use_walk_mesh(mesh_i):
			if BuildingFoundation.is_path_instance(mesh_i):
				_add_path_boxes(body, mesh_i.mesh, xform)
			elif BuildingFoundation.is_shell_mesh(mesh_i.name):
				_add_trimesh(body, mesh_i.mesh, xform)
			else:
				_add_convex(body, mesh_i.mesh, xform)
	for child in node.get_children():
		if child == body or child.name == WALK_BODY:
			continue
		var next := xform
		if child is Node3D:
			next = xform * (child as Node3D).transform
		_add_walk_shapes(child, next, body)


static func _use_walk_mesh(mesh_i: MeshInstance3D) -> bool:
	if mesh_i.mesh == null or not mesh_i.visible:
		return false
	if _is_underfill_proxy(mesh_i.name) or _is_colonly(mesh_i.name):
		return false
	var named := String(mesh_i.name)
	return named != BuildingFoundation.SKIRT_NAME \
			and named != BuildingFoundation.PATH_SKIRT_NAME


static func _add_convex(body: StaticBody3D, mesh: Mesh, xform: Transform3D) -> void:
	var shape := mesh.create_convex_shape(true, true)
	if shape == null:
		shape = mesh.create_convex_shape(true, false)
	if shape == null:
		return
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = xform
	body.add_child(collider)


static func _add_trimesh(body: StaticBody3D, mesh: Mesh, xform: Transform3D) -> void:
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = xform
	body.add_child(collider)


static func _add_path_boxes(body: StaticBody3D, mesh: Mesh, xform: Transform3D) -> void:
	var cells := {}
	var tris := PackedVector3Array()
	BuildingFoundation.collect_floor_tris(mesh, xform, tris)
	var cursor := 0
	while cursor + 2 < tris.size():
		_mark_path_cells(tris[cursor], tris[cursor + 1], tris[cursor + 2], cells)
		cursor += 3
	for key_variant: Variant in cells.keys():
		var key: Vector2i = key_variant
		var span: Vector2 = cells[key]
		var thick := maxf(span.y - span.x, 0.45)
		var box := BoxShape3D.new()
		box.size = Vector3(PATH_CELL, thick, PATH_CELL)
		var collider := CollisionShape3D.new()
		collider.shape = box
		collider.position = Vector3(
			(float(key.x) + 0.5) * PATH_CELL,
			(span.x + span.y) * 0.5,
			(float(key.y) + 0.5) * PATH_CELL)
		body.add_child(collider)


static func _mark_path_cells(a: Vector3, b: Vector3, c: Vector3, cells: Dictionary) -> void:
	var min_y := minf(a.y, minf(b.y, c.y))
	var max_y := maxf(a.y, maxf(b.y, c.y))
	var x0 := int(floor(minf(a.x, minf(b.x, c.x)) / PATH_CELL))
	var x1 := int(floor(maxf(a.x, maxf(b.x, c.x)) / PATH_CELL))
	var z0 := int(floor(minf(a.z, minf(b.z, c.z)) / PATH_CELL))
	var z1 := int(floor(maxf(a.z, maxf(b.z, c.z)) / PATH_CELL))
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var key := Vector2i(x, z)
			if cells.has(key):
				var held: Vector2 = cells[key]
				cells[key] = Vector2(minf(held.x, min_y), maxf(held.y, max_y))
			else:
				cells[key] = Vector2(min_y, max_y)


static func _has_walk_shape(node: Node) -> bool:
	if node is CollisionShape3D:
		var collider := node as CollisionShape3D
		if not collider.disabled and collider.shape != null:
			return true
	for child in node.get_children():
		if _has_walk_shape(child):
			return true
	return false


static func _already_has_body(mesh_i: MeshInstance3D) -> bool:
	for child in mesh_i.get_children():
		if child is StaticBody3D:
			return true
	return false


static func _trimesh_from_mesh(mesh_i: MeshInstance3D, hide := true) -> void:
	if mesh_i.mesh == null:
		return
	var shape := mesh_i.mesh.create_trimesh_shape()
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	if hide:
		mesh_i.visible = false
	var body := StaticBody3D.new()
	body.name = "%s_Body" % mesh_i.name
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	mesh_i.add_child(body)


func _apply_session_quests() -> void:
	if CrawlerProgress.session_payload.is_empty():
		return
	var ledger := CrawlerProgress.new()
	ledger.from_dict(CrawlerProgress.session_payload)
	CrawlerSites.apply_progress(ledger, get_tree())


func _overlay() -> LandPatchOverlay:
	var planet := get_parent() as Planet
	if planet == null:
		return null
	return planet.get_node_or_null("LandPatches") as LandPatchOverlay
