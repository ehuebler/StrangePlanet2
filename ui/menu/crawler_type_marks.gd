class_name CrawlerTypeMarks
extends RefCounted

## Shared type-icon strip for store tiles and selected-item descriptions.


static func make_row(node_name: String, types: PackedStringArray,
		edge := 22.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override(&"separation", 4)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fill(row, types, edge)
	return row


static func fill(row: Control, types: PackedStringArray, edge := 22.0) -> void:
	if row == null:
		return
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	row.visible = not types.is_empty()
	for type_id: String in types:
		var icon := CrawlerCatalog.type_icon(type_id)
		if icon == null:
			continue
		var mark := TextureRect.new()
		mark.name = "TypeMark_%s" % type_id
		mark.texture = icon
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2.ONE * edge
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.tooltip_text = CrawlerCatalog.type_title(type_id)
		row.add_child(mark)
	if row.get_child_count() <= 0:
		row.visible = false
