@tool
class_name PlantSpecies
extends Resource

## One kind of plant: what it is made of, where it will grow, and how thickly.
##
## Everything a [GroundCover] needs to scatter something is here, so adding a
## second plant to the world is a new resource and a line in an array rather than
## a new script. Nothing here is per-instance — size, heading and phase are all
## decided per plant at scatter time — and nothing here is stored between runs.
##
## The split between this and the material is not arbitrary. The material owns
## the look, which is the GPU's business alone. This owns the distances, which
## both sides need: [GroundCover] decides how many instances to submit at a given
## range and [code]vivid_plant[/code] decides which of them to draw, and if those
## two curves disagree the field either draws plants the shader has faded out or
## cuts off ones it has not. So the distances live here, and [method prepare]
## pushes them into the material rather than the material being authored with
## its own copy.

## Width of the soft shoulder on the patch gate, in patch-field units. A hard
## threshold would give every stand a coastline; this is what gives it an edge
## that thins out.
const PATCH_EDGE := 0.45

## Heights between which a species takes a growing share of the view-range
## setting: nothing at the first, all of it at the second. A metre is about where
## a plant stops being a texture on the ground and starts being an object on it;
## six is a young tree, still a readable silhouette from a few hundred metres up.
const RANGE_HEIGHT_FROM := 1.0
const RANGE_HEIGHT_FULL := 6.0

## Areal density, in plants a square metre, that distance thinning will not cut
## below. Roughly one plant in a forty-metre square.
##
## Thinning exists to stop a distant ring costing more than it shows, and it is
## quoted as a share because grass is what it was written for. A tree is the
## other extreme: after its patch rule and its habitat, a canopy stands about one
## to a thirty-six-metre square, so taking the authored eighth of them away saves
## a few hundred instances and removes the only thing on the horizon with a
## readable silhouette. Below this density a species is cheap enough to keep
## whole.
const FAR_DENSITY_FLOOR := 0.0006
## Metres at which a plant is a silhouette worth streaming ahead of the viewer.
## Shorter, denser cover waits until the eye is near; trees and sparse geology
## keep the horizon readable during a fast run.
const SKYLINE_HEIGHT := 3.0

## Global feel calibration for impact destruction. Authored values still rank
## species and instance sizes against one another, but only 65% of the former
## speed is now required so ordinary sprinting can clear lighter obstacles.
const BREAK_THRESHOLD_SCALE := 0.65

## Hit points a plant carries for every metre per second it takes to run
## through it.
##
## Durability is authored once, as health, and the run-through speed is derived
## from it. The two used to be separate numbers and could disagree: a tree could
## be authored to resist a sprint and then fall to a glancing beam, because
## nothing tied the ability damage scale to the impact scale. Deriving one from
## the other means a species is tuned in one place and both answers move
## together.
##
## The constant itself is only the exchange rate between the two units and is
## not a feel knob. Every shipped species was migrated through it from its
## previous [code]break_speed[/code], so the whole existing impact table is
## reproduced exactly; changing it would retune every plant on the planet at
## once. Tune [member health] instead.
const HEALTH_PER_BREAK_SPEED := 12.0

## Share of ability damage each toughness class actually absorbs.
##
## This is the second axis, and it exists because being knocked down by a body
## and being cut by a beam are not the same test. A boulder gives way to a
## sprinting player at eight metres a second — which is authored, deliberate and
## fun — and should still shrug off a laser that fells a tree in a second. One
## number cannot say both, so health says how much punishment a thing takes and
## this says how much of a beam's punishment reaches it.
const TOUGHNESS_SHARE: Array[float] = [1.0, 0.45, 0.08, 0.06]

## Global multiplier on how far cover is drawn, from graphics/flora_range.
##
## Static because it is one player preference rather than a property of any
## plant, and because the fields have to agree about it: a species drawn by two
## GroundCovers must be thinned identically by both, and the shader is handed
## the resolved distances rather than the setting.
static var view_range := 1.0

