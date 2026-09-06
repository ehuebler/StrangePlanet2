class_name HitMarker
extends Control

## Crosshair confirmation drawn in code. A short white X on a landed hit, and a
## longer gold X on a killing blow, so it reads against the red reticle without
## covering the ticks.

const HIT_TIME := 0.16
const KILL_TIME := 0.28
const GAP := 6.0
const ARM := 8.0
const THICKNESS := 2.2

const HIT_INK := Color(0.98, 0.98, 1.0, 1.0)
const KILL_INK := Color(1.0, 0.82, 0.18, 1.0)
const HALO := Color(0.008, 0.008, 0.010, 0.82)

var _left := 0.0
var _span := 0.0
var _kill := false
var _critical := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func flash(killed := false, critical := false) -> void:
	if killed:
		_kill = true
	elif _left <= 0.0:
		_kill = false
	if critical:
		_critical = true
	elif _left <= 0.0:
		_critical = false
	_span = KILL_TIME if _kill else HIT_TIME
	_left = _span
	visible = true
	queue_redraw()


func remaining() -> float:
	return _left


func is_kill() -> bool:
	return _kill and _left > 0.0


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(_left - delta, 0.0)
	if _left <= 0.0:
		_kill = false
		_critical = false
		visible = false
	queue_redraw()


func _draw() -> void:
	if _left <= 0.0:
		return
	var fade := _left / maxf(_span, 0.001)
	var alpha := fade * fade
	var grow := 1.0 + 0.16 * fade
	if _critical:
		grow += 0.08
	var ink := (KILL_INK if _kill else HIT_INK)
	ink.a *= alpha
	var rim := HALO
	rim.a *= alpha
	var centre := size * 0.5
	var inner := GAP * grow
	var outer := inner + ARM * grow
	for direction: Vector2 in [
		Vector2(1.0, 1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(-1.0, -1.0).normalized(),
	]:
		var from := centre + direction * inner
		var to := centre + direction * outer
		draw_line(from, to, rim, THICKNESS + 2.0)
		draw_line(from, to, ink, THICKNESS)
