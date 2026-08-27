class_name LandPatchOverlay
extends Node3D

## Tilde map of [LandPartition]: patch border ribbons on the ground, names at
## high altitude. Street names lie on the ground inside a mapped city.

const GROUP := &"land_patch_overlay"
const FONT: FontFile = preload("res://fonts/Bungee-Regular.ttf")
const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")
const STORE := preload("res://game/city/patch_city_store.gd")

## Typical territory width, metres. About a twelfth of the first cut, so
## ten to fifteen of these fit in one of those larger cells.
@export var target_span := 1300.0
## Keep-out around each Giant Mountain landmark, metres of surface arc.
@export var mountain_clearance := 1000.0
## Ribbon half-width, metres. A painted line on the ground, not a road.
@export var border_half_width := 5.0
## Metres the ribbon sits above the analytical surface, so it does not z-fight
## the terrain mesh.
@export var border_lift := 2.0
## Arc length between draped samples, metres. Short enough that the ribbon
## follows hills instead of spanning them as a chord.
@export var border_step := 6.0

var partition := LandPartition.new()
var _enabled := false
var _baked := false
var _borders: MeshInstance3D
var _labels: Array[Label3D] = []
var _cities: Dictionary = {}


func _ready() -> void:
	name = "LandPatches"
	add_to_group(GROUP)
	visible = false
	set_process(false)
	call_deferred(&"_rebuild")


func set_overlay_enabled(on: bool) -> void:
	_enabled = on
	visible = on and _baked
	set_process(on and _baked)
	if is_instance_valid(_borders):
		_borders.visible = on
	_refresh_city_maps()
	_refresh_patch_labels()


func render_live_city(patch_id: int) -> bool:
	if not _baked or patch_id < 0 or patch_id >= partition.patches.size():
		return false
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return false
	var held := _city_at(patch_id)
	if held != null:
		_cities.erase(patch_id)
		held.free()
	var generator := PatchCityGenerator.new()
	var plan := generator.generate(planet.shape, partition, patch_id)
	if plan.districts.is_empty():
		return false
	var city := PatchCity.new()
	city.apply(plan, planet.shape)
	add_child(city)
	_cities[patch_id] = city
	print("patch_city: %s — %d districts, loop %d pts"
		% [plan.patch_name, plan.districts.size(), plan.loop.size()])
	return _finish_live_city(city, planet)


func place_baked_city(patch_id: int) -> bool:
	if not _baked or patch_id < 0 or patch_id >= partition.patches.size():
		return false
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return false
	var patch_name := partition.patches[patch_id].name
	if not STORE.has_phase(patch_id, PatchCity.PHASE_PAINTED, patch_name):
		return false
	var held := _city_at(patch_id)
	if held != null:
		if held.phase >= PatchCity.PHASE_PAINTED and held.from_bake:
			return false
		_cities.erase(patch_id)
		held.free()
	var started := Time.get_ticks_msec()
	var baked := STORE.instantiate_phase(
		patch_id, PatchCity.PHASE_PAINTED, planet.shape, patch_name,
		STORE.LAYOUT_FIRST_PLANET, planet)
	if baked == null:
		return false
	baked.from_bake = true
	_cities[patch_id] = baked
	baked.clear_flora()
	print("patch_city: placed baked %s — %d places  %d ms"
		% [baked.plan.patch_name, baked.places.size(),
			Time.get_ticks_msec() - started])
	_refresh_city_maps()
	return true


func has_baked_city(patch_id: int) -> bool:
	if patch_id < 0 or patch_id >= partition.patches.size():
		return false
	return STORE.has_phase(
		patch_id, PatchCity.PHASE_PAINTED, partition.patches[patch_id].name)


func _finish_live_city(city: PatchCity, planet: Planet) -> bool:
	var advanced := false
	while city.phase < PatchCity.PHASE_PAINTED:
		if not _advance_live_city(city, planet):
			break
		advanced = true
	return advanced


func _advance_live_city(city: PatchCity, planet: Planet) -> bool:
	if city.advance(planet.shape):
		if city.phase == PatchCity.PHASE_PAVED:
			city.reparent(planet)
			city.clear_flora()
			print("patch_city: paved %s" % city.plan.patch_name)
		elif city.phase == PatchCity.PHASE_MAPPED:
			print("patch_city: mapped %s — %d places"
				% [city.plan.patch_name, city.places.size()])
		elif city.phase == PatchCity.PHASE_BUILT:
			print("patch_city: built %s"
				% city.plan.patch_name)
		elif city.phase == PatchCity.PHASE_PAINTED:
			print("patch_city: painted %s"
				% city.plan.patch_name)
		_refresh_city_maps()
		return true
	return false


