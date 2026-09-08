class_name InventoryPage
extends Control

## Who you are and what you are carrying: your name, a live model you can spin,
## what you are wearing, your stats, your weapon bar, a colour wheel to recolour
## any of it, and your pockets.
##
## This is the Hero Design and Inventory tabs of [GameMenu] **and** both tabs of
## the home screen's character editor, and that is deliberate rather than
## convenient. Dressing a character is dressing a character; a second screen for
## doing it before the game starts would be a second place for the tiles, the
## filters and the quick-move rules to drift out of step. Two switches cover the
## differences:
##
## - [member section] picks which half is built. Both callers build both halves
##   and put a tab over them, against **one** set of containers: an item moving
##   on either tab redraws the tiles on the other with no wiring, which is what
##   two instances buys over two classes.
## - [member show_preview] is off wherever there is already a model of this
##   character on screen — which on the home screen there is, standing at the
##   spawn behind the card.
##
## - [member catalogue] says the pockets are a list of what this character owns
##   rather than a bag of what it happens to be carrying. See there.
##
## `editing` is the fourth and it is much smaller than it was: it makes the name
## typeable and stocks the pockets from the body's wardrobe rather than from a
## backpack.
##
## The page holds no item state. Every tile points at a slot of an [ItemContainer],
## and moving an item is a change to a container, which reports back and has the
## tiles and the model redrawn. Equipping is not special-cased: dropping a hat in
## the head slot is an ordinary move, and the player is the one listening to its
## equipment container.

## A garment or the skin was recoloured. Raised rather than acted on: in game the
## player owns the body being painted, and on the home screen the look being saved.
signal tint_picked(target: String, colour: Color)
## The authored texture/colour should show without a multiplying tint. Separate
## from picking white: sparse tint data is the promise that "no tint" really
## means no override, and lets a later authored colour change come through.
signal tint_cleared(target: String)
## One of the texture schemes offered by this body was chosen. Only the
## home-screen editor exposes the picker; the in-game page still needs the id so
## its preview draws the same character.
signal skin_picked(skin_id: String)
## The name field was committed to. Same reasoning — the name belongs to whoever
## opened the page.
signal name_entered(value: String)

## Which half of the page to build. HERO is who you are — the figure, what it is
## wearing, its stats, its weapons and the colour wheel; POCKETS is what you are
## carrying, over the filters that narrow it.
enum Section { HERO, POCKETS }

const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")
const GAP := 6
## Between the stacked rows — the name, the figure, the pockets, the colour strip.
## There are four of these down the page and each is height the strip is trying to
## stay above, which is why they are the slot gap plus two and not a round ten.
const ROW_GAP := 8
## Columns of the pockets grid — wide and shallow rather than square, and this is
## the value the whole page is sized around. The card has width going spare and none
## of its height, because the figure, the equipment column and the colour strip
## between them spend all of it, so every row saved here is what keeps the strip
## above the fold. Times its rows this has to come to the backpack's size, or the
## last row comes out ragged.
const COLUMNS := 18
## The catalogue's tiles are the other shape entirely: a character owns a few
## dozen things at the outside, so each one is large enough to tell one pair of
## goggles from another. How many fit across is worked out from the width the grid
## is actually given rather than fixed, because the same grid is shown in a card
## half the window wide on the home screen and one nearly the whole window wide in
## game — a count that suits either one wastes most of the other.
const CATALOGUE_TILE := 84.0
const CATALOGUE_MIN_COLUMNS := 4
## Equipment tiles on a page with no figure on it. See [method _worn_column].
const WORN_TILE := 74.0
## Height is the axis that runs out on this page: the figure, the pockets and the
## colour strip all want it and the card has to fit inside the window. Every value
## here that looks mean is paying for the strip staying above the fold.
const PREVIEW_SIZE := Vector2(176.0, 236.0)
## The preview is rendered several times larger than it is shown and scaled back
## down. The outline pass measures its strokes in pixels, so drawing straight into
## a panel this size would ring the model in strokes as thick as its limbs.
const PREVIEW_SUPERSAMPLE := 3
const SPIN_PER_PIXEL := 0.01
const TOOLTIP_OFFSET := Vector2(18.0, 12.0)
const TOOLTIP_WIDTH := 330.0
## The tint key for the body rather than for a garment, as [CharacterDB], the
## player and the spawn metadata all spell it. It is described as the skin,
## because "Body" is already the equipment column's label for the torso.
const TINT_BODY := "body"
## Width of the colour block. See [method _colour_block] for why it is not the
## wheel's own.
const TINT_BLOCK_WIDTH := 212.0

## What the pockets can be narrowed to, and the buttons in the order they sit in.
## A category is worked out from an item's slot rather than stored on it, so
## nothing has to be tagged: [constant ItemDB.WEAPON] is a weapon, any other slot
## is clothing, and something worn nowhere is an item. That last row is what a
## future consumable or crafting material lands in with no edit here.
const CATEGORIES := {
	"clothing": "Clothing",
	"weapons": "Weapons",
	"items": "Items",
}

