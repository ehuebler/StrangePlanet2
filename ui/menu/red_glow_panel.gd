@tool
class_name RedGlowPanel
extends Control

## A square-cornered black pane with a layered red rim.
##
## Use it directly as a responsive Control, or place it behind another Control:
##
##     var surface := RedGlowPanel.add_to(button)
##     surface.glow_intensity = 1.4
##
## Fill stays a CanvasItem rect so the pane does not tear under its contents.
## The rim and halo go through [constant CRT] so menu frames share the same
## glitch, scanlines, and chromatic fringe as the type.

const CRT := preload("res://shaders/ui/red_border_crt.gdshader")

enum MouseBehavior {
	IGNORE,
	PASS,
	STOP,
}

@export_group("Surface")
@export var fill_color := Color(0.0, 0.0, 0.0, 0.40):
	set(value):
		fill_color = value
		_refresh_chrome()
@export var border_color := Color(1.0, 0.055, 0.11, 0.95):
	set(value):
		border_color = value
		_refresh_chrome()
@export_range(0.0, 12.0, 0.25, "or_greater") var border_width := 1.75:
	set(value):
		border_width = maxf(value, 0.0)
		_refresh_chrome()

@export_group("Glow")
@export_range(0.0, 4.0, 0.05, "or_greater") var glow_intensity := 1.0:
	set(value):
		glow_intensity = maxf(value, 0.0)
		_refresh_chrome()
@export_range(0.0, 40.0, 0.5, "or_greater") var glow_spread := 10.0:
	set(value):
		glow_spread = maxf(value, 0.0)
		_refresh_chrome()
@export_range(1, 8, 1) var glow_layers := 4:
	set(value):
		glow_layers = clampi(value, 1, 8)
		_refresh_chrome()

@export_group("Input")
@export var mouse_behavior: MouseBehavior = MouseBehavior.IGNORE:
	set(value):
		mouse_behavior = value
		_apply_mouse_behavior()

var _chrome: Node2D
var _chrome_host: Control
var _crt: ShaderMaterial


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_mouse_behavior()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_ensure_chrome()
	_refresh_chrome()


func _exit_tree() -> void:
	if _chrome == null or not is_instance_valid(_chrome):
		_chrome = null
		return
	# Overlay chrome lives on the dressed target. Drop it when this surface
	# leaves so a reparent does not leave a second rim behind.
	if _chrome.get_parent() != self:
		_chrome.queue_free()
		_chrome = null


func _process(_delta: float) -> void:
	_apply_shader()
	if _chrome != null and is_instance_valid(_chrome):
		_chrome.queue_redraw()
	elif _chrome != null:
		_chrome = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_chrome()


func _draw() -> void:
	var border_rect := _border_rect()
	if border_rect.size.x <= 0.0 or border_rect.size.y <= 0.0:
		return
	# Fill only. The rim is the CRT chrome so a tear cannot open a hole in
	# the pane the page is sitting on.
	draw_rect(border_rect, fill_color, true)
	if _chrome != null:
		return
	_draw_glow(border_rect)
	if border_width > 0.0 and border_color.a > 0.0:
		draw_rect(border_rect, border_color, false, border_width, true)


func _border_rect() -> Rect2:
	var shortest := minf(size.x, size.y)
	if shortest <= 0.0:
		return Rect2()
	var inset_limit := maxf(shortest * 0.5 - 0.01, 0.0)
	var inset := minf(maxf(border_width * 0.5, 0.5), inset_limit)
	return Rect2(Vector2.ZERO, size).grow(-inset)


func _draw_glow(border_rect: Rect2) -> void:
	if glow_intensity <= 0.0 or glow_spread <= 0.0 or border_color.a <= 0.0:
		return
	for layer in range(glow_layers, 0, -1):
		var fraction := float(layer) / float(glow_layers)
		var width := border_width + glow_spread * 2.0 * fraction
		var falloff := (1.0 - fraction * 0.72)
		var alpha := border_color.a * glow_intensity * 0.11 * falloff * falloff
		draw_rect(border_rect, _with_alpha(border_color, alpha), false, width, true)


func _host() -> Control:
	if _chrome_host != null and is_instance_valid(_chrome_host):
		return _chrome_host
	return self


func _host_size() -> Vector2:
	return _host().size


func _ensure_chrome() -> void:
	if _chrome != null and is_instance_valid(_chrome):
		return
	_ensure_material()
	var host := _host()
	_chrome = _CrtInk.new()
	_chrome.name = "CrtChrome"
	_chrome.z_as_relative = true
	_chrome.material = _crt
	(_chrome as _CrtInk).panel = self
	host.add_child(_chrome)
	if host == self:
		move_child(_chrome, 0)


