class_name PatchMonuments
extends Node3D

## Places the authored tower and castle on their land patches when the planet
## loads. Collision comes from each GLB's wall, floor, and furniture proxies,
## not a solid hull. Every session mode sees them; crawler quests only light
## the waypoints.

const TOWER_MODEL := "res://assets/runtime/environment/meridian_office_tower.glb"
const CASTLE_MODEL := "res://assets/runtime/environment/stormwatch_castle.glb"
const NIGHT_LIGHTS := preload("res://game/city/building_night_lights.gd")
const KEEP_OUT := 180.0
const TOWER_HALF_SPAN := 52.0


func _ready() -> void:
	name = "PatchMonuments"
	call_deferred(&"_ensure_sites", 0)


func _ensure_sites(tries: int) -> void:
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		if tries < 12:
			call_deferred(&"_ensure_sites", tries + 1)
		return
	_place_site(
		CrawlerProgress.QUEST_TOWER,
		"Meridian Tower",
		CrawlerRules.TOWER_PATCH,
		TOWER_MODEL,
		Color("ef151f"),
		overlay
	)
	_place_site(
		CrawlerProgress.QUEST_CASTLE,
		"Stormwatch Castle",
		CrawlerRules.CASTLE_PATCH,
		CASTLE_MODEL,
		Color("c9a227"),
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
	wire_interior_collision(body)
	BuildingFoundation.seat(body, site.planet_host())
	NIGHT_LIGHTS.bind(body, site.planet_host())
	BuildingFloraClear.register_node(site, body, site.direction)


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


static func _trimesh_from_mesh(mesh_i: MeshInstance3D) -> void:
	if mesh_i.mesh == null:
		return
	var shape := mesh_i.mesh.create_trimesh_shape()
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
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
