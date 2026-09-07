class_name CrawlerFieldMenu
extends Control

## Crawler E menu. Only opens inside a city. It is a twelve-tab gold shop:
## hats, Caps for Sale, capes, mods, abilities, upgrades, inventory, locker,
## quests, the black market, the reststop, and Duals. Crawler rolls which
## stalls are open each run; Duals stays open in every city. Closed tabs stay
## visible and read CLOSED.
## The shell uses the same starry sheet as the Tab menu so the store reads
## as the same chrome.

signal closed

enum Tab { HATS, CAPS, CAPES, CARDS, ABILITIES, UPGRADES, INVENTORY, LOCKER, QUESTS, MARKET, RESTSTOP, DUALS }

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const MENU_BACKGROUND: Texture2D = preload("res://assets/runtime/ui/menu_background.png")
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const GREEN := Color("45df68")
const BLACK := Color(0.0, 0.0, 0.0, 0.82)
const BLACK_40 := Color(0.0, 0.0, 0.0, 0.40)
const EDGE := 28.0
const TAB_NAMES := [
	"HATS", "CAPS FOR SALE", "CAPES", "MODS", "ABILITIES", "UPGRADES",
	"INVENTORY", "LOCKER", "QUESTS", "MARKET", "RESTSTOP", "DUALS",
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
var _tab_stamps: Array[Label] = []
var _tab_icons: Array[TextureRect] = []
var _list_host: PanelContainer
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label
var _upgrades: CrawlerStoreUpgradesPage
var _inventory_page: CrawlerStoreInventoryPage
var _locker_page: CrawlerStoreLockerPage
var _icons: ItemIcons
var _cap_pick: PackedStringArray = PackedStringArray()


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
	CrtType.watch(self)
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
		var slot := VBoxContainer.new()
		slot.name = "StoreTab_%s" % _shop_id(index)
		slot.add_theme_constant_override(&"separation", 1)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var icon := TextureRect.new()
		icon.name = "StoreTabIcon_%s" % _shop_id(index)
		icon.custom_minimum_size = Vector2(18, 18)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.visible = false
		slot.add_child(icon)
		var button := Button.new()
		button.name = "StoreTabButton_%s" % _shop_id(index)
		button.text = TAB_NAMES[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 36.0
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var chosen: Tab = index as Tab
		button.pressed.connect(func() -> void: set_tab(chosen))
		slot.add_child(button)
		var stamp := Label.new()
		stamp.name = "StoreTabClosed_%s" % _shop_id(index)
		stamp.text = "CLOSED"
		stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stamp.add_theme_font_size_override(&"font_size", 9)
		stamp.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.42))
		stamp.visible = false
		slot.add_child(stamp)
		_tab_row.add_child(slot)
		_tab_buttons.append(button)
		_tab_stamps.append(stamp)
		_tab_icons.append(icon)

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

	_inventory_page = CrawlerStoreInventoryPage.new()
	_inventory_page.configure(_player)
	_inventory_page.visible = false
	column.add_child(_inventory_page)

	_locker_page = CrawlerStoreLockerPage.new()
	_locker_page.configure(_player)
	_locker_page.visible = false
	column.add_child(_locker_page)

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
		var open := _shop_open(index as Tab)
		_style_tab(_tab_buttons[index], index == int(_tab), open)
		if index < _tab_stamps.size() and _tab_stamps[index] != null:
			_tab_stamps[index].visible = in_city and not open
		if index < _tab_icons.size() and _tab_icons[index] != null:
			var shop_id := _shop_id(index)
			var show_icon := in_city and open and CrawlerShopIcons.shows_sign(shop_id)
			_tab_icons[index].visible = show_icon
			_tab_icons[index].texture = CrawlerShopIcons.texture_for(shop_id) \
					if show_icon else null
	_clear_list()
	if not in_city:
		_hint.text = ""
		_show_body()
		_show_empty("")
		return
	if not _shop_open(_tab):
		_hint.text = "A / D flips stores. This stall is closed this run."
		_show_body()
		_show_empty("Closed.")
		return
	_show_body(_tab == Tab.UPGRADES, _tab == Tab.INVENTORY, _tab == Tab.LOCKER)
	match _tab:
		Tab.HATS:
			_hint.text = "A / D flips stores. Hats bought here stay on this run. Buy another copy to fuse two of the same."
			if progress != null and progress.uses_limited_shop(_city_key()):
				_hint.text = "A / D flips stores. Three hats are in stock. Refresh unsold slots for the same gold as a level-up reroll. Sold slots stay empty."
			_fill_hats(progress, gold)
		Tab.CAPS:
			_hint.text = "A / D flips stores. Caps for Sale fuses two owned hats into one model. One mash per city."
			if progress != null and progress.shops_unlimited:
				_hint.text = "A / D flips stores. Caps for Sale fuses two owned hats into one model, as often as you want."
			elif progress != null and not progress.cap_merge_free(_city_key()):
				_hint.text = "A / D flips stores. This city already mashed a pair. Next city, or rest-stop infinite stores."
			_fill_caps_for_sale(progress, gold)
		Tab.CAPES:
			_hint.text = "A / D flips stores. Capes bought here stay on this run."
			_fill_capes(progress, gold)
		Tab.CARDS:
			_hint.text = "A / D flips stores. Buy mods for the abilities you already own."
			if progress != null and progress.uses_limited_shop(_city_key()):
				_hint.text = "A / D flips stores. Three mods are in stock. Refresh unsold slots for the same gold as a level-up reroll. Sold slots stay empty."
			_fill_cards(gold)
		Tab.ABILITIES:
			_hint.text = "A / D flips stores. Buy another Laser Eyes, Kame, or Nausicaa. Copies share store upgrades."
			if progress != null and progress.uses_limited_shop(_city_key()):
				_hint.text = "A / D flips stores. One ability is in stock. Refresh the unsold slot for the same gold as a level-up reroll. A sold slot stays empty."
			_fill_abilities(gold)
		Tab.UPGRADES:
			_hint.text = "A / D flips stores. Pick an ability or mod, then buy its upgrades."
			if progress != null and progress.uses_limited_shop(_city_key()):
				_hint.text = "A / D flips stores. Pick an ability or mod. In-stock upgrades can be maxed. The rest stay listed as out of stock."
			_fill_upgrades(gold)
		Tab.INVENTORY:
			_hint.text = "A / D flips stores. Drag abilities and mods into the city stash. They stay available in every city this run."
			_fill_inventory()
		Tab.LOCKER:
			_hint.text = "A / D flips stores. Lock one ability and its mods here to take them into a later run."
			_fill_locker()
		Tab.QUESTS:
			_hint.text = "A / D flips stores. A bought quest marks the site on tilde."
			_fill_quests()
		Tab.MARKET:
			_hint.text = "A / D flips stores. Respawn tickets cost gold and gems. Without one, death ends the run."
			_fill_market()
		Tab.RESTSTOP:
			_hint.text = "A / D flips stores. The first refill in this city is free. Later visits cost gold."
			_fill_reststop()
		Tab.DUALS:
			_hint.text = "A / D flips stores. Duals will host test battles."
			_fill_duals()


