class_name SettingsPanel
extends VBoxContainer

## The settings screen, in one place for both the ways it is reached: the home
## screen puts it up over the starfield, and the Settings tab of [GameMenu] puts
## the same thing over a paused world.
##
## One panel rather than two because a setting is a setting — a second in-game copy
## would be a second place for the rows, the write-through and the rebind capture
## to drift, and the pair would disagree about defaults the first time one of them
## gained a row. Both entrances share the same sharp red/green presentation and
## section layout. Only the outer navigation differs: home draws its own card and
## offers BACK, while GameMenu supplies the frame and session actions beneath it.
##
## Sections are four buttons over one content area rather than a [TabContainer].
## A tab container brings its own tab strip, and inside [GameMenu] that would be a
## second row of tabs under the first, in a style nothing else here uses.
##
## The controls list is generated from [InputMap], so a new action is rebindable
## with no edit in this file.

signal closed

const SettingsManagerScript := preload("res://core/settings_manager.gd")

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const BLACK_82 := Color(0.0, 0.0, 0.0, 0.82)

## Section name and the builder for it. Walked to make both the buttons and the
## pages, so the two cannot fall out of order.
const SECTIONS: Array[String] = ["Display", "Audio", "Gameplay", "Controls / Info"]

var _settings: GameSettingsManager
## While a rebind row is armed, the next key or button press belongs to it rather
## than to the menu, which is why this is read in _input and not _unhandled_input.
var _rebind_action: StringName
var _rebind_button: Button
var _in_game := false
var _section := 0
var _section_row: HBoxContainer
var _content: MarginContainer
var _save_button: Button
var _load_button: Button
var _save_note: Label


## Called before the panel enters the tree. In game it drops its own card,
## heading, and BACK action because GameMenu already supplies all three.
func configure(in_game: bool) -> void:
	_in_game = in_game


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings = get_node_or_null("/root/SettingsManager") as GameSettingsManager
	if _settings == null:
		_settings = SettingsManagerScript.new()
		_settings.name = "LocalSettingsManager"
		add_child(_settings)
	_build()
	CrtType.watch(self)


func _input(event: InputEvent) -> void:
	if _rebind_button == null:
		return
	if event is InputEventKey and not event.pressed:
		return
	if event is InputEventMouseButton and not event.pressed:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_settings.rebind_action(_rebind_action, event)
		_rebind_button.text = event.as_text()
		_style_red_button(_rebind_button, false)
		_rebind_button = null
		_rebind_action = &""
		get_viewport().set_input_as_handled()


## Rebuilt wholesale after a reset to defaults, so every control re-reads the
## value it is showing instead of being walked back one at a time.
func _build() -> void:
	for child: Node in get_children():
		if child != _settings:
			child.queue_free()

	var box := self as Control
	if not _in_game:
		var card := PanelContainer.new()
		card.name = "HomeSettingsFrame"
		card.custom_minimum_size = Vector2(
			MenuWidgets.panel_width(self, 0.88, 1240.0),
			0.0
		)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override(
			&"panel",
			_style(Color(0.0, 0.0, 0.0, 0.42), Color(RED_BRIGHT, 0.94), 2, 16.0,
				Color(RED, 0.20), 8)
		)
		var glow := RedGlowPanel.add_to(card)
		glow.fill_color = Color(0.0, 0.0, 0.0, 0.16)
		glow.border_color = Color(RED_BRIGHT, 0.96)
		glow.border_width = 2.0
		glow.glow_intensity = 1.35
		glow.glow_spread = 11.0
		glow.glow_layers = 5
		add_child(card)

		var column := VBoxContainer.new()
		column.name = "HomeSettingsContent"
		column.add_theme_constant_override(&"separation", 8)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_child(column)
		box = column

		var header := HBoxContainer.new()
		header.add_theme_constant_override(&"separation", 16)
		var title := Label.new()
		title.text = "SETTINGS"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_red_label(title, RED_BRIGHT, 26)
		header.add_child(title)
		var caption := _settings_caption("CHANGES SAVE AS YOU MAKE THEM")
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.custom_minimum_size.x = 260.0
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_child(caption)
		column.add_child(header)
		column.add_child(_settings_rule())

	_section_row = HBoxContainer.new()
	_section_row.add_theme_constant_override("separation", 8)
	box.add_child(_section_row)

	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.custom_minimum_size = Vector2(0, 190)
	box.add_child(_content)

	box.add_child(_footer())
	show_section(_section)


