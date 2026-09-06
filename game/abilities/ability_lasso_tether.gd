class_name AbilityLassoTether
extends Node3D

## Replicated rope presentation plus host-only constrained target simulation.
## The caster's latest authoritative transform supplies the hand and aim; target
## motion is relayed at the ordinary player sync cadence.

signal miss_finished(tether: AbilityLassoTether)

const SYNC_INTERVAL := 1.0 / 20.0
const COLLISION_DEBOUNCE := 0.22
const STRING_SEGMENTS := 18
const STRING_RADIUS := 0.014
const MISS_HOLD := 0.07
const MISS_RETRACT := 0.16

var source: OnlinePlayer
var target: Node3D
var definition: AbilityDefinition
var target_path := NodePath()
var simulates := false

var _velocity := Vector3.ZERO
var _rope_length := 10.0
var _visual_reach := 0.0
var _left := 0.0
var _sync_left := 0.0
var _collision_left := 0.0
var _string: Array[MeshInstance3D] = []
var _phase := 0.0
var _miss := false
var _miss_to := Vector3.ZERO
var _miss_age := 0.0
var _miss_out := 0.1
var _miss_done := false


static func create(world: Node, caster: OnlinePlayer, caught: Node3D,
		record: AbilityDefinition, path: NodePath,
		host_simulates: bool) -> AbilityLassoTether:
	if world == null or caster == null or caught == null or record == null:
		return null
	var tether := AbilityLassoTether.new()
	tether.source = caster
	tether.target = caught
	tether.definition = record
	tether.target_path = path
	tether.simulates = host_simulates
	tether._left = maxf(float(record.stats.get("duration", 2.0)), 0.1)
	tether._rope_length = maxf(float(
		record.stats.get("rope_length", 10.0)), 1.0)
	var carried: Variant = caught.get("velocity")
	if carried is Vector3 and (carried as Vector3).is_finite():
		tether._velocity = carried as Vector3
	world.add_child(tether)
	return tether


static func create_miss(world: Node, caster: OnlinePlayer,
		record: AbilityDefinition) -> AbilityLassoTether:
	if world == null or caster == null or record == null:
		return null
	var tether := AbilityLassoTether.new()
	tether.source = caster
	tether.definition = record
	tether._miss = true
	var from := caster.hand_point(false)
	var reach := maxf(float(record.stats.get("range", 30.0)), 1.0)
	if caster.has_method(&"crawler_range_scale"):
		reach *= float(caster.call(&"crawler_range_scale"))
	var along := caster.aim_direction(from).normalized()
	if along.length_squared() < 0.5:
		along = caster.look_direction().normalized()
	tether._miss_to = from + along * reach
	var query := PhysicsRayQueryParameters3D.create(
		from, tether._miss_to, 1)
	query.exclude = DamageHit.rid_list(caster.get_rid())
	query.collide_with_areas = false
	var hit := caster.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		tether._miss_to = hit.get("position", tether._miss_to)
	var speed := maxf(float(record.stats.get("speed", 120.0)), 1.0)
	tether._miss_out = maxf(from.distance_to(tether._miss_to) / speed, 0.06)
	world.add_child(tether)
	return tether


func _ready() -> void:
	top_level = true
	var light := _string_material(
		definition.tint.lerp(Color.WHITE, 0.14), 0.18)
	var dark := _string_material(definition.tint.darkened(0.14), 0.08)
	var light_mesh := _string_mesh(STRING_RADIUS, light)
	var dark_mesh := _string_mesh(STRING_RADIUS * 0.94, dark)
	for index in STRING_SEGMENTS:
		var segment := MeshInstance3D.new()
		segment.mesh = light_mesh if index % 2 == 0 else dark_mesh
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.visible = false
		add_child(segment)
		_string.append(segment)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(source):
		if is_instance_valid(target) and target.has_method(&"end_lasso"):
			target.call(&"end_lasso", _velocity)
		queue_free()
		return
	if _miss:
		if definition == null:
			queue_free()
			return
		_update_miss(delta)
		return
	if not is_instance_valid(target) or definition == null:
		if simulates:
			source.host_finish_ability_lasso()
		else:
			queue_free()
		return
	if target.has_method(&"is_lassoed") \
			and not bool(target.call(&"is_lassoed")):
		if simulates:
			source.host_finish_ability_lasso()
		else:
			queue_free()
		return
	if simulates and not source.can_attack():
		source.host_finish_ability_lasso()
		return
	_left = maxf(_left - delta, 0.0)
	_collision_left = maxf(_collision_left - delta, 0.0)
	_update_rope(delta)
	if not simulates:
		return
	if _left <= 0.0:
		source.host_finish_ability_lasso()
		return
	_simulate_target(delta)
	_sync_left -= delta
	if _sync_left <= 0.0:
		_sync_left = SYNC_INTERVAL
		source.publish_ability_lasso_motion(
			target_path, target.global_transform, _velocity)


