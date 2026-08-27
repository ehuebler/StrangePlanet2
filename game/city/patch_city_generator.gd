class_name PatchCityGenerator
extends RefCounted

## Lays out one patch as a finished city: the race-loop road first, then
## districts seated inside and outside that road.

const CELL := 22.0
const EDGE_BUFFER := 95.0
const BORDER_CLEAR := 66.0
const TILE_CLEAR := 36.0
const MIN_TILE_SIDES := 3
const MIN_GROUP := 16
const ROAD_TILE_REACH := 70.0
const EXIT_GAP := 200.0
const EXIT_LAND_NEAR := 70.0
const EXIT_LAND_FAR := 180.0
const EXIT_LAND_WANT := 140.0
const SHORE_INSET := 80.0
const PARK_GRADE := 0.15
const CLIFF_GRADE := 0.32
const CREVASSE_DROP := 0.38
const CORE_GRADE := 0.08
const ROAD_GRADE := 0.08
const CORE_MIN_EDGE := 220.0
const TARGET_MIN := 500.0
const TARGET_MAX := 1500.0
## Fine-only height that is too jagged to seat a district. Hoodoos stand about
## 17 m over the bench and fade out of a 22 m sample; ordinary detail is ~2 m.
const SPIKE_RELIEF := 5.5

const KIND_PARK := 0
const KIND_BUFFER := 1
const KIND_PLAZA := 2
const KIND_CONNECTOR := 3
const KIND_INDUSTRIAL := 4
const KIND_RESIDENTIAL := 5
const KIND_CIVIC := 6
const KIND_CORE := 7

const RANK_LOOP := 0
const RANK_ARTERIAL := 1
const RANK_COLLECTOR := 2
const RANK_LOCAL := 3
const ARTERIAL_GRADE := 0.08
const COLLECTOR_GRADE := 0.10
const ARTERIAL_GAP := 800.0
const COLLECTOR_GAP := 300.0

const KIND_NAME: PackedStringArray = [
	"Park", "Buffer", "Plaza", "Pass", "Works", "Quarter", "Civic", "Downtown",
]

const KIND_COLOR: Array[Color] = [
	Color(0.27, 0.50, 0.30),
	Color(0.18, 0.38, 0.24),
	Color(0.52, 0.60, 0.36),
	Color(0.70, 0.56, 0.36),
	Color(0.40, 0.38, 0.42),
	Color(0.84, 0.70, 0.50),
	Color(0.60, 0.56, 0.70),
	Color(0.80, 0.40, 0.26),
]


class District:
	var id := -1
	var kind := KIND_PARK
	var name := ""
	var colour := Color.WHITE
	var centre := Vector3.UP
	var dirs := PackedVector3Array()
	var span := 0.0
	var grade := 0.0


class Street:
	var rank := RANK_LOCAL
	var dirs := PackedVector3Array()
	var terrace := false


class RoadExit:
	var road := Vector3.UP
	var land := Vector3.UP
	var district_id := -1
	var name := ""


class Plan:
	var patch_id := -1
	var patch_name := ""
	var road_name := ""
	var districts: Array[District] = []
	var loop := PackedVector3Array()
	var extension := PackedVector3Array()
	var nodes := PackedVector3Array()
	var cell_size := CELL
	var streets: Array[Street] = []
	var exits: Array[RoadExit] = []


var _shape: PlanetShape
var _partition: LandPartition
var _patch_id := -1
var _up := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.FORWARD
var _radius := 8000.0
var _width := 0
var _height := 0
var _origin := Vector2.ZERO
var _grid: PackedInt32Array = PackedInt32Array()
var _land: PackedByteArray = PackedByteArray()
var _count := 0
var _dir: PackedVector3Array = PackedVector3Array()
var _gx: PackedInt32Array = PackedInt32Array()
var _gy: PackedInt32Array = PackedInt32Array()
var _elev: PackedFloat32Array = PackedFloat32Array()
var _grade: PackedFloat32Array = PackedFloat32Array()
var _lap: PackedFloat32Array = PackedFloat32Array()
var _edge: PackedFloat32Array = PackedFloat32Array()
var _water: PackedByteArray = PackedByteArray()
var _saddle: PackedByteArray = PackedByteArray()
var _hazard: PackedByteArray = PackedByteArray()
var _kind: PackedInt32Array = PackedInt32Array()
var _district: PackedInt32Array = PackedInt32Array()
var _travel: PackedFloat32Array = PackedFloat32Array()
var _local_dirs: PackedVector3Array = PackedVector3Array()
var _local_owners: PackedInt32Array = PackedInt32Array()
var _loop_cells: Array[int] = []
var _road_rank: PackedInt32Array = PackedInt32Array()
var _loop_poly: PackedVector2Array = PackedVector2Array()
var _in_loop: PackedByteArray = PackedByteArray()
var _loop_gap: PackedFloat32Array = PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func generate(
		shape: PlanetShape,
		partition: LandPartition,
		patch_id: int
	) -> Plan:
	var plan := Plan.new()
	if shape == null or partition == null:
		return plan
	if patch_id < 0 or patch_id >= partition.patches.size():
		return plan
	_shape = shape
	_partition = partition
	_patch_id = patch_id
	var patch := partition.patches[patch_id]
	plan.patch_id = patch_id
	plan.patch_name = patch.name
	_radius = shape.radius
	_up = patch.direction.normalized()
	_east = _up.cross(Vector3.UP if absf(_up.y) < 0.9 else Vector3.RIGHT).normalized()
	_north = _up.cross(_east)
	if not _rasterize(patch):
		return plan
	_rng.seed = hash([patch.seed.x, patch.seed.y, patch.seed.z, patch_id])
	_analyze()
	_route_loop(plan)
	_mark_forced()
	_place_core()
	_density_from_core()
	_place_remaining()
	_seams_and_buffers()
	_fill_along_road()
	_trim_district_tiles()
	_fill_along_road()
	_absorb_tiny_districts()
	_merge_districts()
	_absorb_tiny_districts()
	_name_districts(plan)
	_place_exits(plan)
	return plan


func _rasterize(patch: LandPartition.Patch) -> bool:
	var owned := _partition.directions_of(_patch_id)
	if owned.is_empty():
		return false
	_collect_local(patch)
	var min_u := 1.0e9
	var min_v := 1.0e9
	var max_u := -1.0e9
	var max_v := -1.0e9
	for direction in owned:
		var uv := _to_uv(direction)
		min_u = minf(min_u, uv.x)
		max_u = maxf(max_u, uv.x)
		min_v = minf(min_v, uv.y)
		max_v = maxf(max_v, uv.y)
	var pad := CELL * 1.5
	_origin = Vector2(min_u - pad, min_v - pad)
	_width = maxi(3, int(ceili((max_u - min_u + pad * 2.0) / CELL)))
	_height = maxi(3, int(ceili((max_v - min_v + pad * 2.0) / CELL)))
	_grid.resize(_width * _height)
	_grid.fill(-1)
	_land.resize(_width * _height)
	_land.fill(0)
	_count = 0
	_dir = PackedVector3Array()
	_gx = PackedInt32Array()
	_gy = PackedInt32Array()
	for y in _height:
		for x in _width:
			var uv := _origin + Vector2((float(x) + 0.5) * CELL, (float(y) + 0.5) * CELL)
			var direction := _from_uv(uv)
			if not _inside(direction):
				continue
			if _shape.elevation(direction, CELL) < 0.0:
				continue
			var normal := _shape.normal_at(direction, CELL)
			var tilt := acos(clampf(normal.dot(direction), -1.0, 1.0))
			if tan(tilt) > CLIFF_GRADE:
				continue
			if _tile_has_spikes(direction):
				continue
			var index := _count
			_grid[y * _width + x] = index
			_land[y * _width + x] = 1
			_dir.append(direction)
			_gx.append(x)
			_gy.append(y)
			_count += 1
	if _count < 6:
		return false
	_elev.resize(_count)
	_grade.resize(_count)
	_lap.resize(_count)
	_edge.resize(_count)
	_water.resize(_count)
	_saddle.resize(_count)
	_hazard.resize(_count)
	_kind.resize(_count)
	_district.resize(_count)
	_travel.resize(_count)
	_kind.fill(-1)
	_district.fill(-1)
	_travel.fill(1.0e9)
	return true


