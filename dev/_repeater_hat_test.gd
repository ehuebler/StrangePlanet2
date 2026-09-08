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
	_player._tick_repeater_hat(0.02)
	_expect(fired.size() == 2, "the cap waits out its cadence before the next pulse")
	_player._tick_repeater_hat(progress.repeater_interval())
	_expect(fired.size() >= 4, "the next pulse fires after the shortened wait")

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
