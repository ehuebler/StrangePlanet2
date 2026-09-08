class_name CombatantFlashOverlay
extends MeshInstance3D

## Transient unshaded red shell drawn over one [MeshInstance3D].

var _left := 0.0
var _duration := 0.35
var _peak := 0.62
var _material: StandardMaterial3D


func setup(
		source: MeshInstance3D,
		duration: float,
		peak: float,
		color := Color(0.95, 0.08, 0.06)
	) -> void:
	if source == null:
		queue_free()
		return
	mesh = source.mesh
	skin = source.skin
	transform = Transform3D.IDENTITY
	var skeleton_node := source.get_node_or_null(source.skeleton) \
		if not source.skeleton.is_empty() else null
	if skeleton_node != null:
		skeleton = get_path_to(skeleton_node)
	_duration = maxf(duration, 0.01)
	_peak = clampf(peak, 0.0, 1.0)
	_left = _duration
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A grown shell over a closed mesh only ever shows its outside, and drawing
	# both faces doubled a skinned transparent pass that is retriggered on every
	# tick of sustained fire.
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.albedo_color = Color(color.r, color.g, color.b, _peak)
	# Lift the shell a few millimetres so it does not z-fight the source mesh.
	_material.grow = true
	_material.grow_amount = 0.006
	material_override = _material
	set_process(true)


func retrigger(color := Color.TRANSPARENT) -> void:
	_left = _duration
	if _material != null:
		if color.a > 0.0:
			_material.albedo_color = Color(color.r, color.g, color.b, _peak)
		else:
			_material.albedo_color.a = _peak
	set_process(true)


func _process(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	var share := _left / _duration
	if _material != null:
		_material.albedo_color.a = _peak * share * share
	if _left <= 0.0:
		queue_free()
