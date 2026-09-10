extends Node

## Stale freed mobs in the horde table must not crash castle-keep culling.
##
##     godot --headless --path . dev/_horde_reap_test.tscn

var _failures := 0


func _ready() -> void:
	CrawlerCatalog.reload()
	NetworkManager.session_options = {"mode": "crawler"}
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)

	var live := horde.spawn_test_mob("ranger", Vector3(10.0, 0.0, 0.0), false)
	_expect(live != null, "horde can spawn a test mob")
	var live_id := live.mob_id if live != null else ""
	if live != null:
		live.queue_free()
	await get_tree().process_frame
	_expect(not horde._mobs.has(live_id),
		"a freed mob is dropped from the horde table")

	var ghost := horde.spawn_test_mob("ranger", Vector3(12.0, 0.0, 0.0), false)
	_expect(ghost != null, "horde can spawn a ghost mob")
	var ghost_id := ghost.mob_id if ghost != null else "ghost"
	if ghost != null:
		ghost.queue_free()
	await get_tree().process_frame
	horde._mobs[ghost_id] = ghost
	_expect(horde.call("_held_mob", ghost_id) == null,
		"a freed horde entry does not cast")
	_expect(horde.call("_as_mob", ghost) == null,
		"a freed values() entry does not cast")

	var keep := PatchMonument.new()
	keep.monument_id = CrawlerProgress.QUEST_CASTLE
	add_child(keep)
	keep.global_position = Vector3(400.0, 0.0, 0.0)
	await get_tree().process_frame
	horde.call("_clear_castle_wilds")
	_expect(not horde._mobs.has(ghost_id),
		"castle culling reaps a freed horde entry without crashing")
	horde.call("_dismiss_mob", ghost_id)

	keep.queue_free()
	horde.queue_free()
	await get_tree().process_frame
	print("horde_reap_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("horde_reap_test failed: %s" % label)
