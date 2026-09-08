class_name CrawlerThrenody
extends CrawlerMob

## Six-winged cursed giant. One engages at a time; the rest despawn.
## Patrols an infinity loop, then locks to the top-middle of the player's
## view and drops iridescent shock columns.

const BODY := preload("res://game/crawler/crawler_demon_body.gd")
const COLUMN := preload("res://game/crawler/crawler_demon_column.gd")
const PAINT_PATH := "res://assets/runtime/biomes/paint/threnody_paint.png"
const HEIGHT := 16.5
const WIDTH := 5.8
const INK := Color(0.10, 0.04, 0.16)


var _fire_left := 0.0
var _loop_u := 0.0
var _sway_clock := 0.0
var _columns: Array = []


func _ready() -> void:
	_base_health = 20.0
	_base_damage = 13.0
	_base_speed = 28.0
	_faces_motion = true
	_uses_model_front = true
	super._ready()
	_loop_u = float(hash(mob_id) % 97) * 0.07


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, WIDTH * 0.72)
	shape.shape = box
	add_child(shape)
	var packed := CrawlerDemonModels.scene(wild_kind())
	if packed != null:
		_attach_skinned(packed, HEIGHT)
	else:
		BODY.build(self, 6, HEIGHT, INK, BODY.load_paint(PAINT_PATH))


func wild_kind() -> String:
	return "threnody"


func combat_display_name() -> String:
	return "Threnody"


func combat_position() -> Vector3:
	return global_position + _up() * (HEIGHT * 0.18)


func combat_radius() -> float:
	return WIDTH * 0.48


func flies() -> bool:
	return true


func flyer_floor() -> float:
	return HEIGHT * 0.42 + 8.0


func live_columns() -> int:
	_prune_columns()
	return _columns.size()


func infinity_point(u: float) -> Vector3:
	var up := _up()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := up.cross(east).normalized()
	var rx := CrawlerRules.THRENODY_LOOP_X
	var rz := CrawlerRules.THRENODY_LOOP_Z
	var at := hang_origin + east * sin(u) * rx + north * sin(u) * cos(u) * rz
	return _clamp_flyer_band(at)


func hold_station(player: Node) -> Vector3:
	var origin := _view_origin(player)
	var look := _player_view(player)
	var lift := _view_up(player)
	var hold := lerpf(
		CrawlerMobs.number(wild_kind(), threat_level, "standoff_min",
			CrawlerRules.THRENODY_STANDOFF_MIN),
		CrawlerMobs.number(wild_kind(), threat_level, "standoff_max",
			CrawlerRules.THRENODY_STANDOFF_MAX),
		0.55)
	var right := look.cross(lift)
	if right.length_squared() < 0.0001:
		right = lift.cross(Vector3.RIGHT)
	right = right.normalized()
	var sway := right * sin(_sway_clock * 1.15) * 2.6 \
		+ lift * sin(_sway_clock * 0.72 + 1.1) * 1.5
	var station := origin + look * hold + lift * CrawlerRules.THRENODY_LIFT + sway
	return _clamp_flyer_band(station)


func sees_player(player: Node3D) -> bool:
	if player == null:
		return false
	return global_position.distance_to(_combat_position_of(player)) \
		<= CrawlerRules.THRENODY_PERCEPTION


func tick_agro(player: Node3D, delta: float) -> bool:
	if _other_threnody_engaged():
		_yield_field()
		return false
	var engaged := super.tick_agro(player, delta)
	if chase:
		_clear_idle_siblings()
	return engaged


func apply_damage(hit: DamageHit) -> float:
	var amount := super.apply_damage(hit)
	if not _alive:
		return amount
	if _other_threnody_engaged():
		_yield_field()
	elif chase:
		_clear_idle_siblings()
	return amount


func drop_column_now() -> Node:
	return _drop_column()


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _attack_left > 0.0:
		return BODY.CLIP_CAST
	if _flash_left > 0.04:
		return CLIP_HIT
	return BODY.CLIP_FLY


func _tick_idle(delta: float) -> void:
	_patrol_infinity(delta)


