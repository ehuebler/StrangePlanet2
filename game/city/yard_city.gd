class_name YardCity
extends PatchCity

## Q-key city: same paving and streets as E, MeshMaker buildings with yards,
## no facade-paint phase. Day / dusk / night come from the building kit.

const YARD_FABRIC := preload("res://game/city/yard_fabric.gd")
const YARD_BUILDING := preload("res://game/city/yard_building.gd")
const MODEL_TAG_NEAR := 36.0
const LIGHT_SWAP_PER_FRAME := 10

var _yard_lighting := "day"
var _proxy_hidden := Transform3D()
var _light_queue: Array = []
var _proxy_hull: MultiMeshInstance3D
var _proxy_glow: MultiMeshInstance3D
var _proxy_hull_xforms: Array[Transform3D] = []
var _proxy_glow_xforms: Array[Transform3D] = []
var _proxy_near: PackedByteArray = []
var _proxy_glow_mat: StandardMaterial3D


func yard_lighting() -> String:
	return _yard_lighting


func refresh_map(overlay_on: bool, eye: Vector3) -> void:
	super.refresh_map(overlay_on, eye)
	var show := overlay_on and phase >= PHASE_BUILT
	for building in _buildings:
		if building == null or not is_instance_valid(building):
			continue
		if not building.has_method(&"set_model_tag_visible"):
			continue
		if not show:
			building.set_model_tag_visible(false)
			continue
		building.set_model_tag_visible(eye.distance_to(building.base_point()) <= MODEL_TAG_NEAR)


func advance(shape: PlanetShape) -> bool:
	if phase == PHASE_BUILT:
		return false
	return super.advance(shape)


func _build_fabric(shape: PlanetShape, buckets: Dictionary) -> void:
	_discard_node(_fabric_streets)
	_fabric_streets = null
	_discard_node(_fabric_buildings)
	_fabric_buildings = null
	fabric = {}
	var arteries := {
		"highway": _dirs_to_uv(_highway_dirs),
		"highway_half": HIGHWAY_HALF,
		"spur": _dirs_to_uv(_highway_spur),
		"spur_half": HIGHWAY_HALF * 0.72,
		"exits": _exit_uvs(),
		"exit_half": EXIT_HALF,
	}
	_fabric_arteries = arteries
	_fabric_layout = YARD_FABRIC.new()
	fabric = _fabric_layout.build(plan, buckets, _pad_cell, _up, _east, _north, _radius, arteries)
	_cull_overlapping_lots()
	_refill_fabric_gaps()
	_cull_overlapping_lots()
	_name_fabric()
	var streets: Array = fabric.get("streets", [])
	var street_st := SurfaceTool.new()
	street_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for street in streets:
		var row: Dictionary = street
		var half := float(row["half"])
		var rank: int = int(row["rank"])
		var colour := Color(0.20, 0.20, 0.22, FABRIC_ALPHA)
		if rank == 2:
			colour = Color(0.26, 0.24, 0.22, FABRIC_ALPHA * 0.9)
		elif rank == 0:
			colour = Color(0.17, 0.17, 0.19, FABRIC_ALPHA)
		_deck_ribbon(street_st, shape, row["uv"], half, colour, fabric.get("junctions", []))
	for junction in fabric.get("junctions", []):
		var row: Dictionary = junction
		var rank: int = int(row.get("rank", 1))
		var colour := Color(0.20, 0.20, 0.22, FABRIC_ALPHA)
		if rank == 2:
			colour = Color(0.26, 0.24, 0.22, FABRIC_ALPHA * 0.9)
		elif rank == 0:
			colour = Color(0.17, 0.17, 0.19, FABRIC_ALPHA)
		_deck_pad(street_st, shape, row["at"], float(row["half"]), colour)
	_fabric_streets = _commit_ghost(street_st, "FabricStreets")
	_emit_fabric_buildings(shape)
	print("yard_city: fabric %s — %d streets, %d plots"
		% [plan.patch_name, streets.size(), fabric.get("lots", []).size()])


