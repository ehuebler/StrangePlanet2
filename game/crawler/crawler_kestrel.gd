class_name CrawlerKestrel
extends CrawlerRobot

## Flying office gunner. Spawns ahead and rides the player's frame like a
## ranger, then gatling-fires minigun bolts instead of a lobbed orb.

const HEIGHT := 2.48
const WIDTH := 0.95
const BURST := 8
const BURST_GAP := 0.09
const BURST_WIND := 0.58


func _ready() -> void:
	_base_health = 6.0
	_base_damage = 2.0
	_base_speed = 42.0
	super._ready()


func wild_kind() -> String:
	return "kestrel"


func body_height() -> float:
	return HEIGHT * BODY_SCALE


func body_width() -> float:
	return WIDTH * BODY_SCALE


func flies() -> bool:
	return true


func flyer_floor() -> float:
	return body_height() * 0.55 + 3.4


func flyer_ceiling() -> float:
	return maxf(super.flyer_ceiling(), flyer_floor() + 8.0)


func _wander_point() -> Vector3:
	var at := super._wander_point()
	return _clamp_flyer_band(at)


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


func _track_hold_min() -> float:
	return CrawlerMobs.number(wild_kind(), threat_level, "standoff_min", 24.0)


func _track_hold_max() -> float:
	return CrawlerMobs.number(wild_kind(), threat_level, "standoff_max", 42.0)


func _tick_idle(delta: float) -> void:
	_act = ""
	_patrol(delta, 0.58)


func _tick_ai(delta: float) -> void:
	var player := _hunt_target(delta)
	if player == null:
		_fire_left = maxf(_fire_left - delta, 0.0)
		_tick_idle(delta)
		return
	_fight(player, delta)


func _tick_far(delta: float) -> void:
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_fight(player, delta)
		return
	_fire_left = maxf(_fire_left - delta, 0.0)
	_tick_idle(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _movement_locked():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	if player != null and _apply_agro(player, step, in_city):
		_fight(player, step)
	else:
		_fire_left = maxf(_fire_left - step, 0.0)
		_tick_idle(step)
	if flies():
		_director_climb()


func _fight(player: Node, delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	_tick_hunt_motion(player, delta)
	_try_burst(player, _combat_position_of(player), _flat_gap(player))


func _try_burst(player: Node, at: Vector3, hold: float) -> void:
	if _fire_left > 0.0:
		return
	var gap := _flat_gap(player) if player != null else hold
	var near := CrawlerHunt.shot_min(wild_kind(), threat_level)
	var far := CrawlerHunt.shot_max(wild_kind(), threat_level)
	if gap < near or gap > far:
		return
	if not _begin_attack(BURST_WIND + float(BURST) * BURST_GAP):
		return
	_act = CLIP_FIRE
	_fire_left = maxf(fire_scale(), 1.5)
	var heading := _burst_heading(player, at)
	for shot in BURST:
		_spawn_laser(
			heading, BURST_WIND + float(shot) * BURST_GAP,
			EnergyVfx.TINT_DARK_RED, EnergyVfx.TINT_DARK_RED.lightened(0.28),
			"crawler_kestrel_laser", player)


func _burst_heading(player: Node, at: Vector3) -> Vector3:
	var target := at
	var shot_speed := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_speed", 52.0)
	if player != null and shot_speed > 0.01:
		var eta := muzzle_point().distance_to(at) / shot_speed
		target = at + _player_velocity(player) * eta
	var heading := target - muzzle_point()
	if heading.length_squared() < 0.0001:
		heading = at - muzzle_point()
	return heading
