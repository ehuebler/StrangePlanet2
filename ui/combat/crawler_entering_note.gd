class_name CrawlerEnteringNote
extends Control

## Top-centre crawler toast: "Entering ..." fades in, holds, then fades out.

const HOLD := 2.4
const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")

var _age := 0.0
var _playing := false
var _title: Label
var _bonus: Label


func _init() -> void:
	name = "CrawlerEnteringNote"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 0.0
	offset_top = 22.0
	offset_right = 0.0
	offset_bottom = 128.0
	visible = false


func _ready() -> void:
	_ensure_labels()


func _ensure_labels() -> void:
	if _title != null:
		return
	var column := VBoxContainer.new()
	column.name = "EnteringColumn"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	_title = Label.new()
	_title.name = "EnteringTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_size_override(&"font_size", 34)
	_title.add_theme_color_override(&"font_color", PALETTE.text_primary)
	_title.add_theme_color_override(&"font_outline_color", PALETTE.ink)
	_title.add_theme_constant_override(&"outline_size", 8)
	column.add_child(_title)
	_bonus = Label.new()
	_bonus.name = "EnteringGems"
	_bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bonus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bonus.visible = false
	_bonus.add_theme_font_size_override(&"font_size", 22)
	_bonus.add_theme_color_override(&"font_color", PALETTE.accent)
	_bonus.add_theme_color_override(&"font_outline_color", PALETTE.ink)
	_bonus.add_theme_constant_override(&"outline_size", 6)
	column.add_child(_bonus)
	CrtType.watch(self, true)


func present(place: String, gems := 0) -> void:
	var clean := place.strip_edges()
	if clean.is_empty():
		return
	present_lines(
		"Entering %s" % clean,
		"+%d gems" % gems if gems > 0 else ""
	)


func present_lines(title: String, detail := "") -> void:
	var heading := title.strip_edges()
	if heading.is_empty():
		return
	if _title == null:
		_ensure_labels()
	_title.text = heading
	var extra := detail.strip_edges()
	_bonus.text = extra
	_bonus.visible = not extra.is_empty()
	_age = 0.0
	_playing = true
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 0.0)


func current_text() -> String:
	return _title.text if _title != null else ""


func bonus_text() -> String:
	return _bonus.text if _bonus != null and _bonus.visible else ""


func _process(delta: float) -> void:
	if not _playing:
		return
	_age += maxf(delta, 0.0)
	var pop := smoothstep(0.0, 0.2, _age)
	var fade := 1.0 - smoothstep(HOLD - 0.7, HOLD, _age)
	modulate = Color(1.0, 1.0, 1.0, pop * fade)
	if _age >= HOLD:
		_playing = false
		visible = false
		modulate = Color(1.0, 1.0, 1.0, 0.0)
