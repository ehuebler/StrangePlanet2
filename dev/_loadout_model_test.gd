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
	_check_hat_gem_ownership()
	_check_rack_migration()
	_check_skin_migration()
	_check_graphics_toggles()
	_check_god_rays_shaders()
	_check_god_rays_veil()
	_check_sunset_tint()
	_check_starfield_isotropy()
	_check_night_ground_glow()
	_check_steam_lobby_contract()
	_check_player_designer_contract()
	_check_cape_cloth()
	_check_home_preview_fill()
	_check_meta_upgrades()
	_check_achievements()
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
	_expect(SurfaceSkin.outline_color({}).is_equal_approx(SurfaceSkin.CAMERA_RIM_COLOR),
		"missing outline tint keeps the authored green rim")
	var rim_override := Color(1.0, 0.12, 0.28)
	SurfaceSkin.set_rim_color(material, rim_override)
	var tinted_rim: Variant = material.get_shader_parameter(&"camera_rim_color")
	_expect(tinted_rim is Color and (tinted_rim as Color).is_equal_approx(rim_override),
		"outline tint recolours the player camera rim")
	SurfaceSkin.set_rim_color(ordinary, rim_override)
	var ordinary_rim: Variant = ordinary.get_shader_parameter(&"camera_rim_color")
	_expect(ordinary_rim is Color and (ordinary_rim as Color).is_equal_approx(Color.BLACK),
		"outline tint does not light an ordinary item rim")
	_expect(SurfaceSkin.outline_color({
			SurfaceSkin.TINT_OUTLINE: rim_override,
		}).is_equal_approx(rim_override),
		"outline tint accepts a Color already in the look")
	var stored := SurfaceSkin.outline_color({
		SurfaceSkin.TINT_OUTLINE: "ff1e47",
	})
	_expect(stored.r > 0.9 and stored.g < 0.2 and stored.b > 0.2,
		"saved outline tint parses from the look dictionary")


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
	CrawlerMeta.begin_test({})
	var equipment := ItemContainer.new(ItemDB.SLOT_ORDER.size())
	for index in ItemDB.SLOT_ORDER.size():
		equipment.set_filter(index, ItemDB.SLOT_ORDER[index])
	var catalogue := ItemContainer.new(
		5,
		["c3_hair", "sword", "c3_party_hat", "crawler_plain_cape", "crawler_fool_hat"]
	)

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
	CrtType.dress_tree(panel)
	_expect(panel.find_child("DesignerTabs", true, false) != null
		and panel.find_child("DesignerEquippedSlots", true, false) != null
		and panel.find_child("DesignerSkinPicker", true, false) != null
		and panel.find_child("DesignerColourWheel", true, false) != null
		and panel.find_child("DesignerTintSelector", true, false) != null
		and panel.find_child("DesignerOutlineSelector", true, false) != null
		and panel.find_child("DesignerCharacter_settler", true, false) != null
		and panel.find_child("DesignerHatColourWheel", true, false) != null
		and panel.find_child("DesignerCapeColourWheel", true, false) != null,
		"player designer has red Character controls")
	var noct_face := panel.find_child(
		"DesignerCharacterFace", true, false) as TextureRect
	var noct_title := panel.find_child(
		"DesignerCharacterTitle", true, false) as Label
	var face_crt := CrtType.host_of(noct_face)
	_expect(panel.find_child("DesignerCharacter_pioneer", true, false) == null
			and noct_title != null and noct_title.text == "NOCT"
			and noct_face != null and noct_face.texture != null
			and face_crt != null and face_crt.chromatic() > 0.5,
		"character selector offers one Noct tile with a CRT face")
	var noct_trait := panel.find_child(
		"DesignerCharacterTrait", true, false) as Label
	var noct_ability := panel.find_child(
		"DesignerCharacterAbility", true, false) as TextureRect
	var noct_juke := panel.find_child(
		"DesignerCharacterJuke", true, false) as TextureRect
	_expect(noct_trait != null and noct_trait.text.contains("2%"),
		"Noct tile shows the per-level damage trait")
	_expect(noct_ability != null and noct_ability.texture != null,
		"Noct tile shows a laser eyes starting-ability icon")
	var juke_host := CrtType.host_of(noct_juke)
	var ability_host := CrtType.host_of(noct_ability)
	_expect(noct_juke != null and noct_juke.texture != null
			and juke_host != null and ability_host != null
			and juke_host.get_parent() == ability_host.get_parent()
			and juke_host.get_index() < ability_host.get_index(),
		"Noct tile shows a juke icon beside laser eyes")
	var banner := false
	for node: Node in panel.find_children("*", "Label", true, false):
		var copy := node as Label
		if copy != null and copy.text.contains("LOCKED HATS COST GEMS"):
			banner = true
	_expect(not banner, "hats catalogue has no hold-to-equip banner")
	var apparel_frame := panel.find_child(
		"DesignerApparelCatalogueFrame", true, false) as Control
	var hat_tint := panel.find_child(
		"DesignerHatTintFrame", true, false) as Control
	var cape_frame := panel.find_child(
		"DesignerCapeCatalogueFrame", true, false) as Control
	var cape_tint := panel.find_child(
		"DesignerCapeTintFrame", true, false) as Control
	var hero_tint := panel.find_child(
		"DesignerAppearanceFrame", true, false) as Control
	_expect(apparel_frame != null and hat_tint != null
			and is_equal_approx(apparel_frame.size_flags_stretch_ratio, 3.0)
			and is_equal_approx(hat_tint.size_flags_stretch_ratio, 1.0)
			and cape_frame != null and cape_tint != null
			and is_equal_approx(cape_frame.size_flags_stretch_ratio, 3.0)
			and is_equal_approx(cape_tint.size_flags_stretch_ratio, 1.0)
			and hero_tint != null
			and is_equal_approx(hero_tint.size_flags_stretch_ratio, 1.0),
		"hat, cape, and character tint strips share the lower quarter")
	var tint_mode := panel.find_child(
		"DesignerTintSelector", true, false) as Button
	var outline_mode := panel.find_child(
		"DesignerOutlineSelector", true, false) as Button
	var wheel := panel.find_child(
		"DesignerColourWheel", true, false) as ColourWheel
	var caption := panel.find_child(
		"DesignerTintTarget", true, false) as Label
	var aimed: Array[String] = []
	panel.tint_picked.connect(func(target: String, _colour: Color) -> void:
		aimed.append(target)
	)
	_expect(tint_mode != null and outline_mode != null and wheel != null,
		"character tint strip offers tint and outline selectors")
	if outline_mode != null and wheel != null:
		outline_mode.pressed.emit()
		_expect(caption != null and caption.text.contains("OUTLINE"),
			"outline selector aims the colour wheel at the player rim")
		wheel.picked.emit(Color(1.0, 0.2, 0.35))
	if tint_mode != null and wheel != null:
		tint_mode.pressed.emit()
		_expect(caption != null and caption.text.contains("SKIN"),
			"tint selector returns the colour wheel to the player skin")
		wheel.picked.emit(Color(0.2, 0.45, 0.9))
	_expect(aimed.size() == 2
			and aimed[0] == PlayerDesignerPanel.TINT_OUTLINE
			and aimed[1] == PlayerDesignerPanel.TINT_BODY,
		"tint and outline selectors switch what the wheel paints")
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
	_expect(panel.apparel_ids() == PackedStringArray(["c3_hair"]),
		"player designer catalogue lists owned hats only")
	_expect(panel.find_child("DesignerApparel_c3_party_hat", true, false) == null,
		"locked hats stay out of the character creator")
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
	CrawlerMeta.begin_test({"gems": 80})
	panel.toggle_apparel("c3_party_hat")
	_expect(equipment.find("c3_party_hat") < 0
			and not CrawlerMeta.owns_hat("c3_party_hat"),
		"the character creator cannot unlock hats")
	panel.show_tab(PlayerDesignerPanel.Tab.CAPES)
	_expect(panel.cape_ids().is_empty()
			and panel.find_child("DesignerCape_crawler_plain_cape", true, false) == null,
		"locked capes stay out of the character creator")
	panel.toggle_apparel("crawler_plain_cape")
	_expect(equipment.find("crawler_plain_cape") < 0
			and not CrawlerMeta.owns_cape("crawler_plain_cape"),
		"the character creator cannot unlock capes")
	CrawlerMeta.end_test()
	panel.queue_free()


func _check_home_preview_fill() -> void:
	var home := HomeScreen.new()
	home._build_camera()
	var camera := home.find_child("MenuCamera", true, false) as Camera3D
	var fill := home.find_child("PreviewFillLight", true, false) as SpotLight3D
	_expect(camera != null and fill != null and fill.get_parent() == camera
			and fill.light_energy > 0.0
			and fill.spot_range >= 4.0
			and not fill.shadow_enabled,
		"home screen lights the preview from the front")
	_expect(HomeScreen.preview_fill_energy(0.0) > HomeScreen.preview_fill_energy(1.0)
			and HomeScreen.preview_fill_energy(0.0) >= 4.0,
		"home face fill is stronger after the sun is gone")
	home.free()


func _check_cape_cloth() -> void:
	var cape := CapeCloth.new()
	add_child(cape)
	cape._axis_right = Vector3.RIGHT
	cape._axis_back = Vector3.FORWARD
	cape._axis_down = Vector3.DOWN
	for row in range(1, CapeCloth.ROWS):
		var y := -CapeCloth.LENGTH * float(row) / float(CapeCloth.ROWS - 1)
		for col in CapeCloth.COLS:
			var index := cape._index(col, row)
			cape._pos[index] = Vector3(0.0, y, 0.04)
			cape._prev[index] = cape._pos[index]
	cape._cache_pose()
	for _pass in 12:
		cape._solve_constraints()
	var hem := CapeCloth.ROWS - 1
	var span := cape._pos[cape._index(0, hem)].distance_to(
		cape._pos[cape._index(CapeCloth.COLS - 1, hem)])
	_expect(span > CapeCloth.WIDTH * 0.35,
		"cape constraints uncrumple a folded hem")
	cape._commit_mesh()
	_expect(cape.cloth_mesh() != null and cape.cloth_mesh().mesh != null
			and cape.cloth_mesh().mesh.get_surface_count() > 0,
		"the cape keeps a reusable cloth mesh")
	cape.queue_free()


