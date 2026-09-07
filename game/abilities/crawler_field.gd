class_name CrawlerField
extends Ability

## Shared expanding field. The three shop ids pick shock, poison, or slow.
## Planting takes a stand-still cast; moving far or breaking the pose cancels it.

var _elapsed := 0.0
var _echoes_left := 0
var _echo_wait := 0.0
var _casting := false
var _planted := false
var _cast_from := Vector3.ZERO


func _press() -> bool:
	if player == null or not CrawlerRules.is_field_ability(ability_id):
		return false
	_elapsed = 0.0
	_echo_wait = 0.0
	_echoes_left = CrawlerMulti.extras(stats)
	_planted = false
	if _cast_time() <= 0.001:
		return _plant()
	_casting = true
	_cast_from = player.global_position
	_hold_cast(true)
	return true


func _tick(delta: float) -> void:
	if _casting:
		if _broke_stance():
			cancel()
			return
		_elapsed += delta
		_hold_cast(true)
		if _elapsed >= _cast_time() and not _plant():
			cancel()
		return
	if _echo_wait > 0.0:
		_echo_wait = maxf(_echo_wait - delta, 0.0)
		if _echo_wait > 0.0:
			return
		if _echoes_left > 0 and player.spawn_ability_field(ability_id):
			_echoes_left -= 1
			_elapsed = 0.0
			return
		release()
		return
	_elapsed += delta
	if _elapsed >= stat("animation_duration", CrawlerRules.FIELD_ANIMATION):
		if _echoes_left > 0:
			_echo_wait = CrawlerRules.MULTI_ECHO_GAP
			return
		release()


func release() -> void:
	if is_held() and (_casting or _echoes_left > 0 or _echo_wait > 0.0
			or _elapsed < stat("animation_duration", CrawlerRules.FIELD_ANIMATION)):
		return
	super()


func _release() -> void:
	_hold_cast(false)
	if _casting and not _planted:
		refund_shot()
	_casting = false


func _can_continue_when_attack_blocked() -> bool:
	return _planted or _echoes_left > 0 or _echo_wait > 0.0


func _cast_time() -> float:
	var trim := 0.0
	if player != null and player.has_method(&"crawler_cast_trim"):
		trim = float(player.call(&"crawler_cast_trim"))
	return CrawlerRules.field_cast_time(
		stat("cast", CrawlerRules.FIELD_CAST), trim)


func _plant() -> bool:
	_casting = false
	_hold_cast(false)
	if player == null or not player.spawn_ability_field(ability_id):
		return false
	_planted = true
	_elapsed = 0.0
	return true


func _broke_stance() -> bool:
	if player == null or not _cast_from.is_finite():
		return true
	if player.juke_active():
		return true
	var at := player.global_position
	if not at.is_finite():
		return true
	return at.distance_to(_cast_from) > CrawlerRules.FIELD_CAST_BREAK


func _hold_cast(on: bool) -> void:
	if player == null:
		return
	if not on:
		player.set_field_cast(false)
		if not _planted:
			player.clear_ability_animation()
		return
	player.set_field_cast(true)
	var clip := &"FieldCast"
	if definition != null and not definition.animation.is_empty():
		clip = definition.animation
	player.play_ability_animation(clip, maxf(_cast_time() - _elapsed, 0.12))
