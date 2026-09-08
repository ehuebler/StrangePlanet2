class_name RedHeroPage
extends VBoxContainer

## In-game hero overview for the red menu.
##
## The compressed portrait sits on the left with its hat and cape tiles in the
## upper corners, the juke tile at the lower left, and the live stat readout
## under the figure. The right column is the ability loadout: a four-slot
## hotbar, a scrolling library of known powers, and a description of the
## selected one. Click the worn hat, cape, or juke to read its description and
## effects in that same panel. Shift-click or drag a library tile onto the
## hotbar to assign it. There are no equip or drop buttons.

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const YELLOW := Color("ffd84a")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const BLACK_86 := Color(0.0, 0.0, 0.0, 0.86)

const NARROW_WIDTH := 900.0
const WIDE_HAT_EDGE := 64.0
const NARROW_HAT_EDGE := 52.0
const WIDE_HOTBAR_EDGE := 68.0
const NARROW_HOTBAR_EDGE := 52.0
const LIBRARY_EDGE := 72.0
const LIBRARY_GAP := 8.0

const HOTBAR_BADGES := ["1", "2", "3", "4"]

var _player: OnlinePlayer
var _equipment: ItemContainer
var _abilities: ItemContainer
var _backpack: ItemContainer
var _stats: PlayerStats
var _ability_library: ItemContainer

var _built := false
var _sources_connected := false
var _narrow := false
var _responsive_initialized := false
var _selected_ability_id := ""
var _selected_apparel_slot := ""
var _selected_apparel_id := ""

var _main_grid: BoxContainer
var _stats_frame: PanelContainer
var _stats_heading: Label
var _stats_scroll: ScrollContainer
var _stats_rows: VBoxContainer
var _status_rows: VBoxContainer
var _status_section: VBoxContainer
var _character_block: VBoxContainer
var _ability_column: VBoxContainer
var _hero_name: Label
var _preview: RedCharacterPreview
var _hat_slot: RedItemSlot
var _hat_glyph: RedMenuGlyph
var _cape_slot: RedItemSlot
var _cape_glyph: RedMenuGlyph
var _juke_slot: RedItemSlot
var _hotbar_frame: PanelContainer
var _hotbar_row: HBoxContainer
var _library_scroll: ScrollContainer
var _library_grid: GridContainer
var _description_body: Label
var _description_title: Label
var _description_scroll: ScrollContainer
var _icons: ItemIcons

var _hotbar_slots: Array[RedItemSlot] = []
var _library_slots: Array[RedItemSlot] = []


## Supplies the player whose live loadout this page presents. Configure the page
## before it enters the tree so the 3D preview can build the correct body once.
func configure(player: OnlinePlayer) -> void:
	_disconnect_sources()
	_player = player
	_capture_sources()
	if is_inside_tree():
		_connect_sources()
	if not _built:
		return
	_bind_slots()
	if _preview != null and _player != null:
		_preview.configure(
			_equipment,
			_player.body_id(),
			_player.skin_id(),
			_player.tints()
		)
	refresh()


## Re-reads the name, stats, hat, cape, hotbar and library. Menu code and visual
## harnesses may call this after changing player state directly.
func refresh() -> void:
	if not _built:
		return

	var player_name := "PLAYER"
	if _player != null:
		player_name = _player.display_name.strip_edges()
		if player_name.is_empty():
			player_name = "PLAYER"
	_hero_name.text = player_name.to_upper()

	_fill_stats()
	_fill_status_effects()
	_refresh_hat()
	_refresh_cape()
	_refresh_juke()
	_refresh_hotbar()
	_refresh_library()
	_fill_description()
	_fit_description_scroll()
	if _preview != null:
		if _player != null:
			_preview.set_tints(_player.tints())
		_preview.refresh()
	_request_icons()


func _init() -> void:
	name = "RedHeroPage"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(320.0, 360.0)


## The wide contents must not become the page's own minimum width: doing so
## would prevent a parent container from shrinking far enough to trigger the
## one-column layout. The scroll region owns overflow instead.
func _get_minimum_size() -> Vector2:
	return custom_minimum_size


func _enter_tree() -> void:
	_connect_sources()


func _ready() -> void:
	add_theme_constant_override(&"separation", 10)
	_build()
	_built = true
	refresh()
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	call_deferred(&"_update_responsive_layout")


func _exit_tree() -> void:
	_disconnect_sources()


