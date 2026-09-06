extends "res://game/city/city_building.gd"

## One MeshMaker plot (hull plus yard). Day / dusk / night are separate GLBs.

const YARD_PARTS: PackedStringArray = [
	"Plot", "Site", "Hard", "Plants", "Water",
]
const DETAIL_PARTS: PackedStringArray = [
	"Frames", "Doors",
]
const HULL_COLLIDE: PackedStringArray = [
	"Mass", "Base", "Roof",
]
const EXTRA_COLLIDE: PackedStringArray = [
	"Frames", "Doors", "Trim",
]

const YARD_END := 80.0
const DETAIL_END := 180.0
const LOD_HOUSE := 260.0
const LOD_APT := 340.0
const LOD_TOWER := 500.0

static var _emit_mats: Dictionary = {}

var _models: Dictionary = {}
var _shown := ""
var _model_tag: Label3D
var _anchor := Vector3.ZERO
var _proxy_slot := -1
var _proxy_color := Color(0.36, 0.33, 0.30)
var _proxy_neon := Color(1.0, 0.38, 0.05)
var _lod_near := true


func _rebuild_visual() -> void:
	if _city == null or _shape == null:
		return
	if _dead or _sheared:
		_hide_models()
		super._rebuild_visual()
		return
	var design := String(_lot.get("design", ""))
	if design.is_empty() or not YardBuildingCatalog.has_design(design):
		super._rebuild_visual()
		return
	if is_instance_valid(_hull):
		_hull.visible = false
	if is_instance_valid(_glass):
		_glass.visible = false
	var kind := "day"
	if _city.has_method(&"yard_lighting"):
		kind = String(_city.call(&"yard_lighting"))
	apply_lighting(kind)
	_anchor = base_point()
	_proxy_neon = _lot_neon(false)
	_cache_proxy_color()


func apply_lighting(kind: String) -> void:
	if kind != "dusk" and kind != "night":
		kind = "day"
	if kind == _shown and _models.has(kind) and is_instance_valid(_models[kind]):
		return
	_shown = kind
	_swap_model(kind)


func detail_end() -> float:
	var typology := int(_lot.get("typology", 0))
	if typology >= PatchCity.TYPE_TOWER:
		return LOD_TOWER
	if typology >= PatchCity.TYPE_APARTMENT:
		return LOD_APT
	return LOD_HOUSE


func bind_proxy_slot(slot: int) -> void:
	_proxy_slot = slot


func set_lod(eye: Vector3) -> void:
	var live: Node3D = _models.get(_shown, null)
	var at := _anchor
	if is_instance_valid(live):
		at = live.global_position
	var near := not _dead and eye.distance_squared_to(at) <= detail_end() * detail_end()
	if is_instance_valid(live):
		live.visible = near or _proxy_slot < 0
	if near == _lod_near:
		return
	_lod_near = near
	if _city != null and _city.has_method(&"set_yard_proxy_near"):
		_city.call(&"set_yard_proxy_near", _proxy_slot, near or _dead)


func arm_lod() -> void:
	_lod_near = true


func proxy_color() -> Color:
	return _proxy_color


func proxy_neon() -> Color:
	return _proxy_neon


func proxy_hull_xform() -> Transform3D:
	if not is_instance_valid(_body) or _city == null or not _city.is_inside_tree():
		return Transform3D.IDENTITY
	var size := Vector3(8.0, 10.0, 8.0)
	if is_instance_valid(_collider) and _collider.shape is BoxShape3D:
		size = (_collider.shape as BoxShape3D).size
	var world := _body.global_transform
	world.basis = world.basis * Basis.from_scale(size)
	return _city.global_transform.affine_inverse() * world


func proxy_glow_xform() -> Transform3D:
	var hull := proxy_hull_xform()
	return Transform3D(hull.basis * Basis.from_scale(Vector3(0.78, 0.70, 0.78)), hull.origin)


func _swap_model(kind: String) -> void:
	for key in _models.keys():
		if String(key) == kind:
			continue
		var held: Node3D = _models[key]
		_models.erase(key)
		if is_instance_valid(held):
			held.queue_free()
	_ensure_model(kind)
	var live: Node3D = _models.get(kind, null)
	if is_instance_valid(live):
		live.visible = not _dead and _lod_near
		if _city != null and _shape != null:
			live.transform = _city._lot_model_xform(_shape, _lot)
			_seat_model(live)


func _ensure_model(kind: String) -> void:
	if _models.has(kind) and is_instance_valid(_models[kind]):
		return
	var design := String(_lot.get("design", ""))
	if design.is_empty() or not YardBuildingCatalog.has_design(design):
		return
	if _city == null or _shape == null:
		return
	var scene := YardBuildingCatalog.instantiate(design, kind)
	if scene == null:
		return
	scene.name = "Model_%s" % kind
	scene.visible = false
	add_child(scene)
	scene.transform = _city._lot_model_xform(_shape, _lot)
	_prepare_model(scene)
	_seat_model(scene)
	_tint_night_lights(scene, kind)
	_models[kind] = scene


