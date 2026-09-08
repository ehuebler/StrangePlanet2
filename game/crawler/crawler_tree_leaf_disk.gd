class_name CrawlerTreeLeafDisk
extends Node3D

## Slow spinning leaf disk. Explodes on a player hit or after a random
## travel between 20 m and 50 m from the trunk.

const SPEED := 11.0
const DAMAGE := 8.0
const POISON_DPS := 3.0
const POISON_HOLD := 3.2
const HIT_RADIUS := 1.15

var shooter: Node
var _origin := Vector3.ZERO
var _along := Vector3.FORWARD
var _fuse := 32.0
var _spent := false
var _spin := 0.0
var _visual: MeshInstance3D


func launch(host: Node, from: Vector3, along: Vector3, by: Node, fuse_m: float) -> bool:
	if host == null or not from.is_finite() or along.length_squared() < 0.0001:
		return false
	shooter = by
	_origin = from
	_along = along.normalized()
	_fuse = clampf(fuse_m, 20.0, 50.0)
	host.add_child(self)
	global_position = from
	return true


func _ready() -> void:
	name = "GivingTreeLeaf"
	_visual = MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 0.72
	disk.bottom_radius = 0.72
	disk.height = 0.08
	disk.radial_segments = 24
	_visual.mesh = disk
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.32, 0.86, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.22, 0.72, 0.10)
	mat.emission_energy_multiplier = 3.4
	_visual.material_override = mat
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	var light := OmniLight3D.new()
	light.light_color = Color(0.28, 0.78, 0.16)
	light.light_energy = 1.8
	light.omni_range = 4.2
	add_child(light)
	if _along.length_squared() > 0.0001:
		var up := _origin.normalized() if _origin.length_squared() > 0.01 else Vector3.UP
		look_at(global_position + _along, up)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_spin += delta * 14.0
	if _visual != null:
		_visual.rotate_y(delta * 14.0)
	global_position += _along * SPEED * delta
	var span := global_position.distance_to(_origin)
	if span >= _fuse or _strike_player():
		_explode()


func _strike_player() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node_variant: Variant in tree.get_nodes_in_group(&"network_players"):
		var player := node_variant as Node3D
		if player == null:
			continue
		var at := player.global_position
		if player.has_method(&"combat_position"):
			at = player.call(&"combat_position")
		if global_position.distance_to(at) <= HIT_RADIUS + 0.55:
			return true
	return false


func _explode() -> void:
	if _spent:
		return
	_spent = true
	var hit := DamageHit.area(global_position, 2.6, DAMAGE, 0.4)
	hit.kind = DamageHit.Kind.AREA
	hit.faction = DamageHit.Faction.ENEMY
	hit.ability_id = "giving_tree_leaf"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.radial_impulse = 5.5
	hit.radial_lift = 2.4
	hit.with_status(CombatStatuses.POISON, POISON_HOLD, POISON_DPS)
	hit.status_stack = true
	hit.set_source(shooter if shooter != null else self)
	var world := DamageHit.game_world_of(self)
	if world != null:
		DamageHit.apply_to_combatants(self, hit)
		CrawlerBurst.leaves(world, global_position, _up(), 2.2)
	queue_free()


func _up() -> Vector3:
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP
