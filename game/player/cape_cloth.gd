class_name CapeCloth
extends Node3D

## A blank white cloth cape. The collar is pinned to the shoulders; the rest is
## a world-space Verlet sheet so it lags behind a running body, lifts in the
## wind, and drapes over the back instead of skating with the skeleton.
##
## Colour is a single albedo. Later tints wash this white field; the mesh is
## otherwise unpainted so a future colour-paint texture has a clean UV grid.

const COLS := 7
const ROWS := 10
const WIDTH := 0.48
const LENGTH := 0.86
const COLLAR_BACK := 0.07
const DAMPING := 0.965
const GRAVITY := 12.5
const WIND_DRAG := 0.72
const FLUTTER := 0.55
const CONSTRAINT_PASSES := 5
const TELEPORT := 0.55
const TORSO_RADIUS := 0.15
const HIP_RADIUS := 0.17

@export var cape_color := Color.WHITE:
	set(value):
		cape_color = value
		_apply_color()
@export var cape_paint: Texture2D:
	set(value):
		cape_paint = value
		_apply_color()

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _skeleton: Skeleton3D
var _pos: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _rest_len_row := 0.0
var _rest_len_col := 0.0
var _clock := 0.0
var _last_pin := Vector3.ZERO
var _has_last_pin := false
var _simulating := false


func _init() -> void:
	# Built here, not in _ready, so ItemIcons can photograph the rest pose
	# without putting the garment in a tree first.
	_material = StandardMaterial3D.new()
	_material.albedo_color = cape_color
	_material.roughness = 0.72
	_material.metallic = 0.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = MeshInstance3D.new()
	_mesh.name = "Cloth"
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_rest_len_row = WIDTH / float(COLS - 1)
	_rest_len_col = LENGTH / float(ROWS - 1)
	_fill_local_rest()
	_commit_mesh()
	process_priority = 40


