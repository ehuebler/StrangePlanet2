class_name FaunaMob
extends CharacterBody3D

## One live fauna instance.
##
## The host owns AI, movement, health, and attacks. Other peers interpolate the
## compact state published by FaunaSpawner while running the same procedural
## walk/roll/slap presentation locally.

signal health_changed(current: float, maximum: float)
signal died
signal respawned

enum MotionState {
	IDLE,
	WALK,
	RUN,
	ATTACK,
	DEAD,
	## Standing still with the head down, feeding.
	GRAZE,
	## Running away, in leaps for species that bound.
	FLEE,
	## Circling whoever hurt it while staying turned toward them.
	STRAFE,
}

const SPIT := preload("res://game/fauna/fauna_spit.gd")

const STATE_SYNC_INTERVAL := 0.1
const CLIENT_FOLLOW_SPEED := 15.0
const DAMAGE_FLASH_SECONDS := 0.14
const BODY_SLAP_RECOVERY := 0.48
## How long the spit clip stays up after the ball leaves, and how long a flinch
## is shown. Both are presentation timers, replicated so clients match the host.
const SPIT_RECOVERY := 0.42
const HIT_CLIP_SECONDS := 0.45
const FLOOR_CLEARANCE := 0.025
const THINK_INTERVAL := 0.14
const SURFACE_GUARD_INTERVAL := 0.12
const CONTACT_SCAN_INTERVAL := 0.1
## Prism-Coil is a squat cylinder: its long-axis half length is about 44% of
## its authored height after the asset is turned to face down the travel axis.
const END_OVER_END_HALF_LENGTH_SHARE := 0.44
## One planted-end transfer advances by the full end-to-end body length.
const END_OVER_END_STEP_SHARE := END_OVER_END_HALF_LENGTH_SHARE * 2.0
const END_OVER_END_STRETCH := 0.20
const END_OVER_END_SQUASH := 0.10

var species: FaunaSpecies
var mob_id := ""
var spawn_seed := 1

var _spawner: Node
var _planet: Planet
var _initial_transform := Transform3D.IDENTITY
var _spawn_transform := Transform3D.IDENTITY
var _biome_tint := Color.WHITE
var _instance_height := 1.0
var _maximum_health := 1.0
var _health := 1.0
var _alive := true
var _lassoed := false
var _lasso_source_peer := 0

var _collision: CollisionShape3D
var _visual_root: Node3D
var _visual_pivot: Node3D
var _model_holder: Node3D
var _runtime_materials: Array[ShaderMaterial] = []
var _animator: AnimationPlayer
var _current_clip := ""

var _motion_state: MotionState = MotionState.IDLE
var _target_peer := 0
var _attack_elapsed := 0.0
var _attack_impact_done := false
var _attack_cooldown_left := 0.0
var _respawn_left := 0.0
var _alert_left := 0.0
var _wander_left := 0.0
var _wander_heading := Vector3.ZERO
var _wander_step := 0
var _clock := 0.0
var _sync_left := 0.0
var _flash_left := 0.0
var _last_flash_share := -1.0
var _knockback_left := 0.0
var _think_left := 0.0
var _surface_guard_left := 0.0
var _contact_scan_left := 0.0
var _cached_nearest_player: Node3D
var _player_gap := 0.0
var _physics_body := false
var _far_coast := 0.0
var _cached_up := Vector3.ZERO
var _cached_up_at := Vector3.INF
var _graze_left := 0.0
var _provoked_left := 0.0
var _spit_windup_left := 0.0
var _spit_show_left := 0.0
var _hit_show_left := 0.0
var _strafe_sign := 1.0

var _network_transform := Transform3D.IDENTITY
var _network_velocity := Vector3.ZERO
var _has_network_transform := false
var _last_visual_position := Vector3.INF
var _roll_angle := 0.0
var _gait_phase := 0.0
var _gait_blend := 0.0
var _visual_attack_elapsed := 0.0
var _base_brightness := 1.0


func configure(definition: FaunaSpecies, id: String, seed: int,
		at_transform: Transform3D, biome_tint := Color.WHITE,
		owner: Node = null) -> void:
	species = definition
	mob_id = id
	spawn_seed = maxi(seed, 1)
	_initial_transform = at_transform
	_biome_tint = biome_tint
	_spawner = owner


func _ready() -> void:
	if species == null:
		push_error("FaunaMob '%s' was added without a FaunaSpecies" % name)
		set_process(false)
		set_physics_process(false)
		return
	_planet = _find_planet()
	var rng := RandomNumberGenerator.new()
	rng.seed = spawn_seed
	_instance_height = species.height * rng.randf_range(
		1.0 - species.height_variation, 1.0 + species.height_variation)
	_maximum_health = maxf(species.health_for(_instance_height), 1.0)
	_health = _maximum_health
	_build_collision()
	_build_visuals(rng)
	add_to_group(DamageHit.COMBATANT_GROUP)
	add_to_group(&"fauna_mobs")
	global_transform = _initial_transform
	_spawn_transform = global_transform
	_network_transform = global_transform
	_set_alive_presentation()
	_choose_wander_heading()
	_think_left = _seed_unit(83) * THINK_INTERVAL
	_surface_guard_left = _seed_unit(97) * SURFACE_GUARD_INTERVAL
	_contact_scan_left = _seed_unit(109) * CONTACT_SCAN_INTERVAL
	_strafe_sign = 1.0 if _seed_unit(127) < 0.5 else -1.0


func _process(delta: float) -> void:
	_clock += delta
	_flash_left = maxf(_flash_left - delta, 0.0)
	_spit_show_left = maxf(_spit_show_left - delta, 0.0)
	_hit_show_left = maxf(_hit_show_left - delta, 0.0)
	if _motion_state == MotionState.ATTACK:
		_visual_attack_elapsed += delta
	else:
		_visual_attack_elapsed = 0.0
	_animate_visual(delta)
	_update_damage_flash()