func _hide_models() -> void:
	for key in _models:
		var node: Node3D = _models[key]
		if is_instance_valid(node):
			node.visible = false


func _seat_model(root: Node3D) -> void:
	if root == null or _city == null:
		return
	var planet: Planet = null
	var walk: Node = _city
	while walk != null:
		if walk is Planet:
			planet = walk as Planet
			break
		walk = walk.get_parent()
	BuildingFoundation.seat(
		root, planet, _proxy_color, PackedStringArray(["Mass", "Base"]))
	if is_instance_valid(_body):
		_make_collision()


func _prepare_model(root: Node) -> void:
	if root is MeshInstance3D:
		_prepare_mesh(root as MeshInstance3D)
	for child in root.get_children():
		_prepare_model(child)


func _prepare_mesh(mesh_i: MeshInstance3D) -> void:
	mesh_i.layers = PatchCity.BUILDING_VISUAL_LAYER
	mesh_i.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var name := String(mesh_i.name)
	if _name_has(name, YARD_PARTS):
		mesh_i.visibility_range_end = YARD_END
		mesh_i.visibility_range_end_margin = 12.0
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif _name_has(name, DETAIL_PARTS):
		mesh_i.visibility_range_end = DETAIL_END
		mesh_i.visibility_range_end_margin = 20.0
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		mesh_i.visibility_range_end = detail_end()
		mesh_i.visibility_range_end_margin = 24.0
		var hull := name.contains("Mass") or name.contains("Roof")
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
			if hull else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _cache_proxy_color() -> void:
	var live: Node3D = _models.get(_shown, null)
	if is_instance_valid(live):
		var found := _first_albedo(live, "Mass")
		if found.a > 0.01 and found.r + found.g + found.b < 2.25:
			_proxy_color = found
			return
		found = _first_albedo(live, "Roof")
		if found.a > 0.01 and found.r + found.g + found.b < 2.25:
			_proxy_color = found
			return
	var typology := int(_lot.get("typology", 0))
	if typology >= PatchCity.TYPE_TOWER:
		_proxy_color = Color(0.42, 0.44, 0.48)
	elif typology >= PatchCity.TYPE_APARTMENT:
		_proxy_color = Color(0.40, 0.36, 0.32)
	else:
		_proxy_color = Color(0.47, 0.40, 0.32)


func _first_albedo(root: Node, part: String) -> Color:
	if root is MeshInstance3D and String(root.name).contains(part):
		var mat := (root as MeshInstance3D).get_active_material(0)
		if mat is StandardMaterial3D:
			return (mat as StandardMaterial3D).albedo_color
	for child in root.get_children():
		var found := _first_albedo(child, part)
		if found.a > 0.01:
			return found
	return Color(0, 0, 0, 0)


func _name_has(name: String, parts: PackedStringArray) -> bool:
	for part in parts:
		if name.contains(part):
			return true
	return false


func _lot_neon(alt := false) -> Color:
	var key := "paint_neon_alt" if alt else "paint_neon"
	var colour: Color = _lot.get(key, Color(0, 0, 0, 0))
	if colour.r + colour.g + colour.b < 0.45:
		colour = Color(1.0, 0.38, 0.05) if not alt else Color(0.05, 0.95, 1.0)
	if _city != null:
		return _city._saturate_neon(colour)
	var peak := maxf(colour.r, maxf(colour.g, colour.b))
	if peak < 0.08:
		return colour
	return Color(colour.r / peak, colour.g / peak, colour.b / peak)


func _tint_night_lights(root: Node, kind: String) -> void:
	if kind != "dusk" and kind != "night":
		return
	var neon := _lot_neon(false)
	var trim := _lot_neon(true)
	_tint_night_node(root, kind, neon, trim)


func _tint_night_node(root: Node, kind: String, neon: Color, trim: Color) -> void:
	if root is MeshInstance3D:
		var mesh_i := root as MeshInstance3D
		var name := String(mesh_i.name)
		var glass := name.contains("Glass") or name.contains("Glazing")
		var lit_trim := name.contains("Trim")
		if glass or lit_trim:
			_override_emission(mesh_i, trim if lit_trim and not glass else neon, kind, glass)
	for child in root.get_children():
		_tint_night_node(child, kind, neon, trim)


func _override_emission(mesh_i: MeshInstance3D, colour: Color, kind: String, glass: bool) -> void:
	var mesh := mesh_i.mesh
	if mesh == null:
		return
	for surf in mesh.get_surface_count():
		var src := mesh_i.get_active_material(surf)
		mesh_i.set_surface_override_material(surf, _shared_emit(src, colour, kind, glass))


