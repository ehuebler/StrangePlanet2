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
const SOURCE_CITY_EQUIP := "crawler_city_equip"
const SOURCE_CITY_BAG := "crawler_city_bag"
const SOURCE_CITY_MOD := "crawler_city_mod"
const MOD_STRIDE := 16
const STARTER_REVISION := 4

static var session_payload: Dictionary = {}

var player: OnlinePlayer
var inventory := ItemContainer.new(CrawlerRules.INVENTORY_SLOTS)
var city_inventory := ItemContainer.new(CrawlerRules.INVENTORY_SLOTS)
var cards: Dictionary = {}
## Store upgrades for abilities are shared by catalogue id. Two Laser Eyes
## cards keep the same ranks and slot count; seated mods stay per copy.
var ability_ranks: Dictionary = {}
## Bank kits (city locker UI) keep their own bar and do not write session_payload.
var standalone := false
var _equip: ItemContainer
var city_equip := ItemContainer.new(CrawlerRules.ABILITY_SLOTS)
var _mod_racks: Array[ItemContainer] = []
var _city_mod_racks: Array[ItemContainer] = []
var _syncing := false
var _remembering := false


static func clear_session() -> void:
	session_payload = {}


func bind(owner: OnlinePlayer) -> void:
	player = owner
	standalone = false
	_configure_inventory()
	_configure_city_bank()
	var bar := ability_bar()
	if bar != null and not bar.changed.is_connected(_on_equipped_changed):
		bar.changed.connect(_on_equipped_changed)
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()


func open_bank(equip_slots: int, bag_slots := 0) -> void:
	standalone = true
	player = null
	_equip = ItemContainer.new(maxi(equip_slots, 1))
	_apply_ability_filters(_equip)
	if not _equip.changed.is_connected(_on_equipped_changed):
		_equip.changed.connect(_on_equipped_changed)
	if inventory != null and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)
	inventory = ItemContainer.new(maxi(bag_slots, 0))
	for index in inventory.size():
		inventory.set_filter(index, CrawlerCatalog.FILTER_KIT)
	if inventory.size() > 0 \
			and not inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.connect(_on_inventory_changed)
	_rebuild_mod_racks()


func ability_bar() -> ItemContainer:
	if _equip != null:
		return _equip
	if player != null and is_instance_valid(player) and player.abilities != null:
		return player.abilities
	return null


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
	_configure_city_bank()
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()
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
	if token.is_empty():
		return null
	var hosted := _host_in_bar(ability_bar(), token)
	if hosted != null:
		return hosted
	return _host_in_bar(city_equip, token)


func equipped_card(index: int) -> CrawlerCard:
	var bar := ability_bar()
	if bar == null:
		return null
	return card_for_token(bar.get_item(index))


func city_equipped_card(index: int) -> CrawlerCard:
	if city_equip == null:
		return null
	return card_for_token(city_equip.get_item(index))


func city_inventory_card(index: int) -> CrawlerCard:
	if city_inventory == null:
		return null
	return card_for_token(city_inventory.get_item(index))


func city_mod_rack(index: int) -> ItemContainer:
	if index < 0 or index >= _city_mod_racks.size():
		return null
	return _city_mod_racks[index]


func mod_rack_for(source: String, index: int) -> ItemContainer:
	if source == SOURCE_CITY_EQUIP:
		return city_mod_rack(index)
	return mod_rack(index)


func inventory_card(index: int) -> CrawlerCard:
	return card_for_token(inventory.get_item(index))


func slot_fingerprint(index: int) -> String:
	var card := equipped_card(index)
	return card.fingerprint() if card != null else ""


func uses_ammo(card: CrawlerCard) -> bool:
	return card != null and card.is_ability() and CrawlerRules.uses_ammo(card.id)


func has_endless(card: CrawlerCard) -> bool:
	if card == null:
		return false
	for child: CrawlerCard in card.filled_mods():
		if child != null and child.id == "endless":
			return true
	return false


func clip_mul(card: CrawlerCard) -> int:
	if card == null:
		return 1
	var best := 1
	for child: CrawlerCard in card.filled_mods():
		if child == null or child.id != "clip":
			continue
		best = maxi(best, CrawlerRules.clip_ammo_mul(child.upgrade_rank("ammo")))
	return best


func ammo_max(card: CrawlerCard) -> int:
	if not uses_ammo(card):
		return 0
	return CrawlerRules.base_ammo(card.id) * clip_mul(card)


func ammo_left(card: CrawlerCard) -> int:
	if not uses_ammo(card):
		return 0
	sync_ammo(card)
	if has_endless(card):
		return ammo_max(card)
	return maxi(int(card.extra_stats.get("ammo", 0)), 0)


func can_fire(card: CrawlerCard) -> bool:
	if not uses_ammo(card):
		return true
	if has_endless(card):
		return true
	return ammo_left(card) > 0


func ammo_count_text(card: CrawlerCard) -> String:
	if not uses_ammo(card):
		return ""
	if has_endless(card):
		return "∞"
	return str(ammo_left(card))


func ammo_line(card: CrawlerCard) -> String:
	if not uses_ammo(card):
		return ""
	if has_endless(card):
		return "INFINITE"
	return "%d / %d" % [ammo_left(card), ammo_max(card)]


func spend_ammo(card: CrawlerCard) -> bool:
	if not uses_ammo(card) or has_endless(card):
		return uses_ammo(card)
	sync_ammo(card)
	var left := maxi(int(card.extra_stats.get("ammo", 0)), 0)
	if left <= 0:
		return false
	card.extra_stats["ammo"] = left - 1
	_emit_changed()
	return true


func refund_ammo(card: CrawlerCard) -> void:
	if not uses_ammo(card) or has_endless(card):
		return
	sync_ammo(card)
	var left := maxi(int(card.extra_stats.get("ammo", 0)), 0)
	var ceiling := ammo_max(card)
	if left >= ceiling:
		return
	card.extra_stats["ammo"] = left + 1
	_emit_changed()


func refill_ammo(card: CrawlerCard) -> bool:
	if not uses_ammo(card) or has_endless(card):
		return false
	sync_ammo(card)
	var ceiling := ammo_max(card)
	var left := maxi(int(card.extra_stats.get("ammo", 0)), 0)
	if left >= ceiling:
		return false
	card.extra_stats["ammo"] = ceiling
	_emit_changed()
	return true


func needs_ammo_refill() -> bool:
	for raw: Variant in cards.values():
		var card := raw as CrawlerCard
		if card == null or not card.is_ability() or has_endless(card):
			continue
		if uses_ammo(card) and ammo_left(card) < ammo_max(card):
			return true
	return false


func refill_all_ammo() -> bool:
	var any := false
	for raw: Variant in cards.values():
		var card := raw as CrawlerCard
		if refill_ammo(card):
			any = true
	return any


