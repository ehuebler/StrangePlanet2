extends Node

## Headless checks for the tilde-menu enemy creator and definition-driven AI.
##
##     godot --headless --path . dev/_enemy_creator_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const TEST_CYCLE := preload("res://dev/_multiplayer_test_cycle.gd")

var _failures := 0
var _saved_players: Dictionary
var _saved_state: int
var _saved_single_player := false
var _saved_host := false


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

	_check_ability_scoring()
	await _check_training_body_and_tilde()
	await _check_enemy_hits_player()

	NetworkManager.players = _saved_players
	NetworkManager.state = _saved_state as NetworkManager.SessionState
	NetworkManager.is_single_player = _saved_single_player
	NetworkManager.is_host = _saved_host
	print("enemy_creator_test: %d failed" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check_ability_scoring() -> void:
	var laser := ItemDB.ability_definition("laser_eyes")
	var meteor := ItemDB.ability_definition("meteor_punch")
	var wall := ItemDB.ability_definition("wall")
	var grapple := ItemDB.ability_definition("grapple")
	var nuke := ItemDB.ability_definition("nuke")
	_expect(laser != null and meteor != null and wall != null and grapple != null \
			and nuke != null, "catalogue still exposes the authored abilities")
	_expect(EnemyPlayerAI.score_ability(laser, 20.0, false) \
			> EnemyPlayerAI.score_ability(wall, 20.0, false),
		"attack prefers a beam in range over a barrier")
	_expect(EnemyPlayerAI.score_ability(wall, 8.0, true) \
			> EnemyPlayerAI.score_ability(laser, 8.0, true),
		"flee prefers a barrier to a beam")
	_expect(EnemyPlayerAI.score_ability(meteor, 70.0, false) \
			> EnemyPlayerAI.score_ability(laser, 70.0, false),
		"attack closes a long gap with a self-launch")
	_expect(EnemyPlayerAI.score_ability(meteor, 12.0, true) > 0.8,
		"flee uses a self-launch to get away")
	_expect(EnemyPlayerAI.score_ability(grapple, 1.5, false, Node.new()) < 0.2,
		"grapple is ignored when the prey cannot be carried")
	_expect(EnemyPlayerAI.score_ability(nuke, 80.0, false) > 0.8,
		"a long-range blast is used when the prey is inside its reach")
	var extra := AbilityDefinition.new()
	extra.ability_id = "future_beam"
	extra.implementation = laser.implementation
	extra.activation_type = AbilityDefinition.ActivationType.SUSTAINED
	extra.projectile_type = AbilityDefinition.ProjectileType.BEAM
	extra.stats = {"range": 30.0, "damage": 10.0}
	_expect(EnemyPlayerAI.score_ability(extra, 18.0, false) > 0.9,
		"an unseen future beam is scored from its definition, not its id")


func _check_training_body_and_tilde() -> void:
	var world := _make_world("CreatorWorld")
	add_child(world)
	await get_tree().process_frame

	var player := PLAYER.instantiate() as OnlinePlayer
	player.name = "1"
	player.peer_id = 1
	player.defer_camera = true
	world.add_child(player)
	world._spawned_players[1] = player
	await get_tree().process_frame

	_expect(not player._try_place_enemy_creator(),
		"T does nothing while the tilde overlay is down")
	player._waypoints_wanted = true
	_expect(player._try_place_enemy_creator(),
		"tilde T plants a creator in front of the player")
	var creator := world.get_node_or_null("EnemyCreator") as EnemyCreator
	_expect(creator != null, "the creator stays in the world")
	if creator != null:
		_expect(creator.interact_prompt() == "Configure enemy",
			"E prompt names the creator")
		var ids := ItemDB.ability_ids()
		var pick := PackedStringArray()
		pick.resize(3)
		for index in 3:
			pick[index] = ids[index] if index < ids.size() else ids[0]
		creator.queue_spawn(player, pick, EnemyPlayerAI.Behavior.ATTACK)
		_expect(creator.queued_spawn_count() == 1,
			"spawn is delayed and the cylinder remains")
		creator.force_finish_spawns()
		_expect(creator.queued_spawn_count() == 0
				and is_instance_valid(creator),
			"the cylinder remains after the dummy appears")

	var dummy: OnlinePlayer
	for child in world.get_children():
		var other := child as OnlinePlayer
		if other != null and other.training_enemy:
			dummy = other
			break
	_expect(dummy != null, "the delayed spawn produces a training enemy")
	if dummy != null:
		_expect(dummy.abilities.size() == OnlinePlayer.TRAINING_ABILITY_SLOTS,
			"the dummy holds three ability slots")
		_expect(dummy.ability_controller() != null,
			"the dummy simulates abilities locally")
		_expect(dummy.combat_faction() == DamageHit.Faction.ENEMY,
			"the dummy is an enemy to the live player")
		_expect(dummy.body_id() == player.body_id(),
			"the dummy wears the same body as the player")
		_expect(not dummy.is_in_group(&"network_players"),
			"dummies are not registered as session peers")
	world.queue_free()
	await get_tree().process_frame


func _check_enemy_hits_player() -> void:
	var world := _make_world("HitWorld")
	add_child(world)
	await get_tree().process_frame

	var victim := PLAYER.instantiate() as OnlinePlayer
	victim.name = "1"
	victim.peer_id = 1
	victim.defer_camera = true
	world.add_child(victim)
	world._spawned_players[1] = victim
	await get_tree().process_frame
	victim.global_position = Vector3(0.0, 2.0, 0.0)

	var dummy := PLAYER.instantiate() as OnlinePlayer
	dummy.become_training_enemy(-1001, 3)
	dummy.name = "Dummy"
	world.add_child(dummy)
	await get_tree().process_frame
	dummy.global_position = Vector3(0.0, 2.0, 1.0)

	var before := victim.health()
	var hit := DamageHit.impact(victim.combat_position(), 1.0, 25.0)
	dummy.deal_damage(hit)
	_expect(victim.health() < before,
		"a training enemy's outgoing hit reaches the live player")
	var back := DamageHit.impact(dummy.combat_position(), 1.0, 25.0)
	back.faction = DamageHit.Faction.PLAYER
	back.set_source(victim, victim.peer_id)
	var dummy_before := dummy.health()
	dummy.apply_damage(back)
	_expect(dummy.health() < dummy_before,
		"the live player's hits still damage the dummy")
	world.queue_free()
	await get_tree().process_frame


func _make_world(world_name: String) -> GameWorld:
	var world := GameWorld.new()
	world.name = world_name
	var spawn_points := Node3D.new()
	spawn_points.name = "SpawnPoints"
	var marker := Marker3D.new()
	marker.name = "Spawn1"
	spawn_points.add_child(marker)
	world.add_child(spawn_points)
	var cycle := TEST_CYCLE.new() as CelestialCycle
	cycle.name = "CelestialCycle"
	world.add_child(cycle)
	world.set_physics_process(false)
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("enemy_creator_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("enemy_creator_test: FAIL  %s" % message)
