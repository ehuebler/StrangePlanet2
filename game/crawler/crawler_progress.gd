class_name CrawlerProgress
extends RefCounted

## Run-local crawler XP, gold, and spendable stat ranks. Host owns the numbers;
## the player copies them into motion, health, and damage.

signal changed
signal leveled_up

const STAT_HEALTH := "health"
const STAT_DEXTERITY := "dexterity"
const STAT_FLIGHT := "flight"
const STAT_DODGE := "dodge"
const STAT_DEFENSE := "defense"
const STAT_JUKE := "juke"
const STAT_JUKE_DISTANCE := "juke_distance"
const STAT_DAMAGE := "damage"
const STAT_KNOCKBACK := "knockback"
const STAT_RANGE := "range"
const STAT_CAST := "cast"
const STAT_LUCK := "luck"
const STAT_ELEMENTAL := "elemental"
const STAT_GOLD := "gold"
const STAT_XP := "xp"
const STAT_GEMS := "gems"
const LEVEL_STATS := [
	STAT_HEALTH, STAT_DEXTERITY, STAT_FLIGHT, STAT_DODGE, STAT_DEFENSE,
	STAT_JUKE, STAT_JUKE_DISTANCE, STAT_DAMAGE, STAT_KNOCKBACK, STAT_RANGE,
	STAT_CAST, STAT_LUCK, STAT_ELEMENTAL, STAT_GOLD, STAT_XP, STAT_GEMS,
]
const STAT_ORDER := [
	STAT_HEALTH, STAT_DEXTERITY, STAT_FLIGHT, STAT_DODGE, STAT_DEFENSE,
	STAT_JUKE, STAT_JUKE_DISTANCE, STAT_DAMAGE, STAT_KNOCKBACK, STAT_RANGE,
	STAT_CAST, STAT_LUCK, STAT_ELEMENTAL, STAT_GOLD, STAT_XP, STAT_GEMS,
]
const LEVEL_OFFER_COUNT := 4
const LEVEL_HEAL := 0.10
const RARITY_COMMON := 0
const RARITY_UNCOMMON := 1
const RARITY_RARE := 2
const RARITY_LEGENDARY := 3
const RARITY_RANKS := [0.70, 1.00, 1.75, 2.80]
const RARITY_WEIGHTS := [62.0, 26.0, 10.0, 2.0]
const LUCK_WEIGHT := 0.22
const LUCK_COMMON_SHRINK := 0.14
const REROLL_BASE := 1
const REROLL_USES_CAP := 20

const XP_BASE := 5
const XP_GROWTH := 1
const GOLD_BASE := 0
const GOLD_PER_LEVEL := 1
const XP_KILL_BASE := 0
const XP_PER_LEVEL := 1
const HEALTH_BASE := 100.0
const HEALTH_PER_RANK := 22.0
const DEX_PER_RANK := 0.14
const FLIGHT_PER_RANK := 0.20
const DAMAGE_PER_RANK := 0.12
const KNOCKBACK_PER_RANK := 0.12
const RANGE_PER_RANK := 0.12
const CAST_PER_RANK := 0.10
const ELEMENTAL_PER_RANK := 0.14
const GOLD_GAIN_PER_RANK := 0.12
const XP_GAIN_PER_RANK := 0.12
const GEM_GAIN_PER_RANK := 0.12
const DODGE_PER_RANK := 0.06
const DODGE_MAX := 0.40
const DEFENSE_PER_RANK := 0.08
const DEFENSE_MAX := 0.60
const JUKE_COOLDOWN_BASE := 5.0
const JUKE_COOLDOWN_PER_RANK := 0.10
const JUKE_COOLDOWN_MIN := 0.25
const JUKE_DISTANCE_BASE := 2.0
const JUKE_DISTANCE_PER_RANK := 0.80
const TRAIT_BODY := "settler"
const TRAIT_LEVEL_DAMAGE := "noct_level_damage"
const TRAIT_DAMAGE_PER_LEVEL := 0.02
const HAT_ID := "crawler_gale_hat"
const HAT_WARD := "crawler_ward_hat"
const HAT_LUCK := "crawler_luck_hat"
const HAT_KIT := "crawler_kit_hat"
const HAT_MISSILE := "crawler_missile_hat"
const HAT_MINE := "crawler_mine_hat"
const HAT_VAMPIRE := "crawler_vampire_hat"
const HAT_PHASE := "crawler_phase_hat"
const HAT_ORDINANCE := "crawler_ordinance_hat"
const HAT_RUBBER := "crawler_rubber_hat"
const HAT_LEARNED := "crawler_learned_hat"
const HAT_JUKE := "crawler_juke_hat"
const HAT_REPEATER := "crawler_repeater_hat"
const HAT_FOOL := "crawler_fool_hat"
const HAT_BAZAAR := "crawler_bazaar_hat"
const HAT_PRICE := 50
const HAT_WARD_PRICE := 40
const HAT_LUCK_PRICE := 50
const HAT_KIT_PRICE := 48
const HAT_MISSILE_PRICE := 52
const HAT_MINE_PRICE := 50
const HAT_VAMPIRE_PRICE := 48
const HAT_PHASE_PRICE := 46
const HAT_ORDINANCE_PRICE := 50
const HAT_RUBBER_PRICE := 42
const HAT_LEARNED_PRICE := 55
const HAT_JUKE_PRICE := 44
const HAT_REPEATER_PRICE := 54
const HAT_FOOL_PRICE := 50
const HAT_BAZAAR_PRICE := 58
const HAT_LUCK_BONUS := 8.0
const WARD_RESPAWN := 8.0
const HAT_STOCK := [
	HAT_ID, HAT_WARD, HAT_LUCK, HAT_KIT, HAT_MISSILE,
	HAT_MINE, HAT_VAMPIRE, HAT_PHASE, HAT_ORDINANCE,
	HAT_RUBBER, HAT_LEARNED, HAT_JUKE, HAT_REPEATER, HAT_FOOL,
	HAT_BAZAAR,
]
const HAT_PRICES := {
	HAT_ID: HAT_PRICE,
	HAT_WARD: HAT_WARD_PRICE,
	HAT_LUCK: HAT_LUCK_PRICE,
	HAT_KIT: HAT_KIT_PRICE,
	HAT_MISSILE: HAT_MISSILE_PRICE,
	HAT_MINE: HAT_MINE_PRICE,
	HAT_VAMPIRE: HAT_VAMPIRE_PRICE,
	HAT_PHASE: HAT_PHASE_PRICE,
	HAT_ORDINANCE: HAT_ORDINANCE_PRICE,
	HAT_RUBBER: HAT_RUBBER_PRICE,
	HAT_LEARNED: HAT_LEARNED_PRICE,
	HAT_JUKE: HAT_JUKE_PRICE,
	HAT_REPEATER: HAT_REPEATER_PRICE,
	HAT_FOOL: HAT_FOOL_PRICE,
	HAT_BAZAAR: HAT_BAZAAR_PRICE,
}
const HAT_MERGE_PRICE := 100
const LOCKER_PRICE := 100
const HAT_UID_PREFIX := "crawler_cap_"
const FX_DEX := "dex"
const FX_FLIGHT := "flight"
const FX_WARD := "ward"
const FX_LUCK := "luck"
const FX_KIT := "kit"
const FX_MISSILE := "missile"
const FX_MINE := "mine"
const FX_VAMPIRE := "vampire"
const FX_PHASE := "phase"
const FX_ORDINANCE := "ordinance"
const FX_RUBBER := "rubber"
const FX_LEARNED := "learned"
const FX_JUKE := "juke"
const FX_REPEATER := "repeater"
const FX_FOOL := "fool"
const FX_BAZAAR := "bazaar"
const HAT_FX_KEYS: PackedStringArray = [
	FX_DEX, FX_FLIGHT, FX_WARD, FX_LUCK, FX_KIT, FX_MISSILE,
	FX_MINE, FX_VAMPIRE, FX_PHASE, FX_ORDINANCE, FX_RUBBER, FX_LEARNED, FX_JUKE,
	FX_REPEATER, FX_FOOL, FX_BAZAAR,
]
const HAT_BASE_EFFECTS := {
	HAT_ID: {FX_DEX: 1, FX_FLIGHT: 1},
	HAT_WARD: {FX_WARD: 1},
	HAT_LUCK: {FX_LUCK: 1},
	HAT_KIT: {FX_KIT: 1},
	HAT_MISSILE: {FX_MISSILE: 1},
	HAT_MINE: {FX_MINE: 1},
	HAT_VAMPIRE: {FX_VAMPIRE: 1},
	HAT_PHASE: {FX_PHASE: 1},
	HAT_ORDINANCE: {FX_ORDINANCE: 1},
	HAT_RUBBER: {FX_RUBBER: 1},
	HAT_LEARNED: {FX_LEARNED: 1},
	HAT_JUKE: {FX_JUKE: 1},
	HAT_REPEATER: {FX_REPEATER: 1},
	HAT_FOOL: {FX_FOOL: 1},
	HAT_BAZAAR: {FX_BAZAAR: 1},
}
const HAT_NOUNS := {
	HAT_ID: "Cap",
	HAT_WARD: "Halo",
	HAT_LUCK: "Cap",
	HAT_KIT: "Visor",
	HAT_MISSILE: "Hat",
	HAT_MINE: "Cap",
	HAT_VAMPIRE: "Horns",
	HAT_PHASE: "Helm",
	HAT_ORDINANCE: "Helm",
	HAT_RUBBER: "Beanie",
	HAT_LEARNED: "Cap",
	HAT_JUKE: "Cap",
	HAT_REPEATER: "Cap",
	HAT_FOOL: "Cap",
	HAT_BAZAAR: "Fedora",
}
const CAPE_ID := "crawler_plain_cape"
const CAPE_GOLD := "crawler_gold_cape"
const CAPE_PRICE := 250
const CAPE_GOLD_PRICE := 280
const CAPE_STOCK := [CAPE_ID, CAPE_GOLD]
const CAPE_PRICES := {
	CAPE_ID: CAPE_PRICE,
	CAPE_GOLD: CAPE_GOLD_PRICE,
}
const QUEST_TOWER := "office_tower"
const QUEST_CASTLE := "castle"
const QUEST_BOSS := "boss"
const QUEST_TREE_TITLE := "Barking up the Wrong Tree"
const QUEST_ORDER := [QUEST_TOWER, QUEST_CASTLE, QUEST_BOSS]
const QUEST_PRICES := {
	QUEST_TOWER: 30,
	QUEST_CASTLE: 30,
	QUEST_BOSS: 30,
}
const TICKET_ID := "crawler_respawn_ticket"
const TICKET_GOLD := 50
const TICKET_GEMS := 10
const REST_HEALTH_PRICE := 25
const REST_AMMO_PRICE := 20
const SHOP_IDS: PackedStringArray = [
	"hats", "caps", "capes", "cards", "abilities", "upgrades",
	"inventory", "locker", "quests", "market", "reststop", "duals",
]
const SHOP_ALWAYS: PackedStringArray = ["inventory", "reststop", "duals"]
const SHOP_OPTIONAL: PackedStringArray = [
	"hats", "caps", "capes", "cards", "abilities", "upgrades",
	"locker", "quests", "market",
]
const SHOP_FIRST_CITY: PackedStringArray = ["hats", "abilities"]
const SHOP_EXTRA_MIN := 3
const SHOP_EXTRA_MAX := 4
const SHOP_HAT_SLOTS := 3
const SHOP_ABILITY_SLOTS := 1
const SHOP_MOD_SLOTS := 3
const SITE_GEMS := 8
const HAT_DEX := 1.45
const HAT_FLIGHT := 1.55
const UPGRADE_BASE := 10
const STORE_MOD_PRICE := 10
const STORE_ABILITY_PRICE := 25
const SHOP_PRICES := {
	"wobble": 22,
	"big": 22,
	"bubble": 22,
	"linger": 22,
	"clip": 22,
	"endless": 28,
	"toxic": 22,
	"shock": 22,
	"charm": 22,
	"ice": 22,
	"multi": 22,
	"reach": 22,
	"bounce": 22,
	"impact_cast": 22,
	"homing": 22,
}
const ABILITY_PRICES := {
	"laser_eyes": 36,
	"kame": 42,
	"nausicaa": 40,
	"lightning": 38,
	"meteor_punch": 38,
	"hero_punch": 32,
	"starfire": 40,
	"light_bolt": 38,
	"icicle": 40,
	"teleport": 42,
	"fus": 36,
	"nuke": 44,
	"mini_nuke": 38,
	"wall": 34,
	"roar": 32,
	"toxic_blast": 34,
	"charming_aura": 36,
	"freeze_blast": 34,
	"static_field": 36,
	"toxic_field": 36,
	"freeze_field": 36,
	"healing_field": 36,
	"overdrive": 36,
}

