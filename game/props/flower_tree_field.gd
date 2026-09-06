class_name FlowerTreeField
extends SurfaceAnchor

## Sparse, collidable flower trees over the grassy shelf around Vacationer's Landing.
##
## Trees do not use [GroundCover]. Grass can be one transform in a MultiMesh and
## nothing else; a tree has an independently angled flower and two collision
## shapes. This keeps the part of that framework that matters — deterministic
## scatter, the planet height field and exactly the terrain shader's grass claim
## — while drawing all trunks in one MultiMesh and all heads in a second. The
## result is two draw calls and one static body however many trees are grown.

@export var model: PackedScene
## Trunk daylight surface and the flower's night-emissive variant.
@export var material: Material
@export var head_material: Material
## Existing GroundCover whose terrain classification must agree with this field.
@export var grass_cover: NodePath
## Usually Vacationer's Landing. Trees fade in from this radius rather than trapping
## the player against a trunk at spawn.
@export var clear_of: NodePath
## Other pads and buildings that need the same tree-free working radius.
@export var additional_clear_of: Array[NodePath] = []

@export_group("Where they grow")
## Radius of the planted shelf around this anchor.
@export var spread := 850.0
@export_range(1, 512) var tree_count := 72
@export var keep_back := 58.0
@export var minimum_spacing := 34.0
@export var above_water := 8.0
@export var below := 150.0
@export_range(0.0, 45.0) var maximum_slope := 18.0
## A tree needs roots, not merely a mathematically acceptable normal. Four
## samples this far from the candidate reject ridges, spikes and gully lips.
@export var steady_over := 3.0
@export var steady_within := 1.2
@export_range(0.0, 1.0) var minimum_grass_claim := 0.02
@export var random_seed := 20260912
@export_range(10, 300) var attempts_per_tree := 100

@export_group("Size and flower angle")
## Four metres is safely more than twice every current player's standing height.
@export var minimum_height := 4.0
@export var maximum_height := 11.5
## Bias above one makes small trees common and the giants landmarks.
@export_range(0.2, 4.0) var size_bias := 1.65
## Some flowers face straight up; the rest become naturally tilted blooms.
@export_range(0.0, 1.0) var upright_share := 0.22
@export_range(0.0, 80.0) var maximum_head_tilt := 62.0
## The procedural replacement is authored level, so identity means an upward
## bloom. Keeping this exported makes future asymmetrical variants compatible.
@export var authored_head_normal := Vector3.UP

@export_group("Collision")
@export var trunk_radius := 0.78
@export var trunk_height := 7.15
@export var trunk_centre := Vector3(0.0, 3.575, 0.0)
@export var crown_radius := 4.69
@export var crown_from_pivot := Vector3(0.0, 0.48, 0.0)

@export_group("Impact")
## Hit points a colony tree carries, and what each metre of its real height
## adds. A generated tree's height feeds both the run-through threshold and its
## ability durability, so the smallest colony tree yields to a sprint while the
## tallest still needs committed flight speed.
@export var health := 144.0
@export var health_per_metre := 15.6
## Ability damage this wood absorbs. See [constant PlantSpecies.TOUGHNESS_SHARE].
@export var toughness: PlantSpecies.Toughness = PlantSpecies.Toughness.WOODY
## Resources felling one of these is worth, per metre of the tree's real height, to
## anything harvesting it on purpose. Scaled by height rather than fixed so a
## sixteen-metre trunk is worth clearing and a sapling is not, which comes out of the
## same number the field already scatters heights from.
##
## Zero means a species is not worth cutting, which is what grass will be when
## [GroundCover] grows the same field. Nothing about the tree changes when it is
## harvested rather than shot; this is only what the harvester is owed.
@export var harvest_yield := 4.6
@export_range(0.0, 1.0) var break_momentum_keep := 0.58
@export_enum("Organic", "Wood", "Crystal") var break_effect := 1
@export var break_effect_color := Color(0.92, 0.16, 0.44, 1.0)

@export_group("Night lighting")
## The heads all emit in their shader. This small pool is only the real light
## cast onto nearby players, grass, trunks, and props; its size never grows with
## the 280-tree field.
@export_range(0, 16) var night_light_limit := 8
@export var night_light_range := 50.0
@export var night_light_energy := 9.0
@export var night_light_color := Color(1.0, 0.055, 0.32, 1.0)
@export_range(0.0, 0.5) var night_light_pulse_amount := 0.13
@export var night_light_pulse_speed := 0.22
@export var night_light_retarget_interval := 0.45
## Trees farther than this many light ranges from the viewer cannot illuminate
## anything around them that the viewer can see, so they are not candidates.
@export var night_light_reach_scale := 3.5
## Whether the ground carries this field's night colour once the field itself is
## too far away to be streamed.
##
## From a few hundred metres up there are no tree meshes left to emit anything,
## so this publishes a mask built from the generated trunk transforms. It only
## speaks for trees. [GroundCover] publishes the undergrowth mask from its own
## deterministic scatter; using this field's radius for both was what painted a
## violet circle over bare ground around Vacationer's Landing.
##
## Note what is and is not sent. The shader is told where every generated crown
## stands, and nothing whatever about how it should look: its altitude law,
## colour and brightness live in the terrain material.
@export var orbital_glow := true
## Share of real crowns that light up. Kept at one because a tree that glows
## from the air and a tree that does not are indistinguishable on the ground,
## which makes any other value a lie the player can walk into; the marks stay
## legible as points at this density regardless, the field being 1.8 km across.
@export_range(0.05, 1.0) var orbital_tree_glow_share := 1.0
## Not the crown but the light around it, which is why this is much wider than
## anything the tree actually occupies. It also has to be wide in pixels or
## there is no room in the mask to fall off across, and a point with nothing to
## fall off across is the disc this used to draw.
@export var orbital_tree_spot_radius := 14.0

