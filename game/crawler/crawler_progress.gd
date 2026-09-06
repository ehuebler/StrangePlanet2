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
const STAT_DAMAGE := "damage"
const STAT_KNOCKBACK := "knockback"
const STAT_RANGE := "range"
const STAT_LUCK := "luck"
const LEVEL_STATS := [
	STAT_HEALTH, STAT_DEXTERITY, STAT_FLIGHT, STAT_DODGE, STAT_DEFENSE,
	STAT_JUKE, STAT_DAMAGE, STAT_KNOCKBACK, STAT_RANGE, STAT_LUCK,
]
const STAT_ORDER := [
	STAT_HEALTH, STAT_DEXTERITY, STAT_FLIGHT, STAT_DODGE, STAT_DEFENSE,
	STAT_JUKE, STAT_DAMAGE, STAT_KNOCKBACK, STAT_RANGE, STAT_LUCK,
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

const XP_BASE := 36
const XP_GROWTH := 18
const GOLD_BASE := 8
const GOLD_PER_LEVEL := 6
const XP_KILL_BASE := 12
const XP_PER_LEVEL := 12
const HEALTH_BASE := 100.0
const HEALTH_PER_RANK := 22.0
const DEX_PER_RANK := 0.14
const FLIGHT_PER_RANK := 0.20
const DAMAGE_PER_RANK := 0.12
const KNOCKBACK_PER_RANK := 0.12
const RANGE_PER_RANK := 0.12
const DODGE_PER_RANK := 0.06
const DODGE_MAX := 0.40
const DEFENSE_PER_RANK := 0.08
const DEFENSE_MAX := 0.60
const JUKE_COOLDOWN_BASE := 0.85
const JUKE_COOLDOWN_PER_RANK := 0.10
const JUKE_COOLDOWN_MIN := 0.25
const HAT_ID := "crawler_gale_hat"
const HAT_WARD := "crawler_ward_hat"
const HAT_LUCK := "crawler_luck_hat"
const HAT_PRICE := 45
const HAT_WARD_PRICE := 40
const HAT_LUCK_PRICE := 50
const HAT_LUCK_BONUS := 8.0
const WARD_RESPAWN := 8.0
const HAT_STOCK := [HAT_ID, HAT_WARD, HAT_LUCK]
const HAT_PRICES := {
	HAT_ID: HAT_PRICE,
	HAT_WARD: HAT_WARD_PRICE,
	HAT_LUCK: HAT_LUCK_PRICE,
}
const QUEST_TOWER := "office_tower"
const QUEST_CASTLE := "castle"
const QUEST_ORDER := [QUEST_TOWER, QUEST_CASTLE]
const QUEST_PRICES := {
	QUEST_TOWER: 30,
	QUEST_CASTLE: 30,
}
const TICKET_GOLD := 50
const TICKET_GEMS := 10
const SITE_GEMS := 8
const HAT_DEX := 1.45
const HAT_FLIGHT := 1.55
const UPGRADE_BASE := 28
const UPGRADE_GROWTH := 16
const BIG_UPGRADE_BASE := 80
const BIG_UPGRADE_GROWTH := 1.55
const SHOP_PRICES := {
	"wobble": 22,
	"big": 22,
}
const ABILITY_PRICES := {
	"laser_eyes": 36,
	"meteor_punch": 38,
	"starfire": 40,
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
	STAT_DAMAGE: 0,
	STAT_KNOCKBACK: 0,
	STAT_RANGE: 0,
	STAT_LUCK: 0,
}
var owned_hats: PackedStringArray = PackedStringArray()
var worn_hat := ""
var owned_quests: PackedStringArray = PackedStringArray()
var level_offers: Array = []
var last_levels_gained := 0
var reroll_uses := 0
var unlocked_sites: PackedStringArray = PackedStringArray()
var last_entered_site := ""
var kills := 0
var gems_earned := 0
var respawn_tickets := 0
var _offer_rng: RandomNumberGenerator = null


static func clear_session() -> void:
	session_payload = {}


static func xp_needed(at_level: int) -> int:
	return XP_BASE + XP_GROWTH * maxi(at_level - 1, 0)


static func kill_gold(mob_level: int) -> int:
	return GOLD_BASE + GOLD_PER_LEVEL * maxi(mob_level, 1)


static func kill_xp(mob_level: int, kind := "") -> int:
	var listed := int(CrawlerMobs.number(kind, mob_level, "xp", 0.0))
	if listed > 0:
		return listed
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
		STAT_DAMAGE:
			return "Damage"
		STAT_KNOCKBACK:
			return "Knockback"
		STAT_RANGE:
			return "Range"
		STAT_LUCK:
			return "Luck"
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
		STAT_DAMAGE:
			return "Ability damage multiplier."
		STAT_KNOCKBACK:
			return "Ability knockback multiplier."
		STAT_RANGE:
			return "Ability range multiplier."
		STAT_LUCK:
			return "Better odds of rare and legendary level-up boosts."
		_:
			return ""


func bind(owner: OnlinePlayer) -> void:
	player = owner


func restore_or_seed() -> void:
	if not session_payload.is_empty():
		from_dict(session_payload)
	remember()
	changed.emit()


func award_kill(mob_level: int, kind := "") -> void:
	kills += 1
	gems_earned += CrawlerMeta.kill_gems(mob_level)
	gold += kill_gold(mob_level)
	xp += kill_xp(mob_level, kind)
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


func spend_offer(stat_id: String) -> bool:
	var offer := offer_for(stat_id)
	if offer.is_empty():
		return false
	return spend(stat_id, float(offer.get("amount", 1.0)))


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
			return Color("9ad4ff")


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


static func offer_boost_text(stat_id: String, amount: float) -> String:
	match stat_id:
		STAT_HEALTH:
			return "+%d HP" % int(round(HEALTH_PER_RANK * amount))
		STAT_DEXTERITY:
			return "+%d%% walk" % int(round(DEX_PER_RANK * amount * 100.0))
		STAT_FLIGHT:
			return "+%.1fs flight" % (CrawlerRules.FLIGHT_SECONDS * FLIGHT_PER_RANK * amount)
		STAT_DODGE:
			return "+%d%% dodge" % int(round(DODGE_PER_RANK * amount * 100.0))
		STAT_DEFENSE:
			return "+%d%% defense" % int(round(DEFENSE_PER_RANK * amount * 100.0))
		STAT_JUKE:
			return "-%.2fs juke" % (JUKE_COOLDOWN_PER_RANK * amount)
		STAT_DAMAGE:
			return "+%d%% damage" % int(round(DAMAGE_PER_RANK * amount * 100.0))
		STAT_KNOCKBACK:
			return "+%d%% knockback" % int(round(KNOCKBACK_PER_RANK * amount * 100.0))
		STAT_RANGE:
			return "+%d%% range" % int(round(RANGE_PER_RANK * amount * 100.0))
		STAT_LUCK:
			return "+%.2f luck" % amount
		_:
			return "+%.2f" % amount


func luck_rank() -> float:
	var luck := rank_of(STAT_LUCK) + float(CrawlerMeta.rank_of(STAT_LUCK))
	if wearing_luck_hat():
		luck += HAT_LUCK_BONUS
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
	return unspent > 0 and gold >= reroll_price()


func reroll_level_offers() -> bool:
	if unspent <= 0:
		return false
	var price := reroll_price()
	if gold < price:
		return false
	gold -= price
	reroll_uses += 1
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
		return int(ABILITY_PRICES[catalog_id])
	return int(SHOP_PRICES.get(catalog_id, 0))


static func ability_price(catalog_id: String) -> int:
	return int(ABILITY_PRICES.get(catalog_id, 0))


static func ability_stock() -> PackedStringArray:
	var stock := PackedStringArray()
	for id: String in CrawlerRules.ENABLED_ABILITIES:
		if ability_price(id) <= 0 or not CrawlerCatalog.is_ability(id):
			continue
		stock.append(id)
	return stock


static func upgrade_price(rank: int, catalog_id := "") -> int:
	if catalog_id == "big":
		return maxi(int(round(float(BIG_UPGRADE_BASE)
			* pow(BIG_UPGRADE_GROWTH, float(maxi(rank, 0))))), 1)
	return UPGRADE_BASE + UPGRADE_GROWTH * maxi(rank, 0)


static func shop_stock() -> PackedStringArray:
	var mods := PackedStringArray()
	for id: String in CrawlerCatalog.ids():
		if card_price(id) <= 0 or not CrawlerCatalog.is_modifier(id):
			continue
		mods.append(id)
	return mods


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	remember()
	changed.emit()
	return true


static func is_city_hat(item_id: String) -> bool:
	return not item_id.is_empty() and HAT_STOCK.has(item_id)


static func hat_stock() -> PackedStringArray:
	return PackedStringArray(HAT_STOCK)


static func hat_price(item_id: String) -> int:
	return int(HAT_PRICES.get(item_id, 0))


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
		_:
			return ItemDB.description(item_id)


func buy_hat(item_id := HAT_ID) -> bool:
	if item_id.is_empty() or owns_hat(item_id) or not is_city_hat(item_id):
		return false
	var price := hat_price(item_id)
	if price <= 0 or gold < price:
		return false
	gold -= price
	owned_hats.append(item_id)
	worn_hat = item_id
	remember()
	changed.emit()
	return true


func note_worn(item_id: String) -> void:
	if item_id == worn_hat:
		return
	if not item_id.is_empty() and not owns_hat(item_id):
		return
	worn_hat = item_id
	remember()
	changed.emit()


func owns_hat(item_id: String) -> bool:
	return not item_id.is_empty() and owned_hats.has(item_id)


static func quest_stock() -> PackedStringArray:
	return PackedStringArray(QUEST_ORDER)


static func quest_price(quest_id: String) -> int:
	return int(QUEST_PRICES.get(quest_id, 0))


static func quest_title(quest_id: String) -> String:
	match quest_id:
		QUEST_TOWER:
			return "Meridian Tower"
		QUEST_CASTLE:
			return "Stormwatch Castle"
		_:
			return quest_id


static func quest_blurb(quest_id: String) -> String:
	match quest_id:
		QUEST_TOWER:
			return "Marks Meridian Tower on Far Beacon 4. Tilde points there once you buy it or walk there."
		QUEST_CASTLE:
			return "Marks Stormwatch Castle on Long Shore 4. Tilde points there once you buy it or walk there."
		_:
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
	gems_earned += SITE_GEMS
	CrawlerMeta.add_gems(SITE_GEMS)
	remember()
	changed.emit()
	return SITE_GEMS


func has_respawn_ticket() -> bool:
	return respawn_tickets > 0


func buy_respawn_ticket() -> bool:
	if gold < TICKET_GOLD or CrawlerMeta.gems() < TICKET_GEMS:
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
		_:
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
	return worn_hat == HAT_ID and owns_hat(HAT_ID)


func wearing_ward_hat() -> bool:
	return worn_hat == HAT_WARD and owns_hat(HAT_WARD)


func wearing_luck_hat() -> bool:
	return worn_hat == HAT_LUCK and owns_hat(HAT_LUCK)


func rank_of(stat_id: String) -> float:
	return maxf(float(ranks.get(stat_id, 0)), 0.0)


func combined_rank(stat_id: String) -> float:
	return rank_of(stat_id) + float(CrawlerMeta.rank_of(stat_id))


func health_maximum() -> float:
	return HEALTH_BASE + HEALTH_PER_RANK * float(combined_rank(STAT_HEALTH))


func dex_scale() -> float:
	var scale := 1.0 + DEX_PER_RANK * float(combined_rank(STAT_DEXTERITY))
	if wearing_shop_hat():
		scale *= HAT_DEX
	return scale


func flight_seconds() -> float:
	var seconds := CrawlerRules.FLIGHT_SECONDS \
		* (1.0 + FLIGHT_PER_RANK * float(combined_rank(STAT_FLIGHT)))
	if wearing_shop_hat():
		seconds *= HAT_FLIGHT
	return seconds


func damage_scale() -> float:
	return 1.0 + DAMAGE_PER_RANK * float(combined_rank(STAT_DAMAGE))


func knockback_scale() -> float:
	return 1.0 + KNOCKBACK_PER_RANK * float(combined_rank(STAT_KNOCKBACK))


func range_scale() -> float:
	return 1.0 + RANGE_PER_RANK * float(combined_rank(STAT_RANGE))


func dodge_chance() -> float:
	return minf(DODGE_MAX, DODGE_PER_RANK * float(combined_rank(STAT_DODGE)))


func defense_share() -> float:
	return minf(DEFENSE_MAX, DEFENSE_PER_RANK * float(combined_rank(STAT_DEFENSE)))


func juke_cooldown() -> float:
	return maxf(JUKE_COOLDOWN_MIN,
		JUKE_COOLDOWN_BASE - JUKE_COOLDOWN_PER_RANK * float(combined_rank(STAT_JUKE)))


func hero_stat_rows(owner: OnlinePlayer = null) -> Array:
	var who := owner if owner != null else player
	var rows: Array = []
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
		STAT_DAMAGE:
			return _with_boost("1.00x", damage_scale() - 1.0)
		STAT_KNOCKBACK:
			return _with_boost("1.00x", knockback_scale() - 1.0)
		STAT_RANGE:
			return _with_boost("1.00x", range_scale() - 1.0)
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
		"quests": Array(owned_quests),
		"offers": level_offers.duplicate(true),
		"rerolls": reroll_uses,
		"sites": Array(unlocked_sites),
		"last_site": last_entered_site,
		"kills": kills,
		"gems": gems_earned,
		"tickets": respawn_tickets,
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


func remember() -> void:
	session_payload = to_dict()
