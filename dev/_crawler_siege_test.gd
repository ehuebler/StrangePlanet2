extends Node

## Headless checks for crawler field rules: flight fuel, wild roster, levels,
## safe cities, and the HUD blue bar.
##
##     godot --headless --path . dev/_crawler_siege_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const CITY_RING := preload("res://game/crawler/crawler_city_ring.gd")

var _failures := 0
var _player: OnlinePlayer


class DummyLot extends Node:
	var wrecked := false

	func is_wrecked() -> bool:
		return wrecked


class _BlastDummy extends Node3D:
	var taken := 0.0

	func apply_damage(hit: DamageHit) -> float:
		var amount := float(hit.amount) if hit != null else 0.0
		taken += amount
		return amount

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.4

	func is_dead() -> bool:
		return false


class _StartPadWorld extends GameWorld:
	func _crawler_start_transform() -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(10.0, 20.0, 30.0))


func _ready() -> void:
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerCatalog.reload()
	CrawlerMobs.reload()
	CrawlerProgress.clear_session()
	CrawlerMeta.begin_test()
	Journal.begin_test()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME

	_check_destroy_rule()
	_check_density()
	_check_threat()
	_check_lead()
	_check_wild_rules()
	_check_city_tracker()

	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_player.defer_camera = true
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	await _check_safe_box()
	await _check_city_ring()
	_check_starfire_city_gift()
	_check_heal_and_flash()
	_check_horde_roster()
	await _check_idle_roam()
	await _check_enemy_presence()
	await _check_crawler_bursts()
	_check_flight_and_parry()
	_check_hud()
	_check_progress()
	await _check_level_burst()
	await _check_achievement_burst()
	await _check_city_store()
	await _check_crawler_death()
	await _check_monument_collision()
	_check_building_foundation()
	_check_building_flora()
	await _check_monument_quests()
	await _check_tilde_city_waypoint()
	await _check_entering_sites()

	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerProgress.clear_session()
	Journal.end_test()
	CrawlerMeta.end_test()
	print("crawler_siege_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_destroy_rule() -> void:
	_expect(not CrawlerRules.is_city_destroyed(0, 0), "empty city is not destroyed")
	_expect(not CrawlerRules.is_city_destroyed(3, 5), "exactly 60% is not destroyed")
	_expect(CrawlerRules.is_city_destroyed(4, 5), "more than 60% is destroyed")
	_expect(is_equal_approx(CrawlerRules.destruction_ratio(3, 5), 0.6),
		"destruction ratio is wrecked over total")
	_expect(CrawlerRules.CITY_INFLUENCE_METRES >= 500.0,
		"city influence is at least 500 metres")
	_expect(CrawlerRules.influence_radius_for_extent(800.0) >= 1300.0,
		"a large city keeps influence past its own pad")


func _check_density() -> void:
	_expect(is_equal_approx(CrawlerRules.city_density_weight(0.0), 1.0),
		"density is 1 at a city centre")
	_expect(is_zero_approx(CrawlerRules.city_density_weight(
		CrawlerRules.CITY_INFLUENCE_METRES)),
		"density is 0 at the influence rim")
	var mid := CrawlerRules.city_density_weight(100.0)
	_expect(mid > 0.0 and mid < 1.0, "density falls off away from the pad")
	_expect(CrawlerRules.city_density_weight(50.0)
		> CrawlerRules.city_density_weight(200.0),
		"spawn weight is denser near the centre")
	var wide := CrawlerRules.influence_radius_for_extent(800.0)
	_expect(CrawlerRules.city_density_weight(700.0, wide) > 0.0,
		"standing in a large city still counts as inside its horde ring")
	_expect(not PatchCity.facing_horizon(
		Vector3(0, 8100, 0), Vector3(0, -8000, 0), 8000.0, 200.0),
		"buildings on the far side of the planet stay hidden")
	_expect(PatchCity.facing_horizon(
		Vector3(0, 8100, 0), Vector3(0, 8000, 0), 8000.0, 200.0),
		"buildings facing the camera stay drawn")


func _check_threat() -> void:
	_expect(CrawlerRules.threat_speed(1) > 1.0, "threat raises movement speed")
	_expect(CrawlerRules.threat_health(1) > 1.0, "threat raises health")
	_expect(CrawlerRules.threat_damage(1) > 1.0, "threat raises damage")
	_expect(CrawlerRules.threat_fire(1) < 1.0, "threat shortens fire interval")
	_expect(CrawlerRules.threat_speed(2) > CrawlerRules.threat_speed(1),
		"higher levels move faster")


func _check_lead() -> void:
	var from := Vector3.ZERO
	var target := Vector3(0.0, 0.0, 20.0)
	var motion := Vector3(10.0, 0.0, 0.0)
	var speed := 40.0
	var launch := CrawlerRules.lead_launch(
		from, target, motion, speed, 0.0, Vector3.UP)
	_expect(launch.length() > speed * 0.9, "lead launch keeps shot speed")
	var closest := 1.0e9
	var t := 0.0
	while t <= 1.2:
		var shot := from + launch * t
		var body := target + motion * t
		closest = minf(closest, shot.distance_to(body))
		t += 0.01
	_expect(closest < 0.6, "led shot meets the moving body")


func _check_wild_rules() -> void:
	_expect(CrawlerRules.START_CITIES == 0, "crawler does not place a built city")
	_expect(CrawlerRules.START_PATCH == "Tide Margin 4", "crawler starts on Tide Margin 4")
	_expect(CrawlerRules.reserved_patch("Tide Margin 4"), "start patch is reserved")
	_expect(not CrawlerRules.reserved_patch("Tide Margin"),
		"other Tide Margin patches can hold monsters")
	_expect(CrawlerRules.CITY_RING_PUSH > 0.0, "city ring fallback still sits inland")
	_expect(is_equal_approx(CrawlerRules.CITY_LATITUDE_DEG, 0.18)
			and is_equal_approx(CrawlerRules.CITY_LONGITUDE_DEG, 4.78),
		"Neon Fjord sits at 0.18 N, 4.78 E")
	_expect(CrawlerRules.reserved_patch("Quiet Inlet 4"), "city patch is reserved")
	_expect(not CrawlerRules.reserved_patch("Quiet Inlet"),
		"other Quiet Inlet patches can hold monsters")
	_expect(CrawlerRules.TOWER_PATCH == "Far Beacon 4",
		"the office tower sits on Far Beacon 4")
	_expect(CrawlerRules.CASTLE_PATCH == "Long Shore 4",
		"the castle sits on Long Shore 4")
	_expect(not CrawlerRules.reserved_patch("Salt Prairie"),
		"ordinary patches can hold monsters")
	_expect(is_inf(LandPatchOverlay.spawn_slope_score(2.0, 2.0, 4.0)),
		"wet ground is not a crawler spawn")
	_expect(LandPatchOverlay.spawn_slope_score(3.0, 4.0, 22.0)
		< LandPatchOverlay.spawn_slope_score(12.0, 14.0, 22.0),
		"flatter pads win the Tide Margin spawn")
	_expect(LandPatchOverlay.peak_score(40.0, 0.0, 0.0)
			> LandPatchOverlay.peak_score(12.0, 0.0, 0.0),
		"higher dry ground still scores as a peak")
	_expect(is_equal_approx(CrawlerRules.SPAWN_LATITUDE_DEG, 3.09)
			and is_equal_approx(CrawlerRules.SPAWN_LONGITUDE_DEG, -1.28),
		"Relay 07 sits at 3.09 N, 1.28 W")
	_expect(LandPatchOverlay.peak_score(2.0, 0.0, 0.0) < 0.0,
		"wet ground is not the spawn peak")
	_expect(ResourceLoader.exists(CrawlerSpawnPad.MODEL),
		"Relay 07 is the Tide Margin spawn")
	_expect(CrawlerRules.SPAWN_MIN > CrawlerRules.AGRO_RANGE,
		"field spawns start outside agro")
	_expect(CrawlerRules.SPAWN_MAX <= CrawlerRules.START_ENCOUNTER,
		"field spawns sit inside the ahead encounter band")
	_expect(CrawlerRules.PACK_KEEP >= CrawlerRules.SPAWN_MAX
			and CrawlerRules.PACK_KEEP < CrawlerRules.WILD_STREAM_IN,
		"the following pack counts the ahead homes")
	_expect(CrawlerRules.LIVE_AROUND >= 24, "unsafe tiles keep a dense calm pack")
	CrawlerMobs.reload()
	_expect(CrawlerMobs.kinds_for(CrawlerRules.START_PATCH)
			== CrawlerRules.START_NEAR_KINDS,
		"the start pad CSV calls rangers and rhinos")
	_expect(CrawlerMobs.kinds_for(
			CrawlerRules.START_PATCH, CrawlerRules.START_NEAR_RANGE + 1.0)
			== CrawlerRules.START_FAR_KINDS,
		"the start pad CSV adds eyeballs farther out")
	_expect(CrawlerMobs.kinds_for("Salt Prairie") == CrawlerRules.WILD_KINDS,
		"later patches call the field pack from the CSV")
	_expect(not CrawlerMobs.kinds_for("Salt Prairie").has("rift_hulk"),
		"the box hulk is not on any field patch")
	_expect(CrawlerMobs.agro_mode("rammer", 1) == "leash"
			and CrawlerMobs.spawn_mode("rammer", 1) == "ahead",
		"level-1 rammers wait ahead of travel until the player closes")
	_expect(CrawlerMobs.attack_mode("rhino", 1) == "charge"
			and CrawlerMobs.attack_mode("ranger", 1) == "standoff",
		"each kind has an attack behavior at level 1")
	_expect(CrawlerMobs.number("ranger", 3, "health", 0.0)
			> CrawlerMobs.number("ranger", 1, "health", 0.0),
		"higher ranger levels raise health in the CSV")
	_expect(CrawlerMobs.number("rhino", 3, "charge_from", 0.0)
			> CrawlerMobs.number("rhino", 1, "charge_from", 0.0),
		"higher rhino levels start the charge farther out")
	_expect(CrawlerProgress.kill_xp(3) > CrawlerProgress.kill_xp(1),
		"higher-level enemies pay more XP")
	_expect(CrawlerMobs.kill_xp("ranger", 4) > CrawlerMobs.kill_xp("ranger", 1)
			and CrawlerMobs.kill_xp("rhino", 3) > CrawlerMobs.kill_xp("rhino", 1),
		"CSV ranks pay more XP on harder tiles")
	_expect(CrawlerRules.field_mob_level(Vector3.UP, Vector3.UP) == 1,
		"the start tile fields level-1 mobs")
	_expect(CrawlerRules.field_mob_level(Vector3.UP, Vector3.RIGHT)
			> CrawlerRules.field_mob_level(Vector3.UP, Vector3.UP),
		"farther tiles field higher-level mobs")
	_expect("rhino" in CrawlerRules.WILD_KINDS, "rhinos join the field pack")
	_expect(not CrawlerRules.WILD_KINDS.has("rift_hulk"),
		"the box hulk is not in the field pack")
	_expect(not CrawlerRules.safe_patch("Quiet Inlet 4"),
		"the city tile still fields mobs outside the ring")
	_expect(not CrawlerRules.safe_patch("Tide Margin 4"),
		"the start tile still fields mobs")
	_expect(CrawlerRules.patch_recipe(CrawlerRules.START_PATCH)["kinds"]
			== CrawlerRules.START_NEAR_KINDS,
		"the start pad fields rangers and rhinos")
	_expect(CrawlerRules.patch_recipe(
				CrawlerRules.START_PATCH, CrawlerRules.START_NEAR_RANGE + 1.0)
			["kinds"] == CrawlerRules.START_FAR_KINDS,
		"eyeballs join a bit farther from the start pad")
	_expect(not CrawlerRules.START_NEAR_KINDS.has("rammer"),
		"eyeballs stay out of the opening pad")
	_expect(CrawlerRules.START_FAR_KINDS.has("rammer")
			and CrawlerRules.START_FAR_KINDS.has("rhino"),
		"farther start-tile packs add eyeballs beside the monsters")
	_expect(CrawlerRules.kind_cap("ranger", 1) >= 8
			and CrawlerRules.kind_cap("rhino", 1) >= 8
			and CrawlerRules.kind_cap("rammer", 1) >= 8,
		"the first patch allows a dense calm crowd of each kind")
	_expect(CrawlerRules.kind_cap("ranger", 3)
			> CrawlerRules.kind_cap("ranger", 1),
		"harder patches raise each kind cap")
	_expect(CrawlerRules.pack_limit(CrawlerRules.START_NEAR_KINDS, 1) >= 20,
		"the opening pad holds a crowd of bells and rhinos")
	_expect(CrawlerRules.flies("ranger") and CrawlerRules.flies("rammer")
			and not CrawlerRules.flies("rhino"),
		"bells and eyeballs fly")
	_expect(CrawlerRules.flyer_ceiling(3) > CrawlerRules.flyer_ceiling(1),
		"harder patches let flyers cruise higher")
	_expect(CrawlerRules.ranger_engage_max(1) >= 48.0,
		"level 1 rangers shoot from farther out")
	_expect(CrawlerRules.ranger_engage_max(3)
			> CrawlerRules.ranger_engage_max(1),
		"harder rangers engage farther out")
	_expect(CrawlerRules.RANGER_CROWN_CLEAR >= 18.0,
		"rangers keep a wide hole over the player's head")
	_expect(CrawlerMobs.number("ranger", 1, "agro_range", 0.0) >= 50.0,
		"rangers agro from farther out")
	_expect(CrawlerRules.ranger_chase_speed(80.0, 1, false)
			< CrawlerRules.ranger_chase_speed(80.0, 3, false),
		"level 1 rangers match speed more slowly")
	_expect(CrawlerRules.rhino_chase_speed(40.0, 1) > 30.0,
		"rhinos pick up a running player's speed")
	_expect(CrawlerRules.RHINO_RUN_SPEED == 8.0
			and CrawlerRules.rhino_running(36.0)
			and not CrawlerRules.rhino_running(2.0),
		"rhinos treat a walk as slow and a sprint as a run")
	_expect(CrawlerRules.RHINO_BACKUP == 7.5,
		"rhinos back off before a close meteor")
	_expect(CrawlerRules.RHINO_LEAD == 14.0,
		"rhinos take the lead before cutting a runner")
	_expect(CrawlerRules.rammer_top_speed(0.0, 1) < 32.0,
		"rammers wind up instead of arriving at full sprint")
	_expect(CrawlerRules.rammer_spawn_range(80.0)
			> CrawlerRules.rammer_spawn_range(0.0),
		"faster looks spawn the ram farther out")
	var ram_home := CrawlerRules.rammer_launch_point(
		Vector3.ZERO, Vector3(0.0, 0.0, 1.0), Vector3.UP, 0.0)
	_expect(ram_home.z >= CrawlerRules.SPAWN_MIN * 0.9 and ram_home.y > 1.0,
		"eyeballs appear far ahead of travel")
	_expect(CrawlerRules.ground_intercept(
			Vector3.ZERO, Vector3(12.0, 0.0, 0.0), Vector3(0.0, 0.0, 24.0),
			16.0, Vector3.UP).z > 4.0,
		"a crossing run is led ahead of the player")
	_expect(CrawlerRules.ranger_match_lag(1) < CrawlerRules.ranger_match_lag(3)
			and CrawlerRules.ranger_match_lock(1)
			< CrawlerRules.ranger_match_lock(3),
		"level 1 rangers take longer to lock a player's speed")
	_expect(CrawlerRules.ranger_shot_speed(0.0, 1)
			< CrawlerRules.ranger_shot_speed(0.0, 3),
		"level 1 ranger shots are slower")
	_expect(CrawlerRules.ranger_shot_speed(0.0, 1) >= 22.0
			and CrawlerRules.ranger_shot_speed(0.0, 1) <= 28.0,
		"level 1 ranger orbs are a bit faster")
	_expect(CrawlerRules.ranger_shot_speed(80.0, 1)
			<= CrawlerRules.ranger_shot_speed(0.0, 1) + 0.01,
		"ranger orbs do not match a sprint")
	_expect(CrawlerRules.ranger_shot_ball(1) >= 0.55
			and CrawlerRules.ranger_shot_hit(1) >= 1.3,
		"ranger pills are large")
	_expect(CrawlerRules.ranger_shot_ball(1) > CrawlerRules.ranger_shot_ball(3),
		"level 1 ranger shots are the bigger pills")
	_expect(CrawlerRules.ranger_shot_aoe(1) > CrawlerRules.ranger_shot_hit(1),
		"ranger orbs splash past the ball")
	var gold_pop := DamageNumberEvent.new()
	gold_pop.amount = 14.0
	gold_pop.kind = DamageNumberEvent.Kind.GOLD
	var xp_pop := DamageNumberEvent.new()
	xp_pop.amount = 24.0
	xp_pop.kind = DamageNumberEvent.Kind.XP
	_expect(gold_pop.caption() == "$14", "kill gold reads as a dollar amount")
	_expect(xp_pop.caption() == "+24", "kill XP reads as a plus amount")
	_expect(CrawlerRules.RANGER_AIM_SECONDS >= 1.0,
		"rangers pause a second to aim")
	_expect(float(CrawlerRules.patch_recipe(CrawlerRules.START_PATCH)
			.get("health_scale", 1.0)) <= CrawlerRules.START_HEALTH_SCALE,
		"start-tile mobs are very frail")
	_expect(CrawlerRules.patch_recipe("Salt Prairie")["kinds"]
			== CrawlerRules.WILD_KINDS,
		"later tiles keep the field pack")
	_expect(CrawlerRules.KILL_COOLDOWN >= 3.0
			and CrawlerRules.KILL_REFILL >= 2.5,
		"kills leave a few seconds before the pad and pack refill")
	_expect(CrawlerRules.spawn_player_clear(80.0)
			> CrawlerRules.spawn_player_clear(0.0),
		"faster players need more spawn room")
	_expect(CrawlerRules.spawn_ahead_range(80.0).x
			> CrawlerRules.spawn_ahead_range(0.0).x,
		"faster travel seeds the pack farther out")
	_expect(CrawlerRules.spawn_ahead_range(0.0).x > CrawlerRules.AGRO_RANGE,
		"the ahead band starts outside agro")
	_expect(CrawlerRules.spawn_travel(Vector3(80.0, 0.0, 0.0), Vector3.FORWARD)
			.dot(Vector3.RIGHT) > 0.9,
		"travel follows velocity when the player is moving")
	_expect(CrawlerRules.spawn_travel(Vector3.ZERO, Vector3.FORWARD)
			.dot(Vector3.FORWARD) > 0.9,
		"a still player seeds along look")
	_expect(CrawlerRules.spawn_going(Vector3.ZERO).length_squared() < 0.0001,
		"a still player has no travel heading")
	_expect(CrawlerRules.spawn_going(Vector3(40.0, 0.0, 0.0)).dot(Vector3.RIGHT) > 0.9,
		"the extra pack follows where the player is going")
	_expect(not CrawlerRules.uses_lead_pack(0.0)
			and not CrawlerRules.uses_lead_pack(8.0),
		"a slow player only keeps the ring")
	_expect(CrawlerRules.uses_lead_pack(40.0),
		"a fast player seeds an extra pack ahead")
	_expect(CrawlerRules.spawn_lead_count(0.0) == 0
			and CrawlerRules.spawn_lead_count(80.0)
				> CrawlerRules.spawn_lead_count(20.0),
		"faster travel asks for a thicker ahead pack")
	_expect(CrawlerRules.spawn_lead_range(80.0).x
			> CrawlerRules.spawn_ring_range().y,
		"the extra pack sits farther out than the ring")
	var ring_a := CrawlerRules.spawn_ring_point(
		Vector3.ZERO, Vector3.UP, 0.0, 100.0)
	var ring_b := CrawlerRules.spawn_ring_point(
		Vector3.ZERO, Vector3.UP, PI, 100.0)
	_expect(ring_a.distance_to(ring_b) > 150.0,
		"ring homes sit on opposite sides of the player")
	_expect(not CrawlerRules.spawn_too_close(
			Vector3(100.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO, Vector3.UP),
		"a ring home outside the clear pad is kept")
	_expect(CrawlerRules.spawn_blocked_by_player(
			Vector3.ZERO, Vector3.ZERO, Vector3.ZERO),
		"a spawn on the player is rejected")
	_expect(CrawlerRules.spawn_blocked_by_player(
			Vector3(0.0, 10.0, 0.0), Vector3.ZERO, Vector3.ZERO),
		"a spawn stacked over the player is rejected")
	_expect(CrawlerRules.spawn_blocked_by_player(
			Vector3(40.0, 0.0, 0.0), Vector3.ZERO, Vector3.ZERO,
			Vector3.UP, Vector3.FORWARD),
		"a close side spawn is rejected")
	_expect(CrawlerRules.spawn_blocked_by_player(
			Vector3(30.0, 0.0, 0.0), Vector3.ZERO, Vector3(80.0, 0.0, 0.0)),
		"a close spawn on a fast player's path is rejected")
	_expect(CrawlerRules.spawn_blocked_by_player(
			Vector3(0.0, 0.0, 200.0), Vector3.ZERO, Vector3(80.0, 0.0, 0.0)),
		"a spawn beside a fast player is rejected")
	_expect(not CrawlerRules.spawn_blocked_by_player(
			Vector3(200.0, 0.0, 0.0), Vector3.ZERO, Vector3(80.0, 0.0, 0.0)),
		"a far spawn ahead of travel is kept")
	_expect(CrawlerRules.spawn_blocked_by_kill(Vector3(8.0, 0.0, 0.0),
			Vector3.ZERO, 0.4),
		"a fresh kill keeps that pad empty")
	_expect(not CrawlerRules.spawn_blocked_by_kill(Vector3(8.0, 0.0, 0.0),
			Vector3.ZERO, CrawlerRules.KILL_COOLDOWN + 0.1),
		"the kill pad opens again after the delay")
	_expect(not CrawlerRules.spawn_is_agro(0) and not CrawlerRules.spawn_is_agro(1),
		"field packs spawn calm and agro on approach")
	_expect(CrawlerRules.should_agro(8.0),
		"standing next to a mob agros it")
	_expect(not CrawlerRules.should_agro(CrawlerRules.AGRO_RANGE + 1.0),
		"agro has a finite range")
	_expect(CrawlerRules.AGRO_RANGE < CrawlerRules.DEAGRO_RANGE,
		"agro is tighter than deagro")
	_expect(CrawlerRules.should_deagro(CrawlerRules.DEAGRO_RANGE + 1.0),
		"agro drops after the player pulls away")
	_expect(CrawlerRules.should_despawn_idle(true, false, CrawlerRules.IDLE_DESPAWN),
		"deagroed mobs despawn after they idle")
	_expect(not CrawlerRules.should_despawn_idle(false, false, 30.0),
		"mobs that never chased keep wandering")
	_expect(CrawlerRules.WILD_STREAM_OUT > CrawlerRules.WILD_STREAM_IN,
		"mobs sleep farther out than they stream in")
	_expect(CrawlerRules.PERCEPTION >= 80.0, "enemies have a perception range")
	var near := Vector3.UP
	var far := Vector3.DOWN
	_expect(CrawlerRules.patch_level(near, far) > CrawlerRules.patch_level(near, near),
		"far patches are higher level")
	_expect(CrawlerRules.patch_mob_count(near, far)
		> CrawlerRules.patch_mob_count(near, near),
		"harder patches raise the pack cap")
	var kinds := {}
	for slot in CrawlerRules.WILD_KINDS.size():
		kinds[CrawlerRules.wild_kind("Salt Prairie", slot)] = true
	_expect(kinds.has("ranger") and kinds.has("rammer") and kinds.has("rhino"),
		"the field pack cycles ranger, rammer, and rhino")
	_expect(not kinds.has("rift_hulk"), "the box hulk does not cycle in")
	_expect(CrawlerRules.wild_kind(CrawlerRules.START_PATCH, 0) == "ranger"
			and CrawlerRules.wild_kind(CrawlerRules.START_PATCH, 1) == "rhino",
		"the start pad rolls rangers and rhinos")
	_expect(CrawlerRules.wild_kind(
			CrawlerRules.START_PATCH, 2, CrawlerRules.START_NEAR_RANGE + 8.0)
			== "rammer",
		"eyeballs roll once the player leaves the pad")
	_expect(CrawlerRanger.HEIGHT >= 12.0, "rangers are much larger")
	_expect(CrawlerRanger.HIT_PAD > 0.5, "ranger hitboxes extend past the mesh")
	var horde := CrawlerHorde.new()
	add_child(horde)
	var spawned := horde.spawn_test_mob("rhino", Vector3(0.0, 8.0, 0.0), true)
	_expect(spawned != null and spawned.wild_kind() == "rhino",
		"the horde can spawn a rhino")
	_expect(not spawned.flies(), "rhinos stay on the ground")
	_expect(horde.wild_live_count() == 1, "a test spawn is live")
	var flyer := horde.spawn_test_mob("ranger", Vector3(0.0, 24.0, 0.0), false, 1)
	_expect(flyer != null and flyer.flies(), "rangers fly")
	_expect(flyer.flyer_floor() > 8.0, "rangers keep the bell above the dirt")
	_expect(flyer.flyer_floor() < flyer.flyer_ceiling(),
		"the first-patch ceiling still fits a ranger")
	_expect(flyer.flyer_ceiling() == CrawlerRules.flyer_ceiling(1),
		"first-patch flyers keep a low ceiling")
	horde._note_kill(Vector3(4.0, 8.0, 0.0))
	_expect(horde._kill_blocks(Vector3(10.0, 8.0, 0.0)),
		"the horde keeps the kill pad empty")
	_expect(not horde._kill_blocks(Vector3(80.0, 8.0, 0.0)),
		"a kill does not lock the far field")
	flyer.set_threat_level(4)
	_expect(flyer.flyer_ceiling() > CrawlerRules.flyer_ceiling(1),
		"harder flyers are allowed higher")
	horde.queue_free()
	var world := _StartPadWorld.new()
	var at := world._respawn_transform(1, Vector3(80.0, 12.0, 4.0))
	_expect(at.origin.is_equal_approx(Vector3(10.0, 20.0, 30.0)),
		"crawler respawn returns to the start pad")
	world.free()


func _check_city_tracker() -> void:
	var city := PatchCity.new()
	city.name = "SiegeCity"
	add_child(city)
	var lots: Array = []
	for _i in 5:
		var lot := DummyLot.new()
		city.add_child(lot)
		city.destructible_buildings().append(lot)
		lots.append(lot)
	_expect(city.building_count() == 5, "city counts live lots")
	_expect(not city.is_destroyed(), "intact city is not destroyed")
	var heard := [false]
	city.siege_destroyed.connect(func() -> void: heard[0] = true)
	for index in 3:
		lots[index].wrecked = true
	city.refresh_siege_state()
	_expect(not city.is_destroyed() and not heard[0],
		"60% wrecked is not yet destroyed")
	lots[3].wrecked = true
	city.refresh_siege_state()
	_expect(city.is_destroyed() and heard[0],
		"crossing 60% marks the city destroyed once")
	heard[0] = false
	lots[4].wrecked = true
	city.refresh_siege_state()
	_expect(city.is_destroyed() and not heard[0],
		"already destroyed cities do not emit again")
	city.queue_free()


func _check_safe_box() -> void:
	var box := CrawlerSafeBox.new()
	box.configure(7, Transform3D.IDENTITY)
	add_child(box)
	await get_tree().process_frame
	_expect(box.contains_point(Vector3.ZERO), "safe box interior contains its centre")
	_expect(box.blocks_point(Vector3.ZERO), "mobs are blocked from the interior")
	_expect(not box.contains_point(Vector3(40.0, 0.0, 0.0)),
		"safe box does not cover the open field")
	_player.global_position = Vector3.ZERO
	_expect(_player.in_crawler_safe_zone(), "player standing in the box is safe")
	_expect(not _player.can_attack(), "abilities are blocked inside the box")
	_player.global_position = Vector3(80.0, 0.0, 0.0)
	_expect(not _player.in_crawler_safe_zone(), "leaving the volume ends the shelter")
	_expect(_player.can_attack(), "abilities return outside the box")
	var left := [false]
	box.player_departed.connect(func() -> void: left[0] = true)
	box._on_body_entered(_player)
	box._on_body_exited(_player)
	_expect(left[0], "walking out of a used box fires player_departed")
	box.queue_free()
	await get_tree().process_frame


func _check_city_ring() -> void:
	var ring = CITY_RING.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	await get_tree().process_frame
	_expect(ring.contains_point(Vector3.ZERO), "the ring interior is the city")
	_expect(ring.blocks_near(Vector3(CrawlerRules.CITY_RING_RADIUS + 10.0, 2.0, 0.0)),
		"mobs stay off the rim and the pad around it")
	_expect(not ring.blocks_near(Vector3(300.0, 2.0, 0.0)),
		"the rest of the patch can still spawn")
	_expect(not _ring_has_blocking_collision(ring),
		"city walls have no collision")
	_expect(_ring_walls_are_clear(ring),
		"city walls are 60 percent transparent")
	var city_mark := ring.get_node_or_null("CrawlerWaypoint") as CrawlerSite
	_expect(city_mark != null and city_mark.title == CrawlerRules.CITY_SITE_TITLE,
		"the first city is named Neon Fjord")
	_expect(city_mark != null and city_mark.waypoint
			and city_mark.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"tilde names Neon Fjord from the start")
	_expect(ResourceLoader.exists(CrawlerCityRing.VILLAGE_MODEL),
		"Neon Fjord village is ready to seat on the ring")
	_player.global_position = Vector3(300.0, 0.0, 0.0)
	_press_interact(_player)
	await get_tree().process_frame
	_expect(_player.hud.get_node_or_null("CrawlerFieldMenu") == null,
		"E does not open a menu outside the city")
	_player.global_position = Vector3.ZERO
	_expect(_player.in_crawler_city(), "standing in the ring is being in the city")
	_expect(_player.can_attack(), "the ring does not lock abilities")
	_press_interact(_player)
	await get_tree().process_frame
	var store := _player.hud.get_node_or_null("CrawlerFieldMenu")
	_expect(store != null, "E opens the city store inside the ring")
	if store != null:
		store.queue_free()
	if _player._menu_open:
		_player.close_menu()
	_player.global_position = Vector3(300.0, 0.0, 0.0)
	_expect(not _player.in_crawler_city(), "leaving the ring leaves the city")
	var ranger := CrawlerRanger.new()
	ranger.configure("ring_chase", Transform3D(Basis(), Vector3(40.0, 8.0, 0.0)), 1, true)
	add_child(ranger)
	ranger.set_physics_process(false)
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	ranger.chase = true
	ranger.tick_agro(_player, 0.16)
	_expect(not ranger.chase, "agroed mobs will not follow into the ring")
	var pushed := ring.push_out(Vector3(8.0, 2.0, 0.0), 1.0)
	_expect(Vector2(pushed.x, pushed.z).length() >= ring.keepout_radius(),
		"mobs that touch the ring are pushed out")
	ranger.queue_free()
	ring.queue_free()
	await get_tree().process_frame


func _check_starfire_city_gift() -> void:
	_expect(CrawlerRules.ability_enabled("starfire"),
		"starfire is a crawler ability you can pick up")
	var definition := ItemDB.ability_definition("starfire")
	_expect(definition != null
			and String(definition.animation) == "Fighting_Right_Jab"
			and String(definition.alternate_animation) == "Fighting_Left_Jab"
			and String(definition.hover_animation) == "Fighting_Right_Jab"
			and String(definition.alternate_hover_animation) == "Fighting_Left_Jab",
		"starfire throws with the fight jabs")
	var ring = CITY_RING.new()
	ring.configure(-1, Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)))
	add_child(ring)
	var stand := ring.gift_stand_transform()
	_expect(stand.origin.distance_to(ring.world_centre()) < 1.5
			and stand.origin.y > ring.world_centre().y,
		"the gift stands in the middle of the first city")
	var card := CrawlerCatalog.make_ability("starfire")
	_expect(card != null and card.id == "starfire", "the plaza gift is starfire")
	if card != null:
		var dropped := DroppedCrawlerCard.new()
		dropped.configure(9, card.to_dict())
		add_child(dropped)
		dropped.global_transform = stand
		_expect(dropped.catalog_id() == "starfire"
				and dropped.interact_prompt().contains("Starfire"),
			"the plaza waits with a starfire tile")
		dropped.queue_free()
	ring.queue_free()