func _fill_inventory() -> void:
	_show_empty("")
	if _inventory_page != null:
		_inventory_page.configure(_player)
		_inventory_page.refresh()


func _fill_locker() -> void:
	_show_empty("")
	if _locker_page != null:
		_locker_page.configure(_player)
		_locker_page.refresh()


func _fill_duals() -> void:
	if CrawlerRules.coop() and NetworkManager != null \
			and NetworkManager.players.size() >= 2:
		_show_empty("")
		_add_row(
			"CITY DUEL",
			"Start a player battle. Mobs stay out. E ends it for everyone and puts you back.",
			"START",
			true,
			_start_duel,
			"DualsStart"
		)
		return
	_show_empty("Duels are for co-op. Nothing happens here in a solo run.")


func _start_duel() -> void:
	var world := NetworkManager.active_world as GameWorld
	close()
	if world != null:
		world.request_start_duel()


func _fill_reststop() -> void:
	var progress := _player.crawler_progress if _player != null else null
	var gold := progress.gold if progress != null else 0
	var city := _player.crawler_city_key() if _player != null else ""
	_show_empty("")
	_add_rest_row(
		"health",
		"REFILL HEALTH",
		"Restore your vitals. The first refill in this city is free.",
		progress.rest_health_free(city) if progress != null else true,
		progress.rest_health_price_for(city) if progress != null \
			else CrawlerProgress.REST_HEALTH_PRICE,
		_player != null and _player.health() < _player.maximum_health() - 0.001,
		gold,
		_buy_rest_health
	)
	_add_rest_row(
		"ammo",
		"REFILL AMMO",
		"Top up nuke magazines. The first refill in this city is free.",
		progress.rest_ammo_free(city) if progress != null else true,
		progress.rest_ammo_price_for(city) if progress != null \
			else CrawlerProgress.REST_AMMO_PRICE,
		_player != null and _player.crawler_kit != null \
			and _player.crawler_kit.needs_ammo_refill(),
		gold,
		_buy_rest_ammo
	)
	if not CrawlerRules.crawler():
		return
	_add_row(
		"ADD 10,000 GOLD",
		"Put 10,000 gold in your purse.",
		"TAKE",
		true,
		_grant_rest_gold,
		"RestAct_gold"
	)
	var unlimited := progress != null and progress.shops_unlimited
	_add_row(
		"INFINITE STORES",
		"Keep every stall in stock. Nothing sells out or goes empty.",
		"ON" if unlimited else "SET",
		not unlimited,
		_enable_unlimited_shops,
		"RestAct_stores"
	)


