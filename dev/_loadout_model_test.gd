extends Node

## Focused, rendering-free checks for the Red Tab loadout backend.
##
##     godot --headless --path . dev/_loadout_model_test.tscn

const SETTINGS_PATH := "user://settings.cfg"

var _failures := 0
var _settings_existed := false
var _settings_bytes := PackedByteArray()


func _ready() -> void:
	_snapshot_settings()
	_check_item_kinds()
	_check_container_filters()
	_check_character_schema()
	_check_player_camera_rim()
	_check_organic_camera_rim()
	_check_starter_inventory()
	_check_rack_migration()
	_check_graphics_toggles()
	_check_god_rays_shaders()
	_check_god_rays_veil()
	_check_sunset_tint()
	_check_night_ground_glow()
	_check_steam_lobby_contract()
	_check_player_designer_contract()
	_restore_settings()
	print("loadout_model_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_item_kinds() -> void:
	_expect(ItemDB.kind_of("sword") == ItemDB.KIND_WEAPON,
		"sword has explicit weapon kind")
	_expect(ItemDB.kind_of("c3_hair") == ItemDB.KIND_APPAREL,
		"apparel has explicit apparel kind")
	_expect(ItemDB.accepts_hotbar("sword"), "hotbar accepts weapons")
	_expect(not ItemDB.accepts_ability("sword"), "ability slot rejects weapons")
	# Two abilities ship now. The container still has to keep a weapon out of an
	# ability slot, which is what the check above and the filters below are for;
	# what changed is only that the catalogue is no longer allowed to be empty.
	_expect(ItemDB.accepts_ability("laser_eyes"),
		"ability slot accepts a real ability")


func _check_player_camera_rim() -> void:
	var source := StandardMaterial3D.new()
	var material := SurfaceSkin.material_for(source, true)
	var ordinary := SurfaceSkin.material_for(source)
	var rim_colour: Variant = material.get_shader_parameter(&"camera_rim_color")
	var green_rim := (
		rim_colour is Color
		and (rim_colour as Color).g > (rim_colour as Color).r
		and (rim_colour as Color).g > (rim_colour as Color).b
	)
	var dark := float(material.get_shader_parameter(&"camera_rim_dark"))
	var light := float(material.get_shader_parameter(&"camera_rim_light"))
	_expect(green_rim
		and float(material.get_shader_parameter(&"camera_rim_energy")) > 0.0,
		"player material enables a neon-green camera rim")
	_expect(is_zero_approx(float(
		ordinary.get_shader_parameter(&"camera_rim_energy"))),
		"ordinary items do not inherit the Character 3 rim")
	_expect(dark > 0.0 and dark < light and light < 1.0,
		"player camera rim uses a narrow Color Ramp equivalent")


func _check_organic_camera_rim() -> void:
	var shader_paths := PackedStringArray([
		"res://shaders/vivid/vivid_plant.gdshader",
		"res://shaders/vivid/vivid_fish.gdshader",
		"res://shaders/vivid/vivid_swarm.gdshader",
		"res://shaders/vivid/vivid_night_phenomena.gdshader",
	])
	for path in shader_paths:
		var shader := load(path) as Shader
		var code := shader.code if shader != null else ""
		var same_rim_contract := (
			code.contains(
				"camera_rim_color : source_color = vec3(0.20, 1.0, 0.58)")
			and code.contains("camera_rim_energy")
			and code.contains("camera_rim_dark")
			and code.contains("camera_rim_light")
			and code.contains("camera_rim_color * camera_rim_energy")
		)
		_expect(shader != null and same_rim_contract,
			"%s enables the organic camera rim" % path.get_file())

	var organic_material_paths := PackedStringArray([
		"res://game/props/flower_tree.tres",
		"res://game/props/flower_tree_head.tres",
		"res://game/enemies/bigfoot/bigfoot_surface.tres",
	])
	for path in organic_material_paths:
		var material := load(path) as ShaderMaterial
		_expect(material != null
			and float(material.get_shader_parameter(
				&"camera_rim_energy")) > 0.0,
			"%s keeps the organic camera rim enabled" % path.get_file())

	var grass := load("res://game/props/grass.tres") as ShaderMaterial
	var grass_rim := float(grass.get_shader_parameter(
		&"camera_rim_energy")) if grass != null else INF
	var grass_fade_from := float(grass.get_shader_parameter(
		&"camera_rim_fade_from")) if grass != null else INF
	var grass_fade_to := float(grass.get_shader_parameter(
		&"camera_rim_fade_to")) if grass != null else -INF
	_expect(grass_rim > 0.0 and grass_rim <= 0.1
		and grass_fade_from < grass_fade_to and grass_fade_to <= 30.0,
		"dense grass keeps a subtle close rim and filters distant edge noise")
	_expect(grass != null and float(grass.get_shader_parameter(
			&"glow_strength")) <= 1.0
		and float(grass.get_shader_parameter(&"glow_fade_from"))
			< float(grass.get_shader_parameter(&"glow_fade_to"))
		and float(grass.get_shader_parameter(&"glow_fade_to")) <= 34.0,
		"grass patch emission leaves headroom for coherent ground lighting")

	var near_grass := load(
		"res://game/props/grass_species.tres") as PlantSpecies
	var far_grass := load(
		"res://game/props/grass_distant_species.tres") as PlantSpecies
	_expect(near_grass != null and far_grass != null
		and near_grass.per_square_metre <= 20.0
		and far_grass.per_square_metre <= 1.0,
		"near and distant grass density stay below the noisy overdraw level")


func _check_night_ground_glow() -> void:
	var material := load(
		"res://game/planet/planet_surface.tres") as ShaderMaterial
	var shader := material.shader if material != null else null
	var code := shader.code if shader != null else ""
	_expect(code.contains("vivid_night_ground_glow")
		and code.contains(
			"night_ground_glow_time * night_ground_glow_speed")
		and code.contains("vivid_night_ground_palette")
		and code.contains("night_ground_glow_threshold - softness")
		and code.contains("night_ground_glow_threshold + softness"),
		"night terrain glow has synchronized multicolour flow and soft edges")
	if material == null:
		_expect(false, "night terrain glow has an authored material")
		return
	var energy := float(material.get_shader_parameter(
		&"night_ground_glow_energy"))
	var scale := float(material.get_shader_parameter(
		&"night_ground_glow_scale"))
	var softness := float(material.get_shader_parameter(
		&"night_ground_glow_softness"))
	var speed := float(material.get_shader_parameter(
		&"night_ground_glow_speed"))
	var near_fade := float(material.get_shader_parameter(
		&"night_ground_glow_near"))
	var far_fade := float(material.get_shader_parameter(
		&"night_ground_glow_far"))
	_expect(energy > 0.0 and energy <= 0.18,
		"night terrain glow stays deliberately faint")
	_expect(scale > 0.0 and scale <= 0.005 and softness >= 0.1,
		"night terrain glow forms large patches with broad fading borders")
	_expect(speed > 0.0 and near_fade < far_fade,
		"night terrain glow moves and filters out before orbit shimmer")
	var first_night := NightGroundGlow.palette_for_night(0)
	var second_night := NightGroundGlow.palette_for_night(1)
	_expect(first_night.size() == 3
		and first_night[0] != first_night[1]
		and first_night != second_night,
		"terrain blotches use multiple colours and change palette each night")
	var glow_source := FileAccess.get_file_as_string(
		"res://game/planet/night_ground_glow.gd")
	var planet_source := FileAccess.get_file_as_string(
		"res://game/planet/planet.gd")
	_expect(glow_source.contains("OmniLight3D.new()")
		and glow_source.contains("light_cull_mask = 0xFFFFD")
		and glow_source.contains("sample_direction(direction)")
		and planet_source.contains(
			"instance.layers = TERRAIN_RENDER_LAYER"),
		"terrain glow casts its sampled colours onto every nearby object layer")


func _check_container_filters() -> void:
	var hotbar := ItemContainer.new(CharacterDB.HOTBAR_SLOTS)
	var abilities := ItemContainer.new(CharacterDB.ABILITY_SLOTS)
	var backpack := ItemContainer.new(2)
	for index in hotbar.size():
		hotbar.set_filter(index, ItemDB.HOTBAR)
	for index in abilities.size():
		abilities.set_filter(index, ItemDB.ABILITY)
	for index in backpack.size():
		backpack.set_filter(index, ItemDB.BACKPACK)
	hotbar.set_item(0, "sword")
	abilities.set_item(0, "sword")
	backpack.set_item(0, "c3_hair")
	_expect(hotbar.get_item(0) == "sword", "filtered hotbar stores a weapon")
	_expect(abilities.get_item(0).is_empty(), "filtered ability slot refuses a weapon")
	_expect(backpack.get_item(0) == "c3_hair", "backpack stores apparel")
	_expect(ItemContainer.transfer(backpack, 0, hotbar, 1) == false,
		"hotbar refuses apparel transfers")


func _check_player_designer_contract() -> void:
	var equipment := ItemContainer.new(ItemDB.SLOT_ORDER.size())
	for index in ItemDB.SLOT_ORDER.size():
		equipment.set_filter(index, ItemDB.SLOT_ORDER[index])
	var catalogue := ItemContainer.new(3, ["c3_hair", "sword", "c3_goggles"])

	var panel := PlayerDesignerPanel.new()
	panel.configure(
		equipment,
		catalogue,
		CharacterDB.DEFAULT_BODY,
		CharacterDB.default_skin(CharacterDB.DEFAULT_BODY),
		{},
		"Tester"
	)
	add_child(panel)
	panel.size = Vector2(720.0, 560.0)
	panel._layout_background()
	_expect(panel.find_child("DesignerTabs", true, false) != null
		and panel.find_child("DesignerEquippedSlots", true, false) != null
		and panel.find_child("DesignerSkinPicker", true, false) != null
		and panel.find_child("DesignerColourWheel", true, false) != null,
		"player designer has red Hero Design controls")
	var designer_name := panel.find_child(
		"DesignerName", true, false) as LineEdit
	_expect(designer_name != null
		and designer_name.max_length == NetworkManager.PLAYER_NAME_MAX_LENGTH,
		"player designer applies the twelve-character name cap")
	_expect(panel.find_child("StatsFrame", true, false) == null
		and panel.find_child("HotbarSlots", true, false) == null,
		"player designer omits stats and hotbar")
	var background := panel.find_child(
		"RotatedUIBackground2", true, false) as TextureRect
	_expect(background != null
		and background.texture == PlayerDesignerPanel.BACKGROUND
		and is_equal_approx(background.rotation, PI * 0.5),
		"player designer rotates ui_background2")

	panel.show_tab(PlayerDesignerPanel.Tab.APPAREL)
	_expect(panel.apparel_ids() == PackedStringArray(["c3_hair", "c3_goggles"]),
		"player designer catalogue contains apparel only")
	_expect(panel.find_child("SelectedItemDescription", true, false) == null,
		"player designer apparel has no description panel")
	var tile := panel.find_child(
		"DesignerApparel_c3_hair", true, false) as DesignerApparelTile
	_expect(tile != null and tile.hold_duration > 0.0,
		"designer apparel equips through a hold tile")
	if tile != null:
		tile.hold_completed.emit(tile)
		_expect(equipment.find("c3_hair") >= 0,
			"completed apparel hold equips on the body")
		tile.hold_completed.emit(tile)
		_expect(equipment.find("c3_hair") < 0,
			"completed hold on worn apparel unequips it")
	panel.queue_free()


func _check_character_schema() -> void:
	var defaults := CharacterDB.default_look()
	_expect((defaults["hotbar"] as Array).size() == CharacterDB.HOTBAR_SLOTS,
		"default hotbar has three slots")
	_expect((defaults["abilities"] as Array).size() == CharacterDB.ABILITY_SLOTS,
		"default abilities have two slots")
	_expect(defaults.has("backpack"), "default look carries backpack data")
	var old_look := {"rack": ["sword", "", "laser_rifle", "sword"]}
	_expect(CharacterDB.hotbar_items(old_look, 3) \
		== PackedStringArray(["sword", "", "laser_rifle"]),
		"old rack is a positional hotbar fallback")
	_expect(CharacterDB.racked_items(old_look, 3) \
		== CharacterDB.hotbar_items(old_look, 3),
		"racked_items remains a compatibility alias")


func _check_starter_inventory() -> void:
	# CharacterDB addresses the autoload directly. Swap in an isolated ConfigFile
	# while exercising the one-time seed, then restore both memory and disk.
	var saved_config: ConfigFile = SettingsManager._config
	SettingsManager._config = ConfigFile.new()
	SettingsManager._config.set_value(
		"appearance", "starter_inventory_revision", 0)

	var look := CharacterDB.default_look()
	look["worn"] = {"hat": "c3_hair"}
	look["backpack"] = ["c3_goggles"]
	CharacterDB._seed_starter_inventory(look)
	var backpack: Array = look.get("backpack", [])
	var worn: Dictionary = look.get("worn", {})
	var hotbar: Array = look.get("hotbar", [])
	# The settler wardrobe is larger than the backpack. The seed fills what
	# fits and leaves the rest to the wardrobe catalogue; it must not
	# duplicate anything it does grant.
	var owned := {}
	for item_id: String in backpack:
		_expect(not owned.has(item_id), "starter backpack does not duplicate %s" % item_id)
		owned[item_id] = true
	for item_id: Variant in worn.values():
		var worn_id := str(item_id)
		if worn_id.is_empty():
			continue
		_expect(not owned.has(worn_id), "starter does not wear a backpack duplicate")
		owned[worn_id] = true
	_expect(owned.has("c3_hair") and owned.has("c3_goggles"),
		"starter keeps the worn hair and carried goggles")
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		_expect(owned.has(item_id), "starter seed grants %s" % item_id)
	_expect(backpack.size() <= CharacterDB.BACKPACK_SLOTS,
		"starter seed does not overflow the backpack")
	for item_id: String in ItemDB.weapon_ids():
		_expect(hotbar.count(item_id) + backpack.count(item_id) == 1,
			"starter owns exactly one %s" % item_id)
	_expect(hotbar[0] == "sword" and hotbar[1] == "laser_rifle",
		"starter weapons fill open numbered slots")
	_expect(int(SettingsManager._config.get_value(
		"appearance", "starter_inventory_revision", 0))
		== CharacterDB.STARTER_INVENTORY_REVISION,
		"starter seed records its revision")

	# Once revised, removing an item is permanent: another load cannot manufacture
	# a dropped garment back into the backpack.
	backpack.erase("c3_boots")
	look["backpack"] = backpack
	CharacterDB._seed_starter_inventory(look)
	_expect(not (look["backpack"] as Array).has("c3_boots"),
		"completed starter seed does not resurrect removed ownership")

	# The first finite-inventory rollouts could leave an empty save marked as
	# complete. The current revision repairs that all-missing state from every
	# old marker and adds the weapons those revisions never granted.
	for old_revision: int in [1, 2, 3, 4]:
		SettingsManager._config = ConfigFile.new()
		SettingsManager._config.set_value(
			"appearance", "starter_inventory_revision", old_revision)
		var broken_look := CharacterDB.default_look()
		CharacterDB._seed_starter_inventory(broken_look)
		var repaired: Array = broken_look.get("backpack", [])
		var repaired_hotbar: Array = broken_look.get("hotbar", [])
		_expect(repaired.has("c3_hair"),
			"empty revision-%d save recovers Settler Hair" % old_revision)
		for item_id: String in CharacterDB.SETTLER_HEADWEAR:
			_expect(repaired.count(item_id) == 1,
				"empty revision-%d save recovers %s" % [old_revision, item_id])
		_expect(repaired.size() <= CharacterDB.BACKPACK_SLOTS,
			"empty revision-%d save stays inside the backpack" % old_revision)
		for item_id: String in ItemDB.weapon_ids():
			_expect(repaired_hotbar.count(item_id) == 1,
				"revision-%d save receives %s" % [old_revision, item_id])

	# A partial older wardrobe is real finite ownership. Advancing its marker
	# must not manufacture an individually removed garment.
	SettingsManager._config = ConfigFile.new()
	SettingsManager._config.set_value(
		"appearance", "starter_inventory_revision", 3)
	var partial_look := CharacterDB.default_look()
	partial_look["backpack"] = ["c3_hair"]
	CharacterDB._seed_starter_inventory(partial_look)
	_expect((partial_look["backpack"] as Array).has("c3_hair"),
		"partial older wardrobe keeps the garment it already owned")
	_expect(not (partial_look["backpack"] as Array).has("c3_tunic")
		and not (partial_look["backpack"] as Array).has("c3_boots")
		and not (partial_look["backpack"] as Array).has("c3_goggles"),
		"partial older wardrobe preserves removed apparel")
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		_expect((partial_look["backpack"] as Array).has(item_id),
			"revision-three wardrobe receives %s" % item_id)
	_expect((partial_look["hotbar"] as Array).has("sword")
		and (partial_look["hotbar"] as Array).has("laser_rifle"),
		"revision-three wardrobe receives both missing weapons")
	_expect(int(SettingsManager._config.get_value(
		"appearance", "starter_inventory_revision", 0))
		== CharacterDB.STARTER_INVENTORY_REVISION,
		"partial wardrobe advances the repair revision")

	# Revision four could preserve a wardrobe containing every settler garment
	# except the hair. Repair that known rollout omission without restoring other
	# apparel the player may genuinely have removed.
	SettingsManager._config = ConfigFile.new()
	SettingsManager._config.set_value(
		"appearance", "starter_inventory_revision", 4)
	var hairless_look := CharacterDB.default_look()
	hairless_look["hotbar"] = ["sword", "laser_rifle", ""]
	hairless_look["backpack"] = ["c3_goggles"]
	CharacterDB._seed_starter_inventory(hairless_look)
	_expect((hairless_look["backpack"] as Array).has("c3_goggles")
		and (hairless_look["backpack"] as Array).has("c3_hair"),
		"revision-four partial wardrobe receives missing Settler Hair")
	_expect(not (hairless_look["backpack"] as Array).has("c3_tunic")
		and not (hairless_look["backpack"] as Array).has("c3_boots"),
		"hair repair does not resurrect unrelated removed apparel")
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		_expect((hairless_look["backpack"] as Array).has(item_id),
			"revision-four wardrobe receives %s" % item_id)
	SettingsManager._config = saved_config


func _check_rack_migration() -> void:
	var manager := GameSettingsManager.new()
	manager._config = ConfigFile.new()
	manager._config.set_value("appearance", "body", "settler")
	manager._config.set_value("appearance", "skin", "clean_robotic")
	manager._config.set_value("appearance", "worn", {"hat": "c3_hair"})
	manager._config.set_value("appearance", "tints", {"body": "abcdef"})
	manager._config.set_value("appearance", "rack",
		["sword", "", "laser_rifle", "sword", "laser_rifle"])
	_expect(manager._migrate_loadout(), "old settings trigger loadout migration")
	_expect(manager._config.get_value("appearance", "hotbar", []) \
		== ["sword", "", "laser_rifle"], "rack slots one through three stay numbered")
	_expect(manager._config.get_value("appearance", "rack", []) \
		== ["sword", "", "laser_rifle"], "legacy rack mirrors the migrated hotbar")
	_expect(manager._config.get_value("appearance", "backpack", []) \
		== ["sword", "laser_rifle"], "rack overflow moves to the backpack")
	_expect(manager._config.get_value("appearance", "abilities", []).size() == 2,
		"migration creates both ability slots")
	_expect(manager._config.get_value("appearance", "skin", "") == "clean_robotic" \
		and manager._config.get_value("appearance", "worn", {}) == {"hat": "c3_hair"} \
		and manager._config.get_value("appearance", "tints", {}) == {"body": "abcdef"},
		"migration preserves existing appearance data")
	_expect(not manager._migrate_loadout(), "loadout migration is idempotent")
	manager.free()


## The two atmosphere toggles, as schema rather than as a picture.
##
## Here rather than in one of the rendering harnesses because none of it needs a
## frame drawn: what can go wrong is a key that does not exist, a default that
## ships off, an existing settings.cfg that never receives the new keys, and a
## shader global the toggle writes to that was never declared. All four are
## readable with no world loaded and therefore cost no launch.
func _check_graphics_toggles() -> void:
	var graphics: Dictionary = GameSettingsManager.DEFAULTS["graphics"]
	_expect(graphics.get("atmospheric_scattering", null) == true,
		"atmospheric scattering ships on")
	_expect(graphics.get("god_rays", null) == true, "god rays ship on")

	# A settings.cfg written before either effect existed. The default-fill path
	# has to hand it both keys without touching the choices already in it.
	var manager := GameSettingsManager.new()
	manager._config = ConfigFile.new()
	manager._config.set_value("graphics", "vsync", false)
	manager._config.set_value("graphics", "render_distance", 2)
	manager._apply_defaults()
	_expect(manager._config.get_value(
		"graphics", "atmospheric_scattering", null) == true,
		"legacy settings receive the scattering key")
	_expect(manager._config.get_value("graphics", "god_rays", null) == true,
		"legacy settings receive the god rays key")
	_expect(manager._config.get_value("graphics", "vsync", true) == false
		and int(manager._config.get_value("graphics", "render_distance", 1)) == 2,
		"filling the new keys leaves existing choices alone")
	manager.free()

	# `air_chroma` is written by `_apply_setting` and read by two shaders. An
	# undeclared global is not a silent no-op: both shaders fail to compile.
	_expect(ProjectSettings.get_setting("shader_globals/air_chroma") != null,
		"air_chroma is declared as a shader global")


## The depth thresholds [CelestialCycle] hands the god-rays shader, as ordering
## rather than as a picture.
##
## Here because getting this wrong is silent and expensive. The shader compares the
## depth buffer against these two numbers to decide how much air stands in front of
## each pixel, and the first attempt built them from the camera's own projection
## matrix — which is not the convention the depth buffer is written under. Every
## value came out negative, every pixel including the sky failed the comparison, and
## the effect rendered perfectly and drew nothing. No error, no warning, and a
## launch to find out.
##
## What can be checked without a GPU is the whole of what went wrong: the ordering
## against each other, against the two planes, and against the zero that an empty
## depth buffer holds.
func _check_god_rays_veil() -> void:
	var cycle := CelestialCycle.new()
	var rays := GodRaysEffect.new()
	cycle._god_rays = rays
	var camera := Camera3D.new()
	camera.near = 0.25
	camera.far = 48000.0
	var veil := cycle._veil_depths(camera)

	# Reverse-Z: the nearer plane is the larger number, and both sit strictly
	# inside the buffer's range. The projection-matrix version failed all three.
	_expect(veil.x > veil.y, "the near veil depth is the larger under reverse Z")
	_expect(veil.y > 0.0 and veil.x < 1.0,
		"both veil depths fall inside the depth buffer's range: %f, %f" % [
			veil.x, veil.y])
	# The one that matters most. An empty depth buffer holds zero, so the sky must
	# read as further away than the far veil or it receives no light at all — which
	# is precisely the failure this exists to catch.
	_expect(0.0 < veil.y, "sky depth is beyond the far veil and keeps full rays")

	# The planes themselves, which is what pins the mapping rather than merely
	# checking it is monotonic.
	rays.veil_near = camera.near
	rays.veil_far = camera.far
	var planes := cycle._veil_depths(camera)
	_expect(absf(planes.x - 1.0) < 0.001,
		"the near plane maps to a raw depth of one: %f" % planes.x)
	_expect(absf(planes.y) < 0.001,
		"the far plane maps to a raw depth of zero: %f" % planes.y)

	camera.free()
	cycle.free()


## The direct sun, its atmospheric halo and the compositor rays share one
## low-sun colour contract.
func _check_sunset_tint() -> void:
	var cycle := CelestialCycle.new()
	cycle._read_region_wheel()
	var base := Color(1.0, 0.94, 0.82)
	var axis := cycle._region_axis.normalized()
	var hint := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var side := axis.cross(hint).normalized()
	var front := axis.cross(side)
	var turn := TAU / (3.0 * maxf(absf(cycle._region_turns), 1.0))
	var elsewhere := Basis(axis, turn) * front

	var noon := cycle._sunset_tint(base, front, 1.0)
	_expect(noon.is_equal_approx(base),
		"high sun keeps the authored daytime glow colour")

	var first := cycle._sunset_tint(base, front, 0.0)
	var second := cycle._sunset_tint(base, elsewhere, 0.0)
	var first_rgb := Vector3(first.r, first.g, first.b)
	var second_rgb := Vector3(second.r, second.g, second.b)
	var base_rgb := Vector3(base.r, base.g, base.b)
	_expect(first_rgb.distance_to(base_rgb) > 0.05,
		"horizon sun changes from the daytime glow")
	_expect(first_rgb.distance_to(second_rgb) > 0.05,
		"different planet regions produce different sunset colours")

	cycle._air_chroma = 0.0
	var disabled := cycle._sunset_tint(base, front, 0.0)
	_expect(disabled.is_equal_approx(base),
		"disabling atmospheric scattering restores the fixed sun glow")
	cycle.free()


## Compiles both god-rays stages and reads back the compiler's own verdict.
##
## Worth having as a headless check because a GLSL error in a compositor effect is
## otherwise invisible until the pass silently does nothing in a running frame,
## and finding it that way costs a launch. The importer has already run glslang
## over these by the time this loads them, so this is asking for the result rather
## than doing the work.
func _check_god_rays_shaders() -> void:
	for entry: Dictionary in [
		{"path": GodRaysEffect.RAY_SHADER_PATH, "stages": [
			RenderingDevice.SHADER_STAGE_COMPUTE]},
		{"path": GodRaysEffect.COMPOSITE_SHADER_PATH, "stages": [
			RenderingDevice.SHADER_STAGE_VERTEX,
			RenderingDevice.SHADER_STAGE_FRAGMENT]},
	]:
		var path := String(entry["path"])
		var file := load(path) as RDShaderFile
		_expect(file != null, "%s imports as an RDShaderFile" % path.get_file())
		if file == null:
			continue
		_expect(file.base_error.is_empty(),
			"%s has no base error: %s" % [path.get_file(), file.base_error])
		var spirv := file.get_spirv()
		_expect(spirv != null, "%s has a default version" % path.get_file())
		if spirv == null:
			continue
		for stage: int in entry["stages"]:
			var error := spirv.get_stage_compile_error(stage)
			_expect(error.is_empty(), "%s stage %d compiles: %s" % [
				path.get_file(), stage, error])
			_expect(spirv.get_stage_bytecode(stage).size() > 0,
				"%s stage %d produced bytecode" % [path.get_file(), stage])


## Steam topology and the reference menu can be checked without opening a
## socket. The live callback path needs two Steam accounts, but these assertions
## keep IP fields from creeping back in, keep both supplied App IDs configured,
## and prove that hosting stops in a waiting room until the host presses Start.
func _check_steam_lobby_contract() -> void:
	_expect(ClassDB.class_exists("SteamMultiplayerPeer"),
		"GodotSteam supplies SteamMultiplayerPeer")
	_expect(SteamLobbyService.PLAYTEST_APP_ID == 5098060,
		"Steam Playtest App ID is configured")
	_expect(SteamLobbyService.FULL_GAME_APP_ID == 5098010,
		"full-game Steam App ID is retained for release")
	_expect(int(ProjectSettings.get_setting(
		"steam/initialization/app_data/app_type", -1)) == 2,
		"development builds select GodotSteam's Playtest app type")
	_expect(bool(ProjectSettings.get_setting(
		"steam/initialization/processes/initialize_on_startup", false))
		and not bool(ProjectSettings.get_setting(
			"steam/initialization/processes/embed_callbacks", true)),
		"Steam initializes before rendering and uses manual callback pumping")

	var saved_state := NetworkManager.state
	var saved_host := NetworkManager.is_host
	var saved_single_player := NetworkManager.is_single_player
	var saved_options := NetworkManager.session_options.duplicate(true)
	var saved_players := NetworkManager.players.duplicate(true)
	var saved_pending_invite := NetworkManager._pending_invite.duplicate(true)
	NetworkManager.state = NetworkManager.SessionState.IDLE
	NetworkManager.is_host = false
	NetworkManager.session_options.clear()
	NetworkManager.players.clear()

	var panel := LobbyPanel.new()
	add_child(panel)
	_expect(panel.find_child("LobbyTabs", true, false) != null,
		"online menu has Create and Join tabs")
	_expect(panel.find_child("LobbySettings", true, false) != null
		and panel.find_child("ModeCards", true, false) != null
		and panel.find_child("HostLobby", true, false) != null
		and panel.find_child("PlayerPortrait", true, false) != null,
		"Create tab has settings, mode cards, host portrait, and Host Lobby")
	var mode_title := panel.find_child("ModeTitle", true, false) as Label
	var mode_description := panel.find_child(
		"ModeDescription", true, false) as Label
	_expect(mode_title != null and mode_description != null
		and mode_title.get_theme_font_size(&"font_size") >= 17
		and mode_description.get_theme_font_size(&"font_size") == 12
		and mode_title.get_theme_font_size(&"font_size")
			> mode_description.get_theme_font_size(&"font_size")
		and mode_title.get_theme_color(&"font_color").is_equal_approx(
			LobbyPanel.MODE_GREEN)
		and mode_description.get_theme_color(&"font_color").is_equal_approx(
			Color(0.96, 0.98, 1.0)),
		"game-mode cards use large neon titles and compact white descriptions")
	_expect(NetworkManager._clean_name("ABCDEFGHIJKLMNO") == "ABCDEFGHIJKL",
		"player names are capped at twelve characters in the session model")

	panel._tab = LobbyPanel.Tab.JOIN
	panel._build_current()
	_expect(panel.find_child("LobbySearch", true, false) != null
		and panel.find_child("GameTypeFilter", true, false) != null
		and panel.find_child("PublicOnly", true, false) != null,
		"Join tab has search and both requested filters")
	_expect(panel.find_child("Address", true, false) == null,
		"Steam Join tab exposes no IP-address field")
	_expect(panel._is_valid_code("Moon42")
		and not panel._is_valid_code("bad password"),
		"private lobby passwords accept only the advertised safe format")
	var result_row := panel._make_lobby_row({
		"name": "Layout Test Lobby",
		"mode": "story",
		"players": 1,
		"max_players": 8,
		"visibility": "public",
		"lobby_id": 123,
	})
	var row_mode := result_row.find_child("LobbyRowMode", true, false) as Label
	var row_players := result_row.find_child(
		"LobbyRowPlayers", true, false) as Label
	var row_access := result_row.find_child(
		"LobbyRowAccess", true, false) as Label
	var row_join := result_row.find_child("JoinLobby", true, false) as Button
	_expect(row_mode != null and row_mode.custom_minimum_size.x >= 112.0
		and row_players != null and row_players.custom_minimum_size.x >= 96.0
		and row_access != null and row_access.custom_minimum_size.x >= 86.0
		and row_join != null and row_join.custom_minimum_size.x >= 84.0
		and row_mode.autowrap_mode == TextServer.AUTOWRAP_OFF
		and row_players.autowrap_mode == TextServer.AUTOWRAP_OFF
		and row_access.autowrap_mode == TextServer.AUTOWRAP_OFF,
		"lobby results reserve readable unwrapped metadata columns")
	result_row.free()

	NetworkManager.state = NetworkManager.SessionState.LOBBY
	NetworkManager.is_host = true
	NetworkManager.session_options = {
		"name": "Test Lobby",
		"visibility": "private",
		"code": "Moon42",
		"max_players": 8,
		"mode": "duels",
		"duels_mode": "battle",
	}
	NetworkManager.players = {
		1: {"name": "Host", "peer_id": 1, "steam_id": 123},
		2: {"name": "Guest", "peer_id": 2, "steam_id": 456},
	}
	panel._build_current()
	_expect(panel.find_child("RosterScroll", true, false) != null
		and panel.find_child("InviteFriends", true, false) != null
		and panel.find_child("StartLobby", true, false) != null,
		"hosted view has scrolling roster, Steam invite, and Start")
	var lobby_back := panel.find_child("Back", true, false) as Button
	_expect(lobby_back != null
		and panel.find_child("LeaveLobby", true, false) == null,
		"hosted view uses Back instead of a separate Leave button")
	_expect(not NetworkManager._shared_session_options().has("code"),
		"host never sends its private password back to clients")
	_expect(NetworkManager._unique_player_name("Host") == "Host 1",
		"duplicate lobby names receive a stable numeric suffix")

	panel._tab = LobbyPanel.Tab.JOIN
	panel._visibility = "private"
	panel._private_code = "Moon42"
	panel._max_players = 4
	panel._selected_mode = "duels"
	panel._selected_duels_mode = "race"
	NetworkManager._pending_invite = {"lobby_id": 123}
	var close_events := {"count": 0}
	panel.closed.connect(func() -> void:
		close_events["count"] = int(close_events["count"]) + 1
	)
	if lobby_back != null:
		lobby_back.pressed.emit()
	_expect(NetworkManager.state == NetworkManager.SessionState.IDLE
		and not NetworkManager.is_host
		and NetworkManager.session_options.is_empty()
		and NetworkManager.players.is_empty()
		and NetworkManager._pending_invite.is_empty()
		and int(close_events["count"]) == 1,
		"Back leaves the hosted lobby and requests the home screen")
	_expect(panel._tab == LobbyPanel.Tab.CREATE
		and panel._visibility == "public"
		and panel._private_code.is_empty()
		and panel._max_players == 8
		and panel._selected_mode == "story"
		and panel._selected_duels_mode == "battle",
		"leaving a hosted game resets the Online page to Create defaults")

	remove_child(panel)
	panel.free()
	NetworkManager.players = saved_players
	NetworkManager.session_options = saved_options
	NetworkManager._pending_invite = saved_pending_invite
	NetworkManager.is_single_player = saved_single_player
	NetworkManager.is_host = saved_host
	NetworkManager.state = saved_state


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("loadout_model_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("loadout_model_test: FAIL  %s" % message)


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
		push_error("loadout_model_test: could not restore %s" % path)
		return
	file.store_buffer(_settings_bytes)
	file.close()
