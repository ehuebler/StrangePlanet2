class_name HitLog
extends PanelContainer

## Bottom-right incoming-hit list. Newest row sits on the corner; older rows
## climb and fade so a burst of damage stays readable without covering the
## reticle.

const MARGIN := 12.0
const PAD_X := 8
const PAD_Y := 6
const MAX_ROWS := 7
const HOLD := 7.0
const FADE := 1.4
const LINE_SIZE := 11
const TITLE_SIZE := 8
const WIDTH := 220.0

var _rows: VBoxContainer
var _entries: Array[Dictionary] = []
var _suppressed := false
var _floor_lift := 0.0


func _init() -> void:
	name = "HitLog"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	custom_minimum_size.x = WIDTH


func _ready() -> void:
	RedHudTheme.panel(self)
	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override(&"margin_left", PAD_X)
	padding.add_theme_constant_override(&"margin_right", PAD_X)
	padding.add_theme_constant_override(&"margin_top", PAD_Y)
	padding.add_theme_constant_override(&"margin_bottom", PAD_Y)
	add_child(padding)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	padding.add_child(column)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "HIT LOG"
	RedHudTheme.label(title, TITLE_SIZE)
	title.modulate.a = 0.62
	column.add_child(title)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override(&"separation", 1)
	column.add_child(_rows)


func record(source: String, amount: float, ability := "",
		tags: PackedStringArray = PackedStringArray()) -> void:
	if amount <= 0.0:
		return
	if _rows == null:
		return
	var who := _who(source, ability, tags)
	var row := _make_row(who, amount)
	_rows.add_child(row)
	_entries.append({"row": row, "left": HOLD})
	while _entries.size() > MAX_ROWS:
		_drop(0)
	_refresh_visible()


func lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _rows == null:
		return out
	for child in _rows.get_children():
		if child.has_meta(&"hit_line"):
			out.append(str(child.get_meta(&"hit_line")))
	return out


func has_rows() -> bool:
	return not _entries.is_empty()


func set_suppressed(hidden: bool) -> void:
	_suppressed = hidden
	_refresh_visible()


func set_floor_lift(pixels: float) -> void:
	var next := maxf(pixels, 0.0)
	if is_equal_approx(next, _floor_lift):
		return
	_floor_lift = next
	offset_bottom = -(MARGIN + _floor_lift)


func _process(delta: float) -> void:
	var index := 0
	while index < _entries.size():
		var left := float(_entries[index].get("left", 0.0)) - delta
		_entries[index]["left"] = left
		var row: Variant = _entries[index].get("row")
		if left <= 0.0 or not is_instance_valid(row):
			_drop(index)
			continue
		(row as Control).modulate.a = 1.0 if left >= FADE \
			else clampf(left / FADE, 0.0, 1.0)
		index += 1
	if _entries.is_empty():
		_refresh_visible()


func _make_row(who: String, amount: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 10)
	var name := Label.new()
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.text = who
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RedHudTheme.label(name, LINE_SIZE)
	row.add_child(name)
	var damage := Label.new()
	damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage.text = str(roundi(amount))
	damage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	RedHudTheme.label(damage, LINE_SIZE)
	row.add_child(damage)
	row.set_meta(&"hit_line", "%s  %d" % [who, roundi(amount)])
	return row


func _who(source: String, ability: String,
		tags: PackedStringArray = PackedStringArray()) -> String:
	var named := source.strip_edges()
	if named.is_empty():
		named = ability.strip_edges()
	if named.is_empty():
		named = "Hit"
	if tags.is_empty():
		return named
	return "%s · %s" % [named, " · ".join(tags)]


func _drop(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	var row: Variant = _entries[index].get("row")
	_entries.remove_at(index)
	if is_instance_valid(row):
		(row as Node).queue_free()


func _refresh_visible() -> void:
	visible = not _suppressed and not _entries.is_empty()
