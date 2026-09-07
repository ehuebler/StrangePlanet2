class_name CrtType
extends SubViewportContainer

## Homepage CRT type, reused everywhere. A SubViewport rasters the font first;
## this container wears the shader so chromatic fringe hits glyphs, not the atlas.
## HUD roots keep [member glitch] at 0 (aberration and scanlines only). Menus
## and popups keep the tear, cell-shift, and snow.

const CRT := preload("res://shaders/ui/home_action_crt.gdshader")

var glitch := 1.0
var destructive := 0.0

var _view: SubViewport
var _mounted: Control
var _crt: ShaderMaterial
var _adopted_min := Vector2.ZERO


static func watch(root: Node, glitch_on := true) -> void:
	if root == null:
		return
	root.set_meta(&"crt_glitch", glitch_on)
	if root.has_meta(&"crt_watch"):
		if root.is_inside_tree():
			dress_tree(root)
		return
	root.set_meta(&"crt_watch", true)
	_hook_tree(root.get_tree())
	if root.is_inside_tree():
		dress_tree(root)
	elif not root.has_meta(&"crt_watch_ready"):
		root.set_meta(&"crt_watch_ready", true)
		root.ready.connect(_on_watch_ready.bind(root), CONNECT_ONE_SHOT)


static func dress_tree(root: Node) -> void:
	if root == null:
		return
	if root is Control and _should_wrap(root as Control):
		dress(root as Control)
	for child: Node in root.get_children():
		if child is CrtType:
			continue
		dress_tree(child)


static func dress(control: Control, glitch_on := -1.0) -> Control:
	if control == null or not is_instance_valid(control):
		return control
	if _already_dressed(control):
		return host_of(control)
	var host := CrtType.new()
	host.name = "%sCrt" % control.name
	host.stretch = false
	host.clip_contents = false
	host._adopt_layout(control)
	host._adopted_min = host._measure_before_mount(control)
	host.custom_minimum_size = host._adopted_min
	var amount := glitch_on
	if amount < 0.0:
		amount = 1.0 if _wants_glitch(control) else 0.0
	host.glitch = clampf(amount, 0.0, 1.0)
	var parent := control.get_parent()
	if parent != null:
		if parent.get_children().find(control) < 0:
			return control
		var idx := control.get_index()
		parent.remove_child(control)
		parent.add_child(host)
		parent.move_child(host, idx)
	host._mount(control)
	return host


static func host_of(node: Node) -> CrtType:
	if node is CrtType:
		return node as CrtType
	if node is Control and (node as Control).has_meta(&"crt_type"):
		var marked: Variant = (node as Control).get_meta(&"crt_type")
		if marked is CrtType:
			return marked as CrtType
	var walk := node.get_parent() if node != null else null
	while walk != null:
		if walk is CrtType:
			return walk as CrtType
		walk = walk.get_parent()
	return null


static func inner(node: Node) -> Node:
	if node is CrtType:
		return (node as CrtType).mounted()
	return node


static func layout_parent(node: Node) -> Node:
	var host := host_of(node)
	if host != null:
		return host.get_parent()
	return node.get_parent() if node != null else null


static func screen_rect(node: Node) -> Rect2:
	if not node is Control:
		return Rect2()
	var control := node as Control
	var host := host_of(control)
	if host == null:
		return control.get_global_rect()
	if host.mounted() == control or host == control:
		return host.get_global_rect()
	var local := control.get_global_rect()
	var host_rect := host.get_global_rect()
	return Rect2(host_rect.position + local.position, local.size)


func mounted() -> Control:
	return _mounted


func set_destructive(value: float) -> void:
	destructive = clampf(value, 0.0, 1.0)
	_apply_shader()


func set_glitch(value: float) -> void:
	glitch = clampf(value, 0.0, 1.0)
	_apply_shader()


func _ready() -> void:
	_ensure_material()
	set_process(true)
	tree_exiting.connect(_on_tree_exiting)


func _on_tree_exiting() -> void:
	set_process(false)
	if _mounted != null and is_instance_valid(_mounted):
		_mounted.remove_meta(&"crt_type")
	if _view != null and is_instance_valid(_view):
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_view.queue_free()
		_view = null
	material = null
	_crt = null


