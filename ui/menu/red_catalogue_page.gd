class_name RedCataloguePage
extends VBoxContainer

## Finite, live loadout catalogue for the red in-game menu.
##
## Call [method configure] before adding the page to the tree. Physical entries
## always point at their real [ItemContainer] slot. Apparel also lists every
## garment that fits the current body, the same way abilities list known powers,
## so a hat can be worn without first living in the backpack. A world drop still
## never removes an item here.

signal drop_requested(source: String, index: int, item_id: String)

enum Mode {
	APPAREL,
	ITEMS,
	ABILITIES,
}

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_62 := Color(0.0, 0.0, 0.0, 0.62)
const BLACK_76 := Color(0.0, 0.0, 0.0, 0.76)

const SOURCE_EQUIPMENT := "equipment"
const SOURCE_BACKPACK := "backpack"
const SOURCE_HOTBAR := "hotbar"
const SOURCE_ABILITIES := "abilities"
const SOURCE_KNOWN := "known"
const SOURCE_WARDROBE := "wardrobe"

const NARROW_WIDTH := 780.0
const TILE_EDGE := 82.0
const TILE_GAP := 8.0
const CATALOGUE_MIN_WIDTH := 390.0
const DETAIL_MIN_WIDTH := 330.0
const CATALOGUE_NARROW_HEIGHT := 280.0
const DETAIL_NARROW_HEIGHT := 390.0

const APPAREL_FILTERS := [
	{"id": "", "label": "All", "glyph": RedMenuGlyph.Glyph.APPAREL_ALL},
	{"id": "hat", "label": "Head", "glyph": RedMenuGlyph.Glyph.HAT},
	{"id": "goggles", "label": "Eyes", "glyph": RedMenuGlyph.Glyph.GOGGLES},
	{"id": "long_sleeve", "label": "Body", "glyph": RedMenuGlyph.Glyph.BODY_TUNIC},
	{"id": "pants", "label": "Legs", "glyph": RedMenuGlyph.Glyph.PANTS},
	{"id": "shoes", "label": "Feet", "glyph": RedMenuGlyph.Glyph.BOOTS},
]
const ITEM_FILTERS := [
	{"id": ItemDB.KIND_WEAPON, "label": "Weapons", "glyph": RedMenuGlyph.Glyph.WEAPONS},
	{"id": ItemDB.KIND_ITEM, "label": "Items", "glyph": RedMenuGlyph.Glyph.ITEMS},
]

var _player: OnlinePlayer
var _mode: Mode = Mode.APPAREL
var _equipment: ItemContainer
var _hotbar: ItemContainer
var _abilities: ItemContainer
var _backpack: ItemContainer

var _built := false
var _filter := ""
var _selected_id := ""
var _selected_source := ""
var _selected_index := -1
var _target_index := 0
var _feedback := ""
var _visible_entries: Array[Dictionary] = []
var _ability_library: ItemContainer
var _wardrobe: ItemContainer

var _header_title: Label
var _header_count: Label
var _filter_row: HBoxContainer
var _content_grid: GridContainer
var _catalogue_frame: PanelContainer
var _catalogue_scroll: ScrollContainer
var _item_grid: GridContainer
var _empty_state: CenterContainer
var _empty_glyph: RedMenuGlyph
var _empty_title: Label
var _empty_body: Label
var _detail_frame: PanelContainer
var _detail: VBoxContainer
var _detail_footer: VBoxContainer
var _detail_icon: TextureRect
var _detail_fallback: RedMenuGlyph
var _equip_action: HoldActionButton
var _drop_action: Button
var _target_buttons: Array[Button] = []
var _icons: ItemIcons
var _narrow := false
var _responsive_initialized := false


## Supplies the live owner and the kind of finite inventory to display.
func configure(player: OnlinePlayer, mode: Mode) -> void:
	_disconnect_sources()
	_player = player
	_mode = mode
	_filter = ""
	_selected_id = ""
	_selected_source = ""
	_selected_index = -1
	_target_index = -1 if _mode == Mode.APPAREL else 0
	_feedback = ""
	_capture_sources()
	if is_inside_tree():
		_connect_sources()
	if not _built:
		return
	_fill_filters()
	refresh()


## Re-reads all relevant containers, preserving the selected id when it moved.
func refresh() -> void:
	if not _built:
		return
	var all_entries := _collect_entries()
	_visible_entries.clear()
	for entry: Dictionary in all_entries:
		if _matches_filter(entry):
			_visible_entries.append(entry)
	_resolve_selection()
	_update_header(all_entries.size())
	_fill_catalogue()
	_fill_detail()
	_request_icons(all_entries)
	call_deferred(&"_fit_catalogue_columns")


## Item id currently driving the persistent detail panel.
func selected_item_id() -> String:
	return _selected_id


## Active filter id. An empty string means All.
func selected_filter() -> String:
	return _filter


## Zero-based equipment, numbered-hotbar, or ability target index.
func target_slot() -> int:
	return _target_index


func _init() -> void:
	name = "RedCataloguePage"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(360.0, 420.0)


func _get_minimum_size() -> Vector2:
	return custom_minimum_size


func _enter_tree() -> void:
	_connect_sources()


func _ready() -> void:
	add_theme_constant_override(&"separation", 10)
	_build()
	_built = true
	_fill_filters()
	refresh()
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	call_deferred(&"_update_responsive_layout")


func _exit_tree() -> void:
	_disconnect_sources()


func _capture_sources() -> void:
	if _player == null:
		_equipment = null
		_hotbar = null
		_abilities = null
		_backpack = null
		return
	_equipment = _player.equipment
	_hotbar = _player.get("hotbar") as ItemContainer
	if _hotbar == null:
		_hotbar = _player.weapons
	_abilities = _player.get("abilities") as ItemContainer
	_backpack = _player.backpack


