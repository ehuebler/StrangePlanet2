class_name CrawlerBurst
extends Node3D

## Short, one-shot particle explosion. Death bursts throw several saturated
## colours at once; orb landings keep a tighter purple spray around the
## fireball.

const LIFE := 0.78
const DEATH_COLORS: PackedColorArray = [
	Color(1.00, 0.18, 0.30),
	Color(1.00, 0.58, 0.08),
	Color(0.98, 0.88, 0.14),
	Color(0.16, 0.90, 0.36),
	Color(0.16, 0.64, 1.00),
	Color(0.74, 0.26, 1.00),
]
const ORB_COLORS: PackedColorArray = [
	Color(0.96, 0.78, 1.00),
	Color(0.72, 0.22, 1.00),
	Color(0.42, 0.08, 0.95),
	Color(1.00, 0.42, 0.86),
]

var _size := 2.4
var _up := Vector3.UP
var _colors: PackedColorArray = DEATH_COLORS
var _age := 0.0
var _puffs: Array[GPUParticles3D] = []
var _light: OmniLight3D


static func death(world: Node, at: Vector3, up := Vector3.UP, size := 2.4,
		_kind := "") -> CrawlerBurst:
	return play(world, at, up, size, DEATH_COLORS)


static func orb(world: Node, at: Vector3, up := Vector3.UP, size := 1.8) -> CrawlerBurst:
	return play(world, at, up, size, ORB_COLORS)


static func play(world: Node, at: Vector3, up: Vector3, size: float,
		colors: PackedColorArray) -> CrawlerBurst:
	if world == null or not at.is_finite():
		return null
	var burst := CrawlerBurst.new()
	burst.name = "CrawlerBurst"
	burst._size = clampf(size, 0.8, 8.0)
	burst._up = up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	burst._colors = colors if not colors.is_empty() else DEATH_COLORS
	world.add_child(burst)
	burst.global_position = at
	return burst


func colors() -> PackedColorArray:
	return _colors


func puff_count() -> int:
	return _puffs.size()


func _ready() -> void:
	_build_puffs()
	_light = OmniLight3D.new()
	_light.light_color = _colors[0] if not _colors.is_empty() else Color.WHITE
	_light.light_energy = 6.4
	_light.omni_range = maxf(_size * 4.2, 5.0)
	_light.shadow_enabled = false
	add_child(_light)
	for puff in _puffs:
		puff.restart()
		puff.emitting = true


func _process(delta: float) -> void:
	_age += delta
	if _light != null:
		_light.light_energy = 6.4 * pow(1.0 - clampf(_age / LIFE, 0.0, 1.0), 1.6)
	if _age >= LIFE:
		queue_free()


func _build_puffs() -> void:
	var mesh := _spark_mesh()
	var fade := _fade()
	for index in _colors.size():
		var tint := _colors[index]
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process.emission_sphere_radius = clampf(_size * 0.16, 0.12, 1.1)
		process.direction = _up
		process.spread = 180.0
		process.initial_velocity_min = 3.4 + _size * 0.9
		process.initial_velocity_max = 8.2 + _size * 1.8
		process.gravity = -_up * 7.5
		process.damping_min = 0.6
		process.damping_max = 1.8
		process.scale_min = 0.22
		process.scale_max = 0.62
		process.color = tint
		process.color_ramp = fade
		process.hue_variation_min = -0.04
		process.hue_variation_max = 0.04
		var puff := GPUParticles3D.new()
		puff.name = "BurstPuff%d" % index
		puff.amount = clampi(10 + int(_size * 3.0), 10, 22)
		puff.lifetime = LIFE * 0.92
		puff.one_shot = true
		puff.explosiveness = 1.0
		puff.randomness = 0.55
		puff.local_coords = false
		puff.fixed_fps = 30
		puff.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
		puff.visibility_aabb = AABB(
			Vector3.ONE * -18.0, Vector3.ONE * 36.0)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.process_material = process
		puff.draw_pass_1 = mesh
		puff.emitting = false
		add_child(puff)
		_puffs.append(puff)


func _spark_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	mesh.material = material
	return mesh


func _fade() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color.WHITE,
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
