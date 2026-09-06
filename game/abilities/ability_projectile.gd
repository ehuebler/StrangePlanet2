class_name AbilityProjectile
extends Node3D

## Runtime projectile selected by AbilityDefinition.projectile_type.
##
## The projectile is simulated visually on every peer, while only the owning
## peer dispatches its definition's impact. Damage and terrain then use their
## existing host-approved replication paths.

var shooter: OnlinePlayer
var definition: AbilityDefinition
var authoritative := false
var stats: Dictionary = {}

var _along := Vector3.FORWARD
var _velocity := Vector3.FORWARD
var _speed := 1.0
var _range := 1.0
var _travelled := 0.0
var _shooter_rid := RID()
var _disk: MeshInstance3D
var _probe: SphereShape3D


static func launch(world: Node, source: OnlinePlayer, ability_id: String,
		from: Vector3, along: Vector3, owns_impact: bool,
		inherited_velocity: Vector3 = Vector3.ZERO,
		stats_override: Dictionary = {}) -> AbilityProjectile:
	var authored := ItemDB.ability_definition(ability_id)
	if world == null or source == null or authored == null \
			or authored.projectile_type == AbilityDefinition.ProjectileType.NONE:
		return null
	var projectile := AbilityProjectile.new()
	projectile.shooter = source
	projectile.definition = authored
	projectile.stats = authored.stats.duplicate(true)
	if not stats_override.is_empty():
		projectile.stats.merge(stats_override, true)
	projectile.authoritative = owns_impact
	projectile._along = along.normalized() \
		if along.length_squared() > 0.001 else -source.global_basis.z
	projectile._speed = maxf(float(projectile.stats.get("speed", 1.0)), 1.0)
	var carried := inherited_velocity if inherited_velocity.is_finite() \
		else Vector3.ZERO
	projectile._velocity = projectile._along * projectile._speed + carried
	projectile._range = maxf(float(projectile.stats.get("range", 1.0)), 1.0)
	if source.has_method(&"crawler_range_scale"):
		projectile._range *= float(source.call(&"crawler_range_scale"))
	projectile._shooter_rid = source.get_rid()
	world.add_child(projectile)
	projectile.global_position = from
	var facing := projectile._velocity.normalized() \
		if projectile._velocity.length_squared() > 0.001 else projectile._along
	projectile.look_at(from + facing, source.global_basis.y)
	return projectile


func _ready() -> void:
	match definition.projectile_type:
		AbilityDefinition.ProjectileType.ENERGY_DISK:
			_build_energy_disk()
		AbilityDefinition.ProjectileType.ENERGY_ORB:
			_build_energy_orb()
		_:
			queue_free()


func _build_energy_disk() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius", 0.36)), 0.08)
	var mesh := CylinderMesh.new()
	mesh.top_radius = quoted_radius
	mesh.bottom_radius = quoted_radius
	mesh.height = maxf(quoted_radius * 0.18, 0.035)
	mesh.radial_segments = 24
	mesh.rings = 1

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = definition.tint
	material.emission_enabled = true
	material.emission = definition.tint
	material.emission_energy_multiplier = 4.2
	mesh.material = material

	_disk = MeshInstance3D.new()
	_disk.mesh = mesh
	# CylinderMesh stands on Y already. Keeping that spin axis aligned with the
	# launch up makes the thin rim lead and the broad faces ride above and below
	# the path, like a thrown frisbee rather than a coin flying face-first.
	add_child(_disk)

	var light := OmniLight3D.new()
	light.light_color = definition.tint
	light.light_energy = 2.4
	light.omni_range = maxf(quoted_radius * 7.0, 2.5)
	add_child(light)


func _build_energy_orb() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius", 1.0)), 0.15)
	var sphere := SphereMesh.new()
	sphere.radius = quoted_radius
	sphere.height = quoted_radius * 2.0
	sphere.radial_segments = 28
	sphere.rings = 16
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = definition.tint.lightened(0.28)
	material.emission_enabled = true
	material.emission = definition.tint
	material.emission_energy_multiplier = 7.5
	sphere.material = material
	_disk = MeshInstance3D.new()
	_disk.mesh = sphere
	_disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disk)

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = quoted_radius * 1.32
	halo_mesh.height = quoted_radius * 2.64
	halo_mesh.radial_segments = 24
	halo_mesh.rings = 12
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_color = Color(definition.tint, 0.38)
	halo_material.emission_enabled = true
	halo_material.emission = definition.tint
	halo_material.emission_energy_multiplier = 4.5
	halo_mesh.material = halo_material
	var halo := MeshInstance3D.new()
	halo.mesh = halo_mesh
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	var light := OmniLight3D.new()
	light.light_color = definition.tint
	light.light_energy = 5.5
	light.omni_range = maxf(quoted_radius * 10.0, 7.0)
	add_child(light)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter) or definition == null \
			or not is_instance_valid(_disk):
		queue_free()
		return
	var step_vector := _velocity * delta
	var from := global_position
	var to := from + step_vector
	var hit := _trace_step(from, to)
	if not hit.is_empty():
		global_position = hit["position"]
		if authoritative:
			var normal: Vector3 = hit.get("normal", -_along)
			AbilityImpact.apply(
				shooter, definition, global_position, normal, stats)
		queue_free()
		return
	global_position = to
	# Range is relative to the thrower at the instant of release. Inherited
	# player motion moves the whole flight through the world without consuming
	# the disk's authored 70 m of forward travel in a handful of frames.
	_travelled += _speed * delta
	_disk.rotation.y += delta * 24.0
	if _travelled >= _range:
		if authoritative and definition.projectile_type \
				== AbilityDefinition.ProjectileType.ENERGY_ORB:
			var facing := -_velocity.normalized() \
				if _velocity.length_squared() > 0.001 else -_along
			AbilityImpact.apply(
				shooter, definition, global_position, facing, stats)
		queue_free()


func _quoted_radius() -> float:
	var authored := 0.36
	if definition != null:
		authored = float(definition.stats.get("projectile_radius", authored))
	return maxf(float(stats.get("projectile_radius", authored)), 0.08)


func _trace_step(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude := DamageHit.rid_list(_shooter_rid)
	var motion := to - from
	if motion.length_squared() < 0.000001:
		return {}
	if _probe == null:
		_probe = SphereShape3D.new()
	_probe.radius = _quoted_radius()
	var sweep := PhysicsShapeQueryParameters3D.new()
	sweep.shape = _probe
	sweep.transform = Transform3D(Basis(), from)
	sweep.motion = motion
	sweep.exclude = exclude
	sweep.collide_with_areas = false
	sweep.collide_with_bodies = true
	var fractions := space.cast_motion(sweep)
	if fractions.size() >= 1 and fractions[0] < 1.0:
		var share := fractions[1] if fractions.size() > 1 else fractions[0]
		var at := from + motion * clampf(share, 0.0, 1.0)
		sweep.transform.origin = at
		var rest := space.get_rest_info(sweep)
		if not rest.is_empty():
			rest["position"] = rest.get("point", at)
			if rest.get("normal", Vector3.ZERO).length_squared() < 0.001:
				rest["normal"] = -_along
			return rest
		return {"position": at, "normal": -_along}
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	query.hit_from_inside = true
	query.hit_back_faces = true
	return space.intersect_ray(query)
