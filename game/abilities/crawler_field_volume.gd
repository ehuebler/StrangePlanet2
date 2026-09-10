class_name CrawlerFieldVolume
extends Node3D

## Expanding opaque sphere left by a Field cast. Gameplay ticks on the host;
## the mesh, fade, and interior tint run on every peer.

const GROUP := &"ability_fields"
const TICK_HZ := 4.0
const TICK_STEP := 1.0 / TICK_HZ
const EXPAND := 0.55
const DRAW_LIMIT := 80.0
const BASE_ALPHA := 0.62
const IRIS_SHADER := preload("res://shaders/crawler/crawler_iris_cloud.gdshader")
const TINTS := {
	"static_field": Color(0.48, 0.84, 1.0),
	"toxic_field": Color(0.32, 0.92, 0.22),
	"freeze_field": Color(0.45, 0.82, 1.0),
	"healing_field": Color(0.54, 0.94, 0.75),
}

var ability_id := "static_field"
var owner_peer := 0
var reach := 7.0
var duration := 6.0
var fade_duration := 2.4
var field_tint := Color(0.48, 0.84, 1.0)
var stats: Dictionary = {}
var authoritative := false

var _age := 0.0
var _since_tick := 0.0
var _since_bubble := 0.0
var _inside: Dictionary = {}
var _owner_inside := false
var _material: ShaderMaterial
var _visual: MeshInstance3D


static func create(world: Node, source: OnlinePlayer, id: String,
		at: Vector3, field_stats: Dictionary, tint: Color,
		owns_effects: bool) -> CrawlerFieldVolume:
	if world == null or not at.is_finite():
		return null
	var field := CrawlerFieldVolume.new()
	field.name = "CrawlerField_%s" % id
	field.ability_id = id
	field.owner_peer = source.peer_id if source != null else 0
	field.stats = field_stats.duplicate(true)
	field.reach = maxf(float(field.stats.get("radius",
		field.stats.get("range", CrawlerRules.FIELD_RADIUS))), 1.0)
	field.duration = clampf(float(field.stats.get("duration",
		CrawlerRules.FIELD_DURATION)), 0.4, 40.0)
	field.fade_duration = clampf(float(field.stats.get("fade_duration",
		CrawlerRules.FIELD_FADE)), 0.0, field.duration)
	field.field_tint = tint if tint.a > 0.0 else TINTS.get(id, TINTS["static_field"])
	field.authoritative = owns_effects
	world.add_child(field)
	field.global_position = at
	return field


static func speed_scale_at(anywhere: Node, at: Vector3) -> float:
	return CrawlerMobSense.field_scale(anywhere, at)


static func wash_at(anywhere: Node, at: Vector3) -> Color:
	var wash := Color(0.0, 0.0, 0.0, 0.0)
	if anywhere == null or not anywhere.is_inside_tree() or not at.is_finite():
		return wash
	for node_variant: Variant in anywhere.get_tree().get_nodes_in_group(GROUP):
		var field := node_variant as CrawlerFieldVolume
		if field == null or not field.contains(at, 0.35):
			continue
		var color := field.field_tint
		color.a = field.fade_alpha() * 0.34
		if color.a > wash.a:
			wash = color
	return wash


func _ready() -> void:
	top_level = true
	add_to_group(GROUP)
	set_process(true)
	set_physics_process(true)
	if DisplayServer.get_name() == "headless":
		return
	_material = ShaderMaterial.new()
	_material.shader = IRIS_SHADER
	_material.set_shader_parameter(&"tint", field_tint)
	_material.set_shader_parameter(&"alpha", BASE_ALPHA)
	_material.set_shader_parameter(&"spark", 1.2)
	_material.set_shader_parameter(&"iris", 1.05)
	_material.set_shader_parameter(&"edge_width", 0.24)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 28
	sphere.material = _material
	_visual = MeshInstance3D.new()
	_visual.mesh = sphere
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)


func _process(delta: float) -> void:
	_age += delta
	_draw()
	if _age >= duration:
		queue_free()


func _physics_process(delta: float) -> void:
	_since_bubble += delta
	if _since_bubble >= CrawlerRules.BUBBLE_FIELD_INTERVAL:
		_since_bubble = 0.0
		_emit_bubbles()
	if not authoritative:
		return
	_since_tick += delta
	if _since_tick < TICK_STEP:
		return
	_since_tick -= TICK_STEP
	_tick_inside()


func current_radius() -> float:
	var share := clampf(_age / EXPAND, 0.0, 1.0)
	var eased := 1.0 - (1.0 - share) * (1.0 - share)
	return reach * maxf(eased, 0.04)


func contains(at: Vector3, pad := 0.0) -> bool:
	if not at.is_finite() or remaining() <= 0.0:
		return false
	return at.distance_to(global_position) <= current_radius() + pad


func remaining() -> float:
	return maxf(duration - _age, 0.0)


