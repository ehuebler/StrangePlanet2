extends Node

const WORLD := preload("res://game/world.tscn")
const SHOT_DIR := "res://dev/captures/"

# OnlinePlayer.Stance, which is private to the player and read here by index.
const STAND := 0
const SLIDE := 2
const FLY := 3
const CRASH := 4
const SWIM := 5
const HERO := 6

## Clear of the wardrobe, which stands on the landing site's origin, and facing
## back out of the site so a wind-up has open ground in front of it.
const RUN_START := Vector3(0.0, 0.4, 8.0)
const RUN_YAW := PI
## Off the site's centre for the same reason, for anything that only needs the
## character standing somewhere with room around it.
const CLEAR := Vector3(7.0, 0.4, 7.0)

## Grid the shimmer check differences frames on, and the change that counts as a
## pixel having flickered rather than having merely shaded.
const SHIMMER_WIDTH := 320
const SHIMMER_HEIGHT := 200
const SHIMMER_LOUD := 24
## Metres of ground covered between two frames in the walking pass. A sixth of
## a metre at sixty frames is the new walking speed, which is the pace the
## flicker was reported at.
const SHIMMER_STEP := 0.15
## And a pace slow enough that the view barely changes, which is what separates
## a ground that is sampled badly from one that is merely detailed.
const SHIMMER_CREEP := 0.002

class ImpactStub:
	extends Node
	var calls := 0

	func resolve_flora_impact(_collider: CollisionShape3D,
			_impact_speed: float, _at: Vector3) -> Dictionary:
		calls += 1
		return {
			"handled": true,
			"broken": true,
			"momentum_keep": 0.75,
			"bounce_up": 0.0,
		}


var _player: OnlinePlayer
var _planet: Planet
## The landing site's frame, which every offset in this file is measured in. The
## world's origin is the planet's centre, 8 km underground, so a bare world
## coordinate puts the player in the core. Only good near the site: its up is a
## single direction, and the ground curves away from it by 16 m over 500 m.
var _ground := Transform3D.IDENTITY
var _glow_reported := false
var _grass_spot := Vector3.UP
var _shadow_atlas := 4096
var _covers_named := false
## Furthest the eye moved between two frames of the last shimmer pass, over and
## above the step that pass asked for. Set by `_shimmer_pass` and read out
## beside its result.
var _eye_creep := 0.0
## Each plant material's shipped uniforms, remembered the first time it is seen
## so a row that changed one can put it back.
var _plant_shipped := {}
## Wiring checks failed by `--graphics-toggles`. Only that mode makes claims a
## harness can be wrong about rather than measurements to be read.
var _toggle_failures := 0


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	# The world opens the home screen and spawns nobody while the session reads as
	# idle, so the state has to say "in game" before it comes up.
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	var world := WORLD.instantiate()
	if "--before" in OS.get_cmdline_user_args():
		_restore_thin_lawn()
	add_child(world)
	await _wait(10)
	_player = get_tree().get_first_node_in_group("network_players") as OnlinePlayer
	var site := world.find_child("LandingSite", true, false) as Node3D
	_planet = world.find_child("Planet", true, false) as Planet
	if _player == null or site == null or _planet == null:
		push_error("player_test: player=%s site=%s planet=%s" % [_player, site, _planet])
		get_tree().quit(1)
		return
	_ground = site.global_transform
	# The terrain builds on worker threads around whatever is looking at it, and
	# a player dropped onto a chunk that has no collider yet falls through the
	# planet. Everything here waits for the ground to exist first.
	await _wait(120)
	await _run()
	get_tree().quit()


func _run() -> void:
	var only: PackedStringArray = OS.get_cmdline_user_args()
	if "--sheet" in only:
		await _clip_report()
		await _clip_sheet()
		return
	if "--collision" in only:
		await _prop_checks()
		await _step_checks()
		return
	if "--tech-collision" in only:
		await _tech_collision_checks()
		return
	if "--rings" in only:
		await _ring_site_checks()
		return
	if "--flight" in only:
		await _flight_checks()
		await _flight_shots()
		return
	if "--run" in only:
		await _run_checks()
		return
	if "--movement" in only:
		await _movement_checks()
		return
	if "--gaits" in only:
		await _gait_checks()
		return
	if "--dust" in only:
		await _dust_checks()
		return
	if "--stall" in only:
		await _stall_survey()
		return
	if "--reported-stall" in only:
		await _reported_stall()
		return
	if "--cling" in only:
		await _cling_checks()
		return
	if "--cover-shadows" in only:
		await _cover_shadow_report()
		return
	if "--churn" in only:
		await _churn_report()
		return
	if "--flora-cost" in only:
		await _flora_cost_report()
		return
	if "--warmup" in only:
		await _warmup_report()
		return
	if "--regrow" in only:
		await _regrow_report()
		return
	if "--spot" in only:
		await _spot_report()
		return
	if "--daylight" in only:
		await _daylight_report()
		return
	if "--facets" in only:
		await _facet_report()
		return
	if "--splat" in only:
		await _splat_report()
		return
	if "--tiling" in only:
		await _tiling_report()
		return
	if "--reef" in only:
		await _reef_glow_checks()
		return
	if "--geology" in only:
		await _geology_checks()
		return
	if "--biomes" in only:
		await _biome_population_checks()
		return
	if "--impacts" in only:
		await _flora_impact_checks()
		return
	if "--night-phenomena" in only:
		await _night_phenomena_checks()
		return
	if "--volcano" in only:
		await _volcano_checks()
		return
	if "--waypoints" in only:
		await _waypoint_toggle_checks()
		return
	if "--flora-range" in only:
		await _flora_range_checks()
		return
	if "--lawn" in only:
		await _lawn_report()
		return
	if "--arrival" in only:
		await _arrival_report()
		return
	if "--boot" in only:
		await _boot_report()
		return
	if "--boot-shadow" in only:
		await _boot_shadow_report()
		return
	if "--speed" in only:
		await _speed_report()
		return
	if "--graphics-toggles" in only:
		await _graphics_toggle_checks()
		return
	if "--orbit-glow" in only:
		await _orbit_glow_checks()
		return
	if "--night-lights" in only:
		await _night_light_checks()
		return
	if "--night-cast" in only:
		await _night_cast_checks()
		return
	if "--idle" in only:
		await _idle_creep_checks()
		return
	if "--shimmer" in only:
		var place := "grass"
		if "--colony" in only:
			place = "colony"
		elif "--shadow" in only:
			place = "shadow"
		elif "--ground" in only:
			place = "ground"
		elif "--blades" in only:
			place = "blades"
		elif "--calm" in only:
			place = "calm"
		elif "--reach" in only:
			place = "reach"
		elif "--aa" in only:
			place = "aa"
		elif "--sway" in only:
			place = "sway"
		elif "--far" in only:
			place = "far"
		elif "--dunes" in only:
			place = "dunes"
		elif "--lawn" in only:
			place = "lawn"
		await _shimmer_checks(place)
		return
	await _movement_checks()
	await _run_checks()
	await _cling_checks()
	await _flight_checks()
	await _flight_shots()
	# Props first: the kerb course is scenery the prop checks should not meet.
	await _prop_checks()
	await _step_checks()
	await _camera_shots()
	await _clip_report()
	await _clip_sheet()


## The two grounded gait boundaries, without waiting through a thirty-second
## wind-up to happen to land on either side of them.
func _gait_checks() -> void:
	await _place(CLEAR, 0.0)
	await _wait(20)
	for sample: Array in [
		[_player.sprint_speed, "Walk"],
		[_player.arms_back_speed, "Walk"],
		[_player.arms_back_speed + 0.1, "Run"],
	]:
		var speed: float = sample[0]
		var expected: String = sample[1]
		_player.velocity = -_player.global_basis.z * speed
		_player._update_animation(1.0 / 60.0)
		print("player_test: gait at %4.1f m/s  %s" % [speed, _player._clip])
		if _player._clip != expected:
			push_error("player_test: gait at %.1f m/s was %s, expected %s" % [
				speed, _player._clip, expected])


## Foot trails, movement rings, and the weapon clouds that share their pool.
##
## Particle counts and ring settings are checked directly because the dummy
## renderer cannot draw them. A graphical run records the sprint, landing,
## Meteor and laser sizes against the real character.
func _dust_checks() -> void:
	await _place(CLEAR, 0.0)
	_player.controls_enabled = false
	var dust := _player.dust
	if dust == null:
		push_error("player_test: player has no PlayerDust")
		return
	var trails := dust.trail_emitters()
	var bursts := dust.burst_emitters()
	print("player_test: dust  trails=%d burst pool=%d" % [
		trails.size(), bursts.size()])
	if trails.size() != 2:
		push_error("player_test: dust needs one trail for each foot")
	if bursts.size() < 3:
		push_error("player_test: dust burst pool is too small for chained landings")
	if not bursts.is_empty():
		var process := bursts[0].process_material as ParticleProcessMaterial
		if process == null or process.emission_shape \
				!= ParticleProcessMaterial.EMISSION_SHAPE_RING:
			push_error("player_test: ground dust is not emitted as a circular ring")

	var forward := -_player.global_basis.z
	_player.velocity = forward * _player.sprint_speed
	_player._footed = true
	dust.update_trails(_player.character, _player._up(), forward,
		_player.sprint_speed, true)
	await _drawn(2)
	var running := 0
	for trail in trails:
		if trail.emitting:
			running += 1
	if running != 2:
		push_error("player_test: sprint did not start both foot trails")
	if trails.size() == 2:
		var skeleton := Wardrobe.skeleton_of(_player.character)
		if skeleton == null:
			push_error("player_test: dust check could not find the character skeleton")
		else:
			for index in 2:
				var foot := CharacterRig.find_bone(skeleton, PlayerDust.FOOT_BONES[index])
				if foot < 0:
					push_error("player_test: dust check could not find foot %d" % index)
					continue
				var ankle := skeleton.global_transform \
					* skeleton.get_bone_global_pose(foot).origin
				var from_ankle := trails[index].global_position - ankle
				var sideways := absf(from_ankle.dot(_player.global_basis.x))
				var below := -from_ankle.dot(_player._up())
				print("player_test: dust  sole %d lateral=%.3f below ankle=%.3f" % [
					index, sideways, below])
				if sideways > 0.015:
					push_error(
						"player_test: foot trail is offset toward the foot's side")
				if absf(below - PlayerDust.FOOT_SOLE_DROP) > 0.015:
					push_error("player_test: foot trail is not under the sole")

	dust.update_trails(_player.character, _player._up(), Vector3.ZERO,
		_player.walk_speed, false)
	for trail in trails:
		if trail.emitting:
			push_error("player_test: foot trail remained on below a sprint")

	# Take-off: move clear of the stale floor contact, then let the same
	# airborne transition used by remote peers observe the jump.
	var before := dust.burst_count
	_player.global_position += _player._up() * 1.5
	_player.velocity = _player._up() * _player.jump_velocity
	_player._footed = false
	_player.move_and_slide()
	_player._was_airborne = false
	_player._apply_stance(STAND)
	_player._update_animation(1.0 / 60.0)
	if dust.burst_count != before + 1:
		push_error("player_test: jump take-off made no ground dust pop")

	# A long ordinary arc gets one on the way down as well.
	before = dust.burst_count
	_player._was_airborne = true
	_player._airborne_time = OnlinePlayer.AIR_RUN_DELAY + 0.1
	_player._landing_speed = _player.jump_velocity
	_player._footed = true
	_player.velocity = Vector3.ZERO
	_player._update_animation(1.0 / 60.0)
	if dust.burst_count != before + 1:
		push_error("player_test: big jump landing made no ground dust pop")

	# Entering Hero owns the large pop. Receiving another sync packet with the
	# same replicated stance must not restart it.
	_player._apply_stance(STAND)
	before = dust.burst_count
	_player._apply_stance(HERO)
	_player._apply_stance(HERO)
	if dust.burst_count != before + 1:
		push_error("player_test: Hero pose did not make exactly one dust pop")
	print("player_test: dust  jump, big landing and Hero pops=%d" % [
		dust.burst_count])

	# A remote body has no move_and_slide floor flag. Zero vertical speed at a
	# jump's apex must still be airborne, or it appears to land and take off a
	# second time — which would duplicate both rings.
	var ground_point := _player._dust_ground_point()
	var local_peer := _player.peer_id
	_player.peer_id = 2
	_player.global_position = ground_point + _player._up() * 4.0
	_player.velocity = Vector3.ZERO
	_player._was_airborne = true
	_player._airborne_time = OnlinePlayer.AIR_RUN_DELAY + 0.1
	before = dust.burst_count
	if _player._grounded_for_display():
		push_error("player_test: remote jump apex was mistaken for ground")
	_player._update_animation(1.0 / 60.0)
	if dust.burst_count != before:
		push_error("player_test: remote jump apex made a false dust ring")
	_player.peer_id = local_peer

	# Meteor fills its full crater footprint. The laser ability is rate-limited
	# when held still, may puff immediately when swept to a new point, and the
	# carbine's one-off bolt is never swallowed by that limiter.
	_player.global_position = ground_point
	_player._footed = true
	var impact_at := _planet.standing_position(
		_planet.to_local(ground_point + forward * 2.0))
	var impact_up := _planet.up_at(impact_at)
	before = dust.impact_count
	_player.play_meteor_impact_dust(impact_at, impact_up, 6.0, 1.0)
	if dust.impact_count != before + 1:
		push_error("player_test: Meteor impact made no broad dust cloud")
	var widest := 0.0
	for burst in bursts:
		var process := burst.process_material as ParticleProcessMaterial
		if process != null:
			widest = maxf(widest, process.emission_ring_radius)
	if widest < 5.9:
		push_error("player_test: Meteor dust did not cover its crater radius")

	var eyes := _player.eye_points()
	var laser_before := dust.laser_impact_count
	before = dust.impact_count
	LaserEyes.apply_effect(
		_player, "laser_eyes", eyes[0], eyes[1], impact_at, true)
	LaserEyes.apply_effect(
		_player, "laser_eyes", eyes[0], eyes[1], impact_at, true)
	if dust.laser_impact_count != laser_before + 1 \
			or dust.impact_count != before + 1:
		push_error("player_test: held laser dust was missing or not rate-limited")
	var swept_at := _planet.standing_position(
		_planet.to_local(impact_at + forward * 1.0))
	LaserEyes.apply_effect(
		_player, "laser_eyes", eyes[0], eyes[1], swept_at, true)
	if dust.laser_impact_count != laser_before + 2:
		push_error("player_test: swept laser impact made no new dust puff")

	var bolt := LaserBolt.fire(
		_player.get_parent(), swept_at + impact_up, impact_up, _player)
	laser_before = dust.laser_impact_count
	before = dust.impact_count
	if bolt != null:
		bolt.global_position = swept_at
		bolt._land(impact_up)
		bolt.queue_free()
	if bolt == null or dust.laser_impact_count != laser_before + 1 \
			or dust.impact_count != before + 1:
		push_error("player_test: laser carbine impact made no dust puff")
	print("player_test: dust  Meteor clouds=%d laser clouds=%d" % [
		dust.impact_count, dust.laser_impact_count])

	if DisplayServer.get_name() != "headless":
		await _wait(140)

	# One readable frame: a third-person body with white puffs outside both
	# feet and a complete circular burst against the ground.
	_player._apply_stance(STAND)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_NEAR)
	_player.controls_enabled = true
	await _place(CLEAR, 0.0)
	_player.hud.visible = false
	_look(-0.34)
	var trail_starts := dust.trail_start_count
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(24)
	running = 0
	for trail in trails:
		if trail.emitting:
			running += 1
	if running != 2:
		push_error("player_test: real sprint did not keep both foot trails on")
	print("player_test: dust  real sprint emitter starts=%d" % [
		dust.trail_start_count - trail_starts])
	var shot_camera := Camera3D.new()
	shot_camera.fov = 58.0
	add_child(shot_camera)
	var up := _player._up()
	var right := _player.global_basis.x
	shot_camera.global_position = _player.global_position \
		+ right * 5.5 - forward * 2.2 + up * 2.3
	shot_camera.look_at(
		_player.global_position - forward * 1.6 + up * 0.45, up)
	shot_camera.current = true
	await _shot("player_dust_trail")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	_player.controls_enabled = false
	_player.velocity = Vector3.ZERO
	dust.update_trails(_player.character, _player._up(), Vector3.ZERO,
		0.0, false)
	dust.pop_ground(_player._dust_ground_point(), _player._up(), 2.0)
	await _drawn(8)
	await _shot("player_dust_pop")
	dust.update_trails(_player.character, _player._up(), Vector3.ZERO,
		0.0, false)
	if DisplayServer.get_name() != "headless":
		await _wait(75)
		var visual_at := _player._dust_ground_point()
		dust.impact_cloud(visual_at, _player._up(), 6.0, 1.0)
		await _wait(18)
		await _shot("player_meteor_dust")
		await _wait(100)
		var laser_at := _planet.standing_position(
			_planet.to_local(visual_at + forward * 2.4))
		var laser_up := _planet.up_at(laser_at)
		var visual_eyes := _player.eye_points()
		_player.laser_beams().aim(
			visual_eyes[0], visual_eyes[1], laser_at)
		dust.laser_impact(laser_at, laser_up, 0.6, 0.55, true)
		shot_camera.look_at(
			_player.global_position + forward * 0.8 + up * 0.45, up)
		await _wait(6)
		await _shot("player_laser_dust")
		_player.laser_beams().stop()
	print("player_test: dust  PASS")


## Reports the shadow mode the renderer receives for every streamed cover tile.
##
## Species resources only express intent. The thing that matters is the live
## MultiMeshInstance3D after GroundCover has streamed and dressed it, especially
## because GeometryInstance3D defaults to casting until that dressing runs.
func _cover_shadow_report() -> void:
	var world := _planet.get_parent()
	var ship := world.find_child("VacationersLanding", true, false) as SurfaceAnchor
	if ship != null:
		_stand_on(ship.direction)
	await _wait(400)
	var totals := {}
	for stand in _multimeshes(world):
		var host := stand.get_parent()
		var key := String(host.name) if host != null else "<orphan>"
		# x/y are all off/casting nodes; z/w are the same split restricted to
		# nodes that are actually visible and submit at least one instance.
		# A hidden tile retains GeometryInstance3D's default shadow mode until
		# it is needed, but it cannot put anything in the shadow map.
		var counts: Vector4i = totals.get(key, Vector4i.ZERO)
		var drawn := stand.visible and stand.multimesh != null \
			and stand.multimesh.visible_instance_count != 0
		if stand.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			counts.x += 1
			if drawn:
				counts.z += 1
		else:
			counts.y += 1
			if drawn:
				counts.w += 1
		totals[key] = counts
	var names := PackedStringArray(totals.keys())
	names.sort()
	for key in names:
		var counts: Vector4i = totals[key]
		print("player_test: cover shadows %-22s all(off=%d casting=%d) drawn(off=%d casting=%d)" % [
			key, counts.x, counts.y, counts.z, counts.w])


## Exercises the night flora's two distinct jobs: emission on every instance and
## a bounded number of real lights near the viewer. It also checks that those
## lights change independently at night and return to zero at local noon.
func _night_light_checks() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var flowers := world.find_child("LandingFlowers", true, false) as GroundCover
	var trees := world.find_child("LandingFlowerTrees", true, false) as FlowerTreeField
	var grass := world.find_child("GlobalGrass", true, false) as GroundCover
	var terrain_glow := world.find_child(
		"NightGroundGlow", true, false) as NightGroundGlow
	if cycle == null or flowers == null or trees == null or grass == null \
			or terrain_glow == null:
		push_error("player_test: night flora nodes are incomplete")
		return
	if flowers.glow_light_range < 30.0 or flowers.glow_light_energy < 7.0 \
			or trees.night_light_range < 45.0 \
			or trees.night_light_energy < 8.0 \
			or grass.glow_light_range < 26.0 \
			or grass.glow_light_energy < 3.8 \
			or grass.glow_light_height < 1.0:
		push_error("player_test: flora cast-light pools are not broad and strong")
		return

	var tree_transforms: Array = trees.get("_trees")
	if tree_transforms.is_empty():
		push_error("player_test: flower-tree field grew no trees")
		return
	var nearest := 0
	var nearest_distance := INF
	for index in tree_transforms.size():
		var stood: Transform3D = tree_transforms[index]
		if stood.origin.length_squared() < nearest_distance:
			nearest = index
			nearest_distance = stood.origin.length_squared()
	var nearest_tree: Transform3D = tree_transforms[nearest]
	var root := trees.to_global(nearest_tree.origin)
	var direction := _planet.to_local(root).normalized()
	var tangent := direction.cross(Vector3.UP if absf(direction.y) < 0.9
		else Vector3.RIGHT).normalized()
	# Near enough to receive its light, clear of the trunk collider.
	direction = (direction + tangent * 6.0 / _planet.shape.radius).normalized()
	_stand_on(direction)

	cycle.period_seconds = 0.0
	cycle.set_phase(0.5)
	await _wait(360)
	var flower_lights := _omni_lights(flowers)
	var tree_lights := _omni_lights(trees)
	var grass_lights := _omni_lights(grass)
	var flower_lit := _lit_lights(flower_lights)
	var tree_lit := _lit_lights(tree_lights)
	var grass_lit := _lit_lights(grass_lights)
	print("player_test: night lights flowers=%d/%d trees=%d/%d grass=%d/%d "
			% [flower_lit, flower_lights.size(), tree_lit, tree_lights.size(),
				grass_lit, grass_lights.size()]
		+ "energy=(%.2f, %.2f, %.2f)" % [
			_light_energy(flower_lights), _light_energy(tree_lights),
			_light_energy(grass_lights)])
	if flower_lights.size() != flowers.glow_light_limit or flower_lit == 0:
		push_error("player_test: colony flower light pool did not illuminate at night")
	if tree_lights.size() != trees.night_light_limit or tree_lit == 0:
		push_error("player_test: flower-tree light pool did not illuminate at night")
	if grass_lights.size() != grass.glow_light_limit or grass_lit == 0:
		push_error("player_test: glowing grass did not illuminate its terrain")
	await _shot("night_flora_cast_light")

	var lights: Array[OmniLight3D] = []
	lights.append_array(flower_lights)
	lights.append_array(tree_lights)
	var before := PackedFloat32Array()
	for light in lights:
		before.append(light.light_energy)
	await _wait(60)
	var changed := 0
	for index in lights.size():
		if absf(lights[index].light_energy - before[index]) > 0.01:
			changed += 1
	print("player_test: night pulse changed %d/%d pooled lights independently"
		% [changed, lights.size()])
	if changed < 2:
		push_error("player_test: night flora lights did not pulse independently")

	cycle.set_phase(0.0)
	await _wait(90)
	var daylight_energy := _light_energy(lights)
	print("player_test: daylight flora light energy %.3f" % daylight_energy)
	if daylight_energy > 0.05:
		push_error("player_test: night flora lights remained on in daylight")

	# A plain lawn frame rather than the mixed flower/tree field above. This is
	# the view that catches the failure mode where emissive blades are bright
	# dots over black terrain even though the light pool exists.
	cycle.set_phase(0.5)
	_stand_on(direction)
	flowers.visible = false
	trees.visible = false
	_player._camera_mode = 0
	_player._pitch = -0.32
	if _player.character != null:
		_player.character.visible = false
	if _player.hud != null:
		_player.hud.visible = false
	await _wait(240)
	if _lit_lights(grass_lights) == 0:
		push_error("player_test: grass lights went dark over the plain lawn")
	await _shot("grass_glow_ground")
	_player._camera_mode = 2
	_player._pitch = -0.62
	await _wait(30)
	await _shot("grass_glow_distance")
	grass.visible = false
	var distant_grass := world.find_child(
		"GlobalDistantGrass", true, false) as GroundCover
	if distant_grass != null:
		distant_grass.visible = false
	await _wait(30)
	await _shot("terrain_night_lava_glow")
	var radial := (
		_player.global_position - _planet.global_position).normalized()
	_player.controls_enabled = false
	_player.set_physics_process(false)
	_player.global_position += radial * 300.0
	_player._camera_mode = 0
	_player._pitch = -1.35
	await _wait(300)
	await _shot("terrain_night_lava_glow_aerial")
	var glow_frame := await _frame_sample()
	var terrain := Planet.SURFACE_MATERIAL
	var shipped_ground_glow: float = terrain.get_shader_parameter(
		&"night_ground_glow_energy")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var glow_cost := await _frame_cost(120)
	terrain.set_shader_parameter(&"night_ground_glow_energy", 0.0)
	await _wait(2)
	await _shot("terrain_night_lava_glow_aerial_off")
	var dark_cost := await _frame_cost(120)
	var dark_frame := await _frame_sample()
	var glow_delta := _frame_difference(glow_frame, dark_frame)
	print("player_test: night ground glow mean=%.3f peak=%d pixels=%d" % [
		glow_delta.x, int(glow_delta.y), int(glow_delta.z)])
	if glow_delta.x < 0.2 or glow_delta.y < 4.0:
		push_error("player_test: night terrain glow is not visibly above black")
	print("player_test: night ground glow cost %.2f on, %.2f off, %.2f ms/frame"
		% [glow_cost["frame"], dark_cost["frame"],
			float(glow_cost["frame"]) - float(dark_cost["frame"])])
	terrain.set_shader_parameter(
		&"night_ground_glow_energy", shipped_ground_glow)

	# A new planetary night changes all three authored hues, and a real light
	# sampled from the brightest nearby lobe must reach the character rather than
	# remaining a green emission visible only on the terrain.
	terrain_glow.palette_transition_seconds = 0.0
	for other_light in _omni_lights(world):
		if other_light.get_parent() != terrain_glow:
			# Fields keep rewriting visibility and energy. A zero cull mask is
			# the stable harness-only way to isolate the new terrain bounce.
			other_light.light_cull_mask = 0
	cycle.set_day_index(cycle.day_index() + 1)
	cycle.set_phase(0.5)
	await _wait(3)
	var lit_direction := terrain_glow.brightest_direction_near(
		direction, 520.0, 65.0, true)
	_player.set_physics_process(true)
	_stand_on(lit_direction)
	_player._camera_mode = 2
	_player._pitch = -0.28
	if _player.character != null:
		_player.character.visible = true
	await _wait(240)
	var terrain_lights := terrain_glow.active_lights()
	var terrain_lit := _lit_lights(terrain_lights)
	var non_green := false
	var full_cull_mask := true
	for light in terrain_lights:
		non_green = non_green or light.light_color.r > light.light_color.g \
			or light.light_color.b > light.light_color.g
		full_cull_mask = full_cull_mask and light.light_cull_mask == 0xFFFFD
	print("player_test: night ground cast %d/%d energy=%.2f non_green=%s" % [
		terrain_lit, terrain_lights.size(), _light_energy(terrain_lights),
		non_green])
	if terrain_lit == 0 or not non_green or not full_cull_mask:
		push_error("player_test: multicolour terrain glow did not cast on objects")
	await _shot("terrain_glow_cast_character")
	var cast_frame := await _frame_sample()
	var shipped_cast_energy := terrain_glow.light_energy
	terrain_glow.light_energy = 0.0
	await _wait(120)
	await _shot("terrain_glow_cast_character_off")
	var uncast_frame := await _frame_sample()
	var cast_delta := _frame_difference(cast_frame, uncast_frame)
	print("player_test: terrain cast visible mean=%.3f peak=%d pixels=%d" % [
		cast_delta.x, int(cast_delta.y), int(cast_delta.z)])
	if cast_delta.x < 0.5 or cast_delta.y < 8.0:
		push_error("player_test: terrain lights did not visibly reach nearby meshes")
	terrain_glow.light_energy = shipped_cast_energy


## Whether the night-flowering fields can be seen from above them.
##
## The blooms emit in their own shader and are streamed cover, so climbing away
## from the colony deletes the very thing being looked for. The terrain draws a
## stand-in once they are gone, and the only honest way to check a stand-in is
## the same frame with and without it: the smudge has to be there from orbit,
## and it has to be absent from the ground, where the real flowers are doing the
## job and a second copy underneath them would be double counting.
## Both atmosphere effects in one session: the depth-marched god rays and the
## wavelength scattering, switched through the player's own settings.
##
## One mode rather than two because the expensive part is standing a world up, and
## the two are checked the same way — take a frame, flip the setting, take the
## frame again, difference them. Sharing the session is what keeps the whole
## feature inside a single launch.
##
## What each group of rows is for:
##
## - The wiring rows prove the compositor reached the scene and asked for the
##   right callback stage and a resolved depth buffer. All three fail *silently*:
##   the pass never runs, or runs at a stage where the sky has not been drawn yet,
##   and the result looks like the effect merely being subtle.
## - `open` is the sun in clear sky. `blocked` stands a slab between the eye and
##   the sun, and it is the only row that proves the march reads depth at all —
##   rays that ignored it would be indistinguishable from a radial glow drawn
##   around the disc.
## - `behind` turns around. Nothing should change, because the effect skips both
##   passes once the sun is off screen; a difference here is cost being paid for a
##   frame with no shafts in it.
## - The scattering rows are one frame at `air_chroma` one and zero, which is
##   exactly what the setting does. Off has to match what the game looked like
##   before any of this existed.
## - The timing pair is the performance claim, measured rather than argued.
func _graphics_toggle_checks() -> void:
	# Both figures at the end of this are frame times, and a vsynced frame time is
	# the refresh rate whatever the pass costs: the first run of this reported the
	# two effects as costing exactly 0.00 ms because on and off were both 6.95,
	# which is 144 Hz to the microsecond.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var host := world.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if cycle == null or host == null or sun == null:
		push_error("player_test: graphics toggles need the cycle, environment and sun")
		return

	var compositor := host.compositor
	_expect(compositor != null, "the world environment carries a compositor")
	var rays: GodRaysEffect = null
	if compositor != null:
		for effect: CompositorEffect in compositor.compositor_effects:
			if effect is GodRaysEffect:
				rays = effect
	_expect(rays != null, "the compositor carries the god rays effect")
	if rays == null:
		_toggle_summary()
		return
	_expect(rays.effect_callback_type
		== CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT,
		"the effect runs after transparent, where the sky already exists")
	_expect(rays.access_resolved_depth,
		"the effect asks for a resolved depth buffer")

	# Live write-through, both ways. The setting is left in memory rather than
	# saved: this harness must not edit the player's own settings.cfg.
	SettingsManager.set_setting(&"graphics", &"god_rays", false)
	await _wait(2)
	_expect(not rays.enabled, "switching the setting off disables the effect")
	SettingsManager.set_setting(&"graphics", &"god_rays", true)
	await _wait(2)
	_expect(rays.enabled, "switching it back on re-enables the effect")

	# A stopped sun, low over the landing site. Low because shafts are a low-sun
	# sight, and stopped because a sun that moves between two frames would put
	# its own change into every difference measured below.
	cycle.period_seconds = 0.0
	var site_up := (_ground.origin - _planet.global_position).normalized()
	cycle.set_phase(_phase_for_elevation(cycle, sun, site_up, 0.22))
	var to_sun := sun.global_basis.z.normalized()
	print("player_test: rays  sun %.2f above the site's horizon, light (%.2f, %.2f, %.2f)" % [
		site_up.dot(to_sun), -to_sun.x, -to_sun.y, -to_sun.z])

	if _player.hud != null:
		_player.hud.visible = false
	_still_planet(world)
	# High enough that the ground the player is standing on is not in the way of
	# the sun, and that nothing near the site walks through the frame.
	var eye := _planet.global_position + site_up * (_planet.shape.radius + 300.0)
	var review := Camera3D.new()
	add_child(review)
	review.fov = 70.0
	review.near = 0.25
	review.far = _planet.shape.radius * 8.0
	review.global_position = eye
	review.look_at(eye + to_sun, site_up)
	review.current = true
	await _wait(180)

	await _ray_case("open", review, to_sun)

	# Bars across the sun, rather than one slab. Depth is the whole mechanism, so
	# the shafts have to break around something standing in front of the sun, and
	# terrain cannot be relied on to be in the right place on a procedural planet.
	#
	# Bars with gaps between them and not a single block, because a block only
	# shows that the effect can be dimmed. What is being checked is that the light
	# comes through the gaps and not through the bars — a wash passes the first
	# test and fails this one.
	var opaque := StandardMaterial3D.new()
	opaque.albedo_color = Color(0.02, 0.02, 0.03)
	var bars: Array[Node3D] = []
	for slot in 5:
		var bar := MeshInstance3D.new()
		var block := BoxMesh.new()
		# Tall enough to cross the whole frame at this distance, and spaced two
		# widths apart so two thirds of the sun's light still gets past.
		block.size = Vector3(1.4, 40.0, 0.6)
		bar.mesh = block
		bar.material_override = opaque
		add_child(bar)
		bars.append(bar)
		var side := to_sun.cross(site_up).normalized()
		bar.global_position = eye + to_sun * 14.0 \
			+ side * (float(slot) - 2.0) * 4.2
		bar.look_at(bar.global_position + to_sun, site_up)
	await _wait(20)
	await _ray_case("barred", review, to_sun)
	for bar: Node3D in bars:
		bar.queue_free()

	# Away from the sun, where the effect should be doing nothing whatsoever.
	review.look_at(eye - to_sun, site_up)
	await _wait(60)
	await _ray_case("behind", review, to_sun)

	# The scattering, from the same viewpoint turned a quarter turn off the sun.
	# Not at it: the sun's own halo blows the top of the frame to white, and the
	# first run of this duly reported the sky as 0.92 grey at a saturation of 0.01
	# with and without the model — a measurement of the sun, not of the air. Across
	# the sun is where the sunset band and the blue left over both sit in frame.
	var across := to_sun.cross(site_up).normalized()
	review.look_at(eye + across, site_up)
	await _wait(60)
	for lit: bool in [true, false]:
		SettingsManager.set_setting(&"graphics", &"atmospheric_scattering", lit)
		# Long enough for the sky's radiance cubemap to catch up. The sky is the
		# scene's ambient source, so the ground's own lighting changes with it and
		# a frame taken too early has half the effect in it.
		await _wait(90)
		var image := await _frame("air_toggle_%s" % ("on" if lit else "off"))
		var sky := _sky_mean(image)
		print("player_test: scattering %-3s sky %.3f %.3f %.3f  hue %3.0f deg  sat %.2f  luma %.3f" % [
			"on" if lit else "off", sky.r, sky.g, sky.b,
			sky.h * 360.0, sky.s, sky.get_luminance()])
	SettingsManager.set_setting(&"graphics", &"atmospheric_scattering", true)
	await _wait(90)

	# Back at the sun before timing anything. The ray pass skips every pixel
	# outside `reach` of the sun and the whole dispatch when the sun is behind the
	# camera, so a cost measured looking away from it is a measurement of the
	# early-out.
	review.look_at(eye + to_sun, site_up)
	await _wait(60)

	# Cost. Both effects on against both off, from the same viewpoint, after the
	# terrain has settled — so the difference is the two passes and nothing else.
	var costs := {}
	for on: bool in [true, false]:
		SettingsManager.set_setting(&"graphics", &"god_rays", on)
		SettingsManager.set_setting(&"graphics", &"atmospheric_scattering", on)
		await _wait(60)
		costs["on" if on else "off"] = await _frame_cost(240)
	var with: Dictionary = costs["on"]
	var without: Dictionary = costs["off"]
	print("player_test: cost  both on %.2f ms/frame (cpu %.2f, worst %.2f)" % [
		with["frame"], with["cpu"], with["worst"]])
	print("player_test: cost  both off %.2f ms/frame (cpu %.2f, worst %.2f)" % [
		without["frame"], without["cpu"], without["worst"]])
	print("player_test: cost  the two effects add %.2f ms/frame" % [
		float(with["frame"]) - float(without["frame"])])

	SettingsManager.set_setting(&"graphics", &"god_rays", true)
	SettingsManager.set_setting(&"graphics", &"atmospheric_scattering", true)
	review.queue_free()
	_toggle_summary()


## One god-rays case: the frame with the effect on, the same frame again with
## nothing touched, and the frame with it off.
##
## The middle capture is the measurement's own noise floor and is why three frames
## are taken rather than two. A world this busy never gives the same frame twice,
## and without knowing by how much, a small difference cannot be told from no
## difference at all.
func _ray_case(tag: String, review: Camera3D, to_sun: Vector3) -> void:
	SettingsManager.set_setting(&"graphics", &"god_rays", true)
	await _wait(20)
	var lit := await _frame_sample()
	await _wait(4)
	var again := await _frame_sample()
	await _shot("rays_%s_on" % tag)
	SettingsManager.set_setting(&"graphics", &"god_rays", false)
	await _wait(20)
	var dark := await _frame_sample()
	await _shot("rays_%s_off" % tag)
	var added := _frame_difference(dark, lit)
	var noise := _frame_difference(lit, again)
	_difference_picture(dark, lit).save_png(ProjectSettings.globalize_path(
		SHOT_DIR + "rays_%s_added.png" % tag))
	# Where the sun landed on screen, worked out here rather than read off the
	# effect, so a frame with no shafts in it can be told from a frame whose sun
	# was somewhere the shafts were never going to be.
	var at := review.global_position + to_sun * 1.0e7
	var where := "behind the camera"
	var sun_uv := Vector2(0.5, 0.5)
	if not review.is_position_behind(at):
		sun_uv = review.unproject_position(at) \
			/ review.get_viewport().get_visible_rect().size
		where = "uv %.2f, %.2f" % [sun_uv.x, sun_uv.y]
	var shape := _ray_shape(dark, lit, sun_uv)
	print("player_test: rays %-8s added mean %.2f worst %.0f loud %d   near %.1f far %.1f (x%.1f)   noise %.2f   sun %s" % [
		tag, added.x, added.y, int(added.z), shape.x, shape.y,
		shape.x / maxf(shape.y, 0.01), noise.x, where])
	SettingsManager.set_setting(&"graphics", &"god_rays", true)


## The phase at which the sun stands [param elevation] above the horizon at
## [param up], as the sine of that angle.
##
## Searched rather than solved. The orbit is built from the planet's frost axis
## and a noon anchor, and reproducing that arithmetic here to invert it would be a
## second copy of it that could disagree; asking the cycle itself two hundred and
## forty times costs nothing and cannot.
func _phase_for_elevation(cycle: CelestialCycle, sun: DirectionalLight3D,
		up: Vector3, elevation: float) -> float:
	var best := 0.0
	var closest := INF
	for step in 240:
		var phase := float(step) / 240.0
		cycle.set_phase(phase)
		var error := absf(up.dot(sun.global_basis.z.normalized()) - elevation)
		if error < closest:
			closest = error
			best = phase
	return best


## Mean colour of the top eighth of a frame, which at every pitch used by the
## scattering rows is sky and nothing else.
func _sky_mean(image: Image) -> Color:
	var total := Vector3.ZERO
	var counted := 0
	for y in range(0, maxi(image.get_height() / 8, 1), 2):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			total += Vector3(pixel.r, pixel.g, pixel.b)
			counted += 1
	total /= maxf(float(counted), 1.0)
	return Color(total.x, total.y, total.z)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("player_test: PASS  %s" % message)
		return
	_toggle_failures += 1
	push_error("player_test: FAIL  %s" % message)


func _toggle_summary() -> void:
	print("player_test: graphics toggles %s" % (
		"all wiring checks passed" if _toggle_failures == 0
		else "%d wiring check(s) failed" % _toggle_failures))


func _orbit_glow_checks() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var trees := world.find_child("LandingFlowerTrees", true, false) as FlowerTreeField
	var flowers := world.find_child("LandingFlowers", true, false) as GroundCover
	if cycle == null or trees == null or flowers == null:
		push_error("player_test: orbit glow needs the cycle and both flora fields")
		return
	var surface := Planet.SURFACE_MATERIAL
	# GroundCover now replays every deterministic flower tile on a worker rather
	# than painting the field's radius. Wait for that image to reach the terrain
	# before stopping the flora processes below; stopping it first would leave
	# the completed worker with nobody to upload its image and produce a black
	# test that says nothing about the feature.
	for _frame in 1800:
		if flowers.aerial_glow_ready():
			break
		await get_tree().process_frame
	if not flowers.aerial_glow_ready():
		push_error("player_test: flower aerial mask did not finish")
		return
	var flower_mask := flowers.get("_aerial_glow_texture") as Texture2D
	if flower_mask != null:
		flower_mask.get_image().save_png(ProjectSettings.globalize_path(
			SHOT_DIR + "orbit_glow_flower_mask.png"))
	var centre: Vector3 = trees.get("_centre")
	var radius: float = surface.get_shader_parameter(&"flora_glow_radius")
	var flower_radius: float = surface.get_shader_parameter(
		&"flora_flower_glow_radius")
	if radius <= 0.0:
		push_error("player_test: the flower-tree field published no glow radius")
		return
	if flower_radius <= 0.0:
		push_error("player_test: GroundCover published no flower glow radius")
		return
	print("player_test: orbit glow  field at %.3f %.3f %.3f, trees %.0f m, flowers %.0f m" % [
		centre.x, centre.y, centre.z, radius, flower_radius])

	# Local midnight over the colony — the phase the pooled flora lights are
	# already checked at, so this and the night-light rows agree on when night
	# is. Stopped, because a sunrise part-way down the list would fade the thing
	# being measured out from under it.
	cycle.period_seconds = 0.0
	cycle.set_phase(0.5)
	if _player.hud != null:
		_player.hud.visible = false
	_player._camera_mode = 0
	_still_planet(world)
	await _wait(30)

	# Every altitude the two laws name, plus one underneath the first of them
	# that has to come back black, plus the 9 km orbit players spawn in. The
	# ceiling row and the row above it are read together: the point of the
	# remainder is that they are close, not that either is any particular value.
	for altitude: float in [
			20.0, 40.0, 60.0, 80.0, 140.0, 240.0,
			500.0, 1200.0, 5000.0, 9000.0,
		]:
		_look_down_from(centre, altitude)
		# Long enough for the quadtree to have reached this viewpoint. Coarse
		# ground arriving mid-capture would show up as a change the glow gets
		# the credit for.
		await _wait(210)
		_look_down_from(centre, altitude)
		await _wait(30)
		surface.set_shader_parameter(&"flora_glow_radius", radius)
		surface.set_shader_parameter(&"flora_flower_glow_radius", flower_radius)
		await _wait(4)
		var lit := await _frame("orbit_glow_%06d_lit" % int(altitude))
		# The same frame again, nothing touched. Whatever this picks up is the
		# measurement's own noise, and the row below only means something if it
		# is larger than this.
		await _wait(4)
		var again := await _frame("")
		surface.set_shader_parameter(&"flora_glow_radius", 0.0)
		surface.set_shader_parameter(&"flora_flower_glow_radius", 0.0)
		await _wait(4)
		var dark := await _frame("orbit_glow_%06d_dark" % int(altitude))
		surface.set_shader_parameter(&"flora_glow_radius", radius)
		surface.set_shader_parameter(&"flora_flower_glow_radius", flower_radius)
		_report_glow(altitude, lit, dark, again)


## Puts the eye straight over [param direction] at [param altitude] metres,
## pointed at the ground under it.
func _look_down_from(direction: Vector3, altitude: float) -> void:
	var centre := _planet.global_position
	var up := (_planet.global_transform.basis * direction).normalized()
	var north := Vector3.UP - up * Vector3.UP.dot(up)
	if north.length_squared() < 0.001:
		north = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	_player._apply_stance(FLY)
	_player.global_transform = Transform3D(
		Basis.looking_at(-up, north.normalized()),
		centre + up * (_planet.shape.radius + altitude))
	_player.velocity = Vector3.ZERO


## Stops everything on this planet that moves on its own.
##
## Two frames taken a moment apart differ for a great many reasons and only one
## of them is the thing under test. From orbit the worst offender by far is the
## cloud deck, which drifts, breathes and swirls across most of what is on
## screen; nearer the ground it is the grass. None of it is subtle enough to
## average out over the four frames between captures.
func _still_planet(world: Node) -> void:
	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.0)
	# The body, because first person still puts an arm across the frame and that
	# arm breathes. Looking straight down it is a large part of the picture and
	# by far the loudest thing in it.
	if _player.character != null:
		_player.character.visible = false
	# And the pooled flora lights, which are re-aimed on a timer and glide to
	# their new trees. Hiding them is not enough — the fields drive them every
	# frame — so the fields have to stop running.
	# The shoals as well. Over land they are not in frame and were never missed,
	# but on the reef they cross most of it: two frames four apart differed by a
	# full-scale 1.0 somewhere in the picture purely from fish, which is a noise
	# floor no measurement can be taken above. Their scripts re-pose the
	# MultiMesh and the VAT swims the bodies, so both have to stop.
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField or node is FishSchool:
			node.set_process(false)
			node.set_physics_process(false)
			for light in _omni_lights(node):
				light.visible = false
	var clouds := Planet.CLOUD_MATERIAL
	clouds.set_shader_parameter(&"wind", Vector3.ZERO)
	clouds.set_shader_parameter(&"breathe_speed", 0.0)
	clouds.set_shader_parameter(&"iris_drift", 0.0)
	# Off the material and not off a node lookup. This was reaching for a node
	# called "Ocean", which PlanetWater has never built — it makes a "Water" with
	# a "Surface" under it — so the sea went on rippling through every frame this
	# function exists to hold still, and any measurement of what the ground does
	# between two frames had a moving sea somewhere in it.
	var water := PlanetWater.SURFACE_MATERIAL
	water.set_shader_parameter(&"ripple_speed", 0.0)
	water.set_shader_parameter(&"swell_speed", 0.0)
	water.set_shader_parameter(&"surf_speed", 0.0)
	water.set_shader_parameter(&"caustic_speed", 0.0)
	for plant in _plant_materials(world):
		plant.set_shader_parameter(&"wind_sway", 0.0)
		plant.set_shader_parameter(&"night_pulse_amount", 0.0)
		plant.set_shader_parameter(&"night_twinkle_amount", 0.0)
	# Every baked clip in the world, not only the plants' — the shoals are on
	# vivid_fish rather than vivid_plant, so the list above has never reached
	# them and the swim cycle went on playing through frames meant to be still.
	for material in _instanced_materials(world):
		material.set_shader_parameter(&"vat_playback_speed", 0.0)


## What the stand-in put on screen at this altitude. Reported as the brightest
## pixel it added as well as the mean, because a smudge a few pixels across is
## the whole point from orbit and a mean over the frame would call that nothing.
func _report_glow(altitude: float, lit: Image, dark: Image, again: Image) -> void:
	var width := lit.get_width()
	var height := lit.get_height()
	var difference := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	var added := 0.0
	var peak := 0.0
	var touched := 0
	var noise := 0.0
	var noise_peak := 0.0
	for y in height:
		for x in width:
			var change := lit.get_pixel(x, y) - dark.get_pixel(x, y)
			var most := maxf(maxf(change.r, change.g), change.b)
			difference.set_pixel(x, y, Color(
				clampf(change.r * 8.0, 0.0, 1.0),
				clampf(change.g * 8.0, 0.0, 1.0),
				clampf(change.b * 8.0, 0.0, 1.0)))
			added += maxf(most, 0.0)
			peak = maxf(peak, most)
			if most > 0.004:
				touched += 1
			var drifted := again.get_pixel(x, y) - lit.get_pixel(x, y)
			var moved := maxf(maxf(absf(drifted.r), absf(drifted.g)),
				absf(drifted.b))
			noise += moved
			noise_peak = maxf(noise_peak, moved)
	var path := ProjectSettings.globalize_path(
		"%sorbit_glow_%06d_added.png" % [SHOT_DIR, int(altitude)])
	difference.save_png(path)
	var pixels := float(width * height)
	print("player_test: orbit glow  %6.0f m  peak=%.4f mean=%.5f lit=%.3f%%  (noise peak=%.4f mean=%.5f)" % [
		altitude, peak, added / pixels, 100.0 * touched / pixels,
		noise_peak, noise / pixels])


## The grass as it was before the middle distance was filled in, for `--lawn
## --before` to measure against.
##
## Written here rather than fetched from source control because these resources
## are not in it, and a density change is worth nothing without the frame time it
## cost — which needs the old field and the new one measured by the same code on
## the same machine within a minute of each other. Applied before the world is
## added to the tree, so the fields grow from these numbers rather than being
## rebuilt from them afterwards.
func _restore_thin_lawn() -> void:
	var near := load("res://game/props/grass_species.tres") as PlantSpecies
	near.per_square_metre = 18.0
	near.clump_count = 10
	near.draw_within = 48.0
	near.thin_from = 14.0
	near.thin_to = 0.0
	near.far_density = 0.09
	var far := load("res://game/props/grass_distant_species.tres") as PlantSpecies
	far.per_square_metre = 1.4
	far.clump_count = 4
	far.thin_from = 60.0
	far.thin_to = 110.0
	far.far_density = 0.12
	var skin := load("res://game/props/grass.tres") as ShaderMaterial
	skin.set_shader_parameter(&"translucency", 0.72)
	print("player_test: lawn  measuring the field as it was")


## How tall the plants in a stand are, which is what tells a lawn from a flower
## bed when the nodes have no names worth printing.
func _stand_size(world: Node, material: ShaderMaterial) -> String:
	for node in _multimeshes(world):
		var used := node.material_override as ShaderMaterial
		if used != material:
			continue
		if node.multimesh == null or node.multimesh.mesh == null:
			continue
		var box := node.multimesh.mesh.get_aabb()
		return "%d of %.2f m" % [node.multimesh.instance_count, box.size.y]
	return "unknown"


## The exact place and hour a flicker was reported from, taken apart.
##
## Read straight off the reported screen rather than searched for: the plate
## prints the planet-local direction under the player, and the clock is
## `phase * 24 + 12` hours, so 13:39 is phase 0.069. Worth spelling out because
## the last two passes measured a spot this harness chose for itself, two
## hundred metres from anything, and reported a ground that does not flicker —
## which was true of that spot and answered nothing.
##
## The flora stays where it is here, and that is the point of the pass. Every
## earlier reading hid it, on the grounds that a lawn animating in the frame is
## louder than anything underneath it; but two hundred metres from the ship the
## ground is covered in blades and trees, all of them casting shadows from a sun
## that turns every frame, and hiding them takes the suspect out of the room.
## The wind is stopped instead, which holds the blades still without removing
## what they throw on the ground.
const SPOT_DIRECTION := Vector3(-0.2638, -0.1140, 0.9578)
const SPOT_PHASE := 0.06875

func _spot_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if _player.hud != null:
		_player.hud.visible = false
	if _player.character != null:
		_player.character.visible = false
	_player._camera_mode = 2
	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.0)

	var here := SPOT_DIRECTION.normalized()
	if cycle != null:
		cycle.set_phase(SPOT_PHASE)
	_stand_on(here)
	# Long, because the cover streams in behind the terrain and a reading taken
	# while it is still arriving is a reading of it arriving. Two thousand steps
	# is half a minute of standing still, which is what it took for the first row
	# to stop reading four times what the same row reads at the end of the run.
	await _wait(2000)
	_stand_on(here)
	_pin_eye()
	_look(-0.42)
	await _drawn(60)
	var up := (_planet.global_transform.basis * here).normalized()
	print("player_test: spot  sun %+.1f deg, %d m from the ship" % [
		rad_to_deg(asin(clampf(up.dot(sun.global_basis.z), -1.0, 1.0))),
		int(_ranged())])
	await _shot("spot_view")

	var cover: Array[Node3D] = []
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField:
			cover.append(node as Node3D)

	# Interleaved and repeated rather than run once down the list. The first pass
	# of this read 22, 18, 6, 2, 6, 7 and looked like a clean answer; it was the
	# world still streaming in behind the first two rows, and every later row was
	# reading a scene that had finished arriving. A setting that appears twice at
	# opposite ends of the run cannot be flattered by that, and the gap between
	# its two readings is the size of the drift the rest should be judged by.
	# The blades are posed by a baked clip that runs off TIME, which the wind
	# being off does not stop. So "cover hidden" and "cover frozen" ask two
	# different questions — whether the flora is there at all, and whether it is
	# moving — and only the second one separates a field that is animating, which
	# it is meant to do, from a field that is boiling, which is the complaint.
	var plants := _plant_materials(world)
	var plant_sway := {}
	var plant_speed := {}
	var plant_owner := {}
	var plant_scatter := {}
	var plant_calm_from := {}
	var plant_calm_to := {}
	for plant in plants:
		plant_sway[plant] = plant.get_shader_parameter(&"wind_sway")
		plant_speed[plant] = plant.get_shader_parameter(&"vat_playback_speed")
		plant_scatter[plant] = plant.get_shader_parameter(&"sway_scatter")
		plant_calm_from[plant] = plant.get_shader_parameter(&"calm_from")
		plant_calm_to[plant] = plant.get_shader_parameter(&"calm_to")
		plant_owner[plant] = "?"
	# Which stand each material belongs to, so a row can quiet the grass without
	# quieting the flowers. Both are in frame here and they are very different
	# sizes, so one distance fade cannot be right for both and knowing which one
	# is boiling decides which of them has to change.
	for node in _multimeshes(world):
		var used := node.material_override as ShaderMaterial
		if used == null and node.multimesh != null and node.multimesh.mesh != null:
			for surface in node.multimesh.mesh.get_surface_count():
				used = node.multimesh.mesh.surface_get_material(surface) as ShaderMaterial
				if used != null:
					break
		if used != null and plant_owner.has(used) and plant_owner[used] == "?":
			plant_owner[used] = String(node.name)
	# Named by what they are set to rather than by their node, because the stands
	# are built at runtime and Godot calls them all @MultiMeshInstance3D@1194.
	# The draw radius and the clip length together are enough to tell a lawn from
	# a flower bed at a glance.
	for index in plants.size():
		var plant := plants[index]
		print("player_test: spot  stand %d draws to %s m, %s frames, %s blades, calm %s to %s, speed %s" % [
			index, plant.get_shader_parameter(&"draw_within"),
			plant.get_shader_parameter(&"vat_frame_count"),
			_stand_size(world, plant),
			plant.get_shader_parameter(&"calm_from"),
			plant.get_shader_parameter(&"calm_to"),
			plant.get_shader_parameter(&"vat_playback_speed")])

	# Calming the far blades did nothing, which rules out distance as the dial:
	# at this density a blade is under a pixel from two or three metres, not the
	# eight the shader assumes, so the boil is coming from the grass around the
	# boots and no fade that leaves it alone can reach it. What is left is the
	# motion itself — how fast the baked clip runs and how much of its phase is
	# per plant — so those are what this sweeps.
	var rows: Array[Dictionary] = [
		{"name": "as shipped"},
		{"name": "half speed", "speed": 0.5},
		{"name": "quarter speed", "speed": 0.25},
		{"name": "in step", "scatter": 0.0},
		{"name": "in step, half speed", "scatter": 0.0, "speed": 0.5},
		{"name": "in step, quarter speed", "scatter": 0.0, "speed": 0.25},
		{"name": "calm 2 to 8 m", "calm_from": 2.0, "calm_to": 8.0},
		{"name": "cover frozen", "freeze": true},
		{"name": "as shipped, last"},
	]

	print("player_test: spot  (still camera; anything above the noise floor is flicker)")
	for row: Dictionary in rows:
		var running: bool = row.get("sun", true)
		if cycle != null:
			cycle.period_seconds = 960.0 if running else 0.0
			if running:
				cycle.set_phase(SPOT_PHASE)
		if sun != null:
			sun.shadow_enabled = row.get("shadow", true)
		for node in cover:
			node.visible = row.get("cover", true)
		var frozen: bool = row.get("freeze", false)
		for index in plants.size():
			var plant := plants[index]
			plant.set_shader_parameter(&"wind_sway",
				0.0 if frozen else plant_sway[plant])
			plant.set_shader_parameter(&"vat_playback_speed", 0.0 if frozen
				else plant_speed[plant] * float(row.get("speed", 1.0)))
			plant.set_shader_parameter(&"sway_scatter",
				row.get("scatter", plant_scatter[plant]))
			plant.set_shader_parameter(&"calm_from",
				row.get("calm_from", plant_calm_from[plant]))
			plant.set_shader_parameter(&"calm_to",
				row.get("calm_to", plant_calm_to[plant]))
		get_viewport().msaa_3d = (Viewport.MSAA_4X if row.get("msaa", false)
			else Viewport.MSAA_DISABLED)
		await _drawn(30)

		var previous := await _frame_sample()
		var mean := 0.0
		var worst := 0.0
		var loud := 0.0
		var noisiest_before := PackedByteArray()
		var noisiest := PackedByteArray()
		const FRAMES := 30
		for _i in FRAMES:
			var frame := await _frame_sample()
			var moved := _ground_difference(previous, frame)
			mean += moved.x
			if moved.y > worst:
				worst = moved.y
				noisiest_before = previous
				noisiest = frame
			loud = maxf(loud, moved.z)
			previous = frame
		if not noisiest.is_empty():
			var picture := _difference_picture(noisiest_before, noisiest)
			var path := ProjectSettings.globalize_path(SHOT_DIR + "spot_"
				+ (row["name"] as String).replace(" ", "_").replace(",", "")
				+ "_moved.png")
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			picture.save_png(path)
		print("player_test: spot %-24s ground mean %.3f, worst %3d, loud %5d" % [
			row["name"], mean / float(FRAMES), int(worst), int(loud)])

	if cycle != null:
		cycle.period_seconds = 960.0
	if sun != null:
		sun.shadow_enabled = true
	for node in cover:
		node.visible = true
	for plant in plants:
		plant.set_shader_parameter(&"wind_sway", plant_sway[plant])
		plant.set_shader_parameter(&"vat_playback_speed", plant_speed[plant])
		plant.set_shader_parameter(&"sway_scatter", plant_scatter[plant])
		plant.set_shader_parameter(&"calm_from", plant_calm_from[plant])
		plant.set_shader_parameter(&"calm_to", plant_calm_to[plant])
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", 0.35)
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"texture_blend", 0.85)


## Where in the day the ground flickers, and which layer of it is flickering.
##
## Nothing moves here but the sun. The eye is pinned, the wind is off and every
## field that re-poses itself is stopped, so a difference between two frames a
## sixtieth of a second apart is the lighting and nothing else. Over that
## sixtieth the sun turns by two thousandths of a degree, which no honest shading
## can react to: whatever a frame pair differs by is the flicker.
##
## Swept across the whole day because the report is that it depends on the hour.
## The sun's height over the ground being watched is printed beside each reading,
## so a row that stands out can be read against how grazing the light was.
func _daylight_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if _player.hud != null:
		_player.hud.visible = false
	_player._camera_mode = 0
	_still_planet(world)
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField:
			(node as Node3D).visible = false

	var grass := _grass_direction()
	_stand_on(grass)
	await _wait(240)
	_stand_on(grass)
	_pin_eye()
	_look(-0.42)
	var up := (_planet.global_transform.basis * grass).normalized()

	const STEPS := 12
	var worst_phase := 0.0
	var worst_seen := -1.0
	for step in STEPS:
		var phase := float(step) / float(STEPS)
		var moved := await _daylight_flicker(cycle, phase)
		var height := rad_to_deg(asin(clampf(up.dot(sun.global_basis.z), -1.0, 1.0)))
		if moved.y > worst_seen:
			worst_seen = moved.y
			worst_phase = phase
		print("player_test: daylight phase %.2f  sun %+6.1f deg   frame to frame mean %.3f, worst %3d, loud %5d" % [
			phase, height, moved.x, int(moved.y), int(moved.z)])

	# The worst hour, taken apart. Each row switches off one more of the things
	# the light lands on, so whichever row goes quiet is the one flickering.
	print("player_test: daylight worst hour is phase %.2f" % worst_phase)
	# And one from the middle of the night as well, because the worst hour above
	# lands on the terminator, where a low sun is its own explanation. Deep night
	# has no sun at all and should be the quietest frame of the day.
	await _daylight_flicker(cycle, 0.75, "deep_night")
	for row: Array in [["everything", 0.85, 0.35, true],
			["bump off", 0.85, 0.0, true],
			["photo off", 0.0, 0.35, true],
			["shadows off", 0.85, 0.35, false]]:
		Planet.SURFACE_MATERIAL.set_shader_parameter(&"texture_blend", row[1])
		Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", row[2])
		if sun != null:
			sun.shadow_enabled = row[3]
		var moved := await _daylight_flicker(cycle, worst_phase,
			(row[0] as String).replace(" ", "_"))
		print("player_test: daylight %-12s frame to frame mean %.3f, worst %3d, loud %5d" % [
			row[0], moved.x, int(moved.y), int(moved.z)])
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"texture_blend", 0.85)
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", 0.35)
	if sun != null:
		sun.shadow_enabled = true

	# And the same hours walked rather than stood in. Everything above says the
	# lighting is steady, which it is; the report is of a flicker, and a flicker
	# needs the eye to move for a ground sampled too coarsely to show it. The sky
	# is left out of these because the stars twinkle and are most of the loud
	# pixels in every night frame otherwise.
	var forward := -_player.global_basis.z.normalized()
	print("player_test: daylight walking pace, ground only")
	for row: Array in [["low sun", 0.08, 0.35], ["low sun, no bump", 0.08, 0.0],
			["high sun", 0.33, 0.35], ["high sun, no bump", 0.33, 0.0]]:
		Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", row[2])
		var moved := await _daylight_walk(cycle, row[1], grass, forward)
		print("player_test: daylight %-18s ground mean %.3f, worst %3d, loud %5d" % [
			row[0], moved.x, int(moved.y), int(moved.z)])
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", 0.35)


## The same reading with the eye creeping forward at a walk. The absolute number
## means nothing — most of it is the view honestly changing — so it is only ever
## read as one row against another.
func _daylight_walk(cycle: CelestialCycle, phase: float, grass: Vector3,
		forward: Vector3) -> Vector3:
	if cycle != null:
		cycle.set_phase(phase)
	_stand_on(grass)
	_pin_eye()
	_look(-0.42)
	await _drawn(40)
	var previous := await _frame_sample()
	var mean := 0.0
	var worst := 0.0
	var loud := 0.0
	const FRAMES := 24
	for _i in FRAMES:
		_player.global_position += forward * SHIMMER_STEP
		_player.reset_physics_interpolation()
		var frame := await _frame_sample()
		var moved := _ground_difference(previous, frame)
		mean += moved.x
		worst = maxf(worst, moved.y)
		loud = maxf(loud, moved.z)
		previous = frame
	return Vector3(mean / float(FRAMES), worst, loud)


## [method _frame_difference] over the lower part of the frame only, which at
## this pitch is all ground. The sky above it holds the starfield, and a star is
## one pixel wide and either drawn or not: it dwarfs everything happening on the
## ground and answers a question nobody asked.
func _ground_difference(before: PackedByteArray,
		after: PackedByteArray) -> Vector3:
	const HORIZON := 70
	var total := 0
	var worst := 0
	var loud := 0
	var counted := 0
	for y in range(HORIZON, SHIMMER_HEIGHT):
		for x in SHIMMER_WIDTH:
			var index := (y * SHIMMER_WIDTH + x) * 3
			if index + 2 >= before.size() or index + 2 >= after.size():
				continue
			var step := maxi(maxi(absi(before[index] - after[index]),
				absi(before[index + 1] - after[index + 1])),
				absi(before[index + 2] - after[index + 2]))
			total += step
			worst = maxi(worst, step)
			if step > SHIMMER_LOUD:
				loud += 1
			counted += 1
	return Vector3(float(total) / maxf(counted, 1), float(worst), float(loud))


## Frame-to-frame movement at one hour of the day, as mean, worst and loud pixels.
##
## [param tag], when given, also writes out the noisiest pair of frames as a
## difference picture. A number says how much moved and says nothing about
## where, and where is most of the answer: sixty loud pixels are one story if
## they are scattered over the lawn and quite another if they are all in the sky.
func _daylight_flicker(cycle: CelestialCycle, phase: float,
		tag := "") -> Vector3:
	if cycle != null:
		cycle.set_phase(phase)
	# Long enough for the sky's own radiance to have settled at this hour, so
	# what is measured afterwards is the steady state and not the arrival.
	await _drawn(45)
	var previous := await _frame_sample()
	var mean := 0.0
	var worst := 0.0
	var loud := 0.0
	var noisiest := PackedByteArray()
	var noisiest_before := PackedByteArray()
	const FRAMES := 24
	for _i in FRAMES:
		var frame := await _frame_sample()
		var moved := _frame_difference(previous, frame)
		mean += moved.x
		if moved.y > worst:
			worst = moved.y
			noisiest_before = previous
			noisiest = frame
		loud = maxf(loud, moved.z)
		previous = frame
	if tag != "" and not noisiest.is_empty():
		var picture := _difference_picture(noisiest_before, noisiest)
		var path := ProjectSettings.globalize_path(
			SHOT_DIR + "daylight_" + tag + "_moved.png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		picture.save_png(path)
		await _shot("daylight_" + tag)
	return Vector3(mean / float(FRAMES), worst, loud)


## What the faceted blotches in the middle distance are made of.
##
## Everything cheap has already been ruled out: they survive the photographic
## texture being switched off, the scatter being switched off, the procedural
## bumps, and the macro field. What is left is the mesh, its vertex colours, and
## the light falling on it, and those three are separated here by asking
## questions only one of them can answer.
##
## Moving the sun is the first. Lighting on geometry changes when the light
## does; a colour written into the vertices does not care. Refining the mesh is
## the second and is the direct test of the LOD reading: if the blotches are the
## terrain being lit at the vertex spacing of a coarse chunk, then splitting
## those chunks sooner has to make them smaller.
func _facet_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if cycle != null:
		cycle.period_seconds = 0.0
		cycle.set_phase(0.0)
	if _player.hud != null:
		_player.hud.visible = false
	_player._camera_mode = 0
	_still_planet(world)
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField:
			(node as Node3D).visible = false

	var grass := _grass_direction()
	var shipped_split := _planet.split_ratio
	var baseline := PackedByteArray()
	# Daylight throughout. The first run of this was taken at phase zero, which
	# is the middle of the night here, and a dark frame hid the thing being
	# looked for: in daylight the ground is covered in hard-edged rectangles that
	# are simply not visible under starlight.
	const DAY := 0.42
	# All with the photograph switched off, because with it on it is most of the
	# frame and every other row's difference disappears underneath it. What is
	# left is the mesh, the macro field and the procedural bumps, and each row
	# takes one more of them away until the ground is nothing but lit geometry.
	for row: Array in [["flat", shipped_split, 0.4, 0.35],
			["flat, fine mesh", shipped_split * 4.0, 0.4, 0.35],
			["flat, no macro", shipped_split, 0.0, 0.35],
			["flat, no macro or bump", shipped_split, 0.0, 0.0],
			["geometry only, fine mesh", shipped_split * 4.0, 0.0, 0.0]]:
		if cycle != null:
			cycle.set_phase(DAY)
		if sun != null:
			sun.shadow_enabled = true
		if not is_equal_approx(_planet.split_ratio, row[1]):
			_planet.split_ratio = row[1]
		Planet.SURFACE_MATERIAL.set_shader_parameter(&"texture_blend", 0.0)
		Planet.SURFACE_MATERIAL.set_shader_parameter(&"macro_amount", row[2])
		Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", row[3])

		_player.set_physics_process(true)
		_player.set_process(true)
		_stand_on(grass)
		# Long, because refining the quadtree four times over is a lot of chunks
		# and a half-built mesh would answer the question wrongly.
		await _wait(420)
		_stand_on(grass)
		_pin_eye()
		_look(-0.42)
		await _drawn(30)
		var tag: String = (row[0] as String).replace(" ", "_")
		await _shot("facet_" + tag)
		var frame := await _frame_sample()
		var moved := 0.0
		if baseline.is_empty():
			baseline = frame
		else:
			moved = _frame_difference(baseline, frame).x
		print("player_test: facets %-15s depth under foot %d, %d triangles   changed from baseline by %.2f" % [
			row[0], int(_planet.statistics()["depth"]),
			int(_planet.statistics()["triangles"]), moved])
	_planet.split_ratio = shipped_split
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"texture_blend", 0.85)
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"macro_amount", 0.4)
	Planet.SURFACE_MATERIAL.set_shader_parameter(&"bump_strength", 0.35)


## The scatter lattice, swept: how big its cells are, how much of each cell is a
## blend, and how much of that blend the surfaces' own relief decides.
##
## The complaint this answers is a jagged, geometric, grid-like pattern on flat
## ground — which is not the texture repeating, it is the scatter that hides the
## repeat becoming visible in its own right. The lattice is a sheared grid of
## triangles a few metres across, and while its weights were cubed the handover
## between two cells happened in a band narrow enough to read as a line.
##
## Each row is measured from overhead, where the lattice has a constant spacing
## and so shows up in the correlation, and photographed again from standing
## height, which is where it is actually complained about.
func _splat_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
		cycle.set_phase(0.0)
	if _player.hud != null:
		_player.hud.visible = false
	_player._camera_mode = 0
	_still_planet(world)
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField:
			(node as Node3D).visible = false

	var surface := Planet.SURFACE_MATERIAL
	var grass := _grass_direction()
	var shore := _shore_direction()
	var standing := _planet.shape.elevation(grass, _planet.finest_spacing())
	# Left at the shader's own default in the material, so ask and fall back
	# rather than reading a null.
	var depth_set: Variant = surface.get_shader_parameter(&"splat_depth")
	var shipped_depth: float = 0.25 if depth_set == null else float(depth_set)
	for row: Array in [["height on", shipped_depth], ["height off", 0.0]]:
		surface.set_shader_parameter(&"splat_depth", row[1])
		var tag: String = (row[0] as String).replace(" ", "_")

		# Overhead, to confirm the crispness that widening the blend cost has
		# come back — this is the number that caught the wash.
		_player.set_physics_process(true)
		_player.set_process(true)
		_look_down_from(grass, standing + 30.0)
		await _wait(150)
		_look_down_from(grass, standing + 30.0)
		_pin_eye()
		_look(0.0)
		await _drawn(20)
		var above := await _frame("splat_above_" + tag)
		var lattice := _report_tiling(row[0], above)

		# And a shoreline, which is where two materials actually meet and so the
		# only place the height blending has anything to do.
		_player.set_physics_process(true)
		_player.set_process(true)
		_stand_on(shore)
		await _wait(120)
		_stand_on(shore)
		_pin_eye()
		_look(-0.30)
		await _drawn(20)
		var settled := await _frame_sample()
		await _drawn(2)
		var again := await _frame_sample()
		await _shot("splat_shore_" + tag)
		var still := _frame_difference(settled, again)
		print("player_test: splat  %-11s lattice %.3f (0.076 was the crisp baseline)  shore still %.3f" % [
			row[0], lattice, still.x])
	surface.set_shader_parameter(&"splat_depth", shipped_depth)


func _pin_eye() -> void:
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## A beach: high enough to be out of the sea, low enough that the sand rule still
## fires, so that both it and the grass above it are in one frame.
func _shore_direction() -> Vector3:
	var spacing := _planet.finest_spacing()
	var best := Vector3.UP
	var flattest := INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for _try in 6000:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var height := _planet.shape.elevation(direction, spacing)
		if height < 5.0 or height > 11.0:
			continue
		var fall := _fall_across(direction, height, spacing)
		if fall < flattest:
			flattest = fall
			best = direction
	return best


## Whether the ground still repeats, looked at from above with the cover pulled
## off it.
##
## Two different faults hide under the word "tiling" and they need separate
## measurements. The first is the grid: the same patch of texture recurring at a
## fixed spacing, which shows up as the picture correlating with a shifted copy
## of itself at that spacing. The second is direction: every copy of the texture
## facing the same way, so the grain in it combs the whole landscape one way. A
## scatter that only slides the texture fixes the first and leaves the second
## untouched, and the second is the one that survives being looked at.
##
## So this reports a correlation curve and an orientation histogram, with the
## cell turning off and then on, at the same camera.
func _tiling_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
		cycle.set_phase(0.0)
	if _player.hud != null:
		_player.hud.visible = false
	_player._camera_mode = 0
	_still_planet(world)
	# The cover has to come off. From sixty metres up a lawn is what is in shot,
	# and measuring the arrangement of grass blades would answer a question
	# nobody asked about a texture nobody can see.
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField:
			(node as Node3D).visible = false

	var surface := Planet.SURFACE_MATERIAL
	var places := {
		"grass": _grass_direction(),
		"sand": _sand_direction(_planet.to_local(_ground.origin).normalized()),
	}
	# The third row is the control. Turning the cells can only help where the
	# tiled photograph is what is on screen, and how much of a given ground it is
	# responsible for is not obvious by eye — a procedural macro field is mixed
	# over the top of it and can be most of what a distant slope shows. Taking
	# the photograph out entirely says how much of each of these pictures was
	# ever the scatter's to fix.
	var blend: float = surface.get_shader_parameter(&"texture_blend")
	for place: String in places:
		var lattice := {}
		for row: Array in [["spin0", 0.0, blend], ["spin100", 1.0, blend],
				["nophoto", 1.0, 0.0]]:
			surface.set_shader_parameter(&"texture_spin", row[1])
			surface.set_shader_parameter(&"texture_blend", row[2])
			# High enough that a dozen repeats are in frame, low enough that the
			# texture is still resolved rather than mipped away.
			# Above the ground, not above sea level, which is what
			# _look_down_from is given. A sand shelf sitting forty metres up put
			# the eye five metres over it and photographed a grazing close-up of
			# a slope, and no measurement of tiling survives that.
			var standing := _planet.shape.elevation(places[place],
				_planet.finest_spacing()) + 30.0
			_player.set_physics_process(true)
			_player.set_process(true)
			_look_down_from(places[place], standing)
			await _wait(150)
			_look_down_from(places[place], standing)
			# Pinned, or the shot is not the one that was asked for. Flight
			# rights the body towards the planet's up within a few frames of
			# being pointed at the ground, so waiting after aiming hands back a
			# view of the horizon — and a horizon measures as strongly
			# directional whatever the texture on it is doing, which is how the
			# first run of this reported a 30% preferred direction and no effect
			# from anything.
			_player.set_physics_process(false)
			_player.set_process(false)
			_player.velocity = Vector3.ZERO
			_player.reset_physics_interpolation()
			_look(0.0)
			await _drawn(20)
			var tag := "%s_%s" % [place, row[0]]
			var view := await _frame("tiling_" + tag)
			lattice[row[0]] = _report_tiling(tag, view)
		var off: float = lattice["spin0"]
		var on: float = lattice["spin100"]
		var none: float = lattice["nophoto"]
		if absf(none - off) < 0.02:
			print("player_test: tiling  %s: the photograph contributes nothing to this view, so there is no tiling here for the scatter to fix" % place)
		elif off <= 0.02:
			print("player_test: tiling  %s: no lattice to begin with" % place)
		else:
			print("player_test: tiling  %s: lattice %.3f -> %.3f, %.0f%% less, against %.3f with no photograph at all" % [
				place, off, on, 100.0 * (1.0 - on / off), none])
	surface.set_shader_parameter(&"texture_spin", 1.0)
	surface.set_shader_parameter(&"texture_blend", blend)


