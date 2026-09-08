extends SceneTree

## Builds a randomised planet-wide site map: spawn, cities, castles, offices,
## boss circles, goblin and shrimp pads, latitude-clipped rings, statues,
## and patch mob packs. One first-ring boss is the giant tree battle; the
## rest of the circles stay empty.
##
##     godot --headless --path . --script dev/run_creator.gd
##     godot --headless --path . --script dev/run_creator.gd -- --seed=7 --out=res://assets/runtime/crawler/runs/run_01.json
##     godot --headless --path . --script dev/run_creator.gd -- --batch=20 --out-dir=res://assets/runtime/crawler/runs
##
## Every site sits on dry, frost-free, reasonably flat ground between 60° S and
## 60° N. Distances are great-circle metres on the natural (unsettled) planet.

const DEFAULT_OUT := "res://assets/runtime/crawler/runs/run_01.json"
const DEFAULT_OUT_DIR := "res://assets/runtime/crawler/runs"
const LAT_LIMIT := 60.0
const DRY := 3.0
const SITE_SLOPE_DEG := 10.0
const CITY_SLOPE_DEG := 8.0

const CITY1_MIN := 500.0
const CITY1_MAX := 750.0
const SAT_MIN := 500.0
const SAT_MAX := 750.0
const SPAWN_CASTLE_MIN := 1500.0
const CASTLE_OFFICE_MIN := 1000.0
const CITY2_FROM_CITY1 := 1000.0
const CITY2_FROM_SPAWN := 1500.0
const CITY2_FROM_SITE := 300.0
const CITY2_SPAWN_MAX := 2600.0
const RING_CITIES := 4
const RING_CITY_SEP := 2000.0
const BOSSES_PER_RING := 2
const BOSS_ENCOUNTER_EMPTY := "empty"
const BOSS_ENCOUNTER_TREE := "tree"
const BOSS_SEP := 2000.0
const BOSS_RADIUS := 100.0
const BOSS_EDGE_BAND := 140.0
const BOSS_SITE_CLEAR := 200.0
const RING1_BORDER := 400.0
const RING2_WIDTH := 2000.0
const RING_GROW := 500.0
const SITE_SPIRAL := 42000
const STATUE_SPACING := 72.0
const STATUE_MIN := 50.0
const STATUE_MAX := 200.0
const GOBLIN_PAD := 38.0
const SHRIMP_PAD := 34.0
const GOBLINS_PER_CASTLE := 100
const SHRIMPS_PER_OFFICE := 20
const GOBLIN_INNER := 14.0
const GOBLIN_OUTER := 158.0
const SHRIMP_INNER := 8.0
const SHRIMP_OUTER := 36.0
const GOLDEN := 2.399963229728653
const STATUE_KINDS := ["wealth", "wings", "health", "strength", "misc"]
const GOBLIN_KINDS := ["gruk", "nix", "vex"]
const SHRIMP_KINDS := ["PIP", "BRACK", "SERA"]
const SHOP_IDS := [
	"hats", "caps", "capes", "cards", "abilities", "upgrades",
	"inventory", "locker", "quests", "market", "reststop", "duals",
]
const SHOP_ALWAYS := ["inventory", "reststop", "duals"]
const SHOP_OPTIONAL := [
	"hats", "caps", "capes", "cards", "abilities", "upgrades",
	"locker", "quests", "market",
]
const MOUNTAINS := [
	Vector3(-0.270521, -0.3052884, -0.9130266),
	Vector3(0.6848267, 0.0168872, 0.7285103),
	Vector3(0.2574172, -0.2996968, -0.9186503),
	Vector3(0.4474815, -0.0008659, -0.8942928),
]
const PACKS := [
	{
		"id": "basic",
		"combo": "wild",
		"kinds": ["ranger", "rammer", "rhino"],
	},
	{
		"id": "bots",
		"combo": "robot",
		"kinds": ["kestrel", "bastion", "weaver"],
	},
	{
		"id": "demons",
		"combo": "demon",
		"kinds": ["gloam", "vesper", "threnody"],
	},
	{
		"id": "aliens",
		"combo": "alien",
		"kinds": ["scout", "gray", "tanglemaw"],
	},
]

var _shape: PlanetShape
var _rng := RandomNumberGenerator.new()
var _radius := 8000.0
var _dirs := PackedVector3Array()
var _slope := PackedFloat32Array()
var _lat := PackedFloat32Array()
var _city_hits := PackedInt32Array()
var _rings: Array[Dictionary] = []
var _center := Vector3.UP
var _spawn := Vector3.UP
var _cities: Array[Dictionary] = []
var _castles: Array[Dictionary] = []
var _offices: Array[Dictionary] = []
var _bosses: Array[Dictionary] = []
var _warnings: PackedStringArray = PackedStringArray()
var _partition: LandPartition
var _goblins: Array = []
var _shrimps: Array = []