func _capture_sources() -> void:
	if _player == null:
		_equipment = null
		_abilities = null
		_backpack = null
		_stats = null
		return
	_equipment = _player.equipment
	_abilities = _player.get("abilities") as ItemContainer
	_backpack = _player.backpack
	_stats = _player.stats


func _connect_sources() -> void:
	if _sources_connected:
		return
	for source: ItemContainer in [_equipment, _abilities, _backpack]:
		if source != null and not source.changed.is_connected(refresh):
			source.changed.connect(refresh)
	if _stats != null and not _stats.changed.is_connected(_on_stats_changed):
		_stats.changed.connect(_on_stats_changed)
	if _player != null and not _player.status_changed.is_connected(_on_status_changed):
		_player.status_changed.connect(_on_status_changed)
	_sources_connected = true


func _disconnect_sources() -> void:
	for source: ItemContainer in [_equipment, _abilities, _backpack]:
		if source != null and source.changed.is_connected(refresh):
			source.changed.disconnect(refresh)
	if _stats != null and _stats.changed.is_connected(_on_stats_changed):
		_stats.changed.disconnect(_on_stats_changed)
	if _player != null and _player.status_changed.is_connected(_on_status_changed):
		_player.status_changed.disconnect(_on_status_changed)
	_sources_connected = false


func _on_stats_changed(_id: StringName, _value: float) -> void:
	refresh()


func _on_status_changed(_id: StringName, _remaining: float) -> void:
	_fill_status_effects()


func _build() -> void:
	clip_contents = true
	_main_grid = BoxContainer.new()
	_main_grid.name = "HeroComposition"
	_main_grid.vertical = false
	_main_grid.alignment = BoxContainer.ALIGNMENT_BEGIN
	_main_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_grid.add_theme_constant_override(&"separation", 10)
	add_child(_main_grid)

	_character_block = _build_character_block()
	_main_grid.add_child(_character_block)

	_ability_column = _build_ability_column()
	_main_grid.add_child(_ability_column)

	_icons = ItemIcons.new()
	_icons.name = "ItemIcons"
	add_child(_icons)
	_icons.icon_ready.connect(_on_icon_ready)


func _build_character_block() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "HeroModel"
	column.custom_minimum_size.x = 168.0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	column.add_theme_constant_override(&"separation", 6)

	_hero_name = _label("PLAYER", 27, RED_BRIGHT)
	_hero_name.name = "HeroName"
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_hero_name)
	column.add_child(_rule())

	var stage := Control.new()
	stage.name = "CharacterStage"
	stage.custom_minimum_size = Vector2(168.0, 210.0)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stage.clip_contents = true

	var preview_center := Control.new()
	preview_center.name = "CharacterPreviewCenter"
	preview_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_center.clip_contents = true
	stage.add_child(preview_center)

	_preview = RedCharacterPreview.new()
	_preview.name = "CharacterPreview"
	_preview.view_size = Vector2(168.0, 210.0)
	_preview.hover_in_frame = true
	if _player != null:
		_preview.configure(
			_equipment,
			_player.body_id(),
			_player.skin_id(),
			_player.tints()
		)
	else:
		_preview.configure(null, CharacterDB.DEFAULT_BODY, "", {})
	preview_center.add_child(_preview)

	_hat_slot = RedItemSlot.new()
	_hat_slot.name = "HatSlot"
	_hat_slot.set_edge(WIDE_HAT_EDGE)
	_hat_slot.badge = "HAT"
	_hat_slot.placeholder = ""
	_hat_slot.draggable = false
	_hat_slot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hat_slot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hat_slot.offset_left = -(WIDE_HAT_EDGE + 10.0)
	_hat_slot.offset_top = 10.0
	_hat_slot.offset_right = -10.0
	_hat_slot.offset_bottom = WIDE_HAT_EDGE + 10.0
	_hat_slot.picked.connect(_on_hat_picked)
	_hat_slot.quick_move_requested.connect(_on_hat_quick_move)
	stage.add_child(_hat_slot)

	_hat_glyph = RedMenuGlyph.new()
	_hat_glyph.name = "EmptyGlyph_hat"
	_hat_glyph.glyph = RedMenuGlyph.Glyph.HAT
	_hat_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hat_glyph.offset_left = 12.0
	_hat_glyph.offset_top = 12.0
	_hat_glyph.offset_right = -12.0
	_hat_glyph.offset_bottom = -12.0
	_hat_slot.add_child(_hat_glyph)

	_cape_slot = RedItemSlot.new()
	_cape_slot.name = "CapeSlot"
	_cape_slot.set_edge(WIDE_HAT_EDGE)
	_cape_slot.badge = "CAPE"
	_cape_slot.placeholder = ""
	_cape_slot.draggable = false
	_cape_slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_cape_slot.offset_left = 10.0
	_cape_slot.offset_top = 10.0
	_cape_slot.offset_right = WIDE_HAT_EDGE + 10.0
	_cape_slot.offset_bottom = WIDE_HAT_EDGE + 10.0
	_cape_slot.picked.connect(_on_cape_picked)
	_cape_slot.quick_move_requested.connect(_on_cape_quick_move)
	stage.add_child(_cape_slot)

	_cape_glyph = RedMenuGlyph.new()
	_cape_glyph.name = "EmptyGlyph_cape"
	_cape_glyph.glyph = RedMenuGlyph.Glyph.CAPE
	_cape_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cape_glyph.offset_left = 12.0
	_cape_glyph.offset_top = 12.0
	_cape_glyph.offset_right = -12.0
	_cape_glyph.offset_bottom = -12.0
	_cape_slot.add_child(_cape_glyph)

	_juke_slot = RedItemSlot.new()
	_juke_slot.name = "JukeSlot"
	_juke_slot.set_edge(WIDE_HAT_EDGE)
	_juke_slot.badge = "JUKE"
	_juke_slot.placeholder = ""
	_juke_slot.draggable = false
	_juke_slot.accepts_drops = false
	_juke_slot.forced_item_id = CrawlerProgress.STAT_JUKE
	_juke_slot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_juke_slot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_juke_slot.offset_left = 10.0
	_juke_slot.offset_top = -(WIDE_HAT_EDGE + 10.0)
	_juke_slot.offset_right = WIDE_HAT_EDGE + 10.0
	_juke_slot.offset_bottom = -10.0
	_juke_slot.picked.connect(_on_juke_picked)
	stage.add_child(_juke_slot)

	var shell := VBoxContainer.new()
	shell.name = "CharacterShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override(&"separation", 6)
	shell.add_child(stage)

	_stats_frame = _build_stats_frame()
	_stats_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(_stats_frame)

	var preview_frame := _glow_frame(shell, "CharacterFrame", 3.0)
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview_frame)
	return column


