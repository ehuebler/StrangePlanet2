class_name EnergyExplosion
extends Node3D

## Short emissive pulse shared by projectile and slam impacts.
##
## A small burst is one expanding shell and a light, which is all a disk hitting a
## rock needs. A massive burst adds the brighter outer shells used by Nausicaä.
## A nuclear one — [param nuclear], used only by the Nuke impact type — stages a
## white flash that turns the local view inside out, a fireball, a mushroom cloud,
## and two shock rings running out along the ground. Each stage is a share of the
## authored duration rather than its own number, so widening a blast in the
## manifest keeps the whole sequence in proportion.

const LIFE := 0.34
const CLOUD_SHADER := preload("res://game/abilities/nuke_cloud.gdshader")
const SHOCKWAVE_SHADER := preload(
	"res://game/abilities/nuke_shockwave.gdshader")

## Widest a burst may be drawn, which is what a received radius is trusted
## against. A nuke fireball is over a hundred metres across, so this is a sanity
## bound on the wire and not a judgement about what looks right.
const MAX_RADIUS := 320.0

## How much longer than its fireball a massive burst stands, as a multiple. The
## cloud is the part anyone actually watches: a detonation that cleared the screen
## in the second and a half its fireball lasted read as a muzzle flash.
const SMOKE_SPAN := 4.5

var _radius := 1.0
var _tint := Color.WHITE
var _life := LIFE
var _massive := false
var _nuclear := false
## Nuclear bursts keep the flash, fireball and ground rings. The mushroom is
## optional so a collapsing building can share that detonation without growing
## a cloud.
var _mushroom := true
var _age := 0.0
var _span := LIFE
## Where the burst was asked for. Held separately because [method Node.add_child]
## runs [method _ready] before the caller has had a chance to place the node, and
## the stages that stand outside the swelling fireball need to know where they are
## before they are built.
var _at := Vector3.ZERO
var _material: StandardMaterial3D
var _shell_materials: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _flash: MeshInstance3D
var _flash_material: StandardMaterial3D
## Everything that has to stand up off the ground rather than sit in world axes.
var _column: Node3D
var _rings: Array[MeshInstance3D] = []
var _ring_materials: Array[StandardMaterial3D] = []
var _pressure: MeshInstance3D
var _pressure_material: ShaderMaterial
var _stem: MeshInstance3D
var _cap: MeshInstance3D
var _billows: Array[MeshInstance3D] = []
var _stem_billows: Array[MeshInstance3D] = []
var _smoke_materials: Array[ShaderMaterial] = []


static func burst(world: Node, at: Vector3, radius: float,
		tint: Color, duration := LIFE, massive := false,
		nuclear := false, mushroom := true) -> EnergyExplosion:
	if world == null:
		return null
	var effect := EnergyExplosion.new()
	effect._radius = clampf(radius, 0.2, MAX_RADIUS)
	effect._tint = tint
	effect._life = clampf(duration, 0.12, 2.0)
	effect._massive = massive
	effect._nuclear = nuclear
	effect._mushroom = mushroom
	effect._span = effect._life * (SMOKE_SPAN if nuclear else 1.0)
	effect._at = at
	world.add_child(effect)
	effect.global_position = at
	return effect


## How long this burst stands in total, fireball and cloud together.
func span() -> float:
	return _span


## Whether this nuclear burst grew the mushroom column. Building collapses keep
## the fireball and ground rings and leave the cloud off.
func has_cloud() -> bool:
	return _nuclear and _mushroom