func _check_heal_and_flash() -> void:
	var before := _player.health()
	_player.stats.set_health(before * 0.4)
	var gained := _player.apply_heal(12.0)
	_expect(gained > 0.0 and _player.health() > before * 0.4,
		"host heal restores health")
	var feedback := _player.combat_feedback()
	_expect(feedback != null, "local player has combat feedback")
	if feedback != null:
		feedback.damage_taken(16.0, _player.combat_position(), 0)
		_expect(feedback.flash_amount() > 0.3, "damage flashes the screen red")


func _check_horde_roster() -> void:
	var horde := CrawlerHorde.new()
	add_child(horde)
	_expect(horde.wild_live_count() == 0, "the pack starts empty")
	var ranger := horde.spawn_test_mob("ranger", Vector3(0.0, 12.0, 0.0), true)
	_expect(horde.wild_live_count() == 1, "spawning around the player adds a live mob")
	var base_hp := ranger.maximum_health()
	var base_dmg := ranger.damage()
	ranger.set_threat_level(3)
	_expect(ranger.maximum_health() > base_hp - 0.001,
		"level can restat a living ranger")
	_expect(ranger.damage() > base_dmg, "higher levels raise ranger damage")
	ranger.set_threat_level(1)
	var kept_hp := ranger.maximum_health()
	var kept_level := ranger.threat_level
	horde.raise_threat()
	horde.raise_threat()
	_expect(ranger.threat_level == kept_level
			and is_equal_approx(ranger.maximum_health(), kept_hp),
		"siege clears do not restat mobs already on a patch")
	_expect(horde._level_for(-1, null) == 1,
		"a pack's level comes from the tile, not the player")
	var hulk: CrawlerMob = load("res://game/crawler/crawler_rift_hulk.gd").new()
	_expect(hulk != null, "rift-hulk exists")
	hulk.free()
	var rhino: CrawlerMob = load("res://game/crawler/crawler_rhino.gd").new()
	_expect(rhino != null, "rhino exists")
	rhino.free()
	_player.global_position = Vector3(0.0, 12.0, 0.0)
	horde._note_kill(_player.global_position)
	_expect(horde._refill_blocked(_player),
		"a nearby kill delays the next spawn-in")
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	horde.queue_free()


