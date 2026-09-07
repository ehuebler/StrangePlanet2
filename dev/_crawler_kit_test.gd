extends Node

## Headless checks for crawler abilities, modifiers, and the starter kit.
##
##     godot --headless --path . dev/_crawler_kit_test.tscn

const PLAYER := preload("res://game/player/player.tscn")

var _failures := 0
var _player: OnlinePlayer


class _HatDummy extends Node3D:
	var taken := 0.0

	func _ready() -> void:
		add_to_group(DamageHit.COMBATANT_GROUP)

	func apply_damage(hit: DamageHit) -> float:
		var amount := float(hit.amount) if hit != null else 0.0
		taken += amount
		return amount

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.5

	func combat_faction() -> int:
		return DamageHit.Faction.ENEMY

	func is_alive() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_charmed() -> bool:
		return false


func _ready() -> void:
	CrawlerCatalog.reload()
	CrawlerMeta.begin_test()
	Journal.begin_test()
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	_check_catalog()
	_check_effects()
	_check_tokens()

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	_check_starter()
	_check_spawn_arrival()
	_check_controller()
	_check_move_and_drop()
	_check_pickup_swap()
	_check_shop_full_swap()
	_check_starfire_upgrades()
	_check_light_bolt()
	_check_icicle()
	_check_teleport()
	_check_fus()
	_check_meteor_punch_upgrades()
	_check_hero_punch()
	_check_overdrive()
	_check_roar_upgrades()
	_check_starfire_big()
	_check_big_ranks()
	_check_bubble()
	_check_linger()
	_check_elemental_mods()
	_check_multi_shot()
	_check_reach()
	_check_bounce()
	_check_impact_cast()
	_check_homing()
	_check_ammo()
	_check_kame()
	_check_nausicaa()
	_check_lightning()
	_check_fields()
	_check_wall()
	_check_mini_nuke()
	_check_shared_ability_upgrades()
	_check_hero_page()
	await _check_sandbox_cheats()
	await _check_teammate_waypoint()
	await _check_city_shop_hours()
	await _check_later_cities()
	await _check_game_save()
	await _check_city_shop_stock()
	await _check_cap_merge_once()
	await _check_level_tiles()
	await _check_hud_slots()
	await _check_city_hats()
	_check_fool_cape()
	_check_city_bank()


	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	print("crawler_kit_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_catalog() -> void:
	_expect(CrawlerRules.START_CITIES == 0, "crawler does not seed a built city")
	_expect(CrawlerRules.START_PATCH == "Tide Margin 4", "crawler starts on Tide Margin 4")
	_expect(is_equal_approx(CrawlerRules.SPAWN_LATITUDE_DEG, 3.09)
			and is_equal_approx(CrawlerRules.SPAWN_LONGITUDE_DEG, -1.28),
		"spawn sits at 3.09 N, 1.28 W")
	var spawn_dir := CrawlerRules.spawn_direction()
	_expect(absf(rad_to_deg(asin(clampf(spawn_dir.y, -1.0, 1.0))) - 3.09) < 0.02,
		"spawn latitude matches the plate")
	_expect(absf(rad_to_deg(atan2(spawn_dir.x, spawn_dir.z)) + 1.28) < 0.02,
		"spawn longitude matches the plate")
	_expect(CrawlerRules.CITY_PATCH == "Quiet Inlet 4",
		"crawler city sits on Quiet Inlet 4")
	_expect(is_equal_approx(CrawlerRules.CITY_LATITUDE_DEG, 0.18)
			and is_equal_approx(CrawlerRules.CITY_LONGITUDE_DEG, 4.78),
		"Neon Fjord sits at 0.18 N, 4.78 E")
	var city_dir := CrawlerRules.city_direction()
	_expect(absf(rad_to_deg(asin(clampf(city_dir.y, -1.0, 1.0))) - 0.18) < 0.02,
		"city latitude matches the plate")
	_expect(absf(rad_to_deg(atan2(city_dir.x, city_dir.z)) - 4.78) < 0.02,
		"city longitude matches the plate")
	_expect(CrawlerRules.CITY_SITE_TITLE == "Neon Fjord",
		"the first city is Neon Fjord")
	_expect(CrawlerRules.CITY_CRESCENT_TITLE == "Crescent Market"
			and CrawlerRules.CITY_LEE_TITLE == "Lee Reach",
		"later cities are Crescent Market and Lee Reach")
	_expect(CrawlerRules.starts_visible(CrawlerRules.CITY_SITE_ID),
		"Neon Fjord is the opening waypoint")
	_expect(not CrawlerRules.starts_visible(CrawlerRules.START_SITE_ID),
		"Tide Margin waits until you walk in")
	_expect(not CrawlerRules.starts_visible(CrawlerRules.CITY_CRESCENT_SITE_ID)
			and not CrawlerRules.starts_visible(CrawlerRules.CITY_LEE_SITE_ID),
		"later cities wait until you enter Neon Fjord")
	_expect(ResourceLoader.exists(CrawlerCityRing.VILLAGE_MODEL),
		"Neon Fjord village is in the project")
	_expect(ResourceLoader.exists(CrawlerRules.CRESCENT_VILLAGE),
		"Crescent Market village is in the project")
	var city := Vector3(0.0, 0.0, 1.0)
	var tower := Vector3(1.0, 0.2, 1.0).normalized()
	var castle := Vector3(0.4, 0.7, 1.0).normalized()
	var heading := CrawlerRules.city_pair_heading(city, tower, castle)
	var toward := CrawlerRules.slide_direction(
		city, heading, CrawlerRules.CITY_OUTPOST_METRES, 8000.0)
	var away := CrawlerRules.slide_direction(
		city, heading, -CrawlerRules.CITY_OUTPOST_METRES, 8000.0)
	_expect(absf(CrawlerRules.arc_metres(city, toward, 8000.0)
			- CrawlerRules.CITY_OUTPOST_METRES) < 8.0,
		"Crescent Market sits 750 m toward the monuments")
	_expect(absf(CrawlerRules.arc_metres(city, away, 8000.0)
			- CrawlerRules.CITY_OUTPOST_METRES) < 8.0,
		"Lee Reach sits 750 m opposite the monuments")
	_expect(toward.distance_to(tower) < away.distance_to(tower)
			and toward.distance_to(castle) < away.distance_to(castle),
		"the nearer later city sits between the office and the castle")
	_expect(ResourceLoader.exists(CrawlerSpawnPad.MODEL),
		"Relay 07 is the Tide Margin spawn")
	_expect(BuildingFoundation.EMBED > 0.0, "building stems bite into the ground")
	_expect(BuildingFloraClear.PAD_METRES == 10.0, "flora keeps 10 metres off buildings")
	_expect(CrawlerCatalog.has("laser_eyes"), "catalog lists laser eyes")
	_expect(CrawlerCatalog.has("kame"), "catalog lists kame")
	_expect(CrawlerCatalog.has("nausicaa"), "catalog lists nausicaa")
	_expect(CrawlerCatalog.has("lightning"), "catalog lists lightning")
	_expect(CrawlerCatalog.has("light_bolt"), "catalog lists light bolt")
	_expect(CrawlerCatalog.has("icicle"), "catalog lists icicle")
	_expect(CrawlerCatalog.has("teleport"), "catalog lists teleport")
	_expect(CrawlerCatalog.has("fus"), "catalog lists fus")
	_expect(CrawlerCatalog.has("wall"), "catalog lists wall")
	_expect(CrawlerCatalog.has("mini_nuke"), "catalog lists mini nuke")
	_expect(CrawlerCatalog.has("meteor_punch"), "catalog lists meteor punch")
	_expect(CrawlerCatalog.has("hero_punch"), "catalog lists hero punch")
	_expect(CrawlerCatalog.has("overdrive"), "catalog lists overdrive")
	_expect(CrawlerCatalog.has("static_field") and CrawlerCatalog.has("toxic_field")
			and CrawlerCatalog.has("freeze_field")
			and CrawlerCatalog.has("healing_field"),
		"catalog lists the four field abilities")
	_expect(CrawlerCatalog.has("roar") and CrawlerCatalog.has("toxic_blast")
			and CrawlerCatalog.has("charming_aura")
			and CrawlerCatalog.has("freeze_blast"),
		"catalog lists the four roar abilities")
	_expect(CrawlerCatalog.has("wobble"), "catalog lists wobble")
	_expect(CrawlerCatalog.has("big"), "catalog lists big")
	_expect(CrawlerCatalog.has("bubble"), "catalog lists bubble")
	_expect(CrawlerCatalog.has("clip") and CrawlerCatalog.has("endless"),
		"catalog lists clip and endless")
	_expect(CrawlerCatalog.has("toxic") and CrawlerCatalog.has("shock")
			and CrawlerCatalog.has("charm") and CrawlerCatalog.has("ice"),
		"catalog lists the elemental mods")
	_expect(CrawlerCatalog.has("multi"), "catalog lists multi shot")
	_expect(CrawlerCatalog.has("reach"), "catalog lists reach")
	_expect(CrawlerCatalog.has("bounce"), "catalog lists bounce")
	_expect(CrawlerCatalog.has("impact_cast"), "catalog lists impact cast")
	_expect(CrawlerCatalog.has("homing"), "catalog lists homing")
	_expect(CrawlerCatalog.has("linger"), "catalog lists linger")
	_expect(CrawlerCatalog.is_ability("laser_eyes"), "laser eyes is an ability")
	_expect(CrawlerCatalog.is_ability("meteor_punch"), "meteor punch is an ability")
	_expect(CrawlerCatalog.is_ability("hero_punch"), "hero punch is an ability")
	_expect(CrawlerCatalog.default_slots("meteor_punch") == 3,
		"meteor punch defaults to 3 slots")
	_expect(CrawlerCatalog.default_slots("hero_punch") == CrawlerRules.HERO_PUNCH_SLOTS,
		"hero punch defaults to 3 slots")
	_expect(CrawlerCatalog.is_ability("overdrive"), "overdrive is an ability")
	_expect(CrawlerCatalog.default_slots("overdrive") == CrawlerRules.OVERDRIVE_SLOTS,
		"overdrive starts with one modifier seat")
	_expect(CrawlerCatalog.is_modifier("wobble"), "wobble is a modifier")
	_expect(CrawlerCatalog.is_modifier("bubble"), "bubble is a modifier")
	_expect(CrawlerCatalog.is_modifier("clip") and CrawlerCatalog.is_modifier("endless"),
		"clip and endless are modifiers")
	_expect(CrawlerCatalog.is_modifier("toxic") and CrawlerCatalog.is_modifier("shock")
			and CrawlerCatalog.is_modifier("charm") and CrawlerCatalog.is_modifier("ice"),
		"toxic, shock, charm, and ice are modifiers")
	_expect(CrawlerCatalog.is_modifier("multi"), "multi shot is a modifier")
	_expect(CrawlerCatalog.is_modifier("reach"), "reach is a modifier")
	_expect(CrawlerCatalog.is_modifier("bounce"), "bounce is a modifier")
	_expect(CrawlerCatalog.is_modifier("impact_cast"), "impact cast is a modifier")
	_expect(CrawlerCatalog.is_modifier("homing"), "homing is a modifier")
	_expect(CrawlerCatalog.is_modifier("linger"), "linger is a modifier")
	_expect(CrawlerCatalog.default_slots("laser_eyes") == 3, "laser eyes defaults to 3 slots")
	_expect(CrawlerCatalog.scope_of("wobble") == "type_specific", "wobble is type-specific")
	_expect(CrawlerCatalog.scope_of("bubble") == "type_specific", "bubble is type-specific")
	_expect(CrawlerCatalog.scope_of("clip") == "type_specific"
			and CrawlerCatalog.scope_of("endless") == "type_specific",
		"clip and endless are type-specific")
	_expect(CrawlerCatalog.scope_of("toxic") == "type_specific"
			and CrawlerCatalog.scope_of("shock") == "type_specific"
			and CrawlerCatalog.scope_of("charm") == "type_specific"
			and CrawlerCatalog.scope_of("ice") == "type_specific",
		"elemental mods are type-specific")
	_expect(CrawlerCatalog.scope_of("multi") == "type_specific",
		"multi shot is type-specific")
	_expect(CrawlerCatalog.scope_of("reach") == "type_specific",
		"reach is type-specific")
	_expect(CrawlerCatalog.scope_of("bounce") == "type_specific",
		"bounce is type-specific")
	_expect(CrawlerCatalog.scope_of("impact_cast") == "type_specific",
		"impact cast is type-specific")
	_expect(CrawlerCatalog.scope_of("homing") == "type_specific",
		"homing is type-specific")
	_expect(CrawlerCatalog.scope_of("linger") == "type_specific",
		"linger is type-specific")
	_expect(CrawlerCatalog.scope_of("big") == "generic", "big is generic")
	_expect(CrawlerRules.ability_type("laser_eyes") == CrawlerRules.TYPE_BEAM,
		"laser eyes is a beam")
	_expect(CrawlerRules.ability_type("kame") == CrawlerRules.TYPE_BEAM,
		"kame is a beam")
	_expect(CrawlerRules.ability_type("nausicaa") == CrawlerRules.TYPE_BEAM,
		"nausicaa is a beam")
	_expect(CrawlerRules.ability_type("lightning") == CrawlerRules.TYPE_BEAM,
		"lightning is a beam")
	_expect(CrawlerRules.ability_type("roar") == CrawlerRules.TYPE_SHOCKWAVE,
		"roar is a shockwave")
	_expect(CrawlerRules.ability_type("static_field") == CrawlerRules.TYPE_FIELD
			and CrawlerRules.ability_type("toxic_field") == CrawlerRules.TYPE_FIELD
			and CrawlerRules.ability_type("freeze_field") == CrawlerRules.TYPE_FIELD
			and CrawlerRules.ability_type("healing_field") == CrawlerRules.TYPE_FIELD,
		"the four fields share the field type")
	_expect(CrawlerRules.ability_type("starfire") == CrawlerRules.TYPE_PROJECTILE,
		"starfire is a projectile")
	_expect(CrawlerRules.ability_type("light_bolt") == CrawlerRules.TYPE_PROJECTILE,
		"light bolt is a projectile")
	_expect(CrawlerRules.ability_type("icicle") == CrawlerRules.TYPE_PROJECTILE,
		"icicle is a projectile")
	_expect(CrawlerRules.ability_type("teleport") == CrawlerRules.TYPE_PROJECTILE,
		"teleport is a projectile")
	_expect(CrawlerRules.ability_type("fus") == CrawlerRules.TYPE_PROJECTILE,
		"fus is a projectile")
	_expect(CrawlerRules.is_particle_ability("fus"),
		"fus is a particle projectile")
	_expect(CrawlerRules.ability_type("nuke") == CrawlerRules.TYPE_PROJECTILE,
		"nuke is a projectile")
	_expect(CrawlerRules.ability_type("mini_nuke") == CrawlerRules.TYPE_PROJECTILE
			and CrawlerRules.is_orb_blast("mini_nuke"),
		"mini nuke is a projectile orb blast")
	_expect(CrawlerRules.uses_ammo("nuke")
			and CrawlerRules.base_ammo("nuke") == CrawlerRules.NUKE_AMMO,
		"nuke is a limited-use ability with three shots")
	_expect(CrawlerRules.uses_ammo("mini_nuke")
			and CrawlerRules.base_ammo("mini_nuke") == CrawlerRules.MINI_NUKE_AMMO,
		"mini nuke is a limited-use ability with five shots")
	_expect(not CrawlerRules.uses_ammo("starfire")
			and not CrawlerRules.uses_ammo("light_bolt")
			and not CrawlerRules.uses_ammo("icicle")
			and not CrawlerRules.uses_ammo("teleport")
			and not CrawlerRules.uses_ammo("fus")
			and not CrawlerRules.uses_ammo("laser_eyes"),
		"other projectiles and beams do not spend shots")
	_expect(CrawlerRules.ability_type("wall") == CrawlerRules.TYPE_MISC,
		"wall is misc")
	_expect(CrawlerRules.ability_type("hero_punch") == CrawlerRules.TYPE_MISC,
		"hero punch is misc")
	_expect(CrawlerRules.ability_type("overdrive") == CrawlerRules.TYPE_MISC,
		"overdrive is misc")
	_expect(not CrawlerRules.is_roar_ability("overdrive"),
		"overdrive is not a shockwave roar")
	_expect(CrawlerCatalog.icon_path("wobble").ends_with("wobble.svg"),
		"wobble has its own icon")
	_expect(CrawlerCatalog.icon_path("bubble").ends_with("bubble.svg"),
		"bubble has its own icon")
	_expect(CrawlerCatalog.icon_path("clip").ends_with("clip.svg"),
		"clip has its own icon")
	_expect(CrawlerCatalog.icon_path("endless").ends_with("endless.svg"),
		"endless has its own icon")
	_expect(CrawlerCatalog.icon_path("toxic").ends_with("toxic.svg")
			and CrawlerCatalog.icon_path("shock").ends_with("shock.svg")
			and CrawlerCatalog.icon_path("charm").ends_with("charm.svg")
			and CrawlerCatalog.icon_path("ice").ends_with("ice.svg"),
		"elemental mods have their own icons")
	_expect(CrawlerCatalog.icon_path("multi").ends_with("multi.svg"),
		"multi shot has its own icon")
	_expect(CrawlerCatalog.icon_path("reach").ends_with("reach.svg"),
		"reach has its own icon")
	_expect(CrawlerCatalog.icon_path("bounce").ends_with("bounce.svg"),
		"bounce has its own icon")
	_expect(CrawlerCatalog.icon_path("impact_cast").ends_with("impact_cast.svg"),
		"impact cast has its own icon")
	_expect(CrawlerCatalog.icon_path("homing").ends_with("homing.svg"),
		"homing has its own icon")
	_expect(CrawlerCatalog.icon_path("linger").ends_with("linger.svg"),
		"linger has its own icon")
	var wobble_hosts := CrawlerCatalog.host_abilities("wobble")
	_expect(wobble_hosts.has("laser_eyes") and wobble_hosts.has("nausicaa")
			and wobble_hosts.has("kame") and wobble_hosts.has("lightning"),
		"wobble hosts the beam abilities")
	_expect(CrawlerCatalog.host_abilities("bubble").has("roar")
			and CrawlerCatalog.host_abilities("bubble").has("starfire")
			and CrawlerCatalog.host_abilities("bubble").has("laser_eyes")
			and CrawlerCatalog.host_abilities("bubble").has("kame")
			and CrawlerCatalog.host_abilities("bubble").has("nausicaa")
			and CrawlerCatalog.host_abilities("bubble").has("mini_nuke")
			and CrawlerCatalog.host_abilities("bubble").has("static_field")
			and CrawlerCatalog.host_abilities("bubble").has("hero_punch")
			and CrawlerCatalog.host_abilities("bubble").has("meteor_punch"),
		"bubble hosts beam, shockwave, projectile, field, and punch abilities")
	_expect(CrawlerCatalog.host_abilities("clip").has("nuke")
			and CrawlerCatalog.host_abilities("endless").has("nuke")
			and CrawlerCatalog.host_abilities("clip").has("mini_nuke")
			and CrawlerCatalog.host_abilities("endless").has("mini_nuke"),
		"clip and endless host limited-use abilities")
	_expect(not CrawlerCatalog.host_abilities("clip").has("starfire")
			and not CrawlerCatalog.host_abilities("endless").has("laser_eyes"),
		"clip and endless do not host unlimited abilities")
	_expect(not CrawlerCatalog.host_abilities("bubble").has("wall"),
		"bubble does not host misc abilities")
	_expect(CrawlerCatalog.host_abilities("toxic").has("laser_eyes")
			and CrawlerCatalog.host_abilities("toxic").has("roar")
			and CrawlerCatalog.host_abilities("toxic").has("mini_nuke")
			and CrawlerCatalog.host_abilities("toxic").has("static_field")
			and CrawlerCatalog.host_abilities("toxic").has("wall")
			and CrawlerCatalog.host_abilities("toxic").has("hero_punch")
			and CrawlerCatalog.host_abilities("toxic").has("meteor_punch"),
		"toxic hosts beams, shockwaves, projectiles, fields, punches, and wall")
	_expect(not CrawlerCatalog.host_abilities("toxic").has("lasso")
			and not CrawlerCatalog.host_abilities("shock").has("grapple"),
		"elemental mods do not host grapple or lasso")
	_expect(CrawlerCatalog.host_abilities("multi").has("laser_eyes")
			and CrawlerCatalog.host_abilities("multi").has("starfire")
			and CrawlerCatalog.host_abilities("multi").has("roar")
			and CrawlerCatalog.host_abilities("multi").has("static_field")
			and CrawlerCatalog.host_abilities("multi").has("wall")
			and CrawlerCatalog.host_abilities("multi").has("meteor_punch")
			and CrawlerCatalog.host_abilities("multi").has("hero_punch"),
		"multi shot hosts beams, shots, walls, blasts, fields, and punches")
	_expect(not CrawlerCatalog.host_abilities("multi").has("lasso")
			and not CrawlerCatalog.host_abilities("multi").has("grapple"),
		"multi shot does not host grapple or lasso")
	_expect(CrawlerCatalog.host_abilities("reach").has("laser_eyes")
			and CrawlerCatalog.host_abilities("reach").has("kame")
			and CrawlerCatalog.host_abilities("reach").has("nausicaa")
			and CrawlerCatalog.host_abilities("reach").has("lightning")
			and CrawlerCatalog.host_abilities("reach").has("starfire")
			and CrawlerCatalog.host_abilities("reach").has("light_bolt")
			and CrawlerCatalog.host_abilities("reach").has("icicle")
			and CrawlerCatalog.host_abilities("reach").has("teleport")
			and CrawlerCatalog.host_abilities("reach").has("fus")
			and CrawlerCatalog.host_abilities("reach").has("nuke")
			and CrawlerCatalog.host_abilities("reach").has("mini_nuke"),
		"reach hosts beams and projectiles")
	_expect(not CrawlerCatalog.host_abilities("reach").has("roar")
			and not CrawlerCatalog.host_abilities("reach").has("static_field")
			and not CrawlerCatalog.host_abilities("reach").has("wall")
			and not CrawlerCatalog.host_abilities("reach").has("meteor_punch")
			and not CrawlerCatalog.host_abilities("reach").has("hero_punch")
			and not CrawlerCatalog.host_abilities("reach").has("lasso")
			and not CrawlerCatalog.host_abilities("reach").has("grapple"),
		"reach does not host fields, shockwaves, walls, or physical attacks")
	_expect(CrawlerCatalog.host_abilities("bounce").has("laser_eyes")
			and CrawlerCatalog.host_abilities("bounce").has("kame")
			and CrawlerCatalog.host_abilities("bounce").has("nausicaa")
			and CrawlerCatalog.host_abilities("bounce").has("lightning")
			and CrawlerCatalog.host_abilities("bounce").has("starfire")
			and CrawlerCatalog.host_abilities("bounce").has("light_bolt")
			and CrawlerCatalog.host_abilities("bounce").has("icicle")
			and CrawlerCatalog.host_abilities("bounce").has("teleport")
			and CrawlerCatalog.host_abilities("bounce").has("fus")
			and CrawlerCatalog.host_abilities("bounce").has("nuke")
			and CrawlerCatalog.host_abilities("bounce").has("mini_nuke"),
		"bounce hosts beams and projectiles")
	_expect(not CrawlerCatalog.host_abilities("bounce").has("roar")
			and not CrawlerCatalog.host_abilities("bounce").has("static_field")
			and not CrawlerCatalog.host_abilities("bounce").has("wall")
			and not CrawlerCatalog.host_abilities("bounce").has("meteor_punch")
			and not CrawlerCatalog.host_abilities("bounce").has("hero_punch")
			and not CrawlerCatalog.host_abilities("bounce").has("lasso")
			and not CrawlerCatalog.host_abilities("bounce").has("grapple"),
		"bounce does not host fields, shockwaves, walls, or physical attacks")
	_expect(CrawlerCatalog.host_abilities("impact_cast").has("laser_eyes")
			and CrawlerCatalog.host_abilities("impact_cast").has("kame")
			and CrawlerCatalog.host_abilities("impact_cast").has("nausicaa")
			and CrawlerCatalog.host_abilities("impact_cast").has("lightning")
			and CrawlerCatalog.host_abilities("impact_cast").has("starfire")
			and CrawlerCatalog.host_abilities("impact_cast").has("light_bolt")
			and CrawlerCatalog.host_abilities("impact_cast").has("icicle")
			and CrawlerCatalog.host_abilities("impact_cast").has("teleport")
			and CrawlerCatalog.host_abilities("impact_cast").has("fus")
			and CrawlerCatalog.host_abilities("impact_cast").has("nuke")
			and CrawlerCatalog.host_abilities("impact_cast").has("mini_nuke"),
		"impact cast hosts beams and projectiles")
	_expect(not CrawlerCatalog.host_abilities("impact_cast").has("roar")
			and not CrawlerCatalog.host_abilities("impact_cast").has("static_field")
			and not CrawlerCatalog.host_abilities("impact_cast").has("wall")
			and not CrawlerCatalog.host_abilities("impact_cast").has("meteor_punch")
			and not CrawlerCatalog.host_abilities("impact_cast").has("hero_punch")
			and not CrawlerCatalog.host_abilities("impact_cast").has("lasso")
			and not CrawlerCatalog.host_abilities("impact_cast").has("grapple"),
		"impact cast does not host fields, shockwaves, walls, or physical attacks")
	_expect(CrawlerCatalog.host_abilities("homing").has("laser_eyes")
			and CrawlerCatalog.host_abilities("homing").has("kame")
			and CrawlerCatalog.host_abilities("homing").has("nausicaa")
			and CrawlerCatalog.host_abilities("homing").has("lightning")
			and CrawlerCatalog.host_abilities("homing").has("starfire")
			and CrawlerCatalog.host_abilities("homing").has("light_bolt")
			and CrawlerCatalog.host_abilities("homing").has("icicle")
			and CrawlerCatalog.host_abilities("homing").has("teleport")
			and CrawlerCatalog.host_abilities("homing").has("fus")
			and CrawlerCatalog.host_abilities("homing").has("nuke")
			and CrawlerCatalog.host_abilities("homing").has("mini_nuke")
			and CrawlerCatalog.host_abilities("homing").has("meteor_punch")
			and CrawlerCatalog.host_abilities("homing").has("hero_punch"),
		"homing hosts beams, projectiles, and punches")
	_expect(not CrawlerCatalog.host_abilities("homing").has("roar")
			and not CrawlerCatalog.host_abilities("homing").has("static_field")
			and not CrawlerCatalog.host_abilities("homing").has("wall")
			and not CrawlerCatalog.host_abilities("homing").has("lasso")
			and not CrawlerCatalog.host_abilities("homing").has("grapple"),
		"homing does not host fields, shockwaves, walls, or hooks")
	_expect(CrawlerCatalog.host_abilities("big").is_empty(),
		"generic mods have no host badge")
	_expect(CrawlerCatalog.host_types("wobble") == PackedStringArray(["beam"]),
		"wobble matches the beam type")
	_expect(CrawlerCatalog.host_types("bubble") == PackedStringArray(
			["beam", "shockwave", "projectile", "field", "misc"]),
		"bubble matches beam, shockwave, projectile, field, and punches")
	_expect(CrawlerCatalog.host_types("clip") == PackedStringArray(["limited"])
			and CrawlerCatalog.host_types("endless") == PackedStringArray(["limited"]),
		"clip and endless match the limited type")
	_expect(CrawlerCatalog.host_types("reach") == PackedStringArray(
			["beam", "projectile"]),
		"reach matches beams and projectiles")
	_expect(CrawlerCatalog.host_types("bounce") == PackedStringArray(
			["beam", "projectile"]),
		"bounce matches beams and projectiles")
	_expect(CrawlerCatalog.host_types("impact_cast") == PackedStringArray(
			["beam", "projectile"]),
		"impact cast matches beams and projectiles")
	_expect(CrawlerCatalog.host_types("homing") == PackedStringArray(
			["beam", "projectile", "misc"]),
		"homing matches beams, projectiles, and punches")
	_expect(CrawlerCatalog.host_types("linger") == PackedStringArray(
			["beam", "shockwave", "projectile", "field", "misc"]),
		"linger matches beams, shockwaves, projectiles, fields, and punches")
	var toxic_types := CrawlerCatalog.host_types("toxic")
	_expect(toxic_types.has("beam") and toxic_types.has("shockwave")
			and toxic_types.has("projectile") and toxic_types.has("field")
			and toxic_types.has("misc") and not toxic_types.has("limited"),
		"toxic matches typed hosts plus other")
	_expect(CrawlerCatalog.host_types("big").is_empty(),
		"generic mods have no type badges")
	_expect(CrawlerCatalog.display_types("laser_eyes")
			== PackedStringArray(["beam"]),
		"laser eyes displays as a beam")
	_expect(CrawlerCatalog.display_types("wobble")
			== CrawlerCatalog.host_types("wobble"),
		"mods display their matching types")
	_expect(CrawlerCatalog.type_icon("beam") != null
			and CrawlerCatalog.type_icon("shockwave") != null
			and CrawlerCatalog.type_icon("projectile") != null
			and CrawlerCatalog.type_icon("field") != null
			and CrawlerCatalog.type_icon("limited") != null
			and CrawlerCatalog.type_icon("misc") != null,
		"every ability type has an icon")
	_expect(CrawlerCatalog.type_line("laser_eyes") == "TYPE  //  BEAM",
		"ability descriptions name the type")
	_expect(CrawlerCatalog.type_line("wobble") == "FITS  //  BEAM",
		"mod descriptions name matching types")
	_expect(CrawlerCatalog.texture_for("big") != null, "big has a generic icon")
	_expect(CrawlerCatalog.texture_for("wobble") != null, "wobble has an icon")
	_expect(CrawlerCatalog.texture_for("bubble") != null, "bubble has an icon")
	_expect(CrawlerCatalog.texture_for("linger") != null, "linger has an icon")
	_expect(CrawlerCatalog.texture_for("homing") != null, "homing has an icon")
	var card := CrawlerCatalog.make_ability("laser_eyes")
	_expect(card != null and card.slot_count == 3, "make_ability reads slot count from csv")
	_expect(CrawlerCatalog.make_modifier("wobble") != null, "make_modifier reads wobble from csv")
	_expect(CrawlerCatalog.make_modifier("bubble") != null, "make_modifier reads bubble from csv")
	_expect(CrawlerCatalog.make_modifier("clip") != null
			and CrawlerCatalog.make_modifier("endless") != null,
		"make_modifier reads clip and endless from csv")
	_expect(CrawlerCatalog.make_modifier("toxic") != null
			and CrawlerCatalog.make_modifier("ice") != null,
		"make_modifier reads elemental mods from csv")
	_expect(CrawlerCatalog.make_modifier("multi") != null,
		"make_modifier reads multi shot from csv")
	_expect(CrawlerCatalog.make_modifier("reach") != null,
		"make_modifier reads reach from csv")
	_expect(CrawlerCatalog.make_modifier("bounce") != null,
		"make_modifier reads bounce from csv")
	_expect(CrawlerCatalog.make_modifier("impact_cast") != null,
		"make_modifier reads impact cast from csv")
	_expect(CrawlerCatalog.make_modifier("homing") != null,
		"make_modifier reads homing from csv")
	_expect(CrawlerCatalog.make_modifier("linger") != null,
		"make_modifier reads linger from csv")


func _check_effects() -> void:
	_expect(CrawlerCatalog.compatible("wobble", "laser_eyes"), "wobble fits laser eyes")
	_expect(CrawlerCatalog.compatible("wobble", "kame"), "wobble fits kame")
	_expect(CrawlerCatalog.compatible("wobble", "nausicaa"), "wobble fits nausicaa")
	var nausicaa := CrawlerCatalog.resolve_stats(
		"nausicaa", PackedStringArray(["wobble"]), {})
	_expect(float(nausicaa.get("wobble", 0.0)) == 1.0, "wobble flags nausicaa")
	_expect(not CrawlerCatalog.compatible("wobble", "nuke"), "wobble does not fit nuke")
	_expect(CrawlerCatalog.compatible("bubble", "laser_eyes"), "bubble fits laser eyes")
	_expect(CrawlerCatalog.compatible("bubble", "kame"), "bubble fits kame")
	_expect(CrawlerCatalog.compatible("bubble", "nausicaa"), "bubble fits nausicaa")
	_expect(CrawlerCatalog.compatible("bubble", "roar"), "bubble fits roar")
	_expect(CrawlerCatalog.compatible("bubble", "toxic_blast"), "bubble fits toxic blast")
	_expect(CrawlerCatalog.compatible("bubble", "starfire"), "bubble fits starfire")
	_expect(CrawlerCatalog.compatible("bubble", "light_bolt"), "bubble fits light bolt")
	_expect(CrawlerCatalog.compatible("bubble", "icicle"), "bubble fits icicle")
	_expect(CrawlerCatalog.compatible("bubble", "teleport"), "bubble fits teleport")
	_expect(CrawlerCatalog.compatible("bubble", "fus"), "bubble fits fus")
	_expect(CrawlerCatalog.compatible("bubble", "nuke"), "bubble fits nuke")
	_expect(CrawlerCatalog.compatible("bubble", "mini_nuke"), "bubble fits mini nuke")
	_expect(CrawlerCatalog.compatible("bubble", "static_field")
			and CrawlerCatalog.compatible("bubble", "toxic_field")
			and CrawlerCatalog.compatible("bubble", "freeze_field")
			and CrawlerCatalog.compatible("bubble", "healing_field"),
		"bubble fits field abilities")
	_expect(CrawlerCatalog.compatible("linger", "laser_eyes")
			and CrawlerCatalog.compatible("linger", "roar")
			and CrawlerCatalog.compatible("linger", "starfire")
			and CrawlerCatalog.compatible("linger", "static_field")
			and CrawlerCatalog.compatible("linger", "meteor_punch")
			and CrawlerCatalog.compatible("linger", "hero_punch"),
		"linger fits beams, shockwaves, shots, fields, and punches")
	_expect(not CrawlerCatalog.compatible("linger", "wall")
			and not CrawlerCatalog.compatible("linger", "lasso"),
		"linger does not fit wall or lasso")
	_expect(CrawlerCatalog.compatible("big", "static_field")
			and CrawlerCatalog.compatible("big", "healing_field"),
		"big fits field abilities")
	_expect(not CrawlerCatalog.compatible("wobble", "static_field")
			and not CrawlerCatalog.compatible("wobble", "toxic_field")
			and not CrawlerCatalog.compatible("wobble", "freeze_field")
			and not CrawlerCatalog.compatible("wobble", "healing_field"),
		"wobble does not fit field abilities")
	_expect(CrawlerCatalog.compatible("clip", "nuke"), "clip fits nuke")
	_expect(CrawlerCatalog.compatible("clip", "mini_nuke"), "clip fits mini nuke")
	_expect(CrawlerCatalog.compatible("endless", "nuke"), "endless fits nuke")
	_expect(CrawlerCatalog.compatible("endless", "mini_nuke"), "endless fits mini nuke")
	_expect(not CrawlerCatalog.compatible("wobble", "mini_nuke")
			and not CrawlerCatalog.compatible("wobble", "light_bolt")
			and not CrawlerCatalog.compatible("wobble", "icicle")
			and not CrawlerCatalog.compatible("wobble", "teleport")
			and not CrawlerCatalog.compatible("wobble", "fus"),
		"wobble does not fit mini nuke or particle throws")
	_expect(not CrawlerCatalog.compatible("clip", "laser_eyes"),
		"clip does not fit laser eyes")
	_expect(not CrawlerCatalog.compatible("clip", "kame")
			and not CrawlerCatalog.compatible("endless", "kame"),
		"clip and endless do not fit kame")
	_expect(not CrawlerCatalog.compatible("endless", "starfire"),
		"endless does not fit starfire")
	_expect(not CrawlerCatalog.compatible("bubble", "wall"), "bubble does not fit wall")
	_expect(not CrawlerCatalog.compatible("wobble", "wall")
			and not CrawlerCatalog.compatible("clip", "wall")
			and not CrawlerCatalog.compatible("endless", "wall"),
		"beam and ammo mods do not fit wall")
	_expect(CrawlerCatalog.compatible("big", "wall"), "big fits wall")
	_expect(CrawlerCatalog.compatible("toxic", "laser_eyes")
			and CrawlerCatalog.compatible("shock", "roar")
			and CrawlerCatalog.compatible("charm", "mini_nuke")
			and CrawlerCatalog.compatible("ice", "static_field")
			and CrawlerCatalog.compatible("toxic", "healing_field")
			and CrawlerCatalog.compatible("shock", "healing_field")
			and CrawlerCatalog.compatible("charm", "healing_field")
			and CrawlerCatalog.compatible("ice", "healing_field")
			and CrawlerCatalog.compatible("toxic", "wall")
			and CrawlerCatalog.compatible("charm", "hero_punch")
			and CrawlerCatalog.compatible("shock", "overdrive"),
		"elemental mods fit damage hosts and overdrive")
	_expect(not CrawlerCatalog.compatible("toxic", "lasso")
			and not CrawlerCatalog.compatible("ice", "grapple"),
		"elemental mods do not fit grapple or lasso")
	_expect(CrawlerCatalog.compatible("multi", "laser_eyes")
			and CrawlerCatalog.compatible("multi", "kame")
			and CrawlerCatalog.compatible("multi", "nausicaa")
			and CrawlerCatalog.compatible("multi", "lightning")
			and CrawlerCatalog.compatible("multi", "starfire")
			and CrawlerCatalog.compatible("multi", "light_bolt")
			and CrawlerCatalog.compatible("multi", "icicle")
			and CrawlerCatalog.compatible("multi", "teleport")
			and CrawlerCatalog.compatible("multi", "fus")
			and CrawlerCatalog.compatible("multi", "mini_nuke")
			and CrawlerCatalog.compatible("multi", "roar")
			and CrawlerCatalog.compatible("multi", "static_field")
			and CrawlerCatalog.compatible("multi", "healing_field")
			and CrawlerCatalog.compatible("multi", "wall")
			and CrawlerCatalog.compatible("multi", "meteor_punch")
			and CrawlerCatalog.compatible("multi", "hero_punch"),
		"multi shot fits beams, shots, walls, blasts, fields, and punches")
	_expect(not CrawlerCatalog.compatible("multi", "lasso")
			and not CrawlerCatalog.compatible("multi", "grapple"),
		"multi shot does not fit grapple or lasso")
	_expect(CrawlerCatalog.compatible("reach", "laser_eyes")
			and CrawlerCatalog.compatible("reach", "kame")
			and CrawlerCatalog.compatible("reach", "nausicaa")
			and CrawlerCatalog.compatible("reach", "lightning")
			and CrawlerCatalog.compatible("reach", "starfire")
			and CrawlerCatalog.compatible("reach", "light_bolt")
			and CrawlerCatalog.compatible("reach", "icicle")
			and CrawlerCatalog.compatible("reach", "teleport")
			and CrawlerCatalog.compatible("reach", "fus")
			and CrawlerCatalog.compatible("reach", "nuke")
			and CrawlerCatalog.compatible("reach", "mini_nuke"),
		"reach fits beams and projectiles")
	_expect(not CrawlerCatalog.compatible("reach", "roar")
			and not CrawlerCatalog.compatible("reach", "static_field")
			and not CrawlerCatalog.compatible("reach", "healing_field")
			and not CrawlerCatalog.compatible("reach", "wall")
			and not CrawlerCatalog.compatible("reach", "meteor_punch")
			and not CrawlerCatalog.compatible("reach", "hero_punch")
			and not CrawlerCatalog.compatible("reach", "lasso")
			and not CrawlerCatalog.compatible("reach", "grapple"),
		"reach does not fit fields, shockwaves, walls, or physical attacks")
	_expect(CrawlerCatalog.compatible("bounce", "laser_eyes")
			and CrawlerCatalog.compatible("bounce", "kame")
			and CrawlerCatalog.compatible("bounce", "nausicaa")
			and CrawlerCatalog.compatible("bounce", "lightning")
			and CrawlerCatalog.compatible("bounce", "starfire")
			and CrawlerCatalog.compatible("bounce", "light_bolt")
			and CrawlerCatalog.compatible("bounce", "icicle")
			and CrawlerCatalog.compatible("bounce", "teleport")
			and CrawlerCatalog.compatible("bounce", "fus")
			and CrawlerCatalog.compatible("bounce", "nuke")
			and CrawlerCatalog.compatible("bounce", "mini_nuke"),
		"bounce fits beams and projectiles")
	_expect(not CrawlerCatalog.compatible("bounce", "roar")
			and not CrawlerCatalog.compatible("bounce", "static_field")
			and not CrawlerCatalog.compatible("bounce", "healing_field")
			and not CrawlerCatalog.compatible("bounce", "wall")
			and not CrawlerCatalog.compatible("bounce", "meteor_punch")
			and not CrawlerCatalog.compatible("bounce", "hero_punch")
			and not CrawlerCatalog.compatible("bounce", "lasso")
			and not CrawlerCatalog.compatible("bounce", "grapple"),
		"bounce does not fit fields, shockwaves, walls, or physical attacks")
	_expect(CrawlerCatalog.compatible("impact_cast", "laser_eyes")
			and CrawlerCatalog.compatible("impact_cast", "kame")
			and CrawlerCatalog.compatible("impact_cast", "nausicaa")
			and CrawlerCatalog.compatible("impact_cast", "lightning")
			and CrawlerCatalog.compatible("impact_cast", "starfire")
			and CrawlerCatalog.compatible("impact_cast", "light_bolt")
			and CrawlerCatalog.compatible("impact_cast", "icicle")
			and CrawlerCatalog.compatible("impact_cast", "teleport")
			and CrawlerCatalog.compatible("impact_cast", "fus")
			and CrawlerCatalog.compatible("impact_cast", "nuke")
			and CrawlerCatalog.compatible("impact_cast", "mini_nuke"),
		"impact cast fits beams and projectiles")
	_expect(not CrawlerCatalog.compatible("impact_cast", "roar")
			and not CrawlerCatalog.compatible("impact_cast", "static_field")
			and not CrawlerCatalog.compatible("impact_cast", "healing_field")
			and not CrawlerCatalog.compatible("impact_cast", "wall")
			and not CrawlerCatalog.compatible("impact_cast", "meteor_punch")
			and not CrawlerCatalog.compatible("impact_cast", "hero_punch")
			and not CrawlerCatalog.compatible("impact_cast", "lasso")
			and not CrawlerCatalog.compatible("impact_cast", "grapple"),
		"impact cast does not fit fields, shockwaves, walls, or physical attacks")
	_expect(CrawlerCatalog.compatible("homing", "laser_eyes")
			and CrawlerCatalog.compatible("homing", "kame")
			and CrawlerCatalog.compatible("homing", "nausicaa")
			and CrawlerCatalog.compatible("homing", "lightning")
			and CrawlerCatalog.compatible("homing", "starfire")
			and CrawlerCatalog.compatible("homing", "light_bolt")
			and CrawlerCatalog.compatible("homing", "icicle")
			and CrawlerCatalog.compatible("homing", "teleport")
			and CrawlerCatalog.compatible("homing", "fus")
			and CrawlerCatalog.compatible("homing", "nuke")
			and CrawlerCatalog.compatible("homing", "mini_nuke")
			and CrawlerCatalog.compatible("homing", "meteor_punch")
			and CrawlerCatalog.compatible("homing", "hero_punch"),
		"homing fits beams, projectiles, and punches")
	_expect(not CrawlerCatalog.compatible("homing", "roar")
			and not CrawlerCatalog.compatible("homing", "static_field")
			and not CrawlerCatalog.compatible("homing", "healing_field")
			and not CrawlerCatalog.compatible("homing", "wall")
			and not CrawlerCatalog.compatible("homing", "lasso")
			and not CrawlerCatalog.compatible("homing", "grapple"),
		"homing does not fit fields, shockwaves, walls, or hooks")
	_expect(CrawlerCatalog.compatible("bubble", "meteor_punch")
			and CrawlerCatalog.compatible("bubble", "hero_punch"),
		"bubble fits the punches")
	_expect(not CrawlerCatalog.compatible("wobble", "hero_punch")
			and not CrawlerCatalog.compatible("clip", "hero_punch"),
		"beam and ammo mods do not fit hero punch")
	_expect(CrawlerCatalog.compatible("big", "hero_punch"), "big fits hero punch")
	_expect(CrawlerCatalog.compatible("big", "overdrive")
			and CrawlerCatalog.compatible("wobble", "overdrive")
			and CrawlerCatalog.compatible("bubble", "overdrive")
			and CrawlerCatalog.compatible("linger", "overdrive")
			and CrawlerCatalog.compatible("clip", "overdrive")
			and CrawlerCatalog.compatible("multi", "overdrive")
			and CrawlerCatalog.compatible("reach", "overdrive")
			and CrawlerCatalog.compatible("bounce", "overdrive")
			and CrawlerCatalog.compatible("impact_cast", "overdrive")
			and CrawlerCatalog.compatible("homing", "overdrive"),
		"every modifier can sit on overdrive")
	_expect(CrawlerCatalog.compatible("big", "nuke"), "big fits nuke")
	_expect(CrawlerCatalog.compatible("big", "mini_nuke"), "big fits mini nuke")
	_expect(CrawlerCatalog.compatible("big", "freeze_field"), "big fits freeze field")
	_expect(not CrawlerCatalog.compatible("clip", "healing_field")
			and not CrawlerCatalog.compatible("endless", "healing_field"),
		"clip and endless do not fit healing field")
	var laser := CrawlerCatalog.resolve_stats(
		"laser_eyes", PackedStringArray(["wobble", "big"]), {"radius": 0.45})
	_expect(float(laser.get("wobble", 0.0)) == 1.0, "wobble flags laser eyes")
	_expect(is_equal_approx(float(laser.get("radius", 0.0)),
			0.45 * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies laser radius")
	var nuke := CrawlerCatalog.resolve_stats(
		"nuke", PackedStringArray(["big"]), {"radius": 110.0, "crater_radius": 72.0})
	_expect(is_equal_approx(float(nuke.get("radius", 0.0)),
			110.0 * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies nuke radius from the ability-specific row")
	var mini := CrawlerCatalog.resolve_stats(
		"mini_nuke", PackedStringArray(["big"]),
		{"radius": CrawlerRules.MINI_NUKE_RADIUS,
			"crater_radius": CrawlerRules.MINI_NUKE_CRATER_RADIUS,
			"projectile_radius": CrawlerRules.MINI_NUKE_PROJECTILE_RADIUS})
	_expect(is_equal_approx(float(mini.get("radius", 0.0)),
			CrawlerRules.MINI_NUKE_RADIUS * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies mini nuke blast radius")
	var star := CrawlerCatalog.resolve_stats(
		"starfire", PackedStringArray(["big"]),
		{"radius": 4.5, "projectile_radius": 0.36, "crater_radius": 3.0})
	_expect(is_equal_approx(float(star.get("radius", 0.0)),
			4.5 * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies starfire burst radius")
	_expect(is_equal_approx(float(star.get("projectile_radius", 0.0)),
			0.36 * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies starfire disk radius")
	var meteor := CrawlerCatalog.resolve_stats(
		"meteor_punch", PackedStringArray(["big"]),
		{"radius": 2.4, "crater_radius": 3.6})
	_expect(is_equal_approx(float(meteor.get("radius", 0.0)),
			2.4 * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies meteor punch fist radius")
	_expect(is_equal_approx(float(meteor.get("crater_radius", 0.0)),
			3.6 * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies meteor punch crater")
	var jab := CrawlerCatalog.resolve_stats(
		"hero_punch", PackedStringArray(["big"]),
		{"radius": CrawlerRules.HERO_PUNCH_RADIUS})
	_expect(is_equal_approx(float(jab.get("radius", 0.0)),
			CrawlerRules.HERO_PUNCH_RADIUS * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies hero punch fist radius")
	var star_copy := CrawlerCatalog.description_of("big", "starfire")
	_expect(star_copy.contains(CrawlerRules.format_mul(CrawlerRules.big_size_scale(0)))
			and star_copy.contains("Starfire"),
		"seated big names the starfire size boost")
	var laser_copy := CrawlerCatalog.description_of("big", "laser_eyes")
	_expect(laser_copy.contains(CrawlerRules.format_mul(CrawlerRules.big_size_scale(0)))
			and laser_copy.contains("Laser Eyes"),
		"seated big names the laser size boost")
	var kame_big := CrawlerCatalog.resolve_stats(
		"kame", PackedStringArray(["big"]),
		{"radius": CrawlerRules.KAME_RADIUS, "beam_width": CrawlerRules.KAME_BEAM_WIDTH})
	_expect(is_equal_approx(float(kame_big.get("radius", 0.0)),
			CrawlerRules.KAME_RADIUS * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies kame radius")
	_expect(is_equal_approx(float(kame_big.get("beam_width", 0.0)),
			CrawlerRules.KAME_BEAM_WIDTH * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies kame beam width")
	var wall_big := CrawlerCatalog.resolve_stats(
		"wall", PackedStringArray(["big"]), CrawlerRules.wall_start_stats())
	_expect(is_equal_approx(float(wall_big.get("wall_width", 0.0)),
			CrawlerRules.WALL_WIDTH * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies wall width")
	_expect(is_equal_approx(float(wall_big.get("wall_height", 0.0)),
			CrawlerRules.WALL_HEIGHT * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies wall height")
	var loose := CrawlerCatalog.description_of("big")
	_expect(loose.contains(CrawlerRules.format_mul(CrawlerRules.big_size_scale(0)))
			and loose.contains(str(CrawlerRules.BIG_SIZE_MAX_RANK)),
		"unseated big names the starting scale and max level")


func _check_tokens() -> void:
	var card := CrawlerCatalog.make_ability("laser_eyes", 4)
	var token := card.token()
	_expect(CrawlerCatalog.is_ability_token(token), "ability token is recognised")
	_expect(ItemDB.is_ability(token), "ItemDB treats the token as an ability")
	_expect(ItemDB.accepts_ability(token), "ability slots accept the token")
	_expect(ItemDB.title(token) == "Laser Eyes", "token title resolves")
	var mod := CrawlerCatalog.make_modifier("big")
	_expect(ItemDB.kind_of(mod.token()) == ItemDB.KIND_MODIFIER, "mod token kind")
	_expect(ItemDB.accepts(CrawlerCatalog.FILTER_KIT, mod.token()),
		"kit filter accepts a modifier token")
	_expect(ItemDB.accepts("%s:laser_eyes" % CrawlerCatalog.FILTER_MOD, mod.token()),
		"laser eyes mod slot accepts big")
	_expect(not ItemDB.accepts("%s:nuke" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("wobble").token()),
		"nuke mod slot refuses wobble")
	_expect(ItemDB.accepts("%s:nuke" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("clip").token()),
		"nuke mod slot accepts clip")
	_expect(ItemDB.accepts("%s:mini_nuke" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("clip").token())
			and ItemDB.accepts("%s:mini_nuke" % CrawlerCatalog.FILTER_MOD,
				CrawlerCatalog.make_modifier("bubble").token())
			and ItemDB.accepts("%s:mini_nuke" % CrawlerCatalog.FILTER_MOD,
				CrawlerCatalog.make_modifier("big").token()),
		"mini nuke mod slot accepts clip, bubble, and big")
	_expect(not ItemDB.accepts("%s:mini_nuke" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("wobble").token()),
		"mini nuke mod slot refuses wobble")
	_expect(not ItemDB.accepts("%s:laser_eyes" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("endless").token()),
		"laser eyes mod slot refuses endless")
	_expect(ItemDB.accepts("%s:wall" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("big").token()),
		"wall mod slot accepts big")
	_expect(not ItemDB.accepts("%s:wall" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("wobble").token())
			and not ItemDB.accepts("%s:wall" % CrawlerCatalog.FILTER_MOD,
				CrawlerCatalog.make_modifier("bubble").token())
			and not ItemDB.accepts("%s:wall" % CrawlerCatalog.FILTER_MOD,
				CrawlerCatalog.make_modifier("clip").token()),
		"wall mod slot refuses beam, bubble, and clip mods")
	_expect(ItemDB.accepts("%s:laser_eyes" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("toxic").token()),
		"laser eyes mod slot accepts toxic")
	_expect(ItemDB.accepts("%s:wall" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("toxic").token()),
		"wall mod slot accepts toxic")
	_expect(not ItemDB.accepts("%s:lasso" % CrawlerCatalog.FILTER_MOD,
			CrawlerCatalog.make_modifier("toxic").token()),
		"lasso mod slot refuses toxic")


func _check_starter() -> void:
	_expect(_player.crawler_kit != null, "crawler player has a kit")
	_expect(_player.abilities.size() == 3, "crawler uses three ability slots")
	var card := _player.crawler_kit.equipped_card(0)
	_expect(card != null and card.id == "laser_eyes", "starter equips laser eyes")
	_expect(CrawlerRules.ability_enabled("starfire"),
		"starfire can be picked up in the first city")
	_expect(CrawlerRules.ability_enabled("meteor_punch"),
		"meteor punch is a crawler ability")
	_expect(CrawlerRules.ability_enabled("hero_punch"),
		"hero punch is a crawler ability")
	_expect(CrawlerRules.ability_enabled("overdrive"),
		"overdrive is a crawler ability")
	_expect(CrawlerRules.ability_enabled("nuke"),
		"nuke is a crawler ability")
	_expect(CrawlerRules.ability_enabled("mini_nuke"),
		"mini nuke is a crawler ability")
	_expect(CrawlerRules.ability_enabled("kame"),
		"kame is a crawler ability")
	_expect(CrawlerRules.ability_enabled("nausicaa"),
		"nausicaa is a crawler ability")
	_expect(CrawlerRules.ability_enabled("lightning"),
		"lightning is a crawler ability")
	_expect(CrawlerRules.ability_enabled("wall"),
		"wall is a crawler ability")
	_expect(CrawlerRules.ability_enabled("roar")
			and CrawlerRules.ability_enabled("toxic_blast")
			and CrawlerRules.ability_enabled("charming_aura")
			and CrawlerRules.ability_enabled("freeze_blast"),
		"the four roar abilities can be bought")
	_expect(card.slot_count == 3, "starter laser eyes has three slots")
	_expect(card.mod_at(0) == null, "starter laser eyes has no wobble seated")
	_expect(_player.crawler_kit.equipped_card(1) == null,
		"starter leaves the other hotbar slots empty")
	_expect(_player.crawler_kit.inventory_card(0) == null,
		"starter bag does not give a free mod")
	var stats := _player.crawler_kit.resolved_stats(0)
	_expect(is_equal_approx(float(stats.get("damage", 0.0)), CrawlerRules.LASER_DAMAGE),
		"starter laser eyes deal 50 per second")
	_expect(str(stats.get("damage_unit", "")) == "/s",
		"starter laser eyes list damage as a rate")
	_expect(is_equal_approx(float(stats.get("cooldown", 0.0)), CrawlerRules.LASER_COOLDOWN),
		"starter laser eyes wait half a second")
	_expect(is_equal_approx(float(stats.get("duration", 0.0)), CrawlerRules.LASER_DURATION),
		"starter laser eyes fire for 0.4 seconds")
	_expect(is_equal_approx(float(stats.get("range", 0.0)), CrawlerRules.LASER_RANGE),
		"starter laser eyes reach the authored range")
	_expect(is_equal_approx(float(stats.get("knockback", 0.0)),
			CrawlerRules.LASER_KNOCKBACK),
		"starter laser eyes have a knockback shove")
	_expect(CrawlerRules.upgrade_stats_for("laser_eyes").has("knockback"),
		"knockback is a laser eyes upgrade")
	_expect(CrawlerRules.upgrade_stats_for("laser_eyes").has("range"),
		"range is a laser eyes upgrade")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"the upgrade stall can raise beam range")
	_expect(float(_player.crawler_kit.resolved_stats(0).get("range", 0.0))
			> CrawlerRules.LASER_RANGE,
		"range upgrades lengthen the beam")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"the upgrade stall can raise beam knockback")
	_expect(float(_player.crawler_kit.resolved_stats(0).get("knockback", 0.0))
			> CrawlerRules.LASER_KNOCKBACK,
		"knockback upgrades shove farther")
	_expect(is_equal_approx(float(stats.get("wobble", 0.0)), 0.0),
		"starter laser eyes have no wobble")


func _check_spawn_arrival() -> void:
	_expect(String(CharacterRig.CLIP_ALIASES.get("Death_C", "")) == "Death_C",
		"Death_C is a named spawn clip")
	_expect(CharacterRig.has_clip(_player.animator, "Death_C"),
		"the crawler body has Death_C")
	var phase := CelestialCycle.solve_phase_for_elevation(
		Vector3.UP, Vector3.FORWARD, Vector3.FORWARD, 6.0, 1.0, true)
	var angle := phase * TAU
	var dusk := Vector3.FORWARD * cos(angle) + Vector3.RIGHT * sin(angle)
	var elev := rad_to_deg(asin(clampf(Vector3.FORWARD.dot(dusk), -1.0, 1.0)))
	_expect(absf(elev - 6.0) < 0.05, "dusk solver lands on 6 degrees")
	var next := Vector3.FORWARD * cos(angle + 0.02) + Vector3.RIGHT * sin(angle + 0.02)
	_expect(Vector3.FORWARD.dot(next) < Vector3.FORWARD.dot(dusk),
		"dusk solver picks the descending sun")
	_expect(GameWorld.CRAWLER_SPAWN_SUN_ELEVATION > -17.0
			and GameWorld.CRAWLER_SPAWN_SUN_ELEVATION <= 8.0,
		"crawler spawn sun sits in twilight")
	_player.defer_camera = true
	_player.visible = true
	_player.arm_spawn_arrival()
	_player.play_spawn_arrival()
	_expect(not _player.is_playing_spawn_arrival()
			and _player.get_node_or_null("CrawlerArrivalFlash") == null,
		"the blue orb waits until the player camera arrives")
	_player.take_camera()
	_expect(_player.is_playing_spawn_arrival(), "spawn holds reverse Death_C")
	_expect(_player.spawn_arrival_left() > 0.5, "the rise lasts about a clip")
	var flash := _player.get_node_or_null("CrawlerArrivalFlash")
	_expect(flash != null, "spawn throws a blue orb")
	if flash != null:
		_expect(flash.get_node_or_null("Core") != null
				and flash.get_node_or_null("Shell") != null,
			"the arrival flash is a glowing orb")
		if flash.has_method(&"tint"):
			var tint: Color = flash.call(&"tint")
			_expect(tint.b > tint.r and tint.b > 0.8,
				"the arrival flash is bright blue")
	_expect(not _player.can_attack(), "the rise locks attacks")
	_player.call(&"_tick_spawn_arrival", 30.0)
	if flash != null:
		flash.queue_free()


func _check_controller() -> void:
	var controller := _player.ability_controller()
	_expect(controller != null, "ability controller exists")
	var ability := controller.ability_in(0)
	_expect(ability != null and ability.ability_id == "laser_eyes",
		"controller built laser eyes from the token")
	_expect(not ability.has_modifier("wobble"), "starter laser eyes have no wobble")
	_expect(is_equal_approx(ability.stat("radius", 0.0), 0.45),
		"starter beam size stays the authored width")
	_expect(ability.stat("range", 0.0) > CrawlerRules.LASER_RANGE,
		"the live beam uses the upgraded range")
	_expect(ability._pulse_mode(), "crawler laser eyes fire in pulses")
	_expect(is_equal_approx(
			CrawlerRules.LASER_DAMAGE * LaserEyes.DAMAGE_STEP, 5.0),
		"each beam tick is a tenth of the per-second damage")
	_expect(ability.press(), "holding starts a pulse")
	ability.tick(0.05)
	_expect(ability.is_held() and ability._gap_left <= 0.0 and ability._left > 0.0,
		"the first pulse stays on and deals over its duration")
	ability.tick(0.40)
	_expect(ability.is_held() and ability._gap_left > 0.0,
		"the pulse ends and waits without dropping the hold")
	ability.tick(0.55)
	_expect(ability.is_held() and ability._left > 0.0,
		"holding through the cooldown starts the next pulse")
	ability.release()
	var big := CrawlerCatalog.make_modifier("big")
	_player.crawler_kit.register(big)
	_player.crawler_kit.inventory.set_item(0, big.token())
	var rack := _player.crawler_kit.mod_rack(0)
	_expect(rack != null, "equipped ability exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	ability = controller.ability_in(0)
	_expect(ability != null and ability.has_modifier("big"),
		"seating big rebuilds the ability with the new modifier")
	_expect(ability.stat("radius", 0.0) > 0.45, "big widens the resolved beam")


func _check_move_and_drop() -> void:
	var token := _player.abilities.get_item(0)
	_expect(not token.is_empty(), "equipped token is present before the move")
	_expect(_player.crawler_kit.unequip_to_bag(0), "unequip moves the ability into the bag")
	_expect(_player.abilities.get_item(0).is_empty(), "equip slot is empty after unequip")
	var bag_index := _player.crawler_kit.inventory.find(token)
	_expect(bag_index >= 0, "bag holds the moved ability")
	var payload := _player.crawler_kit.payload_at(CrawlerKit.SOURCE_BAG, bag_index)
	_expect(str(payload.get("id", "")) == "laser_eyes", "drop payload keeps laser eyes")
	_expect(_player.crawler_kit.move_card(
			CrawlerKit.SOURCE_BAG, bag_index, CrawlerKit.SOURCE_EQUIP, 0),
		"dropping laser eyes back onto the hotbar reseats it")
	_expect(_player.crawler_kit.equipped_card(0) != null
		and _player.crawler_kit.equipped_card(0).id == "laser_eyes",
		"reseated laser eyes is still laser eyes")
	token = _player.abilities.get_item(0)
	_expect(_player.crawler_kit.unequip_to_bag(0), "unequip again for extract")
	bag_index = _player.crawler_kit.inventory.find(token)
	var extracted := _player.crawler_kit.extract(
		CrawlerKit.SOURCE_BAG, bag_index, token)
	_expect(str(extracted.get("id", "")) == "laser_eyes", "extract removes the card")
	_expect(_player.crawler_kit.card_for_token(token) == null,
		"extracted card leaves the ledger")


func _check_pickup_swap() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var star := CrawlerCatalog.make_ability("starfire")
	var granted := _player.crawler_kit.grant(star.to_dict())
	_expect(bool(granted.get("ok", false)), "starfire pickup is accepted")
	_expect(_player.crawler_kit.equipped_card(1) != null
		and _player.crawler_kit.equipped_card(1).id == "starfire",
		"starfire seats on an empty hotbar slot")
	_expect(_player.crawler_kit.inventory_card(0) == null,
		"an ability pickup does not go into the mod bag")
	var extra := CrawlerCatalog.make_ability(
		"laser_eyes", CrawlerRules.LASER_SLOTS, CrawlerRules.laser_start_stats())
	_player.crawler_kit.grant(extra.to_dict())
	_expect(_player.crawler_kit.equipped_card(2) != null
		and _player.crawler_kit.equipped_card(2).id == "laser_eyes",
		"a third ability fills the last hotbar slot")
	var incoming := CrawlerCatalog.make_ability(
		"laser_eyes", CrawlerRules.LASER_SLOTS, CrawlerRules.laser_start_stats())
	var swap := _player.crawler_kit.grant(incoming.to_dict(), 0)
	_expect(bool(swap.get("ok", false)), "full kit still accepts a world pickup")
	_expect(swap.has("displaced"), "full hotbar swaps the selected slot")
	_expect(_player.crawler_kit.equipped_card(0) != null
		and _player.crawler_kit.equipped_card(0).uid == incoming.uid,
		"swap seated the incoming ability")
	_expect(_player.crawler_kit.equipped_card(1) != null
		and _player.crawler_kit.equipped_card(1).id == "starfire",
		"swap leaves the other hotbar abilities seated")


func _check_shop_full_swap() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(_player.crawler_kit.shop_grant("starfire"),
		"the stall fills the second hotbar slot")
	_expect(_player.crawler_kit.shop_grant("kame"),
		"the stall fills the last hotbar slot")
	var kept := _player.crawler_kit.equipped_card(0)
	var outgoing := _player.crawler_kit.equipped_card(1)
	_expect(kept != null and outgoing != null and outgoing.id == "starfire",
		"the bar is full before the extra buy")
	if kept == null or outgoing == null:
		return
	_player.select_ability(1)
	var result := _player.crawler_kit.shop_grant_result("hero_punch", 1)
	var displaced: Dictionary = result.get("displaced", {})
	_expect(bool(result.get("ok", false)) and not displaced.is_empty(),
		"a full-bar shop buy still grants the new ability")
	_expect(str(displaced.get("id", "")) == "starfire"
			and str(displaced.get("uid", "")) == outgoing.uid,
		"the selected equipped ability is the one that leaves")
	_expect(_player.crawler_kit.equipped_card(1) != null
			and _player.crawler_kit.equipped_card(1).id == "hero_punch",
		"the bought ability takes the selected slot")
	_expect(_player.crawler_kit.equipped_card(0) != null
			and _player.crawler_kit.equipped_card(0).uid == kept.uid,
		"the other hotbar abilities stay seated")
	_expect(_player.crawler_kit.card_for_token(outgoing.token()) == null
			and _player.crawler_kit.inventory.find(outgoing.token()) < 0,
		"the displaced ability is not kept in the bag")
	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	_player.global_position = Vector3.ZERO
	_player.crawler_progress.gold = 9999
	_player.crawler_progress.force_shop_offers(
		"city", "abilities", PackedStringArray(["hero_punch"]))
	var leaving := _player.crawler_kit.equipped_card(0)
	_player.select_ability(0)
	_expect(_player.in_crawler_city() and _player.buy_crawler_card("hero_punch"),
		"buying with a full bar still spends gold")
	_expect(_player.crawler_kit.equipped_card(0) != null
			and _player.crawler_kit.equipped_card(0).id == "hero_punch",
		"the store buy replaces the selected equipped ability")
	_expect(leaving == null
			or _player.crawler_kit.card_for_token(leaving.token()) == null,
		"the replaced ability leaves the kit so it can drop")
	ring.free()


func _check_starfire_upgrades() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var listed := CrawlerRules.upgrade_stats_for("starfire")
	_expect(listed == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"]),
		"starfire sells damage, cooldown, size, range, knockback, and slots")
	var granted := _player.crawler_kit.grant(CrawlerCatalog.make_ability("starfire").to_dict())
	_expect(bool(granted.get("ok", false)), "starfire can be granted for upgrades")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "starfire", "starfire is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)), CrawlerRules.STARFIRE_DAMAGE),
		"base starfire damage is the reduced burst")
	_expect(is_equal_approx(float(base.get("impact", 0.0)), CrawlerRules.STARFIRE_IMPACT)
			and float(base.get("radius", 0.0)) >= CrawlerRules.STARFIRE_RADIUS,
		"starfire still bursts in an area around the disk")
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)), CrawlerRules.STARFIRE_COOLDOWN),
		"base starfire cooldown is the long wait between disks")
	_expect(is_equal_approx(float(base.get("size", 0.0)), 1.0),
		"base starfire lists size as a multiplier")
	_expect(is_equal_approx(float(base.get("knockback", 0.0)),
			CrawlerRules.STARFIRE_KNOCKBACK),
		"base starfire knocks mobs back")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"starfire damage can be upgraded")
	var harder := _player.crawler_kit.stats_for(card)
	_expect(float(harder.get("damage", 0.0)) > CrawlerRules.STARFIRE_DAMAGE,
		"damage upgrades raise the disk hit")
	_expect(float(harder.get("impact", 0.0)) > CrawlerRules.STARFIRE_IMPACT,
		"damage upgrades also raise the burst")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"starfire cooldown can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
			< CrawlerRules.STARFIRE_COOLDOWN,
		"cooldown upgrades shorten the wait between disks")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"starfire size can be upgraded")
	var grown := _player.crawler_kit.stats_for(card)
	_expect(float(grown.get("projectile_radius", 0.0))
			> CrawlerRules.STARFIRE_PROJECTILE_RADIUS,
		"size upgrades grow the disk")
	_expect(float(grown.get("radius", 0.0)) > CrawlerRules.STARFIRE_RADIUS,
		"size upgrades grow the burst")
	_expect(float(grown.get("crater_radius", 0.0))
			> CrawlerRules.STARFIRE_CRATER_RADIUS,
		"size upgrades grow the crater")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"starfire range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.STARFIRE_RANGE,
		"range upgrades send disks farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"starfire slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.STARFIRE_SLOTS + 1,
		"slot upgrades add a modifier seat")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"starfire knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.STARFIRE_KNOCKBACK,
		"knockback upgrades throw farther")


func _check_light_bolt() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("light_bolt") == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "speed",
				"slots"]),
		"light bolt sells the usual combat stats plus particle speed")
	_expect(CrawlerProgress.ability_stock().has("light_bolt"),
		"the stall sells light bolt")
	_expect(CrawlerProgress.ability_price("light_bolt") == 38,
		"light bolt costs thirty-eight")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability("light_bolt").to_dict())
	_expect(bool(granted.get("ok", false)), "light bolt can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "light_bolt",
		"light bolt is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)),
			CrawlerRules.LIGHT_BOLT_DAMAGE)
			and is_equal_approx(float(base.get("cooldown", 0.0)),
				CrawlerRules.LIGHT_BOLT_COOLDOWN)
			and is_equal_approx(float(base.get("speed", 0.0)),
				CrawlerRules.LIGHT_BOLT_SPEED)
			and is_equal_approx(float(base.get("range", 0.0)),
				CrawlerRules.LIGHT_BOLT_RANGE),
		"base light bolt is a fast, short-cadence particle stream")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "speed"),
		"particle speed can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("speed", 0.0))
			> CrawlerRules.LIGHT_BOLT_SPEED,
		"speed upgrades make the bolts fly faster")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"light bolt damage can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("damage", 0.0))
			> CrawlerRules.LIGHT_BOLT_DAMAGE,
		"damage upgrades raise each bolt")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"light bolt range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.LIGHT_BOLT_RANGE,
		"range upgrades send bolts farther")
	_player.crawler_kit.shop_grant("reach")
	_player.crawler_kit.shop_grant("multi")
	var reach: CrawlerCard = null
	var multi: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "reach":
			reach = owned
		elif owned.id == "multi":
			multi = owned
	_player.crawler_kit.inventory.set_item(0, reach.token() if reach != null else "")
	_player.crawler_kit.inventory.set_item(1, multi.token() if multi != null else "")
	var rack := _player.crawler_kit.mod_rack(1)
	if reach != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	if multi != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	var paired := _player.crawler_kit.stats_for(card)
	_expect(CrawlerReach.far_cast(paired) >= CrawlerRules.REACH_FAR_CAST
			and float(paired.get("range", 0.0))
				> CrawlerRules.LIGHT_BOLT_RANGE + CrawlerRules.LIGHT_BOLT_RANGE_PER_RANK
			and CrawlerMulti.shots(paired) == 2,
		"reach and multi shot apply to light bolt")
	_expect(CrawlerCatalog.compatible("toxic", "light_bolt")
			and CrawlerCatalog.compatible("bubble", "light_bolt")
			and CrawlerCatalog.compatible("big", "light_bolt")
			and CrawlerCatalog.compatible("bounce", "light_bolt")
			and CrawlerCatalog.compatible("impact_cast", "light_bolt")
			and CrawlerCatalog.compatible("homing", "light_bolt")
			and not CrawlerCatalog.compatible("wobble", "light_bolt")
			and not CrawlerCatalog.compatible("clip", "light_bolt"),
		"projectile mods fit light bolt, beam and clip mods do not")
	_expect(CrawlerRules.upgrade_stat_title("speed", "light_bolt")
			== "Particle Speed",
		"light bolt names the particle speed upgrade")


func _check_icicle() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("icicle") == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "speed",
				"cold", "slots"]),
		"icicle sells particle stats plus cold")
	_expect(CrawlerProgress.ability_stock().has("icicle"),
		"the stall sells icicle")
	_expect(CrawlerProgress.ability_price("icicle") == 40,
		"icicle costs forty")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability("icicle").to_dict())
	_expect(bool(granted.get("ok", false)), "icicle can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "icicle",
		"icicle is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)),
			CrawlerRules.ICICLE_DAMAGE)
			and is_equal_approx(float(base.get("speed", 0.0)),
				CrawlerRules.ICICLE_SPEED)
			and is_equal_approx(float(base.get("cold", 0.0)),
				CrawlerRules.ICICLE_COLD)
			and is_equal_approx(float(base.get("cold_damage", 0.0)),
				CrawlerRules.ICICLE_COLD_DAMAGE)
			and is_equal_approx(float(base.get("radius", 0.0)),
				CrawlerRules.ICICLE_RADIUS),
		"base icicle is a thrown frost spear with a small cold burst")
	var payload := CrawlerElements.payload(_player, "icicle", base)
	var freeze_hold := 0.0
	var frost_dps := 0.0
	for entry: Dictionary in payload:
		if String(entry.get("id", "")) == String(CombatStatuses.FREEZE):
			freeze_hold = float(entry.get("duration", 0.0))
			frost_dps = float(entry.get("strength", 0.0))
	_expect(freeze_hold >= CrawlerRules.ICICLE_COLD
			and frost_dps >= CrawlerRules.ICICLE_COLD_DAMAGE,
		"icicle natively applies cold damage and freeze")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cold"),
		"cold can be upgraded")
	var colder := _player.crawler_kit.stats_for(card)
	_expect(float(colder.get("cold", 0.0)) > CrawlerRules.ICICLE_COLD
			and float(colder.get("cold_damage", 0.0))
				> CrawlerRules.ICICLE_COLD_DAMAGE
			and float(colder.get("radius", 0.0)) > CrawlerRules.ICICLE_RADIUS,
		"cold upgrades strengthen frost damage and the snow burst")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "speed"),
		"particle speed can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("speed", 0.0))
			> CrawlerRules.ICICLE_SPEED,
		"speed upgrades make the icicles fly faster")
	_player.crawler_kit.shop_grant("reach")
	_player.crawler_kit.shop_grant("ice")
	var reach: CrawlerCard = null
	var ice: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "reach":
			reach = owned
		elif owned.id == "ice":
			ice = owned
	_player.crawler_kit.inventory.set_item(0, reach.token() if reach != null else "")
	_player.crawler_kit.inventory.set_item(1, ice.token() if ice != null else "")
	var rack := _player.crawler_kit.mod_rack(1)
	if reach != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	if ice != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	var paired := _player.crawler_kit.stats_for(card)
	var iced := CrawlerElements.payload(_player, "icicle", paired)
	var iced_hold := 0.0
	for entry: Dictionary in iced:
		if String(entry.get("id", "")) == String(CombatStatuses.FREEZE):
			iced_hold = float(entry.get("duration", 0.0))
	_expect(CrawlerReach.far_cast(paired) >= CrawlerRules.REACH_FAR_CAST
			and float(paired.get("range", 0.0))
				> CrawlerRules.ICICLE_RANGE
			and iced_hold > float(colder.get("cold", 0.0)),
		"reach and ice apply to icicle")
	_expect(CrawlerCatalog.compatible("toxic", "icicle")
			and CrawlerCatalog.compatible("bubble", "icicle")
			and CrawlerCatalog.compatible("big", "icicle")
			and CrawlerCatalog.compatible("multi", "icicle")
			and not CrawlerCatalog.compatible("wobble", "icicle")
			and not CrawlerCatalog.compatible("clip", "icicle"),
		"projectile mods fit icicle, beam and clip mods do not")
	_expect(CrawlerRules.upgrade_stat_title("cold", "icicle") == "Cold"
			and CrawlerRules.upgrade_stat_title("speed", "icicle")
				== "Particle Speed",
		"icicle names the cold and particle speed upgrades")


