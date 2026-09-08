class_name CrawlerStoreInventoryPage
extends VBoxContainer

## City-store stash. The top pane is the live loadout. The bottom pane is the
## same ability row and bag, saved on the run kit so every city this run can
## pull from it. Dragging a card here takes it out of the player's inventory.

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const BLACK_40_PANEL := Color(0.0, 0.0, 0.0, 0.40)
const INV_EDGE := 36.0
const TILE_MIN := 78.0

var _player: OnlinePlayer
var _kit: CrawlerKit
var _player_tiles: Array[CrawlerAbilityTile] = []
var _city_tiles: Array[CrawlerAbilityTile] = []
var _player_row: HBoxContainer
var _city_row: HBoxContainer
var _player_slots: Array[RedItemSlot] = []
var _city_slots: Array[RedItemSlot] = []
var _player_grid: GridContainer
var _city_grid: GridContainer


func configure(player: OnlinePlayer) -> void:
	_player = player
	_kit = player.crawler_kit if player != null else null


func _ready() -> void:
	name = "StoreInventoryPage"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 10)
	_build()
	refresh()
	_request_icons()


func refresh() -> void:
	if _kit == null and _player != null:
		_kit = _player.crawler_kit
	_refresh_row(_player_tiles, _player_row, CrawlerKit.SOURCE_EQUIP, "CrawlerAbilityTile")
	_refresh_row(_city_tiles, _city_row, CrawlerKit.SOURCE_CITY_EQUIP, "CityAbilityTile")
	_bind_bag(_player_slots, _player_grid, _kit.inventory if _kit != null else null, "CrawlerBag")
	_bind_bag(_city_slots, _city_grid, _kit.city_inventory if _kit != null else null, "CityBag")
	_request_icons()


func notify_icon_ready() -> void:
	for tile: CrawlerAbilityTile in _player_tiles:
		if tile != null:
			tile.refresh()
	for tile: CrawlerAbilityTile in _city_tiles:
		if tile != null:
			tile.refresh()
	for slot: RedItemSlot in _player_slots:
		if slot != null:
			slot.queue_redraw()
	for slot: RedItemSlot in _city_slots:
		if slot != null:
			slot.queue_redraw()


func _build() -> void:
	add_child(_make_pane(
		"YOU",
		"StorePlayerLoadout",
		true
	))
	add_child(_make_pane(
		"CITY",
		"StoreCityLoadout",
		false
	))


func _make_pane(caption: String, pane_name: String, player_side: bool) -> PanelContainer:
	var frame := _pane(pane_name)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 6)
	frame.add_child(body)
	var title := Label.new()
	title.text = caption
	title.add_theme_font_size_override(&"font_size", 12)
	title.add_theme_color_override(&"font_color", RED_BRIGHT)
	body.add_child(title)
	var ability_scroll := ScrollContainer.new()
	ability_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ability_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ability_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ability_scroll.custom_minimum_size.y = TILE_MIN + 8.0
	ability_scroll.clip_contents = true
	body.add_child(ability_scroll)
	var abilities := HBoxContainer.new()
	abilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abilities.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	abilities.custom_minimum_size.y = TILE_MIN
	abilities.add_theme_constant_override(&"separation", 6)
	ability_scroll.add_child(abilities)
	var source := CrawlerKit.SOURCE_EQUIP if player_side else CrawlerKit.SOURCE_CITY_EQUIP
	var tile_name := "CrawlerAbilityTile" if player_side else "CityAbilityTile"
	if player_side:
		_player_row = abilities
	else:
		_city_row = abilities
	for index in _ability_slot_count():
		abilities.add_child(_make_ability_tile(index, source, "%s_%d" % [tile_name, index]))
	var inventory_row := HBoxContainer.new()
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
	body.add_child(inventory_row)
	var lead := Control.new()
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_row.add_child(lead)
	var grid := GridContainer.new()
	grid.columns = CrawlerRules.INVENTORY_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	inventory_row.add_child(grid)
	var trail := Control.new()
	trail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_row.add_child(trail)
	var bag_name := "CrawlerBag" if player_side else "CityBag"
	var bag := _kit.inventory if player_side and _kit != null \
		else _kit.city_inventory if _kit != null else null
	if player_side:
		_player_grid = grid
		_fill_bag_slots(_player_slots, grid, bag, bag_name)
	else:
		_city_grid = grid
		_fill_bag_slots(_city_slots, grid, bag, bag_name)
	return frame


func _make_ability_tile(index: int, source: String, node_name: String) -> CrawlerAbilityTile:
	var tile := CrawlerAbilityTile.new()
	tile.name = node_name
	tile.source = source
	tile.editable = true
	tile.show_clear = false
	tile.compact = true
	tile.custom_minimum_size.y = TILE_MIN
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.setup(index, _kit, source)
	tile.card_received.connect(_on_ability_received)
	if source == CrawlerKit.SOURCE_EQUIP:
		_player_tiles.append(tile)
	else:
		_city_tiles.append(tile)
	return tile


