class_name CrawlerScout
extends CrawlerAlien

## Flying saucer. Banks while it tracks, holds a green sight, then freezes
## that aim and fires short pink pulse beams. Both the sight and the shot
## leave the cannon along its barrel; they do not bend toward the target.

const CANNON_LOCAL := Vector3(0.0, 0.505, 1.708)
const HEIGHT := 2.15
const WIDTH := 1.55
const PULSE_COUNT := 3
const PULSE_GAP := 0.09
const PULSE_RADIUS := 0.42
const POINTER_RADIUS := 0.034
const POINTER_OPACITY := 0.4
const BANK_ROLL := 0.085
const BANK_PITCH := 0.042


var _aim_left := 0.0
var _aim_point := Vector3.INF
var _aim_frozen := false
var _pending_burst := false
var _pulse_left := 0
var _pulse_wait := 0.0
var _pointer: EnergyVfx
var _bank := Vector2.ZERO


func _ready() -> void:
	_base_health = 6.0
	_base_damage = 5.0
	_base_speed = 42.0
	super._ready()
	_bind_cannon()
	_pointer = EnergyVfx.make(EnergyVfx.Kind.BEAM_STREAMS, EnergyVfx.TINT_GREEN)
	_pointer.name = "ScoutPointer"
	_pointer.top_level = true
	add_child(_pointer)
	_pointer.set_opacity(POINTER_OPACITY)
	_pointer.visible = false


func wild_kind() -> String:
	return "scout"


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


func aiming() -> bool:
	return _aim_left > 0.0 or _aim_frozen


func pointer_on() -> bool:
	return _pointer != null and _pointer.visible


func frozen_aim() -> bool:
	return _aim_frozen


func _wander_point() -> Vector3:
	return _clamp_flyer_band(super._wander_point())


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_service_pulses(delta)
	_place_pointer()
	_bank_visual(delta)


func set_director_lod(lod: int) -> void:
	super.set_director_lod(lod)
	if _pulse_left > 0 or _aim_frozen:
		set_physics_process(true)


func _tick_idle(delta: float) -> void:
	_abort_aim()
	_patrol(delta, 0.58)


