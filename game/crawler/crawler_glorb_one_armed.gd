class_name CrawlerGlorbOneArmed
extends CrawlerGray

## Ethereal one-armed Glorb. Shoots from agro range, then kites to a
## 30 m gap at 8 m/s if the player closes.

const KEEP_RANGE := 30.0
const BACK_SPEED := 8.0
const BACK_LAG := 0.55
const BACK_FLOOR := 3.2


func wild_kind() -> String:
	return CrawlerGlorb.KIND_ONE_ARMED


func combat_display_name() -> String:
	return "Glorb One-Armed"


func body_height() -> float:
	return CrawlerGlorb.height(wild_kind())


func body_width() -> float:
	return CrawlerGlorb.height(wild_kind()) * 0.36


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_idle(delta)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_far(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _maybe_glorb_inbound(maxf(delta, 0.0)):
		return
	super.director_far_steer(delta, player, in_city)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	_fire_left = maxf(_fire_left - delta, 0.0)
	snap_to_ground()
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_kite(player, delta)
	_try_fire(player, delta)
	if _aiming():
		_act = CLIP_AIM
		_face_prey(player)


func _tick_hunt_motion(player: Node, delta: float) -> void:
	if player == null:
		return
	_kite(player, delta)


func _kite(player: Node, delta: float) -> void:
	_faces_motion = false
	_face_prey(player)
	var along := _flat_toward(_combat_position_of(player))
	var gap := along.length()
	if gap >= KEEP_RANGE or along.length_squared() < 0.0001:
		_match_speed(0.0, delta, 3.0, 22.0)
		velocity = velocity.move_toward(Vector3.ZERO, 18.0 * delta)
		return
	_match_speed(BACK_SPEED, delta, BACK_LAG, BACK_FLOOR)
	_steer_toward(-along.normalized() * _cruise, delta, 11.0)


func _hold_aim(player: Node, delta: float) -> void:
	if _flat_gap(player) < KEEP_RANGE:
		_faces_motion = false
		_act = CLIP_AIM
		_face_prey(player)
		return
	super._hold_aim(player, delta)


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_AIM or clip == CLIP_CAST or clip == CLIP_ATTACK:
		return PackedStringArray(["Cast", clip])
	return super._clip_aliases(clip)
