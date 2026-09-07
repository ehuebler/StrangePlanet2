class_name StatusChip
extends PanelContainer

## One transient combat status row with optional vector icon and countdown.

var status_id := &"":
	set(value):
		status_id = value
		queue_redraw()

var remaining := 0.0:
	set(value):
		remaining = maxf(value, 0.0)
		_refresh()

var maximum := 1.0:
	set(value):
		maximum = maxf(value, 0.001)
		_refresh()

var _title: Label
var _time: Label
var _icon: Control
var _bar: ColorRect
var _track: PanelContainer
var _track_inner: Control
var _lasting := false


func _init() -> void:
	name = "StatusChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	_refresh()


func _build() -> void:
	RedHudTheme.panel(self)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	add_child(pad)

	_icon = DodoIcon.new()
	_icon.custom_minimum_size = Vector2(22.0, 22.0)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)

	var text_col := VBoxContainer.new()
	text_col.add_theme_constant_override(&"separation", 3)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(header)

	_title = Label.new()
	RedHudTheme.label(_title, 10)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)

	_time = Label.new()
	RedHudTheme.label(_time, 10)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_time)

	_track = PanelContainer.new()
	_track.custom_minimum_size = Vector2(120.0, 5.0)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RedHudTheme.panel(
		_track, 0.0, RedHudTheme.BLACK, RedHudTheme.RED_BRIGHT, 1
	)
	text_col.add_child(_track)

	_track_inner = Control.new()
	_track_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(_track_inner)
	_bar = ColorRect.new()
	_bar.color = RedHudTheme.GREEN
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track_inner.add_child(_bar)


func apply_row(row: Dictionary) -> void:
	status_id = StringName(row.get("id", &""))
	_title.text = String(row.get("title", String(status_id)))
	_lasting = bool(row.get("lasting", false))
	var rem := float(row.get("remaining", 0.0))
	if not _lasting:
		maximum = maxf(maximum, rem)
		remaining = rem
	if _icon != null:
		_icon.visible = CombatStatuses.is_known(status_id)
	_refresh()


func _refresh() -> void:
	if _time == null:
		return
	if _lasting:
		_time.text = ""
		_time.visible = false
		if _track != null:
			_track.visible = false
		return
	_time.visible = true
	if _track != null:
		_track.visible = true
	_time.text = "%.1f s" % remaining
	var share := clampf(remaining / maximum, 0.0, 1.0)
	if _track_inner != null and _bar != null:
		_bar.position = Vector2.ONE
		_bar.size = Vector2(
			maxf((_track_inner.size.x - 2.0) * share, 0.0),
			maxf(_track_inner.size.y - 2.0, 0.0)
		)