func _check_idle_roam() -> void:
	var ram := CrawlerRammer.new()
	ram.configure("soar", Transform3D(Basis(), Vector3(80.0, 8.0, 0.0)), 1, false)
	add_child(ram)
	ram.set_physics_process(false)
	await get_tree().process_frame
	_expect(not ram.chase and ram.flyer_floor() >= 16.0,
		"deagroed eyes stay up with the birds")
	_expect(ram.flyer_ceiling() >= 30.0,
		"deagroed eyes have room to circle high")
	var rise := (ram.soar_point() - ram.hang_origin).dot(ram._up())
	_expect(rise >= 16.0, "the eye circle sits well above the perch")
	ram._tick_ai(0.2)
	_expect(ram.velocity.length() > 1.0, "deagroed eyes keep circling")
	ram.queue_free()

	var ranger := CrawlerRanger.new()
	ranger.configure("roam", Transform3D(Basis(), Vector3(90.0, 20.0, 0.0)), 1, false)
	add_child(ranger)
	ranger.set_physics_process(false)
	await get_tree().process_frame
	ranger._patrol_left = 0.0
	ranger._patrol(0.05, 0.58)
	var first := ranger._patrol_goal
	ranger._patrol_left = 0.0
	ranger._patrol(0.05, 0.58)
	_expect(first.distance_to(ranger._patrol_goal) > 4.0,
		"rangers pick a new roam point")
	ranger.queue_free()

	var rhino := CrawlerRhino.new()
	rhino.configure("graze", Transform3D(Basis(), Vector3(100.0, 1.2, 0.0)), 1, false)
	add_child(rhino)
	rhino.set_physics_process(false)
	await get_tree().process_frame
	rhino._patrol_left = 0.0
	rhino._patrol_ground(0.05)
	first = rhino._patrol_goal
	rhino._patrol_left = 0.0
	rhino._patrol_ground(0.05)
	_expect(first.distance_to(rhino._patrol_goal) > 4.0,
		"rhinos pick a new roam point")
	rhino.queue_free()


