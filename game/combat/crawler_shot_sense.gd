class_name CrawlerShotSense
extends RefCounted

## One physics ticker for every cheap shot, plus a shared glow board.
##
## A bubble swarm used to pay a Godot physics callback, two EnergyVfx
## spheres, and an OmniLight per orb. Homing then asked the combatant board
## again from every shot. This walks the live set once, paints the swarm as
## a MultiMesh, and keeps a handful of lights near the camera.

const LIGHT_BUDGET := 10
const BATCH_CAP := 360
const POP_CAP := 48
const POP_LIFE := 0.20
const CELL := 8.0

static var _shots: Array[Node] = []
static var _boards: Dictionary = {}
static var _suspended := false
static var _prey_frame := -1
static var _prey: Dictionary = {}


class Board extends Node3D:
	var shots: Array[Node] = []
	var batch: MultiMeshInstance3D
	var pops: MultiMeshInstance3D
	var lights: Array[OmniLight3D] = []
	var sparks: Array[Dictionary] = []

	func _physics_process(delta: float) -> void:
		CrawlerShotSense._tick_board(self, delta)


static func watch(shot: Node) -> void:
	if shot == null or not is_instance_valid(shot):
		return
	if _shots.has(shot):
		return
	_retire_overflow()
	_shots.append(shot)
	if shot.has_method(&"set_physics_process"):
		shot.set_physics_process(false)
	var board := _board_of(shot)
	if board != null and not board.shots.has(shot):
		board.shots.append(shot)


static func drop(shot: Node) -> void:
	if shot == null:
		return
	_shots.erase(shot)
	for board_variant: Variant in _boards.values():
		var board := board_variant as Board
		if board == null:
			continue
		board.shots.erase(shot)


static func suspend() -> void:
	_suspended = true
	for board_variant: Variant in _boards.values():
		var board := board_variant as Board
		if board != null and is_instance_valid(board):
			board.set_physics_process(false)


static func resume() -> void:
	_suspended = false
	for board_variant: Variant in _boards.values():
		var board := board_variant as Board
		if board != null and is_instance_valid(board):
			board.set_physics_process(true)


static func invalidate() -> void:
	_shots.clear()
	_prey.clear()
	_prey_frame = -1
	for board_variant: Variant in _boards.values():
		var board := board_variant as Board
		if board != null and is_instance_valid(board):
			board.queue_free()
	_boards.clear()


static func count() -> int:
	_prune_shots()
	return _shots.size()


static func is_suspended() -> bool:
	return _suspended


static func pop(anywhere: Node, at: Vector3, radius: float,
		tint: Color) -> void:
	if anywhere == null or not at.is_finite():
		return
	var board := _board_of(anywhere)
	if board == null:
		return
	board.sparks.append({
		"at": at,
		"radius": maxf(radius, 0.12),
		"tint": tint,
		"age": 0.0,
	})
	if board.sparks.size() > POP_CAP:
		board.sparks.remove_at(0)


static func prey(anywhere: Node, from: Vector3, reach: float,
		skip: Variant = null, along := Vector3.ZERO, keep := -1.0,
		min_span := 0.0, use_capsule := false) -> Node:
	if anywhere == null or not from.is_finite() or reach <= 0.0:
		return null
	var frame := Engine.get_physics_frames()
	if frame != _prey_frame:
		_prey_frame = frame
		_prey.clear()
	var cell := Vector3i(
		floori(from.x / CELL), floori(from.y / CELL), floori(from.z / CELL))
	var face := 0
	if along.length_squared() > 0.0001:
		var dir := along.normalized()
		face = int(dir.x * 3.0) + int(dir.y * 3.0) * 7 + int(dir.z * 3.0) * 49
	var key := "%d:%d:%d:%d:%d:%d:%d" % [
		cell.x, cell.y, cell.z, int(reach), face,
		int(keep * 10.0), 1 if use_capsule else 0]
	if _prey.has(key):
		return _prey[key]
	var found: Node
	if use_capsule:
		found = CombatantSense.nearest(anywhere, from, reach, skip,
			DamageHit.Faction.ENEMY, along, keep, false, true, false, false,
			min_span)
	else:
		found = CombatantSense.nearest_enemy(
			anywhere, from, reach, skip, along, keep, min_span)
	_prey[key] = found
	return found