func _sources() -> Array[ItemContainer]:
	var sources: Array[ItemContainer] = []
	for source: ItemContainer in [_equipment, _hotbar, _abilities, _backpack]:
		if source != null and not sources.has(source):
			sources.append(source)
	return sources


func _connect_sources() -> void:
	for source: ItemContainer in _sources():
		if not source.changed.is_connected(refresh):
			source.changed.connect(refresh)


func _disconnect_sources() -> void:
	for source: ItemContainer in _sources():
		if source.changed.is_connected(refresh):
			source.changed.disconnect(refresh)


func _build() -> void:
	add_child(_build_header())
	add_child(_build_filter_bar())
	add_child(_build_content())

	_icons = ItemIcons.new()
	_icons.name = "ItemIcons"
	add_child(_icons)
	_icons.icon_ready.connect(_on_icon_ready)


func _build_header() -> PanelContainer:
	var row := HBoxContainer.new()
	row.name = "CatalogueHeaderContent"
	row.add_theme_constant_override(&"separation", 12)

	_header_title = _label("ALL APPAREL", 22, RED_BRIGHT)
	_header_title.name = "CatalogueHeading"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_header_title)

	_header_count = _label("00 OWNED", 11, RED_MUTED)
	_header_count.name = "CatalogueCount"
	_header_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_header_count)
	return _glow_frame(row, "CatalogueHeader", 11.0)


func _build_filter_bar() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "FilterContent"
	column.add_theme_constant_override(&"separation", 5)
	column.add_child(_label("FILTER // ACTIVE FILTER CLEARS TO ALL", 10, RED_MUTED))

	var scroll := ScrollContainer.new()
	scroll.name = "FilterScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 52.0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_filter_row = HBoxContainer.new()
	_filter_row.name = "CatalogueFilters"
	_filter_row.add_theme_constant_override(&"separation", 7)
	_filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_filter_row)
	return _glow_frame(column, "CatalogueFilterFrame", 8.0)


func _build_content() -> GridContainer:
	_content_grid = GridContainer.new()
	_content_grid.name = "CatalogueDetailSplit"
	_content_grid.columns = 2
	_content_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_grid.add_theme_constant_override(&"h_separation", 12)
	_content_grid.add_theme_constant_override(&"v_separation", 12)

	_catalogue_frame = _build_catalogue_frame()
	_catalogue_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalogue_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_catalogue_frame.size_flags_stretch_ratio = 0.58
	_content_grid.add_child(_catalogue_frame)

	_detail_frame = _build_detail_frame()
	_detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_frame.size_flags_stretch_ratio = 0.42
	_content_grid.add_child(_detail_frame)
	return _content_grid


func _build_catalogue_frame() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "CatalogueContent"
	column.add_theme_constant_override(&"separation", 8)

	var hint := _label("CLICK TO INSPECT  //  SHIFT+CLICK TO QUICK EQUIP", 10, RED_MUTED)
	hint.name = "CatalogueHint"
	column.add_child(hint)
	column.add_child(_rule())

	_catalogue_scroll = ScrollContainer.new()
	_catalogue_scroll.name = "OwnedItemScroll"
	_catalogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_catalogue_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_catalogue_scroll)

	_item_grid = GridContainer.new()
	_item_grid.name = "OwnedItemGrid"
	_item_grid.columns = 4
	_item_grid.add_theme_constant_override(&"h_separation", int(TILE_GAP))
	_item_grid.add_theme_constant_override(&"v_separation", int(TILE_GAP))
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalogue_scroll.add_child(_item_grid)
	_item_grid.resized.connect(_fit_catalogue_columns)

	_empty_state = CenterContainer.new()
	_empty_state.name = "CatalogueEmptyState"
	_empty_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_empty_state)

	var empty_column := VBoxContainer.new()
	empty_column.custom_minimum_size = Vector2(220.0, 220.0)
	empty_column.alignment = BoxContainer.ALIGNMENT_CENTER
	empty_column.add_theme_constant_override(&"separation", 8)
	_empty_state.add_child(empty_column)

	var glyph_center := CenterContainer.new()
	_empty_glyph = RedMenuGlyph.new()
	_empty_glyph.name = "EmptyStateGlyph"
	_empty_glyph.custom_minimum_size = Vector2(88.0, 88.0)
	glyph_center.add_child(_empty_glyph)
	empty_column.add_child(glyph_center)

	_empty_title = _label("NO OWNED APPAREL", 18, GREEN)
	_empty_title.name = "EmptyStateTitle"
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_column.add_child(_empty_title)

	_empty_body = _label("OWNED ENTRIES WILL APPEAR HERE.", 11, RED_MUTED, true)
	_empty_body.name = "EmptyStateBody"
	_empty_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_column.add_child(_empty_body)

	return _glow_frame(column, "OwnedCatalogueFrame", 10.0)


func _build_detail_frame() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "PersistentDetailLayout"
	column.add_theme_constant_override(&"separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.name = "PersistentDetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_detail = VBoxContainer.new()
	_detail.name = "PersistentItemDetail"
	_detail.add_theme_constant_override(&"separation", 7)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)

	# Assignment and destructive actions remain visible while the record above
	# scrolls. A selected item must never hide its primary controls below the
	# 1280x720 fold.
	_detail_footer = VBoxContainer.new()
	_detail_footer.name = "PersistentDetailActions"
	_detail_footer.add_theme_constant_override(&"separation", 7)
	_detail_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_detail_footer)
	return _glow_frame(column, "PersistentDetailFrame", 12.0)


