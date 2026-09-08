class_name CrawlerGrayShot
extends Node3D

## Slow green ranger-style orb. Homes moderately, then coasts.

const LIFETIME := 7.5
const GLOW_COLOR := EnergyVfx.TINT_GREEN
const HOMING := 2.4
const TURN := 2.15

var damage := 7.0
var gravity := 2.2
var shot_speed := 7.0
var ball_radius := 0.58
var hit_radius := 1.3
var knockback := 4.0
var parryable := true
var shooter: Node
var prey: Node
var homing_left := HOMING
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
	name = "CrawlerGrayShot"
	_velocity = along.normalized() * maxf(shot_speed, 0.5)
	shooter = by
	if prey == null:
		prey = _nearest_prey()
	_charmed_shot = _read_shooter_charmed()
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	host.add_child(self)
	global_position = from
	return true


func _ready() -> void:
	_planet = get_parent() as Planet
	_core = EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, GLOW_COLOR)
	add_child(_core)
	_core.set_ball_radius(ball_radius)
	var lamp := OmniLight3D.new()
	lamp.light_color = GLOW_COLOR
	lamp.light_energy = 3.8
	lamp.omni_range = maxf(ball_radius * 9.0, 4.2)
	lamp.shadow_enabled = false
	add_child(lamp)


func _physics_process(delta: float) -> void:
	_live += delta
	if is_instance_valid(_core):
		var pulse := 1.0 + sin(_live * 9.0) * 0.10
		_core.set_ball_radius(ball_radius * pulse)
	if _live >= LIFETIME:
		queue_free()
		return
	_home(delta)
	var up := _up()
	_velocity -= up * maxf(gravity, 0.0) * delta
	var from := global_position
	var field_slow := CrawlerFieldVolume.speed_scale_at(self, from) \
		* CrawlerLingerCloud.speed_scale_at(self, from)
	var to := from + _velocity * field_slow * delta
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


func _home(delta: float) -> void:
	if homing_left <= 0.0 or shot_speed <= 0.01:
		return
	homing_left = maxf(homing_left - delta, 0.0)
	var target := prey if is_instance_valid(prey) else _nearest_prey()
	if target == null:
		return
	var at := _combat_position(target)
	var along := at - global_position
	if along.length_squared() < 0.0001:
		return
	var wanted := along.normalized() * maxf(shot_speed, 0.5)
	_velocity = _velocity.lerp(wanted, clampf(TURN * delta, 0.0, 1.0))
	if _velocity.length_squared() > 0.0001:
		_velocity = _velocity.normalized() * maxf(shot_speed, 0.5)


func _nearest_prey() -> Node:
	if not is_inside_tree():
		return null
	CrawlerMobSense.ensure_frame(get_tree())
	var best: Node
	var best_span := INF
	for node_variant: Variant in CrawlerMobSense.shot_targets(_shooter_charmed()):
		var node := node_variant as Node
		if node == null or not _should_hurt(node):
			continue
		var span := global_position.distance_squared_to(_combat_position(node))
		if span < best_span:
			best_span = span
			best = node
	return best


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
	if not is_inside_tree():
		return found
	var charmed := _shooter_charmed()
	CrawlerMobSense.ensure_frame(get_tree())
	for node_variant: Variant in CrawlerMobSense.shot_targets(charmed):
		var node := node_variant as Node
		if node != null and _should_hurt(node):
			found.append(node)
	return found


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


func blast_radius() -> float:
	return CrawlerRules.ranger_shot_aoe_from_hit(hit_radius)


func detonate() -> void:
	if _spent:
		return
	_spent = true
	var at := global_position
	_play_burst(at)
	if _is_host():
		_deal_aoe(at)
	queue_free()


func _play_burst(at: Vector3) -> void:
	var world := _effect_world()
	var reach := blast_radius()
	EnergyExplosion.burst(world, at, reach * 0.72, GLOW_COLOR, 0.32)
	CrawlerBurst.orb(world, at, _up(), maxf(reach * 0.55, 1.4))


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
	var blast := DamageHit.area(
		at, blast_radius(), damage, CrawlerRules.RANGER_SHOT_AOE_FALLOFF)
	blast.faction = DamageHit.Faction.PLAYER if _shooter_charmed() \
		else DamageHit.Faction.ENEMY
	blast.parryable = parryable
	blast.reaction = DamageHit.Reaction.STAGGER
	blast.world_impulse = along * knockback * 0.35
	blast.radial_impulse = knockback * 0.7
	blast.radial_lift = knockback * 0.18
	blast.affects_flora = false
	blast.ability_id = "crawler_gray_shot"
	blast.projectile = true
	if is_instance_valid(shooter):
		blast.set_source(shooter)
	return blast


func _effect_world() -> Node:
	if _planet != null:
		return _planet
	var world := DamageHit.game_world_of(self)
	if world != null:
		return world
	return get_parent()


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
