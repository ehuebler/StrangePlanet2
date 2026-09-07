class_name EnemyPlayerAI
extends Node

## Definition-driven brain for a tilde-menu training dummy.
##
## It never names a specific ability. New powers are classified from their
## [AbilityDefinition] — range, projectile, construct, grapple, self-launch —
## so a catalogue addition is picked up without a second table here.

enum Behavior {
	ATTACK,
	FLEE,
	CIRCLE_RUN,
	CIRCLE_FLY,
}

const CIRCLE_RADIUS := 28.0
const THINK_STEP := 0.12
const HOLD_RELEASE_GRACE := 0.18

var player: OnlinePlayer
var creator: Node3D
var behavior: Behavior = Behavior.ATTACK

var _think_left := 0.0
var _held_slot := -1
var _hold_left := 0.0
var _circle_sign := 1.0
var _takeoff_left := 0.0


func configure(owner: OnlinePlayer, anchor: Node3D, mode: Behavior) -> void:
	player = owner
	creator = anchor
	behavior = mode
	_circle_sign = 1.0 if hash(owner.get_instance_id()) % 2 == 0 else -1.0


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.training_enemy:
		return
	if player.is_dead() or not player.can_attack():
		player.set_training_move(Vector2.ZERO)
		_release_held()
		return
	_takeoff_left = maxf(_takeoff_left - delta, 0.0)
	_hold_left = maxf(_hold_left - delta, 0.0)
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = THINK_STEP
		_think()
	_drive_motion(delta)
	if _held_slot >= 0 and _hold_left <= 0.0:
		_release_held()


func _think() -> void:
	var prey := _prey()
	match behavior:
		Behavior.ATTACK:
			if prey != null:
				_choose_ability(prey, false)
		Behavior.FLEE:
			if prey != null:
				_choose_ability(prey, true)
		Behavior.CIRCLE_RUN, Behavior.CIRCLE_FLY:
			_release_held()


func _drive_motion(_delta: float) -> void:
	var prey := _prey()
	match behavior:
		Behavior.ATTACK:
			_chase(prey)
		Behavior.FLEE:
			_retreat(prey)
		Behavior.CIRCLE_RUN:
			_orbit(false)
		Behavior.CIRCLE_FLY:
			_orbit(true)


func _chase(prey: OnlinePlayer) -> void:
	if prey == null:
		player.set_training_move(Vector2.ZERO)
		return
	player.aim_training_at(prey.combat_position())
	var gap := _planar_gap(prey.global_position)
	if prey.stance() == OnlinePlayer.Stance.FLY and player.can_fly() \
			and player.stance() != OnlinePlayer.Stance.FLY \
			and player.stance() != OnlinePlayer.Stance.METEOR:
		_ask_fly()
	elif player.stance() == OnlinePlayer.Stance.FLY and gap < 6.0 \
			and prey.stance() != OnlinePlayer.Stance.FLY:
		player.pulse_training_land()
	var sprint := gap > 8.0
	player.set_training_move(_local_move_toward(prey.global_position), sprint)


func _retreat(prey: OnlinePlayer) -> void:
	if prey == null:
		player.set_training_move(Vector2.ZERO)
		return
	player.aim_training_at(prey.combat_position())
	var away := player.global_position * 2.0 - prey.global_position
	if player.can_fly() and player.stance() != OnlinePlayer.Stance.FLY \
			and _planar_gap(prey.global_position) < 18.0:
		_ask_fly()
	player.set_training_move(_local_move_toward(away), true)


