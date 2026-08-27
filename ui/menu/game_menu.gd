class_name GameMenu
extends Control

## Inset red Tab/Escape-menu shell. The full-screen root owns input, while the
## visible menu leaves a clean border of live world around every edge.

signal closed
signal leave_requested
signal respawn_requested

## Compatibility entries intentionally have distinct values. That lets legacy
## QUESTS and ACHIEVEMENTS calls select the matching Data subtab before they are
## normalized to the canonical DATA page.
enum Tab {
	HERO,
	APPAREL,
	ITEMS,
	ABILITIES,
	DATA,
	SETTINGS,
	ADMIN,
	INVENTORY,
	QUESTS,
	ACHIEVEMENTS,
}

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const MENU_BACKGROUND: Texture2D = preload("res://assets/runtime/ui/menu_background.png")

const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff8d98")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const BLACK_40 := Color(0.0, 0.0, 0.0, 0.40)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const BLACK_82 := Color(0.0, 0.0, 0.0, 0.82)
const EDGE_GAP := 28.0

## The page consumes the width formerly reserved for the side actions. Navigation
## and the circular session actions share the band directly beneath it.
const CONTENT_RECT := Rect2(0.065, 0.035, 0.870, 0.715)
const SELECTOR_RECT := Rect2(0.250, 0.765, 0.220, 0.210)
const ADMIN_RECT := Rect2(0.035, 0.875, 0.135, 0.090)
const ACTIONS_RECT := Rect2(0.500, 0.765, 0.435, 0.140)

var _player: OnlinePlayer
var _tab: Tab = Tab.ITEMS
var _data_kind: StringName = JournalDB.QUEST
var _closing := false

var _shell: Control
var _page_host: MarginContainer
var _active_page: Control
var _selector_buttons: Dictionary = {}
var _admin_button: Button
var _settings_action: Button


## Called before the menu enters the tree. Each routed page is configured from
## this live player rather than from a copied catalogue.
func configure(player: OnlinePlayer) -> void:
	_player = player


func _init() -> void:
	name = "GameMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_shell()
	_replace_active_page()
	_refresh_navigation()


## Tab must be caught before GUI focus navigation consumes it. Escape follows the
## same path, from every page including Settings and its text/input controls.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


## Opens a canonical page. Legacy aliases remain source-compatible:
## INVENTORY -> Items, QUESTS -> Data/Quests, ACHIEVEMENTS -> Data/Achievements.
func show_tab(tab: Tab) -> void:
	if tab == Tab.QUESTS:
		_data_kind = JournalDB.QUEST
	elif tab == Tab.ACHIEVEMENTS:
		_data_kind = JournalDB.ACHIEVEMENT

	var canonical := _canonical_tab(tab)
	var page_is_current := canonical == _tab \
		and _active_page != null and is_instance_valid(_active_page)
	_tab = canonical

	if _page_host == null:
		return
	_refresh_navigation()
	if page_is_current:
		_sync_data_kind()
		return
	_replace_active_page()


## Always reports the normalized canonical page, never a compatibility alias.
func current_tab() -> Tab:
	return _tab


func _canonical_tab(tab: Tab) -> Tab:
	if tab == Tab.INVENTORY:
		return Tab.ITEMS
	if tab == Tab.QUESTS or tab == Tab.ACHIEVEMENTS:
		return Tab.DATA
	if tab == Tab.HERO or tab == Tab.APPAREL or tab == Tab.ITEMS \
			or tab == Tab.ABILITIES or tab == Tab.DATA \
			or tab == Tab.SETTINGS or tab == Tab.ADMIN:
		return tab
	return Tab.ITEMS


# --- Shell ------------------------------------------------------------------

