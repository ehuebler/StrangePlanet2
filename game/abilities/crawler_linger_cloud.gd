class_name CrawlerLingerCloud
extends Node3D

## Iridescent puff left by Linger. Carries the host effect, fades quickly,
## and can slow bodies that walk through it.

const GROUP := &"crawler_lingers"
const TICK_HZ := 4.0
const TICK_STEP := 1.0 / TICK_HZ
const BASE_ALPHA := 0.58
const IRIS_SHADER := preload("res://shaders/crawler/crawler_iris_cloud.gdshader")

var shooter: OnlinePlayer
var ability_id := ""
var cloud_tint := Color(0.62, 0.88, 1.0)
var radius := CrawlerRules.LINGER_RADIUS
var linger := CrawlerRules.LINGER_SECONDS
var damage := CrawlerRules.LINGER_DAMAGE
var slow := 0.0
var extra_statuses: Array = []
var authoritative := true
var homing := 0.0
var steer_rate := 0.0
var velocity := Vector3.ZERO

var _age := 0.0
var _since_tick := 0.0
var _inside: Dictionary = {}
var _material: ShaderMaterial
var _visual: MeshInstance3D
var _shooter_rid := RID()


static func spawn(world: Node, source: OnlinePlayer, recipe: Dictionary,
		at: Vector3, owns_hit := true) -> CrawlerLingerCloud:
	if world == null or source == null or not at.is_finite():
		return null
	var cloud := CrawlerLingerCloud.new()
	cloud.shooter = source
	cloud.ability_id = str(recipe.get("ability_id", "linger"))
	cloud.cloud_tint = recipe.get("tint", Color(0.62, 0.88, 1.0))
	cloud.radius = maxf(float(recipe.get("radius", CrawlerRules.LINGER_RADIUS)), 0.35)
	cloud.linger = maxf(float(recipe.get("duration", CrawlerRules.LINGER_SECONDS)), 0.2)
	cloud.damage = maxf(float(recipe.get("damage", 0.0)), 0.0)
	cloud.slow = clampf(float(recipe.get("slow", 0.0)), 0.0, CrawlerRules.LINGER_SLOW_MAX)
	cloud.homing = maxf(float(recipe.get("homing", 0.0)), 0.0)
	cloud.steer_rate = maxf(float(recipe.get("steer", 0.0)), 0.0)
	var carried: Variant = recipe.get("statuses", [])
	if carried is Array:
		cloud.extra_statuses = (carried as Array).duplicate(true)
	cloud.authoritative = owns_hit
	cloud._shooter_rid = source.get_rid()
	world.add_child(cloud)
	cloud.global_position = at
	return cloud


static func speed_scale_at(anywhere: Node, at: Vector3) -> float:
	var scale := 1.0
	if anywhere == null or not anywhere.is_inside_tree() or not at.is_finite():
		return scale
	for node_variant: Variant in anywhere.get_tree().get_nodes_in_group(GROUP):
		var cloud := node_variant as CrawlerLingerCloud
		if cloud == null or not cloud.contains(at):
			continue
		scale = minf(scale, cloud.speed_mul())
	return scale


static func wash_at(anywhere: Node, at: Vector3) -> Color:
	var wash := Color(0.0, 0.0, 0.0, 0.0)
	if anywhere == null or not anywhere.is_inside_tree() or not at.is_finite():
		return wash
	for node_variant: Variant in anywhere.get_tree().get_nodes_in_group(GROUP):
		var cloud := node_variant as CrawlerLingerCloud
		if cloud == null or not cloud.contains(at, 0.2):
			continue
		var color := cloud.cloud_tint
		color.a = cloud.fade_alpha() * 0.28
		if color.a > wash.a:
			wash = color
	return wash


func _ready() -> void:
	name = "CrawlerLingerCloud"
	top_level = true
	add_to_group(GROUP)
	set_process(true)
	set_physics_process(true)
	if DisplayServer.get_name() == "headless":
		return
	_material = ShaderMaterial.new()
	_material.shader = IRIS_SHADER
	_material.set_shader_parameter(&"tint", cloud_tint)
	_material.set_shader_parameter(&"alpha", BASE_ALPHA)
	_material.set_shader_parameter(&"spark", 0.42)
	_material.set_shader_parameter(&"iris", 1.08)
	_material.set_shader_parameter(&"edge_width", 0.32)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 16
	sphere.material = _material
	_visual = MeshInstance3D.new()
	_visual.mesh = sphere
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	_draw()


