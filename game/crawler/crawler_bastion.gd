class_name CrawlerBastion
extends CrawlerRobot

## Slow office walker. Aims from the mid ring with the shared hunt
## stance. Any number can agro. One high trailed shell, then a red fuse.

const HEIGHT := 1.72
const WIDTH := 0.86
const SHELL := preload("res://game/crawler/crawler_bastion_shell.gd")
const FUSE_HOLD := 1.0
const FUSE_GLOW := 0.75
const BURST_RADIUS := 5.4
const CRATER_RADIUS := 4.0
const CRATER_DEPTH := 1.6
const BURST_TINT := Color(1.0, 0.18, 0.08)


var _spent_shot := false
var _fusing := false
var _fuse_left := 0.0
var _leave_left := 0.0


func _ready() -> void:
	_base_health = 8.0
	_base_damage = 11.0
	_base_speed = 1.8
	super._ready()
	_faces_motion = true


func wild_kind() -> String:
	return "bastion"


func body_height() -> float:
	return HEIGHT * BODY_SCALE


func body_width() -> float:
	return WIDTH * BODY_SCALE


func muzzle_bone() -> String:
	return "socket_hand.R"


func flies() -> bool:
	return false


func fusing() -> bool:
	return _fusing


func set_director_lod(lod: int) -> void:
	if _fusing:
		_director_lod = lod
		set_physics_process(true)
		set_process(true)
		return
	super.set_director_lod(lod)


func _process(delta: float) -> void:
	if _fusing:
		_paint_fuse()
		_update_clips()
		return
	super._process(delta)


func _physics_process(delta: float) -> void:
	if _fusing:
		_tick_fuse(delta)
		return
	super._physics_process(delta)


func _tick_idle(delta: float) -> void:
	_shuffle(delta)


func _tick_ai(delta: float) -> void:
	if _fusing:
		return
	var player := _hunt_target(delta)
	if player == null:
		_fire_left = maxf(_fire_left - delta, 0.0)
		_leave_left = maxf(_leave_left - delta, 0.0)
		_shuffle(delta)
		return
	_fight(player, delta)


func _tick_far(delta: float) -> void:
	if _fusing:
		return
	var player := _nearest_player()
	if player != null and tick_agro(player, delta):
		_fight(player, delta)
		return
	_fire_left = maxf(_fire_left - delta, 0.0)
	_leave_left = maxf(_leave_left - delta, 0.0)
	_shuffle(delta)


func _tick_cold(delta: float, _steer := true) -> void:
	if _fusing:
		return
	super._tick_cold(delta, false)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _fusing or _movement_locked():
		velocity = Vector3.ZERO
		return
	var step := maxf(delta, 0.0)
	if player != null and _apply_agro(player, step, in_city):
		_fight(player, step)
		return
	_fire_left = maxf(_fire_left - step, 0.0)
	_leave_left = maxf(_leave_left - step, 0.0)
	_shuffle(step)