## The two numbers, off one overhead frame.
##
## Read at full resolution over a square crop rather than off a shrunken copy of
## the whole frame: the grain that carries the direction is a few pixels across
## and averaging it away first would report every ground as beautifully
## isotropic.
func _report_tiling(tag: String, view: Image) -> float:
	if view == null:
		push_error("player_test: tiling captured no frame for %s" % tag)
		return 0.0
	var span := 384
	var patch := view.get_region(Rect2i(
		(view.get_width() - span) / 2, (view.get_height() - span) / 2,
		span, span))
	var values := PackedFloat32Array()
	values.resize(span * span)
	var mean := 0.0
	for y in span:
		for x in span:
			var pixel := patch.get_pixel(x, y)
			var grey := pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114
			values[y * span + x] = grey
			mean += grey
	mean /= float(span * span)
	var energy := 0.0
	for index in values.size():
		values[index] -= mean
		energy += values[index] * values[index]
	if energy <= 0.0:
		print("player_test: tiling  %-14s flat frame, nothing to measure" % tag)
		return 0.0

	# How much the picture looks like itself shifted sideways.
	#
	# The number that matters is not the correlation itself but where the curve
	# turns back up. Any ground correlates strongly with a small shift because
	# neighbouring pixels are alike, and ground lying across a slope correlates
	# at every shift because the whole crop is one shading ramp — the sand read
	# 0.87 falling smoothly to -0.26 and none of that is a repeat. A repeat is
	# the curve coming back up after it has fallen, at the spacing of the tile.
	# So the figure reported is the largest rise above the lowest point the curve
	# has reached so far, which is zero for a ramp however steep and large for a
	# lattice however faint.
	var row := ""
	var revival := 0.0
	var lowest := INF
	for shift: int in [6, 10, 14, 20, 26, 34, 42, 52, 64, 78, 94]:
		var total := 0.0
		var counted := 0
		for y in span:
			for x in span - shift:
				total += values[y * span + x] * values[y * span + x + shift]
				counted += 1
		var scaled := total / (energy * float(counted) / float(span * span))
		row += "%6.2f" % scaled
		revival = maxf(revival, scaled - lowest)
		lowest = minf(lowest, scaled)

	# Which way the detail runs. Every edge in the picture votes for its own
	# direction, weighted by how strong it is, into eighteen buckets across a
	# half turn. Ground with no preferred direction spreads them evenly at a
	# eighteenth each; ground whose every tile faces the same way spikes.
	var buckets := PackedFloat32Array()
	buckets.resize(18)
	var weight := 0.0
	for y in range(1, span - 1):
		for x in range(1, span - 1):
			var gx := values[y * span + x + 1] - values[y * span + x - 1]
			var gy := values[(y + 1) * span + x] - values[(y - 1) * span + x]
			var strength := sqrt(gx * gx + gy * gy)
			if strength < 0.004:
				continue
			var bucket := clampi(int(fposmod(atan2(gy, gx), PI) / PI * 18.0),
				0, 17)
			buckets[bucket] += strength
			weight += strength
	var peak := 0.0
	if weight > 0.0:
		for index in buckets.size():
			peak = maxf(peak, buckets[index] / weight)
	print("player_test: tiling  %-14s%s   lattice %.3f" % [tag, row, revival])
	print("player_test: tiling  %-14s strongest direction %.1f%% of edges (even would be 5.6%%)" % [
		tag, 100.0 * peak])
	return revival


## Somewhere on the reef shelf, near the colony and flat enough to stand on.
##
## Aimed at the middle of the corals' depth band rather than at any coral: the
## reef is streamed around the viewer, so there is nothing to search for until
## something is already standing there. The band itself is a property of the
## height field and can be found cold.
func _reef_direction() -> Vector3:
	var spacing := _planet.finest_spacing()
	var colony := _planet.to_local(_ground.origin).normalized()
	var east := colony.cross(Vector3.UP if absf(colony.y) < 0.9
		else Vector3.RIGHT).normalized()
	var north := colony.cross(east).normalized()
	var radius := maxf(_planet.shape.radius, 1.0)
	var best := Vector3.ZERO
	var closest := INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 8082
	for _try in 8000:
		# Kept within a couple of kilometres of the landing site so that the
		# phase the day/night rows call midnight is midnight here too.
		var spin := rng.randf() * TAU
		var out := sqrt(rng.randf()) * 2600.0 / radius
		var direction := (colony
			+ (east * cos(spin) + north * sin(spin)) * out).normalized()
		var height := _planet.shape.elevation(direction, spacing)
		if height > -12.0 or height < -26.0:
			continue
		# Flat, for the same reason the grass search wants it: a body that
		# slides is a camera that moves, and both frames below have to be taken
		# from the same place.
		if _fall_across(direction, height, spacing) > 0.6:
			continue
		var off := absf(height + 19.0)
		if off < closest:
			closest = off
			best = direction
	return best

## Structural and live-world checks for the multi-scale procedural geology.
## Blender previews cover the authored close view; this also captures the exact
## runtime PNG/material, a grounded round boulder, and a landmark silhouette.
func _geology_checks() -> void:
	var world := _planet.get_parent()
	var root := world.find_child("BiomePopulations", true, false)
	if root == null:
		push_error("player_test: geology has no BiomePopulations")
		return
	var fields: Array[GroundCover] = []
	for field_name in [
			"PlanetGeology", "BoulderGeology", "CrystalGeology",
			"RuneGeology", "GiantBoulderSites",
		]:
		var field := root.find_child(field_name, true, false) as GroundCover
		if field == null:
			push_error("player_test: missing geology field %s" % field_name)
			return
		fields.append(field)
	_biome_paint_contract(fields)
	var cast_contract := {
		"CrystalGeology": Vector2(100.0, 8.0),
		"RuneGeology": Vector2(80.0, 7.0),
		"GiantBoulderSites": Vector2(300.0, 15.0),
	}
	for field: GroundCover in fields:
		if not cast_contract.has(field.name):
			continue
		var minimum: Vector2 = cast_contract[field.name]
		if field.glow_light_range < minimum.x \
				or field.glow_light_energy < minimum.y:
			push_error(
				"player_test: %s cast light is still too small (%.0f m, %.1f)"
				% [field.name, field.glow_light_range,
					field.glow_light_energy])
			return

	var plants := {}
	for field in fields:
		for plant: PlantSpecies in field.species:
			if plant != null:
				plants[plant.resource_name] = plant
	var expected := [
		"RoundedBoulder", "LayeredBoulder", "ColossalBoulderSite",
		"HexLavaFormation", "BasaltCitadel", "EmeraldCrystalCluster",
		"AmethystCrystalCluster", "SkyCrystalSpire",
		"RuneMonolithSite", "TattooRuneBoulder",
	]
	for plant_name in expected:
		if not plants.has(plant_name):
			push_error("player_test: geology is missing %s" % plant_name)
			return
		var painted := plants[plant_name] as PlantSpecies
		painted.prepare()
		var collision := painted.mesh_collision_shape()
		if collision == null:
			push_error("player_test: %s has no mesh-derived collision"
				% plant_name)
			return
		if painted.collision_primitive \
				== PlantSpecies.CollisionPrimitive.CONVEX_HULL \
				and not collision is ConvexPolygonShape3D:
			push_error("player_test: %s did not build a convex rock hull"
				% plant_name)
			return
		if painted.collision_primitive \
				== PlantSpecies.CollisionPrimitive.TRIMESH \
				and not collision is ConcavePolygonShape3D:
			push_error("player_test: %s did not build exact formation collision"
				% plant_name)
			return
		var painted_image := painted.paint_texture.get_image() \
			if painted.paint_texture != null else null
		if painted_image == null or not painted_image.has_mipmaps():
			push_error("player_test: %s paint has no imported mip chain"
				% plant_name)
			return

	var lowest_rock_threshold := INF
	var highest_rock_threshold := 0.0
	for plant_name in [
			"WeatheredRock", "BasaltOutcrop", "GlacierShard",
			"RoundedBoulder", "LayeredBoulder",
			"HexLavaFormation", "EmeraldCrystalCluster",
			"AmethystCrystalCluster", "TattooRuneBoulder",
		]:
		var rock := plants[plant_name] as PlantSpecies
		var threshold := rock.impact_threshold(rock.height)
		lowest_rock_threshold = minf(lowest_rock_threshold, threshold)
		highest_rock_threshold = maxf(highest_rock_threshold, threshold)
		if rock.impact_mode != PlantSpecies.ImpactMode.BREAKABLE \
				or rock.break_effect != PlantSpecies.BreakEffect.CRYSTAL:
			push_error("player_test: %s is not a breakable shard impact"
				% plant_name)
			return
		if threshold > 24.0:
			push_error("player_test: %s still needs %.1f m/s to break"
				% [plant_name, threshold])
			return

	var luminous := [
		"EmeraldCrystalCluster", "AmethystCrystalCluster",
		"SkyCrystalSpire", "RuneMonolithSite", "TattooRuneBoulder",
	]
	for plant_name in luminous:
		var plant := plants[plant_name] as PlantSpecies
		plant.prepare()
		var runtime := plant.near_material()
		if runtime == null or not bool(runtime.get_shader_parameter(
				&"emission_from_paint_alpha")):
			push_error("player_test: %s does not use its PNG emission mask"
				% plant_name)
			return
		var image := plant.paint_texture.get_image() \
			if plant.paint_texture != null else null
		if image == null:
			push_error("player_test: %s paint cannot be read" % plant_name)
			return
		var darkest := 1.0
		var brightest := 0.0
		for y in range(0, image.get_height(), 4):
			for x in range(0, image.get_width(), 4):
				var alpha := image.get_pixel(x, y).a
				darkest = minf(darkest, alpha)
				brightest = maxf(brightest, alpha)
		if darkest > 0.08 or brightest < 0.82:
			push_error(
				"player_test: %s PNG alpha is not a selective emission mask"
				% plant_name)
			return
	var strong_sources := {
		"EmeraldCrystalCluster": 1.8,
		"AmethystCrystalCluster": 2.0,
		"TattooRuneBoulder": 1.8,
		"SkyCrystalSpire": 2.7,
		"RuneMonolithSite": 2.5,
	}
	for plant_name in strong_sources:
		if (plants[plant_name] as PlantSpecies).local_light_energy \
				< float(strong_sources[plant_name]):
			push_error("player_test: %s still has weak cast-light energy"
				% plant_name)
			return

	const MAX_ROCK_HEIGHT := 5.0
	for plant_name in [
			"WeatheredRock", "BasaltOutcrop", "RoundedBoulder",
			"LayeredBoulder", "HexLavaFormation", "TattooRuneBoulder",
			"ColossalBoulderSite", "BasaltCitadel",
		]:
		var rock := plants[plant_name] as PlantSpecies
		var tallest := rock.height * (1.0 + rock.height_variation)
		if tallest > MAX_ROCK_HEIGHT:
			push_error("player_test: %s can still grow into a %.1f m giant"
				% [plant_name, tallest])
			return
	if (plants["RoundedBoulder"] as PlantSpecies).ground_sink < 0.6:
		push_error("player_test: round boulders are not embedded in the ground")
		return

	for plant_name in plants:
		var geology := plants[plant_name] as PlantSpecies
		if plant_name == "GlacierShard":
			if geology.ground_layer != PlantSpecies.Ground.ICE \
					or geology.minimum_frost <= 0.0:
				push_error("player_test: glacier shards are not ice-only")
				return
		elif geology.maximum_frost > 0.0:
			push_error("player_test: north-pole snow still admits %s"
				% plant_name)
			return

	for plant_name in ["SkyCrystalSpire", "RuneMonolithSite"]:
		var plant := plants[plant_name] as PlantSpecies
		if plant.height < 90.0 or plant.clump_count < 3 \
				or not plant.clump_resurvey or not plant.collision_enabled \
				or plant.impact_mode != PlantSpecies.ImpactMode.UNBREAKABLE:
			push_error("player_test: %s is not a clustered colliding landmark"
				% plant_name)
			return

	# Let the five geology rings catch up at the colony's starting biome. Their
	# own keep-back radii leave the ship clear while still loading sites beyond.
	var landing_direction := _planet.to_local(_ground.origin).normalized()
	_stand_on(landing_direction)
	await _wait(300)
	var patience := 0
	while patience < 2400:
		var waiting := 0
		for field in fields:
			waiting += field.settling()
		if waiting == 0:
			break
		await _wait(10)
		patience += 10
	print("player_test: geology settled in %.1fs" % (patience / 60.0))
	for field in fields:
		print("player_test: geology  %-18s %5d  %s" % [
			field.name, field.grown(), field.grown_by_species()])

	var boulders := fields[1]
	var crystals := fields[2]
	var runes := fields[3]
	var giants := fields[4]
	var round_stands: Array = boulders.standing_by_species().get(
		"RoundedBoulder", [])
	var giant_by_species := giants.standing_by_species()
	var landmark_stands: Array = giant_by_species.get("RuneMonolithSite", [])
	var landmark_height := 105.0
	if landmark_stands.is_empty():
		landmark_stands = giant_by_species.get("SkyCrystalSpire", [])
		landmark_height = 190.0
	var crystal_stands := crystals.standing()
	var rune_stands := runes.standing()
	var giant_stands := giants.standing()
	if round_stands.is_empty():
		push_error("player_test: no rounded boulder grew in starting region")
		return
	if crystal_stands.is_empty():
		push_error("player_test: no runtime crystal grew in starting region")
		return
	if rune_stands.is_empty():
		push_error("player_test: no runtime rune boulder grew in starting region")
		return
	if giant_stands.is_empty():
		push_error("player_test: no large geology site grew within draw range")
		return
	if landmark_stands.is_empty():
		push_error("player_test: no luminous geology landmark grew in range")
		return

	if _player.hud != null:
		_player.hud.visible = false
	if _player.character != null:
		_player.character.visible = false
	_player.controls_enabled = false
	var round_target: Vector3 = (round_stands[0] as Transform3D).origin
	_geology_camera(round_target, 3.4, 10.0)
	await _wait(180)
	await _shot("geology_round_boulder_close")

	var crystal_target: Vector3 = crystal_stands[0].origin
	_geology_camera(crystal_target, 18.0, 42.0)
	await _wait(240)
	var colliders := crystals.find_children(
		"*Collision", "StaticBody3D", true, false)
	if colliders.is_empty():
		push_error("player_test: nearby crystal has no streamed collision")
		return
	var cast_lights := 0
	var crystal_range := 0.0
	var crystal_energy := 0.0
	for light in crystals.find_children("*", "OmniLight3D", true, false):
		var omni := light as OmniLight3D
		if omni.visible and omni.light_energy > 0.01:
			cast_lights += 1
			crystal_range = maxf(crystal_range, omni.omni_range)
			crystal_energy = maxf(crystal_energy, omni.light_energy)
	if cast_lights == 0:
		push_error("player_test: day-glowing crystals cast no local light")
		return
	if crystal_range < 100.0 or crystal_energy < 12.0:
		push_error("player_test: crystal cast light is not broad and strong")
		return
	await _shot("geology_crystal_close_day")

	var giant_target: Vector3 = giant_stands[0].origin
	var site_members := 0
	for candidate_value in giant_stands:
		var candidate: Transform3D = candidate_value
		var neighbours := 0
		for other_value in giant_stands:
			var other: Transform3D = other_value
			if candidate.origin.distance_to(other.origin) < 520.0:
				neighbours += 1
		if neighbours > site_members:
			site_members = neighbours
			giant_target = candidate.origin
	print("player_test: geology densest visible landmark site has %d members"
		% site_members)
	_geology_camera(giant_target, 180.0, 760.0)
	await _wait(300)
	await _shot("geology_giant_gameplay_distance")
	var began := Time.get_ticks_usec()
	var slowest := 0.0
	var previous := began
	for _frame_index in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		slowest = maxf(slowest, float(now - previous) / 1000.0)
		previous = now
	var elapsed := float(Time.get_ticks_usec() - began) / 1000.0
	print("player_test: geology frame mean=%.2f ms worst=%.2f ms  fps=%.0f" % [
		elapsed / 120.0, slowest, 120000.0 / elapsed])

	var cycle := world.find_child(
		"CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if cycle != null:
		cycle.set_process(false)
	var rune_target: Vector3 = rune_stands[0].origin
	# Hidden sunlight does not change the `sun_direction` global that materials
	# use to decide local night. Rotate the real cycle until this rune's radial
	# is deepest behind the planet, then leave the directional light active so
	# both the mesh and pooled-light night laws see the same answer.
	if cycle != null and sun != null:
		var rune_up := (rune_target - _planet.global_position).normalized()
		var darkest_phase := 0.0
		var darkest_dot := INF
		for phase_index in 16:
			var phase := float(phase_index) / 16.0
			cycle.set_phase(phase)
			var daylight := rune_up.dot(sun.global_basis.z.normalized())
			if daylight < darkest_dot:
				darkest_dot = daylight
				darkest_phase = phase
		cycle.set_phase(darkest_phase)
	var environment := world.find_child(
		"WorldEnvironment", true, false) as WorldEnvironment
	if environment != null and environment.environment != null:
		environment.environment.ambient_light_energy = 0.07
	_geology_camera(rune_target, 10.0, 30.0)
	await _wait(240)
	var rune_lights := 0
	var rune_range := 0.0
	var rune_energy := 0.0
	for light in runes.find_children("*", "OmniLight3D", true, false):
		var omni := light as OmniLight3D
		if omni.visible and omni.light_energy > 0.01:
			rune_lights += 1
			rune_range = maxf(rune_range, omni.omni_range)
			rune_energy = maxf(rune_energy, omni.light_energy)
	if rune_lights == 0:
		push_error("player_test: night rune boulders cast no local light")
		return
	if rune_range < 80.0 or rune_energy < 10.0:
		push_error("player_test: rune-boulder cast light is not broad and strong")
		return
	await _shot("geology_rune_close_night")

	var landmark_target: Vector3 = (
		landmark_stands[0] as Transform3D).origin
	_geology_camera(landmark_target, landmark_height, 240.0)
	await _wait(300)
	var landmark_lights := 0
	var landmark_range := 0.0
	var landmark_energy := 0.0
	for light in giants.find_children("*", "OmniLight3D", true, false):
		var omni := light as OmniLight3D
		if omni.visible and omni.light_energy > 0.01:
			landmark_lights += 1
			landmark_range = maxf(landmark_range, omni.omni_range)
			landmark_energy = maxf(landmark_energy, omni.light_energy)
	if landmark_lights == 0 or landmark_range < 300.0 \
			or landmark_energy < 30.0:
		push_error("player_test: luminous landmark does not flood nearby terrain")
		return
	await _shot("geology_landmark_light_night")
	print(
		"player_test: geology 9 breakable pieces at %.1f..%.1f m/s, "
		% [lowest_rock_threshold, highest_rock_threshold]
		+ "PNG alpha emission, capped rocks, clustered landmarks, "
		+ "%d crystal, %d rune, and %d landmark lights"
			% [cast_lights, rune_lights, landmark_lights])


func _geology_camera(target: Vector3, visual_height: float, away: float) -> void:
	var centre := _planet.global_position
	var up := (target - centre).normalized()
	var side := up.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var origin := target + side * away + up * maxf(visual_height * 0.42, 3.0)
	var focus := target + up * visual_height * 0.38
	_player._apply_stance(FLY)
	_player.global_transform = Transform3D(
		Basis.looking_at(focus - origin, up), origin)
	_player.head.rotation = Vector3.ZERO
	_player._pitch = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Representative loaded counts and frames for the planet-wide population
## catalogue. This checks the habitat split rather than one convenient meadow:
## reef, temperate grass, arid sand, mountain stone and polar ice each get a
## cold move followed by a full streaming settle.
func _biome_population_checks() -> void:
	var world := _planet.get_parent()
	var root := world.find_child("BiomePopulations", true, false)
	if root == null:
		push_error("player_test: biome population scene is missing")
		return
	var fields: Array[GroundCover] = []
	for field_name in [
			"OceanPlants", "TemperateFlora", "ForestGiants",
			"SkywoodGroves", "GiantOrbClearings", "CorkscrewSavanna",
			"PlanetGeology", "BoulderGeology", "CrystalGeology",
			"RuneGeology", "GiantBoulderSites", "DesertFlora",
		]:
		var field := root.find_child(field_name, true, false) as GroundCover
		if field == null:
			push_error("player_test: missing biome field %s" % field_name)
			return
		fields.append(field)
	_biome_paint_contract(fields)
	var classifier := world.find_child("GlobalGrass", true, false) as GroundCover
	if classifier == null:
		push_error("player_test: biome check needs the terrain classifier")
		return
	var atlas := root as GlobalFloraGlow
	if atlas != null:
		for _frame in 1800:
			if atlas.ready_for_orbit():
				break
			await get_tree().process_frame
		print("player_test: biomes  global glow %s from %d luminous species" % [
			"ready" if atlas.ready_for_orbit() else "timed out",
			atlas.luminous_species_count()])

	var sites := [
		{"name": "reef", "at": _reef_direction()},
		{"name": "temperate", "at": _biome_direction(classifier,
			PlantSpecies.Ground.GRASS, 0.0, 0.4, 0.0, 0.32,
			12.0, 210.0, 61701)},
		{"name": "skywood", "at": _biome_direction(classifier,
			PlantSpecies.Ground.GRASS, 0.0, 0.34, 0.08, 0.58,
			24.0, 400.0, 61705)},
		{"name": "giant clearing", "at": _biome_direction(classifier,
			PlantSpecies.Ground.GRASS, 0.0, 0.5, 0.0, 0.48,
			18.0, 450.0, 61706)},
		{"name": "desert", "at": _biome_direction(classifier,
			PlantSpecies.Ground.SAND, 0.62, 1.0, 0.0, 0.16,
			25.0, 380.0, 61702)},
		{"name": "stone", "at": _biome_direction(classifier,
			PlantSpecies.Ground.STONE, 0.0, 1.0, 0.0, 0.5,
			70.0, 460.0, 61703)},
		{"name": "ice", "at": _biome_direction(classifier,
			PlantSpecies.Ground.ICE, 0.0, 1.0, 0.68, 1.0,
			2.0, 500.0, 61704)},
	]
	if _player.hud != null:
		_player.hud.visible = false
	for site in sites:
		var direction: Vector3 = site["at"]
		if direction == Vector3.ZERO:
			push_error("player_test: found no %s population site" % site["name"])
			continue
		_stand_on(direction)
		await _wait(300)
		var patience := 0
		while patience < 1800:
			var waiting := 0
			for field in fields:
				waiting += field.settling()
			if waiting == 0:
				break
			await _wait(10)
			patience += 10
		print("player_test: biomes  %s settled after %.1fs" % [
			site["name"], patience / 60.0])
		for field in fields:
			var report := field.grown_by_species()
			var total := 0
			for count in report.values():
				total += int(count)
			if site["name"] == "ice" and field.name in [
					"PlanetGeology", "BoulderGeology", "CrystalGeology",
					"RuneGeology", "GiantBoulderSites",
					]:
				var positioned := field.standing_by_species()
				for plant: PlantSpecies in field.species:
					if plant.resource_name == "GlacierShard":
						continue
					for stood: Transform3D in positioned.get(
							plant.resource_name, []):
						var local_direction := _planet.to_local(
							stood.origin).normalized()
						if _planet.shape.frost(local_direction) <= 0.0001:
							continue
						push_error(
							"player_test: polar snow grew non-ice geology %s"
							% plant.resource_name)
						break
			if total > 0:
				print("player_test: biomes    %-16s %5d  %s" % [
					field.name, total, report])
			# Only species missing from a field which did grow here. A field
			# whose whole habitat is elsewhere is not a fault, and reporting
			# every one of its species at every site buries the real gaps.
			if total == 0:
				continue
			for plant in field.species:
				if int(report.get(plant.resource_name, 0)) > 0:
					continue
				print("player_test: biomes    %-16s %-22s %s" % [
					field.name, plant.resource_name,
					_habitat_probe(field, plant, direction, 150.0, 600)])
		_look(-0.18)
		await _wait(20)
		# What the biome costs to stand in. A population that only reads well in
		# a screenshot is not finished, and these fields are the first thing on
		# the planet that puts several thousand props in view at once.
		# Wall clock, not Performance.TIME_PROCESS. That monitor counts script
		# time across every _process in the tree and reads far higher than the
		# frame actually takes — it claimed 94 ms in a desert running at 126
		# frames a second, which is worse than useless in a report about cost.
		var slowest := 0.0
		var began := Time.get_ticks_usec()
		var previous := began
		for _tick in 120:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			slowest = maxf(slowest, float(now - previous) / 1000.0)
			previous = now
		var elapsed := float(Time.get_ticks_usec() - began) / 1000.0
		print("player_test: biomes    %-16s frame mean=%.2f ms worst=%.2f ms  fps=%.0f" % [
			"cost", elapsed / 120.0, slowest, 120000.0 / elapsed])
		await _shot("biome_%s" % site["name"])


## Navigation is a deliberate overlay: absent at spawn, complete on tilde, and
## still complete when the camera moves to the antipode of its starting place.
func _waypoint_toggle_checks() -> void:
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	if layer == null:
		push_error("player_test: waypoint layer is missing")
		return
	var expected := PackedStringArray([
		"Arctic Ring Site",
		"Bigfoot",
		"Vacationer's Landing",
		"North Pole",
		"Other Side",
		"Ring Site I",
		"Ring Site II",
		"Ring Site III",
		"South Pole Caldera",
	])
	expected.sort()

	var bound_to_tilde := false
	for binding in InputMap.action_get_events(&"waypoints"):
		var key := binding as InputEventKey
		if key != null and int(key.physical_keycode) == 96:
			bound_to_tilde = true
	if not bound_to_tilde:
		push_error("player_test: waypoint overlay is not bound to tilde")

	await _wait(3)
	if layer.enabled or layer.visible or not layer.drawn(0.0).is_empty():
		push_error("player_test: a waypoint was visible before tilde")

	var toggle := InputEventKey.new()
	toggle.physical_keycode = 96 as Key
	toggle.pressed = true
	_player._unhandled_input(toggle)
	await _wait(3)
	var opened := layer.drawn()
	opened.sort()
	print("player_test: waypoints opened=%s" % [opened])
	if not layer.enabled or not layer.visible or opened != expected:
		push_error("player_test: tilde did not open the selected waypoint set")

	var other_side := _planet.find_child("OtherSide", false, false) as Landmark
	if other_side == null:
		push_error("player_test: Other Side landmark is missing")
	else:
		_player.controls_enabled = false
		_player.global_position = other_side.global_position \
			+ other_side.global_basis.y * 20.0
		_player._align_to_planet(1.0)
		await _wait(3)
		var antipode := layer.drawn()
		antipode.sort()
		print("player_test: waypoints antipode=%s" % [antipode])
		if antipode != expected:
			push_error("player_test: waypoints were hidden by distance or planet")
		_player.controls_enabled = true

	_player._unhandled_input(toggle)
	await _wait(3)
	if layer.enabled or layer.visible or not layer.drawn(0.0).is_empty():
		push_error("player_test: second tilde did not close waypoints")
	print("player_test: waypoints closed with no colony auto-marker")


## The south-pole terrain, liquid meshes and movement guard all read the same
## authored dimensions. This catches the expensive failure modes: a visual pool
## over uncarved ground, a native field that did not receive the new settings,
## or a body that can fall through the analytical surface into the basin.
func _volcano_checks() -> void:
	var volcano := _planet.find_child(
		"SouthPoleVolcano", false, false) as Node3D
	if volcano == null:
		push_error("player_test: SouthPoleVolcano is missing")
		return
	var shape := _planet.shape
	var south := shape.volcano_axis()
	var centre_height := shape.elevation(south, 0.0)
	var parts := shape.sample(south)
	var quiet_angle := shape.volcano_flow_angles.x + 0.72
	var rim_offset := Vector2(cos(quiet_angle), sin(quiet_angle)) \
		* shape.volcano_crater_radius
	var rim_direction: Vector3 = volcano.call("_direction_at", rim_offset)
	var rim_height := shape.elevation(rim_direction, 0.0)
	var island_direction: Vector3 = volcano.call(
		"_direction_at", Vector2(shape.volcano_radius * 0.82, 0.0))
	var island_height := shape.elevation(island_direction, 0.0)
	var steepest_climb := 0.0
	var steepest_at := 0.0
	var climb_inner := shape.volcano_crater_radius * 0.62
	var climb_outer := shape.volcano_crater_radius * 1.03
	for sample in 129:
		var distance := lerpf(climb_inner, climb_outer, float(sample) / 128.0)
		var offset := Vector2(cos(quiet_angle), sin(quiet_angle)) * distance
		var direction: Vector3 = volcano.call("_direction_at", offset)
		var normal := shape.normal_at(direction, _planet.finest_spacing())
		var slope := rad_to_deg(normal.angle_to(direction))
		if slope > steepest_climb:
			steepest_climb = slope
			steepest_at = distance
	print("player_test: volcano terrain centre=%.1f rim=%.1f island=%.1f "
		% [centre_height, rim_height, island_height]
		+ "weight=%.3f" % float(parts.get("volcano", -1.0)))
	print("player_test: volcano climb steepest=%.1f deg at %.0f m, walk limit=%.1f deg"
		% [steepest_climb, steepest_at, rad_to_deg(_player.floor_max_angle)])
	if centre_height < shape.volcano_crater_lava_height - 20.0 \
			or centre_height >= shape.volcano_crater_lava_height:
		push_error("player_test: volcano crater floor does not sit below its lava")
	if rim_height < shape.volcano_crater_lava_height + 70.0:
		push_error("player_test: volcano has no raised crater rim")
	if island_height < 25.0:
		push_error("player_test: volcano island did not replace south-pole sea")
	if float(parts.get("volcano", -1.0)) < 0.99:
		push_error("player_test: native height field did not identify the volcano")
	if steepest_climb > rad_to_deg(_player.floor_max_angle) + 0.25:
		push_error("player_test: caldera wall is too steep to run up (%.1f > %.1f deg)"
			% [steepest_climb, rad_to_deg(_player.floor_max_angle)])

	var liquid_meshes := 0
	var pool_meshes := {}
	for child in volcano.get_children(true):
		var liquid := child as MeshInstance3D
		if liquid == null:
			continue
		liquid_meshes += 1
		if liquid.name == &"CraterLake" or liquid.name.begins_with("LowerPool"):
			pool_meshes[liquid.name] = liquid
	if liquid_meshes != 7:
		push_error("player_test: volcano has %d of 7 lava meshes" % liquid_meshes)

	var pools := shape.volcano_lava_pools()
	for index in pools.size():
		var pool: Dictionary = pools[index]
		var pool_name := &"CraterLake" if index == 0 \
			else StringName("LowerPool%d" % index)
		var pool_mesh := pool_meshes.get(pool_name) as MeshInstance3D
		if pool_mesh == null:
			push_error("player_test: lava pool %d has no visible mesh" % index)
		else:
			var lowest := INF
			for surface_index in pool_mesh.mesh.get_surface_count():
				var arrays := pool_mesh.mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					lowest = minf(lowest, vertex.length() - shape.radius)
			if lowest > float(pool["height"]) - shape.volcano_pool_depth - 1.0:
				push_error("player_test: lava pool %d has no buried edge skirt"
					% index)
		var point: Vector3 = volcano.call(
			"_point_at", pool["offset"], float(pool["height"]) - 0.25)
		var query: Dictionary = volcano.call(
			"lava_sample", volcano.to_global(point))
		if query.is_empty() or absf(float(query["depth"]) - 0.25) > 0.02:
			push_error("player_test: lava pool %d has no matching query" % index)
		var direction: Vector3 = volcano.call("_direction_at", pool["offset"])
		var floor_height := shape.elevation(direction, 0.0)
		var expected_floor := float(pool["height"]) - shape.volcano_pool_depth
		if absf(floor_height - expected_floor) > 0.2:
			push_error("player_test: lava pool %d floor is %.2f, expected %.2f"
				% [index, floor_height, expected_floor])
		# A thin disc over a flat-bottomed basin can pass every centre-height
		# check and still be visibly hollow from walking height. The terrain has
		# to rise to the *irregular* mesh edge in every direction.
		for spoke in 16:
			var angle := TAU * float(spoke) / 16.0
			var edge: float = volcano.call("_pool_radius",
				float(pool["radius"]), angle, int(pool["seed"]))
			var shore_offset: Vector2 = (pool["offset"] as Vector2) \
				+ Vector2(cos(angle), sin(angle)) * edge
			var shore_direction: Vector3 = volcano.call(
				"_direction_at", shore_offset)
			var shore_height := shape.elevation(shore_direction, 0.0)
			var expected_shore := float(pool["height"]) \
				- shape.volcano_pool_shore_overlap
			if absf(shore_height - expected_shore) > 0.35:
				push_error(
					"player_test: lava pool %d has a %.2f m gap at spoke %d"
					% [index, expected_shore - shore_height, spoke])

	var crater: Dictionary = pools[0]
	var surface_local: Vector3 = volcano.call(
		"_point_at", crater["offset"], float(crater["height"]))
	var surface_world: Vector3 = volcano.to_global(surface_local)
	var up := _planet.up_at(surface_world)
	_player.controls_enabled = false
	_player.global_position = surface_world - up * 3.0
	_player._align_to_planet(1.0)
	_player._apply_stance(STAND)
	_player._on_lava = false
	_player._lava_state = {}
	_player.velocity = -up * 24.0
	var caught := _player._catch_ground()
	var caught_local := _planet.to_local(_player.global_position)
	var expected_radius := shape.radius + float(crater["height"]) \
		- float(volcano.get("surface_sink"))
	var radial_speed := absf(_player.velocity.dot(up))
	print("player_test: volcano lava caught=%s stance=%d radius=%.2f/%.2f "
		% [caught, _player._stance, caught_local.length(), expected_radius]
		+ "radial_speed=%.3f speed=%.2f meshes=%d" % [
			radial_speed, _player.velocity.length(), liquid_meshes])
	if not caught or _player._stance != SWIM:
		push_error("player_test: lava impact did not enter surface swim")
	if absf(caught_local.length() - expected_radius) > 0.03:
		push_error("player_test: lava allowed the body below its surface")
	if radial_speed > 0.01:
		push_error("player_test: lava retained inward velocity")
	if _player.velocity.length() > 24.0 * _player.lava_entry_keep + 0.05:
		push_error("player_test: lava did not apply viscous entry loss")

	_player.controls_enabled = true
	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("crouch")
	await _wait(90)
	Input.action_release("crouch")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var stroke_query: Dictionary = volcano.call(
		"lava_sample", _player.global_position)
	var stroke_speed := _player.velocity.length()
	print("player_test: volcano lava stroke stance=%d depth=%.2f speed=%.2f" % [
		_player._stance, float(stroke_query.get("depth", -1.0)), stroke_speed])
	if stroke_query.is_empty() or _player._stance != SWIM:
		push_error("player_test: lava stroke left the analytical surface")
	if absf(float(stroke_query.get("depth", -1.0))
			- float(volcano.get("surface_sink"))) > 0.04:
		push_error("player_test: crouch allowed a lava dive")
	if stroke_speed > _player.lava_sprint_speed + 0.1:
		push_error("player_test: viscous lava exceeded its sprint cap")
	_player.controls_enabled = false

	var review := Camera3D.new()
	_planet.get_parent().add_child(review)
	var view_angle := shape.volcano_flow_angles.x + PI
	var view_offset := Vector2(cos(view_angle), sin(view_angle)) * 1220.0
	var view_direction: Vector3 = volcano.call("_direction_at", view_offset)
	review.global_position = _planet.to_global(
		view_direction * (shape.radius + shape.volcano_island_height + 650.0))
	review.fov = 54.0
	review.look_at(surface_world, _planet.up_at(review.global_position))
	review.current = true
	await _wait(180)
	await _shot("volcano_overview")
	await _volcano_pool_shots(volcano, pools, review)
	review.queue_free()


## Gives every lava shoreline a close oblique view. The overview proves the
## volcano reads from the air, but it cannot show whether the liquid and bank
## actually meet. The spoke checks above are the walking-height regression; the
## raised camera here keeps the bank itself from hiding that seam in the review
## image.
func _volcano_pool_shots(volcano: Node3D, pools: Array[Dictionary],
		review: Camera3D) -> void:
	for index in pools.size():
		var pool: Dictionary = pools[index]
		var centre: Vector2 = pool["offset"]
		var angle := centre.angle() if centre.length_squared() > 0.01 else 0.0
		var facing := Vector2(cos(angle), sin(angle))
		var edge: float = volcano.call(
			"_pool_radius", float(pool["radius"]), angle, int(pool["seed"]))
		var camera_offset := centre + facing * (
			edge + _planet.shape.volcano_pool_shore_width + 6.0)
		var camera_direction: Vector3 = volcano.call(
			"_direction_at", camera_offset)
		var ground := _planet.shape.elevation(camera_direction, 0.0)
		var surface := float(pool["height"])
		review.global_position = _planet.to_global(
			camera_direction * (
				_planet.shape.radius + maxf(ground, surface) + 14.0))
		var target: Vector3 = volcano.call(
			"_point_at", centre, surface)
		review.look_at(volcano.to_global(target),
			_planet.up_at(review.global_position))
		await _wait(20)
		await _shot("volcano_pool_%d_edge" % index)


## The two viewer-centred aerial fields must populate the 40..100 m layer only
## at local night. Instance lifetime remains a shader concern; this checks the
## deterministic spatial envelope and the CPU-side twilight submission gate.
func _night_phenomena_checks() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child(
		"CelestialCycle", true, false) as CelestialCycle
	var sparkles := world.find_child(
		"NightSparkles", true, false) as AerialSwarm
	var wisps := world.find_child(
		"NightWisps", true, false) as AerialSwarm
	if cycle == null or sparkles == null or wisps == null:
		push_error("player_test: night sparkle or wisp field is missing")
		return

	await _place(CLEAR, 0.0)
	cycle.period_seconds = 0.0
	cycle.set_phase(0.5)
	await _wait(180)
	for swarm: AerialSwarm in [sparkles, wisps]:
		var altitude := _phenomenon_altitude_bounds(swarm)
		var report := swarm.statistics()
		print("player_test: night phenomena %-14s count=%d visible=%d "
			% [swarm.name, int(report["swarm"]),
				int(report["visible_insects"])]
			+ "clusters=%d altitude=%.1f..%.1f m uploads=%d" % [
				int(report["clusters"]), altitude.x, altitude.y,
				int(report["buffer_uploads"])])
		if int(report["swarm"]) != swarm.instance_count \
				or int(report["visible_insects"]) == 0:
			push_error("player_test: %s did not stream at night" % swarm.name)
		if altitude.x < 39.8 or altitude.y > 100.2 \
				or altitude.x > altitude.y:
			push_error("player_test: %s escaped the 40..100 m layer" % swarm.name)

	cycle.set_phase(0.0)
	await _wait(120)
	if sparkles.active_cluster_count() != 0 \
			or wisps.active_cluster_count() != 0:
		push_error("player_test: aerial night phenomena remained submitted by day")
	print("player_test: night phenomena daylight hides both fields")


func _phenomenon_altitude_bounds(swarm: AerialSwarm) -> Vector2:
	var low := INF
	var high := -INF
	var clusters: Array = swarm.get("_clusters")
	for cluster: Dictionary in clusters:
		if not bool(cluster["uploaded"]):
			continue
		var multimesh := cluster["multimesh"] as MultiMesh
		var buffer := multimesh.buffer
		for index in multimesh.instance_count:
			var at := index * 20
			var local_point := Vector3(
				buffer[at + 3], buffer[at + 7], buffer[at + 11])
			var planet_point := _planet.to_local(swarm.to_global(local_point))
			var direction := planet_point.normalized()
			var surface_radius := _planet.shape.radius \
				+ _planet.shape.elevation(direction, _planet.finest_spacing())
			var altitude := planet_point.length() - surface_radius
			low = minf(low, altitude)
			high = maxf(high, altitude)
	return Vector2(low, high)


## End-to-end policy and storage checks for impact-breakable MultiMesh flora.
## The synthetic wall proves KinematicCollision3D resolves the tagged shape;
## the mushroom then proves a real streamed instance disappears, bounces with
## preserved tangential speed, and stays gone through tile retirement.
func _flora_impact_checks() -> void:
	var world := _planet.get_parent()
	var effects := world.find_child(
		"ImpactBreakEffects", true, false) as ImpactBreakEffects
	var root := world.find_child("BiomePopulations", true, false)
	var classifier := world.find_child(
		"GlobalGrass", true, false) as GroundCover
	var field := root.find_child(
		"TemperateFlora", true, false) as GroundCover if root != null else null
	if effects == null or field == null or classifier == null:
		push_error("player_test: impact system is missing effects or biome fields")
		return

	var tiny_mushroom := load(
		"res://game/props/biomes/mushroom_cluster.tres") as PlantSpecies
	var mushroom := load(
		"res://game/props/biomes/mushroom_lantern.tres") as PlantSpecies
	var giant_mushroom := load(
		"res://game/props/biomes/mushroom_giant.tres") as PlantSpecies
	var canopy := load(
		"res://game/props/biomes/tree_canopy.tres") as PlantSpecies
	var ancient := load(
		"res://game/props/biomes/tree_orb_giant.tres") as PlantSpecies
	if tiny_mushroom == null or mushroom == null or giant_mushroom == null \
			or canopy == null or ancient == null:
		push_error("player_test: impact species resources did not load")
		return
	if tiny_mushroom.impact_mode != PlantSpecies.ImpactMode.BREAKABLE \
			or mushroom.impact_mode != PlantSpecies.ImpactMode.MUSHROOM_BOUNCE \
			or giant_mushroom.impact_mode \
				!= PlantSpecies.ImpactMode.MUSHROOM_BOUNCE \
			or canopy.impact_mode != PlantSpecies.ImpactMode.BREAKABLE \
			or ancient.impact_mode != PlantSpecies.ImpactMode.UNBREAKABLE:
		push_error("player_test: size-aware mushroom impact policies disagree")
	if canopy.impact_threshold(18.0) <= canopy.impact_threshold(8.0):
		push_error("player_test: larger trees are not harder to break")
	if canopy.impact_threshold(8.0) > 22.0:
		push_error("player_test: ordinary collidable flora threshold stayed too high")
	print("player_test: impact policy  tiny breaks without launch; "
		+ "medium mushroom %.1f m/s -> %.1f m/s up; "
		% [mushroom.impact_threshold(mushroom.height),
			mushroom.bounce_speed(20.0)]
		+ "canopy 8 m %.1f, 18 m %.1f; ancient unbreakable" % [
			canopy.impact_threshold(8.0), canopy.impact_threshold(18.0)])

	await _impact_shape_plumbing(world)

	var direction := _biome_direction(classifier,
		PlantSpecies.Ground.GRASS, 0.0, 0.32, 0.0, 0.28,
		12.0, 170.0, 71031)
	if direction == Vector3.ZERO:
		push_error("player_test: found no temperate mushroom habitat")
		return
	_stand_on(direction)
	field._survey(_player.global_position)
	await _wait(300)
	var patience := 0
	while patience < 1800 and field.settling() > 0:
		await _wait(10)
		patience += 10
	var candidate := _loaded_impact_candidate(field, &"LanternMushroom")
	if candidate.is_empty():
		push_error("player_test: no streamed mushroom grew at impact site")
		return
	var stood: Transform3D = candidate["world"]
	var mushroom_direction := _planet.to_local(stood.origin).normalized()
	_stand_on(mushroom_direction)
	field._survey(_player.global_position)
	await _wait(120)
	# The first survey can still contain a tile retiring from the habitat probe.
	# Re-select from the settled ring at the mushroom itself before reading its
	# collision slot.
	var refreshed := _loaded_impact_candidate(field, &"LanternMushroom")
	if not refreshed.is_empty():
		candidate = refreshed
		stood = candidate["world"]
		mushroom_direction = _planet.to_local(stood.origin).normalized()
		_stand_on(mushroom_direction)
		field._survey(_player.global_position)
		await _wait(60)
	var collider := _loaded_impact_collider(field, candidate)
	if collider == null:
		var tiles: Dictionary = field.get("_tiles")
		var tile = tiles.get(candidate["cell"])
		var body: StaticBody3D
		var showing := -1
		var distance := INF
		if tile != null:
			var stands: Array = tile.get("stands")
			var collisions: Array = tile.get("collisions")
			var species_index := int(candidate["species"])
			if species_index < stands.size() and stands[species_index] != null:
				var stand := stands[species_index] as MultiMeshInstance3D
				showing = stand.multimesh.visible_instance_count
			if species_index < collisions.size():
				body = collisions[species_index] as StaticBody3D
			distance = _player.global_position.distance_to(
				tile.get("at"))
		print("player_test: mushroom collider diagnostic tile=%s showing=%d "
			% [tile != null, showing]
			+ "body=%s children=%d player-to-tile=%.2f" % [
				body != null, body.get_child_count() if body != null else -1,
				distance])
		push_error("player_test: mushroom did not stream its impact collider")
		return
	var visual_height := float(collider.get_meta(
		&"impact_break_height", mushroom.height))
	var threshold := mushroom.impact_threshold(visual_height)
	var low := field.resolve_flora_impact(
		collider, threshold - 0.1, collider.global_position)
	if not low.is_empty():
		push_error("player_test: sub-threshold mushroom impact broke it")
	var response := field.resolve_flora_impact(
		collider, threshold + 12.0, collider.global_position)
	if not bool(response.get("broken", false)) \
			or float(response.get("bounce_up", 0.0)) <= 0.0:
		push_error("player_test: mushroom did not break and return a launch")

	var source_forward := -_player.global_basis.z * 23.0
	_player.set_physics_process(false)
	var bounced := _player._apply_flora_response(source_forward, response)
	var kept := _player._flat(_player.velocity)
	var rise := _player.velocity.dot(_player._up())
	_player.set_physics_process(true)
	if not bounced or kept.distance_to(source_forward) > 0.01 \
			or absf(rise - float(response["bounce_up"])) > 0.01:
		push_error("player_test: mushroom launch lost forward or upward speed")

	var emitting := 0
	for child in effects.get_children(true):
		var burst := child as GPUParticles3D
		if burst != null and burst.emitting:
			emitting += 1
	if emitting == 0:
		push_error("player_test: flora break started no pooled particle burst")
	await get_tree().physics_frame
	if not collider.disabled:
		push_error("player_test: broken mushroom collider remained enabled")
	var broken_transform := _loaded_impact_transform(field, candidate)
	if broken_transform.basis.y.length_squared() > 0.000001:
		push_error("player_test: broken mushroom remained in its MultiMesh")
	print("player_test: impact mushroom  %.2f m tall, threshold %.1f, "
		% [visual_height, threshold]
		+ "launch %.1f up with %.1f forward, %d debris burst" % [
			rise, kept.length(), emitting])

	# Move beyond this field's whole reach so the source tile is retired, then
	# return to the exact plant direction and require the overlay to be applied
	# to the freshly generated MultiMesh.
	var east := mushroom_direction.cross(
		Vector3.UP if absf(mushroom_direction.y) < 0.9
		else Vector3.RIGHT).normalized()
	var away := (mushroom_direction
		+ east * (520.0 / _planet.shape.radius)).normalized()
	_stand_on(away)
	field._survey(_player.global_position)
	await _wait(360)
	var cell: Vector3i = candidate["cell"]
	var retired_tiles: Dictionary = field.get("_tiles")
	if retired_tiles.has(cell):
		push_error("player_test: source impact tile did not retire")
	_stand_on(mushroom_direction)
	field._survey(_player.global_position)
	await _wait(360)
	patience = 0
	while patience < 1800 and field.settling() > 0:
		await _wait(10)
		patience += 10
	var returned := _loaded_impact_transform(field, candidate)
	if returned.basis.y.length_squared() > 0.000001:
		push_error("player_test: destroyed mushroom regrew after tile streaming")
	if _loaded_impact_collider(field, candidate) != null:
		push_error("player_test: destroyed mushroom rebuilt its collider")
	print("player_test: impact persistence  streamed tile returned without plant or collider")
	await _flower_tree_impact_check(world)


func _flower_tree_impact_check(world: Node) -> void:
	var trees := world.find_child(
		"LandingFlowerTrees", true, false) as FlowerTreeField
	if trees == null:
		push_error("player_test: impact check found no flower-tree field")
		return
	var pairs: Array = trees.get("_tree_colliders")
	var roots: Array[Transform3D] = trees.get("_trees")
	var trunk := trees.get("_trunk_stand") as MultiMeshInstance3D
	var head := trees.get("_head_stand") as MultiMeshInstance3D
	if pairs.is_empty() or roots.is_empty() or trunk == null or head == null:
		push_error("player_test: flower-tree impact data is incomplete")
		return
	var collider := (pairs[0] as Array)[0] as CollisionShape3D
	var height := float(collider.get_meta(
		&"impact_break_height", trees.maximum_height))
	var threshold: float = trees.impact_threshold(height)
	if not trees.resolve_flora_impact(
			collider, threshold - 0.1, trees.to_global(roots[0].origin)).is_empty():
		push_error("player_test: sub-threshold flower tree broke")
	var response := trees.resolve_flora_impact(
		collider, threshold + 5.0, trees.to_global(roots[0].origin))
	if not bool(response.get("broken", false)) \
			or float(response.get("bounce_up", -1.0)) != 0.0:
		push_error("player_test: flower tree did not break as a non-bounce tree")
	await get_tree().physics_frame
	for shape: CollisionShape3D in pairs[0]:
		if not shape.disabled:
			push_error("player_test: flower tree left one collider enabled")
	if trees._tree_light_position(0).is_finite():
		push_error("player_test: destroyed flower tree still owned a night light")
	print("player_test: impact flower tree  %.1f m tree broke at %.1f m/s "
		% [height, threshold]
		+ "with trunk, crown, collision, and light removed")


## One real move_and_slide against a tagged synthetic shape protects the
## collider-shape lookup from engine/backend API drift.
func _impact_shape_plumbing(world: Node) -> void:
	await _place(CLEAR, 0.0)
	_player.set_physics_process(false)
	var stub := ImpactStub.new()
	add_child(stub)
	var body := StaticBody3D.new()
	body.name = "ImpactShapeProbe"
	body.collision_layer = 1
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.8, 0.35)
	collider.shape = shape
	collider.set_meta(&"impact_break_owner", stub)
	body.add_child(collider)
	(world as Node3D).add_child(body)
	var forward := -_player.global_basis.z
	body.global_transform = Transform3D(
		_player.global_basis,
		_player.global_position + forward * 0.82 + _player.global_basis.y * 0.7)
	await get_tree().physics_frame
	var carried := forward * 70.0
	_player.velocity = carried
	_player.floor_snap_length = 0.0
	_player.move_and_slide()
	var result := _player._resolve_flora_contacts(carried)
	var handled: Dictionary = result["handled"]
	if stub.calls != 1 or handled.is_empty():
		push_error("player_test: tagged slide collision did not reach impact owner")
	elif _player._hit_something_solid(carried, false, handled):
		push_error("player_test: handled flora contact still triggered a crash")
	else:
		print("player_test: impact plumbing  tagged CollisionShape3D resolved and skipped crash")
	body.queue_free()
	stub.queue_free()
	_player.set_physics_process(true)
	await get_tree().physics_frame


