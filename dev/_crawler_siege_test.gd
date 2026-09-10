extends Node

## Headless checks for crawler field rules: flight fuel, wild roster, levels,
## safe cities, and the HUD blue bar.
##
##     godot --headless --path . dev/_crawler_siege_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const CITY_RING := preload("res://game/crawler/crawler_city_ring.gd")
const GLOAM := preload("res://game/crawler/crawler_gloam.gd")
const VESPER := preload("res://game/crawler/crawler_vesper.gd")
const THRENODY := preload("res://game/crawler/crawler_threnody.gd")
const DEMON_BODY := preload("res://game/crawler/crawler_demon_body.gd")
const DEMON_COLUMN := preload("res://game/crawler/crawler_demon_column.gd")
const MOB_SENSE := preload("res://game/crawler/crawler_mob_sense.gd")
const TIDEKIN := preload("res://game/crawler/crawler_tidekin.gd")
const TIDEKIN_OFFICE := preload("res://game/crawler/crawler_tidekin_office.gd")
const KESTREL := preload("res://game/crawler/crawler_kestrel.gd")
const BASTION := preload("res://game/crawler/crawler_bastion.gd")
const WEAVER := preload("res://game/crawler/crawler_weaver.gd")
const ROBOT_MODELS := preload("res://game/crawler/crawler_robot_models.gd")
const ALIEN_MODELS := preload("res://game/crawler/crawler_alien_models.gd")
const TREE_BOSS := preload("res://game/crawler/crawler_tree_boss.gd")

var _failures := 0
var _player: OnlinePlayer


class DummyLot extends Node:
	var wrecked := false

	func is_wrecked() -> bool:
		return wrecked


class _BlastDummy extends Node3D:
	var taken := 0.0
	var reflected := 0.0

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

	func receive_reflected_damage(amount: float, _source_peer: int) -> void:
		reflected += amount


class _MissileDummy extends Node3D:
	var taken := 0.0

	func _ready() -> void:
		add_to_group(CrawlerMob.GROUP)
		add_to_group(DamageHit.COMBATANT_GROUP)

	func apply_damage(hit: DamageHit) -> float:
		var amount := float(hit.amount) if hit != null else 0.0
		taken += amount
		return amount

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.55

	func combat_faction() -> int:
		return DamageHit.Faction.ENEMY

	func is_alive() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_charmed() -> bool:
		return false


class _StartPadWorld extends GameWorld:
	func _crawler_start_transform() -> Transform3D:
		return Transform3D(Basis.IDENTITY, Vector3(10.0, 20.0, 30.0))


class _HuntDummy extends Node3D:
	var taken := 0.0
	var look := Vector3.FORWARD
	var speed := 0.0
	var velocity := Vector3.ZERO
	var last_hit: DamageHit

	func apply_damage(hit: DamageHit) -> float:
		var amount := float(hit.amount) if hit != null else 0.0
		taken += amount
		last_hit = hit
		return amount

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.4

	func combat_peer_id() -> int:
		return 1

	func combat_faction() -> int:
		return DamageHit.Faction.PLAYER

	func is_dead() -> bool:
		return false

	func look_direction() -> Vector3:
		return look

	func flight_speed() -> float:
		return speed


func _ready() -> void:
	CrawlerRules.glorb_field = false
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
	await _check_site_clear()
	_check_starfire_city_gift()
	_check_heal_and_flash()
	_check_horde_roster()
	_check_mob_sense()
	_check_mob_director()
	await _check_demons()
	_check_run_field_packs()
	await _check_robots()
	await _check_aliens()
	await _check_goblins()
	await _check_idle_roam()
	await _check_enemy_presence()
	await _check_crawler_bursts()
	_check_flight_and_parry()
	_check_hud()
	_check_progress()
	await _check_level_burst()
	await _check_achievement_burst()
	await _check_city_store()
	await _check_reststop()
	await _check_game_menu_items()
	await _check_crawler_death()
	await _check_monument_collision()
	await _check_tidekin_office()
	_check_building_foundation()
	_check_building_flora()
	await _check_monument_quests()
	await _check_nearest_quest_marks()
	await _check_tilde_city_waypoint()
	await _check_waypoint_reveal()
	await _check_entering_sites()
	await _check_crawler_statues()
	_check_roar_shockwaves()
	_check_fields()
	_check_linger()
	_check_elemental_mods()
	_check_multi_shot()
	_check_reach()
	_check_bounce()
	_check_impact_cast()
	_check_homing()

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
	_expect(CrawlerRules.START_PATCH == "Tide Margin 4",
		"Relay 07 stays on the Tide Margin 4 rest cell")
	_expect(CrawlerRules.reserved_patch("Tide Margin 4"), "start patch is reserved")
	_expect(not CrawlerRules.reserved_patch("Tide Margin"),
		"other Tide Margin patches can hold monsters")
	_expect(CrawlerRules.reserved_patch("Wind Gap 4"),
		"the Wind Gap 4 rest cell holds the second later city")
	_expect(not CrawlerRules.reserved_patch("Wind Gap"),
		"other Wind Gap patches can hold monsters")
	_expect(CrawlerRules.CITY_RING_PUSH > 0.0, "city ring fallback still sits inland")
	_expect(is_equal_approx(CrawlerRules.CITY_LATITUDE_DEG, 0.18)
			and is_equal_approx(CrawlerRules.CITY_LONGITUDE_DEG, 4.78),
		"Neon Fjord sits at 0.18 N, 4.78 E")
	_expect(CrawlerRules.reserved_patch("Quiet Inlet 4"), "city patch is reserved")
	_expect(not CrawlerRules.reserved_patch("Quiet Inlet"),
		"other Quiet Inlet patches can hold monsters")
	_expect(CrawlerRules.reserved_patch("Far Beacon 4 Northwest"),
		"Crescent Market's cell is reserved")
	_expect(not CrawlerRules.reserved_patch("Far Beacon 4"),
		"the Far Beacon 4 rest cell stays the office grounds")
	_expect(CrawlerRules.TOWER_PATCH == "Far Beacon 4",
		"the office tower sits on Far Beacon 4")
	_expect(CrawlerRules.CASTLE_PATCH == "Long Shore 4",
		"the castle sits on Long Shore 4")
	_expect(not CrawlerRules.WILD_KINDS.has("gruk")
			and not CrawlerRules.WILD_KINDS.has("nix")
			and not CrawlerRules.WILD_KINDS.has("vex")
			and not CrawlerRules.WILD_KINDS.has("gloam")
			and not CrawlerRules.WILD_KINDS.has("vesper")
			and not CrawlerRules.WILD_KINDS.has("threnody")
			and not CrawlerRules.WILD_KINDS.has("kestrel")
			and not CrawlerRules.WILD_KINDS.has("bastion")
			and not CrawlerRules.WILD_KINDS.has("weaver")
			and not CrawlerRules.WILD_KINDS.has("scout")
			and not CrawlerRules.WILD_KINDS.has("gray")
			and not CrawlerRules.WILD_KINDS.has("tanglemaw"),
		"goblins, demons, robots, and aliens are not part of the roaming field pack")
	_expect(CrawlerRules.patch_combo("Salt Prairie") == CrawlerRules.PATCH_COMBO_WILD
			and CrawlerRules.patch_combo(CrawlerRules.CITY_PATCH)
				== CrawlerRules.PATCH_COMBO_DEMON
			and CrawlerRules.patch_combo(CrawlerRules.CASTLE_PATCH)
				== CrawlerRules.PATCH_COMBO_GOBLIN
			and CrawlerRules.patch_combo(CrawlerRules.TOWER_PATCH)
				== CrawlerRules.PATCH_COMBO_ROBOT,
		"each tile fields one combo: wild, demons, robots, aliens, or goblins")
	_expect(CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_WILD, "ranger")
			and CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_DEMON, "gloam")
			and CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ROBOT, "kestrel")
			and CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ALIEN, "scout")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ROBOT, "gloam")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_DEMON, "kestrel")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_WILD, "kestrel")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_WILD, "vesper")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_WILD, "scout")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ALIEN, "ranger")
			and CrawlerRules.same_patch_combo(
				CrawlerRules.TOWER_PATCH, "Far Beacon 4 Plaza")
			and not CrawlerRules.same_patch_combo(
				CrawlerRules.TOWER_PATCH, CrawlerRules.CITY_PATCH),
		"robots, demons, aliens, and wilds stay on their own three-kind sets")
	_expect(CrawlerRules.field_kinds(CrawlerRules.TOWER_PATCH).has("weaver")
			and not CrawlerRules.field_kinds(CrawlerRules.TOWER_PATCH).has("gloam")
			and CrawlerRules.field_kinds(CrawlerRules.CITY_PATCH).has("threnody")
			and not CrawlerRules.field_kinds(CrawlerRules.CITY_PATCH).has("bastion"),
		"the office ring cannot roll demons, and the inlet cannot roll robots")
	_expect(not CrawlerMobs.kinds_for("Long Shore 4").has("gruk")
			and not CrawlerMobs.kinds_for("Salt Prairie").has("vex")
			and CrawlerMobs.kinds_for("Long Shore 4").is_empty(),
		"field patches do not roll goblins, and the castle has no patch combo")
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
	_expect(is_equal_approx(CrawlerMobs.number("ranger", 2, "health", 0.0),
			CrawlerMobs.number("ranger", 1, "health", 0.0) * 1.25)
			and is_equal_approx(CrawlerMobs.number("ranger", 3, "health", 0.0),
				CrawlerMobs.number("ranger", 1, "health", 0.0) * 1.5),
		"each later ring adds about 25% of the level-1 stats")
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
	_expect(not CrawlerRules.safe_patch("Wind Gap 4"),
		"the Wind Gap 4 city tile still fields mobs outside the ring")
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
	_expect(CrawlerRules.spawn_preview_range(80.0).x
			> CrawlerRules.spawn_lead_range(80.0).y,
		"preview homes sit past the live lead pack")
	_expect(CrawlerRules.spawn_preview_range(80.0).y
			< CrawlerRules.WILD_STREAM_OUT,
		"preview homes stay inside stream-out")
	_expect(CrawlerRules.spawn_stream_range(80.0).y
			> CrawlerRules.spawn_lead_range(80.0).y
			and CrawlerRules.spawn_stream_range(0.0)
				== CrawlerRules.spawn_lead_range(0.0),
		"fast travel uses the longer preview corridor")
	_expect(CrawlerRules.spawn_ready_count(80.0)
			> CrawlerRules.spawn_ready_count(0.0),
		"fast travel stocks more precomputed homes")
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
	_expect(CrawlerRules.spawn_is_agro(12) and not CrawlerRules.spawn_is_agro(13),
		"a rare field home arrives already hunting")
	_expect(CrawlerRules.RING_FILL_PER_TICK >= 2
			and CrawlerRules.HORDE_SEPARATION > 2.0,
		"the horde keeps a player ring and separates without physics pairs")
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
	_expect(flyer.flyer_ceiling() >= CrawlerRules.flyer_ceiling(1)
			and flyer.flyer_ceiling() < CrawlerRules.flyer_ceiling(4),
		"first-patch flyers keep a lower ceiling than late tiles")
	horde._note_kill(Vector3(4.0, 8.0, 0.0))
	_expect(horde._kill_blocks(Vector3(10.0, 8.0, 0.0)),
		"the horde keeps the kill pad empty")
	_expect(not horde._kill_blocks(Vector3(80.0, 8.0, 0.0)),
		"a kill does not lock the far field")
	flyer.set_threat_level(4)
	_expect(flyer.flyer_ceiling() > CrawlerRules.flyer_ceiling(1),
		"harder flyers are allowed higher")
	flyer.chase = true
	flyer.ever_chased = true
	flyer.idle_seconds = 4.0
	flyer.recycle_to(Vector3(0.0, 24.0, 12.0))
	_expect(not flyer.chase and not flyer.ever_chased
			and flyer.hang_origin.z > 10.0,
		"recycling a body drops agro and parks it on the new pad")
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
	_expect(_player.can_edit_crawler_mods(), "safe boxes allow remoding")
	_expect(_has_safe_zone_row(_player), "safe boxes show the Safe Zone buff")
	_expect(_safe_zone_chip_visible(_player),
		"the Safe Zone chip sits on the combat HUD")
	_expect(not _player.can_attack(), "abilities are blocked inside the box")
	_expect_safe_zone_dance("inside the box")
	_player.global_position = Vector3(80.0, 0.0, 0.0)
	_expect(not _player.in_crawler_safe_zone(), "leaving the volume ends the shelter")
	_expect(not _player.can_edit_crawler_mods(), "the field locks ability mods")
	_expect(not _has_safe_zone_row(_player), "the buff leaves with the box")
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
	_expect(CrawlerRules.city_waypoint_tint(1).is_equal_approx(
			CrawlerRules.CITY_WAYPOINT_YELLOW),
		"level 1 city waypoints stay yellow")
	var hot := CrawlerRules.city_waypoint_tint(CrawlerRules.CITY_WAYPOINT_LEVEL_MAX)
	_expect(hot.is_equal_approx(CrawlerRules.CITY_WAYPOINT_RED)
			and hot.g < CrawlerRules.CITY_WAYPOINT_YELLOW.g,
		"high-level city waypoints go bright red")
	_expect(CrawlerRules.city_waypoint_tint(4).g
			< CrawlerRules.city_waypoint_tint(2).g,
		"city waypoints get redder as the tile level rises")
	_expect(city_mark != null and city_mark.tint.is_equal_approx(
			CrawlerRules.CITY_WAYPOINT_YELLOW),
		"Neon Fjord's waypoint is the level 1 yellow")
	_expect(CrawlerRules.OFFICE_WAYPOINT_TINT.b
			> CrawlerRules.OFFICE_WAYPOINT_TINT.r,
		"office waypoints are blue")
	_expect(CrawlerRules.CASTLE_WAYPOINT_TINT.r
			> CrawlerRules.CASTLE_WAYPOINT_TINT.g
			and CrawlerRules.CASTLE_WAYPOINT_TINT.get_luminance()
			< CrawlerRules.CITY_WAYPOINT_RED.get_luminance(),
		"castle waypoints are dark red")
	_expect(CrawlerRules.BOSS_WAYPOINT_TINT.b
			> CrawlerRules.BOSS_WAYPOINT_TINT.g
			and CrawlerRules.BOSS_WAYPOINT_TINT.r
			> CrawlerRules.BOSS_WAYPOINT_TINT.g
			and CrawlerRules.BOSS_WAYPOINT_TINT.get_luminance()
			< CrawlerRules.CITY_WAYPOINT_YELLOW.get_luminance()
			and is_equal_approx(CrawlerRules.BOSS_SITE_RADIUS, 100.0),
		"boss waypoints are dark purple 100 m circles")
	_expect(CrawlerAdobeSite.city_ready(),
		"adobe village buildings are ready to seat on the ring")
	_player.global_position = Vector3(300.0, 0.0, 0.0)
	_press_interact(_player)
	await get_tree().process_frame
	_expect(_player.hud.get_node_or_null("CrawlerFieldMenu") == null,
		"E does not open a menu outside the city")
	_player.global_position = Vector3.ZERO
	_expect(_player.in_crawler_city(), "standing in the ring is being in the city")
	_expect(_player.can_edit_crawler_mods(), "cities allow remoding")
	_expect(_has_safe_zone_row(_player), "cities show the Safe Zone buff")
	_expect(_safe_zone_chip_visible(_player),
		"the city Safe Zone chip sits on the combat HUD")
	var page := CrawlerHeroPage.new()
	page.configure(_player)
	add_child(page)
	await get_tree().process_frame
	page.refresh()
	var eyes := page.find_child("CrawlerAbilityTile_0", true, false) as CrawlerAbilityTile
	_expect(eyes != null and not eyes.mod_slots().is_empty()
			and eyes.mod_slots()[0].draggable
			and eyes.mod_slots()[0].accepts_drops,
		"cities unlock ability mod slots")
	page.queue_free()
	_expect(not _player.can_attack(), "the ring locks abilities")
	_expect_safe_zone_dance("inside the city")
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
	_expect(_player.can_attack(), "abilities return outside the city")
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


