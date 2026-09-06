extends Node

## Headless checks for crawler abilities, modifiers, and the starter kit.
##
##     godot --headless --path . dev/_crawler_kit_test.tscn

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
	_check_starfire_upgrades()
	_check_meteor_punch_upgrades()
	_check_starfire_big()
	_check_big_ranks()
	_check_shared_ability_upgrades()
	_check_hero_page()
	await _check_level_tiles()
	await _check_hud_slots()


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
	_expect(CrawlerRules.starts_visible(CrawlerRules.CITY_SITE_ID),
		"Neon Fjord is on tilde from the start")
	_expect(not CrawlerRules.starts_visible(CrawlerRules.START_SITE_ID),
		"Tide Margin waits until you walk in")
	_expect(ResourceLoader.exists(CrawlerCityRing.VILLAGE_MODEL),
		"Neon Fjord village is in the project")
	_expect(ResourceLoader.exists(CrawlerSpawnPad.MODEL),
		"Relay 07 is the Tide Margin spawn")
	_expect(BuildingFoundation.EMBED > 0.0, "building stems bite into the ground")
	_expect(BuildingFloraClear.PAD_METRES == 10.0, "flora keeps 10 metres off buildings")
	_expect(CrawlerCatalog.has("laser_eyes"), "catalog lists laser eyes")
	_expect(CrawlerCatalog.has("meteor_punch"), "catalog lists meteor punch")
	_expect(CrawlerCatalog.has("wobble"), "catalog lists wobble")
	_expect(CrawlerCatalog.has("big"), "catalog lists big")
	_expect(CrawlerCatalog.is_ability("laser_eyes"), "laser eyes is an ability")
	_expect(CrawlerCatalog.is_ability("meteor_punch"), "meteor punch is an ability")
	_expect(CrawlerCatalog.default_slots("meteor_punch") == 3,
		"meteor punch defaults to 3 slots")
	_expect(CrawlerCatalog.is_modifier("wobble"), "wobble is a modifier")
	_expect(CrawlerCatalog.default_slots("laser_eyes") == 3, "laser eyes defaults to 3 slots")
	_expect(CrawlerCatalog.scope_of("wobble") == "ability_specific", "wobble is ability-specific")
	_expect(CrawlerCatalog.scope_of("big") == "generic", "big is generic")
	_expect(CrawlerCatalog.icon_path("wobble").ends_with("wobble.svg"),
		"wobble has its own icon")
	_expect(CrawlerCatalog.host_abilities("wobble") == PackedStringArray(["laser_eyes"]),
		"wobble names laser eyes as its host")
	_expect(CrawlerCatalog.host_abilities("big").is_empty(),
		"generic mods have no host badge")
	_expect(CrawlerCatalog.texture_for("big") != null, "big has a generic icon")
	_expect(CrawlerCatalog.texture_for("wobble") != null, "wobble has an icon")
	var card := CrawlerCatalog.make_ability("laser_eyes")
	_expect(card != null and card.slot_count == 3, "make_ability reads slot count from csv")
	_expect(CrawlerCatalog.make_modifier("wobble") != null, "make_modifier reads wobble from csv")


func _check_effects() -> void:
	_expect(CrawlerCatalog.compatible("wobble", "laser_eyes"), "wobble fits laser eyes")
	_expect(not CrawlerCatalog.compatible("wobble", "nuke"), "wobble does not fit nuke")
	_expect(CrawlerCatalog.compatible("big", "nuke"), "big fits nuke")
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
		"big multiplies meteor punch crater radius")
	var star_copy := CrawlerCatalog.description_of("big", "starfire")
	_expect(star_copy.contains(CrawlerRules.format_mul(CrawlerRules.big_size_scale(0)))
			and star_copy.contains("Starfire"),
		"seated big names the starfire size boost")
	var laser_copy := CrawlerCatalog.description_of("big", "laser_eyes")
	_expect(laser_copy.contains(CrawlerRules.format_mul(CrawlerRules.big_size_scale(0)))
			and laser_copy.contains("Laser Eyes"),
		"seated big names the laser size boost")
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


func _check_starter() -> void:
	_expect(_player.crawler_kit != null, "crawler player has a kit")
	_expect(_player.abilities.size() == 3, "crawler uses three ability slots")
	var card := _player.crawler_kit.equipped_card(0)
	_expect(card != null and card.id == "laser_eyes", "starter equips laser eyes")
	_expect(CrawlerRules.ability_enabled("starfire"),
		"starfire can be picked up in the first city")
	_expect(CrawlerRules.ability_enabled("meteor_punch"),
		"meteor punch is a crawler ability")
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
	page.queue_free()
	var dropped := DroppedCrawlerCard.new()
	dropped.configure(1, {"id": "laser_eyes", "mods": []})
	add_child(dropped)
	_expect(dropped.find_child("CardVisual", true, false) != null,
		"dropped ability becomes a world tile")
	dropped.queue_free()


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
	_expect(rarity != null and rarity.text.contains("UNCOMMON"),
		"each spend tile names its rarity")
	_expect(boost != null and boost.text.contains("HP"),
		"each spend tile shows the boost amount")
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
	_expect(CrawlerProgress.LEVEL_STATS.has(CrawlerProgress.STAT_LUCK),
		"luck can appear on the level-up board")
	_expect(CrawlerProgress.STAT_ORDER.has(CrawlerProgress.STAT_LUCK),
		"luck is listed with the character stats")
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
			CrawlerProgress.STAT_LUCK, 1.0).contains("luck"),
		"luck boosts say the luck")
	_expect(CrawlerProgress.offer_boost_text(
			CrawlerProgress.STAT_DEFENSE, 1.0).contains("defense"),
		"defense boosts say the reduction")
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


func _check_hud_slots() -> void:
	var bar := WeaponBar.new()
	add_child(bar)
	bar.bind_loadout(_player.abilities, _player.hotbar)
	await get_tree().process_frame
	_expect(bar.find_child("HotbarSlots", true, false) != null, "hud bar exists")
	var row := bar.find_child("HotbarSlots", true, false)
	_expect(row.get_child_count() == 3, "crawler hud shows three boxes")
	bar.queue_free()


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("crawler_kit_test failed: %s" % label)
