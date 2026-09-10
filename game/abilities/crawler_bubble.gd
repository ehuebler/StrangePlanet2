class_name CrawlerBubble
extends Node3D

## Glowing blue orb left by the Bubble modifier. Pulses, floats, then pops.

const GROUP := &"crawler_bubbles"
const CORE_COLOR := Color(0.42, 0.82, 1.0)
const GLOW_COLOR := Color(0.18, 0.62, 1.0)
const HALO_COLOR := Color(0.28, 0.72, 1.0, 0.46)
const PULSE_HZ := 3.4
const PULSE_SPAN := 0.28
const STEER := 7.5
const POP_COLORS: PackedColorArray = [
	Color(0.55, 0.88, 1.00),
	Color(0.22, 0.62, 1.00),
	Color(0.78, 0.96, 1.00),
	Color(0.16, 0.42, 0.95),
]

var shooter: OnlinePlayer
var ability_id := ""
var damage := 0.0
var size := 0.28
var linger := 2.4
var homing := 0.0
var steer_rate := STEER
var pop_radius := 0.0
var status_id := &""
var status_duration := 0.0
var status_strength := 0.0
var extra_statuses: Array = []
var velocity := Vector3.ZERO
var travel_speed := CrawlerRules.BUBBLE_SPEED
var authoritative := false
var bounces_left := 0

var _age := 0.0
var _spent := false
var _shooter_rid := RID()
var _grazed: Dictionary = {}
var _bounce_world := false


static func launch(world: Node, source: OnlinePlayer, recipe: Dictionary,
		at: Vector3, along: Vector3) -> CrawlerBubble:
	var owns := source != null and (
		not source.multiplayer.has_multiplayer_peer()
		or source.multiplayer.is_server())
	var speed := maxf(float(recipe.get("speed", CrawlerRules.BUBBLE_SPEED)),
		CrawlerRules.BUBBLE_SPEED)
	var travel := along.normalized() * speed if along.length_squared() > 0.0001 \
		else Vector3.ZERO
	return spawn(world, source, recipe, at, travel, owns)


static func spawn(world: Node, source: OnlinePlayer, recipe: Dictionary,
		at: Vector3, along: Vector3, owns_hit := true) -> CrawlerBubble:
	if world == null or source == null or not at.is_finite():
		return null
	var bubble := CrawlerBubble.new()
	bubble.shooter = source
	bubble.ability_id = str(recipe.get("ability_id", "bubble"))
	bubble.damage = maxf(float(recipe.get("damage", 0.0)), 0.0)
	bubble.size = maxf(float(recipe.get("size", CrawlerRules.BUBBLE_SIZE)), 0.08)
	bubble.linger = maxf(float(recipe.get("linger", CrawlerRules.BUBBLE_LINGER)), 0.2)
	bubble.homing = maxf(float(recipe.get("homing", 0.0)), 0.0)
	bubble.steer_rate = maxf(float(recipe.get("steer", STEER)), STEER)
	bubble.pop_radius = maxf(float(recipe.get("pop", 0.0)), 0.0)
	bubble.status_id = StringName(str(recipe.get("status_id", "")))
	bubble.status_duration = maxf(float(recipe.get("status_duration", 0.0)), 0.0)
	bubble.status_strength = maxf(float(recipe.get("status_strength", 0.0)), 0.0)
	var carried: Variant = recipe.get("statuses", [])
	if carried is Array:
		bubble.extra_statuses = (carried as Array).duplicate(true)
	bubble.velocity = along if along.is_finite() else Vector3.ZERO
	bubble.travel_speed = maxf(float(recipe.get("speed", CrawlerRules.BUBBLE_SPEED)),
		CrawlerRules.BUBBLE_SPEED)
	bubble.bounces_left = CrawlerBounce.count(recipe)
	bubble._bounce_world = bubble.bounces_left > 0
	if bubble.velocity.length_squared() > 0.0001 \
			and bubble.velocity.length() < bubble.travel_speed:
		bubble.velocity = bubble.velocity.normalized() * bubble.travel_speed
	bubble.authoritative = owns_hit
	bubble._shooter_rid = source.get_rid()
	world.add_child(bubble)
	bubble.global_position = at
	return bubble


