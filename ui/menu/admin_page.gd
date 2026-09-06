class_name AdminPage
extends VBoxContainer

## The Admin tab: conjure any item into the backpack, and set any stat.
##
## A cheat panel, and it is worth saying why one is in the game rather than in a
## harness. Every other way to get an item involves walking to the thing that has
## it, and every way to test a stat involves whatever changes it — so the moment
## there is a second garment or a third stat, checking that it works costs a trip.
## This is the shortcut, and because it is built off [constant ItemDB.ITEMS] and
## [constant PlayerStats.STATS] rather than a list of its own, anything added to
## either table appears here with no edit.
##
## It writes through the same containers and the same stats object the game uses.
## There is no admin-only path into the player: an item added here arrives in the
## backpack exactly as one taken off a shelf would, which is the point — a bug that
## only shows up for conjured items would be a bug in this file.

const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")
const ROWS_HEIGHT := 140.0

var _backpack: ItemContainer
var _stats: PlayerStats
var _body_id := CharacterDB.DEFAULT_BODY

var _item_list: VBoxContainer
var _stat_list: VBoxContainer
var _notice: Label
var _item_search := ""
var _item_slot := "All"
var _lag_status: Label
var _lag_events: VBoxContainer
var _lag_hitches: VBoxContainer
var _lag_charts: Dictionary = {}
var _lag_name: LineEdit
var _lag_pick := -1
var _lag_visible: Dictionary = {}
var _content: VBoxContainer


## Called before the page enters the tree. Handed the container and the stats
## rather than the player, so a harness can drive it without one.
func configure(backpack: ItemContainer, stats: PlayerStats,
		body_id := CharacterDB.DEFAULT_BODY) -> void:
	_backpack = backpack
	_stats = stats
	_body_id = CharacterDB.sanitize_body(body_id)


func _ready() -> void:
	add_theme_constant_override(&"separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_build()
	if LagTracker != null:
		LagTracker.changed.connect(_refresh_lag)
		LagTracker.hitch_recorded.connect(func(index: int) -> void:
			_lag_pick = index
			_refresh_lag()
		)
	_refresh_lag()


func _build() -> void:
	_build_lag()
	_build_items()
	_build_stats()
	_notice = Label.new()
	_notice.add_theme_font_size_override(&"font_size", 13)
	_notice.add_theme_color_override(&"font_color", PALETTE.accent)
	_content.add_child(_notice)


# --- Lag --------------------------------------------------------------------

func _build_lag() -> void:
	var box := _well("LAG TRACKER")
	_lag_status = Label.new()
	_lag_status.add_theme_font_size_override(&"font_size", 12)
	_lag_status.add_theme_color_override(&"font_color", PALETTE.text_secondary)
	_lag_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lag_status)

	var charts := VBoxContainer.new()
	charts.add_theme_constant_override(&"separation", 4)
	box.add_child(charts)
	for channel in LagTracker.channels():
		var id := String(channel["id"])
		_lag_visible[id] = id in ["frame", "process", "terrain", "flora", "draw", "pipes"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.button_pressed = bool(_lag_visible[id])
		toggle.text = String(channel["label"])
		toggle.custom_minimum_size.x = 110
		toggle.add_theme_font_size_override(&"font_size", 11)
		AuroraSurface.add_to(toggle, AuroraSurface.Style.BUTTON)
		toggle.toggled.connect(func(on: bool) -> void:
			_lag_visible[id] = on
			_lag_charts[id]["row"].visible = on
		)
		row.add_child(toggle)
		var reading := Label.new()
		reading.custom_minimum_size.x = 70
		reading.add_theme_font_size_override(&"font_size", 11)
		reading.add_theme_color_override(&"font_color", PALETTE.text_muted)
		reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(reading)
		var chart := LagChart.new()
		chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chart.custom_minimum_size = Vector2(160, 26)
		chart.line_color = channel["color"]
		if id == "frame":
			chart.warn_at = 33.3
		row.add_child(chart)
		row.visible = bool(_lag_visible[id])
		charts.add_child(row)
		_lag_charts[id] = {"row": row, "chart": chart, "reading": reading, "toggle": toggle}

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	var events_box := VBoxContainer.new()
	events_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	events_box.add_child(MenuWidgets.heading("EVENTS", 14))
	_lag_events = _scrolled_min(events_box, 120)
	columns.add_child(events_box)

	var hitch_box := VBoxContainer.new()
	hitch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hitch_box.add_child(MenuWidgets.heading("HITCHES", 14))
	_lag_hitches = _scrolled_min(hitch_box, 120)
	columns.add_child(hitch_box)

	var export_row := HBoxContainer.new()
	export_row.add_theme_constant_override(&"separation", 10)
	box.add_child(export_row)
	_lag_name = LineEdit.new()
	_lag_name.placeholder_text = "Name this lag event"
	_lag_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AuroraSurface.add_to(_lag_name, AuroraSurface.Style.INPUT)
	export_row.add_child(_lag_name)
	var window_btn := MenuWidgets.button("LAST 30S")
	window_btn.custom_minimum_size.x = 110
	window_btn.pressed.connect(func() -> void:
		_lag_pick = -1
		_fill_lag_hitches()
		_refresh_lag()
	)
	export_row.add_child(window_btn)
	var save := MenuWidgets.button("EXPORT")
	save.custom_minimum_size.x = 110
	save.pressed.connect(_export_lag)
	export_row.add_child(save)
	var folder := MenuWidgets.button("OPEN FOLDER")
	folder.custom_minimum_size.x = 140
	folder.pressed.connect(func() -> void:
		LagTracker.open_export_folder()
		_say("Opened %s" % LagTracker.export_dir())
	)
	export_row.add_child(folder)


func _scrolled_min(box: VBoxContainer, height: float) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 4)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	return inner