func _build_ability_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "HeroAbilityColumn"
	column.custom_minimum_size.x = 360.0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 3.0
	column.add_theme_constant_override(&"separation", 10)

	column.add_child(_build_hotbar_block())
	column.add_child(_build_library_block())
	column.add_child(_build_description_block())
	return column


func _build_hotbar_block() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "HotbarContent"
	column.add_theme_constant_override(&"separation", 6)

	_hotbar_row = HBoxContainer.new()
	_hotbar_row.name = "HotbarSlots"
	_hotbar_row.add_theme_constant_override(&"separation", 7)
	_hotbar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_hotbar_row)

	for logical_index in HOTBAR_BADGES.size():
		var slot := RedItemSlot.new()
		var badge: String = HOTBAR_BADGES[logical_index]
		slot.name = "HotbarSlot_%s" % badge
		slot.set_meta(&"logical_input", badge)
		slot.set_edge(WIDE_HOTBAR_EDGE)
		slot.badge = badge
		slot.placeholder = "X"
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.interactive = true
		slot.draggable = true
		slot.picked.connect(_on_hotbar_picked)
		slot.quick_move_requested.connect(_on_hotbar_clear)
		slot.item_dropped.connect(_on_hotbar_dropped)
		_hotbar_row.add_child(slot)
		_hotbar_slots.append(slot)

	_hotbar_frame = _glow_frame(column, "HotbarFrame", 10.0)
	_hotbar_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_hotbar_slots()
	return _hotbar_frame


