class_name CrawlerRangerShot
extends Node3D

## Led purple orb the ranger throws. Every peer flies its own copy from the
## launch the host published; only the host turns a hit into damage.

const LIFETIME := 5.2
const CORE_COLOR := Color(0.92, 0.72, 1.0)
const GLOW_COLOR := Color(0.62, 0.22, 1.0)
const HALO_COLOR := Color(0.48, 0.10, 0.95, 0.42)

var damage := 14.0
var gravity := 16.0
var shot_speed := 16.0
var ball_radius := 0.62
var hit_radius := 1.45
var knockback := 6.0
var parryable := true
var shooter: Node

var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
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
	name = "CrawlerRangerShot"
	_velocity = along
	shooter = by
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	host.add_child(self)
	global_position = from
	return true


func _ready() -> void:
	_planet = get_parent() as Planet
	var mesh := SphereMesh.new()
	mesh.radius = ball_radius
	mesh.height = ball_radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 10
	_core = MeshInstance3D.new()
	_core.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CORE_COLOR
	material.emission_enabled = true
	material.emission = GLOW_COLOR
	material.emission_energy_multiplier = 6.4
	_core.material_override = material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = ball_radius * 1.55
	halo_mesh.height = ball_radius * 3.1
	halo_mesh.radial_segments = 16
	halo_mesh.rings = 8
	_halo = MeshInstance3D.new()
	_halo.mesh = halo_mesh
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_color = HALO_COLOR
	halo_material.emission_enabled = true
	halo_material.emission = GLOW_COLOR
	halo_material.emission_energy_multiplier = 3.8
	_halo.material_override = halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	var lamp := OmniLight3D.new()
	lamp.light_color = GLOW_COLOR
	lamp.light_energy = 4.6
	lamp.omni_range = maxf(ball_radius * 9.0, 4.5)
	lamp.shadow_enabled = false
	add_child(lamp)


func _physics_process(delta: float) -> void:
	_live += delta
	if is_instance_valid(_halo):
		var pulse := 1.0 + sin(_live * 11.0) * 0.10
		_halo.scale = Vector3.ONE * pulse
	if _live >= LIFETIME:
		queue_free()
		return
	var up := _up()
	_velocity -= up * maxf(gravity, 0.0) * delta
	var from := global_position
	var to := from + _velocity * delta
	var struck := _player_along(from, to)
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


func _player_along(from: Vector3, to: Vector3) -> Node:
	var sweep := DamageHit.beam(from, to, hit_radius, 0.0)
	if not is_inside_tree():
		return null
	for player_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := player_variant as Node3D
		if player == null or player == shooter \
				or not DamageHit.in_same_world(self, player):
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		var bounds := 0.4
		if player.has_method(&"combat_radius"):
			bounds = float(player.call(&"combat_radius"))
		if sweep.reaches(_combat_position(player), bounds):
			return player
	return null


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
	var locked := DamageHit.game_world_of(self) != null
	for player_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := player_variant as Node
		if player == null or player == shooter \
				or not player.has_method(&"apply_damage"):
			continue
		if locked and not DamageHit.in_same_world(self, player):
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		var bounds := 0.4
		if player.has_method(&"combat_radius"):
			bounds = float(player.call(&"combat_radius"))
		if not blast.reaches(_combat_position(player), bounds):
			continue
		player.call(&"apply_damage", blast.resolved_for(player))


func _make_blast(at: Vector3) -> DamageHit:
	var along := _velocity.normalized() \
		if _velocity.length_squared() > 0.01 else -_up()
	var blast := DamageHit.area(
		at, blast_radius(), damage, CrawlerRules.RANGER_SHOT_AOE_FALLOFF)
	blast.faction = DamageHit.Faction.ENEMY
	blast.parryable = parryable
	blast.reaction = DamageHit.Reaction.STAGGER
	blast.world_impulse = along * knockback * 0.35
	blast.radial_impulse = knockback * 0.7
	blast.radial_lift = knockback * 0.18
	blast.affects_flora = false
	blast.ability_id = "crawler_ranger_shot"
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
	if player.has_method(&"combat_position"):
		return player.call(&"combat_position")
	return (player as Node3D).global_position


func _up() -> Vector3:
	if _planet != null:
		return _planet.up_at(global_position)
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
