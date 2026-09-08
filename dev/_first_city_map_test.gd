extends Node

## Neon Fjord lights Tide Margin and Crescent after one second.
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
		"the extra marks wait a second")
	await get_tree().create_timer(CrawlerRules.CITY_MAP_DELAY + 0.15).timeout
	_expect(spawn.waypoint, "Tide Margin unlocks after Neon Fjord")
	_expect(crescent.waypoint, "Crescent Market unlocks after Neon Fjord")

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
