class_name CrawlerLevelMenu
extends Control

## Modal pause card after a crawler level-up. Hold a stat tile to spend
## the point; a bar fills across the tile while the press is held.

signal closed

const THEME: Theme = preload("res://ui/themes/main_theme.tres")
const RED := Color("ef151f")
const GREEN := Color("39d98a")
const BLACK := Color(0.0, 0.0, 0.0, 0.86)
## Fast enough that a decided pick still feels instant, long enough that a
## click cannot spend by accident. Wall-clock, because the menu pauses time.
const HOLD_SECONDS := 0.12

var _player: OnlinePlayer
var _closing := false
var _title: Label
var _reroll: Button
var _tile_host: GridContainer
var _tiles: Dictionary = {}
var _offer_sig := ""
var _hold_stat := ""
var _hold_elapsed := 0.0
var _hold_tick_usec := 0


func configure(player: OnlinePlayer) -> void:
	_player = player


func _init() -> void:
	name = "CrawlerLevelMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 80


func _ready() -> void:
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_refresh()
	if _player != null and _player.crawler_progress != null \
			and not _player.crawler_progress.changed.is_connected(_refresh):
		_player.crawler_progress.changed.connect(_refresh)


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
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"pause") \
			or event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		if _player != null and _player.crawler_progress != null \
				and _player.crawler_progress.unspent <= 0:
			close()


func close() -> void:
	if _closing:
		return
	if _player != null and _player.crawler_progress != null \
			and _player.crawler_progress.unspent > 0:
		return
	_closing = true
	closed.emit()
	queue_free()


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
	box.border_color = RED
	box.set_border_width_all(3)
	box.shadow_color = Color(RED, 0.35)
	box.shadow_size = 10
	panel.add_theme_stylebox_override(&"panel", box)
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
	_title.add_theme_font_size_override(&"font_size", 22)
	_title.add_theme_color_override(&"font_color", RED)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	var hint := Label.new()
	hint.name = "SpendHint"
	hint.text = "HOLD A TILE TO SPEND"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override(&"font_size", 12)
	hint.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.72))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hint)

	_tile_host = GridContainer.new()
	_tile_host.name = "SpendTiles"
	_tile_host.columns = 2
	_tile_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tile_host.add_theme_constant_override(&"h_separation", 8)
	_tile_host.add_theme_constant_override(&"v_separation", 8)
	_tile_host.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_tile_host)

	_reroll = Button.new()
	_reroll.name = "RerollOffers"
	_reroll.custom_minimum_size.y = 42.0
	_reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reroll.size_flags_vertical = Control.SIZE_SHRINK_END
	_reroll.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_reroll.add_theme_font_size_override(&"font_size", 15)
	_reroll.pressed.connect(_on_reroll)
	_style_reroll(false)
	column.add_child(_reroll)


func _make_tile(offer: Dictionary) -> PanelContainer:
	var stat_id := str(offer.get("id", ""))
	var rarity := int(offer.get("rarity", CrawlerProgress.RARITY_COMMON))
	var tile := PanelContainer.new()
	tile.name = "SpendTile_%s" % stat_id
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(160.0, 118.0)
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
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override(&"separation", 2)
	body.clip_contents = true
	host.add_child(body)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", 8)
	body.add_child(head)

	var title := Label.new()
	title.name = "SpendTitle"
	_fit_label(title, 16, CrawlerProgress.rarity_color(rarity))
	head.add_child(title)

	var rarity_label := Label.new()
	rarity_label.name = "SpendRarity"
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fit_label(rarity_label, 12, CrawlerProgress.rarity_color(rarity))
	rarity_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	head.add_child(rarity_label)

	var boost := Label.new()
	boost.name = "SpendBoost"
	_fit_label(boost, 15, GREEN)
	body.add_child(boost)

	var values := Label.new()
	values.name = "SpendValues"
	_fit_label(values, 13, GREEN, true)
	body.add_child(values)

	var blurb := Label.new()
	blurb.name = "SpendBlurb"
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fit_label(blurb, 12, Color(1, 1, 1, 0.78), true)
	body.add_child(blurb)

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
	box.border_color = accent
	box.set_border_width_all(2 if hovered else 1)
	box.set_content_margin_all(8)
	tile.add_theme_stylebox_override(&"panel", box)