func throw_velocity() -> Vector3:
	return _velocity


func is_miss_cast() -> bool:
	return _miss and not _miss_done


func _simulate_target(delta: float) -> void:
	if not target.has_method(&"lasso_simulate"):
		source.host_finish_ability_lasso()
		return
	var anchor := source.hand_point(false)
	var position := target.global_position
	var up := target.global_basis.y.normalized()
	if up.length_squared() < 0.5:
		up = source.global_basis.y.normalized()
	var gravity := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity", 34.0))
	_velocity -= up * gravity * delta

	var radial := position - anchor
	var mass := maxf(float(target.call(&"lasso_mass")) \
		if target.has_method(&"lasso_mass") else 1.0, 0.25)
	var drive := source.look_direction()
	var movement_drive := source.velocity
	if radial.length_squared() > 0.001:
		var radial_axis := radial.normalized()
		drive -= radial_axis * drive.dot(radial_axis)
		movement_drive -= radial_axis * movement_drive.dot(radial_axis)
	if drive.length_squared() < 0.001:
		drive = source.global_basis.x
	var acceleration := maxf(float(
		definition.stats.get("swing_acceleration", 70.0)), 0.0) / mass
	_velocity += drive.normalized() * acceleration * delta
	if movement_drive.length_squared() > 0.01:
		# Running, flying, or strafing around the anchor adds bounded
		# tangential acceleration instead of merely dragging the target's
		# position along after the caster.
		var movement_share := clampf(
			movement_drive.length() / 20.0, 0.0, 1.5)
		_velocity += movement_drive.normalized() \
			* acceleration * movement_share * 0.65 * delta
	var maximum := maxf(float(
		definition.stats.get("max_speed", 55.0)), 1.0) / sqrt(mass)
	_velocity = _velocity.limit_length(maximum)

	# A far catch reels toward the authored swing radius instead of teleporting
	# ten metres inward on the frame the rope arrives.
	var current_length := radial.length()
	var permitted := maxf(_rope_length, move_toward(
		current_length, _rope_length, maximum * delta))
	var wanted := position + _velocity * delta
	var offset := wanted - anchor
	if offset.length() > permitted:
		var normal := offset.normalized()
		wanted = anchor + normal * permitted
		var outward_speed := _velocity.dot(normal)
		if outward_speed > 0.0:
			_velocity -= normal * outward_speed
	var result: Variant = target.call(
		&"lasso_simulate", wanted - position, _velocity)
	if not result is Dictionary:
		return
	var collision := result as Dictionary
	if not bool(collision.get("collided", false)):
		return
	var normal_variant: Variant = collision.get("normal", Vector3.ZERO)
	var normal := normal_variant as Vector3 \
		if normal_variant is Vector3 else Vector3.ZERO
	var impact_speed := maxf(-_velocity.dot(normal), 0.0) \
		if normal.length_squared() > 0.001 else _velocity.length()
	if normal.length_squared() > 0.001:
		_velocity = _velocity.bounce(normal.normalized()) * 0.32
	if _collision_left > 0.0 or impact_speed < float(
			definition.stats.get("impact_speed", 10.0)):
		return
	_collision_left = COLLISION_DEBOUNCE
	var point_variant: Variant = collision.get(
		"position", target.global_position)
	var point := point_variant as Vector3 \
		if point_variant is Vector3 else target.global_position
	_damage_combatant(target, point, impact_speed)
	var struck := _combatant_owner(collision.get("collider") as Node)
	if struck != null and struck != target and struck != source:
		_damage_combatant(struck, point, impact_speed)