static var session_payload: Dictionary = {}

var player: OnlinePlayer
var level := 1
var xp := 0
var gold := 0
var unspent := 0
var ranks: Dictionary = {
	STAT_HEALTH: 0,
	STAT_DEXTERITY: 0,
	STAT_FLIGHT: 0,
	STAT_DODGE: 0,
	STAT_DEFENSE: 0,
	STAT_JUKE: 0,
	STAT_JUKE_DISTANCE: 0,
	STAT_DAMAGE: 0,
	STAT_KNOCKBACK: 0,
	STAT_RANGE: 0,
	STAT_CAST: 0,
	STAT_LUCK: 0,
	STAT_ELEMENTAL: 0,
	STAT_GOLD: 0,
	STAT_XP: 0,
	STAT_GEMS: 0,
}
var owned_hats: PackedStringArray = PackedStringArray()
var worn_hat := ""
var hat_ledger: Dictionary = {}
var next_hat_serial := 1
var owned_capes: PackedStringArray = PackedStringArray()
var worn_cape := ""
var owned_quests: PackedStringArray = PackedStringArray()
var level_offers: Array = []
var last_levels_gained := 0
var reroll_uses := 0
var unlocked_sites: PackedStringArray = PackedStringArray()
var last_entered_site := ""
var kills := 0
var gems_earned := 0
var respawn_tickets := 0
var statue_seed := 0
var claimed_statues: PackedStringArray = PackedStringArray()
var rested_health_cities: PackedStringArray = PackedStringArray()
var rested_ammo_cities: PackedStringArray = PackedStringArray()
var fused_hat_cities: PackedStringArray = PackedStringArray()
var hat_buy_cities: PackedStringArray = PackedStringArray()
var shop_stock_slots: Dictionary = {}
var shop_upgrade_picks: Dictionary = {}
var shops_unlimited := false
var gold_unlimited := false
var run_path := ""
var quest_reveals: PackedStringArray = PackedStringArray()
## Set when GAME OVER pays global XP so a rebuilt death screen cannot pay twice.
var settled_global := false
var _offer_rng: RandomNumberGenerator = null


static func clear_session() -> void:
	session_payload = {}


static func xp_needed(at_level: int) -> int:
	return XP_BASE + XP_GROWTH * maxi(at_level - 1, 0)


static func kill_gold(mob_level: int) -> int:
	return GOLD_BASE + GOLD_PER_LEVEL * maxi(mob_level, 1)


static func kill_xp(mob_level: int, _kind := "") -> int:
	return XP_KILL_BASE + XP_PER_LEVEL * maxi(mob_level, 1)


static func stat_title(id: String) -> String:
	match id:
		STAT_HEALTH:
			return "Health"
		STAT_DEXTERITY:
			return "Dexterity"
		STAT_FLIGHT:
			return "Flight"
		STAT_DODGE:
			return "Dodge"
		STAT_DEFENSE:
			return "Defense"
		STAT_JUKE:
			return "Juke"
		STAT_JUKE_DISTANCE:
			return "Juke Distance"
		STAT_DAMAGE:
			return "Damage"
		STAT_KNOCKBACK:
			return "Knockback"
		STAT_RANGE:
			return "Range"
		STAT_CAST:
			return "Cast"
		STAT_LUCK:
			return "Luck"
		STAT_ELEMENTAL:
			return "Elemental"
		STAT_GOLD:
			return "Gold"
		STAT_XP:
			return "XP"
		STAT_GEMS:
			return "Gems"
		_:
			return id.capitalize()


static func stat_blurb(id: String) -> String:
	match id:
		STAT_HEALTH:
			return "More hit points."
		STAT_DEXTERITY:
			return "Faster walk and quicker acceleration."
		STAT_FLIGHT:
			return "A longer blue flight tank."
		STAT_DODGE:
			return "A chance that incoming hits deal no damage."
		STAT_DEFENSE:
			return "Incoming hits deal less damage."
		STAT_JUKE:
			return "A shorter wait between right-click dashes."
		STAT_JUKE_DISTANCE:
			return "Right-click dashes carry farther."
		STAT_DAMAGE:
			return "Ability damage multiplier."
		STAT_KNOCKBACK:
			return "Ability knockback multiplier."
		STAT_RANGE:
			return "Ability range multiplier."
		STAT_CAST:
			return "Field abilities appear sooner. You stand still for less time."
		STAT_LUCK:
			return "Better odds of rare and legendary level-up boosts."
		STAT_ELEMENTAL:
			return "Stronger poison, shock, charm, and frost, and they last longer."
		STAT_GOLD:
			return "More gold from kills."
		STAT_XP:
			return "More in-run XP from kills."
		STAT_GEMS:
			return "More gems from kills and discovered sites."
		_:
			return ""


func bind(owner: OnlinePlayer) -> void:
	player = owner


func restore_or_seed() -> void:
	if not session_payload.is_empty():
		from_dict(session_payload)
	ensure_statue_seed()
	remember()
	changed.emit()


func award_kill(mob_level: int, kind := "", gem_roll := -1.0) -> void:
	kills += 1
	gems_earned += scaled_kill_gems(mob_level, gem_roll)
	gold += scaled_kill_gold(mob_level)
	xp += scaled_kill_xp(mob_level, kind)
	var gained := 0
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		unspent += 1
		gained += 1
	remember()
	changed.emit()
	if gained > 0:
		last_levels_gained = gained
		leveled_up.emit()


func grant_spoils(gold_amount: int, gem_amount: int, xp_amount: int) -> void:
	gold += maxi(gold_amount, 0)
	var gems := maxi(gem_amount, 0)
	if gems > 0:
		gems_earned += gems
		CrawlerMeta.add_gems(gems)
	xp += maxi(xp_amount, 0)
	var gained := 0
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		unspent += 1
		gained += 1
	remember()
	changed.emit()
	if gained > 0:
		last_levels_gained = gained
		leveled_up.emit()


func spend(stat_id: String, amount := 1.0) -> bool:
	if unspent <= 0 or not is_level_stat(stat_id) or amount <= 0.0:
		return false
	ranks[stat_id] = rank_of(stat_id) + amount
	unspent -= 1
	level_offers = []
	remember()
	changed.emit()
	return true


func grant_boost(stat_id: String, amount: float) -> bool:
	if not is_level_stat(stat_id) or amount <= 0.0:
		return false
	ranks[stat_id] = rank_of(stat_id) + amount
	remember()
	changed.emit()
	return true


func ensure_statue_seed() -> int:
	if statue_seed == 0:
		statue_seed = randi()
		if statue_seed == 0:
			statue_seed = 1
		remember()
	return statue_seed


func statue_claimed(kind: String) -> bool:
	return not kind.is_empty() and claimed_statues.has(kind)


func claim_statue(kind: String) -> bool:
	if kind.is_empty() or claimed_statues.has(kind):
		return false
	claimed_statues.append(kind)
	remember()
	return true


func shop_open(shop_id: String, city := "") -> bool:
	return open_shops_for(city).has(shop_id)


func signed_shops_for(city := "") -> PackedStringArray:
	var signed: PackedStringArray = []
	for id: String in open_shops_for(city):
		if CrawlerShopIcons.shows_sign(id):
			signed.append(id)
	return signed


func shops_are_unlimited() -> bool:
	return shops_unlimited or wearing_bazaar_hat()


func open_shops_for(city := "") -> PackedStringArray:
	if shops_are_unlimited() or not CrawlerRules.crawler():
		return SHOP_IDS
	if CrawlerRun.active():
		var listed := CrawlerRun.shops_for(city)
		if not listed.is_empty():
			return listed
	var open := PackedStringArray()
	for id: String in SHOP_ALWAYS:
		open.append(id)
	var required := PackedStringArray()
	if CrawlerRules.is_first_city(city):
		for id: String in SHOP_FIRST_CITY:
			required.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = _shop_hours_seed(city)
	var extra_count := rng.randi_range(SHOP_EXTRA_MIN, SHOP_EXTRA_MAX)
	var pool: Array[String] = []
	for id: String in SHOP_OPTIONAL:
		if required.has(id):
			continue
		pool.append(id)
	for step in range(pool.size() - 1, 0, -1):
		var swap_at := rng.randi_range(0, step)
		var held := pool[step]
		pool[step] = pool[swap_at]
		pool[swap_at] = held
	var extras := required.duplicate()
	for id: String in pool:
		if extras.size() >= extra_count:
			break
		extras.append(id)
	for id: String in extras:
		if not open.has(id):
			open.append(id)
	return open


func shop_extra_count(city := "") -> int:
	var extras := 0
	for id: String in open_shops_for(city):
		if not SHOP_ALWAYS.has(id):
			extras += 1
	return extras


func _shop_hours_seed(city: String) -> int:
	var run := maxi(ensure_statue_seed(), 1)
	var mix := int(hash("%s/%d" % [city, run]))
	return mix if mix != 0 else run


