class_name GameSettingsManager
extends Node

signal settings_changed(section: StringName, key: StringName, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"
## Increment when the shipped character skin changes. This lets an existing
## settings file receive a new project default once without resetting the
## player's skin choice on every later launch.
const DEFAULT_SKIN_REVISION := 2
## Version one replaces the five-entry weapon rack with three numbered hotbar
## entries, two mouse ability entries and persistent backpack contents.
const LOADOUT_SCHEMA_REVISION := 1
const HOTBAR_SLOTS := 3
const ABILITY_SLOTS := 4
const DEFAULTS := {
	"graphics": {
		"window_mode": 0,
		"resolution": "1280x720",
		"vsync": true,
		"max_fps": 120,
		"render_scale": 1.0,
		"quality": 1,
		## Index into [constant Planet.DETAIL_LEVELS]. Applied by the planet
		## rather than by `_apply_setting`, because there is nothing to apply it
		## to until a world is loaded.
		"render_distance": 1,
		## Multiplier on how far ground cover is drawn, applied by [GroundCover]
		## for the same reason: the fields arrive with the map. Ships above one
		## so that flying at a few hundred metres still passes over a populated
		## planet rather than bare terrain.
		"flora_range": 2.0,
		## Wavelength-based colour in the sky and the atmosphere shell. Applied
		## by `_apply_setting` through the `air_chroma` shader global, so it
		## lands with or without a world loaded and needs nothing to be found.
		## Off restores the flat blue atmosphere and costs the two shaders a
		## branch they take uniformly.
		"atmospheric_scattering": true,
		## Depth-marched sunbeams. Applied by [CelestialCycle] rather than here,
		## for the same reason `render_distance` is applied by the planet: the
		## compositor arrives with the map and there is nothing to switch off
		## until it does.
		"god_rays": true,
		## Tear, cell-shift, snow, and RGB fringe on CRT type and rims.
		## Scanlines stay on either way. Applied live by [CrtType] and
		## [RedGlowPanel] each frame so the Display row can be compared
		## without leaving the page.
		"ui_glitch": true,
	},
	"audio": {
		"master_volume": 0.8,
		"music_volume": 0.7,
		"sfx_volume": 0.8,
		"voice_volume": 0.9,
	},
	"gameplay": {
		"mouse_sensitivity": 0.35,
		"invert_y": false,
		"fov": 75.0,
	},
	## Who you are: the name and the look. Body and skin ids, sparse slot→item
	## map, and sparse slot/"body"→HTML tint map. The home screen and the
	## character editor are the writers; spawning, the preview and the lobby read.
	##
	## The name lives here rather than in [NetworkManager] because it outlives a
	## session — it is typed once under the figure on the home screen and is then
	## the name single player uses, the name the lobby fields start on, and the
	## name chat stamps.
	"appearance": {
		"name": "Player",
		"body": "settler",
		"skin": "noct_crimson",
		"worn": {},
		## Positional because the index is the number or mouse button that uses it.
		"hotbar": ["", "", ""],
		"abilities": ["", "", "", ""],
		"backpack": [],
		## CharacterDB raises this after giving a new save its finite starter
		## wardrobe. Resetting defaults returns it to zero so the wardrobe is
		## deliberately seeded again instead of leaving a fresh backpack empty.
		"starter_inventory_revision": 0,
		## Deprecated mirror retained while older menu code still calls it a rack.
		"rack": ["", "", ""],
		"tints": {},
		"loadout_schema_revision": LOADOUT_SCHEMA_REVISION,
	},
	## Quests and achievements finished, as a list of [JournalDB] ids, plus
	## which gem rewards have been claimed from the menu. Local to this
	## machine and never replicated: a co-op session shares a world, not a
	## diary. [Journal] is the only writer.
	"progress": {
		"done": [],
		"claimed": [],
		"kills": 0,
		"claim_revision": 0,
	},
	## Gems, unlocked homescreen hats, permanent crawler stat ranks, and the
	## player's global level. Lives outside a run so the home screen can
	## spend them and the next crawler session still sees the same bonuses.
	"meta": {
		"gems": 0,
		"unlocked_hats": [],
		"xp": 0,
		"sandbox_unlocked": false,
		"ranks": {
			"health": 0,
			"dexterity": 0,
			"flight": 0,
			"dodge": 0,
			"defense": 0,
			"juke": 0,
			"juke_distance": 0,
			"damage": 0,
			"knockback": 0,
			"range": 0,
			"luck": 0,
			"elemental": 0,
		},
		"auto_select": false,
		"auto_select_prefs": {
			"flying": true,
			"health": true,
			"greed": true,
			"strength": true,
			"misc": false,
		},
	},
}

var _config := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_config = ConfigFile.new()
	var error := _config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("Could not load settings.cfg (error %s)." % error)
	var skin_migrated := _migrate_default_skin()
	var loadout_migrated := _migrate_loadout()
	_apply_defaults()
	_load_input_bindings()
	apply_all()
	if skin_migrated or loadout_migrated:
		save_settings()


func save_settings() -> Error:
	_save_input_bindings()
	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Could not save settings.cfg (error %s)." % error)
	return error


func get_setting(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	return _config.get_value(String(section), String(key), fallback)


func set_setting(section: StringName, key: StringName, value: Variant, apply := true) -> void:
	_config.set_value(String(section), String(key), value)
	if apply:
		if String(section) == "graphics":
			LagTracker.note("settings", "graphics/%s = %s" % [String(key), str(value)])
		_apply_setting(section, key, value)
	settings_changed.emit(section, key, value)


func reset_to_defaults() -> void:
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			set_setting(section, key, DEFAULTS[section][key], false)
	apply_all()
	save_settings()


func apply_all() -> void:
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			_apply_setting(section, key, get_setting(section, key, DEFAULTS[section][key]))


func rebind_action(action: StringName, event: InputEvent, slot := 0) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var events := InputMap.action_get_events(action)
	if slot >= 0 and slot < events.size():
		InputMap.action_erase_event(action, events[slot])
	InputMap.action_add_event(action, event)
	save_settings()


func _apply_defaults() -> void:
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			if not _config.has_section_key(section, key):
				_config.set_value(section, key, DEFAULTS[section][key])
	_ensure_meta_ranks()


## Older saves only stored the first wave of gem ranks. Fill any later in-run
## stats so the homescreen shop and the next crawler session share one table.
func _ensure_meta_ranks() -> void:
	var held: Variant = _config.get_value("meta", "ranks", {})
	var ranks: Dictionary = held.duplicate() if held is Dictionary else {}
	var changed := false
	for stat_id: String in CrawlerProgress.LEVEL_STATS:
		if not ranks.has(stat_id):
			ranks[stat_id] = 0
			changed = true
	if changed:
		_config.set_value("meta", "ranks", ranks)


## Ships a new default skin once. Players who still have the previous default
## (Luke) move to Noct Crimson; an explicit later choice stays put.
func _migrate_default_skin() -> bool:
	var revision := int(_config.get_value(
		"appearance", "default_skin_revision", 0))
	if revision >= DEFAULT_SKIN_REVISION:
		return false
	var current := str(_config.get_value("appearance", "skin", ""))
	if current.is_empty() or current == "luke":
		_config.set_value("appearance", "skin", "noct_crimson")
	_config.set_value("appearance", "default_skin_revision",
		DEFAULT_SKIN_REVISION)
	return true


## Migrates the old five-slot rack without dropping slots four and five: the
## first three keep their number keys and any overflow moves into the backpack.
## The old key remains as a compatibility copy and is ignored once the revision
## marker says this migration has run.
func _migrate_loadout() -> bool:
	var revision := int(_config.get_value(
		"appearance", "loadout_schema_revision", 0))
	if revision >= LOADOUT_SCHEMA_REVISION:
		return false

	var old_rack := _variant_array(_config.get_value("appearance", "rack", []))
	var has_hotbar_key := _config.has_section_key("appearance", "hotbar")
	var hotbar_raw: Variant = _config.get_value("appearance", "hotbar", [])
	var had_hotbar := has_hotbar_key and (
		hotbar_raw is Array or hotbar_raw is PackedStringArray)
	var hotbar_source := _variant_array(hotbar_raw if had_hotbar else old_rack)
	var hotbar: Array = []
	for index in HOTBAR_SLOTS:
		hotbar.append(hotbar_source[index] if index < hotbar_source.size() else "")

	var abilities_source := _variant_array(_config.get_value(
		"appearance", "abilities", []))
	var abilities: Array = []
	for index in ABILITY_SLOTS:
		abilities.append(abilities_source[index] if index < abilities_source.size() else "")

	var backpack := _variant_array(_config.get_value(
		"appearance", "backpack", []))
	if not had_hotbar:
		for index in range(HOTBAR_SLOTS, old_rack.size()):
			var overflow := str(old_rack[index])
			if overflow.is_empty():
				continue
			var free := backpack.find("")
			if free >= 0:
				backpack[free] = overflow
			else:
				backpack.append(overflow)

	_config.set_value("appearance", "hotbar", hotbar)
	_config.set_value("appearance", "abilities", abilities)
	_config.set_value("appearance", "backpack", backpack)
	_config.set_value("appearance", "rack", hotbar.duplicate())
	_config.set_value("appearance", "loadout_schema_revision",
		LOADOUT_SCHEMA_REVISION)
	return true


func _variant_array(value: Variant) -> Array:
	var out: Array = []
	if value is Array or value is PackedStringArray:
		for entry: Variant in value:
			out.append(entry)
	return out


func _apply_setting(section: StringName, key: StringName, value: Variant) -> void:
	match "%s/%s" % [section, key]:
		"graphics/window_mode":
			match int(value):
				1:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				2:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				_:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"graphics/resolution":
			var parts := String(value).split("x")
			if parts.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
		"graphics/vsync":
			var enabled := bool(value)
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)
			# VSync already paces frames to the display. A simultaneous 120 FPS
			# software cap produces an uneven cadence on 60/144/165 Hz panels,
			# most visible as a slight judder during slow camera translation.
			Engine.max_fps = 0 if enabled else int(get_setting(
				&"graphics", &"max_fps", DEFAULTS["graphics"]["max_fps"]))
		"graphics/max_fps":
			Engine.max_fps = 0 if bool(get_setting(
				&"graphics", &"vsync", DEFAULTS["graphics"]["vsync"])) else int(value)
		"graphics/render_scale":
			get_tree().root.scaling_3d_scale = float(value)
		"graphics/atmospheric_scattering":
			# A global shader parameter rather than a uniform on each material,
			# because the sky and the atmosphere shell draw two halves of one
			# sight and cross-fade into each other at a fixed altitude — see
			# `air_chroma` in vivid_lib.gdshaderinc. Written only when the
			# setting changes; the sky's radiance cubemap is rebuilt on a global
			# write, so this must never be driven per frame.
			RenderingServer.global_shader_parameter_set(&"air_chroma",
				1.0 if bool(value) else 0.0)
		"graphics/quality":
			match int(value):
				0:
					get_tree().root.msaa_3d = Viewport.MSAA_DISABLED
				2:
					get_tree().root.msaa_3d = Viewport.MSAA_4X
				_:
					get_tree().root.msaa_3d = Viewport.MSAA_2X
		"audio/master_volume":
			_set_bus_volume(&"Master", float(value))
		"audio/music_volume":
			_set_bus_volume(&"Music", float(value))
		"audio/sfx_volume":
			_set_bus_volume(&"SFX", float(value))
		"audio/voice_volume":
			_set_bus_volume(&"Voice", float(value))


func _set_bus_volume(bus_name: StringName, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(linear_volume, 0.0001, 1.0)))
	AudioServer.set_bus_mute(bus_index, is_zero_approx(linear_volume))


