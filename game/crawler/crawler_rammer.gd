class_name CrawlerRammer
extends CrawlerMob

## Winged eyeball. Circles high while idle. Once agroed it glides down into a
## low station in front of the camera, then rams from there so the run stays
## on screen instead of arriving from behind or overhead.

const MODEL := preload("res://assets/runtime/fauna/models/rift_oculus.glb")
const PAINT := preload("res://assets/runtime/biomes/paint/rift_oculus_paint.png")

const RADIUS := 1.35
const AUTHORED_HEIGHT := 2.05
const DETONATE_PAD := 0.85
const DETONATE_CROWN := 2.8
const LUNGE_RANGE := 14.0
const ATTACK_SECONDS := 0.93
const SOAR_FLOOR := 18.0
const SOAR_CEILING := 36.0
const SOAR_RADIUS := 24.0
const SOAR_PACE := 0.62
const SHOW_AHEAD := 17.0
const SHOW_DROP := 2.2
const SHOW_SIDE := 2.8
const SHOW_READY := 5.4
const HOOK_SIDE := 12.0
const HOOK_AHEAD := 6.0
const VIEW_DOT := 0.42
const STAGE_FLOOR := 2.2
const STAGE_CEILING := 10.5
const DESCENT := 7.5
const DESCENT_CAP := 9.0
const DESCENT_READY := 3.2
const RAM_ABORT := 24.0
const CLOSE_RAM := 7.5

enum Phase { SOAR, STAGE, RAM }

var _soar_angle := 0.0
var _soar_radius := SOAR_RADIUS
var _soar_loft := 24.0
var _soar_sign := 1.0
var _phase: Phase = Phase.SOAR
var _ram_heading := Vector3.ZERO
var _glide_loft := -1.0
var _cached_soar_centre := Vector3.ZERO
var _cached_soar_home := Vector3.INF
var _soar_frame := -1


func _ready() -> void:
	_base_health = 4.0
	_base_damage = 15.0
	_base_speed = 12.0
	_faces_motion = true
	super._ready()
	_cruise = 0.0
	velocity = Vector3.ZERO
	_ready_soar()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = RADIUS
	shape.shape = ball
	add_child(shape)
	_attach_creature(
		MODEL, PAINT, AUTHORED_HEIGHT, RADIUS * 2.0, Color(0.18, 0.05, 0.06))


func wild_kind() -> String:
	return "rammer"


func combat_display_name() -> String:
	return "Rammer"


func combat_position() -> Vector3:
	return global_position


func combat_radius() -> float:
	return RADIUS


func flyer_floor() -> float:
	if _phase == Phase.RAM:
		return 0.48
	if chase:
		return STAGE_FLOOR
	return SOAR_FLOOR


func flyer_ceiling() -> float:
	# Hold the soar ceiling while gliding down. Snapping it to the show
	# band makes the shared flyer clamp slam them to eye level in a frame.
	if _phase == Phase.RAM:
		return STAGE_CEILING
	return SOAR_CEILING


func staging() -> bool:
	return _phase == Phase.STAGE


func ramming() -> bool:
	return _phase == Phase.RAM


func _keep_clear_of_terrain(snap: bool) -> void:
	if _phase != Phase.RAM:
		super._keep_clear_of_terrain(snap)
		return
	if _planet == null:
		return
	var up := _up()
	var altitude := surface_altitude()
	var floor_h := 0.32
	if snap and altitude < floor_h:
		global_position += up * (floor_h - altitude)
	if altitude < floor_h:
		var down := -velocity.dot(up)
		if down > 0.0:
			velocity += up * down


func _tick_idle(delta: float) -> void:
	_phase = Phase.SOAR
	_ram_heading = Vector3.ZERO
	_glide_loft = -1.0
	_soar_circle(delta)


func _tick_ai(delta: float) -> void:
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	if _phase == Phase.RAM:
		_update_ram(player, delta)
		return
	_phase = Phase.STAGE
	_update_stage(player, delta)
	if _ready_to_ram(player):
		_begin_ram(player)
		_update_ram(player, delta)


func _update_stage(player: Node, delta: float) -> void:
	var at := _combat_position_of(player)
	var offset := at - global_position
	var distance := offset.length()
	var top := CrawlerRules.rammer_top_speed(_player_speed(player), threat_level)
	_match_speed(top, delta, 0.34, CrawlerMobs.number(
		"rammer", threat_level, "ram_accel", CrawlerRules.RAMMER_ACCEL))
	if _blast_reaches(player, offset, distance):
		_detonate(player)
		return
	_tick_glide(delta, player)
	var goal := stage_goal(player)
	var along := goal - global_position
	if along.length_squared() < 0.0001:
		_limit_descent()
		return
	_steer_toward(along.normalized() * _cruise, delta, 11.0)
	_limit_descent()


