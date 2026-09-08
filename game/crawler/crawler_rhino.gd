class_name CrawlerRhino
extends CrawlerMob

## Ground charger. Meteor strike is the only attack: line up on a slow
## target, match a runner with lag and cut in front, then dash through the
## intercept. A player who is already close is backed away from first.

const MODEL := preload("res://assets/runtime/fauna/models/cinder_plate_rhino.glb")
const PAINT := preload("res://assets/runtime/biomes/paint/cinder_plate_rhino_paint.png")

const HEIGHT := 2.4
const AUTHORED_HEIGHT := 1.85
const CLIP_PAW := "Paw"
const CLIP_CHARGE := "Charge"
const CLIP_GORE := "Gore"
const CHARGE_FROM := 20.0
const CHARGE_MINIMUM := 8.0
const CHARGE_SECONDS := 1.15
const CHARGE_TURN := 1.6
const CHARGE_RECOVER := 0.85
const CHARGE_OVERRUN := 2.2
const CHARGE_MUL := 2.2
const PAW_SECONDS := 0.95
const PAW_COMMIT := 0.28
const PAW_TURN := 16.0
const GORE_CLIP_SECONDS := 0.5
const ATTACK_COOLDOWN := 3.2
const ATTACK_RANGE := 2.8
const ATTACK_RADIUS := 1.2
const ATTACK_KNOCKBACK := 20.0
const SLAM_RANGE := 4.8
const SLAM_RADIUS := 5.2
const SLAM_FALLOFF := 0.45
const CRATER_RADIUS := 4.4
const CRATER_DEPTH := 1.7
const SHOCK_RADIUS := 2.8
const METEOR_TINT := Color(1.0, 0.22, 0.10)
const FLORA_MARGIN := 0.6
const FLORA_DAMAGE := 6000.0
const LINE_AHEAD := 10.0
const LINE_HOOK := 2.2
const LINE_SIDE := 4.2
const LINE_READY := 3.4
const LEAD_HOOK := 1.6
const LEAD_READY := 5.5
const BACKUP_GAP := 12.0
const MATCH_SHARE := 0.88
const MATCH_LOCK := 2.1

enum Phase { PATROL, STALK, PAW, CHARGE, RECOVER }

var _phase: Phase = Phase.PATROL
var _charge_heading := Vector3.ZERO
var _charge_left := 0.0
var _recover_left := 0.0
var _cooldown_left := 0.0
var _phase_elapsed := 0.0
var _gore_show_left := 0.0
var _horn_hit := false
var _slammed := false
var _shock: MeteorShock
var _face := Vector3.ZERO
var _flank_sign := 0
var _lagged_frame := Vector3.ZERO


func _ready() -> void:
	_base_health = 12.0
	_base_damage = 13.0
	_base_speed = 7.0
	_faces_motion = false
	super._ready()
	motion_mode = MOTION_MODE_FLOATING


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = HEIGHT * 0.40
	capsule.height = HEIGHT * 0.74
	shape.shape = capsule
	add_child(shape)
	_attach_creature(
		MODEL, PAINT, AUTHORED_HEIGHT, HEIGHT, Color(0.22, 0.10, 0.08))


func _bind_animator(model: Node) -> void:
	super._bind_animator(model)
	var charge := _resolve_clip(CLIP_CHARGE)
	if _animator != null and not charge.is_empty() and _animator.has_animation(charge):
		_animator.get_animation(charge).loop_mode = Animation.LOOP_LINEAR


func wild_kind() -> String:
	return "rhino"


func combat_display_name() -> String:
	return "Rhino"


func combat_position() -> Vector3:
	return global_position + _up() * (HEIGHT * 0.28)


func combat_radius() -> float:
	return HEIGHT * 0.50


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _gore_show_left > 0.0:
		return CLIP_GORE
	if _phase == Phase.PAW:
		return CLIP_PAW
	if _phase == Phase.CHARGE:
		return CLIP_CHARGE
	if _flash_left > 0.04 and _phase != Phase.CHARGE:
		return CLIP_HIT
	var speed := velocity.length()
	if speed >= RUN_CLIP_SPEED or _phase == Phase.RECOVER:
		return CLIP_RUN
	if speed >= WALK_CLIP_SPEED * 0.35:
		return CLIP_WALK
	return CLIP_IDLE


