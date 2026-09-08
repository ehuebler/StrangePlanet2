class_name CrawlerDemonModels
extends RefCounted

## Looks up authored Gloam / Vesper / Threnody scenes. Drop the cursed-angel
## GLBs in [code]assets/runtime/crawler/demons[/code].

const FOLDERS: PackedStringArray = [
	"res://assets/runtime/crawler/demons/",
	"res://assets/source/crawler/demons/",
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


static func _file_names(kind: String) -> PackedStringArray:
	match kind:
		"gloam":
			return PackedStringArray(["Gloam_Maw", "gloam_maw", "gloam"])
		"vesper":
			return PackedStringArray(["Vesper_Seraph", "vesper_seraph", "vesper"])
		"threnody":
			return PackedStringArray(["Threnody_Oracle", "threnody_oracle", "threnody"])
	return PackedStringArray()
