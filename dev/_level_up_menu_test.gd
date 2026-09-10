extends Node

## Solo level-up opens the spend board. Coop auto-claims and does not.
##
##     godot --headless --path . dev/_level_up_menu_test.tscn

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

	await _check_solo()
	await _check_auto()
	await _check_coop()
	await _check_coop_prefs()

	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("level_up_menu_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _seed_offers() -> void:
	_player.crawler_progress.ranks[CrawlerProgress.STAT_DAMAGE] = 0.0
	_player.crawler_progress.ranks[CrawlerProgress.STAT_DODGE] = 0.0
	_player.crawler_progress.ranks[CrawlerProgress.STAT_HEALTH] = 0.0
	_player.crawler_progress.unspent = 1
	_player.crawler_progress.force_level_offers([
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_HEALTH, CrawlerProgress.RARITY_UNCOMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DEXTERITY, CrawlerProgress.RARITY_COMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DODGE, CrawlerProgress.RARITY_RARE),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DAMAGE, CrawlerProgress.RARITY_LEGENDARY),
	])


func _clear_hud() -> void:
	var hud := _player.hud
	if hud == null:
		return
	for name: String in ["CrawlerLevelBurst", "CrawlerLevelMenu"]:
		var node := hud.get_node_or_null(name)
		if node != null:
			node.queue_free()
	_player.close_menu()
	await get_tree().process_frame


func _check_solo() -> void:
	NetworkManager.is_single_player = true
	_seed_offers()
	_player._on_crawler_leveled_up()
	await get_tree().process_frame
	var hud := _player.hud
	_expect(hud != null, "solo player has a HUD")
	if hud == null:
		return
	var burst := hud.get_node_or_null("CrawlerLevelBurst")
	_expect(burst != null, "solo level-up plays the burst")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"solo spend board waits for the burst")
	_expect(_player.crawler_progress.unspent == 1,
		"solo level-up keeps the point")
	if burst != null:
		burst._process(CrawlerLevelBurst.HOLD)
	await get_tree().process_frame
	_expect(hud.get_node_or_null("CrawlerLevelBurst") == null,
		"solo burst leaves")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") != null,
		"solo level-up opens the spend board")
	_expect(_player._menu_open, "solo level-up pauses the run")
	var menu := hud.get_node_or_null("CrawlerLevelMenu") as CrawlerLevelMenu
	_expect(menu != null and menu.find_child("AutoSelectToggle", true, false) != null,
		"the spend board has an auto select button")
	_expect(menu != null and menu.find_child("LevelTab_Prefs", true, false) != null,
		"the spend board has Auto Select Prefs")
	await get_tree().process_frame
	var auto := menu.find_child("AutoSelectToggle", true, false) as Button
	var reroll := menu.find_child("RerollOffers", true, false) as Button
	var auto_crt := CrtType.host_of(auto)
	var reroll_crt := CrtType.host_of(reroll)
	_expect(auto_crt != null and auto_crt.glitch > 0.0,
		"auto select wears the CRT type")
	_expect(reroll_crt != null and reroll_crt.glitch > 0.0,
		"reroll wears the CRT type")
	_expect(_level_button_rim(auto) != null and _level_button_rim(reroll) != null,
		"auto select and reroll wear CRT rims")
	menu.show_tab(CrawlerLevelMenu.Tab.PREFS)
	var prefs_tab := menu.find_child("LevelTab_Prefs", true, false) as Button
	var prefs_rim := _level_button_rim(prefs_tab)
	_expect(prefs_rim != null and prefs_rim.crt_material() != null
			and prefs_rim.border_color.g > prefs_rim.border_color.r,
		"switching tabs still paints the CRT rim")
	menu.show_tab(CrawlerLevelMenu.Tab.SPEND)
	await _clear_hud()


func _check_coop() -> void:
	NetworkManager.is_single_player = false
	_seed_offers()
	_player._on_crawler_leveled_up()
	await get_tree().process_frame
	var hud := _player.hud
	_expect(hud != null, "coop player has a HUD")
	if hud == null:
		return
	_expect(_player.crawler_progress.unspent == 0, "coop level-up spends itself")
	_expect(is_equal_approx(_player.crawler_progress.rank_of(CrawlerProgress.STAT_DAMAGE),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_LEGENDARY)),
		"coop takes the highest rarity")
	_expect(is_equal_approx(_player.crawler_progress.rank_of(CrawlerProgress.STAT_HEALTH),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_UNCOMMON)),
		"coop also takes the next matching pref")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"coop level-up does not open the spend board")
	var burst := hud.get_node_or_null("CrawlerLevelBurst")
	if burst != null:
		burst._process(CrawlerLevelBurst.HOLD)
	await get_tree().process_frame
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"coop still has no spend board after the burst")
	NetworkManager.is_single_player = true
	await _clear_hud()


func _check_auto() -> void:
	NetworkManager.is_single_player = true
	CrawlerMeta.set_auto_select(true)
	_seed_offers()
	_player._on_crawler_leveled_up()
	await get_tree().process_frame
	var hud := _player.hud
	_expect(_player.crawler_progress.unspent == 0,
		"solo auto select spends the point")
	_expect(is_equal_approx(_player.crawler_progress.rank_of(CrawlerProgress.STAT_DAMAGE),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_LEGENDARY)),
		"solo auto select takes the highest rarity match")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"solo auto select does not open the spend board")
	var burst := hud.get_node_or_null("CrawlerLevelBurst")
	if burst != null:
		burst._process(CrawlerLevelBurst.HOLD)
	await get_tree().process_frame
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"solo auto select still has no spend board after the burst")
	_player._handle_crawler_auto_key()
	_expect(not CrawlerMeta.auto_select(),
		"K turns auto select off")
	await _clear_hud()


func _check_coop_prefs() -> void:
	NetworkManager.is_single_player = false
	CrawlerMeta.set_auto_select(false)
	_player._handle_crawler_auto_key()
	await get_tree().process_frame
	var hud := _player.hud
	var menu := hud.get_node_or_null("CrawlerLevelMenu") as CrawlerLevelMenu
	_expect(menu != null and menu.current_tab() == CrawlerLevelMenu.Tab.PREFS,
		"coop K opens Auto Select Prefs")
	_expect(menu != null and menu.find_child("AutoPref_strength", true, false) != null,
		"coop prefs still list the category boxes")
	_player._handle_crawler_auto_key()
	await get_tree().process_frame
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"coop K closes the prefs board")
	NetworkManager.is_single_player = true
	await _clear_hud()


func _level_button_rim(button: Control) -> RedGlowPanel:
	var walk: Node = button
	while walk != null:
		var rim := walk.get_node_or_null("RedGlowPanel") as RedGlowPanel
		if rim != null:
			return rim
		walk = walk.get_parent()
	return null


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("level_up_menu_test failed: %s" % label)
