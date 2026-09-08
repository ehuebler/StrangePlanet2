extends Node

const BakedFloraLib := preload("res://game/props/baked_flora.gd")

## Headless checks for the travel corridor terrain and flora stream along.
##
##     godot --headless --path . dev/_stream_lead_test.tscn

var _failures := 0


func _ready() -> void:
	_check_terrain_corridor()
	_check_flora_path()
	print("stream_lead_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_terrain_corridor() -> void:
	var planet := Planet.new()
	planet.lead_time = 1.0
	planet.lead_width = 48.0
	planet.lead_distance = 1000.0
	planet._last_eye = Vector3(0.0, 8000.0, 0.0)
	planet._track_lead(Vector3(0.0, 8000.0, 200.0), 1.0)
	_expect(planet.viewer_lead_length() > 190.0,
		"a 200 m/s step opens a one-second terrain lead")
	_expect(planet.viewer_lead_direction().dot(Vector3(0.0, 0.0, 1.0)) > 0.9,
		"terrain lead points along the measured travel")

	var eye := Vector3(0.0, 8000.0, 200.0)
	var ahead := _chunk_at(Vector3(0.0, 8000.0, 300.0), 25.0)
	var beside := _chunk_at(Vector3(70.0, 8000.0, 200.0), 25.0)
	var behind := _chunk_at(Vector3(0.0, 8000.0, 0.0), 25.0)
	_expect(planet._path_distance(ahead, eye) < 1.0,
		"ground on the track is treated as already arrived")
	_expect(planet._path_distance(beside, eye) < 20.0,
		"the 48 m corridor covers a weave beside the track")
	_expect(planet._path_distance(behind, eye) > 100.0,
		"ground already passed is not treated as on the path")

	planet.lead_time = 0.0
	planet._last_eye = Vector3(0.0, 8000.0, 0.0)
	planet._track_lead(Vector3(0.0, 8000.0, 200.0), 1.0)
	_expect(is_zero_approx(planet.viewer_lead_length()),
		"zero lead_time restores a point, not a corridor")
	planet.free()


func _check_flora_path() -> void:
	var tree := PlantSpecies.new()
	tree.height = 8.5
	tree.per_square_metre = 0.0014
	tree.draw_within = 260.0
	var grass := PlantSpecies.new()
	grass.height = 0.33
	grass.per_square_metre = 20.0
	grass.draw_within = 66.0
	_expect(tree.is_skyline() and not grass.is_skyline(),
		"trees are skyline cover and grass is fill")
	_expect(not GroundCover.stream_fill,
		"short cover is baked onto terrain chunks, not streamed")
	_expect(BakedFloraLib.should_bake(9, 9) and not BakedFloraLib.should_bake(8, 9)
			and not BakedFloraLib.should_bake(7, 9),
		"baked grass rides only the finest map tiles")

	var planet := Planet.new()
	planet.max_depth = 9
	planet._lead_direction = Vector3(0.0, 0.0, 1.0)
	planet._lead_length = 200.0
	var eye := Vector3(0.0, 8000.0, 200.0)
	var near := _chunk_at(Vector3(0.0, 8000.0, 220.0), 25.0)
	near.depth = 9
	var ahead := _chunk_at(Vector3(0.0, 8000.0, 500.0), 25.0)
	ahead.depth = 9
	var coarse := _chunk_at(Vector3(0.0, 8000.0, 220.0), 80.0)
	coarse.depth = 7
	_expect(planet._wants_baked_flora(near, eye),
		"lawn bakes on the path just ahead of the viewer")
	_expect(not planet._wants_baked_flora(ahead, eye),
		"the terrain lead does not bake grass 300 m out")
	_expect(not planet._wants_baked_flora(coarse, eye),
		"coarse tiles never bake grass")
	planet.free()

	var cover := GroundCover.new()
	cover.lead_time = 1.0
	cover.lead_distance = 280.0
	cover._lead_direction = Vector3(0.0, 0.0, 1.0)
	cover._lead_length = 200.0
	eye = Vector3.ZERO
	_expect(cover._path_away(Vector3(0.0, 0.0, 150.0), eye) < 1.0,
		"a flora tile on the track sows at arrival density")
	_expect(is_equal_approx(cover._path_away(Vector3(80.0, 0.0, 75.0), eye), 80.0),
		"a flora tile off the track keeps its true side gap")
	cover._lead_length = 0.0
	_expect(is_equal_approx(cover._path_away(Vector3(0.0, 0.0, 150.0), eye), 150.0),
		"standing still flora measures to the eye")
	_expect(cover._ahead_pending() == cover.pending_limit,
		"standing still keeps the authored flora pool")

	var trees: Array[PlantSpecies] = []
	trees.append(tree)
	cover.species = trees
	cover._tile = 34.0
	cover._reach = 260.0
	cover._classify_species()
	cover._lead_length = 200.0
	cover._look_dir = Vector3(0.0, 0.0, 1.0)
	_expect(cover._has_skyline and not cover._fill_only(),
		"a tree field is skyline streaming")
	_expect(cover._ahead_pending() > cover.pending_limit,
		"a run opens extra flora workers so trees fill the corridor")
	_expect(cover._cell_wanted(Vector3(0.0, 0.0, 150.0), eye),
		"trees stay wanted on the travel corridor")
	_expect(not cover._cell_held(Vector3(0.0, 0.0, -80.0), eye),
		"a run drops tiles already passed instead of keeping a back ring")
	cover._reach = 180.0
	_expect(cover._survey_anchors(eye).size() == 2,
		"a run surveys the eye and the lead tip, not a third midpoint ring")
	cover._reach = 260.0
	_expect(GroundCover.TILE_BUDGET <= 64,
		"skyline tiles coarsen so a 260 m field is a few squares, not a fine grid")

	var meadow := GroundCover.new()
	var grasses: Array[PlantSpecies] = []
	grasses.append(grass)
	meadow.species = grasses
	meadow._tile = 26.0
	meadow._reach = 66.0
	meadow._classify_species()
	meadow._lead_direction = Vector3(0.0, 0.0, 1.0)
	meadow._lead_length = 200.0
	meadow._look_dir = Vector3(0.0, 0.0, 1.0)
	_expect(meadow._fill_only() and meadow._rushing(),
		"a grass field is fill and a 200 m lead is a rush")
	_expect(meadow._ahead_pending() == meadow.pending_limit,
		"grass does not take extra workers while rushing")
	_expect(meadow._cell_wanted(Vector3(0.0, 0.0, 20.0), eye),
		"grass still streams underfoot while rushing")
	_expect(not meadow._cell_wanted(Vector3(0.0, 0.0, 150.0), eye),
		"grass does not claim the far corridor while rushing")

	var mixed := GroundCover.new()
	var both: Array[PlantSpecies] = []
	both.append(tree)
	both.append(grass)
	mixed.species = both
	mixed._tile = 34.0
	mixed._reach = 260.0
	mixed._classify_species()
	mixed._lead_length = 200.0
	var far_plan := mixed._detail_plan(150.0)
	var near_plan := mixed._detail_plan(20.0)
	_expect(far_plan.size() == 2 and far_plan[0] > 0.0 and is_zero_approx(far_plan[1]),
		"a rushed mixed tile sows trees and skips baked grass")
	_expect(near_plan.size() == 2 and near_plan[0] > 0.0 and is_zero_approx(near_plan[1]),
		"streamed tiles do not grow fill species while grass is baked")

	cover.free()
	meadow.free()
	mixed.free()


func _chunk_at(origin: Vector3, arc: float) -> Planet.Chunk:
	var chunk := Planet.Chunk.new()
	chunk.origin = origin
	chunk.arc = arc
	return chunk


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("stream_lead_test: ok  %s" % label)
		return
	_failures += 1
	push_error("stream_lead_test: %s" % label)
