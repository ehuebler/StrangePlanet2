@tool
class_name Planet
extends Node3D

## A spherical world drawn as a cube-sphere quadtree that refines toward a viewer.
##
## The whole surface at walkable resolution is hundreds of millions of triangles,
## so only the ground near the viewer is ever built at full detail: each of the
## cube's six faces is a quadtree that splits while the chunk it covers is nearer
## than [member split_ratio] times its own width. Chunk meshes are built on worker
## threads and handed to the scene a few per frame, because building one on the
## main thread is a visible hitch.
##
## Cracks between neighbours at different depths are covered by skirts — a ring of
## vertices dropped below the surface — rather than by stitching, which would make
## every chunk depend on when its neighbours happened to finish.
##
## The terrain itself lives in [PlanetShape]; this file only decides how much of it
## to build and when.
##
## It is also the one writer of the planet frame — the global shader parameters
## that tell the ground, the props standing on it, the sky and the atmosphere
## shell where the planet is and which way its colour wheel is turned. They are
## declared in project.godot's [code][shader_globals][/code] and described in
## [code]shaders/vivid/README.md[/code]; nothing else should write them.

const SURFACE_MATERIAL := preload("res://game/planet/planet_surface.tres")
const ATMOSPHERE_MATERIAL := preload("res://game/planet/planet_atmosphere.tres")
const CLOUD_MATERIAL := preload("res://game/planet/planet_clouds.tres")
## Terrain occupies visual layer two so its own emissive-bounce light pool can
## exclude the emitter while still reaching ordinary layer-one world objects.
const TERRAIN_RENDER_LAYER := 1 << 1

## Outward normal, then the u and v axes of each cube face's [-1, 1] square.
## u cross v equals the normal on every face, so one winding order serves all six.
const FACES: Array[Array] = [
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]

@export var shape: PlanetShape

@export_group("Detail")
## Quads along one edge of an ordinary chunk. Total triangles per chunk is twice
## its square, so this trades chunk count against triangles inside each one.
## Shallow chunks may multiply it through [member far_detail_depth].
@export_range(4, 48, 2) var chunk_resolution := 16
## Minimum *visual* depth of the planet seen from far away. The quadtree still
## begins at depth 0 so its six root meshes can cover the globe immediately, but
## depths below this use proportionally more quads: with 3, depth 0 uses 128 per
## edge, depth 1 uses 64, depth 2 uses 32 and depth 3 uses 16. All four therefore
## describe the same depth-3 grain and replacing one with the next causes no
## coarse-to-medium texture/geometry step. Deeper levels refine normally up to
## [member max_depth]. The live world sets 4, giving 256/128/64/32/16 and a
## 49 m far grain while leaving the finest 1.5 m grain unchanged.
##
## Kept scene-configurable rather than made the universal default because tiny
## standalone harness planets do not need a high-resolution root face.
@export_range(0, 4) var far_detail_depth := 0
## Deepest subdivision. Vertex spacing at the surface is
## (pi / 2) * radius / (2 ^ max_depth) / chunk_resolution — about 1.5 m at the
## defaults, which is finer than a footstep.
@export_range(0, 12) var max_depth := 9
## A chunk splits while the viewer is nearer than this many chunk widths. The
## scene's baseline: [member detail_level] scales it, and `statistics()["reach"]`
## reports what the two came to.
@export_range(0.5, 6.0) var split_ratio := 2.0
## Render distance, as the player's settings offer it, scaling [member
## split_ratio] — the one dial in here worth putting in a menu, because it is the
## only one that trades a visible thing for frames rather than trading one kind of
## hitch for another.
##
## What it moves is where the ground stops being sharp, not how much of the planet
## is on screen: the whole visible cap is always drawn, coarser with distance, and
## no level here removes any of it. Cost is roughly the square of the scale, since
## it is an area of ground being held at each level of detail. With the live
## world's depth-4 far grain and 2.2 scene ratio, `_perf_test.tscn -- --distance`
## measures about 900k, 1.01M and 1.30M triangles from low air. Most of that is
## the new coarse floor shared by all three levels; switching Normal to Far adds
## only the refinement beyond it.
##
## Three rather than four. The old 2.4 level was measured and dropped: it cost
## roughly twice the collision bodies and could not be told from 1.6 in a
## photograph from either the air or the ground. A level nobody can see is a
## level that only costs.
const DETAIL_LEVELS: Array[Dictionary] = [
	{"label": "Near", "scale": 0.6},
	{"label": "Normal", "scale": 1.0},
	{"label": "Far", "scale": 1.6},
]
## Index into [constant DETAIL_LEVELS]. Written by the settings and by harnesses;
## takes effect on the next walk of the quadtree, which coarsens or refines the
## tree that is already standing rather than throwing it away.
var detail_level := 1
## How deep a chunk's skirt hangs, as a share of the chunk's width. It only has to
## cover the step between two subdivision levels, and every metre past that is a
## dark wall on show wherever the neighbour is coarser.
@export_range(0.0, 0.5) var skirt_scale := 0.12

@export_group("Budget")
## Meshes handed to the scene per frame. Each one is an ArrayMesh upload.
@export_range(1, 64) var applies_per_frame := 12
## Chunk builds allowed on the thread pool at once.
##
## It was 4 for as long as a build was GDScript, because twelve at once starved
## the main thread badly enough to cost 35 ms a frame on a 24-core machine: work
## moved to a pool is off the frame but not off the CPU. A build is now 0.9 ms of
## native code instead of 9.4 ms of interpreted, so twenty-four of them cost less
## CPU than four used to.
##
## It is also a throughput ceiling and not only a concurrency cap, which is the
## part that is easy to miss: finished tasks are collected once a frame, so the
## pool can never deliver more than this many chunks per frame however fast a
## build is. At 4 that was 240 chunks a second at 60 fps — exactly the rate
## arriving somewhere new was converging at, while the workers sat 95% idle.
##
## Twelve rather than the twenty-four that converges fastest. Past about this the
## extra supply is spent on churn rather than on arrival: crossing at 200 m/s
## built 8400 chunks at 24 against 5960 at 10, for the same ground and the same
## triangle count standing still.
@export_range(1, 64) var pending_limit := 12
## Chunk splits allowed per frame. Placing a chunk's four children means asking
## the height field where each of them sits, and a flight at 200 m/s crosses
## enough ground to split whole subtrees in a single frame — which was worth 48 ms
## of a 62 ms hitch before this bounded it. Refinement then lags a fast viewer by
## a few frames, which costs nothing visible: the coarse ancestor keeps its mesh
## until every child has one, so the ground is blurred rather than missing.
##
## Raised from 8 once two things made it safe: the budget is now spent
## nearest-first rather than in tree order, so it buys ground the viewer is
## actually near, and `_grow` withholds it entirely when the pool cannot keep up.
## It is also what bounds how fast the tree can *deepen* — a level costs at least
## one walk, so arriving somewhere new that needs five levels takes five of them,
## and a budget too small to finish a level in one walk multiplies that out.
@export_range(1, 64) var splits_per_frame := 26
## Collision bodies built per frame. `ConcavePolygonShape3D.set_faces` builds its
## BVH on the main thread, so this is a main-thread cost like the mesh uploads and
## it has to be paid in instalments for the same reason. Ground that has not been
## given a body yet is caught by the player's own height-field check.
@export_range(1, 32) var bodies_per_frame := 8
## How often the quadtree is walked, in times a second.
##
## Every pass over it is GDScript across about a thousand nodes and costs a few
## milliseconds, and there are two of them — deciding what to split and deciding
## what to draw. Run once a frame at 300 fps that was most of the frame, and it
## bought nothing while standing still: which chunk deserves splitting does not
## change between frames three milliseconds apart.
##
## Finished meshes are still handed to the scene every frame — that part is a
## tenth of a millisecond and it is what puts new ground on screen.
@export_range(5, 240) var lod_updates_per_second := 30
## Faster quadtree walk used only while the viewer is crossing the ground fast.
##
## At 1000 m/s the ordinary 30 Hz walk moves its refinement corridor in 33 m
## jumps. Forty-five makes those steps 22 m while leaving a parked planet at the
## cheaper rate above. `dev/_perf_test.gd -- --speed=1000 --lodhz=45` measured
## no dropped frames and kept depth 8 or 9 underfoot throughout the crossing.
@export_range(5, 240) var fast_lod_updates_per_second := 45
## Speed band over which the walk rate eases from ordinary to fast. It starts
## above every normal sprint, so walking and the 18 m/s grounded gait pay
## nothing; by sustained flight the predictive corridor is fully responsive.
@export var fast_lod_from_speed := 80.0
@export var fast_lod_at_speed := 300.0