func _initialize() -> void:
	var args := _flags()
	var seed := int(args.get("seed", 0.0))
	if seed == 0:
		seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
		if seed == 0:
			seed = 1
	var batch := maxi(int(args.get("batch", 1.0)), 1)
	var out_dir := String(args.get("out-dir", DEFAULT_OUT_DIR))
	var out_path := String(args.get("out", DEFAULT_OUT))
	var started := Time.get_ticks_usec()
	print("run_creator: seed %d  batch %d" % [seed, batch])

	_shape = PlanetShape.new()
	_shape.settled = false
	_shape.prepare()
	_radius = _shape.radius
	print("  planet ready  %.2fs" % _secs(started))

	_gather_land()
	print("  land %d  city-flat %d  %.2fs" % [
		_dirs.size(), _city_hits.size(), _secs(started)])
	if _city_hits.is_empty():
		printerr("FAIL: no flat land between 60 S and 60 N")
		quit(1)
		return
	_bake_partition()
	print("  patches ready  %d  %.2fs" % [
		_partition.patches.size() if _partition != null else 0, _secs(started)])

	for index in batch:
		var run_seed := seed + index * 7919
		var path := out_path if batch == 1 else "%s/run_%02d.json" % [out_dir, index + 1]
		if not _write_run(run_seed, path, started):
			quit(1)
			return
	quit()


func _reset_layout() -> void:
	_rings.clear()
	_cities.clear()
	_castles.clear()
	_offices.clear()
	_bosses.clear()
	_goblins.clear()
	_shrimps.clear()
	_warnings = PackedStringArray()
	_center = Vector3.UP
	_spawn = Vector3.UP


func _write_run(seed: int, out_path: String, started: int) -> bool:
	_reset_layout()
	_rng.seed = seed
	print("run_creator: writing %s  seed %d" % [out_path, seed])
	if not _place_opening():
		printerr("FAIL: could not place spawn / first city / castle / office")
		return false
	_place_follow_cities()
	_build_rings()
	_place_outer_rings()
	_place_bosses()
	_assign_tree_battle()
	var statues: Array = _place_statues()
	print("  statues %d  %.2fs" % [statues.size(), _secs(started)])
	var patches: Array = _place_patches()
	print("  patches %d  %.2fs" % [patches.size(), _secs(started)])
	var payload := _payload(seed, statues, patches, started)
	if not _write(out_path, payload):
		return false
	_report(payload, out_path, started)
	return true


func _place_opening() -> bool:
	var spawn_i := _pick_spawn()
	if spawn_i < 0:
		return false
	_spawn = _dirs[spawn_i]
	_center = _spawn

	# 1500 m from spawn to castle/office only works when city1 is near 750 m
	# and the satellites sit on the far side of that city.
	var city1_i := _pick_in_range(_spawn, 730.0, CITY1_MAX, _city_hits, [], 0.0)
	if city1_i < 0:
		city1_i = _pick_in_range(_spawn, 680.0, CITY1_MAX, _city_hits, [], 0.0)
	if city1_i < 0:
		city1_i = _pick_in_range(_spawn, CITY1_MIN, CITY1_MAX, _city_hits, [], 0.0)
	if city1_i < 0:
		return false
	var city1 := _dirs[city1_i]
	if _metres(_spawn, city1) < 730.0:
		var pushed := _keep_land(
			_move(city1, _away_tangent(city1, _spawn), 745.0), 90.0)
		if pushed != Vector3.ZERO and _metres(_spawn, pushed) <= CITY1_MAX + 15.0 \
				and _metres(_spawn, pushed) >= CITY1_MIN:
			city1 = pushed

	var pair := _opening_satellites(city1, _spawn)
	if pair.size() < 2:
		pair = _satellites_for(city1, _spawn, true)
	if pair.size() < 2:
		return false

	_add_city("city1", 1, city1)
	_add_castle("castle1", "city1", 1, pair[0])
	_add_office("office1", "city1", 1, pair[1])
	print("  spawn / city1 / castle1 / office1")
	return true


func _place_follow_cities() -> void:
	var hits := _filtered(_city_hits, func(dir: Vector3) -> bool:
		if _metres(_spawn, dir) < CITY2_FROM_SPAWN:
			return false
		if _metres(_spawn, dir) > CITY2_SPAWN_MAX:
			return false
		if _metres(_city_dir("city1"), dir) < CITY2_FROM_CITY1:
			return false
		for other: Vector3 in _site_dirs():
			if _metres(other, dir) < CITY2_FROM_SITE:
				return false
		return true)
	var picked := _pick_spread(hits, 2, 400.0)
	if picked.size() < 2:
		hits = _filtered(_city_hits, func(dir: Vector3) -> bool:
			return _metres(_spawn, dir) >= CITY2_FROM_SPAWN \
				and _metres(_city_dir("city1"), dir) >= CITY2_FROM_CITY1
		)
		picked = _pick_spread(hits, 2, 300.0)
	for index in mini(2, picked.size()):
		var name := "city%d" % (_cities.size() + 1)
		_add_city(name, 1, _dirs[picked[index]])
	if picked.size() < 2:
		_warn("only %d of city2/city3 could be placed" % picked.size())
	print("  city2 / city3  (%d)" % picked.size())


