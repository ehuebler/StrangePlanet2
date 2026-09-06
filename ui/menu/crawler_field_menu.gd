class_name CrawlerFieldMenu
extends Control

## Crawler E menu. Only opens inside a city. It is a seven-tab gold shop:
## hats, mods, abilities, upgrades, inventory, quests, and the black market.
## The shell uses the same starry sheet as the Tab menu so the store reads
## as the same chrome.

signal closed

enum Tab { HATS, CARDS, ABILITIES, UPGRADES, INVENTORY, QUESTS, MARKET }

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const MENU_BACKGROUND: Texture2D = preload("res://assets/runtime/ui/menu_background.png")
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const GREEN := Color("45df68")
const BLACK := Color(0.0, 0.0, 0.0, 0.82)
const BLACK_40 := Color(0.0, 0.0, 0.0, 0.40)
const EDGE := 28.0
const TAB_NAMES := [
	"HATS", "MODS", "ABILITIES", "UPGRADES", "INVENTORY", "QUESTS", "MARKET",
]
const STOCK_COLUMNS := 3
const TILE_MIN := Vector2(196.0, 236.0)

var _player: OnlinePlayer
var _closing := false
var _tab: Tab = Tab.HATS
var _title: Label
var _gold: Label
var _hint: Label
var _tab_row: HBoxContainer
var _tab_buttons: Array[Button] = []
var _list_host: PanelContainer
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _upgrades: CrawlerStoreUpgradesPage
var _icons: ItemIcons


func configure(player: OnlinePlayer) -> void:
	_player = player


func current_tab() -> Tab:
	return _tab


func request_item_icons(ids: Array) -> void:
	if _icons != null:
		_icons.request(ids)


func set_tab(tab: Tab) -> void:
	_tab = tab
	_refresh()


func cycle_tab(step: int) -> void:
	set_tab(wrapi(int(_tab) + step, 0, Tab.size()) as Tab)


func _init() -> void:
	name = "CrawlerFieldMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_refresh()
	if _player != null and _player.crawler_progress != null \
			and not _player.crawler_progress.changed.is_connected(_refresh):
		_player.crawler_progress.changed.connect(_refresh)
	if _player != null and _player.crawler_kit != null \
			and not _player.crawler_kit.changed.is_connected(_refresh):
		_player.crawler_kit.changed.connect(_refresh)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"move_left"):
		get_viewport().set_input_as_handled()
		cycle_tab(-1)
		return
	if event.is_action_pressed(&"move_right"):
		get_viewport().set_input_as_handled()
		cycle_tab(1)
		return
	if event.is_action_pressed(&"interact") \
			or event.is_action_pressed(&"inventory") \
			or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	_disconnect_ledgers()
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	_disconnect_ledgers()


func _disconnect_ledgers() -> void:
	if _player != null and _player.crawler_progress != null \
			and _player.crawler_progress.changed.is_connected(_refresh):
		_player.crawler_progress.changed.disconnect(_refresh)
	if _player != null and _player.crawler_kit != null \
			and _player.crawler_kit.changed.is_connected(_refresh):
		_player.crawler_kit.changed.disconnect(_refresh)


func _build() -> void:
	var shell := Control.new()
	shell.name = "StoreShell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.offset_left = EDGE
	shell.offset_top = EDGE
	shell.offset_right = -EDGE
	shell.offset_bottom = -EDGE
	shell.clip_contents = true
	shell.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shell)

	var background := TextureRect.new()
	background.name = "MenuBackground"
	background.texture = MENU_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_child(background)

	var border := RedGlowPanel.new()
	border.name = "StoreBorder"
	border.fill_color = Color.TRANSPARENT
	border.border_color = Color(GREEN, 0.98)
	border.border_width = 2.5
	border.glow_intensity = 1.25
	border.glow_spread = 8.0
	border.glow_layers = 4
	border.mouse_behavior = RedGlowPanel.MouseBehavior.IGNORE
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_child(border)

	var column := VBoxContainer.new()
	column.name = "StoreColumn"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 22.0
	column.offset_top = 18.0
	column.offset_right = -22.0
	column.offset_bottom = -18.0
	column.add_theme_constant_override(&"separation", 10)
	shell.add_child(column)

	_title = Label.new()
	_title.text = "CITY STORE"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 22)
	_title.add_theme_color_override(&"font_color", RED)
	column.add_child(_title)

	_gold = Label.new()
	_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold.add_theme_font_size_override(&"font_size", 18)
	_gold.add_theme_color_override(&"font_color", RED)
	column.add_child(_gold)

	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override(&"separation", 8)
	column.add_child(_tab_row)
	for index in TAB_NAMES.size():
		var button := Button.new()
		button.text = TAB_NAMES[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 36.0
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var chosen: Tab = index as Tab
		button.pressed.connect(func() -> void: set_tab(chosen))
		_tab_row.add_child(button)
		_tab_buttons.append(button)

	_hint = Label.new()
	_hint.add_theme_font_size_override(&"font_size", 11)
	_hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.62))
	column.add_child(_hint)

	_list_host = PanelContainer.new()
	_list_host.name = "StoreListFrame"
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_box := StyleBoxFlat.new()
	list_box.bg_color = BLACK_40
	list_box.border_color = Color(RED_BRIGHT, 0.88)
	list_box.set_border_width_all(2)
	list_box.set_corner_radius_all(0)
	list_box.content_margin_left = 12
	list_box.content_margin_top = 12
	list_box.content_margin_right = 12
	list_box.content_margin_bottom = 12
	_list_host.add_theme_stylebox_override(&"panel", list_box)
	column.add_child(_list_host)

	var list_column := VBoxContainer.new()
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_column.add_theme_constant_override(&"separation", 8)
	_list_host.add_child(list_column)

	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "StoreListScroll"
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_column.add_child(_list_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_list.add_theme_constant_override(&"separation", 8)
	_list_scroll.add_child(_list)

	_empty = Label.new()
	_empty.name = "StoreEmpty"
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_theme_font_size_override(&"font_size", 14)
	_empty.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.72))
	_empty.visible = false
	list_column.add_child(_empty)

	_upgrades = CrawlerStoreUpgradesPage.new()
	_upgrades.configure(_player)
	_upgrades.visible = false
	column.add_child(_upgrades)

	_icons = ItemIcons.new()
	_icons.name = "StoreItemIcons"
	add_child(_icons)
	_icons.icon_ready.connect(_on_store_icon_ready)


func _refresh() -> void:
	if _list == null:
		return
	var progress := _player.crawler_progress if _player != null else null
	var gold := progress.gold if progress != null else 0
	_gold.text = "GOLD  %d    GEMS  %d" % [gold, CrawlerMeta.gems()]
	var in_city := _player != null and _player.in_crawler_city()
	if _title != null:
		_title.visible = in_city
	_gold.visible = in_city
	if _tab_row != null:
		_tab_row.visible = in_city
	for index in _tab_buttons.size():
		_style_tab(_tab_buttons[index], index == int(_tab))
	_clear_list()
	if not in_city:
		_hint.text = ""
		_show_body(false)
		_show_empty("")
		return
	_show_body(_tab == Tab.UPGRADES)
	match _tab:
		Tab.HATS:
			_hint.text = "A / D flips stores. Hats bought here stay on this run."
			_fill_hats(progress, gold)
		Tab.CARDS:
			_hint.text = "A / D flips stores. Buy mods for the abilities you already own."
			_fill_cards(gold)
		Tab.ABILITIES:
			_hint.text = "A / D flips stores. Buy another Laser Eyes or Starfire. Copies share store upgrades."
			_fill_abilities(gold)
		Tab.UPGRADES:
			_hint.text = "A / D flips stores. Pick an ability or mod, then buy its upgrades."
			_fill_upgrades(gold)
		Tab.INVENTORY:
			_hint.text = "A / D flips stores."
			_fill_inventory()
		Tab.QUESTS:
			_hint.text = "A / D flips stores. A bought quest marks the site on tilde."
			_fill_quests()
		Tab.MARKET:
			_hint.text = "A / D flips stores. Respawn tickets cost gold and gems. Without one, death ends the run."
			_fill_market()


func _fill_inventory() -> void:
	_show_empty(
		"Store abilities here to pick them up in other cities."
	)


