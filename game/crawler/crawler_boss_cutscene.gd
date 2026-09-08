class_name CrawlerBossCutscene
extends Node

## Pans a local camera to the tree, optionally pauses solo play, and
## skips when Space is held.

signal finished

const SKIP_HOLD := 0.22
const LERP := 0.55
const HOLD := 2.35

var _player: OnlinePlayer
var _cam: Camera3D
var _from := Transform3D.IDENTITY
var _to := Transform3D.IDENTITY
var _age := 0.0
var _hold := 0.0
var _paused_world := false
var _done := false
var _live := false


func _init() -> void:
	name = "CrawlerBossCutscene"
	process_mode = Node.PROCESS_MODE_ALWAYS


func play(player: OnlinePlayer, look_from: Vector3, look_at: Vector3, pause_world: bool) -> void:
	_player = player
	_paused_world = pause_world and not CrawlerRules.coop()
	_age = 0.0
	_hold = 0.0
	_done = false
	_live = true
	if _paused_world:
		var tree := get_tree()
		if tree != null:
			tree.paused = true
	_set_hud(true)
	if player != null and player.camera != null \
			and look_from.is_finite() and look_at.is_finite():
		_from = player.camera.global_transform
		_cam = Camera3D.new()
		_cam.name = "GivingTreeCam"
		_cam.current = true
		add_child(_cam)
		_cam.global_transform = _from
		var up := look_from.normalized() if look_from.length_squared() > 0.01 \
			else Vector3.UP
		if player.is_inside_tree() and player.global_position.length_squared() > 0.01:
			up = player.global_position.normalized()
		_to = Transform3D(Basis.looking_at(look_at - look_from, up), look_from)
	_set_controls(false)


func skip() -> void:
	_finish()


func is_playing() -> bool:
	return _live and not _done


func age() -> float:
	return _age


func _process(delta: float) -> void:
	if not _live or _done:
		return
	_age += maxf(delta, 0.0)
	if Input.is_physical_key_pressed(KEY_SPACE):
		_hold += delta
		if _hold >= SKIP_HOLD:
			_finish()
			return
	else:
		_hold = 0.0
	if _cam != null:
		var t := clampf(_age / LERP, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		_cam.global_transform = _from.interpolate_with(_to, t)
	if _age >= HOLD:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	_live = false
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
