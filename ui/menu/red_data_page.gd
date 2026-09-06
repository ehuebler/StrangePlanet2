class_name RedDataPage
extends VBoxContainer

## A self-contained red journal terminal with internal quest and achievement tabs.
##
## The page owns presentation only. [JournalDB] supplies every record and [Journal]
## supplies completion state. Call [method configure] before adding it to the tree.

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_40 := Color(0.0, 0.0, 0.0, 0.40)
const BLACK_54 := Color(0.0, 0.0, 0.0, 0.54)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const BLACK_75 := Color(0.0, 0.0, 0.0, 0.75)

const NARROW_WIDTH := 760.0
const LIST_MIN_WIDTH := 280.0
const DETAIL_MIN_WIDTH := 360.0
const LIST_NARROW_HEIGHT := 190.0
const DETAIL_NARROW_HEIGHT := 230.0

var _journal: Journal
var _kind: StringName = JournalDB.QUEST
var _built := false
var _narrow := false
var _responsive_initialized := false
var _syncing_filters := false

var _category_by_kind: Dictionary = {
	JournalDB.QUEST: "All",
	JournalDB.ACHIEVEMENT: "All",
}
var _search_by_kind: Dictionary = {
	JournalDB.QUEST: "",
	JournalDB.ACHIEVEMENT: "",
}
var _selected_by_kind: Dictionary = {
	JournalDB.QUEST: "",
	JournalDB.ACHIEVEMENT: "",
}
var _categories := PackedStringArray()

var _quest_tab: Button
var _achievement_tab: Button
var _header_count: Label
var _filter_grid: GridContainer
var _category_picker: OptionButton
var _search_edit: LineEdit
var _content_grid: GridContainer
var _list_frame: PanelContainer
var _detail_frame: PanelContainer
var _list_heading: Label
var _list_count: Label
var _list: VBoxContainer
var _detail: VBoxContainer


## Supplies the progress source. This is intended to be called before the page
## enters the tree, but reconnecting a page in a harness is also safe.
func configure(journal: Journal) -> void:
	if _journal == journal:
		return
	_disconnect_journal()
	_journal = journal
	if is_inside_tree():
		_connect_journal()
	if _built:
		_refresh_content()


## Changes the internal terminal tab. Unsupported kinds leave the current tab
## untouched so callers cannot put the page into a state JournalDB cannot display.
func set_kind(kind: StringName) -> void:
	if kind != JournalDB.QUEST and kind != JournalDB.ACHIEVEMENT:
		return
	if _kind == kind:
		if _built:
			_refresh_kind()
		return
	_kind = kind
	if _built:
		_refresh_kind()


## The JournalDB kind currently shown. Exposed for menu and test harnesses.
func current_kind() -> StringName:
	return _kind


func _init() -> void:
	name = "RedDataPage"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(360.0, 360.0)


func _enter_tree() -> void:
	_connect_journal()


func _ready() -> void:
	add_theme_constant_override(&"separation", 10)
	_build()
	_built = true
	_refresh_kind()
	resized.connect(_update_responsive_layout)
	call_deferred(&"_update_responsive_layout")


func _exit_tree() -> void:
	_disconnect_journal()


func _connect_journal() -> void:
	if _journal != null and not _journal.completed.is_connected(_on_completed):
		_journal.completed.connect(_on_completed)
	if _journal != null and not _journal.claimed.is_connected(_on_claimed):
		_journal.claimed.connect(_on_claimed)


func _disconnect_journal() -> void:
	if _journal != null and _journal.completed.is_connected(_on_completed):
		_journal.completed.disconnect(_on_completed)
	if _journal != null and _journal.claimed.is_connected(_on_claimed):
		_journal.claimed.disconnect(_on_claimed)


func _build() -> void:
	add_child(_build_header())
	add_child(_build_filters())
	add_child(_build_content())


