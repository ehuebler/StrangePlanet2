class_name PatchMonument
extends Landmark

## Named building on a land patch. Present in every game mode. Crawler packs
## stay out of its keep-out, and a bought quest can raise its tilde waypoint.

const KEEP_GROUP := &"patch_monuments"

var monument_id := ""
var keepout_radius := 180.0


func _ready() -> void:
	add_to_group(KEEP_GROUP)
	super()


func _exit_tree() -> void:
	BuildingFloraClear.unregister_node(self)


func blocks_spawn(at: Vector3) -> bool:
	return at.is_finite() and global_position.distance_to(at) <= keepout_radius


static func blocks_any(tree: SceneTree, at: Vector3) -> bool:
	if tree == null or not at.is_finite():
		return false
	for node_variant: Variant in tree.get_nodes_in_group(KEEP_GROUP):
		var site := node_variant as PatchMonument
		if site != null and site.blocks_spawn(at):
			return true
	return false


static func find_id(monument_id: String) -> PatchMonument:
	if monument_id.is_empty():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node_variant: Variant in tree.get_nodes_in_group(KEEP_GROUP):
		var site := node_variant as PatchMonument
		if site != null and site.monument_id == monument_id:
			return site
	return null


static func enable_waypoint(monument_id: String, announce := true) -> void:
	var site := find_id(monument_id)
	if site == null:
		return
	var first := not site.waypoint
	site.waypoint = true
	if not site.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP):
		site.add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
	if first and announce:
		CrawlerSites.announce_unlock(site)


static func apply_owned_quests(progress: CrawlerProgress) -> void:
	if progress == null:
		return
	for quest_id: String in progress.owned_quests:
		enable_waypoint(quest_id, false)
