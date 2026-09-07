class_name CrawlerCatalog
extends RefCounted

## Runtime reader for the crawler ability/modifier CSVs.
##
## Abilities are instantiated from [constant CATALOG_PATH]; modifier numbers come
## from [constant EFFECTS_PATH]. Effect targets may be an ability id, an ability
## type (`beam`, `shockwave`, `projectile`, `limited`, `misc`), or `*`. A more
## specific row for the same stat wins: ability, then type, then `*`. `limited`
## matches any ability with a shot count.

const CATALOG_PATH := "res://assets/runtime/abilities/crawler_catalog.csv"
const EFFECTS_PATH := "res://assets/runtime/abilities/crawler_effects.csv"
const TOKEN_PREFIX := "ck:"
const FILTER_KIT := "crawler_kit"
const FILTER_MOD := "crawler_mod"
const TYPE_ICON_ROOT := "res://assets/runtime/abilities/icons/type_%s.svg"
const TYPE_ORDER := [
	"beam",
	"shockwave",
	"projectile",
	"field",
	"limited",
	"misc",
]

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
	if clean == "bubble":
		return _bubble_description(host_id)
	if clean == "linger":
		return _linger_description(host_id)
	if clean == "clip":
		return _clip_description(host_id)
	if clean == "endless":
		return _endless_description(host_id)
	if clean == "toxic" or clean == "shock" or clean == "charm" or clean == "ice":
		return _element_description(clean, host_id)
	if clean == "multi":
		return _multi_description(host_id)
	if clean == "reach":
		return _reach_description(host_id)
	if clean == "bounce":
		return _bounce_description(host_id)
	if clean == "impact_cast":
		return _impact_cast_description(host_id)
	if clean == "homing":
		return _homing_description(host_id)
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


static func _bubble_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "Leaves pulsing blue bubbles along %s's beam." % title_of(host)
			CrawlerRules.TYPE_SHOCKWAVE:
				return "Scatters pulsing blue bubbles out with %s's shockwave." % title_of(host)
			CrawlerRules.TYPE_FIELD:
				return "Bubbles keep forming inside %s." % title_of(host)
			CrawlerRules.TYPE_PROJECTILE:
				if CrawlerRules.is_orb_blast(host):
					return "Blooms lingering blue bubbles through %s's blast, not along the throw." \
						% title_of(host)
				return "Leaves a trail of pulsing blue bubbles behind %s." % title_of(host)
			_:
				if host == "meteor_punch" or host == "hero_punch":
					return "Blooms pulsing blue bubbles from %s's impact." % title_of(host)
				return "Bubble does not fit %s." % title_of(host)
	return str(entry("bubble").get("description", ""))


static func _linger_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "Leaves an iridescent smoke trail along %s after the beam dies." % title_of(host)
			CrawlerRules.TYPE_SHOCKWAVE:
				return "Scatters iridescent clouds with %s's shockwave." % title_of(host)
			CrawlerRules.TYPE_FIELD:
				return "Iridescent clouds keep forming inside %s." % title_of(host)
			CrawlerRules.TYPE_PROJECTILE:
				if CrawlerRules.is_orb_blast(host):
					return "Blooms iridescent clouds through %s's blast." % title_of(host)
				return "Leaves iridescent clouds along %s's path." % title_of(host)
			_:
				if host == "meteor_punch" or host == "hero_punch":
					return "Bursts iridescent clouds from %s's impact." % title_of(host)
				return "Linger does not fit %s." % title_of(host)
	return str(entry("linger").get("description", ""))


static func _clip_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if CrawlerRules.uses_ammo(host):
			return "Doubles %s's shots. Upgrade to triple, then quadruple." \
				% title_of(host)
		return "Clip does not fit %s." % title_of(host)
	return str(entry("clip").get("description", ""))


static func _endless_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if CrawlerRules.uses_ammo(host):
			return "Gives %s infinite shots." % title_of(host)
		return "Endless does not fit %s." % title_of(host)
	return str(entry("endless").get("description", ""))


static func _element_description(mod_id: String, host_id: String) -> String:
	var host := catalog_id(host_id)
	var label := title_of(mod_id)
	if is_ability(host):
		if host == "grapple" or host == "lasso":
			return "%s does not fit %s." % [label, title_of(host)]
		if host == "overdrive":
			return "While Overdrive is on, other abilities borrow this %s." % label.to_lower()
		if host == "wall":
			return "Adds %s to Wall's burn. Does nothing until Firewall is upgraded." \
				% label.to_lower()
		return "Adds %s to %s. Scales with your Elemental rank." \
			% [label.to_lower(), title_of(host)]
	return str(entry(mod_id).get("description", ""))