func _loaded_impact_candidate(field: GroundCover,
		resource_name: StringName) -> Dictionary:
	var species_index := -1
	for index in field.species.size():
		var plant := field.species[index] as PlantSpecies
		if plant != null and plant.resource_name == resource_name:
			species_index = index
			break
	if species_index < 0:
		return {}
	var tiles: Dictionary = field.get("_tiles")
	var nearest := INF
	var found: Dictionary = {}
	for cell_value in tiles:
		var tile = tiles[cell_value]
		var stands: Array = tile.get("stands")
		if species_index >= stands.size():
			continue
		var stand := stands[species_index] as MultiMeshInstance3D
		if stand == null or stand.multimesh.instance_count == 0:
			continue
		var buffer := stand.multimesh.buffer
		for instance_index in stand.multimesh.instance_count:
			var local_stood := field._instance_transform(
				buffer, instance_index)
			var world_stood := stand.global_transform \
				* local_stood
			var away := _player.global_position.distance_squared_to(
				world_stood.origin)
			if away >= nearest:
				continue
			nearest = away
			found = {
				"cell": cell_value,
				"species": species_index,
				"instance": instance_index,
				"world": world_stood,
			}
	return found


func _loaded_impact_transform(field: GroundCover,
		candidate: Dictionary) -> Transform3D:
	var tiles: Dictionary = field.get("_tiles")
	var cell: Vector3i = candidate["cell"]
	if not tiles.has(cell):
		return Transform3D.IDENTITY
	var tile = tiles[cell]
	var stands: Array = tile.get("stands")
	var species_index := int(candidate["species"])
	if species_index >= stands.size():
		return Transform3D.IDENTITY
	var stand := stands[species_index] as MultiMeshInstance3D
	var instance_index := int(candidate["instance"])
	if stand == null or instance_index >= stand.multimesh.instance_count:
		return Transform3D.IDENTITY
	return field._instance_transform(stand.multimesh.buffer, instance_index)


func _loaded_impact_collider(field: GroundCover,
		candidate: Dictionary) -> CollisionShape3D:
	var tiles: Dictionary = field.get("_tiles")
	var cell: Vector3i = candidate["cell"]
	if not tiles.has(cell):
		return null
	var tile = tiles[cell]
	var collisions: Array = tile.get("collisions")
	var species_index := int(candidate["species"])
	if species_index >= collisions.size():
		return null
	var body := collisions[species_index] as StaticBody3D
	if body == null:
		return null
	var instance_index := int(candidate["instance"])
	for child in body.get_children():
		var collider := child as CollisionShape3D
		if collider != null and int(collider.get_meta(
				&"impact_break_instance", -1)) == instance_index:
			return collider
	return null


## The tech formations used to collide as the complete +/-0.66 outer AABB.
## That covered every panel, but it also filled all the air between sparse deep
## bars; after non-uniform scaling those empty bands became invisible walls tens
## of metres from a giant fragment. This checks the replacement is a streamed,
## exposed concave surface and that its burial cut never reaches below terrain.
func _tech_collision_checks() -> void:
	var sites := _planet.find_child(
		"TechFormationSites", true, false) as TechFormationSites
	if sites == null:
		push_error("player_test: tech collision has no formation field")
		return
	var pieces: Array = sites.get("_pieces")
	var per_site: int = sites.fragments_per_site
	if pieces.size() < per_site * 2:
		push_error("player_test: tech collision has incomplete formation pieces")
		return

	# The first piece in a dry site is its deliberately giant hero rectangle.
	var index := per_site
	var piece: Dictionary = pieces[index]
	var stood: Transform3D = piece["transform"]
	var original := _player.global_position
	_player.controls_enabled = false
	_player.velocity = Vector3.ZERO
	_player.set_process(false)
	_player.set_physics_process(false)
	var approach := stood.origin + stood.basis.z.normalized() * (
		float(piece["reach"]) + 18.0)
	_player.global_position = sites.to_global(approach)

	var began := Time.get_ticks_usec()
	var active := {}
	for _frame in 240:
		await get_tree().process_frame
		active = sites.get("_active_colliders")
		if active.has(index):
			break
	if not active.has(index):
		push_error("player_test: tech collision did not stream the nearby fragment")
		return
	var built_ms := float(Time.get_ticks_usec() - began) / 1000.0
	var collider := active[index] as CollisionShape3D
	if collider == null or not collider.shape is ConcavePolygonShape3D:
		push_error("player_test: tech collision is still an envelope primitive")
		return
	var faces := (collider.shape as ConcavePolygonShape3D).get_faces()
	if faces.is_empty():
		push_error("player_test: tech collision generated no exposed faces")
		return

	var ground_point: Vector3 = piece["ground_point"]
	var ground_up: Vector3 = piece["ground_up"]
	var lowest := INF
	for point in faces:
		var field_point := collider.transform * point
		lowest = minf(lowest, ground_up.dot(field_point - ground_point))
	if lowest < sites.collision_ground_recess - 0.02:
		push_error(
			"player_test: tech collision extends %.3f m below its exposed cut"
			% (lowest - sites.collision_ground_recess))
		return

	# Prove the generated resource is not merely populated but live in the
	# physics server. Choose an upward-facing panel well clear of terrain so the
	# planet cannot be the thing this short ray reports.
	var ray_centre := Vector3.ZERO
	var ray_normal := Vector3.ZERO
	var ray_clearance := -INF
	for triangle in range(0, faces.size(), 3):
		var a := faces[triangle]
		var b := faces[triangle + 1]
		var c := faces[triangle + 2]
		var normal := (b - a).cross(c - a).normalized()
		var field_normal := (collider.transform.basis * normal).normalized()
		var centre := (a + b + c) / 3.0
		var clearance := ground_up.dot(
			collider.transform * centre - ground_point)
		if field_normal.dot(ground_up) > 0.35 and clearance > ray_clearance:
			ray_centre = centre
			ray_normal = normal
			ray_clearance = clearance
	if ray_normal == Vector3.ZERO:
		push_error("player_test: tech collision found no exposed upward panel")
		return
	var centre_global := sites.to_global(collider.transform * ray_centre)
	var normal_global := (
		sites.global_basis * collider.transform.basis * ray_normal).normalized()
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(
		centre_global + normal_global * 2.0,
		centre_global - normal_global * 2.0, 1)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != collider.get_parent():
		push_error("player_test: exposed tech panel is not live collision")
		return

	# Moving back to the colony proves the detailed shape does not remain loaded
	# as one planet-wide physics burden.
	_player.global_position = original
	for _frame in 120:
		await get_tree().process_frame
		active = sites.get("_active_colliders")
		if active.is_empty():
			break
	print((
		"player_test: tech collision  %d exposed triangles in %.1f ms, "
		+ "lowest %.3f m, streamed back to %d active")
		% [faces.size() / 3, built_ms, lowest, active.size()])
	if not active.is_empty():
		push_error("player_test: remote tech collision did not stream back out")


## Ring sites are deliberately too large and too transparent to validate from
## resource files alone. This checks the generated curves, four map landmarks,
## persistent local lights and the clipped convex collision, then records the
## arctic hero ring under both the sun and its own green emission.
func _ring_site_checks() -> void:
	var sites := _planet.find_child("RingSites", true, false) as RingSites
	if sites == null:
		push_error("player_test: RingSites is missing")
		return
	var fields: Array[MultiMeshInstance3D] = []
	var markers: Array[Landmark] = []
	var lights: Array[OmniLight3D] = []
	for child in sites.get_children(true):
		if child is MultiMeshInstance3D:
			fields.append(child)
		elif child is Landmark:
			markers.append(child)
		elif child is OmniLight3D:
			lights.append(child)
	if fields.size() != 4:
		push_error("player_test: rings generated %d fields, expected 4"
			% fields.size())
		return
	var instances := 0
	for field in fields:
		if field.multimesh == null:
			push_error("player_test: ring field has no MultiMesh")
			return
		instances += field.multimesh.instance_count
	if instances != 788:
		push_error("player_test: rings generated %d/788 crystal segments"
			% instances)
		return
	if markers.size() != 4:
		push_error("player_test: rings generated %d/4 map landmarks"
			% markers.size())
		return
	for title in RingSites.SITE_TITLES:
		var found := false
		for marker in markers:
			if marker.title == title and marker.waypoint \
					and marker.hide_beyond == 0.0:
				found = true
				break
		if not found:
			push_error("player_test: missing orbital ring marker %s" % title)
			return
	if lights.size() != 12:
		push_error("player_test: rings generated %d/12 local lights"
			% lights.size())
		return
	for light in lights:
		if light.light_energy <= 0.0 or light.omni_range < 80.0:
			push_error("player_test: ring light is not a persistent ground light")
			return

	var pieces: Array = sites.get("_segments")
	if pieces.size() != instances:
		push_error("player_test: ring render/collision segment lists disagree")
		return
	for candidate_index in pieces.size():
		var candidate: Dictionary = pieces[candidate_index]
		var surface_direction: Vector3 = candidate["ground_up"]
		var site_index: int = candidate["site"]
		var height := _planet.shape.elevation(
			surface_direction, _planet.finest_spacing())
		if site_index == 0:
			if _planet.shape.frost(surface_direction) < 0.5 \
					or absf(height - PlanetShape.ICE_TOP) > 0.08:
				push_error("player_test: arctic ring leaves its surveyed pack ice")
				return
		else:
			var sample := _planet.shape.sample(surface_direction)
			if height < 2.0 or float(sample["river"]) > 0.0 \
					or float(sample["lake"]) > 0.0:
				push_error("player_test: dry ring crosses water")
				return
			var surface_dot := _planet.shape.normal_at(
				surface_direction, _planet.finest_spacing()
				).dot(surface_direction)
			if surface_dot < cos(deg_to_rad(32.0)):
				push_error(
					("player_test: dry ring segment %d at site %d crosses "
					+ "a %.1f degree face") % [
						candidate_index, site_index,
						rad_to_deg(acos(clampf(surface_dot, -1.0, 1.0)))])
				return
	var piece: Dictionary = pieces[0]
	var stood: Transform3D = piece["transform"]
	var original := _player.global_transform
	_player.controls_enabled = false
	_player.velocity = Vector3.ZERO
	_player.set_process(false)
	_player.set_physics_process(false)
	_player.global_position = sites.to_global(
		stood.origin + stood.basis.z.normalized() * (
			float(piece["reach"]) + 8.0))
	var began := Time.get_ticks_usec()
	var active := {}
	for _frame in 240:
		await get_tree().process_frame
		active = sites.get("_active_colliders")
		if active.has(0):
			break
	if not active.has(0):
		push_error("player_test: ring collision did not stream by the hero ring")
		return
	var built_ms := float(Time.get_ticks_usec() - began) / 1000.0
	var collider := active[0] as CollisionShape3D
	if collider == null or not collider.shape is ConvexPolygonShape3D:
		push_error("player_test: ring collision is not a convex crystal segment")
		return
	var points := (collider.shape as ConvexPolygonShape3D).points
	if points.size() < 8:
		push_error("player_test: ring collision has too few clipped points")
		return
	var ground_point: Vector3 = piece["ground_point"]
	var ground_up: Vector3 = piece["ground_up"]
	var lowest := INF
	for point in points:
		lowest = minf(lowest, ground_up.dot(
			collider.transform * point - ground_point))
	if lowest < sites.collision_ground_recess - 0.02:
		push_error("player_test: ring collision reaches %.3f m below ground cut"
			% (lowest - sites.collision_ground_recess))
		return

	var centroid := Vector3.ZERO
	for point in points:
		centroid += point
	centroid /= float(points.size())
	var ray_axis := (points[0] - centroid).normalized()
	var ray_radius := 0.0
	for point in points:
		ray_radius = maxf(
			ray_radius, absf(ray_axis.dot(point - centroid)))
	var from := sites.to_global(collider.transform * (
		centroid + ray_axis * (ray_radius + 3.0)))
	var to := sites.to_global(collider.transform * (
		centroid - ray_axis * (ray_radius + 3.0)))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != collider.get_parent():
		push_error("player_test: ring crystal collision is not live in physics")
		return

	print((
		"player_test: rings  4 fields, %d segments, 4 orbital markers, "
		+ "%d lights, convex collision in %.1f ms")
		% [instances, lights.size(), built_ms])

	# A stable oblique view across the 720 m polar ring. The camera sits outside
	# its plane so translucency, silhouette and the ground light are all visible.
	var direction: Vector3 = RingSites.SITE_DIRECTIONS[0]
	var local_up := direction.normalized()
	var hint := Vector3.UP if absf(local_up.y) < 0.9 else Vector3.RIGHT
	var east := local_up.cross(hint).normalized()
	var north := local_up.cross(east).normalized()
	var heading := deg_to_rad(12.0)
	var right := (east * cos(heading) + north * sin(heading)).normalized()
	var plane_normal := right.cross(local_up).normalized()
	var centre_local := direction * (
		_planet.shape.radius + _planet.shape.elevation(
			direction, _planet.finest_spacing()))
	var origin_global := _planet.to_global(
		centre_local + plane_normal * 630.0 + local_up * 150.0)
	var target_global := _planet.to_global(centre_local + local_up * 105.0)
	var world_up := (_planet.global_basis * local_up).normalized()
	_player.global_transform = Transform3D(
		Basis.looking_at(target_global - origin_global, world_up),
		origin_global)
	_player.head.rotation = Vector3.ZERO
	_player._pitch = 0.0
	_player.character.visible = false
	_player.reset_physics_interpolation()
	if _player.hud != null:
		_player.hud.visible = false
	await _wait(120)
	await _shot("ring_arctic_day")

	var world := _planet.get_parent()
	var cycle := world.find_child(
		"CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if cycle != null:
		cycle.set_process(false)
	if sun != null:
		sun.visible = false
	var environment := world.find_child(
		"WorldEnvironment", true, false) as WorldEnvironment
	if environment != null and environment.environment != null:
		environment.environment.ambient_light_energy = 0.08
	await _wait(24)
	await _shot("ring_arctic_night")
	_player.global_transform = original


## Every generated biome species has three pieces of the color-paint contract:
## an external PNG on its resource, TEXCOORD_0 on the mesh, and the duplicated
## runtime material actually sampling that PNG. Checking only the files would
## miss the most likely failure — a perfectly good image which the MultiMesh
## material override never binds.
func _biome_paint_contract(fields: Array[GroundCover]) -> void:
	var seen := {}
	var missing: PackedStringArray = []
	var painted := 0
	for field in fields:
		for plant: PlantSpecies in field.species:
			if plant == null or seen.has(plant.resource_path):
				continue
			seen[plant.resource_path] = true
			plant.prepare()
			if plant.paint_texture == null:
				missing.append("%s has no PNG" % plant.resource_name)
				continue
			var mesh := plant.near_mesh()
			var has_uv := mesh != null
			if has_uv:
				for surface in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(surface)
					var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					if uv.is_empty():
						has_uv = false
						break
			if not has_uv:
				missing.append("%s has no TEXCOORD_0" % plant.resource_name)
				continue
			var runtime := plant.near_material()
			var enabled := runtime != null and bool(
				runtime.get_shader_parameter(&"color_paint_enabled"))
			var bound: Variant = runtime.get_shader_parameter(&"color_paint") \
				if runtime != null else null
			if not enabled or bound == null:
				missing.append("%s PNG is not bound" % plant.resource_name)
				continue
			painted += 1
	print("player_test: biomes  paint %d/%d species bound to PNG + TEXCOORD_0" % [
		painted, seen.size()])
	if not missing.is_empty():
		push_error("player_test: biome paint contract: %s" % ", ".join(missing))


## What the flora view distance setting actually buys, from three hundred metres.
##
## The question the setting exists to answer is whether the ground under a flying
## player is populated, and at the shipped ranges it was not: nothing in a
## GroundCover reached past about 285 m, so a viewer at 300 m was outside every
## field at once and looked down at bare terrain. Each pass here writes the
## setting through the manager rather than the static, so the row is also a test
## that the menu is wired to the fields at all.
##
## Counts are reported next to the frame cost deliberately. Range is the one
## graphics setting on the planet whose price rises with the square of the value,
## and a row of plant counts with no milliseconds beside it would hide that.
func _flora_range_checks() -> void:
	var world := _planet.get_parent()
	var settings := get_node_or_null("/root/SettingsManager") as GameSettingsManager
	if settings == null:
		push_error("player_test: flora range needs the SettingsManager autoload")
		return
	var fields: Array[GroundCover] = []
	for node in world.find_children("*", "GroundCover", true, false):
		fields.append(node as GroundCover)
	if fields.is_empty():
		push_error("player_test: no cover fields to range")
		return
	var classifier := world.find_child("GlobalGrass", true, false) as GroundCover
	if classifier == null:
		push_error("player_test: flora range needs the terrain classifier")
		return
	var site := _biome_direction(classifier, PlantSpecies.Ground.GRASS,
		0.0, 0.4, 0.0, 0.32, 12.0, 210.0, 61701)
	if site == Vector3.ZERO:
		push_error("player_test: found no grassland to fly over")
		return
	if _player.hud != null:
		_player.hud.visible = false
	_player._camera_mode = 0
	# Midday and a still planet. The point of the shot is how much of the ground
	# is covered, and neither a night pass nor a swaying one answers that.
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
		cycle.set_phase(0.0)
	# Not `_still_planet`: that stops the cover fields, which are the whole
	# subject here. Only the two things that would otherwise be in the way.
	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.0)
	if _player.character != null:
		_player.character.visible = false
	var was := float(settings.get_setting(&"graphics", &"flora_range", 2.0))

	for wanted: float in [1.0, 2.0, 4.0]:
		settings.set_setting(&"graphics", &"flora_range", wanted)
		# Past the settle window the fields debounce the slider with, then far
		# enough for the first ring of tiles to have been asked for.
		_look_down_from(site, 300.0)
		await _wait(60)
		var patience := 0
		while patience < 3600:
			# Re-aimed every pass. The flight stance keeps levelling the body
			# against the planet, and a survey run from a drifting eye is not
			# the one the shot is taken from.
			_look_down_from(site, 300.0)
			var waiting := 0
			var surveyed := 0
			for field in fields:
				waiting += field.settling()
				surveyed += field.tiles()
			# Nothing waiting reads the same before the first survey as after
			# the last tile lands, so a field has to have been asked for
			# something before its silence counts as finished.
			if waiting == 0 and surveyed > 0 and patience > 60:
				break
			await _wait(10)
			patience += 10
		var reach := 0.0
		var drawn := 0
		var held := 0
		var tiles := 0
		for field in fields:
			for plant in field.species:
				if plant != null:
					reach = maxf(reach, plant.draw_reach())
			drawn += field.grown()
			held += field.planted()
			tiles += field.tiles()
		# What a viewer at this altitude can see of that reach: the slant range
		# is the hypotenuse, so the circle of ground actually inside the fields
		# is narrower than the number the species carries.
		var circle := sqrt(maxf(reach * reach - 300.0 * 300.0, 0.0))
		var slowest := 0.0
		var began := Time.get_ticks_usec()
		var previous := began
		for _tick in 120:
			_look_down_from(site, 300.0)
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			slowest = maxf(slowest, float(now - previous) / 1000.0)
			previous = now
		var elapsed := float(Time.get_ticks_usec() - began) / 1000.0
		print(("player_test: range %.2fx  reach=%4.0f m  circle at 300 m=%4.0f m  "
			+ "drawn=%7d held=%7d tiles=%5d  settled=%4.1fs  "
			+ "frame mean=%.2f ms worst=%.2f ms fps=%.0f") % [
			wanted, reach, circle, drawn, held, tiles, patience / 60.0,
			elapsed / 120.0, slowest, 120000.0 / elapsed])
		for field in fields:
			if field.grown() > 0:
				print("player_test: range     %-16s %6d drawn  %6d held  %4d tiles" % [
					field.name, field.grown(), field.planted(), field.tiles()])
		_look_down_from(site, 300.0)
		await _drawn(2)
		await _shot("flora_range_%.0fx" % (wanted * 100.0))

	# Not saved, and put back: a harness should not leave the player on a
	# setting they never chose.
	settings.set_setting(&"graphics", &"flora_range", was)


