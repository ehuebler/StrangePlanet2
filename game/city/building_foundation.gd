class_name BuildingFoundation
extends RefCounted

## Seats a building on the highest ground under its base, then fills the air
## underneath so nothing can walk through. City villages skip that boxed
## stem: only the authored grey path drops down to uneven ground.

const SKIRT_NAME := "FoundationSkirt"
const BODY_NAME := "FoundationBody"
const PATH_SKIRT_NAME := "PathSkirt"
const PATH_BODY_NAME := "PathBody"
const EMBED := 0.85
const BASE_BAND := 2.8
const MIN_DROP := 0.10
const MAX_CELLS := 12
const DEFAULT_TINT := Color(0.15, 0.13, 0.12, 1.0)
const PATH_TINT := Color(0.56, 0.53, 0.48, 1.0)


static func peak_raise(base_h: float, ground: PackedFloat32Array) -> float:
	var peak := base_h
	for height in ground:
		peak = maxf(peak, height)
	return maxf(peak - base_h, 0.0)


static func drop_at(base_h: float, ground_h: float) -> float:
	return maxf(base_h - ground_h, 0.0) + EMBED


static func path_face_count(root: Node3D) -> int:
	if root == null:
		return 0
	return int(_collect_path_tris(root).size() / 3)


static func collect_floor_tris(mesh: Mesh, xform: Transform3D,
		found: PackedVector3Array) -> void:
	_append_floor_tris(mesh, xform, found)


static func is_path_mesh(node_name: String) -> bool:
	var folded := node_name.to_lower()
	return folded.contains("gray adobe") or folded.contains("grey adobe") \
			or folded.contains("shared path") or folded.contains("pads and") \
			or folded.contains("pads +") or folded.contains("winding connection") \
			or folded.contains("seamless union") or folded.contains("neutral ground")


static func is_path_instance(mesh_i: MeshInstance3D) -> bool:
	if mesh_i == null:
		return false
	if is_path_mesh(mesh_i.name):
		return true
	return mesh_i.mesh != null and is_path_mesh(String(mesh_i.mesh.resource_name))


static func is_shell_mesh(node_name: String) -> bool:
	var folded := node_name.to_lower()
	if is_path_mesh(folded):
		return false
	if folded.contains("seat") or folded.contains("bench") \
			or folded.contains("stool") or folded.contains("counter") \
			or folded.contains("table") or folded.contains("stair") \
			or folded.contains("guard") or folded.contains("tread") \
			or folded.contains("parapet") or folded.contains("landing") \
			or folded.contains("threshold") or folded.contains("approach") \
			or folded.contains("spiral") or folded.contains("chair") \
			or folded.contains("desk") or folded.contains("cubicle") \
			or folded.contains("rail") or folded.contains("flight") \
			or folded.contains("partition"):
		return false
	return folded.contains("loaf") or folded.contains("high shoulder") \
			or folded.contains("broad shoulder") or folded.contains("roots") \
			or folded.contains("oculus") or folded.contains("humps") \
			or folded.contains("leaning tower") or folded.contains("long heel") \
			or folded.contains("pavilion") or folded.contains("gentle beast") \
			or folded.contains("animal adobe") or folded.contains("skylight commons") \
			or folded.contains("maison") or folded.contains("balcony house") \
			or folded.contains("burrow") or folded.contains("longhouse") \
			or folded.contains("blob hq") or folded.contains("corporation") \
			or folded.contains("castle shell")