func _build_rings() -> void:
	var cluster: Array[Vector3] = [_spawn]
	for city: Dictionary in _cities:
		cluster.append(_from_vec(city["direction"]))
	for castle: Dictionary in _castles:
		cluster.append(_from_vec(castle["direction"]))
	for office: Dictionary in _offices:
		cluster.append(_from_vec(office["direction"]))
	_center = _mean_dir(cluster)
	if not _in_belt(_center):
		_center = _spawn

	var reach := 0.0
	for at: Vector3 in cluster:
		reach = maxf(reach, _metres(_center, at))
	var inner := 0.0
	var outer := reach + RING1_BORDER
	_rings.append(_ring_entry(1, inner, outer))

	var cover := _belt_cover_m()
	var ring_id := 2
	var width := RING2_WIDTH
	while outer < cover - 25.0:
		inner = outer
		outer = minf(inner + width, cover)
		_rings.append(_ring_entry(ring_id, inner, outer))
		ring_id += 1
		width += RING_GROW
	print("  rings %d  cover %.0f m  centre lat %.1f" % [
		_rings.size(), cover, _latitude(_center)])


func _place_outer_rings() -> void:
	for ring: Dictionary in _rings:
		var ring_id := int(ring["id"])
		if ring_id < 2:
			continue
		var hits := _filtered(_city_hits, func(dir: Vector3) -> bool:
			return _in_ring(dir, ring_id)
		)
		var picked := _pick_spread(hits, RING_CITIES, RING_CITY_SEP)
		if picked.size() < RING_CITIES:
			picked = _pick_spread(hits, RING_CITIES, RING_CITY_SEP * 0.75)
		if picked.size() < RING_CITIES:
			_warn("ring %d placed %d of %d cities" % [
				ring_id, picked.size(), RING_CITIES])
		for index in picked.size():
			var city_name := "city%d" % (_cities.size() + 1)
			var city_dir: Vector3 = _dirs[picked[index]]
			_add_city(city_name, ring_id, city_dir)
			var pair := _satellites_for(city_dir, Vector3.ZERO, false)
			if pair.size() < 2:
				_warn("%s missing castle/office" % city_name)
				continue
			var n := _cities.size()
			_add_castle("castle%d" % n, city_name, ring_id, pair[0])
			_add_office("office%d" % n, city_name, ring_id, pair[1])
		print("  ring %d  cities +%d" % [ring_id, picked.size()])


func _place_bosses() -> void:
	# Two 100 m circles sit on each ring's outer edge — the seam between
	# that circle and the next ring — on flat land, 2000 m apart. All of
	# them start empty; `_assign_tree_battle` fills one first-ring pad.
	for ring: Dictionary in _rings:
		var ring_id := int(ring["id"])
		var outer := float(ring["outer_m"])
		var avoid := _boss_dirs()
		var hits := _filtered(_city_hits, func(dir: Vector3) -> bool:
			if absf(_metres(_center, dir) - outer) > BOSS_EDGE_BAND:
				return false
			for other: Vector3 in _occupied_dirs():
				if _metres(other, dir) < BOSS_SITE_CLEAR:
					return false
			return true
		)
		var picked := _pick_spread(hits, BOSSES_PER_RING, BOSS_SEP, avoid)
		if picked.size() < BOSSES_PER_RING:
			picked = _pick_spread(hits, BOSSES_PER_RING, BOSS_SEP * 0.75, avoid)
		if picked.size() < BOSSES_PER_RING:
			_warn("ring %d placed %d of %d bosses" % [
				ring_id, picked.size(), BOSSES_PER_RING])
		for index in picked.size():
			_add_boss("boss%d" % (_bosses.size() + 1), ring_id, _dirs[picked[index]])
		print("  ring %d  bosses +%d" % [ring_id, picked.size()])


func _assign_tree_battle() -> void:
	for raw: Variant in _bosses:
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if int(row.get("ring", 0)) != 1:
			continue
		row["empty"] = false
		row["encounter"] = BOSS_ENCOUNTER_TREE
		print("  tree battle  %s  ring 1" % str(row.get("id", "")))
		return
	_warn("no first-ring boss site for the giant tree")


func _place_statues() -> Array:
	var kinds: PackedStringArray = PackedStringArray(STATUE_KINDS)
	var want := int(round(4.0 * PI * _radius * _radius / (STATUE_SPACING * STATUE_SPACING)))
	want = clampi(want, 8000, 180000)
	var candidates := PackedVector3Array()
	for index in want:
		var direction := PlanetShape.even_direction(index, want)
		if not _site_ok(direction, false):
			continue
		candidates.append(direction)
	var kept := _poisson(candidates, STATUE_MIN)
	var order: Array[int] = []
	for index in kept.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: Vector3 = kept[a]
		var db: Vector3 = kept[b]
		var ka := _longitude(da)
		var kb := _longitude(db)
		if is_equal_approx(ka, kb):
			return _latitude(da) < _latitude(db)
		return ka < kb)
	var out: Array = []
	for slot in order.size():
		var direction: Vector3 = kept[order[slot]]
		var kind := String(kinds[slot % kinds.size()])
		out.append({
			"id": "statue%d" % (slot + 1),
			"kind": kind,
			"lat": _latitude(direction),
			"lon": _longitude(direction),
			"direction": _vec(direction),
		})
	return out