func _physics_process(delta: float) -> void:
	if not _is_host():
		if not _lassoed:
			_follow_network(delta)
		return
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)
	_alert_left = maxf(_alert_left - delta, 0.0)
	_contact_scan_left = maxf(_contact_scan_left - delta, 0.0)
	_provoked_left = maxf(_provoked_left - delta, 0.0)
	if not _alive:
		_respawn_left = maxf(_respawn_left - delta, 0.0)
		if _respawn_left <= 0.0:
			_respawn()
		_publish_event()
		return
	if _lassoed:
		return
	if _player_gap > 72.0 and _provoked_left <= 0.0 and _alert_left <= 0.0 \
			and _spit_windup_left <= 0.0 and _knockback_left <= 0.0 \
			and _motion_state != MotionState.ATTACK:
		_far_coast -= delta
		if _far_coast > 0.0:
			_glide(delta, _up())
			_tick_surface_guard(delta)
			_sync_left -= delta
			if _sync_left <= 0.0:
				_sync_left = STATE_SYNC_INTERVAL
				_publish_state()
			return
		_far_coast = 0.22

	# The spit leaves the muzzle on its own clock, so a creature that stops
	# circling mid-throw still finishes the throw it has already started.
	if _spit_windup_left > 0.0:
		_spit_windup_left = maxf(_spit_windup_left - delta, 0.0)
		if _spit_windup_left <= 0.0:
			_launch_spit()

	if _knockback_left > 0.0:
		_knockback_left = maxf(_knockback_left - delta, 0.0)
		var up := _up()
		up_direction = up
		var gravity := float(ProjectSettings.get_setting(
			"physics/3d/default_gravity", 34.0))
		velocity -= up * gravity * delta
		move_and_slide()
		if is_on_floor():
			velocity = velocity.move_toward(Vector3.ZERO, 16.0 * delta)
	elif _motion_state == MotionState.ATTACK:
		_update_body_slap(delta)
	else:
		_update_behaviour(delta)
	if species.attack_style == FaunaSpecies.AttackStyle.CONTACT \
			and species.has_move(FaunaSpecies.Move.ATTACK) \
			and _contact_scan_left <= 0.0:
		_contact_scan_left = CONTACT_SCAN_INTERVAL * lerpf(
			0.85, 1.15, _seed_unit(_wander_step * 23 + 109))
		_try_contact_damage()
	_tick_surface_guard(delta)

	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = STATE_SYNC_INTERVAL
		_publish_state()


func _update_behaviour(delta: float) -> void:
	var target := _nearest_player_for_behaviour(delta)
	var toward_target := Vector3.ZERO
	var target_gap := INF
	if target != null:
		toward_target = _flat_direction(
			target.global_position - global_position, _up())
		target_gap = global_position.distance_to(target.global_position) \
			- combat_radius() - _combat_radius_of(target)

	# A creature that has been hurt stands its ground for a while, whatever its
	# temperament: it circles whoever hurt it and answers with its own attack.
	if _provoked_left > 0.0:
		var provoker := _player_for_peer(_target_peer)
		if provoker != null:
			_strafe(provoker, delta)
			return
		_provoked_left = 0.0

	if species.is_hostile() and target != null \
			and target_gap <= species.notice_range:
		_target_peer = _peer_id(target)
		if species.attack_style == FaunaSpecies.AttackStyle.BODY_SLAP \
				and species.has_move(FaunaSpecies.Move.ATTACK) \
				and target_gap <= species.attack_range \
				and _attack_cooldown_left <= 0.0:
			_start_body_slap()
			_move(Vector3.ZERO, 0.0, delta)
			return
		_travel(toward_target, true, delta)
		return

	if not species.is_hostile() and target != null \
			and target_gap <= species.flee_range:
		_target_peer = _peer_id(target)
		_alert_left = 1.4
		var escape := _flat_direction(
			global_position - target.global_position, _up())
		_flee(escape, delta)
		return

	_target_peer = 0
	_wander(delta)


## Runs from something, in leaps for species whose escape is a series of hops.
func _flee(direction: Vector3, delta: float) -> void:
	_graze_left = 0.0
	if not species.has_move(FaunaSpecies.Move.RUN):
		_travel(direction, false, delta)
		return
	_move(direction, species.run_speed, delta)
	_set_motion_state(MotionState.FLEE if species.bound_when_fleeing \
		else MotionState.RUN)


## Circles a threat at arm's length, facing it, spitting when the throw is ready.
func _strafe(target: Node3D, delta: float) -> void:
	_graze_left = 0.0
	_target_peer = _peer_id(target)
	var up := _up()
	var outward := _flat_direction(
		global_position - target.global_position, up)
	if outward.is_zero_approx():
		outward = _flat_direction(-global_basis.z, up)
	var gap := global_position.distance_to(target.global_position)
	var ring := maxf(species.strafe_radius, 0.5)
	# Circling, plus whatever sideways correction holds the ring: too close and
	# it backs off, too far and it closes, so it never spirals in or away.
	var around := up.cross(outward).normalized() * _strafe_sign
	var heading := _flat_direction(
		around - outward * clampf((gap - ring) / ring, -1.0, 1.0), up)
	_move(heading, species.strafe_speed, delta, -outward)
	_set_motion_state(MotionState.STRAFE)
	_try_spit(gap)


func _try_spit(gap: float) -> void:
	if species.attack_style != FaunaSpecies.AttackStyle.SPIT \
			or not species.has_move(FaunaSpecies.Move.ATTACK) \
			or _spit_windup_left > 0.0 or _attack_cooldown_left > 0.0 \
			or gap > maxf(species.notice_range, 1.0):
		return
	_attack_cooldown_left = maxf(species.attack_cooldown, 0.05)
	_spit_windup_left = maxf(species.attack_windup, 0.05)
	_spit_show_left = _spit_windup_left + SPIT_RECOVERY
	_publish_event()


func _wander(delta: float) -> void:
	if _graze_left > 0.0:
		_graze_left = maxf(_graze_left - delta, 0.0)
		_move(Vector3.ZERO, 0.0, delta)
		_set_motion_state(MotionState.GRAZE)
		return
	_wander_left -= delta
	var home := _flat_direction(
		_spawn_transform.origin - global_position, _up())
	var from_home := global_position.distance_to(_spawn_transform.origin)
	if from_home > maxf(species.wander_radius, 0.5):
		_travel(home, false, delta)
		return
	if _wander_left <= 0.0:
		_choose_wander_heading()
	var rest_share := 0.22 + 0.18 * _seed_unit(_wander_step * 31 + 7)
	if _wander_left <= species.wander_pause * rest_share:
		_move(Vector3.ZERO, 0.0, delta)
		_set_motion_state(MotionState.IDLE)
		return
	var heading := _flat_direction(_wander_heading, _up())
	if not home.is_zero_approx() and species.wander_radius > 0.0:
		heading = heading.lerp(
			home, clampf(from_home / species.wander_radius, 0.0, 0.72))
	_travel(heading.normalized(), false, delta)


