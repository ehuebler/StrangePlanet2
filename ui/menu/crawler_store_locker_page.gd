class_name CrawlerStoreLockerPage
extends VBoxContainer

## City-store locker. The top pane is the player's ability row. The bottom
## pane holds one ability and its seated mods. That card is written to
## [CrawlerMeta] so a later run can take it out.

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const GREEN := Color("45df68")
const BLACK_40 := Color(0.0, 0.0, 0.0, 0.40)
const TILE_MIN := 78.0

var _player: OnlinePlayer
var _kit: CrawlerKit
var _locker: CrawlerKit
var _player_tiles: Array[CrawlerAbilityTile] = []
var _player_row: HBoxContainer
var _locker_tile: CrawlerAbilityTile
var _price_label: Label
var _deposit_button: Button
var _withdraw_button: Button
var _selected_index := -1


func configure(player: OnlinePlayer) -> void:
	_player = player
	_kit = player.crawler_kit if player != null else null
	_ensure_locker()


func locker_kit() -> CrawlerKit:
	_ensure_locker()
	return _locker


func _ready() -> void:
	name = "StoreLockerPage"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 10)
	_ensure_locker()
	_build()
	refresh()
	_request_icons()


func refresh() -> void:
	if _kit == null and _player != null:
		_kit = _player.crawler_kit
	_ensure_locker()
	_sync_player_tiles()
	for tile: CrawlerAbilityTile in _player_tiles:
		tile.setup(tile.index, _kit, CrawlerKit.SOURCE_EQUIP)
		tile.refresh()
	if _locker_tile != null:
		_locker_tile.setup(0, _locker, CrawlerKit.SOURCE_EQUIP)
		_locker_tile.refresh()
	_refresh_actions()
	_request_icons()


func notify_icon_ready() -> void:
	for tile: CrawlerAbilityTile in _player_tiles:
		if tile != null:
			tile.refresh()
	if _locker_tile != null:
		_locker_tile.refresh()


func _ensure_locker() -> void:
	if _locker != null:
		return
	_locker = CrawlerKit.new()
	_locker.open_bank(1, 0)
	var raw := CrawlerMeta.locker_card()
	if not raw.is_empty():
		var card := CrawlerCard.from_dict(raw)
		if card != null:
			_locker.place_card(card, CrawlerKit.SOURCE_EQUIP, 0)
	_locker.changed.connect(_persist_locker)


func _persist_locker() -> void:
	if _locker == null:
		return
	var card := _locker.equipped_card(0)
	CrawlerMeta.set_locker_card(card.to_dict() if card != null else {})


