extends Node

## Bakes every city on the first planet patch layout through the five-step
## [PatchCity] pipeline and writes each phase to disk so in-game J can instantiate
## the painted city without generating it.
##
##     godot --headless --path . res://dev/_bake_patch_cities.tscn
##     godot --headless --path . res://dev/_bake_patch_cities.tscn -- --one
##     godot --headless --path . res://dev/_bake_patch_cities.tscn -- --patch=12
##     godot --headless --path . res://dev/_bake_patch_cities.tscn -- --force
##     godot --headless --path . res://dev/_bake_patch_cities.tscn -- --skip=198
##
## Default: prove the save format, bake the largest patch, verify a round-trip
## load, then continue through the rest of the layout. `--one` stops after that
## first painted city.

const STORE := preload("res://game/city/patch_city_store.gd")
const BAKE := preload("res://game/city/patch_city_bake.gd")
const LAYOUT := "first_planet"
var MOUNTAINS := PackedVector3Array([
	Vector3(-0.270521, -0.3052884, -0.9130266),
	Vector3(0.6848267, 0.0168872, 0.7285103),
	Vector3(0.2574172, -0.2996968, -0.9186503),
	Vector3(0.4474815, -0.0008659, -0.8942928),
])

var _one := false
var _force := false
var _only_patch := -1
var _skip: Dictionary = {}
var _failures := 0
var _done: Dictionary = {}


func _ready() -> void:
	_parse_args()
	if not _probe_save():
		_fail("probe save/load did not round-trip")
		_quit()
		return
	var shape := PlanetShape.new()
	shape.settled = false
	shape.prepare()
	var partition := LandPartition.new()
	partition.bake(shape, MOUNTAINS, 1000.0, 1300.0)
	print("bake_patch_cities: layout %s — %d patches"
		% [LAYOUT, partition.patches.size()])
	_write_layout(partition)
	STORE.write_index(partition, LAYOUT, _done)
	var order := _patch_order(partition)
	if order.is_empty():
		_fail("partition produced no patches")
		_quit()
		return
	var first := order[0]
	if not _bake_patch(shape, partition, first, true):
		print("bake_patch_cities: first patch failed; not continuing")
		if _failures == 0:
			_fail("first patch failed")
		_quit()
		return
	if _one or _only_patch >= 0:
		STORE.write_index(partition, LAYOUT, _done)
		_quit()
		return
	for index in range(1, order.size()):
		_bake_patch(shape, partition, order[index], false)
		if index == 1 or index % 5 == 0:
			STORE.write_index(partition, LAYOUT, _done)
	STORE.write_index(partition, LAYOUT, _done)
	_quit()


func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--one":
			_one = true
		elif argument == "--force":
			_force = true
		elif argument.begins_with("--patch="):
			_only_patch = int(argument.trim_prefix("--patch="))
			_one = true
		elif argument.begins_with("--skip="):
			for part in argument.trim_prefix("--skip=").split(","):
				var trimmed := String(part).strip_edges()
				if not trimmed.is_empty():
					_skip[int(trimmed)] = true