func attach_to_skeleton(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_simulating = skeleton != null
	_has_last_pin = false
	if _simulating:
		_snap_to_body()


func cloth_mesh() -> MeshInstance3D:
	return _mesh


func apply_item(item_id: String) -> void:
	cape_color = ItemDB.tint(item_id)
	var path := ItemDB.paint_path(item_id)
	cape_paint = load(path) as Texture2D if not path.is_empty() else null


func _process(delta: float) -> void:
	if not _simulating or _skeleton == null or not is_instance_valid(_skeleton):
		return
	var step := clampf(delta, 0.0, 0.05)
	_clock += step
	var pin := _pin_world(int(COLS / 2.0))
	if _has_last_pin and pin.distance_to(_last_pin) > TELEPORT:
		_snap_to_body()
	_has_last_pin = true
	_last_pin = pin
	_integrate(step)
	_solve_constraints()
	_collide_torso()
	_commit_mesh()


func _integrate(delta: float) -> void:
	var down := _down()
	var back := _back()
	var right := _right()
	var wind := -_body_velocity() * WIND_DRAG
	var accel := down * GRAVITY + wind
	for col in COLS:
		var pin := _pin_world(col)
		var index := _index(col, 0)
		_pos[index] = pin
		_prev[index] = pin
	for row in range(1, ROWS):
		for col in COLS:
			var index := _index(col, row)
			var current := _pos[index]
			var velocity := (current - _prev[index]) * DAMPING
			var wave := sin(_clock * 5.1 + float(col) * 0.55 + float(row) * 0.18)
			var sway := cos(_clock * 3.4 + float(col) * 0.8)
			velocity += (back * wave + right * sway) * FLUTTER * delta * (float(row) / float(ROWS - 1))
			_prev[index] = current
			_pos[index] = current + velocity + accel * delta * delta


func _solve_constraints() -> void:
	for _constraint_pass in CONSTRAINT_PASSES:
		for row in ROWS:
			for col in range(COLS - 1):
				_keep(_index(col, row), _index(col + 1, row), _rest_len_row)
		for row in range(ROWS - 1):
			for col in COLS:
				_keep(_index(col, row), _index(col, row + 1), _rest_len_col)
		for row in range(ROWS - 1):
			for col in range(COLS - 1):
				_keep(_index(col, row), _index(col + 1, row + 1), _rest_len_row * 1.41)
				_keep(_index(col + 1, row), _index(col, row + 1), _rest_len_row * 1.41)
		for col in COLS:
			var index := _index(col, 0)
			_pos[index] = _pin_world(col)


func _keep(a: int, b: int, rest: float) -> void:
	var delta := _pos[b] - _pos[a]
	var distance := delta.length()
	if distance < 0.0001:
		return
	var share := (distance - rest) / distance
	var a_pin := a < COLS
	var b_pin := b < COLS
	if a_pin and b_pin:
		return
	if a_pin:
		_pos[b] -= delta * share
	elif b_pin:
		_pos[a] += delta * share
	else:
		var half := delta * share * 0.5
		_pos[a] += half
		_pos[b] -= half


func _collide_torso() -> void:
	var chest := _bone_world(&"UpperChest")
	var hips := _bone_world(&"Hips")
	var back := _back()
	var chest_center := chest + back * 0.02
	var hip_center := hips + back * 0.04
	var plane_point := chest + back * 0.01
	for row in range(1, ROWS):
		for col in COLS:
			var index := _index(col, row)
			var point := _pos[index]
			point = _push_sphere(point, chest_center, TORSO_RADIUS)
			point = _push_sphere(point, hip_center, HIP_RADIUS)
			var into := (point - plane_point).dot(back)
			if into < 0.0:
				point -= back * into
			_pos[index] = point


func _push_sphere(point: Vector3, center: Vector3, radius: float) -> Vector3:
	var offset := point - center
	var distance := offset.length()
	if distance >= radius or distance < 0.0001:
		return point
	return center + offset * (radius / distance)


func _snap_to_body() -> void:
	_pos.resize(COLS * ROWS)
	_prev.resize(COLS * ROWS)
	var down := _down()
	var back := _back()
	for row in ROWS:
		var row_t := float(row) / float(ROWS - 1)
		var taper := 1.0 - row_t * 0.08
		for col in COLS:
			var col_t := float(col) / float(COLS - 1)
			var pin := _pin_world(col)
			var centered := (col_t - 0.5) * WIDTH * (taper - 1.0)
			var point := pin \
				+ down * (LENGTH * row_t) \
				+ back * (0.03 + 0.10 * row_t) \
				+ _right() * centered
			var index := _index(col, row)
			_pos[index] = point
			_prev[index] = point
	_commit_mesh()


func _fill_local_rest() -> void:
	_pos.resize(COLS * ROWS)
	_prev.resize(COLS * ROWS)
	for row in ROWS:
		var row_t := float(row) / float(ROWS - 1)
		var taper := 1.0 - row_t * 0.10
		for col in COLS:
			var col_t := float(col) / float(COLS - 1)
			var x := (col_t - 0.5) * WIDTH * taper
			var y := -LENGTH * row_t
			var z := 0.04 + 0.10 * row_t + sin(col_t * PI) * 0.03
			var index := _index(col, row)
			_pos[index] = Vector3(x, y, z)
			_prev[index] = _pos[index]


func _commit_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(ROWS - 1):
		for col in range(COLS - 1):
			var a := _local(_index(col, row))
			var b := _local(_index(col + 1, row))
			var c := _local(_index(col, row + 1))
			var d := _local(_index(col + 1, row + 1))
			var uv_a := Vector2(float(col) / float(COLS - 1), float(row) / float(ROWS - 1))
			var uv_b := Vector2(float(col + 1) / float(COLS - 1), float(row) / float(ROWS - 1))
			var uv_c := Vector2(float(col) / float(COLS - 1), float(row + 1) / float(ROWS - 1))
			var uv_d := Vector2(float(col + 1) / float(COLS - 1), float(row + 1) / float(ROWS - 1))
			_quad(st, a, b, c, d, uv_a, uv_b, uv_c, uv_d)
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, _material)
	_mesh.mesh = mesh
	if _mesh.material_override == null:
		_mesh.material_override = _material


func _quad(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2
) -> void:
	_tri(st, a, b, d, uv_a, uv_b, uv_d)
	_tri(st, a, d, c, uv_a, uv_d, uv_c)
	_tri(st, a, d, b, uv_a, uv_d, uv_b)
	_tri(st, a, c, d, uv_a, uv_c, uv_d)


