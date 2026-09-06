class_name CrawlerWardBubble
extends MeshInstance3D

## Thin iridescent shell worn with the city Ward Halo. Gameplay owns the
## one-hit clock; this node only draws the film, the pop, and the return.

const SHADER := preload("res://game/crawler/crawler_ward_bubble.gdshader")
const ICE := Color(0.82, 0.94, 1.0, 0.08)
const POP_SECONDS := 0.28

var _material: ShaderMaterial
var _up := false
var _pop_left := 0.0
var _phase := 0.0
var _rest_scale := Vector3.ONE


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if DisplayServer.get_name() == "headless":
		visible = false
		set_process(false)
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"shield_color", ICE)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 36
	sphere.rings = 20
	sphere.material = _material
	mesh = sphere
	visible = false
	set_process(false)


func fit_body(height: float, width := 0.88) -> void:
	position.y = height * 0.5
	_rest_scale = Vector3(
		maxf(width, 0.48),
		maxf(height * 0.78, 0.68),
		maxf(width, 0.48)
	)
	if _pop_left <= 0.0:
		scale = _rest_scale


func set_state(up: bool) -> void:
	if up and not _up:
		_pop_left = 0.0
	elif not up and _up:
		_pop_left = POP_SECONDS
	_up = up
	_apply()


func _process(delta: float) -> void:
	_phase += delta * 3.4
	_pop_left = maxf(_pop_left - delta, 0.0)
	_apply()
	if not _up and _pop_left <= 0.0:
		set_process(false)


func _apply() -> void:
	var popping := _pop_left > 0.0
	visible = _up or popping
	if _material == null:
		visible = false
		set_process(false)
		return
	var pop_share := 0.0
	if popping:
		pop_share = 1.0 - (_pop_left / POP_SECONDS)
	_material.set_shader_parameter(&"pop", clampf(pop_share, 0.0, 1.0))
	_material.set_shader_parameter(
		&"pulse",
		0.12 + 0.08 * (0.5 + 0.5 * sin(_phase)) if _up else 0.0
	)
	scale = _rest_scale * (1.0 + 0.22 * pop_share) if popping else _rest_scale
	set_process(_up or popping)
