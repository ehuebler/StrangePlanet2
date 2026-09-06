class_name CrawlerKit
extends RefCounted

## Per-player crawler loadout: three equipped abilities and a shared bag.
##
## Slots still hold strings so [ItemContainer] and the existing tiles keep
## working. The string is a token; this object is the ledger that remembers the
## unique card, its modifier slots, and the CSV-resolved stats.

signal changed

const SOURCE_EQUIP := "crawler_equip"
const SOURCE_BAG := "crawler_bag"
const SOURCE_MOD := "crawler_mod"
const MOD_STRIDE := 16
const STARTER_REVISION := 4

static var session_payload: Dictionary = {}

var player: OnlinePlayer
var inventory := ItemContainer.new(CrawlerRules.INVENTORY_SLOTS)
var cards: Dictionary = {}
## Store upgrades for abilities are shared by catalogue id. Two Laser Eyes
## cards keep the same ranks and slot count; seated mods stay per copy.
var ability_ranks: Dictionary = {}
var _mod_racks: Array[ItemContainer] = []
var _syncing := false
var _remembering := false


static func clear_session() -> void:
	session_payload = {}


func bind(owner: OnlinePlayer) -> void:
	player = owner
	_configure_inventory()
	if player != null and player.abilities != null:
		if not player.abilities.changed.is_connected(_on_equipped_changed):
			player.abilities.changed.connect(_on_equipped_changed)
	_rebuild_mod_racks()


func restore_or_seed() -> void:
	if int(session_payload.get("revision", 0)) >= STARTER_REVISION \
			and not session_payload.is_empty():
		from_dict(session_payload)
	else:
		seed_starter()
	remember()


func seed_starter() -> void:
	_syncing = true
	_clear_containers()
	cards.clear()
	ability_ranks.clear()
	var eyes := CrawlerCatalog.make_ability(
		"laser_eyes", CrawlerRules.LASER_SLOTS, CrawlerRules.laser_start_stats())
	register(eyes)
	if player != null and eyes != null:
		player.abilities.set_item(0, eyes.token())
	_syncing = false
	_rebuild_mod_racks()
	_emit_changed()


func register(card: CrawlerCard) -> void:
	if card == null:
		return
	for node: CrawlerCard in card.collect_tree():
		if node != null and not node.uid.is_empty():
			cards[node.uid] = node


func card_for_token(token: String) -> CrawlerCard:
	return cards.get(CrawlerCatalog.uid_of(token), null) as CrawlerCard


func host_ability_for(token: String) -> CrawlerCard:
	if token.is_empty() or player == null or not is_instance_valid(player) \
			or player.abilities == null:
		return null
	for index in player.abilities.size():
		var hosted := equipped_card(index)
		if hosted == null:
			continue
		for child: CrawlerCard in hosted.collect_tree():
			if child != null and child != hosted and child.token() == token:
				return hosted
	return null


func equipped_card(index: int) -> CrawlerCard:
	if player == null or not is_instance_valid(player) or player.abilities == null:
		return null
	return card_for_token(player.abilities.get_item(index))


func inventory_card(index: int) -> CrawlerCard:
	return card_for_token(inventory.get_item(index))


func slot_fingerprint(index: int) -> String:
	var card := equipped_card(index)
	return card.fingerprint() if card != null else ""


func resolved_stats(index: int) -> Dictionary:
	var card := equipped_card(index)
	if card == null:
		return {}
	return stats_for(card)


func stats_for(card: CrawlerCard) -> Dictionary:
	if card == null or not card.is_ability():
		return {}
	var base := _with_card_stats(ItemDB.stats_of(card.id), card)
	base["slots"] = float(card.slot_count)
	var stats := CrawlerCatalog.resolve_stats(card.id, card.filled_modifier_ids(), base)
	_apply_shop_ranks(stats, card)
	return stats