func _process(delta: float) -> void:
	super._process(delta)
	_update_meteor_shock()


func _tick_idle(delta: float) -> void:
	_abort_charge()
	_patrol_ground(delta)
	_face_along(_face if _face.length_squared() > 0.01 else velocity, delta)


func _tick_ai(delta: float) -> void:
	snap_to_ground()
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_gore_show_left = maxf(_gore_show_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	match _phase:
		Phase.PAW:
			_update_paw(player, delta)
		Phase.CHARGE:
			_update_charge(player, delta)
		Phase.RECOVER:
			_update_recover(player, delta)
		_:
			_stalk(player, delta)
	_face_along(_face if _face.length_squared() > 0.01 else velocity, delta)


func _patrol_ground(delta: float) -> void:
	_phase = Phase.PATROL
	_flank_sign = 0
	_lagged_frame = Vector3.ZERO
	_match_speed(move_speed() * 0.78, delta, 1.5, 7.0)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or global_position.distance_to(_patrol_goal) < 3.4:
		_patrol_serial += 1
		_patrol_left = PATROL_RETARGET + float(_patrol_serial % 5) * 0.45
		_patrol_goal = _wander_point()
	var along := _tangent_toward(_patrol_goal)
	if along.length_squared() < 0.2:
		velocity = velocity.move_toward(Vector3.ZERO, 10.0 * delta)
		_face = along
		return
	_steer_toward(along.normalized() * _cruise, delta, 9.0)
	_face = along


func _stalk(player: Node, delta: float) -> void:
	_phase = Phase.STALK
	_ensure_flank(player)
	if _too_close(player):
		_backup(player, delta)
		return
	if _player_running(player):
		_chase_runner(player, delta)
	else:
		_line_up(player, delta)


func _backup(player: Node, delta: float) -> void:
	_tick_lag(player, delta)
	var along := _tangent_toward(_backup_station(player))
	var heading := along.normalized() if along.length_squared() > 0.0001 \
		else -_player_ahead(player)
	_match_speed(move_speed() * 1.2, delta, 2.2, 14.0)
	_steer_toward(heading * _cruise, delta, 16.0)
	var toward := _tangent_toward(_combat_position_of(player))
	_face = toward if toward.length_squared() > 0.0001 else _player_ahead(player)


func _chase_runner(player: Node, delta: float) -> void:
	var station := _lead_station(player)
	var gap := _tangent_toward(station).length()
	var pace := CrawlerRules.rhino_chase_speed(
		_flat_player_velocity(player).length(), threat_level, gap > 16.0)
	var relative := clampf(gap * 0.55, move_speed() * 0.35, move_speed() * 1.25)
	if gap > 10.0:
		relative = maxf(relative, pace - _lagged_frame.length())
	_ride(player, station, relative, delta, 12.0)
	_face = _player_ahead(player)
	if _cooldown_left <= 0.0 and _lead_ready(player):
		_begin_paw(_intercept_heading(player))


func _line_up(player: Node, delta: float) -> void:
	var station := _line_station(player)
	var gap := _tangent_toward(station).length()
	var relative := clampf(gap * 0.8, move_speed() * 0.45, move_speed() * 1.25)
	_ride(player, station, relative, delta, 12.0)
	var aim := _intercept_heading(player)
	_face = aim
	if _cooldown_left <= 0.0 and _line_ready(player):
		_begin_paw(aim)


func _begin_paw(heading: Vector3) -> void:
	_phase = Phase.PAW
	_phase_elapsed = 0.0
	_horn_hit = false
	_slammed = false
	_charge_heading = heading.normalized() if heading.length_squared() > 0.0001 \
		else _flat_forward()
	_face = _charge_heading


func _update_paw(player: Node, delta: float) -> void:
	_phase_elapsed += delta
	_ensure_flank(player)
	if _too_close(player):
		_phase = Phase.STALK
		_backup(player, delta)
		return
	var aim := _intercept_heading(player)
	_charge_heading = _turn_toward(_charge_heading, aim, PAW_TURN * delta)
	_face = _charge_heading
	if _player_running(player):
		_ride(player, _lead_station(player), 0.0, delta, 10.0)
	else:
		_ride(player, global_position, 0.0, delta, 16.0)
	if _phase_elapsed >= PAW_SECONDS \
			or (_phase_elapsed >= PAW_COMMIT and _facing(aim)):
		_begin_charge(player)


func _begin_charge(player: Node) -> void:
	_ensure_flank(player)
	_charge_heading = _intercept_heading(player)
	_charge_left = CHARGE_SECONDS
	_phase_elapsed = 0.0
	_horn_hit = false
	_slammed = false
	_phase = Phase.CHARGE
	_face = _charge_heading


func _update_charge(player: Node, delta: float) -> void:
	_charge_left = maxf(_charge_left - delta, 0.0)
	_phase_elapsed += delta
	_tick_lag(player, delta)
	if _charge_heading.length_squared() < 0.0001:
		_charge_heading = _intercept_heading(player)
	var want := _intercept_heading(player)
	_charge_heading = _turn_toward(_charge_heading, want, CHARGE_TURN * delta)
	_match_speed(_charge_speed(), delta, 2.2, 18.0)
	_steer_toward(_charge_heading * _cruise, delta, 22.0)
	_face = _charge_heading
	if _should_slam(player):
		_slam_meteor(player)
		return


func _update_recover(player: Node, delta: float) -> void:
	_recover_left = maxf(_recover_left - delta, 0.0)
	var share := _recover_left / maxf(CHARGE_RECOVER, 0.0001)
	if player != null:
		_ensure_flank(player)
		_tick_lag(player, delta)
		if _too_close(player):
			_backup(player, delta)
		else:
			var station := _lead_station(player) if _player_running(player) \
				else _line_station(player)
			_ride(player, station, _charge_speed() * share * share, delta, 10.0)
			_face = _player_ahead(player)
	else:
		_match_speed(_charge_speed() * share * share, delta, 2.4, 16.0)
		if _charge_heading.length_squared() > 0.0001:
			_steer_toward(_charge_heading * _cruise, delta, 10.0)
			_face = _charge_heading
	if _recover_left <= 0.0:
		_phase = Phase.STALK


func _end_charge() -> void:
	_charge_left = 0.0
	_recover_left = CHARGE_RECOVER
	_cooldown_left = ATTACK_COOLDOWN
	_phase_elapsed = 0.0
	_phase = Phase.RECOVER


func _abort_charge() -> void:
	if _phase != Phase.PAW and _phase != Phase.CHARGE and _phase != Phase.RECOVER:
		return
	_charge_left = 0.0
	_recover_left = 0.0
	_phase_elapsed = 0.0
	_horn_hit = false
	_slammed = false
	if _phase == Phase.CHARGE or _phase == Phase.PAW:
		_cooldown_left = maxf(_cooldown_left, ATTACK_COOLDOWN * 0.5)
	_phase = Phase.PATROL


func _ran_past(player: Node) -> bool:
	var along := _tangent_toward(_combat_position_of(player))
	if along.length_squared() < 0.0001:
		return false
	return along.normalized().dot(_charge_heading) < -0.15 \
		and along.length() > CHARGE_OVERRUN


func slam_radius() -> float:
	return SLAM_RADIUS


func meteor_shock() -> MeteorShock:
	if not is_instance_valid(_shock):
		_shock = MeteorShock.new()
		_shock.name = "MeteorShock"
		_shock.radius = SHOCK_RADIUS
		add_child(_shock, false, Node.INTERNAL_MODE_BACK)
	return _shock


func _charging_visually() -> bool:
	var clip := _network_clip if not _is_host() and not _network_clip.is_empty() \
		else _desired_clip()
	return clip == CLIP_PAW or clip == CLIP_CHARGE \
		or clip.ends_with("/" + CLIP_PAW) or clip.ends_with("/" + CLIP_CHARGE)


func _update_meteor_shock() -> void:
	if not _alive or not _charging_visually():
		if is_instance_valid(_shock):
			_shock.stop()
		return
	var heading := _charge_heading
	if heading.length_squared() < 0.0001:
		heading = velocity
	if heading.length_squared() < 0.0001:
		heading = _flat_forward()
	var clip := _desired_clip() if _is_host() else _network_clip
	var winding := clip == CLIP_PAW or clip.ends_with("/" + CLIP_PAW)
	var speed := 88.0 if winding else maxf(velocity.length() * 5.0, 120.0)
	meteor_shock().aim(
		combat_position() + heading.normalized() * 0.85, heading, speed)


func _should_slam(player: Node) -> bool:
	if _slammed:
		return false
	if _charge_left <= 0.0 or _ran_past(player):
		return true
	return player != null and _gap(player) <= SLAM_RANGE


func _slam_meteor(player: Node) -> void:
	if _slammed:
		return
	_slammed = true
	_horn_hit = true
	_gore_show_left = GORE_CLIP_SECONDS
	var heading := _charge_heading if _charge_heading.length_squared() > 0.0001 \
		else _flat_forward()
	var at := _slam_point(heading)
	_play_meteor_vfx(at)
	if _is_host():
		_apply_meteor_blow(at, heading, player)
		_cut_crater(at)
	if is_instance_valid(_shock):
		_shock.stop()
	_end_charge()


func _slam_point(heading: Vector3) -> Vector3:
	var guess := global_position + heading.normalized() * 1.6
	if _planet != null:
		var local := _planet.to_local(guess)
		if local.length_squared() < 0.0001:
			local = _up()
		var hit := ground_surface(guess)
		if hit.is_finite():
			return hit
		return _planet.mesh_position(local)
	return guess


func _play_meteor_vfx(at: Vector3) -> void:
	if _horde != null and _horde.has_method(&"publish_rhino_meteor"):
		_horde.call(&"publish_rhino_meteor", at, SLAM_RADIUS)
		return
	_spawn_meteor_vfx(at, SLAM_RADIUS)


func _spawn_meteor_vfx(at: Vector3, reach: float) -> void:
	var world: Node = _planet if _planet != null else get_parent()
	EnergyExplosion.burst(world, at, reach, METEOR_TINT, 0.42)
	var dust_owner := _nearest_player()
	if dust_owner != null and dust_owner.get("dust") != null \
			and dust_owner.dust.has_method(&"impact_cloud"):
		dust_owner.dust.impact_cloud(at, _up(), reach, 0.9)


func _apply_meteor_blow(at: Vector3, heading: Vector3, player: Node) -> void:
	var blow := DamageHit.area(at, SLAM_RADIUS, damage(), SLAM_FALLOFF)
	blow.faction = outgoing_faction()
	blow.ability_id = "crawler_rhino_meteor"
	blow.affects_flora = false
	blow.parryable = true
	blow.reaction = DamageHit.Reaction.KNOCKBACK
	blow.world_impulse = heading * ATTACK_KNOCKBACK * 0.35
	blow.radial_impulse = ATTACK_KNOCKBACK
	blow.radial_lift = ATTACK_KNOCKBACK * 0.45
	blow.set_source(self)
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, blow)
	elif player != null and player.has_method(&"apply_damage"):
		if blow.reaches(_combat_position_of(player),
				float(player.call(&"combat_radius")) if player.has_method(
					&"combat_radius") else 0.4):
			player.call(&"apply_damage", blow.resolved_for(player))
	var flatten := DamageHit.area(at, CRATER_RADIUS + FLORA_MARGIN, FLORA_DAMAGE, 0.0)
	flatten.ability_id = "crawler_rhino_meteor"
	flatten.affects_combatants = false
	flatten.plant_break_effects = false
	flatten.set_source(self)
	DamageHit.apply_to_fields(self, flatten)


