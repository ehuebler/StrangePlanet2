@tool
class_name PlanetShape
extends Resource

## The planet's height field: the one function that turns a direction from the
## centre into an elevation, a surface normal and a colour.
##
## The mesh builder and the player both read the ground through this, so there is
## no second copy of the terrain to drift out of step. Everything here is a pure
## function of position and is called from mesh worker threads, so nothing may
## cache per-call state on the resource — call [method prepare] once on the main
## thread before any chunk is built.
##
## Elevations are metres relative to sea level, so negative is under water and the
## shoreline is exactly zero. Feature sizes are wavelengths in metres, which is
## the only unit that stays meaningful if the radius changes.
##
## Every read takes the [code]spacing[/code] it is being sampled at, and features
## too fine to survive that spacing are faded out instead of aliased. Without it a
## chunk sampling every 25 m steps straight over a 45 m river gorge that its finer
## neighbour resolves in full, and the two meet in a cliff tens of metres tall.

## Fibonacci-sphere samples used to find the shoreline.
const SURVEY_SAMPLES := 4096

## How far the continent field has to travel inland from the shoreline before the
## ground is as inland as it gets. The sea has its own, shorter span; see
## [member abyss_span] for why the two are not the same number.
const CONTINENT_SPAN := 0.55

# Biome colours at map strength. They are the whole surface a chunk carries, so
# they are chosen to be told apart from orbit; the surface shader adds the grain,
# the region hue and the light that turn them into ground up close.
const DEEP_WATER := Color(0.04, 0.20, 0.46)
const SHALLOW_WATER := Color(0.15, 0.66, 0.74)
const SHORE := Color(0.92, 0.83, 0.56)
const GRASS := Color(0.33, 0.66, 0.25)
const UPLAND := Color(0.19, 0.45, 0.27)
const ROCK := Color(0.46, 0.42, 0.42)
const SNOW := Color(0.95, 0.96, 1.00)
# Arid country, in the order a cliff face stacks them. Sandstone reads as bands
# because it was laid down as bands, so these are a *sequence* and not a palette
# to pick from: [method _strata] walks them by altitude, which is what puts the
# same courses at the same height on every butte in sight of each other and is
# most of why the result looks deposited rather than noisy.
## Darker than sandstone looks in a photograph, and deliberately. The scene runs
## about 1.4 of light through a surface before ACES tone maps it, so a colour
## written at the value the rock reads at comes out washed pink — which is what
## the first pass at this did across a whole hemisphere. Judge these under
## `dev/_planet_test.tscn -- --tour` and nowhere else, the same rule the city
## road tones are held to.
const MESA_MAROON := Color(0.26, 0.10, 0.09)
const MESA_RED := Color(0.45, 0.16, 0.09)
const MESA_ORANGE := Color(0.62, 0.29, 0.11)
const MESA_CREAM := Color(0.70, 0.57, 0.36)
## Dust on anything flat enough to hold it. Bands are a cliff feature — a bench
## top is covered in its own debris — so the flats fade to this and only the
## risers carry the sequence above.
const DESERT_FLOOR := Color(0.56, 0.38, 0.22)
# A geyser basin: sinter white, the bacterial mats that ring a hot pool, and the
# pool itself. Placed on the lake field rather than a field of their own, so a
# basin sits exactly where an arid region would otherwise have had standing water.
const SINTER := Color(0.91, 0.89, 0.83)
const MAT_ORANGE := Color(0.88, 0.51, 0.16)
const POOL_BLUE := Color(0.13, 0.58, 0.70)
## Pack ice, which is not snow: ice is dense enough to swallow the warm end of
## the light and hand back the blue, and reading as a paler shade of the snow
## beside it is what made the arctic one flat white field with no coastline in it.
const ICE := Color(0.76, 0.90, 0.97)
## The south-pole caldera. Kept nearly neutral so the terrain splatter chooses
## photographed stone, while the oxide warmth and shader-side ember fissures
## stop the whole biome reading as one black disc from above.
const VOLCANIC_BASALT := Color(0.075, 0.065, 0.07)
const VOLCANIC_ASH := Color(0.17, 0.145, 0.14)
const VOLCANIC_OXIDE := Color(0.30, 0.095, 0.035)

## Alpha at the waterline. Vertex alpha carries how wet the ground is, and the
## shader reads anything above zero as water; starting the ramp here rather than
## at zero leaves a band of damp sand that a triangle spanning the shore can
## interpolate across.
const SHORE_WETNESS := 0.2

## Height the frozen sea is lifted to, in metres above sea level.
##
## Pack ice is not drawn as water at all: [method elevation] raises everything
## under the waterline inside the cap to exactly this, so the arctic ocean
## becomes a flat plain in the ordinary height field. Every system downstream
## then gets the ice for free and with no new concepts — the mesh draws it, the
## chunk colliders collide with it, the player's ground guard stands on it, and
## the sea's own disc is left underneath where the depth test hides it. Sea
## level itself is untouched, so [method PlanetWater.depth_at] still reports the
## water it always did and nobody swims through the floe.
##
## Freeboard, and not the centimetre a floe really has, because a chunk's
## triangles are chords and a chord cuts inside the sphere it spans. Between two
## vertices s apart the mesh dips about s^2 / 8R below the surface it describes —
## a hand's width at the finest spacing, four metres at five hundred — so a floe
## sitting at sea level spends most of its area underneath the sea drawn over it,
## and the water disc shows through in rings. Three metres buys every LOD anyone
## stands on. It does not buy the coarse ones seen from orbit, where the dip is
## tens of metres; that is why `vivid_water` fades the sea out inside the cap
## rather than relying on this alone.
const ICE_TOP := 3.0

