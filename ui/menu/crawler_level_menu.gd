class_name CrawlerLevelMenu
extends Control

## Modal pause card after a crawler level-up. Hold a stat tile to spend
## the point; a bar fills across the tile while the press is held.

signal closed

enum Tab { SPEND, PREFS }

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const RED := Color("ef151f")
const GREEN := Color("39d98a")
const BLACK := Color(0.0, 0.0, 0.0, 0.86)
## Fast enough that a decided pick still feels instant, long enough that a
## click cannot spend by accident. Wall-clock, because the menu pauses time.
const HOLD_SECONDS := 0.12

var _player: OnlinePlayer
var _prefs_only := false
var _tab := Tab.SPEND
var _closing := false
var _title: Label
var _tabs: HBoxContainer
var _spend_page: VBoxContainer
var _prefs_page: VBoxContainer
var _auto: Button
var _reroll: Button
var _tile_host: GridContainer
var _tiles: Dictionary = {}
var _pref_boxes: Dictionary = {}
var _offer_sig := ""
var _hold_stat := ""
var _hold_elapsed := 0.0
var _hold_tick_usec := 0
var _fonts_dirty := false


func configure(player: OnlinePlayer, prefs_only := false) -> void:
	_player = player
	_prefs_only = prefs_only
	_tab = Tab.PREFS if prefs_only else Tab.SPEND


func _init() -> void:
	name = "CrawlerLevelMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 80


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	CrtType.watch(self)
	_build()
	_refresh()
	_queue_fonts()
	if _player != null and _player.crawler_progress != null \
			and not _player.crawler_progress.changed.is_connected(_refresh):
		_player.crawler_progress.changed.connect(_refresh)


func _queue_fonts() -> void:
	if _fonts_dirty:
		return
	_fonts_dirty = true
	call_deferred(&"_flush_fonts")


func _flush_fonts() -> void:
	_fonts_dirty = false
	for tile_variant: Variant in _tiles.values():
		_scale_tile_fonts(tile_variant as PanelContainer)


func _input(event: InputEvent) -> void:
	if _hold_stat.is_empty():
		return
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT \
			and not mouse.pressed:
		_clear_hold()
		return
	var touch := event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		_clear_hold()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_K:
		get_viewport().set_input_as_handled()
		_on_auto_key()
		return
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		if _can_close():
			close()


func close() -> void:
	if _closing:
		return
	if not _can_close():
		return
	_closing = true
	closed.emit()
	queue_free()


func _can_close() -> bool:
	if _prefs_only:
		return true
	return _player == null or _player.crawler_progress == null \
		or _player.crawler_progress.unspent <= 0


func show_tab(tab: Tab) -> void:
	_tab = tab
	if _spend_page != null:
		_spend_page.visible = _tab == Tab.SPEND and not _prefs_only
	if _prefs_page != null:
		_prefs_page.visible = _tab == Tab.PREFS
	if _reroll != null:
		_reroll.visible = not _prefs_only and _tab == Tab.SPEND
	_paint_tabs()


func current_tab() -> Tab:
	return _tab


