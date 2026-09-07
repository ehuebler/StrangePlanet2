class_name EnemyCreatorMenu
extends Control

## Compact tilde-tool sheet: three ability slots, a behaviour, and spawn.

signal closed
signal spawn_requested(abilities: PackedStringArray, behavior: int)

const THEME: Theme = preload("res://ui/themes/main_theme.tres")

const BEHAVIOR_LABELS := ["Attack", "Flee", "Circle run", "Circle fly"]

var _slots := PackedStringArray(["", "", ""])
var _picking := -1
var _behavior: int = EnemyPlayerAI.Behavior.ATTACK
var _closing := false
var _slot_buttons: Array[Button] = []
var _behavior_buttons: Array[Button] = []
var _catalog: GridContainer
var _spawn_button: Button
var _status: Label


func _init() -> void:
	name = "EnemyCreatorMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fill_defaults()
	_build()
	CrtType.watch(self)
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"inventory"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


func _fill_defaults() -> void:
	var ids := ItemDB.ability_ids()
	for index in _slots.size():
		if index < ids.size():
			_slots[index] = ids[index]


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -310
	panel.offset_top = -260
	panel.offset_right = 310
	panel.offset_bottom = 260
	add_child(panel)
	RedHudTheme.panel(panel, 16.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Enemy creator"
	RedHudTheme.label(title, 22)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Pick three abilities. The dummy uses the same body and clips as you."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RedHudTheme.label(hint, 13)
	box.add_child(hint)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 8)
	box.add_child(slot_row)
	for index in _slots.size():
		var slot := Button.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size.y = 64
		RedHudTheme.button(slot, 14, 8.0)
		var chosen := index
		slot.pressed.connect(func() -> void: _select_slot(chosen))
		_slot_buttons.append(slot)
		slot_row.add_child(slot)

	var behavior_caption := Label.new()
	behavior_caption.text = "Behaviour"
	RedHudTheme.label(behavior_caption, 14)
	box.add_child(behavior_caption)

	var behavior_row := HBoxContainer.new()
	behavior_row.add_theme_constant_override("separation", 8)
	box.add_child(behavior_row)
	for index in BEHAVIOR_LABELS.size():
		var button := Button.new()
		button.text = BEHAVIOR_LABELS[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		RedHudTheme.button(button, 13, 8.0)
		var chosen := index
		button.pressed.connect(func() -> void: _set_behavior(chosen))
		_behavior_buttons.append(button)
		behavior_row.add_child(button)

	var catalog_caption := Label.new()
	catalog_caption.text = "Abilities"
	RedHudTheme.label(catalog_caption, 14)
	box.add_child(catalog_caption)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 220
	box.add_child(scroll)
	_catalog = GridContainer.new()
	_catalog.columns = 2
	_catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_catalog.add_theme_constant_override("h_separation", 8)
	_catalog.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_catalog)
	_fill_catalog()

	_status = Label.new()
	RedHudTheme.label(_status, 13)
	box.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)
	_spawn_button = Button.new()
	_spawn_button.text = "Spawn  (5s)"
	_spawn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RedHudTheme.button(_spawn_button, 16, 10.0)
	_spawn_button.pressed.connect(_spawn)
	actions.add_child(_spawn_button)
	var cancel := Button.new()
	cancel.text = "Close"
	cancel.custom_minimum_size.x = 120
	RedHudTheme.button(cancel, 16, 10.0)
	cancel.pressed.connect(close)
	actions.add_child(cancel)


func _fill_catalog() -> void:
	for child in _catalog.get_children():
		child.queue_free()
	for id in ItemDB.ability_ids():
		var button := Button.new()
		button.text = ItemDB.title(id)
		button.tooltip_text = ItemDB.description(id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40
		RedHudTheme.button(button, 13, 7.0)
		var icon := ItemDB.ability_icon(id)
		if icon != null:
			button.icon = icon
			button.expand_icon = true
		var chosen := id
		button.pressed.connect(func() -> void: _assign(chosen))
		_catalog.add_child(button)


func _select_slot(index: int) -> void:
	_picking = index
	_refresh()


func _assign(id: String) -> void:
	if not ItemDB.accepts_ability(id):
		return
	if _picking < 0:
		_picking = _first_empty_or_zero()
	_slots[_picking] = id
	_picking = (_picking + 1) % _slots.size()
	_refresh()


func _first_empty_or_zero() -> int:
	for index in _slots.size():
		if _slots[index].is_empty():
			return index
	return 0


func _set_behavior(index: int) -> void:
	_behavior = clampi(index, 0, EnemyPlayerAI.Behavior.size() - 1)
	_refresh()


func _spawn() -> void:
	if not _ready_to_spawn():
		return
	spawn_requested.emit(_slots.duplicate(), _behavior)
	close()


func _ready_to_spawn() -> bool:
	for id in _slots:
		if not ItemDB.accepts_ability(id):
			return false
	return true


func _refresh() -> void:
	for index in _slot_buttons.size():
		var id := _slots[index]
		var button := _slot_buttons[index]
		button.text = "Slot %d\n%s" % [index + 1,
			ItemDB.title(id) if ItemDB.accepts_ability(id) else "Empty"]
		button.icon = ItemDB.ability_icon(id)
		button.expand_icon = button.icon != null
	for index in _behavior_buttons.size():
		var button := _behavior_buttons[index]
		button.disabled = index == _behavior
	if _spawn_button != null:
		_spawn_button.disabled = not _ready_to_spawn()
	if _status != null:
		if _picking >= 0:
			_status.text = "Assigning slot %d. New abilities appear here automatically." % (
				_picking + 1)
		else:
			_status.text = "Spawns in front of you after five seconds. The cylinder stays."