func _check_meta_upgrades() -> void:
	CrawlerMeta.begin_test({"gems": 2000})
	_expect(CrawlerMeta.gems() == 2000,
		"meta test payload starts with 2000 gems")
	_expect(CrawlerMeta.upgrade_price_for_rank(0) == 100
			and CrawlerMeta.upgrade_price_for_rank(4) == 500
			and CrawlerMeta.upgrade_price_for_rank(5) == 1000,
		"home upgrades cost 100, then 200 through 500, then double")
	_expect(is_equal_approx(CrawlerMeta.gem_drop_chance(0.0), 0.25)
			and is_equal_approx(CrawlerMeta.gem_drop_chance(80.0), 0.50)
			and CrawlerMeta.gem_drop_chance(1.0) > 0.25,
		"kill gems start at 25 percent and luck can raise them to 50")
	_expect(CrawlerMeta.hat_price("c3_party_hat") == 500
			and CrawlerMeta.cape_price("crawler_plain_cape") == 1000,
		"home hats cost 500 gems and capes cost 1000")
	_expect(CharacterDB.playable_ids().size() >= 6,
		"character selector offers more than the settler")
	_expect(str(CharacterDB.character_trait(CharacterDB.DEFAULT_BODY).get("id", ""))
			== CharacterDB.TRAIT_LEVEL_DAMAGE
			and CharacterDB.character_trait("pioneer").is_empty(),
		"Noct has the per-level damage trait and aliases do not inherit it")
	_expect(is_equal_approx(
			CharacterDB.level_damage_bonus(CharacterDB.DEFAULT_BODY, 1),
			CharacterDB.LEVEL_DAMAGE_SHARE)
			and is_equal_approx(
			CharacterDB.level_damage_bonus(CharacterDB.DEFAULT_BODY, 5),
			CharacterDB.LEVEL_DAMAGE_SHARE * 5.0),
		"Noct gains two percent damage with every level")
	_expect(CharacterDB.starting_abilities(CharacterDB.DEFAULT_BODY).has("laser_eyes"),
		"Noct starts with laser eyes")
	_expect(CrawlerMeta.shop_stats() == PackedStringArray(CrawlerProgress.LEVEL_STATS),
		"the gem shop lists every in-run player stat")
	var shop := MetaUpgradesPanel.new()
	add_child(shop)
	var grid := shop.find_child("UpgradeStatRows", true, false)
	_expect(grid is GridContainer and (grid as GridContainer).columns == 2,
		"Unlocks upgrades sit in a two-column grid")
	_expect(not (shop.find_child("UpgradeStatScroll", true, false) is ScrollContainer),
		"Unlocks upgrades do not use a scroll box")
	_expect(shop.get_combined_minimum_size().y <= 648.0,
		"Unlocks upgrades fit the 720p framed host without scrolling")
	for stat_id: String in CrawlerProgress.LEVEL_STATS:
		_expect(shop.find_child("UpgradeRow_%s" % stat_id, true, false) != null,
			"gem shop draws a row for %s" % stat_id)
		_expect(CrawlerMeta.upgrade_price(stat_id) > 0,
			"gems can buy a permanent %s rank" % stat_id)
	shop.queue_free()
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_HEALTH),
		"gems buy a permanent health rank")
	_expect(CrawlerMeta.rank_of(CrawlerProgress.STAT_HEALTH) == 1,
		"bought health rank is stored")
	_expect(CrawlerMeta.gems() == 2000 - CrawlerMeta.upgrade_price_for_rank(0),
		"buying a rank spends the listed gem price")
	var scratch := CrawlerProgress.new()
	var trait_row: Dictionary = {}
	if not scratch.hero_stat_rows().is_empty() \
			and scratch.hero_stat_rows()[0] is Dictionary:
		trait_row = scratch.hero_stat_rows()[0]
	_expect(str(trait_row.get("id", "")) == CrawlerProgress.TRAIT_LEVEL_DAMAGE
			and str(trait_row.get("kind", "")) == "trait"
			and str(trait_row.get("text", "")).contains("2%"),
		"player stats open with the Noct level-damage trait")
	_expect(is_equal_approx(CharacterDB.LEVEL_DAMAGE_SHARE,
			CrawlerProgress.TRAIT_DAMAGE_PER_LEVEL),
		"Noct trait numbers stay in agreement")
	_expect(is_equal_approx(scratch.damage_scale(),
			1.0 + CrawlerProgress.TRAIT_DAMAGE_PER_LEVEL),
		"Noct damage starts two percent above the base")
	scratch.level = 5
	_expect(is_equal_approx(scratch.damage_scale(),
			1.0 + CrawlerProgress.TRAIT_DAMAGE_PER_LEVEL * 5.0),
		"Noct damage grows two percent with each level")
	scratch.level = 1
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_DAMAGE).begins_with("1"),
		"hero Damage is the flat player base added to each hit")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_HEALTH).contains("(+"),
		"permanent ranks appear beside the base health stat")
	_expect(is_zero_approx(scratch.dodge_chance()),
		"dodge starts at no chance")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_DODGE),
		"gems buy a permanent dodge rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_DODGE).contains("(+"),
		"permanent dodge ranks appear beside the base dodge stat")
	_expect(is_equal_approx(scratch.dodge_chance(), CrawlerRules.upgrade_boost(1)),
		"one gem dodge rank is five percent")
	scratch.ranks[CrawlerProgress.STAT_DODGE] = 20
	_expect(is_equal_approx(scratch.dodge_chance(), CrawlerProgress.DODGE_MAX),
		"dodge chance stops at the cap")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_DODGE),
		"a bought dodge rank can be refunded")
	_expect(is_zero_approx(scratch.defense_share()),
		"defense starts at no reduction")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_DEFENSE),
		"gems buy a permanent defense rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_DEFENSE).contains("(+"),
		"permanent defense ranks appear beside the base defense stat")
	_expect(is_equal_approx(scratch.defense_share(), CrawlerRules.upgrade_boost(1)),
		"one gem defense rank is five percent")
	scratch.ranks[CrawlerProgress.STAT_DEFENSE] = 20
	_expect(is_equal_approx(scratch.defense_share(), CrawlerProgress.DEFENSE_MAX),
		"defense reduction stops at the cap")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_DEFENSE),
		"a bought defense rank can be refunded")
	_expect(is_equal_approx(scratch.juke_cooldown(),
			CrawlerProgress.JUKE_COOLDOWN_BASE),
		"juke starts at the full cooldown")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_JUKE),
		"gems buy a permanent juke rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_JUKE).contains("("),
		"permanent juke ranks appear beside the base cooldown")
	_expect(scratch.juke_cooldown() < CrawlerProgress.JUKE_COOLDOWN_BASE,
		"one gem juke rank shortens the dash wait")
	scratch.ranks[CrawlerProgress.STAT_JUKE] = ceili(
		(CrawlerProgress.JUKE_COOLDOWN_BASE - CrawlerProgress.JUKE_COOLDOWN_MIN)
		/ CrawlerProgress.JUKE_COOLDOWN_PER_RANK)
	_expect(is_equal_approx(scratch.juke_cooldown(),
			CrawlerProgress.JUKE_COOLDOWN_MIN),
		"juke cooldown stops at the floor")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_JUKE),
		"a bought juke rank can be refunded")
	_expect(is_equal_approx(scratch.juke_distance(),
			CrawlerProgress.JUKE_DISTANCE_BASE),
		"juke distance starts at the authored dash")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_JUKE_DISTANCE),
		"gems buy a permanent juke distance rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_JUKE_DISTANCE).contains("("),
		"permanent juke distance ranks appear beside the base dash")
	_expect(is_equal_approx(scratch.juke_distance(),
			CrawlerProgress.JUKE_DISTANCE_BASE
				+ CrawlerProgress.JUKE_DISTANCE_PER_RANK),
		"one gem juke distance rank adds eight tenths of a metre")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_JUKE_DISTANCE),
		"a bought juke distance rank can be refunded")
	_expect(is_equal_approx(scratch.knockback_scale(), 1.0),
		"knockback starts at 1X")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_KNOCKBACK),
		"gems buy a permanent knockback rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_KNOCKBACK).contains("("),
		"permanent knockback ranks appear beside the base multiplier")
	_expect(is_equal_approx(scratch.knockback_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one gem knockback rank is five percent")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_KNOCKBACK),
		"a bought knockback rank can be refunded")
	_expect(is_equal_approx(scratch.range_scale(), 1.0),
		"range starts at 1X")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_RANGE),
		"gems buy a permanent range rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_RANGE).contains("("),
		"permanent range ranks appear beside the base multiplier")
	_expect(is_equal_approx(scratch.range_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one gem range rank is five percent")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_RANGE),
		"a bought range rank can be refunded")
	_expect(is_equal_approx(scratch.cast_trim(), 0.0),
		"cast starts with no stand-still trim")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_CAST),
		"gems buy a permanent cast rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_CAST).contains("("),
		"permanent cast ranks appear beside the base stand")
	_expect(is_equal_approx(scratch.cast_trim(), CrawlerProgress.CAST_PER_RANK),
		"one gem cast rank trims a tenth of a second")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_CAST),
		"a bought cast rank can be refunded")
	_expect(is_equal_approx(scratch.elemental_scale(), 1.0),
		"elemental starts at 1X")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_ELEMENTAL),
		"gems buy a permanent elemental rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_ELEMENTAL).contains("("),
		"permanent elemental ranks appear beside the base multiplier")
	_expect(is_equal_approx(scratch.elemental_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one gem elemental rank is five percent")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_ELEMENTAL),
		"a bought elemental rank can be refunded")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_LUCK),
		"gems buy a permanent luck rank")
	_expect(CrawlerMeta.rank_of(CrawlerProgress.STAT_LUCK) == 1,
		"bought luck rank is stored")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_LUCK).contains("("),
		"permanent luck ranks appear beside the base luck stat")
	_expect(CrawlerProgress.rarity_weights(scratch.luck_rank())[3]
			> CrawlerProgress.rarity_weights(0.0)[3],
		"shop luck raises legendary level-up odds")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_LUCK),
		"a bought luck rank can be refunded")
	_expect(is_equal_approx(scratch.gold_scale(), 1.0),
		"gold gain starts at 1X")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_GOLD),
		"gems buy a permanent gold rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_GOLD).contains("("),
		"permanent gold ranks appear beside the base multiplier")
	_expect(is_equal_approx(scratch.gold_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one gem gold rank is five percent")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_GOLD),
		"a bought gold rank can be refunded")
	_expect(is_equal_approx(scratch.xp_scale(), 1.0),
		"XP gain starts at 1X")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_XP),
		"gems buy a permanent XP rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_XP).contains("("),
		"permanent XP ranks appear beside the base multiplier")
	_expect(is_equal_approx(scratch.xp_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one gem XP rank is five percent")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_XP),
		"a bought XP rank can be refunded")
	_expect(is_equal_approx(scratch.gem_scale(), 1.0),
		"gem gain starts at 1X")
	_expect(CrawlerMeta.buy_rank(CrawlerProgress.STAT_GEMS),
		"gems buy a permanent gem rank")
	_expect(scratch.hero_stat_text(CrawlerProgress.STAT_GEMS).contains("("),
		"permanent gem ranks appear beside the base multiplier")
	_expect(is_equal_approx(scratch.gem_scale(),
			CrawlerRules.upgrade_scale(1)),
		"one gem gem rank is five percent")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_GEMS),
		"a bought gem rank can be refunded")
	_expect(CrawlerMeta.refund_rank(CrawlerProgress.STAT_HEALTH),
		"a bought rank can be refunded")
	_expect(CrawlerMeta.rank_of(CrawlerProgress.STAT_HEALTH) == 0
		and CrawlerMeta.gems() == 2000,
		"refund restores the gems spent on that rank")
	var hats := MetaUpgradesPanel.new()
	hats.opening_tab = MetaUpgradesPanel.Tab.HATS
	add_child(hats)
	_expect(hats.find_child("UplocksTab_Hats", true, false) != null
			and hats.find_child("HatRow_c3_party_hat", true, false) != null
			and CrawlerMeta.shop_hats().has("c3_party_hat"),
		"Unlocks Hats tab lists catalogue hats")
	var hat_buy := hats.find_child(
		"HatBuy_c3_party_hat", true, false) as Button
	_expect(hat_buy != null, "Unlocks Hats tab has a buy button")
	if hat_buy != null:
		hat_buy.pressed.emit()
	_expect(CrawlerMeta.owns_hat("c3_party_hat"),
		"buying a hat from Unlocks spends gems and unlocks it")
	hats.queue_free()
	var carry := CrawlerProgress.new()
	_expect(not carry.seed_look_hat({"worn": {"hat": "c3_party_hat"}}).is_empty()
			and carry.worn_hat == "c3_party_hat"
			and carry.owns_hat("c3_party_hat"),
		"the creator hat is granted to a new crawler run")
	CrawlerMeta.begin_test({"gems": 2000, "hats": [CrawlerProgress.HAT_ID]})
	var gale := CrawlerProgress.new()
	gale.seed_look_hat({"worn": {"hat": CrawlerProgress.HAT_ID}})
	_expect(gale.owns_hat(CrawlerProgress.HAT_ID)
			and gale.hat_effect_rank(CrawlerProgress.FX_FLIGHT) > 0
			and gale.hat_effect_rank(CrawlerProgress.FX_DEX) > 0,
		"an equipped city hat carries its effect into the run")
	CrawlerMeta.begin_test({"gems": 2000})
	var capes := MetaUpgradesPanel.new()
	capes.opening_tab = MetaUpgradesPanel.Tab.CAPES
	add_child(capes)
	_expect(capes.find_child("UplocksTab_Capes", true, false) != null
			and capes.find_child("CapeRow_crawler_plain_cape", true, false) != null
			and CrawlerMeta.shop_capes() == PackedStringArray([
				"crawler_plain_cape", "crawler_gold_cape"
			]),
		"Unlocks Capes tab lists the plain cape and the gold cape")
	var cape_buy := capes.find_child(
		"CapeBuy_crawler_plain_cape", true, false) as Button
	_expect(cape_buy != null, "Unlocks Capes tab has a buy button")
	if cape_buy != null:
		cape_buy.pressed.emit()
	_expect(CrawlerMeta.owns_cape("crawler_plain_cape"),
		"buying a cape from Unlocks spends gems and unlocks it")
	capes.queue_free()
	var players := MetaUpgradesPanel.new()
	players.opening_tab = MetaUpgradesPanel.Tab.PLAYERS
	add_child(players)
	_expect(players.find_child("UplocksTab_Players", true, false) != null
			and players.find_child("UplocksPlayerHost", true, false) != null
			and players.find_child("UplocksPlayerHost", true, false).visible
			and players.find_child("UplocksPlayerHost", true, false).get_child_count() == 0,
		"Unlocks Players tab is present and empty")
	players.queue_free()
	var cloak := CrawlerProgress.new()
	_expect(not cloak.seed_look_cape({
				"worn": {"cape": "crawler_plain_cape"}
			}).is_empty()
			and cloak.worn_cape == "crawler_plain_cape"
			and cloak.owns_cape("crawler_plain_cape"),
		"the creator cape carries into a new crawler run")
	CrawlerMeta.begin_test({"gems": 2000})
	_expect(CrawlerMeta.refund_all_hats() == 0
			and CrawlerMeta.owns_hat("c3_hair"),
		"refund all hats does nothing when only free hats are owned")
	_expect(CrawlerMeta.unlock_hat("c3_party_hat")
			and CrawlerMeta.unlock_cape("crawler_plain_cape"),
		"gems buy a hat and a cape for refund")
	var refund_shop := MetaUpgradesPanel.new()
	add_child(refund_shop)
	refund_shop.show_tab(MetaUpgradesPanel.Tab.HATS)
	var refund_btn := refund_shop.find_child(
		"UpgradeRefundAll", true, false) as Button
	_expect(refund_btn != null and refund_btn.visible
			and refund_btn.text.contains("HAT")
			and not refund_btn.disabled,
		"Hats tab offers refund all")
	refund_btn.pressed.emit()
	_expect(not CrawlerMeta.owns_hat("c3_party_hat")
			and CrawlerMeta.owns_hat("c3_hair")
			and CrawlerMeta.owns_cape("crawler_plain_cape"),
		"hat refund all returns bought hats and keeps free hair")
	_expect(CrawlerMeta.gems() == 2000 - CrawlerMeta.CAPE_GEM_PRICE,
		"hat refund all returns hat gems only")
	refund_shop.show_tab(MetaUpgradesPanel.Tab.CAPES)
	refund_btn = refund_shop.find_child("UpgradeRefundAll", true, false) as Button
	_expect(refund_btn != null and refund_btn.visible
			and refund_btn.text.contains("CAPE")
			and not refund_btn.disabled,
		"Capes tab offers refund all")
	refund_btn.pressed.emit()
	_expect(not CrawlerMeta.owns_cape("crawler_plain_cape")
			and CrawlerMeta.gems() == 2000,
		"cape refund all returns cape gems")
	refund_shop.show_tab(MetaUpgradesPanel.Tab.PLAYERS)
	refund_btn = refund_shop.find_child("UpgradeRefundAll", true, false) as Button
	_expect(refund_btn != null and refund_btn.visible and refund_btn.disabled
			and refund_btn.text.contains("PLAYER"),
		"Players tab offers refund all")
	refund_shop.show_tab(MetaUpgradesPanel.Tab.STATS)
	refund_btn = refund_shop.find_child("UpgradeRefundAll", true, false) as Button
	_expect(refund_btn != null and refund_btn.visible
			and refund_btn.text.contains("UPGRADE"),
		"Unlocks tab still offers refund all upgrades")
	refund_shop.queue_free()
	CrawlerMeta.end_test()