func _build() -> void:
	var panel := Panel.new()
	panel.name = "LevelCard"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 120.0
	panel.offset_top = 72.0
	panel.offset_right = -120.0
	panel.offset_bottom = -72.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = BLACK
	box.set_border_width_all(0)
	panel.add_theme_stylebox_override(&"panel", box)
	var rim := RedGlowPanel.add_to(panel)
	rim.fill_color = Color.TRANSPARENT
	rim.border_color = Color(RED, 0.95)
	rim.border_width = 3.0
	rim.glow_intensity = 1.35
	rim.glow_spread = 10.0
	rim.glow_layers = 5
	add_child(panel)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 28.0
	column.offset_top = 22.0
	column.offset_right = -28.0
	column.offset_bottom = -22.0
	column.add_theme_constant_override(&"separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", 20)
	_title.add_theme_color_override(&"font_color", RED)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	_tabs = HBoxContainer.new()
	_tabs.name = "LevelTabs"
	_tabs.add_theme_constant_override(&"separation", 8)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_tabs)
	_fill_tabs()

	_spend_page = VBoxContainer.new()
	_spend_page.name = "SpendPage"
	_spend_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spend_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spend_page.add_theme_constant_override(&"separation", 10)
	column.add_child(_spend_page)

	var hint := Label.new()
	hint.name = "SpendHint"
	hint.text = "HOLD A TILE TO SPEND"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override(&"font_size", 11)
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.72))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spend_page.add_child(hint)

	_tile_host = GridContainer.new()
	_tile_host.name = "SpendTiles"
	_tile_host.columns = 2
	_tile_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tile_host.add_theme_constant_override(&"h_separation", 8)
	_tile_host.add_theme_constant_override(&"v_separation", 8)
	_tile_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_spend_page.add_child(_tile_host)

	_prefs_page = VBoxContainer.new()
	_prefs_page.name = "AutoSelectPrefs"
	_prefs_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prefs_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prefs_page.add_theme_constant_override(&"separation", 8)
	column.add_child(_prefs_page)
	_fill_prefs()

	var footer := HBoxContainer.new()
	footer.name = "LevelFooter"
	footer.add_theme_constant_override(&"separation", 8)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_child(footer)

	_auto = Button.new()
	_auto.name = "AutoSelectToggle"
	_auto.custom_minimum_size.y = 48.0
	_auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto.size_flags_vertical = Control.SIZE_SHRINK_END
	_auto.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_auto.add_theme_font_size_override(&"font_size", 12)
	_auto.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auto.clip_contents = false
	_auto.clip_text = false
	_auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auto.pressed.connect(_on_auto_pressed)
	_refresh_auto()
	footer.add_child(_auto)

	_reroll = Button.new()
	_reroll.name = "RerollOffers"
	_reroll.custom_minimum_size.y = 48.0
	_reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reroll.size_flags_vertical = Control.SIZE_SHRINK_END
	_reroll.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_reroll.clip_contents = false
	_reroll.add_theme_font_size_override(&"font_size", 13)
	_reroll.pressed.connect(_on_reroll)
	if _player != null and _player.crawler_progress != null:
		_refresh_reroll(_player.crawler_progress)
	else:
		_reroll.text = "REROLL"
		_style_reroll(false)
	footer.add_child(_reroll)
	show_tab(_tab)


func _make_tile(offer: Dictionary) -> PanelContainer:
	var stat_id := str(offer.get("id", ""))
	var rarity := int(offer.get("rarity", CrawlerProgress.RARITY_COMMON))
	var tile := PanelContainer.new()
	tile.name = "SpendTile_%s" % stat_id
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(220.0, 168.0)
	tile.clip_contents = true
	tile.set_meta(&"rarity", rarity)
	tile.set_meta(&"amount", float(offer.get("amount", 1.0)))
	tile.gui_input.connect(_on_tile_input.bind(stat_id))
	tile.mouse_entered.connect(_paint_tile.bind(stat_id, true))
	tile.mouse_exited.connect(func() -> void:
		if _hold_stat == stat_id:
			_clear_hold()
		_paint_tile(stat_id, false)
	)
	_paint_tile(stat_id, false, tile)

	var host := Control.new()
	host.name = "SpendHost"
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.clip_contents = true
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.resized.connect(_queue_fonts)
	tile.add_child(host)

	var fill := ColorRect.new()
	fill.name = "SpendFill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.color = Color(GREEN, 0.58)
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_right = 0.0
	fill.anchor_bottom = 1.0
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0
	fill.visible = false
	host.add_child(fill)

	var body := VBoxContainer.new()
	body.name = "SpendCopy"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override(&"separation", 8)
	body.clip_contents = true
	host.add_child(body)

	var ink := CrawlerProgress.rarity_color(rarity)
	var title := Label.new()
	title.name = "SpendTitle"
	title.set_meta(&"crt_chromatic", true)
	_fit_label(title, 36, ink, true, 2)
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(title)

	var rarity_label := Label.new()
	rarity_label.name = "SpendRarity"
	_fit_label(rarity_label, 17, ink)
	body.add_child(rarity_label)

	var boost := Label.new()
	boost.name = "SpendBoost"
	_fit_label(boost, 28, ink, true, 2)
	boost.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(boost)

	var values := Label.new()
	values.name = "SpendValues"
	_fit_label(values, 19, ink, true, 2)
	body.add_child(values)

	var blurb := Label.new()
	blurb.name = "SpendBlurb"
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fit_label(blurb, 16, ink, true, 3)
	body.add_child(blurb)

	tile.set_meta(&"title", title)
	tile.set_meta(&"rarity_label", rarity_label)
	tile.set_meta(&"boost", boost)
	tile.set_meta(&"values", values)
	tile.set_meta(&"blurb", blurb)
	_tiles[stat_id] = tile
	return tile


