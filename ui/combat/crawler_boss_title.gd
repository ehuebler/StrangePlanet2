class_name CrawlerBossTitle
extends Control

## Falling sting for boss intro, fail, and slay banners.

signal finished

const HOLD := 2.15
const FALL := 0.42
const RED := Color("ef151f")
const GOLD := Color("ffd45a")
const LEAF := Color("5dcf3a")

var _age := 0.0
var _done := false
var _headline := "BOSS BATTLE"
var _subtitle := ""
var _leaves := false
var _title: Label
var _sub: Label
var _hint: Label
var _column: VBoxContainer
var _particles: Array[Dictionary] = []


func _init() -> void:
	name = "CrawlerBossTitle"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_meta(&"crt_skip", true)


static func present(
		host: Node,
		headline: String,
		subtitle := "",
		with_leaves := false,
		show_skip := false
	) -> Control:
	if host == null:
		return null
	var existing := host.get_node_or_null("CrawlerBossTitle")
	if existing != null:
		existing.queue_free()
	var layer := host.get_node_or_null("CrawlerBossTitleLayer") as CanvasLayer
	if layer != null:
		layer.queue_free()
	layer = CanvasLayer.new()
	layer.name = "CrawlerBossTitleLayer"
	layer.layer = 80
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var card = load("res://ui/combat/crawler_boss_title.gd").new()
	card._headline = headline
	card._subtitle = subtitle
	card._leaves = with_leaves
	layer.add_child(card)
	if show_skip:
		card.show_skip()
	return card


static func present_skip(host: Node) -> Control:
	return present(host, "", "", false, true)


func show_skip() -> void:
	if _hint == null:
		return
	_hint.visible = true


func _ready() -> void:
	_column = VBoxContainer.new()
	_column.name = "TitleColumn"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_column.offset_left = 24.0
	_column.offset_right = -24.0
	_column.offset_top = -220.0
	_column.offset_bottom = -80.0
	add_child(_column)
	_title = Label.new()
	_title.name = "BossHeadline"
	_title.text = _headline
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override(&"font_size", 56)
	_title.add_theme_color_override(&"font_color", Color(1.0, 0.96, 0.88, 1.0))
	_title.add_theme_color_override(&"font_outline_color", RED)
	_title.add_theme_constant_override(&"outline_size", 12)
	_title.visible = not _headline.is_empty()
	_column.add_child(_title)
	_sub = Label.new()
	_sub.name = "BossSubtitle"
	_sub.text = _subtitle
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.add_theme_font_size_override(&"font_size", 30)
	_sub.add_theme_color_override(&"font_color", Color(0.82, 0.96, 0.62, 1.0))
	_sub.add_theme_color_override(&"font_outline_color", Color(0.08, 0.18, 0.04, 1.0))
	_sub.add_theme_constant_override(&"outline_size", 8)
	_sub.visible = not _subtitle.is_empty()
	_column.add_child(_sub)
	_hint = Label.new()
	_hint.text = "HOLD SPACE TO SKIP"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -280.0
	_hint.offset_top = -42.0
	_hint.offset_right = -18.0
	_hint.offset_bottom = -14.0
	_hint.add_theme_font_size_override(&"font_size", 14)
	_hint.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.72))
	_hint.visible = false
	add_child(_hint)
	if _leaves:
		_seed_leaves()
	_drive()


func _process(delta: float) -> void:
	if _done:
		return
	_age += maxf(delta, 0.0)
	_drive()
	queue_redraw()
	if _age >= HOLD:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	var layer := get_parent()
	queue_free()
	if layer is CanvasLayer:
		layer.queue_free()


func _drive() -> void:
	var fall := 1.0 - pow(1.0 - clampf(_age / FALL, 0.0, 1.0), 3.0)
	var fade := 1.0 - smoothstep(HOLD - 0.22, HOLD, _age)
	var top := size.y * 0.16
	if _column != null:
		_column.offset_top = lerpf(-220.0, top, fall)
		_column.offset_bottom = _column.offset_top + 140.0
		_column.modulate.a = fade
	if _title != null:
		_title.modulate.a = fade
	if _sub != null:
		var pop := smoothstep(0.18, 0.48, _age)
		_sub.modulate.a = pop * fade


func _seed_leaves() -> void:
	_particles.clear()
	for index in 28:
		_particles.append({
			"ang": float(index) * TAU / 28.0,
			"spin": lerpf(-2.4, 2.4, float(index % 7) / 6.0),
			"reach": 18.0 + float(index % 5) * 7.0,
		})


func _draw() -> void:
	if not _leaves or size.x < 8.0:
		return
	var centre := Vector2(size.x * 0.5, size.y * 0.16 + 108.0)
	var fade := 1.0 - smoothstep(HOLD - 0.28, HOLD, _age)
	var pop := smoothstep(0.18, 0.5, _age)
	for row: Dictionary in _particles:
		var ang := float(row["ang"]) + _age * float(row["spin"])
		var reach := float(row["reach"]) + _age * 46.0
		var at := centre + Vector2(cos(ang), sin(ang) * 0.55) * reach
		var leaf := Color(LEAF, pop * fade * 0.85)
		draw_circle(at, 3.4, leaf)
		draw_circle(at + Vector2(2.2, -1.4), 2.1, Color(GOLD, pop * fade * 0.55))
