class_name CrawlerAbilityTile
extends PanelContainer

## One crawler ability row: a fixed portrait, its name, and nested modifier
## slots. Empty rows stay drawn so the loadout always shows three spaces.
## Dragging a seated tile moves the ability and every seated modifier together.

signal picked(tile: CrawlerAbilityTile)
signal drop_requested(tile: CrawlerAbilityTile)
signal card_received(tile: CrawlerAbilityTile, data: Dictionary)
signal mod_picked(slot: RedItemSlot)
signal mod_moved(target: RedItemSlot, source: RedItemSlot)
signal mod_drop_requested(slot: RedItemSlot)
signal clear_requested(index: int)

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const GREEN := Color("45df68")
const BLACK := Color(0.0, 0.0, 0.0, 0.92)
const MOD_EDGE := 34.0
const COMPACT_MOD_EDGE := 26.0

var index := 0
var kit: CrawlerKit
## Store stalls lock this so a click only selects. The Hero page leaves it
## on so cards can be dragged, seated, or dropped.
var editable := true:
	set(value):
		editable = value
		if _clear != null:
			refresh()
## Shorter store cards: smaller portrait, tighter mods, less padding.
var compact := false:
	set(value):
		compact = value
		_apply_compact()
var selected := false:
	set(value):
		selected = value
		_apply_style()

var _number: Label
var _icon: TextureRect
var _title: Label
var _clear: Button
var _mods: HBoxContainer
var _mod_slots: Array[RedItemSlot] = []
var _drag_live := false
var _hovered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	_apply_style()


func setup(at: int, owner_kit: CrawlerKit) -> void:
	index = at
	kit = owner_kit
	if _icon == null:
		_build()
	if _number != null:
		_number.text = str(index + 1)
	if _mods != null:
		_mods.name = "CrawlerModRow_%d" % index
	refresh()


func token() -> String:
	if kit == null or kit.player == null or not is_instance_valid(kit.player) \
			or kit.player.abilities == null:
		return ""
	return kit.player.abilities.get_item(index)


func card() -> CrawlerCard:
	return kit.equipped_card(index) if kit != null else null


func mod_slots() -> Array[RedItemSlot]:
	return _mod_slots


func refresh() -> void:
	visible = true
	if _icon == null:
		return
	var hosted := card()
	if hosted == null:
		_icon.texture = null
		_icon.modulate = Color(GREEN, 0.18)
		_title.text = "EMPTY"
		if _clear != null:
			_clear.visible = false
		if _mods != null:
			_mods.visible = false
		_sync_mods(null)
		_apply_style()
		return
	var id := hosted.id
	_icon.texture = CrawlerCatalog.texture_for(id)
	_icon.modulate = _icon_modulate(id)
	_title.text = ItemDB.title(id).to_upper()
	if _clear != null:
		_clear.visible = editable
	if _mods != null:
		_mods.visible = true
	_sync_mods(hosted)
	_apply_style()


func _build() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)

	_number = Label.new()
	_number.text = str(index + 1)
	_number.add_theme_font_size_override(&"font_size", 22)
	_number.add_theme_color_override(&"font_color", RED_BRIGHT)
	_number.custom_minimum_size.x = 22.0
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_number)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override(&"separation", 4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(stack)

	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)

	_icon = TextureRect.new()
	_icon.name = "CrawlerAbilityIcon"
	_icon.custom_minimum_size = Vector2(_icon_edge(), _icon_edge())
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_icon)

	_title = Label.new()
	_title.name = "CrawlerAbilityTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override(&"font_size", 14)
	_title.add_theme_color_override(&"font_color", RED_TEXT)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_title)

	_clear = Button.new()
	_clear.name = "CrawlerClear"
	_clear.text = "X"
	_clear.focus_mode = Control.FOCUS_NONE
	_clear.mouse_filter = Control.MOUSE_FILTER_STOP
	_clear.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_clear.custom_minimum_size = Vector2(22.0, 22.0)
	_clear.size_flags_horizontal = Control.SIZE_SHRINK_END
	_clear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clear.add_theme_font_size_override(&"font_size", 11)
	_clear.add_theme_color_override(&"font_color", RED)
	_clear.add_theme_color_override(&"font_hover_color", RED_BRIGHT)
	_clear.add_theme_color_override(&"font_pressed_color", RED)
	_style_clear_button(_clear)
	_clear.pressed.connect(func() -> void:
		clear_requested.emit(index)
	)
	_clear.visible = false
	head.add_child(_clear)

	_mods = HBoxContainer.new()
	_mods.name = "CrawlerModRow_%d" % index
	_mods.add_theme_constant_override(&"separation", 3)
	_mods.mouse_filter = Control.MOUSE_FILTER_STOP
	_mods.custom_minimum_size.y = _mod_edge()
	stack.add_child(_mods)
	_apply_compact()


func _visible_mod_count(hosted: CrawlerCard) -> int:
	if hosted == null:
		return 0
	return maxi(hosted.slot_count, 1)


func _sync_mods(hosted: CrawlerCard) -> void:
	var slots := _visible_mod_count(hosted)
	if _mod_slots.size() != slots:
		_rebuild_mods(hosted)
		return
	var rack := kit.mod_rack(index) if kit != null and hosted != null else null
	for mod_index in slots:
		if rack != null and mod_index < rack.size():
			_mod_slots[mod_index].bind(rack, mod_index)
			_mod_slots[mod_index].interactive = true
			_mod_slots[mod_index].draggable = editable
		else:
			_mod_slots[mod_index].bind(null, mod_index)
			_mod_slots[mod_index].interactive = hosted != null
			_mod_slots[mod_index].draggable = editable and hosted != null
		_mod_slots[mod_index].queue_redraw()


func _rebuild_mods(hosted: CrawlerCard) -> void:
	for child: Node in _mods.get_children():
		_mods.remove_child(child)
		child.queue_free()
	_mod_slots.clear()
	if _mods == null:
		return
	var rack := kit.mod_rack(index) if kit != null and hosted != null else null
	for mod_index in _visible_mod_count(hosted):
		var slot := RedItemSlot.new()
		slot.name = "CrawlerMod_%d_%d" % [index, mod_index]
		slot.set_edge(_mod_edge())
		slot.placeholder = ""
		if rack != null and mod_index < rack.size():
			slot.bind(rack, mod_index)
			slot.interactive = true
			slot.draggable = editable
		else:
			slot.interactive = hosted != null
			slot.draggable = editable and hosted != null
		slot.picked.connect(func(picked_slot: RedItemSlot) -> void:
			mod_picked.emit(picked_slot)
		)
		slot.item_dropped.connect(func(target: RedItemSlot, source: RedItemSlot) -> void:
			mod_moved.emit(target, source)
		)
		slot.drag_released.connect(func(released: RedItemSlot, dropped: bool) -> void:
			if not dropped:
				mod_drop_requested.emit(released)
		)
		_mods.add_child(slot)
		_mod_slots.append(slot)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_LEFT:
		return
	picked.emit(self)


func _get_drag_data(_at: Vector2) -> Variant:
	if not editable:
		return null
	var id := token()
	if id.is_empty():
		return null
	_drag_live = true
	set_drag_preview(_preview())
	return {
		"crawler_move": true,
		"source": CrawlerKit.SOURCE_EQUIP,
		"index": index,
		"token": id,
	}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not editable:
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload := data as Dictionary
	if bool(payload.get("crawler_move", false)):
		var incoming := str(payload.get("token", ""))
		return ItemDB.is_ability(incoming) and incoming != token()
	var from := payload.get("red_item_slot") as RedItemSlot
	return from != null and ItemDB.is_ability(from.item_id())