func _add_rest_row(
		kind: String,
		title: String,
		body: String,
		free: bool,
		price: int,
		needed: bool,
		gold: int,
		callback: Callable
	) -> void:
	var cost := "FREE" if free else "%dg" % price
	var action := "FULL"
	var enabled := false
	if needed:
		action = "FREE" if free else "BUY"
		enabled = free or gold >= price
	_add_row(
		"%s   %s" % [title, cost],
		body,
		action,
		enabled,
		callback,
		"RestAct_%s" % kind
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
	var city := _city_key()
	var grid: GridContainer
	if progress != null and progress.uses_limited_shop(city):
		_add_shop_refresh("hats", progress)
		grid = _stock_grid("StoreHatGrid")
		var icons := PackedStringArray()
		var slots := progress.shop_slots("hats", city)
		for index in slots.size():
			var raw: Variant = slots[index]
			var hat_id := ""
			var sold := true
			if raw is Dictionary:
				hat_id = str((raw as Dictionary).get("id", ""))
				sold = bool((raw as Dictionary).get("sold", false))
			if sold or hat_id.is_empty():
				grid.add_child(_make_empty_slot_tile("hats", index))
				continue
			icons.append(hat_id)
			grid.add_child(_make_hat_tile(hat_id, progress, gold))
		request_item_icons(icons)
		return
	grid = _stock_grid("StoreHatGrid")
	var stock := CrawlerProgress.hat_stock()
	request_item_icons(stock)
	for hat_id: String in stock:
		grid.add_child(_make_hat_tile(hat_id, progress, gold))


func _make_hat_tile(hat_id: String, progress: CrawlerProgress, gold: int) -> Control:
	var copies := progress.hat_count(hat_id) if progress != null else 0
	var price := CrawlerProgress.hat_price(hat_id)
	var tile := _stock_tile("HatTile_%s" % hat_id)
	var copy := tile.get_child(0) as VBoxContainer
	var cached := ItemIcons.cached(hat_id)
	var icon := _stock_icon("HatIcon_%s" % hat_id, cached, cached == null)
	copy.add_child(icon)
	copy.add_child(_stock_label(ItemDB.title(hat_id).to_upper(), 16, Color(1, 1, 1, 0.94)))
	copy.add_child(_stock_label(
		"OWNED ×%d" % copies if copies > 0 else "%dg" % price,
		13,
		GREEN if copies > 0 or gold >= price else Color(1, 1, 1, 0.72)
	))
	var body := _stock_label(CrawlerProgress.hat_blurb(hat_id, copies > 0), 11, Color(1, 1, 1, 0.72), true)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var button := _stock_button(
		"HatAct_%s" % hat_id,
		"BUY",
		gold >= price
	)
	if hat_id == CrawlerProgress.HAT_ID:
		button.name = "HatActButton"
	button.pressed.connect(_buy_hat.bind(hat_id))
	copy.add_child(button)
	return tile


func _fill_caps_for_sale(progress: CrawlerProgress, gold: int) -> void:
	var hats := progress.owned_hats.duplicate() if progress != null \
		else PackedStringArray()
	var kept := PackedStringArray()
	for uid: String in _cap_pick:
		if hats.has(uid) and not kept.has(uid):
			kept.append(uid)
	_cap_pick = kept
	if hats.is_empty():
		_show_empty("Buy hats at the hat stall, then fuse two of them here.")
		return
	_show_empty("")
	var models: Array = []
	for uid: String in hats:
		var model := progress.hat_model(uid)
		if not model.is_empty() and not models.has(model):
			models.append(model)
	request_item_icons(models)
	var can_mash := progress == null or progress.cap_merge_free(_city_key())
	var grid := _stock_grid("StoreCapGrid")
	for uid: String in hats:
		grid.add_child(_make_cap_tile(uid, progress, can_mash))
	if not can_mash:
		_add_row(
			"FUSION USED",
			"This city already mashed one pair. Visit another city, or turn on infinite stores at the rest stop.",
			"USED",
			false,
			func() -> void: pass,
			"CapMergeUsed"
		)
		return
	if _cap_pick.size() < 2:
		_add_row(
			"PICK TWO HATS",
			"Tap two owned hats. Then choose which model keeps the fused effects.",
			"WAIT",
			false,
			func() -> void: pass,
			"CapMergeWait"
		)
		return
	var keep_a := _cap_pick[0]
	var other_a := _cap_pick[1]
	var price := CrawlerProgress.HAT_MERGE_PRICE
	var can_pay := gold >= price
	_add_cap_merge_row(progress, keep_a, other_a, can_pay, "CapMergeKeepA")
	if progress.hat_model(keep_a) != progress.hat_model(other_a):
		_add_cap_merge_row(progress, other_a, keep_a, can_pay, "CapMergeKeepB")


func _make_cap_tile(
		uid: String, progress: CrawlerProgress, can_mash: bool) -> Control:
	var selected := _cap_pick.has(uid)
	var model := progress.hat_model(uid)
	var tile := _stock_tile("CapTile_%s" % uid)
	if selected:
		tile.add_theme_stylebox_override(
			&"panel", _tab_box(BLACK_40, GREEN, 2)
		)
	var copy := tile.get_child(0) as VBoxContainer
	var cached := ItemIcons.cached(model)
	var icon := _stock_icon("CapIcon_%s" % model, cached, cached == null)
	copy.add_child(icon)
	copy.add_child(_stock_label(
		progress.hat_title(uid).to_upper(), 15, Color(1, 1, 1, 0.94)
	))
	var body := _stock_label(
		progress.hat_description(uid), 11, Color(1, 1, 1, 0.72), true
	)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var button := _stock_button(
		"CapAct_%s" % uid,
		"CHOSEN" if selected else "PICK",
		can_mash
	)
	button.pressed.connect(_toggle_cap_pick.bind(uid))
	copy.add_child(button)
	return tile


func _add_cap_merge_row(
		progress: CrawlerProgress,
		keep_uid: String,
		other_uid: String,
		can_pay: bool,
		button_name: String
	) -> void:
	var preview := progress.preview_hat_merge(keep_uid, other_uid)
	if preview.is_empty():
		return
	_add_row(
		"%s   %dg" % [
			str(preview.get("title", "")).to_upper(),
			CrawlerProgress.HAT_MERGE_PRICE,
		],
		str(preview.get("description", "")),
		"MERGE INTO THIS",
		can_pay,
		_merge_caps.bind(keep_uid, other_uid),
		button_name
	)


func _toggle_cap_pick(uid: String) -> void:
	var listed := PackedStringArray()
	for held: String in _cap_pick:
		if held != uid:
			listed.append(held)
	if _cap_pick.has(uid):
		_cap_pick = listed
	elif listed.size() < 2:
		listed.append(uid)
		_cap_pick = listed
	else:
		listed.remove_at(0)
		listed.append(uid)
		_cap_pick = listed
	_redraw_caps()


func _merge_caps(keep_uid: String, other_uid: String) -> void:
	if _player != null:
		_player.merge_crawler_hats(keep_uid, other_uid)
	_cap_pick = PackedStringArray()
	_redraw_caps()


func _redraw_caps() -> void:
	var progress := _player.crawler_progress if _player != null else null
	var gold := progress.gold if progress != null else 0
	if _gold != null:
		_gold.text = "GOLD  %d    GEMS  %d" % [gold, CrawlerMeta.gems()]
	_clear_list()
	_fill_caps_for_sale(progress, gold)


func _fill_capes(progress: CrawlerProgress, gold: int) -> void:
	_show_empty("")
	var stock := CrawlerProgress.cape_stock()
	request_item_icons(stock)
	var grid := _stock_grid("StoreCapeGrid")
	for cape_id: String in stock:
		grid.add_child(_make_cape_tile(cape_id, progress, gold))


func _make_cape_tile(cape_id: String, progress: CrawlerProgress, gold: int) -> Control:
	var owned := progress != null and progress.owns_cape(cape_id)
	var price := CrawlerProgress.cape_price(cape_id)
	var tile := _stock_tile("CapeTile_%s" % cape_id)
	var copy := tile.get_child(0) as VBoxContainer
	var cached := ItemIcons.cached(cape_id)
	var icon := _stock_icon("CapeIcon_%s" % cape_id, cached, cached == null)
	copy.add_child(icon)
	copy.add_child(_stock_label(ItemDB.title(cape_id).to_upper(), 16, Color(1, 1, 1, 0.94)))
	copy.add_child(_stock_label(
		"OWNED" if owned else "%dg" % price,
		13,
		GREEN if owned or gold >= price else Color(1, 1, 1, 0.72)
	))
	var body := _stock_label(CrawlerProgress.cape_blurb(cape_id, owned), 11, Color(1, 1, 1, 0.72), true)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(body)
	var button := _stock_button(
		"CapeAct_%s" % cape_id,
		"SOLD" if owned else "BUY",
		not owned and gold >= price
	)
	if cape_id == CrawlerProgress.CAPE_ID:
		button.name = "CapeActButton"
	if not owned:
		button.pressed.connect(_buy_cape.bind(cape_id))
	copy.add_child(button)
	return tile


func _on_store_icon_ready(id: String, texture: Texture2D) -> void:
	if texture != null:
		var icon := find_child("HatIcon_%s" % id, true, false) as TextureRect
		if icon == null:
			icon = find_child("CapeIcon_%s" % id, true, false) as TextureRect
		if icon == null:
			icon = find_child("AbilityIcon_%s" % id, true, false) as TextureRect
		if icon != null:
			icon.texture = texture
			icon.modulate = Color.WHITE
		for node: Node in find_children("CapIcon_%s" % id, "TextureRect", true, false):
			var cap := node as TextureRect
			cap.texture = texture
			cap.modulate = Color.WHITE
	if _upgrades != null:
		_upgrades.notify_icon_ready()
	if _inventory_page != null:
		_inventory_page.notify_icon_ready()
	if _locker_page != null:
		_locker_page.notify_icon_ready()


func _fill_cards(gold: int) -> void:
	var progress := _player.crawler_progress if _player != null else null
	var city := _city_key()
	var grid: GridContainer
	if progress != null and progress.uses_limited_shop(city):
		_show_empty("")
		_add_shop_refresh("mods", progress)
		grid = _stock_grid("StoreModGrid")
		var slots := progress.shop_slots("mods", city)
		for index in slots.size():
			var raw: Variant = slots[index]
			var catalog_id := ""
			var sold := true
			if raw is Dictionary:
				catalog_id = str((raw as Dictionary).get("id", ""))
				sold = bool((raw as Dictionary).get("sold", false))
			var price := CrawlerProgress.card_price(catalog_id)
			if sold or catalog_id.is_empty() or price <= 0:
				grid.add_child(_make_empty_slot_tile("mods", index))
				continue
			grid.add_child(_make_mod_tile(catalog_id, price, gold))
		return
	var stock := CrawlerProgress.shop_stock()
	if stock.is_empty():
		_show_empty("The stall is empty.")
		return
	_show_empty("")
	grid = _stock_grid("StoreModGrid")
	for catalog_id: String in stock:
		var price := CrawlerProgress.card_price(catalog_id)
		if price <= 0:
			continue
		grid.add_child(_make_mod_tile(catalog_id, price, gold))


func _fill_abilities(gold: int) -> void:
	var progress := _player.crawler_progress if _player != null else null
	var city := _city_key()
	var grid: GridContainer
	if progress != null and progress.uses_limited_shop(city):
		_show_empty("")
		_add_shop_refresh("abilities", progress)
		var icons := PackedStringArray()
		grid = _stock_grid("StoreAbilityGrid")
		var slots := progress.shop_slots("abilities", city)
		for index in slots.size():
			var raw: Variant = slots[index]
			var catalog_id := ""
			var sold := true
			if raw is Dictionary:
				catalog_id = str((raw as Dictionary).get("id", ""))
				sold = bool((raw as Dictionary).get("sold", false))
			var price := CrawlerProgress.ability_price(catalog_id)
			if sold or catalog_id.is_empty() or price <= 0:
				grid.add_child(_make_empty_slot_tile("abilities", index))
				continue
			icons.append(catalog_id)
			grid.add_child(_make_ability_tile(catalog_id, price, gold))
		request_item_icons(icons)
		return
	var stock := CrawlerProgress.ability_stock()
	if stock.is_empty():
		_show_empty("The stall is empty.")
		return
	_show_empty("")
	request_item_icons(stock)
	grid = _stock_grid("StoreAbilityGrid")
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
	var ability_marks := _stock_type_marks(catalog_id)
	if ability_marks != null:
		copy.add_child(ability_marks)
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
	var column := VBoxContainer.new()
	column.name = "ModIconHost_%s" % catalog_id
	column.add_theme_constant_override(&"separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_stock_icon(
		"ModIcon_%s" % catalog_id,
		CrawlerCatalog.texture_for(catalog_id),
		CrawlerCatalog.icon_path(catalog_id).is_empty()
	))
	var marks := _stock_type_marks(catalog_id)
	if marks != null:
		column.add_child(marks)
	return column


