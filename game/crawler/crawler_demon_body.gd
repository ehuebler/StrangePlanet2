class_name CrawlerDemonBody
extends RefCounted

## Procedural winged demon: capsule body, horns, and 1–3 wing pairs with
## Idle / Walk / Run / Fly / Attack / Cast / HitReact clips.


const CLIP_FLY := "Fly"
const CLIP_CAST := "Cast"
const RAYS_NAME := "CursedRays"

static var _ray_image: Texture2D


class RayPulse extends Node3D:
	var _clock := 0.0

	func _process(delta: float) -> void:
		_clock += delta
		var wide := 0.92 + 0.08 * sin(_clock * 1.25)
		scale = Vector3(wide, 1.0, wide)
		var lamp := get_node_or_null("CursedLamp") as OmniLight3D
		if lamp != null:
			lamp.light_energy = 3.2 + sin(_clock * 1.7) * 0.7


static func build(host: CrawlerMob, wings: int, height: float, colour: Color,
		paint: Texture2D, aura := Color(0, 0, 0, 0)) -> Node3D:
	var root := Node3D.new()
	root.name = "Demon"
	host.add_child(root)
	var pairs := clampi(wings / 2, 1, 3)
	var torso := CapsuleMesh.new()
	torso.radius = height * 0.16
	torso.height = height * 0.62
	var body := _mesh(host, root, torso, colour, paint)
	body.position = Vector3(0.0, height * 0.02, 0.0)
	body.name = "Torso"
	var head := SphereMesh.new()
	head.radius = height * 0.14
	head.height = height * 0.28
	var crown := _mesh(host, root, head, colour.lightened(0.12), paint)
	crown.position = Vector3(0.0, height * 0.38, height * 0.02)
	crown.name = "Head"
	for side in [-1.0, 1.0]:
		var horn := CylinderMesh.new()
		horn.top_radius = height * 0.012
		horn.bottom_radius = height * 0.03
		horn.height = height * 0.18
		var spike := _mesh(host, root, horn, colour.darkened(0.18), paint)
		spike.position = Vector3(side * height * 0.08, height * 0.50, 0.0)
		spike.rotation.z = side * 0.35
	for pair in pairs:
		var lift := height * (0.10 + float(pair) * 0.07)
		var span := height * (0.42 + float(pair) * 0.08)
		for side in [-1.0, 1.0]:
			var wing := BoxMesh.new()
			wing.size = Vector3(span, height * 0.035, height * 0.22)
			var vane := _mesh(host, root, wing, colour.lightened(0.08), paint)
			vane.name = "Wing%d%s" % [pair, "L" if side < 0.0 else "R"]
			vane.position = Vector3(side * height * 0.12, lift, -height * 0.04)
			vane.rotation.y = side * 0.22
	add_god_rays(root, height, aura)
	_bind_clips(host, root, pairs, height)
	return root


static func add_aura(host: Node3D, height: float, aura: Color) -> void:
	add_god_rays(host, height, aura)


static func add_god_rays(host: Node3D, height: float, aura: Color) -> void:
	if host == null or aura.a <= 0.04:
		return
	var existing := host.get_node_or_null(RAYS_NAME)
	if existing != null:
		return
	var ink := Color(aura.r, aura.g, aura.b)
	var root := RayPulse.new()
	root.name = RAYS_NAME
	host.add_child(root)
	var core := MeshInstance3D.new()
	core.name = "RayCore"
	var orb := SphereMesh.new()
	orb.radius = height * 0.10
	orb.height = height * 0.20
	core.mesh = orb
	core.material_override = _ray_material(Color(ink.lightened(0.32), 0.46), 6.4)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var shaft := _ray_texture()
	_add_shaft(root, "RayDown", ink, shaft, height * 2.5, height * 0.07, height * 0.52, 0.0, 0.0)
	_add_shaft(root, "RayUp", ink, shaft, height * 1.7, height * 0.028, height * 0.16, PI, 0.0)
	for i in 6:
		var yaw := float(i) * TAU / 6.0
		var tilt := 0.38 + float(i % 2) * 0.10
		_add_shaft(
			root, "Ray%d" % i, ink, shaft,
			height * 2.15, height * 0.04, height * 0.34, tilt, yaw)
	var lamp := OmniLight3D.new()
	lamp.name = "CursedLamp"
	lamp.light_color = ink
	lamp.light_energy = 3.4
	lamp.omni_range = height * 4.2
	root.add_child(lamp)


static func _mesh(host: CrawlerMob, root: Node3D, mesh: Mesh, colour: Color,
		paint: Texture2D) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = host._enemy_material(colour, paint, 1.0)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)
	if host._visual == null:
		host._visual = visual
	return visual


static func _add_shaft(
		root: Node3D, shaft_name: String, ink: Color, texture: Texture2D,
		length: float, tip: float, base: float, tilt: float, yaw: float
	) -> void:
	var pivot := Node3D.new()
	pivot.name = shaft_name
	pivot.rotation = Vector3(tilt, yaw, 0.0)
	root.add_child(pivot)
	var mesh := CylinderMesh.new()
	mesh.top_radius = maxf(tip, 0.01)
	mesh.bottom_radius = maxf(base, tip)
	mesh.height = maxf(length, 0.2)
	mesh.radial_segments = 16
	var visual := MeshInstance3D.new()
	visual.name = "Shaft"
	visual.mesh = mesh
	visual.position.y = -mesh.height * 0.48
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.material_override = _ray_material(Color(ink, 0.30), 5.2, texture)
	pivot.add_child(visual)


