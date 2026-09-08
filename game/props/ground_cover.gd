@tool
class_name GroundCover
extends SurfaceAnchor

## Plants, by the tens of thousands, growing over a stretch of the planet.
##
## The thing this exists to avoid is a node per plant. A flower as a scene is a
## Node3D, a MeshInstance3D, a draw call and a script the engine has to visit
## every frame, and none of those costs go away for the plant being small. A
## hundred of them is affordable and was what the first field cost; ten thousand
## is not affordable at any of them.
##
## So the field is built the way the terrain under it is built, and out of the
## same three ideas:
##
## - **One draw call for a whole tile.** A [MultiMesh] holds a few hundred
##   transforms and is submitted once, so the cost of a plant is a matrix and
##   its triangles rather than a node. There are no plant objects on the CPU at
##   all — no positions to iterate, nothing to visit per frame.
## - **Tiles are streamed, not stored.** The ground is cut into squares and a
##   square is grown when the viewer comes near it and thrown away when they
##   leave. What is in memory is what is in front of you. Growing one is a
##   thread pool task, the same pool and the same nearest-first order the chunk
##   meshes use, because the work is the same work: sample the height field a
##   few hundred times and hand back a buffer.
## - **Nothing is saved and nothing is sent.** A tile is a pure function of its
##   own coordinates, the species' seed and the height field, all of which every
##   peer already has. The field is identical on every machine without a byte
##   crossing the wire, and reseeding is the only way to change it.
##
## Distance is answered twice over, and the two halves are the interesting part.
## The shader gives every plant a rank and draws only the low ranks at range, so
## a field thins out with distance instead of ending at a line — and because
## thinning is a function of distance alone, this node can evaluate the same
## curve per tile and simply not submit the instances that would fail it. See
## [method PlantSpecies.keep_at]. The result is that a tile on the horizon costs
## a tenth of what it costs underfoot, on both sides of the bus.
##
## Streaming is not a full circle past the player's feet. A short keep-circle
## stays grown in every direction so a snap-turn still has plants around the
## body. Outside that, tiles are only grown and drawn in a look cone, with a
## little extra length reserved for preload so the next stretch is already
## sowing as the viewer walks into it.
##
## What is left for the CPU each frame is four positions published as shader
## globals so the plants know who is walking through them. Tile distances are
## refreshed only after meaningful viewer movement; sub-metre camera drift
## cannot visibly change a thinning curve tens of metres wide.

## What grows here. Several species share the ground: each is scattered
## independently over the same tiles with its own density, rules and seed, so a
## meadow is two or three of these rather than one resource that has to describe
## all of it.
@export var species: Array[PlantSpecies] = []
## Ignore [member spread] and stream stable cube-sphere tiles around the viewer
## wherever they travel. Used by planet-wide grass; localized flower meadows
## keep the tangent grid below.
@export var global_cover := false
## Radius of the ground planted, in metres from this node's own place.
@export var spread := 420.0
## Metres to a side of one tile. The trade is per-tile overhead against
## granularity: small tiles mean more nodes and more thread tasks, large ones
## mean a coarser distance for the thinning to work from and a bigger hitch when
## one arrives. Two or three plants' draw distance divided by four is about
## right. Grown with graphics/flora_range so a longer view does not turn into a
## quadratic pile of tiles.
@export var tile_size := 34.0
## Something the field should leave a gap around — a landmark, a building — as a
## node path, and how wide the gap is. Measured between the two anchors'
## [member SurfaceAnchor.direction] values rather than their placed positions,
## so it does not matter which readies first.
@export var clear_of: NodePath
## Further authored sites that use the same clearance and soft return.
@export var additional_clear_of: Array[NodePath] = []
@export var keep_back := 30.0
## And how far past that the field takes to come back to full thickness, as a
## multiple of the gap. A hard edge is worse than no gap at all: bare ground
## inside a clean circle reads as something having been cleared, and a prop with
## a mown ring round it is the one arrangement nobody would mistake for having
## grown that way.
@export_range(1.0, 4.0) var keep_back_fade := 2.1

@export_group("Weather")
## Degrees the wind blows toward, measured about this node's own up. Published
## as a world direction for every plant on the planet, not just this field: one
## gust crosses everything it crosses.
@export_range(-180.0, 180.0) var wind_heading := 35.0:
	set(value):
		wind_heading = value
		if is_inside_tree():
			_publish_wind()
@export_range(0.0, 3.0) var wind_strength := 1.0:
	set(value):
		wind_strength = value
		if is_inside_tree():
			_publish_wind()

@export_group("Walkers")
## How far from someone the plants start leaning away, in metres.
@export var push_reach := 2.6
## Seconds the lean takes to arrive and to go again.
##
## There is no per-plant state to ease — the bend is a function of where the
## walker is, evaluated in the vertex shader — so what is smoothed is the walker.
## The point the plants are pushed by chases the player at this rate instead of
## being them, which comes out as a field that bends as you arrive and stands
## back up behind you, and costs one lerp a frame rather than one per plant.
@export var push_lag := 0.34

@export_group("Glow lighting")
## Emission is per blade; these few pooled lights are only the illumination cast
## onto nearby ground. Ten is a hard cap regardless of how much grass exists.
@export_range(0, 10) var glow_light_limit := 6
@export var glow_light_range := 8.0
@export var glow_light_energy := 1.35
## Height above the root at which the pooled light sits. Grass wants a light
## among its tips; knee-high flowers want one inside the bloom.
@export var glow_light_height := 0.25
## Region colour preserves the existing luminous-grass behavior. A species can
## turn it off and provide a fixed colour, such as the colony flowers' dark
## ultraviolet purple.
@export var glow_light_use_region_color := true
@export var glow_light_color := Color.WHITE
## Night-only pools stay allocated during the day but fade to zero energy, so
## sunset never has to create nodes or compile a new light configuration.
@export var glow_light_night_only := false
## Small, target-position-derived pulses. The position is the seed, so two
## patches do not beat together and a streamed patch keeps the same rhythm when
## it returns.
@export_range(0.0, 0.5) var glow_light_pulse_amount := 0.0
@export var glow_light_pulse_speed := 0.3

@export_group("Aerial glow")
## Hands this localized field to the terrain once the streamed plants themselves
## are too far away to draw.
##
## This is deliberately generated from [method _scatter], not from [member
## spread]. A radius says where a field was allowed to grow; it does not say
## where the patch mask, terrain layer, slope, water, clearance and seeded
## candidate tests actually let it grow. Using the radius was what drew a violet
## circle around Vacationer's Landing over bare ground.
##
## Every luminous species in this field contributes automatically: a species is
## luminous when it has glowing patches or its material has night emission.
## Adding another lit GroundCover species therefore uses its own placement rules
## without adding another aerial approximation.
##
## Global cover needs a planet-wide atlas rather than this tangent mask. Kept
## explicit rather than silently baking an arbitrary patch of a global field.
@export var aerial_glow := false
## The mask is a density field, not a picture of individual flowers. At 256 a
## 430 m meadow has 3.5 m texels before mipmapping, already much finer than a
## wash seen from forty metres up while staying cheap enough to build once.
@export_range(64, 512, 64) var aerial_glow_mask_size := 256
## Metres over which nearby accepted plants pool into one undergrowth glow.
## Positions remain the real generated positions; this only describes how their
## light spreads after it reaches the ground.
@export var aerial_glow_blur_radius := 12.0

@export_group("Streaming")
## Tiles handed to the thread pool at once, and applied to the scene per frame.
## Applying is the main-thread half — a MultiMesh upload — so it is the one that
## shows up as a hitch.
@export_range(1, 8) var pending_limit := 3
@export_range(1, 4) var applies_per_frame := 1
## Seconds between surveys of which tiles should exist. Off the frame loop
## because the answer only changes when the viewer has crossed a good part of a
## tile, and the survey is the one part of this that scales with the area.
@export var survey_interval := 0.35
## Seconds of travel flora is sown ahead of the viewer, and the metre cap on
## that preview. Used by trees and other skyline species so a fast run still
## sees trunks on the corridor. Grass and shrubs stay on a near disk until the
## viewer slows down.
@export_range(0.0, 2.0, 0.05) var lead_time := 1.0
@export_range(0.0, 600.0, 10.0) var lead_distance := 280.0

@export_group("Editor")
## Grows the field in the editor as well as in the game. Off by default: the
## terrain is worth having in the editor because things are placed against it,
## and ten thousand flowers are not.
@export var editor_preview := false

## Floats per instance in a MultiMesh buffer: transform, instance colour, custom
## data. Colour is white for ordinary plants and the sampled biome tint for
## grass. Custom carries rank, VAT/gust phase, stiffness-or-glow and tone.
const STRIDE := 20
const COLOR := 12
const RANK := 16
const LOCAL_FACE := 6
## Glowing spots remembered per tile. Six lights serve the whole field, so a
## tile only has to offer a few well-spread candidates for the nearest of them.
const GLOW_ANCHORS := 6
## Shared metadata contract read by OnlinePlayer after move_and_slide. The
## collider itself owns the stable streamed-instance identity; no per-plant
## script or node is needed.
const IMPACT_OWNER_META := &"impact_break_owner"
const IMPACT_CELL_META := &"impact_break_cell"
const IMPACT_SPECIES_META := &"impact_break_species"
const IMPACT_INSTANCE_META := &"impact_break_instance"
const IMPACT_HEIGHT_META := &"impact_break_height"
const IMPACT_BROKEN_META := &"impact_break_broken"
## Sentinel stored in place of accumulated damage once a plant is gone. A
## destroyed instance and a badly burned one live in the same ledger, because
## the tile has to replay both when it comes back and walking a second
## dictionary to find out which is which is how the two get out of step.
const BROKEN := -1.0
## How dark a plant can get and still be standing. Short of black, so a burned
## survivor still reads as its own species rather than as a silhouette.
const MAX_CHAR := 0.82
## Damage tests take one up vector for a whole tile rather than one per plant.
## Across a tile on a planet this size that is worth a fraction of a degree, and
## this is the share of its own height a plant is allowed to lean by before the
## tests stop trusting it.
const UP_APPROXIMATION := 0.05
## How long the view-range setting has to hold still before the field is rebuilt
## around it.
const REPLANT_SETTLE := 0.4
## The distance curves span tens or hundreds of metres. Re-evaluating every
## stand for a camera move smaller than this cannot change a visible rank, but
## doing it in every one of the planet's cover fields every frame is measurable.
const DRESS_STEP := 0.75
## Passes a field takes to walk all of its tiles.
##
## Dressing is triggered by distance rather than by time, so spreading it costs
## metres and not frames: a tile is looked at once every DRESS_SLICES passes, and
## a pass only happens once the viewer has moved DRESS_STEP, which bounds how
## stale any tile's thinning, level of detail, shadow or collision decision can
## be at three metres of travel however fast the viewer is going. Every
## threshold those decisions turn on is measured in tens of metres.
##
## What this buys is the difference between touching every tile on the planet
## every frame and touching a quarter of them. Flying, that walk was eight
## milliseconds of a seventeen millisecond frame, and nearly all of it was spent
## re-deciding tiles hundreds of metres away that had not changed.
const DRESS_SLICES := 4
## Tiles a field may hold before its squares are grown to suit its reach.
##
## A tile is never free. It is a dictionary entry, a survey candidate, a worker
## job, up to one MultiMesh per species, a node in the tree, and a distance
## evaluation every time the viewer moves far enough to matter. 180 kept
## long-reach trees on ~34 m squares — a 7–8 tile radius that resurveyed every
## few metres at speed. 48 puts a 260 m tree field on ~66 m squares, so the
## live ring is two or three tiles and generation is not re-armed by a step.
## Authored grass and reef squares stay as written when they already fit.
const TILE_BUDGET := 48
## Near plants stay in every direction so a quick turn is not bare ground.
## Past this, only the look cone is grown and drawn.
const KEEP_CIRCLE_MIN := 24.0
const KEEP_CIRCLE_MAX := 52.0
const KEEP_CIRCLE_SHARE := 0.28
## Half-angle of the drawn cone, and the slightly wider one used to hold tiles
## already grown so a small glance does not rebuild the ring.
const VIEW_CONE_COS := 0.6157
const VIEW_CONE_KEEP_COS := 0.4384
## Extra metres past draw reach sown inside the cone, not drawn until the eye
## gets closer. Skyline species use this; grass does not while the viewer is
## rushing.
const STREAM_PAD := 36.0
## How far fill species (grass, shrubs, coral) may stream while the viewer is
## moving fast. Trees keep the full look cone and travel corridor; this is only
## the near disk the small stuff is allowed to spend budget on.
const FILL_STREAM_METRES := 56.0
## Lead length that counts as a rush. Below this, fill is allowed to catch up.
const RUSH_LEAD := 36.0
## Grass, flowers, shrubs and other short cover. Off while that layer is baked
## onto finest terrain chunks; trees and other skyline species still stream.
static var stream_fill := false
## Shared main-thread tokens across every GroundCover on the planet. Thirteen
## fields each applying one MultiMesh used to stack into a 7 ms hitch; one
## budget is what a frame can actually afford.
const FRAME_SURVEYS := 1
const FRAME_APPLIES := 2
const FRAME_SOWS := 4
const FRAME_DROPS := 8
const IDLE_SURVEYS := 2
const IDLE_APPLIES := 2
const IDLE_SOWS := 6
const IDLE_DROPS := 12
const LOOK_SURVEY_DOT := 0.93
const LOOK_DRESS_DOT := 0.97
## Densities a tile may be sown at, as shares of the species' full one.
##
## Most of a field is far away — a ring's area is nearly all outer ring — and at
## distance the thinning curve hides all but a few per cent of what was planted.
## Sowing every tile at full density therefore spends almost all of the worker
## pool's time placing plants that are hidden the moment they arrive, which is
## the noise a machine makes flying over ground it has not seen before.
##
## Sowing less is only safe because the placement is already a random
## permutation: [method _scatter] accepts candidates in a random order and ranks
## them by it, so the first tenth of a tile's buffer is a tenth of the tile
## spread evenly across it. Stopping early therefore yields exactly the plants
## the thinning would have kept, and running the same tile again at a finer band
## re-draws the identical prefix and appends the rest. Nothing that is already
## standing moves, so approaching a tile grows plants in between the ones there
## rather than replacing the lot.
const DETAIL_BANDS: Array[float] = [0.0, 0.0625, 0.125, 0.25, 0.5, 1.0]

## One square of ground and everything growing on it.
## One damage volume reduced to what the per-plant loop needs, and put into this
## field's own space. Built once per [method apply_damage] and read by every
## stand the volume touches.
class Sweep extends RefCounted:
	var from := Vector3.ZERO
	var along := Vector3.ZERO
	var radius := 1.0
	var to_world := Transform3D.IDENTITY
	var into_local := Basis.IDENTITY
	var centre := Vector3.ZERO


class Tile extends RefCounted:
	var cell: Vector3i
	## Middle of the square in world metres, and how far the viewer is from it.
	var at := Vector3.ZERO
	var away := INF
	## Perpendicular metres to the viewer's travel path. Dispatch and re-sow
	## read this so a tile on the track is grown at the density it will need
	## when arrived at, not the coarse band of being two hundred metres out.
	var path_away := INF
	## One MultiMesh per species, in the same order as [member species]. Empty
	## until the tile has been applied; a species that grew nothing on this tile
	## gets a null rather than an empty stand.
	var stands: Array = []
	## Optional nearby physics, aligned with [member stands]. Coral uses one
	## StaticBody per tile/species and one cheap primitive per visible plant.
	var collisions: Array = []
	## What the thread produced, dropped once it has been uploaded.
	var buffers: Array[PackedFloat32Array] = []
	## What each stand is currently drawing, aligned with [member stands] and
	## kept on this side of the rendering server. See [method _rows_of]: reading
	## it back out of the MultiMesh instead costs half a millisecond of waiting
	## per stand, whoever is asking and however few plants they are asking
	## about, and a volume dragged along the ground asks tens of times a tick.
	##
	## Written only by [method _raise] and by the damage paths, both on the main
	## thread, which is why this is not [member buffers]: that one is filled by
	## a worker while the tile it belongs to may still be standing and taking
	## hits.
	var rows: Array[PackedFloat32Array] = []
	## Where every plant of each species is rooted, in this node's own space,
	## aligned with [member stands].
	##
	## Kept for the same reason [member glow_points] is: [member MultiMesh.buffer]
	## hands out a copy through the rendering server, and an ability asking a
	## dozen stands "is anything of yours inside this volume" paid a millisecond
	## in round trips to find out that almost none of them were. Nothing ever
	## moves a plant that is already standing — breaking one zeroes its basis and
	## leaves its origin alone — so this stays true until the tile is re-sown,
	## which rebuilds it.
	var roots: Array[PackedVector3Array] = []
	## A handful of well-separated spots on this tile where the glow mask is
	## strong, in this node's local space, picked while the tile was being sown.
	##
	## Kept because the alternative is reading the answer back out of the
	## MultiMesh: [member MultiMesh.buffer] hands out a copy, and at this
	## instance count a sweep of the field for glowing plants is megabytes of
	## copying on the main thread, which is exactly the periodic hitch you feel
	## while walking.
	var glow_points := PackedVector3Array()
	var glow_levels := PackedFloat32Array()
	## Species owning each point, so a mixed reef casts the colour of the coral
	## actually rooted there rather than one field-wide tint.
	var glow_species := PackedInt32Array()
	## Filled on the sow worker; published to glow_* on the main thread.
	var sow_glow_points := PackedVector3Array()
	var sow_glow_levels := PackedFloat32Array()
	var sow_glow_species := PackedInt32Array()
	## Share of each species' full density this tile was last sown at, in the
	## same order as [member species]. Read back when deciding how much of the
	## buffer to show, because a tile sown at an eighth is already thinned and
	## must not be thinned by the distance a second time.
	var detail := PackedFloat32Array()
	## Which dressing pass looks at this tile, and whether it has to be looked at
	## by the next one whatever pass that is. A tile that has just been raised is
	## drawing every plant it holds with no shadow or collision decision made
	## about it yet, so it cannot wait its turn.
	var slice := 0
	var fresh := true
	var queued := false
	var grown := false

## The one set of walker positions, shared by every field on the planet: they
## are published as global shader parameters, so the second field to do it a
## frame would only be overwriting the first with the same answer.
static var _pushed_frame := -1
static var _pushed := {}
static var _looked_frame := -1
static var _shared_look := Vector3.ZERO
static var _budget_frame := -1
static var _survey_left := 0
static var _apply_left := 0
static var _sow_left := 0

var _shape: PlanetShape
var _radius := 1.0
var _spacing := 1.0
var _centre := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.FORWARD
var _into_local := Transform3D.IDENTITY
## Cosines of the angles the clearance and the far side of its fade subtend, so
## the test is a dot product rather than an arc cosine per candidate. The fade's
## is the smaller of the two: further round the sphere is a smaller dot.
var _keep_outs := PackedVector3Array()
var _keep_cos := 1.0
var _keep_edge := 1.0
var _block_centres := PackedVector3Array()
var _block_coss := PackedFloat32Array()
## Patch mask per species, one field each so two species do not grow in and out
## of the same patches.
var _patches: Array[FastNoiseLite] = []
var _glows: Array[FastNoiseLite] = []
var _reach := 0.0
## Seconds left before a range change is acted on, or a negative when there is
## no change waiting.
var _replant_in := -1.0
## Tile side actually in use. [member tile_size] is the authored side at the
## shipped range; this is that grown to suit graphics/flora_range.
var _tile := 0.0
var _grid: SphericalCoverGrid

var _tiles := {}
## The same tiles as a flat list, for the one caller that reads all of them
## several times a second. Walking the dictionary means a hash lookup per tile,
## and an ability offers its volume to every field on the planet — a few
## thousand tiles between them — for every tick it lasts.
var _tile_list: Array[Tile] = []
var _tile_list_stale := true
## Live collision bodies, for beams that must pass through flora in one ray
## instead of piercing trunks one at a time. Rebuilt when a tile dresses or
## retires physics, not every query.
var _collision_rids: Array[RID] = []
var _collision_rids_stale := true
## Session-local state over deterministic placement. Keys are tile cells, then
## species indices, then instance indices; the value is the ability damage that
## instance is carrying, or [constant BROKEN]. It deliberately survives ordinary
## tile retirement so a plant cannot regrow, or un-burn, by walking away and
## back.
var _instance_damage: Dictionary = {}
## Breaks not yet reported, in the flattened form [method broken_keys] uses.
## Drained by the world a few times a second; see [method drain_new_breaks].
var _new_breaks := PackedInt32Array()
## Tallest plant this field can grow, in metres. Only used to widen the cheap
## per-tile rejection in [method apply_damage] so a beam level with a canopy is
## not discarded because the tile's centre is on the ground far below it.
var _tallest := 0.0
## Shortest species this field grows, by authored height. A volume that spares
## anything above a given height can turn a field of nothing but trees away
## whole, before a single tile of it is looked at.
var _shortest := INF
## Stable tile keys rejected by the species' shared height band. This prevents a
## reef field from spending worker jobs proving that inland grassland is not
## eight metres under water (and grass from doing the inverse over open sea).
var _barren := {}
var _height_floor := INF
var _height_ceiling := -INF
var _height_margin := 0.0
var _wanted: Array[Vector3i] = []
var _pending := {}
var _finished: Array[Tile] = []
## True only while the wanted set may still contain an unqueued tile. Without
## this, every settled field linearly rescanned its whole ring every frame just
## to rediscover that there was no work.
var _dispatch_needed := true
## How far along the nearest-first wanted set the dispatcher has already looked.
## [member _wanted] is ordered by distance when it is built, so everything before
## this is queued, grown or gone and never needs looking at again until the next
## survey rebuilds the order.
var _dispatch_from := 0
var _has_skyline := false
var _has_fill := false
var _since_survey := INF
var _surveyed_at := Vector3.INF
## Predicted point the last survey was aimed at. A heading change can move the
## corridor a tile's width without the eye itself crossing that far.
var _surveyed_ahead := Vector3.INF
## World-space travel corridor, taken from the planet's smoothed drift so every
## field agrees with the terrain about where the viewer is going.
var _lead_direction := Vector3.ZERO
var _lead_length := 0.0
var _look_dir := Vector3.ZERO
var _surveyed_look := Vector3.ZERO
var _dressed_look := Vector3.ZERO
## Last eye position whose thinning, LOD, shadow and collision rings were
## applied. New stands invalidate it so they are dressed on their first frame.
var _dressed_at := Vector3.INF
## Which of [constant DRESS_SLICES] the next dressing pass walks, and the slice
## the next new tile is handed. Tiles are dealt round robin as they are created
## so that neighbours, which arrive together, do not all land in one pass.
var _dress_slice := 0
var _next_slice := 0
var _since_lights := INF
var _glow_lights: Array[OmniLight3D] = []
var _glow_targets: Array[Vector3] = []
var _glow_levels: Array[float] = []
## Quadrant colour at each target. The blades calculate it per pixel; the pooled
## lights need the CPU twin so the ground they illuminate is not always purple.
var _glow_colors: Array[Color] = []
## The aerial build runs on the same worker pool as streamed tiles. It is built
## once from every deterministic tile in this localized field, then only the
## texture survives.
var _aerial_glow_task := -1
var _aerial_glow_image: Image
var _aerial_glow_texture: ImageTexture
var _aerial_glow_species := PackedInt32Array()
## Every GroundCover species with shader night emission. Shared by nearby light
## placement and the optional aerial mask, neither of which should require a
## second opt-in after a material has already declared itself luminous.
var _night_species := PackedInt32Array()
var _aerial_glow_radius := 0.0


func _ready() -> void:
	super()
	if Engine.is_editor_hint() and not editor_preview:
		set_process(false)
		return
	# Joined before the planet check below, so a misconfigured field still
	# answers an ability's sweep with "nothing here" rather than being invisible
	# to it. Membership is what abilities search; they hold no field paths.
	add_to_group(DamageHit.FIELD_GROUP)
	var host := planet_host()
	if host == null or host.shape == null:
		push_warning("GroundCover '%s' has no planet to grow on" % name)
		set_process(false)
		return
	_shape = host.shape
	_shape.prepare()
	_radius = _shape.radius
	_spacing = host.finest_spacing()
	_follow_view_range()
	_resize_tiles()
	if global_cover:
		_grid = SphericalCoverGrid.new(_radius, _tile)
	_centre = direction.normalized()
	_east = _centre.cross(Vector3.UP if absf(_centre.y) < 0.9 else Vector3.RIGHT).normalized()
	_north = _centre.cross(_east)
	_into_local = global_transform.affine_inverse() * host.global_transform
	_prepare_clearance()
	# One entry per species and in the same order, nulls included: everything
	# downstream indexes the two arrays together.
	var growing := 0
	for plant in species:
		if plant == null:
			_patches.append(null)
			_glows.append(null)
			continue
		plant.prepare()
		if _has_night_emission(plant):
			# One patch entry is appended for every preceding species,
			# including nulls, so its current size is this species' index.
			_night_species.append(_patches.size())
		_height_floor = minf(_height_floor, plant.above_water)
		_height_ceiling = maxf(_height_ceiling, plant.below)
		# Furthest a valid slope can move across half a tile, plus the local
		# lumpiness allowance. If all five tile samples miss this expanded band,
		# no point inside can pass the species' own slope/steadiness rules.
		_height_margin = maxf(_height_margin,
			_tile * 0.71 * tan(deg_to_rad(plant.max_slope))
				+ plant.steady_within)
		var patch := FastNoiseLite.new()
		patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		patch.seed = plant.random_seed
		patch.frequency = 1.0 / maxf(plant.patch_size, 1.0)
		_patches.append(patch)
		var glow := FastNoiseLite.new()
		glow.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		glow.seed = plant.glow_seed
		glow.frequency = 1.0 / maxf(plant.glow_patch_size, 1.0)
		_glows.append(glow)
		_reach = maxf(_reach, plant.draw_reach())
		_tallest = maxf(_tallest, plant.height * (1.0 + plant.height_variation))
		_shortest = minf(_shortest, plant.height)
		growing += 1
	_classify_species()
	_publish_wind()
	_prepare_aerial_glow()
	_apply_stream_mode(growing > 0)


## Tile side for the range currently in force.
##
## Tile count goes with the square of the reach, and every tile is a dictionary
## entry, a survey candidate and up to one MultiMesh per species. Left alone, a
## three-times range would ask for nine times the tiles and the setting would be
## paid for in bookkeeping rather than in plants. Growing the side by the root
## of the reach splits the difference: tiles still get finer relative to the
## field as it grows, but their number rises linearly rather than quadratically.
func _resize_tiles() -> void:
	var growth := 1.0
	var reach := 0.0
	for plant in species:
		if plant == null:
			continue
		growth = maxf(growth, plant.range_factor())
		reach = maxf(reach, plant.draw_reach())
	_tile = tile_size * sqrt(growth)
	# A localized field stops at its own edge however far its species would
	# otherwise be drawn, so budgeting for the species' reach would hand it
	# squares far larger than the ground it covers.
	if not global_cover:
		reach = minf(reach, spread)
	if reach > 0.0:
		# The side that fits TILE_BUDGET squares inside the circle actually
		# drawn. Taken as a floor rather than an answer: a field already inside
		# its budget keeps the size it was authored with.
		_tile = maxf(_tile, reach * sqrt(PI / float(TILE_BUDGET)))


## Picks up graphics/flora_range and keeps following it.
##
## Read here rather than applied by [GameSettingsManager], for the reason the
## planet reads its own render distance: the manager starts with the game and
## the fields arrive with the map. Absent in the editor and in harnesses that
## stand a field up on their own, both of which want the scene's baseline.
func _follow_view_range() -> void:
	var settings := get_node_or_null("/root/SettingsManager") as GameSettingsManager
	if settings == null:
		return
	PlantSpecies.view_range = float(
		settings.get_setting(&"graphics", &"flora_range", 1.0))
	settings.settings_changed.connect(
		func(section: StringName, key: StringName, value: Variant) -> void:
			if section == &"graphics" and key == &"flora_range":
				PlantSpecies.view_range = float(value)
				# Dragging the slider announces every step it passes through.
				# Replanting on each one would rebuild the field a dozen times
				# on the way to the value the player wanted, so the last word
				# within the settle window is the one acted on.
				_replant_in = REPLANT_SETTLE)


## Starts the field again at a new range.
##
## Every placement is a function of its tile, and the tiles themselves change
## size with the range, so there is no honest way to keep the standing ones: a
## plant would move as the slider did. Dropping the field and re-surveying costs
## a second or two of repopulating, which is the same wait as walking into new
## country.
func _replant() -> void:
	for task in _pending:
		WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	_finished.clear()
	for tile: Tile in _tiles.values():
		for stand in tile.stands:
			if is_instance_valid(stand):
				stand.queue_free()
		for body in tile.collisions:
			if is_instance_valid(body):
				body.queue_free()
	_tiles.clear()
	_tile_list.clear()
	_tile_list_stale = false
	# A range change changes tile size, and therefore both cell and instance
	# identity. Keeping the old overlay would hide unrelated plants in the new
	# layout; this is the one streaming operation that intentionally resets it.
	_instance_damage.clear()
	_wanted.clear()
	_dispatch_needed = true
	_dispatch_from = 0
	_barren.clear()
	_reach = 0.0
	_tallest = 0.0
	_height_margin = 0.0
	_dressed_at = Vector3.INF
	_surveyed_look = Vector3.ZERO
	_dressed_look = Vector3.ZERO
	_resize_tiles()
	if global_cover:
		_grid = SphericalCoverGrid.new(_radius, _tile)
	for plant in species:
		if plant == null:
			continue
		plant.refresh_view_range()
		_height_margin = maxf(_height_margin,
			_tile * 0.71 * tan(deg_to_rad(plant.max_slope))
				+ plant.steady_within)
		_reach = maxf(_reach, plant.draw_reach())
		_tallest = maxf(_tallest, plant.height * (1.0 + plant.height_variation))
		_shortest = minf(_shortest, plant.height)
	_classify_species()
	var growing := false
	for plant in species:
		if plant != null:
			growing = true
			break
	_apply_stream_mode(growing)
	_since_survey = INF
	_surveyed_at = Vector3.INF
	_surveyed_ahead = Vector3.INF


func _exit_tree() -> void:
	# Tasks read this node's shape and its tangent frame, so none may outlive it.
	for task in _pending:
		WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	if _aerial_glow_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_aerial_glow_task)
		_aerial_glow_task = -1
	_finished.clear()


## Instances currently submitted, across every tile and species. The only honest
## measure of the field: what the rules produced and the thinning kept, rather
## than what was asked for.
func grown() -> int:
	var standing := 0
	for tile: Tile in _tiles.values():
		for stand in tile.stands:
			if is_instance_valid(stand):
				standing += stand.multimesh.visible_instance_count
	return standing


## Instances built and held, drawn or not. The gap between this and [method
## grown] is what the distance thinning is saving.
func planted() -> int:
	var standing := 0
	for tile: Tile in _tiles.values():
		for stand in tile.stands:
			if is_instance_valid(stand):
				standing += stand.multimesh.instance_count
	return standing


## Submitted instances grouped by species. This is a balancing/diagnostic API;
## gameplay remains deliberately unaware of individual streamed plants.
func grown_by_species() -> Dictionary:
	var standing := {}
	for entry in species:
		var plant := entry as PlantSpecies
		if plant != null:
			standing[plant.resource_name] = 0
	for tile: Tile in _tiles.values():
		for index in tile.stands.size():
			var stand := _stand_of(tile, index)
			var plant := species[index] as PlantSpecies
			if stand == null or plant == null:
				continue
			var visible := stand.multimesh.visible_instance_count
			if visible < 0:
				visible = stand.multimesh.instance_count
			standing[plant.resource_name] = int(
				standing.get(plant.resource_name, 0)) + visible
	return standing


func tiles() -> int:
	return _tiles.size()


## Tiles that should exist and do not yet, on the pool or waiting to be applied.
## Zero is the field having caught up with where the viewer is standing.
func settling() -> int:
	var waiting := 0
	for cell: Vector3i in _wanted:
		var tile := _tiles.get(cell) as Tile
		if tile != null and not tile.grown:
			waiting += 1
	return waiting


## Every plant currently built, as a global transform: the origin is where it
## stands and the scale is how big it grew. There are no plant nodes to walk —
## a MultiMesh buffer is the only record of the field there is — so this unpacks
## them, which is a harness's business and nothing else's.
func standing() -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	for tile: Tile in _tiles.values():
		for species_index in tile.stands.size():
			var stand := _stand_of(tile, species_index)
			if stand == null:
				continue
			var buffer := _rows_of(tile, species_index, stand.multimesh)
			for index in stand.multimesh.instance_count:
				found.append(stand.global_transform
					* _instance_transform(buffer, index))
	return found


## The same diagnostic view as [method standing], grouped by species. Keeping
## identity here lets biome harnesses prove that a loaded object is outside a
## forbidden climate rather than mistaking a visible object beyond the biome
## boundary for one growing inside it.
func standing_by_species() -> Dictionary:
	var found := {}
	for entry: PlantSpecies in species:
		if entry != null:
			found[entry.resource_name] = []
	for tile: Tile in _tiles.values():
		for species_index in tile.stands.size():
			var stand := _stand_of(tile, species_index)
			var plant := species[species_index] as PlantSpecies
			if stand == null or plant == null:
				continue
			var instances: Array = found[plant.resource_name]
			var buffer := _rows_of(tile, species_index, stand.multimesh)
			for instance_index in stand.multimesh.instance_count:
				instances.append(stand.global_transform
					* _instance_transform(buffer, instance_index))
	return found


## Main-thread microseconds spent in each streaming phase, summed across every
## field on the planet since it was last read. Diagnostic only: the phases are
## cheap enough individually that only their total across sixteen fields tells
## you anything, and that total is not visible from inside any one of them.
static var phase_cost := {}


## Charges the time since [param from] to a phase and returns the new mark.
static func _charge(phase: StringName, from: int) -> int:
	var now := Time.get_ticks_usec()
	phase_cost[phase] = int(phase_cost.get(phase, 0)) + (now - from)
	return now


func _report_lag() -> void:
	pass


func _process(delta: float) -> void:
	_finish_aerial_glow()
	if _replant_in >= 0.0:
		_replant_in -= delta
		if _replant_in < 0.0:
			_replant()
	var host := planet_host()
	if host == null:
		return
	if not _session_allows_stream():
		return
	var eye := host.to_global(host.viewer_position())
	_publish_walkers(delta)

	_since_survey += delta
	_since_lights += delta
	_follow_lead(host)
	_follow_look(eye)
	# Sixteen skyline fields used to survey, dress and report every frame. At
	# speed only a quarter of them do the grid walk; the rest still drain the
	# worker pool so trees keep arriving on the track.
	var rush := _rushing()
	var heavy := true
	if rush and _surveyed_at.is_finite():
		heavy = int(Engine.get_process_frames() % 4) == int(get_instance_id() % 4)
	if not heavy:
		if _dispatch_needed or not _pending.is_empty() or not _finished.is_empty():
			_dispatch(eye)
			_apply()
		if not _glow_lights.is_empty():
			_fade_glow_lights(delta)
		return
	# Both throttled and movement-driven. The previous OR surveyed every field on
	# its timer while the viewer stood still, even though the answer cannot
	# change; four independent cover fields then produced a steady cadence of
	# main-thread grid walks. A third of a tile is still early enough to grow the
	# next ring before a walking viewer reaches it. A heading or look change
	# moves the corridor the same way a step does, so that is a survey too.
	var step := _tile * _tile * 0.1
	var ahead := eye + _lead_direction * _lead_length
	var moved_to_new_ground := _surveyed_at.distance_squared_to(eye) > step \
		or _surveyed_ahead.distance_squared_to(ahead) > step
	var turned := _look_dir.length_squared() > 0.0001 \
		and _look_dir.dot(_surveyed_look) < LOOK_SURVEY_DOT
	var interval := survey_interval
	if rush:
		# Movement is already true every frame at speed. Tightening the clock
		# just makes sixteen fields fight for one survey token.
		interval = maxf(survey_interval, 0.45)
	elif _lead_length > _tile or turned:
		interval = minf(survey_interval, 0.2)
	var clock := Time.get_ticks_usec()
	# The first pass cannot wait on the interval: spawn is standing still, and
	# the keep-circle has to exist before the first look-around.
	var due := not _surveyed_at.is_finite() \
		or (_since_survey > interval and (moved_to_new_ground or turned))
	if due and _take_survey():
		_since_survey = 0.0
		_surveyed_at = eye
		_surveyed_ahead = ahead
		_surveyed_look = _look_dir
		_survey(eye)
	clock = _charge(&"survey", clock)
	_dispatch(eye)
	clock = _charge(&"dispatch", clock)
	_apply()
	clock = _charge(&"apply", clock)
	_dress(eye)
	_charge(&"dress", clock)
	_report_lag()
	if _since_lights > 0.7:
		_since_lights = 0.0
		_place_glow_lights(eye)
	if not _glow_lights.is_empty():
		_fade_glow_lights(delta)


# --- Aerial glow ------------------------------------------------------------

## Starts one exact, deterministic replay of this localized field.
##
## The texture is cleared before the worker starts. [member
## Planet.SURFACE_MATERIAL] is a preloaded resource and survives a scene reload,
## so leaving the old mask there until the new one arrives would briefly show
## the previous world's meadow.
func _prepare_aerial_glow() -> void:
	if not aerial_glow:
		return
	var surface := Planet.SURFACE_MATERIAL
	surface.set_shader_parameter(&"flora_flower_glow_mask", null)
	surface.set_shader_parameter(&"flora_flower_glow_radius", 0.0)
	if global_cover:
		push_warning("GroundCover '%s' cannot publish a localized aerial mask "
			+ "while global_cover is enabled" % name)
		return

	for index in species.size():
		var plant := species[index] as PlantSpecies
		if plant == null:
			continue
		var night_lit := _night_species.has(index)
		if plant.glowing_patches <= 0.0 and not night_lit:
			continue
		_aerial_glow_species.append(index)
	if _aerial_glow_species.is_empty():
		push_warning("GroundCover '%s' requested aerial glow but has no "
			+ "luminous species" % name)
		return

	# The actual field is a circle of accepted tile centres, and plants inside
	# an edge tile may stand half its diagonal beyond `spread`. Give the mask
	# that real extent; black texels still describe all the ground where no
	# candidate survived.
	_aerial_glow_radius = spread + _tile * 0.71
	surface.set_shader_parameter(&"flora_glow_direction", _centre)
	_aerial_glow_task = WorkerThreadPool.add_task(_build_aerial_glow_image)


func _has_night_emission(plant: PlantSpecies) -> bool:
	if plant.material == null:
		return false
	var energy = plant.material.get_shader_parameter(&"night_emission_energy")
	return energy != null and float(energy) > 0.0


## True once the deterministic field has become the texture the terrain reads.
## Public for the visual harness; gameplay never has to wait on it.
func aerial_glow_ready() -> bool:
	return not aerial_glow or _aerial_glow_texture != null


## Main-thread half of the build. Creating a rendering resource belongs here;
## the worker only creates and fills an [Image].
func _finish_aerial_glow() -> void:
	if _aerial_glow_task < 0 \
			or not WorkerThreadPool.is_task_completed(_aerial_glow_task):
		return
	WorkerThreadPool.wait_for_task_completion(_aerial_glow_task)
	_aerial_glow_task = -1
	if _aerial_glow_image == null or _aerial_glow_image.is_empty():
		push_warning("GroundCover '%s' produced no aerial glow mask" % name)
		return
	_aerial_glow_texture = ImageTexture.create_from_image(_aerial_glow_image)
	_aerial_glow_image = null
	var surface := Planet.SURFACE_MATERIAL
	surface.set_shader_parameter(&"flora_glow_direction", _centre)
	surface.set_shader_parameter(&"flora_flower_glow_radius",
		_aerial_glow_radius)
	surface.set_shader_parameter(&"flora_flower_glow_mask",
		_aerial_glow_texture)


## Worker-thread half: replay every tile through [method _scatter] and rasterize
## the accepted instance origins.
##
## Calling `_scatter` rather than copying its patch and terrain tests is the
## invariant that matters. The same cell seed consumes the same random values,
## so a white texel is not somewhere flowers statistically ought to grow; it is
## where the transforms in a streamed MultiMesh really stand when that tile is
## visited.
func _build_aerial_glow_image() -> void:
	var size := clampi(aerial_glow_mask_size, 64, 512)
	var count := size * size
	var combined := PackedFloat32Array()
	combined.resize(count)
	var metres_per_pixel := _aerial_glow_radius * 2.0 / float(size)
	var edge := spread / _tile
	var cell_limit := ceili(edge) + 1
	var into_host := _into_local.affine_inverse()

	for species_index in _aerial_glow_species:
		var plant := species[species_index] as PlantSpecies
		if plant == null:
			continue
		var density := PackedFloat32Array()
		density.resize(count)
		var all_instances_glow := _night_species.has(species_index)

		for cell_x in range(-cell_limit, cell_limit + 1):
			for cell_y in range(-cell_limit, cell_limit + 1):
				var middle := Vector2(
					float(cell_x) + 0.5, float(cell_y) + 0.5)
				if middle.length() > edge:
					continue
				var cell := Vector3i(LOCAL_FACE, cell_x, cell_y)
				var glow_points := PackedVector3Array()
				var glow_levels := PackedFloat32Array()
				var glow_species := PackedInt32Array()
				# At full density regardless of what the streamed tiles are
				# sown at: this mask is the field as it would be if the viewer
				# stood everywhere at once, and it is built once.
				var buffer := _scatter(species_index, plant,
					_patches[species_index], _glows[species_index], cell, 1.0,
					glow_points, glow_levels, glow_species)
				var instances := buffer.size() / STRIDE
				for instance in instances:
					var base := instance * STRIDE
					var level := 1.0 if all_instances_glow \
						else buffer[base + RANK + 2]
					if level <= 0.01:
						continue
					var local_point := Vector3(
						buffer[base + 3],
						buffer[base + 7],
						buffer[base + 11])
					var at := (into_host * local_point).normalized()
					var centre_share := maxf(at.dot(_centre), 0.0001)
					var offset := Vector2(
						at.dot(_east), at.dot(_north)) \
						* (_radius / centre_share)
					var pixel := Vector2(
						(offset.x / (_aerial_glow_radius * 2.0) + 0.5)
							* float(size - 1),
						(offset.y / (_aerial_glow_radius * 2.0) + 0.5)
							* float(size - 1))
					var x := roundi(pixel.x)
					var y := roundi(pixel.y)
					if x < 0 or x >= size or y < 0 or y >= size:
						continue
					var pixel_index := y * size + x
					density[pixel_index] += level

		# Two box passes approximate the broad footprint of light from many
		# flowers without moving their centres or inventing growth between
		# disconnected patches.
		var blur_pixels := maxi(1, roundi(
			aerial_glow_blur_radius / maxf(metres_per_pixel, 0.01) * 0.6))
		density = _blur_aerial_density(density, size, blur_pixels)
		var expected := maxf(
			plant.per_square_metre * metres_per_pixel * metres_per_pixel,
			0.2)
		for pixel_index in count:
			# A dense, fully valid patch reaches one. Sparse margins retain
			# their real share, and overlapping luminous species pool rather
			# than one replacing another.
			var level := smoothstep(0.02, expected * 0.7,
				density[pixel_index])
			combined[pixel_index] = 1.0 \
				- (1.0 - combined[pixel_index]) * (1.0 - level)

	var image := Image.create_empty(size, size, false, Image.FORMAT_RF)
	for y in size:
		for x in size:
			var level := combined[y * size + x]
			image.set_pixel(x, y, Color(level, 0.0, 0.0, 1.0))
	image.generate_mipmaps()
	_aerial_glow_image = image


## A separable two-pass box blur, repeated once. Dividing by the full kernel at
## an edge treats samples beyond the mask as black, which is the soft falloff a
## planted field needs instead of reflecting its last row of flowers outward.
func _blur_aerial_density(source: PackedFloat32Array, size: int,
		radius_pixels: int) -> PackedFloat32Array:
	var current := source
	var radius := maxi(radius_pixels, 1)
	var kernel := float(radius * 2 + 1)
	for _pass in 2:
		var horizontal := PackedFloat32Array()
		horizontal.resize(size * size)
		for y in size:
			var total := 0.0
			for offset in range(-radius, radius + 1):
				if offset >= 0 and offset < size:
					total += current[y * size + offset]
			for x in size:
				horizontal[y * size + x] = total / kernel
				var remove := x - radius
				var add := x + radius + 1
				if remove >= 0:
					total -= current[y * size + remove]
				if add < size:
					total += current[y * size + add]

		var vertical := PackedFloat32Array()
		vertical.resize(size * size)
		for x in size:
			var total := 0.0
			for offset in range(-radius, radius + 1):
				if offset >= 0 and offset < size:
					total += horizontal[offset * size + x]
			for y in size:
				vertical[y * size + x] = total / kernel
				var remove := y - radius
				var add := y + radius + 1
				if remove >= 0:
					total -= horizontal[remove * size + x]
				if add < size:
					total += horizontal[add * size + x]
		current = vertical
	return current


# --- Streaming --------------------------------------------------------------

## Which tiles should exist, and the retirement of the ones that should not.
func _survey(eye: Vector3) -> void:
	var host := planet_host()
	if host != null:
		_follow_lead(host)
		_follow_look(eye)
	var span := int(ceil(_wanted_reach() / _tile)) + 1
	_wanted.clear()
	_dispatch_needed = true
	if global_cover:
		_survey_global(eye, span)
	else:
		_survey_local(eye, span)
	# Nearest first, decided here rather than by the dispatcher. Sorting is a few
	# hundred comparisons once or twice a second; the scan it replaces was the
	# same few hundred entries walked again in every field in every frame for as
	# long as anything was still streaming, which while flying is always.
	# Path distance so the corridor being run into is grown before the sides.
	# A named compare avoids a lambda allocation per survey; the planet already
	# measured `sort_custom` script calls as the expensive part of a small sort.
	if _wanted.size() > 1:
		_wanted.sort_custom(_wanted_nearer)
	_dispatch_from = 0
	# Hysteresis, so a viewer standing on a tile boundary does not rebuild the
	# same ring of tiles every survey. Retirement stays around the true eye:
	# leading a drop would take plants out from under a viewer that turned.
	# Cap the frees: a ring falling out of range used to queue_free every
	# leftover stand in one survey, which is the despawn hitch at speed.
	var drops := FRAME_DROPS if _rushing() else IDLE_DROPS
	for cell: Vector3i in _tiles.keys():
		if drops <= 0:
			break
		var tile := _tiles[cell] as Tile
		if tile.queued or _cell_held(tile.at, eye):
			continue
		for stand in tile.stands:
			if is_instance_valid(stand):
				stand.queue_free()
		for body in tile.collisions:
			if is_instance_valid(body):
				body.queue_free()
		_tiles.erase(cell)
		_tile_list_stale = true
		drops -= 1


func _survey_anchors(eye: Vector3) -> Array[Vector3]:
	var anchors: Array[Vector3] = [eye]
	if _fill_only() and _rushing():
		return anchors
	if _lead_length <= _tile * 0.5:
		return anchors
	anchors.append(eye + _lead_direction * _lead_length)
	if _lead_length > _reach and not _rushing():
		anchors.append(eye + _lead_direction * (_lead_length * 0.5))
	return anchors


## Copies the planet's smoothed travel into this field's world-space corridor.
## Length is this field's own cap: terrain may look a kilometre ahead, and that
## is too many tiles for plants.
func _follow_lead(host: Planet) -> void:
	var drift := host.viewer_drift()
	var speed := drift.length()
	if lead_time <= 0.0 or speed < 8.0:
		_lead_direction = Vector3.ZERO
		_lead_length = 0.0
		return
	_lead_direction = (host.global_transform.basis * (drift / speed)).normalized()
	_lead_length = minf(speed * lead_time, lead_distance)


func _follow_look(_eye: Vector3) -> void:
	var frame := Engine.get_process_frames()
	if frame == _looked_frame:
		_look_dir = _shared_look
		return
	_looked_frame = frame
	var look := Vector3.ZERO
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			look = -camera.global_transform.basis.z
	if look.length_squared() > 0.0001:
		_shared_look = look.normalized()
	_look_dir = _shared_look


func keep_circle_metres() -> float:
	return clampf(_reach * KEEP_CIRCLE_SHARE, KEEP_CIRCLE_MIN, KEEP_CIRCLE_MAX)


func _stream_reach() -> float:
	return _reach + maxf(STREAM_PAD, _tile * 1.5)