func _cut_crater(at: Vector3) -> void:
	var planet := _planet
	var world := DamageHit.game_world_of(self)
	if planet == null and world != null and world.has_method(&"planet"):
		planet = world.call(&"planet") as Planet
	if planet == null or not at.is_finite():
		return
	var toward := planet.to_local(at)
	if toward.length_squared() < 0.0001:
		return
	var scar := TerrainScars.Scar.new()
	scar.direction = toward.normalized()
	scar.radius = CRATER_RADIUS
	scar.depth = CRATER_DEPTH
	scar.profile = TerrainScars.Profile.BOWL
	scar.char = 0.35
	scar.tint = Color(0.16, 0.13, 0.11)
	scar.warp = 0.08
	scar.seed = fposmod(at.x * 0.7391 + at.y * 1.4142 + at.z * 2.2360, TAU)
	if world != null and world.has_method(&"request_scar"):
		world.call(&"request_scar", scar)
	else:
		planet.add_scar(scar)


func _charge_from() -> float:
	return CrawlerMobs.number("rhino", threat_level, "charge_from", CHARGE_FROM)


func _charge_speed() -> float:
	var burst := move_speed() * CrawlerMobs.number(
		"rhino", threat_level, "charge_mul", CHARGE_MUL)
	return maxf(burst, _lagged_frame.length() * 1.08 + move_speed() * 0.35)


