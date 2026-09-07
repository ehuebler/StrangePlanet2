class_name CrawlerMissile
extends Node3D

## Small homing dart loosed by the Hex Hat. Every peer flies a copy; only the
## host turns a hit into damage.

const GROUP := &"crawler_missiles"
const CORE_COLOR := Color(0.78, 0.42, 1.0)
const GLOW_COLOR := Color(0.56, 0.16, 0.96)
const HALO_COLOR := Color(0.90, 0.48, 1.0, 0.44)
const TIP_COLOR := Color(1.0, 0.82, 0.34)
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
var seek := 24.0
var velocity := Vector3.ZERO
var authoritative := false

var _age := 0.0
var _core: MeshInstance3D
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
	var radius := size
	var body := CapsuleMesh.new()
	body.radius = radius * 0.42
	body.height = radius * 2.8
	body.radial_segments = 12
	body.rings = 4
	_core = MeshInstance3D.new()
	_core.mesh = body
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CORE_COLOR
	material.emission_enabled = true
	material.emission = GLOW_COLOR
	material.emission_energy_multiplier = 7.2
	_core.material_override = material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = radius * 0.38
	tip_mesh.height = radius * 0.76
	tip_mesh.radial_segments = 12
	tip_mesh.rings = 6
	tip.mesh = tip_mesh
	tip.position = Vector3(0.0, radius * 1.15, 0.0)
	var tip_material := StandardMaterial3D.new()
	tip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_material.albedo_color = TIP_COLOR
	tip_material.emission_enabled = true
	tip_material.emission = TIP_COLOR
	tip_material.emission_energy_multiplier = 8.4
	tip.material_override = tip_material
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tip)
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = radius * 1.7
	halo_mesh.height = radius * 3.4
	halo_mesh.radial_segments = 14
	halo_mesh.rings = 8
	var halo := MeshInstance3D.new()
	halo.mesh = halo_mesh
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_color = HALO_COLOR
	halo_material.emission_enabled = true
	halo_material.emission = GLOW_COLOR
	halo_material.emission_energy_multiplier = 4.6
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	var lamp := OmniLight3D.new()
	lamp.light_color = GLOW_COLOR
	lamp.light_energy = 3.4
	lamp.omni_range = maxf(radius * 10.0, 2.2)
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
	var field_slow := CrawlerFieldVolume.speed_scale_at(self, from) \
		* CrawlerLingerCloud.speed_scale_at(self, from)
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


func _nearest_mob() -> Node:
	var best: Node = null
	var best_span := seek
	for node in _hurt_targets():
		var span := global_position.distance_to(_combat_position(node))
		if span > best_span:
			continue
		best = node
		best_span = span
	return best


func _victim_along(from: Vector3, to: Vector3) -> Node:
	var sweep := DamageHit.beam(from, to, maxf(size, 0.10), 0.0)
	if not is_inside_tree():
		return null
	for node in _hurt_targets():
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
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
		var node := node_variant as Node
		if node == null or node == shooter:
			continue
		if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
			continue
		if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
			continue
		if node.has_method(&"is_charmed") and bool(node.call(&"is_charmed")):
			continue
		found.append(node)
	return found


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
	if node.has_method(&"combat_position"):
		return node.call(&"combat_position")
	return (node as Node3D).global_position


func _up() -> Vector3:
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP
