extends Node

## Small runtime check for input dispatch, HUD binding and persistence without
## loading the planet or creating screenshot artifacts.
##
##     godot --headless --path . dev/_loadout_player_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const SETTINGS_PATH := "user://settings.cfg"

var _failures := 0
var _player: OnlinePlayer
var _settings_existed := false
var _settings_bytes := PackedByteArray()


func _ready() -> void:
	_snapshot_settings()
	# The HUD binding is under test, not icon rendering. Seed the process-local
	# cache so a dummy headless renderer is never asked for material parameters.
	for item_id: String in ItemDB.ITEMS:
		ItemIcons._cache[item_id] = ImageTexture.new()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	add_child(_player)
	# This harness is about loadout state, not locomotion.
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	_player.equipment.clear()
	_player.hotbar.clear()
	_player.abilities.clear()
	_player.backpack.clear()
	await get_tree().process_frame

	_check_containers_and_hud()
	await _check_selection_and_holster()
	await _check_persistence()

	_player.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	_restore_settings()
	print("loadout_player_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_containers_and_hud() -> void:
	_expect(_player.hotbar.size() == 3, "player still keeps a leftover item row")
	_expect(_player.abilities.size() == 4, "player exposes four ability slots")
	_expect(_player.weapons == _player.hotbar, "weapons remains a hotbar alias")

	var slots: Array[ItemSlot] = []
	for node in _player._weapon_bar.find_children("*", "Control", true, false):
		if node is ItemSlot:
			slots.append(node as ItemSlot)
	var badges := PackedStringArray()
	for slot in slots:
		badges.append(slot.badge)
	_expect(badges == PackedStringArray(["Q", "RMB", "1", "2", "3", "4"]),
		"HUD order is Q, RMB, 1, 2, 3, 4")
	_expect(slots.size() == 6 and slots[2].container == _player.abilities
		and slots[5].container == _player.abilities,
		"HUD binds the numbered tiles to the ability container")


func _check_selection_and_holster() -> void:
	_expect(_player.equip_hotbar("sword", 0), "public hotbar equip accepts a weapon")
	_expect(_player.equip_hotbar("laser_rifle", 2), "public hotbar equip accepts slot three")
	_player.select_hotbar(0)
	await get_tree().process_frame
	_expect(_player.held_item() == "sword" and not _player.is_holstered(),
		"numbered selection draws its item")

	var press := InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	_expect(press.is_action_pressed("parry")
		and not press.is_action_pressed("holster"), "physical F maps only to parry")
	_player._unhandled_input(press)
	await get_tree().process_frame
	_expect(_player.held_item() == "sword" and not _player.is_holstered(),
		"parry leaves the drawn item alone")
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.pressed = true
	_player._unhandled_input(interact)
	await get_tree().process_frame
	_expect(_player.held_item().is_empty() and _player.is_holstered(),
		"E over empty space enters ability mode")
	_expect(not _player.activate_ability(0), "empty LMB ability safely no-ops")
	_player.activate_primary()
	_expect(_player.held_item().is_empty(), "holstered LMB does not attack a weapon")

	_player.select_hotbar(1)
	_player._cycle_weapon(1)
	await get_tree().process_frame
	_expect(_player.held_item() == "laser_rifle",
		"wheel skips an empty numbered slot")
	_player._cycle_weapon(1)
	await get_tree().process_frame
	_expect(_player.held_item() == "sword", "wheel wraps among nonempty slots")

	# The same methods receive replicated held state on remote peers.
	_player.apply_held("laser_rifle")
	await get_tree().process_frame
	_player.apply_held("")
	await get_tree().process_frame
	_expect(_player.held_item().is_empty(), "replicated empty held state holsters")


func _check_persistence() -> void:
	_player.holster()
	_player.backpack.set_item(0, "c3_hair")
	_expect(_player.equip_ability("laser_eyes", 1),
		"public ability equip accepts a real power in slot 2")
	await get_tree().process_frame
	await get_tree().process_frame
	var stored := CharacterDB.load_look()
	_expect(CharacterDB.hotbar_items(stored, 3) \
		== PackedStringArray(["sword", "", "laser_rifle"]),
		"hotbar changes persist")
	_expect(CharacterDB.backpack_items(stored, CharacterDB.BACKPACK_SLOTS)[0] \
		== "c3_hair", "backpack changes persist")
	_expect(CharacterDB.ability_items(stored, 4)
		== PackedStringArray(["", "laser_eyes", "", ""]),
		"ability assignments persist independently from leftover items")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("loadout_player_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("loadout_player_test: FAIL  %s" % message)


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
		push_error("loadout_player_test: could not restore %s" % path)
		return
	file.store_buffer(_settings_bytes)
	file.close()