func _build_library_block() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "AbilityLibraryContent"
	column.add_theme_constant_override(&"separation", 6)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_library_scroll = ScrollContainer.new()
	_library_scroll.name = "AbilityLibraryScroll"
	_library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_library_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_scroll.custom_minimum_size.y = 150.0
	column.add_child(_library_scroll)

	_library_grid = GridContainer.new()
	_library_grid.name = "AbilityLibrarySlots"
	_library_grid.columns = 4
	_library_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_grid.add_theme_constant_override(&"h_separation", int(LIBRARY_GAP))
	_library_grid.add_theme_constant_override(&"v_separation", int(LIBRARY_GAP))
	_library_scroll.add_child(_library_grid)
	_library_grid.resized.connect(_fit_library_columns)

	var frame := _glow_frame(column, "AbilityLibraryFrame", 10.0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.2
	return frame


func _build_description_block() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "AbilityDescriptionContent"
	column.add_theme_constant_override(&"separation", 6)
	column.custom_minimum_size.y = 132.0

	_description_title = _label("NO ABILITY SELECTED", 16, RED_BRIGHT, true)
	_description_title.name = "AbilityDescriptionTitle"
	column.add_child(_description_title)
	column.add_child(_rule())

	_description_body = _label(
		"CLICK A POWER TO READ IT  //  DRAG OR SHIFT+CLICK INTO THE HOTBAR",
		11,
		RED_TEXT,
		true
	)
	_description_body.name = "AbilityDescriptionBody"
	column.add_child(_scroll_text(_description_body, "AbilityDescriptionScroll"))

	var frame := _glow_frame(column, "AbilityDescriptionFrame", 10.0)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 0.72
	return frame


func _build_stats_frame() -> PanelContainer:
	var column := VBoxContainer.new()
	column.name = "StatsContent"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 3)
	_stats_heading = _section_heading("PLAYER STATS  //  LIVE READOUT", 11)
	_stats_heading.name = "StatsHeading"
	column.add_child(_stats_heading)
	column.add_child(_rule())

	_stats_scroll = ScrollContainer.new()
	_stats_scroll.name = "StatsScroll"
	_stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stats_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_stats_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_scroll.clip_contents = true
	column.add_child(_stats_scroll)

	var stack := VBoxContainer.new()
	stack.name = "StatsStack"
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override(&"separation", 3)
	_stats_scroll.add_child(stack)

	_stats_rows = VBoxContainer.new()
	_stats_rows.name = "StatRows"
	_stats_rows.add_theme_constant_override(&"separation", 2)
	_stats_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(_stats_rows)

	_status_section = VBoxContainer.new()
	_status_section.name = "StatusSection"
	_status_section.add_theme_constant_override(&"separation", 6)
	_status_section.visible = false
	stack.add_child(_status_section)

	var status_heading := _section_heading("TEMPORARY EFFECTS  //  LIVE", 13)
	status_heading.name = "StatusHeading"
	_status_section.add_child(status_heading)
	_status_section.add_child(_rule())

	_status_rows = VBoxContainer.new()
	_status_rows.name = "StatusRows"
	_status_rows.add_theme_constant_override(&"separation", 5)
	_status_section.add_child(_status_rows)

	var frame := _glow_frame(column, "StatsFrame", 5.0)
	frame.visible = true
	frame.custom_minimum_size.y = 88.0
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.clip_contents = true
	return frame


func _bind_slots() -> void:
	if _hat_slot != null:
		_hat_slot.bind(_equipment, 0)
	if _cape_slot != null and _equipment != null and _equipment.size() > 1:
		_cape_slot.bind(_equipment, 1)
	_bind_hotbar_slots()


func _bind_hotbar_slots() -> void:
	if _hotbar_slots.size() != HOTBAR_BADGES.size():
		return
	for logical_index in _hotbar_slots.size():
		_hotbar_slots[logical_index].bind(_abilities, logical_index)


func _refresh_hat() -> void:
	if _hat_slot == null:
		return
	_hat_slot.bind(_equipment, 0)
	var id := _hat_slot.item_id()
	_hat_slot.equipped = not id.is_empty()
	_hat_slot.selected = _selected_apparel_slot == "hat"
	_hat_slot.tooltip_text = (
		"%s\nSHIFT+CLICK TO STOW" % ItemDB.title(id)
		if not id.is_empty()
		else "HAT // EMPTY"
	)
	if _hat_glyph != null:
		_hat_glyph.visible = id.is_empty()
	_hat_slot.queue_redraw()


func _refresh_cape() -> void:
	if _cape_slot == null:
		return
	if _equipment != null and _equipment.size() > 1:
		_cape_slot.bind(_equipment, 1)
	var id := _cape_slot.item_id()
	_cape_slot.equipped = not id.is_empty()
	_cape_slot.selected = _selected_apparel_slot == "cape"
	_cape_slot.tooltip_text = (
		"%s\nSHIFT+CLICK TO STOW" % ItemDB.title(id)
		if not id.is_empty()
		else "CAPE // EMPTY"
	)
	if _cape_glyph != null:
		_cape_glyph.visible = id.is_empty()
	_cape_slot.queue_redraw()


