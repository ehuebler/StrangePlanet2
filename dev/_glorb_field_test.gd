extends Node

## Field Glorbs: two of each kind, inbound from 150 m, agro at 50 m.
##
##     godot --headless --path . dev/_glorb_field_test.tscn

var _failures := 0


class _Prey extends Node3D:
	var velocity := Vector3.ZERO

	func look_direction() -> Vector3:
		return Vector3.FORWARD


func _ready() -> void:
	CrawlerRules.glorb_field = true
	CrawlerRules.reset_glorb_field_prefs()
	CrawlerCatalog.reload()
	CrawlerMobs.reload()
	NetworkManager.session_options = {"mode": "crawler"}
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)

	var kinds := CrawlerRules.field_kinds("Tide Margin 4")
	_expect(kinds.size() == 7
			and kinds.has("glorb_rhino")
			and kinds.has("glorb_jellyfish")
			and kinds.has("glorb_eyeball")
			and kinds.has("glorb_punching")
			and kinds.has("glorb_one_armed")
			and kinds.has("glorb_spider")
			and kinds.has("glorb_angel")
			and is_equal_approx(CrawlerRules.GLORB_SPAWN, 150.0)
			and CrawlerRules.GLORB_EACH == 2
			and CrawlerRules.kind_cap("glorb_rhino", 3) == 2,
		"every patch fields two of each Glorb from 150 m")
	CrawlerRules.set_glorb_kind_enabled("glorb_spider", false)
	CrawlerRules.set_glorb_each(4)
	_expect(not CrawlerRules.field_kinds("Tide Margin 4").has("glorb_spider")
			and CrawlerRules.kind_cap("glorb_spider", 1) == 0
			and CrawlerRules.kind_cap("glorb_rhino", 1) == 4
			and CrawlerRules.glorb_roster_kinds().size() == 6,
		"the M menu can switch a kind off and raise the around-you count")
	CrawlerRules.set_glorb_kind_count("glorb_rhino", 7)
	_expect(CrawlerRules.kind_cap("glorb_rhino", 1) == 7
			and CrawlerRules.kind_cap("glorb_angel", 1) == 4,
		"the M menu can set a different around-you count per kind")
	CrawlerRules.reset_glorb_field_prefs()
	_expect(CrawlerRules.field_kinds("Tide Margin 4").has("glorb_spider")
			and CrawlerRules.kind_cap("glorb_rhino", 1) == 2
			and CrawlerRules.kind_cap("glorb_angel", 1) == 2,
		"field prefs reset to two of every Glorb")
	_expect(CrawlerHunt.role("glorb_rhino") == CrawlerHunt.Role.GROUND_RANGE
			and CrawlerHunt.role("glorb_one_armed") == CrawlerHunt.Role.GROUND_RANGE
			and CrawlerHunt.role("glorb_spider") == CrawlerHunt.Role.GROUND_RANGE
			and CrawlerHunt.role("glorb_jellyfish") == CrawlerHunt.Role.FLY_RANGE
			and CrawlerHunt.role("glorb_angel") == CrawlerHunt.Role.FLY_RANGE
			and CrawlerHunt.role("glorb_eyeball") == CrawlerHunt.Role.MELEE
			and CrawlerHunt.role("glorb_punching") == CrawlerHunt.Role.MELEE,
		"Glorbs borrow rhino, ranger, rammer, tanglemaw, gray, weaver, and vesper hunts")
	_expect(CrawlerRules.flies("glorb_jellyfish")
			and CrawlerRules.flies("glorb_angel")
			and CrawlerRules.flies("glorb_eyeball")
			and not CrawlerRules.flies("glorb_rhino"),
		"jellyfish, angel, and eyeball stay airborne")

	var prey := _Prey.new()
	prey.name = "GlorbPrey"
	prey.add_to_group(&"network_players")
	add_child(prey)
	prey.global_position = Vector3.ZERO
	CrawlerMobSense.invalidate()
	CrawlerMobSense.begin_frame(get_tree())

	var seen: Dictionary = {}
	for kind: String in CrawlerRules.GLORB_KINDS:
		var mob := horde.spawn_test_mob(kind, Vector3(200.0, 2.0, 0.0), false, 1)
		mob.set_physics_process(false)
		mob.set_process(false)
		seen[kind] = mob.wild_kind()
		var tag := mob.get_node_or_null("TrainingRange") as Label3D
		_expect(mob.wild_kind() == kind and not mob.chase
				and tag != null and tag.font_size >= 56,
			"%s spawns deagroed with a large range tag" % kind)
		mob.set_inbound(Vector3(-1.0, 0.0, 0.0))
		var held := mob.inbound_heading
		prey.global_position = Vector3(0.0, 0.0, 40.0)
		mob.director_far_steer(0.16, prey, false)
		_expect(mob.inbound_heading.dot(held) > 0.92 and not mob.chase,
			"%s keeps its inbound heading until 50 m" % kind)
		prey.global_position = Vector3.ZERO
		mob.global_position = Vector3(60.0, 2.0, 0.0)
		_expect(not mob.tick_agro(prey, 0.16) and not mob.chase,
			"%s stays calm at 60 m" % kind)
		mob.global_position = Vector3(35.0, 2.0, 0.0)
		_expect(mob.tick_agro(prey, 0.16) and mob.chase
				and CrawlerHunt.hunting(mob.hunt_stance),
			"%s agros inside 50 m" % kind)
		mob.global_position = Vector3(100.0, 2.0, 0.0)
		mob.tick_agro(prey, 0.16)
		_expect(mob.dismissed or not is_instance_valid(mob),
			"%s leaves after it deagros so another can spawn" % kind)

	var rhino := horde.spawn_test_mob("glorb_rhino", Vector3(12.0, 2.0, 0.0), false, 1)
	rhino.set_physics_process(false)
	var ram := rhino._resolve_clip(CrawlerRhino.CLIP_CHARGE)
	_expect(not ram.is_empty() and ram.to_lower().contains("ram")
			and _clip_seconds(rhino, ram) > 0.5,
		"the rhino Glorb uses Ram for its meteor strike")
	var walk := rhino._resolve_clip(CrawlerMob.CLIP_WALK)
	var rhino_run := rhino._resolve_clip(CrawlerMob.CLIP_RUN)
	_expect(not walk.is_empty() and walk.to_lower().contains("walk")
			and _clip_seconds(rhino, walk) > 0.5
			and not rhino_run.is_empty() and rhino_run.to_lower().contains("run")
			and _clip_seconds(rhino, rhino_run) > 0.5,
		"the rhino Glorb keeps real Walk and Run clips, not the empty NLA stubs")
	rhino.velocity = Vector3(-7.0, 0.0, 0.0)
	rhino.set_inbound(Vector3(-1.0, 0.0, 0.0))
	rhino._update_clips()
	_expect(rhino.current_clip() == CrawlerMob.CLIP_RUN
			and rhino._animator != null
			and str(rhino._animator.current_animation).to_lower().contains("run")
			and _clip_seconds(rhino, str(rhino._animator.current_animation)) > 0.5,
		"deagroed Glorb rhinos play Run while they close")
	var charger := rhino as CrawlerRhino
	_expect(charger != null and charger._uses_model_front,
		"the Glorb rhino uses its authored +Z face")
	if charger != null:
		charger.chase = false
		charger.global_position = Vector3(0.0, 80.0, 0.0)
		charger.inbound_heading = Vector3.LEFT
		charger.velocity = Vector3.LEFT * 6.0
		charger.global_transform.basis = Basis.IDENTITY
		charger._run_glorb_inbound(1.0)
		_expect(charger.global_transform.basis.z.dot(Vector3.LEFT) > 0.7,
			"an inbound Glorb rhino faces the way it runs")
		charger.inbound_heading = Vector3.ZERO
		charger._phase = CrawlerRhino.Phase.STALK
		charger.velocity = Vector3(-10.0, 0.0, 0.0)
		charger._update_clips()
		_expect(charger.current_clip() == CrawlerMob.CLIP_RUN
				and str(charger._animator.current_animation).to_lower().contains("run")
				and _clip_seconds(charger, str(charger._animator.current_animation)) > 0.5,
			"a running Glorb rhino plays Run")
		charger._face = Vector3.FORWARD
		charger._charge_heading = Vector3.FORWARD
		charger._face_along(Vector3.FORWARD, 1.0)
		var horn := charger._nose_point()
		_expect((horn - charger.global_position).dot(Vector3.FORWARD) > 0.15,
			"the Glorb rhino head sits on the forward side")
		charger._begin_paw(Vector3.FORWARD)
		charger._face_along(Vector3.FORWARD, 1.0)
		charger._update_meteor_shock()
		var shock := charger.find_child("MeteorShock", true, false) as MeteorShock
		_expect(shock != null and shock.visible
				and shock.global_transform.basis.y.dot(Vector3.FORWARD) > 0.5,
			"the Glorb meteor cone aims out the head")
		_expect(shock != null and shock.global_position.distance_to(horn) < 2.8,
			"the Glorb meteor cone sits on the head")
		charger._abort_charge()
	_expect(rhino._materials.size() > 0
			and rhino._materials[0] != null
			and rhino._materials[0].shader == CrawlerGlorb.SKIN_SHADER
			and rhino._materials[0].next_pass == null
			and rhino._visual != null
			and rhino._visual.material_override == rhino._materials[0],
		"Glorbs wear the animated ethereal skin without a rim outline")
	var import_text := FileAccess.get_file_as_string(
		"res://assets/runtime/crawler/glorbs/glorb_rhino.glb.import")
	_expect(import_text.contains("meshes/light_baking=0"),
		"Glorb imports do not generate a lightmap UV2")
	_expect(float(rhino._materials[0].get_shader_parameter(&"flash")) < 0.01
			and float(rhino._materials[0].get_shader_parameter(&"rim_strength")) < 0.01,
		"idle Glorbs are not flashed or rim-lit red")
	_expect(_mesh_laser_connects(rhino),
		"a laser through the rhino mesh hits its pill, not only the body origin")

	var jelly := horde.spawn_test_mob("glorb_jellyfish", Vector3(8.0, 6.0, 0.0), false, 1)
	jelly.set_physics_process(false)
	jelly.velocity = Vector3(-12.0, 0.0, 0.0)
	jelly._update_clips()
	var swim := jelly._resolve_clip(CrawlerMob.CLIP_FLY)
	var pulse := jelly._resolve_clip(CrawlerMob.CLIP_ATTACK)
	_expect(not swim.is_empty() and swim.to_lower().contains("pulse")
			and swim == pulse
			and _clip_seconds(jelly, swim) > 0.5
			and _clip_scale_swing(jelly, swim) > 0.08
			and jelly.current_clip() == CrawlerMob.CLIP_FLY
			and jelly._animator != null
			and jelly._animator.is_playing()
			and str(jelly._animator.current_animation).to_lower().contains("pulse")
			and _clip_seconds(jelly, str(jelly._animator.current_animation)) > 0.5,
		"a flying jellyfish plays its real tentacle pulse")
	jelly._pending_shot = true
	jelly._aim_left = 0.25
	jelly._attack_left = 0.25
	jelly.velocity = Vector3(18.0, 0.0, 0.0)
	jelly._hold_to_aim(prey, jelly.global_position, 0.16)
	jelly._update_flash()
	jelly._update_clips()
	var ink := jelly._materials[0] if jelly._materials.size() > 0 else null
	var flash := float(ink.get_shader_parameter(&"flash")) if ink != null else 0.0
	_expect(not pulse.is_empty() and pulse.to_lower().contains("pulse")
			and jelly.current_clip() == CrawlerMob.CLIP_ATTACK
			and str(jelly._animator.current_animation).to_lower().contains("pulse")
			and jelly._animator.speed_scale > 1.6
			and jelly.velocity.length() < 18.0
			and flash > 0.6,
		"a winding jellyfish hovers, turns red, and pulses fast")
	jelly._abort_aim()
	jelly._attack_left = 0.0
	jelly.velocity = Vector3(-10.0, 0.0, 0.0)
	jelly._update_flash()
	jelly._update_clips()
	var rest := float(ink.get_shader_parameter(&"flash")) if ink != null else 1.0
	_expect(jelly.current_clip() == CrawlerMob.CLIP_FLY
			and str(jelly._animator.current_animation).to_lower().contains("pulse")
			and rest < 0.05,
		"after the shot the jellyfish keeps pulsing")

	_expect(CrawlerRules.is_glorb_soft_flyer("glorb_jellyfish")
			and CrawlerRules.is_glorb_soft_flyer("glorb_angel")
			and not CrawlerRules.is_glorb_soft_flyer("glorb_eyeball")
			and CrawlerRules.GLORB_FLYER_MATCH_LAG
				< CrawlerRules.ranger_match_lag(1)
			and CrawlerRules.GLORB_FLYER_MATCH_FLOOR
				< CrawlerRules.ranger_match_floor(1)
			and CrawlerRules.GLORB_FLYER_MATCH_LOCK
				< CrawlerRules.ranger_match_lock(1),
		"angel and jellyfish spool toward a runner more slowly than a ranger")
	prey.global_position = Vector3.ZERO
	prey.velocity = Vector3(40.0, 0.0, 0.0)
	var angel := horde.spawn_test_mob("glorb_angel", Vector3(28.0, 8.0, 0.0), false, 1) \
		as CrawlerGlorbAngel
	angel.set_physics_process(false)
	var fly := angel._resolve_clip(CrawlerMob.CLIP_FLY)
	angel.velocity = Vector3(-3.0, 0.0, 0.0)
	angel.set_inbound(Vector3(-1.0, 0.0, 0.0))
	angel._update_clips()
	_expect(not fly.is_empty() and fly.to_lower().contains("fly")
			and _clip_seconds(angel, fly) > 0.5
			and angel.current_clip() == CrawlerMob.CLIP_FLY
			and str(angel._animator.current_animation).to_lower().contains("fly")
			and _clip_seconds(angel, str(angel._animator.current_animation)) > 0.5,
		"a moving angel plays its Fly clip, not a standing Walk")
	_expect(_mesh_laser_connects(angel),
		"a laser through the angel mesh hits its pill, not only the body origin")
	for flyer in [jelly, angel] as Array[CrawlerMob]:
		flyer.chase = true
		flyer.inbound_heading = Vector3.ZERO
		flyer._cruise = 0.0
		flyer.velocity = Vector3.ZERO
		flyer.global_position = Vector3(28.0, 8.0, 0.0)
		var hold: Vector3 = flyer._hover_hold(prey.global_position, 28.0)
		for _step in 3:
			flyer._close_on(prey, hold, 40.0, 28.0, 40.0, 40.0, 0.16)
		_expect(flyer._cruise > 0.2 and flyer._cruise < 2.4
				and flyer.velocity.length() < 12.0,
			"%s lags while it winds up to the player's speed" % flyer.wild_kind())
		for _step in 25:
			flyer._close_on(prey, hold, 40.0, 28.0, 40.0, 40.0, 0.16)
		_expect(flyer._cruise > 6.0,
			"%s does catch a runner after a longer spool" % flyer.wild_kind())
		flyer.chase = false
		flyer._cruise = 0.0
		flyer.velocity = Vector3.ZERO
		flyer.set_inbound(Vector3(-1.0, 0.0, 0.0))
		flyer._run_glorb_inbound(0.16)
		_expect(flyer._cruise > 0.2 and flyer._cruise < 2.4,
			"%s also lags on the inbound close" % flyer.wild_kind())
	var pack: Array[CrawlerMob] = []
	for i in 5:
		var buddy := horde.spawn_test_mob("glorb_jellyfish", Vector3(-28.0, 8.0, 0.0), false, 1)
		buddy.set_physics_process(false)
		buddy.mob_id = "ring-jelly-%d" % i
		buddy._cached_up = Vector3.UP
		buddy._cached_up_at = buddy.global_position
		buddy.global_position = Vector3(-28.0, 8.0, 0.0)
		buddy._drift_clock = (TAU * float(i) / 5.0 - buddy._ring_seed()) \
			/ buddy._ring_spin()
		pack.append(buddy)
	var slots: Array[Vector3] = []
	for buddy in pack:
		var slot: Vector3 = buddy._hover_hold(Vector3.ZERO, 28.0)
		var flat := Vector3(slot.x, 0.0, slot.z)
		_expect(flat.length() > 24.0 and flat.length() < 32.0,
			"a jellyfish hold sits on the ring around the player")
		slots.append(flat.normalized())
	var spread := 0
	for i in slots.size():
		for j in range(i + 1, slots.size()):
			if slots[i].dot(slots[j]) < 0.55:
				spread += 1
	_expect(spread >= 8,
		"jellyfish ring slots stay spread instead of stacking in the wake")
	var rear := pack[0]
	rear._drift_clock = (0.5 * PI - rear._ring_seed()) / rear._ring_spin()
	var wake: Vector3 = rear._hover_hold(Vector3.ZERO, 28.0)
	_expect(Vector3(wake.x, 0.0, wake.z).normalized().dot(Vector3.LEFT) > 0.85,
		"some jellyfish still hold the slot behind a runner")
	var flank := pack[1]
	flank._drift_clock = (0.0 - flank._ring_seed()) / flank._ring_spin()
	flank._cruise = 18.0
	flank.velocity = Vector3(18.0, 0.0, 0.0)
	flank.chase = true
	var side_hold: Vector3 = flank._hover_hold(Vector3.ZERO, 28.0)
	prey.velocity = Vector3(40.0, 0.0, 0.0)
	for _step in 10:
		flank._flyer_track(prey, 0.16)
	var side := Vector3(side_hold.x, 0.0, side_hold.z)
	_expect(flank.velocity.x > 8.0
			and absf(flank.velocity.z) > 2.0
			and side.length() > 20.0
			and absf(side.z) > absf(side.x) * 0.55,
		"a jellyfish strafes onto its ring slot while the player sprints")
	angel._cruise = 0.0
	angel.velocity = Vector3.ZERO
	angel._locked = prey.global_position
	angel._aim_left = 1.0
	angel._hold_aim(prey, angel.global_position, 0.16)
	_expect(angel._cruise < 2.4 and angel.velocity.length() < 16.0,
		"an aiming angel still lags behind the player's frame")
	prey.velocity = Vector3.ZERO

	var eye := horde.spawn_test_mob("glorb_eyeball", Vector3(40.0, 28.0, 0.0), false, 1) \
		as CrawlerGlorbEyeball
	eye.set_physics_process(false)
	_expect(eye != null and not eye.chase
			and eye.flyer_floor() >= 20.0
			and eye.flyer_ceiling() <= 50.5
			and eye._soar_loft >= 20.0 and eye._soar_loft <= 50.0
			and horde._lift_for("glorb_eyeball", 0) >= 20.0
			and horde._lift_for("glorb_eyeball", 40) <= 50.0,
		"a calm eyeball hangs between 20 and 50 m")
	prey.global_position = Vector3.ZERO
	prey.velocity = Vector3(12.0, 0.0, 0.0)
	eye.chase = true
	eye.ever_chased = true
	eye.hunt_stance = CrawlerHunt.Stance.AGRO
	eye._phase = CrawlerRammer.Phase.SOAR
	eye.global_position = Vector3(0.0, 18.0, -40.0)
	eye._cruise = 0.0
	eye.velocity = Vector3.ZERO
	eye._tick_ai(0.16)
	var perch := eye.show_station(prey)
	_expect(eye.staging() and not eye.ramming()
			and absf(perch.z + 30.0) < 1.0
			and perch.y >= 2.5
			and eye._stage_top_speed(prey) >= 11.5
			and eye._ram_top_speed(prey) >= 5.0
			and eye._ram_top_speed(prey) <= 8.0,
		"an agroed eyeball flutters 30 m in front of the camera above the horizon")
	eye.velocity = Vector3(0.0, 0.0, -8.0)
	eye._update_clips()
	var eye_run := eye._resolve_clip(CrawlerMob.CLIP_RUN)
	_expect(not eye_run.is_empty() and eye_run.to_lower().contains("run")
			and eye.current_clip() == CrawlerMob.CLIP_RUN
			and eye._animator != null
			and str(eye._animator.current_animation).to_lower().contains("run"),
		"a fluttering eyeball plays Run")
	eye.global_position = perch
	eye._glide_loft = eye._altitude(perch)
	eye.velocity = Vector3.ZERO
	eye._tick_ai(0.16)
	_expect(eye.ramming() and eye.in_camera(prey)
			and eye._ram_top_speed(prey) >= 5.0
			and eye._ram_top_speed(prey) <= 8.0,
		"once on station the eyeball charges the face at 5-8 m/s")
	prey.velocity = Vector3.ZERO

	var fist := horde.spawn_test_mob("glorb_punching", Vector3(0.0, 2.0, 0.0), false, 1) \
		as CrawlerGlorbPunching
	fist.set_physics_process(false)
	prey.global_position = Vector3(10.0, 2.0, 0.0)
	fist.chase = true
	fist._face_player(1.0)
	var toward := fist.global_transform.basis.z
	toward -= Vector3.UP * toward.dot(Vector3.UP)
	_expect(not fist.flies()
			and fist._uses_model_front
			and fist.move_speed() <= CrawlerGlorbPunching.PURSUE_SPEED
			and CrawlerHunt.pursuit_speed("glorb_punching", 40.0, 15.0) <= 15.0
			and toward.length() > 0.2
			and toward.normalized().dot(Vector3.RIGHT) > 0.7,
		"an agroed punching Glorb stays grounded, faces the player, and caps at 15 m/s")
	fist.velocity = Vector3.ZERO
	fist._run_at(prey, 0.4)
	fist._update_clips()
	var fist_run := fist._resolve_clip(CrawlerMob.CLIP_RUN)
	var fist_punch := fist._resolve_clip(CrawlerMob.CLIP_ATTACK)
	_expect(not fist_run.is_empty() and fist_run.to_lower().contains("run")
			and fist.current_clip() == CrawlerMob.CLIP_RUN
			and fist._cruise <= CrawlerGlorbPunching.PURSUE_SPEED + 0.05
			and absf(fist.velocity.dot(Vector3.UP)) < 0.2
			and str(fist._animator.current_animation).to_lower().contains("run"),
		"a punching Glorb runs on the ground toward the player")
	fist._pending_punch = true
	fist._windup_left = 0.2
	fist._attack_left = 0.2
	fist.velocity = Vector3(12.0, 0.0, 0.0)
	fist._service_punch(prey, 0.08)
	fist._update_flash()
	fist._update_clips()
	var fist_ink := fist._materials[0] if fist._materials.size() > 0 else null
	var fist_flash := float(fist_ink.get_shader_parameter(&"flash")) \
		if fist_ink != null else 0.0
	_expect(not fist_punch.is_empty() and fist_punch.to_lower().contains("punch")
			and _clip_seconds(fist, fist_punch) > 0.5
			and fist.current_clip() == CrawlerMob.CLIP_ATTACK
			and fist._animator.is_playing()
			and str(fist._animator.current_animation).to_lower().contains("punch")
			and _clip_seconds(fist, str(fist._animator.current_animation)) > 0.5
			and fist.velocity.length() < 12.0
			and fist_flash > 0.5,
		"a punching Glorb plants, turns red, and plays Punch")
	prey.global_position = Vector3(0.0, 2.0, 10.0)
	fist.hunt_stance = CrawlerHunt.Stance.PURSUE
	fist._service_punch(prey, 0.08)
	fist._face_combat_player(0.08)
	var punch_look := fist.global_transform.basis.z
	punch_look -= Vector3.UP * punch_look.dot(Vector3.UP)
	_expect(fist._winding_up()
			and punch_look.length() > 0.2
			and punch_look.normalized().dot(Vector3.BACK) > 0.7,
		"a planted punching Glorb still turns to face the player")

	CrawlerMobSense.invalidate()
	CrawlerMobSense.begin_frame(get_tree())
	var rifle := horde.spawn_test_mob("glorb_one_armed", Vector3(45.0, 2.0, 0.0), false, 1) \
		as CrawlerGlorbOneArmed
	rifle.set_physics_process(false)
	rifle._cached_up = Vector3.UP
	rifle._cached_up_at = rifle.global_position
	prey.global_position = Vector3.ZERO
	prey.velocity = Vector3.ZERO
	rifle.chase = true
	rifle.ever_chased = true
	rifle.hunt_stance = CrawlerHunt.Stance.AGRO
	rifle._fire_left = 0.0
	rifle._cruise = 0.0
	rifle.velocity = Vector3.ZERO
	_expect(CrawlerHunt.shot_min("glorb_one_armed") <= 12.0
			and CrawlerHunt.shot_max("glorb_one_armed") >= 48.0
			and CrawlerGlorbOneArmed.KEEP_RANGE == 30.0
			and CrawlerGlorbOneArmed.BACK_SPEED == 8.0,
		"one-armed Glorbs can shoot from agro range and kite to 30 m")
	rifle._tick_ai(0.16)
	_expect(bool(rifle._aiming()) and rifle.velocity.length() < 2.5
			and rifle._cruise < 1.2,
		"an agroed one-armed Glorb shoots from 45 m instead of walking in")
	rifle._abort_aim()
	rifle._fire_left = 0.0
	rifle.global_position = Vector3(22.0, 2.0, 0.0)
	rifle._cached_up_at = rifle.global_position
	rifle._cruise = 0.0
	rifle.velocity = Vector3.ZERO
	rifle._tick_ai(0.16)
	_expect(rifle.velocity.x > 0.15 and rifle._cruise > 0.3
			and rifle._cruise < 3.2
			and bool(rifle._aiming()),
		"inside 30 m it starts backing up and can still fire")
	for _step in 18:
		rifle._abort_aim()
		rifle._fire_left = 0.0
		rifle._kite(prey, 0.16)
	_expect(rifle.velocity.x > 0.8
			and rifle._cruise > 5.0
			and rifle._cruise <= CrawlerGlorbOneArmed.BACK_SPEED + 0.05,
		"the kite accelerates up to 8 m/s to restore 30 m")

	var spider := horde.spawn_test_mob("glorb_spider", Vector3(18.0, 2.0, 0.0), false, 1) \
		as CrawlerGlorbSpider
	spider.set_physics_process(false)
	_stand_flat(spider, Vector3(18.0, 2.0, 0.0))
	prey.global_position = Vector3.ZERO
	prey.velocity = Vector3(40.0, 0.0, 12.0)
	_expect(spider != null and spider.tick_agro(prey, 0.16) and spider.chase
			and spider.hunt_stance == CrawlerHunt.Stance.AGRO
			and bool(spider.charging())
			and CrawlerHunt.pursuit_speed("glorb_spider", 40.0, 8.6)
				== CrawlerGlorbSpider.PURSUE_SPEED,
		"an agroed spider plants and charges even if the player is sprinting")
	spider._tick_hunt_motion(prey, 0.16)
	_expect(spider.velocity.length() < 1.2 and not bool(spider.hopping())
			and bool(spider.beaming()),
		"a spider inside 20 m stands still to aim")
	spider._stop_beam()
	spider._fire_left = 0.0
	_expect(bool(spider.call("_shot_ready", prey, 18.0)),
		"a spider does not wait for the camera before it charges")
	spider._cruise = 0.0
	spider.velocity = Vector3.ZERO
	_stand_flat(spider, Vector3(32.0, 2.0, 0.0))
	_expect(spider.tick_agro(prey, 0.16)
			and spider.hunt_stance == CrawlerHunt.Stance.PURSUE,
		"a spider outside 20 m runs at the player")
	spider._tick_hunt_motion(prey, 0.16)
	_expect(spider._cruise > 0.2 and spider._cruise < 4.0
			and spider.velocity.x < 0.0
			and not bool(spider.beaming()),
		"spider pursuit accelerates instead of snapping to 15 m/s")
	for _step in 24:
		spider._tick_hunt_motion(prey, 0.16)
	_expect(spider._cruise > 10.0
			and spider._cruise <= CrawlerGlorbSpider.PURSUE_SPEED + 0.05,
		"spider pursuit caps at 15 m/s")
	_stand_flat(spider, Vector3(14.0, 2.0, 0.0))
	spider._cruise = 12.0
	spider.velocity = Vector3(-12.0, 0.0, 0.0)
	_expect(spider.tick_agro(prey, 0.16)
			and spider.hunt_stance == CrawlerHunt.Stance.AGRO,
		"a pursuing spider plants again inside 15 m")
	spider._tick_hunt_motion(prey, 0.16)
	_expect(bool(spider.charging()) and spider.velocity.length() < 8.0
			and not bool(spider.hopping()),
		"inside 15 m the spider stops to take a shot")
	spider._stop_beam()
	spider._fire_left = 0.0
	spider._attack_left = 0.0
	_stand_flat(spider, Vector3(16.0, 2.0, 0.0))
	spider.velocity = Vector3(-9.0, 0.0, 4.0)
	prey.global_position = Vector3.ZERO
	spider._try_beam(prey)
	if not bool(spider.charging()):
		spider._lock_sweep(prey)
		spider._aim_left = 0.4
		spider._beam_prey = prey
	spider._hold_beam(0.05)
	var start_look := _flat_front(spider)
	var sweep_mid := Vector3(-1.0, 0.0, 0.0)
	_expect(bool(spider.charging()) and spider.velocity.length() < 0.05
			and start_look.dot(sweep_mid) < 0.92,
		"a charging spider plants and aims at the start of the sweep")
	var locked_sweep := spider.sweep_point()
	prey.global_position = Vector3(0.0, 2.0, 14.0)
	spider._hold_beam(0.16)
	_expect(_flat_front(spider).dot(start_look) > 0.96
			and spider.sweep_point().distance_to(locked_sweep) < 0.45,
		"a planted spider does not turn to track a sidestep")
	spider._aim_left = 0.0
	spider._start_fire()
	spider._beam_left = CrawlerWeaver.BEAM_SECONDS * 0.5
	spider._hold_beam(0.0)
	_expect(bool(spider.firing()) and _flat_front(spider).dot(sweep_mid) > 0.92,
		"the sweep crosses the player at mid-beam")
	spider._beam_left = 0.02
	spider._hold_beam(0.0)
	_expect(_flat_front(spider).dot(start_look) < 0.55
			and _flat_front(spider).dot(sweep_mid) < 0.92,
		"the laser finishes on the far side of the arc")
	var planted_gap := spider.combat_position().distance_to(Vector3.ZERO)
	_expect(spider._sweep_range > planted_gap + 3.0
			and spider._sweep_range <= CrawlerGlorbSpider.SWEEP_REACH,
		"spider laser eyes reach past the player")
	spider._stop_beam()
	spider._fire_left = 0.0
	spider._attack_left = 0.0
	_stand_flat(spider, Vector3(16.0, 2.0, 0.0))
	spider.velocity = Vector3.ZERO
	prey.global_position = Vector3(0.0, 12.0, 0.0)
	spider._plant_and_aim(prey, 0.0)
	_expect(_look_pitch(spider) > 0.18,
		"a planted spider tilts up at a high player")
	spider._try_beam(prey)
	if not bool(spider.charging()):
		spider._lock_sweep(prey)
		spider._aim_left = 0.4
		spider._beam_prey = prey
	spider._hold_beam(0.0)
	_expect(bool(spider.charging()) and _look_pitch(spider) > 0.18,
		"the sweep keeps that upward tilt")
	spider._stop_beam()
	spider._fire_left = 0.0
	spider._attack_left = 0.0
	prey.global_position = Vector3(0.0, -8.0, 0.0)
	spider._plant_and_aim(prey, 0.0)
	_expect(_look_pitch(spider) < -0.18,
		"a planted spider tilts down at a low player")
	spider._lock_sweep(prey)
	spider._hold_beam(0.0)
	_expect(_look_pitch(spider) < -0.18,
		"the sweep keeps that downward tilt")
	spider._stop_beam()
	prey.global_position = Vector3(spider.combat_position().x - 16.0, spider.combat_position().y, 0.0)
	spider._plant_and_aim(prey, 0.0)
	spider._lock_sweep(prey)
	spider._hold_beam(0.0)
	_expect(absf(_look_pitch(spider)) < 0.12,
		"a spider keeps the body level when the player is on the same plane")

	for kind: String in CrawlerRules.GLORB_KINDS:
		var body := horde.spawn_test_mob(kind, Vector3(0.0, 2.0, 0.0), false, 1)
		body.set_physics_process(false)
		body.set_process(false)
		body._refresh_hit_bounds()
		var pill: Dictionary = body.combat_capsule()
		var center: Vector3 = body.combat_position()
		var radius := body.combat_radius()
		var flat := center - body.global_position
		flat -= Vector3.UP * flat.dot(Vector3.UP)
		_expect(body._hit_ready and flat.length() < 1.15
				and radius > 0.2 and radius < 1.85
				and float(pill.get("radius", 0.0)) < 1.85
				and Vector3(pill.get("a")).distance_to(body.global_position) < 2.4,
			"%s keeps a tight hitbox on its mesh" % kind)
		if not CrawlerRules.flies(kind):
			var lowest := _planted_lowest(body)
			_expect(lowest != INF
					and absf(lowest + body.ground_clearance()) < 0.28,
				"%s plants its feet on the stand height" % kind)
		if kind == "glorb_one_armed" or kind == "glorb_jellyfish" \
				or kind == "glorb_angel":
			var from: Vector3 = body.muzzle_point()
			var muzzle_flat := from - body.global_position
			muzzle_flat -= Vector3.UP * muzzle_flat.dot(Vector3.UP)
			_expect(from.is_finite() and muzzle_flat.length() < 1.35
					and from.distance_to(center) < 1.6,
				"%s casts from its body, not empty air" % kind)

	prey.global_position = Vector3.ZERO
	prey.velocity = Vector3.ZERO
	horde._glorb_menu_serial = 0
	var agro := horde.spawn_glorb_ahead(prey, "glorb_jellyfish", true)
	var calm := horde.spawn_glorb_ahead(prey, "glorb_angel", false)
	var again := horde.spawn_glorb_ahead(prey, "glorb_rhino", true)
	for spawned in [agro, calm, again]:
		if spawned != null:
			spawned.set_physics_process(false)
			spawned.set_process(false)
	var agro_flat := Vector3(agro.global_position.x, 0.0, agro.global_position.z) \
		if agro != null else Vector3.ZERO
	var calm_flat := Vector3(calm.global_position.x, 0.0, calm.global_position.z) \
		if calm != null else Vector3.ZERO
	_expect(agro != null and agro.chase and agro.wild_kind() == "glorb_jellyfish"
			and agro_flat.distance_to(Vector3.ZERO)
				>= CrawlerRules.GLORB_AGRO - 1.0
			and agro_flat.distance_to(Vector3.ZERO)
				<= CrawlerRules.GLORB_AGRO + 1.0
			and agro.global_position.z < -40.0,
		"M-menu agro spawn sits 50 m in front of the player")
	_expect(calm != null and not calm.chase and calm.glorb_inbound()
			and calm.wild_kind() == "glorb_angel"
			and calm_flat.distance_to(Vector3.ZERO) > CrawlerRules.GLORB_AGRO
			and calm.inbound_heading.z > 0.7,
		"M-menu calm spawn stays deagroed just past 50 m and walks in")
	_expect(again != null and again != agro
			and again.global_position.distance_to(agro.global_position) > 1.5,
		"each M-menu click drops another Glorb")

	var menu_script := load("res://ui/menu/crawler_glorb_spawn_menu.gd") as GDScript
	var menu := menu_script.new() as Control
	menu.call(&"configure", prey)
	add_child(menu)
	var missing := 0
	for kind: String in CrawlerRules.GLORB_KINDS:
		if menu.find_child("Agro_%s" % kind, true, false) == null \
				or menu.find_child("Calm_%s" % kind, true, false) == null \
				or menu.find_child("On_%s" % kind, true, false) == null \
				or menu.find_child("Count_%s" % kind, true, false) == null \
				or menu.find_child("CountMinus_%s" % kind, true, false) == null \
				or menu.find_child("CountPlus_%s" % kind, true, false) == null:
			missing += 1
	var around := menu.find_child("AroundCount", true, false) as Label
	var card := menu.find_child("GlorbCard", true, false) as Control
	await get_tree().process_frame
	var view := menu.get_viewport_rect().size
	if view.y < 8.0:
		view = Vector2(1280.0, 720.0)
	menu.call(&"set_kind_on", "glorb_angel", false)
	menu.call(&"set_around_count", 5)
	menu.call(&"set_kind_count", "glorb_spider", 3)
	var spider_count := menu.find_child("Count_glorb_spider", true, false) as Label
	var angel_count := menu.find_child("Count_glorb_angel", true, false) as Label
	_expect(missing == 0
			and around != null and around.text == "5"
			and not CrawlerRules.glorb_kind_enabled("glorb_angel")
			and CrawlerRules.glorb_each == 5
			and CrawlerRules.glorb_kind_count("glorb_spider") == 3
			and CrawlerRules.kind_cap("glorb_spider", 1) == 3
			and CrawlerRules.kind_cap("glorb_angel", 1) == 0
			and spider_count != null and spider_count.text == "3"
			and angel_count != null and angel_count.text == "5",
		"the M menu lists every Glorb and edits the field roster")
	_expect(card != null and card.offset_top <= 40.0
			and card.offset_bottom <= view.y - 8.0,
		"the M menu sits high enough that the close row stays on screen")
	var clicked := menu.call(&"spawn_kind", "glorb_spider", true) as CrawlerMob
	_expect(clicked != null and clicked.chase
			and clicked.wild_kind() == "glorb_spider",
		"the M menu keeps spawning on each click")
	menu.call(&"close")
	CrawlerRules.reset_glorb_field_prefs()

	if _failures > 0:
		push_error("glorb field test failed %d checks" % _failures)
		get_tree().quit(1)
		return
	print("glorb field test passed")
	get_tree().quit(0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("FAIL " + label)


func _stand_flat(mob: CrawlerMob, at: Vector3) -> void:
	if mob == null:
		return
	mob.global_position = at
	mob._cached_up = Vector3.UP
	mob._cached_up_at = at


func _flat_front(mob: Node3D) -> Vector3:
	if mob == null:
		return Vector3.ZERO
	var look := mob.global_transform.basis.z
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return Vector3.ZERO
	return look.normalized()


func _look_pitch(mob: Node3D) -> float:
	if mob == null:
		return 0.0
	var look := mob.global_transform.basis.z
	if look.length_squared() < 0.0001:
		return 0.0
	look = look.normalized()
	var flat := Vector3(look.x, 0.0, look.z)
	if flat.length_squared() < 0.0001:
		return 0.0
	return atan2(look.y, flat.length())


func _planted_lowest(mob: CrawlerMob) -> float:
	if mob == null:
		return INF
	var root := mob.find_child("Creature", true, false) as Node3D
	if root == null:
		return INF
	var inverse := mob.global_transform.affine_inverse()
	var lowest := INF
	for node_variant: Variant in root.find_children("*", "Skeleton3D", true, false):
		var skeleton := node_variant as Skeleton3D
		if skeleton == null:
			continue
		for bone in skeleton.get_bone_count():
			var at := inverse * skeleton.global_transform \
				* skeleton.get_bone_global_pose(bone).origin
			lowest = minf(lowest, at.y)
	return lowest


func _mesh_laser_connects(mob: CrawlerMob) -> bool:
	if mob == null or not mob._hit_ready:
		return false
	var pill: Dictionary = mob.combat_capsule()
	var mid: Vector3 = (pill["a"] + pill["b"]) * 0.5
	var radius := float(pill["radius"])
	if radius < 0.2:
		return false
	var beam := DamageHit.beam(
		mid + Vector3(0.0, 0.0, 5.0),
		mid + Vector3(0.0, 0.0, -5.0),
		0.2, 8.0)
	beam.faction = DamageHit.Faction.PLAYER
	var miss := DamageHit.beam(
		mid + Vector3(radius + 1.8, 0.0, 5.0),
		mid + Vector3(radius + 1.8, 0.0, -5.0),
		0.15, 8.0)
	miss.faction = DamageHit.Faction.PLAYER
	return beam.affects_combatant(mob) and not miss.affects_combatant(mob)


func _clip_seconds(mob: CrawlerMob, clip: String) -> float:
	if mob == null or mob._animator == null or clip.is_empty():
		return 0.0
	if not mob._animator.has_animation(clip):
		return 0.0
	var animation := mob._animator.get_animation(clip)
	return animation.length if animation != null else 0.0


func _clip_scale_swing(mob: CrawlerMob, clip: String) -> float:
	if mob == null or mob._animator == null or clip.is_empty():
		return 0.0
	if not mob._animator.has_animation(clip):
		return 0.0
	var animation := mob._animator.get_animation(clip)
	if animation == null:
		return 0.0
	var best := 0.0
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_SCALE_3D:
			continue
		var count := animation.track_get_key_count(track)
		if count < 2:
			continue
		var first: Vector3 = animation.track_get_key_value(track, 0)
		for key in count:
			var value: Vector3 = animation.track_get_key_value(track, key)
			best = maxf(best, first.distance_to(value))
	return best
