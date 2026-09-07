class_name CrawlerMeta
extends RefCounted

## Persistent gems, hat unlocks, out-of-run stat ranks, and the player's
## global level. Written to `settings.cfg` so a crawler run can spend them
## on the home screen and still have them on the next launch. In-run gold
## and level ranks stay on [CrawlerProgress].

const SECTION := &"meta"
const GEMS_KEY := &"gems"
const HATS_KEY := &"unlocked_hats"
const RANKS_KEY := &"ranks"
const XP_KEY := &"xp"
const SANDBOX_KEY := &"sandbox_unlocked"
const LOCKER_KEY := &"locker"
const XP_BASE := 60
const XP_GROWTH := 20
const TITLE_EVERY := 5
const RUN_XP_RATE := 0.5
const RUN_SITE_XP := 45
const RUN_KILL_XP := 5
const TITLES := [
	"Newbie",
	"Recruit",
	"Scout",
	"Wanderer",
	"Explorer",
	"Pathfinder",
	"Veteran",
	"Ranger",
	"Captain",
	"Commander",
	"Warden",
	"Champion",
	"Hero",
	"Legend",
	"Mythic",
	"Immortal",
	"Sovereign",
]

const FREE_HATS := ["c3_hair", "straw_hat"]
const HAT_PRICE_BASE := 16
const HAT_PRICE_STEP := 4
const UPGRADE_BASE := 24
const UPGRADE_GROWTH := 16
const KILL_GEM_BASE := 1

static var _test_payload: Variant = null


static func begin_test(payload: Dictionary = {}) -> void:
	_test_payload = _sanitize(payload)


static func end_test() -> void:
	_test_payload = null


static func gems() -> int:
	return int(_read().get("gems", 0))


static func global_xp() -> int:
	return maxi(int(_read().get("xp", 0)), 0)


static func xp_needed(at_level: int) -> int:
	return XP_BASE + XP_GROWTH * maxi(at_level - 1, 0)


static func global_level() -> int:
	return _level_from_xp(global_xp())


static func xp_into_level() -> int:
	return remainder_at_xp(global_xp())


static func level_at_xp(total: int) -> int:
	return _level_from_xp(total)


static func remainder_at_xp(total: int) -> int:
	return _into_from_xp(total)


static func title() -> String:
	return title_for(global_level())


static func title_for(level: int) -> String:
	var index := maxi(level, 1) / TITLE_EVERY
	if index < TITLES.size():
		return str(TITLES[index])
	var extra := index - TITLES.size() + 2
	return "%s %s" % [str(TITLES[TITLES.size() - 1]), _roman(extra)]