func ability_upgrade_rank(catalog_id: String, stat_id: String) -> int:
	var table: Variant = _ability_rank_entry(catalog_id).get("upgrades", {})
	if table is Dictionary:
		return maxi(int((table as Dictionary).get(stat_id, 0)), 0)
	return 0


func ability_shop_rank(catalog_id: String) -> int:
	return maxi(int(_ability_rank_entry(catalog_id).get("shop_rank", 0)), 0)


func ability_slot_count(catalog_id: String) -> int:
	return maxi(int(_ability_rank_entry(catalog_id).get("slots", 0)),
		_default_ability_slots(catalog_id))


func upgrade_rank_for(card: CrawlerCard, stat_id: String) -> int:
	if card == null:
		return 0
	if card.is_ability():
		return ability_upgrade_rank(card.id, stat_id)
	return card.upgrade_rank(stat_id)


func shop_rank_for(card: CrawlerCard) -> int:
	if card == null:
		return 0
	if card.is_ability():
		return ability_shop_rank(card.id)
	return card.shop_rank()


func base_stats_for(card: CrawlerCard) -> Dictionary:
	if card == null or not card.is_ability():
		return {}
	var base := _with_card_stats(ItemDB.stats_of(card.id), card)
	if card.id == "laser_eyes":
		base["damage"] = CrawlerRules.LASER_DAMAGE
		base["cooldown"] = CrawlerRules.LASER_COOLDOWN
		base["duration"] = CrawlerRules.LASER_DURATION
		base["range"] = CrawlerRules.LASER_RANGE
		base["size"] = 1.0
		base["knockback"] = CrawlerRules.LASER_KNOCKBACK
		base["damage_unit"] = "/s"
		if not base.has("radius"):
			base["radius"] = 0.45
	elif card.id == "meteor_punch":
		base["damage"] = CrawlerRules.METEOR_DAMAGE
		base["impact"] = CrawlerRules.METEOR_IMPACT
		base["cooldown"] = CrawlerRules.METEOR_COOLDOWN
		base["range"] = CrawlerRules.METEOR_RANGE
		base["size"] = 1.0
		base["radius"] = CrawlerRules.METEOR_RADIUS
		base["crater_radius"] = CrawlerRules.METEOR_CRATER_RADIUS
		base["crater_depth"] = CrawlerRules.METEOR_CRATER_DEPTH
		base["speed"] = CrawlerRules.METEOR_SPEED
		base["knockback"] = CrawlerRules.METEOR_KNOCKBACK
	elif card.id == "starfire":
		base["damage"] = CrawlerRules.STARFIRE_DAMAGE
		base["impact"] = CrawlerRules.STARFIRE_IMPACT
		base["cooldown"] = CrawlerRules.STARFIRE_COOLDOWN
		base["range"] = CrawlerRules.STARFIRE_RANGE
		base["size"] = 1.0
		base["radius"] = CrawlerRules.STARFIRE_RADIUS
		base["projectile_radius"] = CrawlerRules.STARFIRE_PROJECTILE_RADIUS
		base["crater_radius"] = CrawlerRules.STARFIRE_CRATER_RADIUS
		base["knockback"] = CrawlerRules.STARFIRE_KNOCKBACK
	var slots := CrawlerCatalog.default_slots(card.id)
	if slots <= 0:
		slots = CrawlerRules.LASER_SLOTS
	base["slots"] = float(slots)
	return base


func _with_card_stats(authored: Dictionary, card: CrawlerCard) -> Dictionary:
	var stats := authored.duplicate(true)
	if card == null:
		return stats
	for key: Variant in card.extra_stats:
		var name := str(key)
		if name == "upgrades" or name == "shop_rank":
			continue
		stats[name] = card.extra_stats[key]
	return stats