func _refresh_lag() -> void:
	if _lag_status == null:
		return
	var summary: Dictionary = LagTracker.frame_summary()
	var span := LagTracker.window_span()
	var hold := "frozen" if LagTracker.is_frozen() else "live"
	var hitch_n := LagTracker.hitches().size()
	var target := "last 30s"
	if _lag_pick >= 0 and _lag_pick < hitch_n:
		var hitch: Dictionary = LagTracker.hitches()[_lag_pick]
		target = "hitch %.0f ms" % float(hitch.get("frame_ms", 0.0))
	_lag_status.text = "%s  ·  last %.1fs  ·  %.0f fps  ·  avg %.1f ms  ·  max %.1f ms  ·  %d hitches  ·  export %s" % [
		hold,
		span.y - span.x,
		float(summary.get("fps", 0.0)),
		float(summary.get("avg_ms", 0.0)),
		float(summary.get("max_ms", 0.0)),
		hitch_n,
		target,
	]
	_fill_lag_events()
	_fill_lag_hitches()
	_refresh_lag_charts()


func _refresh_lag_charts() -> void:
	if _lag_charts.is_empty():
		return
	var stamps := LagTracker.times()
	var hitch_times := PackedFloat64Array()
	for hitch in LagTracker.hitches():
		hitch_times.append(float((hitch as Dictionary).get("t", 0.0)))
	for id in _lag_charts:
		var bits: Dictionary = _lag_charts[id]
		var chart: LagChart = bits["chart"]
		var reading: Label = bits["reading"]
		chart.times = stamps
		chart.values = LagTracker.series(String(id))
		chart.hitch_times = hitch_times
		chart.queue_redraw()
		reading.text = "%.1f" % LagTracker.latest(String(id))


func _fill_lag_events() -> void:
	if _lag_events == null:
		return
	for child in _lag_events.get_children():
		child.queue_free()
	var rows := LagTracker.events_in_window()
	var start := maxi(rows.size() - 40, 0)
	if rows.is_empty():
		_lag_events.add_child(MenuWidgets.caption("No events in this window."))
		return
	for i in range(start, rows.size()):
		var row: Dictionary = rows[i]
		var line := Label.new()
		line.text = "%s  %s  %s" % [
			_clock(float(row.get("t", 0.0))),
			String(row.get("channel", "")),
			String(row.get("message", "")),
		]
		line.add_theme_font_size_override(&"font_size", 11)
		line.add_theme_color_override(&"font_color", PALETTE.text_secondary)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lag_events.add_child(line)


