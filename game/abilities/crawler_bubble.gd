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
var _core: EnergyVfx
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
	_core = EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, GLOW_COLOR)
	add_child(_core)
	_core.set_ball_radius(size)
	var lamp := OmniLight3D.new()
	lamp.light_color = GLOW_COLOR
	lamp.light_energy = 3.8
	lamp.omni_range = maxf(size * 8.0, 2.4)
	lamp.shadow_enabled = false
	add_child(lamp)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_age += delta
	var pulse := 1.0 + sin(_age * TAU * PULSE_HZ) * PULSE_SPAN
	scale = Vector3.ONE * pulse
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
			if authoritative and pop_radius <= 0.001 \
					and struck.has_method(&"apply_damage"):
				struck.call(
					&"apply_damage",
					_make_hit(global_position, size).resolved_for(struck))
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


func _steer(delta: float) -> void:
	if homing <= 0.001 or not is_inside_tree():
		return
	var prey := _nearest_enemy()
	if prey == null:
		return
	var toward := _combat_position(prey) - global_position
	if toward.length_squared() < 0.0001:
		return
	var wanted := toward.normalized() * maxf(velocity.length(), travel_speed)
	var blend := 1.0 - exp(-delta * steer_rate)
	velocity = velocity.lerp(wanted, blend)


func _nearest_enemy() -> Node:
	var best: Node = null
	var best_span := homing
	for node in _hurt_targets():
		var span := global_position.distance_to(_combat_position(node))
		if span > best_span:
			continue
		best = node
		best_span = span
	return best


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
	var sweep := DamageHit.beam(from, to, maxf(size, 0.12), 0.0)
	if not is_inside_tree():
		return null
	for node in _hurt_targets():
		if _grazed.has(node.get_instance_id()):
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
	for node_variant: Variant in get_tree().get_nodes_in_group(
			DamageHit.COMBATANT_GROUP):
		var node := node_variant as Node
		if node == null or node == shooter:
			continue
		if not node.has_method(&"combat_faction") \
				or int(node.call(&"combat_faction")) != DamageHit.Faction.ENEMY:
			continue
		if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
			continue
		if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
			continue
		found.append(node)
	return found


func _deal(at: Vector3, struck: Node) -> void:
	if not is_inside_tree():
		return
	if pop_radius > 0.001:
		_deal_pop(at)
		return
	if struck == null or not struck.has_method(&"apply_damage"):
		return
	struck.call(&"apply_damage", _make_hit(at, size).resolved_for(struck))


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
	var world := get_parent()
	var reach := pop_radius if pop_radius > 0.001 else maxf(size * 1.8, 0.45)
	EnergyExplosion.burst(world, at, reach, GLOW_COLOR, 0.22)
	CrawlerBurst.play(world, at, _up(), maxf(reach * 0.7, 0.8), POP_COLORS)


func _nearest_on(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var along := to - from
	var span := along.length_squared()
	if span < 0.000001:
		return from
	return from + along * clampf((point - from).dot(along) / span, 0.0, 1.0)


func _combat_position(node: Node) -> Vector3:
	if node.has_method(&"combat_position"):
		return node.call(&"combat_position")
	return (node as Node3D).global_position


func _up() -> Vector3:
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP
