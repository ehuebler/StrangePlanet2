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
	return global_position + _up() * (HEIGHT * 0.12)


func combat_radius() -> float:
	return WIDTH * 0.58


func flies() -> bool:
	return true


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


func _tick_idle(delta: float) -> void:
	_abort_aim()
	_patrol(delta, 0.52)


func _tick_ai(delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		_draw_beam(0.0)
		return
	var at := _combat_position_of(player)
	var hold := lerpf(
		CrawlerMobs.number(wild_kind(), threat_level, "standoff_min",
			CrawlerRules.VESPER_STANDOFF_MIN),
		CrawlerMobs.number(wild_kind(), threat_level, "standoff_max",
			CrawlerRules.VESPER_STANDOFF_MAX),
		_hold_share()
	)
	var desired := _hover_hold(at, hold)
	if aiming():
		_hold_aim(player, desired, delta)
	else:
		_close_or_drift(player, desired, hold, delta)
		_try_charge(player)
	_draw_beam(_charge_share())


func _hold_share() -> float:
	return 0.5 + 0.5 * sin(float(hash(mob_id) % 97) * 0.11)


func _hover_hold(at: Vector3, hold: float) -> Vector3:
	var up := _up()
	var bias := _orbit_bias()
	bias -= up * bias.dot(up)
	if bias.length_squared() < 0.0001:
		bias = up.cross(Vector3.FORWARD)
	bias = bias.normalized()
	return _clamp_flyer_band(at + bias * hold + up * 3.2)


func _close_or_drift(player: Node, desired: Vector3, hold: float, delta: float) -> void:
	var player_speed := _player_speed(player)
	var gap := global_position.distance_to(desired)
	var matched := absf(_cruise - player_speed) <= maxf(player_speed * 0.18, 4.0) \
		and gap <= hold * 1.25
	if matched:
		_match_speed(player_speed, delta, 2.2, 28.0)
		var bob := _up() * sin(Time.get_ticks_msec() * 0.004 + float(hash(mob_id))) * 1.4
		var along := desired + bob - global_position
		var ride := along.normalized() * _cruise if along.length_squared() > 0.2 \
			else _player_velocity(player)
		_steer_toward(ride, delta, 12.0)
	else:
		_match_speed(maxf(player_speed, move_speed()), delta, 1.8, 24.0)
		var along := desired - global_position
		if along.length_squared() > 0.0001:
			_steer_toward(along.normalized() * _cruise, delta, 13.0)


func _try_charge(player: Node) -> void:
	if _fire_left > 0.0 or aiming():
		return
	var gap := _flat_gap(player)
	var near := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_min", CrawlerRules.VESPER_ENGAGE_MIN)
	var far := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_max", CrawlerRules.VESPER_ENGAGE_MAX)
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
	_match_speed(0.0, delta, 4.0, 40.0)
	velocity = velocity.move_toward(Vector3.ZERO, 28.0 * delta)
	var look := _locked - global_position
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
	var from := combat_position()
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


func _flat_gap(player: Node) -> float:
	var up := _up()
	var along := _combat_position_of(player) - global_position
	along -= up * along.dot(up)
	return along.length()


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
	_line.place_beam(combat_position(), _locked, thick)
