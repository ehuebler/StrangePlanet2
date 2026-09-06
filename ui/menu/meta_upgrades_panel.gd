class_name MetaUpgradesPanel
extends VBoxContainer

## Home-screen gem shop for permanent crawler base stats. Spends [CrawlerMeta]
## gems and can refund every purchased rank.

signal closed
signal gems_changed

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)

var _built := false
var _balance: Label
var _rows: VBoxContainer


func _init() -> void:
	name = "MetaUpgradesPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_build()
	_built = true
	refresh()


func refresh() -> void:
	if not _built:
		return
	if _balance != null:
		_balance.text = "%d GEMS" % CrawlerMeta.gems()
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for stat_id: String in CrawlerProgress.STAT_ORDER:
		_rows.add_child(_make_stat_row(stat_id))


func _build() -> void:
	add_theme_constant_override(&"separation", 12)
	var frame := PanelContainer.new()
	frame.name = "HomeUpgradesFrame"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override(
		&"panel",
		_style(Color(0.0, 0.0, 0.0, 0.42), Color(RED_BRIGHT, 0.92), 2, 14.0)
	)
	add_child(frame)

	var shell := VBoxContainer.new()
	shell.add_theme_constant_override(&"separation", 10)
	frame.add_child(shell)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var title := _label("UPGRADES", 24, RED_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_balance = _label("0 GEMS", 14, GREEN_TEXT)
	_balance.name = "UpgradeGemBalance"
	header.add_child(_balance)
	var back := _button("BACK")
	back.name = "UpgradesBack"
	back.custom_minimum_size = Vector2(110.0, 40.0)
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)
	shell.add_child(header)
	shell.add_child(_rule())
	shell.add_child(_label(
		"SPEND GEMS TO RAISE BASE STATS IN EVERY RUN. REFUND RETURNS THE GEMS.",
		11,
		RED_MUTED,
		true
	))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "UpgradeStatRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_rows)

	var refund_all := _button("REFUND ALL UPGRADES")
	refund_all.name = "UpgradeRefundAll"
	refund_all.custom_minimum_size.y = 44.0
	refund_all.pressed.connect(_refund_all)
	shell.add_child(refund_all)


func _make_stat_row(stat_id: String) -> PanelContainer:
	var rank := CrawlerMeta.rank_of(stat_id)
	var price := CrawlerMeta.upgrade_price(stat_id)
	var refund := CrawlerMeta.refund_value(stat_id)
	var row := PanelContainer.new()
	row.name = "UpgradeRow_%s" % stat_id
	row.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(RED, 0.72), 1, 10.0)
	)
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	row.add_child(line)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", 3)
	line.add_child(copy)
	copy.add_child(_label(CrawlerProgress.stat_title(stat_id), 15, GREEN_TEXT))
	copy.add_child(_label(
		"%s   //   RANK %d   //   NEXT %d GEMS" % [
			CrawlerProgress.stat_blurb(stat_id),
			rank,
			price,
		],
		10,
		RED_MUTED,
		true
	))
	var buy := _button("BUY")
	buy.name = "UpgradeBuy_%s" % stat_id
	buy.custom_minimum_size = Vector2(96.0, 40.0)
	buy.disabled = CrawlerMeta.gems() < price
	buy.pressed.connect(func() -> void: _buy(stat_id))
	line.add_child(buy)
	var give_back := _button("REFUND")
	give_back.name = "UpgradeRefund_%s" % stat_id
	give_back.custom_minimum_size = Vector2(108.0, 40.0)
	give_back.disabled = rank <= 0
	give_back.pressed.connect(func() -> void: _refund(stat_id))
	line.add_child(give_back)
	if refund > 0:
		give_back.tooltip_text = "RETURN %d GEMS" % refund
	return row


func _buy(stat_id: String) -> void:
	if CrawlerMeta.buy_rank(stat_id):
		gems_changed.emit()
		refresh()


func _refund(stat_id: String) -> void:
	if CrawlerMeta.refund_rank(stat_id):
		gems_changed.emit()
		refresh()


func _refund_all() -> void:
	if CrawlerMeta.refund_all() >= 0:
		gems_changed.emit()
		refresh()


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(&"font_color", RED_TEXT)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_disabled_color", Color(RED_MUTED, 0.36))
	button.add_theme_stylebox_override(&"normal", _style(BLACK_68, Color(RED, 0.94), 1, 8.0))
	button.add_theme_stylebox_override(&"hover", _style(BLACK_68, GREEN, 2, 8.0))
	button.add_theme_stylebox_override(&"pressed", _style(Color(0.0, 0.2, 0.06, 0.88), GREEN, 2, 8.0))
	button.add_theme_stylebox_override(&"disabled", _style(BLACK_42, Color(RED_MUTED, 0.30), 1, 8.0))
	return button


func _label(text: String, font_size: int, colour: Color, wrap := false) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
