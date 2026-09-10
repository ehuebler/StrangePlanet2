class_name CrawlerGlorb
extends RefCounted

## Shared ethereal Glorb bodies. Each kind borrows another mob's hunt and
## attacks; this helper mounts the authored GLB and the living first skin.

const SKIN_SHADER := preload("res://shaders/crawler/crawler_glorb_ethereal.gdshader")
const KIND_JELLYFISH := "glorb_jellyfish"
const KIND_RHINO := "glorb_rhino"
const KIND_EYEBALL := "glorb_eyeball"
const KIND_PUNCHING := "glorb_punching"
const KIND_ONE_ARMED := "glorb_one_armed"
const KIND_SPIDER := "glorb_spider"
const KIND_ANGEL := "glorb_angel"
const KINDS: PackedStringArray = [
	KIND_JELLYFISH, KIND_RHINO, KIND_EYEBALL, KIND_PUNCHING,
	KIND_ONE_ARMED, KIND_SPIDER, KIND_ANGEL,
]
const HEIGHTS := {
	KIND_JELLYFISH: 2.4,
	KIND_RHINO: 1.8,
	KIND_EYEBALL: 1.5,
	KIND_PUNCHING: 1.8,
	KIND_ONE_ARMED: 2.2,
	KIND_SPIDER: 1.6,
	KIND_ANGEL: 2.4,
}


static func scene_path(kind: String) -> String:
	return "res://assets/runtime/crawler/glorbs/%s.glb" % kind.strip_edges()


static func scene(kind: String) -> PackedScene:
	var path := scene_path(kind)
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


static func height(kind: String) -> float:
	return float(HEIGHTS.get(kind.strip_edges(), 1.8))


static func mount(mob: CrawlerMob, kind: String) -> void:
	if mob == null:
		return
	var visual := height(kind)
	var width := visual * 0.36
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = width
	capsule.height = maxf(visual * 0.74, width * 2.0 + 0.05)
	shape.shape = capsule
	mob.add_child(shape)
	var packed := scene(kind)
	if packed != null:
		mob._attach_skinned(packed, visual)
		mob._apply_glorb_ethereal()
		bind_sockets(mob, kind)
		return
	var mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = width
	capsule_mesh.height = visual
	mesh.mesh = capsule_mesh
	mesh.name = "Creature"
	mob.add_child(mesh)
	mob._paint_glorb_white()


static func bind_sockets(mob: CrawlerMob, kind: String) -> void:
	if mob == null:
		return
	var tip := bind_bone(mob, muzzle_bones(kind))
	if tip == null:
		return
	if "_muzzle" in mob:
		mob.set("_muzzle", tip)
	if kind == KIND_SPIDER and "_head" in mob:
		mob.set("_head", tip)


static func muzzle_bones(kind: String) -> PackedStringArray:
	match kind.strip_edges():
		KIND_ONE_ARMED:
			return PackedStringArray(["forearm.R", "arm.R"])
		KIND_JELLYFISH:
			return PackedStringArray(["body", "body_2"])
		KIND_ANGEL:
			return PackedStringArray(["head", "head_2", "forearm.R"])
		KIND_SPIDER:
			return PackedStringArray(["head"])
		KIND_EYEBALL:
			return PackedStringArray(["body", "body_2"])
		KIND_PUNCHING:
			return PackedStringArray(["forearm.R", "arm.R"])
		KIND_RHINO:
			return PackedStringArray(["head", "head_2"])
	return PackedStringArray()


static func bind_bone(mob: CrawlerMob, names: PackedStringArray) -> Node3D:
	if mob == null or names.is_empty():
		return null
	var skeleton := mob.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var found := ""
	for want: String in names:
		found = _match_bone(skeleton, want)
		if not found.is_empty():
			break
	if found.is_empty():
		return null
	var attach := BoneAttachment3D.new()
	attach.name = "Socket_%s" % found.replace(".", "_")
	attach.bone_name = found
	skeleton.add_child(attach)
	var tip := Marker3D.new()
	tip.name = "Muzzle"
	attach.add_child(tip)
	return tip


static func _match_bone(skeleton: Skeleton3D, want: String) -> String:
	var folded := want.to_lower()
	var numbered := ""
	for bone in skeleton.get_bone_count():
		var listed := skeleton.get_bone_name(bone)
		var tail := listed.to_lower()
		if tail == folded:
			return listed
		if tail.begins_with(folded + "_") and tail.substr(folded.length() + 1).is_valid_int():
			numbered = listed
	return numbered
