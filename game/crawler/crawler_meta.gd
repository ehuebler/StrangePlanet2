class_name CrawlerMeta
extends RefCounted

## Persistent gems, hat unlocks, out-of-run stat ranks, and the player's
## global level. Written to `settings.cfg` so a crawler run can spend them
## on the home screen and still have them on the next launch. In-run gold
## and level ranks stay on [CrawlerProgress].

const SECTION := &"meta"
const GEMS_KEY := &"gems"
const HATS_KEY := &"unlocked_hats"
const CAPES_KEY := &"unlocked_capes"
const RANKS_KEY := &"ranks"
const XP_KEY := &"xp"
const SANDBOX_KEY := &"sandbox_unlocked"
const LOCKER_KEY := &"locker"
const AUTO_SELECT_KEY := &"auto_select"
const AUTO_PREFS_KEY := &"auto_select_prefs"
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
const FREE_CAPES: Array[String] = []
const HAT_GEM_PRICE := 500
const CAPE_GEM_PRICE := 1000
const UPGRADE_BASE := 100
const UPGRADE_STEP := 100
const UPGRADE_LINEAR_RANKS := 5
const KILL_GEM_BASE := 1
const GEM_DROP_CHANCE := 0.25
const GEM_DROP_CHANCE_CAP := 0.50
const GEM_DROP_LUCK_RATE := 0.20

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


static func auto_select() -> bool:
	return bool(_read().get("auto_select", false))


static func set_auto_select(on: bool) -> void:
	var data := _read()
	data["auto_select"] = on
	_write(data)


static func auto_prefs() -> Dictionary:
	return _sanitize_auto_prefs(_read().get("auto_prefs", {})).duplicate()


static func auto_pref_on(pref_id: String) -> bool:
	return bool(auto_prefs().get(pref_id, pref_id != "misc"))


static func set_auto_pref(pref_id: String, on: bool) -> void:
	if not ["flying", "health", "greed", "strength", "misc"].has(pref_id):
		return
	var data := _read()
	var prefs := _sanitize_auto_prefs(data.get("auto_prefs", {}))
	prefs[pref_id] = on
	data["auto_prefs"] = prefs
	_write(data)


static func _sanitize_auto_prefs(raw: Variant) -> Dictionary:
	var clean := {
		"flying": true,
		"health": true,
		"greed": true,
		"strength": true,
		"misc": false,
	}
	if not (raw is Dictionary):
		return clean
	var held := raw as Dictionary
	for pref_id: String in clean.keys():
		if held.has(pref_id):
			clean[pref_id] = bool(held[pref_id])
	return clean


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


static func unlocked_capes() -> PackedStringArray:
	return PackedStringArray(_read().get("capes", []))


static func ranks() -> Dictionary:
	return (_read().get("ranks", _empty_ranks()) as Dictionary).duplicate()


static func rank_of(stat_id: String) -> int:
	return maxi(int(ranks().get(stat_id, 0)), 0)


static func kill_gems(_mob_level := 1) -> int:
	return KILL_GEM_BASE


static func gem_drop_chance(luck_rank := 0.0) -> float:
	var room := GEM_DROP_CHANCE_CAP - GEM_DROP_CHANCE
	var lift := 1.0 - exp(-maxf(luck_rank, 0.0) * GEM_DROP_LUCK_RATE)
	return clampf(GEM_DROP_CHANCE + room * lift, GEM_DROP_CHANCE, GEM_DROP_CHANCE_CAP)


static func is_free_hat(item_id: String) -> bool:
	return not item_id.is_empty() and FREE_HATS.has(item_id)


static func is_free_cape(item_id: String) -> bool:
	return not item_id.is_empty() and FREE_CAPES.has(item_id)


static func hat_price(item_id: String) -> int:
	if item_id.is_empty() or is_free_hat(item_id):
		return 0
	return HAT_GEM_PRICE


static func cape_price(item_id: String) -> int:
	if item_id.is_empty() or is_free_cape(item_id):
		return 0
	return CAPE_GEM_PRICE


static func shop_stats() -> PackedStringArray:
	return PackedStringArray(CrawlerProgress.LEVEL_STATS)


