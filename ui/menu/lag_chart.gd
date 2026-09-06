class_name LagChart
extends Control

## One channel's last 30 seconds, drawn as a sparkline.

var values := PackedFloat32Array()
var times := PackedFloat64Array()
var hitch_times := PackedFloat64Array()
var line_color := Color("6fdcf2")
var warn_at := 0.0


func set_series(next_times: PackedFloat64Array, next_values: PackedFloat32Array) -> void:
	times = next_times
	values = next_values
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 28


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.05, 0.04, 0.12, 0.72))
	draw_rect(rect, Color(0.44, 0.22, 0.32, 0.55), false, 1.0)
	if values.size() < 2 or times.size() != values.size():
		return
	var lo := 0.0
	var hi := 1.0
	for value in values:
		hi = maxf(hi, value)
	if warn_at > 0.0 and hi < warn_at:
		hi = warn_at
	hi *= 1.08
	if warn_at > 0.0:
		var warn_y := _y(warn_at, lo, hi)
		draw_line(Vector2(0.0, warn_y), Vector2(size.x, warn_y), Color(1.0, 0.38, 0.53, 0.35), 1.0)
	var t0 := times[0]
	var t1 := times[times.size() - 1]
	var span := maxf(t1 - t0, 0.001)
	var pts := PackedVector2Array()
	pts.resize(values.size())
	for i in values.size():
		var x := ((times[i] - t0) / span) * size.x
		pts[i] = Vector2(x, _y(values[i], lo, hi))
	draw_polyline(pts, line_color, 1.6, true)
	for hitch in hitch_times:
		if hitch < t0 or hitch > t1:
			continue
		var x := ((hitch - t0) / span) * size.x
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(1.0, 0.38, 0.53, 0.7), 1.0)


func _y(value: float, lo: float, hi: float) -> float:
	var u := clampf((value - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
	return size.y - 2.0 - u * (size.y - 4.0)
