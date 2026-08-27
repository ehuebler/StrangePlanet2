extends Node3D

## Vacationer's Landing and the flower field: the numbers and the pictures.
##
##     & $godot --path . dev/_landing_test.tscn
##     & $godot --path . dev/_landing_test.tscn -- --nosway
##
## It boots the real `game/world.tscn` rather than standing a planet up of its
## own, because most of what can go wrong here is wiring: a field whose
## `clear_of` points at nothing, a waypoint that never draws, a bloom that came
## up in the sea. A harness that rebuilt the scene would pass with all three
## broken.
##
## What it measures:
##
## - **The shore.** Where the landing landmark stands, how level the ground
##   under it is, and how far it is from the sea.
## - **The field.** What grew, and then the rules themselves as measurements:
##   the lowest plant against sea level, the nearest one to the landing, the
##   steepest ground any of them ended up on. Those three are the request — off
##   the shore, off the sharp ground, away from the keep-out — and each is a
##   number rather than a matter of opinion. Also what the streaming is doing,
##   which is the difference between the plants that exist and the plants being
##   drawn.
## - **The sway.** There is nothing left to measure it on: the bend is a vertex
##   shader and no CPU-side value moves when a plant leans. So it is measured
##   off the picture instead, by photographing the same flowers from the same
##   camera with a body near them and without, and counting the pixels that
##   changed. Wind is measured the same way with nobody in frame, and then
##   turned off so that the walker can be measured on its own.
##
## `--nosway` skips the photography, which is the only slow part.

const WORLD := preload("res://game/world.tscn")
const SHOT_DIR := "res://dev/captures/"
## Mesh spacing at full detail, so the ground is judged as it is built.
const SPACING := 1.5

## Name, metres out from the subject along the local ground, metres up, and what
## to look at: the landing, or the flowers.
const VIEWS := [
	["landing_far", 300.0, 120.0, "landing"],
	["landing_shore", 90.0, 26.0, "landing"],
	["landing_ground", 34.0, 2.0, "landing"],
	["flowers_over", 26.0, 16.0, "bloom"],
	["flowers_close", 3.4, 1.1, "bloom"],
]

var _planet: Planet
var _landing: Landmark
var _field: GroundCover
var _flower: PlantSpecies
var _player: OnlinePlayer
var _camera: Camera3D


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	# Off, or every frame time below is the refresh rate and the field appears
	# to be free because the monitor is what is being measured.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	# An offline session, the way the world is entered from the menu. Without a
	# peer and a roster it opens its home screen instead of spawning anybody,
	# and there is nobody here to fly over to the landing.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	var world := WORLD.instantiate()
	add_child(world)
	for _frame in 40:
		await get_tree().process_frame
		_player = get_tree().get_first_node_in_group("network_players") as OnlinePlayer
		if _player != null:
			break
	if _player == null:
		push_error("landing_test: the world spawned nobody")
		get_tree().quit(1)
		return
	_camera = _player.camera
	_planet = world.find_children("*", "Planet", true, false).pop_front() as Planet
	_landing = world.find_child("VacationersLanding", true, false) as Landmark
	_field = world.find_children("*", "GroundCover", true, false).pop_front() as GroundCover
	if _planet == null or _landing == null or _field == null:
		push_error("landing_test: world.tscn is missing the planet, the landing or the field")
		get_tree().quit(1)
		return
	_flower = _field.species[0] as PlantSpecies

	_measure_landing()
	await _measure_waypoint()
	await _measure_field()
	_measure_flower_vat()
	for view: Array in VIEWS:
		await _shot(str(view[0]), view[1] as float, view[2] as float, str(view[3]))
	if not "--nosway" in OS.get_cmdline_user_args():
		await _measure_sway()
	get_tree().quit()


func _measure_flower_vat() -> void:
	print("--- flower VAT ---")
	if _flower.vat == null or _flower.distant_vat == null:
		push_error("landing_test: both flower LODs must carry their own VAT")
		return
	var near_ok := _flower.vat.validate_mesh(_flower.near_mesh())
	var far_ok := _flower.distant_vat.validate_mesh(_flower.distant_mesh())
	print("near/far frames  %d / %d" % [
		int(_flower.vat.frame_count), int(_flower.distant_vat.frame_count)])
	print("near/far mapping %s / %s" % [near_ok, far_ok])
	if not near_ok or not far_ok:
		push_error("landing_test: a flower LOD does not match its VAT vertex IDs")
	if _flower.near_material() == _flower.far_material():
		push_error("landing_test: flower LODs share a material and incompatible VAT uniforms")


# --- The landing ------------------------------------------------------------