func _flat_player_velocity(player: Node) -> Vector3:
	var up := _up()
	var motion := _player_velocity(player)
	motion -= up * motion.dot(up)
	return motion if motion.is_finite() else Vector3.ZERO


func _player_running(player: Node) -> bool:
	return CrawlerRules.rhino_running(_flat_player_velocity(player).length())


func _player_ahead(player: Node) -> Vector3:
	var motion := _flat_player_velocity(player)
	if motion.length_squared() > 0.36:
		return motion.normalized()
	if player is Node3D:
		var look := -(player as Node3D).global_transform.basis.z
		look -= _up() * look.dot(_up())
		if look.length_squared() > 0.0001:
			return look.normalized()
	return _flat_forward()


func _player_right(player: Node) -> Vector3:
	var right := _up().cross(_player_ahead(player))
	if right.length_squared() < 0.0001:
		right = _up().cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	return right.normalized()


func _offset_from_player(player: Node) -> Vector3:
	var up := _up()
	var away := global_position - _combat_position_of(player)
	away -= up * away.dot(up)
	return away


func _side_along(player: Node) -> float:
	return _offset_from_player(player).dot(_player_right(player))


func _along_player(player: Node) -> float:
	return _offset_from_player(player).dot(_player_ahead(player))


func _gap(player: Node) -> float:
	return global_position.distance_to(_combat_position_of(player))


