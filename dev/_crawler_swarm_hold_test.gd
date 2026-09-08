extends Node

## Hold a 40-mob pile (20 rangers, 10 rhinos, 10 rammers) on the player and
## check that unique attack planning stays inside the scaled director budget.
##
##     godot --headless --path . dev/_crawler_swarm_hold_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const MOB_SENSE := preload("res://game/crawler/crawler_mob_sense.gd")
const HOLD_FRAMES := 48
const MAX_FRAME_MS := 40.0

var _failures := 0
var _player: OnlinePlayer


func _ready() -> void:
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerCatalog.reload()
	CrawlerMobs.reload()
	CrawlerProgress.clear_session()
	CrawlerMeta.begin_test()
	Journal.begin_test()
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
	_player.global_position = Vector3.ZERO
	await get_tree().process_frame

	var horde := CrawlerHorde.new()
	add_child(horde)
	for index in 20:
		horde.spawn_test_mob(
			"ranger", Vector3(6.0 + float(index) * 0.35, 4.0, 0.4), true)
	for index in 10:
		horde.spawn_test_mob(
			"rhino", Vector3(-8.0, 4.0, float(index) * 0.7), true)
	for index in 10:
		horde.spawn_test_mob(
			"rammer", Vector3(0.6, 4.0, 8.0 + float(index) * 0.55), true)
	_expect(horde.wild_live_count() == 40,
		"the hold swarm fields 20 rangers, 10 rhinos, and 10 rammers")

	MOB_SENSE.invalidate()
	var worst_ms := 0.0
	var peak_think := 0
	var peak_attack := 0
	var peak_ai_ms := 0.0
	var last_board: Dictionary = {}
	for step in HOLD_FRAMES:
		var clock := Time.get_ticks_usec()
		await get_tree().physics_frame
		var frame_ms := float(Time.get_ticks_usec() - clock) * 0.001
		worst_ms = maxf(worst_ms, frame_ms)
		var board: Dictionary = MOB_SENSE.director_counts()
		last_board = board
		if step >= 2:
			_expect(int(board.get("frame_think_ok", 0))
					<= int(board.get("think_budget", 0)),
				"a 40-mob pile only plans as many hunts as the scaled think budget")
			_expect(int(board.get("frame_attack_ok", 0))
					<= int(board.get("attack_budget", 0)),
				"a 40-mob pile only starts as many new attacks as the scaled attack budget")
			peak_think = maxi(peak_think, int(board.get("frame_think_ok", 0)))
			peak_attack = maxi(peak_attack, int(board.get("frame_attack_ok", 0)))
			peak_ai_ms = maxf(peak_ai_ms, float(board.get("ai_usec", 0)) * 0.001)

	var chase := int(last_board.get("chase", 0))
	var think_cap := int(last_board.get("think_budget", 0))
	var attack_cap := int(last_board.get("attack_budget", 0))
	_expect(chase >= 24, "the hold pack stays in agro")
	_expect(think_cap <= 8 and attack_cap <= 2,
		"a piled-up pack spends fewer unique attack planners")
	_expect(peak_ai_ms < 8.0, "denied hunters skip unique keep-clear work")
	_expect(horde.queued_spawn_count() == 0 and horde.wild_live_count() == 40,
		"the hold swarm does not drip extra bodies while they fight")
	_expect(worst_ms < MAX_FRAME_MS,
		"the hold swarm stays under %.0f ms per physics frame" % MAX_FRAME_MS)
	print("crawler_swarm_hold: worst %.2f ms  chase %d  think %d/%d  attack %d/%d  ai %.2f ms" % [
		worst_ms, chase, peak_think, think_cap, peak_attack, attack_cap, peak_ai_ms])

	horde.queue_free()
	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerProgress.clear_session()
	Journal.end_test()
	CrawlerMeta.end_test()
	print("crawler_swarm_hold_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_swarm_hold_test failed: %s" % label)