func _fight(player: Node, delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	_leave_left = maxf(_leave_left - delta, 0.0)
	snap_to_ground()
	if _attacking():
		velocity = velocity.move_toward(Vector3.ZERO, 16.0 * delta)
		_face_player(player)
		return
	_face_player(player)
	_tick_hunt_motion(player, delta)
	var gap := _flat_toward(_combat_position_of(player)).length()
	var far := CrawlerHunt.shot_max(wild_kind(), threat_level)
	if _spent_shot and gap > far and _leave_left <= 0.0:
		dismiss()
		return
	if gap <= far:
		_hold_and_lob(player, delta)


func _face_player(player: Node) -> void:
	if player == null:
		return
	var look := _flat_toward(_combat_position_of(player))
	if look.length_squared() < 0.0001:
		return
	global_transform.basis = _look_basis(look.normalized(), _up())


func _shuffle(delta: float) -> void:
	_act = ""
	_match_speed(move_speed(), delta, 1.1)
	_patrol_left -= delta
	if _patrol_left <= 0.0 or _flat_toward(_patrol_goal).length() < 1.4:
		_patrol_serial += 1
		_patrol_left = PATROL_RETARGET + float(_patrol_serial % 7) * 0.4
		_patrol_goal = hang_origin
		if hang_origin.is_finite():
			var bias := _orbit_bias() * 2.4
			_patrol_goal = hang_origin + bias
	var along := _flat_toward(_patrol_goal)
	if along.length_squared() < 0.08:
		velocity = velocity.move_toward(Vector3.ZERO, 6.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 4.0)


func _hold_and_lob(player: Node, delta: float) -> void:
	_faces_motion = false
	velocity = velocity.move_toward(Vector3.ZERO, 14.0 * delta)
	var look := _flat_toward(_combat_position_of(player))
	if look.length_squared() > 0.0001:
		global_transform.basis = _look_basis(look, _up())
	_try_mortar(player)


func _try_mortar(player: Node) -> void:
	if _spent_shot or _fire_left > 0.0 or player == null:
		return
	var from := muzzle_point()
	var target := _combat_position_of(player)
	var shot_speed := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_speed", 24.0)
	var launch := CrawlerRules.high_lob_launch(
		from, target, _player_velocity(player), shot_speed,
		CrawlerRules.BASTION_GRAVITY, _up(), CrawlerRules.BASTION_LOFT)
	if launch.is_zero_approx():
		return
	if not _begin_attack(1.4):
		return
	_act = CLIP_STOMP
	_spent_shot = true
	_leave_left = 0.55
	_fire_left = maxf(fire_scale(), 2.4)
	var ball := SHELL.new()
	ball.damage = damage()
	ball.gravity = CrawlerRules.BASTION_GRAVITY
	ball.shot_speed = shot_speed
	ball.ball_radius = CrawlerMobs.number(
		wild_kind(), threat_level, "shot_ball", 0.36)
	ball.hit_radius = CrawlerMobs.number(
		wild_kind(), threat_level, "shot_hit", 2.2)
	ball.ability_id = "crawler_bastion_mortar"
	ball.lift = _up()
	var impact := CrawlerRules.high_lob_intercept(
		from, target, _player_velocity(player), shot_speed,
		CrawlerRules.BASTION_GRAVITY, _up(), CrawlerRules.BASTION_LOFT)
	ball.impact_at = impact if impact.is_finite() else target
	var world: Node = _planet
	if world == null:
		world = DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	if world == null or not ball.launch_anywhere(world, from, launch, self):
		ball.free()
		return
	if _horde != null and _horde.has_method(&"publish_bastion_shell"):
		_horde.call(
			&"publish_bastion_shell", from, launch, damage(), shot_speed,
			ball.ball_radius, ball.hit_radius, ball.impact_at)


func recycle_to(at: Vector3) -> void:
	_spent_shot = false
	_leave_left = 0.0
	_fusing = false
	_fuse_left = 0.0
	super.recycle_to(at)


func _die() -> void:
	if not _alive or dismissed or _fusing:
		return
	_alive = false
	velocity = Vector3.ZERO
	_fusing = true
	_fuse_left = FUSE_HOLD + FUSE_GLOW
	MobSense.note_gone(self)
	set_physics_process(true)
	set_process(true)
	_force_publish()


func _tick_fuse(delta: float) -> void:
	_fuse_left = maxf(_fuse_left - delta, 0.0)
	_paint_fuse()
	if _fuse_left <= 0.0:
		_explode()


func _paint_fuse() -> void:
	var glow := 0.0
	if _fuse_left <= FUSE_GLOW:
		glow = 1.0 - _fuse_left / maxf(FUSE_GLOW, 0.05)
	for index in _skinned_mats.size():
		var material := _skinned_mats[index]
		if material == null:
			continue
		var rest := _skinned_energy[index] if index < _skinned_energy.size() else 0.0
		var rest_color := _skinned_emit[index] if index < _skinned_emit.size() \
			else material.emission
		material.emission_enabled = glow > 0.02 or rest > 0.02
		material.emission = rest_color.lerp(BURST_TINT, glow)
		material.emission_energy_multiplier = lerpf(rest, 6.8, glow)
	for material in _materials:
		if material != null:
			material.set_shader_parameter(&"flash", glow)


func _explode() -> void:
	if dismissed:
		return
	var at := combat_position()
	_play_burst_vfx(at)
	if _is_host():
		_apply_burst(at)
		_cut_crater(at)
	died.emit()
	_force_publish()
	queue_free()


func _play_burst_vfx(at: Vector3) -> void:
	if _horde != null and _horde.has_method(&"publish_bastion_burst"):
		_horde.call(&"publish_bastion_burst", at, BURST_RADIUS)
		return
	EnergyExplosion.burst(_effect_world(), at, BURST_RADIUS, BURST_TINT, 0.5)


func _apply_burst(at: Vector3) -> void:
	var amount := damage() * 1.35
	var mobs := DamageHit.area(at, BURST_RADIUS, amount, 0.35)
	mobs.faction = DamageHit.Faction.PLAYER
	mobs.ability_id = "crawler_bastion_burst"
	mobs.affects_flora = false
	mobs.parryable = false
	mobs.reaction = DamageHit.Reaction.KNOCKBACK
	mobs.radial_impulse = 16.0
	mobs.radial_lift = 7.0
	mobs.set_source(self)
	_deliver_burst(mobs, GROUP)
	var players := DamageHit.area(at, BURST_RADIUS, amount, 0.35)
	players.faction = DamageHit.Faction.ENEMY
	players.ability_id = "crawler_bastion_burst"
	players.affects_flora = false
	players.parryable = true
	players.reaction = DamageHit.Reaction.KNOCKBACK
	players.radial_impulse = 16.0
	players.radial_lift = 7.0
	players.set_source(self)
	_deliver_burst(players, &"network_players")


func _deliver_burst(hit: DamageHit, group: StringName) -> void:
	if hit == null:
		return
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
		return
	if not is_inside_tree():
		return
	for node_variant: Variant in get_tree().get_nodes_in_group(group):
		var node := node_variant as Node
		if node == null or node == self or not node.has_method(&"apply_damage"):
			continue
		if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")) \
				and node != self:
			continue
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = float(node.call(&"combat_radius"))
		if not hit.reaches(_combat_position_of(node), bounds):
			continue
		node.call(&"apply_damage", hit.resolved_for(node))


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
	scar.char = 0.42
	scar.tint = Color(0.22, 0.10, 0.08)
	scar.warp = 0.1
	scar.seed = fposmod(at.x * 0.611 + at.y * 1.273 + at.z * 1.902, TAU)
	if world != null and world.has_method(&"request_scar"):
		world.call(&"request_scar", scar)
	else:
		planet.add_scar(scar)