func _check_teleport() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("teleport") == PackedStringArray(
			["cooldown", "size", "range", "speed", "swap", "slots"]),
		"teleport sells particle stats except damage, plus swap")
	_expect(CrawlerProgress.ability_stock().has("teleport"),
		"the stall sells teleport")
	_expect(CrawlerProgress.ability_price("teleport") == 42,
		"teleport costs forty-two")
	_expect(CrawlerRules.upgrade_max_rank("teleport", "swap") == 1,
		"swap is on or off")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability("teleport").to_dict())
	_expect(bool(granted.get("ok", false)), "teleport can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "teleport",
		"teleport is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 1.0)), 0.0)
			and is_equal_approx(float(base.get("speed", 0.0)),
				CrawlerRules.TELEPORT_SPEED)
			and is_equal_approx(float(base.get("range", 0.0)),
				CrawlerRules.TELEPORT_RANGE)
			and is_equal_approx(float(base.get("swap", 1.0)), 0.0),
		"base teleport is a no-damage arcing marker")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "speed"),
		"particle speed can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("speed", 0.0))
			> CrawlerRules.TELEPORT_SPEED,
		"speed upgrades make the marker fly faster")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "swap"),
		"swap can be turned on")
	_expect(is_equal_approx(
			float(_player.crawler_kit.stats_for(card).get("swap", 0.0)), 1.0),
		"swap seats as on")
	_expect(not _player.crawler_kit.upgrade_card(card.uid, "swap"),
		"swap stops at on")
	_expect(CrawlerCatalog.compatible("reach", "teleport")
			and CrawlerCatalog.compatible("multi", "teleport")
			and CrawlerCatalog.compatible("bubble", "teleport")
			and CrawlerCatalog.compatible("big", "teleport")
			and not CrawlerCatalog.compatible("wobble", "teleport")
			and not CrawlerCatalog.compatible("clip", "teleport"),
		"projectile mods fit teleport, beam and clip mods do not")
	_expect(CrawlerRules.upgrade_stat_title("speed", "teleport")
			== "Particle Speed"
			and CrawlerRules.upgrade_stat_title("swap", "teleport") == "Swap",
		"teleport names particle speed and swap")
	_expect(_player.warp_to(
			_player.global_position + _player.global_basis.z * -2.0,
			-_player.global_basis.z),
		"teleport can warp the caster")