@export_group("Lead")
## Seconds of travel the detail is built ahead of the viewer.
##
## Ground takes time to appear — a chunk is queued, waits for a slot on the pool,
## is built there, and is then handed to the scene a few per frame — and all of
## that happens *after* the viewer is close enough to want it. Standing still that
## is invisible. Crossing the ground it is the whole complaint: the detail arrives
## where you were, and at 200 m/s where you were is a second behind you.
##
## So the refine pass measures its distances to the short path from where the
## viewer is to where it will be in this many seconds, rather than to the point it
## occupies. Chunks along that path are split, queued and built before they are
## arrived at, and `_dispatch` orders the queue by the same distance, so the
## ground being flown into is also what the pool builds first.
##
## It is a *time* and not a distance because what it has to cover is a latency.
## Setting it to zero restores the old behaviour exactly.
@export_range(0.0, 3.0, 0.05) var lead_time := 0.8
## The furthest ahead the detail may be built, in metres.
##
## The cap is what keeps this from being expensive. The region refined is a
## capsule rather than a sphere, so what the lead costs is the ground swept along
## it — nothing at all when standing still, and bounded by this when crossing at
## `fly_speed`, where `lead_time` alone would ask for a kilometre.
## Raised from 300 m once the build got cheap enough to fill it. At 300 the cap,
## not `lead_time`, was what a fast viewer actually got: a second of warning was
## clipped to a third of one at `fly_speed`, which is most of the way back to
## having no lead at all.
@export_range(0.0, 2000.0, 10.0) var lead_distance := 1000.0
## Seconds the measured velocity is smoothed over. The refine pass is the most
## expensive thing in here, so the point it is centred on must not jitter: a
## velocity read off two positions one walk apart is noisy enough to swing the
## whole detail region every pass.
const LEAD_SMOOTHING := 0.35
## Below this speed, in m/s, there is no lead at all. A walk covers less ground in
## `lead_time` than a chunk is wide, so leading it would only add cost.
const LEAD_MIN_SPEED := 8.0
## A step faster than this, in m/s, is a teleport rather than travel — a spawn, a
## harness placing the viewer, a respawn across the planet. Fed to the smoothing
## it would point the lead at wherever the viewer came from for the better part of
## a second, so the reading is thrown away and the drift restarted instead.
const LEAD_TELEPORT_SPEED := 2000.0
## How far the ground has to fall, in metres, before the colliders over it are
## dropped ahead of the rebuild rather than left standing. Roughly a stride: a
## cut shallower than this is a step to walk down, and the stale body sitting a
## few centimetres proud of the new ground for a few frames is not something
## anyone can feel. See [method _mark_stale] for what dropping one costs.
const COLLIDER_DROP := 0.5
## How many chunks may be queued for a mesh, as a multiple of the pool's width,
## before the tree stops growing. Some queue is wanted — it is what keeps a slot
## from ever standing idle — so this is a backlog several builds deep and not a
## demand that the pool be caught up.
##
## It is also the number that decides how long arriving somewhere new takes to
## sharpen, and the two jobs pull opposite ways, which is why it is a dial rather
## than the constant it started as. A level near the viewer is a couple of hundred
## chunks and none of it is drawn until all of it is built, so a mark below that
## makes each level wait for the one under it to finish everywhere: at 8 the
## ground underfoot climbed one level every 1.2 s and took 5.5 s to sharpen.
@export_range(1, 200) var queue_depth := 8

## Letting a few splits through while the queue is past that mark looks like the
## obvious way to get detail to the player's feet sooner, and it is a trap worth
## recording: spent nearest-first, a small floor deepens **one chain** rather than
## one area, because the nearest child of the nearest chunk is nearest again. Its
## three siblings never get built while the pool is busy, `_show` needs a level
## fully covered before it may draw it, and a spike covers nothing — so the ground
## underfoot fell back to a depth 2 ancestor and stayed there for the whole eight
## seconds. Coverage is the quantity that matters here, never depth.

@export_group("Collision")
## Leaf chunks nearer than this get a collision body. Everything past it is
## scenery, which is why this must comfortably exceed anything that walks.
##
## Distance is the only test. Every chunk carries its collision soup whatever
## depth it is at, which was not true for a long time: builds were also gated on
## being within two levels of [member max_depth], on the reasoning that a coarse
## chunk is never the one underfoot. It is, whenever the tree has not finished
## refining — and a coarse chunk near the viewer with no faces cannot be given a
## body at all, so the ground it draws is walked straight through onto whatever
## deeper chunk is under it. The soup is a rearrangement of vertices the build
## has already paid for, so building it always costs a fraction of a millisecond
## and some memory, and buys the invariant that anything drawn can be stood on.
@export var collision_range := 260.0

@export_group("Water")
## Lays a sea at sea level, which is the radius the height field measures from.
## Off leaves the ocean basins as dry holes; nothing else changes, because the
## water is not what makes them basins.
@export var has_water := true

@export_group("Clouds")
## Lays an iridescent cloud deck over the planet. It is one shell and one draw,
## and the weather in it is a function of where you are on the globe rather than
## anything stored, so it costs nothing to have and nothing to replicate.
@export var has_clouds := true
## How high the middle of the deck sits, in metres above sea level. Well inside
## [member atmosphere_height], or the clouds are drawn outside the air they are
## supposed to be in; high enough off the ground that the tallest terrain does
## not poke through, since the deck is a shell and does not part for mountains.
@export var cloud_height := 1200.0
## How deep the slab of cloudy air is, in metres. It is what the deck is marched
## through, so it is also what gives a cloud a top, a bottom and a thickness that
## depends on the angle it is seen from. Thin decks stop reading as volume: much
## under two hundred metres and a ray crosses too little field to accumulate
## anything, and the march is one sample again with the cost of fourteen.
@export var cloud_thickness := 700.0

@export_group("Atmosphere")
## Depth of the air, in metres. It sizes the shell that draws the lit rim seen
## from space, and it is also the altitude the shell fades in at.
##
## It must match [code]atmosphere_height[/code] in vivid_space.gdshader, which is
## where the sky stops being sky: below that the sky shader draws the haze, above
## it this shell does, and a mismatch shows as a band of altitude with either no
## air at all or twice as much. Set it to 0 to raise no shell.
@export var atmosphere_height := 2400.0
## The sun, so the shell knows which side of the planet is the day side. The sky
## reads its own light directly and does not need this.
@export var sun: DirectionalLight3D

@export_group("Editor")
## Builds the terrain in the editor as well as in the game, refining around the
## editor camera instead of a player. Without it the planet is an empty pivot in
## the editor and there is nothing to place a prop against.
##
## It costs what it costs in game, which is a frame budget the game already
## affords. Turn it off if the scene is only being opened to edit something else.
@export var editor_preview := true:
	set(value):
		if editor_preview == value:
			return
		editor_preview = value
		if Engine.is_editor_hint() and is_inside_tree():
			_rebuild()

## What the detail is built around. Falls back to the active camera, which is what
## the harness wants; the world will point this at the local player.
var viewer: Node3D

## The sea, or null if this planet has none. Anything asking how deep it is
## standing in water goes through this.
var water: PlanetWater

## The arctic's weather and its footprints. Where the arctic *is* belongs to
## [member shape]; this is only what happens in it.
var snowfield: Snowfield

## Burn marks projected over the ground. The lasting record of a burn is the
## scar in [member PlanetShape.scars]; this is the readable one.
var scorches: ScorchDecals

var _roots: Array[Chunk] = []
var _pending: Dictionary = {}
var _finished: Array[Chunk] = []
var _requests: Array[Chunk] = []
var _visible: Array[Chunk] = []
## Chunks the last walk found wanting to split, spent nearest-first once it has
## finished. Collected rather than split where they are met, because the walk
## meets them in tree order and tree order is nothing like distance order: with a
## budget of eight per walk, splitting whoever came first spent the whole
## allowance on ground already behind the viewer while the chunk under their feet
## waited for a later frame to come round to it.
var _splitters: Array[Chunk] = []
## [member split_ratio] with the render distance in it, taken once per walk rather
## than per chunk: the walk is a thousand nodes of GDScript and the answer is the
## same for all of them.
var _split_reach := 2.0
## Nodes visited by the last refine pass, which is the size of the whole tree and
## the thing every per-frame pass is proportional to.
var _walked := 0
var _since_lod := 0.0
## Rate selected for the next quadtree walk. Kept for statistics so a fast-flight
## report can prove the adaptive path was actually active.
var _lod_walk_rate := 30.0
## Depth of the finest drawn chunk the viewer is *over*, and how far its origin
## is. -1 while nothing is drawn over the viewer at all, which is a different
## answer from depth 0 and has to stay tellable apart from it: a root patch drawn
## overhead is a real, very coarse floor, and falling back to unlimited detail
## there is exactly the mistake [method spacing_underfoot] exists to prevent.
var _near_depth := -1
var _near_distance := INF
## Where the viewer was at the previous walk, and its smoothed velocity from that,
## in planet-local metres. Together they are the lead: a direction and how far
## along it the refine pass looks.
var _last_eye := Vector3.INF
var _drift := Vector3.ZERO
var _lead_direction := Vector3.ZERO
var _lead_length := 0.0
## Drawn chunks within [member collision_range] still waiting for a body.
var _floorless := 0
## Times a build landed on a chunk that already held a mesh *without* having been
## asked to replace it. `chunk.instance` is the only handle anything has on that
## node, so an overwrite would leave the displaced mesh drawn and unreachable
## forever. Zero is the only correct reading and there is no throttle that makes
## a non-zero one acceptable.
##
## A scar rebuild lands on a chunk that already holds a mesh every single time,
## by design, and counting those here would bury the fault this exists to catch
## under a steady stream of correct behaviour. `Chunk.rebuilding` tells them
## apart.
var _stranded := 0
var _built_meshes := 0
## Worker-thread time spent building the meshes counted by [member _built_meshes],
## which is the supply side of every arrival measurement: the pool can deliver
## `pending_limit / this` chunks a second and no more, whatever the budgets say.
var _build_micros_total := 0.0
var _update_micros := 0.0
## This frame's cost, not an average: both are spike sources and an average is
## the one summary guaranteed to hide a spike.
var _apply_micros := 0.0
var _collision_micros := 0.0
var _frame_micros := 0.0
var _refine_micros := 0.0
var _dispatch_micros := 0.0
var _show_micros := 0.0
var _published_center := Vector3.INF
var _published_sun := Vector3.ZERO
var _published_pole := Vector3.ZERO
var _published_speed := -1.0


