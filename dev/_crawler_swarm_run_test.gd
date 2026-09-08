extends Node

## Run the player through armed patches while a mixed pack agroes. Homes
## already queued for those cells must not drip in mid-sprint.
##
##     godot --headless --path . dev/_crawler_swarm_run_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const MOB_SENSE := preload("res://game/crawler/crawler_mob_sense.gd")
const RUN_STEPS := 16
const STEP_FRAMES := 3
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
	_player.velocity = Vector3(80.0, 0.0, 0.0)
	await get_tree().process_frame

	var horde := CrawlerHorde.new()
	add_child(horde)
	var near_homes: Array = []
	var far_homes: Array = []
	for index in 8:
		near_homes.append(Vector3(18.0 + float(index) * 3.0, 5.0, 2.0))
		far_homes.append(Vector3(150.0 + float(index) * 3.0, 5.0, -2.0))
	_expect(horde.fill_test_patch(1, near_homes, "ranger", 1) == 8
			and horde.fill_test_patch(2, far_homes, "ranger", 1) == 8,
		"both run patches queue their whole roster up front")
	_expect(horde.fill_test_patch(1, [Vector3(40.0, 5.0, 0.0)], "ranger", 1) == 0
			and horde.fill_test_patch(2, [Vector3(170.0, 5.0, 0.0)], "ranger", 1) == 0,
		"armed patches do not queue more homes as the player moves")
	while horde.queued_spawn_count() > 0:
		horde._drain_builds()
	for index in 4:
		horde.spawn_test_mob(
			"ranger", Vector3(80.0 + float(index) * 6.0, 5.0, 3.0), false)
	for index in 10:
		horde.spawn_test_mob(
			"rhino", Vector3(30.0 + float(index) * 16.0, 5.0, -6.0), false)
	for index in 10:
		horde.spawn_test_mob(
			"rammer", Vector3(24.0 + float(index) * 16.0, 6.0, 8.0), false)
	_expect(horde.wild_live_count() == 40 and horde.queued_spawn_count() == 0,
		"the run fields 20 rangers, 10 rhinos, and 10 rammers before the sprint")

	MOB_SENSE.invalidate()
	var live_at_start := horde.wild_live_count()
	var worst_ms := 0.0
	var peak_think := 0
	var peak_attack := 0
	var saw_chase := 0
	for step in RUN_STEPS:
		_player.global_position = Vector3(float(step) * 14.0, 4.0, 0.0)
		for _tick in STEP_FRAMES:
			var clock := Time.get_ticks_usec()
			await get_tree().physics_frame
			var frame_ms := float(Time.get_ticks_usec() - clock) * 0.001
			worst_ms = maxf(worst_ms, frame_ms)
			var board: Dictionary = MOB_SENSE.director_counts()
			saw_chase = maxi(saw_chase, int(board.get("chase", 0)))
			if step >= 2:
				_expect(int(board.get("frame_think_ok", 0))
						<= int(board.get("think_budget", 0)),
					"the run keeps unique hunt planning inside the scaled think budget")
				_expect(int(board.get("frame_attack_ok", 0))
						<= int(board.get("attack_budget", 0)),
					"the run keeps new attacks inside the scaled attack budget")
				peak_think = maxi(peak_think, int(board.get("frame_think_ok", 0)))
				peak_attack = maxi(peak_attack, int(board.get("frame_attack_ok", 0)))
		_expect(horde.queued_spawn_count() == 0,
			"a sprint does not queue new homes mid-run")
		_expect(horde.wild_live_count() == live_at_start,
			"armed patches do not instantiate extra bodies while the player runs")

	var think_cap := CrawlerRules.think_budget_for(saw_chase)
	var attack_cap := CrawlerRules.attack_budget_for(saw_chase)
	_expect(saw_chase >= 8, "mobs agro as the player runs through the lane")
	_expect(worst_ms < MAX_FRAME_MS,
		"the run stays under %.0f ms per physics frame" % MAX_FRAME_MS)
	print("crawler_swarm_run: worst %.2f ms  chase %d  think %d/%d  attack %d/%d  live %d" % [
		worst_ms, saw_chase, peak_think, think_cap, peak_attack, attack_cap,
		horde.wild_live_count()])

	horde.queue_free()
	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerProgress.clear_session()
	Journal.end_test()
	CrawlerMeta.end_test()
	print("crawler_swarm_run_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_swarm_run_test failed: %s" % label)
