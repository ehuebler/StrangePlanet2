@tool
class_name RedMenuGlyph
extends Control

## Responsive menu glyphs drawn entirely with CanvasItem primitives.
##
## Every shape is authored in a 100 x 100 design space and fitted into the
## Control's shortest side, so the icon remains square and centred in arbitrary
## layouts. The default ink is signal green over a black keyline. Set
## [member red_accent] for destructive or warning uses without needing another
## asset.

enum Glyph {
	HERO,
	APPAREL_ALL,
	HAT,
	GOGGLES,
	BODY_TUNIC,
	PANTS,
	BOOTS,
	WEAPONS,
	ITEMS,
	ABILITIES,
	DATA,
	QUEST,
	ACHIEVEMENT,
	CLOSE,
	SETTINGS,
	EXIT,
	RESPAWN,
	EMPTY_X,
	STATS,
}

@export var glyph: Glyph = Glyph.HERO:
	set(value):
		glyph = value
		queue_redraw()

@export_group("Colors")
@export var green_color := Color(0.36, 1.0, 0.43, 1.0):
	set(value):
		green_color = value
		queue_redraw()
@export var black_color := Color(0.005, 0.008, 0.006, 0.96):
	set(value):
		black_color = value
		queue_redraw()
@export var red_color := Color(1.0, 0.055, 0.11, 1.0):
	set(value):
		red_color = value
		queue_redraw()
@export var red_accent := false:
	set(value):
		red_accent = value
		queue_redraw()

@export_group("Geometry")
@export_range(0.0, 0.24, 0.01) var padding_ratio := 0.09:
	set(value):
		padding_ratio = clampf(value, 0.0, 0.24)
		queue_redraw()
@export_range(0.6, 2.0, 0.05) var stroke_scale := 1.0:
	set(value):
		stroke_scale = clampf(value, 0.6, 2.0)
		queue_redraw()

var _origin := Vector2.ZERO
var _unit := 1.0


func _init() -> void:
	custom_minimum_size = Vector2(28.0, 28.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var edge := minf(size.x, size.y)
	if edge <= 1.0:
		return
	var drawing_edge := edge * (1.0 - padding_ratio * 2.0)
	_unit = drawing_edge / 100.0
	_origin = (size - Vector2(drawing_edge, drawing_edge)) * 0.5

	match glyph:
		Glyph.HERO:
			_draw_hero()
		Glyph.APPAREL_ALL:
			_draw_apparel()
		Glyph.HAT:
			_draw_hat()
		Glyph.GOGGLES:
			_draw_goggles()
		Glyph.BODY_TUNIC:
			_draw_tunic()
		Glyph.PANTS:
			_draw_pants()
		Glyph.BOOTS:
			_draw_boots()
		Glyph.WEAPONS:
			_draw_weapons()
		Glyph.ITEMS:
			_draw_items()
		Glyph.ABILITIES:
			_draw_abilities()
		Glyph.DATA:
			_draw_data()
		Glyph.QUEST:
			_draw_quest()
		Glyph.ACHIEVEMENT:
			_draw_achievement()
		Glyph.CLOSE:
			_draw_close()
		Glyph.SETTINGS:
			_draw_settings()
		Glyph.EXIT:
			_draw_exit()
		Glyph.RESPAWN:
			_draw_respawn()
		Glyph.EMPTY_X:
			_draw_empty()
		Glyph.STATS:
			_draw_stats()


func _draw_hero() -> void:
	_circle(Vector2(50.0, 28.0), 13.0, 5.5, _ink())
	_stroke(PackedVector2Array([
		Vector2(18.0, 84.0),
		Vector2(22.0, 68.0),
		Vector2(36.0, 55.0),
		Vector2(50.0, 62.0),
		Vector2(64.0, 55.0),
		Vector2(78.0, 68.0),
		Vector2(82.0, 84.0),
	]), 6.0, _ink())


func _draw_apparel() -> void:
	_arc(Vector2(50.0, 32.0), 10.0, PI, TAU + PI * 0.48, 5.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(50.0, 42.0),
		Vector2(19.0, 67.0),
		Vector2(81.0, 67.0),
		Vector2(50.0, 42.0),
	]), 5.5, _ink())
	_stroke(PackedVector2Array([
		Vector2(25.0, 76.0),
		Vector2(75.0, 76.0),
	]), 5.5, _ink())


