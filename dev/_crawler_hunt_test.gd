extends Node

## Shared agro / pursue / deagro / reagro for field packs.
##
##     godot --headless --path . dev/_crawler_hunt_test.tscn

var _failures := 0


class _Prey extends Node3D:
	var velocity := Vector3.ZERO

	func look_direction() -> Vector3:
		return Vector3.FORWARD


func _ready() -> void:
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

	_expect(CrawlerHunt.role("tanglemaw") == CrawlerHunt.Role.MELEE
			and CrawlerHunt.role("gloam") == CrawlerHunt.Role.MELEE
			and CrawlerHunt.role("rammer") == CrawlerHunt.Role.MELEE,
		"melee packs share a charge hunt")
	_expect(CrawlerHunt.role("scout") == CrawlerHunt.Role.FLY_RANGE
			and CrawlerHunt.role("ranger") == CrawlerHunt.Role.FLY_RANGE
			and CrawlerHunt.role("vesper") == CrawlerHunt.Role.FLY_RANGE
			and CrawlerHunt.role("kestrel") == CrawlerHunt.Role.FLY_RANGE
			and CrawlerHunt.role("threnody") == CrawlerHunt.Role.FLY_RANGE,
		"saucers, rangers, kestrels, and winged demons share a flying hunt")
	_expect(CrawlerHunt.role("bastion") == CrawlerHunt.Role.GROUND_RANGE
			and CrawlerHunt.role("weaver") == CrawlerHunt.Role.GROUND_RANGE
			and CrawlerHunt.role("gray") == CrawlerHunt.Role.GROUND_RANGE
			and CrawlerHunt.role("rhino") == CrawlerHunt.Role.GROUND_RANGE,
		"bastions, spiders, grays, and rhinos share a ground hunt")
	_expect(CrawlerHunt.prefer_ring("threnody") == CrawlerRules.FIELD_RING_FAR
			and CrawlerHunt.prefer_ring("ranger") == CrawlerRules.FIELD_RING_MID
			and CrawlerHunt.hold_min("scout") >= CrawlerHunt.CROWN_CLEAR
			and CrawlerHunt.hold_min("vesper")
				>= CrawlerRules.FIELD_RING_START + CrawlerRules.FIELD_RING_THICK,
		"flyers prefer the mid ring and stay off the crown")
	_expect(CrawlerHunt.DEAGRO == 50.0 and CrawlerHunt.REAGRO == 25.0
			and CrawlerHunt.SPAWN_TICK < CrawlerRules.FIELD_RING_SPAWN_TICK
			and CrawlerHunt.pursuit_speed("tanglemaw", 40.0, 6.0)
				< CrawlerHunt.pursuit_speed("gloam", 40.0, 9.0),
		"deagro is 50 m, reagro is 25 m, and tanglemaws pursue slowly")
	_expect(CrawlerHunt.SCOUT_FIRE > 2.0, "scouts fire slower than a ranger volley")

	var prey := _Prey.new()
	prey.name = "HuntPrey"
	prey.add_to_group(&"network_players")
	add_child(prey)
	prey.global_position = Vector3.ZERO
	CrawlerMobSense.invalidate()
	CrawlerMobSense.begin_frame(get_tree())

	var maw := horde.spawn_test_mob("tanglemaw", Vector3(20.0, 2.0, 0.0), false, 1)
	maw.set_physics_process(false)
	_expect(maw.tick_agro(prey, 0.16) and maw.chase
			and maw.hunt_stance == CrawlerHunt.Stance.AGRO,
		"a tanglemaw in the close ring charges without waiting for melee range")
	maw.global_position = Vector3(51.0, 2.0, 0.0)
	_expect(not maw.tick_agro(prey, 0.16) and not maw.chase
			and maw.hunt_stance == CrawlerHunt.Stance.DEAGRO,
		"any hunter deagros past 50 m")
	maw.global_position = Vector3(40.0, 2.0, 0.0)
	_expect(not maw.tick_agro(prey, 0.16) and not maw.chase,
		"deagroed packs do not wake at 40 m")
	maw.global_position = Vector3(24.0, 2.0, 0.0)
	_expect(maw.tick_agro(prey, 0.16) and maw.chase
			and maw.hunt_stance == CrawlerHunt.Stance.AGRO,
		"deagroed packs reagro inside 25 m")

	prey.velocity = Vector3(40.0, 0.0, 0.0)
	maw.global_position = Vector3(-8.0, 2.0, 0.0)
	maw.tick_agro(prey, 0.16)
	_expect(maw.hunt_stance == CrawlerHunt.Stance.PURSUE,
		"melee packs pursue when the player outruns them")

	var spider := horde.spawn_test_mob("glorb_spider", Vector3(18.0, 2.0, 0.0), false, 1)
	spider.set_physics_process(false)
	prey.global_position = Vector3.ZERO
	prey.velocity = Vector3(40.0, 0.0, 0.0)
	_expect(spider.tick_agro(prey, 0.16) and spider.chase
			and spider.hunt_stance == CrawlerHunt.Stance.AGRO,
		"a spider plants at 18 m even if the player is sprinting")
	spider.global_position = Vector3(32.0, 2.0, 0.0)
	_expect(spider.tick_agro(prey, 0.16)
			and spider.hunt_stance == CrawlerHunt.Stance.PURSUE,
		"a spider pursues only when the player is outside 20 m")
	spider.global_position = Vector3(14.0, 2.0, 0.0)
	_expect(spider.tick_agro(prey, 0.16)
			and spider.hunt_stance == CrawlerHunt.Stance.AGRO,
		"a spider settles and plants again inside 15 m")

	prey.velocity = Vector3.ZERO
	prey.global_position = Vector3(16.0, 2.0, 0.0)
	var gloam := horde.spawn_test_mob("gloam", Vector3(0.0, 2.0, 0.0), false, 1)
	gloam.set_physics_process(false)
	_expect(gloam.tick_agro(prey, 0.16) and gloam.chase
			and gloam.hunt_stance == CrawlerHunt.Stance.AGRO,
		"a gloam in the close ring wakes and charges")
	gloam.call("_pursue", prey, 0.16, true)
	_expect(not gloam.flies() and gloam.velocity.x > 0.4,
		"agroed gloam jogs toward the player instead of running in place")
	var started := gloam.global_position
	gloam._cached_up = Vector3.UP
	gloam._cached_up_at = gloam.global_position
	gloam.global_position += gloam.velocity * 0.16
	gloam._ground_from = gloam.global_position
	gloam._ground_hit = started - Vector3(0.0, gloam.ground_clearance(), 0.0)
	gloam.snap_to_ground()
	_expect(gloam.global_position.x > started.x + 0.05,
		"ground snap does not rewind a jogging gloam")
	prey.velocity = Vector3(16.0, 0.0, 0.0)
	gloam.call("_pursue", prey, 0.16, true)
	_expect(gloam.flies() and gloam.current_clip() == "Fly",
		"a gloam takes off when the player runs")
	prey.velocity = Vector3.ZERO
	prey.global_position = Vector3.ZERO

	var vesper := horde.spawn_test_mob("vesper", Vector3(50.0, 2.0, 0.0), false, 1)
	vesper.set_physics_process(false)
	_expect(vesper.tick_agro(prey, 0.16) and vesper.chase,
		"a four-wing wakes at its catalog agro range")
	vesper.global_position = Vector3(60.0, 2.0, 0.0)
	_expect(vesper.tick_agro(prey, 0.16) and vesper.chase
			and vesper.hunt_stance != CrawlerHunt.Stance.DEAGRO,
		"a four-wing stays on past the melee 50 m drop")
	_expect(CrawlerHunt.shot_min("vesper") <= 18.5
			and CrawlerHunt.shot_max("vesper") >= 48.0
			and vesper._track_hold_min() <= 24.0
			and vesper._track_hold_max() >= 36.0,
		"a four-wing holds and fires in the ranger standoff, not the mid pack ring")
	vesper.global_position = Vector3(48.0, 8.0, 0.0)
	vesper.call("_tick_far", 0.16)
	_expect(vesper.chase and vesper.velocity.length() > 1.0,
		"a four-wing closes onto its hold without a think token")
	vesper.global_position = Vector3(28.0, 8.0, 0.0)
	vesper.velocity = Vector3.ZERO
	CrawlerMobSense.begin_frame(get_tree())
	vesper.call("_tick_far", 0.16)
	_expect(vesper.aiming() and (vesper.locked_aim() as Vector3).is_finite(),
		"a four-wing charges its laser once it holds the ring")
	for _i in 8:
		CrawlerMobSense.take_attack("gloam")
	_expect(CrawlerMobSense.take_attack("vesper"),
		"a four-wing beam is not starved by the bite budget")

	var hymn := horde.spawn_test_mob("threnody", Vector3(80.0, 22.0, 0.0), false, 1)
	hymn.set_physics_process(false)
	_expect(hymn.tick_agro(prey, 0.16) and hymn.chase,
		"a six-wing wakes inside 96 m")
	_expect(hymn.tick_agro(prey, 0.16) and hymn.chase
			and hymn.hunt_stance != CrawlerHunt.Stance.DEAGRO,
		"a six-wing does not deagro at its hold ring")
	hymn.global_position = Vector3(120.0, 22.0, 0.0)
	_expect(hymn.tick_agro(prey, 0.16) and hymn.chase,
		"a six-wing wakes as soon as it can see the player")
	var station: Vector3 = hymn.call("hold_station", prey)
	CrawlerMobSense.begin_frame(get_tree())
	hymn.call("_tick_far", 0.16)
	_expect(hymn.velocity.dot(station - hymn.global_position) > 0.0,
		"a six-wing flies into the player's look, not a ranger ring")
	_expect(hymn.live_columns() > 0, "a six-wing drops a static column without a think token")
	var column: Node = hymn._columns[0] if not hymn._columns.is_empty() else null
	_expect(column != null
			and column.global_position.distance_to(prey.global_position) < 12.0,
		"the column lands on the player, not under the giant")

	var scout := horde.spawn_test_mob("scout", Vector3(0.0, 8.0, 38.0), true, 1)
	scout.set_physics_process(false)
	_expect(scout._track_hold_min() >= CrawlerHunt.CROWN_CLEAR
			and scout._track_hold_min()
				>= CrawlerRules.FIELD_RING_START + CrawlerRules.FIELD_RING_THICK,
		"a scout holds the mid ring instead of the crown")

	var kite := horde.spawn_test_mob("kestrel", Vector3(50.0, 8.0, 0.0), false, 1)
	kite.set_physics_process(false)
	_expect(kite.tick_agro(prey, 0.16) and kite.chase
			and kite._track_hold_min() <= 26.0
			and kite._track_hold_max() <= 44.0,
		"a kestrel wakes from the mid ring and holds its gun standoff")
	kite.global_position = Vector3(32.0, 8.0, 0.0)
	CrawlerMobSense.begin_frame(get_tree())
	kite.call("_tick_far", 0.16)
	_expect(str(kite.call("current_clip")) == "Fire_Burst",
		"a kestrel gatling-fires without a think token")

	var bastion := horde.spawn_test_mob("bastion", Vector3(8.0, 2.0, 0.0), false, 1)
	bastion.set_physics_process(false)
	_expect(bastion.tick_agro(prey, 0.16) and bastion.chase,
		"every bastion can agro; there is no live slot cap")
	var gun := horde.spawn_test_mob("bastion", Vector3(60.0, 2.0, 0.0), false, 1)
	gun.set_physics_process(false)
	_expect(CrawlerMobs.number("bastion", 1, "agro_range", 0.0) >= 64.0
			and CrawlerHunt.shot_max("bastion") >= 64.0
			and gun.tick_agro(prey, 0.16) and gun.chase,
		"a bastion wakes and can lob from 60 m")
	CrawlerMobSense.begin_frame(get_tree())
	gun.call("_tick_far", 0.16)
	var shells := 0
	for node: Node in horde.find_children("*", "", true, false):
		if str(node.name).begins_with("CrawlerBastionShell"):
			shells += 1
	_expect(shells >= 1, "a far bastion lobs without a think token")
	var from := Vector3(0.0, 1.5, 0.0)
	var aim := Vector3(0.0, 1.5, 36.0)
	var launch := CrawlerRules.high_lob_launch(
		from, aim, Vector3.ZERO, 24.0, CrawlerRules.BASTION_GRAVITY, Vector3.UP)
	var pos := from
	var vel := launch
	var dt := 0.016
	for _i in 400:
		vel -= Vector3.UP * CrawlerRules.BASTION_GRAVITY * dt
		pos += vel * dt
		if pos.y <= 1.5 and vel.y < 0.0:
			break
	_expect(pos.distance_to(aim) < 4.0 and pos.distance_to(from) > 24.0,
		"a bastion shell lands on the aim instead of falling on the walker")

	prey.queue_free()
	horde.queue_free()
	await get_tree().process_frame
	print("crawler_hunt_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_hunt_test failed: %s" % label)
