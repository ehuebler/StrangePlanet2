class_name CrawlerMissile
extends Node3D

## Small homing dart loosed by the Hex Hat. Every peer flies a copy; only the
## host turns a hit into damage.

const GROUP := &"crawler_missiles"
const GLOW_COLOR := Color(0.56, 0.16, 0.96)
const PULSE_HZ := 7.2
const PULSE_SPAN := 0.16
const POP_COLORS: PackedColorArray = [
	Color(0.96, 0.72, 1.00),
	Color(0.62, 0.18, 1.00),
	Color(1.00, 0.78, 0.28),
	Color(0.42, 0.08, 0.92),
]

var shooter: OnlinePlayer
var damage := 0.0
var size := 0.14
var linger := 3.6
var speed := 16.0
var seek := 80.0
var velocity := Vector3.ZERO
var authoritative := false

var _age := 0.0
var _core: EnergyVfx
var _spent := false


static func volley(world: Node, source: OnlinePlayer, from: Vector3,
		toward: Vector3, count: int, recipe: Dictionary) -> Array[CrawlerMissile]:
	var spawned: Array[CrawlerMissile] = []
	if world == null or source == null or not from.is_finite() \
			or not toward.is_finite() or count <= 0:
		return spawned
	var forward := toward.normalized() if toward.length_squared() > 0.0001 \
		else -source.global_basis.z
	var up := from.normalized() if from.length_squared() > 0.01 else Vector3.UP
	var right := up.cross(forward)
	if right.length_squared() < 0.0001:
		right = source.global_basis.x
	right = right.normalized()
	up = right.cross(forward).normalized()
	var shots := clampi(count, 1, 24)
	var owns := source != null and (
		not source.multiplayer.has_multiplayer_peer()
		or source.multiplayer.is_server())
	for index in shots:
		var spread := float(index) - float(shots - 1) * 0.5
		var along := (forward + right * spread * 0.22 + up * 0.16).normalized()
		var at := from + along * 0.28 + up * 0.10
		var missile := launch(world, source, recipe, at, along, owns)
		if missile != null:
			spawned.append(missile)
	return spawned


static func launch(world: Node, source: OnlinePlayer, recipe: Dictionary,
		at: Vector3, along: Vector3, owns_hit := true) -> CrawlerMissile:
	if world == null or source == null or not at.is_finite():
		return null
	var missile := CrawlerMissile.new()
	missile.shooter = source
	missile.damage = maxf(float(recipe.get("damage", CrawlerRules.MISSILE_HAT_DAMAGE)), 0.0)
	missile.size = maxf(float(recipe.get("size", CrawlerRules.MISSILE_HAT_SIZE)), 0.06)
	missile.linger = maxf(float(recipe.get("linger", CrawlerRules.MISSILE_HAT_LINGER)), 0.4)
	missile.speed = maxf(float(recipe.get("speed", CrawlerRules.MISSILE_HAT_SPEED)), 4.0)
	missile.seek = maxf(float(recipe.get("range", CrawlerRules.MISSILE_HAT_RANGE)), 2.0)
	var heading := along.normalized() if along.length_squared() > 0.0001 \
		else Vector3.UP
	missile.velocity = heading * missile.speed
	missile.authoritative = owns_hit
	world.add_child(missile)
	missile.global_position = at
	missile._face(heading)
	return missile


func _ready() -> void:
	name = "CrawlerMissile"
	add_to_group(GROUP)
	_core = EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, GLOW_COLOR)
	add_child(_core)
	_core.set_ball_radius(size)
	CrawlerShotSense.watch(self)


func _exit_tree() -> void:
	CrawlerShotSense.drop(self)


func _physics_process(delta: float) -> void:
	shot_tick(delta)


func shot_tick(delta: float) -> void:
	if _spent:
		return
	_age += delta
	var pulse := 1.0 + sin(_age * TAU * PULSE_HZ) * PULSE_SPAN
	scale = Vector3.ONE * pulse
	_steer(delta)
	var from := global_position
	var field_slow := CrawlerMobSense.field_slow(self, from)
	var to := from + velocity * field_slow * delta
	var struck := _victim_along(from, to)
	if struck != null:
		global_position = _nearest_on(from, to, _combat_position(struck))
		pop(struck)
		return
	global_position = to
	if velocity.length_squared() > 0.0001:
		_face(velocity.normalized())
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
	if not is_inside_tree():
		return
	var prey := _nearest_mob()
	if prey == null:
		return
	var toward := _combat_position(prey) - global_position
	if toward.length_squared() < 0.0001:
		return
	var wanted := toward.normalized() * maxf(velocity.length(), speed)
	var blend := 1.0 - exp(-delta * CrawlerRules.MISSILE_HAT_STEER)
	velocity = velocity.lerp(wanted, blend)


func shot_glow_color() -> Color:
	return GLOW_COLOR


func shot_glow_energy() -> float:
	return 0.0 if _spent else 3.4


func shot_glow_range() -> float:
	return maxf(size * 10.0, 2.2)


func _nearest_mob() -> Node:
	var skip: Node = shooter if is_instance_valid(shooter) else null
	return CombatantSense.nearest_mob(self, global_position, seek, skip, true)


func _victim_along(from: Vector3, to: Vector3) -> Node:
	if not is_inside_tree():
		return null
	var skip: Node = shooter if is_instance_valid(shooter) else null
	return CombatantSense.first_along(
		self, from, to, maxf(size, 0.10), skip, {}, -1, false, true, false, true)


func _hurt_targets() -> Array[Node]:
	var skip: Node = shooter if is_instance_valid(shooter) else null
	return CombatantSense.collect(
		self, skip, -1, false, true, false, true)


func _deal(_at: Vector3, struck: Node) -> void:
	if struck == null or not struck.has_method(&"apply_damage"):
		return
	struck.call(&"apply_damage", _make_hit(struck).resolved_for(struck))


func _make_hit(struck: Node) -> DamageHit:
	var at := _combat_position(struck)
	var hit := DamageHit.impact(at, maxf(size, 0.12), damage)
	hit.faction = DamageHit.Faction.PLAYER
	hit.ability_id = "hex"
	hit.affects_flora = false
	hit.projectile = true
	if is_instance_valid(shooter):
		hit.set_source(shooter, shooter.peer_id)
	return hit


func _play_burst(at: Vector3) -> void:
	var world := get_parent()
	var reach := maxf(size * 2.2, 0.42)
	EnergyExplosion.burst(world, at, reach, GLOW_COLOR, 0.18)
	CrawlerBurst.play(world, at, _up(), maxf(reach * 0.85, 0.7), POP_COLORS)


func _face(along: Vector3) -> void:
	if not along.is_finite() or along.length_squared() < 0.0001:
		return
	var facing := along.normalized()
	var up := _up()
	var right := up.cross(facing)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT if absf(facing.y) > 0.9 else up.cross(Vector3.UP)
	right = right.normalized()
	up = facing.cross(right).normalized()
	global_basis = Basis(right, facing, up)


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