func _check_site_clear() -> void:
	_expect(CrawlerRules.SITE_CLEAR_RADIUS == 100.0
			and CrawlerRules.START_FLORA_RADIUS == 1.0,
		"sites keep a 100 m circle; the teleporter keeps 1 m of flora")
	var flora_id := "site_clear_flora"
	BuildingFloraClear.unregister(flora_id)
	var pole := Vector3.RIGHT
	var inside := (Vector3.RIGHT * 8000.0 + Vector3.UP * 90.0).normalized()
	var outside := (Vector3.RIGHT * 8000.0 + Vector3.UP * 110.0).normalized()
	BuildingFloraClear.register(flora_id, pole, CrawlerRules.SITE_CLEAR_RADIUS, 8000.0, 0.0)
	_expect(BuildingFloraClear.covers(inside)
			and not BuildingFloraClear.covers(outside),
		"site flora uses an exact 100 m circle")
	BuildingFloraClear.unregister(flora_id)
	BuildingFloraClear.register(flora_id, pole, CrawlerRules.START_FLORA_RADIUS, 8000.0, 0.0)
	var start_inside := (Vector3.RIGHT * 8000.0 + Vector3.UP * 0.4).normalized()
	var start_outside := (Vector3.RIGHT * 8000.0 + Vector3.UP * 4.0).normalized()
	_expect(BuildingFloraClear.covers(start_inside)
			and not BuildingFloraClear.covers(start_outside),
		"the teleporter only clears 1 m of flora")
	BuildingFloraClear.unregister(flora_id)

	var ring = CITY_RING.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	await get_tree().process_frame
	var rim := Vector3(98.0, 2.0, 0.0)
	var wall := Vector3(160.0, 2.0, 0.0)
	var far := Vector3(400.0, 2.0, 0.0)
	_expect(not ring.contains_point(rim) and ring.in_site_clear(rim),
		"the 100 m site circle sits just outside the city walls")
	_player.global_position = Vector3.ZERO
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(ring.clears_patch_mobs_at(rim) and MOB_SENSE.keepout_blocks(ring, rim),
		"a solo player in the city despawns patch mobs in 100 m")
	_expect(ring.clears_patch_mobs_at(wall) and not ring.clears_patch_mobs_at(far),
		"the 100 m site circle still stops short of the far field")

	var solo := CrawlerHorde.new()
	add_child(solo)
	solo.set_process(false)
	var near_solo := solo.spawn_test_mob("ranger", wall, false)
	var far_solo := solo.spawn_test_mob("ranger", far, false)
	near_solo.set_physics_process(false)
	far_solo.set_physics_process(false)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(solo.should_clear_all_field(),
		"a solo player in the city clears the whole field")
	solo.call("_clear_site_patch_mobs")
	_expect(not is_instance_valid(near_solo) or near_solo.dismissed,
		"a solo city visit clears the wall pack")
	_expect(not is_instance_valid(far_solo) or far_solo.dismissed,
		"a solo city visit despawns the field everywhere")
	solo.queue_free()

	var mate := Node3D.new()
	mate.name = "CoopMate"
	add_child(mate)
	mate.add_to_group("network_players")
	mate.global_position = Vector3(400.0, 0.0, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(not CrawlerRules.all_players_inside_city(MOB_SENSE.players(), ring),
		"coop is split when a partner is still in the field")
	_expect(ring.clears_patch_mobs_at(rim, MOB_SENSE.players())
			and ring.clears_patch_mobs_at(wall, MOB_SENSE.players())
			and MOB_SENSE.keepout_blocks(ring, rim),
		"entering the city still clears the wall pack while a partner is outside")
	_expect(ring.clears_patch_mobs_at(Vector3.ZERO, MOB_SENSE.players()),
		"the plaza still stays clear while one player shops")
	_expect(not ring.clears_patch_mobs_at(far, MOB_SENSE.players()),
		"a partner still fighting far out keeps that pack")

	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	var rim_mob := horde.spawn_test_mob("ranger", rim, false)
	var wall_mob := horde.spawn_test_mob("ranger", wall, true)
	var plaza_mob := horde.spawn_test_mob("ranger", Vector3(8.0, 2.0, 0.0), false)
	var far_mob := horde.spawn_test_mob("ranger", far, false)
	rim_mob.set_physics_process(false)
	wall_mob.set_physics_process(false)
	plaza_mob.set_physics_process(false)
	far_mob.set_physics_process(false)
	horde.call("_clear_site_patch_mobs")
	_expect(not is_instance_valid(rim_mob) or rim_mob.dismissed,
		"the wall pack despawns when you reach the city")
	_expect(not is_instance_valid(wall_mob) or wall_mob.dismissed,
		"mobs at the border despawn with the arriving player")
	_expect(not is_instance_valid(plaza_mob) or plaza_mob.dismissed,
		"mobs that followed into the plaza still despawn")
	_expect(is_instance_valid(far_mob) and not far_mob.dismissed,
		"the far field stays up while a partner is still outside")
	_player.global_position = Vector3(130.0, 2.0, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	var gate_mob := horde.spawn_test_mob("ranger", Vector3(170.0, 2.0, 0.0), true)
	gate_mob.set_physics_process(false)
	horde.call("_clear_site_patch_mobs")
	_expect(not is_instance_valid(gate_mob) or gate_mob.dismissed,
		"crossing the city border clears the mobs around you")
	_player.global_position = Vector3.ZERO

	var office := PatchMonument.new()
	office.monument_id = CrawlerProgress.QUEST_TOWER
	office.position = Vector3(800.0, 0.0, 0.0)
	add_child(office)
	await get_tree().process_frame
	var office_mob := horde.spawn_test_mob("ranger", Vector3(860.0, 0.0, 0.0), false)
	var office_far := horde.spawn_test_mob("ranger", Vector3(930.0, 0.0, 0.0), false)
	office_mob.set_physics_process(false)
	office_far.set_physics_process(false)
	horde.call("_clear_site_patch_mobs")
	_expect(not is_instance_valid(office_mob) or office_mob.dismissed,
		"offices despawn patch mobs in 100 m")
	_expect(is_instance_valid(office_far) and not office_far.dismissed,
		"patch mobs past 100 m of an office stay in the field")
	_expect(not horde._home_clear(Vector3(860.0, 0.0, 0.0), "ranger"),
		"offices do not field a new pack inside 100 m")

	var pad := CrawlerSpawnPad.new()
	pad.position = Vector3(1200.0, 0.0, 0.0)
	add_child(pad)
	await get_tree().process_frame
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(pad.holds_field() and horde.call("_arrival_holds"),
		"the teleporter holds the field until you step off")
	_expect(not MOB_SENSE.keepout_blocks(pad, pad.global_position)
			and not pad.blocks_near(pad.global_position),
		"the teleporter does not despawn patch mobs")
	var hunter := CrawlerRanger.new()
	hunter.configure(
		"pad_agro",
		Transform3D(Basis(), pad.global_position + Vector3(8.0, 2.0, 0.0)),
		1, true)
	add_child(hunter)
	hunter.set_physics_process(false)
	var saved_pad_at := _player.global_position
	_player.global_position = pad.global_position + Vector3(0.0, 1.5, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(MOB_SENSE.player_on_spawn_pad(_player)
			and pad.holds_standing(_player.global_position)
			and horde.call("_arrival_holds"),
		"standing on the teleporter holds the field")
	hunter.chase = false
	_expect(not hunter.tick_agro(_player, 0.16) and not hunter.chase,
		"mobs do not agro a player on the teleporter")
	_player.global_position = pad.global_position + Vector3(14.0, 1.5, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(not pad.holds_field() and not horde.call("_arrival_holds")
			and not MOB_SENSE.player_on_spawn_pad(_player),
		"walking off the teleporter opens the field")
	_expect(hunter.tick_agro(_player, 0.16) and hunter.chase,
		"mobs agro once the player steps off the teleporter")
	_player.global_position = pad.global_position + Vector3(0.0, 1.5, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(not MOB_SENSE.player_on_spawn_pad(_player)
			and pad.holds_standing(_player.global_position),
		"the open teleporter is no longer a site")
	_expect(hunter.tick_agro(_player, 0.16) and hunter.chase,
		"mobs keep agro after they enter the teleporter")
	var deck_mob := horde.spawn_test_mob(
		"ranger", pad.global_position + Vector3(2.0, 1.5, 0.0), false)
	deck_mob.set_physics_process(false)
	horde.call("_clear_site_patch_mobs")
	_expect(is_instance_valid(deck_mob) and not deck_mob.dismissed
			and horde._home_clear(pad.global_position + Vector3(2.0, 1.5, 0.0), "ranger"),
		"mobs on the open teleporter stay in the field")
	_player.global_position = Vector3.ZERO
	mate.global_position = Vector3.ZERO
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	var leftover := horde.spawn_test_mob("ranger", far, false)
	leftover.set_physics_process(false)
	_expect(horde.should_clear_all_field(),
		"the whole party in the city clears the field")
	horde.call("_clear_site_patch_mobs")
	_expect(not is_instance_valid(leftover) or leftover.dismissed,
		"the field despawns everywhere once the whole party is in the city")
	_player.global_position = saved_pad_at
	hunter.queue_free()
	mate.queue_free()
	office.queue_free()
	pad.queue_free()
	horde.queue_free()
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
	var owner := _player.get_instance_id()
	_player.velocity = Vector3(80.0, 0.0, 0.0)
	horde._ready_homes.clear()
	horde._ready_homes.append({"at": Vector3(-200.0, 0.0, 0.0), "owner": owner})
	var missed := horde._take_ready_home(_player, null, false)
	_expect(not missed.is_finite(), "homes behind travel are not used")
	horde._ready_homes.clear()
	horde._ready_homes.append({"at": Vector3(320.0, 0.0, 0.0), "owner": owner})
	var taken := horde._take_ready_home(_player, null, false)
	_expect(taken.is_equal_approx(Vector3(320.0, 0.0, 0.0))
			and horde._ready_homes.is_empty(),
		"ahead fill uses a precomputed home")
	_player.velocity = Vector3.ZERO
	horde.queue_free()


func _check_mob_sense() -> void:
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(MOB_SENSE.players().has(_player),
		"the targeting board caches the live player once a frame")
	var horde := CrawlerHorde.new()
	add_child(horde)
	var ranger := horde.spawn_test_mob("ranger", Vector3(8.0, 12.0, 0.0), false)
	MOB_SENSE.invalidate()
	_expect(ranger.call("_nearest_player") == _player,
		"a ranger still finds the player through the shared board")
	_expect(MOB_SENSE.charmed_count() == 0
			and ranger.call("_nearest_charmed_mob") == null,
		"an empty charm list skips the O(n) bait scan")
	_expect(is_equal_approx(MOB_SENSE.field_slow(ranger, ranger.global_position), 1.0),
		"no fields means no extra group walk for slow")
	_expect(CrawlerRules.patch_recipe(CrawlerRules.START_PATCH)["kinds"].has("ranger"),
		"targeting cache does not change the field roster")
	var box := CrawlerSafeBox.new()
	box.configure(99, Transform3D.IDENTITY)
	add_child(box)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	box.free()
	ranger.call("_keep_out_of_safe_zones")
	_expect(is_equal_approx(MOB_SENSE.field_slow(ranger, ranger.global_position), 1.0)
			and ranger.call("_nearest_player") == _player,
		"a freed keep-out zone does not crash targeting")
	horde.queue_free()


func _check_mob_director() -> void:
	_expect(CrawlerRules.mob_lod(20.0) == CrawlerRules.MOB_LOD_HOT
			and CrawlerRules.mob_lod(50.0) == CrawlerRules.MOB_LOD_WARM
			and CrawlerRules.mob_lod(200.0) == CrawlerRules.MOB_LOD_COLD,
		"mobs drop from unique AI to a cheap coast as they get farther")
	_expect(CrawlerRules.MOB_SPAWN_BUILD < CrawlerHorde.SPAWN_PER_FRAME
			and CrawlerRules.MOB_SPAWN_QUEUE >= 64
			and CrawlerRules.MOB_THINK_BUDGET > 0
			and CrawlerRules.MOB_ATTACK_BUDGET > 0
			and CrawlerRules.think_budget_for(0) == CrawlerRules.MOB_THINK_BUDGET
			and CrawlerRules.think_budget_for(40) == 4
			and CrawlerRules.attack_budget_for(24) == 1,
		"the horde drips instantiates and shrinks unique thinks in a pile-up")
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	var thinks := 0
	for _step in CrawlerRules.MOB_THINK_BUDGET + 4:
		if MOB_SENSE.take_think(null, true):
			thinks += 1
	_expect(thinks == CrawlerRules.MOB_THINK_BUDGET,
		"a physics frame only runs a budget of unique attack planners")
	var think_board: Dictionary = MOB_SENSE.director_counts()
	_expect(int(think_board.get("think_ok", 0)) == CrawlerRules.MOB_THINK_BUDGET
			and int(think_board.get("think_denied", 0)) >= 4,
		"the director log counts granted and denied thinks")
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	var shots := 0
	for _step in CrawlerRules.MOB_ATTACK_BUDGET + 3:
		if MOB_SENSE.take_attack("ranger"):
			shots += 1
	_expect(shots == CrawlerRules.MOB_ATTACK_BUDGET,
		"a physics frame only starts a few new attacks")
	var shot_board: Dictionary = MOB_SENSE.director_counts()
	_expect(int(shot_board.get("attack_ok", 0)) == CrawlerRules.MOB_ATTACK_BUDGET
			and int(shot_board.get("attack_denied", 0)) >= 3,
		"the director log counts granted and denied shots")
	var horde := CrawlerHorde.new()
	add_child(horde)
	_player.global_position = Vector3.ZERO
	var near := horde.spawn_test_mob("ranger", Vector3(8.0, 4.0, 0.0), true)
	var far := horde.spawn_test_mob("ranger", Vector3(240.0, 4.0, 0.0), false)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(MOB_SENSE.lod_of(near) == CrawlerRules.MOB_LOD_HOT
			and MOB_SENSE.lod_of(far) == CrawlerRules.MOB_LOD_COLD,
		"the director keeps nearby unique AI and sleeps the far field")
	var pile_board: Dictionary = MOB_SENSE.director_counts()
	_expect(int(pile_board.get("pile", 0)) >= 1
			and pile_board.has("phys_pairs")
			and pile_board.has("phys_bodies"),
		"the director log counts mobs whose hit boxes overlap the player")
	_expect(horde.queued_spawn_count() == 0, "test spawns are immediate")
	var queued := horde._enqueue_wild(
		"ranger", Vector3(80.0, 8.0, 0.0), 1, -1, 1.0)
	_expect(queued == 1 and horde.queued_spawn_count() == 1
			and horde.wild_live_count() == 2,
		"field fill queues a home instead of instantiating it this frame")
	horde._drain_builds()
	_expect(horde.queued_spawn_count() == 0 and horde.wild_live_count() == 3,
		"the horde drips queued homes across later frames")
	var armed := horde.fill_test_patch(
		7, [Vector3(90.0, 8.0, 0.0), Vector3(96.0, 8.0, 0.0)], "ranger", 1)
	_expect(armed == 2 and horde.is_patch_armed(7)
			and horde.queued_spawn_count() == 2,
		"entering a patch queues the whole cell instead of dripping as you walk")
	_expect(horde.fill_test_patch(7, [Vector3(102.0, 8.0, 0.0)], "ranger", 1) == 0
			and horde.queued_spawn_count() == 2,
		"a patch already armed does not queue more homes")
	var land := LandPartition.new()
	_expect(land.neighbors_of(0).is_empty()
			and land.cell_directions_of(0).is_empty(),
		"an empty partition exposes neighbour and cell-direction lookups")
	horde.queue_free()


func _check_demons() -> void:
	CrawlerMobs.reload()
	_expect(not CrawlerMobs.kinds_for(CrawlerRules.START_PATCH).has("gloam")
			and not CrawlerMobs.kinds_for(CrawlerRules.START_PATCH).has("vesper")
			and not CrawlerMobs.kinds_for(CrawlerRules.START_PATCH).has("threnody"),
		"the start pad fields no demons")
	_expect(not CrawlerMobs.kinds_for(
				CrawlerRules.START_PATCH, CrawlerRules.START_NEAR_RANGE + 1.0)
			.has("vesper")
			and not CrawlerMobs.kinds_for(
				CrawlerRules.START_PATCH, CrawlerRules.START_NEAR_RANGE + 1.0)
			.has("gloam")
			and not CrawlerMobs.kinds_for(
				CrawlerRules.START_PATCH, CrawlerRules.START_NEAR_RANGE + 1.0)
			.has("threnody"),
		"demons stay off the start tile even farther from the pad")
	_expect(CrawlerMobs.kinds_for(CrawlerRules.CITY_PATCH).has("gloam")
			and CrawlerMobs.kinds_for(CrawlerRules.CITY_PATCH).has("vesper")
			and CrawlerMobs.kinds_for(CrawlerRules.CITY_PATCH).has("threnody")
			and CrawlerMobs.kinds_for(CrawlerRules.DEMON_START_SE_PATCH).has("gloam")
			and CrawlerMobs.kinds_for(CrawlerRules.DEMON_START_SE_PATCH).has("vesper")
			and not CrawlerMobs.kinds_for("Salt Prairie").has("threnody")
			and not CrawlerMobs.kinds_for("Salt Prairie").has("gloam"),
		"demons start on Quiet Inlet 4 and Quiet Inlet 4 Southeast")
	_expect(not CrawlerMobs.kinds_for(CrawlerRules.CITY_PATCH).has("ranger")
			and not CrawlerMobs.kinds_for(CrawlerRules.CITY_PATCH).has("rhino")
			and not CrawlerMobs.kinds_for(CrawlerRules.TOWER_PATCH).has("rammer")
			and not CrawlerMobs.kinds_for(CrawlerRules.TOWER_PATCH).has("gloam")
			and CrawlerMobs.kinds_for(CrawlerRules.CASTLE_PATCH).is_empty()
			and CrawlerMobs.kinds_for("Long Shore 4 Keep").is_empty(),
		"demon tiles field only demons, and the castle fields none")
	_expect(CrawlerRules.demon_start_grounds(CrawlerRules.CITY_PATCH)
			and CrawlerRules.demon_start_grounds(CrawlerRules.DEMON_START_SE_PATCH)
			and CrawlerRules.demon_grounds(CrawlerRules.CITY_PATCH)
			and CrawlerRules.demon_grounds(CrawlerRules.DEMON_START_SE_PATCH)
			and not CrawlerRules.demon_start_grounds("Quiet Inlet 4 North")
			and not CrawlerRules.demon_grounds("Quiet Inlet 4 North")
			and not CrawlerRules.demon_grounds(CrawlerRules.CASTLE_PATCH)
			and CrawlerRules.castle_grounds(CrawlerRules.CASTLE_PATCH)
			and CrawlerRules.castle_grounds("Long Shore 4 Keep")
			and not CrawlerRules.demon_grounds(CrawlerRules.TOWER_PATCH)
			and not CrawlerRules.demon_grounds("Far Beacon 4 Plaza")
			and not CrawlerRules.demon_grounds(CrawlerRules.START_PATCH)
			and CrawlerRules.opening_route_patch("Tide Margin 4 North")
			and CrawlerRules.opening_route_patch(CrawlerRules.CITY_PATCH)
			and not CrawlerRules.can_field_demons(CrawlerRules.START_PATCH)
			and CrawlerRules.can_field_demons(CrawlerRules.CITY_PATCH)
			and CrawlerRules.can_field_demons(CrawlerRules.DEMON_START_SE_PATCH)
			and not CrawlerRules.can_field_demons("Quiet Inlet 4 North")
			and not CrawlerRules.can_field_demons("Salt Prairie")
			and not CrawlerRules.can_field_demons(CrawlerRules.CASTLE_PATCH)
			and not CrawlerRules.can_field_demons(CrawlerRules.TOWER_PATCH)
			and CrawlerRules.CASTLE_KEEP_RANGE > CrawlerRules.GOBLIN_OUTER_MAX,
		"demons start on the first-city inlet tiles")
	_expect(CrawlerRules.kind_cap("threnody", 1) == 1
			and CrawlerRules.kind_cap("threnody", 4) == 1,
		"only one Threnody can live on a tile")
	_expect(CrawlerRules.spawn_weight("gloam") > CrawlerRules.spawn_weight("vesper")
			and CrawlerRules.spawn_weight("vesper") > CrawlerRules.spawn_weight("threnody")
			and CrawlerMobs.kind_cap("gloam", 1) >= 48
			and CrawlerRules.GLOAM_FLOCK >= 16,
		"Gloam flocks swarm the inlet")
	_expect(CrawlerMobs.number("gloam", 3, "health", 0.0)
			> CrawlerMobs.number("gloam", 1, "health", 0.0)
			and CrawlerMobs.number("vesper", 3, "damage", 0.0)
			> CrawlerMobs.number("vesper", 1, "damage", 0.0)
			and CrawlerMobs.number("threnody", 3, "damage", 0.0)
			> CrawlerMobs.number("threnody", 1, "damage", 0.0),
		"demon stats scale with level")
	_expect(CrawlerMobs.attack_mode("gloam", 1) == "bite"
			and CrawlerMobs.attack_mode("vesper", 1) == "beam"
			and CrawlerMobs.attack_mode("threnody", 1) == "column",
		"each demon has its own attack")
	_expect(CrawlerMobs.attack_mode("ranger", 1) == "standoff",
		"rangers still lob from a standoff, not a beam")

	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set("_start_origin", Vector3.ZERO)
	var at_pad: String = horde.call(
		"_pick_kind", Vector3.ZERO, CrawlerRules.START_PATCH, 0.0, 1)
	_expect(not CrawlerRules.patch_recipe(CrawlerRules.START_PATCH, 0.0)["kinds"].has("vesper")
			and not CrawlerRules.patch_recipe(CrawlerRules.START_PATCH, 0.0)["kinds"].has("gloam")
			and not CrawlerRules.GOBLIN_KINDS.has(at_pad)
			and (at_pad == "" or CrawlerRules.START_NEAR_KINDS.has(at_pad)),
		"while the player is on the pad, homes 90m out still roll the near roster")
	_expect(not CrawlerRules.patch_recipe(
				CrawlerRules.START_PATCH, CrawlerRules.SPAWN_MIN)["kinds"].has("vesper")
			and not CrawlerRules.patch_recipe(
				CrawlerRules.START_PATCH, CrawlerRules.SPAWN_MIN)["kinds"].has("gloam")
			and not CrawlerRules.field_kinds(
				CrawlerRules.START_PATCH, CrawlerRules.SPAWN_MIN, Vector3.ZERO)
			.has("vesper"),
		"a home-distance check still cannot unlock demons at the pad")
	var at_castle: String = horde.call(
		"_pick_kind", Vector3.ZERO, CrawlerRules.CASTLE_PATCH, 400.0, 1)
	var at_city: String = horde.call(
		"_pick_kind", Vector3.ZERO, CrawlerRules.CITY_PATCH, 400.0, 1)
	_expect(CrawlerRules.field_kinds(CrawlerRules.CITY_PATCH).has("vesper")
			and CrawlerRules.field_kinds(CrawlerRules.DEMON_START_SE_PATCH)
				.has("threnody")
			and not CrawlerRules.field_kinds("Quiet Inlet 4 North").has("gloam")
			and CrawlerRules.DEMON_KINDS.has(at_city),
		"the first-city inlet tiles can roll the demon roster")
	_expect(at_castle.is_empty()
			and CrawlerRules.field_kinds(CrawlerRules.CASTLE_PATCH).is_empty()
			and CrawlerRules.field_kinds(CrawlerRules.TOWER_PATCH).has("kestrel"),
		"castle grounds do not roll a patch combo")
	var castle_mark := PatchMonument.new()
	castle_mark.monument_id = CrawlerProgress.QUEST_CASTLE
	add_child(castle_mark)
	castle_mark.global_position = Vector3(0.0, 0.0, 0.0)
	_expect(CrawlerRules.in_castle_keep(Vector3(120.0, 0.0, 0.0))
			and not CrawlerRules.in_castle_keep(
				Vector3(CrawlerRules.CASTLE_KEEP_RANGE + 40.0, 0.0, 0.0))
			and CrawlerRules.field_kinds(
				CrawlerRules.CASTLE_PATCH, -1.0, Vector3(80.0, 0.0, 0.0))
				.is_empty()
			and CrawlerRules.field_kinds(
				"Salt Prairie", -1.0, Vector3(80.0, 0.0, 0.0)).is_empty()
			and not bool(horde.call(
				"_spawn_point_ok", Vector3(80.0, 0.0, 0.0), _player, null,
				"ranger")),
		"the castle keep does not field patch mobs")
	castle_mark.queue_free()
	var gloam := horde.spawn_test_mob("gloam", Vector3(0.0, 2.0, 0.0), false, 1)
	_expect(gloam != null and gloam.wild_kind() == "gloam" and not gloam.flies(),
		"Gloam spawns on the ground")
	var vesper := horde.spawn_test_mob("vesper", Vector3(8.0, 16.0, 0.0), false, 1)
	_expect(vesper != null and vesper.wild_kind() == "vesper" and vesper.flies(),
		"Vesper spawns flying")
	var threnody := horde.spawn_test_mob("threnody", Vector3(-8.0, 22.0, 0.0), false, 1)
	_expect(threnody != null and threnody.wild_kind() == "threnody",
		"the horde can spawn a Threnody")
	_expect(threnody.combat_radius() > vesper.combat_radius()
			and vesper.combat_radius() > gloam.combat_radius(),
		"Threnody is the massive demon")
	_expect(threnody.find_child("CursedAura", true, false) == null
			and threnody.find_child("CursedRays", true, false) == null,
		"Threnody has no transparent glow shafts")
	_expect(_authored_inks(gloam).size() >= 4
			and _has_bright_ink(_authored_inks(gloam))
			and _has_bright_ink(_authored_inks(vesper))
			and _has_bright_ink(_authored_inks(threnody)),
		"demon GLBs keep their Blender material colors")
	_expect(_has_enemy_rim(gloam) and _has_enemy_rim(vesper)
			and _has_enemy_rim(threnody),
		"authored demons wear the red rim outline")
	gloam.set_physics_process(false)
	vesper.set_physics_process(false)
	threnody.set_physics_process(false)
	await get_tree().process_frame

	var biter: CrawlerMob = GLOAM.new()
	biter.configure("biter", Transform3D(Basis.IDENTITY, Vector3.ZERO), 1, true)
	add_child(biter)
	biter.set_physics_process(false)
	biter.set("_planet", null)
	await get_tree().process_frame
	biter.velocity = Vector3.RIGHT * 10.0
	biter.call("_face_motion", 1.0)
	var mouth := _skeleton_bone_at(biter, "socket_mouth")
	var mouth_along := mouth - biter.global_position
	mouth_along.y = 0.0
	_expect(mouth.is_finite() and mouth_along.dot(Vector3.RIGHT) > 0.2,
		"Gloam mouth faces the run and bite direction")
	var animator := biter.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var bite_name := str(biter.call("_resolve_clip", CrawlerMob.CLIP_ATTACK))
	if animator != null and not bite_name.is_empty() \
			and animator.has_animation(bite_name):
		animator.play(bite_name)
		animator.seek(0.55, true)
		await get_tree().process_frame
		mouth = _skeleton_bone_at(biter, "socket_mouth")
		mouth_along = mouth - biter.global_position
		mouth_along.y = 0.0
		_expect(mouth_along.dot(Vector3.RIGHT) > 0.2,
			"Gloam bite lunges toward the target, not behind it")
	biter.queue_free()

	var prey := _HuntDummy.new()
	add_child(prey)
	prey.global_position = gloam.combat_position()
	gloam.call("_bite", prey)
	_expect(prey.taken > 0.0, "Gloam bite damages a close target")
	var bite_clip := gloam.current_clip()
	_expect(bite_clip == CrawlerMob.CLIP_ATTACK or bite_clip == DEMON_BODY.CLIP_FLY,
		"Gloam plays a bite or fly clip")

	prey.taken = 0.0
	prey.speed = 0.0
	prey.velocity = Vector3.ZERO
	prey.global_position = gloam.global_position + Vector3(20.0, 0.0, 0.0)
	gloam.call("_pursue", prey, 0.16, true)
	_expect(not gloam.flies() and gloam.velocity.x > 1.0,
		"a standing player is jogged at on the ground")
	_expect(gloam.move_speed() <= 10.0, "Gloam cannot sprint on foot")
	prey.speed = 16.0
	prey.velocity = Vector3(16.0, 0.0, 0.0)
	gloam.call("_pursue", prey, 0.16, true)
	_expect(gloam.flies(), "Gloam takes off when the player runs")
	_expect(gloam.current_clip() == DEMON_BODY.CLIP_FLY,
		"an airborne Gloam uses the fly clip")
	gloam.call("_chase_air", prey, 0.16)
	_expect(prey.taken == 0.0, "Gloam never bites while flying")

	var lander: CrawlerMob = GLOAM.new()
	lander.configure("land", Transform3D(Basis(), Vector3(0.0, 6.0, 12.0)), 1, true)
	add_child(lander)
	lander.set_physics_process(false)
	await get_tree().process_frame
	lander.call("_takeoff")
	var perch := _HuntDummy.new()
	add_child(perch)
	perch.global_position = Vector3(0.0, 2.0, 0.0)
	perch.look = Vector3(0.0, 0.0, 1.0)
	perch.speed = 16.0
	perch.velocity = Vector3(0.0, 0.0, 16.0)
	var perch_at: Vector3 = lander.call("_land_perch", perch)
	var cut := perch_at - perch.global_position
	cut.y = 0.0
	_expect(cut.dot(perch.look) > 6.0
			and perch_at.distance_to(perch.global_position)
				>= CrawlerRules.GLOAM_LAND_GAP * 0.7,
		"the landing perch is in front of a runner, not in their lap")
	lander.global_position = perch_at
	lander.call("_land")
	_expect(not lander.flies(), "Gloam lands ahead, then runs in to bite")

	var mark := _HuntDummy.new()
	add_child(mark)
	mark.global_position = vesper.global_position + Vector3(0.0, 0.0, 24.0)
	vesper.call("_try_charge", mark)
	_expect(bool(vesper.call("aiming")) and (vesper.call("locked_aim") as Vector3).is_finite(),
		"Vesper locks a beam the moment it starts charging")
	var locked: Vector3 = vesper.call("locked_aim")
	mark.global_position += Vector3(8.0, 0.0, 0.0)
	vesper.call("_draw_beam", 0.2)
	_expect(vesper.get_node("VesperBeam").visible, "the telegraph line is visible while charging")
	var thin := float(vesper.call("charge_share"))
	vesper.set("_aim_left", float(vesper.get("_aim_left")) * 0.25)
	_expect(float(vesper.call("charge_share")) > thin, "the telegraph grows as the beam powers up")
	_expect((vesper.call("locked_aim") as Vector3).is_equal_approx(locked),
		"the beam stays locked where it began charging")
	vesper.set("_aim_left", 0.0)
	vesper.call("_hold_aim", mark, vesper.global_position, 0.02)
	_expect(mark.taken > 0.0, "the finished beam deals damage")
	_expect(not bool(vesper.call("aiming")), "the telegraph clears after the shot")

	var loop_a: Vector3 = threnody.call("infinity_point", PI * 0.5)
	var loop_b: Vector3 = threnody.call("infinity_point", PI * 1.5)
	_expect(loop_a.distance_to(threnody.hang_origin) > 10.0
			and (loop_a - threnody.hang_origin).dot(loop_b - threnody.hang_origin) < 0.0,
		"Threnody patrols an infinity loop around its hang")
	var looker := _HuntDummy.new()
	add_child(looker)
	looker.global_position = Vector3(40.0, 8.0, 40.0)
	looker.look = Vector3(0.0, 0.0, -1.0)
	var station: Vector3 = threnody.call("hold_station", looker)
	var along := station - looker.global_position
	_expect(along.normalized().dot(looker.look) > 0.7
			and station.distance_to(looker.global_position)
			>= CrawlerRules.VESPER_STANDOFF_MAX,
		"Threnody holds far, top-middle of the look")

	var rival: CrawlerMob = THRENODY.new()
	rival.configure("rival", Transform3D(Basis(), Vector3(12.0, 22.0, 4.0)), 1, false)
	add_child(rival)
	var spare: CrawlerMob = THRENODY.new()
	spare.configure("spare", Transform3D(Basis(), Vector3(20.0, 22.0, -6.0)), 1, false)
	add_child(spare)
	var pack := horde.spawn_test_mob("threnody", Vector3(28.0, 22.0, 2.0), false, 1)
	rival.set_physics_process(false)
	spare.set_physics_process(false)
	if pack != null:
		pack.set_physics_process(false)
	await get_tree().process_frame
	threnody.chase = true
	threnody.call("_clear_idle_siblings")
	_expect(spare.dismissed
			and (pack == null or pack.dismissed)
			and (not is_instance_valid(rival) or rival.dismissed),
		"idle Threnodies despawn when one engages")
	threnody.chase = false
	await get_tree().process_frame

	var before := _player.health()
	_player.global_position = Vector3(70.0, 4.0, 0.0)
	await get_tree().process_frame
	var column_at := _player.combat_position()
	var column: Node = DEMON_COLUMN.place(
		self, threnody, column_at,
		7.5, 20.0, 6.0, 28.0)
	_expect(column != null and bool(column.call("contains", column_at, 0.4)),
		"a cursed column stands where Threnody places it")
	if column != null:
		var mesh := column.find_child("ColumnMesh", true, false) as MeshInstance3D
		var film := mesh.material_override as ShaderMaterial if mesh != null else null
		_expect(film != null and film.shader == DEMON_COLUMN.IRIS_SHADER,
			"cursed columns use the static-field iridescent film")
		column.call("tick_now")
		_expect(_player.health() < before
				and _player.statuses.has(CombatStatuses.SHOCK),
			"the column damages and shocks the player")
		column.queue_free()

	prey.queue_free()
	perch.queue_free()
	mark.queue_free()
	looker.queue_free()
	lander.queue_free()
	if is_instance_valid(rival):
		rival.queue_free()
	if is_instance_valid(spare):
		spare.queue_free()
	horde.queue_free()
	_player.statuses.clear(CombatStatuses.SHOCK)
	_player.stats.set_health(_player.maximum_health())
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().process_frame


func _check_robots() -> void:
	CrawlerMobs.reload()
	for kind: String in CrawlerRules.ROBOT_KINDS:
		_expect(ROBOT_MODELS.scene(kind) != null,
			"%s GLB is in the robot pack" % kind)
	_expect(CrawlerRules.robot_grounds(CrawlerRules.TOWER_PATCH)
			and CrawlerRules.robot_grounds("Far Beacon 4 Plaza")
			and not CrawlerRules.robot_grounds(CrawlerRules.CITY_PATCH)
			and CrawlerRules.patch_combo(CrawlerRules.TOWER_PATCH)
				== CrawlerRules.PATCH_COMBO_ROBOT,
		"the office tile is the robot combo")
	_expect(CrawlerMobs.kinds_for(CrawlerRules.TOWER_PATCH).has("kestrel")
			and CrawlerMobs.kinds_for(CrawlerRules.TOWER_PATCH).has("bastion")
			and CrawlerMobs.kinds_for(CrawlerRules.TOWER_PATCH).has("weaver")
			and CrawlerMobs.kinds_for("Far Beacon 4 Plaza").has("weaver")
			and not CrawlerMobs.kinds_for(CrawlerRules.TOWER_PATCH).has("gloam")
			and not CrawlerMobs.kinds_for(CrawlerRules.CITY_PATCH).has("kestrel"),
		"Far Beacon 4 fields the three robots")
	_expect(CrawlerRules.flies("kestrel")
			and not CrawlerRules.flies("bastion")
			and not CrawlerRules.flies("weaver"),
		"only Kestrel flies")
	_expect(CrawlerMobs.attack_mode("kestrel", 1) == "standoff"
			and CrawlerMobs.attack_mode("bastion", 1) == "mortar"
			and CrawlerMobs.attack_mode("weaver", 1) == "turret",
		"each robot has its own attack")
	_expect(CrawlerMobs.spawn_mode("kestrel", 1) == "ahead"
			and CrawlerMobs.kind_cap("kestrel", 1) >= 11,
		"kestrels spawn ahead like rangers")
	_expect(CrawlerMobs.spawn_mode("bastion", 1) == "pack"
			and CrawlerMobs.agro_mode("bastion", 1) == "reserve"
			and CrawlerMobs.kind_cap("bastion", 1) <= 11
			and CrawlerRules.bastion_agro_cap(1) <= 3
			and CrawlerRules.bastion_reserve_cap(1) >= 4
			and CrawlerRules.bastion_reserve_cap(1) <= 8
			and CrawlerMobs.number("bastion", 1, "speed", 9.0) <= 2.2
			and CrawlerRules.BASTION_AGRO_NEAR
				>= CrawlerRules.FIELD_RING_START + CrawlerRules.FIELD_RING_THICK,
		"bastions keep a small agro pack and a distant reserve")
	_expect(CrawlerRules.bastion_keepout(Vector3(10.0, 0.0, 0.0), Vector3.ZERO)
			and not CrawlerRules.bastion_keepout(Vector3(25.0, 0.0, 0.0), Vector3.ZERO)
			and CrawlerRules.bastion_in_band(
				Vector3(42.0, 0.0, 0.0), Vector3.ZERO,
				CrawlerRules.BASTION_AGRO_NEAR, CrawlerRules.BASTION_AGRO_FAR)
			and CrawlerRules.bastion_in_grid(Vector3(58.0, 0.0, 0.0), Vector3.ZERO),
		"bastions sit in the mid ring and reserves wait in the far ring")
	var lob := CrawlerRules.high_lob_launch(
		Vector3.ZERO, Vector3(0.0, 0.0, 22.0), Vector3.ZERO,
		24.0, CrawlerRules.BASTION_GRAVITY, Vector3.UP)
	_expect(lob.y > 10.0, "bastion shells launch on a high arc")
	_expect(CrawlerMobs.number("bastion", 1, "agro_range", 0.0) >= 64.0
			and CrawlerHunt.shot_max("bastion") >= 64.0,
		"bastions wake and lob from the mid ring")
	var lob_from := Vector3(0.0, 1.5, 0.0)
	var lob_aim := Vector3(0.0, 1.5, 36.0)
	var lob_vel := CrawlerRules.high_lob_launch(
		lob_from, lob_aim, Vector3.ZERO,
		24.0, CrawlerRules.BASTION_GRAVITY, Vector3.UP)
	var lob_at := lob_from
	for _i in 400:
		lob_vel -= Vector3.UP * CrawlerRules.BASTION_GRAVITY * 0.016
		lob_at += lob_vel * 0.016
		if lob_at.y <= 1.5 and lob_vel.y < 0.0:
			break
	_expect(lob_at.distance_to(lob_aim) < 4.0
			and lob_at.distance_to(lob_from) > 24.0,
		"a bastion shell lands on the aim instead of falling on the walker")
	_expect(CrawlerRules.spawn_weight("weaver") > CrawlerRules.spawn_weight("kestrel")
			and CrawlerRules.spawn_weight("weaver") > CrawlerRules.spawn_weight("bastion")
			and CrawlerMobs.kind_cap("weaver", 1) >= 8
			and CrawlerMobs.kind_cap("weaver", 1) <= 14
			and CrawlerRules.WEAVER_FLOCK <= 3
			and CrawlerMobs.number("weaver", 1, "health", 9.0) <= 4.5,
		"weavers stay a thin low-health close pack")
	_expect(CrawlerMobs.number("bastion", 3, "health", 0.0)
			> CrawlerMobs.number("bastion", 1, "health", 0.0),
		"robot stats scale with level")

	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)
	var kestrel := horde.spawn_test_mob("kestrel", Vector3(0.0, 8.0, 0.0), false, 1)
	var bastion := horde.spawn_test_mob("bastion", Vector3(4.0, 2.0, 0.0), false, 1)
	var weaver := horde.spawn_test_mob("weaver", Vector3(-4.0, 2.0, 0.0), false, 1)
	_expect(kestrel != null and kestrel.wild_kind() == "kestrel" and kestrel.flies(),
		"Kestrel spawns flying")
	_expect(bastion != null and bastion.wild_kind() == "bastion" and not bastion.flies(),
		"Bastion spawns on the ground")
	_expect(weaver != null and weaver.wild_kind() == "weaver" and not weaver.flies(),
		"Weaver stays on the ground")
	_expect(kestrel.body_height() > 3.5
			and bastion.body_height() < 3.2
			and bastion.body_height() > 1.6,
		"kestrel stays large and bastions stay compact")
	_expect(weaver.body_height() < 1.8 and weaver.body_height() > 0.7,
		"weavers are small swarm spiders")
	_expect(_authored_inks(kestrel).size() >= 3
			and _has_bright_ink(_authored_inks(kestrel))
			and _has_bright_ink(_authored_inks(bastion))
			and _has_bright_ink(_authored_inks(weaver)),
		"robot GLBs keep their Blender material colors")
	_expect(_has_enemy_rim(kestrel) and _has_enemy_rim(bastion)
			and _has_enemy_rim(weaver),
		"authored robots wear the red rim outline")
	kestrel.set_physics_process(false)
	bastion.set_physics_process(false)
	weaver.set_physics_process(false)
	await get_tree().process_frame

	var prey := _HuntDummy.new()
	add_child(prey)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(bastion.move_speed() <= 2.2, "bastions crawl")
	var saved_at := _player.global_position
	_player.global_position = bastion.global_position + Vector3(0.0, 0.0, 8.0)
	_expect(bastion.tick_agro(_player, 0.2) and bastion.chase,
		"a bastion next to the player agros without a slot cap")
	_player.global_position = saved_at
	prey.add_to_group(&"network_players")
	MOB_SENSE.ensure_frame(get_tree())
	prey.global_position = bastion.combat_position() + Vector3(0.0, 0.0, 22.0)
	bastion.call("_try_mortar", prey)
	_expect(str(bastion.call("current_clip")) == "Stomp",
		"Bastion plays a stomp clip for the lob")
	var shells := 0
	var trails := 0
	for node: Node in horde.find_children("*", "", true, false):
		if str(node.name).begins_with("CrawlerBastionShell"):
			shells += 1
		if node is AbilityTrail:
			trails += 1
	_expect(shells >= 1, "bastions throw a high shell")
	_expect(trails >= 1, "bastion shells leave a teleport-style trail")
	var mark: MeshInstance3D
	var mark_tint := Color.BLACK
	for node: Node in horde.find_children("*", "", true, false):
		if str(node.name) != "BastionMark":
			continue
		mark = node as MeshInstance3D
		var painted := mark.material_override as ShaderMaterial if mark != null \
			else null
		if painted != null:
			mark_tint = painted.get_shader_parameter(&"tint")
		break
	_expect(mark != null and mark.mesh is CylinderMesh
			and mark.global_position.distance_to(prey.global_position) < 6.0,
		"bastion mortars paint a circle on the impact site")
	_expect(mark != null and mark.material_override is ShaderMaterial
			and (mark.material_override as ShaderMaterial).shader
				== CrawlerBastionShell.IRIS_SHADER
			and mark_tint.r > 0.7 and mark_tint.g < 0.35,
		"the impact circle is the red iridescent film")
	for node: Node in horde.find_children("*", "", true, false):
		if str(node.name).begins_with("CrawlerBastionShell"):
			node.queue_free()
	prey.remove_from_group(&"network_players")
	prey.taken = 0.0
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	prey.global_position = weaver.combat_position()
	weaver.call("_try_pincer", prey, 4.0)
	_expect(prey.taken > 0.0, "Weaver pincer damages a close target")
	prey.taken = 0.0
	var weaver_home := weaver.global_position
	prey.speed = 22.0
	prey.velocity = Vector3(0.0, 0.0, 22.0)
	# Godot forward is -Z. A runner heading +Z is looking away from a
	# spider that is chasing from smaller Z.
	prey.look = Vector3(0.0, 0.0, 1.0)
	prey.global_position = weaver.global_position + Vector3(0.0, 0.0, 24.0)
	weaver.call("_hop_chase", prey, 0.16)
	_expect(bool(weaver.call("hopping")) and weaver.velocity.z > 4.0,
		"weavers hop after a runner")
	_expect(str(weaver.call("current_clip")) == "Leap",
		"a chasing weaver plays the hop")
	_expect(bool(weaver.call("_shot_ready", prey, 24.0)),
		"weavers keep shooting as a runner leaves")
	var hook: Vector3 = weaver.call("hop_goal", prey) - weaver.global_position
	_expect(hook.z > 0.0 and not bool(weaver.call("in_camera", prey)),
		"a rear hop swings into the look instead of planting behind")
	var perch: Vector3 = weaver.call("hop_station", prey)
	_expect(perch.z > prey.global_position.z + 6.0,
		"the hop perch sits in front of the camera")
	weaver.global_position = perch
	_expect(bool(weaver.call("in_camera", prey)),
		"the hop perch is on camera")
	weaver.global_position = weaver_home
	weaver.velocity = Vector3.ZERO
	prey.speed = 0.0
	prey.velocity = Vector3.ZERO
	prey.global_position = weaver.combat_position() + Vector3(0.0, 0.0, 12.0)
	prey.look = Vector3(0.0, 0.0, 1.0)
	_expect(bool(weaver.call("_shot_ready", prey, 12.0)) == false,
		"a spider behind the look hops into camera before Laser Eyes")
	prey.look = Vector3(0.0, 0.0, -1.0)
	_expect(bool(weaver.call("in_camera", prey))
			and bool(weaver.call("_shot_ready", prey, 12.0)),
		"a slowed player looking at the spider is a laser shot")
	MOB_SENSE.begin_frame(get_tree())
	weaver.call("_try_beam", prey)
	_expect(bool(weaver.call("beaming")) and bool(weaver.call("charging")),
		"weavers plant and charge a red beam")
	weaver.call("_service_beam", 0.12)
	_expect(prey.taken == 0.0, "the charge does not cut yet")
	var eyes := weaver.get_node_or_null("WeaverEyes")
	_expect(eyes != null and bool(eyes.call("is_lit")),
		"the red beam charges on the player")
	weaver.call("_service_beam", 0.4)
	_expect(prey.taken > 0.0, "Laser Eyes cuts the player")
	_expect(prey.last_hit != null and prey.last_hit.ability_id == "laser_eyes",
		"the weaver shot is Laser Eyes")
	_expect(str(weaver.call("current_clip")) == "Turret_Fire",
		"Laser Eyes uses the turret clip")
	var weaver_bolts := 0
	for node: Node in horde.find_children("*", "", true, false):
		if str(node.name).begins_with("CrawlerRobotLaser"):
			weaver_bolts += 1
	_expect(weaver_bolts == 0, "weavers do not throw turret bolts")
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	prey.global_position = kestrel.combat_position() + Vector3(0.0, 0.0, 24.0)
	kestrel.call("_try_burst", prey, prey.combat_position(), 24.0)
	var bolts := 0
	for node: Node in horde.get_children():
		if node is CrawlerRobotLaser:
			bolts += 1
	_expect(bolts >= 6, "Kestrel gatling leaves a burst of lasers")
	_expect(str(kestrel.call("current_clip")) == "Fire_Burst",
		"Kestrel plays the fire burst")
	var dummy := Node3D.new()
	dummy.name = "DeadGunner"
	add_child(dummy)
	var late := CrawlerRobotLaser.new()
	late.arm_delay = 0.2
	_expect(late.launch_anywhere(
			self, Vector3(0.0, 2.0, 0.0), Vector3.FORWARD, dummy),
		"a delayed laser can leave a dummy muzzle")
	dummy.free()
	late._physics_process(0.016)
	_expect(is_instance_valid(late),
		"a delayed laser survives after its gunner is freed")
	late.queue_free()
	_player.velocity = Vector3(40.0, 0.0, 0.0)
	kestrel.chase = true
	kestrel.ever_chased = true
	kestrel.global_position = _player.global_position + Vector3(28.0, 8.0, 0.0)
	kestrel.velocity = Vector3.ZERO
	kestrel._cruise = CrawlerRules.ranger_chase_speed(40.0, 1, false)
	kestrel._drift_in_frame(
		_player, kestrel._hover_hold(_player.global_position, 28.0), 0.55)
	_expect(kestrel.velocity.x > 24.0, "matched kestrels ride the player's frame")
	_player.velocity = Vector3.ZERO
	prey.add_to_group(&"network_players")
	prey.taken = 0.0
	prey.global_position = Vector3(40.0, 2.0, 40.0)
	var drop := CrawlerBastionShell.new()
	drop.damage = 12.0
	drop.hit_radius = 1.6
	_expect(drop.launch_anywhere(
			self, prey.global_position + Vector3(0.0, 0.3, 0.0),
			Vector3(0.0, -4.0, 0.0), bastion),
		"a bastion shell can land on a runner")
	drop.set_physics_process(false)
	drop.global_position = prey.global_position
	MOB_SENSE.invalidate()
	MOB_SENSE.ensure_frame(get_tree())
	drop.detonate()
	_expect(prey.taken > 0.0, "the bastion shell explodes on impact")
	if is_instance_valid(drop):
		drop.queue_free()
	prey.remove_from_group(&"network_players")
	var rival := horde.spawn_test_mob(
		"weaver", bastion.combat_position() + Vector3(5.2, 0.0, 0.0), false, 1)
	rival.set_physics_process(false)
	var rival_hp := rival.health()
	bastion.call("_die")
	_expect(bool(bastion.call("fusing")) and is_instance_valid(bastion),
		"a killed bastion stays for the red fuse")
	bastion.call("_tick_fuse", 1.1)
	_expect(is_instance_valid(bastion) and bool(bastion.call("fusing")),
		"the body holds before it reddens")
	bastion.call("_tick_fuse", 1.0)
	_expect(not is_instance_valid(bastion) or bastion.is_queued_for_deletion(),
		"the bastion bursts after the fuse")
	_expect(is_instance_valid(rival) and rival.health() < rival_hp,
		"the death burst damages nearby mobs")
	var stray := horde.spawn_test_mob("gloam", Vector3(5.0, 2.0, 2.0), false, 1)
	var kept := horde.spawn_test_mob("ranger", Vector3(3.0, 2.0, -2.0), false, 1)
	stray.set_physics_process(false)
	kept.set_physics_process(false)
	var saved := _player.global_position
	_player.global_position = Vector3.ZERO
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(not bool(horde.call("_recycle_mob", stray)),
		"demons do not recycle onto a wild or robot ring")
	horde.call("_clear_off_combo_wilds")
	_expect(not is_instance_valid(stray) or stray.dismissed,
		"a demon next to the player leaves a robot or wild tile")
	_expect(is_instance_valid(kept) and not kept.dismissed,
		"the current three-kind set stays around the player")
	var leftover_ring: Array[Dictionary] = [{
		"at": Vector3.ZERO,
		"kinds": PackedStringArray(["gloam", "vesper", "threnody"]),
		"patch_id": 4,
	}]
	_expect(not bool(horde.call(
			"_off_combo_near", Vector3(40.0, 0.0, 0.0), "ranger", leftover_ring, 9)),
		"a wild pack on the tile you left stays")
	_expect(bool(horde.call(
			"_off_combo_near", Vector3(8.0, 0.0, 0.0), "ranger", leftover_ring, 4)),
		"a wild that followed onto the new tile still leaves")
	var parked := horde.spawn_test_mob("ranger", Vector3(90.0, 2.0, 0.0), false, 1)
	parked.set_physics_process(false)
	horde.call("_trim_ring_overflow", _player)
	horde.call("_reap_far_and_idle")
	_expect(is_instance_valid(parked) and not parked.dismissed,
		"a pack outside the spawn rings stays until stream-out")
	var distant := horde.spawn_test_mob("ranger", Vector3(500.0, 2.0, 0.0), false, 1)
	distant.set_physics_process(false)
	horde.call("_reap_far_and_idle")
	_expect(not is_instance_valid(distant) or distant.dismissed,
		"a pack past stream-out still despawns")
	_player.global_position = saved
	prey.queue_free()
	horde.queue_free()
	await get_tree().process_frame


func _check_aliens() -> void:
	CrawlerMobs.reload()
	for kind: String in CrawlerRules.ALIEN_KINDS:
		_expect(ALIEN_MODELS.scene(kind) != null,
			"%s GLB is in the alien pack" % kind)
	_expect(CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ALIEN, "scout")
			and CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ALIEN, "gray")
			and CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ALIEN, "tanglemaw")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ALIEN, "ranger")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_WILD, "tanglemaw")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_ROBOT, "scout")
			and not CrawlerRules.combo_allows_kind(CrawlerRules.PATCH_COMBO_DEMON, "gray"),
		"aliens stay on their own three-kind set")
	_expect(CrawlerRules.flies("scout")
			and not CrawlerRules.flies("gray")
			and not CrawlerRules.flies("tanglemaw"),
		"only the scout flies")
	_expect(CrawlerMobs.attack_mode("scout", 1) == "pulse"
			and CrawlerMobs.attack_mode("gray", 1) == "standoff"
			and CrawlerMobs.attack_mode("tanglemaw", 1) == "bite",
		"each alien has its own attack")
	_expect(CrawlerMobs.spawn_mode("scout", 1) == "ahead"
			and CrawlerMobs.spawn_mode("gray", 1) == "ahead"
			and CrawlerMobs.spawn_mode("tanglemaw", 1) == "ring",
		"scouts and grays wait ahead, tanglemaws swarm the ring")
	_expect(CrawlerMobs.kind_cap("tanglemaw", 1) >= 32
			and CrawlerRules.spawn_weight("tanglemaw")
				> CrawlerRules.spawn_weight("scout"),
		"tanglemaws spawn in mass")
	_expect(CrawlerMobs.number("gray", 1, "shot_speed", 24.0) <= 8.0,
		"gray orbs crawl")
	_expect(CrawlerRules.upgrade_stat_title("cold", "icicle") == "Slow",
		"ice names its debuff Slow")

	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)
	var scout := horde.spawn_test_mob("scout", Vector3(0.0, 8.0, 0.0), false, 1)
	var gray := horde.spawn_test_mob("gray", Vector3(4.0, 2.0, 0.0), false, 1)
	var maw := horde.spawn_test_mob("tanglemaw", Vector3(-4.0, 2.0, 0.0), false, 1)
	_expect(scout != null and scout.wild_kind() == "scout" and scout.flies(),
		"Scout spawns flying")
	_expect(gray != null and gray.wild_kind() == "gray" and not gray.flies(),
		"Gray spawns on the ground")
	_expect(maw != null and maw.wild_kind() == "tanglemaw" and not maw.flies(),
		"Tanglemaw stays on the ground")
	_expect(_authored_inks(scout).size() >= 2
			and _has_bright_ink(_authored_inks(scout))
			and _has_bright_ink(_authored_inks(gray))
			and _has_bright_ink(_authored_inks(maw)),
		"alien GLBs keep their Blender material colors")
	_expect(_has_enemy_rim(scout) and _has_enemy_rim(gray)
			and _has_enemy_rim(maw),
		"authored aliens wear the red rim outline")
	scout.set_physics_process(false)
	gray.set_physics_process(false)
	maw.set_physics_process(false)
	await get_tree().process_frame

	var prey := _HuntDummy.new()
	add_child(prey)
	prey.add_to_group(&"network_players")
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	prey.global_position = scout.combat_position() + Vector3(0.0, 0.0, 24.0)
	scout.global_position = Vector3(0.0, 8.0, 0.0)
	scout.call("_try_lock", prey, 24.0, 0.0)
	_expect(bool(scout.call("frozen_aim")) or bool(scout.call("aiming")),
		"scout freezes its aim before it fires")
	scout._aim_point = prey.combat_position()
	scout._aim_frozen = true
	scout.call("_place_pointer")
	_expect(bool(scout.call("pointer_on")),
		"scout holds a green cannon pointer")
	_expect(is_equal_approx(scout._pointer.current_opacity(),
			CrawlerScout.POINTER_OPACITY)
			and is_equal_approx(CrawlerScout.POINTER_OPACITY, 0.4),
		"scout pointer is sixty percent transparent")
	var barrel: Vector3 = scout.cannon_ahead()
	var pointer_along: Vector3 = scout._pointer.global_transform.basis.y
	_expect(pointer_along.length_squared() > 0.0001
			and pointer_along.normalized().dot(barrel) > 0.98,
		"scout pointer leaves the cannon straight")
	scout.call("_start_pulses", prey)
	var pulses := 0
	var pulse_along := Vector3.ZERO
	for node: Node in get_children():
		if str(node.name) == "ScoutPulse":
			pulses += 1
			pulse_along = (node as Node3D).global_transform.basis.y
	for node: Node in horde.find_children("*", "", true, false):
		if str(node.name) == "ScoutPulse":
			pulses += 1
			pulse_along = (node as Node3D).global_transform.basis.y
	_expect(pulses >= 1, "scout fires a pink pulse beam")
	_expect(pulse_along.length_squared() > 0.0001
			and pulse_along.normalized().dot(barrel) > 0.98,
		"scout shots leave the cannon straight")

	prey.taken = 0.0
	prey.global_position = gray.combat_position() + Vector3(0.0, 0.0, 18.0)
	gray.call("_release_shot", prey)
	var orbs := 0
	var green := false
	var homing := false
	for node: Node in horde.find_children("*", "", true, false):
		var shot := node as CrawlerGrayShot
		if shot == null:
			continue
		orbs += 1
		green = shot.GLOW_COLOR == EnergyVfx.TINT_GREEN
		homing = shot.shot_speed <= 8.0 and shot.homing_left > 1.0
	if orbs == 0:
		for node: Node in get_children():
			var shot := node as CrawlerGrayShot
			if shot == null:
				continue
			orbs += 1
			green = shot.GLOW_COLOR == EnergyVfx.TINT_GREEN
			homing = shot.shot_speed <= 8.0 and shot.homing_left > 1.0
	_expect(orbs >= 1 and green, "gray throws a green ranger-style orb")
	_expect(homing, "gray orbs are slow and home for a while")

	_player.statuses.clear()
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	maw.global_position = _player.global_position
	maw.call("_bite", _player, 4.0)
	_expect(_player.statuses.has(CombatStatuses.SLOW)
			and _player.statuses.remaining(CombatStatuses.SLOW) >= 0.9,
		"tanglemaw bites apply Slow")
	for _hit in 4:
		_player.statuses.apply_status(CombatStatuses.SLOW, 1.0, 0.0, true)
	_expect(_player.statuses.remaining(CombatStatuses.SLOW)
			<= CombatStatuses.SLOW_MAX + 0.05,
		"Slow stacks to five seconds")
	_player.statuses.apply_status(CombatStatuses.SLOW, 1.0, 0.0, true)
	_expect(is_equal_approx(_player.statuses.remaining(CombatStatuses.SLOW),
			CombatStatuses.SLOW_MAX),
		"Slow will not stack past five seconds")
	_expect(is_equal_approx(_player.statuses.move_scale(), CombatStatuses.SLOW_SCALE),
		"Slow halves movement")
	_player.statuses.clear()

	var drop_at := scout.global_position
	scout.call("_die")
	await get_tree().process_frame
	var dropped: CrawlerGray
	for mob_variant: Variant in horde._mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob != null and mob.wild_kind() == "gray" and mob != gray:
			dropped = mob as CrawlerGray
			break
	_expect(dropped != null and dropped.dropping()
			and dropped.global_position.distance_to(drop_at) < 2.5,
		"a killed scout drops a gray")
	if dropped != null:
		var hung := dropped.global_position
		var up := dropped._up()
		dropped.set_physics_process(false)
		for _tick in 24:
			dropped._physics_process(0.05)
		var fallen := (hung - dropped.global_position).dot(up)
		_expect(dropped.dropping() and fallen > 2.0,
			"a dropped gray falls out of the wreck instead of hanging in the air")

	prey.remove_from_group(&"network_players")
	prey.queue_free()
	horde.queue_free()
	await get_tree().process_frame


