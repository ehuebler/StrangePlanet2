class_name CrawlerCard
extends RefCounted

## One crawler ability or modifier instance.
##
## Catalogue ids may repeat — three Laser Eyes with different slot counts is
## three cards. Nested [member mods] travel with an ability when it is moved,
## dropped, or picked up.

const KIND_ABILITY := "ability"
const KIND_MODIFIER := "modifier"

var uid := ""
var kind := KIND_ABILITY
var id := ""
var slot_count := 0
var mods: Array[CrawlerCard] = []
var extra_stats: Dictionary = {}


func token() -> String:
	return CrawlerCatalog.token_for(self)


func is_ability() -> bool:
	return kind == KIND_ABILITY


func is_modifier() -> bool:
	return kind == KIND_MODIFIER


func shop_rank() -> int:
	return maxi(int(extra_stats.get("shop_rank", 0)), 0)


func add_shop_rank() -> void:
	extra_stats["shop_rank"] = shop_rank() + 1


func upgrade_rank(stat_id: String) -> int:
	var table: Variant = extra_stats.get("upgrades", {})
	if table is Dictionary:
		return maxi(int((table as Dictionary).get(stat_id, 0)), 0)
	return 0


func add_upgrade_rank(stat_id: String) -> void:
	if stat_id.is_empty():
		return
	var table: Dictionary = {}
	var held: Variant = extra_stats.get("upgrades", {})
	if held is Dictionary:
		table = (held as Dictionary).duplicate()
	table[stat_id] = upgrade_rank(stat_id) + 1
	extra_stats["upgrades"] = table
	add_shop_rank()


func fingerprint() -> String:
	var parts := PackedStringArray()
	parts.append(uid)
	parts.append(id)
	parts.append(str(slot_count))
	for index in slot_count:
		var child := mod_at(index)
		parts.append(child.fingerprint() if child != null else "")
	var stat_keys := extra_stats.keys()
	stat_keys.sort()
	for key: Variant in stat_keys:
		var name := str(key)
		if name == "ammo" or name == "ammo_max":
			continue
		parts.append("%s=%s" % [name, str(extra_stats[key])])
	return "|".join(parts)


func modifier_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for index in slot_count:
		var child := mod_at(index)
		out.append(child.id if child != null else "")
	return out


func filled_modifier_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for child: CrawlerCard in filled_mods():
		out.append(child.id)
	return out


func filled_mods() -> Array[CrawlerCard]:
	var out: Array[CrawlerCard] = []
	for index in slot_count:
		var child := mod_at(index)
		if child != null and not child.id.is_empty():
			out.append(child)
	return out


func mod_at(index: int) -> CrawlerCard:
	_ensure_mods()
	if index < 0 or index >= mods.size():
		return null
	return mods[index]


func place_mod(index: int, card: CrawlerCard) -> CrawlerCard:
	_ensure_mods()
	if index < 0 or index >= mods.size():
		return card
	var previous := mods[index]
	mods[index] = card
	return previous


func collect_tree() -> Array[CrawlerCard]:
	var out: Array[CrawlerCard] = [self]
	for index in slot_count:
		var child := mod_at(index)
		if child != null:
			out.append_array(child.collect_tree())
	return out


func to_dict() -> Dictionary:
	_ensure_mods()
	var nested: Array = []
	for index in slot_count:
		var child := mod_at(index)
		nested.append(child.to_dict() if child != null else {})
	return {
		"uid": uid,
		"kind": kind,
		"id": id,
		"slot_count": slot_count,
		"mods": nested,
		"extra_stats": extra_stats.duplicate(true),
	}


static func from_dict(data: Dictionary) -> CrawlerCard:
	if data.is_empty() or str(data.get("id", "")).is_empty():
		return null
	var card := CrawlerCard.new()
	card.uid = str(data.get("uid", ""))
	card.kind = str(data.get("kind", KIND_ABILITY))
	card.id = str(data.get("id", ""))
	card.slot_count = maxi(int(data.get("slot_count", 0)), 0)
	var extra: Variant = data.get("extra_stats", {})
	if extra is Dictionary:
		card.extra_stats = (extra as Dictionary).duplicate(true)
	card._ensure_mods()
	var nested: Variant = data.get("mods", [])
	if nested is Array:
		for index in mini(card.slot_count, (nested as Array).size()):
			var child_raw: Variant = nested[index]
			if child_raw is Dictionary and not (child_raw as Dictionary).is_empty():
				card.mods[index] = from_dict(child_raw as Dictionary)
	return card


func _ensure_mods() -> void:
	if mods.size() == slot_count:
		return
	var next: Array[CrawlerCard] = []
	next.resize(slot_count)
	for index in mini(slot_count, mods.size()):
		next[index] = mods[index]
	mods = next