func _build_shell() -> void:
	_shell = Control.new()
	_shell.name = "InsetMenuShell"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.offset_left = EDGE_GAP
	_shell.offset_top = EDGE_GAP
	_shell.offset_right = -EDGE_GAP
	_shell.offset_bottom = -EDGE_GAP
	_shell.clip_contents = true
	add_child(_shell)

	var background := TextureRect.new()
	background.name = "MenuBackground"
	background.texture = MENU_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.add_child(background)

	var outer_border := RedGlowPanel.new()
	outer_border.name = "MenuBackgroundBorder"
	outer_border.fill_color = Color.TRANSPARENT
	outer_border.border_color = Color(GREEN, 0.98)
	outer_border.border_width = 2.5
	outer_border.glow_intensity = 1.25
	outer_border.glow_spread = 8.0
	outer_border.glow_layers = 4
	outer_border.mouse_behavior = RedGlowPanel.MouseBehavior.IGNORE
	outer_border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.add_child(outer_border)

	_build_content_frame()
	_build_bottom_selector()
	_build_admin_button()
	_build_right_actions()


func _build_content_frame() -> void:
	var frame := RedGlowPanel.new()
	frame.name = "ContentFrame"
	frame.fill_color = BLACK_40
	frame.border_color = Color(RED_BRIGHT, 0.98)
	frame.border_width = 2.0
	frame.glow_intensity = 1.55
	frame.glow_spread = 13.0
	frame.glow_layers = 5
	frame.mouse_behavior = RedGlowPanel.MouseBehavior.STOP
	_apply_anchor_rect(frame, CONTENT_RECT)
	_shell.add_child(frame)

	_page_host = MarginContainer.new()
	_page_host.name = "PageHost"
	_page_host.clip_contents = true
	_page_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		_page_host.add_theme_constant_override(side, 16)
	frame.add_child(_page_host)


func _build_bottom_selector() -> void:
	var selector := RedGlowPanel.new()
	selector.name = "BottomSelector"
	selector.fill_color = BLACK_68
	selector.border_color = Color(RED_BRIGHT, 0.96)
	selector.border_width = 1.75
	selector.glow_intensity = 1.35
	selector.glow_spread = 10.0
	selector.glow_layers = 5
	selector.mouse_behavior = RedGlowPanel.MouseBehavior.STOP
	_apply_anchor_rect(selector, SELECTOR_RECT)
	_shell.add_child(selector)

	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Equal vertical insets make the air above Hero and below Data match.
	for side in [&"margin_left", &"margin_right"]:
		inset.add_theme_constant_override(side, 8)
	for side in [&"margin_top", &"margin_bottom"]:
		inset.add_theme_constant_override(side, 8)
	selector.add_child(inset)

	var stack := VBoxContainer.new()
	stack.name = "SelectorStack"
	stack.add_theme_constant_override(&"separation", 2)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(stack)

	_add_selector_button(stack, "TabHero", "Hero", RedMenuGlyph.Glyph.HERO, Tab.HERO)
	_add_selector_button(
		stack,
		"TabApparel",
		"Apparel",
		RedMenuGlyph.Glyph.APPAREL_ALL,
		Tab.APPAREL
	)
	_add_selector_button(stack, "TabItems", "Items", RedMenuGlyph.Glyph.ITEMS, Tab.ITEMS)
	_add_selector_button(
		stack,
		"TabAbilities",
		"Abilities",
		RedMenuGlyph.Glyph.ABILITIES,
		Tab.ABILITIES
	)
	_add_selector_button(stack, "TabData", "Data", RedMenuGlyph.Glyph.DATA, Tab.DATA)


func _add_selector_button(
	parent: VBoxContainer,
	node_name: String,
	label_text: String,
	glyph_kind: RedMenuGlyph.Glyph,
	tab: Tab
) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = label_text.to_upper()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 18.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	_style_selector_button(button, false)

	var glyph_lane := CenterContainer.new()
	glyph_lane.name = "GlyphLane"
	glyph_lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_lane.anchor_right = 0.0
	glyph_lane.anchor_bottom = 1.0
	glyph_lane.offset_right = 36.0
	button.add_child(glyph_lane)

	var glyph := RedMenuGlyph.new()
	glyph.name = "Glyph"
	glyph.glyph = glyph_kind
	glyph.custom_minimum_size = Vector2(20.0, 20.0)
	glyph_lane.add_child(glyph)

	var chosen: Tab = tab
	button.pressed.connect(func() -> void: show_tab(chosen))
	parent.add_child(button)
	_selector_buttons[tab] = button