func _bake_partition() -> void:
	var mountains := PackedVector3Array()
	for at: Vector3 in MOUNTAINS:
		mountains.append(at)
	_partition = LandPartition.new()
	_partition.bake(_shape, mountains, 1000.0, 1300.0)


func _place_patches() -> Array:
	var out: Array = []
	if _partition == null or _partition.patches.is_empty():
		_warn("land partition produced no patches")
		return out
	var order: Array[int] = []
	for index in _partition.patches.size():
		order.append(index)
	_shuffle_ints(order)
	for slot in order.size():
		var patch: LandPartition.Patch = _partition.patches[order[slot]]
		var direction: Vector3 = patch.direction
		if direction.length_squared() < 0.25:
			direction = patch.seed
		direction = direction.normalized()
		if not _in_belt(direction):
			continue
		var ring_id := _ring_of(direction)
		var pack: Dictionary = PACKS[slot % PACKS.size()]
		out.append({
			"id": patch.id,
			"name": patch.name,
			"recipe": patch.recipe_name,
			"ring": ring_id,
			"level": maxi(ring_id, 1),
			"pack": pack["id"],
			"combo": pack["combo"],
			"kinds": PackedStringArray(pack["kinds"]),
			"area": patch.area,
			"lat": _latitude(direction),
			"lon": _longitude(direction),
			"direction": _vec(direction),
		})
	return out


func _payload(seed: int, statues: Array, patches: Array, started: int) -> Dictionary:
	return {
		"seed": seed,
		"radius_m": _radius,
		"lat_limit_deg": LAT_LIMIT,
		"generated_at": Time.get_datetime_string_from_system(true, true),
		"elapsed_ms": int(round(_secs(started) * 1000.0)),
		"ring_center": _point(_center, "ring_center", 0),
		"counts": _counts(statues, patches),
		"warnings": _warnings,
		"rings": _rings,
		"spawn": _point(_spawn, "spawn", 1),
		"cities": _cities,
		"castles": _castles,
		"offices": _offices,
		"bosses": _bosses,
		"goblin_spawns": _goblins,
		"shrimp_spawns": _shrimps,
		"statues": statues,
		"patches": patches,
	}


func _counts(statues: Array, patches: Array) -> Dictionary:
	var statue_kinds := {}
	for kind: String in STATUE_KINDS:
		statue_kinds[kind] = 0
	for statue: Dictionary in statues:
		var kind := String(statue.get("kind", ""))
		statue_kinds[kind] = int(statue_kinds.get(kind, 0)) + 1
	var packs := {}
	var levels := {}
	var boss_encounters := {}
	for pack: Dictionary in PACKS:
		packs[String(pack["id"])] = 0
	for patch: Dictionary in patches:
		var pack_id := String(patch.get("pack", ""))
		packs[pack_id] = int(packs.get(pack_id, 0)) + 1
		var level := str(int(patch.get("level", 0)))
		levels[level] = int(levels.get(level, 0)) + 1
	for boss: Dictionary in _bosses:
		var encounter := String(boss.get("encounter", BOSS_ENCOUNTER_EMPTY))
		if encounter.is_empty():
			encounter = BOSS_ENCOUNTER_EMPTY
		boss_encounters[encounter] = int(boss_encounters.get(encounter, 0)) + 1
	return {
		"spawn": 1,
		"cities": _cities.size(),
		"castles": _castles.size(),
		"offices": _offices.size(),
		"bosses": _bosses.size(),
		"boss_encounters": boss_encounters,
		"goblin_spawns": _goblins.size(),
		"shrimp_spawns": _shrimps.size(),
		"rings": _rings.size(),
		"statues": statues.size(),
		"statue_kinds": statue_kinds,
		"patches": patches.size(),
		"patch_packs": packs,
		"patch_levels": levels,
	}


