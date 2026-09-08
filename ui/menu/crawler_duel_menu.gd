class_name CrawlerDuelMenu
extends Control

## Pause-free card shown with E during a city duel. Any player can end it.

signal closed

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const GREEN := Color("45df68")
const BLACK := Color(0.0, 0.0, 0.0, 0.82)

var _closing := false


func configure(_player: OnlinePlayer) -> void:
	pass


func _init() -> void:
	name = "CrawlerDuelMenu"
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
	card.name = "DuelEndCard"
	card.custom_minimum_size = Vector2(420.0, 220.0)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -210.0
	card.offset_right = 210.0
	card.offset_top = -110.0
	card.offset_bottom = 110.0
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
	body.add_theme_constant_override(&"separation", 14)
	inset.add_child(body)

	var title := Label.new()
	title.text = "DUEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 28)
	title.add_theme_color_override(&"font_color", RED_BRIGHT)
	body.add_child(title)

	var copy := Label.new()
	copy.text = "End the fight and return everyone to where they were."
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_theme_font_size_override(&"font_size", 15)
	copy.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	body.add_child(copy)

	var end := Button.new()
	end.name = "EndDuel"
	end.text = "END DUEL"
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


func _on_end() -> void:
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.request_end_duel()
	_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
