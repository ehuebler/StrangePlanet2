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
signal mod_drag_started(slot: RedItemSlot)
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
## Which kit bar this tile reads. City stash tiles use SOURCE_CITY_EQUIP.
var source := CrawlerKit.SOURCE_EQUIP
## Store stalls lock this so a click only selects. The Hero page leaves it
## on so cards can be dragged, seated, or dropped.
var editable := true:
	set(value):
		editable = value
		if _clear != null:
			refresh()
## Store tiles stay editable for drag, but hide the world-drop X.
var show_clear := true:
	set(value):
		show_clear = value
		if _clear != null:
			refresh()
## Locker page shows seated mods without letting them leave the card.
var mods_interactive := true:
	set(value):
		mods_interactive = value
		if _mods != null:
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
## Catalog id of a modifier the player is holding. Incompatible seated
## abilities draw an X over the row and its nested slots.
var blocked_mod := "":
	set(value):
		var clean := CrawlerCatalog.catalog_id(value)
		if blocked_mod == clean:
			return
		blocked_mod = clean
		_apply_block_mark()

var _number: Label
var _icon: TextureRect
var _title: Label
var _ammo: Label
var _clear: Button
var _mods: HBoxContainer
var _reject: Label
var _mod_slots: Array[RedItemSlot] = []
var _drag_live := false
var _hovered := false
var _rim: RedGlowPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	_apply_style()


func setup(at: int, owner_kit: CrawlerKit, from_source := "") -> void:
	index = at
	kit = owner_kit
	if not from_source.is_empty():
		source = from_source
	if _icon == null:
		_build()
	if _number != null:
		_number.text = str(index + 1)
	if _mods != null:
		_mods.name = "CrawlerModRow_%d" % index
	refresh()


func token() -> String:
	if kit == null:
		return ""
	return kit.token_at(source, index)


func card() -> CrawlerCard:
	if kit == null:
		return null
	return kit.card_for_token(token())


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
		if _ammo != null:
			_ammo.text = ""
			_ammo.visible = false
		if _clear != null:
			_clear.visible = false
		if _mods != null:
			_mods.visible = false
		_sync_mods(null)
		_apply_style()
		_apply_block_mark()
		return
	var id := hosted.id
	_icon.texture = CrawlerCatalog.texture_for(id)
	_icon.modulate = _icon_modulate(id)
	_title.text = ItemDB.title(id).to_upper()
	_refresh_ammo(hosted)
	if _clear != null:
		_clear.visible = editable and show_clear
	if _mods != null:
		_mods.visible = true
	_sync_mods(hosted)
	_apply_style()
	_apply_block_mark()


func rejects_held_mod() -> bool:
	return _reject != null and _reject.visible


func _build() -> void:
	var wrap := MarginContainer.new()
	wrap.name = "CrawlerAbilityBody"
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(wrap)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.add_child(body)

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

	_ammo = Label.new()
	_ammo.name = "CrawlerAbilityAmmo"
	_ammo.visible = false
	_ammo.add_theme_font_size_override(&"font_size", 14)
	_ammo.add_theme_color_override(&"font_color", GREEN)
	_ammo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_ammo)

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

	_reject = Label.new()
	_reject.name = "CrawlerFitReject"
	_reject.text = "X"
	_reject.visible = false
	_reject.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reject.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reject.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reject.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reject.add_theme_color_override(&"font_color", RED)
	_reject.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.86))
	_reject.add_theme_constant_override(&"outline_size", 8)
	wrap.add_child(_reject)
	_apply_compact()


func _mods_editable() -> bool:
	if not editable or not mods_interactive:
		return false
	return kit == null or kit.can_edit_mods()


func _visible_mod_count(hosted: CrawlerCard) -> int:
	if hosted == null:
		return 0
	return maxi(hosted.slot_count, 1)


func _sync_mods(hosted: CrawlerCard) -> void:
	var slots := _visible_mod_count(hosted)
	if _mod_slots.size() != slots:
		_rebuild_mods(hosted)
		return
	var rack := kit.mod_rack_for(source, index) if kit != null and hosted != null \
		else null
	var allow_mods := _mods_editable()
	if _mods != null:
		_mods.modulate = Color.WHITE if allow_mods else Color(1.0, 1.0, 1.0, 0.45)
	for mod_index in slots:
		if rack != null and mod_index < rack.size():
			_mod_slots[mod_index].bind(rack, mod_index)
			_mod_slots[mod_index].interactive = true
			_mod_slots[mod_index].draggable = allow_mods
			_mod_slots[mod_index].accepts_drops = allow_mods
		else:
			_mod_slots[mod_index].bind(null, mod_index)
			_mod_slots[mod_index].interactive = hosted != null
			_mod_slots[mod_index].draggable = allow_mods and hosted != null
			_mod_slots[mod_index].accepts_drops = allow_mods and hosted != null
		_mod_slots[mod_index].queue_redraw()


