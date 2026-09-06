class_name CrawlerMeta
extends RefCounted

## Persistent gems, hat unlocks, and out-of-run stat ranks. Written to
## `settings.cfg` so a crawler run can spend them on the home screen and still
## have them on the next launch. In-run gold and level ranks stay on
## [CrawlerProgress].

const SECTION := &"meta"
const GEMS_KEY := &"gems"
const HATS_KEY := &"unlocked_hats"
const RANKS_KEY := &"ranks"

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


static func upgrade_price(stat_id: String) -> int:
	if not CrawlerProgress.STAT_ORDER.has(stat_id):
		return 0
	return UPGRADE_BASE + UPGRADE_GROWTH * rank_of(stat_id)


static func refund_value(stat_id: String) -> int:
	var rank := rank_of(stat_id)
	if rank <= 0:
		return 0
	return UPGRADE_BASE + UPGRADE_GROWTH * (rank - 1)


static func spent_on_ranks() -> int:
	var total := 0
	for stat_id: String in CrawlerProgress.STAT_ORDER:
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
	if not CrawlerProgress.STAT_ORDER.has(stat_id):
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
	for stat_id: String in CrawlerProgress.STAT_ORDER:
		if rank_of(stat_id) > 0:
			return true
	return false


static func _empty_ranks() -> Dictionary:
	var out := {}
	for stat_id: String in CrawlerProgress.STAT_ORDER:
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
		for stat_id: String in CrawlerProgress.STAT_ORDER:
			next_ranks[stat_id] = maxi(int((ranks_raw as Dictionary).get(stat_id, 0)), 0)
	return {
		"gems": maxi(int(raw.get("gems", 0)), 0),
		"hats": hats,
		"ranks": next_ranks,
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
