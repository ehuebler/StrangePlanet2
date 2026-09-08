class_name PlayerDesignerPanel
extends Control

## Home-screen character designer in the same red/green/black language as the
## in-game Hero and Hats pages.
##
## The live character standing beside this panel is the preview. This control
## therefore contains only appearance controls: the character grid, texture and
## skin tint on Character, then owned hats and capes bought from Unlocks with
## matching tinters.

signal name_entered(value: String)
signal skin_picked(skin_id: String)
signal body_picked(body_id: String)
signal hat_unlocked(item_id: String)
signal tint_picked(target: String, colour: Color)
signal tint_cleared(target: String)

enum Tab {
	HERO,
	APPAREL,
	CAPES,
}

const BACKGROUND := preload("res://assets/runtime/ui/menu_background.png")
const TINT_BODY := "body"
const TAB_LABELS: Array[String] = ["Character", "Hats", "Capes"]
const TINT_HAT := "hat"
const TINT_CAPE := "cape"
const TINT_OUTLINE := SurfaceSkin.TINT_OUTLINE

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
const UPPER_SHARE := 3.0
const TINT_SHARE := 1.0
const FACE_EDGE := 72.0

const APPAREL_FILTERS: Array[Dictionary] = [
	{"id": "hat", "label": "Hats", "glyph": RedMenuGlyph.Glyph.HAT},
]
const APPAREL_GLYPHS := [
	RedMenuGlyph.Glyph.HAT,
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
var _hero_tint_target := TINT_BODY
var _built := false

var _background: TextureRect
var _tabs: HBoxContainer
var _page_host: MarginContainer
var _hero_page: VBoxContainer
var _apparel_page: VBoxContainer
var _cape_page: VBoxContainer
var _name_field: LineEdit
var _skin_row: HBoxContainer
var _tint_caption: Label
var _clear_tint: Button
var _wheel: ColourWheel
var _tint_mode_tint: Button
var _tint_mode_outline: Button
var _hero_slots: Array[RedItemSlot] = []
var _hero_glyphs: Array[RedMenuGlyph] = []
var _character_grid: GridContainer
var _hat_wheel: ColourWheel
var _hat_tint_caption: Label
var _clear_hat_tint: Button
var _cape_wheel: ColourWheel
var _cape_tint_caption: Label
var _clear_cape_tint: Button
var _apparel_grid: GridContainer
var _apparel_scroll: ScrollContainer
var _apparel_count: Label
var _empty_apparel: Label
var _apparel_tiles: Array[DesignerApparelTile] = []
var _cape_grid: GridContainer
var _cape_scroll: ScrollContainer
var _cape_count: Label
var _empty_cape: Label
var _cape_tiles: Array[DesignerApparelTile] = []
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
	CrtType.watch(self)
	_connect_sources()
	refresh()
	resized.connect(_layout_background)
	call_deferred(&"_layout_background")
	call_deferred(&"_fit_apparel_columns")
	call_deferred(&"_fit_cape_columns")


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
	_cape_page = _build_cape_page()
	_page_host.add_child(_cape_page)

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

	var roster_column := VBoxContainer.new()
	roster_column.name = "DesignerEquippedContent"
	roster_column.add_theme_constant_override(&"separation", 8)
	var identity := HBoxContainer.new()
	identity.name = "DesignerIdentity"
	identity.add_theme_constant_override(&"separation", 12)
	var title := _label("CHARACTER", 23, RED_BRIGHT)
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
	roster_column.add_child(_glow_frame(identity, "DesignerIdentityFrame", 6.0))
	roster_column.add_child(_section_heading("CHARACTERS  //  TAP A TILE"))
	roster_column.add_child(_rule())
	_character_grid = GridContainer.new()
	_character_grid.name = "DesignerEquippedSlots"
	_character_grid.columns = 4
	_character_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_grid.add_theme_constant_override(&"h_separation", 8)
	_character_grid.add_theme_constant_override(&"v_separation", 8)
	roster_column.add_child(_character_grid)
	roster_column.add_child(_label("SKIN TEXTURE //", 12, RED_BRIGHT))
	_skin_row = HBoxContainer.new()
	_skin_row.name = "DesignerSkinPicker"
	_skin_row.add_theme_constant_override(&"separation", 7)
	roster_column.add_child(_skin_row)
	var equipped_frame := _glow_frame(
		roster_column, "DesignerEquippedFrame", 8.0
	)
	page.add_child(equipped_frame)

	var picker_column := VBoxContainer.new()
	picker_column.name = "DesignerPickerContent"
	picker_column.add_theme_constant_override(&"separation", 6)
	var picker_row := _build_tint_row(
		"TINT //",
		"DesignerNoTint",
		"DesignerTintTarget",
		"DesignerTintPicker",
		"DesignerColourWheel",
		"body"
	)
	picker_column.add_child(picker_row)
	var picker_frame := _glow_frame(
		picker_column, "DesignerAppearanceFrame", 8.0
	)
	page.add_child(picker_frame)
	_apply_page_split(equipped_frame, picker_frame)
	return page


func _build_apparel_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "DesignerApparelPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", 8)

	var catalogue_column := VBoxContainer.new()
	catalogue_column.name = "DesignerApparelCatalogue"
	catalogue_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_theme_constant_override(&"separation", 8)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var title := _label("HATS", 23, RED_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_apparel_count = _label("00 OWNED", 11, RED_MUTED)
	_apparel_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apparel_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_apparel_count)
	catalogue_column.add_child(_glow_frame(header, "DesignerApparelHeader", 10.0))

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
		"BUY HATS IN UPLOCKS.",
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

	var tint_column := VBoxContainer.new()
	tint_column.name = "DesignerHatTintContent"
	tint_column.add_theme_constant_override(&"separation", 6)
	tint_column.add_child(_build_tint_row(
		"HAT TINT //",
		"DesignerHatNoTint",
		"DesignerHatTintTarget",
		"DesignerHatTintPicker",
		"DesignerHatColourWheel",
		"hat"
	))
	var tint_frame := _glow_frame(tint_column, "DesignerHatTintFrame", 8.0)
	page.add_child(tint_frame)
	_apply_page_split(catalogue_frame, tint_frame)
	return page


