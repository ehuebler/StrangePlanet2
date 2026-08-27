extends Node

## Headless checks for fauna data, deterministic colony populations, procedural
## visuals, skeletal clip playback, grazing, bounding flight, provoked strafing,
## the spit projectile, contact damage, body-slap damage, and combat health.
##
##     godot --headless --path . dev/_fauna_test.tscn

const POPULATIONS := preload("res://game/fauna/fauna_populations.tscn")
const PORCUPINE := preload(
	"res://game/fauna/species/lumaquill_porcupine.tres")
const SLINKY := preload("res://game/fauna/species/prism_coil_slinky.tres")
const ALPACA := preload(
	"res://game/fauna/species/aurora_fleece_alpaca.tres")
const COLONY_DIRECTION := Vector3(-0.2881049, -0.1121179, 0.9510127)

var _failures := 0


class TestWorld extends GameWorld:
	func _ready() -> void:
		pass


class TestCycle extends CelestialCycle:
	func _ready() -> void:
		set_process(false)


class TestPlanet extends Planet:
	var test_viewer := Vector3.ZERO

	func _ready() -> void:
		if shape == null:
			shape = PlanetShape.new()
		shape.prepare()
		set_process(false)
		set_physics_process(false)

	func viewer_position() -> Vector3:
		return test_viewer

	func finest_spacing() -> float:
		return 1.5


