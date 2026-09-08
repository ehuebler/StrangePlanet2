extends Node

## Focused headless checks for generalized combat without loading the planet.
##
##     godot --headless --path . dev/_combat_foundation_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const TEST_CYCLE := preload("res://dev/_multiplayer_test_cycle.gd")
const JUKE_GHOST := preload("res://game/player/juke_afterimage.gd")

var _failures := 0
var _saved_players: Dictionary
var _saved_state: int
var _saved_single_player := false
var _saved_host := false


class TestEnemy extends Node3D:
	const NAME := "Test Enemy"

	var taken := 0.0
	var reflected := 0.0
	var reflected_by := 0

	func _ready() -> void:
		add_to_group(DamageHit.COMBATANT_GROUP)

	func combat_faction() -> int:
		return DamageHit.Faction.ENEMY

	func combat_display_name() -> String:
		return NAME

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.45

	func apply_damage(hit: DamageHit) -> float:
		taken += hit.amount
		return hit.amount

	func receive_reflected_damage(amount: float, source_peer: int) -> void:
		reflected += amount
		reflected_by = source_peer


class TestFlora extends Node3D:
	var hits := 0

	func _ready() -> void:
		add_to_group(DamageHit.FIELD_GROUP)

	func apply_damage(_hit: DamageHit) -> float:
		hits += 1
		return 0.0

	func broken_keys() -> PackedInt32Array:
		return PackedInt32Array()

	func drain_new_breaks() -> PackedInt32Array:
		return PackedInt32Array()


