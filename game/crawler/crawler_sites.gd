class_name CrawlerSites
extends RefCounted

## Proximity poll for crawler "Entering ..." notes and first-visit waypoints.


static func poll(player: OnlinePlayer) -> String:
	if player == null or not player.is_inside_tree() or not CrawlerRules.active():
		return ""
	var progress := player.crawler_progress
	if progress == null:
		return ""
	var site := _nearest(player)
	if site == null:
		return ""
	unlock(site)
	var site_id := _site_id(site)
	var first := not progress.site_unlocked(site_id)
	if not progress.enter_site(site_id):
		return ""
	var gems := 0
	if first:
		gems = progress.award_site_gems()
	var title := _site_title(site)
	var hud := player.combat_hud()
	if hud != null and hud.has_method(&"show_entering"):
		hud.call(&"show_entering", title, gems)
	return title


static func apply_progress(progress: CrawlerProgress, tree: SceneTree) -> void:
	if progress == null or tree == null:
		return
	PatchMonument.apply_owned_quests(progress)
	for site in _collect(tree):
		if progress.site_unlocked(_site_id(site)):
			unlock(site)


static func unlock(site: Node) -> void:
	if site is CrawlerSite:
		(site as CrawlerSite).unlock_waypoint()
		return
	if site is PatchMonument:
		var monument := site as PatchMonument
		if not monument.monument_id.is_empty():
			PatchMonument.enable_waypoint(monument.monument_id)
			return
	if site is Landmark:
		var mark := site as Landmark
		mark.waypoint = true
		if not mark.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP):
			mark.add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)


static func _nearest(player: OnlinePlayer) -> Node3D:
	var best: Node3D = null
	var best_span := INF
	var here := player.global_position
	for site in _collect(player.get_tree()):
		var at := (site as Node3D).global_position
		var span := here.distance_to(at)
		if span <= _enter_radius(site) and span < best_span:
			best = site
			best_span = span
	return best


static func _collect(tree: SceneTree) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if tree == null:
		return found
	for node_variant: Variant in tree.get_nodes_in_group(CrawlerRules.SITE_GROUP):
		_append_site(found, node_variant)
	for node_variant: Variant in tree.get_nodes_in_group(PatchMonument.KEEP_GROUP):
		_append_site(found, node_variant)
	return found


static func _append_site(found: Array[Node3D], node_variant: Variant) -> void:
	var node := node_variant as Node3D
	if node == null or not is_instance_valid(node):
		return
	if _site_id(node).is_empty():
		return
	if found.has(node):
		return
	found.append(node)


static func _site_id(site: Node) -> String:
	if site is CrawlerSite:
		return (site as CrawlerSite).site_id
	if site is PatchMonument:
		return (site as PatchMonument).monument_id
	return ""


static func _site_title(site: Node) -> String:
	if site is Landmark:
		var title := (site as Landmark).title.strip_edges()
		if not title.is_empty():
			return title
	return _site_id(site)


static func _enter_radius(site: Node) -> float:
	if site is CrawlerSite:
		return maxf((site as CrawlerSite).enter_radius, 1.0)
	if site is PatchMonument:
		return maxf((site as PatchMonument).keepout_radius, 1.0)
	return 80.0
