extends Node

## Screenshots the home screen without a human clicking through it. The menu is a
## camera over the live world now, so this loads the world the same way the game
## does and drives its HomeScreen from the outside.
##
##     godot --path . dev/_menu_shot.tscn
##
## Saves one capture per view to dev/captures/ and quits. Pass `-- --freeze` to
## stop the pencil surfaces redrawing, so two runs are comparable, and
## `-- --handover` to also shoot the sweep from the home pose into third person,
## which is the one thing here that cannot be checked from a single frame. Pass
## `-- --ingame-red` to start safely and capture the canonical Hero/Hats menu.

const WORLD: PackedScene = preload("res://game/world.tscn")
const CAPTURE_DIR := "res://dev/captures"
const SETTINGS_PATH := "user://settings.cfg"
## Long enough for the planet to get past its coarsest chunks, so the shots are of
## the thing the player sees rather than of a cube.
const SETTLE_FRAMES := 90
## Settings goes last because _run_settings_tabs picks up where the loop leaves
## off, and its card has to still be on screen.
const VIEWS := [
	{"name": "home", "view": HomeScreen.View.HOME},
	{"name": "online", "view": HomeScreen.View.ONLINE},
	{"name": "character", "view": HomeScreen.View.CHARACTER},
	{"name": "settings", "view": HomeScreen.View.SETTINGS},
]

var _world: GameWorld
var _home: HomeScreen
## The look as it was before the run, put back on the way out. The editor writes
## every pick straight to settings.cfg, which is the point of it — but a
## screenshot run is not a choice, and the handover deliberately re-saves the
## look that is on screen, so restoring inside the character section is not
## enough and a sword racked for a screenshot stayed racked across launches.
var _saved_look: Dictionary
var _settings_existed := false
var _settings_bytes := PackedByteArray()


func _ready() -> void:
	_snapshot_settings()
	_saved_look = CharacterDB.load_look()
	_world = WORLD.instantiate() as GameWorld
	add_child(_world)
	await _settle(SETTLE_FRAMES)
	_home = _world.get_node_or_null("HomeScreen") as HomeScreen
	if _home == null:
		push_error("_menu_shot: the world came up with no home screen")
		_restore_settings()
		get_tree().quit(1)
		return

	for entry: Dictionary in VIEWS:
		_home.show_view(entry["view"])
		if entry["view"] == HomeScreen.View.ONLINE \
				or entry["view"] == HomeScreen.View.SETTINGS:
			_report_framed_fade_start(String(entry["name"]))
		await _wait(HomeScreen.MOVE_TIME + 0.4)
		await _capture("menu_%s" % entry["name"])
		if entry["view"] == HomeScreen.View.HOME:
			_report_home_controls()
			_report_home_sun()
			_report_planet_title()
			_report_preview()
			await _run_home_new_game_flow()
		if entry["view"] == HomeScreen.View.ONLINE:
			_report_online_layout()
			_report_online_start_cleanup()
		if entry["view"] == HomeScreen.View.CHARACTER:
			await _run_character_bodies()
		if entry["view"] == HomeScreen.View.SETTINGS:
			_report_settings_background()

	await _run_settings_tabs()

	# The pause card used to be shot here. Escape now opens GameMenu instead, which
	# needs a spawned player to build its pages against, so it has a harness of its
	# own: dev/_menu_test.tscn.
	if "--handover" in OS.get_cmdline_user_args():
		await _run_handover()
	elif "--ingame-red" in OS.get_cmdline_user_args():
		await _run_ingame_red()
	CharacterDB.save_look(_saved_look)
	if is_instance_valid(_world):
		_world.queue_free()
	await get_tree().process_frame
	_restore_settings()
	get_tree().quit()


## The figure on the home screen is meant to be hovering, and a body in its rest
## pose and a body in a hover look near enough alike at 1024 px to have gone
## unnoticed once already. So the clip is named rather than looked at, with the
## hip height beside it: the float lifts them, the rest pose does not.
func _report_preview() -> void:
	var preview := _home.get_node_or_null("PreviewCharacter") as Node3D
	if preview == null:
		push_error("_menu_shot: no preview character on the home screen")
		return
	var animator := preview.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := preview.find_child("Skeleton3D", true, false) as Skeleton3D
	var hips := CharacterRig.find_bone(skeleton, &"Hips")
	print("_menu_shot: preview playing '%s' at %.2fs, hips %.3f (rest %.3f)" % [
		"NOTHING" if animator == null else animator.current_animation,
		0.0 if animator == null else animator.current_animation_position,
		skeleton.get_bone_global_pose(hips).origin.y,
		skeleton.get_bone_global_rest(hips).origin.y])


