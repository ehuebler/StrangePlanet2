class_name RedItemSlot
extends Control

## A sharp inventory tile for [GameMenu].
##
## The old [ItemSlot] remains the right tile for the home editor and HUD. This
## one belongs to the red menu: black glass, square red glow, green icon, and a
## compact key badge. It keeps the same container contract and quick-move signal
## so moving an item is still an [ItemContainer] operation rather than UI state.

signal picked(slot: RedItemSlot)
signal quick_move_requested(slot: RedItemSlot)
signal hover_started(slot: RedItemSlot)
signal hover_ended(slot: RedItemSlot)
signal item_dropped(target: RedItemSlot, source: RedItemSlot)
signal crawler_move_dropped(target: RedItemSlot, data: Dictionary)
signal drag_started(slot: RedItemSlot)
signal drag_released(slot: RedItemSlot, dropped: bool)

const EDGE := 70.0
const RED := Color("ef151f")
const GREEN := Color("45df68")
const YELLOW := Color("ffd84a")
const BLACK := Color(0.0, 0.0, 0.0, 0.76)

var container: ItemContainer
var index := 0
## Portrait / HUD override so a tile can show without a loadout container.
var forced_item_id := "":
	set(value):
		if forced_item_id == value:
			return
		forced_item_id = value
		queue_redraw()
var interactive := true
var draggable := true
var accepts_drops := true
## When true, a drop copies the id onto the target instead of swapping
## containers. Ability library tiles use this so a known power is not consumed.
var copy_on_drag := false
var selected := false
## Hero-page fit hint: a held modifier cannot seat on this tile.
var blocked := false:
	set(value):
		if blocked == value:
			return
		blocked = value
		queue_redraw()
var equipped := false:
	set(value):
		equipped = value
		queue_redraw()
var placeholder := "X"
var badge := ""

var _hovered := false
var _drop_target := false
var _drag_live := false
var _fallback_glyph: RedMenuGlyph
var _icon_rect: TextureRect
var _badge_label: Label
var _rim: RedGlowPanel


func _init() -> void:
	custom_minimum_size = Vector2.ONE * EDGE
	size = custom_minimum_size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Mesh icons take at least one rendered frame. Keep a readable vector icon in
	# the tile until that texture arrives instead of showing a dark tint block
	# (which made Settler Hair look empty on its first appearance).
	_fallback_glyph = RedMenuGlyph.new()
	_fallback_glyph.name = "ItemFallbackGlyph"
	_fallback_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_glyph.offset_left = 13.0
	_fallback_glyph.offset_top = 13.0
	_fallback_glyph.offset_right = -13.0
	_fallback_glyph.offset_bottom = -13.0
	_fallback_glyph.visible = false
	add_child(_fallback_glyph)
	_icon_rect = TextureRect.new()
	_icon_rect.name = "ItemIcon"
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.visible = false
	add_child(_icon_rect)
	_badge_label = Label.new()
	_badge_label.name = "ItemBadge"
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_label.add_theme_font_size_override(&"font_size", 11)
	_badge_label.visible = false
	add_child(_badge_label)
	_ensure_rim()


func set_edge(edge: float) -> void:
	custom_minimum_size = Vector2.ONE * edge
	size = custom_minimum_size
	if _fallback_glyph != null:
		var pad := clampf(edge * 0.10, 2.0, 13.0)
		_fallback_glyph.offset_left = pad
		_fallback_glyph.offset_top = pad
		_fallback_glyph.offset_right = -pad
		_fallback_glyph.offset_bottom = -pad
	queue_redraw()


func use_soft_fx() -> void:
	set_meta(&"crt_soft_glitch", true)
	if _icon_rect != null:
		CrtType.mark_soft_icon(_icon_rect)
	if _fallback_glyph != null:
		CrtType.mark_soft_icon(_fallback_glyph)


func bind(to_container: ItemContainer, at_index: int) -> void:
	container = to_container
	index = at_index
	queue_redraw()


