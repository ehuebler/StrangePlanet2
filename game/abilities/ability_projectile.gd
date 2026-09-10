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
var _trail_travelled := 0.0
var _linger_travelled := 0.0
var _shooter_rid := RID()
var _disk: Node3D
var _probe: SphereShape3D
var _split_done := false
var _pulse := 0.0
var _persist_trail: AbilityTrail
var _struck: Node
var _shock: MeteorShock
var _cone_beam: EnergyVfx
var _ring: MeshInstance3D
var _ring_mesh: TorusMesh
var _ring_light: OmniLight3D
var _cone_origin := Vector3.INF
var _pierced: Dictionary = {}
var _bounces_left := 0
var _glow_color := Color.WHITE
var _glow_energy := 0.0
var _glow_range := 2.4


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
	if authored.projectile_type == AbilityDefinition.ProjectileType.TELEPORT_ORB \
			and float(projectile.stats.get("_multi_child", 0.0)) <= 0.0:
		var loft := clampf(float(projectile.stats.get("loft",
			CrawlerRules.TELEPORT_LOFT)), 0.0, 1.5)
		projectile._velocity += source.global_basis.y.normalized() \
			* projectile._speed * loft
	projectile._range = maxf(float(projectile.stats.get("range", 1.0)), 1.0)
	if source.has_method(&"crawler_range_scale"):
		projectile._range *= float(source.call(&"crawler_range_scale"))
	projectile._shooter_rid = source.get_rid()
	projectile._split_done = float(projectile.stats.get("_multi_child", 0.0)) > 0.0
	projectile._bounces_left = CrawlerBounce.count(projectile.stats)
	world.add_child(projectile)
	projectile.global_position = from
	var facing := projectile._velocity.normalized() \
		if projectile._velocity.length_squared() > 0.001 else projectile._along
	var up := source.global_basis.y
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	else:
		up = up.normalized()
	if absf(facing.dot(up)) < 0.98:
		projectile.look_at(from + facing, up)
	if projectile._is_energy_cone():
		projectile._cone_origin = from
		projectile._aim_cone()
	return projectile


func _ready() -> void:
	match definition.projectile_type:
		AbilityDefinition.ProjectileType.ENERGY_DISK:
			_build_energy_disk()
		AbilityDefinition.ProjectileType.ENERGY_ORB:
			_build_energy_orb()
		AbilityDefinition.ProjectileType.ENERGY_BOLT:
			_build_energy_bolt()
		AbilityDefinition.ProjectileType.ENERGY_ICICLE:
			_build_energy_icicle()
		AbilityDefinition.ProjectileType.TELEPORT_ORB:
			_build_teleport_orb()
		AbilityDefinition.ProjectileType.ENERGY_CONE:
			_build_energy_cone()
		_:
			queue_free()
			return
	CrawlerShotSense.watch(self)


func _build_energy_disk() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius", 0.36)), 0.08)
	var tint := _cast_tint()
	var ball := EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, tint)
	add_child(ball)
	ball.set_ball_radius(quoted_radius)
	_disk = ball
	_glow_color = tint
	_glow_energy = 2.4
	_glow_range = maxf(quoted_radius * 7.0, 2.5)


func _build_energy_orb() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius", 1.0)), 0.15)
	var tint := _cast_tint()
	var ball := EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, tint)
	add_child(ball)
	ball.set_ball_radius(quoted_radius)
	_disk = ball
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 5.5
	light.omni_range = maxf(quoted_radius * 10.0, 7.0)
	light.shadow_enabled = false
	add_child(light)


func _build_energy_bolt() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius",
			CrawlerRules.LIGHT_BOLT_PROJECTILE_RADIUS)), 0.04)
	var tint := EnergyVfx.TINT_PINK
	var ball := EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, tint)
	add_child(ball)
	ball.set_ball_radius(quoted_radius)
	_disk = ball
	_glow_color = tint.lerp(Color(1.0, 0.5, 0.85), 0.4)
	_glow_energy = 1.8
	_glow_range = maxf(quoted_radius * 14.0, 1.6)