func _travel(direction: Vector3, prefer_run: bool, delta: float) -> void:
	var running := species.has_move(FaunaSpecies.Move.RUN) \
		and (prefer_run or not species.has_move(FaunaSpecies.Move.WALK))
	var walking := species.has_move(FaunaSpecies.Move.WALK)
	if not running and not walking:
		_move(Vector3.ZERO, 0.0, delta)
		_set_motion_state(MotionState.IDLE)
		return
	_move(direction, species.run_speed if running else species.walk_speed, delta)
	_set_motion_state(MotionState.RUN if running else MotionState.WALK)


func _choose_wander_heading() -> void:
	_wander_step += 1
	var up := _up()
	var basis_forward := _flat_direction(-global_basis.z, up)
	if basis_forward.is_zero_approx():
		basis_forward = _tangent_axes(up)[0]
	var angle := lerpf(-PI * 0.82, PI * 0.82,
		_seed_unit(_wander_step * 47 + 13))
	_wander_heading = basis_forward.rotated(up, angle)
	_wander_left = species.wander_pause + lerpf(1.4, 4.5,
		_seed_unit(_wander_step * 59 + 23))
	if species.graze \
			and _seed_unit(_wander_step * 37 + 11) < species.graze_chance:
		_graze_left = maxf(species.graze_seconds, 0.0) * lerpf(
			0.7, 1.3, _seed_unit(_wander_step * 41 + 19))


## Moves along [param direction], turning to face it unless [param face] says to
## look somewhere else — which is what lets a creature circle sideways while
## keeping its head, and its aim, on whatever it is circling.
func _move(direction: Vector3, speed: float, delta: float,
		face := Vector3.ZERO) -> void:
	var up := _up()
	up_direction = up
	var desired := Vector3.ZERO
	if speed > 0.0 and not direction.is_zero_approx():
		direction = _flat_direction(direction, up)
		desired = direction * speed
		_face_along(face if not face.is_zero_approx() else direction, up, delta)
	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	horizontal = horizontal.move_toward(
		desired, maxf(species.move_acceleration, 0.0) * delta)
	if is_on_floor() or not _physics_body:
		vertical = Vector3.ZERO
	else:
		var gravity := float(ProjectSettings.get_setting(
			"physics/3d/default_gravity", 34.0))
		vertical -= up * gravity * delta
	velocity = horizontal + vertical
	if not _physics_body:
		_glide(delta, up)
		return
	move_and_slide()


## Walks the height field instead of sweeping the capsule through the world.
##
## Used only past the species' physics_within, where there is no player near
## enough to see the creature pass through a boulder it should have walked around,
## and where the capsule sweep would otherwise be paying for distant terrain.
func _glide(delta: float, up: Vector3) -> void:
	var horizontal := velocity - up * velocity.dot(up)
	global_position += horizontal * delta
	velocity = horizontal
	_plant_on_height_field()


func _plant_on_height_field() -> void:
	if _planet == null or _planet.shape == null:
		return
	var local := _planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return
	var direction := local.normalized()
	var surface := _planet.shape.surface_point(
		direction, _planet.finest_spacing())
	global_position = _planet.to_global(
		direction * (surface.length() + FLOOR_CLEARANCE))


## Whether this creature is near enough to a player to be worth simulating as a
## physics body. The band it leaves on is wider than the one it enters on, so a
## creature pacing the boundary does not swap every time it thinks.
func _refresh_simulation_detail() -> void:
	if species.physics_within <= 0.0:
		_physics_body = true
		return
	var was_physics := _physics_body
	_physics_body = _player_gap <= species.physics_within \
		* (1.35 if was_physics else 1.0)
	if was_physics and not _physics_body:
		# Land on the height field once on the way out, so the first glide starts
		# from the ground rather than from wherever the capsule came to rest.
		_plant_on_height_field()


func _start_body_slap() -> void:
	if species.locomotion == FaunaSpecies.Locomotion.END_OVER_END:
		# Attack from a planted end instead of freezing halfway through a flip.
		_roll_angle = roundf(_roll_angle / PI) * PI
	_set_motion_state(MotionState.ATTACK)
	_attack_elapsed = 0.0
	_visual_attack_elapsed = 0.0
	_attack_impact_done = false
	_attack_cooldown_left = maxf(species.attack_cooldown, 0.05)
	velocity = Vector3.ZERO
	_publish_event()


func _update_body_slap(delta: float) -> void:
	velocity = Vector3.ZERO
	_attack_elapsed += delta
	_visual_attack_elapsed = _attack_elapsed
	var target := _player_for_peer(_target_peer)
	if target != null:
		_face_along(_flat_direction(
			target.global_position - global_position, _up()), _up(), delta)
	if not _attack_impact_done \
			and _attack_elapsed >= maxf(species.attack_windup, 0.0):
		_attack_impact_done = true
		_apply_body_slap()
	if _attack_elapsed >= species.attack_windup + BODY_SLAP_RECOVERY:
		_set_motion_state(MotionState.IDLE)
		_attack_elapsed = 0.0
		_attack_impact_done = false
		_publish_event()


func _apply_body_slap() -> void:
	var forward := _flat_direction(-global_basis.z, _up())
	var hit := DamageHit.cylinder(
		combat_position() - forward * combat_radius() * 0.25,
		combat_position() + forward * species.attack_range,
		maxf(species.attack_radius, 0.1), species.attack_damage)
	hit.faction = DamageHit.Faction.ENEMY
	hit.parryable = species.attack_parryable
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.world_impulse = forward * species.attack_knockback \
		+ _up() * species.attack_knockback * 0.2
	hit.ability_id = "fauna_body_slap"
	hit.set_source(self)
	DamageHit.apply_to_combatants(self, hit)


