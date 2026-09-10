class_name CrawlerRobotLaser
extends Node3D

## Fast straight bolt. Arm delay lets a gatling volley leave one muzzle
## over time from a single attack token.

const LIFETIME := 2.6

var damage := 8.0
var shot_speed := 48.0
var ball_radius := 0.08
var hit_radius := 0.42
var knockback := 3.2
var gravity := 0.0
var arm_delay := 0.0
var core_color := Color(0.55, 0.95, 1.0)
var glow_color := Color(0.12, 0.78, 1.0)
var ability_id := "crawler_robot_laser"
var shooter: Node
## Who this bolt should hit. The kestrel keeps flying through its windup, so
## the heading baked at burst-start is already stale by the time the first
## round leaves. [member prey] is the lock; [method _aim_from_muzzle] aims
## again from the live socket.
var prey: Node
var _charmed_shot := false
var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _armed := false
var _spent := false
var _core: EnergyVfx
var _charm_frame := -1


func launch_anywhere(host: Node, from: Vector3, along: Vector3, by: Node) -> bool:
	if host == null or not from.is_finite() or not along.is_finite() \
			or along.is_zero_approx():
		return false
	name = "CrawlerRobotLaser"
	_velocity = along.normalized() * maxf(shot_speed, 8.0)
	shooter = by
	_charmed_shot = _read_shooter_charmed()
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	host.add_child(self)
	global_position = from
	_armed = arm_delay <= 0.0
	set_physics_process(true)
	return true


func _ready() -> void:
	_planet = get_parent() as Planet
	_core = EnergyVfx.make(EnergyVfx.Kind.BEAM_CORE, glow_color)
	_core.top_level = true
	add_child(_core)
	_fit_bolt()


func _physics_process(delta: float) -> void:
	if not _armed:
		arm_delay -= delta
		if arm_delay > 0.0:
			_stick_muzzle()
			_fit_bolt()
			return
		_armed = true
		_aim_from_muzzle()
	_live += delta
	if _live >= LIFETIME:
		queue_free()
		return
	if _velocity.length_squared() > 0.0001:
		look_at(global_position + _velocity, _up())
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
		_fit_bolt()
		return
	global_position = landed["position"]
	detonate()


func detonate() -> void:
	if _spent:
		return
	_spent = true
	if _is_host():
		_deal_hit(global_position)
	queue_free()


func _fit_bolt() -> void:
	if not is_instance_valid(_core):
		return
	var along := _velocity
	if not _armed:
		var dest := _aim_point()
		if dest.is_finite():
			along = dest - global_position
	if along.length_squared() < 0.0001:
		along = -_up()
	along = along.normalized()
	var span := maxf(ball_radius * 9.0, 0.72)
	var width := maxf(ball_radius * 1.8, 0.045)
	_core.set_tint(glow_color)
	_core.place_beam(
		global_position - along * span * 0.5,
		global_position + along * span * 0.5,
		width)


func _stick_muzzle() -> void:
	var at := _muzzle_point()
	if at.is_finite():
		global_position = at


func _aim_from_muzzle() -> void:
	var from := _muzzle_point()
	if from.is_finite():
		global_position = from
	else:
		from = global_position
	var dest := _aim_point()
	if dest.is_finite():
		var along := dest - from
		if along.length_squared() > 0.0001:
			_velocity = along.normalized() * maxf(shot_speed, 8.0)
			return
	if _velocity.length_squared() < 0.0001:
		_velocity = -_up() * shot_speed


func _aim_point() -> Vector3:
	var target := _resolve_prey()
	if target == null:
		return Vector3.INF
	var dest := _combat_position(target)
	if not dest.is_finite():
		return Vector3.INF
	var speed := maxf(shot_speed, 8.0)
	var lead := _prey_velocity(target)
	if lead.length_squared() > 0.0001:
		dest += lead * (global_position.distance_to(dest) / speed)
	return dest


func _resolve_prey() -> Node:
	if is_instance_valid(prey):
		return prey
	if is_instance_valid(shooter) and shooter.has_method(&"laser_prey"):
		var found: Variant = shooter.call(&"laser_prey")
		if found is Node and is_instance_valid(found):
			return found
	return null


func _prey_velocity(target: Node) -> Vector3:
	if target == null:
		return Vector3.ZERO
	var lead: Variant = target.get(&"velocity")
	return lead as Vector3 if lead is Vector3 and (lead as Vector3).is_finite() \
		else Vector3.ZERO


func _muzzle_point() -> Vector3:
	if not is_instance_valid(shooter):
		return global_position
	if shooter.has_method(&"muzzle_point"):
		var at: Variant = shooter.call(&"muzzle_point")
		if at is Vector3 and (at as Vector3).is_finite():
			return at as Vector3
	var body := shooter as Node3D
	if body != null:
		return body.global_position
	return global_position


func _deal_hit(at: Vector3) -> void:
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
	var blast := DamageHit.area(at, hit_radius, damage, 0.2)
	blast.faction = DamageHit.Faction.PLAYER if _shooter_charmed() \
		else DamageHit.Faction.ENEMY
	blast.parryable = true
	blast.reaction = DamageHit.Reaction.STAGGER
	blast.world_impulse = along * knockback
	blast.affects_flora = false
	blast.ability_id = ability_id
	blast.projectile = true
	if is_instance_valid(shooter):
		blast.set_source(shooter)
	return blast


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