func _fill_lag_hitches() -> void:
	if _lag_hitches == null:
		return
	for child in _lag_hitches.get_children():
		child.queue_free()
	var rows := LagTracker.hitches()
	if rows.is_empty():
		_lag_hitches.add_child(MenuWidgets.caption("No hitch captured yet."))
		return
	for index in rows.size():
		var hitch: Dictionary = rows[index]
		var pick := Button.new()
		pick.toggle_mode = true
		pick.button_pressed = index == _lag_pick
		pick.text = "%s   %.1f ms" % [_clock(float(hitch.get("t", 0.0))), float(hitch.get("frame_ms", 0.0))]
		pick.add_theme_font_size_override(&"font_size", 12)
		AuroraSurface.add_to(pick, AuroraSurface.Style.BUTTON)
		var chosen := index
		pick.pressed.connect(func() -> void:
			_lag_pick = -1 if _lag_pick == chosen else chosen
			if _lag_pick == chosen and _lag_name != null and _lag_name.text.strip_edges().is_empty():
				_lag_name.text = "hitch_%.0fms" % float(hitch.get("frame_ms", 0.0))
			_refresh_lag()
		)
		_lag_hitches.add_child(pick)


func _export_lag() -> void:
	var title := _lag_name.text.strip_edges()
	if title.is_empty():
		_say("Name the event before exporting.")
		if _lag_name != null:
			_lag_name.grab_focus()
		return
	var path := LagTracker.export_named(title, _lag_pick)
	if path.is_empty():
		_say("Export failed.")
		return
	_say("Saved %s" % path.get_file())


func _clock(t: float) -> String:
	var span := LagTracker.window_span()
	var ago := maxf(span.y - t, 0.0)
	return "-%.1fs" % ago


# --- Items ------------------------------------------------------------------

func _build_items() -> void:
	var box := _well("ITEMS")
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override(&"separation", 10)
	box.add_child(filters)

	# Slots as the filter, which is the one axis every item has: five body slots
	# and weapons, straight off the tables rather than typed here.
	var slots := PackedStringArray(["All"])
	slots.append_array(ItemDB.SLOT_ORDER)
	slots.append(ItemDB.WEAPON)
	var picker := OptionButton.new()
	for slot in slots:
		picker.add_item(String(ItemDB.SLOT_LABELS.get(slot, slot)).capitalize() \
			if slot != "All" else "All slots")
	picker.custom_minimum_size.x = 150
	AuroraSurface.add_to(picker, AuroraSurface.Style.BUTTON)
	picker.item_selected.connect(func(index: int) -> void:
		_item_slot = slots[index] if index < slots.size() else "All"
		_fill_items()
	)
	filters.add_child(picker)

	var search := LineEdit.new()
	search.placeholder_text = "Search items"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AuroraSurface.add_to(search, AuroraSurface.Style.INPUT)
	search.text_changed.connect(func(text: String) -> void:
		_item_search = text.strip_edges().to_lower()
		_fill_items()
	)
	filters.add_child(search)

	_item_list = _scrolled(box)
	_fill_items()


## Only what this body can actually wear, plus every weapon, since a weapon is
## held rather than skinned and fits anyone.
##
## Garments cut for the other skeleton used to be listed and marked instead, on
## the grounds that this is the admin tab and hiding a real item is a lie. That
## was the wrong call twice over: [method OnlinePlayer._dress] refuses a mismatch
## outright, so the ADD beside them could not do anything, and with one playable
## body the retired one's wardrobe was most of the list — five dead rows above
## the four that work.
func _fill_items() -> void:
	for child in _item_list.get_children():
		child.queue_free()
	var shown := 0
	for id: String in ItemDB.ITEMS:
		var slot := ItemDB.slot_of(id)
		if not (ItemDB.is_weapon(id) or CharacterDB.apparel_fits(_body_id, id)):
			continue
		if _item_slot != "All" and slot != _item_slot:
			continue
		if not _item_search.is_empty() \
				and not ItemDB.title(id).to_lower().contains(_item_search):
			continue
		shown += 1
		_item_list.add_child(_item_row(id, slot))
	if shown == 0:
		_item_list.add_child(MenuWidgets.caption("No item matches that."))