func item_id() -> String:
	if not forced_item_id.is_empty():
		return forced_item_id
	return container.get_item(index) if container != null else ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_hovered = true
			hover_started.emit(self)
			queue_redraw()
		NOTIFICATION_MOUSE_EXIT:
			_hovered = false
			_drop_target = false
			hover_ended.emit(self)
			queue_redraw()
		NOTIFICATION_DRAG_END:
			_drop_target = false
			if _drag_live:
				var viewport := get_viewport()
				drag_released.emit(
					self,
					viewport != null and viewport.gui_is_drag_successful()
				)
				_drag_live = false
			queue_redraw()
		NOTIFICATION_RESIZED:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed \
			or button.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if button.shift_pressed and not item_id().is_empty():
		quick_move_requested.emit(self)
		return
	picked.emit(self)


func _get_drag_data(_at: Vector2) -> Variant:
	if not interactive or not draggable or item_id().is_empty():
		return null
	_drag_live = true
	set_drag_preview(_drag_preview())
	drag_started.emit(self)
	return {"red_item_slot": self}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not accepts_drops:
		if _drop_target:
			_drop_target = false
			queue_redraw()
		return false
	if _is_crawler_move(data):
		var token := str((data as Dictionary).get("token", ""))
		var legal := container != null and container.accepts(index, token)
		var occupant := item_id()
		if legal and not occupant.is_empty() and not ItemDB.is_ability(occupant):
			legal = false
		if legal != _drop_target:
			_drop_target = legal
			queue_redraw()
		return legal
	var from := _source_slot(data)
	if from == null or container == null:
		return false
	var legal := container.accepts(index, from.item_id())
	if not from.copy_on_drag:
		legal = legal and from.container.accepts(from.index, item_id())
	if legal != _drop_target:
		_drop_target = legal
		queue_redraw()
	return legal


func _drop_data(_at: Vector2, data: Variant) -> void:
	if not accepts_drops:
		return
	if _is_crawler_move(data):
		_drop_target = false
		crawler_move_dropped.emit(self, data as Dictionary)
		return
	var from := _source_slot(data)
	if from == null:
		return
	_drop_target = false
	if from.copy_on_drag:
		item_dropped.emit(self, from)
		if container != null:
			container.set_item(index, from.item_id())
		return
	ItemContainer.transfer(from.container, from.index, container, index)
	item_dropped.emit(self, from)


