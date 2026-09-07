class_name CoordinatePlate
extends PanelContainer

## Where you are, in terms you can read out to somebody who is not here.
##
## A globe has no street to stand on and no world coordinate worth quoting — the
## origin is the planet's *centre*, eight kilometres underground, so a position
## vector is three large numbers that mean nothing on their own. So this reports
## a place the way a place on a globe is reported: latitude and longitude in the
## planet's own frame, height above sea level, the nearest named thing, and the
## surface under the reticle.
##
## Hidden during ordinary play and opened with the tilde navigation overlay. The
## last two lines are for reporting faults rather than for finding your way.
## [member Planet.statistics] knows the depth the
## ground under the viewer is drawn at and how many chunks near it have a
## collider, and those two numbers are what separates "the terrain looks wrong
## here" from "the terrain has not finished loading here" — a distinction no
## screenshot carries and the one most often needed to act on a report.
##
## The unit direction is the line to quote at a harness. Four decimals is 0.8 m
## on this planet, which is close enough to stand a camera on the same rock.

## Gap from the bottom and right edges of the screen, in pixels.
const MARGIN := 12.0
const LINE_SIZE := 8
const PAD_X := 8
const PAD_Y := 6
const ROW_COUNT := 9
## Times a second the readout is rewritten. It is a number for a person to read,
## and one that changes every frame cannot be read at all — nor written down,
## which is the whole point of it. It is also what keeps
## [method Planet.statistics] off the frame: that call walks every drawn chunk.
const REFRESH_HZ := 6.0
## How far above and below the body the floor probe looks, in metres. Up enough
## to start clear of a body standing in a dip, down enough to find the seabed
## from the surface of shallow water.
const PROBE_UP := 3.0
const PROBE_DOWN := 30.0

## The body the readout is being taken for, excluded from the floor probe.
##
## Not optional, and setting the ray's mask does not do it: the player is on
## layer 1 like the terrain, so a probe cast from three metres up hit the top of
## the capsule it started inside and reported a floor 1.5 m *above* the feet. The
## one line on screen that says whether the ground you can see is solid was
## answering with the body standing on it — so it never once printed
## `NO COLLIDER`, and every real hole looked like a floor at a strange height.
var body: CollisionObject3D
## The camera-centred ray that follows the reticle. Shared with interaction and
## aiming rather than duplicated, so every system agrees about what is pointed
## at and this readout adds no physics query of its own.
var aim_ray: RayCast3D

var _lines: VBoxContainer
var _elapsed := 0.0
var _motion_state := "standing"
var _motion_pov := "first person"
var _motion_speed := 0.0
## The world's day/night clock, found once. Looked up by type rather than by
## name for the same reason the player finds its planet that way: the node is a
## sibling of the world's other fixtures and never moves between them.
var _cycle: CelestialCycle


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-right and content-sized: this is diagnostic context rather than a
	# primary play control, so it stays out of the skyline and weapon bar.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	RedHudTheme.panel(self)

	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_theme_constant_override("margin_left", PAD_X)
	padding.add_theme_constant_override("margin_right", PAD_X)
	padding.add_theme_constant_override("margin_top", PAD_Y)
	padding.add_theme_constant_override("margin_bottom", PAD_Y)
	add_child(padding)

	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 1)
	padding.add_child(_lines)
	for row in ROW_COUNT:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		RedHudTheme.label(label, LINE_SIZE)
		_lines.add_child(label)


## The two lower-left plates this replaces are sampled into one compact line.
## Stored every frame but drawn with the location readout's six-hertz cadence.
func set_motion_info(state: String, pov: String, speed: float) -> void:
	_motion_state = state
	_motion_pov = pov
	_motion_speed = maxf(speed, 0.0)


