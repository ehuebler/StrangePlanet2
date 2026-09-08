class_name YardBuildingCatalog
extends RefCounted

## Pregenerated MeshMaker buildings with yards: day, dusk, and night GLBs.

const MANIFEST_PATH := "res://assets/runtime/cities/yard_kit/manifest.json"
const KIT_DIR := "res://assets/runtime/cities/yard_kit/"

const ARCH_HOUSE := "house"
const ARCH_ROW := "rowhouse"
const ARCH_APT := "low_apartment"
const ARCH_MID := "midrise"
const ARCH_HIGH := "highrise"

static var _assets: Dictionary = {}
static var _by_arch: Dictionary = {}
static var _templates: Dictionary = {}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_assets.clear()
	_by_arch.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var assets: Dictionary = (parsed as Dictionary).get("assets", {})
	for key in assets:
		if not assets[key] is Dictionary:
			continue
		var row: Dictionary = assets[key]
		var id := String(row.get("id", key))
		if not _files_ready(row):
			continue
		_assets[id] = row
		var arch := String(row.get("archetype", ARCH_HOUSE))
		var list: PackedStringArray = _by_arch.get(arch, PackedStringArray())
		if not list.has(id):
			list.append(id)
		_by_arch[arch] = list


static func _files_ready(row: Dictionary) -> bool:
	for key in PackedStringArray(["day", "dusk", "night"]):
		var rel := String(row.get(key, ""))
		if rel.is_empty():
			return false
		if not FileAccess.file_exists(KIT_DIR + rel) \
				and not FileAccess.file_exists(ProjectSettings.globalize_path(KIT_DIR + rel)):
			return false
	return true


static func has_design(name: String) -> bool:
	ensure()
	return not name.is_empty() and _assets.has(name)


static func info(name: String) -> Dictionary:
	ensure()
	return _assets.get(name, {})


static func count() -> int:
	ensure()
	return _assets.size()


static func archetype_for_typology(typology: int) -> String:
	match typology:
		PatchCity.TYPE_HOUSE:
			return ARCH_HOUSE
		PatchCity.TYPE_TOWNHOUSE:
			return ARCH_ROW
		PatchCity.TYPE_APARTMENT, PatchCity.TYPE_SHOP:
			return ARCH_APT
		PatchCity.TYPE_TOWER:
			return ARCH_MID
		_:
			return ARCH_HIGH


static func pick_for_lot(lot: Dictionary, salt: int) -> Dictionary:
	ensure()
	var arch := archetype_for_typology(int(lot.get("typology", 0)))
	var names: PackedStringArray = _by_arch.get(arch, PackedStringArray())
	if names.is_empty():
		for other in _by_arch:
			names = _by_arch[other]
			if not names.is_empty():
				break
	if names.is_empty():
		return {}
	var want_w := maxf(float(lot.get("width", 16.0)), 4.0)
	var want_d := maxf(float(lot.get("depth", 16.0)), 4.0)
	var ranked: Array = []
	for id in names:
		var row: Dictionary = _assets[id]
		var pw := maxf(float(row.get("plot_width_m", want_w)), 1.0)
		var pd := maxf(float(row.get("plot_depth_m", want_d)), 1.0)
		var fit := _fit(want_w, want_d, pw, pd)
		var fit_r := _fit(want_w, want_d, pd, pw)
		var rot90 := fit_r > fit
		ranked.append({
			"id": id,
			"score": maxf(fit, fit_r),
			"rot90": rot90,
		})
	ranked.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var pool: Array = []
	for item in ranked:
		if float(item["score"]) >= 0.55 and pool.size() < 12:
			pool.append(item)
	if pool.is_empty():
		pool.append(ranked[0])
	var centre: Vector2 = lot.get("centre", Vector2.ZERO)
	var pick: Dictionary = pool[absi(salt + int(centre.x * 3.0) + int(centre.y * 7.0)) % pool.size()]
	var chosen: Dictionary = _assets[String(pick["id"])].duplicate()
	chosen["yard_rot90"] = bool(pick["rot90"])
	return chosen


static func _fit(lot_w: float, lot_d: float, plot_w: float, plot_d: float) -> float:
	var sx := minf(lot_w / plot_w, plot_w / lot_w)
	var sz := minf(lot_d / plot_d, plot_d / lot_d)
	return minf(sx, sz)


static func instantiate(name: String, lighting: String) -> Node3D:
	ensure()
	if not _assets.has(name):
		return null
	var row: Dictionary = _assets[name]
	var rel := String(row.get(lighting, ""))
	if rel.is_empty():
		rel = String(row.get("day", ""))
	var key := "%s:%s" % [name, lighting]
	if not _templates.has(key):
		var loaded := _load_glb(KIT_DIR + rel)
		if loaded == null:
			return null
		loaded.visible = false
		_sanitize_template(loaded)
		_templates[key] = loaded
	return (_templates[key] as Node3D).duplicate() as Node3D


static func _load_glb(res_path: String) -> Node3D:
	if ResourceLoader.exists(res_path):
		var packed := load(res_path) as PackedScene
		if packed != null:
			return packed.instantiate() as Node3D
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(abs_path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


static func _sanitize_template(root: Node) -> void:
	var drop: Array = []
	_sanitize_node(root, drop)
	for node in drop:
		if not is_instance_valid(node):
			continue
		var parent := (node as Node).get_parent()
		if parent != null:
			parent.remove_child(node)
		(node as Node).free()


static func _sanitize_node(root: Node, drop: Array) -> void:
	if root is StaticBody3D or root is CollisionShape3D or root is Area3D \
			or root is Light3D:
		if root != null:
			drop.append(root)
		return
	if root is MeshInstance3D:
		_sanitize_mesh(root as MeshInstance3D)
	for child in root.get_children():
		_sanitize_node(child, drop)


static func _sanitize_mesh(mesh_i: MeshInstance3D) -> void:
	mesh_i.layers = PatchCity.BUILDING_VISUAL_LAYER
	mesh_i.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var name := String(mesh_i.name)
	if name.contains("Mass") or name.contains("Roof"):
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mesh := mesh_i.mesh
	if mesh == null:
		return
	for surf in mesh.get_surface_count():
		var mat := mesh_i.get_active_material(surf)
		_harden_material(mat)


static func _harden_material(mat: Material) -> void:
	if mat == null or not (mat is StandardMaterial3D):
		return
	var std := mat as StandardMaterial3D
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	std.refraction_enabled = false
	std.clearcoat_enabled = false
	std.rim_enabled = false
	std.anisotropy_enabled = false
	std.heightmap_enabled = false
	std.subsurf_scatter_enabled = false
	std.backlight_enabled = false
	std.proximity_fade_enabled = false
	std.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	std.grow = false