func _try_contact_damage() -> void:
	if _attack_cooldown_left > 0.0:
		return
	CrawlerMobSense.ensure_frame(get_tree())
	for player_variant: Variant in CrawlerMobSense.players():
		var player := player_variant as Node3D
		if player == null or not DamageHit.in_same_world(self, player) \
				or _player_dead(player):
			continue
		var gap := combat_position().distance_to(_combat_position_of(player)) \
			- combat_radius() - _combat_radius_of(player)
		if gap > maxf(species.attack_range, 0.05):
			continue
		var away := _flat_direction(
			player.global_position - global_position, _up())
		var hit := DamageHit.impact(
			_combat_position_of(player), maxf(species.attack_radius, 0.1),
			species.attack_damage)
		hit.faction = DamageHit.Faction.ENEMY
		hit.target_peer = _peer_id(player)
		hit.reaction = DamageHit.Reaction.KNOCKBACK
		hit.world_impulse = away * species.attack_knockback \
			+ _up() * species.attack_knockback * 0.12
		hit.ability_id = "fauna_quills"
		hit.projectile = true
		hit.set_source(self)
		DamageHit.apply_to_combatants(self, hit)
		_attack_cooldown_left = maxf(species.attack_cooldown, 0.05)
		_flash_left = maxf(_flash_left, 0.06)
		_publish_event()
		return


## Throws one ball of liquid from the muzzle, led so a walking target runs into
## it and lofted so gravity brings it back down onto them.
func _launch_spit() -> void:
	var target := _player_for_peer(_target_peer)
	if target == null or _planet == null:
		return
	var up := _up()
	var forward := _flat_direction(-global_basis.z, up)
	var from := global_position \
		+ up * _instance_height * species.spit_from_height_share \
		+ forward * _instance_height * species.spit_from_forward_share
	var at := _combat_position_of(target)
	var flight := from.distance_to(at) / maxf(species.spit_speed, 1.0)
	var lead: Variant = target.get(&"velocity")
	if lead is Vector3 and (lead as Vector3).is_finite():
		at += (lead as Vector3) * flight * 0.55
	var along := at - from + up * 0.5 * species.spit_gravity * flight * flight
	if along.is_zero_approx():
		return
	var launch := along.normalized() * species.spit_speed
	_spawn_spit(from, launch)
	_publish_event({"spit_from": from, "spit_launch": launch})


func _spawn_spit(from: Vector3, launch: Vector3) -> void:
	if _planet == null or not from.is_finite() or not launch.is_finite():
		return
	var ball := SPIT.new()
	ball.damage = species.attack_damage
	ball.knockback = species.attack_knockback
	ball.gravity = species.spit_gravity
	ball.ball_radius = species.spit_ball_radius
	ball.hit_radius = species.spit_hit_radius
	ball.tint = species.spit_color
	ball.glow = species.spit_glow
	ball.parryable = species.attack_parryable
	if not ball.launch(_planet, from, launch, self):
		ball.free()


func _face_along(direction: Vector3, up: Vector3, delta: float) -> void:
	if direction.is_zero_approx():
		return
	var target := _upright_basis(direction, up)
	var current_rotation := global_basis.orthonormalized().get_rotation_quaternion()
	var target_rotation := target.get_rotation_quaternion()
	var share := 1.0 - exp(-delta * maxf(species.turn_speed, 0.01))
	global_basis = Basis(current_rotation.slerp(
		target_rotation, clampf(share, 0.0, 1.0))).orthonormalized()


func _tick_surface_guard(delta: float) -> void:
	_surface_guard_left -= delta
	# A gliding creature is planted on the height field every tick already.
	if _surface_guard_left > 0.0 or is_on_floor() or not _physics_body:
		return
	# Stagger analytical terrain reads so a pack never samples on one frame.
	_surface_guard_left = SURFACE_GUARD_INTERVAL * lerpf(
		0.85, 1.15, _seed_unit(_wander_step * 17 + 97))
	_surface_guard()


func _surface_guard() -> void:
	if _planet == null or _planet.shape == null:
		return
	var local := _planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return
	var direction := local.normalized()
	var surface := _planet.shape.surface_point(
		direction, _planet.finest_spacing())
	var floor_radius := surface.length() + FLOOR_CLEARANCE
	if local.length() >= floor_radius:
		return
	global_position = _planet.to_global(direction * floor_radius)
	var up := (_planet.global_basis * direction).normalized()
	var inward := velocity.dot(up)
	if inward < 0.0:
		velocity -= up * inward


func _follow_network(delta: float) -> void:
	if not _has_network_transform:
		return
	var share := 1.0 - exp(-delta * CLIENT_FOLLOW_SPEED)
	global_transform = global_transform.interpolate_with(
		_network_transform, clampf(share, 0.0, 1.0))
	velocity = _network_velocity


func state_wire() -> Dictionary:
	return {
		"id": mob_id,
		"transform": global_transform,
		"velocity": velocity,
		"motion": int(_motion_state),
		"health": _health,
		"alive": _alive,
		"target_peer": _target_peer,
		"attack_elapsed": _attack_elapsed,
		"attack_cooldown": _attack_cooldown_left,
		"respawn_left": _respawn_left,
		"flash": _flash_left,
		"spit_show": _spit_show_left,
		"hit_show": _hit_show_left,
	}