func _report_home_controls() -> void:
	var name_input := _home.find_child("HomeNameInput", true, false) as LineEdit
	var pencil := _home.find_child("HomeEditCharacter", true, false) as Button
	if name_input == null or pencil == null:
		push_error("_menu_shot: compact home identity controls are missing")
		return
	var normal := name_input.get_theme_stylebox(&"normal") as StyleBoxFlat
	var focus := name_input.get_theme_stylebox(&"focus") as StyleBoxFlat
	var name_rect := CrtType.screen_rect(name_input)
	var pencil_rect := CrtType.screen_rect(pencil)
	var name_centre := name_rect.get_center().x
	var wanted_centre := get_viewport().get_visible_rect().size.x * 0.328
	print("_menu_shot: home name rect=%s centre=%.1f/%.1f pencil=%s" % [
		name_rect,
		name_centre,
		wanted_centre,
		pencil_rect.size,
	])
	var identity_ok := (
		name_input.max_length == NetworkManager.PLAYER_NAME_MAX_LENGTH
		and name_rect.size.x <= 151.0
		and name_rect.size.y <= 43.0
		and name_input.alignment == HORIZONTAL_ALIGNMENT_CENTER
		and absf(name_centre - wanted_centre) <= 2.0
		and normal != null and normal.bg_color.a <= 0.001
		and focus != null and focus.bg_color.a <= 0.001
		and normal.border_width_left == 0
		and focus.border_width_left == 0
		and pencil_rect.size.x <= 35.0
		and pencil_rect.size.y <= name_rect.size.y
		and pencil.get_theme_stylebox(&"normal") is StyleBoxEmpty
	)
	if not identity_ok:
		push_error("_menu_shot: home name bar or unboxed pencil is not compact")
		return

	for button_name: String in [
		"HomeNewGame", "HomeLoad", "HomeOnline", "HomeSandbox", "HomeUpgrades",
		"HomeAchievements", "HomeSettings", "HomeQuit"
	]:
		var button := _home.find_child(button_name, true, false) as Button
		if button == null:
			push_error("_menu_shot: missing home action %s" % button_name)
			continue
		var wanted := (
			HomeScreen.HOME_RED_BRIGHT
			if button_name == "HomeQuit"
			else HomeScreen.HOME_GREEN_TEXT
		)
		if button.get_theme_font_size(&"font_size") \
				< HomeScreen.HOME_ACTION_FONT_SIZE \
				or not button.get_theme_color(&"font_color").is_equal_approx(wanted):
			push_error("_menu_shot: %s does not use the larger home action type" % button_name)
		var wrap := button.get_parent()
		var host := wrap.get_parent() as SubViewportContainer if wrap != null else null
		if host == null or host.material == null \
				or not (host.material is ShaderMaterial):
			push_error("_menu_shot: %s CRT must sit on a SubViewport host" % button_name)
	print("_menu_shot: centred text-only 12-character name and unboxed pencil verified")


func _report_home_sun() -> void:
	var cycle := _world.celestial_cycle
	var sun := _world.find_child("Sun", true, false) as DirectionalLight3D
	var landing := _world.find_child("VacationersLanding", true, false) as Node3D
	var planet := _world.planet()
	if cycle == null or sun == null or landing == null or planet == null:
		push_error("_menu_shot: home sunset needs the cycle, sun, landing, and planet")
		return
	var expected := GameWorld.HOME_SUN_ADVANCE_SECONDS / cycle.period_seconds
	var up := (landing.global_position - planet.global_position).normalized()
	var elevation := up.dot(sun.global_basis.z.normalized())
	var phase := cycle.phase()
	if phase < expected or phase > expected + 0.02 or absf(elevation) > 0.5:
		push_error("_menu_shot: home sun did not open near the authored three-minute sunset")
	print("_menu_shot: home sun phase=%.4f landing elevation=%+.3f" % [
		phase, elevation])


func _report_framed_fade_start(view_name: String) -> void:
	var background := _home.find_child(
		"SettingsBackground", true, false) as TextureRect
	var screen := _home._screen as Control
	if background == null or screen == null or not background.visible:
		push_error("_menu_shot: %s frame did not begin its transition" % view_name)
		return
	if background.modulate.a > 0.01 or screen.modulate.a > 0.01:
		push_error("_menu_shot: %s frame appeared before its camera pan" % view_name)
	else:
		print("_menu_shot: %s background and menu begin faded together" % view_name)


func _report_planet_title() -> void:
	var title := _home.get_node_or_null("MyStrangePlanetTitle") as MeshInstance3D
	var planet := _world.planet()
	if title == null or planet == null or title.mesh == null:
		push_error("_menu_shot: home screen has no curved planet title")
		return
	var material := title.material_override as StandardMaterial3D
	if material == null or material.albedo_texture != HomeScreen.TITLE_ART:
		push_error("_menu_shot: planet title is not using the original logo PNG")
		return
	var clouds := planet.get_node_or_null("Clouds") as MeshInstance3D
	var cloud_material := (
		clouds.material_override as Material
		if clouds != null else null
	)
	if cloud_material == null or material.render_priority >= cloud_material.render_priority:
		push_error("_menu_shot: planet title is not ordered beneath the cloud deck")
		return

	var arrays := title.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var worst_clearance_error := 0.0
	var stride := maxi(vertices.size() / 16, 1)
	for index in range(0, vertices.size(), stride):
		var point := planet.to_local(title.to_global(vertices[index]))
		var direction := point.normalized()
		var clearance := point.length() - planet.shape.surface_point(direction).length()
		worst_clearance_error = maxf(
			worst_clearance_error,
			absf(clearance - HomeScreen.PLANET_TITLE_CLEARANCE)
		)
	print("_menu_shot: planet title vertices=%d clearance error=%.3fm priorities=%d<%d" % [
		vertices.size(),
		worst_clearance_error,
		material.render_priority,
		cloud_material.render_priority,
	])
	if worst_clearance_error > 0.5:
		push_error("_menu_shot: planet title does not follow the terrain surface")


