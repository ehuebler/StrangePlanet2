class_name CityMinimap
extends Control

## Circular city map for a mapped patch you are standing in.
##
## Tilde opens it next to the diagnostic plate. Close in, it is one district:
## grey streets and buildings, yellow halls, the town center in gold. Zoomed
## out it is only white district outlines, a star on the hall's district, and
## no city road.

const FONT: FontFile = preload("res://fonts/Bungee-Regular.ttf")
const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")

const SIZE := 188.0
const GAP := 10.0
const RING := 2.0
const NEAR_M := 78.0
const FAR_ALT := 380.0
const DISTRICT_VIEW := 165.0
const MAX_LABELS := 12
const INK_WHITE := Color(0.96, 0.97, 0.99, 0.96)
const INK_GREY := Color(0.40, 0.40, 0.43, 0.90)
const INK_BUILDING := Color(0.50, 0.50, 0.54, 0.82)
const INK_SPECIAL := Color(0.96, 0.84, 0.22, 0.94)
const INK_HALL := Color(0.94, 0.72, 0.16, 0.96)

var _plate: CoordinatePlate
var _city: PatchCity
var _player_uv := Vector2.ZERO
var _heading := Vector2(0, 1)
var _view_m := NEAR_M
var _altitude := 0.0


func _init() -> void:
	name = "CityMinimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	custom_minimum_size = Vector2(SIZE, SIZE)
	visible = false
	set_process(true)


func bind(plate: CoordinatePlate) -> void:
	_plate = plate


func refresh(
		at: Vector3,
		forward: Vector3,
		planet: Planet,
		overlay_on: bool
	) -> void:
	if not overlay_on:
		_city = null
		visible = false
		return
	_city = _city_holding(at)
	if _city == null:
		visible = false
		return
	_player_uv = _city.world_to_uv(at)
	var aim := _city.heading_uv(forward)
	if aim.length_squared() > 0.04:
		_heading = aim
	_altitude = _height_above(at, planet)
	_view_m = _city.minimap_view_metres(_altitude)
	_sit_beside_plate()
	visible = true
	queue_redraw()


static func name_visible(kind: StringName, distance: float, view_m: float) -> bool:
	if distance > view_m * 0.92:
		return false
	if kind == PatchCity.CityPlace.KIND_LANDMARK:
		return not district_overview(view_m)
	if kind == PatchCity.CityPlace.KIND_TOWN_CENTER:
		return not district_overview(view_m)
	if kind == PatchCity.CityPlace.KIND_DISTRICT:
		return district_overview(view_m)
	return false


static func district_overview(view_m: float) -> bool:
	return view_m >= DISTRICT_VIEW


func _process(_delta: float) -> void:
	if visible:
		_sit_beside_plate()


func _sit_beside_plate() -> void:
	var margin := CoordinatePlate.MARGIN
	var plate_w := 220.0
	if _plate != null and is_instance_valid(_plate) and _plate.visible:
		plate_w = maxf(_plate.size.x, 80.0)
		margin = absf(_plate.offset_right)
	offset_right = -(margin + plate_w + GAP)
	offset_bottom = -margin
	offset_left = offset_right - SIZE
	offset_top = offset_bottom - SIZE


func _city_holding(at: Vector3) -> PatchCity:
	if not is_inside_tree():
		return null
	var best: PatchCity = null
	var nearest := 1.0e12
	for node in get_tree().get_nodes_in_group(PatchCity.MAP_GROUP):
		var city := node as PatchCity
		if city == null or not city.contains_world(at):
			continue
		var away := city.world_to_uv(at).length_squared()
		if away < nearest:
			nearest = away
			best = city
	return best


func _height_above(at: Vector3, planet: Planet) -> float:
	if planet == null or planet.shape == null:
		return _altitude
	var local := planet.to_local(at)
	if local.length_squared() < 1.0:
		return 0.0
	var up := local.normalized()
	return local.length() - planet.shape.radius - planet.shape.elevation(
		up, planet.spacing_underfoot())


func _draw() -> void:
	if _city == null:
		return
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.5
	if radius < 8.0:
		return
	draw_circle(centre, radius, Color(PALETTE.paper.r, PALETTE.paper.g, PALETTE.paper.b, 0.88))
	var clip := _circle_poly(centre, radius - RING)
	_draw_districts(centre, radius, clip)
	if not district_overview(_view_m):
		_draw_lots(centre, radius, clip)
		_draw_streets(centre, radius)
	_draw_names(centre, radius)
	if district_overview(_view_m):
		_draw_hall_star(centre, radius)
	_draw_player(centre)
	draw_arc(centre, radius - RING * 0.5, 0.0, TAU, 64, PALETTE.accent, RING, true)