func _process(delta: float) -> void:
	if _hold_stat.is_empty():
		return
	if _player == null or _player.crawler_progress == null \
			or _player.crawler_progress.unspent <= 0:
		_clear_hold()
		return
	var now := Time.get_ticks_usec()
	var wall := maxf(float(now - _hold_tick_usec) / 1_000_000.0, 0.0)
	_hold_tick_usec = now
	_hold_elapsed += delta if delta > 0.0 else wall
	_set_hold_progress(_hold_stat, _hold_elapsed / HOLD_SECONDS)
	if _hold_elapsed >= HOLD_SECONDS:
		_spend(_hold_stat)


func _on_tile_input(event: InputEvent, stat_id: String) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT:
		if mouse.pressed:
			_begin_hold(stat_id)
		else:
			_clear_hold()
		get_viewport().set_input_as_handled()
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_begin_hold(stat_id)
		else:
			_clear_hold()
		get_viewport().set_input_as_handled()


func _begin_hold(stat_id: String) -> void:
	if _player == null or _player.crawler_progress == null \
			or _player.crawler_progress.unspent <= 0:
		return
	if _hold_stat == stat_id and _hold_elapsed > 0.0:
		return
	_clear_hold()
	_hold_stat = stat_id
	_hold_elapsed = 0.0
	_hold_tick_usec = Time.get_ticks_usec()
	_paint_tile(stat_id, true)
	_set_hold_progress(stat_id, 0.0)


func _clear_hold() -> void:
	var stat_id := _hold_stat
	_hold_stat = ""
	_hold_elapsed = 0.0
	if not stat_id.is_empty():
		_set_hold_progress(stat_id, 0.0)


func _set_hold_progress(stat_id: String, amount: float) -> void:
	var tile := _tiles.get(stat_id) as PanelContainer
	if tile == null:
		return
	var fill := tile.find_child("SpendFill", true, false) as ColorRect
	if fill == null:
		return
	var progress := clampf(amount, 0.0, 1.0)
	fill.anchor_right = progress
	fill.visible = progress > 0.001
	fill.color = Color(GREEN, lerpf(0.36, 0.78, progress))


func hold_progress() -> float:
	if _hold_stat.is_empty() or HOLD_SECONDS <= 0.0:
		return 0.0
	return clampf(_hold_elapsed / HOLD_SECONDS, 0.0, 1.0)


func holding_stat() -> String:
	return _hold_stat


func _paint_tile(stat_id: String, hovered: bool, tile: PanelContainer = null) -> void:
	if tile == null:
		tile = _tiles.get(stat_id) as PanelContainer
	if tile == null:
		return
	var rarity := int(tile.get_meta(&"rarity", CrawlerProgress.RARITY_COMMON))
	var accent := CrawlerProgress.rarity_color(rarity)
	if hovered:
		accent = accent.lightened(0.18)
	var fill := Color(accent.r * 0.20, accent.g * 0.16, accent.b * 0.22, 0.90) \
		if hovered else Color(accent.r * 0.10, accent.g * 0.08, accent.b * 0.12, 0.92)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(0)
	box.set_content_margin_all(8)
	tile.add_theme_stylebox_override(&"panel", box)
	var rim := tile.get_node_or_null("RedGlowPanel") as RedGlowPanel
	if rim == null:
		rim = RedGlowPanel.add_to(tile)
		rim.fill_color = Color.TRANSPARENT
		rim.glow_spread = 7.0
		rim.glow_layers = 4
	rim.border_color = Color(accent, 0.95)
	rim.border_width = 2.0 if hovered else 1.5
	rim.glow_intensity = 1.4 if hovered else 1.15


func _fit_label(
		label: Label,
		size: int,
		colour: Color,
		wrap := false,
		lines := 0) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2.ZERO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.max_lines_visible = lines if lines > 0 else (3 if wrap else 1)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap \
		else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", colour)


