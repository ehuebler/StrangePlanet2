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


func _tick_idle(delta: float) -> void:
	_act = ""
	_patrol(delta, 0.58)


func _tick_ai(delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_flyer_track(player, delta)
	_try_burst(player, _combat_position_of(player), _flat_gap(player))


func _try_burst(player: Node, at: Vector3, hold: float) -> void:
	if _fire_left > 0.0:
		return
	var gap := _flat_gap(player) if player != null else hold
	var near := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_min", CrawlerRules.RANGER_ENGAGE_MIN)
	var far := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_max", CrawlerRules.RANGER_ENGAGE_MAX)
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
			"crawler_kestrel_laser")


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
