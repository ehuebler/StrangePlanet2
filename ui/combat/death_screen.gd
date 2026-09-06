class_name DeathScreen
extends Control

## Full-screen notice shown to the local player while they are dead: what killed
## them, and the only way back.
##
## Colony deaths keep the world running underneath and offer a respawn. Crawler
## deaths end the run unless a ticket is on the ledger: GAME OVER, a summary,
## and a trip back to the home screen.
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
const TITLE := "YOU DIED"
const GAME_OVER_TITLE := "GAME OVER"
const HOME_LABEL := "HOME"
const RESPAWN_LABEL := "RESPAWN"
const BACKDROP := Color(0.05, 0.005, 0.008, 0.62)
## Used when the host could not name what killed you. Lives here rather than on
## the player so this screen never has to reach back at the thing that opens it.
const DEFAULT_NOTICE := "You died"

var _notice_text := DEFAULT_NOTICE
var _summary_text := ""
var _title_text := TITLE
var _button_text := RESPAWN_LABEL
var _sends_home := false
var _title: Label
var _notice: Label
var _summary: Label
var _button: Button
var _plate: RedGlowPanel
var _shown := 0.0
var _asked := false


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


func present_crawler(cause: String, summary: String, can_respawn: bool) -> void:
	set_notice(cause)
	_summary_text = summary
	_title_text = GAME_OVER_TITLE
	_sends_home = not can_respawn
	_button_text = RESPAWN_LABEL if can_respawn else HOME_LABEL
	_apply_copy()


func notice_text() -> String:
	return _notice_text


func title_text() -> String:
	return _title_text


func summary_text() -> String:
	return _summary_text


func sends_home() -> bool:
	return _sends_home


func respawn_button() -> Button:
	return _button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_apply_copy()


func _process(delta: float) -> void:
	_shown += delta
	modulate.a = clampf(_shown / FADE_IN, 0.0, 1.0)
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
	centre.add_child(_plate)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [&"margin_left", &"margin_right"]:
		pad.add_theme_constant_override(side, 28)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 22)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(pad)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override(&"separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)

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

	var button_lane := CenterContainer.new()
	button_lane.name = "ButtonLane"
	button_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if _plate != null:
		_plate.custom_minimum_size = RUN_PLATE_SIZE if not _summary_text.is_empty() \
				else PLATE_SIZE
	if _button != null:
		_button.text = _button_text
		_button.name = "HomeButton" if _sends_home else "RespawnButton"


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