static func _multi_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if host == "grapple" or host == "lasso":
			return "Multi Shot does not fit %s." % title_of(host)
		if host == "overdrive":
			return "While Overdrive is on, other abilities borrow this Multi Shot."
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "Splits %s toward 45° on each side. Odd counts keep a beam straight ahead." \
					% title_of(host)
			CrawlerRules.TYPE_PROJECTILE:
				return "After %s leaves your hand it forks and fans out." % title_of(host)
			CrawlerRules.TYPE_SHOCKWAVE:
				return "Casts %s again automatically after a second." % title_of(host)
			CrawlerRules.TYPE_FIELD:
				return "Raises %s again automatically after a second." % title_of(host)
			_:
				if host == "wall":
					return "Casts extra walls side by side, with one always centered on you."
				if host == "meteor_punch":
					return "Adds more red meteor shocks stacked an inch in front of the fist."
				if host == "hero_punch":
					return "Adds more impacts stacked an inch in front of the jab."
				return "Splits %s." % title_of(host)
	return str(entry("multi").get("description", ""))


static func _reach_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if host == "overdrive":
			return "While Overdrive is on, other beam and projectile abilities borrow this Reach."
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "Makes %s shoot farther, and starts the beam %.0f meters in front of you." \
					% [title_of(host), CrawlerRules.REACH_FAR_CAST]
			CrawlerRules.TYPE_PROJECTILE:
				return "Makes %s fly farther, and throws it from %.0f meters in front of your hand." \
					% [title_of(host), CrawlerRules.REACH_FAR_CAST]
			_:
				return "Reach does not fit %s." % title_of(host)
	return str(entry("reach").get("description", ""))


static func _bounce_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if host == "overdrive":
			return "While Overdrive is on, other beam and projectile abilities borrow this Bounce."
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "Makes %s ricochet off what it hits. Explosions still burst at each bounce." \
					% title_of(host)
			CrawlerRules.TYPE_PROJECTILE:
				return "Makes %s bounce off what it hits. Explosive shots still burst at each bounce." \
					% title_of(host)
			_:
				return "Bounce does not fit %s." % title_of(host)
	return str(entry("bounce").get("description", ""))


static func _impact_cast_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if host == "overdrive":
			return "While Overdrive is on, other beam and projectile abilities borrow this Impact Cast."
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "When %s hits, your other equipped abilities fire from the impact in a random direction." \
					% title_of(host)
			CrawlerRules.TYPE_PROJECTILE:
				return "When %s hits, your other equipped abilities fire from the impact in a random direction." \
					% title_of(host)
			_:
				return "Impact Cast does not fit %s." % title_of(host)
	return str(entry("impact_cast").get("description", ""))


static func _homing_description(host_id: String) -> String:
	var host := catalog_id(host_id)
	if is_ability(host):
		if host == "overdrive":
			return "While Overdrive is on, other beams, shots, and punches borrow this Homing."
		if host == "meteor_punch" or host == "hero_punch":
			return "Locks %s onto a nearby mob and steers the strike toward them." \
				% title_of(host)
		match CrawlerRules.ability_type(host):
			CrawlerRules.TYPE_BEAM:
				return "Bends %s toward nearby mobs. Bubble orbs and Linger clouds on this card also chase." \
					% title_of(host)
			CrawlerRules.TYPE_PROJECTILE:
				return "Turns %s toward nearby mobs. Bubble orbs and Linger clouds on this card also chase." \
					% title_of(host)
			_:
				return "Homing does not fit %s." % title_of(host)
	return str(entry("homing").get("description", ""))


static func scope_of(id: String) -> String:
	return str(entry(id).get("scope", ""))


static func ability_type_of(id: String) -> String:
	return str(entry(id).get("ability_type", "")).strip_edges()


static func shows_host_mark(id: String) -> bool:
	var scope := scope_of(id)
	return scope == "ability_specific" or scope == "type_specific"


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


static func type_icon_path(type_id: String) -> String:
	if not CrawlerRules.is_ability_type(type_id):
		return ""
	return TYPE_ICON_ROOT % type_id


