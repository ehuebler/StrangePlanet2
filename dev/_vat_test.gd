extends Node3D

## Structural VAT/ecosystem harness.
##
##     & $godot --path . dev/_vat_test.tscn
##
## It deliberately takes no screenshots. This checks the contracts that are
## objective (asset topology, texture precision, streamed placement and water
## clearance); density, glow colour and the feel of the motion remain a short
## in-game visual check.

const WORLD := preload("res://game/world.tscn")

var _failed := false
var _planet: Planet
var _flowers: GroundCover
var _grass: GroundCover
var _fish: FishSchool
var _player: OnlinePlayer


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "VAT Test", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	# This harness checks the grass VAT contract on streamed instances. Play
	# bakes that layer onto terrain chunks and leaves stream_fill off.
	GroundCover.stream_fill = true
	var world := WORLD.instantiate()
	add_child(world)
	for _frame in 80:
		await get_tree().process_frame
		_find_systems(world)
		if _planet != null and _flowers != null and _grass != null and _fish != null \
				and _player != null:
			break
	_find_systems(world)
	_require(_planet != null, "world has a planet")
	_require(_flowers != null, "world has LandingFlowers")
	_require(_grass != null, "world has GlobalGrass")
	_require(_fish != null, "world has FishSchools")
	_require(_player != null, "world spawned a viewer")
	if _failed:
		get_tree().quit(1)
		return
	_park_viewer_on_grass()
	# Schools are sited a couple per frame around wherever the viewer is, rather
	# than all at once from a fixed anchor, so what is waited for is a field that
	# has found the sea — not one that has placed every school it owns. Some
	# never will: a school is only ever sited over water of its own depth, and
	# how much of that is within reach depends on where the viewer parked.
	for _frame in 480:
		await get_tree().process_frame
		if _fish.sited_schools() >= 8 \
				and _grass.grown() >= 100 and _grass.settling() == 0:
			break

	_test_grid()
	_test_species(_flowers.species[0], "flower")
	_test_species(_grass.species[0], "grass")
	_test_static(_fish.model, "fish")
	_test_clip(_fish.vat, _mesh_from(_fish.model), "fish")
	_grass._place_glow_lights(_player.global_position)
	print("VAT_TEST_STREAM process=%s reach=%.1f wanted=%d tiles=%d viewer=%s player=%s" % [
		_grass.is_processing(), _grass._reach, _grass._wanted.size(),
		_grass.tiles(), _planet.viewer_position(), _player])
	_test_grass_placement()
	_test_fish_placement()
	if "--profile" in OS.get_cmdline_user_args():
		await _profile_scale()
	print("VAT_TEST_COUNTS flower=%d grass=%d fish=%d grass_tiles=%d" % [
		_flowers.grown(), _grass.grown(), _fish.fish_transforms().size(),
		_grass.tiles()])
	print("VAT_TEST_RESULT %s" % ("FAIL" if _failed else "PASS"))
	GroundCover.stream_fill = false
	get_tree().quit(1 if _failed else 0)


func _find_systems(world: Node) -> void:
	if _planet == null:
		_planet = world.find_child("Planet", true, false) as Planet
	if _flowers == null:
		_flowers = world.find_child("LandingFlowers", true, false) as GroundCover
	if _grass == null:
		_grass = world.find_child("GlobalGrass", true, false) as GroundCover
	if _fish == null:
		_fish = world.find_child("FishSchools", true, false) as FishSchool
	if _player == null:
		_player = get_tree().get_first_node_in_group("network_players") as OnlinePlayer


func _park_viewer_on_grass() -> void:
	var origin := _flowers.direction.normalized()
	var east := origin.cross(
		Vector3.UP if absf(origin.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := origin.cross(east)
	var plant := _grass.species[0]
	var chosen := origin
	var elevation := _planet.shape.elevation(chosen, _planet.finest_spacing())
	for ring in range(0, 401, 20):
		for spoke in 24:
			var angle := TAU * float(spoke) / 24.0
			var offset := (east * cos(angle) + north * sin(angle)) * float(ring)
			var candidate := (origin + offset / _planet.shape.radius).normalized()
			var growth := _grass._growth(plant, candidate)
			if not is_nan(growth.w):
				chosen = candidate
				elevation = growth.w
				_player.global_position = _planet.to_global(
					chosen * (_planet.shape.radius + elevation + 1.5))
				_player.velocity = Vector3.ZERO
				_player.process_mode = Node.PROCESS_MODE_DISABLED
				return
	_player.global_position = _planet.to_global(
		chosen * (_planet.shape.radius + elevation + 1.5))
	_player.velocity = Vector3.ZERO
	_player.process_mode = Node.PROCESS_MODE_DISABLED


func _test_grid() -> void:
	var grid := SphericalCoverGrid.new(_planet.shape.radius, _grass.tile_size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8934
	var worst := 0.0
	for _sample in 500:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var key := grid.key_for(direction)
		var centre := grid.centre(key)
		_require(grid.key_for(centre) == key, "cube-sphere cell round trips")
		worst = maxf(worst, direction.angle_to(centre) * grid.radius)
	_require(worst < _grass.tile_size * 1.8,
		"cube-sphere cells stay within their metre budget")
	print("VAT_TEST_GRID resolution=%d worst_offset=%.2fm" % [grid.resolution, worst])


func _test_species(plant: PlantSpecies, label: String) -> void:
	plant.prepare()
	_test_static(plant.model, "%s-near" % label)
	if plant.distant_model != null:
		_test_static(plant.distant_model, "%s-far" % label)
	_require(plant.vat != null, "%s has a near VAT" % label)
	if plant.vat != null:
		_test_clip(plant.vat, plant.near_mesh(), "%s-near" % label)
	if plant.distant_vat != null:
		_test_clip(plant.distant_vat, plant.distant_mesh(), "%s-far" % label)
	if label == "flower":
		_require(plant.distant_vat != null, "flower has an independent far VAT")
		_require(plant.near_material() != plant.far_material(),
			"flower LODs use independent VAT materials")


func _test_clip(clip: VatClip, mesh: Mesh, label: String) -> void:
	if clip == null:
		return
	_require(clip.validate_mesh(mesh), "%s mesh matches VAT IDs" % label)
	var image := clip.positions.get_image()
	var greatest := 0.0
	for frame in range(1, int(clip.frame_count)):
		for vertex in range(0, clip.vertex_count, maxi(clip.vertex_count / 64, 1)):
			var x := vertex
			var first := image.get_pixel(x, 0)
			var later := image.get_pixel(x, frame)
			greatest = maxf(greatest, Vector3(first.r - later.r,
				first.g - later.g, first.b - later.b).length())
	_require(greatest > 0.00001, "%s VAT contains animated displacement" % label)
	var import_path := clip.positions.resource_path + ".import"
	var imported := FileAccess.get_file_as_string(import_path)
	_require("mipmaps/generate=false" in imported, "%s VAT has mipmaps disabled" % label)
	_require("compress/mode=0" in imported, "%s VAT uses lossless import" % label)
	print("VAT_TEST_CLIP %s vertices=%d frames=%d movement=%.6f" % [
		label, clip.vertex_count, int(clip.frame_count), greatest])


func _test_static(model: PackedScene, label: String) -> void:
	if model == null:
		_require(false, "%s has a static GLB" % label)
		return
	var scene := model.instantiate()
	_require(scene.find_children("*", "Skeleton3D", true, false).is_empty(),
		"%s GLB has no runtime skeleton" % label)
	_require(scene.find_children("*", "AnimationPlayer", true, false).is_empty(),
		"%s GLB has no imported animation" % label)
	scene.queue_free()


func _test_grass_placement() -> void:
	var transforms := _grass.standing()
	_require(transforms.size() >= 100, "streamed grass grows around the viewer")
	var plant := _grass.species[0]
	var checked := 0
	var misses := 0
	var step := maxi(transforms.size() / 128, 1)
	for index in range(0, transforms.size(), step):
		var local := _planet.to_local(transforms[index].origin)
		var growth := _grass._growth(plant, local.normalized())
		if is_nan(growth.w):
			misses += 1
		checked += 1
	_require(misses == 0, "grass instances stand only on grass-textured terrain")
	var tinted := false
	var strongest_glow := 0.0
	for tile in _grass._tiles.values():
		for stand in tile.stands:
			if stand == null:
				continue
			var multimesh: MultiMesh = stand.multimesh
			var raw := multimesh.buffer
			for instance in multimesh.instance_count:
				var color := multimesh.get_instance_color(instance)
				tinted = tinted or not color.is_equal_approx(Color.WHITE)
				strongest_glow = maxf(strongest_glow,
					raw[instance * 20 + 18])
	_require(tinted, "grass carries sampled terrain tint in instance colour")
	_require(strongest_glow > 0.5, "grass contains coherent glowing patches")
	_require(_grass._glow_lights.size() <= 6, "grass illumination uses at most six lights")
	var lit := 0
	for light in _grass._glow_lights:
		lit += 1 if light.visible else 0
	_require(lit > 0, "nearby glowing patches receive pooled ground lights")
	print("VAT_TEST_GRASS checked=%d biome_misses=%d glow=%.2f lights=%d" % [
		checked, misses, strongest_glow, lit])


func _test_fish_placement() -> void:
	var points := _fish.fish_transforms()
	# The seats are what the field owns; the transforms are only the schools that
	# have water under them at the moment. Both are worth checking, because a
	# field that has quietly stopped siting anything still owns all its seats.
	_require(_fish.seat_count() == _fish.instance_count,
		"fish instance count is exact")
	_require(not points.is_empty(), "fish schools found the sea near the viewer")
	if not points.is_empty():
		print("VAT_TEST_FISH_FIRST radius=%.2f origin=%s" % [
			points[0].origin.length(), points[0].origin])
	var shallowest := INF
	var least_clearance := INF
	var nearest_eye := INF
	var farthest_eye := 0.0
	# Against the viewer's ground track rather than Vacationer's Landing: the ring the
	# schools are sited in travels, and measuring from the shore would only be
	# asking whether the viewer had happened to stay next to it.
	var eye := _planet.viewer_position().normalized()
	for transform in points:
		var point := transform.origin
		var world_point := _planet.to_global(point)
		var depth := _planet.water.depth_at(world_point)
		var bed := _planet.shape.elevation(point.normalized(), _planet.finest_spacing())
		var clearance := point.length() - (_planet.shape.radius + bed)
		shallowest = minf(shallowest, depth)
		least_clearance = minf(least_clearance, clearance)
		var from_eye := point.normalized().angle_to(eye) * _planet.shape.radius
		nearest_eye = minf(nearest_eye, from_eye)
		farthest_eye = maxf(farthest_eye, from_eye)
	_require(shallowest >= _fish.minimum_depth - 0.05,
		"every fish stays below the water surface")
	_require(least_clearance >= _fish.seabed_clearance - 0.05,
		"every fish stays above the seabed")
	_require(farthest_eye <= _fish.scatter_radius * FishSchool.RETIRE_MARGIN
			+ _fish.school_orbit + 5.0,
		"fish schools stay inside the ring streamed around the viewer")
	_require(_fish.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"fish schools add no collision or AI bodies")
	print("VAT_TEST_FISH shallowest=%.2fm clearance=%.2fm viewer=%.0f..%.0fm sited=%d/%d" % [
		shallowest, least_clearance, nearest_eye, farthest_eye,
		_fish.sited_schools(), _fish.cluster_count])


func _profile_scale() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var old_max_fps := Engine.max_fps
	Engine.max_fps = 0
	var fish_source := _fish.find_child("Fish", true, false) as MultiMeshInstance3D
	var grass_source: MultiMeshInstance3D
	for tile_child in _grass.find_children("*", "MultiMeshInstance3D", true, false):
		grass_source = tile_child as MultiMeshInstance3D
		if grass_source.multimesh.instance_count > 0:
			break
	_grass.set_process(false)
	_flowers.set_process(false)
	_planet.set_process(false)
	_planet.visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0.0, 2.2, 8.0)
	camera.look_at(Vector3(0.0, 0.4, 0.0), Vector3.UP)
	camera.current = true
	RenderingServer.global_shader_parameter_set(&"planet_center",
		Vector3(0.0, -8000.0, 0.0))
	RenderingServer.global_shader_parameter_set(&"planet_radius", 8000.0)
	RenderingServer.global_shader_parameter_set(&"viewer_point", camera.global_position)
	if fish_source != null:
		await _profile_source("fish", fish_source, [1, 100, 1000])
	if grass_source != null:
		await _profile_source("grass", grass_source, [100, 1000, 10000])
	camera.queue_free()
	_planet.visible = true
	Engine.max_fps = old_max_fps


func _profile_source(label: String, source: MultiMeshInstance3D,
		counts: Array) -> void:
	var maximum := int(counts.max())
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = source.multimesh.use_colors
	multimesh.use_custom_data = true
	multimesh.instance_count = maximum
	multimesh.mesh = source.multimesh.mesh
	var stride := 20 if multimesh.use_colors else 16
	var buffer := PackedFloat32Array()
	buffer.resize(maximum * stride)
	var side := ceili(sqrt(float(maximum)))
	var authored := multimesh.mesh.get_aabb().size
	var scale := 1.15 / maxf(maxf(authored.x, authored.y), authored.z) \
		if label == "fish" else 0.29 / maxf(authored.y, 0.01)
	var spacing := 0.16 if label == "fish" else 0.055
	for index in maximum:
		var column := index % side
		var row := index / side
		var across := (float(column) - float(side - 1) * 0.5) * spacing
		var down := (float(row) - float(side - 1) * 0.5) * spacing
		var origin := Vector3(across, down + 0.6, 0.0) if label == "fish" \
			else Vector3(across, 0.0, down)
		_write_profile_instance(buffer, index, stride,
			Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), origin),
			multimesh.use_colors,
			Color(float(index % 97) / 97.0, float(index % 89) / 89.0, 0.5, 0.5))
	multimesh.buffer = buffer
	multimesh.custom_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 5.0, 8.0))
	var benchmark := MultiMeshInstance3D.new()
	benchmark.multimesh = multimesh
	benchmark.material_override = source.material_override
	benchmark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(benchmark)
	for count in counts:
		multimesh.visible_instance_count = int(count)
		for _warmup in 8:
			await get_tree().process_frame
		var began := Time.get_ticks_usec()
		for _frame in 30:
			await get_tree().process_frame
			RenderingServer.force_sync()
		var milliseconds := float(Time.get_ticks_usec() - began) / 30000.0
		print("VAT_TEST_PROFILE %s=%d %.3fms/frame" % [label, count, milliseconds])
	benchmark.queue_free()


func _write_profile_instance(buffer: PackedFloat32Array, index: int, stride: int,
		placed: Transform3D, with_color: bool, custom: Color) -> void:
	var at := index * stride
	var basis := placed.basis
	var origin := placed.origin
	buffer[at] = basis.x.x
	buffer[at + 1] = basis.y.x
	buffer[at + 2] = basis.z.x
	buffer[at + 3] = origin.x
	buffer[at + 4] = basis.x.y
	buffer[at + 5] = basis.y.y
	buffer[at + 6] = basis.z.y
	buffer[at + 7] = origin.y
	buffer[at + 8] = basis.x.z
	buffer[at + 9] = basis.y.z
	buffer[at + 10] = basis.z.z
	buffer[at + 11] = origin.z
	var custom_at := at + 12
	if with_color:
		buffer[at + 12] = 1.0
		buffer[at + 13] = 1.0
		buffer[at + 14] = 1.0
		buffer[at + 15] = 1.0
		custom_at += 4
	buffer[custom_at] = custom.r
	buffer[custom_at + 1] = custom.g
	buffer[custom_at + 2] = custom.b
	buffer[custom_at + 3] = custom.a


func _mesh_from(model: PackedScene) -> Mesh:
	if model == null:
		return null
	var scene := model.instantiate()
	var mesh: Mesh
	for found in scene.find_children("*", "MeshInstance3D", true, false):
		mesh = (found as MeshInstance3D).mesh
		if mesh != null:
			break
	scene.queue_free()
	return mesh


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("vat_test: %s" % message)
