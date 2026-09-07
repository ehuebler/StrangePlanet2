class_name CrawlerDemonColumn
extends Node3D

## Vertical shock cylinder dropped by a Threnody. Hurts players the way a
## static field hurts mobs: a full first tick, then a 4 Hz drip, plus shock.

const GROUP := &"crawler_demon_columns"
const TICK_HZ := 4.0
const TICK_STEP := 1.0 / TICK_HZ
const BASE_ALPHA := 0.48
const TINT := Color(0.72, 0.22, 0.95)


var reach := 7.5
var height := 28.0
var duration := 6.0
var damage := 20.0
var authoritative := true
var source_path := NodePath()

var _age := 0.0
var _since_tick := 0.0
var _inside: Dictionary = {}
var _material: StandardMaterial3D
var _visual: MeshInstance3D
var _up_axis := Vector3.UP


static func place(host: Node, source: CrawlerMob, at: Vector3, radius: float,
		column_damage: float, hold: float, column_height := 0.0) -> CrawlerDemonColumn:
	if host == null or not at.is_finite():
		return null
	var column := CrawlerDemonColumn.new()
	column.name = "ThrenodyColumn"
	column.reach = clampf(radius, 5.0, 10.0)
	column.damage = maxf(column_damage, 0.0)
	column.duration = clampf(hold, 0.4, 40.0)
	column.height = maxf(column_height, CrawlerRules.THRENODY_COLUMN_HEIGHT)
	column.authoritative = true
	if source != null:
		column.source_path = source.get_path()
		column._up_axis = source._up()
	host.add_child(column)
	column.global_position = at
	column._align_up()
	return column


func remaining() -> float:
	return maxf(duration - _age, 0.0)


func contains(at: Vector3, pad := 0.0) -> bool:
	if not at.is_finite() or remaining() <= 0.0:
		return false
	var local := to_local(at)
	if local.y < -pad or local.y > height + pad:
		return false
	return Vector2(local.x, local.z).length() <= reach + pad


func tick_now() -> void:
	_tick_inside()


func _ready() -> void:
	top_level = true
	add_to_group(GROUP)
	set_process(true)
	set_physics_process(true)
	_align_up()
	if DisplayServer.get_name() == "headless":
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(TINT, BASE_ALPHA)
	_material.emission_enabled = true
	_material.emission = TINT
	_material.emission_energy_multiplier = 2.2
	_material.disable_receive_shadows = true
	var shaft := CylinderMesh.new()
	shaft.top_radius = 1.0
	shaft.bottom_radius = 1.0
	shaft.height = 1.0
	shaft.radial_segments = 20
	var visual := MeshInstance3D.new()
	visual.name = "ColumnMesh"
	visual.mesh = shaft
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.position.y = 0.5
	add_child(visual)
	_visual = visual
	_draw()


func _process(delta: float) -> void:
	_age += delta
	_draw()
	if _age >= duration:
		queue_free()


func _physics_process(delta: float) -> void:
	if not authoritative:
		return
	_since_tick += delta
	if _since_tick < TICK_STEP:
		return
	_since_tick -= TICK_STEP
	_tick_inside()


func _align_up() -> void:
	var up := _up_axis
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	up = up.normalized()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.0001:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := east.cross(up).normalized()
	global_transform.basis = Basis(east, up, north)


func _draw() -> void:
	if _visual == null or _material == null:
		return
	_visual.scale = Vector3(reach, height, reach)
	_visual.position.y = height * 0.5
	var fade := BASE_ALPHA
	if duration > 0.0 and _age > duration * 0.7:
		fade = BASE_ALPHA * clampf(1.0 - (_age - duration * 0.7) / (duration * 0.3), 0.0, 1.0)
	_material.albedo_color = Color(TINT, fade)
	_material.emission_energy_multiplier = 1.2 + fade * 2.4


func _tick_inside() -> void:
	if not is_inside_tree():
		return
	var seen: Dictionary = {}
	for node_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		_try_hit(node_variant as Node, seen)
	for key_variant: Variant in _inside.keys():
		if not seen.has(key_variant):
			_inside.erase(key_variant)


func _try_hit(combatant: Node, seen: Dictionary) -> void:
	if combatant == null or not combatant.has_method(&"apply_damage"):
		return
	if combatant.has_method(&"is_dead") and bool(combatant.call(&"is_dead")):
		return
	if combatant.has_method(&"combat_faction") \
			and int(combatant.call(&"combat_faction")) != DamageHit.Faction.PLAYER:
		return
	var point := global_position
	if combatant.has_method(&"combat_position"):
		point = combatant.call(&"combat_position")
	elif combatant is Node3D:
		point = (combatant as Node3D).global_position
	var bounds := 0.4
	if combatant.has_method(&"combat_radius"):
		bounds = float(combatant.call(&"combat_radius"))
	var key := combatant.get_instance_id()
	if not contains(point, bounds):
		_inside.erase(key)
		return
	seen[key] = true
	var first := not _inside.has(key)
	_inside[key] = true
	var amount := damage if first else damage * TICK_STEP
	var hit := DamageHit.cylinder(
		global_position, global_position + _up_axis.normalized() * height,
		reach, amount)
	hit.faction = DamageHit.Faction.ENEMY
	hit.ability_id = "crawler_threnody_column"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.with_status(CombatStatuses.SHOCK, CrawlerRules.FIELD_SHOCK)
	var source := _source()
	if source != null:
		hit.set_source(source)
		if source.has_method(&"outgoing_faction"):
			hit.faction = int(source.call(&"outgoing_faction"))
	if combatant.has_method(&"combat_peer_id"):
		hit.target_peer = int(combatant.call(&"combat_peer_id"))
	combatant.call(&"apply_damage", hit)


func _source() -> Node:
	if source_path.is_empty() or not is_inside_tree():
		return null
	return get_node_or_null(source_path)