func _build_admin_button() -> void:
	_admin_button = Button.new()
	_admin_button.name = "AdminButton"
	_admin_button.text = "ADMIN"
	_admin_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_admin_button.add_theme_font_size_override(&"font_size", 14)
	_apply_anchor_rect(_admin_button, ADMIN_RECT)
	_style_admin_button(false)
	_admin_button.pressed.connect(func() -> void: show_tab(Tab.ADMIN))

	var glow := RedGlowPanel.add_to(_admin_button)
	glow.fill_color = Color.TRANSPARENT
	glow.border_color = Color(RED, 0.86)
	glow.border_width = 1.5
	glow.glow_intensity = 1.05
	glow.glow_spread = 8.0
	_shell.add_child(_admin_button)


func _build_right_actions() -> void:
	var cluster := HBoxContainer.new()
	cluster.name = "SessionActions"
	cluster.alignment = BoxContainer.ALIGNMENT_CENTER
	cluster.add_theme_constant_override(&"separation", 28)
	_apply_anchor_rect(cluster, ACTIONS_RECT)
	_shell.add_child(cluster)

	var close_action := _action_button("CloseAction", RedMenuGlyph.Glyph.CLOSE)
	close_action.tooltip_text = "Close menu"
	close_action.pressed.connect(close)
	cluster.add_child(_action_entry(close_action, "CLOSE"))

	_settings_action = _action_button("SettingsAction", RedMenuGlyph.Glyph.SETTINGS)
	_settings_action.tooltip_text = "Open settings"
	_settings_action.pressed.connect(func() -> void: show_tab(Tab.SETTINGS))
	cluster.add_child(_action_entry(_settings_action, "SETTINGS"))

	var respawn_action := HoldActionButton.new()
	respawn_action.name = "RespawnAction"
	respawn_action.custom_minimum_size = Vector2(54.0, 54.0)
	respawn_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	respawn_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	respawn_action.label_text = ""
	respawn_action.glyph = RedMenuGlyph.Glyph.RESPAWN
	respawn_action.hold_duration = 1.1
	respawn_action.content_padding = 6.0
	respawn_action.progress_width = 3.0
	respawn_action.fill_color = GREEN
	respawn_action.green_color = GREEN
	respawn_action.active = true
	respawn_action.circular = true
	respawn_action.tooltip_text = "Hold to respawn above the nearest city"
	respawn_action.completed.connect(_on_respawn_completed)
	cluster.add_child(_action_entry(respawn_action, "HOLD RESPAWN"))
	var respawn_glyph := respawn_action.get_node_or_null("Glyph") as RedMenuGlyph
	if respawn_glyph != null:
		respawn_glyph.green_color = BLACK_82
		respawn_glyph.black_color = BLACK_82

	var leave_action := HoldActionButton.new()
	leave_action.name = "LeaveAction"
	leave_action.custom_minimum_size = Vector2(54.0, 54.0)
	leave_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave_action.label_text = ""
	leave_action.glyph = RedMenuGlyph.Glyph.EXIT
	leave_action.hold_duration = 1.1
	leave_action.content_padding = 6.0
	leave_action.progress_width = 3.0
	leave_action.fill_color = GREEN
	leave_action.green_color = GREEN
	leave_action.active = true
	leave_action.circular = true
	leave_action.tooltip_text = "Hold to leave the session"
	leave_action.completed.connect(_on_leave_completed)
	cluster.add_child(_action_entry(leave_action, "HOLD LEAVE"))
	# HoldActionButton keeps green for its progress arc; recolour only the glyph
	# after _ready has created it so the painted key itself remains black.
	var leave_glyph := leave_action.get_node_or_null("Glyph") as RedMenuGlyph
	if leave_glyph != null:
		leave_glyph.green_color = BLACK_82
		leave_glyph.black_color = BLACK_82


