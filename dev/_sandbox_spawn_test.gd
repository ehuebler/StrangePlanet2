extends Node

## Sandbox must host the same crawler rules and spawn path as crawler.
##
##     godot --headless --path . dev/_sandbox_spawn_test.tscn

var _failures := 0
var _saved_players: Dictionary
var _saved_options: Dictionary
var _saved_state: int
var _saved_single_player := false
var _saved_host := false


func _ready() -> void:
	_saved_players = NetworkManager.players.duplicate(true)
	_saved_options = NetworkManager.session_options.duplicate(true)
	_saved_state = int(NetworkManager.state)
	_saved_single_player = NetworkManager.is_single_player
	_saved_host = NetworkManager.is_host

	NetworkManager.players.clear()
	NetworkManager.session_options = {"mode": "sandbox", "max_players": 8}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	NetworkManager.is_single_player = false
	NetworkManager.is_host = true
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	var world := _make_world()
	add_child(world)
	await get_tree().process_frame
	_check_sandbox_matches_crawler(world)

	world.queue_free()
	await get_tree().process_frame
	NetworkManager.players.clear()
	NetworkManager.players.merge(_saved_players, true)
	NetworkManager.session_options = _saved_options
	NetworkManager.state = _saved_state as NetworkManager.SessionState
	NetworkManager.is_single_player = _saved_single_player
	NetworkManager.is_host = _saved_host
	print("sandbox_spawn_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _make_world() -> GameWorld:
	var world := GameWorld.new()
	world.name = "World"
	var spawn_points := Node3D.new()
	spawn_points.name = "SpawnPoints"
	var first := Marker3D.new()
	first.name = "Spawn1"
	first.position = Vector3(0.0, 3.0, 17000.0)
	spawn_points.add_child(first)
	var second := Marker3D.new()
	second.name = "Spawn2"
	second.position = Vector3(50.0, 3.0, 17000.0)
	spawn_points.add_child(second)
	world.add_child(spawn_points)
	var cycle := (load("res://dev/_multiplayer_test_cycle.gd") as GDScript).new() as CelestialCycle
	cycle.name = "CelestialCycle"
	world.add_child(cycle)
	var centre := Node3D.new()
	centre.name = "Planet"
	world.add_child(centre)
	world.set_physics_process(false)
	return world


func _check_sandbox_matches_crawler(world: GameWorld) -> void:
	_expect(CrawlerRules.active() and CrawlerRules.sandbox(),
		"sandbox hosts crawler rules")
	var sandbox_at := world._spawn_transform(1)
	NetworkManager.session_options["mode"] = "crawler"
	_expect(CrawlerRules.active() and not CrawlerRules.sandbox(),
		"crawler stays the named crawler mode")
	var crawler_at := world._spawn_transform(1)
	_expect(sandbox_at.is_equal_approx(crawler_at),
		"sandbox spawn matches crawler spawn")
	NetworkManager.session_options["mode"] = "sandbox"
	_expect(world._spawn_transform(13).is_equal_approx(sandbox_at)
			or world._spawn_transform(13).origin.length_squared() > 0.0,
		"sandbox keeps a usable spawn transform")
	_expect(CrawlerRules.sandbox_invincible() and CrawlerRules.sandbox_fast()
			and not CrawlerRules.sandbox_no_mobs()
			and not CrawlerRules.sandbox_infinite_gold(),
		"sandbox starts invincible and fast")
	CrawlerRules.set_sandbox_cheat(CrawlerRules.CHEAT_MOBS, true)
	CrawlerRules.set_sandbox_cheat(CrawlerRules.CHEAT_INVINCIBLE, true)
	CrawlerRules.set_sandbox_cheat(CrawlerRules.CHEAT_FAST, true)
	CrawlerRules.set_sandbox_cheat(CrawlerRules.CHEAT_GOLD, true)
	_expect(CrawlerRules.sandbox_no_mobs()
			and CrawlerRules.sandbox_invincible()
			and CrawlerRules.sandbox_fast()
			and CrawlerRules.sandbox_infinite_gold(),
		"sandbox cheats only arm while sandbox is hosted")
	NetworkManager.session_options["mode"] = "crawler"
	_expect(not CrawlerRules.sandbox_no_mobs()
			and not CrawlerRules.sandbox_invincible()
			and not CrawlerRules.sandbox_fast()
			and not CrawlerRules.sandbox_infinite_gold(),
		"crawler never reads sandbox cheats")
	CrawlerRules.clear_sandbox_cheats()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("sandbox_spawn_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("sandbox_spawn_test: FAIL  %s" % message)