## One node of one face's quadtree. Alive from the moment it is split into until
## its parent collapses, which may be while its mesh is still on the thread pool.
class Chunk extends RefCounted:
	var face: int
	## Lower-left corner in the face's [-1, 1] square.
	var offset: Vector2
	var size: float
	var depth: int
	## Where the chunk sits on the surface, and how wide it is there in metres.
	var origin: Vector3
	var arc: float
	## Metres from the viewer, as of this frame's refine pass. Cached because the
	## build queue wants to order by it and recomputing it there was the most
	## expensive thing the planet did.
	var distance := 0.0
	## Best known ground level at this chunk's centre. Inherited from the parent
	## when the chunk is made and corrected by its own build, which runs on a
	## worker thread. The correction is only ever read by children, and a chunk
	## cannot have children until its build has landed, so the two never race.
	var height := 0.0
	var children: Array[Chunk] = []
	var instance: MeshInstance3D
	var body: StaticBody3D
	var arrays: Array
	var collision_faces := PackedVector3Array()
	## What this chunk's build cost on its worker thread, in microseconds. Written
	## there and read once the mesh is attached, so it crosses threads the same
	## way the mesh does and needs no lock of its own.
	var build_micros := 0.0
	var triangles := 0
	var queued := false
	## Set when the parent collapses while a build is still running. The result is
	## thrown away rather than cancelled, because a pool task cannot be recalled.
	var discarded := false
	## Set when the ground this chunk describes has changed under it — a crater
	## or a burn was added inside its footprint — so the mesh it is holding is no
	## longer what the height field says. It goes back through the ordinary
	## request queue rather than being rebuilt on the spot, which is what keeps a
	## burst of scars from turning into a frame spike: the same nearest-first
	## budget that builds new ground rebuilds changed ground.
	var stale := false
	## Set while the build now on the pool is a *replacement* for a mesh this
	## chunk already has, rather than the first one it has ever had. Recorded
	## when the build is handed out, because [member stale] is cleared at that
	## moment and the distinction is not available again by the time the mesh
	## lands. What it buys is at [method _attach]: a replacement has to take over
	## from ground that is already on screen without a gap, where a first build
	## has to wait for the walk to choose it.
	var rebuilding := false

	func has_mesh() -> bool:
		return instance != null


func _ready() -> void:
	if shape == null:
		shape = PlanetShape.new()
	shape.prepare()
	_publish_frame()
	_raise_water()
	_raise_snowfield()
	_raise_scorches()
	_raise_clouds()
	_raise_atmosphere()
	_follow_render_distance()
	if Engine.is_editor_hint() and not editor_preview:
		return
	for face in FACES.size():
		_roots.append(_make_chunk(face, Vector2(-1.0, -1.0), 2.0, 0))


## Takes the render distance from the player's settings and keeps taking it.
##
## Read here rather than applied by [GameSettingsManager] with the rest of the
## graphics settings, because there is nothing to apply it to until a world is
## loaded: the manager starts with the game and this node arrives with the map.
## The signal is what makes the setting land while the pause menu is still open,
## which matters more here than for most of them — a render distance is chosen by
## looking at what it did.
func _follow_render_distance() -> void:
	# Absent in the editor and in the harnesses that stand a planet up on their
	# own, both of which want the scene's own baseline.
	var settings := get_node_or_null("/root/SettingsManager") as GameSettingsManager
	if settings == null:
		return
	detail_level = int(settings.get_setting(&"graphics", &"render_distance", 1))
	settings.settings_changed.connect(
		func(section: StringName, key: StringName, value: Variant) -> void:
			if section == &"graphics" and key == &"render_distance":
				detail_level = int(value))


func _exit_tree() -> void:
	# Pool tasks reference this node's shape, so none may outlive it.
	for task in _pending:
		WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()


## Throws the quadtree away and starts it again. Only the editor needs this, to
## answer a change to [member editor_preview] without a scene reload.
func _rebuild() -> void:
	for task in _pending:
		WorkerThreadPool.wait_for_task_completion(task)
	_pending.clear()
	_finished.clear()
	for root in _roots:
		_collapse(root)
		_drop(root)
	_roots.clear()
	_visible.clear()
	if not editor_preview:
		return
	for face in FACES.size():
		_roots.append(_make_chunk(face, Vector2(-1.0, -1.0), 2.0, 0))


func _process(delta: float) -> void:
	if _roots.is_empty():
		return
	var started := Time.get_ticks_usec()
	_publish_frame()
	var applying := Time.get_ticks_usec()
	_apply_finished()
	_apply_micros = float(Time.get_ticks_usec() - applying)

	# Every frame, for the same reason meshes are attached every frame and not on
	# the walk: this is a twentieth of a millisecond and it is what keeps the pool
	# fed. Dispatched only on the walk, a slot that came free just after one stood
	# idle until the next — measured at 2.5 of 4 slots busy and the pool full only
	# 61% of the time, with a queue of 43 chunks waiting to use the other 1.5.
	# Standing requests outlive the walk that found them, so there is always a
	# list to fill from.
	var dispatching := Time.get_ticks_usec()
	_dispatch(viewer_position())
	_dispatch_micros = float(Time.get_ticks_usec() - dispatching)

	_since_lod += delta
	# A parked viewer gets the cheap cadence; a fast one gets a corridor moved
	# often enough that each walk still overlaps the last. `_drift` is the
	# smoothed velocity from the previous walk, so this does not react to camera
	# bob or one-frame transform noise.
	var fast_share := smoothstep(fast_lod_from_speed,
		maxf(fast_lod_at_speed, fast_lod_from_speed + 0.01), _drift.length())
	_lod_walk_rate = lerpf(float(lod_updates_per_second),
		float(fast_lod_updates_per_second), fast_share)
	if _since_lod < 1.0 / maxf(_lod_walk_rate, 1.0):
		# Zeroed rather than left alone, so an average over frames is an average
		# of what those frames actually cost and not of the last one that walked.
		# Dispatch is not among them: it ran above, on this frame.
		_refine_micros = 0.0
		_show_micros = 0.0
		_collision_micros = 0.0
		_frame_micros = float(Time.get_ticks_usec() - started)
		_update_micros = _update_micros * 0.9 + _frame_micros * 0.1
		_report_lag()
		return
	# Read before it is zeroed: it is the interval since the last walk, which is
	# what the viewer's velocity has to be measured against. `delta` is a frame,
	# and frames are several times more often than this.
	var since_walk := _since_lod
	_since_lod = 0.0

	var eye := viewer_position()
	_track_lead(eye, since_walk)
	_requests.clear()
	_splitters.clear()
	_split_reach = split_ratio * float(
		DETAIL_LEVELS[clampi(detail_level, 0, DETAIL_LEVELS.size() - 1)]["scale"])
	_walked = 0
	var refining := Time.get_ticks_usec()
	for root in _roots:
		_refine(root, eye)
	_grow()
	_refine_micros = float(Time.get_ticks_usec() - refining)
	# Again, now that the walk has found this pass's requests: the run above was
	# working from the previous walk's list.
	var redispatch := Time.get_ticks_usec()
	_dispatch(eye)
	_dispatch_micros += float(Time.get_ticks_usec() - redispatch)
	var showing := Time.get_ticks_usec()
	_visible.clear()
	_near_distance = INF
	_near_depth = -1
	for root in _roots:
		_show(root, eye)
	_show_micros = float(Time.get_ticks_usec() - showing)
	# No colliders in the editor: nothing there walks, and a body per chunk would
	# be built and thrown away every time the view moved.
	_collision_micros = 0.0
	if not Engine.is_editor_hint():
		var colliding := Time.get_ticks_usec()
		_update_collision(eye)
		_collision_micros = float(Time.get_ticks_usec() - colliding)
	_frame_micros = float(Time.get_ticks_usec() - started)
	# Rolling average rather than the last frame: mesh handoffs make single frames
	# swing by an order of magnitude, and the average is what costs frame rate.
	_update_micros = _update_micros * 0.9 + _frame_micros * 0.1
	_report_lag()