## The .glb the meshes come out of. Read once at [method prepare] and dropped;
## nothing from the scene itself survives into the world, because a MultiMesh
## draws a [Mesh] and has no use for the nodes around it.
@export var model: PackedScene
## Optional second GLB when the far topology has its own VAT mapping.
@export var distant_model: PackedScene
## Which mesh in it to grow, and which to swap to at range. Matched on the node
## name containing this, so "Far" finds "PurpleFlowerFar". Left empty, the near
## mesh is whichever has the most surfaces and there is no distant one.
@export var mesh_named := ""
@export var distant_mesh_named := ""
@export var material: ShaderMaterial
## A separately baked far VAT cannot share uniforms with the near mesh. Left
## empty, both LODs keep using [member material].
@export var distant_material: ShaderMaterial
@export var vat: VatClip
@export var distant_vat: VatClip

@export_group("Color paint")
## External PNG sampled through the model's TEXCOORD_0. Generated biome assets
## keep COLOR_0 as their semantic/emission mask and put visible bark, leaf,
## petal, cap, rib and strata patterns here. Binding it on the species is
## intentional: GroundCover overrides the GLB material to preserve MultiMesh
## batching, so an image only embedded in the imported model would never be
## sampled at runtime.
@export var paint_texture: Texture2D
@export_range(0.0, 1.0) var paint_strength := 1.0

@export_group("Size")
## Height in metres, and the spread either side of it as a fraction. The mesh's
## own authored height is measured at load, so this is a real height and not a
## scale factor — a species can be swapped for a differently sized model without
## retuning it.
@export var height := 1.0
@export_range(0.0, 0.9) var height_variation := 0.3
## Horizontal spread relative to authored proportions. Grass tufts can cover
## ground densely without becoming ankle-high shrubs.
@export_range(0.2, 4.0) var width_scale := 1.0
## Metres to place the model origin beneath the sampled terrain. Most authored
## assets are ground-aligned and leave this at zero; rounded boulders use a small
## positive value so their curved underside sits in the soil rather than looking
## balanced on top of it. Collision receives the same instance transform.
@export_range(0.0, 10.0, 0.05, "or_greater") var ground_sink := 0.0
## A positive share supersedes the fixed sink and scales the burial with each
## generated instance's actual height. The minimum keeps player-sized stones on
## their authored base while larger rocks bridge curved terrain underground.
@export_range(0.0, 1.0, 0.01) var ground_sink_share := 0.0
@export_range(0.0, 1000.0, 0.05, "or_greater") var ground_sink_above := 0.0
## Degrees off vertical the plants are stood at, as a spread. Nothing that grew
## out of the ground is plumb, and a field of plumb ones reads as a grid however
## well its positions are scattered.
@export_range(0.0, 30.0) var tilt := 7.0

@export_group("Where it grows")
## Metres above sea level the ground has to be. This is the shore rule: on a
## shelf that slopes into the water, height above sea level is distance from it,
## and it costs one sample where measuring a coastline costs a flood fill.
@export var above_water := 12.0
## And the ceiling, which keeps a field on its shelf rather than climbing the
## bluffs behind it.
@export var below := 140.0
## Steepest ground it will stand on, in degrees.
@export_range(0.0, 60.0) var max_slope := 26.0
## Radius the ground is checked over for lumpiness, and the worst height
## difference across it that still counts as even ground. This is the test that
## keeps plants off gully lips and boulder fields — ground that is level on
## average and has nothing flat on it.
@export var steady_over := 2.2
@export var steady_within := 0.85
## Which of the terrain's four ground materials has to claim a spot before this
## species will grow on it. The terrain shader decides that per pixel from the
## biome, the slope and the frost; [GroundCover] evaluates the same rules on the
## CPU, so grass grows where the ground is drawn as grass and coral grows where
## it is drawn as sand, rather than on ground that merely looks similar.
enum Ground { ANYWHERE, GRASS, SAND, STONE, ICE }
@export var ground_layer: Ground = Ground.ANYWHERE
## How strongly that material has to be claimed, on the same 0..1 scale the
## terrain weighs its four by.
@export_range(0.0, 1.0) var minimum_claim := 0.0
## Inclusive climate band. Having both edges matters for populations such as
## cactus and glacier shards: "can tolerate desert/ice" is not the same rule as
## "only grows in desert/ice". Defaults preserve every existing species.
@export_range(0.0, 1.0) var minimum_arid := 0.0
@export_range(0.0, 1.0) var maximum_arid := 1.0
@export_range(0.0, 1.0) var minimum_frost := 0.0
@export_range(0.0, 1.0) var maximum_frost := 1.0
## Instance colour carries the sampled terrain colour into the grass shader.
@export var terrain_tint := false

