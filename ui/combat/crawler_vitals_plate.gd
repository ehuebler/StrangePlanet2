class_name CrawlerVitalsPlate
extends Control

## Small top-left crawler readout: level, XP, and gold.

const WIDTH := 220.0

var _label: Label


func _init() -> void:
	name = "CrawlerVitalsPlate"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 16.0
	offset_top = 14.0
	offset_right = 16.0 + WIDTH
	offset_bottom = 48.0


func _ready() -> void:
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RedHudTheme.label(_label, 12)
	_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.92))
	add_child(_label)


func refresh(player: Node) -> void:
	if player == null or not player.has_method(&"crawler_vitals_text"):
		visible = false
		return
	visible = CrawlerRules.active()
	if _label != null:
		_label.text = str(player.call(&"crawler_vitals_text"))
