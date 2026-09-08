class_name AbilityDelayedBlast
extends Node3D

## One replicated patch in Nausicaä's painted trail. Only the host copy turns
## the one-second fuse into AbilityImpact; every copy draws the same blue glow
## and removes it on the authored deadline. A living follow target carries the
## mark until the fuse ends or the body is freed.

var source: OnlinePlayer
var definition: AbilityDefinition
var from := Vector3.ZERO
var at := Vector3.ZERO
var normal := Vector3.UP
var delay := 1.0
var simulates := false
var overlay: Dictionary = {}
var follow: Node

var _age := 0.0
var _detonated := false
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _lamp: OmniLight3D


static func create(world: Node, caster: OnlinePlayer,
		record: AbilityDefinition, beam_from: Vector3, landed_at: Vector3,
		surface_normal: Vector3, warning: float,
		host_simulates: bool, stats_overlay: Dictionary = {},
		follow_target: Node = null) -> AbilityDelayedBlast:
	if world == null or caster == null or record == null \
			or not beam_from.is_finite() or not landed_at.is_finite():
		return null
	var effect := AbilityDelayedBlast.new()
	effect.source = caster
	effect.definition = record
	effect.from = beam_from
	effect.at = landed_at
	effect.normal = surface_normal.normalized() \
		if surface_normal.length_squared() > 0.001 else caster.global_basis.y
	effect.delay = clampf(warning, 0.1, 5.0)
	effect.simulates = host_simulates
	effect.follow = follow_target if is_instance_valid(follow_target) else null
	if stats_overlay.is_empty() and caster.has_method(&"crawler_ability_overlay"):
		effect.overlay = caster.crawler_ability_overlay(record.ability_id)
	else:
		effect.overlay = stats_overlay.duplicate(true)
	effect._sync_follow()
	world.add_child(effect)
	return effect


func _ready() -> void:
	top_level = true
	var paint_radius := maxf(float(
		_stats().get("paint_radius", 0.8)), 0.1)
	_marker_material = _energy_material(definition.tint, 2.0, 0.58)
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = paint_radius
	marker_mesh.bottom_radius = paint_radius * 0.82
	marker_mesh.height = 0.035
	marker_mesh.radial_segments = 18
	marker_mesh.rings = 0
	marker_mesh.material = _marker_material
	_marker = MeshInstance3D.new()
	_marker.mesh = marker_mesh
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)

	_lamp = OmniLight3D.new()
	_lamp.light_color = definition.tint
	_lamp.light_energy = 2.2
	_lamp.omni_range = maxf(paint_radius * 3.2, 2.0)
	add_child(_lamp)
	_place_marker()


func _process(delta: float) -> void:
	_sync_follow()
	_place_marker()
	_age += delta
	var warning_share := clampf(_age / delay, 0.0, 1.0)
	var pulse := 0.4 + 0.6 * absf(sin(_age * lerpf(10.0, 30.0, warning_share)))
	var marker_colour := definition.tint
	marker_colour.a = lerpf(0.34, 0.92, warning_share) * pulse
	_marker_material.albedo_color = marker_colour
	_marker_material.emission_energy_multiplier = lerpf(
		1.4, 4.0, warning_share) * pulse
	_marker.scale = Vector3.ONE * lerpf(0.94, 1.08, pulse)
	_marker.scale.y = 1.0
	_lamp.light_energy = lerpf(1.2, 4.5, warning_share) * pulse
	if _age < delay or _detonated:
		return
	_detonated = true
	_sync_follow()
	if simulates and is_instance_valid(source):
		AbilityImpact.apply(source, definition, at, normal, overlay)
		CrawlerImpactCast.emit(
			source, definition.ability_id, at, normal, overlay)
	queue_free()


func _sync_follow() -> void:
	if follow == null:
		return
	if not is_instance_valid(follow):
		follow = null
		return
	var dest := CrawlerHoming.combat_at(follow)
	if dest.is_finite():
		at = dest


func _place_marker() -> void:
	if _marker == null:
		return
	var up := normal.normalized() if normal.length_squared() > 0.001 \
		else Vector3.UP
	var side := up.cross(
		Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9
		else Vector3.RIGHT).normalized()
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	_marker.global_transform = Transform3D(
		Basis(side, up, side.cross(up)).orthonormalized(),
		at + up * 0.035)
	if _lamp != null:
		_lamp.global_position = at + up * 0.18


func _stats() -> Dictionary:
	if overlay.is_empty() or definition == null:
		return definition.stats if definition != null else {}
	var merged := definition.stats.duplicate(true)
	merged.merge(overlay, true)
	return merged


func _energy_material(tint: Color, energy: float,
		alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(tint, alpha)
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material