## Wide enough that a spot is a dozen-odd texels across at this field's size,
## which is what a falloff needs to exist in. Built once.
const ORBITAL_GLOW_MASK_SIZE := 1024
const IMPACT_OWNER_META := &"impact_break_owner"
const IMPACT_INSTANCE_META := &"impact_break_instance"
const IMPACT_HEIGHT_META := &"impact_break_height"
const IMPACT_BROKEN_META := &"impact_break_broken"

var _host: Planet
var _shape: PlanetShape
var _cover: GroundCover
var _radius := 1.0
var _spacing := 1.0
var _centre := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.FORWARD
var _keep_outs := PackedVector3Array()
var _keep_cos := 1.0
var _into_local := Transform3D.IDENTITY

var _trunk_mesh: Mesh
var _head_mesh: Mesh
var _head_pivot := Vector3(0.0, 7.0, 0.0)
var _authored_height := 16.0
var _trees: Array[Transform3D] = []
var _heads: Array[Transform3D] = []
var _trunk_stand: MultiMeshInstance3D
var _head_stand: MultiMeshInstance3D
var _tree_colliders: Array = []
var _collision_body: StaticBody3D
var _broken_trees: Dictionary = {}
## A sphere around every trunk in the colony, in this node's own space, so one
## comparison can tell an ability aimed anywhere else on the planet that it has
## nothing here. Measured once, when the trees are placed.
var _bound_centre := Vector3.ZERO
var _bound_radius := 0.0
## Ability damage a still-standing tree is carrying, by tree index. Cleared when
## the tree falls; a tree that survives keeps its scorching for the session.
var _tree_damage: Dictionary = {}
## Fellings not yet reported. See [method drain_new_breaks].
var _new_breaks := PackedInt32Array()
## Stable normalized phase/rate seeds, shared by head shader custom data and the
## matching pooled OmniLight whenever that tree is near the viewer.
var _pulse_phases := PackedFloat32Array()
var _pulse_rates := PackedFloat32Array()
var _night_lights: Array[OmniLight3D] = []
var _light_targets: Array[int] = []
var _since_light_targets := INF
## Kept alive here as well as by the material parameter. Built once from the
## generated tree transforms; no per-frame tree data is sent to the GPU.
var _orbital_tree_glow_mask: ImageTexture


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		return
	add_to_group(DamageHit.FIELD_GROUP)
	set_process(false)
	# Planet and GroundCover children ready independently. Deferring makes the
	# shared terrain classifier valid before this asks it about the first spot.
	call_deferred("_grow")


## Tells the ground where this field is and gives it the actual crown layout, so
## it can stand in for the streamed meshes from orbit.
##
## Pushed from here rather than typed into the material because this node
## already knows both numbers, and a direction written down in two places is a
## direction that goes stale the first time the colony is moved.
func _publish_orbital_glow() -> void:
	var surface := Planet.SURFACE_MATERIAL
	if surface == null:
		return
	surface.set_shader_parameter(&"flora_glow_direction", _centre)
	surface.set_shader_parameter(&"flora_glow_radius",
		spread if orbital_glow else 0.0)
	if not orbital_glow or _trees.is_empty():
		_orbital_tree_glow_mask = null
		surface.set_shader_parameter(&"flora_tree_glow_mask", null)
		return
	_orbital_tree_glow_mask = _build_orbital_tree_glow_mask()
	surface.set_shader_parameter(&"flora_tree_glow_mask",
		_orbital_tree_glow_mask)