func _fill_market() -> void:
	var progress := _player.crawler_progress if _player != null else null
	var gold := progress.gold if progress != null else 0
	var gems := CrawlerMeta.gems()
	var held := progress.respawn_tickets if progress != null else 0
	var afford := gold >= CrawlerProgress.TICKET_GOLD \
			and gems >= CrawlerProgress.TICKET_GEMS
	_show_empty("")
	_add_row(
		"RESPAWN TICKET   %dg + %d gems" % [
			CrawlerProgress.TICKET_GOLD, CrawlerProgress.TICKET_GEMS,
		],
		"One death comes back at Relay 07. Without a ticket the run ends."
		if held <= 0
		else "Held: %d. The next death spends one." % held,
		"BUY",
		afford,
		_buy_ticket,
		"TicketAct"
	)


func _fill_quests() -> void:
	var progress := _player.crawler_progress if _player != null else null
	var gold := progress.gold if progress != null else 0
	var stock := CrawlerProgress.quest_stock()
	if stock.is_empty():
		_show_empty("The stall is empty.")
		return
	_show_empty("")
	for quest_id: String in stock:
		var owned := progress != null and progress.owns_quest(quest_id)
		var price := CrawlerProgress.quest_price(quest_id)
		if owned:
			_add_row(
				"%s   MARKED" % CrawlerProgress.quest_title(quest_id).to_upper(),
				CrawlerProgress.quest_blurb(quest_id),
				"OWNED",
				false,
				func() -> void: pass,
				"QuestAct_%s" % quest_id
			)
			continue
		_add_row(
			"%s   %dg" % [CrawlerProgress.quest_title(quest_id).to_upper(), price],
			CrawlerProgress.quest_blurb(quest_id),
			"BUY",
			gold >= price,
			_buy_quest.bind(quest_id),
			"QuestAct_%s" % quest_id
		)


func _fill_hats(progress: CrawlerProgress, gold: int) -> void:
	_show_empty("")
	var stock := CrawlerProgress.hat_stock()
	request_item_icons(stock)
	var grid := _stock_grid("StoreHatGrid")
	for hat_id: String in stock:
		grid.add_child(_make_hat_tile(hat_id, progress, gold))


func _make_hat_tile(hat_id: String, progress: CrawlerProgress, gold: int) -> Control:
	var owned := progress != null and progress.owns_hat(hat_id)
	var price := CrawlerProgress.hat_price(hat_id)
	var tile := _stock_tile("HatTile_%s" % hat_id)
	var copy := tile.get_child(0) as VBoxContainer
	var cached := ItemIcons.cached(hat_id)
	var icon := _stock_icon("HatIcon_%s" % hat_id, cached, cached == null)
	copy.add_child(icon)
	copy.add_child(_stock_label(ItemDB.title(hat_id).to_upper(), 16, Color(1, 1, 1, 0.94)))
	copy.add_child(_stock_label(
		"OWNED" if owned else "%dg" % price,
		13,
		GREEN if owned or gold >= price else Color(1, 1, 1, 0.72)
	))
	var body := _stock_label(CrawlerProgress.hat_blurb(hat_id, owned), 11, Color(1, 1, 1, 0.72), true)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var button := _stock_button(
		"HatAct_%s" % hat_id,
		"SOLD" if owned else "BUY",
		not owned and gold >= price
	)
	if hat_id == CrawlerProgress.HAT_ID:
		button.name = "HatActButton"
	if not owned:
		button.pressed.connect(_buy_hat.bind(hat_id))
	copy.add_child(button)
	return tile


func _on_store_icon_ready(id: String, texture: Texture2D) -> void:
	if texture != null:
		var icon := find_child("HatIcon_%s" % id, true, false) as TextureRect
		if icon == null:
			icon = find_child("AbilityIcon_%s" % id, true, false) as TextureRect
		if icon != null:
			icon.texture = texture
			icon.modulate = Color.WHITE
	if _upgrades != null:
		_upgrades.notify_icon_ready()