@export_group("Glow")
## Share of *patches*, not blades, that glow. The same 3D noise is evaluated for
## every candidate so neighbouring tufts light together.
@export_range(0.0, 1.0) var glowing_patches := 0.0
@export var glow_patch_size := 18.0
@export var glow_seed := 20260808
## Colour cast onto nearby ground, players and props by GroundCover's bounded
## light pool. Alpha zero delegates to the field's existing fixed/region colour;
## an opaque value belongs to this species and lets one mixed field cast pink,
## blue, purple and green from the matching plants.
##
## A species does not need [member glowing_patches] to receive a light. A
## material with `night_emission_energy` is luminous too, so adding emissive
## coral (or any future night plant) automatically supplies light anchors as
## well as making its own mesh bright.
@export var local_light_color := Color(0.0, 0.0, 0.0, 0.0)
## Per-species multiplier on the GroundCover field's pooled-light energy.
@export_range(0.0, 4.0) var local_light_energy := 1.0

@export_group("How thickly")
## Plants per square metre where the ground is thick with them. The figure that
## matters for cost is this times the area inside [member draw_within], before
## thinning: at 0.15 over a 130 m circle that is eight thousand plants, of which
## the thinning draws about a quarter.
@export var per_square_metre := 0.15
## Preserve sub-candidate densities instead of rounding every tile to zero or
## one trial. Ordinary cover has many trials per tile and keeps the historical
## rounded rule. Monumental geology may expect only a fifth of a site per
## 420-metre tile, so a deterministic fractional roll is what makes "rare"
## possible without forcing one skyscraper candidate into every tile.
@export var fractional_density := false
## Plants grown together from one accepted spot, and how far they spread from
## it in metres. This is what turns scattered specimens into turf: a lawn is not
## a denser scatter of single tufts, it is clumps whose skirts overlap.
##
## It is also the whole of why dense cover is affordable. Deciding whether a
## spot will grow anything is eight height-field samples — the four neighbours
## that answer slope and lumpiness are most of it — and a clump pays that once
## for all of its members, then one sample each to sit them on the ground.
@export_range(1, 12) var clump_count := 1
@export var clump_radius := 1.0
## Re-run the complete habitat/slope/steadiness test for every member instead
## of trusting the accepted centre. Ordinary plant clumps stay within a metre
## or two and do not need this cost. Boulder sites can span hundreds of metres;
## their members must each prove that the ground under a skyscraper-scale rock
## is valid rather than inheriting a test performed on the far side of a hill.
@export var clump_resurvey := false
## Share of the ground left bare, and the size of the bare patches in metres.
## Ground cover with no gaps in it reads as a texture rather than as plants; the
## gaps are what make it look like something grew there.
##
## This is a real share: 0.75 leaves about three quarters of the candidate
## ground bare, so a species' visible count is roughly its density times the
## area inside [member draw_within] times one minus this, before thinning.
@export_range(0.0, 0.95) var bare_share := 0.42
@export var patch_size := 30.0
## The field, as a number. Change it for a different arrangement of the same
## rules. Every peer runs the same one, so no plant's position is ever sent.
@export var random_seed := 20260807