func _report(payload: Dictionary, out_path: String, started: int) -> void:
	var counts: Dictionary = payload["counts"]
	print("run_creator: wrote %s" % out_path)
	print("  elapsed  %.2fs" % _secs(started))
	print("  spawn %d" % int(counts["spawn"]))
	print("  cities %d" % int(counts["cities"]))
	print("  castles %d" % int(counts["castles"]))
	print("  offices %d" % int(counts["offices"]))
	print("  bosses %d" % int(counts.get("bosses", 0)))
	var encounters: Dictionary = counts.get("boss_encounters", {})
	var encounter_keys: Array = encounters.keys()
	encounter_keys.sort()
	for encounter: Variant in encounter_keys:
		print("    encounter %s %d" % [str(encounter), int(encounters[encounter])])
	print("  goblin_spawns %d" % int(counts["goblin_spawns"]))
	print("  shrimp_spawns %d" % int(counts["shrimp_spawns"]))
	print("  rings %d" % int(counts["rings"]))
	print("  statues %d" % int(counts["statues"]))
	var kinds: Dictionary = counts["statue_kinds"]
	for kind: String in STATUE_KINDS:
		print("    %s %d" % [kind, int(kinds.get(kind, 0))])
	print("  patches %d" % int(counts["patches"]))
	var packs: Dictionary = counts["patch_packs"]
	for pack: Dictionary in PACKS:
		var pack_id := String(pack["id"])
		print("    pack %s %d" % [pack_id, int(packs.get(pack_id, 0))])
	var levels: Dictionary = counts["patch_levels"]
	var level_keys: Array = levels.keys()
	level_keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int(a) < int(b))
	for level: Variant in level_keys:
		print("    level %s %d" % [str(level), int(levels[level])])
	for warning: String in _warnings:
		print("  warning: %s" % warning)


func _write(path: String, payload: Dictionary) -> bool:
	var abs_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: could not write %s (%s)" % [
			path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	return true


func _gather_land() -> void:
	_dirs = PackedVector3Array()
	_slope = PackedFloat32Array()
	_lat = PackedFloat32Array()
	_city_hits = PackedInt32Array()
	for index in SITE_SPIRAL:
		var direction := PlanetShape.even_direction(index, SITE_SPIRAL)
		if not _site_ok(direction, true):
			continue
		var slope := _slope_deg(direction)
		if slope > SITE_SLOPE_DEG:
			continue
		_dirs.append(direction)
		_slope.append(slope)
		_lat.append(_latitude(direction))
		if slope <= CITY_SLOPE_DEG:
			_city_hits.append(_dirs.size() - 1)


func _pick_spawn() -> int:
	var hits := PackedInt32Array()
	for index in _city_hits:
		if absf(_lat[index]) <= 28.0:
			hits.append(index)
	if hits.is_empty():
		hits = _city_hits
	if hits.is_empty():
		return -1
	return hits[_rng.randi_range(0, hits.size() - 1)]


func _pick_in_range(
		from: Vector3,
		min_m: float,
		max_m: float,
		pool: PackedInt32Array,
		avoid: Array,
		clear_m: float
	) -> int:
	var hits := PackedInt32Array()
	for index in pool:
		var dir := _dirs[index]
		var span := _metres(from, dir)
		if span < min_m or span > max_m:
			continue
		var blocked := false
		for other: Variant in avoid:
			if _metres(dir, other) < clear_m:
				blocked = true
				break
		if blocked:
			continue
		hits.append(index)
	if hits.is_empty():
		return -1
	return hits[_rng.randi_range(0, hits.size() - 1)]


func _opening_satellites(city: Vector3, spawn: Vector3) -> Array[Vector3]:
	# City at ~750 m and a far-side satellite at ~750 m is the only way to
	# approach 1500 m from spawn. Two satellites 1000 m apart cannot both
	# sit on that far point, so the castle takes the away bearing and the
	# office sits a 1000 m chord around the same ring.
	var away := _away_tangent(city, spawn)
	var reach := lerpf(SAT_MIN, SAT_MAX, 0.94)
	var half := asin(clampf(CASTLE_OFFICE_MIN * 0.5 / reach, 0.0, 1.0))
	var castle := _keep_land(_move(city, away.rotated(city, half), reach), 80.0)
	var office := _keep_land(_move(city, away.rotated(city, -half), reach), 80.0)
	if castle == Vector3.ZERO:
		castle = _move(city, away.rotated(city, half), reach)
	if office == Vector3.ZERO:
		office = _move(city, away.rotated(city, -half), reach)
	return _pair(castle, office)


func _satellites_for(city: Vector3, spawn: Vector3, opening: bool) -> Array[Vector3]:
	var spawn_min := SPAWN_CASTLE_MIN if opening else 0.0
	var pair := _pair_from_ring(city, spawn, opening, SAT_MIN, SAT_MAX, spawn_min)
	if pair.size() >= 2:
		return pair
	pair = _pair_from_ring(city, spawn, opening, 450.0, 850.0, spawn_min * 0.92)
	if pair.size() >= 2:
		return pair
	return _constructed_pair(city, spawn, opening)


func _pair_from_ring(
		city: Vector3,
		spawn: Vector3,
		opening: bool,
		min_m: float,
		max_m: float,
		spawn_min: float
	) -> Array[Vector3]:
	var hits := _ring_hits(city, min_m, max_m)
	var usable: Array[Vector3] = []
	for at: Vector3 in hits:
		if opening and spawn_min > 0.0 and _metres(spawn, at) < spawn_min:
			continue
		usable.append(at)
	var chosen := _pair_separated(usable, CASTLE_OFFICE_MIN)
	if chosen.size() >= 2:
		return chosen
	if opening:
		return [] as Array[Vector3]
	return _pair_separated(hits, CASTLE_OFFICE_MIN * 0.8)


