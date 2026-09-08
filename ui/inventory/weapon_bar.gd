class_name WeaponBar
extends Control

## The four ability slots along the bottom of the HUD, in input order: 1, 2, 3,
## 4. A cape Q tile and a juke F tile sit to their left when those moves exist.
## Numbered keys and scroll select a numbered tile; click fires the selected one.
##
## Tiles are ordinary inventory tiles with input turned off: they are a readout
## here, not somewhere to rummage.

const GAP := 4
## Height of the strip the bar is centred in, above the bottom edge.
const STRIP := 118.0
const BOTTOM_MARGIN := 16.0

var _abilities: ItemContainer
var _hotbar: ItemContainer
var _slots: Array[ItemSlot] = []
var _ability_slots: Array[ItemSlot] = []
var _cape_slot: ItemSlot
var _juke_slot: ItemSlot
var _ability_controller: AbilityController
var _icons: ItemIcons
var _column: VBoxContainer
var _hotbar_row: HBoxContainer
var _cell_plate: PanelContainer
var _cell_label: Label
var _selected := 0


func _init() -> void:
	name = "WeaponBar"


func _ready() -> void:
	# Across the bottom of the screen, and transparent to the mouse: a left click
	# over the bar is a fire, not a click on a tile.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_top = -(STRIP + BOTTOM_MARGIN)
	offset_bottom = -BOTTOM_MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_process(_ability_controller != null)


## Compatibility binding for callers that only know about the old weapon
## container. New code should bind both halves with [method bind_loadout].
func bind(container: ItemContainer) -> void:
	bind_loadout(container if container != null and container.size() > 0
			and container.filter_of(0) == ItemDB.ABILITY else null, container)


func bind_loadout(ability_container: ItemContainer, hotbar_container: ItemContainer) -> void:
	for old_container: ItemContainer in [_abilities, _hotbar]:
		if old_container != null and old_container.changed.is_connected(refresh):
			old_container.changed.disconnect(refresh)
	_abilities = ability_container
	_hotbar = hotbar_container
	_sync_slot_count()
	_bind_slots()
	if _abilities != null and not _abilities.changed.is_connected(refresh):
		_abilities.changed.connect(refresh)
	refresh()


## Supplies the live runtime instances behind the ability tiles. Containers
## know which icon belongs in a slot; the controller knows how far that ability
## is through its current cooldown.
func bind_ability_controller(controller: AbilityController) -> void:
	_ability_controller = controller
	set_process(_ability_controller != null)
	_update_cooldowns()
	_update_juke_slot()


## Highlights the selected ability tile. Index is an ability slot, not a
## leftover weapon slot.
func select(index: int) -> void:
	_selected = index
	_update_selection()


## Compatibility: empty hands still show the selected ability tile.
func holster() -> void:
	_update_selection()


## Shows a line under the bar, or hides the plate when passed nothing: an empty
## plate would read as a blank sticker over the world.
func show_cell(text: String) -> void:
	_cell_label.text = text
	_cell_plate.visible = not text.is_empty()


## CombatHud adds the flight/parry and health bars here so they stay centred
## beneath the inventory boxes at every resolution.
func add_vitals(control: Control) -> void:
	if _column == null:
		call_deferred(&"add_vitals", control)
		return
	if control.get_parent() != null:
		control.reparent(_column)
	else:
		_column.add_child(control)


func refresh() -> void:
	_sync_slot_count()
	_bind_slots()
	for slot in _slots:
		slot.queue_redraw()
	_update_cooldowns()
	_update_ammo()
	_update_cape_slot()
	_update_juke_slot()
	_update_selection()


func _process(_delta: float) -> void:
	_update_cooldowns()
	_update_ammo()
	_update_cape_slot()
	_update_juke_slot()


func _update_ammo() -> void:
	var kit: CrawlerKit = null
	if _ability_controller != null and _ability_controller.player != null:
		kit = _ability_controller.player.crawler_kit
	for index in _ability_slots.size():
		var text := ""
		if kit != null:
			text = kit.ammo_count_text(kit.equipped_card(index))
		_ability_slots[index].count_text = text


func _update_cooldowns() -> void:
	for index in _ability_slots.size():
		var fill := 1.0
		var active := false
		var ability := _ability_controller.ability_in(index) \
			if _ability_controller != null else null
		if ability != null:
			var duration := maxf(ability.cooldown(), 0.0)
			var left := maxf(ability.cooldown_left(), 0.0)
			active = duration > 0.0 and left > 0.0
			if active:
				fill = 1.0 - clampf(left / duration, 0.0, 1.0)
		_ability_slots[index].set_cooldown(fill, active)


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_column = VBoxContainer.new()
	_column.name = "HotbarStack"
	_column.add_theme_constant_override(&"separation", 5)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_column)

	_cell_plate = PanelContainer.new()
	_cell_plate.visible = false
	_cell_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_column.add_child(_cell_plate)
	RedHudTheme.panel(_cell_plate, 0.0)

	var padding := MarginContainer.new()
	for side in [&"margin_left", &"margin_right"]:
		padding.add_theme_constant_override(side, 7)
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_plate.add_child(padding)

	_cell_label = Label.new()
	RedHudTheme.label(_cell_label, 9)
	_cell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_child(_cell_label)

	_hotbar_row = HBoxContainer.new()
	_hotbar_row.name = "HotbarRow"
	_hotbar_row.add_theme_constant_override(&"separation", GAP)
	_hotbar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_hotbar_row)
	_cape_slot = ItemSlot.new()
	_cape_slot.name = "CapeSlot"
	_cape_slot.interactive = false
	_cape_slot.hud_style = true
	_cape_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cape_slot.badge = "Q"
	_cape_slot.visible = false
	_hotbar_row.add_child(_cape_slot)
	_juke_slot = ItemSlot.new()
	_juke_slot.name = "JukeSlot"
	_juke_slot.interactive = false
	_juke_slot.hud_style = true
	_juke_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_juke_slot.badge = "F"
	_hotbar_row.add_child(_juke_slot)
	var row := HBoxContainer.new()
	row.name = "HotbarSlots"
	row.add_theme_constant_override(&"separation", GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_row.add_child(row)
	_fill_ability_row(row)

	_icons = ItemIcons.new()
	add_child(_icons)
	_icons.icon_ready.connect(_on_icon_ready)
	var icon_ids: Array = []
	for ability_id: String in ItemDB.ability_ids():
		icon_ids.append(ability_id)
	icon_ids.append(CrawlerProgress.CAPE_GOLD)
	icon_ids.append(CrawlerProgress.STAT_JUKE)
	_icons.request(icon_ids)
	_bind_slots()
	_update_juke_slot()
	_update_selection()


func _ability_count() -> int:
	if _abilities != null:
		return _abilities.size()
	return CrawlerRules.ability_slots()


func _fill_ability_row(row: HBoxContainer) -> void:
	for index in _ability_count():
		var slot := ItemSlot.new()
		slot.interactive = false
		slot.hud_style = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.badge = str(index + 1)
		row.add_child(slot)
		_slots.append(slot)
		_ability_slots.append(slot)


func _sync_slot_count() -> void:
	var wanted := _ability_count()
	if _ability_slots.size() == wanted:
		return
	var row := find_child("HotbarSlots", true, false) as HBoxContainer
	if row == null:
		return
	for slot: ItemSlot in _ability_slots:
		if slot.get_parent() == row:
			row.remove_child(slot)
		slot.queue_free()
	_ability_slots.clear()
	_slots.clear()
	_fill_ability_row(row)


func _update_cape_slot() -> void:
	if _cape_slot == null:
		return
	var player: OnlinePlayer = null
	if _ability_controller != null:
		player = _ability_controller.player
	var show := player != null and player.cape_hud_visible()
	_cape_slot.visible = show
	if not show:
		_cape_slot.forced_item_id = ""
		_cape_slot.selected = false
		_cape_slot.set_cooldown(1.0, false)
		return
	_cape_slot.forced_item_id = player.cape_ability_id()
	_cape_slot.selected = player.gold_cape_active()
	var duration := player.cape_ability_cooldown()
	var left := player.cape_ability_cooldown_remaining()
	var cooling := duration > 0.0 and left > 0.0
	var fill := 1.0
	if cooling:
		fill = 1.0 - clampf(left / duration, 0.0, 1.0)
	_cape_slot.set_cooldown(fill, cooling)


func _update_juke_slot() -> void:
	if _juke_slot == null:
		return
	var player: OnlinePlayer = null
	if _ability_controller != null:
		player = _ability_controller.player
	_juke_slot.visible = true
	_juke_slot.forced_item_id = CrawlerProgress.STAT_JUKE
	_juke_slot.selected = player != null and player.juke_active()
	if player == null or not player.has_method(&"juke_cooldown_remaining"):
		_juke_slot.set_cooldown(1.0, false)
		return
	var duration := player.juke_cooldown()
	var left := player.juke_cooldown_remaining()
	var cooling := duration > 0.0 and left > 0.0
	var fill := 1.0
	if cooling:
		fill = 1.0 - clampf(left / duration, 0.0, 1.0)
	_juke_slot.set_cooldown(fill, cooling)


func _bind_slots() -> void:
	for index in _ability_slots.size():
		_ability_slots[index].bind(_abilities, index)


func _update_selection() -> void:
	for index in _ability_slots.size():
		_ability_slots[index].selected = index == _selected
		_ability_slots[index].queue_redraw()


func _on_icon_ready(_id: String, _texture: Texture2D) -> void:
	refresh()
