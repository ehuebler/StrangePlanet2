class_name ItemSlot
extends Control

## One tile of an inventory grid: a drawn square holding whatever item sits at
## `index` of `container`.
##
## The tile owns its own rules rather than reporting clicks upwards. Dragging asks
## both containers whether the swap is legal, dropping performs it, and the
## containers then tell the screen to redraw. Shift-clicking is the exception,
## because where an item should jump to depends on which grids are on screen, so
## that is passed out as a signal.

## A plain left click. What that means is the screen's business, not the tile's:
## the character pages use it to choose what the colour chips paint.
signal picked(slot: ItemSlot)
signal quick_move_requested(slot: ItemSlot)
signal hover_started(slot: ItemSlot)
signal hover_ended(slot: ItemSlot)

const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")

const SIZE := 52.0
## Corner of the drawn tile, and the segments each one is drawn with.
const CORNER := 7.0
const CORNER_STEPS := 4
const ICON_INSET := 4.0
## How far inside the rim the second ring of a selected tile sits. It is what
## makes "worn" read as a box around the item rather than as a slightly brighter
## edge, which at 1.6 px against a dark tile is not a difference anyone sees.
const RING_INSET := 3.5

var container: ItemContainer
var index := 0
## HUD-only override so a cape tile can show without a loadout container.
var forced_item_id := "":
	set(value):
		if forced_item_id == value:
			return
		forced_item_id = value
		queue_redraw()
## HUD tiles are drawn but take no input: the weapon bar reports what is in hand
## rather than being rummaged in.
var interactive := true
## Off for a tile that is a **view** of an item rather than a place one is kept —
## the character editor's catalogue is the case. Dragging one of those would swap
## containers and put a worn garment into a list that is meant to hold every
## garment; clicking and hovering still work, which is all a catalogue needs.
var draggable := true
## Shown when the slot is empty, naming the body part an equipment slot covers.
var placeholder := ""
## Drawn small in the top corner: the key that reaches this slot.
var badge := ""
## Marks the weapon bar's current slot, which is drawn heavier and in accent ink.
var selected := false
## HUD ability slots refill from bottom to top while cooling down. One is ready;
## zero is the instant the cooldown begins. Inventory tiles never set this.
var cooldown_fill := 1.0
var cooldown_active := false
## Remaining shots for a limited-use ability. Empty hides the count.
var count_text := "":
	set(value):
		if count_text == value:
			return
		count_text = value
		queue_redraw()
## Gameplay hotbar only: square black tile, red rim, and a black-on-accent key
## badge. Inventory and editor tiles keep their existing tactile presentation.
var hud_style := false:
	set(value):
		hud_style = value
		_outline.clear()
		queue_redraw()

var _hovered := false
var _drop_target := false
## The rounded outline, rebuilt only when the tile is resized.
var _outline := PackedVector2Array()


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size


## A tile off the standard [constant SIZE], which the character editor's
## catalogue is. Everything drawn here is measured off `size`, so the icon, the
## border's wander and the badge all follow.
func set_edge(edge: float) -> void:
	custom_minimum_size = Vector2(edge, edge)
	size = custom_minimum_size


func bind(to_container: ItemContainer, at_index: int) -> void:
	container = to_container
	index = at_index
	queue_redraw()


func set_cooldown(fill: float, active: bool) -> void:
	fill = clampf(fill, 0.0, 1.0)
	if cooldown_active == active and is_equal_approx(cooldown_fill, fill):
		return
	cooldown_fill = fill
	cooldown_active = active
	queue_redraw()


func item_id() -> String:
	if not forced_item_id.is_empty():
		return forced_item_id
	if container == null:
		return ""
	return container.get_item(index)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			_outline.clear()
			queue_redraw()
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
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.shift_pressed and not item_id().is_empty():
		accept_event()
		quick_move_requested.emit(self)
		return
	# Not accepted, because a press is also where a drag begins and swallowing it
	# would leave the tiles unable to be moved. Selecting the tile a drag starts
	# from is harmless: it is the one the player is pointing at either way.
	picked.emit(self)


func _get_drag_data(_at: Vector2) -> Variant:
	if not interactive or not draggable or item_id().is_empty():
		return null
	set_drag_preview(_drag_preview())
	return {"slot": self}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	var from := _source_slot(data)
	if from == null or container == null:
		return false
	# A drop swaps, so the item coming back has to be legal where it lands too.
	var legal := container.accepts(index, from.item_id()) \
		and from.container.accepts(from.index, item_id())
	if legal != _drop_target:
		_drop_target = legal
		queue_redraw()
	return legal