func _check_enemy_presence() -> void:
	var ranger := CrawlerRanger.new()
	ranger.configure("rim", Transform3D(Basis(), Vector3(0.0, 12.0, 0.0)), 0, false)
	add_child(ranger)
	ranger.set_physics_process(false)
	await get_tree().process_frame
	_expect(ranger.find_child("Creature", true, false) != null,
		"ranger uses the knell-bell model")
	_expect(ranger.find_child("CrawlerThreatDot", true, false) == null,
		"enemies do not carry a red head marker")
	var visual: MeshInstance3D
	for node_variant: Variant in ranger.find_children("*", "MeshInstance3D", true, false):
		visual = node_variant as MeshInstance3D
		if visual != null:
			break
	var material := visual.material_override as ShaderMaterial if visual != null else null
	_expect(material != null and material.shader != null,
		"enemies use the red rim shader")
	var animator := ranger.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_expect(animator != null, "ranger is a rigged creature")
	_expect(animator != null and (
			animator.has_animation("Attack")
			or _has_named_clip(animator, "Attack")),
		"ranger has an attack clip")
	_expect(ranger.find_child("Creature", true, false) != null,
		"ranger uses the knell-bell body")
	var frail := CrawlerRanger.new()
	frail.configure(
		"frail", Transform3D.IDENTITY, 1, false, null, -1, -1,
		CrawlerRules.START_HEALTH_SCALE)
	add_child(frail)
	frail.set_physics_process(false)
	await get_tree().process_frame
	_expect(frail.maximum_health() < 20.0,
		"start-tile rangers die in a couple of pulses")
	_expect(frail.maximum_health() < ranger.maximum_health() * 0.25,
		"start-tile health is a fraction of later rangers")
	frail.queue_free()
	var rammer := CrawlerRammer.new()
	rammer.configure("ram", Transform3D.IDENTITY, 0, false)
	add_child(rammer)
	rammer.set_physics_process(false)
	rammer.global_position = _player.global_position + Vector3(80.0, 0.0, 0.0)
	await get_tree().process_frame
	var rammer_anim := rammer.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_expect(rammer_anim != null, "rammer is a rigged creature")
	_expect(rammer_anim != null and (
			rammer_anim.has_animation("Attack")
			or _has_named_clip(rammer_anim, "Attack")),
		"rammer has an attack clip")
	_expect(rammer.find_child("Creature", true, false) != null,
		"rammer uses the winged oculus")
	rammer.chase = true
	rammer.ever_chased = true
	_expect(rammer.flyer_floor() >= 2.0,
		"an agroed eye is allowed down into the view band")
	_player.global_position = Vector3(2.0, 0.0, 40.0)
	_face_along(_player, Vector3.RIGHT)
	var station := rammer.show_station(_player)
	_expect(station.x > _player.global_position.x + 10.0
			and station.y < _player.camera.global_position.y,
		"the show perch sits in front of the camera and a bit below the lens")
	rammer._cruise = 0.0
	rammer.velocity = Vector3.ZERO
	rammer.global_position = Vector3(-16.0, 0.0, 48.0)
	_expect(not rammer.in_camera(_player),
		"an eye behind the look is off camera")
	rammer._tick_ai(0.16)
	_expect(rammer.staging() and not rammer.ramming(),
		"off-camera eyes stage in front before they ram")
	_expect(rammer._cruise > 0.4 and rammer._cruise < 6.0,
		"a fresh ram winds up from a stop")
	var hook := rammer.stage_goal(_player) - rammer.global_position
	_expect(rammer.velocity.x > 0.2 and hook.x > 0.0,
		"a rear approach swings forward into the look instead of diving at the back")
	rammer.global_position = Vector3(12.0, 0.0, 72.0)
	_expect(not rammer.in_camera(_player),
		"an eye high over the look is off camera")
	rammer.velocity = Vector3.ZERO
	rammer._tick_ai(0.16)
	_expect(rammer.staging(),
		"an overhead eye drops into the view before it commits")
	_expect(-rammer.velocity.dot(rammer._up()) <= CrawlerRammer.DESCENT_CAP + 0.05,
		"a high eye glides down instead of slamming to eye level")
	rammer.global_position = rammer.show_station(_player)
	rammer.velocity = Vector3.ZERO
	rammer._tick_ai(0.16)
	_expect(rammer.ramming() and rammer.in_camera(_player),
		"once the eye is low in front of the camera it commits the ram")
	_expect(rammer.velocity.x < 0.0,
		"the ram comes in along the look toward the player")
	rammer.global_position = _player.global_position + Vector3(0.0, 2.4, 0.0)
	var crown := rammer.global_position - _player.combat_position()
	_expect(rammer._blast_reaches(_player, crown, crown.length()),
		"a ram over the head still detonates")
	rammer.queue_free()
	_player.global_transform = Transform3D.IDENTITY
	_player.velocity = Vector3.ZERO
	ranger.chase = true
	ranger.ever_chased = true
	ranger.global_position = _player.global_position + Vector3(0.0, 400.0, 0.0)
	ranger._tick_ai(0.16)
	_expect(not ranger.chase, "agroed enemies deagro after they lose the player")
	_expect(ranger.idle_seconds > 0.0, "deagro starts the idle despawn clock")
	ranger.chase = true
	ranger.idle_seconds = 0.0
	ranger.global_position = _player.global_position + Vector3(0.0, 18.0, 0.0)
	ranger._tick_ai(0.16)
	_expect(ranger.chase, "agroed enemies keep chasing nearby")
	var calm := CrawlerRanger.new()
	calm.configure("calm", Transform3D.IDENTITY, 0, false)
	add_child(calm)
	calm.set_physics_process(false)
	var agro := CrawlerMobs.number(
		"ranger", 1, "agro_range", CrawlerRules.AGRO_RANGE)
	calm.global_position = _player.global_position + Vector3(0.0, agro + 20.0, 0.0)
	calm._tick_ai(0.16)
	_expect(not calm.chase, "mobs past agro range stay calm")
	calm.queue_free()
	_expect(ranger.hit_radius() > CrawlerRanger.RADIUS,
		"ranger hitbox is larger than the mesh")
	_expect(ranger.hit_box() > CrawlerRanger.HEIGHT,
		"the ranger box is larger than the bell")
	var high := ranger.global_position + Vector3(0.0, 6.0, 0.0)
	var beam := DamageHit.beam(
		high + Vector3(0.0, 0.0, 10.0),
		high + Vector3(0.0, 0.0, -10.0),
		0.35, 12.0)
	beam.faction = DamageHit.Faction.PLAYER
	_expect(beam.affects_combatant(ranger),
		"a laser across the upper bell hits the ranger box")
	var dealt := ranger.apply_damage(beam)
	_expect(dealt > 0.0, "laser damage lands on the ranger")
	_expect(ranger._flash_left > 0.1, "a hit flashes the ranger red")
	ranger._abort_aim()
	_player.velocity = Vector3(40.0, 0.0, 0.0)
	ranger._cruise = 40.0
	ranger._tick_ai(0.16)
	_expect(ranger.velocity.x > 24.0, "matched rangers ride the player's frame")
	_player.velocity = Vector3.ZERO
	var other := CrawlerRanger.new()
	other.configure("spread2", Transform3D.IDENTITY, 0, false)
	_expect(ranger._orbit_bias().distance_to(other._orbit_bias()) > 0.15,
		"rangers pick different hold points")
	other.free()
	var hold_at := ranger._hover_hold(_player.global_position, 16.0)
	var flat := hold_at - _player.global_position
	if ranger.has_method(&"_up"):
		var up: Vector3 = ranger._up()
		flat -= up * flat.dot(up)
	_expect(flat.length() >= CrawlerRules.RANGER_CROWN_CLEAR - 0.05,
		"ranger hover stays off the player's head")
	ranger.velocity = Vector3.ZERO
	ranger.global_position = _player.global_position + ranger._up() * 10.0
	ranger._keep_off_crown(_player)
	var shove := ranger.velocity
	shove -= ranger._up() * shove.dot(ranger._up())
	_expect(shove.length() > 4.0,
		"a ranger over the head is shoved off the crown")
	_expect(ranger.velocity.dot(ranger._up()) >= -0.2,
		"the crown shove does not dive onto the player")
	var orb := CrawlerRangerShot.new()
	add_child(orb)
	await get_tree().process_frame
	var glow := orb._core.material_override as StandardMaterial3D
	_expect(glow != null and glow.emission.b > 0.55 and glow.emission.r > 0.4
			and glow.emission.g < 0.4,
		"ranger shots are glowing purple orbs")
	_expect(orb._halo != null, "the orb keeps a glowing halo")
	orb.queue_free()
	ranger._abort_aim()
	ranger._fire_left = 0.0
	ranger._try_fire(_player, 28.0, 0.016)
	_expect(ranger._aiming() and ranger._aim_left > 0.9,
		"rangers pause to aim before they fire")
	_expect(ranger._pending_shot, "the shot waits on the aim")
	ranger._try_fire(_player, 20.0, 0.75)
	_expect(ranger._aiming() and ranger._pending_shot,
		"the aim is still going after most of a second")
	ranger._update_flash()
	var warn := _ranger_albedo(ranger)
	_expect(warn.r > warn.b, "rangers turn red while they aim")
	ranger._abort_aim()
	ranger._flash_left = 0.0
	ranger._update_flash()
	var rest := _ranger_albedo(ranger)
	_expect(rest.b > rest.r, "rangers stay blue until they aim")
	var ghost := Node3D.new()
	add_child(ghost)
	var leftover := DamageHit.impact(Vector3.ZERO, 1.0, 1.0)
	ghost.free()
	leftover.set_source(ghost)
	_expect(leftover.source_path.is_empty(),
		"a shot still in the air does not crash after its ranger dies")
	ranger.queue_free()
	var hulk: CrawlerMob = load("res://game/crawler/crawler_rift_hulk.gd").new()
	hulk.configure("hulk", Transform3D.IDENTITY, 2, false)
	add_child(hulk)
	hulk.set_physics_process(false)
	hulk.global_position = _player.global_position + Vector3(80.0, 0.0, 0.0)
	await get_tree().process_frame
	_expect(hulk.combat_display_name() == "Rift-Hulk", "hulk reports its name")
	_expect(hulk.maximum_health() > 200.0, "hulks have a large health pool")
	hulk.queue_free()
	var rhino: CrawlerMob = load("res://game/crawler/crawler_rhino.gd").new()
	rhino.configure("rhino", Transform3D.IDENTITY, 1, true)
	add_child(rhino)
	rhino.set_physics_process(false)
	rhino.global_position = _player.global_position + Vector3(80.0, 0.0, 0.0)
	await get_tree().process_frame
	_expect(rhino.combat_display_name() == "Rhino", "rhino reports its name")
	_expect(rhino.find_child("Creature", true, false) != null,
		"rhino uses the cinder-plate rhino body")
	var anim := rhino.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_expect(anim != null, "rhino keeps its baked clips")
	_expect(not rhino._resolve_clip("Charge").is_empty(),
		"rhino has the charge clip")
	_expect(not rhino._resolve_clip("Paw").is_empty(),
		"rhino has the paw windup clip")
	_expect(not rhino._resolve_clip("Gore").is_empty(),
		"rhino has the gore clip")
	var charger := rhino as CrawlerRhino
	_expect(charger != null, "the field charger is a CrawlerRhino")
	if charger != null:
		charger.chase = false
		charger.ever_chased = false
		charger.global_position = _player.global_position + Vector3(0.0, 0.0, 6.0)
		charger.tick_agro(_player, 0.16)
		_expect(charger.chase, "a rhino agros a player standing next to it")
		charger._begin_paw(Vector3.FORWARD)
		_expect(charger.current_clip() == "Paw", "pawing plays the warning clip")
		_player.global_position = Vector3.ZERO
		_player.velocity = Vector3(36.0, 0.0, 0.0)
		charger.chase = true
		charger._cooldown_left = 9.0
		charger._flank_sign = 1
		charger._lagged_frame = Vector3.ZERO
		charger.global_position = Vector3(0.0, 0.0, 14.0)
		charger.velocity = Vector3.ZERO
		charger._cruise = 0.0
		charger._stalk(_player, 0.2)
		_expect(charger.velocity.x > 8.0 and charger.velocity.x < 36.0,
			"a stalking rhino lags a runner's speed")
		_expect(charger._lead_station(_player).x > 8.0,
			"a stalking rhino runs for a station ahead of the player")
		charger._begin_paw(Vector3.FORWARD)
		charger._update_paw(_player, 0.16)
		_expect(charger.velocity.x > 8.0,
			"pawing keeps matching the runner")
		_expect(charger._charge_heading.x > 0.5,
			"the paw snaps onto the runner's intercept")
		charger._begin_charge(_player)
		charger._update_charge(_player, 0.16)
		_expect(charger.velocity.x > 8.0,
			"the meteor carries through the intercept")
		_expect(charger._charge_heading.x > 0.5,
			"the meteor is lined up to where the runner will be")
		_expect(DamageHit.ABILITY_DISPLAY_NAMES.get("crawler_rhino_meteor", "")
				== "Meteor Strike",
			"the rhino's only attack is named meteor strike")
		charger._update_meteor_shock()
		var shock := charger.find_child("MeteorShock", true, false) as MeteorShock
		_expect(shock != null and shock.visible,
			"a charging rhino wears the red meteor shock")
		_expect(charger.slam_radius() > charger.ATTACK_RADIUS * 2.0,
			"the meteor slams a crater wider than a horn")
		_expect(not charger._should_slam(_player),
			"the meteor does not land while the rhino is still lining up")
		charger.global_position = _player.global_position + Vector3(0.0, 0.0, 2.4)
		_expect(charger._should_slam(_player),
			"the meteor lands when it reaches the player")
		charger._slam_meteor(_player)
		_expect(charger._slammed, "the meteor strike hits the ground")
		var boom := false
		for child in get_children():
			if child is EnergyExplosion:
				boom = true
				break
		_expect(boom, "the meteor throws a red ground blast")
		_player.velocity = Vector3(2.0, 0.0, 0.0)
		charger._cooldown_left = 9.0
		charger._lagged_frame = Vector3.ZERO
		charger.global_position = Vector3(0.0, 0.0, 14.0)
		charger.velocity = Vector3.ZERO
		charger._cruise = 0.0
		charger._stalk(_player, 0.2)
		_expect(charger._line_station(_player).x > 4.0,
			"a slow player is lined up from in front")
		_expect(charger.velocity.x > 1.0,
			"a lining-up rhino closes on the slow intercept")
		_player.global_position = Vector3.ZERO
		_player.velocity = Vector3(2.0, 0.0, 0.0)
		charger._cooldown_left = 0.0
		charger.global_position = Vector3(0.0, 0.0, 5.0)
		charger.velocity = Vector3.ZERO
		charger._cruise = 0.0
		charger._phase = CrawlerRhino.Phase.STALK
		charger._stalk(_player, 0.2)
		_expect(charger._too_close(_player),
			"five metres is inside the backup ring")
		_expect(charger._phase == CrawlerRhino.Phase.STALK,
			"a close rhino does not start a meteor")
		_expect(charger.velocity.dot(charger._backup_station(_player)
				- charger.global_position) > 0.0,
			"a close rhino backs up before striking")
		var gore := DamageHit.impact(charger.combat_position(), 2.0, 8.0)
		gore.faction = DamageHit.Faction.PLAYER
		_expect(charger.apply_damage(gore) > 0.0, "a rhino takes a hit")
		_expect(charger._flash_left > 0.1, "a hit flashes the rhino red")
		_player.velocity = Vector3.ZERO
		_player.global_position = Vector3.ZERO
	rhino.queue_free()


