class_name CrawlerBossCutscene
extends Node

## Pans a local camera to the tree, holds, then pans home. Solo play
## stays paused until the return finishes. Space skips the whole sting.

signal arrived
signal finished

const SKIP_HOLD := 0.22
const LERP := 0.85
const HOME := 0.70

enum Stage { IN, HOLD, OUT, DONE }

var _player: OnlinePlayer
var _cam: Camera3D
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _age := 0.0
var _hold := 0.0
var _hold_left := -1.0
var _stage: Stage = Stage.DONE
var _paused_world := false
var _done := false
var _live := false
var _arrived := false


func _init() -> void:
	name = "CrawlerBossCutscene"
	process_mode = Node.PROCESS_MODE_ALWAYS


func play(
		player: OnlinePlayer,
		look_from: Vector3,
		look_at: Vector3,
		pause_world: bool,
		fov := 70.0,
		auto_return := -1.0,
		up := Vector3.ZERO
	) -> void:
	_player = player
	_paused_world = pause_world and not CrawlerRules.coop()
	_age = 0.0
	_hold = 0.0
	_hold_left = auto_return
	_done = false
	_live = true
	_arrived = false
	_stage = Stage.IN
	if _paused_world:
		var tree := get_tree()
		if tree != null:
			tree.paused = true
	_set_hud(true)
	if player != null and player.camera != null \
			and look_from.is_finite() and look_at.is_finite() \
			and look_from.distance_squared_to(look_at) > 0.04:
		_from = player.camera.global_transform
		_cam = Camera3D.new()
		_cam.name = "GivingTreeCam"
		_cam.current = true
		_cam.fov = clampf(fov, 40.0, 90.0)
		_cam.far = maxf(player.camera.far, 400.0)
		add_child(_cam)
		_cam.global_transform = _from
		var along := up if up.length_squared() > 0.0001 else _up_for(look_from, player)
		if along.length_squared() < 0.0001:
			along = Vector3.UP
		along = along.normalized()
		var toward := look_at - look_from
		if toward.length_squared() < 0.0001:
			toward = -along
		_to = Transform3D(Basis.looking_at(toward, along), look_from)
	else:
		_arrived = true
		_stage = Stage.HOLD
		arrived.emit()
	_set_controls(false)


func go_home() -> void:
	if not _live or _done or _stage == Stage.OUT:
		return
	if _cam == null:
		_finish()
		return
	_stage = Stage.OUT
	_age = 0.0
	_from = _cam.global_transform
	if _player != null and _player.camera != null:
		_to = _player.camera.global_transform


func skip() -> void:
	_finish()


func is_playing() -> bool:
	return _live and not _done


func has_arrived() -> bool:
	return _arrived


func age() -> float:
	return _age


func _process(delta: float) -> void:
	if not _live or _done:
		return
	var step := maxf(delta, 0.0)
	if Input.is_physical_key_pressed(KEY_SPACE):
		_hold += step
		if _hold >= SKIP_HOLD:
			_finish()
			return
	else:
		_hold = 0.0
	match _stage:
		Stage.IN:
			_age += step
			_lerp_cam(_age / LERP)
			if _age >= LERP:
				_arrive()
		Stage.HOLD:
			if _cam != null:
				_cam.global_transform = _to
			if _hold_left >= 0.0:
				_hold_left -= step
				if _hold_left <= 0.0:
					go_home()
		Stage.OUT:
			_age += step
			_lerp_cam(_age / HOME)
			if _age >= HOME:
				_finish()


func _arrive() -> void:
	if _arrived:
		return
	_arrived = true
	_stage = Stage.HOLD
	if _cam != null:
		_cam.global_transform = _to
	arrived.emit()


func _lerp_cam(blend: float) -> void:
	if _cam == null:
		return
	var t := clampf(blend, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	_cam.global_transform = _from.interpolate_with(_to, t)


func _finish() -> void:
	if _done:
		return
	_done = true
	_live = false
	_stage = Stage.DONE
	if _cam != null:
		_cam.current = false
		_cam.queue_free()
		_cam = null
	if _paused_world:
		var tree := get_tree()
		if tree != null:
			tree.paused = false
		_paused_world = false
	_set_hud(false)
	_set_controls(true)
	finished.emit()


func _up_for(look_from: Vector3, player: OnlinePlayer) -> Vector3:
	if look_from.length_squared() > 0.01:
		return look_from.normalized()
	if player != null and player.is_inside_tree() \
			and player.global_position.length_squared() > 0.01:
		return player.global_position.normalized()
	return Vector3.UP


func _set_controls(on: bool) -> void:
	if _player != null:
		_player.controls_enabled = on


func _set_hud(cutscene: bool) -> void:
	if _player == null:
		return
	if _player.has_method(&"set_cutscene_hud"):
		_player.call(&"set_cutscene_hud", cutscene)
		return
	var hud := _player.combat_hud()
	if hud != null and hud.has_method(&"set_cutscene"):
		hud.call(&"set_cutscene", cutscene)


func _exit_tree() -> void:
	if _live and not _done:
		_finish()