func _build() -> void:
	var loadout := _pane("StoreLockerLoadout")
	var loadout_body := VBoxContainer.new()
	loadout_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loadout_body.add_theme_constant_override(&"separation", 6)
	loadout.add_child(loadout_body)
	loadout_body.add_child(_caption("YOU"))
	var ability_scroll := ScrollContainer.new()
	ability_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ability_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ability_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ability_scroll.custom_minimum_size.y = TILE_MIN + 8.0
	ability_scroll.clip_contents = true
	loadout_body.add_child(ability_scroll)
	_player_row = HBoxContainer.new()
	_player_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_player_row.custom_minimum_size.y = TILE_MIN
	_player_row.add_theme_constant_override(&"separation", 6)
	ability_scroll.add_child(_player_row)
	for index in _ability_slot_count():
		_player_row.add_child(_make_player_tile(index))
	add_child(loadout)

	var bank := _pane("StoreLockerBank")
	var bank_body := VBoxContainer.new()
	bank_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bank_body.add_theme_constant_override(&"separation", 6)
	bank.add_child(bank_body)
	bank_body.add_child(_caption("LOCKER"))
	_price_label = _caption("100g TO DEPOSIT OR WITHDRAW")
	_price_label.name = "LockerPriceLabel"
	bank_body.add_child(_price_label)
	var actions := HBoxContainer.new()
	actions.name = "LockerActions"
	actions.add_theme_constant_override(&"separation", 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_body.add_child(actions)
	_deposit_button = _action_button("LockerDepositButton", "DEPOSIT 100g")
	_deposit_button.pressed.connect(deposit_selected)
	actions.add_child(_deposit_button)
	_withdraw_button = _action_button("LockerWithdrawButton", "WITHDRAW 100g")
	_withdraw_button.pressed.connect(withdraw_stored)
	actions.add_child(_withdraw_button)
	var hold := HBoxContainer.new()
	hold.alignment = BoxContainer.ALIGNMENT_CENTER
	hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hold.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bank_body.add_child(hold)
	_locker_tile = CrawlerAbilityTile.new()
	_locker_tile.name = "LockerAbilityTile_0"
	_locker_tile.source = CrawlerKit.SOURCE_EQUIP
	_locker_tile.editable = true
	_locker_tile.show_clear = false
	_locker_tile.mods_interactive = false
	_locker_tile.compact = true
	_locker_tile.custom_minimum_size = Vector2(280.0, TILE_MIN)
	_locker_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locker_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_locker_tile.setup(0, _locker, CrawlerKit.SOURCE_EQUIP)
	_locker_tile.card_received.connect(_on_ability_received)
	hold.add_child(_locker_tile)
	add_child(bank)


func _make_player_tile(index: int) -> CrawlerAbilityTile:
	var tile := CrawlerAbilityTile.new()
	tile.name = "CrawlerAbilityTile_%d" % index
	tile.source = CrawlerKit.SOURCE_EQUIP
	tile.editable = true
	tile.show_clear = false
	tile.mods_interactive = false
	tile.compact = true
	tile.custom_minimum_size.y = TILE_MIN
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.setup(index, _kit, CrawlerKit.SOURCE_EQUIP)
	tile.card_received.connect(_on_ability_received)
	tile.picked.connect(_on_player_picked)
	_player_tiles.append(tile)
	return tile


func _sync_player_tiles() -> void:
	if _player_row == null:
		return
	var wanted := _ability_slot_count()
	while _player_tiles.size() < wanted:
		_player_row.add_child(_make_player_tile(_player_tiles.size()))
	while _player_tiles.size() > wanted:
		var tile: CrawlerAbilityTile = _player_tiles.pop_back()
		if tile != null:
			tile.queue_free()


func _ability_slot_count() -> int:
	if _kit != null:
		var bar := _kit.ability_bar()
		if bar != null:
			return bar.size()
	if _player != null and _player.abilities != null:
		return _player.abilities.size()
	return CrawlerRules.ABILITY_SLOTS


func _on_player_picked(tile: CrawlerAbilityTile) -> void:
	if tile == null:
		return
	_selected_index = tile.index
	for other: CrawlerAbilityTile in _player_tiles:
		other.selected = other == tile
	_refresh_actions()


func deposit_selected() -> bool:
	var from := _selected_index
	if from < 0 or _kit == null or _kit.equipped_card(from) == null:
		from = _first_filled_player_index()
	if from < 0 or _locker == null or _locker.equipped_card(0) != null:
		return false
	if not _pay_locker():
		return false
	var moved := CrawlerKit.hand_off(
		_kit, CrawlerKit.SOURCE_EQUIP, from,
		_locker, CrawlerKit.SOURCE_EQUIP, 0
	)
	if not moved:
		_refund_locker()
		return false
	_selected_index = -1
	refresh()
	_refresh_store_gold()
	return true


func withdraw_stored() -> bool:
	if _kit == null or _locker == null or _locker.equipped_card(0) == null:
		return false
	var dest := _first_empty_player_index()
	if dest < 0:
		return false
	if not _pay_locker():
		return false
	var moved := CrawlerKit.hand_off(
		_locker, CrawlerKit.SOURCE_EQUIP, 0,
		_kit, CrawlerKit.SOURCE_EQUIP, dest
	)
	if not moved:
		_refund_locker()
		return false
	refresh()
	_refresh_store_gold()
	return true


func _on_ability_received(tile: CrawlerAbilityTile, data: Dictionary) -> void:
	if tile == null or not bool(data.get("crawler_move", false)):
		return
	var from_kit := data.get("kit") as CrawlerKit
	if from_kit == null:
		from_kit = _kit
	if _crosses_locker(from_kit, tile.kit) and not _pay_locker():
		refresh()
		return
	var moved := CrawlerKit.hand_off(
		from_kit,
		str(data.get("source", "")),
		int(data.get("index", -1)),
		tile.kit,
		tile.source,
		tile.index
	)
	if not moved and _crosses_locker(from_kit, tile.kit):
		_refund_locker()
	refresh()
	_refresh_store_gold()


func _crosses_locker(from_kit: CrawlerKit, to_kit: CrawlerKit) -> bool:
	return from_kit != to_kit and (from_kit == _locker or to_kit == _locker)


func _pay_locker() -> bool:
	var progress := _player.crawler_progress if _player != null else null
	if progress == null:
		return false
	return progress.spend_gold(CrawlerProgress.LOCKER_PRICE)


func _refund_locker() -> void:
	var progress := _player.crawler_progress if _player != null else null
	if progress == null:
		return
	progress.refund_gold(CrawlerProgress.LOCKER_PRICE)


func _first_filled_player_index() -> int:
	if _kit == null:
		return -1
	var bar := _kit.ability_bar()
	var count := bar.size() if bar != null else _ability_slot_count()
	for index in count:
		if _kit.equipped_card(index) != null:
			return index
	return -1


func _first_empty_player_index() -> int:
	if _kit == null:
		return -1
	var bar := _kit.ability_bar()
	var count := bar.size() if bar != null else _ability_slot_count()
	for index in count:
		if _kit.equipped_card(index) == null:
			return index
	return -1


func _refresh_actions() -> void:
	var progress := _player.crawler_progress if _player != null else null
	var price := CrawlerProgress.LOCKER_PRICE
	var can_pay := progress != null and progress.has_gold(price)
	if _price_label != null:
		_price_label.text = "%dg TO DEPOSIT OR WITHDRAW" % price
	var locker_card := _locker.equipped_card(0) if _locker != null else null
	var from := _selected_index
	if from < 0 or _kit == null or _kit.equipped_card(from) == null:
		from = _first_filled_player_index()
	if _deposit_button != null:
		_deposit_button.text = "DEPOSIT %dg" % price
		_deposit_button.disabled = not can_pay or from < 0 or locker_card != null
		_style_action(_deposit_button, not _deposit_button.disabled)
	if _withdraw_button != null:
		_withdraw_button.text = "WITHDRAW %dg" % price
		_withdraw_button.disabled = not can_pay or locker_card == null \
			or _first_empty_player_index() < 0
		_style_action(_withdraw_button, not _withdraw_button.disabled)


func _action_button(node_name: String, text: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_action(button, true)
	return button


func _style_action(button: Button, enabled: bool) -> void:
	var fill := GREEN if enabled else Color(0.22, 0.22, 0.22, 0.92)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(0)
	box.content_margin_left = 10
	box.content_margin_right = 10
	button.add_theme_stylebox_override(&"normal", box)
	button.add_theme_stylebox_override(&"hover", box)
	button.add_theme_stylebox_override(&"pressed", box)
	button.add_theme_stylebox_override(&"disabled", box)
	button.add_theme_color_override(&"font_color", Color.BLACK if enabled \
		else Color(1, 1, 1, 0.45))
	button.add_theme_color_override(&"font_hover_color", Color.BLACK)
	button.add_theme_color_override(&"font_pressed_color", Color.BLACK)
	button.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", RED_BRIGHT)
	return label


func _request_icons() -> void:
	var menu := _store_menu()
	if menu == null:
		return
	var ids: Array = []
	for id: String in ItemDB.ability_ids():
		ids.append(id)
	if _kit != null:
		for card: CrawlerCard in _kit.cards.values():
			if card != null and not ids.has(card.id):
				ids.append(card.id)
	if _locker != null:
		for card: CrawlerCard in _locker.cards.values():
			if card != null and not ids.has(card.id):
				ids.append(card.id)
	menu.request_item_icons(ids)


func _refresh_store_gold() -> void:
	var menu := _store_menu()
	if menu != null:
		menu.refresh_wallet()


func _store_menu() -> CrawlerFieldMenu:
	var node: Node = get_parent()
	while node != null:
		if node is CrawlerFieldMenu:
			return node as CrawlerFieldMenu
		node = node.get_parent()
	return null


func _pane(node_name: String) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.name = node_name
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK_40
	box.border_color = Color(RED_BRIGHT, 0.88)
	box.set_border_width_all(2)
	box.set_corner_radius_all(0)
	box.content_margin_left = 10
	box.content_margin_top = 10
	box.content_margin_right = 10
	box.content_margin_bottom = 10
	frame.add_theme_stylebox_override(&"panel", box)
	var glow := RedGlowPanel.add_to(frame)
	glow.fill_color = Color.TRANSPARENT
	glow.border_color = Color(RED, 0.90)
	glow.border_width = 1.5
	glow.glow_intensity = 1.15
	glow.glow_spread = 8.0
	glow.glow_layers = 4
	return frame