func _collect_local(patch: LandPartition.Patch) -> void:
	_local_dirs = PackedVector3Array()
	_local_owners = PackedInt32Array()
	var reach := (patch.span * 0.5 + 500.0) / maxf(_radius, 1.0)
	var min_dot := cos(clampf(reach, 0.02, 1.2))
	var centre := patch.direction
	for index in _partition.vertices.size():
		if _partition.vertices[index].dot(centre) < min_dot:
			continue
		_local_dirs.append(_partition.vertices[index])
		_local_owners.append(_partition.owners[index])


func _tile_has_spikes(direction: Vector3) -> bool:
	var up := direction.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := up.cross(east)
	var floor_h := _shape.elevation(up, CELL)
	var peak := floor_h
	var half := CELL * 0.42
	var offsets := PackedVector2Array()
	offsets.append(Vector2.ZERO)
	offsets.append(Vector2(-half, 0.0))
	offsets.append(Vector2(half, 0.0))
	offsets.append(Vector2(0.0, -half))
	offsets.append(Vector2(0.0, half))
	offsets.append(Vector2(-half, -half))
	offsets.append(Vector2(half, -half))
	offsets.append(Vector2(half, half))
	offsets.append(Vector2(-half, half))
	for offset in offsets:
		var at := (up + (east * offset.x + north * offset.y) / _radius).normalized()
		peak = maxf(peak, _shape.elevation(at, 0.0))
	return peak - floor_h > SPIKE_RELIEF


func _inside(direction: Vector3) -> bool:
	var best := -1
	var best_dot := -2.0
	for index in _local_dirs.size():
		var toward := direction.dot(_local_dirs[index])
		if toward > best_dot:
			best_dot = toward
			best = index
	return best >= 0 and _local_owners[best] == _patch_id


func _analyze() -> void:
	var elev_at: Dictionary = {}
	for index in _count:
		var direction := _dir[index]
		_elev[index] = _shape.elevation(direction, CELL)
		var normal := _shape.normal_at(direction, CELL)
		var tilt := acos(clampf(normal.dot(direction), -1.0, 1.0))
		_grade[index] = tan(tilt)
		var parts := _shape.sample(direction)
		var river := float(parts.get("river", 0.0))
		var lake := float(parts.get("lake", 0.0))
		_water[index] = 1 if (
			_elev[index] < 8.0 or river > 0.25 or lake > 0.45
		) else 0
		elev_at[Vector2i(_gx[index], _gy[index])] = _elev[index]
	for index in _count:
		var x := _gx[index]
		var y := _gy[index]
		var e := _neighbor_elev(elev_at, x + 1, y, _elev[index])
		var w := _neighbor_elev(elev_at, x - 1, y, _elev[index])
		var n := _neighbor_elev(elev_at, x, y - 1, _elev[index])
		var s := _neighbor_elev(elev_at, x, y + 1, _elev[index])
		_lap[index] = e + w + n + s - 4.0 * _elev[index]
		var east_west := e > _elev[index] and w > _elev[index] \
				and n < _elev[index] and s < _elev[index]
		var north_south := n > _elev[index] and s > _elev[index] \
				and e < _elev[index] and w < _elev[index]
		_saddle[index] = 1 if east_west or north_south else 0
		var drop := maxf(absf(e - w), absf(n - s)) / CELL
		var crease := absf(_lap[index]) / CELL
		_hazard[index] = 1 if (
			_grade[index] > CLIFF_GRADE
			or drop > CREVASSE_DROP
			or crease > 0.55
		) else 0
	_carve_hazards()
	_measure_edge()


func _neighbor_elev(elev_at: Dictionary, x: int, y: int, fallback: float) -> float:
	var key := Vector2i(x, y)
	if elev_at.has(key):
		return float(elev_at[key])
	return fallback


func _measure_edge() -> void:
	var queue: Array[int] = []
	for index in _count:
		if _is_border_cell(index):
			_edge[index] = 0.0
			queue.append(index)
		else:
			_edge[index] = 1.0e9
	var cursor := 0
	while cursor < queue.size():
		var at: int = queue[cursor]
		cursor += 1
		for other in _neighbors(at):
			var next := _edge[at] + CELL
			if next < _edge[other]:
				_edge[other] = next
				queue.append(other)


func _is_border_cell(index: int) -> bool:
	var x := _gx[index]
	var y := _gy[index]
	var steps: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	for step in steps:
		var nx := x + step.x
		var ny := y + step.y
		if nx < 0 or ny < 0 or nx >= _width or ny >= _height:
			return true
		if _land[ny * _width + nx] == 0:
			return true
	return false


func _carve_hazards() -> void:
	for index in _count:
		if _hazard[index] == 0:
			continue
		_grid[_gy[index] * _width + _gx[index]] = -1
		_kind[index] = -1


func _mark_forced() -> void:
	for index in _count:
		if _hazard[index] != 0:
			continue
		var corridor := _lap[index] > 4.0 and _grade[index] < 0.10
		if _grade[index] > PARK_GRADE:
			_kind[index] = KIND_PARK
			continue
		if _water[index] != 0 or _elev[index] < 14.0 and _edge[index] < CELL * 2.5:
			_kind[index] = KIND_BUFFER
			continue
		if _edge[index] < 50.0 and not corridor:
			_kind[index] = KIND_BUFFER


func _place_core() -> void:
	var seed := -1
	var best := -1.0e9
	var mean_elev := 0.0
	for index in _count:
		mean_elev += _elev[index]
	mean_elev /= float(maxi(_count, 1))
	for index in _count:
		if _kind[index] >= 0 or _hazard[index] != 0:
			continue
		if _in_loop[index] == 0:
			continue
		if _grade[index] > CORE_GRADE:
			continue
		if _loop_gap[index] < 70.0:
			continue
		var valley := clampf((mean_elev - _elev[index]) / 40.0, -1.0, 1.5)
		var score := -_grade[index] * 18.0 + valley + _loop_gap[index] / 250.0
		if score > best:
			best = score
			seed = index
	if seed < 0:
		for index in _count:
			if _kind[index] >= 0 or _hazard[index] != 0:
				continue
			if _in_loop[index] == 0:
				continue
			var score := -_grade[index] * 10.0 + _loop_gap[index] / 200.0
			if score > best:
				best = score
				seed = index
	if seed < 0:
		return
	var free_inside := 0
	for index in _count:
		if _kind[index] < 0 and _hazard[index] == 0 and _in_loop[index] != 0:
			free_inside += 1
	var cap := clampi(int(round(float(free_inside) * 0.16)), 18, 90)
	var queue: Array[int] = [seed]
	_kind[seed] = KIND_CORE
	var taken := 1
	var cursor := 0
	while cursor < queue.size() and taken < cap:
		var at: int = queue[cursor]
		cursor += 1
		var next_n: Array = Array(_neighbors(at))
		next_n.sort_custom(func(a: int, b: int) -> bool:
			return _grade[a] < _grade[b])
		for other in next_n:
			if taken >= cap:
				break
			if _kind[other] >= 0 or _hazard[other] != 0:
				continue
			if _in_loop[other] == 0:
				continue
			if _loop_gap[other] < 55.0:
				continue
			if _grade[other] > CORE_GRADE + 0.03:
				continue
			_kind[other] = KIND_CORE
			queue.append(other)
			taken += 1
	_place_central_park(seed)


func _place_central_park(core_seed: int) -> void:
	var best := -1
	var best_score := -1.0e9
	for index in _count:
		if _kind[index] == KIND_CORE:
			continue
		var near_core := false
		for other in _neighbors(index):
			if _kind[other] == KIND_CORE:
				near_core = true
				break
		if not near_core:
			continue
		var score := _lap[index] + (1.0 if _kind[index] == KIND_PARK else 0.0) \
				- _grade[index]
		if score > best_score:
			best_score = score
			best = index
	if best < 0:
		return
	var want := mini(8, maxi(3, int(round(float(_count) / 400.0))))
	var queue: Array[int] = [best]
	var taken := 0
	var cursor := 0
	while cursor < queue.size() and taken < want:
		var at: int = queue[cursor]
		cursor += 1
		if _kind[at] == KIND_CORE:
			continue
		if _in_loop.size() == _count and _in_loop[at] == 0:
			continue
		_kind[at] = KIND_PARK
		taken += 1
		for other in _neighbors(at):
			if _kind[other] == KIND_CORE:
				continue
			if _in_loop.size() == _count and _in_loop[other] == 0:
				continue
			queue.append(other)
	_core_seed = core_seed


