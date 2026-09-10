class_name CrawlerTreeBushel
extends Node3D

## One removable foliage chunk on The Giving Tree.

signal destroyed(bushel: Node)

const GROUP := &"giving_tree_bushels"

var bushel_id := ""
var _health := 75.0
var _maximum := 75.0
var _alive := true
var _mesh: MeshInstance3D
var _flash := 0.0
var _base_color := Color.WHITE
var _paint: StandardMaterial3D
var _hitbox: StaticBody3D
var _sense_frame := -1
var _sense_box := AABB()
var _sense_at := Vector3.ZERO
var _sense_radius := 3.2
## World geometry stays on layer 1 so the player can walk under the canopy.
## Beams and projectiles still see this layer.
const HIT_LAYER := 4


func configure(id: String, mesh: MeshInstance3D, hp: float) -> void:
	bushel_id = id
	_mesh = mesh
	_maximum = clampf(hp, 50.0, 100.0)
	_health = _maximum
	_bind_paint()


func _ready() -> void:
	add_to_group(DamageHit.COMBATANT_GROUP)
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_bind_paint()
	_bind_hitbox()


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	if _mesh == null or not _alive:
		return
	var hurt := 1.0 - clampf(_health / maxf(_maximum, 1.0), 0.0, 1.0)
	_tint(maxf(hurt * 0.85, _flash / 0.18))


func combat_faction() -> int:
	return DamageHit.Faction.ENEMY


func combat_peer_id() -> int:
	return 0


func combat_display_name() -> String:
	return "Leaf Bushel"


func combat_position() -> Vector3:
	_refresh_sense()
	return _sense_at


func combat_radius() -> float:
	_refresh_sense()
	return _sense_radius


func combat_aabb() -> AABB:
	_refresh_sense()
	if _sense_box.size.length_squared() > 0.0001:
		return _sense_box
	var half := _sense_radius
	return AABB(_sense_at - Vector3.ONE * half, Vector3.ONE * (half * 2.0))


func health() -> float:
	return _health


func maximum_health() -> float:
	return _maximum


func is_alive() -> bool:
	return _alive


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _alive:
		return 0.0
	if hit.faction != DamageHit.Faction.PLAYER:
		return 0.0
	var actual := minf(maxf(hit.amount, 0.0) if is_finite(hit.amount) else 0.0, _health)
	if actual <= 0.0:
		return 0.0
	_health -= actual
	_flash = 0.18
	if _mesh != null:
		CombatantFlash.flash(_mesh)
	if _health <= 0.0:
		_die()
	return actual


func restore() -> void:
	_alive = true
	_health = _maximum
	_flash = 0.0
	visible = true
	if _mesh != null:
		_mesh.visible = true
	_tint(0.0)
	_set_hitbox(true)
	if not is_in_group(DamageHit.COMBATANT_GROUP):
		add_to_group(DamageHit.COMBATANT_GROUP)


func _die() -> void:
	if not _alive:
		return
	_alive = false
	_health = 0.0
	if _mesh != null:
		_mesh.visible = false
	visible = false
	_set_hitbox(false)
	remove_from_group(DamageHit.COMBATANT_GROUP)
	var world := DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	CrawlerBurst.leaves(world, combat_position(), _up(), maxf(combat_radius() * 1.6, 2.8))
	destroyed.emit(self)


func _bind_paint() -> void:
	if _mesh == null:
		return
	if _paint != null:
		return
	var source := _mesh.get_active_material(0)
	if source is StandardMaterial3D:
		_paint = (source as StandardMaterial3D).duplicate()
		_base_color = _paint.albedo_color
	else:
		_paint = StandardMaterial3D.new()
		_paint.albedo_color = Color(0.22, 0.58, 0.16)
		_base_color = _paint.albedo_color
	_mesh.material_override = _paint


func _tint(amount: float) -> void:
	_bind_paint()
	if _paint == null:
		return
	var pulse := clampf(amount, 0.0, 1.0)
	var red := Color(1.0, 0.16, 0.08)
	_paint.albedo_color = _base_color.lerp(red, pulse)
	_paint.emission_enabled = pulse > 0.04
	_paint.emission = red
	_paint.emission_energy_multiplier = 2.8 * pulse


func _refresh_sense() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _sense_frame:
		return
	_sense_frame = frame
	_sense_box = _world_bounds()
	if _sense_box.size.length_squared() > 0.0001:
		_sense_at = _sense_box.get_center()
		_sense_radius = maxf(
			maxf(_sense_box.size.x, _sense_box.size.y), _sense_box.size.z) * 0.5
		return
	_sense_at = _mesh.global_position if _mesh != null else global_position
	_sense_radius = 3.2


func _world_bounds() -> AABB:
	if _mesh == null or _mesh.mesh == null:
		return AABB()
	return _mesh.global_transform * _mesh.mesh.get_aabb()


func _bind_hitbox() -> void:
	if _hitbox != null or _mesh == null or _mesh.mesh == null:
		return
	var box := _mesh.mesh.get_aabb()
	if box.size.length_squared() < 0.0001:
		return
	_hitbox = StaticBody3D.new()
	_hitbox.name = "BushelHit"
	_hitbox.collision_layer = HIT_LAYER
	_hitbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box.size
	shape.shape = hull
	shape.position = box.get_center()
	_hitbox.add_child(shape)
	# Child of this bushel, which sits on the foliage mesh. Mesh-local AABB
	# offsets stay valid, and projectiles can walk the collider to this node.
	add_child(_hitbox)


func _set_hitbox(on: bool) -> void:
	if _hitbox == null:
		_bind_hitbox()
	if _hitbox != null:
		_hitbox.collision_layer = HIT_LAYER if on else 0
		_hitbox.process_mode = Node.PROCESS_MODE_INHERIT if on \
			else Node.PROCESS_MODE_DISABLED


func _up() -> Vector3:
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP
