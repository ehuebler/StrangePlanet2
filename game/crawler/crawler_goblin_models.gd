class_name CrawlerGoblinModels
extends RefCounted

## Looks up authored Gruk / Nix / Vex scenes. Drop the walk-run-swing GLBs in
## [code]assets/runtime/crawler/goblins[/code] (or the fauna models folder).

const FOLDERS: PackedStringArray = [
	"res://assets/runtime/crawler/goblins/",
	"res://assets/runtime/fauna/models/",
	"res://assets/source/crawler/goblins/",
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
	var clean := kind.strip_edges().to_lower()
	if clean.is_empty():
		return PackedStringArray()
	var names := PackedStringArray([
		clean.to_upper(),
		clean.capitalize(),
		"goblin_%s" % clean,
		"goblin-%s" % clean,
		"%s_goblin" % clean,
	])
	var out := PackedStringArray()
	for folder: String in FOLDERS:
		for name: String in names:
			out.append("%s%s.glb" % [folder, name])
			out.append("%s%s.gltf" % [folder, name])
	return out
