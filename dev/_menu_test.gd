extends Node

## Deterministic verification for the in-game Red Tab Menu.
##
##     godot --headless --path . dev/_menu_test.tscn
##
## The harness drives the same input and Control signals a player uses, counts
## every failed expectation, and restores the settings file byte-for-byte.

const WORLD: PackedScene = preload("res://game/world.tscn")
const SHOT_DIR := "res://dev/captures"
const SETTINGS_PATH := "user://settings.cfg"

var _failures := 0
var _world: GameWorld
var _player: OnlinePlayer
var _isolated_leave_count := 0
var _isolated_respawn_count := 0

var _settings_existed := false
var _settings_bytes := PackedByteArray()
var _saved_players: Dictionary
var _saved_state: int
var _saved_single_player := false
var _saved_host := false
var _saved_time_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_settings()
	_saved_players = NetworkManager.players.duplicate(true)
	_saved_state = int(NetworkManager.state)
	_saved_single_player = NetworkManager.is_single_player
	_saved_host = NetworkManager.is_host
	_saved_time_scale = Engine.time_scale

	# Icon rendering is not under test. Supplying process-local placeholders keeps
	# the dummy renderer away from material-instance APIs in headless runs.
	if DisplayServer.get_name() == "headless":
		for item_id: String in ItemDB.ITEMS:
			ItemIcons._cache[item_id] = ImageTexture.new()

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players.clear()
	NetworkManager.players[1] = {"name": "Menu Harness", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME

	_world = WORLD.instantiate() as GameWorld
	add_child(_world)
	_player = await _wait_for_player()
	if _player == null:
		_expect(false, "world spawns a local player")
		await _finish()
		return
	_expect(_world.celestial_cycle != null
		and _world.celestial_cycle.phase() < 0.01,
		"gameplay resets the home-screen sunset to full daylight")
	_player.display_name = "Menu Harness"
	await _check_ability_test_site()
	await _check_grapple_at_test_site()

	await _run()
	await _finish()


func _check_ability_test_site() -> void:
	# Long enough that an unguarded CharacterBody would fall far through terrain
	# that has not streamed near any player yet.
	await _wait_frames(90)
	var landing := _world.get_node_or_null("Planet/VacationersLanding") as Landmark
	var site := _world.get_node_or_null(
		"Planet/AbilityTestingSite") as Landmark
	var dummies: Array[TrainingDummy] = []
	if site != null:
		for child: Node in site.get_children():
			if child is TrainingDummy:
				dummies.append(child as TrainingDummy)
	var span := landing.global_position.distance_to(site.global_position) \
		if landing != null and site != null else 0.0
	_expect(landing != null and site != null
		and span >= 185.0 and span <= 215.0,
		"the marked Ability Test Site is about 200 m from Vacationer's Landing")
	_expect(site != null and site.waypoint
		and site.show_beyond <= 12.0 and site.hide_beyond >= 1000.0
		and site.get_node_or_null("Beacon") != null,
		"the testing site has both a HUD waypoint and a visible beacon")
	var placed := dummies.size() == 3
	for dummy in dummies:
		placed = placed and dummy.global_position.distance_to(
			site.global_position) <= 8.0 \
			and dummy.is_in_group(DamageHit.COMBATANT_GROUP)
	_expect(placed,
		"three respawning combat dummies stand together on the testing pad")
	var flowers := _world.get_node_or_null(
		"Planet/LandingFlowers") as GroundCover
	var grass := _world.get_node_or_null("Planet/GlobalGrass") as GroundCover
	var trees := _world.get_node_or_null(
		"Planet/LandingFlowerTrees") as FlowerTreeField
	var site_direction := site.direction.normalized() if site != null \
		else Vector3.ZERO
	var vegetation_clear := flowers != null and grass != null and trees != null \
		and site_direction in flowers._keep_outs \
		and site_direction in grass._keep_outs
	if trees != null:
		for stood in trees._trees:
			var tree_direction := (
				trees.transform * stood.origin).normalized()
			vegetation_clear = vegetation_clear \
				and tree_direction.angle_to(site_direction) * trees._radius \
					>= trees.keep_back
	_expect(vegetation_clear,
		"the practice pad clears flowers, grass, and giant trees")


func _check_grapple_at_test_site() -> void:
	var planet := _world.get_node_or_null("Planet") as Planet
	var site := _world.get_node_or_null(
		"Planet/AbilityTestingSite") as AbilityTestSite
	var dummy := _world.get_node_or_null(
		"Planet/AbilityTestingSite/TrainingDummy") as TrainingDummy
	if not _expect(planet != null and site != null and dummy != null,
			"the Grapple check finds the marked site's centre dummy"):
		return
	var restore_transform := _player.global_transform
	var restore_pitch := _player._pitch
	var near := dummy.global_position - site.global_basis.z * 2.0
	var direction := planet.to_local(near).normalized()
	var up := (planet.global_basis * direction).normalized()
	var at := planet.to_global(
		planet.shape.surface_point(direction, planet.finest_spacing())
			+ direction * 0.3)
	var toward := dummy.combat_position() - at
	var flat := toward - up * toward.dot(up)
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	_player.global_transform = Transform3D(
		Basis.looking_at(flat.normalized(), up), at)
	_player.velocity = Vector3.ZERO
	_player._pitch = asin(clampf(
		(dummy.combat_position() - _player.camera.global_position)
			.normalized().dot(up), -1.0, 1.0))
	_player.head.rotation.x = _player._pitch
	_player.reset_network_state(_player.global_transform)
	_player.reset_physics_interpolation()
	_player.abilities.set_item(0, "grapple")
	await _wait_frames(12)

	var origin := _player.global_position
	var launch_up := up
	var dispatched := _player.activate_ability(0)
	# This is the ordinary click that used to cancel a client before approval.
	_player.release_ability(0)
	var started := _player.grapple_active_or_pending()
	var highest := 0.0
	var completed := false
	for _frame in 360:
		await get_tree().physics_frame
		highest = maxf(highest,
			(_player.global_position - origin).dot(launch_up))
		if started and not _player.grapple_active_or_pending():
			completed = true
			break
	_expect(dispatched and started and completed and highest >= 18.0
		and dummy.can_be_grappled(),
		"Grapple quick-click carries the site dummy 20 m and completes its slam")
	await _wait_frames(60)
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	_player.global_transform = restore_transform
	_player.velocity = Vector3.ZERO
	_player._pitch = restore_pitch
	_player.head.rotation.x = restore_pitch
	_player.reset_network_state(restore_transform)
	_player.reset_physics_interpolation()
	await _wait_frames(4)


func _run() -> void:
	await _check_open_and_close_policy()

	await _tap_action(&"inventory")
	await _wait_frames(4)
	var menu := _menu()
	if not _expect(menu != null, "Tab reopens the menu for page checks"):
		return

	await _check_hero(menu)
	await _check_apparel(menu)
	await _check_items_and_abilities(menu)
	await _check_data_settings_and_admin(menu)
	await _check_graphics_toggle_rows(menu)
	await _check_isolated_leave_hold()
	await _check_isolated_respawn_hold()
	await _check_drop_round_trip(menu)


func _check_open_and_close_policy() -> void:
	await _tap_action(&"inventory")
	await _wait_frames(4)
	var menu := _menu()
	_expect(menu != null, "Tab opens GameMenu")
	if menu != null:
		_expect(menu.current_tab() == GameMenu.Tab.HERO,
			"Tab opens the Hero page")
	_expect(get_tree().paused, "single-player world pauses while menu is open")
	_expect(_world.locally_paused(), "world records the local menu pause")
	_expect(not _player.controls_enabled, "menu disables player controls")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"menu releases a visible mouse")
	var paused_phase := _world.celestial_cycle.phase()
	_world._flora_confirm_left = 3.0
	await _wait_frames(8)
	_expect(is_zero_approx(Engine.time_scale)
		and not _world.can_process()
		and not _player.can_process()
		and not _world.celestial_cycle.is_processing(),
		"single-player menu freezes inherited simulation and the real-time sun")
	_expect(is_equal_approx(_world.celestial_cycle.phase(), paused_phase)
		and is_equal_approx(_world._flora_confirm_left, 3.0),
		"single-player menu advances no celestial or world timer time")
	if menu != null:
		var shell := menu.find_child("InsetMenuShell", true, false) as Control
		var background := menu.find_child(
			"MenuBackground", true, false) as TextureRect
		var outer_border := menu.find_child(
			"MenuBackgroundBorder", true, false) as RedGlowPanel
		var content := menu.find_child("ContentFrame", true, false) as Control
		var selector := menu.find_child("BottomSelector", true, false) as Control
		var hero_tab := menu.find_child("TabHero", true, false) as Control
		var data_tab := menu.find_child("TabData", true, false) as Control
		var actions := menu.find_child("SessionActions", true, false) as Control
		var close_button := menu.find_child("CloseAction", true, false) as Button
		var settings_button := menu.find_child(
			"SettingsAction", true, false) as Button
		var leave_button := menu.find_child(
			"LeaveAction", true, false) as HoldActionButton
		var respawn_button := menu.find_child(
			"RespawnAction", true, false) as HoldActionButton
		var viewport_rect := get_viewport().get_visible_rect()
		var shell_rect := shell.get_global_rect() if shell != null else Rect2()
		var edge_gaps := Vector4(
			shell_rect.position.x - viewport_rect.position.x,
			shell_rect.position.y - viewport_rect.position.y,
			viewport_rect.end.x - shell_rect.end.x,
			viewport_rect.end.y - shell_rect.end.y
		)
		_expect(shell != null and edge_gaps.x >= GameMenu.EDGE_GAP - 1.0
			and edge_gaps.y >= GameMenu.EDGE_GAP - 1.0
			and edge_gaps.z >= GameMenu.EDGE_GAP - 1.0
			and edge_gaps.w >= GameMenu.EDGE_GAP - 1.0,
			"Tab menu leaves the live world visible around every edge")
		_expect(background != null
			and background.texture == GameMenu.MENU_BACKGROUND
			and background.stretch_mode == TextureRect.STRETCH_SCALE
			and background.get_global_rect().position.distance_to(
				shell_rect.position) <= 1.0
			and background.get_global_rect().size.distance_to(
				shell_rect.size) <= 1.0,
			"menu background fits the inset shell without cover-cropping")
		_expect(outer_border != null
			and outer_border.border_color.is_equal_approx(
				Color(GameMenu.GREEN, 0.98))
			and outer_border.get_global_rect().position.distance_to(
				shell_rect.position) <= 1.0
			and outer_border.get_global_rect().size.distance_to(
				shell_rect.size) <= 1.0,
			"Tab menu draws a green border around UI Background 2")
		_expect(content != null and actions != null
			and actions.get_global_rect().position.y
				>= content.get_global_rect().end.y,
			"session actions sit below the expanded main page")
		_expect(content != null and selector != null
			and selector.get_global_rect().position.y
				- content.get_global_rect().end.y >= 6.0,
			"bottom tab selector leaves a visible gap beneath the main page")
		_expect(selector != null and hero_tab != null and data_tab != null
			and absf(
				hero_tab.get_global_rect().position.y
					- selector.get_global_rect().position.y
				- (selector.get_global_rect().end.y
					- data_tab.get_global_rect().end.y)
			) <= 1.5,
			"bottom tab selector balances the gaps above Hero and below Data")
		_expect(hero_tab != null and hero_tab.size.y <= 24.0,
			"bottom tab bars stay compact enough for both outer gaps")
		var close_style := (
			close_button.get_theme_stylebox(&"normal") as StyleBoxFlat
			if close_button != null else null
		)
		var settings_style := (
			settings_button.get_theme_stylebox(&"normal") as StyleBoxFlat
			if settings_button != null else null
		)
		_expect(close_style != null and settings_style != null
			and close_style.corner_radius_top_left >= 24
			and settings_style.corner_radius_top_left >= 24
			and leave_button != null and leave_button.circular
			and respawn_button != null and respawn_button.circular,
			"Close, Settings, Hold Respawn, and Hold Leave use circular icon keys")
		var close_glyph := close_button.find_child(
			"Glyph", true, false) as Control if close_button != null else null
		var settings_glyph := settings_button.find_child(
			"Glyph", true, false) as Control if settings_button != null else null
		var leave_glyph := leave_button.find_child(
			"Glyph", true, false) as Control if leave_button != null else null
		_expect(_centres_match(close_button, close_glyph),
			"Close glyph is centered inside its circular key")
		_expect(_centres_match(settings_button, settings_glyph),
			"Settings glyph is centered inside its circular key")
		_expect(_centres_match(leave_button, leave_glyph),
			"Hold Leave glyph is centered inside its circular key")
		var respawn_glyph := respawn_button.find_child(
			"Glyph", true, false) as Control if respawn_button != null else null
		_expect(_centres_match(respawn_button, respawn_glyph),
			"Hold Respawn glyph is centered inside its circular key")
		_expect(respawn_button != null and leave_button != null
			and respawn_button.get_global_rect().end.x
				<= leave_button.get_global_rect().position.x + 1.0,
			"Hold Respawn sits to the left of Hold Leave")
		_expect(_children_have_even_horizontal_gaps(actions),
			"session action keys use even horizontal spacing")

	await _tap_action(&"inventory")
	await _wait_frames(4)
	_expect(_menu() == null, "Tab closes the open menu")
	_expect(not get_tree().paused and not _world.locally_paused(),
		"Tab close resumes the single-player world")
	_expect(is_equal_approx(Engine.time_scale, _saved_time_scale)
		and _world.celestial_cycle.is_processing(),
		"Tab close restores shader time and the celestial clock")
	_expect(_player.controls_enabled, "Tab close restores player controls")
	_expect_captured_mouse("Tab close captures the mouse")

	await _tap_action(&"pause")
	await _wait_frames(4)
	menu = _menu()
	_expect(menu != null and menu.current_tab() == GameMenu.Tab.SETTINGS,
		"Escape opens directly on Settings")
	_expect(get_tree().paused and is_zero_approx(Engine.time_scale)
		and not _world.can_process(),
		"Escape freezes the complete single-player simulation")
	var escape_shell := (
		menu.find_child("InsetMenuShell", true, false) as Control
		if menu != null else null
	)
	var escape_rect := escape_shell.get_global_rect() if escape_shell != null else Rect2()
	var escape_viewport_rect := get_viewport().get_visible_rect()
	_expect(escape_shell != null
		and escape_rect.position.x - escape_viewport_rect.position.x
			>= GameMenu.EDGE_GAP - 1.0
		and escape_rect.position.y - escape_viewport_rect.position.y
			>= GameMenu.EDGE_GAP - 1.0
		and escape_viewport_rect.end.x - escape_rect.end.x
			>= GameMenu.EDGE_GAP - 1.0
		and escape_viewport_rect.end.y - escape_rect.end.y
			>= GameMenu.EDGE_GAP - 1.0,
		"Escape menu leaves the live world visible around every edge")
	await _tap_action(&"pause")
	await _wait_frames(4)
	_expect(_menu() == null, "Escape closes the open menu")
	_expect(not get_tree().paused and _player.controls_enabled,
		"Escape close restores pause and control policy")
	_expect(is_equal_approx(Engine.time_scale, _saved_time_scale),
		"Escape close restores simulation time")


func _check_hero(menu: GameMenu) -> void:
	_clear_loadout()
	menu.show_tab(GameMenu.Tab.HERO)
	await _wait_frames(4)
	var page := _active_page(menu) as RedHeroPage
	if not _expect(page != null, "Hero routes to RedHeroPage"):
		return

	var hero_name := page.find_child("HeroName", true, false) as Label
	_expect(hero_name != null and hero_name.text == "MENU HARNESS",
		"Hero shows the current player name")
	var preview := page.find_child("CharacterPreview", true, false)
	_expect(preview is RedCharacterPreview,
		"Hero owns a CharacterPreview control")
	var character_frame := page.find_child(
		"CharacterFrame", true, false) as Control
	var apparel_frame := page.find_child("ApparelFrame", true, false) as Control
	var hotbar_frame := page.find_child("HotbarFrame", true, false) as Control
	_expect(character_frame != null and apparel_frame != null
		and hotbar_frame != null
		and apparel_frame.get_global_rect().position.x
			>= character_frame.get_global_rect().end.x
		and hotbar_frame.get_global_rect().position.x
			>= character_frame.get_global_rect().end.x,
		"Hero places horizontal Apparel and Hotbar rows right of the character screen")

	var stat_rows := page.find_child("StatRows", true, false)
	_expect(stat_rows != null
		and stat_rows.get_child_count() == PlayerStats.ids().size(),
		"Hero draws one row for every stat")
	for id_text: String in PlayerStats.ids():
		var value := page.find_child("Stat_%s_Value" % id_text, true, false) as Label
		_expect(value != null and value.text.is_valid_float(),
			"Hero stat %s has a numeric value" % id_text)
	var stats_frame := page.find_child("StatsFrame", true, false) as Control
	var stats_toggle := page.find_child("StatsToggle", true, false) as Button
	var stats_glyph := page.find_child("StatsGlyph", true, false) as Control
	_expect(stats_frame != null and stats_toggle != null
		and not stats_frame.visible,
		"Hero stats begin hidden inside the character screen")
	_expect(_centres_match(stats_toggle, stats_glyph),
		"Hero Stats icon is centered in its circular key")
	if stats_toggle != null:
		stats_toggle.pressed.emit()
		await _wait_frames(2)
		_expect(stats_frame.visible
			and character_frame.get_global_rect().encloses(
				stats_frame.get_global_rect()),
			"Hero Stats button opens the in-screen stats overlay")
		await _capture("menu_hero_stats")
		stats_toggle.pressed.emit()
		await _wait_frames(1)
		_expect(not stats_frame.visible,
			"Hero Stats button closes the stats overlay")

	var hotbar_root := page.find_child("HotbarSlots", true, false)
	var hotbar_slots: Array[RedItemSlot] = []
	if hotbar_root != null:
		for child: Node in hotbar_root.get_children():
			if child is RedItemSlot:
				hotbar_slots.append(child as RedItemSlot)
	var badges := PackedStringArray()
	for slot: RedItemSlot in hotbar_slots:
		badges.append(slot.badge)
	_expect(hotbar_slots.size() == 5
		and badges == PackedStringArray(["LMB", "RMB", "1", "2", "3"]),
		"Hero exposes five logical LMB/RMB/1/2/3 tiles")
	var apparel_root := page.find_child("ApparelSlots", true, false) as Control
	_expect(_children_have_even_horizontal_gaps(apparel_root)
		and _children_have_even_horizontal_gaps(hotbar_root),
		"Hero Apparel and Hotbar icons use even horizontal spacing")
	var empty_icons_centred := apparel_root != null
	if apparel_root != null:
		for child: Node in apparel_root.get_children():
			if child is RedItemSlot:
				var empty_glyph := child.find_child(
					"EmptyGlyph_*", true, false) as Control
				empty_icons_centred = empty_icons_centred \
					and _centres_match(child as Control, empty_glyph)
	_expect(empty_icons_centred,
		"Hero empty Apparel glyphs are centered in their slots")
	for tab_name: String in [
		"TabHero",
		"TabApparel",
		"TabItems",
		"TabAbilities",
		"TabData",
	]:
		var tab_button := menu.find_child(tab_name, true, false) as Button
		var glyph_lane := (
			tab_button.find_child("GlyphLane", true, false) as Control
			if tab_button != null
			else null
		)
		var glyph := (
			tab_button.find_child("Glyph", true, false) as Control
			if tab_button != null
			else null
		)
		var style := (
			tab_button.get_theme_stylebox(&"normal") as StyleBoxFlat
			if tab_button != null
			else null
		)
		_expect(tab_button != null and glyph_lane != null and glyph != null
			and style != null
			and glyph_lane.get_global_rect().encloses(glyph.get_global_rect())
			and glyph_lane.get_global_rect().get_center().distance_to(
				glyph.get_global_rect().get_center()) <= 1.0
			and style.content_margin_left >= glyph_lane.size.x + 4.0,
			"%s centers its icon in an evenly spaced glyph lane" % tab_name)
	await _capture("menu_hero")


