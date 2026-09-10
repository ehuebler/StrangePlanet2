class_name Ability
extends RefCounted

## One power in one of the player's numbered ability slots.
##
## An ability is not a node and owns nothing in the scene. It is handed the
## player, told when its button goes down, held and released, and asked whether
## it is allowed to run at all; everything it does happens through the player it
## was given and through the shared systems — [DamageHit] for anything it
## damages, [TerrainScars] for anything it deforms. That is what lets two very
## different powers, a sustained beam and a single launch, live behind the same
## six methods.
##
## The numbers come from the generated [AbilityDefinition], not from here. A
## subclass reads its own stats out of the configured dictionary, so damage and
## range are edited in the manifest the menu reads rather than hidden in code.

## Stances an ability may be started from. Left empty, any of them.
var allowed_stances: Array[int] = []
## Whether being in the water stops it. A beam that fires through the sea would
## be a beam that boils it, and neither is a thing this game has.
var blocked_underwater := false

var player: OnlinePlayer
## Which hotbar slot this is bound to. Keys 1-4 select it; click fires it.
var slot := 0
var ability_id := ""
var definition: AbilityDefinition
var stats: Dictionary = {}
## Crawler modifier catalogue ids currently seated on this instance.
var modifiers: PackedStringArray = []
var crawler_uid := ""

## Seconds until it may be used again, counted down by the controller.
var _cooldown_left := 0.0
var _held := false
var _ammo_spent := false


## Called once when the slot is filled. A subclass overrides
## [method _configure] rather than this, so it cannot forget to record what it
## was given.
func configure(owner: OnlinePlayer, index: int, id: String,
		record: Variant) -> void:
	player = owner
	slot = index
	ability_id = id
	definition = null
	stats = {}
	blocked_underwater = false
	allowed_stances.clear()
	if record is AbilityDefinition:
		definition = record
		stats = definition.stats
		blocked_underwater = definition.blocked_underwater
		for stance_value: int in definition.allowed_stances:
			allowed_stances.append(stance_value)
	elif record is Dictionary:
		stats = record as Dictionary
	modifiers = PackedStringArray()
	crawler_uid = ""
	_configure()


func apply_crawler(card: CrawlerCard) -> void:
	if card == null:
		return
	crawler_uid = card.uid
	modifiers = card.filled_modifier_ids()
	if player != null and player.has_method(&"overdrive_active") \
			and bool(player.call(&"overdrive_active")) \
			and card.id != "overdrive" \
			and player.has_method(&"overdrive_borrowed_mods"):
		var held: Variant = player.call(&"overdrive_borrowed_mods")
		if held is Array:
			for item: Variant in held:
				var mod := item as CrawlerCard
				if mod == null or mod.id.is_empty():
					continue
				if not CrawlerCatalog.compatible(mod.id, card.id):
					continue
				if not modifiers.has(mod.id):
					modifiers.append(mod.id)
	var kit := player.crawler_kit if player != null else null
	if kit != null:
		stats = kit.stats_for(card)
	else:
		stats = CrawlerCatalog.resolve_stats(ability_id, modifiers, stats)


func has_modifier(id: String) -> bool:
	return modifiers.has(id) or stat(id, 0.0) > 0.0


func host_card() -> CrawlerCard:
	if player == null or player.crawler_kit == null:
		return null
	var kit := player.crawler_kit
	var seated := kit.equipped_card(slot)
	if seated != null and (crawler_uid.is_empty() or seated.uid == crawler_uid):
		return seated
	if not crawler_uid.is_empty():
		return kit.cards.get(crawler_uid) as CrawlerCard
	return null


func seated_mods(id: String) -> Array[CrawlerCard]:
	var out: Array[CrawlerCard] = []
	var seen := {}
	var card := host_card()
	if card != null:
		for index in card.slot_count:
			var child := card.mod_at(index)
			if child != null and child.id == id:
				out.append(child)
				seen[child.uid] = true
	if player != null and ability_id != "overdrive" \
			and player.has_method(&"overdrive_active") \
			and bool(player.call(&"overdrive_active")) \
			and player.has_method(&"overdrive_borrowed_mods") \
			and CrawlerCatalog.compatible(id, ability_id):
		var held: Variant = player.call(&"overdrive_borrowed_mods")
		if held is Array:
			for item: Variant in held:
				var child := item as CrawlerCard
				if child == null or child.id != id:
					continue
				if seen.has(child.uid):
					continue
				out.append(child)
				seen[child.uid] = true
	return out


