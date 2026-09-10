extends Node

## Walks every crawler UI page and writes a PNG of each one.
##
##     godot --path . dev/_crawler_ui_shot.tscn
##
## Needs a real window. Headless skips the captures and still prints the fit
## report, so cut-off and off-centre chrome still show up in the log.
## Saves under dev/captures/crawler_ui_*.png.

const PLAYER := preload("res://game/player/player.tscn")
const CAPTURE_DIR := "res://dev/captures"
const SETTLE_FRAMES := 4
const PAGE_WAIT := 0.28

const GAME_TABS := [
	{"name": "tab_hero", "tab": GameMenu.Tab.HERO},
	{"name": "tab_hats", "tab": GameMenu.Tab.APPAREL},
	{"name": "tab_items", "tab": GameMenu.Tab.ITEMS},
	{"name": "tab_quests", "tab": GameMenu.Tab.QUESTS},
	{"name": "tab_achievements", "tab": GameMenu.Tab.ACHIEVEMENTS},
	{"name": "tab_settings", "tab": GameMenu.Tab.SETTINGS},
]

const STORE_TABS := [
	{"name": "store_hats", "tab": CrawlerFieldMenu.Tab.HATS},
	{"name": "store_caps", "tab": CrawlerFieldMenu.Tab.CAPS},
	{"name": "store_capes", "tab": CrawlerFieldMenu.Tab.CAPES},
	{"name": "store_mods", "tab": CrawlerFieldMenu.Tab.CARDS},
	{"name": "store_abilities", "tab": CrawlerFieldMenu.Tab.ABILITIES},
	{"name": "store_upgrades", "tab": CrawlerFieldMenu.Tab.UPGRADES},
	{"name": "store_inventory", "tab": CrawlerFieldMenu.Tab.INVENTORY},
	{"name": "store_locker", "tab": CrawlerFieldMenu.Tab.LOCKER},
	{"name": "store_quests", "tab": CrawlerFieldMenu.Tab.QUESTS},
	{"name": "store_market", "tab": CrawlerFieldMenu.Tab.MARKET},
	{"name": "store_reststop", "tab": CrawlerFieldMenu.Tab.RESTSTOP},
	{"name": "store_duals", "tab": CrawlerFieldMenu.Tab.DUALS},
]

var _player: OnlinePlayer
var _view: SubViewport
var _host_control: Control
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

	_build_stage()
	await get_tree().process_frame
	_fit_host()
	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_player.defer_camera = true
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	if _player.hud != null:
		_player.hud.visible = false
	await get_tree().process_frame
	_stock_run()
	await _settle(SETTLE_FRAMES)

	await _shot_game_menu()
	await _shot_field_menu()
	await _shot_level_menu()
	await _shot_duel_menu()
	await _shot_entering()
	await _shot_level_burst()
	await _shot_achievement_burst()
	await _shot_game_over()

	_teardown()
	print("crawler_ui_shot: done, %d fit warning(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _build_stage() -> void:
	var wanted := _shot_size()
	_view = SubViewport.new()
	_view.name = "UiShotView"
	_view.size = wanted
	_view.transparent_bg = false
	_view.disable_3d = true
	_view.handle_input_locally = false
	_view.gui_disable_input = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_host_control = Control.new()
	_host_control.name = "ShotHost"
	_host_control.size = Vector2(wanted)
	_host_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_host_control)
	var ground := ColorRect.new()
	ground.name = "ShotGround"
	ground.color = Color(0.04, 0.015, 0.02, 1.0)
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host_control.add_child(ground)


func _fit_host() -> void:
	if _view == null or _host_control == null:
		return
	var wanted := _shot_size()
	_view.size = wanted
	_host_control.size = Vector2(wanted)


func _shot_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	)


func _page_view() -> Rect2:
	if _view != null:
		return Rect2(Vector2.ZERO, Vector2(_view.size))
	return get_viewport().get_visible_rect()


func _stock_run() -> void:
	var progress := _player.crawler_progress
	if progress == null:
		push_error("crawler_ui_shot: player has no crawler ledger")
		return
	progress.gold = 9999
	progress.unspent = 1
	progress.set_shops_unlimited(false)
	progress.force_level_offers([
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_HEALTH, CrawlerProgress.RARITY_UNCOMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DEXTERITY, CrawlerProgress.RARITY_COMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DODGE, CrawlerProgress.RARITY_RARE),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DAMAGE, CrawlerProgress.RARITY_LEGENDARY),
	])
	progress.grant_hat(CrawlerProgress.HAT_ID, true)
	progress.grant_hat(CrawlerProgress.HAT_LUCK)
	progress.grant_hat(CrawlerProgress.HAT_LEARNED)
	progress.grant_cape(CrawlerProgress.CAPE_ID, true)
	progress.grant_hat(CrawlerProgress.HAT_FOOL)
	progress.unlock_site(CrawlerRules.START_SITE_ID)
	progress.unlock_site(CrawlerRules.CITY_SITE_ID)
	var kit := _player.crawler_kit
	if kit != null:
		kit.shop_grant("starfire")
		kit.shop_grant("wobble")
		kit.shop_grant("homing")
		kit.shop_grant("icicle")