func _paint_chrome() -> void:
	if _chrome == null:
		return
	var pad := _chrome_pad()
	var edge := _host_size()
	_chrome.draw_rect(
		Rect2(Vector2(-pad, -pad), edge + Vector2(pad, pad) * 2.0),
		Color.WHITE,
		true
	)


func _chrome_pad() -> float:
	return glow_spread + border_width


func _refresh_chrome() -> void:
	queue_redraw()
	_apply_shader()
	if _chrome != null:
		_chrome.queue_redraw()


func _ensure_material() -> void:
	if _crt != null:
		return
	_crt = ShaderMaterial.new()
	_crt.shader = CRT
	_apply_shader()


func _apply_shader() -> void:
	if _crt == null:
		if _chrome == null:
			return
		_ensure_material()
	if _crt == null:
		return
	_crt.set_shader_parameter(&"fill_color", fill_color)
	_crt.set_shader_parameter(&"border_color", border_color)
	_crt.set_shader_parameter(&"border_width", border_width)
	_crt.set_shader_parameter(&"glow_intensity", glow_intensity)
	_crt.set_shader_parameter(&"glow_spread", glow_spread)
	_crt.set_shader_parameter(&"glow_layers", float(glow_layers))
	_crt.set_shader_parameter(&"draw_fill", 0.0)
	_crt.set_shader_parameter(&"glitch", _glitch_amount())
	_crt.set_shader_parameter(&"chromatic", _chromatic_amount())
	_crt.set_shader_parameter(&"clock", float(Time.get_ticks_msec()) * 0.001)
	_crt.set_shader_parameter(&"panel_size", _host_size())
	_crt.set_shader_parameter(&"pad", _chrome_pad())


func _glitch_amount() -> float:
	if not CrtType.ui_fx_enabled():
		return 0.0
	var allowed := true
	var walk: Node = self
	while walk != null:
		if walk.has_meta(&"crt_glitch"):
			allowed = bool(walk.get_meta(&"crt_glitch"))
			break
		walk = walk.get_parent()
	if not allowed:
		return 0.0
	if CrtType.wants_soft_glitch(self):
		return CrtType.MENU_SOFT_GLITCH
	return 1.0


func _chromatic_amount() -> float:
	if not CrtType.ui_fx_enabled():
		return 0.0
	if CrtType.wants_soft_glitch(self):
		return 0.0
	return 1.0


func crt_material() -> ShaderMaterial:
	_ensure_material()
	return _crt


class _CrtInk extends Node2D:
	var panel: RedGlowPanel

	func _draw() -> void:
		if panel != null and is_instance_valid(panel):
			panel._paint_chrome()


func _apply_mouse_behavior() -> void:
	match mouse_behavior:
		MouseBehavior.PASS:
			mouse_filter = Control.MOUSE_FILTER_PASS
		MouseBehavior.STOP:
			mouse_filter = Control.MOUSE_FILTER_STOP
		_:
			mouse_filter = Control.MOUSE_FILTER_IGNORE


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))


## Adds a full-rect surface behind [param target] and returns it for tuning.
## The target keeps ownership of layout and input; callers can opt into PASS or
## STOP when the surface itself should participate in mouse routing.
static func add_to(
	target: Control,
	behavior: MouseBehavior = MouseBehavior.IGNORE
) -> RedGlowPanel:
	var surface := RedGlowPanel.new()
	surface.name = "RedGlowPanel"
	surface.mouse_behavior = behavior
	surface.show_behind_parent = true
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Overlay the rim on the target so PanelContainer margins cannot bury it
	# under a StyleBox fill. Node2D chrome is not laid out by containers.
	surface._chrome_host = target
	target.add_child(surface)
	target.move_child(surface, 0)
	# After add_child returns the host is free to take the overlay. Doing
	# this from ENTER_TREE fails — Godot still has the parent locked.
	surface._ensure_chrome()
	_hide_static_border(target)
	return surface


static func _hide_static_border(target: Control) -> void:
	if not target.has_theme_stylebox_override(&"panel"):
		return
	var box := target.get_theme_stylebox(&"panel") as StyleBoxFlat
	if box == null:
		return
	if box.get_border_width(SIDE_LEFT) <= 0 and box.shadow_size <= 0:
		return
	var next := box.duplicate() as StyleBoxFlat
	next.border_color = Color.TRANSPARENT
	next.set_border_width_all(0)
	next.shadow_size = 0
	target.add_theme_stylebox_override(&"panel", next)
