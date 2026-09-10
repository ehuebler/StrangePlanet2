extends Node

## Placement and shader contract for energy spheres and beams.
##
##     godot --headless --path . dev/_energy_vfx_probe.tscn

var _failures := 0


func _ready() -> void:
	_check_beam_reaches_ends()
	_check_streams_are_centered()
	_check_projectile_is_centered()
	_check_ranger_orb()
	_check_laser_beams_reach_the_eyes()
	print("energy_vfx_probe: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_beam_reaches_ends() -> void:
	var effect := EnergyVfx.make(EnergyVfx.Kind.BEAM_CORE, EnergyVfx.TINT_RED)
	add_child(effect)
	_expect(effect.uses_glow_shader(),
		"core beam wears the fiery glow shader")
	_expect(_shader_fire(effect).r > _shader_fire(effect).g,
		"core beam fire follows the red tint")
	var from := Vector3(0.0, 1.8, 0.0)
	var to := Vector3(0.0, 1.8, -20.0)
	_expect(effect.place_beam(from, to, LaserBeams.RADIUS),
		"core beam accepts a twenty-metre span")
	var box := _world_aabb(effect)
	_expect(_covers(box, from, 0.45),
		"core beam starts at the muzzle, not the midpoint")
	_expect(_covers(box, to, 0.45),
		"core beam reaches the target instead of running past it")
	_expect(box.size.z > 18.0 and box.size.z < 22.0,
		"core beam length matches the shot (%.2f m)" % box.size.z)
	effect.queue_free()


func _check_streams_are_centered() -> void:
	var effect := EnergyVfx.make(EnergyVfx.Kind.BEAM_STREAMS, EnergyVfx.TINT_WHITE)
	add_child(effect)
	_expect(effect.uses_glow_shader(),
		"stream beam wears the fiery glow shader")
	_expect(_payload_origin(effect).length() < 0.01,
		"stream hull sits on the node")
	var from := Vector3.ZERO
	var to := Vector3(0.0, 0.0, -8.0)
	_expect(effect.place_beam(from, to, 0.2),
		"stream beam accepts an eight-metre span")
	var box := _world_aabb(effect)
	_expect(_covers(box, from, 0.55) and _covers(box, to, 0.55),
		"stream beam covers its from-to span")
	effect.set_opacity(CrawlerScout.POINTER_OPACITY)
	_expect(is_equal_approx(effect.current_opacity(), 0.4)
			and is_equal_approx(_shader_opacity(effect), 0.4),
		"stream beam can be sixty percent transparent")
	effect.queue_free()


func _check_projectile_is_centered() -> void:
	var effect := EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, EnergyVfx.TINT_BLUE)
	add_child(effect)
	_expect(effect.uses_glow_shader(),
		"projectile wears the fiery glow shader")
	_expect(_shader_fire(effect).b > _shader_fire(effect).r,
		"projectile fire follows the blue tint")
	_expect(_shader_core(effect).r + _shader_core(effect).g + _shader_core(effect).b
			> _shader_fire(effect).r + _shader_fire(effect).g + _shader_fire(effect).b,
		"projectile core is hotter than its fire")
	_expect(_payload_origin(effect).length() < 0.01,
		"projectile hull sits on the node")
	var box := _world_aabb(effect)
	_expect(box.get_center().length() < 0.35,
		"projectile mesh sits on the node, not three metres beside it")
	effect.queue_free()


func _check_ranger_orb() -> void:
	var shot := CrawlerRangerShot.new()
	add_child(shot)
	_expect(is_instance_valid(shot._core) and shot._core.uses_glow_shader(),
		"ranger orb wears the fiery glow shader")
	if is_instance_valid(shot._core):
		_expect(_shader_fire(shot._core).g > _shader_fire(shot._core).r,
			"ranger fire stays green")
		_expect(_shader_core(shot._core).r > 0.85,
			"ranger core is white-hot, not a green blob")
	shot.queue_free()


func _check_laser_beams_reach_the_eyes() -> void:
	var beams := LaserBeams.new()
	add_child(beams)
	var left := Vector3(-0.05, 1.8, 0.0)
	var right := Vector3(0.05, 1.8, 0.0)
	var at := Vector3(0.0, 1.8, -16.0)
	beams.aim(left, right, at, EnergyVfx.TINT_RED)
	_expect(not beams._beams.is_empty() and not beams._beams[0].is_empty(),
		"LaserBeams builds a core segment")
	if beams._beams.is_empty() or beams._beams[0].is_empty():
		return
	var drawn := beams._beams[0][0] as EnergyVfx
	var box := _world_aabb(drawn)
	_expect(drawn != null and drawn.visible and _covers(box, left, 0.5),
		"Laser Eyes beam is visible from the left eye")
	_expect(drawn != null and _covers(box, at, 0.5),
		"Laser Eyes beam reaches the look point")
	var along := (at - left).normalized()
	_expect(not _covers(box, left - along * 0.25, 0.02),
		"Laser Eyes beam does not start behind the head")
	beams.queue_free()


func _payload_origin(effect: EnergyVfx) -> Vector3:
	if effect._visual == null:
		return Vector3(INF, INF, INF)
	return effect._visual.position


func _shader_fire(effect: EnergyVfx) -> Color:
	return _shader_colour(effect, &"fire_color")


func _shader_core(effect: EnergyVfx) -> Color:
	return _shader_colour(effect, &"core_color")


func _shader_opacity(effect: EnergyVfx) -> float:
	if effect._glow_mat == null:
		return -1.0
	return float(effect._glow_mat.get_shader_parameter(&"opacity"))


func _shader_colour(effect: EnergyVfx, key: StringName) -> Color:
	if effect._glow_mat == null:
		return Color.BLACK
	var value: Variant = effect._glow_mat.get_shader_parameter(key)
	return value if value is Color else Color.BLACK


func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var started := false
	if root == null:
		return box
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var local := mesh.get_aabb()
		var xf := mesh.global_transform
		for index in 8:
			var corner := xf * local.get_endpoint(index)
			if not started:
				box = AABB(corner, Vector3.ZERO)
				started = true
			else:
				box = box.expand(corner)
	return box


func _covers(box: AABB, point: Vector3, slop: float) -> bool:
	return box.grow(slop).has_point(point)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("energy_vfx_probe failed: %s" % label)
