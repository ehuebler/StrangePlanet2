class_name CrawlerElements
extends RefCounted

## Seated elemental mods plus a host's native status, stacked and scaled.

const MODS: PackedStringArray = ["toxic", "shock", "charm", "ice"]


static func payload(player: OnlinePlayer, ability_id: String,
		stats: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if ability_id == "wall" and float(stats.get("firewall", 0.0)) <= 0.001:
		return out
	var element := 1.0
	if player != null and player.has_method(&"crawler_element_scale"):
		element = maxf(float(player.call(&"crawler_element_scale")), 0.0)
	_merge(out, _native_of(ability_id, stats))
	for mod_id: String in MODS:
		for card: CrawlerCard in seated_cards(player, ability_id, mod_id):
			_merge(out, _card_of(card))
	for entry: Dictionary in out:
		entry["duration"] = float(entry.get("duration", 0.0)) * element
		entry["strength"] = float(entry.get("strength", 0.0)) * element
	return out


static func stamp(hit: DamageHit, player: OnlinePlayer, ability_id: String,
		stats: Dictionary, stack_poison := false, poison_mul := 1.0) -> DamageHit:
	return apply_to_hit(
		hit, payload(player, ability_id, stats), stack_poison, poison_mul)


static func apply_to_hit(hit: DamageHit, entries: Array,
		stack_poison := false, poison_mul := 1.0) -> DamageHit:
	if hit == null:
		return null
	var stamped: Array[Dictionary] = []
	var share := poison_mul if is_finite(poison_mul) else 1.0
	for entry: Dictionary in entries:
		var id := StringName(str(entry.get("id", "")))
		var hold := maxf(float(entry.get("duration", 0.0)), 0.0)
		if id.is_empty() or hold <= 0.0:
			continue
		var strength := maxf(float(entry.get("strength", 0.0)), 0.0)
		if id == CombatStatuses.POISON and share != 1.0:
			strength *= share
		var row := {
			"id": String(id),
			"duration": hold,
			"strength": strength,
			"stack": bool(entry.get("stack", false)) or (
				stack_poison and id == CombatStatuses.POISON),
		}
		stamped.append(row)
	if stamped.is_empty():
		hit.status = &""
		hit.status_duration = 0.0
		hit.status_strength = 0.0
		hit.status_stack = false
		hit.extra_statuses.clear()
		return hit
	var first: Dictionary = stamped[0]
	hit.with_status(StringName(str(first.get("id", ""))),
		float(first.get("duration", 0.0)), float(first.get("strength", 0.0)))
	hit.status_stack = bool(first.get("stack", false))
	hit.extra_statuses = stamped.slice(1) if stamped.size() > 1 else []
	return hit


static func apply_to_combatant(combatant: Node, hit: DamageHit) -> bool:
	if combatant == null or hit == null:
		return false
	var held: Variant = combatant.get("statuses")
	if not held is CombatStatuses:
		return false
	var statuses := held as CombatStatuses
	var applied := false
	for entry: Dictionary in hit.status_entries():
		var id := StringName(str(entry.get("id", "")))
		var hold := maxf(float(entry.get("duration", 0.0)), 0.0)
		if id.is_empty() or hold <= 0.0 or not CombatStatuses.is_known(id):
			continue
		if id == CombatStatuses.SHOCK \
				and combatant.has_method(&"shock_immune") \
				and bool(combatant.call(&"shock_immune")):
			continue
		var strength := maxf(float(entry.get("strength", 0.0)), 0.0)
		if bool(entry.get("stack", false)):
			strength = statuses.strength(id) + strength
		if statuses.apply_status(id, hold, strength):
			applied = true
	return applied


static func seated_cards(player: OnlinePlayer, ability_id: String,
		mod_id: String) -> Array[CrawlerCard]:
	var out: Array[CrawlerCard] = []
	if player == null or mod_id.is_empty():
		return out
	var seen := {}
	var card := _host_card(player, ability_id)
	if card != null:
		for index in card.slot_count:
			var child := card.mod_at(index)
			if child == null or child.id != mod_id:
				continue
			out.append(child)
			seen[child.uid] = true
	if ability_id == "overdrive":
		return out
	if not player.has_method(&"overdrive_active") \
			or not bool(player.call(&"overdrive_active")):
		return out
	if not CrawlerCatalog.compatible(mod_id, ability_id):
		return out
	if not player.has_method(&"overdrive_borrowed_mods"):
		return out
	var held: Variant = player.call(&"overdrive_borrowed_mods")
	if not held is Array:
		return out
	for item: Variant in held:
		var child := item as CrawlerCard
		if child == null or child.id != mod_id:
			continue
		if seen.has(child.uid):
			continue
		out.append(child)
		seen[child.uid] = true
	return out


static func _native_of(ability_id: String, stats: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match ability_id:
		"toxic_blast":
			_append(out, CombatStatuses.POISON,
				maxf(float(stats.get("duration", CrawlerRules.ROAR_DURATION)), 0.0),
				maxf(float(stats.get("damage", CrawlerRules.ROAR_TOXIC_DAMAGE)), 0.0),
				false)
		"charming_aura":
			_append(out, CombatStatuses.CHARM,
				maxf(float(stats.get("duration", CrawlerRules.ROAR_DURATION)), 0.0),
				0.0, false)
		"freeze_blast":
			_append(out, CombatStatuses.FREEZE,
				maxf(float(stats.get("duration", CrawlerRules.ROAR_DURATION)), 0.0),
				maxf(float(stats.get("damage", 0.0)), 0.0), false)
		"icicle":
			_append(out, CombatStatuses.FREEZE,
				maxf(float(stats.get("cold", CrawlerRules.ICICLE_COLD)), 0.0),
				maxf(float(stats.get("cold_damage",
					CrawlerRules.ICICLE_COLD_DAMAGE)), 0.0), false)
		"lightning", "static_field":
			_append(out, CombatStatuses.SHOCK,
				maxf(float(stats.get("shock", 0.0)), 0.0), 0.0, false)
		"toxic_field":
			_append(out, CombatStatuses.POISON,
				maxf(float(stats.get("toxic", CrawlerRules.FIELD_TOXIC)), 0.0),
				maxf(float(stats.get("damage", CrawlerRules.FIELD_TOXIC_DAMAGE)), 0.0),
				true)
	return out


static func _card_of(card: CrawlerCard) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if card == null:
		return out
	match card.id:
		"toxic":
			var rank := maxi(card.upgrade_rank("toxic"), 0)
			var hold_rank := maxi(card.upgrade_rank("duration"), 0)
			_append(out, CombatStatuses.POISON,
				CrawlerRules.ELEM_TOXIC_HOLD
					+ CrawlerRules.ELEM_TOXIC_HOLD_PER_RANK * float(hold_rank),
				CrawlerRules.ELEM_TOXIC_DPS
					+ CrawlerRules.ELEM_TOXIC_DPS_PER_RANK * float(rank),
				false)
		"shock":
			var rank := maxi(card.upgrade_rank("shock"), 0)
			_append(out, CombatStatuses.SHOCK,
				CrawlerRules.ELEM_SHOCK_HOLD
					+ CrawlerRules.ELEM_SHOCK_HOLD_PER_RANK * float(rank),
				0.0, false)
		"charm":
			var rank := maxi(card.upgrade_rank("charm"), 0)
			_append(out, CombatStatuses.CHARM,
				CrawlerRules.ELEM_CHARM_HOLD
					+ CrawlerRules.ELEM_CHARM_HOLD_PER_RANK * float(rank),
				0.0, false)
		"ice":
			var rank := maxi(card.upgrade_rank("freeze"), 0)
			_append(out, CombatStatuses.FREEZE,
				CrawlerRules.ELEM_ICE_HOLD
					+ CrawlerRules.ELEM_ICE_HOLD_PER_RANK * float(rank),
				0.0, false)
	return out


static func _append(out: Array[Dictionary], id: StringName, duration: float,
		strength: float, stack: bool) -> void:
	if id.is_empty() or duration <= 0.0:
		return
	out.append({
		"id": String(id),
		"duration": duration,
		"strength": maxf(strength, 0.0),
		"stack": stack,
	})


static func _merge(out: Array[Dictionary], extra: Array[Dictionary]) -> void:
	for entry: Dictionary in extra:
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		var found := false
		for existing: Dictionary in out:
			if str(existing.get("id", "")) != id:
				continue
			existing["duration"] = float(existing.get("duration", 0.0)) \
				+ float(entry.get("duration", 0.0))
			existing["strength"] = float(existing.get("strength", 0.0)) \
				+ float(entry.get("strength", 0.0))
			existing["stack"] = bool(existing.get("stack", false)) \
				or bool(entry.get("stack", false))
			found = true
			break
		if not found:
			out.append(entry.duplicate(true))


static func tint_of(base: Color, entries: Array) -> Color:
	var tint := base
	for entry: Dictionary in entries:
		var wash := Color(0.0, 0.0, 0.0, 0.0)
		match StringName(str(entry.get("id", ""))):
			CombatStatuses.POISON:
				wash = Color(0.32, 0.92, 0.22)
			CombatStatuses.CHARM:
				wash = Color(0.95, 0.38, 0.72)
			CombatStatuses.SHOCK:
				wash = Color(0.95, 0.85, 0.25)
			CombatStatuses.FREEZE:
				wash = Color(0.45, 0.82, 1.0)
		if wash.a > 0.0:
			tint = tint.lerp(wash, 0.62)
	return tint


static func _host_card(player: OnlinePlayer, ability_id: String) -> CrawlerCard:
	if player == null or player.crawler_kit == null:
		return null
	var wanted := CrawlerCatalog.ability_id(ability_id)
	if wanted.is_empty():
		wanted = ability_id
	if player.abilities != null:
		for index in player.abilities.size():
			var card := player.crawler_kit.equipped_card(index)
			if card != null and card.id == wanted:
				return card
	return null
