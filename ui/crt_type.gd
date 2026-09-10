class_name CrtType
extends SubViewportContainer

## Homepage CRT type, reused everywhere. A SubViewport rasters the control
## first; this container wears the shader so tear and fringe hit the picture,
## not the font atlas. HUD roots keep [member glitch] at 0 (scanlines only).
## Menu type keeps a light tear. Body copy stays tear-only. Large titles may
## opt into chromatic aberration with the `crt_chromatic` meta. Icons keep
## the fringe unless a `crt_soft_glitch` ancestor turns it off (mod tiles).
## Red rims use their own shader. The Display setting `ui_glitch`
## zeros tear and fringe on every host and leaves scanlines.

const CRT := preload("res://shaders/ui/home_action_crt.gdshader")
const MENU_TYPE_GLITCH := 0.35
## Lighter tear for modifier tiles so the catalogue art stays readable.
const MENU_SOFT_GLITCH := 0.14

var glitch := 1.0
var destructive := 0.0
var _clock := 0.0
var _last_hover := -1.0
var _last_off := -1.0

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
	if not _object_usable(root):
		return
	if root is Control and _should_wrap(root as Control):
		dress(root as Control)
	if not _object_usable(root):
		return
	for child: Node in root.get_children():
		if not _object_usable(child):
			continue
		if child is CrtType:
			continue
		dress_tree(child)


static func dress(control: Control, glitch_on := -1.0) -> Control:
	if not _usable_control(control):
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
		if not _wants_glitch(control):
			amount = 0.0
		elif _wants_soft_glitch(control):
			amount = MENU_SOFT_GLITCH
		else:
			amount = MENU_TYPE_GLITCH
	elif amount > 0.0:
		amount = minf(amount, MENU_SOFT_GLITCH if _wants_soft_glitch(control) \
			else MENU_TYPE_GLITCH)
	host.glitch = clampf(amount, 0.0, 1.0)
	if _is_icon_control(control):
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent := control.get_parent()
	if parent != null:
		if parent.get_children().find(control) < 0:
			return control
		var idx := control.get_index()
		parent.remove_child(control)
		parent.add_child(host)
		parent.move_child(host, idx)
	host._mount(control)
	# Rim chrome stays outside the type viewport so a buy/tab button can wear
	# text CRT without running the border through the glyph shader twice.
	# Overlay, not behind: the host's picture is the whole button, and a
	# behind-parent rim would sit under that fill.
	_lift_glow(control, host)
	return host


static func host_of(node: Node) -> CrtType:
	if not _object_usable(node):
		return null
	if node is CrtType:
		return node as CrtType
	if node is Control and (node as Control).has_meta(&"crt_type"):
		var marked: Variant = (node as Control).get_meta(&"crt_type")
		if _object_usable(marked) and marked is CrtType:
			return marked as CrtType
	var walk := node.get_parent()
	while walk != null:
		if not _object_usable(walk):
			break
		if walk is CrtType:
			return walk as CrtType
		walk = walk.get_parent()
	return null


static func inner(node: Node) -> Node:
	if not _object_usable(node):
		return node
	if node is CrtType:
		return (node as CrtType).mounted()
	return node


static func layout_parent(node: Node) -> Node:
	var host := host_of(node)
	if host != null:
		return host.get_parent()
	return node.get_parent() if _object_usable(node) else null


static func screen_rect(node: Node) -> Rect2:
	if not _usable_control(node):
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


func clock() -> float:
	return _clock


func chromatic() -> float:
	# Body copy stays readable: slight tear, no RGB split. Large titles
	# that opt in, and ordinary icons, keep the fringe. Modifier tiles
	# drop the split so the SVG stays on-model. HUD type with glitch off
	# also drops aberration.
	if glitch <= 0.0:
		return 0.0
	if _mounted_usable() and _mounted.has_meta(&"crt_chromatic"):
		return 1.0 if _wants_chromatic(_mounted) else 0.0
	if _mounted_usable() and _wants_soft_glitch(_mounted) and _is_icon_surface():
		return 0.0
	if _is_icon_surface() or _is_title_surface():
		return 1.0
	return 0.0


static func ui_fx_enabled() -> bool:
	if Engine.is_editor_hint():
		return true
	if SettingsManager == null:
		return true
	return bool(SettingsManager.get_setting(&"graphics", &"ui_glitch", true))


func _shader_glitch() -> float:
	return glitch if ui_fx_enabled() else 0.0


func _shader_chromatic() -> float:
	return chromatic() if ui_fx_enabled() else 0.0


func _is_icon_surface() -> bool:
	if not _mounted_usable():
		return false
	return _is_icon_control(_mounted)


