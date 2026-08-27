class_name CityBuildingCatalog
extends RefCounted

## Authored city hulls, glass, and paint styles from buildings.json.
##
## Mapping, build and paint all ask here for a design name. Lots that keep
## the old variant masses sample five colour atlases under paint/variants/.
## Missing authored files fall back to those procedural boxes.

const MANIFEST_PATH := "res://assets/runtime/cities/manifests/buildings.json"
const PAINT_STYLES: PackedStringArray = [
	"terracotta_bond",
	"clapboard_pine",
	"lime_stucco",
	"charcoal_panel",
	"ashlar_sand",
	"verdigris_tile",
	"chalk_wash",
	"rust_plate",
	"amethyst_stucco",
	"neon_night",
]
const VARIANT_NAMES: PackedStringArray = [
	"rect", "cylinder", "rect_cap", "gable", "round_end",
	"taper", "point_half", "slant_half", "cyl_half",
]
const VARIANT_PAINT_STYLES: PackedStringArray = [
	"terracotta_bond",
	"clapboard_pine",
	"verdigris_tile",
	"amethyst_stucco",
	"rust_plate",
]
const SPECIALS: PackedStringArray = [
	"police_station",
	"corner_bar",
	"neon_casino",
	"night_club",
	"civic_hospital",
	"glass_greenhouse",
	"quiet_cemetery",
	"civic_office",
]
static var FALLBACK: Dictionary = {
	"small_houses": PackedStringArray([
		"hearth_cottage", "long_shotgun", "hip_bungalow", "saltbox_home",
		"ell_cottage", "apse_cabin", "turret_house", "shed_studio",
		"court_cottage", "drum_hut",
	]),
	"medium_apartments": PackedStringArray([
		"brick_walkup", "court_walkup", "step_walkup", "bay_walkup",
		"twin_bar", "apse_block", "turret_block", "mansard_block",
		"balcony_slab", "podium_bar",
	]),
	"medium_buildings": PackedStringArray([
		"shop_terrace", "market_nave", "clock_block", "arcade_block",
		"sawtooth_works", "civic_rotunda", "hotel_h", "grid_office",
		"playhouse", "vault_hall",
	]),
	"large_towers": PackedStringArray([
		"setback_tower", "point_tower", "slant_tower", "drum_crown",
		"twin_slab", "chamfer_tower", "podium_shaft", "offset_stack",
		"round_tower", "cross_tower",
	]),
	"skyscrapers": PackedStringArray([
		"deco_spire", "glass_slab", "taper_prism", "crown_drum_sky",
		"bundle_tubes", "twist_stack", "pagoda_steps", "needle_spire",
		"twin_podium", "sky_bridge",
	]),
	"specials": SPECIALS,
}

static var _assets: Dictionary = {}
static var _by_category: Dictionary = {}
static var _hulls: Dictionary = {}
static var _glass: Dictionary = {}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_assets.clear()
	_by_category.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		_seed_fallback()
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		_seed_fallback()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_seed_fallback()
		return
	var assets: Dictionary = (parsed as Dictionary).get("assets", {})
	for key in assets:
		if not assets[key] is Dictionary:
			continue
		var row: Dictionary = assets[key]
		var name := String(row.get("name", key))
		_assets[name] = row
		var category := String(row.get("category", "small_houses"))
		var list: PackedStringArray = _by_category.get(category, PackedStringArray())
		if not list.has(name):
			list.append(name)
		_by_category[category] = list
	_seed_fallback()


static func _seed_fallback() -> void:
	for category in FALLBACK:
		var names: PackedStringArray = FALLBACK[category]
		var list: PackedStringArray = _by_category.get(category, PackedStringArray())
		for name in names:
			if not list.has(name):
				list.append(name)
			if _assets.has(name):
				continue
			_assets[name] = {
				"name": name,
				"category": category,
				"display_name": name.capitalize(),
				"glb": "assets/runtime/cities/models/%s/%s.glb" % [category, name],
				"walkable": category == "specials",
			}
		_by_category[category] = list


static func has_design(name: String) -> bool:
	ensure()
	return not name.is_empty() and _assets.has(name)


static func info(name: String) -> Dictionary:
	ensure()
	return _assets.get(name, {})


static func names_in(category: String) -> PackedStringArray:
	ensure()
	var live: PackedStringArray = _by_category.get(category, PackedStringArray())
	if not live.is_empty():
		return live
	return FALLBACK.get(category, PackedStringArray())


static func display_name(name: String) -> String:
	var row := info(name)
	var title := String(row.get("display_name", ""))
	return title if not title.is_empty() else name.capitalize()