func _save_input_bindings() -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var serialized: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			var data := _serialize_event(event)
			if not data.is_empty():
				serialized.append(data)
		_config.set_value("controls", String(action), serialized)


func _load_input_bindings() -> void:
	if not _config.has_section("controls"):
		return
	var has_saved_parry := _config.has_section_key("controls", "parry")
	for action_key: String in _config.get_section_keys("controls"):
		var action := StringName(action_key)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var saved_events: Array = _config.get_value("controls", action_key, [])
		InputMap.action_erase_events(action)
		for event_data: Variant in saved_events:
			if event_data is Dictionary:
				var event := _deserialize_event(event_data)
				if event != null:
					InputMap.action_add_event(action, event)
	# Settings written before parry existed commonly restore F onto holster after
	# project.godot has already put it on parry. Migrate only that legacy F event;
	# deliberate custom holster bindings on other keys remain untouched.
	if not has_saved_parry:
		for event: InputEvent in InputMap.action_get_events(&"holster"):
			if event is InputEventKey and (
					event.physical_keycode == KEY_F or event.keycode == KEY_F):
				InputMap.action_erase_event(&"holster", event)


func _serialize_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {
			"type": "key",
			"keycode": event.keycode,
			"physical_keycode": event.physical_keycode,
		}
	if event is InputEventMouseButton:
		return {"type": "mouse_button", "button_index": event.button_index}
	if event is InputEventJoypadButton:
		return {"type": "joypad_button", "button_index": event.button_index}
	return {}


func _deserialize_event(data: Dictionary) -> InputEvent:
	match String(data.get("type", "")):
		"key":
			var key_event := InputEventKey.new()
			key_event.keycode = int(data.get("keycode", 0)) as Key
			key_event.physical_keycode = int(data.get("physical_keycode", 0)) as Key
			return key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(data.get("button_index", 1)) as MouseButton
			return mouse_event
		"joypad_button":
			var joypad_event := InputEventJoypadButton.new()
			joypad_event.button_index = int(data.get("button_index", 0)) as JoyButton
			return joypad_event
	return null
