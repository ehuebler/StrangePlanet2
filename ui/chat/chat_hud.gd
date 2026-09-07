extends CanvasLayer

## The chat log, the line being typed and who is talking. Add this script as the
## "ChatHud" autoload.
##
## It is an autoload rather than part of a scene because a session outlives the
## scene it started in: the same panel is wanted in the world, over the pause
## card, and on any lobby screen a project adds later. It shows itself whenever
## `NetworkManager.in_multiplayer_session()` is true and hides otherwise, so a
## single-player game never sees it.
##
## Enter opens the line, Enter sends it, Escape abandons it. While the line is
## open the local player's controls are switched off: movement is polled rather
## than event-driven, so a focused field is not enough to stop W walking away
## mid-sentence.

const THEME: Theme = preload("res://ui/themes/main_theme.tres")

## Lines shown at once, and how long the log stays up after the last one.
const VISIBLE_LINES := 7
const LINGER := 12.0
const WIDTH := 520.0
## Clear of the weapon bar along the bottom of the screen.
const BOTTOM_MARGIN := 112.0
const SIDE_MARGIN := 16.0
const FADE_TIME := 0.25
## AuroraSurface.BLEED of each margin is spent on the gap between the panel edge
## and the drawn plate, so these read as 8 less than they say, the same way the
## HUD prompts in player.tscn are set up.
const PAD_SIDE := 20
const PAD_ENDS := 14

var typing := false

var _column: VBoxContainer
var _talkers: Control
var _talkers_label: Label
var _log_plate: Control
var _log_column: VBoxContainer
var _entry: LineEdit
var _linger_left := 0.0
## What the local player's controls were before the field took them.
var _restore_controls := true
var _fade: Tween


func _ready() -> void:
	# The log is readable while the game is paused, so it keeps running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 3
	_build()
	CrtType.watch(self, false)
	visible = false
	ChatManager.message_posted.connect(_on_message_posted)
	ChatManager.history_reset.connect(_refresh_log)
	VoiceChat.speaking_changed.connect(_on_speaking_changed)
	NetworkManager.session_started.connect(_on_session_changed)
	NetworkManager.session_ended.connect(_on_session_changed)
	_on_session_changed()


func _process(delta: float) -> void:
	if typing or not visible:
		return
	if _linger_left > 0.0:
		_linger_left -= delta
		if _linger_left <= 0.0:
			_set_log_shown(false)


## Only consulted while the line is open, and only for the keys that would
## otherwise be taken from under it: `_input` runs before every `_unhandled_input`
## in the tree, which is how Escape closes the field instead of pausing the game.
func _input(event: InputEvent) -> void:
	if not typing:
		return
	if event.is_action_pressed(&"pause"):
		_close()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if typing or not NetworkManager.in_multiplayer_session():
		return
	if event.is_action_pressed(&"chat"):
		_open()
		get_viewport().set_input_as_handled()


func _open() -> void:
	typing = true
	# Talking and typing share the V key; the microphone gives it up.
	VoiceChat.suspended = true
	_entry.text = ""
	_entry.visible = true
	_entry.grab_focus()
	_set_log_shown(true)
	var player := _local_player()
	if player != null:
		_restore_controls = player.controls_enabled
		player.controls_enabled = false


func _close() -> void:
	if not typing:
		return
	typing = false
	VoiceChat.suspended = false
	_entry.release_focus()
	_entry.visible = false
	_linger_left = LINGER
	var player := _local_player()
	if player != null:
		# Back to what it was, not to true: the wardrobe or the pause card may
		# have been holding the controls before chat was opened over it.
		player.controls_enabled = _restore_controls


func _on_submitted(text: String) -> void:
	ChatManager.say(text)
	_close()


func _on_message_posted(_entry_posted: Dictionary) -> void:
	_refresh_log()
	_linger_left = LINGER
	_set_log_shown(true)


func _on_speaking_changed(_peer_id: int, _speaking: bool) -> void:
	var names := VoiceChat.talkers()
	_talkers.visible = not names.is_empty()
	if names.is_empty():
		return
	_talkers_label.text = "talking  %s" % ", ".join(names)


