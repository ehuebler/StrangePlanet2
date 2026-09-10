extends Node

## Headless layout check for the crawler GAME OVER plate.
##
##     godot --headless --path . dev/_game_over_menu_test.tscn

var _failures := 0


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

	await _check_tall_recap(Vector2(1280.0, 640.0), "short window")
	await _check_tall_recap(Vector2(1280.0, 720.0), "720p")
	await _check_home_returns_to_title()

	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("game_over_menu_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_tall_recap(view: Vector2, label: String) -> void:
	var screen := DeathScreen.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.custom_minimum_size = view
	screen.size = view
	screen.present_crawler(
		"Killed by Rhino: Meteor Strike",
		"23 MOBS KILLED\n2 SITES DISCOVERED\nTIDE MARGIN\nCRESCENT MARKET\n54 GEMS EARNED",
		true,
		{
			"achievements": [
				{"id": "kills", "title": "KILL 10 MOBS", "rewards": PackedStringArray(["50 XP"])},
				{"id": "rank", "title": "RECRUIT", "rewards": PackedStringArray(["10 GEMS"])},
			],
			"score": {
				"total": 375,
				"lines": PackedStringArray([
					"215 FROM EXPEDITION XP",
					"45 FROM SITES DISCOVERED",
					"115 FROM MOBS KILLED",
				]),
			},
			"levels": [
				{"level": 3, "title": "", "title_changed": false},
				{"level": 4, "title": "", "title_changed": false},
				{"level": 5, "title": "Recruit", "title_changed": true},
			],
			"before": {"xp": 110.0},
			"after": {"xp": 485.0},
		})
	screen.modulate = Color.WHITE
	screen.finish_recap()
	for _i: int in 6:
		await get_tree().process_frame
		screen._fit_plate()
	var home := screen.home_button()
	var respawn := screen.respawn_button()
	var plate := screen.find_child("Plate", true, false) as Control
	_expect(home != null and home.visible and home.text == DeathScreen.HOME_LABEL
			and respawn != null and respawn.visible
			and respawn.text == DeathScreen.RESPAWN_LABEL
			and plate != null,
		"%s has HOME and RESPAWN on a plate" % label)
	if home == null or respawn == null or plate == null:
		screen.queue_free()
		await get_tree().process_frame
		return
	var box := CrtType.screen_rect(plate)
	var frame := screen.get_global_rect()
	print("game_over_menu_test: %s plate=%.0f,%.0f-%.0f,%.0f home=%.0f,%.0f-%.0f,%.0f respawn=%.0f,%.0f-%.0f,%.0f" % [
		label, box.position.x, box.position.y, box.end.x, box.end.y,
		CrtType.screen_rect(home).position.x, CrtType.screen_rect(home).position.y,
		CrtType.screen_rect(home).end.x, CrtType.screen_rect(home).end.y,
		CrtType.screen_rect(respawn).position.x, CrtType.screen_rect(respawn).position.y,
		CrtType.screen_rect(respawn).end.x, CrtType.screen_rect(respawn).end.y,
	])
	var home_btn := CrtType.screen_rect(home)
	var respawn_btn := CrtType.screen_rect(respawn)
	for pair: Array in [[home, home_btn], [respawn, respawn_btn]]:
		var button := pair[0] as Button
		var btn := pair[1] as Rect2
		_expect(btn.size.x >= 8.0 and btn.size.y >= 8.0,
			"%s %s has a real size" % [label, button.text])
		_expect(
			btn.position.y >= box.position.y - 1.0
			and btn.end.y <= box.end.y + 2.0
			and btn.position.x >= box.position.x - 1.0
			and btn.end.x <= box.end.x + 2.0,
			"%s keeps %s on the plate" % [label, button.text])
	_expect(home_btn.end.x <= respawn_btn.position.x + 1.0
			or respawn_btn.end.x <= home_btn.position.x + 1.0,
		"%s keeps HOME and RESPAWN side by side" % label)
	_expect(
		box.position.y >= frame.position.y - 1.0
		and box.end.y <= frame.end.y + 2.0
		and box.position.x >= frame.position.x - 1.0
		and box.end.x <= frame.end.x + 2.0,
		"%s keeps the plate on screen" % label)
	_expect(not plate.clip_contents, "%s does not clip the end buttons off the plate" % label)
	screen.queue_free()
	await get_tree().process_frame


func _check_home_returns_to_title() -> void:
	var world := _HomeStubWorld.new()
	world.name = "HomeStubWorld"
	var points := Node3D.new()
	points.name = "SpawnPoints"
	world.add_child(points)
	add_child(world)
	NetworkManager.active_world = world
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.session_options = {"mode": "crawler"}
	world.open_stub_session()
	var horde := Node.new()
	horde.name = "CrawlerHorde"
	world.add_child(horde)
	var screen := DeathScreen.new()
	world.add_child(screen)
	screen.present_crawler("Killed by test", "1 MOB KILLED", true)
	screen.home_requested.connect(world.leave_session)
	await get_tree().process_frame
	screen._process(DeathScreen.ARM_DELAY + 0.1)
	var home := screen.home_button()
	_expect(home != null and home.visible and not home.disabled,
		"GAME OVER HOME is armed")
	_expect(home != null and CrtType.host_of(home) == null,
		"GAME OVER HOME is not trapped in a CRT viewport")
	if home != null:
		home.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(NetworkManager.state == NetworkManager.SessionState.IDLE,
		"HOME ends the network session")
	_expect(not world.session_is_open(), "HOME closes the open world session")
	_expect(world.find_child("HomeScreen", false, false) != null,
		"HOME opens the title overlay")
	_expect(not is_instance_valid(horde) or horde.is_queued_for_deletion(),
		"HOME clears the live horde")
	world.queue_free()
	await get_tree().process_frame
	if NetworkManager.active_world == world:
		NetworkManager.active_world = null


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("game_over_menu_test failed: %s" % label)


class _HomeStubWorld extends GameWorld:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		NetworkManager.active_world = self

	func open_stub_session() -> void:
		_session_open = true
