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
const UPGRADE_TILE_MIN := Vector2(108.0, 72.0)
const BASIC_UPGRADE_STATS: Array[String] = [
	"damage", "cooldown", "duration", "range", "size", "knockback",
	"speed", "heal", "boost", "cast",
]

var _player: OnlinePlayer
var _kit: CrawlerKit
var _selected_token := ""
var _ability_tiles: Array[CrawlerAbilityTile] = []
var _ability_row: HBoxContainer
var _inventory_slots: Array[RedItemSlot] = []
var _inventory_grid: GridContainer
var _title: Label
var _type_marks: HBoxContainer
var _body: Label
var _rows: Control
var _upgrade_host: Control
var _upgrade_columns_used := UPGRADE_COLUMNS


func configure(player: OnlinePlayer) -> void:
	if _player != null and _player.crawler_progress != null \
			and _player.crawler_progress.changed.is_connected(refresh):
		_player.crawler_progress.changed.disconnect(refresh)
	_player = player
	_kit = player.crawler_kit if player != null else null
	if _player != null and _player.crawler_progress != null \
			and not _player.crawler_progress.changed.is_connected(refresh):
		_player.crawler_progress.changed.connect(refresh)


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

	var ability_scroll := ScrollContainer.new()
	ability_scroll.name = "StoreAbilityScroll"
	ability_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ability_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ability_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ability_scroll.custom_minimum_size.y = TILE_MIN + 8.0
	ability_scroll.clip_contents = true
	loadout_body.add_child(ability_scroll)
	var abilities := HBoxContainer.new()
	abilities.name = "StoreAbilityRow"
	abilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abilities.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	abilities.custom_minimum_size.y = TILE_MIN
	abilities.add_theme_constant_override(&"separation", 6)
	_ability_row = abilities
	ability_scroll.add_child(abilities)
	for index in _ability_slot_count():
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
	detail_body.add_theme_constant_override(&"separation", 4)
	detail.add_child(detail_body)
	var heading := HBoxContainer.new()
	heading.name = "StoreUpgradeHeading"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override(&"separation", 8)
	detail_body.add_child(heading)
	_title = _label("SELECT A CARD", 14, RED_BRIGHT)
	_title.name = "StoreUpgradeTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	_type_marks = CrawlerTypeMarks.make_row("StoreUpgradeTypes", PackedStringArray(), 20.0)
	heading.add_child(_type_marks)
	_body = _label(
		"CLICK AN ABILITY, A SEATED MOD, OR A BAG TILE TO SEE ITS UPGRADES.",
		11,
		RED_TEXT,
		true,
		2
	)
	_body.name = "StoreUpgradeBody"
	_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail_body.add_child(_body)
	_upgrade_host = MarginContainer.new()
	_upgrade_host.name = "StoreUpgradeHost"
	_upgrade_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrade_host.clip_contents = true
	_upgrade_host.add_theme_constant_override(&"margin_left", 0)
	_upgrade_host.add_theme_constant_override(&"margin_top", 0)
	_upgrade_host.add_theme_constant_override(&"margin_right", 0)
	_upgrade_host.add_theme_constant_override(&"margin_bottom", 0)
	_upgrade_host.resized.connect(_fit_upgrade_grid)
	detail_body.add_child(_upgrade_host)
	_rows = Control.new()
	_rows.name = "StoreUpgradeRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.clip_contents = true
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.set_meta(&"columns", UPGRADE_COLUMNS)
	_upgrade_host.add_child(_rows)


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
		slot.use_soft_fx()
		slot.draggable = false
		slot.bind(bag, index)
		slot.picked.connect(_on_inventory_picked)
		_inventory_grid.add_child(slot)
		_inventory_slots.append(slot)


func _ability_slot_count() -> int:
	if _player != null and _player.abilities != null:
		return _player.abilities.size()
	return CrawlerRules.ABILITY_SLOTS


func _sync_ability_tiles() -> void:
	if _ability_row == null:
		return
	var wanted := _ability_slot_count()
	while _ability_tiles.size() < wanted:
		_ability_row.add_child(_make_ability_tile(_ability_tiles.size()))
	while _ability_tiles.size() > wanted:
		var tile: CrawlerAbilityTile = _ability_tiles.pop_back()
		if tile != null:
			tile.queue_free()