static func is_walkable(name: String) -> bool:
	var row := info(name)
	if row.is_empty():
		return SPECIALS.has(name)
	return bool(row.get("walkable", false)) or String(row.get("category", "")) == "specials"


static func authored_width(name: String, fallback := 10.0) -> float:
	return float(info(name).get("authored_width", fallback))


static func authored_depth(name: String, fallback := 10.0) -> float:
	return float(info(name).get("authored_depth", fallback))


static func authored_height(name: String, fallback := 6.3) -> float:
	var row := info(name)
	var size: Variant = row.get("measured_size", [])
	if size is Array and (size as Array).size() >= 2:
		return maxf(float((size as Array)[1]), 1.2)
	var stories := float(row.get("authored_stories", 2.0))
	return maxf(stories * 3.15, fallback)


static func hull_mesh(name: String) -> Mesh:
	ensure()
	if _hulls.has(name):
		return _hulls[name]
	_cache_meshes(name)
	return _hulls.get(name, null)


static func glass_mesh(name: String) -> Mesh:
	ensure()
	if _glass.has(name):
		return _glass[name]
	_cache_meshes(name)
	return _glass.get(name, null)


static func paint_path(name: String, style: String) -> String:
	var row := info(name)
	for item in row.get("paints", []):
		if not item is Dictionary:
			continue
		if String((item as Dictionary).get("style", "")) != style:
			continue
		var rel := String((item as Dictionary).get("path", ""))
		if rel.is_empty():
			break
		return "res://" + rel
	var category := String(row.get("category", "specials"))
	return "res://assets/runtime/cities/paint/%s/%s_%s_paint.png" % [
		category, name, style,
	]


static func paint_texture(name: String, style: String) -> Texture2D:
	var path := paint_path(name, style)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func variant_name(variant: int) -> String:
	if variant < 0 or variant >= VARIANT_NAMES.size():
		return "rect"
	return VARIANT_NAMES[variant]


static func variant_paint_style_name(lot: Dictionary) -> String:
	var named := String(lot.get("paint_name", ""))
	if VARIANT_PAINT_STYLES.has(named):
		return named
	return VARIANT_PAINT_STYLES[posmod(int(lot.get("paint_style", 0)), VARIANT_PAINT_STYLES.size())]


static func variant_paint_path(variant: int, style: String) -> String:
	return "res://assets/runtime/cities/paint/variants/%s_%s_paint.png" % [
		variant_name(variant), style,
	]


static func variant_paint_texture(variant: int, style: String) -> Texture2D:
	var path := variant_paint_path(variant, style)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func paint_style_name(lot: Dictionary) -> String:
	var named := String(lot.get("paint_name", ""))
	if PAINT_STYLES.has(named):
		return named
	var style := int(lot.get("paint_style", 0))
	if style >= 10 and style <= 13:
		return ["charcoal_panel", "chalk_wash", "rust_plate", "neon_night"][style - 10]
	if style == 18:
		return "neon_night"
	return PAINT_STYLES[posmod(style, PAINT_STYLES.size())]


static func _cache_meshes(name: String) -> void:
	var row := info(name)
	var rel := String(row.get("glb", ""))
	if rel.is_empty():
		var category := String(row.get("category", ""))
		if category.is_empty():
			for key in FALLBACK:
				if (FALLBACK[key] as PackedStringArray).has(name):
					category = String(key)
					break
		if category.is_empty():
			return
		rel = "assets/runtime/cities/models/%s/%s.glb" % [category, name]
	var path := rel if rel.begins_with("res://") else "res://" + rel
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	var root := scene.instantiate()
	if root == null:
		return
	var hulls: Array[Mesh] = []
	var glasses: Array[Mesh] = []
	var walk := [root]
	while not walk.is_empty():
		var node: Node = walk.pop_back()
		for child in node.get_children():
			walk.append(child)
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var node_name := String(mesh_node.name)
		if node_name.ends_with("_glass") or node_name.to_lower().contains("glass"):
			glasses.append(mesh_node.mesh)
		else:
			hulls.append(mesh_node.mesh)
	root.free()
	var hull := _merge_meshes(hulls)
	var glass := _merge_meshes(glasses)
	if hull != null:
		_hulls[name] = hull
	if glass != null:
		_glass[name] = glass


static func _merge_meshes(meshes: Array[Mesh]) -> Mesh:
	if meshes.is_empty():
		return null
	if meshes.size() == 1:
		return meshes[0]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for mesh in meshes:
		if mesh == null:
			continue
		for surf in mesh.get_surface_count():
			st.append_from(mesh, surf, Transform3D.IDENTITY)
	return st.commit()
