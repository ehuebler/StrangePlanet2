extends Node

## Planet-wide flora must stream around the viewer, not Vacationer's Landing.
##
##     godot --headless --path . dev/_flora_focus_test.tscn

const LANDING := Vector3(-0.2881049, -0.1121179, 0.9510127)

var _failures := 0


func _ready() -> void:
	_check_global_cover_sits_at_origin()
	_check_planet_aims_at_spawn_not_landing()
	print("flora_focus_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_global_cover_sits_at_origin() -> void:
	var cover := GroundCover.new()
	cover.name = "GlobalCover"
	cover.global_cover = true
	cover.direction = LANDING
	add_child(cover)
	_expect(cover.transform.origin.length() < 0.01
			and cover.global_cover,
		"planet-wide flora is not planted on the old teleporter")
	var local := GroundCover.new()
	local.name = "LandingMeadow"
	local.global_cover = false
	local.direction = LANDING
	add_child(local)
	_expect(local.global_cover == false,
		"authored landing meadows stay local to that shelf")
	cover.queue_free()
	local.queue_free()


func _check_planet_aims_at_spawn_not_landing() -> void:
	CrawlerRun.clear()
	var far := 0
	for path in CrawlerRun.list_runs():
		if not CrawlerRun.load_path(path):
			continue
		var facing := CrawlerRun.spawn_direction()
		if facing.length_squared() > 0.25 and facing.angle_to(LANDING) > 0.35:
			far += 1
	_expect(far >= 8, "crawler runs spawn around the planet, not on the old pad")
	_expect(CrawlerRun.pick_random(), "a crawler run can be picked")
	var facing := CrawlerRun.spawn_direction()
	_expect(facing.length_squared() > 0.25, "a random run has a spawn direction")
	var planet := Planet.new()
	planet.shape = PlanetShape.new()
	planet.shape.prepare()
	planet.aim_at_direction(facing)
	var at := planet.viewer_position()
	_expect(at.length_squared() > 1.0
			and at.normalized().dot(facing.normalized()) > 0.98,
		"terrain and flora aim at the run spawn, not the title camera")
	planet.free()
	CrawlerRun.clear()


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("flora_focus_test failed: %s" % label)