func sync_ammo(card: CrawlerCard) -> void:
	if not uses_ammo(card):
		return
	var new_max := ammo_max(card)
	if has_endless(card):
		card.extra_stats["ammo_max"] = new_max
		return
	var old_max := maxi(int(card.extra_stats.get("ammo_max", 0)), 0)
	if not card.extra_stats.has("ammo"):
		card.extra_stats["ammo"] = new_max
	elif old_max > 0 and new_max > old_max:
		var left := maxi(int(card.extra_stats.get("ammo", 0)), 0)
		card.extra_stats["ammo"] = mini(left + (new_max - old_max), new_max)
	else:
		card.extra_stats["ammo"] = clampi(
			int(card.extra_stats.get("ammo", 0)), 0, new_max)
	card.extra_stats["ammo_max"] = new_max


func _sync_all_ammo() -> void:
	for raw: Variant in cards.values():
		var card := raw as CrawlerCard
		if card != null and card.is_ability():
			sync_ammo(card)


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
	_apply_active_overdrive(stats, card)
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
	if CrawlerRules.is_pulsed_beam(card.id):
		if card.id == "kame":
			base["damage"] = CrawlerRules.KAME_DAMAGE
			base["cooldown"] = CrawlerRules.KAME_COOLDOWN
			base["duration"] = CrawlerRules.KAME_DURATION
			base["range"] = CrawlerRules.KAME_RANGE
			base["knockback"] = CrawlerRules.KAME_KNOCKBACK
			base["radius"] = CrawlerRules.KAME_RADIUS
			base["beam_width"] = CrawlerRules.KAME_BEAM_WIDTH
			base["damage_hz"] = CrawlerRules.KAME_DAMAGE_HZ
		elif card.id == "lightning":
			var bolt := CrawlerRules.lightning_start_stats()
			for key: Variant in bolt:
				base[str(key)] = bolt[key]
		else:
			base["damage"] = CrawlerRules.LASER_DAMAGE
			base["cooldown"] = CrawlerRules.LASER_COOLDOWN
			base["duration"] = CrawlerRules.LASER_DURATION
			base["range"] = CrawlerRules.LASER_RANGE
			base["knockback"] = CrawlerRules.LASER_KNOCKBACK
			if not base.has("radius"):
				base["radius"] = 0.45
		base["size"] = 1.0
		base["damage_unit"] = ""
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
	elif card.id == "hero_punch":
		var jab := CrawlerRules.hero_punch_start_stats()
		for key: Variant in jab:
			base[str(key)] = jab[key]
	elif card.id == "starfire":
		base["damage"] = CrawlerRules.STARFIRE_DAMAGE
		base["impact"] = CrawlerRules.STARFIRE_IMPACT
		base["player_damage"] = CrawlerRules.STARFIRE_PLAYER_DAMAGE
		base["cooldown"] = CrawlerRules.STARFIRE_COOLDOWN
		base["range"] = CrawlerRules.STARFIRE_RANGE
		base["size"] = 1.0
		base["radius"] = CrawlerRules.STARFIRE_RADIUS
		base["projectile_radius"] = CrawlerRules.STARFIRE_PROJECTILE_RADIUS
		base["crater_radius"] = CrawlerRules.STARFIRE_CRATER_RADIUS
		base["knockback"] = CrawlerRules.STARFIRE_KNOCKBACK
	elif card.id == "light_bolt":
		var bolt := CrawlerRules.light_bolt_start_stats()
		for key: Variant in bolt:
			base[str(key)] = bolt[key]
	elif card.id == "icicle":
		var spear := CrawlerRules.icicle_start_stats()
		for key: Variant in spear:
			base[str(key)] = spear[key]
	elif card.id == "teleport":
		var marker := CrawlerRules.teleport_start_stats()
		for key: Variant in marker:
			base[str(key)] = marker[key]
	elif card.id == "fus":
		var shout := CrawlerRules.fus_start_stats()
		for key: Variant in shout:
			base[str(key)] = shout[key]
	elif CrawlerRules.is_roar_ability(card.id):
		var roar := CrawlerRules.roar_start_stats(card.id)
		for key: Variant in roar:
			base[str(key)] = roar[key]
	elif CrawlerRules.is_field_ability(card.id):
		var field := CrawlerRules.field_start_stats(card.id)
		for key: Variant in field:
			base[str(key)] = field[key]
	elif card.id == "wall":
		var wall := CrawlerRules.wall_start_stats()
		for key: Variant in wall:
			base[str(key)] = wall[key]
	elif card.id == "nuke":
		base["damage"] = CrawlerRules.NUKE_DAMAGE
		base["impact"] = CrawlerRules.NUKE_IMPACT
		base["player_damage"] = CrawlerRules.NUKE_PLAYER_DAMAGE
	elif card.id == "mini_nuke":
		var orb := CrawlerRules.mini_nuke_start_stats()
		for key: Variant in orb:
			base[str(key)] = orb[key]
	elif card.id == "nausicaa":
		var sweep := CrawlerRules.nausicaa_start_stats()
		for key: Variant in sweep:
			base[str(key)] = sweep[key]
	elif card.id == "overdrive":
		var surge := CrawlerRules.overdrive_start_stats()
		for key: Variant in surge:
			base[str(key)] = surge[key]
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
		if name == "upgrades" or name == "shop_rank" \
				or name == "ammo" or name == "ammo_max":
			continue
		stats[name] = card.extra_stats[key]
	return stats


