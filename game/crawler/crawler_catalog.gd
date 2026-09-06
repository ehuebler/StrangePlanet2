class_name CrawlerCatalog
extends RefCounted

## Runtime reader for the crawler ability/modifier CSVs.
##
## Abilities are instantiated from [constant CATALOG_PATH]; modifier numbers come
## from [constant EFFECTS_PATH]. Generic rows (`ability_id` of `*`) apply only
## when that modifier has no specific row for the same stat on that ability.

const CATALOG_PATH := "res://assets/runtime/abilities/crawler_catalog.csv"
const EFFECTS_PATH := "res://assets/runtime/abilities/crawler_effects.csv"
const TOKEN_PREFIX := "ck:"
const FILTER_KIT := "crawler_kit"
const FILTER_MOD := "crawler_mod"

static var _entries: Dictionary = {}
static var _effects: Array[Dictionary] = []
static var _loaded := false
static var _serial := 0


static func reload() -> void:
	_loaded = false
	_entries.clear()
	_effects.clear()
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_catalog()
	_load_effects()


static func has(id: String) -> bool:
	ensure_loaded()
	return _entries.has(catalog_id(id))


static func is_ability(id: String) -> bool:
	return str(entry(id).get("kind", "")) == CrawlerCard.KIND_ABILITY


static func is_modifier(id: String) -> bool:
	return str(entry(id).get("kind", "")) == CrawlerCard.KIND_MODIFIER


static func is_token(id: String) -> bool:
	return id.begins_with(TOKEN_PREFIX)


static func is_ability_token(id: String) -> bool:
	return _token_kind(id) == "a"


static func is_modifier_token(id: String) -> bool:
	return _token_kind(id) == "m"


static func catalog_id(id: String) -> String:
	if not is_token(id):
		return id
	var bits := id.split(":")
	return bits[2] if bits.size() >= 4 else ""


static func uid_of(id: String) -> String:
	if not is_token(id):
		return ""
	var bits := id.split(":")
	return bits[3] if bits.size() >= 4 else ""


static func ability_id(id: String) -> String:
	if is_ability_token(id):
		return catalog_id(id)
	return id


static func entry(id: String) -> Dictionary:
	ensure_loaded()
	return _entries.get(catalog_id(id), {})


static func title_of(id: String) -> String:
	var record := entry(id)
	if record.is_empty():
		return catalog_id(id)
	return str(record.get("title", catalog_id(id)))


static func description_of(id: String, host_id := "", size_rank := -1) -> String:
	var clean := catalog_id(id)
	if clean == "big":
		return _big_description(host_id, size_rank)
	return str(entry(id).get("description", ""))


## Size multiplier Big applies to `host_id`. Prefers an authored `size` row,
## then `radius`, so the copy matches the live burst or beam scale.
static func size_mul_for(modifier_id: String, host_id: String) -> float:
	var size_mul := 0.0
	var radius_mul := 0.0
	for row: Dictionary in effects_for(modifier_id, host_id):
		if str(row.get("op", "")) != "mul":
			continue
		var amount := float(row.get("value", 0.0))
		if amount <= 0.0:
			continue
		match str(row.get("stat", "")):
			"size":
				size_mul = amount
			"radius":
				radius_mul = amount
	if size_mul > 0.0:
		return size_mul
	if radius_mul > 0.0:
		return radius_mul
	return 1.0


static func _big_description(host_id: String, size_rank := -1) -> String:
	var rank := maxi(size_rank, 0)
	var scale := CrawlerRules.big_size_scale(rank)
	var host := catalog_id(host_id)
	if is_ability(host):
		return "Makes %s %s larger." % [title_of(host), CrawlerRules.format_mul(scale)]
	return "Makes the ability it sits on larger. Starts at %s and reaches %s at level %d." % [
		CrawlerRules.format_mul(CrawlerRules.big_size_scale(0)),
		CrawlerRules.format_mul(CrawlerRules.big_size_scale(CrawlerRules.BIG_SIZE_MAX_RANK)),
		CrawlerRules.BIG_SIZE_MAX_RANK,
	]


static func scope_of(id: String) -> String:
	return str(entry(id).get("scope", ""))


static func default_slots(id: String) -> int:
	return maxi(int(entry(id).get("default_slots", 0)), 0)


static func icon_path(id: String) -> String:
	return str(entry(id).get("icon", ""))


static func icon(id: String) -> Texture2D:
	var path := icon_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func texture_for(id: String) -> Texture2D:
	var clean := catalog_id(id)
	if has(clean):
		var from_csv := icon(clean)
		if from_csv != null:
			return from_csv
		var authored := ItemDB.ability_icon(clean)
		if authored != null:
			return authored
	if CrawlerCatalog.is_token(id):
		return ItemIcons.cached(clean)
	return ItemIcons.cached(id)


static func host_abilities(modifier_id: String) -> PackedStringArray:
	ensure_loaded()
	var clean := catalog_id(modifier_id)
	if scope_of(clean) != "ability_specific":
		return PackedStringArray()
	var seen := {}
	var out := PackedStringArray()
	for row: Dictionary in _effects:
		if str(row.get("modifier_id", "")) != clean:
			continue
		var target := str(row.get("ability_id", "")).strip_edges()
		if target.is_empty() or target == "*" or seen.has(target):
			continue
		seen[target] = true
		out.append(target)
	return out