## The section buttons are redrawn on every switch so both entrances show the
## same green selected state.
func _fill_section_row() -> void:
	for child in _section_row.get_children():
		child.queue_free()
	for index in SECTIONS.size():
		var button := _settings_button(SECTIONS[index], index == _section)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		var chosen := index
		button.pressed.connect(func() -> void: show_section(chosen))
		_section_row.add_child(button)


## Switches section. Public because a harness photographs each one, and because the
## in-game tab may one day want to open straight on the controls list.
func show_section(index: int) -> void:
	_section = clampi(index, 0, SECTIONS.size() - 1)
	_fill_section_row()
	for child in _content.get_children():
		child.queue_free()
	var page: VBoxContainer
	match _section:
		0: page = _display_section()
		1: page = _audio_section()
		2: page = _gameplay_section()
		_: page = _controls_section()
	_content.add_child(_scrolled(page))


func _footer() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)
	var reset := _settings_button("RESET DEFAULTS")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func() -> void:
		_settings.reset_to_defaults()
		_build()
	)
	actions.add_child(reset)

	_save_button = _settings_button("SAVE GAME")
	_save_button.name = "SettingsSaveGame"
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_button.pressed.connect(_on_save_game)
	actions.add_child(_save_button)

	_load_button = _settings_button("LOAD GAME")
	_load_button.name = "SettingsLoadGame"
	_load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_button.pressed.connect(_on_load_game)
	actions.add_child(_load_button)

	if not _in_game:
		var back := _settings_button("BACK", true)
		back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		back.pressed.connect(func() -> void:
			_settings.save_settings()
			closed.emit()
		)
		actions.add_child(back)

	column.add_child(actions)
	_save_note = _settings_caption("")
	_save_note.name = "SettingsSaveNote"
	_save_note.visible = false
	column.add_child(_save_note)
	_refresh_save_buttons()
	return column


func _refresh_save_buttons() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if _save_button != null:
		var can_save := GameSave.can_write(tree)
		_save_button.disabled = not can_save
		_save_button.tooltip_text = "" if can_save else "The host can save during a run."
	if _load_button != null:
		var can_load := GameSave.can_apply(tree)
		_load_button.disabled = not can_load
		_load_button.tooltip_text = "" if can_load else (
			"No saved game yet." if not GameSave.has_save() else "Only the host can load a run."
		)


func _on_save_game() -> void:
	var world := GameSave.world_of(get_tree() if is_inside_tree() else null)
	if not GameSave.write_from_world(world):
		_set_save_note("Could not save the game.", true)
		return
	_set_save_note("Game saved.", false)
	_refresh_save_buttons()


func _on_load_game() -> void:
	var payload := GameSave.read()
	if payload.is_empty():
		_set_save_note("No saved game yet.", true)
		_refresh_save_buttons()
		return
	var world := GameSave.world_of(get_tree() if is_inside_tree() else null)
	if world != null and world.has_method(&"session_is_open") \
			and bool(world.call(&"session_is_open")):
		if not bool(world.call(&"apply_disk_save", payload)):
			_set_save_note("Could not load the save.", true)
			return
		_set_save_note("Game loaded.", false)
		var player := world.call(&"local_player") as OnlinePlayer \
			if world.has_method(&"local_player") else null
		if player != null:
			player.close_menu()
		return
	var home := world.get_node_or_null("HomeScreen") as HomeScreen if world != null else null
	if home != null:
		closed.emit()
		home.start_saved_game()
		return
	_set_save_note("Could not load the save.", true)


func _set_save_note(text: String, is_error: bool) -> void:
	if _save_note == null:
		return
	_save_note.text = text
	_save_note.visible = not text.is_empty()
	_style_red_label(_save_note, RED_BRIGHT if is_error else GREEN_TEXT, 13)


func _section_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	return box