## Set before the page enters the tree, alongside [method configure]. Public
## rather than two more arguments on a call that already takes six.
var section := Section.HERO
## Whether to render a model of this character into the page. Off wherever the
## caller already has one on screen; the page then costs no SubViewport at all.
var show_preview := true
## Whether the pockets are a **catalogue** rather than storage: everything this
## character owns, listed whether it is on the body or not, with what is worn
## marked and a click to put it on or take it off.
##
## That is the character editor, and it is a different thing from a backpack even
## though it is drawn the same way. A backpack is where an item *is*, so wearing
## something takes it out of there; a catalogue is a list of what exists, so
## wearing something changes how the row is drawn and nothing else. Off, and the
## grid is ordinary storage that items are dragged out of.
var catalogue := false

var _equipment: ItemContainer
var _weapons: ItemContainer
var _pockets: ItemContainer
var _stats: PlayerStats
var _body_id := CharacterDB.DEFAULT_BODY
var _skin_id := ""
var _player_name := "Player"
var _editing := false

var _slots: Array[ItemSlot] = []
var _icons: ItemIcons
var _tooltip: PanelContainer
var _tooltip_title: Label
var _tooltip_body: Label
var _hovered: ItemSlot

var _preview_character: Node3D
var _preview_holder: TextureRect
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_pivot: Node3D
var _spin := 0.0
var _dragging := false
## Body slot to item id, so the model is only rebuilt where it changed.
var _preview_worn: Dictionary = {}

## Everything laid out, as against the tooltip and the icon driver, which are also
## children of the page but are not part of its layout.
var _column: VBoxContainer
var _stat_rows: VBoxContainer
var _tint_target := TINT_BODY
var _tints: Dictionary = {}
var _tint_caption: Label
var _wheel: ColourWheel
var _clear_tint: Button
var _skin_row: HBoxContainer

## Empty means everything. Two filters rather than one because they narrow along
## different axes and are worth combining: a category is what kind of thing it
## is, a body slot is where it goes.
var _category := ""
var _slot_filter := ""
var _category_row: HBoxContainer
var _slot_row: HBoxContainer
var _grid: GridContainer


## Called before the page enters the tree: it is built against these. `stats` may
## be null, which is what the character editor passes — there is nobody to have
## stats yet. `editing` makes the name typeable and turns the pockets into the rail
## of garments that fit this body.
func configure(equipment: ItemContainer, weapons: ItemContainer, pockets: ItemContainer,
		stats: PlayerStats = null, body_id := CharacterDB.DEFAULT_BODY,
		editing := false) -> void:
	_equipment = equipment
	_weapons = weapons
	_pockets = pockets
	_stats = stats
	_body_id = CharacterDB.sanitize_body(body_id)
	_skin_id = CharacterDB.default_skin(_body_id)
	_editing = editing


func set_player_name(value: String) -> void:
	_player_name = value


## Slot name (or [constant TINT_BODY]) to HTML colour, as [CharacterDB] stores them.
func set_tints(tints: Dictionary) -> void:
	_tints = tints.duplicate(true)
	_paint_model()
	_update_tint_caption()


func set_skin(skin_id: String) -> void:
	var clean := CharacterDB.sanitize_skin(_body_id, skin_id)
	if clean == _skin_id:
		return
	_skin_id = clean
	_fill_skin_row()
	_paint_model()


## Swaps the model for another body. The caller has already decided what happens to
## the garments that were on the old one.
func set_body(body_id: String) -> void:
	body_id = CharacterDB.sanitize_body(body_id)
	if body_id == _body_id:
		return
	_body_id = body_id
	_skin_id = CharacterDB.sanitize_skin(_body_id, _skin_id)
	_preview_worn.clear()
	if is_instance_valid(_preview_pivot):
		if is_instance_valid(_preview_character):
			_preview_character.queue_free()
		_preview_character = _new_model()
		_preview_pivot.add_child(_preview_character)
		_frame_model()
	_fill_skin_row()
	refresh()
	_paint_model()


## The three containers the page was configured against, so a harness can move an
## item without a mouse.
func worn_slots() -> ItemContainer:
	return _equipment


func spare_slots() -> ItemContainer:
	return _pockets


func rack_slots() -> ItemContainer:
	return _weapons


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	# Late, because a ViewportTexture can only resolve the path to its viewport
	# once both ends are in the tree.
	if _preview_holder != null:
		_preview_holder.texture = _preview_viewport.get_texture()
	refresh()
	_paint_model()


func _process(_delta: float) -> void:
	if _tooltip.visible:
		_place_tooltip()


## A plain [Control] does not take a size from its children, and this one is put
## inside a card that has to fit it — the character editor's card is sized by its
## contents. So the page reports the layout column's own minimum and leaves the
## tooltip out of it, which is right for a second reason: the tooltip is positioned
## against the mouse and would otherwise widen the card by its own width.
func _get_minimum_size() -> Vector2:
	return _column.get_combined_minimum_size() if _column != null else Vector2.ZERO


# --- Construction -----------------------------------------------------------

