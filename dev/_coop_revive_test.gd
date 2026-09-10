extends Node

## Co-op downed bodies, hold-E revive, ticket respawn while a teammate is up,
## and a wipe only when everyone is down without tickets.
##
##     godot --headless --path . dev/_coop_revive_test.tscn

const PLAYER := preload("res://game/player/player.tscn")

var _failures := 0
var _player: OnlinePlayer
var _mate: OnlinePlayer


func _ready() -> void:
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerCatalog.reload()
	CrawlerProgress.clear_session()
	CrawlerMeta.begin_test()
	Journal.begin_test()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = false
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME

	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_player.defer_camera = true
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)

	_mate = PLAYER.instantiate() as OnlinePlayer
	_mate.peer_id = 2
	_mate.display_name = "Scout"
	_mate.defer_camera = true
	add_child(_mate)
	_mate.set_process(false)
	_mate.set_physics_process(false)
	await get_tree().process_frame

	_player.global_position = Vector3.ZERO
	_mate.global_position = Vector3(2.0, 0.0, 0.0)
	_clear_tickets()

	await _check_downed_while_teammate_up()
	await _check_wipe_without_tickets()
	await _check_hold_revive()
	await _check_ticket_while_teammate_up()
	await _check_wipe_with_tickets()
	await _check_solo_wipe()

	_player.queue_free()
	if is_instance_valid(_mate):
		_mate.queue_free()
	print("coop_revive_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_downed_while_teammate_up() -> void:
	_expect(CrawlerRules.coop() and not CrawlerRules.crawler_party_wiped(),
		"coop starts with someone standing")
	_player._die(null)
	await get_tree().process_frame
	var screen := _player.death_screen()
	_expect(_player.is_dead() and not _mate.is_dead(),
		"the local body stays down while the teammate is up")
	_expect(screen != null and screen.is_downed()
			and screen.title_text() == DeathScreen.DOWNED_TITLE,
		"a living teammate shows DOWNED, not game over")
	_expect(screen.summary_text() == DeathScreen.WAITING_COPY,
		"DOWNED tells you a teammate can hold E")
	_expect(screen.respawn_button() != null and not screen.respawn_button().visible,
		"without a ticket DOWNED hides RESPAWN")
	_expect(_player.crawler_progress == null
			or not _player.crawler_progress.settled_global,
		"a downed player does not settle the run")


func _check_wipe_without_tickets() -> void:
	_mate._die(null)
	await get_tree().process_frame
	_expect(CrawlerRules.crawler_party_wiped(),
		"the last death wipes the party")
	var screen := _player.death_screen()
	_expect(screen != null and not screen.is_downed()
			and screen.title_text() == DeathScreen.GAME_OVER_TITLE,
		"the last death turns DOWNED into GAME OVER")
	_expect(screen.home_button() != null
			and screen.home_button().visible
			and screen.home_button().text == DeathScreen.HOME_LABEL
			and screen.respawn_button() != null
			and screen.respawn_button().visible
			and screen.respawn_button().text == DeathScreen.RESPAWN_LABEL,
		"a wipe without tickets still offers a free RESPAWN")
	_expect(_player.crawler_progress != null
			and _player.crawler_progress.settled_global,
		"a wipe without tickets settles the run")


func _check_hold_revive() -> void:
	_stand_party()
	_mate.global_position = Vector3(20.0, 0.0, 0.0)
	_mate._die(null)
	await get_tree().process_frame
	_expect(_player.nearest_downed_teammate() == null,
		"revive reach does not stretch across the field")
	_player.tick_revive_hold(CrawlerRules.REVIVE_HOLD, true)
	_expect(_mate.is_dead(), "holding E out of range does not get them up")
	_mate.global_position = Vector3(2.0, 0.0, 0.0)
	_player._update_hud(0.0)
	_expect(_player.prompt_plate.visible
			and _player.interact_prompt.text.contains("Revive"),
		"a downed teammate in reach prompts Hold E")
	_player.tick_revive_hold(CrawlerRules.REVIVE_HOLD * 0.5, true)
	_expect(is_equal_approx(_player.revive_hold_progress(), 0.5)
			and _mate.is_dead(),
		"a half hold is not enough")
	_player.tick_revive_hold(CrawlerRules.REVIVE_HOLD * 0.5, true)
	await get_tree().process_frame
	_expect(not _mate.is_dead(), "holding E through the bar revives in place")
	_expect(_mate.global_position.distance_to(Vector3(2.0, 0.0, 0.0)) < 0.05,
		"the revive stands them up where they fell")
	_expect(_player.crawler_progress == null
			or not _player.crawler_progress.settled_global,
		"a teammate revive does not settle the run")
	_player.tick_revive_hold(0.2, false)
	_expect(is_equal_approx(_player.revive_hold_progress(), 0.0),
		"letting go of E clears the hold")


func _check_ticket_while_teammate_up() -> void:
	_stand_party()
	_set_tickets(1)
	_player._die(null)
	await get_tree().process_frame
	var screen := _player.death_screen()
	_expect(screen != null and screen.is_downed()
			and screen.title_text() == DeathScreen.DOWNED_TITLE,
		"a ticket still leaves you DOWNED while a teammate is up")
	_expect(screen.respawn_button() != null
			and screen.respawn_button().visible
			and screen.respawn_button().text == DeathScreen.RESPAWN_LABEL
			and not screen.sends_home(),
		"DOWNED still offers a ticket RESPAWN")
	_expect(_player.crawler_progress != null
			and not _player.crawler_progress.settled_global,
		"a ticket downed state does not settle the run")
	var spent := _player.crawler_progress.spend_respawn_ticket()
	_expect(spent and not CrawlerRules.crawler_has_respawn_ticket(),
		"the dead player can spend a ticket while the teammate is up")
	_player.respawn_at(_player.global_transform)
	await get_tree().process_frame
	_expect(not _player.is_dead() and _player.death_screen() == null,
		"spending the ticket stands the local player back up")


func _check_wipe_with_tickets() -> void:
	_stand_party()
	_set_tickets(1)
	_player._die(null)
	await get_tree().process_frame
	_mate._die(null)
	await get_tree().process_frame
	_expect(CrawlerRules.crawler_party_wiped()
			and CrawlerRules.crawler_has_respawn_ticket(),
		"tickets do not stop a party wipe, they keep the run open")
	var screen := _player.death_screen()
	_expect(screen != null and not screen.is_downed()
			and screen.title_text() == DeathScreen.GAME_OVER_TITLE
			and not screen.sends_home()
			and screen.respawn_button() != null
			and screen.respawn_button().text == DeathScreen.RESPAWN_LABEL,
		"everyone down with a ticket still offers RESPAWN")
	_expect(_player.crawler_progress != null
			and not _player.crawler_progress.settled_global,
		"a wiped party with tickets does not settle the run")


func _check_solo_wipe() -> void:
	_stand_party()
	_clear_tickets()
	_mate.queue_free()
	_mate = null
	await get_tree().process_frame
	NetworkManager.is_single_player = true
	_player._die(null)
	await get_tree().process_frame
	var screen := _player.death_screen()
	_expect(screen != null and not screen.is_downed()
			and screen.title_text() == DeathScreen.GAME_OVER_TITLE
			and screen.home_button() != null and screen.home_button().visible
			and screen.respawn_button() != null
			and screen.respawn_button().text == DeathScreen.RESPAWN_LABEL,
		"solo death without a ticket is GAME OVER with HOME and free RESPAWN")
	_expect(_player.crawler_progress != null
			and _player.crawler_progress.settled_global,
		"solo death without a ticket still settles the run")


func _stand_party() -> void:
	if is_instance_valid(_player) and _player.is_dead():
		_player.respawn_at(_player.global_transform)
	if is_instance_valid(_mate) and _mate.is_dead():
		_mate.respawn_at(_mate.global_transform)
	if _player.crawler_progress != null:
		_player.crawler_progress.settled_global = false
	if is_instance_valid(_mate) and _mate.crawler_progress != null:
		_mate.crawler_progress.settled_global = false
	_clear_tickets()
	if is_instance_valid(_player):
		_player.global_position = Vector3.ZERO
	if is_instance_valid(_mate):
		_mate.global_position = Vector3(2.0, 0.0, 0.0)


func _clear_tickets() -> void:
	_set_tickets(0)


func _set_tickets(count: int) -> void:
	if is_instance_valid(_mate) and _mate.crawler_progress != null:
		_mate.crawler_progress.respawn_tickets = 0
	if is_instance_valid(_player) and _player.crawler_progress != null:
		_player.crawler_progress.respawn_tickets = count
		_player.crawler_progress.remember()


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  ok  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
