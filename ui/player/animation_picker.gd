class_name AnimationPicker
extends Control

## Hold-B overlay: every clip on the local player's AnimationPlayer, clickable.

signal clip_chosen(clip: String)

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const COLUMNS := 3

var _clips: PackedStringArray = PackedStringArray()
var _current := ""
var _filter := ""
var _search: LineEdit
var _grid: GridContainer
var _status: Label


func configure(clips: PackedStringArray, current: String) -> void:
	_clips = clips.duplicate()
	_clips.sort()
	_current = current
	if _grid != null:
		_rebuild()


func set_current(clip: String) -> void:
	_current = clip
	if _status != null:
		_status.text = "Playing  %s" % clip if not clip.is_empty() else "Click a clip"
	_rebuild()


func _ready() -> void:
	name = "AnimationPicker"
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	CrtType.watch(self)
	_rebuild()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.10
	panel.anchor_bottom = 0.90
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0
	RedHudTheme.panel(panel, 14.0, RedHudTheme.BLACK, RedHudTheme.RED_BRIGHT, 2)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Animations"
	RedHudTheme.label(title, 18)
	title.add_theme_color_override("font_color", RedHudTheme.RED_BRIGHT)
	box.add_child(title)

	_status = Label.new()
	_status.text = "Click a clip"
	RedHudTheme.label(_status, 12)
	box.add_child(_status)

	_search = LineEdit.new()
	_search.placeholder_text = "Filter"
	RedHudTheme.input(_search, 13)
	_search.text_changed.connect(_on_filter)
	box.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_grid)


func _on_filter(text: String) -> void:
	_filter = text.strip_edges().to_lower()
	_rebuild()


func _rebuild() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	for clip: String in _clips:
		if not _filter.is_empty() and clip.to_lower().find(_filter) < 0:
			continue
		var button := Button.new()
		button.text = clip
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 36)
		RedHudTheme.button(button, 12, 8.0)
		if clip == _current:
			button.add_theme_stylebox_override(
				&"normal",
				RedHudTheme.style(Color(RedHudTheme.GREEN, 0.92), RedHudTheme.GREEN, 2, 8.0))
		var chosen := clip
		button.pressed.connect(func() -> void: clip_chosen.emit(chosen))
		_grid.add_child(button)