func _build_cape_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "DesignerCapePage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override(&"separation", 8)

	var catalogue_column := VBoxContainer.new()
	catalogue_column.name = "DesignerCapeCatalogue"
	catalogue_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_theme_constant_override(&"separation", 8)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var title := _label("CAPES", 23, RED_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_cape_count = _label("00 OWNED", 11, RED_MUTED)
	_cape_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cape_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_cape_count)
	catalogue_column.add_child(_glow_frame(header, "DesignerCapeHeader", 10.0))

	_cape_scroll = ScrollContainer.new()
	_cape_scroll.name = "DesignerOwnedCapeScroll"
	_cape_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cape_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cape_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_child(_cape_scroll)
	_cape_grid = GridContainer.new()
	_cape_grid.name = "DesignerOwnedCapeGrid"
	_cape_grid.columns = 5
	_cape_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cape_grid.add_theme_constant_override(&"h_separation", int(TILE_GAP))
	_cape_grid.add_theme_constant_override(&"v_separation", int(TILE_GAP))
	_cape_scroll.add_child(_cape_grid)
	_cape_grid.resized.connect(_fit_cape_columns)

	_empty_cape = _label(
		"BUY CAPES IN UPLOCKS.",
		16,
		RED_MUTED,
		true
	)
	_empty_cape.name = "DesignerCapeEmpty"
	_empty_cape.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_cape.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_cape.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_column.add_child(_empty_cape)

	var catalogue_frame := _glow_frame(
		catalogue_column, "DesignerCapeCatalogueFrame", 11.0
	)
	catalogue_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(catalogue_frame)

	var tint_column := VBoxContainer.new()
	tint_column.name = "DesignerCapeTintContent"
	tint_column.add_theme_constant_override(&"separation", 6)
	tint_column.add_child(_build_tint_row(
		"CAPE TINT //",
		"DesignerCapeNoTint",
		"DesignerCapeTintTarget",
		"DesignerCapeTintPicker",
		"DesignerCapeColourWheel",
		"cape"
	))
	var tint_frame := _glow_frame(tint_column, "DesignerCapeTintFrame", 8.0)
	page.add_child(tint_frame)
	_apply_page_split(catalogue_frame, tint_frame)
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
	if _cape_page != null:
		_cape_page.visible = _tab == Tab.CAPES
	_tint_target = _tab_tint_target()
	_update_tint_target()
	if _tab == Tab.APPAREL:
		_fill_apparel()
	elif _tab == Tab.CAPES:
		_fill_capes()


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
	_fill_character_grid()
	_update_tint_target()
	_fill_apparel()
	_fill_capes()