func _refresh_loadout() -> void:
	_sync_ability_tiles()
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
		CrawlerTypeMarks.fill(_type_marks, PackedStringArray())
		_body.text = "CLICK AN ABILITY, A SEATED MOD, OR A BAG TILE TO SEE ITS UPGRADES."
		return
	var gold := 0
	if _player != null and _player.crawler_progress != null:
		gold = _player.crawler_progress.purse_gold()
	var kind := "MOD" if card.is_modifier() else "ABILITY"
	_title.text = "%s  //  %s" % [kind, CrawlerCatalog.title_of(card.id).to_upper()]
	CrawlerTypeMarks.fill(_type_marks, CrawlerCatalog.display_types(card.id), 20.0)
	var host := _kit.host_ability_for(card.token()) if _kit != null else null
	var host_id := host.id if host != null else ""
	var size_rank := card.upgrade_rank("size") if card.id == "big" else -1
	var description := CrawlerCatalog.description_of(card.id, host_id, size_rank).strip_edges()
	if description.is_empty():
		description = ItemDB.description(card.id, host_id, size_rank).strip_edges()
	var body_lines := PackedStringArray()
	body_lines.append(description if not description.is_empty() else "NO DESCRIPTION FILED.")
	var typed := CrawlerCatalog.type_line(card.id)
	if not typed.is_empty():
		body_lines.append(typed)
	_body.text = "\n".join(body_lines)
	var listed := CrawlerRules.upgrade_stats_for(card.id)
	if _rows != null:
		_upgrade_columns_used = _upgrade_columns(listed.size())
		_rows.set_meta(&"columns", _upgrade_columns_used)
	var rows := 0
	for stat_id: String in listed:
		if stat_id == "slots" and card.slot_count >= CrawlerRules.MAX_MOD_SLOTS:
			continue
		_add_upgrade_tile(card, stat_id, gold)
		rows += 1
	if rows <= 0:
		var note := _label("THIS CARD HAS NO STORE UPGRADES.", 12, RED_MUTED, true, 2)
		note.name = "StoreUpgradeEmpty"
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_rows.add_child(note)
	_fit_upgrade_grid()
	_fit_upgrade_grid.call_deferred()