func _apply_shop_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	if card.id == "laser_eyes":
		stats["damage"] = CrawlerRules.LASER_DAMAGE \
			+ 12.0 * float(upgrade_rank_for(card, "damage"))
		stats["cooldown"] = maxf(
			0.18,
			CrawlerRules.LASER_COOLDOWN - 0.05 * float(upgrade_rank_for(card, "cooldown")))
		stats["duration"] = CrawlerRules.LASER_DURATION \
			+ 0.06 * float(upgrade_rank_for(card, "duration"))
		stats["range"] = CrawlerRules.LASER_RANGE \
			+ CrawlerRules.LASER_RANGE_PER_RANK * float(upgrade_rank_for(card, "range"))
		var size := 1.0 + 0.10 * float(upgrade_rank_for(card, "size"))
		stats["size"] = size
		stats["knockback"] = CrawlerRules.LASER_KNOCKBACK \
			+ CrawlerRules.LASER_KNOCKBACK_PER_RANK \
			* float(upgrade_rank_for(card, "knockback"))
		stats["damage_unit"] = "/s"
		_scale_shop_stat(stats, "radius", size)
		_scale_shop_stat(stats, "beam_width", size)
		_scale_shop_stat(stats, "impact_radius", size)
	elif card.id == "meteor_punch":
		stats["damage"] = CrawlerRules.METEOR_DAMAGE \
			+ 40.0 * float(upgrade_rank_for(card, "damage"))
		stats["impact"] = CrawlerRules.METEOR_IMPACT \
			* (float(stats.get("damage", CrawlerRules.METEOR_DAMAGE))
				/ CrawlerRules.METEOR_DAMAGE)
		stats["cooldown"] = maxf(
			CrawlerRules.METEOR_COOLDOWN_MIN,
			CrawlerRules.METEOR_COOLDOWN
				- CrawlerRules.METEOR_COOLDOWN_PER_RANK
				* float(upgrade_rank_for(card, "cooldown")))
		stats["range"] = CrawlerRules.METEOR_RANGE \
			+ CrawlerRules.METEOR_RANGE_PER_RANK * float(upgrade_rank_for(card, "range"))
		var fist_size := 1.0 + CrawlerRules.METEOR_SIZE_PER_RANK \
			* float(upgrade_rank_for(card, "size"))
		stats["size"] = fist_size
		stats["knockback"] = CrawlerRules.METEOR_KNOCKBACK \
			+ CrawlerRules.METEOR_KNOCKBACK_PER_RANK \
			* float(upgrade_rank_for(card, "knockback"))
		stats["speed"] = CrawlerRules.METEOR_SPEED
		stats["radius"] = CrawlerRules.METEOR_RADIUS
		stats["crater_radius"] = CrawlerRules.METEOR_CRATER_RADIUS
		stats["crater_depth"] = CrawlerRules.METEOR_CRATER_DEPTH
		_scale_shop_stat(stats, "radius", fist_size)
		_scale_shop_stat(stats, "crater_radius", fist_size)
		_scale_shop_stat(stats, "crater_depth", fist_size)
	elif card.id == "starfire":
		var burst := CrawlerRules.STARFIRE_DAMAGE \
			+ CrawlerRules.STARFIRE_DAMAGE_PER_RANK * float(upgrade_rank_for(card, "damage"))
		stats["damage"] = burst
		stats["impact"] = CrawlerRules.STARFIRE_IMPACT \
			* (burst / CrawlerRules.STARFIRE_DAMAGE)
		stats["cooldown"] = maxf(
			CrawlerRules.STARFIRE_COOLDOWN_MIN,
			CrawlerRules.STARFIRE_COOLDOWN
				- CrawlerRules.STARFIRE_COOLDOWN_PER_RANK
				* float(upgrade_rank_for(card, "cooldown")))
		stats["range"] = CrawlerRules.STARFIRE_RANGE \
			+ CrawlerRules.STARFIRE_RANGE_PER_RANK * float(upgrade_rank_for(card, "range"))
		var disk_size := 1.0 + CrawlerRules.STARFIRE_SIZE_PER_RANK \
			* float(upgrade_rank_for(card, "size"))
		stats["size"] = disk_size
		stats["knockback"] = CrawlerRules.STARFIRE_KNOCKBACK \
			+ CrawlerRules.STARFIRE_KNOCKBACK_PER_RANK \
			* float(upgrade_rank_for(card, "knockback"))
		_scale_shop_stat(stats, "radius", disk_size)
		_scale_shop_stat(stats, "projectile_radius", disk_size)
		_scale_shop_stat(stats, "crater_radius", disk_size)
	for index in card.slot_count:
		var child := card.mod_at(index)
		if child == null:
			continue
		_apply_mod_upgrade(stats, child, card.id)
	if card.id == "starfire":
		var authored := CrawlerRules.STARFIRE_RADIUS
		if authored > 0.0:
			stats["size"] = float(stats.get("radius", authored)) / authored
	elif card.id == "meteor_punch":
		var authored := CrawlerRules.METEOR_RADIUS
		if authored > 0.0:
			stats["size"] = float(stats.get("radius", authored)) / authored
	elif card.id == "laser_eyes":
		var authored := 0.45
		var listed: Variant = ItemDB.stats_of(card.id).get("radius", authored)
		if typeof(listed) == TYPE_FLOAT or typeof(listed) == TYPE_INT:
			authored = maxf(float(listed), 0.01)
		stats["size"] = float(stats.get("radius", authored)) / authored


