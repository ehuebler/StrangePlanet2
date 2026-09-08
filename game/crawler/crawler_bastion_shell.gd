class_name CrawlerBastionShell
extends Node3D

## High lob with a teleport-style tracing ribbon. Paints a red iridescent
## circle on the aimed impact, then detonates on the first body or ground
## it hits.

const TRAIL := preload("res://game/abilities/ability_trail.gd")
const BLAST := preload("res://game/abilities/energy_explosion.gd")
const IRIS_SHADER := preload("res://shaders/crawler/crawler_iris_cloud.gdshader")
const LIFETIME := 5.2
const TINT := EnergyVfx.TINT_PINK
const MARK_TINT := Color(1.0, 0.16, 0.08)

var damage := 18.0
var gravity := 32.0
var shot_speed := 24.0
var ball_radius := 0.36
var hit_radius := 2.2
var knockback := 8.0
var ability_id := "crawler_bastion_mortar"
var impact_at := Vector3.INF
var shooter: Node
var _charmed_shot := false
var _velocity := Vector3.ZERO
var _planet: Planet
var _blocker := RID()
var _live := 0.0
var _core: EnergyVfx
var _mark: MeshInstance3D
var _spent := false
var _charm_frame := -1
var _trail: AbilityTrail


func launch_anywhere(host: Node, from: Vector3, along: Vector3, by: Node) -> bool:
	if host == null or not from.is_finite() or not along.is_finite() \
			or along.is_zero_approx():
		return false
	name = "CrawlerBastionShell"
	_velocity = along
	shooter = by
	_charmed_shot = _read_shooter_charmed()
	var body := by as CollisionObject3D
	if body != null:
		_blocker = body.get_rid()
	host.add_child(self)
	global_position = from
	_trail = TRAIL.create(host, from, maxf(ball_radius * 1.6, 0.16), TINT)
	_show_mark()
	set_physics_process(true)
	return true


func _ready() -> void:
	_planet = get_parent() as Planet
	_core = EnergyVfx.make(EnergyVfx.Kind.PROJECTILE, TINT)
	add_child(_core)
	_core.set_ball_radius(ball_radius)


func _exit_tree() -> void:
	_clear_mark()
	if is_instance_valid(_trail):
		_trail.linger(0.55)
		_trail = null


func _physics_process(delta: float) -> void:
	_live += delta
	if _live >= LIFETIME:
		queue_free()
		return
	var up := _up()
	_velocity -= up * maxf(gravity, 0.0) * delta
	var from := global_position
	var to := from + _velocity * delta
	var struck := _victim_along(from, to)
	if struck != null:
		global_position = _nearest_on(from, to, _combat_position(struck))
		detonate()
		return
	if not is_inside_tree():
		return
	var query := PhysicsRayQueryParameters3D.create(from, to)
	if _blocker.is_valid():
		query.exclude = DamageHit.rid_list(_blocker)
	var landed := get_world_3d().direct_space_state.intersect_ray(query)
	if landed.is_empty():
		global_position = to
		if is_instance_valid(_trail):
			_trail.add_point(global_position)
		return
	global_position = landed["position"]
	detonate()


func detonate() -> void:
	if _spent:
		return
	_spent = true
	if is_instance_valid(_trail):
		_trail.add_point(global_position)
		_trail.linger(0.55)
		_trail = null
	_clear_mark()
	BLAST.burst(get_parent(), global_position, maxf(hit_radius, 1.2), TINT, 0.38)
	if _is_host():
		_deal_aoe(global_position)
	queue_free()


func _deal_aoe(at: Vector3) -> void:
	if not is_inside_tree():
		return
	var blast := _make_blast(at)
	for node in _hurt_targets():
		if not node.has_method(&"apply_damage"):
			continue
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = float(node.call(&"combat_radius"))
		if not blast.reaches(_combat_position(node), bounds):
			continue
		node.call(&"apply_damage", blast.resolved_for(node))


