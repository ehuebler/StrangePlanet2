class_name BuildingFoundation
extends RefCounted

## Seats a building on the highest ground under its base, then fills the air
## underneath so nothing can walk through.

const SKIRT_NAME := "FoundationSkirt"
const BODY_NAME := "FoundationBody"
const EMBED := 0.85
const BASE_BAND := 2.8
const MIN_DROP := 0.10
const MAX_CELLS := 12
const DEFAULT_TINT := Color(0.15, 0.13, 0.12, 1.0)


static func peak_raise(base_h: float, ground: PackedFloat32Array) -> float:
	var peak := base_h
	for height in ground:
		peak = maxf(peak, height)
	return maxf(peak - base_h, 0.0)


static func drop_at(base_h: float, ground_h: float) -> float:
	return maxf(base_h - ground_h, 0.0) + EMBED


static func seat(root: Node3D, planet: Planet, tint := DEFAULT_TINT,
		parts: PackedStringArray = PackedStringArray()) -> void:
	if root == null or planet == null or planet.shape == null:
		return
	if not root.is_inside_tree():
		return
	clear(root)
	var boxes := _base_boxes(root, parts)
	if boxes.is_empty():
		return
	var bounds := boxes[0]
	for box in boxes:
		bounds = bounds.merge(box)
	if bounds.size.x < 0.4 or bounds.size.z < 0.4:
		return
	var spacing := planet.finest_spacing()
	var cols := _cells(bounds.size.x)
	var rows := _cells(bounds.size.z)
	var occupied := PackedByteArray()
	var ground := PackedFloat32Array()
	_sample_grid(root, planet, bounds, boxes, cols, rows, spacing, occupied, ground)
	if occupied.is_empty():
		return
	var raise := peak_raise(0.0, ground)
	if raise > 0.02:
		var up := root.transform.basis.y
		if up.length_squared() < 0.0001:
			up = Vector3.UP
		root.position += up.normalized() * raise
		for index in ground.size():
			ground[index] -= raise
	_add_skirt(root, bounds, occupied, ground, cols, rows, tint)


static func clear(root: Node) -> void:
	if root == null:
		return
	var skirt := root.get_node_or_null(SKIRT_NAME)
	if skirt != null:
		skirt.free()
	var body := root.get_node_or_null(BODY_NAME)
	if body != null:
		body.free()


static func _cells(span: float) -> int:
	return clampi(int(ceil(span / 8.0)), 4, MAX_CELLS)


static func _base_boxes(root: Node3D, parts: PackedStringArray) -> Array[AABB]:
	var found: Array[AABB] = []
	_collect_boxes(root, Transform3D.IDENTITY, parts, found)
	if found.is_empty():
		return found
	var floor_y := INF
	for box in found:
		floor_y = minf(floor_y, box.position.y)
	var kept: Array[AABB] = []
	for box in found:
		if box.position.y <= floor_y + BASE_BAND:
			kept.append(box)
	return kept


static func _collect_boxes(
		node: Node,
		xform: Transform3D,
		parts: PackedStringArray,
		found: Array[AABB]
	) -> void:
	if node is MeshInstance3D:
		var mesh_i := node as MeshInstance3D
		if _use_mesh(mesh_i, parts) and mesh_i.mesh != null:
			found.append(xform * mesh_i.mesh.get_aabb())
	for child in node.get_children():
		var next := xform
		if child is Node3D:
			next = xform * (child as Node3D).transform
		_collect_boxes(child, next, parts, found)


static func uses_pad_mesh(node_name: String) -> bool:
	var folded := node_name.to_lower()
	if folded.contains("colonly") or folded == SKIRT_NAME.to_lower():
		return false
	return not folded.contains("hummock") \
			and not folded.contains("meadow") \
			and not folded.contains("woodland") \
			and not folded.contains("earth")