func _configure() -> void:
	pass


## A number out of the catalogue, with a fallback for an ability whose entry
## does not mention it.
func stat(key: String, fallback: float) -> float:
	var value := float(stats.get(key, fallback))
	if key == "damage" and player != null and CrawlerRules.active():
		return CrawlerRules.paired_hit_damage(player, value)
	if key == "knockback" and player != null and CrawlerRules.active() \
			and player.has_method(&"crawler_knockback_scale"):
		value *= float(player.call(&"crawler_knockback_scale"))
	if key == "range" and player != null and CrawlerRules.active() \
			and player.has_method(&"crawler_range_scale"):
		value *= float(player.call(&"crawler_range_scale"))
	return value


func cooldown() -> float:
	return stat("cooldown", 0.0)


func cooldown_left() -> float:
	return _cooldown_left


func is_held() -> bool:
	return _held


## Whether the button would do anything right now. Deliberately answers the
## whole question — cooldown, stance and water — so a caller never has to
## assemble the rule from pieces and get it subtly different.
func can_use() -> bool:
	if player == null or not player.can_attack() or _cooldown_left > 0.0:
		return false
	if blocked_underwater and player.submerged_share() > 0.0:
		return false
	if not allowed_stances.is_empty() \
			and not allowed_stances.has(player.stance()):
		return false
	if not _has_shots():
		return false
	return _can_use()


## Hat autofire uses the cap's cadence, not the ability's own cooldown.
func can_auto_use() -> bool:
	var held_cd := _cooldown_left
	_cooldown_left = 0.0
	var ok := not _held and can_use()
	_cooldown_left = held_cd
	return ok


func clear_cooldown() -> void:
	_cooldown_left = 0.0


func _has_shots() -> bool:
	if player == null or player.crawler_kit == null:
		return true
	var card := host_card()
	if card == null:
		return true
	return player.crawler_kit.can_fire(card)


func _can_use() -> bool:
	return true


## The button went down. Returns whether the ability actually started, which is
## what decides whether the cooldown is charged.
func press() -> bool:
	if _held or not can_use():
		return false
	_held = true
	_ammo_spent = false
	if player != null:
		player.note_crawler_cast(stats)
	if not _press():
		_held = false
		return false
	_ammo_spent = _spend_shot()
	return true


func _spend_shot() -> bool:
	if player == null or player.crawler_kit == null:
		return false
	var card := host_card()
	if card == null or not player.crawler_kit.uses_ammo(card):
		return false
	return player.crawler_kit.spend_ammo(card)


func refund_shot() -> void:
	if not _ammo_spent or player == null or player.crawler_kit == null:
		return
	var card := host_card()
	if card != null:
		player.crawler_kit.refund_ammo(card)
	_ammo_spent = false


func _press() -> bool:
	return true


## Every physics tick while the ability is live. A sustained ability does its
## work here; a one-shot one has already done it in [method _press] and uses
## this only to notice that it is finished.
func tick(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _held and (player == null \
			or (not player.can_attack()
				and not _can_continue_when_attack_blocked())):
		cancel()
		return
	if _held:
		_tick(delta)


func _tick(_delta: float) -> void:
	pass


## A committed movement may deliberately disable every other attack while its
## own Ability instance remains responsible for observing completion.
func _can_continue_when_attack_blocked() -> bool:
	return false


## The button came up, the duration ran out, or something else ended it. Safe to
## call when the ability is not running.
func release() -> void:
	if not _held:
		return
	_held = false
	_release()
	_cooldown_left = cooldown()


func _release() -> void:
	pass


## Ends the ability without charging a cooldown, for a player leaving the world
## or swapping the slot out from under it.
func cancel() -> void:
	if not _held:
		return
	_held = false
	_release()
