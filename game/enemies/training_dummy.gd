class_name TrainingDummy
extends CharacterBody3D

## Passive, respawning combat target anchored to an authored practice site.

signal health_changed(current: float, maximum: float)

@export var maximum_health := 12000.0
@export var respawn_delay := 2.0
## Any upright site on the same planet. Offsets below are measured in that
## anchor's tangent plane, then settled back onto the procedural terrain.
@export var anchor_path := NodePath("../VacationersLanding")
@export var anchor_right_offset := 8.0
@export var anchor_forward_offset := 0.0

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _visuals: Node3D = $Visuals
@onready var _label: Label3D = $Label

var _health := 0.0
var _alive := true
var _respawn_left := 0.0
var _spawn_direction := Vector3.UP
var _spawn_forward := Vector3.FORWARD
var _grappled := false
var _carrier: OnlinePlayer
var _lassoed := false
var _lasso_source_peer := 0
var _state_sequence := 0
var _last_state_sequence := 0
var _flash_left := 0.0
var _knockback_left := 0.0


func _ready() -> void:
	add_to_group(DamageHit.COMBATANT_GROUP)
	_health = maximum_health
	call_deferred(&"_place_near_anchor")
	_update_presentation()


func _physics_process(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	if is_instance_valid(_visuals):
		var pulse := 1.0 + 0.08 * (_flash_left / 0.12) \
			if _flash_left > 0.0 else 1.0
		_visuals.scale = Vector3.ONE * pulse
	if _grappled:
		if is_instance_valid(_carrier):
			grapple_follow(_carrier.grapple_carry_point(), _carrier.global_basis.y)
		else:
			end_grapple(global_position, global_basis.y)
		return
	if _lassoed:
		return
	if not _alive:
		if _is_host():
			_respawn_left = maxf(_respawn_left - delta, 0.0)
			if _respawn_left <= 0.0:
				_respawn()
		return
	if _knockback_left > 0.0:
		_knockback_left = maxf(_knockback_left - delta, 0.0)
		var knock_up := _up()
		up_direction = knock_up
		velocity -= knock_up * 28.0 * delta
		move_and_slide()
		if is_on_floor():
			velocity = velocity.move_toward(Vector3.ZERO, 18.0 * delta)
		return
	# This target can exist hundreds of metres from every player, where no
	# streamed terrain collider exists. Gravity made it fall through the planet
	# before anyone reached the range. Read the deterministic height field
	# directly while idle so it remains where the marked practice site put it.
	_settle_on_ground()


func combat_faction() -> int:
	return DamageHit.Faction.ENEMY


func combat_peer_id() -> int:
	return 0


func combat_display_name() -> String:
	return "Training Dummy"


func combat_position() -> Vector3:
	return global_position + _up()


func combat_radius() -> float:
	return 0.58


func health() -> float:
	return _health


func can_be_grappled() -> bool:
	return _alive and not _grappled and not _lassoed


func begin_grapple(carrier: OnlinePlayer) -> bool:
	if not can_be_grappled() or carrier == null:
		return false
	_grappled = true
	_carrier = carrier
	velocity = Vector3.ZERO
	_collision.set_deferred(&"disabled", true)
	return true


func grapple_follow(centre: Vector3, up: Vector3) -> void:
	if not _grappled or not centre.is_finite():
		return
	up = up.normalized() if up.length_squared() > 0.001 else _up()
	global_position = centre - up
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func end_grapple(at: Vector3, up: Vector3) -> void:
	_grappled = false
	_carrier = null
	if at.is_finite():
		var world_planet := _planet()
		if world_planet != null and world_planet.shape != null:
			var local := world_planet.to_local(at)
			if local.length_squared() > 1.0:
				var direction := local.normalized()
				var spacing := world_planet.finest_spacing()
				var surface := world_planet.shape.surface_point(direction, spacing)
				var normal_local := world_planet.shape.normal_at(
					direction, spacing).normalized()
				var normal := (
					world_planet.global_basis * normal_local).normalized()
				var forward := -global_basis.z
				global_transform = Transform3D(
					_upright_basis(forward, normal),
					world_planet.to_global(surface))
			else:
				global_position = at
		else:
			global_position = at
	elif up.length_squared() > 0.001:
		global_basis = _upright_basis(-global_basis.z, up.normalized())
	_collision.set_deferred(&"disabled", not _alive)
	reset_physics_interpolation()


func can_be_lassoed() -> bool:
	return _alive and not _grappled and not _lassoed


func begin_lasso(source: Node3D) -> bool:
	if not can_be_lassoed() or source == null:
		return false
	_lassoed = true
	_lasso_source_peer = int(source.get("peer_id")) \
		if source.get("peer_id") != null else 0
	_knockback_left = 0.0
	velocity = Vector3.ZERO
	_collision.set_deferred(&"disabled", false)
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
	velocity = next_velocity
	reset_physics_interpolation()


func end_lasso(throw_velocity: Vector3) -> void:
	if not _lassoed:
		return
	_lassoed = false
	_lasso_source_peer = 0
	velocity = throw_velocity if throw_velocity.is_finite() else Vector3.ZERO
	_knockback_left = 0.75 if velocity.length_squared() > 1.0 else 0.0
	_collision.set_deferred(&"disabled", not _alive)
	if _is_host():
		_publish_state()


func lasso_mass() -> float:
	return 1.0


func is_lassoed() -> bool:
	return _lassoed


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _alive or not _is_host() \
			or hit.faction != DamageHit.Faction.PLAYER:
		return 0.0
	var amount := minf(maxf(hit.amount, 0.0), _health) \
		if is_finite(hit.amount) else 0.0
	if amount <= 0.0:
		return 0.0
	_health -= amount
	if hit.reaction == DamageHit.Reaction.KNOCKBACK \
			or hit.reaction == DamageHit.Reaction.RAGDOLL:
		var impulse := hit.world_impulse \
			if hit.world_impulse.is_finite() else Vector3.ZERO
		velocity += impulse
		_knockback_left = maxf(_knockback_left, 0.75)
	_flash_left = 0.12
	if _health <= 0.0:
		_alive = false
		_lassoed = false
		_lasso_source_peer = 0
		_respawn_left = respawn_delay
	_publish_state()
	return amount


func flash_damage(strength := 1.0) -> void:
	_flash_left = maxf(_flash_left, clampf(strength, 0.0, 1.0) * 0.12)


func _respawn() -> void:
	_health = maximum_health
	_alive = true
	_lassoed = false
	_lasso_source_peer = 0
	_respawn_left = 0.0
	_place_at_spawn()
	_publish_state()


func _publish_state() -> void:
	_state_sequence += 1
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_dummy_state.rpc(
			_state_sequence, _health, _alive, global_transform, _flash_left)
	else:
		_apply_dummy_state(
			_state_sequence, _health, _alive, global_transform, _flash_left)


@rpc("authority", "call_local", "reliable")
func _apply_dummy_state(sequence: int, next_health: float, alive: bool,
		at: Transform3D, flash_left: float) -> void:
	if sequence <= _last_state_sequence:
		return
	_last_state_sequence = sequence
	_health = clampf(next_health, 0.0, maximum_health)
	_alive = alive
	_flash_left = clampf(flash_left, 0.0, 0.12)
	if alive:
		global_transform = at
		reset_physics_interpolation()
	_update_presentation()
	health_changed.emit(_health, maximum_health)


func _update_presentation() -> void:
	visible = _alive
	_collision.set_deferred(&"disabled", not _alive or _grappled)
	if is_instance_valid(_label):
		_label.text = "TRAINING DUMMY\n%d / %d" % [
			int(round(_health)), int(round(maximum_health))]


func _place_near_anchor() -> void:
	var anchor := get_node_or_null(anchor_path) as Node3D
	var world_planet := _planet()
	if anchor == null or world_planet == null or world_planet.shape == null:
		return
	var up := world_planet.to_local(anchor.global_position).normalized()
	var forward := -anchor.global_basis.z
	forward -= (world_planet.global_basis * up).normalized() \
		* forward.dot((world_planet.global_basis * up).normalized())
	if forward.length_squared() < 0.001:
		forward = anchor.global_basis.x
	forward = forward.normalized()
	var normal_world := (world_planet.global_basis * up).normalized()
	var right := forward.cross(normal_world).normalized()
	var wanted := anchor.global_position + right * anchor_right_offset \
		+ forward * anchor_forward_offset
	_spawn_direction = world_planet.to_local(wanted).normalized()
	_spawn_forward = forward
	_place_at_spawn()


func _place_at_spawn() -> void:
	var world_planet := _planet()
	if world_planet == null or world_planet.shape == null:
		return
	var spacing := world_planet.finest_spacing()
	var surface := world_planet.shape.surface_point(_spawn_direction, spacing)
	var normal_local := world_planet.shape.normal_at(
		_spawn_direction, spacing).normalized()
	var normal := (world_planet.global_basis * normal_local).normalized()
	global_transform = Transform3D(
		_upright_basis(_spawn_forward, normal),
		world_planet.to_global(surface))
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _settle_on_ground() -> void:
	var world_planet := _planet()
	if world_planet == null or world_planet.shape == null:
		return
	var local := world_planet.to_local(global_position)
	if local.length_squared() < 1.0:
		_place_at_spawn()
		return
	var direction := local.normalized()
	var spacing := world_planet.finest_spacing()
	var surface := world_planet.shape.surface_point(direction, spacing)
	var normal_local := world_planet.shape.normal_at(
		direction, spacing).normalized()
	var normal := (
		world_planet.global_basis * normal_local).normalized()
	var at := world_planet.to_global(surface)
	up_direction = normal
	velocity = Vector3.ZERO
	if global_position.distance_to(at) <= 0.02 \
			and global_basis.y.dot(normal) >= 0.999:
		return
	var forward := -global_basis.z
	global_transform = Transform3D(
		_upright_basis(forward, normal), at)
	reset_physics_interpolation()


func _planet() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		walk = walk.get_parent()
	return null


func _up() -> Vector3:
	var world_planet := _planet()
	if world_planet == null:
		return global_basis.y.normalized()
	var local := world_planet.to_local(global_position)
	return (world_planet.global_basis * local.normalized()).normalized() \
		if local.length_squared() > 1.0 else global_basis.y.normalized()


func _upright_basis(forward: Vector3, up: Vector3) -> Basis:
	up = up.normalized()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.001:
		var hint := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
		forward = hint - up * hint.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	return Basis(right, up, right.cross(up).normalized()).orthonormalized()


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
