extends Node

## Where the frame goes around the fauna at Vacationer's Landing.
##
##     & $godot --path . dev/_fauna_perf_test.tscn
##
## This is a hitch hunt rather than an average. Fauna streams on an interval and
## creatures only move when they are awake, so the number that matters is the
## worst frame while the player is covering ground, not the mean while standing
## still. A mean frame time hides exactly the stutter this exists to catch.
##
## The player is moved in steps rather than driven, because reaching new terrain
## is what provokes fauna and a teleport reaches it sooner than a walk does. Every
## pass is repeated with fauna switched off, which is the only measurement that
## says whether fauna is the cause of a hitch or merely present during one.

const WORLD := preload("res://game/world.tscn")
const SETTLE_FRAMES := 240
## Long enough to contain several survey ticks at the authored interval.
const SAMPLE_FRAMES := 300
## Roughly half a cell, so most steps reach cells with no cached records.
const STEP_METRES := 45.0
const FRAMES_PER_STEP := 20

var _world: GameWorld
var _planet: Planet
var _player: OnlinePlayer
var _spawner: FaunaSpawner
var _colony: Node3D


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	_world = WORLD.instantiate() as GameWorld
	add_child(_world)
	await _wait(10)

	_planet = _world.find_child("Planet", true, false) as Planet
	_spawner = _world.find_child(
		"FaunaPopulations", true, false) as FaunaSpawner
	_colony = _world.find_child("VacationersLanding", true, false) as Node3D
	_player = get_tree().get_first_node_in_group(
		"network_players") as OnlinePlayer
	if _planet == null or _spawner == null or _colony == null \
			or _player == null:
		push_error("fauna_perf: nothing to measure")
		get_tree().quit(1)
		return

	_stand_at(_colony.global_position)
	await _wait(SETTLE_FRAMES)
	print("fauna_perf: %d fauna actors live at Vacationer's Landing"
		% _spawner.actor_count())

	_price_cold_survey()
	_price_one_spawn()
	var with_fauna := await _price_frames("fauna on")
	_report_simulation_detail()
	_disable_fauna()
	await _wait(60)
	var without_fauna := await _price_frames("fauna off")
	print("fauna_perf: fauna costs %.2f ms on its worst frame and %.2f ms on its median"
		% [
			float(with_fauna["worst"]) - float(without_fauna["worst"]),
			float(with_fauna["median"]) - float(without_fauna["median"]),
		])
	get_tree().quit()


## What one survey costs with nothing cached, which is the state every survey is
## in while the player is walking into new ground.
func _price_cold_survey() -> void:
	var warm := _survey_ms()
	var cold := 0.0
	var checks := 0
	for step in 6:
		_stand_at(_step_position(step + 1))
		_spawner.set(&"_cell_cache", {})
		cold = maxf(cold, _survey_ms())
		checks = maxi(checks, _spawner.last_survey_placement_checks())
	print("fauna_perf: survey  warm %.2f ms  cold %.2f ms  %d terrain samples"
		% [warm, cold, checks])
	_stand_at(_colony.global_position)


func _survey_ms() -> float:
	var began := Time.get_ticks_usec()
	_spawner.call(&"_survey_global")
	return float(Time.get_ticks_usec() - began) / 1000.0


## What arriving costs, separately from deciding to arrive. A creature that
## deep-copied its material here would compile a private shader the first frame it
## was drawn, which costs hundreds of milliseconds and shows up as a stall long
## after this returns.
func _price_one_spawn() -> void:
	var sample := _spawner.fauna_snapshot()
	if sample.is_empty():
		print("fauna_perf: no actor to price a spawn against")
		return
	var record := ((sample[0] as Dictionary)["spawn"] as Dictionary).duplicate()
	record["id"] = "perf_probe"
	var began := Time.get_ticks_usec()
	_spawner.call(&"_spawn_local", record)
	var spent := float(Time.get_ticks_usec() - began) / 1000.0
	_spawner.call(&"_despawn_local", "perf_probe")
	print("fauna_perf: one creature arriving is %.2f ms of CPU" % spent)


## How the population is split between the two ways a creature can move. Only the
## handful within reach of a player should be sweeping capsules against terrain.
func _report_simulation_detail() -> void:
	var physical := 0
	var gliding := 0
	for id in _spawner.actor_ids():
		var mob := _spawner.get_node_or_null(String(id)) as FaunaMob
		if mob == null:
			continue
		if mob.is_physics_body():
			physical += 1
		else:
			gliding += 1
	print("fauna_perf: %d creatures are physics bodies, %d walk the height field"
		% [physical, gliding])


func _price_frames(what: String) -> Dictionary:
	var samples: Array[float] = []
	var step := 0
	for frame in SAMPLE_FRAMES:
		if frame % FRAMES_PER_STEP == 0:
			step += 1
			_stand_at(_step_position(step))
		var began := Time.get_ticks_usec()
		await get_tree().process_frame
		samples.append(float(Time.get_ticks_usec() - began) / 1000.0)

	var ranked := samples.duplicate()
	ranked.sort()
	var median: float = ranked[ranked.size() / 2]
	var bar := median * 2.0 + 1.0
	var hitches := 0
	for sample in samples:
		if sample > bar:
			hitches += 1
	print("fauna_perf: %-9s median %.2f ms  99th %.2f ms  worst %.2f ms  %d hitches of %d frames"
		% [what, median, ranked[int(ranked.size() * 0.99)],
			ranked[ranked.size() - 1], hitches, samples.size()])
	_stand_at(_colony.global_position)
	return {"worst": ranked[ranked.size() - 1], "median": median}


## Everything fauna does per frame, without unloading the world: the creatures go,
## the streamer stops, and whatever is left over is the rest of the game.
func _disable_fauna() -> void:
	for id in _spawner.actor_ids():
		_spawner.call(&"_despawn_local", id)
	_spawner.set_process(false)


## A place STEP_METRES * step along one tangent from the ship, on the ground.
func _step_position(step: int) -> Vector3:
	var here := _planet.to_local(_colony.global_position).normalized()
	var east := here.cross(Vector3.UP if absf(here.y) < 0.9 else Vector3.RIGHT)
	east = east.normalized()
	var out := (here + east * (STEP_METRES * float(step)
		/ _planet.shape.radius)).normalized()
	return _planet.to_global(
		out * (_planet.shape.radius + _planet.shape.elevation(
			out, _planet.finest_spacing())))


func _stand_at(at: Vector3) -> void:
	_player.global_position = at + _planet.up_at(at) * 1.2
	_player.velocity = Vector3.ZERO


func _wait(frames: int) -> void:
	for _frame in frames:
		await get_tree().process_frame
