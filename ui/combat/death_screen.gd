class_name DeathScreen
extends Control

## Full-screen notice shown to the local player while they are dead: what killed
## them, and the only way back.
##
## Colony deaths keep the world running underneath and offer a respawn. Crawler
## deaths end the run unless a ticket is on the ledger: GAME OVER, a summary,
## and a trip back to the home screen. In co-op a living teammate leaves the
## fallen player DOWNED — hold E to get them up — until the last body drops.
##
## The world keeps running underneath — in company it has to, and alone a frozen
## ragdoll reads as a crash — so this is an overlay over live play rather than a
## pause screen. It is the one piece of HUD that takes the mouse.

signal respawn_requested
signal home_requested

## Long enough to read as a beat rather than a cut, and short enough that it is
## over before anyone has finished reacting to dying.
const FADE_IN := 0.55
## The button is dead for this long. Whoever died was almost certainly holding
## down fire when it happened, and a respawn spent on that click is a respawn
## nobody asked for and a death notice nobody read.
const ARM_DELAY := 0.9
const PLATE_SIZE := Vector2(520.0, 210.0)
const RUN_PLATE_SIZE := Vector2(560.0, 360.0)
const RECAP_PLATE_SIZE := Vector2(620.0, 560.0)
const VIEW_MARGIN := 28.0
const PAD_X := 28
const PAD_Y := 22
const COL_SEP := 10
const RECAP_SEP := 6
const MIN_RECAP_SCROLL := 72.0
const XP_FILL_TIME := 1.65
const TITLE := "YOU DIED"
const GAME_OVER_TITLE := "GAME OVER"
const DOWNED_TITLE := "DOWNED"
const HOME_LABEL := "HOME"
const RESPAWN_LABEL := "RESPAWN"
const WAITING_COPY := "A teammate can hold E to revive you."
const BACKDROP := Color(0.05, 0.005, 0.008, 0.62)
## Used when the host could not name what killed you. Lives here rather than on
## the player so this screen never has to reach back at the thing that opens it.
const DEFAULT_NOTICE := "You died"

var _notice_text := DEFAULT_NOTICE
var _summary_text := ""
var _title_text := TITLE
var _button_text := RESPAWN_LABEL
var _sends_home := false
var _hide_button := false
var _downed := false
var _recap := {}
var _title: Label
var _notice: Label
var _summary: Label
var _button: Button
var _plate: RedGlowPanel
var _column: VBoxContainer
var _recap_scroll: ScrollContainer
var _recap_host: VBoxContainer
var _xp_label: Label
var _xp_bar: ProgressBar
var _xp_flash: ColorRect
var _shown := 0.0
var _asked := false
var _xp_shown := 0.0
var _xp_from := 0.0
var _xp_to := 0.0
var _xp_age := 0.0
var _xp_done := true


func _init() -> void:
	name = "DeathScreen"
	# Nothing here is paused by the world, and the button has to answer while a
	# single-player session is frozen behind a menu that cannot be opened.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 0.0


## Set before the screen enters the tree, or at any point after it.
func set_notice(text: String) -> void:
	_notice_text = text if not text.is_empty() else DEFAULT_NOTICE
	if _notice != null:
		_notice.text = _notice_text


func present_crawler(
		cause: String,
		summary: String,
		can_respawn: bool,
		recap: Dictionary = {}
	) -> void:
	set_notice(cause)
	_summary_text = summary
	_title_text = GAME_OVER_TITLE
	_sends_home = not can_respawn
	_hide_button = false
	_downed = false
	_asked = false
	_button_text = RESPAWN_LABEL if can_respawn else HOME_LABEL
	_recap = recap.duplicate(true)
	_apply_copy()
	_begin_xp_fill()


func present_downed(cause: String, can_respawn: bool) -> void:
	set_notice(cause)
	_summary_text = WAITING_COPY
	_title_text = DOWNED_TITLE
	_sends_home = false
	_downed = true
	_hide_button = not can_respawn
	_asked = false
	_button_text = RESPAWN_LABEL
	_recap = {}
	_apply_copy()


func notice_text() -> String:
	return _notice_text


func title_text() -> String:
	return _title_text


func summary_text() -> String:
	return _summary_text


func sends_home() -> bool:
	return _sends_home


func is_downed() -> bool:
	return _downed


func recap() -> Dictionary:
	return _recap.duplicate(true)


func finish_recap() -> void:
	if _xp_to <= _xp_from and _recap.is_empty():
		return
	_xp_shown = _xp_to
	_xp_done = true
	_paint_xp(true)