static func locker_card() -> Dictionary:
	var raw: Variant = _read().get("locker", {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


static func set_locker_card(payload: Dictionary) -> void:
	var data := _read()
	data["locker"] = payload.duplicate(true) if not payload.is_empty() else {}
	_write(data)


static func sandbox_unlocked() -> bool:
	return bool(_read().get("sandbox", false))


static func unlock_sandbox() -> bool:
	if sandbox_unlocked():
		return false
	var payload := _read()
	payload["sandbox"] = true
	_write(payload)
	return true


static func lock_sandbox() -> void:
	var payload := _read()
	payload["sandbox"] = false
	_write(payload)


static func add_xp(amount: int) -> Dictionary:
	var before := snapshot()
	if amount <= 0:
		return {"before": before, "after": before, "gained": 0}
	var payload := _read()
	payload["xp"] = global_xp() + amount
	_write(payload)
	var after := snapshot()
	return {
		"before": before,
		"after": after,
		"gained": int(after.get("level", 1)) - int(before.get("level", 1)),
	}


static func snapshot() -> Dictionary:
	var total := global_xp()
	var level := _level_from_xp(total)
	return {
		"xp": total,
		"level": level,
		"into": _into_from_xp(total),
		"need": xp_needed(level),
		"title": title_for(level),
	}


static func score_run(progress: CrawlerProgress) -> Dictionary:
	var from_xp := 0
	var from_sites := 0
	var from_kills := 0
	if progress != null:
		from_xp = int(round(float(progress.lifetime_xp()) * RUN_XP_RATE))
		from_sites = progress.unlocked_sites.size() * RUN_SITE_XP
		from_kills = progress.kills * RUN_KILL_XP
	var total := from_xp + from_sites + from_kills
	var lines := PackedStringArray()
	if from_xp > 0:
		lines.append("%d from expedition XP" % from_xp)
	if from_sites > 0:
		lines.append("%d from sites discovered" % from_sites)
	if from_kills > 0:
		lines.append("%d from mobs killed" % from_kills)
	if lines.is_empty():
		lines.append("0 from this expedition")
	return {
		"from_xp": from_xp,
		"from_sites": from_sites,
		"from_kills": from_kills,
		"total": total,
		"lines": lines,
	}


static func settle_run(progress: CrawlerProgress, journal: Journal = null) -> Dictionary:
	var score := score_run(progress)
	var before := snapshot()
	if progress != null and progress.settled_global:
		return _recap_from(progress, journal, score, before, snapshot(), PackedStringArray())
	if progress != null:
		progress.settled_global = true
	var payout := int(score.get("total", 0))
	if payout > 0:
		add_xp(payout)
	var unlocked := PackedStringArray()
	if journal != null:
		unlocked = journal.note_global_level(global_level())
	return _recap_from(progress, journal, score, before, snapshot(), unlocked)


static func unlocked_hats() -> PackedStringArray:
	return PackedStringArray(_read().get("hats", []))


static func ranks() -> Dictionary:
	return (_read().get("ranks", _empty_ranks()) as Dictionary).duplicate()


static func rank_of(stat_id: String) -> int:
	return maxi(int(ranks().get(stat_id, 0)), 0)


static func kill_gems(mob_level: int) -> int:
	return KILL_GEM_BASE + maxi(mob_level, 1)


static func is_free_hat(item_id: String) -> bool:
	return not item_id.is_empty() and FREE_HATS.has(item_id)


static func hat_price(item_id: String) -> int:
	if item_id.is_empty() or is_free_hat(item_id):
		return 0
	var hash_value := 0
	for index in item_id.length():
		hash_value = (hash_value * 31 + item_id.unicode_at(index)) % 17
	return HAT_PRICE_BASE + HAT_PRICE_STEP * hash_value


static func shop_stats() -> PackedStringArray:
	return PackedStringArray(CrawlerProgress.LEVEL_STATS)


static func upgrade_price(stat_id: String) -> int:
	if not CrawlerProgress.LEVEL_STATS.has(stat_id):
		return 0
	return UPGRADE_BASE + UPGRADE_GROWTH * rank_of(stat_id)


static func refund_value(stat_id: String) -> int:
	var rank := rank_of(stat_id)
	if rank <= 0:
		return 0
	return UPGRADE_BASE + UPGRADE_GROWTH * (rank - 1)


static func spent_on_ranks() -> int:
	var total := 0
	for stat_id: String in shop_stats():
		var rank := rank_of(stat_id)
		for step in rank:
			total += UPGRADE_BASE + UPGRADE_GROWTH * step
	return total


static func owns_hat(item_id: String, look: Dictionary = {}) -> bool:
	if item_id.is_empty():
		return false
	if is_free_hat(item_id):
		return true
	if unlocked_hats().has(item_id):
		return true
	var worn: Variant = look.get("worn", {})
	if worn is Dictionary:
		for value: Variant in (worn as Dictionary).values():
			if str(value) == item_id:
				return true
	var backpack: Variant = look.get("backpack", [])
	if backpack is Array or backpack is PackedStringArray:
		for value: Variant in backpack:
			if str(value) == item_id:
				return true
	return false


static func add_gems(amount: int) -> int:
	if amount <= 0:
		return gems()
	var next := gems() + amount
	_write_gems(next)
	return next


static func spend_gems(amount: int) -> bool:
	if amount <= 0:
		return true
	var current := gems()
	if current < amount:
		return false
	_write_gems(current - amount)
	return true


static func unlock_hat(item_id: String) -> bool:
	if item_id.is_empty() or owns_hat(item_id):
		return owns_hat(item_id)
	var price := hat_price(item_id)
	if price > 0 and not spend_gems(price):
		return false
	var hats := unlocked_hats()
	hats.append(item_id)
	_write_hats(hats)
	return true


static func note_owned_apparel(look: Dictionary) -> void:
	var hats := unlocked_hats()
	var changed := false
	var worn: Variant = look.get("worn", {})
	if worn is Dictionary:
		for value: Variant in (worn as Dictionary).values():
			var item_id := str(value)
			if item_id.is_empty() or is_free_hat(item_id) or hats.has(item_id):
				continue
			if ItemDB.is_apparel(item_id):
				hats.append(item_id)
				changed = true
	var backpack: Variant = look.get("backpack", [])
	if backpack is Array or backpack is PackedStringArray:
		for value: Variant in backpack:
			var item_id := str(value)
			if item_id.is_empty() or is_free_hat(item_id) or hats.has(item_id):
				continue
			if ItemDB.is_apparel(item_id):
				hats.append(item_id)
				changed = true
	if changed:
		_write_hats(hats)


static func buy_rank(stat_id: String) -> bool:
	if not CrawlerProgress.LEVEL_STATS.has(stat_id):
		return false
	var price := upgrade_price(stat_id)
	if not spend_gems(price):
		return false
	var next := ranks()
	next[stat_id] = rank_of(stat_id) + 1
	_write_ranks(next)
	return true


static func refund_rank(stat_id: String) -> bool:
	var rank := rank_of(stat_id)
	if rank <= 0:
		return false
	var value := refund_value(stat_id)
	var next := ranks()
	next[stat_id] = rank - 1
	_write_ranks(next)
	if value > 0:
		add_gems(value)
	return true


static func refund_all() -> int:
	var returned := spent_on_ranks()
	if returned <= 0 and _has_any_rank():
		_write_ranks(_empty_ranks())
		return 0
	if returned <= 0:
		return 0
	_write_ranks(_empty_ranks())
	add_gems(returned)
	return returned


static func hero_stat_rows(progress: CrawlerProgress = null) -> Array:
	if progress != null:
		return progress.hero_stat_rows()
	var scratch := CrawlerProgress.new()
	return scratch.hero_stat_rows()


static func _has_any_rank() -> bool:
	for stat_id: String in shop_stats():
		if rank_of(stat_id) > 0:
			return true
	return false


static func _sanitize_locker(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var held := raw as Dictionary
	if held.is_empty():
		return {}
	var card := CrawlerCard.from_dict(held)
	if card == null or not card.is_ability():
		return {}
	return card.to_dict()


static func _empty_ranks() -> Dictionary:
	var out := {}
	for stat_id: String in shop_stats():
		out[stat_id] = 0
	return out


static func _sanitize(raw: Dictionary) -> Dictionary:
	var hats: Array = []
	var hats_raw: Variant = raw.get("hats", raw.get("unlocked_hats", []))
	if hats_raw is Array or hats_raw is PackedStringArray:
		for value: Variant in hats_raw:
			var item_id := str(value)
			if not item_id.is_empty() and not hats.has(item_id):
				hats.append(item_id)
	var next_ranks := _empty_ranks()
	var ranks_raw: Variant = raw.get("ranks", {})
	if ranks_raw is Dictionary:
		for stat_id: String in shop_stats():
			next_ranks[stat_id] = maxi(int((ranks_raw as Dictionary).get(stat_id, 0)), 0)
	return {
		"gems": maxi(int(raw.get("gems", 0)), 0),
		"hats": hats,
		"ranks": next_ranks,
		"xp": maxi(int(raw.get("xp", 0)), 0),
		"sandbox": bool(raw.get("sandbox", raw.get("sandbox_unlocked", false))),
		"locker": _sanitize_locker(raw.get("locker", {})),
	}


static func _read() -> Dictionary:
	if _test_payload is Dictionary:
		return (_test_payload as Dictionary).duplicate(true)
	if SettingsManager == null:
		return _sanitize({})
	return _sanitize({
		"gems": SettingsManager.get_setting(SECTION, GEMS_KEY, 0),
		"hats": SettingsManager.get_setting(SECTION, HATS_KEY, []),
		"ranks": SettingsManager.get_setting(SECTION, RANKS_KEY, {}),
		"xp": SettingsManager.get_setting(SECTION, XP_KEY, 0),
		"sandbox": SettingsManager.get_setting(SECTION, SANDBOX_KEY, false),
		"locker": SettingsManager.get_setting(SECTION, LOCKER_KEY, {}),
	})


static func _write(payload: Dictionary) -> void:
	var clean := _sanitize(payload)
	if _test_payload is Dictionary:
		_test_payload = clean
		return
	if SettingsManager == null:
		return
	SettingsManager.set_setting(SECTION, GEMS_KEY, int(clean["gems"]), false)
	SettingsManager.set_setting(SECTION, HATS_KEY, (clean["hats"] as Array).duplicate(), false)
	SettingsManager.set_setting(SECTION, RANKS_KEY, (clean["ranks"] as Dictionary).duplicate(), false)
	SettingsManager.set_setting(SECTION, XP_KEY, int(clean["xp"]), false)
	SettingsManager.set_setting(SECTION, SANDBOX_KEY, bool(clean["sandbox"]), false)
	SettingsManager.set_setting(
		SECTION, LOCKER_KEY, (clean["locker"] as Dictionary).duplicate(true), false)
	SettingsManager.save_settings()


static func _write_gems(amount: int) -> void:
	var payload := _read()
	payload["gems"] = maxi(amount, 0)
	_write(payload)


static func _write_hats(hats: PackedStringArray) -> void:
	var payload := _read()
	var listed: Array = []
	for item_id: String in hats:
		if not item_id.is_empty() and not listed.has(item_id):
			listed.append(item_id)
	payload["hats"] = listed
	_write(payload)


static func _write_ranks(next_ranks: Dictionary) -> void:
	var payload := _read()
	payload["ranks"] = next_ranks
	_write(payload)


static func _level_from_xp(total: int) -> int:
	var remain := maxi(total, 0)
	var level := 1
	while remain >= xp_needed(level):
		remain -= xp_needed(level)
		level += 1
	return level


static func _into_from_xp(total: int) -> int:
	var remain := maxi(total, 0)
	var level := 1
	while remain >= xp_needed(level):
		remain -= xp_needed(level)
		level += 1
	return remain


static func _recap_from(
		progress: CrawlerProgress,
		journal: Journal,
		score: Dictionary,
		before: Dictionary,
		after: Dictionary,
		_fresh: PackedStringArray
	) -> Dictionary:
	var achievements: Array = []
	if journal != null:
		for id: String in journal.session_completed():
			if JournalDB.kind_of(id) != JournalDB.ACHIEVEMENT:
				continue
			achievements.append({
				"id": id,
				"title": JournalDB.title_of(id),
				"rewards": JournalDB.instant_reward_lines(id),
			})
	var levels: Array = []
	var start_level := int(before.get("level", 1))
	var end_level := int(after.get("level", 1))
	for level in range(start_level + 1, end_level + 1):
		var row := {
			"level": level,
			"title": title_for(level),
			"title_changed": title_for(level) != title_for(level - 1),
		}
		levels.append(row)
	return {
		"score": score,
		"before": before,
		"after": after,
		"achievements": achievements,
		"levels": levels,
		"kills": progress.kills if progress != null else 0,
		"sites": progress.unlocked_sites.size() if progress != null else 0,
	}


static func _roman(value: int) -> String:
	var n := maxi(value, 1)
	var out := ""
	var numerals := [
		[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"],
		[100, "C"], [90, "XC"], [50, "L"], [40, "XL"],
		[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"],
	]
	for pair: Array in numerals:
		var amount := int(pair[0])
		var glyph := str(pair[1])
		while n >= amount:
			out += glyph
			n -= amount
	return out