static func _use_mesh(mesh_i: MeshInstance3D, parts: PackedStringArray) -> bool:
	if not uses_pad_mesh(mesh_i.name):
		return false
	if not parts.is_empty():
		for part in parts:
			if String(mesh_i.name).contains(part):
				return true
		return false
	return mesh_i.visible


static func _sample_grid(
		root: Node3D,
		planet: Planet,
		bounds: AABB,
		boxes: Array[AABB],
		cols: int,
		rows: int,
		spacing: float,
		occupied: PackedByteArray,
		ground: PackedFloat32Array
	) -> void:
	occupied.resize(cols * rows)
	ground.resize(cols * rows)
	var shape := planet.shape
	for row in rows:
		var tz := (float(row) + 0.5) / float(rows)
		var z := bounds.position.z + bounds.size.z * tz
		for col in cols:
			var tx := (float(col) + 0.5) / float(cols)
			var x := bounds.position.x + bounds.size.x * tx
			var index := row * cols + col
			if not _covers(boxes, x, z):
				occupied[index] = 0
				ground[index] = 0.0
				continue
			occupied[index] = 1
			# Authored buildings keep the walk floor at local y = 0. Sampling the
			# AABB bottom instead lifts any model with earth or hummocks under the
			# plaza until that dirt volume sits on the planet and shoves walkers.
			var world := root.to_global(Vector3(x, 0.0, z))
			var local := planet.to_local(world)
			if local.length_squared() < 1.0:
				ground[index] = 0.0
				continue
			var surface := planet.global_transform * shape.surface_point(
				local.normalized(), spacing)
			ground[index] = (surface - world).dot(root.global_transform.basis.y.normalized())


static func _covers(boxes: Array[AABB], x: float, z: float) -> bool:
	for box in boxes:
		if x < box.position.x or x > box.position.x + box.size.x:
			continue
		if z < box.position.z or z > box.position.z + box.size.z:
			continue
		return true
	return false


static func _add_skirt(
		root: Node3D,
		bounds: AABB,
		occupied: PackedByteArray,
		ground: PackedFloat32Array,
		cols: int,
		rows: int,
		tint: Color
	) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var made := false
	var base_y := bounds.position.y
	for row in rows:
		for col in cols:
			var index := row * cols + col
			if occupied[index] == 0:
				continue
			var drop := drop_at(0.0, ground[index])
			if drop < MIN_DROP:
				continue
			var x0 := bounds.position.x + bounds.size.x * float(col) / float(cols)
			var x1 := bounds.position.x + bounds.size.x * float(col + 1) / float(cols)
			var z0 := bounds.position.z + bounds.size.z * float(row) / float(rows)
			var z1 := bounds.position.z + bounds.size.z * float(row + 1) / float(rows)
			_emit_column(st, x0, x1, z0, z1, base_y, base_y - drop)
			made = true
	if not made:
		return
	st.generate_normals()
	var mesh := st.commit()
	var visual := MeshInstance3D.new()
	visual.name = SKIRT_NAME
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.94
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = mat
	root.add_child(visual)
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	var body := StaticBody3D.new()
	body.name = BODY_NAME
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)


static func _emit_column(
		st: SurfaceTool,
		x0: float,
		x1: float,
		z0: float,
		z1: float,
		top: float,
		bot: float
	) -> void:
	var a := Vector3(x0, bot, z0)
	var b := Vector3(x1, bot, z0)
	var c := Vector3(x1, bot, z1)
	var d := Vector3(x0, bot, z1)
	var e := Vector3(x0, top, z0)
	var f := Vector3(x1, top, z0)
	var g := Vector3(x1, top, z1)
	var h := Vector3(x0, top, z1)
	_quad(st, a, b, c, d)
	_quad(st, e, h, g, f)
	_quad(st, a, e, f, b)
	_quad(st, b, f, g, c)
	_quad(st, c, g, h, d)
	_quad(st, d, h, e, a)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
