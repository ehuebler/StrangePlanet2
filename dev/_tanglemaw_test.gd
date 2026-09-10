extends Node

## Tanglemaws sprint when idle and always agro when you stand next to them.
##
##     godot --headless --path . dev/_tanglemaw_test.tscn

var _failures := 0


func _ready() -> void:
	CrawlerCatalog.reload()
	NetworkManager.session_options = {"mode": "crawler"}
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)
	_check_frantic_roam(horde)
	await _check_nearby_agro(horde)
	horde.queue_free()
	await get_tree().process_frame
	print("tanglemaw_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_frantic_roam(horde: CrawlerHorde) -> void:
	var maw := horde.spawn_test_mob("tanglemaw", Vector3(8.0, 2.0, 0.0), false, 1) \
		as CrawlerTanglemaw
	_expect(maw != null and not maw.chase, "a field tanglemaw starts idle")
	if maw == null:
		return
	maw.set_physics_process(false)
	maw.velocity = Vector3.ZERO
	maw._patrol_left = 0.0
	maw._tick_idle(0.2)
	var first := maw._patrol_goal
	_expect(maw.velocity.length() > 3.5,
		"a deagroed tanglemaw sprints instead of standing still")
	maw._patrol_left = 0.0
	maw._tick_idle(0.2)
	_expect(first.distance_to(maw._patrol_goal) > 4.0,
		"a deagroed tanglemaw keeps picking new sprint points")
	maw.velocity = Vector3.ZERO
	maw._tick_far(0.2)
	_expect(maw.velocity.length() > 3.5,
		"a far tanglemaw keeps sprinting when nobody is in range")
	if is_instance_valid(maw):
		maw.queue_free()


func _check_nearby_agro(horde: CrawlerHorde) -> void:
	var prey := Node3D.new()
	prey.name = "TanglePrey"
	prey.add_to_group(&"network_players")
	add_child(prey)
	prey.global_position = Vector3(2.0, 2.0, 0.0)
	var maw := horde.spawn_test_mob("tanglemaw", Vector3(5.0, 2.0, 0.0), false, 1) \
		as CrawlerTanglemaw
	_expect(maw != null and not maw.chase, "a nearby tanglemaw starts idle")
	if maw == null:
		prey.queue_free()
		return
	maw.set_physics_process(false)
	CrawlerMobSense.invalidate()
	CrawlerMobSense.begin_frame(get_tree())
	while CrawlerMobSense.take_think(null, true):
		pass
	for _tick in 6:
		maw._physics_process(0.05)
	_expect(maw.chase,
		"a tanglemaw standing next to the player agros even when think is spent")
	_expect(maw.velocity.length() > 2.0,
		"an agroed tanglemaw runs at the player")
	prey.queue_free()
	if is_instance_valid(maw):
		maw.queue_free()


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("tanglemaw_test failed: %s" % label)