var _core_seed := 0


func _density_from_core() -> void:
	var queue: Array[int] = []
	for index in _count:
		if _kind[index] == KIND_CORE:
			_travel[index] = 0.0
			queue.append(index)
	var cursor := 0
	while cursor < queue.size():
		var at: int = queue[cursor]
		cursor += 1
		for other in _neighbors(at):
			var step := CELL * (1.0 + 7.0 * _grade[other])
			if _kind[other] == KIND_PARK:
				step *= 1.8
			var next := _travel[at] + step
			if next < _travel[other]:
				_travel[other] = next
				queue.append(other)


func _place_remaining() -> void:
	var core_elev := _elev[_core_seed] if _count > 0 else 0.0
	for index in _count:
		if _kind[index] >= 0 or _hazard[index] != 0:
			continue
		if _saddle[index] != 0:
			_kind[index] = KIND_CONNECTOR
			continue
		if _lap[index] > 6.0 and _grade[index] < PARK_GRADE:
			_kind[index] = KIND_PARK
			continue
		var inside := _in_loop[index] != 0
		if not inside:
			var downhill := _elev[index] < core_elev - 4.0
			if downhill and _grade[index] < 0.10:
				_kind[index] = KIND_INDUSTRIAL
			else:
				_kind[index] = KIND_BUFFER
			continue
		if _loop_gap[index] < 40.0:
			_kind[index] = KIND_PLAZA
			continue
		var high := _elev[index] > core_elev + 10.0
		var moderate := _grade[index] < 0.12
		if high and moderate and _loop_gap[index] > 80.0:
			_kind[index] = KIND_CIVIC
			continue
		_kind[index] = KIND_RESIDENTIAL


func _seams_and_buffers() -> void:
	var pending: PackedInt32Array = PackedInt32Array()
	for index in _count:
		if _kind[index] != KIND_INDUSTRIAL:
			continue
		for other in _neighbors(index):
			if _kind[other] == KIND_RESIDENTIAL or _kind[other] == KIND_CORE:
				pending.append(index)
				pending.append(other)
	for index in pending:
		if _kind[index] != KIND_CORE:
			_kind[index] = KIND_BUFFER
	for index in _count:
		if _kind[index] < 0:
			continue
		var here := _density_of(_kind[index])
		for other in _neighbors(index):
			if _kind[other] < 0:
				continue
			if absi(here - _density_of(_kind[other])) > 1:
				if _kind[index] != KIND_CORE and _kind[index] != KIND_PARK:
					_kind[index] = KIND_PLAZA


func _density_of(kind: int) -> int:
	match kind:
		KIND_CORE:
			return 4
		KIND_CIVIC, KIND_RESIDENTIAL:
			return 3
		KIND_CONNECTOR, KIND_INDUSTRIAL:
			return 2
		KIND_PLAZA, KIND_BUFFER:
			return 1
	return 0


func _trim_district_tiles() -> void:
	_clear_border_tiles()
	var drop := PackedInt32Array()
	for index in _count:
		if _kind[index] < 0:
			continue
		if _occupied_sides(index) < MIN_TILE_SIDES:
			drop.append(index)
	for index in drop:
		_kind[index] = -1
		_district[index] = -1


func _clear_border_tiles() -> void:
	var half := CELL * 0.40 + TILE_CLEAR
	for index in _count:
		if _kind[index] < 0:
			continue
		if _tile_outside_patch(index, half):
			_kind[index] = -1
			_district[index] = -1
			continue
		var near_road := _loop_gap.size() == _count and _loop_gap[index] < ROAD_TILE_REACH
		if _edge[index] < BORDER_CLEAR and not near_road:
			_kind[index] = -1
			_district[index] = -1


func _fill_along_road() -> void:
	if _loop_gap.size() != _count:
		return
	var half := CELL * 0.40 + TILE_CLEAR
	for index in _count:
		if _kind[index] >= 0 or _hazard[index] != 0:
			continue
		if _loop_gap[index] > ROAD_TILE_REACH:
			continue
		if _grade[index] > CLIFF_GRADE:
			continue
		if _water[index] != 0:
			continue
		if _tile_outside_patch(index, half):
			continue
		if _loop_gap[index] < 40.0:
			_kind[index] = KIND_PLAZA
		elif _in_loop[index] != 0:
			_kind[index] = KIND_RESIDENTIAL
		else:
			_kind[index] = KIND_BUFFER


func _tile_outside_patch(index: int, half: float) -> bool:
	var uv := _to_uv(_dir[index])
	if not _in_patch(_from_uv(uv)):
		return true
	var offsets := PackedVector2Array()
	offsets.append(Vector2(-half, -half))
	offsets.append(Vector2(half, -half))
	offsets.append(Vector2(half, half))
	offsets.append(Vector2(-half, half))
	offsets.append(Vector2(-half, 0.0))
	offsets.append(Vector2(half, 0.0))
	offsets.append(Vector2(0.0, -half))
	offsets.append(Vector2(0.0, half))
	for sample in offsets:
		if not _in_patch(_from_uv(uv + sample)):
			return true
	return false


func _occupied_sides(index: int) -> int:
	var cardinal := 0
	for other in _neighbors(index):
		if _kind[other] >= 0:
			cardinal += 1
	if cardinal >= MIN_TILE_SIDES:
		return cardinal
	# A filled-block corner only has two cardinal neighbours. Count the
	# inner diagonal as the third side so squares do not peel to nothing.
	if cardinal == 2:
		var around := 0
		for other in _neighbors8(index):
			if _kind[other] >= 0:
				around += 1
		if around >= MIN_TILE_SIDES:
			return MIN_TILE_SIDES
	return cardinal


func _absorb_tiny_districts() -> void:
	for _sweep in 8:
		var groups: Array[PackedInt32Array] = []
		var kinds := _flood_kind_groups(groups)
		var changed := false
		for index in groups.size():
			if groups[index].size() >= MIN_GROUP:
				continue
			changed = true
			var mate := _best_absorb(index, groups)
			if mate >= 0:
				_reassign(groups[index], kinds[mate])
			else:
				_reassign(groups[index], -1)
		if not changed:
			break
	var leftover: Array[PackedInt32Array] = []
	_flood_kind_groups(leftover)
	for index in leftover.size():
		if leftover[index].size() < MIN_GROUP:
			_reassign(leftover[index], -1)
	var refresh: Array[PackedInt32Array] = []
	_flood_kind_groups(refresh)


func _flood_kind_groups(groups: Array[PackedInt32Array]) -> PackedInt32Array:
	var kinds := PackedInt32Array()
	_district.fill(-1)
	var next_id := 0
	for start in _count:
		if _district[start] >= 0 or _kind[start] < 0:
			continue
		var cells := PackedInt32Array()
		var queue: Array[int] = [start]
		_district[start] = next_id
		var cursor := 0
		while cursor < queue.size():
			var at: int = queue[cursor]
			cursor += 1
			cells.append(at)
			for other in _neighbors(at):
				if _district[other] >= 0 or _kind[other] != _kind[start]:
					continue
				_district[other] = next_id
				queue.append(other)
		groups.append(cells)
		kinds.append(_kind[start])
		next_id += 1
	return kinds


func _best_absorb(index: int, groups: Array[PackedInt32Array]) -> int:
	var votes: Dictionary = {}
	for cell in groups[index]:
		for other in _neighbors(cell):
			var oid := _district[other]
			if oid < 0 or oid == index:
				continue
			votes[oid] = int(votes.get(oid, 0)) + 1
	var best := -1
	var best_score := -1
	for oid in votes:
		var n: int = int(votes[oid])
		var size := groups[int(oid)].size()
		var score := n * 1000 + size
		if score > best_score:
			best_score = score
			best = int(oid)
	return best


