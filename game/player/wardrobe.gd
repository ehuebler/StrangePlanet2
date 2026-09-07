class_name Wardrobe
extends RefCounted

## Puts apparel onto a character instanced from the body .glb.
##
## Skinned garments from assets/source/blender/build_apparel.py share the body's
## 23 joints, so lifting the MeshInstance3D onto the body's Skeleton3D leaves
## them driven by whatever the body is already playing. Script-built cloth
## (a cape) keeps its own node so it can simulate in world space; Wardrobe
## instances that scene whole and asks it to pin itself to the shoulders.
##
## OnlinePlayer derives its pencil materials by walking every MeshInstance3D
## under the character, so equip before that runs and garments are shaded like
## the rest of the body.

const APPAREL := {
	"shoes": "res://assets/runtime/apparel/apparel_shoes.glb",
	"pants": "res://assets/runtime/apparel/apparel_pants.glb",
	"long_sleeve": "res://assets/runtime/apparel/apparel_long_sleeve.glb",
	"hat": "res://assets/runtime/apparel/apparel_hat.glb",
	"goggles": "res://assets/runtime/apparel/apparel_goggles.glb",
}

const NODE_PREFIX := "Apparel_"


static func slots() -> Array:
	return APPAREL.keys()


static func skeleton_of(character: Node) -> Skeleton3D:
	for node in character.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


## Wears `slot`, replacing whatever occupies it. `source` names the garment .glb
## to wear, so two items sharing a slot can be different garments; it defaults to
## the one garment APPAREL lists for the slot. Returns the garment, or null if the
## slot is unknown or the character has no skeleton.
static func equip(character: Node, slot: String, source := "") -> MeshInstance3D:
	var skeleton := skeleton_of(character)
	if skeleton == null:
		push_error("Wardrobe: %s has no Skeleton3D" % character.name)
		return null
	if source.is_empty():
		if not APPAREL.has(slot):
			push_error("Wardrobe: unknown apparel slot '%s'" % slot)
			return null
		source = APPAREL[slot]

	var scene := load(source) as PackedScene
	if scene == null:
		push_error("Wardrobe: could not load %s" % source)
		return null

	var instance := scene.instantiate()
	unequip(character, slot)
	if instance.has_method(&"attach_to_skeleton"):
		instance.name = NODE_PREFIX + slot
		skeleton.add_child(instance)
		instance.call(&"attach_to_skeleton", skeleton)
		var cloth := mesh_of(instance)
		if cloth == null:
			push_error("Wardrobe: %s attached without a MeshInstance3D" % source)
		return cloth

	var garment := mesh_of(instance)
	if garment == null:
		push_error("Wardrobe: %s contains no MeshInstance3D" % source)
		instance.free()
		return null

	# Lift the garment out of its own imported scene, then discard the rest of
	# that scene including its duplicate skeleton.
	garment.get_parent().remove_child(garment)
	instance.free()

	garment.name = NODE_PREFIX + slot
	skeleton.add_child(garment)
	garment.transform = Transform3D.IDENTITY
	# Relative to the garment, so it resolves to the Skeleton3D it now sits under.
	garment.skeleton = NodePath("..")
	return garment


static func mesh_of(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	if root == null:
		return null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		return node as MeshInstance3D
	return null


static func worn_node(character: Node, slot: String) -> Node:
	var skeleton := skeleton_of(character)
	if skeleton == null:
		return null
	return skeleton.get_node_or_null(NODE_PREFIX + slot)


static func worn_mesh(character: Node, slot: String) -> MeshInstance3D:
	return mesh_of(worn_node(character, slot))


static func unequip(character: Node, slot: String) -> void:
	var skeleton := skeleton_of(character)
	if skeleton == null:
		return
	var worn := skeleton.get_node_or_null(NODE_PREFIX + slot)
	if worn != null:
		skeleton.remove_child(worn)
		worn.queue_free()


static func equip_all(character: Node) -> Array:
	var worn := []
	for slot in APPAREL:
		var garment := equip(character, slot)
		if garment != null:
			worn.append(garment)
	return worn