func _check_fus() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("fus") == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "speed",
				"slots"]),
		"fus sells particle combat stats")
	_expect(CrawlerProgress.ability_stock().has("fus"),
		"the stall sells fus")
	_expect(CrawlerProgress.ability_price("fus") == 36,
		"fus costs thirty-six")
	_expect(CrawlerRules.is_particle_ability("fus")
			and not CrawlerRules.is_roar_ability("fus")
			and not CrawlerRules.is_field_ability("fus"),
		"fus is a particle shout, not a shockwave or field")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability("fus").to_dict())
	_expect(bool(granted.get("ok", false)), "fus can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "fus",
		"fus is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)), CrawlerRules.FUS_DAMAGE)
			and is_equal_approx(float(base.get("knockback", 0.0)),
				CrawlerRules.FUS_KNOCKBACK)
			and is_equal_approx(float(base.get("speed", 0.0)),
				CrawlerRules.FUS_SPEED)
			and is_equal_approx(float(base.get("range", 0.0)),
				CrawlerRules.FUS_RANGE)
			and float(base.get("knockback", 0.0))
				> CrawlerRules.ROAR_KNOCKBACK
			and float(base.get("damage", 0.0))
				< CrawlerRules.ROAR_DAMAGE,
		"base fus chips lightly and shoves hard")
	_expect(not base.has("cast"),
		"fus has no field cast time")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"fus knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.FUS_KNOCKBACK,
		"knockback upgrades throw farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "speed"),
		"particle speed can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("speed", 0.0))
			> CrawlerRules.FUS_SPEED,
		"speed upgrades make the cone fly faster")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"fus damage can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("damage", 0.0))
			> CrawlerRules.FUS_DAMAGE,
		"damage upgrades raise the chip")
	_player.crawler_kit.shop_grant("reach")
	_player.crawler_kit.shop_grant("multi")
	var reach: CrawlerCard = null
	var multi: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "reach":
			reach = owned
		elif owned.id == "multi":
			multi = owned
	_player.crawler_kit.inventory.set_item(0, reach.token() if reach != null else "")
	_player.crawler_kit.inventory.set_item(1, multi.token() if multi != null else "")
	var rack := _player.crawler_kit.mod_rack(1)
	if reach != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	if multi != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	var paired := _player.crawler_kit.stats_for(card)
	_expect(CrawlerReach.far_cast(paired) >= CrawlerRules.REACH_FAR_CAST
			and float(paired.get("range", 0.0))
				> CrawlerRules.FUS_RANGE
			and CrawlerMulti.shots(paired) == 2,
		"reach and multi shot apply to fus")
	_expect(CrawlerCatalog.compatible("toxic", "fus")
			and CrawlerCatalog.compatible("shock", "fus")
			and CrawlerCatalog.compatible("charm", "fus")
			and CrawlerCatalog.compatible("ice", "fus")
			and CrawlerCatalog.compatible("bubble", "fus")
			and CrawlerCatalog.compatible("big", "fus")
			and CrawlerCatalog.compatible("reach", "fus")
			and CrawlerCatalog.compatible("multi", "fus")
			and not CrawlerCatalog.compatible("wobble", "fus")
			and not CrawlerCatalog.compatible("clip", "fus")
			and not CrawlerCatalog.compatible("endless", "fus"),
		"projectile mods fit fus, beam and clip mods do not")
	_expect(CrawlerRules.upgrade_stat_title("speed", "fus")
			== "Particle Speed",
		"fus names the particle speed upgrade")
	var definition := ItemDB.ability_definition("fus")
	_expect(definition != null and String(definition.animation) == "Roar"
			and definition.projectile_type
				== AbilityDefinition.ProjectileType.ENERGY_CONE
			and definition.impact_type
				== AbilityDefinition.ImpactType.KNOCKBACK_BURST,
		"fus authors a roar-posed energy cone")
	var ability := Fus.new()
	ability.configure(_player, 1, "fus", definition)
	ability.apply_crawler(card)
	_expect(ability.press(), "fus starts from the hotbar")
	_expect(_player.roar_playing(), "fus plays the roar pose")
	ability.tick(CrawlerRules.ROAR_WINDUP + 0.05)
	var cone: AbilityProjectile = null
	for child: Node in get_children():
		if child is AbilityProjectile \
				and (child as AbilityProjectile).definition != null \
				and (child as AbilityProjectile).definition.ability_id == "fus":
			cone = child as AbilityProjectile
	_expect(cone != null and is_instance_valid(cone._shock)
			and cone._shock.visible,
		"fus launches a visible meteor-shock cone")
	if cone != null:
		cone.queue_free()
	ability.release()
	var victim := CrawlerRanger.new()
	var from := _player.mouth_point()
	var along := _player.aim_direction(from)
	victim.configure("fus_hit",
		Transform3D(Basis(), from + along * 6.0), 1, true)
	add_child(victim)
	victim.set_physics_process(false)
	var before := victim.health()
	var burst := AbilityProjectile.launch(
		self, _player, "fus", from, along, true, Vector3.ZERO, paired)
	_expect(burst != null, "fus can launch a force cone")
	if burst != null:
		for _step in 12:
			burst._physics_process(0.08)
			if not is_instance_valid(burst):
				break
		if is_instance_valid(burst):
			burst.queue_free()
	_expect(victim.health() < before
			and (before - victim.health()) < CrawlerRules.ROAR_DAMAGE
			and victim.velocity.length() > CrawlerRules.ROAR_KNOCKBACK,
		"the fus cone chips lightly and knocks hard")
	victim.queue_free()


func _check_meteor_punch_upgrades() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var listed := CrawlerRules.upgrade_stats_for("meteor_punch")
	_expect(listed == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"]),
		"meteor punch sells damage, cooldown, size, range, knockback, and slots")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability(
			"meteor_punch", CrawlerRules.METEOR_SLOTS,
			CrawlerRules.meteor_start_stats()).to_dict())
	_expect(bool(granted.get("ok", false)), "meteor punch can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "meteor_punch",
		"meteor punch is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)), CrawlerRules.METEOR_DAMAGE),
		"base meteor punch damage is the crawler fist")
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)),
			CrawlerRules.METEOR_COOLDOWN),
		"base meteor punch waits after the landing")
	_expect(is_equal_approx(float(base.get("range", 0.0)), CrawlerRules.METEOR_RANGE),
		"base meteor punch uses the crawler reach")
	_expect(is_equal_approx(float(base.get("knockback", 0.0)),
			CrawlerRules.METEOR_KNOCKBACK),
		"base meteor punch knocks mobs back")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"meteor punch damage can be upgraded")
	var harder := _player.crawler_kit.stats_for(card)
	_expect(float(harder.get("damage", 0.0)) > CrawlerRules.METEOR_DAMAGE,
		"damage upgrades raise the flying fist")
	_expect(float(harder.get("impact", 0.0)) > CrawlerRules.METEOR_IMPACT,
		"damage upgrades also raise the landing")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"meteor punch cooldown can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
			< CrawlerRules.METEOR_COOLDOWN,
		"cooldown upgrades shorten the wait after landing")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"meteor punch size can be upgraded")
	var grown := _player.crawler_kit.stats_for(card)
	_expect(float(grown.get("radius", 0.0)) > CrawlerRules.METEOR_RADIUS,
		"size upgrades thicken the fist")
	_expect(float(grown.get("crater_radius", 0.0))
			> CrawlerRules.METEOR_CRATER_RADIUS,
		"size upgrades grow the crater")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"meteor punch range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.METEOR_RANGE,
		"range upgrades carry the punch farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"meteor punch knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.METEOR_KNOCKBACK,
		"knockback upgrades throw farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"meteor punch slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.METEOR_SLOTS + 1,
		"slot upgrades add a modifier seat")
	var ranger := CrawlerRanger.new()
	ranger.configure("meteor_kb", Transform3D.IDENTITY, 1, true)
	add_child(ranger)
	ranger.set_physics_process(false)
	var shove := DamageHit.impact(ranger.global_position, 1.2, 12.0)
	shove.faction = DamageHit.Faction.PLAYER
	shove.world_impulse = Vector3(CrawlerRules.METEOR_KNOCKBACK, 0.0, 0.0)
	ranger.apply_damage(shove)
	_expect(ranger.velocity.x > 10.0, "meteor knockback throws a crawler mob")
	ranger.queue_free()


func _check_hero_punch() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var listed := CrawlerRules.upgrade_stats_for("hero_punch")
	_expect(listed == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"]),
		"hero punch sells damage, cooldown, size, range, knockback, and slots")
	_expect(CrawlerProgress.ability_stock().has("hero_punch")
			and CrawlerProgress.ability_price("hero_punch") == 32,
		"the ability stall sells hero punch")
	_expect(_player.crawler_kit.shop_grant("hero_punch"),
		"the stall can grant hero punch")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "hero_punch",
		"hero punch is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)),
			CrawlerRules.HERO_PUNCH_DAMAGE),
		"base hero punch damage is the crawler jab")
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)),
			CrawlerRules.HERO_PUNCH_COOLDOWN),
		"base hero punch waits between jabs")
	_expect(is_equal_approx(float(base.get("range", 0.0)),
			CrawlerRules.HERO_PUNCH_RANGE),
		"base hero punch uses the crawler reach")
	_expect(is_equal_approx(float(base.get("radius", 0.0)),
			CrawlerRules.HERO_PUNCH_RADIUS),
		"base hero punch uses the crawler fist")
	_expect(is_equal_approx(float(base.get("knockback", 0.0)),
			CrawlerRules.HERO_PUNCH_KNOCKBACK),
		"base hero punch knocks mobs back")
	_expect(is_equal_approx(float(base.get("size", 0.0)), 1.0),
		"base hero punch lists size as a multiplier")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"hero punch damage can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("damage", 0.0))
			> CrawlerRules.HERO_PUNCH_DAMAGE,
		"damage upgrades raise the jab")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"hero punch cooldown can be upgraded")
	var cooled := float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
	_expect(cooled < CrawlerRules.HERO_PUNCH_COOLDOWN
			and cooled >= CrawlerRules.HERO_PUNCH_COOLDOWN_MIN,
		"cooldown upgrades shorten the wait between jabs")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"hero punch size can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("radius", 0.0))
			> CrawlerRules.HERO_PUNCH_RADIUS,
		"size upgrades thicken the fist")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"hero punch range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.HERO_PUNCH_RANGE,
		"range upgrades reach farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"hero punch knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.HERO_PUNCH_KNOCKBACK,
		"knockback upgrades throw farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"hero punch slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.HERO_PUNCH_SLOTS + 1,
		"slot upgrades add a modifier seat")
	var before := _player.crawler_kit.stats_for(card)
	var big := CrawlerCatalog.make_modifier("big")
	_player.crawler_kit.register(big)
	_player.crawler_kit.inventory.set_item(0, big.token())
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "hero punch exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var live := _player.crawler_kit.stats_for(card)
	_expect(card.filled_modifier_ids().has("big"), "big seats on hero punch")
	_expect(float(live.get("size", 0.0)) > float(before.get("size", 1.0)),
		"big raises hero punch's size stat")
	_expect(float(live.get("radius", 0.0)) > float(before.get("radius", 0.0)),
		"big thickens the hero punch fist")


func _check_overdrive() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	var listed := CrawlerRules.upgrade_stats_for("overdrive")
	_expect(listed == PackedStringArray(
			["boost", "duration", "cooldown", "slots"]),
		"overdrive sells boost, duration, cooldown, and slots")
	_expect(CrawlerRules.upgrade_stat_title("boost", "overdrive") == "Boost",
		"overdrive boost is labeled Boost")
	_expect(CrawlerRules.upgrade_stat_title("duration", "overdrive")
			== "Overdrive time",
		"overdrive duration is the buff time")
	_expect(CrawlerProgress.ability_stock().has("overdrive")
			and CrawlerProgress.ability_price("overdrive") == 36,
		"the ability stall sells overdrive")
	_expect(_player.crawler_kit.shop_grant("overdrive"),
		"the stall can grant overdrive")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "overdrive",
		"overdrive is seated for upgrades")
	if card == null:
		return
	_expect(card.slot_count == CrawlerRules.OVERDRIVE_SLOTS,
		"overdrive starts with one modifier seat")
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("boost", 0.0)),
			CrawlerRules.OVERDRIVE_BOOST),
		"base overdrive uses the authored boost")
	_expect(is_equal_approx(float(base.get("duration", 0.0)),
			CrawlerRules.OVERDRIVE_DURATION),
		"base overdrive lasts the authored time")
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)),
			CrawlerRules.OVERDRIVE_COOLDOWN),
		"base overdrive waits the authored cooldown")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "boost"),
		"overdrive boost can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("boost", 0.0))
			> CrawlerRules.OVERDRIVE_BOOST,
		"boost upgrades raise the jump")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "duration"),
		"overdrive duration can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("duration", 0.0))
			> CrawlerRules.OVERDRIVE_DURATION,
		"duration upgrades last longer")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"overdrive cooldown can be upgraded")
	var cooled := float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
	_expect(cooled < CrawlerRules.OVERDRIVE_COOLDOWN
			and cooled >= CrawlerRules.OVERDRIVE_COOLDOWN_MIN,
		"cooldown upgrades shorten the wait")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"overdrive slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.OVERDRIVE_SLOTS + 1,
		"slot upgrades add a modifier seat")
	var laser := _player.crawler_kit.equipped_card(0)
	_expect(laser != null and laser.id == "laser_eyes",
		"starter laser eyes stay seated beside overdrive")
	if laser == null:
		return
	var laser_before := _player.crawler_kit.stats_for(laser)
	var overlay := _player.crawler_kit.stats_for(card)
	_player.begin_overdrive(overlay, card)
	_expect(_player.overdrive_active(), "overdrive starts a timed buff")
	_expect(_player.overdrive_boost_mul() > 1.0, "overdrive multiplies combat stats")
	var grown := _player.overdrive_size_scale()
	_expect(grown > 1.0, "overdrive grows the body")
	_expect(is_equal_approx(_player.character.scale.x, grown),
		"the character mesh matches the overdrive scale")
	var laser_live := _player.crawler_kit.stats_for(laser)
	_expect(float(laser_live.get("damage", 0.0))
			> float(laser_before.get("damage", 0.0)),
		"overdrive boosts laser damage")
	_expect(float(laser_live.get("radius", 0.0))
			> float(laser_before.get("radius", 0.0)),
		"overdrive boosts laser size")
	_player.end_overdrive()
	_expect(not _player.overdrive_active(), "ending overdrive clears the buff")
	_expect(is_equal_approx(_player.overdrive_size_scale(), 1.0)
			and is_equal_approx(_player.character.scale.x, 1.0),
		"the body shrinks when overdrive ends")
	var big := CrawlerCatalog.make_modifier("big")
	_player.crawler_kit.register(big)
	_player.crawler_kit.inventory.set_item(0, big.token())
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "overdrive exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	_expect(card.filled_modifier_ids().has("big"), "big seats on overdrive")
	var wobble := CrawlerCatalog.make_modifier("wobble")
	_player.crawler_kit.register(wobble)
	_player.crawler_kit.inventory.set_item(0, wobble.token())
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 1)
	_expect(card.filled_modifier_ids().has("wobble"), "wobble seats on overdrive")
	_player.begin_overdrive(_player.crawler_kit.stats_for(card), card)
	var with_big := _player.overdrive_size_scale()
	_expect(with_big > grown, "big on overdrive grows the body further")
	var boosted_laser := _player.crawler_kit.stats_for(laser)
	_expect(float(boosted_laser.get("radius", 0.0))
			> float(laser_before.get("radius", 0.0)) * 1.2,
		"borrowed big thickens laser eyes while overdrive is on")
	_expect(float(boosted_laser.get("wobble", 0.0)) > 0.0,
		"borrowed wobble flags laser eyes while overdrive is on")
	var meteor := CrawlerCatalog.make_ability("meteor_punch")
	_player.crawler_kit.register(meteor)
	_player.crawler_kit.inventory.set_item(1, meteor.token())
	_expect(float(_player.crawler_kit.stats_for(meteor).get("wobble", 0.0)) <= 0.0,
		"borrowed wobble does not flag meteor punch")
	_expect(float(_player.crawler_kit.stats_for(meteor).get("damage", 0.0))
			> CrawlerRules.METEOR_DAMAGE,
		"overdrive still boosts meteor punch")
	_player._tick_overdrive(0.05)
	_expect(_player.overdrive_active(), "overdrive stays up before its timer")
	_player._tick_overdrive(999.0)
	_expect(not _player.overdrive_active()
			and is_equal_approx(_player.character.scale.x, 1.0),
		"overdrive expires and shrinks the body")


func _check_roar_upgrades() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("roar") == PackedStringArray(
			["damage", "range", "knockback", "slots"]),
		"roar sells damage, range, knockback, and slots")
	_expect(not CrawlerRules.upgrade_stats_for("roar").has("duration"),
		"roar has no effect-duration upgrade")
	_expect(CrawlerRules.upgrade_stats_for("toxic_blast")
			== PackedStringArray(
				["damage", "range", "duration", "knockback", "slots"]),
		"toxic blast sells the shared shockwave stats")
	_expect(CrawlerRules.upgrade_stat_title("duration", "toxic_blast")
			== "Effect duration",
		"roar-family duration is the effect, not firing time")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability("roar").to_dict())
	_expect(bool(granted.get("ok", false)), "roar can be granted")
	var roar := _player.crawler_kit.equipped_card(1)
	_expect(roar != null and roar.id == "roar", "roar is seated for upgrades")
	if roar == null:
		return
	var base := _player.crawler_kit.stats_for(roar)
	_expect(is_equal_approx(float(base.get("damage", 0.0)), CrawlerRules.ROAR_DAMAGE),
		"base roar chips the shockwave")
	_expect(is_equal_approx(float(base.get("range", 0.0)), CrawlerRules.ROAR_RADIUS),
		"base roar uses the shared radius")
	_expect(is_equal_approx(float(base.get("knockback", 0.0)),
			CrawlerRules.ROAR_KNOCKBACK),
		"base roar knocks enemies back")
	_expect(not base.has("duration"), "roar itself has no effect duration")
	_expect(_player.crawler_kit.upgrade_card(roar.uid, "damage"),
		"roar damage can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(roar).get("damage", 0.0))
			> CrawlerRules.ROAR_DAMAGE,
		"roar damage upgrades hit harder")
	_expect(_player.crawler_kit.upgrade_card(roar.uid, "range"),
		"roar range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(roar).get("range", 0.0))
			> CrawlerRules.ROAR_RADIUS,
		"roar range upgrades widen the wave")
	_expect(_player.crawler_kit.upgrade_card(roar.uid, "knockback"),
		"roar knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(roar).get("knockback", 0.0))
			> CrawlerRules.ROAR_KNOCKBACK,
		"roar knockback upgrades shove farther")
	_expect(_player.crawler_kit.shop_grant("toxic_blast"),
		"the stall sells toxic blast")
	var toxic := _player.crawler_kit.equipped_card(2)
	_expect(toxic != null and toxic.id == "toxic_blast",
		"toxic blast seats on the last hotbar slot")
	if toxic != null:
		var toxin := _player.crawler_kit.stats_for(toxic)
		_expect(is_equal_approx(float(toxin.get("damage", -1.0)),
				CrawlerRules.ROAR_TOXIC_DAMAGE),
			"toxic blast starts as a poison tick")
		_expect(is_equal_approx(float(toxin.get("knockback", -1.0)), 0.0),
			"toxic blast starts with no knockback")
		_expect(_player.crawler_kit.upgrade_card(toxic.uid, "duration"),
			"toxic duration can be upgraded")
		_expect(float(_player.crawler_kit.stats_for(toxic).get("duration", 0.0))
				> CrawlerRules.ROAR_DURATION,
			"duration upgrades lengthen the poison")
	_expect(is_equal_approx(
			CrawlerRules.roar_base_damage("freeze_blast"), 0.0),
		"freeze blast starts with no burst damage")
	_expect(is_equal_approx(_player.crawler_element_scale(), 1.0),
		"elemental starts at 1x")
	_player.crawler_progress.ranks[CrawlerProgress.STAT_ELEMENTAL] = 1
	_expect(_player.crawler_element_scale() > 1.0,
		"an elemental rank raises poison and frost")
	_player.crawler_progress.ranks[CrawlerProgress.STAT_ELEMENTAL] = 0
	var definition := ItemDB.ability_definition("roar")
	_expect(definition != null and String(definition.animation) == "Roar",
		"the four shockwaves share the Roar clip")
	var ability := CrawlerRoar.new()
	ability.configure(_player, 1, "roar", definition)
	ability.apply_crawler(roar)
	var victim := CrawlerRanger.new()
	victim.configure("roar_hit", Transform3D(Basis(), Vector3(4.0, 0.0, 0.0)), 1, true)
	add_child(victim)
	victim.set_physics_process(false)
	var before := victim.health()
	_expect(ability.press(), "roar starts from the hotbar")
	_expect(_player.roar_playing(), "roar plays the scrunch-and-yell pose")
	ability.tick(CrawlerRules.ROAR_WINDUP + 0.05)
	_expect(victim.health() < before or victim.velocity.length() > 0.0,
		"the roar shockwave hits a nearby mob")
	ability.tick(CrawlerRules.ROAR_EXPAND)
	victim.queue_free()


func _check_starfire_big() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.crawler_kit.grant(CrawlerCatalog.make_ability("starfire").to_dict())
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "starfire", "starfire is seated for big")
	if card == null:
		return
	var before := _player.crawler_kit.stats_for(card)
	var big := CrawlerCatalog.make_modifier("big")
	_player.crawler_kit.register(big)
	_player.crawler_kit.inventory.set_item(0, big.token())
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "starfire exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var live := _player.crawler_kit.stats_for(card)
	_expect(float(live.get("size", 0.0)) > float(before.get("size", 1.0)),
		"big raises starfire's size stat")
	_expect(is_equal_approx(float(live.get("size", 0.0)), CrawlerRules.big_size_scale(0)),
		"big's starfire size is the burst scale")
	_expect(float(live.get("radius", 0.0)) > float(before.get("radius", 0.0)),
		"big widens the starfire burst")
	_expect(float(live.get("projectile_radius", 0.0))
			> float(before.get("projectile_radius", 0.0)),
		"big grows the starfire disk")
	_expect(_player.crawler_kit.host_ability_for(big.token()) == card,
		"the kit knows starfire is hosting big")
	_expect(CrawlerCatalog.description_of("big", card.id).contains(
			CrawlerRules.format_mul(CrawlerRules.big_size_scale(0))),
		"big's description on starfire states the starting size boost")


func _check_big_ranks() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.crawler_kit.grant(CrawlerCatalog.make_ability("starfire").to_dict())
	var star := _player.crawler_kit.equipped_card(1)
	_expect(star != null, "starfire is seated for big ranks")
	if star == null:
		return
	var big := CrawlerCatalog.make_modifier("big")
	_player.crawler_kit.register(big)
	_player.crawler_kit.inventory.set_item(0, big.token())
	ItemContainer.transfer(
		_player.crawler_kit.inventory, 0, _player.crawler_kit.mod_rack(1), 0)
	var rank0 := float(_player.crawler_kit.stats_for(star).get("size", 0.0))
	_expect(is_equal_approx(rank0, CrawlerRules.big_size_scale(0)),
		"unupgraded big starts at the small size step")
	_expect(_player.crawler_kit.upgrade_card(big.uid, "size"),
		"big size can be upgraded")
	var rank1 := float(_player.crawler_kit.stats_for(star).get("size", 0.0))
	_expect(is_equal_approx(rank1, CrawlerRules.big_size_scale(1)),
		"the first big upgrade raises host size")
	_expect(rank1 > rank0 * 1.15, "early big ranks already jump")
	_expect(CrawlerProgress.upgrade_price(0, "big")
			> CrawlerProgress.upgrade_price(0),
		"big upgrades cost more than a regular store rank")
	_expect(CrawlerProgress.upgrade_price(9, "big")
			> CrawlerProgress.upgrade_price(4, "big") * 3,
		"late big upgrades get much more expensive")
	for _step in 9:
		_expect(_player.crawler_kit.upgrade_card(big.uid, "size"),
			"big can be upgraded through level 10")
	var maxed := float(_player.crawler_kit.stats_for(star).get("size", 0.0))
	_expect(is_equal_approx(maxed, CrawlerRules.big_size_scale(10)),
		"level 10 big is the authored max scale")
	_expect(maxed > 10.0, "a maxed big is more than ten times the host size")
	_expect(not _player.crawler_kit.upgrade_card(big.uid, "size"),
		"big size stops at level 10")
	var copy := CrawlerCatalog.description_of("big", "starfire", 10)
	_expect(copy.contains(CrawlerRules.format_mul(CrawlerRules.big_size_scale(10))),
		"maxed big describes the huge host scale")
	var ranks := {"size": big.upgrade_rank("size")}
	var lines := CrawlerRules.mod_progress_lines("big", big.shop_rank(), ranks)
	_expect("LEVEL  //  10 / 10" in lines and "SIZE  //  10 / 10" in lines,
		"big copy lists level and size upgrades")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null, "laser eyes is still seated")
	if eyes == null:
		return
	ItemContainer.transfer(
		_player.crawler_kit.mod_rack(1), 0, _player.crawler_kit.inventory, 0)
	ItemContainer.transfer(
		_player.crawler_kit.inventory, 0, _player.crawler_kit.mod_rack(0), 0)
	var laser := _player.crawler_kit.stats_for(eyes)
	_expect(is_equal_approx(float(laser.get("size", 0.0)),
			CrawlerRules.big_size_scale(10)),
		"maxed big raises the laser eyes size stat")


