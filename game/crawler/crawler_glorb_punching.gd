class_name CrawlerGlorbPunching
extends CrawlerTanglemaw

## Ethereal punching Glorb. Runs on the ground, always faces its prey,
## then plants, turns red, and punches.

const PURSUE_SPEED := 15.0
const PUNCH_WINDUP := 0.55
const PUNCH_REACH := 2.1

var _windup_left := 0.0
var _pending_punch := false


func _ready() -> void:
	super._ready()
	_uses_model_front = true
	_faces_motion = false
	_base_speed = PURSUE_SPEED
	if _animator != null:
		_animator.active = true
		_animator.callback_mode_process = \
			AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


func wild_kind() -> String:
	return CrawlerGlorb.KIND_PUNCHING


func combat_display_name() -> String:
	return "Glorb Punching"


func body_height() -> float:
	return CrawlerGlorb.height(wild_kind())


func body_width() -> float:
	return CrawlerGlorb.height(wild_kind()) * 0.48


func flies() -> bool:
	return false


func move_speed() -> float:
	return minf(super.move_speed(), PURSUE_SPEED)


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())
	var punch := _resolve_clip(CLIP_ATTACK)
	if _animator != null and not punch.is_empty() and _animator.has_animation(punch):
		_animator.get_animation(punch).loop_mode = Animation.LOOP_NONE


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	_abort_punch()
	super._tick_idle(delta)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_chase(player, delta, true)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	_bite_left = maxf(_bite_left - delta, 0.0)
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_chase(player, delta, false)
		return
	_tick_idle(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _maybe_glorb_inbound(maxf(delta, 0.0)):
		return
	if _movement_locked():
		velocity = Vector3.ZERO
		if chase or _winding_up() or _attack_left > 0.0:
			_face_player(delta, player)
		return
	var step := maxf(delta, 0.0)
	_bite_left = maxf(_bite_left - step, 0.0)
	if player != null and tick_agro(player, step):
		_chase(player, step, false)
	else:
		_tick_idle(step)
	if chase or _winding_up() or _attack_left > 0.0:
		_face_player(step, player)


func director_warm_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	super.director_warm_tick(delta, step, steer, player, in_city)
	if chase or _winding_up() or _attack_left > 0.0:
		_face_player(delta, player)


func director_cold_tick(delta: float, step: float, steer: bool, player: Node3D,
		in_city := false) -> void:
	super.director_cold_tick(delta, step, steer, player, in_city)
	if chase or _winding_up() or _attack_left > 0.0:
		_face_player(delta, player)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if chase or _winding_up() or _attack_left > 0.0:
		_face_player(delta)


func _process(delta: float) -> void:
	super._process(delta)
	if chase or _winding_up() or _attack_left > 0.0:
		_face_player(delta)


func _tick_hunt_motion(player: Node, delta: float) -> void:
	if _winding_up():
		_service_punch(player, delta)
		return
	_face_player(delta, player)
	_run_at(player, delta)


func _hunt_set_air(_on: bool) -> void:
	if _hunt_airborne:
		_hunt_airborne = false
		snap_to_ground()
		velocity -= _up() * velocity.dot(_up())


func _chase(player: Node, delta: float, think: bool) -> void:
	_face_player(delta, player)
	if _winding_up():
		_service_punch(player, delta)
		return
	_run_at(player, delta)
	if think:
		snap_to_ground()
	var at := _combat_position_of(player)
	var gap := global_position.distance_to(at)
	var reach := PUNCH_REACH + _reach_of(player)
	if gap <= reach and _bite_left <= 0.0:
		_begin_punch()


func _run_at(player: Node, delta: float) -> void:
	_hunt_airborne = false
	_faces_motion = false
	var along := _flat_toward(_combat_position_of(player))
	_match_speed(PURSUE_SPEED, delta, 1.6, 22.0)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 14.0)
	var up := _up()
	velocity -= up * velocity.dot(up)
	if _director_lod == CrawlerRules.MOB_LOD_HOT:
		snap_to_ground()


func _begin_punch() -> void:
	if _winding_up():
		return
	if not _begin_attack(PUNCH_WINDUP):
		return
	_pending_punch = true
	_windup_left = PUNCH_WINDUP
	_act = CLIP_ATTACK
	_faces_motion = false
	velocity = Vector3.ZERO
	_face_player(1.0)
	_update_clips()


