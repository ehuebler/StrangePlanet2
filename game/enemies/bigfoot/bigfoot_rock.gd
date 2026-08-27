class_name BigfootRock
extends Node3D

## A rock the boss picks out of the ground and throws.
##
## Deliberately not a physics body. A body this small moving this fast tunnels
## through whatever it is aimed at, so the rock sweeps the ground it covered each
## frame instead: a ray for the world, and a capsule against everyone standing in
## the arena, which is what lets it catch a player mid-air.
##
## Every peer flies its own copy from the same launch and shatters it where it
## lands, so the throw reads the same everywhere; only the host turns a hit into
## damage. See [method BigfootBoss._hurl_rock].

## The stone he is throwing is the stone lying around his jungle — same mesh,
## same colour paint, same break debris — rather than a second rock invented in
## code that would not match anything the player has walked past.
const SPECIES := preload("res://game/props/biomes/rock_weathered.tres")
## Across, in metres. About a basketball, which at his size is a thrown stone
## and at yours is something you want to be somewhere else.
const ACROSS := 0.34
## Generous against the body it is thrown at, because the rock is small, fast,
## and swept in steps a fifth of a metre long. Being clipped by one should read
## as being hit by it.
const HIT_RADIUS := 1.05
const LIFETIME := 5.0
const SPIN := 7.0
const BREAK_TINT := Color(0.35, 0.32, 0.28, 1.0)
const BREAK_SIZE := 0.85

var damage := 60.0
var knockback := 26.0
var lift := 7.0
var thrower: Node

## Built once and shared by every throw. See [method _stone_material].
static var _stone: ShaderMaterial

var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _spin_axis := Vector3.UP
var _mesh: MeshInstance3D


## Puts this rock in the air over [param planet] and sets it going, answering
## whether the throw was one that could be made. The thrower is skipped by the
## sweep so he cannot brain himself on his own throw.
##
## Built by the caller rather than by a static factory here, because a factory
## has to name this class to construct it. A script that names its own global
## class does not merely fail to find it while the project's class list is being
## rebuilt — it fails to compile, and it takes everything that preloads it down
## with it, which for this one is the boss.
func launch(planet: Planet, from: Vector3, at: Vector3, by: Node) -> bool:
	if planet == null or not from.is_finite() or not at.is_finite():
		return false
	name = "BigfootRock"
	_velocity = at
	thrower = by
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	planet.add_child(self)
	global_position = from
	return true


func _ready() -> void:
	_planet = get_parent() as Planet
	SPECIES.prepare()
	var mesh := SPECIES.near_mesh()
	if mesh == null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = _stone_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var bounds := mesh.get_aabb()
	var shrink := ACROSS / maxf(bounds.size.y, 0.01)
	_mesh.scale = Vector3.ONE * shrink
	# The quarry model stands on the ground, so its origin is under it. A thrown
	# rock turns about its middle.
	_mesh.position = -bounds.get_center() * shrink
	add_child(_mesh)
	var seed_from := global_position
	_spin_axis = Vector3(
		sin(seed_from.x * 1.7), cos(seed_from.y * 2.3), sin(seed_from.z * 1.1))
	if _spin_axis.length_squared() < 0.01:
		_spin_axis = Vector3.UP
	_spin_axis = _spin_axis.normalized()


## The species' paint on a single instance rather than on a field of them.
##
## Scattered rocks take their shade from per-instance data a lone MeshInstance3D
## has none of, so the shared material draws one at the dark bottom of the
## species' tone range — against the boss and the jungle floor that is a stone
## you cannot see coming. The copy is left at full tone and given enough rim to
## be picked out in flight; the colour paint carries over untouched.
static func _stone_material() -> ShaderMaterial:
	if _stone != null:
		return _stone
	SPECIES.prepare()
	var source := SPECIES.near_material()
	if source == null:
		return null
	_stone = source.duplicate(true) as ShaderMaterial
	_stone.set_shader_parameter(&"tone_variation", 0.0)
	_stone.set_shader_parameter(&"brightness", 1.1)
	_stone.set_shader_parameter(&"region_rim", 0.45)
	_stone.set_shader_parameter(&"specular", 0.18)
	return _stone


func _physics_process(delta: float) -> void:
	_live += delta
	if _live >= LIFETIME:
		queue_free()
		return
	var up := _up()
	_velocity -= up * _gravity() * delta
	var from := global_position
	var to := from + _velocity * delta
	if _mesh != null:
		_mesh.rotate(_spin_axis, SPIN * delta)

	var struck := _player_along(from, to)
	if struck != null:
		global_position = _nearest_on(from, to, _combat_position(struck))
		_strike(struck)
		return
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _blocker.is_valid():
		query.exclude = DamageHit.rid_list(_blocker)
	var landed := get_world_3d().direct_space_state.intersect_ray(query)
	if landed.is_empty():
		global_position = to
		return
	global_position = landed["position"]
	_shatter(landed.get("normal", up) as Vector3)


## Whoever this step of the flight passes through, or null. The capsule is the
## same shape the damage is dealt in, so what the rock looks like it hit and what
## it hits are the same test.
func _player_along(from: Vector3, to: Vector3) -> Node:
	var sweep := DamageHit.beam(from, to, HIT_RADIUS, 0.0)
	for player_variant: Variant in get_tree().get_nodes_in_group(
			&"network_players"):
		var player := player_variant as Node3D
		if player == null or not DamageHit.in_same_world(self, player):
			continue
		if player == thrower:
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		var bounds := 0.4
		if player.has_method(&"combat_radius"):
			bounds = float(player.call(&"combat_radius"))
		if sweep.reaches(_combat_position(player), bounds):
			return player
	return null


func _strike(player: Node) -> void:
	if _is_host() and player.has_method(&"apply_damage"):
		var along := _velocity.normalized() if _velocity.length_squared() > 0.01 \
			else -_up()
		var hit := DamageHit.impact(global_position, HIT_RADIUS, damage)
		hit.faction = DamageHit.Faction.ENEMY
		hit.target_peer = _peer_of(player)
		hit.parryable = true
		# Thrown hard enough to take you off your feet, which is the point of it
		# at range: the punch staggers, this one puts you down.
		hit.reaction = DamageHit.Reaction.RAGDOLL
		hit.world_impulse = along * knockback + _up() * lift
		hit.ability_id = "bigfoot_rock"
		hit.set_source(thrower)
		player.call(&"apply_damage", hit)
	_shatter(_up())


func _shatter(normal: Vector3) -> void:
	var effects := get_tree().get_first_node_in_group(&"impact_break_effects")
	if effects != null and effects.has_method(&"play_break"):
		var facing := normal if normal.length_squared() > 0.0001 else _up()
		effects.call(&"play_break", global_position, facing,
			_velocity.length(), BREAK_SIZE, BREAK_TINT,
			ImpactBreakEffects.Preset.CRYSTAL)
	queue_free()


func _nearest_on(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var along := to - from
	var span := along.length_squared()
	if span < 0.000001:
		return from
	return from + along * clampf((point - from).dot(along) / span, 0.0, 1.0)


func _combat_position(player: Node) -> Vector3:
	if player.has_method(&"combat_position"):
		return player.call(&"combat_position")
	return (player as Node3D).global_position


func _peer_of(player: Node) -> int:
	if player.has_method(&"combat_peer_id"):
		return int(player.call(&"combat_peer_id"))
	return int(player.get("peer_id"))


func _up() -> Vector3:
	if _planet != null:
		return _planet.up_at(global_position)
	return Vector3.UP


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