func _home_action_host(button: Control) -> Control:
	var wrap := button.get_parent()
	var host := wrap.get_parent() as SubViewportContainer if wrap != null else null
	return host if host != null else button


func _run_home_new_game_flow() -> void:
	var start := _home.find_child("HomeNewGame", true, false) as Button
	var sandbox := _home.find_child("HomeSandbox", true, false) as Button
	var upgrades := _home.find_child("HomeUpgrades", true, false) as Button
	var achievements := _home.find_child("HomeAchievements", true, false) as Button
	if start == null or not start.text.to_upper().contains("START"):
		push_error("_menu_shot: themed Start Game button is missing")
		return
	if sandbox == null or upgrades == null or achievements == null:
		push_error("_menu_shot: Sandbox, Upgrades, or Achievements home actions are missing")
		return
	var online := _home.find_child("HomeOnline", true, false) as Button
	var start_host := _home_action_host(start)
	var sandbox_host := _home_action_host(sandbox)
	var upgrades_host := _home_action_host(upgrades)
	var achievements_host := _home_action_host(achievements)
	var online_host := _home_action_host(online) if online != null else null
	var start_rect := start_host.get_global_rect()
	var sandbox_rect := sandbox_host.get_global_rect()
	var upgrades_rect := upgrades_host.get_global_rect()
	if start_rect.size.x + 0.5 < 240.0:
		push_error("_menu_shot: Start Game is too narrow for its label")
	if achievements.text.to_upper() != "ACHIEVEMENTS":
		push_error("_menu_shot: Achievements home action is still abbreviated")
	if online_host != null and (
			sandbox_rect.position.x < online_host.get_global_rect().end.x
			or upgrades_rect.position.x < sandbox_rect.end.x):
		push_error("_menu_shot: Sandbox is not left of Upgrades after Online")
	var row_one := _home.find_child("HomeMenuRow1", true, false)
	var row_two := _home.find_child("HomeMenuRow2", true, false)
	var plate := start.get_theme_stylebox(&"normal")
	if row_one == null or row_two == null:
		push_error("_menu_shot: home actions are not split into two rows")
	elif achievements_host.global_position.y <= start_host.global_position.y + 8.0:
		push_error("_menu_shot: the second home action row is not below the first")
	if not plate is StyleBoxEmpty:
		push_error("_menu_shot: home actions still draw a boxed plate")
	if start_host.material == null or not (start_host.material is ShaderMaterial):
		push_error("_menu_shot: home actions have no CRT type material")
	print("_menu_shot: home actions start='%s' sandbox='%s' upgrades='%s'" % [
		start.text, sandbox.text, upgrades.text
	])
	upgrades.pressed.emit()
	await _wait(0.25)
	var shop := _home.find_child("MetaUpgradesPanel", true, false) as Control
	var gems := _home.find_child("HomeGemCounter", true, false) as Control
	if shop == null or gems == null or not gems.visible:
		push_error("_menu_shot: Upgrades did not open the gem shop")
		return
	await _capture("menu_home_upgrades")
	if _home._pose_view(HomeScreen.View.UPGRADES) != HomeScreen.View.ONLINE:
		push_error("_menu_shot: Upgrades does not pan to the Online planet pose")
	achievements.pressed.emit()
	await _wait(0.25)
	var board := _home.find_child("AchievementsPanel", true, false) as Control
	var reset := _home.find_child("AchievementReset", true, false) as Button
	if board == null or reset == null or gems == null or not gems.visible:
		push_error("_menu_shot: Achievements did not open the gem board")
	if _home._pose_view(HomeScreen.View.ACHIEVEMENTS) != HomeScreen.View.ONLINE:
		push_error("_menu_shot: Achievements does not pan to the Online planet pose")
	await _capture("menu_home_achievements")
	_home.show_view(HomeScreen.View.HOME)
	await _wait(0.1)


func _report_home_mode_settings(mode_id: String) -> void:
	var settings := _home.find_child(
		"HomeModeSettingControls", true, false) as Control
	var start := _home.find_child("HomeStartGame", true, false) as Control
	var selected := _home.find_child("SelectedHomeMode", true, false) as Control
	if settings == null or start == null or selected == null:
		push_error("_menu_shot: %s mode settings are incomplete" % mode_id)
		return
	var start_is_right := CrtType.screen_rect(start).position.x \
		> CrtType.screen_rect(settings).end.x
	var correct_options := (
		_home.find_child("HomeDuelsOptions", true, false) != null
		if mode_id == "duels"
		else _home.find_child("HomeStandardModeSettings", true, false) != null
	)
	print("_menu_shot: home %s settings start_right=%s options=%s" % [
		mode_id, start_is_right, correct_options
	])