func _scale_tile_fonts(tile: PanelContainer) -> void:
	if tile == null:
		return
	var host := tile.find_child("SpendHost", true, false) as Control
	if host == null or host.size.y < 8.0:
		return
	var ink := CrawlerProgress.rarity_color(
		int(tile.get_meta(&"rarity", CrawlerProgress.RARITY_COMMON)))
	var tall := host.size.y
	_paint_copy(tile.get_meta(&"title") as Label,
		clampf(tall * 0.22, 28.0, 62.0), ink)
	_paint_copy(tile.get_meta(&"rarity_label") as Label,
		clampf(tall * 0.095, 16.0, 30.0), ink)
	_paint_copy(tile.get_meta(&"boost") as Label,
		clampf(tall * 0.155, 21.0, 45.0), ink)
	_paint_copy(tile.get_meta(&"values") as Label,
		clampf(tall * 0.105, 16.0, 32.0), ink)
	_paint_copy(tile.get_meta(&"blurb") as Label,
		clampf(tall * 0.08, 14.0, 24.0), ink)


func _paint_copy(label: Label, size: float, colour: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override(&"font_size", int(round(size)))
	label.add_theme_color_override(&"font_color", colour)
	var crt := CrtType.host_of(label)
	if crt != null:
		crt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if label.size_flags_vertical & Control.SIZE_EXPAND:
			crt.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _fill_tabs() -> void:
	if _tabs == null:
		return
	for child: Node in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_add_tab_button("Level Up", Tab.SPEND)
	_add_tab_button("Auto Select Prefs", Tab.PREFS)
	_paint_tabs()


func _add_tab_button(label: String, tab: Tab) -> void:
	var button := Button.new()
	button.name = "LevelTab_%s" % ("Spend" if tab == Tab.SPEND else "Prefs")
	button.text = label.to_upper()
	button.custom_minimum_size.y = 34.0
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = false
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(&"font_size", 12)
	button.pressed.connect(func() -> void: show_tab(tab))
	_tabs.add_child(button)


func _paint_tabs() -> void:
	if _tabs == null:
		return
	for child: Node in _tabs.get_children():
		var button := CrtType.inner(child) as Button
		if button == null:
			continue
		var spend := button.name == "LevelTab_Spend"
		var active := (_tab == Tab.SPEND) == spend
		if _prefs_only and spend:
			button.disabled = true
			active = false
		_style_tab(button, active)


func _style_tab(button: Button, active: bool) -> void:
	var accent := GREEN if active else Color(RED, 0.75)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if active \
		else Color(0.08, 0.02, 0.02, 0.9)
	_paint_button(button, accent, fill, active)


func _fill_prefs() -> void:
	if _prefs_page == null:
		return
	for child: Node in _prefs_page.get_children():
		_prefs_page.remove_child(child)
		child.queue_free()
	_pref_boxes.clear()
	var intro := Label.new()
	intro.text = "When auto select is on, it takes the highest rarity match."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override(&"font_size", 13)
	intro.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.72))
	intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prefs_page.add_child(intro)
	for pref_id: String in CrawlerAutoSelect.PREF_ORDER:
		var box := CheckBox.new()
		box.name = "AutoPref_%s" % pref_id
		box.text = "%s  —  %s" % [
			CrawlerAutoSelect.pref_title(pref_id),
			CrawlerAutoSelect.pref_blurb(pref_id),
		]
		box.button_pressed = CrawlerMeta.auto_pref_on(pref_id)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		box.add_theme_font_size_override(&"font_size", 16)
		box.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.92))
		box.add_theme_color_override(&"font_hover_color", GREEN)
		box.add_theme_color_override(&"font_pressed_color", GREEN)
		var chosen := pref_id
		box.toggled.connect(func(on: bool) -> void:
			CrawlerMeta.set_auto_pref(chosen, on)
		)
		_prefs_page.add_child(box)
		_pref_boxes[pref_id] = box


func _refresh_auto() -> void:
	if _auto == null:
		return
	var on := CrawlerMeta.auto_select()
	_auto.text = "%s\nPRESS K TO TOGGLE" % ("AUTO SELECT    ON" if on \
		else "AUTO SELECT    OFF")
	var accent := GREEN if on else Color(RED, 0.75)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if on \
		else Color(0.08, 0.02, 0.02, 0.9)
	_paint_button(_auto, accent, fill, true)


func _on_auto_pressed() -> void:
	if _player != null and _player.has_method(&"toggle_crawler_auto_select"):
		_player.toggle_crawler_auto_select()
	else:
		CrawlerMeta.set_auto_select(not CrawlerMeta.auto_select())
	_refresh_auto()