func _measure_landing() -> void:
	var shape := _planet.shape
	var up: Vector3 = _landing.direction.normalized()
	var elevation := shape.elevation(up, SPACING)
	var normal := shape.normal_at(up, SPACING)
	print("--- vacationer's landing ---")
	print("title            %s" % _landing.title)
	print("elevation        %.1f m above sea level" % elevation)
	print("slope underfoot  %.2f deg" % rad_to_deg(
		acos(clampf(normal.dot(up), -1.0, 1.0))))
	print("from the town    %.0f m" % (
		CityLayout.CENTRE.normalized().angle_to(up) * shape.radius))
	print("to the sea       %.0f m" % _to_sea(shape, up))


## Roughly how far the water is, by walking out along the steepest downhill until
## the ground goes under.
func _to_sea(shape: PlanetShape, from: Vector3) -> float:
	var east := from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := from.cross(east)
	var nearest := INF
	for index in 72:
		var angle := TAU * float(index) / 72.0
		var out := (east * cos(angle) + north * sin(angle)) / shape.radius
		for step in range(5, 400, 5):
			var probe := (from + out * float(step)).normalized()
			if shape.elevation(probe, SPACING) <= 0.0:
				nearest = minf(nearest, float(step))
				break
	return nearest


# --- The waypoint -----------------------------------------------------------

## Whether the landing is named on the HUD, and at what range. Read off the layer
## rather than off a screenshot: whether a marker is up is the whole of that
## behaviour, and the label is twelve pixels of text over a hillside.
func _measure_waypoint() -> void:
	var layer := _player.find_child("Waypoints", true, false) as WaypointLayer
	if layer == null:
		push_error("landing_test: the player has no waypoint layer")
		return
	print("--- waypoint ---")
	print("drawn from %.0f m out, aimed inside %.0f m, gone past %.0f m" % [
		_landing.show_beyond, _landing.aimed_beyond, _landing.hide_beyond])
	var up: Vector3 = _landing.global_basis.y.normalized()
	var across: Vector3 = _landing.global_basis.x.normalized()
	var named := false
	for out: float in [120.0, 700.0, 2000.0, 6000.0]:
		var eye := _landing.global_position + across * out + up * (out * 0.25 + 20.0)
		await _stand(eye, 90)
		# Aimed at it and then well off it, because the two have different
		# cutoffs and a reading taken only one way cannot tell them apart.
		var reading := PackedStringArray()
		for swing: float in [0.0, 45.0]:
			var look := (_landing.global_position - eye).normalized().rotated(
				up, deg_to_rad(swing))
			_camera.global_transform = Transform3D(Basis.looking_at(look, up), eye)
			await get_tree().process_frame
			await get_tree().process_frame
			var drawn := layer.drawn()
			named = named or "Vacationer's Landing" in drawn
			reading.append("%s %s" % ["aimed" if swing == 0.0 else "aside",
				", ".join(drawn) if not drawn.is_empty() else "—"])
		print("  %5.0f m out   %s" % [out, "   ".join(reading)])
	if not named:
		push_error("landing_test: the landing is never named on the HUD")


# --- The field --------------------------------------------------------------