func _report_mode_card_copy(
		root: Control,
		where: String,
		minimum_title_size: int,
		description_size_wanted: int,
		green: Color
	) -> void:
	var title := root.find_child("ModeTitle", true, false) as Label
	var description := root.find_child("ModeDescription", true, false) as Label
	if title == null or description == null:
		push_error("_menu_shot: %s game-mode copy is missing" % where)
		return
	var title_size := title.get_theme_font_size(&"font_size")
	var description_size := description.get_theme_font_size(&"font_size")
	var white := description.get_theme_color(&"font_color")
	var top_aligned := CrtType.screen_rect(title).position.y \
		< CrtType.screen_rect(description).position.y
	if title_size < minimum_title_size \
			or description_size != description_size_wanted \
			or title_size <= description_size \
			or not title.get_theme_color(&"font_color").is_equal_approx(green) \
			or white.r < 0.94 or white.g < 0.94 or white.b < 0.94 \
			or not top_aligned:
		push_error("_menu_shot: %s game-mode typography is not large green/white top copy" % where)


func _report_settings_background() -> void:
	var background := _home.find_child(
		"SettingsBackground", true, false) as TextureRect
	if background == null:
		push_error("_menu_shot: home Settings has no ui_background2")
		return
	var viewport_rect := get_viewport().get_visible_rect()
	var background_rect := background.get_global_rect()
	var settings_frame := _home.find_child(
		"HomeSettingsFrame", true, false) as Control
	var settings_panel := settings_frame as PanelContainer
	var settings_style := (
		settings_panel.get_theme_stylebox(&"panel") as StyleBoxFlat
		if settings_panel != null else null
	)
	var settings_glow := (
		settings_panel.find_child("RedGlowPanel", false, false) as RedGlowPanel
		if settings_panel != null else null
	)
	var gaps := Vector4(
		background_rect.position.x - viewport_rect.position.x,
		background_rect.position.y - viewport_rect.position.y,
		viewport_rect.end.x - background_rect.end.x,
		viewport_rect.end.y - background_rect.end.y
	)
	var inset := gaps.x > 0.0 and gaps.y > 0.0 and gaps.z > 0.0 and gaps.w > 0.0
	var fitted := false
	if settings_frame != null:
		var frame_rect := settings_frame.get_global_rect()
		var frame_gaps := Vector4(
			frame_rect.position.x - background_rect.position.x,
			frame_rect.position.y - background_rect.position.y,
			background_rect.end.x - frame_rect.end.x,
			background_rect.end.y - frame_rect.end.y
		)
		fitted = frame_gaps.x >= -1.0 and frame_gaps.y >= -1.0 \
			and frame_gaps.z >= -1.0 and frame_gaps.w >= -1.0 \
			and frame_gaps.x <= 36.0 and frame_gaps.y <= 36.0 \
			and frame_gaps.z <= 36.0 and frame_gaps.w <= 36.0
	if background.texture != HomeScreen.SETTINGS_BACKGROUND \
			or background.stretch_mode != TextureRect.STRETCH_SCALE \
			or background.modulate.a < 0.99 or not inset or not fitted \
			or settings_style == null or settings_style.bg_color.a > 0.43 \
			or settings_glow == null or settings_glow.fill_color.a > 0.17:
		push_error("_menu_shot: home Settings background is not fitted inset ui_background2")
		return
	print("_menu_shot: home Settings ui_background2 gaps L%.0f T%.0f R%.0f B%.0f" % [
		gaps.x, gaps.y, gaps.z, gaps.w
	])


func _report_online_layout() -> void:
	var lobby := _home.find_child("SteamLobbyPanel", true, false) as LobbyPanel
	var frame := _home.find_child("OnlineFrame", true, false) as Control
	if lobby == null or frame == null:
		push_error("_menu_shot: online lobby frame is missing")
		return
	var frame_panel := frame as PanelContainer
	var frame_style := (
		frame_panel.get_theme_stylebox(&"panel") as StyleBoxFlat
		if frame_panel != null else null
	)
	var frame_glow := frame.find_child(
		"RedGlowPanel", false, false) as RedGlowPanel
	if frame_style == null or frame_glow == null \
			or frame_style.bg_color.a > 0.43 or frame_glow.fill_color.a > 0.17:
		push_error("_menu_shot: online shell is too opaque to reveal UI Background 2")
	var viewport_rect := get_viewport().get_visible_rect()
	var frame_rect := frame.get_global_rect()
	var gaps := Vector4(
		frame_rect.position.x - viewport_rect.position.x,
		frame_rect.position.y - viewport_rect.position.y,
		viewport_rect.end.x - frame_rect.end.x,
		viewport_rect.end.y - frame_rect.end.y
	)
	print("_menu_shot: online frame gaps L%.0f T%.0f R%.0f B%.0f" % [
		gaps.x, gaps.y, gaps.z, gaps.w
	])
	for node_name: String in [
		"LobbyTabs", "CreateLobbyUpper", "GameModes", "HostLobby"
	]:
		var control := lobby.find_child(node_name, true, false) as Control
		if control == null:
			push_error("_menu_shot: online control %s is missing" % node_name)
			continue
		var control_rect := CrtType.screen_rect(control)
		print("_menu_shot: online %-16s %s%s" % [
			node_name,
			control_rect,
			"" if frame_rect.encloses(control_rect) else " CLIPPED",
		])
	var modes := lobby.find_child("GameModes", true, false) as Control
	if modes != null:
		_report_mode_card_copy(modes, "online", 17, 12, LobbyPanel.MODE_GREEN)
	var host := lobby.find_child("HostLobby", true, false) as Button
	var page_scroll := lobby.find_child(
		"OnlinePageScroll", true, false) as ScrollContainer
	var host_rect := CrtType.screen_rect(host) if host != null else Rect2()
	var page_fits := page_scroll != null and host != null \
		and page_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED \
		and page_scroll.get_global_rect().encloses(host_rect)
	if host == null or host_rect.size.y > 35.0 or not page_fits:
		push_error("_menu_shot: thinner Host Lobby action did not eliminate Online scrolling")