# --- Public surface queries -------------------------------------------------

## The global point on the ground below a direction from the planet's centre.
func surface_position(direction: Vector3) -> Vector3:
	return to_global(shape.surface_point(direction.normalized()))


## Which way is up at a global point, which on a sphere is where the player's
## gravity and camera have to take their orientation from.
func up_at(global_point: Vector3) -> Vector3:
	var local := to_local(global_point)
	return global_basis * (local.normalized() if local.length_squared() > 0.0 else Vector3.UP)


## Vertex spacing of the deepest chunks, which is the finest the ground is ever
## built at. Anything that has to agree with the mesh rather than with the true
## height field — a prop standing on it, a placement check — wants this as its
## sampling distance, because the terrain the player touches is band-limited to
## it and the true field is not.
func finest_spacing() -> float:
	return spacing_at_depth(max_depth)


## Cuts one mark into the ground and rebuilds whatever was drawing it.
##
## The single entry point for terrain deformation. Abilities, and anything else
## that ever wants to dent the planet, describe the mark and hand it here; the
## registry makes it part of the height field and this makes the world catch up
## with the height field. Nothing outside this file needs to know that ground is
## a quadtree of cached meshes.
##
## Returns the scar so a caller can keep hold of it — the laser deepens the same
## mark for as long as it is held on one spot rather than laying a new one every
## tick.
func add_scar(scar: TerrainScars.Scar) -> TerrainScars.Scar:
	shape.scars.add(scar)
	# The widest the rim reaches rather than the nominal radius: a warped crater
	# bulges past its own circle, and rebuilding only the circle would leave the
	# bulges cut out of stale chunks that still hold the old ground.
	mark_region_stale(scar.direction, scar.outer, scar.depth)
	_mark_ground(scar)
	return scar


## Lays the lasting burn a scar is seen as.
##
## The scar's own darkening goes into the vertex colour of the rebuilt chunk,
## which is the version that survives streaming and is right from a distance.
## Close up the ground is drawn from a photographic material and a tint carried
## by a handful of vertices under that does not read at all, so the mark that
## makes a burn a burn is a decal, and for a scar it is one that does not fade.
func _mark_ground(scar: TerrainScars.Scar) -> void:
	if scorches == null or scar.char <= 0.0:
		return
	var at := global_transform * shape.surface_point(scar.direction)
	scorches.scorch(at, up_at(at), scar.outer,
		clampf(scar.char, 0.0, 1.0), true)


## Tells the quadtree that the ground inside a patch has changed.
##
## Separate from [method add_scar] because a scar that is deepened in place
## changes ground it is already registered over, and because the height field
## could in principle be moved by something that is not a scar at all.
##
## [param drop] is how far the ground fell, and decides whether the colliders
## over the patch are worth keeping until the rebuild lands. See [method
## _mark_stale].
func mark_region_stale(direction: Vector3, arc: float, drop := 0.0) -> void:
	var at := direction.normalized()
	for root in _roots:
		_mark_stale(root, at, arc, drop)


func _mark_stale(chunk: Chunk, at: Vector3, arc: float, drop: float) -> void:
	# A child's footprint is inside its parent's, so a parent that cannot reach
	# the patch settles the whole subtree under it in one comparison. Generous
	# by the chunk's full width rather than its half-diagonal: marking a chunk
	# that did not need it costs one rebuild, and missing one leaves a crater
	# with a square of untouched ground in the middle of it.
	#
	# Measured between the two directions projected back to sea level, not
	# between the points themselves. A chunk's origin is lifted to its own patch
	# of ground, so on a mountain the raw distance to a sea-level direction is
	# mostly the mountain's height: a crater cut on a thirty-metre rise compared
	# its six-metre radius against a thirty-three-metre gap and marked nothing
	# at all, leaving the height field dented and the mesh flat over it.
	if chunk.origin.normalized().distance_to(at) * shape.radius \
			> arc + chunk.arc:
		return
	# Coarse chunks are walked through but not marked. A chunk whose vertices
	# are further apart than the patch is wide cannot draw it — the height field
	# fades every scar out at spacings that would alias it — so rebuilding one
	# produces the mesh it already has. Before this, a two-metre laser burn
	# marked every ancestor it sat under, up to a root patch of tens of
	# thousands of vertices, and each of those was then built a vertex at a time
	# in GDScript to arrive at exactly the ground it started with. That was half
	# a second of worker time per burn, four times a second while the beam was
	# held. The children are still visited: they are the ones that can show it.
	if chunk.has_mesh() and shape.scars.resolves(arc, spacing_at_depth(chunk.depth)):
		chunk.stale = true
		# A deep enough cut takes its colliders with it rather than waiting for
		# the rebuild.
		#
		# A mesh may lag the height field by a few frames without anyone
		# noticing; a collider may not. It is the thing bodies stand on, and one
		# generated from ground that has since been dug away holds a player up
		# on a surface that is no longer there — and then drops them into the
		# hole the moment it is finally replaced, which is exactly the fall you
		# feel after landing a punch. Between here and the rebuild the
		# height-field guard is the floor, and the height field already has the
		# crater in it. `_update_collision` puts a body back from the faces the
		# rebuild produces.
		#
		# Only for cuts deeper than a stride, though, and the threshold is the
		# whole of it. Dropping a body leaves drawn ground with nothing under it
		# for as long as the rebuild takes, which is the one state this quadtree
		# is otherwise careful never to be in — see `_floorless`. That is a fair
		# trade for a crater, where the alternative is standing on a ledge of
		# ground that no longer exists. It is a bad one for a laser groove: the
		# beam cuts a fifth of a metre, four times a second, wherever the player
		# happens to be looking, which is very often at their own feet. Paying
		# the floor for that means the ground underneath is repeatedly not
		# there, the guard catches the body a little lower each time, and the
		# camera dips through a surface it should be standing on.
		if drop >= COLLIDER_DROP and chunk.body != null:
			chunk.body.queue_free()
			chunk.body = null
	for child in chunk.children:
		_mark_stale(child, at, arc, drop)


## Vertex spacing of a chunk at a given depth, which is what its mesh is
## band-limited to.
func spacing_at_depth(depth: int) -> float:
	return PI * 0.5 * shape.radius / pow(2.0, depth) \
		/ float(_resolution_at_depth(depth))


## Resolution that preserves [member far_detail_depth] grain through the broad
## root levels. Multiplying resolution while chunk width halves keeps the vertex
## spacing identical, so those levels repartition the same surface rather than
## visibly sharpening it one step at a time.
func _resolution_at_depth(depth: int) -> int:
	var floor_depth := mini(far_detail_depth, max_depth)
	var skipped := maxi(floor_depth - depth, 0)
	return chunk_resolution * (1 << skipped)


## Vertex spacing of the ground actually drawn under the viewer, right now.
##
## Not the same as [method finest_spacing], and the difference is the whole
## reason this exists. Every feature in the height field fades out at coarse
## spacing so it cannot alias, so a chunk that has not refined yet is missing
## whatever is finer than it — and for a canyon or a river gorge, which are very
## nearly step functions, what is missing is the hole. The coarse chunk draws a
## lid straight across it.
##
## Anything asking "where is the ground" on behalf of a *body* must ask at this
## spacing rather than at the finest, or it answers about a surface that is not
## on screen. Underneath a lid the two disagree by the depth of the canyon: the
## guard reads the body as thirty-six metres in the air while it stands on ground
## it can see, and hands it air control and no floor snapping until it sinks
## through. Settled, the two agree to a few centimetres, which is why this only
## ever bites during an arrival and never once the tree has converged.
##
## Falls back to the finest when nothing is drawn over the viewer at all, which is
## right rather than merely safe: with no chunk there is no lid to stand on
## either, and the true field is the only answer available. Depth 0 is **not**
## that case — a root patch overhead is a real floor at 785 m between vertices,
## and answering about unlimited detail under it is the exact failure above.
func spacing_underfoot() -> float:
	if _near_depth < 0:
		return finest_spacing()
	return spacing_at_depth(_near_depth)


## Ground level plus clearance, for putting something on the surface.
func standing_position(direction: Vector3, clearance := 0.0) -> Vector3:
	var unit := direction.normalized()
	return to_global(unit * (shape.radius + shape.elevation(unit) + clearance))