func apply_network_state(wire: Dictionary, snap := false) -> void:
	var transform_value: Variant = wire.get("transform", global_transform)
	if transform_value is Transform3D:
		_network_transform = transform_value as Transform3D
		_has_network_transform = true
		if snap:
			global_transform = _network_transform
	var velocity_value: Variant = wire.get("velocity", Vector3.ZERO)
	if velocity_value is Vector3 and (velocity_value as Vector3).is_finite():
		_network_velocity = velocity_value as Vector3
	var previous_alive := _alive
	_motion_state = clampi(
		int(wire.get("motion", _motion_state)), 0, MotionState.size() - 1) \
		as MotionState
	_health = clampf(float(wire.get("health", _health)), 0.0, _maximum_health)
	_alive = bool(wire.get("alive", _alive))
	_target_peer = maxi(int(wire.get("target_peer", _target_peer)), 0)
	_attack_elapsed = maxf(float(wire.get(
		"attack_elapsed", _attack_elapsed)), 0.0)
	_visual_attack_elapsed = _attack_elapsed
	_attack_cooldown_left = maxf(float(wire.get(
		"attack_cooldown", _attack_cooldown_left)), 0.0)
	_respawn_left = maxf(float(wire.get("respawn_left", _respawn_left)), 0.0)
	_flash_left = maxf(float(wire.get("flash", _flash_left)), _flash_left)
	_spit_show_left = maxf(float(wire.get("spit_show", 0.0)), 0.0)
	_hit_show_left = maxf(float(wire.get("hit_show", 0.0)), 0.0)
	# A thrown ball is an event, not a state: the host sends the launch it made
	# and every peer flies its own copy from it, the way the boss's rocks work.
	var spit_from: Variant = wire.get("spit_from")
	var spit_launch: Variant = wire.get("spit_launch")
	if spit_from is Vector3 and spit_launch is Vector3:
		_spawn_spit(spit_from as Vector3, spit_launch as Vector3)
	if previous_alive != _alive:
		_set_alive_presentation()
	health_changed.emit(_health, _maximum_health)


func _publish_state() -> void:
	if not _should_publish() \
			or not _spawner.has_method(&"publish_actor_state"):
		return
	_spawner.call(&"publish_actor_state", mob_id, state_wire())


func _publish_event(extra := {}) -> void:
	if not _should_publish() \
			or not _spawner.has_method(&"publish_actor_event"):
		return
	var wire := state_wire()
	wire.merge(extra, true)
	_spawner.call(&"publish_actor_event", mob_id, wire)


func _should_publish() -> bool:
	return _spawner != null \
		and _spawner.has_method(&"should_publish_actor_state") \
		and bool(_spawner.call(&"should_publish_actor_state"))


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _alive or not _is_host() \
			or hit.faction != DamageHit.Faction.PLAYER:
		return 0.0
	var delivered := species.damage_taken(
		hit.amount if is_finite(hit.amount) else 0.0)
	var actual := minf(delivered, _health)
	if actual <= 0.0:
		return 0.0
	_health -= actual
	if hit.reaction == DamageHit.Reaction.KNOCKBACK \
			or hit.reaction == DamageHit.Reaction.RAGDOLL:
		var impulse := hit.world_impulse \
			if hit.world_impulse.is_finite() else Vector3.ZERO
		velocity += impulse
		_knockback_left = maxf(_knockback_left, 0.75)
		_set_motion_state(MotionState.IDLE)
	_flash_left = DAMAGE_FLASH_SECONDS
	_hit_show_left = HIT_CLIP_SECONDS
	_alert_left = 2.5
	# Being hurt is what turns a peaceable animal into one that fights back, and
	# it fights back at whoever actually hurt it rather than the nearest player.
	if species.provoked_seconds > 0.0 and hit.source_peer > 0:
		_provoked_left = species.provoked_seconds
		_target_peer = hit.source_peer
		_graze_left = 0.0
	health_changed.emit(_health, _maximum_health)
	if _health <= 0.0:
		_die()
	_publish_event()
	return actual


func _die() -> void:
	_alive = false
	_lassoed = false
	_lasso_source_peer = 0
	_provoked_left = 0.0
	_spit_windup_left = 0.0
	_graze_left = 0.0
	_motion_state = MotionState.DEAD
	_respawn_left = maxf(species.respawn_delay, 0.0)
	velocity = Vector3.ZERO
	_set_alive_presentation()
	died.emit()


func _respawn() -> void:
	_alive = true
	_lassoed = false
	_lasso_source_peer = 0
	_health = _maximum_health
	_respawn_left = 0.0
	_attack_cooldown_left = 0.0
	_attack_elapsed = 0.0
	_target_peer = 0
	_provoked_left = 0.0
	_spit_windup_left = 0.0
	_spit_show_left = 0.0
	_hit_show_left = 0.0
	_graze_left = 0.0
	_motion_state = MotionState.IDLE
	global_transform = _spawn_transform
	_network_transform = global_transform
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_set_alive_presentation()
	health_changed.emit(_health, _maximum_health)
	respawned.emit()


func _build_collision() -> void:
	var radius := maxf(_instance_height * species.collision_radius_share, 0.08)
	var body_height := maxf(
		_instance_height * species.collision_height_share, radius * 2.0)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = body_height
	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	_collision.position = Vector3.UP * body_height * 0.5
	_collision.shape = capsule
	add_child(_collision)
	floor_snap_length = maxf(_instance_height * 0.18, 0.12)
	floor_max_angle = deg_to_rad(maxf(species.max_slope, 1.0))
	# The same margin the player and Bigfoot carry, and for the same reason: at
	# Godot's default of 1 mm, resolving a capsule against ground made of a large
	# triangle soup takes tens of milliseconds per call. A creature built in code
	# does not inherit the setting from a .tscn, so it is set here.
	safe_margin = 0.04


func _build_visuals(rng: RandomNumberGenerator) -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "Visuals"
	add_child(_visual_root)
	_visual_pivot = Node3D.new()
	_visual_pivot.name = "MotionPivot"
	_visual_root.add_child(_visual_pivot)
	_model_holder = Node3D.new()
	_model_holder.name = "Model"
	_visual_pivot.add_child(_model_holder)

	var centred_motion := species.locomotion \
		in [FaunaSpecies.Locomotion.ROLLER,
			FaunaSpecies.Locomotion.END_OVER_END]
	var pivot_height := _instance_height * 0.5 if centred_motion else 0.0
	_visual_pivot.position.y = pivot_height
	_model_holder.position.y = -pivot_height
	if species.locomotion == FaunaSpecies.Locomotion.END_OVER_END:
		# The generated spring's cylinder axis is local X. Point that axis down
		# actor-forward (-Z) so it travels lengthwise instead of as a wheel.
		_model_holder.rotation.y = PI * 0.5
	var model := species.model.instantiate()
	_model_holder.add_child(model)
	var authored := maxf(species.height, 0.01)
	_model_holder.scale = Vector3.ONE * (_instance_height / authored)

	var tint := species.variant_tint_a.lerp(
		species.variant_tint_b, rng.randf())
	if species.terrain_tint:
		tint = tint.lerp(_biome_tint, species.biome_tint_strength)
	_base_brightness = species.brightness * rng.randf_range(0.94, 1.06)
	for node_variant: Variant in model.find_children(
			"*", "MeshInstance3D", true, false):
		var mesh_instance := node_variant as MeshInstance3D
		if mesh_instance == null:
			continue
		var runtime := species.instance_material(tint, _base_brightness)
		if runtime == null:
			continue
		mesh_instance.material_override = runtime
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_runtime_materials.append(runtime)
	if species.skeletal_clips:
		_bind_animator(model)