## The field only exists around whoever is looking at it, so this stands the body
## on the shelf first and waits for the tiles to arrive. Everything below is
## therefore a measurement of the plants near the landing and not of the whole
## meadow, which is the only kind of measurement there is now: the rest of it has
## not been grown and will not be until somebody walks over there.
func _measure_field() -> void:
	await _stand(_landing.global_position + _landing.global_basis.y * 2.0, 30)
	var waited := 0
	for _frame in 600:
		await get_tree().process_frame
		waited += 1
		_player.global_position = _landing.global_position + _landing.global_basis.y * 2.0
		_player.velocity = Vector3.ZERO
		if _field.tiles() > 0 and _field.settling() == 0:
			break

	var shape := _planet.shape
	var plants := _field.standing()
	print("--- flower field ---")
	print("tiles            %d live, %.0f m to a side, planted over %.0f m" % [
		_field.tiles(), _field.tile_size, _field.spread])
	print("streamed in      %d frames after arriving" % waited)
	print("plants           %d built, %d drawn from here" % [
		_field.planted(), _field.grown()])
	print("draw distance    %.0f m, thinning from %.0f m to %.0f%% of them" % [
		_flower.draw_within, _flower.thin_from, _flower.far_density * 100.0])
	if plants.is_empty():
		push_error("landing_test: nothing grew; the rules reject the whole shelf")
		return

	var lowest := INF
	var highest := -INF
	var nearest_landing := INF
	var steepest := 0.0
	var shortest := INF
	var tallest := -INF
	var landing: Vector3 = _landing.direction.normalized()
	for stood in plants:
		var up := _planet.to_local(stood.origin).normalized()
		var elevation := shape.elevation(up, SPACING)
		lowest = minf(lowest, elevation)
		highest = maxf(highest, elevation)
		nearest_landing = minf(nearest_landing, up.angle_to(landing) * shape.radius)
		steepest = maxf(steepest, rad_to_deg(acos(clampf(
			shape.normal_at(up, SPACING).dot(up), -1.0, 1.0))))
		var size := stood.basis.get_scale().y * _flower.authored_height()
		shortest = minf(shortest, size)
		tallest = maxf(tallest, size)

	print("elevation        %.1f m to %.1f m (floor is %.1f m)" % [
		lowest, highest, _flower.above_water])
	print("nearest landing  %.1f m (gap is %.1f m)" % [nearest_landing, _field.keep_back])
	print("steepest ground  %.1f deg (limit is %.1f deg)" % [
		steepest, _flower.max_slope])
	print("heights          %.2f m to %.2f m" % [shortest, tallest])
	var bodies := _field.find_children("*", "PhysicsBody3D", true, false).size() \
		+ _field.find_children("*", "Area3D", true, false).size()
	print("collision        %s" % ("none, as asked" if bodies == 0
		else "%d bodies — the flowers are solid" % bodies))
	if bodies > 0:
		push_error("landing_test: the flowers picked up collision")
	if lowest < _flower.above_water:
		push_error("landing_test: a bloom came up below the shore line")
	if nearest_landing < _field.keep_back:
		push_error("landing_test: a bloom came up inside the landing's clearance")
	# The slope is read here at the terrain's own scale and the rule is applied
	# at the plant's, over a couple of metres, so the two do not have to agree
	# closely — a plant on a two-metre-wide level step is standing on ground this
	# reads as steep. A wide tolerance, and it still catches a cliff face.
	if steepest > _flower.max_slope + 12.0:
		push_error("landing_test: a bloom came up on ground far steeper than the limit")


# --- The sway ---------------------------------------------------------------

## Photographed, because there is nothing else left to read. The bend happens in
## the vertex shader out of the walker positions and the clock; no value on this
## side of the bus moves when a flower leans, so the picture is the measurement.
##
## Two experiments from one fixed camera, and the second one turns the wind off.
##
## That is not tidiness, it is the only way to get an answer. Both effects move
## the same pixels, and in a field this thick the wind moves several times more
## of them than a body pushing the dozen plants within reach of it — so a frame
## with a body in it does not read as different from a frame without one, and a
## comparison between the two says nothing. With the breeze held at zero the only
## thing left that can move a plant is the walker, and what changed is what it
## did.
func _measure_sway() -> void:
	var bloom := _nearest_bloom()
	if bloom == Transform3D.IDENTITY:
		return
	var up := (bloom.origin - _planet.global_position).normalized()
	var across := bloom.basis.x.normalized()
	var focus := bloom.origin + up * 0.5
	# The camera is held off the player for all three: whoever the flowers are
	# leaning away from is normally the person holding the camera, and from
	# there a plant leans directly away and reads as being further off.
	var eye := focus - bloom.basis.z.normalized() * 2.6 + up * 0.6
	var far_off := focus + across * 45.0
	var beside := focus + across * 1.1

	print("--- sway ---")
	print("wind             %.0f deg heading, strength %.2f" % [
		_field.wind_heading, _field.wind_strength])
	print("walkers          %.1f m reach, %.2f s of lag" % [
		_field.push_reach, _field.push_lag])
	var blown := await _photograph("flowers_wind", eye, focus, up, far_off, 150)
	var drifted := await _photograph("", eye, focus, up, far_off, 34)
	var breeze := _changed(blown, drifted)

	RenderingServer.global_shader_parameter_set(&"wind_strength", 0.0)
	var rested := await _photograph("flowers_rest", eye, focus, up, far_off, 120)
	var held := await _photograph("", eye, focus, up, far_off, 34)
	var leaning := await _photograph("flowers_leaning", eye, focus, up, beside, 150)
	RenderingServer.global_shader_parameter_set(&"wind_strength", _field.wind_strength)
	var still := _changed(rested, held)
	var pushed := _changed(rested, leaning)

	print("half a second of wind moved  %.1f%% of the picture" % (breeze * 100.0))
	print("with it off, the sky alone   %.1f%% of it" % (still * 100.0))
	print("a body standing in them      %.1f%% of it" % (pushed * 100.0))
	if breeze < 0.002:
		push_error("landing_test: the field is not moving in the wind")
	# The still pair is not a zero. Holding the plants does not hold the world:
	# the clouds are drifting, their shadows are crossing the ground and the sea
	# is running, and all of that is in the frame. So it is the floor the walker
	# figure is measured against rather than something to assert away.
	if pushed < maxf(still * 3.0, 0.01):
		push_error("landing_test: standing in the flowers did no more than the weather")

	# What the field costs, as the difference between drawing it and not. A
	# figure with the flowers in it is the terrain's number as much as theirs;
	# the same scene twice is the only reading that is about them.
	var standing := await _frame_cost(eye, focus, up, beside)
	var drawn := _field.grown()
	_field.visible = false
	var without := await _frame_cost(eye, focus, up, beside)
	_field.visible = true
	print("%d plants drawn cost %.2f ms a frame (%.2f with, %.2f without)" % [
		drawn, standing - without, standing, without])