func _fill_character_grid() -> void:
	if _character_grid == null:
		return
	_clear(_character_grid)
	# One offered body for now: the settler painted as Noct.
	var body_id := CharacterDB.DEFAULT_BODY
	_character_grid.add_child(_character_tile(body_id, body_id == _body_id))


func _character_tile(body_id: String, selected: bool) -> Button:
	var button := Button.new()
	button.name = "DesignerCharacter_%s" % body_id
	button.text = ""
	button.custom_minimum_size = Vector2(108.0, 152.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var special := CharacterDB.character_trait(body_id)
	if not special.is_empty():
		button.tooltip_text = str(special.get("description", ""))
	_style_button(button, selected)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override(&"separation", 4)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 8.0
	stack.offset_top = 8.0
	stack.offset_right = -8.0
	stack.offset_bottom = -8.0
	button.add_child(stack)
	var face_host := Control.new()
	face_host.name = "DesignerCharacterFaceHost"
	face_host.custom_minimum_size = Vector2(FACE_EDGE, FACE_EDGE)
	face_host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	face_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(face_host)
	var face := TextureRect.new()
	face.name = "DesignerCharacterFace"
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.texture = CharacterDB.face_texture(body_id, _skin_id)
	face_host.add_child(face)
	var starters := CharacterDB.starting_abilities(body_id)
	var icon_edge := 22.0
	var icon_gap := 2.0
	var icon_count := 1 + (0 if starters.is_empty() else 1)
	var icon_row := HBoxContainer.new()
	icon_row.name = "DesignerCharacterIcons"
	icon_row.add_theme_constant_override(&"separation", int(icon_gap))
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	icon_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	icon_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row_w := icon_edge * float(icon_count) + icon_gap * float(maxi(icon_count - 1, 0))
	icon_row.offset_left = -row_w
	icon_row.offset_top = -icon_edge
	icon_row.offset_right = 0.0
	icon_row.offset_bottom = 0.0
	face_host.add_child(icon_row)
	var juke := TextureRect.new()
	juke.name = "DesignerCharacterJuke"
	juke.custom_minimum_size = Vector2(icon_edge, icon_edge)
	juke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	juke.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	juke.mouse_filter = Control.MOUSE_FILTER_IGNORE
	juke.texture = ItemDB.ability_icon(CrawlerProgress.STAT_JUKE)
	juke.tooltip_text = "Juke"
	icon_row.add_child(juke)
	if not starters.is_empty():
		var icon := TextureRect.new()
		icon.name = "DesignerCharacterAbility"
		icon.custom_minimum_size = Vector2(icon_edge, icon_edge)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = ItemDB.ability_icon(starters[0])
		icon.tooltip_text = ItemDB.title(starters[0])
		icon_row.add_child(icon)
	var caption := _label(
		CharacterDB.selector_title(body_id), 12, GREEN_TEXT if selected else RED_TEXT)
	caption.name = "DesignerCharacterTitle"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(caption)
	if not special.is_empty():
		var blurb := _label(
			str(special.get("short", "+2% DMG / LV")),
			8,
			GREEN_TEXT if selected else RED_MUTED
		)
		blurb.name = "DesignerCharacterTrait"
		blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(blurb)
	button.pressed.connect(func() -> void: _pick_body(body_id))
	return button


func _apply_page_split(upper: Control, tint: Control) -> void:
	upper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper.size_flags_stretch_ratio = UPPER_SHARE
	tint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tint.size_flags_stretch_ratio = TINT_SHARE


func _build_tint_row(
		heading: String,
		clear_name: String,
		caption_name: String,
		wheel_host_name: String,
		wheel_name: String,
		kind: String
	) -> HBoxContainer:
	var row := HBoxContainer.new()
	match kind:
		"hat":
			row.name = "DesignerHatPickers"
		"cape":
			row.name = "DesignerCapePickers"
		_:
			row.name = "DesignerPickers"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 12)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", 4)
	row.add_child(copy)
	var title := HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 8)
	if kind == "body":
		_tint_mode_tint = _button("TINT", true)
		_tint_mode_tint.name = "DesignerTintSelector"
		_tint_mode_tint.custom_minimum_size = Vector2(72.0, 32.0)
		_tint_mode_tint.pressed.connect(func() -> void:
			_set_hero_tint_target(TINT_BODY)
		)
		title.add_child(_tint_mode_tint)
		_tint_mode_outline = _button("OUTLINE")
		_tint_mode_outline.name = "DesignerOutlineSelector"
		_tint_mode_outline.custom_minimum_size = Vector2(108.0, 32.0)
		_tint_mode_outline.pressed.connect(func() -> void:
			_set_hero_tint_target(TINT_OUTLINE)
		)
		title.add_child(_tint_mode_outline)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_child(spacer)
	else:
		var heading_label := _label(heading, 12, RED_BRIGHT)
		heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_child(heading_label)
	var clear := _button("NO TINT")
	clear.name = clear_name
	clear.custom_minimum_size = Vector2(96.0, 32.0)
	clear.pressed.connect(_clear_selected_tint)
	title.add_child(clear)
	copy.add_child(title)
	var caption := _label("", 11, GREEN_TEXT, true)
	caption.name = caption_name
	copy.add_child(caption)
	var wheel_centre := CenterContainer.new()
	wheel_centre.name = wheel_host_name
	wheel_centre.custom_minimum_size.x = 132.0
	wheel_centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(wheel_centre)
	var wheel := ColourWheel.new()
	wheel.name = wheel_name
	wheel.picked.connect(_pick_tint)
	wheel_centre.add_child(wheel)
	match kind:
		"hat":
			_clear_hat_tint = clear
			_hat_tint_caption = caption
			_hat_wheel = wheel
		"cape":
			_clear_cape_tint = clear
			_cape_tint_caption = caption
			_cape_wheel = wheel
		_:
			_clear_tint = clear
			_tint_caption = caption
			_wheel = wheel
	return row


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
	_fill_character_grid()
	skin_picked.emit(_skin_id)


