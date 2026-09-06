extends Node

## Arms the player and photographs every hold, the swing, and a shot in flight.
##
## Run it from the project root:
##
##     & $godot --path . dev/_weapon_test.tscn
##
## As well as the shots it measures the grip, which is the part that cannot be
## judged by eye: whether the blade really points up, whether the support hand is
## on the weapon rather than waving beside it, and whether a shot leaves the muzzle
## along the crosshair. Shots land in dev/captures/.

const WORLD := preload("res://game/world.tscn")
const SHOT_DIR := "res://dev/captures/"
const SETTINGS_PATH := "user://settings.cfg"

var _player: OnlinePlayer
var _review: Camera3D
var _failures := 0
var _ability_events: Array[int] = []
var _settings_existed := false
var _settings_bytes := PackedByteArray()
## Bone poses read off the skeleton are a frame behind the modifier that moved
## them, so the hands are measured through attachments, which are not.
var _hand_probes: Dictionary = {}
## The landing site's frame, which every position in this file is measured in.
## The world's origin is the planet's centre now — 8 km underground — so a bare
## world coordinate puts the player inside the core.
var _ground := Transform3D.IDENTITY


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_settings()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players.clear()
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	# The world opens the home screen and spawns nobody while the session reads as
	# idle, so the state has to say "in game" before it comes up.
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	add_child(WORLD.instantiate())
	for _frame in 10:
		await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("network_players") as OnlinePlayer
	var site := get_tree().current_scene.find_child("LandingSite", true, false) as Node3D
	if _player == null or site == null:
		_expect(false, "player=%s site=%s" % [_player, site])
		await _finish()
		return
	_ground = site.global_transform
	_review = Camera3D.new()
	_review.fov = 38.0
	add_child(_review)
	_add_hand_probes()
	await _run()
	await _finish()


func _run() -> void:
	# Out on clear grass, and in third person: the body is drawn as shadow only
	# while the player's own camera is inside its head, whatever camera is looking.
	_place(Vector3(11.0, 0.4, 11.0), PI)
	_player._camera_mode = 1
	await _wait(40)

	await _arm_from_backpack()
	await _selection()
	await _ability_routing()
	await _sword()
	await _walking()
	await _rifle()
	await _first_person()


## Number keys reach every slot; the wheel only stops on the filled ones.
func _selection() -> void:
	_player.select_weapon(0)
	await _wait(10)
	var report := "1:%s" % _player.held_item()
	_expect(_player.held_item() == "sword", "slot 1 draws the sword")
	_player.select_weapon(1)
	await _wait(10)
	report += "  2(empty):'%s'" % _player.held_item()
	_expect(_player.held_item().is_empty() and _player.is_holstered(),
		"empty slot 2 holsters")
	_player._cycle_weapon(1)
	await _wait(10)
	report += "  wheel up:%s" % _player.held_item()
	_expect(_player.held_item() == "laser_rifle",
		"wheel skips forward over empty slot 2")
	_player._cycle_weapon(1)
	await _wait(10)
	report += "  again:%s" % _player.held_item()
	_expect(_player.held_item() == "sword", "wheel wraps to slot 1")
	_player._cycle_weapon(-1)
	await _wait(10)
	report += "  wheel down:%s" % _player.held_item()
	_expect(_player.held_item() == "laser_rifle",
		"reverse wheel wraps to slot 3")
	_report("selection", report)

	_player.select_weapon(0)
	await _wait(10)
	_key(KEY_E)
	await _wait(10)
	_expect(_player.held_item().is_empty() and _player.is_holstered(),
		"physical E over empty space holsters")


## Empty ability slots are safe. Click fires the selected slot. RMB does not.
## Keys 1-4 select a slot without firing it.
func _ability_routing() -> void:
	_ability_events.clear()
	if not _player.ability_activated.is_connected(_on_ability_activated):
		_player.ability_activated.connect(_on_ability_activated)

	_player.abilities.clear()
	_player.holster()
	_dispatch_action(&"attack")
	_dispatch_action(&"aim")
	_expect(_ability_events.is_empty(),
		"empty selected ability and RMB are safe no-ops")

	var ability_ids := ItemDB.ability_ids()
	if ability_ids.size() < 2:
		print("weapon_test: SKIP  populated ability routing (fewer than two definitions)")
		return

	# Observe dispatch without actually launching a beam or movement ability.
	var controller := _player._ability_controller as AbilityController
	var activated := Callable(controller, "_on_activated")
	var released := Callable(controller, "_on_released")
	if controller != null and _player.ability_activated.is_connected(activated):
		_player.ability_activated.disconnect(activated)
	if controller != null and _player.ability_released.is_connected(released):
		_player.ability_released.disconnect(released)

	_player.abilities.set_item(0, ability_ids[0])
	_player.abilities.set_item(1, ability_ids[1])
	_player.holster()
	_player.select_ability(0)
	_dispatch_action(&"attack")
	_dispatch_action(&"aim")
	_expect(_ability_events == [0],
		"click fires the selected ability and RMB does not")

	_ability_events.clear()
	_player.select_ability(1)
	_dispatch_action(&"attack")
	_expect(_ability_events == [1], "click fires the newly selected ability")

	_ability_events.clear()
	_player.select_ability(0)
	_dispatch_action(&"weapon_2")
	_expect(_ability_events.is_empty() and _player.selected_ability_index() == 1,
		"key 2 swaps to slot 2 without firing")
	_dispatch_action(&"attack")
	_expect(_ability_events == [1], "click fires the key-selected ability")

	_player.holster()
	_player.abilities.clear()
	if controller != null and not _player.ability_activated.is_connected(activated):
		_player.ability_activated.connect(activated)
	if controller != null and not _player.ability_released.is_connected(released):
		_player.ability_released.connect(released)
	await _wait(4)


func _sword() -> void:
	_player.select_weapon(0)
	await _wait(45)
	_report("sword hold", _grip())
	await _look_from(Vector3(1.2, 1.0, -1.6))
	await _shot("weapon_sword_hold")
	await _look_from(Vector3(2.1, 1.0, -0.1))
	await _shot("weapon_sword_side")

	# Frames through the cut, from the front: whether it travels across the body
	# from the right cannot be judged from behind.
	await _look_from(Vector3(0.3, 1.0, -2.2))
	_player._attack()
	for index in 4:
		await _wait(5)
		_report("swing %d" % index, _grip())
		await _shot("weapon_sword_swing_%d" % index)
	await _wait(40)


## The whole point of solving the arms rather than baking a hold clip: the legs
## should still be running their own clip underneath it.
func _walking() -> void:
	_place(Vector3(11.0, 0.4, 13.0), PI)
	_player.select_weapon(0)
	await _wait(30)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(45)
	await _look_from(Vector3(2.2, 1.0, -0.2))
	_report("running", "clip=%s  %s" % [_player._clip, _grip()])
	await _shot("weapon_sword_running")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(20)


func _rifle() -> void:
	_player.select_weapon(2)
	await _wait(45)
	_report("rifle hold", _grip())
	await _look_from(Vector3(1.3, 1.0, -1.6))
	await _shot("weapon_rifle_hold")
	await _look_from(Vector3(2.1, 1.0, -0.1))
	await _shot("weapon_rifle_side")

	# Held as a player holds it: the controller reads the polled action every frame,
	# so setting the pose directly would be undone by the next one.
	Input.action_press("aim")
	await _wait(30)
	_report("rifle aimed", _grip())
	await _shot("weapon_rifle_aimed")
	await _look_from(Vector3(2.1, 1.0, -0.1))
	await _shot("weapon_rifle_aimed_side")

	# Watched from the side with the view opened up: a bolt covers more than a metre
	# per frame, so a shot photographed down its own line is a dot.
	_place(Vector3(0.0, 0.4, 6.0), 0.0)
	await _look_from(Vector3(3.0, 0.9, -1.2))
	_review.fov = 74.0
	var before := _player._charge()
	_player._shoot()
	await _wait(2)
	await _shot("weapon_bolt")
	_review.fov = 38.0
	await _wait(2)
	var bolts := _bolts()
	var offset := "none"
	if not bolts.is_empty():
		var bolt := bolts[0]
		var along := -bolt.global_basis.z
		offset = "%.1f°" % rad_to_deg(along.angle_to(-_player.camera.global_basis.z))
	_report("shot", "cell %d -> %d  bolts=%d  off crosshair=%s" % [
		before, _player._charge(), bolts.size(), offset])
	await _shot("weapon_rifle_shot")

	# Empty the cell, then let it trickle back.
	for _index in 20:
		_player._shoot()
		await _wait(2)
	var emptied := _player._charge()
	await _wait(150)
	_report("cell", "emptied to %d, back to %d after 2.5s (pause %.2f, charge %.2f)" % [
		emptied, _player._charge(), _player._cell_pause,
		float(_player._cells.get("laser_rifle", -1.0))])
	Input.action_release("aim")
	await _wait(30)