func _action_button(node_name: String, glyph_kind: RedMenuGlyph.Glyph) -> Button:
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(54.0, 54.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	_style_action_button(button, false)

	var glyph := RedMenuGlyph.new()
	glyph.name = "Glyph"
	glyph.glyph = glyph_kind
	glyph.green_color = BLACK_82
	glyph.black_color = BLACK_82
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.offset_left = 10.0
	glyph.offset_top = 10.0
	glyph.offset_right = -10.0
	glyph.offset_bottom = -10.0
	button.add_child(glyph)
	return button


func _action_entry(control: Control, label_text: String) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.custom_minimum_size = Vector2(108.0, 82.0)
	entry.alignment = BoxContainer.ALIGNMENT_CENTER
	entry.add_theme_constant_override(&"separation", 4)
	entry.add_child(control)

	var label := Label.new()
	label.name = "%sLabel" % control.name
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", RED_BRIGHT)
	label.add_theme_color_override(&"font_outline_color", Color(0.08, 0.0, 0.0, 0.98))
	label.add_theme_constant_override(&"outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(label)
	return entry


func _apply_anchor_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.end.x
	control.anchor_bottom = rect.end.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


# --- Routing ----------------------------------------------------------------

## Only the active page remains in the tree. In particular, Hero's SubViewport
## does not continue rendering behind another tab.
func _replace_active_page() -> void:
	if _active_page != null and is_instance_valid(_active_page):
		if _active_page.get_parent() == _page_host:
			_page_host.remove_child(_active_page)
		_active_page.queue_free()

	_active_page = _build_page(_tab)
	if _active_page == null:
		return
	_active_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(_active_page)


func _build_page(tab: Tab) -> Control:
	match tab:
		Tab.HERO:
			var hero := RedHeroPage.new()
			hero.configure(_player)
			return hero
		Tab.APPAREL:
			return _catalogue_page(RedCataloguePage.Mode.APPAREL)
		Tab.ITEMS:
			return _catalogue_page(RedCataloguePage.Mode.ITEMS)
		Tab.ABILITIES:
			return _catalogue_page(RedCataloguePage.Mode.ABILITIES)
		Tab.DATA:
			var data := RedDataPage.new()
			data.configure(_player.journal if _player != null else null)
			data.set_kind(_data_kind)
			return data
		Tab.SETTINGS:
			var settings := SettingsPanel.new()
			settings.name = "InGameSettings"
			settings.configure(true)
			return settings
		Tab.ADMIN:
			var blank := Control.new()
			blank.name = "AdminBlank"
			return blank
	return null


func _catalogue_page(mode: RedCataloguePage.Mode) -> RedCataloguePage:
	var page := RedCataloguePage.new()
	page.configure(_player, mode)
	page.drop_requested.connect(_on_drop_requested)
	return page


func _sync_data_kind() -> void:
	if _tab == Tab.DATA and _active_page is RedDataPage:
		(_active_page as RedDataPage).set_kind(_data_kind)


## A drop request crosses into the surrounding world only when that public entry
## point exists. The catalogue deliberately leaves every source slot untouched.
func _on_drop_requested(source: String, index: int, item_id: String) -> void:
	if _player == null:
		return
	var world := _surrounding_world()
	if world != null and world.has_method(&"request_drop"):
		world.call(&"request_drop", _player.peer_id, source, index, item_id)


func _surrounding_world() -> Node:
	var ancestor: Node = _player
	while ancestor != null:
		if ancestor is GameWorld:
			return ancestor
		ancestor = ancestor.get_parent()
	return null


func _on_leave_completed() -> void:
	leave_requested.emit()


func _on_respawn_completed() -> void:
	respawn_requested.emit()
	close()


# --- Sharp red/green control styling ----------------------------------------

func _refresh_navigation() -> void:
	if _selector_buttons.is_empty():
		return
	_style_selector_button(
		_selector_buttons[Tab.HERO] as Button,
		_tab == Tab.HERO
	)
	_style_selector_button(
		_selector_buttons[Tab.APPAREL] as Button,
		_tab == Tab.APPAREL
	)
	_style_selector_button(
		_selector_buttons[Tab.ITEMS] as Button,
		_tab == Tab.ITEMS
	)
	_style_selector_button(
		_selector_buttons[Tab.ABILITIES] as Button,
		_tab == Tab.ABILITIES
	)
	_style_selector_button(
		_selector_buttons[Tab.DATA] as Button,
		_tab == Tab.DATA
	)
	_style_admin_button(_tab == Tab.ADMIN)
	_style_action_button(_settings_action, _tab == Tab.SETTINGS)


func _style_selector_button(button: Button, selected: bool) -> void:
	var accent := GREEN if selected else RED
	var text_color := GREEN_TEXT if selected else RED_TEXT
	var fill := Color(0.0, 0.15, 0.045, 0.82) if selected else BLACK_82
	button.add_theme_font_size_override(&"font_size", 12)
	button.add_theme_color_override(&"font_color", text_color)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", text_color)
	button.add_theme_color_override(&"font_outline_color", Color(0.06, 0.0, 0.0, 0.98))
	button.add_theme_constant_override(&"outline_size", 2)
	button.add_theme_stylebox_override(
		&"normal",
		_selector_style(fill, Color(accent, 0.95), 2 if selected else 1, 2.0,
			Color(accent, 0.16), 4)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_selector_style(BLACK_82, GREEN, 2, 2.0, Color(RED, 0.20), 5)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_selector_style(Color(0.0, 0.19, 0.055, 0.90), GREEN, 2, 2.0)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_selector_style(Color.TRANSPARENT, GREEN, 1, 2.0)
	)


## Selector glyphs are drawn as child Controls rather than Button icons. Reserve
## their lane in every state so the label never paints through the glyph.
func _selector_style(
	fill: Color,
	border: Color,
	border_width: int,
	padding: float,
	shadow: Color = Color.TRANSPARENT,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var box := _style(fill, border, border_width, padding, shadow, shadow_size)
	box.content_margin_left = 40.0
	return box


func _style_admin_button(selected: bool) -> void:
	if _admin_button == null:
		return
	var accent := GREEN if selected else RED_BRIGHT
	_admin_button.add_theme_color_override(&"font_color", accent)
	_admin_button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	_admin_button.add_theme_color_override(&"font_pressed_color", GREEN)
	_admin_button.add_theme_color_override(&"font_focus_color", accent)
	_admin_button.add_theme_stylebox_override(
		&"normal",
		_style(
			Color(0.0, 0.14, 0.04, 0.80) if selected else BLACK_82,
			accent,
			2 if selected else 1,
			8.0,
			Color(accent, 0.18),
			5
		)
	)
	_admin_button.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_82, GREEN, 2, 8.0, Color(RED, 0.18), 5)
	)
	_admin_button.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.18, 0.05, 0.88), GREEN, 2, 8.0)
	)
	_admin_button.add_theme_stylebox_override(
		&"focus",
		_style(Color.TRANSPARENT, GREEN, 1, 7.0)
	)


func _style_action_button(button: Button, selected: bool) -> void:
	if button == null:
		return
	var border := GREEN_TEXT if selected else Color(GREEN, 0.96)
	var fill := GREEN_TEXT if selected else GREEN
	button.add_theme_stylebox_override(
		&"normal",
		_circle_style(fill, border, 2 if selected else 1, 3.0,
			Color(RED, 0.16), 4)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_circle_style(GREEN_TEXT, Color.WHITE, 2, 3.0, Color(RED, 0.24), 5)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_circle_style(Color(0.20, 0.72, 0.30, 1.0), BLACK_82, 2, 3.0)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_circle_style(Color.TRANSPARENT, RED_BRIGHT, 2, 3.0)
	)


func _circle_style(
	fill: Color,
	border: Color,
	border_width: int,
	padding: float,
	shadow: Color = Color.TRANSPARENT,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var box := _style(fill, border, border_width, padding, shadow, shadow_size)
	box.set_corner_radius_all(32)
	return box


func _style(
	fill: Color,
	border: Color,
	border_width: int,
	padding: float,
	shadow: Color = Color.TRANSPARENT,
	shadow_size: int = 0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	box.shadow_color = shadow
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2.ZERO
	return box