static func compatible(modifier_id: String, ability_id_value: String) -> bool:
	var clean_mod := catalog_id(modifier_id)
	var clean_ability := catalog_id(ability_id_value)
	if not is_modifier(clean_mod) or clean_ability.is_empty():
		return false
	if scope_of(clean_mod) == "generic":
		return true
	return not effects_for(clean_mod, clean_ability).is_empty()


static func effects_for(modifier_id: String, ability_id_value: String) -> Array[Dictionary]:
	ensure_loaded()
	var clean_mod := catalog_id(modifier_id)
	var clean_ability := catalog_id(ability_id_value)
	var specific: Array[Dictionary] = []
	var generic: Array[Dictionary] = []
	var specific_stats := {}
	for row: Dictionary in _effects:
		if str(row.get("modifier_id", "")) != clean_mod:
			continue
		var target := str(row.get("ability_id", ""))
		if target == clean_ability:
			specific.append(row)
			specific_stats[str(row.get("stat", ""))] = true
		elif target == "*":
			generic.append(row)
	var out: Array[Dictionary] = []
	out.append_array(specific)
	for row: Dictionary in generic:
		if specific_stats.has(str(row.get("stat", ""))):
			continue
		out.append(row)
	return out


static func resolve_stats(
		ability_id_value: String,
		modifier_ids: PackedStringArray,
		base_stats: Dictionary
	) -> Dictionary:
	var stats := base_stats.duplicate(true)
	for modifier_id: String in modifier_ids:
		if modifier_id.is_empty():
			continue
		for row: Dictionary in effects_for(modifier_id, ability_id_value):
			_apply_effect(stats, row)
	return stats


static func make_ability(id: String, slots := -1, extra_stats: Dictionary = {}) -> CrawlerCard:
	ensure_loaded()
	var clean := catalog_id(id)
	if not is_ability(clean):
		return null
	var card := CrawlerCard.new()
	card.uid = _next_uid()
	card.kind = CrawlerCard.KIND_ABILITY
	card.id = clean
	card.slot_count = slots if slots >= 0 else default_slots(clean)
	card.extra_stats = extra_stats.duplicate(true)
	card.place_mod(0, null)
	return card


static func make_modifier(id: String) -> CrawlerCard:
	ensure_loaded()
	var clean := catalog_id(id)
	if not is_modifier(clean):
		return null
	var card := CrawlerCard.new()
	card.uid = _next_uid()
	card.kind = CrawlerCard.KIND_MODIFIER
	card.id = clean
	card.slot_count = 0
	return card


static func token_for(card: CrawlerCard) -> String:
	if card == null or card.uid.is_empty() or card.id.is_empty():
		return ""
	var mark := "a" if card.is_ability() else "m"
	return "%s%s:%s:%s" % [TOKEN_PREFIX, mark, card.id, card.uid]


static func ids() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for id: String in _entries:
		out.append(id)
	return out


static func _apply_effect(stats: Dictionary, row: Dictionary) -> void:
	var key := str(row.get("stat", ""))
	if key.is_empty():
		return
	var op := str(row.get("op", "set"))
	var amount := float(row.get("value", 0.0))
	match op:
		"mul":
			stats[key] = float(stats.get(key, 1.0)) * amount
		"add":
			stats[key] = float(stats.get(key, 0.0)) + amount
		_:
			stats[key] = amount


static func _token_kind(id: String) -> String:
	if not is_token(id):
		return ""
	var bits := id.split(":")
	return bits[1] if bits.size() >= 4 else ""


static func _next_uid() -> String:
	_serial += 1
	return "%x%x" % [Time.get_ticks_usec() & 0xfffffff, _serial]


static func _load_catalog() -> void:
	var rows := _read_csv(CATALOG_PATH)
	for row: Dictionary in rows:
		var id := str(row.get("id", "")).strip_edges()
		if id.is_empty():
			continue
		_entries[id] = {
			"kind": str(row.get("kind", "")).strip_edges(),
			"id": id,
			"title": str(row.get("title", id)),
			"description": str(row.get("description", "")),
			"scope": str(row.get("scope", "")),
			"default_slots": int(row.get("default_slots", 0)),
			"icon": str(row.get("icon", "")),
		}


static func _load_effects() -> void:
	var rows := _read_csv(EFFECTS_PATH)
	for row: Dictionary in rows:
		var modifier_id := str(row.get("modifier_id", "")).strip_edges()
		if modifier_id.is_empty():
			continue
		_effects.append({
			"modifier_id": modifier_id,
			"ability_id": str(row.get("ability_id", "")).strip_edges(),
			"stat": str(row.get("stat", "")).strip_edges(),
			"op": str(row.get("op", "set")).strip_edges(),
			"value": float(row.get("value", 0.0)),
		})


static func _read_csv(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CrawlerCatalog could not read %s" % path)
		return out
	var headers := file.get_csv_line()
	while not file.eof_reached():
		var cells := file.get_csv_line()
		if cells.is_empty() or (cells.size() == 1 and cells[0].is_empty()):
			continue
		var row: Dictionary = {}
		for index in headers.size():
			row[headers[index]] = cells[index] if index < cells.size() else ""
		out.append(row)
	return out
