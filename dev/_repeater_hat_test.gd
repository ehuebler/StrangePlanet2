extends Node

## Repeater cap taps every equipped ability once a second, and a self-fuse
## shortens that cadence.
##
##     godot --headless --path . res://dev/_repeater_hat_test.tscn

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
	_expect(_player.crawler_kit.shop_grant("starfire"),
		"starfire can sit next to laser eyes")
	_player._arrival_left = 0.0
	_player._reveal_left = 0.0
	var progress := _player.crawler_progress
	progress.grant_hat(CrawlerProgress.HAT_REPEATER, true)
	_player.refresh_crawler_look()
	_expect(progress.wearing_repeater_hat(), "the repeater cap goes on")
	_expect(is_equal_approx(
			progress.repeater_interval(), CrawlerRules.REPEATER_HAT_INTERVAL),
		"one copy fires once a second")
	_expect(progress.hat_blurb(CrawlerProgress.HAT_REPEATER).contains("once a second"),
		"the stall copy names the one-second cadence")

	var keep := progress.worn_hat
	var other := progress.grant_hat(CrawlerProgress.HAT_REPEATER)
	progress.gold += CrawlerProgress.HAT_MERGE_PRICE
	_expect(progress.merge_hats(keep, other), "two repeater caps fuse")
	_expect(progress.hat_effect_rank(CrawlerProgress.FX_REPEATER) == 2,
		"a self-fuse stacks the repeater effect")
	_expect(progress.repeater_interval() < CrawlerRules.REPEATER_HAT_INTERVAL,
		"a self-fuse shortens the cadence")
	_expect(is_equal_approx(
			progress.repeater_interval(),
			CrawlerRules.REPEATER_HAT_INTERVAL / (
				1.0 + CrawlerRules.REPEATER_HAT_INTERVAL_SHRINK)),
		"the fused cadence matches the stack shrink")

	var fired: PackedStringArray = PackedStringArray()
	_player.ability_activated.connect(func(_index: int, ability_id: String) -> void:
		fired.append(ability_id)
	)
	_player._repeater_cooldown = 0.0
	_player._tick_repeater_hat(0.02)
	_expect(fired.size() >= 2, "one pulse taps every equipped ability")
	var eyes := _player.ability_controller().ability_in(0)
	_expect(eyes != null and eyes.is_held(),
		"laser eyes keep the burst after the repeater tap")
	_expect(_player.laser_beams().is_lit(),
		"laser eyes stay drawn after the repeater tap")
	_player._tick_repeater_hat(0.02)
	_expect(fired.size() == 2, "the cap waits out its cadence before the next pulse")
	if eyes != null:
		eyes.tick(CrawlerRules.LASER_DURATION + 0.05)
	_player._tick_repeater_hat(progress.repeater_interval())
	_expect(fired.size() >= 4, "the next pulse fires after the shortened wait")

	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(_player.crawler_kit.shop_grant("laser_eyes"),
		"a second laser eyes can sit next to the first")
	_expect(_player.crawler_kit.shop_grant("icicle"),
		"icicle can sit with two laser eyes")
	await get_tree().process_frame
	fired.clear()
	_player._repeater_cooldown = 0.0
	_player._tick_repeater_hat(0.02)
	var named := PackedStringArray()
	for raw: String in fired:
		named.append(CrawlerCatalog.ability_id(raw))
	_expect(named.has("laser_eyes") and named.has("icicle"),
		"the cap taps both laser eyes and icicle")
	_expect(named.count("laser_eyes") >= 2,
		"both laser eyes fire on the same pulse")
	var first := _player.ability_controller().ability_in(0)
	var second := _player.ability_controller().ability_in(1)
	_expect(first != null and first.is_held() and second != null and second.is_held(),
		"both laser eyes keep their bursts after the tap")
	_expect(_player.laser_beams().is_lit(),
		"two laser eyes still draw after the tap")
	_expect(_player.laser_beams().pair_count() >= 2,
		"both laser eyes draw their own pair")

	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("repeater_hat_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("repeater_hat_test failed: %s" % label)
