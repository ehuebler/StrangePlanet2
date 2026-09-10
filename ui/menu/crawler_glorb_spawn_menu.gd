class_name CrawlerGlorbSpawnMenu
extends Control

## Pause-free M menu. Toggle the field roster, set how many of each spawn
## around you, or drop one about 50 m ahead.

signal closed

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const GREEN := Color("45df68")
const BLACK := Color(0.0, 0.0, 0.0, 0.82)

var _player: Node3D
var _closing := false
var _status: Label
var _card: PanelContainer
var _count_label: Label
var _on_buttons: Dictionary = {}
var _kind_counts: Dictionary = {}


func configure(player: Node3D) -> void:
	_player = player


func _init() -> void:
	name = "CrawlerGlorbSpawnMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 70


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_place_card()
	resized.connect(_place_card)
	CrtType.watch(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_M:
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"inventory"):
		_close()
		get_viewport().set_input_as_handled()


func close() -> void:
	_close()


func spawn_kind(kind: String, agro: bool) -> CrawlerMob:
	if _closing or not CrawlerRules.is_glorb_kind(kind):
		return null
	var horde := CrawlerHorde.instance(get_tree())
	if horde == null:
		_set_status("No horde to spawn into.")
		return null
	var mob := horde.spawn_glorb_ahead(_player, kind, agro)
	if mob == null:
		_set_status("Could not spawn %s." % _label(kind))
		return null
	var stance := "agroed" if agro else "deagroed"
	_set_status("Spawned %s %s." % [_label(kind), stance])
	return mob


func set_kind_on(kind: String, on: bool) -> void:
	CrawlerRules.set_glorb_kind_enabled(kind, on)
	_refresh_on_button(kind)
	_apply_field()
	var state := "on" if on else "off"
	_set_status("%s field spawn %s." % [_label(kind), state])


func set_around_count(count: int) -> void:
	CrawlerRules.set_glorb_each(count)
	_refresh_count()
	_apply_field()
	_set_status("%d of each around you." % CrawlerRules.glorb_each)


func set_kind_count(kind: String, count: int) -> void:
	CrawlerRules.set_glorb_kind_count(kind, count)
	_refresh_kind_count(kind)
	_apply_field()
	_set_status("%d %s around you." % [
		CrawlerRules.glorb_kind_count(kind), _label(kind)])


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_card = PanelContainer.new()
	_card.name = "GlorbCard"
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK
	box.set_border_width_all(0)
	box.set_corner_radius_all(12)
	_card.add_theme_stylebox_override(&"panel", box)
	var rim := RedGlowPanel.add_to(_card)
	rim.fill_color = Color.TRANSPARENT
	rim.border_color = Color(RED_BRIGHT, 0.95)
	rim.border_width = 2.0
	rim.glow_intensity = 1.25
	rim.glow_spread = 8.0
	rim.glow_layers = 4
	add_child(_card)

	var inset := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		inset.add_theme_constant_override(side, 18)
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.add_child(inset)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(body)

	var title := Label.new()
	title.text = "GLORB FIELD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 26)
	title.add_theme_color_override(&"font_color", RED_BRIGHT)
	body.add_child(title)

	var copy := Label.new()
	copy.text = "Switch kinds on or off, set how many of each spawn around you, or drop one 50 m ahead."
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_theme_font_size_override(&"font_size", 14)
	copy.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	body.add_child(copy)
	body.add_child(_make_count_row())

	var scroll := ScrollContainer.new()
	scroll.name = "KindScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "KindList"
	list.add_theme_constant_override(&"separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for kind: String in CrawlerRules.GLORB_KINDS:
		list.add_child(_make_row(kind))

	_status = Label.new()
	_status.name = "SpawnStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override(&"font_size", 14)
	_status.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.86))
	_status.text = "M or Esc closes."
	body.add_child(_status)

	var done := Button.new()
	done.name = "CloseButton"
	done.text = "CLOSE"
	done.custom_minimum_size = Vector2(0.0, 38.0)
	done.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	done.add_theme_font_size_override(&"font_size", 18)
	done.add_theme_color_override(&"font_color", GREEN)
	done.pressed.connect(_close)
	body.add_child(done)