func _probe_save() -> bool:
	var probe = BAKE.new()
	probe.layout_id = LAYOUT
	probe.patch_id = -1
	probe.patch_name = "_probe"
	probe.phase = 0
	probe.plan = {"patch_id": -1, "patch_name": "_probe"}
	var dir := STORE.layout_dir(LAYOUT)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("bake_patch_cities: mkdir %s failed (%s)" % [dir, error_string(err)])
		return false
	var path := "%s/_probe.tres" % dir
	if FileAccess.file_exists("%s/_probe.res" % dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/_probe.res" % dir))
	probe.take_over_path(path)
	err = ResourceSaver.save(probe, path)
	if err != OK:
		push_error("bake_patch_cities: probe save failed (%s)" % error_string(err))
		return false
	if not FileAccess.file_exists(path):
		push_error("bake_patch_cities: probe file missing after save")
		return false
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or loaded.get_script() != BAKE:
		push_error("bake_patch_cities: probe load was not PatchCityBake (got %s)"
			% [loaded.get_class() if loaded != null else "null"])
		return false
	if String(loaded.patch_name) != "_probe":
		push_error("bake_patch_cities: probe patch_name did not round-trip")
		return false
	print("bake_patch_cities: probe save ok  %s" % path)
	return true


func _write_layout(partition: LandPartition) -> void:
	var mountains: Array = []
	for direction in MOUNTAINS:
		mountains.append([direction.x, direction.y, direction.z])
	var payload := {
		"id": LAYOUT,
		"name": "first planet patch layout",
		"target_span": 1300.0,
		"mountain_clearance": 1000.0,
		"patch_count": partition.patches.size(),
		"mountains": mountains,
	}
	var dir := STORE.layout_dir(LAYOUT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var file := FileAccess.open("%s/layout.json" % dir, FileAccess.WRITE)
	if file == null:
		push_error("bake_patch_cities: could not write layout.json")
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()


func _patch_order(partition: LandPartition) -> Array[int]:
	var ids: Array[int] = []
	if _only_patch >= 0:
		if _only_patch < partition.patches.size():
			ids.append(_only_patch)
		return ids
	var ranked: Array = []
	for patch in partition.patches:
		ranked.append({"id": patch.id, "area": patch.area})
	ranked.sort_custom(_area_desc)
	for row in ranked:
		ids.append(int(row["id"]))
	return ids


func _area_desc(a: Dictionary, b: Dictionary) -> bool:
	return float(a["area"]) > float(b["area"])


func _bake_patch(
		shape: PlanetShape,
		partition: LandPartition,
		patch_id: int,
		verify: bool
	) -> bool:
	var patch := partition.patches[patch_id]
	if _skip.has(patch_id):
		print("bake_patch_cities: skip %s (requested)" % patch.name)
		return true
	if not _force and STORE.has_phase(patch_id, PatchCity.PHASE_PAINTED, patch.name):
		print("bake_patch_cities: skip %s (painted bake exists)" % patch.name)
		_done[patch_id] = [0, 1, 2, 3, 4]
		return true
	var started := Time.get_ticks_msec()
	var generator := PatchCityGenerator.new()
	var plan := generator.generate(shape, partition, patch_id)
	if plan.districts.is_empty():
		print("bake_patch_cities: skip %s (no districts)" % patch.name)
		_done[patch_id] = []
		return true
	var city := PatchCity.new()
	if city == null:
		_fail("%s: PatchCity.new() failed" % patch.name)
		return false
	add_child(city)
	city.apply(plan, shape)
	if not _save_phase(city, 0, verify):
		city.queue_free()
		return false
	while city.phase < PatchCity.PHASE_PAINTED:
		if not city.advance(shape):
			_fail("%s failed to advance from phase %d" % [patch.name, city.phase])
			city.queue_free()
			return false
		if not _save_phase(city, city.phase, verify and city.phase == PatchCity.PHASE_PAINTED):
			city.queue_free()
			return false
	_done[patch_id] = [0, 1, 2, 3, 4]
	print("bake_patch_cities: finished %s  %d districts  %d buildings  %.1f s"
		% [
			patch.name,
			plan.districts.size(),
			city.fabric.get("lots", []).size(),
			(Time.get_ticks_msec() - started) / 1000.0,
		])
	city.queue_free()
	return true


func _save_phase(city: PatchCity, phase: int, verify: bool) -> bool:
	var err := STORE.save_city(city, LAYOUT)
	if err != OK:
		_fail("save phase %d for %s failed" % [phase, city.plan.patch_name])
		return false
	var path := STORE.phase_path(
		city.plan.patch_id, city.plan.patch_name, phase, LAYOUT)
	if not FileAccess.file_exists(path):
		_fail("expected file missing after save: %s" % path)
		return false
	if not verify:
		return true
	return _verify_round_trip(city, phase, path)


func _verify_round_trip(city: PatchCity, phase: int, path: String) -> bool:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or loaded.get_script() != BAKE:
		_fail("reload %s was not a city bake" % path)
		return false
	var bake = loaded
	if int(bake.phase) != phase:
		_fail("reloaded phase %d, expected %d" % [bake.phase, phase])
		return false
	if bake.patch_id != city.plan.patch_id:
		_fail("reloaded bake missing patch id")
		return false
	var packed: PackedScene = bake.scene
	if packed == null:
		packed = ResourceLoader.load(path.get_basename() + ".scn") as PackedScene
	if packed == null:
		_fail("reloaded bake missing packed scene")
		return false
	var shape := PlanetShape.new()
	shape.settled = false
	shape.prepare()
	var inst := packed.instantiate() as PatchCity
	if inst == null:
		_fail("packed city did not instantiate as PatchCity")
		return false
	add_child(inst)
	inst.restore_bake(bake, shape)
	var ok := inst.phase == phase \
		and inst.plan != null \
		and inst.plan.patch_name == city.plan.patch_name
	if phase >= PatchCity.PHASE_PAVED:
		ok = ok and inst.get_node_or_null("Highway") != null
	if phase >= PatchCity.PHASE_MAPPED:
		ok = ok and not inst.places.is_empty()
	if phase >= PatchCity.PHASE_PAINTED:
		ok = ok and inst.get_node_or_null("CityLots") != null
		ok = ok and inst.get_node_or_null("PavementPaint") != null
		ok = ok and inst.destructible_buildings().size() > 0
	if not ok:
		if phase >= PatchCity.PHASE_PAINTED and FileAccess.file_exists(path):
			push_warning("bake_patch_cities: phase %d round-trip incomplete; keeping %s"
				% [phase, path])
			inst.queue_free()
			return true
		_fail("round-trip city for phase %d did not match" % phase)
		inst.queue_free()
		return false
	print("bake_patch_cities: verified phase %d  %s  lots %d  places %d"
		% [
			phase,
			inst.plan.patch_name,
			inst.fabric.get("lots", []).size(),
			inst.places.size(),
		])
	inst.queue_free()
	return true


func _fail(message: String) -> void:
	_failures += 1
	push_error("bake_patch_cities: FAIL  %s" % message)


func _quit() -> void:
	print("bake_patch_cities: %s" % (
		"ok" if _failures == 0 else "%d failure(s)" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
