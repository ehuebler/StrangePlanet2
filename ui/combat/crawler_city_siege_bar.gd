class_name CrawlerCitySiegeBar
extends Control

## Top-centre crawler objective: how much of the nearby city has come down.

const WIDTH := 320.0
const TOP := 16.0
const HEIGHT := 40.0

var _title: Label
var _pct: Label
var _fill: ColorRect
var _display_share := 0.0


func _ready() -> void:
	name = "CrawlerCitySiegeBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = TOP
	offset_bottom = TOP + HEIGHT
	_build()
	visible = false


func set_siege(city_name: String, ratio: float, delta: float) -> void:
	visible = true
	var share := clampf(ratio, 0.0, 1.0)
	_display_share = lerpf(_display_share, share, clampf(delta * 10.0, 0.0, 1.0))
	if _fill != null:
		_fill.scale.x = maxf(_display_share, 0.0)
	if _title != null:
		_title.text = city_name.to_upper() if not city_name.is_empty() else "CITY"
	if _pct != null:
		_pct.text = "%d%%" % int(round(share * 100.0))


func hide_siege() -> void:
	visible = false
	_display_share = 0.0
	if _fill != null:
		_fill.scale.x = 0.0


func displayed_percent() -> int:
	if _pct == null:
		return 0
	return int(_pct.text.trim_suffix("%"))


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(WIDTH, 0.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RedHudTheme.panel(root, 6.0)
	centre.add_child(root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(column)

	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)

	_title = Label.new()
	_title.text = "CITY"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RedHudTheme.label(_title, 12)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(_title)

	_pct = Label.new()
	_pct.name = "SiegePercent"
	_pct.text = "0%"
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	RedHudTheme.label(_pct, 12)
	_pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(_pct)

	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(WIDTH - 16.0, 8.0)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RedHudTheme.panel(track, 0.0, RedHudTheme.BLACK, RedHudTheme.RED_BRIGHT, 1)
	column.add_child(track)

	var track_pad := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		track_pad.add_theme_constant_override(side, 1)
	track_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(track_pad)

	_fill = ColorRect.new()
	_fill.name = "SiegeFill"
	_fill.color = RedHudTheme.RED
	_fill.custom_minimum_size = Vector2(0.0, 6.0)
	_fill.pivot_offset = Vector2.ZERO
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.scale.x = 0.0
	track_pad.add_child(_fill)