## Hat-slot garments the home Unlocks shop sells for gems. Free starter hats
## stay listed so the grid can mark them owned.
static func shop_hats(body_id := "") -> PackedStringArray:
	var wardrobe := CharacterDB.apparel_ids(
		CharacterDB.sanitize_body(
			body_id if not body_id.is_empty() else CharacterDB.DEFAULT_BODY
		)
	)
	var out := PackedStringArray()
	for item_id: String in wardrobe:
		if ItemDB.slot_of(item_id) == "hat" and not out.has(item_id):
			out.append(item_id)
	return out


static func shop_capes(body_id := "") -> PackedStringArray:
	var wardrobe := CharacterDB.apparel_ids(
		CharacterDB.sanitize_body(
			body_id if not body_id.is_empty() else CharacterDB.DEFAULT_BODY
		)
	)
	var out := PackedStringArray()
	for item_id: String in wardrobe:
		if ItemDB.slot_of(item_id) == "cape" and not out.has(item_id):
			out.append(item_id)
	return out


static func upgrade_price(stat_id: String) -> int:
	if not CrawlerProgress.LEVEL_STATS.has(stat_id):
		return 0
	return upgrade_price_for_rank(rank_of(stat_id))


static func upgrade_price_for_rank(rank: int) -> int:
	var at := maxi(rank, 0)
	if at < UPGRADE_LINEAR_RANKS:
		return UPGRADE_BASE + UPGRADE_STEP * at
	var price := UPGRADE_BASE + UPGRADE_STEP * (UPGRADE_LINEAR_RANKS - 1)
	for _step in range(at - (UPGRADE_LINEAR_RANKS - 1)):
		price *= 2
	return price


static func refund_value(stat_id: String) -> int:
	var rank := rank_of(stat_id)
	if rank <= 0:
		return 0
	return upgrade_price_for_rank(rank - 1)


static func spent_on_ranks() -> int:
	var total := 0
	for stat_id: String in shop_stats():
		var rank := rank_of(stat_id)
		for step in rank:
			total += upgrade_price_for_rank(step)
	return total


static func refundable_hats() -> PackedStringArray:
	var out := PackedStringArray()
	for item_id: String in unlocked_hats():
		if hat_price(item_id) > 0 and not out.has(item_id):
			out.append(item_id)
	return out


static func refundable_capes() -> PackedStringArray:
	var out := PackedStringArray()
	for item_id: String in unlocked_capes():
		if cape_price(item_id) > 0 and not out.has(item_id):
			out.append(item_id)
	return out


static func spent_on_hats() -> int:
	var total := 0
	for item_id: String in refundable_hats():
		total += hat_price(item_id)
	return total


static func spent_on_capes() -> int:
	var total := 0
	for item_id: String in refundable_capes():
		total += cape_price(item_id)
	return total


static func spent_on_players() -> int:
	return 0


static func owns_hat(item_id: String) -> bool:
	return _owns_listed(item_id, is_free_hat(item_id), unlocked_hats())


static func owns_cape(item_id: String) -> bool:
	return _owns_listed(item_id, is_free_cape(item_id), unlocked_capes())


static func owns_apparel(item_id: String) -> bool:
	var slot := ItemDB.slot_of(item_id)
	if slot == "hat":
		return owns_hat(item_id)
	if slot == "cape":
		return owns_cape(item_id)
	return false


static func _owns_listed(
		item_id: String,
		free: bool,
		unlocked: PackedStringArray
	) -> bool:
	return not item_id.is_empty() and (free or unlocked.has(item_id))


## Old starter revisions dumped every settler hat into the backpack, then
## [method note_owned_apparel] copied that dump onto the gem unlock list.
## A complete first or second grant batch is that dump, not a shop history.
## Gem-bought hats outside those batches stay owned.
static func forget_granted_catalogue_hats() -> bool:
	var granted := CharacterDB.granted_catalogue_hats()
	var unlocked := unlocked_hats()
	var has_first := not CharacterDB.SETTLER_HEADWEAR.is_empty()
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		if not unlocked.has(item_id):
			has_first = false
			break
	var has_more := not CharacterDB.SETTLER_HEADWEAR_MORE.is_empty()
	for item_id: String in CharacterDB.SETTLER_HEADWEAR_MORE:
		if not unlocked.has(item_id):
			has_more = false
			break
	if not has_first and not has_more:
		return false
	var kept := PackedStringArray()
	for item_id: String in unlocked:
		if is_free_hat(item_id) or not granted.has(item_id):
			kept.append(item_id)
	_write_hats(kept)
	return true


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