func _stock_type_marks(catalog_id: String) -> Control:
	var types := CrawlerCatalog.display_types(catalog_id)
	if types.is_empty():
		return null
	return CrawlerTypeMarks.make_row("TypeMarks_%s" % catalog_id, types, 22.0)


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


func _show_body(upgrades := false, inventory := false, locker := false) -> void:
	if _list_host != null:
		_list_host.visible = not upgrades and not inventory and not locker
	if _upgrades != null:
		_upgrades.visible = upgrades
	if _inventory_page != null:
		_inventory_page.visible = inventory
	if _locker_page != null:
		_locker_page.visible = locker


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


func _shop_id(index: int) -> String:
	if index < 0 or index >= CrawlerProgress.SHOP_IDS.size():
		return ""
	return CrawlerProgress.SHOP_IDS[index]


func _shop_open(tab: Tab) -> bool:
	if not CrawlerRules.crawler():
		return true
	if _player == null or _player.crawler_progress == null:
		return true
	return _player.crawler_progress.shop_open(_shop_id(int(tab)), _player.crawler_city_key())


func _style_tab(button: Button, selected: bool, open := true) -> void:
	var accent := GREEN if selected else RED
	if not open:
		accent = Color(0.62, 0.62, 0.62, 0.78) if selected \
			else Color(0.48, 0.48, 0.48, 0.70)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if selected and open else BLACK
	if not open:
		fill = Color(0.10, 0.10, 0.10, 0.78)
	button.add_theme_font_size_override(&"font_size", 13)
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN if open else accent)
	button.add_theme_color_override(&"font_pressed_color", GREEN if open else accent)
	button.add_theme_color_override(&"font_focus_color", accent)
	button.add_theme_stylebox_override(&"normal", _tab_box(fill, Color(accent, 0.95), 2 if selected else 1))
	button.add_theme_stylebox_override(&"hover", _tab_box(BLACK, GREEN if open else accent, 2))
	button.add_theme_stylebox_override(&"pressed", _tab_box(Color(0.0, 0.19, 0.055, 0.90) if open else fill, GREEN if open else accent, 2))
	button.add_theme_stylebox_override(&"focus", _tab_box(Color.TRANSPARENT, GREEN if open else accent, 1))


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


