class_name CrawlerHeroPage
extends RedHeroPage

## Crawler Hero tab: three ability cards with nested modifier slots, a shared
## inventory grid, and a description of the selected card.
##
## An ability is the whole card. Dragging it moves the portrait and every
## seated modifier together. Dragging one off the page drops that same card
## into the world as a floating icon tile.

signal drop_requested(source: String, index: int, token: String)

const ROW_MIN := 110.0
const INV_EDGE := 44.0

var _kit: CrawlerKit
var _selected_token := ""
var _ability_tiles: Array[CrawlerAbilityTile] = []
var _inventory_slots: Array[RedItemSlot] = []
var _inventory_scroll: ScrollContainer
var _inventory_grid: GridContainer
var _inventory_frame: PanelContainer
var _ability_list: VBoxContainer
var _desc_title: Label
var _desc_body: Label


func configure(player: OnlinePlayer) -> void:
	_kit = player.crawler_kit if player != null else null
	super.configure(player)


func refresh() -> void:
	if _kit == null and _player != null:
		_kit = _player.crawler_kit
	super.refresh()
	_refresh_ability_rows()
	_refresh_inventory()
	_fill_crawler_description()
	_fit_description_scroll()


func _connect_sources() -> void:
	super._connect_sources()
	if _kit != null and not _kit.changed.is_connected(refresh):
		_kit.changed.connect(refresh)
	if _kit != null and _kit.inventory != null \
			and not _kit.inventory.changed.is_connected(refresh):
		_kit.inventory.changed.connect(refresh)
	if _player != null and _player.crawler_progress != null \
			and not _player.crawler_progress.changed.is_connected(refresh):
		_player.crawler_progress.changed.connect(refresh)


func _disconnect_sources() -> void:
	if _kit != null and _kit.changed.is_connected(refresh):
		_kit.changed.disconnect(refresh)
	if _kit != null and _kit.inventory != null \
			and _kit.inventory.changed.is_connected(refresh):
		_kit.inventory.changed.disconnect(refresh)
	if _player != null and _player.crawler_progress != null \
			and _player.crawler_progress.changed.is_connected(refresh):
		_player.crawler_progress.changed.disconnect(refresh)
	super._disconnect_sources()


func _fill_stats() -> void:
	var progress := _player.crawler_progress if _player != null else null
	if progress == null:
		super._fill_stats()
		return
	if _stats_rows == null:
		return
	_clear_children(_stats_rows)
	if _stats_heading != null:
		_stats_heading.text = "PLAYER STATS  //  LV %d   %dG" % [
			progress.level, progress.gold
		]
	for row_variant: Variant in progress.hero_stat_rows(_player):
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row := row_variant as Dictionary
		_add_stat_row(
			str(row.get("id", "")),
			str(row.get("title", "")),
			str(row.get("description", "")),
			str(row.get("text", ""))
		)