func _drop_data(_at: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	card_received.emit(self, data as Dictionary)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hovered = true
			_apply_style()
		NOTIFICATION_MOUSE_EXIT:
			_hovered = false
			_apply_style()
		NOTIFICATION_DRAG_END:
			if _drag_live:
				var viewport := get_viewport()
				var dropped := viewport != null and viewport.gui_is_drag_successful()
				_drag_live = false
				if not dropped:
					drop_requested.emit(self)


func _preview() -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := PanelContainer.new()
	plate.position = Vector2(-48, -36)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK
	box.border_color = GREEN
	box.set_border_width_all(2)
	box.content_margin_left = 6
	box.content_margin_top = 6
	box.content_margin_right = 6
	box.content_margin_bottom = 6
	plate.add_theme_stylebox_override(&"panel", box)
	holder.add_child(plate)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 4)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(stack)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	var shot := TextureRect.new()
	shot.texture = _icon.texture
	shot.custom_minimum_size = Vector2(40, 40)
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shot.modulate = _icon_modulate(card().id if card() != null else "")
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(shot)
	var name_label := Label.new()
	name_label.text = _title.text
	name_label.add_theme_font_size_override(&"font_size", 12)
	name_label.add_theme_color_override(&"font_color", RED_TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(name_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(row)
	var hosted := card()
	if hosted != null:
		for mod_index in hosted.slot_count:
			var chip := ColorRect.new()
			chip.custom_minimum_size = Vector2(10, 10)
			chip.color = GREEN if hosted.mod_at(mod_index) != null \
				else Color(RED, 0.35)
			row.add_child(chip)
	return holder


func _icon_modulate(id: String) -> Color:
	if not CrawlerCatalog.icon_path(CrawlerCatalog.catalog_id(id)).is_empty():
		return Color.WHITE
	return Color(GREEN, 0.95)


func _mod_edge() -> float:
	return COMPACT_MOD_EDGE if compact else MOD_EDGE


func _icon_edge() -> float:
	return 32.0 if compact else 52.0


func _apply_compact() -> void:
	if _icon != null:
		_icon.custom_minimum_size = Vector2(_icon_edge(), _icon_edge())
	if _number != null:
		_number.add_theme_font_size_override(&"font_size", 16 if compact else 22)
		_number.custom_minimum_size.x = 16.0 if compact else 22.0
	if _title != null:
		_title.add_theme_font_size_override(&"font_size", 11 if compact else 14)
	if _mods != null:
		_mods.custom_minimum_size.y = _mod_edge()
	for slot: RedItemSlot in _mod_slots:
		slot.set_edge(_mod_edge())
	_apply_style()


func _apply_style() -> void:
	var fill := Color(0.0, 0.16, 0.045, 0.92) if selected or _hovered else BLACK
	var rim := GREEN if selected or _hovered else RED
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(rim, 0.98)
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	var pad := 5.0 if compact else 8.0
	box.content_margin_left = pad
	box.content_margin_top = pad
	box.content_margin_right = pad
	box.content_margin_bottom = pad
	add_theme_stylebox_override(&"panel", box)
	if _number != null:
		_number.add_theme_color_override(
			&"font_color", GREEN if selected else RED_BRIGHT
		)
	if _title != null:
		_title.add_theme_color_override(
			&"font_color", GREEN if selected else RED_TEXT
		)


func _style_clear_button(button: Button) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = GREEN
	box.border_color = Color(GREEN, 0.95)
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 2
	box.content_margin_top = 0
	box.content_margin_right = 2
	box.content_margin_bottom = 1
	button.add_theme_stylebox_override(&"normal", box)
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = GREEN.lightened(0.12)
	hover.border_color = RED_BRIGHT
	button.add_theme_stylebox_override(&"hover", hover)
	var pressed := box.duplicate() as StyleBoxFlat
	pressed.bg_color = GREEN.darkened(0.08)
	button.add_theme_stylebox_override(&"pressed", pressed)
