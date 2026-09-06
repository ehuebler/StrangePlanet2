extends Node3D

## Bright blue orb and wash around a crawler arriving on the pad.

const LIFE := 1.05
const COLOR := Color(0.22, 0.72, 1.0)
const SCRIPT := preload("res://game/crawler/crawler_arrival_flash.gd")

var _age := 0.0
var _light: OmniLight3D
var _core: MeshInstance3D
var _shell: MeshInstance3D
var _core_material: StandardMaterial3D
var _shell_material: StandardMaterial3D


static func play(world: Node, at: Vector3, _up := Vector3.UP) -> Node3D:
	if world == null or not at.is_finite():
		return null
	var existing := world.get_node_or_null("CrawlerArrivalFlash")
	if existing != null:
		existing.queue_free()
	var flash := SCRIPT.new()
	flash.name = "CrawlerArrivalFlash"
	world.add_child(flash)
	flash.global_position = at
	return flash


func tint() -> Color:
	return COLOR


func _ready() -> void:
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 36.0
	_light.omni_range = 16.0
	_light.shadow_enabled = false
	_light.light_specular = 0.0
	add_child(_light)
	_core_material = _glow(Color(0.72, 0.92, 1.0), 0.95)
	_core = _orb("Core", _core_material, 0.42)
	_shell_material = _glow(COLOR, 0.72)
	_shell = _orb("Shell", _shell_material, 0.95)
	_build_sparks()


func _process(delta: float) -> void:
	_age += delta
	var share := clampf(_age / LIFE, 0.0, 1.0)
	var fade := pow(1.0 - share, 1.25)
	var punch := 1.0 - pow(share, 0.35)
	if _light != null:
		_light.light_energy = 36.0 * fade
		_light.omni_range = lerpf(10.0, 18.0, share)
	if _core != null:
		_core.scale = Vector3.ONE * lerpf(0.85, 1.55, punch)
	if _shell != null:
		_shell.scale = Vector3.ONE * lerpf(0.7, 3.8, sqrt(share))
	if _core_material != null:
		_core_material.albedo_color.a = 0.95 * fade
		_core_material.emission_energy_multiplier = 10.0 * fade
	if _shell_material != null:
		_shell_material.albedo_color.a = 0.72 * fade
		_shell_material.emission_energy_multiplier = 6.0 * fade
	if _age >= LIFE:
		queue_free()


func _orb(orb_name: String, material: Material, radius: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = orb_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _glow(tint: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 8.0
	material.disable_receive_shadows = true
	return material


func _build_sparks() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.28
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 2.2
	process.initial_velocity_max = 6.4
	process.gravity = Vector3.ZERO
	process.damping_min = 1.2
	process.damping_max = 2.8
	process.scale_min = 0.18
	process.scale_max = 0.42
	process.color = COLOR
	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.amount = 28
	sparks.lifetime = LIFE * 0.85
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.local_coords = false
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.process_material = process
	sparks.draw_pass_1 = _spark_mesh()
	add_child(sparks)
	sparks.restart()
	sparks.emitting = true


func _spark_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.55, 0.88, 1.0, 1.0)
	material.disable_receive_shadows = true
	mesh.material = material
	return mesh