func respawn_button() -> Button:
	return _button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_apply_copy()
	CrtType.watch(self)
	resized.connect(_fit_plate)


func _process(delta: float) -> void:
	_shown += delta
	modulate.a = clampf(_shown / FADE_IN, 0.0, 1.0)
	if not _xp_done:
		_xp_age += maxf(delta, 0.0)
		var t := clampf(_xp_age / XP_FILL_TIME, 0.0, 1.0)
		var bounce := 1.0 - pow(1.0 - t, 3.0)
		bounce += 0.045 * sin(t * PI * 3.0) * (1.0 - t)
		_xp_shown = lerpf(_xp_from, _xp_to, clampf(bounce, 0.0, 1.02))
		if t >= 1.0:
			_xp_shown = _xp_to
			_xp_done = true
		_paint_xp(t >= 1.0)
	if _shown <= FADE_IN + 0.35:
		_fit_plate()
	if _asked or _button == null or not _button.disabled:
		return
	if _shown >= ARM_DELAY:
		_button.disabled = false
		_button.grab_focus()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_plate = RedGlowPanel.new()
	_plate.name = "Plate"
	_plate.custom_minimum_size = PLATE_SIZE
	_plate.fill_color = Color(0.0, 0.0, 0.0, 0.82)
	_plate.border_color = Color(RedHudTheme.RED_BRIGHT, 0.98)
	_plate.border_width = 2.0
	_plate.glow_intensity = 1.6
	_plate.glow_spread = 14.0
	_plate.glow_layers = 5
	_plate.mouse_behavior = RedGlowPanel.MouseBehavior.STOP
	_plate.clip_contents = false
	centre.add_child(_plate)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right"]:
		pad.add_theme_constant_override(side, PAD_X)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, PAD_Y)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(pad)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override(&"separation", COL_SEP)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(_column)
	var column := _column

	_title = Label.new()
	_title.name = "Title"
	_title.text = _title_text
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 44)
	_title.add_theme_color_override(&"font_color", RedHudTheme.RED)
	_title.add_theme_color_override(
		&"font_outline_color", Color(0.04, 0.0, 0.0, 0.98))
	_title.add_theme_constant_override(&"outline_size", 5)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	_notice = Label.new()
	_notice.name = "Notice"
	_notice.text = _notice_text
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_theme_font_size_override(&"font_size", 19)
	_notice.add_theme_color_override(&"font_color", Color(1.0, 0.63, 0.66))
	_notice.add_theme_color_override(
		&"font_outline_color", Color(0.04, 0.0, 0.0, 0.98))
	_notice.add_theme_constant_override(&"outline_size", 3)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_notice)

	_summary = Label.new()
	_summary.name = "Summary"
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override(&"font_size", 17)
	_summary.add_theme_color_override(&"font_color", Color(1.0, 0.82, 0.84))
	_summary.add_theme_color_override(
		&"font_outline_color", Color(0.04, 0.0, 0.0, 0.98))
	_summary.add_theme_constant_override(&"outline_size", 3)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_summary)

	_recap_scroll = ScrollContainer.new()
	_recap_scroll.name = "RunRecapScroll"
	_recap_scroll.visible = false
	_recap_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recap_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_recap_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recap_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recap_scroll.size_flags_stretch_ratio = 1.0
	_recap_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_recap_scroll)

	_recap_host = VBoxContainer.new()
	_recap_host.name = "RunRecap"
	_recap_host.visible = false
	_recap_host.add_theme_constant_override(&"separation", RECAP_SEP)
	_recap_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recap_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap_scroll.add_child(_recap_host)

	var button_lane := CenterContainer.new()
	button_lane.name = "ButtonLane"
	button_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_lane.custom_minimum_size = Vector2(220.0, 52.0)
	button_lane.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button_lane.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_child(button_lane)

	_button = Button.new()
	_button.name = "RespawnButton"
	_button.text = _button_text
	_button.custom_minimum_size = Vector2(200.0, 46.0)
	_button.focus_mode = Control.FOCUS_ALL
	_button.disabled = true
	RedHudTheme.button(_button, 17, 8.0)
	_button.pressed.connect(_on_respawn_pressed)
	button_lane.add_child(_button)