func _check_goblins() -> void:
	CrawlerMobs.reload()
	_expect(CrawlerRules.is_goblin_kind("gruk")
			and CrawlerRules.is_goblin_kind("nix")
			and CrawlerRules.is_goblin_kind("vex"),
		"Gruk, Nix, and Vex are the castle goblins")
	_expect(not CrawlerRules.flies("gruk")
			and not CrawlerRules.flies("nix")
			and not CrawlerRules.flies("vex"),
		"goblins cannot fly")
	_expect(CrawlerMobs.attack_mode("gruk", 1) == "swing"
			and CrawlerMobs.attack_mode("nix", 1) == "swing"
			and CrawlerMobs.attack_mode("vex", 1) == "mortar",
		"Gruk and Nix swing, Vex lobs a mortar")
	_expect(CrawlerRules.GOBLIN_GARRISON >= 200
			and CrawlerRules.GOBLIN_WAKE_RANGE >= 160.0,
		"the castle horde is hundreds of goblins")
	_expect(CrawlerRules.goblin_garrison_reach(0) <= CrawlerRules.GOBLIN_INNER_MAX
			and CrawlerRules.goblin_garrison_reach(CrawlerRules.GOBLIN_INTERIOR)
				>= CrawlerRules.GOBLIN_OUTER_MIN
			and CrawlerRules.goblin_garrison_reach(CrawlerRules.GOBLIN_GARRISON - 1)
				<= CrawlerRules.GOBLIN_OUTER_MAX + 0.01,
		"fallback pads still pack the courtyard and the grounds")
	var kinds := {}
	for index in CrawlerRules.GOBLIN_GARRISON:
		kinds[CrawlerRules.goblin_garrison_kind(index)] = true
	_expect(kinds.has("gruk") and kinds.has("nix") and kinds.has("vex"),
		"the castle horde mixes all three goblins")

	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO

	var site := PatchMonument.new()
	site.monument_id = "keepout-test"
	site.keepout_radius = 24.0
	add_child(site)
	site.global_position = Vector3(200.0, 0.0, 0.0)
	await get_tree().process_frame
	_expect(PatchMonument.blocks_any(get_tree(), Vector3(200.0, 0.0, 0.0)),
		"a monument keep-out still blocks new wild homes")
	_expect(not horde._spawn_point_ok(
			Vector3(200.0, 0.0, 0.0), _player, null, "ranger"),
		"wild packs do not spawn on a monument keep-out")

	var chaser := horde.spawn_test_mob("ranger", Vector3(205.0, 0.0, 0.0), true)
	var lurker := horde.spawn_test_mob("ranger", Vector3(208.0, 0.0, 0.0), false)
	var gruk := horde.spawn_test_mob("gruk", Vector3(202.0, 0.0, 0.0), false)
	chaser.set_physics_process(false)
	lurker.set_physics_process(false)
	gruk.set_physics_process(false)
	await get_tree().process_frame
	_expect(gruk != null and gruk.wild_kind() == "gruk" and not gruk.flies()
			and gruk.is_persistent(),
		"Gruk is a grounded garrison mob")
	horde._reap_far_and_idle()
	_expect(is_instance_valid(chaser) and not chaser.dismissed,
		"a chasing wild is not dismissed for a generic monument keep-out")
	_expect(not is_instance_valid(lurker) or lurker.dismissed,
		"idle wilds still cannot sit on a monument keep-out")
	_expect(is_instance_valid(gruk) and not gruk.dismissed,
		"castle goblins are not reaped for living on the grounds")

	var keep := PatchMonument.new()
	keep.monument_id = CrawlerProgress.QUEST_CASTLE
	add_child(keep)
	keep.global_position = Vector3(400.0, 0.0, 0.0)
	await get_tree().process_frame
	var follower := horde.spawn_test_mob("ranger", Vector3(410.0, 0.0, 0.0), true)
	var idle_keep := horde.spawn_test_mob("rhino", Vector3(420.0, 0.0, 0.0), false)
	follower.set_physics_process(false)
	idle_keep.set_physics_process(false)
	_player.global_position = Vector3(400.0, 0.0, 0.0)
	horde.call("_clear_castle_wilds")
	_expect(not is_instance_valid(follower) or follower.dismissed,
		"a chasing wild despawns when the player enters the castle keep")
	_expect(not is_instance_valid(idle_keep) or idle_keep.dismissed,
		"idle patch mobs leave the castle keep")
	var yard := horde.spawn_test_mob("gruk", Vector3(405.0, 0.0, 0.0), false)
	yard.set_physics_process(false)
	horde.call("_clear_castle_wilds")
	_expect(is_instance_valid(yard) and not yard.dismissed,
		"castle goblins stay in the keep")
	_expect(not horde._spawn_point_ok(
			Vector3(410.0, 0.0, 0.0), _player, null, "ranger"),
		"the castle keep does not stamp a new wild home")
	_player.global_position = Vector3.ZERO
	keep.queue_free()

	var nix := horde.spawn_test_mob("nix", Vector3(0.0, 2.0, 4.0), false)
	var vex := horde.spawn_test_mob("vex", Vector3(0.0, 2.0, -6.0), false)
	nix.set_physics_process(false)
	vex.set_physics_process(false)
	await get_tree().process_frame
	_expect(nix.wild_kind() == "nix" and not nix.flies(),
		"Nix is a grounded melee goblin")
	_expect(vex.wild_kind() == "vex" and not vex.flies(),
		"Vex stays on the ground")
	_expect(_authored_inks(gruk).size() >= 4
			and _has_bright_ink(_authored_inks(gruk))
			and _has_bright_ink(_authored_inks(nix))
			and _has_bright_ink(_authored_inks(vex)),
		"goblin GLBs keep their Blender material colors")
	_expect(_has_enemy_rim(gruk) and _has_enemy_rim(nix)
			and _has_enemy_rim(vex),
		"authored goblins wear the red rim outline")
	_expect(gruk.ground_clearance() >= 0.7
			and nix.ground_clearance() > 0.5,
		"goblins stand a body-height above the mesh")
	var pad := StaticBody3D.new()
	var pad_shape := CollisionShape3D.new()
	var pad_box := BoxShape3D.new()
	pad_box.size = Vector3(16.0, 0.4, 16.0)
	pad_shape.shape = pad_box
	pad.add_child(pad_shape)
	add_child(pad)
	pad.global_position = Vector3(0.0, 400.0, 0.0)
	var roof := StaticBody3D.new()
	var roof_shape := CollisionShape3D.new()
	var roof_box := BoxShape3D.new()
	roof_box.size = Vector3(16.0, 0.4, 16.0)
	roof_shape.shape = roof_box
	roof.add_child(roof_shape)
	add_child(roof)
	roof.global_position = Vector3(0.0, 409.2, 0.0)
	var grounded := CrawlerGruk.new()
	grounded.configure("ground-clear", Transform3D.IDENTITY, 1, false)
	add_child(grounded)
	grounded.set_physics_process(false)
	grounded._planet = null
	grounded.global_position = Vector3(0.0, 408.0, 0.0)
	await get_tree().physics_frame
	grounded.snap_to_ground()
	_expect(grounded.global_position.y > 400.4
			and grounded.global_position.y < 402.0,
		"grounded mobs sit on the floor, not a roof above them")
	var creature := grounded.find_child("Creature", true, false) as Node3D
	if creature != null:
		var lowest := INF
		for node_variant: Variant in creature.find_children("*", "MeshInstance3D", true, false):
			var mesh := node_variant as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var box: AABB = grounded.global_transform.affine_inverse() \
				* mesh.global_transform * mesh.get_aabb()
			lowest = minf(lowest, box.position.y)
		if lowest != INF:
			_expect(absf(lowest + grounded.body_height() * 0.5) < 0.22,
				"authored goblin feet sit at the body floor")
	grounded.queue_free()
	pad.queue_free()
	roof.queue_free()

	var prey := _HuntDummy.new()
	add_child(prey)
	prey.global_position = gruk.combat_position()
	gruk.call("_swing", prey)
	_expect(prey.taken > 0.0, "Gruk swing damages a close target")
	_expect(gruk.current_clip() == CrawlerMob.CLIP_ATTACK,
		"Gruk plays a swing clip")
	prey.taken = 0.0
	prey.global_position = nix.combat_position()
	nix.call("_swing", prey)
	_expect(prey.taken > 0.0, "Nix swing damages a close target")

	var orb := CrawlerVexMortar.new()
	orb.damage = 12.0
	orb.ball_radius = 0.4
	orb.hit_radius = 1.2
	add_child(orb)
	orb.set_physics_process(false)
	await get_tree().process_frame
	_expect(orb._core is EnergyVfx
			and orb._core.kind == EnergyVfx.Kind.PROJECTILE
			and orb._core.current_tint().g > orb._core.current_tint().r
			and orb._core.current_tint().g > orb._core.current_tint().b,
		"Vex mortars glow green")
	orb.queue_free()
	prey.add_to_group(&"network_players")
	prey.global_position = Vector3(40.0, 2.0, 40.0)
	var ball := CrawlerVexMortar.new()
	ball.damage = 12.0
	ball.hit_radius = 1.4
	_expect(ball.launch_anywhere(
			self, prey.global_position + Vector3(0.0, 0.3, 0.0),
			Vector3(0.0, -4.0, 0.0), vex),
		"Vex can throw a mortar")
	for _step in 8:
		await get_tree().physics_frame
	_expect(prey.taken > 0.0, "the mortar damages a player it lands on")
	if is_instance_valid(ball):
		ball.queue_free()
	prey.remove_from_group(&"network_players")

	MOB_SENSE.invalidate()
	MOB_SENSE.ensure_frame(get_tree())
	gruk.chase = false
	nix.chase = false
	vex.chase = false
	gruk.call("_on_agro_started")
	_expect(nix.chase and vex.chase,
		"one goblin agroes the castle horde")
	gruk.chase = false
	nix.chase = false
	vex.chase = false

	var wake := CrawlerHorde.new()
	add_child(wake)
	wake.set_process(false)
	var pads := PackedVector3Array()
	for index in CrawlerRules.GOBLIN_GARRISON:
		pads.append(Vector3(float(index % 20) * 2.0, 3.0, float(index / 20) * 2.0))
	_expect(wake.queue_castle_homes(pads) == CrawlerRules.GOBLIN_GARRISON,
		"the castle horde queues every preseeded home at once")
	_expect(wake._queued_garrison_count() == CrawlerRules.GOBLIN_GARRISON,
		"the garrison wake is one shot")
	_expect(wake.queue_castle_homes(pads) == 0,
		"the castle horde does not queue twice")
	wake.queue_free()

	var before := horde.garrison_live_count()
	_expect(horde.spawn_castle_garrison_at(Vector3(0.0, 12.0, 0.0), 12) == 12,
		"the castle horde uses preset pads")
	_expect(horde.garrison_live_count() == before + 12,
		"garrison pads add live goblins")
	var saw := {}
	for mob_variant: Variant in horde._mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob == null or not mob.is_persistent():
			continue
		mob.set_physics_process(false)
		saw[mob.wild_kind()] = true
	_expect(saw.has("gruk") and saw.has("nix") and saw.has("vex"),
		"the seeded horde includes Gruk, Nix, and Vex")
	var doomed: CrawlerMob
	for mob_variant: Variant in horde._mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob != null and mob.is_persistent() and mob.wild_kind() == "gruk":
			doomed = mob
			break
	_expect(doomed != null, "the horde placed a Gruk")
	var smash := DamageHit.impact(doomed.combat_position(), 2.0, 9999.0)
	smash.faction = DamageHit.Faction.PLAYER
	doomed.apply_damage(smash)
	await get_tree().process_frame
	_expect(horde.garrison_live_count() == before + 11,
		"a killed goblin stays gone")
	_expect(horde.spawn_castle_garrison_at(Vector3(0.0, 12.0, 0.0), 12) == 0,
		"the castle horde does not refill")

	prey.queue_free()
	site.queue_free()
	horde.queue_free()
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().process_frame


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
	ram.velocity = Vector3.ZERO
	ram._tick_far(0.2)
	_expect(ram.velocity.length() > 1.0, "far eyes keep circling")
	ram.global_transform.basis = Basis(
		Vector3(1.2, 0.18, 0.0),
		Vector3(0.04, 0.82, 0.12),
		Vector3(0.08, 0.0, 1.15))
	ram.velocity = Vector3(6.0, 0.0, 2.4)
	ram._face_motion(0.16)
	var faced := ram.global_transform.basis
	_expect(is_equal_approx(faced.x.length(), 1.0)
			and is_equal_approx(faced.y.length(), 1.0)
			and is_equal_approx(faced.z.length(), 1.0)
			and faced.determinant() > 0.9,
		"facing motion keeps an orthonormal basis")
	ram.queue_free()

	var walker := CrawlerRhino.new()
	walker.configure("settle", Transform3D(Basis(), Vector3(0.0, 12.0, 0.0)), 1, false)
	add_child(walker)
	walker.set_physics_process(false)
	walker._planet = null
	walker._cached_alt = walker.ground_clearance()
	walker._cached_alt_at = walker.global_position
	walker.velocity = Vector3(0.0, -4.0, 0.0)
	walker._director_climb()
	_expect(walker.velocity.y >= -0.05 and walker.velocity.y < 1.0,
		"grounded mobs do not launch when they touch the dirt")
	walker._cached_alt = 14.0
	walker._cached_alt_at = walker.global_position
	walker.velocity = Vector3(3.0, 5.0, 0.0)
	walker._director_climb()
	_expect(walker.velocity.y < 0.0,
		"a grounded mob that is high falls back to the terrain")
	walker.queue_free()

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
	ranger.velocity = Vector3.ZERO
	ranger._tick_far(0.2)
	_expect(ranger.velocity.length() > 1.0, "far rangers keep patrolling")
	ranger.velocity = Vector3.ZERO
	ranger._tick_cold(0.2)
	_expect(ranger.velocity.length() > 1.0, "cold rangers keep patrolling")
	ranger.queue_free()

	var maw := CrawlerTanglemaw.new()
	maw.configure("sprint", Transform3D(Basis(), Vector3(70.0, 2.0, 0.0)), 1, false)
	add_child(maw)
	maw.set_physics_process(false)
	await get_tree().process_frame
	maw._patrol_left = 0.0
	maw.velocity = Vector3.ZERO
	maw._tick_idle(0.2)
	var maw_first := maw._patrol_goal
	_expect(maw.velocity.length() > 3.5,
		"deagroed tanglemaws sprint instead of standing still")
	maw._patrol_left = 0.0
	maw._tick_idle(0.2)
	_expect(maw_first.distance_to(maw._patrol_goal) > 4.0,
		"tanglemaws pick a new sprint point")
	maw.queue_free()

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
	_expect(material != null and material.shader == CrawlerMob.ENEMY_SHADER
			and material.next_pass is ShaderMaterial
			and (material.next_pass as ShaderMaterial).shader
				== CrawlerMob.ENEMY_OUTLINE_SHADER,
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
	_player.global_position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await get_tree().process_frame
	_player.velocity = Vector3(40.0, 0.0, 0.0)
	ranger.chase = true
	ranger.ever_chased = true
	ranger.global_position = _player.global_position + Vector3(28.0, 8.0, 0.0)
	ranger.velocity = Vector3.ZERO
	ranger._cruise = CrawlerRules.ranger_chase_speed(40.0, 1, false)
	ranger._drift_in_frame(
		_player, ranger._hover_hold(_player.global_position, 28.0), 0.55)
	_expect(ranger.velocity.x > 24.0, "matched rangers ride the player's frame")
	_player.velocity = Vector3.ZERO
	var other := CrawlerRanger.new()
	other.configure("spread2", Transform3D.IDENTITY, 0, false)
	_expect(ranger._orbit_bias().distance_to(other._orbit_bias()) > 0.15,
		"rangers pick different hold points")
	other.free()
	var mark := Node3D.new()
	add_child(mark)
	mark.global_position = Vector3.ZERO
	ranger.global_position = Vector3(-18.0, 12.0, 0.0)
	var hold_at := ranger._hover_hold(mark.global_position, 16.0)
	var loft: Vector3 = ranger._loft_axis()
	var flat := hold_at - mark.global_position
	flat -= loft * flat.dot(loft)
	_expect(flat.length() >= CrawlerRules.RANGER_CROWN_CLEAR - 0.05,
		"ranger hover stays off the player's head")
	_expect(hold_at.x < mark.global_position.x,
		"ranger hold stays on the side it already occupies")
	ranger.velocity = Vector3.ZERO
	ranger.global_position = Vector3(-8.0, 12.0, 0.0)
	var pull := ranger._seek_along(mark)
	_expect(pull.x < -4.0, "a close ranger's standoff pulls away from the player")
	ranger._cruise = 20.0
	ranger._steer_toward(pull.normalized() * 20.0, 0.2, 10.0)
	var away := ranger.global_position - mark.global_position
	away -= loft * away.dot(loft)
	_expect(away.length_squared() > 0.2
			and ranger.velocity.dot(away.normalized()) > 2.0,
		"a close ranger backs off to standoff instead of ramming")
	_player.global_position = Vector3.ZERO
	ranger.velocity = Vector3.ZERO
	ranger.global_position = Vector3(-8.0, 12.0, 0.0)
	ranger._tick_ai(0.16)
	var inward := _player.global_position - ranger.global_position
	inward -= loft * inward.dot(loft)
	_expect(inward.length_squared() > 0.2
			and ranger.velocity.dot(inward.normalized()) < 6.0,
		"rangers do not charge through the player to reach a hold")
	ranger.velocity = Vector3.ZERO
	ranger.global_position = Vector3(0.0, 10.0, 0.0)
	ranger._orbit_dir = Vector3.RIGHT
	ranger._keep_off_crown(mark)
	var shove := ranger.velocity
	shove -= loft * shove.dot(loft)
	_expect(shove.length() > 4.0,
		"a ranger over the head is shoved off the crown")
	mark.queue_free()
	_expect(ranger.velocity.dot(ranger._up()) >= -0.2,
		"the crown shove does not dive onto the player")
	var orb := CrawlerRangerShot.new()
	add_child(orb)
	await get_tree().process_frame
	_expect(orb._core is EnergyVfx
			and orb._core.kind == EnergyVfx.Kind.PROJECTILE
			and orb._core.current_tint().g > orb._core.current_tint().r
			and orb._core.current_tint().g > orb._core.current_tint().b,
		"ranger shots are glowing green orbs")
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
	var flying := CrawlerRangerShot.new()
	add_child(flying)
	flying.set_physics_process(false)
	CrawlerShotSense.drop(flying)
	flying.shooter = ranger
	ranger.free()
	_expect(not bool(flying.call("_shooter_charmed")),
		"an orb whose ranger already died can still ask charm state")
	_expect(bool(flying.call("_should_hurt", _player)),
		"a dead ranger's orb still hunts the player")
	flying._victim_along(flying.global_position, _player.global_position)
	_expect(true, "a dead shooter does not crash the ranger shot sweep")
	var orphan := CrawlerGrayShot.new()
	add_child(orphan)
	orphan.set_physics_process(false)
	CrawlerShotSense.drop(orphan)
	var gone := Node3D.new()
	add_child(gone)
	orphan.shooter = gone
	gone.free()
	orphan._victim_along(Vector3.ZERO, Vector3(1.0, 0.0, 0.0))
	_expect(orphan._live_shooter() == null,
		"a gray orb clears a freed shooter instead of crashing")
	orphan.queue_free()
	flying.queue_free()
	var hulk: CrawlerMob = load("res://game/crawler/crawler_rift_hulk.gd").new()
	hulk.configure("hulk", Transform3D.IDENTITY, 2, false)
	add_child(hulk)
	hulk.set_physics_process(false)
	hulk.global_position = _player.global_position + Vector3(80.0, 0.0, 0.0)
	await get_tree().process_frame
	_expect(hulk.combat_display_name() == "Rift-Hulk", "hulk reports its name")
	_expect(is_equal_approx(hulk.maximum_health(),
			CrawlerMobs.number("rift_hulk", 1, "health", 0.0) * 1.25),
		"level-2 hulks are about 25% tougher than level 1")
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
		charger.velocity = Vector3(12.0, 0.0, 0.0)
		charger._update_clips()
		_expect(charger.current_clip() == CrawlerMob.CLIP_RUN
				and str(charger._animator.current_animation).to_lower().contains("run"),
			"a charging rhino plays its run clip")
		_expect(DamageHit.ABILITY_DISPLAY_NAMES.get("crawler_rhino_meteor", "")
				== "Meteor Strike",
			"the rhino's only attack is named meteor strike")
		charger._face_along(charger._charge_heading, 1.0)
		charger._update_meteor_shock()
		var shock := charger.find_child("MeteorShock", true, false) as MeteorShock
		var horn := charger._nose_point()
		_expect(shock != null and shock.visible,
			"a charging rhino wears the red meteor shock")
		_expect(shock != null
				and shock.global_transform.basis.y.dot(charger._charge_heading) > 0.5,
			"the meteor cone aims out the horn, not the tail")
		_expect(shock != null and shock.global_position.distance_to(horn) < 3.2,
			"the meteor cone sits on the rhino's head")
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
		_expect(not boom, "the meteor does not throw a red shockwave")
		_expect(is_instance_valid(shock),
			"the meteor keeps the punch cone instead of a ground blast")
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
	CrawlerShotSense.drop(orb)
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
		var shield := parry.find_child("ShieldBar", true, false) as ProgressBar
		_expect(parry.find_child("JukeBar", true, false) == null
				and shield != null,
			"crawler vitals keep the blue flight bar and drop the juke bar")
		var weapon_bar := hud.find_child("WeaponBar", true, false) as WeaponBar
		var juke_slot := weapon_bar.find_child("JukeSlot", true, false) as ItemSlot \
			if weapon_bar != null else null
		_player._juke_cooldown_left = 0.0
		if weapon_bar != null:
			weapon_bar._process(0.0)
		_expect(juke_slot != null and juke_slot.badge == "RMB"
				and not juke_slot.cooldown_active
				and is_equal_approx(juke_slot.cooldown_fill, 1.0),
			"juke icon is full when the dash is ready")
		_player._juke_cooldown_left = _player.juke_cooldown() * 0.5
		if weapon_bar != null:
			weapon_bar._process(0.0)
		_expect(juke_slot != null and juke_slot.cooldown_active
				and absf(juke_slot.cooldown_fill - 0.5) < 0.02,
			"juke icon empties through the dash cooldown")
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
	var fps: Control = null
	if hud != null and hud.has_method(&"fps_overlay"):
		fps = hud.call(&"fps_overlay") as Control
	_expect(fps != null and is_equal_approx(fps.anchor_left, 1.0)
			and is_equal_approx(fps.anchor_top, 0.0)
			and fps.find_child("FpsChart", true, false) != null,
		"crawler HUD tracks FPS in the upper-right")


func _check_progress() -> void:
	var progress := _player.crawler_progress
	_expect(progress != null, "crawler player has a run ledger")
	if progress == null:
		return
	if progress.leveled_up.is_connected(_player._on_crawler_leveled_up):
		progress.leveled_up.disconnect(_player._on_crawler_leveled_up)
	_expect(is_equal_approx(
			_player.crawler_damage_scale(),
			1.0 + CharacterDB.level_damage_bonus(
				_player.body_id(), _player.crawler_progress.level)),
		"damage starts at 1X plus the Noct level trait")
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
	_player.award_crawler_kill(1, "", null, 0.0)
	_expect(progress.gold > before_gold, "kills pay gold")
	_expect(progress.xp > 0, "kills pay XP")
	_expect(progress.level == 1, "one kill is not enough to level")
	_player.award_crawler_kill(4, "", null, 0.0)
	_expect(progress.kills == 2, "the run counts every kill")
	_expect(progress.gems_earned == CrawlerMeta.kill_gems(1) + CrawlerMeta.kill_gems(4),
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
	progress.gold = CrawlerProgress.CAPE_PRICE
	_expect(progress.buy_cape(), "gold buys the plain cape")
	_expect(progress.owns_cape(CrawlerProgress.CAPE_ID),
		"the bought cape is owned for this run")
	_expect(_player.crawler_owned_capes().has(CrawlerProgress.CAPE_ID),
		"only run-bought capes appear in the crawler wardrobe")
	_player.refresh_crawler_look()
	_expect(Wardrobe.worn_node(_player.character, "cape") != null,
		"the plain cape attaches to the character")
	progress.gold += CrawlerProgress.cape_price(CrawlerProgress.CAPE_GOLD)
	_expect(progress.buy_cape(CrawlerProgress.CAPE_GOLD), "gold buys the gold cape")
	_player.refresh_crawler_look()
	_expect(progress.wearing_gold_cape(), "buying the gold cape puts it on")
	_player.stats.set_health(_player.maximum_health())
	_expect(_player.request_cape_ability() and _player.gold_cape_active(),
		"Q opens the gold cape window")
	var dummy := _BlastDummy.new()
	add_child(dummy)
	dummy.global_position = _player.global_position + Vector3(2.0, 0.0, 0.0)
	var bounce := DamageHit.impact(_player.combat_position(), 1.0, 22.0)
	bounce.faction = DamageHit.Faction.ENEMY
	bounce.set_source(dummy)
	var cape_hp := _player.health()
	_expect(is_zero_approx(_player.apply_damage(bounce)),
		"the gold cape blocks the hit")
	_expect(is_equal_approx(_player.health(), cape_hp),
		"the gold cape keeps health")
	_expect(dummy.reflected > 0.0, "the gold cape throws the hit back")
	dummy.queue_free()
	progress.note_worn_cape(CrawlerProgress.CAPE_ID)
	_player.refresh_crawler_look()
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
			_player.crawler_dodge_chance(), CrawlerRules.upgrade_boost(1)),
		"one dodge rank is five percent")
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
			_player.crawler_defense_share(), CrawlerRules.upgrade_boost(1)),
		"one defense rank is five percent")
	var defense_hp := _player.health()
	var taken := _player.apply_damage(dodge_poke)
	_expect(is_equal_approx(
			taken, dodge_poke.amount * (1.0 - CrawlerRules.upgrade_boost(1))),
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
	var before_dash := _player.juke_distance()
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_JUKE_DISTANCE),
		"a level point can raise juke distance")
	_expect(_player.juke_distance() > before_dash,
		"juke distance ranks send the dash farther")
	_expect(is_equal_approx(
			_player.juke_distance(),
			CrawlerProgress.JUKE_DISTANCE_BASE
				+ CrawlerProgress.JUKE_DISTANCE_PER_RANK),
		"one juke distance rank adds eight tenths of a metre")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_KNOCKBACK),
		"a level point can raise knockback")
	_expect(is_equal_approx(
			_player.crawler_knockback_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one knockback rank is five percent")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_RANGE),
		"a level point can raise range")
	_expect(is_equal_approx(
			_player.crawler_range_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one range rank is five percent")
	progress.unspent += 1
	_expect(_player.spend_crawler_stat(CrawlerProgress.STAT_CAST),
		"a level point can raise cast")
	_expect(is_equal_approx(
			_player.crawler_cast_trim(), CrawlerProgress.CAST_PER_RANK),
		"one cast rank trims a tenth of a second")
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
	progress.gold += CrawlerProgress.hat_price(CrawlerProgress.HAT_KIT)
	_expect(progress.buy_hat(CrawlerProgress.HAT_KIT), "gold buys the bench visor")
	_player.refresh_crawler_look()
	_expect(progress.wearing_kit_hat(), "buying the visor puts it on")
	_expect(_player.can_edit_crawler_mods(),
		"the visor lets you remode in the field")
	progress.note_worn(CrawlerProgress.HAT_ID)
	_player.refresh_crawler_look()
	_expect(not _player.can_edit_crawler_mods(),
		"taking the visor off locks field mods")
	progress.gold += CrawlerProgress.hat_price(CrawlerProgress.HAT_MISSILE)
	_expect(progress.buy_hat(CrawlerProgress.HAT_MISSILE), "gold buys the hex hat")
	_player.refresh_crawler_look()
	_expect(progress.wearing_missile_hat(), "buying the hex hat puts it on")
	_expect(progress.missile_count() == CrawlerRules.MISSILE_HAT_COUNT,
		"one hex hat looses a few missiles")
	_expect(CrawlerRules.MISSILE_HAT_RANGE >= CrawlerRules.AGRO_RANGE,
		"hex missiles reach a mob that has already agrod")
	_expect(progress.hat_description(CrawlerProgress.HAT_MISSILE).contains("homing"),
		"the hex hat says it seeks the nearest mob")
	_free_hat_missiles()
	_clear_stray_crawler_mobs()
	var prey := _MissileDummy.new()
	add_child(prey)
	prey.global_position = _player.combat_position() + Vector3(1.4, 0.0, 0.2)
	_player._tick_missile_hat(0.02)
	var first_volley := _hat_missiles()
	_expect(first_volley.size() == CrawlerRules.MISSILE_HAT_COUNT,
		"the worn hex hat looses a volley at the nearest mob")
	_free_hat_missiles()
	prey.global_position = _player.combat_position() + Vector3(40.0, 12.0, 0.0)
	_player._missile_cooldown = 0.0
	_player._tick_missile_hat(0.02)
	_expect(_hat_missiles().size() == CrawlerRules.MISSILE_HAT_COUNT,
		"the hex hat still looses at a mob past the old 24 m bubble")
	_free_hat_missiles()
	prey.global_position = _player.combat_position() + Vector3(1.4, 0.0, 0.2)
	_player._missile_cooldown = 0.0
	_player._tick_missile_hat(0.02)
	first_volley = _hat_missiles()
	_advance_hat_missiles(first_volley, 0.8)
	_expect(prey.taken > 0.0, "the hex missiles home in and hit that mob")
	_free_hat_missiles()
	_player._tick_missile_hat(0.02)
	_expect(_hat_missiles().is_empty(),
		"the hex hat waits before the next volley")
	progress.gold += CrawlerProgress.hat_price(CrawlerProgress.HAT_MISSILE) \
		+ CrawlerProgress.HAT_MERGE_PRICE
	_expect(progress.buy_hat(CrawlerProgress.HAT_MISSILE),
		"the hat stall sells a second hex hat")
	var hex_copy := progress.worn_hat
	_expect(progress.merge_hats(CrawlerProgress.HAT_MISSILE, hex_copy),
		"two hex hats can be stacked")
	_expect(progress.missile_count() == CrawlerRules.MISSILE_HAT_COUNT
			+ CrawlerRules.MISSILE_HAT_EXTRA_PER_RANK,
		"a stacked hex hat looses more missiles")
	_expect(progress.hat_title(progress.worn_hat).contains("Twin"),
		"stacking hex hats doubles the name")
	_expect(progress.hat_description(progress.worn_hat).contains("5"),
		"the stacked description names the larger volley")
	_free_hat_missiles()
	_player._missile_cooldown = 0.0
	_player._tick_missile_hat(0.02)
	_expect(_hat_missiles().size() == progress.missile_count(),
		"the stacked hex hat looses the larger volley")
	_free_hat_missiles()
	prey.free()
	progress.note_worn(CrawlerProgress.HAT_ID)
	_player.refresh_crawler_look()
	_player._tick_missile_hat(0.0)
	_expect(not progress.wearing_missile_hat(),
		"taking the hex hat off stops the volley")
	_check_kill_loot(progress)
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
	var before_flight := _player.crawler_flight_seconds()
	progress.gold += CrawlerProgress.HAT_MERGE_PRICE
	_expect(progress.merge_hats(CrawlerProgress.HAT_ID, CrawlerProgress.HAT_LUCK),
		"gold fuses the gale cap into the fortune cap's effects")
	var fused := progress.worn_hat
	_expect(not fused.is_empty() and not progress.owns_hat(CrawlerProgress.HAT_LUCK),
		"the merge spends both source hats")
	_expect(progress.hat_title(fused).contains("Gale")
			and progress.hat_title(fused).contains("Fortune"),
		"the fused hat takes a new compound name")
	_expect(progress.hat_description(fused).contains("Luck")
			or progress.hat_description(fused).contains("luck"),
		"the fused description names the fortune effect")
	_expect(_player.crawler_flight_seconds() >= before_flight,
		"keeping the gale model keeps the gale flight boost")
	_expect(progress.luck_rank() >= 1.0 + CrawlerProgress.HAT_LUCK_BONUS,
		"the fused gale still grants the fortune luck")
	progress.gold += CrawlerProgress.HAT_PRICE + CrawlerProgress.HAT_MERGE_PRICE
	_expect(progress.buy_hat(CrawlerProgress.HAT_ID),
		"the hat stall sells a second gale cap")
	var gale_copy := progress.worn_hat
	_expect(gale_copy != fused and progress.owns_hat(fused),
		"the second gale is a separate owned hat")
	var stacked_flight := _player.crawler_flight_seconds()
	_expect(progress.merge_hats(fused, gale_copy),
		"two gale effects can be stacked into the fused hat")
	fused = progress.worn_hat
	_expect(progress.hat_title(fused).contains("Twin"),
		"stacking the same hat doubles the name")
	_expect(_player.crawler_flight_seconds() > stacked_flight,
		"two gale ranks jump flight twice as hard")
	progress.gold += CrawlerProgress.HAT_MERGE_PRICE
	_expect(progress.merge_hats(fused, CrawlerProgress.HAT_WARD),
		"a fused hat can merge again")
	fused = progress.worn_hat
	_expect(progress.wearing_ward_hat() and progress.wearing_luck_hat()
			and progress.wearing_shop_hat(),
		"chained merges keep every fused effect")
	_expect(progress.ward_charges() == 1, "one ward rank still takes one hit")
	_player.refresh_crawler_look()
	_expect(_player.ward_active(), "the fused halo still raises a bubble")
	_expect(not progress.merge_hats(fused, fused),
		"a hat cannot merge with itself")
	progress.gold = 0
	_expect(not progress.merge_hats(fused, CrawlerProgress.HAT_KIT),
		"a dry purse cannot fuse hats")
	for item_id: String in [
		CrawlerProgress.HAT_MINE, CrawlerProgress.HAT_VAMPIRE,
		CrawlerProgress.HAT_PHASE, CrawlerProgress.HAT_ORDINANCE,
		CrawlerProgress.HAT_RUBBER, CrawlerProgress.HAT_LEARNED,
		CrawlerProgress.HAT_FOOL, CrawlerProgress.HAT_REPEATER,
		CrawlerProgress.HAT_JUKE, CrawlerProgress.HAT_BAZAAR,
	]:
		progress.gold += CrawlerProgress.hat_price(item_id)
		_expect(progress.buy_hat(item_id), "gold buys %s" % ItemDB.title(item_id))
		_player.refresh_crawler_look()
	_expect(progress.wearing_bazaar_hat(), "buying the last new hat puts it on")
	_expect(progress.shops_are_unlimited()
			and progress.open_shops_for("22").size() == CrawlerProgress.SHOP_IDS.size(),
		"the bazaar fedora opens every stall while it is on")
	_expect(not progress.shops_unlimited,
		"wearing the fedora does not set the rest-stop toggle")
	progress.note_worn(CrawlerProgress.HAT_LEARNED)
	_player.refresh_crawler_look()
	_expect(_player.abilities.size() == CrawlerRules.ABILITY_SLOTS_MAX,
		"the learned cap opens a fourth ability slot in the field")
	progress.note_worn(CrawlerProgress.HAT_MINE)
	_player.refresh_crawler_look()
	_free_hat_mines()
	_player._mine_cooldown = 0.0
	_player._tick_mine_hat(0.02)
	_expect(_hat_mines().size() == 1, "the worn trail cap drops a mine")
	_free_hat_mines()


func _check_level_burst() -> void:
	const BURST := preload("res://ui/combat/crawler_level_burst.gd")
	var hud := _player.hud
	_expect(hud != null, "crawler player has a HUD for the level-up sting")
	if hud == null:
		return
	_expect(BURST.HOLD >= 0.8 and BURST.HOLD <= 1.8,
		"level-up holds briefly without pausing")
	_player.crawler_progress.ranks[CrawlerProgress.STAT_DAMAGE] = 0.0
	_player.crawler_progress.ranks[CrawlerProgress.STAT_DODGE] = 0.0
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
		"the spend board waits for the burst")
	_expect(not _player._menu_open, "the game stays live during the burst")
	_expect(_player.crawler_progress.unspent == 1,
		"solo level-up keeps the point for the spend board")
	_expect(is_zero_approx(_player.crawler_progress.rank_of(CrawlerProgress.STAT_DAMAGE)),
		"solo level-up does not auto-spend")
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
		"the burst leaves on its own")
	_expect(hud.get_node_or_null("CrawlerLevelMenu") != null,
		"solo level-up opens the spend board")
	_expect(_player._menu_open, "solo level-up pauses the run")
	var saved_solo := NetworkManager.is_single_player
	NetworkManager.is_single_player = false
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
	_player._on_crawler_leveled_up()
	_expect(_player.crawler_progress.unspent == 0, "coop level-up spends itself")
	_expect(is_equal_approx(_player.crawler_progress.rank_of(CrawlerProgress.STAT_DAMAGE),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_LEGENDARY)),
		"coop level-up takes the highest rarity")
	_expect(is_equal_approx(_player.crawler_progress.rank_of(CrawlerProgress.STAT_HEALTH),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_UNCOMMON)),
		"coop level-up also takes the next matching pref")
	_player._open_crawler_level_menu()
	var menus := 0
	for child: Node in hud.get_children():
		if child.name == "CrawlerLevelMenu":
			menus += 1
	_expect(menus == 1, "coop auto-claim does not spawn a second spend board")
	NetworkManager.is_single_player = saved_solo
	var menu := hud.get_node_or_null("CrawlerLevelMenu")
	if menu != null:
		menu.queue_free()
	_player.close_menu()
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.set_local_pause(false)
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
	var rewards := hud.find_child("AchievementCompleteRewards", true, false) as Label
	_expect(rewards != null and rewards.visible and rewards.text.contains("50 XP"),
		"the burst shows the instant global XP")
	_expect(rewards != null and not rewards.text.contains("5 Gems"),
		"the burst hides claimable gem rewards")
	if burst is Control:
		_expect(not (burst as Control).clip_contents,
			"the achievement explosion is not boxed by a HUD rectangle")
	if burst != null:
		burst._process(BURST.REWARD_HOLD)
	await get_tree().process_frame
	_expect(hud.get_node_or_null("AchievementBurst") == null,
		"the achievement burst leaves after its hold")