@export_group("How far")
## Past this the species is not drawn at all.
@export var draw_within := 130.0
## Where thinning starts, where it reaches the sparse distant density, and the
## share left from there to [member draw_within].
##
## A zero [member thin_to] preserves the original behaviour and stretches the
## thinning all the way to [member draw_within]. Set it explicitly on fields
## with a very large draw radius: extending the radius should add a sparse
## horizon, not stretch near-field density over the whole new circle.
@export var thin_from := 26.0
@export var thin_to := 0.0
## A floor rather than the final word: see [method far_share], which keeps a
## naturally sparse species whole however small a share this asks for.
@export_range(0.02, 1.0) var far_density := 0.13
## How much of the rank range a plant spends shrinking as its turn comes up,
## which is what keeps the far edge of the field from being a line things pop
## across.
@export_range(0.01, 0.5) var fade_band := 0.14
## Plants nearer than this cast shadows. A field of ten thousand shadow casters
## is a second pass over the whole field for something that is a speck of grey on
## grass past a few metres.
@export var shadow_within := 34.0
## Swapped to the distant mesh past here, if there is one.
@export var distant_beyond := 34.0

@export_group("Collision")
## GroundCover normally has no physics representation. Stout plants such as
## coral can opt into primitive collision, streamed only near the viewer so a
## planet-wide field does not become thousands of permanent physics shapes.
@export var collision_enabled := false
@export var collision_within := 48.0
## Primitive proportions as shares of the generated plant's actual height.
## Rocks can instead opt into a mesh-derived convex hull or exact triangle
## surface. Both remain streamed and share one authored shape per species.
enum CollisionPrimitive { CYLINDER, SPHERE, BOX, CONVEX_HULL, TRIMESH }
@export var collision_primitive: CollisionPrimitive = CollisionPrimitive.CYLINDER
@export_range(0.05, 1.5) var collision_radius_share := 0.35
@export_range(0.1, 1.0) var collision_height_share := 0.85

@export_group("Impact")
## Most collidable species remain ordinary solid obstacles. BREAKABLE species
## disappear when an impact clears their size-adjusted threshold. A
## MUSHROOM_BOUNCE breaks by the same rule and also launches the player, while
## UNBREAKABLE records the deliberate choice made for monumental variants.
enum ImpactMode { SOLID, BREAKABLE, MUSHROOM_BOUNCE, UNBREAKABLE }
@export var impact_mode: ImpactMode = ImpactMode.SOLID
## Hit points before instance size is accounted for.
##
## This is the one durability number a species is authored with. It sets how
## much ability damage the plant absorbs and, through
## [constant HEALTH_PER_BREAK_SPEED], how fast a player has to be moving to run
## straight through it. The default is the migrated form of the old twelve
## metres a second.
@export var health := 144.0
## Extra hit points for every metre of this particular instance. Instance height
## is used rather than the species average, so two differently scaled trees of
## the same variant do not have identical durability.
@export var health_per_metre := 18.0
## What kind of material an ability is cutting into. See
## [constant TOUGHNESS_SHARE]: this scales incoming ability damage only and has
## no effect on the run-through speed.
enum Toughness { SOFT, WOODY, STONE, CRYSTAL }
@export var toughness: Toughness = Toughness.SOFT
## Momentum retained on the tick a breakable obstacle gives way.
@export_range(0.0, 1.0) var break_momentum_keep := 0.82
## Mushroom launch speed is impact speed times this share, clamped to the
## authored bounds. Planet-up is supplied by the player at the contact point.
@export var bounce_up_share := 1.15
@export var bounce_min_up := 18.0
@export var bounce_max_up := 80.0
## One pooled particle service serves all species. The alpha-zero default asks
## GroundCover to use the species' local-light or instance tint before falling
## back to an earthy debris colour.
enum BreakEffect { ORGANIC, WOOD, CRYSTAL }
@export var break_effect: BreakEffect = BreakEffect.ORGANIC
@export var break_effect_color := Color(0.0, 0.0, 0.0, 0.0)

