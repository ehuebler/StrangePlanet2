class_name CrawlerCityRing
extends Node3D

## A crawler city ring. Gameplay is still the volume for shops, healing,
## and mob keep-out. On a planet a Neon Whimsy village sits in that volume;
## tests without a planet keep the old translucent walls. Neon Fjord is the
## default; later towns pass their own site, title, and village.

const GROUP := &"crawler_city_rings"
const VILLAGE_MODEL := "res://assets/runtime/environment/neon_fjord_village.glb"
const NIGHT_LIGHTS := preload("res://game/city/building_night_lights.gd")
const FOLK := preload("res://game/crawler/crawler_village_folk.gd")
const SIGN := preload("res://game/crawler/crawler_stall_sign.gd")
const WALL_ALPHA := 0.40
const WALL_COLOUR := Color(0.07, 0.03, 0.04, WALL_ALPHA)
const SEGMENTS := 36
const SIGN_HEIGHT := 3.4
const CRESCENT_HIDDEN := Vector3(-36.0, 0.0, 24.0)

var patch_id := -1
var site_id := CrawlerRules.CITY_SITE_ID
var site_title := CrawlerRules.CITY_SITE_TITLE
var village_model := VILLAGE_MODEL
var key_override := ""

var _radius := CrawlerRules.CITY_RING_RADIUS
var _height := CrawlerRules.CITY_RING_HEIGHT
var _wall := CrawlerRules.CITY_RING_WALL
var _opening := CrawlerRules.CITY_RING_OPENING
var force_village := false
var _village: Node3D


func configure(
		id: int,
		at: Transform3D,
		next_site := "",
		next_title := "",
		next_model := "",
		next_key := ""
	) -> void:
	patch_id = id
	transform = at
	if not next_site.is_empty():
		site_id = next_site
	if not next_title.is_empty():
		site_title = next_title
	if not next_model.is_empty():
		village_model = next_model
	if not next_key.is_empty():
		key_override = next_key


func _ready() -> void:
	add_to_group(GROUP)
	if not _attach_village():
		_build_walls()
	_ensure_waypoint()
	_register_flora()


func _exit_tree() -> void:
	BuildingFloraClear.unregister_node(self)


func _register_flora() -> void:
	var direction := global_position
	var planet_radius := 8000.0
	var walk: Node = get_parent()
	while walk != null:
		if walk is Planet:
			var planet := walk as Planet
			direction = planet.to_local(global_position)
			if planet.shape != null:
				planet_radius = planet.shape.radius
			break
		walk = walk.get_parent()
	if direction.length_squared() < 0.25:
		direction = world_up()
	var reach := _radius
	if _village != null:
		reach = maxf(reach, BuildingFloraClear.mesh_radius(_village))
	BuildingFloraClear.register(
		str(get_instance_id()), direction, reach, planet_radius)


func radius() -> float:
	return _radius


func keepout_radius() -> float:
	return _radius + CrawlerRules.CITY_SAFE_PAD


func city_extent() -> float:
	return _radius


func zone_centre() -> Vector3:
	return global_position


func world_centre() -> Vector3:
	return global_position


func world_up() -> Vector3:
	return global_transform.basis.y.normalized() \
		if is_inside_tree() else Vector3.UP


## Waist-high stand in the plaza, so the waiting ability tile is in the
## middle of the ring rather than on the wall or the doorway.
func gift_stand_transform(clearance := 0.9) -> Transform3D:
	var up := world_up()
	var forward := -global_transform.basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = global_transform.basis.x
		forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(up)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.FORWARD)
	right = right.normalized()
	return Transform3D(
		Basis(right, up, right.cross(up)).orthonormalized(),
		world_centre() + up * maxf(clearance, 0.35)
	)


func contains_point(point: Vector3) -> bool:
	var local := to_local(point) if is_inside_tree() else point
	var radial := Vector2(local.x, local.z).length()
	return radial <= _radius and local.y >= -4.0 and local.y <= _height