## Every section scrolls. The card has to fit between the title and the foot of
## the screen, and the rebind list alone is longer than that at any size the type
## is actually readable at.
func _scrolled(box: VBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The scrollbar is drawn over the content, not beside it, so without this it
	# sits on the right-hand end of every slider and on the value above it.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override(&"margin_right", 14)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(box)
	scroll.add_child(inset)
	_style_scrollbar(scroll.get_v_scroll_bar())
	return scroll


func _display_section() -> VBoxContainer:
	var tab := _section_box()
	tab.add_child(_option_row(
		"Window mode",
		["Windowed", "Borderless fullscreen", "Exclusive fullscreen"],
		int(_settings.get_setting(&"graphics", &"window_mode", 0)),
		func(value: int) -> void: _write(&"graphics", &"window_mode", value)
	))
	var resolutions := ["1280x720", "1600x900", "1920x1080", "2560x1440"]
	var saved_resolution := String(_settings.get_setting(&"graphics", &"resolution", "1280x720"))
	tab.add_child(_option_row(
		"Resolution",
		resolutions,
		maxi(resolutions.find(saved_resolution), 0),
		func(value: int) -> void: _write(&"graphics", &"resolution", resolutions[value])
	))
	tab.add_child(_toggle_row(
		"Vertical sync",
		bool(_settings.get_setting(&"graphics", &"vsync", true)),
		func(value: bool) -> void: _write(&"graphics", &"vsync", value)
	))
	tab.add_child(_slider_row(
		"Frame rate limit", 30.0, 240.0, 10.0,
		float(_settings.get_setting(&"graphics", &"max_fps", 120)),
		func(value: float) -> void: _write(&"graphics", &"max_fps", int(value)),
		" FPS"
	))
	tab.add_child(_slider_row(
		"Render scale", 0.5, 2.0, 0.05,
		float(_settings.get_setting(&"graphics", &"render_scale", 1.0)),
		func(value: float) -> void: _write(&"graphics", &"render_scale", value),
		"x"
	))
	tab.add_child(_option_row(
		"Graphics quality",
		["Low", "Medium", "High"],
		int(_settings.get_setting(&"graphics", &"quality", 1)),
		func(value: int) -> void: _write(&"graphics", &"quality", value)
	))
	# Labelled by the planet, so the row cannot come to offer a level the terrain
	# does not have.
	var distances: Array[String] = []
	for level: Dictionary in Planet.DETAIL_LEVELS:
		distances.append(String(level["label"]))
	tab.add_child(_option_row(
		"Render distance",
		distances,
		int(_settings.get_setting(&"graphics", &"render_distance", 1)),
		func(value: int) -> void: _write(&"graphics", &"render_distance", value)
	))
	# Separate from render distance: that one buys terrain, this one buys the
	# plants standing on it, and they are nothing like the same cost.
	tab.add_child(_slider_row(
		"Flora view distance", 0.5, 4.0, 0.25,
		float(_settings.get_setting(&"graphics", &"flora_range", 2.0)),
		func(value: float) -> void: _write(&"graphics", &"flora_range", value),
		"x"
	))
	# The two atmosphere effects. Both land the moment they are switched — the
	# scattering through a shader global and the rays by enabling the compositor
	# effect — so this page can be left open while they are compared.
	tab.add_child(_toggle_row(
		"Atmospheric scattering",
		bool(_settings.get_setting(&"graphics", &"atmospheric_scattering", true)),
		func(value: bool) -> void:
			_write(&"graphics", &"atmospheric_scattering", value)
	))
	tab.add_child(_toggle_row(
		"God rays",
		bool(_settings.get_setting(&"graphics", &"god_rays", true)),
		func(value: bool) -> void: _write(&"graphics", &"god_rays", value)
	))
	return tab


func _audio_section() -> VBoxContainer:
	var tab := _section_box()
	for setting: Dictionary in [
		{"label": "Master volume", "key": &"master_volume"},
		{"label": "Music volume", "key": &"music_volume"},
		{"label": "Sound effects", "key": &"sfx_volume"},
		{"label": "Voice chat", "key": &"voice_volume"},
	]:
		var key: StringName = setting.key
		tab.add_child(_slider_row(
			setting.label, 0.0, 1.0, 0.01,
			float(_settings.get_setting(&"audio", key, 0.8)),
			func(value: float) -> void: _write(&"audio", key, value),
			"%"
		))
	return tab


func _gameplay_section() -> VBoxContainer:
	var tab := _section_box()
	tab.add_child(_slider_row(
		"Mouse sensitivity", 0.05, 1.0, 0.05,
		float(_settings.get_setting(&"gameplay", &"mouse_sensitivity", 0.35)),
		func(value: float) -> void: _write(&"gameplay", &"mouse_sensitivity", value)
	))
	tab.add_child(_toggle_row(
		"Invert vertical look",
		bool(_settings.get_setting(&"gameplay", &"invert_y", false)),
		func(value: bool) -> void: _write(&"gameplay", &"invert_y", value)
	))
	tab.add_child(_slider_row(
		"Field of view", 60.0, 110.0, 1.0,
		float(_settings.get_setting(&"gameplay", &"fov", 75.0)),
		func(value: float) -> void: _write(&"gameplay", &"fov", value),
		"deg"
	))
	return tab


## The rebind list, and the handful of facts worth being able to read back without
## leaving the game.
func _controls_section() -> VBoxContainer:
	var tab := _section_box()
	var found_actions := false
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		found_actions = true
		tab.add_child(_rebind_row(action))
	if not found_actions:
		tab.add_child(_settings_caption(
			"Input actions appear here after they are added to the Input Map."))

	tab.add_child(_settings_rule())
	var about := Label.new()
	about.text = "Godot %s    %s" % [
		Engine.get_version_info().get("string", "?"),
		"multiplayer" if NetworkManager != null and NetworkManager.in_multiplayer_session() \
			else "single player",
	]
	_style_red_label(about, RED_MUTED, 12)
	tab.add_child(about)
	return tab


func _rebind_row(action: StringName) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var label := Label.new()
	label.text = String(action).replace("_", " ").capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_red_label(label, RED_TEXT, 13)
	row.add_child(label)
	var control := _settings_button(MenuWidgets.binding_text(action))
	control.custom_minimum_size.x = 168
	control.clip_text = true
	control.pressed.connect(func() -> void:
		if _rebind_button != null:
			_rebind_button.text = MenuWidgets.binding_text(_rebind_action)
			_style_red_button(_rebind_button, false)
		_rebind_action = action
		_rebind_button = control
		control.text = "PRESS A KEY..."
		_style_red_button(control, true)
	)
	row.add_child(control)
	return _row_panel(row)


## Both entry points use these controls so their presentation cannot drift.
func _settings_button(
	label_text: String,
	selected := false,
	destructive := false
) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size.y = 36.0
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	_style_red_button(button, selected, destructive)
	return button


func _settings_caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_red_label(label, RED_MUTED, 12)
	return label


func _option_row(
	label_text: String,
	options: Array,
	selected: int,
	callback: Callable
) -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 5)
	var label := Label.new()
	label.text = label_text
	_style_red_label(label, RED_TEXT, 12)
	group.add_child(label)

	var option := OptionButton.new()
	option.custom_minimum_size.y = 34.0
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.clip_text = true
	option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for item: Variant in options:
		option.add_item(String(item))
	option.select(clampi(selected, 0, maxi(options.size() - 1, 0)))
	option.item_selected.connect(callback)
	_style_option(option)
	group.add_child(option)
	return _row_panel(group)