func has_city(patch_id: int) -> bool:
	return _city_at(patch_id) != null


func city_phase(patch_id: int) -> int:
	var city := _city_at(patch_id)
	return city.phase if city != null else -1


func all_cities() -> Array:
	var out: Array = []
	for patch_id in _cities:
		var city := _city_at(int(patch_id))
		if city != null:
			out.append(city)
	return out


func _city_at(patch_id: int) -> PatchCity:
	if not _cities.has(patch_id):
		return null
	var held: Variant = _cities[patch_id]
	if not is_instance_valid(held):
		_cities.erase(patch_id)
		return null
	return held as PatchCity


func _process(_delta: float) -> void:
	_refresh_city_maps()
	_refresh_patch_labels()


func _refresh_city_maps() -> void:
	var eye := Vector3.ZERO
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		eye = cam.global_position
	for patch_id in _cities:
		var city := _city_at(int(patch_id))
		if city != null:
			city.refresh_map(_enabled, eye)


func _refresh_patch_labels() -> void:
	var show := _enabled and _camera_altitude() >= PatchCity.PATCH_NAME_ALT
	for label in _labels:
		if is_instance_valid(label):
			label.visible = show
	if is_instance_valid(_borders):
		_borders.visible = _enabled


func _camera_altitude() -> float:
	if not is_inside_tree():
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return 0.0
	var local := planet.to_local(cam.global_position)
	if local.length_squared() < 1.0:
		return 0.0
	var up := local.normalized()
	return local.length() - planet.shape.radius - planet.shape.elevation(
		up, planet.spacing_underfoot())


func _rebuild() -> void:
	var planet := get_parent() as Planet
	if planet == null or planet.shape == null:
		return
	planet.shape.prepare()
	var mountains := PackedVector3Array()
	for child in planet.get_children():
		if not is_instance_valid(child):
			continue
		var landmark := child as Landmark
		if landmark == null:
			continue
		if String(landmark.name).begins_with("GiantMountain"):
			if landmark.direction.length_squared() > 0.001:
				mountains.append(landmark.direction.normalized())
	partition.bake(planet.shape, mountains, mountain_clearance, target_span)
	_build_borders(planet)
	_build_labels(planet)
	_baked = true
	visible = _enabled
	if is_instance_valid(_borders):
		_borders.visible = _enabled
	print("land_patches: %d territories, %.0f km² buildable, %d border edges"
		% [
			partition.patches.size(),
			partition.buildable_area / 1_000_000.0,
			partition.border_edge_count(),
		])


func _build_borders(planet: Planet) -> void:
	if is_instance_valid(_borders):
		_borders.queue_free()
	if partition.border_chains.is_empty() or planet.shape == null:
		return
	var shape := planet.shape
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for chain in partition.border_chains:
		var draped := PackedVector3Array()
		if chain.patch_a >= 0 and chain.patch_b >= 0:
			draped = _drape_bisector(shape, chain)
		else:
			draped = _drape_chain(shape, chain.dirs, chain.closed)
		_emit_ribbon(st, draped)
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(
		PALETTE.accent.r, PALETTE.accent.g, PALETTE.accent.b, 0.92)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	_borders = MeshInstance3D.new()
	_borders.name = "Borders"
	_borders.mesh = mesh
	_borders.material_override = material
	_borders.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_borders)


func _drape_bisector(shape: PlanetShape, chain: LandPartition.BorderChain) -> PackedVector3Array:
	var seed_a := partition.patches[chain.patch_a].seed
	var seed_b := partition.patches[chain.patch_b].seed
	var normal := seed_a - seed_b
	if normal.length_squared() < 0.0000001 or chain.dirs.size() < 2:
		return _drape_chain(shape, chain.dirs, chain.closed)
	if chain.closed:
		return _drape_bisector_loop(shape, chain.dirs, normal)
	var a := _on_bisector(chain.dirs[0], normal)
	var b := _on_bisector(chain.dirs[chain.dirs.size() - 1], normal)
	return _drape_slerp(shape, a, b)


