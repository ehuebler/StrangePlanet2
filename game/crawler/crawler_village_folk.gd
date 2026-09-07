class_name CrawlerVillageFolk
extends Node3D

## Friendly meeps for a crawler village. Wanderers stay on the road markers;
## keepers stand behind shop counters; one named local hides off the lanes.

const SPROUT := preload("res://game/crawler/crawler_sproutling.gd")

const WANDER_COUNT := 17
const WANDER_MIN := 15
const WANDER_MAX := 20
const SHOP_BACK := 0.95
const HIDDEN_NAME := "Moss"
const HIDDEN_LOCAL := Vector3(-18.6, 0.0, 26.8)

const SHOPS: Array[Dictionary] = [
	{"mark": "INTERACT_HATS", "title": "Brim"},
	{"mark": "INTERACT_FUSION", "title": "Fuse"},
	{"mark": "INTERACT_CAPES", "title": "Drape"},
	{"mark": "INTERACT_MODS", "title": "Twig"},
	{"mark": "INTERACT_ABILITIES", "title": "Spark"},
	{"mark": "INTERACT_UPGRADES", "title": "Boost"},
	{"mark": "INTERACT_STASH", "title": "Bin"},
	{"mark": "INTERACT_QUESTS", "title": "Map"},
	{"mark": "INTERACT_DUALS", "title": "Pair"},
]


func populate(village: Node3D, seed: int, hide_at := Vector3.ZERO) -> void:
	if village == null:
		return
	name = "VillageFolk"
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(seed, 1)
	var path := _path_points(village)
	_seed_wanderers(village, path, rng)
	_seed_keepers(village, rng)
	_seed_hidden(village, rng, hide_at)


func wanderers() -> Array[CrawlerSproutling]:
	return _by_role(CrawlerSproutling.Role.WANDER)


func keepers() -> Array[CrawlerSproutling]:
	return _by_role(CrawlerSproutling.Role.SHOP)


func hidden() -> CrawlerSproutling:
	var found := _by_role(CrawlerSproutling.Role.HIDDEN)
	return found[0] if not found.is_empty() else null


func _seed_wanderers(
		village: Node3D,
		path: PackedVector3Array,
		rng: RandomNumberGenerator
	) -> void:
	if path.is_empty():
		return
	var count := clampi(WANDER_COUNT, WANDER_MIN, WANDER_MAX)
	for index in count:
		var home := path[index % path.size()]
		var folk: CrawlerSproutling = SPROUT.new()
		add_child(folk)
		folk.position = Vector3(
			home.x + rng.randf_range(-0.7, 0.7),
			0.0,
			home.z + rng.randf_range(-0.7, 0.7)
		)
		folk.configure(
			_variant(rng, index),
			CrawlerSproutling.Role.WANDER,
			int(rng.randi()),
			"",
			path
		)


func _seed_keepers(village: Node3D, rng: RandomNumberGenerator) -> void:
	var used := 0
	for shop_variant: Variant in SHOPS:
		if typeof(shop_variant) != TYPE_DICTIONARY:
			continue
		var shop := shop_variant as Dictionary
		var mark := _named_contains(village, str(shop.get("mark", ""))) as Node3D
		if mark == null:
			continue
		var parent := mark.get_parent() as Node3D
		if parent == null:
			continue
		var folk: CrawlerSproutling = SPROUT.new()
		parent.add_child(folk)
		var planar := Vector3(mark.position.x, 0.0, mark.position.z)
		var inward := Vector3(0.0, 0.0, -1.0)
		if planar.length_squared() >= 0.01:
			inward = -planar.normalized()
		folk.position = inward * SHOP_BACK
		folk.position.y = 0.0
		folk.face_local(-inward)
		folk.configure(
			_variant(rng, 20 + used),
			CrawlerSproutling.Role.SHOP,
			int(rng.randi()),
			str(shop.get("title", ""))
		)
		used += 1


func _seed_hidden(
		_village: Node3D,
		rng: RandomNumberGenerator,
		hide_at := Vector3.ZERO
	) -> void:
	var folk: CrawlerSproutling = SPROUT.new()
	add_child(folk)
	var at := hide_at if hide_at.length_squared() > 0.01 else HIDDEN_LOCAL
	folk.position = at
	folk.face_local(-at)
	folk.configure(
		_variant(rng, 40),
		CrawlerSproutling.Role.HIDDEN,
		int(rng.randi()),
		HIDDEN_NAME
	)


func _path_points(village: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for child: Node in village.get_children():
		if not child is Node3D:
			continue
		var node := child as Node3D
		var label := str(node.name)
		if not (
			label.begins_with("Streetlight_")
			or label.begins_with("Plaza_Bench_")
			or label.begins_with("Lane_Bench_")
		):
			continue
		points.append(Vector3(node.position.x, 0.0, node.position.z))
	return points


func _variant(rng: RandomNumberGenerator, index: int) -> String:
	var names := CrawlerSproutling.VARIANTS
	if names.is_empty():
		return "Luma"
	if index < names.size():
		return names[index]
	return names[rng.randi_range(0, names.size() - 1)]


func _by_role(job: CrawlerSproutling.Role) -> Array[CrawlerSproutling]:
	var found: Array[CrawlerSproutling] = []
	var root := get_parent()
	if root == null:
		root = self
	for node: Node in root.find_children("*", "Node3D", true, false):
		if node is CrawlerSproutling \
				and (node as CrawlerSproutling).role == job:
			found.append(node as CrawlerSproutling)
	return found


static func _named_contains(root: Node, needle: String) -> Node:
	if root == null or needle.is_empty():
		return null
	for node: Node in root.find_children("*", "", true, false):
		if str(node.name).contains(needle):
			return node
	return null