## Wetness written under pack ice. Enough that `vivid_terrain` shades it with the
## smooth, specular treatment it gives water — which is what ice wants too — and
## far enough under the deep-water ramp that none of the blue comes with it.
const SEA_ICE_WETNESS := 0.3

@export var radius := 8000.0
## Named to avoid shadowing GDScript's own seed().
@export var noise_seed := 20260801

@export_group("Feature sizes, metres")
## Distance between continents. At the default radius the equator is ~50 km, so
## 8.2 km gives a handful of landmasses rather than a marbled mess.
@export var continent_wavelength := 8200.0
@export var mountain_wavelength := 1500.0
## Distance between mountain *ranges*, as against between peaks.
##
## The second of the two ridge fields the mountains are shaped from. Deliberately
## much coarser than [member mountain_wavelength] rather than the near-neighbour
## a shader graph would reach for: two fields a hair apart only produce more of
## the same crests, whereas one at two and a half times the span describes where
## the uplift *is*, and the peaks then gather into ranges with plain between them
## instead of being spread evenly over every rough acre.
@export var massif_wavelength := 3800.0
@export var hill_wavelength := 300.0
@export var detail_wavelength := 52.0
@export var river_wavelength := 2400.0
## Controls where the ground is rough and where it is plain, independently of
## how high it is. Without it every inland acre would be hills.
@export var roughness_wavelength := 3600.0
@export var lake_wavelength := 950.0

@export_group("Elevations, metres")
## Relief is kept to under a tenth of the radius on purpose. A 500 m mountain is a
## serious climb at 1.45 m tall, but much more than that on a planet this size and
## the silhouette stops reading as a sphere and starts reading as a potato.
##
## The sea bed is exempt from that budget, because the water surface is what the
## silhouette is made of out there and the floor is under it either way.
##
## Depth of the abyssal plain, which is deliberately deeper than the mountains are
## tall: an ocean floor within a few tens of metres of its own surface reads as a
## flooded field, and worse, as the water itself.
@export var ocean_depth := 480.0
## Depth of the shelf, the apron of shallows a coast wades out across before the
## floor falls away. This is the only depth most swimming ever happens in.
@export var shelf_depth := 22.0
## Where the shelf breaks and the slope to the abyss begins, as a share of the
## span from shoreline to open ocean. Small, because a shelf that is most of the
## ocean puts the whole sea back at the surface.
@export_range(0.02, 0.6) var shelf_break := 0.16
## How far the continent field has to fall past the shoreline before the sea bed
## is at full depth. Much shorter than the span a coast takes to reach full
## height, and that asymmetry is the point: an ocean is a basin with a slope
## round its edge, not a bowl. Measured against the same field, so this is
## directly comparable to [constant CONTINENT_SPAN] — at a third of it, half the
## sea bed lies past the slope instead of on the shelf.
@export_range(0.05, 1.0) var abyss_span := 0.32
## Relief on the sea bed itself. Faded in with depth, so it is dunes and trenches
## out in the dark and nothing at all where it could break the surface.
@export var seabed_relief := 34.0
@export var land_height := 260.0
## Height of the mountains, which is now the height of the *summits* only.
##
## Raised from the 300 it was, and it had to be. The shaping below flattens
## everything below its lower stop into plain, so where the old cubed ridge
## spread a broad hundred-and-twenty-metre swell across all rough country, this
## spends the whole allowance on the fraction that is actually mountain. Same
## budget, concentrated. Still inside the tenth of the radius the silhouette can
## carry: 260 of continent and 400 of summit is 660 against 800.
@export var mountain_height := 400.0
@export var hill_height := 24.0
@export var detail_height := 2.4
@export var river_depth := 45.0
@export var lake_depth := 38.0

@export_group("Mountain shape")
## The mountains are two ridge fields mixed and then put through a hard remap,
## which is the terrain-artist recipe — two noise nodes, a mix, a colour ramp, a
## displacement — written as arithmetic. It replaced a single ridged field cubed,
## and the reason is what cubing does: it pulls the whole noise range down at
## once, so it flattens plains and summits alike and leaves only a thin crease
## along every zero contour of every octave standing. That crease, at five
## octaves, is the field of sharp little spikes that used to be everywhere.
##
## The remap is what fixes it, because it separates the two decisions that
## cubing had welded together. [member mountain_plain] decides *where* there are
## mountains, by putting a floor under the field that plain ground never clears.
## [member mountain_sharpness] decides what the mountains that remain look like.
## Sharp points are still entirely available — more so, since the exponent now
## works on a normalised band rather than on raw noise — but they are now
## somewhere specific rather than a texture over the whole planet.
##
## How much of the broad field is mixed into the fine one, 0 to 1.
##
## Mixed and not multiplied. Multiplying would scale every crest by whatever the
## broad field happened to be underneath it, thinning the ranges it was supposed
## to be picking out; mixing leaves crests at full height and lets the floor
## below do the selecting, so a crest survives exactly where the broad field is
## high enough to carry it over.
@export_range(0.0, 1.0) var mountain_mix := 0.45
## The remap's lower stop: field values at or below this are flat ground.
##
## The most powerful number in this group and the one to reach for first. The
## mixed field sits around 0.74 with most of its mass between 0.55 and 0.95, so
## this is a knob with a narrow useful range and a lot of authority inside it —
## 0.6 makes most of the rough country mountainous, 0.85 leaves a few ranges in a
## lot of plain. It reads as "how much of the planet is mountain" and nothing
## else here changes that.
@export_range(0.0, 1.0) var mountain_plain := 0.72
## The remap's upper stop: field values at or above this are at full height.
##
## What pulling it below 1 buys is *flat* summits, because a clipped peak is a
## plateau — which is the difference between an alpine ridge line and a table
## mountain. Left at 1 here, and that is the setting that answers the brief:
## anything lower and the summits come off level, so from underneath one every
## profile between a spire and a dome draws the same flat-topped wedge and the
## sharpness below has nothing left to act on. At 0.97 this planet's highest
## ground was a smooth snow tableland.
##
## The desert keeps its tables regardless, which is why giving them up here costs
## nothing: terracing in [method mesa] makes those, out of arid ground, and it is
## a better mesa than clipping this ever was because it stacks benches rather
## than shearing one flat top.
@export_range(0.0, 1.0) var mountain_peak := 1.0
## Profile of the climb from plain to summit.
##
## Above 1 the slope is concave and the peak is a spire; below 1 it is convex and
## the peak is a dome. This is the sharp-points control, and it is a better one
## than the old cubed ridge because it is applied after the remap has normalised
## the band — the exponent shapes the mountain instead of also deciding how much
## of the planet is one.
@export_range(0.2, 6.0) var mountain_sharpness := 2.6
## How much sharper the roughest country is than the smoothest, as a multiplier
## on [member mountain_sharpness].
##
## Sharp crags are wanted in some places and not as a planet-wide texture, and
## the roughness field is already the thing that says which places: it decides
## how tall the mountains are, so letting it decide how pointed they are too
## means crags arrive with the terrain that should have them. At 1 the whole
## planet shares one profile.
@export_range(1.0, 4.0) var mountain_crag := 1.8

