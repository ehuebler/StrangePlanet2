class_name MetaUpgradesPanel
extends VBoxContainer

## Home-screen gem shop for permanent crawler base stats, hats, capes, and
## player unlocks. Spends [CrawlerMeta] gems. Each tab can refund its gem
## spends in one shot.

signal closed
signal gems_changed

enum Tab {
	STATS,
	HATS,
	CAPES,
	PLAYERS,
}

const TAB_LABELS: Array[String] = ["Unlocks", "Hats", "Capes", "Players"]
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)

var opening_tab: Tab = Tab.STATS
var _tab: Tab = Tab.STATS
var _built := false
var _balance: Label
var _tabs: HBoxContainer
var _blurb: Label
var _stat_host: Control
var _hat_host: ScrollContainer
var _cape_host: ScrollContainer
var _player_host: Control
var _rows: GridContainer
var _hat_rows: VBoxContainer
var _cape_rows: VBoxContainer
var _refund_all: Button
var _icons: ItemIcons


func _init() -> void:
	name = "MetaUpgradesPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_tab = opening_tab
	_build()
	_built = true
	CrtType.watch(self)
	refresh()


func show_tab(tab: Tab) -> void:
	_tab = tab
	if _built:
		refresh()


func refresh() -> void:
	if not _built:
		return
	if _balance != null:
		_balance.text = "%d GEMS" % CrawlerMeta.gems()
	_fill_tabs()
	if _blurb != null:
		match _tab:
			Tab.HATS:
				_blurb.text = "SPEND GEMS TO UNLOCK HATS FOR THE CHARACTER CREATOR. REFUND ALL RETURNS THE GEMS."
			Tab.CAPES:
				_blurb.text = "SPEND GEMS TO UNLOCK CAPES FOR THE CHARACTER CREATOR. REFUND ALL RETURNS THE GEMS."
			Tab.PLAYERS:
				_blurb.text = "SPEND GEMS TO UNLOCK PLAYERS. REFUND ALL RETURNS THE GEMS."
			_:
				_blurb.text = "SPEND GEMS TO RAISE BASE STATS IN EVERY RUN. REFUND RETURNS THE GEMS."
	if _stat_host != null:
		_stat_host.visible = _tab == Tab.STATS
	if _hat_host != null:
		_hat_host.visible = _tab == Tab.HATS
	if _cape_host != null:
		_cape_host.visible = _tab == Tab.CAPES
	if _player_host != null:
		_player_host.visible = _tab == Tab.PLAYERS
	_paint_refund_all()
	match _tab:
		Tab.HATS:
			_fill_hats()
		Tab.CAPES:
			_fill_capes()
		Tab.PLAYERS:
			pass
		_:
			_fill_stats()


func hat_ids() -> PackedStringArray:
	return CrawlerMeta.shop_hats()


func cape_ids() -> PackedStringArray:
	return CrawlerMeta.shop_capes()