func _fill_bag_slots(
		slots: Array[RedItemSlot],
		grid: GridContainer,
		bag: ItemContainer,
		prefix: String
	) -> void:
	if grid == null:
		return
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	slots.clear()
	for index in CrawlerRules.INVENTORY_SLOTS:
		var slot := RedItemSlot.new()
		slot.name = "%s_%d" % [prefix, index]
		slot.set_edge(INV_EDGE)
		slot.placeholder = ""
		slot.use_soft_fx()
		slot.bind(bag, index)
		slot.item_dropped.connect(_on_bag_moved)
		slot.crawler_move_dropped.connect(_on_bag_received_ability)
		grid.add_child(slot)
		slots.append(slot)


func _refresh_row(
		tiles: Array[CrawlerAbilityTile],
		row: HBoxContainer,
		source: String,
		prefix: String
	) -> void:
	if row == null:
		return
	var wanted := _ability_slot_count()
	while tiles.size() < wanted:
		row.add_child(_make_ability_tile(tiles.size(), source, "%s_%d" % [prefix, tiles.size()]))
	while tiles.size() > wanted:
		var tile: CrawlerAbilityTile = tiles.pop_back()
		if tile != null:
			tile.queue_free()
	for tile: CrawlerAbilityTile in tiles:
		tile.setup(tile.index, _kit, source)
		tile.refresh()


func _bind_bag(
		slots: Array[RedItemSlot],
		grid: GridContainer,
		bag: ItemContainer,
		prefix: String
	) -> void:
	if slots.is_empty():
		_fill_bag_slots(slots, grid, bag, prefix)
		return
	for index in slots.size():
		slots[index].bind(bag, index)
		slots[index].queue_redraw()


func _ability_slot_count() -> int:
	if _kit != null:
		var bar := _kit.ability_bar()
		if bar != null:
			return bar.size()
	if _player != null and _player.abilities != null:
		return _player.abilities.size()
	return CrawlerRules.ABILITY_SLOTS


func _on_ability_received(tile: CrawlerAbilityTile, data: Dictionary) -> void:
	if tile == null:
		return
	if bool(data.get("crawler_move", false)):
		_hand_off_payload(data, _kit, tile.source, tile.index)
		return
	var from := data.get("red_item_slot") as RedItemSlot
	if from == null:
		return
	var located := _source_of_slot(from)
	if located.is_empty():
		return
	_hand_off(
		_kit,
		str(located.get("source", "")),
		int(located.get("index", -1)),
		_kit,
		tile.source,
		tile.index
	)


func _on_bag_received_ability(target: RedItemSlot, data: Dictionary) -> void:
	if target == null:
		return
	var dest := _source_of_slot(target)
	if dest.is_empty():
		return
	_hand_off_payload(data, _kit, str(dest.get("source", "")), int(dest.get("index", -1)))


func _on_bag_moved(_target: RedItemSlot, _source: RedItemSlot) -> void:
	refresh()


func _hand_off_payload(
		data: Dictionary,
		to_kit: CrawlerKit,
		to_source: String,
		to_index: int
	) -> void:
	var from_kit := data.get("kit") as CrawlerKit
	if from_kit == null:
		from_kit = _kit
	_hand_off(
		from_kit,
		str(data.get("source", "")),
		int(data.get("index", -1)),
		to_kit,
		to_source,
		to_index
	)


func _hand_off(
		from_kit: CrawlerKit,
		from_source: String,
		from_index: int,
		to_kit: CrawlerKit,
		to_source: String,
		to_index: int
	) -> void:
	CrawlerKit.hand_off(from_kit, from_source, from_index, to_kit, to_source, to_index)
	refresh()


func _source_of_slot(slot: RedItemSlot) -> Dictionary:
	if slot == null or _kit == null:
		return {}
	if slot.container == _kit.inventory:
		return {"source": CrawlerKit.SOURCE_BAG, "index": slot.index}
	if slot.container == _kit.city_inventory:
		return {"source": CrawlerKit.SOURCE_CITY_BAG, "index": slot.index}
	for tile_index in _ability_slot_count():
		if slot.container == _kit.mod_rack(tile_index):
			return {
				"source": CrawlerKit.SOURCE_MOD,
				"index": _kit.encode_mod_index(tile_index, slot.index),
			}
		if slot.container == _kit.city_mod_rack(tile_index):
			return {
				"source": CrawlerKit.SOURCE_CITY_MOD,
				"index": _kit.encode_mod_index(tile_index, slot.index),
			}
	return {}


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


func _store_menu() -> CrawlerFieldMenu:
	var node: Node = get_parent()
	while node != null:
		if node is CrawlerFieldMenu:
			return node as CrawlerFieldMenu
		node = node.get_parent()
	return null


func _pane(node_name: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK_40_PANEL
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