func _check_city_store() -> void:
	var stock := CrawlerProgress.shop_stock()
	_expect(stock.has("big") and stock.has("wobble") and stock.has("bubble")
			and stock.has("clip") and stock.has("endless")
			and stock.has("toxic") and stock.has("shock")
			and stock.has("charm") and stock.has("ice")
			and stock.has("bounce")
			and stock.has("impact_cast")
			and stock.has("homing"),
		"the city stock sells mods")
	_expect(not stock.has("starfire") and not stock.has("laser_eyes"),
		"the mod stall does not sell abilities")
	var abilities := CrawlerProgress.ability_stock()
	_expect(not CrawlerCatalog.has("grapple") and not CrawlerCatalog.has("lasso"),
		"grapple and lasso are not catalog abilities")
	_expect(abilities.has("laser_eyes") and abilities.has("kame")
			and abilities.has("nausicaa")
			and abilities.has("lightning")
			and abilities.has("starfire")
			and abilities.has("meteor_punch")
			and abilities.has("hero_punch")
			and abilities.has("nuke")
			and abilities.has("mini_nuke")
			and abilities.has("wall")
			and abilities.has("roar")
			and abilities.has("toxic_blast")
			and abilities.has("charming_aura")
			and abilities.has("freeze_blast")
			and abilities.has("overdrive"),
		"the ability stall sells the beam family, wall, the punches, the starters, the four roar blasts, and overdrive")
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
	var store_gold := menu.find_child("StoreGold", true, false) as Label
	_expect(store_gold != null and store_gold.visible
			and store_gold.text == "GOLD  %s" % _player.crawler_progress.gold_text()
			and store_gold.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT,
		"the city store names the purse in the upper right")
	var tab_row_1 := menu.find_child("StoreTabRow1", true, false) as HBoxContainer
	var tab_row_2 := menu.find_child("StoreTabRow2", true, false) as HBoxContainer
	_expect(tab_row_1 != null and tab_row_1.get_child_count() == 6,
		"the first store tab row holds six stalls")
	_expect(tab_row_2 != null and tab_row_2.get_child_count() == 6,
		"the second store tab row holds six stalls")
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
	_expect(buy != null and buy.get_node_or_null("RedGlowPanel") != null,
		"sale buttons sit inside a store rim")
	_expect(hat_icon != null and hat_icon.visible,
		"the hat stall shows a gale-cap icon")
	_expect(menu.find_child("HatPreviewFigure_crawler_gale_hat", true, false) == null,
		"hat tiles do not preview a worn player")
	_expect(hat_grid != null and hat_grid.columns >= 3,
		"hats sit in a multi-column tile grid")
	_expect(ward_tile != null and ward_tile.visible,
		"the hat stall also sells the ward halo")
	_expect(ward_tile != null and ward_tile.get_node_or_null("RedGlowPanel") != null,
		"sale tiles sit inside a store rim")
	var luck_hat := menu.find_child("HatTile_crawler_luck_hat", true, false) as Control
	_expect(luck_hat != null and luck_hat.visible,
		"the hat stall also sells the fortune cap")
	var kit_hat := menu.find_child("HatTile_crawler_kit_hat", true, false) as Control
	_expect(kit_hat != null and kit_hat.visible,
		"the hat stall also sells the bench visor")
	var hex_hat := menu.find_child("HatTile_crawler_missile_hat", true, false) as Control
	_expect(hex_hat != null and hex_hat.visible,
		"the hat stall also sells the hex hat")
	_expect(menu.find_child("HatTile_crawler_mine_hat", true, false) != null,
		"the hat stall also sells the trail cap")
	_expect(menu.find_child("HatTile_crawler_vampire_hat", true, false) != null,
		"the hat stall also sells the vampire horns")
	_expect(menu.find_child("HatTile_crawler_phase_hat", true, false) != null,
		"the hat stall also sells the phase helm")
	_expect(menu.find_child("HatTile_crawler_ordinance_hat", true, false) != null,
		"the hat stall also sells the ordinance helm")
	_expect(menu.find_child("HatTile_crawler_rubber_hat", true, false) != null,
		"the hat stall also sells the rubber beanie")
	_expect(menu.find_child("HatTile_crawler_learned_hat", true, false) != null,
		"the hat stall also sells the learned cap")
	_expect(menu.find_child("HatTile_crawler_juke_hat", true, false) != null,
		"the hat stall also sells the juke cap")
	_expect(menu.find_child("HatTile_crawler_repeater_hat", true, false) != null,
		"the hat stall also sells the repeater cap")
	_expect(menu.find_child("HatTile_crawler_bazaar_hat", true, false) != null,
		"the hat stall also sells the bazaar fedora")
	_expect(menu.find_child("LuckTile", true, false) == null,
		"luck is not for sale in the hat stall")
	progress.owned_hats = held_hats
	progress.worn_hat = worn
	menu._clear_list()
	menu._fill_hats(progress, progress.gold)
	var sold := menu.find_child("HatActButton", true, false) as Button
	_expect(sold != null and sold.visible and sold.text == "BUY",
		"owned hats can still be bought again")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.CAPS,
		"the next tab is Caps for Sale")
	menu._clear_list()
	menu._fill_caps_for_sale(progress, progress.gold)
	var cap_grid := menu.find_child("StoreCapGrid", true, false) as GridContainer
	_expect(cap_grid != null or menu.find_child("StoreEmpty", true, false) != null,
		"Caps for Sale lists owned hats or explains the empty stall")
	if progress.owned_hats.size() >= 2:
		var first := progress.owned_hats[0]
		var second := progress.owned_hats[1]
		var pick_a := menu.find_child("CapAct_%s" % first, true, false) as Button
		_expect(pick_a != null, "owned hats can be picked for a merge")
		if pick_a != null:
			pick_a.pressed.emit()
		var pick_b := menu.find_child("CapAct_%s" % second, true, false) as Button
		_expect(pick_b != null, "the second owned hat can be picked")
		if pick_b != null:
			pick_b.pressed.emit()
		var merge_a := menu.find_child("CapMergeKeepA", true, false) as Button
		_expect(merge_a != null and merge_a.visible,
			"two picks offer a merge into the first model")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.CAPES,
		"the next tab is the cape stall")
	var held_capes := progress.owned_capes.duplicate()
	var worn_cape := progress.worn_cape
	progress.owned_capes = PackedStringArray()
	progress.worn_cape = ""
	menu._clear_list()
	menu._fill_capes(progress, CrawlerProgress.CAPE_PRICE)
	var cape_buy := menu.find_child("CapeActButton", true, false) as Button
	var cape_icon := menu.find_child("CapeIcon_crawler_plain_cape", true, false) as TextureRect
	var cape_grid := menu.find_child("StoreCapeGrid", true, false) as GridContainer
	var cape_tile := menu.find_child("CapeTile_crawler_plain_cape", true, false) as Control
	_expect(cape_buy != null and cape_buy.visible and cape_buy.text == "BUY",
		"the cape stall shows a BUY button")
	_expect(cape_icon != null and cape_icon.visible,
		"the cape stall shows a plain-cape icon")
	_expect(cape_grid != null and cape_grid.columns >= 3,
		"capes sit in a multi-column tile grid")
	_expect(cape_tile != null and cape_tile.visible,
		"the cape stall sells the plain white cape")
	_expect(menu.find_child("CapeTile_crawler_gold_cape", true, false) != null,
		"the cape stall also sells the gold cape")
	_expect(menu.find_child("CapeTile_crawler_fool_cape", true, false) == null,
		"the cape stall no longer sells the fool's cape")
	_expect(CrawlerProgress.cape_stock() == PackedStringArray([
		CrawlerProgress.CAPE_ID, CrawlerProgress.CAPE_GOLD
	]), "the cape stall stocks the plain cape and the gold cape")
	progress.owned_capes = held_capes
	progress.worn_cape = worn_cape
	menu._clear_list()
	menu._fill_capes(progress, progress.gold)
	var cape_sold := menu.find_child("CapeActButton", true, false) as Button
	_expect(cape_sold != null and cape_sold.visible and cape_sold.text == "SOLD",
		"a bought cape is marked sold")
	_expect(cape_sold.disabled, "sold capes cannot be taken off in the store")
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
	CrtType.dress_tree(menu)
	var wobble_crt := CrtType.host_of(wobble_icon)
	_expect(wobble_crt != null and wobble_crt.chromatic() < 0.5,
		"store mod icons drop chromatic aberration")
	_expect(wobble_crt != null and wobble_crt.glitch > 0.0
			and wobble_crt.glitch < CrtType.MENU_TYPE_GLITCH,
		"store mod tiles keep a lighter tear")
	var wobble_types := menu.find_child("TypeMarks_wobble", true, false) as Control
	var wobble_beam := wobble_types.find_child("TypeMark_beam", true, false) as TextureRect \
		if wobble_types != null else null
	_expect(wobble_types != null and wobble_beam != null and wobble_beam.visible
			and wobble_beam.texture == CrawlerCatalog.type_icon("beam")
			and wobble_types.get_child_count() == 1,
		"ability-specific mods show the matching type icon")
	_expect(menu.find_child("ModTile_big", true, false) != null,
		"the mods stall also sells big as a tile")
	_expect(menu.find_child("ModTile_bubble", true, false) != null,
		"the mods stall also sells bubble as a tile")
	_expect(menu.find_child("ModTile_clip", true, false) != null,
		"the mods stall also sells clip as a tile")
	_expect(menu.find_child("ModTile_endless", true, false) != null,
		"the mods stall also sells endless as a tile")
	var bubble_types := menu.find_child("TypeMarks_bubble", true, false) as Control
	_expect(bubble_types != null
			and bubble_types.find_child("TypeMark_beam", true, false) != null
			and bubble_types.find_child("TypeMark_shockwave", true, false) != null
			and bubble_types.find_child("TypeMark_projectile", true, false) != null
			and bubble_types.find_child("TypeMark_field", true, false) != null,
		"mods that fit several types show every matching type icon")
	var clip_types := menu.find_child("TypeMarks_clip", true, false) as Control
	_expect(clip_types != null
			and clip_types.find_child("TypeMark_limited", true, false) != null,
		"limited mods show the limited type icon")
	_expect(menu.find_child("TypeMarks_big", true, false) == null,
		"generic mods do not show type icons")
	_expect(menu.find_child("ModHostIcon_wobble", true, false) == null
			and menu.find_child("ModHostIcon_big", true, false) == null,
		"mod tiles no longer overlay a specific host ability icon")
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
	var eyes_types := menu.find_child("TypeMarks_laser_eyes", true, false) as Control
	var eyes_beam := eyes_types.find_child("TypeMark_beam", true, false) as TextureRect \
		if eyes_types != null else null
	_expect(eyes_beam != null and eyes_beam.visible
			and eyes_beam.texture == CrawlerCatalog.type_icon("beam"),
		"ability tiles show their type icon")
	var fus_types := menu.find_child("TypeMarks_fus", true, false) as Control
	_expect(fus_types != null
			and fus_types.find_child("TypeMark_projectile", true, false) != null,
		"projectile abilities show the projectile type icon")
	_expect(menu.find_child("AbilityTile_lightning", true, false) != null,
		"the ability stall sells lightning")
	_expect(menu.find_child("AbilityTile_kame", true, false) != null,
		"the ability stall sells kame")
	_expect(menu.find_child("AbilityTile_wall", true, false) != null,
		"the ability stall sells wall")
	_expect(star_buy != null and star_buy.visible,
		"the ability stall sells starfire")
	_expect(menu.find_child("AbilityTile_meteor_punch", true, false) != null,
		"the ability stall sells meteor punch")
	_expect(menu.find_child("AbilityTile_hero_punch", true, false) != null,
		"the ability stall sells hero punch")
	_expect(menu.find_child("AbilityTile_nuke", true, false) != null,
		"the ability stall sells nuke")
	_expect(menu.find_child("AbilityTile_mini_nuke", true, false) != null,
		"the ability stall sells mini nuke")
	_expect(menu.find_child("AbilityTile_fus", true, false) != null,
		"the ability stall sells fus")
	_expect(menu.find_child("AbilityTile_roar", true, false) != null
			and menu.find_child("AbilityTile_toxic_blast", true, false) != null
			and menu.find_child("AbilityTile_charming_aura", true, false) != null
			and menu.find_child("AbilityTile_freeze_blast", true, false) != null,
		"the ability stall sells roar, toxic blast, charming aura, and freeze blast")
	_expect(menu.find_child("AbilityTile_overdrive", true, false) != null,
		"the ability stall sells overdrive")
	_expect(menu.find_child("AbilityTile_healing_field", true, false) != null
			and menu.find_child("AbilityTile_static_field", true, false) != null,
		"the ability stall sells healing field")
	var heal_types := menu.find_child("TypeMarks_healing_field", true, false) as Control
	_expect(heal_types != null
			and heal_types.find_child("TypeMark_field", true, false) != null,
		"healing field shows the field type icon")
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
	var upgrade_types := menu.find_child("StoreUpgradeTypes", true, false) as Control
	var upgrade_beam := upgrade_types.find_child("TypeMark_beam", true, false) as TextureRect \
		if upgrade_types != null else null
	_expect(upgrade_beam != null and upgrade_beam.visible
			and upgrade_beam.texture == CrawlerCatalog.type_icon("beam"),
		"the selected upgrade card shows its type icon")
	var first_grid := menu.find_child("StoreUpgradeRows", true, false) as Control
	await get_tree().process_frame
	_expect(_store_upgrades_fit(detail, first_grid),
		"laser eye upgrades fit the lower half without overlap")
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
	var upgrade_grid := menu.find_child("StoreUpgradeRows", true, false) as Control
	var damage_tile := menu.find_child("UpgradeTile_damage", true, false) as Control
	var bag_center := menu.find_child("StoreInventoryCenter", true, false) as Control
	_expect(upgrade_grid != null and int(upgrade_grid.get_meta(&"columns", 0)) >= 3,
		"upgrades sit in a multi-column tile grid")
	_expect(menu.find_child("StoreUpgradeScroll", true, false) == null,
		"upgrade tiles are not in a scroll")
	damage = menu.find_child("UpgradeAct_damage", true, false) as Button
	_expect(damage_tile != null and damage != null and damage.is_inside_tree()
			and damage_tile.is_ancestor_of(damage)
			and damage.text == "UPGRADE",
		"the upgrade button lives inside its tile")
	await get_tree().process_frame
	await get_tree().process_frame
	damage = menu.find_child("UpgradeAct_damage", true, false) as Button
	_expect(damage != null and _upgrade_act_width(damage) >= 48.0,
		"the upgrade button is wide enough to show UPGRADE")
	_expect(_store_upgrades_fit(detail, upgrade_grid),
		"starfire upgrades fit the lower half without overlap")
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
	menu._show_body(false, true, false)
	menu._fill_inventory()
	var inv_page := menu.find_child("StoreInventoryPage", true, false) as Control
	_expect(inv_page != null and inv_page.visible,
		"inventory shows the city stash")
	_expect(inv_page.find_child("CrawlerAbilityTile_0", true, false) != null
			and inv_page.find_child("CrawlerBag_0", true, false) != null,
		"inventory shows the player loadout on top")
	_expect(inv_page.find_child("CityAbilityTile_0", true, false) != null
			and inv_page.find_child("CityBag_0", true, false) != null,
		"inventory shows a matching city loadout below")
	var note := menu.find_child("StoreEmpty", true, false) as Label
	_expect(note == null or not note.visible,
		"inventory is a stash page, not a placeholder")
	var stashed := false
	var bar := kit.ability_bar()
	if bar != null:
		for index in bar.size():
			var hosted := kit.equipped_card(index)
			if hosted == null or hosted.id != "starfire":
				continue
			stashed = kit.move_card(
				CrawlerKit.SOURCE_EQUIP,
				index,
				CrawlerKit.SOURCE_CITY_EQUIP,
				0
			)
			break
	_expect(stashed, "the city stash accepts a moved ability")
	menu._fill_inventory()
	var city_tile := inv_page.find_child("CityAbilityTile_0", true, false) as CrawlerAbilityTile
	_expect(city_tile != null and city_tile.card() != null
			and city_tile.card().id == "starfire",
		"the city row holds the stored ability")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.LOCKER,
		"the next tab is the locker")
	menu._show_body(false, false, true)
	menu._fill_locker()
	var locker_page := menu.find_child("StoreLockerPage", true, false) as CrawlerStoreLockerPage
	_expect(locker_page != null and locker_page.visible,
		"locker shows the deposit pane")
	_expect(locker_page.find_child("CrawlerAbilityTile_0", true, false) != null,
		"locker shows player abilities")
	_expect(locker_page.find_child("LockerAbilityTile_0", true, false) != null,
		"locker has one deposit slot")
	_expect(locker_page.find_child("LockerDepositButton", true, false) != null,
		"locker shows a paid deposit button")
	_expect(locker_page.find_child("LockerWithdrawButton", true, false) != null,
		"locker shows a paid withdraw button")
	_expect(locker_page.find_child("CrawlerBag_0", true, false) == null,
		"locker hides the mod bag")
	var locker_tile := locker_page.find_child("LockerAbilityTile_0", true, false) \
		as CrawlerAbilityTile
	progress.gold += CrawlerProgress.LOCKER_PRICE
	var locker_gold := progress.gold
	var locked := locker_page.deposit_selected()
	_expect(locked, "the locker accepts one ability")
	_expect(progress.gold == locker_gold - CrawlerProgress.LOCKER_PRICE,
		"depositing spends locker gold")
	locker_page.refresh()
	_expect(locker_tile != null and locker_tile.card() != null
			and locker_tile.card().id == "laser_eyes",
		"the locker holds the deposited ability")
	_expect(kit.equipped_card(0) == null,
		"depositing in the locker removes it from the loadout")
	_expect(str(CrawlerMeta.locker_card().get("id", "")) == "laser_eyes",
		"the locker writes the card to meta")
	CrawlerMeta.set_locker_card({})
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.QUESTS,
		"the next tab is the quest stall")
	menu._clear_list()
	menu._fill_quests()
	_expect(menu.find_child("QuestAct_office_tower", true, false) != null,
		"the quest stall sells the tower")
	_expect(menu.find_child("QuestAct_castle", true, false) != null,
		"the quest stall sells the castle")
	_expect(menu.find_child("QuestAct_boss", true, false) != null,
		"the quest stall sells one boss location")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.MARKET,
		"the next tab is the black market")
	menu._clear_list()
	menu._fill_market()
	var ticket := menu.find_child("TicketAct", true, false) as Button
	_expect(ticket != null and ticket.visible and ticket.text == "BUY",
		"the black market sells respawn tickets")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.RESTSTOP,
		"the next tab is the reststop")
	_player.stats.set_health(_player.maximum_health() * 0.4)
	menu._clear_list()
	menu._fill_reststop()
	var rest_hp := menu.find_child("RestAct_health", true, false) as Button
	_expect(rest_hp != null and rest_hp.visible and rest_hp.text == "FREE",
		"the first health rest is free")
	var rest_ammo := menu.find_child("RestAct_ammo", true, false) as Button
	_expect(rest_ammo != null and rest_ammo.visible,
		"the reststop sells an ammo refill")
	var rest_gold := menu.find_child("RestAct_gold", true, false) as Button
	_expect(rest_gold != null and rest_gold.visible and rest_gold.text == "SET"
			and not rest_gold.disabled,
		"the reststop can grant infinite gold")
	var rest_stores := menu.find_child("RestAct_stores", true, false) as Button
	_expect(rest_stores != null and rest_stores.visible
			and rest_stores.text == "SET" and not rest_stores.disabled,
		"the reststop can make stores infinite")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.DUALS,
		"the last tab is Duals")
	menu._clear_list()
	menu._fill_duals()
	var duals := menu.find_child("StoreEmpty", true, false) as Label
	_expect(duals != null and duals.visible
			and duals.text.contains("co-op")
			and duals.text.contains("solo"),
		"solo Duals explains it is a co-op fight")
	var train := menu.find_child("DualsTrain", true, false) as Button
	_expect(train != null and train.visible and not train.disabled,
		"solo Duals still offers a training field")
	menu.cycle_tab(1)
	_expect(menu.current_tab() == CrawlerFieldMenu.Tab.HATS,
		"tabs wrap back to the hat stall")
	menu.queue_free()