func _fill_tabs() -> void:
	if _tabs == null:
		return
	for child: Node in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for index in TAB_LABELS.size():
		var button := _button(TAB_LABELS[index], 11)
		button.name = "UplocksTab_%s" % TAB_LABELS[index]
		button.custom_minimum_size = Vector2(96.0, 30.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if index == int(_tab):
			button.add_theme_color_override(&"font_color", GREEN_TEXT)
			button.add_theme_stylebox_override(
				&"normal",
				_style(Color(0.0, 0.2, 0.06, 0.88), GREEN, 2, 8.0)
			)
		var chosen := index
		button.pressed.connect(func() -> void: show_tab(chosen as Tab))
		_tabs.add_child(button)


func _fill_stats() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for stat_id: String in CrawlerMeta.shop_stats():
		_rows.add_child(_make_stat_row(stat_id))


func _fill_hats() -> void:
	if _hat_rows == null:
		return
	for child: Node in _hat_rows.get_children():
		_hat_rows.remove_child(child)
		child.queue_free()
	var ids := CrawlerMeta.shop_hats()
	for item_id: String in ids:
		_hat_rows.add_child(_make_hat_row(item_id))
	if _icons != null:
		_icons.request(Array(ids))


func _fill_capes() -> void:
	if _cape_rows == null:
		return
	for child: Node in _cape_rows.get_children():
		_cape_rows.remove_child(child)
		child.queue_free()
	var ids := CrawlerMeta.shop_capes()
	for item_id: String in ids:
		_cape_rows.add_child(_make_cape_row(item_id))
	if _icons != null:
		_icons.request(Array(ids))


func _build() -> void:
	add_theme_constant_override(&"separation", 6)
	var frame := PanelContainer.new()
	frame.name = "HomeUpgradesFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override(
		&"panel",
		_style(Color(0.0, 0.0, 0.0, 0.42), Color(RED_BRIGHT, 0.92), 2, 8.0)
	)
	var rim := RedGlowPanel.add_to(frame)
	rim.fill_color = Color.TRANSPARENT
	rim.border_color = Color(RED_BRIGHT, 0.92)
	rim.border_width = 2.0
	rim.glow_intensity = 1.25
	rim.glow_spread = 8.0
	rim.glow_layers = 4
	add_child(frame)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override(&"separation", 6)
	frame.add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	_tabs = HBoxContainer.new()
	_tabs.name = "UplocksTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_constant_override(&"separation", 8)
	header.add_child(_tabs)
	_balance = _label("0 GEMS", 12, GREEN_TEXT)
	_balance.name = "UpgradeGemBalance"
	header.add_child(_balance)
	var back := _button("BACK", 11)
	back.name = "UpgradesBack"
	back.custom_minimum_size = Vector2(88.0, 30.0)
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)
	shell.add_child(header)
	shell.add_child(_rule())
	_blurb = _label(
		"SPEND GEMS TO RAISE BASE STATS IN EVERY RUN. REFUND RETURNS THE GEMS.",
		9,
		RED_MUTED
	)
	_blurb.name = "UplocksBlurb"
	_blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_blurb.clip_text = true
	shell.add_child(_blurb)

	_stat_host = MarginContainer.new()
	_stat_host.name = "UpgradeStatScroll"
	_stat_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stat_host.clip_contents = true
	shell.add_child(_stat_host)
	_rows = GridContainer.new()
	_rows.name = "UpgradeStatRows"
	_rows.columns = 2
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"h_separation", 6)
	_rows.add_theme_constant_override(&"v_separation", 4)
	_stat_host.add_child(_rows)

	_hat_host = ScrollContainer.new()
	_hat_host.name = "UplocksHatScroll"
	_hat_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hat_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hat_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(_hat_host)
	_hat_rows = VBoxContainer.new()
	_hat_rows.name = "UplocksHatRows"
	_hat_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hat_rows.add_theme_constant_override(&"separation", 8)
	_hat_host.add_child(_hat_rows)

	_cape_host = ScrollContainer.new()
	_cape_host.name = "UplocksCapeScroll"
	_cape_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cape_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cape_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(_cape_host)
	_cape_rows = VBoxContainer.new()
	_cape_rows.name = "UplocksCapeRows"
	_cape_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cape_rows.add_theme_constant_override(&"separation", 8)
	_cape_host.add_child(_cape_rows)

	_player_host = Control.new()
	_player_host.name = "UplocksPlayerHost"
	_player_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_player_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(_player_host)

	_refund_all = _button("REFUND ALL UPGRADES", 10)
	_refund_all.name = "UpgradeRefundAll"
	_refund_all.custom_minimum_size.y = 28.0
	_refund_all.pressed.connect(_refund_all_current)
	shell.add_child(_refund_all)

	_icons = ItemIcons.new()
	_icons.name = "UplocksHatIcons"
	add_child(_icons)
	_icons.icon_ready.connect(_on_icon_ready)