## One of the two halves, and nothing shared but the tooltip, the icon driver and
## the container hookups below.
##
## Both halves used to end in a captioned "Reserved" well marking the room the
## layout was designed with. They are gone: a well is a control, and a control
## the size of half the card reads as the screen's main feature however it is
## captioned. Blank card says the same thing and does not compete.
func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override(&"separation", ROW_GAP)
	add_child(column)
	_column = column
	if section == Section.POCKETS:
		column.add_child(_pockets_block())
	else:
		_build_hero(column)

	_build_tooltip()

	_icons = ItemIcons.new()
	add_child(_icons)
	_icons.icon_ready.connect(_on_icon_ready)
	_icons.request(ItemDB.ITEMS.keys())

	for container in [_equipment, _weapons, _pockets]:
		if container != null:
			(container as ItemContainer).changed.connect(refresh)
	if _stats != null:
		_stats.changed.connect(func(_id: StringName, _value: float) -> void: _fill_stats())
	update_minimum_size()


## Who you are, in one shape wherever it is shown: the name across the top; the
## figure and what it is wearing down the left; the stats, the weapon bar and the
## colour wheel down the right, in that order, with the wheel pushed into the
## bottom corner.
##
## The editor draws the same thing rather than a reduced version of it. It has no
## figure of its own — the one at the spawn behind the card is the model — and
## nothing has been picked up yet, so its stats are the ones a new character
## starts with and its weapon bar is empty. Both are worth the room they take:
## the two screens then hold still against each other, and the numbers you are
## about to play with are visible while you are choosing a body to hang them on.
func _build_hero(column: VBoxContainer) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 12)
	top.add_child(_name_plate())
	if _editing and CharacterDB.skin_ids(_body_id).size() > 1:
		top.add_child(_skin_picker())
	else:
		top.add_child(_spacer())
	column.add_child(top)

	var middle := HBoxContainer.new()
	middle.add_theme_constant_override(&"separation", 12)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(middle)
	if show_preview:
		middle.add_child(_preview())
	middle.add_child(_worn_column())

	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", ROW_GAP)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(right)
	right.add_child(_stats_block())
	right.add_child(_weapon_block())

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 12)
	bottom.add_child(_spacer())
	bottom.add_child(_colour_block())
	right.add_child(bottom)


## The name, top left. Typeable in the editor, where naming yourself is part of
## making a character; a plate in game, where it is who you already are.
func _name_plate() -> Control:
	var panel := PanelContainer.new()
	# The home editor shares this row with its texture buttons. Keeping the name
	# plate narrower than the read-only version leaves room for those controls at
	# the 1280 px reference width while retaining the full 24-character value.
	panel.custom_minimum_size = Vector2(216.0 if _editing else 260.0, 0.0)
	AuroraSurface.add_to(panel, AuroraSurface.Style.INPUT if _editing \
		else AuroraSurface.Style.ROW)
	var padding := _padded(8 if _editing else 10)
	panel.add_child(padding)
	if not _editing:
		var label := Label.new()
		label.text = _player_name
		label.add_theme_font_size_override(&"font_size", 19)
		label.add_theme_color_override(&"font_color", PALETTE.text_primary)
		padding.add_child(label)
		return panel

	# Body size rather than the 24 the in-game plate uses, which is what the row was
	# drawn for: the reserve beside it is 38 tall and a 24 px field with 10 px of
	# padding made the row 72. The editor is the page with 136 px of title band over
	# it and the least height to spend, and this row is where it was going.
	var field := LineEdit.new()
	field.text = _player_name
	field.placeholder_text = "Your name"
	field.max_length = 24
	field.add_theme_font_size_override(&"font_size", 13)
	field.text_submitted.connect(func(value: String) -> void: name_entered.emit(value))
	field.focus_exited.connect(func() -> void: name_entered.emit(field.text))
	padding.add_child(field)
	return panel


## Texture schemes are a property of this one body, not another body picker:
## both choices keep the settler's skeleton, measurements and wardrobe. Kept in
## the name row so adding the choice costs width the editor has rather than
## height it does not.
func _skin_picker() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AuroraSurface.add_to(panel, AuroraSurface.Style.ROW)
	var padding := _padded(6)
	panel.add_child(padding)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 6)
	padding.add_child(line)
	var caption := _caption("Texture")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(caption)
	_skin_row = HBoxContainer.new()
	_skin_row.add_theme_constant_override(&"separation", 5)
	_skin_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_skin_row)
	_fill_skin_row()
	return panel


func _fill_skin_row() -> void:
	if _skin_row == null:
		return
	for child in _skin_row.get_children():
		child.queue_free()
	for skin_id: String in CharacterDB.skin_ids(_body_id):
		var button := MenuWidgets.button(CharacterDB.skin_title(skin_id),
			AuroraSurface.Style.PRIMARY if skin_id == _skin_id else AuroraSurface.Style.BUTTON)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 12)
		var chosen := skin_id
		button.pressed.connect(func() -> void: _pick_skin(chosen))
		_skin_row.add_child(button)