func _check_apparel(menu: GameMenu) -> void:
	_player.equipment.clear()
	_player.backpack.clear()
	_player.backpack.set_item(0, "c3_hair")
	# Exercise the cold-cache path: a first visit still needs a visible symbol
	# while the mesh photograph is rendering.
	ItemIcons._cache.erase("c3_hair")
	menu.show_tab(GameMenu.Tab.APPAREL)
	await _wait_frames(4)
	var page := _active_page(menu) as RedCataloguePage
	if not _expect(page != null, "Apparel routes to RedCataloguePage"):
		return

	var owned := _owned_slots(page)
	var listed: PackedStringArray = PackedStringArray()
	for slot: RedItemSlot in owned:
		var listed_id := slot.item_id()
		if not listed_id.is_empty() and not listed.has(listed_id):
			listed.append(listed_id)
	_expect(listed.has("c3_hair"),
		"Apparel still lists the physically owned garment")
	_expect(listed.has("c3_party_hat") and listed.has("c3_bunny_ears"),
		"Apparel lists body-wardrobe hats that are not in the backpack")
	var hair_owned := _red_slot(page, _player.backpack, 0)
	_expect(hair_owned != null and hair_owned.item_id() == "c3_hair",
		"physically owned Settler Hair keeps its backpack slot in the catalogue")
	var filter_row := page.find_child(
		"CatalogueFilters", true, false) as Control
	var filters_centred := filter_row != null
	if filter_row != null:
		for child: Node in filter_row.get_children():
			if not child is Button:
				continue
			var lane := child.find_child("GlyphLane", true, false) as Control
			var glyph := child.find_child("Glyph", true, false) as Control
			filters_centred = filters_centred and lane != null \
				and glyph != null \
				and lane.get_global_rect().encloses(glyph.get_global_rect()) \
				and _centres_match(lane, glyph)
	_expect(filters_centred and _children_have_even_horizontal_gaps(filter_row),
		"catalogue filter icons are centered and evenly spaced")
	var detail_frame := page.find_child(
		"PersistentDetailFrame", true, false) as Control
	var detail_scroll := page.find_child(
		"PersistentDetailScroll", true, false) as Control
	var detail_title := page.find_child(
		"SelectedItemTitle", true, false) as Control
	var detail_state := page.find_child(
		"SelectedItemState", true, false) as Control
	var detail_description := page.find_child(
		"SelectedItemDescription", true, false) as Control
	var equip_action := page.find_child("EquipAction", true, false) as Control
	var drop_action := page.find_child("DropAction", true, false) as Control
	_expect(detail_frame != null and equip_action != null and drop_action != null
		and detail_frame.get_global_rect().encloses(equip_action.get_global_rect())
		and detail_frame.get_global_rect().encloses(drop_action.get_global_rect()),
		"Apparel keeps Equip and Drop visible inside the persistent detail panel")
	_expect(equip_action != null and drop_action != null
		and equip_action.size.y <= 36.0 and drop_action.size.y <= 36.0,
		"catalogue Equip and Drop actions stay compact")
	_expect(detail_scroll != null and detail_title != null and detail_state != null
		and detail_description != null
		and detail_scroll.get_global_rect().encloses(detail_title.get_global_rect())
		and detail_scroll.get_global_rect().encloses(detail_state.get_global_rect())
		and detail_scroll.get_global_rect().encloses(
			detail_description.get_global_rect()),
		"Apparel shows selected item identity and detail without scrolling")
	var total_before := _count_physical("c3_hair")
	var backpack_slot := _red_slot(page, _player.backpack, 0)
	_expect(backpack_slot != null, "owned backpack garment has a RedItemSlot")
	var hair_fallback := (
		backpack_slot.find_child("ItemFallbackGlyph", true, false) as RedMenuGlyph
		if backpack_slot != null else null
	)
	_expect(hair_fallback != null
		and (hair_fallback.visible or ItemIcons.cached("c3_hair") != null),
		"Settler Hair always has a visible rendered or vector icon")
	if backpack_slot != null:
		_shift_click(backpack_slot)
	await _wait_frames(3)
	var worn_index := _player.equipment.find("c3_hair")
	_expect(worn_index >= 0 and _player.backpack.find("c3_hair") < 0,
		"shift-clicking backpack apparel equips it")
	_expect(_count_physical("c3_hair") == total_before,
		"equipping apparel preserves total ownership")

	var worn_slot := _red_slot(page, _player.equipment, worn_index)
	_expect(worn_slot != null and worn_slot.equipped,
		"worn garment remains in the finite view with yellow equipped state")
	await _capture("menu_apparel_equipped")
	if worn_slot != null:
		_shift_click(worn_slot)
	await _wait_frames(3)
	_expect(_player.equipment.find("c3_hair") < 0
		and _player.backpack.find("c3_hair") >= 0,
		"shift-clicking worn apparel returns it to the backpack")
	_expect(_count_physical("c3_hair") == total_before,
		"stowing apparel preserves total ownership")
	await _capture("menu_apparel")