static func type_icon(type_id: String) -> Texture2D:
	var path := type_icon_path(type_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func type_title(type_id: String) -> String:
	match type_id:
		CrawlerRules.TYPE_BEAM:
			return "Beam"
		CrawlerRules.TYPE_SHOCKWAVE:
			return "Shockwave"
		CrawlerRules.TYPE_PROJECTILE:
			return "Projectile"
		CrawlerRules.TYPE_FIELD:
			return "Field"
		CrawlerRules.TYPE_LIMITED:
			return "Limited"
		CrawlerRules.TYPE_MISC:
			return "Other"
		_:
			return type_id.capitalize()


static func host_types(modifier_id: String) -> PackedStringArray:
	ensure_loaded()
	var clean := catalog_id(modifier_id)
	if not shows_host_mark(clean):
		return PackedStringArray()
	var seen := {}
	for row: Dictionary in _effects:
		if str(row.get("modifier_id", "")) != clean:
			continue
		var target := str(row.get("ability_id", "")).strip_edges()
		if target.is_empty() or target == "*":
			continue
		var type_id := target if CrawlerRules.is_ability_type(target) \
			else resolved_ability_type(target)
		if type_id.is_empty():
			continue
		seen[type_id] = true
	return _ordered_types(seen)


static func display_types(id: String) -> PackedStringArray:
	var clean := catalog_id(id)
	if is_ability(clean):
		var typed := resolved_ability_type(clean)
		if typed.is_empty():
			return PackedStringArray()
		return PackedStringArray([typed])
	if is_modifier(clean):
		return host_types(clean)
	return PackedStringArray()


static func type_line(id: String) -> String:
	var types := display_types(id)
	if types.is_empty():
		return ""
	var names := PackedStringArray()
	for type_id: String in types:
		names.append(type_title(type_id).to_upper())
	var label := "TYPE" if is_ability(catalog_id(id)) else "FITS"
	return "%s  //  %s" % [label, ", ".join(names)]


static func _ordered_types(seen: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for type_id: String in TYPE_ORDER:
		if seen.has(type_id):
			out.append(type_id)
	for type_id: Variant in seen.keys():
		var clean := str(type_id)
		if not out.has(clean):
			out.append(clean)
	return out


static func host_abilities(modifier_id: String) -> PackedStringArray:
	ensure_loaded()
	var clean := catalog_id(modifier_id)
	if not shows_host_mark(clean):
		return PackedStringArray()
	var seen := {}
	var out := PackedStringArray()
	for row: Dictionary in _effects:
		if str(row.get("modifier_id", "")) != clean:
			continue
		var target := str(row.get("ability_id", "")).strip_edges()
		if target.is_empty() or target == "*":
			continue
		if CrawlerRules.is_ability_type(target):
			for id: String in _abilities_of_type(target):
				if seen.has(id):
					continue
				seen[id] = true
				out.append(id)
			continue
		if seen.has(target):
			continue
		seen[target] = true
		out.append(target)
	return out


static func compatible(modifier_id: String, ability_id_value: String) -> bool:
	var clean_mod := catalog_id(modifier_id)
	var clean_ability := catalog_id(ability_id_value)
	if not is_modifier(clean_mod) or clean_ability.is_empty():
		return false
	if clean_ability == "overdrive":
		return true
	if scope_of(clean_mod) == "generic":
		return true
	return not effects_for(clean_mod, clean_ability).is_empty()


static func _abilities_of_type(type_id: String) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	if not CrawlerRules.is_ability_type(type_id):
		return out
	for id: String in _entries:
		if str(_entries[id].get("kind", "")) != CrawlerCard.KIND_ABILITY:
			continue
		if type_id == CrawlerRules.TYPE_LIMITED:
			if CrawlerRules.uses_ammo(id):
				out.append(id)
			continue
		if resolved_ability_type(id) != type_id:
			continue
		out.append(id)
	return out


static func resolved_ability_type(id: String) -> String:
	var from_csv := ability_type_of(id)
	if not from_csv.is_empty():
		return from_csv
	return CrawlerRules.ability_type(catalog_id(id))


static func effects_for(modifier_id: String, ability_id_value: String) -> Array[Dictionary]:
	ensure_loaded()
	var clean_mod := catalog_id(modifier_id)
	var clean_ability := catalog_id(ability_id_value)
	var typed := resolved_ability_type(clean_ability)
	var specific: Array[Dictionary] = []
	var type_rows: Array[Dictionary] = []
	var generic: Array[Dictionary] = []
	var claimed := {}
	for row: Dictionary in _effects:
		if str(row.get("modifier_id", "")) != clean_mod:
			continue
		var target := str(row.get("ability_id", ""))
		if target == clean_ability:
			specific.append(row)
			claimed[str(row.get("stat", ""))] = true
		elif target == typed and CrawlerRules.is_ability_type(typed):
			type_rows.append(row)
		elif target == CrawlerRules.TYPE_LIMITED \
				and CrawlerRules.uses_ammo(clean_ability):
			type_rows.append(row)
		elif target == "*":
			generic.append(row)
	var out: Array[Dictionary] = []
	out.append_array(specific)
	for row: Dictionary in type_rows:
		var stat := str(row.get("stat", ""))
		if claimed.has(stat):
			continue
		claimed[stat] = true
		out.append(row)
	for row: Dictionary in generic:
		if claimed.has(str(row.get("stat", ""))):
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
	if CrawlerRules.uses_ammo(clean) and not card.extra_stats.has("ammo"):
		var shots := CrawlerRules.base_ammo(clean)
		card.extra_stats["ammo"] = shots
		card.extra_stats["ammo_max"] = shots
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
			"ability_type": str(row.get("ability_type", "")).strip_edges(),
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