@export_group("Water")
## Share of the surface below sea level. The raw noise's own zero crossing drifts
## with the seed, so the shoreline is solved for at prepare() rather than assumed.
@export_range(0.0, 0.95) var sea_fraction := 0.44
## Half-width of the river channel in noise units. ~0.012 reads as a river a few
## tens of metres across at the default wavelength.
@export_range(0.0, 0.2) var river_width := 0.012
## Roughly how wide a river ends up on the ground. Only used to decide the mesh
## spacing at which rivers stop being resolvable and start being faded out.
@export var river_channel := 45.0
## Noise level above which a lowland flat sinks into a lake bed. Lower floods more.
@export_range(0.0, 1.0) var lake_threshold := 0.60

@export_group("Arid country")
## Share of the land that is desert. The whole look below hangs off this one
## number: at 0 the planet is the green one it was, at 1 there is no grass left
## anywhere. It is approximate rather than solved the way [member sea_fraction]
## is, because nothing downstream depends on the exact figure — no shoreline has
## to come out in the right place — so a threshold on the raw field is enough.
@export_range(0.0, 1.0) var aridity := 0.66
## Distance between deserts. Deliberately smaller than the continents so that a
## single landmass carries both, and a green valley is something you fly out of
## the red country to reach rather than a different continent.
@export var arid_wavelength := 4600.0

## Height of one bench, in metres.
##
## This is the number that turns hills into mesas, and the most powerful one in
## the file. The ground is quantised onto multiples of it, so a slope that used
## to run smoothly uphill becomes a staircase of flat tops and steep risers —
## which is what Monument Valley is, geologically and visually: level courses of
## rock, each eroding back at its own rate.
@export var terrace_height := 32.0
## Share of each bench spent climbing rather than flat. Small is dramatic: at
## 0.2 a fifth of the rise is cliff and four fifths is tableland. Past about 0.5
## it stops reading as terracing at all and is just a slightly lumpy hill.
@export_range(0.02, 0.9) var terrace_riser := 0.2
## The sample spacing at which benches stop being drawn, in metres. Cliffs are
## the one thing here that genuinely cannot survive a coarse mesh — a riser is
## near-vertical and a chunk stepping over it aliases into a sawtooth — so they
## fade like every other fine feature. Set generously: the fade is what a distant
## mesa loses, and losing it looks like a smooth hill rather than like an error.
@export var terrace_span := 120.0

## Extra depth of a slot canyon over an ordinary river, in metres.
##
## Cut from the same noise field the rivers use and therefore free, which is also
## why it is right: a canyon is what a river does to arid ground given time, so
## the two belong on the same lines. It is applied above the waterline only, so a
## canyon is a dry gorge and its lowland reaches are still the river they were.
@export var canyon_depth := 120.0
## Half-width of the slot, in noise units. Far narrower than [member river_width]
## — the point of a slot canyon is that it is a crack you could jump across at
## the top and a hundred metres deep.
@export_range(0.0, 0.05) var canyon_width := 0.0035

## Thickness of one colour course, in metres.
##
## **Must not divide [member terrace_height] evenly**, and that is not a nicety.
## Terracing quantises the ground onto multiples of the bench height, so if the
## courses shared a period with it every bench top in the world would land on the
## same colour and the banding would vanish everywhere except the risers — which
## is exactly what the first attempt did, and it came out a uniform salmon. Left
## incommensurate, successive benches land at different points in the sequence and
## a staircase of tablelands climbs through the whole palette.
@export var stratum_height := 11.5

