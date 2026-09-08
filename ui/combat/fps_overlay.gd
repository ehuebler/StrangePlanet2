class_name FpsOverlay
extends PanelContainer

## Live FPS readout and sparkline in the upper-right.

const MARGIN := 12.0
const WIDTH := 228.0
const HISTORY := 180
const WARN_FPS := 30.0
const GOOD_FPS := 55.0

var _readout: Label
var _chart: Control
var _values := PackedFloat32Array()
var _latest := 0.0
var _latest_ms := 0.0


func _init() -> void:
	name = "FpsOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	offset_left = -MARGIN - WIDTH
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN
	custom_minimum_size = Vector2(WIDTH, 78.0)


func _ready() -> void:
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.03, 0.03, 0.05, 0.78)
	plate.border_color = Color(0.55, 0.18, 0.26, 0.85)
	plate.set_border_width_all(1)
	plate.content_margin_left = 8
	plate.content_margin_right = 8
	plate.content_margin_top = 5
	plate.content_margin_bottom = 6
	add_theme_stylebox_override(&"panel", plate)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 3)
	add_child(column)
	_readout = Label.new()
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_readout.add_theme_font_size_override(&"font_size", 14)
	_readout.add_theme_color_override(&"font_color", Color(0.82, 0.94, 1.0, 0.96))
	_readout.text = "— FPS"
	column.add_child(_readout)
	_chart = Control.new()
	_chart.name = "FpsChart"
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart.custom_minimum_size = Vector2(0.0, 44.0)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.draw.connect(_draw_chart)
	column.add_child(_chart)
	_sample()


func _process(_delta: float) -> void:
	_sample()


func current_fps() -> float:
	return _latest


func current_ms() -> float:
	return _latest_ms


func sample_count() -> int:
	return _values.size()


func _sample() -> void:
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	if frame_ms <= 0.001:
		frame_ms = (1.0 / maxf(Engine.get_frames_per_second(), 1.0)) * 1000.0
	_latest_ms = frame_ms
	_latest = 1000.0 / maxf(frame_ms, 0.01)
	if _values.size() >= HISTORY:
		_values.remove_at(0)
	_values.append(_latest)
	if _readout != null:
		_readout.text = "%d FPS   %.1f ms" % [int(round(_latest)), _latest_ms]
		_readout.add_theme_color_override(&"font_color", _ink(_latest))
	if _chart != null:
		_chart.queue_redraw()


func _ink(fps: float) -> Color:
	if fps >= GOOD_FPS:
		return Color(0.45, 0.92, 0.72, 0.96)
	if fps >= WARN_FPS:
		return Color(0.98, 0.82, 0.32, 0.96)
	return Color(1.0, 0.38, 0.53, 0.96)


func _draw_chart() -> void:
	if _chart == null:
		return
	var area := _chart.size
	_chart.draw_rect(Rect2(Vector2.ZERO, area), Color(0.02, 0.02, 0.04, 0.55))
	if area.x < 2.0 or area.y < 2.0:
		return
	var hi := 60.0
	for value in _values:
		hi = maxf(hi, value)
	hi *= 1.06
	_draw_guide(area, WARN_FPS, hi, Color(1.0, 0.38, 0.53, 0.28))
	_draw_guide(area, 60.0, hi, Color(0.45, 0.92, 0.72, 0.18))
	if _values.size() < 2:
		return
	var pts := PackedVector2Array()
	pts.resize(_values.size())
	var last := _values.size() - 1
	for i in _values.size():
		var x := (float(i) / float(last)) * area.x
		pts[i] = Vector2(x, _chart_y(area, _values[i], hi))
	_chart.draw_polyline(pts, _ink(_values[last]), 1.7, true)


func _draw_guide(area: Vector2, fps: float, hi: float, colour: Color) -> void:
	var y := _chart_y(area, fps, hi)
	_chart.draw_line(Vector2(0.0, y), Vector2(area.x, y), colour, 1.0)


func _chart_y(area: Vector2, fps: float, hi: float) -> float:
	var u := clampf(fps / maxf(hi, 0.001), 0.0, 1.0)
	return area.y - 2.0 - u * (area.y - 4.0)