## One red-channel mask over the field's tangent square. Every mark comes from a
## generated tree transform; only its display radius is enlarged so the crown
## remains a point after mipmapping from orbit.
##
## The falloff around each mark is baked here rather than shaped in the shader,
## because a shader can only reshape what a mask already contains and a mark a
## couple of texels wide contains no shape at all. Widening it here is what gave
## the canopy law something to be soft with.
func _build_orbital_tree_glow_mask() -> ImageTexture:
	var image := Image.create_empty(
		ORBITAL_GLOW_MASK_SIZE, ORBITAL_GLOW_MASK_SIZE,
		false, Image.FORMAT_RF)
	image.fill(Color.BLACK)
	var metres_per_pixel := spread * 2.0 / float(ORBITAL_GLOW_MASK_SIZE)
	for index in _trees.size():
		# A stable, well-dispersed subset of the actual trees. Pulse phase is
		# unrelated to placement and deterministic, so changing this share never
		# moves a point; it only includes or excludes that real crown.
		if _pulse_phases[index] > orbital_tree_glow_share:
			continue
		# `_trees` is local to this SurfaceAnchor. Multiplying by this node's
		# transform returns the exact planet-local point used during scatter.
		var point := transform * _trees[index].origin
		var at := point.normalized()
		var centre_share := maxf(at.dot(_centre), 0.0001)
		var offset := Vector2(
			at.dot(_east), at.dot(_north)) * (_radius / centre_share)
		var pixel := Vector2(
			(offset.x / (spread * 2.0) + 0.5)
				* float(ORBITAL_GLOW_MASK_SIZE - 1),
			(offset.y / (spread * 2.0) + 0.5)
				* float(ORBITAL_GLOW_MASK_SIZE - 1))

		# Larger authored trees receive slightly larger points; unrelated pulse
		# phase supplies a stable intensity variation without changing layout.
		var height := _trees[index].basis.x.length() * _authored_height
		var size := clampf(inverse_lerp(
			minimum_height, maximum_height, height), 0.0, 1.0)
		var radius_pixels := orbital_tree_spot_radius \
			* lerpf(0.75, 1.2, size) / metres_per_pixel
		var reach := ceili(radius_pixels)
		var intensity := lerpf(0.68, 1.0, _pulse_rates[index])
		var centre_x := roundi(pixel.x)
		var centre_y := roundi(pixel.y)
		for y in range(centre_y - reach, centre_y + reach + 1):
			if y < 0 or y >= ORBITAL_GLOW_MASK_SIZE:
				continue
			for x in range(centre_x - reach, centre_x + reach + 1):
				if x < 0 or x >= ORBITAL_GLOW_MASK_SIZE:
					continue
				var away := Vector2(float(x), float(y)).distance_to(pixel)
				if away > radius_pixels:
					continue
				# Brightest exactly at the trunk and falling the whole way out,
				# with no plateau anywhere in it. A flat middle is what made
				# these read as discs cut out of the ground rather than as
				# lights standing on it, and no amount of shaping in the shader
				# could put back a falloff the mask never had. Squared, so most
				# of the light sits in a small core and the rest is a long dim
				# skirt -- the shape of a lamp seen through air.
				var fade := 1.0 - away / radius_pixels
				var radial := fade * fade
				# Summed rather than kept: a stand of trees close together
				# pools into one brighter patch, which is what a stand of
				# lights actually does.
				var existing := image.get_pixel(x, y).r
				image.set_pixel(x, y, Color(
					minf(existing + radial * intensity, 1.0), 0.0, 0.0, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _grow() -> void:
	_host = planet_host()
	_cover = get_node_or_null(grass_cover) as GroundCover
	if _host == null or _host.shape == null or _cover == null:
		push_error("FlowerTreeField needs a Planet and its grass GroundCover")
		return
	if model == null or material == null:
		push_error("FlowerTreeField is missing its model or material")
		return
	_shape = _host.shape
	_shape.prepare()
	_radius = _shape.radius
	_spacing = _host.finest_spacing()
	_centre = direction.normalized()
	_east = _centre.cross(Vector3.UP if absf(_centre.y) < 0.9
		else Vector3.RIGHT).normalized()
	_north = _centre.cross(_east).normalized()
	_keep_outs.clear()
	var clear_paths: Array[NodePath] = [clear_of]
	clear_paths.append_array(additional_clear_of)
	for path in clear_paths:
		var anchor := get_node_or_null(path) as SurfaceAnchor
		if anchor != null:
			_keep_outs.append(anchor.direction.normalized())
	if _keep_outs.is_empty():
		_keep_outs.append(_centre)
	_keep_cos = cos(keep_back / _radius)
	_into_local = transform.affine_inverse()
	if not _read_model():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var occupied := PackedVector3Array()
	var attempts := tree_count * attempts_per_tree
	for _attempt in attempts:
		if _trees.size() >= tree_count:
			break
		var spin := rng.randf() * TAU
		var reach := sqrt(rng.randf()) * spread
		var offset := Vector2(cos(spin), sin(spin)) * reach
		var at := (_centre
			+ (_east * offset.x + _north * offset.y) / _radius).normalized()
		if _inside_clearance(at):
			continue
		var ground := _ground(at)
		if is_nan(ground):
			continue
		var point := at * (_radius + ground)
		var separate := true
		for other in occupied:
			if point.distance_squared_to(other) < minimum_spacing * minimum_spacing:
				separate = false
				break
		if not separate:
			continue

		var target_height := lerpf(minimum_height, maximum_height,
			pow(rng.randf(), size_bias))
		var scale := target_height / maxf(_authored_height, 0.01)
		var stood_planet := Transform3D(
			(Basis(at, rng.randf() * TAU) * _upright(at))
				.scaled(Vector3.ONE * scale),
			point)
		var stood := _into_local * stood_planet
		var head := stood * Transform3D(_head_rotation(rng), _head_pivot)
		_trees.append(stood)
		_heads.append(head)
		occupied.append(point)

	if _trees.is_empty():
		push_warning("FlowerTreeField found no grassy ground around its anchor")
		return
	if _trees.size() < tree_count:
		push_warning("FlowerTreeField grew %d of %d requested trees"
			% [_trees.size(), tree_count])
	_measure_bounds()
	# Use a separate generator so adding pulse art direction never changes the
	# established deterministic tree layout.
	var pulse_rng := RandomNumberGenerator.new()
	pulse_rng.seed = random_seed ^ 0x4F1B29A7
	for _tree in _trees:
		_pulse_phases.append(pulse_rng.randf())
		_pulse_rates.append(pulse_rng.randf())
	_publish_orbital_glow()
	_trunk_stand = _raise_multimesh(
		"FlowerTreeTrunks", _trunk_mesh, _trees, material)
	_head_stand = _raise_multimesh("FlowerTreeHeads", _head_mesh, _heads,
		head_material if head_material != null else material)
	_raise_collision()
	_raise_night_lights()
	set_process(not _night_lights.is_empty())


## Extract the two meshes and the authored hinge from the generated GLB. The
## scene itself is discarded; instances live only as MultiMesh transforms.
func _read_model() -> bool:
	var scene := model.instantiate() as Node3D
	if scene == null:
		push_error("flower_tree.glb did not instantiate a Node3D")
		return false
	var pivot := scene.find_child("FlowerTreeHeadPivot", true, false) as Node3D
	var trunk := scene.find_child("FlowerTreeTrunk", true, false) as MeshInstance3D
	var head := scene.find_child("FlowerTreeHead", true, false) as MeshInstance3D
	if pivot == null or trunk == null or head == null:
		scene.queue_free()
		push_error("flower_tree.glb is missing its trunk, head, or head pivot")
		return false
	_trunk_mesh = trunk.mesh
	_head_mesh = head.mesh
	# Imported GLBs may add a wrapper root. Read the pivot through its local
	# ancestors, not from global_transform: this temporary scene is deliberately
	# never added to the tree, where a global transform would be invalid.
	var pivot_transform := Transform3D.IDENTITY
	var cursor: Node3D = pivot
	while cursor != null and cursor != scene:
		pivot_transform = cursor.transform * pivot_transform
		cursor = cursor.get_parent_node_3d()
	_head_pivot = pivot_transform.origin
	_authored_height = maxf(
		_trunk_mesh.get_aabb().end.y,
		_head_pivot.y + _head_mesh.get_aabb().end.y)
	scene.queue_free()
	return _trunk_mesh != null and _head_mesh != null


func _raise_multimesh(node_name: String, mesh: Mesh,
		transforms: Array[Transform3D],
		surface: Material) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.instance_count = transforms.size()
	multimesh.mesh = mesh
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_custom_data(index, Color(
			_pulse_phases[index], _pulse_rates[index], 0.0, 0.0))
	# The field curves down around its anchor and the terrain can climb well
	# above it. A generous stable bound is cheaper than recalculating one and
	# prevents the whole two-call forest disappearing at a frustum edge.
	multimesh.custom_aabb = AABB(
		Vector3(-spread - maximum_height, -250.0, -spread - maximum_height),
		Vector3((spread + maximum_height) * 2.0, 500.0,
			(spread + maximum_height) * 2.0))
	var stand := MultiMeshInstance3D.new()
	stand.name = node_name
	stand.multimesh = multimesh
	stand.material_override = surface
	stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	stand.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# These transforms are static except for an impact hiding one tree. Retaining
	# a second interpolation buffer for both forest MultiMeshes buys no motion.
	stand.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(stand, false, Node.INTERNAL_MODE_BACK)
	return stand


## One body with two shared primitive shapes per tree. Primitive collision is
## deliberate: a 7k-triangle concave crown copied seventy times would cost more
## physics memory than both visual MultiMeshes and would feel worse to collide
## with than a smooth crown.
func _raise_collision() -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = trunk_radius
	trunk.height = trunk_height
	var crown := SphereShape3D.new()
	crown.radius = crown_radius
	var body := StaticBody3D.new()
	body.name = "FlowerTreeCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	_tree_colliders.resize(_trees.size())
	for index in _trees.size():
		var visual_height := _trees[index].basis.y.length() * _authored_height
		var colliders: Array[CollisionShape3D] = []
		var trunk_collider := CollisionShape3D.new()
		trunk_collider.name = "Trunk%d" % index
		trunk_collider.shape = trunk
		trunk_collider.transform = _trees[index] \
			* Transform3D(Basis.IDENTITY, trunk_centre)
		_tag_impact_collider(trunk_collider, index, visual_height)
		body.add_child(trunk_collider)
		colliders.append(trunk_collider)

		var crown_collider := CollisionShape3D.new()
		crown_collider.name = "Crown%d" % index
		crown_collider.shape = crown
		crown_collider.transform = _heads[index] \
			* Transform3D(Basis.IDENTITY, crown_from_pivot)
		_tag_impact_collider(crown_collider, index, visual_height)
		body.add_child(crown_collider)
		colliders.append(crown_collider)
		_tree_colliders[index] = colliders
	_collision_body = body
	add_child(body, false, Node.INTERNAL_MODE_BACK)


func _tag_impact_collider(collider: CollisionShape3D, index: int,
		visual_height: float) -> void:
	collider.set_meta(IMPACT_OWNER_META, self)
	collider.set_meta(IMPACT_INSTANCE_META, index)
	collider.set_meta(IMPACT_HEIGHT_META, visual_height)


## Player-facing impact contract shared with GroundCover. The two fields use
## different storage, but OnlinePlayer should not have to know which one drew
## the plant it touched.
func resolve_flora_impact(collider: CollisionShape3D, impact_speed: float,
		at: Vector3) -> Dictionary:
	if collider == null or collider.get_meta(IMPACT_OWNER_META, null) != self:
		return {}
	var index := int(collider.get_meta(IMPACT_INSTANCE_META, -1))
	if index < 0 or index >= _trees.size():
		return {}
	var visual_height := float(collider.get_meta(
		IMPACT_HEIGHT_META, maximum_height))
	if impact_speed < impact_threshold(visual_height):
		return {}
	var answer := {
		"handled": true,
		"broken": false,
		"momentum_keep": break_momentum_keep,
		"bounce_up": 0.0,
	}
	if _broken_trees.has(index):
		return answer
	_fell(index, at, impact_speed, visual_height)
	answer["broken"] = true
	return answer


## Hit points one generated tree carries.
func health_for(visual_height: float) -> float:
	return maxf(health, 0.0) \
		+ maxf(visual_height, 0.0) * maxf(health_per_metre, 0.0)


## Speed needed to run straight through one tree, derived from its health so a
## colony tree is tuned in one place like every [PlantSpecies].
##
## Deliberately without [constant PlantSpecies.BREAK_THRESHOLD_SCALE]. These
## trees never had it: their threshold was always the raw sum, and the sprint
## allowance the constant grants was tuned against streamed cover rather than
## against sixteen-metre trunks standing over the colony.
func impact_threshold(visual_height: float) -> float:
	return health_for(visual_height) / PlantSpecies.HEALTH_PER_BREAK_SPEED


## The one body that owns every trunk and crown shape. See
## [method GroundCover.collision_rids].
func collision_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if is_instance_valid(_collision_body):
		rids.append(_collision_body.get_rid())
	return rids


## Ability damage contract, shared with [GroundCover] through
## [constant DamageHit.FIELD_GROUP]. Trees inside the volume take their share
## and fall when it exceeds their health.
func apply_damage(hit: DamageHit) -> float:
	if hit == null or _trees.is_empty():
		return 0.0
	var to_world := global_transform
	# The colony against the volume, once, before any tree is looked at. A
	# colony is under a kilometre across on an eight-kilometre planet, so almost
	# every volume offered to it is somewhere else entirely and this is the only
	# line that runs.
	if not hit.reaches(to_world * _bound_centre, _bound_radius):
		return 0.0
	# A volume that spares the canopy spares a colony of sixteen-metre trees
	# outright, and knowing that costs one comparison against the shortest tree
	# the colony can hold.
	if hit.max_plant_height > 0.0 and minimum_height > hit.max_plant_height:
		return 0.0
	if maximum_height < hit.min_plant_height:
		return 0.0
	var absorbed := 0.0
	var centre := _host.global_position if _host != null else Vector3.ZERO
	# The volume's axis taken apart, and the furthest a trunk may be rooted from
	# it and still have any part of itself inside. The colony is a few thousand
	# trees and an ability touches a handful, so the loop below is really a
	# rejection test with a felling routine hanging off it; everything that can
	# be hoisted out of the rejection is.
	var from := hit.origin
	var along := hit.toward - from
	var span := along.length_squared()
	# Every trunk is scaled to a height drawn between the two exported bounds,
	# so the tallest one the colony can contain is known without asking any of
	# them. Generous by a factor of two, since the highest point tested below is
	# the crown at half height.
	var reach := hit.radius + maximum_height
	var reach_squared := reach * reach
	for index in _trees.size():
		if _broken_trees.has(index):
			continue
		var root := to_world * _trees[index].origin
		var offset := root - from
		var closest := offset
		if span > 0.000001:
			closest = offset - along * clampf(offset.dot(along) / span, 0.0, 1.0)
		if closest.length_squared() >= reach_squared:
			continue
		var visual_height := _trees[index].basis.y.length() * _authored_height
		if hit.max_plant_height > 0.0 \
				and visual_height > hit.max_plant_height:
			continue
		if visual_height < hit.min_plant_height:
			continue
		# Also measured at the crown. A beam level with the flowers is over the
		# root by the whole height of the trunk, and testing the root alone made
		# a sixteen-metre tree immune to anything not aimed at its feet.
		var up := (root - centre).normalized()
		var middle := root + up * (visual_height * 0.5)
		var share := maxf(hit.share_at(root), hit.share_at(middle))
		if share <= 0.0:
			continue
		var taken := _damage_taken(hit.amount * share)
		if taken <= 0.0:
			continue
		absorbed += taken
		var carried := float(_tree_damage.get(index, 0.0)) + taken
		if carried < health_for(visual_height):
			_tree_damage[index] = carried
			continue
		_tree_damage.erase(index)
		_fell(index, middle, hit.amount * share, visual_height,
			hit.plant_break_effects)
	return absorbed


## Fits [member _bound_centre] and [member _bound_radius] around the placed
## trunks. Grown by the tallest a tree may be, because what has to be inside the
## sphere is the whole tree and what is measured is where it is rooted.
func _measure_bounds() -> void:
	var lowest := Vector3.INF
	var highest := -Vector3.INF
	for stood: Transform3D in _trees:
		lowest = lowest.min(stood.origin)
		highest = highest.max(stood.origin)
	_bound_centre = (lowest + highest) * 0.5
	_bound_radius = (highest - lowest).length() * 0.5 + maximum_height


func _damage_taken(raw: float) -> float:
	var index := clampi(int(toughness), 0,
		PlantSpecies.TOUGHNESS_SHARE.size() - 1)
	return maxf(raw, 0.0) * PlantSpecies.TOUGHNESS_SHARE[index]


## The one place a tree comes down, whichever spent its health. Keeping both
## routes here is what stops a laser-felled tree from leaving its collider
## standing while a rammed one does not.
## A colony holds tens of trees rather than the tens of thousands of blades a
## ground cover does, so [param bursts] is never here for what it saves — it is
## here so that one hit cannot be answered with fragments by one field and
## silently by the other.
func _fell(index: int, at: Vector3, strength: float,
		visual_height: float, bursts := true) -> void:
	_broken_trees[index] = true
	_new_breaks.append(index)
	if _trunk_stand != null:
		_trunk_stand.multimesh.set_instance_transform(
			index, _hidden(_trees[index]))
	if _head_stand != null:
		_head_stand.multimesh.set_instance_transform(
			index, _hidden(_heads[index]))
	for shape in _tree_colliders[index]:
		if not is_instance_valid(shape):
			continue
		shape.set_meta(IMPACT_BROKEN_META, true)
		shape.set_deferred(&"disabled", true)
	if not bursts:
		return
	var root := to_global(_trees[index].origin)
	var up := (root - _host.global_position).normalized() \
		if _host != null else global_basis.y
	var effects := get_tree().get_first_node_in_group(&"impact_break_effects")
	if effects != null and effects.has_method(&"play_break"):
		effects.call(&"play_break",
			at if at.is_finite() else root,
			up, strength, visual_height, break_effect_color, break_effect)


## Every tree still standing within [param radius] of a world point, as the world
## position it is rooted at and the height it grew to.
##
## Packed four to a vector — position in `xyz`, height in `w` — because the caller
## wants both together and neither an array of dictionaries nor two parallel returns
## is worth the allocation.
##
## Answered for whoever is felling trees on purpose rather than by accident.
## It is answerable at all because this field is
## not streamed: every tree is placed once and kept, so work can be planned
## against trees that no player is anywhere near. [GroundCover] cannot promise that —
## its tiles exist only around a viewer — which is why this is the field mining
## starts with rather than the one with the most in it.
func standing_near(centre: Vector3, radius: float) -> PackedVector4Array:
	var found := PackedVector4Array()
	if _trees.is_empty() or radius <= 0.0 or not centre.is_finite():
		return found
	var to_world := global_transform
	# The colony against the sphere once, before any tree is looked at. The same
	# rejection [method apply_damage] opens with, and for the same reason.
	if (to_world * _bound_centre).distance_to(centre) > radius + _bound_radius:
		return found
	var reach := radius * radius
	for index in _trees.size():
		if _broken_trees.has(index):
			continue
		var root := to_world * _trees[index].origin
		if root.distance_squared_to(centre) > reach:
			continue
		found.push_back(Vector4(root.x, root.y, root.z,
			_trees[index].basis.y.length() * _authored_height))
	return found


## What felling one of these is worth to whoever cut it down, by the tree's real
## height. Means nothing to this field; it is the one number a harvester needs and
## the tree is the thing that knows it.
func harvest_value(visual_height: float) -> float:
	return maxf(harvest_yield, 0.0) * maxf(visual_height, 0.0)


## The trees felled since this was last asked, forgetting them as it answers.
## Drained on every peer; only the host does anything with the answer.
func drain_new_breaks() -> PackedInt32Array:
	var keys := _new_breaks
	_new_breaks = PackedInt32Array()
	return keys


## Which trees this field has lost, for the host's authoritative snapshot.
func broken_keys() -> PackedInt32Array:
	var keys := PackedInt32Array()
	for index in _broken_trees:
		keys.append(int(index))
	return keys


## Applies a set of breaks decided elsewhere — a late joiner catching up with
## the host, or a peer confirming what a remote ability felled.
func apply_broken_keys(keys: PackedInt32Array) -> void:
	for index in keys:
		if index < 0 or index >= _trees.size() or _broken_trees.has(index):
			continue
		_tree_damage.erase(index)
		var visual_height := _trees[index].basis.y.length() * _authored_height
		_fell(index, Vector3.INF, 0.0, visual_height)


## Stands every tree this colony lost inside a sphere back up, and reports how
## many came back. The colony's layout is placed once and kept, so a felled tree
## is restored to the transform it was scattered with rather than regrown
## somewhere new. See [method GroundCover.restore_within].
func restore_within(centre: Vector3, radius: float) -> int:
	if _broken_trees.is_empty() or radius <= 0.0 or not centre.is_finite():
		return 0
	var to_world := global_transform
	var restored := 0
	var restored_indices := {}
	for index_key: Variant in _broken_trees.keys():
		var index := int(index_key)
		if index < 0 or index >= _trees.size():
			continue
		if (to_world * _trees[index].origin).distance_to(centre) > radius:
			continue
		_broken_trees.erase(index)
		_tree_damage.erase(index)
		if _trunk_stand != null:
			_trunk_stand.multimesh.set_instance_transform(index, _trees[index])
		if _head_stand != null:
			_head_stand.multimesh.set_instance_transform(index, _heads[index])
		for shape in _tree_colliders[index]:
			if not is_instance_valid(shape):
				continue
			shape.set_meta(IMPACT_BROKEN_META, false)
			shape.set_deferred(&"disabled", false)
		restored_indices[index] = true
		restored += 1
	if restored > 0 and not _new_breaks.is_empty():
		# Do not let the world's next reconciliation broadcast fellings that
		# happened just before this reset. Those keys describe an older encounter
		# and would immediately knock the restored trees back down on clients.
		var pending := PackedInt32Array()
		for index in _new_breaks:
			if not restored_indices.has(index):
				pending.append(index)
		_new_breaks = pending
	return restored


func _hidden(stood: Transform3D) -> Transform3D:
	# A truly singular basis is rejected. Five-decimal scale is visually zero
	# even on the largest authored crown and remains a valid transform.
	return Transform3D(
		stood.basis.scaled(Vector3.ONE * 0.00001), stood.origin)


## Allocate once after the field is grown. Lights remain shadowless: their job
## is coloured fill cast onto nearby surfaces, while the sun continues to own
## the stable large-scale shadows.
func _raise_night_lights() -> void:
	for index in night_light_limit:
		var light := OmniLight3D.new()
		light.name = "FlowerTreeGlow%d" % index
		light.light_color = night_light_color
		light.light_energy = 0.0
		light.light_specular = 0.65
		light.omni_range = night_light_range
		# Linear-ish falloff rather than the sharper default curve, so the pool
		# is still delivering light by the time it has fallen from the crown to
		# the grass underneath.
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light, false, Node.INTERNAL_MODE_BACK)
		_night_lights.append(light)
		_light_targets.append(-1)


func _process(delta: float) -> void:
	if _night_lights.is_empty() or _host == null:
		return
	_since_light_targets += delta
	if _since_light_targets >= night_light_retarget_interval:
		_since_light_targets = 0.0
		_choose_light_targets()
	_update_night_lights(delta)


## Pick the nearest heads, but preserve the slot of every head that remains in
## the chosen set. Without that small assignment step, two trees exchanging
## nearest-order would make both pool lights fade and relocate unnecessarily.
func _choose_light_targets() -> void:
	var eye := _host.to_global(_host.viewer_position())
	var reach := night_light_range * night_light_reach_scale
	var candidates: Array[Vector2] = []
	for index in _heads.size():
		if _broken_trees.has(index):
			continue
		var point := _tree_light_position(index)
		var away := eye.distance_squared_to(point)
		if away <= reach * reach:
			candidates.append(Vector2(away, float(index)))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.x < b.x)

	var remaining: Array[int] = []
	for index in mini(candidates.size(), _night_lights.size()):
		remaining.append(int(candidates[index].y))
	for slot in _light_targets.size():
		var current := _light_targets[slot]
		if current >= 0 and remaining.has(current):
			remaining.erase(current)
		else:
			_light_targets[slot] = -1
	for slot in _light_targets.size():
		if _light_targets[slot] < 0 and not remaining.is_empty():
			_light_targets[slot] = remaining.pop_front()


