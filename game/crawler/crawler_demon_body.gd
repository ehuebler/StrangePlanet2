class_name CrawlerDemonBody
extends RefCounted

## Procedural winged demon: capsule body, horns, and 1–3 wing pairs with
## Idle / Walk / Run / Fly / Attack / Cast / HitReact clips.


const CLIP_FLY := "Fly"
const CLIP_CAST := "Cast"


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
	if aura.a > 0.04:
		var glow := SphereMesh.new()
		glow.radius = height * 0.62
		glow.height = height * 1.24
		var haze := MeshInstance3D.new()
		haze.name = "CursedAura"
		haze.mesh = glow
		haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = aura
		mat.emission_enabled = true
		mat.emission = Color(aura.r, aura.g, aura.b)
		mat.emission_energy_multiplier = 2.4
		haze.material_override = mat
		root.add_child(haze)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(aura.r, aura.g, aura.b)
		lamp.light_energy = 2.8
		lamp.omni_range = height * 3.4
		root.add_child(lamp)
	_bind_clips(host, root, pairs, height)
	return root


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