func _refresh_hotbar() -> void:
	for index in _hotbar_slots.size():
		var slot := _hotbar_slots[index]
		var id := slot.item_id()
		slot.equipped = not id.is_empty()
		slot.selected = id == _selected_ability_id and not id.is_empty()
		slot.tooltip_text = (
			"%s // %s" % [HOTBAR_BADGES[index], ItemDB.title(id)]
			if not id.is_empty()
			else "%s // EMPTY" % HOTBAR_BADGES[index]
		)
		slot.queue_redraw()


func _refresh_library() -> void:
	var ids := ItemDB.ability_ids()
	if _library_grid == null or _library_slots.size() != ids.size():
		_rebuild_library()
		return
	for index in ids.size():
		if _library_slots[index].item_id() != ids[index]:
			_rebuild_library()
			return
	_mark_library_selection()


func _rebuild_library() -> void:
	if _library_grid == null:
		return
	_clear_children(_library_grid)
	_library_slots.clear()
	var ids := ItemDB.ability_ids()
	var contents: Array = []
	for id: String in ids:
		contents.append(id)
	_ability_library = ItemContainer.new(contents.size(), contents)
	for index in _ability_library.size():
		_ability_library.set_filter(index, ItemDB.ABILITY)
		var id := _ability_library.get_item(index)
		var slot := RedItemSlot.new()
		slot.name = "AbilityLibrary_%s" % id
		slot.set_edge(LIBRARY_EDGE)
		slot.copy_on_drag = true
		slot.bind(_ability_library, index)
		slot.equipped = _abilities != null and _abilities.find(id) >= 0
		slot.selected = id == _selected_ability_id
		slot.tooltip_text = "%s\nDRAG OR SHIFT+CLICK TO ASSIGN" % ItemDB.title(id)
		slot.picked.connect(_on_library_picked)
		slot.quick_move_requested.connect(_on_library_quick_move)
		_library_grid.add_child(slot)
		_library_slots.append(slot)
	call_deferred(&"_fit_library_columns")


func _fill_description() -> void:
	if _description_title == null:
		return
	if not _selected_apparel_slot.is_empty():
		_fill_apparel_description()
		return
	var id := _selected_ability_id
	if id.is_empty() or not ItemDB.is_ability(id):
		_description_title.text = "NO ABILITY SELECTED"
		_description_body.text = (
			"CLICK A POWER, HAT, CAPE, OR JUKE TO READ IT  //  DRAG OR SHIFT+CLICK INTO THE HOTBAR"
		)
		return
	_description_title.text = ItemDB.title(id).to_upper()
	var description := ItemDB.description(id).strip_edges()
	if description.is_empty():
		description = "NO DESCRIPTION FILED."
	var lines: PackedStringArray = [description]
	var profile := ItemDB.ability_profile(id)
	if not profile.is_empty():
		lines.append("PROFILE //  %s" % profile)
	var written_stats := PackedStringArray()
	for line: String in ItemDB.stat_lines(id):
		written_stats.append(line.replace("\t", "  //  "))
	if not written_stats.is_empty():
		lines.append("STATS\n%s" % "\n".join(written_stats))
	_description_body.text = "\n\n".join(lines)


func _fill_apparel_description() -> void:
	if _description_title == null:
		return
	if _selected_apparel_slot == "juke":
		var juke := _juke_copy()
		_description_title.text = str(juke.get("title", "JUKE"))
		_description_body.text = str(juke.get("body", "NO DESCRIPTION FILED."))
		return
	if _selected_apparel_id.is_empty():
		if _selected_apparel_slot == "cape":
			_description_title.text = "NO CAPE EQUIPPED"
			_description_body.text = "WEAR A CAPE TO READ ITS DESCRIPTION AND EFFECTS HERE."
		else:
			_description_title.text = "NO HAT EQUIPPED"
			_description_body.text = "WEAR A HAT TO READ ITS DESCRIPTION AND EFFECTS HERE."
		return
	var copy := _apparel_copy(_selected_apparel_id, _selected_apparel_slot)
	_description_title.text = str(copy.get("title", "APPAREL"))
	_description_body.text = str(copy.get("body", "NO DESCRIPTION FILED."))


