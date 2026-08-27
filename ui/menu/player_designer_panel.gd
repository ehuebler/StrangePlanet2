class_name PlayerDesignerPanel
extends Control

## Home-screen character designer in the same red/green/black language as the
## in-game Hero and Apparel pages.
##
## The live character standing beside this panel is the preview. This control
## therefore contains only appearance controls: equipped apparel, texture and
## tint on Hero Design, then an apparel-only hold catalogue on Apparel.

signal name_entered(value: String)
signal skin_picked(skin_id: String)
signal tint_picked(target: String, colour: Color)
signal tint_cleared(target: String)

enum Tab {
	HERO,
	APPAREL,
}

const BACKGROUND := preload("res://assets/runtime/ui/menu_background.png")
const TINT_BODY := "body"
const TAB_LABELS: Array[String] = ["Hero Design", "Apparel"]

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const BLACK_86 := Color(0.0, 0.0, 0.0, 0.86)
const TILE_EDGE := 88.0
const TILE_GAP := 9.0

const APPAREL_FILTERS: Array[Dictionary] = [
	{"id": "", "label": "All", "glyph": RedMenuGlyph.Glyph.APPAREL_ALL},
	{"id": "hat", "label": "Head", "glyph": RedMenuGlyph.Glyph.HAT},
	{"id": "goggles", "label": "Eyes", "glyph": RedMenuGlyph.Glyph.GOGGLES},
	{"id": "long_sleeve", "label": "Body", "glyph": RedMenuGlyph.Glyph.BODY_TUNIC},
	{"id": "pants", "label": "Legs", "glyph": RedMenuGlyph.Glyph.PANTS},
	{"id": "shoes", "label": "Feet", "glyph": RedMenuGlyph.Glyph.BOOTS},
]
const APPAREL_GLYPHS := [
	RedMenuGlyph.Glyph.HAT,
	RedMenuGlyph.Glyph.GOGGLES,
	RedMenuGlyph.Glyph.BODY_TUNIC,
	RedMenuGlyph.Glyph.PANTS,
	RedMenuGlyph.Glyph.BOOTS,
]

var _equipment: ItemContainer
var _catalogue: ItemContainer
var _body_id := CharacterDB.DEFAULT_BODY
var _skin_id := ""
var _tints: Dictionary = {}
var _player_name := "PLAYER"
var _tab := Tab.HERO
var _filter := ""
var _tint_target := TINT_BODY
var _built := false

var _background: TextureRect
var _tabs: HBoxContainer
var _page_host: MarginContainer
var _hero_page: VBoxContainer
var _apparel_page: VBoxContainer
var _name_field: LineEdit
var _skin_row: HBoxContainer
var _tint_caption: Label
var _clear_tint: Button
var _wheel: ColourWheel
var _hero_slots: Array[RedItemSlot] = []
var _hero_glyphs: Array[RedMenuGlyph] = []
var _apparel_grid: GridContainer
var _apparel_scroll: ScrollContainer
var _apparel_count: Label
var _empty_apparel: Label
var _apparel_tiles: Array[DesignerApparelTile] = []
var _icons: ItemIcons


func configure(
		equipment: ItemContainer,
		catalogue: ItemContainer,
		body_id: String,
		skin_id: String,
		tints: Dictionary,
		player_name: String
	) -> void:
	_disconnect_sources()
	_equipment = equipment
	_catalogue = catalogue
	_body_id = CharacterDB.sanitize_body(body_id)
	_skin_id = CharacterDB.sanitize_skin(_body_id, skin_id)
	_tints = tints.duplicate(true)
	_player_name = player_name
	if is_inside_tree():
		_connect_sources()
	if _built:
		refresh()


func _init() -> void:
	name = "PlayerDesignerPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(520.0, 430.0)
	clip_contents = true


func _ready() -> void:
	_build()
	_built = true
	_connect_sources()
	refresh()
	resized.connect(_layout_background)
	call_deferred(&"_layout_background")
	call_deferred(&"_fit_apparel_columns")