func _update_night_lights(delta: float) -> void:
	var step := delta * night_light_energy * 3.0
	var seconds := float(Time.get_ticks_msec()) * 0.001
	for slot in _night_lights.size():
		var light := _night_lights[slot]
		var tree := _light_targets[slot]
		var target := _tree_light_position(tree) if tree >= 0 else Vector3.INF
		var arrived := target.is_finite() \
			and light.global_position.distance_squared_to(target) < 0.01
		var toward := 0.0
		if arrived:
			var pulse := 1.0 + night_light_pulse_amount * sin(
				seconds * TAU * night_light_pulse_speed
					* lerpf(0.82, 1.18, _pulse_rates[tree])
				+ _pulse_phases[tree] * TAU)
			toward = night_light_energy * _night_at(target) * pulse
		light.light_energy = move_toward(light.light_energy, toward, step)
		light.visible = light.light_energy > 0.001
		if not arrived and light.light_energy <= 0.001 and target.is_finite():
			light.global_position = target
			light.light_color = night_light_color


func _tree_light_position(index: int) -> Vector3:
	if index < 0 or index >= _heads.size() or _broken_trees.has(index):
		return Vector3.INF
	var centre := (_heads[index] \
		* Transform3D(Basis.IDENTITY, crown_from_pivot)).origin
	return to_global(centre)