func _apparel_copy(id: String, slot_name: String) -> Dictionary:
	var progress := _player.crawler_progress if _player != null else null
	var title := ItemDB.title(id)
	var model := id
	var description := ItemDB.description(id).strip_edges()
	var effects := ""
	if slot_name == "hat" and progress != null:
		title = progress.hat_title(id)
		model = progress.hat_model(id)
		if model.is_empty():
			model = id
		var flavor := ItemDB.description(model).strip_edges()
		if not flavor.is_empty():
			description = flavor
		effects = CrawlerProgress.compose_hat_description(
			progress.hat_effects(id)).strip_edges()
	elif slot_name == "cape":
		if progress != null:
			var blurb := CrawlerProgress.cape_blurb(id, true).strip_edges()
			if not blurb.is_empty():
				description = blurb
		if progress != null and progress.cape_has_ability(id):
			effects = (
				"Q sparkles and bounces every hit back for a few seconds. "
				+ "Then it rests a long while."
			)
	if title.is_empty():
		title = id
	if description.is_empty():
		description = "NO DESCRIPTION FILED."
	var lines: PackedStringArray = [description]
	if not effects.is_empty():
		lines.append("EFFECTS\n%s" % effects)
	return {
		"title": title.to_upper(),
		"body": "\n\n".join(lines),
	}


func _select_apparel(slot_name: String, id: String) -> void:
	_selected_ability_id = ""
	_selected_apparel_slot = slot_name
	_selected_apparel_id = id
	_on_apparel_selected()
	_refresh_hat()
	_refresh_cape()
	_refresh_juke()
	_refresh_hotbar()
	_mark_library_selection()
	_fill_description()
	_fit_description_scroll()


func _on_apparel_selected() -> void:
	pass


func _clear_apparel_selection() -> void:
	if _selected_apparel_slot.is_empty() and _selected_apparel_id.is_empty():
		return
	_selected_apparel_slot = ""
	_selected_apparel_id = ""
	_refresh_hat()
	_refresh_cape()
	_refresh_juke()


func _assign_ability(id: String, dest := -1) -> void:
	if _abilities == null or not ItemDB.accepts_ability(id):
		return
	if dest < 0:
		dest = _abilities.first_accepting(id)
	if dest < 0:
		dest = 0
	if dest >= _abilities.size():
		return
	_abilities.set_item(dest, id)
	_selected_ability_id = id


func _on_library_picked(slot: RedItemSlot) -> void:
	_clear_apparel_selection()
	_selected_ability_id = slot.item_id()
	_refresh_hotbar()
	_mark_library_selection()
	_fill_description()


func _on_library_quick_move(slot: RedItemSlot) -> void:
	var id := slot.item_id()
	if id.is_empty():
		return
	_clear_apparel_selection()
	_selected_ability_id = id
	_assign_ability(id)
	refresh()


func _on_hotbar_picked(slot: RedItemSlot) -> void:
	_clear_apparel_selection()
	_selected_ability_id = slot.item_id()
	_refresh_hotbar()
	_mark_library_selection()
	_fill_description()


func _on_hotbar_clear(slot: RedItemSlot) -> void:
	if slot.container != _abilities:
		return
	var id := slot.item_id()
	slot.container.set_item(slot.index, "")
	if _selected_ability_id == id:
		_selected_ability_id = ""
	refresh()


func _on_hotbar_dropped(_target: RedItemSlot, source: RedItemSlot) -> void:
	var id := source.item_id()
	if id.is_empty():
		return
	_clear_apparel_selection()
	_selected_ability_id = id
	_fill_description()


func _on_hat_picked(slot: RedItemSlot) -> void:
	_select_apparel("hat", slot.item_id() if slot != null else "")


func _on_hat_quick_move(slot: RedItemSlot) -> void:
	if slot.container != _equipment or _backpack == null:
		return
	var id := slot.item_id()
	if id.is_empty():
		return
	if not ItemContainer.quick_move(_equipment, slot.index, _backpack):
		_equipment.set_item(slot.index, "")
	refresh()


func _on_cape_picked(slot: RedItemSlot) -> void:
	_select_apparel("cape", slot.item_id() if slot != null else "")


func _on_cape_quick_move(slot: RedItemSlot) -> void:
	_on_hat_quick_move(slot)


func _on_juke_picked(_slot: RedItemSlot) -> void:
	_select_apparel("juke", CrawlerProgress.STAT_JUKE)