func _is_title_surface() -> bool:
	if not _mounted_usable():
		return false
	return _wants_chromatic(_mounted)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	if is_queued_for_deletion() or not _mounted_usable():
		return
	if visible != _mounted.visible:
		visible = _mounted.visible
	if not visible:
		return
	var lit := 0.0
	var off := 0.0
	if _mounted is BaseButton:
		var button := _mounted as BaseButton
		lit = 1.0 if button.is_hovered() or button.has_focus() else 0.0
		# Some empty actions (Load with no save) already paint a light disabled
		# ink. The shader crush would turn that gray into black.
		off = 1.0 if button.disabled \
			and not button.has_meta(&"crt_keep_disabled_ink") else 0.0
	var fx := _shader_glitch() > 0.001 or _shader_chromatic() > 0.001
	if not fx and is_equal_approx(lit, _last_hover) and is_equal_approx(off, _last_off):
		if Engine.get_process_frames() % 10 != 0:
			return
	_last_hover = lit
	_last_off = off
	_sync_view()
	if not _mounted_usable() or _crt == null:
		return
	_crt.set_shader_parameter(&"hover", lit)
	_crt.set_shader_parameter(&"disabled", off)
	_crt.set_shader_parameter(&"destructive", destructive)
	_crt.set_shader_parameter(&"glitch", _shader_glitch())
	_crt.set_shader_parameter(&"chromatic", _shader_chromatic())
	if fx:
		_tick_clock()
		queue_redraw()
	if _view != null:
		var focused := (
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
		if "mouse_target" in self:
			set(&"mouse_target", true)
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
	if not _mounted_usable():
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
	_crt.set_shader_parameter(&"glitch", _shader_glitch())
	_crt.set_shader_parameter(&"chromatic", _shader_chromatic())
	_tick_clock()


func _tick_clock() -> void:
	_clock = float(Time.get_ticks_msec()) * 0.001
	if _crt != null:
		_crt.set_shader_parameter(&"clock", _clock)


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
	if not _usable_control(node):
		return
	var control := node as Control
	if not _should_wrap(control):
		return
	if control.has_meta(&"crt_queued"):
		return
	control.set_meta(&"crt_queued", true)
	_dress_later.call_deferred(control)


static func _dress_later(node: Variant) -> void:
	if not _usable_control(node):
		return
	var control := node as Control
	if control.has_meta(&"crt_queued"):
		control.remove_meta(&"crt_queued")
	dress(control)


static func _object_usable(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT:
		return false
	if not is_instance_valid(value):
		return false
	return not (value as Object).is_queued_for_deletion()


static func _usable_control(value: Variant) -> bool:
	return _object_usable(value) and value is Control


func _mounted_usable() -> bool:
	if _object_usable(_mounted):
		return true
	_mounted = null
	return false


static func _should_wrap(control: Control) -> bool:
	if not _usable_control(control):
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
	return _is_text_control(control) or _is_icon_control(control)


static func _already_dressed(control: Control) -> bool:
	if control.has_meta(&"crt_type"):
		return true
	var walk := control.get_parent()
	while walk != null:
		if not _object_usable(walk):
			break
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
	if control is RedGlowPanel:
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
		if walk is CrawlerBossTitle:
			return true
		if walk.has_meta(&"crt_skip"):
			return true
		if walk.name == "CrawlerBossTitle" or walk.name == "CrawlerBossTitleLayer":
			return true
		if walk.name == "RunRecap" or walk.name == "RunRecapScroll":
			return true
		walk = walk.get_parent()
	return false


static func _lift_glow(control: Control, host: CrtType) -> void:
	if not _usable_control(control) or host == null:
		return
	var rim := control.get_node_or_null("RedGlowPanel") as RedGlowPanel
	if rim == null:
		return
	var chrome := control.get_node_or_null("CrtChrome") as Node2D
	control.remove_child(rim)
	host.add_child(rim)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rim.show_behind_parent = false
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim._chrome_host = host
	if chrome == null or not is_instance_valid(chrome):
		return
	if chrome.get_parent() == control:
		control.remove_child(chrome)
	if chrome.get_parent() != host:
		host.add_child(chrome)


static func _is_icon_control(node: Node) -> bool:
	if node is RedMenuGlyph:
		return true
	if node is RedCharacterPreview:
		return str(node.name).contains("Face")
	if not (node is TextureRect):
		return false
	var icon := node as TextureRect
	var icon_name := str(icon.name)
	if icon_name.contains("Background"):
		return false
	if icon.stretch_mode == TextureRect.STRETCH_SCALE:
		return false
	if icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
		return true
	return icon_name.contains("Icon") or icon_name.contains("Glyph")


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


static func mark_soft_icon(node: Node) -> void:
	if not _object_usable(node):
		return
	node.set_meta(&"crt_soft_glitch", true)
	if node is Control:
		(node as Control).set_meta(&"crt_chromatic", false)
	var host := host_of(node)
	if host != null:
		host.set_glitch(MENU_SOFT_GLITCH)


static func wants_soft_glitch(node: Node) -> bool:
	return _wants_soft_glitch(node)


static func _wants_soft_glitch(node: Node) -> bool:
	var walk := node
	while walk != null:
		if not _object_usable(walk):
			break
		if walk.has_meta(&"crt_soft_glitch"):
			return bool(walk.get_meta(&"crt_soft_glitch"))
		walk = walk.get_parent()
	return false


static func _wants_glitch(node: Node) -> bool:
	var walk := node
	while walk != null:
		if walk.has_meta(&"crt_glitch"):
			return bool(walk.get_meta(&"crt_glitch"))
		walk = walk.get_parent()
	return true


static func _wants_chromatic(node: Node) -> bool:
	if not _object_usable(node):
		return false
	if node.has_meta(&"crt_chromatic"):
		return bool(node.get_meta(&"crt_chromatic"))
	return false