func _build_header() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 12)
	column.add_child(title_row)

	var title := _label("DATA // JOURNAL DATABASE", 22, RED_BRIGHT)
	title.name = "DataHeading"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	_header_count = _label("00 / 00 COMPLETE", 12, RED_MUTED)
	_header_count.name = "CompletionCount"
	_header_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_header_count)

	var tabs := HBoxContainer.new()
	tabs.name = "KindTabs"
	tabs.add_theme_constant_override(&"separation", 8)
	column.add_child(tabs)

	_quest_tab = _tab_button("QUESTS", "QuestsTab")
	_quest_tab.pressed.connect(func() -> void: set_kind(JournalDB.QUEST))
	tabs.add_child(_quest_tab)

	_achievement_tab = _tab_button("ACHIEVEMENTS", "AchievementsTab")
	_achievement_tab.pressed.connect(func() -> void: set_kind(JournalDB.ACHIEVEMENT))
	tabs.add_child(_achievement_tab)

	return _glow_frame(column, 11.0)


func _build_filters() -> Control:
	_filter_grid = GridContainer.new()
	_filter_grid.name = "DataFilters"
	_filter_grid.columns = 2
	_filter_grid.add_theme_constant_override(&"h_separation", 10)
	_filter_grid.add_theme_constant_override(&"v_separation", 8)

	var category_group := VBoxContainer.new()
	category_group.add_theme_constant_override(&"separation", 4)
	category_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_grid.add_child(category_group)
	category_group.add_child(_label("CATEGORY FILTER", 11, RED_MUTED))

	_category_picker = OptionButton.new()
	_category_picker.name = "CategoryFilter"
	_category_picker.custom_minimum_size = Vector2(180.0, 40.0)
	_category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_picker.clip_text = true
	_style_picker(_category_picker)
	_category_picker.item_selected.connect(_on_category_selected)
	category_group.add_child(_category_picker)

	var search_group := VBoxContainer.new()
	search_group.add_theme_constant_override(&"separation", 4)
	search_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_grid.add_child(search_group)
	search_group.add_child(_label("SEARCH DATABASE", 11, RED_MUTED))

	_search_edit = LineEdit.new()
	_search_edit.name = "SearchField"
	_search_edit.custom_minimum_size = Vector2(220.0, 40.0)
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.placeholder_text = "SEARCH RECORDS..."
	_style_search(_search_edit)
	_search_edit.text_changed.connect(_on_search_changed)
	search_group.add_child(_search_edit)

	return _glow_frame(_filter_grid, 9.0)


func _build_content() -> Control:
	_content_grid = GridContainer.new()
	_content_grid.name = "DataSplit"
	_content_grid.columns = 2
	_content_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_grid.add_theme_constant_override(&"h_separation", 10)
	_content_grid.add_theme_constant_override(&"v_separation", 10)

	_list_frame = _build_list_frame()
	_list_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_frame.size_flags_stretch_ratio = 0.38
	_content_grid.add_child(_list_frame)

	_detail_frame = _build_detail_frame()
	_detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_frame.size_flags_stretch_ratio = 0.62
	_content_grid.add_child(_detail_frame)

	return _content_grid


func _build_list_frame() -> PanelContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override(&"separation", 8)
	column.add_child(heading_row)

	_list_heading = _label("QUEST RECORDS", 15, RED_BRIGHT)
	_list_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(_list_heading)

	_list_count = _label("00 VISIBLE", 10, RED_MUTED)
	_list_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_list_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading_row.add_child(_list_count)
	column.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.name = "EntryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_list = VBoxContainer.new()
	_list.name = "EntryList"
	_list.add_theme_constant_override(&"separation", 7)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	return _glow_frame(column, 10.0)


func _build_detail_frame() -> PanelContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_detail = VBoxContainer.new()
	_detail.name = "EntryDetail"
	_detail.add_theme_constant_override(&"separation", 9)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)

	return _glow_frame(scroll, 12.0)


func _refresh_kind() -> void:
	_style_tab(_quest_tab, _kind == JournalDB.QUEST)
	_style_tab(_achievement_tab, _kind == JournalDB.ACHIEVEMENT)
	_sync_filter_controls()
	_refresh_content()


