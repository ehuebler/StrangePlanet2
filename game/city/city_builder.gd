@tool
class_name CityBuilder
extends Node3D

## One town's streets in the world: finds its ground, resolves its lines, builds them,
## and puts its signs up.
##
## Parent it to the [Planet] and name the town in [member site]. It stands itself at
## that town's centre and builds everything relative to that, which keeps every vertex
## within a couple of kilometres of its own origin instead of eight thousand out at the
## planet's — a float at that distance has half a millimetre to spare, and road
## markings are not that forgiving.
##
## Almost nothing happens in here. [RoadNetwork] works out where the lines go and
## whether they make sense, [RoadMesh] turns them into triangles and colliders, and
## [Settlements] says which town is which. What is left is the wiring, and the one piece
## of judgement worth reading: the [CityPlan] this builds on is fetched from the
## [PlanetShape]'s own prepared list rather than made fresh from the layout, because the
## roads have to sit on the very pad the height field flattened. An equal copy is not
## good enough — it would be equal until somebody changed one of them.
##
## The roads are meshes rather than height field, and they have to be: a viaduct
## crosses over other streets, and a height field holds one height per direction. What
## they do share with the terrain is the ground — every station asks [CityPlan] how high
## it is and sits on it, so a street crossing a graded city slopes with it and nothing
## has to be levelled by hand.

const SURFACE: ShaderMaterial = preload("res://game/city/city_road_surface.tres")

## Which town this builds. See [Settlements].
@export var site: StringName = Settlements.LANDING
## Whether the town is built at all. Off leaves the node standing and empty rather than
## deleted, so the wiring survives being switched back on, and it takes the town's own
## waypoints down with the streets — they are signs on the thing that is not there.
##
## The pads are separate and belong to the terrain: see [member PlanetShape.settled],
## which is what decides whether the ground is flattened for a town in the first place.
@export var enabled := true
## The planet to build on. Left empty it walks up to the nearest [Planet] ancestor,
## which is where one of these belongs.
@export var planet: Planet
## Print the network's size and its audit on build. Cheap, and it is the one check that
## says the streets still join up and that no two of them are laid through each other.
@export var report := true

## The resolved lines, kept so `dev/_city_test.gd` can draw them and measure them
## without building the town twice.
var network: RoadNetwork
## Where the viaducts' legs came down, on the map. Empty for a town built on one level.
var piers: PackedVector2Array = PackedVector2Array()

var _plan: CityPlan
var _mesh: RoadMesh


func _ready() -> void:
	build()


## Clears whatever is there and lays the town out again. Safe to call from the editor,
## which is what makes a change to a layout table visible without a restart.
func build() -> void:
	for child in get_children():
		child.queue_free()
	piers.clear()
	network = null
	_mesh = null
	# After the clearing, so switching it off in the editor takes the streets down
	# rather than leaving the last build standing.
	if not enabled:
		return

	var host := planet if planet != null else _host()
	if host == null or host.shape == null:
		push_warning("CityBuilder '%s' has no planet to build on" % name)
		return
	var shape := host.shape
	# Children ready before their parents, so the planet has not prepared its own shape
	# yet. Guarded on the shape's side, so asking twice costs nothing.
	shape.prepare()
	_plan = _ground(shape)
	if _plan == null or not _plan.enabled:
		return

	position = _plan.surface_at(Vector2.ZERO)
	network = Settlements.network(site)
	if network == null:
		return
	if report:
		_report(network.audit())

	_mesh = RoadMesh.new(_plan, network, position, shape.radius)
	var view := MeshInstance3D.new()
	view.name = "Surfaces"
	view.mesh = _mesh.build()
	view.material_override = SURFACE
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(view, false, Node.INTERNAL_MODE_BACK)
	for body: StaticBody3D in _mesh.bodies():
		add_child(body, false, Node.INTERNAL_MODE_BACK)
	piers = _mesh.piers
	_raise_waypoints()


## Whether a viaduct leg of [param need] metres could stand at [param local] without a
## foot on a street. Only the harness asks; kept here because the map it reads belongs
## to the mesh and the mesh is private.
func clear_below(local: Vector2, need: float) -> bool:
	return _mesh == null or _mesh.clear_below(local, need)


## The prepared pad for this town, out of the shape's own list.
func _ground(shape: PlanetShape) -> CityPlan:
	for town: CityPlan in shape.cities:
		if town.site == site:
			return town
	push_warning("CityBuilder '%s': the planet has no town called '%s'" % [name, site])
	return null


## The town's own signs. Named nodes rather than anonymous ones, because a quest
## condition names a landmark by its node name and not by its title.
func _raise_waypoints() -> void:
	for waypoint: Dictionary in Settlements.waypoints(site):
		var mark := Landmark.new()
		mark.name = String(waypoint["name"])
		mark.title = String(waypoint["title"])
		mark.direction = _plan.direction_at(waypoint["at"] as Vector2)
		# Only what the row actually names, so [Landmark]'s own defaults stand for the
		# rest. Restating them here is how the ranges drifted apart the first time: a
		# retuned default reached every landmark in the world scene and none of these.
		#
		# `waypoint` is in the list although no settlement currently sets it. The
		# planet's hand-placed landmarks are all silent now bar Vacationer's Landing, and
		# a town switched back on would otherwise be the one way to get a marker up
		# without a say in the matter.
		for field: String in ["clearance", "tint", "show_beyond", "aimed_beyond",
				"hide_beyond", "waypoint"]:
			if waypoint.has(field):
				mark.set(field, waypoint[field])
		mark.planet = planet if planet != null else _host()
		add_child(mark, false, Node.INTERNAL_MODE_BACK)


func _host() -> Planet:
	var node := get_parent()
	while node != null:
		if node is Planet:
			return node as Planet
		node = node.get_parent()
	return null


func _report(found: Dictionary) -> void:
	print("%s: %d junctions of %d nodes, %d roads in %d runs, %.1f km of street" % [
		_plan.title, found["junctions"], found["nodes"], found["roads"],
		found["runs"], (found["length"] as float) / 1000.0])
	print("  %d nodes reachable, %d dead ends" % [
		found["reached"], (found["dead_ends"] as Array[String]).size()])
	for problem: String in found["problems"] as PackedStringArray:
		push_error("%s: %s" % [_plan.title, problem])