## Finds the clips the model's GLB was exported with and marks the ones that are
## meant to run forever as looping. The Animation resources are shared by every
## creature of this species, which is why the loop is set here and not per frame.
func _bind_animator(model: Node) -> void:
	_animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animator == null:
		push_warning("%s has no AnimationPlayer to play %s" % [
			species.species_id, species.clip_idle])
		return
	_animator.playback_default_blend_time = species.clip_blend
	for clip in [species.clip_idle, species.clip_walk, species.clip_run,
			species.clip_graze, species.clip_bound, species.clip_strafe]:
		if _animator.has_animation(clip):
			_animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _animate_visual(delta: float) -> void:
	if _visual_pivot == null or species == null:
		return
	var moved := 0.0
	if _last_visual_position.is_finite():
		moved = global_position.distance_to(_last_visual_position)
	_last_visual_position = global_position
	var speed := moved / maxf(delta, 0.0001)
	if species.skeletal_clips:
		_animate_clips(speed)
		return
	var moving := _motion_state == MotionState.WALK \
		or _motion_state == MotionState.RUN
	var attack_duration := maxf(
		species.attack_windup + BODY_SLAP_RECOVERY, 0.01)
	var attack_progress := clampf(
		_visual_attack_elapsed / attack_duration, 0.0, 1.0)
	var gait_moving := moving and speed > 0.04
	if species.quadruped_gait:
		_gait_blend = move_toward(
			_gait_blend, 1.0 if gait_moving else 0.0, delta * 7.5)
		if gait_moving:
			var stride := maxf(
				_instance_height * species.gait_stride_share, 0.08)
			_gait_phase = fposmod(
				_gait_phase + moved / stride * TAU, TAU)
		_update_gait_materials()

	var centred_motion := species.locomotion \
		in [FaunaSpecies.Locomotion.ROLLER,
			FaunaSpecies.Locomotion.END_OVER_END]
	var pivot_height := _instance_height * 0.5 if centred_motion else 0.0
	_visual_pivot.position = Vector3.UP * pivot_height
	_visual_pivot.rotation = Vector3.ZERO
	_visual_pivot.scale = Vector3.ONE
	if species.locomotion == FaunaSpecies.Locomotion.ROLLER:
		if moving:
			_roll_angle = fmod(_roll_angle + moved \
				/ maxf(_instance_height * 0.48, 0.08), TAU)
		var slap := 0.0
		if _motion_state == MotionState.ATTACK:
			var strike := sin(attack_progress * PI)
			var recoil := sin(attack_progress * TAU) * 0.22
			slap = (strike + recoil) * deg_to_rad(62.0)
			_visual_pivot.scale.x = 1.0 + strike * 0.22
			_visual_pivot.scale.y = 1.0 - strike * 0.12
		_visual_pivot.rotation = Vector3(
			_roll_angle, sin(_clock * 3.1 + spawn_seed) * 0.035, slap)
	elif species.locomotion == FaunaSpecies.Locomotion.END_OVER_END:
		_animate_end_over_end(moved, moving, delta, attack_progress)
	else:
		var speed_share := clampf(
			speed / maxf(species.run_speed, 0.1), 0.0, 1.0)
		var beat := _clock * lerpf(
			4.2, 10.5, speed_share) + spawn_seed * 0.17
		if species.quadruped_gait:
			if _gait_blend > 0.0:
				_visual_pivot.position.y += absf(sin(_gait_phase * 2.0)) \
					* _instance_height * species.body_bob_share * _gait_blend
				_visual_pivot.rotation.x = sin(_gait_phase) \
					* deg_to_rad(species.body_rock_degrees) * _gait_blend
				_visual_pivot.rotation.z = sin(_gait_phase * 2.0) \
					* deg_to_rad(species.body_rock_degrees * 0.22) \
					* _gait_blend
			else:
				_visual_pivot.scale.y = 1.0 + sin(
					_clock * 1.7 + spawn_seed) * 0.014
		elif moving:
			_visual_pivot.position.y += sin(beat * 2.0) \
				* _instance_height * lerpf(0.018, 0.045, speed_share)
			_visual_pivot.rotation.z = sin(beat) \
				* lerpf(0.035, 0.085, speed_share)
			_visual_pivot.rotation.x = cos(beat * 2.0) * 0.018
		else:
			_visual_pivot.scale.y = 1.0 + sin(
				_clock * 1.7 + spawn_seed) * 0.014
		if _motion_state == MotionState.ATTACK:
			var brace := sin(attack_progress * PI)
			_visual_pivot.scale = Vector3(
				1.0 + brace * 0.08, 1.0 - brace * 0.05, 1.0 + brace * 0.08)


## Plays the clip this creature's state calls for, at the rate its actual ground
## speed calls for. Every peer runs this from the state it has, so a client shows
## the same gait as the host without the clip itself being on the wire.
func _animate_clips(speed: float) -> void:
	if _animator == null:
		return
	var clip := _clip_for_state()
	var rate := species.clip_speed_scale
	if clip == species.clip_walk:
		rate *= _clip_rate(speed, species.walk_speed)
	elif clip == species.clip_run or clip == species.clip_bound:
		rate *= _clip_rate(speed, species.run_speed)
	elif clip == species.clip_strafe:
		rate *= _clip_rate(speed, species.strafe_speed)
	if clip != _current_clip:
		_current_clip = clip
		if _animator.has_animation(clip):
			_animator.play(clip, species.clip_blend)
	_animator.speed_scale = maxf(rate, 0.05)


func _clip_rate(speed: float, authored: float) -> float:
	return clampf(speed / maxf(authored, 0.1), 0.55, 2.0)