func _build_energy_icicle() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius",
			CrawlerRules.ICICLE_PROJECTILE_RADIUS)), 0.06)
	var tint := _cast_tint()
	var ball := EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, tint)
	add_child(ball)
	ball.set_ball_radius(quoted_radius * 1.35)
	_disk = ball
	_glow_color = tint.lerp(Color(0.95, 0.98, 1.0), 0.45)
	_glow_energy = 2.2
	_glow_range = maxf(quoted_radius * 12.0, 2.2)


func _build_teleport_orb() -> void:
	var quoted_radius := maxf(
		float(stats.get("projectile_radius",
			CrawlerRules.TELEPORT_PROJECTILE_RADIUS)), 0.08)
	var tint := EnergyVfx.TINT_WHITE
	var ball := EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, tint)
	add_child(ball)
	ball.set_ball_radius(quoted_radius)
	_disk = ball
	_glow_color = tint
	_glow_energy = 3.2
	_glow_range = maxf(quoted_radius * 14.0, 2.8)
	_persist_trail = AbilityTrail.create(
		get_parent(), global_position, quoted_radius * 0.85, tint)


func _build_energy_cone() -> void:
	var dummy := MeshInstance3D.new()
	dummy.visible = false
	dummy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	dummy.mesh = mesh
	_disk = dummy
	add_child(dummy)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.85
	_ring_mesh.outer_radius = 1.15
	_ring_mesh.rings = 48
	_ring_mesh.ring_segments = 14
	_ring = MeshInstance3D.new()
	_ring.name = "FusRing"
	_ring.mesh = _ring_mesh
	_ring.top_level = true
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fire := _cast_tint()
	if fire.a <= 0.0 or fire.is_equal_approx(Color.WHITE):
		fire = EnergyVfx.TINT_GREEN
	_ring.material_override = EnergyVfx.glow_material(
		fire, Color(0.92, 1.0, 0.82), false, 4.2, 0.42, 0.22, 1.0)
	add_child(_ring)
	_ring_light = OmniLight3D.new()
	_ring_light.light_color = fire
	_ring_light.light_energy = 2.6
	_ring_light.omni_range = 4.0
	_ring_light.shadow_enabled = false
	_ring.add_child(_ring_light)
	_aim_cone()


func _exit_tree() -> void:
	CrawlerShotSense.drop(self)
	if is_instance_valid(_persist_trail):
		_persist_trail.linger(0.55)
		_persist_trail = null
	if is_instance_valid(_shock):
		_shock.stop()
	if is_instance_valid(_ring):
		_ring.visible = false


func _physics_process(delta: float) -> void:
	shot_tick(delta)


func shot_glow_color() -> Color:
	return _glow_color


func shot_glow_energy() -> float:
	return _glow_energy


func shot_glow_range() -> float:
	return _glow_range


