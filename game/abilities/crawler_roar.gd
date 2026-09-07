class_name CrawlerRoar
extends Ability

## Shared expanding roar shockwave. The four shop ids pick damage, knockback,
## and the status the front applies.

const WAVE := preload("res://game/abilities/player_roar_wave.gd")
const TINTS := {
	"roar": Color(0.95, 0.55, 0.12),
	"toxic_blast": Color(0.32, 0.92, 0.22),
	"charming_aura": Color(0.95, 0.38, 0.72),
	"freeze_blast": Color(0.45, 0.82, 1.0),
}

var _elapsed := 0.0
var _origin := Vector3.ZERO
var _struck: Dictionary = {}
var _wave: PlayerRoarWave
var _bubbles_cast := false
var _echoes_left := 0
var _echo_wait := 0.0


func _press() -> bool:
	if player == null:
		return false
	_echoes_left = CrawlerMulti.extras(stats)
	_echo_wait = 0.0
	_start_wave()
	return true


func _start_wave() -> void:
	_elapsed = 0.0
	_struck.clear()
	_bubbles_cast = false
	_origin = _mouth()
	player.begin_roar(stat("animation_duration", CrawlerRules.ROAR_ANIMATION))
	_ensure_wave()


func _tick(delta: float) -> void:
	if _echo_wait > 0.0:
		_echo_wait = maxf(_echo_wait - delta, 0.0)
		if _echo_wait > 0.0:
			return
		if _echoes_left > 0:
			_echoes_left -= 1
			_start_wave()
		else:
			release()
		return
	_elapsed += delta
	_origin = _mouth()
	var windup := CrawlerRules.ROAR_WINDUP
	var expand := CrawlerRules.ROAR_EXPAND
	if _elapsed < windup:
		if is_instance_valid(_wave):
			_wave.clear()
		return
	var reach := maxf(stat("range", CrawlerRules.ROAR_RADIUS), 1.0)
	var share := clampf((_elapsed - windup) / expand, 0.0, 1.0)
	var radius := reach * share
	if is_instance_valid(_wave):
		_wave.set_wave(_origin, radius)
	if not _bubbles_cast:
		_bubbles_cast = true
		CrawlerBubbles.emit_shockwave(player, ability_id, _origin, reach)
		CrawlerLingers.emit_shockwave(player, ability_id, _origin, reach)
	_strike(radius)
	if _elapsed >= windup + expand:
		_clear_wave()
		if _echoes_left > 0:
			_echo_wait = CrawlerRules.MULTI_ECHO_GAP
			return
		release()


func release() -> void:
	if is_held() and (_echoes_left > 0 or _echo_wait > 0.0
			or _elapsed < CrawlerRules.ROAR_WINDUP + CrawlerRules.ROAR_EXPAND):
		return
	_clear_wave()
	super()


func _release() -> void:
	_clear_wave()


func _mouth() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var up := player.up_direction if player.up_direction.length_squared() > 0.01 \
		else Vector3.UP
	if player.has_method(&"combat_position"):
		return player.combat_position() + up * 0.22
	return player.global_position + up * 1.4


func _element() -> float:
	if player != null and player.has_method(&"crawler_element_scale"):
		return maxf(float(player.call(&"crawler_element_scale")), 0.0)
	return 1.0


func _effect_duration() -> float:
	if ability_id == "roar":
		return 0.0
	var held := maxf(stat("duration", CrawlerRules.ROAR_DURATION), 0.0)
	if ability_id == "toxic_blast" or ability_id == "freeze_blast":
		return held * _element()
	return held


func _hit_amount() -> float:
	match ability_id:
		"roar":
			return maxf(stat("damage", CrawlerRules.ROAR_DAMAGE), 0.0)
		"freeze_blast":
			return maxf(stat("damage", 0.0) * _element(), 0.0)
		_:
			return 0.0


func _dot() -> float:
	if ability_id != "toxic_blast":
		return 0.0
	return maxf(stat("damage", CrawlerRules.ROAR_TOXIC_DAMAGE) * _element(), 0.0)


func _status_id() -> StringName:
	match ability_id:
		"toxic_blast":
			return CombatStatuses.POISON
		"charming_aura":
			return CombatStatuses.CHARM
		"freeze_blast":
			return CombatStatuses.FREEZE
		_:
			return &""


func _strike(radius: float) -> void:
	if player == null or not player.is_inside_tree() or not _is_host():
		return
	for node_variant: Variant in player.get_tree().get_nodes_in_group(
			DamageHit.COMBATANT_GROUP):
		var combatant := node_variant as Node
		if combatant == null or combatant == player:
			continue
		if not combatant.has_method(&"apply_damage") \
				or not combatant.has_method(&"combat_faction"):
			continue
		if int(combatant.call(&"combat_faction")) != DamageHit.Faction.ENEMY:
			continue
		if combatant.has_method(&"is_alive") \
				and not bool(combatant.call(&"is_alive")):
			continue
		var key := combatant.get_instance_id()
		if _struck.has(key):
			continue
		var point := _origin
		if combatant.has_method(&"combat_position"):
			point = combatant.call(&"combat_position")
		elif combatant is Node3D:
			point = (combatant as Node3D).global_position
		var bounds := 0.4
		if combatant.has_method(&"combat_radius"):
			bounds = float(combatant.call(&"combat_radius"))
		if point.distance_to(_origin) > radius + bounds:
			continue
		_struck[key] = true
		var delivered := _make_hit(point, bounds)
		combatant.call(&"apply_damage", delivered.resolved_for(combatant))


func _make_hit(at: Vector3, bounds: float) -> DamageHit:
	var reach := maxf(at.distance_to(_origin) + bounds + 0.4, 0.4)
	var hit := DamageHit.impact(_origin, reach, _hit_amount())
	hit.faction = DamageHit.Faction.PLAYER
	hit.ability_id = ability_id
	hit.affects_flora = false
	var knockback := maxf(stat("knockback", 0.0), 0.0)
	if knockback > 0.0:
		hit.reaction = DamageHit.Reaction.KNOCKBACK
		hit.radial_impulse = knockback
		hit.radial_lift = knockback * 0.22
	CrawlerElements.stamp(hit, player, ability_id, stats)
	if player != null:
		hit.set_source(player)
	return hit


func _ensure_wave() -> void:
	if player == null:
		return
	if not is_instance_valid(_wave):
		_wave = WAVE.new()
		_wave.name = "PlayerRoarWave"
		player.add_child(_wave)
	_wave.set_color(TINTS.get(ability_id, TINTS["roar"]))
	_wave.clear()


func _clear_wave() -> void:
	if is_instance_valid(_wave):
		_wave.clear()


func _is_host() -> bool:
	if player == null:
		return false
	return not player.multiplayer.has_multiplayer_peer() \
		or player.multiplayer.is_server()
