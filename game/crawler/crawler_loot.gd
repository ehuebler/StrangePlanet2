class_name CrawlerLoot
extends RefCounted

## Kill-loot rolls for crawler abilities, modifiers, and basic city hats.
##
## Each kind has its own 1–3% base chance. Luck lifts every kind toward a
## shared 10% cap so a fortune stack makes drops common without guaranteeing them.

const KIND_ABILITY := "ability"
const KIND_MOD := "mod"
const KIND_HAT := "hat"
const CHANCE_CAP := 0.10
const LUCK_RATE := 0.20
const BASE_CHANCE := {
	KIND_ABILITY: 0.025,
	KIND_MOD: 0.03,
	KIND_HAT: 0.02,
}


static func base_chance(kind: String) -> float:
	return float(BASE_CHANCE.get(kind, 0.02))


static func drop_chance(kind: String, luck_rank: float) -> float:
	var base := clampf(base_chance(kind), 0.01, 0.03)
	var room := maxf(CHANCE_CAP - base, 0.0)
	var lift := 1.0 - exp(-maxf(luck_rank, 0.0) * LUCK_RATE)
	return clampf(base + room * lift, base, CHANCE_CAP)


static func roll_kill_drops(
		progress: CrawlerProgress,
		rng: RandomNumberGenerator,
		rolls: PackedFloat32Array = PackedFloat32Array()
	) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rng == null and rolls.is_empty():
		return out
	var luck := 0.0
	if progress != null:
		luck = progress.luck_rank()
	if _unit(rng, rolls, 0) < drop_chance(KIND_ABILITY, luck):
		var ability := _pick_ability(rng)
		if not ability.is_empty():
			out.append({"kind": KIND_ABILITY, "id": ability})
	if _unit(rng, rolls, 1) < drop_chance(KIND_MOD, luck):
		var mod := _pick_mod(rng)
		if not mod.is_empty():
			out.append({"kind": KIND_MOD, "id": mod})
	if _unit(rng, rolls, 2) < drop_chance(KIND_HAT, luck):
		var hat := _pick_hat(rng)
		if not hat.is_empty():
			out.append({"kind": KIND_HAT, "id": hat})
	return out


static func _unit(
		rng: RandomNumberGenerator,
		rolls: PackedFloat32Array,
		index: int
	) -> float:
	if index < rolls.size():
		return rolls[index]
	if rng != null:
		return rng.randf()
	return 1.0


static func card_payload(drop: Dictionary) -> Dictionary:
	var kind := str(drop.get("kind", ""))
	var id := str(drop.get("id", ""))
	if id.is_empty():
		return {}
	var card: CrawlerCard
	if kind == KIND_ABILITY:
		card = CrawlerCatalog.make_ability(id)
	elif kind == KIND_MOD:
		card = CrawlerCatalog.make_modifier(id)
	if card == null:
		return {}
	return card.to_dict()


static func _pick_ability(rng: RandomNumberGenerator) -> String:
	return _pick_from(CrawlerProgress.ability_stock(), rng)


static func _pick_mod(rng: RandomNumberGenerator) -> String:
	return _pick_from(CrawlerProgress.shop_stock(), rng)


static func _pick_hat(rng: RandomNumberGenerator) -> String:
	return _pick_from(CrawlerProgress.hat_stock(), rng)


static func _pick_from(stock: PackedStringArray, rng: RandomNumberGenerator) -> String:
	if stock.is_empty():
		return ""
	if rng == null:
		return stock[0]
	return stock[rng.randi_range(0, stock.size() - 1)]