func _process(_delta: float) -> void:
	_sync_view()
	if _mounted != null:
		if visible != _mounted.visible:
			visible = _mounted.visible
	if _crt == null:
		return
	var lit := 0.0
	var off := 0.0
	if _mounted is BaseButton:
		var button := _mounted as BaseButton
		lit = 1.0 if button.is_hovered() or button.has_focus() else 0.0
		off = 1.0 if button.disabled else 0.0
	_crt.set_shader_parameter(&"hover", lit)
	_crt.set_shader_parameter(&"disabled", off)
	_crt.set_shader_parameter(&"destructive", destructive)
	_crt.set_shader_parameter(&"glitch", glitch)
	if _view != null:
		var focused := _mounted != null and (
			_mounted is LineEdit or _mounted is TextEdit
		) and _mounted.has_focus()
		_view.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if focused
			else SubViewport.UPDATE_WHEN_VISIBLE
		)


func _get_minimum_size() -> Vector2:
	return _adopted_min if _adopted_min != Vector2.ZERO else custom_minimum_size


func _mount(control: Control) -> void:
	_mounted = control
	control.set_meta(&"crt_type", self)
	_ensure_material()
	material = _crt
	if _view == null:
		_view = SubViewport.new()
		_view.name = "CrtView"
		_view.transparent_bg = true
		_view.disable_3d = true
		_view.handle_input_locally = false
		_view.gui_disable_input = false
		_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		_view.size = Vector2i(1, 1)
		add_child(_view)
	if control.get_parent() != _view:
		if control.get_parent() != null:
			control.get_parent().remove_child(control)
		_view.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	visible = control.visible
	_apply_shader()
	_sync_view()


func _adopt_layout(from: Control) -> void:
	custom_minimum_size = from.custom_minimum_size
	size_flags_horizontal = from.size_flags_horizontal
	size_flags_vertical = from.size_flags_vertical
	size_flags_stretch_ratio = from.size_flags_stretch_ratio
	grow_horizontal = from.grow_horizontal
	grow_vertical = from.grow_vertical
	mouse_filter = from.mouse_filter
	if from is BaseButton:
		mouse_filter = Control.MOUSE_FILTER_STOP
	var parent := from.get_parent()
	var boxed := parent is Container
	if boxed:
		return
	anchor_left = from.anchor_left
	anchor_top = from.anchor_top
	anchor_right = from.anchor_right
	anchor_bottom = from.anchor_bottom
	offset_left = from.offset_left
	offset_top = from.offset_top
	offset_right = from.offset_right
	offset_bottom = from.offset_bottom
	if is_equal_approx(anchor_left, anchor_right) \
			and is_equal_approx(anchor_top, anchor_bottom):
		position = from.position
		size = from.size


func _measure_before_mount(control: Control) -> Vector2:
	var explicit := control.custom_minimum_size
	var expand_x := (control.size_flags_horizontal & Control.SIZE_EXPAND) != 0
	if control is Label:
		var label := control as Label
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var measured := _measure_label(label, 0.0)
			return Vector2(
				explicit.x if expand_x else maxf(explicit.x, measured.x),
				maxf(explicit.y, measured.y)
			)
		return explicit
	if control is RichTextLabel:
		return explicit
	var measured := control.get_combined_minimum_size()
	return Vector2(maxf(explicit.x, measured.x), maxf(explicit.y, measured.y))


func _capped_label_height(label: Label, measured_y: float) -> float:
	if label.max_lines_visible <= 0:
		return measured_y
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null:
		return measured_y
	var line := font.get_height(font_size)
	if line <= 0.0:
		return measured_y
	return minf(measured_y, line * float(label.max_lines_visible))


func _measure_label(label: Label, wrap_width: float) -> Vector2:
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	if font == null:
		return Vector2.ZERO
	var flags := label.horizontal_alignment
	var pad := float(label.get_theme_constant(&"outline_size"))
	var measured := Vector2.ZERO
	if wrap_width > 1.0:
		measured = font.get_multiline_string_size(
			label.text, flags, wrap_width, font_size)
	else:
		measured = font.get_string_size(label.text, flags, -1, font_size)
	return measured + Vector2(pad, pad)