func _draw_hat() -> void:
	_polygon(PackedVector2Array([
		Vector2(30.0, 61.0),
		Vector2(35.0, 29.0),
		Vector2(65.0, 29.0),
		Vector2(70.0, 61.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(31.0, 50.0),
		Vector2(69.0, 50.0),
	]), 5.0, black_color)
	_stroke(PackedVector2Array([
		Vector2(16.0, 67.0),
		Vector2(84.0, 67.0),
	]), 7.0, _ink())


func _draw_goggles() -> void:
	_circle(Vector2(33.0, 51.0), 16.0, 6.0, _ink())
	_circle(Vector2(67.0, 51.0), 16.0, 6.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(49.0, 49.0),
		Vector2(51.0, 49.0),
	]), 6.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(17.0, 47.0),
		Vector2(8.0, 39.0),
	]), 5.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(83.0, 47.0),
		Vector2(92.0, 39.0),
	]), 5.0, _ink())


func _draw_tunic() -> void:
	_polygon(PackedVector2Array([
		Vector2(37.0, 20.0),
		Vector2(18.0, 31.0),
		Vector2(10.0, 51.0),
		Vector2(27.0, 58.0),
		Vector2(32.0, 49.0),
		Vector2(29.0, 84.0),
		Vector2(71.0, 84.0),
		Vector2(68.0, 49.0),
		Vector2(73.0, 58.0),
		Vector2(90.0, 51.0),
		Vector2(82.0, 31.0),
		Vector2(63.0, 20.0),
		Vector2(57.0, 32.0),
		Vector2(43.0, 32.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(40.0, 68.0),
		Vector2(60.0, 68.0),
	]), 4.0, black_color)


func _draw_pants() -> void:
	_polygon(PackedVector2Array([
		Vector2(25.0, 17.0),
		Vector2(75.0, 17.0),
		Vector2(72.0, 48.0),
		Vector2(67.0, 85.0),
		Vector2(50.0, 85.0),
		Vector2(47.0, 53.0),
		Vector2(43.0, 85.0),
		Vector2(26.0, 85.0),
		Vector2(28.0, 48.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(26.0, 31.0),
		Vector2(74.0, 31.0),
	]), 5.0, black_color)


func _draw_boots() -> void:
	_polygon(PackedVector2Array([
		Vector2(20.0, 20.0),
		Vector2(43.0, 20.0),
		Vector2(43.0, 63.0),
		Vector2(52.0, 72.0),
		Vector2(52.0, 84.0),
		Vector2(15.0, 84.0),
		Vector2(15.0, 68.0),
		Vector2(22.0, 61.0),
	]), _ink())
	_polygon(PackedVector2Array([
		Vector2(57.0, 20.0),
		Vector2(80.0, 20.0),
		Vector2(78.0, 61.0),
		Vector2(85.0, 68.0),
		Vector2(85.0, 84.0),
		Vector2(48.0, 84.0),
		Vector2(48.0, 72.0),
		Vector2(57.0, 63.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(22.0, 37.0),
		Vector2(42.0, 37.0),
	]), 4.0, black_color)
	_stroke(PackedVector2Array([
		Vector2(58.0, 37.0),
		Vector2(78.0, 37.0),
	]), 4.0, black_color)


func _draw_weapons() -> void:
	_stroke(PackedVector2Array([
		Vector2(20.0, 82.0),
		Vector2(75.0, 21.0),
	]), 7.0, _ink())
	_polygon(PackedVector2Array([
		Vector2(75.0, 21.0),
		Vector2(87.0, 11.0),
		Vector2(81.0, 29.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(14.0, 69.0),
		Vector2(31.0, 84.0),
	]), 5.0, _ink())

	_stroke(PackedVector2Array([
		Vector2(80.0, 82.0),
		Vector2(25.0, 21.0),
	]), 7.0, _ink())
	_polygon(PackedVector2Array([
		Vector2(25.0, 21.0),
		Vector2(13.0, 11.0),
		Vector2(19.0, 29.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(69.0, 84.0),
		Vector2(86.0, 69.0),
	]), 5.0, _ink())


func _draw_items() -> void:
	_outline_rect(Rect2(19.0, 34.0, 62.0, 51.0), 6.0, _ink())
	_arc(Vector2(50.0, 36.0), 18.0, PI, TAU, 6.0, _ink())
	_filled_rect(Rect2(28.0, 48.0, 44.0, 8.0), _ink())
	_polygon(PackedVector2Array([
		Vector2(50.0, 62.0),
		Vector2(59.0, 70.0),
		Vector2(50.0, 78.0),
		Vector2(41.0, 70.0),
	]), _ink())


func _draw_abilities() -> void:
	_polygon(PackedVector2Array([
		Vector2(55.0, 8.0),
		Vector2(22.0, 55.0),
		Vector2(45.0, 55.0),
		Vector2(36.0, 92.0),
		Vector2(79.0, 42.0),
		Vector2(56.0, 42.0),
	]), _ink())


func _draw_data() -> void:
	_outline_rect(Rect2(20.0, 13.0, 60.0, 74.0), 5.5, _ink())
	for y in [32.0, 50.0, 68.0]:
		_filled_circle(Vector2(32.0, y), 3.5, _ink())
		_stroke(PackedVector2Array([
			Vector2(43.0, y),
			Vector2(69.0, y),
		]), 4.0, _ink())


func _draw_quest() -> void:
	_outline_rect(Rect2(18.0, 14.0, 64.0, 72.0), 5.5, _ink())
	_stroke(PackedVector2Array([
		Vector2(18.0, 25.0),
		Vector2(10.0, 25.0),
		Vector2(10.0, 14.0),
		Vector2(27.0, 14.0),
	]), 5.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(82.0, 75.0),
		Vector2(90.0, 75.0),
		Vector2(90.0, 86.0),
		Vector2(73.0, 86.0),
	]), 5.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(50.0, 30.0),
		Vector2(50.0, 58.0),
	]), 7.0, _ink())
	_filled_circle(Vector2(50.0, 70.0), 4.5, _ink())


func _draw_achievement() -> void:
	_polygon(PackedVector2Array([
		Vector2(27.0, 16.0),
		Vector2(73.0, 16.0),
		Vector2(68.0, 49.0),
		Vector2(58.0, 60.0),
		Vector2(42.0, 60.0),
		Vector2(32.0, 49.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(28.0, 25.0),
		Vector2(14.0, 25.0),
		Vector2(17.0, 49.0),
		Vector2(36.0, 55.0),
	]), 5.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(72.0, 25.0),
		Vector2(86.0, 25.0),
		Vector2(83.0, 49.0),
		Vector2(64.0, 55.0),
	]), 5.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(50.0, 60.0),
		Vector2(50.0, 76.0),
	]), 7.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(32.0, 84.0),
		Vector2(68.0, 84.0),
	]), 8.0, _ink())