func _check_items_and_abilities(menu: GameMenu) -> void:
	_player.hotbar.clear()
	_player.abilities.clear()
	_player.backpack.clear()
	_player.backpack.set_item(0, "sword")
	_player.hotbar.set_item(2, "laser_rifle")
	menu.show_tab(GameMenu.Tab.ITEMS)
	await _wait_frames(4)
	var page := _active_page(menu) as RedCataloguePage
	if not _expect(page != null, "Items routes to RedCataloguePage"):
		return
	await _capture("menu_items")

	_expect(_owned_slots(page).size() == 2,
		"Items lists only owned hotbar and backpack entries")
	var weapons_filter := page.find_child("Filter_weapon", true, false) as Button
	var items_filter := page.find_child("Filter_item", true, false) as Button
	_expect(weapons_filter != null and items_filter != null,
		"Items exposes Weapons and Items filters")
	if weapons_filter != null:
		weapons_filter.pressed.emit()
		await _wait_frames(2)
		_expect(page.selected_filter() == ItemDB.KIND_WEAPON
			and _owned_slots(page).size() == 2,
			"Weapons filter keeps owned weapons")
	items_filter = page.find_child("Filter_item", true, false) as Button
	if items_filter != null:
		items_filter.pressed.emit()
		await _wait_frames(2)
		_expect(page.selected_filter() == ItemDB.KIND_ITEM
			and _owned_slots(page).is_empty(),
			"Items filter excludes weapons when no ordinary item is owned")
		items_filter = page.find_child("Filter_item", true, false) as Button
		if items_filter != null:
			items_filter.pressed.emit()
			await _wait_frames(2)
	_expect(page.selected_filter().is_empty() and _owned_slots(page).size() == 2,
		"pressing the active filter restores All")

	var sword_slot := _red_slot(page, _player.backpack, 0)
	_expect(sword_slot != null, "backpack sword is selectable")
	if sword_slot != null:
		sword_slot.picked.emit(sword_slot)
	await _wait_frames(2)
	for index in 3:
		var target := page.find_child(
			"TargetSlot%d" % (index + 1), true, false) as Button
		_expect(target != null, "Items exposes target %d" % (index + 1))
		if target != null:
			target.pressed.emit()
			_expect(page.target_slot() == index,
				"target %d selects numbered slot %d" % [index + 1, index + 1])
			await _wait_frames(1)

	# Slot three already contains a rifle. The transfer must swap, never delete.
	var sword_count := _count_physical("sword")
	var rifle_count := _count_physical("laser_rifle")
	var equip := page.find_child("EquipAction", true, false) as HoldActionButton
	_expect(equip != null and equip.hold_duration > 0.0
		and not equip.completed.get_connections().is_empty(),
		"hold-to-equip action is wired to the catalogue")
	if equip != null:
		equip.completed.emit()
	await _wait_frames(3)
	_expect(_player.hotbar.get_item(2) == "sword"
		and _player.backpack.get_item(0) == "laser_rifle",
		"equipping into an occupied target swaps losslessly")
	_expect(_count_physical("sword") == sword_count
		and _count_physical("laser_rifle") == rifle_count,
		"numbered-slot transfer preserves both items")

	_player.abilities.clear()
	menu.show_tab(GameMenu.Tab.ABILITIES)
	await _wait_frames(4)
	page = _active_page(menu) as RedCataloguePage
	if not _expect(page != null, "Abilities routes without crashing"):
		return
	await _capture("menu_abilities")
	var targets := page.find_child("TargetButtons", true, false)
	var target_labels := PackedStringArray()
	if targets != null:
		for child: Node in targets.get_children():
			if child is Button:
				target_labels.append((child as Button).text)
	_expect(target_labels == PackedStringArray(["LMB", "RMB"]),
		"Abilities keeps LMB and RMB targets with empty assignments")
	if ItemDB.ability_ids().is_empty():
		var empty_title := page.find_child("EmptyStateTitle", true, false) as Label
		var empty_body := page.find_child("EmptyStateBody", true, false) as Label
		_expect(empty_title != null and empty_title.visible
			and empty_title.text.contains("STANDBY")
			and empty_body != null and empty_body.text.contains("LMB")
			and empty_body.text.contains("RMB"),
			"Abilities presents the polished empty-library state")
	else:
		var expected := PackedStringArray([
			"laser_eyes", "meteor_punch", "starfire", "grapple",
			"nuke", "lasso", "wall", "nausicaa",
		])
		var all_icons := true
		for id: String in expected:
			all_icons = all_icons and ItemDB.ability_icon(id) != null
		_expect(ItemDB.ability_ids() == expected
			and _owned_slots(page).size() == expected.size()
			and all_icons,
			"Abilities presents all eight generated definitions with menu icons")
		_expect("\n".join(ItemDB.stat_lines("wall")).contains(
			"Wall Width\t8 m"),
			"new authored stats use their catalogue labels and units")