func _clip_for_state() -> String:
	if not _alive:
		return species.clip_dead
	if _spit_show_left > 0.0:
		return species.clip_attack
	if _hit_show_left > 0.0:
		return species.clip_hit
	match _motion_state:
		MotionState.GRAZE:
			return species.clip_graze
		MotionState.WALK:
			return species.clip_walk
		MotionState.RUN:
			return species.clip_run
		MotionState.FLEE:
			return species.clip_bound if species.bound_when_fleeing \
				else species.clip_run
		MotionState.STRAFE:
			return species.clip_strafe
		MotionState.ATTACK:
			return species.clip_attack
	return species.clip_idle


func _update_gait_materials() -> void:
	for runtime in _runtime_materials:
		runtime.set_shader_parameter(&"gait_phase", _gait_phase)
		runtime.set_shader_parameter(&"gait_amount", _gait_blend)


func _animate_end_over_end(moved: float, moving: bool, delta: float,
		attack_progress: float) -> void:
	if moving and moved > 0.0:
		var step_length := maxf(
			_instance_height * END_OVER_END_STEP_SHARE, 0.12)
		_roll_angle = fposmod(
			_roll_angle + moved * PI / step_length, TAU)
	elif _motion_state != MotionState.ATTACK:
		# Let the nearest end finish planting when AI changes to idle.
		var planted := roundf(_roll_angle / PI) * PI
		_roll_angle = move_toward(_roll_angle, planted, delta * 5.5)

	var half_turn := floorf(_roll_angle / PI)
	var transfer_share := fposmod(_roll_angle, PI) / PI
	# A smooth transfer briefly holds each end on the ground instead of reading
	# as another constant-speed wheel rotation.
	var eased_share := smoothstep(0.0, 1.0, transfer_share)
	var tumble := half_turn * PI + eased_share * PI
	var transfer := pow(sin(transfer_share * PI), 2.0)
	var axial_scale := 1.0 + transfer * END_OVER_END_STRETCH
	var radial_scale := 1.0 - transfer * END_OVER_END_SQUASH
	var attack_pitch := 0.0
	if _motion_state == MotionState.ATTACK:
		var strike_shape := sin(attack_progress * PI)
		axial_scale += strike_shape * 0.18
		radial_scale -= strike_shape * 0.08
		attack_pitch = _body_slap_pitch()

	_visual_pivot.scale = Vector3(
		radial_scale, radial_scale, axial_scale)
	var presented_angle := tumble + attack_pitch
	# Support mapping for a cylinder tipped around X: R|cos(a)| + L|sin(a)|.
	# This plants each end while allowing the centre to arc upward mid-transfer.
	var radial_support := _instance_height * 0.5 * radial_scale
	var base_axial_half := _instance_height * END_OVER_END_HALF_LENGTH_SHARE
	var axial_support := _instance_height \
		* END_OVER_END_HALF_LENGTH_SHARE * axial_scale
	_visual_pivot.position.y = radial_support * absf(cos(presented_angle)) \
		+ axial_support * absf(sin(presented_angle))
	if _motion_state != MotionState.ATTACK:
		# Counter the actor's linear centre motion so one end stays planted while
		# the spring vaults over it, returning to zero offset at each handoff.
		var step_length := _instance_height * END_OVER_END_STEP_SHARE
		_visual_pivot.position.z = step_length * transfer_share \
			+ axial_support * cos(eased_share * PI) - base_axial_half
	_visual_pivot.rotation = Vector3(
		presented_angle,
		sin(_clock * 2.4 + spawn_seed) * 0.025 * transfer,
		0.0)


func _body_slap_pitch() -> float:
	var impact_at := maxf(species.attack_windup, 0.05)
	var rear_at := impact_at * 0.58
	var rear := deg_to_rad(58.0)
	var follow_through := deg_to_rad(-18.0)
	if _visual_attack_elapsed <= rear_at:
		var share := smoothstep(
			0.0, 1.0, _visual_attack_elapsed / maxf(rear_at, 0.01))
		return lerpf(0.0, rear, share)
	if _visual_attack_elapsed <= impact_at:
		var share := smoothstep(0.0, 1.0,
			(_visual_attack_elapsed - rear_at)
			/ maxf(impact_at - rear_at, 0.01))
		return lerpf(rear, follow_through, share)
	var recovery_share := smoothstep(0.0, 1.0,
		(_visual_attack_elapsed - impact_at) / BODY_SLAP_RECOVERY)
	return lerpf(follow_through, 0.0, recovery_share)


func _update_damage_flash() -> void:
	var flash := _flash_left / DAMAGE_FLASH_SECONDS \
		if _flash_left > 0.0 else 0.0
	if is_equal_approx(flash, _last_flash_share):
		return
	_last_flash_share = flash
	for runtime in _runtime_materials:
		runtime.set_shader_parameter(
			&"brightness", _base_brightness * (1.0 + flash * 0.42))


func _set_alive_presentation() -> void:
	if _visual_root != null:
		_visual_root.visible = _alive
	if _collision != null:
		_collision.set_deferred(&"disabled", not _alive)


func _set_motion_state(next: MotionState) -> void:
	if _motion_state == next:
		return
	_motion_state = next
	if next != MotionState.ATTACK:
		_visual_attack_elapsed = 0.0


func combat_faction() -> int:
	# DamageHit's ENEMY value means a non-player combat target. Temperament is
	# intentionally separate: passive fauna remains damageable without aggroing.
	return DamageHit.Faction.ENEMY


func combat_peer_id() -> int:
	return 0


func combat_display_name() -> String:
	return species.display_name if species != null else "Alien Creature"


func combat_position() -> Vector3:
	return global_position + _up() * _instance_height * 0.5


func combat_radius() -> float:
	return maxf(_instance_height * species.combat_radius_share, 0.1) \
		if species != null else 0.5


func health() -> float:
	return _health


func maximum_health() -> float:
	return _maximum_health


func is_alive() -> bool:
	return _alive


func can_be_lassoed() -> bool:
	return _alive and not _lassoed


func begin_lasso(source: Node3D) -> bool:
	if not can_be_lassoed() or source == null:
		return false
	_lassoed = true
	_lasso_source_peer = int(source.get("peer_id")) \
		if source.get("peer_id") != null else 0
	_motion_state = MotionState.IDLE
	_attack_elapsed = 0.0
	_attack_impact_done = false
	_target_peer = 0
	_knockback_left = 0.0
	velocity = Vector3.ZERO
	return true


