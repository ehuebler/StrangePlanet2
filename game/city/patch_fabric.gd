extends RefCounted

const BuildingCatalog := preload("res://game/city/city_building_catalog.gd")

## Streets, alleys and lots for one paved city, in the city's UV metre frame.
##
## Arterials join the highway exits and a spine; local streets recursively
## split the leftover into blocks; alleys bisect the bigger commercial ones.
## Lots fill every remaining cell, facing the nearest street rather than a
## shared compass, so neighbouring blocks do not all sit on the same heading.

const RANK_ARTERIAL := 0
const RANK_LOCAL := 1
const RANK_ALLEY := 2

const TYPE_HOUSE := 0
const TYPE_TOWNHOUSE := 1
const TYPE_APARTMENT := 2
const TYPE_SHOP := 3
const TYPE_TOWER := 4
const TYPE_SKY := 5
const TYPE_LANDMARK := 6
const TYPE_TOWN_CENTER := 7

const TYPE_NAME: PackedStringArray = [
	"House", "Townhouse", "Apartment", "Shop", "Tower", "Skyscraper", "Hall", "Town Center",
]

const STEMS: PackedStringArray = [
	"Oak", "Cedar", "Harbor", "Market", "River", "Hill", "Pine", "Stone",
	"Anchor", "Lantern", "Quay", "Meadow", "Cliff", "Dune", "Forge", "Canal",
	"Bramble", "Cove", "Ember", "Flint", "Gull", "Hearth", "Iris", "Jute",
]

const STREET_WORD: PackedStringArray = [
	"Street", "Avenue", "Way", "Row", "Lane",
]

const ARTERIAL_HALF := 4.4
const LOCAL_HALF := 3.1
const ALLEY_HALF := 1.6
const HOUSE_ARTERIAL_HALF := 3.15
const HOUSE_LOCAL_HALF := 2.05
const HOUSE_ALLEY_HALF := 1.15
const STORY := 3.15
const ROAD_CLEAR := 2.2
const MIN_FOOTPRINT := 8.0
const MIN_INRADIUS := 1.55
const VARIANT_RECT := 0
const VARIANT_CYLINDER := 1
const VARIANT_RECT_CAP := 2
const VARIANT_GABLE := 3
const VARIANT_ROUND_END := 4
const VARIANT_TAPER := 5
const VARIANT_POINT_HALF := 6
const VARIANT_SLANT_HALF := 7
const VARIANT_CYL_HALF := 8

var _cell := 4.0
var _rng := RandomNumberGenerator.new()
var _owner: Dictionary = {}
var _roads: Dictionary = {}
var _tangents: Dictionary = {}
var _ranks: Dictionary = {}
var _streets: Array = []
var _lots: Array = []
var _taken: Dictionary = {}
var _street_serial := 0
var _building_serial := 0
var _district_area: Dictionary = {}
var _district_centre: Dictionary = {}
var _district_name: Dictionary = {}
var _city_name := ""
var _fill_jobs: Array = []
var _junctions: Array = []
var _tight_house_used := false
var _district_special: Dictionary = {}


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
	_cell = maxf(pad_cell, 3.2)
	_owner.clear()
	_roads.clear()
	_tangents.clear()
	_ranks.clear()
	_streets.clear()
	_lots.clear()
	_taken.clear()
	_street_serial = 0
	_building_serial = 0
	_district_area.clear()
	_district_centre.clear()
	_district_name.clear()
	_fill_jobs.clear()
	_junctions.clear()
	_tight_house_used = false
	_district_special.clear()
	_city_name = plan.patch_name
	_rng.seed = hash([plan.patch_id, plan.patch_name, plan.districts.size()])
	if plan == null or buckets.is_empty():
		return {"streets": [], "lots": []}
	for district_id in buckets:
		var cells: Dictionary = buckets[district_id]
		for key in cells:
			_owner[key] = int(district_id)
	var downtown := _pick_downtown(plan, buckets, up, east, north, radius)
	for district in plan.districts:
		var cells: Dictionary = buckets.get(district.id, {})
		if cells.size() < 8:
			continue
		_layout_district(plan, district, cells, downtown, up, east, north, radius)
	_clip_streets_to_pad()
	_cut_streets_off_highway(arteries)
	_knit_intersections()
	_cut_streets_off_highway(arteries)
	_drop_highway_junctions(arteries)
	_drop_lonely_junctions()
	_restamp_roads()
	_mark_midrise_jobs()
	for job in _fill_jobs:
		var row: Dictionary = job
		_fill_lots(
			int(row["id"]),
			row["cells"],
			row["centre"],
			float(row["density"]),
			int(row["ceiling"]),
			float(row["area"]),
			int(row["exits"]))
	_smooth_lots()
	_apply_typology()
	_place_district_marks()
	_place_town_center()
	_pack_medium_apartments()
	_clip_lots(arteries)
	_clip_lots_to_pad(arteries)
	_place_mega_towers()
	_ensure_district_marks()
	_taper_skyline()
	_infill_leftover_lots(arteries)
	_name_lots()
	_record_buildings()
	return {
		"streets": _streets,
		"lots": _lots,
		"arteries": arteries,
		"junctions": _junctions,
	}


func take_lots(lots: Array) -> void:
	_lots = lots


func refill_leftovers(arteries: Dictionary) -> Array:
	_infill_leftover_lots(arteries)
	_ensure_district_marks()
	_name_lots()
	_record_buildings()
	return _lots


func _pick_downtown(
		plan: PatchCityGenerator.Plan,
		buckets: Dictionary,
		up: Vector3,
		east: Vector3,
		north: Vector3,
		radius: float
	) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -1.0
	for district in plan.districts:
		var cells: Dictionary = buckets.get(district.id, {})
		if cells.is_empty():
			continue
		var centre := _to_uv(district.centre, up, east, north, radius)
		var exits := _exits_of(plan, district.id, cells, up, east, north, radius).size()
		var area := float(cells.size()) * _cell * _cell
		var score := area * (1.0 + float(exits)) / (1.0 + centre.length() * 0.002)
		if score > best_score:
			best_score = score
			best = centre
	return best


func _layout_district(
		plan: PatchCityGenerator.Plan,
		district: PatchCityGenerator.District,
		cells: Dictionary,
		downtown: Vector2,
		up: Vector3,
		east: Vector3,
		north: Vector3,
		radius: float
	) -> void:
	var area := float(cells.size()) * _cell * _cell
	var centre := _to_uv(district.centre, up, east, north, radius)
	_district_area[district.id] = area
	_district_centre[district.id] = centre
	_district_name[district.id] = district.name
	var exits := _exits_of(plan, district.id, cells, up, east, north, radius)
	var neighbors := _neighbor_count(district.id, cells)
	var density := _density_score(area, centre, downtown, exits.size(), neighbors)
	var ceiling := _typology_ceiling(area, exits.size())
	var tight := _want_tight_houses(ceiling, density)
	if tight:
		ceiling = maxi(ceiling, TYPE_SHOP)
	var min_block := _min_block_area(area, density)
	if tight:
		min_block = clampf(min_block * 0.28, 280.0, 640.0)
	elif ceiling >= TYPE_TOWER:
		min_block = clampf(min_block * 0.58, 640.0, 1500.0)
	_carve_skeleton(district.id, cells, centre, exits, area, density, tight)
	_split_blocks(district.id, cells, min_block, density, 0, tight)
	_carve_alleys(district.id, cells, density, ceiling, min_block, tight)
	_fill_jobs.append({
		"id": district.id,
		"cells": cells,
		"centre": centre,
		"density": density,
		"ceiling": ceiling,
		"area": area,
		"exits": exits.size(),
		"tight": tight,
	})


func _density_score(
		area: float,
		centre: Vector2,
		downtown: Vector2,
		exits: int,
		neighbors: int
	) -> float:
	var proximity := 1.0 / (1.0 + centre.distance_to(downtown) / 380.0)
	var size_term := 1.0 / (1.0 + exp(-(log(maxf(area, 80.0)) - log(9000.0)) / 0.55))
	var connect := clampf(0.18 + float(exits) * 0.22 + float(neighbors) * 0.10, 0.18, 1.0)
	var score := proximity * size_term * connect
	if exits <= 0:
		if area < 28000.0:
			score = minf(score, 0.22)
		else:
			score = minf(score, 0.38)
	return clampf(score, 0.08, 1.0)


func _is_house_district(ceiling: int, density: float) -> bool:
	if ceiling <= TYPE_TOWNHOUSE:
		return true
	return ceiling <= TYPE_APARTMENT and density * 5.15 < 1.70


func _want_tight_houses(ceiling: int, density: float) -> bool:
	if not _is_house_district(ceiling, density):
		return false
	_tight_house_used = true
	return true


func _mark_midrise_jobs() -> void:
	var skyline: Dictionary = {}
	for id in _skyline_districts():
		skyline[int(id)] = true
	for job in _fill_jobs:
		var row: Dictionary = job
		var id := int(row["id"])
		var area := float(row["area"])
		var ceiling: int = int(row["ceiling"])
		row["midrise"] = (not bool(row.get("tight", false))) \
			and (not skyline.has(id)) \
			and ceiling >= TYPE_APARTMENT \
			and area >= 8000.0


func _typology_ceiling(area: float, exits: int) -> int:
	if area <= 4200.0:
		return TYPE_TOWNHOUSE
	if area <= 16000.0:
		return TYPE_APARTMENT
	if area <= 52000.0:
		return TYPE_SHOP
	if exits >= 3:
		return TYPE_SKY
	return TYPE_TOWER


func _min_block_area(area: float, density: float) -> float:
	var base := lerpf(3000.0, 1180.0, density)
	base *= clampf(1.12 - area / 140000.0, 0.70, 1.12)
	return clampf(base, 900.0, 3600.0)


func _district_half(rank: int, tight: bool) -> float:
	if not tight:
		match rank:
			RANK_ARTERIAL:
				return ARTERIAL_HALF
			RANK_ALLEY:
				return ALLEY_HALF
			_:
				return LOCAL_HALF
	match rank:
		RANK_ARTERIAL:
			return HOUSE_ARTERIAL_HALF
		RANK_ALLEY:
			return HOUSE_ALLEY_HALF
		_:
			return HOUSE_LOCAL_HALF


func _carve_skeleton(
		district_id: int,
		cells: Dictionary,
		centre: Vector2,
		exits: PackedVector2Array,
		area: float,
		density: float,
		tight := false
	) -> void:
	if exits.size() <= 0:
		_carve_isolated(district_id, cells, centre, area, tight)
		return
	var nodes := PackedVector2Array()
	nodes.append(centre)
	for point in exits:
		nodes.append(point)
	var links := _mst(nodes)
	if area > 22000.0 and nodes.size() >= 4:
		var extra := _longest_unused(nodes, links)
		if extra.x >= 0:
			links.append(extra)
	var wander := 8.0 if tight else 16.0
	var half := _district_half(RANK_ARTERIAL, tight)
	for link in links:
		var a: Vector2 = nodes[link.x]
		var b: Vector2 = nodes[link.y]
		var path := _jitter_path(a, b, wander)
		_stamp_and_record(district_id, cells, path, RANK_ARTERIAL, half, density)


func _carve_isolated(
		district_id: int,
		cells: Dictionary,
		centre: Vector2,
		area: float,
		tight := false
	) -> void:
	var box := _bounds(cells)
	var inset := Vector2(maxf((box.z - box.x) * 0.22, _cell * 3.0),
		maxf((box.w - box.y) * 0.22, _cell * 3.0))
	var loop := PackedVector2Array()
	loop.append(Vector2(box.x + inset.x, box.y + inset.y))
	loop.append(Vector2(box.z - inset.x, box.y + inset.y))
	loop.append(Vector2(box.z - inset.x, box.w - inset.y))
	loop.append(Vector2(box.x + inset.x, box.w - inset.y))
	loop.append(loop[0])
	if area > 3500.0:
		_stamp_and_record(
			district_id, cells, loop, RANK_ARTERIAL,
			_district_half(RANK_ARTERIAL, tight) * 0.9, 0.2)
	var stub := PackedVector2Array()
	stub.append(centre)
	stub.append(Vector2(box.z - inset.x * 0.35, centre.y + _rng.randf_range(-18.0, 18.0)))
	_stamp_and_record(
		district_id, cells, stub, RANK_LOCAL, _district_half(RANK_LOCAL, tight), 0.2)


func _split_blocks(
		district_id: int,
		cells: Dictionary,
		min_block: float,
		density: float,
		depth: int,
		tight := false
	) -> void:
	if depth > 10:
		return
	var min_cells := maxi(8 if tight else 10, int(ceili(min_block / (_cell * _cell))))
	var blobs := _components(_open_cells(district_id, cells))
	var splits := 0
	for blob in blobs:
		var block: Dictionary = blob
		if block.size() < min_cells:
			continue
		if splits + _street_count(district_id) > 90:
			break
		if not _split_one(district_id, cells, block, density, tight):
			continue
		splits += 1
	if splits > 0:
		_split_blocks(district_id, cells, min_block, density, depth + 1, tight)


func _split_one(
		district_id: int,
		cells: Dictionary,
		block: Dictionary,
		density: float,
		tight := false
	) -> bool:
	var box := _bounds(block)
	var wide := box.z - box.x
	var tall := box.w - box.y
	if wide < _cell * 4.0 and tall < _cell * 4.0:
		return false
	var along_x := wide >= tall
	var ratio := 0.5 if tight else _rng.randf_range(0.36, 0.46)
	if not tight and _rng.randf() > 0.5:
		ratio = 1.0 - ratio
	var angle := 0.0 if tight else _rng.randf_range(-0.16, 0.16)
	var cx := (box.x + box.z) * 0.5
	var cy := (box.y + box.w) * 0.5
	var path := PackedVector2Array()
	if along_x:
		var x0 := box.x + wide * ratio
		path.append(Vector2(x0 + (box.y - cy) * tan(angle), box.y))
		path.append(Vector2(x0 + (box.w - cy) * tan(angle), box.w))
	else:
		var y0 := box.y + tall * ratio
		path.append(Vector2(box.x, y0 + (box.x - cx) * tan(angle)))
		path.append(Vector2(box.z, y0 + (box.z - cx) * tan(angle)))
	path = _clip_to_block(path, block)
	if path.size() < 2:
		return false
	path = _extend_to_road(district_id, cells, path)
	_stamp_and_record(
		district_id, cells, path, RANK_LOCAL, _district_half(RANK_LOCAL, tight), density)
	return true


func _carve_alleys(
		district_id: int,
		cells: Dictionary,
		density: float,
		ceiling: int,
		min_block: float,
		tight := false
	) -> void:
	if not tight and ceiling < TYPE_TOWER and (density < 0.42 or ceiling < TYPE_APARTMENT):
		return
	var need := maxi(18, int(ceili(maxf(min_block, 2000.0) * 1.15 / (_cell * _cell))))
	if tight:
		need = maxi(7, int(ceili(maxf(min_block, 700.0) * 0.72 / (_cell * _cell))))
	elif ceiling >= TYPE_TOWER:
		need = maxi(12, int(ceili(maxf(min_block, 1400.0) * 0.90 / (_cell * _cell))))
	for blob in _components(_open_cells(district_id, cells)):
		var block: Dictionary = blob
		if block.size() < need:
			continue
		_split_alley(district_id, cells, block, tight)


func _split_alley(
		district_id: int,
		cells: Dictionary,
		block: Dictionary,
		tight := false
	) -> void:
	var box := _bounds(block)
	var along_x := (box.z - box.x) >= (box.w - box.y)
	var path := PackedVector2Array()
	var drift := 0.0 if tight else _rng.randf_range(-_cell, _cell)
	if along_x:
		var x0 := (box.x + box.z) * 0.5 + drift
		path.append(Vector2(x0, box.y))
		path.append(Vector2(x0, box.w))
	else:
		var y0 := (box.y + box.w) * 0.5 + drift
		path.append(Vector2(box.x, y0))
		path.append(Vector2(box.z, y0))
	path = _clip_to_block(path, block)
	if path.size() < 2:
		return
	path = _extend_to_road(district_id, cells, path)
	_stamp_and_record(
		district_id, cells, path, RANK_ALLEY, _district_half(RANK_ALLEY, tight), 0.5)


func _fill_lots(
		district_id: int,
		cells: Dictionary,
		centre: Vector2,
		density: float,
		ceiling: int,
		area: float,
		exits: int
	) -> void:
	var packed := exits <= 0 or area < 18000.0
	var coverage_nudge := 0.12 if packed else 0.05
	var tight := false
	var midrise := false
	for job in _fill_jobs:
		var row: Dictionary = job
		if int(row["id"]) == district_id:
			tight = bool(row.get("tight", false))
			midrise = bool(row.get("midrise", false))
			break
	if tight:
		packed = true
		coverage_nudge = maxf(coverage_nudge, 0.24)
	if ceiling >= TYPE_TOWER:
		packed = true
		coverage_nudge = maxf(coverage_nudge, 0.16)
	if midrise:
		packed = true
		coverage_nudge = maxf(coverage_nudge, 0.14)
	for blob in _components(_open_cells(district_id, cells)):
		var block: Dictionary = blob
		if block.size() < 3:
			continue
		_lots_from_block(
			district_id, block, centre, density, ceiling, coverage_nudge, packed, tight, midrise)


func _lots_from_block(
		district_id: int,
		block: Dictionary,
		centre: Vector2,
		density: float,
		ceiling: int,
		coverage_nudge: float,
		packed: bool,
		tight := false,
		midrise := false
	) -> void:
	var mid := _centroid(block)
	var face := _nearest_tangent(mid)
	if face.length_squared() < 0.01:
		face = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	face = face.normalized()
	var across := Vector2(-face.y, face.x)
	var span_along := 0.0
	var span_across := 0.0
	var min_s := 1.0e9
	var max_s := -1.0e9
	var min_t := 1.0e9
	var max_t := -1.0e9
	for key in block:
		var at := _cell_uv(key)
		var s := at.dot(face)
		var t := at.dot(across)
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)
		min_t = minf(min_t, t)
		max_t = maxf(max_t, t)
	span_along = maxf(max_s - min_s, _cell)
	span_across = maxf(max_t - min_t, _cell)
	var local := density * (0.52 + 0.48 * exp(-mid.distance_to(centre) / maxf(span_along, 40.0)))
	if _near_arterial(mid):
		local = minf(local * 1.16, 1.0)
	var rim := ceiling >= TYPE_TOWER and mid.distance_to(centre) > 52.0
	if rim:
		packed = true
	var core := midrise and mid.distance_to(centre) < 82.0
	if core:
		packed = true
	var breaks := _row_breaks(min_t, max_t, _row_depth_target(ceiling, packed, tight))
	var fill_pack := packed or breaks.size() > 2
	for index in range(breaks.size() - 1):
		_emit_strip_lots(
			district_id, face, across, min_s, max_s, breaks[index], breaks[index + 1],
			local, ceiling, coverage_nudge, fill_pack, tight, rim, core, false)


func _row_depth_target(ceiling: int, packed: bool, tight: bool) -> float:
	if tight:
		return clampf(_cell * 2.35, 8.4, 11.0)
	if packed or ceiling >= TYPE_TOWER:
		return clampf(_cell * 3.4, 12.5, 16.5)
	return clampf(_cell * 2.7, 10.0, 13.5)


func _row_breaks(min_t: float, max_t: float, target: float) -> PackedFloat32Array:
	var span := maxf(max_t - min_t, _cell)
	var n := maxi(1, int(round(span / maxf(target, _cell * 2.0))))
	while n > 1 and span / float(n) < _cell * 1.85:
		n -= 1
	n = mini(n, 5)
	var out := PackedFloat32Array()
	out.resize(n + 1)
	for index in n + 1:
		out[index] = lerpf(min_t, max_t, float(index) / float(n))
	return out


func _emit_strip_lots(
		district_id: int,
		face: Vector2,
		across: Vector2,
		min_s: float,
		max_s: float,
		min_t: float,
		max_t: float,
		local: float,
		ceiling: int,
		coverage_nudge: float,
		packed: bool,
		tight: bool,
		rim: bool,
		core: bool,
		infill: bool
	) -> void:
	var span_across := maxf(max_t - min_t, _cell)
	var lot_w := _lot_width(local, ceiling, tight, rim, core)
	if infill:
		lot_w = clampf(lot_w * 0.78, maxf(_cell * 1.25, 5.4), minf(lot_w, 11.5))
	var cursor := min_s
	while cursor < max_s - _cell * 0.4:
		var width := lot_w
		if not tight:
			var jitter := lot_w * _rng.randf_range(-0.08, 0.08) if (rim or core) \
				else lot_w * _rng.randf_range(-0.20, 0.20)
			width = clampf(
				lot_w + jitter,
				lot_w * 0.72 if (rim or core) else lot_w * 0.62,
				lot_w * 1.18 if (rim or core) else lot_w * 1.38)
		var next := minf(cursor + width, max_s)
		var strip_w := next - cursor
		if strip_w < _cell * 0.8:
			break
		var lot_mid_s := (cursor + next) * 0.5
		var lot_centre := face * lot_mid_s + across * ((min_t + max_t) * 0.5)
		var corner := _is_corner(lot_centre)
		if corner and not tight and not rim and not core and not infill:
			width = minf(width * 1.38, (max_s - cursor) * 0.9)
			next = minf(cursor + width, max_s)
			strip_w = next - cursor
			lot_mid_s = (cursor + next) * 0.5
			lot_centre = face * lot_mid_s + across * ((min_t + max_t) * 0.5)
		var depth := span_across
		if not packed and not infill:
			depth = maxf(span_across * _rng.randf_range(0.72, 1.0), _cell * 2.0)
		var toward_street := across
		if _road_side(lot_centre, across) < 0.0:
			toward_street = -across
		var lot := {
			"centre": lot_centre,
			"along": face,
			"across": toward_street,
			"across_axis": across,
			"t_min": min_t,
			"t_max": max_t,
			"width": strip_w,
			"depth": depth,
			"density": local,
			"ceiling": ceiling,
			"district_id": district_id,
			"nudge": coverage_nudge,
			"packed": packed or infill,
			"tight": tight,
			"rim": rim,
			"midrise_core": core,
			"infill": infill,
			"typology": TYPE_HOUSE,
			"stories": 1.0,
			"name": "",
			"street_name": _nearest_street_name(lot_centre),
		}
		_lots.append(lot)
		cursor = next


func _smooth_lots() -> void:
	if _lots.size() < 2:
		return
	var bins: Dictionary = {}
	for index in _lots.size():
		var here: Vector2 = (_lots[index] as Dictionary)["centre"]
		var key := Vector2i(int(floor(here.x / 40.0)), int(floor(here.y / 40.0)))
		var bucket: Array = bins.get(key, [])
		bucket.append(index)
		bins[key] = bucket
	for _round in 2:
		var next: PackedFloat32Array = PackedFloat32Array()
		next.resize(_lots.size())
		for index in _lots.size():
			var lot: Dictionary = _lots[index]
			var acc := float(lot["density"])
			var weight := 1.0
			var here: Vector2 = lot["centre"]
			var home := Vector2i(int(floor(here.x / 40.0)), int(floor(here.y / 40.0)))
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var bucket: Array = bins.get(Vector2i(home.x + ox, home.y + oy), [])
					for other_i in bucket:
						if int(other_i) == index:
							continue
						var other: Dictionary = _lots[other_i]
						var away: float = here.distance_to(other["centre"])
						if away > 48.0:
							continue
						var w := 1.0 - away / 48.0
						acc += float(other["density"]) * w
						weight += w
			next[index] = acc / weight
		for index in _lots.size():
			(_lots[index] as Dictionary)["density"] = next[index]


func _apply_typology() -> void:
	for lot in _lots:
		_style_lot(lot)


func _style_lot(row: Dictionary) -> void:
	if bool(row.get("infill", false)):
		_style_infill_lot(row)
		return
	var density := float(row["density"])
	var ceiling: int = int(row["ceiling"])
	var packed: bool = bool(row["packed"])
	var nudge := float(row["nudge"])
	var bucket := density * 5.15
	var typology := TYPE_HOUSE
	if bucket >= 4.25:
		typology = TYPE_SKY
	elif bucket >= 3.45:
		typology = TYPE_TOWER
	elif bucket >= 2.70:
		typology = TYPE_SHOP
	elif bucket >= 1.70:
		typology = TYPE_APARTMENT
	elif bucket >= 0.92:
		typology = TYPE_TOWNHOUSE
	typology = mini(typology, ceiling)
	if packed and typology >= TYPE_TOWER and float(row["width"]) < 9.0:
		if bool(row.get("rim", false)):
			typology = TYPE_SHOP
		elif bool(row.get("tight", false)):
			typology = TYPE_SHOP if typology == TYPE_SHOP else TYPE_TOWNHOUSE
		else:
			typology = mini(typology, TYPE_TOWNHOUSE)
	elif packed and typology > TYPE_TOWNHOUSE and float(row["width"]) < 9.0:
		if bool(row.get("tight", false)) or bool(row.get("rim", false)) \
				or bool(row.get("midrise_core", false)):
			typology = mini(typology, TYPE_SHOP)
		else:
			typology = mini(typology, TYPE_TOWNHOUSE)
	row["typology"] = typology
	var cover := _coverage(typology, packed, nudge, bool(row.get("tight", false)))
	if bool(row.get("rim", false)):
		cover = maxf(cover, 0.74)
	var stories := _stories(typology)
	row["stories"] = stories
	var width := maxf(float(row["width"]) * clampf(sqrt(cover / 0.62), 0.72, 1.12), _cell)
	var depth := maxf(float(row["depth"]) * cover, _cell * 1.6)
	var span_t := maxf(absf(float(row.get("t_max", 0.0)) - float(row.get("t_min", 0.0))), _cell)
	var max_depth := maxf(span_t - 1.6, _cell * 1.4)
	depth = minf(depth, max_depth)
	if typology == TYPE_SKY:
		width = minf(width, 28.0)
		depth = minf(depth, 28.0)
	if typology >= TYPE_TOWER and not bool(row.get("rim", false)):
		var lo := 16.0 if typology >= TYPE_SKY else 14.0
		var cap := minf(24.0, maxf(minf(width, depth), _cell * 2.0))
		var span := clampf((width + depth) * 0.5, minf(lo, cap), cap)
		width = span
		depth = span
	row["width"] = width
	row["depth"] = depth
	row["coverage"] = cover
	var axis: Vector2 = row.get("across_axis", row["across"])
	var along: Vector2 = row["along"]
	var toward: Vector2 = row["across"]
	var s := along.dot(row["centre"])
	if packed:
		var t_mid := (float(row["t_min"]) + float(row["t_max"])) * 0.5
		row["centre"] = along * s + axis * t_mid
		return
	var t_front := float(row.get("t_mid", 0.0))
	if toward.dot(axis) > 0.0:
		t_front = float(row["t_max"]) - 1.0 - depth * 0.5
	else:
		t_front = float(row["t_min"]) + 1.0 + depth * 0.5
	row["centre"] = along * s + axis * t_front


func _style_infill_lot(row: Dictionary) -> void:
	var width := maxf(float(row.get("width", _cell)), _cell)
	var depth := maxf(float(row.get("depth", _cell)), _cell)
	var area := width * depth
	var short := minf(width, depth)
	var ceiling: int = int(row.get("ceiling", TYPE_HOUSE))
	var typology := TYPE_HOUSE
	if area >= 520.0 and short >= 16.0:
		typology = TYPE_TOWER if (ceiling >= TYPE_TOWER or area >= 720.0) else TYPE_APARTMENT
	elif area >= 220.0 and short >= 10.0:
		typology = TYPE_APARTMENT if _rng.randf() < 0.62 else TYPE_SHOP
	elif area >= 90.0:
		typology = TYPE_SHOP if _rng.randf() < 0.58 else TYPE_TOWNHOUSE
	elif _rng.randf() < 0.38:
		typology = TYPE_TOWNHOUSE
	if ceiling <= TYPE_SHOP:
		typology = mini(typology, TYPE_TOWER)
	else:
		typology = mini(typology, maxi(ceiling, TYPE_APARTMENT))
	row["typology"] = typology
	row["stories"] = _stories(typology)
	row["coverage"] = 0.90
	row["packed"] = true
	row["width"] = maxf(width * 0.90, _cell)
	row["depth"] = maxf(depth * 0.88, _cell * 1.2)


func _place_district_marks() -> void:
	var best: Dictionary = {}
	var nearest: Dictionary = {}
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		var district_id: int = int(row["district_id"])
		if not _district_centre.has(district_id):
			continue
		var away: float = Vector2(row["centre"]).distance_squared_to(_district_centre[district_id])
		if nearest.has(district_id) and away >= float(nearest[district_id]):
			continue
		best[district_id] = index
		nearest[district_id] = away
	for district_id in _district_centre:
		var id := int(district_id)
		if best.has(id):
			_promote_landmark(_lots[best[id]], id)
			continue
		var lot := {
			"centre": _district_centre[id],
			"along": _nearest_tangent(_district_centre[id]),
			"across": Vector2.UP,
			"across_axis": Vector2.UP,
			"t_min": 0.0,
			"t_max": 0.0,
			"width": 16.0,
			"depth": 14.0,
			"density": 1.0,
			"ceiling": TYPE_LANDMARK,
			"district_id": id,
			"nudge": 0.0,
			"packed": false,
			"typology": TYPE_LANDMARK,
			"stories": 4.0,
			"name": "",
			"street_name": _nearest_street_name(_district_centre[id]),
		}
		if Vector2(lot["along"]).length_squared() < 0.0001:
			lot["along"] = Vector2.RIGHT
		var along: Vector2 = lot["along"]
		lot["along"] = along.normalized()
		lot["across"] = Vector2(-along.y, along.x)
		lot["across_axis"] = lot["across"]
		_promote_landmark(lot, id)
		_lots.append(lot)


func _ensure_district_marks() -> void:
	var halls: Dictionary = {}
	var pick: Dictionary = {}
	var nearest: Dictionary = {}
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		var district_id: int = int(row["district_id"])
		if bool(row.get("landmark", false)):
			halls[district_id] = true
			continue
		if bool(row.get("town_center", false)) or bool(row.get("mega", false)):
			continue
		if not _district_centre.has(district_id):
			continue
		var away: float = Vector2(row["centre"]).distance_squared_to(_district_centre[district_id])
		if nearest.has(district_id) and away >= float(nearest[district_id]):
			continue
		pick[district_id] = index
		nearest[district_id] = away
	for district_id in pick:
		var id := int(district_id)
		if halls.has(id):
			continue
		_promote_landmark(_lots[int(pick[id])], id)


func _promote_landmark(lot: Dictionary, district_id: int) -> void:
	lot["typology"] = TYPE_LANDMARK
	lot["landmark"] = true
	lot["district_name"] = String(_district_name.get(district_id, "District"))
	lot["ceiling"] = TYPE_LANDMARK
	_apply_special(lot, _special_for_district(district_id))


func _place_town_center() -> void:
	var biggest_id := -1
	var biggest_area := -1.0
	for district_id in _district_area:
		var area := float(_district_area[district_id])
		if area > biggest_area:
			biggest_area = area
			biggest_id = int(district_id)
	if biggest_id < 0:
		return
	var centre: Vector2 = _district_centre.get(biggest_id, Vector2.ZERO)
	var best := -1
	var nearest := 1.0e12
	var hall: Dictionary = {}
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		if int(row["district_id"]) != biggest_id:
			continue
		if bool(row.get("landmark", false)):
			hall = row
			continue
		var away: float = Vector2(row["centre"]).distance_squared_to(centre)
		if away < nearest:
			nearest = away
			best = index
	if best >= 0:
		_promote_town_center(_lots[best], biggest_id)
		return
	var lot := _civic_lot(biggest_id, centre)
	if not hall.is_empty():
		var along: Vector2 = hall.get("along", Vector2.RIGHT)
		if along.length_squared() < 0.0001:
			along = Vector2.RIGHT
		along = along.normalized()
		var gap := float(hall["width"]) * 0.5 + 8.0
		lot["centre"] = Vector2(hall["centre"]) + along * gap
		lot["along"] = along
		lot["across"] = Vector2(-along.y, along.x)
		lot["across_axis"] = lot["across"]
	_promote_town_center(lot, biggest_id)
	_lots.append(lot)


func _civic_lot(district_id: int, at: Vector2) -> Dictionary:
	var along := _nearest_tangent(at)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across := Vector2(-along.y, along.x)
	return {
		"centre": at,
		"along": along,
		"across": across,
		"across_axis": across,
		"t_min": 0.0,
		"t_max": 0.0,
		"width": 24.0,
		"depth": 20.0,
		"density": 1.0,
		"ceiling": TYPE_TOWN_CENTER,
		"district_id": district_id,
		"nudge": 0.0,
		"packed": false,
		"typology": TYPE_TOWN_CENTER,
		"stories": 8.0,
		"name": "",
		"street_name": _nearest_street_name(at),
	}


