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
	if _mesh != null:
		return _mesh.global_position
	return global_position


func combat_radius() -> float:
	if _mesh != null and _mesh.mesh != null:
		var box := _mesh.mesh.get_aabb()
		return maxf(maxf(box.size.x, box.size.y), box.size.z) * 0.42 \
			* maxf(_mesh.global_basis.get_scale().x, 1.0)
	return 3.2


func combat_aabb() -> AABB:
	var half := combat_radius()
	var at := combat_position()
	return AABB(at - Vector3.ONE * half, Vector3.ONE * (half * 2.0))


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
	var red := Color(1.0, 0.16, 0.08)
	_paint.albedo_color = _base_color.lerp(red, clampf(amount, 0.0, 1.0))


func _up() -> Vector3:
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP
