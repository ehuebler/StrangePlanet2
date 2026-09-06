class_name CrawlerStoreUpgradesPage
extends VBoxContainer

## City-store upgrade stall. The top pane is the live loadout: three ability
## cards, their seated mods, and the shared bag. The bottom pane lists gold
## upgrades for whichever card is selected, including mods picked from a
## seated slot or from the bag.

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_40 := Color(0.0, 0.0, 0.0, 0.40)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const INV_EDGE := 36.0
const TILE_MIN := 78.0
const UPGRADE_COLUMNS := 3

var _player: OnlinePlayer
var _kit: CrawlerKit
var _selected_token := ""
var _ability_tiles: Array[CrawlerAbilityTile] = []
var _inventory_slots: Array[RedItemSlot] = []
var _inventory_grid: GridContainer
var _title: Label
var _body: Label
var _rows: GridContainer


func configure(player: OnlinePlayer) -> void:
	_player = player
	_kit = player.crawler_kit if player != null else null


func _ready() -> void:
	name = "StoreUpgradesPage"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 10)
	_build()
	refresh()
	_request_icons()


func refresh() -> void:
	if _kit == null and _player != null:
		_kit = _player.crawler_kit
	if _selected_token.is_empty() or _card_for(_selected_token) == null:
		_selected_token = _first_owned_token()
	_refresh_loadout()
	_fill_detail()


func selected_token() -> String:
	return _selected_token


func _build() -> void:
	var loadout := _pane("StoreUpgradeLoadout")
	loadout.size_flags_stretch_ratio = 0.62
	add_child(loadout)
	var loadout_body := VBoxContainer.new()
	loadout_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loadout_body.add_theme_constant_override(&"separation", 6)
	loadout.add_child(loadout_body)

	var abilities := HBoxContainer.new()
	abilities.name = "StoreAbilityRow"
	abilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abilities.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	abilities.custom_minimum_size.y = TILE_MIN
	abilities.add_theme_constant_override(&"separation", 6)
	loadout_body.add_child(abilities)
	for index in CrawlerRules.ABILITY_SLOTS:
		abilities.add_child(_make_ability_tile(index))

	var inventory_row := HBoxContainer.new()
	inventory_row.name = "StoreInventoryCenter"
	inventory_row.alignment = BoxContainer.ALIGNMENT_CENTER
	inventory_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	inventory_row.add_theme_constant_override(&"separation", 0)
	inventory_row.custom_minimum_size = Vector2(
		CrawlerRules.INVENTORY_COLUMNS * INV_EDGE
			+ (CrawlerRules.INVENTORY_COLUMNS - 1) * 4.0,
		CrawlerRules.INVENTORY_ROWS * INV_EDGE
			+ (CrawlerRules.INVENTORY_ROWS - 1) * 4.0
	)
	loadout_body.add_child(inventory_row)
	var lead := Control.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_row.add_child(lead)
	_inventory_grid = GridContainer.new()
	_inventory_grid.name = "StoreInventorySlots"
	_inventory_grid.columns = CrawlerRules.INVENTORY_COLUMNS
	_inventory_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_inventory_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_inventory_grid.add_theme_constant_override(&"h_separation", 4)
	_inventory_grid.add_theme_constant_override(&"v_separation", 4)
	inventory_row.add_child(_inventory_grid)
	var trail := Control.new()
	trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_row.add_child(trail)
	_build_inventory_slots()

	var detail := _pane("StoreUpgradeDetail")
	detail.size_flags_stretch_ratio = 1.38
	add_child(detail)
	var detail_body := VBoxContainer.new()
	detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_constant_override(&"separation", 8)
	detail.add_child(detail_body)
	_title = _label("SELECT A CARD", 16, RED_BRIGHT)
	_title.name = "StoreUpgradeTitle"
	detail_body.add_child(_title)
	_body = _label(
		"CLICK AN ABILITY, A SEATED MOD, OR A BAG TILE TO SEE ITS UPGRADES.",
		12,
		RED_TEXT,
		true
	)
	_body.name = "StoreUpgradeBody"
	detail_body.add_child(_body)
	var scroll := ScrollContainer.new()
	scroll.name = "StoreUpgradeScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_body.add_child(scroll)
	_rows = GridContainer.new()
	_rows.name = "StoreUpgradeRows"
	_rows.columns = UPGRADE_COLUMNS
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"h_separation", 8)
	_rows.add_theme_constant_override(&"v_separation", 8)
	scroll.add_child(_rows)


func _make_ability_tile(index: int) -> CrawlerAbilityTile:
	var tile := CrawlerAbilityTile.new()
	tile.name = "CrawlerAbilityTile_%d" % index
	tile.editable = false
	tile.compact = true
	tile.custom_minimum_size.y = TILE_MIN
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.setup(index, _kit)
	tile.picked.connect(_on_ability_picked)
	tile.mod_picked.connect(_on_mod_picked)
	_ability_tiles.append(tile)
	return tile