func _process(delta: float) -> void:
	_age += delta
	_draw()
	if _age >= linger:
		queue_free()


func _physics_process(delta: float) -> void:
	_chase(delta)
	if not authoritative:
		return
	_since_tick += delta
	if _since_tick < TICK_STEP:
		return
	_since_tick -= TICK_STEP
	_tick_inside()


func _chase(delta: float) -> void:
	if homing <= 0.001 or steer_rate <= 0.001 or not is_inside_tree():
		return
	var recipe := {
		"homing": steer_rate,
		"homing_range": homing,
	}
	velocity = CrawlerHoming.steer(
		velocity, global_position, recipe, shooter, delta, CrawlerHoming.CLOUD_SPEED)
	if velocity.length_squared() < 0.0001:
		return
	global_position += velocity * delta


func contains(at: Vector3, pad := 0.0) -> bool:
	if not at.is_finite() or remaining() <= 0.0:
		return false
	return at.distance_to(global_position) <= radius + pad


func remaining() -> float:
	return maxf(linger - _age, 0.0)


func fade_alpha() -> float:
	var share := clampf(_age / maxf(linger, 0.05), 0.0, 1.0)
	return BASE_ALPHA * pow(1.0 - share, 1.2)


func speed_mul() -> float:
	if slow <= 0.0:
		return 1.0
	return clampf(1.0 - slow / 100.0, 0.12, 1.0)


func _draw() -> void:
	if _visual == null or _material == null:
		return
	var pulse := 0.88 + 0.14 * sin(_age * TAU * 1.4)
	scale = Vector3.ONE * radius * pulse
	var alpha := fade_alpha()
	_material.set_shader_parameter(&"tint", cloud_tint)
	_material.set_shader_parameter(&"alpha", alpha)
	_material.set_shader_parameter(&"spark", 0.28 + alpha * 0.35)


func _tick_inside() -> void:
	if shooter == null or not shooter.is_inside_tree():
		return
	var seen: Dictionary = {}
	for node_variant: Variant in shooter.get_tree().get_nodes_in_group(
			DamageHit.COMBATANT_GROUP):
		var combatant := node_variant as Node
		if combatant == null or combatant == shooter:
			continue
		if not combatant.has_method(&"apply_damage") \
				or not combatant.has_method(&"combat_faction"):
			continue
		if int(combatant.call(&"combat_faction")) != DamageHit.Faction.ENEMY:
			continue
		if combatant.has_method(&"is_alive") \
				and not bool(combatant.call(&"is_alive")):
			continue
		var point := global_position
		if combatant.has_method(&"combat_position"):
			point = combatant.call(&"combat_position")
		elif combatant is Node3D:
			point = (combatant as Node3D).global_position
		var bounds := 0.4
		if combatant.has_method(&"combat_radius"):
			bounds = float(combatant.call(&"combat_radius"))
		var key := combatant.get_instance_id()
		if not contains(point, bounds):
			_inside.erase(key)
			continue
		seen[key] = true
		var first := not _inside.has(key)
		_inside[key] = true
		_affect(combatant, point, bounds, first)
	for key_variant: Variant in _inside.keys():
		if not seen.has(key_variant):
			_inside.erase(key_variant)


func _affect(combatant: Node, at: Vector3, bounds: float, first: bool) -> void:
	var amount := damage
	if not first:
		amount *= TICK_STEP
	if ability_id == "healing_field" or ability_id == "teleport":
		amount = 0.0
	var hit := DamageHit.impact(global_position,
		maxf(at.distance_to(global_position) + bounds + 0.3, 0.4), amount)
	hit.faction = DamageHit.Faction.PLAYER
	hit.ability_id = ability_id
	hit.affects_flora = false
	CrawlerElements.apply_to_hit(hit, extra_statuses, true, TICK_STEP)
	if amount <= 0.0 and hit.status.is_empty():
		return
	hit.set_source(shooter, shooter.peer_id)
	combatant.call(&"apply_damage", hit.resolved_for(combatant))