var _near: Mesh
var _far: Mesh
var _authored := 1.0
var _ready := false
var _near_material: ShaderMaterial
var _far_material: ShaderMaterial
var _mesh_collision_shape: Shape3D

## The thinning curve, resolved once for the range in force.
##
## [method keep_at] is the hottest function in the flora system by a wide margin:
## every cover field evaluates it for every tile and every species each time the
## viewer moves far enough to matter, which while flying is every frame, and
## across the planet's sixteen fields that is tens of thousands of calls a
## second. Written out it reads as five arithmetic steps, but four of them were
## method calls that each re-derived the range factor, so a single evaluation
## resolved the same handful of constants five times over. Measured flying, the
## dressing pass that does nothing but call this cost eleven milliseconds of a
## twenty-two millisecond frame.
##
## The inputs are a resource's own exported numbers and one static setting, so
## the answer only changes when the setting does. Keyed on that value rather than
## on a dirty flag, because the fields share species resources and there is no
## single owner to tell them all.
var _curve_for := -1.0
var _curve_reach := 0.0
var _curve_fade_out := 0.0
var _curve_thin_from := 0.0
var _curve_thin_to := 0.0
var _curve_far := 0.0
var _curve_near := 1.0
var _curve_factor := 1.0


## Pulls the meshes out of the model and hands the material the distances it has
## to agree with [GroundCover] about. Cheap to call again; only the first does
## anything.
func prepare() -> void:
	if _ready:
		return
	_ready = true
	if model == null:
		push_error("PlantSpecies '%s' has no model to grow" % resource_name)
		return
	var scene := model.instantiate()
	var best_surfaces := -1
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var found := (node as MeshInstance3D).mesh
		if found == null:
			continue
		if distant_mesh_named != "" and node.name.contains(distant_mesh_named):
			_far = found
			continue
		if mesh_named != "":
			if node.name.contains(mesh_named):
				_near = found
		elif found.get_surface_count() > best_surfaces:
			best_surfaces = found.get_surface_count()
			_near = found
	scene.queue_free()
	if distant_model != null:
		var far_scene := distant_model.instantiate()
		var far_vertices := -1
		for node in far_scene.find_children("*", "MeshInstance3D", true, false):
			var found := (node as MeshInstance3D).mesh
			if found == null:
				continue
			if distant_mesh_named != "" and node.name.contains(distant_mesh_named):
				_far = found
				break
			var vertices := 0
			for surface in found.get_surface_count():
				vertices += found.surface_get_array_len(surface)
			if vertices > far_vertices:
				far_vertices = vertices
				_far = found
		far_scene.queue_free()
	if _near == null:
		push_error("PlantSpecies '%s' found no mesh in its model" % resource_name)
		return
	# The shader's lever arm is a fraction of this, so it is measured rather than
	# typed: a re-export at a different size would otherwise bend the plant over
	# a height it no longer has.
	_authored = maxf(_near.get_aabb().size.y, 0.01)
	if material == null:
		return
	# Uniforms belong to a species/LOD, not to the source resource. Duplicating
	# avoids a second field retuning the first one's draw range or VAT metadata.
	_near_material = material.duplicate(true) as ShaderMaterial
	var far_source := distant_material if distant_material != null else material
	_far_material = far_source.duplicate(true) as ShaderMaterial
	_prepare_material(_near_material, vat, _near)
	_prepare_material(_far_material, distant_vat if distant_vat != null else vat,
		distant_mesh())