func _check_crawler_bursts() -> void:
	var ranger := CrawlerRanger.new()
	ranger.configure("pop", Transform3D(Basis(), Vector3(40.0, 8.0, 0.0)), 0, false)
	add_child(ranger)
	ranger.set_physics_process(false)
	await get_tree().process_frame
	var at := ranger.combat_position()
	var kill := DamageHit.impact(at, 8.0, 9999.0)
	kill.faction = DamageHit.Faction.PLAYER
	_expect(ranger.apply_damage(kill) > 0.0, "a lethal hit drops the ranger")
	var death := _burst_near(at)
	_expect(death != null, "a kill throws a particle burst")
	if death != null:
		_expect(death.puff_count() >= 5, "the death burst uses several colours")
		var hues := death.colors()
		_expect(hues.size() >= 5 and hues[0].r > hues[3].r
				and hues[4].b > hues[1].b,
			"the death burst mixes reds, greens and blues")
	var near := _BlastDummy.new()
	var mid := _BlastDummy.new()
	var far := _BlastDummy.new()
	add_child(near)
	add_child(mid)
	add_child(far)
	near.global_position = Vector3(180.0, 0.0, 0.0)
	mid.global_position = Vector3(182.0, 0.0, 0.0)
	far.global_position = Vector3(220.0, 0.0, 0.0)
	near.add_to_group(&"network_players")
	mid.add_to_group(&"network_players")
	far.add_to_group(&"network_players")
	var orb := CrawlerRangerShot.new()
	orb.damage = 14.0
	orb.hit_radius = CrawlerRules.ranger_shot_hit(1)
	add_child(orb)
	orb.set_physics_process(false)
	await get_tree().process_frame
	orb.global_position = near.global_position
	_expect(orb.blast_radius() > orb.hit_radius,
		"the orb blast is wider than the ball")
	orb.detonate()
	await get_tree().process_frame
	_expect(not is_instance_valid(orb), "the orb is spent after it lands")
	_expect(_explosion_near(near.global_position) != null,
		"a landing orb throws an explosion")
	_expect(_burst_near(near.global_position) != null,
		"a landing orb also sprays particles")
	_expect(near.taken > mid.taken and mid.taken > 0.0,
		"the orb splash hits the landing and a nearby body")
	_expect(far.taken == 0.0, "the orb splash does not reach far bodies")
	near.queue_free()
	mid.queue_free()
	far.queue_free()
	var feedback := _player.combat_feedback()
	_expect(feedback != null, "the local crawler can float loot numbers")
	if feedback != null:
		var gold := CrawlerProgress.kill_gold(1)
		var xp := CrawlerProgress.kill_xp(1, "ranger")
		feedback.loot_gained(gold, xp, Vector3(12.0, 8.0, 0.0))
		await get_tree().process_frame
		_expect(_loot_label("$%d" % gold, true) != null,
			"kills float a golden $ amount off the mob")
		_expect(_loot_label("+%d" % xp, false) != null,
			"kills float blue XP off the mob")


func _burst_near(at: Vector3) -> CrawlerBurst:
	for child in get_children():
		var burst := child as CrawlerBurst
		if burst != null and burst.global_position.distance_to(at) < 1.2:
			return burst
	return null


func _explosion_near(at: Vector3) -> EnergyExplosion:
	for child in get_children():
		var boom := child as EnergyExplosion
		if boom != null and boom.global_position.distance_to(at) < 1.2:
			return boom
	return null


func _loot_label(text: String, gold: bool) -> Label:
	var hud := _player.hud if _player != null else null
	var layer := hud.get_node_or_null("DamageNumbers") as Node if hud != null else null
	if layer == null:
		return null
	for child in layer.get_children():
		var label := child as Label
		if label == null or label.text != text:
			continue
		var colour := label.get_theme_color(&"font_color")
		if gold and colour.r > 0.85 and colour.g > 0.65 and colour.b < 0.45:
			return label
		if not gold and colour.b > 0.7 and colour.r < 0.5:
			return label
	return null


func _check_flight_and_parry() -> void:
	_expect(_player.fly_speed <= CrawlerRules.FLY_SPEED + 0.01,
		"crawler flight is slower than story flight")
	_expect(_player.walk_speed < 3.2, "crawler walk starts very slow")
	_expect(_player.fly_speed <= 90.0, "crawler flight starts very slow")
	_expect(CrawlerRules.FLIGHT_SECONDS <= 4.0, "crawler flight tank starts short")
	_expect(is_equal_approx(_player.flight_fuel_share(), 1.0),
		"player starts with a full flight bar")
	_expect(not _player.request_parry(), "F does nothing in crawler")
	_expect(not _player.parry_active(), "F does not raise a shield in crawler")
	_player._flight_fuel = 0.0
	_expect(not _player.can_fly(), "empty flight fuel blocks takeoff")
	var parked := _player.global_position
	_player.global_position = parked + Vector3(0.0, 400.0, 0.0)
	var carried := Vector3(0.0, 8.0, 70.0)
	_player._apply_stance(OnlinePlayer.Stance.FLY)
	_player._footed = false
	_player.velocity = carried
	_player._flight_velocity = carried
	_player._flight_fuel = 0.01
	_player._update_flight_state(0.016, false)
	_expect(_player.stance() == OnlinePlayer.Stance.STAND,
		"empty tank leaves flight")
	_expect(_player.velocity.length() > 60.0,
		"empty tank keeps flight momentum into the fall")
	_player._apply_stance(OnlinePlayer.Stance.FLY)
	_player._footed = false
	_player.velocity = carried
	_player._flight_velocity = carried
	_player._end_flight()
	_expect(_player.velocity.length() <= _player.sprint_speed + 0.1,
		"the land key still dumps flight speed")
	_player.global_position = parked
	_player.velocity = Vector3.ZERO
	_player._flight_fuel = 1.0
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	_expect(_player.can_fly(), "a full tank can take off")
	_player.global_position = Vector3(400.0, 0.0, 0.0)
	_expect(not _player.in_crawler_safe_zone(),
		"juke is checked outside the city")
	var along := _player._juke_wish_direction()
	_player._apply_stance(OnlinePlayer.Stance.FLY)
	_player._footed = false
	_player.velocity = along * 40.0
	_player._flight_velocity = _player.velocity
	_expect(_player.request_juke(), "crawler right-click can juke")
	_expect(_player.juke_active(), "crawler juke starts")
	_player._juke_move(0.016)
	var burst := OnlinePlayer.JUKE_DISTANCE / OnlinePlayer.JUKE_TIME
	_expect(_player.velocity.dot(along) > burst + 20.0,
		"a flight juke keeps forward speed and adds the burst")
	var juke_hp := _player.health()
	var juke_hit := DamageHit.impact(_player.combat_position(), 1.2, 18.0)
	juke_hit.faction = DamageHit.Faction.ENEMY
	_expect(is_zero_approx(_player.apply_damage(juke_hit)),
		"crawler juke is invulnerable")
	_expect(is_equal_approx(_player.health(), juke_hp),
		"crawler juke keeps the hit points")
	_player._tick_combat(OnlinePlayer.JUKE_TIME)
	_player._juke_cooldown_left = 0.0
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	_player.velocity = Vector3.ZERO
	_player._flight_velocity = Vector3.ZERO
	_player.global_position = parked


func _check_hud() -> void:
	var hud := _player.combat_hud()
	_expect(hud != null, "crawler player owns a combat HUD")
	if hud != null and hud.has_method(&"city_counter"):
		_expect(hud.call(&"city_counter") == null,
			"crawler HUD no longer shows a city counter")
	if hud != null and hud.has_method(&"city_siege_bar"):
		_expect(hud.call(&"city_siege_bar") == null,
			"crawler HUD no longer shows a siege bar")
	var parry: ParryIndicator = hud.parry_indicator() if hud != null else null
	_expect(parry != null, "crawler HUD keeps the blue vital bar")
	if parry != null:
		_player._flight_fuel = 0.37
		parry.refresh(_player)
		_expect(is_equal_approx(parry.shield_share(), 0.37),
			"blue bar shows remaining flight")
		var juke := parry.find_child("JukeBar", true, false) as ProgressBar
		var shield := parry.find_child("ShieldBar", true, false) as ProgressBar
		_expect(juke != null and shield != null
				and juke.get_index() < shield.get_index(),
			"orange juke cooldown sits above the blue flight bar")
		_player._juke_cooldown_left = 0.0
		parry.refresh(_player)
		_expect(is_equal_approx(parry.juke_share(), 1.0),
			"juke bar is full when the dash is ready")
		_player._juke_cooldown_left = _player.juke_cooldown() * 0.5
		parry.refresh(_player)
		_expect(absf(parry.juke_share() - 0.5) < 0.02,
			"juke bar empties through the dash cooldown")
		_player._juke_cooldown_left = 0.0
	var menu: Control = load("res://ui/menu/crawler_field_menu.gd").new()
	_expect(menu != null, "the city store script exists")
	menu.free()
	_expect(_player.crawler_vitals_text().contains("LV 1"),
		"HUD vitals start at level 1")
	_expect(_player.crawler_vitals_text().contains("G 0"),
		"HUD vitals start with no gold")
	_expect(hud.find_child("CrawlerVitalsPlate", true, false) != null,
		"crawler HUD shows the XP and gold plate")