func _ring_hits(city: Vector3, min_m: float, max_m: float) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var east := _frame(city)[0]
	for step in 48:
		var tangent := east.rotated(city, TAU * float(step) / 48.0)
		for part in 3:
			var reach := lerpf(min_m, max_m, float(part) / 2.0)
			var at := _keep_land(_move(city, tangent, reach), 70.0)
			if at == Vector3.ZERO:
				continue
			var span := _metres(city, at)
			if span < min_m * 0.85 or span > max_m * 1.15:
				continue
			found.append(at)
	for index in _dirs.size():
		var span := _metres(city, _dirs[index])
		if span >= min_m and span <= max_m:
			found.append(_dirs[index])
	return found


func _pair_separated(hits: Array[Vector3], min_sep: float) -> Array[Vector3]:
	if hits.size() < 2:
		return [] as Array[Vector3]
	var best_a := hits[0]
	var best_b := hits[1]
	var best_d := _metres(best_a, best_b)
	var start := _rng.randi_range(0, hits.size() - 1)
	for offset in mini(hits.size(), 80):
		var a: Vector3 = hits[(start + offset) % hits.size()]
		for other in hits:
			var span := _metres(a, other)
			if span >= min_sep:
				return _pair(a, other)
			if span > best_d:
				best_d = span
				best_a = a
				best_b = other
	if best_d >= min_sep * 0.75:
		return _pair(best_a, best_b)
	return [] as Array[Vector3]


func _constructed_pair(city: Vector3, spawn: Vector3, opening: bool) -> Array[Vector3]:
	var away := _away_tangent(city, spawn if opening else city)
	var reach := lerpf(SAT_MIN, SAT_MAX, 0.92)
	var castle := _keep_land(_move(city, away.rotated(city, 0.95), reach), 120.0)
	var office := _keep_land(_move(city, away.rotated(city, -0.95), reach), 120.0)
	if castle == Vector3.ZERO:
		castle = _move(city, away.rotated(city, 0.95), reach)
	if office == Vector3.ZERO:
		office = _move(city, away.rotated(city, -0.95), reach)
	if opening:
		castle = _nudge_from(spawn, castle, SPAWN_CASTLE_MIN * 0.96)
		office = _nudge_from(spawn, office, SPAWN_CASTLE_MIN * 0.96)
	if _metres(castle, office) < CASTLE_OFFICE_MIN:
		office = _nudge_from(castle, office, CASTLE_OFFICE_MIN)
	return _pair(castle, office)


func _pick_spread(
		pool: PackedInt32Array,
		count: int,
		min_sep: float,
		avoid: Array = []
	) -> PackedInt32Array:
	var out := PackedInt32Array()
	if pool.is_empty() or count <= 0:
		return out
	var work := pool.duplicate()
	_shuffle_packed(work)
	for index in work:
		if _spread_span(_dirs[index], out, avoid) >= min_sep:
			out.append(index)
			break
	if out.is_empty():
		return out
	while out.size() < count:
		var best := -1
		var best_d := -1.0
		for index in work:
			var already := false
			for taken in out:
				if taken == index:
					already = true
					break
			if already:
				continue
			var nearest := _spread_span(_dirs[index], out, avoid)
			if nearest > best_d:
				best_d = nearest
				best = index
		if best < 0 or best_d < min_sep:
			break
		out.append(best)
	return out


func _spread_span(dir: Vector3, taken: PackedInt32Array, avoid: Array) -> float:
	var nearest := INF
	for index in taken:
		nearest = minf(nearest, _metres(dir, _dirs[index]))
	for other: Variant in avoid:
		if other is Vector3:
			nearest = minf(nearest, _metres(dir, other))
	return nearest


