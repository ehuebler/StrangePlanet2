class_name CityBuilding
extends Node3D

## One painted lot that can take damage, shear, and collapse.
##
## Health comes from the fabric record. Hits flash red; at 60% the hull
## cracks and smokes; skyscrapers lose their crown at 50%; death is a nuke-like
## fireball (no mushroom) and a smoldering stump that can catch neighbours.

const HURT_RATIO := 0.60
const SHEAR_RATIO := 0.50
const SMOKE_HURT := 28
const SMOKE_DEAD := 96

static var _smoke_tex: Texture2D

var lot_index := -1
var _city: PatchCity
var _shape: PlanetShape
var _lot: Dictionary = {}
var _health := 0.0
var _max_health := 1.0
var _hull: MeshInstance3D
var _glass: MeshInstance3D
var _body: StaticBody3D
var _collider: CollisionShape3D
var _hurt_smoke: GPUParticles3D
var _dead_smoke: GPUParticles3D
var _embers: GPUParticles3D
var _hurt := false
var _sheared := false
var _dead := false
var _collapsing := false
var _wall_mat: ShaderMaterial
var _glass_mat: ShaderMaterial


func setup(city: PatchCity, index: int, lot: Dictionary, shape: PlanetShape) -> void:
	_city = city
	lot_index = index
	_lot = lot
	_shape = shape
	_max_health = maxf(float(lot.get("max_health", 80.0)), 1.0)
	_health = clampf(float(lot.get("health", _max_health)), 0.0, _max_health)
	name = "Building_%d" % index
	_rebuild_visual()
	_make_collision()
	_apply_visual_layers()


func rebind(city: PatchCity, index: int, lot: Dictionary, shape: PlanetShape) -> void:
	_city = city
	lot_index = index
	_lot = lot
	_shape = shape
	_max_health = maxf(float(lot.get("max_health", 80.0)), 1.0)
	_health = clampf(float(lot.get("health", _max_health)), 0.0, _max_health)
	_hull = get_node_or_null("Hull") as MeshInstance3D
	_glass = get_node_or_null("Glass") as MeshInstance3D
	_body = get_node_or_null("Body") as StaticBody3D
	if is_instance_valid(_body) and _body.get_child_count() > 0:
		_collider = _body.get_child(0) as CollisionShape3D
	if is_instance_valid(_body):
		_body.collision_layer = 1
		_body.collision_mask = 1
	elif _city != null and _shape != null:
		_make_collision()
	if city != null:
		if is_instance_valid(_hull):
			_wall_mat = _paint_wall_material(is_large())
			_hull.material_override = _wall_mat
		if is_instance_valid(_glass):
			_glass_mat = city.window_material_for(is_large())
			_glass.material_override = _glass_mat
		if is_instance_valid(_wall_mat):
			city.stamp_lamp_on_wall(_wall_mat)
	_apply_visual_layers()


func health() -> float:
	return _health


func max_health() -> float:
	return _max_health


func is_hurt() -> bool:
	return _hurt


func is_sheared() -> bool:
	return _sheared


func is_wrecked() -> bool:
	return _dead


func is_large() -> bool:
	return int(_lot.get("typology", 0)) >= PatchCity.TYPE_TOWER


func typology() -> int:
	return int(_lot.get("typology", 0))


func original_stories() -> float:
	return float(_lot.get("stories", 2.0))


func hull_mesh() -> Mesh:
	return _hull.mesh if is_instance_valid(_hull) else null


func glass_mesh() -> Mesh:
	return _glass.mesh if is_instance_valid(_glass) else null


func has_hit_flash() -> bool:
	if not is_instance_valid(_hull):
		return false
	for child in _hull.get_children():
		if child is CombatantFlashOverlay:
			return true
	return false


func has_smoke() -> bool:
	return (is_instance_valid(_hurt_smoke) and _hurt_smoke.emitting) \
		or (is_instance_valid(_dead_smoke) and _dead_smoke.emitting)


func combat_position() -> Vector3:
	var local := _mark_at(_visual_stories() * 0.5)
	if _city != null and _city.is_inside_tree():
		return _city.global_transform * local
	return local


func combat_radius() -> float:
	return maxf(maxf(float(_lot.get("width", 8.0)), float(_lot.get("depth", 8.0))) * 0.55, 2.4)


func base_point() -> Vector3:
	return _to_world(_mark_at(0.0))


func roof_point() -> Vector3:
	return _to_world(_mark_at(_visual_stories()))


func nearest_hit_point(point: Vector3) -> Vector3:
	var core := _closest_on_core(point)
	var offset := point - core
	var away := offset.length()
	var radius := combat_radius()
	if away <= 0.0001:
		return core
	if away <= radius:
		return point
	return core + offset * (radius / away)


static func from_collider(collider: Object) -> CityBuilding:
	var walk := collider as Node
	while walk != null:
		if walk is CityBuilding:
			return walk as CityBuilding
		walk = walk.get_parent()
	return null


func apply_hit(hit: DamageHit) -> float:
	if _dead or hit == null:
		return 0.0
	if not hit.reaches_segment(base_point(), roof_point(), combat_radius()):
		return 0.0
	var at := nearest_hit_point(hit.centre())
	var dealt := hit.damage_at(at)
	if dealt <= 0.0:
		return 0.0
	var before := _health
	_health = maxf(_health - dealt, 0.0)
	_lot["health"] = _health
	_sync_place()
	if _health < before and not _dead:
		_flash()
	_refresh_state()
	return before - _health


func explode_radius() -> float:
	var span := maxf(float(_lot.get("width", 8.0)), float(_lot.get("depth", 8.0)))
	var stories := float(_lot.get("stories", 2.0))
	return clampf(span * 0.72 + stories * 0.55, 6.0, 86.0)


func explode_damage() -> float:
	return _max_health * 0.32 + float(_lot.get("stories", 2.0)) * 14.0


func collapse_hit() -> DamageHit:
	var hit := DamageHit.area(combat_position(), explode_radius(), explode_damage(), 0.85)
	hit.kind = DamageHit.Kind.AREA
	hit.faction = DamageHit.Faction.NEUTRAL
	hit.ability_id = "building_collapse"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.radial_impulse = explode_radius() * 0.85
	hit.radial_lift = explode_radius() * 0.28
	return hit


func _refresh_state() -> void:
	if _dead:
		return
	var ratio := _health / _max_health
	if ratio <= 0.0:
		_collapse()
		return
	var sky := _is_sky()
	if sky and ratio <= SHEAR_RATIO and not _sheared:
		_sheared = true
		_hurt = true
		_rebuild_visual()
		_make_collision()
		_start_hurt_smoke()
		return
	if ratio <= HURT_RATIO and not _hurt:
		_hurt = true
		_set_ruin(1.0)
		_start_hurt_smoke()


func _is_sky() -> bool:
	return int(_lot.get("typology", 0)) >= PatchCity.TYPE_SKY or bool(_lot.get("mega", false))


func _visual_stories() -> float:
	var stories := float(_lot.get("stories", 2.0))
	if _dead:
		return maxf(stories * 0.18, 0.55)
	if _sheared:
		return stories * 0.48
	return stories


func _collapse() -> void:
	if _dead:
		return
	_dead = true
	_collapsing = true
	_hurt = true
	_sheared = true
	_health = 0.0
	_lot["health"] = 0.0
	_sync_place()
	_play_blasts()
	_rebuild_visual()
	_make_collision()
	_start_dead_smoke()
	if is_instance_valid(_glass):
		_glass.visible = false
	_collapsing = false
	if _city != null:
		_city.queue_building_blast(self)


func _play_blasts() -> void:
	if _city == null:
		return
	var host: Node = _city
	var world := DamageHit.game_world_of(_city)
	if world != null:
		host = world
	var at := combat_position()
	var up := at.normalized() if at.length_squared() > 0.01 else Vector3.UP
	var rise := _visual_stories() * 3.15
	var count := 1
	if int(_lot.get("typology", 0)) >= PatchCity.TYPE_TOWER:
		count = 2
	if _is_sky():
		count = clampi(int(round(float(_lot.get("stories", 20.0)) / 10.0)), 3, 6)
	var radius := explode_radius() * 0.42
	var tint := Color(1.0, 0.62, 0.28)
	for index in count:
		var t := (float(index) + 0.5) / float(count)
		var spot := at + up * (rise * t)
		EnergyExplosion.burst(
			host,
			spot,
			radius * (1.15 if index == 0 else 0.72),
			tint,
			0.55,
			true,
			true,
			false)


func refresh_facade() -> void:
	_rebuild_visual()


func set_night(night: float) -> void:
	if _wall_mat != null:
		_wall_mat.set_shader_parameter(&"night", night)
	if _glass_mat != null:
		_glass_mat.set_shader_parameter(&"night", night)


func uses_authored_design() -> bool:
	return not _dead and not _sheared and _city != null and _city.lot_has_design(_lot)


func _rebuild_visual() -> void:
	if _city == null or _shape == null:
		return
	var hull_st := SurfaceTool.new()
	var glass_st := SurfaceTool.new()
	hull_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	glass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var row: Dictionary = _lot.duplicate()
	var large := is_large()
	if _dead:
		row["stories"] = _visual_stories()
		row["ruin_wreck"] = true
		row["ruin_jagged"] = true
		row["variant"] = PatchCity.VARIANT_RECT
	elif _sheared:
		row["stories"] = _visual_stories()
		row["ruin_jagged"] = true
		row["variant"] = PatchCity.VARIANT_RECT
	var used_authored := false
	if uses_authored_design():
		used_authored = _city._emit_authored_lot(hull_st, _shape, row, true)
		if used_authored:
			_city._emit_authored_glass(glass_st, _shape, row)
			if not _dead:
				_city._dress_authored_neon(hull_st, _shape, row, large)
	if not used_authored:
		_city._emit_lot_box(hull_st, _shape, row, true)
		if not _dead:
			_city._dress_lot_facade(hull_st, glass_st, _shape, row, large)
	var hull_mesh := hull_st.commit()
	if not is_instance_valid(_hull):
		_hull = MeshInstance3D.new()
		_hull.name = "Hull"
		_hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(_hull)
	_hull.mesh = hull_mesh
	_wall_mat = _authored_wall_material(large) if used_authored else _variant_wall_material(large)
	_hull.material_override = _wall_mat
	if _city != null:
		_city.stamp_lamp_on_wall(_wall_mat)
	_apply_visual_layers()
	if _hurt or _dead:
		_set_ruin(1.0 if _dead else 0.82)
	var glass_mesh := glass_st.commit()
	if glass_mesh.get_surface_count() > 0:
		if not is_instance_valid(_glass):
			_glass = MeshInstance3D.new()
			_glass.name = "Glass"
			_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_glass)
		_glass.mesh = glass_mesh
		_glass_mat = _city.window_material_for(large)
		_glass.material_override = _glass_mat
		_glass.visible = not _dead
	elif is_instance_valid(_glass):
		_glass.visible = false


func wall_material() -> ShaderMaterial:
	return _wall_mat


func _apply_visual_layers() -> void:
	var mask := PatchCity.BUILDING_VISUAL_LAYER
	if is_instance_valid(_hull):
		_hull.layers = mask
	if is_instance_valid(_glass):
		_glass.layers = mask


func _paint_wall_material(large: bool) -> ShaderMaterial:
	if uses_authored_design():
		return _authored_wall_material(large)
	return _variant_wall_material(large)


func _authored_wall_material(large: bool) -> ShaderMaterial:
	var material := _city.wall_material_for(large).duplicate() as ShaderMaterial
	var design := String(_lot.get("design", ""))
	var style := CityBuildingCatalog.paint_style_name(_lot)
	var paint := CityBuildingCatalog.paint_texture(design, style)
	if paint != null:
		material.set_shader_parameter(&"paint_tex", paint)
		material.set_shader_parameter(&"use_paint", 1.0)
	return material