## Whether the ground stands between two global points.
##
## Asked by anything drawing a world position onto the screen, which on a globe
## is most often asking whether the thing is on the other side of it. A raycast
## cannot answer that: only the [member collision_range] around the viewer has a
## body, and everything worth naming from a distance is well past it. So the
## height field is walked directly, which needs no collision and no chunk to have
## been built.
##
## Samples are spread evenly along the line, so this catches the planet's own
## bulge exactly and a mountain range only if it is wider than the spacing. That
## is the right trade for a HUD: the bulge is the whole point and a hill in the
## way is a detail. It costs [param samples] height lookups, which is enough to
## want throttling if it is asked every frame.
func sight_blocked(from: Vector3, to: Vector3, samples := 12) -> bool:
	if shape == null:
		return false
	var start := to_local(from)
	var finish := to_local(to)
	var spacing := finest_spacing()
	for index in range(1, samples):
		var point := start.lerp(finish, float(index) / float(samples))
		var reach := point.length()
		if reach < 1.0:
			return true
		var direction := point / reach
		if reach < shape.radius + shape.elevation(direction, spacing):
			return true
	return false


## Chunks on screen, chunks mid-build, triangles drawn, and colliders standing.
## The harness prints these; they are the only honest way to see what the LOD is
## actually doing.
func statistics() -> Dictionary:
	var triangles := 0
	var bodies := 0
	for chunk in _visible:
		triangles += chunk.triangles
		if chunk.body != null:
			bodies += 1
	return {
		"visible": _visible.size(),
		"pending": _pending.size(),
		# Chunks the last walk wanted a mesh for. Held apart from `pending`
		# because the two say different things and only together say which end of
		# the pipe is the narrow one: a backlog with the pool full is supply, a
		# pool with slots free is demand that arrived too late to use them.
		"requests": _requests.size(),
		# What the ground under the viewer is drawn at, against `max_depth`. This
		# is the arrival measurement: throughput says how much ground is being
		# built anywhere, and this says whether any of it is where somebody is
		# standing.
		"depth": _near_depth,
		"triangles": triangles,
		"bodies": bodies,
		# Drawn ground within reach of a walker that has no collider yet. Zero is
		# the only steady-state answer; anything else is ground you fall through.
		"floorless": _floorless,
		# Meshes that would have been stranded on screen with no handle left to
		# hide them. See `_attach`.
		"stranded": _stranded,
		"built": _built_meshes,
		"build_ms": _build_micros_total / 1000.0 / maxf(1.0, float(_built_meshes)),
		"update_ms": _update_micros / 1000.0,
		"apply_ms": _apply_micros / 1000.0,
		"collision_ms": _collision_micros / 1000.0,
		"frame_ms": _frame_micros / 1000.0,
		"refine_ms": _refine_micros / 1000.0,
		"dispatch_ms": _dispatch_micros / 1000.0,
		"show_ms": _show_micros / 1000.0,
		"nodes": _walked,
		"reach": _split_reach,
		"lod_hz": _lod_walk_rate,
		"lead": _lead_length,
	}


func _report_lag() -> void:
	if Engine.is_editor_hint():
		return
	var ms := _frame_micros / 1000.0
	LagTracker.set_gauge("terrain", ms)
	if _apply_micros >= 4000.0 or _requests.size() >= 24:
		LagTracker.note_throttled("terrain", "terrain_storm",
			"apply %.1f ms  requests %d  visible %d" % [
				_apply_micros / 1000.0, _requests.size(), _visible.size()], 0.4)


# --- The planet frame -------------------------------------------------------

## Writes the globals the vivid shaders read. Guarded on change rather than
## written every frame: a global shader parameter counts as a uniform change, and
## the sky's radiance cubemap — which is the scene's ambient light — is rebuilt
## whenever one moves. The sun is the one that now moves every frame, by design:
## CelestialCycle turns it continuously and the Sky is set to realtime to match,
## so freezing it again to save the rebuild would only stop the day.
func _publish_frame() -> void:
	# How fast the viewer is crossing the ground, which the terrain shader uses
	# to calm the detail that has no mip chain to calm itself; see its Motion
	# block. Taken from the drift already smoothed for the detail lead rather
	# than measured again, so the ground and the quadtree agree about how fast
	# this is going.
	#
	# On the material and not as a global, unlike everything below: a global
	# shader parameter is a uniform change the sky answers with a radiance
	# rebuild, and this one moves whenever the player touches the throttle.
	# Rounded for the same reason — full precision here would write it every
	# frame of every flight to say the speed changed by a millimetre a second.
	var speed := snappedf(_drift.length(), 0.5)
	if speed != _published_speed:
		_published_speed = speed
		SURFACE_MATERIAL.set_shader_parameter(&"eye_speed", speed)
	var center := global_position
	if center != _published_center:
		_published_center = center
		RenderingServer.global_shader_parameter_set(&"planet_center", center)
		RenderingServer.global_shader_parameter_set(&"planet_radius", shape.radius)
	# North, in world space, and the two cosines that bound the polar cap. The
	# shape owns all three; publishing them rather than restating them in the
	# shaders is what keeps the ice the mesh is built from and the white the
	# shaders paint on the same circle.
	var pole := (global_basis * shape.frost_axis).normalized()
	if pole != _published_pole:
		_published_pole = pole
		RenderingServer.global_shader_parameter_set(&"frost_axis", pole)
		RenderingServer.global_shader_parameter_set(&"frost_edge", shape.frost_outer())
		RenderingServer.global_shader_parameter_set(&"frost_full", shape.frost_inner())
	if sun == null:
		return
	var direction := -sun.global_basis.z
	if direction != _published_sun:
		_published_sun = direction
		RenderingServer.global_shader_parameter_set(&"sun_direction", direction)


## The sea. One node and one mesh, sized and placed by itself; all this decides is
## where the surface is, which is sea level and nowhere else.
func _raise_water() -> void:
	if not has_water:
		return
	water = PlanetWater.new()
	water.name = "Water"
	water.sea_level = shape.radius
	# It follows the same viewer the terrain refines around, and finding one in
	# the editor is knowledge this node already has.
	water.viewer_source = viewer_position
	add_child(water, false, Node.INTERNAL_MODE_BACK)


## The arctic, in as much as it is weather rather than terrain. The white ground
## and the pack ice are in the height field itself; this is the snow falling
## through the air over it and the tracks left behind in it.
func _raise_snowfield() -> void:
	snowfield = Snowfield.new()
	snowfield.name = "Snowfield"
	snowfield.shape = shape
	snowfield.viewer_source = viewer_position
	add_child(snowfield, false, Node.INTERNAL_MODE_BACK)


func _raise_scorches() -> void:
	scorches = ScorchDecals.new()
	scorches.name = "Scorches"
	add_child(scorches, false, Node.INTERNAL_MODE_BACK)


## The weather, drawn as one sphere a kilometre or so up.
##
## There is no cloud object and nothing is generated in GDScript: the deck is a
## field filling the slab between two radii, marched per pixel by
## `vivid_clouds.gdshader`, which is what makes the clouds located on the globe,
## endless, free to store and free to replicate. Which part of the sky is
## clouding over and which is clearing is in that shader too — see the header
## there for how condensing and evaporating are the same dial.
##
## The sphere raised here is the **top** of the slab and not the middle of it,
## because it is the volume's silhouette rather than its surface: a mesh inside
## the field would clip the deck at the limb, and the shader measures the depth
## of the slab downward from it. More segments than the air above it, because
## this one is looked at from underneath, where its silhouette is against the
## horizon rather than against space.
func _raise_clouds() -> void:
	if not has_clouds or cloud_height <= 0.0:
		return
	var radius := shape.radius + cloud_height + cloud_thickness * 0.5
	var material := CLOUD_MATERIAL.duplicate() as ShaderMaterial
	material.set_shader_parameter(&"shell_radius", radius)
	material.set_shader_parameter(&"deck_thickness", cloud_thickness)
	add_child(_shell("Clouds", radius, 128, material), false, Node.INTERNAL_MODE_BACK)


## The band of air, drawn as one sphere a few per cent wider than the planet.
##
## It is a single draw and the shader inside it fades to nothing below the
## altitude where the sky takes over, so there is no cost to leaving it up while
## someone is walking around underneath it.
func _raise_atmosphere() -> void:
	if atmosphere_height <= 0.0:
		return
	# Duplicated rather than shared, because the height is written into it and
	# the .tres would otherwise carry one planet's setting into the next scene.
	var material := ATMOSPHERE_MATERIAL.duplicate() as ShaderMaterial
	material.set_shader_parameter(&"shell_height", atmosphere_height)
	add_child(_shell("Atmosphere", shape.radius + atmosphere_height, 96, material),
		false, Node.INTERNAL_MODE_BACK)