func shot_tick(delta: float) -> void:
	if not is_instance_valid(shooter) or definition == null \
			or not is_instance_valid(_disk):
		queue_free()
		return
	if definition.projectile_type == AbilityDefinition.ProjectileType.TELEPORT_ORB:
		var gravity := maxf(float(stats.get("gravity",
			CrawlerRules.TELEPORT_GRAVITY)), 0.0)
		_velocity -= _flight_up() * gravity * delta
		if _velocity.length_squared() > 0.0001:
			_along = _velocity.normalized()
	if CrawlerHoming.enabled(stats):
		_velocity = CrawlerHoming.steer(
			_velocity, global_position, stats, shooter, delta, _speed)
		if _velocity.length_squared() > 0.0001:
			_along = _velocity.normalized()
	var field_slow := CrawlerMobSense.field_slow(self, global_position)
	var step_vector := _velocity * field_slow * delta
	var from := global_position
	var to := from + step_vector
	if definition.projectile_type == AbilityDefinition.ProjectileType.TELEPORT_ORB:
		var prey := _victim_along(from, to)
		if prey != null:
			global_position = _nearest_on(from, to, _combat_position(prey))
			_struck = prey
			_land(to - from)
			return
	var hit := _trace_step(from, to)
	if not hit.is_empty() and not _is_energy_cone():
		global_position = hit["position"]
		_struck = _combatant_from_hit(hit)
		_land(hit.get("normal", -_along))
		return
	if not hit.is_empty() and _is_energy_cone():
		global_position = hit["position"]
		_aim_cone()
		_pierce_cone()
		_land(hit.get("normal", -_along))
		return
	global_position = to
	if is_instance_valid(_persist_trail):
		_persist_trail.add_point(global_position)
	if _velocity.length_squared() > 0.0001:
		var facing := _velocity.normalized()
		var up := _flight_up()
		if absf(facing.dot(up)) < 0.98:
			look_at(global_position + facing, up)
	# Range is relative to the thrower at the instant of release. Inherited
	# player motion moves the whole flight through the world without consuming
	# the disk's authored 70 m of forward travel in a handful of frames.
	_travelled += _speed * field_slow * delta
	_trail_travelled += _speed * field_slow * delta
	_linger_travelled += _speed * field_slow * delta
	_try_split()
	if not _emits_blast_bubbles() \
			and _trail_travelled >= CrawlerRules.BUBBLE_TRAIL_SPACING:
		_trail_travelled = 0.0
		CrawlerBubbles.emit_trail(
			shooter, definition.ability_id, global_position, _velocity)
	if not _emits_blast_bubbles() \
			and _linger_travelled >= CrawlerRules.LINGER_TRAIL_SPACING:
		_linger_travelled = 0.0
		CrawlerLingers.emit_trail(
			shooter, definition.ability_id, global_position, _velocity)
	if definition.projectile_type == AbilityDefinition.ProjectileType.ENERGY_BOLT:
		_pulse_bolt(delta)
	elif definition.projectile_type == AbilityDefinition.ProjectileType.ENERGY_ICICLE:
		_pulse_bolt(delta)
	elif definition.projectile_type == AbilityDefinition.ProjectileType.ENERGY_CONE:
		_aim_cone()
		_pierce_cone()
	elif definition.projectile_type != AbilityDefinition.ProjectileType.TELEPORT_ORB:
		_disk.rotation.y += delta * 24.0
	if _travelled >= _range:
		if authoritative and definition.projectile_type \
				in [AbilityDefinition.ProjectileType.ENERGY_ORB,
					AbilityDefinition.ProjectileType.ENERGY_ICICLE,
					AbilityDefinition.ProjectileType.TELEPORT_ORB]:
			var facing := -_velocity.normalized() \
				if _velocity.length_squared() > 0.001 else -_along
			AbilityImpact.apply(
				shooter, definition, global_position, facing, stats, _struck)
		if _is_energy_cone():
			_aim_cone()
			_pierce_cone()
			if is_instance_valid(_shock):
				_shock.stop()
		_emit_blast_bubbles()
		queue_free()


func _land(facing: Vector3) -> void:
	if bounce_off(facing):
		return
	_emit_blast_bubbles()
	_emit_impact_cast(facing)
	if _is_energy_cone():
		if is_instance_valid(_shock):
			_shock.stop()
		queue_free()
		return
	if authoritative:
		var along := facing if facing.length_squared() > 0.001 else -_along
		AbilityImpact.apply(
			shooter, definition, global_position, along, stats, _struck)
	queue_free()


func bounce_off(normal: Vector3) -> bool:
	if _bounces_left <= 0:
		return false
	if definition != null \
			and definition.projectile_type \
				== AbilityDefinition.ProjectileType.TELEPORT_ORB \
			and is_instance_valid(_struck):
		return false
	var incoming := _velocity if _velocity.length_squared() > 0.000001 \
		else _along
	var outgoing := CrawlerBounce.reflect(incoming, normal)
	if outgoing.length_squared() < 0.000001:
		return false
	_bounces_left -= 1
	_emit_impact_cast(normal)
	if CrawlerBounce.explodes_on_bounce(definition):
		_emit_blast_bubbles()
		if authoritative:
			var along := normal if normal.length_squared() > 0.001 else -_along
			AbilityImpact.apply(
				shooter, definition, global_position, along, stats, _struck)
	var speed := _velocity.length() if _velocity.length() > 0.001 else _speed
	_along = outgoing
	_velocity = outgoing * speed
	var at := global_position if is_inside_tree() else position
	at = CrawlerBounce.nudge(at, normal, outgoing)
	if is_inside_tree():
		global_position = at
	else:
		position = at
	_struck = null
	if _is_energy_cone():
		_aim_cone()
	return true


