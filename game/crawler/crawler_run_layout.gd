class_name CrawlerRunLayout
extends Node

## Places run-creator sites as the player opens each ring, and lights
## waypoints from city entry and quests.

const GROUP := &"crawler_run_layout"
const CASTLE_MODEL := "res://assets/runtime/environment/stormwatch_castle.glb"
const OFFICE_MODEL := "res://assets/runtime/environment/meridian_office_tower.glb"
const NIGHT_LIGHTS := preload("res://game/city/building_night_lights.gd")
const TIDEKIN_OFFICE := preload("res://game/crawler/crawler_tidekin_office.gd")
const CASTLE_GARRISON := preload("res://game/crawler/crawler_castle_garrison.gd")
const TREE_BOSS := preload("res://game/crawler/crawler_tree_boss.gd")

var _rendered: Dictionary = {}
var _watch := 0.0


func _ready() -> void:
	name = "CrawlerRunLayout"
	add_to_group(GROUP)
	set_process(true)


static func instance(tree: SceneTree = null) -> CrawlerRunLayout:
	var host := tree if tree != null else Engine.get_main_loop() as SceneTree
	if host == null:
		return null
	return host.get_first_node_in_group(GROUP) as CrawlerRunLayout


static func ensure(world: Node) -> CrawlerRunLayout:
	if world == null:
		return null
	var existing := world.get_node_or_null("CrawlerRunLayout") as CrawlerRunLayout
	if existing != null:
		return existing
	var layout := CrawlerRunLayout.new()
	world.add_child(layout)
	return layout


func apply_saved_progress(progress: CrawlerProgress) -> void:
	if not CrawlerRun.active() or progress == null:
		return
	if progress.site_unlocked(CrawlerRules.CITY_SITE_ID) \
			or progress.site_unlocked(CrawlerRun.first_city_id()):
		render_ring(1)
	for raw: Variant in CrawlerRun.cities():
		if not raw is Dictionary:
			continue
		var id := str(raw.get("id", ""))
		var site_id := CrawlerRules.CITY_SITE_ID if id == CrawlerRun.first_city_id() else id
		if not progress.site_unlocked(site_id) and not progress.site_unlocked(id):
			continue
		var ring := int(raw.get("ring", 1))
		render_ring(ring)
		render_ring(ring + 1)
	for site_id: String in progress.quest_reveals:
		var row := _site_row(site_id)
		if not row.is_empty():
			render_ring(int(row.get("ring", 1)))
		PatchMonument.enable_waypoint(site_id, false)


func place_opening() -> void:
	if not CrawlerRun.active():
		return
	var world := _world()
	if world == null:
		return
	_clear_authored_monuments()
	if world.has_method(&"_ensure_crawler_spawn_pad"):
		world.call(&"_ensure_crawler_spawn_pad")
	if world.has_method(&"_ensure_crawler_start_site"):
		world.call(&"_ensure_crawler_start_site")
	_place_city(CrawlerRun.first_city_id())
	if world.has_method(&"_apply_crawler_site_progress"):
		world.call(&"_apply_crawler_site_progress")
	if world.has_method(&"_ensure_crawler_city_gift"):
		world.call(&"_ensure_crawler_city_gift")


func render_ring(ring_id: int) -> void:
	if ring_id <= 0 or _rendered.get(ring_id, false):
		return
	for raw: Variant in CrawlerRun.cities():
		if not raw is Dictionary:
			continue
		var city: Dictionary = raw
		if int(city.get("ring", 0)) != ring_id:
			continue
		_place_city(str(city.get("id", "")))
	for raw: Variant in CrawlerRun.castles():
		if raw is Dictionary and int(raw.get("ring", 0)) == ring_id:
			_place_castle(raw)
	for raw: Variant in CrawlerRun.offices():
		if raw is Dictionary and int(raw.get("ring", 0)) == ring_id:
			_place_office(raw)
	for raw: Variant in CrawlerRun.bosses():
		if raw is Dictionary and int(raw.get("ring", 0)) == ring_id:
			_place_boss(raw)
	_rendered[ring_id] = true


func on_city_entered(site_id: String, player: OnlinePlayer) -> void:
	if not CrawlerRun.active() or site_id.is_empty():
		return
	if site_id == CrawlerRun.first_city_id() or site_id == CrawlerRules.CITY_SITE_ID:
		render_ring(1)
		_reveal_ids(CrawlerRun.later_city_ids(), player)
		return
	if CrawlerRun.city_entry(site_id).is_empty():
		return
	var ring := CrawlerRun.ring_of_city(site_id)
	render_ring(ring)
	render_ring(ring + 1)
	_reveal_nearest_cities(player, 2)