## Height of a hoodoo above the bench it stands on, in metres.
##
## Spires stand on the lip of a riser, which is where they form: a bench erodes
## back and leaves columns of the harder course behind it. They are the finest
## thing on the planet and the first to fade, so they are only ever seen from
## close to — which is the honest treatment, since at 1.5 m between vertices a
## spire is four vertices across and would read as speckle at any distance.
@export var hoodoo_height := 17.0
## Distance between spires, in metres.
@export var hoodoo_wavelength := 21.0
## The level the spire field has to reach before a column stands.
##
## How rare a hoodoo is, and the number that decides whether these read as rock
## or as a sawtooth pattern laid over the desert. It was effectively 0.80, and
## the trouble with 0.80 is that the field averages about 0.74 — so a third of
## every bench lip cleared it and the columns came out shoulder to shoulder,
## which is not what a hoodoo is. A hoodoo is a survivor, the last of a bench
## that eroded away from around it, and survivors are sparse by definition.
##
## The field's mass sits between about 0.55 and 0.95, so the useful range here is
## narrow and the top of it is very sensitive: 0.90 is a crowd, 0.97 is a handful
## of landmarks per escarpment.
@export_range(0.5, 0.99) var hoodoo_stand := 0.94
## Distance between hoodoo amphitheatres, in metres.
##
## Which escarpments grow spires and which are bare rock. Without this the only
## test was the bench lip, and a lip is a *contour* — it traces every bench in
## the desert at once, so every one of them got columns. Worse, it fails hardest
## where the ground is most interesting: as a slope steepens its benches crowd
## together in plan, so the dashed lines of spires close up into a single
## serrated wall running down the side of every canyon.
##
## Coarse on purpose. The answer wants to hold for a whole amphitheatre rather
## than flicker along it, which is the difference between hoodoo country and
## speckle.
@export var badland_wavelength := 700.0
## How much of the arid country is hoodoo country, as a level on that field.
##
## Higher leaves fewer, larger gaps between the places that have spires at all.
## Around 0.62 the desert reads as mostly bare benches with the occasional
## amphitheatre worth walking into.
@export_range(0.0, 1.0) var badland_reach := 0.62

@export_group("Polar cap")
## How much of the planet's surface is arctic, as a share of its area.
##
## Stated as an area rather than as an angle because that is the only form the
## number means anything in — "18% of the planet" against "50 degrees from the
## pole" — and the two are one line apart: a cap of area f subtends
## cos(theta) = 1 - 2f, which is the form every query below actually uses.
@export_range(0.0, 0.5) var frost_area := 0.18
## Width of the cap's edge, in the same units. The ground is fully arctic inside
## `frost_area - frost_blend / 2` and untouched outside `frost_area +
## frost_blend / 2`. It wants to be wide enough that the pack ice runs out into
## open sea over a kilometre or two rather than ending in a wall.
@export_range(0.0, 0.3) var frost_blend := 0.06
## Which way is north, in planet-local space.
@export var frost_axis := Vector3.UP

@export_group("South-pole volcano")
## A broad volcanic island centred on the antipode of [member frost_axis].
## Geometry lives in the height field, so terrain LOD, collision, flora surveys,
## the ground guard, and the map all receive the same caldera.
@export var volcano_enabled := true
@export var volcano_radius := 1450.0
@export var volcano_island_height := 55.0
@export var volcano_cone_radius := 980.0
@export var volcano_cone_height := 500.0
@export var volcano_crater_radius := 190.0
@export var volcano_crater_depth := 145.0
## Three breached directions. Each flow follows one and ends in the matching
## lower pool described below.
@export var volcano_flow_angles := Vector3(0.65, -1.55, 2.55)
@export var volcano_channel_width := 34.0
@export var volcano_channel_depth := 135.0
## (distance from pole, visible radius, lava-surface elevation), in metres.
@export var volcano_pool_one := Vector3(760.0, 130.0, 126.0)
@export var volcano_pool_two := Vector3(870.0, 105.0, 76.0)
@export var volcano_pool_three := Vector3(810.0, 120.0, 100.0)
@export var volcano_pool_depth := 10.0
## Width of the shallow shelf that brings each basin floor back up to meet the
## visible liquid. Half lies beneath the pool and half forms its bank.
@export var volcano_pool_shore_width := 18.0
## How far the ground meets the liquid below its top, avoiding a z-fighting seam
## while still leaving no camera-height gap around the shore.
@export var volcano_pool_shore_overlap := 0.25
@export var volcano_crater_lava_height := 420.0

@export_group("Settlements")
## Whether the planet has towns on it at all. Clear it for the untouched noise, which
## is what the planet export and anything measuring raw terrain wants.
@export var settled := true
## The towns, each replacing the terrain inside its own footprint. Left empty and
## [member settled], it is filled from [Settlements], so a bare shape in a harness
## describes the same planet the game does.
##
## A list rather than one city, and the cost of that is a dot product per town on both
## hot paths below. That is affordable while this is a handful of settlements and would
## not be at a hundred: past that the caps want sorting into a coarse grid over the
## sphere so a direction tests against its own neighbourhood instead of against
## everywhere.
@export var cities: Array[CityPlan] = []

## A cosine no unit dot product can reach, which is how a town that is switched
## off keeps its row in the tables below without ever matching.
const UNREACHABLE_CAP := 2.0

## Where a feature is fully resolved, as a fraction of its own width. See
## [method _resolves], which is this rule written out.
const RESOLVE_FLOOR := 0.33

## [member cities]' `near` test, flattened: the cap axis and the cosine to beat,
## one row per town in the same order. See `prepare`.
var _town_up: PackedVector3Array = []
var _town_cap: PackedFloat32Array = []

## The native height field. Built in [method prepare] and read-only afterwards,
## which is what makes it safe on the mesh worker threads.
##
## Typed, and that is a performance requirement rather than tidiness. Held as an
## [Object] the call is resolved by name against [ClassDB] every time, which
## takes a global read lock — four build threads asking a few thousand times each
## per chunk turned a sample that had got cheaper into one that was twenty times
## dearer, and it reads as the whole terrain pipeline stalling rather than as a
## slow function. Typed, GDScript binds the method once and calls it directly.
var _field: PlanetField