func _ready() -> void:
	_saved_players = NetworkManager.players.duplicate(true)
	_saved_state = int(NetworkManager.state)
	_saved_single_player = NetworkManager.is_single_player
	_saved_host = NetworkManager.is_host
	NetworkManager.players.clear()
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	_check_status_object()
	_check_hit_geometry_and_wire()

	var world_a := _make_world("WorldA")
	var flora_a := TestFlora.new()
	flora_a.name = "Flora"
	world_a.add_child(flora_a)
	add_child(world_a)
	var world_b := _make_world("WorldB")
	var flora_b := TestFlora.new()
	flora_b.name = "Flora"
	world_b.add_child(flora_b)
	add_child(world_b)
	await get_tree().process_frame

	var player := PLAYER.instantiate() as OnlinePlayer
	player.name = "1"
	player.peer_id = 1
	player.defer_camera = true
	world_a.add_child(player, true)
	world_a._spawned_players[1] = player
	var enemy := TestEnemy.new()
	enemy.name = "Enemy"
	world_a.add_child(enemy)
	enemy.global_position = player.combat_position()
	var other_enemy := TestEnemy.new()
	other_enemy.name = "OtherEnemy"
	world_b.add_child(other_enemy)
	other_enemy.global_position = enemy.global_position
	await get_tree().process_frame
	player.set_process(false)
	player.set_physics_process(false)

	_check_scoped_factions(player, enemy, other_enemy, flora_a, flora_b)
	_check_walkable_slopes(player)
	_check_input(player)
	_check_parry_health_and_feedback(player, enemy)
	_check_death_snapshot_respawn(world_a, player, enemy)
	_check_juke(world_a, player, enemy)
	_check_grab_follow_and_throw(world_a, player, enemy)

	world_b.queue_free()
	world_a.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	NetworkManager.players.clear()
	NetworkManager.players.merge(_saved_players, true)
	NetworkManager.state = _saved_state as NetworkManager.SessionState
	NetworkManager.is_single_player = _saved_single_player
	NetworkManager.is_host = _saved_host
	print("combat_foundation_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_status_object() -> void:
	var statuses := CombatStatuses.new()
	var changes := [0]
	statuses.changed.connect(
		func(_id: StringName, _remaining: float) -> void:
			changes[0] += 1)
	_expect(statuses.apply_status(CombatStatuses.FLIGHTLESS, 2.0),
		"Flightless can be applied")
	_expect(statuses.has(CombatStatuses.FLIGHTLESS)
		and statuses.rows().size() == 1,
		"active status exposes a HUD row")
	statuses.tick(0.75)
	_expect(is_equal_approx(
		statuses.remaining(CombatStatuses.FLIGHTLESS), 1.25),
		"status countdown ticks")
	var copy := CombatStatuses.new()
	copy.apply_wire(statuses.to_wire())
	_expect(is_equal_approx(
		copy.remaining(CombatStatuses.FLIGHTLESS), 1.25),
		"status survives a wire snapshot")
	copy.tick(2.0)
	_expect(not copy.has(CombatStatuses.FLIGHTLESS) and changes[0] > 0,
		"status expires and emits changes")
	var ailments := CombatStatuses.new()
	_expect(ailments.apply_status(CombatStatuses.POISON, 3.0, 8.0)
			and ailments.apply_status(CombatStatuses.CHARM, 2.0)
			and ailments.apply_status(CombatStatuses.FREEZE, 1.5)
			and ailments.apply_status(CombatStatuses.SLOW, 1.0)
			and ailments.apply_status(CombatStatuses.SHOCK, 2.0),
		"poison, charm, freeze, slow, and shock are known statuses")
	_expect(is_equal_approx(ailments.strength(CombatStatuses.POISON), 8.0),
		"poison stores its tick strength")
	_expect(ailments.shock_locked(), "shock starts in a lock pulse")
	ailments.tick(CombatStatuses.SHOCK_LOCK + 0.05)
	_expect(not ailments.shock_locked(), "shock then lets the body twitch free")
	_expect(ailments.rows().size() == 5, "each ailment exposes a HUD row")


func _check_hit_geometry_and_wire() -> void:
	var hit := DamageHit.cylinder(
		Vector3.ZERO, Vector3(0.0, 2.0, 0.0), 1.0, 30.0, 0.5)
	hit.faction = DamageHit.Faction.ENEMY
	hit.source_peer = 9
	hit.source_path = NodePath("Enemy")
	hit.target_peer = 1
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.world_impulse = Vector3(3.0, 4.0, 5.0)
	hit.status = CombatStatuses.FLIGHTLESS
	hit.status_duration = 6.0
	hit.parryable = true
	hit.reflection = 11.0
	hit.sequence = 14
	hit.affects_flora = false
	hit.affects_combatants = false
	hit.ability_id = "bigfoot_rock"
	_expect(hit.damage_at(Vector3(0.5, 1.0, 0.0)) > 0.0,
		"cylinder contains its radial middle")
	_expect(is_zero_approx(hit.damage_at(Vector3(0.0, 2.2, 0.0))),
		"cylinder has flat rather than capsule ends")
	_expect(is_zero_approx(hit.damage_at(Vector3(1.1, 1.0, 0.0))),
		"cylinder excludes points outside its radius")
	_expect(hit.reaches(Vector3(0.0, 2.3, 0.0), 0.4)
		and not hit.reaches(Vector3(0.0, 2.6, 0.0), 0.4),
		"spherical target bounds touch a flat cylinder cap without rounding it")
	var crown := DamageHit.impact(Vector3(0.0, 40.0, 0.0), 2.0, 25.0)
	_expect(crown.reaches_segment(Vector3.ZERO, Vector3(0.0, 50.0, 0.0), 3.0),
		"an impact on a tower crown reaches its vertical capsule")
	_expect(not crown.reaches(Vector3(0.0, 25.0, 0.0), 3.0),
		"the same impact misses a mid-height sphere")
	_expect(not crown.reaches_segment(
			Vector3(20.0, 0.0, 0.0), Vector3(20.0, 50.0, 0.0), 3.0),
		"a neighbouring tower is outside the same impact")
	var edge_target := TestEnemy.new()
	add_child(edge_target)
	edge_target.global_position = Vector3(8.0, 0.0, 0.0)
	var spread := DamageHit.area(Vector3.ZERO, 10.0, 100.0, 1.0)
	var edge_damage := spread.resolved_for(edge_target).amount
	_expect(edge_damage > 20.0 and edge_damage < 30.0,
		"dissipating combat area resolves falloff at target body bounds")
	edge_target.free()
	var copy := DamageHit.from_wire(hit.to_wire())
	_expect(copy.shape == DamageHit.Shape.CYLINDER
		and copy.faction == DamageHit.Faction.ENEMY
		and copy.source_path == NodePath("Enemy")
		and copy.target_peer == 1
		and copy.reaction == DamageHit.Reaction.KNOCKBACK
		and copy.world_impulse == Vector3(3.0, 4.0, 5.0)
		and copy.status == CombatStatuses.FLIGHTLESS
		and is_equal_approx(copy.status_duration, 6.0)
		and copy.parryable and is_equal_approx(copy.reflection, 11.0)
		and copy.sequence == 14 and not copy.affects_flora
		and not copy.affects_combatants
		and copy.ability_display_name() == "Rock Throw",
		"all generalized hit fields survive the wire")
	var forged := DamageHit.sanitize_player_packet(hit.to_wire(), 3, null)
	_expect(forged.faction == DamageHit.Faction.PLAYER
		and forged.reaction == DamageHit.Reaction.NONE
		and forged.world_impulse == Vector3.ZERO
		and forged.status.is_empty() and not forged.parryable
		and is_zero_approx(forged.reflection),
		"host sanitizer strips enemy consequences from hero packets")


func _check_scoped_factions(player: OnlinePlayer, enemy: TestEnemy,
		other_enemy: TestEnemy, flora_a: TestFlora,
		flora_b: TestFlora) -> void:
	var before_health := player.health()
	var feedback_events := [0]
	player.enemy_damaged.connect(
		func(_target: Node, _amount: float, _hit: DamageHit) -> void:
			feedback_events[0] += 1)
	var hit := DamageHit.impact(enemy.global_position, 2.0, 9.0)
	hit.faction = DamageHit.Faction.PLAYER
	hit.set_source(player, player.peer_id)
	DamageHit.apply_to_world(player, hit)
	_expect(is_equal_approx(enemy.taken, 9.0),
		"player-faction hit damages an enemy")
	_expect(feedback_events[0] == 1,
		"enemy damage emits the reusable public feedback hook")
	_expect(is_equal_approx(player.health(), before_health),
		"player-faction hit does not damage players")
	_expect(is_zero_approx(other_enemy.taken)
		and flora_a.hits == 1 and flora_b.hits == 0,
		"group dispatch stays inside one GameWorld")
	var enemy_before := enemy.taken
	var flora_before := flora_a.hits
	var flatten := DamageHit.area(enemy.global_position, 4.0, 6000.0, 0.0)
	flatten.faction = DamageHit.Faction.PLAYER
	flatten.affects_combatants = false
	flatten.set_source(player, player.peer_id)
	DamageHit.apply_to_world(player, flatten)
	_expect(is_equal_approx(enemy.taken, enemy_before)
		and flora_a.hits == flora_before + 1,
		"a terrain-clearing volume reaches flora without multiplying actor damage")
	var actor_only := DamageHit.impact(enemy.global_position, 2.0, 7.0)
	actor_only.faction = DamageHit.Faction.PLAYER
	actor_only.affects_flora = false
	actor_only.set_source(player, player.peer_id)
	DamageHit.apply_to_world(player, actor_only)
	_expect(is_equal_approx(enemy.taken, enemy_before + 7.0)
		and flora_a.hits == flora_before + 1,
		"an actor blast skips the duplicate flora scan")


func _check_walkable_slopes(player: OnlinePlayer) -> void:
	var up := player._up().normalized()
	var across := player.global_basis.x.normalized()
	var walkable_angle := deg_to_rad(72.0)
	var walkable := (
		up * cos(walkable_angle) - across * sin(walkable_angle)
	).normalized()
	var cliff_angle := deg_to_rad(80.0)
	var cliff := (
		up * cos(cliff_angle) - across * sin(cliff_angle)
	).normalized()
	_expect(absf(rad_to_deg(player.floor_max_angle)
			- OnlinePlayer.MAX_WALK_SLOPE_DEGREES) < 0.01
		and walkable.dot(up) > OnlinePlayer.FLOOR_FACE
		and cliff.dot(up) < OnlinePlayer.FLOOR_FACE,
		"terrain up to 75 degrees is floor while sharper cliffs remain walls")
	_expect(not player._impact_crashes(walkable, across * 40.0, false),
		"a fast run onto newly walkable steep terrain does not crash")


func _check_input(player: OnlinePlayer) -> void:
	player.apply_held("sword")
	var parry := InputEventKey.new()
	parry.physical_keycode = KEY_F
	parry.pressed = true
	_expect(parry.is_action_pressed(&"parry")
		and not parry.is_action_pressed(&"holster"),
		"F is parry and no longer holster")
	player._unhandled_input(parry)
	_expect(player.held_item() == "sword",
		"parry does not change weapon mode")
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	player._unhandled_input(interact)
	_expect(player.is_holstered(),
		"E with no interactable falls back to ability mode")


func _check_parry_health_and_feedback(player: OnlinePlayer,
		enemy: TestEnemy) -> void:
	# Input above started the authoritative window.
	_expect(player.parry_active() and player.parry_perfect_active()
		and player.parry_cooldown_remaining() > 1.0,
		"host accepts a parry with exported window and cooldown")
	var before := player.health()
	var roar := DamageHit.impact(player.combat_position(), 2.0, 0.0)
	roar.faction = DamageHit.Faction.ENEMY
	roar.target_peer = player.peer_id
	roar.set_source(enemy)
	roar.status = CombatStatuses.FLIGHTLESS
	roar.status_duration = 5.0
	roar.reaction = DamageHit.Reaction.RAGDOLL
	roar.parryable = true
	roar.reflection = 5.0
	DamageHit.apply_to_world(enemy, roar)
	_expect(is_equal_approx(player.health(), before)
		and not player.has_status(CombatStatuses.FLIGHTLESS)
		and player.stance() != OnlinePlayer.Stance.CRASH,
		"perfect parry blocks zero-damage status and reaction")
	_expect(is_equal_approx(enemy.reflected, 5.0)
		and enemy.reflected_by == player.peer_id,
		"perfect parry reflects authored nonzero value")
	_expect(is_zero_approx(player._combat_feedback.flash_amount()),
		"zero-damage Roar never red-flashes")

	player._tick_combat(0.11)
	var ordinary := DamageHit.impact(player.combat_position(), 2.0, 12.0)
	ordinary.faction = DamageHit.Faction.ENEMY
	ordinary.target_peer = player.peer_id
	ordinary.set_source(enemy)
	ordinary.parryable = true
	ordinary.status = CombatStatuses.FLIGHTLESS
	ordinary.status_duration = 3.0
	DamageHit.apply_to_world(enemy, ordinary)
	_expect(player.parry_active() and not player.parry_perfect_active()
		and is_equal_approx(player.health(), before)
		and is_equal_approx(enemy.reflected, 5.0),
		"ordinary block stops damage/status without reflection")
	_expect(not player.request_parry(),
		"parry cooldown is host-validated")

	player._tick_combat(0.4)
	DamageHit.apply_to_world(enemy, ordinary)
	_expect(is_equal_approx(player.health(), before - 12.0)
		and player.has_status(CombatStatuses.FLIGHTLESS),
		"unblocked enemy hit damages player and applies Flightless")
	player._apply_stance(OnlinePlayer.Stance.FLY)
	_expect(player.stance() != OnlinePlayer.Stance.FLY,
		"Flightless blocks every direct flight entry")
	_expect(player._combat_feedback.flash_amount() > 0.0,
		"actual local damage produces a red flash")
	var camera_transform := player.camera.transform
	player.flora_contact_feedback(80.0)
	_expect(player._combat_feedback.shake_remaining() > 0.0
		and player.camera.transform == camera_transform,
		"flora speed adds visual-only camera shake")
	_expect(is_zero_approx(player._combat_feedback.wobble_remaining()),
		"a brush through flora shakes the view without rolling it")
	player.status_impact_feedback(0.7)
	_expect(player._combat_feedback.wobble_remaining() > 0.0,
		"a roar rolls the view as its pressure front goes through")
	var roll := player.camera.rotation.z
	for _step in 40:
		player._combat_feedback._process(0.02)
	_expect(is_zero_approx(player._combat_feedback.wobble_remaining())
		and is_equal_approx(player.camera.rotation.z, roll),
		"the wobble always returns the camera to level")


func _check_death_snapshot_respawn(world: GameWorld, player: OnlinePlayer,
		enemy: TestEnemy) -> void:
	var lethal := DamageHit.impact(player.combat_position(), 2.0, 500.0)
	lethal.faction = DamageHit.Faction.ENEMY
	lethal.target_peer = player.peer_id
	lethal.reaction = DamageHit.Reaction.RAGDOLL
	lethal.ability_id = "bigfoot_meteor"
	lethal.set_source(enemy)
	DamageHit.apply_to_world(player, lethal)
	_expect(player.is_dead() and is_zero_approx(player.health()),
		"zero HP dies")
	_expect(player.death_cause() \
			== "Killed by %s: Meteor Punch" % TestEnemy.NAME,
		"the killer and authored attack are named at the killing blow")
	var snapshot := player.combat_snapshot()
	_expect(bool(snapshot.get("dead", false))
		and is_zero_approx(float(snapshot.get("health", -1.0)))
		and String(snapshot.get("death_cause", "")) == player.death_cause()
		and (snapshot.get("statuses", {}) as Dictionary).has(
			String(CombatStatuses.FLIGHTLESS)),
		"death snapshot records health, death, cause and statuses")
	var screen := player.death_screen()
	_expect(screen != null and screen.notice_text() == player.death_cause(),
		"the player who died is shown what killed them")
	# Nothing puts him back on its own: a clock that took the body back would
	# take the notice with it, and the notice is the whole point of dying.
	for _step in 20:
		world._physics_process(1.0)
	_expect(player.is_dead(), "and nothing but the player ends it")
	if screen != null:
		var button := screen.respawn_button()
		_expect(button != null and button.disabled,
			"the button ignores the shot that was already being fired")
		screen._process(DeathScreen.ARM_DELAY + 0.1)
		_expect(button != null and not button.disabled,
			"and arms a moment later")
		button.pressed.emit()
	_expect(not player.is_dead()
		and is_equal_approx(player.health(), player.maximum_health())
		and player.status_rows().is_empty()
		and is_zero_approx(player.parry_cooldown_remaining()),
		"colony respawn restores full HP and clears temporary effects")
	_expect(player.death_cause().is_empty()
		and player.death_screen() == null,
		"and clears the notice along with the rest of it")

	# Nothing owns some deaths. Better a plain notice than a killer called
	# nothing, or the name of whatever the path happens to resolve to.
	var anonymous := DamageHit.impact(player.combat_position(), 2.0, 500.0)
	anonymous.faction = DamageHit.Faction.ENEMY
	anonymous.target_peer = player.peer_id
	DamageHit.apply_to_world(player, anonymous)
	_expect(player.is_dead()
		and player.death_cause() == DeathScreen.DEFAULT_NOTICE,
		"an unattributed death is reported as one rather than guessed at")
	world.request_colony_respawn()
	# Apply the captured combat fields in a living late-join state; the dead bit
	# itself was asserted above without starting the same physical ragdoll twice
	# under the headless dummy renderer.
	var late_state := snapshot.duplicate(true)
	late_state["dead"] = false
	late_state["forced_ragdoll"] = false
	late_state["health"] = 37.0
	player.apply_combat_snapshot(late_state)
	_expect(not player.is_dead() and is_equal_approx(player.health(), 37.0)
		and player.has_status(CombatStatuses.FLIGHTLESS),
		"late-join combat snapshot applies health/status over defaults")


func _check_juke(world: GameWorld, player: OnlinePlayer,
		enemy: TestEnemy) -> void:
	player.apply_held("")
	player._juke_left = 0.0
	player._juke_cooldown_left = 0.0
	Input.action_press("move_left")
	_expect(player.request_juke(), "empty hands can start a juke")
	Input.action_release("move_left")
	_expect(player.juke_active(), "juke opens an invulnerable window")
	var left := -player.camera.global_basis.x
	_expect(player.juke_direction().dot(left) > 0.7,
		"holding A jukes left")
	var ghosts := 0
	for child: Node in world.get_children():
		if child.get_script() == JUKE_GHOST:
			ghosts += 1
	_expect(ghosts > 0, "a juke leaves a transparent afterimage")
	var hp := player.health()
	var poke := DamageHit.impact(player.combat_position(), 1.2, 18.0)
	poke.faction = DamageHit.Faction.ENEMY
	poke.target_peer = player.peer_id
	poke.set_source(enemy)
	poke.status = CombatStatuses.FLIGHTLESS
	poke.status_duration = 2.0
	_expect(is_zero_approx(player.apply_damage(poke)),
		"a juke takes no damage")
	_expect(is_equal_approx(player.health(), hp),
		"a juke keeps the hit points")
	var before := player.global_position
	player._juke_move(0.05)
	_expect(player.global_position.distance_to(before) > 0.35,
		"a juke rushes the body two metres")
	player._tick_combat(OnlinePlayer.JUKE_TIME)
	player._juke_cooldown_left = 0.0
	var look := player.look_direction()
	look.y = 0.0
	_expect(player._juke_wish_direction().dot(look) < 0.0,
		"juke goes backward unless a steer key is held")
	Input.action_press("move_backward")
	_expect(player._juke_wish_direction().dot(look) < 0.0,
		"holding S still jukes backward")
	Input.action_release("move_backward")
	Input.action_press("move_forward")
	_expect(player._juke_wish_direction().dot(look) > 0.0,
		"holding W jukes forward")
	Input.action_release("move_forward")
	var along := player._juke_wish_direction()
	var carried := along * 18.0
	player.velocity = carried
	_expect(player.request_juke(), "a moving body can still juke")
	player._juke_move(0.016)
	var burst := OnlinePlayer.JUKE_DISTANCE / OnlinePlayer.JUKE_TIME
	_expect(player.velocity.dot(along) > burst + 12.0,
		"juke adds onto existing run or flight speed")
	player._tick_combat(OnlinePlayer.JUKE_TIME)
	_expect(not player.juke_active(), "the juke window ends")
	_expect(player.apply_damage(poke) > 0.0, "hits land after a juke")
	_expect(not player.request_juke(), "juke cooldown is host-validated")
	player._tick_combat(OnlinePlayer.JUKE_COOLDOWN)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	_expect(mouse.is_action_pressed(&"aim") and not player._weapon_can_aim(),
		"right click is juke when no rifle is sighted")
	var aim := InputEventAction.new()
	aim.action = &"aim"
	aim.pressed = true
	player._unhandled_input(aim)
	_expect(player.juke_active(), "the aim action starts a juke")
	player._tick_combat(OnlinePlayer.JUKE_TIME + OnlinePlayer.JUKE_COOLDOWN)
	player.apply_held("laser_rifle")
	_expect(player._weapon_can_aim(),
		"a drawn rifle still uses right click to aim")
	player._unhandled_input(aim)
	_expect(not player.juke_active(),
		"a sighted rifle does not start a juke")
	player.apply_held("")
	player.stats.set_health(player.maximum_health())
	player._juke_left = 0.0
	player._juke_cooldown_left = 0.0


func _check_grab_follow_and_throw(world: GameWorld,
		player: OnlinePlayer, enemy: TestEnemy) -> void:
	player.abilities.set_item(0, "laser_eyes")
	var ability := player.ability_controller().ability_in(0)
	_expect(ability != null and player.activate_ability(0)
		and ability.is_held(), "an ability is live before the grab")
	var socket := Node3D.new()
	socket.name = "GrabSocket"
	world.add_child(socket)
	socket.global_position = Vector3(8.0, 6.0, -3.0)
	var offset := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.25))
	_expect(player.grab_at_socket(socket, offset),
		"host can attach a player to a world-relative grab socket")
	player._follow_grab_socket()
	_expect(player.is_grabbed() and player.grab_socket() == socket
		and player.global_transform.is_equal_approx(
			socket.global_transform * offset),
		"grabbed player follows its socket and authored offset")
	var enemy_before := enemy.taken
	var blocked_hit := DamageHit.impact(enemy.global_position, 2.0, 9.0)
	blocked_hit.ability_id = "meteor_punch"
	player.deal_damage(blocked_hit)
	if player._weapon_pose != null:
		player.apply_held("sword")
		player._swing_weapon()
	_expect(not player.can_attack()
		and (ability == null or not ability.is_held())
		and not player.activate_ability(0)
		and is_equal_approx(enemy.taken, enemy_before)
		and (player._weapon_pose == null or not player._weapon_pose.swinging()),
		"a grabbed player stops held powers and cannot dispatch attacks")
	socket.global_position += Vector3(2.0, 1.0, 4.0)
	player._follow_grab_socket()
	_expect(player.global_transform.is_equal_approx(
		socket.global_transform * offset),
		"socket follow updates without allocating a new attachment")
	var throw_velocity := Vector3(11.0, 7.0, -2.0)
	_expect(player.release_grab(throw_velocity)
		and not player.is_grabbed()
		and player.velocity.is_equal_approx(throw_velocity)
		and player.stance() == OnlinePlayer.Stance.CRASH,
		"release carries throw velocity into the full ragdoll path")
	_expect(not player.can_attack() and not player.activate_ability(0),
		"a thrown ragdoll cannot attack before standing up")
	player._clear_ragdoll()
	socket.queue_free()


func _make_world(world_name: String) -> GameWorld:
	var world := GameWorld.new()
	world.name = world_name
	var spawn_points := Node3D.new()
	spawn_points.name = "SpawnPoints"
	var marker := Marker3D.new()
	marker.name = "Spawn1"
	marker.position = Vector3(4.0, 2.0, 3.0)
	spawn_points.add_child(marker)
	world.add_child(spawn_points)
	var cycle := TEST_CYCLE.new() as CelestialCycle
	cycle.name = "CelestialCycle"
	world.add_child(cycle)
	# Timers are driven explicitly by this harness.
	world.set_physics_process(false)
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("combat_foundation_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("combat_foundation_test: FAIL  %s" % message)
