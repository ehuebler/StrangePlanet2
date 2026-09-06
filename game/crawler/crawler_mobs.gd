class_name CrawlerMobs
extends RefCounted

## Runtime reader for [code]assets/runtime/crawler/mobs.csv[/code].
##
## Each row is one kind at one level: stats, spawn, and attack behavior.
## A patch calls the kinds whose [code]patches[/code] token matches it.
## [code]*[/code] is the fallback roster for unnamed tiles.
## [code]Tide Margin 4:near[/code] / [code]:far[/code] split the start pad.

const PATH := "res://assets/runtime/crawler/mobs.csv"
const FIELD_ORDER: PackedStringArray = ["ranger", "rammer", "rhino", "rift_hulk"]

static var _rows: Array[Dictionary] = []
static var _by_key: Dictionary = {}
static var _max_level: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_loaded = false
	_rows.clear()
	_by_key.clear()
	_max_level.clear()
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
	var rank := _clamped_level(clean, level)
	return _by_key.get(_key(clean, rank), {})


static func title(kind: String, level := 1) -> String:
	return str(stats(kind, level).get("title", kind))


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
	var patch := patch_name.strip_edges()
	var band := "far" if CrawlerRules.start_patch(patch) \
			and from_start > CrawlerRules.START_NEAR_RANGE else "near"
	if not CrawlerRules.start_patch(patch):
		band = "any"
	var called := {}
	for kind: String in FIELD_ORDER:
		if _kind_called_by(kind, patch, band):
			called[kind] = true
	var order := CrawlerRules.WILD_KINDS
	if CrawlerRules.start_patch(patch):
		order = CrawlerRules.START_FAR_KINDS if band == "far" \
			else CrawlerRules.START_NEAR_KINDS
	var out := PackedStringArray()
	for kind: String in order:
		if called.has(kind):
			out.append(kind)
	for kind: String in FIELD_ORDER:
		if kind == "rift_hulk" or not called.has(kind) or out.has(kind):
			continue
		out.append(kind)
	return out


static func kind_cap(kind: String, level: int) -> int:
	var cap := int(number(kind, level, "cap", -1.0))
	if cap >= 0:
		return cap
	return CrawlerRules.kind_cap_fallback(kind, level)


static func _kind_called_by(kind: String, patch: String, band: String) -> bool:
	var named := false
	var hit := false
	var wildcard := false
	for row: Dictionary in _rows:
		if str(row.get("kind", "")) != kind:
			continue
		for token: String in _patch_tokens(row):
			if token == "*":
				wildcard = true
				continue
			var bits := token.split(":")
			var name := bits[0]
			if name != patch:
				continue
			named = true
			var need := bits[1] if bits.size() > 1 else "any"
			if need == "any" or band == "any" or need == band:
				hit = true
	if named:
		return hit
	return wildcard


static func _patch_tokens(row: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for bit: String in str(row.get("patches", "")).split(";"):
		var token := bit.strip_edges()
		if not token.is_empty():
			out.append(token)
	return out


static func _clamped_level(kind: String, level: int) -> int:
	var top := int(_max_level.get(kind, 1))
	return clampi(maxi(level, 1), 1, maxi(top, 1))


static func _key(kind: String, level: int) -> String:
	return "%s:%d" % [kind, level]


static func _load() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_error("CrawlerMobs could not read %s" % PATH)
		return
	var headers := file.get_csv_line()
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.is_empty() or (cells.size() == 1 and cells[0].is_empty()):
			continue
		var raw: Dictionary = {}
		for index in headers.size():
			raw[headers[index]] = cells[index] if index < cells.size() else ""
		var kind := str(raw.get("kind", "")).strip_edges()
		var level := maxi(int(raw.get("level", 1)), 1)
		if kind.is_empty():
			continue
		var row := _parse_row(raw, kind, level)
		_rows.append(row)
		_by_key[_key(kind, level)] = row
		_max_level[kind] = maxi(int(_max_level.get(kind, 0)), level)


static func _parse_row(raw: Dictionary, kind: String, level: int) -> Dictionary:
	var row := {
		"kind": kind,
		"level": level,
		"title": str(raw.get("title", kind)).strip_edges(),
		"patches": str(raw.get("patches", "")).strip_edges(),
		"agro": str(raw.get("agro", "leash")).strip_edges(),
		"spawn": str(raw.get("spawn", "ahead")).strip_edges(),
		"attack": str(raw.get("attack", "")).strip_edges(),
		"notes": str(raw.get("notes", "")).strip_edges(),
	}
	for key: String in [
		"health", "damage", "speed", "cap", "agro_range", "deagro_range",
		"spawn_min", "spawn_max", "flyer_ceiling", "engage_min", "engage_max",
		"standoff_min", "standoff_max", "shot_speed", "shot_ball", "shot_hit",
		"aim_seconds", "charge_from", "charge_mul", "ram_top", "ram_accel",
		"fire", "xp",
	]:
		var text := str(raw.get(key, "")).strip_edges()
		if text.is_empty():
			continue
		row[key] = float(text)
	return row
