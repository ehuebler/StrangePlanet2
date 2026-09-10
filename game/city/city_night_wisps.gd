class_name CityNightWisps
extends Node3D

## Warm orange point-light wisps that drift through a crawler city after dark.
## The lights only exist while a living player is inside the ring, so empty
## cities stay cheap. Unlike [NightGroundGlow], the wash includes terrain.

const NODE_NAME := "NightWisps"
const WISP_COUNT := 14
const COLOR := Color(1.0, 0.62, 0.22)
const ENERGY := 16.0
const RANGE := 40.0
const ATTEN := 0.68
## Every visual layer, including planet terrain on layer two.
const CULL_MASK := 0xFFFFF
const INNER := 18.0
const LOFT_MIN := 0.85
const LOFT_MAX := 3.1
const EDGE_PAD := 7.0

## Below zero reads the planet sun. Tests set 0 or 1.
var night_override := -1.0

var _wisps: Array[Node3D] = []
var _homes: PackedVector3Array = PackedVector3Array()
var _phases: PackedVector3Array = PackedVector3Array()
var _rates: PackedVector3Array = PackedVector3Array()
var _spans: PackedVector3Array = PackedVector3Array()
var _pulses: PackedFloat32Array = PackedFloat32Array()
var _base_energy: PackedFloat32Array = PackedFloat32Array()
var _age := 0.0


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	_wisps.clear()


func _process(delta: float) -> void:
	_age += maxf(delta, 0.0)
	var night := night_amount()
	if _occupied() and night > 0.02:
		if _wisps.is_empty():
			_load()
		_drift()
		_apply(night)
	elif not _wisps.is_empty():
		_unload()


func advance(delta: float) -> void:
	_process(delta)


func night_amount() -> float:
	if night_override >= 0.0:
		return clampf(night_override, 0.0, 1.0)
	var planet := _planet()
	if planet == null or planet.sun == null or not is_inside_tree():
		return 0.0
	var up := (global_position - planet.global_position).normalized()
	if up.length_squared() < 0.01:
		up = global_transform.basis.y.normalized()
	var to_sun := planet.sun.global_basis.z.normalized()
	return 1.0 - smoothstep(-0.16, 0.12, up.dot(to_sun))


func wisp_count() -> int:
	return _wisps.size()


func omni_lights() -> Array[OmniLight3D]:
	var lights: Array[OmniLight3D] = []
	for wisp in _wisps:
		if wisp == null or not is_instance_valid(wisp):
			continue
		var lamp := wisp.get_node_or_null("Lamp") as OmniLight3D
		if lamp != null:
			lights.append(lamp)
	return lights


func _occupied() -> bool:
	var ring := get_parent() as CrawlerCityRing
	if ring == null or not is_inside_tree():
		return false
	for item: Variant in CrawlerCityRing.living_players(get_tree()):
		if ring.contains_player(item as Node):
			return true
	return false


func _load() -> void:
	_unload()
	var ring := get_parent() as CrawlerCityRing
	var radius := ring.radius() if ring != null else CrawlerRules.CITY_RING_RADIUS
	var seed_key := ring.city_key() if ring != null else "city"
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash(seed_key))
	_homes.resize(WISP_COUNT)
	_phases.resize(WISP_COUNT)
	_rates.resize(WISP_COUNT)
	_spans.resize(WISP_COUNT)
	_pulses.resize(WISP_COUNT)
	_base_energy.resize(WISP_COUNT)
	var outer := maxf(radius - EDGE_PAD, INNER + 4.0)
	for index in WISP_COUNT:
		var turn := float(index) * TAU * 0.61803398875 + rng.randf() * 0.35
		var reach := lerpf(INNER, outer,
			(float(index) + rng.randf()) / float(WISP_COUNT))
		_homes[index] = Vector3(
			sin(turn) * reach,
			lerpf(LOFT_MIN, LOFT_MAX, rng.randf()),
			-cos(turn) * reach)
		_phases[index] = Vector3(
			rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_rates[index] = Vector3(
			rng.randf_range(0.07, 0.16),
			rng.randf_range(0.05, 0.12),
			rng.randf_range(0.06, 0.15))
		_spans[index] = Vector3(
			rng.randf_range(5.5, 11.0),
			rng.randf_range(0.22, 0.65),
			rng.randf_range(5.5, 11.0))
		_pulses[index] = rng.randf_range(0.9, 1.7)
		_base_energy[index] = ENERGY * rng.randf_range(0.92, 1.18)
		var wisp := _make_wisp(index)
		wisp.position = _homes[index]
		add_child(wisp)
		_wisps.append(wisp)
	_drift()
	_apply(night_amount())


func _make_wisp(index: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Wisp_%d" % index
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = COLOR
	lamp.light_energy = 0.0
	lamp.omni_range = RANGE
	lamp.omni_attenuation = ATTEN
	lamp.light_size = 1.8
	lamp.light_specular = 0.22
	lamp.shadow_enabled = false
	lamp.light_cull_mask = CULL_MASK
	root.add_child(lamp)
	root.add_child(_orb("Core", 0.11, Color(1.0, 0.82, 0.42, 0.98), 14.0))
	var halo := COLOR
	halo.a = 0.55
	root.add_child(_orb("Halo", 0.42, halo, 6.5))
	return root


func _orb(orb_name: String, radius: float, tint: Color, emit: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = Color(tint.r, tint.g, tint.b)
	material.emission_energy_multiplier = emit
	var node := MeshInstance3D.new()
	node.name = orb_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _drift() -> void:
	var ring := get_parent() as CrawlerCityRing
	var radius := ring.radius() if ring != null else CrawlerRules.CITY_RING_RADIUS
	var limit := maxf(radius - 3.0, INNER)
	for index in _wisps.size():
		var wisp := _wisps[index]
		if wisp == null or not is_instance_valid(wisp):
			continue
		var phase := _phases[index]
		var rate := _rates[index]
		var span := _spans[index]
		var at := _homes[index] + Vector3(
			sin(_age * rate.x + phase.x) * span.x,
			sin(_age * rate.y + phase.y) * span.y,
			cos(_age * rate.z + phase.z) * span.z)
		var radial := Vector2(at.x, at.z)
		if radial.length() > limit:
			radial = radial.normalized() * limit
			at.x = radial.x
			at.z = radial.y
		at.y = clampf(at.y, LOFT_MIN, LOFT_MAX + 0.35)
		wisp.position = at


func _apply(night: float) -> void:
	var on := night > 0.02
	for index in _wisps.size():
		var wisp := _wisps[index]
		if wisp == null or not is_instance_valid(wisp):
			continue
		var lamp := wisp.get_node_or_null("Lamp") as OmniLight3D
		if lamp != null:
			var pulse := 0.86 + 0.14 * sin(_age * _pulses[index] + float(index))
			lamp.light_energy = _base_energy[index] * night * pulse if on else 0.0
			lamp.visible = lamp.light_energy > 0.02
		wisp.visible = on


func _unload() -> void:
	for wisp in _wisps:
		if wisp != null and is_instance_valid(wisp):
			wisp.free()
	_wisps.clear()
	_homes = PackedVector3Array()
	_phases = PackedVector3Array()
	_rates = PackedVector3Array()
	_spans = PackedVector3Array()
	_pulses = PackedFloat32Array()
	_base_energy = PackedFloat32Array()


func _planet() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		if walk is GameWorld:
			return (walk as GameWorld).planet()
		walk = walk.get_parent()
	return null