func _check_progress() -> void:
	var progress := _player.crawler_progress
	_expect(progress != null, "crawler player has a run ledger")
	if progress == null:
		return
	if progress.leveled_up.is_connected(_player._on_crawler_leveled_up):
		progress.leveled_up.disconnect(_player._on_crawler_leveled_up)
	_expect(is_equal_approx(_player.crawler_damage_scale(), 1.0),
		"damage starts at 1X")
	_expect(is_equal_approx(_player.crawler_knockback_scale(), 1.0),
		"knockback starts at 1X")
	_expect(is_equal_approx(_player.crawler_range_scale(), 1.0),
		"range starts at 1X")
	_expect(is_zero_approx(_player.crawler_dodge_chance()),
		"dodge starts at no chance")
	_expect(is_equal_approx(_player.juke_cooldown(),
			CrawlerProgress.JUKE_COOLDOWN_BASE),
		"juke starts at the full cooldown")
	_expect(progress.owns_hat(CrawlerProgress.HAT_ID) == false,
		"run starts with no shop hat")
	_expect(_player.equipment.get_item(0).is_empty(),
		"home-screen hat does not carry into crawler")
	var before_gold := progress.gold
	_player.award_crawler_kill(1)
	_expect(progress.gold > before_gold, "kills pay gold")
	_expect(progress.xp > 0, "kills pay XP")
	_expect(progress.level == 1, "one kill is not enough to level")
	_player.award_crawler_kill(3)
	_expect(progress.kills == 2, "the run counts every kill")
	_expect(progress.gems_earned == CrawlerMeta.kill_gems(1) + CrawlerMeta.kill_gems(3),
		"the run counts gems from those kills")
	_expect(progress.level >= 2 and progress.unspent >= 1,
		"enough XP levels the player and banks a point")
	var gems_before := CrawlerMeta.gems()
	CrawlerMeta.add_gems(CrawlerProgress.TICKET_GEMS)
	progress.gold = CrawlerProgress.TICKET_GOLD
	_expect(progress.buy_respawn_ticket(), "gold and gems buy a respawn ticket")
	_expect(progress.has_respawn_ticket(), "the ticket stays on the run")
	_expect(CrawlerMeta.gems() == gems_before, "the ticket spends the gems")
	_expect(progress.spend_respawn_ticket() and not progress.has_respawn_ticket(),
		"death spends one ticket")
	var before_hp := _player.maximum_health()
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_HEALTH),
		"a level point can raise health")
	_expect(_player.maximum_health() > before_hp, "health rank raises max HP")
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_DAMAGE)
			or progress.unspent == 0,
		"spent points cannot be spent twice")
	progress.gold = CrawlerProgress.HAT_PRICE
	_expect(progress.buy_hat(), "gold buys the gale cap")
	_expect(progress.owns_hat(CrawlerProgress.HAT_ID),
		"the bought hat is owned for this run")
	_expect(_player.crawler_owned_hats().has(CrawlerProgress.HAT_ID),
		"only run-bought hats appear in the crawler wardrobe")
	progress.note_worn(CrawlerProgress.HAT_ID)
	_player._apply_crawler_progress()
	_expect(_player.crawler_flight_seconds() > CrawlerRules.FLIGHT_SECONDS,
		"the gale cap lengthens flight")
	progress.gold += CrawlerProgress.hat_price(CrawlerProgress.HAT_WARD)
	_expect(progress.buy_hat(CrawlerProgress.HAT_WARD), "gold buys the ward halo")
	_player.refresh_crawler_look()
	_expect(progress.wearing_ward_hat(), "buying the halo puts it on")
	_expect(_player.ward_active(), "the halo raises a bubble")
	var poke := DamageHit.impact(_player.combat_position(), 1.2, 18.0)
	poke.faction = DamageHit.Faction.ENEMY
	var hp := _player.health()
	_expect(is_zero_approx(_player.apply_damage(poke)),
		"the bubble eats the first hit")
	_expect(is_equal_approx(_player.health(), hp),
		"the bubble saves the hit points")
	_expect(not _player.ward_active(), "the bubble pops after one hit")
	_expect(_player.apply_damage(poke) > 0.0,
		"a second hit lands after the pop")
	_player._tick_ward(CrawlerProgress.WARD_RESPAWN)
	_expect(_player.ward_active(), "the bubble comes back after the wait")
	progress.note_worn(CrawlerProgress.HAT_ID)
	_player.refresh_crawler_look()
	var ranger := CrawlerRanger.new()
	ranger.last_source_peer = _player.peer_id
	_expect(ranger.last_source_peer == _player.peer_id,
		"mobs remember who last hit them")
	ranger.free()
	progress.unspent += 1
	var before_dex := progress.dex_scale()
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_DEXTERITY),
		"a level point can raise dexterity")
	_expect(progress.dex_scale() > before_dex, "dexterity ranks raise walk pace")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_DODGE),
		"a level point can raise dodge")
	_expect(is_equal_approx(
			_player.crawler_dodge_chance(), CrawlerProgress.DODGE_PER_RANK),
		"one dodge rank is six percent")
	var dodge_poke := DamageHit.impact(_player.combat_position(), 1.2, 18.0)
	dodge_poke.faction = DamageHit.Faction.ENEMY
	var dodge_hp := _player.health()
	_player._dodge_roll_override = 0.0
	_expect(is_zero_approx(_player.apply_damage(dodge_poke)),
		"a successful dodge deals no damage")
	_expect(is_equal_approx(_player.health(), dodge_hp),
		"a successful dodge keeps the hit points")
	_player._dodge_roll_override = 0.99
	_expect(_player.apply_damage(dodge_poke) > 0.0,
		"a failed dodge still lands")
	_player._dodge_roll_override = 0.99
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_DEFENSE),
		"a level point can raise defense")
	_expect(is_equal_approx(
			_player.crawler_defense_share(), CrawlerProgress.DEFENSE_PER_RANK),
		"one defense rank is eight percent")
	var defense_hp := _player.health()
	var taken := _player.apply_damage(dodge_poke)
	_expect(is_equal_approx(
			taken, dodge_poke.amount * (1.0 - CrawlerProgress.DEFENSE_PER_RANK)),
		"defense cuts incoming damage")
	_expect(is_equal_approx(_player.health(), defense_hp - taken),
		"defense still spends the reduced hit points")
	_player._dodge_roll_override = -1.0
	progress.unspent += 1
	var before_juke := _player.juke_cooldown()
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_JUKE),
		"a level point can raise juke")
	_expect(_player.juke_cooldown() < before_juke,
		"juke ranks shorten the dash wait")
	_expect(is_equal_approx(
			_player.juke_cooldown(),
			CrawlerProgress.JUKE_COOLDOWN_BASE
				- CrawlerProgress.JUKE_COOLDOWN_PER_RANK),
		"one juke rank cuts a tenth of a second")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_KNOCKBACK),
		"a level point can raise knockback")
	_expect(is_equal_approx(
			_player.crawler_knockback_scale(),
			1.0 + CrawlerProgress.KNOCKBACK_PER_RANK),
		"one knockback rank is twelve percent")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_RANGE),
		"a level point can raise range")
	_expect(is_equal_approx(
			_player.crawler_range_scale(),
			1.0 + CrawlerProgress.RANGE_PER_RANK),
		"one range rank is twelve percent")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_LUCK),
		"a level point can raise luck")
	_expect(progress.rank_of(CrawlerProgress.STAT_LUCK) >= 0.999,
		"spent luck is stored on the run")
	_expect(CrawlerProgress.rarity_weights(progress.luck_rank())[3]
			> CrawlerProgress.rarity_weights(0.0)[3],
		"luck makes legendary boosts more likely")
	progress.gold += CrawlerProgress.hat_price(CrawlerProgress.HAT_LUCK)
	_expect(progress.buy_hat(CrawlerProgress.HAT_LUCK), "gold buys the fortune cap")
	_expect(progress.wearing_luck_hat(), "buying the fortune cap puts it on")
	_expect(progress.luck_rank() >= 1.0 + CrawlerProgress.HAT_LUCK_BONUS,
		"the fortune cap adds a lot of luck")
	progress.note_worn(CrawlerProgress.HAT_ID)
	_player.refresh_crawler_look()
	_expect(is_equal_approx(progress.luck_rank(), 1.0),
		"taking the fortune cap off returns luck to its ranks")
	var max_hp := _player.maximum_health()
	_player.stats.set_health(max_hp * 0.5)
	var wounded := _player.health()
	progress.last_levels_gained = 1
	_player._apply_crawler_level_heal()
	_expect(is_equal_approx(
			_player.health(),
			wounded + max_hp * CrawlerProgress.LEVEL_HEAL),
		"level-up restores ten percent health")
	_expect(CrawlerRules.CITY_HEAL_PER_SECOND > 0.0,
		"cities restore health")
	_expect(not _player.buy_crawler_hat() or progress.owns_hat(CrawlerProgress.HAT_ID),
		"the shop only sells inside a city")


func _check_level_burst() -> void:
	const BURST := preload("res://ui/combat/crawler_level_burst.gd")
	var hud := _player.hud
	_expect(hud != null, "crawler player has a HUD for the level-up sting")
	if hud == null:
		return
	_expect(BURST.HOLD >= 0.8 and BURST.HOLD <= 1.8,
		"level-up holds briefly before the pause")
	_player.crawler_progress.unspent += 1
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
	_player._on_crawler_leveled_up()
	_player._on_crawler_leveled_up()
	await get_tree().process_frame
	var burst := hud.get_node_or_null("CrawlerLevelBurst")
	_expect(burst != null, "killing enough XP plays a Level Up burst")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") == null,
		"the spend menu waits for the burst")
	_expect(not _player._menu_open, "the game stays live during the burst")
	var title := hud.find_child("LevelUpTitle", true, false) as Label
	_expect(title != null and title.text == "Level Up",
		"the burst shows Level Up at the top of the HUD")
	if burst is Control:
		_expect(not (burst as Control).clip_contents,
			"the level-up explosion is not boxed by a HUD rectangle")
	if burst != null:
		burst._process(BURST.HOLD)
	await get_tree().process_frame
	_expect(hud.get_node_or_null("CrawlerLevelBurst") == null,
		"the burst leaves once the menu is due")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") != null,
		"the spend menu opens after the burst")
	_expect(_player._menu_open, "the game pauses when the menu opens")
	var menu := hud.get_node_or_null("CrawlerLevelMenu") as CrawlerLevelMenu
	_expect(menu != null and menu.HOLD_SECONDS > 0.06 and menu.HOLD_SECONDS <= 0.20,
		"level-up tiles spend on a short hold")
	if menu != null:
		var hint := menu.find_child("SpendHint", true, false) as Label
		_expect(hint != null and hint.text.contains("HOLD"),
			"the spend menu tells the player to hold")
		var reroll := menu.find_child("RerollOffers", true, false) as Button
		_expect(reroll != null and reroll.text.contains("g"),
			"the spend menu offers a gold reroll")
		var press := InputEventMouseButton.new()
		press.pressed = true
		press.button_index = MOUSE_BUTTON_LEFT
		menu._on_tile_input(press, CrawlerProgress.STAT_HEALTH)
		_expect(_player.crawler_progress.unspent == 1,
			"pressing a tile does not spend the point")
		menu._process(0.08)
		var fill := menu.find_child("SpendFill", true, false) as ColorRect
		_expect(menu.hold_progress() > 0.0 and fill != null and fill.visible,
			"holding a tile fills a bar on that tile")
		_expect(_player.crawler_progress.unspent == 1,
			"a short hold does not spend yet")
		menu._process(menu.HOLD_SECONDS)
	await get_tree().process_frame
	_expect(_player.crawler_progress.unspent == 0,
		"holding a tile through the bar spends the point")
	menu = hud.get_node_or_null("CrawlerLevelMenu") as CrawlerLevelMenu
	if menu != null:
		menu.queue_free()
	if _player._menu_open:
		_player.close_menu()
	await get_tree().process_frame


func _check_achievement_burst() -> void:
	const BURST := preload("res://ui/combat/achievement_burst.gd")
	var hud := _player.hud
	_expect(hud != null, "crawler player has a HUD for achievement stings")
	if hud == null or _player.journal == null:
		return
	_player.journal.reset_achievements()
	_player.journal.note_kill(10)
	await get_tree().process_frame
	var burst := hud.get_node_or_null("AchievementBurst")
	_expect(burst != null, "ten kills play an achievement burst")
	var heading := hud.find_child("AchievementCompleteTitle", true, false) as Label
	var detail := hud.find_child("AchievementCompleteName", true, false) as Label
	_expect(heading != null and heading.text == "ACHIEVEMENT COMPLETE",
		"the burst titles the unlock Achievement Complete")
	_expect(detail != null and detail.text == '"Kill 10 mobs"',
		"the burst names Kill 10 mobs in quotes")
	if burst is Control:
		_expect(not (burst as Control).clip_contents,
			"the achievement explosion is not boxed by a HUD rectangle")
	if burst != null:
		burst._process(BURST.HOLD)
	await get_tree().process_frame
	_expect(hud.get_node_or_null("AchievementBurst") == null,
		"the achievement burst leaves after its hold")


