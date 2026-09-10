extends Node

## Infinite stores lift upgrade rank caps so a stat can keep going.
##
##     godot --headless --path . res://dev/_unlimited_upgrades_test.tscn

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

	_player.crawler_kit.seed_starter()
	_expect(_player.crawler_kit.shop_grant("clip"), "clip can be granted")
	var clip: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "clip":
			clip = card
			break
	_expect(clip != null, "the granted card is clip")
	if clip == null:
		_finish()
		return
	_expect(_player.crawler_kit.upgrade_card(clip.uid, "ammo")
			and _player.crawler_kit.upgrade_card(clip.uid, "ammo"),
		"clip can reach its usual cap")
	_expect(clip.upgrade_rank("ammo") == CrawlerRules.CLIP_MAX_RANK,
		"clip sits on the authored cap")
	_expect(not _player.crawler_kit.upgrade_card(clip.uid, "ammo"),
		"normal stores stop clip at the cap")
	_expect(CrawlerRules.upgrade_at_cap(
			"clip", "ammo", clip.upgrade_rank("ammo"), false),
		"the cap helper still sees a normal stop")
	_player.crawler_progress.gold = 9999
	_player.crawler_progress.set_shops_unlimited(true)
	_expect(not CrawlerRules.upgrade_at_cap(
			"clip", "ammo", clip.upgrade_rank("ammo"), true),
		"infinite stores lift the clip cap")
	_expect(_player.crawler_kit.upgrade_card(clip.uid, "ammo"),
		"infinite stores let clip keep going")
	_expect(clip.upgrade_rank("ammo") == CrawlerRules.CLIP_MAX_RANK + 1,
		"clip can pass the authored cap")
	_expect(CrawlerRules.clip_ammo_mul(clip.upgrade_rank("ammo"))
			== CrawlerRules.CLIP_BASE_MUL + CrawlerRules.CLIP_MAX_RANK + 1,
		"extra clip ranks still raise the magazine")

	var host := Control.new()
	host.name = "UpgradeHost"
	host.custom_minimum_size = Vector2(1280.0, 720.0)
	host.size = Vector2(1280.0, 720.0)
	add_child(host)
	CrtType.watch(host)
	var page := CrawlerStoreUpgradesPage.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.configure(_player)
	host.add_child(page)
	page._select(clip.token())
	page.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var act := page.find_child("UpgradeAct_ammo", true, false) as Button
	var act_box := CrtType.screen_rect(act)
	_expect(act != null and act.text == "UPGRADE" and not act.disabled,
		"the upgrade stall keeps selling a maxed stat under infinite stores")
	_expect(CrtType.host_of(act) != null,
		"the upgrade button wears CRT type")
	_expect(act_box.size.x >= 48.0 and act_box.size.y >= 18.0,
		"the upgrade button stays wide enough to read")
	page.queue_free()
	host.queue_free()

	_finish()


func _finish() -> void:
	if is_instance_valid(_player):
		_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("unlimited_upgrades_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("unlimited_upgrades_test failed: %s" % label)