func _report_online_start_cleanup() -> void:
	var background := _home.find_child(
		"SettingsBackground", true, false) as TextureRect
	_home._dismiss_overlay()
	if background == null or background.visible or background.modulate.a > 0.01:
		push_error("_menu_shot: Online ui_background2 survives session start")
		return
	print("_menu_shot: Online ui_background2 clears with its lobby panel")


## New Game should never cut: the camera leaves the home pose and arrives behind
## the body, and the body is the one that was standing there. Three frames along
## the sweep is enough to see whether it moved or jumped.
func _run_handover() -> void:
	# Seconds rather than frames, all the way through: the tweens and the sweep run
	# on a clock and the harness runs unlocked, so counting frames here started the
	# sweep from whichever pose the camera happened to still be travelling through.
	_home.show_view(HomeScreen.View.HOME)
	await _wait(HomeScreen.MOVE_TIME + 0.4)
	var title := _home.get_node_or_null("MyStrangePlanetTitle") as MeshInstance3D
	var title_material := (
		title.material_override as StandardMaterial3D
		if title != null else null
	)
	_home.start_new_game()
	for step in 3:
		await _wait(HomeScreen.HANDOVER_TIME / 4.0)
		await _capture("menu_handover_%d" % step)
	await _wait(HomeScreen.HANDOVER_TIME)
	await _capture("menu_handover_done")
	var player := _world.local_player()
	print("_menu_shot: local player %s, camera %s, controls %s, home screen %s" % [
		"spawned" if player != null else "MISSING",
		"handed over" if player != null and player.camera.current else "NOT HANDED OVER",
		"on" if player != null and player.controls_enabled else "OFF",
		"gone" if not is_instance_valid(_home) else "STILL UP",
	])
	if title_material == null or title_material.albedo_color.a > 0.05:
		push_error("_menu_shot: planet title did not fade out during game start")
	else:
		print("_menu_shot: planet title faded out with the game start")
	# The body the editor chose has to be the body that spawns, garments, weapons
	# and all. It is the one thing about the handover that no frame of the sweep
	# shows, since the preview and the player are meant to look identical by then
	# — and the rack it never showed at all, because nothing puts a weapon in the
	# figure's hand.
	if player != null:
		var wanted := CharacterDB.load_look()
		print("_menu_shot: body wanted=%s got=%s, skin wanted=%s got=%s, worn wanted=%s got=%s" % [
			wanted["body"], player.body_id(), wanted["skin"], player.skin_id(),
			CharacterDB.worn_items(wanted), player.worn_items(),
		])
		print("_menu_shot: three-slot hotbar wanted=%s got=%s" % [
			CharacterDB.hotbar_items(wanted, player.hotbar.size()),
			player.hotbar.items(),
		])


## Optional visual-only path for the in-game shell. Behavioral coverage belongs
## to _menu_test; this path reports geometry and saves two representative frames.
func _run_ingame_red() -> void:
	_home.show_view(HomeScreen.View.HOME)
	await _wait(HomeScreen.MOVE_TIME + 0.4)
	_home.start_new_game()
	await _wait(HomeScreen.HANDOVER_TIME + 0.5)
	var player := _world.local_player()
	if player == null:
		push_error("_menu_shot: --ingame-red did not spawn a local player")
		return
	if _world.celestial_cycle == null \
			or _world.celestial_cycle.phase() > 0.01:
		push_error("_menu_shot: New Game did not reset the sunset menu to full daylight")
	player._open_game_menu(GameMenu.Tab.HERO)
	await _wait(0.25)
	var menu := _game_menu(player)
	if menu == null:
		push_error("_menu_shot: --ingame-red did not open GameMenu")
		return
	_report_red_bounds(menu, "Hero")
	await _capture("menu_ingame_hero")
	menu.show_tab(GameMenu.Tab.APPAREL)
	await _wait(0.25)
	_report_red_bounds(menu, "Hats")
	await _capture("menu_ingame_hats")
	menu.close()
	await get_tree().process_frame


func _game_menu(player: OnlinePlayer) -> GameMenu:
	for child: Node in player.hud.get_children():
		if child is GameMenu:
			return child as GameMenu
	return null


func _report_red_bounds(menu: GameMenu, page_name: String) -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	for node_name: String in [
		"ContentFrame",
		"BottomSelector",
		"AdminButton",
		"SessionActions",
	]:
		var control := menu.find_child(node_name, true, false) as Control
		if control == null:
			push_error("_menu_shot: %s is missing %s" % [page_name, node_name])
			continue
		var bounds := control.get_global_rect()
		var contained := viewport_rect.encloses(bounds)
		print("_menu_shot: %s %-14s at %.0f,%.0f size %.0fx%.0f inside=%s" % [
			page_name,
			node_name,
			bounds.position.x,
			bounds.position.y,
			bounds.size.x,
			bounds.size.y,
			contained,
		])