func _apply_copy() -> void:
	if _title != null:
		_title.text = _title_text
	if _notice != null:
		_notice.text = _notice_text
	if _summary != null:
		_summary.text = _summary_text
		_summary.visible = not _summary_text.is_empty()
	_fill_recap()
	_fit_plate()
	if is_inside_tree():
		call_deferred(&"_fit_plate")
	if _button != null:
		_button.text = _button_text
		_button.name = "HomeButton" if _sends_home else "RespawnButton"
		_button.visible = not _hide_button
		var lane := _button.get_parent() as Control
		if lane != null:
			lane.visible = not _hide_button
		if not _hide_button and _shown >= ARM_DELAY:
			_button.disabled = _asked


func _fill_recap() -> void:
	if _recap_host == null:
		return
	for child: Node in _recap_host.get_children():
		_recap_host.remove_child(child)
		child.queue_free()
	_xp_label = null
	_xp_bar = null
	_xp_flash = null
	if _recap.is_empty():
		_recap_host.visible = false
		if _recap_scroll != null:
			_recap_scroll.visible = false
		return
	_recap_host.visible = true
	if _recap_scroll != null:
		_recap_scroll.visible = true
	var achievements: Array = _recap.get("achievements", [])
	if not achievements.is_empty():
		_recap_host.add_child(_recap_heading("ACHIEVEMENTS"))
		for row_variant: Variant in achievements:
			if typeof(row_variant) != TYPE_DICTIONARY:
				continue
			var row := row_variant as Dictionary
			var id := str(row.get("id", ""))
			var block := VBoxContainer.new()
			block.name = "RunAchievement_%s" % id
			block.add_theme_constant_override(&"separation", 2)
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var title := _recap_line(str(row.get("title", id)), 16, Color(1.0, 0.86, 0.55))
			title.name = "RunAchievementTitle_%s" % id
			block.add_child(title)
			var rewards: Variant = row.get("rewards", PackedStringArray())
			if rewards is PackedStringArray or rewards is Array:
				for reward: Variant in rewards:
					var line := _recap_line("+ %s" % str(reward), 14, Color("45df68"))
					line.name = "RunReward_%s" % id
					block.add_child(line)
			_recap_host.add_child(block)
	var score: Dictionary = _recap.get("score", {})
	var score_lines: Variant = score.get("lines", PackedStringArray())
	_recap_host.add_child(_recap_heading("GLOBAL XP"))
	if score_lines is PackedStringArray or score_lines is Array:
		for line_variant: Variant in score_lines:
			_recap_host.add_child(_recap_line(str(line_variant), 13, Color(1.0, 0.82, 0.84)))
	_xp_label = _recap_line("", 15, Color("ffd45a"))
	_xp_label.name = "RunXpLabel"
	_recap_host.add_child(_xp_label)
	var bar_host := Control.new()
	bar_host.name = "RunXpBarHost"
	bar_host.custom_minimum_size = Vector2(0.0, 22.0)
	bar_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recap_host.add_child(bar_host)
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "RunXpBar"
	_xp_bar.show_percentage = false
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 1.0
	_xp_bar.value = 0.0
	_xp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ffd45a")
	fill.set_corner_radius_all(0)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0.12, 0.02, 0.03, 0.92)
	empty.border_color = Color(RedHudTheme.RED_BRIGHT, 0.85)
	empty.set_border_width_all(1)
	empty.set_corner_radius_all(0)
	_xp_bar.add_theme_stylebox_override(&"fill", fill)
	_xp_bar.add_theme_stylebox_override(&"background", empty)
	bar_host.add_child(_xp_bar)
	_xp_flash = ColorRect.new()
	_xp_flash.name = "RunXpFlash"
	_xp_flash.color = Color(1.0, 0.92, 0.45, 0.0)
	_xp_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_host.add_child(_xp_flash)
	var levels: Array = _recap.get("levels", [])
	for level_variant: Variant in levels:
		if typeof(level_variant) != TYPE_DICTIONARY:
			continue
		var level_row := level_variant as Dictionary
		var level := int(level_row.get("level", 0))
		var title := str(level_row.get("title", ""))
		var copy := "LEVEL %d" % level
		if bool(level_row.get("title_changed", false)) and not title.is_empty():
			copy += "  //  %s" % title.to_upper()
		var level_line := _recap_line(copy, 14, Color("45df68"))
		level_line.name = "RunLevel_%d" % level
		_recap_host.add_child(level_line)
	_begin_xp_fill()


