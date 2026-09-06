class_name CrawlerCityRing
extends Node3D

## First crawler city. Gameplay is still the ring volume for shops, healing,
## and mob keep-out. On a planet the Neon Fjord village sits in that volume;
## tests without a planet keep the old translucent walls.

const GROUP := &"crawler_city_rings"
const VILLAGE_MODEL := "res://assets/runtime/environment/neon_fjord_village.glb"
const NIGHT_LIGHTS := preload("res://game/city/building_night_lights.gd")
const WALL_ALPHA := 0.40
const WALL_COLOUR := Color(0.07, 0.03, 0.04, WALL_ALPHA)
const SEGMENTS := 36

var patch_id := -1

var _radius := CrawlerRules.CITY_RING_RADIUS
var _height := CrawlerRules.CITY_RING_HEIGHT
var _wall := CrawlerRules.CITY_RING_WALL
var _opening := CrawlerRules.CITY_RING_OPENING
var force_village := false
var _village: Node3D


func configure(id: int, at: Transform3D) -> void:
	patch_id = id
	transform = at


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
	if not ResourceLoader.exists(VILLAGE_MODEL):
		return false
	var held := get_node_or_null("Village") as Node3D
	if held != null:
		_village = held
		NIGHT_LIGHTS.bind(held, _planet_host())
		return true
	var packed := load(VILLAGE_MODEL) as PackedScene
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
	return true


func _ensure_waypoint() -> Landmark:
	if not CrawlerRules.active():
		return null
	var planet := _planet_host()
	var mark := get_node_or_null("CrawlerWaypoint") as CrawlerSite
	if mark == null:
		mark = CrawlerSite.new()
		mark.name = "CrawlerWaypoint"
	mark.site_id = CrawlerRules.CITY_SITE_ID
	mark.title = CrawlerRules.CITY_SITE_TITLE
	mark.enter_radius = CrawlerRules.CITY_ENTER_RADIUS
	mark.hide_beyond = 0.0
	mark.show_beyond = 0.0
	mark.aimed_beyond = 0.0
	mark.clearance = 6.0
	mark.direction = world_up()
	mark.planet = planet
	if mark.get_parent() != self:
		add_child(mark)
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