func _fill_stream_reach() -> float:
	return maxf(keep_circle_metres(), FILL_STREAM_METRES)


func _wanted_reach() -> float:
	if _fill_only() and _rushing():
		return _fill_stream_reach()
	return _stream_reach()


func _rushing() -> bool:
	return _lead_length >= RUSH_LEAD


func _fill_only() -> bool:
	return _has_fill and not _has_skyline


func _apply_stream_mode(growing: bool) -> void:
	set_process(growing and (stream_fill or _has_skyline))


func _classify_species() -> void:
	_has_skyline = false
	_has_fill = false
	for plant in species:
		if plant == null:
			continue
		if plant.is_skyline():
			_has_skyline = true
		else:
			_has_fill = true
	if _has_skyline and not _has_fill:
		process_priority = -20
	elif _has_fill and not _has_skyline:
		process_priority = 20
	else:
		process_priority = 0


func _session_allows_stream() -> bool:
	if Engine.is_editor_hint():
		return editor_preview
	return NetworkManager.state == NetworkManager.SessionState.IN_GAME


static func _refresh_budgets() -> void:
	var frame := Engine.get_process_frames()
	if frame == _budget_frame:
		return
	_budget_frame = frame
	_survey_left = IDLE_SURVEYS
	_apply_left = IDLE_APPLIES
	_sow_left = IDLE_SOWS


func _take_survey() -> bool:
	_refresh_budgets()
	if _rushing():
		_survey_left = mini(_survey_left, FRAME_SURVEYS)
	if _survey_left <= 0:
		return false
	_survey_left -= 1
	return true


func _take_apply() -> bool:
	_refresh_budgets()
	if _rushing():
		_apply_left = mini(_apply_left, FRAME_APPLIES)
	if _apply_left <= 0:
		return false
	_apply_left -= 1
	return true


func _take_sow() -> bool:
	_refresh_budgets()
	if _rushing():
		_sow_left = mini(_sow_left, FRAME_SOWS)
	if _sow_left <= 0:
		return false
	_sow_left -= 1
	return true


## True when a world point sits inside the look cone and inside `far`.
## The keep-circle around the viewer is applied by the tile filters, not here.
static func in_view_volume(at: Vector3, eye: Vector3, look: Vector3,
		cone_cos: float, far: float) -> bool:
	var delta := at - eye
	var away2 := delta.length_squared()
	if away2 > far * far:
		return false
	if look.length_squared() < 0.0001:
		return false
	if away2 < 0.0001:
		return true
	return delta.normalized().dot(look.normalized()) >= cone_cos


func _cell_wanted(at: Vector3, eye: Vector3) -> bool:
	var keep := keep_circle_metres()
	var away := eye.distance_to(at)
	if _fill_only() and _rushing():
		return away <= _fill_stream_reach() + _tile
	if away <= keep + _tile:
		return true
	if in_view_volume(at, eye, _look_dir, VIEW_CONE_COS, _stream_reach() + _tile):
		return true
	if _lead_length > _tile * 0.5 and _path_away(at, eye) <= keep:
		var along := (at - eye).dot(_lead_direction)
		return along > 0.0 and along <= _lead_length + _tile
	return false


func _cell_shown(at: Vector3, eye: Vector3) -> bool:
	var keep := keep_circle_metres()
	if eye.distance_to(at) <= keep + _tile * 0.35:
		return true
	return in_view_volume(at, eye, _look_dir, VIEW_CONE_COS, _reach + _tile * 0.5)


func _cell_held(at: Vector3, eye: Vector3) -> bool:
	var keep := keep_circle_metres()
	var away := eye.distance_to(at)
	if _fill_only() and _rushing():
		return away <= _fill_stream_reach() + _tile * 2.2
	var along := (at - eye).dot(_lead_direction)
	if _rushing() and along < -_tile:
		return false
	if away <= keep + _tile * 2.2:
		return true
	if in_view_volume(at, eye, _look_dir, VIEW_CONE_KEEP_COS,
			_stream_reach() + _tile * 2.0):
		return true
	if _lead_length > _tile * 0.5 and along > 0.0 \
			and _path_away(at, eye) <= keep + _tile:
		return true
	return false


func _path_away(at: Vector3, eye: Vector3) -> float:
	if _lead_length <= 0.0:
		return eye.distance_to(at)
	var to_tile := at - eye
	var along := clampf(to_tile.dot(_lead_direction), 0.0, _lead_length)
	return (to_tile - _lead_direction * along).length()


func _ahead_pending() -> int:
	if _has_skyline and _lead_length >= maxf(_tile, 1.0):
		return mini(pending_limit + 2, 4)
	return pending_limit


func _wanted_nearer(a: Vector3i, b: Vector3i) -> bool:
	var left := _tiles.get(a) as Tile
	var right := _tiles.get(b) as Tile
	if left == null:
		return false
	if right == null:
		return true
	return left.path_away < right.path_away


func _ensure_tile_list() -> void:
	if not _tile_list_stale:
		return
	_tile_list.assign(_tiles.values())
	_tile_list_stale = false


func _survey_local(eye: Vector3, span: int) -> void:
	var edge := spread / _tile
	var seen := {}
	var anchors := _survey_anchors(eye)
	var keep_span := _keep_span()
	for index in anchors.size():
		var disk_only := index > 0
		var walk := keep_span if disk_only else span
		var here := _cell_of(anchors[index])
		var look_flat := _look_on_tangent(_east, _north)
		for x in range(here.y - walk, here.y + walk + 1):
			for y in range(here.z - walk, here.z + walk + 1):
				var cell := Vector3i(LOCAL_FACE, x, y)
				if seen.has(cell):
					continue
				var middle := Vector2(float(x) + 0.5, float(y) + 0.5)
				if middle.length() > edge:
					continue
				var offset := Vector2(float(x - here.y), float(y - here.z)) * _tile
				if not _offset_wanted(offset, look_flat, disk_only):
					continue
				seen[cell] = true
				_want_cell(cell, eye)


func _survey_global(eye: Vector3, span: int) -> void:
	var seen := {}
	var anchors := _survey_anchors(eye)
	var keep_span := _keep_span()
	for index in anchors.size():
		_survey_global_around(anchors[index],
			keep_span if index > 0 else span, seen, eye, index > 0)


func _survey_global_around(anchor: Vector3, span: int, seen: Dictionary,
		eye: Vector3, disk_only: bool) -> void:
	var host := planet_host()
	if host == null or _grid == null:
		return
	var up := host.to_local(anchor).normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := up.cross(east)
	var look_flat := _look_on_tangent(east, north)
	# Sampling the viewer's tangent square and canonicalising each direction to a
	# cube-face key naturally crosses face seams. Oversampling by one cell avoids
	# a missed corner where cube projection compresses the grid.
	for x in range(-span - 1, span + 2):
		for y in range(-span - 1, span + 2):
			var offset := Vector2(float(x), float(y)) * _tile
			if not _offset_wanted(offset, look_flat, disk_only):
				continue
			var direction_at := (up
				+ (east * offset.x + north * offset.y) / _radius).normalized()
			var cell := _grid.key_for(direction_at)
			if seen.has(cell):
				continue
			seen[cell] = true
			_want_cell(cell, eye)


func _keep_span() -> int:
	return int(ceil(keep_circle_metres() / _tile)) + 2


## Look direction in the same east/north frame the survey walks, so a cell
## behind the viewer can be skipped before it is projected or height-sampled.
func _look_on_tangent(east: Vector3, north: Vector3) -> Vector2:
	var look := _look_dir
	var host := planet_host()
	if host != null:
		look = host.global_transform.basis.inverse() * _look_dir
	return Vector2(look.dot(east), look.dot(north))


func _offset_wanted(offset: Vector2, look_flat: Vector2, disk_only: bool) -> bool:
	var away := offset.length()
	var keep := keep_circle_metres() + _tile
	if _fill_only() and _rushing():
		return away <= _fill_stream_reach() + _tile
	if disk_only:
		return away <= keep
	var far := _stream_reach() + _tile * 1.5
	if away > far:
		return false
	if away <= keep:
		return true
	# No camera yet: only the keep-circle, matching `_cell_wanted`. A zero look
	# must not be read as "looking down" or the first survey walks a full ring.
	if _look_dir.length_squared() < 0.0001:
		return false
	# Looking down (or up) onto the disk: the 3D cone covers the ground around
	# the viewer, so the whole radius has to stay in play.
	if look_flat.length_squared() < 0.08:
		return true
	if away < 0.0001:
		return true
	return offset.normalized().dot(look_flat.normalized()) >= VIEW_CONE_KEEP_COS


func _want_cell(cell: Vector3i, eye: Vector3) -> void:
	var tile := _tiles.get(cell) as Tile
	if tile == null:
		if _barren.has(cell):
			return
		if not _cell_may_grow(cell):
			if _barren.size() >= 4096:
				_barren.clear()
			_barren[cell] = true
			return
		var at := _ground_point(cell)
		if not _cell_wanted(at, eye):
			return
		tile = Tile.new()
		tile.cell = cell
		tile.at = at
		tile.slice = _next_slice
		_next_slice = (_next_slice + 1) % DRESS_SLICES
		_tiles[cell] = tile
		_tile_list_stale = true
	elif not _cell_wanted(tile.at, eye):
		return
	tile.away = eye.distance_to(tile.at)
	tile.path_away = _path_away(tile.at, eye)
	# Coming closer earns a tile plants its distance had not. Re-sowing is not a
	# rebuild: the finer band repeats the prefix it already grew and appends to
	# it, so this adds plants between the standing ones rather than moving them.
	# Path distance so a tile on the track is thickened before the viewer
	# arrives, instead of waiting for the true gap to fall into the next band.
	if tile.grown and not tile.queued and _detail_short(tile):
		tile.grown = false
		_dispatch_needed = true
	_wanted.append(cell)


## Share of a species' full density a tile this far off could ever show, rounded
## up to a band so that walking towards one re-sows it a few times rather than
## continuously.
func _detail_needed(plant: PlantSpecies, away: float) -> float:
	# Measured to the near edge, matching _dress: the nearest plant on the tile
	# is what decides how much of it has to exist.
	var nearest := maxf(away - _tile * 0.71, 0.0)
	var need := minf(plant.keep_at(nearest), 1.0)
	for band in DETAIL_BANDS:
		if band >= need:
			return band
	return 1.0


func _detail_plan(away: float) -> PackedFloat32Array:
	var plan := PackedFloat32Array()
	plan.resize(species.size())
	var fill_cap := _fill_stream_reach() if _rushing() else INF
	for index in species.size():
		var plant := species[index] as PlantSpecies
		if plant == null:
			plan[index] = 0.0
			continue
		if not plant.is_skyline() and (not stream_fill or away > fill_cap):
			plan[index] = 0.0
			continue
		plan[index] = _detail_needed(plant, away)
	return plan


## Whether any species on a grown tile is now standing at a coarser density than
## the viewer's distance calls for.
func _detail_short(tile: Tile) -> bool:
	for index in species.size():
		var plant := species[index] as PlantSpecies
		if plant == null:
			continue
		var have := tile.detail[index] if index < tile.detail.size() else 1.0
		if _detail_needed(plant, tile.path_away) > have + 0.0001:
			return true
	return false


## Cheap rejection before a tile reaches the worker pool. Centre plus corners
## are enough because the margin above is the maximum change a slope this species
## accepts can make across the tile.
func _cell_may_grow(cell: Vector3i) -> bool:
	if not is_finite(_height_floor) or not is_finite(_height_ceiling):
		return false
	var low := _height_floor - _height_margin
	var high := _height_ceiling + _height_margin
	var here := _shape.elevation(_direction_in_cell(cell, 0.5, 0.5), _spacing)
	if here >= low and here <= high:
		return true
	for sample: Vector2 in [Vector2(0.0, 0.0), Vector2(1.0, 1.0)]:
		var height := _shape.elevation(
			_direction_in_cell(cell, sample.x, sample.y), _spacing)
		if height >= low and height <= high:
			return true
	return false


func _dispatch(eye: Vector3) -> void:
	if not _dispatch_needed:
		return
	var slots := _ahead_pending() - _pending.size()
	while slots > 0:
		# The tile underfoot matters more than one at the edge of sight, and the
		# wanted set is already in that order, so this only ever walks past
		# tiles it will never have to consider again.
		var nearest: Tile = null
		while _dispatch_from < _wanted.size():
			var tile := _tiles.get(_wanted[_dispatch_from]) as Tile
			if tile != null and not tile.queued and not tile.grown:
				nearest = tile
				break
			_dispatch_from += 1
		if nearest == null:
			_dispatch_needed = false
			return
		if not _take_sow():
			return
		nearest.queued = true
		# Decided here and not on the thread, so the worker reads a plan that
		# cannot change under it and the tile remembers what it was given.
		# Path distance, not the dressed true gap: dress overwrites `away`
		# every few metres, and sowing from that would grow the corridor at
		# horizon density and hitch again when the viewer arrived.
		nearest.path_away = _path_away(nearest.at, eye)
		nearest.detail = _detail_plan(nearest.path_away)
		_pending[WorkerThreadPool.add_task(_sow.bind(nearest))] = nearest
		_dispatch_from += 1
		slots -= 1


func _apply() -> void:
	if _pending.is_empty() and _finished.is_empty():
		return
	for task in _pending.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_finished.append(_pending[task])
			_pending.erase(task)
	while not _finished.is_empty():
		var tile := _finished[0] as Tile
		if not _tiles.has(tile.cell):
			_finished.pop_front()
			tile.queued = false
			continue
		if not _take_apply():
			return
		_finished.pop_front()
		tile.queued = false
		tile.grown = true
		tile.glow_points = tile.sow_glow_points
		tile.glow_levels = tile.sow_glow_levels
		tile.glow_species = tile.sow_glow_species
		_raise(tile)


func _stand_of(tile: Tile, index: int) -> MultiMeshInstance3D:
	if tile == null or index < 0 or index >= tile.stands.size():
		return null
	var held: Variant = tile.stands[index]
	if not is_instance_valid(held):
		tile.stands[index] = null
		return null
	return held as MultiMeshInstance3D


func _body_of(tile: Tile, index: int) -> StaticBody3D:
	if tile == null or index < 0 or index >= tile.collisions.size():
		return null
	var held: Variant = tile.collisions[index]
	if not is_instance_valid(held):
		tile.collisions[index] = null
		return null
	return held as StaticBody3D


## Turns a grown tile's buffers into the nodes that draw them.
func _raise(tile: Tile) -> void:
	# A tile is raised again every time approaching it earns a finer sow, and
	# what comes back is the whole tile rather than the difference. The plants
	# already drawn are in the new buffer at the same indices, so nothing visibly
	# changes place — but the physics built from the old buffer knows nothing of
	# the ones appended to it, so that is dropped and rebuilt by the next
	# dressing pass.
	for index in tile.collisions.size():
		var body := _body_of(tile, index)
		if body != null:
			body.queue_free()
	if not tile.collisions.is_empty():
		_collision_rids_stale = true
	tile.collisions.clear()
	tile.stands.resize(species.size())
	tile.collisions.resize(species.size())
	tile.roots.clear()
	tile.roots.resize(species.size())
	tile.rows.clear()
	tile.rows.resize(species.size())
	# Whatever pass this tile belongs to, it cannot wait for it: until it is
	# dressed it is drawing every plant it holds and has no shadow or collision
	# decision made about it.
	tile.fresh = true
	for index in species.size():
		var plant := species[index] as PlantSpecies
		var buffer := tile.buffers[index] as PackedFloat32Array
		var stand := _stand_of(tile, index)
		if plant == null or buffer.is_empty():
			# A species can lose its footing on a re-sow the tile had it on
			# before, so an empty buffer has to retire the stand rather than
			# leave the previous one drawing.
			if stand != null:
				stand.queue_free()
				tile.stands[index] = null
			continue
		var count := buffer.size() / STRIDE
		var multimesh := stand.multimesh if stand != null else null
		if multimesh == null:
			multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = true
			multimesh.use_custom_data = true
		multimesh.instance_count = count
		buffer = _apply_broken_instances(tile.cell, index, buffer)
		multimesh.buffer = buffer
		tile.rows[index] = buffer
		tile.roots[index] = _roots_of(buffer, count)
		multimesh.mesh = plant.near_mesh()
		if stand == null:
			stand = MultiMeshInstance3D.new()
			# GeometryInstance3D defaults to casting. Set the species'
			# no-shadow intent before the node enters the tree instead of
			# waiting for _dress: a newly streamed tile must never spend even
			# its first rendered frame writing thousands of animated,
			# sub-texel leaves into the shadow map.
			if plant.shadow_within <= 0.0:
				stand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# The bend moves vertices the bounds were computed without, and at
			# the scale of a tile the whole field would otherwise be culled a
			# frame early at the edge of the screen.
			stand.extra_cull_margin = plant.height * 1.5
			stand.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			# Rooted cover never has a physics-driven transform. Disabling the
			# server's second interpolation buffer also keeps the rare impact
			# upload from being treated as an out-of-physics animation update.
			stand.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			stand.material_override = plant.near_material()
			# Internal, for the same reason the planet's chunks are: a few
			# hundred of these in the Scene dock is a few hundred things
			# between you and the world.
			add_child(stand, false, Node.INTERNAL_MODE_BACK)
			tile.stands[index] = stand
		# Reused where one is already standing. Re-sowing a tile at a finer
		# band happens as often as walking towards one, and building a node and
		# a rendering-server instance for a tile that already had both was the
		# single largest part of what applying a tile cost.
		stand.multimesh = multimesh
		# Preload tiles exist so a turn or a step has plants ready, but they
		# must not spend a frame as a full-density draw behind the camera.
		if not _cell_shown(tile.at, _viewer_eye()):
			multimesh.visible_instance_count = 0
			stand.visible = false
	tile.buffers.clear()
	_dressed_at = Vector3.INF


