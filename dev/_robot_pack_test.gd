extends Node

## Office robots: a thin weaver pack and a capped bastion pack.
##
##     godot --headless --path . dev/_robot_pack_test.tscn

const MOB_SENSE := preload("res://game/crawler/crawler_mob_sense.gd")

var _failures := 0


func _ready() -> void:
	CrawlerRules.glorb_field = false
	CrawlerCatalog.reload()
	CrawlerMobs.reload()
	NetworkManager.session_options = {"mode": "crawler"}
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)

	_expect(CrawlerMobs.spawn_mode("bastion", 1) == "pack"
			and CrawlerMobs.agro_mode("bastion", 1) == "reserve",
		"bastions no longer plant a grid")
	_expect(CrawlerRules.bastion_agro_cap(1) >= 2
			and CrawlerRules.bastion_agro_cap(1) <= 3
			and CrawlerRules.bastion_reserve_cap(1) >= 4
			and CrawlerRules.bastion_reserve_cap(1) <= 8
			and CrawlerMobs.kind_cap("bastion", 1) <= 11,
		"level one keeps 2-3 agroed bastions and 4-8 reserves")
	_expect(CrawlerMobs.kind_cap("weaver", 1) >= 8
			and CrawlerMobs.kind_cap("weaver", 1) <= 14
			and CrawlerRules.WEAVER_FLOCK <= 3
			and CrawlerMobs.number("weaver", 1, "health", 9.0) <= 4.5,
		"weavers stay a thin low-health close pack")
	var robot := CrawlerRules.field_kinds(CrawlerRules.TOWER_PATCH)
	var demon := CrawlerRules.field_kinds(CrawlerRules.CITY_PATCH)
	var close_robot := CrawlerRules.pack_kinds_for_ring(
		CrawlerRules.FIELD_RING_CLOSE, robot)
	var mid_robot := CrawlerRules.pack_kinds_for_ring(
		CrawlerRules.FIELD_RING_MID, robot)
	var far_robot := CrawlerRules.pack_kinds_for_ring(
		CrawlerRules.FIELD_RING_FAR, robot)
	var far_demon := CrawlerRules.pack_kinds_for_ring(
		CrawlerRules.FIELD_RING_FAR, demon)
	_expect(CrawlerRules.field_ring_of(28.0) == CrawlerRules.FIELD_RING_CLOSE
			and CrawlerRules.field_ring_of(42.0) == CrawlerRules.FIELD_RING_MID
			and CrawlerRules.field_ring_of(58.0) == CrawlerRules.FIELD_RING_FAR
			and CrawlerRules.field_ring_of(70.0) == CrawlerRules.FIELD_RING_NONE
			and CrawlerRules.field_ring_min(CrawlerRules.FIELD_RING_CLOSE)
				< CrawlerRules.field_ring_fill(CrawlerRules.FIELD_RING_CLOSE)
			and CrawlerRules.field_ring_fill(CrawlerRules.FIELD_RING_CLOSE)
				< CrawlerRules.field_ring_max(CrawlerRules.FIELD_RING_CLOSE)
			and CrawlerRules.field_ring_max(CrawlerRules.FIELD_RING_CLOSE) <= 100
			and CrawlerRules.field_ring_max(CrawlerRules.FIELD_RING_MID) <= 50
			and CrawlerRules.field_ring_max(CrawlerRules.FIELD_RING_FAR) <= 25,
		"three 15 m rings sit at 20 m and leave a buffer under each cap")
	_expect(close_robot.has("weaver")
			and not close_robot.has("gloam")
			and not close_robot.has("kestrel")
			and mid_robot.has("bastion")
			and mid_robot.has("kestrel")
			and not mid_robot.has("weaver")
			and far_robot.has("kestrel")
			and not far_robot.has("threnody")
			and far_demon.has("threnody")
			and CrawlerRules.pack_kinds_for_ring(
				CrawlerRules.FIELD_RING_CLOSE, CrawlerRules.WILD_KINDS).has("rhino")
			and not CrawlerRules.pack_kinds_for_ring(
				CrawlerRules.FIELD_RING_CLOSE, CrawlerRules.WILD_KINDS).has("weaver"),
		"rings only place kinds from the tile pack")
	_expect(CrawlerRules.field_ring_should_engage(28.0, "weaver")
			and CrawlerRules.field_ring_should_engage(42.0, "bastion")
			and CrawlerRules.field_ring_should_engage(64.0, "bastion")
			and CrawlerRules.field_ring_should_engage(58.0, "kestrel")
			and CrawlerRules.field_ring_should_engage(58.0, "threnody")
			and CrawlerRules.field_ring_spawn_agro(
				CrawlerRules.FIELD_RING_CLOSE, "weaver", 0)
			and not CrawlerRules.field_ring_spawn_agro(
				CrawlerRules.FIELD_RING_FAR, "kestrel", 9)
			and CrawlerRules.field_ring_spawn_agro(
				CrawlerRules.FIELD_RING_FAR, "threnody", 9)
			and CrawlerRules.pack_homes("threnody", true) == 1,
		"close bodies, bastions, and kestrels engage; far flyers stay calm except one threnody")
	_expect(CrawlerRules.mob_lod(20.0) == CrawlerRules.MOB_LOD_HOT
			and CrawlerRules.mob_lod(50.0) == CrawlerRules.MOB_LOD_WARM
			and CrawlerRules.mob_lod(100.0) == CrawlerRules.MOB_LOD_COLD
			and CrawlerRules.MOB_LOD_HOT_RANGE <= 40.0
			and CrawlerRules.MOB_WARM_STRIDE >= 4
			and CrawlerRules.MOB_COLD_STRIDE >= 12,
		"unique AI stays in a close bubble; far packs tick less often")

	var weaver := horde.spawn_test_mob("weaver", Vector3(-4.0, 2.0, 0.0), false, 1)
	_expect(weaver != null and weaver.body_height() < 1.8
			and weaver.body_height() > 0.7
			and weaver.maximum_health() <= 5.0,
		"a weaver spawns small and fragile")
	weaver.set_physics_process(false)
	var mark := Node3D.new()
	add_child(mark)
	mark.global_position = weaver.global_position + Vector3(0.0, 1.0, 8.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	weaver.velocity = Vector3(6.0, 0.0, 0.0)
	weaver.call("_try_beam", mark)
	_expect(bool(weaver.call("charging")) and weaver.velocity.length() < 0.05,
		"a weaver locks in place to charge")
	weaver.call("_service_beam", 0.1)
	var eyes := weaver.get_node_or_null("WeaverEyes")
	_expect(bool(weaver.call("charging")) and eyes != null and bool(eyes.call("is_lit")),
		"a red beam charges on the player before the shot")
	weaver.call("_service_beam", 0.4)
	_expect(bool(weaver.call("firing")) and not bool(weaver.call("charging")),
		"the charge finishes into Laser Eyes")
	mark.queue_free()
	var compact := horde.spawn_test_mob("bastion", Vector3(12.0, 2.0, 0.0), true, 1)
	_expect(compact != null and compact.body_height() < 3.2
			and compact.body_height() > 1.6,
		"bastions are compact walkers")
	compact.set_physics_process(false)
	compact.chase = true
	var looker := Node3D.new()
	add_child(looker)
	looker.global_position = compact.global_position + Vector3(0.0, 0.0, 8.0)
	compact.director_far_steer(0.2, looker, false)
	var face := compact.global_transform.basis.z
	var toward := looker.global_position - compact.global_position
	toward.y = 0.0
	face.y = 0.0
	_expect(face.length() > 0.01 and toward.length() > 0.01
			and face.normalized().dot(toward.normalized()) > 0.35,
		"an agroed bastion faces the player")
	looker.queue_free()

	var prey := Node3D.new()
	prey.name = "RobotPrey"
	prey.add_to_group(&"network_players")
	add_child(prey)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())

	prey.global_position = Vector3(0.0, 1000.0, 0.0)
	var facing := horde.spawn_test_mob("weaver", Vector3(0.0, 1000.0, 28.0), false, 1)
	facing.set_physics_process(false)
	var face_spawn := facing.global_transform.basis.z
	var toward_spawn := prey.global_position - facing.global_position
	face_spawn.y = 0.0
	toward_spawn.y = 0.0
	_expect(face_spawn.length() > 0.01 and toward_spawn.length() > 0.01
			and face_spawn.normalized().dot(toward_spawn.normalized()) > 0.35,
		"ring homes spawn facing the player")

	var close_runner := horde.spawn_test_mob(
		"weaver", Vector3(0.0, 1000.0, 30.0), false, 1)
	close_runner.set_physics_process(false)
	var mid_gun := horde.spawn_test_mob(
		"bastion", Vector3(0.0, 1000.0, 42.0), false, 1)
	mid_gun.set_physics_process(false)
	await get_tree().process_frame
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	MOB_SENSE.direct_horde(0.05)
	_expect(close_runner.chase and mid_gun.chase,
		"the monitor engages the close ring and mid-ring bastions")
	close_runner.global_position = prey.global_position + Vector3(8.0, 0.0, 0.0)
	horde.call(&"_trim_ring_overflow", prey)
	_expect(is_instance_valid(close_runner) and not close_runner.dismissed,
		"walking inside the close ring does not despawn a spawned body")
	var leftover := horde.spawn_test_mob(
		"weaver", prey.global_position + Vector3(0.0, 0.0, 90.0), false, 1)
	leftover.set_physics_process(false)
	horde.call(&"_trim_ring_overflow", prey)
	_expect(is_instance_valid(leftover) and not leftover.dismissed,
		"walking off a spawn ring does not despawn the pack you left")

	var rammer := horde.spawn_test_mob(
		"rammer", prey.global_position + Vector3(0.0, 2.2, 0.0), true, 1)
	rammer.set_physics_process(false)
	rammer.director_far_steer(0.16, prey, false)
	_expect(not is_instance_valid(rammer) or not rammer.is_alive(),
		"a rammer explodes on impact instead of pushing through")

	var hunter := horde.spawn_test_mob("bastion", Vector3(20.0, 2.0, 0.0), true, 1)
	hunter.set_physics_process(false)
	prey.global_position = hunter.global_position + Vector3(0.0, 0.0, 88.0)
	var stood := hunter.global_position
	hunter.director_far_steer(0.2, prey, false)
	_expect(hunter.velocity.length() > 0.2
			or hunter.global_position.distance_to(stood) > 0.01,
		"an agroed bastion still walks in from outside mortar range")

	var walker := horde.spawn_test_mob("gray", Vector3(180.0, 2.0, 0.0), false, 1)
	walker.set_physics_process(false)
	walker.set_director_lod(CrawlerRules.MOB_LOD_COLD)
	walker.velocity = Vector3(4.0, 0.0, 0.0)
	var before := walker.global_position
	walker.director_cold_tick(0.05, 0.0, false, null, false)
	_expect(walker.global_position.distance_to(before) > 0.04,
		"a far walker coasts without a ground probe")

	prey.queue_free()
	horde.queue_free()
	await get_tree().process_frame
	print("robot_pack_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("robot_pack_test failed: %s" % label)