## One of the shells the planet wears. Both are the same object — a sphere with
## no shading of its own, whose whole appearance is in the shader — so they are
## built in one place and differ only by radius, resolution and material.
func _shell(shell_name: String, radius: float, segments: int,
		material: ShaderMaterial) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	# Enough that the limb reads as a circle rather than as a polygon. The shell
	# is unshaded and untextured, so this is the only thing the count buys.
	sphere.radial_segments = segments
	sphere.rings = segments / 2
	var instance := MeshInstance3D.new()
	instance.name = shell_name
	instance.mesh = sphere
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# --- Quadtree ---------------------------------------------------------------

func _make_chunk(face: int, offset: Vector2, size: float, depth: int, height := 0.0) -> Chunk:
	var chunk := Chunk.new()
	chunk.face = face
	chunk.offset = offset
	chunk.size = size
	chunk.depth = depth
	# A face's square spans a quarter of a great circle, so half its [-1, 1] width
	# is (pi / 2) * radius of surface.
	chunk.arc = size * PI * shape.radius * 0.25
	# The parent's ground level, not this chunk's own. Asking the height field
	# where the centre sits costs about a third of a millisecond, and a split
	# wants four of those — which at thirty splits a second was the single most
	# expensive thing in the frame. Half a chunk's worth of terrain is a good
	# enough guess for placing an origin, and the build corrects it for free.
	chunk.height = height
	chunk.origin = _direction(chunk, 0.5, 0.5) * (shape.radius + height)
	return chunk


## Distance from the viewer to the chunk's patch of ground, measured to a sphere
## around it so a chunk is not judged by its centre alone.
## Works out how far ahead of the viewer the detail should be built, from how fast
## the viewer is actually moving. Nothing tells the planet its viewer's velocity —
## it may be a player, a camera or a harness writing a transform — so it is
## measured here, off two positions one walk apart.
func _track_lead(eye: Vector3, elapsed: float) -> void:
	if _last_eye == Vector3.INF or elapsed <= 0.0:
		_last_eye = eye
		return
	var measured := (eye - _last_eye) / elapsed
	_last_eye = eye
	if measured.length() > LEAD_TELEPORT_SPEED:
		_drift = Vector3.ZERO
	else:
		_drift = _drift.lerp(measured, clampf(elapsed / LEAD_SMOOTHING, 0.0, 1.0))
	var speed := _drift.length()
	if lead_time <= 0.0 or speed < LEAD_MIN_SPEED:
		_lead_direction = Vector3.ZERO
		_lead_length = 0.0
		return
	_lead_direction = _drift / speed
	_lead_length = minf(speed * lead_time, lead_distance)


## Distance from a chunk to the viewer, less most of the chunk's own half-width so
## that a big chunk is judged by its nearest ground rather than by its middle.
func _distance(chunk: Chunk, eye: Vector3) -> float:
	return maxf(0.0, eye.distance_to(chunk.origin) - chunk.arc * 0.75)


## The same measure taken to the whole path the viewer is on rather than to the
## point it occupies, which is what makes the ground ahead refine before it is
## reached. Degenerates to [method _distance] exactly when there is no lead, so
## standing still costs nothing over the old behaviour and the region refined
## grows only in the direction being travelled.
##
## The path is a straight segment while the planet is round, and that is fine at
## this length: 300 m of chord across an 8 km sphere departs from the surface by
## six metres, well under the arc already being subtracted.
func _path_distance(chunk: Chunk, eye: Vector3) -> float:
	var to_chunk := chunk.origin - eye
	var along := clampf(to_chunk.dot(_lead_direction), 0.0, _lead_length)
	return maxf(0.0, (to_chunk - _lead_direction * along).length() - chunk.arc * 0.75)


func _refine(chunk: Chunk, eye: Vector3) -> void:
	# Every level on the path gets a mesh, not just the leaves. A coarse ancestor
	# is what covers the ground while its children are still on the thread pool,
	# so without them the planet has a hole in it wherever the viewer is looking.
	if (not chunk.has_mesh() or chunk.stale) and not chunk.queued:
		_requests.append(chunk)
	_walked += 1
	# Measured to the path and not to the viewer, so a chunk about to be flown
	# over is split and queued now. `chunk.distance` carries it to `_dispatch`,
	# which builds the nearest first — and nearest to the path is exactly the
	# order a fast viewer wants. Collision keeps to the true position; see
	# `_update_collision`.
	var distance := _path_distance(chunk, eye)
	chunk.distance = distance
	var split_at := chunk.arc * _split_reach
	# Nothing subdivides until it has been built. Splitting on distance alone let
	# a viewer at 200 m/s demand levels far faster than the thread pool could
	# supply them, and the tree grew to thousands of meshless nodes that every
	# pass then had to walk — which is what made refining, queueing and drawing
	# each cost tens of milliseconds. Tying growth to what has actually arrived
	# keeps the tree the size of the ground that exists.
	if chunk.depth < max_depth and distance < split_at and chunk.has_mesh():
		# Only noted here. Nothing records that a split was wanted beyond this
		# walk: the same test comes round again next time, and by then the
		# nearest chunk wanting one may well be a different chunk.
		if chunk.children.is_empty():
			_splitters.append(chunk)
	elif not chunk.children.is_empty() and distance > split_at * 1.3:
		# Collapsing further out than splitting, so a viewer loitering on the
		# boundary does not rebuild the same four chunks every frame.
		_collapse(chunk)
	for child in chunk.children:
		_refine(child, eye)


## Spends the walk's split budget on the chunks nearest the path, and withholds it
## entirely while the pool is hopelessly behind.
##
## Two separate things gate growth here and they answer different questions. The
## budget is how much tree may be added in one walk; the queue is whether adding
## any of it is worth doing at all. A split makes four meshless chunks, and while
## hundreds are already waiting for the pool those four cannot make their ground
## arrive one moment sooner for having been asked earlier — all they do is
## lengthen every later walk, and the refine and draw passes are the two most
## expensive things in this file. Growth left ungated that way feeds itself: a
## bigger tree costs more per frame, fewer meshes are attached, so more of the
## tree is meshless, which is the state that was measured at 350 deep.
##
## The loop that results is self-limiting rather than tuned. Builds landing take
## chunks out of the queue, the queue falls under the mark, splitting resumes —
## so the tree settles at the size the pool can actually keep in meshes.
func _grow() -> void:
	# Both conditions, and the first is the one that was missing. A deep queue
	# only means growth is pointless if the pool is also flat out: with a slot
	# standing free there is capacity for the ground being asked for, and
	# refusing to ask is how the tree ended up throttled while builders idled.
	# The queue alone is not evidence of anything — it is 43 deep in the healthy
	# case, which is above any fixed mark worth setting.
	if _pending.size() >= pending_limit \
			and _requests.size() > pending_limit * queue_depth:
		return
	var budget := splits_per_frame
	# Nearest-first by the same argument as `_dispatch`, and by repeated linear
	# scan even at this budget. Sorting once and taking the front looks strictly
	# better on paper — a few thousand comparisons against tens of thousands of
	# array reads — and measured worse on both counts, refine 6.25 ms to 8.51 and
	# delivery 2856 chunks to 2618. `sort_custom` pays a script call per
	# comparison, and one of those costs more than the dozen inline reads it
	# saves. Do not re-derive this from the complexity; it is the constant that
	# decides it.
	while budget > 0:
		var nearest: Chunk = null
		var nearest_at := INF
		for chunk in _splitters:
			if chunk.children.is_empty() and chunk.distance < nearest_at:
				nearest_at = chunk.distance
				nearest = chunk
		if nearest == null:
			return
		_split(nearest)
		budget -= 1


func _split(chunk: Chunk) -> void:
	var half := chunk.size * 0.5
	for corner in 4:
		var offset := chunk.offset + Vector2(float(corner % 2) * half, float(corner / 2) * half)
		chunk.children.append(_make_chunk(chunk.face, offset, half, chunk.depth + 1, chunk.height))


func _collapse(chunk: Chunk) -> void:
	for child in chunk.children:
		_collapse(child)
		_drop(child)
	chunk.children.clear()


func _drop(chunk: Chunk) -> void:
	chunk.discarded = true
	if chunk.instance != null:
		chunk.instance.queue_free()
		chunk.instance = null
	if chunk.body != null:
		chunk.body.queue_free()
		chunk.body = null


## Walks the tree deciding what to draw, and returns whether this subtree is fully
## covered. A parent keeps its mesh on screen until every descendant that replaces
## it is ready, so the ground never opens up mid-build.
func _show(chunk: Chunk, eye: Vector3) -> bool:
	if not chunk.children.is_empty():
		var covered := true
		for child in chunk.children:
			covered = _show(child, eye) and covered
		if covered:
			_set_visible(chunk, false)
			return true
		for child in chunk.children:
			_hide(child)
	if chunk.has_mesh():
		_set_visible(chunk, true)
		_visible.append(chunk)
		_note_underfoot(chunk, eye)
		return true
	_set_visible(chunk, false)
	return false