func _viewer_eye() -> Vector3:
	var host := planet_host()
	if host == null:
		return global_position
	return host.to_global(host.viewer_position())


## Per-frame distance work: how much of each tile to draw, which mesh to draw it
## with, and whether it is worth a shadow. Everything here is per tile and per
## species — a few hundred numbers — and nothing is per plant.
func _dress(eye: Vector3) -> void:
	if _tiles.is_empty():
		return
	var turned := _look_dir.length_squared() > 0.0001 \
		and _look_dir.dot(_dressed_look) < LOOK_DRESS_DOT
	if _dressed_at.is_finite() \
			and _dressed_at.distance_squared_to(eye) < DRESS_STEP * DRESS_STEP \
			and not turned:
		return
	_dressed_at = eye
	_dressed_look = _look_dir
	# A heading change has to hide the old back-hemisphere this frame. Walking
	# the usual slice would leave three quarters of those MultiMeshes submitted
	# until the next few metres of travel, which is the snap-turn hitch.
	if not turned:
		_dress_slice = (_dress_slice + 1) % DRESS_SLICES
	_ensure_tile_list()
	for tile: Tile in _tile_list:
		if not turned and tile.slice != _dress_slice and not tile.fresh:
			continue
		tile.fresh = false
		tile.away = eye.distance_to(tile.at)
		# Measured to the near edge rather than the middle. The thinning curve
		# has to be at least as generous as the one the shader evaluates per
		# plant, and the nearest plant in the tile is nearer than its centre.
		var nearest := maxf(tile.away - _tile * 0.71, 0.0)
		for index in tile.stands.size():
			var stand := _stand_of(tile, index)
			if stand == null:
				continue
			var plant := species[index] as PlantSpecies
			var multimesh := stand.multimesh
			# Divided by the band the tile was sown at, because that share of
			# the thinning has already been taken: a tile holding an eighth of
			# its plants and asked to show an eighth of them would show a
			# sixty-fourth.
			var detail := tile.detail[index] if index < tile.detail.size() else 1.0
			# Nearer than the thinning begins, every plant the tile holds is
			# drawn; past the fade nothing is. Only the band between the two
			# needs the curve, and while flying most of a field is outside it.
			var showing := multimesh.instance_count
			# Past the far edge of the fade rather than the reach itself: the
			# curve is still handing out the far share at the reach and only
			# reaches zero twelve per cent beyond it.
			if not _cell_shown(tile.at, eye):
				showing = 0
			elif not plant.is_skyline() and _rushing() \
					and nearest > _fill_stream_reach():
				showing = 0
			elif nearest >= plant.draw_reach() * 1.12:
				showing = 0
			elif nearest > plant.full_within():
				showing = clampi(int(plant.keep_at(nearest)
						/ maxf(detail, 0.0001)
						* float(multimesh.instance_count)),
					0, multimesh.instance_count)
			if multimesh.visible_instance_count != showing:
				multimesh.visible_instance_count = showing
			var wanted_visible := showing > 0
			if stand.visible != wanted_visible:
				stand.visible = wanted_visible
			if not _rushing():
				_dress_collision(tile, index, plant, stand,
					wanted_visible and nearest < plant.collision_within)
			if showing == 0:
				continue
			# Compared against what the stand is already holding rather than
			# against a remembered flag, so several species on one tile each
			# swap at their own distance.
			var distant := tile.away > plant.distant_beyond
			var wanted := plant.distant_mesh() if distant else plant.near_mesh()
			if multimesh.mesh != wanted:
				multimesh.mesh = wanted
			var wanted_material := plant.far_material() if distant else plant.near_material()
			if stand.material_override != wanted_material:
				stand.material_override = wanted_material
			var casting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
				if tile.away < plant.shadow_within \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if stand.cast_shadow != casting:
				stand.cast_shadow = casting


## Adds physics only to the ring of cover a player could currently touch.
## Visual instances remain in their MultiMesh; unpacking their transforms happens
## once when a tile enters that ring, never every frame.
func _dress_collision(tile: Tile, index: int, plant: PlantSpecies,
		stand: MultiMeshInstance3D, wanted: bool) -> void:
	wanted = wanted and plant.collision_enabled
	var current := _body_of(tile, index)
	if not wanted:
		if current != null:
			current.queue_free()
			tile.collisions[index] = null
			_collision_rids_stale = true
		return
	if current != null:
		return

	var body := StaticBody3D.new()
	body.name = "%sCollision" % plant.resource_name
	body.collision_layer = 1
	body.collision_mask = 1
	var multimesh := stand.multimesh
	var buffer := _rows_of(tile, index, multimesh)
	var mesh_shape := plant.mesh_collision_shape()
	for plant_index in multimesh.instance_count:
		if _is_broken(tile.cell, index, plant_index):
			continue
		var stood := _instance_transform(buffer, plant_index)
		var visual_height := plant.authored_height() * stood.basis.y.length()
		var collider_height := maxf(
			visual_height * plant.collision_height_share, 0.1)
		var collider_radius := maxf(
			visual_height * plant.collision_radius_share, 0.08)
		var shape: Shape3D = mesh_shape
		if shape == null:
			match plant.collision_primitive:
				PlantSpecies.CollisionPrimitive.SPHERE:
					var sphere := SphereShape3D.new()
					sphere.radius = maxf(collider_radius, collider_height * 0.5)
					shape = sphere
				PlantSpecies.CollisionPrimitive.BOX:
					var box := BoxShape3D.new()
					box.size = Vector3(
						collider_radius * 2.0, collider_height,
						collider_radius * 2.0)
					shape = box
				_:
					var cylinder := CylinderShape3D.new()
					cylinder.height = collider_height
					cylinder.radius = collider_radius
					shape = cylinder
		var collider := CollisionShape3D.new()
		collider.name = "%s%d" % [plant.resource_name, plant_index]
		collider.shape = shape
		if mesh_shape != null:
			var instance_scale := maxf(stood.basis.y.length(), 0.0001)
			collider.transform = Transform3D(
				stood.basis.orthonormalized().scaled(
					Vector3.ONE * instance_scale),
				stood.origin)
		else:
			var stem_up := stood.basis.y.normalized()
			collider.transform = Transform3D(
				stood.basis.orthonormalized(),
				stood.origin + stem_up * collider_height * 0.5)
		collider.set_meta(IMPACT_OWNER_META, self)
		collider.set_meta(IMPACT_CELL_META, tile.cell)
		collider.set_meta(IMPACT_SPECIES_META, index)
		collider.set_meta(IMPACT_INSTANCE_META, plant_index)
		collider.set_meta(IMPACT_HEIGHT_META, visual_height)
		body.add_child(collider)
	add_child(body, false, Node.INTERNAL_MODE_BACK)
	tile.collisions[index] = body
	_collision_rids_stale = true


## Resolves one player contact identified by collider metadata. An empty answer
## means the ordinary solid-impact policy still owns the contact. A non-empty
## answer tells OnlinePlayer to preserve momentum (and, for mushrooms, launch)
## while this field removes the visual and physical instance.
func resolve_flora_impact(collider: CollisionShape3D, impact_speed: float,
		at: Vector3) -> Dictionary:
	if collider == null or collider.get_meta(IMPACT_OWNER_META, null) != self:
		return {}
	var cell_value: Variant = collider.get_meta(IMPACT_CELL_META, null)
	if not cell_value is Vector3i:
		return {}
	var cell: Vector3i = cell_value
	var species_index := int(collider.get_meta(IMPACT_SPECIES_META, -1))
	var instance_index := int(collider.get_meta(IMPACT_INSTANCE_META, -1))
	if species_index < 0 or species_index >= species.size() or instance_index < 0:
		return {}
	var plant := species[species_index] as PlantSpecies
	if plant == null or (plant.impact_mode != PlantSpecies.ImpactMode.BREAKABLE
			and plant.impact_mode != PlantSpecies.ImpactMode.MUSHROOM_BOUNCE):
		return {}
	var visual_height := float(collider.get_meta(
		IMPACT_HEIGHT_META, plant.height))
	if impact_speed < plant.impact_threshold(visual_height):
		return {}
	var bounce := plant.bounce_speed(impact_speed) \
		if plant.impact_mode == PlantSpecies.ImpactMode.MUSHROOM_BOUNCE \
		else 0.0
	var answer := {
		"handled": true,
		"broken": false,
		"momentum_keep": plant.break_momentum_keep,
		"bounce_up": bounce,
	}
	# Two slide entries can report the same shape in one move. The first removed
	# it; the second is still a handled soft contact but must not emit twice.
	if _is_broken(cell, species_index, instance_index):
		return answer
	var tile := _tiles.get(cell) as Tile
	if tile == null or species_index >= tile.stands.size():
		return {}
	var stand := _stand_of(tile, species_index)
	if stand == null or instance_index >= stand.multimesh.instance_count:
		return {}

	var multimesh := stand.multimesh
	var buffer := _rows_of(tile, species_index, multimesh)
	var stood := _instance_transform(buffer, instance_index)
	var world_stood := stand.global_transform * stood
	_mark_broken(cell, species_index, instance_index)
	_hide_instance(buffer, instance_index)
	tile.rows[species_index] = buffer
	multimesh.buffer = buffer
	collider.set_meta(IMPACT_BROKEN_META, true)
	# Physics shapes cannot be changed while the server is flushing the
	# move_and_slide query that found this one.
	collider.set_deferred(&"disabled", true)
	_play_break_effect(
		at if at.is_finite() else world_stood.origin,
		world_stood.basis.y.normalized(),
		impact_speed,
		visual_height,
		_break_tint(plant, buffer, instance_index),
		plant.break_effect)
	answer["broken"] = true
	return answer


func _mark_broken(cell: Vector3i, species_index: int,
		instance_index: int) -> void:
	if _is_broken(cell, species_index, instance_index):
		return
	_record_damage(cell, species_index, instance_index, BROKEN)
	_new_breaks.append_array(PackedInt32Array([cell.x, cell.y, cell.z,
		species_index, instance_index]))


func _is_broken(cell: Vector3i, species_index: int,
		instance_index: int) -> bool:
	return _damage_carried(cell, species_index, instance_index) == BROKEN


## Damage one instance is already carrying, or [constant BROKEN] if it is gone.
func _damage_carried(cell: Vector3i, species_index: int,
		instance_index: int) -> float:
	var per_species: Dictionary = _instance_damage.get(cell, {})
	var indices: Dictionary = per_species.get(species_index, {})
	return float(indices.get(instance_index, 0.0))


func _record_damage(cell: Vector3i, species_index: int, instance_index: int,
		carried: float) -> void:
	var per_species: Dictionary = _instance_damage.get(cell, {})
	var indices: Dictionary = per_species.get(species_index, {})
	indices[instance_index] = carried
	per_species[species_index] = indices
	_instance_damage[cell] = per_species


## Replays this tile's remembered destruction and scorching onto a freshly sown
## buffer. Placement is deterministic, so index N is the same plant it was
## before the tile was retired, and both the missing plants and the charring on
## the survivors come back with it.
func _apply_broken_instances(cell: Vector3i, species_index: int,
		buffer: PackedFloat32Array) -> PackedFloat32Array:
	var per_species: Dictionary = _instance_damage.get(cell, {})
	var indices: Dictionary = per_species.get(species_index, {})
	if indices.is_empty():
		return buffer
	var plant := species[species_index] as PlantSpecies
	for key in indices:
		var instance_index := int(key)
		if instance_index < 0 or (instance_index + 1) * STRIDE > buffer.size():
			continue
		var carried := float(indices[key])
		if carried == BROKEN:
			_hide_instance(buffer, instance_index)
			continue
		if plant == null:
			continue
		_char_instance(buffer, instance_index,
			carried / maxf(plant.health_for(
				_instance_height(buffer, instance_index, plant)), 0.001))
	return buffer


## Height in metres of one built instance, read back off its own transform.
## Pulls the origin column out of every row of a freshly sown buffer. See
## [member Tile.roots] for why it is worth keeping.
func _roots_of(buffer: PackedFloat32Array, count: int) -> PackedVector3Array:
	var roots := PackedVector3Array()
	roots.resize(count)
	for instance_index in count:
		var at := instance_index * STRIDE
		roots[instance_index] = Vector3(
			buffer[at + 3], buffer[at + 7], buffer[at + 11])
	return roots


func _instance_height(buffer: PackedFloat32Array, instance_index: int,
		plant: PlantSpecies) -> float:
	var at := instance_index * STRIDE
	var grew := Vector3(buffer[at + 1], buffer[at + 5], buffer[at + 9]).length()
	return grew * plant.authored_height()


## Collision bodies this field is currently simulating. Used by beams that must
## pass through flora: excluding these RIDs is one ray, piercing trunks one at a
## time is eight convex-hull queries on the physics clock.
func collision_rids() -> Array[RID]:
	if not _collision_rids_stale:
		return _collision_rids
	_collision_rids.clear()
	_ensure_tile_list()
	for tile in _tile_list:
		for body_variant in tile.collisions:
			var body := body_variant as CollisionObject3D
			if body != null and is_instance_valid(body):
				_collision_rids.append(body.get_rid())
	_collision_rids_stale = false
	return _collision_rids


## Ability damage, offered by anything holding a [DamageHit]. Returns how much
## of it this field absorbed, so a caller can tell a beam that cut through a
## thicket from one that found open ground.
##
## Instances are found by sweeping the buffers rather than by physics, because
## most cover has no collider at all: grass, shrubs and small mushrooms are the
## bulk of what a beam should mow, and none of them exist to a raycast. Only the
## instances a tile is actually drawing are considered — a plant thinned out at
## distance is not on screen to be burned — and only their origins are decoded
## until one proves to be inside the volume.
func apply_damage(hit: DamageHit) -> float:
	if hit == null or _tiles.is_empty():
		return 0.0
	# Nothing here is in the band this volume touches. Worth its own line before
	# the tile walk, and it is the whole reason a volume can be swept along the
	# ground continuously: it turns away the grass fields, which hold most of the
	# plants on the planet, without looking at a blade of it.
	if hit.max_plant_height > 0.0 and _shortest > hit.max_plant_height:
		return 0.0
	if hit.min_plant_height > 0.0 and _tallest < hit.min_plant_height:
		return 0.0
	var absorbed := 0.0
	var sweep := Sweep.new()
	sweep.to_world = global_transform
	var to_local := sweep.to_world.affine_inverse()
	sweep.into_local = to_local.basis
	sweep.from = to_local * hit.origin
	sweep.along = to_local.basis * (hit.toward - hit.origin)
	sweep.radius = hit.radius
	var host := planet_host()
	sweep.centre = host.global_position if host != null else Vector3.ZERO
	var tile_bound := _tile * 0.71
	# The volume reduced to a sphere, so a tile nowhere near it is turned away
	# without the capsule arithmetic. Every field is offered every volume and
	# between them they hold a few thousand streamed tiles, so this comparison
	# runs more often than anything else an ability does — which is also why it
	# reads the flat list rather than looking every tile up by its cell.
	var middle := (hit.origin + hit.toward) * 0.5
	var gross := hit.extent() + tile_bound + _tallest
	var gross_squared := gross * gross
	_ensure_tile_list()
	for tile in _tile_list:
		if tile.at.distance_squared_to(middle) >= gross_squared:
			continue
		if not hit.reaches(tile.at, tile_bound + _tallest):
			continue
		for index in tile.stands.size():
			var plant := species[index] as PlantSpecies
			if plant == null or not plant.takes_ability_damage():
				continue
			if hit.max_plant_height > 0.0 \
					and plant.height > hit.max_plant_height:
				continue
			if plant.height < hit.min_plant_height:
				continue
			var stand := _stand_of(tile, index)
			if stand == null:
				continue
			# Asked again with this species' own height in place of the field's
			# tallest. The tile above is admitted because a twenty-five metre
			# tree rooted on it could reach the volume; that says nothing about
			# the thousand blades of grass sharing the tile, and the grass is
			# what makes the loop below long.
			if not hit.reaches(tile.at, tile_bound + _standing_height(plant)):
				continue
			absorbed += _damage_stand(hit, sweep, tile, index, plant, stand)
	return absorbed


