class_name AbilityTrail
extends MeshInstance3D

## World-space ribbon that grows until the caller frees it. Used by Teleport so
## the white path stays until the orb lands instead of fading mid-flight.

const MIN_STEP := 0.18

var _points: PackedVector3Array = PackedVector3Array()
var _width := 0.08
var _immediate := ImmediateMesh.new()
var _up := Vector3.UP


static func create(world: Node, at: Vector3, width := 0.08,
		tint := Color.WHITE) -> AbilityTrail:
	if world == null or not at.is_finite():
		return null
	var trail := AbilityTrail.new()
	trail.name = "AbilityTrail"
	trail._width = maxf(width, 0.02)
	trail.mesh = trail._immediate
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(tint, 0.82)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 3.6
	trail.material_override = material
	world.add_child(trail)
	trail.top_level = true
	trail.global_position = Vector3.ZERO
	trail.add_point(at)
	return trail


func linger(seconds: float) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		queue_free()
		return
	get_tree().create_timer(seconds).timeout.connect(queue_free)


func add_point(at: Vector3) -> void:
	if not at.is_finite():
		return
	if not _points.is_empty() and _points[_points.size() - 1].distance_to(at) \
			< MIN_STEP:
		if _points.size() >= 2:
			_points[_points.size() - 1] = at
			_rebuild()
		return
	_points.append(at)
	if at.length_squared() > 0.01:
		_up = at.normalized()
	_rebuild()


func _rebuild() -> void:
	_immediate.clear_surfaces()
	if _points.size() < 2:
		return
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in _points.size():
		var at := _points[index]
		var ahead := _points[index + 1] if index + 1 < _points.size() \
			else at + (at - _points[index - 1])
		var along := ahead - at
		if along.length_squared() < 0.000001:
			along = Vector3.FORWARD
		var side := _up.cross(along.normalized())
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		side = side.normalized() * (_width * 0.5)
		_immediate.surface_add_vertex(at - side)
		_immediate.surface_add_vertex(at + side)
	_immediate.surface_end()