func _merge_districts() -> void:
	_district.fill(-1)
	var next_id := 0
	var groups: Array[PackedInt32Array] = []
	var kinds: PackedInt32Array = PackedInt32Array()
	for start in _count:
		if _district[start] >= 0 or _kind[start] < 0:
			continue
		var cells := PackedInt32Array()
		var queue: Array[int] = [start]
		_district[start] = next_id
		var cursor := 0
		while cursor < queue.size():
			var at: int = queue[cursor]
			cursor += 1
			cells.append(at)
			for other in _neighbors(at):
				if _district[other] >= 0 or _kind[other] != _kind[start]:
					continue
				_district[other] = next_id
				queue.append(other)
		groups.append(cells)
		kinds.append(_kind[start])
		next_id += 1
	for index in groups.size():
		var span := _span_of(groups[index])
		if span >= TARGET_MIN or kinds[index] == KIND_CORE:
			continue
		if groups[index].size() < MIN_GROUP:
			continue
		if span < 220.0 and kinds[index] != KIND_PARK:
			_reassign(groups[index], KIND_PARK)
	_district.fill(-1)
	next_id = 0
	groups.clear()
	kinds = PackedInt32Array()
	for start in _count:
		if _district[start] >= 0 or _kind[start] < 0:
			continue
		var cells := PackedInt32Array()
		var queue: Array[int] = [start]
		_district[start] = next_id
		var cursor := 0
		while cursor < queue.size():
			var at: int = queue[cursor]
			cursor += 1
			cells.append(at)
			for other in _neighbors(at):
				if _district[other] >= 0 or _kind[other] != _kind[start]:
					continue
				_district[other] = next_id
				queue.append(other)
		groups.append(cells)
		kinds.append(_kind[start])
		next_id += 1
	var absorbed: Dictionary = {}
	for index in groups.size():
		if absorbed.has(index):
			continue
		if kinds[index] == KIND_CORE:
			continue
		if _span_of(groups[index]) >= TARGET_MIN:
			continue
		var mate := _best_merge(index, groups, kinds)
		if mate < 0:
			continue
		for cell in groups[index]:
			_kind[cell] = kinds[mate]
			_district[cell] = mate
		absorbed[index] = true
	_district.fill(-1)
	next_id = 0
	for start in _count:
		if _district[start] >= 0 or _kind[start] < 0:
			continue
		var queue: Array[int] = [start]
		_district[start] = next_id
		var cursor := 0
		while cursor < queue.size():
			var at: int = queue[cursor]
			cursor += 1
			for other in _neighbors(at):
				if _district[other] >= 0 or _kind[other] != _kind[start]:
					continue
				_district[other] = next_id
				queue.append(other)
		next_id += 1


func _reassign(cells: PackedInt32Array, kind: int) -> void:
	for cell in cells:
		_kind[cell] = kind
		if kind < 0:
			_district[cell] = -1


func _best_merge(
		index: int,
		groups: Array[PackedInt32Array],
		kinds: PackedInt32Array
	) -> int:
	var votes: Dictionary = {}
	for cell in groups[index]:
		for other in _neighbors(cell):
			var oid := _district[other]
			if oid < 0 or oid == index:
				continue
			if kinds[oid] == KIND_CORE and kinds[index] != KIND_PARK:
				continue
			votes[oid] = int(votes.get(oid, 0)) + 1
	var best := -1
	var best_n := 0
	for oid in votes:
		var n: int = int(votes[oid])
		if n > best_n:
			best_n = n
			best = int(oid)
	return best


func _span_of(cells: PackedInt32Array) -> float:
	if cells.is_empty():
		return 0.0
	var acc := Vector3.ZERO
	for cell in cells:
		acc += _dir[cell]
	var centre := acc.normalized() if acc.length_squared() > 0.001 else _up
	var farthest := 0.0
	for cell in cells:
		farthest = maxf(farthest, centre.angle_to(_dir[cell]))
	return farthest * _radius * 2.0


func _name_districts(plan: Plan) -> void:
	var n := 0
	for index in _count:
		n = maxi(n, _district[index] + 1)
	var named := 0
	for id in n:
		var cells := PackedInt32Array()
		var acc := Vector3.ZERO
		for index in _count:
			if _district[index] != id:
				continue
			cells.append(index)
			acc += _dir[index]
		if cells.is_empty() or cells.size() < MIN_GROUP:
			continue
		var district := District.new()
		district.id = plan.districts.size()
		district.kind = -1
		district.colour = Color.WHITE
		district.dirs.resize(cells.size())
		for cell_i in cells.size():
			district.dirs[cell_i] = _dir[cells[cell_i]]
		district.centre = acc.normalized() if acc.length_squared() > 0.001 else _up
		district.span = _span_of(cells)
		var grade_sum := 0.0
		for cell in cells:
			grade_sum += _grade[cell]
		district.grade = grade_sum / float(cells.size())
		named += 1
		district.name = "District" if named == 1 else "District %d" % named
		plan.districts.append(district)
		for cell in cells:
			_district[cell] = district.id


func _place_exits(plan: Plan) -> void:
	if plan.loop.size() < 3 or plan.districts.is_empty():
		return
	var taken := PackedVector3Array()
	for district in plan.districts:
		if district.grade > PARK_GRADE:
			continue
		var slots := 1 + int(floor(district.span / 700.0))
		var picks := _exit_lands(district, slots)
		for land in picks:
			var road := _nearest_loop_point(plan, land)
			if road == Vector3.ZERO:
				continue
			if land.angle_to(road) * _radius < EXIT_LAND_NEAR:
				land = _push_landing(district, road)
			if land == Vector3.ZERO:
				continue
			if land.angle_to(road) * _radius < EXIT_LAND_NEAR:
				continue
			if _exit_blocked(taken, road):
				continue
			var ramp := RoadExit.new()
			ramp.road = road
			ramp.land = land
			ramp.district_id = district.id
			plan.exits.append(ramp)
			taken.append(road)


func _exit_lands(district: District, slots: int) -> PackedVector3Array:
	var picks := PackedVector3Array()
	if slots <= 0 or district.dirs.is_empty():
		return picks
	var ranked: Array[int] = []
	for index in _count:
		if _district[index] != district.id or _hazard[index] != 0:
			continue
		if _loop_gap.size() != _count:
			continue
		ranked.append(index)
	ranked.sort_custom(func(a: int, b: int) -> bool:
		return _exit_land_score(a) > _exit_land_score(b))
	for index in ranked:
		if picks.size() >= slots:
			break
		if _loop_gap[index] < EXIT_LAND_NEAR or _loop_gap[index] > EXIT_LAND_FAR * 1.35:
			continue
		var land: Vector3 = _dir[index]
		var crowded := false
		for other in picks:
			if land.angle_to(other) * _radius < EXIT_GAP:
				crowded = true
				break
		if crowded:
			continue
		picks.append(land)
	return picks


func _exit_land_score(index: int) -> float:
	var gap := _loop_gap[index]
	var band := 1.0 - clampf(absf(gap - EXIT_LAND_WANT) / 55.0, 0.0, 1.0)
	if gap < EXIT_LAND_NEAR:
		band *= 0.05
	return band * 8.0 - _grade[index] * 12.0 + _edge[index] / 400.0


func _push_landing(district: District, road: Vector3) -> Vector3:
	var road_uv := _to_uv(road)
	var aim := _to_uv(district.centre) - road_uv
	if aim.length_squared() < 1.0:
		aim = _to_uv(district.centre)
	aim = aim.normalized()
	var best := Vector3.ZERO
	var best_gap := 0.0
	for direction in district.dirs:
		var gap := direction.angle_to(road) * _radius
		if gap < EXIT_LAND_NEAR or gap > EXIT_LAND_FAR * 1.4:
			continue
		if gap > best_gap:
			best_gap = gap
			best = direction
	if best != Vector3.ZERO:
		return best
	var candidate := _from_uv(road_uv + aim * EXIT_LAND_WANT)
	if _loop_ok(candidate):
		return candidate
	return Vector3.ZERO