func uses_limited_shop(city: String) -> bool:
	return CrawlerRules.crawler() and not shops_are_unlimited() \
			and not city.strip_edges().is_empty()


func shop_slot_count(kind: String) -> int:
	match kind:
		"hats":
			return SHOP_HAT_SLOTS
		"abilities":
			return SHOP_ABILITY_SLOTS
		"mods":
			return SHOP_MOD_SLOTS
		_:
			return 0


func shop_slots(kind: String, city: String) -> Array:
	if not uses_limited_shop(city):
		return []
	ensure_shop_offers(city)
	var row := _offers_row(city)
	var held: Variant = row.get(kind, [])
	return held as Array if held is Array else []


func shop_has_unsold(kind: String, item_id: String, city: String) -> bool:
	if item_id.is_empty():
		return false
	if not uses_limited_shop(city):
		return true
	for raw: Variant in shop_slots(kind, city):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var slot := raw as Dictionary
		if str(slot.get("id", "")) == item_id and not bool(slot.get("sold", false)):
			return true
	return false


func shop_offer_ids(kind: String, city: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for raw: Variant in shop_slots(kind, city):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var slot := raw as Dictionary
		var item_id := str(slot.get("id", ""))
		if item_id.is_empty() or bool(slot.get("sold", false)):
			continue
		ids.append(item_id)
	return ids


func shop_can_refresh(kind: String, city: String) -> bool:
	if not uses_limited_shop(city) or shop_slot_count(kind) <= 0:
		return false
	if not has_gold(reroll_price()):
		return false
	for raw: Variant in shop_slots(kind, city):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if not bool((raw as Dictionary).get("sold", false)):
			return true
	return false


func ensure_shop_offers(city: String) -> void:
	if not uses_limited_shop(city):
		return
	var row := _offers_row(city)
	for kind: String in ["hats", "abilities", "mods"]:
		var held: Variant = row.get(kind, [])
		if held is Array and not (held as Array).is_empty():
			continue
		row[kind] = _roll_shop_slots(kind, city, [])
	shop_stock_slots[city] = row
	remember()


func force_shop_offers(city: String, kind: String, ids: PackedStringArray) -> void:
	var slots: Array = []
	for id: String in ids:
		slots.append({"id": id, "sold": false})
	while slots.size() < shop_slot_count(kind):
		slots.append({"id": "", "sold": false})
	var row := _offers_row(city)
	row[kind] = slots
	shop_stock_slots[city] = row
	remember()


func mark_shop_sold(kind: String, item_id: String, city: String) -> void:
	if not uses_limited_shop(city) or item_id.is_empty():
		return
	ensure_shop_offers(city)
	var row := _offers_row(city)
	var slots: Variant = row.get(kind, [])
	if not (slots is Array):
		return
	for raw: Variant in slots:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var slot := raw as Dictionary
		if str(slot.get("id", "")) != item_id or bool(slot.get("sold", false)):
			continue
		slot["id"] = ""
		slot["sold"] = true
		break
	row[kind] = slots
	shop_stock_slots[city] = row
	remember()
	changed.emit()


func refresh_shop_offers(kind: String, city: String) -> bool:
	if not shop_can_refresh(kind, city):
		return false
	if not pay_reroll():
		return false
	var row := _offers_row(city)
	var previous: Variant = row.get(kind, [])
	row[kind] = _roll_shop_slots(
		kind, city, previous as Array if previous is Array else [])
	shop_stock_slots[city] = row
	remember()
	changed.emit()
	return true


func upgrade_in_stock(catalog_id: String, stat_id: String, city: String) -> bool:
	if catalog_id.is_empty() or stat_id.is_empty():
		return false
	if not uses_limited_shop(city):
		return true
	var picks := upgrade_picks_for(catalog_id, city)
	return picks.has(stat_id)


func upgrade_picks_for(catalog_id: String, city: String) -> PackedStringArray:
	var listed := CrawlerRules.upgrade_stats_for(catalog_id)
	if not uses_limited_shop(city):
		return listed
	ensure_upgrade_picks(catalog_id, city)
	var row := _upgrade_row(city)
	var held: Variant = row.get(catalog_id, PackedStringArray())
	if held is PackedStringArray:
		return held
	var out := PackedStringArray()
	if held is Array:
		for raw: Variant in held:
			var stat_id := str(raw)
			if not stat_id.is_empty() and not out.has(stat_id):
				out.append(stat_id)
	return out


func ensure_upgrade_picks(catalog_id: String, city: String) -> void:
	if not uses_limited_shop(city) or catalog_id.is_empty():
		return
	var row := _upgrade_row(city)
	if row.has(catalog_id):
		return
	var listed := CrawlerRules.upgrade_stats_for(catalog_id)
	var pool: Array[String] = []
	for stat_id: String in listed:
		pool.append(stat_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = _offer_seed(city, "upgrade:%s" % catalog_id)
	for step in range(pool.size() - 1, 0, -1):
		var swap_at := rng.randi_range(0, step)
		var held := pool[step]
		pool[step] = pool[swap_at]
		pool[swap_at] = held
	var take := clampi(listed.size() / 2, 1, 3)
	var picks := PackedStringArray()
	for index in mini(take, pool.size()):
		picks.append(pool[index])
	row[catalog_id] = picks
	shop_upgrade_picks[city] = row
	remember()


func force_upgrade_picks(
		city: String, catalog_id: String, stats: PackedStringArray) -> void:
	if city.is_empty() or catalog_id.is_empty():
		return
	var row := _upgrade_row(city)
	row[catalog_id] = stats.duplicate()
	shop_upgrade_picks[city] = row
	remember()


func _roll_shop_slots(kind: String, city: String, previous: Array) -> Array:
	var count := shop_slot_count(kind)
	var pool: Array[String] = []
	for id: String in _shop_pool(kind):
		pool.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = _offer_seed(city, kind)
	for step in range(pool.size() - 1, 0, -1):
		var swap_at := rng.randi_range(0, step)
		var held := pool[step]
		pool[step] = pool[swap_at]
		pool[swap_at] = held
	var taken: Array[String] = []
	var slots: Array = []
	for index in count:
		var keep_sold := false
		if index < previous.size() and previous[index] is Dictionary:
			keep_sold = bool((previous[index] as Dictionary).get("sold", false))
		if keep_sold:
			slots.append({"id": "", "sold": true})
			continue
		var pick := ""
		for id: String in pool:
			if taken.has(id):
				continue
			pick = id
			break
		if not pick.is_empty():
			taken.append(pick)
		slots.append({"id": pick, "sold": false})
	return slots


func _shop_pool(kind: String) -> PackedStringArray:
	match kind:
		"hats":
			return hat_stock()
		"abilities":
			return ability_stock()
		"mods":
			return shop_stock()
		_:
			return PackedStringArray()


func _offer_seed(city: String, kind: String) -> int:
	var run := maxi(ensure_statue_seed(), 1)
	var mix := int(hash("%s/%s/%d/%d" % [city, kind, run, reroll_uses]))
	return mix if mix != 0 else run


func _offers_row(city: String) -> Dictionary:
	return _table_row(shop_stock_slots, city)


func _upgrade_row(city: String) -> Dictionary:
	return _table_row(shop_upgrade_picks, city)


func _table_row(table: Dictionary, city: String) -> Dictionary:
	if city.is_empty():
		return {}
	var held: Variant = table.get(city, null)
	if held is Dictionary:
		return held as Dictionary
	var row := {}
	table[city] = row
	return row


func _clone_shop_table(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for key: Variant in (raw as Dictionary).keys():
		var city := str(key)
		if city.is_empty():
			continue
		var held: Variant = (raw as Dictionary).get(key, null)
		if held is Dictionary:
			out[city] = (held as Dictionary).duplicate(true)
	return out


func rest_health_free(city: String) -> bool:
	return city.is_empty() or not rested_health_cities.has(city)


func rest_ammo_free(city: String) -> bool:
	return city.is_empty() or not rested_ammo_cities.has(city)


func rest_health_price_for(city: String) -> int:
	return 0 if rest_health_free(city) else REST_HEALTH_PRICE


func rest_ammo_price_for(city: String) -> int:
	return 0 if rest_ammo_free(city) else REST_AMMO_PRICE


func mark_rested_health(city: String) -> void:
	if city.is_empty() or rested_health_cities.has(city):
		return
	rested_health_cities.append(city)
	remember()
	changed.emit()


func mark_rested_ammo(city: String) -> void:
	if city.is_empty() or rested_ammo_cities.has(city):
		return
	rested_ammo_cities.append(city)
	remember()
	changed.emit()


func cap_merge_free(city: String) -> bool:
	if shops_are_unlimited() or not CrawlerRules.crawler():
		return true
	return city.is_empty() or not fused_hat_cities.has(city)


func mark_cap_merged(city: String) -> void:
	if city.is_empty() or fused_hat_cities.has(city):
		return
	fused_hat_cities.append(city)
	remember()
	changed.emit()


func mark_hat_bought(city: String) -> void:
	if city.is_empty() or hat_buy_cities.has(city):
		return
	hat_buy_cities.append(city)
	remember()
	changed.emit()


func hat_shop_price(city: String) -> int:
	return _city_double_price(HAT_PRICE, hat_buy_cities, city)


func cap_merge_price(city: String) -> int:
	return _city_double_price(HAT_MERGE_PRICE, fused_hat_cities, city)


static func _city_double_price(
		base: int, cities: PackedStringArray, city: String) -> int:
	if city.is_empty():
		return base
	var step := cities.size()
	if cities.has(city):
		step = maxi(step - 1, 0)
	return base * (1 << step)


func spend_offer(stat_id: String) -> bool:
	var offer := offer_for(stat_id)
	if offer.is_empty():
		return false
	return spend(stat_id, float(offer.get("amount", 1.0)))


func auto_pick_offers(offers: Array = []) -> Array:
	var source: Array = offers if not offers.is_empty() else level_offers
	var clean: Array = []
	for raw: Variant in source:
		if raw is Dictionary:
			var offer := _sanitize_offer(raw)
			if not offer.is_empty():
				clean.append(offer)
	if clean.is_empty():
		return []
	var pool := CrawlerAutoSelect.filter_offers(clean, CrawlerMeta.auto_prefs())
	if pool.is_empty():
		pool = clean
	pool.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("rarity", 0)) > int(right.get("rarity", 0))
	)
	var picks: Array = [pool[0]]
	if pool.size() > 1:
		picks.append(pool[1])
	return picks


func auto_claim_level_offers() -> Array:
	var claimed: Array = []
	while unspent > 0:
		ensure_level_offers()
		if level_offers.is_empty():
			break
		var picks := auto_pick_offers(level_offers)
		unspent -= 1
		level_offers = []
		for pick_variant: Variant in picks:
			if not (pick_variant is Dictionary):
				continue
			var pick := pick_variant as Dictionary
			grant_boost(str(pick.get("id", "")), float(pick.get("amount", 1.0)))
			claimed.append(pick)
		remember()
	changed.emit()
	return claimed


static func is_level_stat(stat_id: String) -> bool:
	return not stat_id.is_empty() and LEVEL_STATS.has(stat_id)


static func rarity_title(rarity: int) -> String:
	match clampi(rarity, RARITY_COMMON, RARITY_LEGENDARY):
		RARITY_UNCOMMON:
			return "Uncommon"
		RARITY_RARE:
			return "Rare"
		RARITY_LEGENDARY:
			return "Legendary"
		_:
			return "Common"


static func rarity_color(rarity: int) -> Color:
	match clampi(rarity, RARITY_COMMON, RARITY_LEGENDARY):
		RARITY_UNCOMMON:
			return Color("1e4db8")
		RARITY_RARE:
			return Color("b14cff")
		RARITY_LEGENDARY:
			return Color("ffb31a")
		_:
			return Color("b8b8b8")


static func rarity_amount(rarity: int) -> float:
	var index := clampi(rarity, RARITY_COMMON, RARITY_LEGENDARY)
	return float(RARITY_RANKS[index])


static func make_offer(stat_id: String, rarity: int) -> Dictionary:
	var clamped := clampi(rarity, RARITY_COMMON, RARITY_LEGENDARY)
	return {
		"id": stat_id,
		"rarity": clamped,
		"amount": rarity_amount(clamped),
	}


static func rarity_weights(luck_rank: float) -> PackedFloat32Array:
	var luck := maxf(luck_rank, 0.0)
	var boost := 1.0 + LUCK_WEIGHT * luck
	return PackedFloat32Array([
		RARITY_WEIGHTS[0] / (1.0 + LUCK_COMMON_SHRINK * luck),
		RARITY_WEIGHTS[1] * boost,
		RARITY_WEIGHTS[2] * boost * boost,
		RARITY_WEIGHTS[3] * pow(boost, 3.0),
	])


static func roll_rarity(rng: RandomNumberGenerator, luck_rank: float) -> int:
	var weights := rarity_weights(luck_rank)
	var total := 0.0
	for weight: float in weights:
		total += weight
	if rng == null or total <= 0.0:
		return RARITY_COMMON
	var roll := rng.randf() * total
	var acc := 0.0
	for index in weights.size():
		acc += weights[index]
		if roll < acc:
			return index
	return RARITY_COMMON


static func offer_boost_text(stat_id: String, amount: float, current := 0.0) -> String:
	var from_rank := maxf(current, 0.0)
	var to_rank := from_rank + maxf(amount, 0.0)
	var pct := int(round((CrawlerRules.upgrade_boost_f(to_rank)
		- CrawlerRules.upgrade_boost_f(from_rank)) * 100.0))
	match stat_id:
		STAT_HEALTH:
			return "+%d HP" % int(round(HEALTH_PER_RANK * amount))
		STAT_DEXTERITY:
			return "+%d%% walk" % pct
		STAT_FLIGHT:
			return "+%.1fs flight" % (CrawlerRules.FLIGHT_SECONDS
				* (CrawlerRules.upgrade_scale_f(to_rank)
					- CrawlerRules.upgrade_scale_f(from_rank)))
		STAT_DODGE:
			return "+%d%% dodge" % pct
		STAT_DEFENSE:
			return "+%d%% defense" % pct
		STAT_JUKE:
			return "-%.2fs juke" % (JUKE_COOLDOWN_PER_RANK * amount)
		STAT_JUKE_DISTANCE:
			return "+%.1fm dash" % (JUKE_DISTANCE_PER_RANK * amount)
		STAT_DAMAGE:
			return "+%d%% damage" % pct
		STAT_KNOCKBACK:
			return "+%d%% knockback" % pct
		STAT_RANGE:
			return "+%d%% range" % pct
		STAT_CAST:
			return "-%.2fs cast" % (CAST_PER_RANK * amount)
		STAT_LUCK:
			return "+%.2f luck" % amount
		STAT_ELEMENTAL:
			return "+%d%% elemental" % pct
		STAT_GOLD:
			return "+%d%% gold" % pct
		STAT_XP:
			return "+%d%% XP" % pct
		STAT_GEMS:
			return "+%d%% gems" % pct
		_:
			return "+%.2f" % amount


func luck_rank() -> float:
	var luck := rank_of(STAT_LUCK) + float(CrawlerMeta.rank_of(STAT_LUCK))
	luck += HAT_LUCK_BONUS * float(hat_effect_rank(FX_LUCK))
	return luck


func offer_rng() -> RandomNumberGenerator:
	if _offer_rng == null:
		_offer_rng = RandomNumberGenerator.new()
		_offer_rng.randomize()
	return _offer_rng


func seed_offers(seed: int) -> void:
	offer_rng().seed = seed


func offer_for(stat_id: String) -> Dictionary:
	for raw: Variant in level_offers:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == stat_id:
			return raw
	return {}


func force_level_offers(offers: Array) -> void:
	level_offers = []
	for raw: Variant in offers:
		if raw is Dictionary:
			var offer := _sanitize_offer(raw)
			if not offer.is_empty():
				level_offers.append(offer)
	remember()


func reroll_price() -> int:
	return REROLL_BASE << clampi(reroll_uses, 0, REROLL_USES_CAP)


func can_reroll_offers() -> bool:
	return unspent > 0 and has_gold(reroll_price())


func pay_reroll() -> bool:
	var price := reroll_price()
	if not spend_gold(price):
		return false
	reroll_uses += 1
	remember()
	return true


func reroll_level_offers() -> bool:
	if unspent <= 0:
		return false
	if not pay_reroll():
		return false
	roll_level_offers()
	changed.emit()
	return true


func ensure_level_offers() -> Array:
	if unspent <= 0:
		level_offers = []
		return level_offers
	if not level_offers.is_empty():
		return level_offers
	return roll_level_offers()


func roll_level_offers() -> Array:
	level_offers = []
	if unspent <= 0:
		return level_offers
	var pool: Array = LEVEL_STATS.duplicate()
	var luck := luck_rank()
	var rng := offer_rng()
	var count := mini(LEVEL_OFFER_COUNT, pool.size())
	for _index in count:
		var pick := rng.randi_range(0, pool.size() - 1)
		var stat_id := str(pool[pick])
		pool.remove_at(pick)
		level_offers.append(make_offer(stat_id, roll_rarity(rng, luck)))
	remember()
	return level_offers


func _sanitize_offer(raw: Dictionary) -> Dictionary:
	var stat_id := str(raw.get("id", ""))
	if not is_level_stat(stat_id):
		return {}
	var rarity := clampi(int(raw.get("rarity", RARITY_COMMON)),
		RARITY_COMMON, RARITY_LEGENDARY)
	var amount := float(raw.get("amount", rarity_amount(rarity)))
	if amount <= 0.0:
		amount = rarity_amount(rarity)
	return {
		"id": stat_id,
		"rarity": rarity,
		"amount": amount,
	}


static func card_price(catalog_id: String) -> int:
	if ABILITY_PRICES.has(catalog_id):
		return STORE_ABILITY_PRICE
	if SHOP_PRICES.has(catalog_id):
		return STORE_MOD_PRICE
	return 0


static func ability_price(catalog_id: String) -> int:
	return STORE_ABILITY_PRICE if ABILITY_PRICES.has(catalog_id) else 0


static func ability_stock() -> PackedStringArray:
	var stock := PackedStringArray()
	if CrawlerRules.sandbox():
		for id: String in CrawlerCatalog.ids():
			if ability_price(id) <= 0 or not CrawlerCatalog.is_ability(id):
				continue
			stock.append(id)
		return stock
	for id: String in CrawlerRules.ENABLED_ABILITIES:
		if ability_price(id) <= 0 or not CrawlerCatalog.is_ability(id):
			continue
		stock.append(id)
	return stock


static func upgrade_price(rank: int, _catalog_id := "") -> int:
	return UPGRADE_BASE * (1 << maxi(rank, 0))


static func shop_stock() -> PackedStringArray:
	var mods := PackedStringArray()
	for id: String in CrawlerCatalog.ids():
		if card_price(id) <= 0 or not CrawlerCatalog.is_modifier(id):
			continue
		mods.append(id)
	return mods


func gold_is_unlimited() -> bool:
	return gold_unlimited or CrawlerRules.sandbox_infinite_gold()


func gold_text() -> String:
	return "INF" if gold_is_unlimited() else str(gold)


## Shop tiles compare this against a price. Infinite gold has to look rich
## enough to enable every button without writing a second affordance path.
func purse_gold() -> int:
	return CrawlerRules.SANDBOX_GOLD if gold_is_unlimited() else gold


func has_gold(amount: int) -> bool:
	return amount <= 0 or gold_is_unlimited() or gold >= amount


func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return false
	if gold_is_unlimited():
		return true
	if gold < amount:
		return false
	gold -= amount
	remember()
	changed.emit()
	return true


func refund_gold(amount: int) -> void:
	if amount <= 0 or gold_is_unlimited():
		return
	gold += amount
	remember()
	changed.emit()


func grant_sandbox_gold() -> void:
	gold = CrawlerRules.SANDBOX_GOLD
	remember()
	changed.emit()


func grant_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	remember()
	changed.emit()


func set_shops_unlimited(enabled: bool) -> void:
	if shops_unlimited == enabled:
		return
	shops_unlimited = enabled
	remember()
	changed.emit()


func set_gold_unlimited(enabled: bool) -> void:
	if gold_unlimited == enabled:
		return
	gold_unlimited = enabled
	remember()
	changed.emit()


static func is_city_hat(item_id: String) -> bool:
	return not item_id.is_empty() and HAT_STOCK.has(item_id)


static func hat_stock() -> PackedStringArray:
	return PackedStringArray(HAT_STOCK)


static func hat_price(item_id: String) -> int:
	return HAT_PRICE if is_city_hat(item_id) else 0


static func hat_blurb(item_id: String, owned := false) -> String:
	match item_id:
		HAT_ID:
			return (
				"A city-made propeller cap. Flight time and dexterity jump while it is on."
				if owned
				else "A city-made propeller cap. Putting it on boosts flight time and dexterity a lot."
			)
		HAT_WARD:
			return (
				"A pale halo. The bubble takes one hit, then comes back after a short wait."
				if owned
				else "A pale halo. A thin iridescent bubble takes one hit, then comes back after a short wait."
			)
		HAT_LUCK:
			return (
				"A city-made fortune cap. Luck jumps while it is on."
				if owned
				else "A city-made fortune cap. Putting it on boosts luck a lot."
			)
		HAT_KIT:
			return (
				"A city-made visor. Ability mods can be moved anywhere while it is on."
				if owned
				else "A city-made visor. Putting it on lets you move ability mods anywhere."
			)
		HAT_MISSILE:
			return (
				"A city-made wizard hat. It looses a few homing missiles at the nearest mob."
				if owned
				else "A city-made wizard hat. Putting it on looses a few homing missiles at the nearest mob."
			)
		HAT_MINE:
			return (
				"A city-made hard hat. It drops a mine at your feet that bursts after a second."
				if owned
				else "A city-made hard hat. Putting it on drops a mine at your feet that bursts after a second."
			)
		HAT_VAMPIRE:
			return (
				"City-cut devil horns. Damage you deal pulls a little health back."
				if owned
				else "City-cut devil horns. Putting them on pulls a little health back from damage you deal."
			)
		HAT_PHASE:
			return (
				"A city-made space helm. Incoming projectiles sometimes pass through."
				if owned
				else "A city-made space helm. Putting it on lets incoming projectiles sometimes pass through."
			)
		HAT_ORDINANCE:
			return (
				"A city-made combat helm. Explosive damage does not land."
				if owned
				else "A city-made combat helm. Putting it on stops explosive damage."
			)
		HAT_RUBBER:
			return (
				"A city-made yellow beanie. Shock does not land."
				if owned
				else "A city-made yellow beanie. Putting it on stops shock."
			)
		HAT_LEARNED:
			return (
				"A city-made deerstalker. A fourth ability can be equipped."
				if owned
				else "A city-made deerstalker. Putting it on opens a fourth ability slot."
			)
		HAT_JUKE:
			return (
				"A city-made ball cap. Juking through a foe hurts them."
				if owned
				else "A city-made ball cap. Putting it on hurts foes you juke through."
			)
		HAT_REPEATER:
			return (
				"City headphones. They fire every equipped ability once a second."
				if owned
				else "City headphones. Putting them on fires every equipped ability once a second."
			)
		HAT_FOOL:
			return (
				"A city-made party hat. A hit throws you a short way, or rarely a very long way."
				if owned
				else "A city-made party hat. Putting it on makes every hit throw you somewhere else."
			)
		HAT_BAZAAR:
			return (
				"A city-made fedora. Every stall stays open while it is on."
				if owned
				else "A city-made fedora. Putting it on opens every city stall."
			)
		_:
			return ItemDB.description(item_id)


func buy_hat(item_id := HAT_ID, city := "") -> bool:
	if item_id.is_empty() or not is_city_hat(item_id):
		return false
	var price := hat_shop_price(city)
	if price <= 0 or not spend_gold(price):
		return false
	var uid := grant_hat(item_id, true)
	if uid.is_empty():
		gold += price
		remember()
		changed.emit()
		return false
	mark_hat_bought(city)
	return true


func grant_hat(item_id: String, wear := false) -> String:
	if item_id.is_empty() or not is_city_hat(item_id):
		return ""
	var uid := item_id
	if owns_hat(item_id):
		uid = _mint_hat_uid()
		_store_hat_record(uid, item_id, ItemDB.title(item_id),
			hat_blurb(item_id, true), _base_hat_effects(item_id))
	owned_hats.append(uid)
	if wear or worn_hat.is_empty():
		worn_hat = uid
	remember()
	changed.emit()
	return uid


func note_worn(item_id: String) -> void:
	if item_id == worn_hat:
		return
	if not item_id.is_empty() and not owns_hat(item_id):
		return
	worn_hat = item_id
	remember()
	changed.emit()


## Puts the home-screen creator hat onto this run so its mesh, tint, and city
## effects survive Start Game / online. Saved runs that already wear a hat keep
## that copy.
func seed_look_hat(look: Dictionary) -> String:
	var worn_raw: Variant = look.get("worn", {})
	if not worn_raw is Dictionary:
		return worn_hat
	var hat_id := str((worn_raw as Dictionary).get("hat", ""))
	if hat_id.is_empty() or not CrawlerMeta.owns_hat(hat_id):
		return worn_hat
	if is_city_hat(hat_id):
		if hat_count(hat_id) <= 0:
			return grant_hat(hat_id, true)
		if worn_hat.is_empty() or hat_model(worn_hat) != hat_id:
			for uid: String in owned_hats:
				if hat_model(uid) == hat_id:
					note_worn(uid)
					return uid
		return worn_hat
	if not owned_hats.has(hat_id):
		owned_hats.append(hat_id)
	if worn_hat != hat_id:
		worn_hat = hat_id
		remember()
		changed.emit()
	return hat_id


func owns_hat(item_id: String) -> bool:
	return not item_id.is_empty() and owned_hats.has(item_id)


static func is_city_cape(item_id: String) -> bool:
	return not item_id.is_empty() and CAPE_STOCK.has(item_id)


static func cape_stock() -> PackedStringArray:
	return PackedStringArray(CAPE_STOCK)


static func cape_price(item_id: String) -> int:
	return int(CAPE_PRICES.get(item_id, 0))


static func cape_blurb(item_id: String, owned := false) -> String:
	match item_id:
		CAPE_ID:
			return (
				"A blank white cape. It hangs from the shoulders and follows the wind."
				if owned
				else "A blank white cape. Buy it and it hangs on. Colour comes later."
			)
		CAPE_GOLD:
			return (
				"A city-made gold cape. Q makes you sparkle and bounce every hit back for a few seconds."
				if owned
				else "A city-made gold cape. Putting it on lets Q bounce every hit back for a few seconds."
			)
		_:
			return ItemDB.description(item_id)


func buy_cape(item_id := CAPE_ID) -> bool:
	if item_id.is_empty() or owns_cape(item_id) or not is_city_cape(item_id):
		return false
	var price := cape_price(item_id)
	if price <= 0 or not spend_gold(price):
		return false
	return grant_cape(item_id, true)


func grant_cape(item_id: String, wear := false) -> bool:
	if item_id.is_empty() or not is_city_cape(item_id) or owns_cape(item_id):
		return false
	owned_capes.append(item_id)
	if wear or worn_cape.is_empty():
		worn_cape = item_id
	remember()
	changed.emit()
	return true


func note_worn_cape(item_id: String) -> void:
	if item_id == worn_cape:
		return
	if not item_id.is_empty() and not owns_cape(item_id):
		return
	worn_cape = item_id
	remember()
	changed.emit()


func owns_cape(item_id: String) -> bool:
	return not item_id.is_empty() and owned_capes.has(item_id)


func wearing_gold_cape() -> bool:
	return worn_cape == CAPE_GOLD


func cape_has_ability(item_id := worn_cape) -> bool:
	return item_id == CAPE_GOLD


func seed_look_cape(look: Dictionary) -> String:
	var worn_raw: Variant = look.get("worn", {})
	if not worn_raw is Dictionary:
		return worn_cape
	var cape_id := str((worn_raw as Dictionary).get("cape", ""))
	if cape_id.is_empty() or not CrawlerMeta.owns_cape(cape_id):
		return worn_cape
	if is_city_cape(cape_id):
		if not owns_cape(cape_id):
			grant_cape(cape_id, true)
			return worn_cape
		if worn_cape != cape_id:
			note_worn_cape(cape_id)
		return worn_cape
	if not owned_capes.has(cape_id):
		owned_capes.append(cape_id)
	if worn_cape != cape_id:
		worn_cape = cape_id
		remember()
		changed.emit()
	return cape_id


static func quest_stock() -> PackedStringArray:
	return PackedStringArray(QUEST_ORDER)


static func quest_price(quest_id: String) -> int:
	return int(QUEST_PRICES.get(quest_id, 0))


static func quest_title(quest_id: String, encounter := "") -> String:
	match quest_id:
		QUEST_TOWER:
			return "Meridian Tower"
		QUEST_CASTLE:
			return "Stormwatch Castle"
		QUEST_BOSS:
			if encounter == CrawlerRules.BOSS_ENCOUNTER_TREE:
				return QUEST_TREE_TITLE
			return "Boss Site"
		_:
			return quest_id


static func quest_blurb(quest_id: String, encounter := "") -> String:
	match quest_id:
		QUEST_TOWER:
			return "Marks the nearest unmarked office. Tilde points there once you buy it or walk there."
		QUEST_CASTLE:
			return "Marks the nearest unmarked castle. Tilde points there once you buy it or walk there."
		QUEST_BOSS:
			if encounter == CrawlerRules.BOSS_ENCOUNTER_TREE:
				return "Marks the giant tree battle. Tilde points there once you buy it."
			return "Marks the nearest unmarked boss site. Tilde points there once you buy it."
		_:
			return ""


static func quest_matches_site(quest_id: String, site_id: String) -> bool:
	if quest_id.is_empty() or site_id.is_empty():
		return false
	if CrawlerRules.is_boss_id(quest_id):
		return CrawlerRules.is_boss_id(site_id)
	if CrawlerRules.is_castle_id(quest_id):
		return CrawlerRules.is_castle_id(site_id)
	if CrawlerRules.is_office_id(quest_id):
		return CrawlerRules.is_office_id(site_id)
	return quest_id == site_id


func quest_reveal_for(quest_id: String) -> String:
	for site_id: String in quest_reveals:
		if quest_matches_site(quest_id, site_id):
			return site_id
	return ""


func owns_quest(quest_id: String) -> bool:
	return not quest_id.is_empty() and owned_quests.has(quest_id)


func buy_quest(quest_id: String) -> bool:
	var price := quest_price(quest_id)
	if price <= 0 or owns_quest(quest_id):
		return false
	if not spend_gold(price):
		return false
	owned_quests.append(quest_id)
	remember()
	changed.emit()
	return true


func site_unlocked(site_id: String) -> bool:
	return not site_id.is_empty() and unlocked_sites.has(site_id)


func unlock_site(site_id: String) -> bool:
	if site_id.is_empty() or unlocked_sites.has(site_id):
		return false
	unlocked_sites.append(site_id)
	remember()
	return true


func award_site_gems() -> int:
	var gems := scaled_site_gems()
	gems_earned += gems
	CrawlerMeta.add_gems(gems)
	remember()
	changed.emit()
	return gems


func has_respawn_ticket() -> bool:
	return respawn_tickets > 0


func buy_respawn_ticket() -> bool:
	if not has_gold(TICKET_GOLD) or CrawlerMeta.gems() < TICKET_GEMS:
		return false
	if not CrawlerMeta.spend_gems(TICKET_GEMS):
		return false
	if not spend_gold(TICKET_GOLD):
		CrawlerMeta.add_gems(TICKET_GEMS)
		return false
	respawn_tickets += 1
	remember()
	changed.emit()
	return true


func spend_respawn_ticket() -> bool:
	if respawn_tickets <= 0:
		return false
	respawn_tickets -= 1
	remember()
	changed.emit()
	return true


func run_summary() -> String:
	var site_line := _count_line(
		unlocked_sites.size(), "site discovered", "sites discovered")
	if not unlocked_sites.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for site_id: String in unlocked_sites:
			names.append(site_title(site_id))
		site_line += "\n" + ", ".join(names)
	return "%s\n%s\n%s" % [
		_count_line(kills, "mob killed", "mobs killed"),
		site_line,
		_count_line(gems_earned, "gem earned", "gems earned"),
	]


static func site_title(site_id: String) -> String:
	match site_id:
		CrawlerRules.START_SITE_ID:
			return CrawlerRules.START_SITE_TITLE
		CrawlerRules.CITY_SITE_ID:
			return CrawlerRules.CITY_SITE_TITLE
		CrawlerRules.CITY_CRESCENT_SITE_ID:
			return CrawlerRules.CITY_CRESCENT_TITLE
		CrawlerRules.CITY_LEE_SITE_ID:
			return CrawlerRules.CITY_LEE_TITLE
		_:
			if CrawlerRules.is_boss_id(site_id):
				return quest_title(QUEST_BOSS, CrawlerRun.boss_encounter(site_id))
			if CrawlerRules.is_castle_id(site_id):
				return quest_title(QUEST_CASTLE)
			if CrawlerRules.is_office_id(site_id):
				return quest_title(QUEST_TOWER)
			var titled := quest_title(site_id)
			return titled if titled != site_id else site_id


static func _count_line(count: int, singular: String, plural: String) -> String:
	return "%d %s" % [count, singular if count == 1 else plural]


func enter_site(site_id: String) -> bool:
	if site_id.is_empty():
		return false
	unlock_site(site_id)
	if last_entered_site == site_id:
		return false
	last_entered_site = site_id
	remember()
	return true


func wearing_shop_hat() -> bool:
	return hat_effect_rank(FX_DEX) > 0 or hat_effect_rank(FX_FLIGHT) > 0


func wearing_bazaar_hat() -> bool:
	return hat_effect_rank(FX_BAZAAR) > 0


func wearing_ward_hat() -> bool:
	return hat_effect_rank(FX_WARD) > 0


func wearing_luck_hat() -> bool:
	return hat_effect_rank(FX_LUCK) > 0


func wearing_kit_hat() -> bool:
	return hat_effect_rank(FX_KIT) > 0


func wearing_missile_hat() -> bool:
	return hat_effect_rank(FX_MISSILE) > 0


func wearing_mine_hat() -> bool:
	return hat_effect_rank(FX_MINE) > 0


func wearing_vampire_hat() -> bool:
	return hat_effect_rank(FX_VAMPIRE) > 0


func wearing_phase_hat() -> bool:
	return hat_effect_rank(FX_PHASE) > 0


func wearing_ordinance_hat() -> bool:
	return hat_effect_rank(FX_ORDINANCE) > 0


func wearing_rubber_hat() -> bool:
	return hat_effect_rank(FX_RUBBER) > 0


func wearing_learned_hat() -> bool:
	return hat_effect_rank(FX_LEARNED) > 0


func wearing_juke_hat() -> bool:
	return hat_effect_rank(FX_JUKE) > 0


func wearing_repeater_hat() -> bool:
	return hat_effect_rank(FX_REPEATER) > 0


func wearing_fool_hat() -> bool:
	return hat_effect_rank(FX_FOOL) > 0


func repeater_rank() -> int:
	return hat_effect_rank(FX_REPEATER)


func repeater_interval() -> float:
	var ranks := repeater_rank()
	if ranks <= 0:
		return CrawlerRules.REPEATER_HAT_INTERVAL
	return CrawlerRules.REPEATER_HAT_INTERVAL / (
		1.0 + CrawlerRules.REPEATER_HAT_INTERVAL_SHRINK * float(ranks - 1))


func ability_bar_slots() -> int:
	return CrawlerRules.ABILITY_SLOTS_MAX if wearing_learned_hat() \
		else CrawlerRules.ABILITY_SLOTS


func missile_rank() -> int:
	return hat_effect_rank(FX_MISSILE)


func missile_count() -> int:
	var ranks := missile_rank()
	if ranks <= 0:
		return 0
	return CrawlerRules.MISSILE_HAT_COUNT \
		+ CrawlerRules.MISSILE_HAT_EXTRA_PER_RANK * (ranks - 1)


func missile_interval() -> float:
	var ranks := missile_rank()
	if ranks <= 0:
		return CrawlerRules.MISSILE_HAT_INTERVAL
	return CrawlerRules.MISSILE_HAT_INTERVAL / (
		1.0 + CrawlerRules.MISSILE_HAT_INTERVAL_SHRINK * float(ranks - 1))


func missile_damage() -> float:
	var ranks := missile_rank()
	if ranks <= 0:
		return 0.0
	return CrawlerRules.MISSILE_HAT_DAMAGE \
		* (1.0 + CrawlerRules.MISSILE_HAT_DAMAGE_PER_RANK * float(ranks - 1)) \
		* damage_scale()


func missile_range() -> float:
	if missile_rank() <= 0:
		return 0.0
	return CrawlerRules.MISSILE_HAT_RANGE * range_scale()


func mine_rank() -> int:
	return hat_effect_rank(FX_MINE)


func mine_interval() -> float:
	var ranks := mine_rank()
	if ranks <= 0:
		return CrawlerRules.MINE_HAT_INTERVAL
	return CrawlerRules.MINE_HAT_INTERVAL / (
		1.0 + CrawlerRules.MINE_HAT_INTERVAL_SHRINK * float(ranks - 1))


func mine_damage() -> float:
	var ranks := mine_rank()
	if ranks <= 0:
		return 0.0
	return CrawlerRules.MINE_HAT_DAMAGE \
		* (1.0 + CrawlerRules.MINE_HAT_DAMAGE_PER_RANK * float(ranks - 1)) \
		* damage_scale()


func mine_radius() -> float:
	var ranks := mine_rank()
	if ranks <= 0:
		return 0.0
	return CrawlerRules.MINE_HAT_RADIUS \
		+ CrawlerRules.MINE_HAT_RADIUS_PER_RANK * float(ranks - 1)


func vampire_steal() -> float:
	var ranks := hat_effect_rank(FX_VAMPIRE)
	if ranks <= 0:
		return 0.0
	return CrawlerRules.VAMPIRE_STEAL \
		+ CrawlerRules.VAMPIRE_STEAL_PER_RANK * float(ranks - 1)


func phase_chance() -> float:
	var ranks := hat_effect_rank(FX_PHASE)
	if ranks <= 0:
		return 0.0
	return minf(
		CrawlerRules.PHASE_CHANCE
			+ CrawlerRules.PHASE_CHANCE_PER_RANK * float(ranks - 1),
		CrawlerRules.PHASE_CHANCE_MAX)


func juke_hat_damage() -> float:
	var ranks := hat_effect_rank(FX_JUKE)
	if ranks <= 0:
		return 0.0
	return CrawlerRules.JUKE_HAT_DAMAGE \
		* (1.0 + CrawlerRules.JUKE_HAT_DAMAGE_PER_RANK * float(ranks - 1)) \
		* damage_scale()


func hat_model(uid: String) -> String:
	if hat_ledger.has(uid):
		return str((hat_ledger[uid] as Dictionary).get("model", ""))
	if is_city_hat(uid) or ItemDB.slot_of(uid) == "hat":
		return uid
	return ""


func hat_title(uid: String) -> String:
	if hat_ledger.has(uid):
		return str((hat_ledger[uid] as Dictionary).get("title", ItemDB.title(uid)))
	return ItemDB.title(uid)


func hat_description(uid: String) -> String:
	if hat_ledger.has(uid):
		return str((hat_ledger[uid] as Dictionary).get("description", ""))
	return hat_blurb(uid, owns_hat(uid))


func hat_effects(uid: String) -> Dictionary:
	if not owns_hat(uid):
		return {}
	if hat_ledger.has(uid):
		var held: Variant = (hat_ledger[uid] as Dictionary).get("effects", {})
		return (held as Dictionary).duplicate() if held is Dictionary else {}
	return _base_hat_effects(uid)


func hat_effect_rank(effect: String, uid := "") -> int:
	var source := uid if not uid.is_empty() else worn_hat
	if source.is_empty() or not owns_hat(source):
		return 0
	return maxi(int(hat_effects(source).get(effect, 0)), 0)


func ward_charges() -> int:
	return hat_effect_rank(FX_WARD)


func hat_count(model: String) -> int:
	var total := 0
	for uid: String in owned_hats:
		if hat_model(uid) == model:
			total += 1
	return total


func preview_hat_merge(keep_uid: String, other_uid: String) -> Dictionary:
	if keep_uid.is_empty() or other_uid.is_empty() or keep_uid == other_uid \
			or not owns_hat(keep_uid) or not owns_hat(other_uid):
		return {}
	var model := hat_model(keep_uid)
	if model.is_empty():
		return {}
	var effects := add_hat_effects(hat_effects(keep_uid), hat_effects(other_uid))
	return {
		"model": model,
		"title": compose_hat_title(model, effects),
		"description": compose_hat_description(effects),
		"effects": effects,
	}


func merge_hats(keep_uid: String, other_uid: String, city := "") -> bool:
	var preview := preview_hat_merge(keep_uid, other_uid)
	var price := cap_merge_price(city)
	if preview.is_empty() or price <= 0 or not spend_gold(price):
		return false
	var uid := _mint_hat_uid()
	_store_hat_record(
		uid,
		str(preview.get("model", "")),
		str(preview.get("title", "")),
		str(preview.get("description", "")),
		preview.get("effects", {}) as Dictionary
	)
	_forget_hat(keep_uid)
	_forget_hat(other_uid)
	owned_hats.append(uid)
	if worn_hat.is_empty() or worn_hat == keep_uid or worn_hat == other_uid:
		worn_hat = uid
	remember()
	changed.emit()
	return true


static func add_hat_effects(left: Dictionary, right: Dictionary) -> Dictionary:
	var out := {}
	for key: String in HAT_FX_KEYS:
		var total := int(left.get(key, 0)) + int(right.get(key, 0))
		if total > 0:
			out[key] = total
	return out


static func compose_hat_title(model: String, effects: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var gale := maxi(int(effects.get(FX_DEX, 0)), int(effects.get(FX_FLIGHT, 0)))
	if gale > 0:
		parts.append(_hat_count_label(gale, "Gale"))
	var ward := int(effects.get(FX_WARD, 0))
	if ward > 0:
		parts.append(_hat_count_label(ward, "Ward"))
	var luck := int(effects.get(FX_LUCK, 0))
	if luck > 0:
		parts.append(_hat_count_label(luck, "Fortune"))
	var kit := int(effects.get(FX_KIT, 0))
	if kit > 0:
		parts.append(_hat_count_label(kit, "Bench"))
	var hex := int(effects.get(FX_MISSILE, 0))
	if hex > 0:
		parts.append(_hat_count_label(hex, "Hex"))
	var mine := int(effects.get(FX_MINE, 0))
	if mine > 0:
		parts.append(_hat_count_label(mine, "Trail"))
	var vampire := int(effects.get(FX_VAMPIRE, 0))
	if vampire > 0:
		parts.append(_hat_count_label(vampire, "Vampire"))
	var phase := int(effects.get(FX_PHASE, 0))
	if phase > 0:
		parts.append(_hat_count_label(phase, "Phase"))
	var ordinance := int(effects.get(FX_ORDINANCE, 0))
	if ordinance > 0:
		parts.append(_hat_count_label(ordinance, "Ordinance"))
	var rubber := int(effects.get(FX_RUBBER, 0))
	if rubber > 0:
		parts.append(_hat_count_label(rubber, "Rubber"))
	var learned := int(effects.get(FX_LEARNED, 0))
	if learned > 0:
		parts.append(_hat_count_label(learned, "Learned"))
	var juke := int(effects.get(FX_JUKE, 0))
	if juke > 0:
		parts.append(_hat_count_label(juke, "Juke"))
	var repeater := int(effects.get(FX_REPEATER, 0))
	if repeater > 0:
		parts.append(_hat_count_label(repeater, "Repeater"))
	var fool := int(effects.get(FX_FOOL, 0))
	if fool > 0:
		parts.append(_hat_count_label(fool, "Fool"))
	var bazaar := int(effects.get(FX_BAZAAR, 0))
	if bazaar > 0:
		parts.append(_hat_count_label(bazaar, "Bazaar"))
	var noun := str(HAT_NOUNS.get(model, "Cap"))
	if parts.is_empty():
		return ItemDB.title(model)
	return "%s %s" % [" ".join(parts), noun]


static func compose_hat_description(effects: Dictionary) -> String:
	var bits: PackedStringArray = PackedStringArray()
	var gale := maxi(int(effects.get(FX_DEX, 0)), int(effects.get(FX_FLIGHT, 0)))
	if gale > 0:
		bits.append("Flight time and dexterity jump%s." % _hat_stack_phrase(gale))
	var ward := int(effects.get(FX_WARD, 0))
	if ward > 0:
		bits.append(
			"A bubble takes %s, then comes back after a short wait." % (
				"one hit" if ward == 1 else "%d hits" % ward
			)
		)
	var luck := int(effects.get(FX_LUCK, 0))
	if luck > 0:
		bits.append("Luck jumps%s." % _hat_stack_phrase(luck))
	if int(effects.get(FX_KIT, 0)) > 0:
		bits.append("Ability mods can be moved anywhere.")
	var hex := int(effects.get(FX_MISSILE, 0))
	if hex > 0:
		var shots := CrawlerRules.MISSILE_HAT_COUNT \
			+ CrawlerRules.MISSILE_HAT_EXTRA_PER_RANK * (hex - 1)
		bits.append("It looses %d homing missiles at the nearest mob." % shots)
	var mine := int(effects.get(FX_MINE, 0))
	if mine > 0:
		bits.append("It drops a mine at your feet that bursts after a second%s." % (
			"" if mine == 1 else _hat_stack_phrase(mine)
		))
	var vampire := int(effects.get(FX_VAMPIRE, 0))
	if vampire > 0:
		bits.append("Dealt damage pulls a little health back%s." % _hat_stack_phrase(vampire))
	var phase := int(effects.get(FX_PHASE, 0))
	if phase > 0:
		bits.append("Incoming projectiles sometimes pass through%s." % _hat_stack_phrase(phase))
	if int(effects.get(FX_ORDINANCE, 0)) > 0:
		bits.append("Explosive damage does not land.")
	if int(effects.get(FX_RUBBER, 0)) > 0:
		bits.append("Shock does not land.")
	if int(effects.get(FX_LEARNED, 0)) > 0:
		bits.append("A fourth ability can be equipped.")
	var juke := int(effects.get(FX_JUKE, 0))
	if juke > 0:
		bits.append("Juking through a foe hurts them%s." % _hat_stack_phrase(juke))
	var repeater := int(effects.get(FX_REPEATER, 0))
	if repeater > 0:
		if repeater == 1:
			bits.append("It fires every equipped ability once a second.")
		else:
			bits.append("It fires every equipped ability more often.")
	if int(effects.get(FX_FOOL, 0)) > 0:
		bits.append("A hit throws you somewhere else.")
	if int(effects.get(FX_BAZAAR, 0)) > 0:
		bits.append("Every city stall stays open.")
	return " ".join(bits)


static func _hat_count_label(amount: int, word: String) -> String:
	if amount <= 1:
		return word
	if amount == 2:
		return "Twin %s" % word
	if amount == 3:
		return "Triple %s" % word
	return "%dx %s" % [amount, word]


static func _hat_stack_phrase(amount: int) -> String:
	if amount <= 1:
		return ""
	if amount == 2:
		return " twice as hard"
	return " %dx" % amount


static func _base_hat_effects(item_id: String) -> Dictionary:
	var held: Variant = HAT_BASE_EFFECTS.get(item_id, {})
	return (held as Dictionary).duplicate() if held is Dictionary else {}


func _mint_hat_uid() -> String:
	while true:
		var uid := "%s%d" % [HAT_UID_PREFIX, next_hat_serial]
		next_hat_serial += 1
		if not owns_hat(uid) and not hat_ledger.has(uid):
			return uid
	return ""


func _store_hat_record(
		uid: String,
		model: String,
		title: String,
		description: String,
		effects: Dictionary
	) -> void:
	hat_ledger[uid] = {
		"model": model,
		"title": title,
		"description": description,
		"effects": effects.duplicate(),
	}
	_publish_hat_item(uid)


func _forget_hat(uid: String) -> void:
	var listed := PackedStringArray()
	for held: String in owned_hats:
		if held != uid:
			listed.append(held)
	owned_hats = listed
	if hat_ledger.has(uid):
		hat_ledger.erase(uid)
	ItemDB.unregister_runtime_item(uid)
	if worn_hat == uid:
		worn_hat = ""


func _publish_hat_item(uid: String) -> void:
	if not hat_ledger.has(uid):
		return
	var record: Dictionary = hat_ledger[uid]
	var model := str(record.get("model", ""))
	ItemDB.register_runtime_item(uid, {
		"title": str(record.get("title", ItemDB.title(model))),
		"description": str(record.get("description", "")),
		"kind": ItemDB.KIND_APPAREL,
		"slot": "hat",
		"scene": ItemDB.scene_path(model),
		"tint": ItemDB.tint(model),
		"model": model,
	})


func _forget_hat_overlays() -> void:
	for uid: Variant in hat_ledger.keys():
		ItemDB.unregister_runtime_item(str(uid))


func _restore_hat_overlays() -> void:
	for uid: Variant in hat_ledger.keys():
		_publish_hat_item(str(uid))


func rank_of(stat_id: String) -> float:
	return maxf(float(ranks.get(stat_id, 0)), 0.0)


func combined_rank(stat_id: String) -> float:
	return rank_of(stat_id) + float(CrawlerMeta.rank_of(stat_id))


func health_maximum() -> float:
	return HEALTH_BASE + HEALTH_PER_RANK * float(combined_rank(STAT_HEALTH))


func boost_scale(stat_id: String) -> float:
	return CrawlerRules.upgrade_scale_f(combined_rank(stat_id))


func dex_scale() -> float:
	var scale := boost_scale(STAT_DEXTERITY)
	var ranks := hat_effect_rank(FX_DEX)
	if ranks > 0:
		scale *= pow(HAT_DEX, float(ranks))
	return scale


func flight_seconds() -> float:
	var seconds := CrawlerRules.FLIGHT_SECONDS * boost_scale(STAT_FLIGHT)
	var ranks := hat_effect_rank(FX_FLIGHT)
	if ranks > 0:
		seconds *= pow(HAT_FLIGHT, float(ranks))
	return seconds


func hero_body_id(owner: OnlinePlayer = null) -> String:
	var who := owner if owner != null else player
	if who != null and is_instance_valid(who):
		return who.body_id()
	return TRAIT_BODY


func character_damage_bonus(owner: OnlinePlayer = null) -> float:
	if hero_body_id(owner) != TRAIT_BODY:
		return 0.0
	return TRAIT_DAMAGE_PER_LEVEL * float(maxi(level, 0))


func damage_scale() -> float:
	return boost_scale(STAT_DAMAGE) * (1.0 + character_damage_bonus())


func knockback_scale() -> float:
	return boost_scale(STAT_KNOCKBACK)


func range_scale() -> float:
	return boost_scale(STAT_RANGE)


func elemental_scale() -> float:
	return boost_scale(STAT_ELEMENTAL)


func gold_scale() -> float:
	return boost_scale(STAT_GOLD)


func xp_scale() -> float:
	return boost_scale(STAT_XP)


func gem_scale() -> float:
	return boost_scale(STAT_GEMS)


static func apply_gain(base: int, scale: float) -> int:
	return maxi(int(round(float(maxi(base, 0)) * maxf(scale, 0.0))), 0)


func scaled_kill_gold(mob_level: int) -> int:
	return apply_gain(kill_gold(mob_level), gold_scale())


func scaled_kill_xp(mob_level: int, kind := "") -> int:
	return apply_gain(kill_xp(mob_level, kind), xp_scale())


func scaled_kill_gems(mob_level: int, roll := -1.0) -> int:
	var sample := roll
	if sample < 0.0:
		sample = offer_rng().randf()
	if sample >= CrawlerMeta.gem_drop_chance(luck_rank()):
		return 0
	return apply_gain(CrawlerMeta.kill_gems(mob_level), gem_scale())


func scaled_site_gems() -> int:
	return apply_gain(SITE_GEMS, gem_scale())


func dodge_chance() -> float:
	return minf(DODGE_MAX, CrawlerRules.upgrade_boost_f(combined_rank(STAT_DODGE)))


func defense_share() -> float:
	return minf(DEFENSE_MAX, CrawlerRules.upgrade_boost_f(combined_rank(STAT_DEFENSE)))


func juke_cooldown() -> float:
	return maxf(JUKE_COOLDOWN_MIN,
		JUKE_COOLDOWN_BASE - JUKE_COOLDOWN_PER_RANK * float(combined_rank(STAT_JUKE)))


func juke_distance() -> float:
	return JUKE_DISTANCE_BASE \
		+ JUKE_DISTANCE_PER_RANK * float(combined_rank(STAT_JUKE_DISTANCE))


func cast_trim() -> float:
	return CAST_PER_RANK * float(combined_rank(STAT_CAST))


func hero_stat_rows(owner: OnlinePlayer = null) -> Array:
	var who := owner if owner != null else player
	var rows: Array = []
	if hero_body_id(who) == TRAIT_BODY:
		rows.append({
			"id": TRAIT_LEVEL_DAMAGE,
			"title": "Noct",
			"description": "Gain 2% damage with every level.",
			"text": "+2% DMG / LV",
			"kind": "trait",
		})
	for stat_id: String in STAT_ORDER:
		rows.append({
			"id": stat_id,
			"title": stat_title(stat_id),
			"description": stat_blurb(stat_id),
			"text": hero_stat_text(stat_id, who),
		})
	return rows


func hero_stat_text(stat_id: String, _owner: OnlinePlayer = null) -> String:
	match stat_id:
		STAT_HEALTH:
			return _with_boost("%d HP" % int(round(HEALTH_BASE)),
				health_maximum() - HEALTH_BASE)
		STAT_DEXTERITY:
			var listed: Variant = PlayerStats.STATS.get("speed", {})
			var walk := 4.6
			if listed is Dictionary:
				walk = float((listed as Dictionary).get("base", 4.6))
			var base_pace := walk * CrawlerRules.SPEED_SCALE
			return _with_boost("%.1f m/s" % base_pace,
				base_pace * dex_scale() - base_pace)
		STAT_FLIGHT:
			return _with_boost("%.1f s" % CrawlerRules.FLIGHT_SECONDS,
				flight_seconds() - CrawlerRules.FLIGHT_SECONDS)
		STAT_DODGE:
			return _with_boost("0%", dodge_chance() * 100.0)
		STAT_DEFENSE:
			return _with_boost("0%", defense_share() * 100.0)
		STAT_JUKE:
			return _with_boost("%.2fs" % JUKE_COOLDOWN_BASE,
				juke_cooldown() - JUKE_COOLDOWN_BASE)
		STAT_JUKE_DISTANCE:
			return _with_boost("%.1f m" % JUKE_DISTANCE_BASE,
				juke_distance() - JUKE_DISTANCE_BASE)
		STAT_DAMAGE:
			return _with_boost("1.00x", damage_scale() - 1.0)
		STAT_KNOCKBACK:
			return _with_boost("1.00x", knockback_scale() - 1.0)
		STAT_RANGE:
			return _with_boost("1.00x", range_scale() - 1.0)
		STAT_CAST:
			var wait := CrawlerRules.field_cast_time(
				CrawlerRules.FIELD_CAST, cast_trim())
			return _with_boost("%.2fs" % CrawlerRules.FIELD_CAST,
				wait - CrawlerRules.FIELD_CAST)
		STAT_ELEMENTAL:
			return _with_boost("1.00x", elemental_scale() - 1.0)
		STAT_GOLD:
			return _with_boost("1.00x", gold_scale() - 1.0)
		STAT_XP:
			return _with_boost("1.00x", xp_scale() - 1.0)
		STAT_GEMS:
			return _with_boost("1.00x", gem_scale() - 1.0)
		STAT_LUCK:
			return _with_boost("base", luck_rank())
		_:
			return _with_boost("r0", rank_of(stat_id))


func _with_boost(base_text: String, delta: float) -> String:
	if is_zero_approx(delta):
		return base_text
	var bit := "%d" % int(round(delta)) if is_equal_approx(delta, round(delta)) \
		else "%.2f" % delta if absf(delta) < 1.0 else "%.1f" % delta
	if delta > 0.0:
		bit = "+" + bit
	return "%s (%s)" % [base_text, bit]


func lifetime_xp() -> int:
	var total := maxi(xp, 0)
	for at in range(1, maxi(level, 1)):
		total += xp_needed(at)
	return total


func xp_to_next() -> int:
	return xp_needed(level)


func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"gold": gold,
		"unspent": unspent,
		"ranks": ranks.duplicate(),
		"hats": Array(owned_hats),
		"worn": worn_hat,
		"hat_ledger": hat_ledger.duplicate(true),
		"hat_serial": next_hat_serial,
		"capes": Array(owned_capes),
		"worn_cape": worn_cape,
		"quests": Array(owned_quests),
		"offers": level_offers.duplicate(true),
		"rerolls": reroll_uses,
		"sites": Array(unlocked_sites),
		"last_site": last_entered_site,
		"kills": kills,
		"gems": gems_earned,
		"tickets": respawn_tickets,
		"statue_seed": statue_seed,
		"statues": Array(claimed_statues),
		"rest_hp": Array(rested_health_cities),
		"rest_ammo": Array(rested_ammo_cities),
		"cap_merge": Array(fused_hat_cities),
		"hat_buy": Array(hat_buy_cities),
		"shop_slots": _clone_shop_table(shop_stock_slots),
		"shop_upgrades": _clone_shop_table(shop_upgrade_picks),
		"shops_unlimited": shops_unlimited,
		"gold_unlimited": gold_unlimited,
		"run_path": run_path,
		"quest_reveals": Array(quest_reveals),
	}


func from_dict(payload: Dictionary) -> void:
	level = maxi(int(payload.get("level", 1)), 1)
	xp = maxi(int(payload.get("xp", 0)), 0)
	gold = maxi(int(payload.get("gold", 0)), 0)
	unspent = maxi(int(payload.get("unspent", 0)), 0)
	reroll_uses = clampi(int(payload.get("rerolls", 0)), 0, REROLL_USES_CAP)
	var next_ranks: Variant = payload.get("ranks", {})
	if next_ranks is Dictionary:
		for key in STAT_ORDER:
			ranks[key] = maxf(float((next_ranks as Dictionary).get(key, 0)), 0.0)
	level_offers = []
	var offers: Variant = payload.get("offers", [])
	if offers is Array:
		for raw: Variant in offers:
			if raw is Dictionary:
				var offer := _sanitize_offer(raw)
				if not offer.is_empty():
					level_offers.append(offer)
	_forget_hat_overlays()
	hat_ledger = {}
	var ledger_raw: Variant = payload.get("hat_ledger", {})
	if ledger_raw is Dictionary:
		for key: Variant in (ledger_raw as Dictionary).keys():
			var uid := str(key)
			var raw: Variant = (ledger_raw as Dictionary).get(key, {})
			if uid.is_empty() or not (raw is Dictionary):
				continue
			var record := raw as Dictionary
			hat_ledger[uid] = {
				"model": str(record.get("model", "")),
				"title": str(record.get("title", "")),
				"description": str(record.get("description", "")),
				"effects": (record.get("effects", {}) as Dictionary).duplicate() \
					if record.get("effects", {}) is Dictionary else {},
			}
	next_hat_serial = maxi(int(payload.get("hat_serial", 1)), 1)
	owned_hats = PackedStringArray()
	var hats: Variant = payload.get("hats", [])
	if hats is Array:
		for raw: Variant in hats:
			var item_id := str(raw)
			if not item_id.is_empty() and not owned_hats.has(item_id):
				owned_hats.append(item_id)
	worn_hat = str(payload.get("worn", ""))
	if not worn_hat.is_empty() and not owns_hat(worn_hat):
		worn_hat = ""
	_restore_hat_overlays()
	owned_capes = PackedStringArray()
	var had_fool_cape := false
	var capes: Variant = payload.get("capes", [])
	if capes is Array:
		for raw: Variant in capes:
			var cape_id := str(raw)
			if cape_id == "crawler_fool_cape":
				had_fool_cape = true
				continue
			if not cape_id.is_empty() and not owned_capes.has(cape_id):
				owned_capes.append(cape_id)
	worn_cape = str(payload.get("worn_cape", ""))
	if worn_cape == "crawler_fool_cape":
		had_fool_cape = true
		worn_cape = ""
	if not worn_cape.is_empty() and not owns_cape(worn_cape):
		worn_cape = ""
	if had_fool_cape and not owns_hat(HAT_FOOL):
		owned_hats.append(HAT_FOOL)
		if worn_hat.is_empty():
			worn_hat = HAT_FOOL
	owned_quests = PackedStringArray()
	var quests: Variant = payload.get("quests", [])
	if quests is Array:
		for raw: Variant in quests:
			var quest_id := str(raw)
			if not quest_id.is_empty() and not owned_quests.has(quest_id):
				owned_quests.append(quest_id)
	unlocked_sites = PackedStringArray()
	var sites: Variant = payload.get("sites", [])
	if sites is Array:
		for raw: Variant in sites:
			var site_id := str(raw)
			if not site_id.is_empty() and not unlocked_sites.has(site_id):
				unlocked_sites.append(site_id)
	last_entered_site = str(payload.get("last_site", ""))
	kills = maxi(int(payload.get("kills", 0)), 0)
	gems_earned = maxi(int(payload.get("gems", 0)), 0)
	respawn_tickets = maxi(int(payload.get("tickets", 0)), 0)
	statue_seed = int(payload.get("statue_seed", 0))
	claimed_statues = PackedStringArray()
	var statues: Variant = payload.get("statues", [])
	if statues is Array:
		for raw: Variant in statues:
			var kind := str(raw)
			if not kind.is_empty() and not claimed_statues.has(kind):
				claimed_statues.append(kind)
	rested_health_cities = PackedStringArray()
	var rest_hp: Variant = payload.get("rest_hp", [])
	if rest_hp is Array:
		for raw: Variant in rest_hp:
			var city := str(raw)
			if not city.is_empty() and not rested_health_cities.has(city):
				rested_health_cities.append(city)
	rested_ammo_cities = PackedStringArray()
	var rest_ammo: Variant = payload.get("rest_ammo", [])
	if rest_ammo is Array:
		for raw: Variant in rest_ammo:
			var city := str(raw)
			if not city.is_empty() and not rested_ammo_cities.has(city):
				rested_ammo_cities.append(city)
	fused_hat_cities = PackedStringArray()
	var cap_merge: Variant = payload.get("cap_merge", [])
	if cap_merge is Array:
		for raw: Variant in cap_merge:
			var city := str(raw)
			if not city.is_empty() and not fused_hat_cities.has(city):
				fused_hat_cities.append(city)
	hat_buy_cities = PackedStringArray()
	var hat_buy: Variant = payload.get("hat_buy", [])
	if hat_buy is Array:
		for raw: Variant in hat_buy:
			var city := str(raw)
			if not city.is_empty() and not hat_buy_cities.has(city):
				hat_buy_cities.append(city)
	shop_stock_slots = _clone_shop_table(payload.get("shop_slots", {}))
	shop_upgrade_picks = _clone_shop_table(payload.get("shop_upgrades", {}))
	shops_unlimited = bool(payload.get("shops_unlimited", false))
	gold_unlimited = bool(payload.get("gold_unlimited", false))
	run_path = str(payload.get("run_path", ""))
	quest_reveals = PackedStringArray()
	var reveals: Variant = payload.get("quest_reveals", [])
	if reveals is Array:
		for raw: Variant in reveals:
			var site_id := str(raw)
			if not site_id.is_empty() and not quest_reveals.has(site_id):
				quest_reveals.append(site_id)
	if not run_path.is_empty() and not CrawlerRun.active():
		CrawlerRun.load_path(run_path)


func remember() -> void:
	session_payload = to_dict()