func _fill_filters() -> void:
	if _filter_row == null:
		return
	_clear_children(_filter_row)
	var definitions: Array = []
	match _mode:
		Mode.APPAREL:
			definitions = APPAREL_FILTERS
		Mode.ITEMS:
			definitions = ITEM_FILTERS
		Mode.ABILITIES:
			var notice := _label("ABILITIES  //  LMB + RMB ASSIGNMENT", 12, GREEN_TEXT)
			notice.name = "AbilityFilterNotice"
			notice.custom_minimum_size = Vector2(300.0, 46.0)
			notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_filter_row.add_child(notice)
			return

	for definition: Dictionary in definitions:
		var id := String(definition["id"])
		var label_text := String(definition["label"])
		var glyph := int(definition["glyph"]) as RedMenuGlyph.Glyph
		var button := _filter_button(label_text, glyph, id == _filter)
		button.name = "Filter_%s" % ("All" if id.is_empty() else id)
		var chosen := id
		button.pressed.connect(func() -> void: _pick_filter(chosen))
		_filter_row.add_child(button)


func _filter_button(
	label_text: String,
	glyph_kind: RedMenuGlyph.Glyph,
	active: bool
) -> Button:
	var button := Button.new()
	button.text = label_text.to_upper()
	button.custom_minimum_size = Vector2(116.0, 46.0)
	button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(button, active)
	_reserve_icon_lane(button, 46.0)

	var glyph_lane := CenterContainer.new()
	glyph_lane.name = "GlyphLane"
	glyph_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_lane.anchor_right = 0.0
	glyph_lane.anchor_bottom = 1.0
	glyph_lane.offset_right = 42.0
	button.add_child(glyph_lane)

	var glyph := RedMenuGlyph.new()
	glyph.name = "Glyph"
	glyph.glyph = glyph_kind
	glyph.custom_minimum_size = Vector2(30.0, 30.0)
	glyph_lane.add_child(glyph)
	return button


func _pick_filter(id: String) -> void:
	_filter = "" if _filter == id else id
	_feedback = ""
	_fill_filters()
	refresh()


func _collect_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _player == null:
		return entries
	match _mode:
		Mode.APPAREL:
			var allowed := CharacterDB.apparel_ids(_player.body_id())
			_append_apparel(entries, _equipment, SOURCE_EQUIPMENT, allowed)
			_append_apparel(entries, _backpack, SOURCE_BACKPACK, allowed)
			_append_wardrobe(entries, allowed)
		Mode.ITEMS:
			_append_numbered_items(entries, _hotbar, SOURCE_HOTBAR)
			_append_numbered_items(entries, _backpack, SOURCE_BACKPACK)
		Mode.ABILITIES:
			_append_abilities(entries)
	return entries


func _append_apparel(
	entries: Array[Dictionary],
	container: ItemContainer,
	source: String,
	allowed: PackedStringArray
) -> void:
	if container == null:
		return
	for index in container.size():
		var id := container.get_item(index)
		if id.is_empty() or not ItemDB.is_apparel(id) or not allowed.has(id):
			continue
		entries.append(_entry(id, source, container, index))


