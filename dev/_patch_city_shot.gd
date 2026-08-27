extends Node

## Generates one live patch city and photographs day, night, and apron slopes.
##
##     godot --path . dev/_patch_city_shot.tscn
##     godot --path . dev/_patch_city_shot.tscn -- --patch=12
##
## Not headless: the dummy renderer never draws a frame. Default patch is the
## largest territory, the same one the bake script paints first. Night and day
## are forced at that city, not at Vacationer's Landing, so the hulls, windows,
## and terrain share one exposure.

const WORLD := preload("res://game/world.tscn")
const SHOT_DIR := "res://dev/captures/"
var MOUNTAINS := PackedVector3Array([
	Vector3(-0.270521, -0.3052884, -0.9130266),
	Vector3(0.6848267, 0.0168872, 0.7285103),
	Vector3(0.2574172, -0.2996968, -0.9186503),
	Vector3(0.4474815, -0.0008659, -0.8942928),
])
const SETTLE_FRAMES := 140
const DAY := true
const NIGHT := false

var _only_patch := -1
var _world: GameWorld
var _planet: Planet
var _player: OnlinePlayer
var _cycle: CelestialCycle
var _camera: Camera3D
var _city: PatchCity
var _failures := 0


func _ready() -> void:
	_parse_args()
	if DisplayServer.get_name() == "headless":
		push_error("patch_city_shot: needs a windowed renderer")
		get_tree().quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	_world = WORLD.instantiate() as GameWorld
	add_child(_world)
	await _wait(12)

	_planet = _world.find_child("Planet", true, false) as Planet
	_cycle = _world.find_child("CelestialCycle", true, false) as CelestialCycle
	_player = get_tree().get_first_node_in_group("network_players") as OnlinePlayer
	if _planet == null or _planet.shape == null:
		_fail("planet missing")
		_quit()
		return
	if _player != null:
		if _player.hud != null:
			_player.hud.visible = false
		_player.visible = false
	if _cycle != null:
		_cycle.period_seconds = 0.0
	_camera = Camera3D.new()
	_camera.name = "ShotCamera"
	_camera.fov = 62.0
	_camera.near = 0.4
	_camera.far = 16000.0
	_planet.add_child(_camera)
	_camera.make_current()
	_planet.viewer = _camera
	_planet.splits_per_frame = 64
	_planet.applies_per_frame = 32
	_planet.pending_limit = 8
	_planet.lod_updates_per_second = 120
	var overlay := _planet.get_node_or_null("LandPatches") as LandPatchOverlay
	if overlay != null:
		overlay.set_overlay_enabled(false)

	if not _generate_city():
		_quit()
		return
	_park_player()
	await _shoot_all()
	_quit()


func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--patch="):
			_only_patch = int(argument.trim_prefix("--patch="))


func _generate_city() -> bool:
	var shape := _planet.shape
	shape.prepare()
	var partition := _partition_for(shape)
	if partition.patches.is_empty():
		_fail("partition produced no patches")
		return false
	var patch_id := _pick_patch(partition)
	if patch_id < 0:
		_fail("no patch to generate")
		return false
	var started := Time.get_ticks_msec()
	var generator := PatchCityGenerator.new()
	var plan := generator.generate(shape, partition, patch_id)
	if plan.districts.is_empty():
		_fail("%s has no districts" % partition.patches[patch_id].name)
		return false
	_city = PatchCity.new()
	_city.apply(plan, shape)
	_planet.add_child(_city)
	while _city.phase < PatchCity.PHASE_PAINTED:
		if not _city.advance(shape):
			_fail("%s failed to advance from phase %d"
				% [plan.patch_name, _city.phase])
			return false
		print("patch_city_shot: phase %d  %s"
			% [_city.phase, plan.patch_name])
	print("patch_city_shot: painted %s  %d districts  %d buildings  %.1f s"
		% [
			plan.patch_name,
			plan.districts.size(),
			_city.fabric.get("lots", []).size(),
			(Time.get_ticks_msec() - started) / 1000.0,
		])
	return true


func _partition_for(shape: PlanetShape) -> LandPartition:
	var overlay := _planet.get_node_or_null("LandPatches") as LandPatchOverlay
	if overlay != null and overlay.partition.patches.size() > 0:
		return overlay.partition
	var partition := LandPartition.new()
	partition.bake(shape, MOUNTAINS, 1000.0, 1300.0)
	return partition


func _pick_patch(partition: LandPartition) -> int:
	if _only_patch >= 0:
		if _only_patch < partition.patches.size():
			return _only_patch
		_fail("patch %d is out of range (%d patches)"
			% [_only_patch, partition.patches.size()])
		return -1
	var best := -1
	var best_area := -1.0
	for patch in partition.patches:
		if patch.area > best_area:
			best_area = patch.area
			best = patch.id
	return best


