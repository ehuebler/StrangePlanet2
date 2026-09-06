class_name CrawlerCityCounter
extends Control

## Upper-right crawler tally. Starts at zero and only moves after the player
## walks out of a fallen city's shelter.

var _plate: Panel
var _label: Label


func _ready() -> void:
	name = "CrawlerCityCounter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -168.0
	offset_top = 16.0
	offset_right = -16.0
	offset_bottom = 58.0
	_plate = Panel.new()
	_plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RedHudTheme.panel(_plate, 8.0)
	add_child(_plate)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = "CITIES  0"
	RedHudTheme.label(_label, 18)
	add_child(_label)


func set_count(value: int) -> void:
	if _label == null:
		return
	_label.text = "CITIES  %d" % maxi(value, 0)