func _drop_data(_at: Vector2, data: Variant) -> void:
	var from := _source_slot(data)
	if from == null:
		return
	_drop_target = false
	ItemContainer.transfer(from.container, from.index, container, index)


func _source_slot(data: Variant) -> ItemSlot:
	if not interactive or not draggable or typeof(data) != TYPE_DICTIONARY:
		return null
	var from := (data as Dictionary).get("slot") as ItemSlot
	if from == null or from == self or from.container == null:
		return null
	return from


func _drag_preview() -> Control:
	# Wrapped in a spacer, because a preview is pinned by its top-left corner and
	# should hang off the cursor's middle.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = ItemIcons.cached(item_id())
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = size
	icon.position = -size * 0.5
	icon.modulate = Color(1.0, 1.0, 1.0, 0.85)
	if icon.texture == null:
		icon.modulate = ItemDB.tint(item_id())
	holder.add_child(icon)
	return holder


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var id := item_id()
	var corner := 0.0 if hud_style else CORNER
	if _outline.is_empty():
		_outline = _rounded(rect.grow(-1.0), corner)
	draw_colored_polygon(_outline, _fill_color())
	if hud_style and cooldown_active and not id.is_empty():
		var fill_height := (size.y - 2.0) * cooldown_fill
		if fill_height > 0.0:
			draw_rect(Rect2(
				Vector2(1.0, size.y - 1.0 - fill_height),
				Vector2(size.x - 2.0, fill_height)
			), Color(ItemDB.tint(id), 0.22))
	# A tile is a well cut into the pane, so its rim has to read against the pane
	# rather than against the tile.
	var ink: Color = (
		RedHudTheme.GREEN if selected else RedHudTheme.RED
	) if hud_style else (
		PALETTE.accent if (_drop_target or selected) else PALETTE.text_muted
	)
	var weight := 2.4 if (_drop_target or _hovered or selected) else 1.4
	draw_polyline(_outline, Color(ink, 0.9), weight, true)
	if selected or _drop_target:
		# The box that says this item is on the body. Two rings rather than one
		# heavier ring: a grid of tiles is read at a glance and a doubled edge is
		# the only weight difference that survives being 44 px across.
		draw_polyline(
			_rounded(rect.grow(-RING_INSET), maxf(corner - 2.0, 0.0)),
			Color(RedHudTheme.GREEN if hud_style else PALETTE.accent, 0.62),
			1.6,
			true
		)

	if id.is_empty():
		_draw_placeholder()
		_draw_badge()
		_draw_count()
		return
	var icon := ItemIcons.cached(id)
	var inner := rect.grow(-ICON_INSET)
	if icon != null:
		_draw_icon(icon, inner, id)
	else:
		# Until the icon has been rendered, the item still reads as something
		# rather than as an empty slot.
		_draw_fallback(inner.grow(-4.0), id)
	_draw_badge()
	_draw_count()


func _draw_icon(icon: Texture2D, inner: Rect2, id: String) -> void:
	if not hud_style or not cooldown_active:
		draw_texture_rect(icon, inner, false)
		return
	# Keep the whole symbol barely visible as context, then reveal its full
	# colour from the bottom up along with the box behind it.
	draw_texture_rect(icon, inner, false, Color(0.26, 0.26, 0.26, 0.72))
	var fill := clampf(cooldown_fill, 0.0, 1.0)
	var texture_size := icon.get_size()
	if fill > 0.0 and texture_size.x > 0.0 and texture_size.y > 0.0:
		var reveal_height := inner.size.y * fill
		var destination := Rect2(
			Vector2(inner.position.x, inner.end.y - reveal_height),
			Vector2(inner.size.x, reveal_height)
		)
		var source := Rect2(
			Vector2(0.0, texture_size.y * (1.0 - fill)),
			Vector2(texture_size.x, texture_size.y * fill)
		)
		draw_texture_rect_region(
			icon, destination, source, Color.WHITE, false, true)
	_draw_cooldown_edge(inner, id, fill)


func _draw_fallback(inner: Rect2, id: String) -> void:
	var tint := ItemDB.tint(id)
	if not hud_style or not cooldown_active:
		draw_rect(inner, tint)
		return
	draw_rect(inner, Color(tint.darkened(0.7), 0.72))
	var fill := clampf(cooldown_fill, 0.0, 1.0)
	var reveal_height := inner.size.y * fill
	if reveal_height > 0.0:
		draw_rect(Rect2(
			Vector2(inner.position.x, inner.end.y - reveal_height),
			Vector2(inner.size.x, reveal_height)
		), tint)
	_draw_cooldown_edge(inner, id, fill)