func _build_city(shape: PlanetShape) -> void:
	_index_city_roads()
	_assign_paint_styles()
	_assign_yard_neons()
	_paint_pavement(shape)
	_solidify_buildings(shape)
	_place_lamps(shape)
	_refresh_night_glow(shape)
	_dressed = true
	_paint_ground_map()
	if is_instance_valid(_fabric_streets):
		_fabric_streets.visible = false
	if is_instance_valid(_fabric_buildings):
		_fabric_buildings.visible = false
	set_process(true)
	print("yard_city: built %s — %d MeshMaker plots, %d lamps"
		% [plan.patch_name, fabric.get("lots", []).size(), _lamp_spots.size()])


func _solidify_buildings(shape: PlanetShape) -> void:
	_cull_overlapping_lots()
	_discard_node(_solid_buildings)
	_solid_buildings = null
	_discard_node(_solid_body)
	_solid_body = null
	_discard_node(_lot_root)
	_lot_root = null
	_buildings.clear()
	YardBuildingCatalog.ensure()
	var lots: Array = fabric.get("lots", [])
	if lots.is_empty():
		return
	_lot_root = Node3D.new()
	_lot_root.name = "YardLots"
	add_child(_lot_root)
	if not is_in_group(DamageHit.BUILDING_GROUP):
		add_to_group(DamageHit.BUILDING_GROUP)
	for index in lots.size():
		var row: Dictionary = lots[index]
		if not _lot_on_slab(row):
			continue
		if String(row.get("design", "")).is_empty():
			var picked := YardBuildingCatalog.pick_for_lot(row, plan.patch_id + index)
			if not picked.is_empty():
				row["design"] = String(picked.get("id", ""))
				row["plot_margin"] = float(picked.get("plot_margin_m", row.get("plot_margin", 6.0)))
				row["yard_rot90"] = bool(picked.get("yard_rot90", false))
				lots[index] = row
		var building = YARD_BUILDING.new()
		_lot_root.add_child(building)
		building.setup(self, index, row, shape)
		_buildings.append(building)
	fabric["lots"] = lots
	_build_proxies()


func _assign_yard_neons() -> void:
	var lots: Array = fabric.get("lots", [])
	for index in lots.size():
		var row: Dictionary = lots[index]
		var typology := int(row.get("typology", 0))
		var centre: Vector2 = row.get("centre", Vector2.ZERO)
		var h := _hash21(centre * Vector2(2.13, 0.77) + Vector2(float(index) * 0.017, 0.0))
		var h2 := _hash21(centre * Vector2(0.61, 3.07))
		var palette: Array
		if typology >= TYPE_TOWER:
			palette = [
				Color(1.0, 0.06, 0.72),
				Color(0.05, 0.95, 1.0),
				Color(0.68, 0.02, 1.0),
				Color(0.08, 1.0, 0.22),
				Color(1.0, 0.38, 0.04),
				Color(0.12, 0.42, 1.0),
			]
			row["night_crown"] = h2 > 0.4
		elif typology >= TYPE_APARTMENT:
			palette = [
				Color(1.0, 0.22, 0.08),
				Color(1.0, 0.06, 0.55),
				Color(0.12, 0.85, 1.0),
				Color(1.0, 0.48, 0.07),
				Color(0.55, 0.08, 1.0),
			]
			row["night_crown"] = false
		else:
			palette = [
				Color(1.0, 0.38, 0.05),
				Color(1.0, 0.55, 0.08),
				Color(1.0, 0.18, 0.42),
				Color(1.0, 0.28, 0.04),
				Color(0.95, 0.72, 0.08),
			]
			row["night_crown"] = false
		var pick := int(h * float(palette.size())) % palette.size()
		row["paint_neon"] = _saturate_neon(palette[pick])
		row["paint_neon_alt"] = _saturate_neon(
			palette[(pick + 1 + int(h2 * 3.0)) % palette.size()])
		row["night_trim"] = true
		lots[index] = row
	fabric["lots"] = lots