## Tallest any plant of this species grows, which is the only part of it the
## rejection tests need to know.
func _standing_height(plant: PlantSpecies) -> float:
	return plant.height * (1.0 + plant.height_variation)


func _damage_stand(hit: DamageHit, sweep: Sweep, tile: Tile, index: int,
		plant: PlantSpecies, stand: MultiMeshInstance3D) -> float:
	var to_world := sweep.to_world
	var centre := sweep.centre
	var multimesh := stand.multimesh
	# Drawn-or-not is a rendering decision. Streamed plants still occupy the
	# ground — a blast behind the camera, or one that reaches a preloaded cone
	# tile, has to find them.
	var showing := multimesh.instance_count
	if showing <= 0:
		return 0.0
	var roots: PackedVector3Array = tile.roots[index]
	showing = mini(showing, roots.size())
	if showing <= 0:
		return 0.0
	# This loop is the whole cost of an ability: a volume is offered thousands of
	# plants and cuts a dozen, so what matters is not what happens to the dozen
	# but how cheaply the rest are turned away. Everything in it is in this
	# node's own space, which is the space the roots are already cached in —
	# three vectors are brought down to it instead of a thousand roots being
	# lifted out of it.
	var from := sweep.from
	var along := sweep.along
	# A plant is a standing line, not a point, so a volume level with a canopy is
	# over the root by the whole height of the tree. This used to be answered by
	# growing the radius by that height, which on a jungle field of twenty-five
	# metre trees made a six metre shock consider everything rooted within
	# thirty-one metres of it: forty-seven thousand candidates for a hundred
	# felled trees. Every plant on a tile stands along the same up, so the gap
	# separates instead into a horizontal part, which no amount of height can
	# close, and a vertical one, which is the only part height helps with.
	var standing := (sweep.into_local * (tile.at - centre)).normalized()
	var stem := _standing_height(plant)
	var rise := along.dot(standing)
	var along_flat := along - standing * rise
	var flat_span := along_flat.length_squared()
	# The tile's single up is a chord across a curved surface, so a plant at its
	# corner leans a fraction of a degree away from it. Widened by that much of
	# its own height rather than trusting the approximation exactly.
	var reach := sweep.radius + stem * UP_APPROXIMATION
	var reach_squared := reach * reach
	var ceiling := stem + reach
	# Which plants are worth decoding, found from the cached roots alone. The
	# buffer behind them is a copy fetched back through the rendering server —
	# tens of microseconds a stand — and a volume that turns out to touch
	# nothing here must not pay for one.
	var candidates := PackedInt32Array()
	if stem * 2.0 <= sweep.radius:
		# Ground cover, where the height a plant could reach up into the volume
		# is a fraction of the volume's own radius. Splitting the gap into its
		# horizontal and vertical parts buys nothing here and the plain sphere
		# against the axis is half the arithmetic — which is the whole of the
		# difference, because this is the case that runs hundreds of thousands
		# of times when a shock crosses a meadow.
		var reach_flat := sweep.radius + stem
		var flat_squared := reach_flat * reach_flat
		var span := along.length_squared()
		for instance_index in showing:
			var offset := roots[instance_index] - from
			var closest := offset
			if span > 0.000001:
				closest = offset - along * clampf(
					offset.dot(along) / span, 0.0, 1.0)
			if closest.length_squared() < flat_squared:
				candidates.append(instance_index)
	else:
		for instance_index in showing:
			var offset := roots[instance_index] - from
			var offset_up := offset.dot(standing)
			var offset_flat := offset - standing * offset_up
			var share := 0.0
			if flat_span > 0.000001:
				share = clampf(offset_flat.dot(along_flat) / flat_span, 0.0, 1.0)
			if (along_flat * share - offset_flat).length_squared() > reach_squared:
				continue
			# How high the axis runs over this root across its length. Out of
			# reach under the plant's feet or clear over its head either way.
			var low := minf(-offset_up, rise - offset_up)
			if low > ceiling:
				continue
			var high := maxf(-offset_up, rise - offset_up)
			if high < -reach:
				continue
			candidates.append(instance_index)
	if candidates.is_empty():
		return 0.0

	var buffer := _rows_of(tile, index, multimesh)
	# Everything the loop below needs from the species and from this stand's
	# ledger, fetched once. Read per plant, these were property lookups on a
	# Resource and two nested dictionary walks for every blade of grass standing
	# under a shock, and a wide volume over jungle floor offers tens of
	# thousands of those.
	var authored := plant.authored_height()
	var base_health := maxf(plant.health, 0.0)
	var per_metre := maxf(plant.health_per_metre, 0.0)
	var absorbs := plant.damage_taken(1.0)
	var ledger := _ledger_for(tile.cell, index)
	var span := along.length_squared()
	var radius_squared := sweep.radius * sweep.radius
	var falling := hit.falloff > 0.0
	# A flat-ended cylinder is not a capsule past its caps, so the arithmetic
	# below cannot answer for one. Authored waves are rare and are left to the
	# general form.
	var capsule := hit.shape == DamageHit.Shape.CAPSULE
	var bursts := hit.plant_break_effects
	var absorbed := 0.0
	var touched := false
	for instance_index in candidates:
		var root := roots[instance_index]
		var row := instance_index * STRIDE
		var tall := Vector3(buffer[row + 1], buffer[row + 5],
			buffer[row + 9]).length() * authored
		# Both ends of the plant. A beam level with a canopy is over the root by
		# the whole height of the tree, and testing the root alone made tall
		# species immune to anything not aimed at their feet.
		var share := 0.0
		if capsule:
			var offset := root - from
			var foot := offset - along * (clampf(offset.dot(along) / span,
				0.0, 1.0) if span > 0.000001 else 0.0)
			var top := offset + standing * tall
			var head := top - along * (clampf(top.dot(along) / span,
				0.0, 1.0) if span > 0.000001 else 0.0)
			var nearest := minf(foot.length_squared(), head.length_squared())
			if nearest < radius_squared:
				share = 1.0 if not falling else lerpf(1.0, 1.0 - hit.falloff,
					sqrt(nearest) / sweep.radius)
		else:
			var world_root := to_world * root
			var world_up := (world_root - centre).normalized()
			share = maxf(hit.share_at(world_root),
				hit.share_at(world_root + world_up * tall))
		if share <= 0.0:
			continue
		var carried := float(ledger.get(instance_index, 0.0))
		if carried == BROKEN:
			continue
		var taken := hit.amount * share * absorbs
		if taken <= 0.0:
			continue
		absorbed += taken
		touched = true
		carried += taken
		var health := base_health + tall * per_metre
		if carried < health:
			ledger[instance_index] = carried
			# _char_instance, inlined: this is the branch nearly every plant
			# under a wide volume takes, and all it comes to is one array write.
			buffer[row + COLOR + 3] = 1.0 - clampf(
				carried / maxf(health, 0.001), 0.0, 1.0) * MAX_CHAR
			continue
		_mark_broken(tile.cell, index, instance_index)
		_hide_instance(buffer, instance_index)
		_disable_collider(tile, index, instance_index)
		if not bursts:
			continue
		var world_root := to_world * root
		_play_break_effect(world_root, (world_root - centre).normalized(),
			plant.impact_threshold(tall), tall,
			_break_tint(plant, buffer, instance_index), plant.break_effect)
	if touched:
		# Both sides, and this one first: writing an element of a buffer the
		# tile is also holding copies the whole stand rather than editing it,
		# so putting it back is what keeps the next hit's edits in place.
		tile.rows[index] = buffer
		multimesh.buffer = buffer
	return absorbed


## What one stand is drawing, without asking the rendering server for it.
##
## [member MultiMesh.buffer]'s getter is a round trip: it has to catch up with
## the render thread before it can answer, and that wait costs about the same
## whether the stand holds nine plants or nine thousand — half a millisecond a
## call, measured against this world. A volume swept along the ground overlaps
## tens of stands, so a single tick of a meteor charge spent twenty
## milliseconds doing nothing but waiting, and the fields holding the fewest
## plants were the worst of it: a colony of three trees per tile pays the same
## half millisecond as a tile of five thousand blades of grass.
##
## The setter has no such cost — it queues the upload and returns — so writes
## stay as they were and only the reads come from here.
func _rows_of(tile: Tile, index: int,
		multimesh: MultiMesh) -> PackedFloat32Array:
	if index < tile.rows.size():
		var kept: PackedFloat32Array = tile.rows[index]
		# A stand raised before this tile last recorded its rows, or one whose
		# instance count has moved on, is read back once and remembered.
		if kept.size() == multimesh.instance_count * STRIDE:
			return kept
	var read := multimesh.buffer
	if index < tile.rows.size():
		tile.rows[index] = read
	return read


## The damage ledger for one stand, installed if nothing has touched it before.
## Handed out whole so that the loop above can read and write it directly:
## reaching every plant's entry down through two nested dictionaries was a
## measurable share of what a wide volume over dense cover cost.
func _ledger_for(cell: Vector3i, species_index: int) -> Dictionary:
	var per_species: Dictionary = _instance_damage.get(cell, {})
	if not _instance_damage.has(cell):
		_instance_damage[cell] = per_species
	var indices: Dictionary = per_species.get(species_index, {})
	if not per_species.has(species_index):
		per_species[species_index] = indices
	return indices


## Turns off the streamed shape belonging to one destroyed instance, when this
## tile happens to be inside the collision ring. Cover with no physics — which
## is most of it — simply has nothing to switch off.
func _disable_collider(tile: Tile, species_index: int,
		instance_index: int) -> void:
	if species_index >= tile.collisions.size():
		return
	var body := _body_of(tile, species_index)
	if body == null:
		return
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		if int(shape.get_meta(IMPACT_INSTANCE_META, -1)) != instance_index:
			continue
		shape.set_meta(IMPACT_BROKEN_META, true)
		shape.set_deferred(&"disabled", true)
		return


## Writes how burned a survivor looks into the free alpha of its instance
## colour. The three colour channels are a semantic mask the plant shader reads
## for petals, paint and emission, so they cannot carry this; alpha was written
## and never read, which is exactly the channel a new per-instance signal wants.
func _char_instance(buffer: PackedFloat32Array, instance_index: int,
		share: float) -> void:
	var charred := clampf(share, 0.0, 1.0) * MAX_CHAR
	buffer[instance_index * STRIDE + COLOR + 3] = 1.0 - charred


## The breaks since this was last asked, in the same five-integer form as
## [method broken_keys], forgetting them as it answers.
##
## Drained on every peer and not only on the host, because the list exists so
## the host can tell everyone what it decided: on a client nobody reads it, and
## left undrained it would grow for the whole session.
func drain_new_breaks() -> PackedInt32Array:
	var keys := _new_breaks
	_new_breaks = PackedInt32Array()
	return keys


## Every instance this field has lost, flattened for the wire: cell x, y, z,
## species index and instance index, five entries per plant. The host sends this
## to a late joiner so they arrive in a world with the same gaps in it.
func broken_keys() -> PackedInt32Array:
	var keys := PackedInt32Array()
	for cell_key in _instance_damage:
		var cell: Vector3i = cell_key
		var per_species: Dictionary = _instance_damage[cell_key]
		for species_key in per_species:
			var indices: Dictionary = per_species[species_key]
			for instance_key in indices:
				if float(indices[instance_key]) != BROKEN:
					continue
				keys.append_array(PackedInt32Array([cell.x, cell.y, cell.z,
					int(species_key), int(instance_key)]))
	return keys


## Applies breaks decided elsewhere. Tiles that are not streamed are still
## recorded, so a plant the host felled while this peer was away is already
## missing when they walk into it.
func apply_broken_keys(keys: PackedInt32Array) -> void:
	var entry := 0
	while entry + 4 < keys.size():
		var cell := Vector3i(keys[entry], keys[entry + 1], keys[entry + 2])
		var species_index := keys[entry + 3]
		var instance_index := keys[entry + 4]
		entry += 5
		if species_index < 0 or species_index >= species.size():
			continue
		if _is_broken(cell, species_index, instance_index):
			continue
		_record_damage(cell, species_index, instance_index, BROKEN)
		_hide_broken_now(cell, species_index, instance_index)


## Regrows everything this field lost inside a sphere, and reports how many
## plants came back.
##
## Damage is deliberately permanent for the session — walking away and back does
## not un-burn a bush — so this is the one path that undoes it, for an encounter
## that resets the ground it was fought over. It works in whole tiles: the ledger
## records which instance was hit, not where it stood, and a tile is thirty-odd
## metres against an arena of a hundred. Standing tiles are retired rather than
## repaired, because a fresh sow with an empty ledger restores the plants, their
## charring and their collision in one step and is the same code every streamed
## tile already runs.
func restore_within(centre: Vector3, radius: float) -> int:
	if _instance_damage.is_empty() or radius <= 0.0 or not centre.is_finite():
		return 0
	var reach := radius + _tile * 0.71
	var reach_squared := reach * reach
	var restored := 0
	var restored_cells := {}
	for cell_key: Variant in _instance_damage.keys():
		var cell: Vector3i = cell_key
		if _ground_point(cell).distance_squared_to(centre) > reach_squared:
			continue
		var per_species: Dictionary = _instance_damage[cell]
		for species_key: Variant in per_species:
			restored += (per_species[species_key] as Dictionary).size()
		_instance_damage.erase(cell)
		restored_cells[cell] = true
		_retire(cell)
	if restored > 0:
		# A break can still be waiting for the world's next reconciliation pass
		# when an encounter resets. Broadcasting that stale key after clearing
		# the ledger would hide the plant again on every client (and on any peer
		# applying the confirmation locally), undoing the regrow.
		var pending := PackedInt32Array()
		var entry := 0
		while entry + 4 < _new_breaks.size():
			var pending_cell := Vector3i(
				_new_breaks[entry], _new_breaks[entry + 1],
				_new_breaks[entry + 2])
			if not restored_cells.has(pending_cell):
				pending.append_array(PackedInt32Array([
					_new_breaks[entry], _new_breaks[entry + 1],
					_new_breaks[entry + 2], _new_breaks[entry + 3],
					_new_breaks[entry + 4]]))
			entry += 5
		_new_breaks = pending
		# A survey is normally earned by the viewer walking onto new ground, and
		# nobody has to be walking for this to happen — the plants would sit
		# missing until someone did. This is the same nudge a range change gives.
		_since_survey = INF
		_surveyed_at = Vector3.INF
		_surveyed_ahead = Vector3.INF
	return restored


## Drops a tile so the streamer sows it again from scratch. The plants are
## placed deterministically, so what comes back stands exactly where it did.
func _retire(cell: Vector3i) -> void:
	var tile := _tiles.get(cell) as Tile
	if tile == null:
		return
	for stand in tile.stands:
		if is_instance_valid(stand):
			stand.queue_free()
	for body in tile.collisions:
		if is_instance_valid(body):
			body.queue_free()
	tile.stands.clear()
	tile.collisions.clear()
	_tiles.erase(cell)
	_tile_list_stale = true
	_dispatch_needed = true