func _ready() -> void:
	name = "CrawlerBubble"
	add_to_group(GROUP)
	CrawlerShotSense.watch(self)


func _exit_tree() -> void:
	CrawlerShotSense.drop(self)


func _physics_process(delta: float) -> void:
	shot_tick(delta)


func shot_tick(delta: float) -> void:
	if _spent:
		return
	_age += delta
	_steer(delta)
	var from := global_position
	var to := from + velocity * delta
	var struck := _victim_along(from, to)
	var wall := _world_along(from, to) if _bounce_world else {}
	if struck != null and not wall.is_empty():
		var enemy_at := _nearest_on(from, to, _combat_position(struck))
		var wall_at: Vector3 = wall.get("position", to)
		if from.distance_to(wall_at) < from.distance_to(enemy_at):
			struck = null
		else:
			wall = {}
	if struck != null:
		global_position = _nearest_on(from, to, _combat_position(struck))
		if bounces_left > 0:
			_grazed[struck.get_instance_id()] = true
			if authoritative and pop_radius <= 0.001:
				_hurt(struck, global_position, size)
			var away := global_position - _combat_position(struck)
			_ricochet(away if away.length_squared() > 0.000001 else -velocity,
				pop_radius > 0.001)
			return
		pop(struck)
		return
	if not wall.is_empty():
		global_position = wall.get("position", to)
		if bounces_left > 0:
			_ricochet(wall.get("normal", -velocity), pop_radius > 0.001)
		else:
			pop(null)
		return
	global_position = to
	if _age >= linger:
		pop(null)


func pop(struck: Node = null) -> void:
	if _spent:
		return
	_spent = true
	var at := global_position
	_play_burst(at)
	if authoritative:
		_deal(at, struck)
	queue_free()


func shot_retire() -> void:
	if _spent:
		return
	_spent = true
	queue_free()


func shot_batch_radius() -> float:
	return 0.0 if _spent else size


func shot_batch_pulse() -> float:
	return 1.0 + sin(_age * TAU * PULSE_HZ) * PULSE_SPAN


func shot_glow_color() -> Color:
	return GLOW_COLOR


func shot_glow_energy() -> float:
	return 0.0 if _spent else 3.8


func shot_glow_range() -> float:
	return maxf(size * 8.0, 2.4)


func _steer(delta: float) -> void:
	if homing <= 0.001 or not is_inside_tree():
		return
	var prey := CrawlerShotSense.prey(
		self, global_position, homing, shooter)
	if prey == null:
		return
	var toward := CombatantSense.point_of(prey) - global_position
	if toward.length_squared() < 0.0001:
		return
	var wanted := toward.normalized() * maxf(velocity.length(), travel_speed)
	var blend := 1.0 - exp(-delta * steer_rate)
	velocity = velocity.lerp(wanted, blend)


func _ricochet(normal: Vector3, explode: bool) -> void:
	if explode and pop_radius > 0.001:
		if authoritative:
			_deal_pop(global_position)
		_play_burst(global_position)
	var incoming := velocity if velocity.length_squared() > 0.000001 \
		else Vector3.UP
	var outgoing := CrawlerBounce.reflect(incoming, normal)
	if outgoing.length_squared() < 0.000001:
		pop(null)
		return
	bounces_left = maxi(bounces_left - 1, 0)
	var speed := maxf(velocity.length(), travel_speed)
	velocity = outgoing * speed
	global_position = CrawlerBounce.nudge(global_position, normal, outgoing)