## Records the finest chunk drawn over the viewer, which is the resolution the
## ground under the feet was band-limited to and the whole of what
## [method spacing_underfoot] means.
##
## **Containment, not nearness**, and taking the nearest was wrong twice over.
## `chunk.distance` is the *lead* distance, aimed ahead along the path so ground
## about to be flown over refines before it is reached — so at speed it names a
## chunk the viewer is not on. And `_distance` subtracts three quarters of a
## chunk's own width, which is right for deciding what to split and useless here:
## a root patch is nine kilometres across, so it reports zero from most of the
## visible cap and wins every comparison it enters.
##
## Both faults point the same way: the guard ends up sampling the field at a
## spacing no chunk under the body was built at, and its surface stops being the
## surface on screen — which is the thing `spacing_underfoot` was written to
## guarantee. A parent and its own children are never drawn together, so among
## the chunks containing the eye there is one per face and the deepest is the
## answer.
func _note_underfoot(chunk: Chunk, eye: Vector3) -> void:
	if chunk.depth <= _near_depth:
		return
	# Sideways only. A chunk's extent is a patch of ground and altitude is not
	# part of it, so the straight-line distance is the wrong measure entirely: a
	# viewer 80 m up is more than a depth-9 chunk's whole width away from every
	# chunk beneath them, and testing that way says nothing is underfoot anywhere
	# above head height.
	var to_eye := eye - chunk.origin
	var radial := chunk.origin.normalized()
	var lateral := (to_eye - radial * to_eye.dot(radial)).length()
	# Half a chunk plus a margin: the half-diagonal is 0.71 of the arc, and being
	# generous costs nothing because the deepest container wins. A coarse patch
	# only takes the answer where no finer one covers the spot, which is exactly
	# when the coarse patch *is* the ground on screen.
	if lateral > chunk.arc * 0.75:
		return
	_near_depth = chunk.depth
	_near_distance = lateral


func _hide(chunk: Chunk) -> void:
	_set_visible(chunk, false)
	for child in chunk.children:
		_hide(child)


func _set_visible(chunk: Chunk, shown: bool) -> void:
	# Writing visible goes through to the rendering server whether or not it
	# changed, and this runs over every node in the tree every frame.
	if chunk.instance != null and chunk.instance.visible != shown:
		chunk.instance.visible = shown
	# Ground nobody can see is ground nobody can stand on. This is also what
	# retires a parent's collider once its children have taken over.
	if not shown and chunk.body != null:
		chunk.body.queue_free()
		chunk.body = null


# --- Building ---------------------------------------------------------------

func _dispatch(_eye: Vector3) -> void:
	var slots := pending_limit - _pending.size()
	if slots <= 0 or _requests.is_empty():
		return
	# Nearest first: the chunk under the viewer's feet matters more than one on
	# the horizon, and both are in the same queue. Picked by scanning rather than
	# by sorting, because only a handful of slots are ever free and ordering the
	# whole list to take twelve off the front cost more than the builds did.
	for slot in slots:
		var nearest: Chunk = null
		var nearest_at := INF
		for chunk in _requests:
			# `has_mesh` as well as `queued`, and leaving it out was the whole of
			# the leak. Requests deliberately outlive the walk that found them so
			# the pool never idles, but `_apply_finished` runs every frame too and
			# clears `queued` the instant a build lands — so between that attach
			# and the next walk, a chunk that is finished and drawn still looks
			# like an outstanding request and gets built all over again.
			if chunk.queued or (chunk.has_mesh() and not chunk.stale):
				continue
			if chunk.distance < nearest_at:
				nearest_at = chunk.distance
				nearest = chunk
		if nearest == null:
			return
		nearest.queued = true
		nearest.rebuilding = nearest.stale
		# Cleared as the build is handed out rather than when it lands, so a
		# scar added while this one is on the pool marks the chunk again and
		# earns it a second rebuild instead of being silently swallowed.
		nearest.stale = false
		_pending[WorkerThreadPool.add_task(_build.bind(nearest))] = nearest


func _apply_finished() -> void:
	for task in _pending.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_finished.append(_pending[task])
			_pending.erase(task)
	var applied := 0
	while applied < applies_per_frame and not _finished.is_empty():
		var chunk := _finished.pop_front() as Chunk
		chunk.queued = false
		if not chunk.discarded:
			_attach(chunk)
			applied += 1
		chunk.arrays = []


## Hangs a finished mesh on the planet, in place of whatever the chunk had before.
##
## **The old instance has to be freed here**, and not freeing it was invisible in
## exactly the way that costs the most. `chunk.instance` is the only handle
## anything has on a chunk's mesh — `_set_visible` writes through it, `_drop`
## frees through it — so a replacement that merely reassigns the field leaves the
## previous node parented to the planet, drawn, holding whatever visibility it
## was last given, and unreachable by every piece of code that could ever turn it
## off. An orphaned *parent* is the bad case: coarse, smoothed ground that stays
## on screen above the refined chunks that replaced it, with no collider, because
## a collider belongs to the chunk and the chunk has moved on.
func _attach(chunk: Chunk) -> void:
	var shown := false
	if chunk.instance != null:
		if chunk.rebuilding:
			shown = chunk.instance.visible
		else:
			_stranded += 1
		chunk.instance.queue_free()
		chunk.instance = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk.arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = SURFACE_MATERIAL
	instance.layers = TERRAIN_RENDER_LAYER
	# Vertices are stored around the chunk's own origin, so a chunk 8 km from the
	# planet's centre still has small coordinates and a tight bounding box.
	instance.position = chunk.origin
	# Ground that was on screen a moment ago goes straight back on screen.
	#
	# Waiting for the next `_show` walk to choose it is a hole in the planet, and
	# not a brief one: meshes are attached every frame but the walk runs at
	# `lod_updates_per_second`, so a rebuild landing just after one waits the
	# best part of a walk interval with nothing drawn there at all. Nothing else
	# covers it either — the parent that used to draw this patch retired its own
	# mesh when this chunk took it over — so what is behind it is the inside of
	# the world. A held laser commits several scars a second and it read as the
	# terrain flickering out from under the beam.
	#
	# Only a replacement. A first build has no predecessor to inherit from and
	# must still wait to be chosen, which is what stops half-built ground
	# appearing through the coarse mesh that is standing in for it.
	instance.visible = shown
	# Internal, so the hundreds of them stay out of the Scene dock and out of the
	# saved file when the quadtree is running in the editor.
	add_child(instance, false, Node.INTERNAL_MODE_BACK)
	chunk.instance = instance
	chunk.rebuilding = false
	# The collider was generated from the mesh that has just been replaced, so it
	# goes with it — and it is replaced here and now rather than left to the next
	# collision pass.
	#
	# Handing it to `_update_collision` looks equivalent and is not. That pass is
	# budgeted by `bodies_per_frame` and shares its allowance with all the
	# ordinary streaming, so a chunk can spend several frames drawn with nothing
	# under it, which is the `_floorless` state this tree is otherwise careful
	# never to enter. Under a held laser that is ground the player is standing on
	# going away four times a second. There is no saving in deferring it either:
	# the faces this build produced are in hand, the work is the same work, and
	# only chunks that already had a body — the handful near the viewer — pay it.
	if chunk.body != null:
		chunk.body.queue_free()
		chunk.body = null
		if not chunk.collision_faces.is_empty():
			chunk.body = _make_body(chunk)
	_built_meshes += 1
	_build_micros_total += chunk.build_micros