func _pick_skin(skin_id: String) -> void:
	var clean := CharacterDB.sanitize_skin(_body_id, skin_id)
	if clean == _skin_id:
		return
	_skin_id = clean
	_fill_skin_row()
	_paint_model()
	skin_picked.emit(_skin_id)


## What is on the body, one tile per slot, head to feet.
##
## Centred down the row rather than sitting at the top of it, and larger wherever
## there is no figure beside it. Without a preview this column *is* the left of
## the card — the home screen's editor is the case, since its model is the figure
## standing at the spawn behind it — and five 52 px tiles stranded against the top
## edge of a 600 px row leave the whole lower half of the card blank.
func _worn_column() -> Control:
	var worn := VBoxContainer.new()
	worn.add_theme_constant_override(&"separation", GAP)
	worn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for index in _equipment.size():
		var slot := _new_slot(_equipment, index)
		if not show_preview:
			slot.set_edge(WORN_TILE)
		slot.placeholder = String(ItemDB.SLOT_LABELS.get(_equipment.filter_of(index), ""))
		worn.add_child(slot)
	return worn


## The weapon slots, in the same order and with the same numbers as the bar on the
## HUD, because they are the same container.
func _weapon_block() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", GAP)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override(&"separation", GAP)
	for index in _weapons.size():
		var slot := _new_slot(_weapons, index)
		slot.badge = str(index + 1)
		slots.add_child(slot)
	block.add_child(slots)
	# The editor's line is short on purpose: a hint is the widest single control in
	# the right-hand column, so it sets the card's width, and the editor's card is
	# a share of the window with a figure standing in the rest of it.
	block.add_child(_hint("What you start with" if _editing \
		else "1 - %d or the mouse wheel to draw" % _weapons.size()))
	return block


## What you are carrying, over the filters that narrow it.
func _pockets_block() -> Control:
	var block := VBoxContainer.new()
	block.add_theme_constant_override(&"separation", GAP)
	block.add_child(_filters())
	_grid = GridContainer.new()
	_grid.columns = CATALOGUE_MIN_COLUMNS if catalogue else COLUMNS
	_grid.add_theme_constant_override(&"h_separation", GAP)
	_grid.add_theme_constant_override(&"v_separation", GAP)
	for index in _pockets.size():
		var slot := _new_slot(_pockets, index)
		if catalogue:
			slot.set_edge(CATALOGUE_TILE)
		_grid.add_child(slot)
	block.add_child(_grid)
	if catalogue:
		_grid.resized.connect(_fit_columns)
	return block


## As many tiles across as the grid has been given room for. A GridContainer wraps
## on its column count and not on its width, so without this the catalogue is as
## wide as the narrowest card it is ever shown in and the rest of the page is
## blank to the right of it.
func _fit_columns() -> void:
	var across := maxi(CATALOGUE_MIN_COLUMNS,
		int((_grid.size.x + GAP) / (CATALOGUE_TILE + GAP)))
	if _grid.columns != across:
		_grid.columns = across


# --- Filtering the pockets --------------------------------------------------

## Two rows of toggles: what kind of thing, and then which of that kind.
##
## The second row is the sub-divisions of whatever the first has chosen, which
## today means the body slots under Clothing and nothing under the other two —
## so the row is only there when it has something to say. A weapon has no body
## slot, and a row of five greyed-out garment names above a grid of rifles would
## be worse than an absent row.
func _filters() -> Control:
	# The catalogue is a wardrobe, so it opens on the clothes rather than on
	# everything: the mock-up's two rows are both up on arrival, and there is no
	# state where the second row is missing until you go looking for a weapon.
	if catalogue:
		_category = "clothing"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", GAP)
	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override(&"separation", GAP)
	box.add_child(_category_row)
	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override(&"separation", GAP)
	box.add_child(_slot_row)
	_fill_filters()
	return box


func _fill_filters() -> void:
	var labels: Array[String] = []
	var ids: Array[String] = []
	for id: String in CATEGORIES:
		labels.append(String(CATEGORIES[id]))
		ids.append(id)
	_fill_toggles(_category_row, labels, ids, _category, _pick_category)
	_slot_row.visible = _category == "clothing"
	if not _slot_row.visible:
		return
	var slot_labels: Array[String] = []
	for slot: String in ItemDB.SLOT_ORDER:
		slot_labels.append(String(ItemDB.SLOT_LABELS.get(slot, slot)))
	_fill_toggles(_slot_row, slot_labels, ItemDB.SLOT_ORDER, _slot_filter, _pick_slot)


## Toggles rather than a radio group, so pressing the open one clears it. That is
## the same idiom the worn tiles use to hand the colour wheel back to the skin,
## and it is what saves an "All" button that would otherwise be needed on both
## rows.
func _fill_toggles(row: HBoxContainer, labels: Array[String], ids: Array,
		current: String, on_pick: Callable) -> void:
	for child in row.get_children():
		child.queue_free()
	for index in labels.size():
		var id := String(ids[index])
		var button := MenuWidgets.button(labels[index],
			AuroraSurface.Style.PRIMARY if id == current else AuroraSurface.Style.BUTTON)
		button.add_theme_font_size_override(&"font_size", 13)
		button.pressed.connect(func() -> void: on_pick.call(id))
		row.add_child(button)