func _check_achievements() -> void:
	CrawlerMeta.begin_test()
	Journal.begin_test()
	var journal := Journal.new()
	_expect(JournalDB.has_entry("kill_10_mobs"),
		"kill 10 mobs is a catalogued achievement")
	_expect(JournalDB.gems_of("kill_10_mobs") == 5,
		"kill 10 mobs unlocks five gems")
	_expect(journal.note_kill(9).is_empty() and not journal.is_done("kill_10_mobs"),
		"nine kills do not finish the achievement")
	var unlocked := journal.note_kill(1)
	_expect(unlocked.has("kill_10_mobs") and journal.is_done("kill_10_mobs"),
		"the tenth kill completes kill 10 mobs")
	_expect(CrawlerMeta.gems() == 0,
		"completing does not pay claimable gems until the reward is claimed")
	_expect(CrawlerMeta.global_xp() == JournalDB.xp_of("kill_10_mobs"),
		"kill 10 mobs pays global XP immediately")
	_expect(journal.can_claim("kill_10_mobs"),
		"the menu can claim a finished gem reward")
	var board := AchievementsPanel.new()
	add_child(board)
	var claim_button := board.find_child("AchievementClaim_kill_10_mobs", true, false) as Button
	_expect(claim_button != null and claim_button.visible and claim_button.text == "CLAIM",
		"the achievements menu shows CLAIM on an unclaimed reward")
	if claim_button != null:
		claim_button.pressed.emit()
	journal.load_progress()
	_expect(CrawlerMeta.gems() == 5, "claiming from the menu grants five gems")
	_expect(journal.is_claimed("kill_10_mobs") and not journal.can_claim("kill_10_mobs"),
		"claimed gems stay claimed")
	_expect(board.find_child("AchievementClaim_kill_10_mobs", true, false) == null,
		"CLAIM is gone after the reward is taken")
	_expect(not journal.claim("kill_10_mobs"), "a reward cannot be claimed twice")
	_expect(CrawlerMeta.gems() == 5, "a second claim pays nothing")
	_expect(journal.complete("see_vacationers_landing"),
		"a quest can sit beside the combat achievement")
	journal.reset_achievements()
	_expect(not journal.is_done("kill_10_mobs") and journal.kills() == 0,
		"reset achievements clears combat progress")
	_expect(not journal.is_claimed("kill_10_mobs"),
		"reset achievements clears claimed rewards")
	_expect(journal.is_done("see_vacationers_landing"),
		"reset achievements leaves quests alone")
	CrawlerMeta.begin_test()
	Journal.begin_test()
	journal = Journal.new()
	_expect(CrawlerMeta.title_for(1) == "Newbie"
			and CrawlerMeta.title_for(4) == "Newbie"
			and CrawlerMeta.title_for(5) == "Recruit",
		"global titles advance every five levels from Newbie")
	_expect(not CrawlerMeta.sandbox_unlocked(),
		"sandbox starts locked")
	var city := journal.note_city()
	_expect(city.has("first_city") and journal.is_done("first_city"),
		"reaching a city completes First City")
	_expect(CrawlerMeta.sandbox_unlocked(),
		"First City unlocks sandbox")
	_expect(CrawlerMeta.gems() == 10 and CrawlerMeta.global_xp() == 100,
		"First City pays ten gems and 100 XP immediately")
	_expect(JournalDB.instant_reward_lines("first_city").has("Sandbox Mode")
			and JournalDB.instant_reward_lines("first_city").has("10 Gems")
			and JournalDB.instant_reward_lines("first_city").has("100 XP"),
		"First City lists sandbox, gems, and XP as instant rewards")
	_expect(not journal.can_claim("first_city"),
		"First City gems are not a claimable menu reward")
	CrawlerMeta.begin_test()
	Journal.begin_test()
	journal = Journal.new()
	var need := 0
	for at in range(1, 5):
		need += CrawlerMeta.xp_needed(at)
	CrawlerMeta.add_xp(need)
	var ranked := journal.note_global_level(CrawlerMeta.global_level())
	_expect(CrawlerMeta.global_level() == 5 and CrawlerMeta.title() == "Recruit",
		"360 expedition XP reaches global level 5")
	_expect(ranked.has("reach_global_5") and journal.is_done("reach_global_5"),
		"level 5 completes the Recruit achievement")
	_expect(CrawlerMeta.gems() == 10 and not journal.can_claim("reach_global_5"),
		"level 5 pays ten gems immediately")
	board.queue_free()
	Journal.end_test()
	CrawlerMeta.end_test()