func _service_punch(player: Node, delta: float) -> void:
	_windup_left = maxf(_windup_left - maxf(delta, 0.0), 0.0)
	_brake_stand(delta)
	_face_player(maxf(delta, 0.0), player)
	if _windup_left > 0.0:
		return
	if _pending_punch:
		_land_punch(player)


func _land_punch(player: Node) -> void:
	_pending_punch = false
	_act = ""
	_bite_left = maxf(CrawlerMobs.number(
		wild_kind(), threat_level, "fire", CrawlerRules.TANGLEMAW_BITE), 0.35)
	var reach := PUNCH_REACH + _reach_of(player) + 0.35
	if player == null:
		return
	if global_position.distance_to(_combat_position_of(player)) > reach:
		return
	var hit := DamageHit.impact(combat_position(), reach, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_glorb_punch"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
	if not is_charmed() and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player.has_method(&"apply_damage"):
		player.call(&"apply_damage", hit)


func _abort_punch() -> void:
	_pending_punch = false
	_windup_left = 0.0
	_act = ""


func _winding_up() -> bool:
	return _pending_punch or _windup_left > 0.0


func _brake_stand(delta: float) -> void:
	var rate := maxf(48.0, velocity.length() * 6.0)
	velocity = velocity.move_toward(Vector3.ZERO, rate * maxf(delta, 0.0))


func _face_combat_player(delta: float) -> void:
	_face_player(delta)


func _face_player(delta: float, player: Node = null) -> void:
	if player == null:
		player = _nearest_player()
	if player == null:
		return
	var look := _chase_along(player)
	if look.length_squared() < 0.0001:
		return
	var up := _up()
	var desired := _look_basis(look.normalized(), up)
	if desired.determinant() < 0.0:
		desired.x = -desired.x
	if absf(desired.determinant()) < 0.01:
		return
	# Feet stay planted for the windup. Yaw still tracks the player so the
	# punch meets the face they are looking at.
	if _winding_up() or _attack_left > 0.0 or delta >= 0.16:
		global_transform.basis = desired
		return
	var current := global_transform.basis.orthonormalized()
	if current.determinant() < 0.0:
		current.x = -current.x
	if absf(current.determinant()) < 0.01:
		global_transform.basis = desired
		return
	global_transform.basis = Basis(
		current.get_rotation_quaternion().slerp(
			desired.get_rotation_quaternion(),
			clampf(maxf(delta, 0.0) * 14.0, 0.0, 1.0))).orthonormalized()


func _chase_along(player: Node) -> Vector3:
	var along := _flat_toward(_combat_position_of(player))
	if along.length_squared() > 0.04:
		return along
	along = _combat_position_of(player) - global_position
	along -= _up() * along.dot(_up())
	if along.length_squared() > 0.04:
		return along
	along = _combat_position_of(player) - global_position
	along.y = 0.0
	return along


func _face_prey() -> void:
	_face_player(0.16)


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_BITE or clip == CLIP_ATTACK or clip == CLIP_CAST:
		return PackedStringArray(["Punch", clip])
	if clip == CLIP_FLY or clip == CLIP_WALK:
		return PackedStringArray(["Run", CLIP_RUN, clip])
	return super._clip_aliases(clip)


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _winding_up() or _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	if chase or velocity.length() > 0.55 or glorb_inbound():
		return CLIP_RUN
	return CLIP_IDLE


func _glorb_travel_clip(clip: String) -> String:
	if clip == CLIP_HIT:
		return clip
	if _winding_up() or _attack_left > 0.0:
		return CLIP_ATTACK
	if chase or velocity.length() > 0.55 or glorb_inbound():
		return CLIP_RUN
	return CLIP_IDLE


func _update_clips() -> void:
	super._update_clips()
	if _animator == null or not _winding_up():
		return
	var punch := _resolve_clip(CLIP_ATTACK)
	if punch.is_empty() or not _animator.has_animation(punch):
		return
	if _animator.current_animation != punch or not _animator.is_playing():
		_current_clip = punch
		_animator.play(punch, CLIP_BLEND)
	var length := _animator.get_animation(punch).length
	if length > 0.2:
		_animator.speed_scale = length / PUNCH_WINDUP


func _update_flash() -> void:
	var warn := 0.0
	if _winding_up():
		warn = 1.0 - _windup_left / maxf(PUNCH_WINDUP, 0.05)
	var flash := 0.92 if _flash_left > 0.0 else clampf(warn, 0.0, 1.0)
	for material in _materials:
		if material != null:
			material.set_shader_parameter(&"flash", flash)