func _filtered(pool: PackedInt32Array, keep: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	for index in pool:
		if keep.call(_dirs[index]):
			out.append(index)
	return out


func _add_city(id: String, ring: int, direction: Vector3) -> void:
	var site := _point(direction, id, ring)
	site["stores"] = _stores_for(_cities.size())
	_cities.append(site)


func _add_castle(id: String, city_id: String, ring: int, direction: Vector3) -> void:
	var pads := _pads_around(
		direction, id, city_id, "castle_id", GOBLIN_KINDS,
		GOBLINS_PER_CASTLE, GOBLIN_INNER, GOBLIN_OUTER)
	var site := _point(direction, id, ring)
	site["city_id"] = city_id
	site["goblin_count"] = pads.size()
	_castles.append(site)
	_goblins.append_array(pads)


func _add_boss(id: String, ring: int, direction: Vector3) -> void:
	var site := _point(direction, id, ring)
	site["radius_m"] = BOSS_RADIUS
	site["empty"] = true
	site["encounter"] = BOSS_ENCOUNTER_EMPTY
	_bosses.append(site)


func _add_office(id: String, city_id: String, ring: int, direction: Vector3) -> void:
	var pads := _pads_around(
		direction, id, city_id, "office_id", SHRIMP_KINDS,
		SHRIMPS_PER_OFFICE, SHRIMP_INNER, SHRIMP_OUTER)
	var site := _point(direction, id, ring)
	site["city_id"] = city_id
	site["shrimp_count"] = pads.size()
	_offices.append(site)
	_shrimps.append_array(pads)


func _pads_around(
		center: Vector3,
		site_id: String,
		city_id: String,
		owner_key: String,
		kinds: Array,
		count: int,
		min_m: float,
		max_m: float
	) -> Array:
	var east := _frame(center)[0]
	var out: Array = []
	for index in count:
		var share := float(index) / float(maxi(count - 1, 1))
		var reach := lerpf(min_m, max_m, share)
		var tangent := east.rotated(center, GOLDEN * float(index))
		var at := _move(center, tangent, reach)
		if not _site_ok(at, false):
			var snapped := _keep_land(at, 36.0)
			if snapped != Vector3.ZERO:
				at = snapped
		var pad := {
			"id": "%s_%d" % [site_id, index + 1],
			"city_id": city_id,
			"kind": String(kinds[index % kinds.size()]),
			"lat": _latitude(at),
			"lon": _longitude(at),
			"direction": _vec(at),
		}
		pad[owner_key] = site_id
		out.append(pad)
	return out


func _stores_for(city_index: int) -> PackedStringArray:
	if city_index <= 0:
		return PackedStringArray(SHOP_IDS)
	var open := PackedStringArray()
	for id: String in SHOP_ALWAYS:
		open.append(id)
	var pool: Array[String] = []
	for id: String in SHOP_OPTIONAL:
		pool.append(id)
	for step in range(pool.size() - 1, 0, -1):
		var swap_at := _rng.randi_range(0, step)
		var held := pool[step]
		pool[step] = pool[swap_at]
		pool[swap_at] = held
	var extra := _rng.randi_range(3, 4)
	for id: String in pool:
		if open.size() >= SHOP_ALWAYS.size() + extra:
			break
		if not open.has(id):
			open.append(id)
	return open


func _point(direction: Vector3, id: String, ring: int) -> Dictionary:
	return {
		"id": id,
		"ring": ring if ring > 0 else _ring_of(direction),
		"lat": _latitude(direction),
		"lon": _longitude(direction),
		"direction": _vec(direction),
	}


func _ring_entry(id: int, inner: float, outer: float) -> Dictionary:
	return {
		"id": id,
		"name": "ring%d" % id,
		"inner_m": inner,
		"outer_m": outer,
		"width_m": outer - inner,
		"clip_lat_deg": LAT_LIMIT,
	}


func _site_ok(direction: Vector3, need_flat: bool) -> bool:
	if not _in_belt(direction):
		return false
	if _shape.frost(direction) > 0.0:
		return false
	if _shape.elevation(direction) < DRY:
		return false
	if need_flat and _slope_deg(direction) > SITE_SLOPE_DEG + 4.0:
		return false
	return true


func _in_belt(direction: Vector3) -> bool:
	return absf(_latitude(direction)) <= LAT_LIMIT


func _in_ring(direction: Vector3, ring_id: int) -> bool:
	if not _in_belt(direction):
		return false
	var span := _metres(_center, direction)
	for ring: Dictionary in _rings:
		if int(ring["id"]) != ring_id:
			continue
		return span >= float(ring["inner_m"]) - 1.0 \
			and span <= float(ring["outer_m"]) + 1.0
	return false


func _ring_of(direction: Vector3) -> int:
	if not _in_belt(direction):
		return 0
	var span := _metres(_center, direction)
	for ring: Dictionary in _rings:
		if span <= float(ring["outer_m"]) + 1.0:
			return int(ring["id"])
	if not _rings.is_empty():
		return int(_rings[_rings.size() - 1]["id"])
	return 1


func _belt_cover_m() -> float:
	var farthest := _clamp_lat(-_center, LAT_LIMIT)
	return maxf(_metres(_center, farthest), _radius * PI * 0.5)


func _slope_deg(direction: Vector3) -> float:
	var frame := _frame(direction)
	var mid := _shape.elevation(direction)
	var worst := 0.0
	var step := 28.0
	for axis in 4:
		var tangent := frame[0] if axis % 2 == 0 else frame[1]
		if axis >= 2:
			tangent = -tangent
		var height := _shape.elevation(_move(direction, tangent, step))
		worst = maxf(worst, absf(height - mid) / step)
	return rad_to_deg(atan(worst))


func _keep_land(from: Vector3, max_m: float) -> Vector3:
	if from == Vector3.ZERO:
		return Vector3.ZERO
	if _site_ok(from, true):
		return from
	var best := Vector3.ZERO
	var best_d := max_m + 1.0
	for index in _dirs.size():
		var span := _metres(from, _dirs[index])
		if span < best_d:
			best_d = span
			best = _dirs[index]
	return best if best_d <= max_m else Vector3.ZERO


func _nudge_from(origin: Vector3, at: Vector3, min_m: float) -> Vector3:
	if _metres(origin, at) >= min_m:
		return at
	var now := _move(at, _away_tangent(at, origin), min_m - _metres(origin, at) + 20.0)
	var snapped := _keep_land(now, 80.0)
	return snapped if snapped != Vector3.ZERO else now


func _pad_near(from: Vector3, tangent: Vector3, metres: float) -> Vector3:
	var at := _move(from, tangent, metres)
	var snapped := _keep_land(at, 24.0)
	return snapped if snapped != Vector3.ZERO else at


func _poisson(candidates: PackedVector3Array, min_m: float) -> PackedVector3Array:
	var cell := min_m
	var bins := {}
	var kept := PackedVector3Array()
	var order: Array[int] = []
	for index in candidates.size():
		order.append(index)
	_shuffle_ints(order)
	for slot in order:
		var direction: Vector3 = candidates[slot]
		var key := _cell(direction, cell)
		var blocked := false
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					var other: Variant = bins.get(key + Vector3i(x, y, z), null)
					if other == null:
						continue
					for taken: Vector3 in other:
						if _metres(direction, taken) < min_m:
							blocked = true
							break
					if blocked:
						break
				if blocked:
					break
			if blocked:
				break
		if blocked:
			continue
		if not bins.has(key):
			bins[key] = []
		bins[key].append(direction)
		kept.append(direction)
	return kept


func _cell(direction: Vector3, cell_m: float) -> Vector3i:
	var at := direction * _radius
	var s := maxf(cell_m, 1.0)
	return Vector3i(
		int(floor(at.x / s)),
		int(floor(at.y / s)),
		int(floor(at.z / s)))


func _pair(a: Vector3, b: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.append(a)
	out.append(b)
	return out


func _city_dir(id: String) -> Vector3:
	for city: Dictionary in _cities:
		if String(city["id"]) == id:
			return _from_vec(city["direction"])
	return _spawn


func _site_dirs() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for castle: Dictionary in _castles:
		out.append(_from_vec(castle["direction"]))
	for office: Dictionary in _offices:
		out.append(_from_vec(office["direction"]))
	return out


func _occupied_dirs() -> Array[Vector3]:
	var out: Array[Vector3] = [_spawn]
	for city: Dictionary in _cities:
		out.append(_from_vec(city["direction"]))
	out.append_array(_site_dirs())
	return out


func _boss_dirs() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for boss: Dictionary in _bosses:
		out.append(_from_vec(boss["direction"]))
	return out


func _from_vec(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0)))
	return Vector3.ZERO