## Why a species grew nothing here, counted over the ground it was offered.
##
## A count of zero has two very different causes which look identical from the
## outside: no spot in reach suits the plant, or plenty do and the patch field
## simply left this stretch bare. The reason histogram separates them, and names
## the single rule to move when the cause is the first one.
func _habitat_probe(field: GroundCover, plant: PlantSpecies, at: Vector3,
		reach: float, samples: int) -> String:
	var radius := _planet.shape.radius
	var east := at.cross(Vector3.UP if absf(at.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := at.cross(east)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(plant.resource_name)
	var reasons := {}
	for _try in samples:
		var spin := rng.randf() * TAU
		var out := sqrt(rng.randf()) * reach / radius
		var spot := (at + (east * cos(spin) + north * sin(spin)) * out).normalized()
		var reason := field.habitat_reason(plant, spot)
		reasons[reason] = int(reasons.get(reason, 0)) + 1
	var order := reasons.keys()
	order.sort_custom(func(a, b): return reasons[a] > reasons[b])
	var parts := PackedStringArray()
	for reason in order:
		parts.append("%s %d%%" % [reason,
			roundi(100.0 * float(reasons[reason]) / float(samples))])
	return ", ".join(parts)


## Finds terrain which satisfies the same painted-material and climate contract
## as a PlantSpecies. Searched from the height field so a seed/terrain change
## cannot leave the harness photographing stale coordinates.
func _biome_direction(classifier: GroundCover, layer: PlantSpecies.Ground,
		minimum_arid: float, maximum_arid: float,
		minimum_frost: float, maximum_frost: float,
		minimum_height: float, maximum_height: float, seed: int) -> Vector3:
	var spacing := _planet.finest_spacing()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var best := Vector3.ZERO
	var best_score := -INF
	for _try in 12000:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if direction.length_squared() < 0.001:
			continue
		direction = direction.normalized()
		var height := _planet.shape.elevation(direction, spacing)
		if height < minimum_height or height > maximum_height:
			continue
		var sample := _planet.shape.sample(direction)
		var arid := float(sample.get("arid", 0.0))
		var frost := _planet.shape.frost(direction)
		if arid < minimum_arid or arid > maximum_arid \
				or frost < minimum_frost or frost > maximum_frost:
			continue
		if float(sample["river"]) > 0.0 or float(sample["lake"]) > 0.0:
			continue
		var normal := _planet.shape.normal_at(direction, spacing)
		var biome := _planet.shape.color_at(direction, height, normal)
		if not classifier.terrain_claims(
				direction, height, normal, biome, layer, 0.05):
			continue
		var flatness := normal.dot(direction)
		var climate := arid if minimum_arid > 0.0 \
			else (frost if minimum_frost > 0.0 else 0.5)
		var score := flatness * 2.0 + climate
		if score > best_score:
			best_score = score
			best = direction
	return best


## Whether the reef lights itself at night, and whether it does so in its own
## colours.
##
## The second half is the part worth testing. Emission that comes on at midnight
## is easy to confirm and easy to get wrong in a way that still passes: a single
## authored colour would light every head the same shade and satisfy any check
## that only asks whether the reef got brighter. So this photographs the reef
## with the emission on and off, and looks at the hue of what was added. One
## authored colour puts every gained pixel in one hue bucket. Colour taken from
## the coral spreads them across the four the meshes are painted in.
func _reef_glow_checks() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var reef := world.find_child("Reef", true, false) as GroundCover
	if cycle == null or reef == null:
		push_error("player_test: reef glow needs the cycle and the reef")
		return
	if reef.glow_light_range < 24.0 or reef.glow_light_energy < 5.0:
		push_error("player_test: reef cast-light pool is not broad and strong")
		return
	# The live materials, off the species, not the .tres they were authored in.
	# PlantSpecies.prepare duplicates the material for each species and LOD so
	# that one field cannot retune another's draw range, which means the shared
	# coral.tres is not the material anything on screen is drawn with. Writing to
	# it changes nothing and does so silently: the first version of this pass
	# toggled the file, photographed two identical reefs, and reported whatever
	# noise it could find between them.
	var lamps: Array[ShaderMaterial] = []
	for entry in reef.species:
		var plant := entry as PlantSpecies
		if plant == null:
			continue
		for used in [plant.near_material(), plant.far_material()]:
			var shaded := used as ShaderMaterial
			if shaded != null and not lamps.has(shaded):
				lamps.append(shaded)
	if lamps.is_empty():
		push_error("player_test: the reef has no coral materials")
		return
	var energy: float = lamps[0].get_shader_parameter(&"night_emission_energy")
	if energy <= 0.0:
		push_error("player_test: coral has no night emission to measure")
		return

	cycle.period_seconds = 0.0
	cycle.set_phase(0.5)
	if _player.hud != null:
		_player.hud.visible = false
	var spot := _reef_direction()
	if spot == Vector3.ZERO:
		push_error("player_test: found no reef shelf near the colony")
		return
	print("player_test: reef glow  shelf at %.1f m below sea level" % [
		_planet.shape.elevation(spot, _planet.finest_spacing())])
	_stand_on(spot)
	await _wait(240)
	_stand_on(spot)
	var patience := 0
	while patience < 2400 and reef.settling() > 0:
		await _wait(10)
		patience += 10
	print("player_test: reef glow  %d corals standing after %.1fs" % [
		reef.grown(), patience / 60.0])
	if reef.grown() == 0:
		push_error("player_test: no coral grew on the shelf")
		return
	# The mesh emission above is only half the feature. GroundCover should have
	# turned night-emissive species into bounded nearby OmniLight targets as
	# well, in the colours authored on the four coral species.
	await _wait(120)
	var cast_lights := _omni_lights(reef)
	var active_lights := 0
	var cast_colours := PackedColorArray()
	for light in cast_lights:
		if light.visible and light.light_energy > 0.01:
			active_lights += 1
			cast_colours.append(light.light_color)
	print("player_test: reef glow  %d/%d pooled lights active, colours %s" % [
		active_lights, cast_lights.size(), cast_colours])
	if active_lights == 0:
		push_error("player_test: luminous coral supplied no cast lights")
		return
	# Level, so the frame is reef rather than sand.
	_look(0.0)
	await _shot("reef_glow_cast_light")
	_still_planet(world)
	await _wait(30)
	# And the body, which is the last thing in frame still moving. A swimmer is
	# never quite at rest — buoyancy keeps trading against gravity — and a camera
	# that shifts by a fraction of a millimetre puts a full-scale difference
	# along every high-contrast edge, which at midnight is the outline of every
	# coral against black water. That is precisely the outline being measured.
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _wait(4)
	# _still_planet is not enough here and cannot reasonably be made enough. It
	# knows about the wind, the clouds, the sea surface and the pooled lights,
	# but underwater the loudest thing in frame is the caustics on the sand, and
	# behind them a swimming body that never quite settles. Slowing the clock
	# slows all of it, and anything added later, without this function needing to
	# be told what that is.
	#
	# Slowed and not stopped: at a time scale of exactly zero the renderer stops
	# producing new frames, so all three captures come back byte-identical and
	# the pass reports a perfect noise floor and no signal whatsoever. A fiftieth
	# advances the caustics by a small fraction of one frame across the three
	# captures, which measures as a noise floor of about a thousandth.
	#
	# Physics is scaled with it, so nothing below may wait on a physics frame.
	Engine.time_scale = 0.02

	var night_lit := await _frame("reef_glow_night")
	# The same frame again with nothing touched. The sea is still faintly alive
	# even after _still_planet and the corals themselves breathe, so a bare
	# difference against the unlit frame counts a quarter of the picture as
	# "gained light" when the coral covers a few percent of it — and the hue of
	# that quarter is the hue of the water, which buried the thing being looked
	# for. This frame is the floor everything below has to clear.
	await _drawn(3)
	var night_again := await _frame("")
	_set_coral_glow(lamps, 0.0)
	await _drawn(3)
	var night_dark := await _frame("reef_glow_night_unlit")
	_set_coral_glow(lamps, energy)
	_report_reef_glow("midnight", night_lit, night_again, night_dark)

	# And off again at noon, which is the other half of "at night". The same two
	# frames taken with the sun up should differ by nothing at all.
	#
	# Zero, not a quarter. Phase is measured from noon at the landing site, so a
	# quarter is dusk — where the emission is genuinely half up, and where this
	# check duly failed for a while before the convention was read rather than
	# assumed.
	cycle.set_phase(0.0)
	await _drawn(30)
	var noon_lit := await _frame("reef_glow_noon")
	await _drawn(3)
	var noon_again := await _frame("")
	_set_coral_glow(lamps, 0.0)
	await _drawn(3)
	var noon_dark := await _frame("")
	_set_coral_glow(lamps, energy)
	_report_reef_glow("noon", noon_lit, noon_again, noon_dark)
	Engine.time_scale = 1.0


func _set_coral_glow(lamps: Array[ShaderMaterial], energy: float) -> void:
	for lamp in lamps:
		lamp.set_shader_parameter(&"night_emission_energy", energy)


## The light the emission is responsible for, as a share of the picture and as a
## spread of hues. [param again] is the untouched repeat of [param lit] and sets
## the noise floor; a pixel has to beat its own frame-to-frame wobble by a clear
## margin before it counts as having been lit by anything.
func _report_reef_glow(when: String, lit: Image, again: Image, dark: Image) -> void:
	if lit == null or again == null or dark == null:
		push_error("player_test: reef glow captured no frames at %s" % when)
		return
	var width := lit.get_width()
	var height := lit.get_height()
	var buckets := PackedInt32Array()
	buckets.resize(12)
	var touched := 0
	var gained := Color(0.0, 0.0, 0.0)
	var brightest := 0.0
	var floor_peak := 0.0
	for y in height:
		for x in width:
			var steady := lit.get_pixel(x, y) - again.get_pixel(x, y)
			var wobble := maxf(maxf(absf(steady.r), absf(steady.g)),
				absf(steady.b))
			floor_peak = maxf(floor_peak, wobble)
			var change := lit.get_pixel(x, y) - dark.get_pixel(x, y)
			var most := maxf(maxf(change.r, change.g), change.b)
			if most <= maxf(0.05, wobble * 3.0):
				continue
			touched += 1
			gained += change
			brightest = maxf(brightest, most)
			# Hue of the light that was added, not of the pixel it landed on.
			buckets[clampi(int(Color(maxf(change.r, 0.0), maxf(change.g, 0.0),
				maxf(change.b, 0.0)).h * 12.0), 0, 11)] += 1
	var pixels := float(width * height)
	print("player_test: reef glow  %-8s noise floor peak %.4f" % [
		when, floor_peak])
	if touched == 0:
		print("player_test: reef glow  %-8s nothing gained any light" % when)
		if when == "midnight":
			push_error("player_test: the reef did not light up at midnight")
		return
	print("player_test: reef glow  %-8s lit %.2f%% of frame, mean rgb (%.3f %.3f %.3f), peak %.3f" % [
		when, 100.0 * touched / pixels, gained.r / touched, gained.g / touched,
		gained.b / touched, brightest])
	var spread := 0
	var row := ""
	for index in buckets.size():
		var share := float(buckets[index]) / float(touched)
		row += "%5.1f" % (100.0 * share)
		if share > 0.06:
			spread += 1
	print("player_test: reef glow  %-8s hue %s  (%d buckets over 6%%)" % [
		when, row, spread])
	if when == "noon":
		if touched * 200 > int(pixels):
			push_error("player_test: the reef is still emitting in daylight")
		return
	if spread < 2:
		push_error("player_test: the reef glows in one hue, not in its own colours")


## What the lawn actually delivers at each distance, and what it costs.
##
## "More grass" is two separate questions and they are answered in different
## places. How much of it there is at a given range is arithmetic — the species'
## density times the share its thinning curve keeps out there — and can be
## printed exactly rather than squinted at. What that costs is not arithmetic at
## all, because the thinning means most of the planted circle is never submitted,
## so the instance counts have to be read off the live fields.
##
## Both fields are reported because neither is the lawn on its own: the dense
## one owns the near ground and hands over to the sparse one, and a bare band is
## what happens between them when the handover is set wrong.
func _lawn_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		# Pinned to midday rather than merely stopped. Stopping it freezes
		# whichever phase the run happened to reach, and how long a run takes to
		# reach this line depends on how long the field took to stream — so a
		# denser species moves the sun, the sun moves the shadow work, and the
		# frame time comes back different for a reason that has nothing to do
		# with grass. Two runs an hour apart differed by fourteen frames a second
		# on this alone.
		cycle.period_seconds = 0.0
		cycle.set_phase(0.25)
	# Off, because a capped frame rate reports the cap and calls it a result.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _player.hud != null:
		_player.hud.visible = false
	var fields := {
		"near": world.find_child("GlobalGrass", true, false) as GroundCover,
		"far": world.find_child("GlobalDistantGrass", true, false) as GroundCover,
	}
	for name: String in fields:
		if fields[name] == null:
			push_error("player_test: lawn needs both grass fields")
			return
	_stand_on(_grass_direction())
	await _wait(120)
	_stand_on(_grass_direction())
	# Waited on rather than guessed at. These fields apply one tile a frame, and a
	# denser species makes every one of those tiles a bigger buffer to build, so a
	# fixed wait that was ample before a density change can be nowhere near enough
	# after it — and a frame time measured while tiles are still landing is a
	# measurement of the streaming, not of the field.
	var patience := 0
	while patience < 3600:
		var waiting := 0
		for name: String in fields:
			waiting += (fields[name] as GroundCover).settling()
		if waiting == 0:
			break
		await _wait(10)
		patience += 10
	print("player_test: lawn  settled after %.1fs of standing still" % [
		patience / 60.0])
	await _wait(120)

	# per_square_metre is already the blade count and clump_count must not be
	# multiplied into it. _scatter divides the number of spots it tests by the
	# clump size precisely so that the density stays put when the clumping
	# changes — the clump decides whether those blades stand in many small tufts
	# or few large ones, not how many of them there are.
	print("player_test: lawn  blades per square metre, by distance")
	var header := "player_test: lawn  %8s" % "metres"
	for away: float in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 80.0, 120.0, 200.0]:
		header += "%7.0f" % away
	print(header)
	var totals := {}
	for name: String in fields:
		var cover: GroundCover = fields[name]
		var line := "player_test: lawn  %8s" % name
		for away: float in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 80.0, 120.0, 200.0]:
			var blades := 0.0
			for entry in cover.species:
				var plant := entry as PlantSpecies
				blades += plant.per_square_metre \
					* (1.0 - plant.bare_share) * minf(plant.keep_at(away), 1.0)
			line += "%7.1f" % blades
			totals[away] = float(totals.get(away, 0.0)) + blades
		print(line)
	var summed := "player_test: lawn  %8s" % "both"
	for away: float in [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 80.0, 120.0, 200.0]:
		summed += "%7.1f" % float(totals[away])
	print(summed)

	for name: String in fields:
		var cover: GroundCover = fields[name]
		print("player_test: lawn  %-5s drawn=%7d held=%7d tiles=%4d" % [
			name, cover.grown(), cover.planted(), cover.tiles()])

	# Frame cost, which is the number that decides whether any of the above is
	# affordable. Taken over a couple of seconds of standing still so a single
	# slow frame does not become the finding.
	var slowest := 0.0
	var spent := 0.0
	var draw_calls := 0.0
	for _tick in 120:
		await get_tree().process_frame
		var frame := float(Performance.get_monitor(
			Performance.TIME_PROCESS)) + float(Performance.get_monitor(
			Performance.TIME_PHYSICS_PROCESS))
		spent += frame
		slowest = maxf(slowest, frame)
		draw_calls += float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("player_test: lawn  cpu frame mean=%.3f ms worst=%.3f ms  fps=%.1f draws=%.0f" % [
		spent / 120.0 * 1000.0, slowest * 1000.0,
		Performance.get_monitor(Performance.TIME_FPS), draw_calls / 120.0])

	# Pictures last. Reading the viewport back stalls the pipeline for the better
	# part of a second, and taken before the timing loop that stall lands inside
	# it: a run with screenshots reported a worst frame of 791 ms and a mean four
	# times the truth.
	#
	# A shallow angle, because the middle distance is only in shot at one. Level
	# puts the 40 to 60 m band in the middle of the frame where the question can
	# be judged; the harness's usual downward pitch fills the picture with the two
	# metres in front of the player's feet, which was never the part in doubt.
	var tag := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	_look(-0.16)
	await _wait(20)
	await _shot("lawn_%s_middle" % tag)
	_look(-0.55)
	await _wait(20)
	await _shot("lawn_%s_underfoot" % tag)


## Whether walking towards a distant tile grows plants or rearranges them.
##
## Tiles are no longer sown at full density wherever they are: one a few hundred
## metres off gets a fraction of its plants, because a fraction is all the
## thinning would ever have shown, and coming closer sows it again at a finer
## band. The whole approach rests on that second sow reproducing the first one
## exactly and adding to it — the candidate order is random and deterministic, so
## stopping early and carrying on later should give the identical prefix.
##
## If that is wrong it is not subtly wrong. Every plant on every tile would shift
## as the player walked towards it, which is the sort of thing that is obvious in
## motion and invisible in a screenshot, so it is worth a test that reads the
## buffers rather than an eye that might not be looking.
func _regrow_report() -> void:
	var world := _planet.get_parent()
	var field := world.find_child("GlobalDistantGrass", true, false) as GroundCover
	if field == null:
		push_error("player_test: regrow needs the distant grass field")
		return
	_stand_on(_grass_direction())
	await _wait(90)
	_stand_on(_grass_direction())
	await _settled(field)

	# The furthest tile that actually grew something, which is the one sown at
	# the coarsest band and so has the most to prove.
	var chosen := Vector3i.ZERO
	var furthest := 0.0
	for cell: Vector3i in field._tiles:
		var tile: GroundCover.Tile = field._tiles[cell]
		if tile.stands.is_empty() or tile.stands[0] == null:
			continue
		if tile.away > furthest:
			furthest = tile.away
			chosen = cell
	if furthest <= 0.0:
		push_error("player_test: regrow found no grown tile to follow")
		return

	var tile: GroundCover.Tile = field._tiles[chosen]
	var coarse_detail: float = tile.detail[0]
	var coarse := _tile_origins(field, tile)
	print("player_test: regrow  tile %d m off holds %d blades at detail %.4f" % [
		int(furthest), coarse.size(), coarse_detail])

	# Stand on it. Nothing about the tile changes except how much of it the
	# distance now earns.
	_stand_on(_planet.to_local(tile.at).normalized())
	await _wait(90)
	await _settled(field)
	var near_tile: GroundCover.Tile = field._tiles.get(chosen)
	if near_tile == null or near_tile.stands.is_empty() \
			or near_tile.stands[0] == null:
		push_error("player_test: regrow lost the tile on approach")
		return
	var fine_detail: float = near_tile.detail[0]
	var fine := _tile_origins(field, near_tile)
	print("player_test: regrow  same tile underfoot holds %d at detail %.4f" % [
		fine.size(), fine_detail])

	if fine_detail <= coarse_detail:
		push_error("player_test: regrow never refined the tile (%.4f to %.4f)"
			% [coarse_detail, fine_detail])
		return
	if fine.size() < coarse.size():
		push_error("player_test: regrow lost blades on approach, %d to %d"
			% [coarse.size(), fine.size()])
		return
	var moved := 0.0
	for index in coarse.size():
		moved = maxf(moved, coarse[index].distance_to(fine[index]))
	if moved > 0.01:
		push_error(("player_test: regrow moved a standing blade %.3f m; the "
			+ "finer sow is not a superset of the coarse one") % moved)
		return
	print(("player_test: regrow  %d blades held station to within %.4f m while "
		+ "%d grew in between them") % [coarse.size(), moved,
		fine.size() - coarse.size()])


## Every instance origin a tile is holding for its first species, in order.
func _tile_origins(field: GroundCover,
		tile: GroundCover.Tile) -> PackedVector3Array:
	var stand := tile.stands[0] as MultiMeshInstance3D
	var buffer := stand.multimesh.buffer
	var origins := PackedVector3Array()
	for index in stand.multimesh.instance_count:
		origins.append(stand.global_transform
			* field._instance_transform(buffer, index).origin)
	return origins


func _settled(field: GroundCover) -> void:
	var patience := 0
	while patience < 2400 and field.settling() > 0:
		await _wait(10)
		patience += 10


## What pressing New Game now pays for, and whether it is worth the wait.
##
## Two questions, and the second is the one that decides whether the card should
## exist at all. How long does the warm-up take, and does the descent it is
## paying for actually get cheaper — because a loading screen that buys nothing
## is worse than no loading screen.
##
## The descent is measured as the worst frame of a flight from the spawn down to
## the ground, which is where a pipeline compile shows up: not as a cost spread
## over the run but as one frame that takes a tenth of a second while everything
## else takes eight milliseconds.
func _warmup_report() -> void:
	var world := _planet.get_parent()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _player.hud != null:
		_player.hud.visible = false
	var spot := _grass_direction()

	# `--cold` skips the warm-up and flies the same descent, which is the only
	# way to see what the card bought: within one run a pipeline is compiled
	# once, so a warmed process cannot also measure an unwarmed one.
	if "--cold" in OS.get_cmdline_user_args():
		await _warmup_descent(spot, "cold")
		return

	var warmup := WorldWarmup.new()
	warmup.name = "WorldWarmup"
	# Counted through a container rather than a local, because a lambda captures
	# a local by value and would have been adding to a copy.
	var notes := PackedStringArray()
	warmup.progressed.connect(func(_share: float, note: String) -> void:
		notes.append(note))
	world.add_child(warmup)
	var began := Time.get_ticks_usec()
	await warmup.run(world, _player.camera)
	var spent := float(Time.get_ticks_usec() - began) / 1000.0
	print("player_test: warmup  %d pairs in %.0f ms, %d steps, last '%s'" % [
		warmup.compiled, spent, notes.size(),
		"" if notes.is_empty() else notes[notes.size() - 1]])
	if warmup.compiled < 40:
		push_error("player_test: warmup only found %d pairs to compile"
			% warmup.compiled)
		return
	warmup.queue_free()

	# Left behind is the failure worth catching: this hangs geometry off the
	# camera and takes it away again, and a node it forgot would follow the
	# player around for the rest of the game.
	var left := 0
	for child in _player.camera.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D:
			left += 1
	if left > 0:
		push_error("player_test: warmup left %d nodes on the camera" % left)
		return

	await _warmup_descent(spot, "warm")


## Falls from the spawn to the ground, which crosses every level of terrain
## detail and every band of flora on the way down. Reported as the worst frame
## rather than the mean, because a pipeline compile is not a cost spread over a
## descent: it is one frame that takes a tenth of a second.
func _warmup_descent(spot: Vector3, tag: String) -> void:
	var worst := 0.0
	var spent := 0.0
	var long_frames := 0
	var previous := Time.get_ticks_usec()
	for step in 240:
		_look_down_from(spot, lerpf(9000.0, 3.0, float(step) / 239.0))
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame := float(now - previous) / 1000.0
		spent += frame
		worst = maxf(worst, frame)
		if frame > 25.0:
			long_frames += 1
		previous = now
	print(("player_test: warmup  %-4s descent frame mean=%.2f ms worst=%.2f ms"
		+ "  frames over 25 ms=%d") % [tag, spent / 240.0, worst, long_frames])


## Where the frame actually goes, subsystem by subsystem.
##
## `--lawn` reports one number for the whole scene, which is enough to notice a
## regression and useless for choosing what to fix: a ten millisecond frame full
## of grass and a ten millisecond frame full of pooled lights look identical.
## This switches one group of flora off at a time and re-measures, so the cost of
## each is the difference it leaves behind rather than a guess about which of
## them looks expensive.
##
## Both halves are reported because they have different cures. Wall-clock frame
## time is what makes the fans audible and includes the GPU; process time is CPU
## only, and a group that costs milliseconds of wall clock but none of CPU is a
## drawing problem, not a streaming one.
func _flora_cost_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
		cycle.set_phase(0.25)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if _player.hud != null:
		_player.hud.visible = false

	var groups := {
		"near grass": ["GlobalGrass"],
		"far grass": ["GlobalDistantGrass"],
		"biome flora": ["BiomePopulations"],
		"reef coral": ["Reef"],
		"colony flowers": ["LandingFlowers"],
		"flower trees": ["LandingFlowerTrees"],
		"fish schools": ["FishSchools", "ReefSwarms", "NightShoals"],
		"air swarms": ["NightSparkles", "NightWisps"],
	}
	var nodes := {}
	for label: String in groups:
		var found: Array[Node] = []
		for name: String in groups[label]:
			var node := world.find_child(name, true, false)
			if node != null:
				found.append(node)
		nodes[label] = found

	_stand_on(_grass_direction())
	await _wait(120)
	_stand_on(_grass_direction())
	var covers := _cover_fields(world)
	var patience := 0
	while patience < 3600:
		var waiting := 0
		for cover: GroundCover in covers:
			waiting += cover.settling()
		if waiting == 0:
			break
		await _wait(10)
		patience += 10
	print("player_test: cost  settled after %.1fs, %d cover fields" % [
		patience / 60.0, covers.size()])
	_look(-0.16)
	await _wait(60)

	var base := await _frame_cost(120)
	print(("player_test: cost  %-16s frame=%6.2f ms  cpu=%6.2f ms  "
		+ "draws=%5.0f  fps=%5.1f") % ["everything on", base["frame"],
		base["cpu"], base["draws"], 1000.0 / maxf(base["frame"], 0.001)])

	for label: String in groups:
		var group: Array[Node] = nodes[label]
		if group.is_empty():
			continue
		for node in group:
			_set_group_running(node, false)
		var off := await _frame_cost(90)
		for node in group:
			_set_group_running(node, true)
		print(("player_test: cost  %-16s frame -%5.2f ms  cpu -%5.2f ms  "
			+ "draws -%5.0f") % [label, base["frame"] - off["frame"],
			base["cpu"] - off["cpu"], base["draws"] - off["draws"]])
		await _wait(30)

	# Cross-cutting costs, which no single node owns. Pooled lights and shadow
	# casting are both switched on per field and per species, so their price is
	# spread across every group above and invisible in the table.
	var lights := _pooled_flora_lights(world)
	var lit := 0
	for light in lights:
		if light.visible:
			lit += 1
		light.visible = false
	var without_lights := await _frame_cost(90)
	for light in lights:
		light.visible = true
	print(("player_test: cost  %-16s frame -%5.2f ms  cpu -%5.2f ms  "
		+ "(%d pooled, %d lit)") % ["pooled lights",
		base["frame"] - without_lights["frame"],
		base["cpu"] - without_lights["cpu"], lights.size(), lit])
	await _wait(30)

	var casters := _flora_shadow_casters(world)
	for stand in casters:
		stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var without_shadows := await _frame_cost(90)
	print(("player_test: cost  %-16s frame -%5.2f ms  cpu -%5.2f ms  "
		+ "(%d casting stands)") % ["flora shadows",
		base["frame"] - without_shadows["frame"],
		base["cpu"] - without_shadows["cpu"], casters.size()])
	for stand in casters:
		stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	await _wait(30)

	# The floor: what a frame costs with no flora in it at all. Everything above
	# has to fit in the gap between this and the first line.
	for label: String in groups:
		for node: Node in nodes[label]:
			_set_group_running(node, false)
	var bare := await _frame_cost(120)
	print(("player_test: cost  %-16s frame=%6.2f ms  cpu=%6.2f ms  "
		+ "draws=%5.0f") % ["terrain only", bare["frame"], bare["cpu"],
		bare["draws"]])
	for label: String in groups:
		for node: Node in nodes[label]:
			_set_group_running(node, true)
	await _wait(60)

	# Moving, because the complaint is about flying and running rather than
	# standing. Streaming work only happens when the viewer crosses into ground
	# it has not surveyed, so a still measurement cannot see it at all — and it
	# is a different cost with a different cure from the drawing measured above.
	var flying := await _moving_cost()
	print(("player_test: cost  flying %-9s frame=%6.2f ms  worst=%6.2f ms%s")
		% ["everything", flying["frame"], flying["worst"], flying["phases"]])
	for label: String in groups:
		var group: Array[Node] = nodes[label]
		if group.is_empty():
			continue
		for node in group:
			_set_group_running(node, false)
		var off := await _moving_cost()
		for node in group:
			_set_group_running(node, true)
		print(("player_test: cost  flying %-9s frame -%5.2f ms  worst -%6.2f ms")
			% [label, flying["frame"] - off["frame"],
			flying["worst"] - off["worst"]])
	for label: String in groups:
		for node: Node in nodes[label]:
			_set_group_running(node, false)
	var quiet := await _moving_cost()
	print(("player_test: cost  flying %-9s frame=%6.2f ms  worst=%6.2f ms")
		% ["terrain", quiet["frame"], quiet["worst"]])
	for label: String in groups:
		for node: Node in nodes[label]:
			_set_group_running(node, true)

	# One field at a time, because "the biome flora" is thirteen independent
	# fields with tile sizes an order of magnitude apart and there is no reason
	# to expect them to share the bill evenly.
	var populations := world.find_child("BiomePopulations", true, false)
	if populations == null:
		return
	for child in populations.get_children():
		var cover := child as GroundCover
		if cover == null:
			continue
		_set_group_running(cover, false)
		var without := await _moving_cost()
		_set_group_running(cover, true)
		print(("player_test: cost  flying %-18s frame -%6.2f ms  tile=%4.0f m  "
			+ "species=%d  tiles=%d") % [cover.name,
			flying["frame"] - without["frame"], cover.tile_size,
			cover.species.size(), cover.tiles()])


## One pass of level flight over fresh ground, which is the state every flora
## field is most expensive in. Restarted from the same place each time so two
## passes cross the same tiles.
func _moving_cost() -> Dictionary:
	var spot := _grass_direction()
	var up := (_planet.global_transform.basis * spot).normalized()
	var north := Vector3.UP - up * Vector3.UP.dot(up)
	if north.length_squared() < 0.001:
		north = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	north = (_planet.global_transform.basis * north).normalized()
	_player._apply_stance(FLY)
	_player.global_transform = Transform3D(Basis.looking_at(north, up),
		_planet.standing_position(spot, 45.0))
	_player.velocity = Vector3.ZERO
	for _settle in 60:
		await get_tree().process_frame
	var worst := 0.0
	GroundCover.phase_cost.clear()
	var began := Time.get_ticks_usec()
	var previous := began
	for _tick in 240:
		_player.velocity = _player.global_transform.basis * Vector3.FORWARD * 60.0
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - previous) / 1000.0)
		previous = now
	var phases := ""
	for phase: StringName in GroundCover.phase_cost:
		phases += "  %s=%.2f ms" % [phase,
			float(GroundCover.phase_cost[phase]) / 240.0 / 1000.0]
	return {
		"frame": float(Time.get_ticks_usec() - began) / 240.0 / 1000.0,
		"worst": worst,
		"phases": phases,
	}


## Every GroundCover on the planet, however deeply it is nested.
func _cover_fields(world: Node) -> Array[GroundCover]:
	var found: Array[GroundCover] = []
	for node in world.find_children("*", "Node3D", true, false):
		var cover := node as GroundCover
		if cover != null:
			found.append(cover)
	return found


