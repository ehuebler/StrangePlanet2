class_name StatusChipLayer
extends Control

## Upper-right stack of transient combat statuses, positioned below a
## [CoordinatePlate].

const GAP := 4.0

var _chips: Dictionary = {}


func _init() -> void:
	name = "StatusChipLayer"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	offset_left = -188.0
	offset_right = -CoordinatePlate.MARGIN
	offset_top = CoordinatePlate.MARGIN
	offset_bottom = -CoordinatePlate.MARGIN


func _ready() -> void:
	var column := VBoxContainer.new()
	column.name = "ChipColumn"
	column.add_theme_constant_override(&"separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(column)


func sync_rows(rows: Array) -> void:
	var column := get_child(0) as VBoxContainer
	var seen: Dictionary = {}
	for row_variant: Variant in rows:
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var id := StringName(row.get("id", &""))
		if id.is_empty():
			continue
		seen[id] = true
		var chip: StatusChip = _chips.get(id, null)
		if chip == null:
			chip = StatusChip.new()
			chip.name = "Chip_%s" % String(id)
			chip.maximum = float(row.get("remaining", 1.0))
			column.add_child(chip)
			_chips[id] = chip
		chip.apply_row(row)
	for id_variant: Variant in _chips.keys():
		var id := StringName(id_variant)
		if seen.has(id):
			continue
		var chip: StatusChip = _chips[id]
		column.remove_child(chip)
		chip.queue_free()
		_chips.erase(id)


func place_below(plate: Control) -> void:
	if plate == null:
		return
	offset_top = plate.offset_top + plate.size.y + GAP


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and get_child_count() > 0:
		var column := get_child(0) as VBoxContainer
		if column != null:
			column.size.x = size.x