func _flight_up() -> Vector3:
	if is_instance_valid(shooter):
		var up := shooter.global_basis.y
		if up.length_squared() > 0.0001:
			return up.normalized()
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP


func _victim_along(from: Vector3, to: Vector3) -> Node:
	if not is_inside_tree():
		return null
	return CombatantSense.first_along(
		self, from, to, _quoted_radius(), shooter)


func _combatant_from_hit(hit: Dictionary) -> Node:
	var node := hit.get("collider") as Node
	if node == null:
		var collider_id := int(hit.get("collider_id", 0))
		if collider_id != 0:
			node = instance_from_id(collider_id) as Node
	var walk := node
	while walk != null:
		if walk.is_in_group(DamageHit.COMBATANT_GROUP) and walk != shooter:
			return walk
		walk = walk.get_parent()
	return null


func _combat_position(node: Node) -> Vector3:
	return CombatantSense.point_of(node)


func _nearest_on(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var along := to - from
	var span := along.length_squared()
	if span < 0.000001:
		return from
	return from + along * clampf((point - from).dot(along) / span, 0.0, 1.0)


func _try_split() -> void:
	if _split_done or not is_instance_valid(shooter) or definition == null:
		return
	var count := CrawlerMulti.shots(stats)
	if count <= 1 or _travelled < CrawlerRules.MULTI_SPLIT_TRAVEL:
		return
	_split_done = true
	var world := get_parent()
	if world == null:
		return
	var up := CrawlerMulti.up_of(shooter)
	var inherited := _velocity - _along * _speed
	var dirs := CrawlerMulti.fan_dirs(_along, count, up)
	for index in dirs.size():
		var dir: Vector3 = dirs[index]
		if index == 0:
			_along = dir
			_velocity = _along * _speed + inherited
			continue
		var child_stats := stats.duplicate(true)
		child_stats["_multi_child"] = 1.0
		var child := AbilityProjectile.launch(
			world, shooter, definition.ability_id, global_position, dir,
			authoritative, inherited, child_stats)
		if child == null:
			continue
		child._split_done = true
		child._travelled = _travelled
		child._range = _range
		child._bounces_left = _bounces_left


func _pulse_bolt(delta: float) -> void:
	_pulse += delta * 8.5
	var wave := 0.74 + 0.26 * (0.5 + 0.5 * sin(_pulse * TAU))
	if is_instance_valid(_disk):
		var radius := _quoted_radius()
		if _disk is EnergyVfx:
			(_disk as EnergyVfx).set_ball_radius(radius * wave)
		else:
			_disk.scale = Vector3.ONE * wave


func _emit_impact_cast(facing: Vector3) -> void:
	if not authoritative or definition == null:
		return
	var along := facing if facing.length_squared() > 0.001 else -_along
	CrawlerImpactCast.emit(
		shooter, definition.ability_id, global_position, along, stats)


func _emits_blast_bubbles() -> bool:
	return definition != null and definition.impact_type \
		== AbilityDefinition.ImpactType.MASSIVE_BLAST


func _emit_blast_bubbles() -> void:
	if shooter == null or definition == null:
		return
	var reach := maxf(float(stats.get("radius", 1.0)), 0.8)
	CrawlerBubbles.emit_blast(
		shooter, definition.ability_id, global_position, reach)
	CrawlerLingers.emit_blast(
		shooter, definition.ability_id, global_position, reach)


func _cast_tint() -> Color:
	var base := definition.tint if definition != null else Color.WHITE
	if shooter == null or definition == null:
		return base
	return CrawlerElements.tint_of(
		base, CrawlerElements.payload(shooter, definition.ability_id, stats))


func _quoted_radius() -> float:
	var authored := 0.36
	if definition != null:
		authored = float(definition.stats.get("projectile_radius", authored))
	return maxf(float(stats.get("projectile_radius", authored)), 0.08)


func _is_energy_cone() -> bool:
	return definition != null and definition.projectile_type \
		== AbilityDefinition.ProjectileType.ENERGY_CONE


func _cone_radius() -> float:
	var start := maxf(float(stats.get("radius", CrawlerRules.FUS_RADIUS)), 0.25)
	var size := maxf(float(stats.get("size", 1.0)), 0.25)
	var age := _travelled / maxf(_speed, 1.0)
	return start + CrawlerRules.FUS_EXPAND * size * age


func _world_probe_radius() -> float:
	if _is_energy_cone():
		return 0.35
	return _quoted_radius()


func _aim_cone() -> void:
	if is_instance_valid(_shock):
		_shock.visible = false
	if is_instance_valid(_cone_beam):
		_cone_beam.visible = false
	if not is_instance_valid(_ring):
		return
	if not _cone_origin.is_finite():
		_cone_origin = global_position
	var forward := _velocity.normalized() \
		if _velocity.length_squared() > 0.001 else _along
	if forward.length_squared() < 0.001:
		return
	var radius := _cone_radius()
	var thick := maxf(
		float(stats.get("projectile_radius", CrawlerRules.FUS_PROJECTILE_RADIUS)),
		0.28)
	_ring.scale = Vector3(radius, radius, clampf(thick / 0.15, 0.7, 4.0))
	var up := _flight_up()
	if absf(forward.dot(up)) > 0.98:
		up = Vector3.RIGHT if absf(forward.x) < 0.9 else Vector3.FORWARD
	_ring.global_position = global_position
	_ring.look_at(global_position + forward, up)
	_ring.visible = true
	if is_instance_valid(_ring_light):
		_ring_light.omni_range = maxf(radius * 1.8, 3.0)
		_ring_light.light_energy = 2.4 + minf(radius * 0.08, 1.6)


func _pierce_cone() -> void:
	if not authoritative or not _is_energy_cone() or not is_inside_tree():
		return
	var forward := _velocity.normalized() \
		if _velocity.length_squared() > 0.001 else _along
	if forward.length_squared() < 0.001:
		return
	var radius := _cone_radius()
	var thick := maxf(
		float(stats.get("projectile_radius", CrawlerRules.FUS_PROJECTILE_RADIUS)),
		0.35)
	var depth := maxf(thick * 1.15, 0.55)
	var at := global_position
	CombatantSense.ensure(self)
	for combatant in CombatantSense.collect(self, shooter):
		if not combatant.has_method(&"apply_damage"):
			continue
		var key := combatant.get_instance_id()
		if _pierced.has(key):
			continue
		var point := CombatantSense.point_of(combatant)
		var bounds := CombatantSense.radius_of(combatant)
		var offset := point - at
		var along := offset.dot(forward)
		if absf(along) > depth + bounds:
			continue
		var out := offset - forward * along
		var radial := out.length()
		if radial > radius + thick + bounds:
			continue
		_pierced[key] = true
		var shove := forward
		if out.length_squared() > 0.0001:
			shove = (forward * 0.72 + out.normalized() * 0.55).normalized()
		var blow := stats.duplicate(true)
		blow["radius"] = maxf(radius + thick, 0.8)
		AbilityImpact.strike_force(
			shooter, definition, at, shove, blow, combatant)


func _trace_exclude() -> Array[RID]:
	var exclude := DamageHit.rid_list(_shooter_rid)
	if not _is_energy_cone() or not is_inside_tree():
		return exclude
	CombatantSense.ensure(self)
	CombatantSense.append_collision_rids(exclude)
	return exclude


func _trace_step(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude := _trace_exclude()
	var motion := to - from
	if motion.length_squared() < 0.000001:
		return {}
	if _probe == null:
		_probe = SphereShape3D.new()
	_probe.radius = _world_probe_radius()
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