func _apply_mod_upgrade(stats: Dictionary, mod: CrawlerCard, host_id := "") -> void:
	if mod.id == "wobble":
		var rank := maxi(mod.upgrade_rank("wobble"), mod.shop_rank())
		if rank <= 0:
			return
		stats["wobble"] = float(stats.get("wobble", 1.0)) + 0.45 * float(rank)
		stats["wobble_cone_degrees"] = float(stats.get("wobble_cone_degrees", 16.0)) \
			+ 7.0 * float(rank)
		_scale_shop_stat(stats, "damage", maxf(0.45, 1.0 - 0.10 * float(rank)))
		return
	if mod.id == "big":
		var rank := clampi(mod.upgrade_rank("size"), 0, CrawlerRules.BIG_SIZE_MAX_RANK)
		var wanted := CrawlerRules.big_size_scale(rank)
		var already := CrawlerCatalog.size_mul_for("big", host_id)
		var extra := wanted / already if already > 0.0001 else wanted
		_scale_shop_stat(stats, "size", extra)
		_scale_shop_stat(stats, "radius", extra)
		_scale_shop_stat(stats, "beam_width", extra)
		_scale_shop_stat(stats, "impact_radius", extra)
		_scale_shop_stat(stats, "projectile_radius", extra)
		_scale_shop_stat(stats, "crater_radius", extra)


func _scale_shop_stat(stats: Dictionary, key: String, scale: float) -> void:
	if not stats.has(key):
		if key != "beam_width":
			return
		stats[key] = 1.0
	stats[key] = float(stats[key]) * scale


func mod_rack(index: int) -> ItemContainer:
	if index < 0 or index >= _mod_racks.size():
		return null
	return _mod_racks[index]


func token_at(source: String, index: int) -> String:
	var found := _locate(source, index)
	if found.is_empty():
		return ""
	return str(found.get("token", ""))


func payload_at(source: String, index: int) -> Dictionary:
	var card := card_for_token(token_at(source, index))
	return card.to_dict() if card != null else {}


func extract(source: String, index: int, expected_token := "") -> Dictionary:
	var token := token_at(source, index)
	if token.is_empty() or (not expected_token.is_empty() and token != expected_token):
		return {}
	var card := card_for_token(token)
	if card == null:
		return {}
	var payload := card.to_dict()
	_clear_located(source, index)
	_unregister_tree(card)
	_rebuild_mod_racks()
	_emit_changed()
	return payload