func _prepare_material(target: ShaderMaterial, clip: VatClip, mesh: Mesh) -> void:
	if target == null:
		return
	target.set_shader_parameter(&"stem_height", _authored)
	target.set_shader_parameter(&"far_density", far_share())
	target.set_shader_parameter(&"fade_band", fade_band)
	target.set_shader_parameter(&"color_paint_enabled", paint_texture != null)
	if paint_texture != null:
		target.set_shader_parameter(&"color_paint", paint_texture)
		target.set_shader_parameter(&"color_paint_strength", paint_strength)
	_publish_range(target)
	if clip != null:
		if clip.validate_mesh(mesh):
			clip.apply(target)


func _publish_range(target: ShaderMaterial) -> void:
	target.set_shader_parameter(&"thin_from", thin_start())
	target.set_shader_parameter(&"thin_to", thinning_end())
	target.set_shader_parameter(&"draw_within", draw_reach())


## Re-pushes the resolved distances after [member view_range] moves. The meshes
## and the VAT metadata are untouched, so this costs three uniforms per level
## rather than another [method prepare].
func refresh_view_range() -> void:
	invalidate_curve()
	if _near_material != null:
		_publish_range(_near_material)
	if _far_material != null:
		_publish_range(_far_material)


func near_mesh() -> Mesh:
	return _near


## The distant mesh, or the near one if the species was exported without a
## second level. A caller does not have to know which.
func distant_mesh() -> Mesh:
	return _far if _far != null else _near


func near_material() -> ShaderMaterial:
	return _near_material if _near_material != null else material


func far_material() -> ShaderMaterial:
	return _far_material if _far_material != null else near_material()


## Height the mesh was modelled at, in metres. Measured at [method prepare]
## rather than declared, so a re-export at a different size needs no retuning.
func authored_height() -> float:
	return _authored


## A collision surface made from the same near mesh that the MultiMesh draws.
## Horizontal species width is baked into the shared shape, leaving only the
## instance's uniform height scale on CollisionShape3D.
func mesh_collision_shape() -> Shape3D:
	if _mesh_collision_shape != null:
		return _mesh_collision_shape
	if _near == null or (collision_primitive != CollisionPrimitive.CONVEX_HULL
			and collision_primitive != CollisionPrimitive.TRIMESH):
		return null
	var points := _mesh_collision_points(
		collision_primitive == CollisionPrimitive.TRIMESH)
	if points.is_empty():
		return null
	if collision_primitive == CollisionPrimitive.TRIMESH:
		var surface := ConcavePolygonShape3D.new()
		surface.set_faces(points)
		surface.backface_collision = true
		_mesh_collision_shape = surface
	else:
		points = _convex_support_points(points)
		var hull := ConvexPolygonShape3D.new()
		hull.points = points
		_mesh_collision_shape = hull
	return _mesh_collision_shape


func _mesh_collision_points(triangles: bool) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface_index in _near.get_surface_count():
		if _near.surface_get_primitive_type(surface_index) \
				!= Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := _near.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if not triangles:
			for vertex in vertices:
				points.append(_collision_point(vertex))
			continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for vertex in vertices:
				points.append(_collision_point(vertex))
		else:
			for vertex_index in indices:
				points.append(_collision_point(vertices[vertex_index]))
	return points


func _collision_point(point: Vector3) -> Vector3:
	return Vector3(point.x * width_scale, point.y, point.z * width_scale)


## Flat-shaded GLBs duplicate a position for every face normal. Passing all of
## those copies to physics deferred expensive hull work until the first nearby
## field streamed. Support points in the 26 principal directions preserve the
## authored silhouette while keeping every shared rock hull small and stable.
func _convex_support_points(vertices: PackedVector3Array) \
		-> PackedVector3Array:
	var points := PackedVector3Array()
	for x in [-1.0, 0.0, 1.0]:
		for y in [-1.0, 0.0, 1.0]:
			for z in [-1.0, 0.0, 1.0]:
				var direction := Vector3(x, y, z)
				if direction == Vector3.ZERO:
					continue
				direction = direction.normalized()
				var best := vertices[0]
				var furthest := best.dot(direction)
				for index in range(1, vertices.size()):
					var distance := vertices[index].dot(direction)
					if distance > furthest:
						furthest = distance
						best = vertices[index]
				if not points.has(best):
					points.append(best)
	return points