func _pick_body(body_id: String) -> void:
	var clean := CharacterDB.sanitize_body(body_id)
	if clean == _body_id:
		return
	_body_id = clean
	_skin_id = CharacterDB.sanitize_skin(_body_id, _skin_id)
	_fill_character_grid()
	_fill_skin_row()
	body_picked.emit(_body_id)


func _tab_tint_target() -> String:
	match _tab:
		Tab.APPAREL:
			return TINT_HAT
		Tab.CAPES:
			return TINT_CAPE
		_:
			return _hero_tint_target


func _set_hero_tint_target(target: String) -> void:
	_hero_tint_target = target
	_update_tint_target()


func _pick_tint(colour: Color) -> void:
	_tint_target = _tab_tint_target()
	_tints[_tint_target] = colour.to_html(false)
	_update_tint_target()
	tint_picked.emit(_tint_target, colour)


func _clear_selected_tint() -> void:
	_tint_target = _tab_tint_target()
	if not _tints.has(_tint_target):
		return
	_tints.erase(_tint_target)
	_update_tint_target()
	tint_cleared.emit(_tint_target)


func _update_tint_target() -> void:
	_tint_target = _tab_tint_target()
	var outlining := _hero_tint_target == TINT_OUTLINE
	var hero_active := _tints.has(_hero_tint_target)
	if _tint_caption != null:
		_tint_caption.text = "TARGET // %s\n%s" % [
			"OUTLINE" if outlining else "SKIN",
			"TINT ACTIVE" if hero_active else "AUTHORED COLOUR",
		]
	if _tint_mode_tint != null:
		_style_button(_tint_mode_tint, not outlining)
	if _tint_mode_outline != null:
		_style_button(_tint_mode_outline, outlining)
	if _hat_tint_caption != null:
		var worn := _equipped_in(TINT_HAT)
		var hat_title := ItemDB.title(worn).to_upper() if not worn.is_empty() else "NO HAT"
		_hat_tint_caption.text = "TARGET // %s\n%s" % [
			hat_title,
			"TINT ACTIVE" if _tints.has(TINT_HAT) else "AUTHORED COLOUR",
		]
	if _cape_tint_caption != null:
		var worn_cape := _equipped_in(TINT_CAPE)
		var cape_title := (
			ItemDB.title(worn_cape).to_upper() if not worn_cape.is_empty() else "NO CAPE"
		)
		_cape_tint_caption.text = "TARGET // %s\n%s" % [
			cape_title,
			"TINT ACTIVE" if _tints.has(TINT_CAPE) else "AUTHORED COLOUR",
		]
	if _clear_tint != null:
		_clear_tint.disabled = not hero_active
	if _clear_hat_tint != null:
		_clear_hat_tint.disabled = not _tints.has(TINT_HAT)
	if _clear_cape_tint != null:
		_clear_cape_tint.disabled = not _tints.has(TINT_CAPE)
	if _wheel != null:
		var fallback := SurfaceSkin.CAMERA_RIM_COLOR.to_html(false) \
			if outlining else "ffffff"
		_wheel.set_colour(Color.html(str(_tints.get(_hero_tint_target, fallback))))
	if _hat_wheel != null:
		_hat_wheel.set_colour(Color.html(str(_tints.get(TINT_HAT, "ffffff"))))
	if _cape_wheel != null:
		_cape_wheel.set_colour(Color.html(str(_tints.get(TINT_CAPE, "ffffff"))))


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
	_fill_gear(
		_apparel_grid,
		_apparel_scroll,
		_empty_apparel,
		_apparel_count,
		_apparel_tiles,
		"hat",
		"DesignerApparel",
		&"_fit_apparel_columns"
	)