func _fit_label(label: Label, size: int, colour: Color, wrap := false) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2.ZERO
	label.clip_text = true
	label.max_lines_visible = 3 if wrap else 1
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap \
		else TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", colour)


func _refresh() -> void:
	var progress := _player.crawler_progress if _player != null else null
	if progress == null:
		return
	_title.text = "LEVEL %d    %dg" % [progress.level, progress.gold]
	if progress.unspent <= 0:
		close()
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
		var title := tile.find_child("SpendTitle", true, false) as Label
		var rarity_label := tile.find_child("SpendRarity", true, false) as Label
		var boost := tile.find_child("SpendBoost", true, false) as Label
		var values := tile.find_child("SpendValues", true, false) as Label
		var blurb := tile.find_child("SpendBlurb", true, false) as Label
		if title != null:
			title.text = CrawlerProgress.stat_title(stat_id).to_upper()
			title.add_theme_color_override(&"font_color", accent)
		if rarity_label != null:
			rarity_label.text = CrawlerProgress.rarity_title(rarity).to_upper()
			rarity_label.add_theme_color_override(&"font_color", accent)
		if boost != null:
			boost.text = CrawlerProgress.offer_boost_text(stat_id, amount)
		if values != null:
			values.text = "%s  →  %s" % [
				_preview(progress, stat_id, rank),
				_preview(progress, stat_id, rank + amount),
			]
		if blurb != null:
			blurb.text = CrawlerProgress.stat_blurb(stat_id)
		tile.mouse_filter = Control.MOUSE_FILTER_STOP


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
			return "%d%%" % int(round((1.0 + CrawlerProgress.DEX_PER_RANK * float(rank)) * 100.0))
		CrawlerProgress.STAT_FLIGHT:
			return "%.1fs" % (CrawlerRules.FLIGHT_SECONDS \
				* (1.0 + CrawlerProgress.FLIGHT_PER_RANK * float(rank)))
		CrawlerProgress.STAT_DODGE:
			return "%d%%" % int(round(minf(
				CrawlerProgress.DODGE_MAX,
				CrawlerProgress.DODGE_PER_RANK * float(rank)) * 100.0))
		CrawlerProgress.STAT_DEFENSE:
			return "%d%%" % int(round(minf(
				CrawlerProgress.DEFENSE_MAX,
				CrawlerProgress.DEFENSE_PER_RANK * float(rank)) * 100.0))
		CrawlerProgress.STAT_JUKE:
			return "%.2fs" % maxf(
				CrawlerProgress.JUKE_COOLDOWN_MIN,
				CrawlerProgress.JUKE_COOLDOWN_BASE
					- CrawlerProgress.JUKE_COOLDOWN_PER_RANK * float(rank))
		CrawlerProgress.STAT_DAMAGE:
			return "%.2fX" % (1.0 + CrawlerProgress.DAMAGE_PER_RANK * float(rank))
		CrawlerProgress.STAT_KNOCKBACK:
			return "%.2fX" % (1.0 + CrawlerProgress.KNOCKBACK_PER_RANK * float(rank))
		CrawlerProgress.STAT_RANGE:
			return "%.2fX" % (1.0 + CrawlerProgress.RANGE_PER_RANK * float(rank))
		CrawlerProgress.STAT_LUCK:
			return "+%.2f" % float(rank)
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
	_reroll.add_theme_color_override(&"font_color", accent)
	_reroll.add_theme_color_override(&"font_hover_color", GREEN)
	_reroll.add_theme_color_override(&"font_pressed_color", GREEN)
	_reroll.add_theme_color_override(&"font_disabled_color", Color(1, 1, 1, 0.45))
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Color(accent, 0.95)
	box.set_border_width_all(2 if enabled else 1)
	box.set_content_margin_all(8)
	_reroll.add_theme_stylebox_override(&"normal", box)
	var hover := box.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.0, 0.2, 0.06, 0.88)
	hover.border_color = GREEN
	_reroll.add_theme_stylebox_override(&"hover", hover)
	_reroll.add_theme_stylebox_override(&"pressed", hover)
	var dead := box.duplicate() as StyleBoxFlat
	dead.bg_color = Color(0.08, 0.02, 0.02, 0.9)
	dead.border_color = Color(1, 1, 1, 0.28)
	_reroll.add_theme_stylebox_override(&"disabled", dead)


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