func _exit_tree() -> void:
	_disconnect_sources()


func _get_minimum_size() -> Vector2:
	return custom_minimum_size


func _connect_sources() -> void:
	for source: ItemContainer in [_equipment, _catalogue]:
		if source != null and not source.changed.is_connected(refresh):
			source.changed.connect(refresh)


func _disconnect_sources() -> void:
	for source: ItemContainer in [_equipment, _catalogue]:
		if source != null and source.changed.is_connected(refresh):
			source.changed.disconnect(refresh)


func _build() -> void:
	_background = TextureRect.new()
	_background.name = "RotatedUIBackground2"
	_background.texture = BACKGROUND
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var veil := ColorRect.new()
	veil.name = "DesignerBackgroundVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.0, 0.0, 0.0, 0.25)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

	var frame := PanelContainer.new()
	frame.name = "DesignerFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_stylebox_override(
		&"panel",
		_style(Color(0.0, 0.0, 0.0, 0.12), Color(RED_BRIGHT, 0.98), 2, 10.0)
	)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = Color(0.0, 0.0, 0.0, 0.16)
	glow.border_color = Color(RED_BRIGHT, 0.98)
	glow.border_width = 2.0
	glow.glow_intensity = 1.4
	glow.glow_spread = 11.0
	glow.glow_layers = 5
	add_child(frame)

	var shell := VBoxContainer.new()
	shell.name = "DesignerShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override(&"separation", 8)
	frame.add_child(shell)

	_tabs = HBoxContainer.new()
	_tabs.name = "DesignerTabs"
	_tabs.add_theme_constant_override(&"separation", 9)
	shell.add_child(_tabs)

	_page_host = MarginContainer.new()
	_page_host.name = "DesignerPageHost"
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(_page_host)

	_hero_page = _build_hero_page()
	_page_host.add_child(_hero_page)
	_apparel_page = _build_apparel_page()
	_page_host.add_child(_apparel_page)

	_icons = ItemIcons.new()
	_icons.name = "DesignerItemIcons"
	add_child(_icons)
	_icons.icon_ready.connect(_on_icon_ready)

	show_tab(_tab)


