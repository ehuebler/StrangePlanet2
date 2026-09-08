extends Node

## Safe boxes and cities hold fire. A click plays a Mixamo dance instead.
##
##     godot --headless --path . dev/_safe_zone_dance_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const CITY_RING := preload("res://game/crawler/crawler_city_ring.gd")

var _failures := 0
var _player: OnlinePlayer


func _ready() -> void:
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerCatalog.reload()
	CrawlerProgress.clear_session()
	CrawlerMeta.begin_test()
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

	_player.equip_ability("starfire", 0)
	_player.select_ability(0)

	await _check_safe_box()
	await _check_city()

	_player.queue_free()
	print("safe_zone_dance_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_safe_box() -> void:
	var box := CrawlerSafeBox.new()
	box.configure(7, Transform3D.IDENTITY)
	add_child(box)
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_expect(_player.in_crawler_safe_zone() and not _player.can_attack(),
		"the box holds abilities")
	_expect_dance("inside the box")
	_player.global_position = Vector3(80.0, 0.0, 0.0)
	_expect(not _player.in_crawler_safe_zone() and _player.can_attack(),
		"abilities return outside the box")
	box.queue_free()
	await get_tree().process_frame


func _check_city() -> void:
	var ring = CITY_RING.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_expect(_player.in_crawler_city() and not _player.can_attack(),
		"the city holds abilities")
	_expect_dance("inside the city")
	_player.global_position = Vector3(300.0, 0.0, 0.0)
	_expect(not _player.in_crawler_city() and _player.can_attack(),
		"abilities return outside the city")
	ring.queue_free()
	await get_tree().process_frame


func _expect_dance(where: String) -> void:
	var fired := [false]
	var on_fire := func(_slot: int, _id: String) -> void: fired[0] = true
	_player.ability_activated.connect(on_fire)
	_expect(not _player.activate_ability(0),
		"direct ability use is blocked %s" % where)
	_player.activate_primary()
	_player.ability_activated.disconnect(on_fire)
	_expect(not fired[0], "clicking %s does not fire" % where)
	var dances := CharacterRig.dance_clips(_player.animator)
	_expect(not dances.is_empty(), "the body has Mixamo dances")
	var clip := ""
	if _player.animator != null:
		clip = String(_player.animator.current_animation)
	_expect(clip.begins_with("Dance_"),
		"clicking %s starts a dance (got %s)" % [where, clip])


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  ok  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