func _draw_districts(centre: Vector2, radius: float, _clip: PackedVector2Array) -> void:
	for item in _city.minimap.get("districts", []):
		var ring := _district_ring(item)
		if ring.size() < 3:
			continue
		_stroke_path(
			_path_to_screen(ring, centre, radius),
			INK_WHITE, 1.7, true, centre, radius)


func _draw_lots(centre: Vector2, radius: float, clip: PackedVector2Array) -> void:
	var reach := _view_m + 12.0
	for lot in _city.fabric.get("lots", []):
		var row: Dictionary = lot
		var at: Vector2 = row.get("centre", Vector2.ZERO)
		if at.distance_to(_player_uv) > reach:
			continue
		var footprints: Array = row.get("footprints", [])
		if footprints.is_empty():
			continue
		var colour := _lot_ink(row)
		for piece in footprints:
			var poly: PackedVector2Array = piece
			_fill_clipped(_path_to_screen(poly, centre, radius), clip, colour)


func _draw_streets(centre: Vector2, radius: float) -> void:
	for street in _city.minimap.get("streets", []):
		var row: Dictionary = street
		var half := float(row["half"])
		var street_uv: PackedVector2Array = row["uv"]
		_stroke_path(
			_path_to_screen(street_uv, centre, radius),
			INK_GREY, _stroke_px(half, radius), false, centre, radius)


func _draw_names(centre: Vector2, radius: float) -> void:
	if _city.places.is_empty():
		return
	var ranked: Array = []
	for place in _city.places:
		var uv := _city.place_uv(place)
		var dist := uv.distance_to(_player_uv)
		if not name_visible(place.kind, dist, _view_m):
			continue
		ranked.append({
			"place": place,
			"uv": uv,
			"d": dist,
			"w": _name_weight(place.kind, dist),
		})
	ranked.sort_custom(_heavier_label)
	var drawn := 0
	var occupied: Array = []
	for row in ranked:
		if drawn >= MAX_LABELS:
			break
		var info: Dictionary = row
		var uv: Vector2 = info["uv"]
		var at := _uv_to_screen(uv, centre, radius)
		if at.distance_to(centre) > radius - 14.0:
			continue
		if _label_blocked(at, occupied):
			continue
		var place = info["place"]
		var colour := PALETTE.text_primary
		var px := 9
		if place.kind == PatchCity.CityPlace.KIND_LANDMARK:
			colour = INK_SPECIAL
			px = 10
		elif place.kind == PatchCity.CityPlace.KIND_TOWN_CENTER:
			colour = INK_HALL
			px = 11
		elif place.kind == PatchCity.CityPlace.KIND_DISTRICT:
			px = 10
			colour = INK_WHITE
		var text := String(place.name)
		var size_px := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
		var pos := at + Vector2(-size_px.x * 0.5, 4.0)
		draw_string_outline(
			FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, PALETTE.ink)
		draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, colour)
		occupied.append(Rect2(pos, size_px))
		drawn += 1


func _draw_hall_star(centre: Vector2, radius: float) -> void:
	var hall_id := int(_city.minimap.get("town_district", -1))
	if hall_id < 0:
		return
	for item in _city.minimap.get("districts", []):
		if int(_district_id(item)) != hall_id:
			continue
		var ring := _district_ring(item)
		if ring.size() < 3:
			continue
		var mid := Vector2.ZERO
		for point in ring:
			mid += point
		mid /= float(ring.size())
		var at := _uv_to_screen(mid, centre, radius)
		if at.distance_to(centre) > radius - 18.0:
			return
		_draw_star(at + Vector2(0, 14), 5.5, INK_HALL)
		return


func _draw_star(at: Vector2, size_px: float, colour: Color) -> void:
	for index in 5:
		var tip := -PI * 0.5 + float(index) * TAU / 5.0
		var left := tip - TAU / 10.0
		var right := tip + TAU / 10.0
		var tri := PackedVector2Array()
		tri.append(at)
		tri.append(at + Vector2(cos(left), sin(left)) * size_px * 0.42)
		tri.append(at + Vector2(cos(tip), sin(tip)) * size_px)
		draw_colored_polygon(tri, colour)
		var tri2 := PackedVector2Array()
		tri2.append(at)
		tri2.append(at + Vector2(cos(tip), sin(tip)) * size_px)
		tri2.append(at + Vector2(cos(right), sin(right)) * size_px * 0.42)
		draw_colored_polygon(tri2, colour)


func _draw_player(centre: Vector2) -> void:
	var tip := centre + Vector2(0, -7)
	var left := centre + Vector2(-5, 6)
	var right := centre + Vector2(5, 6)
	var tri := PackedVector2Array()
	tri.append(tip)
	tri.append(right)
	tri.append(left)
	draw_colored_polygon(tri, PALETTE.highlight)
	draw_polyline(PackedVector2Array([tip, right, left, tip]), PALETTE.ink, 1.2, true)