func _nearest_loop_point(plan: Plan, land: Vector3) -> Vector3:
	var n := plan.loop.size()
	if n < 3:
		return Vector3.ZERO
	var nearest := 0
	var nearest_dot := -2.0
	for index in n:
		var toward := plan.loop[index].dot(land)
		if toward > nearest_dot:
			nearest_dot = toward
			nearest = index
	var best := nearest
	var best_score := -1.0e9
	var window := mini(n / 2, 14)
	for step in range(-window, window + 1):
		var index := (nearest + step + n * 8) % n
		var road: Vector3 = plan.loop[index]
		var prev: Vector3 = plan.loop[(index - 1 + n) % n]
		var next: Vector3 = plan.loop[(index + 1) % n]
		var up := road.normalized()
		var tan := next - prev
		tan -= up * tan.dot(up)
		if tan.length_squared() < 0.0001:
			continue
		tan = tan.normalized()
		var to_land := land - road
		to_land -= up * to_land.dot(up)
		var along := absf(to_land.dot(tan))
		var gap := road.angle_to(land) * _radius
		var score := -gap + along * 0.4
		if score > best_score:
			best_score = score
			best = index
	return plan.loop[best]


func _exit_blocked(taken: PackedVector3Array, road: Vector3) -> bool:
	for other in taken:
		if road.angle_to(other) * _radius < EXIT_GAP:
			return true
	return false


func _route_loop(plan: Plan) -> void:
	if _count == 0:
		return
	var origin := Vector2.ZERO
	var count := 36
	var hull: PackedFloat32Array = PackedFloat32Array()
	hull.resize(count)
	for step in count:
		var angle := TAU * float(step) / float(count)
		hull[step] = _patch_hull_radius(origin, Vector2(cos(angle), sin(angle)))
	var flower := _rng.randf() < 0.55
	var petals := _rng.randi_range(3, 6)
	var phase := _rng.randf() * TAU
	var valley := _rng.randf_range(0.48, 0.64)
	var wobble := _rng.randf_range(0.03, 0.08)
	var wobble_phase := _rng.randf() * TAU
	var margin := _rng.randf_range(70.0, 110.0)
	var radii: PackedFloat32Array = PackedFloat32Array()
	radii.resize(count)
	for step in count:
		var angle := TAU * float(step) / float(count)
		var cap: float = hull[step]
		var scale := 0.92
		if flower:
			var petal := 0.5 + 0.5 * cos(float(petals) * angle + phase)
			scale = valley + (0.97 - valley) * petal * petal
		else:
			scale = 0.91 + wobble * cos(2.0 * angle + wobble_phase)
		var radius := cap * clampf(scale, 0.42, 0.98) - margin * 0.25
		radii[step] = clampf(radius, 90.0, maxf(cap - 55.0, 90.0))
	_smooth_closed_radii(radii, 1)
	var controls: PackedVector2Array = PackedVector2Array()
	controls.resize(count)
	for step in count:
		var angle := TAU * float(step) / float(count)
		var aim := Vector2(cos(angle), sin(angle))
		var uv := _keep_inside_patch(origin, aim, radii[step])
		controls[step] = uv
		plan.nodes.append(_from_uv(uv))
	_loop_poly = _spline_closed(controls, 14.0)
	for index in _loop_poly.size():
		var uv: Vector2 = _loop_poly[index]
		if _loop_ok(_from_uv(uv)):
			continue
		var aim := uv - origin
		_loop_poly[index] = _keep_inside_patch(origin, aim, aim.length())
	plan.loop = PackedVector3Array()
	_loop_cells.clear()
	for uv in _loop_poly:
		var direction := _from_uv(uv)
		if not _loop_ok(direction):
			var aim := uv - origin
			direction = _from_uv(_keep_inside_patch(origin, aim, aim.length()))
		if not _loop_ok(direction):
			continue
		plan.loop.append(direction)
		var snapped := _closest_open(direction)
		if snapped >= 0:
			_loop_cells.append(snapped)
	if plan.loop.size() >= 3 and plan.loop[0].dot(plan.loop[plan.loop.size() - 1]) < 0.999:
		plan.loop.append(plan.loop[0])
	_measure_loop_fields()
	_mark_extension_from_dirs(plan)


func _measure_loop_fields() -> void:
	_in_loop.resize(_count)
	_loop_gap.resize(_count)
	if _loop_poly.size() < 3:
		_in_loop.fill(1)
		_loop_gap.fill(200.0)
		return
	for index in _count:
		var uv := _to_uv(_dir[index])
		_in_loop[index] = 1 if _point_in_poly(uv, _loop_poly) else 0
		_loop_gap[index] = _dist_to_poly(uv, _loop_poly)


