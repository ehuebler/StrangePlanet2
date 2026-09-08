class_name CrawlerInteriorHomes
extends RefCounted

## Walkable pads harvested from a seated castle or office GLB. Spawn
## empties come first, then a grid on floor-like meshes. Sampling stays
## in mesh space so a planet-seated building still yields interior
## points instead of a surface ring around the monument.

const STEP := 3.6
const LIFT := 1.05
const INSET := 1.6
const MIN_SPAN := 2.4
const MAX_FLOOR_Y := 3.8
const MAX_PER_MESH := 96


static func harvest(root: Node3D, want: int, min_gap := 1.8) -> PackedVector3Array:
	if root == null or want <= 0:
		return PackedVector3Array()
	var marks := spawn_markers(root)
	var floors := floor_points(root, maxi(want * 3, 64))
	return fit(_merge(marks, floors, min_gap), want)


static func spawn_markers(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	_collect_markers(root, out)
	return out


static func floor_points(root: Node3D, want: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	if root == null or want <= 0:
		return points
	var meshes := _floor_meshes(root)
	var seen: Dictionary = {}
	for mesh_i: MeshInstance3D in meshes:
		_sample_mesh(mesh_i, root, seen, points, want)
		if points.size() >= want:
			break
	return points


static func fit(src: PackedVector3Array, want: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	if src.is_empty() or want <= 0:
		return out
	if src.size() == want:
		return src
	if src.size() > want:
		var stride := float(src.size()) / float(want)
		for index in want:
			var pick := clampi(int(floor(float(index) * stride)), 0, src.size() - 1)
			out.append(src[pick])
		return out
	out.append_array(src)
	var spin_i := 0
	while out.size() < want:
		var home := src[spin_i % src.size()]
		var yaw := CrawlerRules.GOBLIN_GOLDEN * float(out.size())
		home += Vector3(cos(yaw), 0.0, sin(yaw)) * 0.55
		out.append(home)
		spin_i += 1
	return out


static func _collect_markers(node: Node, out: PackedVector3Array) -> void:
	if node is Node3D:
		var label := String(node.name)
		if label.begins_with("SPAWN_") or label.begins_with("SPAWN "):
			var at := (node as Node3D).global_position
			if at.is_finite():
				out.append(at)
	for child in node.get_children():
		_collect_markers(child, out)


static func _floor_meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root == null:
		return found
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := node as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null or not mesh_i.visible:
			continue
		if not is_floor_mesh(String(mesh_i.name)):
			continue
		found.append(mesh_i)
	found.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool:
		return _floor_rank(String(a.name)) < _floor_rank(String(b.name))
	)
	return found


static func is_floor_mesh(node_name: String) -> bool:
	var folded := node_name.to_lower()
	if folded.contains("colonly") or folded.contains("stair") \
			or folded.contains("curtain") or folded.contains("furnish") \
			or folded.contains("furniture") or folded.contains("meadow") \
			or folded.contains("oak") or folded.contains("tree") \
			or folded.contains("shell") or folded.contains("foundation") \
			or folded.contains("ceiling") or folded.contains("roof garden") \
			or folded.contains("sign"):
		return false
	if folded.contains("flagstone") or folded.contains("carpet"):
		return true
	if folded.contains("keep interior"):
		return true
	if folded.contains("courtyard") and folded.contains("ground"):
		return true
	if folded.contains("structure") and (folded.contains("tile") \
			or folded.contains("stone")):
		return true
	if folded.contains("rooms") and (folded.contains("tile") \
			or folded.contains("wood") or folded.contains("stone")):
		return true
	return false


static func _floor_rank(node_name: String) -> int:
	var folded := node_name.to_lower()
	if folded.contains("courtyard"):
		return 0
	if folded.contains("keep interior") or folded.contains("carpet"):
		return 1
	if folded.contains("wing rooms") or folded.contains("rooms"):
		return 2
	if folded.contains("bastion") and not folded.contains("roof"):
		return 3
	if folded.contains("structure"):
		return 2
	return 4


static func _sample_mesh(
		mesh_i: MeshInstance3D,
		root: Node3D,
		seen: Dictionary,
		points: PackedVector3Array,
		want: int
	) -> void:
	var box := mesh_i.mesh.get_aabb()
	if not _is_walk_box(box):
		return
	var up := _root_up(root)
	var added := 0
	var inner := box.grow(-INSET)
	if inner.size.x < MIN_SPAN or inner.size.z < MIN_SPAN:
		var centre := Vector3(
			box.get_center().x,
			box.position.y + box.size.y,
			box.get_center().z)
		_accept(mesh_i.to_global(centre) + up * LIFT, root, seen, points)
		return
	var cols := clampi(int(floor(inner.size.x / STEP)) + 1, 1, 28)
	var rows := clampi(int(floor(inner.size.z / STEP)) + 1, 1, 28)
	var top := box.position.y + box.size.y
	for row in rows:
		var tz := 0.5 if rows == 1 else float(row) / float(rows - 1)
		var z := inner.position.z + inner.size.z * tz
		for col in cols:
			if added >= MAX_PER_MESH or points.size() >= want:
				return
			var tx := 0.5 if cols == 1 else float(col) / float(cols - 1)
			var x := inner.position.x + inner.size.x * tx
			var world := mesh_i.to_global(Vector3(x, top, z)) + up * LIFT
			if _accept(world, root, seen, points):
				added += 1


static func _is_walk_box(box: AABB) -> bool:
	if box.size.x < MIN_SPAN or box.size.z < MIN_SPAN:
		return false
	if box.size.y <= MAX_FLOOR_Y:
		return true
	return box.size.y < minf(box.size.x, box.size.z) * 0.18


static func _accept(
		world: Vector3,
		root: Node3D,
		seen: Dictionary,
		points: PackedVector3Array
	) -> bool:
	if not world.is_finite():
		return false
	var local := root.to_local(world) if root != null else world
	var key := Vector3i(
		int(floor(local.x / 1.8)),
		int(floor(local.y / 2.2)),
		int(floor(local.z / 1.8)))
	if seen.has(key):
		return false
	seen[key] = true
	points.append(world)
	return true


static func _merge(
		first: PackedVector3Array,
		second: PackedVector3Array,
		min_gap: float
	) -> PackedVector3Array:
	var out := PackedVector3Array()
	var gap := maxf(min_gap, 0.4)
	var gap_sq := gap * gap
	for pack in [first, second]:
		for at: Vector3 in pack:
			if not at.is_finite():
				continue
			var clash := false
			for held: Vector3 in out:
				if at.distance_squared_to(held) < gap_sq:
					clash = true
					break
			if clash:
				continue
			out.append(at)
	return out


static func _root_up(root: Node3D) -> Vector3:
	if root == null:
		return Vector3.UP
	var up := root.global_transform.basis.y
	if up.length_squared() < 0.0001:
		return Vector3.UP
	return up.normalized()