func _ready() -> void:
	_material = _shell_material(_tint, 4.0)
	var shell := MeshInstance3D.new()
	shell.mesh = _ball(_material)
	add_child(shell)
	_shell_materials.append(_material)
	if _massive:
		_add_outer_shell(1.08, _tint.lightened(0.45), 6.5)
		_add_outer_shell(1.22, _tint.darkened(0.18), 3.2)

	_light = OmniLight3D.new()
	_light.light_color = _tint
	_light.light_energy = 11.0 if _massive else 5.0
	_light.omni_range = _radius * (2.0 if _massive else 1.6)
	add_child(_light)
	scale = Vector3.ONE * 0.08

	if not _nuclear:
		return
	_build_flash()
	# Outside the fireball's transform for the same reason the flash is: this node
	# swells from a twelfth of full size to the whole of it, and a ring or a cloud
	# parented under that would be multiplied by it.
	_column = Node3D.new()
	_column.top_level = true
	add_child(_column)
	_column.global_transform = Transform3D(_ground_frame(), _at)
	_build_rings()
	if _mushroom:
		_build_cloud()
	_bleach_local_view()


func _process(delta: float) -> void:
	_age += delta
	var share := clampf(_age / _life, 0.0, 1.0)
	var opened := 1.0 - pow(1.0 - share, 3.0)
	scale = Vector3.ONE * lerpf(0.08, _radius, opened)
	var alpha := pow(1.0 - share, 1.6)
	for index in _shell_materials.size():
		var material := _shell_materials[index]
		var colour := material.emission
		colour.a = alpha * (1.0 - float(index) * 0.2)
		material.albedo_color = colour
		material.emission_energy_multiplier = 1.0 \
			+ alpha * (7.0 if _massive else 4.0)
	_light.light_energy = alpha * (11.0 if _massive else 5.0)
	if _nuclear:
		# The stages run on the node's own age rather than on the fireball's
		# share, because all of them outlast it.
		_drive_flash()
		_drive_rings()
		if _mushroom:
			_drive_cloud()
	if _age >= _span:
		queue_free()


## The near-white core of the first instant.
##
## Its own shell rather than a brighter fireball, because the two want opposite
## timings: the fireball swells over the whole duration and this has to be at full
## width before anyone can see it grow and gone before the cloud starts.
func _build_flash() -> void:
	_flash_material = _shell_material(
		Color(1.0, 0.97, 0.92).lerp(_tint, 0.25), 14.0)
	_flash = MeshInstance3D.new()
	_flash.mesh = _ball(_flash_material)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Outside the parent's own scale, which starts at a twelfth of full size and
	# is still opening while this is already fading.
	_flash.top_level = true
	add_child(_flash)
	_flash.global_position = _at


func _drive_flash() -> void:
	if _flash == null:
		return
	var over := _life * 0.3
	if _age >= over:
		_flash.queue_free()
		_flash = null
		return
	var share := _age / over
	_flash.scale = Vector3.ONE * _radius * lerpf(0.35, 1.3, sqrt(share))
	var colour := _flash_material.emission
	colour.a = pow(1.0 - share, 2.2)
	_flash_material.albedo_color = colour
	_flash_material.emission_energy_multiplier = 1.0 + colour.a * 22.0


## Two rings running out along the ground, the second well behind the first.
##
## The far one is the reason there are two: a single ring reads as the edge of the
## fireball, and a second one still travelling after the fireball has gone is what
## makes the blast look like it displaced something.
func _build_rings() -> void:
	for index in 2:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.82
		ring.outer_radius = 1.0
		ring.rings = 48
		ring.ring_segments = 10
		var material := _shell_material(
			_tint.lightened(0.6 if index == 0 else 0.3), 5.0 - float(index) * 2.0)
		ring.material = material
		_ring_materials.append(material)
		var body := MeshInstance3D.new()
		body.mesh = ring
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_column.add_child(body)
		_rings.append(body)
	_pressure_material = ShaderMaterial.new()
	_pressure_material.shader = SHOCKWAVE_SHADER
	_pressure_material.set_shader_parameter(&"tint", _tint)
	_pressure = MeshInstance3D.new()
	_pressure.mesh = _ball(_pressure_material)
	_pressure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pressure.visible = false
	_column.add_child(_pressure)