func _toggle_row(label_text: String, value: bool, callback: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_red_label(label, RED_TEXT, 13)
	row.add_child(label)

	var toggle := Button.new()
	toggle.text = "ON" if value else "OFF"
	toggle.toggle_mode = true
	toggle.button_pressed = value
	toggle.custom_minimum_size = Vector2(124.0, 36.0)
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_red_button(toggle, value)
	toggle.toggled.connect(func(pressed: bool) -> void:
		toggle.text = "ON" if pressed else "OFF"
		_style_red_button(toggle, pressed)
		callback.call(pressed)
	)
	row.add_child(toggle)
	return _row_panel(row)


func _slider_row(
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	callback: Callable,
	suffix := ""
) -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 4)
	var header := HBoxContainer.new()
	group.add_child(header)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_red_label(label, RED_TEXT, 13)
	header.add_child(label)

	var value_label := Label.new()
	_style_red_label(value_label, GREEN_TEXT, 13)
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 18.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_slider(slider)
	group.add_child(slider)

	var update_label := func(new_value: float) -> void:
		value_label.text = (
			"%d%s" % [roundi(new_value * 100.0), suffix]
			if suffix == "%"
			else "%.2f%s" % [new_value, suffix]
		)
	update_label.call(value)
	slider.value_changed.connect(update_label)
	slider.value_changed.connect(callback)
	return _row_panel(group)


func _settings_rule() -> Control:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(
		&"panel",
		_style(Color(RED, 0.48), RED_BRIGHT, 1, 0.0)
	)
	return rule


func _row_panel(content: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_theme_stylebox_override(
		&"panel",
		_style(
			BLACK_68 if _in_game else Color(0.0, 0.0, 0.0, 0.50),
			Color(RED, 0.72),
			1,
			9.0
		)
	)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return panel


func _style_red_button(button: Button, selected: bool, destructive := false) -> void:
	var accent := GREEN if selected else (RED_BRIGHT if destructive else RED)
	var text_color := GREEN_TEXT if selected else (RED_BRIGHT if destructive else RED_TEXT)
	var fill := Color(0.0, 0.14, 0.04, 0.78) if selected else BLACK_82
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(&"font_color", text_color)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_hover_pressed_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", text_color)
	button.add_theme_color_override(&"font_disabled_color", Color(RED_MUTED, 0.36))
	button.add_theme_color_override(
		&"font_outline_color",
		Color(0.08, 0.0, 0.0, 0.98)
	)
	button.add_theme_constant_override(&"outline_size", 1)
	button.add_theme_stylebox_override(
		&"normal",
		_style(fill, Color(accent, 0.92), 2 if selected else 1, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_82, GREEN, 2, 8.0, Color(GREEN, 0.14), 3)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.18, 0.05, 0.88), GREEN, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover_pressed",
		_style(Color(0.0, 0.20, 0.06, 0.92), GREEN_TEXT, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, GREEN, 1, 7.0)
	)
	button.add_theme_stylebox_override(
		&"disabled",
		_style(BLACK_42, Color(RED_MUTED, 0.30), 1, 8.0)
	)