func _begin_ram(player: Node) -> void:
	_phase = Phase.RAM
	_ram_heading = _ram_along(player)
	var distance := global_position.distance_to(_combat_position_of(player))
	if distance <= LUNGE_RANGE and not _attacking():
		_begin_attack(ATTACK_SECONDS)


func _update_ram(player: Node, delta: float) -> void:
	var at := _combat_position_of(player)
	var offset := at - global_position
	var distance := offset.length()
	if distance > RAM_ABORT and not in_camera(player):
		_phase = Phase.STAGE
		_ram_heading = Vector3.ZERO
		_update_stage(player, delta)
		return
	var top := CrawlerRules.rammer_top_speed(_player_speed(player), threat_level)
	_match_speed(top, delta, 0.22, CrawlerMobs.number(
		"rammer", threat_level, "ram_accel", CrawlerRules.RAMMER_ACCEL))
	if _blast_reaches(player, offset, distance):
		_detonate(player)
		return
	var want := _ram_along(player)
	if _ram_heading.length_squared() > 0.0001:
		_ram_heading = _ram_heading.lerp(want, clampf(delta * 5.0, 0.0, 1.0))
		if _ram_heading.length_squared() > 0.0001:
			_ram_heading = _ram_heading.normalized()
	else:
		_ram_heading = want
	_steer_toward(_ram_heading * _cruise, delta, 9.0)
	if distance <= LUNGE_RANGE and not _attacking():
		_begin_attack(ATTACK_SECONDS)


func _ready_to_ram(player: Node) -> bool:
	if player == null or not in_camera(player):
		return false
	var distance := global_position.distance_to(_combat_position_of(player))
	if _height_above_station(player) > DESCENT_READY:
		return false
	if distance <= CLOSE_RAM:
		return true
	return global_position.distance_to(show_station(player)) <= SHOW_READY


func _ram_along(player: Node) -> Vector3:
	var at := _combat_position_of(player)
	var distance := global_position.distance_to(at)
	var top := CrawlerRules.rammer_top_speed(_player_speed(player), threat_level)
	var flight := distance / maxf(top, 8.0)
	var intercept := at + _player_velocity(player) * clampf(flight, 0.0, 0.85)
	var along := intercept - global_position
	if along.length_squared() < 0.0001:
		along = at - global_position
	return along.normalized() if along.length_squared() > 0.0001 else _player_view(player)


func in_camera(player: Node) -> bool:
	if player == null:
		return false
	var to := global_position - _view_origin(player)
	if to.length_squared() < 1.2:
		return true
	return to.normalized().dot(_player_view(player)) >= VIEW_DOT


func show_station(player: Node) -> Vector3:
	var origin := _view_origin(player)
	var look := _player_view(player)
	var lift := _view_up(player)
	var right := look.cross(lift)
	if right.length_squared() < 0.0001:
		right = lift.cross(Vector3.RIGHT)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	return origin + look * SHOW_AHEAD - lift * SHOW_DROP + right * SHOW_SIDE * _flank_sign()


func stage_goal(player: Node) -> Vector3:
	return _with_loft(_stage_home(player), _glide_loft if _glide_loft >= 0.0 \
		else _altitude())


func _stage_home(player: Node) -> Vector3:
	var station := show_station(player)
	if in_camera(player):
		return station
	var origin := _view_origin(player)
	var look := _player_view(player)
	var lift := _view_up(player)
	var right := look.cross(lift)
	if right.length_squared() < 0.0001:
		return station
	right = right.normalized()
	var away := global_position - origin
	away -= lift * away.dot(lift)
	var side := signf(away.dot(right))
	if is_zero_approx(side):
		side = _flank_sign()
	return origin + right * side * HOOK_SIDE + look * HOOK_AHEAD - lift * SHOW_DROP


func _tick_glide(delta: float, player: Node) -> void:
	var want := _altitude(show_station(player))
	if _glide_loft < 0.0:
		_glide_loft = _altitude()
	_glide_loft = move_toward(_glide_loft, want, DESCENT * maxf(delta, 0.0))


func _limit_descent() -> void:
	var up := _up()
	var down := -velocity.dot(up)
	if down > DESCENT_CAP:
		velocity += up * (down - DESCENT_CAP)


func _height_above_station(player: Node) -> float:
	return _altitude() - _altitude(show_station(player))


func _altitude(at := Vector3.INF) -> float:
	var point := at if at.is_finite() else global_position
	if _planet != null:
		return surface_altitude(point)
	return point.dot(_up())


