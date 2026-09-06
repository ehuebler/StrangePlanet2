class_name CrawlerSpawnPad
extends Node3D

## Tide Margin spawn. The Relay 07 teleporter sits at the authored
## coordinate-plate reading; the player arrives on its receiver pad.

const GROUP := &"crawler_spawn_pads"
const MODEL := "res://assets/runtime/environment/relay_07_spawn.glb"
const NIGHT_LIGHTS := preload("res://game/city/building_night_lights.gd")
const DECK_RADIUS := 10.0
const MARKER_LIFT := 0.30
const PLAYER_CLEARANCE := 1.35
const KEEPOUT_PAD := 8.0

var force_model := false
var _model: Node3D


func configure(at: Transform3D) -> void:
	transform = at


func _ready() -> void:
	add_to_group(GROUP)
	_attach_model()
	_register_flora()


func _exit_tree() -> void:
	BuildingFloraClear.unregister_node(self)


func world_up() -> Vector3:
	return global_transform.basis.y.normalized() \
		if is_inside_tree() else Vector3.UP


func world_centre() -> Vector3:
	return global_position


func keepout_radius() -> float:
	return DECK_RADIUS + KEEPOUT_PAD


func player_spawn_transform(clearance := PLAYER_CLEARANCE) -> Transform3D:
	var marker := _marker()
	var at := global_transform
	var lift := MARKER_LIFT
	if marker != null:
		at = marker.global_transform
		lift = 0.0
	var up := at.basis.y
	if up.length_squared() < 0.0001:
		up = world_up()
	at.origin += up.normalized() * (lift + maxf(clearance, 0.0))
	return at


func blocks_near(point: Vector3) -> bool:
	var local := to_local(point) if is_inside_tree() else point
	var radial := Vector2(local.x, local.z).length()
	return radial <= keepout_radius() \
		and local.y >= -12.0 and local.y <= 28.0


static func blocks_near_any(tree: SceneTree, point: Vector3) -> bool:
	if tree == null:
		return false
	for zone_variant: Variant in tree.get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerSpawnPad
		if zone != null and zone.blocks_near(point):
			return true
	return false


func _attach_model() -> bool:
	if not force_model and _planet_host() == null:
		return false
	if not ResourceLoader.exists(MODEL):
		return false
	var held := get_node_or_null("Relay") as Node3D
	if held != null:
		_model = held
		NIGHT_LIGHTS.bind(held, _planet_host())
		return true
	var packed := load(MODEL) as PackedScene
	if packed == null:
		return false
	var body := packed.instantiate() as Node3D
	if body == null:
		return false
	body.name = "Relay"
	add_child(body)
	PatchMonuments.wire_interior_collision(body)
	BuildingFoundation.seat(body, _planet_host())
	NIGHT_LIGHTS.bind(body, _planet_host())
	_model = body
	return true


func _marker() -> Node3D:
	if _model == null:
		_model = get_node_or_null("Relay") as Node3D
	var host := _model if _model != null else self
	for name: String in ["SPAWN_PLAYER", "TELEPORT_TARGET"]:
		var found := host.find_child(name, true, false) as Node3D
		if found != null:
			return found
	return null


func _register_flora() -> void:
	var direction := global_position
	var planet_radius := 8000.0
	var planet := _planet_host()
	if planet != null:
		direction = planet.to_local(global_position)
		if planet.shape != null:
			planet_radius = planet.shape.radius
	if direction.length_squared() < 0.25:
		direction = world_up()
	var reach := DECK_RADIUS
	if _model != null:
		reach = maxf(reach, BuildingFloraClear.mesh_radius(_model))
	BuildingFloraClear.register(
		str(get_instance_id()), direction, reach, planet_radius)


func _planet_host() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		if walk is GameWorld:
			return (walk as GameWorld).planet()
		walk = walk.get_parent()
	return null