func _make_count_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "AroundRow"
	row.add_theme_constant_override(&"separation", 10)
	var name_label := Label.new()
	name_label.text = "ALL TYPES"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 16)
	name_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.94))
	row.add_child(name_label)
	row.add_child(_make_step("AroundMinus", "−", -1))
	_count_label = Label.new()
	_count_label.name = "AroundCount"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.custom_minimum_size = Vector2(48.0, 0.0)
	_count_label.add_theme_font_size_override(&"font_size", 20)
	_count_label.add_theme_color_override(&"font_color", GREEN)
	row.add_child(_count_label)
	row.add_child(_make_step("AroundPlus", "+", 1))
	_refresh_count()
	return row


func _make_step(node_name: String, text: String, delta: int) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(40.0, 34.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", 20)
	button.add_theme_color_override(&"font_color", GREEN)
	button.pressed.connect(func() -> void:
		set_around_count(CrawlerRules.glorb_each + delta)
	)
	return button


func _make_kind_step(kind: String, text: String, delta: int) -> Button:
	var button := Button.new()
	button.name = "%s_%s" % ["CountMinus" if delta < 0 else "CountPlus", kind]
	button.text = text
	button.custom_minimum_size = Vector2(40.0, 34.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", 20)
	button.add_theme_color_override(&"font_color", GREEN)
	button.pressed.connect(func() -> void:
		set_kind_count(kind, CrawlerRules.glorb_kind_count(kind) + delta)
	)
	return button


func _make_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = kind
	row.add_theme_constant_override(&"separation", 8)
	var toggle := Button.new()
	toggle.name = "On_%s" % kind
	toggle.custom_minimum_size = Vector2(72.0, 34.0)
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle.add_theme_font_size_override(&"font_size", 14)
	toggle.pressed.connect(func() -> void:
		set_kind_on(kind, not CrawlerRules.glorb_kind_enabled(kind))
	)
	_on_buttons[kind] = toggle
	row.add_child(toggle)
	_refresh_on_button(kind)
	var name_label := Label.new()
	name_label.text = _label(kind).to_upper()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 16)
	name_label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.94))
	row.add_child(name_label)
	row.add_child(_make_kind_step(kind, "−", -1))
	var count := Label.new()
	count.name = "Count_%s" % kind
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.custom_minimum_size = Vector2(48.0, 0.0)
	count.add_theme_font_size_override(&"font_size", 20)
	count.add_theme_color_override(&"font_color", GREEN)
	_kind_counts[kind] = count
	row.add_child(count)
	_refresh_kind_count(kind)
	row.add_child(_make_kind_step(kind, "+", 1))
	row.add_child(_make_button("Agro_%s" % kind, "AGRO", kind, true))
	row.add_child(_make_button("Calm_%s" % kind, "CALM", kind, false))
	return row


func _make_button(node_name: String, text: String, kind: String, agro: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(88.0, 34.0)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", 15)
	button.add_theme_color_override(&"font_color", GREEN)
	button.pressed.connect(func() -> void: spawn_kind(kind, agro))
	return button


func _refresh_on_button(kind: String) -> void:
	var button := _on_buttons.get(kind) as Button
	if button == null:
		return
	var on := CrawlerRules.glorb_kind_enabled(kind)
	button.text = "ON" if on else "OFF"
	button.add_theme_color_override(&"font_color", GREEN if on else Color(RED, 0.82))


func _refresh_kind_count(kind: String) -> void:
	var label := _kind_counts.get(kind) as Label
	if label != null:
		label.text = str(CrawlerRules.glorb_kind_count(kind))


func _refresh_count() -> void:
	if _count_label != null:
		_count_label.text = str(CrawlerRules.glorb_each)
	for kind: String in CrawlerRules.GLORB_KINDS:
		_refresh_kind_count(kind)


func _apply_field() -> void:
	var horde := CrawlerHorde.instance(get_tree())
	if horde != null:
		horde.apply_glorb_roster()


func _place_card() -> void:
	if _card == null:
		return
	var view := get_viewport_rect().size
	if view.x < 8.0 or view.y < 8.0:
		view = Vector2(1280.0, 720.0)
	var wide := minf(720.0, maxf(view.x - 40.0, 400.0))
	var top := 28.0
	var bottom_pad := 36.0
	var height := clampf(view.y - top - bottom_pad, 320.0, 620.0)
	if top + height > view.y - 16.0:
		height = maxf(view.y - top - 16.0, 260.0)
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.0
	_card.anchor_bottom = 0.0
	_card.offset_left = -wide * 0.5
	_card.offset_right = wide * 0.5
	_card.offset_top = top
	_card.offset_bottom = top + height


func _label(kind: String) -> String:
	return CrawlerMobs.title(kind).replace("Glorb ", "")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
