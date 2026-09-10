class_name CrawlerRun
extends RefCounted

## One randomised crawler layout from `assets/runtime/crawler/runs`.
## The live session picks a file at start; sites, shops, and patch packs
## read from that payload instead of the authored Tide Margin map.

const RUNS_DIR := "res://assets/runtime/crawler/runs"
const FIRST_CITY_ID := "city1"

static var path := ""
static var payload: Dictionary = {}
static var _patches_by_name: Dictionary = {}
static var _city_by_id: Dictionary = {}


static func active() -> bool:
	return not payload.is_empty()


static func clear() -> void:
	path = ""
	payload = {}
	_patches_by_name.clear()
	_city_by_id.clear()


static func pick_random(forced := "") -> bool:
	if not forced.is_empty():
		return load_path(forced)
	var files := list_runs()
	if files.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return load_path(files[rng.randi_range(0, files.size() - 1)])


static func ensure_session() -> bool:
	if active():
		return true
	var held := ""
	if NetworkManager != null:
		held = str(NetworkManager.session_options.get("crawler_run", ""))
	if not held.is_empty() and load_path(held):
		return true
	return pick_random()


static func list_runs() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(RUNS_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.ends_with(".json"):
			found.append("%s/%s" % [RUNS_DIR, name])
		name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


static func load_path(next_path: String) -> bool:
	var text := FileAccess.get_file_as_string(next_path)
	if text.is_empty():
		push_warning("CrawlerRun: empty %s" % next_path)
		return false
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("CrawlerRun: could not parse %s" % next_path)
		return false
	clear()
	path = next_path
	payload = parsed
	_index()
	if NetworkManager != null:
		NetworkManager.session_options["crawler_run"] = next_path
	return true


static func spawn_direction() -> Vector3:
	return _dir_of(payload.get("spawn", {}))


static func city_direction() -> Vector3:
	return _dir_of(city_entry(FIRST_CITY_ID))


static func first_city_id() -> String:
	return FIRST_CITY_ID


static func city_entry(id: String) -> Dictionary:
	var row: Variant = _city_by_id.get(id, {})
	return row if row is Dictionary else {}


static func cities() -> Array:
	var listed: Variant = payload.get("cities", [])
	return listed if listed is Array else []


static func castles() -> Array:
	var listed: Variant = payload.get("castles", [])
	return listed if listed is Array else []


static func offices() -> Array:
	var listed: Variant = payload.get("offices", [])
	return listed if listed is Array else []


static func bosses() -> Array:
	var listed: Variant = payload.get("bosses", [])
	return listed if listed is Array else []


static func boss_entry(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	for raw: Variant in bosses():
		if raw is Dictionary and str(raw.get("id", "")) == id:
			return raw
	return {}


static func boss_encounter(id: String) -> String:
	var row := boss_entry(id)
	if row.is_empty():
		return ""
	var encounter := str(row.get("encounter", ""))
	if encounter.is_empty():
		return CrawlerRules.BOSS_ENCOUNTER_EMPTY \
			if bool(row.get("empty", true)) \
			else ""
	return encounter


static func is_tree_boss(id: String) -> bool:
	return boss_encounter(id) == CrawlerRules.BOSS_ENCOUNTER_TREE


static func rings() -> Array:
	var listed: Variant = payload.get("rings", [])
	return listed if listed is Array else []


static func last_ring() -> int:
	var last := 1
	for listed: Array in [cities(), castles(), offices(), bosses()]:
		for raw: Variant in listed:
			if raw is Dictionary:
				last = maxi(last, int(raw.get("ring", 1)))
	for raw: Variant in rings():
		if raw is Dictionary:
			last = maxi(last, int(raw.get("id", raw.get("ring", 1))))
	return last


static func shops_for(city_key: String) -> PackedStringArray:
	var id := _city_id_from_key(city_key)
	var row := city_entry(id)
	var listed: Variant = row.get("stores", [])
	var out := PackedStringArray()
	if listed is Array:
		for raw: Variant in listed:
			var shop := str(raw)
			if not shop.is_empty() and not out.has(shop):
				out.append(shop)
	return out


static func combo_for_patch(patch_name: String) -> String:
	var row := _patch_row(patch_name)
	var combo := str(row.get("combo", ""))
	return combo if not combo.is_empty() else "wild"


static func kinds_for_patch(patch_name: String) -> PackedStringArray:
	var row := _patch_row(patch_name)
	var listed: Variant = row.get("kinds", [])
	var out := PackedStringArray()
	if listed is Array:
		for raw: Variant in listed:
			var kind := str(raw)
			if not kind.is_empty():
				out.append(kind)
	return out


static func level_for_patch(patch_name: String) -> int:
	var row := _patch_row(patch_name)
	return maxi(int(row.get("level", 1)), 1)


static func level_at_dir(direction: Vector3) -> int:
	var row := _nearest_patch(direction)
	return maxi(int(row.get("level", 1)), 1)


static func ring_of_dir(direction: Vector3) -> int:
	if direction.length_squared() < 0.0001:
		return 0
	var center := ring_center()
	var span := direction.normalized().angle_to(center) * radius()
	var last := 1
	for ring: Variant in rings():
		if not ring is Dictionary:
			continue
		last = int(ring.get("id", last))
		if span <= float(ring.get("outer_m", 0.0)) + 1.0:
			return last
	return last


static func ring_of_world(at: Vector3) -> int:
	return ring_of_dir(at.normalized()) if at.length_squared() > 0.0001 else 0


static func ring_of_city(id: String) -> int:
	return maxi(int(city_entry(id).get("ring", 1)), 1)


static func ring_center() -> Vector3:
	var at := _dir_of(payload.get("ring_center", {}))
	return at if at.length_squared() > 0.25 else spawn_direction()


static func radius() -> float:
	return maxf(float(payload.get("radius_m", 8000.0)), 1.0)


static func is_start_patch(patch_name: String) -> bool:
	var row := _patch_row(patch_name)
	if row.is_empty():
		return false
	var spawn := spawn_direction()
	var facing := _dir_of(row)
	if facing.length_squared() < 0.25:
		return false
	return spawn.angle_to(facing) * radius() <= 220.0


static func goblin_pads_for(castle_id: String) -> Array:
	return _pads_for("goblin_spawns", "castle_id", castle_id)


static func shrimp_pads_for(office_id: String) -> Array:
	return _pads_for("shrimp_spawns", "office_id", office_id)


static func later_city_ids() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("city2")
	out.append("city3")
	return out


static func _index() -> void:
	_promote_alien_field()
	_patches_by_name.clear()
	_city_by_id.clear()
	for raw: Variant in cities():
		if raw is Dictionary:
			_city_by_id[str(raw.get("id", ""))] = raw
	for raw: Variant in payload.get("patches", []):
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		var name := str(row.get("name", ""))
		if not name.is_empty():
			_patches_by_name[name] = row
		var recipe := str(row.get("recipe", ""))
		if not recipe.is_empty() and not _patches_by_name.has(recipe):
			_patches_by_name[recipe] = row


static func _promote_alien_field() -> void:
	var listed: Variant = payload.get("patches", [])
	if not listed is Array:
		return
	var kinds: Array = ["scout", "gray", "tanglemaw"]
	var spawn := spawn_direction()
	var rad := radius()
	for raw: Variant in listed:
		if not raw is Dictionary:
			continue
		var row: Dictionary = raw
		if str(row.get("combo", "")) != "wild":
			continue
		var facing := _dir_of(row)
		if spawn.length_squared() > 0.25 and facing.length_squared() > 0.25 \
				and spawn.angle_to(facing) * rad <= 220.0:
			continue
		var key := str(row.get("id", row.get("name", "")))
		if key.is_empty() or hash(key) % 3 != 0:
			continue
		row["combo"] = "alien"
		row["pack"] = "aliens"
		row["kinds"] = kinds


static func _patch_row(patch_name: String) -> Dictionary:
	var clean := patch_name.strip_edges()
	if clean.is_empty():
		return {}
	var exact: Variant = _patches_by_name.get(clean, null)
	if exact is Dictionary:
		return exact
	for name: String in _patches_by_name.keys():
		if clean.begins_with(name + " ") or name.begins_with(clean + " "):
			var row: Variant = _patches_by_name[name]
			if row is Dictionary:
				return row
	return {}


static func _nearest_patch(direction: Vector3) -> Dictionary:
	if direction.length_squared() < 0.0001:
		return {}
	var want := direction.normalized()
	var best: Dictionary = {}
	var best_dot := -2.0
	var listed: Variant = payload.get("patches", [])
	if not listed is Array:
		return best
	for raw: Variant in listed:
		if not raw is Dictionary:
			continue
		var facing := _dir_of(raw)
		if facing.length_squared() < 0.25:
			continue
		var hit := want.dot(facing.normalized())
		if hit > best_dot:
			best_dot = hit
			best = raw
	return best


static func _pads_for(key: String, owner_key: String, owner_id: String) -> Array:
	var out: Array = []
	var listed: Variant = payload.get(key, [])
	if not listed is Array:
		return out
	for raw: Variant in listed:
		if raw is Dictionary and str(raw.get(owner_key, "")) == owner_id:
			out.append(raw)
	return out


static func _city_id_from_key(city_key: String) -> String:
	var clean := city_key.strip_edges()
	if _city_by_id.has(clean):
		return clean
	if clean == "city" or clean.is_empty():
		return FIRST_CITY_ID
	for raw: Variant in cities():
		if raw is Dictionary and str(raw.get("id", "")) == clean:
			return clean
	return clean


static func _dir_of(row: Variant) -> Vector3:
	if not row is Dictionary:
		return Vector3.ZERO
	var held: Variant = (row as Dictionary).get("direction", {})
	if held is Dictionary:
		return Vector3(
			float(held.get("x", 0.0)),
			float(held.get("y", 0.0)),
			float(held.get("z", 0.0)))
	return Vector3.ZERO