func _park_player() -> void:
	if _player == null or _city == null:
		return
	var up := _city_up()
	var away := _planet.standing_position((-up).normalized(), 2.0)
	_player.global_position = away
	_player.velocity = Vector3.ZERO


func _shoot_all() -> void:
	var tower := _tower_target()
	var slope := _slope_target()
	if tower.is_empty():
		_fail("no skyscraper lot to photograph")
	if slope.is_empty():
		_fail("no apron slope to photograph")

	_set_city_day(DAY)
	if not tower.is_empty():
		_frame_tower(tower, 70.0, 0.22)
		await _shot("patch_city_day_close")
		_frame_tower(tower, 220.0, 0.18)
		await _shot("patch_city_day_gameplay")
	if not slope.is_empty():
		_frame_slope_out(slope, 28.0, 9.0)
		await _shot("patch_city_slope_out_close")
		_frame_slope_out(slope, 95.0, 18.0)
		await _shot("patch_city_slope_out_gameplay")
		_frame_slope_in(slope, 18.0, 7.0)
		await _shot("patch_city_slope_in_close")
		_frame_slope_in(slope, 48.0, 11.0)
		await _shot("patch_city_slope_in_gameplay")

	_set_city_day(NIGHT)
	if not tower.is_empty():
		_frame_tower(tower, 70.0, 0.22)
		await _shot("patch_city_night_close")
		_frame_tower(tower, 220.0, 0.18)
		await _shot("patch_city_night_gameplay")
		_frame_tower(tower, 38.0, 0.16)
		await _shot("patch_city_night_windows")


func _tower_target() -> Dictionary:
	var best: Dictionary = {}
	var best_h := -1.0
	var acc := Vector2.ZERO
	var acc_n := 0
	for lot in _city.fabric.get("lots", []):
		var row: Dictionary = lot
		if int(row.get("typology", 0)) < PatchCity.TYPE_TOWER:
			continue
		var height := float(row.get("stories", 0.0))
		var centre: Vector2 = row.get("centre", Vector2.ZERO)
		acc += centre
		acc_n += 1
		if height > best_h:
			best_h = height
			best = row
	if best.is_empty():
		return {}
	var centre: Vector2 = best.get("centre", Vector2.ZERO)
	if acc_n >= 3:
		centre = centre.lerp(acc / float(acc_n), 0.35)
	var up := _city._from_uv(centre).normalized()
	var stories := maxf(best_h, 8.0)
	var foot := _city.to_global(
		_city._deck_mark(_planet.shape, up, PatchCity.STREET_LIFT))
	var along: Vector2 = best.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	var east := _city._from_uv(centre + along.normalized()).normalized() - up
	if east.length_squared() < 0.0001:
		east = _side(up)
	east = east.normalized()
	return {
		"foot": foot,
		"up": up,
		"east": east,
		"north": up.cross(east).normalized(),
		"height": stories * 3.15,
		"stories": stories,
	}


func _slope_target() -> Dictionary:
	var cell := _city._pad_cell
	if cell < 0.1 or _city._pad_tops.is_empty():
		return {}
	var city_uv := Vector2.ZERO
	var city_n := 0
	for lot in _city.fabric.get("lots", []):
		var row: Dictionary = lot
		city_uv += row.get("centre", Vector2.ZERO) as Vector2
		city_n += 1
	if city_n > 0:
		city_uv /= float(city_n)
	var best_uv := Vector2.ZERO
	var best_out := Vector2.ZERO
	var best_pad := 0.0
	var best_score := -1.0
	for key in _city._pad_tops:
		var at: Vector2i = key
		var missing := 0
		var out := Vector2.ZERO
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not _city._pad_tops.has(at + dir):
				missing += 1
				out += Vector2(float(dir.x), float(dir.y))
		if missing == 0:
			continue
		var uv := Vector2(float(at.x) * cell, float(at.y) * cell)
		if out.length_squared() < 0.0001:
			out = uv - city_uv
		out = out.normalized()
		var pad := float(_city._pad_tops[at])
		var score := uv.distance_to(city_uv) + pad * 4.0 + float(missing)
		if score > best_score:
			best_score = score
			best_uv = uv
			best_out = out
			best_pad = pad
	if best_score < 0.0:
		return {}
	var rim_up := _city._from_uv(best_uv).normalized()
	var rim := _city.to_global(
		_city._deck_mark(_planet.shape, rim_up, PatchCity.STREET_LIFT))
	var mid_uv := best_uv + best_out * 14.0
	var mid_up := _city._from_uv(mid_uv).normalized()
	var mid := _planet.standing_position(mid_up, 0.6)
	var outward := _flat(mid - rim, rim_up)
	var mid_h := rim.lerp(mid, 0.55)
	return {
		"rim": rim,
		"mid": mid_h,
		"up": rim_up,
		"out": outward,
		"pad": best_pad,
	}