func _check_reststop() -> void:
	var progress := _player.crawler_progress
	var kit := _player.crawler_kit
	_expect(progress != null and kit != null, "the reststop reads the run ledger")
	if progress == null or kit == null:
		return
	progress.rested_health_cities = PackedStringArray()
	progress.rested_ammo_cities = PackedStringArray()
	_player.global_position = Vector3(400.0, 0.0, 0.0)
	_expect(not _player.buy_crawler_rest_health()
			and not _player.buy_crawler_rest_ammo(),
		"the reststop only sells inside a city")
	var ring = CITY_RING.new()
	ring.configure(7, Transform3D.IDENTITY)
	add_child(ring)
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_expect(_player.in_crawler_city() and _player.crawler_city_key() == "7",
		"the reststop keys the first free rest to this city")
	var max_hp := _player.maximum_health()
	_player.stats.set_health(max_hp * 0.4)
	var gold := progress.gold
	_expect(_player.buy_crawler_rest_health(), "the first health rest is free")
	_expect(is_equal_approx(_player.health(), max_hp),
		"a health rest fills vitals")
	_expect(progress.gold == gold, "the first health rest spends no gold")
	_expect(progress.rested_health_cities.has("7"),
		"the first health rest marks this city")
	_player.stats.set_health(max_hp * 0.4)
	progress.gold = CrawlerProgress.REST_HEALTH_PRICE
	_expect(_player.buy_crawler_rest_health(), "later health rests cost gold")
	_expect(progress.gold == 0, "a paid health rest spends the listed gold")
	_expect(is_equal_approx(_player.health(), max_hp),
		"a paid health rest still fills vitals")
	_player.stats.set_health(max_hp * 0.4)
	progress.gold = CrawlerProgress.REST_HEALTH_PRICE - 1
	_expect(not _player.buy_crawler_rest_health(),
		"a short purse cannot buy another health rest")
	_expect(_player.health() < max_hp, "an unpaid rest does not heal")
	ring.patch_id = 8
	progress.gold = 0
	_expect(_player.crawler_city_key() == "8", "a new city uses a new rest key")
	_expect(_player.buy_crawler_rest_health(), "a new city is free again")
	_expect(is_equal_approx(_player.health(), max_hp)
			and progress.gold == 0,
		"the first rest in a new city spends no gold")
	_expect(kit.shop_grant("nuke"), "the reststop can refill a nuke")
	var nuke := kit.equipped_card(1)
	if nuke == null or nuke.id != "nuke":
		for card: CrawlerCard in kit.owned_cards():
			if card != null and card.id == "nuke":
				nuke = card
				break
	_expect(nuke != null and nuke.id == "nuke", "a nuke is ready to refill")
	if nuke != null:
		kit.sync_ammo(nuke)
		nuke.extra_stats["ammo"] = 0
		progress.gold = 0
		_expect(kit.needs_ammo_refill(), "an empty nuke needs a rest")
		_expect(_player.buy_crawler_rest_ammo(), "the first ammo rest is free")
		_expect(kit.ammo_left(nuke) == kit.ammo_max(nuke)
				and progress.gold == 0
				and progress.rested_ammo_cities.has("8"),
			"the first ammo rest fills magazines for free")
		nuke.extra_stats["ammo"] = 0
		progress.gold = CrawlerProgress.REST_AMMO_PRICE
		_expect(_player.buy_crawler_rest_ammo(), "later ammo rests cost gold")
		_expect(kit.ammo_left(nuke) == kit.ammo_max(nuke)
				and progress.gold == 0,
			"a paid ammo rest spends the listed gold")
		nuke.extra_stats["ammo"] = 0
		progress.gold = CrawlerProgress.REST_AMMO_PRICE - 1
		_expect(not _player.buy_crawler_rest_ammo()
				and kit.ammo_left(nuke) == 0,
			"a short purse cannot buy another ammo rest")
	progress.gold = 0
	_expect(_player.grant_crawler_rest_gold()
			and progress.gold_unlimited
			and progress.gold == 0
			and progress.has_gold(CrawlerRules.SANDBOX_GOLD)
			and progress.gold_text() == "INF",
		"the reststop can grant infinite gold")
	var held := progress.gold
	_expect(progress.spend_gold(80) and progress.gold == held,
		"infinite gold does not empty the purse")
	_expect(_player.set_crawler_unlimited_gold(false)
			and not progress.gold_unlimited
			and not progress.has_gold(1)
			and progress.gold == held,
		"infinite gold can be switched off")
	_expect(_player.grant_crawler_rest_gold() and progress.gold_unlimited,
		"infinite gold can be switched back on")
	_expect(_player.enable_crawler_unlimited_shops()
			and progress.shops_unlimited
			and not progress.uses_limited_shop("8"),
		"the reststop can keep every stall in stock")
	var restored := CrawlerProgress.new()
	restored.from_dict(progress.to_dict())
	_expect(restored.rested_health_cities.has("7")
			and restored.rested_health_cities.has("8")
			and restored.rested_ammo_cities.has("8"),
		"rested cities persist")
	_expect(restored.shops_unlimited and restored.gold_unlimited
			and restored.gold == progress.gold,
		"the reststop gold grant and infinite stores persist")
	progress.set_shops_unlimited(false)
	progress.set_gold_unlimited(false)
	progress.gold = 0
	progress.remember()
	ring.queue_free()
	_player.global_position = Vector3(400.0, 0.0, 0.0)
	await get_tree().process_frame