## The editor dresses the figure and recolours it, and neither shows in a single
## frame of whichever look happened to be saved. So the body is dressed in its own
## apparel for a shot, which is also the check that a garment cut for the other
## skeleton is never offered on this one.
##
## There is one playable body now, so this no longer walks them. Turning the
## astronaut back on means putting the loop back — the containers already handle a
## body change; see `_on_tint_picked` in `home_screen.gd`.
func _run_character_bodies() -> void:
	var page := _world.find_child(
		"PlayerDesignerPanel", true, false) as PlayerDesignerPanel
	if page == null:
		push_error("_menu_shot: the character view came up with no editor")
		return
	_report_designer_fit(page)
	var saved := CharacterDB.load_look()
	var body_id := CharacterDB.sanitize_body(saved["body"])
	if _press("Integrated Robotic"):
		await _wait(0.35)
		await _capture("menu_character_integrated_robotic")
		print("_menu_shot: texture picked %s" % CharacterDB.load_look()["skin"])
	if _press("Clean Robotic"):
		await _wait(0.35)
		await _capture("menu_character_clean_robotic")
	await _run_character_apparel(page, body_id)
	page.show_tab(PlayerDesignerPanel.Tab.HERO)
	await _wait(0.35)
	await _capture("menu_character_%s" % body_id)
	print("_menu_shot: %s wearing %s" % [body_id, page.worn_slots().items()])
	# Twice over on one target, because a tint multiplies what it lands on and the
	# failure is not a wrong colour but a colour that keeps getting darker.
	for colour: Color in [Color(0.86, 0.24, 0.20), Color(0.24, 0.46, 0.74)]:
		page.tint_picked.emit(PlayerDesignerPanel.TINT_BODY, colour)
		await _wait(0.2)
	page.tint_picked.emit("hat", Color(0.94, 0.68, 0.22))
	await _wait(0.35)
	await _capture("menu_character_tinted")
	page.tint_cleared.emit(PlayerDesignerPanel.TINT_BODY)
	page.tint_cleared.emit("hat")
	await _wait(0.35)
	await _capture("menu_character_no_tint")
	print("_menu_shot: no tint leaves %s" % CharacterDB.load_look()["tints"])
	CharacterDB.save_look(saved)
	# The ordinary shots leave the clean design selected. A handover run takes the
	# other one through the preview → player seam as well; the outer cleanup puts
	# the user's saved choice back after the player has been inspected.
	if "--handover" in OS.get_cmdline_user_args() and _press("Integrated Robotic"):
		await _wait(0.35)


## The second tab is hats only. Toggle one real owned hat through the same
## code a completed tile hold uses, then put it back before taking the screenshot.
func _run_character_apparel(
		page: PlayerDesignerPanel,
		body_id: String
	) -> void:
	page.show_tab(PlayerDesignerPanel.Tab.APPAREL)
	await _wait(0.35)
	var owned := page.apparel_ids()
	var weapon_tiles := page.find_children("DesignerApparel_*", "DesignerApparelTile",
		true, false).filter(func(node: Node) -> bool:
			return ItemDB.is_weapon((node as DesignerApparelTile).item_id())
	)
	print("_menu_shot: hats catalogue count=%d ids=%s weapon_tiles=%d" % [
		owned.size(), owned, weapon_tiles.size()])

	var garment := ""
	for item_id: String in owned:
		if CharacterDB.apparel_fits(body_id, item_id):
			garment = item_id
			break
	if not garment.is_empty():
		var before := page.worn_slots().items()
		page.toggle_apparel(garment)
		page.toggle_apparel(garment)
		print("_menu_shot: hold hat round trip %s -> %s" % [
			before, page.worn_slots().items()])
	else:
		print("_menu_shot: finite catalogue has no owned hat to toggle")
	await _capture("menu_character_hats")


func _report_designer_fit(page: PlayerDesignerPanel) -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	var panel_rect := page.get_global_rect()
	var background := page.find_child(
		"RotatedUIBackground2", true, false) as TextureRect
	var no_stats := page.find_child("StatsFrame", true, false) == null
	var no_hotbar := page.find_child("HotbarSlots", true, false) == null
	var compressed_right := panel_rect.position.x \
		>= viewport_rect.size.x * (1.0 - HomeScreen.EDITOR_CARD_SHARE) - 1.0
	print("_menu_shot: designer rect=%s inside=%s rotated_background=%s no_stats=%s no_hotbar=%s" % [
		panel_rect,
		viewport_rect.encloses(panel_rect),
		background != null and is_equal_approx(background.rotation, PI * 0.5),
		no_stats,
		no_hotbar,
	])
	if not viewport_rect.encloses(panel_rect) or not compressed_right:
		push_error("_menu_shot: designer card is not compressed to the right of the figure")


