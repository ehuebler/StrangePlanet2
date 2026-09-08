class_name CrawlerRiftHulk
extends CrawlerMob

## Grounded brute. Walks the planet surface and slams anything that comes close.

const HEIGHT := 6.4
const WIDTH := 2.7
const REACH := 5.6
const SLAM_COOLDOWN := 1.35


var _slam_left := 0.0


func _ready() -> void:
	_base_health = 20.0
	_base_damage = 20.0
	_base_speed = 11.0
	super._ready()
	motion_mode = MOTION_MODE_FLOATING


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, WIDTH * 0.82)
	shape.shape = box
	add_child(shape)
	var torso := BoxMesh.new()
	torso.size = Vector3(WIDTH, HEIGHT * 0.62, WIDTH * 0.78)
	var body := _make_mesh(torso, Color(0.12, 0.04, 0.05), 1.4)
	body.position = Vector3(0.0, HEIGHT * 0.06, 0.0)
	var head := BoxMesh.new()
	head.size = Vector3(WIDTH * 0.62, HEIGHT * 0.28, WIDTH * 0.58)
	var crown := _make_mesh(head, Color(0.20, 0.06, 0.07), 1.7)
	crown.position = Vector3(0.0, HEIGHT * 0.38, WIDTH * 0.06)


func wild_kind() -> String:
	return "rift_hulk"


func combat_display_name() -> String:
	return "Rift-Hulk"


func combat_position() -> Vector3:
	return global_position + _up() * (HEIGHT * 0.35)


func combat_radius() -> float:
	return WIDTH * 0.62


func ground_clearance() -> float:
	return HEIGHT * 0.5


func _tick_idle(delta: float) -> void:
	_patrol_ground(delta)


func _tick_ai(delta: float) -> void:
	snap_to_ground()
	_slam_left = maxf(_slam_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	var at := _combat_position_of(player)
	var along := _tangent_toward(at)
	_match_speed(move_speed(), delta, 1.4, 8.0)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 12.0)
	var reach := REACH
	if player.has_method(&"combat_radius"):
		reach += float(player.call(&"combat_radius"))
	if global_position.distance_to(at) <= reach and _slam_left <= 0.0:
		_slam(player)


func _patrol_ground(delta: float) -> void:
	_match_speed(move_speed() * 0.45, delta, 1.4, 6.0)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or global_position.distance_to(_patrol_goal) < 3.0:
		_patrol_left = PATROL_RETARGET + hash(mob_id) % 11 * 0.1
		_patrol_goal = _wander_point()
	var along := _tangent_toward(_patrol_goal)
	if along.length_squared() < 0.2:
		velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 8.0)


func _wander_point() -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(mob_id + str(int(Time.get_ticks_msec() / 2200))) & 0x7fffffff)
	var yaw := rng.randf() * TAU
	var reach := rng.randf_range(8.0, CrawlerRules.PATROL_RADIUS)
	var at := hang_origin + (east * cos(yaw) + north * sin(yaw)) * reach
	if _planet != null:
		var local := _planet.to_local(at)
		if local.length_squared() < 0.0001:
			local = _up()
		var surface := ground_surface(at)
		if surface.is_finite():
			at = surface + _planet.up_at(surface) * ground_clearance()
		else:
			var mesh := _planet.mesh_position(local)
			at = mesh + _planet.up_at(mesh) * ground_clearance()
	return at


func _tangent_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _stick_to_surface() -> void:
	snap_to_ground()


func _slam(player: Node) -> void:
	if not _alive:
		return
	_slam_left = SLAM_COOLDOWN
	var hit := DamageHit.area(combat_position(), REACH + 0.8, damage(), 0.4)
	hit.kind = DamageHit.Kind.AREA
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_hulk_slam"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.radial_impulse = 8.0
	hit.radial_lift = 4.0
	hit.set_source(self)
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		player.call(&"apply_damage", hit)