func _frame_tower(target: Dictionary, away: float, height_t: float) -> void:
	var foot: Vector3 = target["foot"]
	var up: Vector3 = target["up"]
	var east: Vector3 = target["east"]
	var north: Vector3 = target["north"]
	var height: float = target["height"]
	var look := foot + up * clampf(height * height_t, 8.0, height * 0.45)
	var eye := foot + east * away * 0.82 + north * away * 0.42 \
		+ up * (10.0 + height * 0.12)
	_aim(eye, look, up)


func _frame_slope_out(target: Dictionary, away: float, lift: float) -> void:
	var mid: Vector3 = target["mid"]
	var up: Vector3 = target["up"]
	var outward: Vector3 = target["out"]
	var along := up.cross(outward)
	if along.length_squared() < 0.0001:
		along = _side(up)
	along = along.normalized()
	var probe := mid + outward * away
	var dir := (probe - _planet.global_position).normalized()
	# Walk off the pad so the eye sits on terrain, not under the slab.
	for _step in 8:
		if is_nan(_city._pad_top_at(dir)):
			break
		dir = (dir + outward * 0.012).normalized()
	var stand := _planet.standing_position(dir, 2.4)
	var eye := stand + up * lift + along * away * 0.08
	_aim(eye, mid + up * 2.0, up)


func _frame_slope_in(target: Dictionary, away: float, lift: float) -> void:
	var rim: Vector3 = target["rim"]
	var mid: Vector3 = target["mid"]
	var up: Vector3 = target["up"]
	var outward: Vector3 = target["out"]
	var along := up.cross(outward)
	if along.length_squared() < 0.0001:
		along = _side(up)
	along = along.normalized()
	# On the pavement, looking out and down the ramp — the winding that used
	# to cull away when the camera was on the pad side.
	var eye := rim - outward * minf(away, 10.0) + up * lift + along * 2.0
	_aim(eye, rim + outward * 22.0 - up * 2.5, up)


func _set_city_day(is_day: bool) -> void:
	var up := _city_up()
	if _cycle == null or _planet.sun == null:
		return
	var pole := (_planet.global_basis * _planet.shape.frost_axis).normalized()
	var noon := _planet.sun.global_basis.z.normalized()
	var landing := _planet.get_node_or_null("VacationersLanding") as Landmark
	if landing != null and landing.direction.length_squared() > 0.001:
		noon = (_planet.global_basis * landing.direction.normalized()).normalized()
	noon -= pole * noon.dot(pole)
	if noon.length_squared() < 0.0001:
		noon = pole.cross(Vector3.FORWARD if absf(pole.z) < 0.9 else Vector3.RIGHT)
	noon = noon.normalized()
	var target := up - pole * up.dot(pole)
	if target.length_squared() < 0.0001:
		target = noon
	if not is_day:
		target = -target
	target = target.normalized()
	var orbit := _cycle.orbit_direction
	if absf(orbit) < 0.001:
		orbit = 1.0
	var phase := fposmod(noon.signed_angle_to(target, pole) / TAU / orbit, 1.0)
	_cycle.set_phase(phase)
	var env := _cycle.world_environment
	if env != null and env.environment != null:
		env.environment.ambient_light_energy = (
			_cycle.day_ambient_energy if is_day else _cycle.night_ambient_energy)
	var night := _city._night_at(_city.global_transform * (up * _city._radius)) \
		if _city.is_inside_tree() else (0.0 if is_day else 1.0)
	print("patch_city_shot: %s  phase=%.3f  city_night=%.2f"
		% ["day" if is_day else "night", phase, night])


func _city_up() -> Vector3:
	if _city._up.length_squared() > 0.001:
		return _city._up.normalized()
	return _planet.up_at(_city.global_position)


func _aim(eye: Vector3, at: Vector3, up: Vector3) -> void:
	_camera.global_position = eye
	_camera.look_at(at, up)
	_camera.make_current()
	_planet.viewer = _camera


func _flat(direction: Vector3, up: Vector3) -> Vector3:
	var flat := direction - up * direction.dot(up)
	if flat.length_squared() < 0.000001:
		return _side(up)
	return flat.normalized()


func _side(up: Vector3) -> Vector3:
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
	if side.length_squared() < 0.000001:
		side = up.cross(Vector3.FORWARD)
	return side.normalized()


func _wait(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	_camera.make_current()
	await _wait(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(SHOT_DIR + shot_name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := image.save_png(path)
	print("patch_city_shot: %s %s"
		% [shot_name, "saved" if error == OK else error_string(error)])


func _fail(message: String) -> void:
	_failures += 1
	push_error("patch_city_shot: FAIL  %s" % message)


func _quit() -> void:
	print("patch_city_shot: %s" % (
		"ok" if _failures == 0 else "%d failure(s)" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)