## Scale to apply to the model for a plant of [param metres].
func scale_for(metres: float) -> float:
	return maxf(metres, 0.05) / _authored


## Metres this particular instance is buried below its sampled terrain point.
func ground_sink_for(metres: float) -> float:
	if ground_sink_share <= 0.0:
		return maxf(ground_sink, 0.0)
	if metres <= ground_sink_above:
		return 0.0
	return maxf(metres, 0.0) * clampf(ground_sink_share, 0.0, 1.0)


## Hit points one generated instance of this species carries.
func health_for(visual_height: float) -> float:
	return maxf(health, 0.0) \
		+ maxf(visual_height, 0.0) * maxf(health_per_metre, 0.0)


## Size-aware destruction threshold for one generated instance, in metres a
## second. Derived from [method health_for] so durability cannot be authored
## twice; see [constant HEALTH_PER_BREAK_SPEED].
func impact_threshold(visual_height: float) -> float:
	return health_for(visual_height) / HEALTH_PER_BREAK_SPEED \
		* BREAK_THRESHOLD_SCALE


## How much of an ability's raw damage this species actually absorbs.
func damage_taken(raw: float) -> float:
	if not takes_ability_damage():
		return 0.0
	var index := clampi(int(toughness), 0, TOUGHNESS_SHARE.size() - 1)
	return maxf(raw, 0.0) * TOUGHNESS_SHARE[index]


## Monumental variants are landmarks rather than obstacles: they are exempt from
## the run-through rule and from ability damage alike, so a skyline cannot be
## quietly erased. Every other mode — including the plain SOLID default that
## grass and shrubs use — can be burned and smashed.
func takes_ability_damage() -> bool:
	return impact_mode != ImpactMode.UNBREAKABLE


## Upward speed produced when this mushroom clears its break threshold.
func bounce_speed(impact_speed: float) -> float:
	return clampf(
		maxf(impact_speed, 0.0) * maxf(bounce_up_share, 0.0),
		maxf(bounce_min_up, 0.0),
		maxf(bounce_max_up, bounce_min_up))


## The share of this species still standing at a given distance, as a rank
## threshold in 0..1. The GDScript half of [code]plant_keep[/code] in
## vivid_plant.gdshader — see the class note for why there are two of it, and
## keep them equal.
func keep_at(away: float) -> float:
	if _curve_for != view_range:
		_resolve_curve()
	var thinned := lerpf(_curve_near, _curve_far,
		smoothstep(_curve_thin_from, _curve_thin_to, away))
	return thinned * (1.0 - smoothstep(_curve_reach, _curve_fade_out, away))


## Works out the distances the curve is made of, for the range now in force.
func _resolve_curve() -> void:
	_curve_factor = 1.0
	if view_range <= 1.0:
		_curve_factor = maxf(view_range, 0.1)
	else:
		_curve_factor = 1.0 + (view_range - 1.0) * clampf(
			(height - RANGE_HEIGHT_FROM)
				/ (RANGE_HEIGHT_FULL - RANGE_HEIGHT_FROM), 0.0, 1.0)
	_curve_reach = draw_within * _curve_factor
	_curve_fade_out = _curve_reach * 1.12
	_curve_near = 1.0 + fade_band
	var standing := per_square_metre * (1.0 - bare_share)
	_curve_far = far_density if standing <= 0.0 \
		else clampf(FAR_DENSITY_FLOOR / standing, far_density, 1.0)
	_curve_thin_from = minf(thin_from, _curve_reach * 0.6)
	_curve_thin_to = _curve_reach if thin_to <= thin_from \
		else clampf(thin_to * _curve_factor, _curve_thin_from + 0.01,
			_curve_reach)
	_curve_for = view_range