func _add_upgrade_tile(card: CrawlerCard, stat_id: String, gold: int) -> void:
	var price := CrawlerProgress.upgrade_price(
		_kit.shop_rank_for(card) if _kit != null else card.shop_rank(),
		card.id)
	var rank := _kit.upgrade_rank_for(card, stat_id) if _kit != null \
		else card.upgrade_rank(stat_id)
	var cap := CrawlerRules.upgrade_max_rank(card.id, stat_id)
	var city := _player.crawler_city_key() if _player != null else ""
	var progress := _player.crawler_progress if _player != null else null
	var unlimited := progress != null and progress.shops_are_unlimited()
	var at_max := CrawlerRules.upgrade_at_cap(card.id, stat_id, rank, unlimited)
	var in_stock := progress == null \
			or progress.upgrade_in_stock(card.id, stat_id, city)
	var tile := Control.new()
	tile.name = "UpgradeTile_%s" % stat_id
	tile.size_flags_horizontal = Control.SIZE_FILL
	tile.size_flags_vertical = Control.SIZE_FILL
	tile.custom_minimum_size = UPGRADE_TILE_MIN
	tile.clip_contents = true
	var plate := Panel.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.clip_contents = true
	plate.add_theme_stylebox_override(&"panel", _fill_box(BLACK_40, 3))
	tile.add_child(plate)
	_ensure_rim(tile, RED_BRIGHT, 1.5, 3.0)
	var copy := VBoxContainer.new()
	copy.name = "UpgradeCopy"
	copy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	copy.offset_left = 4.0
	copy.offset_top = 4.0
	copy.offset_right = -4.0
	copy.offset_bottom = -4.0
	copy.add_theme_constant_override(&"separation", 1)
	copy.alignment = BoxContainer.ALIGNMENT_BEGIN
	copy.clip_contents = true
	tile.add_child(copy)
	var title := _label(
		CrawlerRules.upgrade_stat_title(stat_id, card.id).to_upper(),
		10,
		RED_TEXT,
		true,
		2
	)
	title.name = "UpgradeTitle_%s" % stat_id
	title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	copy.add_child(title)
	var price_line := "%dg" % price
	if _is_basic_upgrade(card, stat_id):
		price_line = "%dg  %d→%d" % [price, rank, rank + 1] if not at_max \
			else "%dg  MAX" % price
	var cost := _label(price_line, 9, GREEN_TEXT)
	cost.name = "UpgradeCost_%s" % stat_id
	copy.add_child(cost)
	if not _is_basic_upgrade(card, stat_id):
		var blurb := _upgrade_blurb(card, stat_id, rank, cap, unlimited)
		if not blurb.is_empty():
			var detail := _label(blurb, 8, RED_MUTED, true, 2)
			detail.name = "UpgradeBlurb_%s" % stat_id
			detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
			copy.add_child(detail)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(spacer)
	var button := Button.new()
	button.name = "UpgradeAct_%s" % stat_id
	button.clip_text = false
	button.clip_contents = false
	button.custom_minimum_size = Vector2(64.0, 22.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_END
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if at_max:
		button.text = "MAX"
		button.disabled = true
		_style_action(button, false)
	elif not in_stock:
		button.text = "OUT OF STOCK"
		button.disabled = true
		_style_action(button, false)
	else:
		button.text = "UPGRADE"
		button.disabled = gold < price
		button.pressed.connect(_buy_upgrade.bind(card.uid, stat_id))
		_style_action(button, gold >= price)
	copy.add_child(button)
	_rows.add_child(tile)


func _is_basic_upgrade(card: CrawlerCard, stat_id: String) -> bool:
	if card == null or not BASIC_UPGRADE_STATS.has(stat_id):
		return false
	if card.id == "big" and stat_id == "size":
		return false
	if card.id == "reach" and stat_id == "range":
		return false
	if card.id == "homing" and stat_id == "range":
		return false
	return true


func _upgrade_blurb(
		card: CrawlerCard, stat_id: String, rank: int, cap: int,
		unlimited := false
	) -> String:
	var blurb := CrawlerRules.upgrade_stat_blurb(card.id, stat_id)
	var next_rank := rank + 1
	if cap > 0 and not unlimited:
		next_rank = mini(rank + 1, cap)
	if stat_id == "slots":
		blurb += " %d → %d." % [card.slot_count, card.slot_count + 1]
	elif card.id == "big" and stat_id == "size":
		blurb += " %s → %s." % [
			CrawlerRules.format_mul(CrawlerRules.big_size_scale(rank)),
			CrawlerRules.format_mul(CrawlerRules.big_size_scale(next_rank)),
		]
	elif card.id == "clip" and stat_id == "ammo":
		blurb += " %s → %s." % [
			CrawlerRules.format_mul(float(CrawlerRules.clip_ammo_mul(rank))),
			CrawlerRules.format_mul(float(CrawlerRules.clip_ammo_mul(next_rank))),
		]
	elif card.id == "wall" and stat_id == "house":
		blurb += " Off → On." if rank <= 0 else " On."
	elif card.id == "teleport" and stat_id == "swap":
		blurb += " Off → On." if rank <= 0 else " On."
	else:
		blurb += " Rank %d → %d." % [rank, rank + 1]
	return blurb.strip_edges()


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
	for index in _ability_slot_count():
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


func _upgrade_columns(count: int) -> int:
	if count <= 6:
		return UPGRADE_COLUMNS
	if count <= 8:
		return 4
	return 5


func _fit_upgrade_grid() -> void:
	if _rows == null or _upgrade_host == null:
		return
	var tiles: Array[Control] = []
	for child: Node in _rows.get_children():
		var tile := child as Control
		if tile != null and tile.visible:
			tiles.append(tile)
	var count := tiles.size()
	_upgrade_columns_used = _upgrade_columns(count)
	_rows.set_meta(&"columns", _upgrade_columns_used)
	var area := _upgrade_host.size
	if area.x < 8.0 or area.y < 8.0:
		return
	if count <= 0:
		return
	var columns := maxi(_upgrade_columns_used, 1)
	var rows := int(ceili(float(count) / float(columns)))
	var gap := 6.0
	var cell := Vector2(
		maxf((area.x - gap * float(maxi(columns - 1, 0))) / float(columns), 8.0),
		maxf((area.y - gap * float(maxi(rows - 1, 0))) / float(rows), 8.0)
	)
	for index in tiles.size():
		var tile := tiles[index]
		var col := index % columns
		var row := int(index / columns)
		tile.custom_minimum_size = cell
		tile.position = Vector2(
			float(col) * (cell.x + gap),
			float(row) * (cell.y + gap)
		)
		tile.size = cell
		_clamp_upgrade_tile(tile, cell)


func _clamp_upgrade_tile(tile: Control, cell: Vector2) -> void:
	tile.clip_contents = true
	var inner := Vector2(maxf(cell.x - 8.0, 8.0), maxf(cell.y - 8.0, 8.0))
	var copy := tile.get_node_or_null("UpgradeCopy") as Control
	if copy != null:
		copy.clip_contents = true
		copy.size = inner
	for child: Node in tile.find_children("UpgradeAct_*", "Button", true, false):
		var button := child as Button
		if button == null:
			continue
		button.clip_text = false
		button.clip_contents = false
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 22.0)
		button.custom_minimum_size.x = minf(
			maxf(button.custom_minimum_size.x, 64.0), inner.x)
		var host := CrtType.host_of(button)
		if host != null:
			host.clip_contents = false
			host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var host_min := Vector2(
				minf(maxf(host.custom_minimum_size.x, 64.0), inner.x),
				maxf(host.custom_minimum_size.y, 22.0)
			)
			host.custom_minimum_size = host_min
			host._adopted_min = host_min
			host.update_minimum_size()