func _check_data_settings_and_admin(menu: GameMenu) -> void:
	menu.show_tab(GameMenu.Tab.DATA)
	await _wait_frames(3)
	var data := _active_page(menu) as RedDataPage
	if not _expect(data != null and menu.current_tab() == GameMenu.Tab.DATA,
			"Data routes to one canonical RedDataPage"):
		return
	var achievements := data.find_child("AchievementsTab", true, false) as Button
	var quests := data.find_child("QuestsTab", true, false) as Button
	_expect(achievements != null and quests != null,
		"Data owns internal Quests and Achievements controls")
	if achievements != null:
		achievements.pressed.emit()
		_expect(data.current_kind() == JournalDB.ACHIEVEMENT,
			"Achievements switches inside Data")
	if quests != null:
		quests.pressed.emit()
		_expect(data.current_kind() == JournalDB.QUEST,
			"Quests switches inside Data")

	menu.show_tab(GameMenu.Tab.ACHIEVEMENTS)
	_expect(menu.current_tab() == GameMenu.Tab.DATA
		and _active_page(menu) == data
		and data.current_kind() == JournalDB.ACHIEVEMENT,
		"legacy Achievements routing normalizes without replacing Data")
	menu.show_tab(GameMenu.Tab.QUESTS)
	_expect(menu.current_tab() == GameMenu.Tab.DATA
		and _active_page(menu) == data
		and data.current_kind() == JournalDB.QUEST,
		"legacy Quests routing normalizes without replacing Data")

	var settings_action := menu.find_child("SettingsAction", true, false) as Button
	_expect(settings_action != null, "side SettingsAction exists")
	if settings_action != null:
		settings_action.pressed.emit()
	await _wait_frames(3)
	var settings_panel := _active_page(menu) as SettingsPanel
	_expect(menu.current_tab() == GameMenu.Tab.SETTINGS
		and settings_panel != null
		and settings_panel.name == "InGameSettings",
		"side SettingsAction routes to in-game Settings")
	_expect(settings_panel != null
		and _panel_button(settings_panel, "LEAVE GAME") == null,
		"in-game Settings omits the redundant Leave Game action")
	await _capture("menu_settings_red")

	menu.show_tab(GameMenu.Tab.ADMIN)
	await _wait_frames(2)
	var blank := _active_page(menu)
	_expect(blank != null and blank.name == "AdminBlank"
		and blank.get_child_count() == 0 and blank.get_script() == null,
		"AdminBlank is a truly blank Control")