func _drive_rings() -> void:
	for index in _rings.size():
		var start := _life * (0.05 if index == 0 else 0.55)
		var over := _life * (1.6 if index == 0 else 2.6)
		var share := clampf((_age - start) / over, 0.0, 1.0)
		var body := _rings[index]
		if share <= 0.0 or share >= 1.0:
			body.visible = false
			continue
		body.visible = true
		# Eased out rather than linear: a front slows as it spends itself, and a
		# ring travelling at a constant speed reads as a growing hoop.
		var reach := _radius * lerpf(0.15, 1.5 + float(index) * 0.8,
			1.0 - pow(1.0 - share, 2.4))
		# Flattened, and flatter as it widens. It is a front along the ground.
		body.scale = Vector3(reach, reach * lerpf(0.22, 0.05, share), reach)
		body.position.y = maxf(0.45, reach * 0.015)
		var material := _ring_materials[index]
		var colour := material.emission
		colour.a = pow(1.0 - share, 1.4) * (0.85 if index == 0 else 0.5)
		material.albedo_color = colour
		material.emission_energy_multiplier = 1.0 + colour.a * 6.0

	# The secondary front begins after the first ground ring has cleared the
	# fireball. Unlike the rings it climbs through the air as a spherical shell,
	# which keeps it visible when terrain hides the far half of a flat torus.
	var pressure_start := _life * 0.7
	var pressure_over := _life * 2.8
	var pressure_share := clampf(
		(_age - pressure_start) / pressure_over, 0.0, 1.0)
	if pressure_share <= 0.0 or pressure_share >= 1.0:
		_pressure.visible = false
		return
	_pressure.visible = true
	var pressure_reach := _radius * lerpf(0.22, 2.65,
		1.0 - pow(1.0 - pressure_share, 2.0))
	_pressure.scale = Vector3.ONE * pressure_reach
	_pressure.position.y = maxf(0.5, pressure_reach * 0.018)
	_pressure_material.set_shader_parameter(
		&"strength", pow(sin(pressure_share * PI), 0.72))


## Stem, cap, and enough billows to break both silhouettes.
##
## The broad geometry gives the cloud its readable shape at distance. Its shader
## cuts noisy holes through that skin and writes a depth pre-pass, so overlapping
## lobes become one torn mass rather than a diagram made out of dark circles.
func _build_cloud() -> void:
	var stem := CylinderMesh.new()
	stem.top_radius = 0.34
	stem.bottom_radius = 0.5
	stem.height = 1.0
	stem.radial_segments = 20
	stem.rings = 1
	stem.material = _smoke_material()
	_stem = MeshInstance3D.new()
	_stem.mesh = stem
	_stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.add_child(_stem)

	_cap = MeshInstance3D.new()
	_cap.mesh = _ball(_smoke_material())
	_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.add_child(_cap)

	# Fixed bearings rather than random ones. Every peer draws the same cloud
	# without anything being sent, and a shot of it is the same shot twice.
	for index in 10:
		var billow := MeshInstance3D.new()
		billow.mesh = _ball(_smoke_material())
		billow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_column.add_child(billow)
		_billows.append(billow)
	for index in 6:
		var billow := MeshInstance3D.new()
		billow.mesh = _ball(_smoke_material())
		billow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_column.add_child(billow)
		_stem_billows.append(billow)


