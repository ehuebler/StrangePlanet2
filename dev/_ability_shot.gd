extends Node

## Captures the two abilities being used, close up and at the distance they are
## actually played at.
##
##     godot --path . dev/_ability_shot.tscn
##
## Not headless: the dummy renderer never draws a frame, so there is nothing to
## save. This is the visual half of the plan's validation — the colour-paint
## rule asks for one close view and one gameplay-distance view of anything whose
## look changes, and burning flora black changes it.

const WORLD := preload("res://game/world.tscn")
const SHOT_DIR := "res://dev/captures/"
const TERRAIN_FRAMES := 160
## Long enough for a marked region to be rebuilt through the quadtree's
## per-frame budget and for a new collider to be generated under the player.
const REBUILD_FRAMES := 240

var _player: OnlinePlayer
var _planet: Planet


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	var world := WORLD.instantiate()
	add_child(world)
	await _wait(10)
	_planet = world.find_child("Planet", true, false) as Planet
	var site := world.find_child("LandingSite", true, false) as Node3D
	_player = get_tree().get_first_node_in_group("network_players") \
		as OnlinePlayer
	if _planet == null or site == null or _player == null:
		push_error("ability_shot: planet=%s site=%s player=%s" % [
			_planet, site, _player])
		get_tree().quit(1)
		return
	_player.global_transform = site.global_transform
	_player.velocity = Vector3.ZERO
	_player.abilities.set_item(0, "laser_eyes")
	_player.abilities.set_item(1, "meteor_punch")
	await _wait(TERRAIN_FRAMES)
	var controller := _player.ability_controller()
	print("ability_shot: slots %s / %s, controller %s / %s" % [
		_player.abilities.get_item(0), _player.abilities.get_item(1),
		controller.ability_in(0) if controller != null else null,
		controller.ability_in(1) if controller != null else null])

	var arguments := OS.get_cmdline_user_args()
	if arguments.has("--nausicaa-only"):
		_player.abilities.set_item(1, "nausicaa")
		await _wait(4)
		await _nausicaa_shots()
		get_tree().quit()
		return
	if arguments.has("--new-only"):
		await _new_ability_shots(world)
		get_tree().quit()
		return
	await _laser_shots()
	await _meteor_shots()
	await _new_ability_shots(world)
	get_tree().quit()


