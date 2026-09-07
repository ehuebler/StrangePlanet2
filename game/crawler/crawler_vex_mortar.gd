class_name CrawlerVexMortar
extends Node3D

## Cheap red pulsing lob. No lights. Only checks players unless the thrower
## is charmed, so a castle horde of Vex does not scan every goblin.

const LIFETIME := 4.2
const CORE_COLOR := Color(1.0, 0.22, 0.14)
const GLOW_COLOR := Color(0.95, 0.08, 0.06)

var damage := 16.0
var gravity := 22.0
var shot_speed := 16.0
var ball_radius := 0.42
var hit_radius := 1.15
var knockback := 5.0
var shooter: Node
var _charmed_shot := false

var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _core: MeshInstance3D
var _spent := false


func launch(planet: Planet, from: Vector3, along: Vector3, by: Node) -> bool:
	if planet == null:
		return false
	return _begin(planet, from, along, by)


func launch_anywhere(host: Node, from: Vector3, along: Vector3, by: Node) -> bool:
	if host == null:
		return false
	return _begin(host, from, along, by)


func _begin(host: Node, from: Vector3, along: Vector3, by: Node) -> bool:
	if not from.is_finite() or not along.is_finite() or along.is_zero_approx():
		return false
	name = "CrawlerVexMortar"
	_velocity = along
	shooter = by
	_charmed_shot = _read_shooter_charmed()
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	host.add_child(self)
	global_position = from
	set_physics_process(true)
	return true


func _ready() -> void:
	set_physics_process(_velocity.length_squared() > 0.0001)
	_planet = get_parent() as Planet
	var mesh := SphereMesh.new()
	mesh.radius = ball_radius
	mesh.height = ball_radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	_core = MeshInstance3D.new()
	_core.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CORE_COLOR
	material.emission_enabled = true
	material.emission = GLOW_COLOR
	material.emission_energy_multiplier = 5.8
	_core.material_override = material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)


func _physics_process(delta: float) -> void:
	_live += delta
	if is_instance_valid(_core):
		var pulse := 1.0 + sin(_live * 14.0) * 0.22
		_core.scale = Vector3.ONE * pulse
		var glow := _core.material_override as StandardMaterial3D
		if glow != null:
			glow.emission_energy_multiplier = 4.4 + sin(_live * 11.0) * 2.2
	if _live >= LIFETIME:
		queue_free()
		return
	var up := _up()
	_velocity -= up * maxf(gravity, 0.0) * delta
	var from := global_position
	var to := from + _velocity * delta
	var struck := _victim_along(from, to)
	if struck != null:
		global_position = _nearest_on(from, to, _combat_position(struck))
		detonate()
		return
	if not is_inside_tree():
		return
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _blocker.is_valid():
		query.exclude = DamageHit.rid_list(_blocker)
	var landed := get_world_3d().direct_space_state.intersect_ray(query)
	if landed.is_empty():
		global_position = to
		return
	global_position = landed["position"]
	detonate()


func _victim_along(from: Vector3, to: Vector3) -> Node:
	var sweep := DamageHit.beam(from, to, hit_radius, 0.0)
	if not is_inside_tree():
		return null
	for node in _hurt_targets():
		if not is_instance_valid(node):
			continue
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = float(node.call(&"combat_radius"))
		if sweep.reaches(_combat_position(node), bounds):
			return node
	return null


func _hurt_targets() -> Array[Node]:
	var found: Array[Node] = []
	var seen := {}
	if not is_inside_tree():
		return found
	if _shooter_charmed():
		for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
			if is_instance_valid(node_variant):
				_take_if(node_variant as Node, seen, found)
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		if is_instance_valid(node_variant):
			_take_if(node_variant as Node, seen, found)
	return found


func _take_if(node: Node, seen: Dictionary, found: Array[Node]) -> void:
	if not is_instance_valid(node):
		return
	var key := node.get_instance_id()
	if seen.has(key) or not _should_hurt(node):
		return
	seen[key] = true
	found.append(node)


func _should_hurt(node: Node) -> bool:
	if not is_instance_valid(node) or node == shooter:
		return false
	if not node is Node3D:
		return false
	if DamageHit.game_world_of(self) != null \
			and not DamageHit.in_same_world(self, node):
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return false
	if _shooter_charmed():
		return node is CrawlerMob
	return node.is_in_group(&"network_players")


func _shooter_charmed() -> bool:
	if is_instance_valid(shooter):
		_charmed_shot = _read_shooter_charmed()
	return _charmed_shot


func _read_shooter_charmed() -> bool:
	if not is_instance_valid(shooter):
		return false
	var mob := shooter as CrawlerMob
	return mob != null and mob.is_charmed()


func detonate() -> void:
	if _spent:
		return
	_spent = true
	var at := global_position
	if _is_host():
		_deal_aoe(at)
	queue_free()


func _deal_aoe(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var blast := _make_blast(at)
	for node in _hurt_targets():
		if not node.has_method(&"apply_damage"):
			continue
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = float(node.call(&"combat_radius"))
		if not blast.reaches(_combat_position(node), bounds):
			continue
		node.call(&"apply_damage", blast.resolved_for(node))


func _make_blast(at: Vector3) -> DamageHit:
	var along := _velocity.normalized() \
		if _velocity.length_squared() > 0.01 else -_up()
	var blast := DamageHit.area(at, hit_radius * 1.15, damage, 0.35)
	blast.faction = DamageHit.Faction.PLAYER if _shooter_charmed() \
		else DamageHit.Faction.ENEMY
	blast.parryable = true
	blast.reaction = DamageHit.Reaction.STAGGER
	blast.world_impulse = along * knockback * 0.3
	blast.radial_impulse = knockback * 0.55
	blast.affects_flora = false
	blast.ability_id = "crawler_vex_mortar"
	blast.projectile = true
	if is_instance_valid(shooter):
		blast.set_source(shooter)
	return blast


func _nearest_on(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var along := to - from
	var span := along.length_squared()
	if span < 0.000001:
		return from
	return from + along * clampf((point - from).dot(along) / span, 0.0, 1.0)


func _combat_position(player: Node) -> Vector3:
	if not is_instance_valid(player):
		return global_position
	if player.has_method(&"combat_position"):
		return player.call(&"combat_position")
	var body := player as Node3D
	return body.global_position if body != null else global_position


func _up() -> Vector3:
	if _planet != null:
		return _planet.up_at(global_position)
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
