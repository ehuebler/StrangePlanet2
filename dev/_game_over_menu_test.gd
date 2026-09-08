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
		false,
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
	var button := screen.respawn_button()
	var plate := screen.find_child("Plate", true, false) as Control
	_expect(button != null and plate != null and button.text == DeathScreen.HOME_LABEL,
		"%s has HOME on a plate" % label)
	if button == null or plate == null:
		screen.queue_free()
		await get_tree().process_frame
		return
	var btn := CrtType.screen_rect(button)
	var box := CrtType.screen_rect(plate)
	var frame := screen.get_global_rect()
	print("game_over_menu_test: %s plate=%.0f,%.0f-%.0f,%.0f home=%.0f,%.0f-%.0f,%.0f" % [
		label, box.position.x, box.position.y, box.end.x, box.end.y,
		btn.position.x, btn.position.y, btn.end.x, btn.end.y,
	])
	_expect(btn.size.x >= 8.0 and btn.size.y >= 8.0,
		"%s HOME has a real size" % label)
	_expect(
		btn.position.y >= box.position.y - 1.0
		and btn.end.y <= box.end.y + 2.0
		and btn.position.x >= box.position.x - 1.0
		and btn.end.x <= box.end.x + 2.0,
		"%s keeps HOME on the plate" % label)
	_expect(
		box.position.y >= frame.position.y - 1.0
		and box.end.y <= frame.end.y + 2.0
		and box.position.x >= frame.position.x - 1.0
		and box.end.x <= frame.end.x + 2.0,
		"%s keeps the plate on screen" % label)
	_expect(not plate.clip_contents, "%s does not clip HOME off the plate" % label)
	screen.queue_free()
	await get_tree().process_frame


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("game_over_menu_test failed: %s" % label)