func reveal_quest_site(player: OnlinePlayer, quest_id := "") -> String:
	var picked := _pick_unrevealed(player, quest_id)
	var best_id := str(picked.get("id", ""))
	if best_id.is_empty():
		return ""
	render_ring(int(picked.get("ring", 1)))
	var row := _site_row(best_id)
	if not row.is_empty():
		if CrawlerRules.is_boss_id(best_id):
			_place_boss(row)
		elif CrawlerRules.is_castle_id(best_id):
			_place_castle(row)
		elif CrawlerRules.is_office_id(best_id):
			_place_office(row)
	PatchMonument.enable_waypoint(best_id, true)
	return best_id


func peek_quest_site(player: OnlinePlayer, quest_id := "") -> String:
	return str(_pick_unrevealed(player, quest_id).get("id", ""))


func peek_quest_encounter(player: OnlinePlayer, quest_id := "") -> String:
	var site_id := peek_quest_site(player, quest_id)
	if site_id.is_empty():
		return ""
	if CrawlerRules.is_boss_id(quest_id) or CrawlerRules.is_boss_id(site_id):
		return CrawlerRun.boss_encounter(site_id)
	if CrawlerRules.is_castle_id(site_id):
		return "castle"
	if CrawlerRules.is_office_id(site_id):
		return "office"
	return ""


func quest_shop_encounter(
		player: OnlinePlayer,
		quest_id: String,
		reveals: PackedStringArray = PackedStringArray()
	) -> String:
	for site_id: String in reveals:
		if CrawlerProgress.quest_matches_site(quest_id, site_id):
			if CrawlerRules.is_boss_id(site_id):
				return CrawlerRun.boss_encounter(site_id)
			if CrawlerRules.is_castle_id(site_id):
				return "castle"
			if CrawlerRules.is_office_id(site_id):
				return "office"
			return ""
	return peek_quest_encounter(player, quest_id)


func _process(delta: float) -> void:
	if not CrawlerRun.active():
		return
	_watch -= delta
	if _watch > 0.0:
		return
	_watch = 0.35
	var tree := get_tree()
	if tree == null:
		return
	for node_variant: Variant in tree.get_nodes_in_group(&"network_players"):
		var player := node_variant as Node3D
		if player == null:
			continue
		var ring := CrawlerRun.ring_of_world(player.global_position)
		if ring >= 1:
			render_ring(ring)


func _place_city(city_id: String) -> void:
	if city_id.is_empty():
		return
	var node_name := _city_node_name(city_id)
	var world := _world()
	if world == null or world.get_node_or_null(node_name) != null:
		return
	var row := CrawlerRun.city_entry(city_id)
	var direction := CrawlerRun._dir_of(row)
	if direction.length_squared() < 0.25:
		return
	var overlay := _overlay()
	if overlay == null or not overlay.ensure_ready():
		return
	var at := overlay.surface_transform_for_direction(direction, 0.35)
	if at.origin.length_squared() < 1.0:
		return
	var patch_id := overlay.patch_id_at(at.origin)
	var ring = load("res://game/crawler/crawler_city_ring.gd").new()
	ring.name = node_name
	var site_id := city_id
	if city_id == CrawlerRun.first_city_id():
		site_id = CrawlerRules.CITY_SITE_ID
	var title := city_id
	var model := CrawlerCityRing.VILLAGE_MODEL
	if city_id == "city2":
		model = CrawlerRules.CRESCENT_VILLAGE
	ring.configure(patch_id, at, site_id, title, model, city_id)
	world.add_child(ring)
	if world.has_method(&"_record_crawler_city"):
		world.call(&"_record_crawler_city", city_id)


func _place_castle(row: Dictionary) -> void:
	_place_monument(
		str(row.get("id", "")),
		str(row.get("id", "castle")),
		CrawlerRun._dir_of(row),
		CASTLE_MODEL,
		CrawlerRules.CASTLE_WAYPOINT_TINT,
		true
	)


func _place_office(row: Dictionary) -> void:
	_place_monument(
		str(row.get("id", "")),
		str(row.get("id", "office")),
		CrawlerRun._dir_of(row),
		OFFICE_MODEL,
		CrawlerRules.OFFICE_WAYPOINT_TINT,
		false
	)