static func seat(root: Node3D, planet: Planet, tint := DEFAULT_TINT,
		parts: PackedStringArray = PackedStringArray(),
		extrude_paths := false) -> void:
	if root == null or planet == null or planet.shape == null:
		return
	if not root.is_inside_tree():
		return
	clear(root)
	var boxes := _base_boxes(root, parts, extrude_paths)
	var path_tris := PackedVector3Array()
	if extrude_paths:
		path_tris = _collect_path_tris(root)
	if boxes.is_empty() and path_tris.is_empty():
		return
	var spacing := planet.finest_spacing()
	var peak_ground := PackedFloat32Array()
	var occupied := PackedByteArray()
	var ground := PackedFloat32Array()
	var bounds := AABB()
	var cols := 0
	var rows := 0
	if not boxes.is_empty():
		bounds = boxes[0]
		for box in boxes:
			bounds = bounds.merge(box)
		if bounds.size.x >= 0.4 and bounds.size.z >= 0.4:
			cols = _cells(bounds.size.x)
			rows = _cells(bounds.size.z)
			_sample_grid(root, planet, bounds, boxes, cols, rows, spacing,
				occupied, ground)
			peak_ground.append_array(ground)
	_sample_path_peak(root, planet, path_tris, spacing, peak_ground)
	if peak_ground.is_empty():
		return
	var raise := peak_raise(0.0, peak_ground)
	if raise > 0.02:
		var up := root.transform.basis.y
		if up.length_squared() < 0.0001:
			up = Vector3.UP
		root.position += up.normalized() * raise
		for index in ground.size():
			ground[index] -= raise
	if cols > 0 and rows > 0 and not extrude_paths:
		_add_skirt(root, bounds, occupied, ground, cols, rows, tint)
	if not path_tris.is_empty():
		_add_path_skirt(root, planet, path_tris, spacing)


static func clear(root: Node) -> void:
	if root == null:
		return
	for name: String in [SKIRT_NAME, BODY_NAME, PATH_SKIRT_NAME, PATH_BODY_NAME]:
		var held := root.get_node_or_null(name)
		if held != null:
			held.free()


static func _cells(span: float) -> int:
	return clampi(int(ceil(span / 8.0)), 4, MAX_CELLS)


static func _base_boxes(root: Node3D, parts: PackedStringArray,
		exclude_paths := false) -> Array[AABB]:
	var found: Array[AABB] = []
	_collect_boxes(root, Transform3D.IDENTITY, parts, found, exclude_paths)
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
		found: Array[AABB],
		exclude_paths: bool
	) -> void:
	if node is MeshInstance3D:
		var mesh_i := node as MeshInstance3D
		if _use_mesh(mesh_i, parts, exclude_paths) and mesh_i.mesh != null:
			found.append(xform * mesh_i.mesh.get_aabb())
	for child in node.get_children():
		var next := xform
		if child is Node3D:
			next = xform * (child as Node3D).transform
		_collect_boxes(child, next, parts, found, exclude_paths)


static func uses_pad_mesh(node_name: String) -> bool:
	var folded := node_name.to_lower()
	if folded.contains("colonly") or folded == SKIRT_NAME.to_lower() \
			or folded == PATH_SKIRT_NAME.to_lower():
		return false
	return not folded.contains("hummock") \
			and not folded.contains("meadow") \
			and not folded.contains("woodland") \
			and not folded.contains("earth")


static func _use_mesh(mesh_i: MeshInstance3D, parts: PackedStringArray,
		exclude_paths := false) -> bool:
	if not uses_pad_mesh(mesh_i.name):
		return false
	if exclude_paths and is_path_instance(mesh_i):
		return false
	if not parts.is_empty():
		for part in parts:
			if String(mesh_i.name).contains(part):
				return true
		return false
	return mesh_i.visible


static func _collect_path_tris(root: Node3D) -> PackedVector3Array:
	var found := PackedVector3Array()
	_gather_path_tris(root, Transform3D.IDENTITY, found)
	return found


static func _gather_path_tris(
		node: Node,
		xform: Transform3D,
		found: PackedVector3Array
	) -> void:
	if node is MeshInstance3D:
		var mesh_i := node as MeshInstance3D
		if mesh_i.visible and mesh_i.mesh != null and is_path_instance(mesh_i):
			_append_floor_tris(mesh_i.mesh, xform, found)
	for child in node.get_children():
		var next := xform
		if child is Node3D:
			next = xform * (child as Node3D).transform
		_gather_path_tris(child, next, found)