func _shared_emit(src: Material, colour: Color, kind: String, glass: bool) -> Material:
	var src_id := src.get_instance_id() if src != null else 0
	var key := "%s_%s_%d_%d_%d_%d" % [
		kind,
		"g" if glass else "t",
		int(colour.r * 15.0),
		int(colour.g * 15.0),
		int(colour.b * 15.0),
		src_id,
	]
	if _emit_mats.has(key) and is_instance_valid(_emit_mats[key]):
		return _emit_mats[key]
	var energy := 2.2 if kind == "dusk" else 3.8
	if not glass:
		energy *= 0.72
	var mat: Material = src.duplicate() if src != null else StandardMaterial3D.new()
	YardBuildingCatalog._harden_material(mat)
	if mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		std.emission_enabled = true
		std.emission = colour
		std.emission_texture = null
		std.emission_energy_multiplier = energy
		if glass:
			std.albedo_color = Color(colour.r * 0.18, colour.g * 0.18, colour.b * 0.18)
			std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_emit_mats[key] = mat
	return mat


func _make_collision() -> void:
	if _city == null or _shape == null:
		return
	var model: Node3D = _models.get(_shown, null)
	if not is_instance_valid(model):
		super._make_collision()
		return
	if not is_instance_valid(_body):
		_body = StaticBody3D.new()
		_body.name = "Body"
		_body.collision_layer = 1
		_body.collision_mask = 1
		_collider = CollisionShape3D.new()
		_body.add_child(_collider)
		add_child(_body)
	_body.collision_layer = 1
	_body.collision_mask = 1
	_body.collision_priority = 1.0
	var bounds := _solid_model_aabb(model, HULL_COLLIDE)
	if bounds.size.x < 1.0 or bounds.size.z < 1.0:
		bounds = _solid_model_aabb(model, EXTRA_COLLIDE)
	if bounds.size.x < 1.0 or bounds.size.z < 1.0:
		bounds = _fallback_hull_aabb()
	bounds.size = Vector3(
		maxf(bounds.size.x, 2.4),
		maxf(bounds.size.y, 2.4),
		maxf(bounds.size.z, 2.4))
	var box := BoxShape3D.new()
	box.size = bounds.size
	_collider.shape = box
	_collider.disabled = false
	_body.transform = model.transform * Transform3D(Basis.IDENTITY, bounds.get_center())


func _solid_model_aabb(root: Node, parts: PackedStringArray) -> AABB:
	var held: Array = [false, AABB()]
	_accum_solid_aabb(root, Transform3D.IDENTITY, parts, held)
	if not bool(held[0]):
		return AABB()
	return held[1]


func _accum_solid_aabb(node: Node, xform: Transform3D, parts: PackedStringArray, held: Array) -> void:
	if node is MeshInstance3D and _name_has(String(node.name), parts):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			var piece := xform * mesh.get_aabb()
			if bool(held[0]):
				held[1] = (held[1] as AABB).merge(piece)
			else:
				held[0] = true
				held[1] = piece
	for child in node.get_children():
		var next := xform
		if child is Node3D:
			next = xform * (child as Node3D).transform
		_accum_solid_aabb(child, next, parts, held)


func _fallback_hull_aabb() -> AABB:
	var design := String(_lot.get("design", ""))
	var info := YardBuildingCatalog.info(design)
	var plot_w := maxf(float(info.get("plot_width_m", _lot.get("width", 12.0))), 4.0)
	var plot_d := maxf(float(info.get("plot_depth_m", _lot.get("depth", 12.0))), 4.0)
	var plot_h := maxf(float(info.get("height_m", float(_lot.get("stories", 2.0)) * 3.15)), 3.0)
	var margin := float(_lot.get("plot_margin", info.get("plot_margin_m", 6.0)))
	var hull_w := maxf(plot_w - margin * 2.0, plot_w * 0.55)
	var hull_d := maxf(plot_d - margin * 2.0, plot_d * 0.55)
	return AABB(Vector3(hull_w * -0.5, 0.0, hull_d * -0.5), Vector3(hull_w, plot_h, hull_d))


func set_night(_night: float) -> void:
	pass


func set_model_tag_visible(on: bool) -> void:
	if on and not _dead and not String(_lot.get("design", "")).is_empty():
		_ensure_model_tag()
		if not _model_tag.visible:
			_place_model_tag()
		_model_tag.visible = true
		return
	if is_instance_valid(_model_tag):
		_model_tag.visible = false


func _ensure_model_tag() -> void:
	if is_instance_valid(_model_tag):
		return
	_model_tag = Label3D.new()
	_model_tag.name = "ModelTag"
	_model_tag.font = PatchCity.MAP_FONT
	_model_tag.font_size = 18
	_model_tag.pixel_size = 0.03
	_model_tag.modulate = Color(0.95, 0.90, 0.62, 0.96)
	_model_tag.outline_size = 8
	_model_tag.outline_modulate = Color(0.04, 0.03, 0.08, 0.92)
	_model_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_model_tag.no_depth_test = false
	_model_tag.shaded = false
	_model_tag.double_sided = true
	_model_tag.visible = false
	add_child(_model_tag)
	_place_model_tag()


func _place_model_tag() -> void:
	if not is_instance_valid(_model_tag) or _city == null:
		return
	_model_tag.text = String(_lot.get("design", ""))
	var centre: Vector2 = _lot.get("centre", Vector2.ZERO)
	var up := _city._from_uv(centre).normalized()
	_model_tag.position = _mark_at(original_stories()) + up * 1.6
