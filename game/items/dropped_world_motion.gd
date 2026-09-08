class_name DroppedWorldMotion
extends RefCounted

## Shared settle-and-spin for world pickups. Tiles spawn in the air, fall to
## the ground they can see, then keep turning and bobbing. A local gold shaft
## marks the site.

const FALL_SECONDS := 0.9
const FALL_SPIN := 2.55
const GROUND_SPIN := 1.35
const HOVER_HEIGHT := 0.42
const BOB_HEIGHT := 0.08
const BOB_SPEED := 1.85
const MIN_FALL := 0.12
const BEACON_NAME := "PickupBeacon"
const BEACON_TINT := Color(1.0, 0.84, 0.42)

static var _shaft_image: Texture2D


static func start(body: Node3D, clearance: float) -> Dictionary:
	if body == null:
		return _state(Vector3.ZERO, Vector3.ZERO, 1.0)
	var from := body.global_position
	var to := land_point(body, clearance)
	if from.distance_to(to) < MIN_FALL:
		return _state(from, from, 1.0)
	var duration := clampf(
		from.distance_to(to) / 7.5, FALL_SECONDS, 2.1)
	return _state(from, to, 0.0, duration)


static func start_to(body: Node3D, at: Vector3) -> Dictionary:
	if body == null or not at.is_finite():
		return _state(Vector3.ZERO, Vector3.ZERO, 1.0)
	return _state(body.global_position, at, 0.0)


static func hover(body: Node3D) -> Dictionary:
	var at := body.global_position if body != null else Vector3.ZERO
	return _state(at, at, 1.0)


static func tick(
		body: Node3D,
		visual: Node3D,
		state: Dictionary,
		delta: float,
		visual_origin: Vector3
	) -> void:
	if body == null or state.is_empty():
		return
	state["clock"] = float(state.get("clock", 0.0)) + delta
	var t := float(state.get("t", 1.0))
	if t < 1.0:
		var duration := maxf(float(state.get("duration", FALL_SECONDS)), 0.12)
		t = minf(t + delta / duration, 1.0)
		state["t"] = t
		var from: Vector3 = state.get("from", body.global_position)
		var to: Vector3 = state.get("to", body.global_position)
		if from.is_finite() and to.is_finite():
			var weight := t * t * (3.0 - 2.0 * t)
			body.global_position = from.lerp(to, weight)
	if not is_instance_valid(visual):
		return
	var spin := FALL_SPIN if t < 1.0 else GROUND_SPIN
	visual.rotate_y(delta * spin)
	if t >= 1.0:
		visual.position = visual_origin + Vector3.UP \
			* (sin(float(state.get("clock", 0.0)) * BOB_SPEED) * BOB_HEIGHT)
	_breathe_beacon(body, float(state.get("clock", 0.0)))


static func landed(state: Dictionary) -> bool:
	return float(state.get("t", 1.0)) >= 1.0


static func attach_beacon(host: Node3D, tint: Color = BEACON_TINT) -> Node3D:
	if host == null:
		return null
	var existing := host.get_node_or_null(BEACON_NAME) as Node3D
	if existing != null:
		return existing
	var ink := tint if tint.a > 0.0 else BEACON_TINT
	var root := Node3D.new()
	root.name = BEACON_NAME
	host.add_child(root)
	var pool := MeshInstance3D.new()
	pool.name = "BeaconPool"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.58
	disc.bottom_radius = 0.58
	disc.height = 0.05
	disc.radial_segments = 24
	pool.mesh = disc
	pool.position.y = -HOVER_HEIGHT
	pool.material_override = _beacon_material(Color(ink, 0.58), 2.6)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pool)
	var shaft := _shaft_texture()
	var haze := MeshInstance3D.new()
	haze.name = "BeaconHaze"
	var haze_mesh := CylinderMesh.new()
	haze_mesh.top_radius = 0.04
	haze_mesh.bottom_radius = 0.42
	haze_mesh.height = 5.4
	haze_mesh.radial_segments = 18
	haze.mesh = haze_mesh
	haze.position.y = -HOVER_HEIGHT + haze_mesh.height * 0.5
	haze.material_override = _beacon_material(Color(ink, 0.22), 3.6, shaft)
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(haze)
	var core := MeshInstance3D.new()
	core.name = "BeaconCore"
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.012
	core_mesh.bottom_radius = 0.09
	core_mesh.height = 4.8
	core_mesh.radial_segments = 14
	core.mesh = core_mesh
	core.position.y = -HOVER_HEIGHT + core_mesh.height * 0.5
	core.material_override = _beacon_material(
		Color(ink.lightened(0.28), 0.55), 5.8, shaft)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	return root


static func _beacon_material(
		color: Color,
		energy: float,
		texture: Texture2D = null
	) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	if texture != null:
		material.albedo_texture = texture
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = energy
	material.disable_receive_shadows = true
	return material


static func _shaft_texture() -> Texture2D:
	if _shaft_image != null:
		return _shaft_image
	const WIDTH := 32
	const HEIGHT := 128
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		# CylinderMesh V=0 is the top ring, so the image's first row is the tip.
		var along := float(y) / float(HEIGHT - 1)
		var rise := pow(along, 0.65)
		var floor_fade := smoothstep(1.0, 0.92, along)
		var alpha := rise * floor_fade
		var pixel := Color(1.0, 1.0, 1.0, alpha)
		for x in WIDTH:
			image.set_pixel(x, y, pixel)
	_shaft_image = ImageTexture.create_from_image(image)
	return _shaft_image


static func _breathe_beacon(host: Node3D, clock: float) -> void:
	if host == null:
		return
	var root := host.get_node_or_null(BEACON_NAME) as Node3D
	if root == null:
		return
	var breathe := 0.90 + 0.10 * sin(clock * 1.55)
	root.scale = Vector3(breathe, 1.0, breathe)


static func land_point(body: Node3D, clearance: float) -> Vector3:
	if body == null or not body.is_inside_tree():
		return Vector3.ZERO
	var from := body.global_position
	var pad := maxf(clearance, 0.0)
	var up_guess := from.normalized() if from.length_squared() > 0.01 \
		else Vector3.UP
	var planet := _planet_of(body)
	if planet != null:
		var local := planet.to_local(from)
		if local.length_squared() > 0.01:
			up_guess = planet.up_at(from)
	# The collider under the drop, not the analytical height field: a tile
	# that sat on the mesh but inside a rock still read as "on the ground".
	var space := body.get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(
			from + up_guess * 2.5, from - up_guess * 80.0)
		query.exclude = [body.get_rid()] if body is CollisionObject3D \
			else []
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit["position"] + up_guess * pad
	if planet != null and planet.shape != null:
		var local := planet.to_local(from)
		if local.length_squared() >= 0.25:
			var surface := planet.mesh_position(local)
			return surface + planet.up_at(surface) * pad
	return from


static func _planet_of(body: Node3D) -> Planet:
	var walk: Node = body
	while walk != null:
		if walk is Planet:
			return walk
		var child := walk.get_node_or_null("Planet")
		if child is Planet:
			return child
		walk = walk.get_parent()
	return null


static func _state(
		from: Vector3,
		to: Vector3,
		t: float,
		duration := FALL_SECONDS
	) -> Dictionary:
	return {
		"from": from,
		"to": to,
		"t": t,
		"clock": 0.0,
		"duration": maxf(duration, 0.12),
	}