func _tri(
	st: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2
) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		normal = Vector3.BACK
	else:
		normal = normal.normalized()
	st.set_normal(normal)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_uv(uv_c)
	st.add_vertex(c)


func _local(index: int) -> Vector3:
	if not is_inside_tree():
		return _pos[index]
	return global_transform.affine_inverse() * _pos[index]


func _pin_world(col: int) -> Vector3:
	var t := float(col) / float(COLS - 1)
	var left := _shoulder(&"LeftShoulder", &"LeftUpperArm")
	var right := _shoulder(&"RightShoulder", &"RightUpperArm")
	var mid := left.lerp(right, 0.5)
	var chest := _bone_world(&"UpperChest")
	if chest != Vector3.ZERO:
		mid = mid.lerp(chest, 0.18)
	return left.lerp(right, t).lerp(mid, 0.12) + _back() * COLLAR_BACK + _up() * 0.015


func _shoulder(root_name: StringName, arm_name: StringName) -> Vector3:
	var root := _bone_world(root_name)
	var arm := _bone_world(arm_name)
	if root == Vector3.ZERO:
		return _fallback_origin() + _right() * (-WIDTH * 0.5 if String(root_name).begins_with("Left") else WIDTH * 0.5)
	if arm == Vector3.ZERO:
		return root
	return root.lerp(arm, 0.42)


func _bone_world(bone_name: StringName) -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return Vector3.ZERO
	var bone := CharacterRig.find_bone(_skeleton, bone_name)
	if bone < 0:
		return Vector3.ZERO
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


func _basis_axis(axis: int) -> Vector3:
	if _skeleton != null and is_instance_valid(_skeleton):
		var bone := CharacterRig.find_bone(_skeleton, &"UpperChest")
		if bone >= 0:
			var xf := _skeleton.global_transform * _skeleton.get_bone_global_pose(bone)
			match axis:
				0:
					return xf.basis.x.normalized()
				1:
					return xf.basis.y.normalized()
				_:
					return xf.basis.z.normalized()
		match axis:
			0:
				return _skeleton.global_transform.basis.x.normalized()
			1:
				return _skeleton.global_transform.basis.y.normalized()
			_:
				return _skeleton.global_transform.basis.z.normalized()
	match axis:
		0:
			return Vector3.RIGHT
		1:
			return Vector3.UP
		_:
			return Vector3.FORWARD


func _up() -> Vector3:
	var hips := _bone_world(&"Hips")
	var chest := _bone_world(&"UpperChest")
	if hips != Vector3.ZERO and chest != Vector3.ZERO:
		var up := (chest - hips).normalized()
		if up.length_squared() > 0.01:
			return up
	return _basis_axis(1)


func _down() -> Vector3:
	return -_up()


func _right() -> Vector3:
	var left := _bone_world(&"LeftShoulder")
	var right := _bone_world(&"RightShoulder")
	if left != Vector3.ZERO and right != Vector3.ZERO:
		var across := right - left
		if across.length_squared() > 0.002:
			return across.normalized()
	return _basis_axis(0)


func _back() -> Vector3:
	var across := _right()
	var up := _up()
	var back := across.cross(up)
	if back.length_squared() < 0.0001:
		back = -_basis_axis(2)
	back = back.normalized()
	var head := _bone_world(&"Head")
	var chest := _bone_world(&"UpperChest")
	if head != Vector3.ZERO and chest != Vector3.ZERO:
		var forward := head - chest
		forward -= up * forward.dot(up)
		if forward.length_squared() > 0.0004 and back.dot(forward.normalized()) > 0.0:
			back = -back
	return back


func _body_velocity() -> Vector3:
	var node: Node = _skeleton
	while node != null:
		if node is CharacterBody3D:
			return (node as CharacterBody3D).velocity
		node = node.get_parent()
	return Vector3.ZERO


func _fallback_origin() -> Vector3:
	if _skeleton != null and is_instance_valid(_skeleton):
		return _skeleton.global_transform.origin
	return global_position if is_inside_tree() else Vector3.ZERO


func _index(col: int, row: int) -> int:
	return row * COLS + col


func _apply_color() -> void:
	if _material == null:
		return
	_material.albedo_color = cape_color
	_material.albedo_texture = cape_paint
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
