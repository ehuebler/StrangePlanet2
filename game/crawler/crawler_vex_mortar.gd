class_name CrawlerVexMortar
extends Node3D

## Cheap red pulsing lob. No lights. Only checks players unless the thrower
## is charmed, so a castle horde of Vex does not scan every goblin.

const LIFETIME := 4.2
const GLOW_COLOR := EnergyVfx.TINT_GREEN

var damage := 16.0
var gravity := 22.0
var shot_speed := 16.0
var ball_radius := 0.42
var hit_radius := 1.15
var knockback := 5.0
var ability_id := "crawler_vex_mortar"
var shooter: Node
var _charmed_shot := false

var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _core: EnergyVfx
var _spent := false
var _charm_frame := -1


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
	_core = EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, GLOW_COLOR)
	add_child(_core)
	_core.set_ball_radius(ball_radius)


func _physics_process(delta: float) -> void:
	_live += delta
	if is_instance_valid(_core):
		var pulse := 1.0 + sin(_live * 14.0) * 0.22
		_core.set_ball_radius(ball_radius * pulse)
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
	if not is_inside_tree():
		return null
	return CombatantSense.first_shot_along(
		self, from, to, hit_radius, shooter, _shooter_charmed())


func _hurt_targets() -> Array[Node]:
	if not is_inside_tree():
		return []
	return CombatantSense.shot_collect(self, shooter, _shooter_charmed())


func _should_hurt(node: Node) -> bool:
	if not is_instance_valid(node) or node == shooter:
		return false
	if not node is Node3D:
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return false
	if _shooter_charmed():
		return node is CrawlerMob
	return node.is_in_group(&"network_players")


func _shooter_charmed() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _charm_frame:
		_charm_frame = frame
		_charmed_shot = _read_shooter_charmed() if is_instance_valid(shooter) \
			else false
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
	blast.ability_id = ability_id
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
	return CombatantSense.point_of(player)


func _up() -> Vector3:
	if _planet != null:
		return _planet.up_at(global_position)
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