static func direct(delta: float, anywhere: Node = null) -> void:
	if anywhere != null:
		var board := _board_of(anywhere)
		if board != null:
			_tick_board(board, delta)
			return
	for board_variant: Variant in _boards.values():
		var board := board_variant as Board
		if board != null and is_instance_valid(board):
			_tick_board(board, delta)


static func _tick_board(board: Board, delta: float) -> void:
	if board == null or not is_instance_valid(board):
		return
	_prune_board(board)
	var host: Node = board
	for shot in board.shots:
		if shot != null and is_instance_valid(shot) and shot.is_inside_tree():
			host = shot
			break
	if host != null:
		CombatantSense.ensure(host)
	var live := board.shots.duplicate()
	for shot in live:
		if shot == null or not is_instance_valid(shot):
			continue
		if shot.has_method(&"shot_tick"):
			shot.call(&"shot_tick", delta)
	_prune_board(board)
	_age_pops(board, delta)
	_paint(board)


static func _board_of(shot: Node) -> Board:
	if shot == null or not is_instance_valid(shot):
		return null
	var host: Node = DamageHit.game_world_of(shot)
	if host == null:
		host = shot.get_parent()
	if host == null:
		host = shot
	var key := host.get_instance_id()
	var found: Variant = _boards.get(key)
	if found is Board and is_instance_valid(found):
		return found
	var board := Board.new()
	board.name = "CrawlerShotBoard"
	_boards[key] = board
	if host.is_inside_tree():
		host.add_child(board)
	elif shot.is_inside_tree():
		shot.get_parent().add_child(board)
	board.set_physics_process(not _suspended)
	if _can_draw():
		_build_draw(board)
	return board


static func _build_draw(board: Board) -> void:
	board.batch = _make_swarm(board, "ShotBatch",
		EnergyVfx.glow_material(
			CrawlerBubble.GLOW_COLOR, Color(0.78, 0.96, 1.0), false,
			3.6, 0.42, 0.24, 1.0))
	board.pops = _make_swarm(board, "ShotPops",
		EnergyVfx.glow_material(
			CrawlerBubble.GLOW_COLOR, Color(0.88, 0.98, 1.0), false,
			4.4, 0.28, 0.20, 1.0))
	for _index in LIGHT_BUDGET:
		var lamp := OmniLight3D.new()
		lamp.light_color = CrawlerBubble.GLOW_COLOR
		lamp.light_energy = 0.0
		lamp.omni_range = 2.4
		lamp.shadow_enabled = false
		lamp.visible = false
		board.add_child(lamp)
		board.lights.append(lamp)


static func _make_swarm(board: Board, node_name: String,
		material: Material) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(node)
	return node


static func _paint(board: Board) -> void:
	if not _can_draw() or board.batch == null:
		return
	var transforms: Array[Transform3D] = []
	var glows: Array[Dictionary] = []
	for shot in board.shots:
		if shot == null or not is_instance_valid(shot):
			continue
		var at := _glow_at(shot)
		if not at.is_finite():
			continue
		var radius := _batch_radius(shot)
		if radius > 0.001:
			var pulse := _batch_pulse(shot)
			transforms.append(Transform3D(
				Basis.from_scale(Vector3.ONE * radius * pulse), at))
		var energy := _glow_energy(shot)
		if energy > 0.001:
			glows.append({
				"at": at,
				"color": _glow_color(shot),
				"energy": energy,
				"range": _glow_range(shot),
			})
	_write_instances(board.batch, transforms)
	_write_instances(board.pops, _pop_transforms(board))
	_place_lights(board, glows)


static func _pop_transforms(board: Board) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for spark: Dictionary in board.sparks:
		var share := clampf(float(spark.get("age", 0.0)) / POP_LIFE, 0.0, 1.0)
		var radius := float(spark.get("radius", 0.4)) * lerpf(0.55, 1.8, share)
		var at: Vector3 = spark.get("at", Vector3.ZERO)
		if at.is_finite():
			out.append(Transform3D(Basis.from_scale(Vector3.ONE * radius), at))
	return out


static func _write_instances(node: MultiMeshInstance3D,
		transforms: Array[Transform3D]) -> void:
	if node == null or node.multimesh == null:
		return
	var multi := node.multimesh
	var count := transforms.size()
	if multi.instance_count < count:
		multi.instance_count = maxi(count, 1)
	multi.visible_instance_count = count
	for index in count:
		multi.set_instance_transform(index, transforms[index])