func blocks_near(point: Vector3) -> bool:
	var local := to_local(point) if is_inside_tree() else point
	var radial := Vector2(local.x, local.z).length()
	return radial <= keepout_radius() \
		and local.y >= -12.0 and local.y <= _height + 24.0


func blocks_point(point: Vector3) -> bool:
	return blocks_near(point)


func contains_player(player: Node) -> bool:
	return player is Node3D and contains_point((player as Node3D).global_position)


func city_key() -> String:
	if not key_override.strip_edges().is_empty():
		return key_override.strip_edges()
	return str(patch_id) if patch_id >= 0 else "city"


static func city_key_for(node: Node3D) -> String:
	if node == null or not node.is_inside_tree():
		return ""
	for zone_variant: Variant in node.get_tree().get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerCityRing
		if zone != null and zone.contains_player(node):
			return zone.city_key()
	return ""


func push_out(point: Vector3, pad := 1.2) -> Vector3:
	if not blocks_near(point):
		return point
	var local := to_local(point) if is_inside_tree() else point
	var planar := Vector3(local.x, 0.0, local.z)
	if planar.length_squared() < 0.0001:
		planar = Vector3(0.0, 0.0, 1.0)
	planar = planar.normalized() * (keepout_radius() + pad)
	local.x = planar.x
	local.z = planar.z
	return to_global(local) if is_inside_tree() else local


static func contains_any(node: Node3D) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	for zone_variant: Variant in node.get_tree().get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerCityRing
		if zone != null and zone.contains_player(node):
			return true
	return false


static func blocks_near_any(tree: SceneTree, point: Vector3) -> bool:
	if tree == null:
		return false
	for zone_variant: Variant in tree.get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerCityRing
		if zone != null and zone.blocks_near(point):
			return true
	return false


static func push_out_any(tree: SceneTree, point: Vector3, pad := 1.2) -> Vector3:
	if tree == null:
		return point
	var pushed := point
	for zone_variant: Variant in tree.get_nodes_in_group(GROUP):
		var zone := zone_variant as CrawlerCityRing
		if zone != null:
			pushed = zone.push_out(pushed, pad)
	return pushed


func _build_walls() -> void:
	var chord := 2.0 * _radius * sin(PI / float(SEGMENTS)) + 0.55
	var door_half := _opening * 0.5 / maxf(_radius, 1.0)
	var door_cos := cos(door_half)
	var bury := 3.0
	var tall := _height + bury
	for index in SEGMENTS:
		var angle := (float(index) + 0.5) * TAU / float(SEGMENTS)
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		if radial.dot(Vector3(0.0, 0.0, -1.0)) >= door_cos:
			continue
		var visual := MeshInstance3D.new()
		visual.name = "CityWall"
		var right := Vector3.UP.cross(radial)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		right = right.normalized()
		visual.basis = Basis(right, Vector3.UP, radial)
		visual.position = radial * _radius + Vector3(0.0, tall * 0.5 - bury, 0.0)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(chord, tall, _wall)
		visual.mesh = mesh
		visual.material_override = _wall_material()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(visual)


func _wall_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = WALL_COLOUR
	material.roughness = 0.92
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color("ef151f")
	material.emission_energy_multiplier = 0.18
	return material


func _attach_village() -> bool:
	if not force_village and _planet_host() == null:
		return false
	if not ResourceLoader.exists(village_model):
		return false
	var held := get_node_or_null("Village") as Node3D
	if held != null:
		_village = held
		NIGHT_LIGHTS.bind(held, _planet_host())
		_seed_folk()
		refresh_stall_signs()
		return true
	var packed := load(village_model) as PackedScene
	if packed == null:
		return false
	var body := packed.instantiate() as Node3D
	if body == null:
		return false
	body.name = "Village"
	add_child(body)
	PatchMonuments.wire_interior_collision(body)
	BuildingFoundation.seat(body, _planet_host())
	NIGHT_LIGHTS.bind(body, _planet_host())
	_village = body
	_seed_folk()
	refresh_stall_signs()
	return true


