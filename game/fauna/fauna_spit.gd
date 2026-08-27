class_name FaunaSpit
extends Node3D

## A ball of liquid an animal spits at whoever provoked it.
##
## Built the same way as the boss's thrown rock, and for the same reasons: a body
## this small at this speed would tunnel through whatever it was aimed at, so it
## sweeps the ground it covered each frame instead — a ray for the world and a
## capsule against everyone standing in it, which is what lets it catch a player
## mid-jump. Every peer flies its own copy from the launch the host published, so
## the throw reads the same everywhere; only the host turns a hit into damage.
##
## See [method FaunaMob._launch_spit].

const LIFETIME := 3.0
## Rings out from the ball as it flies, so a wet ball reads as wet rather than as
## a bead of glass. Cheap: two spheres and one light, no particles in flight.
const HALO_SHARE := 2.4
const WOBBLE := 9.0
const SPLASH_TINT_MIX := 0.35

var damage := 8.0
var knockback := 4.0
var gravity := 9.0
var ball_radius := 0.13
var hit_radius := 0.6
var tint := Color(0.58, 0.93, 1.0)
var glow := 1.8
var parryable := true
var spitter: Node

var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D


## Puts this ball in the air over [param planet] and sets it going, answering
## whether the throw was one that could be made. The animal that spat it is
## skipped by the sweep, and built by the caller rather than by a static factory
## here, so this script never has to name its own global class to construct it.
func launch(planet: Planet, from: Vector3, along: Vector3, by: Node) -> bool:
	if planet == null or not from.is_finite() or not along.is_finite() \
			or along.is_zero_approx():
		return false
	name = "FaunaSpit"
	_velocity = along
	spitter = by
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	planet.add_child(self)
	global_position = from
	return true


func _ready() -> void:
	_planet = get_parent() as Planet
	var core_mesh := SphereMesh.new()
	core_mesh.radius = ball_radius
	core_mesh.height = ball_radius * 2.0
	core_mesh.radial_segments = 10
	core_mesh.rings = 6
	_core = MeshInstance3D.new()
	_core.mesh = core_mesh
	_core.material_override = _liquid_material(tint, 0.92, glow)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = ball_radius * HALO_SHARE * 0.5
	halo_mesh.height = ball_radius * HALO_SHARE
	halo_mesh.radial_segments = 8
	halo_mesh.rings = 5
	_halo = MeshInstance3D.new()
	_halo.mesh = halo_mesh
	_halo.material_override = _liquid_material(
		tint.lightened(0.2), 0.22, glow * 0.5)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)

	if glow > 0.0:
		var lamp := OmniLight3D.new()
		lamp.light_color = tint
		lamp.light_energy = glow * 0.8
		lamp.omni_range = maxf(ball_radius * 22.0, 2.0)
		lamp.shadow_enabled = false
		add_child(lamp)


## Unshaded and additive: the ball is its own light source, and one that has to
## be picked out against both a bright hillside and a night sky.
static func _liquid_material(colour: Color, alpha: float,
		energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = maxf(energy, 0.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.disable_receive_shadows = true
	return material


func _physics_process(delta: float) -> void:
	_live += delta
	if _live >= LIFETIME:
		queue_free()
		return
	var up := _up()
	_velocity -= up * maxf(gravity, 0.0) * delta
	var from := global_position
	var to := from + _velocity * delta
	if _halo != null:
		# A slight breathing wobble, so the ball does not read as a solid pellet.
		var pulse := 1.0 + sin(_live * WOBBLE) * 0.12
		_halo.scale = Vector3(pulse, 1.0 / pulse, pulse)

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
	_burst(landed.get("normal", up) as Vector3)


## Whoever this step of the flight passes through, or null. The capsule is the
## same shape the damage is dealt in, so what the ball looks like it hit and what
## it hits are the same test.
func _player_along(from: Vector3, to: Vector3) -> Node:
	var sweep := DamageHit.beam(from, to, hit_radius, 0.0)
	for player_variant: Variant in get_tree().get_nodes_in_group(
			&"network_players"):
		var player := player_variant as Node3D
		if player == null or player == spitter \
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


func _strike(player: Node) -> void:
	if _is_host() and player.has_method(&"apply_damage"):
		var along := _velocity.normalized() \
			if _velocity.length_squared() > 0.01 else -_up()
		var hit := DamageHit.impact(global_position, hit_radius, damage)
		hit.faction = DamageHit.Faction.ENEMY
		hit.target_peer = _peer_of(player)
		hit.parryable = parryable
		# A wet slap staggers rather than knocks down: this is an animal warning
		# somebody off, not the boss taking them off their feet.
		hit.reaction = DamageHit.Reaction.STAGGER
		hit.world_impulse = along * knockback + _up() * knockback * 0.2
		hit.ability_id = "fauna_spit"
		hit.set_source(spitter)
		player.call(&"apply_damage", hit)
	_burst(-_velocity.normalized() if _velocity.length_squared() > 0.01 \
		else _up())


func _burst(normal: Vector3) -> void:
	var effects := get_tree().get_first_node_in_group(&"impact_break_effects")
	if effects != null and effects.has_method(&"play_break"):
		var facing := normal if normal.length_squared() > 0.0001 else _up()
		effects.call(&"play_break", global_position, facing,
			_velocity.length() * 0.5, maxf(ball_radius * 3.4, 0.2),
			tint.lerp(Color(0.86, 0.97, 1.0), SPLASH_TINT_MIX),
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


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