## The two atmosphere toggles on the shared Display page.
##
## Driven through the rows a player actually presses rather than through
## [GameSettingsManager], because the whole risk with a new setting is the wiring
## between the two: a row that reads the wrong key shows the right word and does
## nothing, and a row that writes the wrong one changes something else. Pressing
## the button and then asking the manager what it now holds is the only check that
## covers the join.
##
## The compositor is asked as well where the world has one. It is what turns "the
## setting was written" into "the effect went off", which are not the same claim
## and have failed apart before in this project — see the render distance, which is
## applied by the planet rather than by the manager for the same reason.
func _check_graphics_toggle_rows(menu: GameMenu) -> void:
	menu.show_tab(GameMenu.Tab.SETTINGS)
	await _wait_frames(3)
	var panel := _active_page(menu) as SettingsPanel
	if not _expect(panel != null, "Settings routes to the shared SettingsPanel"):
		return
	# Display is the first section and is where both rows live. Asked for
	# explicitly rather than assumed, so this does not quietly start checking
	# whatever section a previous row left open.
	panel.show_section(0)
	await _wait_frames(3)

	var rays_row := _display_toggle(panel, "God rays")
	var air_row := _display_toggle(panel, "Atmospheric scattering")
	_expect(rays_row != null, "Display page offers a named God rays row")
	_expect(air_row != null, "Display page offers a named Atmospheric scattering row")
	if rays_row == null or air_row == null:
		return
	_expect(rays_row.button_pressed and rays_row.text == "ON",
		"the God rays row opens showing the saved ON state")
	_expect(air_row.button_pressed and air_row.text == "ON",
		"the Atmospheric scattering row opens showing the saved ON state")

	var effect := _god_rays_effect()
	_expect(effect != null, "the loaded world carries a god rays compositor effect")

	rays_row.button_pressed = false
	await _wait_frames(2)
	_expect(SettingsManager.get_setting(&"graphics", &"god_rays", true) == false,
		"pressing the God rays row writes the setting off")
	_expect(rays_row.text == "OFF", "the God rays row relabels itself when pressed")
	_expect(effect == null or not effect.enabled,
		"switching God rays off disables the compositor effect live")

	air_row.button_pressed = false
	await _wait_frames(2)
	_expect(SettingsManager.get_setting(
		&"graphics", &"atmospheric_scattering", true) == false,
		"pressing the Atmospheric scattering row writes the setting off")
	# Each row writes only its own key. Two toggles added together is exactly the
	# shape of mistake where both end up pointing at the same one.
	_expect(SettingsManager.get_setting(&"graphics", &"god_rays", true) == false,
		"the scattering row leaves the God rays setting where it was")

	# Reset rebuilds the whole panel, so the rows are looked up again rather than
	# reused: the old Buttons have been freed by the time this returns.
	var reset := _panel_button(panel, "RESET DEFAULTS")
	if not _expect(reset != null, "the Display page offers RESET DEFAULTS"):
		return
	reset.pressed.emit()
	await _wait_frames(4)
	panel = _active_page(menu) as SettingsPanel
	if panel != null:
		panel.show_section(0)
		await _wait_frames(3)
	_expect(SettingsManager.get_setting(&"graphics", &"god_rays", false) == true
		and SettingsManager.get_setting(
			&"graphics", &"atmospheric_scattering", false) == true,
		"resetting defaults returns both effects to on")
	_expect(effect == null or effect.enabled,
		"resetting defaults re-enables the compositor effect")
	var rebuilt := _display_toggle(panel, "God rays") if panel != null else null
	_expect(rebuilt != null and rebuilt.button_pressed and rebuilt.text == "ON",
		"the rebuilt God rays row shows the restored default")


