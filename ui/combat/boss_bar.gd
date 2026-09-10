class_name BossBar
extends Control

## Top-centre boss title and health strip for one arena encounter.

const TITLE := "Bigfoot"
const WIDTH := 360.0
const TOP := 2.0
const HEIGHT := 32.0
const HEALTH_LERP := 10.0
const WARNING_FLASH_HZ := 2.5
const WARNING_ALPHA_MIN := 0.30
const WARNING_TINT_MIN := 0.22

var _root: Control
var _title: Label
var _track: PanelContainer
var _fill: ColorRect
var _display_share := 1.0
var _target_share := 1.0
var _warning_elapsed := 0.0
var _warning_active := false


func _init() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta(&"crt_skip", true)
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = TOP
	offset_bottom = TOP + HEIGHT


func _ready() -> void:
	_build()


func set_title(title: String) -> void:
	if _title == null:
		return
	_title.text = title if not title.is_empty() else TITLE


func set_encounter(alpha: float, health: float, maximum: float, delta: float,
		warning := false) -> void:
	_warning_active = warning
	if warning:
		_warning_elapsed += maxf(delta, 0.0)
		var pulse := sin(_warning_elapsed * TAU * WARNING_FLASH_HZ) * 0.5 + 0.5
		var tint := lerpf(WARNING_TINT_MIN, 1.0, pulse)
		modulate = Color(
			1.0, tint, tint, lerpf(WARNING_ALPHA_MIN, 1.0, pulse))
	else:
		_warning_elapsed = 0.0
		modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	visible = warning or alpha > 0.001
	if not visible:
		return
	var share := clampf(health / maxf(maximum, 0.001), 0.0, 1.0)
	_target_share = share
	var step := clampf(delta * HEALTH_LERP, 0.0, 1.0)
	_display_share = lerpf(_display_share, _target_share, step)
	# Containers own their children's size and would restore a manually shortened
	# ColorRect on the next layout pass. Scale preserves that layout while
	# clipping the red strip from its left edge.
	_fill.scale.x = _display_share


func reset_display() -> void:
	_display_share = 1.0
	_target_share = 1.0
	_warning_elapsed = 0.0
	_warning_active = false
	modulate = Color.WHITE
	if _fill != null:
		_fill.scale.x = 1.0


func warning_active() -> bool:
	return _warning_active


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(WIDTH, 0.0)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_root)
	RedHudTheme.panel(_root)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 8)
	pad.add_theme_constant_override(&"margin_right", 8)
	pad.add_theme_constant_override(&"margin_top", 1)
	pad.add_theme_constant_override(&"margin_bottom", 1)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)
	_root.add_child(pad)

	_title = Label.new()
	_title.text = TITLE
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RedHudTheme.label(_title, 12)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)
	CrtType.watch(_title, true)

	_track = PanelContainer.new()
	_track.custom_minimum_size = Vector2(WIDTH - 16.0, 7.0)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_track)
	RedHudTheme.panel(
		_track, 0.0, RedHudTheme.BLACK, RedHudTheme.RED_BRIGHT, 1
	)

	var track_pad := MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		track_pad.add_theme_constant_override(side, 1)
	track_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track.add_child(track_pad)

	_fill = ColorRect.new()
	_fill.color = RedHudTheme.RED
	_fill.custom_minimum_size = Vector2(0.0, 5.0)
	_fill.pivot_offset = Vector2.ZERO
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_pad.add_child(_fill)
	visible = false