func _apply_shop_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	if card.id == "lightning":
		_apply_lightning_ranks(stats, card)
	elif CrawlerRules.is_pulsed_beam(card.id):
		_apply_pulsed_beam_ranks(stats, card)
	elif card.id == "wall":
		_apply_wall_ranks(stats, card)
	elif card.id == "mini_nuke":
		_apply_mini_nuke_ranks(stats, card)
	elif card.id == "nausicaa":
		_apply_nausicaa_ranks(stats, card)
	elif card.id == "meteor_punch":
		stats["damage"] = CrawlerRules.scaled_stat(
			CrawlerRules.METEOR_DAMAGE, upgrade_rank_for(card, "damage"))
		stats["impact"] = CrawlerRules.METEOR_IMPACT \
			* (float(stats.get("damage", CrawlerRules.METEOR_DAMAGE))
				/ CrawlerRules.METEOR_DAMAGE)
		stats["cooldown"] = maxf(
			CrawlerRules.METEOR_COOLDOWN_MIN,
			CrawlerRules.METEOR_COOLDOWN
				- CrawlerRules.METEOR_COOLDOWN_PER_RANK
				* float(upgrade_rank_for(card, "cooldown")))
		stats["range"] = CrawlerRules.scaled_stat(
			CrawlerRules.METEOR_RANGE, upgrade_rank_for(card, "range"))
		var fist_size := _rank_scale(card, "size")
		stats["size"] = fist_size
		stats["knockback"] = CrawlerRules.scaled_stat(
			CrawlerRules.METEOR_KNOCKBACK, upgrade_rank_for(card, "knockback"))
		stats["speed"] = CrawlerRules.METEOR_SPEED
		stats["radius"] = CrawlerRules.METEOR_RADIUS
		stats["crater_radius"] = CrawlerRules.METEOR_CRATER_RADIUS
		stats["crater_depth"] = CrawlerRules.METEOR_CRATER_DEPTH
		_scale_shop_stat(stats, "radius", fist_size)
		_scale_shop_stat(stats, "crater_radius", fist_size)
		_scale_shop_stat(stats, "crater_depth", fist_size)
	elif card.id == "hero_punch":
		_apply_hero_punch_ranks(stats, card)
	elif card.id == "overdrive":
		_apply_overdrive_ranks(stats, card)
	elif card.id == "starfire":
		var burst := CrawlerRules.scaled_stat(
			CrawlerRules.STARFIRE_DAMAGE, upgrade_rank_for(card, "damage"))
		stats["damage"] = burst
		stats["impact"] = CrawlerRules.STARFIRE_IMPACT \
			* (burst / CrawlerRules.STARFIRE_DAMAGE)
		stats["player_damage"] = CrawlerRules.STARFIRE_PLAYER_DAMAGE \
			* (burst / CrawlerRules.STARFIRE_DAMAGE)
		stats["cooldown"] = maxf(
			CrawlerRules.STARFIRE_COOLDOWN_MIN,
			CrawlerRules.STARFIRE_COOLDOWN
				- CrawlerRules.STARFIRE_COOLDOWN_PER_RANK
				* float(upgrade_rank_for(card, "cooldown")))
		stats["range"] = CrawlerRules.scaled_stat(
			CrawlerRules.STARFIRE_RANGE, upgrade_rank_for(card, "range"))
		var disk_size := _rank_scale(card, "size")
		stats["size"] = disk_size
		stats["knockback"] = CrawlerRules.scaled_stat(
			CrawlerRules.STARFIRE_KNOCKBACK, upgrade_rank_for(card, "knockback"))
		_scale_shop_stat(stats, "radius", disk_size)
		_scale_shop_stat(stats, "projectile_radius", disk_size)
		_scale_shop_stat(stats, "crater_radius", disk_size)
	elif card.id == "light_bolt":
		_apply_light_bolt_ranks(stats, card)
	elif card.id == "icicle":
		_apply_icicle_ranks(stats, card)
	elif card.id == "teleport":
		_apply_teleport_ranks(stats, card)
	elif card.id == "fus":
		_apply_fus_ranks(stats, card)
	elif CrawlerRules.is_field_ability(card.id):
		_apply_field_ranks(stats, card)
	elif CrawlerRules.is_roar_ability(card.id):
		stats["damage"] = CrawlerRules.scaled_stat(
			CrawlerRules.roar_base_damage(card.id), upgrade_rank_for(card, "damage"))
		stats["range"] = CrawlerRules.scaled_stat(
			CrawlerRules.ROAR_RADIUS, upgrade_rank_for(card, "range"))
		stats["radius"] = float(stats["range"])
		stats["knockback"] = CrawlerRules.scaled_stat(
			CrawlerRules.roar_base_knockback(card.id),
			upgrade_rank_for(card, "knockback"))
		stats["cooldown"] = CrawlerRules.ROAR_COOLDOWN
		stats["animation_duration"] = CrawlerRules.ROAR_ANIMATION
		if card.id != "roar":
			stats["duration"] = CrawlerRules.scaled_stat(
				CrawlerRules.ROAR_DURATION, upgrade_rank_for(card, "duration"))
	for index in card.slot_count:
		var child := card.mod_at(index)
		if child == null:
			continue
		_apply_mod_upgrade(stats, child, card.id)
	if card.id == "starfire":
		var authored := CrawlerRules.STARFIRE_RADIUS
		if authored > 0.0:
			stats["size"] = float(stats.get("radius", authored)) / authored
	elif card.id == "light_bolt":
		var authored := CrawlerRules.LIGHT_BOLT_RADIUS
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif card.id == "icicle":
		var authored := CrawlerRules.scaled_stat(
			CrawlerRules.ICICLE_RADIUS, upgrade_rank_for(card, "cold"))
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif card.id == "teleport":
		var authored := CrawlerRules.TELEPORT_RADIUS
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif card.id == "meteor_punch":
		var authored := CrawlerRules.METEOR_RADIUS
		if authored > 0.0:
			stats["size"] = float(stats.get("radius", authored)) / authored
	elif CrawlerRules.is_field_ability(card.id):
		var authored := CrawlerRules.FIELD_RADIUS
		stats["radius"] = float(stats.get("radius",
			stats.get("range", authored)))
		stats["range"] = float(stats["radius"])
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif card.id == "lightning":
		var authored := CrawlerRules.LIGHTNING_RADIUS
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif CrawlerRules.is_pulsed_beam(card.id):
		var authored := CrawlerRules.KAME_RADIUS if card.id == "kame" else 0.45
		var listed: Variant = ItemDB.stats_of(card.id).get("radius", authored)
		if typeof(listed) == TYPE_FLOAT or typeof(listed) == TYPE_INT:
			authored = maxf(float(listed), 0.01)
		stats["size"] = float(stats.get("radius", authored)) / authored
	elif card.id == "wall":
		var authored := CrawlerRules.WALL_WIDTH
		stats["size"] = float(stats.get("wall_width", authored)) / maxf(authored, 0.01)
	elif card.id == "mini_nuke":
		var authored := CrawlerRules.MINI_NUKE_RADIUS
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif card.id == "nausicaa":
		var authored := CrawlerRules.NAUSICAA_RADIUS
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)
	elif card.id == "hero_punch":
		var authored := CrawlerRules.HERO_PUNCH_RADIUS
		stats["size"] = float(stats.get("radius", authored)) / maxf(authored, 0.01)