func _mean_dir(dirs: Array[Vector3]) -> Vector3:
	var sum := Vector3.ZERO
	for at: Vector3 in dirs:
		sum += at
	if sum.length_squared() < 1e-8:
		return _spawn
	return sum.normalized()


func _metres(a: Vector3, b: Vector3) -> float:
	return a.angle_to(b) * _radius


func _latitude(direction: Vector3) -> float:
	return rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))


func _longitude(direction: Vector3) -> float:
	return rad_to_deg(atan2(direction.x, direction.z))


func _direction_from_plate(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var east := cos(lat)
	return Vector3(east * sin(lon), sin(lat), east * cos(lon)).normalized()


func _clamp_lat(direction: Vector3, limit_deg: float) -> Vector3:
	var lat := _latitude(direction)
	if absf(lat) <= limit_deg:
		return direction.normalized()
	return _direction_from_plate(
		limit_deg * signf(lat if lat != 0.0 else 1.0),
		_longitude(direction))


func _frame(up: Vector3) -> Array[Vector3]:
	var hint := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var forward := (hint - up * hint.dot(up)).normalized()
	return [up.cross(forward), -forward]


func _move(up: Vector3, tangent: Vector3, metres: float) -> Vector3:
	var side := tangent - up * tangent.dot(up)
	if side.length_squared() < 1e-10:
		side = _frame(up)[0]
	else:
		side = side.normalized()
	var arc := metres / maxf(_radius, 1.0)
	return (up * cos(arc) + side * sin(arc)).normalized()


func _away_tangent(from: Vector3, avoid: Vector3) -> Vector3:
	var chord := from - avoid
	var tangent := chord - from * chord.dot(from)
	if tangent.length_squared() < 1e-10:
		return _frame(from)[0]
	return tangent.normalized()


func _vec(direction: Vector3) -> Dictionary:
	return {"x": direction.x, "y": direction.y, "z": direction.z}


func _shuffle_packed(values: PackedInt32Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := _rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap]
		values[swap] = held


func _shuffle_ints(values: Array[int]) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap := _rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap]
		values[swap] = held


func _secs(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000000.0


func _warn(text: String) -> void:
	_warnings.append(text)


func _flags() -> Dictionary:
	var found := {}
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=")
		if pair.size() != 2:
			continue
		found[pair[0]] = pair[1].to_float() if pair[1].is_valid_float() else pair[1]
	return found