func _fill_capes() -> void:
	_fill_gear(
		_cape_grid,
		_cape_scroll,
		_empty_cape,
		_cape_count,
		_cape_tiles,
		"cape",
		"DesignerCape",
		&"_fit_cape_columns"
	)


func _fill_gear(
		grid: GridContainer,
		scroll: ScrollContainer,
		empty: Label,
		count: Label,
		tiles: Array[DesignerApparelTile],
		slot: String,
		tile_prefix: String,
		fit_method: StringName
	) -> void:
	if grid == null or _catalogue == null:
		return
	_clear(grid)
	tiles.clear()
	var entries := _gear_entries(slot)
	if count != null:
		count.text = "%02d OWNED" % entries.size()
	if scroll != null:
		scroll.visible = not entries.is_empty()
	if empty != null:
		empty.visible = entries.is_empty()
	var icon_ids: Array = []
	for entry: Dictionary in entries:
		var id := String(entry["id"])
		var tile := DesignerApparelTile.new()
		tile.name = "%s_%s" % [tile_prefix, id]
		tile.set_edge(TILE_EDGE)
		tile.bind(_catalogue, int(entry["index"]))
		tile.placeholder = ""
		tile.equipped = _equipment != null and _equipment.find(id) >= 0
		tile.selected = tile.equipped
		tile.modulate = Color.WHITE
		tile.badge = "WORN" if tile.equipped else "HOLD"
		tile.tooltip_text = "%s\n%s" % [
			ItemDB.title(id).to_upper(),
			"HOLD TO UNEQUIP" if tile.equipped else "HOLD TO EQUIP",
		]
		tile.hold_completed.connect(_on_apparel_hold_completed)
		grid.add_child(tile)
		tiles.append(tile)
		icon_ids.append(id)
	if _icons != null:
		_icons.request(icon_ids)
	call_deferred(fit_method)


func _apparel_entries(filtered: bool) -> Array[Dictionary]:
	var slot := _filter if filtered and not _filter.is_empty() else "hat"
	if not filtered:
		slot = "hat"
	return _gear_entries(slot)


func _gear_entries(slot: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _catalogue == null:
		return entries
	var seen: Dictionary = {}
	for index in _catalogue.size():
		var id := _catalogue.get_item(index)
		if id.is_empty() or seen.has(id) or not ItemDB.is_apparel(id) \
				or not CharacterDB.apparel_fits(_body_id, id) \
				or ItemDB.slot_of(id) != slot \
				or not CrawlerMeta.owns_apparel(id):
			continue
		seen[id] = true
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
	if not CrawlerMeta.owns_apparel(item_id):
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
	for tile: DesignerApparelTile in _cape_tiles:
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


func _fit_cape_columns() -> void:
	if _cape_grid == null or _cape_scroll == null:
		return
	var available := _cape_scroll.size.x - 8.0
	if available <= 0.0:
		return
	_cape_grid.columns = maxi(
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


func set_body(value: String) -> void:
	_body_id = CharacterDB.sanitize_body(value)
	_skin_id = CharacterDB.sanitize_skin(_body_id, _skin_id)
	_fill_character_grid()
	_fill_skin_row()


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
	for entry: Dictionary in _gear_entries("hat"):
		ids.append(String(entry["id"]))
	return ids


func cape_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry: Dictionary in _gear_entries("cape"):
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