func _draw_cooldown_edge(inner: Rect2, id: String, fill: float) -> void:
	if fill <= 0.01 or fill >= 0.99:
		return
	var y := inner.end.y - inner.size.y * fill
	draw_line(
		Vector2(inner.position.x, y),
		Vector2(inner.end.x, y),
		Color(ItemDB.tint(id).lightened(0.28), 0.92),
		1.8,
		true
	)


func _fill_color() -> Color:
	if hud_style:
		return Color(RedHudTheme.BLACK, 0.88)
	if not interactive:
		# These sit over the world rather than over a card, so they keep enough
		# of the plate to be read against grass, sky or a lit prop. Any thinner
		# and the slot numbers dissolve into whatever is behind them, which is
		# the same reason the HUD's text plates are opaque.
		return Color(PALETTE.paper_card, 0.94) if selected else Color(PALETTE.paper, 0.86)
	# A tile lightens as it is reached for, the opposite way round from the light
	# scheme this replaced but the same signal: the one under the cursor is the
	# one furthest from the card behind it.
	if _drop_target or _hovered:
		return PALETTE.paper_card
	return PALETTE.paper_shade


## Sits over the tile's own corner rather than beside it, so a row of tiles keeps
## its spacing whether the numbers are there or not.
func _draw_badge() -> void:
	if badge.is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	if hud_style:
		var font_size := 10
		var text_size := font.get_string_size(
			badge, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		)
		var badge_rect := Rect2(
			Vector2(3.0, 3.0),
			Vector2(maxf(text_size.x + 7.0, 17.0), 15.0)
		)
		var badge_fill := RedHudTheme.GREEN if selected else RedHudTheme.RED
		draw_rect(badge_rect, badge_fill, true)
		draw_rect(badge_rect, RedHudTheme.BLACK, false, 1.0)
		draw_string(
			font,
			Vector2(6.0, 14.0),
			badge,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			RedHudTheme.INK
		)
		return
	# Full-strength rather than muted: the number is the one thing on a HUD tile
	# that has to be read at a glance, and it is the smallest type in the game.
	var color: Color = PALETTE.accent if selected else PALETTE.text_primary
	draw_string(font, Vector2(5.0, 15.0), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func _draw_count() -> void:
	if count_text.is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 12 if hud_style else 11
	var text_size := font.get_string_size(
		count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	)
	var pad := 5.0 if hud_style else 4.0
	var box := Rect2(
		Vector2(size.x - text_size.x - pad - 4.0, size.y - 17.0),
		Vector2(text_size.x + 6.0, 14.0)
	)
	var empty := count_text == "0"
	if hud_style:
		var fill := Color(RedHudTheme.BLACK, 0.82)
		var ink := RedHudTheme.RED if empty else RedHudTheme.GREEN
		draw_rect(box, fill, true)
		draw_rect(box, Color(ink, 0.9), false, 1.0)
		draw_string(
			font,
			Vector2(box.position.x + 3.0, box.position.y + 12.0),
			count_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			ink
		)
		return
	draw_string(
		font,
		Vector2(box.position.x + 2.0, size.y - 5.0),
		count_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		PALETTE.text_primary
	)


func _draw_placeholder() -> void:
	if placeholder.is_empty():
		return
	var font := get_theme_default_font()
	if font == null:
		return
	var font_size := 12
	var baseline := (size.y + float(font_size)) * 0.5 - 1.0
	draw_string(font, Vector2(0.0, baseline), placeholder, HORIZONTAL_ALIGNMENT_CENTER,
		size.x, font_size, (
			RedHudTheme.INK if hud_style else Color(PALETTE.text_muted, 0.85)
		))


## A closed rounded rectangle, corners first. Returned as a path rather than
## drawn, because the fill and the rim are the same shape and a tile whose fill
## and outline disagree about its corners shows a bright pip at each one.
func _rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var limit := clampf(radius, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var centres := [
		rect.position + Vector2(limit, limit),
		rect.position + Vector2(rect.size.x - limit, limit),
		rect.end - Vector2(limit, limit),
		rect.position + Vector2(limit, rect.size.y - limit),
	]
	var path := PackedVector2Array()
	for corner in 4:
		# Anticlockwise from the top-left corner's own quarter turn.
		var from := PI + float(corner) * TAU * 0.25
		for step in CORNER_STEPS + 1:
			var angle := from + TAU * 0.25 * float(step) / float(CORNER_STEPS)
			path.append(centres[corner] + Vector2(cos(angle), sin(angle)) * limit)
	path.append(path[0])
	return path