## Rewrites the readout, at most [constant REFRESH_HZ] times a second.
func refresh(at: Vector3, planet: Planet, delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0 / REFRESH_HZ:
		return
	_elapsed = 0.0
	_write(8, "%s  %d m/s   %s   %d fps" % [
		_motion_state,
		roundi(_motion_speed),
		_motion_pov,
		Engine.get_frames_per_second(),
	])
	if planet == null or planet.shape == null:
		_write(0, "no planet")
		return

	var local := planet.to_local(at)
	var direction := local.normalized()
	var stats := planet.statistics()
	# The spacing the ground under the viewer was actually built at, which is what
	# the player's own guard now samples at. Asking for unlimited detail instead
	# reports a terrain nothing in the game is standing on.
	var spacing := planet.spacing_underfoot()
	_write(0, _nearest_place(at))
	_write(1, "lat %s   lon %s" % [
		_degrees(rad_to_deg(asin(clampf(direction.y, -1.0, 1.0))), "N", "S"),
		_degrees(rad_to_deg(atan2(direction.x, direction.z)), "E", "W")])
	_write(2, _time_of_day(at, planet))
	_write(3, _reticle_position(at, planet))
	_write(4, "alt %d m   ground %d m" % [
		roundi(local.length() - planet.shape.radius),
		roundi(planet.shape.elevation(direction, spacing))])
	_write(5, "dir %.4f, %.4f, %.4f" % [direction.x, direction.y, direction.z])
	# A depth of -1 is nothing drawn over the viewer at all, which is not depth 0
	# and must not print as it: it is the one state in which the field the guard
	# is sampling belongs to no chunk on screen.
	var depth := int(stats["depth"])
	_write(6, "lod %s/%d   %d colliders%s" % [
		"-" if depth < 0 else str(depth), planet.max_depth, int(stats["bodies"]),
		# Only while it is happening. A queue that is draining is the normal
		# state on arrival and saying so every frame would train the eye to
		# ignore the line that matters when it is *not* draining.
		"   loading %d" % int(stats["floorless"]) if int(stats["floorless"]) > 0 else ""])
	_write(7, _floor_under(at, planet, direction, spacing))


## Where the sixteen-minute day has got to, and what the sun is doing here.
##
## The clock and the sun angle are both printed because they answer different
## questions. The clock says the cycle is running at all — it is the line to
## watch when the complaint is that nothing is changing. The angle says what
## this particular patch of planet should look like, which the clock cannot: the
## day advances everywhere at once, but the far side of the world is in darkness
## while the landing is at noon.
func _time_of_day(at: Vector3, planet: Planet) -> String:
	var cycle := _celestial_cycle()
	if cycle == null or cycle.sun == null:
		return "day  no cycle"
	# Phase zero puts the sun over the landing, so that is the hour the clock is
	# anchored to and midday is what a fresh game starts at.
	var hours := fposmod(cycle.phase() * 24.0 + 12.0, 24.0)
	var up := (at - planet.global_position).normalized()
	# The light's +Z is the way to the sun; its sine against local up is the
	# elevation, so this is negative exactly when the sun is below the horizon.
	var elevation := rad_to_deg(asin(clampf(
		up.dot(cycle.sun.global_basis.z.normalized()), -1.0, 1.0)))
	return "day %02d:%02d   sun %+d deg   %s" % [
		int(hours), int(fposmod(hours * 60.0, 60.0)), roundi(elevation),
		_sky_state(elevation)]


## The three states worth naming, cut where the sky shader's own dusk band is:
## it stops putting the air out around eight degrees up and has finished by
## seventeen degrees down.
func _sky_state(elevation: float) -> String:
	if elevation > 8.0:
		return "daylight"
	if elevation > -17.0:
		return "twilight"
	return "night"


func _celestial_cycle() -> CelestialCycle:
	if is_instance_valid(_cycle):
		return _cycle
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for child in scene.get_children():
		if child is CelestialCycle:
			_cycle = child as CelestialCycle
			return _cycle
	return null


## Distance and planetary coordinates of the surface under the crosshair.
## Props use the point where their collider was hit, so aiming at a ship still
## reports the patch of planet it occupies. No collision is stated plainly rather
## than leaving the previous point frozen on screen.
func _reticle_position(at: Vector3, planet: Planet) -> String:
	if aim_ray == null:
		return "reticle  unavailable"
	aim_ray.force_raycast_update()
	if not aim_ray.is_colliding():
		return "reticle  no surface within %d m" % roundi(aim_ray.target_position.length())
	var hit := aim_ray.get_collision_point()
	var local := planet.to_local(hit)
	if local.length_squared() < 1.0:
		return "reticle  invalid surface"
	var direction := local.normalized()
	return "reticle %d m   %s, %s" % [
		roundi(at.distance_to(hit)),
		_degrees(rad_to_deg(asin(clampf(direction.y, -1.0, 1.0))), "N", "S"),
		_degrees(rad_to_deg(atan2(direction.x, direction.z)), "E", "W"),
	]


## The two floors under the feet, and whether they agree.
##
## `field` is the height field, which is what the player's own ground guard is
## holding them up with and is always there. `mesh` is a real collider found by
## a real ray, and is the one that can be missing — when it is, the surface you
## can see is a surface you go through, and this line is the only thing on
## screen that says so. Reported apart rather than as a difference because the
## interesting reading is one of them being absent, not the two disagreeing.
func _floor_under(at: Vector3, planet: Planet, direction: Vector3,
		spacing: float) -> String:
	var up := planet.global_transform.basis * direction
	var field := at.distance_to(planet.global_position) \
		- planet.shape.radius - planet.shape.elevation(direction, spacing)
	var query := PhysicsRayQueryParameters3D.create(at + up * PROBE_UP, at - up * PROBE_DOWN)
	query.collision_mask = 1
	# The player's own capsule is not the floor, and it is on the same layer the
	# terrain is, so it has to be named rather than masked out.
	if body != null:
		query.exclude = DamageHit.rid_list(body.get_rid())
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return "floor  NO COLLIDER   field %.1f m" % field
	return "floor  mesh %.1f m   field %.1f m" % [
		hit["position"].distance_to(at + up * PROBE_UP) - PROBE_UP, field]


## The planet's own frame, so the poles are where the ice is. Longitude runs from
## the planet's local +Z and counts east toward +X, which is a choice and not a
## convention — nothing else in the project measures one, so it only has to agree
## with itself.
func _degrees(value: float, positive: String, negative: String) -> String:
	return "%.2f %s" % [absf(value), positive if value >= 0.0 else negative]


func _nearest_place(at: Vector3) -> String:
	var closest: Landmark = null
	var nearest := INF
	for node in get_tree().get_nodes_in_group(Landmark.GROUP):
		if not is_instance_valid(node):
			continue
		var landmark := node as Landmark
		if landmark == null:
			continue
		var span := landmark.global_position.distance_to(at)
		if span < nearest:
			nearest = span
			closest = landmark
	if closest == null:
		return "nowhere named"
	return "%s  %s" % [closest.title, Landmark.distance_text(nearest)]


func _write(row: int, text: String) -> void:
	var label := CrtType.inner(_lines.get_child(row)) as Label
	if label != null:
		label.text = text