func _place_boss(row: Dictionary) -> void:
	var monument_id := str(row.get("id", ""))
	var direction := CrawlerRun._dir_of(row)
	if monument_id.is_empty() or direction.length_squared() < 0.25:
		return
	var host := _monuments()
	if host == null:
		return
	var existing := host.get_node_or_null(monument_id) as PatchMonument
	if existing != null:
		_bind_boss_site(existing, row)
		return
	var radius := maxf(float(row.get("radius_m", CrawlerRules.BOSS_SITE_RADIUS)), 1.0)
	var encounter := str(row.get("encounter", ""))
	if encounter == CrawlerRules.BOSS_ENCOUNTER_TREE \
			or CrawlerRun.is_tree_boss(monument_id):
		radius = CrawlerRules.TREE_BATTLE_RADIUS
	var site := PatchMonument.new()
	site.name = monument_id
	site.monument_id = monument_id
	site.tint = CrawlerRules.BOSS_WAYPOINT_TINT
	site.waypoint = false
	site.keepout_radius = radius
	site.hide_beyond = 0.0
	site.show_beyond = 0.0
	site.aimed_beyond = 0.0
	site.direction = direction
	site.clearance = 0.0
	host.add_child(site)
	_bind_boss_site(site, row)


func _place_monument(
		monument_id: String,
		title: String,
		direction: Vector3,
		model_path: String,
		tint: Color,
		castle: bool
	) -> void:
	if monument_id.is_empty() or direction.length_squared() < 0.25:
		return
	var host := _monuments()
	if host == null:
		return
	if host.get_node_or_null(monument_id) != null:
		return
	var site := PatchMonument.new()
	site.name = monument_id
	site.monument_id = monument_id
	site.title = title
	site.tint = tint
	site.waypoint = false
	site.keepout_radius = PatchMonuments.KEEP_OUT
	site.hide_beyond = 0.0
	site.show_beyond = 0.0
	site.aimed_beyond = 0.0
	site.direction = direction
	site.clearance = 0.0
	host.add_child(site)
	_attach_model(site, model_path, castle)


func _attach_model(site: PatchMonument, model_path: String, castle: bool) -> void:
	if not ResourceLoader.exists(model_path):
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		return
	var body := packed.instantiate() as Node3D
	if body == null:
		return
	body.name = "Model"
	site.add_child(body)
	PatchMonuments.wire_interior_collision(body)
	BuildingFoundation.seat(body, site.planet_host())
	NIGHT_LIGHTS.bind(body, site.planet_host())
	BuildingFloraClear.register_node(
		site, body, site.direction, CrawlerRules.SITE_CLEAR_RADIUS, 0.0)
	if castle:
		var garrison := CASTLE_GARRISON.attach(site, body)
		_apply_goblin_pads(site, garrison)
	else:
		var flock := TIDEKIN_OFFICE.attach(site, body)
		_apply_shrimp_pads(site, flock)


func _apply_goblin_pads(site: PatchMonument, garrison: CrawlerCastleGarrison) -> void:
	if garrison == null:
		return
	var homes := _world_pads(CrawlerRun.goblin_pads_for(site.monument_id))
	if not homes.is_empty():
		garrison.homes = homes


func _apply_shrimp_pads(site: PatchMonument, flock: CrawlerTidekinOffice) -> void:
	if flock == null:
		return
	var homes := _world_pads(CrawlerRun.shrimp_pads_for(site.monument_id))
	if not homes.is_empty():
		flock.apply_homes(homes)


