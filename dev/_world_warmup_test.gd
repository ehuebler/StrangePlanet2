extends Node

## Collect walks a snapshot and yields; the live tree keeps freeing nodes.
## Casting those freed refs used to crash New Game.
##
##     godot --headless --path . dev/_world_warmup_test.tscn

var _failures := 0
var _world: Node3D


func _ready() -> void:
	await _check_collect_survives_frees()
	await _check_assign_run_is_separate()
	print("world_warmup_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_assign_run_is_separate() -> void:
	var warmup := WorldWarmup.new()
	warmup.name = "AssignWarmup"
	add_child(warmup)
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerRun.clear()
	await warmup.assign_run(self, "crawler", true)
	_expect(warmup.compiled == 0,
		"site and ring assignment does not compile shaders")
	_expect(CrawlerRun.active(),
		"the crawler run is picked before the session opens")
	warmup.queue_free()
	CrawlerRun.clear()
	NetworkManager.session_options.clear()


func _check_collect_survives_frees() -> void:
	_world = Node3D.new()
	_world.name = "WarmupWorld"
	add_child(_world)
	for _i in 200:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		_world.add_child(mesh)
	var warmup := WorldWarmup.new()
	warmup.name = "WorldWarmup"
	add_child(warmup)
	var draws: Array[Dictionary] = await warmup._collect(_world)
	_expect(not draws.is_empty(), "collect still finds meshes while the tree is torn down")
	warmup.queue_free()
	_world.queue_free()
	await get_tree().process_frame


func _process(_delta: float) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var kids := _world.get_children()
	var cut := mini(40, kids.size())
	for index in cut:
		var kid: Node = kids[index]
		if is_instance_valid(kid):
			kid.queue_free()


func _expect(ok: bool, message: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("world_warmup_test: FAIL  %s" % message)