func _fill_cards(gold: int) -> void:
	var stock := CrawlerProgress.shop_stock()
	if stock.is_empty():
		_show_empty("The stall is empty.")
		return
	_show_empty("")
	var grid := _stock_grid("StoreModGrid")
	for catalog_id: String in stock:
		var price := CrawlerProgress.card_price(catalog_id)
		if price <= 0:
			continue
		grid.add_child(_make_mod_tile(catalog_id, price, gold))


func _fill_abilities(gold: int) -> void:
	var stock := CrawlerProgress.ability_stock()
	if stock.is_empty():
		_show_empty("The stall is empty.")
		return
	_show_empty("")
	request_item_icons(stock)
	var grid := _stock_grid("StoreAbilityGrid")
	for catalog_id: String in stock:
		var price := CrawlerProgress.ability_price(catalog_id)
		if price <= 0:
			continue
		grid.add_child(_make_ability_tile(catalog_id, price, gold))


func _make_ability_tile(catalog_id: String, price: int, gold: int) -> Control:
	var tile := _stock_tile("AbilityTile_%s" % catalog_id)
	var copy := tile.get_child(0) as VBoxContainer
	copy.add_child(_stock_icon(
		"AbilityIcon_%s" % catalog_id,
		CrawlerCatalog.texture_for(catalog_id),
		CrawlerCatalog.icon_path(catalog_id).is_empty()
	))
	copy.add_child(_stock_label(
		CrawlerCatalog.title_of(catalog_id).to_upper(),
		15,
		Color(1, 1, 1, 0.94)
	))
	copy.add_child(_stock_label(
		"%dg" % price,
		13,
		GREEN if gold >= price else Color(1, 1, 1, 0.72)
	))
	var body := _stock_label(
		CrawlerCatalog.description_of(catalog_id),
		11,
		Color(1, 1, 1, 0.72),
		true
	)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var button := _stock_button(
		"AbilityAct_%s" % catalog_id,
		"BUY",
		gold >= price
	)
	button.pressed.connect(_buy_card.bind(catalog_id))
	copy.add_child(button)
	return tile


func _make_mod_tile(catalog_id: String, price: int, gold: int) -> Control:
	var tile := _stock_tile("ModTile_%s" % catalog_id)
	var copy := tile.get_child(0) as VBoxContainer
	copy.add_child(_stock_mod_icon(catalog_id))
	var kind := "MOD" if CrawlerCatalog.is_modifier(catalog_id) else "ABILITY"
	copy.add_child(_stock_label(
		"%s  %s" % [kind, CrawlerCatalog.title_of(catalog_id).to_upper()],
		15,
		Color(1, 1, 1, 0.94)
	))
	copy.add_child(_stock_label(
		"%dg" % price,
		13,
		GREEN if gold >= price else Color(1, 1, 1, 0.72)
	))
	var body := _stock_label(
		CrawlerCatalog.description_of(catalog_id),
		11,
		Color(1, 1, 1, 0.72),
		true
	)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var button := _stock_button(
		"ModAct_%s" % catalog_id,
		"BUY",
		gold >= price
	)
	button.pressed.connect(_buy_card.bind(catalog_id))
	copy.add_child(button)
	return tile


func _stock_grid(node_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = STOCK_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 10)
	_list.add_child(grid)
	return grid