func _orbit(fly: bool) -> void:
	if creator == null or not is_instance_valid(creator):
		player.set_training_move(Vector2.ZERO)
		return
	var up := player.global_basis.y
	var to_anchor := creator.global_position - player.global_position
	var flat := to_anchor - up * to_anchor.dot(up)
	var radius := flat.length()
	var inward := flat.normalized() if radius > 0.05 else -player.global_basis.z
	var tangent := up.cross(inward).normalized() * _circle_sign
	var radial := clampf((radius - CIRCLE_RADIUS) / maxf(CIRCLE_RADIUS, 1.0), -1.0, 1.0)
	var heading := (tangent + inward * radial).normalized()
	var look_at := player.global_position + heading * 8.0 + up * (2.0 if fly else 0.8)
	player.aim_training_at(look_at)
	if fly:
		if player.stance() != OnlinePlayer.Stance.FLY and player.can_fly():
			_ask_fly()
		player.set_training_jump_held(true)
	else:
		player.set_training_jump_held(false)
		if player.stance() == OnlinePlayer.Stance.FLY:
			player.pulse_training_land()
	player.set_training_move(_world_to_move(heading), true)


func _ask_fly() -> void:
	if _takeoff_left > 0.0:
		return
	_takeoff_left = 0.35
	if player.stance() == OnlinePlayer.Stance.STAND \
			or player.stance() == OnlinePlayer.Stance.CROUCH \
			or player.stance() == OnlinePlayer.Stance.SLIDE:
		player.start_flying()
	else:
		player.pulse_training_jump()


func _choose_ability(prey: OnlinePlayer, fleeing: bool) -> void:
	var controller := player.ability_controller()
	if controller == null:
		return
	var distance := player.combat_position().distance_to(prey.combat_position())
	var best_slot := -1
	var best_score := 0.0
	for index in player.abilities.size():
		var ability := controller.ability_in(index)
		if ability == null or not ability.can_use():
			if _held_slot == index and ability != null and ability.is_held():
				best_slot = index
				best_score = 1.0
			continue
		var definition := ability.definition
		if definition == null:
			definition = ItemDB.ability_definition(ability.ability_id)
		var score := score_ability(definition, distance, fleeing, prey)
		if score > best_score:
			best_score = score
			best_slot = index
	if best_slot < 0 or best_score < 0.15:
		_release_held()
		return
	_press_slot(best_slot, controller.ability_in(best_slot))


func _press_slot(index: int, ability: Ability) -> void:
	if ability == null:
		return
	if _held_slot == index and ability.is_held():
		_hold_left = HOLD_RELEASE_GRACE
		return
	_release_held()
	if not player.activate_ability(index):
		return
	var definition := ability.definition
	if definition == null:
		definition = ItemDB.ability_definition(ability.ability_id)
	if definition != null \
			and definition.activation_type == AbilityDefinition.ActivationType.SUSTAINED:
		_held_slot = index
		_hold_left = maxf(float(definition.stats.get("duration", 1.0)), 0.4)
	elif definition != null \
			and definition.activation_type == AbilityDefinition.ActivationType.COMMITTED:
		_held_slot = index
		_hold_left = 8.0
	else:
		player.release_ability(index)
		_held_slot = -1


func _release_held() -> void:
	if _held_slot < 0 or player == null:
		_held_slot = -1
		return
	player.release_ability(_held_slot)
	_held_slot = -1
	_hold_left = 0.0