## The beam at arm's length and then from where it is actually seen. Both are
## taken while it is firing, and one after, because the mark it leaves is as
## much of the ability as the beam is.
func _laser_shots() -> void:
	var here := _cover_nearby()
	_stand_facing(here, 11.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	await _wait(20)
	await _turn_to_open(14.0)
	# Shallow enough that the beam has a few metres to cross before it lands.
	# Straight down the beam is a dot at the player's feet and the burn is behind
	# the character's own shoulder.
	_player._pitch = -0.28
	await _wait(4)
	await _ready_in(0)
	var before := await _frame("ability_laser_close_before")
	print("ability_shot: laser close dispatched=%s" % _player.activate_ability(0))
	await _wait(24)
	print("ability_shot: laser held=%s beams=%s marks=%d" % [
		_player.ability_controller().ability_in(0).is_held(),
		_player.laser_beams().visible, _burn_marks()])
	_report_ray()
	await _shot("ability_laser_close")
	await _side_shot("ability_laser_close_side")
	await _face_shot("ability_laser_face")
	await _wait(40)
	_player.release_ability(0)
	print("ability_shot: laser left %d marks, %d scars" % [
		_burn_marks(), _planet.shape.scars.count()])
	await _wait(REBUILD_FRAMES)
	await _shot("ability_laser_close_after")
	_report_scar()
	await _look_down_at_burn()
	await _shot("ability_laser_close_burn")
	_hide_burn_marks()
	var after := await _frame("ability_laser_close_scar")
	_difference(before, after, "ability_laser_close_burned")

	_stand_facing(here, 45.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	_player._pitch = -0.1
	await _wait(30)
	await _ready_in(0)
	_player.activate_ability(0)
	await _wait(30)
	await _shot("ability_laser_distance")
	await _side_shot("ability_laser_distance_side")
	_player.release_ability(0)
	await _wait(REBUILD_FRAMES)
	await _shot("ability_laser_distance_after")


## The punch both ways: dived out of a flight, and thrown flat off a run.
func _meteor_shots() -> void:
	var here := _cover_nearby()
	_stand_facing(here, 90.0)
	_player.start_flying()
	_player.global_position += _planet.up_at(_player.global_position) * 90.0
	_player._pitch = -0.55
	await _wait(20)
	await _ready_in(1)
	print("ability_shot: flight punch dispatched=%s" % _player.activate_ability(1))
	# Far enough in that the punch's pose has finished crossfading, well short of
	# the reach being spent.
	await _wait(12)
	print("ability_shot: flying stance=%d speed=%.0f" % [
		_player.stance(), _player.velocity.length()])
	await _shot("ability_meteor_flight")
	await _side_shot("ability_meteor_flight_side", 3.0, 6.0)
	await _wait(120)
	await _shot("ability_meteor_flight_landed")
	await _wait(REBUILD_FRAMES)
	await _crater_view()
	await _shot("ability_meteor_flight_crater")

	_stand_facing(here, 40.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	_player._pitch = 0.0
	await _wait(20)
	await _ready_in(1)
	var from := _player.global_position
	print("ability_shot: run punch dispatched=%s stance=%d" % [
		_player.activate_ability(1), _player.stance()])
	await _wait(12)
	print("ability_shot: running punch stance=%d speed=%.0f, %.1f m out" % [
		_player.stance(), _player.velocity.length(),
		from.distance_to(_player.global_position)])
	await _shot("ability_meteor_run")
	await _side_shot("ability_meteor_run_side", 3.0, 6.0)
	await _wait(130)
	print("ability_shot: scars now %d" % _planet.shape.scars.count())
	await _shot("ability_meteor_run_landed")
	await _wait(REBUILD_FRAMES)
	await _crater_view()
	await _shot("ability_meteor_run_crater")

	await _dive_shots(here)


## Exercises the remaining catalogue additions through the same in-world path
## used by play. Each effect gets a gameplay camera view plus a side or aftermath
## view that makes its shape, collision volume, or terrain result readable.
func _new_ability_shots(world: GameWorld) -> void:
	var dummy := world.find_child(
		"TrainingDummy", true, false) as TrainingDummy
	var arena := _cover_nearby()

	# Everything that wants intact ground goes before the nuke. It leaves a
	# seventy-metre hole in the middle of the arena, and the shots after it would
	# otherwise be of a player standing at the bottom of one.
	_player.abilities.set_item(0, "wall")
	_player.abilities.set_item(1, "nausicaa")
	await _wait(4)
	await _wall_shots()
	await _nausicaa_shots()

	if dummy != null:
		_player.abilities.set_item(0, "nuke")
		await _wait(4)
		# The long-distance shot is aimed along the horizon. Leaving the dummy
		# on that line makes it the blast centre and throws it back through every
		# frame meant to show the cloud. Removing it is more reliable than hiding
		# it: its respawn routine deliberately restores visibility and collision.
		dummy.queue_free()
		await get_tree().process_frame
		await _nuke_shots(arena)
		await _nuke_self_launch_shots(arena)


## The whole sequence, from a stand-off. Every stage gets its own frame because
## they do not look alike and none of them lasts: the white flash and the negative
## it leaves are gone inside a second, the cloud takes several to stand up, and the
## second front is still running out along the ground after both.
func _nuke_shots(arena: Vector3) -> void:
	# Outside the blast, taken from the authored radius. Any closer and every frame
	# below is of the caster being thrown by their own detonation rather than of the
	# detonation — that shot exists, and it is the next one.
	var reach := float(ItemDB.stats_of("nuke").get("radius", 0.0))
	_player._clear_ragdoll()
	_stand_facing(arena, reach + 55.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	await _wait(20)
	# Level along the tangent. Aiming at distant ground on a spherical world
	# points through the planet and detonates at the caster's feet; level flight
	# reaches max range a few metres over the surface, close enough to cut it.
	_player._pitch = 0.0
	await _ready_in(0)
	var scars_before := _planet.shape.scars.count()
	print("ability_shot: nuke dispatched=%s from %.0f m" % [
		_player.activate_ability(0), reach + 55.0])
	await _wait(6)
	await _shot("ability_nuke_projectile")
	await _side_shot("ability_nuke_projectile_side", 5.0, 10.0)
	for _frame in 240:
		await get_tree().process_frame
		if _planet.shape.scars.count() > scars_before:
			break
	print("ability_shot: nuke added crater=%s" % (
		_planet.shape.scars.count() > scars_before))
	var scar: TerrainScars.Scar
	if _planet.shape.scars.count() > scars_before:
		var scars: Array = _planet.shape.scars.get("_scars")
		scar = scars.back() as TerrainScars.Scar
	var impact := arena
	var crater_reach := float(
		ItemDB.stats_of("nuke").get("crater_radius", reach * 0.5))
	if scar != null:
		impact = _planet.global_transform \
			* _planet.shape.surface_point(scar.direction)
		crater_reach = scar.outer

	# The next rendered frame is the white wash. A fraction of a second later it
	# has yielded to the negative the user sees for the rest of the first second.
	await _shot("ability_nuke_flash")
	await _wait_seconds(0.2)
	await _shot("ability_nuke_invert")

	# Past the one-second screen treatment, so the observer can show the world
	# effect itself instead of photographing the post-process twice.
	await _wait_seconds(0.9)
	await _blast_observer_shot(
		"ability_nuke_blast", impact, reach, 2.25, 0.55, 0.35)
	# Far enough along that the cloud has climbed clear of the fireball and the
	# secondary front has left the first behind.
	await _wait_seconds(1.4)
	await _blast_observer_shot(
		"ability_nuke_mushroom", impact, reach, 2.4, 0.95, 0.72)
	await _blast_observer_shot(
		"ability_nuke_shockwave_side", impact, reach, 3.2, 0.35, 0.12)

	# Let the cloud clear and the wide terrain rebuild finish before judging the
	# hole; otherwise its translucent cap sits over the overhead rim shot.
	await _wait_seconds(4.8)
	_player._clear_ragdoll()
	# The body has just recovered from earlier reaction captures. Keep it out of
	# this observer frame entirely: the only subject here is the terrain it cut.
	_player.visible = false
	await _blast_observer_shot(
		"ability_nuke_crater", impact, crater_reach, 1.45, 0.55, -0.05)
	_player.visible = true
	# From overhead, which is the only view a rim that is not a circle reads from.
	await _overhead_shot("ability_nuke_crater_rim", impact, crater_reach)


## Point blank, which is the only way to reach the self-launch: the blast has to
## catch its own caster. What this is here to show is that the body goes up with
## the view. The camera hangs off the capsule and the character hangs off the
## limp bones, so a launch only one of the two is allowed to keep reads as a
## camera flying away from a player still standing on the ground — and the two
## climbs are printed as well as photographed, because a screenshot cannot say
## how far either of them got.
func _nuke_self_launch_shots(arena: Vector3) -> void:
	# Well clear of the crater the last shot dug, which is seventy metres across
	# and reaches further than that where its rim bulges. Dropped onto a lip whose
	# collider has not been rebuilt yet the player falls, crashes, and a crashed
	# player cannot cast at all.
	# This shot is specifically about starting a fresh self-launch. Do not let a
	# reaction from any preceding capture leave can_attack false while its body
	# has already found a standing pose.
	_player._clear_ragdoll()
	_stand_facing(arena,
		float(ItemDB.stats_of("nuke").get("crater_radius", 0.0)) * 2.2)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	await _wait(60)
	# Down at the ground a couple of metres ahead, so the caster is deep inside
	# the blast that follows rather than at the edge of it.
	_player._pitch = -0.6
	await _wait(10)
	await _ready_in(0)
	var from := _player.global_position
	var up := _planet.up_at(from)
	var body := _player._ragdoll
	var body_from := body.centre() if body != null else from
	print("ability_shot: nuke self stance=%d dispatched=%s" % [
		_player.stance(), _player.activate_ability(0)])
	var capsule_climb := 0.0
	var body_climb := 0.0
	var caught := false
	for _frame in 300:
		await get_tree().process_frame
		if _player.stance() != OnlinePlayer.Stance.CRASH:
			continue
		capsule_climb = maxf(capsule_climb,
			(_player.global_position - from).dot(up))
		if body != null and body.limp():
			body_climb = maxf(body_climb, (body.centre() - body_from).dot(up))
		# From the side, and well clear of the ground: the whole point is to see
		# the limp body and the camera that hangs off its collider at the same
		# height, which the player's own view cannot show.
		if not caught and capsule_climb > 18.0:
			caught = true
			await _side_shot("ability_nuke_self_launch", 4.0, 14.0)
	print("ability_shot: nuke self-launch capsule=%.1f m body=%.1f m" % [
		capsule_climb, body_climb])
	await _shot("ability_nuke_self_landed")
	_player._clear_ragdoll()
	await _wait(10)


func _wall_shots() -> void:
	var here := _cover_nearby()
	_stand_facing(here, 22.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	_player._pitch = 0.0
	await _wait(20)
	await _ready_in(0)
	print("ability_shot: wall dispatched=%s" % _player.activate_ability(0))
	await _wait(10)
	await _shot("ability_wall_gameplay")
	await _side_shot("ability_wall_close", 3.0, 10.0)
	var barriers := get_tree().get_nodes_in_group("ability_barriers")
	if not barriers.is_empty() and barriers[0] is AbilityBarrier:
		var barrier := barriers[0] as AbilityBarrier
		_stand_facing(barrier.global_position, 18.0)
		await _wait(20)
		await _shot("ability_wall_distance")


func _nausicaa_shots() -> void:
	var here := _cover_nearby()
	_stand_facing(here, 22.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	# Down far enough that the fourteen-metre beam actually reaches terrain.
	# Empty air and props are deliberately not paintable.
	_player._pitch = -0.18
	await _wait(20)
	await _ready_in(1)
	var scars_before := _planet.shape.scars.count()
	print("ability_shot: nausicaa dispatched=%s" % _player.activate_ability(1))
	# Sweep the short-lived eye beam laterally. Each accepted landing point is a
	# separate blue patch, so the fuse order is also the order this arc is drawn.
	var up := _planet.up_at(_player.global_position)
	for frame in 24:
		_player.global_basis = _player.global_basis.rotated(up, deg_to_rad(1.0))
		await get_tree().process_frame
		if frame == 6:
			await _shot("ability_nausicaa_beam")
	await _side_shot("ability_nausicaa_warning", 4.0, 10.0)
	for _frame in 120:
		await get_tree().process_frame
		if _planet.shape.scars.count() > scars_before:
			break
	print("ability_shot: nausicaa began chain=%s" % (
		_planet.shape.scars.count() > scars_before))
	await _side_shot("ability_nausicaa_chain", 5.0, 12.0)
	# The first patch has gone off; leave enough time for the equal fuses on the
	# later patches to advance the blast all the way to the end of the trail.
	await _wait_seconds(1.0)
	await _wait(REBUILD_FRAMES)
	await _crater_view()
	await _shot("ability_nausicaa_indent")


## Relocates the test target to the same dry patch selected for the camera
## harness. Vacationer's Landing is intentionally coastal; stepping around it
## for a framing shot can otherwise put a water-blocked ability in the sea.
func _place_dummy(dummy: TrainingDummy, at: Vector3) -> void:
	var direction := _planet.to_local(at).normalized()
	var up := _planet.up_at(at)
	var forward := -_player.global_basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.001:
		forward = up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
	dummy.global_transform = Transform3D(
		Basis.looking_at(forward.normalized(), up),
		_planet.standing_position(direction, 0.0))
	dummy.velocity = Vector3.ZERO
	dummy.reset_physics_interpolation()


## Sets both halves of third-person aim: yaw lives on the body while pitch
## lives on the head. This puts the target's combat centre on the crosshair
## rather than assuming equal eye heights.
func _aim_at(target: Vector3) -> void:
	var up := _planet.up_at(_player.global_position)
	var toward := target - _player.camera.global_position
	var flat := toward - up * toward.dot(up)
	if flat.length_squared() > 0.001:
		_player.global_basis = Basis.looking_at(flat.normalized(), up)
	if toward.length_squared() > 0.001:
		_player._pitch = asin(clampf(
			toward.normalized().dot(up), -1.0, 1.0))
	await _wait(5)


## The punch thrown out of a fast dive, which is the case the other two do not
## reach: flight tops out five times above the punch's own speed, and what
## arrives at that speed digs a hole to match.
func _dive_shots(here: Vector3) -> void:
	_stand_facing(here, 120.0)
	# Lifted first and flown second, or the previous frame's footing ends the
	# take-off again on the frame after it.
	_player.global_position += _planet.up_at(_player.global_position) * 500.0
	await _wait(6)
	_player.start_flying()
	_player._pitch = -1.2
	await _wait(6)
	await _ready_in(1)
	_player.velocity = _player.look_direction() * 600.0
	var was := _planet.shape.scars.count()
	print("ability_shot: dive punch dispatched=%s at %.0f m/s" % [
		_player.activate_ability(1), _player.velocity.length()])
	await _wait(10)
	await _shot("ability_meteor_dive")
	for _frame in 600:
		await get_tree().process_frame
		if _planet.shape.scars.count() > was:
			break
	var cut: Dictionary = _planet.shape.scars.to_wire().back()
	print("ability_shot: dive cut r=%.1f depth=%.1f, stance=%d" % [
		float(cut.get("radius", 0.0)), float(cut.get("depth", 0.0)),
		_player.stance()])
	await _wait(REBUILD_FRAMES)
	await _crater_view()
	await _shot("ability_meteor_dive_crater")
	await _side_shot("ability_meteor_dive_side", 6.0, 14.0)


## Close on the head, which is the only view that can answer where the beams
## leave from. Every other shot stands far enough back that the bridge of the
## nose and the back of the neck are the same pixel, which is how a beam fired
## out of the back of the head went unnoticed: it still lands on the crosshair.
func _face_shot(shot_name: String) -> void:
	var ran := _player.process_mode
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var eyes := _player.eye_points()
	var middle: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var along := _player.aim_direction(middle)
	var up := _planet.up_at(middle)
	var side := along.cross(up).normalized()
	var watcher := Camera3D.new()
	add_child(watcher)
	# Ahead and round to one side, so the face and the first stretch of the beam
	# are both in frame. Straight on, the beam is a dot hiding its own origin.
	watcher.global_position = middle + along * 0.85 + side * 0.7 + up * 0.1
	watcher.look_at(middle, up)
	watcher.fov = 42.0
	watcher.current = true
	await _wait(2)
	await _shot(shot_name)
	watcher.queue_free()
	_player.camera.current = true
	_player.process_mode = ran
	await _wait(2)


## The same moment from off to one side. The game is played from behind the
## player's own head, which is the one angle a beam fired from that head is a dot
## rather than a line, so a shot down the view axis cannot say whether the beam
## is drawn at all. This one is not a gameplay view and is not meant to be: it is
## the view that can answer the question.
func _side_shot(shot_name: String, ahead := 6.0, out := 12.0) -> void:
	# The body is held still while the camera is moved into place. A punch covers
	# three metres a frame, and the two frames a new camera takes to become the
	# current one are enough to leave the subject behind the lens. Stopping the
	# node rather than pausing the tree, because the world keeps a running game
	# running through a pause.
	var ran := _player.process_mode
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var eye: Vector3 = _player.eye_points()[0]
	var along := _player.aim_direction(eye)
	var up := _planet.up_at(eye)
	var side := along.cross(up).normalized()
	if side.length_squared() < 0.000001:
		_player.process_mode = ran
		return
	var watcher := Camera3D.new()
	add_child(watcher)
	watcher.global_position = eye + along * ahead + side * out + up * 1.5
	# Aimed short of the point it stands off from, so the player is in the frame
	# rather than at the edge of it looking out.
	watcher.look_at(eye + along * (ahead * 0.35), up)
	watcher.current = true
	await _wait(2)
	await _shot(shot_name)
	watcher.queue_free()
	_player.camera.current = true
	_player.process_mode = ran
	await _wait(2)


## A camera far enough from a hundred-metre detonation to put the whole thing in
## frame. The regular side view is framed around the player's hands; using it for
## the Nuke put the camera underneath the cloud and made its stem a white wall.
func _blast_observer_shot(shot_name: String, target: Vector3, reach: float,
		distance_share: float, height_share: float,
		aim_height_share: float) -> void:
	var ran := _player.process_mode
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var up := _planet.up_at(target)
	var side := up.cross(
		Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var watcher := Camera3D.new()
	add_child(watcher)
	watcher.global_position = target \
		+ side * reach * distance_share \
		+ up * reach * height_share
	watcher.look_at(target + up * reach * aim_height_share, up)
	watcher.fov = 62.0
	watcher.current = true
	await _wait(4)
	await _shot(shot_name)
	watcher.queue_free()
	_player.camera.current = true
	_player.process_mode = ran
	await _wait(2)


## Straight down from well above a point, which is the only view the outline of a
## hole reads from. From the ground a crater is a slope, and a slope cannot say
## whether the rim it belongs to is a circle.
func _overhead_shot(shot_name: String, target: Vector3, reach: float) -> void:
	var ran := _player.process_mode
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var up := _planet.up_at(target)
	var side := up.cross(
		Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var watcher := Camera3D.new()
	add_child(watcher)
	# High enough that the whole footprint is inside the frame.
	watcher.global_position = target + up * maxf(reach * 2.6, 30.0)
	watcher.look_at(target, side)
	watcher.current = true
	await _wait(4)
	await _shot(shot_name)
	watcher.queue_free()
	_player.camera.current = true
	_player.process_mode = ran
	await _wait(2)


## Backs the camera off and looks down, because a crater seen from a standing
## eye line at its own centre is just a horizon that is slightly too close.
func _crater_view() -> void:
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	_player._pitch = -0.45
	await _wait(6)


## Stands the player off the newest mark and looks down at it, because a burn
## two metres in front of a third-person camera is a burn behind the character.
func _look_down_at_burn() -> void:
	var scars: TerrainScars = _planet.shape.scars
	if scars.count() == 0:
		return
	var scar: TerrainScars.Scar = scars.get("_scars")[scars.count() - 1]
	_stand_facing(_planet.global_transform
		* _planet.shape.surface_point(scar.direction), 7.0)
	_player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_FAR)
	_player._pitch = -0.5
	await _wait(30)


## What the shape says about the newest mark, and what the mesh drawn over it
## actually ended up with. The two disagreeing is the difference between a scar
## that was never registered and one that was never rebuilt.
func _report_scar() -> void:
	var scars: TerrainScars = _planet.shape.scars
	if scars.count() == 0:
		print("ability_shot: no scar to report")
		return
	var scar: TerrainScars.Scar = scars.get("_scars")[scars.count() - 1]
	var here := scar.direction
	var side := here.cross(Vector3.UP).normalized()
	var away := (here + side * (scar.radius * 2.0
		/ _planet.shape.radius)).normalized()
	print("ability_shot: scar r=%.1f depth %.2f m, tint %s vs clean %s" % [
		scar.radius, scars.depth_at(here),
		_ground_colour(here), _ground_colour(away)])
	print("ability_shot: mesh colour %s vs clean %s" % [
		_mesh_colour(here), _mesh_colour(away)])


## What the shape would paint the ground under a direction, sampled the way the
## mesh builder samples it.
func _ground_colour(direction: Vector3) -> Color:
	return _planet.shape.color_at(direction,
		_planet.shape.elevation(direction), direction)


## The vertex colour the drawn mesh is carrying nearest a direction, which is
## the only proof that a rebuild actually happened.
func _mesh_colour(direction: Vector3) -> Color:
	var at := direction * (_planet.shape.radius
		+ _planet.shape.elevation(direction))
	var best := Color.TRANSPARENT
	var nearest := INF
	for node in _planet.find_children("*", "MeshInstance3D", true, false):
		var piece := node as MeshInstance3D
		if piece.mesh == null or piece.mesh.get_surface_count() == 0:
			continue
		if not piece.is_visible_in_tree():
			continue
		var arrays := piece.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: Variant = arrays[Mesh.ARRAY_COLOR]
		if colours == null:
			continue
		var frame := _planet.global_transform.affine_inverse() \
			* piece.global_transform
		for index in points.size():
			var away := (frame * points[index]).distance_to(at)
			if away < nearest:
				nearest = away
				best = (colours as PackedColorArray)[index]
	return best


## Takes the fading marks away and leaves the ones a scar owns, which is what
## the ground looks like once the beam is a memory. Anything still visible after
## this is something that is meant to still be there tomorrow.
func _hide_burn_marks() -> void:
	if _planet.scorches == null:
		return
	var kept: PackedByteArray = _planet.scorches.get("_kept")
	var marks: Array = _planet.scorches.get("_marks")
	for index in marks.size():
		if kept[index] == 0:
			(marks[index] as Decal).visible = false


## Turns on the spot until there is open ground ahead, so a beam meant to be
## seen crossing a hillside is not fired into a boulder five metres away.
func _turn_to_open(clearance: float) -> void:
	var up := _planet.up_at(_player.global_position)
	# Level, so this is a question about props in the way rather than about the
	# ground, which any beam aimed downwards is going to find immediately.
	_player._pitch = 0.0
	for _turn in 12:
		var eye: Vector3 = _player.eye_points()[0]
		var query := PhysicsRayQueryParameters3D.create(
			eye, eye + _player.aim_direction(eye) * clearance)
		query.exclude = [_player.get_rid()]
		if _player.get_world_3d().direct_space_state.intersect_ray(
				query).is_empty():
			return
		_player.global_basis = _player.global_basis.rotated(up, PI / 6.0)
		await _wait(2)


## What the first thing in front of the eyes actually is, and whether the beam
## considers it a plant worth passing through.
func _report_ray() -> void:
	var eye: Vector3 = _player.eye_points()[0]
	var query := PhysicsRayQueryParameters3D.create(
		eye, eye + _player.aim_direction(eye) * 60.0)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		print("ability_shot: beam reaches open sky")
		return
	var body := hit["collider"] as CollisionObject3D
	var shape := body.shape_owner_get_owner(
		body.shape_find_owner(int(hit["shape"]))) as Node
	print("ability_shot: beam first hits %s / %s at %.1f m, flora=%s" % [
		body.name, shape.name if shape != null else "?",
		eye.distance_to(hit["position"]),
		shape != null and shape.has_meta(GroundCover.IMPACT_OWNER_META)])


## Burn decals currently showing, read straight off the pool.
func _burn_marks() -> int:
	if _planet.scorches == null:
		return -1
	var showing := 0
	for mark in _planet.scorches.get("_marks"):
		if (mark as Decal).visible:
			showing += 1
	return showing


## Waits out a cooldown, so a shot is never of an ability that politely refused.
## Waits for a slot to come off cooldown, bounded in seconds rather than in
## frames. The budget has to cover the longest cooldown in the catalogue, and a
## frame count that does so at sixty frames a second falls well short of it at a
## hundred and ten — which reads as an ability that silently refused to fire.
func _ready_in(index: int) -> void:
	var ability := _player.ability_controller().ability_in(index)
	if ability == null:
		return
	var left := ability.cooldown() + 4.0
	while left > 0.0:
		if ability.can_use():
			return
		await get_tree().process_frame
		left -= get_process_delta_time()
	print("ability_shot: slot %d never came off cooldown, stance=%d" % [
		index, _player.stance()])


## Somewhere with plants on it, so a beam has something to burn. Searched rather
## than written down, because which biome the landing site sits in is not this
## file's business.
func _cover_nearby() -> Vector3:
	var best := _player.global_position
	var thickest := 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not (field is GroundCover):
			continue
		for stand in _stands_under(field):
			var showing := stand.multimesh.visible_instance_count
			if showing < 0:
				showing = stand.multimesh.instance_count
			if showing <= thickest:
				continue
			var buffer := stand.multimesh.buffer
			for index in showing:
				var at := index * 12
				if (at + 11) >= buffer.size():
					break
				if Vector3(buffer[at], buffer[at + 4],
						buffer[at + 8]).length() <= 0.001:
					continue
				thickest = showing
				best = stand.global_transform * Vector3(
					buffer[at + 3], buffer[at + 7], buffer[at + 11])
				break
	return best


func _stands_under(node: Node) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child in node.get_children(true):
		var stand := child as MultiMeshInstance3D
		if stand != null and stand.visible and stand.multimesh != null:
			found.append(stand)
		found.append_array(_stands_under(child))
	return found


## Puts the player that many metres from a point, on the ground, looking at it.
func _stand_facing(target: Vector3, away: float) -> void:
	var direction := _planet.to_local(target).normalized()
	var up := _planet.global_basis * direction
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		side = up.cross(Vector3.FORWARD)
	side = side.normalized()
	var stand_at := (direction + _planet.to_local(
		_planet.global_position + side).normalized()
		* (away / _planet.shape.radius)).normalized()
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	_player.global_transform = Transform3D(
		Basis.looking_at(-side, _planet.global_basis * stand_at),
		_planet.standing_position(stand_at, 0.4))
	_player.velocity = Vector3.ZERO
	_player._pitch = 0.0


func _wait(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame


## A presentation stage is authored in seconds, not in however many frames this
## machine happened to draw while recording it.
func _wait_seconds(seconds: float) -> void:
	var left := maxf(seconds, 0.0)
	while left > 0.0:
		await get_tree().process_frame
		left -= get_process_delta_time()


## Saves a frame and hands it back, so the same view before and after a burn can
## be subtracted.
func _frame(shot_name: String) -> Image:
	await _shot(shot_name)
	if DisplayServer.get_name() == "headless":
		return null
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


## What the ground gained, times six. The scar's own tint is worth a fraction of
## the albedo it lands on, which is easy to argue about by eye and impossible to
## argue about here.
func _difference(before: Image, after: Image, shot_name: String) -> void:
	if before == null or after == null:
		return
	var width := before.get_width()
	var height := before.get_height()
	var picture := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	var worst := 0.0
	for y in height:
		for x in width:
			var moved := before.get_pixel(x, y) - after.get_pixel(x, y)
			worst = maxf(worst, maxf(maxf(moved.r, moved.g), moved.b))
			picture.set_pixel(x, y, Color(
				clampf(moved.r * 6.0, 0.0, 1.0),
				clampf(moved.g * 6.0, 0.0, 1.0),
				clampf(moved.b * 6.0, 0.0, 1.0)))
	var path := ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	picture.save_png(path)
	print("ability_shot: %s darkened the view by at most %.3f" % [
		shot_name, worst])


func _shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("ability_shot: %s skipped, no renderer" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	print("ability_shot: %s %s" % [
		shot_name, "saved" if error == OK else error_string(error)])
