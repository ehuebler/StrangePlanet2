class_name HomeActionButton
extends Button

## Text-only home action. [CrtType] rasters the font and wears the CRT
## material so the shader tints glyphs instead of the atlas.

var _destructive := false


func _ready() -> void:
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	_apply_empty_plate()
	if get_parent() is SubViewport:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_destructive(value: bool) -> void:
	_destructive = value
	var host := CrtType.host_of(self)
	if host != null:
		host.set_destructive(1.0 if _destructive else 0.0)


func crt_host() -> Control:
	var host := CrtType.dress(self, 1.0)
	if host is CrtType:
		(host as CrtType).set_destructive(1.0 if _destructive else 0.0)
	return host


func _apply_empty_plate() -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 26.0
	empty.content_margin_top = 4.0
	empty.content_margin_right = 26.0
	empty.content_margin_bottom = 4.0
	for style: StringName in [
		&"normal", &"hover", &"pressed", &"focus", &"disabled"
	]:
		add_theme_stylebox_override(style, empty)