static func _ray_material(
		color: Color, energy: float, texture: Texture2D = null
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


static func _ray_texture() -> Texture2D:
	if _ray_image != null:
		return _ray_image
	const WIDTH := 32
	const HEIGHT := 128
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in HEIGHT:
		var along := float(y) / float(HEIGHT - 1)
		var rise := pow(along, 0.62)
		var fade := smoothstep(1.0, 0.88, along)
		var pixel := Color(1.0, 1.0, 1.0, rise * fade)
		for x in WIDTH:
			image.set_pixel(x, y, pixel)
	_ray_image = ImageTexture.create_from_image(image)
	return _ray_image


static func load_paint(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _bind_clips(host: CrawlerMob, root: Node3D, pairs: int, height: float) -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation(CrawlerMob.CLIP_IDLE, _clip_idle(pairs, 1.4, height))
	library.add_animation(CrawlerMob.CLIP_WALK, _clip_flap(pairs, 0.55, 0.28, height))
	library.add_animation(CrawlerMob.CLIP_RUN, _clip_flap(pairs, 0.32, 0.42, height))
	library.add_animation(CLIP_FLY, _clip_flap(pairs, 0.38, 0.55, height))
	library.add_animation(CrawlerMob.CLIP_ATTACK, _clip_attack(pairs, 0.42, height))
	library.add_animation(CLIP_CAST, _clip_cast(pairs, 0.90, height))
	library.add_animation(CrawlerMob.CLIP_HIT, _clip_hit(0.28, height))
	player.add_animation_library("", library)
	host._bind_animator(root)


static func _clip_idle(pairs: int, length: float, height: float) -> Animation:
	var anim := _empty(length, true)
	_bob(anim, length, height * 0.02, height * 0.014)
	_flap(anim, pairs, length, 0.12)
	return anim


static func _clip_flap(pairs: int, length: float, amount: float, height: float) -> Animation:
	var anim := _empty(length, true)
	_bob(anim, length, height * 0.02, height * 0.022)
	_flap(anim, pairs, length, amount)
	return anim


static func _clip_attack(pairs: int, length: float, height: float) -> Animation:
	var anim := _empty(length, false)
	var idx := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("Head:position"))
	var head := Vector3(0.0, height * 0.38, height * 0.02)
	anim.position_track_insert_key(idx, 0.0, head)
	anim.position_track_insert_key(idx, length * 0.45,
		head + Vector3(0.0, -height * 0.02, height * 0.06))
	anim.position_track_insert_key(idx, length, head)
	_flap(anim, pairs, length, 0.2)
	return anim


static func _clip_cast(pairs: int, length: float, height: float) -> Animation:
	var anim := _empty(length, false)
	_flap(anim, pairs, length, 0.18)
	var idx := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("Torso:position"))
	var rest := Vector3(0.0, height * 0.02, 0.0)
	anim.position_track_insert_key(idx, 0.0, rest)
	anim.position_track_insert_key(idx, length * 0.5,
		rest + Vector3(0.0, height * 0.04, -height * 0.02))
	anim.position_track_insert_key(idx, length, rest)
	return anim


static func _clip_hit(length: float, height: float) -> Animation:
	var anim := _empty(length, false)
	var idx := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("Torso:position"))
	var rest := Vector3(0.0, height * 0.02, 0.0)
	anim.position_track_insert_key(idx, 0.0, rest)
	anim.position_track_insert_key(idx, length * 0.4,
		rest + Vector3(0.0, 0.0, -height * 0.04))
	anim.position_track_insert_key(idx, length, rest)
	return anim


static func _empty(length: float, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return anim


static func _bob(anim: Animation, length: float, rest_y: float, amount: float) -> void:
	var idx := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("Torso:position"))
	anim.position_track_insert_key(idx, 0.0, Vector3(0.0, rest_y, 0.0))
	anim.position_track_insert_key(idx, length * 0.5, Vector3(0.0, rest_y + amount, 0.0))
	anim.position_track_insert_key(idx, length, Vector3(0.0, rest_y, 0.0))


static func _flap(anim: Animation, pairs: int, length: float, amount: float) -> void:
	for pair in pairs:
		for side_name: String in ["L", "R"]:
			var idx := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(idx, NodePath("Wing%d%s:rotation" % [pair, side_name]))
			var sign := -1.0 if side_name == "L" else 1.0
			anim.rotation_track_insert_key(
				idx, 0.0, Quaternion(Vector3.FORWARD, sign * -amount))
			anim.rotation_track_insert_key(
				idx, length * 0.5, Quaternion(Vector3.FORWARD, sign * amount))
			anim.rotation_track_insert_key(
				idx, length, Quaternion(Vector3.FORWARD, sign * -amount))