## Drops the resolved curve, for the harnesses that rewrite a species' density or
## distances after it has already been asked about them.
func invalidate_curve() -> void:
	_curve_for = -1.0


## Distance past which a tile can hold nothing worth drawing, and the one inside
## which it holds all of it. Handed out so [GroundCover] can skip the curve
## entirely for the tiles that are plainly on one side of it or the other, which
## while flying is most of them.
func full_within() -> float:
	if _curve_for != view_range:
		_resolve_curve()
	return _curve_thin_from


## Share kept out at the far edge, after the sparse-species floor.
##
## [member per_square_metre] is quoted before the patch field takes its cut, so
## the density this works from is that times the share of ground the patches
## actually claim. Habitat rules thin it further and are not accounted for, which
## only makes the estimate cautious.
func far_share() -> float:
	if _curve_for != view_range:
		_resolve_curve()
	return _curve_far


## Share of [member view_range] this species takes.
##
## A plant is worth drawing while it still covers a pixel, and what it covers
## goes as its height over its distance — so the range worth giving a species
## goes with its height. A slider that ignored that would be paid for almost
## entirely by grass, which is also the one thing that cannot be seen from a
## distance however far it is drawn: at twenty-eight blades a square metre, a
## quarter more radius is half again as many blades, all of them under a pixel.
## The same setting spent on trees is a populated landscape.
##
## Reductions are not weighted. Someone turning the setting down wants the frame
## back everywhere, and the field that costs the most is the grass.
func range_factor() -> float:
	if _curve_for != view_range:
		_resolve_curve()
	return _curve_factor


## Past this the species is not drawn at all, after the view-range setting.
func draw_reach() -> float:
	if _curve_for != view_range:
		_resolve_curve()
	return _curve_reach


## True for trees, monoliths and other sparse objects that still read at range.
## GroundCover streams these along the travel corridor first; grass and shrubs
## catch up closer to the viewer.
func is_skyline() -> bool:
	return height >= SKYLINE_HEIGHT or per_square_metre <= FAR_DENSITY_FLOOR


## Where thinning starts. Deliberately not scaled up: extending the range should
## add a sparse horizon, not widen the band held at full near-field density,
## which is the one change that would make the setting unaffordable.
func thin_start() -> float:
	if _curve_for != view_range:
		_resolve_curve()
	return _curve_thin_from


## Distance at which thinning has reached [member far_density]. Kept as a
## method because the CPU culling and shader must receive exactly the same
## resolved value.
func thinning_end() -> float:
	if _curve_for != view_range:
		_resolve_curve()
	return _curve_thin_to


## Level on the patch field above which this species is allowed to grow, chosen
## so that [member bare_share] of the ground really is left bare.
##
## The gate is [code]smoothstep(level, level + PATCH_EDGE, noise)[/code] on
## smooth simplex. That noise spends almost none of its area near the ends of
## its nominal -1..1 range — measured deviation is 0.231 and the widest reading
## over two hundred thousand samples is 0.80 — so reading the share straight off
## that range is not a percentage of anything. It cost the desert, ice and stone
## biomes every plant they had: a "three quarters bare" setting was rejecting
## 99.6% of candidates, and species sparse enough to matter rounded to none.
##
## Inverting the measured curve instead. A normal quantile with a deviation of
## 0.25, offset by half the smoothstep band, reproduces the sampled acceptance
## to within about a point across the whole useful range.
static func patch_level(share: float) -> float:
	return 0.25 * _normal_quantile(clampf(share, 0.001, 0.999)) - PATCH_EDGE * 0.5


## Abramowitz and Stegun 26.2.23, whose error stays under 4.5e-4 — far below the
## precision anyone can author a bare share to.
static func _normal_quantile(probability: float) -> float:
	var tail := minf(probability, 1.0 - probability)
	var t := sqrt(-2.0 * log(tail))
	var value := t - (2.515517 + 0.802853 * t + 0.010328 * t * t) \
		/ (1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t)
	return value if probability > 0.5 else -value