func _check_bubble() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("bubble") == PackedStringArray(
			["damage", "size", "duration", "homing", "pop", "speed",
				"spreader"]),
		"bubble sells damage, size, linger, homing, pop, particle speed, and spreader")
	_expect(CrawlerRules.upgrade_stat_title("speed", "bubble") == "Particle Speed",
		"bubble names the particle speed upgrade")
	_expect(CrawlerRules.upgrade_stat_title("duration", "bubble") == "Lingering time",
		"bubble duration is lingering time")
	_expect(CrawlerRules.upgrade_max_rank("bubble", "spreader") == 1,
		"spreader is on or off")
	_expect(CrawlerProgress.shop_stock().has("bubble"), "the stall sells bubble")
	_expect(_player.crawler_kit.shop_grant("bubble"), "the stall can grant bubble")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for bubble")
	if eyes == null:
		return
	var first: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "bubble":
			first = card
			break
	_expect(first != null, "the granted card is bubble")
	if first == null:
		return
	var second := CrawlerCatalog.make_modifier("bubble")
	_player.crawler_kit.register(second)
	_expect(first != null and second != null and first.uid != second.uid,
		"two bubble cards are in the kit")
	if second == null:
		return
	_expect(_player.crawler_kit.upgrade_card(first.uid, "homing"),
		"one bubble can buy homing")
	_expect(first.upgrade_rank("homing") == 1, "homing rank is stored on that card")
	_expect(second.upgrade_rank("homing") == 0, "the other bubble stays without homing")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "damage"),
		"bubble damage can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "size"),
		"bubble size can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "duration"),
		"bubble linger can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "pop"),
		"bubble pop can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "speed"),
		"bubble particle speed can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "spreader"),
		"bubble spreader can be turned on")
	_expect(not _player.crawler_kit.upgrade_card(first.uid, "spreader"),
		"spreader stops at on")
	_player.crawler_kit.inventory.set_item(0, first.token())
	_player.crawler_kit.inventory.set_item(1, second.token())
	var rack := _player.crawler_kit.mod_rack(0)
	_expect(rack != null, "laser eyes exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	_expect(eyes.filled_modifier_ids() == PackedStringArray(["bubble", "bubble"]),
		"both bubble cards seat on laser eyes")
	var recipes := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	_expect(recipes.size() == 2, "each seated bubble card is its own stream")
	if recipes.size() < 2:
		return
	_expect(float(recipes[0].get("homing", 0.0)) > 0.0
			and is_equal_approx(float(recipes[1].get("homing", 0.0)), 0.0),
		"only the upgraded bubble card homes")
	_expect(float(recipes[0].get("damage", 0.0))
			> float(recipes[1].get("damage", 0.0)),
		"damage upgrades stay on that card's bubbles")
	_expect(float(recipes[0].get("size", 0.0))
			> float(recipes[1].get("size", 0.0)),
		"size upgrades stay on that card's bubbles")
	_expect(float(recipes[0].get("linger", 0.0))
			> float(recipes[1].get("linger", 0.0)),
		"linger upgrades stay on that card's bubbles")
	_expect(float(recipes[0].get("pop", 0.0)) > 0.0
			and is_equal_approx(float(recipes[1].get("pop", 0.0)), 0.0),
		"pop upgrades stay on that card's bubbles")
	_expect(float(recipes[0].get("speed", 0.0))
			> float(recipes[1].get("speed", 0.0)),
		"particle speed upgrades stay on that card's bubbles")
	_expect(bool(recipes[0].get("spreader", false))
			and not bool(recipes[1].get("spreader", false)),
		"spreader stays on that card's bubbles")
	var big := CrawlerCatalog.make_modifier("big")
	_player.crawler_kit.register(big)
	_player.crawler_kit.inventory.set_item(2, big.token())
	ItemContainer.transfer(_player.crawler_kit.inventory, 2, rack, 2)
	var grown := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	_expect(grown.size() == 2, "big does not replace the bubble cards")
	_expect(float(grown[0].get("size", 0.0)) > float(recipes[0].get("size", 0.0)),
		"big enlarges the bubbles with the host")
	_expect(CrawlerCatalog.description_of("bubble", "laser_eyes").contains("along"),
		"seated bubble names the beam trail, not only the impact")
	var beam_from := Vector3(0.0, 2.0, 0.0)
	var beam_at := Vector3(0.0, 2.0, 20.0)
	var beam_path := PackedVector3Array([beam_from, beam_at])
	var along := CrawlerBubbles.emit_beam(
		_player, "laser_eyes", beam_from, beam_from, beam_at, 0.0, 4, beam_path)
	_expect(along.size() >= CrawlerRules.BUBBLE_BEAM_ALONG_MIN * recipes.size(),
		"a beam leaves several bubbles along its path")
	_expect(_bubbles_peel_from_beam(beam_from, beam_at, along),
		"beam bubbles peel outward along the path, not only at the impact")
	for orb: CrawlerBubble in along:
		if is_instance_valid(orb):
			orb.queue_free()
	var bolt := PackedVector3Array([
		Vector3(0.0, 2.0, 0.0),
		Vector3(3.0, 3.5, 7.0),
		Vector3(-2.0, 1.5, 13.0),
		Vector3(1.0, 2.0, 20.0),
	])
	var hops := CrawlerBubbles.emit_beam(
		_player, "laser_eyes", bolt[0], bolt[0], bolt[bolt.size() - 1], 0.0, 1,
		bolt)
	_expect(_bubbles_follow_polyline(bolt, hops),
		"a bolt leaves bubbles along its hops, not the straight impact line")
	for orb: CrawlerBubble in hops:
		if is_instance_valid(orb):
			orb.queue_free()
	_player.crawler_kit.shop_grant("toxic_blast")
	var toxic := _player.crawler_kit.equipped_card(1)
	_expect(toxic != null and toxic.id == "toxic_blast",
		"toxic blast seats for spreader")
	if toxic == null:
		return
	var toxic_rack := _player.crawler_kit.mod_rack(1)
	ItemContainer.transfer(rack, 0, toxic_rack, 0)
	var carried := CrawlerBubbles.recipes_for_player(_player, "toxic_blast")
	_expect(carried.size() == 1, "one bubble card moved onto toxic blast")
	if not carried.is_empty():
		_expect(str(carried[0].get("status_id", "")) == String(CombatStatuses.POISON),
			"spreader on toxic blast loads poison onto those bubbles")
	var definition := ItemDB.ability_definition("roar")
	_player.crawler_kit.shop_grant("roar")
	var roar := _player.crawler_kit.equipped_card(2)
	_expect(roar != null and roar.id == "roar", "roar seats for shockwave bubbles")
	if roar == null or definition == null:
		return
	ItemContainer.transfer(rack, 1, _player.crawler_kit.mod_rack(2), 0)
	var ability := CrawlerRoar.new()
	ability.configure(_player, 2, "roar", definition)
	ability.apply_crawler(roar)
	_expect(ability.press(), "roar starts with a bubble card seated")
	ability.tick(CrawlerRules.ROAR_WINDUP + 0.05)
	var floating := 0
	for node: Node in get_tree().get_nodes_in_group(CrawlerBubble.GROUP):
		floating += 1
	_expect(floating > 0, "a roar with bubble leaves floating orbs")
	ability.tick(CrawlerRules.ROAR_EXPAND)
	for node: Node in get_tree().get_nodes_in_group(CrawlerBubble.GROUP):
		if node is CrawlerBubble:
			(node as CrawlerBubble).queue_free()
	var wave_at := Vector3(2.0, 8.0, -1.0)
	var wave := CrawlerBubbles.emit_shockwave(_player, "roar", wave_at, 10.0)
	_expect(wave.size() >= CrawlerRules.BUBBLE_SHOCKWAVE_COUNT,
		"a roar shockwave leaves a full bubble bloom")
	_expect(_bubbles_surround(wave_at, wave),
		"shockwave bubbles bloom around the wave, not in a line")
	for orb: CrawlerBubble in wave:
		if is_instance_valid(orb):
			orb.queue_free()


