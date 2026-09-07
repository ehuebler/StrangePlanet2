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
	if site_id == CrawlerRules.CITY_SITE_ID and player.journal != null:
		player.journal.note_city()
	if site_id == CrawlerRules.CITY_SITE_ID and first:
		schedule_later_city_unlock(player)
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
			unlock(site, false)
	if progress.site_unlocked(CrawlerRules.CITY_SITE_ID):
		unlock_later_cities(tree, false)


static func unlock(site: Node, announce := true) -> void:
	if site is CrawlerSite:
		(site as CrawlerSite).unlock_waypoint(announce)
		return
	if site is PatchMonument:
		var monument := site as PatchMonument
		if not monument.monument_id.is_empty():
			PatchMonument.enable_waypoint(monument.monument_id, announce)
			return
	if site is Landmark:
		var mark := site as Landmark
		var first := not mark.waypoint
		mark.waypoint = true
		if not mark.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP):
			mark.add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
		if first and announce:
			announce_unlock(mark)


static func schedule_later_city_unlock(player: OnlinePlayer, delay := -1.0) -> void:
	if player == null or not player.is_inside_tree():
		return
	var tree := player.get_tree()
	if later_cities_shown(tree):
		return
	var wait := delay if delay >= 0.0 else CrawlerRules.CITY_MAP_DELAY
	if wait <= 0.0:
		unlock_later_cities(tree, true)
		return
	var timer := tree.create_timer(wait)
	timer.timeout.connect(func() -> void:
		unlock_later_cities(tree, true)
	)


static func unlock_later_cities(tree: SceneTree, announce := true) -> void:
	if tree == null:
		return
	for site in _collect(tree):
		if CrawlerRules.is_later_city(_site_id(site)):
			unlock(site, announce)


static func later_cities_shown(tree: SceneTree) -> bool:
	if tree == null:
		return false
	for site in _collect(tree):
		if CrawlerRules.is_later_city(_site_id(site)):
			var mark := site as Landmark
			if mark != null and mark.waypoint:
				return true
	return false


## Local players turn to a newly unlocked mark. Restored progress stays silent.
static func announce_unlock(site: Node) -> void:
	if site == null or not site.is_inside_tree():
		return
	var landmark := site as Landmark
	if landmark == null:
		return
	for node_variant: Variant in site.get_tree().get_nodes_in_group("network_players"):
		var player := node_variant as OnlinePlayer
		if player == null or not is_instance_valid(player) or player.training_enemy:
			continue
		if player.peer_id != player.multiplayer.get_unique_id():
			continue
		player.notice_waypoint_unlocked(landmark)


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
