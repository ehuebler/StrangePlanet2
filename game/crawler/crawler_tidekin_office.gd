class_name CrawlerTidekinOffice
extends Node3D

## Friendly Tidekin flock for Meridian Tower. Pads are harvested from the
## seated office at generation. A handful of each variant walk those
## floors while a player is inside, then despawn once everyone leaves.

const GROUP := &"crawler_tidekin_office"
const PER_VARIANT := 4
const FLOOR_Y: Array[float] = [1.0, 5.5, 10.0, 14.5, 19.0, 23.5]
const LEAVE_PAD := 12.0
const NEAR_RANGE := 80.0
const PATH_X: Array[float] = [-18.0, -6.0, 6.0, 18.0]
const PATH_Z: Array[float] = [-16.0, 0.0, 16.0, 26.0]

const HOMES := preload("res://game/crawler/crawler_interior_homes.gd")
const HOME_WANT := 96

var _site: Node3D
var _host: Node3D
var _local_homes: PackedVector3Array = PackedVector3Array()
var _seeded := false
var _auto := false


func _ready() -> void:
	name = "TidekinOffice"
	add_to_group(GROUP)
	set_process(true)


static func attach(site: Node3D, host: Node3D) -> CrawlerTidekinOffice:
	var flock := CrawlerTidekinOffice.new()
	if host != null:
		host.add_child(flock)
	flock.bind(site)
	flock.harvest()
	return flock


func bind(site: Node3D) -> void:
	_site = site
	_host = site
	if site != null:
		var model := site.get_node_or_null("Model") as Node3D
		if model != null:
			_host = model


func apply_homes(world_homes: PackedVector3Array) -> void:
	_local_homes = PackedVector3Array()
	for at: Vector3 in world_homes:
		if not at.is_finite():
			continue
		_local_homes.append(to_local(at) if is_inside_tree() else at)
	_seeded = true


func harvest() -> int:
	var root := _host
	if root == null:
		root = get_parent() as Node3D
	var world := HOMES.harvest(root, HOME_WANT, 2.4)
	_local_homes = PackedVector3Array()
	for at: Vector3 in world:
		if not at.is_finite():
			continue
		_local_homes.append(to_local(at) if is_inside_tree() else at)
	return _local_homes.size()


func home_count() -> int:
	return _local_homes.size()


func home_at(index: int) -> Vector3:
	if index < 0 or index >= _local_homes.size():
		return Vector3.INF
	return to_global(_local_homes[index]) if is_inside_tree() else _local_homes[index]


func live_count() -> int:
	var count := 0
	for child: Node in get_children():
		if child is CrawlerTidekin:
			count += 1
	return count


func populate(seed := 1) -> int:
	_clear()
	if _host == null:
		_host = self
	if _local_homes.is_empty():
		harvest()
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(seed, 1)
	var made := 0
	var slot := 0
	for kind: String in CrawlerTidekin.VARIANTS:
		for _copy in PER_VARIANT:
			var path := _path_for_slot(slot)
			if path.is_empty():
				continue
			var floor_y := path[0].y
			var folk := CrawlerTidekin.new()
			add_child(folk)
			var home := path[rng.randi_range(0, path.size() - 1)]
			folk.position = Vector3(
				home.x + rng.randf_range(-1.1, 1.1),
				floor_y,
				home.z + rng.randf_range(-1.1, 1.1)
			)
			folk.configure(kind, int(rng.randi()), path, floor_y)
			made += 1
			slot += 1
	_seeded = made > 0
	return made


func clear_folk() -> void:
	_clear()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not CrawlerRules.active():
		if _seeded:
			_clear()
		return
	if not _players_nearby():
		if _auto or _seeded:
			_auto = false
			_clear()
		return
	if _anyone_inside():
		_auto = true
		if not _seeded:
			populate(_office_seed())
		return
	if _auto and _everyone_outside():
		_auto = false
		_clear()


func _players_nearby() -> bool:
	var at := _site.global_position if _site != null else global_position
	if not at.is_finite():
		return false
	var reach2 := NEAR_RANGE * NEAR_RANGE
	for player: Node3D in _players():
		if player.global_position.distance_squared_to(at) <= reach2:
			return true
	return false


func _anyone_inside() -> bool:
	for player: Node3D in _players():
		if CrawlerRules.in_office_tower(player.global_position):
			return true
	return false


func _everyone_outside() -> bool:
	for player: Node3D in _players():
		if CrawlerRules.in_office_tower(player.global_position, LEAVE_PAD):
			return false
	return true


func _players() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for player_variant: Variant in CrawlerMobSense.players():
		var player := player_variant as Node3D
		if player != null and is_instance_valid(player):
			found.append(player)
	if not found.is_empty() or not is_inside_tree():
		return found
	for node_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := node_variant as Node3D
		if player != null and is_instance_valid(player):
			found.append(player)
	return found


func _office_seed() -> int:
	if _site is PatchMonument:
		return maxi((_site as PatchMonument).monument_id.hash(), 1)
	return 7


func _path_for_slot(slot: int) -> PackedVector3Array:
	if _local_homes.is_empty():
		return _floor_points(float(FLOOR_Y[slot % FLOOR_Y.size()]))
	var home := _local_homes[slot % _local_homes.size()]
	var path := PackedVector3Array()
	for at: Vector3 in _local_homes:
		if absf(at.y - home.y) <= 2.2:
			path.append(at)
	if path.is_empty():
		path.append(home)
	return path


func _floor_points(floor_y: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for x: float in PATH_X:
		for z: float in PATH_Z:
			points.append(Vector3(x, floor_y, z))
	return points


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_seeded = false
	_auto = false
