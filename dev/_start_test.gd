extends Node

## Presses New Game the way a player does and watches the whole start sequence.
##
##     & $godot --path . dev/_start_test.tscn
##
## The other harnesses all begin with a session already open, because that is
## where the game is. This one begins where the player does — on the title
## screen, with the world rendering behind it and nothing spawned — so it is the
## only place the pre-game warm-up can be tested at all.
##
## What it is checking is a sequence rather than a picture: that choosing a mode
## runs the warm-up behind a small red/green bar (not a full-screen card), that
## its real draw geometry exists only in an offscreen viewport and never on the
## menu camera, that the warm-up takes that geometry away again, and that the
## session then opens and hands the player the camera.

const WORLD := preload("res://game/world.tscn")

var _world: GameWorld
var _home: HomeScreen
var _handover_frames := 0
var _handover_overlapped := false
var _handover_went_blank := false


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	# Left idle, unlike the other harnesses: idle is what makes the world open a
	# home screen instead of spawning into itself.
	NetworkManager.state = NetworkManager.SessionState.IDLE
	_world = WORLD.instantiate() as GameWorld
	add_child(_world)
	await _wait(30)

	_home = _world.find_child("HomeScreen", false, false) as HomeScreen
	if _home == null:
		push_error("start_test: the world opened without a home screen")
		get_tree().quit(1)
		return
	await _run()
	get_tree().quit()


func _run() -> void:
	var camera := _home.find_child("MenuCamera", true, false) as Camera3D
	var began := Time.get_ticks_msec()
	_home.start_new_game("story")

	# Watch the invisible warm-up and the session in one pass. It only takes a
	# fraction of a second on a warm shader cache, so looking for it after waiting
	# for the player would be looking for a node that has correctly gone away.
	var saw_warmup := false
	var most_offscreen_geometry := 0
	var main_camera_geometry := 0
	var saw_loading_bar := false
	var loading_bar_too_big := false
	var player: OnlinePlayer = null
	while player == null and Time.get_ticks_msec() - began < 30000:
		await _wait(1)
		if is_instance_valid(_home):
			var bar := _home.find_child("StartLoadingBar", true, false) as Control
			if bar != null and bar.visible:
				saw_loading_bar = true
				if bar.size.x > 360.0 or bar.size.y > 22.0:
					loading_bar_too_big = true
		main_camera_geometry = maxi(main_camera_geometry, _camera_geometry(camera))
		var warmup := _world.find_child("WorldWarmup", true, false) as WorldWarmup
		if warmup != null:
			saw_warmup = true
			most_offscreen_geometry = maxi(most_offscreen_geometry,
				_warm_geometry(warmup))
		player = _world.local_player()
		_observe_handover_bodies(player)
	print("start_test: warm-up offscreen=%d, loading bar=%s, menu-camera=%d" % [
		most_offscreen_geometry, saw_loading_bar, main_camera_geometry])
	if not saw_warmup or most_offscreen_geometry == 0:
		print("start_test: FAIL  nothing was warmed up")
		return
	if not saw_loading_bar:
		print("start_test: FAIL  warm-up never showed the start loading bar")
		return
	if loading_bar_too_big:
		print("start_test: FAIL  the start loading bar was a full-screen card")
		return
	if main_camera_geometry != 0 or _camera_geometry(camera) != 0:
		print("start_test: FAIL  warm-up geometry entered the menu camera")
		return

	# The session, the body, and the camera changing hands.
	if player == null:
		print("start_test: FAIL  no player spawned after the warm-up")
		return
	print("start_test: session opened and body arrived %d ms in" % [
		Time.get_ticks_msec() - began])

	while is_instance_valid(_home) and Time.get_ticks_msec() - began < 30000:
		await _wait(1)
		_observe_handover_bodies(player)
	if is_instance_valid(_home):
		print("start_test: FAIL  the home screen never handed over")
		return
	print("start_test: handover body frames=%d overlap=%s blank=%s" % [
		_handover_frames, _handover_overlapped, _handover_went_blank])
	if _handover_frames == 0 or _handover_overlapped or _handover_went_blank:
		print("start_test: FAIL  preview/player handover did not render exactly one body")
		return
	print("start_test: handover complete %d ms after New Game" % [
		Time.get_ticks_msec() - began])
	print("start_test: player camera current=%s controls=%s" % [
		player.camera.current, player.controls_enabled])


func _warm_geometry(warmup: WorldWarmup) -> int:
	return warmup.find_children("*", "MeshInstance3D", true, false).size() \
		+ warmup.find_children("*", "MultiMeshInstance3D", true, false).size()


func _camera_geometry(camera: Camera3D) -> int:
	if camera == null or not is_instance_valid(camera):
		return 0
	var found := 0
	for child in camera.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D:
			found += 1
	return found


## The preview and player intentionally share a transform, so showing both is
## not harmless duplication: their depth values tie and black patches flicker
## between the two surfaces. The handover must atomically exchange visibility.
func _observe_handover_bodies(player: OnlinePlayer) -> void:
	if player == null:
		return
	_handover_frames += 1
	var visible_bodies := 1 if player.visible else 0
	if is_instance_valid(_home):
		var preview := _home.find_child(
			"PreviewCharacter", false, false) as Node3D
		if preview != null and preview.visible:
			visible_bodies += 1
	_handover_overlapped = _handover_overlapped or visible_bodies > 1
	_handover_went_blank = _handover_went_blank or visible_bodies == 0


func _wait(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