func _point_in_poly(point: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var count := poly.size()
	var prev := count - 1
	for index in count:
		var a := poly[index]
		var b := poly[prev]
		if (a.y > point.y) != (b.y > point.y):
			var dy := b.y - a.y
			if absf(dy) > 0.0001:
				var at := (b.x - a.x) * (point.y - a.y) / dy + a.x
				if point.x < at:
					inside = not inside
		prev = index
	return inside


func _dist_to_poly(point: Vector2, poly: PackedVector2Array) -> float:
	var best := 1.0e9
	var count := poly.size()
	for index in count:
		var a := poly[index]
		var b := poly[(index + 1) % count]
		best = minf(best, _dist_to_segment(point, a, b))
	return best


func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var span := ab.length_squared()
	if span < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / span, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _loop_frame() -> Dictionary:
	var cells := PackedInt32Array()
	for index in _count:
		if _hazard[index] == 0:
			cells.append(index)
	if cells.is_empty():
		return {"along": Vector2.RIGHT, "across": Vector2.UP}
	return _district_axes(cells, 0.0)


func _patch_hull_radius(origin: Vector2, aim: Vector2) -> float:
	if aim.length_squared() < 0.0001:
		return 180.0
	aim = aim.normalized()
	var last_good := 80.0
	var t := 20.0
	var hit_water := false
	while t < 2800.0:
		var direction := _from_uv(origin + aim * t)
		if not _in_patch(direction):
			break
		if _wet(direction):
			hit_water = true
			break
		last_good = t
		t += CELL
	if hit_water:
		last_good -= SHORE_INSET
	return maxf(last_good, 90.0)


func _keep_inside_patch(origin: Vector2, aim: Vector2, radius: float) -> Vector2:
	if aim.length_squared() < 0.0001:
		return origin
	aim = aim.normalized()
	var lo := 40.0
	var hi := maxf(radius, 40.0)
	if _loop_ok(_from_uv(origin + aim * hi)):
		if _wet(_from_uv(origin + aim * (hi + CELL))):
			hi = maxf(hi - SHORE_INSET, 40.0)
		return origin + aim * hi
	for _step in 10:
		var mid := (lo + hi) * 0.5
		if _loop_ok(_from_uv(origin + aim * mid)):
			lo = mid
		else:
			hi = mid
	if _wet(_from_uv(origin + aim * (lo + CELL))):
		lo = maxf(lo - SHORE_INSET, 40.0)
	return origin + aim * lo


func _in_patch(direction: Vector3) -> bool:
	return _partition != null and _partition.owner_at(direction) == _patch_id


func _wet(direction: Vector3) -> bool:
	return _shape == null or _shape.elevation(direction, CELL) < 0.0


func _loop_ok(direction: Vector3) -> bool:
	return _in_patch(direction) and not _wet(direction)


func _smooth_closed_radii(radii: PackedFloat32Array, passes: int) -> void:
	var count := radii.size()
	if count < 3:
		return
	for _pass in passes:
		var next := PackedFloat32Array()
		next.resize(count)
		for index in count:
			var prev: float = radii[(index + count - 1) % count]
			var at: float = radii[index]
			var after: float = radii[(index + 1) % count]
			next[index] = prev * 0.2 + at * 0.6 + after * 0.2
		for index in count:
			radii[index] = next[index]


func _spline_closed(controls: PackedVector2Array, step_m: float) -> PackedVector2Array:
	var count := controls.size()
	var out := PackedVector2Array()
	if count < 3:
		return out
	for index in count:
		var p0 := controls[(index + count - 1) % count]
		var p1 := controls[index]
		var p2 := controls[(index + 1) % count]
		var p3 := controls[(index + 2) % count]
		var chord := p1.distance_to(p2)
		var pieces := maxi(3, int(ceili(chord / maxf(step_m, 4.0))))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			out.append(_catmull(p0, p1, p2, p3, t))
	return out


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _closest_open(direction: Vector3) -> int:
	var best := -1
	var best_dot := -2.0
	for index in _count:
		if _hazard[index] != 0:
			continue
		var toward := direction.dot(_dir[index])
		if toward > best_dot:
			best_dot = toward
			best = index
	return best


func _densify_cells(cells: Array) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	if cells.size() < 2:
		return dirs
	for index in cells.size() - 1:
		var a := _dir[int(cells[index])]
		var b := _dir[int(cells[index + 1])]
		var arc := a.angle_to(b) * _radius
		var pieces := maxi(1, int(ceili(arc / 16.0)))
		for piece in pieces:
			dirs.append(a.slerp(b, float(piece) / float(pieces)))
	dirs.append(_dir[int(cells[cells.size() - 1])])
	return dirs


func _geometric_ring(hub: Vector3, dist_m: float, count: int) -> PackedVector3Array:
	var origin := _to_uv(hub)
	var samples := PackedVector3Array()
	for step in count:
		var angle := TAU * float(step) / float(count)
		var uv := origin + Vector2(cos(angle), sin(angle)) * dist_m
		var direction := _from_uv(uv)
		if not _inside(direction):
			var cell := _closest_open(direction)
			if cell < 0:
				continue
			direction = _dir[cell]
		samples.append(direction)
	if samples.size() < 3:
		return PackedVector3Array()
	samples.append(samples[0])
	var dirs := PackedVector3Array()
	for index in samples.size() - 1:
		var a := samples[index]
		var b := samples[index + 1]
		var arc := a.angle_to(b) * _radius
		var pieces := maxi(1, int(ceili(arc / 16.0)))
		for piece in pieces:
			dirs.append(a.slerp(b, float(piece) / float(pieces)))
	dirs.append(samples[samples.size() - 1])
	return dirs


func _mark_extension_from_dirs(plan: Plan) -> void:
	if plan.loop.size() < 2:
		return
	var best := 0
	var best_edge := 1.0e9
	for index in plan.loop.size():
		var cell := _closest_open(plan.loop[index])
		if cell < 0:
			continue
		if _edge[cell] < best_edge:
			best_edge = _edge[cell]
			best = index
	plan.extension.append(plan.loop[best])
	var outward := (plan.loop[best] - _up).normalized()
	var stub := (plan.loop[best] + outward * (CELL / _radius)).normalized()
	if _loop_ok(stub):
		plan.extension.append(stub)


func _seam_toward(from: Vector3, aim: Vector3) -> int:
	var best := -1
	var best_score := -1.0e9
	for index in _count:
		if _edge[index] < EDGE_BUFFER * 0.65:
			continue
		if _kind[index] == KIND_CORE:
			continue
		var tangent := _dir[index] - from
		if tangent.dot(aim) < 0.15:
			continue
		if not _on_seam(index):
			continue
		var score := tangent.dot(aim) - _grade[index] * 4.0 \
				+ (0.4 if _saddle[index] != 0 else 0.0)
		if _kind[index] == KIND_PARK:
			score -= 0.8
		if score > best_score:
			best_score = score
			best = index
	if best >= 0:
		return best
	for index in _count:
		if _kind[index] == KIND_CORE or _edge[index] < 80.0:
			continue
		var tangent := _dir[index] - from
		if tangent.dot(aim) < 0.2:
			continue
		var score := tangent.dot(aim) - _grade[index] * 3.0
		if score > best_score:
			best_score = score
			best = index
	return best


func _on_seam(index: int) -> bool:
	var here := _district[index]
	for other in _neighbors(index):
		if _district[other] != here:
			return true
		if _kind[other] == KIND_CORE and _kind[index] != KIND_CORE:
			return true
	return _is_border_cell(index)


func _path(start: int, goal: int) -> PackedInt32Array:
	if start < 0 or goal < 0:
		return PackedInt32Array()
	var dist: Dictionary = {start: 0.0}
	var prev: Dictionary = {}
	var queue: Array[int] = [start]
	var cursor := 0
	while cursor < queue.size():
		var at: int = queue[cursor]
		cursor += 1
		if at == goal:
			break
		for other in _neighbors8(at):
			if _grade[other] > ROAD_GRADE + 0.04 and _saddle[other] == 0:
				continue
			var cost := CELL * (1.0 + 10.0 * _grade[other])
			cost += absf(_elev[other] - _elev[at]) * 2.2
			if _kind[other] == KIND_CORE:
				cost += 80.0
			if _edge[other] < EDGE_BUFFER * 0.5:
				cost += 40.0
			if _kind[other] == KIND_PARK:
				cost += 12.0
			if not _on_seam(other):
				cost += 18.0
			if _saddle[other] != 0:
				cost *= 0.55
			var next: float = float(dist[at]) + cost
			if next < float(dist.get(other, 1.0e12)):
				dist[other] = next
				prev[other] = at
				queue.append(other)
	if not prev.has(goal) and start != goal:
		return PackedInt32Array([start, goal])
	var run := PackedInt32Array()
	var at := goal
	run.append(at)
	while prev.has(at):
		at = int(prev[at])
		run.append(at)
	run.reverse()
	return run


func _unstick_interior(loop_cells: Array) -> void:
	for index in loop_cells.size():
		var cell: int = int(loop_cells[index])
		if _on_seam(cell) or _kind[cell] != KIND_CORE:
			continue
		var best := cell
		var best_edge := _edge[cell]
		for other in _neighbors(cell):
			if _on_seam(other) and _kind[other] != KIND_CORE:
				if _edge[other] > best_edge:
					best_edge = _edge[other]
					best = other
		loop_cells[index] = best


func _touch_missing(plan: Plan, loop_cells: Array) -> void:
	var touched: Dictionary = {}
	for cell in loop_cells:
		touched[_district[int(cell)]] = true
		for other in _neighbors(int(cell)):
			touched[_district[other]] = true
	for district in plan.districts:
		if touched.has(district.id):
			continue
		var nearest := -1
		var nearest_d := 1.0e9
		var from := district.centre
		for cell in loop_cells:
			var d := from.angle_to(_dir[int(cell)])
			if d < nearest_d:
				nearest_d = d
				nearest = int(cell)
		if nearest < 0:
			continue
		var pull := _closest_cell(from)
		if pull < 0:
			continue
		var idx := loop_cells.find(nearest)
		if idx >= 0:
			loop_cells[idx] = pull


func _mark_extension(plan: Plan, loop_cells: Array) -> void:
	var best_loop := -1
	var best_out := -1
	var best := -1.0e9
	for cell in loop_cells:
		var at: int = int(cell)
		for other in _neighbors(at):
			if _edge[other] > _edge[at]:
				continue
			var corridor := _lap[other] > 2.0 or _saddle[other] != 0
			var score := (EDGE_BUFFER - _edge[other]) + (8.0 if corridor else 0.0)
			if score > best:
				best = score
				best_loop = at
				best_out = other
	if best_loop < 0:
		return
	plan.extension.append(_dir[best_loop])
	if best_out >= 0:
		plan.extension.append(_dir[best_out])
		var step := (_dir[best_out] - _dir[best_loop]).normalized()
		var further := (_dir[best_out] + step * (CELL / _radius)).normalized()
		if _inside(further):
			plan.extension.append(further)


func _route_streets(plan: Plan) -> void:
	_road_rank.resize(_count)
	_road_rank.fill(99)
	for cell in _loop_cells:
		_road_rank[int(cell)] = RANK_LOOP
	_route_arterials(plan)
	_route_collectors(plan)
	_route_locals(plan)


func _route_arterials(plan: Plan) -> void:
	var placed: Array[Vector3] = []
	for district in plan.districts:
		if not _wants_streets(district):
			continue
		var start := _district_hub(district.id)
		var goal := _nearest_loop(start)
		if start < 0 or goal < 0:
			continue
		if _cells_apart(start, goal) < 1:
			continue
		if _too_close_to_placed(_dir[start], placed, ARTERIAL_GAP * 0.45):
			continue
		var run := _path_street(start, goal, ARTERIAL_GRADE, RANK_ARTERIAL, -1)
		if run.size() < 2:
			continue
		_commit_street(plan, run, RANK_ARTERIAL)
		placed.append(_dir[start])
	for district in plan.districts:
		if district.span < ARTERIAL_GAP or not _wants_streets(district):
			continue
		var gate := _best_gate(district.id)
		if gate < 0:
			continue
		var other_id := _gate_other(gate, district.id)
		if other_id < 0:
			continue
		var other := _district_by_id(plan, other_id)
		if other == null or not _wants_streets(other):
			continue
		var hub_a := _district_hub(district.id)
		var hub_b := _district_hub(other_id)
		if hub_a < 0 or hub_b < 0:
			continue
		if _too_close_to_placed(_dir_mid(hub_a, hub_b), placed, ARTERIAL_GAP):
			continue
		var first := _path_street(hub_a, gate, ARTERIAL_GRADE, RANK_ARTERIAL, -1)
		var second := _path_street(gate, hub_b, ARTERIAL_GRADE, RANK_ARTERIAL, -1)
		if first.size() < 2 or second.size() < 2:
			continue
		_commit_street(plan, first, RANK_ARTERIAL)
		_commit_street(plan, second, RANK_ARTERIAL)
		placed.append(_dir[gate])


func _route_collectors(plan: Plan) -> void:
	for district in plan.districts:
		if not _wants_streets(district):
			continue
		if district.span < 180.0:
			continue
		var cells := _cells_of(district.id)
		if cells.size() < 4:
			continue
		var ports := _ports_of(district.id, RANK_ARTERIAL)
		if ports.size() < 2:
			var extra := _nearest_loop(_district_hub(district.id))
			if extra >= 0:
				ports.append(extra)
		if ports.size() < 2:
			continue
		var axes := _district_axes(cells, district.grade)
		var across: Vector2 = axes["across"]
		var min_s := 1.0e9
		var max_s := -1.0e9
		for cell in cells:
			var s := _to_uv(_dir[cell]).dot(across)
			min_s = minf(min_s, s)
			max_s = maxf(max_s, s)
		var cursor := min_s + COLLECTOR_GAP * 0.5
		while cursor < max_s:
			var left := _port_at(ports, across, cursor, -1.0)
			var right := _port_at(ports, across, cursor, 1.0)
			cursor += COLLECTOR_GAP
			if left < 0 or right < 0 or left == right:
				continue
			var run := _path_street(
				left, right, COLLECTOR_GRADE, RANK_COLLECTOR, district.id)
			if run.size() < 2:
				continue
			if not _ends_on_higher(run, RANK_COLLECTOR):
				continue
			_commit_street(plan, run, RANK_COLLECTOR)


func _route_locals(plan: Plan) -> void:
	for district in plan.districts:
		if not _wants_locals(district):
			continue
		var cells := _cells_of(district.id)
		if cells.size() < 3:
			continue
		var axes := _district_axes(cells, district.grade)
		var along: Vector2 = axes["along"]
		var across: Vector2 = axes["across"]
		var minor := 80.0
		var major := 150.0
		if district.grade >= 0.10:
			minor = 100.0
			major = 200.0
		elif district.grade >= 0.05:
			minor = 80.0
			major = 160.0
		var pockets := 0
		var blocks := maxi(1, int(round(district.span / major)))
		_lay_grid(plan, district, cells, along, across, major, minor, blocks, pockets)
		_lay_grid(plan, district, cells, across, along, minor, major, blocks, pockets)


func _lay_grid(
		plan: Plan,
		district: District,
		cells: PackedInt32Array,
		along: Vector2,
		across: Vector2,
		step: float,
		_span: float,
		blocks: int,
		pockets: int
	) -> void:
	var min_s := 1.0e9
	var max_s := -1.0e9
	for cell in cells:
		var s := _to_uv(_dir[cell]).dot(across)
		min_s = minf(min_s, s)
		max_s = maxf(max_s, s)
	var cursor := min_s + step * 0.5
	while cursor < max_s:
		var line := _line_cells(cells, along, across, cursor)
		cursor += step
		if line.size() < 2:
			continue
		var ends := _spine_ends(line, RANK_COLLECTOR)
		if ends.x < 0 or ends.y < 0:
			if district.grade > PARK_GRADE and pockets < maxi(1, blocks / 10) \
					and ends.x >= 0:
				var stub := PackedInt32Array([ends.x, line[line.size() / 2]])
				_commit_street(plan, stub, RANK_LOCAL)
				pockets += 1
			continue
		var run := _path_street(
			ends.x, ends.y, _local_grade_cap(district), RANK_LOCAL, district.id)
		if run.size() < 2:
			continue
		if not _ends_on_higher(run, RANK_LOCAL):
			continue
		_commit_street(plan, run, RANK_LOCAL)


func _wants_streets(district: District) -> bool:
	return district.kind != KIND_PARK and district.kind != KIND_BUFFER \
			and district.kind != KIND_PLAZA


func _wants_locals(district: District) -> bool:
	return _wants_streets(district) and district.grade <= PARK_GRADE


func _local_grade_cap(district: District) -> float:
	if district.grade >= 0.10:
		return PARK_GRADE
	if district.grade >= 0.05:
		return 0.10
	return 0.05


func _district_hub(district_id: int) -> int:
	var best := -1
	var best_score := -1.0e9
	for index in _count:
		if _district[index] != district_id:
			continue
		if _kind[index] == KIND_PARK:
			continue
		var score := -_grade[index] * 6.0 + _edge[index] / 400.0
		if score > best_score:
			best_score = score
			best = index
	return best


func _nearest_loop(from: int) -> int:
	if from < 0 or _loop_cells.is_empty():
		return -1
	var best := -1
	var best_dot := -2.0
	var at := _dir[from]
	for cell in _loop_cells:
		var toward := at.dot(_dir[int(cell)])
		if toward > best_dot:
			best_dot = toward
			best = int(cell)
	return best


func _cells_of(district_id: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for index in _count:
		if _district[index] == district_id:
			cells.append(index)
	return cells


func _ports_of(district_id: int, max_rank: int) -> PackedInt32Array:
	var ports := PackedInt32Array()
	for index in _count:
		if _road_rank[index] > max_rank:
			continue
		var touch := _district[index] == district_id
		if not touch:
			for other in _neighbors(index):
				if _district[other] == district_id:
					touch = true
					break
		if touch:
			ports.append(index)
	return ports


func _port_at(ports: PackedInt32Array, across: Vector2, cursor: float, side: float) -> int:
	var best := -1
	var best_score := -1.0e9
	for port in ports:
		var uv := _to_uv(_dir[port])
		var along := uv.dot(across) - cursor
		var score := uv.dot(across) * side - absf(along) * 0.15
		if score > best_score:
			best_score = score
			best = int(port)
	return best


func _district_axes(cells: PackedInt32Array, grade: float) -> Dictionary:
	var along := Vector2.RIGHT
	var across := Vector2.UP
	if grade >= 0.05:
		var g := Vector2.ZERO
		var n := 0
		for cell in cells:
			var x := _gx[cell]
			var y := _gy[cell]
			var e := _elev[_cell_at(x + 1, y, cell)]
			var w := _elev[_cell_at(x - 1, y, cell)]
			var north := _elev[_cell_at(x, y - 1, cell)]
			var south := _elev[_cell_at(x, y + 1, cell)]
			g += Vector2(e - w, south - north)
			n += 1
		if n > 0 and g.length_squared() > 0.0001:
			across = g.normalized()
			along = Vector2(-across.y, across.x)
			return {"along": along, "across": across}
	var mean := Vector2.ZERO
	for cell in cells:
		mean += _to_uv(_dir[cell])
	mean /= float(maxi(cells.size(), 1))
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for cell in cells:
		var p := _to_uv(_dir[cell]) - mean
		xx += p.x * p.x
		xy += p.x * p.y
		yy += p.y * p.y
	var det := sqrt(maxf((xx - yy) * (xx - yy) + 4.0 * xy * xy, 0.0))
	var vx := xx - yy + det
	var vy := 2.0 * xy
	if vx * vx + vy * vy > 0.0001:
		along = Vector2(vx, vy).normalized()
		across = Vector2(-along.y, along.x)
	return {"along": along, "across": across}


func _cell_at(x: int, y: int, fallback: int) -> int:
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return fallback
	var other := _grid[y * _width + x]
	return other if other >= 0 else fallback


func _line_cells(
		cells: PackedInt32Array,
		along: Vector2,
		across: Vector2,
		cursor: float
	) -> PackedInt32Array:
	var member: Dictionary = {}
	var min_t := 1.0e9
	var max_t := -1.0e9
	for cell in cells:
		member[cell] = true
		var uv := _to_uv(_dir[cell])
		if absf(uv.dot(across) - cursor) > CELL * 0.85:
			continue
		var t := uv.dot(along)
		min_t = minf(min_t, t)
		max_t = maxf(max_t, t)
	var line := PackedInt32Array()
	var last := -1
	var t := min_t
	while t <= max_t + CELL * 0.5:
		var uv := along * t + across * cursor
		var at := _closest_in(member, uv)
		if at >= 0 and at != last:
			line.append(at)
			last = at
		t += CELL * 0.6
	return line


func _closest_in(member: Dictionary, uv: Vector2) -> int:
	var best := -1
	var best_d := CELL * CELL * 2.2
	for key in member:
		var cell: int = int(key)
		var d := _to_uv(_dir[cell]).distance_squared_to(uv)
		if d < best_d:
			best_d = d
			best = cell
	return best


func _spine_ends(line: PackedInt32Array, max_rank: int) -> Vector2i:
	var first := -1
	var last := -1
	for cell in line:
		if _road_rank[cell] <= max_rank or _near_rank(cell, max_rank):
			if first < 0:
				first = int(cell)
			last = int(cell)
	return Vector2i(first, last)


func _near_rank(cell: int, max_rank: int) -> bool:
	for other in _neighbors(cell):
		if _road_rank[other] <= max_rank:
			return true
	return false


func _ends_on_higher(run: PackedInt32Array, rank: int) -> bool:
	if run.size() < 2:
		return false
	return _road_rank[run[0]] < rank and _road_rank[run[run.size() - 1]] < rank


func _is_gate(index: int) -> bool:
	if _kind[index] != KIND_PARK and _kind[index] != KIND_PLAZA \
			and _kind[index] != KIND_BUFFER:
		return false
	var seen: Dictionary = {}
	for other in _neighbors(index):
		if _district[other] >= 0:
			seen[_district[other]] = true
	return seen.size() >= 2


func _best_gate(district_id: int) -> int:
	var best := -1
	var best_score := -1.0e9
	for index in _count:
		if not _is_gate(index):
			continue
		var touches := false
		for other in _neighbors(index):
			if _district[other] == district_id:
				touches = true
				break
		if not touches:
			continue
		var score := -_grade[index] * 4.0 + (1.0 if _saddle[index] != 0 else 0.0)
		if score > best_score:
			best_score = score
			best = index
	return best


func _gate_other(gate: int, district_id: int) -> int:
	for other in _neighbors(gate):
		if _district[other] >= 0 and _district[other] != district_id \
				and _kind[other] != KIND_PARK and _kind[other] != KIND_BUFFER \
				and _kind[other] != KIND_PLAZA:
			return _district[other]
	return -1


func _district_by_id(plan: Plan, district_id: int) -> District:
	for district in plan.districts:
		if district.id == district_id:
			return district
	return null


func _too_close_to_placed(direction: Vector3, placed: Array[Vector3], gap: float) -> bool:
	for other in placed:
		if direction.angle_to(other) * _radius < gap:
			return true
	return false


func _dir_mid(a: int, b: int) -> Vector3:
	return (_dir[a] + _dir[b]).normalized()


func _cells_apart(a: int, b: int) -> int:
	return absi(_gx[a] - _gx[b]) + absi(_gy[a] - _gy[b])


func _cross_slope(a: int, b: int) -> float:
	var step := _dir[b] - _dir[a]
	var along := (step - _dir[a] * step.dot(_dir[a])).normalized()
	if along.length_squared() < 0.0001:
		return 0.0
	var side := _dir[a].cross(along).normalized()
	var sample := (_dir[a] + side * (CELL / _radius)).normalized()
	return absf(_shape.elevation(sample, CELL) - _elev[a]) / CELL


func _seam_ok(a: int, b: int, rank: int) -> bool:
	if _district[a] == _district[b]:
		return true
	var soft := _kind[a] == KIND_PARK or _kind[a] == KIND_PLAZA \
			or _kind[a] == KIND_BUFFER or _kind[b] == KIND_PARK \
			or _kind[b] == KIND_PLAZA or _kind[b] == KIND_BUFFER
	if not soft:
		return rank <= RANK_ARTERIAL
	return _is_gate(a) or _is_gate(b)


func _path_street(
		start: int,
		goal: int,
		max_grade: float,
		rank: int,
		stay: int
	) -> PackedInt32Array:
	if start < 0 or goal < 0:
		return PackedInt32Array()
	var dist: Dictionary = {start: 0.0}
	var prev: Dictionary = {}
	var queue: Array[int] = [start]
	var cursor := 0
	while cursor < queue.size():
		var at: int = queue[cursor]
		cursor += 1
		if at == goal:
			break
		if _road_rank[at] == RANK_LOOP and at != start:
			continue
		for other in _neighbors8(at):
			if stay >= 0 and _district[other] != stay \
					and _road_rank[other] > RANK_ARTERIAL:
				continue
			if _road_rank[other] == RANK_LOOP and other != goal and at != start:
				continue
			if _grade[other] > max_grade + 0.03 and _saddle[other] == 0:
				if rank == RANK_LOCAL:
					continue
				if _grade[other] > max_grade + 0.06:
					continue
			if not _seam_ok(at, other, rank):
				continue
			if _kind[other] == KIND_PARK and not _is_gate(other) \
					and _road_rank[other] > RANK_LOOP:
				continue
			var rise := absf(_elev[other] - _elev[at]) / CELL
			var cost := CELL * (1.0 + 8.0 * _grade[other] + 6.0 * rise)
			if rank <= RANK_ARTERIAL and rise > 0.08:
				cost += 40.0
			if _kind[other] == KIND_PARK:
				cost += 16.0
			var next: float = float(dist[at]) + cost
			if next < float(dist.get(other, 1.0e12)):
				dist[other] = next
				prev[other] = at
				queue.append(other)
	if not prev.has(goal) and start != goal:
		return PackedInt32Array()
	var run := PackedInt32Array()
	var at := goal
	run.append(at)
	while prev.has(at):
		at = int(prev[at])
		run.append(at)
	run.reverse()
	return run


func _commit_street(plan: Plan, run: PackedInt32Array, rank: int) -> void:
	if run.size() < 2:
		return
	var street := Street.new()
	street.rank = rank
	street.dirs.resize(run.size())
	var terrace := false
	for index in run.size():
		var cell := int(run[index])
		street.dirs[index] = _dir[cell]
		if _road_rank[cell] > rank:
			_road_rank[cell] = rank
		if index > 0 and _cross_slope(int(run[index - 1]), cell) > 0.20:
			terrace = true
	street.terrace = terrace
	plan.streets.append(street)


func _closest_cell(direction: Vector3) -> int:
	var best := -1
	var best_dot := -2.0
	for index in _count:
		var toward := direction.dot(_dir[index])
		if toward > best_dot:
			best_dot = toward
			best = index
	return best


func _neighbors(index: int) -> PackedInt32Array:
	var steps: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	]
	return _offset_neighbors(index, steps)


func _neighbors8(index: int) -> PackedInt32Array:
	var steps: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	return _offset_neighbors(index, steps)


func _offset_neighbors(index: int, steps: Array[Vector2i]) -> PackedInt32Array:
	var found := PackedInt32Array()
	var x := _gx[index]
	var y := _gy[index]
	for step in steps:
		var nx := x + step.x
		var ny := y + step.y
		if nx < 0 or ny < 0 or nx >= _width or ny >= _height:
			continue
		var other := _grid[ny * _width + nx]
		if other >= 0:
			found.append(other)
	return found


func _to_uv(direction: Vector3) -> Vector2:
	var q := direction - _up * direction.dot(_up)
	return Vector2(q.dot(_east), q.dot(_north)) * _radius


func _from_uv(uv: Vector2) -> Vector3:
	return (_up + (_east * uv.x + _north * uv.y) / _radius).normalized()


func _uv(index: int) -> Vector2:
	return _origin + Vector2((float(_gx[index]) + 0.5) * CELL, (float(_gy[index]) + 0.5) * CELL) \
			- Vector2.ZERO