## The toggle button belonging to the Display row labelled [param label_text].
##
## Found by its label rather than by a node name because the rows are built by a
## generic helper that names nothing — which is also why the label text is worth
## asserting on: it is the only thing a player has to go on.
func _display_toggle(panel: SettingsPanel, label_text: String) -> Button:
	for node: Node in panel.find_children("*", "Label", true, false):
		var label := node as Label
		if label == null or label.text != label_text:
			continue
		var row := label.get_parent()
		if row == null:
			continue
		for sibling: Node in row.get_children():
			var button := sibling as Button
			if button != null and button.toggle_mode:
				return button
	return null


func _panel_button(panel: SettingsPanel, text: String) -> Button:
	for node: Node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text == text:
			return button
	return null


func _god_rays_effect() -> GodRaysEffect:
	var host := _world.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if host == null or host.compositor == null:
		return null
	for effect: CompositorEffect in host.compositor.compositor_effects:
		if effect is GodRaysEffect:
			return effect
	return null


func _check_isolated_leave_hold() -> void:
	# This shell has no player/world leave connection. Only the observer below is
	# connected, so completing the hold cannot terminate the active test session.
	var shell := Control.new()
	shell.name = "IsolatedLeaveShell"
	shell.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(shell)
	var isolated := GameMenu.new()
	isolated.configure(null)
	isolated.leave_requested.connect(_on_isolated_leave_requested)
	shell.add_child(isolated)
	await _wait_frames(2)

	var leave := isolated.find_child("LeaveAction", true, false) as HoldActionButton
	if not _expect(leave != null, "side hold-to-leave action exists"):
		shell.queue_free()
		return
	leave.hold_duration = 0.01
	leave.grab_focus()
	await _wait_frames(1)
	var press := InputEventAction.new()
	press.action = &"ui_accept"
	press.pressed = true
	leave._gui_input(press)
	leave._process(0.02)
	leave._process(0.02)
	var release := InputEventAction.new()
	release.action = &"ui_accept"
	release.pressed = false
	leave._gui_input(release)
	_expect(_isolated_leave_count == 1,
		"one continuous leave hold completes exactly once")
	shell.queue_free()
	await _wait_frames(2)


func _check_isolated_respawn_hold() -> void:
	var shell := Control.new()
	shell.name = "IsolatedRespawnShell"
	shell.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(shell)
	var isolated := GameMenu.new()
	isolated.configure(null)
	isolated.respawn_requested.connect(_on_isolated_respawn_requested)
	shell.add_child(isolated)
	await _wait_frames(2)

	var respawn := isolated.find_child("RespawnAction", true, false) as HoldActionButton
	if not _expect(respawn != null, "side hold-to-respawn action exists"):
		shell.queue_free()
		return
	respawn.hold_duration = 0.01
	respawn.grab_focus()
	await _wait_frames(1)
	var press := InputEventAction.new()
	press.action = &"ui_accept"
	press.pressed = true
	respawn._gui_input(press)
	respawn._process(0.02)
	respawn._process(0.02)
	var release := InputEventAction.new()
	release.action = &"ui_accept"
	release.pressed = false
	respawn._gui_input(release)
	_expect(_isolated_respawn_count == 1,
		"one continuous respawn hold completes exactly once")
	shell.queue_free()
	await _wait_frames(2)


func _check_drop_round_trip(menu: GameMenu) -> void:
	_player.equipment.clear()
	_player.hotbar.clear()
	_player.backpack.clear()
	_player.backpack.set_item(0, "sword")
	menu.show_tab(GameMenu.Tab.ITEMS)
	await _wait_frames(3)
	var page := _active_page(menu) as RedCataloguePage
	if not _expect(page != null, "Drop check opens the Items catalogue"):
		return
	var source := _red_slot(page, _player.backpack, 0)
	if source != null:
		source.picked.emit(source)
	await _wait_frames(1)
	var before := _count_physical("sword")
	var drop := page.find_child("DropAction", true, false) as Button
	_expect(drop != null and not drop.disabled,
		"selected physical item enables Drop")
	if drop != null:
		drop.pressed.emit()
	await _wait_frames(2)
	var snapshots := _world.pickup_snapshots()
	_expect(_count_physical("sword") == before - 1
		and _player.backpack.get_item(0).is_empty()
		and snapshots.size() == 1,
		"Drop removes exactly one source item through GameWorld")
	if snapshots.is_empty():
		return
	var pickup_id := int((snapshots[0] as Dictionary).get("pickup_id", 0))
	var dropped := _world.pickup_node(pickup_id)
	_expect(is_instance_valid(dropped) and dropped is DroppedItem,
		"Drop creates one physical pickup")
	if not is_instance_valid(dropped):
		return

	var close_action := menu.find_child("CloseAction", true, false) as Button
	_expect(close_action != null, "side CloseAction exists")
	if close_action != null:
		close_action.pressed.emit()
	await _wait_frames(4)
	_expect(_menu() == null and not get_tree().paused
		and _player.controls_enabled,
		"CloseAction closes and restores pause/control policy")
	_expect_captured_mouse("CloseAction captures the mouse")

	# Freeze locomotion, put the body in pickup range, and aim the actual camera
	# ray at the StaticBody. The E event then takes the normal interaction path.
	_player.set_process(false)
	_player.set_physics_process(false)
	var up := dropped.global_basis.y.normalized()
	var side := dropped.global_basis.x.normalized()
	var back := dropped.global_basis.z.normalized()
	_player.global_position = dropped.global_position + side
	var target := dropped.global_position + up * 0.40
	_player.camera.global_position = target + back * 1.45 + up * 0.08
	_player.camera.look_at(target, up)
	await get_tree().physics_frame
	_expect(_player._interact_target() == dropped,
		"player interaction ray resolves the dropped pickup")

	var interact := InputEventKey.new()
	interact.keycode = KEY_E
	interact.physical_keycode = KEY_E
	interact.pressed = true
	_expect(interact.is_action_pressed(&"interact"), "physical E maps to interact")
	_player._unhandled_input(interact)
	var after_pickup := _count_physical("sword")
	_expect(_world.pickup_node(pickup_id) == null
		and after_pickup == before,
		"E interaction returns exactly one item")
	_player._unhandled_input(interact)
	_expect(_count_physical("sword") == after_pickup,
		"duplicate E cannot grant the pickup twice")
	await _wait_frames(2)