func _seed_folk() -> void:
	if _village == null or _village.get_node_or_null("VillageFolk") != null:
		return
	var folk = FOLK.new()
	_village.add_child(folk)
	folk.populate(_village, 91031 + patch_id, _hidden_local())


func _hidden_local() -> Vector3:
	if village_model == CrawlerRules.CRESCENT_VILLAGE:
		return CRESCENT_HIDDEN
	return Vector3.ZERO


func refresh_stall_signs(tries := 0) -> void:
	if _village == null or not is_inside_tree():
		if tries < 16:
			call_deferred(&"refresh_stall_signs", tries + 1)
		return
	_clear_stall_signs()
	for shop_id: String in _hours_ledger().signed_shops_for(city_key()):
		_mount_stall_sign(shop_id)


func _clear_stall_signs() -> void:
	var doomed: Array[Node] = []
	for child: Node in get_children():
		if child is CrawlerStallSign or str(child.name).begins_with("StallSign_"):
			doomed.append(child)
	if _village != null:
		for child: Node in _village.get_children():
			if child is CrawlerStallSign or str(child.name).begins_with("StallSign_"):
				doomed.append(child)
	for child: Node in doomed:
		child.free()


func _mount_stall_sign(shop_id: String) -> void:
	var anchor := _stall_anchor(shop_id)
	if anchor == null:
		return
	var tex := CrawlerShopIcons.texture_for(shop_id)
	if tex == null:
		return
	var sign = SIGN.new()
	sign.name = "StallSign_%s" % shop_id
	sign.texture = tex
	add_child(sign)
	sign.global_position = anchor.global_position + world_up() * SIGN_HEIGHT


func _stall_anchor(shop_id: String) -> Node3D:
	var mark_name := CrawlerShopIcons.stall_mark(shop_id)
	if not mark_name.is_empty():
		var found := find_child(mark_name, true, false)
		if found is Node3D:
			return found as Node3D
	var mesh_name := CrawlerShopIcons.stall_name(shop_id)
	if not mesh_name.is_empty():
		var found := find_child(mesh_name, true, false)
		if found is Node3D:
			return found as Node3D
	if _village == null:
		return null
	var mark := CrawlerVillageFolk._named_contains(_village, mark_name) as Node3D
	if mark != null:
		return mark
	return CrawlerVillageFolk._named_contains(_village, mesh_name) as Node3D


func _hours_ledger() -> CrawlerProgress:
	if is_inside_tree():
		for node_variant: Variant in get_tree().get_nodes_in_group("network_players"):
			var player := node_variant as OnlinePlayer
			if player != null and player.crawler_progress != null:
				return player.crawler_progress
	var ledger := CrawlerProgress.new()
	if not CrawlerProgress.session_payload.is_empty():
		ledger.from_dict(CrawlerProgress.session_payload)
	elif ledger.statue_seed == 0:
		ledger.statue_seed = 1
	return ledger


func village() -> Node3D:
	return _village


func _ensure_waypoint() -> Landmark:
	if not CrawlerRules.active():
		return null
	var planet := _planet_host()
	var mark := get_node_or_null("CrawlerWaypoint") as CrawlerSite
	if mark == null:
		mark = CrawlerSite.new()
		mark.name = "CrawlerWaypoint"
	mark.site_id = site_id
	mark.title = site_title
	mark.city_key = city_key()
	mark.enter_radius = CrawlerRules.CITY_ENTER_RADIUS
	mark.hide_beyond = 0.0
	mark.show_beyond = 0.0
	mark.aimed_beyond = 0.0
	mark.clearance = 6.0
	mark.direction = world_up()
	mark.planet = planet
	if mark.get_parent() != self:
		add_child(mark)
	if CrawlerRules.starts_visible(site_id):
		mark.unlock_waypoint()
	if mark.is_inside_tree() and planet != null:
		mark.place()
	return mark


func _planet_host() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		if walk is GameWorld:
			return (walk as GameWorld).planet()
		walk = walk.get_parent()
	return null