func _tick_ai(delta: float) -> void:
	_fire_left = maxf(_fire_left - delta, 0.0)
	_sway_clock += delta
	_prune_columns()
	var player := _hunt_target(delta)
	if player == null:
		_tick_idle(delta)
		return
	_lock_camera(player, delta)
	if _fire_left <= 0.0 and live_columns() < CrawlerRules.THRENODY_COLUMN_CAP:
		_drop_column()


func _patrol_infinity(delta: float) -> void:
	_loop_u += delta * 0.55
	_patrol_goal = infinity_point(_loop_u)
	_match_speed(move_speed() * 0.48, delta, 1.4, 10.0)
	var along := _patrol_goal - global_position
	if along.length_squared() < 0.2:
		velocity = velocity.move_toward(Vector3.ZERO, 8.0 * delta)
		return
	_steer_toward(along.normalized() * _cruise, delta, 11.0)


func _lock_camera(player: Node, delta: float) -> void:
	var station := hold_station(player)
	var player_speed := _player_speed(player)
	_match_speed(maxf(player_speed * 1.2, move_speed()), delta, 2.8, 42.0)
	var along := station - global_position
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 20.0)


func _drop_column() -> Node:
	if not _begin_attack(0.72):
		return null
	_fire_left = CrawlerMobs.number(
		wild_kind(), threat_level, "fire", CrawlerRules.THRENODY_FIRE)
	var parent := get_parent()
	if parent == null:
		return null
	var radius := clampf(
		CrawlerRules.THRENODY_COLUMN_RADIUS + float(maxi(threat_level - 1, 0)) * 0.8,
		5.0, 10.0)
	var column: Node = COLUMN.place(
		parent, self, _ground_under(), radius, damage(),
		CrawlerRules.THRENODY_COLUMN_DURATION,
		CrawlerRules.THRENODY_COLUMN_HEIGHT)
	if column != null:
		_columns.append(column)
	return column


func _ground_under() -> Vector3:
	var surface := ground_surface()
	if surface.is_finite():
		return surface
	var altitude := surface_altitude()
	if altitude > 0.05:
		return global_position - _up() * altitude
	return global_position


func _other_threnody_engaged() -> bool:
	return MobSense.any_chasing_kind("threnody", self)


func _clear_idle_siblings() -> void:
	if _horde != null and _horde.has_method(&"dismiss_idle_kind"):
		_horde.call(&"dismiss_idle_kind", wild_kind(), self)
	for item: Variant in MobSense.each_kind(wild_kind(), self):
		var sibling := item as CrawlerMob
		if sibling == null or sibling.chase or sibling.dismissed:
			continue
		sibling.dismiss()


func _yield_field() -> void:
	chase = false
	if dismissed or not _alive:
		return
	if _horde != null and _horde.has_method(&"dismiss_mob"):
		_horde.call(&"dismiss_mob", mob_id)
		return
	dismiss()


func _prune_columns() -> void:
	var kept: Array = []
	for column_variant: Variant in _columns:
		if not is_instance_valid(column_variant):
			continue
		var column := column_variant as Node
		if column != null and column.has_method(&"remaining") \
				and float(column.call(&"remaining")) > 0.0:
			kept.append(column)
	_columns = kept


func _view_origin(player: Node) -> Vector3:
	var camera := _player_camera(player)
	if camera != null:
		return camera.global_position
	return _combat_position_of(player)


func _player_view(player: Node) -> Vector3:
	if player != null and player.has_method(&"look_direction"):
		var look: Variant = player.call(&"look_direction")
		if look is Vector3 and (look as Vector3).is_finite() \
				and (look as Vector3).length_squared() > 0.0001:
			return (look as Vector3).normalized()
	if player is Node3D:
		var facing := -(player as Node3D).global_transform.basis.z
		if facing.length_squared() > 0.0001:
			return facing.normalized()
	return Vector3.FORWARD


func _view_up(player: Node) -> Vector3:
	var camera := _player_camera(player)
	if camera != null:
		var lift := camera.global_basis.y
		if lift.length_squared() > 0.0001:
			return lift.normalized()
	if player is Node3D:
		var lift := (player as Node3D).global_transform.basis.y
		if lift.length_squared() > 0.0001:
			return lift.normalized()
	return _up()


func _player_camera(player: Node) -> Camera3D:
	if player == null:
		return null
	var held: Variant = player.get(&"camera")
	return held as Camera3D if held is Camera3D else null