func _is_crawler_move(data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY \
		and bool((data as Dictionary).get("crawler_move", false))


func _source_slot(data: Variant) -> RedItemSlot:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var from := (data as Dictionary).get("red_item_slot") as RedItemSlot
	return from if from != null and from != self and from.container != null else null


func _drag_preview() -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var preview := TextureRect.new()
	preview.texture = CrawlerCatalog.texture_for(item_id())
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.position = -size * 0.42
	preview.size = size * 0.84
	preview.modulate = _icon_modulate(item_id())
	holder.add_child(preview)
	return holder


func _draw() -> void:
	_sync_rim()
	var edge := minf(size.x, size.y)
	var frame := clampf(edge * 0.06, 1.5, 3.0)
	var outer := Rect2(Vector2.ZERO, size).grow(-frame)
	var id := item_id()
	if id.is_empty():
		_sync_fallback("", false)
		_sync_icon("", null)
		_draw_placeholder()
	else:
		var icon := CrawlerCatalog.texture_for(id)
		var has_icon := icon != null
		_sync_fallback(id, not has_icon)
		_sync_icon(id, icon)
		if not has_icon:
			draw_rect(outer.grow(-_icon_inset() - 2.0), Color(ItemDB.tint(id), 0.22))
	_sync_badge()
	if blocked:
		_draw_block_x()


func _ensure_rim() -> void:
	if _rim != null:
		return
	_rim = RedGlowPanel.add_to(self)
	_rim.fill_color = BLACK
	_rim.border_color = Color(RED, 0.98)
	_rim.border_width = 2.0
	_rim.glow_intensity = 1.05
	_rim.glow_spread = 3.0
	_rim.glow_layers = 3


func _sync_rim() -> void:
	_ensure_rim()
	var edge := minf(size.x, size.y)
	var bloom := clampf(edge * 0.08, 1.5, 3.0)
	var fill := BLACK
	if equipped:
		fill = Color(0.16, 0.12, 0.01, 0.92)
	if selected and not equipped:
		fill = Color(0.02, 0.17, 0.06, 0.9)
	var rim := (
		GREEN if _drop_target
		else YELLOW if equipped
		else GREEN if selected
		else RED
	)
	var rim_w := 2.0 if edge < 40.0 else 3.0
	if not (_hovered or _drop_target or selected or equipped):
		rim_w = maxf(rim_w - 1.0, 1.0)
	_rim.fill_color = fill
	_rim.border_color = Color(rim, 0.98)
	_rim.border_width = rim_w
	_rim.glow_spread = bloom
	_rim.glow_intensity = 1.2 if (_hovered or _drop_target or selected or equipped) \
		else 1.0


func _icon_modulate(id: String) -> Color:
	# Catalogue SVGs already carry their own ink. Multiplying them by the
	# menu green turns the dark plates into empty-looking squares, which is
	# what the city-store bag tiles were showing for wobble and big.
	if not CrawlerCatalog.icon_path(CrawlerCatalog.catalog_id(id)).is_empty():
		return Color.WHITE
	return Color(YELLOW if equipped else GREEN, 0.95)


func _icon_inset() -> float:
	var edge := minf(size.x, size.y)
	# Large library tiles keep a generous gutter. Ability-mod squares are
	# ~28px; a 7px pad on each side left an 8px icon in a 28px box.
	if edge >= 56.0:
		return 7.0
	return clampf(edge * 0.04, 1.0, 2.5)


func _sync_fallback(id: String, show: bool) -> void:
	if _fallback_glyph == null:
		return
	_fallback_glyph.visible = show
	if not show:
		return
	var glyph := _fallback_for(id)
	if _fallback_glyph.glyph != glyph:
		_fallback_glyph.glyph = glyph
	var ink := YELLOW if equipped else GREEN
	if _fallback_glyph.green_color != ink:
		_fallback_glyph.green_color = ink


func _fallback_for(id: String) -> RedMenuGlyph.Glyph:
	if ItemDB.is_weapon(id):
		return RedMenuGlyph.Glyph.WEAPONS
	if ItemDB.is_item(id):
		return RedMenuGlyph.Glyph.ITEMS
	if ItemDB.is_ability(id):
		return RedMenuGlyph.Glyph.ABILITIES
	match ItemDB.slot_of(id):
		"hat":
			return RedMenuGlyph.Glyph.HAT
		"goggles":
			return RedMenuGlyph.Glyph.GOGGLES
		"long_sleeve":
			return RedMenuGlyph.Glyph.BODY_TUNIC
		"pants":
			return RedMenuGlyph.Glyph.PANTS
		"shoes":
			return RedMenuGlyph.Glyph.BOOTS
	return RedMenuGlyph.Glyph.ITEMS


func _draw_placeholder() -> void:
	if placeholder.is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := clampi(roundi(size.y * 0.34), 14, 28)
	var baseline := (size.y + font_size) * 0.5 - 2.0
	draw_string(font, Vector2(0.0, baseline), placeholder,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, GREEN)


func _draw_block_x() -> void:
	var pad := minf(size.x, size.y) * 0.16
	var a := Vector2(pad, pad)
	var b := Vector2(size.x - pad, size.y - pad)
	var c := Vector2(size.x - pad, pad)
	var d := Vector2(pad, size.y - pad)
	var width := clampf(minf(size.x, size.y) * 0.14, 2.0, 4.5)
	draw_line(a, b, Color(RED, 0.96), width, true)
	draw_line(c, d, Color(RED, 0.96), width, true)


func _sync_icon(id: String, icon: Texture2D) -> void:
	if _icon_rect == null:
		return
	var has := icon != null and not id.is_empty()
	_icon_rect.texture = icon if has else null
	_icon_rect.visible = has
	if has:
		_icon_rect.modulate = _icon_modulate(id)
	var inset := _icon_inset() + clampf(minf(size.x, size.y) * 0.06, 1.5, 3.0)
	var target: Control = CrtType.host_of(_icon_rect)
	if target == null:
		target = _icon_rect
	target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.offset_left = inset
	target.offset_top = inset
	target.offset_right = -inset
	target.offset_bottom = -inset


func _sync_badge() -> void:
	if _badge_label == null:
		return
	_badge_label.text = badge
	_badge_label.visible = not badge.is_empty()
	_badge_label.add_theme_color_override(
		&"font_color", YELLOW if equipped else RED)
	var target: Control = CrtType.host_of(_badge_label)
	if target == null:
		target = _badge_label
	target.position = Vector2(7.0, 2.0)
	target.size = Vector2(maxf(size.x - 10.0, 8.0), 16.0)