func _build_inventory_slots() -> void:
	if _inventory_grid == null:
		return
	for child: Node in _inventory_grid.get_children():
		_inventory_grid.remove_child(child)
		child.queue_free()
	_inventory_slots.clear()
	var bag := _kit.inventory if _kit != null else null
	for index in CrawlerRules.INVENTORY_SLOTS:
		var slot := RedItemSlot.new()
		slot.name = "CrawlerBag_%d" % index
		slot.set_edge(INV_EDGE)
		slot.placeholder = ""
		slot.draggable = false
		slot.bind(bag, index)
		slot.picked.connect(_on_inventory_picked)
		_inventory_grid.add_child(slot)
		_inventory_slots.append(slot)


func _refresh_loadout() -> void:
	for tile: CrawlerAbilityTile in _ability_tiles:
		tile.setup(tile.index, _kit)
		tile.selected = not _selected_token.is_empty() \
			and tile.token() == _selected_token
		tile.refresh()
		for slot: RedItemSlot in tile.mod_slots():
			var token := slot.item_id()
			slot.selected = token == _selected_token and not token.is_empty()
			slot.draggable = false
			slot.queue_redraw()
	if _inventory_slots.is_empty():
		_build_inventory_slots()
	else:
		var bag := _kit.inventory if _kit != null else null
		for index in _inventory_slots.size():
			_inventory_slots[index].bind(bag, index)
	for slot: RedItemSlot in _inventory_slots:
		var token := slot.item_id()
		slot.selected = token == _selected_token and not token.is_empty()
		slot.draggable = false
		slot.queue_redraw()
	_fit_inventory_columns()
	_request_icons()


func _fill_detail() -> void:
	_clear_rows()
	var card := _card_for(_selected_token)
	if card == null:
		_title.text = "SELECT A CARD"
		_body.text = "CLICK AN ABILITY, A SEATED MOD, OR A BAG TILE TO SEE ITS UPGRADES."
		return
	var gold := 0
	if _player != null and _player.crawler_progress != null:
		gold = _player.crawler_progress.gold
	var kind := "MOD" if card.is_modifier() else "ABILITY"
	_title.text = "%s  //  %s" % [kind, CrawlerCatalog.title_of(card.id).to_upper()]
	var host := _kit.host_ability_for(card.token()) if _kit != null else null
	var host_id := host.id if host != null else ""
	var size_rank := card.upgrade_rank("size") if card.id == "big" else -1
	var description := CrawlerCatalog.description_of(card.id, host_id, size_rank).strip_edges()
	if description.is_empty():
		description = ItemDB.description(card.id, host_id, size_rank).strip_edges()
	var body_lines := PackedStringArray()
	body_lines.append(description if not description.is_empty() else "NO DESCRIPTION FILED.")
	if card.is_modifier():
		var ranks := {}
		for stat_id: String in CrawlerRules.upgrade_stats_for(card.id):
			ranks[stat_id] = _kit.upgrade_rank_for(card, stat_id) if _kit != null \
				else card.upgrade_rank(stat_id)
		var level := _kit.shop_rank_for(card) if _kit != null else card.shop_rank()
		body_lines.append_array(CrawlerRules.mod_progress_lines(card.id, level, ranks))
	_body.text = "\n".join(body_lines)
	var listed := CrawlerRules.upgrade_stats_for(card.id)
	var rows := 0
	for stat_id: String in listed:
		if stat_id == "slots" and card.slot_count >= CrawlerRules.MAX_MOD_SLOTS:
			continue
		_add_upgrade_tile(card, stat_id, gold)
		rows += 1
	if rows <= 0:
		var note := _label("THIS CARD HAS NO STORE UPGRADES.", 13, RED_MUTED, true)
		note.name = "StoreUpgradeEmpty"
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(note)


