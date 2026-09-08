class_name CrawlerVex
extends CrawlerGoblin

## Stays in the back of the castle horde and lobs a red pulsing mortar from
## the top of his staff.

const SHOT := preload("res://game/crawler/crawler_vex_mortar.gd")
const VEX_HEIGHT := 1.72
const VEX_WIDTH := 0.58
const VEX_INK := Color(0.36, 0.16, 0.18)
const MORTAR_GRAVITY := 22.0
const LOB_SECONDS := 0.38


var _fire_left := 0.0


func _ready() -> void:
	_base_health = 5.0
	_base_damage = 10.0
	_base_speed = 7.0
	super._ready()


func wild_kind() -> String:
	return "vex"


func body_height() -> float:
	return VEX_HEIGHT


func body_width() -> float:
	return VEX_WIDTH


func body_ink() -> Color:
	return VEX_INK


func _build_fallback(colour: Color) -> void:
	super._build_fallback(colour)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.045
	pole.height = body_height() * 0.95
	var staff := MeshInstance3D.new()
	staff.name = "Staff"
	staff.mesh = pole
	staff.position = Vector3(body_width() * 0.42, body_height() * 0.08, 0.12)
	staff.rotation_degrees.z = 12.0
	staff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(0.18, 0.08, 0.08)
	staff.material_override = ink
	add_child(staff)
	var orb := SphereMesh.new()
	orb.radius = 0.09
	orb.height = 0.18
	var tip := MeshInstance3D.new()
	tip.name = "StaffTip"
	tip.mesh = orb
	tip.position = Vector3(0.0, pole.height * 0.5 + 0.06, 0.0)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.16, 0.12)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.12, 0.08)
	glow.emission_energy_multiplier = 4.6
	tip.material_override = glow
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	staff.add_child(tip)
	_staff = tip


func _tick_ai(delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	snap_to_ground()
	if _attacking():
		velocity = velocity.move_toward(Vector3.ZERO, 22.0 * delta)
		return
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_hold_back(player, delta)
	_try_lob(player)


func _hold_back(player: Node, delta: float) -> void:
	var along := _flat_toward(_combat_position_of(player))
	var gap := along.length()
	var hold := CrawlerMobs.number(
		wild_kind(), threat_level, "standoff_min",
		CrawlerRules.GOBLIN_STANDOFF)
	var wanted := 0.0
	var heading := Vector3.ZERO
	if gap < hold * 0.82 and along.length_squared() > 0.0001:
		wanted = move_speed()
		heading = -along.normalized()
	elif gap > hold * 1.35 and along.length_squared() > 0.0001:
		wanted = move_speed() * 0.55
		heading = along.normalized()
	_match_speed(wanted, delta, 0.8, 8.0)
	if heading.length_squared() > 0.0001 and _cruise > 0.2:
		_steer_toward(heading * _cruise, delta, 10.0)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, 14.0 * delta)


func _try_lob(player: Node) -> void:
	if _fire_left > 0.0 or player == null:
		return
	var gap := _flat_toward(_combat_position_of(player)).length()
	var near := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_min", 8.0)
	var far := CrawlerMobs.number(
		wild_kind(), threat_level, "engage_max", 42.0)
	if gap < near or gap > far:
		return
	_lob(player)


func _lob(player: Node) -> void:
	var from := staff_tip()
	var target := _combat_position_of(player)
	var shot_speed := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_speed", CrawlerRules.GOBLIN_MORTAR_SPEED)
	var launch := CrawlerRules.lead_launch(
		from, target, _player_velocity(player), shot_speed, MORTAR_GRAVITY, _up())
	if launch.is_zero_approx():
		return
	if not _begin_attack(LOB_SECONDS):
		return
	_fire_left = maxf(fire_scale(), 1.6)
	var ball_radius := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_ball", 0.42)
	var hit_radius := CrawlerMobs.number(
		wild_kind(), threat_level, "shot_hit", 1.15)
	_spawn_shot(from, launch, shot_speed, ball_radius, hit_radius)
	if _horde != null and _horde.has_method(&"publish_vex_mortar"):
		_horde.call(
			&"publish_vex_mortar", from, launch, damage(), shot_speed,
			ball_radius, hit_radius)


func _spawn_shot(
		from: Vector3, launch: Vector3, shot_speed: float,
		ball_radius: float, hit_radius: float
	) -> void:
	var ball := SHOT.new()
	ball.damage = damage()
	ball.gravity = MORTAR_GRAVITY
	ball.shot_speed = shot_speed
	ball.ball_radius = ball_radius
	ball.hit_radius = hit_radius
	var world: Node = _planet
	if world == null:
		world = DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	if world == null or not ball.launch_anywhere(world, from, launch, self):
		ball.free()