func _promote_town_center(lot: Dictionary, district_id: int) -> void:
	var area := float(_district_area.get(district_id, 8000.0))
	var span := sqrt(maxf(area, 400.0))
	lot["typology"] = TYPE_TOWN_CENTER
	lot["town_center"] = true
	lot["landmark"] = false
	lot["district_name"] = String(_district_name.get(district_id, "District"))
	lot["width"] = clampf(span * 0.095, 28.0, 92.0)
	lot["depth"] = clampf(span * 0.080, 24.0, 76.0)
	lot["stories"] = clampf(span * 0.040, 8.0, 44.0)
	lot["ceiling"] = TYPE_TOWN_CENTER


## Medium districts that never host a mega cluster get a pocket of large
## walk-ups near the hall, packed along one stretch of street.
func _pack_medium_apartments() -> void:
	for job in _fill_jobs:
		var row: Dictionary = job
		if not bool(row.get("midrise", false)):
			continue
		var area := float(row["area"])
		var count := 5
		if area >= 22000.0:
			count = 6
		if area >= 36000.0:
			count = 8
		_raise_apartment_pack(int(row["id"]), count)
	var kept: Array = []
	for lot in _lots:
		var row: Dictionary = lot
		if bool(row.get("absorb", false)):
			continue
		kept.append(row)
	_lots = kept


func _raise_apartment_pack(district_id: int, count: int) -> void:
	var centre: Vector2 = _district_centre.get(district_id, Vector2.ZERO)
	var candidates: Array = []
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		if int(row["district_id"]) != district_id:
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		if bool(row.get("mega", false)) or bool(row.get("absorb", false)):
			continue
		if float(row.get("width", 0.0)) * float(row.get("depth", 0.0)) < 48.0:
			continue
		candidates.append({
			"i": index,
			"d": Vector2(row["centre"]).distance_squared_to(centre),
		})
	if candidates.size() < 3:
		return
	candidates.sort_custom(_closer_candidate)
	var seed: Dictionary = _lots[int((candidates[0] as Dictionary)["i"])]
	var seed_at: Vector2 = seed["centre"]
	for row in candidates:
		(row as Dictionary)["d"] = Vector2(
			(_lots[int(row["i"])] as Dictionary)["centre"]).distance_squared_to(seed_at)
	candidates.sort_custom(_closer_candidate)
	var chosen: Array = []
	var span := 46.0
	var want := mini(maxi(count, 4), candidates.size())
	while chosen.size() < mini(want, 4) and span <= 110.0:
		chosen.clear()
		for row in candidates:
			if chosen.size() >= want:
				break
			var lot: Dictionary = _lots[int(row["i"])]
			if Vector2(lot["centre"]).distance_to(seed_at) > span:
				continue
			chosen.append(int(row["i"]))
		span += 16.0
	if chosen.size() < 3:
		return
	_merge_apartment_neighbors(chosen)
	for index in chosen:
		var lot: Dictionary = _lots[int(index)]
		if bool(lot.get("absorb", false)):
			continue
		_promote_apartment_pack(lot)


func _merge_apartment_neighbors(chosen: Array) -> void:
	var used: Dictionary = {}
	for index in chosen:
		if used.has(int(index)):
			continue
		var keep: Dictionary = _lots[int(index)]
		if bool(keep.get("absorb", false)):
			continue
		var partner := -1
		var best := 1.0e9
		for other in chosen:
			var other_i := int(other)
			if other_i == int(index) or used.has(other_i):
				continue
			var drop: Dictionary = _lots[other_i]
			if bool(drop.get("absorb", false)):
				continue
			if not _lots_can_merge(keep, drop):
				continue
			var away: float = Vector2(keep["centre"]).distance_to(drop["centre"])
			if away < best:
				best = away
				partner = other_i
		used[int(index)] = true
		if partner < 0:
			continue
		_merge_lots(keep, _lots[partner])
		used[partner] = true


func _lots_can_merge(keep: Dictionary, drop: Dictionary) -> bool:
	var a: Vector2 = keep["centre"]
	var b: Vector2 = drop["centre"]
	var delta := b - a
	if delta.length_squared() < 0.01:
		return false
	var along: Vector2 = keep.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = delta
	along = along.normalized()
	var heading := delta.normalized()
	if absf(along.dot(heading)) < 0.72:
		return false
	var across_keep: Vector2 = keep.get("across", Vector2.UP)
	var across_drop: Vector2 = drop.get("across", Vector2.UP)
	if across_keep.length_squared() > 0.0001 and across_drop.length_squared() > 0.0001:
		if across_keep.normalized().dot(across_drop.normalized()) < 0.45:
			return false
	var reach := (float(keep["width"]) + float(drop["width"])) * 0.5 + 2.8
	return delta.length() <= reach


func _merge_lots(keep: Dictionary, drop: Dictionary) -> void:
	var a: Vector2 = keep["centre"]
	var b: Vector2 = drop["centre"]
	var w1 := float(keep["width"])
	var w2 := float(drop["width"])
	var gap := maxf(a.distance_to(b) - (w1 + w2) * 0.5, 0.0)
	keep["width"] = clampf(w1 + w2 + gap, 14.0, 36.0)
	keep["depth"] = maxf(float(keep["depth"]), float(drop["depth"]))
	keep["centre"] = (a + b) * 0.5
	keep["t_min"] = minf(float(keep.get("t_min", 0.0)), float(drop.get("t_min", 0.0)))
	keep["t_max"] = maxf(float(keep.get("t_max", 0.0)), float(drop.get("t_max", 0.0)))
	drop["absorb"] = true


func _promote_apartment_pack(lot: Dictionary) -> void:
	lot["typology"] = TYPE_APARTMENT
	lot["ceiling"] = maxi(int(lot.get("ceiling", 0)), TYPE_APARTMENT)
	lot["stories"] = float(_rng.randi_range(7, 12))
	lot["coverage"] = maxf(float(lot.get("coverage", 0.7)), 0.80)
	lot["packed"] = true
	lot["apartment_pack"] = true
	lot["width"] = clampf(float(lot["width"]), 12.0, 36.0)
	lot["depth"] = maxf(float(lot["depth"]), 10.0)


func _place_mega_towers() -> void:
	var ranked := _skyline_districts()
	if ranked.is_empty():
		return
	var downtown_id: int = ranked[0]
	var hall_h := _hall_stories(downtown_id)
	_raise_megas(downtown_id, 5, hall_h * 6.0)
	if ranked.size() < 2:
		return
	var other_id: int = ranked[1]
	var local_h := _hall_stories(other_id)
	var count := _rng.randi_range(3, 5)
	_raise_megas(other_id, count, local_h * _rng.randf_range(4.2, 5.2))


func _skyline_districts() -> Array:
	var ranked: Array = []
	for district_id in _district_area:
		ranked.append({
			"id": int(district_id),
			"a": float(_district_area[district_id]),
		})
	ranked.sort_custom(_larger_district)
	var out: Array = []
	if ranked.is_empty():
		return out
	out.append(int((ranked[0] as Dictionary)["id"]))
	if ranked.size() < 2:
		return out
	var biggest := float((ranked[0] as Dictionary)["a"])
	var runner := ranked[1] as Dictionary
	if float(runner["a"]) >= maxf(biggest * 0.38, 28000.0):
		out.append(int(runner["id"]))
	return out


func _larger_district(p: Dictionary, q: Dictionary) -> bool:
	return float(p["a"]) > float(q["a"])


func _biggest_district() -> int:
	var ranked := _skyline_districts()
	if ranked.is_empty():
		return -1
	return int(ranked[0])


func _hall_stories(district_id: int) -> float:
	var height := 12.0
	for lot in _lots:
		var row: Dictionary = lot
		if int(row["district_id"]) != district_id:
			continue
		if not bool(row.get("landmark", false)):
			continue
		return maxf(float(row["stories"]), 4.0)
	return height


func _raise_megas(district_id: int, count: int, stories: float) -> void:
	var centre: Vector2 = _district_centre.get(district_id, Vector2.ZERO)
	var candidates: Array = []
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		if int(row["district_id"]) != district_id:
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		if bool(row.get("mega", false)):
			continue
		var footprints: Array = row.get("footprints", [])
		if footprints.is_empty():
			continue
		var area := 0.0
		var fat := false
		for piece in footprints:
			var poly: PackedVector2Array = piece
			area += _poly_area(poly)
			if _poly_building_ok(poly):
				fat = true
		if (not fat) or area < 70.0:
			continue
		candidates.append({
			"i": index,
			"d": Vector2(row["centre"]).distance_squared_to(centre),
			"a": area,
		})
	candidates.sort_custom(_closer_candidate)
	if candidates.is_empty():
		return
	var want := clampf(stories, 24.0, 200.0)
	var seed: Dictionary = _lots[int((candidates[0] as Dictionary)["i"])]
	var seed_at: Vector2 = seed["centre"]
	for row in candidates:
		(row as Dictionary)["d"] = Vector2((_lots[int(row["i"])] as Dictionary)["centre"]).distance_squared_to(seed_at)
	candidates.sort_custom(_closer_candidate)
	var chosen: Array = []
	var span := 78.0
	while chosen.size() < mini(count, 3) and span <= 140.0:
		chosen.clear()
		var spots: Array = []
		for row in candidates:
			if chosen.size() >= count:
				break
			var lot: Dictionary = _lots[int(row["i"])]
			var at: Vector2 = lot["centre"]
			if at.distance_to(seed_at) > span:
				continue
			var far_enough := true
			for other in spots:
				if at.distance_to(other) < 26.0:
					far_enough = false
					break
			if not far_enough:
				continue
			spots.append(at)
			chosen.append(int(row["i"]))
		span += 18.0
	for index in chosen:
		var lot: Dictionary = _lots[int(index)]
		lot["mega"] = true
		lot["typology"] = TYPE_SKY
		lot["stories"] = want
		lot["ceiling"] = TYPE_SKY
		_square_plan(lot, 18.0, 24.0)


func _taper_skyline() -> void:
	var cores: Array = []
	for lot in _lots:
		var row: Dictionary = lot
		if not bool(row.get("mega", false)):
			continue
		cores.append({
			"at": row["centre"],
			"h": float(row["stories"]),
		})
	if cores.is_empty():
		return
	var inner := 34.0
	var outer := 240.0
	for lot in _lots:
		var row: Dictionary = lot
		if bool(row.get("mega", false)):
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		if bool(row.get("apartment_pack", false)):
			continue
		var at: Vector2 = row["centre"]
		var nearest := 1.0e12
		var peak := 0.0
		for core in cores:
			var info: Dictionary = core
			var away: float = at.distance_to(info["at"])
			if away < nearest:
				nearest = away
				peak = float(info["h"])
		if nearest >= outer or peak < 8.0:
			continue
		var t := 1.0 - _smoothstep(inner, outer, nearest)
		var base := float(row["stories"])
		var cap := peak * 0.78
		var grain := _skyline_grain(at)
		var blend := clampf(t * 0.82 + grain, 0.0, 1.0)
		var raised := lerpf(base, cap, blend)
		raised *= _rng.randf_range(0.76, 1.12)
		if nearest <= 40.0:
			raised = maxf(raised, peak * 0.46)
		row["stories"] = maxf(base, raised)
		_restyle_for_height(row)
	_guard_mega_shoulders(cores)
	_line_skyline_outskirts(cores)


func _guard_mega_shoulders(cores: Array) -> void:
	for lot in _lots:
		var row: Dictionary = lot
		if bool(row.get("mega", false)):
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		if bool(row.get("apartment_pack", false)):
			continue
		var at: Vector2 = row["centre"]
		var nearest := 1.0e12
		var peak := 0.0
		for core in cores:
			var info: Dictionary = core
			var away: float = at.distance_to(info["at"])
			if away < nearest:
				nearest = away
				peak = float(info["h"])
		if nearest > 40.0 or peak < 8.0:
			continue
		var floor_h := peak * 0.46
		if float(row["stories"]) + 0.001 < floor_h:
			row["stories"] = floor_h
			_restyle_for_height(row)


func _line_skyline_outskirts(cores: Array) -> void:
	if cores.is_empty():
		return
	var inner := 44.0
	var outer := 158.0
	for lot in _lots:
		var row: Dictionary = lot
		if bool(row.get("mega", false)):
			continue
		if bool(row.get("landmark", false)) or bool(row.get("town_center", false)):
			continue
		if bool(row.get("apartment_pack", false)):
			continue
		var at: Vector2 = row["centre"]
		var nearest := 1.0e12
		for core in cores:
			var info: Dictionary = core
			nearest = minf(nearest, at.distance_to(info["at"]))
		if nearest < inner or nearest > outer:
			continue
		var t := clampf((nearest - inner) / maxf(outer - inner, 1.0), 0.0, 1.0)
		var typology := TYPE_APARTMENT
		var stories := float(_rng.randi_range(5, 10))
		if t < 0.28:
			typology = TYPE_TOWER if _rng.randf() < 0.58 else TYPE_APARTMENT
			stories = float(_rng.randi_range(10, 16)) if typology == TYPE_TOWER \
				else float(_rng.randi_range(6, 11))
		elif t < 0.62:
			typology = TYPE_SHOP if _rng.randf() < 0.38 else TYPE_APARTMENT
			stories = float(_rng.randi_range(3, 6)) if typology == TYPE_SHOP \
				else float(_rng.randi_range(5, 10))
		else:
			typology = TYPE_SHOP if _rng.randf() < 0.55 else TYPE_APARTMENT
			stories = float(_rng.randi_range(3, 6)) if typology == TYPE_SHOP \
				else float(_rng.randi_range(4, 8))
		row["typology"] = typology
		row["ceiling"] = maxi(int(row.get("ceiling", 0)), typology)
		row["packed"] = true
		row["rim"] = true
		row["stories"] = maxf(stories, 3.0)
		row["coverage"] = maxf(float(row.get("coverage", 0.7)), 0.74)


func _skyline_grain(at: Vector2) -> float:
	var clump := sin(at.x * 0.071 + at.y * 0.053) * 0.20
	var speck := sin(at.x * 0.21 - at.y * 0.17) * 0.16
	return clump + speck + _rng.randf_range(-0.16, 0.10)


func _restyle_for_height(lot: Dictionary) -> void:
	var height := float(lot["stories"])
	var typology := TYPE_HOUSE
	if height >= 22.0:
		typology = TYPE_SKY
	elif height >= 12.0:
		typology = TYPE_TOWER
	elif height >= 6.0:
		typology = TYPE_APARTMENT
	elif height >= 3.0:
		typology = TYPE_TOWNHOUSE
	lot["typology"] = typology
	lot["ceiling"] = maxi(int(lot.get("ceiling", 0)), typology)
	if typology >= TYPE_TOWER and not bool(lot.get("rim", false)):
		_square_plan(lot, 14.0 if typology == TYPE_TOWER else 16.0, 24.0)


func _square_plan(lot: Dictionary, lo: float, hi: float) -> void:
	if not lot.get("footprints", []).is_empty():
		_fit_lot_to_footprint(lot)
		var room := minf(float(lot.get("width", lo)), float(lot.get("depth", lo)))
		if room < 2.4:
			return
		var span := clampf(room, minf(lo, room), minf(hi, room))
		lot["width"] = span
		lot["depth"] = span
		return
	var span := clampf(
		(float(lot.get("width", lo)) + float(lot.get("depth", lo))) * 0.5, lo, hi)
	lot["width"] = span
	lot["depth"] = span


func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _closer_candidate(p: Dictionary, q: Dictionary) -> bool:
	return float(p["d"]) < float(q["d"])


func _infill_leftover_lots(arteries: Dictionary) -> void:
	if _lots.is_empty() or _owner.is_empty():
		return
	_infill_pass(arteries)


