class_name BuildingFloraClear
extends RefCounted

## Hard keep-out for plant scatter: the building footprint plus a 10 m ring.
## Stored as a snapshot so GroundCover worker threads can test it without
## touching the scene tree.

const PAD_METRES := 10.0

static var _ids: PackedStringArray = PackedStringArray()
static var _dirs: PackedVector3Array = PackedVector3Array()
static var _coss: PackedFloat32Array = PackedFloat32Array()


static func covers(direction: Vector3) -> bool:
	if _dirs.is_empty() or not direction.is_finite():
		return false
	var at := direction.normalized()
	for index in _dirs.size():
		if at.dot(_dirs[index]) >= _coss[index]:
			return true
	return false


static func register(
		id: String,
		direction: Vector3,
		radius_m: float,
		planet_radius := 8000.0
	) -> void:
	if id.is_empty() or not direction.is_finite() or direction.length_squared() < 0.25:
		return
	var reach := maxf(radius_m, 0.0) + PAD_METRES
	var cosine := cos(reach / maxf(planet_radius, 1.0))
	var at := direction.normalized()
	var found := _ids.find(id)
	if found >= 0:
		_dirs[found] = at
		_coss[found] = cosine
	else:
		_ids.append(id)
		_dirs.append(at)
		_coss.append(cosine)
	_replant(at, reach)


static func register_node(host: Node, model: Node3D, direction: Vector3) -> void:
	if host == null:
		return
	var planet_radius := 8000.0
	if host is SurfaceAnchor:
		var planet := (host as SurfaceAnchor).planet_host()
		if planet != null and planet.shape != null:
			planet_radius = planet.shape.radius
	elif model != null and model.is_inside_tree():
		var walk: Node = model
		while walk != null:
			if walk is Planet:
				var planet := walk as Planet
				if planet.shape != null:
					planet_radius = planet.shape.radius
				break
			walk = walk.get_parent()
	register(str(host.get_instance_id()), direction, mesh_radius(model), planet_radius)


static func unregister(id: String) -> void:
	var found := _ids.find(id)
	if found < 0:
		return
	_ids.remove_at(found)
	_dirs.remove_at(found)
	_coss.remove_at(found)


static func unregister_node(host: Node) -> void:
	if host != null:
		unregister(str(host.get_instance_id()))


static func mesh_radius(root: Node) -> float:
	if root == null:
		return 24.0
	var found := false
	var bounds := AABB()
	var stack: Array[Dictionary] = [{
		"node": root,
		"xform": Transform3D.IDENTITY,
	}]
	while not stack.is_empty():
		var item: Dictionary = stack.pop_back()
		var node: Node = item["node"]
		var xform: Transform3D = item["xform"]
		if node is MeshInstance3D:
			var mesh_i := node as MeshInstance3D
			var folded := String(mesh_i.name).to_lower()
			if mesh_i.mesh != null and not folded.contains("colonly") \
					and folded != "foundationskirt":
				var piece := xform * mesh_i.mesh.get_aabb()
				if found:
					bounds = bounds.merge(piece)
				else:
					bounds = piece
					found = true
		for child in node.get_children():
			var next := xform
			if child is Node3D:
				next = xform * (child as Node3D).transform
			stack.append({"node": child, "xform": next})
	if not found:
		return 24.0
	return maxf(maxf(bounds.size.x, bounds.size.z) * 0.5, 8.0)


static func _replant(direction: Vector3, reach: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node_variant: Variant in tree.get_nodes_in_group(DamageHit.FIELD_GROUP):
		var node := node_variant as Node
		if not is_instance_valid(node):
			continue
		if node.has_method(&"replant_around"):
			node.call(&"replant_around", direction, reach + 8.0)
		if node.has_method(&"hide_under_city"):
			node.call(&"hide_under_city")