func _check_character_schema() -> void:
	var defaults := CharacterDB.default_look()
	_expect((defaults["hotbar"] as Array).size() == CharacterDB.HOTBAR_SLOTS,
		"default hotbar has three slots")
	_expect((defaults["abilities"] as Array).size() == CharacterDB.ABILITY_SLOTS,
		"default abilities have four slots")
	_expect(defaults.has("backpack"), "default look carries backpack data")
	var old_look := {"rack": ["sword", "", "laser_rifle", "sword"]}
	_expect(CharacterDB.hotbar_items(old_look, 3) \
		== PackedStringArray(["sword", "", "laser_rifle"]),
		"old rack is a positional hotbar fallback")
	_expect(CharacterDB.racked_items(old_look, 3) \
		== CharacterDB.hotbar_items(old_look, 3),
		"racked_items remains a compatibility alias")
	_expect(str(defaults["skin"]) == "noct_crimson",
		"the settler default look is Noct Crimson")
	_expect(CharacterDB.skin_ids(CharacterDB.DEFAULT_BODY).has("noct_crimson")
			and CharacterDB.skin_texture(
				CharacterDB.DEFAULT_BODY, "noct_crimson") != null,
		"Noct Crimson is a selectable settler texture")


func _check_starter_inventory() -> void:
	# CharacterDB addresses the autoload directly. Swap in an isolated ConfigFile
	# while exercising the one-time seed, then restore both memory and disk.
	var saved_config: ConfigFile = SettingsManager._config
	SettingsManager._config = ConfigFile.new()
	SettingsManager._config.set_value(
		"appearance", "starter_inventory_revision", 0)

	var look := CharacterDB.default_look()
	look["worn"] = {"hat": "c3_hair"}
	look["backpack"] = ["c3_party_hat"]
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
	_expect(owned.has("c3_hair") and not owned.has("c3_party_hat"),
		"starter keeps free hair and drops an unbought catalogue hat")
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		_expect(not owned.has(item_id),
			"fresh starter leaves %s locked for gems" % item_id)
	_expect(backpack.size() <= CharacterDB.BACKPACK_SLOTS,
		"starter seed does not overflow the backpack")
	for item_id: String in ItemDB.weapon_ids():
		_expect(hotbar.count(item_id) + backpack.count(item_id) == 0,
			"starter no longer grants %s" % item_id)
	_expect(int(SettingsManager._config.get_value(
		"appearance", "starter_inventory_revision", 0))
		== CharacterDB.STARTER_INVENTORY_REVISION,
		"starter seed records its revision")

	# Once revised, removing an item is permanent: another load cannot manufacture
	# a dropped garment back into the backpack.
	backpack.erase("c3_party_hat")
	look["backpack"] = backpack
	CharacterDB._seed_starter_inventory(look)
	_expect(not (look["backpack"] as Array).has("c3_party_hat"),
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
			_expect(not repaired.has(item_id),
				"empty revision-%d save leaves %s locked for gems" % [
					old_revision, item_id])
		_expect(repaired.size() <= CharacterDB.BACKPACK_SLOTS,
			"empty revision-%d save stays inside the backpack" % old_revision)
		for item_id: String in ItemDB.weapon_ids():
			_expect(repaired_hotbar.count(item_id) == 0,
				"revision-%d save does not receive %s" % [old_revision, item_id])

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
		_expect(not (partial_look["backpack"] as Array).has(item_id),
			"revision-three wardrobe leaves %s locked for gems" % item_id)
	_expect(not (partial_look["hotbar"] as Array).has("sword")
		and not (partial_look["hotbar"] as Array).has("laser_rifle"),
		"revision-three wardrobe does not receive weapons")
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
	hairless_look["backpack"] = ["c3_party_hat"]
	CharacterDB._seed_starter_inventory(hairless_look)
	_expect((hairless_look["backpack"] as Array).has("c3_hair"),
		"revision-four partial wardrobe receives missing Settler Hair")
	_expect(not (hairless_look["backpack"] as Array).has("c3_party_hat")
		and not (hairless_look["backpack"] as Array).has("c3_tunic")
		and not (hairless_look["backpack"] as Array).has("c3_boots"),
		"hair repair does not resurrect unbought catalogue hats")
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		_expect(not (hairless_look["backpack"] as Array).has(item_id),
			"revision-four wardrobe leaves %s locked for gems" % item_id)
	SettingsManager._config = saved_config


func _check_hat_gem_ownership() -> void:
	var dumped: Array = []
	for item_id: String in CharacterDB.SETTLER_HEADWEAR:
		dumped.append(item_id)
	for item_id: String in CharacterDB.SETTLER_HEADWEAR_MORE:
		dumped.append(item_id)
	dumped.append("crawler_gale_hat")
	CrawlerMeta.begin_test({"hats": dumped})
	_expect(CrawlerMeta.owns_hat("c3_party_hat"),
		"a grant dump still lists catalogue hats before forget")
	_expect(CrawlerMeta.forget_granted_catalogue_hats(),
		"a complete free-hat grant dump is forgotten")
	_expect(not CrawlerMeta.owns_hat("c3_party_hat"),
		"granted catalogue hats are not gem-owned")
	_expect(CrawlerMeta.owns_hat("crawler_gale_hat"),
		"hats bought outside the grant dump stay owned")
	_expect(CrawlerMeta.owns_hat("c3_hair"),
		"free starter hair stays owned")

	CrawlerMeta.begin_test({"hats": ["c3_party_hat", "crawler_gale_hat"]})
	_expect(not CrawlerMeta.forget_granted_catalogue_hats()
			and CrawlerMeta.owns_hat("c3_party_hat"),
		"a short bought hat list is not treated as a grant dump")

	CrawlerMeta.begin_test({})
	CrawlerMeta.note_owned_apparel({
		"worn": {"hat": "c3_party_hat"},
		"backpack": ["c3_party_hat"],
	})
	_expect(not CrawlerMeta.owns_hat("c3_party_hat"),
		"wearing or carrying a hat does not unlock it")
	CrawlerMeta.note_owned_apparel({
		"worn": {"cape": "crawler_plain_cape"},
	})
	_expect(CrawlerMeta.owns_cape("crawler_plain_cape"),
		"wearing a cape still notes cape ownership")

	var saved_config: ConfigFile = SettingsManager._config
	SettingsManager._config = ConfigFile.new()
	SettingsManager._config.set_value(
		"appearance", "starter_inventory_revision", 8)
	CrawlerMeta.begin_test({"hats": dumped})
	var dumped_look := CharacterDB.default_look()
	dumped_look["worn"] = {"hat": "c3_party_hat"}
	dumped_look["backpack"] = ["c3_party_hat", "crawler_gale_hat"]
	CharacterDB._seed_starter_inventory(dumped_look)
	_expect(not CrawlerMeta.owns_hat("c3_party_hat")
			and CrawlerMeta.owns_hat("crawler_gale_hat"),
		"revision eight forgets the hat grant dump and keeps bought hats")
	_expect(not (dumped_look["backpack"] as Array).has("c3_party_hat")
			and (dumped_look["backpack"] as Array).has("crawler_gale_hat")
			and str((dumped_look["worn"] as Dictionary).get("hat", "")).is_empty(),
		"revision eight removes unbought dump hats from the look")
	_expect(int(SettingsManager._config.get_value(
		"appearance", "starter_inventory_revision", 0))
		== CharacterDB.STARTER_INVENTORY_REVISION,
		"hat ownership repair advances the starter revision")
	SettingsManager._config = saved_config
	CrawlerMeta.end_test()


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
	_expect(manager._config.get_value("appearance", "abilities", []).size() == 4,
		"migration creates four ability slots")
	_expect(manager._config.get_value("appearance", "skin", "") == "clean_robotic" \
		and manager._config.get_value("appearance", "worn", {}) == {"hat": "c3_hair"} \
		and manager._config.get_value("appearance", "tints", {}) == {"body": "abcdef"},
		"migration preserves existing appearance data")
	_expect(not manager._migrate_loadout(), "loadout migration is idempotent")
	manager.free()


func _check_skin_migration() -> void:
	var manager := GameSettingsManager.new()
	manager._config = ConfigFile.new()
	manager._config.set_value("appearance", "skin", "luke")
	manager._config.set_value("appearance", "default_skin_revision", 1)
	_expect(manager._migrate_default_skin(),
		"the previous default triggers a skin migration")
	_expect(str(manager._config.get_value("appearance", "skin", "")) == "noct_crimson",
		"Luke becomes Noct Crimson once")
	_expect(not manager._migrate_default_skin(), "skin migration is idempotent")
	manager._config.set_value("appearance", "skin", "clean_robotic")
	manager._config.set_value("appearance", "default_skin_revision", 1)
	_expect(manager._migrate_default_skin()
			and str(manager._config.get_value("appearance", "skin", "")) \
				== "clean_robotic",
		"an explicit later skin choice is left alone")
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
	_expect(graphics.get("ui_glitch", null) == true, "UI glitch ships on")

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
	_expect(manager._config.get_value("graphics", "ui_glitch", null) == true,
		"legacy settings receive the UI glitch key")
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


func _check_starfield_isotropy() -> void:
	var code := FileAccess.get_file_as_string(
		"res://shaders/vivid/vivid_space.gdshader")
	_expect(code.contains("vec3 star_frame(vec3 direction, vec3 seed)")
			and code.contains("star_layer(direction, star_densities.x, star_size, star_fill,")
			and code.contains("vec3(0.22, 1.00, 0.48)")
			and code.contains("vec3(0.41, 0.87, 0.23)"),
		"star layers sit in different frames so cube-grid rings do not stack")


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
		and panel._selected_mode == "crawler"
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