func _damage_combatant(combatant: Node, at: Vector3,
		impact_speed: float) -> void:
	if combatant == null or not combatant.has_method(&"apply_damage") \
			or not combatant.has_method(&"combat_faction"):
		return
	var threshold := maxf(float(
		definition.stats.get("impact_speed", 10.0)), 0.1)
	var maximum := maxf(float(
		definition.stats.get("max_speed", 55.0)), threshold + 0.1)
	var share := clampf(
		(impact_speed - threshold) / (maximum - threshold), 0.2, 1.0)
	var is_player := int(combatant.call(&"combat_faction")) \
		== DamageHit.Faction.PLAYER
	var quoted := float(definition.stats.get(
		"player_damage" if is_player else "damage", 0.0))
	var hit := DamageHit.impact(
		at, maxf(_combat_radius(combatant), 0.25), maxf(quoted, 0.0) * share)
	hit.faction = DamageHit.Faction.ENEMY \
		if is_player else DamageHit.Faction.PLAYER
	hit.ability_id = definition.ability_id
	hit.reaction = DamageHit.Reaction.RAGDOLL \
		if is_player else DamageHit.Reaction.KNOCKBACK
	hit.world_impulse = _velocity
	hit.set_source(source, source.peer_id)
	var result: Variant = combatant.call(&"apply_damage", hit)
	var dealt := float(result) if result is float or result is int else 0.0
	if dealt > 0.0:
		source.combat_damage_dealt(combatant, dealt, hit)


func _combatant_owner(node: Node) -> Node:
	var walk := node
	while walk != null:
		if walk.is_in_group(DamageHit.COMBATANT_GROUP):
			return walk
		walk = walk.get_parent()
	return null


func _combat_radius(combatant: Node) -> float:
	return maxf(float(combatant.call(&"combat_radius")), 0.0) \
		if combatant != null and combatant.has_method(&"combat_radius") else 0.5


func _update_rope(delta: float) -> void:
	_phase += delta * 5.0
	var from := source.hand_point(false)
	var to := target.call(&"combat_position") as Vector3 \
		if target.has_method(&"combat_position") else target.global_position
	var span := from.distance_to(to)
	_visual_reach = minf(
		_visual_reach + maxf(float(definition.stats.get("speed", 120.0)), 1.0)
			* delta,
		span)
	var shown_to := from + (to - from).normalized() * _visual_reach \
		if span > 0.001 else to
	_place_string(from, shown_to, false)


func _update_miss(delta: float) -> void:
	if _miss_done:
		return
	_miss_age += delta
	_phase += delta * 8.0
	var from := source.hand_point(false)
	var span := from.distance_to(_miss_to)
	var reach := span
	var retract_at := _miss_out + MISS_HOLD
	if _miss_age < _miss_out:
		reach = span * clampf(_miss_age / _miss_out, 0.0, 1.0)
	elif _miss_age > retract_at:
		var retract := clampf(
			(_miss_age - retract_at) / MISS_RETRACT, 0.0, 1.0)
		reach = span * (1.0 - retract)
		if retract >= 1.0:
			_miss_done = true
			_hide_string()
			miss_finished.emit(self)
			queue_free()
			return
	_visual_reach = reach
	var shown_to := from + (_miss_to - from).normalized() * reach \
		if span > 0.001 else from
	_place_string(from, shown_to, true)


func _string_material(colour: Color, emission: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.78
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = emission
	return material


func _string_mesh(radius: float,
		material: StandardMaterial3D) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 0
	mesh.material = material
	return mesh


func _place_string(from: Vector3, to: Vector3, travelling: bool) -> void:
	var along := to - from
	var span := along.length()
	if span < 0.001 or _string.is_empty():
		_hide_string()
		return
	var axis := along / span
	var up := source.global_basis.y.normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	var side := axis.cross(up)
	if side.length_squared() < 0.001:
		side = axis.cross(
			Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD)
	side = side.normalized()
	var down := -up
	var sag := clampf(span * 0.022, 0.025, 0.42)
	if travelling:
		sag *= 0.42
	var fibre := minf(span * 0.002, 0.018)
	for index in _string.size():
		var start_share := float(index) / float(_string.size())
		var end_share := float(index + 1) / float(_string.size())
		var start := _string_point(
			from, to, down, side, start_share, sag, fibre)
		var finish := _string_point(
			from, to, down, side, end_share, sag, fibre)
		_place_segment(_string[index], start, finish)


func _string_point(from: Vector3, to: Vector3, down: Vector3,
		side: Vector3, share: float, sag: float, fibre: float) -> Vector3:
	var middle := sin(PI * share)
	return from.lerp(to, share) \
		+ down * middle * sag \
		+ side * sin(share * TAU * 2.5 + _phase) * middle * fibre


func _place_segment(instance: MeshInstance3D,
		from: Vector3, to: Vector3) -> void:
	var along := to - from
	var span := along.length()
	if span < 0.001:
		instance.visible = false
		return
	var axis := along / span
	var side := axis.cross(
		Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	instance.global_transform = Transform3D(
		Basis(side, axis * span, side.cross(axis)),
		from + along * 0.5)
	instance.visible = true


func _hide_string() -> void:
	for segment in _string:
		segment.visible = false
