class_name CapeCloth
extends Node3D

## A blank white cloth cape. The collar is pinned to the shoulders; the rest is
## a world-space Verlet sheet so it lags behind a running body and drapes over
## the back.
##
## Folding and idle flapping are the usual Verlet-cape failure: distance
## springs alone cannot stop a grid crumpling, and per-column sine waves drive
## accordion folds. This follows the PhysX / Kim 2012 cloth recipe — stretch,
## shear, bend, then unilateral long-range attachments to the collar — plus
## collision inside the solver and wind that only scales with movement.
##
## Colour is a single albedo. Later tints wash this white field; the mesh is
## otherwise unpainted so a future colour-paint texture has a clean UV grid.

const COLS := 7
const ROWS := 10
const WIDTH := 0.48
const LENGTH := 0.86
const COLLAR_BACK := 0.07
const TAPER := 0.08
const DAMPING := 0.88
const GRAVITY := 10.5
const WIND_DRAG := 0.30
const WIND_MAX := 3.4
const WIND_FOLLOW := 4.5
const FLUTTER := 0.05
const SUBSTEPS := 1
const CONSTRAINT_PASSES := 3
const IDLE_SPEED := 0.45
const IDLE_PIN := 0.012
const BEND_STIFF := 0.55
const TETHER_SLACK := 1.06
const TORSO_RADIUS := 0.15
const HIP_RADIUS := 0.17
const TELEPORT := 0.55
const MIN_COL_SEP := 0.70

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
var _rest_len_col := 0.0
var _clock := 0.0
var _last_pin := Vector3.ZERO
var _has_last_pin := false
var _simulating := false
var _wind := Vector3.ZERO
var _pins: PackedVector3Array = PackedVector3Array()
var _axis_down := Vector3.DOWN
var _axis_back := Vector3.FORWARD
var _axis_right := Vector3.RIGHT
var _gold := false
var _sparkle := false
var _body: CharacterBody3D
var _bone_ids: Dictionary = {}
var _chest := Vector3.ZERO
var _hips := Vector3.ZERO
var _head := Vector3.ZERO
var _left_root := Vector3.ZERO
var _right_root := Vector3.ZERO
var _left_arm := Vector3.ZERO
var _right_arm := Vector3.ZERO
var _chest_center := Vector3.ZERO
var _hip_center := Vector3.ZERO
var _plane_point := Vector3.ZERO
var _rest_across: PackedFloat32Array = PackedFloat32Array()
var _vertices: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _uvs: PackedVector2Array = PackedVector2Array()
var _indices: PackedInt32Array = PackedInt32Array()
var _array_mesh: ArrayMesh
var _idle_ticks := 0


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
	_rest_len_col = LENGTH / float(ROWS - 1)
	_fill_local_rest()
	_build_mesh_shell()
	_commit_mesh()
	process_physics_priority = 40