## First person is the case the body is hidden in, so what is left of the weapon
## has to be looked at rather than assumed.
func _first_person() -> void:
	_player.camera.current = true
	_player._camera_mode = 0
	_player.select_weapon(0)
	await _wait(50)
	await _shot("weapon_first_person_sword")
	_player.select_weapon(2)
	await _wait(50)
	await _shot("weapon_first_person_rifle")
	Input.action_press("aim")
	await _wait(40)
	await _shot("weapon_first_person_aimed")
	Input.action_release("aim")
	await _wait(20)


## Combat still knows how to hold leftover weapons. The Items tab is gone, so
## this harness places them on the private hotbar directly.
func _arm_from_backpack() -> void:
	_player.holster()
	_player.hotbar.clear()
	_player.abilities.clear()
	_player.backpack.clear()
	_player.hotbar.set_item(0, "sword")
	_player.hotbar.set_item(2, "laser_rifle")
	_expect(_player.hotbar.items()
		== PackedStringArray(["sword", "", "laser_rifle"]),
		"leftover weapon row still accepts sword and rifle")
	_report("arming", "hotbar=%s backpack=%s" % [
		_player.hotbar.items(), _player.backpack.items()])
	await _shot("weapon_rack")
	await _wait(4)
	get_tree().paused = false


func _equip_from_backpack(
	page: RedCataloguePage,
	item_id: String,
	target_index: int
) -> void:
	var tile := _red_tile(page, _player.backpack, item_id)
	_expect(tile != null, "backpack exposes %s RedItemSlot" % item_id)
	if tile == null:
		return
	tile.picked.emit(tile)
	await _wait(2)
	var target := page.find_child(
		"TargetSlot%d" % (target_index + 1), true, false) as Button
	_expect(target != null, "%s can select target %d" % [
		item_id, target_index + 1])
	if target == null:
		return
	target.pressed.emit()
	await _wait(1)
	var equip := page.find_child("EquipAction", true, false) as HoldActionButton
	_expect(equip != null and not equip.completed.get_connections().is_empty(),
		"%s hold-to-equip is signal-wired" % item_id)
	if equip != null:
		equip.completed.emit()
	await _wait(3)


func _game_menu() -> GameMenu:
	for child: Node in _player.hud.get_children():
		if child is GameMenu:
			return child as GameMenu
	return null


func _active_catalogue(menu: GameMenu) -> RedCataloguePage:
	var host := menu.find_child("PageHost", true, false)
	if host == null or host.get_child_count() != 1:
		return null
	return host.get_child(0) as RedCataloguePage


func _red_tile(
	page: RedCataloguePage,
	container: ItemContainer,
	item_id: String
) -> RedItemSlot:
	var grid := page.find_child("OwnedItemGrid", true, false)
	if grid == null:
		return null
	for child: Node in grid.get_children():
		if child is RedItemSlot:
			var slot := child as RedItemSlot
			if slot.container == container and slot.item_id() == item_id:
				return slot
	return null


# --- Measurements -----------------------------------------------------------

## What the hold is actually doing, in numbers: where the weapon points, and how
## far the supporting hand is off its axis.
func _grip() -> String:
	var mesh := _player._held_mesh
	if mesh == null:
		return "nothing in hand"
	var origin := mesh.global_position
	var along := -mesh.global_basis.z
	var support := _grip_point("LeftHand")
	var lead := _grip_point("RightHand")
	return "points %s  up=%+.2f  cant %.0f°  support %.0f mm off the axis  grips %.0f mm apart" % [
		_compass(along), along.dot(Vector3.UP),
		rad_to_deg(_cant(along)),
		_distance_to_axis(support, origin, along) * 1000.0,
		support.distance_to(lead) * 1000.0]


## How far off the way the character faces the weapon points, measured flat: a
## carbine held across the chest reads as wrong however good the grip is.
func _cant(along: Vector3) -> float:
	var local: Vector3 = _player.global_basis.inverse() * along
	return absf(atan2(local.x, -local.z))