func _check_linger() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("linger") == PackedStringArray(
			["duration", "toxic", "freeze", "slow"]),
		"linger sells linger time, toxic, freeze, and slow")
	_expect(CrawlerRules.upgrade_stat_title("duration", "linger") == "Linger time",
		"linger duration is linger time")
	_expect(CrawlerProgress.shop_stock().has("linger"), "the stall sells linger")
	_expect(_player.crawler_kit.shop_grant("linger"), "the stall can grant linger")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for linger")
	if eyes == null:
		return
	var card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "linger":
			card = owned
			break
	_expect(card != null, "the granted card is linger")
	if card == null:
		return
	_expect(_player.crawler_kit.upgrade_card(card.uid, "duration"),
		"linger time can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slow"),
		"linger slow can be upgraded")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "toxic"),
		"linger toxic can be upgraded")
	_player.crawler_kit.inventory.set_item(0, card.token())
	var rack := _player.crawler_kit.mod_rack(0)
	_expect(rack != null, "laser eyes exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	_expect(eyes.filled_modifier_ids().has("linger"), "linger seats on laser eyes")
	var recipes := CrawlerLingers.recipes_for_player(_player, "laser_eyes")
	_expect(recipes.size() == 1, "a seated linger card is its own cloud recipe")
	if recipes.is_empty():
		return
	_expect(float(recipes[0].get("duration", 0.0)) > CrawlerRules.LINGER_SECONDS,
		"linger time upgrades stay on that card's clouds")
	_expect(float(recipes[0].get("slow", 0.0)) > 0.0,
		"slow upgrades stay on that card's clouds")
	var loaded: Array = recipes[0].get("statuses", [])
	var has_poison := false
	for entry: Variant in loaded:
		if entry is Dictionary \
				and str(entry.get("id", "")) == String(CombatStatuses.POISON):
			has_poison = true
	_expect(has_poison, "linger toxic loads poison onto those clouds")
	var clouds := CrawlerLingers.emit_beam_trail(
		_player, "laser_eyes", Vector3(2.0, 3.0, 0.0), Vector3(8.0, 3.0, 0.0))
	_expect(not clouds.is_empty(), "linger leaves a smoking trail along the beam")
	if not clouds.is_empty():
		var wash := CrawlerLingerCloud.wash_at(self, clouds[0].global_position)
		_expect(wash.a > 0.02, "standing in a linger cloud tints the view")
		_expect(CrawlerLingerCloud.speed_scale_at(self, clouds[0].global_position)
				< 0.95,
			"a slow linger cloud cuts speed inside")
	for cloud: CrawlerLingerCloud in clouds:
		cloud.queue_free()
	_player.crawler_kit.shop_grant("bubble")
	var bubble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bubble":
			bubble = owned
			break
	_expect(bubble != null, "bubble can sit beside linger")
	if bubble == null:
		return
	_player.crawler_kit.inventory.set_item(1, bubble.token())
	ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	var with_linger := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	ItemContainer.transfer(rack, 0, _player.crawler_kit.inventory, 0)
	var without := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	_expect(not with_linger.is_empty() and not without.is_empty()
			and float(with_linger[0].get("linger", 0.0))
				> float(without[0].get("linger", 0.0)),
		"linger on the same ability lengthens bubble linger")


func _check_elemental_mods() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	_expect(CrawlerRules.upgrade_stats_for("toxic") == PackedStringArray(
			["toxic", "duration"]),
		"toxic sells poison strength and hold")
	_expect(CrawlerRules.upgrade_stats_for("shock") == PackedStringArray(["shock"])
			and CrawlerRules.upgrade_stats_for("charm") == PackedStringArray(["charm"])
			and CrawlerRules.upgrade_stats_for("ice") == PackedStringArray(["freeze"]),
		"shock, charm, and ice each sell one rank")
	_expect(CrawlerRules.upgrade_max_rank("toxic", "toxic") == CrawlerRules.ELEM_MAX_RANK,
		"elemental mods stop at rank eight")
	_expect(CrawlerProgress.shop_stock().has("toxic")
			and CrawlerProgress.shop_stock().has("shock")
			and CrawlerProgress.shop_stock().has("charm")
			and CrawlerProgress.shop_stock().has("ice"),
		"the stall sells the elemental mods")
	_expect(CrawlerProgress.card_price("toxic") == 22, "toxic costs twenty-two")
	_expect(_player.crawler_kit.shop_grant("toxic"), "the stall can grant toxic")
	var first: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "toxic":
			first = card
			break
	_expect(first != null, "the granted card is toxic")
	if first == null:
		return
	_expect(_player.crawler_kit.upgrade_card(first.uid, "toxic"),
		"toxic strength can be upgraded")
	_expect(first.upgrade_rank("toxic") == 1, "toxic rank is stored on that card")
	var second := CrawlerCatalog.make_modifier("toxic")
	_player.crawler_kit.register(second)
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for toxic")
	if eyes == null:
		return
	_player.crawler_kit.inventory.set_item(0, first.token())
	_player.crawler_kit.inventory.set_item(1, second.token())
	var rack := _player.crawler_kit.mod_rack(0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var one := CrawlerElements.payload(
		_player, "laser_eyes", _player.crawler_kit.stats_for(eyes))
	_expect(not one.is_empty()
			and str(one[0].get("id", "")) == String(CombatStatuses.POISON),
		"one toxic card poisons laser eyes")
	var one_dps := float(one[0].get("strength", 0.0)) if not one.is_empty() else 0.0
	ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	var two := CrawlerElements.payload(
		_player, "laser_eyes", _player.crawler_kit.stats_for(eyes))
	_expect(not two.is_empty()
			and float(two[0].get("strength", 0.0)) > one_dps * 1.4,
		"two toxic cards add together")
	_player.crawler_progress.ranks[CrawlerProgress.STAT_ELEMENTAL] = 1
	var scaled := CrawlerElements.payload(
		_player, "laser_eyes", _player.crawler_kit.stats_for(eyes))
	_expect(not scaled.is_empty()
			and is_equal_approx(float(scaled[0].get("strength", 0.0)),
				float(two[0].get("strength", 0.0)) * 1.14),
		"elemental rank scales seated toxic")
	_player.crawler_progress.ranks[CrawlerProgress.STAT_ELEMENTAL] = 0
	_player.crawler_kit.shop_grant("toxic_field")
	var field := _player.crawler_kit.equipped_card(1)
	_expect(field != null and field.id == "toxic_field",
		"toxic field seats beside laser eyes")
	if field != null:
		var native := CrawlerElements.payload(
			_player, "toxic_field", _player.crawler_kit.stats_for(field))
		ItemContainer.transfer(rack, 0, _player.crawler_kit.mod_rack(1), 0)
		var doubled := CrawlerElements.payload(
			_player, "toxic_field", _player.crawler_kit.stats_for(field))
		_expect(not native.is_empty() and not doubled.is_empty()
				and float(doubled[0].get("strength", 0.0))
					> float(native[0].get("strength", 0.0)),
			"toxic on toxic field is stronger than the field alone")
	_player.crawler_kit.shop_grant("wall")
	var wall := _player.crawler_kit.equipped_card(2)
	_expect(wall != null and wall.id == "wall", "wall seats for toxic")
	if wall != null:
		var leftover := CrawlerCatalog.make_modifier("toxic")
		_player.crawler_kit.register(leftover)
		_player.crawler_kit.inventory.set_item(2, leftover.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(2), 0)
		var cold := CrawlerElements.payload(
			_player, "wall", _player.crawler_kit.stats_for(wall))
		_expect(cold.is_empty(), "toxic on wall does nothing without firewall")
		_expect(_player.crawler_kit.upgrade_card(wall.uid, "firewall"),
			"wall firewall can be upgraded")
		var hot := CrawlerElements.payload(
			_player, "wall", _player.crawler_kit.stats_for(wall))
		_expect(not hot.is_empty()
				and str(hot[0].get("id", "")) == String(CombatStatuses.POISON),
			"toxic on a burning wall applies poison")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.crawler_kit.shop_grant("bubble")
	var bubble: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "bubble":
			bubble = card
			break
	var toxin := CrawlerCatalog.make_modifier("toxic")
	_player.crawler_kit.register(toxin)
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.inventory.set_item(0, bubble.token() if bubble != null else "")
	_player.crawler_kit.inventory.set_item(1, toxin.token())
	rack = _player.crawler_kit.mod_rack(0)
	if bubble != null:
		ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	var recipes := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	_expect(not recipes.is_empty()
			and str(recipes[0].get("status_id", "")) == String(CombatStatuses.POISON)
			and not bool(recipes[0].get("spreader", false)),
		"toxic on laser eyes poisons bubbles without spreader")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("overdrive")
	var drive := _player.crawler_kit.equipped_card(1)
	_expect(drive != null and drive.id == "overdrive",
		"overdrive seats for a borrowed toxic")
	if drive != null:
		var borrowed := CrawlerCatalog.make_modifier("toxic")
		_player.crawler_kit.register(borrowed)
		_player.crawler_kit.inventory.set_item(2, borrowed.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(1), 0)
		_player.begin_overdrive(_player.crawler_kit.stats_for(drive), drive)
		var loaned := CrawlerElements.payload(
			_player, "laser_eyes", _player.crawler_kit.stats_for(eyes))
		_expect(_player.overdrive_active() and not loaned.is_empty()
				and str(loaned[0].get("id", "")) == String(CombatStatuses.POISON),
			"overdrive lends toxic onto laser eyes")
		_player.end_overdrive()


func _check_multi_shot() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	_expect(CrawlerRules.upgrade_stats_for("multi") == PackedStringArray(["multi"]),
		"multi shot sells a split rank")
	_expect(CrawlerRules.multi_shots(0) == 2
			and CrawlerRules.multi_shots(1) == 3
			and CrawlerRules.multi_shots(2) == 4
			and CrawlerRules.multi_shots(3) == 5,
		"multi shot starts at 2 and upgrades to 5")
	_expect(CrawlerRules.upgrade_max_rank("multi", "multi")
			== CrawlerRules.MULTI_MAX_RANK,
		"multi shot stops at five splits")
	var two := CrawlerMulti.yaw_degrees(2)
	_expect(two.size() == 2
			and is_equal_approx(two[0], -45.0)
			and is_equal_approx(two[1], 45.0),
		"two beams point out at 45 degrees")
	var three := CrawlerMulti.yaw_degrees(3)
	_expect(three.size() == 3
			and is_equal_approx(three[0], -45.0)
			and is_equal_approx(three[1], 0.0)
			and is_equal_approx(three[2], 45.0),
		"three beams keep one straight ahead")
	var five := CrawlerMulti.yaw_degrees(5)
	_expect(five.size() == 5
			and is_equal_approx(five[0], -45.0)
			and is_equal_approx(five[2], 0.0)
			and is_equal_approx(five[4], 45.0),
		"five beams stay inside the 45 degree fan")
	var walls := CrawlerMulti.wall_offsets(4, 8.0)
	_expect(walls.size() == 4 and is_equal_approx(walls[0], 0.0),
		"walls always keep one centered")
	var punches := CrawlerMulti.punch_offsets(3)
	_expect(punches.size() == 3
			and is_equal_approx(punches[0], 0.0)
			and punches[2] > punches[1]
			and punches[1] > 0.0,
		"physical extras stack in front of the first hit")
	_expect(CrawlerProgress.shop_stock().has("multi"),
		"the stall sells multi shot")
	_expect(CrawlerProgress.card_price("multi") == 22, "multi shot costs twenty-two")
	_expect(_player.crawler_kit.shop_grant("multi"), "the stall can grant multi shot")
	var card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "multi":
			card = owned
			break
	_expect(card != null, "the granted card is multi shot")
	if card == null:
		return
	_expect(_player.crawler_kit.upgrade_card(card.uid, "multi"),
		"multi shot can be upgraded")
	_expect(card.upgrade_rank("multi") == 1, "multi shot rank is stored on that card")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for multi shot")
	if eyes == null:
		return
	_player.crawler_kit.inventory.set_item(0, card.token())
	var rack := _player.crawler_kit.mod_rack(0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var stats := _player.crawler_kit.stats_for(eyes)
	_expect(CrawlerMulti.shots(stats) == 3, "one upgraded card splits laser eyes 3 ways")
	_expect(CrawlerCatalog.description_of("multi", "laser_eyes").contains("45"),
		"laser eyes copy mentions the 45 degree fan")
	_expect(CrawlerCatalog.description_of("multi", "starfire").contains("fans"),
		"projectile copy mentions the fork")
	_expect(CrawlerCatalog.description_of("multi", "wall").contains("centered"),
		"wall copy mentions the centered barrier")
	_expect(CrawlerCatalog.description_of("multi", "roar").contains("second"),
		"shockwave copy mentions the delayed recast")
	_expect(CrawlerCatalog.description_of("multi", "static_field").contains("second"),
		"field copy mentions the delayed recast")
	_expect(CrawlerCatalog.description_of("multi", "meteor_punch").contains("meteor"),
		"meteor copy mentions stacked shocks")
	_expect(CrawlerCatalog.description_of("multi", "lasso").contains("does not fit"),
		"lasso refuses multi shot")
	_player.crawler_kit.shop_grant("wobble")
	var wobble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "wobble":
			wobble = owned
			break
	if wobble != null:
		_player.crawler_kit.inventory.set_item(1, wobble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
		var paired := _player.crawler_kit.stats_for(eyes)
		_expect(CrawlerMulti.shots(paired) == 3
				and float(paired.get("wobble", 0.0)) > 0.0,
			"multi shot pairs with wobble on laser eyes")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("overdrive")
	var drive := _player.crawler_kit.equipped_card(1)
	_expect(drive != null and drive.id == "overdrive",
		"overdrive seats for a borrowed multi shot")
	if drive != null:
		var borrowed := CrawlerCatalog.make_modifier("multi")
		_player.crawler_kit.register(borrowed)
		_player.crawler_kit.inventory.set_item(2, borrowed.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(1), 0)
		_player.begin_overdrive(_player.crawler_kit.stats_for(drive), drive)
		var loaned := _player.crawler_kit.stats_for(eyes)
		_expect(_player.overdrive_active() and CrawlerMulti.shots(loaned) == 2,
			"overdrive lends multi shot onto laser eyes")
		_player.end_overdrive()


func _check_reach() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	_expect(CrawlerRules.upgrade_stats_for("reach")
			== PackedStringArray(["range", "far_cast"]),
		"reach sells range and far cast")
	_expect(is_equal_approx(CrawlerRules.reach_range_mul(0),
			CrawlerRules.REACH_RANGE_MUL)
			and is_equal_approx(CrawlerRules.reach_range_mul(1),
				CrawlerRules.REACH_RANGE_MUL + CrawlerRules.REACH_RANGE_PER_RANK)
			and is_equal_approx(
				CrawlerRules.reach_range_mul(CrawlerRules.REACH_MAX_RANK),
				CrawlerRules.REACH_RANGE_MUL
					+ CrawlerRules.REACH_RANGE_PER_RANK
					* float(CrawlerRules.REACH_MAX_RANK)),
		"reach range starts at 1.28x and grows each rank")
	_expect(is_equal_approx(CrawlerRules.far_cast_meters(0),
			CrawlerRules.REACH_FAR_CAST)
			and CrawlerRules.far_cast_meters(1)
				> CrawlerRules.REACH_FAR_CAST,
		"far cast starts at two meters")
	_expect(CrawlerRules.upgrade_max_rank("reach", "range")
			== CrawlerRules.REACH_MAX_RANK
			and CrawlerRules.upgrade_max_rank("reach", "far_cast")
			== CrawlerRules.REACH_MAX_RANK,
		"reach upgrades stop at the authored cap")
	var flagged := CrawlerCatalog.resolve_stats(
		"laser_eyes", PackedStringArray(["reach"]), {"range": 60.0})
	_expect(float(flagged.get("reach", 0.0)) == 1.0
			and is_equal_approx(float(flagged.get("far_cast", 0.0)),
				CrawlerRules.REACH_FAR_CAST),
		"reach flags beams and sets a two meter far cast")
	_expect(not CrawlerCatalog.resolve_stats(
			"roar", PackedStringArray(["reach"]), {}).has("far_cast"),
		"reach does not flag shockwaves")
	_expect(CrawlerProgress.shop_stock().has("reach"), "the stall sells reach")
	_expect(CrawlerProgress.card_price("reach") == 22, "reach costs twenty-two")
	_expect(_player.crawler_kit.shop_grant("reach"), "the stall can grant reach")
	var card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "reach":
			card = owned
			break
	_expect(card != null, "the granted card is reach")
	if card == null:
		return
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"reach range can be upgraded")
	_expect(card.upgrade_rank("range") == 1, "reach range rank is stored")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "far_cast"),
		"far cast can be upgraded")
	_expect(card.upgrade_rank("far_cast") == 1, "far cast rank is stored")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for reach")
	if eyes == null:
		return
	_player.crawler_kit.inventory.set_item(0, card.token())
	var rack := _player.crawler_kit.mod_rack(0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var stats := _player.crawler_kit.stats_for(eyes)
	var wanted_mul := CrawlerRules.reach_range_mul(1)
	_expect(is_equal_approx(float(stats.get("range", 0.0)),
			CrawlerRules.LASER_RANGE * wanted_mul),
		"one upgraded reach card lengthens laser eyes")
	_expect(is_equal_approx(float(stats.get("far_cast", 0.0)),
			CrawlerRules.far_cast_meters(1)),
		"one upgraded far cast sits in front of the eyes")
	_expect(CrawlerCatalog.description_of("reach", "laser_eyes").contains("farther"),
		"beam copy mentions the extra range")
	_expect(CrawlerCatalog.description_of("reach", "starfire").contains("hand"),
		"projectile copy mentions the throw")
	_expect(CrawlerCatalog.description_of("reach", "roar").contains("does not fit"),
		"shockwave copy refuses reach")
	_expect(CrawlerCatalog.description_of("reach", "wall").contains("does not fit"),
		"wall copy refuses reach")
	_expect(CrawlerCatalog.description_of("reach", "lasso").contains("does not fit"),
		"lasso refuses reach")
	_player.crawler_kit.shop_grant("wobble")
	_player.crawler_kit.shop_grant("multi")
	var wobble: CrawlerCard = null
	var multi: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "wobble":
			wobble = owned
		elif owned.id == "multi":
			multi = owned
	if wobble != null:
		_player.crawler_kit.inventory.set_item(1, wobble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	if multi != null:
		_player.crawler_kit.inventory.set_item(2, multi.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 2, rack, 2)
	var paired := _player.crawler_kit.stats_for(eyes)
	_expect(is_equal_approx(float(paired.get("range", 0.0)),
			CrawlerRules.LASER_RANGE * wanted_mul)
			and is_equal_approx(float(paired.get("far_cast", 0.0)),
				CrawlerRules.far_cast_meters(1))
			and float(paired.get("wobble", 0.0)) > 0.0
			and CrawlerMulti.shots(paired) == 2,
		"reach pairs with wobble and multi shot on laser eyes")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("overdrive")
	var drive := _player.crawler_kit.equipped_card(1)
	_expect(drive != null and drive.id == "overdrive",
		"overdrive seats for a borrowed reach")
	if drive != null:
		var borrowed := CrawlerCatalog.make_modifier("reach")
		_player.crawler_kit.register(borrowed)
		_player.crawler_kit.inventory.set_item(2, borrowed.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(1), 0)
		_player.begin_overdrive(_player.crawler_kit.stats_for(drive), drive)
		var loaned := _player.crawler_kit.stats_for(eyes)
		var boosted := CrawlerRules.LASER_RANGE * CrawlerRules.REACH_RANGE_MUL \
			* _player.overdrive_boost_mul()
		_expect(_player.overdrive_active()
				and is_equal_approx(float(loaned.get("range", 0.0)), boosted)
				and is_equal_approx(float(loaned.get("far_cast", 0.0)),
					CrawlerRules.REACH_FAR_CAST),
			"overdrive lends reach onto laser eyes")
		_player.end_overdrive()


func _check_bounce() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	_expect(CrawlerRules.upgrade_stats_for("bounce") == PackedStringArray(["bounce"]),
		"bounce sells a bounce rank")
	_expect(CrawlerRules.bounce_count(0) == 1
			and CrawlerRules.bounce_count(1) == 2
			and CrawlerRules.bounce_count(2) == 3
			and CrawlerRules.bounce_count(3) == 4
			and CrawlerRules.bounce_count(4) == 5,
		"bounce starts at 1 and upgrades to 5")
	_expect(CrawlerRules.upgrade_max_rank("bounce", "bounce")
			== CrawlerRules.BOUNCE_MAX_RANK,
		"bounce stops at five ricochets")
	_expect(CrawlerRules.upgrade_stat_title("bounce", "bounce") == "Bounces",
		"bounce names the bounce upgrade")
	var outgoing := CrawlerBounce.reflect(Vector3(0.0, -1.0, 0.0), Vector3.UP)
	_expect(outgoing.y > 0.0, "a downward shot reflects up off a floor")
	var nuke_def := ItemDB.ability_definition("nuke")
	var teleport_def := ItemDB.ability_definition("teleport")
	var star_def := ItemDB.ability_definition("starfire")
	_expect(CrawlerBounce.explodes_on_bounce(nuke_def)
			and CrawlerBounce.explodes_on_bounce(star_def)
			and not CrawlerBounce.explodes_on_bounce(teleport_def),
		"explosive shots burst on bounce, teleport waits for the last land")
	var flagged := CrawlerCatalog.resolve_stats(
		"laser_eyes", PackedStringArray(["bounce"]), {})
	_expect(float(flagged.get("bounce", 0.0)) == 1.0
			and CrawlerBounce.count(flagged) == 1,
		"bounce flags beams with one ricochet")
	_expect(not CrawlerCatalog.resolve_stats(
			"roar", PackedStringArray(["bounce"]), {}).has("bounce"),
		"bounce does not flag shockwaves")
	_expect(CrawlerProgress.shop_stock().has("bounce"), "the stall sells bounce")
	_expect(CrawlerProgress.card_price("bounce") == 22, "bounce costs twenty-two")
	_expect(_player.crawler_kit.shop_grant("bounce"), "the stall can grant bounce")
	var card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bounce":
			card = owned
			break
	_expect(card != null, "the granted card is bounce")
	if card == null:
		return
	_expect(_player.crawler_kit.upgrade_card(card.uid, "bounce"),
		"bounce can be upgraded")
	_expect(card.upgrade_rank("bounce") == 1, "bounce rank is stored on that card")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for bounce")
	if eyes == null:
		return
	_player.crawler_kit.inventory.set_item(0, card.token())
	var rack := _player.crawler_kit.mod_rack(0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var stats := _player.crawler_kit.stats_for(eyes)
	_expect(CrawlerBounce.count(stats) == 2,
		"one upgraded bounce card gives laser eyes two ricochets")
	_expect(CrawlerCatalog.description_of("bounce", "laser_eyes").contains("ricochet"),
		"beam copy mentions the ricochet")
	_expect(CrawlerCatalog.description_of("bounce", "starfire").contains("bounce"),
		"projectile copy mentions the bounce")
	_expect(CrawlerCatalog.description_of("bounce", "roar").contains("does not fit"),
		"shockwave copy refuses bounce")
	_expect(CrawlerCatalog.description_of("bounce", "wall").contains("does not fit"),
		"wall copy refuses bounce")
	_expect(CrawlerCatalog.description_of("bounce", "lasso").contains("does not fit"),
		"lasso refuses bounce")
	_player.crawler_kit.shop_grant("bubble")
	_player.crawler_kit.shop_grant("wobble")
	var bubble: CrawlerCard = null
	var wobble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bubble":
			bubble = owned
		elif owned.id == "wobble":
			wobble = owned
	if wobble != null:
		_player.crawler_kit.inventory.set_item(1, wobble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	if bubble != null:
		_player.crawler_kit.inventory.set_item(2, bubble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 2, rack, 2)
	var paired := _player.crawler_kit.stats_for(eyes)
	_expect(CrawlerBounce.count(paired) == 2
			and float(paired.get("wobble", 0.0)) > 0.0
			and float(paired.get("bubble", 0.0)) > 0.0,
		"bounce pairs with wobble and bubble on laser eyes")
	var recipes := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	_expect(not recipes.is_empty()
			and CrawlerBounce.count(recipes[0]) == 2,
		"bubble recipes inherit the host bounce count")
	var shot := AbilityProjectile.new()
	shot.definition = star_def
	shot.stats = {"bounce": 2.0, "speed": 20.0}
	shot._along = Vector3(0.0, -1.0, 0.0)
	shot._velocity = Vector3(0.0, -20.0, 0.0)
	shot._speed = 20.0
	shot._bounces_left = 2
	shot.authoritative = false
	_expect(shot.bounce_off(Vector3.UP)
			and shot._velocity.y > 0.0
			and shot._bounces_left == 1,
		"a seated bounce reflects a projectile and keeps a bounce left")
	shot.free()
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("overdrive")
	var drive := _player.crawler_kit.equipped_card(1)
	_expect(drive != null and drive.id == "overdrive",
		"overdrive seats for a borrowed bounce")
	if drive != null:
		var borrowed := CrawlerCatalog.make_modifier("bounce")
		_player.crawler_kit.register(borrowed)
		_player.crawler_kit.inventory.set_item(2, borrowed.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(1), 0)
		_player.begin_overdrive(_player.crawler_kit.stats_for(drive), drive)
		var loaned := _player.crawler_kit.stats_for(eyes)
		_expect(_player.overdrive_active() and CrawlerBounce.count(loaned) == 1,
			"overdrive lends bounce onto laser eyes")
		_player.end_overdrive()


func _check_impact_cast() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	_expect(CrawlerRules.upgrade_stats_for("impact_cast").is_empty()
			and CrawlerRules.display_stats_for("impact_cast").is_empty(),
		"impact cast has no store ranks")
	_expect(CrawlerImpactCast.enabled({"impact_cast": 1.0})
			and not CrawlerImpactCast.enabled({})
			and not CrawlerImpactCast.enabled(
				{"impact_cast": 1.0, "_impact_echo": 1.0}),
		"impact cast is a host flag and echoes cannot retrigger it")
	_expect(CrawlerImpactCast.can_echo("mini_nuke")
			and CrawlerImpactCast.can_echo("meteor_punch")
			and CrawlerImpactCast.can_echo("laser_eyes")
			and CrawlerImpactCast.can_echo("hero_punch")
			and not CrawlerImpactCast.can_echo("teleport")
			and not CrawlerImpactCast.can_echo("overdrive")
			and not CrawlerImpactCast.can_echo("grapple")
			and not CrawlerImpactCast.can_echo("lasso")
			and not CrawlerImpactCast.can_echo("wall"),
		"impact cast copies combat abilities and skips movement tools")
	var along := CrawlerImpactCast.random_along(Vector3.UP)
	_expect(along.is_normalized() and along.dot(Vector3.UP) > 0.0,
		"impact copies leave along the hit hemisphere")
	var flagged := CrawlerCatalog.resolve_stats(
		"starfire", PackedStringArray(["impact_cast"]), {})
	_expect(CrawlerImpactCast.enabled(flagged),
		"impact cast flags projectiles")
	_expect(not CrawlerCatalog.resolve_stats(
			"roar", PackedStringArray(["impact_cast"]), {}).has("impact_cast"),
		"impact cast does not flag shockwaves")
	_expect(CrawlerProgress.shop_stock().has("impact_cast"),
		"the stall sells impact cast")
	_expect(CrawlerProgress.card_price("impact_cast") == 22,
		"impact cast costs twenty-two")
	_expect(_player.crawler_kit.shop_grant("impact_cast"),
		"the stall can grant impact cast")
	var card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "impact_cast":
			card = owned
			break
	_expect(card != null, "the granted card is impact cast")
	if card == null:
		return
	_expect(not _player.crawler_kit.upgrade_card(card.uid, "impact_cast")
			and not _player.crawler_kit.upgrade_card(card.uid),
		"impact cast cannot be upgraded")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for impact cast")
	if eyes == null:
		return
	_player.crawler_kit.inventory.set_item(0, card.token())
	var rack := _player.crawler_kit.mod_rack(0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var stats := _player.crawler_kit.stats_for(eyes)
	_expect(CrawlerImpactCast.enabled(stats),
		"seating impact cast flags laser eyes")
	_expect(_player.crawler_kit.shop_grant("wobble"),
		"the stall can grant wobble")
	var wobble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "wobble":
			wobble = owned
			break
	_expect(wobble != null, "the granted card is wobble")
	if wobble != null:
		var bag_index := _player.crawler_kit.inventory.find(wobble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, bag_index, rack, 1)
	var paired := _player.crawler_kit.stats_for(eyes)
	_expect(CrawlerImpactCast.enabled(paired)
			and float(paired.get("wobble", 0.0)) > 0.0,
		"impact cast pairs with wobble on laser eyes")
	_expect(_player.crawler_kit.shop_grant("mini_nuke"),
		"mini nuke seats beside the host")
	var nuke := _player.crawler_kit.equipped_card(1)
	_expect(nuke != null and nuke.id == "mini_nuke",
		"mini nuke is the other equipped ability")
	if nuke == null:
		return
	var ammo_before := _player.crawler_kit.ammo_left(nuke)
	var listed := CrawlerImpactCast.guests(_player, "laser_eyes")
	_expect(listed.has("mini_nuke") and not listed.has("laser_eyes"),
		"impact cast copies the other equipped ability")
	var echo := CrawlerImpactCast.echo_overlay(_player, "mini_nuke")
	_expect(float(echo.get("impact_cast", 1.0)) <= 0.0
			and CrawlerImpactCast.is_echo(echo)
			and not CrawlerImpactCast.enabled(echo),
		"copied stats strip impact cast so the echo cannot nest")
	_expect(_player.crawler_kit.ammo_left(nuke) == ammo_before,
		"listing a copy does not spend the guest magazine")
	_expect(CrawlerCatalog.description_of("impact_cast", "laser_eyes").contains("other equipped"),
		"beam copy mentions the other abilities")
	_expect(CrawlerCatalog.description_of("impact_cast", "starfire").contains("impact"),
		"projectile copy mentions the impact")
	_expect(CrawlerCatalog.description_of("impact_cast", "roar").contains("does not fit"),
		"shockwave copy refuses impact cast")
	_expect(CrawlerCatalog.description_of("impact_cast", "wall").contains("does not fit"),
		"wall copy refuses impact cast")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("overdrive")
	var drive := _player.crawler_kit.equipped_card(1)
	_expect(drive != null and drive.id == "overdrive",
		"overdrive seats for a borrowed impact cast")
	if drive != null:
		var borrowed := CrawlerCatalog.make_modifier("impact_cast")
		_player.crawler_kit.register(borrowed)
		_player.crawler_kit.inventory.set_item(2, borrowed.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(1), 0)
		_player.begin_overdrive(_player.crawler_kit.stats_for(drive), drive)
		var loaned := _player.crawler_kit.stats_for(eyes)
		_expect(_player.overdrive_active() and CrawlerImpactCast.enabled(loaned),
			"overdrive lends impact cast onto laser eyes")
		_player.end_overdrive()


func _check_homing() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.end_overdrive()
	_expect(CrawlerRules.upgrade_stats_for("homing")
			== PackedStringArray(["homing", "range"]),
		"homing sells intensity and seek range")
	_expect(CrawlerRules.display_stats_for("homing")
			== PackedStringArray(["homing", "range"]),
		"homing shows intensity and seek range")
	_expect(is_equal_approx(CrawlerRules.homing_steer(0),
			CrawlerRules.HOMING_STEER_BASE)
			and is_equal_approx(CrawlerRules.homing_steer(1),
				CrawlerRules.HOMING_STEER_BASE
				+ CrawlerRules.HOMING_STEER_PER_RANK)
			and is_equal_approx(CrawlerRules.homing_range(0),
				CrawlerRules.HOMING_RANGE_BASE)
			and is_equal_approx(CrawlerRules.homing_range(1),
				CrawlerRules.HOMING_RANGE_BASE
				+ CrawlerRules.HOMING_RANGE_PER_RANK),
		"homing starts at 4.5 pull / 8 m and upgrades both")
	_expect(CrawlerRules.upgrade_max_rank("homing", "homing")
			== CrawlerRules.HOMING_MAX_RANK
			and CrawlerRules.upgrade_max_rank("homing", "range")
				== CrawlerRules.HOMING_MAX_RANK,
		"homing stops at six ranks")
	_expect(CrawlerRules.upgrade_stat_title("homing", "homing") == "Intensity"
			and CrawlerRules.upgrade_stat_title("range", "homing")
				== "Seek Range",
		"homing names intensity and seek range")
	_expect(CrawlerHoming.enabled({"homing": 4.5, "homing_range": 8.0})
			and not CrawlerHoming.enabled({})
			and not CrawlerHoming.enabled({"homing": 4.5}),
		"homing needs both pull and seek")
	_expect(CrawlerHoming.uses_path({"homing": 4.5, "homing_range": 8.0})
			and CrawlerHoming.uses_path({"bounce": 1.0})
			and not CrawlerHoming.uses_path({}),
		"homing or bounce draw a path")
	var curve := CrawlerHoming.arc(
		Vector3.ZERO, Vector3(0.0, 0.0, -8.0), Vector3(0.0, 0.0, -1.0),
		{"homing": 8.0, "homing_range": 12.0})
	_expect(curve.size() == CrawlerHoming.ARC_STEPS + 1
			and curve[0].is_equal_approx(Vector3.ZERO)
			and curve[curve.size() - 1].is_equal_approx(Vector3(0.0, 0.0, -8.0)),
		"a homing arc keeps the start and end")
	var pull := {
		"homing": 8.0,
		"homing_range": 12.0,
	}
	_expect(CrawlerHoming.aim(
			Vector3.ZERO, Vector3(0.0, 0.0, -1.0), pull, null)
			.is_equal_approx(Vector3(0.0, 0.0, -1.0)),
		"aim without a mob keeps the original heading")
	var turned := CrawlerHoming.turn(
		Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, -1.0), pull, 0.25)
	_expect(turned.x > 0.05, "a punch heading leans toward its lock")
	_expect(CrawlerHoming.steer(
			Vector3(0.0, 0.0, -10.0), Vector3.ZERO, pull, null, 0.2, 10.0)
			.is_equal_approx(Vector3(0.0, 0.0, -10.0)),
		"steer without a mob keeps the shot going")
	var flagged := CrawlerCatalog.resolve_stats(
		"laser_eyes", PackedStringArray(["homing"]), {})
	_expect(CrawlerHoming.enabled(flagged)
			and is_equal_approx(CrawlerHoming.steer_of(flagged),
				CrawlerRules.homing_steer(0))
			and is_equal_approx(CrawlerHoming.range_of(flagged),
				CrawlerRules.homing_range(0)),
		"homing flags beams with the base pull and seek")
	_expect(CrawlerHoming.enabled(CrawlerCatalog.resolve_stats(
			"starfire", PackedStringArray(["homing"]), {})),
		"homing flags projectiles")
	_expect(CrawlerHoming.enabled(CrawlerCatalog.resolve_stats(
			"meteor_punch", PackedStringArray(["homing"]), {}))
			and CrawlerHoming.enabled(CrawlerCatalog.resolve_stats(
				"hero_punch", PackedStringArray(["homing"]), {})),
		"homing flags meteor punch and hero punch")
	_expect(not CrawlerCatalog.resolve_stats(
			"roar", PackedStringArray(["homing"]), {}).has("homing")
			and not CrawlerCatalog.resolve_stats(
				"wall", PackedStringArray(["homing"]), {}).has("homing"),
		"homing does not flag shockwaves or walls")
	_expect(CrawlerProgress.shop_stock().has("homing"),
		"the stall sells homing")
	_expect(CrawlerProgress.card_price("homing") == 22,
		"homing costs twenty-two")
	_expect(_player.crawler_kit.shop_grant("homing"),
		"the stall can grant homing")
	var card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "homing":
			card = owned
			break
	_expect(card != null, "the granted card is homing")
	if card == null:
		return
	_expect(_player.crawler_kit.upgrade_card(card.uid, "homing")
			and _player.crawler_kit.upgrade_card(card.uid, "range"),
		"homing can buy intensity and seek range")
	_expect(card.upgrade_rank("homing") == 1
			and card.upgrade_rank("range") == 1,
		"both homing ranks are stored on that card")
	var eyes := _player.crawler_kit.equipped_card(0)
	_expect(eyes != null and eyes.id == "laser_eyes",
		"laser eyes is seated for homing")
	if eyes == null:
		return
	_player.crawler_kit.inventory.set_item(0, card.token())
	var rack := _player.crawler_kit.mod_rack(0)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	var stats := _player.crawler_kit.stats_for(eyes)
	_expect(is_equal_approx(CrawlerHoming.steer_of(stats),
			CrawlerRules.homing_steer(1))
			and is_equal_approx(CrawlerHoming.range_of(stats),
				CrawlerRules.homing_range(1)),
		"one upgraded homing card gives laser eyes stronger pull and seek")
	_expect(CrawlerCatalog.description_of("homing", "laser_eyes").contains("mobs"),
		"beam copy mentions mobs")
	_expect(CrawlerCatalog.description_of("homing", "starfire").contains("Turns"),
		"projectile copy mentions the turn")
	_expect(CrawlerCatalog.description_of("homing", "meteor_punch").contains("Locks"),
		"meteor punch copy mentions the lock")
	_expect(CrawlerCatalog.description_of("homing", "hero_punch").contains("Locks"),
		"hero punch copy mentions the lock")
	_expect(CrawlerCatalog.description_of("homing", "roar").contains("does not fit"),
		"shockwave copy refuses homing")
	_expect(CrawlerCatalog.description_of("homing", "wall").contains("does not fit"),
		"wall copy refuses homing")
	_player.crawler_kit.shop_grant("wobble")
	_player.crawler_kit.shop_grant("bounce")
	var wobble: CrawlerCard = null
	var bounce: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "wobble":
			wobble = owned
		elif owned.id == "bounce":
			bounce = owned
	if wobble != null:
		_player.crawler_kit.inventory.set_item(1, wobble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	if bounce != null:
		_player.crawler_kit.inventory.set_item(2, bounce.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 2, rack, 2)
	var paired := _player.crawler_kit.stats_for(eyes)
	_expect(CrawlerHoming.enabled(paired)
			and float(paired.get("wobble", 0.0)) > 0.0
			and CrawlerBounce.count(paired) == 1,
		"homing pairs with wobble and bounce on laser eyes")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("homing")
	_player.crawler_kit.shop_grant("bubble")
	_player.crawler_kit.shop_grant("linger")
	var home: CrawlerCard = null
	var bubble: CrawlerCard = null
	var linger: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "homing":
			home = owned
		elif owned.id == "bubble":
			bubble = owned
		elif owned.id == "linger":
			linger = owned
	eyes = _player.crawler_kit.equipped_card(0)
	rack = _player.crawler_kit.mod_rack(0)
	if home != null:
		_player.crawler_kit.inventory.set_item(0, home.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	if bubble != null:
		_player.crawler_kit.inventory.set_item(1, bubble.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 1, rack, 1)
	if linger != null:
		_player.crawler_kit.inventory.set_item(2, linger.token())
		ItemContainer.transfer(_player.crawler_kit.inventory, 2, rack, 2)
	var host := _player.crawler_kit.stats_for(eyes)
	var bubbles := CrawlerBubbles.recipes_for_player(_player, "laser_eyes")
	_expect(not bubbles.is_empty()
			and CrawlerHoming.enabled(host)
			and float(bubbles[0].get("homing", 0.0))
				>= CrawlerHoming.range_of(host) - 0.001
			and float(bubbles[0].get("steer", 0.0))
				>= CrawlerHoming.steer_of(host) - 0.001,
		"a seated homing card makes bubble orbs chase even at bubble homing rank 0")
	var clouds := CrawlerLingers.recipes_for_player(_player, "laser_eyes")
	_expect(not clouds.is_empty()
			and is_equal_approx(float(clouds[0].get("homing", 0.0)),
				CrawlerHoming.range_of(host))
			and is_equal_approx(float(clouds[0].get("steer", 0.0)),
				CrawlerHoming.steer_of(host)),
		"linger clouds inherit the host homing pull and seek")
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	eyes = _player.crawler_kit.equipped_card(0)
	_player.crawler_kit.shop_grant("overdrive")
	var drive := _player.crawler_kit.equipped_card(1)
	_expect(drive != null and drive.id == "overdrive",
		"overdrive seats for a borrowed homing")
	if drive != null:
		var borrowed := CrawlerCatalog.make_modifier("homing")
		_player.crawler_kit.register(borrowed)
		_player.crawler_kit.inventory.set_item(2, borrowed.token())
		ItemContainer.transfer(
			_player.crawler_kit.inventory, 2, _player.crawler_kit.mod_rack(1), 0)
		_player.begin_overdrive(_player.crawler_kit.stats_for(drive), drive)
		var loaned := _player.crawler_kit.stats_for(eyes)
		_expect(_player.overdrive_active() and CrawlerHoming.enabled(loaned),
			"overdrive lends homing onto laser eyes")
		_player.end_overdrive()


func _check_ammo() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("clip") == PackedStringArray(["ammo"]),
		"clip sells an ammo multiplier")
	_expect(CrawlerRules.clip_ammo_mul(0) == 2
			and CrawlerRules.clip_ammo_mul(1) == 3
			and CrawlerRules.clip_ammo_mul(2) == 4,
		"clip starts at 2x and upgrades to 3x then 4x")
	_expect(CrawlerRules.upgrade_max_rank("clip", "ammo") == 2,
		"clip stops at 4x")
	_expect(CrawlerRules.upgrade_stats_for("endless").is_empty(),
		"endless has no store ranks")
	_expect(CrawlerProgress.shop_stock().has("clip")
			and CrawlerProgress.shop_stock().has("endless"),
		"the stall sells clip and endless")
	_expect(CrawlerProgress.ability_stock().has("nuke"),
		"the stall sells nuke")
	_expect(_player.crawler_kit.shop_grant("nuke"), "the stall can grant nuke")
	var nuke := _player.crawler_kit.equipped_card(1)
	_expect(nuke != null and nuke.id == "nuke", "nuke seats in an empty slot")
	if nuke == null:
		return
	_expect(_player.crawler_kit.ammo_max(nuke) == CrawlerRules.NUKE_AMMO
			and _player.crawler_kit.ammo_left(nuke) == CrawlerRules.NUKE_AMMO,
		"a new nuke starts with three shots")
	_expect(_player.crawler_kit.ammo_count_text(nuke) == "3",
		"hotbar count starts at three")
	_expect(_player.crawler_kit.ammo_line(nuke) == "3 / 3",
		"hero tab lists remaining over max")
	var before := nuke.fingerprint()
	_expect(_player.crawler_kit.spend_ammo(nuke), "the first shot spends")
	_expect(_player.crawler_kit.ammo_left(nuke) == 2, "two shots remain")
	_expect(nuke.fingerprint() == before, "spending a shot does not rebuild the card")
	_expect(_player.crawler_kit.spend_ammo(nuke)
			and _player.crawler_kit.spend_ammo(nuke),
		"the last two shots spend")
	_expect(_player.crawler_kit.ammo_left(nuke) == 0
			and not _player.crawler_kit.can_fire(nuke)
			and not _player.crawler_kit.spend_ammo(nuke),
		"an empty nuke cannot fire")
	_expect(_player.crawler_kit.needs_ammo_refill(),
		"an empty nuke needs a reststop refill")
	_expect(_player.crawler_kit.refill_ammo(nuke),
		"a reststop refill fills an empty nuke")
	_expect(_player.crawler_kit.ammo_left(nuke) == CrawlerRules.NUKE_AMMO
			and _player.crawler_kit.can_fire(nuke),
		"a refill restores the magazine")
	_expect(not _player.crawler_kit.refill_ammo(nuke)
			and not _player.crawler_kit.needs_ammo_refill(),
		"a full magazine does not refill")
	_expect(_player.crawler_kit.spend_ammo(nuke)
			and _player.crawler_kit.spend_ammo(nuke)
			and _player.crawler_kit.spend_ammo(nuke),
		"a refilled nuke can empty again")
	_expect(_player.crawler_kit.refill_all_ammo()
			and _player.crawler_kit.ammo_left(nuke) == CrawlerRules.NUKE_AMMO,
		"refill all tops every magazine")
	_expect(_player.crawler_kit.spend_ammo(nuke)
			and _player.crawler_kit.spend_ammo(nuke)
			and _player.crawler_kit.spend_ammo(nuke),
		"clip tests still start from an empty mag")
	_expect(_player.crawler_kit.equipped_card(1) != null
			and _player.crawler_kit.equipped_card(1).uid == nuke.uid,
		"an empty nuke stays on the hotbar")
	_expect(_player.crawler_kit.ammo_count_text(nuke) == "0",
		"the count reads zero when empty")
	_expect(_player.crawler_kit.shop_grant("clip"), "the stall can grant clip")
	var clip: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "clip":
			clip = card
			break
	_expect(clip != null, "the granted card is clip")
	if clip == null:
		return
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "nuke exposes a mod rack")
	var bag_index := _player.crawler_kit.inventory.find(clip.token())
	_expect(bag_index >= 0, "clip landed in the bag")
	ItemContainer.transfer(_player.crawler_kit.inventory, bag_index, rack, 0)
	_expect(nuke.filled_modifier_ids().has("clip"), "clip seats on nuke")
	_expect(_player.crawler_kit.ammo_max(nuke) == CrawlerRules.NUKE_AMMO * 2,
		"clip doubles the magazine")
	_expect(_player.crawler_kit.ammo_left(nuke) == CrawlerRules.NUKE_AMMO,
		"clip adds the extra shots to an empty mag")
	_expect(_player.crawler_kit.upgrade_card(clip.uid, "ammo"),
		"clip can upgrade to 3x")
	_expect(_player.crawler_kit.ammo_max(nuke) == CrawlerRules.NUKE_AMMO * 3,
		"the first clip upgrade is 3x")
	_expect(_player.crawler_kit.upgrade_card(clip.uid, "ammo"),
		"clip can upgrade to 4x")
	_expect(_player.crawler_kit.ammo_max(nuke) == CrawlerRules.NUKE_AMMO * 4,
		"the second clip upgrade is 4x")
	_expect(not _player.crawler_kit.upgrade_card(clip.uid, "ammo"),
		"clip stops at 4x")
	_expect(_player.crawler_kit.shop_grant("endless"), "the stall can grant endless")
	var endless: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "endless":
			endless = card
			break
	_expect(endless != null, "the granted card is endless")
	if endless == null:
		return
	var endless_bag := _player.crawler_kit.inventory.find(endless.token())
	_expect(endless_bag >= 0, "endless landed in the bag")
	rack = _player.crawler_kit.mod_rack(1)
	_expect(rack != null and rack.size() > 1, "nuke still has a free mod seat")
	ItemContainer.transfer(_player.crawler_kit.inventory, endless_bag, rack, 1)
	_expect(nuke.filled_modifier_ids().has("endless"), "endless seats on nuke")
	_expect(_player.crawler_kit.has_endless(nuke)
			and _player.crawler_kit.can_fire(nuke)
			and _player.crawler_kit.ammo_count_text(nuke) == "∞",
		"endless never runs out")
	nuke.extra_stats["ammo"] = 0
	_expect(_player.crawler_kit.can_fire(nuke),
		"endless still fires when the count is empty")
	_expect(not _player.crawler_kit.refill_ammo(nuke)
			and not _player.crawler_kit.needs_ammo_refill()
			and not _player.crawler_kit.refill_all_ammo(),
		"endless does not take a reststop refill")
	var page := CrawlerHeroPage.new()
	page.configure(_player)
	add_child(page)
	page.refresh()
	page.select_token(nuke.token())
	var body := page.find_child("CrawlerDescriptionBody", true, false) as Label
	_expect(body != null and body.text.to_upper().contains("AMMO")
			and body.text.to_upper().contains("INFINITE"),
		"hero tab lists infinite ammo")
	var tile := page.find_child("CrawlerAbilityTile_1", true, false) as CrawlerAbilityTile
	var ammo_label := tile.find_child("CrawlerAbilityAmmo", true, false) as Label \
		if tile != null else null
	_expect(ammo_label != null and ammo_label.visible and ammo_label.text == "∞",
		"hero tile shows infinite shots")
	page.queue_free()


func _check_kame() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("kame")
			== CrawlerRules.upgrade_stats_for("laser_eyes"),
		"kame sells the same upgrade set as laser eyes")
	_expect(CrawlerRules.KAME_DAMAGE > CrawlerRules.LASER_DAMAGE
			and CrawlerRules.KAME_RANGE >= CrawlerRules.LASER_RANGE * 3.0
			and CrawlerRules.KAME_DURATION > 1.0
			and CrawlerRules.KAME_RADIUS > 0.45
			and CrawlerRules.KAME_DAMAGE_HZ > LaserEyes.DAMAGE_HZ
			and CrawlerRules.KAME_COOLDOWN > CrawlerRules.LASER_COOLDOWN
			and CrawlerRules.KAME_LOOK_SCALE < 0.5,
		"kame is a longer, heavier burst than laser eyes")
	_expect(CrawlerProgress.ability_stock().has("kame")
			and CrawlerProgress.ability_price("kame") > 0,
		"the ability stall sells kame")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability(
			"kame", CrawlerRules.KAME_SLOTS,
			CrawlerRules.kame_start_stats()).to_dict())
	_expect(bool(granted.get("ok", false)), "kame can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "kame", "kame is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)), CrawlerRules.KAME_DAMAGE),
		"base kame damage is the stronger rate")
	_expect(str(base.get("damage_unit", "")) == "/s",
		"kame lists damage as a rate")
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)), CrawlerRules.KAME_COOLDOWN),
		"base kame cooldown is the long wait")
	_expect(is_equal_approx(float(base.get("duration", 0.0)), CrawlerRules.KAME_DURATION),
		"base kame burst lasts the authored cook")
	_expect(is_equal_approx(float(base.get("range", 0.0)), CrawlerRules.KAME_RANGE),
		"base kame reaches much farther than laser eyes")
	_expect(is_equal_approx(float(base.get("radius", 0.0)), CrawlerRules.KAME_RADIUS),
		"base kame is basketball-thick")
	_expect(is_equal_approx(float(base.get("beam_width", 0.0)),
			CrawlerRules.KAME_BEAM_WIDTH),
		"base kame has the authored beam width")
	_expect(is_equal_approx(float(base.get("damage_hz", 0.0)),
			CrawlerRules.KAME_DAMAGE_HZ),
		"base kame pulses faster than laser eyes")
	_expect(is_equal_approx(float(base.get("knockback", 0.0)),
			CrawlerRules.KAME_KNOCKBACK),
		"base kame knocks along the beam")
	var kame := _player.ability_controller().ability_in(1) as Kame
	_expect(kame != null and not kame._pulse_mode(),
		"kame is a single burst, not a pulse train")
	if kame == null:
		return
	_expect(kame.press(), "kame starts the burst")
	kame.tick(0.05)
	_expect(kame.is_held() and kame._left > 1.5,
		"the burst stays on for the rooted cook")
	kame.release()
	_expect(kame.is_held() and kame._is_beam_lit(),
		"releasing the button does not cut the burst short")
	_expect(is_equal_approx(_player._beam_look_scale, CrawlerRules.KAME_LOOK_SCALE),
		"kame slows look while the beam is rooted")
	kame.tick(CrawlerRules.KAME_DURATION)
	_expect(not kame.is_held(), "the burst ends after the authored cook")
	kame.tick(CrawlerRules.KAME_COOLDOWN)
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"kame damage can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("damage", 0.0))
			> CrawlerRules.KAME_DAMAGE,
		"damage upgrades raise the kame rate")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"kame cooldown can be upgraded")
	var cooled := float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
	_expect(cooled < CrawlerRules.KAME_COOLDOWN
			and cooled >= CrawlerRules.KAME_COOLDOWN_MIN,
		"cooldown upgrades shorten kame without making it spammy")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "duration"),
		"kame duration can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("duration", 0.0))
			> CrawlerRules.KAME_DURATION,
		"duration upgrades lengthen the burst")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"kame range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.KAME_RANGE,
		"range upgrades lengthen kame")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"kame size can be upgraded")
	var grown := _player.crawler_kit.stats_for(card)
	_expect(float(grown.get("radius", 0.0)) > CrawlerRules.KAME_RADIUS,
		"size upgrades thicken the kame beam")
	_expect(float(grown.get("beam_width", 0.0)) > CrawlerRules.KAME_BEAM_WIDTH,
		"size upgrades widen the drawn kame beam")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"kame knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.KAME_KNOCKBACK,
		"knockback upgrades shove farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"kame slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.KAME_SLOTS + 1,
		"slot upgrades add a modifier seat")
	_expect(_player.crawler_kit.shop_grant("wobble"),
		"a wobble can be granted for kame")
	var wobble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "wobble":
			wobble = owned
			break
	_expect(wobble != null, "the granted card is wobble")
	if wobble == null:
		return
	_player.crawler_kit.inventory.set_item(0, wobble.token())
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "kame exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	_expect(card.filled_modifier_ids().has("wobble"),
		"wobble seats on kame")
	_expect(float(_player.crawler_kit.stats_for(card).get("wobble", 0.0)) > 0.0,
		"seated wobble flags kame")
	_expect(_player.crawler_kit.shop_grant("bubble"),
		"a bubble can be granted for kame")
	var bubble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bubble":
			bubble = owned
			break
	_expect(bubble != null, "the granted card is bubble")
	if bubble == null:
		return
	_player.crawler_kit.inventory.set_item(0, bubble.token())
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 1)
	_expect(card.filled_modifier_ids().has("bubble"),
		"bubble seats on kame")
	var recipes := CrawlerBubbles.recipes_for_player(_player, "kame")
	_expect(not recipes.is_empty(), "kame with bubble emits a bubble stream")
	_expect(CrawlerCatalog.compatible("big", "kame"), "big fits kame")
	_expect(String(CharacterRig.CLIP_ALIASES.get("Kame", "")) == "Two-hand_Blast",
		"kame uses the two-hand blast clip")