class TestPlayer extends CharacterBody3D:
	var peer_id := 1
	var damage_taken := 0.0

	func _ready() -> void:
		add_to_group(&"network_players")
		add_to_group(DamageHit.COMBATANT_GROUP)

	func combat_faction() -> int:
		return DamageHit.Faction.PLAYER

	func combat_peer_id() -> int:
		return peer_id

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.4

	func is_dead() -> bool:
		return false

	func apply_damage(hit: DamageHit) -> float:
		var actual := maxf(hit.amount, 0.0)
		damage_taken += actual
		return actual


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var world := TestWorld.new()
	world.name = "TestWorld"
	var spawn_points := Node3D.new()
	spawn_points.name = "SpawnPoints"
	world.add_child(spawn_points)
	var cycle := TestCycle.new()
	cycle.name = "CelestialCycle"
	world.add_child(cycle)
	add_child(world)
	var planet := TestPlanet.new()
	planet.name = "Planet"
	planet.shape = PlanetShape.new()
	world.add_child(planet)
	await get_tree().process_frame

	var direction := COLONY_DIRECTION.normalized()
	var colony := Node3D.new()
	colony.name = "VacationersLanding"
	colony.position = planet.shape.surface_point(
		direction, planet.finest_spacing())
	planet.add_child(colony)
	planet.test_viewer = colony.position + direction * 4.0

	var spawner := POPULATIONS.instantiate() as FaunaSpawner
	planet.add_child(spawner)
	for _frame in 30:
		await get_tree().process_frame
		await get_tree().physics_frame

	_check_species_contracts()
	_expect(spawner != null, "population scene instantiates FaunaSpawner")
	if spawner != null:
		_check_population(spawner)
		await _check_combat(spawner, planet)
		await _check_alpaca(spawner, planet)

	world.queue_free()
	await get_tree().process_frame
	print("fauna_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_species_contracts() -> void:
	_expect(PORCUPINE.validate().is_empty(),
		"porcupine resource satisfies runtime asset contract")
	_expect(SLINKY.validate().is_empty(),
		"slinky resource satisfies runtime asset contract")
	_expect(PORCUPINE.disposition == FaunaSpecies.Disposition.PASSIVE
		and PORCUPINE.attack_style == FaunaSpecies.AttackStyle.CONTACT,
		"porcupine is passive with contact quills")
	_expect(PORCUPINE.has_move(FaunaSpecies.Move.WALK)
		and PORCUPINE.has_move(FaunaSpecies.Move.RUN)
		and PORCUPINE.has_move(FaunaSpecies.Move.ATTACK),
		"porcupine exposes walk, run, and contact attack moves")
	_expect(PORCUPINE.enabled and PORCUPINE.quadruped_gait
		and PORCUPINE.body_rock_degrees > 0.0,
		"porcupine population has procedural legs and body rock")
	_expect(not SLINKY.enabled,
		"slinky definition remains catalogued but is disabled")
	_expect(PORCUPINE.paint_texture != null and SLINKY.paint_texture != null
		and ALPACA.paint_texture != null,
		"every species samples an external runtime color-paint PNG")
	_expect(PORCUPINE.night_emission_energy > 0.0
		and SLINKY.night_emission_energy > 0.0
		and ALPACA.night_emission_energy > 0.0,
		"every species has authored night emission")
	_expect(ALPACA.validate().is_empty(),
		"alpaca resource satisfies runtime asset contract")
	_expect(ALPACA.disposition == FaunaSpecies.Disposition.FRIENDLY
		and ALPACA.attack_style == FaunaSpecies.AttackStyle.SPIT
		and ALPACA.provoked_seconds > 0.0,
		"alpaca is friendly and only spits once it has been provoked")
	_expect(ALPACA.skeletal_clips and not ALPACA.quadruped_gait,
		"alpaca is posed by its skeleton rather than by the shader gait")
	_expect(ALPACA.graze and ALPACA.bound_when_fleeing,
		"alpaca grazes while idle and bounds away when crowded")
	_expect(not ALPACA.global_population and ALPACA.colony_count > 0,
		"alpaca is a colony-site test population only")


func _check_population(spawner: FaunaSpawner) -> void:
	var expected_colony := 0
	var skeletal := 0
	for definition in spawner.species:
		if definition == null:
			continue
		_expect(definition.validate().is_empty(),
			"%s resource satisfies runtime asset contract" % definition.species_id)
		if definition.enabled:
			expected_colony += definition.colony_count
		if definition.skeletal_clips:
			skeletal += 1
			_expect(not definition.quadruped_gait
				and not definition.clip_attack.is_empty(),
				"%s is posed by clips and names an attack" % definition.species_id)
	_expect(skeletal >= 10,
		"rigged creature catalogue includes the ten new land fauna")
	_expect(spawner.colony_actor_count() == expected_colony,
		"every catalogued colony creature spawns near Vacationer's Landing")
	_expect(spawner.species_count("lumaquill_porcupine") >= 4,
		"porcupine colony population is live")
	_expect(spawner.species_count("aurora_fleece_alpaca")
		== ALPACA.colony_count,
		"alpaca herd is live at the colony site")
	_expect(spawner.species_count("prism_coil_slinky") == 0,
		"disabled slinky population creates no actors")
	print("fauna_test: colony spawn %.2f ms, %d terrain checks" % [
		float(spawner.last_colony_micros()) / 1000.0,
		spawner.last_colony_placement_checks(),
	])
	spawner.call(&"_survey_global")
	print("fauna_test: global survey %.2f ms, %d terrain checks" % [
		float(spawner.last_survey_micros()) / 1000.0,
		spawner.last_survey_placement_checks(),
	])
	_expect(spawner.last_survey_placement_checks() <= 400,
		"global survey terrain work stays bounded")
	_expect(spawner.light_pool_size() == 7,
		"night glow uses its bounded physical-light pool")
	_expect(spawner.fauna_snapshot().size() == spawner.actor_count(),
		"fauna snapshot covers every live host actor")
	for mob_variant: Variant in get_tree().get_nodes_in_group(&"fauna_mobs"):
		var mob := mob_variant as FaunaMob
		if mob == null or not spawner.is_ancestor_of(mob):
			continue
		_expect(mob.find_children(
			"*", "MeshInstance3D", true, false).size() == 1,
			"%s has one runtime mesh" % mob.mob_id)


func _check_combat(spawner: FaunaSpawner, planet: Planet) -> void:
	var porcupine := _first_mob(spawner, "lumaquill_porcupine")
	_expect(porcupine != null, "porcupine colony exposes live actors")
	if porcupine == null:
		return
	porcupine.set_physics_process(false)
	var motion_pivot := porcupine.get_node_or_null(
		"Visuals/MotionPivot") as Node3D
	var meshes := porcupine.find_children(
		"*", "MeshInstance3D", true, false)
	var mesh_instance := meshes[0] as MeshInstance3D \
		if not meshes.is_empty() else null
	var gait_material := mesh_instance.material_override as ShaderMaterial \
		if mesh_instance != null else null
	var starting_transform := porcupine.global_transform
	porcupine.set(&"_gait_phase", 0.0)
	porcupine.set(&"_gait_blend", 0.0)
	porcupine.set(&"_last_visual_position", porcupine.global_position)
	porcupine.call(&"_set_motion_state", FaunaMob.MotionState.WALK)
	porcupine.global_position += -porcupine.global_basis.z \
		* porcupine.instance_height() * PORCUPINE.gait_stride_share * 0.25
	porcupine.call(&"_animate_visual", 0.1)
	_expect(gait_material != null
		and bool(gait_material.get_shader_parameter(&"quadruped_gait"))
		and float(gait_material.get_shader_parameter(&"gait_amount")) > 0.5,
		"porcupine material animates its COLOR_0 leg mask")
	_expect(motion_pivot != null
		and absf(motion_pivot.rotation.x) > deg_to_rad(4.0),
		"porcupine rocks fore and aft while walking")
	porcupine.global_transform = starting_transform
	porcupine.call(&"_set_motion_state", FaunaMob.MotionState.IDLE)

	# A creature with no player near it must not be sweeping its capsule against
	# the world. Doing so costs tens of milliseconds per call against distant
	# terrain, which reads in play as the whole world freezing for a moment.
	porcupine.set(&"_player_gap", PORCUPINE.physics_within * 4.0)
	porcupine.call(&"_refresh_simulation_detail")
	_expect(not porcupine.is_physics_body(),
		"a creature far from every player walks the height field")
	porcupine.set(&"_player_gap", PORCUPINE.physics_within * 0.5)
	porcupine.call(&"_refresh_simulation_detail")
	_expect(porcupine.is_physics_body(),
		"a creature beside a player is a full physics body")

	var before := porcupine.health()
	var player_hit := DamageHit.impact(
		porcupine.combat_position(), 1.0, 20.0)
	player_hit.faction = DamageHit.Faction.PLAYER
	var delivered := porcupine.apply_damage(player_hit)
	_expect(delivered > 0.0 and porcupine.health() < before,
		"player-faction combat damage reduces fauna health")

	var player := TestPlayer.new()
	player.name = "1"
	planet.add_child(player)
	await get_tree().process_frame

	_expect(porcupine.begin_lasso(player) and porcupine.is_lassoed()
		and porcupine.lasso_mass() < 1.0,
		"Lasso captures fauna with species-scale swing mass")
	porcupine.lasso_simulate(
		Vector3.RIGHT * 0.25, Vector3(11.0, 4.0, 0.0))
	porcupine.end_lasso(Vector3(13.0, 4.0, 0.0))
	_expect(porcupine.can_be_lassoed() and not porcupine.is_lassoed()
		and porcupine.velocity.length() > 12.0,
		"Lasso throw restores fauna AI and keeps release velocity")

	player.global_position = porcupine.combat_position()
	porcupine.call(&"_try_contact_damage")
	_expect(player.damage_taken >= PORCUPINE.attack_damage,
		"touching passive porcupine applies quill damage")
	player.queue_free()


## The alpaca is the first creature whose presentation comes from a skeleton and
## whose temperament changes when it is hurt, so each of those is driven here by
## hand: the clip it would play, the leap it flees in, the ring it holds once
## provoked, and the ball it throws from that ring actually landing on somebody.
func _check_alpaca(spawner: FaunaSpawner, planet: Planet) -> void:
	var alpaca := _first_mob(spawner, "aurora_fleece_alpaca")
	_expect(alpaca != null, "alpaca herd exposes live actors")
	if alpaca == null:
		return
	alpaca.set_physics_process(false)
	var animator := alpaca.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	_expect(animator != null, "alpaca model carries baked animation clips")
	if animator != null:
		var missing := PackedStringArray()
		for clip in [ALPACA.clip_idle, ALPACA.clip_walk, ALPACA.clip_run,
				ALPACA.clip_graze, ALPACA.clip_bound, ALPACA.clip_strafe,
				ALPACA.clip_attack, ALPACA.clip_hit, ALPACA.clip_dead]:
			if not animator.has_animation(clip):
				missing.append(clip)
		_expect(missing.is_empty(),
			"alpaca GLB exports every clip the species asks for%s" % (
				"" if missing.is_empty()
				else " (missing %s)" % ", ".join(missing)))
		_expect(animator.get_animation(
			ALPACA.clip_walk).loop_mode == Animation.LOOP_LINEAR,
			"alpaca walk clip is bound as a looping gait")

	var meshes := alpaca.find_children("*", "MeshInstance3D", true, false)
	var mesh_instance := meshes[0] as MeshInstance3D \
		if not meshes.is_empty() else null
	var material := mesh_instance.material_override as ShaderMaterial \
		if mesh_instance != null else null
	_expect(material != null
		and not bool(material.get_shader_parameter(&"quadruped_gait")),
		"alpaca material leaves its vertices to the skeleton")

	# Grazing is rolled when a wander leg is chosen, so roll until it comes up
	# rather than reaching in and setting the timer the behaviour reads.
	for _attempt in 24:
		if float(alpaca.get(&"_graze_left")) > 0.0:
			break
		alpaca.call(&"_choose_wander_heading")
	_expect(float(alpaca.get(&"_graze_left")) > 0.0,
		"alpaca wander pauses turn into grazing")
	alpaca.call(&"_wander", 0.1)
	_expect(alpaca.motion_state() == FaunaMob.MotionState.GRAZE
		and alpaca.call(&"_clip_for_state") == ALPACA.clip_graze,
		"a grazing alpaca stands still with its head down")

	var player := TestPlayer.new()
	player.name = "1"
	planet.add_child(player)
	player.global_position = alpaca.combat_position() \
		- alpaca.global_basis.z * 3.0
	await get_tree().process_frame

	# Driven as a height-field walker so each step here is the same analytical
	# move every frame, rather than a capsule sweep outside the physics tick.
	alpaca.set(&"_player_gap", ALPACA.physics_within * 4.0)
	alpaca.call(&"_refresh_simulation_detail")
	alpaca.set(&"_think_left", 0.0)
	alpaca.call(&"_update_behaviour", 0.1)
	_expect(alpaca.motion_state() == FaunaMob.MotionState.FLEE
		and alpaca.call(&"_clip_for_state") == ALPACA.clip_bound,
		"a crowded alpaca bounds away instead of standing there")
	_expect(float(alpaca.get(&"_graze_left")) == 0.0,
		"fleeing interrupts a graze")

	var hit := DamageHit.impact(alpaca.combat_position(), 1.0, 5.0)
	hit.faction = DamageHit.Faction.PLAYER
	hit.set_source(player)
	alpaca.apply_damage(hit)
	_expect(float(alpaca.get(&"_provoked_left")) > 0.0,
		"hurting an alpaca provokes it")
	_expect(alpaca.call(&"_clip_for_state") == ALPACA.clip_hit,
		"a struck alpaca flinches")
	alpaca.set(&"_hit_show_left", 0.0)
	alpaca.set(&"_attack_cooldown_left", 0.0)
	var gap_before := alpaca.global_position.distance_to(
		player.global_position)
	for _step in 12:
		alpaca.set(&"_think_left", 0.0)
		alpaca.call(&"_update_behaviour", 0.1)
	_expect(alpaca.motion_state() == FaunaMob.MotionState.STRAFE,
		"a provoked alpaca circles whoever hurt it")
	var aim := -alpaca.global_basis.z.dot(
		(player.global_position - alpaca.global_position).normalized())
	_expect(aim > 0.5,
		"a strafing alpaca keeps its aim on its target (%.2f)" % aim)
	_expect(float(alpaca.get(&"_spit_windup_left")) > 0.0
		and alpaca.call(&"_clip_for_state") == ALPACA.clip_attack,
		"circling at close range starts a spit")
	var gap_after := alpaca.global_position.distance_to(player.global_position)
	_expect(gap_after > gap_before - 0.5
		and gap_after < ALPACA.strafe_radius + 2.0,
		"strafing opens out to its ring rather than charging or bolting")

	# The ball is thrown by hand at a target standing in its path, which is the
	# only way to prove the throw carries damage rather than merely existing.
	player.global_position = alpaca.combat_position() \
		- alpaca.global_basis.z * 4.0
	alpaca.call(&"_launch_spit")
	var balls := planet.find_children("*", "FaunaSpit", false, false)
	_expect(balls.size() == 1, "a spit puts exactly one ball in the air")
	if not balls.is_empty():
		var ball := balls[0] as Node3D
		# Flown on real physics frames rather than by calling its step by hand:
		# the ball queries the physics server, and those queries are only safe
		# from inside the tick that owns them.
		for _step in 40:
			if not is_instance_valid(ball) or player.damage_taken > 0.0:
				break
			await get_tree().physics_frame
		_expect(player.damage_taken >= ALPACA.attack_damage,
			"the spit ball damages the player it was thrown at")
		if is_instance_valid(ball):
			ball.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _first_mob(spawner: FaunaSpawner, species_id: String) -> FaunaMob:
	for child_variant: Variant in spawner.get_children():
		var mob := child_variant as FaunaMob
		if mob != null and mob.species != null \
				and mob.species.species_id == species_id:
			return mob
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("fauna_test: PASS  ", message)
		return
	_failures += 1
	push_error("fauna_test: FAIL  %s" % message)