## The weapon's direction in the character's own terms, which is what a pose is
## described in.
func _compass(direction: Vector3) -> String:
	var local: Vector3 = _player.global_basis.inverse() * direction
	var parts := PackedStringArray()
	if absf(local.z) > 0.3:
		parts.append("forward" if local.z < 0.0 else "back")
	if absf(local.y) > 0.3:
		parts.append("up" if local.y > 0.0 else "down")
	if absf(local.x) > 0.3:
		parts.append("right" if local.x > 0.0 else "left")
	return " ".join(parts) if parts.size() > 0 else "level"


func _distance_to_axis(point: Vector3, origin: Vector3, along: Vector3) -> float:
	var offset := point - origin
	return (offset - along.normalized() * offset.dot(along.normalized())).length()


func _add_hand_probes() -> void:
	var skeleton := Weapons.skeleton_of(_player.character)
	for bone_name in ["LeftHand", "RightHand"]:
		var probe := BoneAttachment3D.new()
		skeleton.add_child(probe)
		probe.bone_name = bone_name
		_hand_probes[bone_name] = probe


## Where the hand grips, rather than where its wrist is: a weapon sits part way
## down the hand bone, and the wrist trailing the grip is not a miss.
func _grip_point(bone_name: String) -> Vector3:
	var probe := _hand_probes.get(bone_name) as BoneAttachment3D
	if probe == null:
		return Vector3.ZERO
	var skeleton := Weapons.skeleton_of(_player.character)
	var bone := skeleton.find_bone(bone_name)
	var along := skeleton.get_bone_rest(bone).origin.length() * Weapons.GRIP_ALONG_HAND
	return probe.global_position + probe.global_basis.y.normalized() * along


func _bolts() -> Array[LaserBolt]:
	var found: Array[LaserBolt] = []
	for node in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if node is LaserBolt:
			found.append(node as LaserBolt)
	return found


# --- Helpers ----------------------------------------------------------------

## [param offset] is metres in the landing site's frame — its +Y is up out of the
## planet there — and [param yaw] turns about that up rather than the world's.
func _place(offset: Vector3, yaw: float) -> void:
	_player.global_transform = Transform3D(
		_ground.basis * Basis(Vector3.UP, yaw), _ground * offset)
	_player.velocity = Vector3.ZERO


## Reviews the character from `offset` in its own frame: +X its right, -Z the way
## it faces, so the same offset frames every pose the same way.
func _look_from(offset: Vector3) -> void:
	var eye: Vector3 = _player.global_position + _player.global_basis * offset
	_review.global_position = eye
	_review.look_at(_player.global_position + Vector3(0.0, 0.95, 0.0), Vector3.UP)
	_review.current = true
	await _wait(2)


func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	Input.parse_input_event(press)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)


func _dispatch_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	_player._unhandled_input(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	_player._unhandled_input(release)


func _on_ability_activated(index: int, _id: String) -> void:
	_ability_events.append(index)


func _wait(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame


func _report(step: String, detail: String) -> void:
	print("weapon_test: %-14s %s" % [step, detail])


func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("weapon_test: PASS  %s" % message)
		return true
	_failures += 1
	push_error("weapon_test: FAIL  %s" % message)
	return false


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("weapon_test: SKIP  %s.png (headless display)" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	if error != OK:
		print("weapon_test: shot %s failed: %s" % [shot_name, error_string(error)])


func _snapshot_settings() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_PATH)
	_settings_existed = FileAccess.file_exists(path)
	if _settings_existed:
		_settings_bytes = FileAccess.get_file_as_bytes(path)


func _restore_settings() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_PATH)
	if not _settings_existed:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("weapon_test: could not restore %s" % path)
		return
	file.store_buffer(_settings_bytes)
	file.close()


func _finish() -> void:
	get_tree().paused = false
	Input.action_release("aim")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	var world := NetworkManager.active_world as GameWorld
	if is_instance_valid(world):
		world.queue_free()
	await _wait(3)
	_restore_settings()
	NetworkManager.players.clear()
	NetworkManager.state = NetworkManager.SessionState.IDLE
	NetworkManager.is_single_player = false
	NetworkManager.is_host = false
	print("weapon_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
