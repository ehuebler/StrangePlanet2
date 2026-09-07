class_name HeroPunch
extends Ability

## Close-range jabs that swap hands the way Starfire swaps throws.


var _next_left := false
var _release_requested := false


func _press() -> bool:
	_release_requested = false
	return _punch_next()


func _punch_next() -> bool:
	if player == null or definition == null:
		return false
	if not player.fire_hero_punch(ability_id, _next_left):
		return false
	_next_left = not _next_left
	_cooldown_left = cooldown()
	return true


func _tick(_delta: float) -> void:
	if _release_requested:
		release()
		return
	if _cooldown_left <= 0.0 and not _punch_next():
		cancel()


func release() -> void:
	if not is_held():
		return
	_release_requested = true
	var cadence_left := _cooldown_left
	super()
	_cooldown_left = cadence_left


func _release() -> void:
	_release_requested = false
