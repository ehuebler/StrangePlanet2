class_name AbilityController
extends Node

## Keeps the player's two ability slots filled and running.
##
## The player already knows how to route a mouse button to a slot and emit
## [signal OnlinePlayer.ability_activated]; what it does not know is what an
## ability is. This is the piece between the two. It watches the ability
## container, builds the right [Ability] for whatever is in each slot, and
## drives press, hold and release on the fixed physics clock so a sustained
## power ticks at the same rate the body moves.
##
## Only the local player's abilities run. A remote peer's laser is drawn from
## the effects their own machine broadcasts, not simulated a second time here —
## the same division the weapons already use.

var player: OnlinePlayer

## One entry per ability slot, null where the slot is empty.
var _abilities: Array[Ability] = []
## Which instance fingerprint each slot was last built for, so a container
## change that did not touch a slot does not rebuild the ability standing in it.
var _built_for := PackedStringArray()


func _ready() -> void:
	player = get_parent() as OnlinePlayer
	if player == null:
		push_error("AbilityController must be a child of OnlinePlayer")
		set_physics_process(false)
		return
	_abilities.resize(player.abilities.size())
	_built_for.resize(player.abilities.size())
	player.abilities.changed.connect(_on_slots_changed)
	player.ability_activated.connect(_on_activated)
	player.ability_released.connect(_on_released)
	if player.crawler_kit != null \
			and not player.crawler_kit.changed.is_connected(_on_slots_changed):
		player.crawler_kit.changed.connect(_on_slots_changed)
	_rebuild()


func _exit_tree() -> void:
	cancel_all()


## Immediately stops every live slot without letting a committed ability veto
## its ordinary button release. Used when the body becomes incapacitated.
func cancel_all() -> void:
	for ability in _abilities:
		if ability != null:
			ability.cancel()


## The ability standing in a slot, or null. The harnesses read this; nothing in
## the game needs to reach past the controller.
func ability_in(index: int) -> Ability:
	if index < 0 or index >= _abilities.size():
		return null
	return _abilities[index]


func _on_slots_changed() -> void:
	_rebuild()


func _rebuild() -> void:
	if _abilities.size() != player.abilities.size():
		_abilities.resize(player.abilities.size())
		_built_for.resize(player.abilities.size())
	for index in _abilities.size():
		var id := player.abilities.get_item(index)
		var key := _slot_key(index, id)
		if key == _built_for[index]:
			continue
		var standing := _abilities[index]
		if standing != null:
			standing.cancel()
		_built_for[index] = key
		_abilities[index] = _make(index, id)


func _slot_key(index: int, id: String) -> String:
	if player.crawler_kit != null:
		return player.crawler_kit.slot_fingerprint(index)
	return id


func _make(index: int, id: String) -> Ability:
	if not ItemDB.accepts_ability(id):
		return null
	var definition := ItemDB.ability_definition(id)
	if definition == null:
		push_error("Ability '%s' has no generated definition" % id)
		return null
	var path := ItemDB.ability_script(id)
	if path.is_empty():
		push_warning("Ability '%s' has no script" % id)
		return null
	var script := load(path) as GDScript
	if script == null:
		push_error("Ability '%s' could not load %s" % [id, path])
		return null
	var ability := script.new() as Ability
	if ability == null:
		push_error("Ability '%s' script is not an Ability" % id)
		return null
	ability.configure(player, index, CrawlerCatalog.ability_id(id), definition)
	if player.crawler_kit != null:
		ability.apply_crawler(player.crawler_kit.equipped_card(index))
	return ability


func _on_activated(index: int, _id: String) -> void:
	var ability := ability_in(index)
	if ability != null:
		ability.press()


func _on_released(index: int) -> void:
	var ability := ability_in(index)
	if ability != null:
		ability.release()


## On the physics clock rather than the frame clock. Cooldowns could run on
## either, but a beam that damages once per tick has to tick at the same rate
## the body it is fired from moves, or its damage rate follows the frame rate.
func _physics_process(delta: float) -> void:
	for ability in _abilities:
		if ability != null:
			ability.tick(delta)
