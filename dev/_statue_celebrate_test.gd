extends Node

## Filling a statue drops the sphere, sprays confetti, and pops the boost.
##
##     godot --headless --path . dev/_statue_celebrate_test.tscn

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

	var progress := _player.crawler_progress
	progress.claimed_statues = PackedStringArray()
	progress.remember()
	var statue := CrawlerStatue.new()
	statue.configure(CrawlerStatue.KIND_STRENGTH)
	add_child(statue)
	await get_tree().process_frame
	var aura := statue.find_child("StatueAura", true, false) as MeshInstance3D
	_expect(aura != null and aura.visible, "an unspent statue shows its sphere")
	var blessing := statue.tick_presence(CrawlerStatue.FILL_SECONDS, true, _player)
	_expect(statue.claimed and not blessing.is_empty(), "the bar spends the statue")
	_expect(aura != null and not aura.visible, "the sphere disappears")
	var pop := statue.find_child("StatueBlessing", true, false) as Label3D
	var copy := CrawlerStatue.popup_text(blessing)
	_expect(pop != null and pop.text == copy and not copy.is_empty(),
		"stat text pops off the statue")
	_expect(copy.contains(CrawlerProgress.stat_title(
			str(blessing.get("id", ""))).to_upper()),
		"the pop names the stat")
	_expect(copy.contains("+") or copy.contains("-"),
		"the pop names the amount")
	var burst := statue.find_child("CrawlerBurst", true, false)
	_expect(burst != null, "confetti pops out of the statue")
	if burst is CrawlerBurst:
		_expect((burst as CrawlerBurst).colors() == CrawlerBurst.CONFETTI_COLORS,
			"the burst uses confetti colours")
	print("statue_celebrate_test: pop='%s'" % copy)

	statue.queue_free()
	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("statue_celebrate_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("statue_celebrate_test failed: %s" % label)
