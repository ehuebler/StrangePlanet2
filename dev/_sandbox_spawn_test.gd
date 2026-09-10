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
	await _check_sandbox_reststop()
	await _check_sandbox_waypoints()

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
	var saved_solo := NetworkManager.is_single_player
	NetworkManager.is_single_player = true
	_expect(CrawlerRules.crawler_free_respawn(),
		"sandbox GAME OVER respawns without a ticket")
	NetworkManager.is_single_player = saved_solo
	_expect(CrawlerRules.starts_visible(CrawlerRules.CITY_SITE_ID)
			and not CrawlerRules.starts_visible(CrawlerRules.START_SITE_ID)
			and not CrawlerRules.starts_visible(CrawlerRules.CITY_CRESCENT_SITE_ID)
			and not CrawlerRules.starts_visible(CrawlerProgress.QUEST_CASTLE),
		"sandbox starts with city 1 and waits on the later sites")
	var held_run := CrawlerRun.payload.duplicate(true)
	var held_path := CrawlerRun.path
	CrawlerRun.clear()
	_expect(CrawlerRun.ensure_session() and CrawlerRun.active(),
		"sandbox picks a crawler run")
	_expect(CrawlerRules.starts_visible(CrawlerRun.first_city_id()),
		"a sandbox run lights city 1 first")
	_expect(not CrawlerRules.first_city_map_ids().has(CrawlerRules.START_SITE_ID),
		"a sandbox run does not put Tide Margin on the city map")
	CrawlerRun.clear()
	CrawlerRun.payload = held_run
	CrawlerRun.path = held_path
	if not held_run.is_empty():
		CrawlerRun._index()
	var sandbox_at := world._spawn_transform(1)
	NetworkManager.session_options["mode"] = "crawler"
	_expect(CrawlerRules.active() and not CrawlerRules.sandbox()
			and not CrawlerRules.starts_visible(CrawlerRules.START_SITE_ID)
			and not CrawlerRules.starts_visible(CrawlerRules.CITY_CRESCENT_SITE_ID),
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


func _check_sandbox_reststop() -> void:
	NetworkManager.session_options["mode"] = "sandbox"
	var store := CrawlerFieldMenu.new()
	add_child(store)
	await get_tree().process_frame
	store._clear_list()
	store._fill_reststop()
	var rest_gold := store.find_child("RestAct_gold", true, false) as Button
	var rest_stores := store.find_child("RestAct_stores", true, false) as Button
	_expect(rest_gold != null and rest_gold.visible and rest_gold.text == "SET",
		"sandbox reststop offers infinite gold")
	_expect(rest_stores != null and rest_stores.visible and rest_stores.text == "SET",
		"sandbox reststop offers infinite stores")
	store.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options["mode"] = "crawler"
	var crawler_store := CrawlerFieldMenu.new()
	add_child(crawler_store)
	await get_tree().process_frame
	crawler_store._clear_list()
	crawler_store._fill_reststop()
	_expect(crawler_store.find_child("RestAct_gold", true, false) != null
			and crawler_store.find_child("RestAct_stores", true, false) != null,
		"crawler reststop still offers infinite gold and stores")
	crawler_store.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options["mode"] = "sandbox"


func _check_sandbox_waypoints() -> void:
	NetworkManager.session_options["mode"] = "sandbox"
	var spawn := CrawlerSite.new()
	spawn.site_id = CrawlerRules.START_SITE_ID
	spawn.title = CrawlerRules.START_SITE_TITLE
	add_child(spawn)
	var office := PatchMonument.new()
	office.monument_id = CrawlerProgress.QUEST_TOWER
	office.title = "Meridian Tower"
	office.waypoint = false
	add_child(office)
	await get_tree().process_frame
	_expect(not spawn.waypoint and not office.waypoint,
		"sandbox leaves the spawn and office dark until they are revealed")
	spawn.queue_free()
	office.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("sandbox_spawn_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("sandbox_spawn_test: FAIL  %s" % message)
