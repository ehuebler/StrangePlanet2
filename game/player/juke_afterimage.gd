class_name JukeAfterimage
extends Node3D

## A frozen, fading copy of the player body left behind during a juke.

const LIFE := 0.28
const PEAK_ALPHA := 0.40
const TINT := Color(0.70, 0.86, 1.0, 1.0)

var _left := LIFE
var _span := LIFE
var _material: StandardMaterial3D


static func spawn(source: Node3D, world: Node) -> JukeAfterimage:
	if source == null or world == null or not is_instance_valid(source):
		return null
	var ghost := JukeAfterimage.new()
	world.add_child(ghost)
	ghost._build(source)
	return ghost


func _build(source: Node3D) -> void:
	var saved := source.global_transform
	var copy := source.duplicate() as Node3D
	if copy == null:
		queue_free()
		return
	_prune(copy)
	add_child(copy)
	copy.global_transform = saved
	copy.process_mode = Node.PROCESS_MODE_DISABLED
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.albedo_color = Color(TINT, PEAK_ALPHA)
	_paint(copy)
	set_process(true)


func _prune(node: Node) -> void:
	if node == null:
		return
	node.set_script(null)
	var doomed: Array[Node] = []
	for child: Node in node.get_children():
		if child is PhysicalBone3D or child is PhysicalBoneSimulator3D \
				or child is CollisionObject3D or child is CollisionShape3D:
			doomed.append(child)
			continue
		_prune(child)
	for child: Node in doomed:
		node.remove_child(child)
		child.free()


func _paint(node: Node) -> void:
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		player.active = false
		player.stop()
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.visible = true
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_overlay = null
		mesh.material_override = _material
	for child: Node in node.get_children():
		_paint(child)


func _process(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	if _material != null:
		var share := _left / maxf(_span, 0.01)
		_material.albedo_color.a = PEAK_ALPHA * share * share
	if _left <= 0.0:
		queue_free()