func _on_session_changed() -> void:
	var live := NetworkManager.in_multiplayer_session()
	visible = live
	if live:
		_refresh_log()
		_linger_left = LINGER
		_set_log_shown(true)
		return
	if typing:
		_close()
	_talkers.visible = false


func _refresh_log() -> void:
	for line in _log_column.get_children():
		line.queue_free()
	var entries := ChatManager.history
	for entry: Dictionary in entries.slice(maxi(entries.size() - VISIBLE_LINES, 0)):
		_log_column.add_child(_line(entry))


func _line(entry: Dictionary) -> RichTextLabel:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override(&"normal_font_size", 13)
	# Told its width up front, because a label that fits its content has to know
	# how wide it is to know how tall it is, and one waiting on the container to
	# say gets its last line clipped for a frame or two.
	line.custom_minimum_size.x = WIDTH - 2.0 * float(PAD_SIDE)
	if str(entry.get("kind", ChatManager.SAY)) == ChatManager.SYSTEM:
		line.add_theme_color_override(&"default_color", Color(RedHudTheme.INK, 0.72))
		line.text = str(entry.get("text", ""))
		return line
	line.add_theme_color_override(&"default_color", RedHudTheme.INK)
	line.text = "[color=#%s]%s[/color]  %s" % [
		RedHudTheme.INK.to_html(false),
		str(entry.get("name", "")),
		str(entry.get("text", "")),
	]
	return line


## The plate fades rather than blinking out, since it sits over the world and a
## panel that vanishes between two frames reads as a glitch.
func _set_log_shown(shown: bool) -> void:
	var target := 1.0 if shown else 0.0
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if shown:
		_log_plate.visible = true
	if is_zero_approx(_log_plate.modulate.a - target):
		_log_plate.visible = shown
		return
	_fade = create_tween()
	_fade.tween_property(_log_plate, "modulate:a", target, FADE_TIME)
	if not shown:
		_fade.tween_callback(func() -> void: _log_plate.visible = false)


func _local_player() -> OnlinePlayer:
	for node in get_tree().get_nodes_in_group(&"network_players"):
		var player := node as OnlinePlayer
		if player != null and player.peer_id == multiplayer.get_unique_id():
			return player
	return null


func _build() -> void:
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Anchored to the bottom left and grown upwards, so the log rises off the
	# entry field instead of the field being pushed off the screen.
	_column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_column.grow_horizontal = Control.GROW_DIRECTION_END
	_column.offset_left = SIDE_MARGIN
	_column.offset_bottom = -BOTTOM_MARGIN
	_column.custom_minimum_size = Vector2(WIDTH, 0.0)
	_column.add_theme_constant_override(&"separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.theme = THEME
	add_child(_column)

	_talkers = _plate()
	_talkers.visible = false
	# A name or two, so this plate is as wide as what is on it rather than as wide
	# as the log under it.
	_talkers.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.add_child(_talkers)
	_talkers_label = Label.new()
	RedHudTheme.label(_talkers_label, 11)
	_talkers.get_node(^"Padding").add_child(_talkers_label)

	_log_plate = _plate()
	_column.add_child(_log_plate)
	_log_column = VBoxContainer.new()
	_log_column.add_theme_constant_override(&"separation", 4)
	_log_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_plate.get_node(^"Padding").add_child(_log_column)

	_entry = LineEdit.new()
	_entry.name = "Entry"
	_entry.placeholder_text = "say something"
	_entry.max_length = ChatManager.MAX_LENGTH
	_entry.visible = false
	RedHudTheme.input(_entry, 11)
	_entry.text_submitted.connect(_on_submitted)
	# Losing focus any other way — a menu opening over the top — closes the line
	# rather than leaving a field that swallows keys nobody can see going in.
	_entry.focus_exited.connect(func() -> void:
		if typing:
			_close()
	)
	_column.add_child(_entry)


## A drawn plate with padding inside it, the same one the HUD prompts use.
func _plate() -> PanelContainer:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RedHudTheme.panel(plate)
	var padding := MarginContainer.new()
	padding.name = "Padding"
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [&"margin_left", &"margin_right"]:
		padding.add_theme_constant_override(side, PAD_SIDE)
	for side in [&"margin_top", &"margin_bottom"]:
		padding.add_theme_constant_override(side, PAD_ENDS)
	plate.add_child(padding)
	return plate