func lot_has_design(lot: Dictionary) -> bool:
	var design := String(lot.get("design", ""))
	return not design.is_empty() and YardBuildingCatalog.has_design(design)


func _lot_model_xform(shape: PlanetShape, lot: Dictionary) -> Transform3D:
	var centre: Vector2 = lot.get("centre", Vector2.ZERO)
	var along: Vector2 = lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across: Vector2 = lot.get("across", Vector2(-along.y, along.x))
	if across.length_squared() < 0.0001:
		across = Vector2(-along.y, along.x)
	across = across.normalized()
	var up := _from_uv(centre).normalized()
	var origin := _lot_deck_mark(shape, lot, centre)
	var z_axis := (_from_uv(centre + across).normalized() - up)
	z_axis = (z_axis - up * z_axis.dot(up)).normalized()
	if z_axis.length_squared() < 0.0001:
		z_axis = up.cross(Vector3.RIGHT)
		if z_axis.length_squared() < 0.0001:
			z_axis = up.cross(Vector3.FORWARD)
		z_axis = z_axis.normalized()
	var x_axis := up.cross(z_axis).normalized()
	var along_t := (_from_uv(centre + along).normalized() - up)
	along_t = (along_t - up * along_t.dot(up)).normalized()
	if x_axis.dot(along_t) < 0.0:
		x_axis = -x_axis
	z_axis = x_axis.cross(up).normalized()
	var design := String(lot.get("design", ""))
	var info := YardBuildingCatalog.info(design)
	var plot_w := maxf(float(info.get("plot_width_m", lot.get("width", 12.0))), 1.0)
	var plot_d := maxf(float(info.get("plot_depth_m", lot.get("depth", 12.0))), 1.0)
	var plot_h := maxf(float(info.get("height_m", float(lot.get("stories", 2.0)) * 3.15)), 1.0)
	if bool(lot.get("yard_rot90", false)):
		var swap := plot_w
		plot_w = plot_d
		plot_d = swap
	var sx := float(lot.get("width", plot_w)) / plot_w
	var sz := float(lot.get("depth", plot_d)) / plot_d
	var sy := clampf((float(lot.get("stories", 2.0)) * 3.15) / plot_h, 0.65, 1.45)
	return Transform3D(Basis(x_axis * sx, up * sy, z_axis * sz), origin)


func _process(delta: float) -> void:
	super._process(delta)
	if phase < PHASE_BUILT:
		return
	var origin := global_transform * (_up * _radius) if is_inside_tree() else _up * _radius
	var night := _night_at(origin)
	var kind := "day"
	if night >= 0.55:
		kind = "night"
	elif night >= 0.15:
		kind = "dusk"
	if kind != _yard_lighting:
		_yard_lighting = kind
		_light_queue = _buildings.duplicate()
	_drain_light_queue()
	_ensure_proxies()
	_refresh_lod()
	_sync_proxy_glow()


func _drain_light_queue() -> void:
	var left := LIGHT_SWAP_PER_FRAME
	while left > 0 and not _light_queue.is_empty():
		var building = _light_queue.pop_front()
		left -= 1
		if building != null and is_instance_valid(building):
			building.apply_lighting(_yard_lighting)


func _ensure_proxies() -> void:
	if is_instance_valid(_proxy_hull) or _buildings.is_empty():
		return
	_build_proxies()