func _draw_close() -> void:
	_stroke(PackedVector2Array([
		Vector2(18.0, 18.0),
		Vector2(82.0, 82.0),
	]), 8.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(82.0, 18.0),
		Vector2(18.0, 82.0),
	]), 8.0, _ink())


func _draw_settings() -> void:
	var gear := PackedVector2Array()
	var tooth_points := 24
	for index in tooth_points:
		var radius := 42.0 if index % 2 == 0 else 33.0
		var angle := -PI * 0.5 + TAU * float(index) / float(tooth_points)
		gear.append(Vector2(50.0, 50.0) + Vector2(cos(angle), sin(angle)) * radius)
	_polygon(gear, _ink())
	_filled_circle(Vector2(50.0, 50.0), 13.0, black_color)
	_circle(Vector2(50.0, 50.0), 14.0, 3.0, _ink())


func _draw_exit() -> void:
	_outline_rect(Rect2(18.0, 12.0, 45.0, 76.0), 5.5, _ink())
	_filled_circle(Vector2(52.0, 51.0), 3.5, _ink())
	_stroke(PackedVector2Array([
		Vector2(44.0, 50.0),
		Vector2(88.0, 50.0),
	]), 7.0, _ink())
	_polygon(PackedVector2Array([
		Vector2(88.0, 50.0),
		Vector2(72.0, 35.0),
		Vector2(72.0, 65.0),
	]), _ink())


func _draw_respawn() -> void:
	_stroke(PackedVector2Array([
		Vector2(50.0, 16.0),
		Vector2(50.0, 60.0),
	]), 6.5, _ink())
	_polygon(PackedVector2Array([
		Vector2(50.0, 72.0),
		Vector2(32.0, 50.0),
		Vector2(68.0, 50.0),
	]), _ink())
	_stroke(PackedVector2Array([
		Vector2(20.0, 84.0),
		Vector2(80.0, 84.0),
	]), 6.0, _ink())


func _draw_empty() -> void:
	_outline_rect(Rect2(14.0, 14.0, 72.0, 72.0), 4.5, _ink())
	_stroke(PackedVector2Array([
		Vector2(31.0, 31.0),
		Vector2(69.0, 69.0),
	]), 6.0, _ink())
	_stroke(PackedVector2Array([
		Vector2(69.0, 31.0),
		Vector2(31.0, 69.0),
	]), 6.0, _ink())


func _draw_stats() -> void:
	_stroke(PackedVector2Array([
		Vector2(16.0, 84.0),
		Vector2(86.0, 84.0),
	]), 5.0, _ink())
	_filled_rect(Rect2(21.0, 55.0, 13.0, 29.0), _ink())
	_filled_rect(Rect2(44.0, 36.0, 13.0, 48.0), _ink())
	_filled_rect(Rect2(67.0, 18.0, 13.0, 66.0), _ink())