## Keep the physical light on the same sunset curve as vivid_surface.
func _night_at(at: Vector3) -> float:
	if _host.sun == null:
		return 0.0
	var up := (at - _host.global_position).normalized()
	var to_sun := _host.sun.global_basis.z.normalized()
	return 1.0 - smoothstep(-0.16, 0.12, up.dot(to_sun))


## Rotate the authored face normal into a generated tilt. Whole-tree yaw already
## turns that bending plane to a random compass direction.
func _head_rotation(rng: RandomNumberGenerator) -> Basis:
	var tilt := 0.0 if rng.randf() < upright_share \
		else deg_to_rad(rng.randf_range(7.0, maximum_head_tilt))
	var base := authored_head_normal.normalized()
	var horizontal := Vector3(base.x, 0.0, base.z).normalized()
	if horizontal.is_zero_approx():
		horizontal = Vector3.FORWARD
	var wanted := (Vector3.UP * cos(tilt) + horizontal * sin(tilt)).normalized()
	return _turn_between(base, wanted)


func _turn_between(from: Vector3, to: Vector3) -> Basis:
	var first := from.normalized()
	var second := to.normalized()
	var cosine := clampf(first.dot(second), -1.0, 1.0)
	if cosine > 0.99999:
		return Basis.IDENTITY
	var axis := first.cross(second)
	if axis.is_zero_approx():
		axis = first.cross(Vector3.RIGHT if absf(first.x) < 0.9
			else Vector3.FORWARD)
	return Basis(axis.normalized(), acos(cosine))


