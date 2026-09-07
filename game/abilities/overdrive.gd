class_name Overdrive
extends Ability

## Short roar pose and orange wave, then a timed stat buff. Mods seated on this
## card are borrowed by the other equipped abilities for the duration.

const WAVE := preload("res://game/abilities/player_roar_wave.gd")
const TINT := Color(0.95, 0.55, 0.12)

var _elapsed := 0.0
var _origin := Vector3.ZERO
var _wave: PlayerRoarWave


func _press() -> bool:
	if player == null:
		return false
	_elapsed = 0.0
	_origin = _mouth()
	player.begin_roar(stat("animation_duration", CrawlerRules.ROAR_ANIMATION))
	_ensure_wave()
	player.begin_overdrive(stats, host_card())
	return true


func _tick(delta: float) -> void:
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
	if _elapsed >= windup + expand:
		_clear_wave()
		release()


func release() -> void:
	if is_held() and _elapsed < CrawlerRules.ROAR_WINDUP + CrawlerRules.ROAR_EXPAND:
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


func _ensure_wave() -> void:
	if player == null:
		return
	if not is_instance_valid(_wave):
		_wave = WAVE.new()
		_wave.name = "PlayerOverdriveWave"
		player.add_child(_wave)
	_wave.set_color(TINT)
	_wave.clear()


func _clear_wave() -> void:
	if is_instance_valid(_wave):
		_wave.clear()