func _drape_bisector_loop(
		shape: PlanetShape,
		dirs: PackedVector3Array,
		normal: Vector3
	) -> PackedVector3Array:
	var axis := normal.normalized()
	var pole := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var u := axis.cross(pole).normalized()
	var v := axis.cross(u)
	var angles: PackedFloat32Array = PackedFloat32Array()
	angles.resize(dirs.size())
	for index in dirs.size():
		var on := _on_bisector(dirs[index], normal)
		angles[index] = atan2(on.dot(v), on.dot(u))
	var sorted := Array(angles)
	sorted.sort()
	var gap := -1.0
	var gap_after := 0
	for index in sorted.size():
		var next_ang: float = float(sorted[(index + 1) % sorted.size()])
		var at: float = float(sorted[index])
		var span := next_ang - at
		if index == sorted.size() - 1:
			span = next_ang + TAU - at
		if span > gap:
			gap = span
			gap_after = index
	var from: float = float(sorted[(gap_after + 1) % sorted.size()])
	var to: float = float(sorted[gap_after])
	if gap_after == sorted.size() - 1:
		to += TAU
	if to < from:
		to += TAU
	var start := (u * cos(from) + v * sin(from)).normalized()
	var stop := (u * cos(to) + v * sin(to)).normalized()
	return _drape_slerp(shape, start, stop)


func _on_bisector(direction: Vector3, normal: Vector3) -> Vector3:
	var axis := normal.normalized()
	var on := direction - axis * direction.dot(axis)
	if on.length_squared() < 0.0000001:
		return direction.normalized()
	return on.normalized()


func _drape_slerp(shape: PlanetShape, a: Vector3, b: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var arc := a.angle_to(b) * shape.radius
	var pieces := maxi(1, int(ceili(arc / maxf(border_step, 1.0))))
	for piece in pieces + 1:
		var t := float(piece) / float(pieces)
		points.append(_surface_mark(shape, a.slerp(b, t)))
	return points


func _drape_chain(
		shape: PlanetShape,
		dirs: PackedVector3Array,
		closed: bool
	) -> PackedVector3Array:
	var points := PackedVector3Array()
	var count := dirs.size()
	if count < 2:
		return points
	var segments := count if closed else count - 1
	var step := maxf(border_step, 1.0)
	for index in segments:
		var a := dirs[index]
		var b := dirs[(index + 1) % count]
		var arc := a.angle_to(b) * shape.radius
		var pieces := maxi(1, int(ceili(arc / step)))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			points.append(_surface_mark(shape, a.slerp(b, t)))
	if not closed:
		points.append(_surface_mark(shape, dirs[count - 1]))
	return points


func _surface_mark(shape: PlanetShape, direction: Vector3) -> Vector3:
	var up := direction.normalized()
	return shape.surface_point(up) + up * border_lift


func _emit_ribbon(st: SurfaceTool, points: PackedVector3Array) -> void:
	var count := points.size()
	if count < 2:
		return
	for index in count - 1:
		var pa := points[index]
		var pb := points[index + 1]
		var chord := pb - pa
		if chord.length_squared() < 0.01:
			continue
		var up := ((pa + pb) * 0.5).normalized()
		var side := up.cross(chord)
		if side.length_squared() < 0.0001:
			continue
		side = side.normalized() * border_half_width
		st.add_vertex(pa - side)
		st.add_vertex(pa + side)
		st.add_vertex(pb + side)
		st.add_vertex(pa - side)
		st.add_vertex(pb + side)
		st.add_vertex(pb - side)


func _build_labels(planet: Planet) -> void:
	for label in _labels:
		if is_instance_valid(label):
			label.queue_free()
	_labels.clear()
	var shape := planet.shape
	for patch in partition.patches:
		var up := patch.direction.normalized()
		var at := shape.surface_point(up)
		var height := clampf(patch.span * 0.14, 48.0, 220.0)
		var label := Label3D.new()
		label.text = patch.name.to_upper()
		label.font = FONT
		label.font_size = 42
		label.pixel_size = height / 42.0
		label.modulate = PALETTE.accent
		label.outline_size = 12
		label.outline_modulate = PALETTE.ink
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = false
		label.visible = false
		label.position = at + up * (height * 0.35 + 24.0)
		add_child(label)
		_labels.append(label)
