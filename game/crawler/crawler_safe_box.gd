class_name CrawlerSafeBox
extends Node3D

## Thick-walled shelter that appears after a city falls. Mobs cannot enter.
## The player heals inside and cannot use abilities. The box vanishes when
## they walk back out, which is also when the city counter ticks.

signal player_departed
signal occupancy_changed(inside: bool)

const GROUP := &"crawler_safe_zones"

var city_id := -1

var _inner := CrawlerRules.SAFE_BOX_INNER
var _wall := CrawlerRules.SAFE_BOX_WALL
var _height := CrawlerRules.SAFE_BOX_HEIGHT
var _opening := CrawlerRules.SAFE_BOX_OPENING
var _inside: Dictionary = {}
var _was_occupied := false
var _closing := false
var _interior: Area3D


func configure(id: int, at: Transform3D, inner := -1.0) -> void:
	city_id = id
	transform = at
	if inner > 0.0:
		_inner = inner


func _ready() -> void:
	add_to_group(GROUP)
	_build_shell()
	_build_interior()


func contains_player(player: Node) -> bool:
	if player == null:
		return false
	if _inside.has(player.get_instance_id()):
		return true
	return player is Node3D and contains_point((player as Node3D).global_position)


func contains_point(point: Vector3) -> bool:
	return _local_inside(to_local(point), false)


func blocks_point(point: Vector3) -> bool:
	return _local_inside(to_local(point), true)


func zone_centre() -> Vector3:
	return global_position


func push_out(point: Vector3, pad := 1.0) -> Vector3:
	var local := to_local(point)
	if not _local_inside(local, true):
		return point
	var half := _outer_half()
	var ax := absf(local.x) / maxf(half.x, 0.01)
	var ay := absf(local.y) / maxf(half.y, 0.01)
	var az := absf(local.z) / maxf(half.z, 0.01)
	if ax >= ay and ax >= az:
		local.x = signf(local.x) * (half.x + pad)
	elif ay >= az:
		local.y = signf(local.y) * (half.y + pad)
	else:
		local.z = signf(local.z) * (half.z + pad)
	return to_global(local)


static func contains_any(node: Node3D) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	for zone_variant: Variant in node.get_tree().get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerSafeBox
		if zone != null and zone.contains_player(node):
			return true
	return false


static func blocks_any(tree: SceneTree, point: Vector3) -> bool:
	if tree == null:
		return false
	for zone_variant: Variant in tree.get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerSafeBox
		if zone != null and zone.blocks_point(point):
			return true
	return false


func _build_shell() -> void:
	var half := _inner * 0.5
	var tall := _height
	var thick := _wall
	var door := minf(_opening, _inner - 0.8)
	var door_half := door * 0.5
	var door_height := minf(4.6, tall - 0.8)
	var lintel := tall - door_height
	var side := (_inner - door) * 0.5
	var colour := Color(0.12, 0.13, 0.16)
	_add_wall(Vector3(_inner + thick, thick, _inner + thick),
		Vector3(0.0, -tall * 0.5, 0.0), colour)
	_add_wall(Vector3(_inner + thick, thick, _inner + thick),
		Vector3(0.0, tall * 0.5, 0.0), colour)
	_add_wall(Vector3(thick, tall, _inner + thick),
		Vector3(-half - thick * 0.5, 0.0, 0.0), colour)
	_add_wall(Vector3(thick, tall, _inner + thick),
		Vector3(half + thick * 0.5, 0.0, 0.0), colour)
	_add_wall(Vector3(_inner + thick, tall, thick),
		Vector3(0.0, 0.0, -half - thick * 0.5), colour)
	if side > 0.05:
		_add_wall(Vector3(side, tall, thick),
			Vector3(-(door_half + side * 0.5), 0.0, half + thick * 0.5), colour)
		_add_wall(Vector3(side, tall, thick),
			Vector3(door_half + side * 0.5, 0.0, half + thick * 0.5), colour)
	if lintel > 0.05:
		_add_wall(Vector3(door, lintel, thick),
			Vector3(0.0, (tall - lintel) * 0.5, half + thick * 0.5), colour)


func _add_wall(size: Vector3, at: Vector3, colour: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.86
	visual.material_override = material
	body.add_child(visual)
	add_child(body)


func _build_interior() -> void:
	_interior = Area3D.new()
	_interior.collision_layer = 0
	_interior.collision_mask = 1
	_interior.monitoring = true
	_interior.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_inner - 0.2, _height - 0.3, _inner - 0.2)
	shape.shape = box
	_interior.add_child(shape)
	_interior.body_entered.connect(_on_body_entered)
	_interior.body_exited.connect(_on_body_exited)
	add_child(_interior)


func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	_inside[body.get_instance_id()] = body
	_was_occupied = true
	if body.has_method(&"cancel_combat_actions"):
		body.call(&"cancel_combat_actions")
	occupancy_changed.emit(true)


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	_inside.erase(body.get_instance_id())
	if not _inside.is_empty() or not _was_occupied or _closing:
		if _inside.is_empty():
			occupancy_changed.emit(false)
		return
	_closing = true
	occupancy_changed.emit(false)
	player_departed.emit()


func _is_player(body: Node) -> bool:
	return body != null and body.is_in_group(&"network_players")


func _outer_half() -> Vector3:
	return Vector3(_inner * 0.5 + _wall, _height * 0.5, _inner * 0.5 + _wall)


func _local_inside(local: Vector3, include_walls: bool) -> bool:
	var half := _outer_half() if include_walls \
		else Vector3(_inner * 0.5, _height * 0.5 - 0.1, _inner * 0.5)
	return absf(local.x) <= half.x and absf(local.y) <= half.y \
		and absf(local.z) <= half.z