func _inside_clearance(at: Vector3) -> bool:
	if PatchCity.flora_covers(at):
		return true
	for keep_out in _keep_outs:
		if at.dot(keep_out) >= _keep_cos:
			return true
	return false


func hide_under_city() -> void:
	if _trees.is_empty() or _host == null:
		return
	for index in _trees.size():
		if _broken_trees.has(index):
			continue
		var world := to_global(_trees[index].origin)
		var local := _host.to_local(world)
		if local.length_squared() < 1.0:
			continue
		if not PatchCity.flora_covers(local.normalized()):
			continue
		var visual_height := _trees[index].basis.y.length() * _authored_height
		_fell(index, world, 0.0, visual_height, false)


## A suitable root patch. This mirrors GroundCover's slope/lumpiness check and
## then asks that node's public terrain classifier whether the terrain shader
## paints grass here, so trees and grass cannot disagree at biome boundaries.
func _ground(at: Vector3) -> float:
	var here := _shape.elevation(at, _spacing)
	if here < above_water or here > below:
		return NAN
	var wet := _shape.sample(at)
	if float(wet.get("river", 0.0)) > 0.0 or float(wet.get("lake", 0.0)) > 0.0:
		return NAN
	var east := at.cross(Vector3.UP if absf(at.y) < 0.9
		else Vector3.RIGHT).normalized()
	var north := at.cross(east)
	var step := steady_over / _radius
	var behind := _shape.elevation((at - east * step).normalized(), _spacing)
	var ahead := _shape.elevation((at + east * step).normalized(), _spacing)
	var left := _shape.elevation((at - north * step).normalized(), _spacing)
	var right := _shape.elevation((at + north * step).normalized(), _spacing)
	for near: float in [behind, ahead, left, right]:
		if near < above_water or near > below \
				or absf(near - here) > steady_within:
			return NAN
	var run := steady_over * 2.0
	var gradient := Vector2(ahead - behind, right - left) / run
	if gradient.length() > tan(deg_to_rad(maximum_slope)):
		return NAN
	var normal := (at - east * gradient.x - north * gradient.y).normalized()
	var biome := _shape.color_at(at, here, normal)
	if not _cover.terrain_claims(at, here, normal, biome,
			PlantSpecies.Ground.GRASS, minimum_grass_claim):
		return NAN
	return here


func grown() -> int:
	return _trees.size()