## Marks abilities have left on the ground, applied after everything else so a
## crater cuts through a city pad as readily as through open country.
##
## Held here rather than on [Planet] because this resource is the one thing the
## mesh builder, the collision generator, the flora surveys and the player's
## ground guard all read the terrain through. A deformation that lived anywhere
## else would be a second version of the ground, and the two would disagree the
## moment anything cached.
var scars := TerrainScars.new()

## Where the arid field is cut to leave [member aridity] of the land desert.
var _arid_edge := 0.0
var _sea_bias := 0.0
var _pole := Vector3.UP
## Cosines of the cap's outer and inner edges, in that order, so [method frost]
## is one dot product and one smoothstep on the hot path.
var _frost_edge := 0.0
var _frost_full := 0.0
## Allows source changes to run before Windows releases the loaded GDExtension
## DLL for relinking. New native fields identify themselves with a `volcano`
## sample key; an older binary falls back to the identical pure functions below
## and routes only south-pole chunks through Planet's scripted patch builder.
var _native_volcano := false
var _built := false


## Builds the noise fields and solves for the shoreline. Must run on the main
## thread before any worker calls [method elevation].
func prepare() -> void:
	if _built:
		return
	# The arithmetic lives in the native field; this resource owns the numbers,
	# the towns and the API. See AGENTS.md for why the split is here and not
	# somewhere more convenient — briefly, everything above this line is data a
	# designer edits and everything below it is a few thousand samples per chunk.
	_field = PlanetField.new()
	_field.configure(native_settings(self))
	scars.planet_radius = radius
	# Simplex clusters around zero rather than spreading evenly, so the useful
	# half of this range is the middle: the ends are asking for a threshold the
	# field almost never crosses, which is why it stops short of +-1.
	_arid_edge = lerpf(-0.5, 0.5, 1.0 - aridity)
	_sea_bias = float(_field.solve_sea_bias(SURVEY_SAMPLES, sea_fraction))
	_pole = frost_axis.normalized() if frost_axis.length_squared() > 0.0 else Vector3.UP
	_native_volcano = (_field.sample(-_pole) as Dictionary).has("volcano")
	_frost_edge = 1.0 - 2.0 * clampf(frost_area + frost_blend * 0.5, 0.0, 1.0)
	_frost_full = 1.0 - 2.0 * clampf(frost_area - frost_blend * 0.5, 0.0, 1.0)
	if not settled:
		cities.clear()
	elif cities.is_empty():
		cities.assign(Settlements.plans())
	for town: CityPlan in cities:
		town.prepare(radius)
	# `near()` is two comparisons and a dot product, and calling it costs several
	# times what it does: at two towns the test was 0.82 µs of a 6.7 µs sample,
	# 12% of every height on the planet spent on cross-resource call overhead
	# rather than on arithmetic. Cached flat so the hot paths can ask inline.
	#
	# One row per town whether or not it is switched on, so an index into these
	# is an index into `cities`: a town that can never answer yes is given a cap
	# no dot product can reach rather than being left out, because dropping it
	# would silently shift every later town onto the wrong plan.
	_town_up.clear()
	_town_cap.clear()
	for town: CityPlan in cities:
		var bounds := town.near_bounds()
		var live := bounds != Vector4.ZERO
		_town_up.append(Vector3(bounds.x, bounds.y, bounds.z) if live else Vector3.UP)
		_town_cap.append(bounds.w if live else UNREACHABLE_CAP)
	_built = true


## How arctic a direction is: 0 outside the polar cap, 1 inside it, and a ramp
## across the edge.
##
## Everything that changes at the pole is this one number — the white ground, the
## pack ice, the deeper cloud deck, the snow the player wades through — so the
## cap has exactly one boundary and nothing downstream can disagree about where
## it is. The shader side reads the same figures through `vivid_frost`, which
## `Planet` keeps fed from here.
##
## Deliberately takes no [code]spacing[/code]. The cap moves the ground, and
## ground may not fade with detail: a chunk that dropped the ice at coarse
## spacing would draw the sea bed the finer chunk beside it draws as a floe, and
## they would meet in a cliff four hundred metres tall. Same reason the city pad
## ignores spacing; see the note on [method elevation].
func frost(direction: Vector3) -> float:
	return smoothstep(_frost_edge, _frost_full, direction.dot(_pole))


## Cosine of the cap's outer edge, where frost reaches zero. For `Planet` to
## publish to the shaders; nothing else should need it.
func frost_outer() -> float:
	return _frost_edge


## Cosine of the cap's inner edge, where frost reaches one.
func frost_inner() -> float:
	return _frost_full


## Centre of the volcanic biome in planet-local space.
func volcano_axis() -> Vector3:
	return -_pole


## Smooth biome weight, one through the island and zero beyond its coast.
func volcano_influence(direction: Vector3) -> float:
	if not volcano_enabled or volcano_radius <= 0.0:
		return 0.0
	var south := volcano_axis()
	var outer := cos(volcano_radius / maxf(radius, 1.0))
	var inner := cos(volcano_radius * 0.82 / maxf(radius, 1.0))
	return smoothstep(outer, inner, direction.normalized().dot(south))


