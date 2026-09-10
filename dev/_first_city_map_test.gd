extends Node

## Neon Fjord lights Tide Margin and Crescent after three seconds.
##
##     godot --headless --path . dev/_first_city_map_test.tscn

const PLAYER := preload("res://game/player/player.tscn")

var _failures := 0
var _player: OnlinePlayer


func _ready() -> void:
	CrawlerCatalog.reload()
	CrawlerMeta.begin_test()
	Journal.begin_test()
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME

	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_player.defer_camera = true
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	var spawn := CrawlerSite.new()
	spawn.site_id = CrawlerRules.START_SITE_ID
	spawn.title = CrawlerRules.START_SITE_TITLE
	spawn.enter_radius = 40.0
	spawn.position = Vector3.ZERO
	add_child(spawn)
	var fjord := CrawlerSite.new()
	fjord.site_id = CrawlerRules.CITY_SITE_ID
	fjord.title = CrawlerRules.CITY_SITE_TITLE
	fjord.enter_radius = 40.0
	fjord.position = Vector3(200.0, 0.0, 0.0)
	add_child(fjord)
	var crescent := CrawlerSite.new()
	crescent.site_id = CrawlerRules.CITY_CRESCENT_SITE_ID
	crescent.title = CrawlerRules.CITY_CRESCENT_TITLE
	crescent.enter_radius = 40.0
	crescent.position = Vector3(400.0, 0.0, 0.0)
	add_child(crescent)
	await get_tree().process_frame

	_player.global_position = Vector3.ZERO
	_expect(CrawlerSites.poll(_player) == CrawlerRules.START_SITE_TITLE,
		"spawn still announces Tide Margin")
	_expect(not spawn.waypoint, "Tide Margin stays dark at the pad")
	_expect(not crescent.waypoint, "Crescent stays dark at the pad")

	_player.global_position = Vector3(200.0, 0.0, 0.0)
	_expect(CrawlerSites.poll(_player) == CrawlerRules.CITY_SITE_TITLE,
		"walking in announces Neon Fjord")
	_expect(not spawn.waypoint and not crescent.waypoint,
		"the extra marks wait three seconds")
	await get_tree().create_timer(CrawlerRules.CITY_MAP_DELAY + 0.15).timeout
	_expect(spawn.waypoint, "Tide Margin unlocks after Neon Fjord")
	_expect(crescent.waypoint, "Crescent Market unlocks after Neon Fjord")

	_player.crawler_progress.gold = 81
	var store := CrawlerFieldMenu.new()
	store.configure(_player)
	add_child(store)
	await get_tree().process_frame
	var store_gold := store.find_child("StoreGold", true, false) as Label
	_expect(store_gold != null and store_gold.visible and store_gold.text == "GOLD  81"
			and store_gold.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
			and store_gold.get_global_rect().size.x >= 40.0,
		"the city store names the purse in the upper right")
	store.queue_free()
	var tab := GameMenu.new()
	tab.configure(_player)
	add_child(tab)
	await get_tree().process_frame
	var tab_gold := tab.find_child("MenuGold", true, false) as Label
	_expect(tab_gold != null and tab_gold.visible and tab_gold.text == "GOLD  81"
			and tab_gold.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
		"the Tab menu names the purse in the upper right")
	tab.queue_free()

	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	await get_tree().process_frame
	_player.global_position = Vector3(130.0, 2.0, 0.0)
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	var gate := horde.spawn_test_mob("ranger", Vector3(170.0, 2.0, 0.0), true)
	var far := horde.spawn_test_mob("ranger", Vector3(400.0, 2.0, 0.0), false)
	gate.set_physics_process(false)
	far.set_physics_process(false)
	horde.call("_clear_site_patch_mobs")
	_expect(not is_instance_valid(gate) or gate.dismissed,
		"crossing the city border despawns the mobs around you")
	_expect(not is_instance_valid(far) or far.dismissed,
		"a solo city visit despawns the field everywhere")
	ring.queue_free()
	horde.queue_free()

	spawn.queue_free()
	fjord.queue_free()
	crescent.queue_free()
	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("first_city_map_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("first_city_map_test failed: %s" % label)