func _sync_filter_controls() -> void:
	_syncing_filters = true
	_categories = JournalDB.categories_of_kind(_kind)
	var category := String(_category_by_kind.get(_kind, "All"))
	if not _categories.has(category):
		category = "All"
		_category_by_kind[_kind] = category

	_category_picker.clear()
	for category_name: String in _categories:
		_category_picker.add_item(category_name.to_upper())
	_category_picker.selected = maxi(_categories.find(category), 0)

	var search := String(_search_by_kind.get(_kind, ""))
	_search_edit.text = search
	_search_edit.placeholder_text = "SEARCH %s..." % _kind_plural()
	_syncing_filters = false


func _refresh_content() -> void:
	if not _built:
		return
	var ids := _visible_ids()
	var selected := String(_selected_by_kind.get(_kind, ""))
	if not ids.has(selected):
		selected = ids[0] if not ids.is_empty() else ""
		_selected_by_kind[_kind] = selected

	_fill_list(ids, selected)
	_fill_detail(selected)
	_update_counts(ids.size())


func _visible_ids() -> PackedStringArray:
	var visible := PackedStringArray()
	var category := String(_category_by_kind.get(_kind, "All"))
	var search := String(_search_by_kind.get(_kind, "")).strip_edges().to_lower()
	for id: String in JournalDB.ids_of_kind(_kind):
		if category != "All" and JournalDB.category_of(id) != category:
			continue
		if not search.is_empty():
			var haystack := "%s %s %s %s %s %s" % [
				JournalDB.title_of(id),
				JournalDB.summary_of(id),
				JournalDB.detail_of(id),
				JournalDB.category_of(id),
				JournalDB.landmark_of(id),
				JournalDB.reward_of(id),
			]
			if not haystack.to_lower().contains(search):
				continue
		visible.append(id)
	return visible


func _fill_list(ids: PackedStringArray, selected: String) -> void:
	_clear_children(_list)
	if ids.is_empty():
		var empty := _label("NO RECORDS MATCH THE ACTIVE FILTERS.", 12, RED_MUTED, true)
		empty.custom_minimum_size.y = 48.0
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(empty)
		return

	for id: String in ids:
		var done := _journal != null and _journal.is_done(id)
		var waiting := _journal != null and _journal.can_claim(id)
		var mark := "ACTIVE"
		if waiting:
			mark = "CLAIM"
		elif done:
			mark = "COMPLETE"
		var button := Button.new()
		button.name = "Entry_%s" % id
		button.text = "[ %s ]  //  %s" % [
			mark,
			JournalDB.title_of(id).to_upper(),
		]
		button.tooltip_text = JournalDB.summary_of(id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size.y = 44.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_entry_button(button, id == selected, done)
		var chosen: String = id
		button.pressed.connect(func() -> void: _select(chosen))
		_list.add_child(button)


func _fill_detail(id: String) -> void:
	_clear_children(_detail)
	if id.is_empty():
		var empty := _label(
			"NO RECORD SELECTED.\nADJUST CATEGORY OR SEARCH PARAMETERS.",
			14,
			RED_MUTED,
			true
		)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_detail.add_child(empty)
		return

	var done := _journal != null and _journal.is_done(id)
	var waiting := _journal != null and _journal.can_claim(id)
	var title := _label(
		JournalDB.title_of(id),
		23,
		GREEN if done else RED_BRIGHT,
		true
	)
	title.name = "RecordTitle"
	_detail.add_child(title)

	var state := "IN PROGRESS"
	if waiting:
		state = "UNCLAIMED"
	elif _journal != null and _journal.is_claimed(id):
		state = "CLAIMED"
	elif done:
		state = "COMPLETE"
	var status := _label(
		"%s  //  %s" % [JournalDB.category_of(id), state],
		12,
		GREEN_TEXT if done else RED_MUTED
	)
	status.name = "RecordStatus"
	_detail.add_child(status)
	_detail.add_child(_rule())

	_detail.add_child(_detail_section(
		"SUMMARY",
		JournalDB.summary_of(id),
		GREEN_TEXT if done else RED_TEXT
	))

	var detail_text := JournalDB.detail_of(id)
	if not detail_text.is_empty():
		_detail.add_child(_detail_section("DETAIL", detail_text, RED_TEXT))

	var landmark := JournalDB.landmark_of(id)
	if not landmark.is_empty():
		_detail.add_child(_detail_section(
			"LANDMARK",
			"%s // %s\nPROXIMITY THRESHOLD: %d M" % [
				JournalDB.title_of(id),
				landmark,
				roundi(JournalDB.within_of(id)),
			],
			RED_TEXT
		))

	var reward := JournalDB.reward_of(id)
	if not reward.is_empty():
		_detail.add_child(_detail_section("REWARD", reward, GREEN_TEXT))
	if waiting:
		var claim := _tab_button("CLAIM GEMS", "JournalClaim_%s" % id)
		claim.size_flags_horizontal = Control.SIZE_SHRINK_END
		claim.custom_minimum_size = Vector2(160.0, 42.0)
		_style_tab(claim, true)
		var chosen := id
		claim.pressed.connect(func() -> void: _claim(chosen))
		_detail.add_child(claim)


func _detail_section(title: String, text: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.name = "%sSection" % title.capitalize().replace(" ", "")
	panel.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_54, Color(RED, 0.38), 1, 9.0)
	)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	panel.add_child(column)
	column.add_child(_label("%s //" % title, 11, RED_BRIGHT))
	column.add_child(_label(text, 13, color, true))
	return panel