func _tick_ai(delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	if _aiming():
		_hold_frozen(player, delta)
	else:
		_aim_point = _combat_position_of(player)
		_tick_hunt_motion(player, delta)
	_try_lock(player, _flat_gap(player), delta)


func _aiming() -> bool:
	return _aim_left > 0.0 or _pending_burst or _pulse_left > 0


func _abort_aim() -> void:
	_aim_left = 0.0
	_aim_frozen = false
	_pending_burst = false
	_pulse_left = 0
	_pulse_wait = 0.0
	_act = ""
	_faces_motion = true
	if _pointer != null:
		_pointer.visible = false


func _hold_frozen(player: Node, delta: float) -> void:
	_faces_motion = false
	var desired := _hover_hold(
		_combat_position_of(player),
		lerpf(_track_hold_min(), _track_hold_max(), _hold_share()))
	var frame := _player_velocity(player)
	_match_speed(frame.length(), delta, 1.4, 8.0)
	var spring := (desired - global_position) * 1.2
	velocity = velocity.lerp(frame + spring, clampf(3.6 * delta, 0.0, 1.0))
	var ahead := _aim_point - muzzle_point()
	if ahead.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(ahead.normalized(), _up())


func _try_lock(player: Node, distance: float, delta: float) -> void:
	if _aiming():
		_aim_left = maxf(_aim_left - delta, 0.0)
		if _aim_left > 0.0:
			return
		if _pending_burst:
			_start_pulses(player)
		return
	_faces_motion = true
	if _fire_left > 0.0 or _pulse_left > 0:
		return
	var near := CrawlerHunt.shot_min(wild_kind(), threat_level)
	var far := CrawlerHunt.shot_max(wild_kind(), threat_level)
	if distance < near or distance > far:
		return
	var aim := CrawlerMobs.number(
		wild_kind(), threat_level, "aim_seconds", CrawlerRules.SCOUT_AIM)
	if not _begin_attack(aim + float(PULSE_COUNT) * PULSE_GAP + 0.15):
		return
	_aim_frozen = true
	_pending_burst = true
	_aim_left = aim
	_aim_point = _combat_position_of(player)
	_bank = Vector2.ZERO
	_act = CLIP_ATTACK
	set_physics_process(true)


func _start_pulses(player: Node) -> void:
	_pending_burst = false
	_aim_frozen = true
	_pulse_left = PULSE_COUNT
	_pulse_wait = PULSE_GAP
	if not _aim_point.is_finite():
		_aim_point = _combat_position_of(player)
	_fire_pulse(player)


func _service_pulses(delta: float) -> void:
	if _pulse_left <= 0:
		return
	if _movement_locked():
		_abort_aim()
		return
	_pulse_wait = maxf(_pulse_wait - delta, 0.0)
	if _pulse_wait > 0.0:
		return
	_pulse_left -= 1
	if _pulse_left <= 0:
		_aim_frozen = false
		_act = ""
		_faces_motion = true
		_fire_left = maxf(_fire_left, maxf(fire_scale(), CrawlerHunt.SCOUT_FIRE))
		return
	_pulse_wait = PULSE_GAP
	_fire_pulse(_nearest_player())


func _fire_pulse(player: Node) -> void:
	var shot := _cannon_span()
	if shot.is_empty():
		return
	var from: Vector3 = shot[0]
	var to: Vector3 = shot[1]
	_flash_beam(from, to, EnergyVfx.TINT_PINK, PULSE_RADIUS)
	var hit := DamageHit.beam(from, to, PULSE_RADIUS, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_scout_beam"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		if hit.reaches(
				_combat_position_of(player),
				float(player.call(&"combat_radius")) if player.has_method(
					&"combat_radius") else 0.4):
			player.call(&"apply_damage", hit.resolved_for(player))
	if _horde != null and _horde.has_method(&"publish_scout_beam"):
		_horde.call(&"publish_scout_beam", from, to)


func _flash_beam(from: Vector3, to: Vector3, tint: Color, radius: float) -> void:
	var world: Node = DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	if world == null:
		return
	var beam := EnergyVfx.make(EnergyVfx.Kind.BEAM_CORE, tint)
	beam.name = "ScoutPulse"
	world.add_child(beam)
	beam.place_beam(from, to, radius)
	var tree := get_tree()
	if tree != null:
		tree.create_timer(0.12).timeout.connect(beam.queue_free)
	else:
		beam.queue_free()


func cannon_ahead() -> Vector3:
	if is_instance_valid(_muzzle) and _muzzle.is_inside_tree():
		var ahead := _muzzle.global_transform.basis.z
		if ahead.length_squared() > 0.0001:
			return ahead.normalized()
	var ahead := global_transform.basis.z
	if ahead.length_squared() > 0.0001:
		return ahead.normalized()
	return Vector3.FORWARD


func _cannon_reach() -> float:
	return maxf(CrawlerMobs.number(
		wild_kind(), threat_level, "engage_max", CrawlerRules.RANGER_ENGAGE_MAX), 4.0)


func _cannon_span() -> PackedVector3Array:
	var from := muzzle_point()
	var ahead := cannon_ahead()
	if ahead.length_squared() < 0.0001:
		return PackedVector3Array()
	return PackedVector3Array([from, from + ahead * _cannon_reach()])


func _place_pointer() -> void:
	if _pointer == null:
		return
	if not _aim_point.is_finite() or not _alive:
		_pointer.visible = false
		return
	var shot := _cannon_span()
	if shot.is_empty() or not _pointer.place_beam(shot[0], shot[1], POINTER_RADIUS):
		_pointer.visible = false


func _bank_visual(delta: float) -> void:
	var root := find_child("Creature", false, false) as Node3D
	if root == null:
		return
	var up := _up()
	var ahead := global_transform.basis.z
	ahead -= up * ahead.dot(up)
	if ahead.length_squared() < 0.0001:
		return
	ahead = ahead.normalized()
	var right := up.cross(ahead)
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var want := Vector2.ZERO
	if not _aim_frozen:
		want = Vector2(
			clampf(-velocity.dot(up) * BANK_PITCH, -0.28, 0.28),
			clampf(-velocity.dot(right) * BANK_ROLL, -0.55, 0.55))
		_bank = _bank.lerp(want, clampf(delta * 6.0, 0.0, 1.0))
	else:
		_bank = Vector2.ZERO
	root.rotation = Vector3(_bank.x, 0.0, _bank.y)


func _bind_cannon() -> void:
	if _muzzle != null:
		return
	var model := find_child("Creature", true, false)
	if model == null:
		return
	var tip := Marker3D.new()
	tip.name = "CannonTip"
	tip.position = CANNON_LOCAL
	var host := model.get_child(0) as Node3D if model.get_child_count() > 0 \
		else model
	if host == null:
		host = model
	host.add_child(tip)
	_muzzle = tip