## If the finite save owns a weapon, show that its tile can arm one of exactly
## three numbered slots. A character that owns no weapon is a valid empty view.
func _arm_owned_weapon(
	page: InventoryPage,
	owned: PackedStringArray
) -> void:
	if page.rack_slots().size() != CharacterDB.HOTBAR_SLOTS:
		push_error("_menu_shot: home hotbar has %d slots, expected %d" % [
			page.rack_slots().size(), CharacterDB.HOTBAR_SLOTS])
		return
	if not _press("Weapons"):
		push_error("_menu_shot: the catalogue has no Weapons filter")
		return
	await _wait(0.2)
	var weapon := ""
	for item_id: String in owned:
		if ItemDB.is_weapon(item_id):
			weapon = item_id
			break
	if weapon.is_empty():
		print("_menu_shot: finite catalogue has no owned weapon to arm")
		_press("Clothing")
		await _wait(0.2)
		return
	print("_menu_shot: weapons filter %s" % _catalogue_state(page))
	if page.rack_slots().find(weapon) < 0:
		await _click(page, weapon)
	print("_menu_shot: armed owned %s -> %s" % [
		weapon, page.rack_slots().items()])
	_press("Clothing")
	await _wait(0.2)


func _finite_owned_ids(page: InventoryPage) -> PackedStringArray:
	var owned := PackedStringArray()
	for item_id: String in page.spare_slots().items():
		if not item_id.is_empty() and not owned.has(item_id):
			owned.append(item_id)
	return owned


func _click(page: InventoryPage, item_id: String) -> void:
	var slot := _tile(page, item_id)
	if slot == null:
		push_error("_menu_shot: %s is not in the catalogue" % item_id)
		return
	slot.picked.emit(slot)
	await _wait(0.1)


## How many tiles the grid is showing, how many of them are ringed as worn, and
## what the body actually has on — the three have to agree or the ring is
## decoration.
func _catalogue_state(page: InventoryPage) -> String:
	var shown := 0
	var marked := 0
	for node in page.find_children("*", "ItemSlot", true, false):
		var slot := node as ItemSlot
		if slot.container != page.spare_slots() or not slot.visible:
			continue
		shown += 1
		if slot.selected:
			marked += 1
	return "tiles=%d ringed=%d wearing %s" % [shown, marked, page.worn_slots().items()]


func _page(section: InventoryPage.Section) -> InventoryPage:
	for candidate in _world.find_children("*", "InventoryPage", true, false):
		var page := candidate as InventoryPage
		if page.section == section:
			return page
	return null


func _tile(page: InventoryPage, item_id: String) -> ItemSlot:
	for node in page.find_children("*", "ItemSlot", true, false):
		var slot := node as ItemSlot
		if slot.container == page.spare_slots() and slot.item_id() == item_id:
			return slot
	return null


func _press(label: String) -> bool:
	for node in _world.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text.to_lower() == label.to_lower():
			button.pressed.emit()
			return true
	return false


## Whether the editor's card is inside the room the home screen gave it, which is
## the one thing about this screen a shot of it does not show: a control cannot be
## smaller than its contents, so a card that wants more than the host drags the
## host past its own anchors instead of being clipped by it. Every frame still
## looks plausible and the window quietly loses the bottom row — the colour strip,
## which is the last one down and the thing the editor is for.
##
## Measured against the room the anchors allow and not against `host.size`, which
## is the stretched figure and would report every overflow as a fit. Checked
## dressed as well as undressed because a target button per worn garment is width
## the strip demands on one line, and that is the axis that goes first.
func _report_fit(page: InventoryPage, when: String) -> void:
	var card := _card_above(page)
	if card == null:
		push_error("_menu_shot: no card above the editor page")
		return
	var host := card.get_parent() as Control
	var wanted := card.get_combined_minimum_size()
	# The general form, and it has to be: the host is held to the right of the
	# window while the editor is open, so the share of its parent it is anchored
	# across is most of the answer. Reading the parent's whole width — which is
	# what this did while every screen was full-width — reported twice the room
	# that was really there and passed a card overflowing by 400 px.
	var parent := host.get_parent() as Control
	var room := Vector2(
		parent.size.x * (host.anchor_right - host.anchor_left)
			+ host.offset_right - host.offset_left,
		parent.size.y * (host.anchor_bottom - host.anchor_top)
			+ host.offset_bottom - host.offset_top)
	var over := (wanted - room).maxf(0.0)
	# The card no longer carries the page's height in its own minimum — the page
	# host is a ScrollContainer, whose minimum is nothing — so the card fitting is
	# necessary and no longer sufficient. The page's own ask against the viewport
	# it was given is the other half, and it is a note rather than a failure:
	# scrolling is the answer to a page that wants more, and reaching for it is
	# the screen working rather than breaking.
	var wants_page := page.get_combined_minimum_size().y
	var scroll := page.get_parent() as ScrollContainer
	var viewport := scroll.size.y if scroll != null else room.y
	print("_menu_shot: editor %s room %.0fx%.0f card wants %.0fx%.0f, over by %.0fx%.0f%s" % [
		when, room.x, room.y, wanted.x, wanted.y, over.x, over.y,
		", page %.0f in %.0f%s" % [wants_page, viewport,
			" (scrolls)" if wants_page > viewport + 1.0 else ""]])
	if over != Vector2.ZERO:
		push_error("_menu_shot: the %s editor card is %.0fx%.0f px bigger than its host" % [
			when, over.x, over.y])
	_report_spill(card, when)


