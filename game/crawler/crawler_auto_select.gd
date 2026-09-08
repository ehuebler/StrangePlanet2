class_name CrawlerAutoSelect
extends RefCounted

## Persistent solo auto-spend prefs. Flying, health, greed, and strength
## start on; misc starts off. The on/off switch is off until the player
## turns it on. Coop always auto-spends and uses the same prefs.

const PREF_FLYING := "flying"
const PREF_HEALTH := "health"
const PREF_GREED := "greed"
const PREF_STRENGTH := "strength"
const PREF_MISC := "misc"
const PREF_ORDER: PackedStringArray = [
	PREF_FLYING, PREF_HEALTH, PREF_GREED, PREF_STRENGTH, PREF_MISC,
]


static func default_prefs() -> Dictionary:
	return {
		PREF_FLYING: true,
		PREF_HEALTH: true,
		PREF_GREED: true,
		PREF_STRENGTH: true,
		PREF_MISC: false,
	}


static func pref_title(pref_id: String) -> String:
	match pref_id:
		PREF_FLYING:
			return "Flying"
		PREF_HEALTH:
			return "Health"
		PREF_GREED:
			return "Greed"
		PREF_STRENGTH:
			return "Strength"
		PREF_MISC:
			return "Misc"
		_:
			return pref_id.capitalize()


static func pref_blurb(pref_id: String) -> String:
	match pref_id:
		PREF_FLYING:
			return "Highest rarity flight"
		PREF_HEALTH:
			return "Heal or max health"
		PREF_GREED:
			return "XP, gems, and gold"
		PREF_STRENGTH:
			return "Damage and defense"
		PREF_MISC:
			return "Everything else"
		_:
			return ""


static func category_of(stat_id: String) -> String:
	match stat_id.strip_edges():
		"flight":
			return PREF_FLYING
		"health", "heal":
			return PREF_HEALTH
		"gold", "xp", "gems":
			return PREF_GREED
		"damage", "defense":
			return PREF_STRENGTH
		_:
			return PREF_MISC


static func sanitize_prefs(raw: Variant) -> Dictionary:
	var clean := default_prefs()
	if not (raw is Dictionary):
		return clean
	var held := raw as Dictionary
	for pref_id: String in PREF_ORDER:
		if held.has(pref_id):
			clean[pref_id] = bool(held[pref_id])
	return clean


static func pref_on_in(prefs: Dictionary, pref_id: String) -> bool:
	return bool(prefs.get(pref_id, default_prefs().get(pref_id, false)))


static func matches_in(prefs: Dictionary, stat_id: String) -> bool:
	return pref_on_in(prefs, category_of(stat_id))


static func filter_offers(offers: Array, prefs: Dictionary) -> Array:
	var matching: Array = []
	for raw: Variant in offers:
		if not (raw is Dictionary):
			continue
		if matches_in(prefs, str((raw as Dictionary).get("id", ""))):
			matching.append(raw)
	return matching