func _infill_pass(arteries: Dictionary) -> int:
	var occupied: Dictionary = {}
	for lot in _lots:
		_mark_lot_cells(occupied, lot, 0.4)
	var leftover: Dictionary = {}
	for key in _owner:
		if _roads.has(key) or occupied.has(key):
			continue
		var district_id := int(_owner[key])
		var cells: Dictionary = leftover.get(district_id, {})
		cells[key] = true
		leftover[district_id] = cells
	if leftover.is_empty():
		return 0
	var job_of: Dictionary = {}
	for job in _fill_jobs:
		job_of[int(job["id"])] = job
	var before := _lots.size()
	for district_id in leftover:
		var job: Dictionary = job_of.get(int(district_id), {})
		var density := float(job.get("density", 0.4))
		var ceiling: int = int(job.get("ceiling", TYPE_HOUSE))
		var district_tight: bool = bool(job.get("tight", false))
		for blob in _components(leftover[district_id]):
			if blob.size() < 2:
				continue
			var area := float(blob.size()) * _cell * _cell
			if area < 24.0:
				continue
			_pack_leftover_blob(
				int(district_id), blob, density, ceiling, district_tight, arteries)
	var bins := _bin_existing_lots(before)
	var kept: Array = []
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		if index < before:
			kept.append(row)
			continue
		if not _infill_lot_ok(row, bins):
			continue
		kept.append(row)
		_bin_add_lot(bins, row)
	var added := kept.size() - before
	_lots = kept
	return added


func _pack_leftover_blob(
		district_id: int,
		blob: Dictionary,
		density: float,
		ceiling: int,
		tight: bool,
		arteries: Dictionary
	) -> void:
	var keys: Array = blob.keys()
	keys.sort_custom(_cell_key_less)
	var used: Dictionary = {}
	var face := _nearest_tangent(_centroid(blob))
	if face.length_squared() < 0.01:
		face = Vector2.RIGHT
	face = face.normalized()
	var sizes: Array[Vector2i] = [
		Vector2i(3, 3), Vector2i(3, 2), Vector2i(2, 3), Vector2i(2, 2),
		Vector2i(2, 1), Vector2i(1, 2),
	]
	var start := _lots.size()
	for key in keys:
		var origin: Vector2i = key
		if used.has(origin):
			continue
		var claimed: Array = []
		for size in sizes:
			claimed = _claim_cell_rect(blob, used, origin, size.x, size.y)
			if not claimed.is_empty():
				break
		if claimed.is_empty():
			continue
		for cell in claimed:
			used[cell] = true
		_emit_claimed_lot(district_id, claimed, face, density, ceiling, tight)
	for index in range(start, _lots.size()):
		_style_lot(_lots[index])
		_clip_lot_to_blob(_lots[index], blob)
		_keep_infill_on_pad(_lots[index], arteries)