func owned_cards() -> Array[CrawlerCard]:
	var out: Array[CrawlerCard] = []
	var seen: Dictionary = {}
	if player != null and player.abilities != null:
		for index in player.abilities.size():
			var card := equipped_card(index)
			if card == null or seen.has(card.uid):
				continue
			seen[card.uid] = true
			out.append(card)
			for child: CrawlerCard in card.collect_tree():
				if child == null or child == card or seen.has(child.uid):
					continue
				seen[child.uid] = true
				out.append(child)
	for index in inventory.size():
		var card := inventory_card(index)
		if card == null or seen.has(card.uid):
			continue
		seen[card.uid] = true
		out.append(card)
	return out


func shop_grant(catalog_id: String) -> bool:
	var card: CrawlerCard
	if CrawlerCatalog.is_ability(catalog_id):
		if not CrawlerRules.ability_enabled(catalog_id) \
				or CrawlerProgress.ability_price(catalog_id) <= 0:
			return false
		card = CrawlerCatalog.make_ability(catalog_id)
		if card == null:
			return false
		register(card)
		_apply_shared_ability_ranks(card)
		return _shop_place_ability(card)
	if CrawlerCatalog.is_modifier(catalog_id):
		card = CrawlerCatalog.make_modifier(catalog_id)
	else:
		return false
	if card == null:
		return false
	var result := grant(card.to_dict())
	return bool(result.get("ok", false))


func upgrade_card(uid: String, stat_id := "") -> bool:
	var card := cards.get(uid) as CrawlerCard
	if card == null:
		return false
	var wanted := stat_id
	if wanted.is_empty():
		var listed := CrawlerRules.upgrade_stats_for(card.id)
		wanted = listed[0] if not listed.is_empty() else ""
	if not CrawlerRules.upgrade_stats_for(card.id).has(wanted):
		return false
	if card.is_ability() and not CrawlerRules.ability_enabled(card.id):
		return false
	if card.is_ability():
		return _upgrade_shared_ability(card, wanted)
	if wanted == "slots":
		if card.slot_count >= CrawlerRules.MAX_MOD_SLOTS:
			return false
		card.slot_count += 1
		card._ensure_mods()
	var cap := CrawlerRules.upgrade_max_rank(card.id, wanted)
	if cap > 0 and card.upgrade_rank(wanted) >= cap:
		return false
	card.add_upgrade_rank(wanted)
	_rebuild_mod_racks()
	_emit_changed()
	return true


## World pickup. Abilities take an empty hotbar slot, or swap the selected
## one when the bar is full. Modifiers still fill the bag, then a free seat.
func grant(payload: Dictionary, swap_equipped_index := 0) -> Dictionary:
	var card := CrawlerCard.from_dict(payload)
	if card == null:
		return {"ok": false}
	register(card)
	if card.is_ability():
		_apply_shared_ability_ranks(card)
		return _grant_ability(card, swap_equipped_index)
	return _grant_modifier(card)


func move_card(from_source: String, from_index: int, to_source: String, to_index: int) -> bool:
	if from_source == SOURCE_MOD or to_source == SOURCE_MOD:
		return false
	if from_source == to_source and from_index == to_index:
		return false
	var from_found := _locate(from_source, from_index)
	var to_found := _locate(to_source, to_index)
	var from_container := from_found.get("container") as ItemContainer
	var to_container := to_found.get("container") as ItemContainer
	if from_container == null or to_container == null:
		return false
	return ItemContainer.transfer(
		from_container,
		int(from_found.get("index", -1)),
		to_container,
		int(to_found.get("index", -1))
	)


func unequip_to_bag(index: int) -> bool:
	if player == null or player.abilities == null:
		return false
	var token := player.abilities.get_item(index)
	if token.is_empty():
		return false
	var dest := inventory.first_accepting(token)
	if dest < 0:
		return false
	return ItemContainer.transfer(player.abilities, index, inventory, dest)


func remember() -> void:
	session_payload = to_dict()