func _pick_category(id: String) -> void:
	# The catalogue has no "everything" state to fall back to, because opening it
	# on everything is what the mock-up's lit Clothing button says it does not do.
	_category = "" if _category == id and not catalogue else id
	# A slot filter left behind by Clothing would keep narrowing a category that
	# has no body slots, and nothing on screen would say why the grid is empty.
	if _category != "clothing":
		_slot_filter = ""
	_fill_filters()
	_refresh_pockets()


func _pick_slot(id: String) -> void:
	_slot_filter = "" if _slot_filter == id else id
	_fill_filters()
	_refresh_pockets()


## Which tiles of the grid can be seen, and which are marked as worn. One pass,
## because both are answers about the same tile taken from the same containers
## and both have to be taken again whenever anything moves.
##
## Hiding rather than greying: a [GridContainer] lays out only its visible
## children, so the survivors close up instead of leaving the grid full of holes.
func _refresh_pockets() -> void:
	if _slot_row == null:
		return
	var filtering := catalogue or not (_category.is_empty() and _slot_filter.is_empty())
	for slot in _slots:
		if slot.container != _pockets:
			continue
		var id := slot.item_id()
		# Empty tiles go with the filter rather than staying as somewhere to drop
		# things: a filtered grid is a search result, and blanks are not results.
		# A catalogue is nowhere to drop anything, so its blanks never show.
		slot.visible = _matches(id) if filtering else true
		var worn := catalogue and not id.is_empty() and _in_use(id)
		if slot.selected != worn:
			slot.selected = worn
		slot.queue_redraw()


## Whether a catalogue entry is on the body or on the rack. Both, because a
## catalogue lists weapons beside garments and a ring that only ever meant "worn"
## would leave every weapon looking unequipped while one of them is in hand.
func _in_use(id: String) -> bool:
	return _equipment.find(id) >= 0 or (_weapons != null and _weapons.find(id) >= 0)


func _matches(id: String) -> bool:
	if id.is_empty():
		return false
	if not _category.is_empty() and _category_of(id) != _category:
		return false
	return _slot_filter.is_empty() or ItemDB.slot_of(id) == _slot_filter


func _category_of(id: String) -> String:
	var slot := ItemDB.slot_of(id)
	if slot == ItemDB.WEAPON:
		return "weapons"
	return "clothing" if ItemDB.SLOT_ORDER.has(slot) else "items"


# --- Stats ------------------------------------------------------------------

func _stats_block() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	AuroraSurface.add_to(panel, AuroraSurface.Style.ROW)
	var padding := _padded(16)
	panel.add_child(padding)
	_stat_rows = VBoxContainer.new()
	_stat_rows.add_theme_constant_override(&"separation", 8)
	padding.add_child(_stat_rows)
	_fill_stats()
	return panel


## One row per entry in [constant PlayerStats.STATS], so a stat added to that table
## shows up here with no edit. The editor has no stats to show and says so rather
## than drawing an empty well.
func _fill_stats() -> void:
	for child in _stat_rows.get_children():
		child.queue_free()
	_stat_rows.add_child(_caption("Stats"))
	if _stats == null:
		_stat_rows.add_child(_hint("Stats begin once you are in the world."))
		return
	for id in PlayerStats.ids():
		_stat_rows.add_child(_stat_row(_stats.row(StringName(id))))


func _stat_row(row: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)

	var line := HBoxContainer.new()
	var title := Label.new()
	title.text = String(row["title"])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 14)
	title.add_theme_color_override(&"font_color", PALETTE.text_secondary)
	line.add_child(title)

	var value := Label.new()
	value.text = String(row["text"])
	value.add_theme_font_size_override(&"font_size", 14)
	value.add_theme_color_override(&"font_color", PALETTE.text_primary)
	line.add_child(value)
	box.add_child(line)
	box.add_child(_bar(float(row["share"])))
	return box


## A filled share of a track, drawn rather than themed: a ProgressBar would need a
## pair of styleboxes, and `main_theme.tres` leaves styleboxes empty on purpose so
## that the pencil shader reaches a control's edge.
func _bar(share: float) -> Control:
	var track := Control.new()
	track.custom_minimum_size = Vector2(0.0, 7.0)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filled := clampf(share, 0.0, 1.0)
	track.draw.connect(func() -> void:
		track.draw_rect(Rect2(Vector2.ZERO, track.size), PALETTE.paper_shade)
		track.draw_rect(Rect2(Vector2.ZERO,
			Vector2(track.size.x * filled, track.size.y)), PALETTE.secondary)
	)
	return track


# --- The colour wheel -------------------------------------------------------