func _build_proxies() -> void:
	_discard_node(_proxy_hull)
	_discard_node(_proxy_glow)
	_proxy_hull = null
	_proxy_glow = null
	_proxy_hull_xforms.clear()
	_proxy_glow_xforms.clear()
	_proxy_near = PackedByteArray()
	var count := 0
	for building in _buildings:
		if building != null and is_instance_valid(building):
			count += 1
	if count <= 0:
		return
	_proxy_hidden = Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3.ZERO)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var hull_mm := MultiMesh.new()
	hull_mm.transform_format = MultiMesh.TRANSFORM_3D
	hull_mm.use_colors = true
	hull_mm.instance_count = count
	hull_mm.mesh = box
	var glow_mm := MultiMesh.new()
	glow_mm.transform_format = MultiMesh.TRANSFORM_3D
	glow_mm.use_colors = true
	glow_mm.instance_count = count
	glow_mm.mesh = box
	var hull_mat := StandardMaterial3D.new()
	hull_mat.vertex_color_use_as_albedo = true
	hull_mat.roughness = 0.88
	hull_mat.metallic = 0.0
	_proxy_glow_mat = StandardMaterial3D.new()
	_proxy_glow_mat.vertex_color_use_as_albedo = true
	_proxy_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_proxy_glow_mat.emission_enabled = true
	_proxy_glow_mat.emission = Color.WHITE
	_proxy_glow_mat.emission_energy_multiplier = 0.0
	_proxy_hull = MultiMeshInstance3D.new()
	_proxy_hull.name = "YardProxies"
	_proxy_hull.multimesh = hull_mm
	_proxy_hull.material_override = hull_mat
	_proxy_hull.layers = BUILDING_VISUAL_LAYER
	_proxy_hull.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_proxy_hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_proxy_hull)
	_proxy_glow = MultiMeshInstance3D.new()
	_proxy_glow.name = "YardProxyLights"
	_proxy_glow.multimesh = glow_mm
	_proxy_glow.material_override = _proxy_glow_mat
	_proxy_glow.layers = BUILDING_VISUAL_LAYER
	_proxy_glow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_proxy_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_proxy_glow)
	_proxy_near.resize(count)
	var slot := 0
	for building in _buildings:
		if building == null or not is_instance_valid(building):
			continue
		building.bind_proxy_slot(slot)
		var hull_x: Transform3D = building.proxy_hull_xform()
		var glow_x: Transform3D = building.proxy_glow_xform()
		_proxy_hull_xforms.append(hull_x)
		_proxy_glow_xforms.append(glow_x)
		_proxy_near[slot] = 1
		hull_mm.set_instance_transform(slot, _proxy_hidden)
		hull_mm.set_instance_color(slot, building.proxy_color() as Color)
		glow_mm.set_instance_transform(slot, _proxy_hidden)
		glow_mm.set_instance_color(slot, building.proxy_neon() as Color)
		slot += 1
	_lod_near_reset()


func _lod_near_reset() -> void:
	for building in _buildings:
		if building != null and is_instance_valid(building):
			building.arm_lod()


func _refresh_lod() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	for building in _buildings:
		if building != null and is_instance_valid(building):
			building.set_lod(eye)


func set_yard_proxy_near(slot: int, hide_proxy: bool) -> void:
	if slot < 0 or slot >= _proxy_near.size():
		return
	var flag := 1 if hide_proxy else 0
	if _proxy_near[slot] == flag:
		return
	_proxy_near[slot] = flag
	if is_instance_valid(_proxy_hull) and slot < _proxy_hull_xforms.size():
		_proxy_hull.multimesh.set_instance_transform(
			slot, _proxy_hidden if hide_proxy else _proxy_hull_xforms[slot])
	if is_instance_valid(_proxy_glow) and slot < _proxy_glow_xforms.size():
		_proxy_glow.multimesh.set_instance_transform(
			slot, _proxy_hidden if hide_proxy else _proxy_glow_xforms[slot])


func _sync_proxy_glow() -> void:
	if _proxy_glow_mat == null:
		return
	var energy := 0.0
	if _yard_lighting == "dusk":
		energy = 1.8
	elif _yard_lighting == "night":
		energy = 3.6
	_proxy_glow_mat.emission_energy_multiplier = energy
	if is_instance_valid(_proxy_glow):
		_proxy_glow.visible = energy > 0.01
