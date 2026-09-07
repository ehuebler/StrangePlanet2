class_name AbilityBarrier
extends AnimatableBody3D

## Indestructible layer-one collision with a locally animated translucent shell.
## Lifetime is replicated at spawn; GameWorld also snapshots the remaining time
## for peers that join while a wall is still standing. Optional extras turn the
## slab into a moving wall, a damaging firewall, or a house around the caster.

signal expired(construct_id: int)

const FIRE_HZ := 4.0
const FIRE_STEP := 1.0 / FIRE_HZ
const DOOR_WIDTH := 2.0
const DOOR_HEIGHT := 2.6

var construct_id := 0
var owner_peer := 0
var ability_id := "wall"
var _size := Vector3(8.0, 4.0, 0.35)
var _duration := 7.0
var _fade_duration := 4.0
var _age := 0.0
var _tint := Color(0.27, 0.69, 1.0)
var _initial_alpha := 0.52
var _material: StandardMaterial3D
var _materials: Array[StandardMaterial3D] = []
var _collision: CollisionShape3D
var _panel_count := 1
var _house := false
var _project_speed := 0.0
var _project_along := Vector3.ZERO
var _firewall := 0.0
var _since_fire := 0.0
var _burn_areas: Array[Area3D] = []
var _inner := Vector3.ZERO


static func create(world: Node, id: int, source_peer: int,
		at: Transform3D, size: Vector3, duration: float,
		fade_duration: float, tint: Color,
		initial_alpha := 0.52, extras: Dictionary = {}) -> AbilityBarrier:
	if world == null or id <= 0 or not at.is_finite() or not size.is_finite():
		return null
	var barrier := AbilityBarrier.new()
	barrier.name = "AbilityWall_%d" % id
	barrier.construct_id = id
	barrier.owner_peer = maxi(source_peer, 0)
	barrier.ability_id = str(extras.get("ability_id", "wall"))
	barrier._size = Vector3(
		maxf(size.x, 0.2), maxf(size.y, 0.2), maxf(size.z, 0.05))
	barrier._duration = clampf(duration, 0.2, 30.0)
	barrier._fade_duration = clampf(
		fade_duration, 0.0, barrier._duration)
	barrier._tint = tint
	barrier._initial_alpha = clampf(initial_alpha, 0.0, 0.52)
	barrier._house = bool(extras.get("house", false))
	barrier._project_speed = maxf(float(extras.get("project_speed", 0.0)), 0.0)
	var along: Variant = extras.get("project_along", Vector3.ZERO)
	if along is Vector3 and (along as Vector3).is_finite():
		barrier._project_along = (along as Vector3)
		if barrier._project_along.length_squared() > 0.0001:
			barrier._project_along = barrier._project_along.normalized()
	barrier._firewall = maxf(float(extras.get("firewall", 0.0)), 0.0)
	if barrier._firewall > 0.0:
		barrier._tint = barrier._tint.lerp(Color(1.0, 0.32, 0.08), 0.58)
	world.add_child(barrier)
	barrier.global_transform = at
	return barrier


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	sync_to_physics = true
	add_to_group(&"ability_barriers")
	if _house:
		_build_house()
	else:
		_add_panel(_size, Vector3.ZERO, true)
		_panel_count = 1
	if _project_speed > 0.001 or _firewall > 0.001:
		set_physics_process(true)
	else:
		set_physics_process(false)


func _process(delta: float) -> void:
	_age += delta
	var fade_start := _duration - _fade_duration
	var alpha := _initial_alpha
	if _fade_duration > 0.0 and _age > fade_start:
		var share := clampf(
			(_age - fade_start) / _fade_duration, 0.0, 1.0)
		alpha = _initial_alpha * pow(1.0 - share, 1.35)
	var colour := _tint
	colour.a = alpha
	for material: StandardMaterial3D in _materials:
		material.albedo_color = colour
		material.emission_energy_multiplier = 0.7 + alpha * 2.2
	if _age < _duration:
		return
	for child: Node in get_children():
		var shape := child as CollisionShape3D
		if shape != null:
			shape.set_deferred(&"disabled", true)
	expired.emit(construct_id)
	queue_free()


func _physics_process(delta: float) -> void:
	if _project_speed > 0.001 and _project_along.length_squared() > 0.0001:
		global_position += _project_along * _project_speed * delta
		if _house:
			_carry_owner()
	if _firewall <= 0.001:
		return
	_since_fire += delta
	if _since_fire < FIRE_STEP:
		return
	_since_fire -= FIRE_STEP
	_burn_touching()


func remaining() -> float:
	return maxf(_duration - _age, 0.0)


func fade_duration() -> float:
	return minf(_fade_duration, remaining())


func size() -> Vector3:
	return _size


func tint() -> Color:
	return _tint


func current_alpha() -> float:
	return _material.albedo_color.a if _material != null else _initial_alpha


func is_house() -> bool:
	return _house


func project_speed() -> float:
	return _project_speed


func firewall_damage() -> float:
	return _firewall


func panel_count() -> int:
	return _panel_count


