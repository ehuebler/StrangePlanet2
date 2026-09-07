class_name LightBolt
extends Ability

## Hold-fire stream of small eye-cast energy bolts.


var _next_left := false
var _requested_left := false
var _request_sequence := 0
var _release_requested := false


func _press() -> bool:
	_release_requested = false
	return _fire_next()


func _fire_next() -> bool:
	if definition == null or definition.projectile_type \
			!= AbilityDefinition.ProjectileType.ENERGY_BOLT:
		return false
	var eyes := player.eye_points()
	if eyes.size() < 2:
		return false
	_requested_left = _next_left
	var socket: Vector3 = eyes[0] if _requested_left else eyes[1]
	var along := player.aim_direction(socket)
	var from := CrawlerReach.shift(socket, along, stats)
	var variant := 1 if _requested_left else 0
	if player.uses_float_pose():
		variant |= 2
	_request_sequence = player.fire_ability_projectile(
		ability_id, from, along, variant)
	return _request_sequence > 0


func _tick(_delta: float) -> void:
	if _request_sequence > 0:
		var state := player.ability_projectile_request_state(_request_sequence)
		if state == OnlinePlayer.ProjectileRequestState.PENDING:
			return
		if state == OnlinePlayer.ProjectileRequestState.REJECTED:
			cancel()
			return
		_accept_request()
		if _release_requested:
			release()
		return
	if _cooldown_left <= 0.0 and not _fire_next():
		cancel()


func release() -> void:
	if not is_held():
		return
	_release_requested = true
	if _request_sequence > 0 and player != null:
		var state := player.ability_projectile_request_state(_request_sequence)
		if state == OnlinePlayer.ProjectileRequestState.PENDING:
			return
		if state == OnlinePlayer.ProjectileRequestState.REJECTED:
			cancel()
			return
		_accept_request()
	var cadence_left := _cooldown_left
	super()
	_cooldown_left = cadence_left


func _accept_request() -> void:
	_next_left = not _requested_left
	_request_sequence = 0
	_cooldown_left = cooldown()


func _release() -> void:
	_request_sequence = 0
	_release_requested = false