func _check_game_menu_items() -> void:
	var progress := _player.crawler_progress
	_expect(progress != null, "Items tab reads the run ledger")
	if progress == null:
		return
	var held := progress.respawn_tickets
	progress.respawn_tickets = 2
	if _player.hotbar != null:
		_player.hotbar.set_item(0, "sword")
	var menu := GameMenu.new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	var items_tab := menu.find_child("TabItems", true, false) as Button
	_expect(items_tab != null and items_tab.text == "ITEMS",
		"the tab menu has an Items tab")
	menu.show_tab(GameMenu.Tab.ITEMS)
	await get_tree().process_frame
	_expect(menu.current_tab() == GameMenu.Tab.ITEMS,
		"Items opens as its own page")
	var page := menu.find_child("RedCataloguePage", true, false) as RedCataloguePage
	_expect(page != null, "Items uses the catalogue page")
	_expect(menu.find_child("Filter_weapon", true, false) == null,
		"Items has no Weapons filter")
	var ticket := menu.find_child(
		"OwnedItem_00_crawler_respawn_ticket", true, false) as RedItemSlot
	_expect(ticket != null and ticket.visible
			and ticket.item_id() == CrawlerProgress.TICKET_ID
			and ticket.badge == "2",
		"Items lists held respawn tickets")
	var listed: PackedStringArray = PackedStringArray()
	if page != null:
		var grid := page.find_child("OwnedItemGrid", true, false)
		if grid != null:
			for child: Node in grid.get_children():
				if child is RedItemSlot:
					var slot := child as RedItemSlot
					if not slot.item_id().is_empty():
						listed.append(slot.item_id())
	_expect(not listed.has("sword"),
		"Items does not list leftover swords")
	var equip := menu.find_child("EquipAction", true, false) as HoldActionButton
	var drop := menu.find_child("DropAction", true, false) as Button
	_expect(equip != null and equip.disabled,
		"a ticket cannot be equipped")
	_expect(drop != null and drop.disabled,
		"a ticket cannot be dropped")
	progress.respawn_tickets = held
	if _player.hotbar != null:
		_player.hotbar.set_item(0, "")
	menu.queue_free()
	await get_tree().process_frame


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
	CrawlerProgress.session_payload["tickets"] = 0
	_player._die(null)
	await get_tree().process_frame
	var screen := _player.death_screen()
	_expect(screen != null and screen.title_text() == DeathScreen.GAME_OVER_TITLE,
		"crawler death says game over")
	_expect(screen.home_button() != null
			and screen.home_button().visible
			and screen.home_button().text == DeathScreen.HOME_LABEL
			and screen.respawn_button() != null
			and screen.respawn_button().visible
			and screen.respawn_button().text == DeathScreen.RESPAWN_LABEL,
		"GAME OVER offers HOME and a free RESPAWN")
	_expect(screen.summary_text().contains("killed")
			and screen.summary_text().contains("gem"),
		"game over lists the run")
	screen.finish_recap()
	var recap := screen.recap()
	_expect(not recap.is_empty() and int(recap.get("score", {}).get("total", 0)) > 0,
		"game over pays global XP for the expedition")
	var xp_bar := screen.find_child("RunXpBar", true, false) as ProgressBar
	var xp_label := screen.find_child("RunXpLabel", true, false) as Label
	_expect(xp_bar != null and xp_label != null and xp_label.text.contains("LV"),
		"game over fills a global XP bar")
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.custom_minimum_size = Vector2(1280.0, 720.0)
	screen.size = Vector2(1280.0, 720.0)
	for _settle: int in 5:
		await get_tree().process_frame
		screen._fit_plate()
	_expect(_death_home_is_on_plate(screen),
		"game over keeps HOME and RESPAWN on the plate")
	var squeeze := DeathScreen.new()
	add_child(squeeze)
	squeeze.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	squeeze.custom_minimum_size = Vector2(1280.0, 640.0)
	squeeze.size = Vector2(1280.0, 640.0)
	squeeze.present_crawler(
		"Killed by Rhino: Meteor Strike",
		"23 MOBS KILLED\n1 SITE DISCOVERED\nTIDE MARGIN\n54 GEMS EARNED",
		true,
		{
			"achievements": [
				{"id": "kills", "title": "KILL 10 MOBS", "rewards": PackedStringArray(["50 XP"])},
				{"id": "rank", "title": "RECRUIT", "rewards": PackedStringArray(["10 GEMS"])},
			],
			"score": {
				"total": 375,
				"lines": PackedStringArray([
					"215 FROM EXPEDITION XP",
					"45 FROM SITES DISCOVERED",
					"115 FROM MOBS KILLED",
				]),
			},
			"levels": [
				{"level": 3, "title": "", "title_changed": false},
				{"level": 4, "title": "", "title_changed": false},
				{"level": 5, "title": "Recruit", "title_changed": true},
			],
			"before": {"xp": 110.0},
			"after": {"xp": 485.0},
		})
	for _squeeze_settle: int in 5:
		await get_tree().process_frame
		squeeze._fit_plate()
	_expect(_death_home_is_on_plate(squeeze),
		"a tall recap still keeps HOME and RESPAWN on the plate")
	_expect(squeeze.find_child("RunLevel_5", true, false) != null,
		"levelled titles stay in the recap")
	squeeze.queue_free()
	var homes := [0]
	screen.home_requested.connect(func() -> void: homes[0] += 1)
	screen._process(DeathScreen.ARM_DELAY + 0.1)
	screen.home_button().pressed.emit()
	_expect(homes[0] == 1, "home ends the run")
	_expect(_player.is_dead(), "home does not revive the body")
	_player.respawn_at(_player.global_transform)
	await get_tree().process_frame
	_expect(_player.death_screen() == null and not _player.is_dead(),
		"a later revive clears the overlay")
	progress.respawn_tickets = 0
	_player._die(null)
	await get_tree().process_frame
	screen = _player.death_screen()
	var asked := [0]
	screen.respawn_requested.connect(func() -> void: asked[0] += 1)
	screen._process(DeathScreen.ARM_DELAY + 0.1)
	screen.respawn_button().pressed.emit()
	_expect(asked[0] == 1, "GAME OVER respawns without a ticket")
	_player.respawn_at(_player.global_transform)
	await get_tree().process_frame
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
		if path == PatchMonuments.TOWER_MODEL:
			site.monument_id = CrawlerProgress.QUEST_TOWER
		else:
			site.monument_id = CrawlerProgress.QUEST_CASTLE
		add_child(site)
		site.global_position = Vector3(7200.0, 12.0, -7200.0) \
				if path == PatchMonuments.TOWER_MODEL \
				else Vector3(8400.0, 12.0, -8400.0)
		hosts._attach_model(site, path)
		await get_tree().process_frame
		_expect(site.find_child("MonumentCollision", true, false) == null,
			"%s is not wrapped in a solid box" % path.get_file())
		_expect(_monument_has_trimesh(site),
			"%s uses walkable hull and floor collision" % path.get_file())
		_expect(not _monument_has_envelope_box(site),
			"%s has no building-sized box collider" % path.get_file())
		_expect(site.find_child("TidekinOffice", true, false) == null
				and site.find_child("CastleGarrison", true, false) == null,
			"%s does not seed site mobs" % path.get_file())
		site.queue_free()
	hosts.queue_free()
	await get_tree().process_frame


func _check_tidekin_office() -> void:
	for kind: String in TIDEKIN.VARIANTS:
		_expect(
			ResourceLoader.exists("%s%s.glb" % [TIDEKIN.MODEL_DIR, kind]),
			"%s Tidekin GLB is in the pack" % kind)
	var flock: Node = TIDEKIN_OFFICE.new()
	add_child(flock)
	flock.set_process(false)
	var wanted: int = TIDEKIN.VARIANTS.size() * TIDEKIN_OFFICE.PER_VARIANT
	_expect(int(flock.call("populate", 11)) == wanted,
		"a handful of each Tidekin walks the office")
	var counts := {}
	var bodied := 0
	var clips := 0
	for child: Node in flock.get_children():
		if child.get_script() != TIDEKIN:
			continue
		var kind := str(child.get_meta(&"tidekin_variant"))
		counts[kind] = int(counts.get(kind, 0)) + 1
		_expect(bool(child.get_meta(&"tidekin_friendly")),
			"%s is friendly" % kind)
		_expect(not child is CrawlerMob
				and not child.is_in_group(CrawlerMob.GROUP),
			"%s is not a combatant" % kind)
		if child.find_child("Model", true, false) != null:
			bodied += 1
		var animator := child.find_child("AnimationPlayer", true, false) \
				as AnimationPlayer
		if animator == null:
			continue
		var listed := ",".join(animator.get_animation_list()).to_lower()
		if listed.contains("walk") and listed.contains("idle"):
			clips += 1
	for kind: String in TIDEKIN.VARIANTS:
		_expect(int(counts.get(kind, 0)) == TIDEKIN_OFFICE.PER_VARIANT,
			"four %s Tidekin walk the floors" % kind)
	_expect(bodied == int(flock.call("live_count"))
			and clips == int(flock.call("live_count")),
		"Tidekin wear shrimp bodies with walk and idle clips")
	flock.call("clear_folk")
	_expect(int(flock.call("live_count")) == 0,
		"clearing the flock empties the office")

	var hosts := PatchMonuments.new()
	add_child(hosts)
	var site := PatchMonument.new()
	site.monument_id = CrawlerProgress.QUEST_TOWER
	add_child(site)
	site.global_position = Vector3(6400.0, 12.0, -6400.0)
	hosts._attach_model(site, PatchMonuments.TOWER_MODEL)
	await get_tree().process_frame
	_expect(site.get_node_or_null("Model") != null,
		"the office seats the adobe headquarters")
	_expect(site.find_child("TidekinOffice", true, false) == null,
		"the adobe office does not seed Tidekin")
	_expect(_monument_has_trimesh(site),
		"the adobe office keeps walkable collision")
	_expect(PatchMonument.find_id(CrawlerProgress.QUEST_TOWER) == site,
		"the office keep uses the seated tower")
	_expect(CrawlerRules.in_office_tower(site.global_position + Vector3(0.0, 2.0, 0.0))
			and not CrawlerRules.in_office_tower(
				site.global_position + Vector3(200.0, 0.0, 0.0)),
		"the office keep covers the tower and ends outside")
	site.queue_free()
	hosts.queue_free()
	flock.queue_free()


func _check_village_folk(ring: Node, place := "Neon Fjord") -> void:
	for kind: String in ["Luma", "Mochi", "Ember", "Cosmo", "Sunny"]:
		_expect(
			ResourceLoader.exists(
				"res://assets/runtime/characters/sproutlings/%s.glb" % kind),
			"%s lives in the meep pack" % kind)
	var folk := ring.find_child("VillageFolk", true, false)
	_expect(folk != null, "%s seats meep inhabitants" % place)
	if folk == null:
		return
	var wanderers := 0
	var keepers := 0
	var hidden := 0
	var bodied := 0
	var kinds := {}
	var shop_titles := {}
	for node: Node in ring.find_children("*", "Node3D", true, false):
		if not node.has_meta(&"sproutling_role"):
			continue
		var role := str(node.get_meta(&"sproutling_role"))
		var kind := str(node.get_meta(&"sproutling_variant"))
		var title := str(node.get_meta(&"sproutling_name"))
		kinds[kind] = true
		if node.find_child("Model", true, false) != null:
			bodied += 1
		if role == "wander":
			wanderers += 1
		elif role == "shop":
			keepers += 1
			if not title.is_empty():
				shop_titles[title] = true
			var tag := node.find_child("SproutlingName", true, false) as Label3D
			_expect(tag != null and tag.text == title.to_upper(),
				"%s stands behind a counter with a name" % title)
		elif role == "hidden":
			hidden += 1
			var tag := node.find_child("SproutlingName", true, false) as Label3D
			_expect(title == "Moss" and tag != null and tag.text == "MOSS",
				"the off-path local is named Moss")
			var here := node as Node3D
			_expect(Vector2(here.position.x, here.position.z).length() > 20.0,
				"Moss stands away from the plaza")
	_expect(wanderers >= 15 and wanderers <= 20,
		"about 15-20 meeps wander the village paths")
	_expect(keepers >= 5, "shop counters have stationed keepers")
	_expect(hidden == 1, "one meep stands off the beaten path")
	_expect(kinds.size() >= 5, "every meep variant lives in town")
	_expect(bodied >= wanderers + keepers + hidden,
		"meeps wear their onion bodies")
	_expect(shop_titles.has("Brim") and shop_titles.has("Map"),
		"hat and quest counters have named keepers")
	var village := ring.get_node_or_null("Village") as Node3D
	var path_ok := 0
	if village != null:
		var marks: Array[Vector3] = []
		for child: Node in village.get_children():
			if not child is Node3D:
				continue
			var label := str(child.name)
			if label.begins_with("Streetlight_") \
					or label.begins_with("Plaza_Bench_") \
					or label.begins_with("Lane_Bench_"):
				marks.append((child as Node3D).position)
		for node: Node in ring.find_children("*", "Node3D", true, false):
			if not node.has_meta(&"sproutling_role"):
				continue
			if str(node.get_meta(&"sproutling_role")) != "wander":
				continue
			var here := node as Node3D
			for mark: Vector3 in marks:
				if Vector2(here.position.x - mark.x, here.position.z - mark.z) \
						.length() <= 4.5:
					path_ok += 1
					break
	_expect(path_ok == wanderers, "wanderers spawn on the village paths")


func _check_stall_signs(ring: Node, place := "Neon Fjord") -> void:
	if ring == null or _player == null or _player.crawler_progress == null:
		return
	var city := str(ring.city_key()) if ring.has_method("city_key") else "city"
	var signed := _player.crawler_progress.signed_shops_for(city)
	var found := 0
	for shop_id: String in signed:
		if ring.find_child("StallSign_%s" % shop_id, true, false) != null:
			found += 1
	_expect(found >= 1, "%s floats icons over open stalls" % place)
	_expect(ring.find_child("StallSign_reststop", true, false) == null,
		"%s does not sign the rest stop" % place)
	_expect(ring.find_child("StallSign_locker", true, false) == null,
		"%s does not sign the lockers" % place)


func _interior_homes_inside(site: Node3D, path: String) -> bool:
	var host: Node
	var want := 12
	var span_x := CrawlerRules.OFFICE_KEEP_X + 4.0
	var span_z := CrawlerRules.OFFICE_KEEP_Z + 4.0
	var y_min := CrawlerRules.OFFICE_KEEP_Y_MIN
	var y_max := CrawlerRules.OFFICE_KEEP_Y_MAX
	if path == PatchMonuments.CASTLE_MODEL:
		host = site.find_child("CastleGarrison", true, false)
		want = 80
		span_x = 54.0
		span_z = 54.0
		y_min = -4.0
		y_max = 52.0
	else:
		host = site.find_child("TidekinOffice", true, false)
	if host == null or not host.has_method("home_count") \
			or int(host.call("home_count")) < want:
		return false
	var model := site.get_node_or_null("Model") as Node3D
	var frame := model if model != null else site
	var inside := 0
	for index in int(host.call("home_count")):
		var at: Variant = host.call("home_at", index)
		if typeof(at) != TYPE_VECTOR3:
			continue
		var local := frame.to_local(at)
		if absf(local.x) <= span_x and absf(local.z) <= span_z \
				and local.y >= y_min and local.y <= y_max:
			inside += 1
	return inside >= want


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
		var shape := (node as CollisionShape3D).shape
		if shape is ConcavePolygonShape3D \
				or shape is ConvexPolygonShape3D \
				or shape is BoxShape3D:
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
	_expect(BuildingFoundation.is_path_mesh(
			"GRAY ADOBE | 14 shaped pads + 23 winding connections"),
		"the authored gray path extrudes instead of paving its bounds")
	_expect(BuildingFoundation.is_shell_mesh("12 Skylight Commons")
			and not BuildingFoundation.is_shell_mesh("02 Plateau seat 1"),
		"house shells stay enterable and furniture stays a cheap hull")
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
	_expect(site.tint.is_equal_approx(CrawlerRules.OFFICE_WAYPOINT_TINT),
		"the office waypoint is blue")
	var keep := PatchMonument.new()
	keep.monument_id = CrawlerProgress.QUEST_CASTLE
	keep.title = "Stormwatch Castle"
	keep.waypoint = false
	keep.keepout_radius = 180.0
	add_child(keep)
	await get_tree().process_frame
	PatchMonument.enable_waypoint(CrawlerProgress.QUEST_CASTLE)
	_expect(keep.tint.is_equal_approx(CrawlerRules.CASTLE_WAYPOINT_TINT),
		"the castle waypoint is dark red")
	var boss := PatchMonument.new()
	boss.monument_id = "boss1"
	boss.title = "Boss Site"
	boss.waypoint = false
	boss.keepout_radius = CrawlerRules.BOSS_SITE_RADIUS
	add_child(boss)
	await get_tree().process_frame
	_expect(not boss.blocks_spawn(boss.global_position),
		"empty boss sites do not keep field packs off the pad")
	PatchMonument.enable_waypoint("boss1")
	_expect(boss.waypoint and boss.tint.is_equal_approx(CrawlerRules.BOSS_WAYPOINT_TINT),
		"the boss waypoint is dark purple")
	var tree_pad := PatchMonument.new()
	tree_pad.monument_id = "boss_tree"
	tree_pad.title = CrawlerProgress.QUEST_TREE_TITLE
	tree_pad.encounter = CrawlerRules.BOSS_ENCOUNTER_TREE
	tree_pad.waypoint = false
	tree_pad.keepout_radius = CrawlerRules.BOSS_SITE_RADIUS
	add_child(tree_pad)
	await get_tree().process_frame
	_expect(not tree_pad.blocks_spawn(tree_pad.global_position),
		"an idle giving tree pad still allows field packs")
	tree_pad.queue_free()
	boss.queue_free()
	keep.queue_free()
	site.queue_free()


func _check_run_field_packs() -> void:
	var held := CrawlerRun.payload.duplicate(true)
	var held_path := CrawlerRun.path
	CrawlerRun.payload = {
		"radius_m": 8000.0,
		"spawn": {"direction": {"x": 0.0, "y": 1.0, "z": 0.0}},
		"patches": [
			{
				"name": CrawlerRules.CITY_PATCH,
				"combo": "robot",
				"kinds": ["kestrel", "bastion", "weaver"],
				"level": 2,
				"direction": {"x": 0.0, "y": 0.0, "z": 1.0},
			},
			{
				"name": CrawlerRules.CASTLE_PATCH,
				"combo": "alien",
				"kinds": ["scout", "gray", "tanglemaw"],
				"level": 3,
				"direction": {"x": 1.0, "y": 0.0, "z": 0.0},
			},
			{
				"name": CrawlerRules.TOWER_PATCH,
				"combo": "demon",
				"kinds": ["gloam", "vesper", "threnody"],
				"level": 2,
				"direction": {"x": 0.0, "y": 0.0, "z": -1.0},
			},
		],
	}
	CrawlerRun.path = "res://dev/fake_run.json"
	CrawlerRun._index()
	_expect(CrawlerRules.city_patch(CrawlerRules.CITY_PATCH)
			and CrawlerRules.reserved_patch(CrawlerRules.CITY_PATCH),
		"a run still knows the authored city names")
	_expect(not CrawlerRules.castle_grounds(CrawlerRules.CASTLE_PATCH)
			and CrawlerRules.field_kinds(CrawlerRules.CASTLE_PATCH).has("scout"),
		"Long Shore fields its run pack instead of staying empty castle land")
	_expect(not CrawlerRules.robot_grounds(CrawlerRules.TOWER_PATCH)
			and CrawlerRules.demon_grounds(CrawlerRules.TOWER_PATCH)
			and CrawlerRules.field_kinds(CrawlerRules.TOWER_PATCH).has("gloam"),
		"Far Beacon fields the run combo, not the authored office robots")
	_expect(CrawlerRules.field_kinds(CrawlerRules.CITY_PATCH).has("kestrel")
			and not CrawlerRules.field_kinds(CrawlerRules.CITY_PATCH).has("gloam"),
		"Quiet Inlet fields its run pack outside the plaza")
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	var city_kind: String = horde.call(
		"_pick_kind", Vector3(400.0, 0.0, 0.0), CrawlerRules.CITY_PATCH, 400.0, 2)
	_expect(city_kind == "kestrel" or city_kind == "weaver",
		"the horde rolls the run pack on the old city name")
	var empty_ring: Array[Dictionary] = [{
		"at": Vector3.ZERO,
		"kinds": PackedStringArray(),
	}]
	var demon_ring: Array[Dictionary] = [{
		"at": Vector3.ZERO,
		"kinds": PackedStringArray(["gloam", "vesper", "threnody"]),
	}]
	_expect(not bool(horde.call("_off_combo_near", Vector3.ZERO, "ranger", empty_ring)),
		"an empty roster does not wipe the nearby pack")
	_expect(bool(horde.call("_off_combo_near", Vector3.ZERO, "ranger", demon_ring)),
		"a demon ring still retires wilds that followed in")
	var left_ring: Array[Dictionary] = [{
		"at": Vector3.ZERO,
		"kinds": PackedStringArray(["gloam", "vesper", "threnody"]),
		"patch_id": 2,
	}]
	_expect(not bool(horde.call(
			"_off_combo_near", Vector3(36.0, 0.0, 0.0), "ranger", left_ring, 8)),
		"crossing into a new combo does not wipe the tile you left")
	_expect(bool(horde.call(
			"_off_combo_near", Vector3(6.0, 0.0, 0.0), "ranger", left_ring, 2)),
		"a wild that followed onto the new combo tile still leaves")
	horde.queue_free()
	CrawlerRun.clear()
	CrawlerRun.payload = held
	CrawlerRun.path = held_path
	if not held.is_empty():
		CrawlerRun._index()


