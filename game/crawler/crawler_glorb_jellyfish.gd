class_name CrawlerGlorbJellyfish
extends CrawlerRanger

## Ethereal jellyfish Glorb. Swims on its tentacle pulse, then hovers, turns
## red, and pulses faster before each lobbed shot.

const PULSE_RATE_START := 1.8
const PULSE_RATE_PEAK := 3.4


func wild_kind() -> String:
	return CrawlerGlorb.KIND_JELLYFISH


func combat_display_name() -> String:
	return "Glorb Jellyfish"


func hit_radius() -> float:
	return CrawlerGlorb.height(wild_kind()) * 0.55


func hit_height() -> float:
	return CrawlerGlorb.height(wild_kind())


func hit_box() -> float:
	return maxf(hit_height(), hit_radius() * 2.0)


func flyer_floor() -> float:
	return 4.2


func flyer_ceiling() -> float:
	return 12.0


func _ready() -> void:
	super._ready()
	if _animator != null:
		_animator.active = true
		_animator.callback_mode_process = \
			AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_update_clips()


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())
	_loop_living_clips()
	_update_clips()


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_idle(delta)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_ai(delta)


func director_cold_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	if player != null and (chase or hunting()):
		steer = true
		step = maxf(step, delta)
	super.director_cold_tick(delta, step, steer, player, in_city)


func director_warm_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	if player != null and (chase or hunting()):
		steer = true
		step = maxf(step, delta)
	super.director_warm_tick(delta, step, steer, player, in_city)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	if _winding_up():
		var player := _nearest_player()
		if player != null:
			_hold_to_aim(player, global_position, delta)
			_try_fire(player, _flat_gap(player), delta)
		else:
			_brake_hover(delta)
		return
	super._tick_far(delta)


func _tick_hunt_motion(player: Node, delta: float) -> void:
	if _winding_up():
		_hold_to_aim(player, global_position, delta)
		_try_fire(player, _flat_gap(player), delta)
		return
	super._tick_hunt_motion(player, delta)


func _flyer_track(player: Node, delta: float) -> void:
	if _winding_up():
		_hold_to_aim(player, global_position, delta)
		return
	super._flyer_track(player, delta)


func _hold_to_aim(player: Node, _desired: Vector3, delta: float) -> void:
	_faces_motion = false
	_brake_hover(delta)
	if player == null:
		return
	var ahead := _combat_position_of(player) - global_position
	var up := _up()
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	var desired_basis := Basis.looking_at(ahead.normalized(), up).orthonormalized()
	if desired_basis.determinant() < 0.0:
		desired_basis.x = -desired_basis.x
	var current := global_transform.basis.orthonormalized()
	if current.determinant() < 0.0:
		current.x = -current.x
	global_transform.basis = Basis(
		current.get_rotation_quaternion().slerp(
			desired_basis.get_rotation_quaternion(),
			clampf(delta * 8.0, 0.0, 1.0))).orthonormalized()


func _brake_hover(delta: float) -> void:
	var rate := maxf(42.0, velocity.length() * 5.0)
	velocity = velocity.move_toward(Vector3.ZERO, rate * maxf(delta, 0.0))


func _winding_up() -> bool:
	return _aiming() or _pending_shot


func _windup_seconds() -> float:
	return maxf(CrawlerMobs.number(
		wild_kind(), threat_level, "aim_seconds", CrawlerRules.RANGER_AIM_SECONDS), 0.05)


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_ATTACK or clip == CLIP_CAST or clip == CLIP_FLY \
			or clip == CLIP_WALK or clip == CLIP_RUN or clip == CLIP_IDLE:
		return PackedStringArray(["Tentacle_Pulse", "Run", CLIP_RUN, clip])
	return super._clip_aliases(clip)


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _winding_up() or _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	return CLIP_FLY


func _glorb_travel_clip(clip: String) -> String:
	if clip == CLIP_HIT:
		return clip
	if _winding_up() or _attack_left > 0.0:
		return CLIP_ATTACK
	return CLIP_FLY


func _update_clips() -> void:
	super._update_clips()
	if _animator == null:
		return
	_loop_living_clips()
	var pulse := _resolve_clip(CLIP_FLY)
	if _alive and _flash_left <= 0.04 and not pulse.is_empty() \
			and _animator.current_animation != pulse:
		_current_clip = pulse
		_animator.play(pulse, CLIP_BLEND)
	if _winding_up():
		var warn := 1.0 - _aim_left / _windup_seconds()
		_animator.speed_scale = lerpf(
			PULSE_RATE_START, PULSE_RATE_PEAK, clampf(warn, 0.0, 1.0))
		return
	if not is_equal_approx(_animator.speed_scale, 1.15):
		_animator.speed_scale = 1.15


func _loop_living_clips() -> void:
	if _animator == null:
		return
	for clip: String in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_FLY, CLIP_ATTACK]:
		var resolved := _resolve_clip(clip)
		if resolved.is_empty() or not _animator.has_animation(resolved):
			continue
		_animator.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR


func _update_flash() -> void:
	var warn := 0.0
	if _winding_up():
		warn = 1.0 - _aim_left / _windup_seconds()
	var flash := 0.92 if _flash_left > 0.0 else clampf(warn, 0.0, 1.0)
	for material in _materials:
		if material != null:
			material.set_shader_parameter(&"flash", flash)


func _paint_mood(_warn: float) -> void:
	pass
