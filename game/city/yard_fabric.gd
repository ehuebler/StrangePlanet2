extends "res://game/city/patch_fabric.gd"

## Street and lot packing that leaves MeshMaker plot / yard space.
##
## Lots are the full plot (hull plus yard), not the old curb-hugging footprint.
## The GLB already contains the flat yard, so the lot sits against the street
## clearance and the yard is the buffer between hull and pavement.

const YardCatalog := preload("res://game/city/yard_building_catalog.gd")


func build(
		plan: PatchCityGenerator.Plan,
		buckets: Dictionary,
		pad_cell: float,
		up: Vector3,
		east: Vector3,
		north: Vector3,
		radius: float,
		arteries: Dictionary = {}
	) -> Dictionary:
	var result := super.build(plan, buckets, pad_cell, up, east, north, radius, arteries)
	_stamp_yards()
	_assign_yard_designs()
	return result


func refill_leftovers(arteries: Dictionary) -> Array:
	var lots := super.refill_leftovers(arteries)
	_stamp_yards()
	_assign_yard_designs()
	return lots


func _row_depth_target(ceiling: int, packed: bool, tight: bool) -> float:
	if tight:
		return clampf(_cell * 4.2, 14.0, 18.0)
	if packed or ceiling >= TYPE_TOWER:
		return clampf(_cell * 8.4, 28.0, 44.0)
	return clampf(_cell * 5.6, 18.0, 26.0)


func _lot_width(density: float, ceiling: int, tight := false, rim := false, core := false) -> float:
	if tight:
		return clampf(lerpf(13.5, 10.0, density), 9.5, 14.5)
	if rim:
		return clampf(lerpf(26.0, 18.0, density), 16.0, 28.0)
	if core:
		return clampf(lerpf(38.0, 28.0, density), 24.0, 42.0)
	var width := lerpf(24.0, 16.0, density)
	if ceiling >= TYPE_SHOP:
		width = lerpf(34.0, 24.0, density)
	if ceiling >= TYPE_SKY:
		width = lerpf(50.0, 36.0, density)
	return clampf(width, 14.0, 54.0)


func _coverage(_typology: int, _packed: bool, _nudge: float, _tight := false) -> float:
	return 0.94


func _style_lot(row: Dictionary) -> void:
	super._style_lot(row)
	_apply_plot(row)


func _style_infill_lot(row: Dictionary) -> void:
	super._style_infill_lot(row)
	_apply_plot(row)


func _yard_margin(typology: int) -> float:
	match typology:
		TYPE_HOUSE:
			return 6.0
		TYPE_TOWNHOUSE:
			return 2.1
		TYPE_APARTMENT, TYPE_SHOP:
			return 6.0
		TYPE_TOWER:
			return 9.0
		_:
			return 12.0


func _apply_plot(row: Dictionary) -> void:
	var typology := int(row.get("typology", TYPE_HOUSE))
	var margin := _yard_margin(typology)
	var span_t := maxf(absf(float(row.get("t_max", 0.0)) - float(row.get("t_min", 0.0))), _cell)
	var width := maxf(float(row.get("width", _cell)), _cell)
	var depth := maxf(span_t * 0.94, _cell * 2.8)
	depth = minf(depth, maxf(span_t - 0.4, _cell * 2.0))
	if typology >= TYPE_SKY:
		width = minf(maxf(width, 34.0), 58.0)
		depth = minf(maxf(depth, 34.0), 58.0)
	elif typology >= TYPE_TOWER:
		width = minf(maxf(width, 26.0), 48.0)
		depth = minf(maxf(depth, 26.0), 48.0)
	row["width"] = width
	row["depth"] = depth
	row["plot_margin"] = margin
	row["yard"] = true
	row["coverage"] = 0.94
	var axis: Vector2 = row.get("across_axis", row["across"])
	var along: Vector2 = row["along"]
	if along.length_squared() < 0.0001:
		return
	along = along.normalized()
	if axis.length_squared() < 0.0001:
		axis = Vector2(-along.y, along.x)
	var s := along.dot(row["centre"])
	var t_mid := (float(row.get("t_min", 0.0)) + float(row.get("t_max", 0.0))) * 0.5
	row["centre"] = along * s + axis * t_mid


func _stamp_yards() -> void:
	for lot in _lots:
		if not bool(lot.get("yard", false)):
			_apply_plot(lot)


func _assign_yard_designs() -> void:
	YardCatalog.ensure()
	if YardCatalog.count() <= 0:
		return
	for lot in _lots:
		var row: Dictionary = lot
		var picked := YardCatalog.pick_for_lot(row, _rng.randi())
		if picked.is_empty():
			continue
		row["design"] = String(picked.get("id", ""))
		row["plot_margin"] = float(picked.get("plot_margin_m", row.get("plot_margin", 6.0)))
		row["yard_rot90"] = bool(picked.get("yard_rot90", false))
		row["walkable"] = false