static func unlock_cape(item_id: String) -> bool:
	if item_id.is_empty() or owns_cape(item_id):
		return owns_cape(item_id)
	var price := cape_price(item_id)
	if price > 0 and not spend_gems(price):
		return false
	var capes := unlocked_capes()
	capes.append(item_id)
	_write_capes(capes)
	return true


static func note_owned_apparel(look: Dictionary) -> void:
	var capes: Array = Array(unlocked_capes())
	var capes_changed := false
	var worn: Variant = look.get("worn", {})
	if worn is Dictionary:
		for value: Variant in (worn as Dictionary).values():
			capes_changed = _note_owned_cape(str(value), capes) or capes_changed
	var backpack: Variant = look.get("backpack", [])
	if backpack is Array or backpack is PackedStringArray:
		for value: Variant in backpack:
			capes_changed = _note_owned_cape(str(value), capes) or capes_changed
	if capes_changed:
		_write_capes(PackedStringArray(capes))


static func _note_owned_cape(item_id: String, capes: Array) -> bool:
	if item_id.is_empty() or ItemDB.slot_of(item_id) != "cape":
		return false
	if is_free_cape(item_id) or capes.has(item_id):
		return false
	capes.append(item_id)
	return true


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


static func refund_all_hats() -> int:
	return _refund_listed_apparel(refundable_hats(), true)


static func refund_all_capes() -> int:
	return _refund_listed_apparel(refundable_capes(), false)


static func refund_all_players() -> int:
	return 0


static func _refund_listed_apparel(item_ids: PackedStringArray, hats: bool) -> int:
	if item_ids.is_empty():
		return 0
	var returned := 0
	var drop := {}
	for item_id: String in item_ids:
		drop[item_id] = true
		returned += hat_price(item_id) if hats else cape_price(item_id)
	var kept := PackedStringArray()
	var listed := unlocked_hats() if hats else unlocked_capes()
	for item_id: String in listed:
		if not drop.has(item_id):
			kept.append(item_id)
	if hats:
		_write_hats(kept)
	else:
		_write_capes(kept)
	if returned > 0:
		add_gems(returned)
	_strip_saved_apparel(item_ids)
	return returned


static func _strip_saved_apparel(item_ids: PackedStringArray) -> void:
	if _test_payload is Dictionary or SettingsManager == null \
			or item_ids.is_empty():
		return
	var drop := {}
	for item_id: String in item_ids:
		drop[item_id] = true
	var worn_raw: Variant = SettingsManager.get_setting(&"appearance", &"worn", {})
	var worn: Dictionary = {}
	if worn_raw is Dictionary:
		worn = (worn_raw as Dictionary).duplicate()
	var changed := false
	for slot_variant: Variant in worn.keys():
		if drop.has(str(worn[slot_variant])):
			worn.erase(slot_variant)
			changed = true
	var backpack_raw: Variant = SettingsManager.get_setting(
		&"appearance", &"backpack", [])
	var backpack: Array = []
	if backpack_raw is Array or backpack_raw is PackedStringArray:
		for value: Variant in backpack_raw:
			var item_id := str(value)
			if item_id.is_empty():
				continue
			if drop.has(item_id):
				changed = true
				continue
			backpack.append(item_id)
	if not changed:
		return
	SettingsManager.set_setting(&"appearance", &"worn", worn, false)
	SettingsManager.set_setting(&"appearance", &"backpack", backpack, false)
	SettingsManager.save_settings()


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
	var capes: Array = []
	_bucket_apparel(raw.get("hats", raw.get("unlocked_hats", [])), hats, capes)
	var capes_raw: Variant = raw.get("capes", raw.get("unlocked_capes", []))
	if capes_raw is Array or capes_raw is PackedStringArray:
		for value: Variant in capes_raw:
			var cape_id := str(value)
			if cape_id == "crawler_fool_cape":
				if not hats.has(CrawlerProgress.HAT_FOOL):
					hats.append(CrawlerProgress.HAT_FOOL)
				continue
			if not cape_id.is_empty() and not capes.has(cape_id):
				capes.append(cape_id)
	var next_ranks := _empty_ranks()
	var ranks_raw: Variant = raw.get("ranks", {})
	if ranks_raw is Dictionary:
		for stat_id: String in shop_stats():
			next_ranks[stat_id] = maxi(int((ranks_raw as Dictionary).get(stat_id, 0)), 0)
	return {
		"gems": maxi(int(raw.get("gems", 0)), 0),
		"hats": hats,
		"capes": capes,
		"ranks": next_ranks,
		"xp": maxi(int(raw.get("xp", 0)), 0),
		"sandbox": bool(raw.get("sandbox", raw.get("sandbox_unlocked", false))),
		"locker": _sanitize_locker(raw.get("locker", {})),
		"auto_select": bool(raw.get("auto_select", false)),
		"auto_prefs": _sanitize_auto_prefs(raw.get("auto_prefs", {})),
	}