func _add_upgrade_tile(card: CrawlerCard, stat_id: String, gold: int) -> void:
	var price := CrawlerProgress.upgrade_price(
		_kit.shop_rank_for(card) if _kit != null else card.shop_rank(),
		card.id)
	var rank := _kit.upgrade_rank_for(card, stat_id) if _kit != null \
		else card.upgrade_rank(stat_id)
	var cap := CrawlerRules.upgrade_max_rank(card.id, stat_id)
	var at_max := cap > 0 and rank >= cap
	var blurb := CrawlerRules.upgrade_stat_blurb(card.id, stat_id)
	if stat_id == "slots":
		blurb += " %d → %d." % [card.slot_count, card.slot_count + 1]
	elif card.id == "big" and stat_id == "size":
		blurb += " %s → %s." % [
			CrawlerRules.format_mul(CrawlerRules.big_size_scale(rank)),
			CrawlerRules.format_mul(CrawlerRules.big_size_scale(mini(rank + 1, cap))),
		]
	else:
		blurb += " Rank %d → %d." % [rank, rank + 1]
	var tile := PanelContainer.new()
	tile.name = "UpgradeTile_%s" % stat_id
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(160.0, 148.0)
	tile.add_theme_stylebox_override(
		&"panel",
		_box(BLACK_40, Color(RED_BRIGHT, 0.82), 2)
	)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override(&"separation", 6)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.add_child(copy)
	copy.add_child(_label(
		CrawlerRules.upgrade_stat_title(stat_id).to_upper(),
		14,
		RED_TEXT
	))
	copy.add_child(_label("%dg" % price, 13, GREEN_TEXT))
	var detail := _label(blurb, 11, RED_MUTED, true)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(detail)
	var button := Button.new()
	button.name = "UpgradeAct_%s" % stat_id
	button.text = "MAX" if at_max else "UPGRADE"
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_END
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.disabled = at_max or gold < price
	button.pressed.connect(_buy_upgrade.bind(card.uid, stat_id))
	_style_action(button, not at_max and gold >= price)
	copy.add_child(button)
	_rows.add_child(tile)


func _buy_upgrade(uid: String, stat_id: String) -> void:
	if _player != null:
		_player.upgrade_crawler_card(uid, stat_id)
	refresh()


func _on_ability_picked(tile: CrawlerAbilityTile) -> void:
	if tile == null:
		return
	_select(tile.token())


func _on_mod_picked(slot: RedItemSlot) -> void:
	if slot == null or slot.item_id().is_empty():
		return
	_select(slot.item_id())


func _on_inventory_picked(slot: RedItemSlot) -> void:
	if slot == null or slot.item_id().is_empty():
		return
	_select(slot.item_id())


func _select(token: String) -> void:
	_selected_token = token
	_refresh_loadout()
	_fill_detail()


func _first_owned_token() -> String:
	if _kit == null:
		return ""
	for index in CrawlerRules.ABILITY_SLOTS:
		var card := _kit.equipped_card(index)
		if card != null:
			return card.token()
	for index in CrawlerRules.INVENTORY_SLOTS:
		var bag := _kit.inventory_card(index)
		if bag != null:
			return bag.token()
	return ""


func _card_for(token: String) -> CrawlerCard:
	if _kit == null or token.is_empty():
		return null
	return _kit.card_for_token(token)


func _fit_inventory_columns() -> void:
	if _inventory_grid == null:
		return
	_inventory_grid.columns = CrawlerRules.INVENTORY_COLUMNS


func _request_icons() -> void:
	var menu := _store_menu()
	if menu == null:
		return
	var ids: Array = ["wobble", "big"]
	for id: String in ItemDB.ability_ids():
		ids.append(id)
	if _kit != null:
		for card: CrawlerCard in _kit.cards.values():
			if card != null and not ids.has(card.id):
				ids.append(card.id)
	menu.request_item_icons(ids)


func notify_icon_ready() -> void:
	for tile: CrawlerAbilityTile in _ability_tiles:
		if tile != null:
			tile.refresh()
	for slot: RedItemSlot in _inventory_slots:
		if slot != null:
			slot.queue_redraw()


func _store_menu() -> CrawlerFieldMenu:
	var node: Node = get_parent()
	while node != null:
		if node is CrawlerFieldMenu:
			return node as CrawlerFieldMenu
		node = node.get_parent()
	return null


func _clear_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.free()


func _pane(node_name: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK_40
	box.border_color = Color(RED_BRIGHT, 0.88)
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.content_margin_left = 10
	box.content_margin_top = 10
	box.content_margin_right = 10
	box.content_margin_bottom = 10
	frame.add_theme_stylebox_override(&"panel", box)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = Color.TRANSPARENT
	glow.border_color = Color(RED, 0.90)
	glow.border_width = 1.5
	glow.glow_intensity = 1.15
	glow.glow_spread = 8.0
	glow.glow_layers = 4
	return frame


func _label(text: String, font_size: int, colour: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _style_action(button: Button, enabled: bool) -> void:
	var accent := GREEN if enabled else Color(RED, 0.55)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if enabled else Color(0.08, 0.02, 0.02, 0.9)
	button.add_theme_font_size_override(&"font_size", 15)
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))
	button.add_theme_stylebox_override(&"normal", _box(fill, Color(accent, 0.95), 2))
	button.add_theme_stylebox_override(&"hover", _box(BLACK_68, GREEN, 2))
	button.add_theme_stylebox_override(&"pressed", _box(Color(0.0, 0.19, 0.055, 0.90), GREEN, 2))
	button.add_theme_stylebox_override(&"disabled", _box(fill, Color(1, 1, 1, 0.28), 1))
	button.add_theme_stylebox_override(&"focus", _box(fill, GREEN, 2))


func _box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_content_margin_all(8)
	return box
