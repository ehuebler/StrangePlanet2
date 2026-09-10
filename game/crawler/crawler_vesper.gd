class_name CrawlerVesper
extends CrawlerMob

## Four-winged medium demon. Patrols in the air and locks a telegraph beam
## before it fires. It stays off the ground; the same beam is used if it lands.

const BODY := preload("res://game/crawler/crawler_demon_body.gd")
const PAINT_PATH := "res://assets/runtime/biomes/paint/vesper_paint.png"
const HEIGHT := 4.6
const WIDTH := 1.7
const INK := Color(0.16, 0.06, 0.20)


var _aim_left := 0.0
var _fire_left := 0.0
var _locked := Vector3.INF
var _line: EnergyVfx
var _muzzle: Node3D


func _ready() -> void:
	_base_health = 6.0
	_base_damage = 10.0
	_base_speed = 38.0
	_faces_motion = true
	_uses_model_front = true
	super._ready()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, WIDTH * 0.8)
	shape.shape = box
	add_child(shape)
	var packed := CrawlerDemonModels.scene(wild_kind())
	if packed != null:
		_attach_skinned(packed, HEIGHT)
	else:
		BODY.build(self, 4, HEIGHT, INK, BODY.load_paint(PAINT_PATH))
	_line = EnergyVfx.make(EnergyVfx.Kind.BEAM_STREAMS, EnergyVfx.TINT_PURPLE)
	_line.name = "VesperBeam"
	_line.visible = false
	_line.top_level = true
	add_child(_line)


func wild_kind() -> String:
	return "vesper"


func combat_display_name() -> String:
	return "Vesper"


func combat_position() -> Vector3:
	if _hit_ready:
		return super.combat_position()
	return global_position + _up() * (HEIGHT * 0.12)


func combat_radius() -> float:
	if _hit_ready:
		return super.combat_radius()
	return WIDTH * 0.58


func flies() -> bool:
	return true


func muzzle_point() -> Vector3:
	if _muzzle is Node3D:
		return _muzzle.global_position
	return combat_position()


func flyer_floor() -> float:
	return HEIGHT * 0.55 + 4.0


func aiming() -> bool:
	return _aim_left > 0.0


func locked_aim() -> Vector3:
	return _locked


func charge_share() -> float:
	return _charge_share()


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _aim_left > 0.0:
		return BODY.CLIP_CAST
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	return BODY.CLIP_FLY


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
	return CrawlerMobs.number(
		wild_kind(), threat_level, "standoff_min", CrawlerRules.VESPER_STANDOFF_MIN)


func _track_hold_max() -> float:
	return CrawlerMobs.number(
		wild_kind(), threat_level, "standoff_max", CrawlerRules.VESPER_STANDOFF_MAX)


func _tick_idle(delta: float) -> void:
	_abort_aim()
	_patrol(delta, 0.52)


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
	var hold := lerpf(_track_hold_min(), _track_hold_max(), _hold_share())
	var desired := _hover_hold(_combat_position_of(player), hold)
	if aiming():
		_hold_aim(player, desired, delta)
	else:
		_flyer_track(player, delta)
		_try_charge(player)
	_draw_beam(_charge_share())


func _try_charge(player: Node) -> void:
	if _fire_left > 0.0 or aiming():
		return
	var gap := _flat_gap(player)
	var near := CrawlerHunt.shot_min(wild_kind(), threat_level)
	var far := CrawlerHunt.shot_max(wild_kind(), threat_level)
	if gap < near or gap > far:
		return
	var aim := CrawlerMobs.number(
		wild_kind(), threat_level, "aim_seconds", CrawlerRules.VESPER_CHARGE)
	if not _begin_attack(aim):
		return
	_locked = _combat_position_of(player)
	_aim_left = aim


func _hold_aim(player: Node, desired: Vector3, delta: float) -> void:
	_aim_left = maxf(_aim_left - delta, 0.0)
	_faces_motion = false
	var frame := _player_velocity(player)
	var lag := CrawlerRules.GLORB_FLYER_HOLD_LAG \
		if CrawlerRules.is_glorb_soft_flyer(wild_kind()) else 1.4
	var floor_rate := CrawlerRules.GLORB_FLYER_HOLD_FLOOR \
		if CrawlerRules.is_glorb_soft_flyer(wild_kind()) else 8.0
	var lock := CrawlerRules.GLORB_FLYER_HOLD_LOCK \
		if CrawlerRules.is_glorb_soft_flyer(wild_kind()) else 4.2
	_match_speed(frame.length(), delta, lag, floor_rate)
	var spring := (desired - global_position) * 1.35
	velocity = velocity.lerp(
		frame + spring, clampf(lock * delta, 0.0, 1.0))
	var look := _locked - global_position
	if not look.is_finite():
		look = _combat_position_of(player) - global_position
	if look.length_squared() > 0.0001:
		var up := _up()
		look -= up * look.dot(up)
		if look.length_squared() > 0.0001:
			global_transform.basis = _look_basis(look, up)
	if _aim_left <= 0.0:
		_release(player)
		_faces_motion = true


func _release(player: Node) -> void:
	_fire_left = CrawlerMobs.number(
		wild_kind(), threat_level, "fire", CrawlerRules.VESPER_FIRE)
	_begin_attack(0.28)
	if not _locked.is_finite():
		_abort_aim()
		return
	var from := muzzle_point()
	var hit := DamageHit.beam(
		from, _locked, CrawlerRules.VESPER_BEAM_RADIUS, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_vesper_beam"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		player.call(&"apply_damage", hit)
	_abort_aim()


func _abort_aim() -> void:
	_aim_left = 0.0
	_locked = Vector3.INF
	_draw_beam(0.0)


func _charge_share() -> float:
	var wait := CrawlerMobs.number(
		wild_kind(), threat_level, "aim_seconds", CrawlerRules.VESPER_CHARGE)
	if wait <= 0.001 or not aiming():
		return 0.0
	return 1.0 - clampf(_aim_left / wait, 0.0, 1.0)


func _draw_beam(share: float) -> void:
	if _line == null:
		return
	if share <= 0.02 or not _locked.is_finite():
		_line.visible = false
		return
	var thick := lerpf(0.05, 0.22, share)
	if share > 0.92:
		thick = 0.28
	_line.set_tint(EnergyVfx.TINT_PURPLE)
	_line.place_beam(muzzle_point(), _locked, thick)
