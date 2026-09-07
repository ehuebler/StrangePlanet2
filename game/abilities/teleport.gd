class_name Teleport
extends Ability

## One overhand throw. The glowing marker owns no damage; landing warps you.


var _request_sequence := 0


func _press() -> bool:
	if definition == null or definition.projectile_type \
			!= AbilityDefinition.ProjectileType.TELEPORT_ORB:
		return false
	var hand := player.hand_point(false)
	var along := player.aim_direction(hand)
	var from := CrawlerReach.shift(hand, along, stats)
	var variant := 2 if player.uses_float_pose() else 0
	_request_sequence = player.fire_ability_projectile(
		ability_id, from, along, variant)
	return _request_sequence > 0


func _tick(_delta: float) -> void:
	if _request_sequence <= 0:
		cancel()
		return
	var state := player.ability_projectile_request_state(_request_sequence)
	if state == OnlinePlayer.ProjectileRequestState.PENDING:
		return
	if state == OnlinePlayer.ProjectileRequestState.REJECTED:
		cancel()
		return
	_request_sequence = 0
	release()


func _release() -> void:
	_request_sequence = 0
