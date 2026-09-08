class_name CrawlerRobot
extends CrawlerMob

## Shared authored Null Forge body. Office-patch robots keep Blender clips
## and a muzzle socket. Unique hunt still lives in each kind's `_tick_ai`.

const MODELS := preload("res://game/crawler/crawler_robot_models.gd")
const LASER := preload("res://game/crawler/crawler_robot_laser.gd")
const CLIP_SHUTDOWN := "Shutdown"
const CLIP_FIRE := "Fire_Burst"
const CLIP_PUNCH := "Punch"
const CLIP_STOMP := "Stomp"
const CLIP_PINCER := "Pincer_Attack"
const CLIP_TURRET := "Turret_Fire"
const CLIP_LEAP := "Leap"
const WALK_SPEED := 2.4
const RUN_SPEED := 6.2
const BODY_SCALE := 1.6
const INK := Color(0.46, 0.50, 0.52)

var _muzzle: Node3D
var _fire_left := 0.0
var _act := ""


func _ready() -> void:
	_faces_motion = true
	_uses_model_front = true
	super._ready()
	motion_mode = MOTION_MODE_FLOATING


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_width() * 0.48
	capsule.height = maxf(body_height() * 0.72, capsule.radius * 2.0 + 0.05)
	shape.shape = capsule
	add_child(shape)
	var packed := MODELS.scene(wild_kind())
	if packed != null:
		_attach_skinned(packed, body_height())
		var model := find_child("Creature", true, false)
		if model != null:
			_muzzle = MODELS.bind_socket(model, muzzle_bone())
	else:
		_build_fallback()


func body_height() -> float:
	return 2.2 * BODY_SCALE


func body_width() -> float:
	return 0.9 * BODY_SCALE


func muzzle_bone() -> String:
	return "socket_muzzle"


func combat_display_name() -> String:
	return CrawlerMobs.title(wild_kind(), maxi(threat_level, 1))


func combat_position() -> Vector3:
	return global_position + _up() * (body_height() * 0.22)


func combat_radius() -> float:
	return body_width() * 0.55


func ground_clearance() -> float:
	return body_height() * 0.5


func muzzle_point() -> Vector3:
	if _muzzle is Node3D:
		return _muzzle.global_position
	return combat_position() + -global_transform.basis.z * (body_width() * 0.7)


func _flat_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _reach_of(player: Node, extra := 0.0) -> float:
	var reach := extra
	if player != null and player.has_method(&"combat_radius"):
		reach += float(player.call(&"combat_radius"))
	return reach


func _melee(player: Node, reach: float, ability: String) -> void:
	var hit := DamageHit.impact(combat_position(), reach, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = ability
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


func _spawn_laser(
		along: Vector3, delay := 0.0, glow := Color(0.12, 0.78, 1.0),
		core := Color(0.55, 0.95, 1.0), ability := "crawler_robot_laser"
	) -> void:
	var heading := along
	if heading.length_squared() < 0.0001:
		heading = -global_transform.basis.z
	var bolt := LASER.new()
	bolt.damage = damage()
	bolt.shot_speed = CrawlerMobs.number(
		wild_kind(), threat_level, "shot_speed", 48.0)
	bolt.ball_radius = CrawlerMobs.number(
		wild_kind(), threat_level, "shot_ball", 0.08)
	bolt.hit_radius = CrawlerMobs.number(
		wild_kind(), threat_level, "shot_hit", 0.42)
	bolt.arm_delay = maxf(delay, 0.0)
	bolt.core_color = core
	bolt.glow_color = glow
	bolt.ability_id = ability
	var world: Node = _planet
	if world == null:
		world = DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	if world == null or not bolt.launch_anywhere(world, muzzle_point(), heading, self):
		bolt.free()
		return
	if _horde != null and _horde.has_method(&"publish_robot_laser"):
		_horde.call(
			&"publish_robot_laser", muzzle_point(),
			heading.normalized() * bolt.shot_speed, damage(),
			bolt.shot_speed, bolt.ball_radius, bolt.hit_radius, glow)


func _desired_clip() -> String:
	if not _alive:
		return CLIP_SHUTDOWN
	if not _act.is_empty() and _attack_left > 0.0:
		return _act
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	if flies():
		return CLIP_FLY if velocity.length() > 1.4 else CLIP_IDLE
	var speed := velocity.length()
	if speed >= RUN_SPEED:
		return CLIP_RUN
	if speed >= WALK_SPEED:
		return CLIP_WALK
	return CLIP_IDLE


func _clip_aliases(clip: String) -> PackedStringArray:
	match clip:
		CLIP_ATTACK:
			return PackedStringArray([
				CLIP_FIRE, CLIP_PUNCH, CLIP_PINCER, CLIP_ATTACK, "Strike"])
		CLIP_CAST:
			return PackedStringArray([CLIP_STOMP, CLIP_TURRET, CLIP_CAST])
		CLIP_HIT:
			return PackedStringArray(["Hit_React", CLIP_HIT, "Hit"])
		CLIP_SHUTDOWN:
			return PackedStringArray([CLIP_SHUTDOWN, "Hit_React", CLIP_HIT])
		CLIP_FIRE:
			return PackedStringArray([CLIP_FIRE])
		CLIP_PUNCH:
			return PackedStringArray([CLIP_PUNCH])
		CLIP_STOMP:
			return PackedStringArray([CLIP_STOMP])
		CLIP_PINCER:
			return PackedStringArray([CLIP_PINCER])
		CLIP_TURRET:
			return PackedStringArray([CLIP_TURRET])
		CLIP_LEAP:
			return PackedStringArray([CLIP_LEAP])
		CLIP_FLY:
			return PackedStringArray([CLIP_FLY, "Strafe", CLIP_RUN])
	return super._clip_aliases(clip)


func _bind_animator(model: Node) -> void:
	super._bind_animator(model)
	if _animator == null:
		return
	for clip: String in [CLIP_IDLE, CLIP_WALK, CLIP_RUN, CLIP_FLY, "Strafe", "Guard"]:
		var resolved := _resolve_clip(clip)
		if not resolved.is_empty() and _animator.has_animation(resolved):
			_animator.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR


func _build_fallback() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = body_width() * 0.38
	mesh.height = body_height() * 0.86
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _enemy_material(INK, null, 0.0)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	_visual = visual