func _check_nearest_quest_marks() -> void:
	var held := CrawlerRun.payload.duplicate(true)
	var held_path := CrawlerRun.path
	CrawlerRun.payload = {
		"radius_m": 8000.0,
		"spawn": {"direction": {"x": 0.0, "y": 1.0, "z": 0.0}},
		"cities": [],
		"castles": [
			{"id": "castle1", "ring": 1, "direction": {"x": 0.0, "y": 0.0, "z": 1.0}},
			{"id": "castle2", "ring": 2, "direction": {"x": -1.0, "y": 0.0, "z": 0.0}},
		],
		"offices": [
			{"id": "office1", "ring": 1, "direction": {"x": 1.0, "y": 0.0, "z": 0.0}},
			{"id": "office2", "ring": 2, "direction": {"x": 0.0, "y": 0.0, "z": -1.0}},
		],
		"bosses": [
			{
				"id": "boss1", "ring": 1, "radius_m": 100.0, "empty": false,
				"encounter": CrawlerRules.BOSS_ENCOUNTER_TREE,
				"direction": {"x": 0.8, "y": 0.0, "z": 0.6},
			},
			{
				"id": "boss2", "ring": 2, "radius_m": 100.0, "empty": true,
				"encounter": CrawlerRules.BOSS_ENCOUNTER_EMPTY,
				"direction": {"x": -0.8, "y": 0.0, "z": -0.6},
			},
		],
	}
	CrawlerRun.path = "res://dev/fake_run.json"
	CrawlerRun._index()
	_player.global_position = Vector3(400.0, 0.0, 80.0)
	var office_near := _quest_mark("office1", CrawlerRules.OFFICE_WAYPOINT_TINT)
	var office_far := _quest_mark("office2", CrawlerRules.OFFICE_WAYPOINT_TINT)
	var castle_near := _quest_mark("castle1", CrawlerRules.CASTLE_WAYPOINT_TINT)
	var castle_far := _quest_mark("castle2", CrawlerRules.CASTLE_WAYPOINT_TINT)
	var boss_near := _quest_mark("boss1", CrawlerRules.BOSS_WAYPOINT_TINT)
	var boss_far := _quest_mark("boss2", CrawlerRules.BOSS_WAYPOINT_TINT)
	var layout := CrawlerRunLayout.new()
	layout.set_process(false)
	add_child(layout)
	await get_tree().process_frame
	_expect(layout.reveal_quest_site(_player, CrawlerProgress.QUEST_TOWER) == "office1"
			and office_near.waypoint and not office_far.waypoint,
		"an office quest marks the nearest unmarked office")
	_expect(layout.reveal_quest_site(_player, CrawlerProgress.QUEST_CASTLE) == "castle1"
			and castle_near.waypoint and not castle_far.waypoint,
		"a castle quest marks the nearest unmarked castle")
	_expect(layout.peek_quest_site(_player, CrawlerProgress.QUEST_BOSS) == "boss1",
		"the stall peeks the nearest unmarked boss before buying")
	_expect(layout.peek_quest_encounter(_player, CrawlerProgress.QUEST_BOSS)
			== CrawlerRules.BOSS_ENCOUNTER_TREE,
		"the stall knows the nearest boss is the giant tree")
	_expect(CrawlerProgress.quest_title(
			CrawlerProgress.QUEST_BOSS, CrawlerRules.BOSS_ENCOUNTER_TREE)
			== CrawlerProgress.QUEST_TREE_TITLE,
		"the tree battle quest is titled Barking up the Wrong Tree")
	_expect(CrawlerRun.is_tree_boss("boss1") and not CrawlerRun.is_tree_boss("boss2"),
		"only the first-ring boss is the giant tree")
	_expect(CrawlerProgress.site_title("boss1") == CrawlerProgress.QUEST_TREE_TITLE,
		"the tree site keeps that title on the map")
	var stall := CrawlerFieldMenu.new()
	stall.configure(_player)
	add_child(stall)
	await get_tree().process_frame
	stall._clear_list()
	stall._fill_quests()
	var stall_title := stall.find_child("QuestTitle_boss", true, false) as Label
	_expect(stall_title != null
			and stall_title.text.begins_with("BARKING UP THE WRONG TREE"),
		"the quest stall titles the tree battle")
	stall.queue_free()
	_expect(layout.reveal_quest_site(_player, CrawlerProgress.QUEST_BOSS) == "boss1"
			and boss_near.waypoint and not boss_far.waypoint
			and boss_near.tint.is_equal_approx(CrawlerRules.BOSS_WAYPOINT_TINT),
		"a boss quest marks the nearest unmarked boss in dark purple")
	_expect(layout.peek_quest_encounter(_player, CrawlerProgress.QUEST_BOSS)
			== CrawlerRules.BOSS_ENCOUNTER_EMPTY,
		"the next unmarked boss stays an empty circle")
	_expect(CrawlerProgress.quest_title(
			CrawlerProgress.QUEST_BOSS, CrawlerRules.BOSS_ENCOUNTER_EMPTY)
			== "Boss Site",
		"an empty circle keeps the generic boss title")
	var tree: Node = TREE_BOSS.new()
	tree.name = "TreeBossCheck"
	add_child(tree)
	await get_tree().process_frame
	_expect(str(tree.call(&"combat_display_name")) == "The Giving Tree"
			and tree.is_in_group(BossAdapter.CRAWLER_GROUP)
			and is_equal_approx(float(tree.call(&"maximum_health")), 500.0)
			and is_equal_approx(float(tree.call(&"battle_radius")), 200.0)
			and int(tree.call(&"bushel_count")) >= 6
			and not bool(tree.call(&"blocks_field_spawns")),
		"The Giving Tree is the first-ring boss")
	_expect(is_equal_approx(CrawlerRules.TREE_BATTLE_RADIUS, 200.0)
			and is_equal_approx(CrawlerRules.TREE_FLORA_CLEAR, 1.0),
		"the giving tree fight is a 200 m ring with a 1 m trunk clear")
	var poke := DamageHit.impact(tree.call(&"combat_position"), 2.0, 40.0)
	poke.faction = DamageHit.Faction.PLAYER
	_expect(is_equal_approx(float(tree.call(&"apply_damage", poke)), 0.0),
		"the trunk stays locked until the bushels are gone")
	_expect(JournalDB.has_entry("first_boss")
			and JournalDB.gems_of("first_boss") == 10
			and JournalDB.xp_of("first_boss") == 100,
		"killing a first boss is a claimable combat achievement")
	var gold_before := _player.crawler_progress.gold if _player.crawler_progress != null else 0
	if _player.crawler_progress != null:
		_player.crawler_progress.grant_spoils(100, 10, 25)
		_expect(_player.crawler_progress.gold == gold_before + 100,
			"slaying the tree pays run gold")
	if _player.journal != null:
		_player.journal.complete("first_boss")
		_expect(_player.journal.is_done("first_boss")
				and _player.journal.can_claim("first_boss"),
			"the first-boss achievement waits to be claimed")
		_player.journal.reset("first_boss")
	tree.queue_free()
	layout.queue_free()
	office_near.queue_free()
	office_far.queue_free()
	castle_near.queue_free()
	castle_far.queue_free()
	boss_near.queue_free()
	boss_far.queue_free()
	CrawlerRun.clear()
	CrawlerRun.payload = held
	CrawlerRun.path = held_path
	if not held.is_empty():
		CrawlerRun._index()
	_player.global_position = Vector3.ZERO


func _quest_mark(monument_id: String, tint: Color) -> PatchMonument:
	var site := PatchMonument.new()
	site.monument_id = monument_id
	site.title = monument_id
	site.tint = tint
	site.waypoint = false
	site.keepout_radius = 100.0
	add_child(site)
	return site


func _check_tilde_city_waypoint() -> void:
	_expect(not _player._waypoints_wanted, "tilde starts closed")
	var tilde := InputEventKey.new()
	tilde.physical_keycode = 96 as Key
	tilde.pressed = true
	_player._unhandled_input(tilde)
	_expect(_player._waypoints_wanted, "tilde opens the city waypoint")
	_expect(not _player._coordinates_wanted,
		"crawler tilde does not open the info plate")
	if _player._land_patches != null:
		_expect(not _player._land_patches.visible,
			"crawler tilde hides patch boundaries")
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


func _check_waypoint_reveal() -> void:
	if ResourceLoader.exists(CrawlerSpawnPad.MODEL):
		var packed_pad := load(CrawlerSpawnPad.MODEL) as PackedScene
		if packed_pad != null:
			var pad := CrawlerSpawnPad.new()
			pad.force_model = true
			add_child(pad)
			await get_tree().process_frame
			var seated := pad.player_spawn_transform()
			var panel := pad.control_panel_point()
			_expect(panel.is_finite(), "Relay 07 has a computer control panel")
			if panel.is_finite():
				var up := seated.basis.y.normalized()
				var toward := panel - seated.origin
				toward -= up * toward.dot(up)
				var forward := -seated.basis.z
				forward -= up * forward.dot(up)
				_expect(toward.length_squared() > 0.0001
						and forward.length_squared() > 0.0001
						and forward.normalized().dot(toward.normalized()) > 0.85,
					"spawn faces the teleporter control panel")
			pad.queue_free()
			await get_tree().process_frame
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	_expect(layer != null, "waypoint reveal uses the HUD layer")
	if layer == null:
		return
	_player._waypoints_wanted = false
	_player._apply_tilde_overlay()
	var mark := Landmark.new()
	mark.title = "Reveal Test"
	mark.waypoint = true
	mark.position = Vector3(400.0, 0.0, 0.0)
	add_child(mark)
	mark.add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
	await get_tree().process_frame
	_player.global_position = Vector3.ZERO
	_player.global_basis = Basis.IDENTITY
	_player.reveal_waypoint(mark)
	_expect(_player.is_revealing_waypoint(), "a new waypoint starts the reveal")
	_expect(not _player._waypoints_wanted, "the reveal does not open tilde")
	_tick_waypoint_reveal(1.1)
	_expect(layer.visible and layer.is_revealing(),
		"the unlock blinks in outside tilde")
	_expect(layer.drawn(0.0).has("Reveal Test"),
		"the new waypoint is named during the blink")
	_expect(not layer.enabled, "the blink keeps the map overlay closed")
	_expect(layer.pulse_amount() > 0.0, "the blink carries a radar pulse")
	_expect(_player.look_direction().dot(Vector3.RIGHT) > 0.55,
		"player and camera turn to face the new waypoint")
	_tick_waypoint_reveal(3.0)
	_expect(not _player.is_revealing_waypoint(), "the reveal ends")
	_expect(not layer.visible or layer.drawn(0.0).is_empty(),
		"the mark fades after the pulse")
	_expect(not _player._waypoints_wanted, "tilde stays closed after the fade")
	_player._waypoints_wanted = true
	_player._apply_tilde_overlay()
	layer._process(0.016)
	_expect(layer.enabled and layer.drawn(0.0).has("Reveal Test"),
		"tilde shows the unlocked waypoint after the fade")
	var known := Landmark.new()
	known.title = "Already Known"
	known.waypoint = true
	known.position = Vector3(0.0, 0.0, 400.0)
	add_child(known)
	known.add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
	await get_tree().process_frame
	layer._process(0.016)
	_expect(layer.drawn(0.0).has("Already Known"),
		"tilde still names the older waypoint")
	_player.reveal_waypoint(known)
	_expect(_player.is_revealing_waypoint() and not layer.enabled,
		"a later reveal closes the map again")
	_tick_waypoint_reveal(1.1)
	var exclusive := layer.drawn(0.0)
	_expect(exclusive.has("Already Known"),
		"the later reveal names only that waypoint")
	_expect(not exclusive.has("Reveal Test"),
		"other map waypoints stay hidden during the reveal")
	_tick_waypoint_reveal(3.0)
	_player._waypoints_wanted = true
	_player._apply_tilde_overlay()
	layer._process(0.016)
	var restored := layer.drawn(0.0)
	_expect(layer.enabled and restored.has("Reveal Test")
			and restored.has("Already Known"),
		"tilde restores every waypoint after the fade")
	known.queue_free()
	await get_tree().process_frame
	_player._waypoints_wanted = false
	_player._apply_tilde_overlay()
	var city := CrawlerSite.new()
	city.site_id = CrawlerRules.CITY_SITE_ID
	city.title = CrawlerRules.CITY_SITE_TITLE
	city.enter_radius = 40.0
	city.position = Vector3(0.0, 0.0, 500.0)
	add_child(city)
	await get_tree().process_frame
	_player.defer_camera = false
	_player.visible = true
	_player._opening_reveal_done = false
	_player._revealed_waypoints.erase("site:%s" % CrawlerRules.CITY_SITE_ID)
	_player._revealed_waypoints.erase("title:%s" % CrawlerRules.CITY_SITE_TITLE)
	_player._try_opening_waypoint_reveal()
	_expect(city.waypoint and city.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"the opening waypoint unlocks just after spawn")
	_expect(_player.is_revealing_waypoint()
			and _player._opening_reveal_done,
		"spawn turns the player toward Neon Fjord")
	_tick_waypoint_reveal(4.0)
	var later := CrawlerSite.new()
	later.site_id = "later_beacon"
	later.title = "Later Beacon"
	later.enter_radius = 40.0
	later.waypoint = false
	later.position = Vector3(-500.0, 0.0, 0.0)
	add_child(later)
	await get_tree().process_frame
	later.unlock_waypoint()
	_expect(_player.is_revealing_waypoint(),
		"a distant unlock turns the player again")
	_tick_waypoint_reveal(4.0)
	_player.defer_camera = true
	mark.queue_free()
	city.queue_free()
	later.queue_free()


func _tick_waypoint_reveal(seconds: float) -> void:
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	var left := seconds
	while left > 0.0:
		var step := minf(left, 0.05)
		left -= step
		_player._tick_waypoint_reveal(step)
		if layer != null:
			layer._process(step)


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
	_expect(not spawn.waypoint,
		"Tide Margin stays off tilde until Neon Fjord")
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
	var city_gems := 0 if _player.journal.is_done("first_city") \
		else JournalDB.auto_gems_of("first_city")
	_expect(CrawlerSites.poll(_player) == CrawlerRules.CITY_SITE_TITLE,
		"the village shows Entering Neon Fjord")
	_expect(hud != null and hud.entering_bonus() == "+%d gems" % site_gems,
		"a new village also shows +gems")
	_expect(village.waypoint, "walking into the village lights its waypoint")
	_expect(not spawn.waypoint, "Tide Margin waits a beat after Neon Fjord")
	CrawlerSites.unlock_later_cities(get_tree(), false)
	_expect(spawn.waypoint and spawn.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP),
		"Neon Fjord lights the Tide Margin waypoint")
	_expect(_player.journal.is_done("first_city")
			and CrawlerMeta.sandbox_unlocked(),
		"the first city unlocks sandbox")
	_player.global_position = Vector3.ZERO
	_expect(CrawlerSites.poll(_player) == CrawlerRules.START_SITE_TITLE,
		"a later site lets the first place announce again")
	_expect(hud != null and hud.entering_bonus().is_empty(),
		"a known site does not show another gem bonus")
	_expect(CrawlerMeta.gems() == gems_before + site_gems * 2 + city_gems
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
	if CrawlerAdobeSite.city_ready():
		var ring = CITY_RING.new()
		ring.force_village = true
		add_child(ring)
		await get_tree().process_frame
		_expect(ring.get_node_or_null("Village") != null,
			"the first city seats adobe buildings")
		_expect(CrawlerAdobeSite.building_count(ring) == CrawlerAdobeSite.CITY_BUILDINGS.size(),
			"the city seats the blob village")
		_expect(ring.find_child("CityWall", true, false) == null,
			"the village replaces the stand-in walls")
		_expect(_monument_has_trimesh(ring)
				or _ring_has_blocking_collision(ring),
			"the village keeps walkable collision")
		_expect(ring.find_child("VillageFolk", true, false) == null,
			"adobe cities do not seat meeps")
		ring.refresh_stall_signs()
		await get_tree().process_frame
		_expect(ring.find_child("StallSign_hats", true, false) == null,
			"adobe cities do not float stall tiles")
		var first_palette := CrawlerAdobeSite.palette_for(ring.city_key())
		var crescent = CITY_RING.new()
		crescent.force_village = true
		crescent.configure(
			-1,
			Transform3D.IDENTITY,
			CrawlerRules.CITY_CRESCENT_SITE_ID,
			CrawlerRules.CITY_CRESCENT_TITLE,
			"",
			CrawlerRules.CITY_CRESCENT_SITE_ID
		)
		add_child(crescent)
		await get_tree().process_frame
		_expect(crescent.get_node_or_null("Village") != null,
			"later cities seat the same adobe catalog")
		_expect(CrawlerAdobeSite.building_count(crescent)
				== CrawlerAdobeSite.CITY_BUILDINGS.size(),
			"Crescent Market seats the blob village")
		var crescent_mark := crescent.get_node_or_null("CrawlerWaypoint") as CrawlerSite
		_expect(crescent_mark != null and not crescent_mark.waypoint
				and crescent_mark.title == CrawlerRules.CITY_CRESCENT_TITLE,
			"Crescent Market waits until you enter Neon Fjord")
		_expect(crescent.find_child("VillageFolk", true, false) == null,
			"later adobe cities do not seat meeps")
		var later_palette := CrawlerAdobeSite.palette_for(crescent.city_key())
		_expect(first_palette[0] != later_palette[0]
				or first_palette[1] != later_palette[1]
				or first_palette[2] != later_palette[2],
			"each city rolls its own adobe palette")
		ring.queue_free()
		crescent.queue_free()
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


func _check_crawler_statues() -> void:
	var progress := _player.crawler_progress
	_expect(progress != null, "statues read the run ledger")
	if progress == null:
		return
	for kind: String in CrawlerStatue.KINDS:
		_expect(FileAccess.file_exists(String(CrawlerStatue.PORTRAIT[kind])),
			"%s still has its statue painting" % kind)
		_expect(FileAccess.file_exists(String(CrawlerStatue.MODEL[kind])),
			"%s uses its blender statue" % kind)
	_expect(CrawlerStatue.pool_for(CrawlerStatue.KIND_WINGS)
			== PackedStringArray([
				CrawlerProgress.STAT_FLIGHT, CrawlerProgress.STAT_DEXTERITY,
			]),
		"the wing statue offers flight or speed")
	_expect(CrawlerStatue.pool_for(CrawlerStatue.KIND_STRENGTH)
			== PackedStringArray([
				CrawlerProgress.STAT_DAMAGE, CrawlerProgress.STAT_DEFENSE,
			]),
		"the strength statue offers damage or defense")
	var wealth := CrawlerStatue.pool_for(CrawlerStatue.KIND_WEALTH)
	_expect(wealth.has(CrawlerProgress.STAT_GOLD)
			and wealth.has(CrawlerProgress.STAT_XP)
			and wealth.has(CrawlerProgress.STAT_GEMS)
			and wealth.size() == 3,
		"the wealth statue raises gem, gold, or XP gain")
	var misc := CrawlerStatue.pool_for(CrawlerStatue.KIND_MISC)
	_expect(misc.has(CrawlerProgress.STAT_LUCK)
			and misc.has(CrawlerProgress.STAT_DODGE)
			and misc.has(CrawlerProgress.STAT_JUKE_DISTANCE)
			and misc.has(CrawlerProgress.STAT_CAST)
			and not misc.has(CrawlerProgress.STAT_GOLD)
			and not misc.has(CrawlerProgress.STAT_XP)
			and not misc.has(CrawlerProgress.STAT_GEMS)
			and not misc.has(CrawlerProgress.STAT_FLIGHT)
			and not misc.has(CrawlerProgress.STAT_DAMAGE)
			and not misc.has(CrawlerProgress.STAT_HEALTH),
		"the curious statue rolls the leftover motion and luck stats")
	_expect(CrawlerStatue.pool_for(CrawlerStatue.KIND_HEALTH).has(CrawlerStatue.HEAL_ID)
			and CrawlerStatue.pool_for(CrawlerStatue.KIND_HEALTH).has(
				CrawlerProgress.STAT_HEALTH),
		"the health statue can raise max HP or heal")
	var unspent := progress.unspent
	var before_damage := progress.rank_of(CrawlerProgress.STAT_DAMAGE)
	_expect(progress.grant_boost(CrawlerProgress.STAT_DAMAGE,
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_RARE)),
		"a statue can grant a rare damage rank")
	_expect(is_equal_approx(
			progress.rank_of(CrawlerProgress.STAT_DAMAGE),
			before_damage + CrawlerProgress.rarity_amount(
				CrawlerProgress.RARITY_RARE))
			and progress.unspent == unspent,
		"a statue boost does not spend a level point")
	_player.stats.set_health(12.0)
	_expect(CrawlerStatue.apply_blessing(_player, {
			"id": CrawlerStatue.HEAL_ID,
			"rarity": 0,
			"amount": 0.0,
		}),
		"the health statue can mend the body")
	_expect(is_equal_approx(_player.health(), _player.maximum_health()),
		"a heal blessing fills the bar")
	progress.claimed_statues = PackedStringArray()
	progress.remember()
	var flight_before := progress.rank_of(CrawlerProgress.STAT_FLIGHT)
	var dex_before := progress.rank_of(CrawlerProgress.STAT_DEXTERITY)
	var statue := CrawlerStatue.new()
	statue.configure(CrawlerStatue.KIND_WINGS)
	add_child(statue)
	await get_tree().process_frame
	_expect(statue.find_child("StatueAura", true, false) != null
			and statue.find_child("StatueBarFill", true, false) != null
			and statue.find_child("StatueAuraZone", true, false) != null
			and statue.find_child("StatueFigure", true, false) != null
			and statue.find_child("StatueSign", true, false) != null,
		"a statue carries a blender figure, an aura sphere, and a progress bar")
	_player.global_position = statue.global_position + Vector3(8.0, 0.4, 0.0)
	statue.call(&"_face_visitor")
	var sign := statue.find_child("StatueSign", true, false) as Node3D
	var toward := _player.global_position - sign.global_position
	toward.y = 0.0
	_expect(sign != null and toward.length_squared() > 0.01
			and sign.global_transform.basis.z.dot(toward.normalized()) > 0.65,
		"the fill bar over a statue faces the player")
	var blessing := statue.tick_presence(CrawlerStatue.FILL_SECONDS, true, _player)
	_expect(statue.claimed and statue.fill >= 1.0 and not blessing.is_empty(),
		"standing in the aura until the bar fills spends the statue")
	var aura := statue.find_child("StatueAura", true, false) as MeshInstance3D
	_expect(aura != null and not aura.visible,
		"a spent statue drops its aura sphere")
	var pop := statue.find_child("StatueBlessing", true, false) as Label3D
	_expect(pop != null and pop.text == CrawlerStatue.popup_text(blessing)
			and pop.text.contains(CrawlerProgress.stat_title(
				str(blessing.get("id", ""))).to_upper()),
		"blessing text pops off the statue with the stat and amount")
	_expect(statue.find_child("CrawlerBurst", true, false) != null,
		"confetti pops out of a spent statue")
	var bar := statue.find_child("StatueBarFill", true, false) as MeshInstance3D
	_expect(bar != null and is_equal_approx(bar.position.x, 0.0)
			and is_equal_approx(bar.scale.x, 1.0),
		"a full statue bar reaches the end of the track")
	_expect(progress.statue_claimed(CrawlerStatue.KIND_WINGS),
		"the run remembers a spent statue")
	_expect(
		progress.rank_of(CrawlerProgress.STAT_FLIGHT) > flight_before
		or progress.rank_of(CrawlerProgress.STAT_DEXTERITY) > dex_before,
		"the wing statue raised flight or speed")
	_expect(statue.tick_presence(CrawlerStatue.FILL_SECONDS, true, _player).is_empty(),
		"a spent statue does not bless again")
	var restored := CrawlerProgress.new()
	restored.from_dict(progress.to_dict())
	_expect(restored.statue_claimed(CrawlerStatue.KIND_WINGS)
			and restored.statue_seed != 0,
		"statue claims and the placement seed persist")
	_expect(CrawlerStatues.OPENING_COUNT >= 2 and CrawlerStatues.OPENING_COUNT <= 4
			and CrawlerStatues.MIN_SEPARATION <= 320.0
			and CrawlerStatues.FIELD_SEPARATION < CrawlerStatues.OPENING_SEPARATION
			and CrawlerStatues.TARGET_COUNT > 240,
		"statues are spaced for 2-4 finds on the walk and pack the inland cells")
	var opening := CrawlerStatues.pick_directions(null, 1)
	var walk := CrawlerRules.spawn_direction().angle_to(
			CrawlerRules.city_direction()) * 8000.0
	_expect(opening.size() == CrawlerStatues.OPENING_COUNT
			and CrawlerStatues.count_along_opening(opening) == opening.size()
			and walk > 700.0 and walk < 1300.0
			and walk / CrawlerStatues.MIN_SEPARATION >= 2.0
			and walk / CrawlerStatues.MIN_SEPARATION <= 5.5,
		"three shrines sit on the spawn-to-city walk")
	var gold_before := progress.rank_of(CrawlerProgress.STAT_GOLD)
	var xp_before := progress.rank_of(CrawlerProgress.STAT_XP)
	var gems_before := progress.rank_of(CrawlerProgress.STAT_GEMS)
	progress.claimed_statues = PackedStringArray()
	progress.remember()
	var purse := CrawlerStatue.new()
	purse.configure(CrawlerStatue.KIND_WEALTH, Vector3.FORWARD, 0)
	add_child(purse)
	await get_tree().process_frame
	var purse_blessing := purse.tick_presence(CrawlerStatue.FILL_SECONDS, true, _player)
	_expect(purse.claimed and not purse_blessing.is_empty()
			and progress.statue_claimed(purse.claim_id)
			and (
				progress.rank_of(CrawlerProgress.STAT_GOLD) > gold_before
				or progress.rank_of(CrawlerProgress.STAT_XP) > xp_before
				or progress.rank_of(CrawlerProgress.STAT_GEMS) > gems_before
			),
		"standing at a wealth statue boosts gem, gold, or XP gain")
	statue.queue_free()
	purse.queue_free()
	await get_tree().process_frame


func _check_roar_shockwaves() -> void:
	var poisoned := CrawlerRanger.new()
	poisoned.configure("toxin", Transform3D(Basis(), Vector3(12.0, 4.0, 0.0)), 1, true)
	add_child(poisoned)
	poisoned.set_physics_process(false)
	var before := poisoned.health()
	var toxin := DamageHit.impact(poisoned.combat_position(), 2.0, 0.0)
	toxin.faction = DamageHit.Faction.PLAYER
	toxin.with_status(CombatStatuses.POISON, 2.0, 10.0)
	_expect(poisoned.apply_damage(toxin) == 0.0
			and poisoned.statuses.has(CombatStatuses.POISON),
		"poison applies without an opening hit")
	poisoned._tick_statuses(0.5)
	_expect(poisoned.health() < before and poisoned.is_alive(),
		"poison deals damage over time")

	var frozen := CrawlerRanger.new()
	frozen.configure("frost", Transform3D(Basis(), Vector3(16.0, 4.0, 0.0)), 1, true)
	add_child(frozen)
	frozen.set_physics_process(false)
	frozen.velocity = Vector3(8.0, 0.0, 0.0)
	var frost := DamageHit.impact(frozen.combat_position(), 2.0, 0.0)
	frost.faction = DamageHit.Faction.PLAYER
	frost.with_status(CombatStatuses.FREEZE, 2.0)
	frozen.apply_damage(frost)
	_expect(frozen.is_frozen(), "freeze locks a mob")
	frozen._physics_process(0.16)
	_expect(frozen.velocity.is_zero_approx(), "a frozen mob stops moving")

	var shocked := CrawlerRanger.new()
	shocked.configure("shock", Transform3D(Basis(), Vector3(18.0, 4.0, 0.0)), 1, true)
	add_child(shocked)
	shocked.set_physics_process(false)
	shocked.velocity = Vector3(8.0, 0.0, 0.0)
	var jolt := DamageHit.impact(shocked.combat_position(), 2.0, 8.0)
	jolt.faction = DamageHit.Faction.PLAYER
	jolt.with_status(CombatStatuses.SHOCK, 2.0)
	shocked.apply_damage(jolt)
	_expect(shocked.statuses.has(CombatStatuses.SHOCK)
			and shocked.is_frozen(),
		"shock starts by locking a mob")
	shocked._tick_statuses(CombatStatuses.SHOCK_LOCK + 0.05)
	_expect(shocked.statuses.has(CombatStatuses.SHOCK)
			and not shocked.is_frozen(),
		"shock then lets the mob twitch free")
	shocked._tick_statuses(CombatStatuses.SHOCK_MOVE + 0.05)
	_expect(shocked.is_frozen(), "shock locks the mob again")

	var heart := DamageNumberEvent.new()
	heart.kind = DamageNumberEvent.Kind.CHARM
	heart.amount = 1.0
	var toxin_pop := DamageNumberEvent.new()
	toxin_pop.kind = DamageNumberEvent.Kind.POISON
	toxin_pop.amount = 5.0
	var bolt := DamageNumberEvent.new()
	bolt.kind = DamageNumberEvent.Kind.SHOCK
	bolt.amount = 1.0
	_expect(heart.caption() == "♥" and bolt.caption() == "⚡"
			and toxin_pop.caption() == "5",
		"charm, shock, and poison each have their own float")

	var first := CrawlerRanger.new()
	first.configure("bolt_a", Transform3D(Basis(), Vector3(30.0, 4.0, 0.0)), 1, true)
	var second := CrawlerRanger.new()
	second.configure("bolt_b", Transform3D(Basis(), Vector3(34.0, 4.0, 0.0)), 1, true)
	add_child(first)
	add_child(second)
	first.set_physics_process(false)
	second.set_physics_process(false)
	var chain := Lightning.collect_hops(
		self, Vector3(28.0, 4.0, 0.0), first.combat_position(), 1, 9.0, 7.0)
	_expect(chain.size() >= 2,
		"lightning snaps to a nearby body and hops to a second")

	poisoned.queue_free()
	frozen.queue_free()
	shocked.queue_free()
	first.queue_free()
	second.queue_free()

	var bait := CrawlerRanger.new()
	bait.configure("charm_bait", Transform3D(Basis(), Vector3(20.0, 4.0, 0.0)), 1, true)
	var hunter := CrawlerRanger.new()
	hunter.configure("charm_hunter", Transform3D(Basis(), Vector3(24.0, 4.0, 0.0)), 1, true)
	add_child(bait)
	add_child(hunter)
	bait.set_physics_process(false)
	hunter.set_physics_process(false)
	var charm := DamageHit.impact(bait.combat_position(), 2.0, 0.0)
	charm.faction = DamageHit.Faction.PLAYER
	charm.with_status(CombatStatuses.CHARM, 3.0)
	bait.apply_damage(charm)
	_expect(bait.is_charmed() and hunter._combat_target() == bait,
		"other mobs hunt a charmed enemy")
	var prey := bait._combat_target()
	_expect(prey is CrawlerMob and prey != bait,
		"a charmed mob attacks another mob")
	_expect(bait.outgoing_faction() == DamageHit.Faction.PLAYER,
		"charmed mobs strike as the player's side")
	bait.statuses.clear(CombatStatuses.CHARM)
	bait._tick_statuses(0.0)
	_expect(not bait.is_charmed() and bait.chase,
		"charm expiry leaves the mob agroed")

	bait.queue_free()
	hunter.queue_free()


