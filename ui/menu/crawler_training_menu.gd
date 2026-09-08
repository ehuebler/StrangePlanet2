class_name CrawlerTrainingMenu
extends Control

## Pause-free card shown with E on the Duals training field.

signal closed

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const GREEN := Color("45df68")
const BLACK := Color(0.0, 0.0, 0.0, 0.82)

var _closing := false
var _level_label: Label


func configure(_player: OnlinePlayer) -> void:
	pass


func _init() -> void:
	name = "CrawlerTrainingMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var card := PanelContainer.new()
	card.name = "TrainingCard"
	card.custom_minimum_size = Vector2(440.0, 320.0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -220.0
	card.offset_right = 220.0
	card.offset_top = -160.0
	card.offset_bottom = 160.0
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK
	box.set_border_width_all(0)
	box.set_corner_radius_all(12)
	card.add_theme_stylebox_override(&"panel", box)
	var rim := RedGlowPanel.add_to(card)
	rim.fill_color = Color.TRANSPARENT
	rim.border_color = Color(RED_BRIGHT, 0.95)
	rim.border_width = 2.0
	rim.glow_intensity = 1.25
	rim.glow_spread = 8.0
	rim.glow_layers = 4
	add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	card.add_child(column)
	var inset := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		inset.add_theme_constant_override(side, 22)
	column.add_child(inset)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	inset.add_child(body)

	var title := Label.new()
	title.text = "TRAINING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 28)
	title.add_theme_color_override(&"font_color", RED_BRIGHT)
	body.add_child(title)

	var copy := Label.new()
	copy.text = "Leave the field and return to your run, or raise the idle mobs."
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_theme_font_size_override(&"font_size", 15)
	copy.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	body.add_child(copy)

	_level_label = Label.new()
	_level_label.name = "TrainingLevel"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override(&"font_size", 16)
	_level_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.86))
	body.add_child(_level_label)
	_refresh_level()

	var raise := Button.new()
	raise.name = "RaiseMobs"
	raise.text = "RAISE MOB LEVEL"
	raise.custom_minimum_size = Vector2(0.0, 44.0)
	raise.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	raise.add_theme_font_size_override(&"font_size", 18)
	raise.add_theme_color_override(&"font_color", GREEN)
	raise.pressed.connect(_on_raise)
	body.add_child(raise)

	var end := Button.new()
	end.name = "EndTraining"
	end.text = "RETURN TO RUN"
	end.custom_minimum_size = Vector2(0.0, 44.0)
	end.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	end.add_theme_font_size_override(&"font_size", 18)
	end.add_theme_color_override(&"font_color", GREEN)
	end.pressed.connect(_on_end)
	body.add_child(end)
	CrtType.watch(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		_close()
		get_viewport().set_input_as_handled()


func _on_raise() -> void:
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.request_training_level(world.training_level() + 1)
	_refresh_level()


func _on_end() -> void:
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.request_end_training()
	_close()


func _refresh_level() -> void:
	if _level_label == null:
		return
	var world := NetworkManager.active_world as GameWorld
	var level := world.training_level() if world != null else 1
	_level_label.text = "MOB LEVEL  %d" % level


func _close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