## Tangent-plane metres from the south pole. The cap is small enough that an
## azimuthal distance is effectively exact, and unlike latitude/longitude this
## remains well-defined at the pole itself.
func volcano_coordinates(direction: Vector3) -> Vector2:
	var south := volcano_axis()
	var out := direction.normalized()
	var cosine := clampf(out.dot(south), -1.0, 1.0)
	var distance := acos(cosine) * radius
	var tangent := out - south * cosine
	if tangent.length_squared() < 0.0000001:
		return Vector2.ZERO
	tangent = tangent.normalized()
	var east := south.cross(
		Vector3.UP if absf(south.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := south.cross(east).normalized()
	return Vector2(tangent.dot(east), tangent.dot(north)) * distance


## Shared by the terrain basins, visible liquid meshes, and player query. A
## Vector3 pool export is (distance, radius, surface elevation).
func volcano_lava_pools() -> Array[Dictionary]:
	var pools: Array[Dictionary] = [{
		"offset": Vector2.ZERO,
		"radius": volcano_crater_radius * 0.62,
		"height": volcano_crater_lava_height,
		"seed": 3,
		"crater": true,
	}]
	var packed := [volcano_pool_one, volcano_pool_two, volcano_pool_three]
	for index in packed.size():
		var pool: Vector3 = packed[index]
		var angle := volcano_flow_angles[index]
		pools.append({
			"offset": Vector2(cos(angle), sin(angle)) * pool.x,
			"radius": pool.y,
			"height": pool.z,
			"seed": 11 + index * 7,
			"crater": false,
			"flow_angle": angle,
		})
	return pools


## The irregular visible shoreline shared by the liquid mesh, its analytical
## query, and the terrain basin beneath it.
func volcano_pool_radius(base: float, angle: float, seed: int) -> float:
	var phase := float(seed) * 0.731
	return base * (0.91
		+ sin(angle * 3.0 + phase) * 0.045
		+ sin(angle * 7.0 - phase * 1.7) * 0.028
		+ sin(angle * 11.0 + phase * 0.43) * 0.018)


func _volcano_channel(coordinates: Vector2) -> float:
	var distance := coordinates.length()
	if volcano_channel_depth <= 0.0 or volcano_channel_width <= 0.0 \
			or distance <= volcano_crater_radius * 0.55 \
			or distance >= volcano_cone_radius * 1.02:
		return 0.0
	var angle := coordinates.angle()
	var channel := 0.0
	for flow_angle: float in [
			volcano_flow_angles.x,
			volcano_flow_angles.y,
			volcano_flow_angles.z,
		]:
		var delta := angle - flow_angle
		if cos(delta) <= 0.0:
			continue
		var lateral := absf(sin(delta)) * distance
		channel = maxf(channel, 1.0 - smoothstep(
			volcano_channel_width, volcano_channel_width * 2.2, lateral))
	var from_crater := smoothstep(
		volcano_crater_radius * 0.55, volcano_crater_radius, distance)
	var toward_foot := 1.0 - smoothstep(
		volcano_cone_radius * 0.82, volcano_cone_radius * 1.02, distance)
	var cone := smoothstep(volcano_cone_radius, volcano_crater_radius, distance)
	return volcano_channel_depth * channel * from_crater * toward_foot * cone


func _volcano_one_pool_basin(coordinates: Vector2, centre: Vector2,
		base_radius: float, surface: float, seed: int, height: float) -> float:
	var relative := coordinates - centre
	var away := relative.length()
	# Almost every volcano sample is nowhere near any one pool. Reject it before
	# evaluating the three sines that make that pool's irregular edge.
	var widest_edge := base_radius * 1.001
	var widest_shore := clampf(
		volcano_pool_shore_width, 0.1, widest_edge * 0.45)
	if away >= widest_edge + widest_shore:
		return height
	var edge := volcano_pool_radius(base_radius, relative.angle(), seed)
	var shore := clampf(volcano_pool_shore_width, 0.1, edge * 0.45)
	var floor_edge := edge - shore
	var outer_edge := edge + shore
	if away >= outer_edge:
		return height
	var floor := surface - volcano_pool_depth
	var lip := surface - volcano_pool_shore_overlap
	if away <= floor_edge:
		return floor
	if away < edge:
		return lerpf(floor, lip, smoothstep(floor_edge, edge, away))
	return lerpf(lip, height, smoothstep(edge, outer_edge, away))


func _volcano_pool_basin(coordinates: Vector2, height: float) -> float:
	# The crater lake is a pool too. Its old crater profile left the whole basin
	# ten metres below a surface-only lava disc, exactly like the three lower
	# pools, so it needs the same rising shore.
	height = _volcano_one_pool_basin(
		coordinates, Vector2.ZERO, volcano_crater_radius * 0.62,
		volcano_crater_lava_height, 3, height)
	var pools := [volcano_pool_one, volcano_pool_two, volcano_pool_three]
	for index in pools.size():
		var pool: Vector3 = pools[index]
		var angle := volcano_flow_angles[index]
		var centre := Vector2(cos(angle), sin(angle)) * pool.x
		height = _volcano_one_pool_basin(
			coordinates, centre, pool.y, pool.z, 11 + index * 7, height)
	return height


func _volcano_height(direction: Vector3, height: float, spacing: float) -> float:
	var influence := volcano_influence(direction)
	if influence <= 0.0:
		return height
	var coordinates := volcano_coordinates(direction)
	var distance := coordinates.length()
	var cone := smoothstep(volcano_cone_radius, volcano_crater_radius, distance)
	var crater := 1.0 - smoothstep(
		volcano_crater_radius * 0.62, volcano_crater_radius, distance)
	var target := volcano_island_height + volcano_cone_height * cone \
		- volcano_crater_depth * crater
	var detail_fade := smoothstep(180.0, 55.0, spacing)
	if detail_fade > 0.0 and cone > 0.0 and crater < 1.0:
		target += _field.noise_at("_hills", direction) * 18.0 \
			* cone * (1.0 - crater) * detail_fade
	target -= _volcano_channel(coordinates)
	var shaped := lerpf(height, target, influence)
	return _volcano_pool_basin(coordinates, shaped)


func _volcano_color(direction: Vector3, ground: Color) -> Color:
	var influence := volcano_influence(direction)
	if influence <= 0.0:
		return ground
	var soot := _field.noise_at("_hills", direction) * 0.5 + 0.5
	var basalt := VOLCANIC_BASALT.lerp(
		VOLCANIC_ASH, 0.24 + soot * 0.52)
	var oxide := smoothstep(0.74, 0.94,
		_field.noise_at("_roughness", direction) * 0.5 + 0.5)
	basalt = basalt.lerp(VOLCANIC_OXIDE, oxide * 0.32)
	basalt.a = 0.0
	return ground.lerp(basalt, influence)


# --- The height field -------------------------------------------------------

## Metres above sea level along a unit direction from the planet's centre.
##
## [param spacing] is the distance between the samples being taken, so that a
## coarse mesh gets a smoothed version of the same terrain rather than an aliased
## one. Pass 0 for the true surface.
##
## This is the hot path — a few hundred thousand calls per chunk — so it returns a
## bare float and leaves the breakdown to [method sample].
##
## The city is the one feature that ignores [param spacing] entirely. Everything
## else is faded out once the samples are too far apart to hold it, but a pad
## that faded would leave a distant chunk drawing the hills the city was built
## over while the player's ground guard — which always samples at the finest
## spacing — held them on the flat.
## Scars are taken off last of all, after the towns. A crater in a landing pad
## is a crater in a landing pad; there is no ground on this planet that an
## ability is not allowed to damage.
func elevation(direction: Vector3, spacing := 0.0) -> float:
	var height: float = _field.elevation(direction, spacing)
	if not _native_volcano:
		height = _volcano_height(direction, height, spacing)
	for index in _town_up.size():
		if direction.dot(_town_up[index]) >= _town_cap[index]:
			height = cities[index].elevation(direction, height)
			break
	return height - scars.depth_at(direction, spacing)


## Height without the city flatten. District ramps have to meet the grass the
## chunk actually draws; [method elevation] still reports the pad, which can sit
## metres above that mesh and leave a collider in empty air.
func natural_elevation(direction: Vector3, spacing := 0.0) -> float:
	var height: float = _field.elevation(direction, spacing)
	if not _native_volcano:
		height = _volcano_height(direction, height, spacing)
	return height - scars.depth_at(direction, spacing)


## The parts an elevation was made of: what the water is, how rough the ground is,
## how high it would have been dry. Surveys need this to tell a river from a lake,
## which cannot be done from the finished height alone. Built by the native field
## from the same helpers as [method elevation], so the two cannot drift apart.
func sample(direction: Vector3) -> Dictionary:

	var parts: Dictionary = _field.sample(direction)
	if not _native_volcano:
		var volcanic := volcano_influence(direction)
		if volcanic > 0.0:
			parts["elevation"] = _volcano_height(
				direction, float(parts["elevation"]), 0.0)
			parts["dry"] = maxf(float(parts.get("dry", 0.0)), volcanic)
			parts["river"] = 0.0
			parts["lake"] = 0.0
			parts["rough"] = maxf(float(parts.get("rough", 0.0)), volcanic)
			parts["arid"] = maxf(float(parts.get("arid", 0.0)), volcanic)
			parts["volcano"] = volcanic
	for index in _town_up.size():
		if direction.dot(_town_up[index]) >= _town_cap[index]:
			parts["elevation"] = cities[index].elevation(direction, parts["elevation"])
			break
	parts["elevation"] = float(parts["elevation"]) - scars.depth_at(direction)
	return parts


## The point on the surface below a unit direction, in planet-local space.
func surface_point(direction: Vector3, spacing := 0.0) -> Vector3:
	return direction * (radius + elevation(direction, spacing))


## Surface normal from central differences of the height field.
##
## [param spacing] is both how far apart the samples are taken and which features
## the height field is allowed to include, so the normals describe the mesh being
## built rather than a finer one it does not have the triangles for.
func normal_at(direction: Vector3, spacing: float) -> Vector3:
	var up := direction.normalized()
	var tangent := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent := up.cross(tangent)
	var step := maxf(spacing, 0.05) / radius
	var along_u := surface_point((up + tangent * step).normalized(), spacing) \
		- surface_point((up - tangent * step).normalized(), spacing)
	var along_v := surface_point((up + bitangent * step).normalized(), spacing) \
		- surface_point((up - bitangent * step).normalized(), spacing)
	var normal := along_u.cross(along_v)
	if normal.length_squared() < 1e-12:
		return up
	normal = normal.normalized()
	return normal if normal.dot(up) > 0.0 else -normal


## Whether a patch of ground this wide, centred here, could touch a town.
##
## Conservative on purpose: it is the test that decides whether a chunk may be
## built by the native field, which knows nothing about towns, and a false
## negative would build a pad as though the hills under it were still there.
## The chunk's own width is turned into an angle and taken straight off the cap's
## cosine, which over-estimates the reach — a cosine never falls faster than its
## angle — and so can only ever err toward the slower path.
func overlaps_town(centre: Vector3, arc: float) -> bool:
	if not _native_volcano and volcano_enabled:
		var reach := (volcano_radius + maxf(arc, 0.0)) / maxf(radius, 1.0)
		if centre.normalized().dot(volcano_axis()) >= cos(reach):
			return true
	if _town_up.is_empty():
		return false
	var direction := centre.normalized()
	var margin := arc / maxf(radius, 1.0)
	for index in _town_up.size():
		if direction.dot(_town_up[index]) >= _town_cap[index] - margin:
			return true
	return false


## Whether a chunk this wide has anything on it the native field cannot build.
##
## The native height field knows about noise, water, deserts and ice, and
## nothing about towns or scars — both of those are GDScript overrides applied
## on this side of the boundary. A chunk that touches either has to be built the
## slow way, through [method elevation], or it would come back with the pad or
## the crater missing.
##
## [method overlaps_town] is left as it was for the callers that genuinely mean
## "is there a settlement here".
##
## [param spacing] is how far apart the chunk's vertices will be. A scar too
## small to survive that spacing is not a reason to take the slow path, which is
## the difference between a two-metre burn costing one chunk and it costing
## every ancestor of that chunk up to the whole face.
func needs_script_build(centre: Vector3, arc: float, spacing := 0.0) -> bool:
	return overlaps_town(centre, arc) or scars.overlaps(centre, arc, spacing)


## One chunk's mesh, built in the native field. See [method Planet._build_natively].
func build_patch(face_origin: Vector3, face_u: Vector3, face_v: Vector3,
		offset: Vector2, size: float, resolution: int, spacing: float,
		skirt: float, chunk_origin: Vector3, want_collision: bool) -> Dictionary:
	return _field.build_patch(face_origin, face_u, face_v, offset, size,
		resolution, spacing, skirt, chunk_origin, want_collision)


## The biome colour for a point, with how wet it is in the alpha channel.
##
## Alpha is the one signal the surface shader cannot work out for itself: a chunk
## carries no elevation, and water has to be shaded as a smooth surface rather
## than as blue ground. 0 is dry, [constant SHORE_WETNESS] is the waterline, 1 is
## open ocean.
func color_at(direction: Vector3, height: float, normal: Vector3) -> Color:
	var ground: Color = _field.color_at(direction, height, normal)
	# Water is not zoned. The town cap is a disc on the sphere and the Landing's
	# reaches the sea, so a pad's concrete would otherwise be mixed into the
	# harbour — which is what happened for as long as this loop ran over every
	# colour rather than over the dry ones. Height, not alpha, decides: the
	# alpha channel is wetness and the shore is wet without being sea.
	if height <= 0.0:
		return ground
	if not _native_volcano:
		ground = _volcano_color(direction, ground)
	for index in _town_up.size():
		if direction.dot(_town_up[index]) >= _town_cap[index]:
			ground = cities[index].tint(direction, ground)
			break
	return scars.tint(direction, ground)


## Biome colour without the city's zoning overlay.
##
## [method color_at] paints lawn and concrete across the town cap, which is
## right for the pad itself and wrong for the slope that leaves it: a desert
## ramp should still read as desert. Height and volcano and scars stay, so a
## shore or a crater on that slope still looks like the country around it.
func biome_color_at(direction: Vector3, spacing := 0.0) -> Color:
	var up := direction.normalized()
	var height: float = _field.elevation(up, spacing)
	if not _native_volcano:
		height = _volcano_height(up, height, spacing)
	height -= scars.depth_at(up, spacing)
	var ground: Color = _field.color_at(up, height, up)
	if height <= 0.0:
		return ground
	if not _native_volcano:
		ground = _volcano_color(up, ground)
	return scars.tint(up, ground)


## Every tuning number the native field needs, by the name it has here.
##
## A dictionary rather than a setter per field because the alternative is fifty
## of them that all have to be kept in step with the exports above by hand, and
## a name missed is a number silently left at the C++ side's own default —
## which produces a plausible planet that is not this one. Keyed off the export
## list so adding a number here is the only edit a new tuning knob needs.
static func native_settings(shape: PlanetShape) -> Dictionary:
	var settings := {}
	for entry in shape.get_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_STORAGE == 0:
			continue
		var named: String = entry["name"]
		var value: Variant = shape.get(named)
		if value is float or value is int or value is bool or value is Vector3:
			settings[named] = value
	# The constants go over too, so this file stays the one place the planet's
	# palette and thresholds are written down. They could be literals on the
	# other side — they were, for one version — but a colour is the kind of thing
	# somebody edits without ever opening the C++, and a palette that exists twice
	# is a palette that will disagree.
	settings["CONTINENT_SPAN"] = CONTINENT_SPAN
	settings["RESOLVE_FLOOR"] = RESOLVE_FLOOR
	settings["SHORE_WETNESS"] = SHORE_WETNESS
	settings["ICE_TOP"] = ICE_TOP
	settings["SEA_ICE_WETNESS"] = SEA_ICE_WETNESS
	settings["palette"] = {
		"DEEP_WATER": DEEP_WATER, "SHALLOW_WATER": SHALLOW_WATER,
		"SHORE": SHORE, "GRASS": GRASS, "UPLAND": UPLAND, "ROCK": ROCK,
		"SNOW": SNOW, "ICE": ICE, "MESA_MAROON": MESA_MAROON,
		"MESA_RED": MESA_RED, "MESA_ORANGE": MESA_ORANGE,
		"MESA_CREAM": MESA_CREAM, "DESERT_FLOOR": DESERT_FLOOR,
		"VOLCANIC_BASALT": VOLCANIC_BASALT, "VOLCANIC_ASH": VOLCANIC_ASH,
		"VOLCANIC_OXIDE": VOLCANIC_OXIDE,
	}
	return settings


## One of [param count] directions spread evenly over the sphere, so a survey
## does not over-sample the poles the way a lat/long grid would.
static func even_direction(index: int, count: int) -> Vector3:
	var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
	var ring := sqrt(maxf(0.0, 1.0 - y * y))
	var angle := PI * (3.0 - sqrt(5.0)) * float(index)
	return Vector3(cos(angle) * ring, y, sin(angle) * ring)