func _stock_tile(node_name: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.name = node_name
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = TILE_MIN
	tile.add_theme_stylebox_override(&"panel", _tab_box(BLACK_40, Color(RED_BRIGHT, 0.82), 2))
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override(&"separation", 6)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.add_child(copy)
	return tile


func _stock_mod_icon(catalog_id: String) -> Control:
	var host := Control.new()
	host.name = "ModIconHost_%s" % catalog_id
	host.custom_minimum_size = Vector2(88.0, 88.0)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := _stock_icon(
		"ModIcon_%s" % catalog_id,
		CrawlerCatalog.texture_for(catalog_id),
		CrawlerCatalog.icon_path(catalog_id).is_empty()
	)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(icon)
	if CrawlerCatalog.scope_of(catalog_id) != "ability_specific":
		return host
	var hosts := CrawlerCatalog.host_abilities(catalog_id)
	if hosts.is_empty():
		return host
	var host_tex := CrawlerCatalog.texture_for(hosts[0])
	if host_tex == null:
		return host
	var mark := TextureRect.new()
	mark.name = "ModHostIcon_%s" % catalog_id
	mark.texture = host_tex
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.modulate = Color.WHITE if not CrawlerCatalog.icon_path(hosts[0]).is_empty() \
		else Color(GREEN, 0.95)
	mark.anchor_left = 1.0
	mark.anchor_top = 1.0
	mark.anchor_right = 1.0
	mark.anchor_bottom = 1.0
	mark.offset_left = -36.0
	mark.offset_top = -36.0
	mark.offset_right = -4.0
	mark.offset_bottom = -4.0
	host.add_child(mark)
	return host


func _stock_icon(node_name: String, texture: Texture2D, green := false) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = node_name
	icon.custom_minimum_size = Vector2(88.0, 88.0)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture
	icon.modulate = Color(GREEN, 0.95) if green else Color.WHITE
	return icon


func _stock_label(text: String, font_size: int, colour: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap \
		else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _stock_button(node_name: String, text: String, enabled: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_END
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.disabled = not enabled
	_style_action(button, enabled)
	return button


func _fill_upgrades(_gold: int) -> void:
	_show_empty("")
	if _upgrades != null:
		_upgrades.configure(_player)
		_upgrades.refresh()


func _show_body(upgrades: bool) -> void:
	if _list_host != null:
		_list_host.visible = not upgrades
	if _upgrades != null:
		_upgrades.visible = upgrades


func _add_row(title: String, body: String, action: String, enabled: bool,
		callback: Callable, button_name := "") -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "%s\n%s" % [title, body]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.9))
	row.add_child(label)
	var button := Button.new()
	if not button_name.is_empty():
		button.name = button_name
	button.text = action
	button.custom_minimum_size = Vector2(160.0, 40.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.disabled = not enabled
	button.pressed.connect(callback)
	_style_action(button, enabled)
	row.add_child(button)
	_list.add_child(row)


func _show_empty(text: String) -> void:
	if _empty == null:
		return
	_empty.text = text
	_empty.visible = not text.is_empty()


func _style_action(button: Button, enabled: bool) -> void:
	var accent := GREEN if enabled else Color(RED, 0.55)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if enabled else Color(0.08, 0.02, 0.02, 0.9)
	button.add_theme_font_size_override(&"font_size", 15)
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))
	button.add_theme_stylebox_override(&"normal", _tab_box(fill, Color(accent, 0.95), 2))
	button.add_theme_stylebox_override(&"hover", _tab_box(BLACK, GREEN, 2))
	button.add_theme_stylebox_override(&"pressed", _tab_box(Color(0.0, 0.19, 0.055, 0.90), GREEN, 2))
	button.add_theme_stylebox_override(&"disabled", _tab_box(fill, Color(1, 1, 1, 0.28), 1))
	button.add_theme_stylebox_override(&"focus", _tab_box(fill, GREEN, 2))


func _style_tab(button: Button, selected: bool) -> void:
	var accent := GREEN if selected else RED
	var fill := Color(0.0, 0.15, 0.045, 0.82) if selected else BLACK
	button.add_theme_font_size_override(&"font_size", 13)
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_stylebox_override(&"normal", _tab_box(fill, Color(accent, 0.95), 2 if selected else 1))
	button.add_theme_stylebox_override(&"hover", _tab_box(BLACK, GREEN, 2))
	button.add_theme_stylebox_override(&"pressed", _tab_box(Color(0.0, 0.19, 0.055, 0.90), GREEN, 2))
	button.add_theme_stylebox_override(&"focus", _tab_box(Color.TRANSPARENT, GREEN, 1))


func _tab_box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_content_margin_all(8)
	return box


func _clear_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _buy_ticket() -> void:
	if _player != null:
		_player.buy_crawler_ticket()
	_refresh()


func _buy_quest(quest_id: String) -> void:
	if _player != null:
		_player.buy_crawler_quest(quest_id)
	_refresh()


func _buy_hat(hat_id := CrawlerProgress.HAT_ID) -> void:
	if _player != null:
		_player.buy_crawler_hat(hat_id)
	_refresh()


func _buy_card(catalog_id: String) -> void:
	if _player != null:
		_player.buy_crawler_card(catalog_id)
	_refresh()