func _world_along(from: Vector3, to: Vector3) -> Dictionary:
	if shooter == null or not is_instance_valid(shooter):
		return {}
	return LaserEyes._surface(shooter, from, to)


func _victim_along(from: Vector3, to: Vector3) -> Node:
	if not is_inside_tree():
		return null
	var skip: Node = shooter if is_instance_valid(shooter) else null
	return CombatantSense.first_along(
		self, from, to, maxf(size, 0.12), skip, _grazed)


func _hurt_targets() -> Array[Node]:
	var skip: Node = shooter if is_instance_valid(shooter) else null
	return CombatantSense.collect(self, skip)


func _deal(at: Vector3, struck: Node) -> void:
	if not is_inside_tree():
		return
	if pop_radius > 0.001:
		_deal_pop(at)
		return
	_hurt(struck, at, size)


func _hurt(target: Node, at: Vector3, radius: float) -> void:
	if target == null or not target.has_method(&"apply_damage"):
		return
	# Confirmed touch: skip capsule falloff so a surface graze still hurts.
	var hit := _make_hit(at, radius)
	hit.falloff = 0.0
	var result: Variant = target.call(&"apply_damage", hit)
	var dealt := float(result) if result is float or result is int else 0.0
	if dealt > 0.0 and is_instance_valid(shooter) \
			and shooter.has_method(&"combat_damage_dealt"):
		shooter.call(&"combat_damage_dealt", target, dealt, hit)


func _deal_pop(at: Vector3) -> void:
	var blast := _make_hit(at, pop_radius)
	blast.kind = DamageHit.Kind.AREA
	blast.falloff = 0.35
	blast.affects_flora = true
	blast.plant_break_effects = false
	DamageHit.apply_to_world(self, blast)
	_scar(at)


func _make_hit(at: Vector3, radius: float) -> DamageHit:
	var hit := DamageHit.area(at, maxf(radius, 0.12), damage, 0.15)
	hit.faction = DamageHit.Faction.PLAYER
	hit.ability_id = "bubble"
	hit.affects_flora = false
	if extra_statuses.size() > 1:
		CrawlerElements.apply_to_hit(hit, extra_statuses)
	elif not status_id.is_empty() and status_duration > 0.0:
		hit.with_status(status_id, status_duration, status_strength)
	if is_instance_valid(shooter):
		hit.set_source(shooter, shooter.peer_id)
	return hit


func _scar(at: Vector3) -> void:
	if shooter == null or not is_instance_valid(shooter) or pop_radius <= 0.001:
		return
	var world_planet := shooter.planet() if shooter.has_method(&"planet") else null
	if world_planet == null:
		return
	var direction := world_planet.to_local(at)
	if direction.length_squared() < 0.25:
		return
	var scar := TerrainScars.Scar.new()
	scar.direction = direction.normalized()
	scar.radius = pop_radius
	scar.depth = clampf(pop_radius * 0.22, 0.12, 2.4)
	scar.profile = TerrainScars.Profile.BOWL
	scar.char = 0.42
	scar.tint = Color(0.10, 0.18, 0.28)
	shooter.request_scar(scar)


func _play_burst(at: Vector3) -> void:
	var reach := pop_radius if pop_radius > 0.001 else maxf(size * 1.8, 0.45)
	if pop_radius <= 0.001:
		CrawlerShotSense.pop(self, at, reach, GLOW_COLOR)
		return
	var world := get_parent()
	EnergyExplosion.burst(world, at, reach, GLOW_COLOR, 0.22)
	CrawlerBurst.play(world, at, _up(), maxf(reach * 0.7, 0.8), POP_COLORS)


func _nearest_on(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var along := to - from
	var span := along.length_squared()
	if span < 0.000001:
		return from
	return from + along * clampf((point - from).dot(along) / span, 0.0, 1.0)


func _combat_position(node: Node) -> Vector3:
	return CombatantSense.point_of(node)


func _up() -> Vector3:
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP
