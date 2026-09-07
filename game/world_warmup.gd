class_name WorldWarmup
extends Node3D

## Everything worth paying for before a game starts rather than during it.
##
## The world is never loaded when New Game is pressed — it has been rendering
## behind the title screen the whole time — so there is no scene to stream in.
## The home screen's small red/green bar measures this warm-up instead: work the
## first few minutes of play would otherwise do a piece at a time, in frames
## the player is trying to fly in:
##
##   - **Graphics pipelines.** A material costs a compile the first time it is
##     actually drawn, and from the spawn nine kilometres up almost nothing has
##     been. Every blade, tree, boulder, fish and lava surface on the planet is
##     therefore a stall waiting to happen, spread over the whole descent, which
##     is exactly the period the player is judging the game on. Drawing one of
##     each in an offscreen viewport moves all of them here.
##   - **Species preparation.** Pulling meshes out of a GLB and duplicating a
##     material per level of detail is main-thread work that a field otherwise
##     does the first time it is asked to grow something.
##   - **The terrain quadtree.** The planet refines towards whatever the camera
##     is looking at, and starting the moment it has been asked to is starting on
##     a coarse ball.
##
## Pipeline warm-up geometry has to be genuinely drawn to count, but it does not
## have to share the player's viewport. A small isolated SubViewport renders it
## offscreen so the title screen can remain unchanged while this runs.
##
## Nothing here changes the world. Everything it makes, it takes away again.

## Fired as each step finishes so the caller can draw a bar. The share is 0..1
## across the whole warm-up.
signal progressed(share: float, note: String)

## Draws submitted per batch, and how many frames each batch is left up.
##
## Two frames because a pipeline is created when the draw is submitted and the
## submission is a frame behind the call; one frame was enough on this machine
## and is not enough to rely on.
const BATCH_SIZE := 10
const BATCH_FRAMES := 2
## Longest the terrain is waited on, in frames. It is a courtesy rather than a
## requirement — the game is perfectly playable while the quadtree finishes — so
## this exists to stop a slow machine holding the start action indefinitely.
const TERRAIN_PATIENCE := 300
## How large a warmed mesh is drawn, in metres, whatever size it really is. Big
## enough to cover pixels, small enough that a two hundred metre monolith does
## not fill the offscreen target.
const WARM_SIZE := 0.3
## How far in front of the camera the warm-up geometry stands.
const WARM_AHEAD := 1.2
## Large enough that the warmed meshes cover real pixels, but deliberately much
## smaller than the game window: this render target is never presented.
const WARM_VIEW_SIZE := Vector2i(256, 256)


## How many distinct mesh-and-material pairs the last run compiled. Reported for
## the harness, which cannot otherwise tell a warm-up that found the whole planet
## from one that found nothing and returned quickly.
var compiled := 0


## Runs the whole warm-up. Awaited by the caller while the ordinary title screen
## remains visible.
func run(world: Node, camera: Camera3D) -> void:
	var planet := world.find_child("Planet", true, false) as Planet
	progressed.emit(0.0, "Waking the planet")
	await get_tree().process_frame

	var draws := await _collect(world)
	compiled = draws.size()
	progressed.emit(0.15, "Preparing plants")

	await _compile(draws, camera)
	progressed.emit(0.85, "Building terrain")

	await _settle_terrain(planet)
	# The offscreen viewport and its last batch are freed deferred. Returning
	# after that has happened keeps the warm-up a self-contained transient node.
	await get_tree().process_frame
	progressed.emit(1.0, "Ready")


## Every distinct mesh-and-material pair the world can draw, with the species
## prepared on the way past.
##
## Deliberately taken from the fields rather than from what is on screen. A cover
## field holds no stands at all until the viewer is near enough to grow some, so
## at the title screen the entire flora system is invisible to a walk of the
## scene tree — which is precisely why none of it has been compiled.
func _collect(world: Node) -> Array[Dictionary]:
	var draws: Array[Dictionary] = []
	var seen := {}
	var species_seen := {}
	var nodes := world.find_children("*", "Node3D", true, false)
	for index in nodes.size():
		var node: Node = nodes[index]
		var cover := node as GroundCover
		if cover != null:
			for entry in cover.species:
				var plant := entry as PlantSpecies
				if plant == null or species_seen.has(plant.get_instance_id()):
					continue
				species_seen[plant.get_instance_id()] = true
				plant.prepare()
				_offer(draws, seen, plant.near_mesh(), plant.near_material(),
					null)
				_offer(draws, seen, plant.distant_mesh(), plant.far_material(),
					null)
		else:
			var fauna := node as FaunaSpawner
			if fauna != null:
				# Creatures are invisible to a walk of the tree for the same reason
				# stands are: none exist until the streamer places one, and the first
				# one placed is the one that would otherwise stall the frame.
				for entry in fauna.species:
					var creature := entry as FaunaSpecies
					if creature == null or not creature.enabled \
							or species_seen.has(creature.get_instance_id()):
						continue
					species_seen[creature.get_instance_id()] = true
					creature.prepare()
					_offer(draws, seen, creature.template_mesh(),
						creature.template_material(), null)
			else:
				var batch := node as MultiMeshInstance3D
				if batch != null and batch.multimesh != null:
					# Rebuilt at one instance rather than borrowed: a reef swarm's own
					# MultiMesh holds thirty-six thousand fish and drawing it a metre
					# from the camera to compile one pipeline would be worse than the
					# stall it is avoiding.
					_offer(draws, seen, batch.multimesh.mesh,
						batch.material_override, batch.multimesh)
				else:
					var single := node as MeshInstance3D
					if single != null:
						_offer(draws, seen, single.mesh, single.material_override, null)
		if index % 64 == 0:
			progressed.emit(
				lerpf(0.02, 0.14, float(index + 1) / float(maxi(nodes.size(), 1))),
				"Preparing plants")
			await get_tree().process_frame
	return draws


func _offer(draws: Array[Dictionary], seen: Dictionary, mesh: Mesh,
		material: Material, like: MultiMesh) -> void:
	if mesh == null:
		return
	var key := "%d:%d" % [mesh.get_instance_id(),
		0 if material == null else material.get_instance_id()]
	if seen.has(key):
		return
	seen[key] = true
	draws.append({"mesh": mesh, "material": material, "like": like})


## Draws one of everything offscreen, a handful at a time, and throws it away
## again. The isolated World3D is important: a SubViewport sharing the game's
## World3D would still register these meshes in the main camera's scenario and
## make them visible there even though their render target was separate.
func _compile(draws: Array[Dictionary], source_camera: Camera3D) -> void:
	if source_camera == null or draws.is_empty():
		return
	var viewport := _warm_viewport(source_camera)
	var camera := viewport.get_node("Camera") as Camera3D
	# Give the viewport one submission before its first batch. It is not attached
	# to a Control, so UPDATE_ALWAYS is what makes it render despite never being
	# presented on screen.
	await get_tree().process_frame
	var done := 0
	while done < draws.size():
		var batch: Array[Node3D] = []
		for step in mini(BATCH_SIZE, draws.size() - done):
			var made := _warm_node(draws[done + step], step)
			if made != null:
				camera.add_child(made)
				batch.append(made)
		done += BATCH_SIZE
		for _frame in BATCH_FRAMES:
			await get_tree().process_frame
		for made in batch:
			made.queue_free()
		progressed.emit(
			lerpf(0.15, 0.85, float(done) / float(draws.size())),
			"Compiling shaders")
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.queue_free()
	await get_tree().process_frame


## A private render target and world for the real draws used to create graphics
## pipelines. It borrows the menu camera's environment so shader variants match,
## and owns a shadow-casting sun so both colour and shadow passes are submitted.
func _warm_viewport(source_camera: Camera3D) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "WarmViewport"
	viewport.size = WARM_VIEW_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = source_camera.fov
	camera.near = 0.05
	camera.far = 20.0
	camera.environment = source_camera.environment
	camera.attributes = source_camera.attributes
	viewport.add_child(camera)
	camera.current = true

	var sun := DirectionalLight3D.new()
	sun.name = "WarmSun"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.shadow_enabled = true
	viewport.add_child(sun)
	return viewport


## One tiny instance of a mesh, in the camera's own space so it cannot be missed
## by the frustum, and casting a shadow so that variant of the pipeline is built
## too.
func _warm_node(draw: Dictionary, slot: int) -> Node3D:
	var mesh := draw["mesh"] as Mesh
	var box := mesh.get_aabb()
	var span := maxf(box.size.length(), 0.001)
	var fit := WARM_SIZE / span
	# Spread across the near plane rather than stacked, so each is its own draw
	# rather than nine of them hidden behind the first.
	var across := (float(slot % 5) - 2.0) * WARM_SIZE * 1.2
	var down := (float(slot / 5) - 0.5) * WARM_SIZE * 1.2
	var frame := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * fit),
		Vector3(across, down, -WARM_AHEAD) - box.get_center() * fit)

	var like := draw["like"] as MultiMesh
	var material := draw["material"] as Material
	if like == null:
		var single := MeshInstance3D.new()
		single.mesh = mesh
		single.material_override = material
		single.transform = frame
		single.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return single

	var multimesh := MultiMesh.new()
	multimesh.transform_format = like.transform_format
	multimesh.use_colors = like.use_colors
	multimesh.use_custom_data = like.use_custom_data
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	if like.use_colors:
		multimesh.set_instance_color(0, Color.WHITE)
	if like.use_custom_data:
		multimesh.set_instance_custom_data(0, Color(0.5, 0.5, 0.5, 0.5))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multimesh
	batch.material_override = material
	batch.transform = frame
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return batch


## Waits for the planet to stop refining under the spawn.
func _settle_terrain(planet: Planet) -> void:
	if planet == null:
		return
	var waited := 0
	while waited < TERRAIN_PATIENCE:
		var numbers := planet.statistics()
		if int(numbers.get("pending", 0)) == 0 \
				and int(numbers.get("requests", 0)) == 0:
			return
		await get_tree().process_frame
		waited += 1
		if waited % 15 == 0:
			progressed.emit(lerpf(0.85, 0.99,
				float(waited) / float(TERRAIN_PATIENCE)), "Building terrain")