func _check_nausicaa() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("nausicaa")
			== CrawlerRules.upgrade_stats_for("laser_eyes"),
		"nausicaa sells the same upgrade set as laser eyes")
	_expect(CrawlerRules.NAUSICAA_RANGE < CrawlerRules.LASER_RANGE
			and CrawlerRules.NAUSICAA_COOLDOWN > CrawlerRules.LASER_COOLDOWN
			and CrawlerRules.NAUSICAA_DELAY > 0.0
			and CrawlerRules.NAUSICAA_RADIUS > 0.45,
		"nausicaa is a short delayed terrain sweep")
	_expect(CrawlerProgress.ability_stock().has("nausicaa")
			and CrawlerProgress.ability_price("nausicaa") > 0,
		"the ability stall sells nausicaa")
	_expect(_player.crawler_kit.shop_grant("nausicaa"),
		"the stall can grant nausicaa")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "nausicaa",
		"nausicaa is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)),
			CrawlerRules.NAUSICAA_DAMAGE),
		"base nausicaa damage is the crawler blast")
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)),
			CrawlerRules.NAUSICAA_COOLDOWN),
		"base nausicaa cooldown is the long wait")
	_expect(is_equal_approx(float(base.get("duration", 0.0)),
			CrawlerRules.NAUSICAA_DURATION),
		"base nausicaa sweep lasts the authored time")
	_expect(is_equal_approx(float(base.get("range", 0.0)),
			CrawlerRules.NAUSICAA_RANGE),
		"base nausicaa stays a short eye laser")
	_expect(is_equal_approx(float(base.get("radius", 0.0)),
			CrawlerRules.NAUSICAA_RADIUS),
		"base nausicaa blast uses the crawler radius")
	_expect(is_equal_approx(float(base.get("beam_width", 0.0)),
			CrawlerRules.NAUSICAA_BEAM_WIDTH),
		"base nausicaa has the authored beam width")
	_expect(is_equal_approx(float(base.get("delay", 0.0)),
			CrawlerRules.NAUSICAA_DELAY),
		"base nausicaa keeps the one-second fuse")
	_expect(is_equal_approx(float(base.get("paint_radius", 0.0)),
			CrawlerRules.NAUSICAA_PAINT_RADIUS),
		"base nausicaa paints the authored marks")
	_expect(is_equal_approx(float(base.get("knockback", 0.0)),
			CrawlerRules.NAUSICAA_KNOCKBACK),
		"base nausicaa knocks on detonation")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"nausicaa damage can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("damage", 0.0))
			> CrawlerRules.NAUSICAA_DAMAGE,
		"damage upgrades raise the nausicaa blast")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"nausicaa cooldown can be upgraded")
	var cooled := float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
	_expect(cooled < CrawlerRules.NAUSICAA_COOLDOWN
			and cooled >= CrawlerRules.NAUSICAA_COOLDOWN_MIN,
		"cooldown upgrades shorten nausicaa without making it spammy")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "duration"),
		"nausicaa duration can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("duration", 0.0))
			> CrawlerRules.NAUSICAA_DURATION,
		"duration upgrades lengthen the sweep")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"nausicaa range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.NAUSICAA_RANGE,
		"range upgrades lengthen nausicaa")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"nausicaa size can be upgraded")
	var grown := _player.crawler_kit.stats_for(card)
	_expect(float(grown.get("radius", 0.0)) > CrawlerRules.NAUSICAA_RADIUS,
		"size upgrades widen the nausicaa blast")
	_expect(float(grown.get("beam_width", 0.0)) > CrawlerRules.NAUSICAA_BEAM_WIDTH,
		"size upgrades widen the painted beam")
	_expect(float(grown.get("paint_radius", 0.0))
			> CrawlerRules.NAUSICAA_PAINT_RADIUS,
		"size upgrades grow the painted marks")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"nausicaa knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.NAUSICAA_KNOCKBACK,
		"knockback upgrades shove farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"nausicaa slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.NAUSICAA_SLOTS + 1,
		"slot upgrades add a modifier seat")
	_expect(_player.crawler_kit.shop_grant("wobble"),
		"a wobble can be granted for nausicaa")
	var wobble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "wobble":
			wobble = owned
			break
	_expect(wobble != null, "the granted card is wobble")
	if wobble == null:
		return
	_player.crawler_kit.inventory.set_item(0, wobble.token())
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "nausicaa exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	_expect(card.filled_modifier_ids().has("wobble"),
		"wobble seats on nausicaa")
	_expect(float(_player.crawler_kit.stats_for(card).get("wobble", 0.0)) > 0.0,
		"seated wobble flags nausicaa")
	_expect(_player.crawler_kit.shop_grant("bubble"),
		"a bubble can be granted for nausicaa")
	var bubble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bubble":
			bubble = owned
			break
	_expect(bubble != null, "the granted card is bubble")
	if bubble == null:
		return
	_player.crawler_kit.inventory.set_item(0, bubble.token())
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 1)
	_expect(card.filled_modifier_ids().has("bubble"),
		"bubble seats on nausicaa")
	var recipes := CrawlerBubbles.recipes_for_player(_player, "nausicaa")
	_expect(not recipes.is_empty(), "nausicaa with bubble emits a bubble stream")
	_expect(CrawlerCatalog.compatible("big", "nausicaa"), "big fits nausicaa")
	_expect(_player.crawler_kit.shop_grant("big"),
		"a big can be granted for nausicaa")
	var big: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "big":
			big = owned
			break
	_expect(big != null, "the granted card is big")
	if big == null:
		return
	_player.crawler_kit.inventory.set_item(0, big.token())
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 2)
	_expect(card.filled_modifier_ids().has("big"), "big seats on nausicaa")
	var bloated := _player.crawler_kit.stats_for(card)
	_expect(float(bloated.get("radius", 0.0)) > float(grown.get("radius", 0.0)),
		"big widens the nausicaa blast")
	_expect(float(bloated.get("paint_radius", 0.0))
			> float(grown.get("paint_radius", 0.0)),
		"big grows the painted marks")
	var painted := CrawlerCatalog.resolve_stats(
		"nausicaa", PackedStringArray(["big"]),
		{"radius": CrawlerRules.NAUSICAA_RADIUS,
			"crater_radius": CrawlerRules.NAUSICAA_CRATER_RADIUS,
			"beam_width": CrawlerRules.NAUSICAA_BEAM_WIDTH,
			"paint_radius": CrawlerRules.NAUSICAA_PAINT_RADIUS})
	_expect(is_equal_approx(float(painted.get("radius", 0.0)),
			CrawlerRules.NAUSICAA_RADIUS * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies nausicaa blast radius")
	_expect(is_equal_approx(float(painted.get("paint_radius", 0.0)),
			CrawlerRules.NAUSICAA_PAINT_RADIUS * CrawlerRules.BIG_SIZE_BASE),
		"big multiplies nausicaa paint marks")
	_expect(not CrawlerCatalog.compatible("clip", "nausicaa")
			and not CrawlerCatalog.compatible("endless", "nausicaa"),
		"clip and endless do not fit nausicaa")


func _check_fields() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("static_field").has("shock")
			and CrawlerRules.upgrade_stats_for("toxic_field").has("toxic")
			and CrawlerRules.upgrade_stats_for("freeze_field").has("freeze")
			and CrawlerRules.upgrade_stats_for("healing_field").has("heal"),
		"each field sells its signature upgrade")
	_expect(CrawlerRules.upgrade_stats_for("static_field").has("cast")
			and CrawlerRules.upgrade_stat_title("cast", "static_field")
				== "Cast Time",
		"fields sell a cast-time upgrade")
	_expect(CrawlerRules.upgrade_stat_title("duration", "static_field")
			== "Lifetime",
		"field duration is how long the sphere stays")
	_expect(CrawlerProgress.ability_stock().has("static_field")
			and CrawlerProgress.ability_stock().has("toxic_field")
			and CrawlerProgress.ability_stock().has("freeze_field")
			and CrawlerProgress.ability_stock().has("healing_field"),
		"the ability stall sells the four fields")
	_expect(_player.crawler_kit.shop_grant("static_field"),
		"the stall can grant static field")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "static_field",
		"static field is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("radius", 0.0)),
			CrawlerRules.FIELD_RADIUS),
		"base field expands to seven metres")
	_expect(is_equal_approx(float(base.get("shock", 0.0)),
			CrawlerRules.FIELD_SHOCK),
		"static field starts with shock")
	_expect(is_equal_approx(float(base.get("cast", 0.0)),
			CrawlerRules.FIELD_CAST),
		"a field starts as a one-second stand")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cast"),
		"field cast time can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("cast", 0.0))
			< CrawlerRules.FIELD_CAST,
		"cast upgrades shorten the stand-still")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "shock"),
		"static shock can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("shock", 0.0))
			> CrawlerRules.FIELD_SHOCK,
		"shock upgrades hold the lock-and-twitch longer")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "duration"),
		"field lifetime can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("duration", 0.0))
			> CrawlerRules.FIELD_DURATION,
		"lifetime upgrades keep the sphere up longer")
	_expect(_player.crawler_kit.shop_grant("toxic_field"),
		"the stall can grant toxic field")
	var toxic := _player.crawler_kit.equipped_card(2)
	_expect(toxic != null and toxic.id == "toxic_field",
		"toxic field seats on the last hotbar slot")
	if toxic != null:
		_expect(_player.crawler_kit.upgrade_card(toxic.uid, "toxic"),
			"toxic hold can be upgraded")
		_expect(float(_player.crawler_kit.stats_for(toxic).get("toxic", 0.0))
				> CrawlerRules.FIELD_TOXIC,
			"toxic upgrades lengthen stacked poison")
	var freeze_stats := CrawlerRules.field_start_stats("freeze_field")
	_expect(is_equal_approx(float(freeze_stats.get("freeze", 0.0)),
			CrawlerRules.FIELD_FREEZE),
		"freeze field starts by cutting speed hard")
	_expect(_player.crawler_kit.shop_grant("healing_field"),
		"the stall can grant healing field")
	var heal_card: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "healing_field":
			heal_card = owned
			break
	_expect(heal_card != null, "the granted card is healing field")
	if heal_card != null:
		var heal_stats := _player.crawler_kit.stats_for(heal_card)
		_expect(is_equal_approx(float(heal_stats.get("heal", 0.0)),
				CrawlerRules.FIELD_HEAL),
			"healing field starts at the authored heal")
		_expect(is_equal_approx(float(heal_stats.get("radius", 0.0)),
				CrawlerRules.FIELD_RADIUS)
				and is_equal_approx(float(heal_stats.get("cast", 0.0)),
					CrawlerRules.FIELD_CAST)
				and is_equal_approx(float(heal_stats.get("cooldown", 0.0)),
					CrawlerRules.FIELD_COOLDOWN),
			"healing field shares the field family baseline")
		_expect(CrawlerRules.upgrade_stats_for("healing_field").has("heal")
				and CrawlerRules.upgrade_stats_for("healing_field").has("cast")
				and CrawlerRules.upgrade_stats_for("healing_field").has("duration")
				and CrawlerRules.upgrade_stats_for("healing_field").has("range")
				and CrawlerRules.upgrade_stats_for("healing_field").has("size")
				and CrawlerRules.upgrade_stats_for("healing_field").has("cooldown")
				and CrawlerRules.upgrade_stats_for("healing_field").has("slots")
				and not CrawlerRules.upgrade_stats_for("healing_field").has("damage"),
			"healing field sells heal and the shared field upgrades")
		_expect(_player.crawler_kit.upgrade_card(heal_card.uid, "heal"),
			"heal can be upgraded")
		_expect(float(_player.crawler_kit.stats_for(heal_card).get("heal", 0.0))
				> CrawlerRules.FIELD_HEAL,
			"heal upgrades restore more")
		_expect(_player.crawler_kit.upgrade_card(heal_card.uid, "range"),
			"healing field range can be upgraded")
		_expect(float(_player.crawler_kit.stats_for(heal_card).get("radius", 0.0))
				> CrawlerRules.FIELD_RADIUS,
			"range upgrades grow the heal sphere")
		_expect(CrawlerCatalog.host_abilities("bubble").has("healing_field"),
			"bubble hosts healing field")
		var wounded := _player.maximum_health() * 0.4
		_player.stats.set_health(wounded)
		var heal_at := _player.combat_position()
		var volume := CrawlerFieldVolume.create(
			self, _player, "healing_field", heal_at,
			_player.crawler_kit.stats_for(heal_card),
			Color(0.54, 0.94, 0.75), true)
		if volume != null:
			volume._age = CrawlerFieldVolume.EXPAND
			volume._tick_inside()
			_expect(_player.health() > wounded,
				"standing in a healing field restores the owner")
			volume.queue_free()
	var carried := CrawlerBubbles.host_status(
		"static_field", _player.crawler_kit.stats_for(card), _player)
	_expect(str(carried.get("id", "")) == String(CombatStatuses.SHOCK),
		"bubble spreader can carry static-field shock")
	_expect(_player.crawler_kit.shop_grant("bubble"),
		"a bubble can be granted for static field")
	var bubble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bubble":
			bubble = owned
			break
	_expect(bubble != null, "the granted card is bubble")
	if bubble != null:
		var bag := _player.crawler_kit.inventory.find(bubble.token())
		var field_rack := _player.crawler_kit.mod_rack(1)
		_expect(bag >= 0 and field_rack != null,
			"static field can seat the granted bubble")
		if bag >= 0 and field_rack != null:
			ItemContainer.transfer(_player.crawler_kit.inventory, bag, field_rack, 0)
			_expect(card.filled_modifier_ids().has("bubble"),
				"bubble seats on static field")
			var field_at := Vector3(1.5, 7.0, 2.0)
			var orbs := CrawlerBubbles.emit_field(
				_player, "static_field", field_at, 7.0)
			_expect(orbs.size() >= CrawlerRules.BUBBLE_FIELD_COUNT,
				"a field with bubble leaves a bloom")
			_expect(_bubbles_surround(field_at, orbs),
				"field bubbles bloom around the sphere, not in a line")
			for orb: CrawlerBubble in orbs:
				if is_instance_valid(orb):
					orb.queue_free()
	_check_field_cast(card)


func _check_field_cast(card: CrawlerCard) -> void:
	var definition := ItemDB.ability_definition("static_field")
	_expect(definition != null, "static field has a generated definition")
	if definition == null or card == null:
		return
	var ability := CrawlerField.new()
	ability.configure(_player, 1, "static_field", definition)
	ability.apply_crawler(card)
	var wait := CrawlerRules.field_cast_time(
		float(ability.stats.get("cast", CrawlerRules.FIELD_CAST)),
		_player.crawler_cast_trim())
	_free_fields()
	_player.global_position = Vector3(4.0, 2.0, 1.0)
	_expect(ability.press(), "a field starts the stand-still")
	_expect(_player.field_casting(), "the stand-still roots the caster")
	ability.tick(maxf(wait - 0.05, 0.0))
	_expect(_field_volumes().is_empty(), "the sphere waits out the stand")
	ability.tick(0.10)
	_expect(not _field_volumes().is_empty(), "the sphere appears after the stand")
	ability.cancel()
	_free_fields()
	_player.global_position = Vector3(4.0, 2.0, 1.0)
	_expect(ability.press(), "a second cast can start")
	_player.global_position += Vector3(CrawlerRules.FIELD_CAST_BREAK + 0.5, 0.0, 0.0)
	ability.tick(0.05)
	_expect(not ability.is_held() and _field_volumes().is_empty(),
		"leaving the spot cancels the stand")
	_expect(is_zero_approx(ability.cooldown_left()),
		"a broken stand does not start the cooldown")
	var before := wait
	_player.crawler_progress.ranks[CrawlerProgress.STAT_CAST] = 1
	var faster := CrawlerRules.field_cast_time(
		float(ability.stats.get("cast", CrawlerRules.FIELD_CAST)),
		_player.crawler_cast_trim())
	_expect(faster < before - 0.001, "a cast rank shortens the stand")
	_player.crawler_progress.ranks[CrawlerProgress.STAT_CAST] = 0


func _field_volumes() -> Array[CrawlerFieldVolume]:
	var found: Array[CrawlerFieldVolume] = []
	if not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP):
		var field := node_variant as CrawlerFieldVolume
		if field != null:
			found.append(field)
	return found


func _free_fields() -> void:
	for field: CrawlerFieldVolume in _field_volumes():
		field.free()


func _check_lightning() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("lightning").has("arcs")
			and CrawlerRules.upgrade_stats_for("lightning").has("shock"),
		"lightning sells arcs and shock")
	_expect(CrawlerRules.is_pulsed_beam("lightning"),
		"lightning is a pulsed beam")
	_expect(CrawlerProgress.ability_stock().has("lightning")
			and CrawlerProgress.ability_price("lightning") > 0,
		"the ability stall sells lightning")
	_expect(_player.crawler_kit.shop_grant("lightning"),
		"the stall can grant lightning")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "lightning",
		"lightning is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)),
			CrawlerRules.LIGHTNING_DAMAGE),
		"base lightning damage is the crawler bolt")
	_expect(is_equal_approx(float(base.get("arcs", 0.0)),
			float(CrawlerRules.LIGHTNING_ARCS)),
		"base lightning hops to one extra target")
	_expect(is_equal_approx(float(base.get("shock", -1.0)), 0.0),
		"base lightning has no shock until upgraded")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "arcs"),
		"lightning arcs can be upgraded")
	_expect(is_equal_approx(float(_player.crawler_kit.stats_for(card).get(
			"arcs", 0.0)), float(CrawlerRules.LIGHTNING_ARCS + 1)),
		"each arcs rank adds one hop")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "shock"),
		"lightning shock can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("shock", 0.0))
			> 0.0,
		"shock upgrades apply the lock-and-twitch pulse")
	_expect(CrawlerCatalog.compatible("wobble", "lightning")
			and CrawlerCatalog.compatible("bubble", "lightning")
			and CrawlerCatalog.compatible("big", "lightning"),
		"beam mods fit lightning")
	var carried := CrawlerBubbles.host_status(
		"lightning", _player.crawler_kit.stats_for(card), _player)
	_expect(str(carried.get("id", "")) == String(CombatStatuses.SHOCK),
		"bubble spreader can carry lightning shock")


func _check_wall() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("wall") == PackedStringArray(
			["cooldown", "range", "duration", "size",
				"project", "firewall", "house", "slots"]),
		"wall sells cooldown, range, lifetime, size, project, firewall, house, and slots")
	_expect(CrawlerRules.upgrade_stat_title("duration", "wall") == "Lifetime",
		"wall duration is lifetime")
	_expect(CrawlerRules.upgrade_max_rank("wall", "house") == 1,
		"house is on or off")
	_expect(CrawlerProgress.ability_stock().has("wall")
			and CrawlerProgress.ability_price("wall") > 0,
		"the ability stall sells wall")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability(
			"wall", CrawlerRules.WALL_SLOTS,
			CrawlerRules.wall_start_stats()).to_dict())
	_expect(bool(granted.get("ok", false)), "wall can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "wall", "wall is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("cooldown", 0.0)), CrawlerRules.WALL_COOLDOWN),
		"base wall cooldown is the authored wait")
	_expect(is_equal_approx(float(base.get("range", 0.0)), CrawlerRules.WALL_RANGE),
		"base wall appears at the authored range")
	_expect(is_equal_approx(float(base.get("duration", 0.0)), CrawlerRules.WALL_DURATION),
		"base wall stands for the authored lifetime")
	_expect(is_equal_approx(float(base.get("wall_width", 0.0)), CrawlerRules.WALL_WIDTH)
			and is_equal_approx(float(base.get("wall_height", 0.0)),
				CrawlerRules.WALL_HEIGHT),
		"base wall uses the authored slab")
	_expect(is_equal_approx(float(base.get("project", 0.0)), 0.0)
			and is_equal_approx(float(base.get("firewall", 0.0)), 0.0)
			and is_equal_approx(float(base.get("house", 0.0)), 0.0),
		"base wall starts still, cold, and as a slab")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"wall cooldown can be upgraded")
	var cooled := float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
	_expect(cooled < CrawlerRules.WALL_COOLDOWN
			and cooled >= CrawlerRules.WALL_COOLDOWN_MIN,
		"cooldown upgrades shorten wall without making it spammy")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"wall range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.WALL_RANGE,
		"range upgrades place the slab farther out")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "duration"),
		"wall lifetime can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("duration", 0.0))
			> CrawlerRules.WALL_DURATION,
		"lifetime upgrades keep the barrier up longer")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"wall size can be upgraded")
	var grown := _player.crawler_kit.stats_for(card)
	_expect(float(grown.get("wall_width", 0.0)) > CrawlerRules.WALL_WIDTH
			and float(grown.get("wall_height", 0.0)) > CrawlerRules.WALL_HEIGHT,
		"size upgrades grow the slab")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "project"),
		"wall project can be upgraded")
	_expect(is_equal_approx(
			float(_player.crawler_kit.stats_for(card).get("project", 0.0)),
			CrawlerRules.wall_project_speed(1)),
		"project rank one slides at the authored speed")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "project"),
		"wall project can be upgraded again")
	_expect(is_equal_approx(
			float(_player.crawler_kit.stats_for(card).get("project", 0.0)),
			CrawlerRules.wall_project_speed(2)),
		"project upgrades slide the wall faster")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "firewall"),
		"wall firewall can be upgraded")
	_expect(is_equal_approx(
			float(_player.crawler_kit.stats_for(card).get("firewall", 0.0)),
			CrawlerRules.wall_firewall_damage(1)),
		"firewall rank one burns at the authored rate")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "firewall"),
		"wall firewall can be upgraded again")
	_expect(float(_player.crawler_kit.stats_for(card).get("firewall", 0.0))
			> CrawlerRules.wall_firewall_damage(1),
		"firewall upgrades burn harder")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "house"),
		"wall house can be turned on")
	var housed := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(housed.get("house", 0.0)), 1.0)
			and float(housed.get("project", 0.0)) > 0.0
			and float(housed.get("firewall", 0.0)) > 0.0,
		"house, project, and firewall can sit on the same wall")
	_expect(not _player.crawler_kit.upgrade_card(card.uid, "house"),
		"house stops at on")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"wall slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.WALL_SLOTS + 1,
		"slot upgrades add a modifier seat")
	_expect(_player.crawler_kit.shop_grant("big"),
		"a big can be granted for wall")
	var big: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "big":
			big = owned
			break
	_expect(big != null, "the granted card is big")
	if big == null:
		return
	_player.crawler_kit.inventory.set_item(0, big.token())
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "wall exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 0)
	_expect(card.filled_modifier_ids().has("big"), "big seats on wall")
	var with_big := _player.crawler_kit.stats_for(card)
	_expect(float(with_big.get("wall_width", 0.0))
			> float(housed.get("wall_width", 0.0)),
		"seated big widens the wall")
	_expect(float(with_big.get("size", 0.0)) > float(housed.get("size", 1.0)),
		"seated big raises wall size")
	var page := CrawlerHeroPage.new()
	page.configure(_player)
	add_child(page)
	page.refresh()
	page.select_token(card.token())
	var body := page.find_child("CrawlerDescriptionBody", true, false) as Label
	var shown := body.text.to_upper() if body != null else ""
	for label: String in ["COOLDOWN", "RANGE", "DURATION", "SIZE",
			"PROJECT", "FIREWALL", "HOUSE", "SLOTS"]:
		_expect(shown.contains(label),
			"selected wall lists %s" % label.to_lower())
	page.queue_free()


func _check_mini_nuke() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(CrawlerRules.upgrade_stats_for("mini_nuke") == PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"]),
		"mini nuke sells damage, cooldown, size, range, knockback, and slots")
	_expect(CrawlerProgress.ability_stock().has("mini_nuke")
			and CrawlerProgress.ability_price("mini_nuke") > 0,
		"the ability stall sells mini nuke")
	_expect(ItemDB.ability_definition("nuke").animation == &"Kame"
			and ItemDB.ability_definition("mini_nuke").animation == &"Kame"
			and ItemDB.ability_definition("nuke").hover_animation.is_empty()
			and ItemDB.ability_definition("mini_nuke").hover_animation.is_empty(),
		"nuke and mini nuke throw with the kame pose")
	_expect(CrawlerRules.MINI_NUKE_RADIUS < 110.0
			and CrawlerRules.MINI_NUKE_SPEED > 90.0
			and CrawlerRules.MINI_NUKE_RANGE > 240.0,
		"mini nuke is smaller, faster, and flies farther than nuke")
	var granted := _player.crawler_kit.grant(
		CrawlerCatalog.make_ability(
			"mini_nuke", CrawlerRules.MINI_NUKE_SLOTS,
			CrawlerRules.mini_nuke_start_stats()).to_dict())
	_expect(bool(granted.get("ok", false)), "mini nuke can be granted")
	var card := _player.crawler_kit.equipped_card(1)
	_expect(card != null and card.id == "mini_nuke",
		"mini nuke is seated for upgrades")
	if card == null:
		return
	var base := _player.crawler_kit.stats_for(card)
	_expect(is_equal_approx(float(base.get("damage", 0.0)),
			CrawlerRules.MINI_NUKE_DAMAGE),
		"base mini nuke damage is the smaller burst")
	_expect(is_equal_approx(float(base.get("speed", 0.0)),
			CrawlerRules.MINI_NUKE_SPEED),
		"base mini nuke flies faster than nuke")
	_expect(is_equal_approx(float(base.get("range", 0.0)),
			CrawlerRules.MINI_NUKE_RANGE),
		"base mini nuke detonates farther out")
	_expect(is_equal_approx(float(base.get("radius", 0.0)),
			CrawlerRules.MINI_NUKE_RADIUS),
		"base mini nuke blast is the authored small radius")
	_expect(_player.crawler_kit.ammo_max(card) == CrawlerRules.MINI_NUKE_AMMO
			and _player.crawler_kit.ammo_left(card) == CrawlerRules.MINI_NUKE_AMMO,
		"a new mini nuke starts with five shots")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "damage"),
		"mini nuke damage can be upgraded")
	var harder := _player.crawler_kit.stats_for(card)
	_expect(float(harder.get("damage", 0.0)) > CrawlerRules.MINI_NUKE_DAMAGE
			and float(harder.get("impact", 0.0)) > CrawlerRules.MINI_NUKE_IMPACT,
		"damage upgrades raise the core and the burst")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "cooldown"),
		"mini nuke cooldown can be upgraded")
	var cooled := float(_player.crawler_kit.stats_for(card).get("cooldown", 0.0))
	_expect(cooled < CrawlerRules.MINI_NUKE_COOLDOWN
			and cooled >= CrawlerRules.MINI_NUKE_COOLDOWN_MIN,
		"cooldown upgrades shorten mini nuke without making it spammy")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "size"),
		"mini nuke size can be upgraded")
	var grown := _player.crawler_kit.stats_for(card)
	_expect(float(grown.get("radius", 0.0)) > CrawlerRules.MINI_NUKE_RADIUS
			and float(grown.get("projectile_radius", 0.0))
				> CrawlerRules.MINI_NUKE_PROJECTILE_RADIUS
			and float(grown.get("crater_radius", 0.0))
				> CrawlerRules.MINI_NUKE_CRATER_RADIUS,
		"size upgrades grow the core, blast, and crater")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "range"),
		"mini nuke range can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("range", 0.0))
			> CrawlerRules.MINI_NUKE_RANGE,
		"range upgrades detonate farther out")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "knockback"),
		"mini nuke knockback can be upgraded")
	_expect(float(_player.crawler_kit.stats_for(card).get("knockback", 0.0))
			> CrawlerRules.MINI_NUKE_KNOCKBACK,
		"knockback upgrades throw farther")
	_expect(_player.crawler_kit.upgrade_card(card.uid, "slots"),
		"mini nuke slots can be upgraded")
	_expect(card.slot_count == CrawlerRules.MINI_NUKE_SLOTS + 1,
		"slot upgrades add a modifier seat")
	_expect(_player.crawler_kit.shop_grant("bubble"),
		"a bubble can be granted for mini nuke")
	var bubble: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "bubble":
			bubble = owned
			break
	_expect(bubble != null, "the granted card is bubble")
	if bubble == null:
		return
	var bag := _player.crawler_kit.inventory.find(bubble.token())
	_expect(bag >= 0, "bubble landed in the bag")
	var rack := _player.crawler_kit.mod_rack(1)
	_expect(rack != null, "mini nuke exposes a mod rack")
	ItemContainer.transfer(_player.crawler_kit.inventory, bag, rack, 0)
	_expect(card.filled_modifier_ids().has("bubble"),
		"bubble seats on mini nuke")
	_expect(_player.crawler_kit.upgrade_card(bubble.uid, "duration"),
		"bubble linger can be upgraded on mini nuke")
	var recipes := CrawlerBubbles.recipes_for_player(_player, "mini_nuke")
	_expect(not recipes.is_empty(), "mini nuke with bubble has a recipe")
	_expect(float(recipes[0].get("linger", 0.0)) > CrawlerRules.BUBBLE_LINGER,
		"linger upgrades stay on mini nuke's blast bubbles")
	_expect(CrawlerCatalog.description_of("bubble", "mini_nuke").contains("blast"),
		"seated bubble names the blast, not a trail")
	var blast := CrawlerBubbles.emit_blast(
		_player, "mini_nuke", Vector3(0.0, 2.0, 0.0), 8.0)
	_expect(blast.size() >= CrawlerRules.BUBBLE_BLAST_COUNT,
		"mini nuke blooms lingering bubbles through the blast")
	var trail := CrawlerBubbles.emit_trail(
		_player, "mini_nuke", Vector3(0.0, 2.0, 4.0), Vector3.FORWARD)
	_expect(not trail.is_empty(),
		"trail emit still builds orbs if asked, but the orb skips that path")
	for orb: CrawlerBubble in blast:
		if is_instance_valid(orb):
			orb.queue_free()
	for orb: CrawlerBubble in trail:
		if is_instance_valid(orb):
			orb.queue_free()
	_expect(_player.crawler_kit.shop_grant("big"),
		"a big can be granted for mini nuke")
	var big: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "big":
			big = owned
			break
	_expect(big != null, "the granted card is big")
	if big == null:
		return
	_player.crawler_kit.inventory.set_item(0, big.token())
	rack = _player.crawler_kit.mod_rack(1)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 1)
	_expect(card.filled_modifier_ids().has("big"), "big seats on mini nuke")
	_expect(float(_player.crawler_kit.stats_for(card).get("radius", 0.0))
			> float(grown.get("radius", 0.0)),
		"seated big widens the mini nuke blast")
	_expect(_player.crawler_kit.shop_grant("clip"),
		"a clip can be granted for mini nuke")
	var clip: CrawlerCard = null
	for owned: CrawlerCard in _player.crawler_kit.owned_cards():
		if owned.id == "clip":
			clip = owned
			break
	_expect(clip != null, "the granted card is clip")
	if clip == null:
		return
	_player.crawler_kit.inventory.set_item(0, clip.token())
	rack = _player.crawler_kit.mod_rack(1)
	ItemContainer.transfer(_player.crawler_kit.inventory, 0, rack, 2)
	_expect(card.filled_modifier_ids().has("clip"), "clip seats on mini nuke")
	_expect(_player.crawler_kit.ammo_max(card) == CrawlerRules.MINI_NUKE_AMMO * 2,
		"clip doubles mini nuke shots")


func _check_shared_ability_upgrades() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var first := _player.crawler_kit.equipped_card(0)
	_expect(first != null and first.id == "laser_eyes",
		"shared upgrade check starts from starter laser eyes")
	_expect(_player.crawler_kit.shop_grant("laser_eyes"),
		"the stall sells another laser eyes")
	var second := _player.crawler_kit.equipped_card(1)
	_expect(second != null and second.id == "laser_eyes" and second.uid != first.uid,
		"a second laser eyes is its own card")
	_expect(_player.crawler_kit.upgrade_card(first.uid, "range"),
		"upgrading one laser eyes is allowed")
	_expect(_player.crawler_kit.upgrade_rank_for(first, "range")
			== _player.crawler_kit.upgrade_rank_for(second, "range"),
		"both laser eyes share the range rank")
	_expect(is_equal_approx(
			float(_player.crawler_kit.stats_for(first).get("range", 0.0)),
			float(_player.crawler_kit.stats_for(second).get("range", 0.0))),
		"both laser eyes resolve the same range")
	_expect(_player.crawler_kit.upgrade_card(second.uid, "slots"),
		"upgrading slots on the other copy is allowed")
	_expect(first.slot_count == second.slot_count
			and first.slot_count == CrawlerRules.LASER_SLOTS + 1,
		"slot upgrades apply to every copy")
	_expect(_player.crawler_kit.shop_rank_for(first)
			== _player.crawler_kit.shop_rank_for(second),
		"copies share the next upgrade price")
	_expect(_player.crawler_kit.shop_grant("starfire"),
		"the stall sells starfire")
	_expect(_player.crawler_kit.equipped_card(2) != null
			and _player.crawler_kit.equipped_card(2).id == "starfire",
		"bought starfire seats on an empty hotbar slot")