static func _bucket_apparel(raw: Variant, hats: Array, capes: Array) -> void:
	if not (raw is Array or raw is PackedStringArray):
		return
	for value: Variant in raw:
		var item_id := str(value)
		if item_id.is_empty():
			continue
		if item_id == "crawler_fool_cape":
			if not hats.has(CrawlerProgress.HAT_FOOL):
				hats.append(CrawlerProgress.HAT_FOOL)
			continue
		if ItemDB.slot_of(item_id) == "cape":
			if not capes.has(item_id):
				capes.append(item_id)
			continue
		if not hats.has(item_id):
			hats.append(item_id)


static func _read() -> Dictionary:
	if _test_payload is Dictionary:
		return (_test_payload as Dictionary).duplicate(true)
	if SettingsManager == null:
		return _sanitize({})
	return _sanitize({
		"gems": SettingsManager.get_setting(SECTION, GEMS_KEY, 0),
		"hats": SettingsManager.get_setting(SECTION, HATS_KEY, []),
		"capes": SettingsManager.get_setting(SECTION, CAPES_KEY, []),
		"ranks": SettingsManager.get_setting(SECTION, RANKS_KEY, {}),
		"xp": SettingsManager.get_setting(SECTION, XP_KEY, 0),
		"sandbox": SettingsManager.get_setting(SECTION, SANDBOX_KEY, false),
		"locker": SettingsManager.get_setting(SECTION, LOCKER_KEY, {}),
		"auto_select": SettingsManager.get_setting(SECTION, AUTO_SELECT_KEY, false),
		"auto_prefs": SettingsManager.get_setting(SECTION, AUTO_PREFS_KEY, {}),
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
	SettingsManager.set_setting(SECTION, CAPES_KEY, (clean["capes"] as Array).duplicate(), false)
	SettingsManager.set_setting(SECTION, RANKS_KEY, (clean["ranks"] as Dictionary).duplicate(), false)
	SettingsManager.set_setting(SECTION, XP_KEY, int(clean["xp"]), false)
	SettingsManager.set_setting(SECTION, SANDBOX_KEY, bool(clean["sandbox"]), false)
	SettingsManager.set_setting(
		SECTION, LOCKER_KEY, (clean["locker"] as Dictionary).duplicate(true), false)
	SettingsManager.set_setting(SECTION, AUTO_SELECT_KEY, bool(clean["auto_select"]), false)
	SettingsManager.set_setting(
		SECTION, AUTO_PREFS_KEY, (clean["auto_prefs"] as Dictionary).duplicate(), false)
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


static func _write_capes(capes: PackedStringArray) -> void:
	var payload := _read()
	var listed: Array = []
	for item_id: String in capes:
		if not item_id.is_empty() and not listed.has(item_id):
			listed.append(item_id)
	payload["capes"] = listed
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
