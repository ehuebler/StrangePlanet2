class_name CrawlerGlorbEyeball
extends CrawlerRammer

## Ethereal eyeball Glorb. Circles 20–50 m up while calm. Once agroed it
## flutters on Run in front of the camera, then rams the face at a walk.

const IDLE_FLOOR := 20.0
const IDLE_CEILING := 50.0
const FLUTTER_AHEAD := 30.0
const FLUTTER_LIFT := 3.2
const FLUTTER_READY := 6.5
const RAM_SPEED := 6.5
const RAM_SPEED_MIN := 5.0
const RAM_SPEED_MAX := 8.0
const FLUTTER_SWAY := 2.6
const FLUTTER_HZ := 1.15
const FLUTTER_ROLL := 0.28

var _flutter := 0.0


func wild_kind() -> String:
	return CrawlerGlorb.KIND_EYEBALL


func combat_display_name() -> String:
	return "Glorb Eyeball"


func flyer_floor() -> float:
	if _phase == Phase.RAM:
		return 0.48
	if chase:
		return 2.4
	return IDLE_FLOOR


func flyer_ceiling() -> float:
	if _phase == Phase.RAM:
		return 16.0
	if chase:
		return IDLE_CEILING
	return IDLE_CEILING


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())


func _ready_soar() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int((hash(mob_id) * 53 + 11) & 0x7fffffff)
	_soar_angle = rng.randf() * TAU
	_soar_radius = rng.randf_range(SOAR_RADIUS * 0.7, SOAR_RADIUS * 1.35)
	_soar_loft = rng.randf_range(IDLE_FLOOR, IDLE_CEILING)
	_soar_sign = -1.0 if rng.randf() < 0.5 else 1.0


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		_hold_idle_loft(delta)
		return
	_phase = Phase.SOAR
	_ram_heading = Vector3.ZERO
	_glide_loft = -1.0
	_soar_circle(delta)
	_hold_idle_loft(delta)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		_hold_idle_loft(delta)
		return
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	if _try_detonate(player):
		return
	if _phase == Phase.RAM:
		_update_ram(player, delta)
		return
	_phase = Phase.STAGE
	_update_stage(player, delta)
	if _ready_to_ram(player):
		_begin_ram(player)
		_update_ram(player, delta)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		_hold_idle_loft(delta)
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_tick_ai(delta)
		return
	_tick_idle(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	if _maybe_glorb_inbound(step):
		_hold_idle_loft(step)
		return
	if player != null and _apply_agro(player, step, in_city):
		if _try_detonate(player):
			return
		_tick_ai(step)
	else:
		_tick_idle(step)
	if flies():
		_director_climb()


func _director_climb() -> void:
	_hold_idle_loft(0.16)


func _hold_idle_loft(_delta: float) -> void:
	var up := _up()
	var altitude := _altitude()
	var floor_h := flyer_floor()
	var ceiling := flyer_ceiling()
	if not chase and _soar_loft >= IDLE_FLOOR:
		floor_h = maxf(floor_h, _soar_loft - 4.0)
		ceiling = minf(ceiling, _soar_loft + 4.0)
	if altitude < floor_h:
		var down := -velocity.dot(up)
		if down > 0.0:
			velocity += up * down
		velocity += up * maxf((floor_h - altitude) * 6.0, 10.0)
		return
	if altitude > ceiling:
		var rise := velocity.dot(up)
		if rise > 0.0:
			velocity -= up * rise
		velocity -= up * clampf((altitude - ceiling) * 4.0, 6.0, 28.0)


func _stage_top_speed(player: Node) -> float:
	return maxf(_player_speed(player), 2.4)


func _ram_top_speed(_player: Node) -> float:
	return clampf(RAM_SPEED, RAM_SPEED_MIN, RAM_SPEED_MAX)


func show_station(player: Node) -> Vector3:
	var origin := _view_origin(player)
	var look := _player_view(player)
	var lift := _view_up(player)
	if look.length_squared() < 0.0001:
		look = Vector3.FORWARD
	look = look.normalized()
	if lift.length_squared() < 0.0001:
		lift = _up()
	lift = lift.normalized()
	return origin + look * FLUTTER_AHEAD + lift * FLUTTER_LIFT


func stage_goal(player: Node) -> Vector3:
	var goal := super.stage_goal(player)
	var lift := _view_up(player)
	var look := _player_view(player)
	var right := look.cross(lift)
	if right.length_squared() < 0.0001:
		return goal
	return goal + right.normalized() * sin(_flutter * TAU * FLUTTER_HZ) * FLUTTER_SWAY


func _update_stage(player: Node, delta: float) -> void:
	_flutter += maxf(delta, 0.0)
	super._update_stage(player, delta)


func _ready_to_ram(player: Node) -> bool:
	if player == null or not in_camera(player):
		return false
	if _height_above_station(player) > DESCENT_READY:
		return false
	if global_position.distance_to(_combat_position_of(player)) <= CLOSE_RAM:
		return true
	return global_position.distance_to(show_station(player)) <= FLUTTER_READY


func _face_motion(delta: float) -> void:
	if staging():
		var player := _nearest_player()
		if player != null:
			var up := _up()
			var ahead := _combat_position_of(player) - global_position
			ahead -= up * ahead.dot(up)
			if ahead.length_squared() > 0.0001:
				var desired := _look_basis(ahead.normalized(), up)
				var current := global_transform.basis.orthonormalized()
				global_transform.basis = Basis(
					current.get_rotation_quaternion().slerp(
						desired.get_rotation_quaternion(),
						clampf(delta * 7.0, 0.0, 1.0))).orthonormalized()
				var roll := sin(_flutter * TAU * FLUTTER_HZ) * FLUTTER_ROLL
				global_transform.basis = global_transform.basis.rotated(
					global_transform.basis.z, roll)
				return
	super._face_motion(delta)


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_ATTACK:
		return PackedStringArray(["Pulse", CLIP_RUN, clip])
	if clip == CLIP_FLY or clip == CLIP_WALK or clip == CLIP_IDLE:
		return PackedStringArray(["Run", CLIP_RUN, clip])
	return super._clip_aliases(clip)


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	if chase or staging() or ramming() or velocity.length() > 0.4 \
			or glorb_inbound():
		return CLIP_RUN
	return CLIP_IDLE


func _glorb_travel_clip(clip: String) -> String:
	if clip == CLIP_HIT or clip == CLIP_ATTACK:
		return clip
	if chase or staging() or ramming() or velocity.length() > 0.4 \
			or glorb_inbound():
		return CLIP_RUN
	return CLIP_IDLE