func _apply_light_bolt_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	var burst := CrawlerRules.scaled_stat(
		CrawlerRules.LIGHT_BOLT_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["damage"] = burst
	stats["impact"] = CrawlerRules.LIGHT_BOLT_IMPACT \
		* (burst / CrawlerRules.LIGHT_BOLT_DAMAGE)
	stats["player_damage"] = CrawlerRules.LIGHT_BOLT_PLAYER_DAMAGE \
		* (burst / CrawlerRules.LIGHT_BOLT_DAMAGE)
	stats["cooldown"] = maxf(
		CrawlerRules.LIGHT_BOLT_COOLDOWN_MIN,
		CrawlerRules.LIGHT_BOLT_COOLDOWN
			- CrawlerRules.LIGHT_BOLT_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHT_BOLT_RANGE, upgrade_rank_for(card, "range"))
	stats["speed"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHT_BOLT_SPEED, upgrade_rank_for(card, "speed"))
	var bolt_size := _rank_scale(card, "size")
	stats["size"] = bolt_size
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHT_BOLT_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	_scale_shop_stat(stats, "radius", bolt_size)
	_scale_shop_stat(stats, "projectile_radius", bolt_size)
	_scale_shop_stat(stats, "crater_radius", bolt_size)
	_scale_shop_stat(stats, "crater_depth", bolt_size)


func _apply_icicle_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["damage"] = CrawlerRules.scaled_stat(
		CrawlerRules.ICICLE_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["cooldown"] = maxf(
		CrawlerRules.ICICLE_COOLDOWN_MIN,
		CrawlerRules.ICICLE_COOLDOWN
			- CrawlerRules.ICICLE_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.ICICLE_RANGE, upgrade_rank_for(card, "range"))
	stats["speed"] = CrawlerRules.scaled_stat(
		CrawlerRules.ICICLE_SPEED, upgrade_rank_for(card, "speed"))
	var spear_size := _rank_scale(card, "size")
	stats["size"] = spear_size
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.ICICLE_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	var cold_rank := upgrade_rank_for(card, "cold")
	stats["cold"] = CrawlerRules.scaled_stat(CrawlerRules.ICICLE_COLD, cold_rank)
	stats["cold_damage"] = CrawlerRules.scaled_stat(
		CrawlerRules.ICICLE_COLD_DAMAGE, cold_rank)
	stats["radius"] = CrawlerRules.scaled_stat(CrawlerRules.ICICLE_RADIUS, cold_rank)
	stats["projectile_radius"] = CrawlerRules.ICICLE_PROJECTILE_RADIUS
	_scale_shop_stat(stats, "radius", spear_size)
	_scale_shop_stat(stats, "projectile_radius", spear_size)


func _apply_teleport_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["damage"] = 0.0
	stats["cooldown"] = maxf(
		CrawlerRules.TELEPORT_COOLDOWN_MIN,
		CrawlerRules.TELEPORT_COOLDOWN
			- CrawlerRules.TELEPORT_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.TELEPORT_RANGE, upgrade_rank_for(card, "range"))
	stats["speed"] = CrawlerRules.scaled_stat(
		CrawlerRules.TELEPORT_SPEED, upgrade_rank_for(card, "speed"))
	var marker_size := _rank_scale(card, "size")
	stats["size"] = marker_size
	stats["swap"] = 1.0 if upgrade_rank_for(card, "swap") > 0 else 0.0
	stats["gravity"] = CrawlerRules.TELEPORT_GRAVITY
	stats["loft"] = CrawlerRules.TELEPORT_LOFT
	stats["radius"] = CrawlerRules.TELEPORT_RADIUS
	stats["projectile_radius"] = CrawlerRules.TELEPORT_PROJECTILE_RADIUS
	_scale_shop_stat(stats, "radius", marker_size)
	_scale_shop_stat(stats, "projectile_radius", marker_size)


func _apply_fus_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["damage"] = CrawlerRules.scaled_stat(
		CrawlerRules.FUS_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["cooldown"] = maxf(
		CrawlerRules.FUS_COOLDOWN_MIN,
		CrawlerRules.FUS_COOLDOWN
			- CrawlerRules.FUS_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.FUS_RANGE, upgrade_rank_for(card, "range"))
	stats["speed"] = CrawlerRules.scaled_stat(
		CrawlerRules.FUS_SPEED, upgrade_rank_for(card, "speed"))
	var cone_size := _rank_scale(card, "size")
	stats["size"] = cone_size
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.FUS_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	stats["radius"] = CrawlerRules.FUS_RADIUS
	stats["projectile_radius"] = CrawlerRules.FUS_PROJECTILE_RADIUS


func _apply_hero_punch_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["damage"] = CrawlerRules.scaled_stat(
		CrawlerRules.HERO_PUNCH_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["cooldown"] = maxf(
		CrawlerRules.HERO_PUNCH_COOLDOWN_MIN,
		CrawlerRules.HERO_PUNCH_COOLDOWN
			- CrawlerRules.HERO_PUNCH_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.HERO_PUNCH_RANGE, upgrade_rank_for(card, "range"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.HERO_PUNCH_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	if not stats.has("radius"):
		stats["radius"] = CrawlerRules.HERO_PUNCH_RADIUS
	_scale_shop_stat(stats, "radius", size)


func _apply_overdrive_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["boost"] = CrawlerRules.scaled_stat(
		CrawlerRules.OVERDRIVE_BOOST, upgrade_rank_for(card, "boost"))
	stats["duration"] = CrawlerRules.scaled_stat(
		CrawlerRules.OVERDRIVE_DURATION, upgrade_rank_for(card, "duration"))
	stats["cooldown"] = maxf(
		CrawlerRules.OVERDRIVE_COOLDOWN_MIN,
		CrawlerRules.OVERDRIVE_COOLDOWN
			- CrawlerRules.OVERDRIVE_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["animation_duration"] = CrawlerRules.ROAR_ANIMATION
	if not stats.has("size"):
		stats["size"] = 1.0
	if not stats.has("range"):
		stats["range"] = CrawlerRules.ROAR_RADIUS
	if not stats.has("radius"):
		stats["radius"] = CrawlerRules.ROAR_RADIUS


func _apply_active_overdrive(stats: Dictionary, card: CrawlerCard) -> void:
	if card == null or card.id == "overdrive":
		return
	if player == null or not player.has_method(&"overdrive_active") \
			or not bool(player.call(&"overdrive_active")):
		return
	var seated := card.filled_modifier_ids()
	var borrowed: Array = []
	if player.has_method(&"overdrive_borrowed_mods"):
		var held: Variant = player.call(&"overdrive_borrowed_mods")
		if held is Array:
			borrowed = held
	var extra_ids := PackedStringArray()
	var extra_cards: Array[CrawlerCard] = []
	for item: Variant in borrowed:
		var mod := item as CrawlerCard
		if mod == null or mod.id.is_empty():
			continue
		if not CrawlerCatalog.compatible(mod.id, card.id):
			continue
		if seated.has(mod.id):
			continue
		extra_ids.append(mod.id)
		extra_cards.append(mod)
	if not extra_ids.is_empty():
		var merged := CrawlerCatalog.resolve_stats(card.id, extra_ids, stats)
		stats.clear()
		for key: Variant in merged:
			stats[key] = merged[key]
		for mod: CrawlerCard in extra_cards:
			_apply_mod_upgrade(stats, mod, card.id)
	var mul := 1.0
	if player.has_method(&"overdrive_boost_mul"):
		mul = float(player.call(&"overdrive_boost_mul"))
	if mul > 1.0001:
		for key: String in CrawlerRules.OVERDRIVE_BOOST_STATS:
			_scale_shop_stat(stats, key, mul)


func _apply_nausicaa_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	var burst := CrawlerRules.scaled_stat(
		CrawlerRules.NAUSICAA_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["damage"] = burst
	stats["player_damage"] = CrawlerRules.NAUSICAA_PLAYER_DAMAGE \
		* (burst / CrawlerRules.NAUSICAA_DAMAGE)
	stats["cooldown"] = maxf(
		CrawlerRules.NAUSICAA_COOLDOWN_MIN,
		CrawlerRules.NAUSICAA_COOLDOWN
			- CrawlerRules.NAUSICAA_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["duration"] = CrawlerRules.scaled_stat(
		CrawlerRules.NAUSICAA_DURATION, upgrade_rank_for(card, "duration"))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.NAUSICAA_RANGE, upgrade_rank_for(card, "range"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.NAUSICAA_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	stats["delay"] = CrawlerRules.NAUSICAA_DELAY
	stats["paint_spacing"] = float(stats.get(
		"paint_spacing", CrawlerRules.NAUSICAA_PAINT_SPACING))
	stats["chain_interval"] = float(stats.get(
		"chain_interval", CrawlerRules.NAUSICAA_CHAIN_INTERVAL))
	stats["lift"] = CrawlerRules.NAUSICAA_LIFT
	stats["explosion_duration"] = CrawlerRules.NAUSICAA_EXPLOSION
	if not stats.has("beam_width"):
		stats["beam_width"] = CrawlerRules.NAUSICAA_BEAM_WIDTH
	if not stats.has("paint_radius"):
		stats["paint_radius"] = CrawlerRules.NAUSICAA_PAINT_RADIUS
	if not stats.has("radius"):
		stats["radius"] = CrawlerRules.NAUSICAA_RADIUS
	_scale_shop_stat(stats, "radius", size)
	_scale_shop_stat(stats, "beam_width", size)
	_scale_shop_stat(stats, "paint_radius", size)
	_scale_shop_stat(stats, "crater_radius", size)
	_scale_shop_stat(stats, "crater_depth", size)


func _apply_mini_nuke_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	var burst := CrawlerRules.scaled_stat(
		CrawlerRules.MINI_NUKE_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["damage"] = burst
	stats["impact"] = CrawlerRules.MINI_NUKE_IMPACT \
		* (burst / CrawlerRules.MINI_NUKE_DAMAGE)
	stats["player_damage"] = CrawlerRules.MINI_NUKE_PLAYER_DAMAGE \
		* (burst / CrawlerRules.MINI_NUKE_DAMAGE)
	stats["cooldown"] = maxf(
		CrawlerRules.MINI_NUKE_COOLDOWN_MIN,
		CrawlerRules.MINI_NUKE_COOLDOWN
			- CrawlerRules.MINI_NUKE_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.MINI_NUKE_RANGE, upgrade_rank_for(card, "range"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["speed"] = CrawlerRules.MINI_NUKE_SPEED
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.MINI_NUKE_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	stats["lift"] = CrawlerRules.MINI_NUKE_LIFT
	stats["self_launch_speed"] = CrawlerRules.MINI_NUKE_SELF_LAUNCH
	stats["explosion_duration"] = CrawlerRules.MINI_NUKE_EXPLOSION
	stats["crater_warp"] = CrawlerRules.MINI_NUKE_CRATER_WARP
	_scale_shop_stat(stats, "radius", size)
	_scale_shop_stat(stats, "projectile_radius", size)
	_scale_shop_stat(stats, "crater_radius", size)
	_scale_shop_stat(stats, "crater_depth", size)


func _apply_wall_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["cooldown"] = maxf(
		CrawlerRules.WALL_COOLDOWN_MIN,
		CrawlerRules.WALL_COOLDOWN
			- CrawlerRules.WALL_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.WALL_RANGE, upgrade_rank_for(card, "range"))
	stats["duration"] = CrawlerRules.scaled_stat(
		CrawlerRules.WALL_DURATION, upgrade_rank_for(card, "duration"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["fade_duration"] = CrawlerRules.WALL_FADE
	stats["project"] = CrawlerRules.wall_project_speed(
		upgrade_rank_for(card, "project"))
	stats["firewall"] = CrawlerRules.wall_firewall_damage(
		upgrade_rank_for(card, "firewall"))
	stats["house"] = 1.0 if upgrade_rank_for(card, "house") > 0 else 0.0
	_scale_shop_stat(stats, "wall_width", size)
	_scale_shop_stat(stats, "wall_height", size)
	_scale_shop_stat(stats, "wall_thickness", size)


func _apply_field_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["damage"] = CrawlerRules.scaled_stat(
		CrawlerRules.field_base_damage(card.id), upgrade_rank_for(card, "damage"))
	stats["cooldown"] = maxf(
		CrawlerRules.FIELD_COOLDOWN_MIN,
		CrawlerRules.FIELD_COOLDOWN
			- CrawlerRules.FIELD_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["duration"] = CrawlerRules.scaled_stat(
		CrawlerRules.FIELD_DURATION, upgrade_rank_for(card, "duration"))
	var radius := CrawlerRules.scaled_stat(
		CrawlerRules.FIELD_RADIUS, upgrade_rank_for(card, "range"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["range"] = radius
	stats["radius"] = radius
	stats["fade_duration"] = CrawlerRules.FIELD_FADE
	stats["cast"] = maxf(
		CrawlerRules.FIELD_CAST_MIN,
		CrawlerRules.FIELD_CAST
			- CrawlerRules.FIELD_CAST_PER_RANK
			* float(upgrade_rank_for(card, "cast")))
	stats["animation_duration"] = CrawlerRules.FIELD_ANIMATION
	stats["shock"] = 0.0
	stats["toxic"] = 0.0
	stats["freeze"] = 0.0
	stats["heal"] = 0.0
	if card.id == "static_field":
		stats["shock"] = CrawlerRules.scaled_stat(
			CrawlerRules.FIELD_SHOCK, upgrade_rank_for(card, "shock"))
	elif card.id == "toxic_field":
		stats["toxic"] = CrawlerRules.scaled_stat(
			CrawlerRules.FIELD_TOXIC, upgrade_rank_for(card, "toxic"))
	elif card.id == "freeze_field":
		stats["freeze"] = minf(
			CrawlerRules.FIELD_FREEZE_MAX,
			CrawlerRules.scaled_stat(
				CrawlerRules.FIELD_FREEZE, upgrade_rank_for(card, "freeze")))
	elif card.id == "healing_field":
		stats["heal"] = CrawlerRules.scaled_stat(
			CrawlerRules.FIELD_HEAL, upgrade_rank_for(card, "heal"))
	_scale_shop_stat(stats, "radius", size)
	_scale_shop_stat(stats, "range", size)


func _apply_lightning_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	stats["damage"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHTNING_DAMAGE, upgrade_rank_for(card, "damage"))
	stats["cooldown"] = maxf(
		CrawlerRules.LIGHTNING_COOLDOWN_MIN,
		CrawlerRules.LIGHTNING_COOLDOWN
			- CrawlerRules.LIGHTNING_COOLDOWN_PER_RANK
			* float(upgrade_rank_for(card, "cooldown")))
	stats["duration"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHTNING_DURATION, upgrade_rank_for(card, "duration"))
	stats["range"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHTNING_RANGE, upgrade_rank_for(card, "range"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["knockback"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHTNING_KNOCKBACK, upgrade_rank_for(card, "knockback"))
	stats["arcs"] = float(CrawlerRules.LIGHTNING_ARCS \
		+ CrawlerRules.LIGHTNING_ARCS_PER_RANK \
		* upgrade_rank_for(card, "arcs"))
	stats["shock"] = CrawlerRules.scaled_stat(
		CrawlerRules.LIGHTNING_SHOCK, upgrade_rank_for(card, "shock"))
	stats["hop_range"] = CrawlerRules.LIGHTNING_ARC_RANGE
	stats["damage_unit"] = ""
	if not stats.has("radius"):
		stats["radius"] = CrawlerRules.LIGHTNING_RADIUS
	if not stats.has("beam_width"):
		stats["beam_width"] = CrawlerRules.LIGHTNING_BEAM_WIDTH
	_scale_shop_stat(stats, "radius", size)
	_scale_shop_stat(stats, "beam_width", size)
	_scale_shop_stat(stats, "impact_radius", size)


func _apply_pulsed_beam_ranks(stats: Dictionary, card: CrawlerCard) -> void:
	var kame := card.id == "kame"
	var damage := CrawlerRules.KAME_DAMAGE if kame else CrawlerRules.LASER_DAMAGE
	var cooldown := CrawlerRules.KAME_COOLDOWN if kame else CrawlerRules.LASER_COOLDOWN
	var duration := CrawlerRules.KAME_DURATION if kame else CrawlerRules.LASER_DURATION
	var reach := CrawlerRules.KAME_RANGE if kame else CrawlerRules.LASER_RANGE
	var knockback := CrawlerRules.KAME_KNOCKBACK if kame else CrawlerRules.LASER_KNOCKBACK
	var cooldown_per := CrawlerRules.KAME_COOLDOWN_PER_RANK if kame else 0.05
	var cooldown_min := CrawlerRules.KAME_COOLDOWN_MIN if kame else 0.18
	stats["damage"] = CrawlerRules.scaled_stat(damage, upgrade_rank_for(card, "damage"))
	stats["cooldown"] = maxf(
		cooldown_min,
		cooldown - cooldown_per * float(upgrade_rank_for(card, "cooldown")))
	stats["duration"] = CrawlerRules.scaled_stat(
		duration, upgrade_rank_for(card, "duration"))
	stats["range"] = CrawlerRules.scaled_stat(reach, upgrade_rank_for(card, "range"))
	var size := _rank_scale(card, "size")
	stats["size"] = size
	stats["knockback"] = CrawlerRules.scaled_stat(
		knockback, upgrade_rank_for(card, "knockback"))
	stats["damage_unit"] = "/s" if kame else ""
	if kame:
		stats["damage_hz"] = CrawlerRules.KAME_DAMAGE_HZ
	_scale_shop_stat(stats, "radius", size)
	_scale_shop_stat(stats, "beam_width", size)
	_scale_shop_stat(stats, "impact_radius", size)


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
		var rank := maxi(mod.upgrade_rank("size"), 0)
		var wanted := CrawlerRules.big_size_scale(rank)
		var already := CrawlerCatalog.size_mul_for("big", host_id)
		var extra := wanted / already if already > 0.0001 else wanted
		_scale_shop_stat(stats, "size", extra)
		_scale_shop_stat(stats, "radius", extra)
		_scale_shop_stat(stats, "beam_width", extra)
		_scale_shop_stat(stats, "paint_radius", extra)
		_scale_shop_stat(stats, "impact_radius", extra)
		_scale_shop_stat(stats, "projectile_radius", extra)
		_scale_shop_stat(stats, "crater_radius", extra)
		_scale_shop_stat(stats, "wall_width", extra)
		_scale_shop_stat(stats, "wall_height", extra)
		_scale_shop_stat(stats, "wall_thickness", extra)
		return
	if mod.id == "ice" and CrawlerRules.is_field_ability(host_id):
		var rank := maxi(mod.upgrade_rank("freeze"), 0)
		var extra := CrawlerRules.scaled_stat(CrawlerRules.ELEM_ICE_FIELD, rank)
		stats["freeze"] = minf(
			float(stats.get("freeze", 0.0)) + extra, CrawlerRules.FIELD_FREEZE_MAX)
		return
	if mod.id == "multi":
		var rank := maxi(mod.upgrade_rank("multi"), 0)
		var wanted := CrawlerRules.multi_shots(rank)
		stats["multi"] = float(maxi(int(round(float(stats.get("multi", 0.0)))), wanted))
	if mod.id == "reach":
		if host_id == "overdrive":
			return
		if not host_id.is_empty() and not CrawlerCatalog.compatible("reach", host_id):
			return
		var range_rank := maxi(mod.upgrade_rank("range"), 0)
		var wanted_mul := CrawlerRules.reach_range_mul(range_rank)
		var already := float(stats.get("_reach_mul", 1.0))
		if wanted_mul > already + 0.0001:
			var extra := wanted_mul / already if already > 0.0001 else wanted_mul
			_scale_shop_stat(stats, "range", extra)
			_scale_shop_stat(stats, "hop_range", extra)
			stats["_reach_mul"] = wanted_mul
		var cast_rank := maxi(mod.upgrade_rank("far_cast"), 0)
		stats["far_cast"] = maxf(
			float(stats.get("far_cast", 0.0)),
			CrawlerRules.far_cast_meters(cast_rank))
	if mod.id == "bounce":
		if host_id == "overdrive":
			return
		if not host_id.is_empty() and not CrawlerCatalog.compatible("bounce", host_id):
			return
		var bounce_rank := maxi(mod.upgrade_rank("bounce"), 0)
		var bounce_wanted := CrawlerRules.bounce_count(bounce_rank)
		stats["bounce"] = float(maxi(
			int(round(float(stats.get("bounce", 0.0)))), bounce_wanted))
	if mod.id == "impact_cast":
		if host_id == "overdrive":
			return
		if not host_id.is_empty() and not CrawlerCatalog.compatible("impact_cast", host_id):
			return
		stats["impact_cast"] = 1.0
	if mod.id == "homing":
		if host_id == "overdrive":
			return
		if not host_id.is_empty() and not CrawlerCatalog.compatible("homing", host_id):
			return
		var pull_rank := maxi(mod.upgrade_rank("homing"), 0)
		var seek_rank := maxi(mod.upgrade_rank("range"), 0)
		stats["homing"] = maxf(
			float(stats.get("homing", 0.0)), CrawlerRules.homing_steer(pull_rank))
		stats["homing_range"] = maxf(
			float(stats.get("homing_range", 0.0)),
			CrawlerRules.homing_range(seek_rank))


func _rank_scale(card: CrawlerCard, stat_id: String) -> float:
	return CrawlerRules.upgrade_scale(upgrade_rank_for(card, stat_id))


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


func can_edit_mods() -> bool:
	if standalone:
		return true
	if player == null or not is_instance_valid(player):
		return true
	if player.has_method(&"can_edit_crawler_mods"):
		return bool(player.call(&"can_edit_crawler_mods"))
	return true


func extract(source: String, index: int, expected_token := "") -> Dictionary:
	if source == SOURCE_MOD and not can_edit_mods():
		return {}
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
	_rebuild_city_mod_racks()
	_emit_changed()
	return payload


func owned_cards() -> Array[CrawlerCard]:
	var out: Array[CrawlerCard] = []
	var seen: Dictionary = {}
	_collect_owned(out, seen, ability_bar(), true)
	_collect_owned(out, seen, city_equip, true)
	_collect_owned(out, seen, inventory, false)
	_collect_owned(out, seen, city_inventory, false)
	return out


func shop_grant(catalog_id: String, swap_equipped_index := 0) -> bool:
	return bool(shop_grant_result(catalog_id, swap_equipped_index).get("ok", false))


func shop_grant_result(catalog_id: String, swap_equipped_index := 0) -> Dictionary:
	var card: CrawlerCard
	if CrawlerCatalog.is_ability(catalog_id):
		if not CrawlerRules.ability_enabled(catalog_id) \
				or CrawlerProgress.ability_price(catalog_id) <= 0:
			return {"ok": false}
		card = CrawlerCatalog.make_ability(catalog_id)
		if card == null:
			return {"ok": false}
		register(card)
		_apply_shared_ability_ranks(card)
		sync_ammo(card)
		return _grant_ability(card, swap_equipped_index)
	if CrawlerCatalog.is_modifier(catalog_id):
		card = CrawlerCatalog.make_modifier(catalog_id)
	else:
		return {"ok": false}
	if card == null:
		return {"ok": false}
	return grant(card.to_dict())


func _shops_unlimited() -> bool:
	return player != null and player.crawler_progress != null \
		and player.crawler_progress.shops_are_unlimited()


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
	if CrawlerRules.upgrade_at_cap(
			card.id, wanted, card.upgrade_rank(wanted), _shops_unlimited()):
		return false
	card.add_upgrade_rank(wanted)
	if card.id == "clip":
		var host := host_ability_for(card.token())
		if host != null:
			sync_ammo(host)
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()
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
		sync_ammo(card)
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
	var bar := ability_bar()
	if bar == null:
		return false
	var token := bar.get_item(index)
	if token.is_empty():
		return false
	var dest := inventory.first_accepting(token)
	if dest < 0:
		return false
	return ItemContainer.transfer(bar, index, inventory, dest)


func remember() -> void:
	if standalone:
		return
	session_payload = to_dict()


func to_dict() -> Dictionary:
	return {
		"revision": STARTER_REVISION,
		"equipped": _bar_payload(ability_bar()),
		"inventory": _bar_payload(inventory),
		"city_equipped": _bar_payload(city_equip),
		"city_inventory": _bar_payload(city_inventory),
		"ability_ranks": ability_ranks.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_syncing = true
	_clear_containers()
	cards.clear()
	ability_ranks.clear()
	_configure_city_bank()
	_fill_bar(ability_bar(), data.get("equipped", []))
	_fill_bar(inventory, data.get("inventory", []))
	_fill_bar(city_equip, data.get("city_equipped", []))
	_fill_bar(city_inventory, data.get("city_inventory", []))
	var ranks_raw: Variant = data.get("ability_ranks", {})
	if ranks_raw is Dictionary and not (ranks_raw as Dictionary).is_empty():
		ability_ranks = (ranks_raw as Dictionary).duplicate(true)
	else:
		_fold_ability_ranks_from_cards()
	_sync_all_ability_copies()
	_sync_all_ammo()
	_syncing = false
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()
	_emit_changed()


func _upgrade_shared_ability(card: CrawlerCard, wanted: String) -> bool:
	var entry := _ability_rank_entry(card.id)
	var table: Dictionary = {}
	var held: Variant = entry.get("upgrades", {})
	if held is Dictionary:
		table = (held as Dictionary).duplicate()
	if CrawlerRules.upgrade_at_cap(
			card.id, wanted, int(table.get(wanted, 0)), _shops_unlimited()):
		return false
	if wanted == "slots":
		var slots := maxi(int(entry.get("slots", 0)), card.slot_count)
		if slots >= CrawlerRules.MAX_MOD_SLOTS:
			return false
		entry["slots"] = slots + 1
	table[wanted] = int(table.get(wanted, 0)) + 1
	entry["upgrades"] = table
	entry["shop_rank"] = int(entry.get("shop_rank", 0)) + 1
	ability_ranks[card.id] = entry
	_sync_ability_copies(card.id)
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()
	_emit_changed()
	return true


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
	var bar := ability_bar()
	if bar == null:
		_unregister_tree(card)
		return {"ok": false}
	var equip := bar.first_accepting(token)
	if equip >= 0:
		bar.set_item(equip, token)
		_rebuild_mod_racks()
		_emit_changed()
		return {"ok": true}
	var slot := clampi(swap_equipped_index, 0, bar.size() - 1)
	var old_token := bar.get_item(slot)
	var old := card_for_token(old_token)
	var displaced := old.to_dict() if old != null else {}
	if old != null:
		_unregister_tree(old)
	bar.set_item(slot, token)
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
	if can_edit_mods() and ability_bar() != null:
		for index in ability_bar().size():
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
	_mod_racks = _make_mod_racks(ability_bar(), _on_mod_rack_changed)


func _on_mod_rack_changed(index: int) -> void:
	if _syncing:
		return
	var card := equipped_card(index)
	var rack := mod_rack(index)
	if card == null or rack == null:
		return
	for mod_index in rack.size():
		card.place_mod(mod_index, card_for_token(rack.get_item(mod_index)))
	sync_ammo(card)
	_emit_changed()


func _on_equipped_changed() -> void:
	if _syncing:
		return
	_configure_city_bank()
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()
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
	var bar := ability_bar()
	if bar != null:
		bar.clear()
	inventory.clear()
	if city_equip != null:
		city_equip.clear()
	if city_inventory != null:
		city_inventory.clear()


func _unregister_tree(card: CrawlerCard) -> void:
	if card == null:
		return
	for node: CrawlerCard in card.collect_tree():
		cards.erase(node.uid)


func _locate(source: String, index: int) -> Dictionary:
	match source:
		SOURCE_EQUIP:
			return _locate_bar(ability_bar(), index)
		SOURCE_BAG:
			return _locate_bar(inventory, index)
		SOURCE_CITY_EQUIP:
			return _locate_bar(city_equip, index)
		SOURCE_CITY_BAG:
			return _locate_bar(city_inventory, index)
		SOURCE_MOD:
			return _locate_mod(_mod_racks, index)
		SOURCE_CITY_MOD:
			return _locate_mod(_city_mod_racks, index)
	return {}


func _clear_located(source: String, index: int) -> void:
	var found := _locate(source, index)
	var container := found.get("container") as ItemContainer
	if container == null:
		return
	_syncing = true
	container.set_item(int(found.get("index", -1)), "")
	if source == SOURCE_MOD or source == SOURCE_CITY_MOD:
		var host := equipped_card(index / MOD_STRIDE) if source == SOURCE_MOD \
			else city_equipped_card(index / MOD_STRIDE)
		if host != null:
			host.place_mod(index % MOD_STRIDE, null)
	_syncing = false


func encode_mod_index(equip_index: int, mod_index: int) -> int:
	return equip_index * MOD_STRIDE + mod_index


func place_card(card: CrawlerCard, source: String, index: int) -> bool:
	if card == null:
		return false
	register(card)
	if card.is_ability():
		_absorb_card_ranks(card)
		_apply_shared_ability_ranks(card)
		_sync_ability_copies(card.id)
		sync_ammo(card)
	var found := _locate(source, index)
	var container := found.get("container") as ItemContainer
	if container == null:
		_unregister_tree(card)
		return false
	var dest := int(found.get("index", -1))
	_syncing = true
	container.set_item(dest, card.token())
	var seated := container.get_item(dest) == card.token()
	_syncing = false
	if not seated:
		_unregister_tree(card)
		return false
	_rebuild_mod_racks()
	_rebuild_city_mod_racks()
	_emit_changed()
	return true


static func hand_off(
		from_kit: CrawlerKit,
		from_source: String,
		from_index: int,
		to_kit: CrawlerKit,
		to_source: String,
		to_index: int
	) -> bool:
	if from_kit == null or to_kit == null:
		return false
	if from_kit == to_kit:
		return from_kit.move_card(from_source, from_index, to_source, to_index)
	var moving := from_kit.extract(from_source, from_index)
	if moving.is_empty():
		return false
	var displaced: Dictionary = {}
	if not to_kit.token_at(to_source, to_index).is_empty():
		displaced = to_kit.extract(to_source, to_index)
	var card := CrawlerCard.from_dict(moving)
	if card == null or not to_kit.place_card(card, to_source, to_index):
		from_kit.place_card(CrawlerCard.from_dict(moving), from_source, from_index)
		if not displaced.is_empty():
			to_kit.place_card(CrawlerCard.from_dict(displaced), to_source, to_index)
		return false
	if not displaced.is_empty():
		from_kit.place_card(CrawlerCard.from_dict(displaced), from_source, from_index)
	return true


func _host_in_bar(bar: ItemContainer, token: String) -> CrawlerCard:
	if bar == null or token.is_empty():
		return null
	for index in bar.size():
		var hosted := card_for_token(bar.get_item(index))
		if hosted == null:
			continue
		for child: CrawlerCard in hosted.collect_tree():
			if child != null and child != hosted and child.token() == token:
				return hosted
	return null


func _collect_owned(
		out: Array[CrawlerCard],
		seen: Dictionary,
		bar: ItemContainer,
		with_tree: bool
	) -> void:
	if bar == null:
		return
	for index in bar.size():
		var card := card_for_token(bar.get_item(index))
		if card == null or seen.has(card.uid):
			continue
		seen[card.uid] = true
		out.append(card)
		if not with_tree:
			continue
		for child: CrawlerCard in card.collect_tree():
			if child == null or child == card or seen.has(child.uid):
				continue
			seen[child.uid] = true
			out.append(child)


func _bar_payload(bar: ItemContainer) -> Array:
	var out: Array = []
	if bar == null:
		return out
	for index in bar.size():
		var card := card_for_token(bar.get_item(index))
		out.append(card.to_dict() if card != null else {})
	return out


func _fill_bar(bar: ItemContainer, raw: Variant) -> void:
	if bar == null or not (raw is Array):
		return
	var rows := raw as Array
	for index in mini(bar.size(), rows.size()):
		var held: Variant = rows[index]
		if not (held is Dictionary):
			continue
		var card := CrawlerCard.from_dict(held as Dictionary)
		if card == null:
			continue
		register(card)
		bar.set_item(index, card.token())


func _locate_bar(bar: ItemContainer, index: int) -> Dictionary:
	if bar == null or index < 0 or index >= bar.size():
		return {}
	return {
		"token": bar.get_item(index),
		"container": bar,
		"index": index,
	}


func _locate_mod(racks: Array[ItemContainer], index: int) -> Dictionary:
	var equip_index := index / MOD_STRIDE
	var mod_index := index % MOD_STRIDE
	if equip_index < 0 or equip_index >= racks.size():
		return {}
	var rack := racks[equip_index]
	if rack == null or mod_index < 0 or mod_index >= rack.size():
		return {}
	return {
		"token": rack.get_item(mod_index),
		"container": rack,
		"index": mod_index,
	}


func _apply_ability_filters(bar: ItemContainer) -> void:
	if bar == null:
		return
	for index in bar.size():
		bar.set_filter(index, ItemDB.ABILITY)


func _configure_city_bank() -> void:
	var slots := CrawlerRules.ABILITY_SLOTS
	var bar := ability_bar()
	if bar != null:
		slots = bar.size()
	if city_equip == null or city_equip.size() != slots:
		var previous := city_equip
		if previous != null and previous.changed.is_connected(_on_city_equip_changed):
			previous.changed.disconnect(_on_city_equip_changed)
		city_equip = ItemContainer.new(slots)
		if previous != null:
			for index in mini(previous.size(), city_equip.size()):
				city_equip.set_item(index, previous.get_item(index))
	_apply_ability_filters(city_equip)
	if not city_equip.changed.is_connected(_on_city_equip_changed):
		city_equip.changed.connect(_on_city_equip_changed)
	if city_inventory == null \
			or city_inventory.size() != CrawlerRules.INVENTORY_SLOTS:
		var previous_bag := city_inventory
		if previous_bag != null \
				and previous_bag.changed.is_connected(_on_inventory_changed):
			previous_bag.changed.disconnect(_on_inventory_changed)
		city_inventory = ItemContainer.new(CrawlerRules.INVENTORY_SLOTS)
		if previous_bag != null:
			for index in mini(previous_bag.size(), city_inventory.size()):
				city_inventory.set_item(index, previous_bag.get_item(index))
	for index in city_inventory.size():
		city_inventory.set_filter(index, CrawlerCatalog.FILTER_KIT)
	if not city_inventory.changed.is_connected(_on_inventory_changed):
		city_inventory.changed.connect(_on_inventory_changed)


func _rebuild_city_mod_racks() -> void:
	if standalone:
		_city_mod_racks = []
		return
	_city_mod_racks = _make_mod_racks(city_equip, _on_city_mod_rack_changed)


func _make_mod_racks(bar: ItemContainer, callback: Callable) -> Array[ItemContainer]:
	var racks: Array[ItemContainer] = []
	if bar == null:
		return racks
	for index in bar.size():
		var card := card_for_token(bar.get_item(index))
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
		rack.changed.connect(callback.bind(index))
		racks.append(rack)
	return racks


func _on_city_equip_changed() -> void:
	if _syncing:
		return
	_rebuild_city_mod_racks()
	_emit_changed()


func _on_city_mod_rack_changed(index: int) -> void:
	if _syncing:
		return
	var card := city_equipped_card(index)
	var rack := city_mod_rack(index)
	if card == null or rack == null:
		return
	for mod_index in rack.size():
		card.place_mod(mod_index, card_for_token(rack.get_item(mod_index)))
	sync_ammo(card)
	_emit_changed()


func _absorb_card_ranks(card: CrawlerCard) -> void:
	if card == null or not card.is_ability() or card.id.is_empty():
		return
	var entry := _ability_rank_entry(card.id)
	var upgrades: Dictionary = {}
	var existing: Variant = entry.get("upgrades", {})
	if existing is Dictionary:
		upgrades = (existing as Dictionary).duplicate()
	var table: Variant = card.extra_stats.get("upgrades", {})
	if table is Dictionary:
		for key: Variant in table:
			var name := str(key)
			upgrades[name] = maxi(int(upgrades.get(name, 0)), int(table[key]))
	entry["upgrades"] = upgrades
	entry["shop_rank"] = maxi(int(entry.get("shop_rank", 0)), card.shop_rank())
	entry["slots"] = maxi(int(entry.get("slots", 0)), card.slot_count)
	ability_ranks[card.id] = entry