func _drive_cloud() -> void:
	if _cap == null:
		return
	# Starts as the fireball is halfway through collapsing, so the cloud is seen
	# to come out of it rather than to appear beside it.
	var start := _life * 0.35
	var share := clampf((_age - start) / maxf(_span - start, 0.01), 0.0, 1.0)
	var visible_now := share > 0.0 and share < 1.0
	_stem.visible = visible_now
	_cap.visible = visible_now
	for billow in _billows:
		billow.visible = visible_now
	for billow in _stem_billows:
		billow.visible = visible_now
	if not visible_now:
		return
	# Climb eases off; width does not. A column rises fast and then stalls while
	# the head it fed keeps spreading.
	var climbed := 1.0 - pow(1.0 - share, 2.2)
	var height := _radius * lerpf(0.2, 1.55, climbed)
	var width := _radius * lerpf(0.28, 1.0, sqrt(share))

	_stem.scale = Vector3(width * 0.45, height, width * 0.45)
	_stem.position = Vector3(0.0, height * 0.5, 0.0)
	_cap.scale = Vector3(width, width * 0.72, width)
	_cap.position = Vector3(0.0, height, 0.0)
	for index in _billows.size():
		var ring := index / 5
		var turn := TAU * float(index % 5) / 5.0 + float(ring) * 0.53
		var billow := _billows[index]
		var lobe := width * (0.38 + float((index * 7) % 5) * 0.035) \
			* lerpf(0.82, 1.12, sqrt(share))
		billow.scale = Vector3(lobe, lobe * 0.82, lobe)
		billow.position = Vector3(
			cos(turn) * width * (0.52 + float(ring) * 0.18),
			height + (float(ring) - 0.5) * width * 0.25
				+ sin(turn * 1.7) * width * 0.13,
			sin(turn) * width * (0.52 + float(ring) * 0.18))
	for index in _stem_billows.size():
		var portion := float(index + 1) / float(_stem_billows.size() + 1)
		var turn := float(index) * 2.17
		var lobe := width * lerpf(0.22, 0.38, portion) \
			* lerpf(0.78, 1.0, sqrt(share))
		var billow := _stem_billows[index]
		billow.scale = Vector3(lobe, lobe * 1.18, lobe)
		billow.position = Vector3(
			cos(turn) * width * 0.10,
			height * portion,
			sin(turn) * width * 0.10)

	# Opens quickly, holds, and thins out over the last third.
	var thickness := minf(share / 0.12, 1.0) * (1.0 - smoothstep(0.62, 1.0, share))
	var heat := pow(1.0 - clampf(share / 0.65, 0.0, 1.0), 1.5)
	for index in _smoke_materials.size():
		var material := _smoke_materials[index]
		material.set_shader_parameter(
			&"smoke_color", Color(0.50, 0.42, 0.36))
		material.set_shader_parameter(&"hot_color", _tint)
		material.set_shader_parameter(&"opacity",
			thickness * lerpf(0.96, 0.72, float(index)
				/ maxf(float(_smoke_materials.size() - 1), 1.0)))
		material.set_shader_parameter(&"heat", heat)


## Whites out and inverts the local view if it is close enough to be inside this.
##
## Driven from the effect rather than from the ability because the effect already
## stands at the same place on every peer: whose screen this is decides how far
## away it is, and how far away it is decides what they see, so nothing about it
## has to be sent.
func _bleach_local_view() -> void:
	var world := get_parent() as GameWorld
	if world == null:
		return
	var watcher := world.local_player()
	if watcher == null:
		return
	var feedback := watcher.combat_feedback()
	if feedback == null:
		return
	var away := watcher.global_position.distance_to(_at)
	# Everything inside the fireball gets the whole of it, and it is gone by three
	# times its reach.
	var share := 1.0 - clampf(
		(away - _radius) / maxf(_radius * 2.0, 1.0), 0.0, 1.0)
	if share > 0.02:
		feedback.blast_flash(share)


## The tangent frame of the ground under this, so a cloud climbs away from the
## planet instead of along world Y.
func _ground_frame() -> Basis:
	var up := Vector3.UP
	var world := get_parent() as GameWorld
	if world != null:
		var world_planet := world.planet()
		if world_planet != null:
			up = world_planet.up_at(_at)
	elif _at.length_squared() > 0.01:
		up = _at.normalized()
	if up.length_squared() < 0.001:
		up = Vector3.UP
	up = up.normalized()
	var side := up.cross(
		Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()


func _ball(material: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = material
	return mesh


func _add_outer_shell(size: float, tint: Color, energy: float) -> void:
	var material := _shell_material(tint, energy)
	_shell_materials.append(material)
	var shell := MeshInstance3D.new()
	shell.mesh = _ball(material)
	shell.scale = Vector3.ONE * size
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)


func _shell_material(tint: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = energy
	return material


func _smoke_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLOUD_SHADER
	material.set_shader_parameter(&"phase",
		float(_smoke_materials.size()) * 0.731)
	_smoke_materials.append(material)
	return material
