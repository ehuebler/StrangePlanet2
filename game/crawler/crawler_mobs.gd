class_name CrawlerMobs
extends RefCounted

## Runtime reader for [code]assets/runtime/crawler/mobs.json[/code].
##
## Each record is one kind at one level: stats, spawn, and attack behavior.
## The file already stores a patch-call index, so a fill does not scan every
## row to decide who belongs on a tile. [code]*[/code] is the fallback roster
## for unnamed tiles. [code]Tide Margin 4[/code] near/far split the start pad.
## Demon names pin Gloam, Vesper, and Threnody to Quiet Inlet 4 and
## Quiet Inlet 4 Southeast. The office tile fields Kestrel, Bastion, and
## Weaver. Alien tiles field Scout, Gray, and Tanglemaw. Castle tiles
## keep the goblin garrison and do not field a patch combo. A named token
## also covers a child such as
## [code]Far Beacon 4 Plaza[/code].

const PATH := "res://assets/runtime/crawler/mobs.json"
const FIELD_ORDER: PackedStringArray = ["ranger", "rammer", "rhino", "rift_hulk", "gloam", "vesper", "threnody", "kestrel", "bastion", "weaver", "scout", "gray", "tanglemaw", "gruk", "nix", "vex", "glorb_jellyfish", "glorb_rhino", "glorb_eyeball", "glorb_punching", "glorb_one_armed", "glorb_spider", "glorb_angel"]
## Level-1 catalog rows are the live L1 combat numbers (health 4–20, hits 2–20).
## Each later ring adds about 25% of those L1 numbers: L2 is 1.25×, L3 is 1.5×.
const LEVEL_STEP := 0.25

static var _by_key: Dictionary = {}
static var _max_level: Dictionary = {}
static var _call_index: Dictionary = {}
static var _kinds_for_cache: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_loaded = false
	_by_key.clear()
	_max_level.clear()
	_call_index.clear()
	_kinds_for_cache.clear()
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load()


static func stats(kind: String, level: int) -> Dictionary:
	ensure_loaded()
	var clean := kind.strip_edges()
	if clean.is_empty():
		return {}
	var base: Variant = _by_key.get(_key(clean, 1))
	if not base is Dictionary:
		var rank := _clamped_level(clean, 1)
		base = _by_key.get(_key(clean, rank))
	if not base is Dictionary:
		return {}
	var row: Dictionary = (base as Dictionary).duplicate()
	if level <= 1:
		return row
	var scale := 1.0 + LEVEL_STEP * float(level - 1)
	for key: String in ["health", "damage", "speed", "xp", "shot_speed", "cap"]:
		if not row.has(key):
			continue
		row[key] = float(row[key]) * scale
	row["level"] = level
	return row


static func title(kind: String, level := 1) -> String:
	return str(stats(kind, level).get("title", kind))


static func max_level_for(kind: String) -> int:
	ensure_loaded()
	return maxi(int(_max_level.get(kind.strip_edges(), 1)), 1)


static func agro_mode(kind: String, level := 1) -> String:
	var mode := str(stats(kind, level).get("agro", "leash")).strip_edges()
	return mode if not mode.is_empty() else "leash"


static func spawn_mode(kind: String, level := 1) -> String:
	var mode := str(stats(kind, level).get("spawn", "ring")).strip_edges()
	return mode if not mode.is_empty() else "ahead"


static func attack_mode(kind: String, level := 1) -> String:
	var mode := str(stats(kind, level).get("attack", "")).strip_edges()
	return mode


static func kill_xp(kind: String, level: int) -> int:
	return CrawlerProgress.kill_xp(level, kind)


static func number(kind: String, level: int, key: String, fallback: float) -> float:
	var row := stats(kind, level)
	if row.is_empty() or not row.has(key):
		return fallback
	var value := float(row.get(key, fallback))
	return value if is_finite(value) else fallback


static func kinds_for(patch_name: String, from_start := -1.0) -> PackedStringArray:
	ensure_loaded()
	if CrawlerRun.active():
		var listed := CrawlerRun.kinds_for_patch(patch_name)
		if not listed.is_empty():
			return listed
	var patch := patch_name.strip_edges()
	var combo := CrawlerRules.patch_combo(patch)
	var started := CrawlerRules.start_patch(patch)
	var band := "any"
	if started:
		band = "far" if from_start > CrawlerRules.START_NEAR_RANGE else "near"
	var cache_key := "%s|%s|%s" % [patch, band, combo]
	var cached: Variant = _kinds_for_cache.get(cache_key)
	if cached is PackedStringArray:
		return cached
	var out := PackedStringArray()
	if combo == CrawlerRules.PATCH_COMBO_GOBLIN:
		_kinds_for_cache[cache_key] = out
		return out
	if combo == CrawlerRules.PATCH_COMBO_DEMON:
		for kind: String in CrawlerRules.DEMON_KINDS:
			out.append(kind)
		_kinds_for_cache[cache_key] = out
		return out
	if combo == CrawlerRules.PATCH_COMBO_ROBOT:
		for kind: String in CrawlerRules.ROBOT_KINDS:
			out.append(kind)
		_kinds_for_cache[cache_key] = out
		return out
	if combo == CrawlerRules.PATCH_COMBO_ALIEN:
		for kind: String in CrawlerRules.ALIEN_KINDS:
			out.append(kind)
		_kinds_for_cache[cache_key] = out
		return out
	var called := {}
	for kind: String in FIELD_ORDER:
		if _kind_called_by(kind, patch, band):
			called[kind] = true
	var order := CrawlerRules.WILD_KINDS
	if started:
		order = CrawlerRules.START_FAR_KINDS if band == "far" \
			else CrawlerRules.START_NEAR_KINDS
	for kind: String in order:
		if called.has(kind):
			out.append(kind)
	_kinds_for_cache[cache_key] = out
	return out


static func kind_cap(kind: String, level: int) -> int:
	var cap := int(number(kind, level, "cap", -1.0))
	if cap >= 0:
		return cap
	return CrawlerRules.kind_cap_fallback(kind, level)


static func _kind_called_by(kind: String, patch: String, band: String) -> bool:
	var info: Variant = _call_index.get(kind)
	if info == null:
		return false
	var names: Dictionary = info["names"]
	var named := false
	var hit := false
	var exact: Variant = names.get(patch)
	if exact != null:
		named = true
		hit = _band_matches(exact, band)
	else:
		for name: String in names:
			if not patch.begins_with(name + " "):
				continue
			named = true
			if _band_matches(names[name], band):
				hit = true
				break
	if named:
		return hit
	return bool(info["wildcard"])


static func _band_matches(bands: Variant, band: String) -> bool:
	if band == "any":
		return true
	if bands is PackedStringArray:
		for need: String in bands:
			if need == "any" or need == band:
				return true
		return false
	if bands is Array:
		for need_variant: Variant in bands:
			var need := str(need_variant)
			if need == "any" or need == band:
				return true
	return false


static func _clamped_level(kind: String, level: int) -> int:
	var top := int(_max_level.get(kind, 1))
	return clampi(maxi(level, 1), 1, maxi(top, 1))


static func _key(kind: String, level: int) -> String:
	return "%s:%d" % [kind, level]


static func _load() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("CrawlerMobs could not read %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("CrawlerMobs could not parse %s" % PATH)
		return
	var data: Dictionary = parsed
	var stats: Variant = data.get("stats", {})
	var levels: Variant = data.get("max_level", {})
	var calls: Variant = data.get("call", {})
	if stats is Dictionary:
		_by_key = stats
	if levels is Dictionary:
		_max_level = levels
	if calls is Dictionary:
		_call_index = calls