func _check_hero_page() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var eyes_token := _player.crawler_kit.equipped_card(0).token()
	var page := CrawlerHeroPage.new()
	page.configure(_player)
	add_child(page)
	_expect(page.find_child("CrawlerAbilityRows", true, false) != null,
		"hero page builds three ability rows")
	var eyes := page.find_child("CrawlerAbilityTile_0", true, false) as CrawlerAbilityTile
	var spare := page.find_child("CrawlerAbilityTile_1", true, false) as CrawlerAbilityTile
	_expect(eyes != null, "hero page builds a laser eyes ability tile")
	_expect(spare != null, "hero page keeps the empty hotbar rows")
	_expect(eyes.find_child("CrawlerEquip_0", true, false) == null,
		"ability portrait is not an inventory slot")
	_expect(eyes.mod_slots().size() == 3, "laser eyes tile shows three modifier slots")
	_expect(not eyes.mod_slots()[0].draggable
			and not eyes.mod_slots()[0].accepts_drops,
		"the field locks ability mod slots")
	var empty := page.find_child("CrawlerAbilityTile_2", true, false) as CrawlerAbilityTile
	_expect(empty != null and empty.visible,
		"empty ability slot keeps its tile")
	var empty_title := empty.find_child("CrawlerAbilityTitle", true, false) as Label
	_expect(empty.token().is_empty(), "third slot starts empty")
	_expect(empty_title != null and empty_title.text == "EMPTY",
		"empty ability row reads as a reserved space")
	_expect(page.find_child("CrawlerInventorySlots", true, false) != null,
		"hero page builds the inventory grid")
	var bag_scroll := page.find_child("CrawlerInventoryScroll", true, false) as ScrollContainer
	_expect(bag_scroll != null, "mod tiles sit in a scroll")
	_expect(bag_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"the bag scrolls instead of growing the page")
	var bag_grid := page.find_child("CrawlerInventorySlots", true, false)
	_expect(bag_grid != null and bag_grid.get_parent() == bag_scroll,
		"the inventory grid is the scroll child")
	_expect(page.find_child("CrawlerBag_21", true, false) != null,
		"inventory is two rows of eleven")
	_expect(page.find_child("CrawlerBag_22", true, false) == null,
		"inventory does not keep a third row")
	var clear := eyes.find_child("CrawlerClear", true, false) as Button
	_expect(clear != null, "ability tiles host their own clear button")
	_expect(clear.get_parent() != eyes,
		"clear button is not a PanelContainer child")
	var portrait := eyes.find_child("CrawlerAbilityIcon", true, false) as TextureRect
	var title := eyes.find_child("CrawlerAbilityTitle", true, false) as Label
	_expect(portrait != null and portrait.visible, "laser eyes portrait stays visible")
	_expect(title != null and title.text.contains("LASER"),
		"laser eyes title stays on the card")
	var bag_one := page.find_child("CrawlerBag_1", true, false) as RedItemSlot
	_expect(bag_one != null and bag_one.item_id().is_empty(),
		"starter bag does not seat laser eyes")
	var body := page.find_child("CrawlerDescriptionBody", true, false) as Label
	_expect(body != null, "hero page has a description box")
	eyes.picked.emit(eyes)
	if not body.text.to_upper().contains("BEAM"):
		page.select_token(eyes_token)
	_expect(body.text.to_upper().contains("BEAM"),
		"clicking an ability fills the description")
	var type_row := page.find_child("CrawlerDescriptionTypes", true, false) as Control
	var beam_mark := type_row.find_child("TypeMark_beam", true, false) as TextureRect \
		if type_row != null else null
	_expect(beam_mark != null and beam_mark.visible
			and beam_mark.texture == CrawlerCatalog.type_icon("beam"),
		"selected laser eyes show the beam type icon")
	_expect(body.text.contains("TYPE  //  BEAM"),
		"selected laser eyes name the beam type")
	var shown := body.text.to_upper()
	for label: String in ["DAMAGE", "COOLDOWN", "DURATION", "RANGE", "SIZE",
			"KNOCKBACK", "SLOTS"]:
		_expect(shown.contains(label),
			"selected laser eyes lists %s" % label.to_lower())
	_player.crawler_kit.grant(CrawlerCatalog.make_ability("starfire").to_dict())
	page.refresh()
	var star_tile := page.find_child("CrawlerAbilityTile_1", true, false) as CrawlerAbilityTile
	_expect(star_tile != null and star_tile.card() != null
			and star_tile.card().id == "starfire",
		"hero page shows seated starfire")
	if star_tile != null:
		page.select_token(star_tile.token())
	var star_shown := body.text.to_upper()
	for label: String in ["DAMAGE", "COOLDOWN", "SIZE", "RANGE", "KNOCKBACK",
			"SLOTS"]:
		_expect(star_shown.contains(label),
			"selected starfire lists %s" % label.to_lower())
	_expect(not star_shown.contains("PROJECTILE RADIUS"),
		"starfire folds disk and burst size into Size")
	_player.crawler_kit.grant(CrawlerCatalog.make_ability("meteor_punch").to_dict())
	page.refresh()
	var meteor_tile := page.find_child("CrawlerAbilityTile_2", true, false) as CrawlerAbilityTile
	_expect(meteor_tile != null and meteor_tile.card() != null
			and meteor_tile.card().id == "meteor_punch",
		"hero page shows seated meteor punch")
	if meteor_tile != null:
		page.select_token(meteor_tile.token())
	var meteor_shown := body.text.to_upper()
	for label: String in ["DAMAGE", "COOLDOWN", "SIZE", "RANGE", "KNOCKBACK",
			"SLOTS"]:
		_expect(meteor_shown.contains(label),
			"selected meteor punch lists %s" % label.to_lower())
	_expect(not shown.contains("(+"),
		"starter laser eyes list the base numbers")
	var eyes_card := _player.crawler_kit.equipped_card(0)
	_expect(eyes_card != null and _player.crawler_kit.upgrade_card(eyes_card.uid, "range"),
		"hero page can upgrade laser range")
	page.select_token(eyes_token)
	_expect(body.text.contains("(+"),
		"upgraded laser eyes show the boost beside the base")
	var stats_toggle := page.find_child("StatsToggle", true, false) as Button
	var stats_frame := page.find_child("StatsFrame", true, false) as Control
	_expect(stats_toggle != null and stats_frame != null
			and not stats_frame.visible,
		"hero stats start hidden")
	stats_toggle.pressed.emit()
	_expect(stats_frame.visible, "stats button opens the live readout")
	_expect(page.find_child("StatsScroll", true, false) != null,
		"the stats overlay scrolls so every row stays reachable")
	for stat_id: String in CrawlerProgress.STAT_ORDER:
		var row := page.find_child("Stat_%s" % stat_id, true, false) as Control
		var value := page.find_child("Stat_%s_Value" % stat_id, true, false) as Label
		_expect(row != null and row.visible and value != null
				and not value.text.is_empty(),
			"stats button lists live %s" % stat_id)
	var health_value := page.find_child("Stat_health_Value", true, false) as Label
	_expect(health_value != null and not health_value.text.contains("("),
		"base player health has no boost yet")
	_player.crawler_progress.unspent = 1
	_player.spend_crawler_stat(CrawlerProgress.STAT_HEALTH)
	page.refresh()
	health_value = page.find_child("Stat_health_Value", true, false) as Label
	_expect(health_value != null and health_value.text.contains("(+"),
		"boosted player health shows the gain in parentheses")
	CrawlerMeta.begin_test({"ranks": {"health": 1}})
	page.refresh()
	health_value = page.find_child("Stat_health_Value", true, false) as Label
	_expect(health_value != null and health_value.text.contains("(+"),
		"homescreen gem ranks join in-run health in parentheses")
	CrawlerMeta.begin_test()
	_player.award_crawler_kill(1, "", Vector3.ZERO)
	_expect(CrawlerMeta.gems() == CrawlerMeta.kill_gems(1),
		"killing a crawler mob grants persistent gems")
	var bag := page.find_child("CrawlerBag_0", true, false) as RedItemSlot
	_expect(bag != null and bag.item_id().is_empty(), "starter bag starts empty")
	var drop_calls: Array = []
	page.drop_requested.connect(func(source: String, index: int, token: String) -> void:
		drop_calls.append({"source": source, "index": index, "token": token})
	)
	eyes.clear_requested.emit(0)
	_expect(drop_calls.size() == 1, "X asks the world for a dropped tile")
	_expect(str(drop_calls[0].get("source", "")) == CrawlerKit.SOURCE_EQUIP,
		"X drops the equipped card")
	_expect(int(drop_calls[0].get("index", -1)) == 0, "X drops the pressed row")
	_expect(str(drop_calls[0].get("token", "")) == eyes_token,
		"X drops the card that was on the tile")
	_expect(_player.crawler_kit.equipped_card(0) != null
			and _player.crawler_kit.equipped_card(0).id == "laser_eyes",
		"X does not pocket the ability into the bag")
	_expect(_player.crawler_kit.inventory.find(eyes_token) < 0,
		"bag stays free of the dropped ability")
	_expect(_player.crawler_kit.shop_grant("wobble"),
		"hero page can hold a wobble")
	page.refresh()
	var wobble_card: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "wobble":
			wobble_card = card
			break
	_expect(wobble_card != null, "wobble lands in the kit")
	if wobble_card != null:
		page.select_token(wobble_card.token())
	_expect(page.held_modifier_id() == "wobble",
		"selecting wobble counts as holding a mod")
	_expect(body.text.contains("FITS  //  BEAM")
			and not body.text.contains("FITS  //  LASER"),
		"wobble description lists the beam type, not every beam ability")
	var wobble_types := page.find_child("CrawlerDescriptionTypes", true, false) as Control
	var wobble_beam := wobble_types.find_child("TypeMark_beam", true, false) as TextureRect \
		if wobble_types != null else null
	_expect(wobble_beam != null and wobble_beam.visible
			and wobble_beam.texture == CrawlerCatalog.type_icon("beam")
			and wobble_types.get_child_count() == 1,
		"selected wobble shows only the beam type icon")
	var eyes_reject := eyes.find_child("CrawlerFitReject", true, false) as Label
	var star_reject := star_tile.find_child("CrawlerFitReject", true, false) as Label
	var meteor_reject := meteor_tile.find_child("CrawlerFitReject", true, false) as Label
	_expect(eyes_reject != null and not eyes_reject.visible
			and not eyes.rejects_held_mod(),
		"wobble fits laser eyes so that row stays clear")
	_expect(star_reject != null and star_reject.visible
			and star_tile.rejects_held_mod(),
		"holding wobble marks starfire with an X")
	_expect(meteor_reject != null and meteor_reject.visible
			and meteor_tile.rejects_held_mod(),
		"holding wobble marks meteor punch with an X")
	_expect(not eyes.mod_slots().is_empty() and not eyes.mod_slots()[0].blocked,
		"laser eyes mod slots stay open for wobble")
	_expect(not star_tile.mod_slots().is_empty() and star_tile.mod_slots()[0].blocked,
		"starfire mod slots show X marks for wobble")
	_expect(_player.crawler_kit.shop_grant("big"), "hero page can hold a big")
	page.refresh()
	var big_card: CrawlerCard = null
	for card: CrawlerCard in _player.crawler_kit.owned_cards():
		if card.id == "big":
			big_card = card
			break
	if big_card != null:
		page.select_token(big_card.token())
	_expect(page.held_modifier_id() == "big"
			and not star_tile.rejects_held_mod()
			and not meteor_tile.rejects_held_mod(),
		"holding a generic mod leaves every seated ability open")
	page.select_token(eyes_token)
	_expect(page.held_modifier_id().is_empty()
			and not star_tile.rejects_held_mod()
			and eyes_reject != null and not eyes_reject.visible,
		"X marks hide when the held card is an ability")
	page.queue_free()
	var dropped := DroppedCrawlerCard.new()
	dropped.configure(1, {"id": "laser_eyes", "mods": []})
	add_child(dropped)
	_expect(dropped.find_child("CardVisual", true, false) != null,
		"dropped ability becomes a world tile")
	dropped.global_position = Vector3(0.0, 3.2, 0.0)
	dropped.begin_settle_to(Vector3(0.0, 0.3, 0.0))
	var start_y := dropped.global_position.y
	dropped._process(0.35)
	_expect(dropped.global_position.y < start_y - 0.4,
		"dropped tiles fall toward the ground")
	dropped._process(1.0)
	_expect(is_equal_approx(dropped.global_position.y, 0.3),
		"dropped tiles settle on the ground")
	dropped.queue_free()
	var hat := DroppedCrawlerHat.new()
	hat.configure(2, CrawlerProgress.HAT_MISSILE)
	add_child(hat)
	_expect(hat.find_child("HatVisual", true, false) != null
			and hat.find_child("HatGlow", true, false) != null
			and hat.find_child("HatLamp", true, false) != null,
		"dropped hats show a glowing spinning model")
	hat.queue_free()


func _check_sandbox_cheats() -> void:
	var saved_mode := str(NetworkManager.session_options.get("mode", "crawler"))
	NetworkManager.session_options["mode"] = "sandbox"
	CrawlerRules.apply_sandbox_defaults()
	_player._apply_crawler_limits()
	_expect(CrawlerRules.active() and CrawlerRules.sandbox(),
		"sandbox hosts the same crawler rules")
	_expect(CrawlerRules.sandbox_invincible() and CrawlerRules.sandbox_fast()
			and not CrawlerRules.sandbox_no_mobs()
			and not CrawlerRules.sandbox_infinite_gold(),
		"sandbox starts invincible and fast")
	_expect(CrawlerProgress.ability_stock().has("grapple")
			and CrawlerProgress.ability_stock().has("lasso")
			and CrawlerProgress.ability_stock().has("laser_eyes")
			and CrawlerProgress.shop_stock().has("wobble"),
		"sandbox store keeps every catalog ability and mod")
	_player._waypoints_wanted = true
	_player._apply_tilde_overlay()
	_expect(_player._coordinates_wanted,
		"sandbox tilde shows patches and names")
	var extra := Landmark.new()
	extra.title = "Vacationer's Landing"
	extra.waypoint = true
	add_child(extra)
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	if layer != null:
		layer._process(0.016)
		_expect(layer.drawn(0.0).has("Vacationer's Landing"),
			"sandbox tilde names every landmark")
	extra.queue_free()
	_player._waypoints_wanted = false
	_player._apply_tilde_overlay()
	var authored_accel := _player._authored_flight_accel
	var dex := _player.crawler_progress.dex_scale() \
		if _player.crawler_progress != null else 1.0
	_expect(_player.fly_speed > CrawlerRules.FLY_SPEED
			and _player.flight_accel > authored_accel * dex + 0.01
			and _player.can_fly(),
		"sandbox starts with full flight, faster acceleration, and infinite fuel")
	_player.set_sandbox_cheat(CrawlerRules.CHEAT_INVINCIBLE, false)
	_expect(not CrawlerRules.sandbox_invincible(),
		"the Tab menu can turn invincible off")
	var menu := GameMenu.new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	var actions := menu.find_child("SessionActions", true, false) as Control
	var cheats := menu.find_child("SandboxCheats", true, false) as Control
	var hero := menu.find_child("CrawlerAbilityRows", true, false)
	var invincible_key := menu.find_child("SandboxInvincible", true, false) as Button
	var fast_key := menu.find_child("SandboxFast", true, false) as Button
	_expect(hero != null, "sandbox Tab Hero is the crawler hero page")
	_expect(cheats != null
			and menu.find_child("SandboxMobs", true, false) != null
			and invincible_key != null
			and fast_key != null
			and menu.find_child("SandboxGold", true, false) != null,
		"sandbox Tab menu adds four cheat keys under the session actions")
	_expect(invincible_key != null and not invincible_key.button_pressed
			and fast_key != null and fast_key.button_pressed,
		"invincible can be off while fast stays on")
	_expect(actions != null and cheats != null
			and cheats.get_global_rect().position.y
				>= actions.get_global_rect().end.y - 2.0,
		"sandbox cheat keys sit under the respawn circle buttons")
	var before_fly := _player.fly_speed
	_player.set_sandbox_cheat(CrawlerRules.CHEAT_FAST, false)
	_expect(not CrawlerRules.sandbox_fast()
			and is_equal_approx(_player.fly_speed, CrawlerRules.FLY_SPEED)
			and is_equal_approx(_player.flight_accel, authored_accel * dex),
		"turning fast off restores crawler flight")
	_player.set_sandbox_cheat(CrawlerRules.CHEAT_FAST, true)
	_expect(CrawlerRules.sandbox_fast()
			and _player.fly_speed > CrawlerRules.FLY_SPEED
			and _player.fly_speed >= before_fly
			and _player.flight_accel > authored_accel * dex + 0.01,
		"fast restores full flight speed and higher acceleration")
	_player._flight_fuel = 0.0
	_expect(_player.can_fly(), "fast keeps flight infinite")
	_player.set_sandbox_cheat(CrawlerRules.CHEAT_INVINCIBLE, true)
	var poke := DamageHit.impact(_player.global_position, 1.2, 40.0)
	poke.faction = DamageHit.Faction.ENEMY
	_expect(is_zero_approx(_player.apply_damage(poke)),
		"invincible ignores incoming hits")
	var saved_gold := _player.crawler_progress.gold
	_player.set_sandbox_cheat(CrawlerRules.CHEAT_GOLD, true)
	_expect(_player.crawler_progress.has_gold(CrawlerRules.SANDBOX_GOLD),
		"infinite gold can pay any shop price")
	var held := _player.crawler_progress.gold
	_expect(_player.crawler_progress.spend_gold(80)
			and _player.crawler_progress.gold == held,
		"infinite gold does not empty the purse")
	_player.set_sandbox_cheat(CrawlerRules.CHEAT_MOBS, true)
	_expect(CrawlerRules.sandbox_no_mobs(), "no-mobs turns the field packs off")
	menu.queue_free()
	await get_tree().process_frame
	CrawlerRules.clear_sandbox_cheats()
	NetworkManager.session_options["mode"] = saved_mode
	_expect(not CrawlerProgress.ability_stock().has("grapple")
			and not CrawlerProgress.ability_stock().has("lasso"),
		"crawler store still hides unused abilities")
	_player.crawler_progress.gold = saved_gold
	_player.crawler_progress.remember()
	_player._apply_crawler_limits()
	_player._flight_fuel = 1.0


func _check_teammate_waypoint() -> void:
	var saved_solo := NetworkManager.is_single_player
	var mate := PLAYER.instantiate() as OnlinePlayer
	mate.peer_id = 2
	mate.display_name = "Scout"
	mate.defer_camera = true
	add_child(mate)
	mate.set_process(false)
	mate.set_physics_process(false)
	mate.global_position = _player.global_position + Vector3(8.0, 0.0, 0.0)
	await get_tree().process_frame
	_player._waypoints_wanted = true
	_player._apply_tilde_overlay()
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	_expect(layer != null, "tilde has a waypoint layer")
	NetworkManager.is_single_player = true
	if layer != null:
		layer._process(0.016)
		_expect(not layer.drawn(0.0).has("Scout"),
			"solo tilde does not mark another player")
	NetworkManager.is_single_player = false
	if layer != null:
		layer._process(0.016)
		_expect(layer.drawn(0.0).has("Scout"),
			"coop tilde names a teammate")
		_expect(layer.tint_of("Scout").is_equal_approx(WaypointLayer.MATE_TINT),
			"the teammate waypoint is blue")
	NetworkManager.is_single_player = saved_solo
	_player._waypoints_wanted = false
	_player._apply_tilde_overlay()
	mate.queue_free()
	await get_tree().process_frame


func _check_city_shop_hours() -> void:
	var saved_mode := str(NetworkManager.session_options.get("mode", "crawler"))
	NetworkManager.session_options["mode"] = "crawler"
	var progress := CrawlerProgress.new()
	progress.statue_seed = 91031
	var first := progress.open_shops_for("city")
	_expect(first.has("inventory") and first.has("reststop") and first.has("duals"),
		"every city keeps reststop, inventory, and duals")
	_expect(first.has("hats") and first.has("abilities"),
		"the first city keeps the hat and ability stalls")
	_expect(progress.shop_extra_count("city") >= 3
			and progress.shop_extra_count("city") <= 4,
		"the first city opens 3-4 extra stalls")
	_expect(progress.open_shops_for("city") == first,
		"the same run keeps the same first-city stalls")
	var later := progress.open_shops_for("22")
	_expect(later.has("inventory") and later.has("reststop") and later.has("duals"),
		"later cities still keep reststop, inventory, and duals")
	_expect(progress.shop_extra_count("22") >= 3
			and progress.shop_extra_count("22") <= 4,
		"later cities open 3-4 extra stalls")
	progress.statue_seed = 77441
	_expect(progress.open_shops_for("city").has("hats")
			and progress.open_shops_for("city").has("abilities"),
		"a new run still forces first-city hat and ability stalls")
	NetworkManager.session_options["mode"] = "sandbox"
	_expect(progress.open_shops_for("city").size() == CrawlerProgress.SHOP_IDS.size(),
		"sandbox keeps every stall open")
	NetworkManager.session_options["mode"] = "crawler"
	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	_player.global_position = Vector3.ZERO
	_player.crawler_progress.statue_seed = 91031
	var menu := CrawlerFieldMenu.new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	var inv_stamp := menu.find_child("StoreTabClosed_inventory", true, false) as Label
	var rest_stamp := menu.find_child("StoreTabClosed_reststop", true, false) as Label
	var hat_stamp := menu.find_child("StoreTabClosed_hats", true, false) as Label
	var ability_stamp := menu.find_child("StoreTabClosed_abilities", true, false) as Label
	_expect(inv_stamp != null and not inv_stamp.visible,
		"inventory never reads closed")
	_expect(rest_stamp != null and not rest_stamp.visible,
		"reststop never reads closed")
	_expect(hat_stamp != null and not hat_stamp.visible,
		"the first city hat stall stays open")
	_expect(ability_stamp != null and not ability_stamp.visible,
		"the first city ability stall stays open")
	var closed_count := 0
	for id: String in CrawlerProgress.SHOP_IDS:
		var stamp := menu.find_child("StoreTabClosed_%s" % id, true, false) as Label
		if stamp != null and stamp.visible:
			closed_count += 1
	_expect(closed_count >= 6 and closed_count <= 7,
		"closed first-city stalls show CLOSED")
	var hat_icon := menu.find_child("StoreTabIcon_hats", true, false) as TextureRect
	var inv_icon := menu.find_child("StoreTabIcon_inventory", true, false) as TextureRect
	var rest_icon := menu.find_child("StoreTabIcon_reststop", true, false) as TextureRect
	var locker_icon := menu.find_child("StoreTabIcon_locker", true, false) as TextureRect
	_expect(hat_icon != null and hat_icon.visible and hat_icon.texture != null,
		"open store tabs show a stall icon")
	_expect(inv_icon != null and inv_icon.visible and inv_icon.texture != null,
		"inventory keeps a stall icon")
	_expect(rest_icon != null and not rest_icon.visible,
		"the rest stop tab has no stall icon")
	_expect(locker_icon != null and not locker_icon.visible,
		"the locker tab has no stall icon")
	menu.queue_free()
	ring.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options["mode"] = saved_mode


func _check_later_cities() -> void:
	var first := CrawlerCityRing.new()
	first.configure(-1, Transform3D.IDENTITY)
	add_child(first)
	var crescent := CrawlerCityRing.new()
	crescent.configure(
		-1,
		Transform3D(Basis(), Vector3(220.0, 0.0, 0.0)),
		CrawlerRules.CITY_CRESCENT_SITE_ID,
		CrawlerRules.CITY_CRESCENT_TITLE,
		"",
		CrawlerRules.CITY_CRESCENT_SITE_ID
	)
	add_child(crescent)
	var lee := CrawlerCityRing.new()
	lee.configure(
		-1,
		Transform3D(Basis(), Vector3(-220.0, 0.0, 0.0)),
		CrawlerRules.CITY_LEE_SITE_ID,
		CrawlerRules.CITY_LEE_TITLE,
		"",
		CrawlerRules.CITY_LEE_SITE_ID
	)
	add_child(lee)
	await get_tree().process_frame
	var first_mark := first.get_node_or_null("CrawlerWaypoint") as CrawlerSite
	var crescent_mark := crescent.get_node_or_null("CrawlerWaypoint") as CrawlerSite
	var lee_mark := lee.get_node_or_null("CrawlerWaypoint") as CrawlerSite
	_expect(first_mark != null and first_mark.waypoint
			and first_mark.title == CrawlerRules.CITY_SITE_TITLE,
		"Neon Fjord still starts on tilde")
	_expect(crescent_mark != null and not crescent_mark.waypoint
			and crescent_mark.title == CrawlerRules.CITY_CRESCENT_TITLE,
		"Crescent Market stays off tilde at the start")
	_expect(lee_mark != null and not lee_mark.waypoint
			and lee_mark.title == CrawlerRules.CITY_LEE_TITLE,
		"Lee Reach stays off tilde at the start")
	var signed := _player.crawler_progress.signed_shops_for("city")
	_expect(signed.has("inventory") and signed.has("hats")
			and not signed.has("reststop") and not signed.has("locker"),
		"city waypoint signs skip the rest stop and lockers")
	_player._waypoints_wanted = true
	_player._apply_tilde_overlay()
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	if layer != null:
		layer._process(0.016)
		var icons := layer.shop_icon_ids(first_mark)
		_expect(icons.has("inventory") and icons.has("hats")
				and not icons.has("reststop") and not icons.has("locker"),
			"the first-city waypoint lists open store icons")
	_player._waypoints_wanted = false
	_player._apply_tilde_overlay()
	var ledger := CrawlerProgress.new()
	ledger.unlock_site(CrawlerRules.CITY_SITE_ID)
	CrawlerSites.apply_progress(ledger, get_tree())
	_expect(crescent_mark.waypoint and lee_mark.waypoint,
		"a saved first-city visit restores the later maps")
	crescent_mark.waypoint = false
	lee_mark.waypoint = false
	CrawlerSites.schedule_later_city_unlock(_player, 0.05)
	_expect(not crescent_mark.waypoint and not lee_mark.waypoint,
		"later cities wait out the city-enter delay")
	await get_tree().create_timer(0.2).timeout
	_expect(crescent_mark.waypoint and lee_mark.waypoint,
		"entering Neon Fjord lights the later towns after a short wait")
	first.queue_free()
	crescent.queue_free()
	lee.queue_free()
	await get_tree().process_frame


func _check_game_save() -> void:
	GameSave.clear_file()
	_expect(not GameSave.has_save(), "a missing file is not a save")
	_player.crawler_progress.gold = 81
	_player.crawler_progress.unlock_site(CrawlerRules.CITY_SITE_ID)
	_player.crawler_progress.remember()
	_player.crawler_kit.remember()
	var xf := Transform3D(Basis(), Vector3(12.0, 4.0, -9.0))
	_player.global_transform = xf
	_player.set_look_pitch(-0.4)
	var payload := {
		"version": GameSave.VERSION,
		"saved_at": 1,
		"session": {"mode": "crawler"},
		"progress": _player.crawler_progress.to_dict(),
		"kit": _player.crawler_kit.to_dict(),
		"look": {},
		"player": {
			"transform": _player.global_transform,
			"pitch": _player.look_pitch(),
			"combat": _player.combat_snapshot(),
		},
		"world": {},
	}
	_expect(GameSave.write_payload(payload), "a run can be written to disk")
	_expect(GameSave.has_save(), "the save file exists after a write")
	_player.crawler_progress.gold = 0
	var loaded := GameSave.read()
	var progress_raw: Variant = loaded.get("progress", {})
	_expect(progress_raw is Dictionary
			and int((progress_raw as Dictionary).get("gold", 0)) == 81,
		"the save keeps gold")
	_expect(GameSave.player_transform(loaded).origin.distance_to(xf.origin) < 0.05,
		"the save keeps the player's place")
	_expect(is_equal_approx(float((loaded.get("player", {}) as Dictionary)
			.get("pitch", 0.0)), -0.4),
		"the save keeps the look pitch")
	if progress_raw is Dictionary:
		_player.crawler_progress.from_dict(progress_raw)
	_expect(_player.crawler_progress.gold == 81, "loading restores gold")
	_expect(_player.crawler_progress.site_unlocked(CrawlerRules.CITY_SITE_ID),
		"loading restores discovered sites")
	var panel := SettingsPanel.new()
	panel.configure(true)
	add_child(panel)
	await get_tree().process_frame
	_expect(panel.find_child("SettingsSaveGame", true, false) != null,
		"settings has a SAVE GAME action")
	_expect(panel.find_child("SettingsLoadGame", true, false) != null,
		"settings has a LOAD GAME action")
	panel.queue_free()
	GameSave.clear_file()
	await get_tree().process_frame


func _check_city_shop_stock() -> void:
	var saved_mode := str(NetworkManager.session_options.get("mode", "crawler"))
	NetworkManager.session_options["mode"] = "crawler"
	var scratch := CrawlerProgress.new()
	scratch.statue_seed = 4242
	scratch.gold = 999
	scratch.reroll_uses = 0
	scratch.ensure_shop_offers("stock")
	_expect(scratch.shop_slots("hats", "stock").size() == CrawlerProgress.SHOP_HAT_SLOTS,
		"the hat stall offers three slots")
	_expect(scratch.shop_slots("abilities", "stock").size()
			== CrawlerProgress.SHOP_ABILITY_SLOTS,
		"the ability stall offers one slot")
	_expect(scratch.shop_slots("mods", "stock").size() == CrawlerProgress.SHOP_MOD_SLOTS,
		"the mod stall offers three slots")
	var hats := scratch.shop_offer_ids("hats", "stock")
	var abilities := scratch.shop_offer_ids("abilities", "stock")
	var mods := scratch.shop_offer_ids("mods", "stock")
	_expect(hats.size() == CrawlerProgress.SHOP_HAT_SLOTS
			and _unique_count(hats) == hats.size(),
		"three distinct hats are in stock")
	_expect(abilities.size() == CrawlerProgress.SHOP_ABILITY_SLOTS,
		"one ability is in stock")
	_expect(mods.size() == CrawlerProgress.SHOP_MOD_SLOTS
			and _unique_count(mods) == mods.size(),
		"three distinct mods are in stock")
	var sold_hat := hats[0]
	scratch.mark_shop_sold("hats", sold_hat, "stock")
	_expect(not scratch.shop_has_unsold("hats", sold_hat, "stock"),
		"buying a hat empties that slot")
	var first_price := scratch.reroll_price()
	_expect(first_price == CrawlerProgress.REROLL_BASE,
		"store refresh starts at the level-up reroll price")
	var gold_before := scratch.gold
	_expect(scratch.refresh_shop_offers("hats", "stock"),
		"unsold hat slots can refresh")
	_expect(scratch.gold == gold_before - first_price,
		"refresh spends the same gold as a level-up reroll")
	_expect(scratch.reroll_price() == CrawlerProgress.REROLL_BASE * 2,
		"store refresh shares the level-up price ladder")
	_expect(not scratch.shop_has_unsold("hats", sold_hat, "stock"),
		"a sold hat slot stays empty after refresh")
	var sold_slot: Variant = scratch.shop_slots("hats", "stock")[0]
	_expect(sold_slot is Dictionary and bool((sold_slot as Dictionary).get("sold", false))
			and str((sold_slot as Dictionary).get("id", "")).is_empty(),
		"the sold hat slot is still marked sold")
	scratch.force_upgrade_picks(
		"stock", "starfire", PackedStringArray(["damage", "cooldown", "size"]))
	_expect(scratch.upgrade_in_stock("starfire", "damage", "stock")
			and scratch.upgrade_in_stock("starfire", "cooldown", "stock")
			and scratch.upgrade_in_stock("starfire", "size", "stock"),
		"chosen starfire upgrades stay in stock")
	_expect(not scratch.upgrade_in_stock("starfire", "range", "stock")
			and not scratch.upgrade_in_stock("starfire", "knockback", "stock")
			and not scratch.upgrade_in_stock("starfire", "slots", "stock"),
		"unpicked starfire upgrades are out of stock")
	NetworkManager.session_options["mode"] = "sandbox"
	_expect(not scratch.uses_limited_shop("stock"),
		"sandbox keeps the full stall")
	_expect(scratch.upgrade_in_stock("starfire", "range", "stock"),
		"sandbox keeps every upgrade in stock")
	NetworkManager.session_options["mode"] = "crawler"
	scratch.set_shops_unlimited(true)
	_expect(not scratch.uses_limited_shop("stock")
			and scratch.shop_has_unsold("hats", sold_hat, "stock")
			and scratch.upgrade_in_stock("starfire", "range", "stock"),
		"unlimited stores keep every hat and upgrade in stock")
	scratch.mark_shop_sold("hats", hats[1] if hats.size() > 1 else sold_hat, "stock")
	_expect(scratch.shop_has_unsold(
			"hats", hats[1] if hats.size() > 1 else sold_hat, "stock"),
		"unlimited stores do not empty a bought slot")
	var gold_before_grant := scratch.gold
	scratch.grant_gold(CrawlerProgress.REST_GOLD_GRANT)
	_expect(scratch.gold == gold_before_grant + CrawlerProgress.REST_GOLD_GRANT,
		"the reststop gold grant adds 10,000")
	var unlimited_restored := CrawlerProgress.new()
	unlimited_restored.from_dict(scratch.to_dict())
	_expect(unlimited_restored.shops_unlimited
			and unlimited_restored.gold == scratch.gold,
		"unlimited stores and the gold grant persist")
	scratch.set_shops_unlimited(false)
	scratch.force_shop_offers("alpha", "abilities", PackedStringArray(["starfire"]))
	scratch.force_shop_offers("beta", "abilities", PackedStringArray(["starfire"]))
	scratch.force_shop_offers("alpha", "hats", PackedStringArray([
		CrawlerProgress.HAT_ID, CrawlerProgress.HAT_WARD, CrawlerProgress.HAT_LUCK,
	]))
	scratch.force_shop_offers("beta", "hats", PackedStringArray([
		CrawlerProgress.HAT_ID, CrawlerProgress.HAT_WARD, CrawlerProgress.HAT_LUCK,
	]))
	scratch.force_shop_offers("alpha", "mods", PackedStringArray(["wobble", "big", "clip"]))
	scratch.force_shop_offers("beta", "mods", PackedStringArray(["wobble", "big", "clip"]))
	scratch.mark_shop_sold("abilities", "starfire", "alpha")
	scratch.mark_shop_sold("hats", CrawlerProgress.HAT_ID, "alpha")
	scratch.mark_shop_sold("mods", "wobble", "alpha")
	_expect(not scratch.shop_has_unsold("abilities", "starfire", "alpha")
			and scratch.shop_has_unsold("abilities", "starfire", "beta"),
		"selling an ability in one city leaves the same ability in another")
	_expect(not scratch.shop_has_unsold("hats", CrawlerProgress.HAT_ID, "alpha")
			and scratch.shop_has_unsold("hats", CrawlerProgress.HAT_ID, "beta"),
		"selling a hat in one city leaves the same hat in another")
	_expect(not scratch.shop_has_unsold("mods", "wobble", "alpha")
			and scratch.shop_has_unsold("mods", "wobble", "beta"),
		"selling a mod in one city leaves the same mod in another")
	scratch.force_upgrade_picks(
		"alpha", "starfire", PackedStringArray(["damage"]))
	scratch.force_upgrade_picks(
		"beta", "starfire", PackedStringArray(["damage", "range"]))
	_expect(not scratch.upgrade_in_stock("starfire", "range", "alpha")
			and scratch.upgrade_in_stock("starfire", "range", "beta"),
		"upgrade stock is rolled per city")
	scratch.ensure_shop_offers("gamma")
	_expect(scratch.shop_offer_ids("hats", "gamma").size()
			== CrawlerProgress.SHOP_HAT_SLOTS
			and scratch.shop_offer_ids("abilities", "gamma").size()
			== CrawlerProgress.SHOP_ABILITY_SLOTS
			and scratch.shop_offer_ids("mods", "gamma").size()
			== CrawlerProgress.SHOP_MOD_SLOTS,
		"a new city still rolls a full stall after another city sells out")
	_expect(scratch.cap_merge_free("alpha"), "the first mash in a city is free")
	scratch.mark_cap_merged("alpha")
	_expect(not scratch.cap_merge_free("alpha")
			and scratch.cap_merge_free("beta"),
		"mashing hats in one city leaves the next city free")
	scratch.set_shops_unlimited(true)
	_expect(scratch.cap_merge_free("alpha"),
		"infinite stores let you mash hats again")
	scratch.set_shops_unlimited(false)
	var fused_restored := CrawlerProgress.new()
	fused_restored.from_dict(scratch.to_dict())
	_expect(not fused_restored.cap_merge_free("alpha")
			and fused_restored.cap_merge_free("beta")
			and fused_restored.shop_has_unsold("abilities", "starfire", "beta")
			and not fused_restored.shop_has_unsold("abilities", "starfire", "alpha"),
		"per-city mash and stall stock persist")
	var progress := _player.crawler_progress
	progress.statue_seed = _first_city_seed_with_shops(
		progress, PackedStringArray(["cards", "upgrades"]))
	progress.gold = 9999
	progress.reroll_uses = 0
	progress.shop_stock_slots.clear()
	progress.shop_upgrade_picks.clear()
	progress.force_shop_offers("city", "hats", PackedStringArray([
		CrawlerProgress.HAT_ID, CrawlerProgress.HAT_WARD, CrawlerProgress.HAT_LUCK,
	]))
	progress.force_shop_offers("city", "abilities", PackedStringArray(["starfire"]))
	progress.force_shop_offers("city", "mods", PackedStringArray(["wobble", "big", "clip"]))
	progress.force_upgrade_picks(
		"city", "starfire", PackedStringArray(["damage", "cooldown", "size"]))
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_expect(_player.crawler_kit.shop_grant("starfire"),
		"starfire can sit for the upgrade stall")
	var star := _player.crawler_kit.equipped_card(1)
	_expect(star != null and star.id == "starfire", "starfire is seated for stock checks")
	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	_player.global_position = Vector3.ZERO
	var menu := CrawlerFieldMenu.new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	menu.set_tab(CrawlerFieldMenu.Tab.HATS)
	await get_tree().process_frame
	var refresh := menu.find_child("StoreRefresh_hats", true, false) as Button
	_expect(menu.find_child("HatTile_crawler_gale_hat", true, false) != null
			and menu.find_child("HatTile_crawler_ward_hat", true, false) != null
			and menu.find_child("HatTile_crawler_luck_hat", true, false) != null,
		"the hat stall shows the three rolled hats")
	_expect(menu.find_child("HatTile_crawler_kit_hat", true, false) == null,
		"hats that were not rolled stay off the floor")
	_expect(refresh != null and refresh.visible and refresh.text.contains("1"),
		"the hat stall offers a refresh at the first reroll price")
	_expect(_player.buy_crawler_hat(CrawlerProgress.HAT_ID),
		"an in-stock hat can still be bought")
	await get_tree().process_frame
	_expect(menu.find_child("HatTile_crawler_gale_hat", true, false) == null
			and menu.find_child("SoldSlot_hats_0", true, false) != null,
		"a sold hat slot is empty")
	var gold_after_hat := progress.gold
	refresh = menu.find_child("StoreRefresh_hats", true, false) as Button
	_expect(refresh != null, "sold hats still leave a refresh control")
	if refresh != null:
		refresh.pressed.emit()
	await get_tree().process_frame
	_expect(progress.gold == gold_after_hat - CrawlerProgress.REROLL_BASE,
		"refreshing the hat stall spends the shared reroll price")
	_expect(menu.find_child("SoldSlot_hats_0", true, false) != null,
		"refresh leaves the sold hat slot empty")
	menu.set_tab(CrawlerFieldMenu.Tab.ABILITIES)
	await get_tree().process_frame
	_expect(menu.find_child("AbilityTile_starfire", true, false) != null
			and menu.find_child("AbilityTile_laser_eyes", true, false) == null,
		"the ability stall shows only the rolled ability")
	_expect(menu.find_child("StoreRefresh_abilities", true, false) != null,
		"the ability stall can refresh")
	menu.set_tab(CrawlerFieldMenu.Tab.CARDS)
	await get_tree().process_frame
	_expect(menu.find_child("ModTile_wobble", true, false) != null
			and menu.find_child("ModTile_big", true, false) != null
			and menu.find_child("ModTile_clip", true, false) != null
			and menu.find_child("ModTile_bubble", true, false) == null,
		"the mod stall shows only the three rolled mods")
	_expect(menu.find_child("StoreRefresh_mods", true, false) != null,
		"the mod stall can refresh")
	_expect(progress.shop_open("upgrades", "city"),
		"the first-city seed keeps the upgrade stall open")
	if star != null:
		_expect(_player.upgrade_crawler_card(star.uid, "damage"),
			"an in-stock upgrade can still be bought")
		_expect(not _player.upgrade_crawler_card(star.uid, "range"),
			"an out-of-stock upgrade cannot be bought")
		_expect(_player.upgrade_crawler_card(star.uid, "damage"),
			"in-stock upgrades can be bought again toward their cap")
	menu.set_tab(CrawlerFieldMenu.Tab.UPGRADES)
	await get_tree().process_frame
	menu._fill_upgrades(progress.gold)
	var star_tile: CrawlerAbilityTile = null
	for index in 4:
		var tile := menu.find_child("CrawlerAbilityTile_%d" % index, true, false) \
			as CrawlerAbilityTile
		if tile == null or tile.card() == null or tile.card().id != "starfire":
			continue
		star_tile = tile
		break
	if star_tile != null:
		star_tile.picked.emit(star_tile)
	await get_tree().process_frame
	var damage := menu.find_child("UpgradeAct_damage", true, false) as Button
	var range_act := menu.find_child("UpgradeAct_range", true, false) as Button
	_expect(menu.find_child("UpgradeTile_damage", true, false) != null
			and menu.find_child("UpgradeTile_range", true, false) != null
			and menu.find_child("UpgradeTile_slots", true, false) != null,
		"out-of-stock upgrades stay listed")
	_expect(damage != null and damage.text != "OUT OF STOCK",
		"in-stock upgrades stay buyable")
	_expect(range_act != null and range_act.text == "OUT OF STOCK" and range_act.disabled,
		"unpicked upgrades read OUT OF STOCK")
	progress.reroll_uses = 0
	progress.remember()
	menu.queue_free()
	ring.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options["mode"] = saved_mode