func _make_blast(at: Vector3) -> DamageHit:
	var along := _velocity.normalized() \
		if _velocity.length_squared() > 0.01 else -_up()
	var blast := DamageHit.area(at, hit_radius, damage, 0.4)
	blast.faction = DamageHit.Faction.PLAYER if _shooter_charmed() \
		else DamageHit.Faction.ENEMY
	blast.parryable = true
	blast.reaction = DamageHit.Reaction.KNOCKBACK
	blast.world_impulse = along * knockback * 0.25
	blast.radial_impulse = knockback
	blast.radial_lift = knockback * 0.35
	blast.affects_flora = false
	blast.ability_id = ability_id
	blast.projectile = true
	if is_instance_valid(shooter):
		blast.set_source(shooter)
	return blast


func _victim_along(from: Vector3, to: Vector3) -> Node:
	var sweep := DamageHit.beam(from, to, hit_radius * 0.45, 0.0)
	if not is_inside_tree():
		return null
	for node in _hurt_targets():
		if not is_instance_valid(node):
			continue
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = float(node.call(&"combat_radius"))
		if sweep.reaches(_combat_position(node), bounds):
			return node
	return null


func _hurt_targets() -> Array[Node]:
	var found: Array[Node] = []
	if not is_inside_tree():
		return found
	CrawlerMobSense.ensure_frame(get_tree())
	for node_variant: Variant in CrawlerMobSense.shot_targets(_shooter_charmed()):
		var node := node_variant as Node
		if node != null and _should_hurt(node):
			found.append(node)
	return found


func _should_hurt(node: Node) -> bool:
	if not is_instance_valid(node) or node == shooter:
		return false
	if not node is Node3D:
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return false
	if _shooter_charmed():
		return node is CrawlerMob
	return node.is_in_group(&"network_players")


func _shooter_charmed() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _charm_frame:
		_charm_frame = frame
		_charmed_shot = _read_shooter_charmed() if is_instance_valid(shooter) \
			else false
	return _charmed_shot


func _read_shooter_charmed() -> bool:
	if not is_instance_valid(shooter):
		return false
	var mob := shooter as CrawlerMob
	return mob != null and mob.is_charmed()


func _nearest_on(from: Vector3, to: Vector3, point: Vector3) -> Vector3:
	var along := to - from
	var span := along.length_squared()
	if span < 0.000001:
		return from
	return from + along * clampf((point - from).dot(along) / span, 0.0, 1.0)


func _combat_position(player: Node) -> Vector3:
	if not is_instance_valid(player):
		return global_position
	if player.has_method(&"combat_position"):
		return player.call(&"combat_position")
	var body := player as Node3D
	return body.global_position if body != null else global_position


func _up() -> Vector3:
	if _planet != null:
		return _planet.up_at(global_position)
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP


func _show_mark() -> void:
	_clear_mark()
	var at := impact_at if impact_at.is_finite() else global_position
	if not at.is_finite():
		return
	var up := _up_at(at)
	var reach := maxf(hit_radius, 1.2)
	var material := ShaderMaterial.new()
	material.shader = IRIS_SHADER
	material.set_shader_parameter(&"tint", MARK_TINT)
	material.set_shader_parameter(&"alpha", 0.78)
	material.set_shader_parameter(&"spark", 1.35)
	material.set_shader_parameter(&"iris", 1.1)
	material.set_shader_parameter(&"edge_width", 0.38)
	var disk := CylinderMesh.new()
	disk.top_radius = reach
	disk.bottom_radius = reach
	disk.height = 0.08
	disk.radial_segments = 36
	disk.rings = 0
	_mark = MeshInstance3D.new()
	_mark.name = "BastionMark"
	_mark.mesh = disk
	_mark.material_override = material
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark.top_level = true
	add_child(_mark)
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.0001:
		side = up.cross(Vector3.RIGHT)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	_mark.global_transform = Transform3D(
		Basis(side, up, side.cross(up)).orthonormalized(),
		at + up * 0.05)


func _clear_mark() -> void:
	if is_instance_valid(_mark):
		_mark.queue_free()
	_mark = null


func _up_at(at: Vector3) -> Vector3:
	if _planet != null:
		return _planet.up_at(at)
	return Vector3.UP


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
