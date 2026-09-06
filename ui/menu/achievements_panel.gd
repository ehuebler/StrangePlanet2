class_name AchievementsPanel
extends VBoxContainer

## Home-screen achievement list. Combat and exploration goals live in
## [JournalDB]; finishing one unlocks gems that [Journal] pays when claimed.

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

var _journal := Journal.new()
var _built := false
var _balance: Label
var _rows: VBoxContainer


func _init() -> void:
	name = "AchievementsPanel"
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
	_journal.load_progress()
	if _balance != null:
		_balance.text = "%d GEMS" % CrawlerMeta.gems()
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for id: String in JournalDB.ids_of_kind(JournalDB.ACHIEVEMENT):
		_rows.add_child(_make_row(id))


func _build() -> void:
	add_theme_constant_override(&"separation", 12)
	var frame := PanelContainer.new()
	frame.name = "HomeAchievementsFrame"
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
	var title := _label("ACHIEVEMENTS", 24, RED_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_balance = _label("0 GEMS", 14, GREEN_TEXT)
	_balance.name = "AchievementGemBalance"
	header.add_child(_balance)
	var back := _button("BACK")
	back.name = "AchievementsBack"
	back.custom_minimum_size = Vector2(110.0, 40.0)
	back.pressed.connect(func() -> void: closed.emit())
	header.add_child(back)
	shell.add_child(header)
	shell.add_child(_rule())
	shell.add_child(_label(
		"FINISH A GOAL, THEN CLAIM ITS GEMS HERE. RESET CLEARS PROGRESS SO THEY CAN FIRE AGAIN.",
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
	_rows.name = "AchievementRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 8)
	scroll.add_child(_rows)

	var reset := _button("RESET ACHIEVEMENTS")
	reset.name = "AchievementReset"
	reset.custom_minimum_size.y = 44.0
	reset.pressed.connect(_reset)
	shell.add_child(reset)


func _make_row(id: String) -> PanelContainer:
	var done := _journal.is_done(id)
	var waiting := _journal.can_claim(id)
	var gems := JournalDB.gems_of(id)
	var needed := JournalDB.kills_of(id)
	var row := PanelContainer.new()
	row.name = "AchievementRow_%s" % id
	row.add_theme_stylebox_override(
		&"panel",
		_style(BLACK_42, Color(GREEN if done else RED, 0.72), 1, 10.0)
	)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override(&"separation", 4)
	row.add_child(copy)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 10)
	copy.add_child(title_row)
	var title := _label(JournalDB.title_of(id), 15, GREEN_TEXT if done else RED_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if waiting:
		var claim := _button("CLAIM")
		claim.name = "AchievementClaim_%s" % id
		claim.custom_minimum_size = Vector2(110.0, 36.0)
		var chosen := id
		claim.pressed.connect(func() -> void: _claim(chosen))
		title_row.add_child(claim)
	else:
		var status := "OPEN"
		if _journal.is_claimed(id):
			status = "CLAIMED"
		elif done:
			status = "COMPLETE"
		elif gems > 0:
			status = "%d GEMS" % gems
		title_row.add_child(_label(status, 12, GREEN_TEXT if done else RED_MUTED))
	copy.add_child(_label(JournalDB.summary_of(id), 11, RED_MUTED, true))
	if needed > 0:
		copy.add_child(_label(
			"KILLS  %d / %d" % [mini(_journal.kills(), needed), needed],
			11,
			GREEN_TEXT if done else RED_TEXT
		))
	return row


func _claim(id: String) -> void:
	if not _journal.claim(id):
		return
	gems_changed.emit()
	refresh()


func _reset() -> void:
	_journal.reset_achievements()
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
