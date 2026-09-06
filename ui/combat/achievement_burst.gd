class_name AchievementBurst
extends Control

## Top-of-HUD sting when an achievement unlocks. Same band as the crawler
## level-up card: the world stays live, confetti bursts from the title.

signal finished

const HOLD := 2.2
const RED := Color("ef151f")
const GREEN := Color("39d98a")
const GOLD := Color("ffd45a")
const PIECES := 46

var title_text := "Kill 10 mobs"
var _age := 0.0
var _done := false
var _heading: Label
var _detail: Label
var _confetti: Array[Dictionary] = []


func _init() -> void:
	name = "AchievementBurst"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 70
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func configure(achievement_title: String) -> void:
	title_text = achievement_title.strip_edges()
	if title_text.is_empty():
		title_text = "Achievement"
	if _detail != null:
		_detail.text = '"%s"' % title_text


func _ready() -> void:
	_heading = Label.new()
	_heading.name = "AchievementCompleteTitle"
	_heading.text = "ACHIEVEMENT COMPLETE"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_heading.offset_left = 0.0
	_heading.offset_top = 10.0
	_heading.offset_right = 0.0
	_heading.offset_bottom = 78.0
	_heading.add_theme_font_size_override(&"font_size", 34)
	_heading.add_theme_color_override(&"font_color", Color(1.0, 0.96, 0.88, 1.0))
	_heading.add_theme_color_override(&"font_outline_color", RED)
	_heading.add_theme_constant_override(&"outline_size", 10)
	add_child(_heading)

	_detail = Label.new()
	_detail.name = "AchievementCompleteName"
	_detail.text = '"%s"' % title_text
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_detail.offset_left = 0.0
	_detail.offset_top = 68.0
	_detail.offset_right = 0.0
	_detail.offset_bottom = 128.0
	_detail.add_theme_font_size_override(&"font_size", 28)
	_detail.add_theme_color_override(&"font_color", GOLD)
	_detail.add_theme_color_override(&"font_outline_color", Color(0.08, 0.0, 0.0, 0.96))
	_detail.add_theme_constant_override(&"outline_size", 8)
	add_child(_detail)
	_seed_confetti()
	_drive_title()


func _process(delta: float) -> void:
	if _done:
		return
	_age += maxf(delta, 0.0)
	_drive_title()
	_advance_confetti(delta)
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
	var pop := smoothstep(0.0, 0.14, _age)
	var bounce := 1.0 + 0.1 * sin(_age * 22.0) * exp(_age * -5.0)
	var fade := 1.0 - smoothstep(HOLD - 0.22, HOLD, _age)
	for label: Label in [_heading, _detail]:
		if label == null:
			continue
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2.ONE * lerpf(0.42, 1.0, pop) * bounce
		label.modulate = Color(1.0, 1.0, 1.0, pop * fade)


func _seed_confetti() -> void:
	_confetti.clear()
	var colours: Array[Color] = [
		RED, GOLD, GREEN, Color("ff6b9d"), Color("6bd7ff"), Color("fff36b"),
	]
	for index in PIECES:
		_confetti.append({
			"origin": Vector2(randf_range(-220.0, 220.0), randf_range(-18.0, 28.0)),
			"velocity": Vector2(randf_range(-220.0, 220.0), randf_range(-40.0, 80.0)),
			"spin": randf_range(-8.0, 8.0),
			"size": Vector2(randf_range(6.0, 13.0), randf_range(3.0, 7.0)),
			"color": colours[index % colours.size()],
		})


func _advance_confetti(delta: float) -> void:
	for piece: Dictionary in _confetti:
		var velocity: Vector2 = piece["velocity"]
		velocity.y += 620.0 * delta
		piece["velocity"] = velocity
		piece["origin"] = piece["origin"] + velocity * delta


func _draw() -> void:
	var extent := size
	if extent.x < 8.0 or extent.y < 8.0:
		return
	var centre := Vector2(extent.x * 0.5, 72.0)
	var flash := 1.0 - smoothstep(0.0, 0.38, _age)
	draw_circle(centre, 36.0 + _age * 240.0, Color(GOLD, 0.20 * flash))
	draw_circle(centre, 16.0 + _age * 170.0, Color(RED, 0.28 * flash))
	var fade := 1.0 - smoothstep(HOLD - 0.28, HOLD, _age)
	for piece: Dictionary in _confetti:
		var at: Vector2 = centre + piece["origin"]
		var angle := _age * float(piece["spin"])
		var half: Vector2 = piece["size"] * 0.5
		var tint: Color = piece["color"]
		var points := PackedVector2Array([
			at + Vector2(-half.x, -half.y).rotated(angle),
			at + Vector2(half.x, -half.y).rotated(angle),
			at + Vector2(half.x, half.y).rotated(angle),
			at + Vector2(-half.x, half.y).rotated(angle),
		])
		draw_colored_polygon(points, Color(tint, 0.92 * fade))
