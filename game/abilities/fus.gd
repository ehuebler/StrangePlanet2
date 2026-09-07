class_name Fus
extends Ability

## Roar pose, then a travelling green force cone. Little chip, huge shove.


var _elapsed := 0.0
var _fired := false
var _request_sequence := 0


func _press() -> bool:
	if player == null or definition == null \
			or definition.projectile_type \
				!= AbilityDefinition.ProjectileType.ENERGY_CONE:
		return false
	_elapsed = 0.0
	_fired = false
	_request_sequence = 0
	player.begin_roar(stat("animation_duration", CrawlerRules.ROAR_ANIMATION))
	return true


func _tick(delta: float) -> void:
	_elapsed += delta
	if not _fired:
		if _elapsed < CrawlerRules.ROAR_WINDUP:
			return
		_fired = true
		_launch()
		if _request_sequence <= 0:
			cancel()
			return
	if _request_sequence > 0:
		var state := player.ability_projectile_request_state(_request_sequence)
		if state == OnlinePlayer.ProjectileRequestState.PENDING:
			return
		if state == OnlinePlayer.ProjectileRequestState.REJECTED:
			cancel()
			return
		_request_sequence = 0
	if _elapsed >= stat("animation_duration", CrawlerRules.ROAR_ANIMATION):
		release()


func release() -> void:
	if is_held() and (not _fired or _request_sequence > 0
			or _elapsed < CrawlerRules.ROAR_WINDUP):
		return
	super()


func _release() -> void:
	_request_sequence = 0


func _launch() -> void:
	var from := _mouth()
	var along := player.aim_direction(from)
	from = CrawlerReach.shift(from, along, stats)
	_request_sequence = player.fire_ability_projectile(ability_id, from, along, 0)


func _mouth() -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.has_method(&"mouth_point"):
		return player.mouth_point()
	var up := player.up_direction if player.up_direction.length_squared() > 0.01 \
		else Vector3.UP
	if player.has_method(&"combat_position"):
		return player.combat_position() + up * 0.22
	return player.global_position + up * 1.4