func _build_ability_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "CrawlerAbilityColumn"
	column.custom_minimum_size.x = 380.0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 3.0
	column.add_theme_constant_override(&"separation", 10)

	var top := HBoxContainer.new()
	top.name = "CrawlerLoadoutRow"
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.size_flags_stretch_ratio = 1.15
	top.add_theme_constant_override(&"separation", 10)
	column.add_child(top)

	var bay := CrawlerAbilityBay.new()
	bay.host = self
	_ability_list = bay
	_ability_list.name = "CrawlerAbilityRows"
	_ability_list.mouse_filter = Control.MOUSE_FILTER_STOP
	_ability_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ability_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ability_list.size_flags_stretch_ratio = 1.35
	_ability_list.add_theme_constant_override(&"separation", 8)
	for index in CrawlerRules.ABILITY_SLOTS:
		_ability_list.add_child(_build_ability_row(index))
	top.add_child(_menu_frame(_ability_list, "CrawlerAbilityFrame"))

	var desc_column := VBoxContainer.new()
	desc_column.name = "CrawlerDescriptionContent"
	desc_column.custom_minimum_size = Vector2(160.0, 120.0)
	desc_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_column.size_flags_stretch_ratio = 0.72
	desc_column.add_theme_constant_override(&"separation", 6)
	_desc_title = _label("DESCRIPTION", 14, RED_BRIGHT, true)
	_desc_title.name = "CrawlerDescriptionTitle"
	desc_column.add_child(_desc_title)
	_desc_body = _label(
		"CLICK AN ABILITY OR MODIFIER TO READ IT.",
		11,
		RED_TEXT,
		true
	)
	_desc_body.name = "CrawlerDescriptionBody"
	desc_column.add_child(_scroll_text(_desc_body, "CrawlerDescriptionScroll"))
	top.add_child(_menu_frame(desc_column, "CrawlerDescriptionFrame"))

	var inventory_column := VBoxContainer.new()
	inventory_column.name = "CrawlerInventoryContent"
	inventory_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_column.add_theme_constant_override(&"separation", 6)
	_inventory_scroll = ScrollContainer.new()
	_inventory_scroll.name = "CrawlerInventoryScroll"
	_inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inventory_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_inventory_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_scroll.custom_minimum_size.y = INV_EDGE + 4.0
	_inventory_scroll.clip_contents = true
	_inventory_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_column.add_child(_inventory_scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.name = "CrawlerInventorySlots"
	_inventory_grid.columns = CrawlerRules.INVENTORY_COLUMNS
	_inventory_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_grid.add_theme_constant_override(&"h_separation", 4)
	_inventory_grid.add_theme_constant_override(&"v_separation", 4)
	_inventory_scroll.add_child(_inventory_grid)
	_inventory_scroll.resized.connect(_fit_inventory_columns)
	_inventory_frame = _menu_frame(inventory_column, "CrawlerInventoryFrame")
	_inventory_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inventory_frame.clip_contents = true
	column.add_child(_inventory_frame)

	_description_title = _desc_title
	_description_body = _desc_body
	_build_inventory_slots()
	return column


func _build_ability_row(index: int) -> CrawlerAbilityTile:
	var tile := CrawlerAbilityTile.new()
	tile.name = "CrawlerAbilityTile_%d" % index
	tile.custom_minimum_size.y = ROW_MIN
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.setup(index, _kit)
	tile.picked.connect(_on_ability_picked)
	tile.drop_requested.connect(_on_ability_world_drop)
	tile.card_received.connect(_on_ability_received)
	tile.mod_picked.connect(_on_mod_picked)
	tile.mod_moved.connect(_on_mod_moved)
	tile.mod_drop_requested.connect(_on_mod_world_drop)
	tile.clear_requested.connect(_on_clear_pressed)
	_ability_tiles.append(tile)
	return tile


func _build_inventory_slots() -> void:
	if _inventory_grid == null or _kit == null:
		return
	_clear_children(_inventory_grid)
	_inventory_slots.clear()
	for index in CrawlerRules.INVENTORY_SLOTS:
		var slot := RedItemSlot.new()
		slot.name = "CrawlerBag_%d" % index
		slot.set_edge(INV_EDGE)
		slot.placeholder = ""
		slot.bind(_kit.inventory, index)
		slot.picked.connect(_on_inventory_picked)
		slot.item_dropped.connect(_on_inventory_moved)
		slot.crawler_move_dropped.connect(_on_inventory_received_ability)
		slot.drag_released.connect(_on_inventory_drag_released.bind(
			CrawlerKit.SOURCE_BAG, index))
		_inventory_grid.add_child(slot)
		_inventory_slots.append(slot)


func _bind_slots() -> void:
	if _hat_slot != null:
		_hat_slot.bind(_equipment, 0)
	_bind_crawler_slots()


func _bind_hotbar_slots() -> void:
	_bind_crawler_slots()


func _bind_crawler_slots() -> void:
	if _kit == null:
		return
	for index in _ability_tiles.size():
		_ability_tiles[index].setup(index, _kit)
	if _inventory_slots.is_empty():
		_build_inventory_slots()
	else:
		for index in _inventory_slots.size():
			_inventory_slots[index].bind(_kit.inventory, index)


func _refresh_hotbar() -> void:
	_refresh_ability_rows()


func _refresh_library() -> void:
	_refresh_inventory()


func _rebuild_library() -> void:
	_refresh_inventory()


func _refresh_ability_rows() -> void:
	for tile: CrawlerAbilityTile in _ability_tiles:
		tile.selected = not _selected_token.is_empty() \
			and tile.token() == _selected_token
		tile.refresh()
	_paint_mod_selection()


func _refresh_inventory() -> void:
	if _inventory_slots.is_empty():
		_build_inventory_slots()
		return
	for slot: RedItemSlot in _inventory_slots:
		var token := slot.item_id()
		slot.selected = token == _selected_token and not token.is_empty()
		slot.queue_redraw()


func _paint_selection() -> void:
	for tile: CrawlerAbilityTile in _ability_tiles:
		tile.selected = not _selected_token.is_empty() \
			and tile.token() == _selected_token
	_paint_mod_selection()
	_refresh_inventory()
	_fill_crawler_description()


func _paint_mod_selection() -> void:
	for tile: CrawlerAbilityTile in _ability_tiles:
		for slot: RedItemSlot in tile.mod_slots():
			var token := slot.item_id()
			slot.selected = token == _selected_token and not token.is_empty()
			slot.queue_redraw()


func _fill_description() -> void:
	_fill_crawler_description()


func _fill_crawler_description() -> void:
	if _desc_title == null:
		return
	if _selected_token.is_empty() or _kit == null:
		_desc_title.text = "DESCRIPTION"
		_desc_body.text = "CLICK AN ABILITY OR MODIFIER TO READ IT."
		_fit_description_scroll()
		return
	var card := _kit.card_for_token(_selected_token)
	var id := card.id if card != null else CrawlerCatalog.catalog_id(_selected_token)
	_desc_title.text = ItemDB.title(id).to_upper()
	var lines: PackedStringArray = []
	var host := _kit.host_ability_for(_selected_token)
	var host_id := host.id if host != null else ""
	var size_rank := card.upgrade_rank("size") if card != null and card.id == "big" else -1
	var description := ItemDB.description(id, host_id, size_rank).strip_edges()
	if description.is_empty():
		description = CrawlerCatalog.description_of(id, host_id, size_rank)
	lines.append(description if not description.is_empty() else "NO DESCRIPTION FILED.")
	if card != null and card.is_ability():
		lines.append("SLOTS  //  %d" % card.slot_count)
		var seated := card.filled_modifier_ids()
		if not seated.is_empty():
			var names := PackedStringArray()
			for modifier_id: String in seated:
				names.append(ItemDB.title(modifier_id))
			lines.append("MODS  //  %s" % ", ".join(names))
		var written := PackedStringArray()
		for line: String in _stat_lines_for(card):
			written.append(line.replace("\t", "  //  "))
		if not written.is_empty():
			lines.append("STATS\n%s" % "\n".join(written))
	elif CrawlerCatalog.is_modifier(id):
		if card != null:
			var ranks := {}
			for stat_id: String in CrawlerRules.upgrade_stats_for(card.id):
				ranks[stat_id] = _kit.upgrade_rank_for(card, stat_id)
			for line: String in CrawlerRules.mod_progress_lines(
					card.id, _kit.shop_rank_for(card), ranks):
				lines.append(line)
		lines.append("SCOPE  //  %s" % CrawlerCatalog.scope_of(id).replace("_", " "))
		if id != "big":
			var effects := CrawlerCatalog.effects_for(id, "laser_eyes")
			var extra: PackedStringArray = []
			for row: Dictionary in effects:
				extra.append("%s %s %s" % [
					str(row.get("stat", "")),
					str(row.get("op", "")),
					str(row.get("value", "")),
				])
			if not extra.is_empty():
				lines.append("LASER EYES  //  %s" % "   |   ".join(extra))
			if CrawlerCatalog.scope_of(id) == "generic":
				var punch_effects := CrawlerCatalog.effects_for(id, "meteor_punch")
				var punch_lines: PackedStringArray = []
				for row: Dictionary in punch_effects:
					punch_lines.append("%s %s %s" % [
						str(row.get("stat", "")),
						str(row.get("op", "")),
						str(row.get("value", "")),
					])
				if not punch_lines.is_empty():
					lines.append("METEOR PUNCH  //  %s" % "   |   ".join(punch_lines))
				var nuke_effects := CrawlerCatalog.effects_for(id, "nuke")
				var nuke_lines: PackedStringArray = []
				for row: Dictionary in nuke_effects:
					nuke_lines.append("%s %s %s" % [
						str(row.get("stat", "")),
						str(row.get("op", "")),
						str(row.get("value", "")),
					])
				if not nuke_lines.is_empty():
					lines.append("NUKE  //  %s" % "   |   ".join(nuke_lines))
	_desc_body.text = "\n\n".join(lines)
	_fit_description_scroll()


func _stat_lines_for(card: CrawlerCard) -> PackedStringArray:
	if card == null:
		return PackedStringArray()
	var stats := _kit.stats_for(card) if _kit != null else {}
	var base := _kit.base_stats_for(card) if _kit != null else {}
	var wanted := CrawlerRules.display_stats_for(card.id)
	if wanted.is_empty():
		return ItemDB.stat_lines_from(stats, base)
	var shown := {}
	var shown_base := {}
	for key: String in wanted:
		if stats.has(key):
			shown[key] = stats[key]
		if base.has(key):
			shown_base[key] = base[key]
	return ItemDB.stat_lines_from(shown, shown_base)


func select_token(token: String) -> void:
	_selected_token = token
	_paint_selection()


func _on_ability_picked(tile: CrawlerAbilityTile) -> void:
	if tile == null:
		return
	select_token(tile.token())


func _on_mod_picked(slot: RedItemSlot) -> void:
	_selected_token = slot.item_id() if slot != null else ""
	_paint_selection()


func _on_inventory_picked(slot: RedItemSlot) -> void:
	_selected_token = slot.item_id() if slot != null else ""
	_paint_selection()


func _on_mod_moved(_target: RedItemSlot, source: RedItemSlot) -> void:
	if source != null:
		_selected_token = source.item_id()
	refresh()


func _on_inventory_moved(_target: RedItemSlot, source: RedItemSlot) -> void:
	if source != null:
		_selected_token = source.item_id()
	refresh()


func _on_ability_received(tile: CrawlerAbilityTile, data: Dictionary) -> void:
	if _kit == null or tile == null:
		return
	if bool(data.get("crawler_move", false)):
		_kit.move_card(
			str(data.get("source", "")),
			int(data.get("index", -1)),
			CrawlerKit.SOURCE_EQUIP,
			tile.index
		)
		_selected_token = str(data.get("token", tile.token()))
		refresh()
		return
	var from := data.get("red_item_slot") as RedItemSlot
	if from == null:
		return
	var located := _source_of_slot(from)
	if located.is_empty():
		return
	_kit.move_card(
		str(located.get("source", "")),
		int(located.get("index", -1)),
		CrawlerKit.SOURCE_EQUIP,
		tile.index
	)
	_selected_token = from.item_id()
	refresh()


func _on_inventory_received_ability(target: RedItemSlot, data: Dictionary) -> void:
	if _kit == null or target == null:
		return
	_kit.move_card(
		str(data.get("source", "")),
		int(data.get("index", -1)),
		CrawlerKit.SOURCE_BAG,
		target.index
	)
	_selected_token = str(data.get("token", target.item_id()))
	refresh()


func _on_ability_world_drop(tile: CrawlerAbilityTile) -> void:
	if tile == null or not _should_world_drop():
		return
	var token := tile.token()
	if token.is_empty():
		return
	drop_requested.emit(CrawlerKit.SOURCE_EQUIP, tile.index, token)


func _on_mod_world_drop(slot: RedItemSlot) -> void:
	if slot == null or not _should_world_drop():
		return
	var located := _source_of_slot(slot)
	var token := slot.item_id()
	if located.is_empty() or token.is_empty():
		return
	drop_requested.emit(
		str(located.get("source", "")),
		int(located.get("index", -1)),
		token
	)


func _on_inventory_drag_released(
		source: String,
		index: int,
		slot: RedItemSlot,
		dropped: bool
	) -> void:
	if dropped or slot == null or not _should_world_drop():
		return
	var token := _kit.token_at(source, index) if _kit != null else slot.item_id()
	if token.is_empty():
		return
	drop_requested.emit(source, index, token)


func _should_world_drop() -> bool:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_is_drag_successful():
		return false
	var hovered := viewport.gui_get_hovered_control() if viewport != null else null
	return not _is_internal_drop_target(hovered)


func _is_internal_drop_target(node: Node) -> bool:
	while node != null:
		if node is CrawlerAbilityTile or node is RedItemSlot \
				or node == _ability_list or node == _inventory_scroll \
				or node == _inventory_grid:
			return true
		node = node.get_parent()
	return false


func first_empty_equip() -> int:
	if _kit == null or _kit.player == null or not is_instance_valid(_kit.player) \
			or _kit.player.abilities == null:
		return -1
	for index in _kit.player.abilities.size():
		if _kit.player.abilities.get_item(index).is_empty():
			return index
	return -1


func seat_incoming_ability(data: Dictionary) -> void:
	var dest := first_empty_equip()
	if dest < 0 or dest >= _ability_tiles.size():
		return
	_on_ability_received(_ability_tiles[dest], data)


func _source_of_slot(slot: RedItemSlot) -> Dictionary:
	if slot == null or _kit == null:
		return {}
	if slot.container == _kit.inventory:
		return {"source": CrawlerKit.SOURCE_BAG, "index": slot.index}
	for tile_index in _ability_tiles.size():
		var rack := _kit.mod_rack(tile_index)
		if slot.container == rack:
			return {
				"source": CrawlerKit.SOURCE_MOD,
				"index": _kit.encode_mod_index(tile_index, slot.index),
			}
	return {}


func _on_clear_pressed(index: int) -> void:
	if _kit == null:
		return
	var token := _kit.token_at(CrawlerKit.SOURCE_EQUIP, index)
	if token.is_empty():
		return
	drop_requested.emit(CrawlerKit.SOURCE_EQUIP, index, token)


func _request_icons() -> void:
	if _icons == null:
		return
	var ids: Array = []
	for id: String in ItemDB.ability_ids():
		ids.append(id)
	for id: String in ["wobble", "big"]:
		ids.append(id)
	if _kit != null:
		for card: CrawlerCard in _kit.cards.values():
			if card != null and not ids.has(card.id):
				ids.append(card.id)
	_icons.request(ids)


func _on_icon_ready(_id: String, _texture: Texture2D) -> void:
	super._on_icon_ready(_id, _texture)
	for tile: CrawlerAbilityTile in _ability_tiles:
		tile.refresh()
	for slot: RedItemSlot in _inventory_slots:
		slot.queue_redraw()


func _update_responsive_layout() -> void:
	super._update_responsive_layout()
	_fit_inventory_columns()


func _fit_inventory_columns() -> void:
	if _inventory_grid == null or _inventory_scroll == null:
		return
	var available := _inventory_scroll.size.x - 8.0
	if available <= 0.0:
		return
	var gap := 4.0
	_inventory_grid.columns = clampi(
		int((available + gap) / (INV_EDGE + gap)),
		1,
		CrawlerRules.INVENTORY_COLUMNS
	)


func _menu_frame(content: Control, node_name: String) -> PanelContainer:
	var frame := _glow_frame(content, node_name, 10.0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return frame
