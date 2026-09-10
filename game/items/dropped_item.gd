class_name DroppedItem
extends StaticBody3D

## One finite inventory item resting in the world.
##
## It is a StaticBody rather than an Area because the player's interaction ray
## deliberately asks for physics bodies. The server owns whether this pickup
## still exists; this node only displays the replicated result and forwards an E
## interaction to [GameWorld].

const DISPLAY_REACH := 0.72
const TARGET_SIZE := Vector3(0.78, 0.82, 0.78)

var pickup_id := 0
var item_id := ""
var _visual: Node3D
var _visual_origin := Vector3.ZERO
var _motion: Dictionary = {}


func configure(id: int, item: String) -> void:
	pickup_id = id
	item_id = item
	name = "DroppedItem_%d" % pickup_id


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_visual()
	_build_collision()


func begin_settle() -> void:
	_motion = DroppedWorldMotion.start(self, 0.10)


func begin_settle_to(at: Vector3) -> void:
	_motion = DroppedWorldMotion.start_to(self, at)


func _process(delta: float) -> void:
	DroppedWorldMotion.tick(self, _visual, _motion, delta, _visual_origin)


func interact_prompt() -> String:
	return "Pick up %s" % ItemDB.title(item_id)


func interact(player: OnlinePlayer) -> void:
	if player == null or item_id.is_empty():
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is GameWorld:
			(ancestor as GameWorld).request_pickup(pickup_id, player.peer_id)
			return
		ancestor = ancestor.get_parent()


func _build_visual() -> void:
	var path := ItemDB.scene_path(item_id)
	var packed := load(path) as PackedScene if not path.is_empty() else null
	if packed == null:
		_build_fallback_visual()
		return
	_visual = packed.instantiate() as Node3D
	if _visual == null:
		_build_fallback_visual()
		return
	add_child(_visual)
	SurfaceSkin.apply(_visual)

	var span := 0.0
	var lowest := INF
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.mesh.get_aabb()
		span = maxf(span, maxf(maxf(box.size.x, box.size.y), box.size.z))
		lowest = minf(lowest, box.position.y)
	var fit := DISPLAY_REACH / maxf(span, 0.01)
	_visual.scale = Vector3.ONE * minf(fit, 1.0)
	if lowest != INF:
		_visual.position.y = -lowest * _visual.scale.y + 0.08
	_visual_origin = _visual.position


func _build_fallback_visual() -> void:
	_visual = Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 0.42, 0.42)
	var material := StandardMaterial3D.new()
	material.albedo_color = ItemDB.tint(item_id)
	material.roughness = 0.72
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.29
	_visual.add_child(mesh_instance)
	add_child(_visual)
	_visual_origin = _visual.position


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = TARGET_SIZE
	var collider := CollisionShape3D.new()
	collider.position.y = shape.size.y * 0.5
	collider.shape = shape
	add_child(collider)
