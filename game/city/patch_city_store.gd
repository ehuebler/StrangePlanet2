class_name PatchCityStore
extends RefCounted

## On-disk layout for baked [PatchCity] phases. Files live under
## `res://assets/runtime/cities/<layout>/` and are loaded with [method ResourceLoader.load]
## at the moment they are needed — never preloaded.

const BAKE := preload("res://game/city/patch_city_bake.gd")
const LAYOUT_FIRST_PLANET := "first_planet"
const ROOT := "res://assets/runtime/cities"
const SAVE_FLAGS := ResourceSaver.FLAG_COMPRESS


static func layout_dir(layout_id := LAYOUT_FIRST_PLANET) -> String:
	return "%s/%s" % [ROOT, layout_id]


static func patch_dir(patch_id: int, patch_name: String, layout_id := LAYOUT_FIRST_PLANET) -> String:
	return "%s/p%03d_%s" % [layout_dir(layout_id), patch_id, _slug(patch_name)]


static func phase_path(
		patch_id: int,
		patch_name: String,
		phase: int,
		layout_id := LAYOUT_FIRST_PLANET
	) -> String:
	var file: String = "4_painted.res"
	if phase >= 0 and phase < BAKE.PHASE_FILE.size():
		file = String(BAKE.PHASE_FILE[phase])
	return "%s/%s" % [patch_dir(patch_id, patch_name, layout_id), file]


static func index_path(layout_id := LAYOUT_FIRST_PLANET) -> String:
	return "%s/index.json" % layout_dir(layout_id)


static func has_phase(
		patch_id: int,
		phase: int,
		patch_name := "",
		layout_id := LAYOUT_FIRST_PLANET
	) -> bool:
	var path := _resolve_phase_path(patch_id, phase, patch_name, layout_id)
	return _on_disk(path)


static func has_painted(patch_id: int, layout_id := LAYOUT_FIRST_PLANET) -> bool:
	return has_phase(patch_id, PatchCity.PHASE_PAINTED, "", layout_id)


static func save_city(
		city: PatchCity,
		layout_id := LAYOUT_FIRST_PLANET
	) -> Error:
	if city == null or city.plan == null:
		return ERR_INVALID_PARAMETER
	var bake := city.capture_bake(layout_id)
	if bake == null:
		return ERR_CANT_CREATE
	var dir := patch_dir(city.plan.patch_id, city.plan.patch_name, layout_id)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("patch_city_store: mkdir %s failed (%s)" % [dir, error_string(err)])
		return err
	var path := phase_path(city.plan.patch_id, city.plan.patch_name, city.phase, layout_id)
	var scene_path := path.get_basename() + ".scn"
	if bake.scene != null:
		bake.scene.take_over_path(scene_path)
		err = ResourceSaver.save(bake.scene, scene_path, SAVE_FLAGS)
		if err != OK:
			push_error("patch_city_store: save %s failed (%s)"
				% [scene_path, error_string(err)])
			return err
		bake.scene = ResourceLoader.load(scene_path)
	bake.take_over_path(path)
	err = ResourceSaver.save(bake, path)
	if err != OK:
		push_error("patch_city_store: save %s failed (%s)" % [path, error_string(err)])
		return err
	return OK


static func load_bake(
		patch_id: int,
		phase: int,
		patch_name := "",
		layout_id := LAYOUT_FIRST_PLANET,
		cache_mode := ResourceLoader.CACHE_MODE_REUSE
	) -> Resource:
	return _load_resource(
		_resolve_phase_path(patch_id, phase, patch_name, layout_id), cache_mode)


static func instantiate_phase(
		patch_id: int,
		phase: int,
		shape: PlanetShape,
		patch_name := "",
		layout_id := LAYOUT_FIRST_PLANET,
		parent: Node = null
	) -> PatchCity:
	var bake := load_bake(patch_id, phase, patch_name, layout_id)
	if bake == null:
		return null
	var packed: PackedScene = bake.scene
	if packed == null:
		var res_path := _resolve_phase_path(patch_id, phase, patch_name, layout_id)
		if not res_path.is_empty():
			packed = _load_resource(res_path.get_basename() + ".scn") as PackedScene
	if packed == null:
		return null
	var city := packed.instantiate() as PatchCity
	if city == null:
		return null
	if parent != null:
		parent.add_child(city)
	city.restore_bake(bake, shape)
	return city


static func write_index(
		partition: LandPartition,
		layout_id := LAYOUT_FIRST_PLANET,
		done: Dictionary = {}
	) -> Error:
	var patches: Array = []
	if partition != null:
		for patch in partition.patches:
			var row := {
				"id": patch.id,
				"name": patch.name,
				"span": patch.span,
				"area": patch.area,
				"phases": [],
			}
			var listed: Variant = done.get(patch.id, null)
			if listed is Array:
				row["phases"] = listed
			else:
				for phase in BAKE.PHASE_FILE.size():
					if has_phase(patch.id, phase, patch.name, layout_id):
						(row["phases"] as Array).append(phase)
			patches.append(row)
	var payload := {
		"layout": layout_id,
		"patch_count": patches.size(),
		"patches": patches,
	}
	var dir := layout_dir(layout_id)
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var file := FileAccess.open(index_path(layout_id), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


static func pack_tree(root: Node) -> PackedScene:
	if root == null:
		return null
	_own_tree(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("patch_city_store: pack failed (%s)" % error_string(err))
		return null
	return packed


static func _own_tree(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_tree(child, owner)


static func _slug(name: String) -> String:
	var out := ""
	for index in name.length():
		var ch := name.unicode_at(index)
		if (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57):
			out += char(ch)
		elif ch >= 65 and ch <= 90:
			out += char(ch + 32)
		elif ch == 32 or ch == 45 or ch == 95:
			if not out.ends_with("_"):
				out += "_"
	return out.trim_suffix("_") if not out.is_empty() else "patch"


static func _on_disk(path: String) -> bool:
	if path.is_empty():
		return false
	if FileAccess.file_exists(path) or ResourceLoader.exists(path):
		return true
	var abs := ProjectSettings.globalize_path(path)
	return abs != path and FileAccess.file_exists(abs)


static func _load_resource(
		path: String,
		cache_mode := ResourceLoader.CACHE_MODE_REUSE
	) -> Resource:
	if path.is_empty():
		return null
	var loaded := ResourceLoader.load(path, "", cache_mode)
	if loaded != null:
		return loaded
	var abs := ProjectSettings.globalize_path(path)
	if abs != path and FileAccess.file_exists(abs):
		return ResourceLoader.load(abs, "", cache_mode)
	return null


static func _resolve_phase_path(
		patch_id: int,
		phase: int,
		patch_name: String,
		layout_id: String
	) -> String:
	if not patch_name.is_empty():
		var named := phase_path(patch_id, patch_name, phase, layout_id)
		if _on_disk(named):
			return named
	var parent := ProjectSettings.globalize_path(layout_dir(layout_id))
	if not DirAccess.dir_exists_absolute(parent):
		return ""
	var prefix := "p%03d_" % patch_id
	var dir := DirAccess.open(parent)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir() and entry.begins_with(prefix):
			var file: String = "4_painted.res"
			if phase >= 0 and phase < BAKE.PHASE_FILE.size():
				file = String(BAKE.PHASE_FILE[phase])
			var path := "%s/%s/%s" % [layout_dir(layout_id), entry, file]
			dir.list_dir_end()
			return path if _on_disk(path) else ""
		entry = dir.get_next()
	dir.list_dir_end()
	return ""