func _check_city_store() -> void:
	var stock := CrawlerProgress.shop_stock()
	_expect(stock.has("big") and stock.has("wobble"),
		"the city stock sells mods")
	_expect(not stock.has("starfire") and not stock.has("laser_eyes"),
		"the mod stall does not sell abilities")
	var abilities := CrawlerProgress.ability_stock()
	_expect(abilities.has("laser_eyes") and abilities.has("starfire")
			and abilities.has("meteor_punch"),
		"the ability stall sells laser eyes, meteor punch, and starfire")
	_expect(CrawlerProgress.upgrade_price(1) > CrawlerProgress.upgrade_price(0),
		"each upgrade rank costs more")
	var kit := _player.crawler_kit
	_expect(kit != null, "crawler player has a kit for the card stalls")
	if kit == null:
		return
	_expect(kit.shop_grant("starfire"), "the stall can grant a starfire copy")
	var before := kit.owned_cards().size()
	_expect(kit.shop_grant("wobble"), "the stall can grant a wobble mod")
	_expect(kit.owned_cards().size() > before, "a bought mod lands in the kit")
	var eyes := kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes", "the hotbar still holds laser eyes")
	if eyes != null:
		var damage := float(kit.stats_for(eyes).get("damage", 0.0))
		var slots := eyes.slot_count
		_expect(kit.upgrade_card(eyes.uid, "damage"), "the upgrade stall can raise beam damage")
		_expect(float(kit.stats_for(eyes).get("damage", 0.0)) > damage,
			"laser eyes damage upgrades")
		_expect(kit.upgrade_card(eyes.uid, "slots"), "the upgrade stall can add a modifier slot")
		_expect(eyes.slot_count == slots + 1, "laser eyes slot upgrades")
	var wobble: CrawlerCard = null
	for card: CrawlerCard in kit.owned_cards():
		if card.id == "wobble":
			wobble = card
			break
	_expect(wobble != null, "the granted card is wobble")
	if wobble != null:
		_expect(kit.upgrade_card(wobble.uid, "wobble"), "wobble upgrades its one stat")
		_expect(wobble.upgrade_rank("wobble") == 1, "wobble rank is stored on the mod")
	var menu: CrawlerFieldMenu = load("res://ui/menu/crawler_field_menu.gd").new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.HATS, "the city store opens on hats")
	var progress := _player.crawler_progress
	var held_hats := progress.owned_hats.duplicate()
	var worn := progress.worn_hat
	progress.owned_hats = PackedStringArray()
	progress.worn_hat = ""
	menu._clear_list()
	menu._fill_hats(progress, CrawlerProgress.HAT_PRICE)
	var buy := menu.find_child("HatActButton", true, false) as Button
	var hat_icon := menu.find_child("HatIcon_crawler_gale_hat", true, false) as TextureRect
	var hat_grid := menu.find_child("StoreHatGrid", true, false) as GridContainer
	var ward_tile := menu.find_child("HatTile_crawler_ward_hat", true, false) as Control
	_expect(buy != null and buy.visible and buy.text == "BUY",
		"the hat stall shows a BUY button")
	_expect(hat_icon != null and hat_icon.visible,
		"the hat stall shows a gale-cap icon")
	_expect(menu.find_child("HatPreviewFigure_crawler_gale_hat", true, false) == null,
		"hat tiles do not preview a worn player")
	_expect(hat_grid != null and hat_grid.columns >= 3,
		"hats sit in a multi-column tile grid")
	_expect(ward_tile != null and ward_tile.visible,
		"the hat stall also sells the ward halo")
	var luck_hat := menu.find_child("HatTile_crawler_luck_hat", true, false) as Control
	_expect(luck_hat != null and luck_hat.visible,
		"the hat stall also sells the fortune cap")
	_expect(menu.find_child("LuckTile", true, false) == null,
		"luck is not for sale in the hat stall")
	progress.owned_hats = held_hats
	progress.worn_hat = worn
	menu._clear_list()
	menu._fill_hats(progress, progress.gold)
	var sold := menu.find_child("HatActButton", true, false) as Button
	_expect(sold != null and sold.visible and sold.text == "SOLD",
		"a bought hat is marked sold")
	_expect(sold.disabled, "sold hats cannot be taken off in the store")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.CARDS,
		"the next tab is the mods stall")
	menu._clear_list()
	menu._fill_cards(progress.gold)
	var mod_grid := menu.find_child("StoreModGrid", true, false) as GridContainer
	var wobble_mod := menu.find_child("ModTile_wobble", true, false) as Control
	var wobble_icon := menu.find_child("ModIcon_wobble", true, false) as TextureRect
	_expect(mod_grid != null and mod_grid.columns >= 3,
		"mods sit in a multi-column tile grid")
	_expect(wobble_mod != null and wobble_mod.visible,
		"the mods stall sells wobble as a tile")
	_expect(wobble_icon != null and wobble_icon.texture != null,
		"mod tiles show the catalogue icon")
	var wobble_host := menu.find_child("ModHostIcon_wobble", true, false) as TextureRect
	_expect(wobble_host != null and wobble_host.visible
			and wobble_host.texture == CrawlerCatalog.texture_for("laser_eyes"),
		"ability-specific mods show the host ability icon")
	_expect(menu.find_child("ModTile_big", true, false) != null,
		"the mods stall also sells big as a tile")
	_expect(menu.find_child("ModHostIcon_big", true, false) == null,
		"generic mods do not show a host ability icon")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.ABILITIES,
		"the next tab is the ability stall")
	menu._clear_list()
	menu._fill_abilities(progress.gold)
	var ability_grid := menu.find_child("StoreAbilityGrid", true, false) as GridContainer
	var eyes_buy := menu.find_child("AbilityTile_laser_eyes", true, false) as Control
	var star_buy := menu.find_child("AbilityTile_starfire", true, false) as Control
	_expect(ability_grid != null and ability_grid.columns >= 3,
		"abilities sit in a multi-column tile grid")
	_expect(eyes_buy != null and eyes_buy.visible,
		"the ability stall sells laser eyes")
	_expect(star_buy != null and star_buy.visible,
		"the ability stall sells starfire")
	_expect(menu.find_child("AbilityTile_meteor_punch", true, false) != null,
		"the ability stall sells meteor punch")
	_expect(menu.find_child("AbilityAct_laser_eyes", true, false) != null
			and menu.find_child("AbilityAct_starfire", true, false) != null
			and menu.find_child("AbilityAct_meteor_punch", true, false) != null,
		"ability tiles keep a BUY button")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.UPGRADES,
		"the next tab upgrades owned cards")
	var sheet := menu.find_child("MenuBackground", true, false) as TextureRect
	_expect(sheet != null and sheet.texture == GameMenu.MENU_BACKGROUND,
		"the city store uses the tab menu starry sheet")
	menu._show_body(true)
	menu._fill_upgrades(progress.gold)
	await get_tree().process_frame
	var loadout := menu.find_child("StoreUpgradeLoadout", true, false) as Control
	var detail := menu.find_child("StoreUpgradeDetail", true, false) as Control
	var eyes_tile := menu.find_child("CrawlerAbilityTile_0", true, false) as Control
	var bag_tile := menu.find_child("CrawlerBag_0", true, false) as Control
	var damage := menu.find_child("UpgradeAct_damage", true, false) as Button
	_expect(loadout != null and loadout.visible,
		"upgrades show the ability and bag loadout on top")
	_expect(detail != null and detail.visible,
		"upgrades show the selected card under the loadout")
	_expect(eyes_tile != null and bag_tile != null,
		"the loadout draws three abilities and the bag even if empty")
	_expect(damage != null and damage.visible,
		"selecting laser eyes lists its damage upgrade")
	kit.grant(CrawlerCatalog.make_ability("starfire").to_dict())
	menu._fill_upgrades(progress.gold)
	var star_tile := menu.find_child("CrawlerAbilityTile_1", true, false) as CrawlerAbilityTile
	_expect(star_tile != null and star_tile.card() != null
			and star_tile.card().id == "starfire",
		"the upgrade stall can select seated starfire")
	if star_tile != null:
		star_tile.picked.emit(star_tile)
	_expect(menu.find_child("UpgradeTile_damage", true, false) != null
			and menu.find_child("UpgradeTile_cooldown", true, false) != null
			and menu.find_child("UpgradeTile_size", true, false) != null
			and menu.find_child("UpgradeTile_range", true, false) != null
			and menu.find_child("UpgradeTile_knockback", true, false) != null
			and menu.find_child("UpgradeTile_slots", true, false) != null,
		"starfire lists damage, cooldown, size, range, knockback, and slots")
	_expect(menu.find_child("UpgradeTile_duration", true, false) == null,
		"starfire does not sell a firing-time upgrade")
	var upgrade_grid := menu.find_child("StoreUpgradeRows", true, false) as GridContainer
	var damage_tile := menu.find_child("UpgradeTile_damage", true, false) as Control
	var bag_center := menu.find_child("StoreInventoryCenter", true, false) as Control
	_expect(upgrade_grid != null and upgrade_grid.columns >= 3,
		"upgrades sit in a multi-column tile grid")
	_expect(damage_tile != null and damage.is_inside_tree()
			and damage.get_parent() == damage_tile.get_child(0),
		"the upgrade button lives inside its tile")
	_expect(bag_center != null, "the bag slots are centred under the abilities")
	var wobble_tile := menu.find_child("CrawlerBag_0", true, false) as RedItemSlot
	_expect(wobble_tile != null
			and CrawlerCatalog.catalog_id(wobble_tile.item_id()) == "wobble",
		"the bought wobble sits on a store bag tile")
	if wobble_tile != null:
		_expect(CrawlerCatalog.texture_for(wobble_tile.item_id()) != null,
			"store bag tiles resolve the wobble icon")
		_expect(wobble_tile.size.x >= 36.0 and wobble_tile.size.y >= 36.0,
			"store bag tiles keep enough room for the icon")
		_expect(wobble_tile._icon_modulate(wobble_tile.item_id()) == Color.WHITE,
			"catalogue mod icons keep their authored colors")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.INVENTORY,
		"the next tab is the city inventory store")
	menu._clear_list()
	menu._fill_inventory()
	var note := menu.find_child("StoreEmpty", true, false) as Label
	_expect(note != null and note.visible
			and note.text.contains("other cities"),
		"the inventory store explains city-to-city ability pickup")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.QUESTS,
		"the next tab is the quest stall")
	menu._clear_list()
	menu._fill_quests()
	_expect(menu.find_child("QuestAct_office_tower", true, false) != null,
		"the quest stall sells the tower")
	_expect(menu.find_child("QuestAct_castle", true, false) != null,
		"the quest stall sells the castle")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.MARKET,
		"the last tab is the black market")
	menu._clear_list()
	menu._fill_market()
	var ticket := menu.find_child("TicketAct", true, false) as Button
	_expect(ticket != null and ticket.visible and ticket.text == "BUY",
		"the black market sells respawn tickets")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.HATS,
		"tabs wrap back to the hat stall")
	menu.queue_free()


func _check_crawler_death() -> void:
	var progress := _player.crawler_progress
	_expect(progress != null, "crawler death reads the run ledger")
	if progress == null:
		return
	progress.unlock_site(CrawlerRules.START_SITE_ID)
	progress.unlock_site(CrawlerRules.CITY_SITE_ID)
	var summary := progress.run_summary()
	_expect(summary.contains("killed"), "the summary names mobs killed")
	_expect(summary.contains(CrawlerRules.START_SITE_TITLE)
			and summary.contains(CrawlerRules.CITY_SITE_TITLE),
		"the summary names discovered sites")
	_expect(summary.contains("gem"), "the summary names gems earned")
	progress.respawn_tickets = 0
	_player._die(null)
	await get_tree().process_frame
	var screen := _player.death_screen()
	_expect(screen != null and screen.title_text() == DeathScreen.GAME_OVER_TITLE,
		"crawler death says game over")
	_expect(screen.sends_home()
			and screen.respawn_button() != null
			and screen.respawn_button().text == DeathScreen.HOME_LABEL,
		"without a ticket the only way out is home")
	_expect(screen.summary_text().contains("killed")
			and screen.summary_text().contains("gem"),
		"game over lists the run")
	var homes := [0]
	screen.home_requested.connect(func() -> void: homes[0] += 1)
	screen._process(DeathScreen.ARM_DELAY + 0.1)
	screen.respawn_button().pressed.emit()
	_expect(homes[0] == 1, "home ends the run")
	_expect(_player.is_dead(), "home does not revive the body")
	_player.respawn_at(_player.global_transform)
	await get_tree().process_frame
	_expect(_player.death_screen() == null and not _player.is_dead(),
		"a later revive clears the overlay")
	progress.respawn_tickets = 1
	_player._die(null)
	await get_tree().process_frame
	screen = _player.death_screen()
	_expect(screen != null and not screen.sends_home()
			and screen.respawn_button() != null
			and screen.respawn_button().text == DeathScreen.RESPAWN_LABEL,
		"a ticket offers a respawn")
	_player.respawn_at(_player.global_transform)
	await get_tree().process_frame


func _check_monument_collision() -> void:
	var hosts := PatchMonuments.new()
	add_child(hosts)
	for path in [PatchMonuments.TOWER_MODEL, PatchMonuments.CASTLE_MODEL]:
		var site := PatchMonument.new()
		add_child(site)
		hosts._attach_model(site, path)
		await get_tree().process_frame
		_expect(site.find_child("MonumentCollision", true, false) == null,
			"%s is not wrapped in a solid box" % path.get_file())
		_expect(_monument_has_trimesh(site),
			"%s uses wall and floor triangle collision" % path.get_file())
		_expect(not _monument_has_envelope_box(site),
			"%s has no building-sized box collider" % path.get_file())
		_expect(_night_lights_on(site) > 0,
			"%s glowing fixtures cast real night light" % path.get_file())
		site.queue_free()
	hosts.queue_free()


func _night_lights_on(node: Node) -> int:
	var rig := node.find_child("NightLights", true, false)
	if rig == null:
		return 0
	var count := 0
	for child in rig.get_children():
		if child is OmniLight3D:
			count += 1
	return count


func _monument_has_trimesh(node: Node) -> bool:
	if node is CollisionShape3D:
		if (node as CollisionShape3D).shape is ConcavePolygonShape3D:
			return true
	for child in node.get_children():
		if _monument_has_trimesh(child):
			return true
	return false


func _named_mesh_visible(node: Node, needle: String) -> bool:
	var folded := needle.to_lower()
	if node is MeshInstance3D:
		var mesh_i := node as MeshInstance3D
		if mesh_i.visible and String(mesh_i.name).to_lower().contains(folded):
			return true
	for child in node.get_children():
		if _named_mesh_visible(child, needle):
			return true
	return false


func _named_collision_enabled(node: Node, needle: String) -> bool:
	var folded := needle.to_lower()
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		if body.collision_layer != 0 and String(node.name).to_lower().contains(folded):
			return true
	if node is CollisionShape3D:
		var collider := node as CollisionShape3D
		if not collider.disabled:
			var held := node.get_parent()
			if String(node.name).to_lower().contains(folded) \
					or (held != null and String(held.name).to_lower().contains(folded)):
				return true
	for child in node.get_children():
		if _named_collision_enabled(child, needle):
			return true
	return false


func _monument_has_envelope_box(node: Node) -> bool:
	if node is CollisionShape3D:
		var shape := (node as CollisionShape3D).shape
		if shape is BoxShape3D:
			var size: Vector3 = (shape as BoxShape3D).size
			if size.x >= 80.0 and size.z >= 80.0 and size.y >= 20.0:
				return true
	for child in node.get_children():
		if _monument_has_envelope_box(child):
			return true
	return false