func _hide_broken_now(cell: Vector3i, species_index: int,
		instance_index: int) -> void:
	var tile := _tiles.get(cell) as Tile
	if tile == null or species_index >= tile.stands.size():
		return
	var stand := _stand_of(tile, species_index)
	if stand == null or instance_index >= stand.multimesh.instance_count:
		return
	var buffer := _rows_of(tile, species_index, stand.multimesh)
	_hide_instance(buffer, instance_index)
	tile.rows[species_index] = buffer
	stand.multimesh.buffer = buffer
	_disable_collider(tile, species_index, instance_index)


## MultiMesh.buffer is the authoritative CPU copy for these fields. Instances
## are uploaded as complete buffers for speed, and Godot does not populate the
## per-instance getter cache from that path; get_instance_transform therefore
## returns identity transforms here. Decode the documented row layout written
## by [method _write] instead.
func _instance_transform(buffer: PackedFloat32Array,
		instance_index: int) -> Transform3D:
	var at := instance_index * STRIDE
	return Transform3D(
		Basis(
			Vector3(buffer[at], buffer[at + 4], buffer[at + 8]),
			Vector3(buffer[at + 1], buffer[at + 5], buffer[at + 9]),
			Vector3(buffer[at + 2], buffer[at + 6], buffer[at + 10])),
		Vector3(buffer[at + 3], buffer[at + 7], buffer[at + 11]))


func _hide_instance(buffer: PackedFloat32Array, instance_index: int) -> void:
	var at := instance_index * STRIDE
	for offset in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
		buffer[at + offset] = 0.0


func _break_tint(plant: PlantSpecies, buffer: PackedFloat32Array,
		instance_index: int) -> Color:
	if plant.break_effect_color.a > 0.0:
		return plant.break_effect_color
	if plant.local_light_color.a > 0.0:
		return plant.local_light_color
	var at := instance_index * STRIDE + COLOR
	var tint := Color(
		buffer[at], buffer[at + 1], buffer[at + 2], buffer[at + 3])
	var chroma := maxf(tint.r, maxf(tint.g, tint.b)) \
		- minf(tint.r, minf(tint.g, tint.b))
	if tint.a > 0.0 and (chroma > 0.05 or maxf(
			tint.r, maxf(tint.g, tint.b)) < 0.86):
		return tint
	match plant.break_effect:
		PlantSpecies.BreakEffect.WOOD:
			return Color(0.43, 0.22, 0.105, 1.0)
		PlantSpecies.BreakEffect.CRYSTAL:
			return Color(0.32, 0.78, 1.0, 1.0)
		_:
			return Color(0.34, 0.52, 0.18, 1.0)


func _play_break_effect(at: Vector3, up: Vector3, speed: float, size: float,
		tint: Color, preset: int) -> void:
	var effects := get_tree().get_first_node_in_group(&"impact_break_effects")
	if effects != null and effects.has_method(&"play_break"):
		effects.call(&"play_break", at, up, speed, size, tint, preset)


## Chooses which glowing patches near the viewer are worth one of the pooled
## lights. Only ever picks targets: [method _fade_glow_lights] is what moves the
## lights onto them, because a light that jumps is a light you see jump.
func _place_glow_lights(eye: Vector3) -> void:
	var spacing := 0.0
	for species_index in species.size():
		var plant := species[species_index] as PlantSpecies
		if plant != null and (plant.glowing_patches > 0.0
				or _night_species.has(species_index)):
			spacing = maxf(spacing, plant.glow_patch_size)
	var wanted := glow_light_limit if spacing > 0.0 else 0
	while _glow_lights.size() < wanted:
		var light := OmniLight3D.new()
		light.name = "GroundCoverGlow"
		light.light_color = Color.WHITE
		light.omni_range = glow_light_range
		light.light_energy = 0.0
		light.visible = false
		light.shadow_enabled = false
		add_child(light, false, Node.INTERNAL_MODE_BACK)
		_glow_lights.append(light)
		_glow_targets.append(Vector3.INF)
		_glow_levels.append(0.0)
		_glow_colors.append(Color.WHITE)
	for index in _glow_targets.size():
		_glow_targets[index] = Vector3.INF
		_glow_levels[index] = 0.0
		_glow_colors[index] = Color.WHITE
	if wanted == 0:
		return
	# Every remembered anchor on the nearby tiles, ordered by how far it is from
	# the viewer rather than by which tile it belongs to. Sorting tiles alone
	# was not enough: a tile is tens of metres across, so the patch that got the
	# light was whichever the scatter happened to record first, and the glowing
	# flowers a player was standing in routinely lost to ones behind them.
	# A tile holds at most GLOW_ANCHORS points, so this stays a list of tens.
	var points := PackedVector3Array()
	var levels := PackedFloat32Array()
	var source_species := PackedInt32Array()
	for tile: Tile in _tiles.values():
		if tile.glow_points.is_empty() or tile.away > glow_light_range * 5.0 \
				or not _cell_shown(tile.at, eye):
			continue
		var count := mini(
			tile.glow_points.size(),
			mini(tile.glow_levels.size(), tile.glow_species.size()))
		for index in count:
			points.append(to_global(tile.glow_points[index]))
			levels.append(tile.glow_levels[index])
			source_species.append(tile.glow_species[index])
	var order: Array[int] = []
	for index in points.size():
		order.append(index)
	order.sort_custom(func(a: int, b: int) -> bool:
		return eye.distance_squared_to(points[a]) \
			< eye.distance_squared_to(points[b]))

	var apart := spacing * 0.55
	var taken := 0
	for index in order:
		if taken >= wanted:
			break
		var point := points[index]
		var separate := true
		for other in taken:
			if point.distance_squared_to(_glow_targets[other]) < apart * apart:
				separate = false
				break
		if not separate:
			continue
		# Lifted into whatever part emits: among grass tips by default, or
		# into the bloom for the taller colony flowers.
		_glow_targets[taken] = point \
			+ (point - planet_host().global_position).normalized() * glow_light_height
		var plant := species[source_species[index]] as PlantSpecies
		_glow_levels[taken] = glow_light_energy * levels[index] \
			* plant.local_light_energy
		if plant.local_light_color.a > 0.0:
			_glow_colors[taken] = Color(
				plant.local_light_color.r,
				plant.local_light_color.g,
				plant.local_light_color.b, 1.0)
		else:
			_glow_colors[taken] = _region_light(point) \
				if glow_light_use_region_color else glow_light_color
		taken += 1


## Brings each pooled light to the patch chosen for it. A light only travels
## once it is dark, so what a player sees is a glow going out over a third of a
## second and another coming up somewhere else, rather than six lights blinking
## in place every time the field is re-surveyed.
func _fade_glow_lights(delta: float) -> void:
	var step := delta * glow_light_energy * 3.0
	for index in _glow_lights.size():
		var light := _glow_lights[index]
		var target: Vector3 = _glow_targets[index]
		var arrived := target.is_finite() \
			and light.global_position.distance_squared_to(target) < 0.01
		var toward := 0.0
		if arrived:
			toward = _glow_levels[index] * _glow_night(target) \
				* _glow_pulse(target)
		light.light_energy = move_toward(light.light_energy, toward, step)
		if arrived:
			light.light_color = light.light_color.lerp(_glow_colors[index],
				1.0 - exp(-delta * 5.0))
		light.visible = light.light_energy > 0.001
		if not arrived and light.light_energy <= 0.001 and target.is_finite():
			light.global_position = target
			light.light_color = _glow_colors[index]


## Local night at a pooled target, matching vivid_plant's sunset band. The sun's
## +Z points from the planet toward the light; Planet publishes the opposite as
## sun_direction for shaders.
func _glow_night(at: Vector3) -> float:
	if not glow_light_night_only:
		return 1.0
	var host := planet_host()
	if host == null or host.sun == null:
		return 0.0
	var up := (at - host.global_position).normalized()
	var to_sun := host.sun.global_basis.z.normalized()
	return 1.0 - smoothstep(-0.16, 0.12, up.dot(to_sun))


## A stable, asynchronous pulse for one pooled patch. Two independent hashes
## provide phase and rate, avoiding the slow re-synchronization that equal-speed
## oscillators eventually show even when they started apart.
func _glow_pulse(at: Vector3) -> float:
	if glow_light_pulse_amount <= 0.0 or glow_light_pulse_speed <= 0.0:
		return 1.0
	var phase_hash := fposmod(sin(at.dot(Vector3(0.071, 0.113, 0.167))
		+ 1.37) * 43758.5453, 1.0)
	var rate_hash := fposmod(sin(at.dot(Vector3(0.137, 0.059, 0.191))
		+ 2.11) * 24634.6345, 1.0)
	var rate := glow_light_pulse_speed * lerpf(0.82, 1.18, rate_hash)
	var seconds := float(Time.get_ticks_msec()) * 0.001
	return 1.0 + glow_light_pulse_amount \
		* sin(seconds * TAU * rate + phase_hash * TAU)


## CPU approximation of vivid_region_light for the handful of pooled lights.
## The shader adds low-frequency noise to soften the borders; omitting that
## noise here keeps this cheap and still picks the same broad coloured quadrant.
func _region_light(at: Vector3) -> Color:
	var unit := (at - planet_host().global_position).normalized()
	var axis_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_axis", {})
	var turns_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_turns", {})
	var phase_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_phase", {})
	var chroma_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_chroma", {})
	var axis: Vector3 = axis_setting.get("value", Vector3.UP)
	axis = axis.normalized()
	var hint := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var side := axis.cross(hint).normalized()
	var front := axis.cross(side)
	var longitude := atan2(unit.dot(side), unit.dot(front)) / TAU
	var latitude := asin(clampf(unit.dot(axis), -1.0, 1.0)) / PI
	var turns := float(turns_setting.get("value", 3.0))
	var phase := float(phase_setting.get("value", 0.0))
	var hue := fposmod(longitude * turns + latitude * 0.5 + phase, 1.0)
	var spectrum := Vector3(
		0.5 + 0.5 * cos(TAU * hue),
		0.5 + 0.5 * cos(TAU * (hue + 0.33)),
		0.5 + 0.5 * cos(TAU * (hue + 0.67)))
	var chroma := float(chroma_setting.get("value", 0.85))
	var color := Vector3.ONE.lerp(spectrum, chroma)
	return Color(color.x, color.y, color.z, 1.0)


# --- Sowing -----------------------------------------------------------------

## Grows one tile. Runs on a worker thread: it reads the height field, this
## node's tangent frame and the species, and writes only to the tile handed to
## it. [method PlanetShape.elevation] is a pure function and is the same call the
## chunk meshes are built from on this same pool.
func _sow(tile: Tile) -> void:
	var buffers: Array[PackedFloat32Array] = []
	var points := PackedVector3Array()
	var levels := PackedFloat32Array()
	var light_species := PackedInt32Array()
	for index in species.size():
		var plant := species[index] as PlantSpecies
		var detail := tile.detail[index] if index < tile.detail.size() else 1.0
		buffers.append(PackedFloat32Array() if plant == null or detail <= 0.0
			else _scatter(index, plant, _patches[index], _glows[index],
				tile.cell, detail, points, levels, light_species))
	tile.buffers = buffers
	tile.sow_glow_points = points
	tile.sow_glow_levels = levels
	tile.sow_glow_species = light_species


func _scatter(species_index: int, plant: PlantSpecies, patch: FastNoiseLite,
		glow_noise: FastNoiseLite, cell: Vector3i, detail: float,
		glow_points: PackedVector3Array,
		glow_levels: PackedFloat32Array,
		glow_species: PackedInt32Array) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	# The tile's own seed, so a tile grows the same whichever order the field is
	# walked in and whichever peer is walking it.
	rng.seed = hash(Vector3i(cell.y ^ cell.x * 73856093,
		cell.z ^ cell.x * 19349663, plant.random_seed))
	var area := _grid.area(cell) if global_cover else _tile * _tile
	var clump := maxi(plant.clump_count, 1)
	# The density is quoted per plant, so the number of spots to test is that
	# divided by how many plants a spot grows.
	# Scaled by the band the tile was planned at. The candidate sequence is
	# untouched by this: stopping the loop early cannot change the spots the
	# earlier turns of it drew, which is what lets a finer sow later reproduce
	# this one exactly and add to it.
	var expected_tries := plant.per_square_metre * area / float(clump) \
		* detail
	var tries := int(round(expected_tries))
	if plant.fractional_density:
		tries = floori(expected_tries)
		if rng.randf() < expected_tries - float(tries):
			tries += 1
	var buffer := PackedFloat32Array()
	buffer.resize(tries * clump * STRIDE)
	# Where the bare ground starts. Calibrated against the patch field's real
	# distribution rather than its nominal range, so the share is honest — see
	# [method PlantSpecies.patch_level]. The band above it is what gives a patch
	# a soft edge instead of a coastline.
	var bare := PlantSpecies.patch_level(plant.bare_share)
	var all_instances_cast := _night_species.has(species_index)
	var grown := 0
	for _try in tries:
		var at := _direction_in_cell(cell, rng.randf(), rng.randf())
		var here := at * _radius
		if rng.randf() > smoothstep(bare, bare + PlantSpecies.PATCH_EDGE,
				patch.get_noise_3d(here.x, here.y, here.z)):
			continue
		# The clearance, thinning in rather than stopping at a line. Done here
		# and not in `_ground` because it is the one rule that is a probability
		# rather than a yes: everything else about a spot either suits a plant
		# or does not.
		if _clearance_rejects(at, rng.randf()):
			continue
		var growth := _growth(plant, at)
		if is_nan(growth.w):
			continue
		var tint := Color(growth.x, growth.y, growth.z, 1.0) \
			if plant.terrain_tint else Color.WHITE
		var glow := 0.0
		if plant.glowing_patches > 0.0 and glow_noise != null:
			# Smooth Simplex spends very little of its area near +/-1, so using
			# the mathematical range as a percentile would make a 12% setting
			# effectively zero. These empirical shoulders keep "some patches"
			# literal while preserving broad coherent islands.
			var threshold := lerpf(0.62, -0.62, plant.glowing_patches)
			glow = smoothstep(threshold - 0.12, threshold + 0.12,
				glow_noise.get_noise_3d(here.x, here.y, here.z))
		# The clump's own tangent frame, so its members spread across the ground
		# rather than through it.
		var east := at.cross(Vector3.UP if absf(at.y) < 0.9 else Vector3.RIGHT).normalized()
		var north := at.cross(east)
		for member in clump:
			var up := at
			var ground := growth.w
			if member > 0:
				# Square-rooted, so the members are spread evenly over the
				# clump's disc instead of piling into its middle.
				var spin := rng.randf() * TAU
				var out := sqrt(rng.randf()) * plant.clump_radius / _radius
				up = (at + (east * cos(spin) + north * sin(spin)) * out).normalized()
				if plant.clump_resurvey:
					# Monumental geology can spread hundreds of metres. Each
					# member therefore proves its own biome, slope and broad
					# footing rather than borrowing the centre's answer.
					var member_growth := _growth(plant, up)
					if is_nan(member_growth.w):
						continue
					ground = member_growth.w
				else:
					# One sample rather than the eight `_growth` costs: ordinary
					# plant clumps stay within the radius the accepted spot
					# already vouched for.
					ground = _shape.elevation(up, _spacing)
					# Do not let a small clump hang over a gully lip merely
					# because its middle happened to land beside it.
					if ground < plant.above_water or ground > plant.below \
							or absf(ground - growth.w) > plant.steady_within:
						continue
			# Clamped at the spread rather than left as a plain normal. Over a
			# few thousand plants the tails of an unclamped one are reached
			# often enough to matter, and what they produce is a seedling and a
			# plant twice anyone's height standing next to each other.
			var tall := plant.height * (1.0 + clampf(
				rng.randfn(0.0, plant.height_variation * 0.5),
				-plant.height_variation, plant.height_variation))
			# A few degrees off vertical, because nothing that grew out of the
			# ground is plumb and a field of plumb ones reads as a placement
			# grid.
			var tipped := _upright(up)
			if plant.tilt > 0.0:
				tipped = Basis(tipped.z,
					deg_to_rad(rng.randfn(0.0, plant.tilt * 0.5))) * tipped
			var stood := _into_local * Transform3D(
				(Basis(up, rng.randf() * TAU) * tipped)
					.scaled(Vector3(plant.width_scale, 1.0, plant.width_scale)
						* plant.scale_for(tall)),
				# The same buried origin reaches the MultiMesh and its streamed
				# collision, so no invisible shelf remains below a sunk rock.
				up * (_radius + ground - plant.ground_sink_for(tall)))
			# Night-emissive plants cast light even when they do not use the
			# separate daytime glowing-patch channel. This is the path coral
			# was missing: its mesh emitted, but no point was ever offered to
			# the pool that lights the bed, swimmer and nearby objects.
			var cast_level := 1.0 if all_instances_cast else glow
			if cast_level > 0.55:
				_remember_glow(glow_points, glow_levels, glow_species,
					stood.origin, cast_level, plant.glow_patch_size,
					species_index)
			_write(buffer, grown, stood, rng, tint, glow,
				plant.glowing_patches > 0.0)
			grown += 1
	buffer.resize(grown * STRIDE)
	# Rank, once the tile knows how many it grew. Candidates are drawn in random
	# order, so the order they were accepted in is already a random permutation
	# of the tile and ranking by it needs no shuffle: the first tenth of the
	# buffer is a tenth of the tile spread evenly over it, which is exactly what
	# the thinning wants to be left with.
	#
	# Divided by what a full sow would have grown rather than by what this one
	# did, so a tile sown at an eighth ranks its plants across the first eighth
	# of the scale instead of spreading them over all of it. Both the shader and
	# _dress read rank as a share of the whole tile, and renormalising here would
	# tell them a sparse tile was a full one.
	var full := maxf(float(grown) / maxf(detail, 0.0001), 1.0)
	for index in grown:
		buffer[index * STRIDE + RANK] = (float(index) + 0.5) / full
	return buffer