func _append_wardrobe(entries: Array[Dictionary], allowed: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for entry: Dictionary in entries:
		seen[String(entry["id"])] = true
	var wardrobe_ids: Array = []
	for item_id: String in allowed:
		if item_id.is_empty() or seen.has(item_id):
			continue
		seen[item_id] = true
		wardrobe_ids.append(item_id)
	_wardrobe = ItemContainer.new(wardrobe_ids.size(), wardrobe_ids)
	for index in _wardrobe.size():
		entries.append(_entry(
			_wardrobe.get_item(index),
			SOURCE_WARDROBE,
			_wardrobe,
			index
		))


func _append_numbered_items(
	entries: Array[Dictionary],
	container: ItemContainer,
	source: String
) -> void:
	if container == null:
		return
	for index in container.size():
		var id := container.get_item(index)
		if id.is_empty() or not ItemDB.accepts_hotbar(id):
			continue
		entries.append(_entry(id, source, container, index))


func _append_abilities(entries: Array[Dictionary]) -> void:
	var seen: Dictionary = {}
	if _abilities != null:
		for index in _abilities.size():
			var id := _abilities.get_item(index)
			if id.is_empty() or not ItemDB.is_ability(id) or seen.has(id):
				continue
			seen[id] = true
			entries.append(_entry(id, SOURCE_ABILITIES, _abilities, index))

	var library_ids: Array = []
	for id: String in ItemDB.ability_ids():
		if seen.has(id):
			continue
		seen[id] = true
		library_ids.append(id)
	_ability_library = ItemContainer.new(library_ids.size(), library_ids)
	for index in _ability_library.size():
		_ability_library.set_filter(index, ItemDB.ABILITY)
		entries.append(_entry(
			_ability_library.get_item(index),
			SOURCE_KNOWN,
			_ability_library,
			index
		))


func _entry(
	id: String,
	source: String,
	container: ItemContainer,
	index: int
) -> Dictionary:
	return {
		"id": id,
		"source": source,
		"container": container,
		"index": index,
	}


func _matches_filter(entry: Dictionary) -> bool:
	if _filter.is_empty():
		return true
	var id := String(entry.get("id", ""))
	if _mode == Mode.APPAREL:
		return ItemDB.slot_of(id) == _filter
	if _mode == Mode.ITEMS:
		return ItemDB.kind_of(id) == _filter
	return true


func _resolve_selection() -> void:
	var found: Dictionary = {}
	if not _selected_id.is_empty():
		for entry: Dictionary in _visible_entries:
			if String(entry["id"]) == _selected_id \
					and String(entry["source"]) == _selected_source \
					and int(entry["index"]) == _selected_index:
				found = entry
				break
		if found.is_empty():
			for entry: Dictionary in _visible_entries:
				if String(entry["id"]) == _selected_id:
					found = entry
					break
	if found.is_empty() and not _visible_entries.is_empty():
		found = _visible_entries[0]
	if found.is_empty():
		_selected_id = ""
		_selected_source = ""
		_selected_index = -1
		if _mode == Mode.APPAREL:
			_target_index = -1
		else:
			_target_index = maxi(_target_index, 0)
		return
	_remember_entry(found, false)


func _remember_entry(entry: Dictionary, user_pick: bool) -> void:
	_selected_id = String(entry["id"])
	_selected_source = String(entry["source"])
	_selected_index = int(entry["index"])
	if _mode == Mode.APPAREL:
		_target_index = _equipment_index_for_slot(ItemDB.slot_of(_selected_id))
	elif user_pick and _selected_source == _target_source():
		_target_index = _selected_index
	var count := _target_count()
	if count > 0 and (_target_index < 0 or _target_index >= count):
		_target_index = 0


func _current_selected_entry() -> Dictionary:
	for entry: Dictionary in _visible_entries:
		if String(entry["id"]) == _selected_id \
				and String(entry["source"]) == _selected_source \
				and int(entry["index"]) == _selected_index:
			return entry
	for entry: Dictionary in _visible_entries:
		if String(entry["id"]) == _selected_id:
			return entry
	return {}


func _fill_catalogue() -> void:
	_clear_children(_item_grid)
	var has_entries := not _visible_entries.is_empty()
	_catalogue_scroll.visible = has_entries
	_empty_state.visible = not has_entries
	if not has_entries:
		_fill_empty_state()
		return

	for order in _visible_entries.size():
		var entry := _visible_entries[order]
		var slot := RedItemSlot.new()
		slot.name = "OwnedItem_%02d_%s" % [order, String(entry["id"])]
		slot.set_edge(TILE_EDGE)
		slot.bind(entry["container"] as ItemContainer, int(entry["index"]))
		slot.badge = _entry_badge(entry)
		slot.placeholder = ""
		slot.draggable = false
		slot.equipped = String(entry["source"]) == SOURCE_EQUIPMENT \
			or String(entry["source"]) == SOURCE_HOTBAR \
			or String(entry["source"]) == SOURCE_ABILITIES
		slot.selected = (
			String(entry["id"]) == _selected_id
			and String(entry["source"]) == _selected_source
			and int(entry["index"]) == _selected_index
		)
		slot.tooltip_text = "%s\n%s\nCLICK TO INSPECT // SHIFT+CLICK TO QUICK EQUIP" % [
			ItemDB.title(String(entry["id"])).to_upper(),
			_entry_state(entry),
		]
		slot.picked.connect(_on_slot_picked)
		slot.quick_move_requested.connect(_on_slot_quick_move)
		_item_grid.add_child(slot)


func _fill_empty_state() -> void:
	match _mode:
		Mode.APPAREL:
			_empty_glyph.glyph = (
				RedMenuGlyph.Glyph.APPAREL_ALL
				if _filter.is_empty()
				else _glyph_for_body_slot(_filter)
			)
			_empty_title.text = (
				"NO APPAREL"
				if _filter.is_empty()
				else "NO %s APPAREL" % _filter_label(_filter)
			)
			_empty_body.text = (
				"EVERY GARMENT THAT FITS THIS BODY APPEARS HERE.\n"
				+ "HOLD EQUIP ON A TILE, OR SHIFT-CLICK IT, TO PUT IT ON."
			)
		Mode.ITEMS:
			_empty_glyph.glyph = (
				RedMenuGlyph.Glyph.WEAPONS
				if _filter == ItemDB.KIND_WEAPON
				else RedMenuGlyph.Glyph.ITEMS
			)
			_empty_title.text = (
				"NO OWNED ITEMS"
				if _filter.is_empty()
				else "NO OWNED %s" % _filter_label(_filter)
			)
			_empty_body.text = (
				"NUMBERED-SLOT ITEMS APPEAR ONLY FROM YOUR HOTBAR OR BACKPACK."
			)
		Mode.ABILITIES:
			_empty_glyph.glyph = RedMenuGlyph.Glyph.ABILITIES
			_empty_title.text = "ABILITY CHANNELS STANDBY"
			_empty_body.text = (
				"NO ABILITIES MATCH THIS VIEW.\n"
				+ "LMB AND RMB ASSIGNMENTS REMAIN AVAILABLE."
			)


func _on_slot_picked(slot: RedItemSlot) -> void:
	var entry := _entry_for_slot(slot)
	if entry.is_empty():
		return
	_feedback = ""
	_remember_entry(entry, true)
	refresh()


func _on_slot_quick_move(slot: RedItemSlot) -> void:
	var entry := _entry_for_slot(slot)
	if entry.is_empty():
		return
	_feedback = ""
	_remember_entry(entry, true)
	match _mode:
		Mode.APPAREL:
			_equip_apparel(entry)
		Mode.ITEMS:
			_target_index = _quick_target(_hotbar, String(entry["id"]))
			_move_numbered(entry, _hotbar, SOURCE_HOTBAR)
		Mode.ABILITIES:
			_target_index = _quick_target(_abilities, String(entry["id"]))
			_move_ability(entry)
	refresh()


func _entry_for_slot(slot: RedItemSlot) -> Dictionary:
	for entry: Dictionary in _visible_entries:
		if entry["container"] == slot.container and int(entry["index"]) == slot.index:
			return entry
	return {}


func _fill_detail() -> void:
	_clear_children(_detail)
	_clear_children(_detail_footer)
	_target_buttons.clear()
	_detail_icon = null
	_detail_fallback = null
	_equip_action = null
	_drop_action = null

	var entry := _current_selected_entry()
	var id := String(entry.get("id", ""))
	if id.is_empty():
		_detail.add_child(_detail_icon_block(id))
		_fill_empty_detail()
		return

	var description := ItemDB.description(id).strip_edges()
	if description.is_empty():
		description = "NO DESCRIPTION FILED."
	_detail.add_child(_detail_record(entry, id, description))
	if _mode != Mode.APPAREL:
		_detail_footer.add_child(_build_targets(id))
	_detail_footer.add_child(_build_actions(entry))

	if not _feedback.is_empty():
		var feedback := _label(_feedback, 11, GREEN_TEXT, true)
		feedback.name = "ActionFeedback"
		feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detail_footer.add_child(feedback)


func _detail_record(entry: Dictionary, id: String, description: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "SelectedItemRecord"
	row.custom_minimum_size.y = 178.0 if ItemDB.is_ability(id) else 104.0
	row.add_theme_constant_override(&"separation", 10)
	row.add_child(_detail_icon_block(id))

	var copy := VBoxContainer.new()
	copy.name = "SelectedItemCopy"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", 4)
	row.add_child(copy)

	var title := _label(ItemDB.title(id), 21, GREEN, true)
	title.name = "SelectedItemTitle"
	copy.add_child(title)

	var state := _label(
		"%s  //  %s" % [ItemDB.kind_of(id), _entry_state(entry)],
		10,
		GREEN_TEXT
	)
	state.name = "SelectedItemState"
	copy.add_child(state)
	copy.add_child(_rule())

	var detail_text := "DETAIL //\n%s" % description
	if ItemDB.is_ability(id):
		var profile := ItemDB.ability_profile(id)
		if not profile.is_empty():
			detail_text += "\n\nPROFILE //  %s" % profile
		var written_stats := PackedStringArray()
		for line: String in ItemDB.stat_lines(id):
			written_stats.append(line.replace("\t", "  "))
		if not written_stats.is_empty():
			detail_text += "\nSTATS //  %s" % "   |   ".join(written_stats)
	var detail := _label(detail_text, 10, RED_TEXT, true)
	detail.name = "SelectedItemDescription"
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(detail)
	return row


func _fill_empty_detail() -> void:
	var title_text := "NO ITEM SELECTED"
	var body_text := "SELECT AN OWNED ENTRY TO OPEN ITS LOADOUT RECORD."
	if _mode == Mode.APPAREL:
		title_text = "NO APPAREL SELECTED"
		body_text = "SELECT A WARDROBE ENTRY TO OPEN ITS LOADOUT RECORD."
	elif _mode == Mode.ABILITIES:
		title_text = "NO ABILITY SELECTED"
		body_text = (
			"SELECT A KNOWN ABILITY TO OPEN ITS POWER RECORD.\n"
			+ "ASSIGN IT TO LMB OR RMB BELOW."
		)
	var title := _label(title_text, 22, RED_BRIGHT, true)
	title.name = "SelectedItemTitle"
	_detail.add_child(title)
	_detail.add_child(_label(body_text, 12, RED_MUTED, true))
	_detail.add_child(_rule())
	if _mode != Mode.APPAREL:
		_detail_footer.add_child(_build_targets(""))
	_detail_footer.add_child(_build_actions({}))


func _detail_icon_block(id: String) -> PanelContainer:
	var centre := CenterContainer.new()
	centre.custom_minimum_size = Vector2(92.0, 92.0)

	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(80.0, 80.0)
	centre.add_child(icon_holder)

	_detail_icon = TextureRect.new()
	_detail_icon.name = "SelectedItemIcon"
	_detail_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_icon.offset_left = 8.0
	_detail_icon.offset_top = 8.0
	_detail_icon.offset_right = -8.0
	_detail_icon.offset_bottom = -8.0
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.texture = ItemIcons.cached(id) if not id.is_empty() else null
	_detail_icon.modulate = GREEN
	icon_holder.add_child(_detail_icon)

	_detail_fallback = RedMenuGlyph.new()
	_detail_fallback.name = "SelectedItemFallbackGlyph"
	_detail_fallback.glyph = _glyph_for_item(id)
	_detail_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_fallback.offset_left = 14.0
	_detail_fallback.offset_top = 14.0
	_detail_fallback.offset_right = -14.0
	_detail_fallback.offset_bottom = -14.0
	_detail_fallback.visible = _detail_icon.texture == null \
		or _detail_icon.texture.get_width() <= 1
	icon_holder.add_child(_detail_fallback)

	return _glow_frame(centre, "SelectedItemIconFrame", 4.0)


func _detail_section(title_text: String, body: String, colour: Color) -> PanelContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	column.add_child(_label("%s //" % title_text, 10, RED_BRIGHT))
	column.add_child(_label(body, 12, colour, true))
	var panel := PanelContainer.new()
	panel.name = "%sSection" % title_text.capitalize()
	panel.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(RED, 0.45), 1, 9.0)
	)
	panel.add_child(column)
	return panel