func _world_pads(rows: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var overlay := _overlay()
	if overlay == null:
		return out
	for raw: Variant in rows:
		if not raw is Dictionary:
			continue
		var direction := CrawlerRun._dir_of(raw)
		if direction.length_squared() < 0.25:
			continue
		var at := overlay.surface_transform_for_direction(direction, 1.1)
		if at.origin.length_squared() > 1.0:
			out.append(at.origin)
	return out


func _reveal_ids(ids: PackedStringArray, player: OnlinePlayer) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for site in CrawlerSites._collect(tree):
		var site_id := CrawlerSites._site_id(site)
		if not ids.has(site_id) and not _city_matches(site_id, ids):
			continue
		CrawlerSites.unlock(site, true)
		if player != null:
			player.notice_waypoint_unlocked(site as Landmark)


func _reveal_nearest_cities(player: OnlinePlayer, want: int) -> void:
	if player == null:
		return
	var from := player.global_position.normalized()
	if from.length_squared() < 0.0001:
		from = CrawlerRun.spawn_direction()
	var ranked: Array = []
	for raw: Variant in CrawlerRun.cities():
		if not raw is Dictionary:
			continue
		var id := str(raw.get("id", ""))
		var site_id := CrawlerRules.CITY_SITE_ID if id == CrawlerRun.first_city_id() else id
		if _waypoint_lit(site_id):
			continue
		var facing := CrawlerRun._dir_of(raw)
		if facing.length_squared() < 0.25:
			continue
		ranked.append({"id": site_id, "dot": from.dot(facing.normalized())})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dot"]) > float(b["dot"]))
	var picked := PackedStringArray()
	for row: Dictionary in ranked:
		picked.append(str(row["id"]))
		if picked.size() >= want:
			break
	_reveal_ids(picked, player)


func _quest_rows(quest_id: String) -> Array:
	if CrawlerRules.is_office_id(quest_id):
		return CrawlerRun.offices()
	if CrawlerRules.is_castle_id(quest_id):
		return CrawlerRun.castles()
	if CrawlerRules.is_boss_id(quest_id):
		return CrawlerRun.bosses()
	return []


func _site_row(site_id: String) -> Dictionary:
	if site_id.is_empty():
		return {}
	for listed: Array in [CrawlerRun.castles(), CrawlerRun.offices(), CrawlerRun.bosses()]:
		for raw: Variant in listed:
			if raw is Dictionary and str(raw.get("id", "")) == site_id:
				return raw
	return {}


func _pick_unrevealed(player: OnlinePlayer, quest_id: String) -> Dictionary:
	var empty := {"id": "", "dot": -2.0, "ring": 1}
	if not CrawlerRun.active():
		return empty
	var from := player.global_position if player != null else Vector3.ZERO
	var from_dir := from.normalized() if from.length_squared() > 0.0001 \
		else CrawlerRun.spawn_direction()
	var best := empty.duplicate()
	for raw: Variant in _quest_rows(quest_id):
		var scored := _score_unrevealed(raw, from_dir, "")
		if float(scored["dot"]) > float(best["dot"]):
			best = scored
	return best


func _bind_boss_site(site: PatchMonument, row: Dictionary) -> void:
	if site == null:
		return
	var encounter := CrawlerRun.boss_encounter(site.monument_id)
	if encounter.is_empty():
		encounter = str(row.get("encounter", CrawlerRules.BOSS_ENCOUNTER_EMPTY))
		if encounter.is_empty():
			encounter = CrawlerRules.BOSS_ENCOUNTER_EMPTY \
				if bool(row.get("empty", true)) \
				else ""
	site.encounter = encounter
	site.title = CrawlerProgress.quest_title(CrawlerProgress.QUEST_BOSS, encounter)
	if encounter == CrawlerRules.BOSS_ENCOUNTER_TREE:
		site.keepout_radius = CrawlerRules.TREE_BATTLE_RADIUS
		_ensure_tree_boss(site)


func _ensure_tree_boss(site: PatchMonument) -> void:
	if site == null or site.get_node_or_null("TreeBoss") != null:
		return
	var boss: Node = TREE_BOSS.new()
	boss.name = "TreeBoss"
	if boss.has_method(&"configure"):
		boss.call(&"configure", site.monument_id)
	site.add_child(boss)


func _score_unrevealed(raw: Variant, from_dir: Vector3, _kind: String) -> Dictionary:
	var empty := {"id": "", "dot": -2.0, "ring": 1}
	if not raw is Dictionary:
		return empty
	var row: Dictionary = raw
	var id := str(row.get("id", ""))
	if id.is_empty() or _waypoint_lit(id):
		return empty
	var facing := CrawlerRun._dir_of(row)
	if facing.length_squared() < 0.25:
		return empty
	return {
		"id": id,
		"dot": from_dir.dot(facing.normalized()),
		"ring": int(row.get("ring", 1)),
	}


func _waypoint_lit(site_id: String) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for site in CrawlerSites._collect(tree):
		if CrawlerSites._site_id(site) != site_id:
			continue
		var mark := site as Landmark
		return mark != null and mark.waypoint
	return false


func _city_matches(site_id: String, ids: PackedStringArray) -> bool:
	if ids.has(site_id):
		return true
	if site_id == CrawlerRules.CITY_SITE_ID and ids.has(CrawlerRun.first_city_id()):
		return true
	return false


func _city_node_name(city_id: String) -> String:
	if city_id == CrawlerRun.first_city_id():
		return "CrawlerCityRing"
	return "CrawlerRing_%s" % city_id


func _world() -> Node:
	return get_parent()


func _overlay() -> LandPatchOverlay:
	var world := _world()
	if world != null and world.has_method(&"_land_patches"):
		return world.call(&"_land_patches") as LandPatchOverlay
	return get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) as LandPatchOverlay \
		if get_tree() != null else null


func _clear_authored_monuments() -> void:
	var host := _monuments()
	if host == null:
		return
	for id: String in [CrawlerProgress.QUEST_TOWER, CrawlerProgress.QUEST_CASTLE]:
		var site := host.get_node_or_null(id)
		if site != null:
			site.queue_free()


func _monuments() -> PatchMonuments:
	var world := _world()
	if world is GameWorld:
		var planet := (world as GameWorld).planet()
		if planet != null:
			var host := planet.get_node_or_null("PatchMonuments") as PatchMonuments
			if host != null:
				return host
	if world != null:
		var nested := world.get_node_or_null("Planet/PatchMonuments") as PatchMonuments
		if nested != null:
			return nested
	return null