func _active_page(menu: GameMenu) -> Control:
	var host := menu.find_child("PageHost", true, false)
	if host == null or host.get_child_count() != 1:
		return null
	return host.get_child(0) as Control


func _owned_slots(page: RedCataloguePage) -> Array[RedItemSlot]:
	var slots: Array[RedItemSlot] = []
	var grid := page.find_child("OwnedItemGrid", true, false)
	if grid == null:
		return slots
	for child: Node in grid.get_children():
		if child is RedItemSlot:
			slots.append(child as RedItemSlot)
	return slots


func _red_slot(
	page: RedCataloguePage,
	container: ItemContainer,
	index: int
) -> RedItemSlot:
	for slot: RedItemSlot in _owned_slots(page):
		if slot.container == container and slot.index == index:
			return slot
	return null


func _shift_click(slot: RedItemSlot) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.shift_pressed = true
	slot._gui_input(event)


func _clear_loadout() -> void:
	_player.holster()
	_player.equipment.clear()
	_player.hotbar.clear()
	_player.abilities.clear()
	_player.backpack.clear()


func _count_physical(item_id: String) -> int:
	var count := 0
	for container: ItemContainer in [
		_player.equipment,
		_player.hotbar,
		_player.backpack,
	]:
		for held: String in container.items():
			if held == item_id:
				count += 1
	return count


func _menu() -> GameMenu:
	if _player == null or not is_instance_valid(_player):
		return null
	for child: Node in _player.hud.get_children():
		if child is GameMenu and not (child as GameMenu).is_queued_for_deletion():
			return child as GameMenu
	return null


func _wait_for_player() -> OnlinePlayer:
	for _frame in 240:
		var candidate := get_tree().get_first_node_in_group(
			"network_players") as OnlinePlayer
		if candidate != null:
			return candidate
		await get_tree().process_frame
	return null


func _tap_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _wait_frames(1)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _wait_frames(1)


func _wait_frames(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame


func _capture(capture_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("menu_test: SKIP  %s.png (headless display)" % capture_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var wanted := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	)
	if image.get_size() != wanted:
		image.resize(wanted.x, wanted.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path(
		"%s/%s.png" % [SHOT_DIR, capture_name])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	_expect(error == OK, "capture %s saves at %dx%d" % [
		capture_name, wanted.x, wanted.y])
	if error == OK:
		print("menu_test: saved %s" % path)


func _on_isolated_leave_requested() -> void:
	_isolated_leave_count += 1


func _on_isolated_respawn_requested() -> void:
	_isolated_respawn_count += 1


func _centres_match(
	outer: Control,
	inner: Control,
	tolerance := 1.0
) -> bool:
	if outer == null or inner == null:
		return false
	return outer.get_global_rect().get_center().distance_to(
		inner.get_global_rect().get_center()) <= tolerance


func _children_have_even_horizontal_gaps(parent: Control) -> bool:
	if parent == null:
		return false
	var controls: Array[Control] = []
	for child: Node in parent.get_children():
		if child is Control and (child as Control).visible:
			controls.append(child as Control)
	if controls.size() < 2:
		return true
	controls.sort_custom(func(a: Control, b: Control) -> bool:
		return a.global_position.x < b.global_position.x)
	var first_gap := controls[1].get_global_rect().get_center().x \
		- controls[0].get_global_rect().get_center().x
	for index in range(2, controls.size()):
		var gap := controls[index].get_global_rect().get_center().x \
			- controls[index - 1].get_global_rect().get_center().x
		if absf(gap - first_gap) > 1.0:
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("menu_test: PASS  %s" % message)
		return true
	_failures += 1
	push_error("menu_test: FAIL  %s" % message)
	return false


func _expect_captured_mouse(message: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("menu_test: SKIP  %s (headless display)" % message)
		return
	_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, message)


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
		push_error("menu_test: could not restore %s" % path)
		return
	file.store_buffer(_settings_bytes)
	file.close()


func _finish() -> void:
	get_tree().paused = false
	Engine.time_scale = _saved_time_scale
	if is_instance_valid(_world):
		_world.queue_free()
	await _wait_frames(3)
	NetworkManager.players.clear()
	NetworkManager.players.merge(_saved_players, true)
	NetworkManager.state = _saved_state as NetworkManager.SessionState
	NetworkManager.is_single_player = _saved_single_player
	NetworkManager.is_host = _saved_host
	_restore_settings()
	print("menu_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