func _sync_view() -> void:
	if _mounted == null:
		return
	var next := _adopted_min
	if _mounted.custom_minimum_size.x > 0.0:
		next.x = maxf(next.x, _mounted.custom_minimum_size.x)
	if _mounted.custom_minimum_size.y > 0.0:
		next.y = maxf(next.y, _mounted.custom_minimum_size.y)
	if _mounted is Label:
		var label := _mounted as Label
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			var wrap_w := size.x
			if _mounted.custom_minimum_size.x > 1.0:
				wrap_w = _mounted.custom_minimum_size.x
			if wrap_w > 1.0:
				var measured := _measure_label(label, wrap_w)
				next.x = _adopted_min.x
				if _mounted.custom_minimum_size.x > 1.0:
					next.x = _mounted.custom_minimum_size.x
				next.y = maxf(next.y, _capped_label_height(label, measured.y))
	if not custom_minimum_size.is_equal_approx(next):
		custom_minimum_size = next
		_adopted_min = next
		update_minimum_size()
	if _view == null:
		return
	var px := Vector2i(
		maxi(int(round(maxf(size.x, 1.0))), 1),
		maxi(int(round(maxf(size.y, 1.0))), 1)
	)
	if _view.size != px:
		_view.size = px


func _ensure_material() -> void:
	if _crt != null:
		return
	_crt = ShaderMaterial.new()
	_crt.shader = CRT
	_apply_shader()


func _apply_shader() -> void:
	if _crt == null:
		return
	_crt.set_shader_parameter(&"red_tint", Color("ef151f"))
	_crt.set_shader_parameter(&"destructive", destructive)
	_crt.set_shader_parameter(&"glitch", glitch)


static func _on_watch_ready(root: Node) -> void:
	_hook_tree(root.get_tree())
	dress_tree(root)


static func _hook_tree(tree: SceneTree) -> void:
	if tree == null:
		return
	if tree.has_meta(&"crt_type_hooked"):
		return
	tree.set_meta(&"crt_type_hooked", true)
	tree.node_added.connect(_on_node_added)


static func _on_node_added(node: Node) -> void:
	if not node is Control:
		return
	var control := node as Control
	if not _should_wrap(control):
		return
	if control.has_meta(&"crt_queued"):
		return
	control.set_meta(&"crt_queued", true)
	_dress_later.call_deferred(control)


static func _dress_later(node: Variant) -> void:
	if node == null or not is_instance_valid(node) or not node is Control:
		return
	var control := node as Control
	if control.has_meta(&"crt_queued"):
		control.remove_meta(&"crt_queued")
	dress(control)


static func _should_wrap(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if control is CrtType:
		return false
	if _already_dressed(control):
		return false
	if not _under_watched(control):
		return false
	if _skip_control(control):
		return false
	var parent := control.get_parent()
	if parent != null and parent.get_children().find(control) < 0:
		return false
	return _is_text_control(control)


static func _already_dressed(control: Control) -> bool:
	if control.has_meta(&"crt_type"):
		return true
	var walk := control.get_parent()
	while walk != null:
		if walk is CrtType:
			return true
		walk = walk.get_parent()
	return false


static func _under_watched(node: Node) -> bool:
	var walk := node
	while walk != null:
		if walk.has_meta(&"crt_watch"):
			return true
		walk = walk.get_parent()
	return false


static func _skip_control(control: Control) -> bool:
	if control is TextureButton:
		return true
	if control is LineEdit:
		var parent := control.get_parent()
		if parent is SpinBox:
			return true
	var walk: Node = control
	while walk != null:
		if walk is DamageNumberLayer:
			return true
		if walk is HoldActionButton:
			return true
		walk = walk.get_parent()
	return false


static func _is_text_control(node: Node) -> bool:
	if node is Label or node is RichTextLabel or node is LineEdit \
			or node is TextEdit:
		return true
	if node is Button and not node is TextureButton:
		var button := node as Button
		if button.text.strip_edges().is_empty():
			return false
		return not _has_text_descendant(button)
	return false


static func _has_text_descendant(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is Label or child is RichTextLabel or child is LineEdit \
				or child is TextEdit:
			return true
		if child is BaseButton or child is CrtType:
			continue
		if _has_text_descendant(child):
			return true
	return false


static func _wants_glitch(node: Node) -> bool:
	var walk := node
	while walk != null:
		if walk.has_meta(&"crt_glitch"):
			return bool(walk.get_meta(&"crt_glitch"))
		walk = walk.get_parent()
	return true