## Public so the harness can lock the policy without standing a body up.
static func score_ability(definition: AbilityDefinition, distance: float,
		fleeing: bool, prey: Node = null) -> float:
	if definition == null or not definition.valid():
		return 0.0
	var reach := maxf(float(definition.stats.get("range", 0.0)), 0.0)
	var blast := maxf(float(definition.stats.get("radius", 0.0)), 0.0)
	var useful_reach := maxf(reach, blast * 0.45)
	if useful_reach <= 0.0:
		useful_reach = 8.0
	# A self-launch flag is a blast side-effect, not a dash. Only a SELF
	# projectile is a committed close-the-gap / get-away move.
	var dash := definition.projectile_type == AbilityDefinition.ProjectileType.SELF
	var defensive := definition.construct_type \
			== AbilityDefinition.ConstructType.BARRIER
	var control := definition.grapple_type != AbilityDefinition.GrappleType.NONE \
			or definition.projectile_type == AbilityDefinition.ProjectileType.TETHER
	var ranged := definition.projectile_type in [
		AbilityDefinition.ProjectileType.BEAM,
		AbilityDefinition.ProjectileType.ENERGY_DISK,
		AbilityDefinition.ProjectileType.ENERGY_ORB,
		AbilityDefinition.ProjectileType.ENERGY_BOLT,
		AbilityDefinition.ProjectileType.ENERGY_ICICLE,
		AbilityDefinition.ProjectileType.TELEPORT_ORB,
		AbilityDefinition.ProjectileType.ENERGY_CONE,
	] or definition.impact_type in [
		AbilityDefinition.ImpactType.BURN,
		AbilityDefinition.ImpactType.MASSIVE_BLAST,
		AbilityDefinition.ImpactType.DELAYED_BLAST,
		AbilityDefinition.ImpactType.EXPLOSION_CRATER,
	]
	if control and not _can_control(definition, prey):
		control = false
	if fleeing:
		if dash or definition.self_launch:
			return 1.0 if distance < 40.0 else 0.35
		if defensive and distance < 16.0:
			return 0.92
		if control and definition.affects_players and distance <= useful_reach:
			return 0.7
		if ranged and distance < useful_reach * 0.6:
			return 0.22
		return 0.0
	if control and distance <= maxf(useful_reach, 2.5):
		return 1.05
	if dash:
		if distance > useful_reach * 0.85:
			return 0.88
		if distance < 10.0:
			return 0.8
		return 0.4
	if ranged and distance <= useful_reach:
		var closeness := 1.0 - clampf(distance / maxf(useful_reach, 1.0), 0.0, 1.0)
		var weight := 0.95
		if definition.projectile_type == AbilityDefinition.ProjectileType.BEAM:
			weight = 1.0
		if definition.impact_type == AbilityDefinition.ImpactType.MASSIVE_BLAST \
				and distance < blast * 0.35:
			weight = 0.2
		return weight + closeness * 0.08
	if defensive and distance < 12.0:
		return 0.28
	if ranged and distance > useful_reach:
		return 0.08
	return 0.05


static func _can_control(definition: AbilityDefinition, prey: Node) -> bool:
	if prey == null:
		return definition.affects_players
	if definition.grapple_type == AbilityDefinition.GrappleType.CARRY_SLAM:
		return prey.has_method(&"begin_grapple") and prey.has_method(&"can_be_grappled") \
			and bool(prey.call(&"can_be_grappled"))
	if definition.projectile_type == AbilityDefinition.ProjectileType.TETHER \
			or definition.grapple_type == AbilityDefinition.GrappleType.PHYSICS_TETHER:
		if not prey.has_method(&"begin_lasso"):
			return false
		if prey.has_method(&"combat_faction") \
				and int(prey.call(&"combat_faction")) == DamageHit.Faction.PLAYER:
			return definition.affects_players
		return true
	return definition.affects_players


func _prey() -> OnlinePlayer:
	var world := player.get_parent() as GameWorld
	if world != null:
		var local := world.local_player()
		if local != null and local != player and is_instance_valid(local) \
				and not local.is_dead():
			return local
	if player.get_tree() == null:
		return null
	for node in player.get_tree().get_nodes_in_group(&"network_players"):
		var other := node as OnlinePlayer
		if other != null and other != player and not other.training_enemy \
				and not other.is_dead():
			return other
	return null


func _planar_gap(toward: Vector3) -> float:
	var up := player.global_basis.y
	var delta := toward - player.global_position
	return (delta - up * delta.dot(up)).length()


func _local_move_toward(world_point: Vector3) -> Vector2:
	var up := player.global_basis.y
	var delta := world_point - player.global_position
	var flat := delta - up * delta.dot(up)
	if flat.length_squared() < 0.0001:
		return Vector2.ZERO
	return _world_to_move(flat.normalized())


func _world_to_move(world_heading: Vector3) -> Vector2:
	var local := player.global_basis.inverse() * world_heading
	var move := Vector2(local.x, local.z)
	if move.length_squared() < 0.0001:
		return Vector2.ZERO
	return move.normalized()