func _variant_wall_material(large: bool) -> ShaderMaterial:
	var material := _city.wall_material_for(large).duplicate() as ShaderMaterial
	var variant := int(_lot.get("variant", 0))
	var style := CityBuildingCatalog.variant_paint_style_name(_lot)
	var paint := CityBuildingCatalog.variant_paint_texture(variant, style)
	if paint != null:
		material.set_shader_parameter(&"paint_tex", paint)
		material.set_shader_parameter(&"use_paint", 1.0)
	return material


func _set_ruin(amount: float) -> void:
	if is_instance_valid(_hull):
		_hull.set_instance_shader_parameter(&"ruin", amount)


func _flash() -> void:
	if is_instance_valid(_hull):
		CombatantFlash.flash(_hull)


func _make_collision() -> void:
	if _city == null or _shape == null:
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
	var hull := _hull.mesh if is_instance_valid(_hull) else null
	if hull != null and hull.get_surface_count() > 0:
		var shape := hull.create_trimesh_shape()
		if shape != null:
			if shape is ConcavePolygonShape3D:
				(shape as ConcavePolygonShape3D).backface_collision = true
			_collider.shape = shape
			_body.transform = Transform3D.IDENTITY
			return
	_collider.shape = _lot_box_shape()
	_body.transform = _lot_box_xform()


func _start_hurt_smoke() -> void:
	if is_instance_valid(_hurt_smoke):
		_hurt_smoke.emitting = true
		_place_smoke(_hurt_smoke, 0.92)
		_hurt_smoke.restart()
		return
	_hurt_smoke = _make_smoke(SMOKE_HURT, 9.0, 6.5, Color(0.42, 0.38, 0.34, 0.82))
	add_child(_hurt_smoke)
	_place_smoke(_hurt_smoke, 0.92)
	_hurt_smoke.restart()


func _start_dead_smoke() -> void:
	if is_instance_valid(_hurt_smoke):
		_hurt_smoke.emitting = false
	if not is_instance_valid(_dead_smoke):
		_dead_smoke = _make_smoke(SMOKE_DEAD, 16.0, 11.0, Color(0.28, 0.26, 0.24, 0.9))
		add_child(_dead_smoke)
	_dead_smoke.emitting = true
	_place_smoke(_dead_smoke, 1.05)
	_dead_smoke.restart()
	if not is_instance_valid(_embers):
		_embers = _make_smoke(22, 4.8, 3.4, Color(1.0, 0.42, 0.1, 1.0), true)
		add_child(_embers)
	_embers.emitting = true
	_place_smoke(_embers, 0.55)
	_embers.restart()


func _place_smoke(smoke: GPUParticles3D, along_height: float) -> void:
	smoke.transform = _smoke_xform(along_height)


func _to_world(local: Vector3) -> Vector3:
	if _city != null and _city.is_inside_tree():
		return _city.global_transform * local
	return local


func _closest_on_core(point: Vector3) -> Vector3:
	var a := base_point()
	var b := roof_point()
	var along := b - a
	var run := along.length_squared()
	if run < 0.0001:
		return a
	return a + along * clampf((point - a).dot(along) / run, 0.0, 1.0)


func _lot_box_shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	var height := maxf(_visual_stories() * 3.15, 1.2)
	box.size = Vector3(
		maxf(float(_lot.get("width", 8.0)), 1.6),
		height,
		maxf(float(_lot.get("depth", 8.0)), 1.6))
	return box


func _lot_box_xform() -> Transform3D:
	var height := maxf(_visual_stories() * 3.15, 1.2)
	var centre: Vector2 = _lot.get("centre", Vector2.ZERO)
	var along: Vector2 = _lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var up := _city._from_uv(centre).normalized()
	var origin := _city._deck_mark(_shape, up, PatchCity.STREET_LIFT) + up * (height * 0.5)
	var east := _city._from_uv(centre + along).normalized() - up
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east)
	if north.length_squared() < 0.0001:
		north = Vector3.FORWARD
	north = north.normalized()
	east = north.cross(up).normalized()
	return Transform3D(Basis(east, up, north), origin)


func _mark_at(along_stories: float) -> Vector3:
	var centre: Vector2 = _lot.get("centre", Vector2.ZERO)
	var up := _city._from_uv(centre).normalized()
	return _city._deck_mark(_shape, up, PatchCity.STREET_LIFT) + up * (along_stories * 3.15)


func _smoke_xform(along_height: float) -> Transform3D:
	var centre: Vector2 = _lot.get("centre", Vector2.ZERO)
	var up := _city._from_uv(centre).normalized()
	var origin := _mark_at(_visual_stories() * along_height)
	var east := _city._from_uv(centre + Vector2(1.0, 0.0)).normalized() - up
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east)
	if north.length_squared() < 0.0001:
		north = Vector3.FORWARD
	north = north.normalized()
	east = north.cross(up).normalized()
	return Transform3D(Basis(east, up, north), origin)


func _make_smoke(
		amount: int,
		life: float,
		lift: float,
		tint: Color,
		embers := false
	) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.amount = amount
	smoke.lifetime = life
	smoke.preprocess = minf(life * 0.55, 8.0)
	smoke.randomness = 0.62
	smoke.local_coords = true
	smoke.fixed_fps = 24
	smoke.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	var span := maxf(maxf(float(_lot.get("width", 8.0)), float(_lot.get("depth", 8.0))), 6.0)
	smoke.visibility_aabb = AABB(
		Vector3(-span * 2.4, -6.0, -span * 2.4),
		Vector3(span * 4.8, 90.0, span * 4.8))
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = clampf(span * (0.08 if embers else 0.22), 0.6, 7.0)
	process.direction = Vector3.UP
	process.spread = 22.0 if embers else 16.0
	process.initial_velocity_min = lift * 0.35
	process.initial_velocity_max = lift
	process.gravity = Vector3(0.0, 1.4 if embers else 2.2, 0.0)
	process.damping_min = 0.18
	process.damping_max = 0.55
	process.scale_min = 0.45 if embers else 3.2
	process.scale_max = 1.1 if embers else 8.5
	process.color = Color.WHITE
	process.color_ramp = _smoke_ramp(tint, embers)
	smoke.process_material = process
	smoke.draw_pass_1 = _smoke_quad(tint, embers)
	smoke.emitting = true
	return smoke


func _smoke_ramp(tint: Color, embers: bool) -> GradientTexture1D:
	var fade := Gradient.new()
	if embers:
		fade.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
		fade.colors = PackedColorArray([
			Color(tint.r, tint.g, tint.b, 0.0),
			Color(tint.r, tint.g, tint.b, 1.0),
			Color(tint.r * 0.7, tint.g * 0.35, tint.b * 0.08, 0.7),
			Color(0.08, 0.05, 0.04, 0.0),
		])
	else:
		fade.offsets = PackedFloat32Array([0.0, 0.08, 0.58, 1.0])
		fade.colors = PackedColorArray([
			Color(tint.r, tint.g, tint.b, 0.0),
			Color(tint.r, tint.g, tint.b, tint.a),
			Color(tint.r * 0.72, tint.g * 0.72, tint.b * 0.72, tint.a * 0.55),
			Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 0.0),
		])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	return ramp


func _smoke_quad(tint: Color, embers: bool) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _smoke_texture()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.disable_receive_shadows = true
	if embers:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = 4.2
	var quad := QuadMesh.new()
	quad.size = Vector2(1.15, 1.15) if not embers else Vector2(0.42, 0.42)
	quad.material = material
	return quad


func _smoke_texture() -> Texture2D:
	if _smoke_tex != null:
		return _smoke_tex
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / 64.0 * 2.0 - Vector2.ONE
			var radius_now := point.length()
			var billow := 0.84 + sin(point.x * 9.0 + point.y * 5.0) * 0.05 \
				+ sin(point.x * 17.0 - point.y * 13.0) * 0.03
			var alpha := 1.0 - smoothstep(0.28, billow, radius_now)
			alpha *= smoothstep(1.0, 0.38, radius_now)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_smoke_tex = ImageTexture.create_from_image(image)
	return _smoke_tex


func _sync_place() -> void:
	if _city == null:
		return
	for place in _city.places:
		if place.lot_index != lot_index:
			continue
		place.health = _health
		place.max_health = _max_health
		return