## What is actually drawn outside the card, which is a different question from the
## one above and the one the screenshots kept losing.
##
## A minimum size is what a control **asks** for, and the sum of those asks can
## fit inside the card while a particular control still ends up hanging over its
## edge — a shrink-centred child of an over-tall row, a tooltip placed against the
## mouse, anything positioned rather than laid out. The card reported 0x0 over for
## as long as the colour wheel was being clipped by it. So this walks what was
## laid out rather than what was asked for, and names the worst offender: a number
## nobody has to interpret, against a screenshot that has to be squinted at.
func _report_spill(card: Control, when: String) -> void:
	var inside := Rect2(card.global_position, card.size).grow(-AuroraSurface.BLEED)
	var worst := 0.0
	var culprit := ""
	for node in card.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.visible or control.size == Vector2.ZERO:
			continue
		# The surfaces are grown past their Control by AuroraSurface.BLEED on
		# purpose, and the shader insets the drawn shape by the same amount, so
		# every one of them overhangs by exactly that and none of them draws
		# anything out there.
		if control is AuroraSurface:
			continue
		# A ScrollContainer clips, so its contents cannot draw outside it however
		# far their rects reach — that overhang is the scrollbar's reason to
		# exist and is reported as such by _report_fit.
		if _scrolled(control, card):
			continue
		var rect := Rect2(control.global_position, control.size)
		var spill := maxf(
			maxf(inside.position.x - rect.position.x, rect.end.x - inside.end.x),
			maxf(inside.position.y - rect.position.y, rect.end.y - inside.end.y))
		if spill > worst:
			worst = spill
			culprit = "%s (%s)" % [control.name, control.get_class()]
	# Up to the bleed is not a spill. The card's own padding container fills the
	# card exactly, so it clears the inset rim by precisely that much on all four
	# sides, and a real overhang is tens of pixels rather than six.
	if worst <= AuroraSurface.BLEED + 1.0:
		print("_menu_shot: editor %s spill none" % when)
		return
	push_error("_menu_shot: the %s editor draws %.0f px outside its card, worst is %s" % [
		when, worst, culprit])


func _scrolled(control: Control, card: Control) -> bool:
	var walk := control.get_parent()
	while walk != null and walk != card:
		if walk is ScrollContainer:
			return true
		walk = walk.get_parent()
	return false


## The drawn card the page sits inside, found by walking up rather than by
## counting parents: the editor grew a tab strip and a page host between the two,
## and a hop count silently started measuring the strip instead — which fits
## whatever it is given and would have reported every overflow as a fit.
func _card_above(page: Control) -> Control:
	var found: Control = null
	var node := page.get_parent() as Control
	while node != null:
		if node is PanelContainer:
			found = node
		node = node.get_parent() as Control
	return found


## The settings shot above only ever catches the first section. The others are
## worth their own frames: audio is the widest row and controls carries the rebind
## list, which is the longest thing in any menu and the first to overrun its card
## when the type is resized.
func _run_settings_tabs() -> void:
	var panels := _world.find_children("*", "SettingsPanel", true, false)
	if panels.is_empty():
		push_error("_menu_shot: the settings card came up with no panel")
		return
	var panel := panels[0] as SettingsPanel
	for index in range(1, SettingsPanel.SECTIONS.size()):
		panel.show_section(index)
		await _wait(0.25)
		await _capture("menu_settings_%d" % index)
	panel.show_section(0)
	await _wait(0.25)
	await _scrolled_shot(panel, "menu_settings_0_foot")


## Every section is taller than the card it sits in, so a shot of one is a shot of
## its first three rows. Display is the section where that hides the most — the
## render scale, the quality and the render distance are all under the fold, and
## none of them had ever been photographed. Run to the bottom and take the rest.
func _scrolled_shot(panel: SettingsPanel, shot_name: String) -> void:
	var scrolls := panel.find_children("*", "ScrollContainer", true, false)
	if scrolls.is_empty():
		push_error("_menu_shot: the settings section has no scroll to run down")
		return
	var scroll := scrolls[0] as ScrollContainer
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _wait(0.25)
	await _capture(shot_name)


## Frames, for waiting on work that is measured in them: the planet applies a
## fixed number of built chunks per frame.
func _settle(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
	await _still()


## Seconds, for waiting on anything driven by a tween or by delta.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await _still()


func _still() -> void:
	if "--freeze" in OS.get_cmdline_user_args():
		_freeze()
		await get_tree().process_frame


func _freeze() -> void:
	for control: Node in _surfaces(self):
		var material := (control as CanvasItem).material as ShaderMaterial
		if material != null:
			material.set_shader_parameter(&"redraw_fps", 0.0)


func _surfaces(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node is CanvasItem and (node as CanvasItem).material is ShaderMaterial:
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_surfaces(child))
	return found


func _capture(capture_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("_menu_shot: skipped %s.png (headless display)" % capture_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var wanted := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	)
	if image.get_size() != wanted:
		image.resize(wanted.x, wanted.y, Image.INTERPOLATE_LANCZOS)
	var path := ProjectSettings.globalize_path("%s/%s.png" % [CAPTURE_DIR, capture_name])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if image.save_png(path) == OK:
		print("_menu_shot: saved %s (%dx%d)" % [path, wanted.x, wanted.y])
	else:
		push_error("_menu_shot: could not save %s" % path)


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
		push_error("_menu_shot: could not restore %s" % path)
		return
	file.store_buffer(_settings_bytes)
	file.close()
