class_name Kame
extends LaserEyes

## Both arms forward, one thick beam from the hands.
##
## One committed burst: the beam stays on for the authored cook even if the
## button comes up, then the cooldown starts. It does not pulse-repeat the way
## [LaserEyes] does. While it is lit the body is rooted, look still steers the
## beam, and look speed is scaled down so the sweep is heavy rather than twitchy.

const COLOR := Color(0.24, 0.71, 1.0)

var _commit := false


func _origin_points() -> Array[Vector3]:
	if player == null:
		return super._origin_points()
	var mid := player.merged_hand_point()
	return [mid, mid]


func _beam_tint() -> Color:
	if definition != null:
		return definition.tint
	return COLOR


func _beam_invert() -> bool:
	return true


func _follow_mode() -> int:
	return LaserBeams.FOLLOW_HANDS_MERGED


func _damage_hz() -> float:
	return maxf(stat("damage_hz", CrawlerRules.KAME_DAMAGE_HZ), 1.0)


func _beam_width() -> float:
	return maxf(_beam_radius() / LaserBeams.RADIUS, 0.35)


func _beam_radius() -> float:
	return maxf(stat("radius", CrawlerRules.KAME_RADIUS), 0.05)


func _scar_scale() -> float:
	return maxf(_beam_radius() / SCAR_RADIUS, 0.05)


func _pulse_mode() -> bool:
	return false


func _press() -> bool:
	if not super._press():
		_commit = false
		return false
	_commit = true
	return true


func release() -> void:
	if _commit and is_held() and _left > 0.0:
		return
	_commit = false
	super()


func _on_beam_lit() -> void:
	_hold_pose(true)


func _on_beam_dark() -> void:
	_commit = false
	_hold_pose(false)
	super._on_beam_dark()


func _tick(delta: float) -> void:
	if player != null and player.submerged_share() > 0.0:
		_commit = false
	super._tick(delta)
	if _held and _is_beam_lit():
		_hold_pose(true)


func _hold_pose(on: bool) -> void:
	if player == null:
		return
	if not on:
		player.clear_ability_animation()
		player.set_beam_root(false)
		return
	var clip := &"Kame"
	if definition != null and not definition.animation.is_empty():
		clip = definition.animation
	player.play_ability_animation(clip, maxf(_left, 0.28))
	player.set_beam_root(true, CrawlerRules.KAME_LOOK_SCALE)


func _is_beam_lit() -> bool:
	return _left > 0.0