func _make_stat_row(stat_id: String) -> PanelContainer:
	var rank := CrawlerMeta.rank_of(stat_id)
	var price := CrawlerMeta.upgrade_price(stat_id)
	var refund := CrawlerMeta.refund_value(stat_id)
	var row := PanelContainer.new()
	row.name = "UpgradeRow_%s" % stat_id
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.clip_contents = true
	row.tooltip_text = CrawlerProgress.stat_blurb(stat_id).to_upper()
	row.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(RED, 0.72), 1, 4.0)
	)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 2)
	row.add_child(body)
	var heading := HBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override(&"separation", 4)
	body.add_child(heading)
	var title := _label(CrawlerProgress.stat_title(stat_id), 10, GREEN_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	heading.add_child(title)
	var meta := _label("RANK %d · %d GEMS" % [rank, price], 7, RED_MUTED)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.clip_text = true
	heading.add_child(meta)
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(grow)
	var actions := HBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override(&"separation", 4)
	body.add_child(actions)
	var buy := _button("BUY", 8, 3.0)
	buy.name = "UpgradeBuy_%s" % stat_id
	buy.custom_minimum_size = Vector2(0.0, 20.0)
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.clip_text = true
	buy.disabled = CrawlerMeta.gems() < price
	buy.pressed.connect(func() -> void: _buy(stat_id))
	actions.add_child(buy)
	var give_back := _button("REFUND", 8, 3.0)
	give_back.name = "UpgradeRefund_%s" % stat_id
	give_back.custom_minimum_size = Vector2(0.0, 20.0)
	give_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_back.clip_text = true
	give_back.disabled = rank <= 0
	give_back.pressed.connect(func() -> void: _refund(stat_id))
	actions.add_child(give_back)
	if refund > 0:
		give_back.tooltip_text = "RETURN %d GEMS" % refund
	return row


func _make_hat_row(item_id: String) -> PanelContainer:
	var owned := CrawlerMeta.owns_hat(item_id)
	var price := CrawlerMeta.hat_price(item_id)
	var row := PanelContainer.new()
	row.name = "HatRow_%s" % item_id
	row.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(RED, 0.72), 1, 10.0)
	)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.name = "HatIcon_%s" % item_id
	icon.custom_minimum_size = Vector2(56.0, 56.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = ItemIcons.cached(item_id)
	line.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", 3)
	line.add_child(copy)
	copy.add_child(_label(ItemDB.title(item_id), 15, GREEN_TEXT))
	var blurb := CrawlerProgress.hat_blurb(item_id, owned)
	if blurb.is_empty():
		blurb = ItemDB.description(item_id)
	if owned:
		copy.add_child(_label("%s   //   OWNED" % blurb, 10, RED_MUTED, true))
	elif price <= 0:
		copy.add_child(_label("%s   //   FREE" % blurb, 10, RED_MUTED, true))
	else:
		copy.add_child(_label(
			"%s   //   %d GEMS" % [blurb, price],
			10,
			RED_MUTED,
			true
		))
	var buy := _button("OWNED" if owned else ("FREE" if price <= 0 else "BUY"))
	buy.name = "HatBuy_%s" % item_id
	buy.custom_minimum_size = Vector2(108.0, 40.0)
	buy.disabled = owned or (price > 0 and CrawlerMeta.gems() < price)
	if not owned:
		buy.pressed.connect(func() -> void: _buy_hat(item_id))
	line.add_child(buy)
	return row


func _make_cape_row(item_id: String) -> PanelContainer:
	var owned := CrawlerMeta.owns_cape(item_id)
	var price := CrawlerMeta.cape_price(item_id)
	var row := PanelContainer.new()
	row.name = "CapeRow_%s" % item_id
	row.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(RED, 0.72), 1, 10.0)
	)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	row.add_child(line)
	var icon := TextureRect.new()
	icon.name = "CapeIcon_%s" % item_id
	icon.custom_minimum_size = Vector2(56.0, 56.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = ItemIcons.cached(item_id)
	line.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", 3)
	line.add_child(copy)
	copy.add_child(_label(ItemDB.title(item_id), 15, GREEN_TEXT))
	var blurb := CrawlerProgress.cape_blurb(item_id, owned)
	if blurb.is_empty():
		blurb = ItemDB.description(item_id)
	if owned:
		copy.add_child(_label("%s   //   OWNED" % blurb, 10, RED_MUTED, true))
	elif price <= 0:
		copy.add_child(_label("%s   //   FREE" % blurb, 10, RED_MUTED, true))
	else:
		copy.add_child(_label(
			"%s   //   %d GEMS" % [blurb, price],
			10,
			RED_MUTED,
			true
		))
	var buy := _button("OWNED" if owned else ("FREE" if price <= 0 else "BUY"))
	buy.name = "CapeBuy_%s" % item_id
	buy.custom_minimum_size = Vector2(108.0, 40.0)
	buy.disabled = owned or (price > 0 and CrawlerMeta.gems() < price)
	if not owned:
		buy.pressed.connect(func() -> void: _buy_cape(item_id))
	line.add_child(buy)
	return row


func _buy(stat_id: String) -> void:
	if CrawlerMeta.buy_rank(stat_id):
		gems_changed.emit()
		refresh()


func _refund(stat_id: String) -> void:
	if CrawlerMeta.refund_rank(stat_id):
		gems_changed.emit()
		refresh()


func _paint_refund_all() -> void:
	if _refund_all == null:
		return
	_refund_all.visible = true
	match _tab:
		Tab.HATS:
			_refund_all.text = "REFUND ALL HATS"
			_refund_all.disabled = CrawlerMeta.spent_on_hats() <= 0
		Tab.CAPES:
			_refund_all.text = "REFUND ALL CAPES"
			_refund_all.disabled = CrawlerMeta.spent_on_capes() <= 0
		Tab.PLAYERS:
			_refund_all.text = "REFUND ALL PLAYERS"
			_refund_all.disabled = CrawlerMeta.spent_on_players() <= 0
		_:
			_refund_all.text = "REFUND ALL UPGRADES"
			_refund_all.disabled = CrawlerMeta.spent_on_ranks() <= 0


func _refund_all_current() -> void:
	var returned := 0
	match _tab:
		Tab.HATS:
			returned = CrawlerMeta.refund_all_hats()
		Tab.CAPES:
			returned = CrawlerMeta.refund_all_capes()
		Tab.PLAYERS:
			returned = CrawlerMeta.refund_all_players()
		_:
			returned = CrawlerMeta.refund_all()
	if returned >= 0:
		gems_changed.emit()
		refresh()


func _buy_hat(item_id: String) -> void:
	if CrawlerMeta.unlock_hat(item_id):
		gems_changed.emit()
		refresh()


func _buy_cape(item_id: String) -> void:
	if CrawlerMeta.unlock_cape(item_id):
		gems_changed.emit()
		refresh()


func _on_icon_ready(item_id: String, texture: Texture2D) -> void:
	for prefix: String in ["HatIcon_", "CapeIcon_"]:
		var icon := find_child("%s%s" % [prefix, item_id], true, false) as TextureRect
		if icon != null:
			icon.texture = texture


func _button(text: String, font_size := 12, padding := 6.0) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = true
	button.add_theme_font_size_override(&"font_size", font_size)
	button.add_theme_color_override(&"font_color", RED_TEXT)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_disabled_color", Color(RED_MUTED, 0.36))
	button.add_theme_stylebox_override(&"normal", _style(BLACK_68, Color(RED, 0.94), 1, padding))
	button.add_theme_stylebox_override(&"hover", _style(BLACK_68, GREEN, 2, padding))
	button.add_theme_stylebox_override(&"pressed", _style(Color(0.0, 0.2, 0.06, 0.88), GREEN, 2, padding))
	button.add_theme_stylebox_override(&"disabled", _style(BLACK_42, Color(RED_MUTED, 0.30), 1, padding))
	return button


func _label(text: String, font_size: int, colour: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _rule() -> PanelContainer:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(&"panel", _style(Color(RED, 0.48), RED_BRIGHT, 1, 0.0))
	return rule


func _style(fill: Color, border: Color, border_width: int, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	return box