func _select(id: String) -> void:
	if not JournalDB.has_entry(id) or JournalDB.kind_of(id) != _kind:
		return
	_selected_by_kind[_kind] = id
	_refresh_content()


func _update_counts(visible_count: int) -> void:
	var total := JournalDB.ids_of_kind(_kind).size()
	var completed := _journal.done_count(_kind) if _journal != null else 0
	_header_count.text = "%02d / %02d COMPLETE" % [completed, total]
	_header_count.add_theme_color_override(
		&"font_color",
		GREEN if total > 0 and completed == total else RED_MUTED
	)
	_list_heading.text = "%s RECORDS" % _kind_singular()
	_list_count.text = "%02d VISIBLE" % visible_count


func _on_category_selected(index: int) -> void:
	if _syncing_filters or index < 0 or index >= _categories.size():
		return
	_category_by_kind[_kind] = _categories[index]
	_refresh_content()


func _on_search_changed(text: String) -> void:
	if _syncing_filters:
		return
	_search_by_kind[_kind] = text.strip_edges().to_lower()
	_refresh_content()


func _on_completed(_id: String) -> void:
	_refresh_content()


func _on_claimed(_id: String) -> void:
	_refresh_content()


func _claim(id: String) -> void:
	if _journal != null:
		_journal.claim(id)


func _update_responsive_layout() -> void:
	if not _built:
		return
	var available_width := size.x
	if available_width <= 0.0:
		available_width = get_viewport_rect().size.x
	var narrow := available_width < NARROW_WIDTH
	if _responsive_initialized and narrow == _narrow:
		return
	_responsive_initialized = true
	_narrow = narrow

	_filter_grid.columns = 1 if narrow else 2
	_content_grid.columns = 1 if narrow else 2
	if narrow:
		_list_frame.custom_minimum_size = Vector2(0.0, LIST_NARROW_HEIGHT)
		_detail_frame.custom_minimum_size = Vector2(0.0, DETAIL_NARROW_HEIGHT)
		_list_frame.size_flags_stretch_ratio = 0.43
		_detail_frame.size_flags_stretch_ratio = 0.57
	else:
		_list_frame.custom_minimum_size = Vector2(LIST_MIN_WIDTH, 0.0)
		_detail_frame.custom_minimum_size = Vector2(DETAIL_MIN_WIDTH, 0.0)
		_list_frame.size_flags_stretch_ratio = 0.38
		_detail_frame.size_flags_stretch_ratio = 0.62


func _kind_singular() -> String:
	return "QUEST" if _kind == JournalDB.QUEST else "ACHIEVEMENT"


func _kind_plural() -> String:
	return "QUESTS" if _kind == JournalDB.QUEST else "ACHIEVEMENTS"


