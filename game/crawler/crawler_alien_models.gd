class_name CrawlerAlienModels
extends RefCounted

## Looks up authored Scout / Gray / Tanglemaw scenes.

const FOLDERS: PackedStringArray = [
	"res://assets/runtime/crawler/aliens/",
	"res://assets/source/crawler/aliens/",
]


static func scene(kind: String) -> PackedScene:
	for path: String in paths(kind):
		if not ResourceLoader.exists(path):
			continue
		var loaded := load(path)
		if loaded is PackedScene:
			return loaded as PackedScene
	return null


static func paths(kind: String) -> PackedStringArray:
	var names := _file_names(kind.strip_edges().to_lower())
	if names.is_empty():
		return PackedStringArray()
	var out := PackedStringArray()
	for folder: String in FOLDERS:
		for name: String in names:
			out.append("%s%s.glb" % [folder, name])
			out.append("%s%s.gltf" % [folder, name])
	return out


static func bind_socket(model: Node, bone_name: String) -> Node3D:
	if model == null or bone_name.is_empty():
		return null
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return null
	var found := ""
	var folded := bone_name.to_lower()
	for bone in skeleton.get_bone_count():
		var listed := skeleton.get_bone_name(bone)
		if listed == bone_name or listed.to_lower() == folded:
			found = listed
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


static func _file_names(kind: String) -> PackedStringArray:
	match kind:
		"scout":
			return PackedStringArray(["Scout_Saucer", "scout_saucer", "scout"])
		"gray", "grey":
			return PackedStringArray(["Grey_Rifleman", "Gray_Rifleman", "grey_rifleman", "gray"])
		"tanglemaw":
			return PackedStringArray(["Tanglemaw", "tangle_maw", "tanglemaw"])
	return PackedStringArray()