func _request_icons() -> void:
	var menu := _store_menu()
	if menu == null:
		return
	var ids: Array = ["wobble", "big", "bubble", "linger", "clip", "endless"]
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
	box.content_margin_left = 8
	box.content_margin_top = 8
	box.content_margin_right = 8
	box.content_margin_bottom = 8
	frame.add_theme_stylebox_override(&"panel", box)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = Color.TRANSPARENT
	glow.border_color = Color(RED, 0.90)
	glow.border_width = 1.5
	glow.glow_intensity = 1.15
	glow.glow_spread = 8.0
	glow.glow_layers = 4
	return frame


func _label(
		text: String,
		font_size: int,
		colour: Color,
		wrap := false,
		lines := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.max_lines_visible = lines if lines > 0 else (2 if wrap else 1)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


func _style_action(button: Button, enabled: bool) -> void:
	var accent := GREEN if enabled else Color(RED, 0.55)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if enabled else Color(0.08, 0.02, 0.02, 0.9)
	button.clip_contents = false
	var type_size := 8 if button.text.length() > 8 else 9
	button.add_theme_font_size_override(&"font_size", type_size)
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))
	button.add_theme_stylebox_override(&"normal", _action_box(fill))
	button.add_theme_stylebox_override(&"hover", _action_box(BLACK_68))
	button.add_theme_stylebox_override(&"pressed", _action_box(Color(0.0, 0.19, 0.055, 0.90)))
	button.add_theme_stylebox_override(&"disabled", _action_box(fill))
	button.add_theme_stylebox_override(&"focus", _action_box(fill))
	_ensure_rim(button, accent, 1.25, 2.0)


func _fill_box(fill: Color, margin := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_content_margin_all(margin)
	return box


func _action_box(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _ensure_rim(
		target: Control,
		accent: Color,
		width := 2.0,
		spread := 8.0
	) -> RedGlowPanel:
	var rim := target.get_node_or_null("RedGlowPanel") as RedGlowPanel
	if rim == null:
		rim = RedGlowPanel.add_to(target)
	rim.fill_color = Color.TRANSPARENT
	rim.border_color = Color(accent, 0.95)
	rim.border_width = width
	rim.glow_intensity = 1.05
	rim.glow_spread = spread
	rim.glow_layers = 3
	return rim