func _check_cap_merge_once() -> void:
	var saved_mode := str(NetworkManager.session_options.get("mode", "crawler"))
	NetworkManager.session_options["mode"] = "crawler"
	var progress := _player.crawler_progress
	var held_hats := progress.owned_hats.duplicate()
	var held_worn := progress.worn_hat
	var held_gold := progress.gold
	var held_fused := progress.fused_hat_cities.duplicate()
	var held_seed := progress.statue_seed
	var held_unlimited := progress.shops_unlimited
	progress.set_shops_unlimited(false)
	progress.fused_hat_cities = PackedStringArray()
	progress.gold = 9999
	progress.statue_seed = _first_city_seed_with_shops(
		progress, PackedStringArray(["caps"]))
	progress.remember()
	var keep := progress.grant_hat(CrawlerProgress.HAT_ID)
	var other := progress.grant_hat(CrawlerProgress.HAT_WARD)
	var spare := progress.grant_hat(CrawlerProgress.HAT_LUCK)
	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	_player.global_position = Vector3.ZERO
	await get_tree().process_frame
	_expect(_player.merge_crawler_hats(keep, other),
		"Caps for Sale mashes the first pair in a city")
	_expect(not progress.cap_merge_free("city"),
		"that city is used after one mash")
	_expect(not _player.merge_crawler_hats(progress.worn_hat, spare),
		"the same city refuses a second mash")
	_expect(progress.owns_hat(spare),
		"the refused mash leaves the second pair intact")
	_expect(progress.cap_merge_free("city_crescent"),
		"another city can still mash hats")
	var menu := CrawlerFieldMenu.new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	menu.set_tab(CrawlerFieldMenu.Tab.CAPS)
	await get_tree().process_frame
	var used := menu.find_child("CapMergeUsed", true, false) as Button
	_expect(used != null and used.disabled and used.text == "USED",
		"Caps for Sale reads USED after the city mash")
	progress.set_shops_unlimited(true)
	menu._clear_list()
	menu._fill_caps_for_sale(progress, progress.gold)
	_expect(menu.find_child("CapMergeUsed", true, false) == null,
		"infinite stores hide the used mash stamp")
	_expect(_player.merge_crawler_hats(progress.worn_hat, spare),
		"infinite stores let you mash again in the same city")
	menu.queue_free()
	ring.queue_free()
	progress.set_shops_unlimited(held_unlimited)
	progress.fused_hat_cities = held_fused
	progress.owned_hats = held_hats
	progress.worn_hat = held_worn
	progress.gold = held_gold
	progress.statue_seed = held_seed
	progress.remember()
	await get_tree().process_frame
	NetworkManager.session_options["mode"] = saved_mode


func _first_city_seed_with_shops(
		progress: CrawlerProgress, shops: PackedStringArray) -> int:
	var held := progress.statue_seed
	var found := 1
	for seed in range(1, 8000):
		progress.statue_seed = seed
		var ok := true
		for shop_id: String in shops:
			if progress.shop_open(shop_id, "city"):
				continue
			ok = false
			break
		if ok:
			found = seed
			break
	progress.statue_seed = held
	return found


func _unique_count(ids: PackedStringArray) -> int:
	var seen: Dictionary = {}
	for id: String in ids:
		seen[id] = true
	return seen.size()


func _check_level_tiles() -> void:
	_check_level_offers()
	_player.crawler_progress.unspent = 1
	_player.crawler_progress.ranks[CrawlerProgress.STAT_HEALTH] = 0
	_player.crawler_progress.force_level_offers(_health_level_offers())
	var menu := CrawlerLevelMenu.new()
	menu.configure(_player)
	add_child(menu)
	await get_tree().process_frame
	var host := menu.find_child("SpendTiles", true, false) as GridContainer
	_expect(host != null and host.columns == 2
			and host.get_child_count() == CrawlerProgress.LEVEL_OFFER_COUNT,
		"spend window offers four tiles in a two-by-two")
	var tile := menu.find_child("SpendTile_health", true, false) as Control
	_expect(tile != null, "spend window uses tiles")
	_expect(tile != null and not (tile is Button),
		"spend choices are tiles, not theme buttons")
	_expect(tile != null and tile.mouse_filter == Control.MOUSE_FILTER_STOP,
		"spend tiles take the click")
	_expect(tile != null and tile.clip_contents,
		"spend tile copy stays inside the box")
	var rarity := menu.find_child("SpendRarity", true, false) as Label
	var boost := menu.find_child("SpendBoost", true, false) as Label
	var title := menu.find_child("SpendTitle", true, false) as Label
	var ink := CrawlerProgress.rarity_color(CrawlerProgress.RARITY_UNCOMMON)
	_expect(rarity != null and rarity.text.contains("UNCOMMON"),
		"each spend tile names its rarity")
	_expect(boost != null and boost.text.contains("HP"),
		"each spend tile shows the boost amount")
	_expect(title != null
			and title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
			and title.vertical_alignment == VERTICAL_ALIGNMENT_CENTER
			and title.get_theme_font_size(&"font_size") >= 28,
		"spend titles are large and centered in the tile")
	_expect(title != null and title.get_theme_color(&"font_color") == ink
			and boost.get_theme_color(&"font_color") == ink
			and rarity.get_theme_color(&"font_color") == ink,
		"spend copy uses the offer rarity color")
	await get_tree().process_frame
	_expect(title != null and CrtType.host_of(title) != null
			and CrtType.host_of(boost) != null
			and CrtType.host_of(rarity) != null,
		"spend copy wears the CRT type")
	var reroll := menu.find_child("RerollOffers", true, false) as Button
	_player.crawler_progress.gold = 0
	menu._refresh()
	_expect(reroll != null and reroll.disabled,
		"reroll stays shut without gold")
	_player.crawler_progress.gold = 1
	menu._refresh()
	_expect(reroll != null and not reroll.disabled
			and reroll.text.contains("1"),
		"the first reroll is listed at one gold")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	tile.gui_input.emit(click)
	_expect(_player.crawler_progress.rank_of(CrawlerProgress.STAT_HEALTH) == 0,
		"pressing a spend tile does not spend yet")
	menu._process(menu.HOLD_SECONDS)
	_expect(_player.crawler_progress.rank_of(CrawlerProgress.STAT_HEALTH) == 1,
		"holding a spend tile spends the point")
	if is_instance_valid(menu):
		menu.queue_free()


func _check_level_offers() -> void:
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_DEFENSE),
		"defense can appear on the level-up board")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_KNOCKBACK),
		"knockback can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_KNOCKBACK),
		"knockback is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_RANGE),
		"range can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_RANGE),
		"range is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_CAST),
		"cast can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_CAST),
		"cast is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_LUCK),
		"luck can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_LUCK),
		"luck is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_ELEMENTAL),
		"elemental can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_ELEMENTAL),
		"elemental is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_JUKE_DISTANCE),
		"juke distance can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_JUKE_DISTANCE),
		"juke distance is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_GOLD),
		"gold gain can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_GOLD),
		"gold gain is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_XP),
		"XP gain can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_XP),
		"XP gain is listed with the character stats")
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_GEMS),
		"gem gain can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_GEMS),
		"gem gain is listed with the character stats")
	_expect(CrawlerMeta.shop_stats() == PackedStringArray(CrawlerProgress.LEVEL_STATS),
		"the gem shop sells every in-run player stat")
	_expect(CrawlerProgress.rarity_weights(3.0)[3]
			> CrawlerProgress.rarity_weights(0.0)[3],
		"luck raises legendary weight")
	_expect(CrawlerProgress.rarity_weights(3.0)[0]
			< CrawlerProgress.rarity_weights(0.0)[0],
		"luck lowers common weight")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_DAMAGE, 1.0).contains("%"),
		"damage boosts say the percent")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_KNOCKBACK, 1.0).contains("knockback"),
		"knockback boosts say the shove")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_RANGE, 1.0).contains("range"),
		"range boosts say the reach")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_CAST, 1.0).contains("cast"),
		"cast boosts say the stand-still")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_LUCK, 1.0).contains("luck"),
		"luck boosts say the luck")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_ELEMENTAL, 1.0).contains("elemental"),
		"elemental boosts say the element")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_DEFENSE, 1.0).contains("defense"),
		"defense boosts say the reduction")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_JUKE_DISTANCE, 1.0).contains("dash"),
		"juke distance boosts say the dash")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_GOLD, 1.0).contains("gold"),
		"gold boosts say the gold")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_XP, 1.0).contains("XP"),
		"XP boosts say the XP")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_GEMS, 1.0).contains("gem"),
		"gem boosts say the gems")
	var payout := CrawlerProgress.new()
	payout.ranks[CrawlerProgress.STAT_GOLD] = 1.0
	payout.ranks[CrawlerProgress.STAT_XP] = 1.0
	payout.ranks[CrawlerProgress.STAT_GEMS] = 1.0
	var base_gold := CrawlerProgress.kill_gold(5)
	var base_xp := CrawlerProgress.kill_xp(5)
	var base_gems := CrawlerMeta.kill_gems(5)
	payout.award_kill(5)
	_expect(payout.gold == CrawlerProgress.apply_gain(
			base_gold, 1.0 + CrawlerProgress.GOLD_GAIN_PER_RANK),
		"one gold rank raises kill gold by twelve percent")
	_expect(payout.lifetime_xp() == CrawlerProgress.apply_gain(
			base_xp, 1.0 + CrawlerProgress.XP_GAIN_PER_RANK),
		"one XP rank raises kill XP by twelve percent")
	_expect(payout.gems_earned == CrawlerProgress.apply_gain(
			base_gems, 1.0 + CrawlerProgress.GEM_GAIN_PER_RANK),
		"one gem rank raises kill gems by twelve percent")
	_expect(payout.scaled_site_gems() == CrawlerProgress.apply_gain(
			CrawlerProgress.SITE_GEMS, 1.0 + CrawlerProgress.GEM_GAIN_PER_RANK),
		"gem rank also raises site discovery gems")
	var scratch := CrawlerProgress.new()
	scratch.unspent = 1
	scratch.seed_offers(7)
	var offers := scratch.roll_level_offers()
	_expect(offers.size() == CrawlerProgress.LEVEL_OFFER_COUNT,
		"level-up rolls four boosts")
	var seen := {}
	for raw: Variant in offers:
		if not (raw is Dictionary):
			_expect(false, "each offer is a dictionary")
			continue
		var stat_id := str((raw as Dictionary).get("id", ""))
		_expect(CrawlerProgress.LEVEL_STATS.has(stat_id),
			"level-up offers come from the player stats")
		_expect(not seen.has(stat_id), "level-up offers are unique")
		seen[stat_id] = true
	_expect(scratch.reroll_price() == CrawlerProgress.REROLL_BASE,
		"the first reroll costs one gold")
	scratch.gold = 0
	_expect(not scratch.reroll_level_offers(), "reroll refuses a dry purse")
	scratch.gold = 1
	_expect(scratch.reroll_level_offers(), "one gold buys a fresh set of boosts")
	_expect(scratch.gold == 0, "the first reroll spends its gold")
	_expect(scratch.reroll_price() == CrawlerProgress.REROLL_BASE * 2,
		"each reroll doubles the next price")
	scratch.gold = 2
	_expect(scratch.reroll_level_offers(), "the doubled price can still be paid")
	_expect(scratch.reroll_price() == CrawlerProgress.REROLL_BASE * 4,
		"a second reroll doubles the price again")
	_expect(scratch.level_offers.size() == CrawlerProgress.LEVEL_OFFER_COUNT,
		"a reroll still offers four boosts")
	scratch.unspent = 1
	scratch.ranks[CrawlerProgress.STAT_DAMAGE] = 0.0
	scratch.ranks[CrawlerProgress.STAT_DODGE] = 0.0
	scratch.force_level_offers([
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_HEALTH, CrawlerProgress.RARITY_UNCOMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DEXTERITY, CrawlerProgress.RARITY_COMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DODGE, CrawlerProgress.RARITY_RARE),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DAMAGE, CrawlerProgress.RARITY_LEGENDARY),
	])
	var auto_picks := scratch.auto_pick_offers()
	_expect(auto_picks.size() == 2
			and str((auto_picks[0] as Dictionary).get("id", "")) == CrawlerProgress.STAT_DAMAGE
			and str((auto_picks[1] as Dictionary).get("id", "")) == CrawlerProgress.STAT_DODGE,
		"auto level-up takes the highest rarity and the next offer")
	scratch.auto_claim_level_offers()
	_expect(scratch.unspent == 0, "auto level-up spends the point")
	_expect(is_equal_approx(scratch.rank_of(CrawlerProgress.STAT_DAMAGE),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_LEGENDARY)),
		"auto level-up applies the best rarity")
	_expect(is_equal_approx(scratch.rank_of(CrawlerProgress.STAT_DODGE),
			CrawlerProgress.rarity_amount(CrawlerProgress.RARITY_RARE)),
		"auto level-up also applies a second stat")


func _health_level_offers() -> Array:
	return [
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_HEALTH, CrawlerProgress.RARITY_UNCOMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DEXTERITY, CrawlerProgress.RARITY_COMMON),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DODGE, CrawlerProgress.RARITY_RARE),
		CrawlerProgress.make_offer(
			CrawlerProgress.STAT_DAMAGE, CrawlerProgress.RARITY_LEGENDARY),
	]


func _hat_mines() -> Array[CrawlerHatMine]:
	var found: Array[CrawlerHatMine] = []
	if not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerHatMine.GROUP):
		var mine := node_variant as CrawlerHatMine
		if mine != null:
			found.append(mine)
	return found


func _free_hat_mines() -> void:
	for mine: CrawlerHatMine in _hat_mines():
		mine.queue_free()
	await get_tree().process_frame


func _check_city_hats() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var progress := _player.crawler_progress
	_expect(_player.abilities.size() == CrawlerRules.ABILITY_SLOTS,
		"crawler starts with three ability slots")
	progress.grant_hat(CrawlerProgress.HAT_LEARNED, true)
	_player.refresh_crawler_look()
	_expect(progress.wearing_learned_hat(), "granting the learned cap puts it on")
	_expect(_player.abilities.size() == CrawlerRules.ABILITY_SLOTS_MAX,
		"the learned cap opens a fourth ability slot")
	_expect(_player.crawler_kit.shop_grant("starfire"),
		"a bought card can sit in the extra slot")
	var extra := _player.abilities.get_item(1)
	_expect(not extra.is_empty(), "the spare card lands on the bar")
	_player.abilities.set_item(1, "")
	_player.abilities.set_item(3, extra)
	_expect(_player.abilities.get_item(3) == extra,
		"the fourth slot holds an equipped card")
	var bar := WeaponBar.new()
	add_child(bar)
	bar.bind_loadout(_player.abilities, _player.hotbar)
	bar.refresh()
	var row := bar.find_child("HotbarSlots", true, false)
	_expect(row != null and row.get_child_count() == 4,
		"the hud grows a fourth box for the learned cap")
	bar.queue_free()
	var page := CrawlerHeroPage.new()
	page.configure(_player)
	add_child(page)
	page.refresh()
	_expect(page.find_child("CrawlerAbilityScroll", true, false) != null,
		"hero ability rows sit in a scroll")
	_expect(page.find_child("CrawlerAbilityTile_3", true, false) != null,
		"the hero page shows a fourth ability tile")
	page.queue_free()
	var store := CrawlerStoreUpgradesPage.new()
	store.configure(_player)
	add_child(store)
	store.refresh()
	_expect(store.find_child("CrawlerAbilityTile_3", true, false) != null,
		"the upgrade page shows a fourth ability tile")
	store.queue_free()
	progress.note_worn("")
	_player.refresh_crawler_look()
	_expect(_player.abilities.size() == CrawlerRules.ABILITY_SLOTS,
		"taking the learned cap off closes the fourth slot")
	_expect(_player.crawler_kit.inventory.find(extra) >= 0,
		"the extra card drops into the bag")

	progress.grant_hat(CrawlerProgress.HAT_VAMPIRE, true)
	_player.refresh_crawler_look()
	var max_hp := _player.maximum_health()
	_player.stats.set_health(max_hp * 0.5)
	var wounded := _player.health()
	var drain := Node.new()
	add_child(drain)
	var leech := DamageHit.impact(_player.combat_position(), 0.4, 50.0)
	_player.combat_damage_dealt(drain, 50.0, leech)
	_expect(is_equal_approx(
			_player.health(), wounded + 50.0 * progress.vampire_steal()),
		"the vampire hat heals from dealt damage")
	drain.free()

	progress.grant_hat(CrawlerProgress.HAT_ORDINANCE, true)
	_player.refresh_crawler_look()
	var blast := DamageHit.area(_player.combat_position(), 2.0, 24.0, 0.0)
	blast.faction = DamageHit.Faction.ENEMY
	blast.explosive = true
	var hp := _player.health()
	_expect(is_zero_approx(_player.apply_damage(blast)),
		"the ordinance helm ignores explosive damage")
	_expect(is_equal_approx(_player.health(), hp),
		"the ordinance helm keeps the hit points")
	var poke := DamageHit.impact(_player.combat_position(), 1.0, 8.0)
	poke.faction = DamageHit.Faction.ENEMY
	_expect(_player.apply_damage(poke) > 0.0,
		"the ordinance helm still takes ordinary hits")

	progress.grant_hat(CrawlerProgress.HAT_RUBBER, true)
	_player.refresh_crawler_look()
	var zap := DamageHit.impact(_player.combat_position(), 1.0, 18.0)
	zap.faction = DamageHit.Faction.ENEMY
	zap.ability_id = "lightning"
	_expect(is_zero_approx(_player.apply_damage(zap)),
		"the rubber beanie ignores lightning")
	var shocked := DamageHit.impact(_player.combat_position(), 0.4, 0.0)
	shocked.faction = DamageHit.Faction.ENEMY
	shocked.with_status(CombatStatuses.SHOCK, 2.0, 1.0)
	_player.apply_damage(shocked)
	_expect(not _player.statuses.has(CombatStatuses.SHOCK),
		"the rubber beanie refuses shock")

	progress.grant_hat(CrawlerProgress.HAT_PHASE, true)
	_player.refresh_crawler_look()
	_expect(is_equal_approx(progress.phase_chance(), CrawlerRules.PHASE_CHANCE),
		"one phase helm is a quarter chance")
	var bolt := DamageHit.impact(_player.combat_position(), 0.8, 16.0)
	bolt.faction = DamageHit.Faction.ENEMY
	bolt.projectile = true
	_player._dodge_roll_override = 0.0
	_expect(is_zero_approx(_player.apply_damage(bolt)),
		"the phase helm lets a projectile pass through")
	_player._dodge_roll_override = 0.99
	_expect(_player.apply_damage(bolt) > 0.0,
		"the phase helm still lets some projectiles land")
	_player._dodge_roll_override = -1.0

	progress.grant_hat(CrawlerProgress.HAT_MINE, true)
	_player.refresh_crawler_look()
	_player._mine_cooldown = 0.0
	_player._tick_mine_hat(0.02)
	var mines := _hat_mines()
	_expect(mines.size() == 1, "the trail cap drops a mine at your feet")
	var prey := _HatDummy.new()
	add_child(prey)
	prey.global_position = _player.combat_position()
	if not mines.is_empty():
		mines[0]._burst()
	_expect(prey.taken > 0.0, "the trail mine bursts after a second")
	await _free_hat_mines()
	prey.free()

	progress.grant_hat(CrawlerProgress.HAT_JUKE, true)
	_player.refresh_crawler_look()
	var foe := _HatDummy.new()
	add_child(foe)
	foe.global_position = _player.combat_position()
	_player._juke_struck.clear()
	_player._juke_hat_strike()
	_expect(foe.taken > 0.0, "the juke cap hurts a foe you dash through")
	foe.free()
	progress.note_worn("")
	_player.refresh_crawler_look()


func _check_hud_slots() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	_player.crawler_kit.shop_grant("nuke")
	var bar := WeaponBar.new()
	add_child(bar)
	bar.bind_loadout(_player.abilities, _player.hotbar)
	bar.bind_ability_controller(_player.ability_controller())
	await get_tree().process_frame
	_expect(bar.find_child("HotbarSlots", true, false) != null, "hud bar exists")
	var row := bar.find_child("HotbarSlots", true, false)
	_expect(row.get_child_count() == 3, "crawler hud shows three boxes")
	var nuke_slot := row.get_child(1) as ItemSlot
	_expect(nuke_slot != null and nuke_slot.count_text == "3",
		"hud shows three shots on nuke")
	var nuke := _player.crawler_kit.equipped_card(1)
	if nuke != null:
		_player.crawler_kit.spend_ammo(nuke)
		_player.crawler_kit.spend_ammo(nuke)
		_player.crawler_kit.spend_ammo(nuke)
		bar.refresh()
		_expect(nuke_slot.count_text == "0", "hud shows zero when nuke is empty")
	bar.queue_free()


func _check_fool_cape() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var progress := _player.crawler_progress
	progress.note_worn("")
	_player.refresh_crawler_look()
	_player.stats.set_health(_player.maximum_health())
	_expect(CrawlerProgress.cape_stock().has(CrawlerProgress.CAPE_FOOL),
		"the cape stall stocks the fool's teleport cape")
	_expect(not ItemDB.paint_path(CrawlerProgress.CAPE_FOOL).is_empty(),
		"the fool's cape has a paint texture")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var near := 0
	var far := 0
	var illegal := 0
	for _index in 400:
		var span := CrawlerRules.fool_cape_distance(rng)
		if span < CrawlerRules.FOOL_CAPE_MIN - 0.001 \
				or span > CrawlerRules.FOOL_CAPE_MAX + 0.001:
			illegal += 1
		elif span <= CrawlerRules.FOOL_CAPE_LIKELY + 0.001:
			near += 1
		else:
			far += 1
	_expect(illegal == 0, "fool hops stay between five and twenty-five hundred metres")
	_expect(near > far * 4, "most fool hops land inside twenty metres")
	_expect(progress.grant_cape(CrawlerProgress.CAPE_FOOL, true),
		"the run can be given the fool's cape")
	_player.refresh_crawler_look()
	_expect(progress.wearing_fool_cape() and _player.wearing_fool_cape(),
		"granting the fool's cape puts it on")
	var cloth := Wardrobe.worn_node(_player.character, "cape") as CapeCloth
	_expect(cloth != null and cloth.cape_paint != null,
		"the worn fool's cape shows red splotches")
	_player.global_position = Vector3(12.0, 3.0, -4.0)
	_player.velocity = Vector3(6.0, 0.0, -2.0)
	_player._fool_cape_lock = 0.0
	_player._fool_cape_distance_override = 12.0
	_player._fool_cape_dir_override = Vector3.RIGHT
	var before := _player.global_position
	var poke := DamageHit.impact(_player.combat_position(), 1.0, 9.0)
	poke.faction = DamageHit.Faction.ENEMY
	_expect(_player.apply_damage(poke) > 0.0, "a hit still deals damage through the cape")
	_expect(_player.global_position.distance_to(before) > 8.0,
		"a hit throws the wearer somewhere else")
	_expect(_player.velocity.is_equal_approx(Vector3(6.0, 0.0, -2.0)),
		"the fool's cape keeps the wearer's momentum")
	var hopped := _player.global_position
	_expect(_player.apply_damage(poke) > 0.0, "a second hit still hurts")
	_expect(_player.global_position.is_equal_approx(hopped),
		"the lock stops a second hop from the same blast")
	_player._fool_cape_distance_override = -1.0
	_player._fool_cape_dir_override = Vector3.ZERO
	progress.note_worn_cape("")
	_player.refresh_crawler_look()
	_expect(not _player.wearing_fool_cape(), "taking the fool's cape off stops the hops")


func _check_city_bank() -> void:
	CrawlerKit.clear_session()
	_player.crawler_kit.seed_starter()
	var kit := _player.crawler_kit
	var eyes := kit.equipped_card(0)
	_expect(eyes != null, "starter laser is present for the city bank")
	if eyes == null:
		return
	_expect(kit.upgrade_card(eyes.uid, "damage"),
		"city bank test can rank laser eyes")
	_expect(kit.move_card(
			CrawlerKit.SOURCE_EQUIP, 0, CrawlerKit.SOURCE_CITY_EQUIP, 0),
		"an ability can move into the city stash")
	_expect(kit.equipped_card(0) == null,
		"city stash takes the card off the hotbar")
	_expect(kit.city_equipped_card(0) != null
			and kit.city_equipped_card(0).id == "laser_eyes",
		"the city row holds laser eyes")
	var wobble := CrawlerCatalog.make_modifier("wobble")
	_expect(bool(kit.grant(wobble.to_dict()).get("ok", false)),
		"city bank test can grant a wobble")
	var bag := -1
	for index in kit.inventory.size():
		var held := kit.inventory_card(index)
		if held != null and held.id == "wobble":
			bag = index
			break
	_expect(bag >= 0, "wobble landed in the bag")
	_expect(kit.move_card(
			CrawlerKit.SOURCE_BAG, bag, CrawlerKit.SOURCE_CITY_BAG, 0),
		"a mod can move into the city bag")
	_expect(kit.city_inventory_card(0) != null
			and kit.city_inventory_card(0).id == "wobble",
		"the city bag holds wobble")
	var payload := kit.to_dict()
	CrawlerKit.clear_session()
	kit.from_dict(payload)
	_expect(kit.city_equipped_card(0) != null
			and kit.city_equipped_card(0).id == "laser_eyes",
		"the city stash survives a kit reload")
	_expect(kit.city_inventory_card(0) != null
			and kit.city_inventory_card(0).id == "wobble",
		"the city bag survives a kit reload")
	_expect(kit.ability_upgrade_rank("laser_eyes", "damage") >= 1,
		"stashed laser eyes keep their store ranks")
	_expect(kit.move_card(
			CrawlerKit.SOURCE_CITY_EQUIP, 0, CrawlerKit.SOURCE_EQUIP, 0),
		"the city stash can return an ability")
	_expect(kit.move_card(
			CrawlerKit.SOURCE_CITY_BAG, 0, CrawlerKit.SOURCE_BAG, 0),
		"the city bag can return a mod")
	var rack := kit.mod_rack(0)
	_expect(rack != null, "returned laser eyes expose a mod rack")
	if rack != null:
		ItemContainer.transfer(kit.inventory, 0, rack, 0)
	_expect(kit.equipped_card(0) != null
			and kit.equipped_card(0).mod_at(0) != null
			and kit.equipped_card(0).mod_at(0).id == "wobble",
		"laser eyes can carry a seated mod into the locker")
	var locker := CrawlerKit.new()
	locker.open_bank(1, 0)
	_expect(CrawlerKit.hand_off(
			kit, CrawlerKit.SOURCE_EQUIP, 0, locker, CrawlerKit.SOURCE_EQUIP, 0),
		"the locker takes the ability off the loadout")
	_expect(kit.equipped_card(0) == null,
		"locking an ability removes it from the run")
	_expect(locker.equipped_card(0) != null
			and locker.equipped_card(0).id == "laser_eyes",
		"the locker holds laser eyes")
	_expect(locker.equipped_card(0).mod_at(0) != null
			and locker.equipped_card(0).mod_at(0).id == "wobble",
		"the locker keeps seated mods")
	CrawlerMeta.set_locker_card(locker.equipped_card(0).to_dict())
	_expect(str(CrawlerMeta.locker_card().get("id", "")) == "laser_eyes",
		"meta keeps the locker card")
	CrawlerKit.clear_session()
	kit.seed_starter()
	_expect(kit.equipped_card(0) != null
			and kit.equipped_card(0).id == "laser_eyes",
		"a new run still starts with laser eyes")
	_expect(kit.ability_upgrade_rank("laser_eyes", "damage") == 0,
		"a fresh run does not keep the last run's ranks")
	var next := CrawlerKit.new()
	next.open_bank(1, 0)
	var stored := CrawlerCard.from_dict(CrawlerMeta.locker_card())
	_expect(stored != null and stored.id == "laser_eyes",
		"the locker card can be read after a new run starts")
	_expect(next.place_card(stored, CrawlerKit.SOURCE_EQUIP, 0),
		"the locker kit can load the stored card")
	_expect(CrawlerKit.hand_off(
			next, CrawlerKit.SOURCE_EQUIP, 0, kit, CrawlerKit.SOURCE_EQUIP, 1),
		"the locker can return the card to a later run")
	_expect(kit.equipped_card(1) != null
			and kit.equipped_card(1).id == "laser_eyes",
		"the withdrawn locker card seats on the new run")
	_expect(kit.equipped_card(1).mod_at(0) != null
			and kit.equipped_card(1).mod_at(0).id == "wobble",
		"the locker returns seated mods")
	_expect(kit.ability_upgrade_rank("laser_eyes", "damage") >= 1,
		"withdrawing a locker card restores its store ranks")
	_expect(kit.upgrade_rank_for(kit.equipped_card(0), "damage") >= 1,
		"shared ranks apply to the starter copy too")
	CrawlerMeta.set_locker_card({})
	_expect(CrawlerMeta.locker_card().is_empty(), "clearing the locker empties meta")


func _bubbles_peel_from_beam(from: Vector3, dest: Vector3,
		orbs: Array[CrawlerBubble]) -> bool:
	if orbs.size() < 3:
		return false
	var span := dest - from
	var length := span.length()
	if length < 0.2:
		return false
	var dir := span / length
	var min_share := 1.0
	var max_share := 0.0
	var near_end := 0
	for orb: CrawlerBubble in orbs:
		if orb == null or not is_instance_valid(orb):
			continue
		var share := (orb.global_position - from).dot(dir) / length
		min_share = minf(min_share, share)
		max_share = maxf(max_share, share)
		if share > 0.85:
			near_end += 1
		if orb.velocity.length_squared() < 0.0001:
			return false
		if absf(orb.velocity.normalized().dot(dir)) > 0.55:
			return false
	return max_share - min_share > 0.35 and near_end * 2 < orbs.size()


func _bubbles_follow_polyline(path: PackedVector3Array,
		orbs: Array[CrawlerBubble]) -> bool:
	if path.size() < 3 or orbs.size() < 3:
		return false
	var chord := path[path.size() - 1] - path[0]
	var chord_len := chord.length()
	if chord_len < 0.2:
		return false
	var along := chord / chord_len
	var off_chord := 0
	for orb: CrawlerBubble in orbs:
		if orb == null or not is_instance_valid(orb):
			continue
		var best := INF
		for index in path.size() - 1:
			var a := path[index]
			var b := path[index + 1]
			var span := b - a
			var length := span.length_squared()
			var point := a if length < 0.000001 \
				else a + span * clampf((orb.global_position - a).dot(span) / length,
					0.0, 1.0)
			best = minf(best, point.distance_squared_to(orb.global_position))
		if best > 0.8:
			return false
		var lateral := orb.global_position - (path[0] + along * clampf(
			(orb.global_position - path[0]).dot(along), 0.0, chord_len))
		if lateral.length() > 1.1:
			off_chord += 1
	return off_chord > 0


func _bubbles_surround(origin: Vector3, orbs: Array[CrawlerBubble]) -> bool:
	if orbs.size() < 3:
		return false
	var up := origin.normalized() if origin.length_squared() > 0.01 else Vector3.UP
	var east := up.cross(Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP)
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east).normalized()
	var max_up := 0.0
	var max_east := 0.0
	var max_north := 0.0
	for orb: CrawlerBubble in orbs:
		if orb == null or not is_instance_valid(orb):
			continue
		var offset := orb.global_position - origin
		max_up = maxf(max_up, absf(offset.dot(up)))
		max_east = maxf(max_east, absf(offset.dot(east)))
		max_north = maxf(max_north, absf(offset.dot(north)))
	var span := maxf(maxf(max_up, max_east), max_north)
	return span > 0.2 \
		and max_up > span * 0.22 \
		and max_east > span * 0.22 \
		and max_north > span * 0.22


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_kit_test failed: %s" % label)