## Bottom right, where the mock-up puts it. What it recolours is whichever worn
## tile is selected, or the skin when none is — so the tiles are the target
## picker and there is not a second one.
##
## There used to be a row of buttons here naming every garment on the body, which
## said the same thing as the equipment tiles a few centimetres above it and had
## to be rebuilt from the container every time anything moved, purely to stay in
## step with them. A tile that is already on screen, already knows what is in it
## and already draws a selected state for the weapon bar is the control that was
## being duplicated.
func _colour_block() -> Control:
	var panel := PanelContainer.new()
	AuroraSurface.add_to(panel, AuroraSurface.Style.ROW)
	var padding := _padded(10)
	panel.add_child(padding)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	# Wider than the wheel on purpose. The line under the heading names what is
	# being painted and the longest of those is a sentence, so at the disc's own
	# width it wraps to three lines — and height is the axis this card runs out
	# of, while width it has going spare.
	column.custom_minimum_size = Vector2(TINT_BLOCK_WIDTH, 0.0)
	padding.add_child(column)
	var title_row := HBoxContainer.new()
	title_row.add_child(_caption("Colour"))
	title_row.add_child(_spacer())
	_clear_tint = MenuWidgets.button("No tint", AuroraSurface.Style.BUTTON)
	_clear_tint.add_theme_font_size_override(&"font_size", 12)
	_clear_tint.pressed.connect(_clear_selected_tint)
	title_row.add_child(_clear_tint)
	column.add_child(title_row)
	_tint_caption = _hint("")
	_tint_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tint_caption.custom_minimum_size = Vector2(TINT_BLOCK_WIDTH, 0.0)
	column.add_child(_tint_caption)

	_wheel = ColourWheel.new()
	_wheel.picked.connect(_pick_tint)
	column.add_child(_wheel)
	_update_tint_caption()
	return panel


func _pick_tint(colour: Color) -> void:
	_tints[_tint_target] = colour.to_html(false)
	_paint_model()
	_update_tint_caption()
	tint_picked.emit(_tint_target, colour)


func _clear_selected_tint() -> void:
	if not _tints.has(_tint_target):
		return
	_tints.erase(_tint_target)
	_paint_model()
	_update_tint_caption()
	tint_cleared.emit(_tint_target)


## A tile was clicked. On the body it aims the wheel; in a catalogue it dresses.
##
## Clicking the selected worn tile again lets go of it, because there has to be a
## way back to the skin that is not taking the hat off. Clicking a catalogue tile
## that is already on the body takes it off for the same reason: the tab has no
## other way to undress, and a click that only ever equips does nothing at all
## half the time it is used.
func _on_slot_picked(slot: ItemSlot) -> void:
	if slot.container == _pockets and catalogue:
		_wear(slot.item_id())
		return
	var target := TINT_BODY
	if slot.container == _equipment and not slot.item_id().is_empty():
		var chosen := _equipment.filter_of(slot.index)
		target = TINT_BODY if chosen == _tint_target else chosen
	_set_tint_target(target)


## Puts `id` on the body or on the rack, or takes it off if that is where it
## already is. Nothing is moved between containers: a catalogue lists what
## exists, and the equipment and weapon containers are the only places a thing
## being carried is recorded.
##
## A garment goes to the one slot that accepts it, so wearing a second hat swaps
## the first out. A weapon has five interchangeable slots instead, so it goes to
## the first empty one and the rack fills up left to right the way the number keys
## expect.
func _wear(id: String) -> void:
	if id.is_empty():
		return
	if ItemDB.is_weapon(id):
		_rack(id)
		return
	var body_slot := ItemDB.slot_of(id)
	for index in _equipment.size():
		if _equipment.filter_of(index) != body_slot:
			continue
		_equipment.set_item(index, "" if _equipment.get_item(index) == id else id)
		return


func _rack(id: String) -> void:
	if _weapons == null:
		return
	var held := _weapons.find(id)
	if held >= 0:
		_weapons.set_item(held, "")
		return
	var free := _weapons.first_accepting(id)
	if free >= 0:
		_weapons.set_item(free, id)


## Puts the selection ring, the caption, the wheel and [member _tint_target] in
## step. Also the place a target that has just been taken off is dropped: the
## wheel must never silently paint a garment nobody can see.
func _set_tint_target(target: String) -> void:
	if target != TINT_BODY and _equipped_in(target).is_empty():
		target = TINT_BODY
	_tint_target = target
	# Worn tiles only: a catalogue tile's ring says the garment is on the body,
	# and this pass would clear every one of them.
	for slot in _slots:
		if slot.container != _equipment:
			continue
		var wanted := target != TINT_BODY and _equipment.filter_of(slot.index) == target
		if slot.selected != wanted:
			slot.selected = wanted
			slot.queue_redraw()
	_update_tint_caption()


## The caption names what the wheel is aimed at, and the wheel is moved to
## whatever that thing has already been painted — otherwise every target opens on
## white and the marker says nothing about the colour under it.
func _update_tint_caption() -> void:
	if _tint_caption == null:
		return
	var target_name := "the skin — click a worn tile" \
		if _tint_target == TINT_BODY else ItemDB.title(_equipped_in(_tint_target))
	_tint_caption.text = target_name + (" — tint active" if _tints.has(_tint_target) \
		else " — authored colour")
	if _clear_tint != null:
		_clear_tint.disabled = not _tints.has(_tint_target)
	if _wheel != null:
		_wheel.set_colour(Color.html(str(_tints.get(_tint_target, "ffffff"))))