func _ink() -> Color:
	return red_color if red_accent else green_color


func _point(design_point: Vector2) -> Vector2:
	return _origin + design_point * _unit


func _mapped(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(_point(point))
	return result


func _stroke(
	points: PackedVector2Array,
	width_in_design_units: float,
	color: Color
) -> void:
	if points.size() < 2:
		return
	var path := _mapped(points)
	var width := maxf(width_in_design_units * _unit * stroke_scale, 0.8)
	var keyline := maxf(1.8 * _unit * stroke_scale, 0.75)
	draw_polyline(path, black_color, width + keyline * 2.0, true)
	draw_polyline(path, color, width, true)


func _polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var shape := _mapped(points)
	draw_colored_polygon(shape, color)
	var closed := shape.duplicate()
	closed.append(shape[0])
	var keyline := maxf(2.0 * _unit * stroke_scale, 0.8)
	draw_polyline(closed, black_color, keyline, true)


func _circle(
	center: Vector2,
	radius_in_design_units: float,
	width_in_design_units: float,
	color: Color
) -> void:
	var radius := radius_in_design_units * _unit
	var width := maxf(width_in_design_units * _unit * stroke_scale, 0.8)
	var keyline := maxf(1.8 * _unit * stroke_scale, 0.75)
	var point_count := maxi(18, ceili(radius * 1.2))
	draw_arc(_point(center), radius, 0.0, TAU, point_count,
		black_color, width + keyline * 2.0, true)
	draw_arc(_point(center), radius, 0.0, TAU, point_count, color, width, true)


func _arc(
	center: Vector2,
	radius_in_design_units: float,
	from_angle: float,
	to_angle: float,
	width_in_design_units: float,
	color: Color
) -> void:
	var radius := radius_in_design_units * _unit
	var width := maxf(width_in_design_units * _unit * stroke_scale, 0.8)
	var keyline := maxf(1.8 * _unit * stroke_scale, 0.75)
	var point_count := maxi(12, ceili(radius))
	draw_arc(_point(center), radius, from_angle, to_angle, point_count,
		black_color, width + keyline * 2.0, true)
	draw_arc(_point(center), radius, from_angle, to_angle, point_count,
		color, width, true)


func _outline_rect(rect: Rect2, width_in_design_units: float, color: Color) -> void:
	var local_rect := Rect2(_point(rect.position), rect.size * _unit)
	var width := maxf(width_in_design_units * _unit * stroke_scale, 0.8)
	var keyline := maxf(1.8 * _unit * stroke_scale, 0.75)
	draw_rect(local_rect, black_color, false, width + keyline * 2.0, true)
	draw_rect(local_rect, color, false, width, true)


func _filled_rect(rect: Rect2, color: Color) -> void:
	var local_rect := Rect2(_point(rect.position), rect.size * _unit)
	draw_rect(local_rect, color, true)
	draw_rect(local_rect, black_color, false,
		maxf(1.8 * _unit * stroke_scale, 0.75), true)


func _filled_circle(center: Vector2, radius_in_design_units: float, color: Color) -> void:
	var radius := radius_in_design_units * _unit
	var keyline := maxf(1.4 * _unit * stroke_scale, 0.6)
	draw_circle(_point(center), radius + keyline, black_color)
	draw_circle(_point(center), radius, color)


static func label_for(value: Glyph) -> String:
	match value:
		Glyph.HERO:
			return "Hero"
		Glyph.APPAREL_ALL:
			return "Apparel / All"
		Glyph.HAT:
			return "Hat"
		Glyph.GOGGLES:
			return "Goggles"
		Glyph.BODY_TUNIC:
			return "Body / Tunic"
		Glyph.PANTS:
			return "Pants"
		Glyph.BOOTS:
			return "Boots"
		Glyph.WEAPONS:
			return "Weapons"
		Glyph.ITEMS:
			return "Items"
		Glyph.ABILITIES:
			return "Abilities"
		Glyph.DATA:
			return "Data"
		Glyph.QUEST:
			return "Quest"
		Glyph.ACHIEVEMENT:
			return "Achievement"
		Glyph.CLOSE:
			return "Close"
		Glyph.SETTINGS:
			return "Settings"
		Glyph.EXIT:
			return "Exit"
		Glyph.RESPAWN:
			return "Respawn"
		Glyph.EMPTY_X:
			return "Empty"
		Glyph.STATS:
			return "Stats"
	return ""