func fade_alpha() -> float:
	var alpha := BASE_ALPHA
	var fade_start := duration - fade_duration
	if fade_duration > 0.0 and _age > fade_start:
		var share := clampf((_age - fade_start) / fade_duration, 0.0, 1.0)
		alpha = BASE_ALPHA * pow(1.0 - share, 1.35)
	return alpha


func speed_mul() -> float:
	var slow := clampf(float(stats.get("freeze", 0.0)),
		0.0, CrawlerRules.FIELD_FREEZE_MAX)
	if slow <= 0.0:
		return 1.0
	return clampf(1.0 - slow / 100.0, 0.08, 1.0)


func _draw() -> void:
	if _visual == null or _material == null:
		return
	var radius := current_radius()
	if radius > DRAW_LIMIT:
		_visual.visible = false
		return
	_visual.visible = radius > 0.05
	scale = Vector3.ONE * radius
	var alpha := fade_alpha()
	_material.set_shader_parameter(&"tint", field_tint)
	_material.set_shader_parameter(&"alpha", alpha)
	_material.set_shader_parameter(&"spark", 0.85 + alpha * 0.7)


func _tick_inside() -> void:
	var owner := _owner_player()
	if owner == null or not owner.is_inside_tree():
		return
	_tick_owner(owner)
	var seen: Dictionary = {}
	for combatant in CombatantSense.collect(self, owner):
		if not combatant.has_method(&"apply_damage"):
			continue
		var point := CombatantSense.point_of(combatant)
		var bounds := CombatantSense.radius_of(combatant)
		var key := combatant.get_instance_id()
		if not contains(point, bounds):
			_inside.erase(key)
			continue
		seen[key] = true
		var first := not _inside.has(key)
		_inside[key] = true
		_affect(owner, combatant, point, bounds, first)
	for key_variant: Variant in _inside.keys():
		if not seen.has(key_variant):
			_inside.erase(key_variant)


func _affect(owner: OnlinePlayer, combatant: Node, at: Vector3,
		bounds: float, first: bool) -> void:
	var hit := _make_hit(owner, combatant, at, bounds, first)
	if hit == null:
		return
	combatant.call(&"apply_damage", hit.resolved_for(combatant))


func _make_hit(owner: OnlinePlayer, combatant: Node, at: Vector3,
		bounds: float, first: bool) -> DamageHit:
	var amount := 0.0
	var element := maxf(float(stats.get("element", 1.0)), 0.0)
	match ability_id:
		"static_field":
			amount = maxf(float(stats.get("damage",
				CrawlerRules.FIELD_STATIC_DAMAGE)), 0.0)
			if not first:
				amount *= TICK_STEP
		"toxic_field":
			amount = 0.0
		"freeze_field":
			amount = maxf(float(stats.get("damage", 0.0)) * element, 0.0)
			if not first:
				amount *= TICK_STEP
		"healing_field":
			amount = 0.0
		_:
			return null
	var reach_hit := maxf(at.distance_to(global_position) + bounds + 0.4, 0.4)
	var hit := DamageHit.impact(global_position, reach_hit, amount)
	hit.faction = DamageHit.Faction.PLAYER
	hit.ability_id = ability_id
	hit.affects_flora = false
	CrawlerElements.stamp(hit, owner, ability_id, stats, true, TICK_STEP)
	if amount <= 0.0 and hit.status.is_empty():
		return null
	hit.set_source(owner, owner.peer_id)
	return hit


func _tick_owner(owner: OnlinePlayer) -> void:
	if ability_id != "healing_field" or owner == null:
		return
	if owner.has_method(&"is_alive") and not owner.is_alive():
		_owner_inside = false
		return
	var point := owner.global_position
	if owner.has_method(&"combat_position"):
		point = owner.combat_position()
	var bounds := 0.4
	if owner.has_method(&"combat_radius"):
		bounds = float(owner.combat_radius())
	if not contains(point, bounds):
		_owner_inside = false
		return
	var first := not _owner_inside
	_owner_inside = true
	var amount := maxf(float(stats.get("heal", CrawlerRules.FIELD_HEAL)), 0.0)
	if not first:
		amount *= TICK_STEP
	if amount <= 0.0 or not owner.has_method(&"apply_heal"):
		return
	owner.apply_heal(amount)


func _emit_bubbles() -> void:
	var owner := _owner_player()
	if owner == null:
		return
	CrawlerBubbles.emit_field(owner, ability_id, global_position, current_radius())
	CrawlerLingers.emit_field(owner, ability_id, global_position, current_radius())


func _owner_player() -> OnlinePlayer:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(&"network_players"):
		var player := node as OnlinePlayer
		if player != null and player.peer_id == owner_peer:
			return player
	var parent := get_parent()
	if parent != null:
		for child: Node in parent.get_children():
			var player := child as OnlinePlayer
			if player != null and player.peer_id == owner_peer:
				return player
	return null
