class_name CrawlerMulti
extends RefCounted

## Seated Multi Shot ranks, plus the per-host split geometry.


static func shots(stats: Dictionary) -> int:
	var listed := int(round(float(stats.get("multi", 0.0))))
	if listed <= 0:
		return 1
	return clampi(listed, 1, CrawlerRules.MULTI_SHOTS_MAX)


static func extras(stats: Dictionary) -> int:
	return maxi(shots(stats) - 1, 0)


static func yaw_degrees(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := clampi(count, 1, CrawlerRules.MULTI_SHOTS_MAX)
	if n <= 1:
		out.append(0.0)
		return out
	var span := CrawlerRules.MULTI_BEAM_YAW
	for index in n:
		out.append(lerpf(-span, span, float(index) / float(n - 1)))
	return out


static func rotate_yaw(along: Vector3, degrees: float, up: Vector3) -> Vector3:
	if along.length_squared() < 0.000001 or absf(degrees) <= 0.001:
		return along
	var length := along.length()
	var dir := along / length
	var axis := up
	if axis.length_squared() < 0.000001:
		axis = Vector3.UP
	axis = axis.normalized()
	if absf(dir.dot(axis)) > 0.98:
		axis = dir.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.000001:
			axis = dir.cross(Vector3.FORWARD)
		if axis.length_squared() < 0.000001:
			return along
		axis = axis.normalized()
	return dir.rotated(axis, deg_to_rad(degrees)) * length


static func fan_points(from: Vector3, at: Vector3, count: int,
		up: Vector3) -> PackedVector3Array:
	var along := at - from
	var points := PackedVector3Array()
	for yaw: float in yaw_degrees(count):
		points.append(from + rotate_yaw(along, yaw, up))
	return points


static func fan_dirs(along: Vector3, count: int, up: Vector3) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	var heading := along
	if heading.length_squared() < 0.000001:
		heading = Vector3.FORWARD
	for yaw: float in yaw_degrees(count):
		var turned := rotate_yaw(heading, yaw, up)
		if turned.length_squared() > 0.000001:
			dirs.append(turned.normalized())
	return dirs


static func wall_offsets(count: int, width: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := clampi(count, 1, CrawlerRules.MULTI_SHOTS_MAX)
	out.append(0.0)
	if n <= 1:
		return out
	var gap := maxf(width, 0.4) + CrawlerRules.MULTI_WALL_GAP
	for index in range(1, n):
		var step := (index + 1) / 2
		var side := 1.0 if (index & 1) == 1 else -1.0
		out.append(side * float(step) * gap)
	return out


static func punch_offsets(count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := clampi(count, 1, CrawlerRules.MULTI_SHOTS_MAX)
	for index in n:
		out.append(float(index) * CrawlerRules.MULTI_PUNCH_GAP)
	return out


static func up_of(node: Node) -> Vector3:
	if node is CharacterBody3D:
		var body := node as CharacterBody3D
		if body.up_direction.length_squared() > 0.0001:
			return body.up_direction.normalized()
	if node is Node3D:
		var along := (node as Node3D).global_transform.basis.y
		if along.length_squared() > 0.0001:
			return along.normalized()
	return Vector3.UP