func _on_auto_key() -> void:
	if CrawlerRules.coop() or _prefs_only:
		close()
		return
	_on_auto_pressed()


func _refresh() -> void:
	var progress := _player.crawler_progress if _player != null else null
	_refresh_auto()
	if progress == null:
		return
	_title.text = "LEVEL %d    %sg" % [progress.level, progress.gold_text()]
	if progress.unspent <= 0 and not _prefs_only:
		close()
		return
	if _prefs_only:
		return
	_sync_tiles(progress)
	_refresh_reroll(progress)
	for stat_id: String in _tiles.keys():
		var tile := _tiles.get(stat_id) as PanelContainer
		if tile == null:
			continue
		var amount := float(tile.get_meta(&"amount", 1.0))
		var rarity := int(tile.get_meta(&"rarity", CrawlerProgress.RARITY_COMMON))
		var rank := progress.rank_of(stat_id)
		var accent := CrawlerProgress.rarity_color(rarity)
		var title := tile.get_meta(&"title") as Label
		var rarity_label := tile.get_meta(&"rarity_label") as Label
		var boost := tile.get_meta(&"boost") as Label
		var values := tile.get_meta(&"values") as Label
		var blurb := tile.get_meta(&"blurb") as Label
		if title != null:
			title.text = CrawlerProgress.stat_title(stat_id).to_upper()
			title.add_theme_color_override(&"font_color", accent)
		if rarity_label != null:
			rarity_label.text = CrawlerProgress.rarity_title(rarity).to_upper()
			rarity_label.add_theme_color_override(&"font_color", accent)
		if boost != null:
			boost.text = CrawlerProgress.offer_boost_text(stat_id, amount, rank)
			boost.add_theme_color_override(&"font_color", accent)
		if values != null:
			values.text = "%s  →  %s" % [
				_preview(progress, stat_id, rank),
				_preview(progress, stat_id, rank + amount),
			]
			values.add_theme_color_override(&"font_color", accent)
		if blurb != null:
			blurb.text = CrawlerProgress.stat_blurb(stat_id)
			blurb.add_theme_color_override(&"font_color", accent)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
	_queue_fonts()


func _sync_tiles(progress: CrawlerProgress) -> void:
	var offers := progress.ensure_level_offers()
	var signature := _offer_signature(offers)
	if signature == _offer_sig and not _tiles.is_empty():
		return
	_clear_hold()
	if _tile_host == null:
		return
	for child: Node in _tile_host.get_children():
		_tile_host.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_offer_sig = signature
	for raw: Variant in offers:
		if raw is Dictionary:
			_tile_host.add_child(_make_tile(raw))


func _offer_signature(offers: Array) -> String:
	var bits: PackedStringArray = PackedStringArray()
	for raw: Variant in offers:
		if raw is Dictionary:
			var offer := raw as Dictionary
			bits.append("%s:%s:%s" % [
				offer.get("id", ""),
				offer.get("rarity", 0),
				offer.get("amount", 0),
			])
	return ",".join(bits)


func _preview(_progress: CrawlerProgress, stat_id: String, rank: float) -> String:
	match stat_id:
		CrawlerProgress.STAT_HEALTH:
			return "%d HP" % int(CrawlerProgress.HEALTH_BASE \
				+ CrawlerProgress.HEALTH_PER_RANK * float(rank))
		CrawlerProgress.STAT_DEXTERITY:
			return "%d%%" % int(round(CrawlerRules.upgrade_scale_f(rank) * 100.0))
		CrawlerProgress.STAT_FLIGHT:
			return "%.1fs" % (CrawlerRules.FLIGHT_SECONDS \
				* CrawlerRules.upgrade_scale_f(rank))
		CrawlerProgress.STAT_DODGE:
			return "%d%%" % int(round(minf(
				CrawlerProgress.DODGE_MAX,
				CrawlerRules.upgrade_boost_f(rank)) * 100.0))
		CrawlerProgress.STAT_DEFENSE:
			return "%d%%" % int(round(minf(
				CrawlerProgress.DEFENSE_MAX,
				CrawlerRules.upgrade_boost_f(rank)) * 100.0))
		CrawlerProgress.STAT_JUKE:
			return "%.2fs" % maxf(
				CrawlerProgress.JUKE_COOLDOWN_MIN,
				CrawlerProgress.JUKE_COOLDOWN_BASE
					- CrawlerProgress.JUKE_COOLDOWN_PER_RANK * float(rank))
		CrawlerProgress.STAT_JUKE_DISTANCE:
			return "%.1fm" % (CrawlerProgress.JUKE_DISTANCE_BASE
				+ CrawlerProgress.JUKE_DISTANCE_PER_RANK * float(rank))
		CrawlerProgress.STAT_DAMAGE:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		CrawlerProgress.STAT_KNOCKBACK:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		CrawlerProgress.STAT_RANGE:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		CrawlerProgress.STAT_ELEMENTAL:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		CrawlerProgress.STAT_CAST:
			return "%.2fs" % CrawlerRules.field_cast_time(
				CrawlerRules.FIELD_CAST,
				CrawlerProgress.CAST_PER_RANK * float(rank))
		CrawlerProgress.STAT_LUCK:
			return "+%.2f" % float(rank)
		CrawlerProgress.STAT_GOLD:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		CrawlerProgress.STAT_XP:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		CrawlerProgress.STAT_GEMS:
			return "%.2fX" % CrawlerRules.upgrade_scale_f(rank)
		_:
			return str(rank)