## Holds the body at [param stood], the camera on [param focus], waits, and
## returns the frame. The wait is what makes a pair comparable: the walker point
## chases the player, so a shot taken as it arrives is a shot of the lean part
## way in. An empty name is a frame taken only to be compared against.
func _photograph(shot_name: String, eye: Vector3, focus: Vector3, up: Vector3,
		stood: Vector3, frames: int) -> Image:
	for _frame in frames:
		await get_tree().process_frame
		_player.global_position = stood
		_player.velocity = Vector3.ZERO
		_camera.global_transform = Transform3D(Basis.looking_at(focus - eye, up), eye)
	var shot := get_viewport().get_texture().get_image()
	if shot_name != "":
		shot.save_png(ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png"))
	return shot


## Share of the picture that differs between two frames. Sampled on a grid
## rather than every pixel, and against a threshold well above the dither in a
## tone-mapped frame, so what it counts is geometry that moved.
func _changed(before: Image, after: Image) -> float:
	var counted := 0
	var moved := 0
	for x in range(0, before.get_width(), 3):
		for y in range(0, before.get_height(), 3):
			counted += 1
			var was := before.get_pixel(x, y)
			var now := after.get_pixel(x, y)
			if maxf(maxf(absf(was.r - now.r), absf(was.g - now.g)),
					absf(was.b - now.b)) > 0.04:
				moved += 1
	return float(moved) / maxf(float(counted), 1.0)


func _frame_cost(eye: Vector3, focus: Vector3, up: Vector3, stood: Vector3) -> float:
	# The settings autoload holds the game to 120, which is slower than either
	# reading here and would report the field as free.
	Engine.max_fps = 0
	for _frame in 30:
		await get_tree().process_frame
	var began := Time.get_ticks_usec()
	for _frame in 120:
		await get_tree().process_frame
		_player.global_position = stood
		_player.velocity = Vector3.ZERO
		_camera.global_transform = Transform3D(Basis.looking_at(focus - eye, up), eye)
	return float(Time.get_ticks_usec() - began) / 1000.0 / 120.0


# --- Scaffolding ------------------------------------------------------------

## The plant nearest the landing, which is the one every close view is framed on.
func _nearest_bloom() -> Transform3D:
	var at := _landing.global_position
	var nearest := Transform3D.IDENTITY
	var closest := INF
	for stood in _field.standing():
		var away := stood.origin.distance_to(at)
		if away < closest:
			closest = away
			nearest = stood
	if closest == INF:
		push_error("landing_test: no plant to frame on")
	return nearest


## Holds the body at a point for a while. Held rather than placed: it is still
## being simulated, and gravity would have it somewhere else by the next frame.
func _stand(at: Vector3, frames: int) -> void:
	_player.start_flying()
	for _frame in frames:
		await get_tree().process_frame
		_player.global_position = at
		_player.velocity = Vector3.ZERO


func _shot(shot_name: String, out: float, altitude: float, subject: String) -> void:
	var at: Vector3 = _landing.global_position + _landing.global_basis.y * 2.0
	if subject == "bloom":
		var bloom := _nearest_bloom()
		if bloom == Transform3D.IDENTITY:
			return
		at = bloom.origin + bloom.basis.y.normalized() * 0.5
	var up := (at - _planet.global_position).normalized()
	# Back along the landing's own -Z, which the anchor turned at the water: stand
	# inland of the subject and the sea is behind it in every frame. Standing
	# the other side is standing in the sea looking at the shore.
	var across := _landing.global_basis.z
	across = (across - up * across.dot(up)).normalized()
	var eye := at + across * out + up * altitude
	await _stand(eye, 110)
	_camera.global_transform = Transform3D(Basis.looking_at(at - eye, up), eye)
	for _frame in 40:
		await get_tree().process_frame
		_player.global_position = eye
		_player.velocity = Vector3.ZERO
		_camera.global_transform = Transform3D(Basis.looking_at(at - eye, up), eye)
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png"))
	print("%-16s %5.0f m out, %4.0f m up" % [shot_name, out, altitude])
