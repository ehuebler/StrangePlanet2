class_name ImpactCastMeteor
extends Node3D

## A meteor punch thrown from an Impact Cast site, not from the player's body.


var shooter: OnlinePlayer
var stats: Dictionary = {}
var authoritative := false

var _along := Vector3.FORWARD
var _speed := 60.0
var _top_speed := 200.0
var _range := 50.0
var _travelled := 0.0
var _shock: MeteorShock
var _since_sweep := 0.0
var _last_at := Vector3.ZERO


static func launch(world: Node, source: OnlinePlayer, from: Vector3,
		along: Vector3, overlay: Dictionary, owns_impact: bool) -> ImpactCastMeteor:
	if world == null or source == null or not from.is_finite() \
			or along.length_squared() < 0.000001:
		return null
	var strike := ImpactCastMeteor.new()
	strike.shooter = source
	strike.stats = overlay.duplicate(true)
	strike.authoritative = owns_impact
	strike._along = along.normalized()
	strike._speed = maxf(float(overlay.get("speed",
		OnlinePlayer.METEOR_LAUNCH_SPEED)), OnlinePlayer.METEOR_LAUNCH_SPEED)
	strike._top_speed = maxf(float(overlay.get("speed", 200.0)), strike._speed)
	strike._range = maxf(float(overlay.get("range", 50.0)), 4.0)
	if source.has_method(&"crawler_range_scale"):
		strike._range *= float(source.call(&"crawler_range_scale"))
	world.add_child(strike)
	strike.global_position = from
	return strike


func _ready() -> void:
	name = "ImpactCastMeteor"
	top_level = true
	_last_at = global_position
	_shock = MeteorShock.new()
	_shock.radius = maxf(float(stats.get("radius",
		OnlinePlayer.METEOR_FIST_RADIUS)), 1.2)
	add_child(_shock)
	_shock.aim(global_position, _along, _speed)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(shooter):
		queue_free()
		return
	if CrawlerHoming.enabled(stats):
		var steered := CrawlerHoming.steer(
			_along * _speed, global_position, stats, shooter, delta, _speed)
		if steered.length_squared() > 0.0001:
			_along = steered.normalized()
	_speed = move_toward(_speed, _top_speed,
		OnlinePlayer.METEOR_ACCELERATION * delta)
	var step := _along * _speed * delta
	var from := global_position
	var to := from + step
	var hit := LaserEyes._surface(shooter, from, to)
	if not hit.is_empty():
		global_position = hit.get("position", to) as Vector3
		_land(hit.get("normal", -_along) as Vector3, true)
		return
	global_position = to
	_travelled += step.length()
	if is_instance_valid(_shock):
		_shock.aim(global_position, _along, _speed)
	_sweep(from, global_position, delta)
	if _travelled >= _range:
		_land(-_along, false)


func _sweep(from: Vector3, to: Vector3, delta: float) -> void:
	_since_sweep += delta
	if _since_sweep < OnlinePlayer.METEOR_DAMAGE_STEP:
		return
	_since_sweep -= OnlinePlayer.METEOR_DAMAGE_STEP
	if not authoritative:
		return
	var radius := maxf(float(stats.get("radius",
		OnlinePlayer.METEOR_FIST_RADIUS)), 1.2)
	var damage := maxf(float(stats.get("damage", 0.0)), 0.0) \
		* OnlinePlayer.METEOR_TICK_SHARE
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	for slide: float in CrawlerMulti.punch_offsets(CrawlerMulti.shots(stats)):
		var a := from + _along * slide
		var b := to + _along * slide
		var hit := DamageHit.beam(a, b, radius, damage)
		hit.ability_id = "meteor_punch"
		if knockback > 0.0:
			hit.world_impulse = _along * knockback * OnlinePlayer.METEOR_TICK_SHARE
		CrawlerElements.stamp(hit, shooter, "meteor_punch", stats)
		DamageHit.apply_to_world(shooter, hit)


func _land(facing: Vector3, struck: bool) -> void:
	if is_instance_valid(_shock):
		_shock.stop()
	var at := global_position
	var force := clampf(_speed / maxf(_top_speed, 1.0), 0.35, 2.0)
	var spread := OnlinePlayer.METEOR_SPREAD \
		* maxf(float(stats.get("size", 1.0)), 1.0) * force
	var crater_radius := maxf(float(stats.get("crater_radius",
		OnlinePlayer.METEOR_CRATER_RADIUS)), 0.1) * force
	var crater_depth := maxf(float(stats.get("crater_depth",
		OnlinePlayer.METEOR_CRATER_DEPTH)), 0.1) * force
	if authoritative:
		var blow := DamageHit.area(
			at, spread, maxf(float(stats.get("impact", 0.0)), 0.0) * force, 1.0)
		blow.ability_id = "meteor_punch"
		blow.explosive = true
		blow.affects_flora = false
		var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0) * force
		if knockback > 0.0:
			blow.world_impulse = _along * knockback
			blow.radial_impulse = knockback * 0.55
			blow.radial_lift = knockback * 0.2
		CrawlerElements.stamp(blow, shooter, "meteor_punch", stats)
		DamageHit.apply_to_world(shooter, blow)
		CrawlerBubbles.emit_blast(shooter, "meteor_punch", at, spread)
		CrawlerLingers.emit_blast(shooter, "meteor_punch", at, spread)
		var world_planet := shooter.planet() if shooter.has_method(&"planet") \
			else null
		if world_planet != null:
			var flatten := DamageHit.area(
				at, crater_radius + OnlinePlayer.METEOR_FLORA_MARGIN,
				maxf(OnlinePlayer.METEOR_FLORA_DAMAGE,
					float(stats.get("impact", 0.0)) * force), 0.0)
			flatten.ability_id = "meteor_punch"
			flatten.affects_combatants = false
			flatten.plant_break_effects = false
			shooter.deal_damage(flatten)
			var scar := TerrainScars.Scar.new()
			scar.direction = world_planet.to_local(at).normalized()
			scar.radius = crater_radius
			scar.depth = crater_depth
			scar.profile = TerrainScars.Profile.BOWL if struck \
				else TerrainScars.Profile.CONE
			scar.char = 0.35
			scar.tint = Color(0.16, 0.13, 0.11)
			shooter.request_scar(scar)
	if shooter.has_method(&"play_meteor_impact_dust"):
		shooter.play_meteor_impact_dust(at, facing, crater_radius, force)
	queue_free()