func to_dict() -> Dictionary:
	var equipped: Array = []
	if player != null and player.abilities != null:
		for index in player.abilities.size():
			var card := equipped_card(index)
			equipped.append(card.to_dict() if card != null else {})
	var bag: Array = []
	for index in inventory.size():
		var card := inventory_card(index)
		bag.append(card.to_dict() if card != null else {})
	return {
		"revision": STARTER_REVISION,
		"equipped": equipped,
		"inventory": bag,
		"ability_ranks": ability_ranks.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_syncing = true
	_clear_containers()
	cards.clear()
	ability_ranks.clear()
	var equipped_raw: Variant = data.get("equipped", [])
	if equipped_raw is Array and player != null and player.abilities != null:
		for index in mini(player.abilities.size(), (equipped_raw as Array).size()):
			var raw: Variant = equipped_raw[index]
			if raw is Dictionary:
				var card := CrawlerCard.from_dict(raw as Dictionary)
				if card != null:
					register(card)
					player.abilities.set_item(index, card.token())
	var bag_raw: Variant = data.get("inventory", [])
	if bag_raw is Array:
		for index in mini(inventory.size(), (bag_raw as Array).size()):
			var raw: Variant = bag_raw[index]
			if raw is Dictionary:
				var card := CrawlerCard.from_dict(raw as Dictionary)
				if card != null:
					register(card)
					inventory.set_item(index, card.token())
	var ranks_raw: Variant = data.get("ability_ranks", {})
	if ranks_raw is Dictionary and not (ranks_raw as Dictionary).is_empty():
		ability_ranks = (ranks_raw as Dictionary).duplicate(true)
	else:
		_fold_ability_ranks_from_cards()
	_sync_all_ability_copies()
	_syncing = false
	_rebuild_mod_racks()
	_emit_changed()


func _upgrade_shared_ability(card: CrawlerCard, wanted: String) -> bool:
	var entry := _ability_rank_entry(card.id)
	if wanted == "slots":
		var slots := maxi(int(entry.get("slots", 0)), card.slot_count)
		if slots >= CrawlerRules.MAX_MOD_SLOTS:
			return false
		entry["slots"] = slots + 1
	var table: Dictionary = {}
	var held: Variant = entry.get("upgrades", {})
	if held is Dictionary:
		table = (held as Dictionary).duplicate()
	table[wanted] = int(table.get(wanted, 0)) + 1
	entry["upgrades"] = table
	entry["shop_rank"] = int(entry.get("shop_rank", 0)) + 1
	ability_ranks[card.id] = entry
	_sync_ability_copies(card.id)
	_rebuild_mod_racks()
	_emit_changed()
	return true


func _shop_place_ability(card: CrawlerCard) -> bool:
	var token := card.token()
	if player != null and player.abilities != null:
		var equip := player.abilities.first_accepting(token)
		if equip >= 0:
			player.abilities.set_item(equip, token)
			_rebuild_mod_racks()
			_emit_changed()
			return true
	var bag := inventory.first_accepting(token)
	if bag >= 0:
		inventory.set_item(bag, token)
		_emit_changed()
		return true
	_unregister_tree(card)
	return false


func _apply_shared_ability_ranks(card: CrawlerCard) -> void:
	if card == null or not card.is_ability() or card.id.is_empty():
		return
	var entry := _ability_rank_entry(card.id)
	var upgrades: Variant = entry.get("upgrades", {})
	if upgrades is Dictionary:
		card.extra_stats["upgrades"] = (upgrades as Dictionary).duplicate(true)
	card.extra_stats["shop_rank"] = int(entry.get("shop_rank", 0))
	var slots := maxi(int(entry.get("slots", 0)), _default_ability_slots(card.id))
	slots = maxi(slots, card.slot_count)
	card.slot_count = slots
	card._ensure_mods()


func _sync_ability_copies(catalog_id: String) -> void:
	for card: Variant in cards.values():
		var held := card as CrawlerCard
		if held != null and held.is_ability() and held.id == catalog_id:
			_apply_shared_ability_ranks(held)


func _sync_all_ability_copies() -> void:
	var seen := {}
	for card: Variant in cards.values():
		var held := card as CrawlerCard
		if held == null or not held.is_ability() or held.id.is_empty() \
				or seen.has(held.id):
			continue
		seen[held.id] = true
		_sync_ability_copies(held.id)


func _fold_ability_ranks_from_cards() -> void:
	ability_ranks.clear()
	for card: Variant in cards.values():
		var held := card as CrawlerCard
		if held == null or not held.is_ability() or held.id.is_empty():
			continue
		var entry := _ability_rank_entry(held.id)
		var upgrades: Dictionary = {}
		var existing: Variant = entry.get("upgrades", {})
		if existing is Dictionary:
			upgrades = (existing as Dictionary).duplicate()
		var table: Variant = held.extra_stats.get("upgrades", {})
		if table is Dictionary:
			for key: Variant in table:
				var name := str(key)
				upgrades[name] = maxi(int(upgrades.get(name, 0)), int(table[key]))
		entry["upgrades"] = upgrades
		entry["shop_rank"] = maxi(int(entry.get("shop_rank", 0)), held.shop_rank())
		entry["slots"] = maxi(int(entry.get("slots", 0)), held.slot_count)
		ability_ranks[held.id] = entry


func _ability_rank_entry(catalog_id: String) -> Dictionary:
	if catalog_id.is_empty():
		return {"upgrades": {}, "shop_rank": 0, "slots": 0}
	if ability_ranks.has(catalog_id) and ability_ranks[catalog_id] is Dictionary:
		var held := (ability_ranks[catalog_id] as Dictionary).duplicate(true)
		if not held.has("upgrades") or not (held.get("upgrades") is Dictionary):
			held["upgrades"] = {}
		if not held.has("shop_rank"):
			held["shop_rank"] = 0
		if not held.has("slots"):
			held["slots"] = _max_owned_slots(catalog_id)
		return held
	return {
		"upgrades": {},
		"shop_rank": 0,
		"slots": _max_owned_slots(catalog_id),
	}


func _default_ability_slots(catalog_id: String) -> int:
	var slots := CrawlerCatalog.default_slots(catalog_id)
	return slots if slots > 0 else CrawlerRules.LASER_SLOTS


func _max_owned_slots(catalog_id: String) -> int:
	var best := _default_ability_slots(catalog_id)
	for card: Variant in cards.values():
		var held := card as CrawlerCard
		if held != null and held.is_ability() and held.id == catalog_id:
			best = maxi(best, held.slot_count)
	return best


func _grant_ability(card: CrawlerCard, swap_equipped_index: int) -> Dictionary:
	var token := card.token()
	if player == null or player.abilities == null:
		_unregister_tree(card)
		return {"ok": false}
	var equip := player.abilities.first_accepting(token)
	if equip >= 0:
		player.abilities.set_item(equip, token)
		_rebuild_mod_racks()
		_emit_changed()
		return {"ok": true}
	var slot := clampi(swap_equipped_index, 0, player.abilities.size() - 1)
	var old_token := player.abilities.get_item(slot)
	var old := card_for_token(old_token)
	var displaced := old.to_dict() if old != null else {}
	if old != null:
		_unregister_tree(old)
	player.abilities.set_item(slot, token)
	_rebuild_mod_racks()
	_emit_changed()
	return {"ok": true, "displaced": displaced}


func _grant_modifier(card: CrawlerCard) -> Dictionary:
	var token := card.token()
	var bag := inventory.first_accepting(token)
	if bag >= 0:
		inventory.set_item(bag, token)
		_emit_changed()
		return {"ok": true}
	if player != null and player.abilities != null:
		for index in player.abilities.size():
			var host := equipped_card(index)
			var rack := mod_rack(index)
			if host == null or rack == null:
				continue
			if not CrawlerCatalog.compatible(card.id, host.id):
				continue
			var dest := rack.first_accepting(token)
			if dest < 0:
				continue
			rack.set_item(dest, token)
			_emit_changed()
			return {"ok": true}
	_unregister_tree(card)
	return {"ok": false}


func _configure_inventory() -> void:
	if inventory.size() != CrawlerRules.INVENTORY_SLOTS:
		var previous := inventory
		if previous != null and previous.changed.is_connected(_on_inventory_changed):
			previous.changed.disconnect(_on_inventory_changed)
		inventory = ItemContainer.new(CrawlerRules.INVENTORY_SLOTS)
		if previous != null:
			for index in mini(previous.size(), inventory.size()):
				inventory.set_item(index, previous.get_item(index))
	for index in inventory.size():
		inventory.set_filter(index, CrawlerCatalog.FILTER_KIT)
	if not inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.connect(_on_inventory_changed)


func _rebuild_mod_racks() -> void:
	var previous := _mod_racks
	_mod_racks = []
	if player == null or player.abilities == null:
		return
	for index in player.abilities.size():
		var card := equipped_card(index)
		var slots := card.slot_count if card != null else 0
		var rack := ItemContainer.new(slots)
		for mod_index in slots:
			rack.set_filter(
				mod_index,
				"%s:%s" % [CrawlerCatalog.FILTER_MOD, card.id]
			)
			var child := card.mod_at(mod_index)
			if child != null:
				rack.set_item(mod_index, child.token())
		rack.changed.connect(_on_mod_rack_changed.bind(index))
		_mod_racks.append(rack)
	for rack: ItemContainer in previous:
		if rack != null and rack.changed.is_connected(_on_mod_rack_changed):
			pass


func _on_mod_rack_changed(index: int) -> void:
	if _syncing:
		return
	var card := equipped_card(index)
	var rack := mod_rack(index)
	if card == null or rack == null:
		return
	for mod_index in rack.size():
		card.place_mod(mod_index, card_for_token(rack.get_item(mod_index)))
	_emit_changed()


func _on_equipped_changed() -> void:
	if _syncing:
		return
	_rebuild_mod_racks()
	_emit_changed()


func _on_inventory_changed() -> void:
	if _syncing:
		return
	_emit_changed()


func _emit_changed() -> void:
	if _remembering:
		return
	_remembering = true
	remember()
	changed.emit()
	_remembering = false


func _clear_containers() -> void:
	if player != null and player.abilities != null:
		player.abilities.clear()
	inventory.clear()


func _unregister_tree(card: CrawlerCard) -> void:
	if card == null:
		return
	for node: CrawlerCard in card.collect_tree():
		cards.erase(node.uid)


func _locate(source: String, index: int) -> Dictionary:
	match source:
		SOURCE_EQUIP:
			if player == null or not is_instance_valid(player) \
					or player.abilities == null:
				return {}
			if index < 0 or index >= player.abilities.size():
				return {}
			return {
				"token": player.abilities.get_item(index),
				"container": player.abilities,
				"index": index,
			}
		SOURCE_BAG:
			if index < 0 or index >= inventory.size():
				return {}
			return {
				"token": inventory.get_item(index),
				"container": inventory,
				"index": index,
			}
		SOURCE_MOD:
			var equip_index := index / MOD_STRIDE
			var mod_index := index % MOD_STRIDE
			var rack := mod_rack(equip_index)
			if rack == null or mod_index < 0 or mod_index >= rack.size():
				return {}
			return {
				"token": rack.get_item(mod_index),
				"container": rack,
				"index": mod_index,
			}
	return {}


func _clear_located(source: String, index: int) -> void:
	var found := _locate(source, index)
	var container := found.get("container") as ItemContainer
	if container == null:
		return
	_syncing = true
	container.set_item(int(found.get("index", -1)), "")
	if source == SOURCE_MOD:
		var card := equipped_card(index / MOD_STRIDE)
		if card != null:
			card.place_mod(index % MOD_STRIDE, null)
	_syncing = false


func encode_mod_index(equip_index: int, mod_index: int) -> int:
	return equip_index * MOD_STRIDE + mod_index