## Read off the filters rather than by position, so this does not depend on the
## equipment container being in SLOT_ORDER.
func _equipped_in(slot: String) -> String:
	for index in _equipment.size():
		if _equipment.filter_of(index) == slot:
			return _equipment.get_item(index)
	return ""


# --- The figure -------------------------------------------------------------

## A live model wearing whatever the equipment container holds, on a pivot so it
## can be turned by dragging it. The pivot rather than the model itself, because
## the model is replaced whenever the body changes and the spin should survive that.
func _preview() -> Control:
	var holder := TextureRect.new()
	holder.custom_minimum_size = PREVIEW_SIZE
	# Otherwise the panel would grow to the full size of the supersampled render.
	holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	holder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(_on_preview_input)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(PREVIEW_SIZE * PREVIEW_SUPERSAMPLE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(viewport)

	# No environment of its own: the transparent target already clears to nothing,
	# and the pencil material ignores ambient light, so the only thing an
	# Environment here could do is escape into the world's own lighting. That same
	# blindness to ambient is why the model needs a lamp to hatch against.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, 152.0, 0.0)
	key.light_energy = 1.1
	viewport.add_child(key)

	_preview_pivot = Node3D.new()
	viewport.add_child(_preview_pivot)
	_preview_character = _new_model()
	_preview_pivot.add_child(_preview_character)

	_preview_camera = Camera3D.new()
	_preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(_preview_camera)
	_preview_holder = holder
	_preview_viewport = viewport
	_frame_model()
	return holder


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_spin -= event.relative.x * SPIN_PER_PIXEL
		if is_instance_valid(_preview_pivot):
			_preview_pivot.basis = Basis(Vector3.UP, _spin)


func _new_model() -> Node3D:
	var packed := CharacterDB.scene(_body_id)
	var model: Node3D = packed.instantiate() if packed != null else Node3D.new()
	CharacterRig.normalize_body(model)
	SurfaceSkin.apply(model, true)
	SurfaceSkin.set_body_texture(model, CharacterDB.skin_texture(_body_id, _skin_id))
	_play_idle(model)
	return model


## Framed on the body's authored height with headroom for a hat, from slightly
## off-centre so the pose reads as three-dimensional. Re-measured whenever the body
## changes, since two bodies are not the same height.
func _frame_model() -> void:
	var height := CharacterDB.height(_body_id)
	_preview_camera.size = height * 1.28
	var eye := Vector3(-0.55, height * 0.54, -1.9)
	var target := Vector3(0.0, height * 0.5, 0.0)
	_preview_camera.transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)


func _play_idle(character: Node) -> void:
	var animator: AnimationPlayer = null
	for node in character.find_children("*", "AnimationPlayer", true, false):
		animator = node as AnimationPlayer
		break
	if animator == null:
		return
	CharacterRig.prepare(animator, CharacterDB.extra_animation_paths(_body_id))
	var clip := CharacterRig.resolve_clip(animator, "Idle")
	if not animator.has_animation(clip):
		return
	animator.play(clip)


# --- Small parts ------------------------------------------------------------

func _new_slot(container: ItemContainer, index: int) -> ItemSlot:
	var slot := ItemSlot.new()
	slot.bind(container, index)
	slot.draggable = not (catalogue and container == _pockets)
	slot.picked.connect(_on_slot_picked)
	slot.quick_move_requested.connect(_on_quick_move)
	slot.hover_started.connect(_on_hover_started)
	slot.hover_ended.connect(_on_hover_ended)
	_slots.append(slot)
	return slot


## Blank card, pushing whatever comes after it to the far end of the row.
func _spacer() -> Control:
	var control := Control.new()
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


## Margins are theme constants rather than properties, so they cannot be set
## through the inspector-style names.
func _padded(inset: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		margin.add_theme_constant_override(side, inset)
	return margin


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 14)
	label.add_theme_color_override(&"font_color", PALETTE.text_secondary)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 11)
	label.add_theme_color_override(&"font_color", PALETTE.text_muted)
	return label


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0.0)
	add_child(_tooltip)
	AuroraSurface.add_to(_tooltip, AuroraSurface.Style.ROW)

	var padding := _padded(10)
	_tooltip.add_child(padding)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 2)
	padding.add_child(column)

	_tooltip_title = Label.new()
	_tooltip_title.add_theme_font_size_override(&"font_size", 17)
	_tooltip_title.add_theme_color_override(&"font_color", PALETTE.text_primary)
	column.add_child(_tooltip_title)

	_tooltip_body = Label.new()
	_tooltip_body.add_theme_font_size_override(&"font_size", 14)
	_tooltip_body.add_theme_color_override(&"font_color", PALETTE.text_secondary)
	_tooltip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_body.custom_minimum_size = Vector2(TOOLTIP_WIDTH - 20.0, 0.0)
	column.add_child(_tooltip_body)


