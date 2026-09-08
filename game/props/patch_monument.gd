class_name PatchMonument
extends Landmark

## Named building on a land patch. Present in every game mode. Crawler packs
## stay out of its keep-out, and a bought quest can raise its tilde waypoint.

const KEEP_GROUP := &"patch_monuments"

var monument_id := ""
var keepout_radius := 180.0
var encounter := ""


func _ready() -> void:
	add_to_group(KEEP_GROUP)
	super()


func _exit_tree() -> void:
	BuildingFloraClear.unregister_node(self)


func blocks_spawn(at: Vector3) -> bool:
	if CrawlerRules.is_boss_id(monument_id):
		if encounter.is_empty() or encounter == CrawlerRules.BOSS_ENCOUNTER_EMPTY:
			return false
		if encounter == CrawlerRules.BOSS_ENCOUNTER_TREE:
			var tree := get_node_or_null("TreeBoss")
			if tree == null or not tree.has_method(&"blocks_field_spawns") \
					or not bool(tree.call(&"blocks_field_spawns")):
				return false
	return at.is_finite() and global_position.distance_to(at) <= keepout_radius


func in_site_clear(at: Vector3) -> bool:
	return CrawlerRules.in_site_clear(global_position, at)


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
	CrawlerRules.apply_crawler_waypoint_tint(site)
	if first and announce:
		CrawlerSites.announce_unlock(site)


static func apply_owned_quests(progress: CrawlerProgress) -> void:
	if progress == null:
		return
	if not progress.quest_reveals.is_empty():
		for site_id: String in progress.quest_reveals:
			enable_waypoint(site_id, false)
		return
	for quest_id: String in progress.owned_quests:
		enable_waypoint(quest_id, false)