func _tab_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text.to_upper()
	button.custom_minimum_size = Vector2(120.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _style_tab(button: Button, active: bool) -> void:
	var accent := GREEN if active else RED
	var fill := Color(0.0, 0.12, 0.035, 0.72) if active else BLACK_68
	button.add_theme_font_size_override(&"font_size", 14)
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN if active else RED_BRIGHT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_stylebox_override(
		&"normal",
		_style(fill, Color(accent, 0.92), 2 if active else 1, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_54, Color(accent, 1.0), 2, 8.0, Color(accent, 0.18), 4)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.16, 0.045, 0.75), GREEN, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, Color(accent, 0.92), 1, 7.0)
	)


func _style_entry_button(button: Button, selected: bool, done: bool) -> void:
	var accent := GREEN if selected or done else RED
	var fill := Color(0.0, 0.13, 0.035, 0.72) if selected else BLACK_68
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(
		&"font_color",
		GREEN_TEXT if selected or done else RED_TEXT
	)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_stylebox_override(
		&"normal",
		_style(fill, Color(accent, 0.72), 2 if selected else 1, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_54, Color(GREEN, 0.94), 2, 8.0, Color(GREEN, 0.15), 3)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.17, 0.05, 0.75), GREEN, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, GREEN, 1, 7.0)
	)


func _style_picker(picker: OptionButton) -> void:
	picker.add_theme_font_size_override(&"font_size", 12)
	picker.add_theme_color_override(&"font_color", RED_TEXT)
	picker.add_theme_color_override(&"font_hover_color", RED_BRIGHT)
	picker.add_theme_color_override(&"font_pressed_color", GREEN)
	picker.add_theme_color_override(&"font_focus_color", RED_BRIGHT)
	picker.add_theme_stylebox_override(
		&"normal",
		_style(BLACK_68, Color(RED, 0.72), 1, 8.0)
	)
	picker.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_54, RED_BRIGHT, 1, 8.0, Color(RED, 0.14), 3)
	)
	picker.add_theme_stylebox_override(
		&"pressed",
		_style(BLACK_75, GREEN, 1, 8.0)
	)
	picker.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, RED_BRIGHT, 1, 7.0)
	)

	var popup := picker.get_popup()
	popup.add_theme_font_size_override(&"font_size", 12)
	popup.add_theme_color_override(&"font_color", RED_TEXT)
	popup.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	popup.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_75, RED, 1, 6.0, Color(RED, 0.16), 4)
	)
	popup.add_theme_stylebox_override(
		&"hover",
		_style(Color(0.0, 0.15, 0.04, 0.75), GREEN, 1, 5.0)
	)


func _style_search(search: LineEdit) -> void:
	search.add_theme_font_size_override(&"font_size", 12)
	search.add_theme_color_override(&"font_color", RED_TEXT)
	search.add_theme_color_override(&"font_placeholder_color", RED_MUTED)
	search.add_theme_color_override(&"caret_color", GREEN)
	search.add_theme_color_override(&"selection_color", Color(GREEN, 0.28))
	search.add_theme_stylebox_override(
		&"normal",
		_style(BLACK_68, Color(RED, 0.72), 1, 8.0)
	)
	search.add_theme_stylebox_override(
		&"focus",
		_style(BLACK_75, GREEN, 2, 7.0, Color(GREEN, 0.14), 3)
	)
	search.add_theme_stylebox_override(
		&"read_only",
		_style(BLACK_54, Color(RED_MUTED, 0.55), 1, 8.0)
	)


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
	label.add_theme_color_override(&"font_outline_color", Color(0.1, 0.0, 0.0, 0.92))
	label.add_theme_constant_override(&"outline_size", 1)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _rule() -> Control:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(
		&"panel",
		_style(Color(RED, 0.46), Color(RED_BRIGHT, 0.72), 1, 0.0)
	)
	return rule


func _glow_frame(content: Control, padding: float) -> PanelContainer:
	var outer := PanelContainer.new()
	outer.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_40, Color(RED, 0.30), 3, 3.0, Color(RED, 0.16), 5)
	)

	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_68, Color(RED_BRIGHT, 0.84), 1, padding)
	)
	outer.add_child(inner)
	inner.add_child(content)
	return outer


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