## Takes a whole field out of the frame: nothing drawn, nothing stepped. Both
## halves matter, because a hidden field still surveys and sows.
func _set_group_running(node: Node, running: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT if running \
		else Node.PROCESS_MODE_DISABLED
	var spatial := node as Node3D
	if spatial != null:
		spatial.visible = running


func _pooled_flora_lights(world: Node) -> Array[OmniLight3D]:
	var found: Array[OmniLight3D] = []
	for cover in _cover_fields(world):
		for child in cover.get_children(true):
			var light := child as OmniLight3D
			if light != null:
				found.append(light)
	return found


func _flora_shadow_casters(world: Node) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for cover in _cover_fields(world):
		for child in cover.get_children(true):
			var stand := child as MultiMeshInstance3D
			if stand == null:
				continue
			if stand.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				found.append(stand)
	return found


## Wall clock and process time over a run of frames, after letting whatever was
## just switched settle. The first frames after a change are never typical: a
## freed light or a hidden field leaves the renderer rebuilding its lists.
func _frame_cost(frames: int) -> Dictionary:
	for _settle in 30:
		await get_tree().process_frame
	var cpu := 0.0
	var worst := 0.0
	var draws := 0.0
	var began := Time.get_ticks_usec()
	for _tick in frames:
		await get_tree().process_frame
		var frame := float(Performance.get_monitor(Performance.TIME_PROCESS)) \
			+ float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		cpu += frame
		worst = maxf(worst, frame)
		draws += float(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return {
		"frame": float(Time.get_ticks_usec() - began) / float(frames) / 1000.0,
		"cpu": cpu / float(frames) * 1000.0,
		"worst": worst * 1000.0,
		"draws": draws / float(frames),
	}


## Why the ground flickers for the first minute of a game and then stops.
##
## `--churn` asks whether a settled quadtree stays settled and answers yes, but
## it spends ten seconds arriving before it starts counting, so it can only ever
## report the calm afterwards. The complaint is about the arrival itself: fly in
## from the spawn and the ground boils, wait a while and it stops, without
## anything having been touched.
##
## Two things could do that and they need opposite fixes. Either the flicker
## belongs to the flight — a fast camera over fine detail, which is aliasing and
## would stop the moment the camera stopped whatever the terrain was doing — or
## it belongs to the terrain still refining underneath, which would go on after
## the camera stopped and fade as the quadtree caught up. So this pins the
## camera the instant it arrives and holds it pinned for well over a minute. A
## pinned camera cannot alias. Anything left is the ground moving on its own,
## and if that decays, the wait is the whole story.
func _arrival_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
	if _player.hud != null:
		_player.hud.visible = false
	_still_planet(world)

	# Coarse to begin with, exactly as at the main menu, so the arrival below has
	# the same depths left to build that a real descent does. Measuring from an
	# already-warm tree would report the calm this is trying to catch the absence
	# of.
	var spot := _grass_direction()
	_look_down_from(spot, 9000.0)
	await _wait(150)
	print("player_test: arrival  from orbit: %s" % _statistics_line(0.0))

	# Awake just long enough to find the floor and bring the camera rig with it,
	# then pinned for the duration. Pinning any earlier than this leaves the eye
	# up at the altitude it was teleported from, drawing a perfectly steady
	# picture of the wrong place — which reads as a completely calm ground and is
	# the one result this cannot afford to report by accident.
	_player.set_physics_process(true)
	_player.set_process(true)
	_stand_on(spot)
	await _wait(40)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _shot("arrival_view")

	var camera := _player.get_viewport().get_camera_3d()
	var eye_was := camera.global_position if camera != null else Vector3.ZERO
	var elapsed := 0.0
	# Out past a minute, because "after a minute" is the claim being tested and a
	# table that stops at thirty seconds cannot distinguish settled from still
	# settling.
	for step in 12:
		var previous := await _frame_sample()
		var loud := 0
		var worst := 0
		var total := 0.0
		for _pass in 5:
			await _wait(1)
			var current := await _frame_sample()
			var difference := _frame_difference(previous, current)
			total += difference.x
			worst = maxi(worst, int(difference.y))
			loud = maxi(loud, int(difference.z))
			previous = current
		var drifted := 0.0
		if camera != null:
			drifted = camera.global_position.distance_to(eye_was)
			eye_was = camera.global_position
		elapsed += 5.0 / 60.0
		print("player_test: arrival  %s  mean=%5.2f worst=%3d loud=%4d eye=%.4f mm" % [
			_statistics_line(elapsed), total / 5.0, worst, loud,
			drifted * 1000.0])
		# Geometric, so the first seconds are sampled closely enough to catch a
		# fast decay and the tail still reaches past a minute without a hundred
		# rows of nothing happening.
		var hold := 12 * (step + 1)
		await _wait(hold)
		elapsed += float(hold) / 60.0


## What the first minute of a real game does that the rest of it does not.
##
## `--arrival` pins the eye on a spot this harness chose and reports a ground
## that goes still within half a second; `--speed` explains the shimmer that
## belongs to moving. Neither is the complaint. The screen recording is of a body
## hovering three metres up and not moving at all — the plate's direction,
## latitude and altitude are identical from one frame to the next — and a third
## of its pixels change by more than the eye forgives *every frame*, all of it on
## the edges of the dark ground blotches. So something in a freshly arrived world
## moves on its own, and wherever `--arrival` was standing is not somewhere it
## does.
##
## Read off that recording rather than searched for, the same way `--spot` was:
## the plate prints the planet-local direction under the body, and its clock is
## `phase * 24 + 12` hours, so 14:05 is phase 0.0868.
##
## Two tables. The first is the decay — pinned, sampled out past a minute, with
## the quadtree's own counters and the number of plants actually being drawn on
## every row, so whatever is still arriving is named beside the flicker instead
## of guessed at. The second is the attribution: one suspect removed per row,
## each measured on a world that has been made cold again, because a world that
## has finished arriving cannot demonstrate an arrival.
const BOOT_DIRECTION := Vector3(0.1336, 0.0272, 0.9907)
const BOOT_PHASE := 0.0868
## Metres of air under the body in the recording: ALT 67 m over GROUND 64 m.
const BOOT_HOVER := 3.0
## Loud pixels a pinned eye at the spawn angle is allowed. The fault this pass
## was written for produced seventeen thousand of them and the fix produces none,
## so anywhere in between is a gate; this is set high enough that a stray sparkle
## or a cloud edge cannot fail the run.
const BOOT_QUIET := 200

func _boot_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if _player.hud != null:
		_player.hud.visible = false
	# The body is not in the recording's frame and it breathes, so leaving it in
	# would only raise the noise floor. Nothing else is quietened: the sun turns,
	# the wind blows and the fields stream, which is the state under test.
	if _player.character != null:
		_player.character.visible = false
	if cycle != null:
		cycle.set_phase(BOOT_PHASE)

	var here := BOOT_DIRECTION.normalized()
	var fields := _streamed_fields(world)
	# Coarse first, so the arrival below has the same depths left to build that a
	# descent from the title screen does.
	_look_down_from(here, 9000.0)
	await _wait(120)
	print("player_test: boot  from orbit: %s" % _statistics_line(0.0))
	_hover_over(here)
	await _wait(2)
	_pin_eye()
	_look(-0.42)
	await _drawn(2)

	var up := (_planet.global_transform.basis * here).normalized()
	print("player_test: boot  sun %+.1f deg, %d cover fields, %d m from the ship" % [
		rad_to_deg(asin(clampf(up.dot(sun.global_basis.z), -1.0, 1.0)))
			if sun != null else 0.0,
		fields.size(), int(_ranged())])
	await _shot("boot_view")

	print("player_test: boot  (pinned eye; every row is the world moving on its own)")
	var elapsed := 0.0
	for step in 12:
		var reading := await _boot_sample(12)
		print("player_test: boot  %s plants=%7d  mean=%5.2f worst=%3d loud=%5d" % [
			_statistics_line(elapsed), _drawn_instances(world),
			reading.x, int(reading.y), int(reading.z)])
		# Geometric, so the first seconds are sampled closely enough to catch a
		# fast decay and the tail still reaches past a minute.
		var hold := 10 * (step + 1)
		await _drawn(hold)
		elapsed += float(hold + 13) / 60.0

	# The verdict, so this is an assertion and not only a table. A pinned eye at
	# the angle every game opens on has to draw a still picture; the fault this
	# was written for put seventeen thousand pixels over the threshold, and the
	# gate is two hundred, so nothing but a real regression can trip it.
	var settled := await _boot_sample(20)
	print("player_test: boot  %s  spawn-angle flicker mean=%.2f loud=%d" % [
		"PASS" if settled.z <= BOOT_QUIET else "FAIL",
		settled.x, int(settled.z)])

	await _boot_suspects(world, cycle, sun, fields)
	await _boot_sun_sweep(cycle, sun, here)


## One suspect removed per row, each on a cold world.
##
## Every row replants the fields and measures the seconds straight afterwards,
## which is the only window the fault exists in. A row is only worth reading
## beside its plant count: a field that came back empty is quiet for a reason
## that has nothing to do with the suspect.
func _boot_suspects(world: Node, cycle: CelestialCycle,
		sun: DirectionalLight3D, fields: Array[Node3D]) -> void:
	var ground := Planet.SURFACE_MATERIAL
	var plants := _plant_materials(world)
	var sway := {}
	var speed := {}
	for plant in plants:
		sway[plant] = plant.get_shader_parameter(&"wind_sway")
		speed[plant] = plant.get_shader_parameter(&"vat_playback_speed")

	var rows: Array[Dictionary] = [
		{"name": "as shipped, cold"},
		{"name": "flora frozen", "freeze": true},
		{"name": "flora hidden", "cover": false},
		{"name": "sun still", "turning": false},
		{"name": "no sun shadow", "shadow": false},
		{"name": "no ground pattern", "ground": [[&"pattern_amount", 0.0]]},
		{"name": "no procedural grain", "ground": [[&"detail_amount", 0.0]]},
		{"name": "no macro noise", "ground": [[&"macro_amount", 0.0]]},
		{"name": "no relief", "ground": [
			[&"bump_strength", 0.0], [&"texture_bump", 0.0]]},
		{"name": "as shipped, cold, last"},
	]

	print("player_test: boot  (cold world each row; the suspect is what is missing)")
	for row: Dictionary in rows:
		if cycle != null:
			cycle.period_seconds = 960.0 if row.get("turning", true) else 0.0
			cycle.set_phase(BOOT_PHASE)
		if sun != null:
			sun.shadow_enabled = row.get("shadow", true)
		for field in fields:
			field.visible = row.get("cover", true)
		var frozen: bool = row.get("freeze", false)
		for plant in plants:
			plant.set_shader_parameter(&"wind_sway",
				0.0 if frozen else sway[plant])
			plant.set_shader_parameter(&"vat_playback_speed",
				0.0 if frozen else speed[plant])
		var restore := {}
		for pair: Array in row.get("ground", []):
			restore[pair[0]] = ground.get_shader_parameter(pair[0])
			ground.set_shader_parameter(pair[0], pair[1])

		_recold(fields)
		# Long enough for the first tiles to land and short enough to still be
		# inside the fault. The decay table above is what says where that is.
		await _drawn(30)
		var reading := await _boot_sample(20)
		print("player_test: boot  %-24s plants=%7d  mean=%5.2f worst=%3d loud=%5d" % [
			row["name"], _drawn_instances(world),
			reading.x, int(reading.y), int(reading.z)])

		for key: StringName in restore:
			ground.set_shader_parameter(key, restore[key])
	for plant in plants:
		plant.set_shader_parameter(&"wind_sway", sway[plant])
		plant.set_shader_parameter(&"vat_playback_speed", speed[plant])


## Where in the sun's turn the shadow map is loud, and where it is quiet.
##
## The suspect table says the whole of this flicker is the shadow map answering
## the sun's own motion, which happens all day and would therefore be a game that
## flickers all day. It is not: it goes away after about a minute of play and does
## not come back. A minute is 22 degrees of a sixteen-minute day, so the only
## thing that can have changed in it is the angle — and the game always begins at
## the same one, because phase zero is noon over the landing site.
##
## So this holds the eye where it is, walks the sun through its turn, and reports
## the same measurement at each angle. A row that is loud only near the top of
## the sky explains both the complaint and the fact that nobody sees it again
## until tomorrow.
func _boot_sun_sweep(cycle: CelestialCycle, sun: DirectionalLight3D,
		here: Vector3) -> void:
	if cycle == null or sun == null:
		return
	var up := (_planet.global_transform.basis * here).normalized()
	print("player_test: boot  (sun angle sweep; the eye never moves)")
	# Half-minute steps out to a quarter of a turn, so the row a minute in — the
	# one the complaint says is already better — is in the table twice over.
	for step in 11:
		var phase := BOOT_PHASE + float(step) * 0.03125
		cycle.period_seconds = 960.0
		cycle.set_phase(phase)
		await _drawn(20)
		var reading := await _boot_sample(16)
		print("player_test: boot  %+5.1fs sun %+5.1f deg  mean=%5.2f worst=%3d loud=%5d" % [
			float(step) * 30.0,
			rad_to_deg(asin(clampf(up.dot(sun.global_basis.z), -1.0, 1.0))),
			reading.x, int(reading.y), int(reading.z)])
	cycle.set_phase(BOOT_PHASE)

	# And what the loud angle actually looks like with and without the map, so a
	# number that says "the shadow moved" can be read beside a picture that says
	# whether the dark it moved was a shadow at all.
	await _drawn(20)
	await _shot("boot_shadowed")
	sun.shadow_enabled = false
	await _drawn(20)
	await _shot("boot_unshadowed")
	sun.shadow_enabled = true


## Which shadow setting owns the noon speckle.
##
## Everything about the map's *contents* was ruled out before this pass was
## written. Twenty times the depth bias moved it by nothing, and switching every
## caster on the planet off — all six hundred and seventy terrain surfaces and
## three hundred and forty-nine other things — left the picture pixel-for-pixel as
## speckled as it was. Yet clearing [member Light3D.shadow_enabled] leaves it
## perfectly clean. So the ground is being darkened by the act of looking the
## shadow up, with an empty map, and what is left to blame is how that lookup is
## configured.
##
## Noon is the worst case for that shape and this is why: the eye is near the
## ground looking out at the horizon, so the frustum's footprint is a long thin
## wedge running away to the shadow distance, and a vertical sun flattens that
## wedge into a slab with almost no depth along the light. Every cascade is fitted
## to it, so the ortho range collapses and the comparison is left reading its own
## quantisation. Tilt the sun and the slab gains depth, which is the fade.
func _boot_shadow_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	if _player.hud != null:
		_player.hud.visible = false
	if _player.character != null:
		_player.character.visible = false
	if cycle == null or sun == null:
		return

	var here := BOOT_DIRECTION.normalized()
	cycle.set_phase(BOOT_PHASE)
	_look_down_from(here, 9000.0)
	await _wait(120)
	_hover_over(here)
	await _wait(2)
	_pin_eye()
	_look(-0.42)
	await _drawn(60)

	var shipped := {
		&"directional_shadow_mode": sun.directional_shadow_mode,
		&"directional_shadow_blend_splits": sun.directional_shadow_blend_splits,
		&"directional_shadow_max_distance": sun.directional_shadow_max_distance,
		&"directional_shadow_split_1": sun.directional_shadow_split_1,
		&"directional_shadow_split_2": sun.directional_shadow_split_2,
		&"directional_shadow_split_3": sun.directional_shadow_split_3,
		&"shadow_normal_bias": sun.shadow_normal_bias,
		&"shadow_blur": sun.shadow_blur,
		&"shadow_opacity": sun.shadow_opacity,
	}
	print("player_test: shadow  shipped mode=%d blend=%s max=%.0f splits %.3f/%.3f/%.3f normal=%.1f blur=%.1f" % [
		sun.directional_shadow_mode, sun.directional_shadow_blend_splits,
		sun.directional_shadow_max_distance, sun.directional_shadow_split_1,
		sun.directional_shadow_split_2, sun.directional_shadow_split_3,
		sun.shadow_normal_bias, sun.shadow_blur])

	var rows: Array[Dictionary] = [
		{"name": "as shipped"},
		{"name": "one cascade", "directional_shadow_mode": 0},
		{"name": "two cascades", "directional_shadow_mode": 1},
		{"name": "no split blending",
			"directional_shadow_blend_splits": false},
		{"name": "engine default splits", "directional_shadow_split_1": 0.1,
			"directional_shadow_split_2": 0.2,
			"directional_shadow_split_3": 0.5},
		{"name": "shadow distance 60", "directional_shadow_max_distance": 60.0},
		{"name": "shadow distance 400",
			"directional_shadow_max_distance": 400.0},
		{"name": "no normal bias", "shadow_normal_bias": 0.0},
		{"name": "normal bias 1", "shadow_normal_bias": 1.0},
		{"name": "normal bias 12", "shadow_normal_bias": 12.0},
		# The dial, swept rather than demonstrated once, because the answer is
		# not a radius: any value above zero engages the filter and the first
		# one that does is already at the noise floor. That is what says this is
		# a tap count and what makes the shipped 1.0 margin rather than blur.
		{"name": "no filter", "shadow_blur": 0.0},
		{"name": "filter 0.1", "shadow_blur": 0.1},
		{"name": "filter 0.25", "shadow_blur": 0.25},
		{"name": "filter 0.5", "shadow_blur": 0.5},
		{"name": "as shipped, last"},
	]

	for row: Dictionary in rows:
		for key: StringName in shipped:
			sun.set(key, row.get(key, shipped[key]))
		cycle.set_phase(BOOT_PHASE)
		await _drawn(24)
		var reading := await _boot_sample(16)
		print("player_test: shadow  %-24s mean=%5.2f worst=%3d loud=%5d" % [
			row["name"], reading.x, int(reading.y), int(reading.z)])
		await _shot("shadow_" + String(row["name"]).replace(" ", "_"))
	for key: StringName in shipped:
		sun.set(key, shipped[key])


## Throws away every plant on the planet so the fields have to grow them again.
##
## `_replant` alone is not enough while the eye is pinned: a field only surveys
## once the viewer has crossed a good part of a tile, and the viewer is not going
## to move, so a replanted field would sit empty for ever and the row would read
## as beautifully quiet. Clearing the survey's memory of where it last ran is
## what lets it notice that it has nothing.
func _recold(fields: Array[Node3D]) -> void:
	for field in fields:
		if not field.has_method("_replant"):
			continue
		field.call("_replant")
		field.set("_surveyed_at", Vector3.INF)
		field.set("_since_survey", INF)


## Plants actually being drawn, summed over every streamed stand on the planet.
##
## `GroundCover.standing()` unpacks each one into a Transform3D, which at these
## counts is seconds of work per call; the visible instance count is the same
## question answered off the buffer header.
func _drawn_instances(from: Node) -> int:
	var total := 0
	for node in _multimeshes(from):
		if node.multimesh == null or not node.is_visible_in_tree():
			continue
		var showing := node.multimesh.visible_instance_count
		total += node.multimesh.instance_count if showing < 0 else showing
	return total


## Every field that grows its own contents in the background, of either kind.
## [method _cover_fields] is the GroundCover-only subset.
func _streamed_fields(world: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in world.find_children("*", "Node3D", true, false):
		if node is GroundCover or node is FlowerTreeField:
			found.append(node as Node3D)
	return found


## The recording's stance: hovering, not standing, with the ground a few metres
## below and the body facing along its own north.
func _hover_over(direction: Vector3) -> void:
	var up := _planet.global_transform.basis * direction
	var north := Vector3.UP - direction * Vector3.UP.dot(direction)
	if north.length_squared() < 0.001:
		north = Vector3.RIGHT - direction * Vector3.RIGHT.dot(direction)
	_player._apply_stance(FLY)
	_player.global_transform = Transform3D(
		Basis.looking_at(_planet.global_transform.basis * north.normalized(), up),
		_planet.standing_position(direction, BOOT_HOVER))
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


## Mean, worst and loud-pixel count over [param frames] consecutive drawn frames,
## measured on the ground half of the picture.
func _boot_sample(frames: int) -> Vector3:
	var previous := await _frame_sample()
	var mean := 0.0
	var worst := 0.0
	var loud := 0.0
	for _index in frames:
		var frame := await _frame_sample()
		var moved := _ground_difference(previous, frame)
		mean += moved.x
		worst = maxf(worst, moved.y)
		loud = maxf(loud, moved.z)
		previous = frame
	return Vector3(mean / float(frames), worst, loud)


## How badly the ground aliases as a function of how fast the eye crosses it.
##
## `--arrival` rules the terrain itself out: pin the camera and the picture is
## dead still within half a second of landing, whatever the quadtree was doing
## beforehand. So the flicker belongs to the movement, and the question stops
## being "what is the ground doing" and becomes "how much does it cost to move".
##
## The footprint a pixel covers is worked out from screen derivatives, which
## describe the ground under this frame and know nothing whatever about where
## the eye was during the last one. That is exactly the quantity that goes wrong
## here: at a walk the sample point barely moves between frames and a mip chosen
## for area is also right in time, while at flying speed it jumps metres and the
## same mip is far too sharp to be stable. Hence a sweep by speed rather than a
## single number.
func _speed_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
	if _player.hud != null:
		_player.hud.visible = false
	_still_planet(world)
	_grass_spot = _grass_direction()
	var material := Planet.SURFACE_MATERIAL
	var shipped_footprint: float = material.get_shader_parameter(&"texture_footprint")
	await _wait(120)

	print("player_test: flight  as shipped, footprint %.1f" % shipped_footprint)
	# Metres the eye covers per frame, and the same figures in the units the
	# game is tuned in. A walk is the pace the ground was last quietened at and
	# is the row every other row is read against.
	for step: float in [0.0, SHIMMER_STEP, 0.6, 1.5, 3.0]:
		var result := await _shimmer_pass(step, "", 45)
		print("player_test: flight  %5.1f m/s  mean=%5.2f worst=%3d loud=%4d" % [
			step * 60.0, result.x, int(result.y), int(result.z)])

	# Whether widening the filter buys the fast rows anything, and what it costs
	# the still one. A value that quietens the flight and blurs the walk is not a
	# fix, which is why the sweep is measured at both ends.
	for footprint: float in [shipped_footprint, 8.0, 12.0, 18.0]:
		material.set_shader_parameter(&"texture_footprint", footprint)
		await _wait(10)
		var still := await _shimmer_pass(0.0, "")
		var walk := await _shimmer_pass(SHIMMER_STEP, "")
		var fast := await _shimmer_pass(1.5, "")
		print("player_test: flight  footprint %4.1f  still loud=%4d  walk loud=%4d  90 m/s loud=%4d" % [
			footprint, int(still.z), int(walk.z), int(fast.z)])
	material.set_shader_parameter(&"texture_footprint", shipped_footprint)

	# One suspect removed per row, all at flying speed, because the filter sweep
	# above says the photographed ground is not what is loudest here and a list
	# of things it might be instead is worth nothing beside a list of what
	# happens when each is taken away.
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	var suspects: Array = [
		["everything on", []],
		["no relief", [[&"bump_strength", 0.0]]],
		["no procedural grain", [[&"detail_amount", 0.0]]],
		["no macro noise", [[&"macro_amount", 0.0]]],
		["no photo colour", [[&"texture_blend", 0.0]]],
		["no photo relief", [[&"texture_bump", 0.0]]],
		["no photo occlusion", [[&"texture_occlusion", 0.0]]],
		["flat ground, all off", [
			[&"bump_strength", 0.0], [&"detail_amount", 0.0],
			[&"macro_amount", 0.0], [&"texture_blend", 0.0],
			[&"texture_bump", 0.0], [&"texture_occlusion", 0.0]]],
	]
	for row: Array in suspects:
		var changed: Array = row[1]
		var restore := {}
		for pair: Array in changed:
			restore[pair[0]] = material.get_shader_parameter(pair[0])
			material.set_shader_parameter(pair[0], pair[1])
		await _wait(10)
		# Warmed like the rows further down, so the two tables are describing the
		# same flight over the same ground and can be read against each other.
		var fast := await _shimmer_pass(1.5, "", 45)
		print("player_test: flight  90 m/s  %-22s mean=%5.2f loud=%5d" % [
			row[0], fast.x, int(fast.z)])
		for key: StringName in restore:
			material.set_shader_parameter(key, restore[key])

	# Separately, because it is not a ground setting at all. A shadow map is
	# fixed to the view, so every metre the eye travels re-rasterises it and its
	# edges crawl; that looks exactly like a ground that shimmers and no amount
	# of filtering the ground would touch it.
	if sun != null:
		var had_shadows := sun.shadow_enabled
		sun.shadow_enabled = false
		await _wait(10)
		var fast := await _shimmer_pass(1.5, "", 45)
		print("player_test: flight  90 m/s  %-22s mean=%5.2f loud=%5d" % [
			"no sun shadows", fast.x, int(fast.z)])
		sun.shadow_enabled = had_shadows

	# The fix, end to end and through the real plumbing: the body is moved, the
	# planet measures its own drift from that, and the ground reads the speed off
	# the material. Switched off by moving the band out of reach rather than by
	# writing `eye_speed`, because Planet rewrites that every frame and a row
	# that fought it for the value would be measuring whichever won.
	var shipped_from: float = material.get_shader_parameter(&"motion_calm_from")
	var shipped_to: float = material.get_shader_parameter(&"motion_calm_to")
	var shipped_keep: float = material.get_shader_parameter(&"motion_relief_keep")
	var shipped_rush: float = material.get_shader_parameter(&"motion_footprint")
	for row: Array in [
			["off", 1.0e9, shipped_to, shipped_keep, shipped_rush],
			["to 90, keep 0.12", shipped_from, 90.0, 0.12, shipped_rush],
			["to 55, keep 0.12", shipped_from, 55.0, 0.12, shipped_rush],
			["to 55, keep 0.00", shipped_from, 55.0, 0.0, shipped_rush],
			["to 55, keep 0.12, wide 24", shipped_from, 55.0, 0.12, 24.0],
		]:
		material.set_shader_parameter(&"motion_calm_from", row[1])
		material.set_shader_parameter(&"motion_calm_to", row[2])
		material.set_shader_parameter(&"motion_relief_keep", row[3])
		material.set_shader_parameter(&"motion_footprint", row[4])
		await _wait(10)
		# Warmed, so the planet's smoothed drift has actually reached the speed
		# the row claims to be measuring.
		var walk := await _shimmer_pass(SHIMMER_STEP, "", 45)
		var walk_speed: float = material.get_shader_parameter(&"eye_speed")
		var fast := await _shimmer_pass(1.5, "", 45)
		var fast_speed: float = material.get_shader_parameter(&"eye_speed")
		print("player_test: flight  calming %-26s walk loud=%5d at %4.1f m/s   fast loud=%5d at %5.1f m/s" % [
			row[0], int(walk.z), walk_speed, int(fast.z), fast_speed])
	material.set_shader_parameter(&"motion_calm_from", shipped_from)
	material.set_shader_parameter(&"motion_calm_to", shipped_to)
	material.set_shader_parameter(&"motion_relief_keep", shipped_keep)
	material.set_shader_parameter(&"motion_footprint", shipped_rush)


## One line of whatever the quadtree is currently doing, so a flicker number and
## the terrain's own activity can be read off the same row.
func _statistics_line(elapsed: float) -> String:
	var now: Dictionary = _planet.statistics()
	return "%5.1fs visible=%3d pending=%2d requests=%3d depth=%d built=%5d" % [
		elapsed, int(now["visible"]), int(now["pending"]),
		int(now["requests"]), int(now["depth"]), int(now["built"])]


## Whether the terrain settles when the viewer does.
##
## A quadtree is supposed to reach a fixed set of chunks for a fixed viewpoint
## and then stop. If it does not — if chunks keep being built and swapped while
## nobody moves — every swap changes the normals the ground texture is lit and
## projected by, and the ground flickers on its own. That looks like a texture
## fault and is not one, which is why this counts meshes rather than pixels.
func _churn_report() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	if cycle != null:
		cycle.period_seconds = 0.0
	_stand_on(_grass_direction())
	if _player.hud != null:
		_player.hud.visible = false
	# Well past the point where a settled quadtree would have finished.
	await _wait(600)
	_stand_on(_grass_direction())
	_player.velocity = Vector3.ZERO
	await _wait(240)

	var before: Dictionary = _planet.statistics()
	print("player_test: churn  standing still, planet should now be static")
	var last_built := int(before["built"])
	for tick in 8:
		await _wait(30)
		var now: Dictionary = _planet.statistics()
		var built := int(now["built"])
		print("player_test: churn  %.1fs visible=%3d pending=%2d requests=%3d depth=%d triangles=%6d built=+%d speed=%.3f m/s" % [
			(tick + 1) * 0.5, int(now["visible"]), int(now["pending"]),
			int(now["requests"]), int(now["depth"]), int(now["triangles"]),
			built - last_built, _player.velocity.length()])
		last_built = built
	var after: Dictionary = _planet.statistics()
	var grew := int(after["built"]) - int(before["built"])
	print("player_test: churn  %d chunk meshes built over four still seconds" % grew)
	if grew > 4:
		push_error("player_test: terrain keeps rebuilding itself while nobody moves")


## Whether the pooled lights reach anything. `--night-lights` only proves the
## nodes are on, and a light with energy that lands on nothing looks exactly the
## same from the outside as no light at all. So this photographs the ground at
## midnight with the pools on and again with them switched off, and reports how
## much of the picture the lights are actually responsible for.
func _night_cast_checks() -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false) as CelestialCycle
	var flowers := world.find_child("LandingFlowers", true, false) as GroundCover
	var trees := world.find_child("LandingFlowerTrees", true, false) as FlowerTreeField
	if cycle == null or flowers == null or trees == null:
		push_error("player_test: night flora nodes are incomplete")
		return

	var tree_transforms: Array = trees.get("_trees")
	if tree_transforms.is_empty():
		push_error("player_test: flower-tree field grew no trees")
		return
	var nearest := 0
	var nearest_distance := INF
	for index in tree_transforms.size():
		var stood: Transform3D = tree_transforms[index]
		if stood.origin.length_squared() < nearest_distance:
			nearest = index
			nearest_distance = stood.origin.length_squared()
	var nearest_tree: Transform3D = tree_transforms[nearest]
	var root := trees.to_global(nearest_tree.origin)
	var direction := _planet.to_local(root).normalized()
	var tangent := direction.cross(Vector3.UP if absf(direction.y) < 0.9
		else Vector3.RIGHT).normalized()
	direction = (direction + tangent * 7.0 / _planet.shape.radius).normalized()

	cycle.period_seconds = 0.0
	cycle.set_phase(0.5)
	_stand_on(direction)
	_player.hud.visible = false
	# Third person looking back at the tree, so both the crown and the ground
	# under it are in frame.
	_player._camera_mode = 2
	await _wait(420)
	_stand_on(direction)
	await _wait(120)

	# Differencing two frames only isolates the lights if nothing else in the
	# picture moves between them, and by default almost everything does: the
	# grass bends, the baked sway plays off TIME, both glows breathe and the
	# body idles. Left running, the sway alone swamps the measurement.
	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.0)
	for plant in _plant_materials(world):
		plant.set_shader_parameter(&"wind_sway", 0.0)
		plant.set_shader_parameter(&"vat_playback_speed", 0.0)
		plant.set_shader_parameter(&"night_pulse_amount", 0.0)
	for stand in _multimeshes(world):
		var crown := stand.material_override as ShaderMaterial
		if crown != null:
			crown.set_shader_parameter(&"night_pulse_amount", 0.0)
	flowers.glow_light_pulse_amount = 0.0
	trees.night_light_pulse_amount = 0.0
	if _player.animator != null:
		_player.animator.pause()
	await _wait(90)

	var pools: Array[OmniLight3D] = []
	pools.append_array(_omni_lights(flowers))
	pools.append_array(_omni_lights(trees))
	var eye := _player.global_position
	var closest := INF
	for light in pools:
		if light.light_energy > 0.01:
			closest = minf(closest, eye.distance_to(light.global_position))
	var environment := (world.find_child("WorldEnvironment", true, false) \
		as WorldEnvironment).environment
	var up := (eye - _planet.global_position).normalized()
	print("player_test: night cast  %d pooled lights, nearest lit one %.1f m away" % [
		pools.size(), closest])
	print("player_test: night cast  sun overhead %.3f, ambient energy %.3f" % [
		up.dot(cycle.sun.global_basis.z.normalized()),
		environment.ambient_light_energy])

	var lit_frame := await _frame("night_cast_lit")
	# Off at the source rather than by hiding: the fields drive these every
	# frame, so the pools have to stop being driven before they stop shining.
	flowers.set_process(false)
	trees.set_process(false)
	for light in pools:
		light.light_energy = 0.0
		light.visible = false
	await _wait(6)
	var dark_frame := await _frame("night_cast_dark")
	_report_cast(lit_frame, dark_frame)


## What the pools added, per channel and as a picture. Mean luminance over a
## whole frame is a poor test here — most of it is sky — so this also reports
## the share of ground pixels that changed at all, and saves the amplified
## difference so the spill can be looked at rather than argued about.
func _report_cast(lit: Image, dark: Image) -> void:
	var width := lit.get_width()
	var height := lit.get_height()
	var difference := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	var added := Color(0.0, 0.0, 0.0)
	var touched := 0
	var counted := 0
	# The lower two thirds, which is the ground rather than the sky.
	var from := height / 3
	for y in height:
		for x in width:
			var change := lit.get_pixel(x, y) - dark.get_pixel(x, y)
			difference.set_pixel(x, y, Color(
				clampf(change.r * 6.0, 0.0, 1.0),
				clampf(change.g * 6.0, 0.0, 1.0),
				clampf(change.b * 6.0, 0.0, 1.0)))
			if y < from:
				continue
			counted += 1
			added += Color(absf(change.r), absf(change.g), absf(change.b))
			if maxf(maxf(absf(change.r), absf(change.g)), absf(change.b)) > 0.02:
				touched += 1
	var path := ProjectSettings.globalize_path(SHOT_DIR + "night_cast_added.png")
	difference.save_png(path)
	print("player_test: night cast  ground gained rgb (%.4f %.4f %.4f) over %.1f%% of the ground" % [
		added.r / counted, added.g / counted, added.b / counted,
		100.0 * touched / maxf(float(counted), 1.0)])
	if touched * 20 < counted:
		push_error("player_test: pooled flora lights reached under a twentieth of the ground")


## Runs away from the landing site on every compass heading and separates the
## three things "running in place" can mean: the target keeps rising while the
## collider is stopped, the collider moves while the visible clip is stopped,
## or both are moving and the camera makes the motion hard to read.
func _stall_survey() -> void:
	for heading in 8:
		Input.action_release("move_forward")
		Input.action_release("sprint")
		await _place(RUN_START, RUN_YAW + heading * TAU / 8.0)
		await _wait(20)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var before := _player.global_position
		print("player_test: stall heading %d" % heading)
		for second in 8:
			await _wait(60)
			var travelled := before.distance_to(_player.global_position)
			before = _player.global_position
			var animation_position := -1.0
			if _player.animator != null:
				animation_position = _player.animator.current_animation_position
			print("player_test:   %ds moved=%6.1fm actual=%6.1f target=%6.1f floor=%-5s wall=%-5s stance=%-6s clip=%-5s clip_at=%4.2f" % [
				second + 1, travelled, _player._horizontal_speed(), _player._run_speed,
				_player.is_on_floor(), _player.is_on_wall(),
				_stance_name(_player._stance), _player._clip, animation_position])
		Input.action_release("move_forward")
		Input.action_release("sprint")


## Exact route reported from the coordinate plate: 6.87 S, 4.40 W, aiming due
## north at 6.64 S on the same longitude. This crosses one full-detail 1.5 m
## height-field spacing per tick at about 90 m/s, the boundary that exposed the
## grounded anti-tunnelling rewind.
func _reported_stall() -> void:
	var latitude := deg_to_rad(-6.87)
	var longitude := deg_to_rad(-4.40)
	var direction := Vector3(
		cos(latitude) * sin(longitude),
		sin(latitude),
		cos(latitude) * cos(longitude)).normalized()
	var north := (Vector3.UP - direction * direction.y).normalized()
	var up := _planet.global_transform.basis * direction
	# The two-decimal reticle readout rounds the slight westward component away.
	# In the supplied view the crosshair is a little left of due north.
	var heading := north.rotated(direction, deg_to_rad(15.0))
	var forward := _planet.global_transform.basis * heading
	Input.action_release("jump")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_player._apply_stance(STAND)
	_player._run_speed = _player.walk_speed
	_player.global_transform = Transform3D(
		Basis.looking_at(forward, up), _planet.standing_position(direction, 0.1))
	_player.velocity = Vector3.ZERO
	await _wait(120)
	# Probe the exact boundary directly before the gradual run reaches whatever
	# terrain feature happens to lie farther along this heading. The old guard
	# rewound this 1.67 m stride to zero because it began on the field.
	_player._run_speed = 100.0
	_player.velocity = forward * 100.0
	Input.action_press("move_forward")
	var probe_from := _player.global_position
	await get_tree().physics_frame
	var probe_stride := probe_from.distance_to(_player.global_position)
	print("player_test: reported 100 m/s probe moved %.3f m" % probe_stride)
	if probe_stride < 1.0:
		push_error("player_test: grounded 100 m/s stride was rewound")
	Input.action_release("move_forward")
	_player.global_transform = Transform3D(
		Basis.looking_at(forward, up), _planet.standing_position(direction, 0.1))
	_player.velocity = Vector3.ZERO
	_player._run_speed = _player.walk_speed
	await _wait(20)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var before := _player.global_position
	for second in 20:
		await _wait(60)
		var travelled := before.distance_to(_player.global_position)
		before = _player.global_position
		print("player_test: reported stall %2ds moved=%6.1fm actual=%6.1f target=%6.1f floor=%s" % [
			second + 1, travelled, _player._horizontal_speed(), _player._run_speed,
			_player.is_on_floor()])
		if _player._horizontal_speed() >= 90.0 and travelled < 45.0:
			push_error("player_test: grounded run rewound at %.0f m/s" % _player._horizontal_speed())
			break
		if _player._stance == CRASH:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")


## Kerbs of rising height walked into head-on. Anything up to the step limit
## should be climbed without stopping; anything above it should still block.
func _step_checks() -> void:
	var heights := [0.12, 0.22, 0.3, 0.36, 0.5]
	for index in heights.size():
		var height: float = heights[index]
		var base := Vector3(14.0, 0.0, -14.0 + index * 5.0)
		_add_kerb(base, height)
		await _place(base + Vector3(0.0, 0.4, 2.4), 0.0)
		await _wait(20)
		var floor_at := _altitude()
		Input.action_press("move_forward")
		var peak := 0.0
		var clips := {}
		# Whether the body ever met the kerb as a wall, and whether the step
		# probe ever fired. Without these a kerb that is never reached and a kerb
		# that is reached and not climbed report identically, and the two have
		# nothing to do with one another.
		var walled := false
		var stepped := false
		# Short enough to stop on top of the kerb rather than cross it.
		for _i in 34:
			await get_tree().physics_frame
			peak = maxf(peak, _altitude() - floor_at)
			walled = walled or _player.is_on_wall()
			stepped = stepped or _player._step_offset < -0.001
			# A step that dropped ground contact would show up here as Fall.
			clips[_player._clip] = true
		Input.action_release("move_forward")
		await _wait(10)
		var risen := _altitude() - floor_at
		print("player_test: kerb %.2f  rise=%.3f  peak=%.3f  wall=%-3s step=%-3s clips=%-16s climbed=%s" % [
			height, risen, peak, "yes" if walled else "no",
			"yes" if stepped else "no", ",".join(clips.keys()),
			"yes" if risen > height - 0.08 else "no",
		])
		if is_equal_approx(height, 0.3):
			_player._camera_mode = 2
			await _wait(40)
			await _shot("kerb_step_up")
			_player._camera_mode = 0
			await _wait(20)


func _add_kerb(base: Vector3, height: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, height, 3.0)
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	visual.mesh = box_mesh
	body.add_child(visual)
	get_tree().current_scene.add_child(body)
	# On the ground that is there, not on the site's plane. The site's frame is a
	# single tangent plane and the terrain under this course rolls by the better
	# part of a metre across the twenty metres it is laid out over, which buried
	# the low kerbs and stood the tall ones on air. Every kerb then reported the
	# hillside it was sunk into rather than its own height — and with the body
	# floating a decimetre over the ground as well, the two errors cancelled
	# often enough to look like a working test.
	var spot: Vector3 = _ground * base
	var up := _planet.up_at(spot)
	var ground := _planet.standing_position((spot - _planet.global_position).normalized())
	body.global_transform = Transform3D(_ground.basis, ground + up * (height * 0.5))


## Walks into every prop at the landing site head-on, then turns 55 degrees and
## keeps walking. That second leg is the tell: a player wedged against a prop
## stops moving entirely, while a clean contact slides them around it.
func _prop_checks() -> void:
	for prop in _site_props():
		# The site's frame, so the approach runs along its ground rather than
		# along a world axis that points into the sky here.
		var at := _ground.affine_inverse() * prop.global_position
		await _place(Vector3(at.x, 0.4, at.z + 4.0), 0.0)
		await _wait(20)
		Input.action_press("move_forward")
		var peak := 0.0
		for _i in 70:
			await get_tree().physics_frame
			peak = maxf(peak, _altitude())
		var contact := _player.global_position
		_player.global_basis = _player.global_basis.rotated(_player.global_basis.y, deg_to_rad(55.0))
		await _wait(60)
		Input.action_release("move_forward")
		print("player_test: prop %-9s stopped_at=%5.2f  rode_up=%.2f  alt=%5.2f  slid_around=%5.2f" % [
			prop.name,
			contact.distance_to(prop.global_position),
			peak, _altitude(), contact.distance_to(_player.global_position),
		])


## Everything standing on the landing site. The world used to be a flat floor
## with a `Props` node on it; on the planet the anchor is the only place a prop
## can be, so the anchor's children are the props.
func _site_props() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var site := get_tree().current_scene.find_child("LandingSite", true, false)
	if site == null:
		return found
	for child in site.get_children():
		if child is Node3D:
			found.append(child as Node3D)
	return found


## Foot and hip heights sampled across each clip. The rest sole sits at bone
## height 0.103, so a grounded clip should hold its planted foot near that and
## never dip far below it.
func _clip_report() -> void:
	await _place(CLEAR, 0.0)
	await _wait(20)
	var animator: AnimationPlayer = _player.animator
	var skeleton: Skeleton3D = _player.character.find_child("Skeleton3D", true, false)
	var feet := [CharacterRig.find_bone(skeleton, &"LeftFoot"),
		CharacterRig.find_bone(skeleton, &"RightFoot")]
	var hips := CharacterRig.find_bone(skeleton, &"Hips")
	for clip in animator.get_animation_list():
		var length := animator.get_animation(clip).length
		var lowest := [1.0e9, 1.0e9]
		var planted := [-1.0e9, -1.0e9]
		var hip_low := 1.0e9
		for step in 24:
			animator.play(clip, 0.0)
			animator.seek(length * step / 24.0, true)
			await get_tree().process_frame
			for i in 2:
				var y: float = skeleton.get_bone_global_pose(feet[i]).origin.y
				lowest[i] = minf(lowest[i], y)
				planted[i] = maxf(planted[i], y)
			hip_low = minf(hip_low, skeleton.get_bone_global_pose(hips).origin.y)
		print("player_test: %-11s foot_low=(%.3f, %.3f) foot_high=(%.3f, %.3f) hips_low=%.3f" % [
			clip, lowest[0], lowest[1], planted[0], planted[1], hip_low,
		])


## Freezes the rig at a few points in every baked clip, from a fixed side-on
## camera, so the poses can be judged without playing the game.
func _clip_sheet() -> void:
	await _place(CLEAR, 0.0)
	# Third person, so the player script keeps its own mesh visible.
	_player._camera_mode = 2
	await _wait(30)

	# Props out of the way, so anything coloured showing up on the character is
	# the character's own shading rather than scenery seen through it.
	for prop in _site_props():
		prop.visible = false

	# Parented to the player: the review positions below are body-relative, and
	# on a sphere the body's own frame is the only one they mean anything in.
	var review := Camera3D.new()
	_player.add_child(review)
	review.fov = 34.0
	review.position = Vector3(2.6, 0.8, -0.3)
	_aim(review, Vector3(0.0, 0.68, 0.0))
	review.current = true
	await _wait(2)

	var animator: AnimationPlayer = _player.animator
	print("player_test: clips %s" % [animator.get_animation_list()])
	for clip in animator.get_animation_list():
		var length := animator.get_animation(clip).length
		for step in 3:
			var at := length * (0.08 + 0.42 * step)
			animator.play(clip, 0.0)
			animator.seek(at, true)
			animator.speed_scale = 0.0
			await _shot("clip_%s_%d" % [clip, step])

	# Head-on as well, which is the view that shows how wide the arms are held.
	review.fov = 34.0
	review.position = Vector3(0.0, 0.8, -2.6)
	_aim(review, Vector3(0.0, 0.68, 0.0))
	for clip in ["Idle", "Walk", "Run", "CrouchIdle"]:
		var length := animator.get_animation(clip).length
		for step in 2:
			animator.play(clip, 0.0)
			animator.seek(length * (0.08 + 0.42 * step), true)
			await _shot("front_%s_%d" % [clip, step])

	review.fov = 30.0
	review.position = Vector3(1.15, 0.45, -0.25)
	_aim(review, Vector3(0.0, 0.44, 0.0))
	for clip in ["Run", "CrouchIdle", "Walk"]:
		animator.play(clip, 0.0)
		animator.seek(animator.get_animation(clip).length * 0.5, true)
		await _shot("hips_%s" % clip)
	animator.speed_scale = 1.0
	review.queue_free()
	for prop in _site_props():
		prop.visible = true


## Points a review camera at a spot in the player's own frame. Both halves of this
## are corrections for standing on a sphere, and each one on its own produced a
## sheet of unusable screenshots:
##
## - `look_at` takes a **world** point, and this world's origin is the planet's
##   centre 8 km underground. Aiming at a bare `Vector3(0, 0.68, 0)` — which is what
##   you write when the origin is the ground at the player's feet — pointed every
##   shot straight down into the core, and the whole sheet came out as the inside of
##   a hillside.
## - Its up hint defaults to **world** up, which anywhere but one point on the
##   planet is not the body's up. Left alone it rolled the head-on view by ninety
##   degrees and laid the character on its side.
func _aim(camera: Camera3D, at: Vector3) -> void:
	camera.look_at(_player.to_global(at), _player.global_basis.y)


func _movement_checks() -> void:
	await _place(Vector3(0.0, 0.4, 12.0), PI)
	_report("idle")

	Input.action_press("move_forward")
	await _wait(45)
	_report("walk")
	# Only as long as shift's step up to a sprint. Holding it winds the run on
	# past that, and past that there is not enough floor here to hold the run or
	# the slide it earns: `_run_checks` has the strip for it.
	Input.action_press("sprint")
	await _wait(10)
	_report("sprint")
	Input.action_release("sprint")

	Input.action_press("crouch")
	await _wait(5)
	_report("slide start")
	await _wait(35)
	_report("slide mid")
	await _wait(60)
	_report("slide over")
	Input.action_release("crouch")
	Input.action_release("move_forward")

	await _place(Vector3(0.0, 0.4, 12.0), PI)
	Input.action_press("crouch")
	Input.action_press("move_forward")
	await _wait(45)
	_report("crouch walk")
	Input.action_release("crouch")
	Input.action_release("move_forward")
	await _wait(20)
	_report("stood back up")

	await _place(Vector3(0.0, 0.4, 12.0), PI)
	await _wait(25)
	Input.action_press("jump")
	await _wait(3)
	Input.action_release("jump")
	await _wait(12)
	_report("jump rising")
	await _wait(70)
	_report("landed")

	# A normal hop is home before the late pose is due. Keep a body clear of the
	# ground long enough to prove the one-second hold and the slow crossfade both
	# finish, rather than merely proving that the GLB contains the clip.
	await _place(Vector3(0.0, 80.0, 12.0), PI)
	await _wait(35)
	if _player._clip == "AirRun":
		push_error("player_test: long-air stride started at %.2fs, before its one-second hold"
			% _player._airborne_time)
	await _wait(51)
	_report("long-air stride")
	if _player._clip != "AirRun":
		push_error("player_test: long fall stayed in %s after %.2fs airborne" % [
			_player._clip, _player._airborne_time])
	await _place(Vector3(0.0, 0.4, 12.0), PI)

	# Pressed 4 frames before touchdown, which only becomes a jump if the input
	# buffer survived the airborne frames.
	await _place(Vector3(0.0, 0.55, 12.0), PI)
	await _wait(2)
	Input.action_press("jump")
	await _wait(3)
	Input.action_release("jump")
	await _wait(12)
	_report("buffered jump")
	await _wait(70)


## The wind-up, what survives letting go of shift, the skid when forward is
## released, what a wall does to it, and the slide and the jump it buys. Watch
## `run=`: that is the speed the legs are being asked for, and the gap between it
## and `speed=` is how far behind the body is running.
func _run_checks() -> void:
	_crash_policy_checks()
	# The baseline the run is measured against: what the terrain costs and how
	# much of it is standing when nobody is going anywhere.
	await _place(RUN_START, RUN_YAW)
	await _wait(180)
	var rest := _planet.statistics()
	print("player_test: standing still     colliders=%3d  pending=%2d  lod=%5.1f ms  visible=%d" % [
		rest["bodies"], rest["pending"], rest["update_ms"], rest["visible"]])

	await _wind_up(0.0)
	# Counted, not sampled: a run that skips off the ground loses its ground
	# acceleration for those frames, and a single report can easily land on a
	# frame either side of that. It is also the honest test of whether the
	# terrain's collision chunks keep up — they are built on worker threads
	# within `Planet.collision_range` of the camera, and a flat-out run crosses
	# that range in a little over a second.
	var airborne := 0
	for second in 6:
		var missed := 0
		for _i in 60:
			await get_tree().physics_frame
			missed += 0 if _player.is_on_floor() else 1
		airborne += missed
		var stats := _planet.statistics()
		print("player_test: winding up %ds  speed=%6.1f  off_ground=%2d/60  colliders=%3d  pending=%2d  lod=%5.1f ms" % [
			second + 1, _player._horizontal_speed(), missed,
			stats["bodies"], stats["pending"], stats["update_ms"]])
	print("player_test: %-22s %d of 360 frames off the ground, %.0f m out" % [
		"wind-up contact", airborne, _ranged()])
	var wound: float = _player._horizontal_speed()
	if _fell_through("the wind-up"):
		pass
	elif wound < _player.run_top_speed * 0.9:
		push_error("player_test: six seconds of shift only reached %.0f m/s" % wound)

	# The whole point of the wind-up: shift buys the speed, and letting go of it
	# does not hand the speed back.
	Input.action_release("sprint")
	await _wait(120)
	_report_run("shift released, 2s")
	if _player._horizontal_speed() < wound * 0.95:
		push_error("player_test: the run bled off after shift was released")

	# Forward released. Not a stop, a skid.
	Input.action_release("move_forward")
	var from := _player.global_position
	await _wait(15)
	_report_run("coasting")
	var frames := 0
	while _player._horizontal_speed() > 0.5 and frames < 600:
		await get_tree().physics_frame
		frames += 1
	print("player_test: %-22s skidded %.0f m in %.2fs" % [
		"coast to a stop", from.distance_to(_player.global_position), frames / 60.0])

	# An unwalkable slope met before the run becomes a crash. This is the case
	# that used to leave the target speed winding upward while the capsule was
	# stationary: it was too steep to walk, but the run-break threshold only
	# recognized an almost vertical wall.
	await _wind_up(0.0)
	var slope := _slope_ahead(8.0)
	frames = 0
	while not _player.is_on_wall() and frames < 180:
		await get_tree().physics_frame
		frames += 1
	await _wait(8)
	_report_run("blocked by steep slope")
	if frames >= 180:
		push_error("player_test: never reached the steep-slope obstruction")
	elif _player._run_speed > _player.sprint_speed:
		push_error("player_test: target speed kept rising while blocked by a steep slope")
	elif _player._stance == CRASH:
		push_error("player_test: a low-speed slope contact caused a crash")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	slope.queue_free()

	# Into a wall flat out. `move_and_slide` alone would keep every metre per
	# second of it and just turn the run sideways.
	await _wind_up(6.0)
	var wall := _wall_ahead(250.0)
	_report_run("approaching the wall")
	frames = 0
	while not _player.is_on_wall() and frames < 900:
		await get_tree().physics_frame
		frames += 1
	await _wait(8)
	_report_run("hit the wall" if frames < 900 else "never met the wall")
	if _fell_through("the wall run"):
		pass
	elif _player._run_speed > _player.sprint_speed:
		push_error("player_test: the run survived a wall at %.0f m/s" % _player._run_speed)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	wall.queue_free()

	await _wind_up(6.0)
	var entry: float = _player._horizontal_speed()
	from = _player.global_position
	Input.action_press("crouch")
	await _wait(4)
	_report_run("slide start")
	var span: float = _player._slide_span
	frames = 0
	while _player._stance == SLIDE and frames < 900:
		await get_tree().physics_frame
		frames += 1
	Input.action_release("crouch")
	print("player_test: %-22s from %.0f m/s, ran %.2fs of a %.2fs span for %.0f m" % [
		"slide", entry, frames / 60.0, span, from.distance_to(_player.global_position)])
	await _wait(12)
	_report_run("slide over")
	Input.action_release("move_forward")
	Input.action_release("sprint")

	# The same jump from a standstill and flat out, which is the only honest way
	# to read "proportional to the run".
	var standing := await _measure_jump(false)
	var flying := await _measure_jump(true)
	print("player_test: %-22s standing %.2f m, flat out %.2f m (%.1fx)" % [
		"jump apex", standing, flying, flying / maxf(standing, 0.01)])
	if standing < 2.8:
		push_error("player_test: higher standing jump only reached %.2f m" % standing)
	elif _fell_through("the flat-out jump"):
		pass
	elif flying <= standing * 1.5:
		push_error("player_test: a flat-out jump is no higher than a standing one")

	await _run_shots()
	await _place(Vector3(0.0, 0.4, 12.0), PI)
	await _wait(20)


## The three crash rules without relying on procedural terrain to happen to make
## the exact normal each rule needs. Physical wall and landing checks below
## still exercise the collision path; these cases pin down its policy.
func _crash_policy_checks() -> void:
	var up := _player._up()
	var across := _player.global_basis.x.normalized()
	var wall := -across
	var steep_face := 0.23
	var steep := (up * steep_face
		- across * sqrt(1.0 - steep_face * steep_face)).normalized()
	var cases := [
		["flight into flat ground", up, -up * 40.0, true, true],
		["flight into a wall", wall, across * 40.0, true, true],
		["run into a steep face", steep, across * 40.0, false, true],
		["airborne into a steep face", steep, across * 40.0, false, true],
		["run onto flat ground", up, -up * 100.0, false, false],
		["airborne onto flat ground", up, -up * 100.0, false, false],
		["slow contact with a wall", wall, across * 8.0, true, false],
	]
	var passed := 0
	for item in cases:
		var result: bool = _player._impact_crashes(item[1], item[2], item[3])
		if result != item[4]:
			push_error("player_test: crash policy '%s' expected %s, got %s" % [
				item[0], item[4], result])
		else:
			passed += 1
	print("player_test: crash policy         %d/%d cases passed" % [passed, cases.size()])


## How well the feet stay on the ground while crossing it, at each of the three
## speeds.
##
## A run over rolling terrain should ride the surface. What it did instead was
## hop: every small crest threw the body off the ground, and it hung there —
## gravity was suspended for anything the height field called grounded — until
## the ground came back up to it. From inside the game that reads as a bounce
## with no cause, and no screenshot shows it. These two numbers do: the share of
## frames with no floor under the capsule, and how far off the ground the worst
## of them got.
const CLING_FRAMES := 240

## Set by `--trace`, which adds a frame-by-frame dump to the sprint leg.
var _tracing := false

func _cling_checks() -> void:
	_tracing = "--trace" in OS.get_cmdline_user_args()
	await _measure_cling("walk", 0.0, false)
	await _measure_cling("sprint", 1.5, true)
	_tracing = false
	await _measure_cling("flat out", 6.0, true)


func _measure_cling(label: String, wind: float, sprinting: bool) -> void:
	Input.action_release("crouch")
	await _place(RUN_START, RUN_YAW)
	await _wait(20)
	Input.action_press("move_forward")
	if sprinting:
		Input.action_press("sprint")
	if wind > 0.0:
		await _wait(roundi(wind * 60.0))
	var airborne := 0
	var worst := 0.0
	var total := 0.0
	var top := 0.0
	# Bouncing and flying are the same share of airborne frames arranged
	# differently: a hundred one-frame hops is the fault being chased here, and
	# one hundred-frame arc off a ridge is the run doing what it should. Only the
	# count of take-offs and the length of the longest tells them apart.
	var takeoffs := 0
	var longest := 0
	var aloft := 0
	var was_down := true
	for i in CLING_FRAMES:
		await get_tree().physics_frame
		# Only upward counts as being off the ground. A frame or two a couple of
		# millimetres inside the collider is the safe margin doing its job, and
		# averaging it in would flatter the result.
		var gap := maxf(_altitude(), 0.0)
		worst = maxf(worst, gap)
		total += gap
		top = maxf(top, _player.velocity.length())
		var down := _player.is_on_floor()
		if down:
			aloft = 0
		else:
			airborne += 1
			aloft += 1
			longest = maxi(longest, aloft)
			if was_down:
				takeoffs += 1
		was_down = down
		# The shape of the bounce, not just its size. A sawtooth — climb, drop,
		# repeat — is the body being thrown; noise a millimetre wide is the
		# capsule losing contact on ground it is still resting on, and the two
		# want completely different fixes.
		if _tracing and i < 90:
			print("player_test:   trace %-9s %3d  gap %6.3f m  rise %7.3f m/s  floor %s" % [
				label, i, _altitude(),
				_player.velocity.dot(_planet.up_at(_player.global_position)),
				"yes" if _player.is_on_floor() else "no "])
	Input.action_release("move_forward")
	Input.action_release("sprint")
	print("player_test: cling %-9s top %6.1f m/s   airborne %5.1f%% over %3d take-offs, longest %3d frames   off the ground: mean %.3f m, worst %.3f m" % [
		label, top, 100.0 * airborne / float(CLING_FRAMES), takeoffs, longest,
		total / float(CLING_FRAMES), worst])


## Side on to the run at a walk, a sprint and flat out, plus the readout the
## player actually sees. The clip sheet cannot cover this: the lean is not in the
## clip, it is applied over the top of it.
func _run_shots() -> void:
	_player._camera_mode = 2
	_player.hud.visible = false
	# Parented to the player: at 200 m/s a camera placed in the world is a body
	# length behind by the time the frame is drawn.
	var review := Camera3D.new()
	_player.add_child(review)
	review.fov = 40.0
	review.position = Vector3(3.4, 0.72, 0.0)
	review.rotation.y = PI * 0.5
	review.current = true

	await _place(RUN_START, RUN_YAW)
	Input.action_press("move_forward")
	await _wait(45)
	await _rig_shot(review, "run_walk")
	Input.action_press("sprint")
	await _wait(10)
	await _rig_shot(review, "run_sprint")
	await _wait(300)
	await _rig_shot(review, "run_flat_out")

	review.current = false
	review.queue_free()
	_player.hud.visible = true
	_player._camera_mode = 0
	await _wait(20)
	await _shot("run_hud")
	Input.action_release("sprint")
	Input.action_release("move_forward")


## Runs out from the landing site with shift held for `seconds`, and leaves both
## keys down so the caller can carry the run into whatever it is measuring.
func _wind_up(seconds: float) -> void:
	Input.action_release("crouch")
	await _place(RUN_START, RUN_YAW)
	await _wait(20)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	if seconds > 0.0:
		await _wait(roundi(seconds * 60.0))


## Height gained by one jump, from a standstill or from the top of a run.
func _measure_jump(wound_up: bool) -> float:
	if wound_up:
		await _wind_up(6.0)
	else:
		await _place(RUN_START, RUN_YAW)
		await _wait(25)
	# Against the ground rather than against world Y, which is a direction the
	# run is mostly travelling sideways to by the time it is flat out.
	var base := _altitude()
	var crashes := _player._crashes
	Input.action_press("jump")
	await _wait(3)
	Input.action_release("jump")
	var apex := base
	for _i in 240:
		await get_tree().physics_frame
		apex = maxf(apex, _altitude())
		if _player.is_on_floor() and _i > 20:
			break
	Input.action_release("move_forward")
	Input.action_release("sprint")
	if _player._crashes != crashes:
		push_error("player_test: a clean %s landing caused a crash" % [
			"flat-out jump" if wound_up else "standing jump"])
	return apex - base


## Drops a wall across the player's path, [param metres] ahead of wherever they
## are now and square to the ground under them. Placed live rather than in
## advance, because a run that is flat out is a kilometre from the landing site
## and the site's frame has the ground 60 m below where it actually is by then.
func _wall_ahead(metres: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Tall and sunk well below the feet: over 250 m the planet's own curve drops
	# the ground four metres, and terrain adds more, so a wall sized to the
	# player's height would be flown under rather than hit.
	box.size = Vector3(120.0, 90.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	get_tree().current_scene.add_child(body)
	var basis := _player.global_basis
	body.global_transform = Transform3D(basis,
		_player.global_position - basis.z * metres + basis.y * 15.0)
	return body


## An obstacle just steeper than the controller accepts as floor. Its near-face
## normal is 0.23 of the way up, below `FLOOR_FACE`'s 0.259 line: too steep to
## walk, but still short of the run-break threshold.
func _slope_ahead(metres: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 0.6)
	shape.shape = box
	body.add_child(shape)
	get_tree().current_scene.add_child(body)
	var basis := _player.global_basis.rotated(_player.global_basis.x, -asin(0.23))
	body.global_transform = Transform3D(basis,
		_player.global_position - _player.global_basis.z * metres
			+ _player.global_basis.y * 1.5)
	return body


func _report_run(label: String) -> void:
	print("player_test: %-22s stance=%-6s speed=%6.1f run=%6.1f alt=%5.2f rise=%6.1f floor=%-5s blend=%.2f lean=%5.1f clip=%s" % [
		label,
		_stance_name(_player._stance),
		_player._horizontal_speed(),
		_player._run_speed,
		_altitude(),
		_player.velocity.dot(_player.global_basis.y),
		_player.is_on_floor(),
		_player._run_blend,
		rad_to_deg(_player.character.rotation.x),
		_player._clip,
	])


## Take-off, the climb, the boost up to flat out, the brake, and the dive back
## down. Speed and lean are the two to watch: lean is what carries the change
## from an upright hover to flying flat, and it should track the speed.
func _flight_checks() -> void:
	_landing_policy_checks()
	# A fast jump is already over the same threshold that changes Float into
	# Fly. Taking off from it must preserve that velocity and pose immediately,
	# rather than clamping the body back to a 20 m/s hover.
	await _place(Vector3(0.0, 60.0, 12.0), PI)
	_player._apply_stance(STAND)
	_player.floor_snap_length = _player._floor_snap
	_player._flight_velocity = Vector3.ZERO
	_player._coyote_left = 0.0
	await _wait(14)
	var inherited := 100.0
	_player.velocity = -_player.global_basis.z * inherited
	Input.action_press("move_forward")
	Input.action_press("jump")
	await _wait(2)
	Input.action_release("jump")
	_report_flight("fast jump takeoff")
	if _player._stance != FLY:
		push_error("player_test: fast airborne jump did not enter flight")
	elif _player.velocity.length() < inherited * 0.9:
		push_error("player_test: fast airborne takeoff discarded momentum")
	elif _player._fly_blend < 0.45:
		push_error("player_test: fast airborne takeoff entered the Float pose")
	elif absf(_player.velocity.dot(_player._up())) > 5.0:
		push_error("player_test: takeoff press caused a float-like upward launch")
	elif _player._pitch < 0.1:
		push_error("player_test: direct fast flight did not lift the player's view")
	Input.action_release("move_forward")
	Input.action_press("land")
	await _wait(2)
	Input.action_release("land")

	await _place(Vector3(0.0, 60.0, 12.0), PI)
	# Long enough for the coyote window to lapse, which is what separates a
	# take-off from a jump made just after walking off something.
	await _wait(14)
	_report_flight("falling")

	# Polled, not parsed: the take-off is read with is_action_just_pressed.
	Input.action_press("jump")
	await _wait(4)
	Input.action_release("jump")
	await _wait(10)
	_report_flight("took off")
	if _player._stance != FLY:
		push_error("player_test: space in clear air did not take off")

	Input.action_press("jump")
	await _wait(45)
	_report_flight("rising")
	Input.action_release("jump")
	await _wait(30)
	_report_flight("hovering")

	Input.action_press("move_forward")
	await _wait(45)
	_report_flight("floating forward")

	Input.action_press("sprint")
	for second in 5:
		await _wait(60)
		_report_flight("boosting %ds" % (second + 1))
	var top: float = _player.velocity.length()
	if top < _player.fly_speed * 0.9:
		push_error("player_test: five seconds of boost only reached %.0f m/s" % top)
	Input.action_release("sprint")
	await _wait(60)
	_report_flight("coasting")

	# Releasing the direction is the only brake there is, so it has to actually
	# haul a thousand metres a second back down to a hover on its own.
	Input.action_release("move_forward")
	await _wait(240)
	_report_flight("let go, 4s")
	if _player.velocity.length() > _player.float_speed:
		push_error("player_test: coasting left %.0f m/s" % _player.velocity.length())

	# X out of a hover with nothing underneath: the flight ends where it is and
	# the player falls the rest of the way.
	await _wait(20)
	# Polled, like the take-off: a parsed InputEventAction never satisfies
	# is_action_just_pressed.
	Input.action_press("land")
	await _wait(4)
	Input.action_release("land")
	_report_flight("cancelled")
	if _player._stance != STAND:
		push_error("player_test: the land key left the player in stance %d" % _player._stance)
	await _wait(90)

	# Drifting down onto the floor, which is the other way out and the one a
	# player finds without being told. A fresh take-off: the cancel above put the
	# feet back down.
	await _place(Vector3(0.0, 14.0, 12.0), PI)
	await _wait(14)
	Input.action_press("jump")
	await _wait(4)
	Input.action_release("jump")
	await _wait(10)
	_look(-1.35)
	_player.velocity = -_player._up() * 80.0 - _player.global_basis.z * 15.0
	_player._cruise = _player.velocity.length()
	Input.action_press("move_forward")
	var saw_hero := false
	for frame in 150:
		await get_tree().physics_frame
		saw_hero = saw_hero or _player._stance == HERO
	Input.action_release("move_forward")
	_look(0.0)
	await _wait(25)
	_report_flight("landed")
	if not saw_hero:
		push_error("player_test: a fast steep dive never entered HeroLand")
	elif _player._stance != STAND:
		push_error("player_test: still in stance %d after a dive into the floor" % _player._stance)


## Pins down the angle split without depending on a generated hill to present
## exactly the required normal. Physical flight above still proves that the
## resulting state and animation are reached through an actual landing.
func _landing_policy_checks() -> void:
	var up := _player._up()
	var along := -_player.global_basis.z.normalized()
	_player._land_fast_flight(along * 25.0 - up * 80.0)
	if _player._stance != HERO or _player._hero_left <= 0.0:
		push_error("player_test: steep flight landing did not enter HeroLand")
	_player._update_camera(0.5)
	if _player.camera_arm.spring_length < 1.5:
		push_error("player_test: HeroLand did not move to a shoulder camera")
	elif _player.camera_arm.position.x * _player._shoulder < 0.3:
		push_error("player_test: HeroLand lost the selected shoulder")
	elif absf(_player.head.rotation.x) > 0.05:
		push_error("player_test: HeroLand camera still points into the ground")
	_player._apply_stance(STAND)
	for frame in 4:
		_player._update_camera(0.25)
	if _player._camera_mode == 0 and _player.camera_arm.spring_length > 0.1:
		push_error("player_test: camera did not return after HeroLand")
	_player._land_fast_flight(along * 100.0 - up * 20.0)
	if _player._stance != STAND:
		push_error("player_test: shallow flight landing did not enter locomotion")
	elif absf(_player._horizontal_speed() - 88.0) > 1.0:
		push_error("player_test: shallow landing retained %.1f rather than 88%% speed" % \
			_player._horizontal_speed())
	_player.velocity = Vector3.ZERO
	_player._run_speed = _player.walk_speed


## Side on to the body at each point along the hover-to-flat-out continuum. The
## clip sheet cannot cover these two: its camera is framed for a standing figure,
## and flying puts the body through ninety degrees and the arms above the frame.
func _flight_shots() -> void:
	# High up, so every pose is read against sky rather than against scenery.
	await _place(Vector3(0.0, 40.0, 0.0), 0.0)
	await _wait(14)
	Input.action_press("jump")
	await _wait(4)
	Input.action_release("jump")
	await _wait(30)

	_player._camera_mode = 2
	_player.hud.visible = false
	# Parented to the player rather than placed each shot: these are taken at
	# 200 m/s, where even one frame of lag leaves the body out of the frame.
	# Level with the hips, which is what the lean turns about.
	var review := Camera3D.new()
	_player.add_child(review)
	review.fov = 40.0
	review.position = Vector3(3.4, 0.72, 0.0)
	review.rotation.y = PI * 0.5
	review.current = true
	await _wait(10)
	await _rig_shot(review, "flight_hover")

	Input.action_press("move_forward")
	await _wait(50)
	await _rig_shot(review, "flight_float_forward")

	Input.action_press("sprint")
	await _wait(45)
	await _rig_shot(review, "flight_leaning_over")
	await _wait(135)
	await _rig_shot(review, "flight_flat_out")

	# Nose up on the boost: the lean should stand the body back upright rather
	# than leave it flying flat while it climbs.
	_look(1.35)
	await _wait(90)
	await _rig_shot(review, "flight_climbing")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await _wait(180)
	_look(0.0)
	await _wait(30)

	# Back to the player's own camera, which is where the controls card is read.
	review.current = false
	review.queue_free()
	_player.hud.visible = true
	_player._camera_mode = 0
	await _wait(40)
	await _shot("flight_hud")

	# The climbing shot is taken under full boost, which leaves the player some
	# kilometres up. Brought back down before the dive home, or the checks that
	# follow inherit a player still in the air.
	await _place(Vector3(0.0, 14.0, 12.0), PI)
	_look(-1.35)
	Input.action_press("move_forward")
	await _wait(180)
	Input.action_release("move_forward")
	_look(0.0)
	await _wait(30)
	_report_flight("shots done")
	if _player._stance != STAND:
		push_error("player_test: shots left the player airborne in stance %d" % _player._stance)


## The same moment from the player's right and from above it. Side on is what
## reads the lean; overhead is the only view that separates the arms from the
## torso once the body is lying along them.
func _rig_shot(review: Camera3D, shot_name: String) -> void:
	review.position = Vector3(3.4, 0.72, 0.0)
	review.rotation = Vector3(0.0, PI * 0.5, 0.0)
	await _shot(shot_name)
	review.position = Vector3(0.0, 3.6, 0.0)
	review.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	await _shot(shot_name + "_above")


func _look(pitch: float) -> void:
	_player._pitch = pitch
	_player.head.rotation.x = pitch


func _report_flight(label: String) -> void:
	print("player_test: %-18s stance=%-6s speed=%6.1f m/s  cruise=%6.1f  blend=%4.2f  lean=%7.1f deg  clip=%-6s y=%7.2f  fov=%5.1f" % [
		label,
		_stance_name(_player._stance),
		_player.velocity.length(),
		_player._cruise,
		_player._fly_blend,
		rad_to_deg(_player.character.rotation.x),
		_player._clip,
		_altitude(),
		_player.camera.fov,
	])


func _camera_shots() -> void:
	# Facing the wardrobe across the landing site, so the shots have the character
	# against scenery rather than against bare terrain.
	await _place(Vector3(-6.0, 0.4, -2.0), atan2(3.0, 5.0))
	await _wait(20)
	await _shot("player_first_person")

	await _tap("cycle_camera")
	await _wait(30)
	_report("third near")
	await _shot("player_third_near")

	await _tap("cycle_camera")
	await _wait(30)
	_report("third far")
	await _shot("player_third_far")

	await _tap("swap_shoulder")
	await _wait(30)
	await _shot("player_third_far_left")

	Input.action_press("crouch")
	await _wait(30)
	_report("crouch, third person")
	await _shot("player_crouch_third")
	Input.action_release("crouch")
	await _wait(20)

	await _place(Vector3(2.0, 0.4, -11.0), 0.0)
	Input.action_press("move_forward")
	# A sprint's worth of shift and no more. Held for the fifty frames this used
	# to run for, the run winds up past what the test floor is long enough to
	# slide across, and the shot is of a body leaving the edge of the world.
	Input.action_press("sprint")
	await _wait(10)
	Input.action_release("sprint")
	await _wait(30)
	Input.action_press("crouch")
	await _wait(12)
	_report("slide, third person")
	await _shot("player_slide_third")
	Input.action_release("crouch")
	Input.action_release("move_forward")


## [param offset] is metres in the landing site's frame — its +Y is up out of the
## planet there, -Z the way a zero yaw faces — and [param yaw] turns about that up
## rather than about the world's.
func _place(offset: Vector3, yaw: float) -> void:
	_player.global_transform = Transform3D(
		_ground.basis * Basis(Vector3.UP, yaw), _ground * offset)
	_player.velocity = Vector3.ZERO
	await _wait(10)


## Whether the run left the planet through the inside. The terrain's colliders are
## built on worker threads around the camera, and past roughly 120 m/s the run
## arrives somewhere before its ground does; the body then falls through the shell
## and any measurement taken after that is about gravity, not about running. Said
## once, plainly, rather than left to surface as a run that "survived a wall".
func _fell_through(what: String) -> bool:
	if _altitude() > -20.0:
		return false
	push_warning("player_test: %s outran the terrain's colliders and fell through the planet" % what)
	print("player_test: !! %s fell through unbuilt ground at %.0f m/s" % [
		what, _player._horizontal_speed()])
	return true


## Metres between the feet and the ground under them. World Y means nothing on a
## sphere, so every height printed here is this.
func _altitude() -> float:
	var centre := _planet.global_position
	var out := _player.global_position - centre
	return out.length() - (_planet.standing_position(out) - centre).length()


## How far the player has travelled across the ground from the landing site,
## measured along the surface rather than through it.
func _ranged() -> float:
	var centre := _planet.global_position
	var here := (_player.global_position - centre).normalized()
	var there := (_ground.origin - centre).normalized()
	return acos(clampf(here.dot(there), -1.0, 1.0)) * _planet.shape.radius


## Parsed as a real event so it reaches _unhandled_input, and held for a few
## frames so a polled is_action_just_pressed() sees it too.
func _tap(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(3)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await _wait(2)


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


## The same, counted in drawn frames rather than physics steps. For use while
## the clock is stopped, when no physics step is ever going to arrive.
func _drawn(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


## Row order follows OnlinePlayer.Stance, so a stance added there without a name
## added here reports as its number rather than taking the harness down.
func _stance_name(stance: int) -> String:
	const NAMES := ["stand", "crouch", "slide", "fly", "crash", "swim"]
	return NAMES[stance] if stance < NAMES.size() else str(stance)


func _report(label: String) -> void:
	print("player_test: %-22s stance=%-6s speed=%5.2f alt=%5.2f out=%6.1f floor=%-5s cam=%d arm=%4.2f shoulder=%5.2f" % [
		label,
		_stance_name(_player._stance),
		_player._horizontal_speed(),
		_altitude(),
		_ranged(),
		_player.is_on_floor(),
		_player._camera_mode,
		_player.camera_arm.spring_length,
		_player.camera_arm.position.x,
	])


## Whether the picture holds still when nothing in it is moving.
##
## Shimmer and flicker look the same in a screenshot and have opposite causes.
## Aliasing needs the camera to move before it shows itself; a light, a sky or a
## shader that advances on its own shows up with everything standing still. So
## the body, the camera and the look angle are pinned, consecutive frames are
## differenced, and whatever is left is the scene moving under its own steam.
##
## Each row then takes one suspect away. The row where the number collapses is
## the one doing it, which is a good deal more use than four plausible theories.
func _shimmer_checks(place: String) -> void:
	var world := _planet.get_parent()
	var cycle := world.find_child("CelestialCycle", true, false)
	var sun := world.find_child("Sun", true, false) as DirectionalLight3D
	var ship := world.find_child("VacationersLanding", true, false) as Node3D
	var material := Planet.SURFACE_MATERIAL
	# Read rather than written down, so the rows that leave it alone put back
	# whatever the project is actually shipping instead of a guess at it. The
	# same reason the ground's own dials are read here: a row named "as shipped"
	# that sets them to a number in this file stops being that row the moment
	# the material is retuned, and stops being it silently.
	var shipped_bump: float = material.get_shader_parameter(&"texture_bump")
	var shipped_footprint: float = material.get_shader_parameter(&"texture_footprint")
	var shipped_relief: float = material.get_shader_parameter(&"bump_strength")
	var shipped_grain: float = material.get_shader_parameter(&"detail_amount")
	var shipped_texture_blend: float = material.get_shader_parameter(&"texture_blend")
	var shipped_texture_scale: float = material.get_shader_parameter(&"texture_scale")
	var shipped_occlusion: float = material.get_shader_parameter(&"texture_occlusion")
	var shipped_detail_range: float = material.get_shader_parameter(&"texture_detail_range")
	var shipped_bump_footprint: float = material.get_shader_parameter(
		&"texture_bump_footprint")
	# Left at the shader's own default in the material, so ask the material and
	# fall back rather than reading a null.
	var spin_set: Variant = material.get_shader_parameter(&"texture_spin")
	var shipped_spin: float = 1.0 if spin_set == null else float(spin_set)
	_shadow_atlas = int(ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/size", 4096))
	print("player_test: shimmer shadow atlas %d, filter quality %d" % [
		_shadow_atlas, ProjectSettings.get_setting(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)])

	# The landing site is desert, and grass is the whole subject here — it is the
	# only ground with blades on it, the only ground with glow lights over it,
	# and the only ground the flicker was reported on. So the body is moved to
	# the greenest ground on the planet first.
	#
	# `colony` moves it to Vacationer's Landing instead, which is a different
	# question with a different suspect list. Open grass anywhere on the planet
	# is lit by one unobstructed light; the coastal shelf is a different biome
	# mix and the only place the flicker was first reported. Comparing the two
	# is most of the diagnosis.
	if not place in ["grass", "far", "dunes"] and ship != null:
		# Ten metres off the landing radial: still on the coastal shelf, inside
		# the nearest shadow cascade, and roughly where the walking that was
		# reported was being done. Stepped along a tangent and renormalized,
		# because a direction is not a position and adding metres to its
		# components would move it by however far the radius says rather than
		# by ten.
		var at := (ship.get("direction") as Vector3).normalized()
		var side := at.cross(Vector3.UP)
		if side.length_squared() < 0.001:
			side = at.cross(Vector3.RIGHT)
		_grass_spot = (at + side.normalized()
			* (10.0 / maxf(_planet.shape.radius, 1.0))).normalized()
	elif place == "dunes":
		_grass_spot = _sand_direction(_grass_direction())
	else:
		_grass_spot = _grass_direction()
	var standing := _planet.shape.color_at(_grass_spot,
		_planet.shape.elevation(_grass_spot, _planet.finest_spacing()),
		_grass_spot)
	print("player_test: shimmer standing on %s at %.4f, %.4f, %.4f, biome (%.2f %.2f %.2f)" % [
		place, _grass_spot.x, _grass_spot.y, _grass_spot.z,
		standing.r, standing.g, standing.b])

	# Pointed down at the ground a few metres ahead, in first person so the
	# character's own idle breathing is not being measured, and with the HUD off
	# because a readout that rewrites six times a second is a changing picture.
	_stand_on(_grass_spot)
	# Third person and steeply down for `lawn`, because that is the view the
	# far-grass flicker was reported from and it is not the view the rest of
	# this function measures. First person at eye height spends most of its
	# frame on the two to twenty metres in front of the boots; a camera up
	# behind the shoulder looking down fills the same frame with the ten to
	# sixty metre band, which is where a blade is thinner than a pixel.
	_player._camera_mode = 2 if place == "lawn" else 0
	# Shallow enough to have the middle distance in frame, which is where a
	# ground texture shimmers, rather than only the metre in front of the boots.
	#
	# `far` goes shallower still, to just under the horizon. That fills the
	# frame with ground at a grazing angle, which is where a pixel covers metres
	# rather than millimetres and where every fade in this shader is deciding
	# something. The default pitch spends most of its picture on the two metres
	# in front of the boots, where nothing is being tested.
	_player._pitch = -0.08 if place == "far" else (-0.62 if place == "lawn" else -0.32)
	# First person still puts an arm across the frame and that arm breathes. It
	# was the largest thing in every difference picture taken here — a reading
	# of the body, printed under a heading about the ground.
	if _player.character != null:
		_player.character.visible = false
	if _player.hud != null:
		_player.hud.visible = false
	# Long enough for the terrain, its colliders and the streamed cover to all
	# arrive; a shot taken before the grass grows is a shot of bare ground.
	await _wait(400)

	await _shot("shimmer_view")
	# Before the rows rather than inside the first one. It walks the body a
	# couple of hundred frames, every streamer in the world then spends a while
	# rebuilding the tiles it left behind, and a reading taken during that reads
	# as a wildly shimmering scene — which is exactly what the first row of
	# every run had been reporting, whatever that row was set to.
	if not _glow_reported:
		_glow_reported = true
		await _glow_report(world)
		_stand_on(_grass_spot)
		await _wait(180)

	print("player_test: shimmer  (mean change between consecutive frames, 0-255)")
	# The blade rows come first for context, but the ones that matter are the
	# hidden-blade rows below them: standing in a lawn this thick, the grass
	# fills the frame and its own animation is all any measurement can see. The
	# report is about the ground under it, so the ground has to be visible.
	# Two row sets, because the two places are being asked different questions.
	# On open grass the question was which of the things growing there moves; at
	# the ship it is why the same ground misbehaves *here* and not out there, so
	# the rows take away the things that are only true at the ship — its shadow,
	# its hull, and a sun that has been turning under it every frame since the
	# day/night cycle went in.
	var grass_rows := [
		{"name": "as shipped"},
		{"name": "wind off", "wind": true},
		{"name": "far grass hidden", "hide": "GlobalDistantGrass"},
		{"name": "near grass hidden", "hide": "GlobalGrass"},
		{"name": "all blades hidden", "hide": ""},
		{"name": "  + no ground texture", "hide": "", "ground": true},
		{"name": "MSAA 4x", "msaa": Viewport.MSAA_4X},
		{"name": "FXAA", "fxaa": true},
		{"name": "TAA", "taa": true},
	]
	# Cumulative, so each line is the one above it with one more thing gone and
	# the drop between two lines is what that one thing was worth.
	var colony_rows := [
		{"name": "as shipped"},
		{"name": "as shipped again"},
		{"name": "only the sun stopped", "sun": true},
		{"name": "blades hidden", "hide": ""},
		{"name": "  + sun stopped", "hide": "", "sun": true},
		{"name": "  + shadows off", "hide": "", "sun": true, "shadow": true},
		{"name": "  + hull hidden", "hide": "", "sun": true, "shadow": true,
			"hull": true},
		{"name": "  + no ground texture", "hide": "", "sun": true,
			"shadow": true, "hull": true, "ground": true},
		{"name": "blades hidden again", "hide": ""},
	]
	# Having found the shadow, which part of it. All of these keep the blades
	# hidden, because the ground under them is the subject and a lawn in frame
	# drowns every difference between two shadow settings.
	# Every one of these freezes the sun, and it is not optional. Left running,
	# the sun turns 19 degrees over the minute these rows take, the ship's shadow
	# lengthens across the whole run, and the readings fall monotonically down
	# the list whatever each row actually changed — a confound that reads exactly
	# like every setting being an improvement on the one above it.
	var shadow_rows := [
		{"name": "as shipped", "hide": "", "sun": true},
		{"name": "hard filter", "hide": "", "sun": true,
			"filter": RenderingServer.SHADOW_QUALITY_HARD},
		{"name": "soft very low", "hide": "", "sun": true,
			"filter": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW},
		{"name": "soft high", "hide": "", "sun": true,
			"filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH},
		{"name": "no split blending", "hide": "", "sun": true, "blend": true},
		{"name": "normal bias 1", "hide": "", "sun": true, "normal_bias": 1.0},
		{"name": "hard + no blending", "hide": "", "sun": true, "blend": true,
			"filter": RenderingServer.SHADOW_QUALITY_HARD},
		{"name": "atlas 8192", "hide": "", "sun": true, "atlas": 8192},
		{"name": "atlas 8192 + hard", "hide": "", "sun": true, "atlas": 8192,
			"filter": RenderingServer.SHADOW_QUALITY_HARD},
		{"name": "as shipped again", "hide": "", "sun": true},
		{"name": "shadows off", "hide": "", "sun": true, "shadow": true},
	]
	# And which part of the ground texture, once the shadow has been ruled out.
	# Same discipline as the shadow rows: blades hidden and the sun frozen, so
	# the only thing changing between lines is the one named. The question is
	# not "does removing the texture stop the flicker" — it plainly does, and
	# the picture that leaves is not one worth shipping — but "can the texture
	# stay and the flicker go".
	#
	# A pixel of this ground is a colour and a direction, and the two fail
	# differently: the colour is a photograph with a mip chain behind it and it
	# behaves, the direction is that photograph's normal map multiplied by a
	# light and it does not. So the sweep is over how much wider than the colour
	# the relief is read, with the colour then pulled back sharper than it has
	# been to spend what that buys.
	var ground_rows := [
		{"name": "as shipped", "hide": "", "sun": true},
		{"name": "relief at the pixel", "hide": "", "sun": true,
			"bump_footprint": 1.0},
		# What is left once the map's relief is filtered wide is the other
		# relief: a metre-scale field of noise with no mip chain of any kind
		# behind it. These say how much of the remainder is that.
		{"name": "no procedural bumps", "hide": "", "sun": true, "relief": 0.0},
		# What the relief filter is trying to reach without giving the map's own
		# bumps up, and what the photograph on its own is worth.
		{"name": "unfaded map relief", "hide": "", "sun": true,
			"detail_range": 0.83},
		# The floor each of those is trying to reach, and the floor the ground
		# was reduced to the last time this was chased out of it. The second is
		# here to be beaten, not chosen: it is biome colour and procedural
		# grain with no photograph and no relief anywhere in it.
		{"name": "no texture normals", "hide": "", "sun": true, "bump": true},
		{"name": "flat colour", "hide": "", "sun": true,
			"ground": true, "relief": 0.0, "bump": true},
		# With the relief rows above all measuring nothing, what is left is the
		# photograph's own colour, and these take it apart. The first drops it
		# and keeps every bit of relief, which is the reverse of the row above
		# and the one that says whether the colour is the whole story; the rest
		# are the three ways it could be aliasing.
		{"name": "no photo colour", "hide": "", "sun": true, "ground": true},
		# Blurring the read puts fewer texels under a pixel; spreading the
		# photograph over more ground does the same thing without costing any
		# sharpness, and makes the pattern bigger rather than softer. Measured
		# apart, the blur is worth several times the spread. Measured together,
		# the spread buys back the feature size the blur takes away — which is
		# the whole point, because the pattern is the part being kept.
		{"name": "filtered 5x", "hide": "", "sun": true, "footprint": 5.0},
		{"name": "filtered 5x, 1.3x larger", "hide": "", "sun": true,
			"footprint": 5.0, "texture_scale": 0.45},
		{"name": "filtered 8x, 1.3x larger", "hide": "", "sun": true,
			"footprint": 8.0, "texture_scale": 0.45},
		# Turning the scatter cells is what took the lattice out of the ground
		# (see --tiling). It reads three differently-oriented copies of the
		# texture where it used to read three differently-offset ones, so it is
		# worth confirming here that the ground is no livelier for it. The
		# gradients are turned with the coordinate, so it should not be.
		{"name": "cells unturned", "hide": "", "sun": true, "spin": 0.0},
		{"name": "as shipped again", "hide": "", "sun": true},
	]
	# Which of the things growing at the ship is doing it. The near lawn is
	# blades; the far carpet is a mat that reads as ground rather than as
	# planting, so "the grass texture" and "the grass blades" can very
	# reasonably mean those two, and they have to be told apart by name.
	var blade_rows := [
		{"name": "as shipped"},
		{"name": "far carpet hidden", "hide": "GlobalDistantGrass"},
		{"name": "near lawn hidden", "hide": "GlobalGrass"},
		{"name": "flowers hidden", "hide": "LandingFlowers"},
		{"name": "flower trees hidden", "hide": "LandingFlowerTrees"},
		{"name": "everything hidden", "hide": ""},
		{"name": "as shipped again"},
		{"name": "far carpet hidden again", "hide": "GlobalDistantGrass"},
	]
	# Before and after the distance calming, and the two extremes either side of
	# it. "no calming at all" is what the field looked like when the report came
	# in; "every plant still" is the floor the calming is working towards and is
	# not a shippable look, only the number to judge the shipped one against.
	# Motion against everything else. This is the one comparison in the file that
	# is not open to argument, because the camera never moves in the still
	# column: whatever it reports really is the scene changing on its own.
	var calm_rows := [
		{"name": "no calming", "calm_from": 4000.0, "calm_to": 8000.0},
		{"name": "calm 30 to 90 m", "calm_from": 30.0, "calm_to": 90.0},
		{"name": "as shipped, 18 to 55 m"},
		{"name": "calm 10 to 35 m", "calm_from": 10.0, "calm_to": 35.0},
		{"name": "calm 6 to 20 m", "calm_from": 6.0, "calm_to": 20.0},
		{"name": "calm 4 to 14 m", "calm_from": 4.0, "calm_to": 14.0},
		{"name": "calm 3 to 10 m", "calm_from": 3.0, "calm_to": 10.0},
		{"name": "calm 2 to 7 m", "calm_from": 2.0, "calm_to": 7.0},
		# Not a shippable look — this stills the grass around the boots. It is
		# here to prove the dial reaches the field at all, because a row that
		# changes nothing and a row that is not wired up are the same number.
		{"name": "calm 1 to 4 m", "calm_from": 1.0, "calm_to": 4.0},
		{"name": "wind off", "wind": true},
		{"name": "baked sway and wind both off", "freeze": true},
		{"name": "no plants at all", "hide": ""},
		{"name": "no calming again", "calm_from": 4000.0, "calm_to": 8000.0},
	]
	# How fast the baked sway should run, and how much of its phase should be
	# per plant. The pair have to be swept together: slowing a field of blades
	# that are all beating against each other only slows the beating down.
	var sway_rows := [
		{"name": "0.88 loops/s, scatter 1.0", "sway": 0.88, "scatter": 1.0},
		{"name": "0.88 loops/s, scatter 0.25", "sway": 0.88, "scatter": 0.25},
		{"name": "0.50 loops/s, scatter 0.25", "sway": 0.5, "scatter": 0.25},
		{"name": "0.35 loops/s, scatter 0.25", "sway": 0.35, "scatter": 0.25},
		{"name": "0.35 loops/s, scatter 1.0", "sway": 0.35, "scatter": 1.0},
		{"name": "0.35 loops/s, scatter 0.1", "sway": 0.35, "scatter": 0.1},
		{"name": "0.22 loops/s, scatter 0.25", "sway": 0.22, "scatter": 0.25},
		{"name": "0.88 again, scatter 1.0", "sway": 0.88, "scatter": 1.0},
		{"name": "no plants at all", "hide": ""},
	]
	# Where in the field the flicker lives. Shrinking the draw radius collapses
	# every plant past it to nothing, so the drop between two of these lines is
	# what that band of ground was contributing — which is the number that says
	# whether a distance rule can fix this at all, and from how far out.
	var reach_rows := [
		{"name": "grass to 48 m (shipped)"},
		{"name": "grass to 34 m", "reach": 34.0},
		{"name": "grass to 24 m", "reach": 24.0},
		{"name": "grass to 16 m", "reach": 16.0},
		{"name": "grass to 10 m", "reach": 10.0},
		{"name": "grass to 5 m", "reach": 5.0},
		{"name": "no plants at all", "hide": ""},
		{"name": "48 m, plants frozen", "freeze": true},
		{"name": "48 m again", "reach": 48.0},
	]
	# Whether anti-aliasing fixes it, asked properly.
	#
	# Every row but the last three freezes the plants, and that is the point:
	# with the field still, the only thing that can change between two frames is the
	# sampling, so the creep column stops being "grass moved" plus "grass
	# aliased" and becomes aliasing alone. Asked with the wind on, the animation
	# is an order of magnitude larger than the effect being measured and buries
	# it.
	var aa_rows := [
		{"name": "frozen, no AA", "freeze": true},
		{"name": "frozen, MSAA 2x", "freeze": true, "msaa": Viewport.MSAA_2X},
		{"name": "frozen, MSAA 4x", "freeze": true, "msaa": Viewport.MSAA_4X},
		{"name": "frozen, MSAA 8x", "freeze": true, "msaa": Viewport.MSAA_8X},
		{"name": "frozen, FXAA", "freeze": true, "fxaa": true},
		{"name": "frozen, TAA", "freeze": true, "taa": true},
		{"name": "frozen, MSAA 4x + TAA", "freeze": true,
			"msaa": Viewport.MSAA_4X, "taa": true},
		{"name": "frozen, no AA again", "freeze": true},
		{"name": "frozen, no plants", "freeze": true, "hide": ""},
		{"name": "live, no AA"},
		{"name": "live, MSAA 4x", "msaa": Viewport.MSAA_4X},
		{"name": "live, MSAA 4x + TAA", "msaa": Viewport.MSAA_4X, "taa": true},
	]
	var rows := grass_rows
	if place == "sway":
		rows = sway_rows
	elif place == "aa":
		rows = aa_rows
	elif place == "reach":
		rows = reach_rows
	elif place == "calm":
		rows = calm_rows
	elif place == "blades":
		rows = blade_rows
	elif place == "lawn":
		rows = calm_rows
	elif place == "colony":
		rows = colony_rows
	elif place == "shadow":
		rows = shadow_rows
	elif place == "ground" or place == "far" or place == "dunes":
		rows = ground_rows
	for row in rows:
		get_viewport().msaa_3d = row.get("msaa", Viewport.MSAA_DISABLED)
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA \
			if row.has("fxaa") else Viewport.SCREEN_SPACE_AA_DISABLED
		get_viewport().use_taa = row.has("taa")
		# Re-found every row. The streamers only build a tile's multimesh once
		# that tile is near, so a list gathered before walking over here is a
		# list of the fields that existed at the spawn point.
		var covers := _grass_covers(world)
		if not _covers_named:
			_covers_named = true
			var names := PackedStringArray()
			for cover in covers:
				names.append(cover.name)
			print("player_test: shimmer fields %s (%d plant materials)" % [
				", ".join(names), _plant_materials(world).size()])
		RenderingServer.global_shader_parameter_set(&"wind_strength",
			0.0 if row.has("wind") else 1.0)
		if cycle != null:
			# Zero is the cycle's own "do not advance", so the sun is left
			# wherever it had got to rather than being moved to a new angle.
			cycle.set("period_seconds", 0.0 if row.has("sun") else 960.0)
			if place != "grass":
				# Every row starts from the same sun, which separates the two
				# things a frozen sun changes. Left to run, it turns 19 degrees
				# over a set of rows and the shadow lengthens the whole way
				# down the list, so a "stopped" row further down looks better
				# than a "running" row above it purely for being later.
				#
				# A tenth of a day past noon puts it about 54 degrees up and
				# throws the ship's 26 m of hull some 19 m along the ground —
				# over the patch being watched rather than straight down under
				# the hull, which is where phase zero would put it and where
				# there would be no shadow to study at all.
				cycle.call("set_phase", 0.1)
		if sun != null:
			sun.shadow_enabled = not row.has("shadow")
			sun.shadow_normal_bias = row.get("normal_bias", 4.0)
			sun.directional_shadow_blend_splits = not row.has("blend")
		if ship != null:
			ship.visible = not row.has("hull")
		RenderingServer.directional_soft_shadow_filter_set_quality(
			row.get("filter", RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM))
		RenderingServer.directional_shadow_atlas_set_size(
			row.get("atlas", _shadow_atlas), true)
		for cover in covers:
			# An empty name hides the lot; a name hides one field, which is how
			# the near lawn and the far carpet are told apart.
			cover.visible = not (row.has("hide")
				and String(row["hide"]) in ["", cover.name])
		material.set_shader_parameter(&"texture_scatter", 0.0 if row.has("scatter") else 1.0)
		material.set_shader_parameter(&"texture_bump",
			0.0 if row.has("bump") else row.get("bump_amount", shipped_bump))
		material.set_shader_parameter(&"texture_blend", 0.0
			if row.has("ground")
			else row.get("blend_amount", shipped_texture_blend))
		material.set_shader_parameter(&"texture_scale",
			row.get("texture_scale", shipped_texture_scale))
		material.set_shader_parameter(&"texture_occlusion",
			row.get("occlusion", shipped_occlusion))
		material.set_shader_parameter(&"bump_strength", row.get("relief", shipped_relief))
		material.set_shader_parameter(&"detail_amount", row.get("grain", shipped_grain))
		material.set_shader_parameter(&"texture_footprint",
			row.get("footprint", shipped_footprint))
		material.set_shader_parameter(&"texture_detail_range",
			row.get("detail_range", shipped_detail_range))
		material.set_shader_parameter(&"texture_bump_footprint",
			row.get("bump_footprint", shipped_bump_footprint))
		material.set_shader_parameter(&"texture_spin",
			row.get("spin", shipped_spin))
		for plant in _plant_materials(world):
			if not _plant_shipped.has(plant):
				_plant_shipped[plant] = {
					&"draw_within": plant.get_shader_parameter(&"draw_within"),
					&"wind_sway": plant.get_shader_parameter(&"wind_sway"),
					&"vat_playback_speed":
						plant.get_shader_parameter(&"vat_playback_speed"),
				}
			var shipped: Dictionary = _plant_shipped[plant]
			plant.set_shader_parameter(&"draw_within",
				row.get("reach", shipped[&"draw_within"]))
			# Freezing a field means stopping both of the things that move it,
			# and grass in particular needs both: the wind bend is the shader's,
			# the sway is a baked clip playing off TIME, and killing either one
			# alone leaves the other still going.
			plant.set_shader_parameter(&"wind_sway",
				0.0 if row.has("freeze") else shipped[&"wind_sway"])
			plant.set_shader_parameter(&"vat_playback_speed", 0.0
				if row.has("freeze")
				else row.get("sway", shipped[&"vat_playback_speed"]))
			plant.set_shader_parameter(&"sway_scatter", row.get("scatter", 0.25))
			# Where the field stops moving. A row that wants it out of the way
			# pushes both past the draw radius rather than setting a flag, so
			# "off" is a distance like every other value in the sweep.
			plant.set_shader_parameter(&"calm_from", row.get("calm_from", 18.0))
			plant.set_shader_parameter(&"calm_to", row.get("calm_to", 55.0))
		await _wait(30)

		var slug := String(row["name"]).strip_edges().replace(" ", "_") \
			.replace("+_", "").replace(",", "")
		# The view itself, so the difference pictures below can be read against
		# the ground they were taken of rather than guessed at. Two rows only —
		# these are full-size pictures and there are a dozen rows.
		if String(row["name"]) in [
				"as shipped", "no photo colour", "filtered 5x",
				"filtered 5x, 1.3x larger", "filtered 8x, 1.3x larger",
				"no calming", "as shipped, 18 to 55 m", "calm 10 to 35 m",
				"baked sway and wind both off",
			]:
			await _shot("shimmer_" + slug + "_view")
		var still := await _shimmer_pass(0.0, slug + "_still")
		var still_eye := _eye_creep
		# Printed so a still pass that was not actually still cannot be read as
		# a shimmering one.
		var drift := _player._horizontal_speed()
		# Two millimetres a frame. At that size the picture has almost no honest
		# reason to change — the ground has barely moved behind the pixel grid —
		# so what does change is the sampling snapping rather than the view
		# shifting. The walking column cannot tell those apart, because at a
		# proper pace most of what moves is moving for good reason.
		var creep := await _shimmer_pass(SHIMMER_CREEP, slug + "_creep")
		var walking := await _shimmer_pass(SHIMMER_STEP, slug)
		# The peak alongside the mean, because they are not the same complaint.
		# A ground that boils is a scatter of pixels changing a lot while most
		# of the frame changes very little, and a mean over the frame reports
		# that as almost nothing. `loud` counts the pixels that moved by more
		# than the eye would forgive.
		print("player_test:   %-22s still=%6.3f (eye %6.3f mm) creep=%6.3f (peak %3d, loud %6d) walking=%6.3f (drift %.2f)" % [
			row["name"], still.x, still_eye * 1000.0, creep.x,
			int(creep.y), int(creep.z), walking.x, drift])


## How steady the pooled grass glow lights are while the player walks.
##
## They are the one light source that exists over grass and nowhere else, and
## the pool is re-picked on a timer, so a light that keeps being handed a
## different patch spends its life fading out, jumping and fading back in. That
## reads as the lawn itself pulsing. "Lit" is a light at its full brightness on
## a patch it has reached; anything else is a light in transit, and a row where
## most of them are in transit is the fault.
func _glow_report(world: Node) -> void:
	var cover: Node3D = null
	for node in world.find_children("GlobalGrass", "", true, false):
		cover = node as Node3D
	if cover == null:
		print("player_test: glow  no GlobalGrass in the world")
		return
	var lights: Array = cover.get("_glow_lights")
	if lights == null or lights.is_empty():
		print("player_test: glow  the pool has no lights here (no glowing grass nearby)")
		return
	_stand_on(_grass_spot)
	await _wait(60)
	for sample in 8:
		# Half a second of walking between readings, which is most of one
		# survey interval, so consecutive rows are different re-picks.
		for _frame in 30:
			_player.global_position += -_player.global_basis.z * SHIMMER_STEP
			await _wait(1)
		var lit := 0
		var travelling := 0
		for light: OmniLight3D in lights:
			if light.light_energy > 0.001:
				lit += 1
			else:
				travelling += 1
		print("player_test: glow  t=%.1fs lit=%d dark=%d of %d" % [
			sample * 0.5, lit, travelling, lights.size()])


## One reading, either with the body pinned or with it walking `step` metres
## between frames. Both are needed and neither means much alone: the still pass
## is the noise floor, and only the difference between the two is aliasing.
##
## Walking is stepped by hand rather than by holding a key, so every row covers
## exactly the same ground at exactly the same pace and the rows can be
## compared with each other.
## [param warm] frames of the same movement before any of it is measured, for
## the rows that care about speed. The ground's motion calming is driven by the
## planet's smoothed drift, which is averaged over about a third of a second, so
## six frames of movement from a standing start reaches a fraction of the speed
## the row is named after and the calming reads as doing nothing at all. Left at
## zero the pass behaves exactly as it always has.
func _shimmer_pass(step: float, save_as: String, warm: int = 0) -> Vector3:
	# Awake for the placement, because `_stand_on` puts the body in the air over
	# the spot and it is the walk that finds the floor.
	_player.set_physics_process(true)
	_player.set_process(true)
	_stand_on(_grass_spot)
	await _wait(40)
	# The body is put to sleep for the duration, and this is the difference
	# between a measurement and an anecdote.
	#
	# Left awake it never quite stops. `_stand_on` drops it, it settles, and the
	# walk camera's radial filter then spends the best part of a second easing
	# the last of that drop out — a glide of a millimetre or so a frame, which is
	# far too small to see as movement and far too large to leave a detailed
	# ground alone. Every row measured that glide, the glide differed from row to
	# row by more than the rows differed from each other, and the whole table was
	# noise wearing three decimal places.
	_player.set_physics_process(false)
	_player.set_process(false)
	var total := 0.0
	var worst := 0
	var loud := 0
	var samples := 0
	var picture: Image = null
	# Where the eye actually was, frame by frame. Without this a still pass that
	# reports a shimmering ground is two completely different findings wearing
	# the same number: a ground that boils on its own, or a body that never
	# came to rest under a camera that faithfully drew what it was shown.
	var camera := _player.get_viewport().get_camera_3d()
	for _run in warm:
		if step > 0.0:
			_player.global_position += -_player.global_basis.z * step
			_player.reset_physics_interpolation()
		await _wait(1)
	var eye_was := camera.global_position if camera != null else Vector3.ZERO
	_eye_creep = 0.0
	var previous := await _frame_sample()
	for _pass in 6:
		if step > 0.0:
			_player.global_position += -_player.global_basis.z * step
			# Physics interpolation draws between the last two physics poses,
			# and with physics stopped both of those are wherever the body was
			# when it was stopped. Without this the step is written and never
			# drawn, and every row reports a perfectly still frame.
			_player.reset_physics_interpolation()
		await _wait(1)
		if camera != null:
			var eye := camera.global_position
			# Minus the step that was asked for, so the walking passes report
			# what the body added to it rather than the walk itself.
			_eye_creep = maxf(_eye_creep,
				absf(eye.distance_to(eye_was) - step))
			eye_was = eye
		var current := await _frame_sample()
		var difference := _frame_difference(previous, current)
		total += difference.x
		worst = maxi(worst, int(difference.y))
		if int(difference.z) >= loud:
			loud = int(difference.z)
			picture = _difference_picture(previous, current)
		samples += 1
		previous = current
	if save_as != "":
		var path := ProjectSettings.globalize_path(
			"%sshimmer_%s.png" % [SHOT_DIR, save_as])
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		if picture == null:
			print("player_test: shimmer  no picture for %s" % save_as)
		else:
			var wrote := picture.save_png(path)
			if wrote != OK:
				print("player_test: shimmer  %s failed: %s" % [
					path, error_string(wrote)])
	return Vector3(total / maxf(samples, 1), float(worst), float(loud))


## The greenest ground on the planet, which is where the grass, its blades and
## its glow patches are. Searched rather than written down as a coordinate: the
## terrain is generated, so a spot copied into this file goes stale the moment
## the seed does.
func _grass_direction() -> Vector3:
	var spacing := _planet.finest_spacing()
	var best := Vector3.UP
	var greenest := -INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	for _try in 4000:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		var height := _planet.shape.elevation(direction, spacing)
		# Well clear of the shore, where the terrain paints sand over whatever
		# the biome colour underneath happens to be.
		if height < 25.0:
			continue
		# And flat, which is not fussiness: a body left standing on a slope
		# slides down it, and a sliding body is a moving camera, which is the
		# one thing a measurement of a still frame cannot have.
		if _fall_across(direction, height, spacing) > 0.5:
			continue
		var biome := _planet.shape.color_at(direction, height, direction)
		var green := biome.g - maxf(biome.r, biome.b)
		if green > greenest:
			greenest = green
			best = direction
	return best


## The same search, for open desert. Sand and grass are painted by one shared
## texture path, so a fault in it should show on both; standing on each in turn
## is what tells a shared fault from a grass-only one.
## [param lit] is somewhere known to be in daylight at the phase these rows fix
## the sun to. Without it the search happily returns the reddest sand on the
## planet and that sand is as likely as not to be facing the stars, where every
## row reads near zero and reads it for the wrong reason.
func _sand_direction(lit: Vector3) -> Vector3:
	var spacing := _planet.finest_spacing()
	var best := Vector3.UP
	var reddest := -INF
	var rng := RandomNumberGenerator.new()
	rng.seed = 8081
	for _try in 4000:
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if direction.length_squared() < 0.0001:
			continue
		direction = direction.normalized()
		if direction.dot(lit) < 0.35:
			continue
		var height := _planet.shape.elevation(direction, spacing)
		# Above the shore band, so this is desert the biome chose rather than
		# beach the height rule painted.
		if height < 25.0:
			continue
		if _fall_across(direction, height, spacing) > 0.5:
			continue
		var biome := _planet.shape.color_at(direction, height, direction)
		var red := biome.r - maxf(biome.g, biome.b)
		if red > reddest:
			reddest = red
			best = direction
	return best


## Biggest height change within a couple of metres, which is slope without
## needing a normal.
func _fall_across(direction: Vector3, height: float, spacing: float) -> float:
	var across := direction.cross(Vector3.UP)
	if across.length_squared() < 0.001:
		across = direction.cross(Vector3.RIGHT)
	across = across.normalized()
	var along := direction.cross(across).normalized()
	var reach := 2.0 / maxf(_planet.shape.radius, 1.0)
	var worst := 0.0
	for step: Vector3 in [across, -across, along, -along]:
		var near := (direction + step * reach).normalized()
		worst = maxf(worst, absf(_planet.shape.elevation(near, spacing) - height))
	return worst


## What the eye does when the player is doing nothing at all.
##
## The shimmer table cannot answer this, because it stops the body before it
## measures anything — see the note over that in `_shimmer_pass`. Stopping the
## body was the right way to ask "does the ground boil on its own" and it is the
## wrong way to ask "is the ground still when the player is standing still",
## which is the question a player actually stands in a field and asks. This one
## leaves everything running and watches the camera.
##
## Reported in millimetres a frame, because that is the size the answer is: a
## tenth of a millimetre is nothing and a millimetre is enough to walk a
## detailed ground across the pixel grid and set it sparkling.
func _idle_creep_checks() -> void:
	var world := get_tree().current_scene
	_grass_spot = _grass_direction()
	_stand_on(_grass_spot)
	_player._camera_mode = 0
	_player._pitch = -0.32
	if _player.character != null:
		_player.character.visible = false
	if _player.hud != null:
		_player.hud.visible = false
	# Long enough for the terrain and its cover to arrive, and then long enough
	# again for anything that eases to have finished easing. If the body has not
	# settled after this it is not settling.
	await _wait(400)
	_stand_on(_grass_spot)
	await _wait(300)

	var camera := _player.get_viewport().get_camera_3d()
	var eye_was := camera.global_position
	var radius_was := _planet.to_local(_player.global_position).length()
	var eye_peak := 0.0
	var eye_total := 0.0
	var body_peak := 0.0
	var offset_peak := 0.0
	var offset_span := Vector2(INF, -INF)
	var picture := await _frame_sample()
	var frame_total := 0.0
	var loud := 0
	const IDLE_FRAMES := 180
	for _frame in IDLE_FRAMES:
		await _wait(1)
		var eye := camera.global_position
		var moved := eye.distance_to(eye_was) * 1000.0
		eye_peak = maxf(eye_peak, moved)
		eye_total += moved
		eye_was = eye
		var radius := _planet.to_local(_player.global_position).length()
		body_peak = maxf(body_peak, absf(radius - radius_was) * 1000.0)
		radius_was = radius
		var offset: float = _player._walk_camera_offset
		offset_peak = maxf(offset_peak, absf(offset) * 1000.0)
		offset_span = Vector2(minf(offset_span.x, offset * 1000.0),
			maxf(offset_span.y, offset * 1000.0))
		var current := await _frame_sample()
		var difference := _frame_difference(picture, current)
		frame_total += difference.x
		loud = maxi(loud, int(difference.z))
		picture = current
	print("player_test: idle eye   %.3f mm peak, %.3f mm mean per frame" % [
		eye_peak, eye_total / float(IDLE_FRAMES)])
	print("player_test: idle body  %.3f mm peak radial change per frame" % body_peak)
	print("player_test: idle filter %.3f mm peak offset, resting between %.3f and %.3f mm" % [
		offset_peak, offset_span.x, offset_span.y])
	print("player_test: idle screen %.3f mean change between frames, %d loud pixels" % [
		frame_total / float(IDLE_FRAMES), loud])
	if world == null:
		return


## Puts the body upright on the surface anywhere on the planet. `_place` only
## works near the landing site, whose frame every offset in this file is in.
func _stand_on(direction: Vector3) -> void:
	var up := _planet.global_transform.basis * direction
	var north := Vector3.UP - direction * Vector3.UP.dot(direction)
	if north.length_squared() < 0.001:
		north = Vector3.RIGHT - direction * Vector3.RIGHT.dot(direction)
	_player._apply_stance(STAND)
	_player._run_speed = _player.walk_speed
	_player.global_transform = Transform3D(
		Basis.looking_at(_planet.global_transform.basis * north.normalized(), up),
		_planet.standing_position(direction, 0.3))
	_player.velocity = Vector3.ZERO


## Every live material that vivid_plant is drawing with.
##
## Taken off the tiles rather than loaded by path, and that is the whole reason
## this exists: PlantSpecies duplicates its material once per species and once
## per level of detail, so `grass.tres` on disk is not the material any blade is
## drawn with and writing a uniform to it changes nothing at all. A run that set
## the calming to "still every plant on the planet" and measured no difference
## whatever was measuring exactly that mistake.
## Every shader material drawn through a MultiMesh, whichever shader it is on.
## [method _plant_materials] is the vivid_plant subset of this.
func _instanced_materials(from: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for node in _multimeshes(from):
		var used := node.material_override as ShaderMaterial
		if used == null and node.multimesh != null and node.multimesh.mesh != null:
			for surface in node.multimesh.mesh.get_surface_count():
				used = node.multimesh.mesh.surface_get_material(surface) as ShaderMaterial
				if used != null:
					break
		if used != null and not found.has(used):
			found.append(used)
	return found


func _plant_materials(from: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	for node in _multimeshes(from):
		var used := node.material_override as ShaderMaterial
		if used == null and node.multimesh != null and node.multimesh.mesh != null:
			for surface in node.multimesh.mesh.get_surface_count():
				used = node.multimesh.mesh.surface_get_material(surface) as ShaderMaterial
				if used != null:
					break
		if used == null or used.shader == null:
			continue
		if not used.shader.resource_path.ends_with("vivid_plant.gdshader"):
			continue
		if not found.has(used):
			found.append(used)
	return found


## Saves a frame and hands it back, so two lighting states can be differenced
## as well as looked at.
func _frame(shot_name: String) -> Image:
	await _shot(shot_name)
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## Internal children are where both flora systems keep their pooled lights.
func _omni_lights(from: Node) -> Array[OmniLight3D]:
	var found: Array[OmniLight3D] = []
	for child in from.get_children(true):
		if child is OmniLight3D:
			found.append(child)
		found.append_array(_omni_lights(child))
	return found


func _lit_lights(lights: Array[OmniLight3D]) -> int:
	var lit := 0
	for light in lights:
		if light.visible and light.light_energy > 0.01:
			lit += 1
	return lit


func _light_energy(lights: Array[OmniLight3D]) -> float:
	var total := 0.0
	for light in lights:
		total += light.light_energy
	return total


## Every MultiMeshInstance3D in the world, internal children included.
func _multimeshes(from: Node) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child in from.get_children(true):
		if child is MultiMeshInstance3D:
			found.append(child)
		found.append_array(_multimeshes(child))
	return found


## Every streamed plant multimesh in the world.
##
## Walked by hand with `get_children(true)` rather than with `find_children`,
## which does not return internal children — and every one of these is one.
## Missing them is not a quiet failure either: the list comes back empty, the
## "blades hidden" row hides nothing, and the grass then dominates a reading
## that was supposed to be about the ground under it.
## Returns the nodes that *own* those multimeshes rather than the multimeshes
## themselves, because the owner is the only thing worth hiding: the streamers
## rebuild and re-show their own tiles every few frames, so a `visible = false`
## written onto a tile is gone again before the next reading is taken. Hiding
## the parent takes the whole field out through inherited visibility, which
## nothing writes back over.
func _grass_covers(from: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in from.get_children(true):
		if child is MultiMeshInstance3D:
			var host := child.get_parent() as Node3D
			if host != null and not found.has(host):
				found.append(host)
			continue
		found.append_array(_grass_covers(child))
	return found


## The frame, cut down to a grid of single pixels. Nearest-neighbour on purpose:
## anything that averages neighbours together averages the shimmer away as well,
## and the shimmer is the measurement.
func _frame_sample() -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	image.resize(SHIMMER_WIDTH, SHIMMER_HEIGHT, Image.INTERPOLATE_NEAREST)
	return image.get_data()


## Mean change, worst change, and how many pixels moved by more than
## [constant SHIMMER_LOUD]. The count is the one that separates the two things
## a high "worst" can mean: a whole area breathing, or one white speck.
func _frame_difference(before: PackedByteArray, after: PackedByteArray) -> Vector3:
	var count := mini(before.size(), after.size())
	var total := 0
	var worst := 0
	var loud := 0
	for index in range(0, count, 3):
		var step := maxi(maxi(absi(before[index] - after[index]),
			absi(before[index + 1] - after[index + 1])),
			absi(before[index + 2] - after[index + 2]))
		total += step
		worst = maxi(worst, step)
		if step > SHIMMER_LOUD:
			loud += 1
	return Vector3(float(total) / maxf(count / 3, 1), float(worst), float(loud))


## How the added light is distributed about the sun: mean change within a third of
## the frame height of [param sun_uv], and mean change beyond two thirds of it.
##
## The number that separates the two things god rays can be, which a whole-frame
## mean cannot. Shafts are light from one place and must be far brighter at their
## root than out at the edges; a pass that mistakes the whole sky for the light
## source produces the same brightness everywhere, and reads as fog with the sun
## inside it. The first run of this effect had a near/far ratio near one.
func _ray_shape(before: PackedByteArray, after: PackedByteArray,
		sun_uv: Vector2) -> Vector2:
	var aspect := float(SHIMMER_WIDTH) / float(SHIMMER_HEIGHT)
	var near_total := 0.0
	var near_count := 0
	var far_total := 0.0
	var far_count := 0
	for y in SHIMMER_HEIGHT:
		for x in SHIMMER_WIDTH:
			var index := (y * SHIMMER_WIDTH + x) * 3
			if index + 2 >= before.size() or index + 2 >= after.size():
				continue
			var step := maxi(maxi(absi(before[index] - after[index]),
				absi(before[index + 1] - after[index + 1])),
				absi(before[index + 2] - after[index + 2]))
			var at := Vector2((float(x) + 0.5) / float(SHIMMER_WIDTH),
				(float(y) + 0.5) / float(SHIMMER_HEIGHT))
			# Scaled by aspect for the same reason the shader does it: a circle
			# around the sun in pixels is an ellipse in UV.
			var away := ((at - sun_uv) * Vector2(aspect, 1.0)).length()
			if away < 0.33:
				near_total += float(step)
				near_count += 1
			elif away > 0.66:
				far_total += float(step)
				far_count += 1
	return Vector2(near_total / maxf(near_count, 1.0),
		far_total / maxf(far_count, 1.0))


## The change between two frames, as a picture: white where it moved, so a
## glance says whether it is one sparkling edge or a whole lawn.
func _difference_picture(before: PackedByteArray, after: PackedByteArray) -> Image:
	var picture := Image.create_empty(SHIMMER_WIDTH, SHIMMER_HEIGHT, false, Image.FORMAT_RGB8)
	for y in SHIMMER_HEIGHT:
		for x in SHIMMER_WIDTH:
			var index := (y * SHIMMER_WIDTH + x) * 3
			if index + 2 >= before.size() or index + 2 >= after.size():
				continue
			var step := maxi(maxi(absi(before[index] - after[index]),
				absi(before[index + 1] - after[index + 1])),
				absi(before[index + 2] - after[index + 2]))
			# Amplified four times, so a change of sixty is already white and
			# the faint ones are visible at all.
			var level := minf(step * 4.0 / 255.0, 1.0)
			picture.set_pixel(x, y, Color(level, level, level))
	return picture


func _shot(shot_name: String) -> void:
	# The dummy headless renderer never emits frame_post_draw. Visual runs still
	# save captures; command-line policy/physics checks must be allowed to finish.
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	if error != OK:
		print("player_test: shot %s failed: %s" % [shot_name, error_string(error)])
