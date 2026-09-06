class_name CrawlerLevelBurst
extends Control

## Top-of-HUD sting after a crawler level-up. The world stays live until this
## finishes, then the spend menu opens.

signal finished

const HOLD := 1.2
const RED := Color("ef151f")
const GREEN := Color("39d98a")
const GOLD := Color("ffd45a")

var _age := 0.0
var _done := false
var _title: Label


func _init() -> void:
	name = "CrawlerLevelBurst"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _ready() -> void:
	_title = Label.new()
	_title.name = "LevelUpTitle"
	_title.text = "Level Up"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_left = 0.0
	_title.offset_top = 18.0
	_title.offset_right = 0.0
	_title.offset_bottom = 132.0
	_title.add_theme_font_size_override(&"font_size", 52)
	_title.add_theme_color_override(&"font_color", Color(1.0, 0.96, 0.88, 1.0))
	_title.add_theme_color_override(&"font_outline_color", RED)
	_title.add_theme_constant_override(&"outline_size", 10)
	add_child(_title)
	_drive_title()


func _process(delta: float) -> void:
	if _done:
		return
	_age += maxf(delta, 0.0)
	_drive_title()
	queue_redraw()
	if _age >= HOLD:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _drive_title() -> void:
	if _title == null:
		return
	var pop := smoothstep(0.0, 0.14, _age)
	var bounce := 1.0 + 0.1 * sin(_age * 22.0) * exp(_age * -5.0)
	var fade := 1.0 - smoothstep(HOLD - 0.16, HOLD, _age)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2.ONE * lerpf(0.42, 1.0, pop) * bounce
	_title.modulate = Color(1.0, 1.0, 1.0, pop * fade)


func _draw() -> void:
	var extent := size
	if extent.x < 8.0 or extent.y < 8.0:
		return
	var centre := Vector2(extent.x * 0.5, 86.0)
	var flash := 1.0 - smoothstep(0.0, 0.38, _age)
	draw_circle(centre, 48.0 + _age * 280.0, Color(RED, 0.22 * flash))
	draw_circle(centre, 22.0 + _age * 210.0, Color(GOLD, 0.42 * flash))
	draw_circle(centre, 10.0 + _age * 90.0, Color(1.0, 0.95, 0.8, 0.7 * flash))
	for ring in 4:
		var ring_t := _age - float(ring) * 0.07
		if ring_t <= 0.0:
			continue
		var radius := 14.0 + ring_t * 260.0
		var alpha := 1.0 - smoothstep(0.0, 0.72, ring_t)
		var tint := RED if ring % 2 == 0 else GOLD
		draw_arc(centre, radius, 0.0, TAU, 48, Color(tint, alpha), 3.4, true)
	for spark in 20:
		var ang := float(spark) * TAU / 20.0 + _age * 0.9
		var reach := 18.0 + _age * 320.0
		var alpha := 1.0 - smoothstep(0.04, 0.88, _age)
		var tip := centre + Vector2(cos(ang), sin(ang)) * reach
		var mid := centre + Vector2(cos(ang), sin(ang)) * (reach * 0.52)
		var spark_color := GOLD if spark % 3 != 0 else GREEN
		draw_line(mid, tip, Color(RED, alpha * 0.75), 2.2)
		draw_circle(tip, 3.2, Color(spark_color, alpha))