func attach_to_skeleton(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_simulating = skeleton != null
	_has_last_pin = false
	_bone_ids.clear()
	_body = null
	var walk: Node = skeleton
	while walk != null:
		if walk is CharacterBody3D:
			_body = walk
			break
		walk = walk.get_parent()
	if _simulating:
		_snap_to_body()


func cloth_mesh() -> MeshInstance3D:
	return _mesh


func apply_item(item_id: String) -> void:
	_gold = item_id == "crawler_gold_cape"
	cape_color = ItemDB.tint(item_id)
	var path := ItemDB.paint_path(item_id)
	cape_paint = load(path) as Texture2D if not path.is_empty() else null
	_apply_color()


func set_sparkle(on: bool) -> void:
	if _sparkle == on:
		return
	_sparkle = on
	_apply_color()


func _physics_process(delta: float) -> void:
	if not _simulating or _skeleton == null or not is_instance_valid(_skeleton):
		return
	_cache_pose()
	var pin := _pin_at(int(COLS / 2.0))
	if _has_last_pin and pin.distance_to(_last_pin) > TELEPORT:
		_snap_to_body()
		_cache_pose()
		pin = _pin_at(int(COLS / 2.0))
	var moving := _body_velocity().length_squared() > IDLE_SPEED * IDLE_SPEED
	if _has_last_pin and pin.distance_squared_to(_last_pin) > IDLE_PIN * IDLE_PIN:
		moving = true
	_has_last_pin = true
	_last_pin = pin
	if not moving:
		_idle_ticks += 1
		if (_idle_ticks & 1) == 1:
			return
	else:
		_idle_ticks = 0
	var step := delta / float(SUBSTEPS)
	for _sub in SUBSTEPS:
		_clock += step
		_integrate(step)
		_solve_constraints()
	_commit_mesh()


func _cache_pose() -> void:
	_chest = _read_bone(&"UpperChest")
	_hips = _read_bone(&"Hips")
	_head = _read_bone(&"Head")
	_left_root = _read_bone(&"LeftShoulder")
	_right_root = _read_bone(&"RightShoulder")
	_left_arm = _read_bone(&"LeftUpperArm")
	_right_arm = _read_bone(&"RightUpperArm")
	_axis_down = _down()
	_axis_back = _back()
	_axis_right = _right()
	_pins.resize(COLS)
	var left := _shoulder_from(_left_root, _left_arm, true)
	var right := _shoulder_from(_right_root, _right_arm, false)
	var mid := left.lerp(right, 0.5)
	if _chest != Vector3.ZERO:
		mid = mid.lerp(_chest, 0.18)
	var lift := _up() * 0.015 + _axis_back * COLLAR_BACK
	for col in COLS:
		var t := float(col) / float(COLS - 1)
		_pins[col] = left.lerp(right, t).lerp(mid, 0.12) + lift
	_chest_center = _chest + _axis_back * 0.02
	_hip_center = _hips + _axis_back * 0.04
	_plane_point = _chest + _axis_back * 0.01


func _integrate(delta: float) -> void:
	var wanted := -_body_velocity() * WIND_DRAG
	if wanted.length() > WIND_MAX:
		wanted = wanted.normalized() * WIND_MAX
	_wind = _wind.lerp(wanted, clampf(delta * WIND_FOLLOW, 0.0, 1.0))
	var accel := _axis_down * GRAVITY + _wind
	var flap := clampf(_wind.length() / WIND_MAX, 0.0, 1.0)
	for col in COLS:
		var pin := _pin_at(col)
		var index := _index(col, 0)
		_pos[index] = pin
		_prev[index] = pin
	for row in range(1, ROWS):
		var hem := float(row) / float(ROWS - 1)
		# One shared wave along the length, not a per-column phase. Column
		# offsets are what accordion-fold a hanging sheet.
		var wave := sin(_clock * 1.55 + float(row) * 0.28) * FLUTTER * flap * hem
		for col in COLS:
			var index := _index(col, row)
			var current := _pos[index]
			var velocity := (current - _prev[index]) * DAMPING
			velocity += _axis_back * wave * delta
			_prev[index] = current
			_pos[index] = current + velocity + accel * delta * delta


func _solve_constraints() -> void:
	for _constraint_pass in CONSTRAINT_PASSES:
		_solve_stretch()
		_solve_shear()
		_solve_bend()
		_collide_torso()
		_solve_tethers()
		_pin_collar()
		_uncross_columns()
	_pin_collar()


func _solve_stretch() -> void:
	for row in ROWS:
		var rest := _across(row)
		var base := row * COLS
		for col in range(COLS - 1):
			_keep(base + col, base + col + 1, rest)
	for row in range(ROWS - 1):
		var base := row * COLS
		var below := base + COLS
		for col in COLS:
			_keep(base + col, below + col, _rest_len_col)


func _solve_shear() -> void:
	for row in range(ROWS - 1):
		var rest := Vector2((_across(row) + _across(row + 1)) * 0.5, _rest_len_col).length()
		var base := row * COLS
		var below := base + COLS
		for col in range(COLS - 1):
			_keep(base + col, below + col + 1, rest)
			_keep(base + col + 1, below + col, rest)


func _solve_bend() -> void:
	for row in ROWS:
		var rest := _across(row) * 2.0
		var base := row * COLS
		for col in range(COLS - 2):
			_keep(base + col, base + col + 2, rest, BEND_STIFF)
	for row in range(ROWS - 2):
		var base := row * COLS
		var skip := base + COLS * 2
		for col in COLS:
			_keep(base + col, skip + col, _rest_len_col * 2.0, BEND_STIFF)


func _solve_tethers() -> void:
	# Kim 2012 long-range attachments: a particle may not travel farther from
	# its collar pin than the sewn path. Unilateral, so the hem can still lift.
	for row in range(1, ROWS):
		var limit := _rest_len_col * float(row) * TETHER_SLACK
		var base := row * COLS
		for col in COLS:
			_tether(base + col, _pin_at(col), limit)


func _pin_collar() -> void:
	for col in COLS:
		var index := _index(col, 0)
		_pos[index] = _pin_at(col)
		_prev[index] = _pos[index]


func _keep(a: int, b: int, rest: float, stiffness := 1.0) -> void:
	var delta := _pos[b] - _pos[a]
	var distance := delta.length()
	if distance < 0.0001:
		var axis := _axis_back
		if axis.length_squared() < 0.0001:
			axis = Vector3.FORWARD
		_pos[b] = _pos[a] + axis * rest
		return
	var share := ((distance - rest) / distance) * stiffness
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


func _tether(index: int, anchor: Vector3, rest: float) -> void:
	var delta := _pos[index] - anchor
	var distance := delta.length()
	if distance <= rest or distance < 0.0001:
		return
	_pos[index] = anchor + delta * (rest / distance)


func _collide_torso() -> void:
	var back := _axis_back
	for row in range(1, ROWS):
		var base := row * COLS
		for col in COLS:
			var index := base + col
			var point := _pos[index]
			point = _push_sphere(point, _chest_center, TORSO_RADIUS)
			point = _push_sphere(point, _hip_center, HIP_RADIUS)
			var into := (point - _plane_point).dot(back)
			if into < 0.0:
				point -= back * into
			_pos[index] = point


func _uncross_columns() -> void:
	# Weft threads that pass each other read as a folded sheet. Keep each row
	# ordered along the shoulders with a fraction of the sewn spacing.
	var right := _axis_right
	if right.length_squared() < 0.0001:
		return
	for row in range(1, ROWS):
		var min_sep := _across(row) * MIN_COL_SEP
		var base := row * COLS
		for col in range(COLS - 1):
			var a := base + col
			var b := a + 1
			var along := (_pos[b] - _pos[a]).dot(right)
			if along >= min_sep:
				continue
			var fix := right * ((min_sep - along) * 0.5)
			_pos[a] -= fix
			_pos[b] += fix


func _push_sphere(point: Vector3, center: Vector3, radius: float) -> Vector3:
	var offset := point - center
	var distance := offset.length()
	if distance >= radius or distance < 0.0001:
		return point
	return center + offset * (radius / distance)


func _snap_to_body() -> void:
	_wind = Vector3.ZERO
	if _skeleton != null and is_instance_valid(_skeleton):
		_cache_pose()
	_pos.resize(COLS * ROWS)
	_prev.resize(COLS * ROWS)
	for row in ROWS:
		for col in COLS:
			var index := _index(col, row)
			var point := _drape_point(col, row)
			_pos[index] = point
			_prev[index] = point
	_commit_mesh()


func _pin_at(col: int) -> Vector3:
	if _pins.size() == COLS:
		return _pins[col]
	return _pin_world(col)


func _drape_point(col: int, row: int) -> Vector3:
	var row_t := float(row) / float(ROWS - 1)
	var col_t := float(col) / float(COLS - 1)
	var pin := _pin_at(col)
	var taper := 1.0 - row_t * TAPER
	var centered := (col_t - 0.5) * WIDTH * (taper - 1.0)
	return pin \
		+ _down() * (LENGTH * row_t) \
		+ _back() * (0.03 + 0.10 * row_t) \
		+ _right() * centered


func _fill_local_rest() -> void:
	_pos.resize(COLS * ROWS)
	_prev.resize(COLS * ROWS)
	for row in ROWS:
		var row_t := float(row) / float(ROWS - 1)
		var taper := 1.0 - row_t * TAPER
		for col in COLS:
			var col_t := float(col) / float(COLS - 1)
			var x := (col_t - 0.5) * WIDTH * taper
			var y := -LENGTH * row_t
			var z := 0.04 + 0.10 * row_t + sin(col_t * PI) * 0.03
			var index := _index(col, row)
			_pos[index] = Vector3(x, y, z)
			_prev[index] = _pos[index]


func _rest_row(row: int) -> float:
	var row_t := float(row) / float(ROWS - 1)
	return (WIDTH * (1.0 - row_t * TAPER)) / float(COLS - 1)


func _across(row: int) -> float:
	if row >= 0 and row < _rest_across.size():
		return _rest_across[row]
	return _rest_row(row)


func _build_mesh_shell() -> void:
	var count := COLS * ROWS
	_uvs.resize(count)
	_rest_across.resize(ROWS)
	for row in ROWS:
		_rest_across[row] = _rest_row(row)
		for col in COLS:
			_uvs[row * COLS + col] = Vector2(
				float(col) / float(COLS - 1), float(row) / float(ROWS - 1))
	_indices = PackedInt32Array()
	for row in range(ROWS - 1):
		for col in range(COLS - 1):
			var a := row * COLS + col
			var b := a + 1
			var c := a + COLS
			var d := c + 1
			_indices.append(a)
			_indices.append(b)
			_indices.append(d)
			_indices.append(a)
			_indices.append(d)
			_indices.append(c)


func _commit_mesh() -> void:
	var count := COLS * ROWS
	_vertices.resize(count)
	_normals.resize(count)
	var to_local := Transform3D.IDENTITY
	if is_inside_tree():
		to_local = global_transform.affine_inverse()
	for index in count:
		_vertices[index] = to_local * _pos[index]
		_normals[index] = Vector3.ZERO
	var stop := _indices.size()
	var cursor := 0
	while cursor < stop:
		var ia := _indices[cursor]
		var ib := _indices[cursor + 1]
		var ic := _indices[cursor + 2]
		var a := _vertices[ia]
		var b := _vertices[ib]
		var c := _vertices[ic]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 0.000001:
			normal = Vector3.BACK
		else:
			normal = normal.normalized()
		_normals[ia] += normal
		_normals[ib] += normal
		_normals[ic] += normal
		cursor += 3
	for index in count:
		if _normals[index].length_squared() > 0.000001:
			_normals[index] = _normals[index].normalized()
		else:
			_normals[index] = Vector3.BACK
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	if _array_mesh == null:
		_array_mesh = ArrayMesh.new()
	elif _array_mesh.get_surface_count() > 0:
		_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _array_mesh.get_surface_count() > 0:
		_array_mesh.surface_set_material(0, _material)
	_mesh.mesh = _array_mesh
	if _mesh.material_override == null:
		_mesh.material_override = _material


func _pin_world(col: int) -> Vector3:
	if _pins.size() == COLS:
		return _pins[col]
	_cache_pose()
	return _pin_at(col)


func _shoulder(root_name: StringName, arm_name: StringName) -> Vector3:
	return _shoulder_from(
		_read_bone(root_name),
		_read_bone(arm_name),
		String(root_name).begins_with("Left"))


func _shoulder_from(root: Vector3, arm: Vector3, left: bool) -> Vector3:
	if root == Vector3.ZERO:
		return _fallback_origin() + _right() * (-WIDTH * 0.5 if left else WIDTH * 0.5)
	if arm == Vector3.ZERO:
		return root
	return root.lerp(arm, 0.42)


func _bone_world(bone_name: StringName) -> Vector3:
	return _read_bone(bone_name)


func _read_bone(bone_name: StringName) -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return Vector3.ZERO
	var bone := int(_bone_ids.get(bone_name, -2))
	if bone == -2:
		bone = CharacterRig.find_bone(_skeleton, bone_name)
		_bone_ids[bone_name] = bone
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
	if _hips != Vector3.ZERO and _chest != Vector3.ZERO:
		var up := (_chest - _hips).normalized()
		if up.length_squared() > 0.01:
			return up
	return _basis_axis(1)


func _down() -> Vector3:
	return -_up()


func _right() -> Vector3:
	if _left_root != Vector3.ZERO and _right_root != Vector3.ZERO:
		var across := _right_root - _left_root
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
	if _head != Vector3.ZERO and _chest != Vector3.ZERO:
		var forward := _head - _chest
		forward -= up * forward.dot(up)
		if forward.length_squared() > 0.0004 and back.dot(forward.normalized()) > 0.0:
			back = -back
	return back


func _body_velocity() -> Vector3:
	if _body != null and is_instance_valid(_body):
		return _body.velocity
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
	if _gold:
		_material.metallic = 0.82
		_material.roughness = 0.22
		_material.emission_enabled = true
		_material.emission = cape_color
		_material.emission_energy_multiplier = 2.6 if _sparkle else 0.55
	else:
		_material.metallic = 0.0
		_material.roughness = 0.72
		_material.emission_enabled = false
		_material.emission_energy_multiplier = 1.0