func _check_fields() -> void:
	var frost_at := Vector3(48.0, 4.0, 0.0)
	var frost := CrawlerFieldVolume.create(
		self, _player, "freeze_field", frost_at,
		CrawlerRules.field_start_stats("freeze_field"),
		Color(0.45, 0.82, 1.0), true)
	_expect(frost != null, "freeze field can be placed")
	if frost != null:
		frost._age = CrawlerFieldVolume.EXPAND
		var slow := CrawlerFieldVolume.speed_scale_at(self, frost_at)
		_expect(slow < 0.4 and slow > 0.05,
			"freeze field cuts speed of bodies and shots inside")
		var wash := CrawlerFieldVolume.wash_at(self, frost_at)
		_expect(wash.a > 0.05, "standing in a field tints the view")
		var slowed := CrawlerRanger.new()
		slowed.configure("field_slow", Transform3D(Basis(), frost_at), 1, true)
		add_child(slowed)
		slowed.set_physics_process(false)
		slowed.velocity = Vector3(10.0, 0.0, 0.0)
		var scale := CrawlerFieldVolume.speed_scale_at(slowed, frost_at)
		slowed.velocity *= scale
		_expect(slowed.velocity.length() < 4.0,
			"a mob inside a freeze field moves slower")
		slowed.queue_free()
		frost.queue_free()

	var toxin_at := Vector3(56.0, 4.0, 0.0)
	var toxin := CrawlerFieldVolume.create(
		self, _player, "toxic_field", toxin_at,
		CrawlerRules.field_start_stats("toxic_field"),
		Color(0.32, 0.92, 0.22), true)
	var soaked := CrawlerRanger.new()
	soaked.configure("field_toxin", Transform3D(Basis(), toxin_at), 1, true)
	add_child(soaked)
	soaked.set_physics_process(false)
	if toxin != null:
		toxin._age = CrawlerFieldVolume.EXPAND
		toxin._tick_inside()
		var first := soaked.statuses.strength(CombatStatuses.POISON)
		toxin._tick_inside()
		_expect(soaked.statuses.has(CombatStatuses.POISON)
				and soaked.statuses.strength(CombatStatuses.POISON) > first,
			"toxic field stacks poison while a mob stays inside")
		toxin.queue_free()
	soaked.queue_free()

	var static_at := Vector3(64.0, 4.0, 0.0)
	var static_field := CrawlerFieldVolume.create(
		self, _player, "static_field", static_at,
		CrawlerRules.field_start_stats("static_field"),
		Color(0.48, 0.84, 1.0), true)
	var jolted := CrawlerRanger.new()
	jolted.configure("field_static", Transform3D(Basis(), static_at), 1, true)
	add_child(jolted)
	jolted.set_physics_process(false)
	var before := jolted.health()
	if static_field != null:
		static_field._age = CrawlerFieldVolume.EXPAND
		static_field._tick_inside()
		_expect(jolted.health() < before
				and jolted.statuses.has(CombatStatuses.SHOCK),
			"static field damages and shocks a mob that enters")
		static_field.queue_free()
	jolted.queue_free()

	var heal_at := _player.combat_position()
	var wounded := _player.maximum_health() * 0.45
	_player.stats.set_health(wounded)
	var healing := CrawlerFieldVolume.create(
		self, _player, "healing_field", heal_at,
		CrawlerRules.field_start_stats("healing_field"),
		Color(0.54, 0.94, 0.75), true)
	var bystander := CrawlerRanger.new()
	bystander.configure("field_heal", Transform3D(Basis(), heal_at), 1, true)
	add_child(bystander)
	bystander.set_physics_process(false)
	var mob_before := bystander.health()
	if healing != null:
		healing._age = CrawlerFieldVolume.EXPAND
		healing._tick_inside()
		_expect(_player.health() > wounded,
			"healing field restores the owner standing inside")
		_expect(is_equal_approx(bystander.health(), mob_before),
			"healing field does not damage mobs")
		healing.queue_free()
	bystander.queue_free()
	_player.stats.set_health(_player.maximum_health())


func _check_linger() -> void:
	var at := Vector3(40.0, 4.0, 0.0)
	var recipe := {
		"ability_id": "laser_eyes",
		"tint": Color(0.48, 0.84, 1.0),
		"duration": 2.0,
		"radius": 1.6,
		"damage": 10.0,
		"slow": 40.0,
		"statuses": [],
	}
	var cloud := CrawlerLingerCloud.spawn(self, _player, recipe, at, true)
	_expect(cloud != null, "a linger cloud can be placed")
	if cloud == null:
		return
	var wash := CrawlerLingerCloud.wash_at(self, at)
	_expect(wash.a > 0.02, "standing in a linger cloud tints the view")
	_expect(CrawlerLingerCloud.speed_scale_at(self, at) < 0.75,
		"a slow linger cloud cuts speed inside")
	var dummy := CrawlerRanger.new()
	dummy.configure("linger_hit", Transform3D(Basis(), at), 1, true)
	add_child(dummy)
	dummy.set_physics_process(false)
	var before := dummy.health()
	cloud._tick_inside()
	_expect(dummy.health() < before, "a linger cloud damages a mob inside")
	dummy.queue_free()
	cloud.queue_free()


func _check_elemental_mods() -> void:
	var stacked := CrawlerRanger.new()
	stacked.configure("beam_toxin", Transform3D(Basis(), Vector3(72.0, 4.0, 0.0)), 1, true)
	add_child(stacked)
	stacked.set_physics_process(false)
	var pulse := DamageHit.beam(
		stacked.combat_position(), stacked.combat_position() + Vector3.RIGHT, 1.0, 1.0)
	pulse.faction = DamageHit.Faction.PLAYER
	CrawlerElements.apply_to_hit(pulse, [{
		"id": String(CombatStatuses.POISON),
		"duration": 4.0,
		"strength": 2.0,
		"stack": true,
	}], true)
	stacked.apply_damage(pulse)
	var first := stacked.statuses.strength(CombatStatuses.POISON)
	stacked.apply_damage(pulse)
	_expect(stacked.statuses.has(CombatStatuses.POISON)
			and stacked.statuses.strength(CombatStatuses.POISON) > first,
		"a toxic beam stacks poison on a mob")
	stacked.queue_free()

	var blast := DamageHit.area(Vector3(80.0, 4.0, 0.0), 10.0, 20.0, 1.0)
	blast.faction = DamageHit.Faction.PLAYER
	blast.with_status(CombatStatuses.CHARM, 4.0)
	var near := CrawlerMob.new()
	near.configure("charm_near", Transform3D(Basis(), Vector3(80.0, 4.0, 0.0)), 1, true)
	var far := CrawlerMob.new()
	far.configure("charm_far", Transform3D(Basis(), Vector3(88.0, 4.0, 0.0)), 1, true)
	add_child(near)
	add_child(far)
	near.set_physics_process(false)
	far.set_physics_process(false)
	var centre := blast.resolved_for(near)
	var edge := blast.resolved_for(far)
	_expect(centre.status_duration > edge.status_duration
			and edge.status_duration > 0.0,
		"charm on a blast trails off toward the edge")
	near.queue_free()
	far.queue_free()

	var burned := CrawlerRanger.new()
	burned.configure("wall_toxin", Transform3D(Basis(), Vector3(96.0, 4.0, 0.0)), 1, true)
	add_child(burned)
	burned.set_physics_process(false)
	var cold := DamageHit.impact(burned.combat_position(), 1.0, 4.0)
	cold.faction = DamageHit.Faction.PLAYER
	cold.ability_id = "wall"
	CrawlerElements.apply_to_hit(cold, CrawlerElements.payload(
		_player, "wall", {"firewall": 0.0}))
	burned.apply_damage(cold)
	_expect(not burned.statuses.has(CombatStatuses.POISON),
		"toxic on wall does nothing without firewall")
	var hot := DamageHit.impact(burned.combat_position(), 1.0, 4.0)
	hot.faction = DamageHit.Faction.PLAYER
	CrawlerElements.apply_to_hit(hot, [{
		"id": String(CombatStatuses.POISON),
		"duration": 4.0,
		"strength": 8.0,
		"stack": true,
	}], true, AbilityBarrier.FIRE_STEP)
	burned.apply_damage(hot)
	_expect(burned.statuses.has(CombatStatuses.POISON),
		"toxic on a burning wall applies poison")
	burned.queue_free()

	var chill_at := Vector3(104.0, 4.0, 0.0)
	var chilled := CrawlerFieldVolume.create(
		self, _player, "static_field", chill_at,
		{"damage": 0.0, "shock": 0.0, "freeze": 40.0,
			"radius": 7.0, "duration": 6.0, "fade_duration": 0.0},
		Color(0.48, 0.84, 1.0), true)
	if chilled != null:
		chilled._age = CrawlerFieldVolume.EXPAND
		_expect(CrawlerFieldVolume.speed_scale_at(self, chill_at) < 0.75,
			"ice on a field slows bodies and shots inside")
		chilled.queue_free()


func _check_multi_shot() -> void:
	var two := CrawlerMulti.yaw_degrees(2)
	_expect(two.size() == 2
			and is_equal_approx(two[0], -CrawlerRules.MULTI_BEAM_YAW)
			and is_equal_approx(two[1], CrawlerRules.MULTI_BEAM_YAW),
		"two-way multi shot fans to 45 degrees")
	var three := CrawlerMulti.fan_points(
		Vector3.ZERO, Vector3(0.0, 0.0, -10.0), 3, Vector3.UP)
	_expect(three.size() == 3
			and three[1].distance_to(Vector3(0.0, 0.0, -10.0)) < 0.05,
		"three-way multi shot keeps a center beam")
	var walls := CrawlerMulti.wall_offsets(5, 8.0)
	_expect(walls.size() == 5 and is_equal_approx(walls[0], 0.0),
		"five walls keep one on the player")
	_expect(CrawlerMulti.shots({"multi": 2}) == 2
			and CrawlerMulti.extras({"multi": 5}) == 4
			and CrawlerMulti.shots({}) == 1,
		"shockwaves and fields recast once per extra split")
	_expect(CrawlerRules.MULTI_ECHO_GAP == 1.0
			and CrawlerRules.MULTI_SPLIT_TRAVEL > 0.0,
		"projectiles split after they leave, blasts wait a second")
	var punches := CrawlerMulti.punch_offsets(4)
	_expect(punches.size() == 4
			and is_equal_approx(punches[1], CrawlerRules.MULTI_PUNCH_GAP),
		"physical extras sit an inch in front of each other")


func _check_reach() -> void:
	_expect(is_equal_approx(CrawlerReach.range_mul(0), CrawlerRules.REACH_RANGE_MUL)
			and is_equal_approx(CrawlerReach.far_cast_meters(0),
				CrawlerRules.REACH_FAR_CAST),
		"reach starts at 1.25x range and a two meter far cast")
	var from := Vector3.ZERO
	var along := Vector3.FORWARD
	var shifted := CrawlerReach.shift(from, along, {"far_cast": 2.0})
	_expect(shifted.distance_to(from + along * 2.0) < 0.001,
		"far cast moves the origin along the aim")
	_expect(CrawlerReach.shift(from, along, {}).is_equal_approx(from),
		"no far cast leaves the origin alone")
	var pair := CrawlerReach.shift_pair(
		Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0), {"far_cast": 2.0})
	_expect(pair.size() == 2
			and is_equal_approx(pair[0].z, 2.0)
			and is_equal_approx(pair[1].z, 2.0),
		"both eyes move forward together")
	var longer := CrawlerMulti.fan_points(
		shifted, shifted + along * 60.0 * CrawlerRules.REACH_RANGE_MUL, 3,
		Vector3.UP)
	_expect(longer.size() == 3
			and longer[1].distance_to(
				shifted + along * 60.0 * CrawlerRules.REACH_RANGE_MUL) < 0.05,
		"multi shot fans from the far-cast origin across the longer reach")


func _check_bounce() -> void:
	_expect(CrawlerRules.bounce_count(0) == CrawlerRules.BOUNCE_BASE
			and CrawlerRules.bounce_count(CrawlerRules.BOUNCE_MAX_RANK)
				== CrawlerRules.BOUNCE_MAX,
		"bounce starts at one ricochet and upgrades to five")
	var outgoing := CrawlerBounce.reflect(Vector3(1.0, -1.0, 0.0), Vector3.UP)
	_expect(outgoing.y > 0.0 and outgoing.x > 0.0,
		"bounce reflects off a surface normal")
	_expect(CrawlerBounce.count({"bounce": 3}) == 3
			and CrawlerBounce.count({}) == 0,
		"seated bounce is a count, and empty stats do not ricochet")
	var recipe := CrawlerBubbles.recipe_from(
		CrawlerCatalog.make_modifier("bubble"),
		CrawlerCatalog.make_ability("laser_eyes"),
		{"bounce": 2.0, "radius": 0.45})
	_expect(CrawlerBounce.count(recipe) == 2,
		"bubble recipes inherit bounce from the host")
	_expect(CrawlerBounce.explodes_on_bounce(ItemDB.ability_definition("mini_nuke"))
			and not CrawlerBounce.explodes_on_bounce(
				ItemDB.ability_definition("teleport")),
		"orb blasts still explode on bounce, teleport does not")


func _check_impact_cast() -> void:
	_expect(CrawlerRules.upgrade_stats_for("impact_cast").is_empty(),
		"impact cast has no upgrades")
	_expect(CrawlerImpactCast.enabled({"impact_cast": 1.0})
			and not CrawlerImpactCast.enabled(
				{"impact_cast": 1.0, "_impact_echo": 1.0}),
		"echo copies cannot nest another impact cast")
	var along := CrawlerImpactCast.random_along(Vector3.UP)
	_expect(along.is_normalized() and along.dot(Vector3.UP) > 0.0,
		"impact copies leave off the hit face")
	_expect(CrawlerImpactCast.can_echo("mini_nuke")
			and CrawlerImpactCast.can_echo("meteor_punch")
			and not CrawlerImpactCast.can_echo("teleport")
			and not CrawlerImpactCast.can_echo("wall"),
		"impact cast copies combat abilities and skips teleport and walls")
	var flagged := CrawlerCatalog.resolve_stats(
		"laser_eyes", PackedStringArray(["impact_cast"]), {})
	_expect(CrawlerImpactCast.enabled(flagged)
			and not CrawlerCatalog.resolve_stats(
				"roar", PackedStringArray(["impact_cast"]), {}).has("impact_cast"),
		"impact cast flags beams and projectiles, not shockwaves")


func _check_homing() -> void:
	_expect(is_equal_approx(CrawlerRules.homing_steer(0),
			CrawlerRules.HOMING_STEER_BASE)
			and is_equal_approx(CrawlerRules.homing_range(0),
				CrawlerRules.HOMING_RANGE_BASE)
			and CrawlerRules.upgrade_max_rank("homing", "homing")
				== CrawlerRules.HOMING_MAX_RANK,
		"homing starts at 4.5 pull / 8 m and upgrades to rank six")
	_expect(CrawlerHoming.enabled({"homing": 4.5, "homing_range": 8.0})
			and not CrawlerHoming.enabled({}),
		"seated homing is a pull-and-seek pair")
	_expect(CrawlerHoming.enabled(CrawlerCatalog.resolve_stats(
			"laser_eyes", PackedStringArray(["homing"]), {}))
			and CrawlerHoming.enabled(CrawlerCatalog.resolve_stats(
				"starfire", PackedStringArray(["homing"]), {}))
			and CrawlerHoming.enabled(CrawlerCatalog.resolve_stats(
				"meteor_punch", PackedStringArray(["homing"]), {}))
			and not CrawlerCatalog.resolve_stats(
				"roar", PackedStringArray(["homing"]), {}).has("homing"),
		"homing flags beams, shots, and punches, not shockwaves")
	var recipe := CrawlerBubbles.recipe_from(
		CrawlerCatalog.make_modifier("bubble"),
		CrawlerCatalog.make_ability("laser_eyes"),
		{"homing": 6.0, "homing_range": 11.0})
	_expect(float(recipe.get("homing", 0.0)) >= 11.0
			and float(recipe.get("steer", 0.0)) >= 6.0,
		"bubble recipes inherit host homing even at bubble homing rank 0")
	var cloud := CrawlerLingers.recipe_from(
		CrawlerCatalog.make_modifier("linger"),
		CrawlerCatalog.make_ability("laser_eyes"),
		{"homing": 6.0, "homing_range": 11.0})
	_expect(is_equal_approx(float(cloud.get("homing", 0.0)), 11.0)
			and is_equal_approx(float(cloud.get("steer", 0.0)), 6.0),
		"linger clouds inherit host homing")
	var curve := CrawlerHoming.arc(
		Vector3.ZERO, Vector3(0.0, 0.0, -6.0), Vector3.FORWARD,
		{"homing": 8.0, "homing_range": 12.0})
	_expect(curve.size() == CrawlerHoming.ARC_STEPS + 1,
		"homing draws a curved beam path")


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


func _skeleton_bone_at(host: Node, bone: String) -> Vector3:
	if host == null or bone.is_empty():
		return Vector3.INF
	var skeleton := host.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return Vector3.INF
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return Vector3.INF
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin


func _authored_inks(mob: CrawlerMob) -> Array[Color]:
	var colors: Array[Color] = []
	if mob == null:
		return colors
	var creature := mob.find_child("Creature", true, false)
	if creature == null:
		return colors
	for node_variant: Variant in creature.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material is StandardMaterial3D:
				colors.append((material as StandardMaterial3D).albedo_color)
			elif material is ShaderMaterial:
				var colour: Variant = (material as ShaderMaterial) \
					.get_shader_parameter(&"albedo")
				if colour is Color:
					colors.append(colour as Color)
	return colors


func _has_enemy_rim(mob: CrawlerMob) -> bool:
	if mob == null:
		return false
	for node_variant: Variant in mob.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		var material := mesh.material_override as ShaderMaterial
		if material == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
			material = mesh.get_active_material(0) as ShaderMaterial
		if material == null or material.shader != CrawlerMob.ENEMY_SHADER:
			continue
		var outline := material.next_pass as ShaderMaterial
		if outline != null and outline.shader == CrawlerMob.ENEMY_OUTLINE_SHADER:
			return true
	return false


func _has_bright_ink(colors: Array[Color]) -> bool:
	for color in colors:
		if maxf(color.r, maxf(color.g, color.b)) > 0.35:
			return true
	return false


func _ranger_albedo(ranger: CrawlerRanger) -> Color:
	for material in ranger._materials:
		if material == null:
			continue
		var colour: Variant = material.get_shader_parameter(&"albedo")
		if colour is Color:
			return colour as Color
	return Color.BLACK


func _has_safe_zone_row(player: OnlinePlayer) -> bool:
	if player == null:
		return false
	for row_variant: Variant in player.status_rows():
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		if StringName((row_variant as Dictionary).get("id", &"")) == &"safe_zone":
			return true
	return false


func _expect_safe_zone_dance(where: String) -> void:
	var fired := [false]
	var on_fire := func(_slot: int, _id: String) -> void: fired[0] = true
	_player.ability_activated.connect(on_fire)
	_player.activate_primary()
	_player.ability_activated.disconnect(on_fire)
	_expect(not fired[0], "clicking %s does not fire" % where)
	var dances := CharacterRig.dance_clips(_player.animator)
	_expect(not dances.is_empty(), "the body has Mixamo dances")
	var clip := ""
	if _player.animator != null:
		clip = String(_player.animator.current_animation)
	_expect(clip.begins_with("Dance_"),
		"clicking %s starts a dance (got %s)" % [where, clip])


func _safe_zone_chip_visible(player: OnlinePlayer) -> bool:
	var hud := player.combat_hud() as CombatHud if player != null else null
	if hud == null:
		return false
	hud.refresh(0.016)
	var layer := hud.status_layer()
	if layer == null:
		return false
	var chip := layer.find_child("Chip_safe_zone", true, false) as StatusChip
	if chip == null:
		return false
	for node: Node in chip.find_children("*", "Label", true, false):
		if (node as Label).text == "Safe Zone":
			return true
	return false


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


func _check_kill_loot(progress: CrawlerProgress) -> void:
	_expect(is_equal_approx(CrawlerLoot.base_chance(CrawlerLoot.KIND_HAT), 0.02)
			and is_equal_approx(CrawlerLoot.base_chance(CrawlerLoot.KIND_ABILITY), 0.02)
			and is_equal_approx(CrawlerLoot.base_chance(CrawlerLoot.KIND_MOD), 0.02),
		"hats, abilities, and mods drop at two percent")
	var plain := CrawlerLoot.drop_chance(CrawlerLoot.KIND_HAT, 0.0)
	var lucky := CrawlerLoot.drop_chance(CrawlerLoot.KIND_HAT, 16.0)
	_expect(is_equal_approx(plain, 0.02),
		"hat drops stay at two percent with no luck")
	_expect(is_equal_approx(lucky, CrawlerLoot.CHANCE_CAP)
			and is_equal_approx(
				CrawlerLoot.drop_chance(CrawlerLoot.KIND_ABILITY, 16.0),
				CrawlerLoot.CHANCE_CAP)
			and is_equal_approx(
				CrawlerLoot.drop_chance(CrawlerLoot.KIND_MOD, 16.0),
				CrawlerLoot.CHANCE_CAP),
		"luck cannot push kill drops past two percent")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var drops := CrawlerLoot.roll_kill_drops(
		progress, rng, PackedFloat32Array([0.0, 0.0, 0.0]))
	_expect(drops.size() == 3, "a lucky roll can drop an ability, a mod, and a hat")
	var kinds: PackedStringArray = PackedStringArray()
	for drop: Dictionary in drops:
		kinds.append(str(drop.get("kind", "")))
	_expect(kinds.has(CrawlerLoot.KIND_ABILITY)
			and kinds.has(CrawlerLoot.KIND_MOD)
			and kinds.has(CrawlerLoot.KIND_HAT),
		"one kill can offer every loot kind")
	_expect(CrawlerLoot.roll_kill_drops(
			progress, rng, PackedFloat32Array([0.99, 0.99, 0.99])).is_empty(),
		"an unlucky roll drops nothing")
	var before := progress.owned_hats.size()
	var uid := progress.grant_hat(CrawlerProgress.HAT_WARD)
	_expect(not uid.is_empty() and progress.owned_hats.size() == before + 1,
		"a dropped hat is granted without a gold spend")
	var hat := DroppedCrawlerHat.new()
	hat.configure(11, CrawlerProgress.HAT_MISSILE)
	add_child(hat)
	_expect(hat.find_child("HatLamp", true, false) != null
			and hat.find_child("HatVisual", true, false) != null
			and hat.find_child("PickupBeacon", true, false) != null,
		"a dropped hat is the glowing hat model over a local god-ray")
	hat.global_position = Vector3(0.0, 2.8, 0.0)
	hat.begin_settle_to(Vector3(0.0, 0.2, 0.0))
	hat._process(0.4)
	_expect(hat.global_position.y < 2.2, "dropped hats fall while they spin")
	hat.free()


func _hat_missiles() -> Array[CrawlerMissile]:
	var found: Array[CrawlerMissile] = []
	if not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMissile.GROUP):
		var missile := node_variant as CrawlerMissile
		if missile != null and is_instance_valid(missile) and not missile._spent:
			found.append(missile)
	return found


func _free_hat_missiles() -> void:
	for missile: CrawlerMissile in _hat_missiles():
		missile.free()


func _hat_mines() -> Array[CrawlerHatMine]:
	var found: Array[CrawlerHatMine] = []
	if not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerHatMine.GROUP):
		var mine := node_variant as CrawlerHatMine
		if mine != null and is_instance_valid(mine) and not mine._spent:
			found.append(mine)
	return found


func _free_hat_mines() -> void:
	for mine: CrawlerHatMine in _hat_mines():
		mine.free()


func _clear_stray_crawler_mobs() -> void:
	if not is_inside_tree():
		return
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
		var node := node_variant as Node
		if node != null and is_instance_valid(node):
			node.free()


func _advance_hat_missiles(missiles: Array[CrawlerMissile], seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step := minf(left, 0.05)
		left -= step
		for missile: CrawlerMissile in missiles:
			if is_instance_valid(missile) and not missile._spent:
				missile._physics_process(step)


func _death_home_is_on_plate(screen: DeathScreen) -> bool:
	if screen == null:
		return false
	var plate := screen.find_child("Plate", true, false) as Control
	if plate == null:
		return false
	var box := CrtType.screen_rect(plate)
	for button: Button in [screen.home_button(), screen.respawn_button()]:
		if button == null or not button.visible:
			continue
		var btn := CrtType.screen_rect(button)
		if btn.position.y < box.position.y - 1.0 \
				or btn.end.y > box.end.y + 2.0 \
				or btn.position.x < box.position.x - 1.0 \
				or btn.end.x > box.end.x + 2.0:
			return false
	return true


func _upgrade_act_width(button: Button) -> float:
	if button == null:
		return 0.0
	return CrtType.screen_rect(button).size.x


func _store_upgrades_fit(detail: Control, grid: Control) -> bool:
	if detail == null or grid == null:
		return false
	var pane := detail.get_global_rect().grow(2.0)
	var tiles: Array[Control] = []
	for child: Node in grid.get_children():
		var tile := child as Control
		if tile == null or not str(tile.name).begins_with("UpgradeTile_"):
			continue
		if not tile.visible:
			continue
		tiles.append(tile)
	if tiles.is_empty():
		return false
	for tile: Control in tiles:
		var box := tile.get_global_rect()
		if box.size.x < 8.0 or box.size.y < 8.0:
			return false
		if box.position.x < pane.position.x - 2.0 \
				or box.position.y < pane.position.y - 2.0 \
				or box.end.x > pane.end.x + 2.0 \
				or box.end.y > pane.end.y + 2.0:
			return false
	for index in tiles.size():
		var first := tiles[index].get_global_rect().grow(-2.0)
		for other in range(index + 1, tiles.size()):
			if first.intersects(tiles[other].get_global_rect().grow(-2.0)):
				return false
	return true


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_siege_test failed: %s" % label)