func _item_row(id: String, slot: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)

	var title := Label.new()
	title.text = ItemDB.title(id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 14)
	row.add_child(title)

	var where := Label.new()
	where.text = String(ItemDB.SLOT_LABELS.get(slot, slot))
	where.custom_minimum_size.x = 80
	where.add_theme_font_size_override(&"font_size", 12)
	where.add_theme_color_override(&"font_color", PALETTE.text_muted)
	row.add_child(where)

	var add := MenuWidgets.button("ADD")
	add.custom_minimum_size.x = 90
	add.add_theme_font_size_override(&"font_size", 12)
	add.pressed.connect(func() -> void: _give(id))
	row.add_child(add)
	return row


## Into the backpack, through the container's own filters, so an item that would
## not be accepted is refused here too.
func _give(id: String) -> void:
	if _backpack == null:
		return
	var index := _backpack.first_accepting(id)
	if index < 0:
		_say("No room in the backpack for %s." % ItemDB.title(id))
		return
	_backpack.set_item(index, id)
	_say("%s added to the backpack." % ItemDB.title(id))


# --- Stats ------------------------------------------------------------------

func _build_stats() -> void:
	var box := _well("STATS")
	_stat_list = _scrolled(box)
	_fill_stats()


func _fill_stats() -> void:
	for child in _stat_list.get_children():
		child.queue_free()
	if _stats == null:
		_stat_list.add_child(MenuWidgets.caption("No stats to edit here."))
		return
	for id in PlayerStats.ids():
		_stat_list.add_child(_stat_row(StringName(id)))


## One stat, its current base, a box to type a new one into, and APPLY. A box
## rather than a slider because the point of this tab is to set an exact number and
## see what it does, which a slider is bad at.
func _stat_row(id: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)

	var title := Label.new()
	title.text = PlayerStats.title_of(id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 14)
	row.add_child(title)

	var now := Label.new()
	now.text = PlayerStats.format(id, _stats.base_of(id))
	now.custom_minimum_size.x = 90
	now.add_theme_font_size_override(&"font_size", 12)
	now.add_theme_color_override(&"font_color", PALETTE.text_muted)
	row.add_child(now)

	var field := SpinBox.new()
	field.min_value = PlayerStats.minimum_of(id)
	field.max_value = PlayerStats.maximum_of(id)
	field.step = 0.1
	field.value = _stats.base_of(id)
	field.custom_minimum_size.x = 120
	AuroraSurface.add_to(field, AuroraSurface.Style.INPUT)
	row.add_child(field)

	var apply := MenuWidgets.button("APPLY")
	apply.custom_minimum_size.x = 90
	apply.add_theme_font_size_override(&"font_size", 12)
	apply.pressed.connect(func() -> void:
		_stats.set_base(id, field.value)
		now.text = PlayerStats.format(id, _stats.base_of(id))
		field.value = _stats.base_of(id)
		_say("%s set to %s." % [PlayerStats.title_of(id), now.text])
	)
	row.add_child(apply)
	return row


# --- Shared -----------------------------------------------------------------

## A captioned well added straight to the page, returning the box to fill. Both
## builders above want the same four nodes and neither wants the panel itself, so
## it is added here rather than handed back.
func _well(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	_content.add_child(panel)
	AuroraSurface.add_to(panel, AuroraSurface.Style.ROW)
	var padding := MarginContainer.new()
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		padding.add_theme_constant_override(side, 18)
	panel.add_child(padding)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	padding.add_child(box)
	box.add_child(MenuWidgets.heading(title, 19))
	return box


func _scrolled(box: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, ROWS_HEIGHT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The scrollbar draws over the content, so the rows are inset clear of it.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override(&"margin_right", 20)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(inner)
	scroll.add_child(inset)
	return inner


func _say(text: String) -> void:
	if _notice != null:
		_notice.text = text