func _refresh_juke() -> void:
	if _juke_slot == null:
		return
	_juke_slot.forced_item_id = CrawlerProgress.STAT_JUKE
	_juke_slot.equipped = true
	_juke_slot.selected = _selected_apparel_slot == "juke"
	_juke_slot.tooltip_text = "Juke\nCLICK TO READ"
	_juke_slot.queue_redraw()


func _juke_copy() -> Dictionary:
	var cooldown := CrawlerProgress.JUKE_COOLDOWN_BASE
	var distance := CrawlerProgress.JUKE_DISTANCE_BASE
	if _player != null:
		cooldown = _player.juke_cooldown()
		distance = _player.juke_distance()
	var description := ItemDB.description(CrawlerProgress.STAT_JUKE).strip_edges()
	if description.is_empty():
		description = "A short invulnerable dash. Press F to slip aside."
	var effects := "Cooldown  //  %.2fs\nDistance  //  %.1f m\nHits miss you during the dash." \
		% [cooldown, distance]
	return {
		"title": "JUKE",
		"body": "%s\n\nEFFECTS\n%s" % [description, effects],
	}


func _mark_library_selection() -> void:
	for slot: RedItemSlot in _library_slots:
		var id := slot.item_id()
		slot.selected = id == _selected_ability_id
		slot.equipped = _abilities != null and _abilities.find(id) >= 0
		slot.queue_redraw()


func _fill_stats() -> void:
	if _stats_rows == null:
		return
	_clear_children(_stats_rows)
	if _stats_heading != null:
		_stats_heading.text = "PLAYER STATS  //  LIVE READOUT"
	if _stats == null:
		_stats_rows.add_child(_label("NO STAT DATA", 12, RED_MUTED))
		return

	for row_variant: Variant in CrawlerMeta.hero_stat_rows():
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row := row_variant as Dictionary
		_add_stat_row(
			str(row.get("id", "")),
			str(row.get("title", "")),
			str(row.get("description", "")),
			str(row.get("text", "")),
			str(row.get("kind", ""))
		)


func _add_stat_row(id_text: String, title_text: String, description: String,
		value_text: String, kind := "") -> void:
	var special := kind == "trait"
	var row_panel := PanelContainer.new()
	row_panel.name = "Stat_%s" % id_text
	row_panel.tooltip_text = description
	row_panel.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(YELLOW if special else RED, 0.55 if special else 0.42),
			1, 3.0)
	)
	_stats_rows.add_child(row_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	row_panel.add_child(row)

	var title := _label(title_text, 8, YELLOW if special else RED_TEXT)
	title.add_theme_constant_override(&"outline_size", 1)
	title.name = "Stat_%s_Name" % id_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var value := _label(value_text, 9, GREEN)
	value.add_theme_constant_override(&"outline_size", 1)
	value.name = "Stat_%s_Value" % id_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)


func _fill_status_effects() -> void:
	if _status_rows == null or _status_section == null:
		return
	_clear_children(_status_rows)
	var rows: Array = []
	if _player != null:
		rows = _player.status_rows()
	_status_section.visible = not rows.is_empty()
	if rows.is_empty():
		return
	for row_variant: Variant in rows:
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var row_panel := PanelContainer.new()
		row_panel.name = "Status_%s" % String(row.get("id", ""))
		row_panel.tooltip_text = String(row.get("description", ""))
		row_panel.add_theme_stylebox_override(
			&"panel",
			_style(BLACK_42, Color(YELLOW, 0.55), 1, 7.0)
		)
		_status_rows.add_child(row_panel)

		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 12)
		row_panel.add_child(line)

		var title := _label(String(row.get("title", "")), 12, YELLOW)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(title)

		var value := _label(
			"%.1f s" % float(row.get("remaining", 0.0)),
			16,
			GREEN
		)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)


func _format_stat_number(id: StringName, value: float) -> String:
	var precision := 0
	var definition: Variant = PlayerStats.STATS.get(String(id), {})
	if definition is Dictionary:
		precision = maxi(int((definition as Dictionary).get("precision", 0)), 0)
	return "%.*f" % [precision, value]


func _request_icons() -> void:
	if _icons == null:
		return
	var ids: Array = []
	for source: ItemContainer in [_equipment, _abilities]:
		if source == null:
			continue
		for id: String in source.items():
			if not id.is_empty() and not ids.has(id):
				ids.append(id)
	for id: String in ItemDB.ability_ids():
		if not ids.has(id):
			ids.append(id)
	if not ids.has(CrawlerProgress.STAT_JUKE):
		ids.append(CrawlerProgress.STAT_JUKE)
	_icons.request(ids)