func _cell_key_less(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


func _claim_cell_rect(
		blob: Dictionary,
		used: Dictionary,
		origin: Vector2i,
		wide: int,
		tall: int
	) -> Array:
	var claimed: Array = []
	for ox in wide:
		for oy in tall:
			var key := Vector2i(origin.x + ox, origin.y + oy)
			if used.has(key) or not blob.has(key):
				return []
			claimed.append(key)
	return claimed


func _emit_claimed_lot(
		district_id: int,
		claimed: Array,
		face: Vector2,
		density: float,
		ceiling: int,
		tight: bool
	) -> void:
	if claimed.is_empty():
		return
	var along := face.normalized()
	var across := Vector2(-along.y, along.x)
	var min_s := 1.0e9
	var max_s := -1.0e9
	var min_t := 1.0e9
	var max_t := -1.0e9
	var acc := Vector2.ZERO
	var h := _cell * 0.5
	for cell in claimed:
		var at: Vector2i = cell
		var mid := _cell_uv(at)
		acc += mid
		for delta in [
			Vector2(-h, -h),
			Vector2(h, -h),
			Vector2(h, h),
			Vector2(-h, h),
		]:
			var corner: Vector2 = mid + delta
			var s := corner.dot(along)
			var t := corner.dot(across)
			min_s = minf(min_s, s)
			max_s = maxf(max_s, s)
			min_t = minf(min_t, t)
			max_t = maxf(max_t, t)
	var centre := acc / float(claimed.size())
	var lot := {
		"centre": centre,
		"along": along,
		"across": across,
		"across_axis": across,
		"t_min": min_t,
		"t_max": max_t,
		"width": maxf(max_s - min_s, _cell),
		"depth": maxf(max_t - min_t, _cell),
		"density": density,
		"ceiling": ceiling,
		"district_id": district_id,
		"nudge": 0.22,
		"packed": true,
		"tight": tight,
		"rim": false,
		"midrise_core": false,
		"infill": true,
		"typology": TYPE_HOUSE,
		"stories": 1.0,
		"name": "",
		"street_name": _nearest_street_name(centre),
	}
	_lots.append(lot)


func _clip_lot_to_blob(row: Dictionary, blob: Dictionary) -> void:
	var pieces: Array = row.get("footprints", [])
	if pieces.is_empty():
		pieces = [_lot_rect(row)]
	var clipped: Array = []
	for piece in pieces:
		var ring: PackedVector2Array = piece
		if ring.size() < 3:
			continue
		var overlap := _blob_overlap_rect(ring, blob)
		if overlap.size.x < _cell * 0.7 or overlap.size.y < _cell * 0.7:
			continue
		var piece_box := _poly_aabb(ring)
		var piece_area := maxf(piece_box.size.x * piece_box.size.y, 1.0)
		if overlap.get_area() >= piece_area * 0.55 and _poly_building_ok(ring):
			clipped.append(ring)
			continue
		var clip := _rect_poly(overlap)
		for part in Geometry2D.intersect_polygons(ring, clip):
			var keep := _dedupe_ring(part)
			if _poly_building_ok(keep):
				clipped.append(keep)
	row["footprints"] = clipped
	if clipped.is_empty():
		return
	var biggest: PackedVector2Array = clipped[0]
	var best_a := _poly_area(biggest)
	for part in clipped:
		var a := _poly_area(part)
		if a > best_a:
			best_a = a
			biggest = part
	row["centre"] = _poly_centroid(biggest)
	_fit_lot_to_footprint(row)


func _blob_overlap_rect(poly: PackedVector2Array, blob: Dictionary) -> Rect2:
	var box := _poly_aabb(poly)
	var x0 := int(floor(box.position.x / _cell))
	var y0 := int(floor(box.position.y / _cell))
	var x1 := int(ceil(box.end.x / _cell))
	var y1 := int(ceil(box.end.y / _cell))
	var overlap := Rect2()
	var started := false
	var h := _cell * 0.5
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var key := Vector2i(x, y)
			if not blob.has(key):
				continue
			var mid := _cell_uv(key)
			var cell_box := Rect2(mid - Vector2(h, h), Vector2(_cell, _cell))
			if started:
				overlap = overlap.merge(cell_box)
			else:
				overlap = cell_box
				started = true
	return overlap


func _rect_poly(box: Rect2) -> PackedVector2Array:
	return _ccw(PackedVector2Array([
		box.position,
		Vector2(box.end.x, box.position.y),
		box.end,
		Vector2(box.position.x, box.end.y),
	]))


func _keep_infill_on_pad(row: Dictionary, arteries: Dictionary) -> void:
	var pieces: Array = row.get("footprints", [])
	if pieces.is_empty():
		pieces = [_lot_rect(row)]
	var on_pad: Array = []
	for piece in pieces:
		var poly: PackedVector2Array = piece
		var mid := _poly_centroid(poly)
		if not _uv_on_pad(mid):
			continue
		if _uv_on_artery(mid, arteries):
			continue
		if _poly_building_ok(poly):
			on_pad.append(poly)
	row["footprints"] = on_pad
	if on_pad.is_empty():
		return
	var biggest: PackedVector2Array = on_pad[0]
	var best_a := _poly_area(biggest)
	for part in on_pad:
		var a := _poly_area(part)
		if a > best_a:
			best_a = a
			biggest = part
	row["centre"] = _poly_centroid(biggest)
	_fit_lot_to_footprint(row)


func _infill_lot_ok(row: Dictionary, bins: Dictionary) -> bool:
	var pieces: Array = row.get("footprints", [])
	if pieces.is_empty():
		return false
	var ok := false
	for piece in pieces:
		if _poly_building_ok(piece):
			ok = true
			break
	if not ok:
		return false
	if not _uv_on_pad(row.get("centre", Vector2.ZERO)):
		return false
	for other in _binned_lots_near(bins, row):
		if _lots_overlap(row, other, 3.5):
			return false
	return true


func _bin_existing_lots(count: int) -> Dictionary:
	var bins: Dictionary = {}
	var n := mini(count, _lots.size())
	for index in n:
		_bin_add_lot(bins, _lots[index])
	return bins


func _bin_add_lot(bins: Dictionary, lot: Dictionary) -> void:
	var at: Vector2 = lot.get("centre", Vector2.ZERO)
	var key := Vector2i(int(floor(at.x / 24.0)), int(floor(at.y / 24.0)))
	var bucket: Array = bins.get(key, [])
	bucket.append(lot)
	bins[key] = bucket


func _binned_lots_near(bins: Dictionary, lot: Dictionary) -> Array:
	var at: Vector2 = lot.get("centre", Vector2.ZERO)
	var cx := int(floor(at.x / 24.0))
	var cy := int(floor(at.y / 24.0))
	var out: Array = []
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			out.append_array(bins.get(Vector2i(cx + ox, cy + oy), []))
	return out


func _lots_overlap(a: Dictionary, b: Dictionary, min_area: float) -> bool:
	var pa: Array = a.get("footprints", [])
	var pb: Array = b.get("footprints", [])
	if pa.is_empty():
		pa = [_lot_rect(a)]
	if pb.is_empty():
		pb = [_lot_rect(b)]
	for piece_a in pa:
		for piece_b in pb:
			var hit: Array = Geometry2D.intersect_polygons(piece_a, piece_b)
			for part in hit:
				if _poly_area(_ccw(part)) >= min_area:
					return true
	return false


func _mark_lot_cells(occupied: Dictionary, lot: Dictionary, margin: float) -> void:
	var pieces: Array = lot.get("footprints", [])
	if pieces.is_empty():
		pieces = [_lot_rect(lot)]
	for piece in pieces:
		var ring: PackedVector2Array = piece
		if ring.size() < 3:
			continue
		var box := _poly_aabb(ring).grow(maxf(margin, 0.0))
		var x0 := int(floor(box.position.x / _cell))
		var y0 := int(floor(box.position.y / _cell))
		var x1 := int(ceil(box.end.x / _cell))
		var y1 := int(ceil(box.end.y / _cell))
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				var key := Vector2i(x, y)
				if occupied.has(key):
					continue
				if _point_to_ring(_cell_uv(key), ring) <= margin:
					occupied[key] = true


func _inflate_poly(poly: PackedVector2Array, margin: float) -> PackedVector2Array:
	var ring := _ccw(poly)
	if ring.size() < 3 or margin <= 0.01:
		return ring
	var mid := _poly_centroid(ring)
	var out := PackedVector2Array()
	for point in ring:
		var away: Vector2 = point - mid
		if away.length_squared() < 0.0001:
			out.append(point)
			continue
		out.append(mid + away.normalized() * (away.length() + margin))
	return _ccw(out)


func _clip_lots(arteries: Dictionary) -> void:
	var cutters := _road_cutters(arteries)
	var paths := _clearance_paths(arteries)
	if cutters.is_empty():
		for lot in _lots:
			(lot as Dictionary)["footprints"] = [_lot_rect(lot)]
		return
	var bins := _bin_cutters(cutters)
	var path_bins := _bin_paths(paths)
	for lot in _lots:
		_clip_one_lot(lot, bins, path_bins)


func _clip_one_lot(row: Dictionary, bins: Dictionary, path_bins: Dictionary) -> void:
	if bins.is_empty():
		row["footprints"] = [_lot_rect(row)]
		return
	var pieces: Array = [_lot_rect(row)]
	var box := _poly_aabb(pieces[0])
	var nearby := _cutters_near(bins, box)
	var nearby_paths := _paths_near(path_bins, box)
	if nearby.is_empty() and nearby_paths.is_empty():
		row["footprints"] = pieces
		return
	for cutter in nearby:
		var next: Array = []
		for piece in pieces:
			next.append_array(_subtract_piece(piece, cutter))
		pieces = next
		if pieces.is_empty():
			break
	if pieces.is_empty():
		pieces = _remnant_off_road(row, nearby)
	if not pieces.is_empty():
		pieces = _slice_until_clear(pieces, nearby_paths)
	if pieces.is_empty():
		pieces = _remnant_off_road(row, nearby)
		pieces = _slice_until_clear(pieces, nearby_paths)
	pieces = _sanitize_pieces(pieces)
	pieces = _reject_road_hits(pieces, [], nearby_paths)
	if pieces.is_empty():
		pieces = _remnant_off_road(row, nearby)
		pieces = _slice_until_clear(pieces, nearby_paths)
		pieces = _sanitize_pieces(pieces)
		pieces = _reject_road_hits(pieces, [], nearby_paths)
	row["footprints"] = pieces
	if not pieces.is_empty():
		var biggest: PackedVector2Array = pieces[0]
		var best_a := _poly_area(biggest)
		for part in pieces:
			var a := _poly_area(part)
			if a > best_a:
				best_a = a
				biggest = part
		row["centre"] = _poly_centroid(biggest)
		_fit_lot_to_footprint(row)


func _clip_lots_to_pad(arteries: Dictionary = {}) -> void:
	var kept: Array = []
	var paths := _clearance_paths(arteries)
	var path_bins := _bin_paths(paths)
	for lot in _lots:
		var row: Dictionary = lot
		var pieces: Array = row.get("footprints", [])
		if pieces.is_empty():
			continue
		var on_pad: Array = []
		for piece in pieces:
			var poly: PackedVector2Array = piece
			if _poly_on_pad(poly, arteries):
				on_pad.append(poly)
		if on_pad.is_empty():
			continue
		on_pad = _sanitize_pieces(on_pad)
		var nearby_paths := _paths_near(path_bins, _poly_aabb(on_pad[0]))
		on_pad = _reject_road_hits(on_pad, [], nearby_paths)
		if on_pad.is_empty():
			continue
		var biggest: PackedVector2Array = on_pad[0]
		var best_a := _poly_area(biggest)
		for part in on_pad:
			var a := _poly_area(part)
			if a > best_a:
				best_a = a
				biggest = part
		row["footprints"] = on_pad
		var centre := _poly_centroid(biggest)
		if not _uv_on_pad(centre):
			centre = _snap_to_pad(centre)
		if not _uv_on_pad(centre):
			continue
		row["centre"] = centre
		_fit_lot_to_footprint(row)
		kept.append(row)
	_lots = kept


func _record_buildings() -> void:
	_assign_variants()
	for lot in _lots:
		var row: Dictionary = lot
		var area := float(row["width"]) * float(row["depth"])
		var stories := float(row["stories"])
		var health := _base_health(int(row["typology"])) + stories * 18.0 + area * 0.35
		if bool(row.get("mega", false)):
			health *= 1.8
		row["max_health"] = health
		row["health"] = health


func _assign_variants() -> void:
	var by_district: Dictionary = {}
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		var district_id: int = int(row["district_id"])
		var list: Array = by_district.get(district_id, [])
		list.append(index)
		by_district[district_id] = list
	for district_id in by_district:
		_assign_district_variants(int(district_id), by_district[district_id])
	var all_small: Array = []
	var all_large: Array = []
	for index in _lots.size():
		var typology: int = int((_lots[index] as Dictionary)["typology"])
		if typology >= TYPE_TOWER:
			all_large.append(index)
		else:
			all_small.append(index)
	_ensure_variant_palette(all_small, PackedInt32Array([
		VARIANT_RECT, VARIANT_RECT_CAP, VARIANT_GABLE, VARIANT_ROUND_END, VARIANT_CYLINDER,
	]))
	_ensure_variant_palette(all_large, PackedInt32Array([
		VARIANT_RECT, VARIANT_TAPER, VARIANT_POINT_HALF, VARIANT_SLANT_HALF, VARIANT_CYL_HALF,
	]))


func _assign_district_variants(_district_id: int, indices: Array) -> void:
	var small: Array = []
	var large: Array = []
	for index in indices:
		var typology: int = int((_lots[index] as Dictionary)["typology"])
		if typology >= TYPE_TOWER:
			large.append(index)
		else:
			small.append(index)
	var small_palette := PackedInt32Array([
		VARIANT_RECT, VARIANT_RECT_CAP, VARIANT_GABLE, VARIANT_ROUND_END, VARIANT_CYLINDER,
	])
	var large_palette := PackedInt32Array([
		VARIANT_RECT, VARIANT_TAPER, VARIANT_POINT_HALF, VARIANT_SLANT_HALF, VARIANT_CYL_HALF,
	])
	_paint_variant_group(small, small_palette, true)
	_paint_variant_group(large, large_palette, false)


func _paint_variant_group(indices: Array, palette: PackedInt32Array, small: bool) -> void:
	if indices.is_empty() or palette.is_empty():
		return
	var order: Array = []
	for item in palette:
		if small and int(item) == VARIANT_CYLINDER:
			continue
		order.append(int(item))
	for shuffle_i in order.size():
		var swap_i: int = _rng.randi_range(0, order.size() - 1)
		var hold: int = int(order[shuffle_i])
		order[shuffle_i] = int(order[swap_i])
		order[swap_i] = hold
	if small:
		order.append(VARIANT_CYLINDER)
	var primary: int = int(order[0])
	var secondary: int = int(order[mini(1, order.size() - 1)])
	for index in indices:
		var row: Dictionary = _lots[index]
		var centre: Vector2 = row["centre"]
		var cluster := Vector2i(int(floor(centre.x / 36.0)), int(floor(centre.y / 36.0)))
		var local := primary
		if absi(cluster.x + cluster.y * 13) % 3 == 2:
			local = secondary
		var roll := _rng.randf()
		var picked := local
		if small:
			if roll < 0.58:
				picked = local
			elif roll < 0.78:
				picked = secondary if local == primary else primary
			elif roll < 0.90:
				picked = int(order[_rng.randi_range(0, maxi(order.size() - 2, 0))])
			else:
				picked = VARIANT_CYLINDER
		else:
			if roll < 0.52:
				picked = local
			elif roll < 0.76:
				picked = secondary if local == primary else primary
			else:
				picked = int(order[_rng.randi_range(0, order.size() - 1)])
		row["variant"] = picked
		if picked == VARIANT_ROUND_END:
			row["round_dir"] = 1 if _rng.randi() % 2 == 0 else -1
		_lots[index] = row
	if small:
		_ensure_variant_palette(indices, PackedInt32Array([
			VARIANT_RECT, VARIANT_RECT_CAP, VARIANT_GABLE, VARIANT_ROUND_END,
		]))
	else:
		_ensure_variant_palette(indices, palette)


func _ensure_variant_palette(indices: Array, palette: PackedInt32Array) -> void:
	if indices.size() < palette.size():
		return
	var counts: Dictionary = {}
	for index in indices:
		var variant: int = int((_lots[index] as Dictionary)["variant"])
		counts[variant] = int(counts.get(variant, 0)) + 1
	for item in palette:
		var wanted: int = int(item)
		if int(counts.get(wanted, 0)) > 0:
			continue
		var donor := -1
		var most := 1
		for index in indices:
			var have: int = int((_lots[index] as Dictionary)["variant"])
			if int(counts.get(have, 0)) > most:
				most = int(counts[have])
				donor = int(index)
		if donor < 0:
			continue
		var prev: int = int((_lots[donor] as Dictionary)["variant"])
		counts[prev] = int(counts.get(prev, 1)) - 1
		(_lots[donor] as Dictionary)["variant"] = wanted
		if wanted == VARIANT_ROUND_END:
			(_lots[donor] as Dictionary)["round_dir"] = 1 if _rng.randi() % 2 == 0 else -1
		counts[wanted] = 1


func _category_for_typology(typology: int) -> String:
	if typology <= TYPE_TOWNHOUSE:
		return "small_houses"
	if typology == TYPE_APARTMENT:
		return "medium_apartments"
	if typology == TYPE_SHOP:
		return "medium_buildings"
	if typology == TYPE_TOWER:
		return "large_towers"
	if typology == TYPE_SKY:
		return "skyscrapers"
	return "medium_buildings"


func _assign_designs() -> void:
	var by_category: Dictionary = {}
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		if bool(row.get("landmark", false)) or not String(row.get("special", "")).is_empty():
			continue
		var category := _category_for_typology(int(row["typology"]))
		if bool(row.get("mega", false)) or int(row["typology"]) == TYPE_SKY:
			category = "skyscrapers"
		var list: Array = by_category.get(category, [])
		list.append(index)
		by_category[category] = list
	for category in by_category:
		_paint_design_group(by_category[category], BuildingCatalog.names_in(String(category)))


func _paint_design_group(indices: Array, palette: PackedStringArray) -> void:
	if indices.is_empty() or palette.is_empty():
		return
	var order: Array = []
	for item in palette:
		order.append(String(item))
	for shuffle_i in order.size():
		var swap_i: int = _rng.randi_range(0, order.size() - 1)
		var hold := String(order[shuffle_i])
		order[shuffle_i] = String(order[swap_i])
		order[swap_i] = hold
	var primary := String(order[0])
	var secondary := String(order[mini(1, order.size() - 1)])
	for index in indices:
		var row: Dictionary = _lots[index]
		if _lot_keeps_variant_mass(row):
			row["design"] = ""
			row["walkable"] = false
			_lots[index] = row
			continue
		var centre: Vector2 = row["centre"]
		var cluster := Vector2i(int(floor(centre.x / 36.0)), int(floor(centre.y / 36.0)))
		var local := primary
		if absi(cluster.x + cluster.y * 13) % 3 == 2:
			local = secondary
		var roll := _rng.randf()
		var picked := local
		if roll < 0.54:
			picked = local
		elif roll < 0.78:
			picked = secondary if local == primary else primary
		else:
			picked = String(order[_rng.randi_range(0, order.size() - 1)])
		row["design"] = picked
		row["walkable"] = BuildingCatalog.is_walkable(picked)
		_lots[index] = row


func _lot_keeps_variant_mass(row: Dictionary) -> bool:
	if row.get("town_center", false) or row.get("landmark", false):
		return false
	if not String(row.get("special", "")).is_empty():
		return false
	var centre: Vector2 = row.get("centre", Vector2.ZERO)
	var cluster := Vector2i(int(floor(centre.x / 42.0)), int(floor(centre.y / 42.0)))
	var keep := absi(cluster.x * 7 + cluster.y * 13) % 5 < 2
	if _rng.randf() < 0.10:
		keep = not keep
	return keep


func _keep_variant_masses() -> void:
	var by_variant: Dictionary = {}
	for index in _lots.size():
		var row: Dictionary = _lots[index]
		if not String(row.get("special", "")).is_empty():
			continue
		if row.get("town_center", false) or row.get("landmark", false):
			continue
		var variant := int(row.get("variant", 0))
		var list: Array = by_variant.get(variant, [])
		list.append(index)
		by_variant[variant] = list
	for variant in by_variant:
		var list: Array = by_variant[variant]
		var bare := false
		for index in list:
			if String((_lots[index] as Dictionary).get("design", "")).is_empty():
				bare = true
				break
		if bare or list.is_empty():
			continue
		var pick: int = int(list[_rng.randi() % list.size()])
		var row: Dictionary = _lots[pick]
		row["design"] = ""
		row["walkable"] = false
		_lots[pick] = row


func _bind_district_specials() -> void:
	if not _district_special.is_empty() or _district_area.is_empty():
		return
	var ranked: Array = []
	for district_id in _district_area:
		ranked.append({
			"id": int(district_id),
			"a": float(_district_area[district_id]),
		})
	ranked.sort_custom(_larger_district)
	var specs: Array = []
	for name in BuildingCatalog.SPECIALS:
		var design := String(name)
		specs.append({
			"n": design,
			"a": BuildingCatalog.authored_width(design, 12.0) \
				* BuildingCatalog.authored_depth(design, 10.0),
		})
	specs.sort_custom(_larger_district)
	if specs.is_empty():
		return
	for index in ranked.size():
		var spec: Dictionary = specs[index % specs.size()]
		_district_special[int((ranked[index] as Dictionary)["id"])] = String(spec["n"])


func _special_for_district(district_id: int) -> String:
	_bind_district_specials()
	if _district_special.has(district_id):
		return String(_district_special[district_id])
	if BuildingCatalog.SPECIALS.is_empty():
		return "police_station"
	return String(BuildingCatalog.SPECIALS[absi(district_id) % BuildingCatalog.SPECIALS.size()])


func _apply_special(lot: Dictionary, design: String) -> void:
	lot["design"] = ""
	lot["walkable"] = true
	lot["special"] = design
	var display := BuildingCatalog.display_name(design)
	var district := String(lot.get("district_name", "District"))
	if district.is_empty():
		district = String(lot.get("street_name", "Civic"))
	lot["name"] = _unique("%s %s" % [district, display])
	var area := float(_district_area.get(int(lot.get("district_id", -1)), 8000.0))
	var scale := clampf(sqrt(maxf(area, 400.0)) / 110.0, 1.0, 1.22)
	lot["width"] = clampf(float(lot.get("width", 16.0)) * scale, 14.0, 36.0)
	lot["depth"] = clampf(float(lot.get("depth", 14.0)) * scale, 12.0, 32.0)
	lot["stories"] = maxf(float(lot.get("stories", 3.0)), 2.0)


func _base_health(typology: int) -> float:
	match typology:
		TYPE_TOWNHOUSE:
			return 140.0
		TYPE_APARTMENT:
			return 260.0
		TYPE_SHOP:
			return 200.0
		TYPE_TOWER:
			return 480.0
		TYPE_SKY:
			return 900.0
		TYPE_LANDMARK:
			return 700.0
		TYPE_TOWN_CENTER:
			return 1100.0
	return 90.0


func _poly_on_pad(poly: PackedVector2Array, arteries: Dictionary = {}) -> bool:
	if poly.size() < 3:
		return false
	var centre := _poly_centroid(poly)
	if not _uv_on_pad(centre):
		return false
	if _uv_on_artery(centre, arteries):
		return false
	for point in poly:
		if not _uv_on_pad(point):
			return false
	return true


func _snap_to_pad(uv: Vector2) -> Vector2:
	var key := Vector2i(roundi(uv.x / _cell), roundi(uv.y / _cell))
	if _owner.has(key):
		return _cell_uv(key)
	var best := uv
	var nearest := _cell * _cell * 2.0
	for ox in range(-2, 3):
		for oy in range(-2, 3):
			var other := Vector2i(key.x + ox, key.y + oy)
			if not _owner.has(other):
				continue
			var at := _cell_uv(other)
			var away := at.distance_squared_to(uv)
			if away < nearest:
				nearest = away
				best = at
	return best


func _uv_on_artery(at: Vector2, arteries: Dictionary) -> bool:
	if arteries.is_empty():
		return false
	var hw: PackedVector2Array = arteries.get("highway", PackedVector2Array())
	var hw_half := float(arteries.get("highway_half", 8.0))
	if hw.size() >= 2 and _path_distance(at, hw, true) < hw_half:
		return true
	var spur: PackedVector2Array = arteries.get("spur", PackedVector2Array())
	var spur_half := float(arteries.get("spur_half", 6.0))
	if spur.size() >= 2 and _path_distance(at, spur, false) < spur_half:
		return true
	var exit_half := float(arteries.get("exit_half", 6.2))
	for path in arteries.get("exits", []):
		var uv: PackedVector2Array = path
		if uv.size() >= 2 and _path_distance(at, uv, false) < exit_half:
			return true
	return false


func _road_cutters(arteries: Dictionary) -> Array:
	var cutters: Array = []
	for street in _streets:
		var row: Dictionary = street
		var half := float(row["half"]) + ROAD_CLEAR
		_append_path_cutters(cutters, row["uv"], half, false)
	for junction in _junctions:
		var row: Dictionary = junction
		_append_pad_cutter(
			cutters,
			row["at"],
			float(row["half"]) + ROAD_CLEAR)
	_append_path_cutters(
		cutters,
		arteries.get("highway", PackedVector2Array()),
		float(arteries.get("highway_half", 8.0)) + ROAD_CLEAR + 0.4,
		true)
	_append_path_cutters(
		cutters,
		arteries.get("spur", PackedVector2Array()),
		float(arteries.get("spur_half", 6.0)) + ROAD_CLEAR,
		false)
	var exits: Array = arteries.get("exits", [])
	var exit_half := float(arteries.get("exit_half", 6.2)) + ROAD_CLEAR
	for path in exits:
		_append_path_cutters(cutters, path, exit_half, false)
	return cutters


func _clearance_paths(arteries: Dictionary) -> Array:
	var paths: Array = []
	for street in _streets:
		var row: Dictionary = street
		paths.append({
			"id": paths.size(),
			"uv": row["uv"],
			"half": float(row["half"]),
			"closed": false,
		})
	paths.append({
		"id": paths.size(),
		"uv": arteries.get("highway", PackedVector2Array()),
		"half": float(arteries.get("highway_half", 8.0)),
		"closed": true,
	})
	paths.append({
		"id": paths.size(),
		"uv": arteries.get("spur", PackedVector2Array()),
		"half": float(arteries.get("spur_half", 6.0)),
		"closed": false,
	})
	var exit_half := float(arteries.get("exit_half", 6.2))
	for path in arteries.get("exits", []):
		paths.append({
			"id": paths.size(),
			"uv": path,
			"half": exit_half,
			"closed": false,
		})
	return paths


func _bin_paths(paths: Array) -> Dictionary:
	var bins: Dictionary = {}
	var cell := 48.0
	for path in paths:
		var uv: PackedVector2Array = path.get("uv", PackedVector2Array())
		if uv.size() < 2:
			continue
		var closed := bool(path.get("closed", false))
		var count := uv.size()
		var n := count if closed and count >= 3 else count - 1
		if closed and count >= 3 and uv[0].distance_to(uv[count - 1]) < 2.0:
			n = count - 1
		for index in n:
			var a: Vector2 = uv[index]
			var b: Vector2 = uv[(index + 1) % count]
			var run := a.distance_to(b)
			var pieces := maxi(1, int(ceili(run / 24.0)))
			for piece in pieces + 1:
				var at := a.lerp(b, float(piece) / float(pieces))
				var key := Vector2i(int(floor(at.x / cell)), int(floor(at.y / cell)))
				var bucket: Array = bins.get(key, [])
				var pid: int = int(path["id"])
				var seen := false
				for item in bucket:
					if int((item as Dictionary)["id"]) == pid:
						seen = true
						break
				if seen:
					continue
				bucket.append(path)
				bins[key] = bucket
	return bins


func _paths_near(bins: Dictionary, box: Rect2) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var grown := box.grow(10.0)
	var min_x := int(floor(grown.position.x / 48.0)) - 1
	var min_y := int(floor(grown.position.y / 48.0)) - 1
	var max_x := int(floor(grown.end.x / 48.0)) + 1
	var max_y := int(floor(grown.end.y / 48.0)) + 1
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var bucket: Array = bins.get(Vector2i(x, y), [])
			for path in bucket:
				var pid: int = int((path as Dictionary)["id"])
				if seen.has(pid):
					continue
				seen[pid] = true
				out.append(path)
	return out


func _append_path_cutters(cutters: Array, path: Variant, half: float, closed: bool) -> void:
	var uv: PackedVector2Array = path
	if uv.size() < 2 or half <= 0.1:
		return
	var count := uv.size()
	var segments := count if closed and count >= 3 else count - 1
	if closed and count >= 3 and uv[0].distance_to(uv[count - 1]) < 2.0:
		segments = count - 1
	for index in segments:
		var a: Vector2 = uv[index]
		var b: Vector2 = uv[(index + 1) % count]
		var chord := b - a
		var run := chord.length()
		if run < 0.25:
			continue
		var tangent := chord / run
		var side := Vector2(-tangent.y, tangent.x) * half
		var pad := tangent * minf(0.6, run * 0.25)
		var poly := PackedVector2Array()
		poly.append(a - pad - side)
		poly.append(b + pad - side)
		poly.append(b + pad + side)
		poly.append(a - pad + side)
		var keep := _ccw(poly)
		if keep.size() < 3:
			continue
		cutters.append({
			"id": cutters.size(),
			"poly": keep,
			"aabb": _poly_aabb(keep),
			"a": a,
			"b": b,
			"half": half,
		})


func _append_poly_cutter(cutters: Array, poly: PackedVector2Array) -> void:
	var keep := _ccw(poly)
	if keep.size() < 3:
		return
	cutters.append({
		"id": cutters.size(),
		"poly": keep,
		"aabb": _poly_aabb(keep),
		"a": keep[0],
		"b": keep[mini(1, keep.size() - 1)],
		"half": 1.0,
	})


func _append_pad_cutter(cutters: Array, at: Vector2, half: float) -> void:
	if half <= 0.1:
		return
	var poly := PackedVector2Array()
	var radius := half * 1.15
	for index in 8:
		var ang := TAU * float(index) / 8.0
		poly.append(at + Vector2(cos(ang), sin(ang)) * radius)
	var keep := _ccw(poly)
	if keep.size() < 3:
		return
	cutters.append({
		"id": cutters.size(),
		"poly": keep,
		"aabb": _poly_aabb(keep),
		"a": at + Vector2(radius, 0.0),
		"b": at - Vector2(radius, 0.0),
		"half": radius,
	})


func _bin_cutters(cutters: Array) -> Dictionary:
	var bins: Dictionary = {}
	for cutter in cutters:
		var box: Rect2 = cutter["aabb"]
		var min_x := int(floor(box.position.x / 48.0))
		var min_y := int(floor(box.position.y / 48.0))
		var max_x := int(floor(box.end.x / 48.0))
		var max_y := int(floor(box.end.y / 48.0))
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				var key := Vector2i(x, y)
				var bucket: Array = bins.get(key, [])
				bucket.append(cutter)
				bins[key] = bucket
	return bins


func _cutters_near(bins: Dictionary, box: Rect2) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var min_x := int(floor(box.position.x / 48.0)) - 1
	var min_y := int(floor(box.position.y / 48.0)) - 1
	var max_x := int(floor(box.end.x / 48.0)) + 1
	var max_y := int(floor(box.end.y / 48.0)) + 1
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var bucket: Array = bins.get(Vector2i(x, y), [])
			for cutter in bucket:
				var cid: int = int(cutter["id"])
				if seen.has(cid):
					continue
				seen[cid] = true
				var other: Rect2 = cutter["aabb"]
				if box.intersects(other, true):
					out.append(cutter)
	return out


func _subtract_piece(subject: PackedVector2Array, cutter: Dictionary) -> Array:
	if subject.size() < 3:
		return []
	var blade: PackedVector2Array = cutter["poly"]
	var inter: Array = Geometry2D.intersect_polygons(subject, blade)
	if inter.is_empty():
		return [subject]
	var clipped: Array = Geometry2D.clip_polygons(subject, blade)
	if clipped.is_empty():
		return []
	var outers: Array = []
	var has_hole := false
	var kept_area := 0.0
	for part in clipped:
		var poly: PackedVector2Array = part
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			has_hole = true
			continue
		var keep := _ccw(poly)
		var area := _poly_area(keep)
		if area < MIN_FOOTPRINT:
			continue
		kept_area += area
		outers.append(keep)
	var inter_area := 0.0
	for part in inter:
		inter_area += _poly_area(_ccw(part))
	var subject_area := _poly_area(subject)
	if (not has_hole) and kept_area <= subject_area - inter_area * 0.35:
		return outers
	var split := _punch_through(subject, cutter)
	if not split.is_empty():
		return split
	return _split_outside_strip(
		subject,
		cutter.get("a", Vector2.ZERO),
		cutter.get("b", Vector2.RIGHT),
		float(cutter.get("half", 3.0)))


func _punch_through(subject: PackedVector2Array, cutter: Dictionary) -> Array:
	var through := _through_quad(
		_poly_aabb(subject),
		cutter.get("a", Vector2.ZERO),
		cutter.get("b", Vector2.RIGHT),
		float(cutter.get("half", 3.0)))
	if through.size() < 3:
		return []
	var punched: Array = Geometry2D.clip_polygons(subject, through)
	var split: Array = []
	var has_hole := false
	for part in punched:
		var poly: PackedVector2Array = part
		if poly.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(poly):
			has_hole = true
			continue
		var keep := _ccw(poly)
		if _poly_area(keep) >= MIN_FOOTPRINT:
			split.append(keep)
	if has_hole or split.is_empty():
		return []
	if split.size() == 1 and _poly_area(split[0]) > _poly_area(subject) * 0.92:
		return []
	return split


func _through_quad(box: Rect2, a: Vector2, b: Vector2, half: float) -> PackedVector2Array:
	var chord := b - a
	var run := chord.length()
	if run < 0.001 or half <= 0.1:
		return PackedVector2Array()
	var tangent := chord / run
	var side := Vector2(-tangent.y, tangent.x) * half
	var origin := (a + b) * 0.5
	var reach := half + 8.0
	var c0 := box.position
	var c1 := Vector2(box.end.x, box.position.y)
	var c2 := box.end
	var c3 := Vector2(box.position.x, box.end.y)
	reach = maxf(reach, absf((c0 - origin).dot(tangent)) + 4.0)
	reach = maxf(reach, absf((c1 - origin).dot(tangent)) + 4.0)
	reach = maxf(reach, absf((c2 - origin).dot(tangent)) + 4.0)
	reach = maxf(reach, absf((c3 - origin).dot(tangent)) + 4.0)
	var p0 := origin - tangent * reach
	var p1 := origin + tangent * reach
	var poly := PackedVector2Array()
	poly.append(p0 - side)
	poly.append(p1 - side)
	poly.append(p1 + side)
	poly.append(p0 + side)
	return _ccw(poly)


func _split_outside_strip(subject: PackedVector2Array, a: Vector2, b: Vector2, half: float) -> Array:
	var chord := b - a
	var run := chord.length()
	if run < 0.001:
		return [subject]
	var tangent := chord / run
	var side := Vector2(-tangent.y, tangent.x)
	var left := _clip_halfplane(subject, a + side * half, side)
	var right := _clip_halfplane(subject, a - side * half, -side)
	var out: Array = []
	if left.size() >= 3 and _poly_area(left) >= MIN_FOOTPRINT:
		out.append(left)
	if right.size() >= 3 and _poly_area(right) >= MIN_FOOTPRINT:
		out.append(right)
	return out


func _clip_halfplane(poly: PackedVector2Array, origin: Vector2, normal: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	if n < 2:
		return out
	var prev: Vector2 = poly[n - 1]
	var prev_in := (prev - origin).dot(normal) >= -0.02
	for index in n:
		var cur: Vector2 = poly[index]
		var cur_in := (cur - origin).dot(normal) >= -0.02
		if cur_in:
			if not prev_in:
				out.append(_plane_hit(prev, cur, origin, normal))
			out.append(cur)
		elif prev_in:
			out.append(_plane_hit(prev, cur, origin, normal))
		prev = cur
		prev_in = cur_in
	if out.size() < 3:
		return PackedVector2Array()
	return _ccw(out)


func _plane_hit(p: Vector2, q: Vector2, origin: Vector2, normal: Vector2) -> Vector2:
	var den := (q - p).dot(normal)
	if absf(den) < 0.000001:
		return q
	var t := (origin - p).dot(normal) / den
	return p.lerp(q, clampf(t, 0.0, 1.0))


func _remnant_off_road(lot: Dictionary, cutters: Array) -> Array:
	var poly := _lot_rect(lot)
	var centre := _poly_centroid(poly)
	for _step in 8:
		var push := Vector2.ZERO
		for cutter in cutters:
			var road: PackedVector2Array = cutter["poly"]
			if Geometry2D.is_point_in_polygon(centre, road):
				push += centre - _poly_centroid(road)
		if push.length_squared() < 0.0001:
			push = Vector2.RIGHT.rotated(_rng.randf() * TAU)
		push = push.normalized() * 4.5
		poly = _shift_poly(poly, push)
		centre += push
		var pieces: Array = [poly]
		for cutter in cutters:
			var next: Array = []
			for piece in pieces:
				next.append_array(_subtract_piece(piece, cutter))
			pieces = next
			if pieces.is_empty():
				break
		if not pieces.is_empty():
			return pieces
		poly = _scale_poly(poly, 0.82)
	var along: Vector2 = lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across := Vector2(-along.y, along.x)
	var at: Vector2 = lot["centre"] + across * (float(lot["depth"]) * 0.35 + 3.0)
	var fallback := PackedVector2Array()
	var hx := along * 3.2
	var hy := across * 2.4
	fallback.append(at - hx - hy)
	fallback.append(at + hx - hy)
	fallback.append(at + hx + hy)
	fallback.append(at - hx + hy)
	var seed: Array = [_ccw(fallback)]
	for cutter in cutters:
		var next: Array = []
		for piece in seed:
			next.append_array(_subtract_piece(piece, cutter))
		seed = next
		if seed.is_empty():
			break
	return seed


func _reject_road_hits(pieces: Array, cutters: Array, paths: Array) -> Array:
	var kept: Array = []
	for piece in pieces:
		var poly: PackedVector2Array = piece
		if _poly_area(poly) < MIN_FOOTPRINT:
			continue
		if _poly_inradius(poly) < MIN_INRADIUS:
			continue
		if _hits_any_cutter(poly, cutters):
			continue
		if _hits_any_path(poly, paths):
			continue
		kept.append(poly)
	return kept


func _hits_any_cutter(poly: PackedVector2Array, cutters: Array) -> bool:
	var mid := _vertex_mid(poly)
	for cutter in cutters:
		if Geometry2D.is_point_in_polygon(mid, cutter["poly"]):
			return true
	return false


func _hits_any_path(poly: PackedVector2Array, paths: Array) -> bool:
	var mid := _vertex_mid(poly)
	for path in paths:
		var row: Dictionary = path
		var uv: PackedVector2Array = row["uv"]
		if uv.size() < 2:
			continue
		if _point_to_path(mid, uv) + 0.35 < float(row["half"]):
			return true
	return false


func _slice_until_clear(pieces: Array, paths: Array) -> Array:
	var work: Array = pieces
	for _pass in 6:
		var next: Array = []
		var dirty := false
		for piece in work:
			var poly: PackedVector2Array = piece
			var hit := _nearest_hit_path(poly, paths)
			if hit.is_empty():
				next.append(poly)
				continue
			dirty = true
			var a: Vector2 = hit["a"]
			var b: Vector2 = hit["b"]
			var sliced := _split_outside_strip(poly, a, b, float(hit["half"]) + ROAD_CLEAR)
			if sliced.is_empty():
				sliced = _convex_clear(poly, paths)
			for part in sliced:
				if _poly_area(part) < MIN_FOOTPRINT:
					continue
				if _hits_any_path(part, paths):
					next.append_array(_convex_clear(part, paths))
				else:
					next.append(part)
		work = next
		if not dirty:
			break
	return _reject_road_hits(work, [], paths)


func _nearest_hit_path(poly: PackedVector2Array, paths: Array) -> Dictionary:
	var mid := _vertex_mid(poly)
	var best: Dictionary = {}
	var best_d := 1.0e12
	for path in paths:
		var row: Dictionary = path
		var uv: PackedVector2Array = row["uv"]
		if uv.size() < 2:
			continue
		var dist := _point_to_path(mid, uv)
		if dist + 0.35 >= float(row["half"]):
			continue
		if dist >= best_d:
			continue
		best_d = dist
		var seg := _nearest_segment(mid, uv, bool(row.get("closed", false)))
		best = {
			"a": seg[0],
			"b": seg[1],
			"half": float(row["half"]),
		}
	return best


func _convex_clear(poly: PackedVector2Array, paths: Array) -> Array:
	if not _polygon_decomposable(poly):
		return []
	var parts: Array = Geometry2D.decompose_polygon_in_convex(poly)
	var kept: Array = []
	for part in parts:
		var keep := _ccw(part)
		if _poly_area(keep) < MIN_FOOTPRINT:
			continue
		if _hits_any_path(keep, paths):
			continue
		kept.append(keep)
	return kept


func _polygon_decomposable(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	for point in poly:
		if not point.is_finite():
			return false
	return _poly_area(_ccw(poly)) >= MIN_FOOTPRINT * 0.25


func _vertex_mid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for point in poly:
		acc += point
	return acc / float(poly.size())


func _point_to_path(at: Vector2, path: PackedVector2Array) -> float:
	var nearest := 1.0e12
	if path.size() <= 1:
		return at.distance_to(path[0]) if path.size() == 1 else nearest
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var ab := b - a
		var run := ab.length_squared()
		var t := 0.0
		if run >= 0.0001:
			t = clampf((at - a).dot(ab) / run, 0.0, 1.0)
		nearest = minf(nearest, at.distance_to(a.lerp(b, t)))
	return nearest


func _nearest_segment(at: Vector2, path: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(path[0])
	out.append(path[mini(1, path.size() - 1)])
	var nearest := 1.0e12
	var count := path.size()
	var segments := count if closed and count >= 3 else count - 1
	if closed and count >= 3 and path[0].distance_to(path[count - 1]) < 2.0:
		segments = count - 1
	for index in segments:
		var a: Vector2 = path[index]
		var b: Vector2 = path[(index + 1) % count]
		var ab := b - a
		var run := ab.length_squared()
		var t := 0.0
		if run >= 0.0001:
			t = clampf((at - a).dot(ab) / run, 0.0, 1.0)
		var dist := at.distance_to(a.lerp(b, t))
		if dist < nearest:
			nearest = dist
			out[0] = a
			out[1] = b
	return out


## Pull width, depth and centre back onto the biggest clipped piece so authored
## hulls use the same pad the procedural footprints already stay on.
func _fit_lot_to_footprint(lot: Dictionary) -> void:
	var pieces: Array = lot.get("footprints", [])
	if pieces.is_empty():
		return
	var biggest: PackedVector2Array = pieces[0]
	var best := -1.0
	for piece in pieces:
		var poly: PackedVector2Array = piece
		var area := _poly_area(poly)
		if area > best:
			best = area
			biggest = poly
	if biggest.size() < 3:
		return
	var along: Vector2 = lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across: Vector2 = lot.get("across", Vector2(-along.y, along.x))
	if across.length_squared() < 0.0001:
		across = Vector2(-along.y, along.x)
	across = across.normalized()
	var min_s := 1.0e9
	var max_s := -1.0e9
	var min_t := 1.0e9
	var max_t := -1.0e9
	for point in biggest:
		var at: Vector2 = point
		var s := at.dot(along)
		var t := at.dot(across)
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)
		min_t = minf(min_t, t)
		max_t = maxf(max_t, t)
	var width := maxf(max_s - min_s, _cell * 0.6)
	var depth := maxf(max_t - min_t, _cell * 0.6)
	var centre := along * ((min_s + max_s) * 0.5) + across * ((min_t + max_t) * 0.5)
	for _pass in 14:
		if _rect_inside_poly(biggest, centre, along, across, width, depth):
			break
		width *= 0.9
		depth *= 0.9
		if width < _cell * 0.5 or depth < _cell * 0.5:
			break
	lot["centre"] = centre
	lot["width"] = maxf(width - 0.35, _cell * 0.6)
	lot["depth"] = maxf(depth - 0.35, _cell * 0.6)


func _rect_inside_poly(
		poly: PackedVector2Array,
		centre: Vector2,
		along: Vector2,
		across: Vector2,
		width: float,
		depth: float
	) -> bool:
	var hw := width * 0.5
	var hd := depth * 0.5
	var spots: Array[Vector2] = [
		centre,
		centre + along * hw + across * hd,
		centre + along * hw - across * hd,
		centre - along * hw + across * hd,
		centre - along * hw - across * hd,
		centre + along * hw,
		centre - along * hw,
		centre + across * hd,
		centre - across * hd,
	]
	for spot in spots:
		if not Geometry2D.is_point_in_polygon(spot, poly):
			return false
	return true


func _lot_rect(lot: Dictionary) -> PackedVector2Array:
	var centre: Vector2 = lot["centre"]
	var along: Vector2 = lot["along"]
	var across: Vector2 = lot["across"]
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	if across.length_squared() < 0.0001:
		across = Vector2(-along.y, along.x)
	across = across.normalized()
	var x := along * (float(lot["width"]) * 0.5)
	var y := across * (float(lot["depth"]) * 0.5)
	var poly := PackedVector2Array()
	poly.append(centre - x - y)
	poly.append(centre + x - y)
	poly.append(centre + x + y)
	poly.append(centre - x + y)
	return _ccw(poly)


func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() >= 3 and Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	return poly


func _poly_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	if n < 3:
		return 0.0
	for index in n:
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % n]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


func _poly_inradius(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var mid := _poly_centroid(poly)
	var best := 1.0e9
	for index in poly.size():
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var ab := b - a
		var run := ab.length_squared()
		var away := mid.distance_to(a)
		if run >= 0.0001:
			var t := clampf((mid - a).dot(ab) / run, 0.0, 1.0)
			away = mid.distance_to(a.lerp(b, t))
		best = minf(best, away)
	if best > 1.0e8:
		return 0.0
	return best


func _point_to_ring(at: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 1.0e9
	if Geometry2D.is_point_in_polygon(at, poly):
		return 0.0
	var best := 1.0e9
	for index in poly.size():
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var ab := b - a
		var run := ab.length_squared()
		if run < 0.0001:
			best = minf(best, at.distance_to(a))
			continue
		var t := clampf((at - a).dot(ab) / run, 0.0, 1.0)
		best = minf(best, at.distance_to(a.lerp(b, t)))
	return best


func _sanitize_pieces(pieces: Array) -> Array:
	var kept: Array = []
	for piece in pieces:
		var poly: PackedVector2Array = piece
		kept.append_array(_sanitize_poly(poly))
	return kept


func _sanitize_poly(poly: PackedVector2Array) -> Array:
	var ring := _dedupe_ring(poly)
	if _poly_building_ok(ring):
		return [ring]
	if not _polygon_decomposable(ring):
		return []
	var fat: Array = []
	for part in Geometry2D.decompose_polygon_in_convex(ring):
		var keep := _dedupe_ring(part)
		if _poly_building_ok(keep):
			fat.append(keep)
	return fat


func _poly_building_ok(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	if _poly_area(poly) < MIN_FOOTPRINT:
		return false
	var radius := _poly_inradius(poly)
	if radius < MIN_INRADIUS:
		return false
	var box := _poly_aabb(poly)
	if minf(box.size.x, box.size.y) < MIN_INRADIUS * 2.0:
		return false
	var mid := _poly_centroid(poly)
	var farthest := 0.0
	for point in poly:
		farthest = maxf(farthest, point.distance_to(mid))
	return farthest <= radius * 12.0


func _dedupe_ring(poly: PackedVector2Array) -> PackedVector2Array:
	if poly.size() < 3:
		return PackedVector2Array()
	var ring := _ccw(poly)
	var kept := PackedVector2Array()
	for point in ring:
		if kept.is_empty() or kept[kept.size() - 1].distance_to(point) >= 0.15:
			kept.append(point)
	if kept.size() >= 2 and kept[0].distance_to(kept[kept.size() - 1]) < 0.15:
		kept.remove_at(kept.size() - 1)
	if kept.size() < 3:
		return PackedVector2Array()
	return kept


func _poly_centroid(poly: PackedVector2Array) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for point in poly:
		acc += point
	return acc / float(poly.size())


func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var box := Rect2(poly[0], Vector2.ZERO)
	for index in range(1, poly.size()):
		box = box.expand(poly[index])
	return box.grow(0.4)


func _shift_poly(poly: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in poly:
		out.append(point + delta)
	return out


func _scale_poly(poly: PackedVector2Array, scale: float) -> PackedVector2Array:
	var mid := _poly_centroid(poly)
	var out := PackedVector2Array()
	for point in poly:
		out.append(mid + (point - mid) * scale)
	return out


func _coverage(typology: int, packed: bool, nudge: float, tight := false) -> float:
	var lo := 0.50
	var hi := 0.68
	match typology:
		TYPE_TOWNHOUSE:
			lo = 0.56
			hi = 0.74
		TYPE_APARTMENT:
			lo = 0.66
			hi = 0.86
		TYPE_SHOP:
			lo = 0.72
			hi = 0.90
		TYPE_TOWER:
			lo = 0.58
			hi = 0.80
		TYPE_SKY:
			lo = 0.54
			hi = 0.76
	if tight and typology <= TYPE_TOWNHOUSE:
		lo = 0.70 if typology == TYPE_HOUSE else 0.78
		hi = 0.88 if typology == TYPE_HOUSE else 0.92
	if tight and typology == TYPE_SHOP:
		lo = 0.78
		hi = 0.92
	var cover := _rng.randf_range(lo, hi) + nudge
	if packed:
		cover = maxf(cover, lo + 0.06)
	return clampf(cover, 0.24, 0.92)


func _stories(typology: int) -> float:
	match typology:
		TYPE_TOWNHOUSE:
			return float(_rng.randi_range(2, 3))
		TYPE_APARTMENT:
			return float(_rng.randi_range(4, 8))
		TYPE_SHOP:
			return float(_rng.randi_range(3, 6))
		TYPE_TOWER:
			return float(_rng.randi_range(10, 18))
		TYPE_SKY:
			return float(_rng.randi_range(20, 56))
	return float(_rng.randi_range(1, 2))


func _name_lots() -> void:
	var counters: Dictionary = {}
	for lot in _lots:
		var row: Dictionary = lot
		var street := String(row.get("street_name", ""))
		if street.is_empty():
			street = "Lane"
		var n := int(counters.get(street, 0)) + 2
		counters[street] = n
		var typology: int = int(row["typology"])
		if typology == TYPE_LANDMARK:
			if String(row.get("name", "")).is_empty():
				var hall := "%s Hall" % String(row.get("district_name", "District"))
				row["name"] = _unique(hall)
			_building_serial += 1
			row["serial"] = _building_serial
			continue
		if typology == TYPE_TOWN_CENTER:
			var city := _city_name if not _city_name.is_empty() else "City"
			_building_serial += 1
			row["name"] = _unique("%s Town Center" % city)
			row["serial"] = _building_serial
			continue
		if bool(row.get("mega", false)):
			var stem := String(row.get("street_name", "Harbor"))
			if stem.is_empty():
				stem = "Harbor"
			_building_serial += 1
			row["name"] = _unique("%s Spire" % stem)
			row["serial"] = _building_serial
			continue
		var title := "%d %s" % [n, street]
		match typology:
			TYPE_SHOP:
				title = "%s Shop" % street
			TYPE_TOWER:
				title = "%s Tower" % street
			TYPE_SKY:
				title = "%s Heights" % street
			TYPE_APARTMENT:
				title = "%s Court" % street if n % 4 == 0 else title
		_building_serial += 1
		row["name"] = _unique(title)
		row["serial"] = _building_serial


func _stamp_and_record(
		district_id: int,
		cells: Dictionary,
		path: PackedVector2Array,
		rank: int,
		half: float,
		_density: float
	) -> void:
	if path.size() < 2:
		return
	var parts := _split_path_on_cells(path, cells)
	for part in parts:
		var kept: PackedVector2Array = part
		if kept.size() < 2:
			continue
		_stamp_path(cells, kept, half, rank)
		var name := _street_name(rank, kept)
		_streets.append({
			"uv": kept,
			"rank": rank,
			"name": name,
			"district_id": district_id,
			"half": half,
			"mid": kept[kept.size() / 2],
		})


func _knit_intersections() -> void:
	if _streets.size() < 2:
		return
	var raw: Array = []
	_collect_crossings(raw)
	_collect_tee_and_ends(raw)
	_junctions = _merge_junction_points(raw)
	_embed_junctions()
	_drop_lonely_junctions()


func _cells_of(district_id: int) -> Dictionary:
	for job in _fill_jobs:
		var row: Dictionary = job
		if int(row["id"]) == district_id:
			return row["cells"]
	return {}


func _clip_streets_to_pad() -> void:
	var next: Array = []
	for street in _streets:
		var row: Dictionary = street
		var cells := _cells_of(int(row["district_id"]))
		if cells.is_empty():
			cells = _owner
		var parts := _split_path_on_cells(row["uv"], cells)
		for part in parts:
			var kept: PackedVector2Array = part
			if kept.size() < 2:
				continue
			var copy: Dictionary = row.duplicate()
			copy["uv"] = kept
			copy["mid"] = kept[kept.size() / 2]
			next.append(copy)
	_streets = next


func _cut_streets_off_highway(arteries: Dictionary) -> void:
	if arteries.is_empty():
		return
	var hw: PackedVector2Array = arteries.get("highway", PackedVector2Array())
	var hw_half := float(arteries.get("highway_half", 8.0))
	var spur: PackedVector2Array = arteries.get("spur", PackedVector2Array())
	var spur_half := float(arteries.get("spur_half", 6.0))
	var next: Array = []
	for street in _streets:
		var row: Dictionary = street
		var extra := float(row["half"]) + 0.6
		var parts := _split_path_clear_of(
			row["uv"], hw, hw_half + extra, true, spur, spur_half + extra)
		for part in parts:
			var kept: PackedVector2Array = part
			if kept.size() < 2:
				continue
			var copy: Dictionary = row.duplicate()
			copy["uv"] = kept
			copy["mid"] = kept[kept.size() / 2]
			next.append(copy)
	_streets = next


func _drop_highway_junctions(arteries: Dictionary) -> void:
	if _junctions.is_empty() or arteries.is_empty():
		return
	var hw: PackedVector2Array = arteries.get("highway", PackedVector2Array())
	var hw_half := float(arteries.get("highway_half", 8.0)) + 1.2
	var spur: PackedVector2Array = arteries.get("spur", PackedVector2Array())
	var spur_half := float(arteries.get("spur_half", 6.0)) + 1.0
	var kept: Array = []
	for junction in _junctions:
		var row: Dictionary = junction
		var at: Vector2 = row["at"]
		if hw.size() >= 2 and _path_distance(at, hw, true) < hw_half:
			continue
		if spur.size() >= 2 and _path_distance(at, spur, false) < spur_half:
			continue
		kept.append(row)
	_junctions = kept


func _restamp_roads() -> void:
	_roads.clear()
	_tangents.clear()
	_ranks.clear()
	for street in _streets:
		var row: Dictionary = street
		var path: PackedVector2Array = row["uv"]
		if path.size() >= 2:
			row["mid"] = path[path.size() / 2]
		_stamp_path(
			_owner,
			path,
			float(row["half"]),
			int(row["rank"]))


func _uv_on_pad(uv: Vector2) -> bool:
	var key := Vector2i(roundi(uv.x / _cell), roundi(uv.y / _cell))
	return _owner.has(key)


func _uv_near_pad(uv: Vector2) -> bool:
	if _uv_on_pad(uv):
		return true
	var cx := roundi(uv.x / _cell)
	var cy := roundi(uv.y / _cell)
	var reach := _cell * 0.85
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var key := Vector2i(cx + ox, cy + oy)
			if not _owner.has(key):
				continue
			if _cell_uv(key).distance_to(uv) <= reach:
				return true
	return false


func _densify_path(path: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.is_empty():
		return out
	out.append(path[0])
	var step := maxf(_cell * 0.45, 1.2)
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var run := a.distance_to(b)
		var pieces := maxi(1, int(ceili(run / step)))
		for piece in range(1, pieces + 1):
			var at := a.lerp(b, float(piece) / float(pieces))
			if out[out.size() - 1].distance_squared_to(at) > 0.25:
				out.append(at)
	return out


func _split_kept_samples(samples: PackedVector2Array, kept_flags: PackedByteArray) -> Array:
	var parts: Array = []
	var current := PackedVector2Array()
	for index in samples.size():
		if kept_flags[index] != 0:
			var at: Vector2 = samples[index]
			if current.is_empty() or current[current.size() - 1].distance_squared_to(at) > 0.25:
				current.append(at)
		else:
			if current.size() >= 2:
				parts.append(current)
			current = PackedVector2Array()
	if current.size() >= 2:
		parts.append(current)
	return parts


func _split_path_on_cells(path: PackedVector2Array, cells: Dictionary) -> Array:
	var samples := _densify_path(path)
	var flags := PackedByteArray()
	flags.resize(samples.size())
	for index in samples.size():
		var at: Vector2 = samples[index]
		var key := Vector2i(roundi(at.x / _cell), roundi(at.y / _cell))
		flags[index] = 1 if cells.has(key) else 0
	return _split_kept_samples(samples, flags)


func _split_path_clear_of(
		path: PackedVector2Array,
		hw: PackedVector2Array,
		hw_reach: float,
		hw_closed: bool,
		spur: PackedVector2Array,
		spur_reach: float
	) -> Array:
	var samples := _densify_path(path)
	var flags := PackedByteArray()
	flags.resize(samples.size())
	for index in samples.size():
		var at: Vector2 = samples[index]
		var blocked := false
		if hw.size() >= 2 and _path_distance(at, hw, hw_closed) < hw_reach:
			blocked = true
		elif spur.size() >= 2 and _path_distance(at, spur, false) < spur_reach:
			blocked = true
		flags[index] = 0 if blocked else 1
	return _split_kept_samples(samples, flags)


func _path_distance(at: Vector2, path: PackedVector2Array, closed: bool) -> float:
	if path.size() <= 1 or not closed:
		return _point_to_path(at, path)
	var wrapped := path.duplicate()
	if path[0].distance_to(path[path.size() - 1]) > 1.5:
		wrapped.append(path[0])
	return _point_to_path(at, wrapped)


func _collect_crossings(raw: Array) -> void:
	var segs := _street_segments()
	var bins := _bin_segments(segs)
	var seen: Dictionary = {}
	for seg in segs:
		var row: Dictionary = seg
		var box := Rect2(row["a"], Vector2.ZERO).expand(row["b"]).grow(2.0)
		for other in _segments_near(bins, box):
			var hit := _seg_hit(row, other)
			if not hit.is_finite():
				continue
			var si: int = int(row["si"])
			var sj: int = int(other["si"])
			var ei: int = int(row["ei"])
			var ej: int = int(other["ei"])
			if si == sj and absi(ei - ej) <= 1:
				continue
			var key := Vector2i(mini(si, sj), maxi(si, sj))
			var edge := Vector2i(mini(ei, ej), maxi(ei, ej))
			var token := "%d:%d:%d:%d" % [key.x, key.y, edge.x, edge.y]
			if seen.has(token):
				continue
			seen[token] = true
			raw.append({
				"at": hit,
				"half": maxf(float(row["half"]), float(other["half"])),
				"rank": mini(int(row["rank"]), int(other["rank"])),
			})


func _collect_tee_and_ends(raw: Array) -> void:
	var segs := _street_segments()
	var bins := _bin_segments(segs)
	for index in _streets.size():
		var street: Dictionary = _streets[index]
		var path: PackedVector2Array = street["uv"]
		if path.size() < 2:
			continue
		var half := float(street["half"])
		var rank: int = int(street["rank"])
		_snap_end_into(raw, path[0], index, half, rank, segs, bins, path[1] - path[0])
		_snap_end_into(
			raw,
			path[path.size() - 1],
			index,
			half,
			rank,
			segs,
			bins,
			path[path.size() - 1] - path[path.size() - 2])


func _snap_end_into(
		raw: Array,
		at: Vector2,
		street_i: int,
		half: float,
		rank: int,
		_segs: Array,
		bins: Dictionary,
		tangent: Vector2
	) -> void:
	var box := Rect2(at, Vector2.ZERO).grow(7.0)
	var best := Vector2(INF, INF)
	var best_d := 5.6
	var best_half := half
	var best_rank := rank
	var aim := tangent
	if aim.length_squared() > 0.0001:
		aim = aim.normalized()
	for other in _segments_near(bins, box):
		var row: Dictionary = other
		if int(row["si"]) == street_i:
			continue
		var hit := _closest_on_seg(at, row["a"], row["b"])
		var away := at.distance_to(hit)
		if away >= best_d:
			continue
		var chord: Vector2 = row["b"] - row["a"]
		if chord.length_squared() > 0.0001 and aim.length_squared() > 0.0001:
			if absf(aim.dot(chord.normalized())) > 0.94:
				continue
		best_d = away
		best = hit
		best_half = maxf(half, float(row["half"]))
		best_rank = mini(rank, int(row["rank"]))
	if best.is_finite():
		raw.append({"at": best, "half": best_half, "rank": best_rank})
		raw.append({"at": at, "half": half, "rank": rank})


func _street_segments() -> Array:
	var segs: Array = []
	for index in _streets.size():
		var street: Dictionary = _streets[index]
		var path: PackedVector2Array = street["uv"]
		if path.size() < 2:
			continue
		for edge in path.size() - 1:
			var a: Vector2 = path[edge]
			var b: Vector2 = path[edge + 1]
			if a.distance_to(b) < 0.35:
				continue
			segs.append({
				"si": index,
				"ei": edge,
				"a": a,
				"b": b,
				"half": float(street["half"]),
				"rank": int(street["rank"]),
			})
	return segs


func _bin_segments(segs: Array) -> Dictionary:
	var bins: Dictionary = {}
	for seg in segs:
		var row: Dictionary = seg
		var box := Rect2(row["a"], Vector2.ZERO).expand(row["b"])
		var min_x := int(floor(box.position.x / 36.0))
		var min_y := int(floor(box.position.y / 36.0))
		var max_x := int(floor(box.end.x / 36.0))
		var max_y := int(floor(box.end.y / 36.0))
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				var key := Vector2i(x, y)
				var bucket: Array = bins.get(key, [])
				bucket.append(row)
				bins[key] = bucket
	return bins


func _segments_near(bins: Dictionary, box: Rect2) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	var min_x := int(floor(box.position.x / 36.0)) - 1
	var min_y := int(floor(box.position.y / 36.0)) - 1
	var max_x := int(floor(box.end.x / 36.0)) + 1
	var max_y := int(floor(box.end.y / 36.0)) + 1
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for seg in bins.get(Vector2i(x, y), []):
				var row: Dictionary = seg
				var token := "%d:%d" % [int(row["si"]), int(row["ei"])]
				if seen.has(token):
					continue
				seen[token] = true
				out.append(row)
	return out


func _merge_junction_points(raw: Array) -> Array:
	var merged: Array = []
	for item in raw:
		var row: Dictionary = item
		var at: Vector2 = row["at"]
		if not at.is_finite():
			continue
		var found := false
		for other in merged:
			var hold: Dictionary = other
			if at.distance_to(hold["at"]) > 3.6:
				continue
			var n := int(hold.get("n", 1))
			hold["at"] = (hold["at"] * float(n) + at) / float(n + 1)
			hold["half"] = maxf(float(hold["half"]), float(row["half"]))
			hold["rank"] = mini(int(hold["rank"]), int(row["rank"]))
			hold["n"] = n + 1
			found = true
			break
		if not found:
			merged.append({
				"at": at,
				"half": float(row["half"]),
				"rank": int(row["rank"]),
				"n": 1,
			})
	return merged


func _embed_junctions() -> void:
	for street in _streets:
		var row: Dictionary = street
		row["uv"] = _path_with_junctions(row["uv"])


func _path_with_junctions(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 2 or _junctions.is_empty():
		return path
	var out := PackedVector2Array()
	var start := _snap_to_junction(path[0])
	out.append(start)
	for index in path.size() - 1:
		var a: Vector2 = out[out.size() - 1]
		var b := _snap_to_junction(path[index + 1])
		var hits: Array = []
		for junction in _junctions:
			var at: Vector2 = (junction as Dictionary)["at"]
			if at.distance_to(a) < 1.1 or at.distance_to(b) < 1.1:
				continue
			var on := _closest_on_seg(at, a, b)
			if at.distance_to(on) > 1.4:
				continue
			var run := a.distance_to(b)
			if run < 0.2:
				continue
			hits.append({
				"t": a.distance_to(on) / run,
				"at": at,
			})
		hits.sort_custom(_sooner_hit)
		for hit in hits:
			var at: Vector2 = (hit as Dictionary)["at"]
			if out[out.size() - 1].distance_to(at) > 0.8:
				out.append(at)
		if out[out.size() - 1].distance_to(b) > 0.8:
			out.append(b)
	return out


func _snap_to_junction(at: Vector2) -> Vector2:
	var best := at
	var nearest := 3.6
	for junction in _junctions:
		var row: Dictionary = junction
		var away := at.distance_to(row["at"])
		if away < nearest:
			nearest = away
			best = row["at"]
	return best


func _sooner_hit(p: Dictionary, q: Dictionary) -> bool:
	return float(p["t"]) < float(q["t"])


func _drop_lonely_junctions() -> void:
	var kept: Array = []
	for junction in _junctions:
		var row: Dictionary = junction
		var at: Vector2 = row["at"]
		var streets := 0
		for street in _streets:
			var path: PackedVector2Array = (street as Dictionary)["uv"]
			var on := false
			for point in path:
				if point.distance_to(at) <= 1.8:
					on = true
					break
			if on:
				streets += 1
			if streets >= 2:
				break
		if streets >= 2:
			kept.append(row)
	_junctions = kept


func _seg_hit(left: Dictionary, right: Dictionary) -> Vector2:
	var a: Vector2 = left["a"]
	var b: Vector2 = left["b"]
	var c: Vector2 = right["a"]
	var d: Vector2 = right["b"]
	var r := b - a
	var s := d - c
	var den := r.x * s.y - r.y * s.x
	if absf(den) < 0.0000001:
		return Vector2(INF, INF)
	var rel := c - a
	var t := (rel.x * s.y - rel.y * s.x) / den
	var u := (rel.x * r.y - rel.y * r.x) / den
	if t < 0.04 or t > 0.96 or u < 0.04 or u > 0.96:
		return Vector2(INF, INF)
	return a.lerp(b, t)


func _closest_on_seg(at: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var run := ab.length_squared()
	if run < 0.0001:
		return a
	var t := clampf((at - a).dot(ab) / run, 0.0, 1.0)
	return a.lerp(b, t)


func _street_name(rank: int, path: PackedVector2Array) -> String:
	_street_serial += 1
	var stem: String = STEMS[_rng.randi() % STEMS.size()]
	if rank == RANK_ALLEY:
		return _unique("%s Alley" % stem)
	if rank == RANK_ARTERIAL:
		return _unique("%s Avenue" % stem)
	var word: String = STREET_WORD[_rng.randi() % STREET_WORD.size()]
	return _unique("%s %s" % [stem, word])


func _unique(title: String) -> String:
	var name := title
	var n := 2
	while _taken.has(name):
		name = "%s %d" % [title, n]
		n += 1
	_taken[name] = true
	return name


func _stamp_path(cells: Dictionary, path: PackedVector2Array, half: float, rank: int) -> void:
	var reach := maxi(1, int(ceili(half / _cell)))
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var chord := b - a
		var run := chord.length()
		if run < 0.2:
			continue
		var tangent := chord / run
		var pieces := maxi(1, int(ceili(run / maxf(_cell * 0.45, 1.2))))
		for piece in pieces + 1:
			var at := a.lerp(b, float(piece) / float(pieces))
			var cx := roundi(at.x / _cell)
			var cy := roundi(at.y / _cell)
			for ox in range(-reach, reach + 1):
				for oy in range(-reach, reach + 1):
					var key := Vector2i(cx + ox, cy + oy)
					if not cells.has(key):
						continue
					if _cell_uv(key).distance_to(at) > half + _cell * 0.55:
						continue
					_roads[key] = true
					_tangents[key] = tangent
					_ranks[key] = rank


func _open_cells(district_id: int, cells: Dictionary) -> Dictionary:
	var open: Dictionary = {}
	for key in cells:
		if _roads.has(key):
			continue
		if int(_owner.get(key, -1)) != district_id:
			continue
		open[key] = true
	return open


func _components(cells: Dictionary) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for start in cells:
		if seen.has(start):
			continue
		var blob: Dictionary = {}
		var stack: Array = [start]
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			if seen.has(at) or not cells.has(at):
				continue
			seen[at] = true
			blob[at] = true
			stack.append(Vector2i(at.x + 1, at.y))
			stack.append(Vector2i(at.x - 1, at.y))
			stack.append(Vector2i(at.x, at.y + 1))
			stack.append(Vector2i(at.x, at.y - 1))
		if blob.size() >= 2:
			out.append(blob)
	return out


func _mst(nodes: PackedVector2Array) -> Array:
	var edges: Array = []
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			edges.append({
				"a": i,
				"b": j,
				"d": nodes[i].distance_squared_to(nodes[j]),
			})
	edges.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["d"]) < float(q["d"]))
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(nodes.size())
	for i in nodes.size():
		parent[i] = i
	var links: Array = []
	for edge in edges:
		var a: int = edge["a"]
		var b: int = edge["b"]
		var pa := _find(parent, a)
		var pb := _find(parent, b)
		if pa == pb:
			continue
		parent[pa] = pb
		links.append(Vector2i(a, b))
		if links.size() >= nodes.size() - 1:
			break
	return links


func _find(parent: PackedInt32Array, index: int) -> int:
	while parent[index] != index:
		parent[index] = parent[parent[index]]
		index = parent[index]
	return index


func _longest_unused(nodes: PackedVector2Array, links: Array) -> Vector2i:
	var used: Dictionary = {}
	for link in links:
		var pair: Vector2i = link
		used["%d-%d" % [mini(pair.x, pair.y), maxi(pair.x, pair.y)]] = true
	var best := Vector2i(-1, -1)
	var farthest := 0.0
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			if used.has("%d-%d" % [i, j]):
				continue
			var span := nodes[i].distance_squared_to(nodes[j])
			if span > farthest:
				farthest = span
				best = Vector2i(i, j)
	return best


func _jitter_path(a: Vector2, b: Vector2, wander: float) -> PackedVector2Array:
	var path := PackedVector2Array()
	path.append(a)
	var run := a.distance_to(b)
	var pieces := maxi(1, int(ceili(run / 64.0)))
	var chord := b - a
	var perp := Vector2(-chord.y, chord.x)
	if perp.length_squared() > 0.001:
		perp = perp.normalized()
	for piece in range(1, pieces):
		var t := float(piece) / float(pieces)
		var at := a.lerp(b, t)
		at += perp * _rng.randf_range(-wander, wander)
		path.append(at)
	path.append(b)
	return path


func _clip_to_block(path: PackedVector2Array, block: Dictionary) -> PackedVector2Array:
	var kept := PackedVector2Array()
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var run := a.distance_to(b)
		var pieces := maxi(2, int(ceili(run / _cell)))
		for piece in pieces + 1:
			var at := a.lerp(b, float(piece) / float(pieces))
			var key := Vector2i(roundi(at.x / _cell), roundi(at.y / _cell))
			if block.has(key):
				if kept.is_empty() or kept[kept.size() - 1].distance_squared_to(at) > 0.4:
					kept.append(at)
	return kept


func _extend_to_road(
		district_id: int,
		cells: Dictionary,
		path: PackedVector2Array
	) -> PackedVector2Array:
	if path.size() < 2:
		return path
	path = _extend_end(district_id, cells, path, true)
	return _extend_end(district_id, cells, path, false)


func _extend_end(
		district_id: int,
		cells: Dictionary,
		path: PackedVector2Array,
		front: bool
	) -> PackedVector2Array:
	var from: Vector2 = path[0] if front else path[path.size() - 1]
	var nxt: Vector2 = path[1] if front else path[path.size() - 2]
	var step := (from - nxt)
	if step.length_squared() < 0.01:
		return path
	step = step.normalized() * _cell
	var at := from
	for _i in 24:
		at += step
		var key := Vector2i(roundi(at.x / _cell), roundi(at.y / _cell))
		if not cells.has(key) or int(_owner.get(key, -1)) != district_id:
			break
		if front:
			path.insert(0, at)
		else:
			path.append(at)
		if _roads.has(key):
			break
	return path


func _exits_of(
		plan: PatchCityGenerator.Plan,
		district_id: int,
		cells: Dictionary,
		up: Vector3,
		east: Vector3,
		north: Vector3,
		radius: float
	) -> PackedVector2Array:
	var points := PackedVector2Array()
	for exit in plan.exits:
		var uv := _to_uv(exit.land, up, east, north, radius)
		var key := Vector2i(roundi(uv.x / _cell), roundi(uv.y / _cell))
		var mine := exit.district_id == district_id or cells.has(key)
		if not mine:
			var nearest := _nearest_cell(cells, uv)
			if nearest.x < 900000 and _cell_uv(nearest).distance_to(uv) < 48.0:
				uv = _cell_uv(nearest)
				mine = true
		if mine:
			points.append(uv)
	return points


func _neighbor_count(district_id: int, cells: Dictionary) -> int:
	var found: Dictionary = {}
	for key in cells:
		var at: Vector2i = key
		var look: Array = [
			Vector2i(at.x + 1, at.y), Vector2i(at.x - 1, at.y),
			Vector2i(at.x, at.y + 1), Vector2i(at.x, at.y - 1),
		]
		for other in look:
			var owner: int = int(_owner.get(other, -1))
			if owner >= 0 and owner != district_id:
				found[owner] = true
	return found.size()


func _bounds(cells: Dictionary) -> Vector4:
	var min_x := 1.0e9
	var min_y := 1.0e9
	var max_x := -1.0e9
	var max_y := -1.0e9
	for key in cells:
		var at := _cell_uv(key)
		min_x = minf(min_x, at.x)
		min_y = minf(min_y, at.y)
		max_x = maxf(max_x, at.x)
		max_y = maxf(max_y, at.y)
	return Vector4(min_x, min_y, max_x, max_y)


func _centroid(cells: Dictionary) -> Vector2:
	var acc := Vector2.ZERO
	for key in cells:
		acc += _cell_uv(key)
	return acc / float(maxi(cells.size(), 1))


func _cell_uv(key: Vector2i) -> Vector2:
	return Vector2(float(key.x) * _cell, float(key.y) * _cell)


func _nearest_cell(cells: Dictionary, uv: Vector2) -> Vector2i:
	var best := Vector2i(1000000, 1000000)
	var nearest := 1.0e12
	for key in cells:
		var away := _cell_uv(key).distance_squared_to(uv)
		if away < nearest:
			nearest = away
			best = key
	return best


func _nearest_tangent(uv: Vector2) -> Vector2:
	var cx := roundi(uv.x / _cell)
	var cy := roundi(uv.y / _cell)
	if _tangents.has(Vector2i(cx, cy)):
		return Vector2(_tangents[Vector2i(cx, cy)]).normalized()
	var best := Vector2.ZERO
	var nearest := 1.0e12
	for ox in range(-12, 13):
		for oy in range(-12, 13):
			var key := Vector2i(cx + ox, cy + oy)
			if not _tangents.has(key):
				continue
			var away := _cell_uv(key).distance_squared_to(uv)
			if away < nearest:
				nearest = away
				best = _tangents[key]
	if best.length_squared() > 0.0001:
		return best.normalized()
	return best


func _nearest_street_name(uv: Vector2) -> String:
	var best := ""
	var nearest := 90.0 * 90.0
	for street in _streets:
		var row: Dictionary = street
		var mid: Vector2 = row["mid"]
		var away := mid.distance_squared_to(uv)
		if away < nearest:
			nearest = away
			best = String(row["name"])
	return best


func _near_arterial(uv: Vector2) -> bool:
	var key := Vector2i(roundi(uv.x / _cell), roundi(uv.y / _cell))
	for ox in range(-3, 4):
		for oy in range(-3, 4):
			var at := Vector2i(key.x + ox, key.y + oy)
			if int(_ranks.get(at, -1)) == RANK_ARTERIAL:
				return true
	return false


func _is_corner(uv: Vector2) -> bool:
	var cx := roundi(uv.x / _cell)
	var cy := roundi(uv.y / _cell)
	var seen: Array[Vector2] = []
	for ox in range(-5, 6):
		for oy in range(-5, 6):
			var key := Vector2i(cx + ox, cy + oy)
			if not _tangents.has(key):
				continue
			var t: Vector2 = _tangents[key]
			if t.length_squared() < 0.0001:
				continue
			t = t.normalized()
			var fresh := true
			for old in seen:
				if absf(old.dot(t)) > 0.72:
					fresh = false
					break
			if fresh:
				seen.append(t)
			if seen.size() >= 2:
				return true
	return false


func _road_side(uv: Vector2, across: Vector2) -> float:
	var cx := roundi(uv.x / _cell)
	var cy := roundi(uv.y / _cell)
	var nearest := 1.0e12
	var side := 1.0
	for ox in range(-10, 11):
		for oy in range(-10, 11):
			var key := Vector2i(cx + ox, cy + oy)
			if not _roads.has(key):
				continue
			var pos := _cell_uv(key)
			var away := pos.distance_squared_to(uv)
			if away < nearest:
				nearest = away
				side = across.dot(pos - uv)
	return side


func _lot_width(density: float, ceiling: int, tight := false, rim := false, core := false) -> float:
	if tight:
		return clampf(lerpf(6.4, 4.6, density), 4.4, 6.8)
	if rim:
		return clampf(lerpf(11.2, 7.6, density), 7.2, 12.2)
	if core:
		return clampf(lerpf(17.4, 13.2, density), 12.4, 18.6)
	var width := lerpf(13.5, 8.0, density)
	if ceiling >= TYPE_SHOP:
		width = lerpf(18.0, 12.0, density)
	if ceiling >= TYPE_SKY:
		width = lerpf(22.0, 14.0, density)
	return clampf(width, 7.0, 24.0)


func _street_count(district_id: int) -> int:
	var n := 0
	for street in _streets:
		if int((street as Dictionary)["district_id"]) == district_id:
			n += 1
	return n


func _to_uv(
		direction: Vector3,
		up: Vector3,
		east: Vector3,
		north: Vector3,
		radius: float
	) -> Vector2:
	var q := direction - up * direction.dot(up)
	return Vector2(q.dot(east), q.dot(north)) * radius