func _heavier_label(a: Dictionary, b: Dictionary) -> bool:
	return float(a["w"]) > float(b["w"])


func _name_weight(kind: StringName, distance: float) -> float:
	var rank := 1.0
	if kind == PatchCity.CityPlace.KIND_TOWN_CENTER:
		rank = 8.0
	elif kind == PatchCity.CityPlace.KIND_LANDMARK:
		rank = 7.0
	elif kind == PatchCity.CityPlace.KIND_DISTRICT:
		rank = 6.0
	return rank * 80.0 - distance


func _label_blocked(at: Vector2, occupied: Array) -> bool:
	var box := Rect2(at - Vector2(36, 8), Vector2(72, 16))
	for other in occupied:
		var hit: Rect2 = other
		if hit.intersects(box):
			return true
	return false


func _lot_ink(lot: Dictionary) -> Color:
	if bool(lot.get("town_center", false)) or int(lot.get("typology", 0)) == 7:
		return INK_HALL
	if bool(lot.get("landmark", false)) or int(lot.get("typology", 0)) == 6:
		return INK_SPECIAL
	return INK_BUILDING


func _district_ring(item: Variant) -> PackedVector2Array:
	if item is Dictionary:
		return PackedVector2Array((item as Dictionary).get("uv", PackedVector2Array()))
	return PackedVector2Array(item)


func _district_id(item: Variant) -> int:
	if item is Dictionary:
		return int((item as Dictionary).get("id", -1))
	return -1


func _stroke_px(half: float, radius: float) -> float:
	return clampf(half / maxf(_view_m, 8.0) * radius * 2.0, 1.0, 7.5)


func _uv_to_screen(uv: Vector2, centre: Vector2, radius: float) -> Vector2:
	var delta := uv - _player_uv
	var right := Vector2(_heading.y, -_heading.x)
	var x := delta.dot(right)
	var y := delta.dot(_heading)
	var scale := (radius - RING) / maxf(_view_m, 8.0)
	return centre + Vector2(x, -y) * scale


func _path_to_screen(path: PackedVector2Array, centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var step := 1
	if path.size() > 80 and _view_m > 220.0:
		step = 2
	var index := 0
	while index < path.size():
		out.append(_uv_to_screen(path[index], centre, radius))
		index += step
	if path.size() >= 2 and out.size() >= 1 and out[out.size() - 1] != _uv_to_screen(path[path.size() - 1], centre, radius):
		out.append(_uv_to_screen(path[path.size() - 1], centre, radius))
	return out


func _stroke_path(
		path: PackedVector2Array,
		colour: Color,
		width: float,
		closed: bool,
		centre: Vector2,
		radius: float
	) -> void:
	var count := path.size()
	if count < 2:
		return
	var last := count if closed else count - 1
	for index in last:
		var a: Vector2 = path[index]
		var b: Vector2 = path[(index + 1) % count]
		_draw_clipped_line(a, b, centre, radius - RING, colour, width)


func _fill_clipped(
		poly: PackedVector2Array,
		clip: PackedVector2Array,
		colour: Color
	) -> void:
	if poly.size() < 3:
		return
	var parts: Array = Geometry2D.intersect_polygons(poly, clip)
	for part in parts:
		var ring: PackedVector2Array = part
		if ring.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(ring):
			continue
		draw_colored_polygon(ring, colour)


func _draw_clipped_line(
		a: Vector2,
		b: Vector2,
		centre: Vector2,
		radius: float,
		colour: Color,
		width: float
	) -> void:
	var chord := b - a
	if chord.length_squared() < 0.25:
		return
	var knots: Array = [0.0, 1.0]
	var f := a - centre
	var aa := chord.dot(chord)
	if aa >= 0.0001:
		var bb := 2.0 * f.dot(chord)
		var cc := f.dot(f) - radius * radius
		var disc := bb * bb - 4.0 * aa * cc
		if disc >= 0.0:
			var root := sqrt(disc)
			var t1 := (-bb - root) / (2.0 * aa)
			var t2 := (-bb + root) / (2.0 * aa)
			if t1 > 0.0 and t1 < 1.0:
				knots.append(t1)
			if t2 > 0.0 and t2 < 1.0:
				knots.append(t2)
	knots.sort()
	for index in knots.size() - 1:
		var t0: float = knots[index]
		var t1: float = knots[index + 1]
		if t1 - t0 < 0.0001:
			continue
		var mid := a.lerp(b, (t0 + t1) * 0.5)
		if mid.distance_squared_to(centre) > radius * radius:
			continue
		draw_line(a.lerp(b, t0), a.lerp(b, t1), colour, width, true)


func _circle_poly(centre: Vector2, radius: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	var steps := 32
	for index in steps:
		var ang := TAU * float(index) / float(steps)
		ring.append(centre + Vector2(cos(ang), sin(ang)) * radius)
	return ring