static func _append_floor_tris(
		mesh: Mesh,
		xform: Transform3D,
		found: PackedVector3Array
	) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idxs: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idxs = arrays[Mesh.ARRAY_INDEX]
		if idxs.is_empty():
			idxs.resize(verts.size())
			for index in verts.size():
				idxs[index] = index
		var cursor := 0
		while cursor + 2 < idxs.size():
			var a := xform * verts[idxs[cursor]]
			var b := xform * verts[idxs[cursor + 1]]
			var c := xform * verts[idxs[cursor + 2]]
			cursor += 3
			var across := (b - a).cross(c - a)
			var span := across.length()
			if span < 0.04:
				continue
			if across.y <= span * 0.35:
				continue
			var mid_y := (a.y + b.y + c.y) * (1.0 / 3.0)
			if mid_y > BASE_BAND:
				continue
			found.append(a)
			found.append(b)
			found.append(c)


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
			ground[index] = _ground_at(root, planet, Vector3(x, 0.0, z), spacing)


static func _sample_path_peak(
		root: Node3D,
		planet: Planet,
		tris: PackedVector3Array,
		spacing: float,
		peak_ground: PackedFloat32Array
	) -> void:
	var cursor := 0
	while cursor + 2 < tris.size():
		var mid := (tris[cursor] + tris[cursor + 1] + tris[cursor + 2]) * (1.0 / 3.0)
		peak_ground.append(_ground_at(root, planet, mid, spacing))
		cursor += 3


static func _ground_at(root: Node3D, planet: Planet, local: Vector3,
		spacing: float) -> float:
	var world := root.to_global(Vector3(local.x, 0.0, local.z))
	var planet_local := planet.to_local(world)
	if planet_local.length_squared() < 1.0:
		return 0.0
	var surface := planet.global_transform * planet.shape.surface_point(
		planet_local.normalized(), spacing)
	return (surface - world).dot(root.global_transform.basis.y.normalized())


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
	_attach_solid(root, st, SKIRT_NAME, BODY_NAME, tint)


static func _add_path_skirt(
		root: Node3D,
		planet: Planet,
		tris: PackedVector3Array,
		spacing: float
	) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var made := false
	var cursor := 0
	while cursor + 2 < tris.size():
		var a := tris[cursor]
		var b := tris[cursor + 1]
		var c := tris[cursor + 2]
		cursor += 3
		var a2 := _path_foot(root, planet, a, spacing)
		var b2 := _path_foot(root, planet, b, spacing)
		var c2 := _path_foot(root, planet, c, spacing)
		if a.y - a2.y < MIN_DROP and b.y - b2.y < MIN_DROP \
				and c.y - c2.y < MIN_DROP:
			continue
		_emit_prism(st, a, b, c, a2, b2, c2)
		made = true
	if not made:
		return
	_attach_solid(root, st, PATH_SKIRT_NAME, PATH_BODY_NAME, PATH_TINT, false)


static func _path_foot(root: Node3D, planet: Planet, local: Vector3,
		spacing: float) -> Vector3:
	var ground_h := _ground_at(root, planet, local, spacing)
	return Vector3(local.x, minf(local.y, ground_h) - EMBED, local.z)


static func _attach_solid(
		root: Node3D,
		st: SurfaceTool,
		visual_name: String,
		body_name: String,
		tint: Color,
		collide := true
	) -> void:
	st.generate_normals()
	var mesh := st.commit()
	var visual := MeshInstance3D.new()
	visual.name = visual_name
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.94
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = mat
	root.add_child(visual)
	if not collide:
		return
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	var body := StaticBody3D.new()
	body.name = body_name
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


static func _emit_prism(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		a2: Vector3,
		b2: Vector3,
		c2: Vector3
	) -> void:
	_tri(st, a2, c2, b2)
	_quad(st, a2, a, b, b2)
	_quad(st, b2, b, c, c2)
	_quad(st, c2, c, a, a2)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