func _too_close(player: Node) -> bool:
	return _gap(player) < CrawlerRules.RHINO_BACKUP


func _ensure_flank(player: Node) -> void:
	if _flank_sign != 0:
		return
	var taken := 0
	if is_inside_tree():
		for other_variant: Variant in get_tree().get_nodes_in_group(GROUP):
			var other := other_variant as CrawlerRhino
			if other == null or other == self or other._flank_sign == 0:
				continue
			taken = other._flank_sign
			break
	var side := _side_along(player)
	if absf(side) > 1.2 and (taken == 0 or int(signf(side)) != taken):
		_flank_sign = 1 if side > 0.0 else -1
	elif taken != 0:
		_flank_sign = -taken
	else:
		_flank_sign = 1 if (int(hash(mob_id)) & 1) == 0 else -1


func _lead_ready(player: Node) -> bool:
	var away := _gap(player)
	return _along_player(player) >= LEAD_READY \
		and away >= CHARGE_MINIMUM \
		and away <= _charge_from()


func _line_ready(player: Node) -> bool:
	var away := _gap(player)
	return _along_player(player) >= LINE_READY \
		and absf(_side_along(player)) <= LINE_SIDE \
		and away >= CHARGE_MINIMUM \
		and away <= _charge_from()


func _intercept_at(player: Node) -> Vector3:
	var motion := _lagged_frame
	if motion.length_squared() < 0.25:
		motion = _flat_player_velocity(player)
	return CrawlerRules.ground_intercept(
		global_position, _combat_position_of(player), motion,
		_charge_speed(), _up())


func _intercept_heading(player: Node) -> Vector3:
	var along := _tangent_toward(_intercept_at(player))
	if along.length_squared() < 0.0001:
		along = _tangent_toward(_combat_position_of(player))
	return along.normalized() if along.length_squared() > 0.0001 \
		else _flat_forward()