static func _place_lights(board: Board, glows: Array[Dictionary]) -> void:
	if board.lights.is_empty():
		return
	var camera_at := _camera_at(board)
	glows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_at: Vector3 = a.get("at", camera_at)
		var b_at: Vector3 = b.get("at", camera_at)
		return camera_at.distance_squared_to(a_at) \
			< camera_at.distance_squared_to(b_at)
	)
	for index in board.lights.size():
		var lamp := board.lights[index]
		if index >= glows.size():
			lamp.visible = false
			lamp.light_energy = 0.0
			continue
		var glow: Dictionary = glows[index]
		lamp.global_position = glow.get("at", lamp.global_position)
		lamp.light_color = glow.get("color", CrawlerBubble.GLOW_COLOR)
		lamp.light_energy = float(glow.get("energy", 3.0))
		lamp.omni_range = maxf(float(glow.get("range", 2.4)), 0.8)
		lamp.visible = true


static func _age_pops(board: Board, delta: float) -> void:
	var keep: Array[Dictionary] = []
	for spark: Dictionary in board.sparks:
		spark["age"] = float(spark.get("age", 0.0)) + delta
		if float(spark["age"]) < POP_LIFE:
			keep.append(spark)
	board.sparks = keep


static func _retire_overflow() -> void:
	var batched := 0
	for shot in _shots:
		if shot != null and is_instance_valid(shot) and _batch_radius(shot) > 0.001:
			batched += 1
	if batched < BATCH_CAP:
		return
	for shot in _shots:
		if shot == null or not is_instance_valid(shot):
			continue
		if _batch_radius(shot) <= 0.001:
			continue
		if shot.has_method(&"shot_retire"):
			shot.call(&"shot_retire")
		else:
			shot.queue_free()
		return


static func _prune_shots() -> void:
	var live: Array[Node] = []
	for shot in _shots:
		if shot != null and is_instance_valid(shot) and shot.is_inside_tree():
			live.append(shot)
	_shots = live


static func _prune_board(board: Board) -> void:
	var live: Array[Node] = []
	for shot in board.shots:
		if shot != null and is_instance_valid(shot) and shot.is_inside_tree():
			live.append(shot)
	board.shots = live
	if not live.is_empty():
		return
	var key := -1
	for board_key: Variant in _boards.keys():
		if _boards[board_key] == board:
			key = int(board_key)
			break
	if key >= 0:
		_boards.erase(key)
	if is_instance_valid(board) and board.sparks.is_empty():
		board.queue_free()


static func _glow_at(shot: Node) -> Vector3:
	if shot.has_method(&"shot_glow_at"):
		var at: Variant = shot.call(&"shot_glow_at")
		if at is Vector3:
			return at
	if shot is Node3D:
		return (shot as Node3D).global_position
	return Vector3(INF, INF, INF)


static func _glow_color(shot: Node) -> Color:
	if shot.has_method(&"shot_glow_color"):
		var tint: Variant = shot.call(&"shot_glow_color")
		if tint is Color:
			return tint
	return CrawlerBubble.GLOW_COLOR


static func _glow_energy(shot: Node) -> float:
	if shot.has_method(&"shot_glow_energy"):
		return maxf(float(shot.call(&"shot_glow_energy")), 0.0)
	return 0.0


static func _glow_range(shot: Node) -> float:
	if shot.has_method(&"shot_glow_range"):
		return maxf(float(shot.call(&"shot_glow_range")), 0.0)
	return 2.4


static func _batch_radius(shot: Node) -> float:
	if shot.has_method(&"shot_batch_radius"):
		return maxf(float(shot.call(&"shot_batch_radius")), 0.0)
	return 0.0


static func _batch_pulse(shot: Node) -> float:
	if shot.has_method(&"shot_batch_pulse"):
		return maxf(float(shot.call(&"shot_batch_pulse")), 0.05)
	return 1.0


static func _camera_at(board: Node) -> Vector3:
	if board == null or not board.is_inside_tree():
		return Vector3.ZERO
	var viewport := board.get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null:
			return camera.global_position
	return Vector3.ZERO


static func _can_draw() -> bool:
	return DisplayServer.get_name() != "headless"