func _refresh_reroll(progress: CrawlerProgress) -> void:
	if _reroll == null:
		return
	var price := progress.reroll_price()
	var affordable := progress.can_reroll_offers()
	_reroll.text = "REROLL    %dg" % price
	_reroll.disabled = not affordable
	_style_reroll(affordable)


func _style_reroll(enabled: bool) -> void:
	if _reroll == null:
		return
	var accent := GREEN if enabled else Color(RED, 0.55)
	var fill := Color(0.0, 0.15, 0.045, 0.82) if enabled \
		else Color(0.08, 0.02, 0.02, 0.9)
	_paint_button(_reroll, accent, fill, enabled)


func _paint_button(button: Button, accent: Color, fill: Color, thick: bool) -> void:
	if button == null:
		return
	button.clip_contents = false
	button.add_theme_color_override(&"font_color", accent)
	button.add_theme_color_override(&"font_hover_color", GREEN)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))
	button.add_theme_stylebox_override(&"normal", _fill_box(fill))
	var hover := _fill_box(Color(0.0, 0.2, 0.06, 0.88))
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", hover)
	button.add_theme_stylebox_override(&"disabled", _fill_box(Color(0.08, 0.02, 0.02, 0.9)))
	button.add_theme_stylebox_override(&"focus", _fill_box(fill))
	_ensure_rim(button, accent, 2.0 if thick else 1.0)
	_ensure_type(button)


func _fill_box(fill: Color, margin := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color.TRANSPARENT
	box.set_border_width_all(0)
	box.set_content_margin_all(margin)
	return box


func _rim_of(target: Control) -> RedGlowPanel:
	var rim := target.get_node_or_null("RedGlowPanel") as RedGlowPanel
	if rim != null:
		return rim
	var host := CrtType.host_of(target)
	if host != null:
		return host.get_node_or_null("RedGlowPanel") as RedGlowPanel
	return null


func _ensure_rim(target: Control, accent: Color, width := 2.0) -> RedGlowPanel:
	var rim := _rim_of(target)
	if rim == null:
		var host := CrtType.host_of(target)
		if host != null:
			rim = RedGlowPanel.add_to(host)
			host.move_child(rim, host.get_child_count() - 1)
		else:
			rim = RedGlowPanel.add_to(target)
		rim.fill_color = Color.TRANSPARENT
		rim.glow_spread = 6.0
		rim.glow_layers = 3
	rim.show_behind_parent = false
	rim.fill_color = Color.TRANSPARENT
	rim.border_color = Color(accent, 0.95)
	rim.border_width = width
	rim.glow_intensity = 1.15
	rim.glow_spread = 6.0
	return rim


func _ensure_type(button: Button) -> void:
	if button == null or not button.is_inside_tree():
		return
	if CrtType.host_of(button) != null:
		return
	if button.text.strip_edges().is_empty():
		return
	CrtType.dress(button)


func _on_reroll() -> void:
	if _player == null:
		return
	_clear_hold()
	_player.reroll_crawler_offers()


func _spend(stat_id: String) -> void:
	if _player == null or _player.crawler_progress == null:
		return
	_clear_hold()
	_player.spend_crawler_offer(stat_id)