func extras() -> Dictionary:
	return {
		"ability_id": ability_id,
		"house": _house,
		"project_speed": _project_speed,
		"project_along": _project_along,
		"firewall": _firewall,
	}


func _build_house() -> void:
	var inner := maxf(_size.x, 2.4)
	var tall := maxf(_size.y, 2.4)
	var thick := maxf(_size.z, 0.08)
	_inner = Vector3(inner, tall, inner)
	var half := inner * 0.5
	var door := minf(DOOR_WIDTH, inner - 0.9)
	var door_half := door * 0.5
	var door_h := minf(DOOR_HEIGHT, tall - 0.7)
	var lintel := tall - door_h
	var side := (inner - door) * 0.5
	_add_panel(Vector3(inner + thick, thick, inner + thick),
		Vector3(0.0, -tall * 0.5, 0.0), false)
	_add_panel(Vector3(inner + thick, thick, inner + thick),
		Vector3(0.0, tall * 0.5, 0.0), false)
	_add_panel(Vector3(thick, tall, inner + thick),
		Vector3(-half - thick * 0.5, 0.0, 0.0), true)
	_add_panel(Vector3(thick, tall, inner + thick),
		Vector3(half + thick * 0.5, 0.0, 0.0), true)
	_add_panel(Vector3(inner + thick, tall, thick),
		Vector3(0.0, 0.0, half + thick * 0.5), true)
	if side > 0.05:
		_add_panel(Vector3(side, tall, thick),
			Vector3(-(door_half + side * 0.5), 0.0, -half - thick * 0.5), true)
		_add_panel(Vector3(side, tall, thick),
			Vector3(door_half + side * 0.5, 0.0, -half - thick * 0.5), true)
	if lintel > 0.05:
		_add_panel(Vector3(door, lintel, thick),
			Vector3(0.0, (tall - lintel) * 0.5, -half - thick * 0.5), true)
	_panel_count = 5 + (2 if side > 0.05 else 0) + (1 if lintel > 0.05 else 0)


func _add_panel(panel: Vector3, at: Vector3, burns: bool) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = panel
	shape.shape = box
	shape.position = at
	add_child(shape)
	if _collision == null:
		_collision = shape

	var mesh := BoxMesh.new()
	mesh.size = panel
	var material := _make_material()
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	if burns and _firewall > 0.001:
		_add_burn_area(panel, at)


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(_tint, _initial_alpha)
	material.emission_enabled = true
	material.emission = _tint
	material.emission_energy_multiplier = 1.8
	material.disable_receive_shadows = true
	_materials.append(material)
	if _material == null:
		_material = material
	return material


func _add_burn_area(panel: Vector3, at: Vector3) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	area.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = panel + Vector3.ONE * 0.16
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	_burn_areas.append(area)


func _burn_touching() -> void:
	var owner := _owner_player()
	if owner == null:
		return
	var seen: Dictionary = {}
	for area: Area3D in _burn_areas:
		if area == null or not is_instance_valid(area):
			continue
		for body: Node3D in area.get_overlapping_bodies():
			if body == null or seen.has(body.get_instance_id()):
				continue
			if body == owner or body == self:
				continue
			if not body.has_method(&"apply_damage") \
					or not body.has_method(&"combat_faction"):
				continue
			seen[body.get_instance_id()] = true
			var hit := DamageHit.area(
				body.global_position, 0.9, _firewall * FIRE_STEP)
			hit.ability_id = ability_id
			hit.faction = owner.combat_faction()
			hit.set_source(owner, owner.peer_id)
			var overlay: Dictionary = {}
			if owner.has_method(&"crawler_ability_overlay"):
				overlay = owner.crawler_ability_overlay(ability_id)
			CrawlerElements.stamp(hit, owner, ability_id, overlay, true, FIRE_STEP)
			DamageHit.apply_to_world(owner, hit)


func _carry_owner() -> void:
	var owner := _owner_player()
	if owner == null or not owner.has_method(&"apply_construct_carry"):
		return
	if not _contains_owner(owner):
		return
	owner.call(&"apply_construct_carry", _project_along * _project_speed)


func _contains_owner(owner: Node3D) -> bool:
	var local := to_local(owner.global_position)
	if _house and _inner.length_squared() > 0.001:
		var pad := Vector3(0.35, 0.45, 0.35)
		return absf(local.x) <= _inner.x * 0.5 + pad.x \
			and absf(local.y) <= _inner.y * 0.5 + pad.y \
			and absf(local.z) <= _inner.z * 0.5 + pad.z
	return absf(local.x) <= _size.x * 0.6 \
		and absf(local.y) <= _size.y * 0.6 \
		and absf(local.z) <= _size.z * 0.8 + 0.8


func _owner_player() -> OnlinePlayer:
	var world := get_tree()
	if world == null:
		return null
	for node: Node in world.get_nodes_in_group(&"network_players"):
		var player := node as OnlinePlayer
		if player != null and player.peer_id == owner_peer:
			return player
	var parent := get_parent()
	if parent != null:
		for child: Node in parent.get_children():
			var player := child as OnlinePlayer
			if player != null and player.peer_id == owner_peer:
				return player
	return null