func _rebuild_mods(hosted: CrawlerCard) -> void:
	for child: Node in _mods.get_children():
		_mods.remove_child(child)
		child.queue_free()
	_mod_slots.clear()
	if _mods == null:
		return
	var rack := kit.mod_rack_for(source, index) if kit != null and hosted != null \
		else null
	var allow_mods := _mods_editable()
	if _mods != null:
		_mods.modulate = Color.WHITE if allow_mods else Color(1.0, 1.0, 1.0, 0.45)
	for mod_index in _visible_mod_count(hosted):
		var slot := RedItemSlot.new()
		slot.name = "CrawlerMod_%d_%d" % [index, mod_index]
		slot.set_edge(_mod_edge())
		slot.placeholder = ""
		slot.use_soft_fx()
		if rack != null and mod_index < rack.size():
			slot.bind(rack, mod_index)
			slot.interactive = true
			slot.draggable = allow_mods
			slot.accepts_drops = allow_mods
		else:
			slot.interactive = hosted != null
			slot.draggable = allow_mods and hosted != null
			slot.accepts_drops = allow_mods and hosted != null
		slot.picked.connect(func(picked_slot: RedItemSlot) -> void:
			mod_picked.emit(picked_slot)
		)
		slot.item_dropped.connect(func(target: RedItemSlot, source: RedItemSlot) -> void:
			mod_moved.emit(target, source)
		)
		slot.drag_started.connect(func(started: RedItemSlot) -> void:
			mod_drag_started.emit(started)
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
		"source": source,
		"index": index,
		"token": id,
		"kit": kit,
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


func _refresh_ammo(hosted: CrawlerCard) -> void:
	if _ammo == null:
		return
	var kit_ammo := kit.ammo_count_text(hosted) if kit != null else ""
	_ammo.text = kit_ammo
	_ammo.visible = not kit_ammo.is_empty()
	if kit_ammo == "0":
		_ammo.add_theme_color_override(&"font_color", RED_BRIGHT)
	else:
		_ammo.add_theme_color_override(&"font_color", GREEN)


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
	if _ammo != null:
		_ammo.add_theme_font_size_override(&"font_size", 11 if compact else 14)
	if _mods != null:
		_mods.custom_minimum_size.y = _mod_edge()
	if _reject != null:
		_reject.add_theme_font_size_override(&"font_size", 28 if compact else 44)
	for slot: RedItemSlot in _mod_slots:
		slot.set_edge(_mod_edge())
	_apply_style()
	_apply_block_mark()


func _should_reject() -> bool:
	if blocked_mod.is_empty() or not CrawlerCatalog.is_modifier(blocked_mod):
		return false
	var hosted := card()
	if hosted == null:
		return false
	return not CrawlerCatalog.compatible(blocked_mod, hosted.id)


func _apply_block_mark() -> void:
	var reject := _should_reject()
	if _reject != null:
		_reject.visible = reject
	for slot: RedItemSlot in _mod_slots:
		slot.blocked = reject
	_apply_style()


func _ensure_rim() -> void:
	if _rim != null:
		return
	_rim = RedGlowPanel.add_to(self)
	_rim.fill_color = Color.TRANSPARENT
	_rim.border_width = 2.0
	_rim.glow_intensity = 1.15
	_rim.glow_spread = 6.0
	_rim.glow_layers = 4


func _apply_style() -> void:
	var reject := _should_reject()
	var fill := Color(0.0, 0.16, 0.045, 0.92) if selected or _hovered else BLACK
	var rim := GREEN if selected or _hovered else RED
	if reject:
		fill = Color(0.16, 0.02, 0.03, 0.92)
		rim = RED
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_corner_radius_all(0)
	var pad := 5.0 if compact else 8.0
	box.content_margin_left = pad
	box.content_margin_top = pad
	box.content_margin_right = pad
	box.content_margin_bottom = pad
	add_theme_stylebox_override(&"panel", box)
	_ensure_rim()
	_rim.border_color = Color(rim, 0.98)
	_rim.glow_intensity = 1.35 if selected or _hovered else 1.15
	if _number != null:
		_number.add_theme_color_override(
			&"font_color", GREEN if selected else RED_BRIGHT
		)
	if _title != null:
		_title.add_theme_color_override(
			&"font_color", GREEN if selected else RED_TEXT
		)
	if _ammo != null and _ammo.text != "0":
		_ammo.add_theme_color_override(
			&"font_color", GREEN if selected else GREEN
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