func _with_loft(at: Vector3, loft: float) -> Vector3:
	if not at.is_finite():
		return at
	return at + _up() * (loft - _altitude(at))


func _flank_sign() -> float:
	return -1.0 if (hash(mob_id) & 1) == 0 else 1.0


func _view_origin(player: Node) -> Vector3:
	var camera := _player_camera(player)
	if camera != null:
		return camera.global_position
	return _combat_position_of(player)


func _player_view(player: Node) -> Vector3:
	if player != null and player.has_method(&"look_direction"):
		var look: Variant = player.call(&"look_direction")
		if look is Vector3 and (look as Vector3).is_finite() \
				and (look as Vector3).length_squared() > 0.0001:
			return (look as Vector3).normalized()
	var lift := _view_up(player)
	var motion := _player_velocity(player)
	motion -= lift * motion.dot(lift)
	if motion.length_squared() > 0.36:
		return motion.normalized()
	if player is Node3D:
		var facing := -(player as Node3D).global_transform.basis.z
		if facing.length_squared() > 0.0001:
			return facing.normalized()
	return Vector3.FORWARD


func _view_up(player: Node) -> Vector3:
	var camera := _player_camera(player)
	if camera != null:
		var lift := camera.global_basis.y
		if lift.length_squared() > 0.0001:
			return lift.normalized()
	if player is Node3D:
		var lift := (player as Node3D).global_transform.basis.y
		if lift.length_squared() > 0.0001:
			return lift.normalized()
	return _up()


func _player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	var held: Variant = player.get(&"camera")
	return held as Camera3D if held is Camera3D else null


func _ready_soar() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(mob_id) * 53 + 11) & 0x7fffffff)
	_soar_angle = rng.randf() * TAU
	_soar_radius = rng.randf_range(SOAR_RADIUS * 0.7, SOAR_RADIUS * 1.35)
	_soar_loft = rng.randf_range(SOAR_FLOOR + 2.0, SOAR_CEILING - 2.0)
	_soar_sign = -1.0 if rng.randf() < 0.5 else 1.0


func soar_point() -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	return _soar_centre() \
		+ (east * cos(_soar_angle) + north * sin(_soar_angle)) * _soar_radius


func _soar_centre() -> Vector3:
	var frame := Engine.get_physics_frames()
	var home := hang_origin if hang_origin.length_squared() > 0.25 \
		else global_position
	if frame == _soar_frame \
			or (home.distance_squared_to(_cached_soar_home) < 4.0 \
			and _cached_soar_centre.length_squared() > 0.01):
		return _cached_soar_centre
	var up := _up()
	var centre := home + up * _soar_loft
	if _planet != null:
		var local := _planet.to_local(home)
		if local.length_squared() < 0.0001:
			local = up
		var surface := _planet.mesh_position(local)
		centre = surface + _planet.up_at(surface) * _soar_loft
	_soar_frame = frame
	_cached_soar_home = home
	_cached_soar_centre = centre
	return centre


func _soar_circle(delta: float) -> void:
	_match_speed(move_speed() * SOAR_PACE, delta, 1.3, 6.0)
	var radius := maxf(_soar_radius, 8.0)
	_soar_angle += _soar_sign * (_cruise / radius) * delta
	var up := _up()
	var goal := soar_point()
	var radial := goal - _soar_centre()
	radial -= up * radial.dot(up)
	var tangent := up.cross(radial)
	if tangent.length_squared() < 0.0001:
		tangent = _orbit_bias()
		tangent -= up * tangent.dot(up)
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized() * _soar_sign
	var spring := (goal - global_position) * 0.55
	_steer_toward(tangent * _cruise + spring, delta, 7.5)


func _blast_reaches(player: Node, offset: Vector3, distance: float) -> bool:
	var reach := combat_radius() + DETONATE_PAD
	if player != null and player.has_method(&"combat_radius"):
		reach += float(player.call(&"combat_radius"))
	if distance <= reach:
		return true
	var up := _up()
	var flat := offset - up * offset.dot(up)
	return flat.length() <= combat_radius() + 0.55 \
		and absf(offset.dot(up)) <= DETONATE_CROWN


func _detonate(player: Node) -> void:
	if not _alive:
		return
	var hit := DamageHit.area(global_position, combat_radius() + 1.6, damage(), 0.35)
	hit.kind = DamageHit.Kind.AREA
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_ram"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.radial_impulse = 10.0
	hit.radial_lift = 3.0
	if is_instance_valid(self):
		hit.set_source(self)
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		player.call(&"apply_damage", hit)
	_die()