func _lead_station(player: Node) -> Vector3:
	var at := _combat_position_of(player) + _lagged_frame * 0.16
	return at + _player_ahead(player) * CrawlerRules.RHINO_LEAD \
		+ _player_right(player) * LEAD_HOOK * float(_flank_sign)


func _line_station(player: Node) -> Vector3:
	return _combat_position_of(player) \
		+ _player_ahead(player) * LINE_AHEAD \
		+ _player_right(player) * LINE_HOOK * float(_flank_sign)


func _backup_station(player: Node) -> Vector3:
	var away := _offset_from_player(player)
	if away.length_squared() < 0.25:
		away = -_player_ahead(player)
	else:
		away = away.normalized()
	return _combat_position_of(player) + away * BACKUP_GAP


func _tick_lag(player: Node, delta: float) -> void:
	var live := _flat_player_velocity(player)
	var rate := maxf(live.length(), 8.0) * MATCH_LOCK
	_lagged_frame = _lagged_frame.move_toward(live, rate * delta)


func _ride(player: Node, goal: Vector3, relative: float, delta: float,
		accel: float) -> void:
	_tick_lag(player, delta)
	var along := _tangent_toward(goal)
	var heading := along.normalized() if along.length_squared() > 0.0001 \
		else (_charge_heading if _charge_heading.length_squared() > 0.0001 \
			else _flat_forward())
	var wanted := _lagged_frame * MATCH_SHARE + heading * relative
	_match_speed(wanted.length(), delta, 1.55, 9.0)
	_steer_toward(wanted, delta, accel)
	if _face.length_squared() < 0.0001:
		_face = heading


func _turn_toward(from: Vector3, want: Vector3, step: float) -> Vector3:
	var up := _up()
	var heading := from - up * from.dot(up)
	var target := want - up * want.dot(up)
	if heading.length_squared() < 0.0001:
		heading = target if target.length_squared() > 0.0001 else _flat_forward()
	if target.length_squared() < 0.0001:
		return heading.normalized()
	heading = heading.normalized()
	target = target.normalized()
	var turn := clampf(heading.signed_angle_to(target, up), -step, step)
	if absf(turn) < 0.0001 and heading.dot(target) < 0.86:
		return target
	return heading.rotated(up, turn).normalized()


func _facing(want: Vector3) -> bool:
	if _charge_heading.length_squared() < 0.0001 or want.length_squared() < 0.0001:
		return false
	return _charge_heading.dot(want.normalized()) >= 0.86


func _wander_point() -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(mob_id) * 29 + _patrol_serial * 67) & 0x7fffffff)
	var yaw := rng.randf() * TAU
	var reach := rng.randf_range(18.0, CrawlerRules.PATROL_RADIUS)
	var at := hang_origin + (east * cos(yaw) + north * sin(yaw)) * reach
	var surface := ground_surface(at)
	if surface.is_finite():
		var lift := _up()
		if _planet != null:
			lift = _planet.up_at(surface)
		at = surface + lift * ground_clearance()
	return at


func _tangent_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _flat_forward() -> Vector3:
	var up := _up()
	var ahead := -global_transform.basis.z
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		ahead = up.cross(Vector3.RIGHT)
	if ahead.length_squared() < 0.0001:
		ahead = Vector3.FORWARD
	return ahead.normalized()


func _stick_to_surface() -> void:
	snap_to_ground()


func _face_along(ahead: Vector3, delta: float) -> void:
	var up := _up()
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	var current := global_transform.basis.orthonormalized()
	if current.determinant() < 0.0:
		current.x = -current.x
	var desired := Basis.looking_at(ahead.normalized(), up).orthonormalized()
	if desired.determinant() < 0.0:
		desired.x = -desired.x
	var from := current.get_rotation_quaternion()
	var to := desired.get_rotation_quaternion()
	var rate := 18.0 if _phase == Phase.PAW else 7.0
	global_transform.basis = Basis(from.slerp(to, clampf(delta * rate, 0.0, 1.0))) \
		.orthonormalized()