func _build_hero_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "DesignerHeroPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", 8)

	var identity := HBoxContainer.new()
	identity.name = "DesignerIdentity"
	identity.add_theme_constant_override(&"separation", 12)
	var title := _label("HERO DESIGN", 23, RED_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(title)
	_name_field = LineEdit.new()
	_name_field.name = "DesignerName"
	_name_field.custom_minimum_size = Vector2(238.0, 40.0)
	_name_field.max_length = NetworkManager.PLAYER_NAME_MAX_LENGTH
	_name_field.placeholder_text = "YOUR NAME"
	_style_input(_name_field)
	_name_field.text_submitted.connect(func(value: String) -> void:
		name_entered.emit(value)
	)
	_name_field.focus_exited.connect(func() -> void:
		name_entered.emit(_name_field.text)
	)
	identity.add_child(_name_field)
	page.add_child(_glow_frame(identity, "DesignerIdentityFrame", 6.0))

	var apparel_column := VBoxContainer.new()
	apparel_column.name = "DesignerEquippedContent"
	apparel_column.add_theme_constant_override(&"separation", 8)
	apparel_column.add_child(_section_heading("EQUIPPED APPAREL  //  CLICK TO AIM TINT"))
	apparel_column.add_child(_rule())
	var apparel_centre := CenterContainer.new()
	apparel_centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apparel_centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	apparel_column.add_child(apparel_centre)
	var equipped_grid := GridContainer.new()
	equipped_grid.name = "DesignerEquippedSlots"
	equipped_grid.columns = ItemDB.SLOT_ORDER.size()
	equipped_grid.add_theme_constant_override(&"h_separation", 10)
	apparel_centre.add_child(equipped_grid)
	for index in ItemDB.SLOT_ORDER.size():
		var body_slot: String = ItemDB.SLOT_ORDER[index]
		var slot := RedItemSlot.new()
		slot.name = "DesignerWorn_%s" % body_slot
		slot.set_edge(78.0)
		slot.badge = String(ItemDB.SLOT_LABELS.get(body_slot, body_slot)).to_upper()
		slot.placeholder = ""
		slot.draggable = false
		slot.bind(_equipment, index)
		slot.picked.connect(_on_hero_slot_picked)
		equipped_grid.add_child(slot)
		_hero_slots.append(slot)

		var glyph := RedMenuGlyph.new()
		glyph.name = "Empty_%s" % body_slot
		glyph.glyph = APPAREL_GLYPHS[index]
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.offset_left = 14.0
		glyph.offset_top = 14.0
		glyph.offset_right = -14.0
		glyph.offset_bottom = -14.0
		slot.add_child(glyph)
		_hero_glyphs.append(glyph)
	var equipped_frame := _glow_frame(
		apparel_column, "DesignerEquippedFrame", 8.0
	)
	equipped_frame.custom_minimum_size.y = 132.0
	page.add_child(equipped_frame)

	var picker_column := VBoxContainer.new()
	picker_column.name = "DesignerPickerContent"
	picker_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_column.add_theme_constant_override(&"separation", 8)
	picker_column.add_child(_section_heading(
		"APPEARANCE PICKERS  //  REPLACES THE HOTBAR"
	))
	picker_column.add_child(_rule())

	var picker_row := HBoxContainer.new()
	picker_row.name = "DesignerPickers"
	picker_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_row.add_theme_constant_override(&"separation", 14)
	picker_column.add_child(picker_row)

	var picker_controls := VBoxContainer.new()
	picker_controls.name = "SkinAndTintControls"
	picker_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_controls.add_theme_constant_override(&"separation", 8)
	picker_row.add_child(picker_controls)
	picker_controls.add_child(_label("SKIN TEXTURE //", 12, RED_BRIGHT))
	_skin_row = HBoxContainer.new()
	_skin_row.name = "DesignerSkinPicker"
	_skin_row.add_theme_constant_override(&"separation", 7)
	picker_controls.add_child(_skin_row)
	picker_controls.add_child(_rule())

	var tint_title := HBoxContainer.new()
	tint_title.add_theme_constant_override(&"separation", 8)
	var tint_heading := _label("TINT //", 12, RED_BRIGHT)
	tint_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tint_title.add_child(tint_heading)
	_clear_tint = _button("NO TINT")
	_clear_tint.name = "DesignerNoTint"
	_clear_tint.custom_minimum_size = Vector2(112.0, 36.0)
	_clear_tint.pressed.connect(_clear_selected_tint)
	tint_title.add_child(_clear_tint)
	picker_controls.add_child(tint_title)
	_tint_caption = _label("", 11, GREEN_TEXT, true)
	_tint_caption.name = "DesignerTintTarget"
	_tint_caption.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_controls.add_child(_tint_caption)
	picker_controls.add_child(_label(
		"CLICK A WORN TILE ABOVE TO TINT THAT GARMENT.",
		10,
		RED_MUTED,
		true
	))

	var wheel_centre := CenterContainer.new()
	wheel_centre.name = "DesignerTintPicker"
	wheel_centre.custom_minimum_size.x = 154.0
	wheel_centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_row.add_child(wheel_centre)
	_wheel = ColourWheel.new()
	_wheel.name = "DesignerColourWheel"
	_wheel.picked.connect(_pick_tint)
	wheel_centre.add_child(_wheel)

	var picker_frame := _glow_frame(
		picker_column, "DesignerAppearanceFrame", 8.0
	)
	picker_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(picker_frame)
	return page


func _build_apparel_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "DesignerApparelPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", 10)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var title := _label("APPAREL", 23, RED_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_apparel_count = _label("00 OWNED", 11, RED_MUTED)
	_apparel_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apparel_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_apparel_count)
	page.add_child(_glow_frame(header, "DesignerApparelHeader", 10.0))

	var filter_column := VBoxContainer.new()
	filter_column.add_theme_constant_override(&"separation", 5)
	filter_column.add_child(_label("FILTER // CLICK ACTIVE FILTER TO SHOW ALL", 10, RED_MUTED))
	var filter_scroll := ScrollContainer.new()
	filter_scroll.name = "DesignerFilterScroll"
	filter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	filter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	filter_scroll.custom_minimum_size.y = 48.0
	filter_column.add_child(filter_scroll)
	var filter_row := HBoxContainer.new()
	filter_row.name = "DesignerApparelFilters"
	filter_row.add_theme_constant_override(&"separation", 7)
	filter_scroll.add_child(filter_row)
	for definition: Dictionary in APPAREL_FILTERS:
		var id := String(definition["id"])
		var filter_button := _filter_button(
			String(definition["label"]),
			int(definition["glyph"]) as RedMenuGlyph.Glyph,
			id == _filter
		)
		filter_button.name = "DesignerFilter_%s" % (
			"All" if id.is_empty() else id
		)
		var chosen := id
		filter_button.pressed.connect(func() -> void: _pick_filter(chosen))
		filter_row.add_child(filter_button)
	page.add_child(_glow_frame(filter_column, "DesignerApparelFilterFrame", 8.0))

	var catalogue_column := VBoxContainer.new()
	catalogue_column.name = "DesignerApparelCatalogue"
	catalogue_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_theme_constant_override(&"separation", 8)
	var hint := _label(
		"HOLD A TILE TO EQUIP OR UNEQUIP  //  EVERY GARMENT FOR THIS BODY",
		10,
		GREEN_TEXT,
		true
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	catalogue_column.add_child(hint)
	catalogue_column.add_child(_rule())

	_apparel_scroll = ScrollContainer.new()
	_apparel_scroll.name = "DesignerOwnedApparelScroll"
	_apparel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_apparel_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apparel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_child(_apparel_scroll)
	_apparel_grid = GridContainer.new()
	_apparel_grid.name = "DesignerOwnedApparelGrid"
	_apparel_grid.columns = 5
	_apparel_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apparel_grid.add_theme_constant_override(&"h_separation", int(TILE_GAP))
	_apparel_grid.add_theme_constant_override(&"v_separation", int(TILE_GAP))
	_apparel_scroll.add_child(_apparel_grid)
	_apparel_grid.resized.connect(_fit_apparel_columns)

	_empty_apparel = _label(
		"NO OWNED APPAREL MATCHES THIS FILTER.",
		16,
		RED_MUTED,
		true
	)
	_empty_apparel.name = "DesignerApparelEmpty"
	_empty_apparel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_apparel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_apparel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_child(_empty_apparel)

	var catalogue_frame := _glow_frame(
		catalogue_column, "DesignerApparelCatalogueFrame", 11.0
	)
	catalogue_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(catalogue_frame)
	return page


func show_tab(tab: Tab) -> void:
	_tab = tab
	if not _built and _tabs == null:
		return
	_fill_tabs()
	if _hero_page != null:
		_hero_page.visible = _tab == Tab.HERO
	if _apparel_page != null:
		_apparel_page.visible = _tab == Tab.APPAREL
	if _tab == Tab.APPAREL:
		_fill_apparel()


func _fill_tabs() -> void:
	if _tabs == null:
		return
	_clear(_tabs)
	for index in TAB_LABELS.size():
		var button := _button(TAB_LABELS[index], index == int(_tab))
		button.name = "DesignerTab_%s" % TAB_LABELS[index].replace(" ", "")
		button.custom_minimum_size.y = 42.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chosen := index
		button.pressed.connect(func() -> void: show_tab(chosen as Tab))
		_tabs.add_child(button)


func refresh() -> void:
	if not _built:
		return
	if _name_field != null and not _name_field.has_focus():
		_name_field.text = _player_name
	_fill_skin_row()
	_refresh_hero_slots()
	_update_tint_target()
	_fill_apparel()


func _refresh_hero_slots() -> void:
	for index in _hero_slots.size():
		var slot := _hero_slots[index]
		var id := slot.item_id()
		var body_slot := _equipment.filter_of(index) if _equipment != null else ""
		slot.equipped = not id.is_empty()
		slot.selected = _tint_target != TINT_BODY and body_slot == _tint_target
		slot.tooltip_text = (
			"%s\nCLICK TO AIM TINT"
			% (ItemDB.title(id).to_upper() if not id.is_empty() else "EMPTY %s" % slot.badge)
		)
		if index < _hero_glyphs.size():
			_hero_glyphs[index].visible = id.is_empty()
		slot.queue_redraw()


func _fill_skin_row() -> void:
	if _skin_row == null:
		return
	_clear(_skin_row)
	for skin_id: String in CharacterDB.skin_ids(_body_id):
		var button := _button(
			CharacterDB.skin_title(skin_id),
			skin_id == _skin_id
		)
		button.name = "DesignerSkin_%s" % skin_id
		button.custom_minimum_size.y = 42.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var chosen := skin_id
		button.pressed.connect(func() -> void: _pick_skin(chosen))
		_skin_row.add_child(button)


func _pick_skin(skin_id: String) -> void:
	var clean := CharacterDB.sanitize_skin(_body_id, skin_id)
	if clean == _skin_id:
		return
	_skin_id = clean
	_fill_skin_row()
	skin_picked.emit(_skin_id)


func _on_hero_slot_picked(slot: RedItemSlot) -> void:
	if slot.item_id().is_empty() or _equipment == null:
		_tint_target = TINT_BODY
	else:
		var chosen := _equipment.filter_of(slot.index)
		_tint_target = TINT_BODY if chosen == _tint_target else chosen
	_update_tint_target()
	_refresh_hero_slots()


func _pick_tint(colour: Color) -> void:
	_tints[_tint_target] = colour.to_html(false)
	_update_tint_target()
	tint_picked.emit(_tint_target, colour)


func _clear_selected_tint() -> void:
	if not _tints.has(_tint_target):
		return
	_tints.erase(_tint_target)
	_update_tint_target()
	tint_cleared.emit(_tint_target)


func _update_tint_target() -> void:
	if _tint_target != TINT_BODY and _equipped_in(_tint_target).is_empty():
		_tint_target = TINT_BODY
	if _tint_caption != null:
		var target_title := "SKIN"
		if _tint_target != TINT_BODY:
			target_title = ItemDB.title(_equipped_in(_tint_target)).to_upper()
		_tint_caption.text = "TARGET // %s\n%s" % [
			target_title,
			"TINT ACTIVE" if _tints.has(_tint_target) else "AUTHORED COLOUR",
		]
	if _clear_tint != null:
		_clear_tint.disabled = not _tints.has(_tint_target)
	if _wheel != null:
		_wheel.set_colour(Color.html(str(_tints.get(_tint_target, "ffffff"))))


func _equipped_in(body_slot: String) -> String:
	if _equipment == null:
		return ""
	for index in _equipment.size():
		if _equipment.filter_of(index) == body_slot:
			return _equipment.get_item(index)
	return ""


func _pick_filter(id: String) -> void:
	_filter = "" if _filter == id else id
	_rebuild_apparel_filters()
	_fill_apparel()


func _rebuild_apparel_filters() -> void:
	var row := find_child("DesignerApparelFilters", true, false) as HBoxContainer
	if row == null:
		return
	_clear(row)
	for definition: Dictionary in APPAREL_FILTERS:
		var id := String(definition["id"])
		var button := _filter_button(
			String(definition["label"]),
			int(definition["glyph"]) as RedMenuGlyph.Glyph,
			id == _filter
		)
		button.name = "DesignerFilter_%s" % ("All" if id.is_empty() else id)
		var chosen := id
		button.pressed.connect(func() -> void: _pick_filter(chosen))
		row.add_child(button)


func _fill_apparel() -> void:
	if _apparel_grid == null or _catalogue == null:
		return
	_clear(_apparel_grid)
	_apparel_tiles.clear()
	var all_entries := _apparel_entries(false)
	var visible_entries := _apparel_entries(true)
	if _apparel_count != null:
		_apparel_count.text = "%02d / %02d OWNED" % [
			visible_entries.size(),
			all_entries.size(),
		]
	if _apparel_scroll != null:
		_apparel_scroll.visible = not visible_entries.is_empty()
	if _empty_apparel != null:
		_empty_apparel.visible = visible_entries.is_empty()

	var icon_ids: Array = []
	for entry: Dictionary in visible_entries:
		var id := String(entry["id"])
		var tile := DesignerApparelTile.new()
		tile.name = "DesignerApparel_%s" % id
		tile.set_edge(TILE_EDGE)
		tile.bind(_catalogue, int(entry["index"]))
		tile.placeholder = ""
		tile.equipped = _equipment != null and _equipment.find(id) >= 0
		tile.selected = tile.equipped
		tile.badge = "WORN" if tile.equipped else "HOLD"
		tile.tooltip_text = "%s\n%s" % [
			ItemDB.title(id).to_upper(),
			"HOLD TO UNEQUIP" if tile.equipped else "HOLD TO EQUIP",
		]
		tile.hold_completed.connect(_on_apparel_hold_completed)
		_apparel_grid.add_child(tile)
		_apparel_tiles.append(tile)
		icon_ids.append(id)
	if _icons != null:
		_icons.request(icon_ids)
	call_deferred(&"_fit_apparel_columns")


func _apparel_entries(filtered: bool) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _catalogue == null:
		return entries
	var seen: Dictionary = {}
	for index in _catalogue.size():
		var id := _catalogue.get_item(index)
		if id.is_empty() or seen.has(id) or not ItemDB.is_apparel(id) \
				or not CharacterDB.apparel_fits(_body_id, id):
			continue
		seen[id] = true
		if filtered and not _filter.is_empty() and ItemDB.slot_of(id) != _filter:
			continue
		entries.append({"id": id, "index": index})
	return entries


func _on_apparel_hold_completed(tile: DesignerApparelTile) -> void:
	toggle_apparel(tile.item_id())


## Toggles one catalogue garment. Public so visual and contract harnesses can
## exercise the same operation without synthesising a timed pointer hold.
func toggle_apparel(item_id: String) -> void:
	if _equipment == null or item_id.is_empty() or not ItemDB.is_apparel(item_id) \
			or not CharacterDB.apparel_fits(_body_id, item_id):
		return
	var body_slot := ItemDB.slot_of(item_id)
	for index in _equipment.size():
		if _equipment.filter_of(index) != body_slot:
			continue
		_equipment.set_item(
			index,
			"" if _equipment.get_item(index) == item_id else item_id
		)
		return


func _on_icon_ready(_id: String, _texture: Texture2D) -> void:
	for slot: RedItemSlot in _hero_slots:
		slot.queue_redraw()
	for tile: DesignerApparelTile in _apparel_tiles:
		tile.queue_redraw()


func _fit_apparel_columns() -> void:
	if _apparel_grid == null or _apparel_scroll == null:
		return
	var available := _apparel_scroll.size.x - 8.0
	if available <= 0.0:
		return
	_apparel_grid.columns = maxi(
		2,
		int((available + TILE_GAP) / (TILE_EDGE + TILE_GAP))
	)


func _layout_background() -> void:
	if _background == null:
		return
	# A horizontal image is turned into the editor's tall card rather than
	# stretched into it in its original direction.
	_background.rotation = PI * 0.5
	_background.pivot_offset = Vector2.ZERO
	_background.position = Vector2(size.x, 0.0)
	_background.size = Vector2(size.y, size.x)


func set_player_name(value: String) -> void:
	_player_name = value
	if _name_field != null and not _name_field.has_focus():
		_name_field.text = value


func set_skin(value: String) -> void:
	_skin_id = CharacterDB.sanitize_skin(_body_id, value)
	_fill_skin_row()


func set_tints(value: Dictionary) -> void:
	_tints = value.duplicate(true)
	_update_tint_target()


func current_tab() -> Tab:
	return _tab


func worn_slots() -> ItemContainer:
	return _equipment


func apparel_catalogue() -> ItemContainer:
	return _catalogue


func apparel_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry: Dictionary in _apparel_entries(false):
		ids.append(String(entry["id"]))
	return ids


func _filter_button(
		label_text: String,
		glyph_kind: RedMenuGlyph.Glyph,
		active: bool
	) -> Button:
	var button := _button(label_text, active)
	button.custom_minimum_size = Vector2(98.0, 44.0)
	button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for state: StringName in [
			&"normal", &"hover", &"pressed", &"focus", &"disabled"
	]:
		var box := button.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			box.content_margin_left = 39.0
	var lane := CenterContainer.new()
	lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.anchor_bottom = 1.0
	lane.offset_right = 38.0
	button.add_child(lane)
	var glyph := RedMenuGlyph.new()
	glyph.glyph = glyph_kind
	glyph.custom_minimum_size = Vector2(28.0, 28.0)
	lane.add_child(glyph)
	return button


func _button(text: String, active := false) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_button(button, active)
	return button


func _style_button(button: Button, active: bool) -> void:
	var accent := GREEN if active else RED
	var fill := Color(0.0, 0.15, 0.04, 0.78) if active else BLACK_68
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(&"font_color", GREEN_TEXT if active else RED_TEXT)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_color_override(&"font_disabled_color", Color(RED_MUTED, 0.36))
	button.add_theme_stylebox_override(
		&"normal", _style(fill, Color(accent, 0.94), 2 if active else 1, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover", _style(BLACK_86, GREEN, 2, 8.0, Color(GREEN, 0.15), 4)
	)
	button.add_theme_stylebox_override(
		&"pressed", _style(Color(0.0, 0.2, 0.06, 0.88), GREEN, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"focus", _style(Color.TRANSPARENT, accent, 1, 7.0)
	)
	button.add_theme_stylebox_override(
		&"disabled", _style(BLACK_42, Color(RED_MUTED, 0.30), 1, 8.0)
	)


func _style_input(field: LineEdit) -> void:
	field.add_theme_font_size_override(&"font_size", 14)
	field.add_theme_color_override(&"font_color", GREEN_TEXT)
	field.add_theme_color_override(&"font_placeholder_color", Color(RED_MUTED, 0.72))
	field.add_theme_color_override(&"caret_color", GREEN)
	field.add_theme_color_override(&"selection_color", Color(GREEN, 0.42))
	field.add_theme_stylebox_override(
		&"normal", _style(BLACK_68, Color(RED, 0.92), 1, 10.0)
	)
	field.add_theme_stylebox_override(
		&"focus", _style(BLACK_86, GREEN, 2, 9.0)
	)


func _section_heading(text: String, font_size := 14) -> Label:
	return _label(text, font_size, RED_BRIGHT)


func _label(
		text: String,
		font_size: int,
		colour: Color,
		wrap := false
	) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_color_override(&"font_outline_color", Color(0.08, 0.0, 0.0, 0.96))
	label.add_theme_constant_override(&"outline_size", 1)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _rule() -> PanelContainer:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(
		&"panel", _style(Color(RED, 0.48), RED_BRIGHT, 1, 0.0)
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
		_style(Color(0.0, 0.0, 0.0, 0.56), Color(RED_BRIGHT, 0.92), 1, padding)
	)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = BLACK_42
	glow.border_color = Color(RED, 0.94)
	glow.border_width = 1.5
	glow.glow_intensity = 1.15
	glow.glow_spread = 8.0
	glow.glow_layers = 4
	frame.add_child(content)
	return frame


func _style(
		fill: Color,
		border: Color,
		border_width: int,
		padding: float,
		shadow := Color.TRANSPARENT,
		shadow_size := 0
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


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