func _shot_game_menu() -> void:
	var menu := GameMenu.new()
	menu.configure(_player)
	_host().add_child(menu)
	await _settle(2)
	for entry: Dictionary in GAME_TABS:
		menu.show_tab(entry["tab"])
		await _wait(PAGE_WAIT)
		var shot := str(entry["name"])
		_report_named(shot, menu, [
			"InsetMenuShell", "ContentFrame", "BottomSelector",
			"SessionActions", "SandboxCheats",
		])
		await _capture(shot)
	await _drop(menu)


func _shot_field_menu() -> void:
	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	_player.global_position = Vector3.ZERO
	await get_tree().process_frame
	var menu := CrawlerFieldMenu.new()
	menu.configure(_player)
	_host().add_child(menu)
	await _settle(2)
	_report_store_tabs(menu)
	for entry: Dictionary in STORE_TABS:
		menu.set_tab(entry["tab"])
		await _wait(PAGE_WAIT)
		var shot := str(entry["name"])
		_report_named(shot, menu, [
			"StoreShell", "StoreColumn", "StoreBorder", "MenuBackground",
			"StoreTabs", "StoreTabRow1", "StoreTabRow2",
		])
		_report_overflow(shot, menu)
		await _capture(shot)
	await _drop(menu)
	await _drop(ring)


func _shot_level_menu() -> void:
	var menu := CrawlerLevelMenu.new()
	menu.configure(_player)
	_host().add_child(menu)
	await _wait(PAGE_WAIT)
	_report_named("level", menu, ["LevelCard", "SpendTiles", "RerollOffers"])
	_report_overflow("level", menu)
	await _capture("level")
	await _drop(menu)


func _shot_duel_menu() -> void:
	var menu := CrawlerDuelMenu.new()
	menu.configure(_player)
	_host().add_child(menu)
	await _wait(PAGE_WAIT)
	_report_named("duel", menu, ["DuelEndCard"])
	_report_centered("duel", menu.find_child("DuelEndCard", true, false) as Control)
	await _capture("duel")
	await _drop(menu)


func _shot_entering() -> void:
	var note := CrawlerEnteringNote.new()
	_host().add_child(note)
	note.present("Tide Margin", 8)
	note.modulate = Color.WHITE
	await _wait(0.2)
	_report_named("entering", note, ["EnteringTitle", "EnteringGems"])
	await _capture("entering")
	await _drop(note)


func _shot_level_burst() -> void:
	var burst := CrawlerLevelBurst.new()
	_host().add_child(burst)
	await _wait(0.22)
	_report_named("level_burst", burst, ["LevelUpTitle"])
	await _capture("level_burst")
	await _drop(burst)


func _shot_achievement_burst() -> void:
	var burst := AchievementBurst.new()
	burst.configure("Kill 10 mobs", PackedStringArray(["50 XP", "10 GEMS"]))
	_host().add_child(burst)
	await _wait(0.22)
	_report_named("achievement_burst", burst, [
		"AchievementCompleteTitle",
		"AchievementCompleteName",
		"AchievementCompleteRewards",
	])
	await _capture("achievement_burst")
	await _drop(burst)