func _on_icon_ready(_id: String, _texture: Texture2D) -> void:
	if _hat_slot != null:
		_hat_slot.queue_redraw()
	if _cape_slot != null:
		_cape_slot.queue_redraw()
	if _juke_slot != null:
		_juke_slot.queue_redraw()
	for slot: RedItemSlot in _hotbar_slots:
		slot.queue_redraw()
	for slot: RedItemSlot in _library_slots:
		slot.queue_redraw()


func _update_responsive_layout() -> void:
	if not _built:
		return
	var available_width := size.x
	if available_width <= 0.0:
		available_width = get_viewport_rect().size.x
	var narrow := available_width < NARROW_WIDTH
	if _responsive_initialized and narrow == _narrow:
		_fit_library_columns()
		return
	_responsive_initialized = true
	_narrow = narrow

	_main_grid.vertical = narrow
	_character_block.custom_minimum_size.x = 0.0 if narrow else 168.0
	_character_block.size_flags_stretch_ratio = 0.0 if narrow else 1.0
	_ability_column.custom_minimum_size.x = 0.0 if narrow else 360.0
	_ability_column.size_flags_stretch_ratio = 1.0 if narrow else 3.0
	var preview_min := Vector2(150.0, 180.0) if narrow else Vector2(168.0, 210.0)
	_preview.custom_minimum_size = preview_min
	var stage := _character_block.find_child("CharacterStage", true, false) as Control
	if stage != null:
		stage.custom_minimum_size = preview_min

	var hat_edge := NARROW_HAT_EDGE if narrow else WIDE_HAT_EDGE
	if _hat_slot != null:
		_hat_slot.set_edge(hat_edge)
		_hat_slot.offset_left = -(hat_edge + 10.0)
		_hat_slot.offset_top = 10.0
		_hat_slot.offset_right = -10.0
		_hat_slot.offset_bottom = hat_edge + 10.0
	if _cape_slot != null:
		_cape_slot.set_edge(hat_edge)
		_cape_slot.offset_left = 10.0
		_cape_slot.offset_top = 10.0
		_cape_slot.offset_right = hat_edge + 10.0
		_cape_slot.offset_bottom = hat_edge + 10.0
	if _juke_slot != null:
		_juke_slot.set_edge(hat_edge)
		_juke_slot.offset_left = 10.0
		_juke_slot.offset_top = -(hat_edge + 10.0)
		_juke_slot.offset_right = hat_edge + 10.0
		_juke_slot.offset_bottom = -10.0
	for slot: RedItemSlot in _hotbar_slots:
		slot.set_edge(NARROW_HOTBAR_EDGE if narrow else WIDE_HOTBAR_EDGE)
	_fit_library_columns()


func _fit_library_columns() -> void:
	if _library_grid == null or _library_scroll == null:
		return
	var available := _library_scroll.size.x - 8.0
	if available <= 0.0:
		return
	_library_grid.columns = maxi(
		3,
		int((available + LIBRARY_GAP) / (LIBRARY_EDGE + LIBRARY_GAP))
	)


func _section_heading(text: String, font_size := 16) -> Label:
	var heading := _label(text, font_size, RED_BRIGHT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return heading


func _scroll_text(label: Label, node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(label)
	scroll.resized.connect(_fit_description_scroll)
	_description_scroll = scroll
	return scroll


func _fit_description_scroll() -> void:
	if _description_scroll == null or _description_body == null:
		return
	var bar := _description_scroll.get_v_scroll_bar()
	var gutter := 18.0 if bar != null and bar.visible else 0.0
	_description_body.custom_minimum_size.x = maxf(
		_description_scroll.size.x - gutter, 8.0)
	_description_body.custom_minimum_size.y = 0.0
	if CrtType.host_of(_description_body) != null:
		return
	_description_body.reset_size()
	_description_body.custom_minimum_size.y = maxf(
		_description_body.get_minimum_size().y, 8.0)


func _label(
	text: String,
	font_size: int,
	color: Color,
	wrap: bool = false
) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(
		&"font_outline_color",
		Color(0.10, 0.0, 0.0, 0.94)
	)
	label.add_theme_constant_override(&"outline_size", 2)
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
		_style(
			BLACK_68,
			Color(RED_BRIGHT, 0.92),
			1,
			padding,
			Color(RED, 0.18),
			6
		)
	)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = BLACK_42
	glow.border_color = Color(RED, 0.9)
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