func lasso_simulate(motion: Vector3,
		next_velocity: Vector3) -> Dictionary:
	if not _is_host() or not _lassoed or not motion.is_finite() \
			or not next_velocity.is_finite():
		return {}
	var collision := move_and_collide(motion)
	velocity = next_velocity
	if collision == null:
		return {"collided": false}
	return {
		"collided": true,
		"normal": collision.get_normal(),
		"position": collision.get_position(),
		"collider": collision.get_collider(),
	}


func lasso_apply_network_motion(at: Transform3D,
		next_velocity: Vector3) -> void:
	if _is_host() or not _lassoed or not at.is_finite() \
			or not next_velocity.is_finite():
		return
	global_transform = at
	_network_transform = at
	velocity = next_velocity
	_network_velocity = next_velocity
	_has_network_transform = true
	reset_physics_interpolation()


func end_lasso(throw_velocity: Vector3) -> void:
	if not _lassoed:
		return
	_lassoed = false
	_lasso_source_peer = 0
	velocity = throw_velocity if throw_velocity.is_finite() else Vector3.ZERO
	_network_velocity = velocity
	_knockback_left = 0.75 if velocity.length_squared() > 1.0 else 0.0
	if _is_host():
		_publish_event()


func lasso_mass() -> float:
	return maxf(_instance_height * _instance_height, 0.45)


func is_lassoed() -> bool:
	return _lassoed


func motion_state() -> MotionState:
	return _motion_state


func instance_height() -> float:
	return _instance_height


## Whether this creature is currently sweeping its capsule against the world, as
## opposed to walking the height field because no player is near enough to care.
func is_physics_body() -> bool:
	return _physics_body


func biome_tint() -> Color:
	return _biome_tint


func glow_position() -> Vector3:
	return combat_position()


func _nearest_player_for_behaviour(delta: float) -> Node3D:
	_think_left -= delta
	if _think_left > 0.0:
		if _cached_nearest_player == null:
			return null
		if is_instance_valid(_cached_nearest_player) \
				and not _player_dead(_cached_nearest_player) \
				and DamageHit.in_same_world(self, _cached_nearest_player):
			return _cached_nearest_player
	_think_left = THINK_INTERVAL * lerpf(
		0.85, 1.15, _seed_unit(_wander_step * 29 + 83))
	_cached_nearest_player = _nearest_player()
	_player_gap = global_position.distance_to(
		_cached_nearest_player.global_position) \
		if _cached_nearest_player != null else INF
	_refresh_simulation_detail()
	return _cached_nearest_player


func _nearest_player() -> Node3D:
	if not is_inside_tree():
		return null
	CrawlerMobSense.ensure_frame(get_tree())
	var found := CrawlerMobSense.nearest_player(self)
	if found != null:
		return found
	return _scan_nearest_player()


func _player_for_peer(peer: int) -> Node3D:
	if peer <= 0 or not is_inside_tree():
		return null
	CrawlerMobSense.ensure_frame(get_tree())
	var found := _match_peer(CrawlerMobSense.players(), peer)
	if found != null:
		return found
	return _match_peer(get_tree().get_nodes_in_group(&"network_players"), peer)


func _match_peer(candidates: Array, peer: int) -> Node3D:
	for player_variant: Variant in candidates:
		var player := player_variant as Node3D
		if player != null and _peer_id(player) == peer \
				and DamageHit.in_same_world(self, player) \
				and not _player_dead(player):
			return player
	return null


func _scan_nearest_player() -> Node3D:
	var nearest: Node3D
	var nearest_squared := INF
	for player_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := player_variant as Node3D
		if player == null or not DamageHit.in_same_world(self, player) \
				or _player_dead(player):
			continue
		var away := global_position.distance_squared_to(player.global_position)
		if away < nearest_squared:
			nearest_squared = away
			nearest = player
	return nearest


func _peer_id(player: Node) -> int:
	return int(player.call(&"combat_peer_id")) \
		if player != null and player.has_method(&"combat_peer_id") else 0


func _player_dead(player: Node) -> bool:
	return bool(player.call(&"is_dead")) \
		if player != null and player.has_method(&"is_dead") else false


func _combat_position_of(target: Node3D) -> Vector3:
	return target.call(&"combat_position") as Vector3 \
		if target.has_method(&"combat_position") else target.global_position


func _combat_radius_of(target: Node) -> float:
	return maxf(float(target.call(&"combat_radius")), 0.0) \
		if target != null and target.has_method(&"combat_radius") else 0.0


func _find_planet() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		walk = walk.get_parent()
	return null


func _up() -> Vector3:
	if global_position.distance_squared_to(_cached_up_at) < 1.0 \
			and _cached_up.length_squared() > 0.0001:
		return _cached_up
	var up := global_basis.y.normalized()
	if _planet != null:
		var local := _planet.to_local(global_position)
		if local.length_squared() > 1.0:
			up = (_planet.global_basis * local.normalized()).normalized()
	_cached_up = up
	_cached_up_at = global_position
	return up


func _flat_direction(direction: Vector3, up: Vector3) -> Vector3:
	var flat := direction - up * direction.dot(up)
	return flat.normalized() if flat.length_squared() > 0.000001 \
		else Vector3.ZERO


func _tangent_axes(up: Vector3) -> Array[Vector3]:
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 \
		else Vector3.RIGHT).normalized()
	return [east, up.cross(east).normalized()]


func _upright_basis(forward: Vector3, up: Vector3) -> Basis:
	up = up.normalized()
	forward = _flat_direction(forward, up)
	if forward.is_zero_approx():
		forward = _tangent_axes(up)[0]
	var right := forward.cross(up).normalized()
	return Basis(right, up, right.cross(up).normalized()).orthonormalized()


func _seed_unit(salt: int) -> float:
	var mixed := int(spawn_seed) ^ (salt * 1103515245)
	mixed ^= mixed >> 13
	mixed *= 1274126177
	mixed ^= mixed >> 16
	return float(absi(mixed) % 1000003) / 1000003.0


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