func _shot_game_over() -> void:
	var screen := DeathScreen.new()
	_host().add_child(screen)
	screen.present_crawler(
		"Killed by Rhino: Meteor Strike",
		"23 MOBS KILLED\n2 SITES DISCOVERED\nTIDE MARGIN\nCRESCENT MARKET\n54 GEMS EARNED",
		true,
		{
			"achievements": [
				{
					"id": "kills",
					"title": "KILL 10 MOBS",
					"rewards": PackedStringArray(["50 XP"]),
				},
				{
					"id": "rank",
					"title": "RECRUIT",
					"rewards": PackedStringArray(["10 GEMS"]),
				},
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
	screen._shown = DeathScreen.ARM_DELAY
	screen.finish_recap()
	await _settle(2)
	screen._fit_plate()
	await _wait(PAGE_WAIT)
	_report_named("game_over", screen, [
		"Plate", "Title", "Notice", "Summary", "HomeButton", "RespawnButton",
		"RunRecapScroll",
	])
	_report_centered("game_over", screen.find_child("Plate", true, false) as Control)
	_report_button_on_plate(screen)
	_report_overflow("game_over", screen)
	await _capture("game_over")
	await _drop(screen)


func _drop(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _host() -> Node:
	return _host_control


func _report_named(page: String, root: Node, names: Array) -> void:
	if root == null:
		_fail("%s root is missing" % page)
		return
	var view := _page_view()
	for node_name: Variant in names:
		var id := str(node_name)
		var control := root.find_child(id, true, false) as Control
		if control == null and root is Control and (root as Control).name == id:
			control = root as Control
		if control == null or not control.visible:
			continue
		var box := CrtType.screen_rect(control)
		if box.size.x < 2.0 or box.size.y < 2.0:
			continue
		var inside := view.encloses(box.grow(-1.0))
		print("crawler_ui_shot: %-20s %-16s at %4.0f,%4.0f size %4.0fx%-4.0f inside=%s" % [
			page, id, box.position.x, box.position.y, box.size.x, box.size.y, inside,
		])
		if not inside:
			_fail("%s %s is cut off by the viewport" % [page, id])


func _report_centered(page: String, control: Control) -> void:
	if control == null or not control.visible:
		return
	var view := _page_view()
	var mid := CrtType.screen_rect(control).get_center()
	var want := view.get_center()
	var delta := mid - want
	print("crawler_ui_shot: %-20s center_delta %+6.1f,%+6.1f" % [
		page, delta.x, delta.y,
	])
	if absf(delta.x) > 24.0 or absf(delta.y) > 24.0:
		_fail("%s is not centred (delta %.0f,%.0f)" % [page, delta.x, delta.y])


func _report_button_on_plate(screen: DeathScreen) -> void:
	var plate := screen.find_child("Plate", true, false) as Control
	if plate == null:
		_fail("game_over is missing the plate")
		return
	var box := CrtType.screen_rect(plate)
	for button: Button in [screen.home_button(), screen.respawn_button()]:
		if button == null or not button.visible:
			_fail("game_over is missing HOME or RESPAWN")
			return
		var btn := CrtType.screen_rect(button)
		var on := btn.position.y >= box.position.y - 1.0 \
				and btn.end.y <= box.end.y + 2.0 \
				and btn.position.x >= box.position.x - 1.0 \
				and btn.end.x <= box.end.x + 2.0
		print("crawler_ui_shot: game_over %s on_plate=%s btn=%.0f,%.0f-%.0f,%.0f plate=%.0f,%.0f-%.0f,%.0f" % [
			button.text, on, btn.position.x, btn.position.y, btn.end.x, btn.end.y,
			box.position.x, box.position.y, box.end.x, box.end.y,
		])
		if not on:
			_fail("game_over %s is cut off by the plate" % button.text)


func _report_store_tabs(menu: CrawlerFieldMenu) -> void:
	if menu == null:
		_fail("city store menu is missing")
		return
	var row1 := menu.find_child("StoreTabRow1", true, false) as HBoxContainer
	var row2 := menu.find_child("StoreTabRow2", true, false) as HBoxContainer
	if row1 == null or row2 == null:
		_fail("city store tabs are missing the two-row host")
		return
	print("crawler_ui_shot: store_tabs rows %d+%d" % [
		row1.get_child_count(), row2.get_child_count(),
	])
	if row1.get_child_count() != 6 or row2.get_child_count() != 6:
		_fail("city store tabs are not two rows of six")
	var view := _page_view()
	for shop_id: String in CrawlerProgress.SHOP_IDS:
		var button := menu.find_child("StoreTabButton_%s" % shop_id, true, false) as Button
		if button == null or not button.is_visible_in_tree():
			_fail("city store is missing tab %s" % shop_id)
			continue
		var box := CrtType.screen_rect(button)
		if box.size.x < 2.0 or box.size.y < 2.0:
			_fail("city store tab %s has no size" % shop_id)
			continue
		var inside := view.encloses(box.grow(-1.0))
		print("crawler_ui_shot: store_tabs %-16s at %4.0f,%4.0f size %4.0fx%-4.0f inside=%s" % [
			shop_id, box.position.x, box.position.y, box.size.x, box.size.y, inside,
		])
		if not inside:
			_fail("city store tab %s is cut off by the viewport" % shop_id)


func _report_overflow(page: String, root: Control) -> void:
	if root == null:
		return
	_walk_overflow(root, _page_view(), page)


func _walk_overflow(node: Node, view: Rect2, page: String) -> void:
	if node is Label:
		var label := node as Label
		if label.visible:
			var box := CrtType.screen_rect(label)
			if box.size.x >= 8.0 and box.size.y >= 8.0 \
					and not view.encloses(box.grow(-1.0)):
				print("crawler_ui_shot: %-20s overflow %s rect=%.0f,%.0f %.0fx%.0f" % [
					page, label.name, box.position.x, box.position.y,
					box.size.x, box.size.y,
				])
	for child: Node in node.get_children():
		_walk_overflow(child, view, page)


func _fail(message: String) -> void:
	_failures += 1
	push_error("crawler_ui_shot: %s" % message)


func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _capture(capture_name: String) -> void:
	if _view == null:
		_fail("shot viewport is missing")
		return
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := _view.get_texture().get_image()
	if image == null:
		_fail("could not read %s" % capture_name)
		return
	var wanted := _shot_size()
	if image.get_size() != wanted:
		image.resize(wanted.x, wanted.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path(
		"%s/crawler_ui_%s.png" % [CAPTURE_DIR, capture_name])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) == OK:
		print("crawler_ui_shot: saved %s (%dx%d)" % [path, wanted.x, wanted.y])
	else:
		_fail("could not save %s" % path)


func _teardown() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