## Records a glowing spot for the pooled lights, keeping each species' list
## short and its entries apart. Species stay separate because colour is part of
## the source: a nearby blue coral must not be collapsed into an earlier pink
## candidate merely because their branches share a tile.
func _remember_glow(points: PackedVector3Array, levels: PackedFloat32Array,
		owners: PackedInt32Array, at: Vector3, level: float, apart: float,
		species_index: int) -> void:
	var spacing := maxf(apart * 0.6, 1.0)
	var held := 0
	for index in points.size():
		if owners[index] != species_index:
			continue
		held += 1
		if points[index].distance_squared_to(at) < spacing * spacing:
			# Keep the brightest witness for a patch already known about.
			if level > levels[index]:
				points[index] = at
				levels[index] = level
			return
	if held >= GLOW_ANCHORS:
		return
	points.append(at)
	levels.append(level)
	owners.append(species_index)


func _write(buffer: PackedFloat32Array, index: int, stood: Transform3D,
		rng: RandomNumberGenerator, tint: Color, glow: float,
		glow_custom: bool) -> void:
	var at := index * STRIDE
	var basis := stood.basis
	var origin := stood.origin
	buffer[at] = basis.x.x
	buffer[at + 1] = basis.y.x
	buffer[at + 2] = basis.z.x
	buffer[at + 3] = origin.x
	buffer[at + 4] = basis.x.y
	buffer[at + 5] = basis.y.y
	buffer[at + 6] = basis.z.y
	buffer[at + 7] = origin.y
	buffer[at + 8] = basis.x.z
	buffer[at + 9] = basis.y.z
	buffer[at + 10] = basis.z.z
	buffer[at + 11] = origin.z
	buffer[at + COLOR] = tint.r
	buffer[at + COLOR + 1] = tint.g
	buffer[at + COLOR + 2] = tint.b
	buffer[at + COLOR + 3] = tint.a
	# Rank is filled in once the tile is finished; the other three are the
	# plant's own character and are decided here.
	buffer[at + RANK + 1] = rng.randf()
	buffer[at + RANK + 2] = glow if glow_custom else rng.randf()
	buffer[at + RANK + 3] = rng.randf()


## The elevation a plant would stand at, or NAN if this is nowhere to grow. One
## return for every rule, so a caller cannot use a height that failed them.
##
## The four neighbours are read once and answer two questions: their spread is
## whether the ground is lumpy at the scale of the plant, and their differences
## are its slope. Asking [method PlanetShape.normal_at] for the slope instead
## would be four more samples for a reading taken at the wrong scale — the
## terrain's, not the plant's.
func _growth(plant: PlantSpecies, at: Vector3) -> Vector4:
	var here := _shape.elevation(at, _spacing)
	if here < plant.above_water or here > plant.below:
		return Vector4(1.0, 1.0, 1.0, NAN)
	var wet := _shape.sample(at)
	if float(wet["river"]) > 0.0 or float(wet["lake"]) > 0.0:
		return Vector4(1.0, 1.0, 1.0, NAN)
	var arid := float(wet.get("arid", 0.0))
	var frozen := _shape.frost(at)
	if arid < plant.minimum_arid or arid > plant.maximum_arid \
			or frozen < plant.minimum_frost or frozen > plant.maximum_frost:
		return Vector4(1.0, 1.0, 1.0, NAN)
	var east := at.cross(Vector3.UP if absf(at.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := at.cross(east)
	var step := plant.steady_over / _radius
	var behind := _shape.elevation((at - east * step).normalized(), _spacing)
	var ahead := _shape.elevation((at + east * step).normalized(), _spacing)
	var left := _shape.elevation((at - north * step).normalized(), _spacing)
	var right := _shape.elevation((at + north * step).normalized(), _spacing)
	for near: float in [behind, ahead, left, right]:
		if near < plant.above_water or absf(near - here) > plant.steady_within:
			return Vector4(1.0, 1.0, 1.0, NAN)
	var run := plant.steady_over * 2.0
	var gradient := Vector2(ahead - behind, right - left) / run
	if gradient.length() > tan(deg_to_rad(plant.max_slope)):
		return Vector4(1.0, 1.0, 1.0, NAN)
	var tint := Color.WHITE
	if plant.ground_layer != PlantSpecies.Ground.ANYWHERE or plant.terrain_tint:
		var normal := (at - east * gradient.x - north * gradient.y).normalized()
		tint = _shape.color_at(at, here, normal)
		if not _terrain_claims(at, here, normal, tint,
				plant.ground_layer, plant.minimum_claim):
			return Vector4(1.0, 1.0, 1.0, NAN)
	return Vector4(tint.r, tint.g, tint.b, here)


## Compatibility helper used by placement diagnostics.
func _ground(plant: PlantSpecies, at: Vector3) -> float:
	return _growth(plant, at).w


## Which single rule turned a spot down, or "grows" when none did.
##
## [method _growth] deliberately answers only yes or no, because placement has
## no use for a reason and paying for one per candidate would be wasteful. A
## barren biome, though, is almost always one rule set slightly wrong, and
## without a name for it the search is a guess over a dozen numbers. This is the
## same ladder in the same order, reporting the rung it stopped on.
func habitat_reason(plant: PlantSpecies, at: Vector3) -> StringName:
	var here := _shape.elevation(at, _spacing)
	if here < plant.above_water:
		return &"too low"
	if here > plant.below:
		return &"too high"
	var wet := _shape.sample(at)
	if float(wet["river"]) > 0.0 or float(wet["lake"]) > 0.0:
		return &"inland water"
	var arid := float(wet.get("arid", 0.0))
	var frozen := _shape.frost(at)
	if arid < plant.minimum_arid:
		return &"too damp"
	if arid > plant.maximum_arid:
		return &"too arid"
	if frozen < plant.minimum_frost:
		return &"too warm"
	if frozen > plant.maximum_frost:
		return &"too frozen"
	var east := at.cross(Vector3.UP if absf(at.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := at.cross(east)
	var step := plant.steady_over / _radius
	var behind := _shape.elevation((at - east * step).normalized(), _spacing)
	var ahead := _shape.elevation((at + east * step).normalized(), _spacing)
	var left := _shape.elevation((at - north * step).normalized(), _spacing)
	var right := _shape.elevation((at + north * step).normalized(), _spacing)
	for near: float in [behind, ahead, left, right]:
		if near < plant.above_water:
			return &"waterside"
		if absf(near - here) > plant.steady_within:
			return &"lumpy"
	var run := plant.steady_over * 2.0
	var gradient := Vector2(ahead - behind, right - left) / run
	if gradient.length() > tan(deg_to_rad(plant.max_slope)):
		return &"steep"
	if plant.ground_layer != PlantSpecies.Ground.ANYWHERE or plant.terrain_tint:
		var normal := (at - east * gradient.x - north * gradient.y).normalized()
		var tint := _shape.color_at(at, here, normal)
		if not _terrain_claims(at, here, normal, tint,
				plant.ground_layer, plant.minimum_claim):
			return &"wrong ground"
	return &"grows"


## CPU form of vivid_terrain's four material claims. A layer is accepted when it
## is one of the two the shader actually samples, not merely when it scores
## something: the terrain draws the best two and blends them, so a species that
## insisted on winning outright would refuse half the ground its own material is
## visibly painted on. Grass, in particular, is the fallback everywhere neutral
## flat country claims nothing else.
##
## Public wrapper for sparse props that need to agree with the same painted
## layer without becoming a GroundCover species themselves. Trees use it because
## their collision bodies make them intentionally too sparse and too stateful
## for a plant MultiMesh tile.
func terrain_claims(at: Vector3, height: float, normal: Vector3,
		biome: Color, layer: PlantSpecies.Ground, minimum: float) -> bool:
	return _terrain_claims(at, height, normal, biome, layer, minimum)


func _terrain_claims(at: Vector3, height: float, normal: Vector3,
		biome: Color, layer: PlantSpecies.Ground, minimum: float) -> bool:
	if layer == PlantSpecies.Ground.ANYWHERE:
		return true
	var brightest := maxf(maxf(biome.r, biome.g), biome.b)
	var darkest := minf(minf(biome.r, biome.g), biome.b)
	var chroma := brightest - darkest
	var green := clampf((biome.g - maxf(biome.r, biome.b)) * 7.0, 0.0, 1.0)
	var red := clampf((biome.r - maxf(biome.g, biome.b)) * 7.0, 0.0, 1.0)
	var grey := 1.0 - clampf(chroma * 7.0, 0.0, 1.0)
	var cool := clampf((biome.b - biome.r) * 7.0, 0.0, 1.0)
	var pale := maxf(grey, cool) * clampf((brightest - 0.7) * 7.0, 0.0, 1.0)
	var frozen := _shape.frost(at)
	var shore := 1.0 - smoothstep(0.0, 7.0, height)
	var ice := maxf(pale, frozen * 1.3)
	var sand := (red + shore) * (1.0 - minf(ice, 1.0))
	var slope := 1.0 - clampf(normal.dot(at), 0.0, 1.0)
	var cliff := smoothstep(0.22, 0.55, slope)
	var stone := maxf(grey - pale, 0.0) + cliff * 1.1
	var grass := maxf(green, 0.3 - maxf(maxf(sand, stone), ice))
	var scores := [grass, sand, stone, ice]
	var mine: float = scores[layer - 1]
	if mine < minimum:
		return false
	var ahead := 0
	for index in scores.size():
		if index != layer - 1 and float(scores[index]) > mine:
			ahead += 1
	return ahead <= 1


# --- The frame the field is laid out in -------------------------------------

## Tile coordinates of a world position, by projecting it into the tangent plane
## this node's grid is ruled on. Approximate at the edges of a large field — a
## sphere does not have a flat grid on it — but the plants themselves are placed
## by normalising back onto the sphere, so the approximation costs the survey a
## metre at the corners and costs the field nothing.
func _cell_of(at: Vector3) -> Vector3i:
	var host := planet_host()
	var up := (host.to_local(at)).normalized()
	if global_cover:
		return _grid.key_for(up)
	var offset := up - _centre * _centre.dot(up)
	return Vector3i(LOCAL_FACE,
		floori(offset.dot(_east) * _radius / _tile),
		floori(offset.dot(_north) * _radius / _tile))


## The middle of a tile, on the ground, in world metres.
func _ground_point(cell: Vector3i) -> Vector3:
	var at := _direction_in_cell(cell, 0.5, 0.5)
	var host := planet_host()
	return host.to_global(at * (_radius + _shape.elevation(at, _spacing)))


func _direction_in_cell(cell: Vector3i, across: float, down: float) -> Vector3:
	if global_cover:
		return _grid.direction_in(cell, across, down)
	var u := (float(cell.y) + across) * _tile
	var v := (float(cell.z) + down) * _tile
	return (_centre + (_east * u + _north * v) / _radius).normalized()


func _prepare_clearance() -> void:
	_keep_outs.clear()
	var paths: Array[NodePath] = [clear_of]
	paths.append_array(additional_clear_of)
	for path in paths:
		var node := get_node_or_null(path) as SurfaceAnchor
		if node != null:
			_keep_outs.append(node.direction.normalized())
	_keep_cos = cos(keep_back / _radius)
	_keep_edge = cos(keep_back * keep_back_fade / _radius)


func _clearance_rejects(at: Vector3, random: float) -> bool:
	if PatchCity.flora_covers(at):
		return true
	var cleared := 0.0
	for keep_out in _keep_outs:
		cleared = maxf(cleared,
			smoothstep(_keep_edge, _keep_cos, at.dot(keep_out)))
	return random > 1.0 - cleared


func _city_blocks(at: Vector3) -> bool:
	var toward := at.normalized()
	for index in _block_centres.size():
		if toward.dot(_block_centres[index]) >= _block_coss[index]:
			return true
	return false


## Drops streamed tiles that overlap paved city ground so they sow again
## without plants on the road or district pads.
func replant_around(direction: Vector3, radius_m: float) -> void:
	if _shape == null:
		return
	_since_survey = INF
	_surveyed_at = Vector3.INF
	_surveyed_ahead = Vector3.INF
	if _tiles.is_empty():
		return
	var host := planet_host()
	if host == null:
		return
	var at := host.to_global(
		direction * (_radius + _shape.elevation(direction, _spacing)))
	var reach := radius_m + _tile
	var drop: Array[Vector3i] = []
	for cell: Vector3i in _tiles.keys():
		var tile := _tiles[cell] as Tile
		if tile.at.distance_to(at) > reach:
			continue
		if _tile_hits_city(cell):
			drop.append(cell)
	for cell in drop:
		_retire(cell)


func _tile_hits_city(cell: Vector3i) -> bool:
	for sample in [
			Vector2(0.5, 0.5),
			Vector2(0.2, 0.2), Vector2(0.8, 0.2),
			Vector2(0.2, 0.8), Vector2(0.8, 0.8),
	]:
		if PatchCity.flora_covers(_direction_in_cell(cell, sample.x, sample.y)):
			return true
	return false


# --- What the shaders are told ----------------------------------------------

func _publish_wind() -> void:
	var up := direction.normalized()
	var heading := Basis(up, deg_to_rad(wind_heading)) * _upright(up) * Vector3.FORWARD
	var host := planet_host()
	if host != null:
		heading = host.global_basis * heading
	RenderingServer.global_shader_parameter_set(&"wind_direction", heading.normalized())
	RenderingServer.global_shader_parameter_set(&"wind_strength", wind_strength)


## Where the picture is drawn from, and who is walking through the plants.
##
## The lag is the whole of the animation. A plant's bend is a function of these
## four positions and nothing else — there is no per-plant state anywhere to
## ease toward a target — so easing the positions instead is what turns an
## instant response into one that takes a third of a second to arrive and as
## long to let go.
func _publish_walkers(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if _pushed_frame == frame:
		return
	_pushed_frame = frame
	var host := planet_host()
	if host != null:
		RenderingServer.global_shader_parameter_set(&"viewer_point",
			host.to_global(host.viewer_position()))

	var chase := 1.0 - exp(-delta / maxf(push_lag, 0.001))
	var live := {}
	var slot := 0
	# Every body, not just the local one, and being right about that costs
	# nothing: the bend is a function of positions all peers already agree on,
	# so plants bend under somebody else's feet on your screen too, with nothing
	# sent.
	for node in get_tree().get_nodes_in_group(&"network_players"):
		var body := node as Node3D
		if body == null:
			continue
		var id := body.get_instance_id()
		var lagged: Vector3 = _pushed.get(id, body.global_position)
		lagged = lagged.lerp(body.global_position, chase)
		live[id] = lagged
		if slot < 4:
			RenderingServer.global_shader_parameter_set(
				&"walker_%d" % slot, Vector4(lagged.x, lagged.y, lagged.z, push_reach))
			slot += 1
	# Dropped rather than left to age out, so a player who left does not hold a
	# dent in the field where they were standing.
	_pushed = live
	while slot < 4:
		RenderingServer.global_shader_parameter_set(&"walker_%d" % slot, Vector4.ZERO)
		slot += 1