func _build_targets(id: String) -> Control:
	var column := VBoxContainer.new()
	column.name = "TargetControls"
	column.add_theme_constant_override(&"separation", 5)
	column.add_child(_label("TARGET SLOT //", 10, RED_BRIGHT))

	var row := HBoxContainer.new()
	row.name = "TargetButtons"
	row.add_theme_constant_override(&"separation", 6)
	column.add_child(row)

	if _mode == Mode.APPAREL:
		if not id.is_empty():
			var body_slot := ItemDB.slot_of(id)
			row.add_child(_target_button(_filter_label(body_slot), _target_index))
		return column

	var labels := ["1", "2", "3"] if _mode == Mode.ITEMS else ["LMB", "RMB"]
	for index in labels.size():
		row.add_child(_target_button(labels[index], index))
	return column


func _target_button(label_text: String, index: int) -> Button:
	var button := Button.new()
	button.name = "TargetSlot%d" % (index + 1)
	button.text = label_text.to_upper()
	button.custom_minimum_size = Vector2(64.0, 32.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(button, index == _target_index)
	var chosen := index
	button.pressed.connect(func() -> void: _choose_target(chosen))
	_target_buttons.append(button)
	return button


func _choose_target(index: int) -> void:
	if index < 0 or index >= _target_count():
		return
	_target_index = index
	_feedback = ""
	_fill_detail()


func _build_actions(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "DetailActions"
	row.add_theme_constant_override(&"separation", 7)

	var id := String(entry.get("id", ""))
	_equip_action = HoldActionButton.new()
	_equip_action.name = "EquipAction"
	_equip_action.custom_minimum_size = Vector2(150.0, 34.0)
	_equip_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_action.size_flags_stretch_ratio = 0.72
	_equip_action.hold_duration = 0.8
	_equip_action.label_text = _equip_label(entry)
	_equip_action.label_font_size = 12
	_equip_action.content_padding = 4.0
	_equip_action.progress_width = 2.0
	_equip_action.glyph = _glyph_for_item(id)
	_equip_action.active = not id.is_empty()
	_equip_action.selected = _selected_at_target(entry)
	_equip_action.disabled = id.is_empty() or not _can_equip(entry)
	_equip_action.completed.connect(_on_equip_completed)
	row.add_child(_equip_action)

	_drop_action = Button.new()
	_drop_action.name = "DropAction"
	_drop_action.text = "DROP"
	_drop_action.custom_minimum_size = Vector2(74.0, 34.0)
	_drop_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_action.size_flags_stretch_ratio = 0.28
	_drop_action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_drop_action.disabled = id.is_empty() or not _is_physical(entry) \
		or _mode == Mode.ABILITIES
	_style_button(_drop_action, false, true)
	_drop_action.pressed.connect(_on_drop_pressed)
	row.add_child(_drop_action)
	return row


func _equip_label(entry: Dictionary) -> String:
	if entry.is_empty():
		return "HOLD TO EQUIP"
	if _mode == Mode.APPAREL and String(entry["source"]) == SOURCE_EQUIPMENT:
		return "HOLD TO UNEQUIP"
	if _selected_at_target(entry):
		return "EQUIPPED // %s" % _target_label(_target_index)
	return "HOLD TO EQUIP"


func _can_equip(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	match _mode:
		Mode.APPAREL:
			return _equipment != null and _target_index >= 0
		Mode.ITEMS:
			return _hotbar != null and _target_index >= 0 \
				and _target_index < _hotbar.size()
		Mode.ABILITIES:
			return _abilities != null and _target_index >= 0 \
				and _target_index < _abilities.size()
	return false


func _selected_at_target(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	return String(entry.get("source", "")) == _target_source() \
		and int(entry.get("index", -1)) == _target_index


func _on_equip_completed() -> void:
	var entry := _current_selected_entry()
	if entry.is_empty():
		return
	_feedback = ""
	match _mode:
		Mode.APPAREL:
			_equip_apparel(entry)
		Mode.ITEMS:
			_move_numbered(entry, _hotbar, SOURCE_HOTBAR)
		Mode.ABILITIES:
			_move_ability(entry)
	refresh()


func _equip_apparel(entry: Dictionary) -> void:
	if _equipment == null or _backpack == null:
		_feedback = "LOADOUT CONTAINERS UNAVAILABLE"
		return
	var id := String(entry["id"])
	var source := String(entry["source"])
	var container := entry["container"] as ItemContainer
	var index := int(entry["index"])
	var equipment_index := _equipment_index_for_slot(ItemDB.slot_of(id))
	if equipment_index < 0:
		_feedback = "NO COMPATIBLE BODY SLOT"
		return
	var moved := false
	if source == SOURCE_EQUIPMENT:
		if _backpack == null:
			_equipment.set_item(index, "")
			_feedback = "APPAREL REMOVED"
			return
		moved = ItemContainer.quick_move(_equipment, index, _backpack)
		if not moved:
			# Wardrobe garments do not have to occupy a backpack slot.
			_equipment.set_item(index, "")
			_feedback = "APPAREL REMOVED"
		else:
			_feedback = "MOVED TO BACKPACK"
	elif source == SOURCE_BACKPACK and container == _backpack:
		moved = ItemContainer.transfer(_backpack, index, _equipment, equipment_index)
		_feedback = "APPAREL EQUIPPED" if moved else "EQUIP TRANSFER REFUSED"
	elif source == SOURCE_WARDROBE:
		_wear_wardrobe_item(id, equipment_index)


func _wear_wardrobe_item(id: String, equipment_index: int) -> void:
	var current := _equipment.get_item(equipment_index)
	if current == id:
		if _backpack != null and _backpack.find(current) < 0 \
				and ItemContainer.quick_move(_equipment, equipment_index, _backpack):
			_feedback = "MOVED TO BACKPACK"
		else:
			_equipment.set_item(equipment_index, "")
			_feedback = "APPAREL REMOVED"
		return
	if not current.is_empty() and _backpack != null and _backpack.find(current) < 0:
		var dest := _backpack.first_accepting(current)
		if dest >= 0:
			_backpack.set_item(dest, current)
	_equipment.set_item(equipment_index, id)
	_feedback = (
		"APPAREL EQUIPPED"
		if _equipment.get_item(equipment_index) == id
		else "EQUIP REFUSED"
	)


func _move_numbered(
	entry: Dictionary,
	target: ItemContainer,
	target_source: String
) -> void:
	if target == null or _target_index < 0 or _target_index >= target.size():
		_feedback = "TARGET SLOT UNAVAILABLE"
		return
	var source := entry["container"] as ItemContainer
	var source_index := int(entry["index"])
	if source == null:
		_feedback = "SOURCE SLOT UNAVAILABLE"
		return
	if source == target and source_index == _target_index:
		_feedback = "ALREADY EQUIPPED // %s" % _target_label(_target_index)
		return
	var moved := ItemContainer.transfer(source, source_index, target, _target_index)
	_feedback = (
		"MOVED TO %s" % _target_label(_target_index)
		if moved
		else "LOSSLESS TRANSFER REFUSED"
	)
	if moved:
		_selected_source = target_source
		_selected_index = _target_index


func _move_ability(entry: Dictionary) -> void:
	if _abilities == null or _target_index < 0 or _target_index >= _abilities.size():
		_feedback = "ABILITY TARGET UNAVAILABLE"
		return
	var source := String(entry["source"])
	if source == SOURCE_KNOWN:
		# Known powers are definitions, not physical ownership. Replacing an
		# assignment cannot destroy the displaced definition.
		_abilities.set_item(_target_index, String(entry["id"]))
		var assigned := _abilities.get_item(_target_index) == String(entry["id"])
		_feedback = (
			"ABILITY ASSIGNED // %s" % _target_label(_target_index)
			if assigned
			else "ABILITY ASSIGNMENT REFUSED"
		)
		if assigned:
			_selected_source = SOURCE_ABILITIES
			_selected_index = _target_index
		return
	_move_numbered(entry, _abilities, SOURCE_ABILITIES)


func _quick_target(container: ItemContainer, id: String) -> int:
	if container == null or container.size() <= 0:
		return -1
	var open := container.first_accepting(id)
	return open if open >= 0 else 0


func _on_drop_pressed() -> void:
	if _mode == Mode.ABILITIES:
		return
	var entry := _current_selected_entry()
	if entry.is_empty() or not _is_physical(entry):
		return
	var container := entry["container"] as ItemContainer
	var index := int(entry["index"])
	var id := String(entry["id"])
	if container == null or container.get_item(index) != id:
		return
	var source := String(entry["source"])
	drop_requested.emit(source, index, id)
	_feedback = "DROP REQUESTED // AWAITING WORLD AUTHORITY"
	_fill_detail()


func _is_physical(entry: Dictionary) -> bool:
	var source := String(entry.get("source", ""))
	return source == SOURCE_EQUIPMENT or source == SOURCE_BACKPACK \
		or source == SOURCE_HOTBAR


func _equipment_index_for_slot(body_slot: String) -> int:
	if _equipment == null:
		return -1
	for index in _equipment.size():
		if _equipment.filter_of(index) == body_slot:
			return index
	var ordered := ItemDB.SLOT_ORDER.find(body_slot)
	return ordered if ordered >= 0 and ordered < _equipment.size() else -1


func _target_count() -> int:
	match _mode:
		Mode.APPAREL:
			return _equipment.size() if _equipment != null else ItemDB.SLOT_ORDER.size()
		Mode.ITEMS:
			return _hotbar.size() if _hotbar != null else CharacterDB.HOTBAR_SLOTS
		Mode.ABILITIES:
			return _abilities.size() if _abilities != null else CharacterDB.ABILITY_SLOTS
	return 0


func _target_source() -> String:
	match _mode:
		Mode.APPAREL:
			return SOURCE_EQUIPMENT
		Mode.ITEMS:
			return SOURCE_HOTBAR
		Mode.ABILITIES:
			return SOURCE_ABILITIES
	return ""


func _target_label(index: int) -> String:
	if _mode == Mode.APPAREL:
		if index >= 0 and index < ItemDB.SLOT_ORDER.size():
			return _filter_label(ItemDB.SLOT_ORDER[index])
		return "BODY SLOT"
	if _mode == Mode.ABILITIES:
		return ["LMB", "RMB"][index] if index >= 0 and index < 2 else "ABILITY SLOT"
	return "SLOT %d" % (index + 1)


func _entry_badge(entry: Dictionary) -> String:
	var source := String(entry["source"])
	var index := int(entry["index"])
	match source:
		SOURCE_EQUIPMENT:
			return "WORN"
		SOURCE_BACKPACK:
			return "B%02d" % (index + 1)
		SOURCE_HOTBAR:
			return str(index + 1)
		SOURCE_ABILITIES:
			return ["LMB", "RMB"][index] if index >= 0 and index < 2 else "A"
		SOURCE_KNOWN:
			return "KNOWN"
		SOURCE_WARDROBE:
			return "WARDROBE"
	return ""


func _entry_state(entry: Dictionary) -> String:
	var source := String(entry.get("source", ""))
	var index := int(entry.get("index", -1))
	match source:
		SOURCE_EQUIPMENT:
			return "WORN // %s" % _target_label(index)
		SOURCE_BACKPACK:
			return "BACKPACK // SLOT %02d" % (index + 1)
		SOURCE_HOTBAR:
			return "HOTBAR // SLOT %d" % (index + 1)
		SOURCE_ABILITIES:
			return "ASSIGNED // %s" % (
				["LMB", "RMB"][index] if index >= 0 and index < 2 else "ABILITY"
			)
		SOURCE_KNOWN:
			return "KNOWN // UNASSIGNED"
		SOURCE_WARDROBE:
			return "WARDROBE // READY TO WEAR"
	return "UNASSIGNED"


func _update_header(total_count: int) -> void:
	var heading := ""
	match _mode:
		Mode.APPAREL:
			heading = "ALL APPAREL" if _filter.is_empty() else _filter_label(_filter)
		Mode.ITEMS:
			heading = "ALL ITEMS" if _filter.is_empty() else _filter_label(_filter)
		Mode.ABILITIES:
			heading = "ABILITIES"
	_header_title.text = heading.to_upper()
	var noun := "KNOWN"
	if _mode == Mode.ITEMS:
		noun = "OWNED"
	elif _mode == Mode.APPAREL:
		noun = "WARDROBE"
	_header_count.text = "%02d / %02d %s" % [
		_visible_entries.size(),
		total_count,
		noun,
	]


func _request_icons(entries: Array[Dictionary]) -> void:
	if _icons == null:
		return
	var ids: Array = []
	for entry: Dictionary in entries:
		var id := String(entry["id"])
		if not id.is_empty() and not ids.has(id):
			ids.append(id)
	_icons.request(ids)


func _on_icon_ready(id: String, texture: Texture2D) -> void:
	for child: Node in _item_grid.get_children():
		if child is RedItemSlot:
			(child as RedItemSlot).queue_redraw()
	if id != _selected_id or _detail_icon == null \
			or not is_instance_valid(_detail_icon):
		return
	_detail_icon.texture = texture
	if _detail_fallback != null and is_instance_valid(_detail_fallback):
		_detail_fallback.visible = texture == null


func _update_responsive_layout() -> void:
	if not _built:
		return
	var available_width := size.x
	if available_width <= 0.0:
		available_width = get_viewport_rect().size.x
	var narrow := available_width < NARROW_WIDTH
	if _responsive_initialized and narrow == _narrow:
		_fit_catalogue_columns()
		return
	_responsive_initialized = true
	_narrow = narrow
	_content_grid.columns = 1 if narrow else 2
	if narrow:
		_catalogue_frame.custom_minimum_size = Vector2(0.0, CATALOGUE_NARROW_HEIGHT)
		_detail_frame.custom_minimum_size = Vector2(0.0, DETAIL_NARROW_HEIGHT)
	else:
		_catalogue_frame.custom_minimum_size = Vector2(CATALOGUE_MIN_WIDTH, 0.0)
		_detail_frame.custom_minimum_size = Vector2(DETAIL_MIN_WIDTH, 0.0)
	call_deferred(&"_fit_catalogue_columns")


func _fit_catalogue_columns() -> void:
	if _item_grid == null or not is_instance_valid(_item_grid):
		return
	var available := _catalogue_scroll.size.x - 4.0
	if available <= 0.0:
		return
	var columns := maxi(2, int((available + TILE_GAP) / (TILE_EDGE + TILE_GAP)))
	if _item_grid.columns != columns:
		_item_grid.columns = columns


func _glyph_for_item(id: String) -> RedMenuGlyph.Glyph:
	if _mode == Mode.ABILITIES or ItemDB.is_ability(id):
		return RedMenuGlyph.Glyph.ABILITIES
	if ItemDB.is_weapon(id):
		return RedMenuGlyph.Glyph.WEAPONS
	if ItemDB.is_item(id):
		return RedMenuGlyph.Glyph.ITEMS
	if ItemDB.is_apparel(id):
		return _glyph_for_body_slot(ItemDB.slot_of(id))
	match _mode:
		Mode.APPAREL:
			return RedMenuGlyph.Glyph.APPAREL_ALL
		Mode.ITEMS:
			return RedMenuGlyph.Glyph.ITEMS
		Mode.ABILITIES:
			return RedMenuGlyph.Glyph.ABILITIES
	return RedMenuGlyph.Glyph.EMPTY_X


func _glyph_for_body_slot(body_slot: String) -> RedMenuGlyph.Glyph:
	match body_slot:
		"hat":
			return RedMenuGlyph.Glyph.HAT
		"goggles":
			return RedMenuGlyph.Glyph.GOGGLES
		"long_sleeve":
			return RedMenuGlyph.Glyph.BODY_TUNIC
		"pants":
			return RedMenuGlyph.Glyph.PANTS
		"shoes":
			return RedMenuGlyph.Glyph.BOOTS
	return RedMenuGlyph.Glyph.APPAREL_ALL


func _filter_label(id: String) -> String:
	if id == ItemDB.KIND_WEAPON:
		return "Weapons"
	if id == ItemDB.KIND_ITEM:
		return "Items"
	return String(ItemDB.SLOT_LABELS.get(id, id.capitalize()))


func _reserve_icon_lane(button: Button, left_margin: float) -> void:
	for state: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"focus",
		&"disabled",
	]:
		var box := button.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			box.content_margin_left = left_margin


func _style_button(button: Button, active: bool, destructive := false) -> void:
	var accent := GREEN if active else RED
	var text_colour := GREEN_TEXT if active else (RED_BRIGHT if destructive else RED_TEXT)
	var fill := Color(0.0, 0.14, 0.04, 0.76) if active else BLACK_62
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(&"font_color", text_colour)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_color_override(&"font_disabled_color", Color(RED_MUTED, 0.34))
	button.add_theme_stylebox_override(
		&"normal",
		_style(fill, Color(accent, 0.9), 2 if active else 1, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_76, GREEN, 2, 8.0, Color(GREEN, 0.15), 4)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.18, 0.05, 0.82), GREEN, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, accent, 1, 7.0)
	)
	button.add_theme_stylebox_override(
		&"disabled",
		_style(BLACK_42, Color(RED_MUTED, 0.30), 1, 8.0)
	)


func _label(
	text: String,
	font_size: int,
	colour: Color,
	wrap: bool = false
) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_color_override(&"font_outline_color", Color(0.1, 0.0, 0.0, 0.94))
	label.add_theme_constant_override(&"outline_size", 1)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _rule() -> PanelContainer:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(
		&"panel",
		_style(Color(RED, 0.48), RED_BRIGHT, 1, 0.0)
	)
	return rule


func _glow_frame(
	content: Control,
	node_name: String,
	padding: float
) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_62, Color(RED_BRIGHT, 0.90), 1, padding)
	)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = BLACK_42
	glow.border_color = Color(RED, 0.94)
	glow.border_width = 1.5
	glow.glow_intensity = 1.2
	glow.glow_spread = 8.0
	glow.glow_layers = 4
	frame.add_child(content)
	return frame


func _style(
	fill: Color,
	border: Color,
	border_width: int,
	padding: float,
	shadow: Color = Color.TRANSPARENT,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	box.shadow_color = shadow
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2.ZERO
	return box


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