# --- Reacting ---------------------------------------------------------------

## Everything that depends on a container, in one call. Public because the owner
## changes containers behind the page's back — the home screen restocks the
## rail when the body changes.
func refresh() -> void:
	for slot in _slots:
		slot.queue_redraw()
	if _hovered != null:
		_show_tooltip(_hovered)
	_refresh_preview()
	_set_tint_target(_tint_target)
	# An item that has just moved may no longer match what the grid is narrowed
	# to, and a tile left showing through a filter it fails is worse than one that
	# has gone: it reads as the filter being broken.
	_refresh_pockets()
	if _stat_rows != null:
		_fill_stats()


## Puts the model in step with the equipment container, garment by garment, so an
## unchanged shirt is not reloaded because a hat came off.
func _refresh_preview() -> void:
	if not is_instance_valid(_preview_character):
		return
	var dressing_changed := false
	for index in _equipment.size():
		var body_slot := _equipment.filter_of(index)
		var id := _equipment.get_item(index)
		if _preview_worn.get(body_slot, "") == id:
			continue
		_preview_worn[body_slot] = id
		dressing_changed = true
		if id.is_empty():
			Wardrobe.unequip(_preview_character, body_slot)
			continue
		var garment := Wardrobe.equip(_preview_character, body_slot, ItemDB.scene_path(id))
		if garment != null:
			SurfaceSkin.paint(garment, {}, true)
	if dressing_changed and not _tints.is_empty():
		_paint_model()


## A tint multiplies the albedo it finds, so picking three colours in a row would
## otherwise leave the garment the product of all three. Every tint is laid over a
## freshly painted model instead of over the last one.
##
## Materials are derived per target rather than across the whole model, which does
## two things: a material the body and a garment happened to share cannot carry
## one's tint onto the other, and each material is tinted exactly once however many
## meshes are wearing it.
func _paint_model() -> void:
	if not is_instance_valid(_preview_character):
		return
	var groups: Dictionary = {}
	for node in _preview_character.find_children("*", "MeshInstance3D", true, false):
		var worn_as := String(node.name)
		var target := worn_as.trim_prefix(Wardrobe.NODE_PREFIX) \
			if worn_as.begins_with(Wardrobe.NODE_PREFIX) else TINT_BODY
		groups.get_or_add(target, []).append(node)
	for target: String in groups:
		var derived: Dictionary = {}
		for mesh_instance: MeshInstance3D in groups[target]:
			SurfaceSkin.paint(mesh_instance, derived, true)
		if target == TINT_BODY:
			var texture := CharacterDB.skin_texture(_body_id, _skin_id)
			for mesh_instance: MeshInstance3D in groups[target]:
				SurfaceSkin.set_texture(mesh_instance, texture)
		if not _tints.has(target):
			continue
		var colour := Color.html(str(_tints[target]))
		for material: Variant in derived.values():
			SurfaceSkin.tint_material(material as ShaderMaterial, colour)
	SurfaceSkin.apply_outline_tint(_preview_character, _tints)


## Shift-clicking sends an item where it most obviously wants to go: onto the body
## or the rack if it can be equipped, and off either into your pockets.
##
## Against a catalogue there is nowhere to send it, because the grid holds every
## item whether it is carried or not — so the shortcut means take it off, which is
## the same thing clicking the tile does. Moving it would be worse than useless:
## the rail is sized to its own contents and has no free slot, so the item would
## land on top of another entry or vanish.
func _on_quick_move(slot: ItemSlot) -> void:
	var id := slot.item_id()
	if id.is_empty():
		return
	var from := slot.container
	var equipped: Array[ItemContainer] = [_equipment, _weapons]
	if catalogue:
		if equipped.has(from):
			from.set_item(slot.index, "")
		else:
			_wear(id)
		return
	if equipped.has(from):
		ItemContainer.quick_move(from, slot.index, _pockets)
		return
	for to in equipped:
		if to.first_accepting(id) >= 0:
			ItemContainer.quick_move(from, slot.index, to)
			return


func _on_hover_started(slot: ItemSlot) -> void:
	_hovered = slot
	_show_tooltip(slot)


func _on_hover_ended(slot: ItemSlot) -> void:
	if _hovered != slot:
		return
	_hovered = null
	_tooltip.visible = false


func _show_tooltip(slot: ItemSlot) -> void:
	var id := slot.item_id()
	if id.is_empty():
		_tooltip.visible = false
		return
	_tooltip_title.text = ItemDB.title(id)
	_tooltip_body.text = ItemDB.description(id)
	_tooltip.visible = true
	_tooltip.reset_size()
	_place_tooltip()


func _place_tooltip() -> void:
	var wanted := get_global_mouse_position() + TOOLTIP_OFFSET
	var limit := size - _tooltip.size - Vector2(8.0, 8.0)
	_tooltip.global_position = Vector2(minf(wanted.x, limit.x), minf(wanted.y, limit.y)).maxf(8.0)


func _on_icon_ready(_id: String, _texture: Texture2D) -> void:
	for slot in _slots:
		slot.queue_redraw()