## Runs on a worker thread. Touches nothing but the chunk it was handed and the
## shape, which is read-only once prepared.
func _build(chunk: Chunk) -> void:
	var began := Time.get_ticks_usec()
	var resolution := _resolution_at_depth(chunk.depth)
	if not shape.needs_script_build(chunk.origin, chunk.arc,
			chunk.arc / float(resolution)):
		_build_natively(chunk)
		chunk.build_micros = float(Time.get_ticks_usec() - began)
		return
	# One skirt ring outside the patch on every side, so the grid is the patch
	# plus a border rather than a patch with special cases at its edges.
	var side := resolution + 3
	var count := side * side
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	uvs.resize(count)

	var spacing := chunk.arc / float(resolution)
	# On a worker thread, where a height-field sample is free as far as the frame
	# is concerned. This is what any children of this chunk will place themselves
	# against instead of sampling for themselves.
	chunk.height = shape.elevation(_direction(chunk, 0.5, 0.5), spacing)
	# Deep enough to cover the step where a coarser neighbour's smoothed terrain
	# meets this chunk's, which scales with the chunk because that is what decides
	# how much of the height field each level is allowed to see.
	var skirt := chunk.arc * skirt_scale
	var last := side - 1

	var span := float(resolution)
	# One field evaluation per grid slot and no more. The ring outside the patch
	# is a genuine step out rather than a copy of the edge, because the pass below
	# differences it: a normal taken from these heights costs four array reads
	# where `PlanetShape.normal_at` costs four more evaluations of the whole
	# field, which was 23 of the 30 microseconds a vertex used to take.
	var field := PackedVector3Array()
	var heights := PackedFloat32Array()
	field.resize(count)
	heights.resize(count)
	for row in side:
		for col in side:
			var index := row * side + col
			var direction := _direction(chunk, float(col - 1) / span, float(row - 1) / span)
			field[index] = direction
			heights[index] = shape.elevation(direction, spacing)

	for row in side:
		var v_index := clampi(row - 1, 0, resolution)
		var patch_row := clampi(row, 1, last - 1)
		for col in side:
			var u_index := clampi(col - 1, 0, resolution)
			var patch_col := clampi(col, 1, last - 1)
			var index := row * side + col
			# The skirt hangs off the patch edge, so a ring slot stands on the
			# edge's own direction and height and drops them. Its own sample is
			# there to be differenced, not to be stood on, which is what keeps
			# the curtain a vertical one and the geometry what it always was.
			var source := patch_row * side + patch_col
			var direction := field[source]
			var height := heights[source]
			var normal := _grid_normal(field, heights, side, patch_row, patch_col)
			var radius := shape.radius + height
			if row == 0 or col == 0 or row == last or col == last:
				radius -= skirt
			vertices[index] = direction * radius - chunk.origin
			normals[index] = normal
			colors[index] = shape.color_at(direction, height, normal)
			uvs[index] = Vector2(float(u_index), float(v_index)) / span

	var indices := PackedInt32Array()
	indices.resize(last * last * 6)
	var write := 0
	for row in last:
		for col in last:
			var corner := row * side + col
			# Clockwise seen from outside, which is Godot's front face.
			indices[write] = corner
			indices[write + 1] = corner + side
			indices[write + 2] = corner + 1
			indices[write + 3] = corner + 1
			indices[write + 4] = corner + side
			indices[write + 5] = corner + side + 1
			write += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	chunk.arrays = arrays
	chunk.triangles = indices.size() / 3

	chunk.collision_faces = _collision_from(vertices, side, resolution)

	chunk.build_micros = float(Time.get_ticks_usec() - began)


## The same patch, built entirely in the native field.
##
## The loop above is kept, and is not dead code: it is the path a chunk over a
## town takes. A town's ground and colour come from a [CityPlan] — a baked raster
## and a pad in GDScript — so those chunks are composed here a vertex at a time
## the way every chunk used to be. There are two towns on an 8 km sphere, so this
## is a handful of chunks against thousands, and the alternative was either to
## port [CityPlan] as well or to teach the native field about something that is
## not terrain.
func _build_natively(chunk: Chunk) -> void:
	var resolution := _resolution_at_depth(chunk.depth)
	var axes: Array = FACES[chunk.face]
	var patch: Dictionary = shape.build_patch(
		axes[0], axes[1], axes[2], chunk.offset, chunk.size, resolution,
		chunk.arc / float(resolution), chunk.arc * skirt_scale, chunk.origin,
		true)

	chunk.height = float(patch["height"])
	var indices: PackedInt32Array = patch["indices"]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = patch["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = patch["normals"]
	arrays[Mesh.ARRAY_COLOR] = patch["colors"]
	arrays[Mesh.ARRAY_TEX_UV] = patch["uvs"]
	arrays[Mesh.ARRAY_INDEX] = indices
	chunk.arrays = arrays
	chunk.triangles = indices.size() / 3
	if patch.has("collision"):
		chunk.collision_faces = patch["collision"]


## Surface normal from the chunk's own height grid, as a central difference of the
## four neighbouring samples.
##
## Cheaper than [method PlanetShape.normal_at] by the whole of that function: it
## reads four numbers the build has already paid for, where the field's own
## version evaluates the entire height field four more times. It is also the more
## honest of the two, because it describes the triangles actually being built
## rather than a finer surface this mesh has not got the vertices for.
##
## Two chunks at one depth agree along the edge they share, which is the property
## that keeps normals from seaming there: the grid steps one cell *outside* the
## patch, so both sides difference the same two points. Clamping the ring to the
## edge instead would leave each side taking a one-sided difference in opposite
## directions, and the seam would run down every chunk boundary on the planet.
func _grid_normal(field: PackedVector3Array, heights: PackedFloat32Array,
		side: int, row: int, col: int) -> Vector3:
	var index := row * side + col
	var west := index - 1
	var east := index + 1
	var south := index - side
	var north := index + side
	var along_u := field[east] * (shape.radius + heights[east]) \
		- field[west] * (shape.radius + heights[west])
	var along_v := field[north] * (shape.radius + heights[north]) \
		- field[south] * (shape.radius + heights[south])
	var normal := along_u.cross(along_v)
	var up := field[index]
	if normal.length_squared() < 1e-12:
		return up
	normal = normal.normalized()
	return normal if normal.dot(up) > 0.0 else -normal


## Triangles for the collider, taken from the patch only: the skirt hangs below
## the ground and would catch anything that walked over the chunk's edge.
func _collision_from(vertices: PackedVector3Array, side: int,
		resolution: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	faces.resize(resolution * resolution * 6)
	var write := 0
	for row in resolution:
		for col in resolution:
			var corner := (row + 1) * side + col + 1
			faces[write] = vertices[corner]
			faces[write + 1] = vertices[corner + side]
			faces[write + 2] = vertices[corner + 1]
			faces[write + 3] = vertices[corner + 1]
			faces[write + 4] = vertices[corner + side]
			faces[write + 5] = vertices[corner + side + 1]
			write += 6
	return faces


# --- Collision --------------------------------------------------------------

func _update_collision(eye: Vector3) -> void:
	var built := 0
	_floorless = 0
	for chunk in _visible:
		# The true position, deliberately, where the refine pass uses the lead. A
		# collider is what the body stands on, so leading this would take the
		# floor out from under a viewer that had just slowed down or turned. The
		# ground ahead needs no body until it is arrived at, and by then the lead
		# has already had its mesh built, which is the part that takes time.
		if _distance(chunk, eye) >= collision_range:
			if chunk.body != null:
				chunk.body.queue_free()
				chunk.body = null
			continue
		if chunk.body != null:
			continue
		# Ground that is drawn, is close enough to walk on, and has nothing to
		# walk on it with. A steady figure here is a real hole: the body budget
		# is a queue and is meant to drain, so this should only ever be non-zero
		# for the frames after arriving somewhere.
		#
		# Counted **before** the faces are looked at, and that is the whole point
		# of the ordering. A drawn chunk whose build produced no collision soup
		# is the one hole that can never drain, and folding that test into the
		# reachability check above — which is how this was written — left it as
		# the one hole this counter could not see. The only instrument for the
		# fault read zero precisely when the fault was permanent.
		_floorless += 1
		if chunk.collision_faces.is_empty() or built >= bodies_per_frame:
			continue
		built += 1
		chunk.body = _make_body(chunk)


func _make_body(chunk: Chunk) -> StaticBody3D:
	var shape_resource := ConcavePolygonShape3D.new()
	shape_resource.set_faces(chunk.collision_faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape_resource
	var body := StaticBody3D.new()
	body.position = chunk.origin
	body.add_child(collider)
	add_child(body, false, Node.INTERNAL_MODE_BACK)
	return body


# --- Geometry ---------------------------------------------------------------

## The unit direction at a point inside a chunk, given in the chunk's own [0, 1]
## coordinates.
func _direction(chunk: Chunk, u: float, v: float) -> Vector3:
	var basis_axes: Array = FACES[chunk.face]
	var face_u := chunk.offset.x + u * chunk.size
	var face_v := chunk.offset.y + v * chunk.size
	return (basis_axes[0] as Vector3
		+ (basis_axes[1] as Vector3) * _spread(face_u)
		+ (basis_axes[2] as Vector3) * _spread(face_v)).normalized()


## Pushes cube coordinates out toward the edges before they are normalized.
## Without it a face's middle quads project far larger than its corner ones, and
## triangle size — which is what the LOD is budgeting — varies by about 1.4x
## across a single chunk.
func _spread(coordinate: float) -> float:
	return tan(coordinate * PI * 0.25)


## Where the detail is being built around, in planet-local metres. Public because
## the sea has to follow the same point the ground does, and because working out
## what counts as a viewer in the editor is a job with one right answer.
func viewer_position() -> Vector3:
	if is_instance_valid(viewer):
		return to_local(viewer.global_position)
	# In the editor the detail has to follow the camera being flown around the
	# scene, which is not the edited scene's own camera and is not reachable
	# through this node's viewport. Reached through the engine rather than named
	# outright, because `EditorInterface` does not exist in an exported build and
	# naming it there is a compile error rather than a branch never taken.
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		var editor := Engine.get_singleton(&"EditorInterface")
		var view := editor.call(&"get_editor_viewport_3d", 0) as SubViewport
		var editor_camera := view.get_camera_3d() if view != null else null
		if editor_camera != null:
			return to_local(editor_camera.global_position)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return to_local(camera.global_position)
	return Vector3.ZERO
