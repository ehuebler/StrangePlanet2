extends RefCounted

## Grass and a little short cover, grown with the terrain chunk that owns them.
##
## GroundCover no longer streams fill species. The lawn has to live somewhere, so
## the finest map tiles — the planet chunks underfoot — carry a MultiMesh of
## grass and a couple of small plants, built on the same worker as the mesh and
## thrown away with it. Trees and other skyline cover still stream on their own.

const STRIDE := GroundCover.STRIDE
const COLOR := GroundCover.COLOR
const RANK := GroundCover.RANK

const GRASS := preload("res://game/props/grass_species.tres")
const FLOWER := preload("res://game/props/purple_flower.tres")
const FEATHER := preload("res://game/props/biomes/grass_feather.tres")

## Blades a square metre on a finest chunk. Lower than the streamed lawn: the
## terrain already paints grass, and this is the 3D layer on top of that paint.
const GRASS_DENSITY := 2.2
const FLOWER_DENSITY := 0.045
const FEATHER_DENSITY := 0.03
const RUSH_RAISES := 1
const IDLE_RAISES := 2

static var _prepared := false
static var _jobs: Array = []
static var _pool: Array[MultiMeshInstance3D] = []


static func prepare() -> void:
	if _prepared:
		return
	GRASS.prepare()
	FLOWER.prepare()
	FEATHER.prepare()
	_prepared = true


static func should_bake(depth: int, max_depth: int) -> bool:
	return depth >= max_depth


static func bake(shape: PlanetShape, chunk: Variant, radius: float,
		max_depth: int, axes: Array, extras := true) -> void:
	chunk.flora_layers.clear()
	if shape == null or not bool(chunk.flora_wanted) \
			or not should_bake(int(chunk.depth), max_depth):
		return
	prepare()
	chunk.flora_layers.append(_scatter(shape, chunk, axes, radius, GRASS,
		GRASS_DENSITY, 1))
	if not extras:
		return
	chunk.flora_layers.append(_scatter(shape, chunk, axes, radius, FLOWER,
		FLOWER_DENSITY, 2))
	chunk.flora_layers.append(_scatter(shape, chunk, axes, radius, FEATHER,
		FEATHER_DENSITY, 3))


## Holds finished buffers until the main thread has a free upload slot. Terrain
## attach used to raise every layer the same frame the mesh landed, which at
## speed stacked a dozen MultiMesh uploads on top of a dozen chunk attaches.
static func enqueue(host: MeshInstance3D, chunk: Variant) -> void:
	if host == null or chunk.flora_layers.is_empty():
		return
	prepare()
	var plants: Array[PlantSpecies] = [GRASS, FLOWER, FEATHER]
	for index in mini(chunk.flora_layers.size(), plants.size()):
		var buffer: PackedFloat32Array = chunk.flora_layers[index]
		if buffer.is_empty():
			continue
		_jobs.append({
			"host": host,
			"buffer": buffer,
			"plant": plants[index],
		})
	chunk.flora_layers.clear()


static func reclaim(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	var kept: Array = []
	for job: Dictionary in _jobs:
		if job.get("host") != host:
			kept.append(job)
	_jobs = kept
	for child in host.get_children():
		var stand := child as MultiMeshInstance3D
		if stand == null or not stand.name.begins_with("BakedFlora_"):
			continue
		host.remove_child(stand)
		stand.visible = false
		if stand.multimesh != null:
			stand.multimesh.instance_count = 0
		_pool.append(stand)


static func pump(rushing := false) -> void:
	var left := RUSH_RAISES if rushing else IDLE_RAISES
	while left > 0 and not _jobs.is_empty():
		var job: Dictionary = _jobs.pop_front()
		var host := job.get("host") as MeshInstance3D
		if host == null or not is_instance_valid(host):
			continue
		_raise_one(host, job.get("plant") as PlantSpecies,
			job.get("buffer") as PackedFloat32Array)
		left -= 1


static func _raise_one(host: MeshInstance3D, plant: PlantSpecies,
		buffer: PackedFloat32Array) -> void:
	if plant == null or buffer.is_empty():
		return
	var stand: MultiMeshInstance3D = null
	if not _pool.is_empty():
		stand = _pool.pop_back()
	if stand == null:
		stand = MultiMeshInstance3D.new()
		stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stand.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		stand.physics_interpolation_mode = \
			Node.PHYSICS_INTERPOLATION_MODE_OFF
	stand.name = "BakedFlora_%s" % plant.resource_name
	var multimesh := stand.multimesh
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
	multimesh.instance_count = buffer.size() / STRIDE
	multimesh.buffer = buffer
	multimesh.mesh = plant.near_mesh()
	stand.multimesh = multimesh
	stand.material_override = plant.near_material()
	stand.extra_cull_margin = plant.height * 1.5
	stand.visible = true
	if stand.get_parent() != host:
		if stand.get_parent() != null:
			stand.get_parent().remove_child(stand)
		host.add_child(stand, false, Node.INTERNAL_MODE_BACK)


static func instance_count(planet: Node) -> int:
	var standing := 0
	if planet == null:
		return 0
	for node in planet.find_children("BakedFlora_*", "MultiMeshInstance3D",
			true, false):
		var stand := node as MultiMeshInstance3D
		if stand != null and stand.multimesh != null:
			standing += stand.multimesh.instance_count
	return standing


static func _scatter(shape: PlanetShape, chunk: Variant, axes: Array,
		radius: float, plant: PlantSpecies, density: float, salt: int) \
		-> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	var origin := chunk.origin as Vector3
	var arc := float(chunk.arc)
	rng.seed = hash(Vector3i(
		int(origin.x * 10.0),
		int(origin.z * 10.0) ^ salt,
		plant.random_seed))
	var area := arc * arc
	var clump := maxi(plant.clump_count, 1)
	var tries := maxi(int(round(density * area / float(clump))), 0)
	if tries <= 0:
		return PackedFloat32Array()
	var spacing := maxf(arc / 16.0, 1.2)
	var buffer := PackedFloat32Array()
	buffer.resize(tries * clump * STRIDE)
	var grown := 0
	for _try in tries:
		var at := _direction(axes, chunk, rng.randf(), rng.randf())
		if PatchCity.flora_covers(at):
			continue
		var growth := _growth(shape, plant, at, radius, spacing)
		if is_nan(growth.w):
			continue
		var tint := Color(growth.x, growth.y, growth.z, 1.0) \
			if plant.terrain_tint else Color.WHITE
		var east := at.cross(Vector3.UP if absf(at.y) < 0.9 else Vector3.RIGHT).normalized()
		var north := at.cross(east)
		for member in clump:
			var up := at
			var ground := growth.w
			if member > 0:
				var spin := rng.randf() * TAU
				var out := sqrt(rng.randf()) * plant.clump_radius / radius
				up = (at + (east * cos(spin) + north * sin(spin)) * out).normalized()
			var tall := plant.height * (1.0 + clampf(
				rng.randfn(0.0, plant.height_variation * 0.5),
				-plant.height_variation, plant.height_variation))
			var tipped := _upright(up)
			if plant.tilt > 0.0:
				tipped = Basis(tipped.z,
					deg_to_rad(rng.randfn(0.0, plant.tilt * 0.5))) * tipped
			var stood := Transform3D(
				(Basis(up, rng.randf() * TAU) * tipped)
					.scaled(Vector3(plant.width_scale, 1.0, plant.width_scale)
						* plant.scale_for(tall)),
				up * (radius + ground - plant.ground_sink_for(tall))
					- origin)
			_write(buffer, grown, stood, rng, tint)
			grown += 1
	buffer.resize(grown * STRIDE)
	var full := maxf(float(grown), 1.0)
	for index in grown:
		buffer[index * STRIDE + RANK] = (float(index) + 0.5) / full
	return buffer


static func _direction(axes: Array, chunk: Variant, u: float, v: float) \
		-> Vector3:
	var offset := chunk.offset as Vector2
	var size := float(chunk.size)
	var face_u := offset.x + u * size
	var face_v := offset.y + v * size
	return ((axes[0] as Vector3)
		+ (axes[1] as Vector3) * tan(face_u * PI * 0.25)
		+ (axes[2] as Vector3) * tan(face_v * PI * 0.25)).normalized()


static func _growth(shape: PlanetShape, plant: PlantSpecies, at: Vector3,
		_radius: float, spacing: float) -> Vector4:
	var here := shape.elevation(at, spacing)
	if here < plant.above_water or here > plant.below:
		return Vector4(NAN, NAN, NAN, NAN)
	var wet := shape.sample(at)
	if float(wet.get("river", 0.0)) > 0.0 or float(wet.get("lake", 0.0)) > 0.0:
		return Vector4(NAN, NAN, NAN, NAN)
	var arid := float(wet.get("arid", 0.0))
	var frozen := shape.frost(at)
	if arid < plant.minimum_arid or arid > plant.maximum_arid:
		return Vector4(NAN, NAN, NAN, NAN)
	if frozen < plant.minimum_frost or frozen > plant.maximum_frost:
		return Vector4(NAN, NAN, NAN, NAN)
	if not plant.terrain_tint:
		return Vector4(1.0, 1.0, 1.0, here)
	var tint := shape.color_at(at, here, at)
	return Vector4(tint.r, tint.g, tint.b, here)


static func _upright(up: Vector3) -> Basis:
	var hint := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
	var forward := (hint - up * hint.dot(up)).normalized()
	return Basis(up.cross(forward), up, forward)


static func _write(buffer: PackedFloat32Array, index: int, stood: Transform3D,
		rng: RandomNumberGenerator, tint: Color) -> void:
	var at := index * STRIDE
	var basis := stood.basis
	var origin := stood.origin
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
	buffer[at + COLOR] = tint.r
	buffer[at + COLOR + 1] = tint.g
	buffer[at + COLOR + 2] = tint.b
	buffer[at + COLOR + 3] = tint.a
	buffer[at + RANK + 1] = rng.randf()
	buffer[at + RANK + 2] = rng.randf()
	buffer[at + RANK + 3] = rng.randf()
