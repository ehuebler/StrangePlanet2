class_name CrawlerSpawnPad
extends Node3D

## Tide Margin spawn. The Relay 07 teleporter sits at the authored
## coordinate-plate reading; the player arrives on its receiver pad.
## The field stays dark until a player steps off this deck. After that
## the pad is scenery: packs can walk onto it and never despawn there.

const GROUP := &"crawler_spawn_pads"
const MODEL := "res://assets/runtime/environment/relay_07_spawn.glb"
const NIGHT_LIGHTS := preload("res://game/city/building_night_lights.gd")
const DECK_RADIUS := 10.0
const MARKER_LIFT := 0.30
const PLAYER_CLEARANCE := 1.35
const KEEPOUT_PAD := 8.0
## Authored names on Relay 07, first match wins. The navigation console is the
## computer the arrival faces; PHASE CONTROL is the labelled screen on it.
const PANEL_NAMES := [
	"30 Navigation console 1 | Panel",
	"PHASE CONTROL",
	"30 Navigation console 1 | Purple",
	"ARRIVAL LOCK",
]

var force_model := false
var _model: Node3D
var _field_open := false
var _saw_standing := false


func configure(at: Transform3D) -> void:
	transform = at


func _ready() -> void:
	add_to_group(GROUP)
	_attach_model()
	_register_flora()
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _field_open or not is_inside_tree():
		set_physics_process(false)
		return
	var tree := get_tree()
	if tree == null:
		return
	for node_variant: Variant in tree.get_nodes_in_group("network_players"):
		var body := node_variant as Node3D
		if body != null:
			notice_player(body.global_position)
		if _field_open:
			return


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
	up = up.normalized()
	at.origin += up * (lift + maxf(clearance, 0.0))
	var panel := control_panel_point()
	if panel.is_finite():
		var toward := panel - at.origin
		toward -= up * toward.dot(up)
		if toward.length_squared() > 0.0001:
			at.basis = Basis.looking_at(toward.normalized(), up)
	return at


func player_spawn_transform_for(index: int, count: int,
		clearance := PLAYER_CLEARANCE) -> Transform3D:
	var at := player_spawn_transform(clearance)
	var n := maxi(count, 1)
	if n <= 1:
		return at
	var up := at.basis.y
	if up.length_squared() < 0.0001:
		up = world_up()
	up = up.normalized()
	var right := at.basis.x
	if right.length_squared() < 0.0001 or absf(right.dot(up)) > 0.98:
		right = up.cross(Vector3.FORWARD)
		if right.length_squared() < 0.0001:
			right = up.cross(Vector3.RIGHT)
	right = (right - up * right.dot(up)).normalized()
	var forward := up.cross(right).normalized()
	var angle := TAU * float(posmod(index, n)) / float(n)
	at.origin += (right * cos(angle) + forward * sin(angle)) * 2.4
	return at


## World point on the teleporter's computer console, or INF if the model is not
## seated yet. Spawn facing and the home-screen handover both read this.
func control_panel_point() -> Vector3:
	var panel := _control_panel()
	if panel == null:
		return Vector3.INF
	if panel is MeshInstance3D:
		var mesh := panel as MeshInstance3D
		var bounds := mesh.get_aabb()
		if bounds.size.length_squared() > 0.0001:
			return mesh.to_global(bounds.get_center())
	return panel.global_position


func holds_standing(point: Vector3) -> bool:
	if not point.is_finite() or not is_inside_tree():
		return false
	var local := to_local(point)
	var marker := _marker()
	if marker != null:
		var mark := to_local(marker.global_position)
		local -= Vector3(mark.x, 0.0, mark.z)
	var radial := Vector2(local.x, local.z).length()
	return radial <= DECK_RADIUS \
		and local.y >= -12.0 and local.y <= 28.0


## True until a player who stood on the deck walks off. Horde fill waits
## on this; after it flips the pad is no longer a site.
func holds_field() -> bool:
	return not _field_open


func shelters_standing(point: Vector3) -> bool:
	return holds_field() and holds_standing(point)


func notice_player(point: Vector3) -> void:
	if _field_open or not point.is_finite():
		return
	if holds_standing(point):
		_saw_standing = true
		return
	if _saw_standing:
		open_field()


func open_field() -> void:
	if _field_open:
		return
	_field_open = true
	if is_inside_tree():
		set_physics_process(false)


func blocks_near(_point: Vector3) -> bool:
	return false


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


func _control_panel() -> Node3D:
	if _model == null:
		_model = get_node_or_null("Relay") as Node3D
	var host := _model if _model != null else self
	for panel_name: String in PANEL_NAMES:
		var found := host.find_child(panel_name, true, false) as Node3D
		if found != null:
			return found
	for node: Node in host.find_children("*", "MeshInstance3D", true, false):
		var label := String(node.name)
		if label.contains("Navigation console") and label.contains("Panel"):
			return node as Node3D
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
	BuildingFloraClear.register(
		str(get_instance_id()),
		direction,
		CrawlerRules.START_FLORA_RADIUS,
		planet_radius,
		0.0)


func _planet_host() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		if walk is GameWorld:
			return (walk as GameWorld).planet()
		walk = walk.get_parent()
	return null
