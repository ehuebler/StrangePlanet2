class_name Weapons
extends RefCounted

## Puts weapons built by assets/source/blender/build_weapons.py into the hands of
## a character instanced from player_character.glb.
##
## Each weapon .glb has its origin at the centre of its grip and points along its
## own -Z, with +Z up. A weapon hangs off a BoneAttachment3D on the hand bone, so
## it follows the hand through every clip the body plays without needing its own
## skeleton or its own copy of the animations.
##
## The offset that puts the grip inside the fist is **derived from the skeleton**
## rather than written down: the hand bone supplies the direction and the distance
## to its parent supplies the length. Nothing here needs updating when the
## character's proportions change.
##
## OnlinePlayer derives its pencil materials by walking every MeshInstance3D under
## the character, so equip before that runs and weapons are shaded like the body,
## picking up the colours baked into their .glb.

const WEAPONS := {
	"sword": "res://assets/runtime/items/sword.glb",
	"laser_rifle": "res://assets/runtime/items/laser_rifle.glb",
}

const HANDS := {
	"right": "RightHand",
	"left": "LeftHand",
}

const NODE_PREFIX := "Weapon_"

## How far along the hand bone the grip sits, as a fraction of the bone's length.
## This is the centroid of the vertices weighted to that bone, measured off
## player_character.glb by assets/source/blender/character_ref.py. It must match
## GRIP_ALONG_HAND there, or a weapon sits in a different place in Godot than it
## does in the Blender previews.
const GRIP_ALONG_HAND := 0.66


static func names() -> Array:
	return WEAPONS.keys()


static func hands() -> Array:
	return HANDS.keys()


static func skeleton_of(character: Node) -> Skeleton3D:
	for node in character.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


## Rest transform of `bone` in skeleton space. Walked rather than read straight
## off the skeleton so this does not depend on which Godot version exposes
## get_bone_global_rest().
static func global_rest(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var result := Transform3D.IDENTITY
	var index := bone
	while index >= 0:
		result = skeleton.get_bone_rest(index) * result
		index = skeleton.get_bone_parent(index)
	return result


## Where a grip should sit inside the given hand, in skeleton space.
static func grip_point(skeleton: Skeleton3D, bone: int) -> Vector3:
	var rest := global_rest(skeleton, bone)
	var along := _bone_along(skeleton, bone)
	if along.length_squared() < 0.0001:
		# A leaf bone has no child to measure against; the authored humanoid
		# hands run along local +Y the way Blender exports them.
		var length: float = skeleton.get_bone_rest(bone).origin.length()
		along = rest.basis.y.normalized() * length
	return rest.origin + along.normalized() * (along.length() * GRIP_ALONG_HAND)


## Direction and length of `bone`, taken from a child joint when the rig has
## one. Mixamo hands have finger bones and do not run along +Y.
static func _bone_along(skeleton: Skeleton3D, bone: int) -> Vector3:
	var rest := global_rest(skeleton, bone)
	var preferred := -1
	var fallback := -1
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_parent(index) != bone:
			continue
		if fallback < 0:
			fallback = index
		if skeleton.get_bone_name(index).begins_with("middle"):
			preferred = index
			break
	var child := preferred if preferred >= 0 else fallback
	if child < 0:
		return Vector3.ZERO
	return global_rest(skeleton, child).origin - rest.origin


## Local transform for a weapon parented to `bone`'s attachment: puts the grip at
## the fist and leaves the weapon aiming along the character's forward. Because a
## BoneAttachment3D carries the bone's pose, the weapon then tracks the hand.
static func grip_transform(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var rest := global_rest(skeleton, bone)
	var held := Transform3D(Basis.IDENTITY, grip_point(skeleton, bone))
	return rest.affine_inverse() * held


## Arms `hand` with `weapon`, replacing whatever it already holds. `source` names
## the .glb, defaulting to the one WEAPONS lists. Returns the weapon mesh, or null
## if the hand or weapon is unknown or the character has no matching bone.
static func equip(character: Node, hand: String, weapon: String, source := "") -> MeshInstance3D:
	var skeleton := skeleton_of(character)
	if skeleton == null:
		push_error("Weapons: %s has no Skeleton3D" % character.name)
		return null
	if not HANDS.has(hand):
		push_error("Weapons: unknown hand '%s'" % hand)
		return null
	var bone := CharacterRig.find_bone(skeleton, StringName(HANDS[hand]))
	if bone < 0:
		push_error("Weapons: no '%s' bone on %s" % [HANDS[hand], skeleton.name])
		return null
	if source.is_empty():
		if not WEAPONS.has(weapon):
			push_error("Weapons: unknown weapon '%s'" % weapon)
			return null
		source = WEAPONS[weapon]

	var scene := load(source) as PackedScene
	if scene == null:
		push_error("Weapons: could not load %s" % source)
		return null
	var instance := scene.instantiate()
	var mesh: MeshInstance3D = null
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		mesh = node as MeshInstance3D
		break
	if mesh == null:
		push_error("Weapons: %s contains no MeshInstance3D" % source)
		instance.free()
		return null

	# Lift the mesh out of its imported scene and discard the rest of it.
	mesh.get_parent().remove_child(mesh)
	instance.free()

	unequip(character, hand)
	var mount := BoneAttachment3D.new()
	mount.name = NODE_PREFIX + hand
	skeleton.add_child(mount)
	mount.bone_name = String(CharacterRig.bone_name(skeleton, StringName(HANDS[hand])))
	mount.add_child(mesh)
	mesh.transform = grip_transform(skeleton, bone)
	return mesh


static func unequip(character: Node, hand: String) -> void:
	var skeleton := skeleton_of(character)
	if skeleton == null:
		return
	var mount := skeleton.get_node_or_null(NODE_PREFIX + hand)
	if mount != null:
		skeleton.remove_child(mount)
		mount.queue_free()


## Arms both hands at once. Returns {hand: MeshInstance3D} for whatever stuck.
static func dual_wield(character: Node, right := "sword", left := "laser_rifle") -> Dictionary:
	var held := {}
	for pair in [["right", right], ["left", left]]:
		var mesh := equip(character, pair[0], pair[1])
		if mesh != null:
			held[pair[0]] = mesh
	return held
