extends Node

## Focused deterministic checks for combat HUD presentation.
##
##     godot --headless --path . dev/_combat_hud_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const SETTINGS_PATH := "user://settings.cfg"

var _failures := 0
var _player: OnlinePlayer
var _hud: Node
var _world: Node3D
var _boss: TestBoss
var _settings_existed := false
var _settings_bytes := PackedByteArray()


class TestBoss extends Node3D:
	var engaged := false
	var boss_health := 100.0
	var maximum := 100.0
	var radius := 100.0
	var distance := 50.0
	var boundary_visible := false

	func _ready() -> void:
		add_to_group(BossAdapter.GROUP)

	func is_engaged() -> bool:
		return engaged

	func health() -> float:
		return boss_health

	func maximum_health() -> float:
		return maximum

	func battle_radius() -> float:
		return radius

	func arena_distance_to(body: Node3D) -> float:
		return distance

	func set_arena_boundary_visible(shown: bool) -> void:
		boundary_visible = shown


func _ready() -> void:
	_snapshot_settings()
	for item_id: String in ItemDB.ITEMS:
		ItemIcons._cache[item_id] = ImageTexture.new()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	_world = Node3D.new()
	_world.name = "TestWorld"
	add_child(_world)

	_boss = TestBoss.new()
	_boss.name = "Bigfoot"
	_world.add_child(_boss)

	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_player.defer_camera = true
	_world.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	_hud = _player.combat_hud()
	_expect(_hud != null, "local player owns a CombatHud")
	await _check_fps_overlay()
	await _check_compact_player_hud()
	await _check_boss_bar()
	await _check_flightless_chip()
	await _check_hero_status_rows()
	await _check_parry_indicator()
	await _check_mob_flash()
	await _check_local_feedback()
	await _check_death_screen()

	_player.queue_free()
	_world.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	_restore_settings()
	print("combat_hud_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_fps_overlay() -> void:
	var hud := _player.combat_hud() as CombatHud
	var meter: Control = hud.fps_overlay() if hud != null else null
	_expect(meter != null, "combat HUD shows a live FPS meter")
	if meter == null:
		return
	_expect(is_equal_approx(meter.anchor_left, 1.0)
			and is_equal_approx(meter.anchor_top, 0.0)
			and meter.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"the FPS chart sits in the upper-right")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(int(meter.call(&"sample_count")) >= 2
			and float(meter.call(&"current_fps")) > 0.0
			and meter.find_child("FpsChart", true, false) != null
			and meter.find_child("FpsHitchNote", true, false) == null,
		"the FPS line chart records frames as they land")


func _check_compact_player_hud() -> void:
	_expect(_player.find_child("StancePlate", true, false) == null
		and _player.find_child("FlightPlate", true, false) == null,
		"old lower-left stance and flight boxes are removed")
	var info: CoordinatePlate = null
	for node: Node in _player.find_children("*", "CoordinatePlate", true, false):
		info = node as CoordinatePlate
		break
	_expect(info != null and is_equal_approx(info.anchor_top, 1.0)
		and is_equal_approx(info.anchor_right, 1.0),
		"compact info plate is anchored bottom-right")
	if info != null:
		_expect(not info.visible, "info plate is hidden during ordinary play")
		var tilde := InputEventKey.new()
		tilde.physical_keycode = 96 as Key
		tilde.pressed = true
		_player._unhandled_input(tilde)
		_expect(info.visible, "tilde opens the bottom-right info plate")
		info.set_motion_info("floating", "third close", 12.0)
		info.refresh(Vector3.ZERO, null, 0.3)
		var labels := info.find_children("*", "Label", true, false)
		var summary: Label = null
		if not labels.is_empty():
			summary = labels[labels.size() - 1] as Label
		_expect(summary != null and summary.text.contains("floating")
			and summary.text.contains("fps")
			and summary.get_theme_font_size(&"font_size") <= 8,
			"info plate combines movement, POV, speed, and FPS in small text")
		_player._unhandled_input(tilde)
		_expect(not info.visible, "second tilde hides the info plate")

	var log := (_player.combat_hud() as CombatHud).hit_log() \
		if _player.combat_hud() is CombatHud else null
	_expect(log != null and is_equal_approx(log.anchor_top, 1.0)
			and is_equal_approx(log.anchor_right, 1.0),
		"hit log sits in the bottom-right")
	_expect(log != null and not log.visible and not log.has_rows(),
		"hit log stays hidden until something lands")

	var mini := _player.find_child("CityMinimap", true, false) as Control
	_expect(mini != null, "circular city mini-map sits in the HUD")
	if mini != null:
		_expect(is_equal_approx(mini.anchor_top, 1.0)
			and is_equal_approx(mini.anchor_right, 1.0),
			"mini-map is anchored bottom-right, left of the info plate")
		_expect(not mini.visible, "mini-map stays hidden outside a mapped city")

	var weapon_bar := _player.find_child("WeaponBar", true, false) as WeaponBar
	_expect(weapon_bar != null, "themed weapon bar exists")
	if weapon_bar != null:
		var slots := weapon_bar.find_children("*", "ItemSlot", true, false)
		var themed := weapon_bar._ability_slots.size() == OnlinePlayer.ABILITY_SLOTS
		for node: Node in slots:
			themed = themed and (node as ItemSlot).hud_style
		var juke_slot := weapon_bar.find_child("JukeSlot", true, false) as ItemSlot
		_expect(themed, "all four ability squares use the red HUD style")
		_expect(juke_slot != null and juke_slot.badge == "F" and juke_slot.visible
				and juke_slot.forced_item_id == CrawlerProgress.STAT_JUKE,
			"juke sits on the hotbar as an F tile")

		_player.abilities.set_item(0, "nuke")
		await get_tree().process_frame
		var ability := _player.ability_controller().ability_in(0)
		var ability_slot := weapon_bar._ability_slots[0]
		if ability != null:
			ability._cooldown_left = ability.cooldown()
			weapon_bar._process(0.0)
		_expect(ability != null and ability_slot.cooldown_active
			and is_zero_approx(ability_slot.cooldown_fill),
			"an ability cooldown empties its HUD icon box")
		if ability != null:
			ability._cooldown_left = ability.cooldown() * 0.5
			weapon_bar._process(0.0)
		_expect(ability != null and is_equal_approx(
			ability_slot.cooldown_fill, 0.5),
			"the ability icon refills in proportion to cooldown recovery")
		if ability != null:
			ability._cooldown_left = 0.0
			weapon_bar._process(0.0)
		_expect(not ability_slot.cooldown_active
			and is_equal_approx(ability_slot.cooldown_fill, 1.0),
			"the icon is completely restored when the ability is ready")
		_player.abilities.set_item(0, "")


func _check_boss_bar() -> void:
	var bar: BossBar = _hud.call("boss_bar")
	_expect(bar != null, "boss bar exists")
	var title_label: Label = null
	for node: Node in bar.find_children("*", "Label", true, false):
		if (node as Label).text == "Bigfoot":
			title_label = node
			break
	_expect(title_label != null, "boss bar title is exactly Bigfoot")

	_boss.engaged = false
	_boss.distance = 50.0
	_hud.refresh(0.16)
	_expect(not bar.visible and not _boss.boundary_visible,
		"boss bar and arena boundary stay hidden until engagement")

	_boss.engaged = true
	_boss.boss_health = 100.0
	_hud._last_boss_health = -1.0
	_hud._session_engaged = false
	_hud.refresh(0.16)
	_expect(bar.visible and is_equal_approx(bar.modulate.a, 1.0),
		"boss bar visible well inside arena")
	_expect(_boss.boundary_visible,
		"showing the boss bar also reveals the arena boundary")

	_boss.boss_health = 40.0
	for _step in 8:
		_hud.refresh(0.16)
		await get_tree().process_frame
	_expect(bar.visible, "boss bar stays visible after damage")
	var fill := bar.get("_fill") as ColorRect
	_expect(fill != null and absf(fill.scale.x - 0.4) < 0.05,
		"boss health strip visibly tracks the replicated health share")

	_boss.distance = 90.0
	_hud.refresh(0.16)
	_expect(bar.visible and bar.modulate.a < 1.0 and bar.modulate.a > 0.0,
		"boss bar fades between 80 m and 100 m")

	_boss.distance = 110.0
	_hud.refresh(0.16)
	var warning_alpha := bar.modulate.a
	_hud.refresh(0.16)
	_expect(bar.visible and _boss.boundary_visible and bar.warning_active()
		and not is_equal_approx(warning_alpha, bar.modulate.a),
		"boss name and health bar flash while the arena exit warning is active")

	_boss.distance = 50.0
	_hud.refresh(0.16)
	_expect(bar.visible and _boss.boundary_visible and not bar.warning_active(),
		"returning to the arena clears the warning without ending the fight")

	_boss.distance = 110.0
	_hud.refresh(0.16)
	_boss.engaged = false
	_hud.refresh(0.16)
	_expect(not bar.visible and not _boss.boundary_visible,
		"the authoritative arena reset hides both encounter indicators")

	_boss.distance = 50.0
	_hud.refresh(0.16)
	_expect(not bar.visible and not _boss.boundary_visible,
		"a reset encounter stays hidden after returning")

	_boss.engaged = true
	_hud.refresh(0.16)
	_expect(bar.visible and _boss.boundary_visible,
		"re-engagement shows the bar and ground boundary again")


func _check_flightless_chip() -> void:
	_player.statuses.apply_status(CombatStatuses.FLIGHTLESS, 4.0)
	await get_tree().process_frame
	_hud.refresh(0.16)
	var layer: StatusChipLayer = _hud.call("status_layer")
	_expect(layer.visible, "flightless chip layer visible")
	var chip := layer.find_child("Chip_flightless", true, false) as StatusChip
	_expect(chip != null, "flightless chip exists")
	var title: Label = null
	for node: Node in chip.find_children("*", "Label", true, false):
		if (node as Label).text == "Flightless":
			title = node
			break
	_expect(title != null, "flightless chip shows title")

	_player.statuses.tick(4.5)
	await get_tree().process_frame
	_hud.refresh(0.16)
	_expect(_player.status_rows().is_empty(), "flightless expired")
	_expect(layer.find_child("Chip_flightless", true, false) == null,
		"flightless chip removed after expiry")


func _check_hero_status_rows() -> void:
	_player.statuses.apply_status(CombatStatuses.FLIGHTLESS, 3.0)
	await get_tree().process_frame
	var page := RedHeroPage.new()
	page.configure(_player)
	add_child(page)
	await get_tree().process_frame
	page.refresh()
	var section := page.find_child("StatusSection", true, false) as VBoxContainer
	_expect(section != null and section.visible,
		"hero stats include temporary effects section")
	var row := page.find_child("Status_flightless", true, false)
	_expect(row != null, "hero stats lists Flightless row")
	page.queue_free()
	_player.statuses.clear()


func _check_parry_indicator() -> void:
	var indicator: ParryIndicator = _hud.call("parry_indicator")
	_player._parry_cooldown_left = 0.0
	_player._parry_window_left = 0.0
	indicator.refresh(_player)
	_expect(is_equal_approx(indicator.shield_share(), 1.0),
		"ready shield bar is full")
	_expect(indicator.find_children("*", "Label", true, false).is_empty(),
		"shield HUD has no F or ready text")

	_player._parry_cooldown_left = 1.2
	_player._parry_window_left = 0.0
	indicator.refresh(_player)
	var expected_regen := 1.0 - 1.2 / _player.parry_cooldown
	_expect(absf(indicator.shield_share() - expected_regen) < 0.01,
		"shield bar grows through parry regeneration")

	_player._parry_cooldown_left = 0.0
	_player._parry_window_left = 0.2
	_player._parry_perfect_left = 0.08
	indicator.refresh(_player)
	_expect(is_equal_approx(indicator.shield_share(), 1.0),
		"active parry keeps the shield readiness geometry valid")

	var maximum := _player.maximum_health()
	_player.stats.set_health(maximum * 0.4)
	indicator.refresh(_player)
	_expect(absf(indicator.health_share() - 0.4) < 0.01,
		"health bar sits under shield and tracks player health")
	var shield := indicator.find_child("ShieldBar", true, false) as ProgressBar
	var health := indicator.find_child("HealthBar", true, false) as ProgressBar
	_expect(indicator.find_child("JukeBar", true, false) == null
		and shield != null and health != null
		and shield.get_index() < health.get_index(),
		"the blue bar sits above health with no juke bar under the hotbar")
	_player.statuses.apply(CombatStatuses.POISON, 4.0, 3.0)
	indicator.refresh(_player)
	var goop := health.get_node_or_null("ToxicGoop") as ColorRect
	var track := health.get_theme_stylebox(&"background") as StyleBoxFlat
	_expect(indicator.toxic_active() and goop != null and goop.visible
			and track != null and track.border_width_left >= 4
			and track.border_color.is_equal_approx(ParryIndicator.TOXIC),
		"poison outlines the health bar in neon green goop")
	_player.statuses.clear(CombatStatuses.POISON)
	indicator.refresh(_player)
	_expect(not indicator.toxic_active() and goop != null and not goop.visible,
		"the toxic outline leaves when poison ends")
	var weapon_bar := _player.find_child("WeaponBar", true, false) as WeaponBar
	var juke_slot := weapon_bar.find_child("JukeSlot", true, false) as ItemSlot \
		if weapon_bar != null else null
	_player._juke_cooldown_left = 0.0
	if weapon_bar != null:
		weapon_bar._process(0.0)
	_expect(juke_slot != null and not juke_slot.cooldown_active
			and is_equal_approx(juke_slot.cooldown_fill, 1.0),
		"ready juke icon is full")
	_player._juke_cooldown_left = _player.juke_cooldown() * 0.4
	if weapon_bar != null:
		weapon_bar._process(0.0)
	_expect(juke_slot != null and juke_slot.cooldown_active
			and absf(juke_slot.cooldown_fill - 0.6) < 0.02,
		"juke icon refills through dash regeneration")
	_player._juke_cooldown_left = 0.0
	_player.stats.set_health(maximum)


func _check_mob_flash() -> void:
	var root := Node3D.new()
	var skeleton := Skeleton3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mesh.mesh = box
	root.add_child(skeleton)
	root.add_child(mesh)
	_world.add_child(root)
	var source_skin := Skin.new()
	mesh.skin = source_skin
	mesh.skeleton = mesh.get_path_to(skeleton)
	var original := mesh.mesh
	CombatantFlash.flash(root)
	await get_tree().process_frame
	var overlay := mesh.get_node_or_null("DamageFlashOverlay")
	_expect(overlay != null, "mob flash adds overlay child")
	_expect(mesh.mesh == original, "mob flash preserves source mesh/material")
	_expect(overlay.material_override != mesh.material_override,
		"overlay uses separate material")
	_expect(overlay.skin == source_skin
		and overlay.get_node_or_null(overlay.skeleton) == skeleton,
		"mob flash follows the source mesh's animated skeleton")
	for _frame in 90:
		await get_tree().process_frame
		if mesh.get_node_or_null("DamageFlashOverlay") == null:
			break
	_expect(mesh.get_node_or_null("DamageFlashOverlay") == null,
		"mob flash overlay cleans up")
	root.queue_free()


func _check_local_feedback() -> void:
	var remote := PLAYER.instantiate() as OnlinePlayer
	remote.peer_id = 99
	remote.defer_camera = true
	_world.add_child(remote)
	await get_tree().process_frame
	_expect(remote.combat_hud() == null, "remote player has no combat hud")
	_expect(remote.combat_feedback() == null, "remote player has no combat feedback")

	_count = 0
	_player.combat_feedback().damage_number.connect(_count_number)
	_player.combat_feedback().damage_taken(
		12.0, _player.global_position, 0, "Rammer")
	await get_tree().process_frame
	_expect(_count == 1, "local damage number signal fires once")
	_expect(_player.combat_feedback().hit_marker_remaining() <= 0.0,
		"taking a hit does not flash a hit marker")
	var hits := (_player.combat_hud() as CombatHud).hit_log() \
		if _player.combat_hud() is CombatHud else null
	_expect(hits != null and hits.visible and hits.lines().size() == 1
			and hits.lines()[0] == "Rammer  12",
		"the hit log names the attacker and the damage")
	_player.combat_feedback().damage_taken(
		9.0, _player.global_position, 0, "Ranger", "Ranger Shot")
	await get_tree().process_frame
	_expect(hits != null and hits.lines().size() == 2
			and hits.lines()[1] == "Ranger  9",
		"each hit appends a new log line")
	_player.combat_feedback().outgoing_damage(
		42.0, _player.global_position, 0, false, true, "lot")
	await get_tree().process_frame
	var layer := _player.hud.get_node_or_null("DamageNumbers") as Node
	var red := false
	if layer != null:
		for child in layer.get_children():
			var label := child as Label
			if label == null or label.text != "42":
				continue
			red = label.get_theme_color(&"font_color") == Color(1.0, 0.3, 0.25)
	_expect(red, "building damage pops a red number")
	_expect(_player.combat_feedback().hit_marker_remaining() > 0.0,
		"landing a hit flashes an X on the reticle")
	_expect(not _player.combat_feedback().hit_marker_is_kill(),
		"a non-lethal hit stays a white marker")
	_player.combat_feedback().outgoing_damage(
		9.0, _player.global_position, 0, false, false, "mob", true)
	_expect(_player.combat_feedback().hit_marker_is_kill(),
		"a killing blow turns the marker gold")
	_expect(_player.combat_feedback().hit_marker_remaining() > HitMarker.HIT_TIME,
		"a kill marker holds longer than a regular hit")
	_player.combat_feedback().loot_gained(8.0, 12.0, _player.global_position)
	await get_tree().process_frame
	var gold := false
	var xp := false
	if layer != null:
		for child in layer.get_children():
			var label := child as Label
			if label == null:
				continue
			var colour := label.get_theme_color(&"font_color")
			if label.text == "$8" and colour.r > 0.85 and colour.g > 0.65:
				gold = true
			if label.text == "+12" and colour.b > 0.7:
				xp = true
	_expect(gold, "kills float a golden $ amount")
	_expect(xp, "kills float blue XP")
	await _check_number_jiggle(layer as DamageNumberLayer)
	remote.queue_free()


## The screen itself, driven from the signal the host fires rather than from a
## real kill: what a killing blow does is the combat suite's business, and this
## world has no planet to be killed on.
func _check_death_screen() -> void:
	var notice := "Killed by %s" % BigfootBoss.DISPLAY_NAME
	_player.died.emit(0, notice)
	await get_tree().process_frame
	var screen := _player.death_screen()
	_expect(screen != null, "dying puts a screen in front of the local player")
	if screen == null:
		return
	_expect(screen.get_parent() == _player.hud,
		"on the HUD layer, over everything else the player owns")
	var read := ""
	for node: Node in screen.find_children("*", "Label", true, false):
		var line := (node as Label).text
		if line == notice:
			read = line
	_expect(read == "Killed by Bigfoot",
		"and it says who did it: %s" % [read if not read.is_empty()
			else "nothing found"])
	# The mouse mode itself is not worth asserting under the headless display
	# server, which reports one whatever it is set to.
	_expect(screen.mouse_filter == Control.MOUSE_FILTER_STOP
		and not _player.controls_enabled,
		"the screen takes the input the world was getting")
	_expect(screen.process_mode == Node.PROCESS_MODE_ALWAYS,
		"and it answers whether or not the world is running")

	var asked := [0]
	screen.respawn_requested.connect(func() -> void: asked[0] += 1)
	var button := screen.respawn_button()
	screen._process(DeathScreen.ARM_DELAY + 0.1)
	_expect(button != null and not button.disabled
		and is_equal_approx(screen.modulate.a, 1.0),
		"the button arms once the screen has faded up")
	button.pressed.emit()
	button.pressed.emit()
	_expect(asked[0] == 1, "and asks for one respawn however often it is hit")

	_player.respawned.emit()
	await get_tree().process_frame
	_expect(_player.death_screen() == null and _player.controls_enabled,
		"coming back takes the screen away and gives the world the input")

	var remote := PLAYER.instantiate() as OnlinePlayer
	remote.peer_id = 77
	remote.defer_camera = true
	_world.add_child(remote)
	await get_tree().process_frame
	remote.died.emit(0, notice)
	await get_tree().process_frame
	_expect(remote.death_screen() == null,
		"nobody is shown anyone else's death")
	remote.queue_free()


func _check_number_jiggle(layer: DamageNumberLayer) -> void:
	if layer == null or _player.camera == null:
		_expect(false, "damage numbers can jiggle")
		return
	var spots: Array[Vector2] = []
	for i in 5:
		var event := DamageNumberEvent.new()
		event.amount = 3.0 + float(i)
		event.world_position = _player.global_position + Vector3(4.0, 1.0, 0.0)
		event.merge_key = "jiggle-%d" % i
		layer.show_event(event, _player.camera)
		var label := _number_label(layer, event.caption())
		if label != null:
			spots.append(label.position)
	var spread := false
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if spots[i].distance_to(spots[j]) > 2.0:
				spread = true
	_expect(spread, "hits peel off the body in different spots")
	var wobble := _number_label(layer, "3")
	if wobble == null:
		_expect(false, "a popped number jiggles as it rises")
		return
	var start := wobble.position
	for _frame in 4:
		await get_tree().process_frame
	_expect(is_instance_valid(wobble) and (
			absf(wobble.position.x - start.x) > 0.4
			or absf(wobble.rotation) > 0.01),
		"a popped number jiggles as it rises")


func _number_label(layer: Node, text: String) -> Label:
	if layer == null:
		return null
	for child in layer.get_children():
		var label := child as Label
		if label != null and label.text == text:
			return label
	return null


var _count := 0
func _count_number(_event: DamageNumberEvent) -> void:
	_count += 1


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("combat_hud_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("combat_hud_test: FAIL  %s" % message)


func _snapshot_settings() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_PATH)
	_settings_existed = FileAccess.file_exists(path)
	if _settings_existed:
		_settings_bytes = FileAccess.get_file_as_bytes(path)


func _restore_settings() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_PATH)
	if _settings_existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_settings_bytes)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