func _style_option(option: OptionButton) -> void:
	option.add_theme_font_size_override(&"font_size", 12)
	option.add_theme_color_override(&"font_color", GREEN_TEXT)
	option.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	option.add_theme_color_override(&"font_pressed_color", GREEN)
	option.add_theme_color_override(&"font_focus_color", GREEN_TEXT)
	option.add_theme_color_override(
		&"font_outline_color",
		Color(0.08, 0.0, 0.0, 0.98)
	)
	option.add_theme_constant_override(&"outline_size", 1)
	option.add_theme_stylebox_override(
		&"normal",
		_style(BLACK_82, Color(RED, 0.82), 1, 8.0)
	)
	option.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_82, GREEN, 2, 8.0, Color(GREEN, 0.12), 3)
	)
	option.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.16, 0.045, 0.90), GREEN, 2, 8.0)
	)
	option.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, GREEN, 1, 7.0)
	)

	var popup := option.get_popup()
	popup.add_theme_font_size_override(&"font_size", 12)
	popup.add_theme_color_override(&"font_color", RED_TEXT)
	popup.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	popup.add_theme_color_override(&"font_checked_color", GREEN_TEXT)
	popup.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_82, RED, 1, 6.0, Color(RED, 0.16), 4)
	)
	popup.add_theme_stylebox_override(
		&"hover",
		_style(Color(0.0, 0.15, 0.04, 0.88), GREEN, 1, 5.0)
	)


func _style_slider(slider: HSlider) -> void:
	slider.add_theme_stylebox_override(
		&"slider",
		_style(BLACK_82, Color(RED, 0.88), 1, 3.0)
	)
	slider.add_theme_stylebox_override(
		&"grabber_area",
		_style(Color(GREEN, 0.78), Color(GREEN_TEXT, 0.96), 1, 3.0)
	)
	slider.add_theme_stylebox_override(
		&"grabber_area_highlight",
		_style(Color(GREEN, 0.94), GREEN_TEXT, 1, 3.0)
	)
	slider.add_theme_icon_override(&"grabber", _solid_texture(GREEN, Vector2i(8, 16)))
	slider.add_theme_icon_override(
		&"grabber_highlight",
		_solid_texture(GREEN_TEXT, Vector2i(10, 18))
	)
	slider.add_theme_icon_override(
		&"grabber_disabled",
		_solid_texture(RED_MUTED, Vector2i(8, 16))
	)


func _style_scrollbar(scrollbar: VScrollBar) -> void:
	scrollbar.custom_minimum_size.x = 10.0
	scrollbar.add_theme_stylebox_override(
		&"scroll",
		_style(BLACK_82, Color(RED, 0.62), 1, 2.0)
	)
	scrollbar.add_theme_stylebox_override(
		&"grabber",
		_style(Color(0.0, 0.16, 0.045, 0.94), GREEN, 1, 2.0)
	)
	scrollbar.add_theme_stylebox_override(
		&"grabber_highlight",
		_style(Color(0.0, 0.22, 0.065, 0.98), GREEN_TEXT, 1, 2.0)
	)
	scrollbar.add_theme_stylebox_override(
		&"grabber_pressed",
		_style(GREEN, GREEN_TEXT, 1, 2.0)
	)


func _style_red_label(label: Label, color: Color, font_size: int) -> void:
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(
		&"font_outline_color",
		Color(0.1, 0.0, 0.0, 0.94)
	)
	label.add_theme_constant_override(&"outline_size", 1)


func _solid_texture(color: Color, texture_size: Vector2i) -> ImageTexture:
	var image := Image.create(
		texture_size.x,
		texture_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _style(
	fill: Color,
	border: Color,
	border_width: int,
	padding: float,
	shadow: Color = Color.TRANSPARENT,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	box.shadow_color = shadow
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2.ZERO
	return box


func _write(section: StringName, key: StringName, value: Variant) -> void:
	_settings.set_setting(section, key, value)
	_settings.save_settings()