func _buy_rest_health() -> void:
	if _player != null:
		_player.buy_crawler_rest_health()
	_refresh()


func _buy_rest_ammo() -> void:
	if _player != null:
		_player.buy_crawler_rest_ammo()
	_refresh()


func _grant_rest_gold() -> void:
	if _player != null:
		_player.grant_crawler_rest_gold()
	_refresh()


func _enable_unlimited_shops() -> void:
	if _player != null:
		_player.enable_crawler_unlimited_shops()
	_refresh()


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


func _buy_cape(cape_id := CrawlerProgress.CAPE_ID) -> void:
	if _player != null:
		_player.buy_crawler_cape(cape_id)
	_refresh()


func _buy_card(catalog_id: String) -> void:
	if _player != null:
		_player.buy_crawler_card(catalog_id)
	_refresh()


func _refresh_shop(kind: String) -> void:
	if _player != null:
		_player.refresh_crawler_shop(kind)
	_refresh()


func _city_key() -> String:
	return _player.crawler_city_key() if _player != null else ""


func _add_shop_refresh(kind: String, progress: CrawlerProgress) -> void:
	if progress == null:
		return
	var price := progress.reroll_price()
	_add_row(
		"REFRESH STOCK",
		"Reroll unsold slots. Sold slots stay empty.",
		"REFRESH  %dg" % price,
		progress.shop_can_refresh(kind, _city_key()),
		_refresh_shop.bind(kind),
		"StoreRefresh_%s" % kind
	)


func _make_empty_slot_tile(kind: String, index: int) -> Control:
	var tile := _stock_tile("SoldSlot_%s_%d" % [kind, index])
	tile.modulate = Color(1, 1, 1, 0.38)
	var copy := tile.get_child(0) as VBoxContainer
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy.add_child(filler)
	return tile