func _fit_plate() -> void:
	if _plate == null:
		return
	var view := size
	if view.x < 2.0 or view.y < 2.0:
		view = get_viewport_rect().size if is_inside_tree() else Vector2(1280.0, 720.0)
	if view.x < 2.0 or view.y < 2.0:
		view = Vector2(1280.0, 720.0)
	var glow := _plate.glow_spread
	var inset := VIEW_MARGIN + glow
	var max_w := minf(RECAP_PLATE_SIZE.x, maxf(view.x - inset * 2.0, 320.0))
	var max_h := maxf(view.y - inset * 2.0, 240.0)
	var inner_w := maxf(max_w - float(PAD_X * 2), 160.0)
	if _notice != null:
		_notice.custom_minimum_size.x = inner_w
	if _summary != null:
		_summary.custom_minimum_size.x = inner_w
	var recap_open := _recap_host != null and _recap_host.visible
	if _recap_scroll != null:
		_recap_scroll.visible = recap_open
	if _column != null:
		_column.alignment = (
			BoxContainer.ALIGNMENT_BEGIN if recap_open
			else BoxContainer.ALIGNMENT_CENTER
		)
	var chrome := float(PAD_Y * 2)
	var button_h := 0.0
	var rows := 0
	if _column != null:
		for child: Node in _column.get_children():
			var row := child as Control
			if row == null or not row.visible:
				continue
			rows += 1
			if row == _recap_scroll:
				continue
			var h := _row_height(row)
			if row.name == "ButtonLane":
				button_h = h
			else:
				chrome += h
	chrome += float(COL_SEP * maxi(rows - 1, 0))
	if button_h <= 0.0:
		button_h = 52.0
	if not recap_open:
		var wanted := RUN_PLATE_SIZE if not _summary_text.is_empty() else PLATE_SIZE
		var h := minf(maxf(wanted.y, chrome + button_h), max_h)
		_plate.custom_minimum_size = Vector2(minf(wanted.x, max_w), h)
		if _recap_scroll != null:
			_recap_scroll.custom_minimum_size = Vector2.ZERO
			_recap_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return
	var plate_h := minf(RECAP_PLATE_SIZE.y, max_h)
	var leftover := maxf(plate_h - chrome - button_h, 0.0)
	if leftover < MIN_RECAP_SCROLL and chrome + button_h + MIN_RECAP_SCROLL <= max_h:
		leftover = MIN_RECAP_SCROLL
		plate_h = chrome + leftover + button_h
	if _recap_scroll != null:
		_recap_scroll.custom_minimum_size = Vector2(0.0, leftover)
		_recap_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plate.custom_minimum_size = Vector2(max_w, minf(chrome + leftover + button_h, max_h))


func _row_height(row: Control) -> float:
	if row == null:
		return 0.0
	var host := CrtType.host_of(row)
	if host != null:
		return maxf(host.get_combined_minimum_size().y, host.size.y)
	return maxf(row.get_combined_minimum_size().y, row.size.y)


func _begin_xp_fill() -> void:
	var before: Dictionary = _recap.get("before", {})
	var after: Dictionary = _recap.get("after", {})
	_xp_from = float(before.get("xp", 0))
	_xp_to = float(after.get("xp", _xp_from))
	_xp_shown = _xp_from
	_xp_age = 0.0
	_xp_done = _xp_to <= _xp_from + 0.001
	_paint_xp(_xp_done)


func _paint_xp(finished: bool) -> void:
	if _xp_label == null or _xp_bar == null:
		return
	var level := CrawlerMeta.level_at_xp(int(round(_xp_shown)))
	var into := CrawlerMeta.remainder_at_xp(int(round(_xp_shown)))
	var need := CrawlerMeta.xp_needed(level)
	var title := CrawlerMeta.title_for(level)
	var gained := int(round(_xp_to - _xp_from))
	_xp_label.text = "LV %d  %s    %d / %d" % [level, title.to_upper(), into, need]
	if gained > 0:
		_xp_label.text += "    +%d XP" % gained
	_xp_bar.max_value = 1.0
	_xp_bar.value = 0.0 if need <= 0 else float(into) / float(need)
	if _xp_flash != null:
		var pulse := 0.0
		if not finished:
			pulse = 0.22 + 0.18 * absf(sin(_xp_age * 14.0))
		_xp_flash.color = Color(1.0, 0.92, 0.45, pulse)


func _recap_heading(text: String) -> Label:
	return _recap_line(text, 13, Color(1.0, 0.63, 0.66))


func _recap_line(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _on_respawn_pressed() -> void:
	if _asked:
		return
	# One press. The world answers over the network, so the button has to stop
	# asking rather than wait to be told that it worked.
	_asked = true
	if _button != null:
		_button.disabled = true
	if _sends_home:
		home_requested.emit()
	else:
		respawn_requested.emit()
