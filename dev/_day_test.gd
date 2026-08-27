extends SceneTree

## Reports whether the celestial cycle actually turns the sun.
##
## Loads the real `game/world.tscn` rather than standing a light up on its own,
## because every candidate cause of a stuck sun — an export that did not
## resolve, a `_ready` that bailed, a node that is not processing, a transform
## written by something else afterwards — lives in the scene's own wiring and
## none of them reproduce in a harness that rebuilds that wiring by hand.
##
##     godot --headless --path . --script dev/_day_test.gd -- --period=20
##
## `--period` overrides the sixteen minutes so a whole day passes inside a test
## run. Without it the scene's own period is used and the reading to check is
## that the angle moves at all.

const SETTLE_FRAMES := 20

var _cycle: Node
var _sun: DirectionalLight3D
var _planet: Node3D
var _anchor: Node3D
var _period := 0.0
var _frames := 0
var _elapsed := 0.0
var _next_report := 0.0
var _reports := 0
var _first_angle := INF
var _plate: CoordinatePlate


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--period="):
			_period = float(argument.trim_prefix("--period="))

	var packed: PackedScene = load("res://game/world.tscn")
	if packed == null:
		print("day_test: could not load world.tscn")
		quit(1)
		return
	var world := packed.instantiate()
	root.add_child(world)
	# `current_scene` is what a few systems look for; without it the world is in
	# the tree but not the scene the game thinks it is running.
	current_scene = world

	_cycle = world.find_child("CelestialCycle", true, false)
	_sun = world.find_child("Sun", true, false) as DirectionalLight3D
	_planet = world.find_child("Planet", true, false) as Node3D
	_anchor = world.find_child("VacationersLanding", true, false) as Node3D

	print("day_test: cycle=%s sun=%s planet=%s anchor=%s" % [
		_cycle, _sun, _planet, _anchor])
	if _cycle == null or _sun == null:
		quit(1)
		return

	# The three things that silently stop the orbit, each printed as it is
	# rather than inferred from the sun not moving.
	print("day_test: script=%s" % _cycle.get_script())
	print("day_test: processing=%s process_mode=%d" % [
		_cycle.is_processing(), _cycle.process_mode])
	print("day_test: exports planet=%s sun=%s environment=%s noon_anchor=%s" % [
		_cycle.get("planet"), _cycle.get("sun"),
		_cycle.get("world_environment"), _cycle.get("noon_anchor")])
	print("day_test: period_seconds=%s update_interval=%s orbit_direction=%s" % [
		_cycle.get("period_seconds"), _cycle.get("update_interval"),
		_cycle.get("orbit_direction")])

	if _period > 0.0:
		_cycle.set("period_seconds", _period)
		if _cycle.has_method("set_phase"):
			_cycle.call("set_phase", 0.0)
		print("day_test: period overridden to %.1f s" % _period)


func _process(delta: float) -> bool:
	_frames += 1
	# The scene needs a few frames to finish _ready and place the anchor before
	# any reading off it means anything.
	if _frames < SETTLE_FRAMES:
		return false
	_elapsed += delta
	if _elapsed < _next_report:
		return false
	_next_report += 1.0

	var to_sun := _sun.global_basis.z
	var angle := rad_to_deg(atan2(to_sun.x, to_sun.z))
	if _first_angle == INF:
		_first_angle = angle
	var phase := float(_cycle.call("phase")) if _cycle.has_method("phase") else -1.0

	# Elevation of the sun over Vacationer's Landing: +1 is noon overhead, 0 is the
	# horizon, -1 is midnight. This is the number the complaint is really about.
	var elevation := 0.0
	if _anchor != null and _planet != null:
		var up := (_planet.global_basis
			* _anchor.global_position.direction_to(_planet.global_position) * -1.0).normalized()
		elevation = up.dot(to_sun.normalized())

	print("day_test: t=%5.1fs phase=%.4f angle=%8.2f deg turned=%7.2f deg landing_sun=%+.3f" % [
		_elapsed, phase, angle, angle - _first_angle, elevation])
	_report_plate()

	_reports += 1
	if _reports >= 16:
		print("day_test: total turn over %.1f s = %.2f deg" % [
			_elapsed, angle - _first_angle])
		quit()
	return false


## The readout the player actually sees, driven directly rather than through a
## spawned body: the plate is what the clock is being added to, so a cycle that
## turns while the line above it says something else is still a failure.
func _report_plate() -> void:
	if _plate == null:
		_plate = CoordinatePlate.new()
		root.add_child(_plate)
	var standing := _planet.global_position \
		+ (_anchor.global_position - _planet.global_position).normalized() \
		* (_planet.global_position.distance_to(_anchor.global_position) + 1.7)
	# Refreshes are rate limited inside the plate, so it is handed a whole
	# second rather than a frame.
	_plate.refresh(standing, _planet as Planet, 1.0)
	var labels := _plate.find_children("", "Label", true, false)
	if labels.size() > 2:
		print("day_test:   plate | %s" % (labels[2] as Label).text)