func _check_building_flora() -> void:
	_expect(BuildingFloraClear.PAD_METRES == 10.0, "flora keeps 10 metres off a building")
	var id := "flora_clear_test"
	BuildingFloraClear.unregister(id)
	var pole := Vector3.RIGHT
	var near := (Vector3.RIGHT * 8000.0 + Vector3.UP * 24.0).normalized()
	var far := (Vector3.RIGHT * 8000.0 + Vector3.UP * 55.0).normalized()
	_expect(not BuildingFloraClear.covers(pole), "the test pad starts clear")
	BuildingFloraClear.register(id, pole, 20.0, 8000.0)
	_expect(BuildingFloraClear.covers(pole), "flora is kept off the building pad")
	_expect(BuildingFloraClear.covers(near),
		"flora is kept 10 metres past the building footprint")
	_expect(not BuildingFloraClear.covers(far),
		"flora still grows beyond the 10 metre ring")
	_expect(PatchCity.flora_covers(near), "plant scatter uses the building keep-out")
	BuildingFloraClear.unregister(id)
	_expect(not BuildingFloraClear.covers(pole),
		"freed buildings return the ground to flora")


func _check_building_foundation() -> void:
	_expect(BuildingFoundation.peak_raise(10.0, PackedFloat32Array([10.0, 8.0, 12.5])) == 2.5,
		"buildings rise to the highest ground under the base")
	_expect(BuildingFoundation.peak_raise(12.0, PackedFloat32Array([10.0, 11.0])) == 0.0,
		"flat or lower ground does not lift the hull")
	_expect(BuildingFoundation.drop_at(12.0, 8.0) == 4.0 + BuildingFoundation.EMBED,
		"floating corners extrude down to the ground")
	_expect(not BuildingFoundation.uses_pad_mesh("02 Edge hummocks | Ground"),
		"hummocks do not lift the village")
	_expect(not BuildingFoundation.uses_pad_mesh("00 Organic meadow | Earth"),
		"earth under the grass is not the building pad")
	_expect(not BuildingFoundation.uses_pad_mesh("70 Pine woodland | Pine"),
		"tree scatter is not a seating pad")
	_expect(BuildingFoundation.uses_pad_mesh("40 Commons L0 | Concrete"),
		"building floors still seat the village")
	_expect(BuildingFoundation.uses_pad_mesh("01 Winding stone trails | Stone"),
		"the plaza trails still seat the village")
	var root := Node3D.new()
	add_child(root)
	BuildingFoundation.seat(root, null)
	_expect(root.get_node_or_null(BuildingFoundation.SKIRT_NAME) == null,
		"seating without a planet is a no-op")
	root.queue_free()


func _check_monument_quests() -> void:
	var site := PatchMonument.new()
	site.monument_id = CrawlerProgress.QUEST_TOWER
	site.title = "Meridian Tower"
	site.waypoint = false
	site.keepout_radius = 180.0
	add_child(site)
	await get_tree().process_frame
	_expect(PatchMonument.blocks_any(get_tree(), site.global_position),
		"mobs cannot spawn on the tower pad")
	_expect(not PatchMonument.blocks_any(
			get_tree(), site.global_position + Vector3(400.0, 0.0, 0.0)),
		"the keep-out does not cover the far field")
	var progress := _player.crawler_progress
	_expect(progress != null, "crawler player can buy monument quests")
	if progress != null:
		progress.gold = maxi(progress.gold, CrawlerProgress.quest_price(
			CrawlerProgress.QUEST_TOWER))
		_expect(progress.buy_quest(CrawlerProgress.QUEST_TOWER),
			"gold buys the tower quest")
		_expect(progress.owns_quest(CrawlerProgress.QUEST_TOWER),
			"the bought quest stays on the run")
	PatchMonument.enable_waypoint(CrawlerProgress.QUEST_TOWER)
	_expect(site.waypoint, "buying the quest lights the tower waypoint")
	_expect(site.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"the quest mark is on tilde")
	site.queue_free()


func _check_tilde_city_waypoint() -> void:
	_expect(not _player._waypoints_wanted, "tilde starts closed")
	var tilde := InputEventKey.new()
	tilde.physical_keycode = 96 as Key
	tilde.pressed = true
	_player._unhandled_input(tilde)
	_expect(_player._waypoints_wanted, "tilde opens the city waypoint")
	_expect(not _player._coordinates_wanted,
		"crawler tilde does not open the info plate")
	var info := _player.find_child("CoordinatePlate", true, false) as CanvasItem
	_expect(info == null or not info.visible,
		"crawler tilde hides the coordinate plate")
	var mini := _player.find_child("CityMinimap", true, false) as CanvasItem
	_expect(mini == null or not mini.visible,
		"crawler tilde hides the mini-map")
	var city := Landmark.new()
	city.title = CrawlerRules.CITY_SITE_TITLE
	city.waypoint = true
	add_child(city)
	city.add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
	var other := Landmark.new()
	other.title = "Vacationer's Landing"
	other.waypoint = true
	add_child(other)
	await get_tree().process_frame
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	_expect(layer != null and layer.enabled, "crawler tilde enables waypoints")
	if layer != null:
		layer._process(0.016)
		var names := layer.drawn(0.0)
		_expect(names.has(CrawlerRules.CITY_SITE_TITLE), "tilde points at Neon Fjord")
		_expect(not names.has("Vacationer's Landing"),
			"tilde hides every other landmark")
	var plan := PatchCityGenerator.Plan.new()
	plan.patch_id = 7
	plan.patch_name = "Quiet Inlet 4"
	NetworkManager.session_options["crawler_cities"] = [7]
	var pad := PatchCity.new()
	pad.plan = plan
	add_child(pad)
	var mark := pad.ensure_crawler_waypoint()
	_expect(mark != null and mark.waypoint and mark.title == "Quiet Inlet 4",
		"the first city raises a waypoint")
	_expect(mark != null and mark.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"the city waypoint is the crawler tilde mark")
	_player._unhandled_input(tilde)
	_expect(not _player._waypoints_wanted, "second tilde closes the city waypoint")
	city.queue_free()
	other.queue_free()
	pad.queue_free()


func _check_entering_sites() -> void:
	var progress := _player.crawler_progress
	_expect(progress != null, "entering notes use the run ledger")
	if progress == null:
		return
	progress.last_entered_site = ""
	progress.unlocked_sites = PackedStringArray()
	progress.remember()
	var gems_before := CrawlerMeta.gems()
	var earned_before := progress.gems_earned
	var site_gems := CrawlerProgress.SITE_GEMS
	var spawn := CrawlerSite.new()
	spawn.site_id = CrawlerRules.START_SITE_ID
	spawn.title = CrawlerRules.START_SITE_TITLE
	spawn.enter_radius = 40.0
	spawn.position = Vector3.ZERO
	add_child(spawn)
	var village := CrawlerSite.new()
	village.site_id = CrawlerRules.CITY_SITE_ID
	village.title = CrawlerRules.CITY_SITE_TITLE
	village.enter_radius = 40.0
	village.position = Vector3(200.0, 0.0, 0.0)
	add_child(village)
	var tower := PatchMonument.new()
	tower.monument_id = CrawlerProgress.QUEST_TOWER
	tower.title = "Meridian Tower"
	tower.keepout_radius = 40.0
	tower.waypoint = false
	tower.position = Vector3(400.0, 0.0, 0.0)
	add_child(tower)
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_expect(CrawlerSites.poll(_player) == CrawlerRules.START_SITE_TITLE,
		"spawn shows Entering Tide Margin")
	_expect(spawn.waypoint and spawn.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"walking onto spawn lights its waypoint")
	var hud := _player.combat_hud() as CombatHud
	_expect(hud != null and hud.entering_text() == "Entering Tide Margin",
		"the entering note sits on the combat HUD")
	_expect(hud != null and hud.entering_bonus() == "+%d gems" % site_gems,
		"first visit shows +gems under the entering note")
	_expect(CrawlerMeta.gems() == gems_before + site_gems
			and progress.gems_earned == earned_before + site_gems,
		"first visit banks discovery gems")
	_player.global_position = Vector3(80.0, 0.0, 0.0)
	_expect(CrawlerSites.poll(_player).is_empty(),
		"wilderness does not fire another entering note")
	_player.global_position = Vector3.ZERO
	_expect(CrawlerSites.poll(_player).is_empty(),
		"coming back to the same site does not repeat the note")
	_player.global_position = Vector3(200.0, 0.0, 0.0)
	_expect(CrawlerSites.poll(_player) == CrawlerRules.CITY_SITE_TITLE,
		"the village shows Entering Neon Fjord")
	_expect(hud != null and hud.entering_bonus() == "+%d gems" % site_gems,
		"a new village also shows +gems")
	_expect(village.waypoint, "walking into the village lights its waypoint")
	_player.global_position = Vector3.ZERO
	_expect(CrawlerSites.poll(_player) == CrawlerRules.START_SITE_TITLE,
		"a later site lets the first place announce again")
	_expect(hud != null and hud.entering_bonus().is_empty(),
		"a known site does not show another gem bonus")
	_expect(CrawlerMeta.gems() == gems_before + site_gems * 2
			and progress.gems_earned == earned_before + site_gems * 2,
		"revisiting a known site does not pay again")
	_player.global_position = Vector3(400.0, 0.0, 0.0)
	_expect(CrawlerSites.poll(_player) == "Meridian Tower",
		"assigned monuments announce when you near them")
	_expect(hud != null and hud.entering_bonus() == "+%d gems" % site_gems,
		"a first monument visit pays gems")
	_expect(tower.waypoint and tower.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"visiting the tower lights its tilde mark")
	var restored := CrawlerProgress.new()
	restored.from_dict(progress.to_dict())
	_expect(restored.site_unlocked(CrawlerRules.START_SITE_ID)
			and restored.site_unlocked(CrawlerRules.CITY_SITE_ID)
			and restored.last_entered_site == CrawlerProgress.QUEST_TOWER,
		"visited sites persist on the run")
	spawn.queue_free()
	village.queue_free()
	tower.queue_free()
	if ResourceLoader.exists(CrawlerCityRing.VILLAGE_MODEL):
		var packed := load(CrawlerCityRing.VILLAGE_MODEL) as PackedScene
		if packed != null:
			var ring = CITY_RING.new()
			ring.force_village = true
			add_child(ring)
			await get_tree().process_frame
			_expect(ring.get_node_or_null("Village") != null,
				"the first city seats Neon Fjord")
			_expect(ring.find_child("CityWall", true, false) == null,
				"the village replaces the stand-in walls")
			_expect(_monument_has_trimesh(ring),
				"the village keeps walkable collision")
			_expect(not _named_collision_enabled(ring, "meadow"),
				"the meadow dirt volume does not shove walkers")
			_expect(_named_mesh_visible(ring, "meadow |"),
				"the painted meadow stays")
			_expect(_night_lights_on(ring) > 0,
				"village neon and lamps cast real night light")
			ring.queue_free()
			await get_tree().process_frame
	if ResourceLoader.exists(CrawlerSpawnPad.MODEL):
		var packed_pad := load(CrawlerSpawnPad.MODEL) as PackedScene
		if packed_pad != null:
			var pad := CrawlerSpawnPad.new()
			pad.force_model = true
			add_child(pad)
			await get_tree().process_frame
			_expect(pad.get_node_or_null("Relay") != null,
				"spawn seats the Relay 07 teleporter")
			_expect(_monument_has_trimesh(pad)
					or _ring_has_blocking_collision(pad),
				"the teleporter keeps walkable collision")
			_expect(_night_lights_on(pad) > 0,
				"the teleporter's glowing fixtures cast real night light")
			pad.queue_free()
			await get_tree().process_frame


func _press_interact(player: OnlinePlayer) -> void:
	var press := InputEventAction.new()
	press.action = "interact"
	press.pressed = true
	player._unhandled_input(press)


func _ring_has_blocking_collision(root: Node) -> bool:
	if root is CollisionObject3D and (root as CollisionObject3D).collision_layer != 0:
		return true
	if root is CollisionShape3D:
		return true
	for child in root.get_children():
		if _ring_has_blocking_collision(child):
			return true
	return false


func _ring_walls_are_clear(root: Node) -> bool:
	var found := [false]
	return _walls_clear(root, found) and bool(found[0])


func _walls_clear(node: Node, found: Array) -> bool:
	if node is MeshInstance3D:
		found[0] = true
		var material := (node as MeshInstance3D).material_override
		if not (material is StandardMaterial3D):
			return false
		var std := material as StandardMaterial3D
		if std.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA \
				or absf(std.albedo_color.a - 0.40) > 0.02:
			return false
	for child in node.get_children():
		if not _walls_clear(child, found):
			return false
	return true


func _ranger_albedo(ranger: CrawlerRanger) -> Color:
	for material in ranger._materials:
		if material == null:
			continue
		var colour: Variant = material.get_shader_parameter(&"albedo")
		if colour is Color:
			return colour
	return Color.BLACK


func _face_along(player: OnlinePlayer, toward: Vector3, up := Vector3.UP) -> void:
	var along := toward
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	player.global_transform = Transform3D(
		Basis.looking_at(along.normalized(), up), player.global_position)


func _has_named_clip(animator: AnimationPlayer, clip: String) -> bool:
	if animator == null:
		return false
	for listed in animator.get_animation_list():
		if listed == clip or listed.ends_with("/" + clip):
			return true
	return false


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_siege_test failed: %s" % label)
