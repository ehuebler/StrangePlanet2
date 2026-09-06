# Vivid shader

The look the game runs on: real lighting, exaggerated colour. Godot's own PBR does
the shading in every one of these shaders — there is no custom `light()` function
anywhere — and the style comes entirely from what is fed into it. That split is the
whole idea. Hues are pushed past life, the light falling on them is not, and the
result reads as a bright real place rather than as a filter laid over one.

Three problems shaped it:

- **The art is flat.** Hand-painted ~500 px textures, single-colour Blender
  materials, no normal maps and no plan to author any. Lit plainly that reads as
  coloured plastic, so relief is manufactured from the albedo's own brightness and
  from 3D noise.
- **The map is a planet.** Ground, sky, air and props have to agree on where the
  planet is, which way is up at any point, and how high the camera is. They do
  that through global shader parameters rather than per-material uniforms.
- **Colour should mean somewhere.** The planet is painted as a colour wheel: hue
  runs around an axis the way longitude does, so a region gleams in its own colour
  and its neighbours arrive as a gradient rather than at a border.

## Files

| File | Role |
| --- | --- |
| `vivid_lib.gdshaderinc` | The planet frame, the colour wheel, noise and detail helpers |
| `vivid_terrain.gdshader` | The planet's ground: biome, cliffs, sea bed, caustics (`cull_back`) |
| `vivid_terrain_core.gdshaderinc` | Shared body of the ground shader |
| `vivid_terrain_apron.gdshader` | Same ground look on district ramps (`cull_disabled`, lifted) |
| `vivid_surface.gdshader` | Props, characters, garments, weapons, imported `.glb` |
| `vivid_tech.gdshader` | Reflective magenta/turquoise film on the alien-tech formations |
| `vivid_space.gdshader` | Sky and space, as one continuous climb between them |
| `vivid_atmosphere.gdshader` | The band of lit air seen from outside it |
| `vivid_water.gdshader` | The sea, bent onto the sea-level sphere |
| `vivid_clouds.gdshader` | The iridescent cloud deck, as a field on a shell |
| `vivid_material.tres` | Preset for `vivid_surface.gdshader` |

The materials that use them live with the thing they dress:
`game/planet/planet_surface.tres`, `game/planet/planet_atmosphere.tres`,
`game/planet/planet_water.tres`, `game/planet/planet_clouds.tres` and
`game/player/player_suit.tres`.

## The planet frame

Ten global shader parameters, declared in `project.godot` under
`[shader_globals]` and read by every shader here through `vivid_lib`:

| Parameter | Meaning |
| --- | --- |
| `planet_center`, `planet_radius` | Where the planet is and how big, in world metres |
| `sun_direction` | Where the sun's light travels, matching a `DirectionalLight3D`'s -Z |
| `region_axis` | Pole of the colour wheel; hue runs around it as longitude does |
| `region_turns` | Turns of the wheel per trip around the planet |
| `region_phase` | Rotates the whole wheel |
| `region_warp` | How far region boundaries wander off their meridians |
| `region_chroma` | 0 leaves the world its own colour, 1 is full spectrum |
| `frost_axis` | North, in world space |
| `frost_edge`, `frost_full` | Cosines of the polar cap's outer and inner edges |

**Only `Planet` writes them**, in `_publish_frame()`, and only the first three and
the last three — the region controls are authored in `project.godot` and left
alone at runtime. Everything else reads. That is what lets a prop standing on the
ground pick up the same region colour as the ground under it with no wiring
between them.

The frost three are the polar cap, and they exist so that the cap has exactly one
owner. `PlanetShape` decides where the arctic is, builds the ice into the height
field there and paints it; `Planet` publishes the same two cosines it used;
`vivid_frost(up)` gives every shader the identical 0-to-1 answer. Do not restate
the cap in a material — the values in `project.godot` are only what an editor
preview sees before a `Planet` has published its own.

The cap is **two surfaces and two colours**, told apart by height alone, which they
can be because `_freeze()` put the frozen sea at exactly `ICE_TOP` and left
everything else alone. `PlanetShape.ICE` is pale blue on the floe, because ice is
dense enough to swallow the warm end of the light and hand back the blue, and it
carries `SEA_ICE_WETNESS` so `vivid_terrain` gives it the smooth specular treatment
it gives water. `SNOW` stays white and dry over the land above it. Both being white
made the whole arctic one flat field with no coastline anywhere in it.

Two rules about the wheel are worth knowing before turning any of it:

- **`region_turns` must be a whole number.** The hue is `fract()` of an angle, so
  a fractional count meets itself on the far side of the planet as a hard seam
  instead of a gradient.
- **The wander is added to the angle, not to the finished hue.** Warping the hue
  directly breaks that same wrap. `vivid_region()` in the library is the one place
  this is decided; use it rather than rolling a second version.

`vivid_region()` returns two numbers: a hue coordinate that wraps, and an
intensity from a second, independent noise field. The intensity is why the wheel
reads as weather rather than as a paint chart — brightness does not simply track
hue.

## Where the colour reaches

Every shader here takes the region in three separate doses, and they are kept
apart on purpose because they fail differently:

| Dose | What it is | Failure mode |
| --- | --- | --- |
| `region_albedo` | The hue mixed into the surface's own colour | Fluorescent paint, if saturated again on top |
| `region_sheen` | A grazing-angle glow in `EMISSION` | A wash over the whole frame |
| `region_rim` | Godot's `RIM`, lit by the real lights | The same wash, in white |

The albedo dose is the honest one and carries most of the effect. The other two
are highlights and want to stay small — especially on terrain, where a landscape
running to the horizon is nearly all grazing angle. `vivid_terrain` ships with
`region_rim` at 0 and `sheen_falloff` at 8 for exactly that reason; a prop can
afford far more, because a prop has actual silhouettes.

The spectrum averages 0.5 per channel, so the tint is applied as
`albedo * region_color * 2.0`: the hue swings and the brightness stays put.

## Making flat art interesting

`vivid_surface.gdshader` is where the "flat textures should not be boring" problem
is answered, with three things stacked on whatever albedo arrives:

- **Texture relief.** The texture's own luminance is read as height across two
  extra taps, and the difference bends the normal along the UV axes. This is the
  single biggest win on painted art and costs almost nothing — it is what makes
  the mortar lines in a brick texture actually catch the sun.
- **Procedural detail.** Two scales of 3D noise: `detail_*` for grain, `macro_*`
  for the blotchy variation that stops a large panel being one wash. `bump_*`
  bends the normal by the gradient of the same field, which matters more than any
  amount of albedo noise because it makes light move as the camera does.
- **Roughness variation.** Highlights break up across a surface instead of sliding
  over it as one clean shape.

All of it is in **cycles per metre**, so the numbers do not carry between a
1.45 m character and a hillside. Compare `player_suit.tres` (`detail_scale` 14,
`macro_scale` 1.6) against `planet_surface.tres` (0.35 and 0.014).

**And all of it is off on the character.** `player_suit.tres` zeroes
`macro_amount`, `detail_amount`, `bump_strength`, `roughness_variation` and
`texture_relief`, because manufactured relief is a fix for a large still panel
and a body is neither. At character scale the macro field is blotches the size of
a torso and the bump is centimetre lumps crawling over a face; the result reads
as unfired clay, which is worse than the plastic it was meant to avoid. A
character is small, close and nearly always moving, and that is what gives it
shape. The two noise fields are skipped rather than multiplied by zero, so off
also means free — worth remembering if a new surface turns them back on.

**Detail has to fade with distance.** Procedural noise has no mip chain, so once a
bump is smaller than a pixel it aliases into shimmer. Every detail field here is
gated by `detail_near`/`detail_far`, and the terrain's macro field needs a second
gate of its own (`macro_near`/`macro_far`): from orbit its 70 m blotches fall under
a pixel and boil into speckle.

### Alien technology

`vivid_tech.gdshader` is the narrow exception to the general-purpose surface:
`TechFormationSites` needs a fixed magenta/turquoise identity rather than the
planet's regional wheel. Its reflection is still Godot's Schlick-GGX response —
low roughness, high dielectric specular and **zero metallic** — while a small
view-angle term in `EMISSION` supplies the thin-film colour shift at the edges.
That term never replaces the light, so the 562 real panels in
`tech_fragment.glb` keep their own highlights and shadows.

There is deliberately **no painted grid** over that geometry. Continuous
world-space noise only breaks up the highlight, and the fine normal variation
fades through `detail_near` / `detail_far`; every visible square and bar remains
one of the mesh's real protrusions. That distinction matters now that one
instance can be stretched from a room-sized buried block into a 300 m slab:
a shader grid would sit over both at the same unrelated scale.

## Sky and space

`vivid_space.gdshader` is one sky shader, not two with a swap at a boundary. It
reads the camera's altitude out of the planet frame and crossfades: daytime air at
sea level, thinning blue and a darkening zenith on the way up, then stars, a
nebula on the same colour wheel the ground uses, and the sun burning as a bare
disc. Coming back down runs it in reverse. `atmosphere_height` is the altitude
that crossfade is measured against.

**There are two ways out of the daytime sky and whichever has gone further wins.**
Climbing thins the air away; the planet turning puts it out. `dusk_low` and
`dusk_high` are the sine of the sun's elevation where the air starts going dark
and where it is fully dark, `night_air` is what it keeps after that, and the same
fade brings the stars in — so a player standing on a beach at midnight gets the
open-space sky at sea level. Only altitude used to do this, which meant the unlit
half of the planet was black ground under a blue noon and the stars could not be
seen from any surface anywhere.

Three constraints on it:

- **`TIME` is never read.** A sky shader that reads it forces the radiance cubemap
  to be rebuilt every frame, and this sky is the scene's ambient light source.
- **The cubemap pass skips the expensive half.** Stars and nebula are five octaves
  of noise per texel and worth no measurable ambient light, so `AT_CUBEMAP_PASS`
  draws the atmosphere and `space_color` only. It does take the night fade, which
  is what makes the night side dark rather than merely blue.
- **`LIGHT0_DIRECTION` is not `sun_direction` under another name, and must not be
  negated to "match" it.** The frame's `sun_direction` is where the light travels,
  matching a `DirectionalLight3D`'s -Z; the engine hands a *sky* shader the
  opposite vector, the one pointing at the light, so that
  `dot(EYEDIR, LIGHT0_DIRECTION)` peaks on the disc — Godot's own
  `ProceduralSkyMaterial` uses it exactly that way. Negating it draws the sun, its
  glow and the whole warm forward-scattering half of the sky over the hemisphere
  facing away from the light, which reads as a planet lit on the wrong side.

**Star count is bought with `star_fill`, not with `star_densities`.** A cell at
density 500 subtends a fifth of a pixel, so a layer up there adds hundreds of
thousands of stars nobody can see; density sets how *big* a star is and the fill
share sets how many there are. `star_beacons` is the small share of the coarsest
cells holding a bright one, and it matters more than the count — a field of evenly
matched dots reads as sensor noise however many of them there are. `star_haze` is
the milky wash down the galactic band, drawn as a noise field rather than as a
fourth lattice, because below a pixel a point is not a disc but a lift in the
background and lattice points that small alias into a speckle that crawls as the
camera turns.

`vivid_atmosphere.gdshader` is the other half: an additive shell raised by `Planet`
at `atmosphere_height` above the surface, which draws the lit rim of air seen from
outside. Its `shell_height` **must match** the sky's `atmosphere_height`. Below
that line the sky shader draws the haze and above it the shell does, so a mismatch
shows as a band of altitude with either no air at all or twice as much.

## The sea

`vivid_water.gdshader` is the sea, and almost all of it is the vertex stage. The
mesh handed to it is a flat disc lying in the tangent plane under the viewer, and
`vertex()` normalises every vertex out of the planet's centre and puts it back at
`planet_radius`. So the ocean is not a mesh of the planet — it is a patch that
follows whoever is looking at it and lands on the exact radius the height field
calls zero. No seam, no LOD, nothing to keep in step with the terrain's chunks.
`PlanetWater` sizes the disc to the horizon and does nothing else.

Three render modes are doing real work:

- **`world_vertex_coords`**, without which the projection would have to be
  undone through the model matrix on the way back out.
- **`cull_disabled`**, because a swimmer looks up at the underside of it.
- **`depth_draw_always`**, and this one is not optional. A transparent surface
  that writes no depth does not hide itself, so the far half of the disc is drawn
  over the near half and the sea extends past its own horizon as a flat band with
  the disc's rim notched along the top. It costs nothing against the terrain,
  which is opaque and drawn before any of this.

The rest is a fresnel. `water_alpha` is how much of the sea bed shows through
looking straight down; both the colour and the opacity climb toward 1 at grazing
angles, which is most of what gives a nearly flat sheet a shape. `glint_sharpness`
and `glint_strength` are the sun's reflection, read off `sun_direction` directly
rather than through a light, and they are what the ocean reads as from orbit.

### Swell

`swell_height` is real displacement, and it is an **error budget** before it is a
taste setting. `PlanetWater.depth_at` measures the sea as an exact radius, so a
crest stands `swell_height` above where swimming, buoyancy and the splash check
all believe the surface is. Half a metre disappears inside the bob buoyancy
already has on a 1.45 m body; a couple of metres would let you swim through air,
and anything wanting that has to move the physics first. `ripple_*` is the fine
detail on top and still bends the normal only — at that scale a displacement
would be smaller than the disc's own triangles anywhere but under the eye.

Three planar waves crossing, from `vivid_swell()`, planar in 3D and then cut by
the sphere. On a ball this size that gives crests near enough to great circles,
and it costs **no tangent frame** — which is the one thing that cannot be built
over a whole sphere without a seam. `vivid_wave()` gives back the gradient as
well as the height, so the normal is analytic and per-pixel; interpolating the
vertex normal instead hands the outer rings, where one triangle is longer than a
wavelength, the average slope of a whole wave, which is nothing.

The fresnel is taken against that **shaped** normal and not against the radial
up, and that is what makes the swell visible at all. Lit only through its
specular a wave shows up when the sun happens to be behind it and is a flat plane
the rest of the day. Off the tilt, every face toward the eye goes dark and every
face away from it pale, and the sea has a shape from any angle in any light — it
was worth 5% of the frame before the change and 12% after.

### Webbed light

The caustic net — the thing on the bottom of a swimming pool — is drawn from
three places and is **one field**: `vivid_caustic()` in the library, sampled at
the point's own sea-level projection. So the web on the bed is the same web
glittering on the surface five metres above it and the same one the shafts
between them are lit by, without any of the three shaders knowing the others
exist. `caustic_scale` therefore has a twin in `planet_surface.tres` and they
have to be kept equal.

| Where | Shader | Uniform |
| --- | --- | --- |
| On the bed | `vivid_terrain` | `caustic_strength`, `caustic_depth` |
| Hanging in the water | `vivid_terrain` | `shaft_strength`, `shaft_reach` |
| Twinkling on top | `vivid_water` | `twinkle` |
| On the underside, for a swimmer | `vivid_water` | `underlight` |
| In the surf | `vivid_water` | `surf_caustic` |

The filaments come free: the half-contour of a noise field is already a closed
net of cells, so the only work is sharpening it. **Time is the third axis, not a
drift** — a caustic net does not travel across the bed, it boils in place as the
surface above it bends, and walking through the noise instead of across it is
exactly that for the same eight lookups.

`vivid_sea_shafts()` is not a scattering integral. It samples the same net at the
place each step's own sun ray crossed the surface and adds six of them up, which
is the actual reason shafts exist — the column of water under a bright filament
is lit the whole way down. It is weighted by the murk below, because a shaft is
made of the light scattered out of the water in its path and there is exactly as
much of that as there is water.

### The water column

Everything the sea does to the ground under it comes off **one length**:
`vivid_sea_path()`, the metres of the eye-to-fragment segment that lie below sea
level. `murk_visibility` is how far light survives in that length, and the two
together are what give the sea a body — without them the bed is as crisp at six
hundred metres as at six.

Asking for a length rather than for "is the camera submerged" is the point of it.
A bed two metres down and the same bed sixty metres down are not the same sight,
and a boolean cannot tell them apart. It used to be a boolean, with the tint on
deep water lerped from the painted depth in the vertex alpha instead, and the
result was that **looking down into water from outside it showed ground in a
slightly odd colour**: the alpha is a map of how deep the water is under a
*vertex*, not of how much of it a *pixel* is looking through, so a bay was tinted
the same from directly overhead as from a kilometre away along the surface, and
the only thing marking either as wet was a sheen.

The same length is read two ways, and never both at once:

| Where the eye is | What the column does | How |
| --- | --- | --- |
| Outside the water | The bed loses its own colour and gains the sea's | `albedo` mixed toward `water_deep_tint` |
| Inside the water | The bed is taken away and a lit wash put in its place | albedo down, `murk_color` up in `EMISSION` |

Both `vivid_terrain` and `vivid_water` carry `murk_color` and `murk_visibility`
and they must agree, or the underwater horizon is drawn at two different distances
where the bed meets the sea.

Altitude is taken to run linearly along the segment, which is exact enough over
any distance a sea is deep and errs toward too little water rather than too much.
A ray that leaves the water and comes back — over a sandbar — is counted as though
it stayed out.

**Shafts stay a thing seen from inside**, unlike the rest of this. You see a shaft
because you are in the medium doing the scattering and looking along it; from above
there is nothing to look along, and marching them anyway put a bright net over a
five-hundred-metre trench that read as a reef in water a few feet deep — and
charged six noise samples for every ocean pixel on the planet to do it. From above,
the honest view is the blue column plus the net where the light has a bed to bounce
off, and both of those are already drawn.

### Under the surface

The inside-the-water half of the column is applied as an **emissive fog** — albedo
down, `murk_color` up — rather than as a tint on the albedo, because a tint would be
shaded: ground in shadow would look through clear water and ground in the sun
through murk. The outside-the-water half is the opposite on purpose: it *is* a tint,
because sunlight scattering back out of a sea is lit, and a sea that emitted its own
colour would glow at midnight.

Two things had to be taken away with the albedo, and each one on its own left the
bottom as bright as an unfogged one:

- **`SPECULAR` and `ROUGHNESS`.** Albedo is not the whole of what a surface
  returns. A bed at 0.9 specular and 0.06 roughness goes on reflecting the sky
  through any amount of water put in front of it.
- **The wet-ground sheen itself.** Wet ground is written smooth and specular so
  that an ocean seen from *above* has a sheen at ranges the sea's own ripples
  have faded out at. From inside the water that reading is simply wrong — the
  mirror is the surface overhead, which is drawn separately — and it burnt the
  sun into the sand. `vivid_terrain` drops the whole treatment when the camera is
  submerged.

### The surf

White water at the shore is the one thing the sea draws that depends on the
land, and it gets there without a coastline ever being computed. The opaque pass
has already drawn the sea bed, so the depth buffer holds it; reconstruct that
fragment's world position, take its radius from the planet's centre, and
subtract it from `planet_radius`. That is the depth of the water column, in
metres, and every white thing here is a function of it. A band of constant depth
*is* a line parallel to the shore, so the foam follows every bay, headland and
river mouth exactly, and keeps doing so when the terrain seed changes.

Take the depth as a **difference of radii**, never as a length along the view
ray. The slant path through shallow water is long, so the ray-length version
reads every grazing pixel as shallow and lays a band of foam along the whole
horizon.

Two things go on top of it. `wash_depth` is the band that stays white whatever
the waves are doing — the swash on the sand. `break_depth`, `wave_spacing` and
`crest_width` are the breakers: a pulse of white per wave, marching shoreward as
`TIME` advances because the phase is `depth / spacing + TIME * surf_speed`.
Spacing is in metres of **depth**, not of ground, which crowds the breakers
together on a steep shore and draws them out across a flat one for free.

Two more tie the surf to the rest of the sea. `surf_swell` lets a crest riding
the face of the swell break harder than one in the trough, so the two are not
marching up the beach to separate schedules. `surf_caustic` puts the net into the
crests and deliberately **not** into the wash: bubbles are lit by the same
focused light that draws the net on the sand under them, which is why real surf
glitters, but the band along the waterline has to stay solid white or the
shoreline dissolves.

**The surf fades out in two stages, and it has to.** `crest_near` / `crest_far`
put the breakers away at a few hundred metres; `surf_near` / `surf_far` keep the
wash going to a couple of kilometres and then end it. One fade for both, which is
what this had, sets an impossible brief: the crests are spaced by `wave_spacing`
— under a metre of depth, a few metres of ground on a shelf this gentle, the
finest pattern anywhere in this project — and they are laid *across* the shore,
which is the direction most foreshortened when a coast is looked down on from
above. Past a few hundred metres there is well under a pixel per wave, and what
gets drawn is not surf but the aliasing of surf: a row of white dashes hugging
every coastline, which from a few kilometres up is the most visible thing on the
planet and reads as the ocean being striped. Set to 1200–5000 m it was doing
exactly that from anywhere in low orbit.

The wash outlasts the crests because it is not a pattern — it is the band of
white at the waterline, and a coast a kilometre below does have a white line on
it. It still has to end well short of orbit: the band is under a metre of depth,
and the bed behind it is read `filter_nearest` from a depth buffer whose chunk
triangles are hundreds of metres wide out there.

Three numbers here were each wrong once, in a way worth not repeating:

- **`break_depth` is small — 3.5 m against a 22 m shelf.** These coasts shelve
  very gently, so a depth that sounds modest in metres is enormous on the ground.
  At 9 m the entire shallows went white instead of the shore.
- **A crest has to saturate, not peak.** The first version ramped between crests
  and averaged a third; a third of white blended over dark water is not surf, it
  is grey. The pulse is overdriven and clamped so its middle is *actually* white
  and only its edges are a blend.
- **Foam is lit by the sky, not by the sun.** Tied to the water's own `day` it
  capped at whatever a low sun gave, measured at 0.53 on the test coast — grey
  again. It gets the same terminator opened up at both ends, and still falls to
  `night_light` on the dark side so an unlit shore is not a beacon.

`region_tint` is **0**, and the reason is worth keeping. It is how much of the
colour wheel the sea takes, and unlike the ripples it does not fade with
distance — so it is the only thing varying across the ocean from orbit, and what
it varies in is bands, because bands are the shape of the wheel. At the 0.35 it
used to be, half a planet of water was striped. Land can carry the wheel because
it has terrain to break the boundaries up; a flat sheet cannot.

## The clouds

`vivid_clouds.gdshader` is the weather, and there is no cloud object anywhere in
the project. `Planet._raise_clouds()` puts up one sphere and the shader does the
rest: every cloud is a function of position relative to the planet's centre, so
the deck is **located on the globe**, is endless, costs nothing to store and
costs nothing to replicate. Two players in different hemispheres see different
weather without a byte crossing the wire.

Four ideas carry it.

**The deck is a slab and every pixel walks through it.** The sphere that gets
submitted is at `cloud_height + cloud_thickness / 2` and it is not the clouds; it
is the volume's silhouette, and all it does is get a fragment onto the screen
wherever the deck could be seen. What is drawn is a field of density filling the
`cloud_thickness` metres below it, and the fragment intersects its own view ray
with that slab and marches the crossing, gathering light and losing transmittance
as it goes.

This is the whole difference between gas and a sticker, and it was the shader's
first design. One sample per pixel — which is all a shell can take — has no
thickness in it anywhere: a cloud looks the same edge-on as face-on, has no
underside, and passes through the camera in one frame as a wall with no inside.
Marching gives all three for nothing extra in concept. Thickness is how much
field the ray crossed, the underside is where the ray came in from below, and
flying into the deck simply starts the march at the eye, so cloud builds up
around the camera the way fog does. `vertical_scale` is what makes the field
three-dimensional rather than extruded — at zero every cloud is a column with the
same cross-section at its base as at its top, and a deck of those reads as
curtains.

It is not free. Measured with `dev/_perf_test.tscn -- --noclouds` against the
same run without it, the deck costs 0.04 ms from orbit, 0.2 ms at treetop and
0.36 ms standing on the ground, but **2.3 ms at 1800 m**, which is the worst case
and is where the player flies. Every pixel up there is a ray skimming along the
slab rather than dropping through it. See the three step dials below before
reaching for anything else.

**Condensing and evaporating are one dial.** The density field holds still while
the level it is cut at breathes, so raising the cut shrinks a cloud in from its
edges until it is gone and lowering it grows the cloud back out of its own core.
A second, much slower field (`breathe_scale`, `breathe_speed`) decides which
part of the sky is doing which, so the deck never clears all at once. `wind`
slides the whole field, slowly — anything visibly moving in a sky is a gale.

**The colour is a thin film at three scales**, each taking over as the one below
it stops being resolvable:

| Term | Scale | Where it is the hue |
| --- | --- | --- |
| `iris_bands` | contour lines of the density | close up |
| `iris_swirl` | the cloud's own body | a few kilometres out |
| `vivid_region()` | the planet's colour wheel | from orbit |

The bands cannot share the detail fade, and this is the one trap in the file:
they multiply the density's own wobble by `iris_bands`, so they alias about that
many times sooner than the field they are drawn on. Left on from orbit they are
a sub-pixel rainbow, which resolves as grey speckle over the whole planet. Hence
`band_near` / `band_far`, which are several times tighter than `detail_near` /
`detail_far`.

**A band is faded out of the colour and never out of the phase.** This one cost
an afternoon and looked worse than anything else the shader has ever done.
Multiplying the phase by a fade does not remove what the phase was drawing — the
hue is read from it, so every pixel on the way from full strength to none passes
through as many turns of the spectrum as the phase was worth. Because the fades
here depend on how obliquely the deck is being seen, those turns land along lines
of constant view angle, and the sky fills with concentric rainbow rings centred
on the zenith, worst exactly where the fade was meant to be removing them. Take
the spectrum twice, with and without the band term, and `mix` the two colours.

**Detail fades on three things, and the last two only exist because this is a
volume.** The first is the pixel footprint, `range / facing²` — how much deck one
pixel is being asked to average. Distance alone misses the horizon seen from
under the deck, which is only a few kilometres away but crossed at seventy-five
degrees; obliquity alone misses the limb from orbit. Note that from *inside* a
shell the incidence angle can never reach ninety degrees — it bottoms out at
`acos(r / R)` — so a fade written against the angle alone never fires at all.

The second is the march's own step. Nothing finer than a step is being resolved,
and this is measured against the crest field's feature size rather than tuned, so
it follows `cloud_scale` and `detail_scale` without being told.

The third applies to the **colour only** and is much harder: `smoothstep` on
`facing`. Everything downstream of the march is sampled where the ray found its
cloud, and that point runs along the deck as the view tips over, so at a grazing
angle one pixel of screen slides it tens of metres and the fine fields sweep
through several periods. The density detail is deliberately left out of it — it
lives inside the march and decides what shape a cloud is, and a shape that fades
with the angle it is seen from is a cloud that changes as the player turns their
head.

`fwidth` is the obvious tool for all three and cannot be used anywhere in this
file. Derivatives are undefined in non-uniform control flow, and every value here
comes out of a loop with a data-dependent break, downstream of three discards.
What it returns is whatever the neighbouring pixel happened to be doing, and the
fade it drives is silently no fade at all — it compiles, it runs, and it does
nothing.

Five smaller things that each fix something specific:

- **The step is sized off the field, never off the deck.** `cloud_scale` turns
  are wrapped around a nine kilometre sphere and `vertical_scale` turns are
  packed into seven hundred metres of slab, so the field's finest octave is a
  couple of hundred metres wide sideways and under a hundred tall. A ray dropping
  straight through has to be sampled several times more finely than one skimming
  along, and the two rates add along the direction of travel. Sizing both off the
  deck's depth spends the same on each, which means spending the whole budget on
  the skimming ray — and that is every pixel on screen when flying over the tops.
  It was four and a half milliseconds before this and is 2.3 after.
  `step_detail` is how much of that finest octave one step may cross; under about
  half it stops integrating and starts point-sampling, which reads as a boiling
  speckle because neighbouring pixels land in different parts of the field.
- **The step grows as the ray goes**, by `step_growth` each time. A fixed budget
  of equal steps either stops a few kilometres in, leaving the far half of a
  grazing crossing undrawn, or is coarse enough to reach and wastes that
  coarseness on the near half where it shows.
- **There is no jitter, and that is deliberate.** The usual dither on the first
  sample wants a temporal filter to resolve it, and there is none here. At the
  step sizes this deck reaches it stops being a dither and becomes the noise: the
  first version of this marched two steps through the deck from orbit with a
  full-step jitter, and the planet came back as a boiling rainbow foam.

- **Haze.** Seen from below, the deck compresses toward the horizon until a whole
  weather system is a few pixels tall, and with nothing in front of that band it
  is busier down there than anything overhead. `haze_range` fixes it the way
  every real sky does; `haze_ceiling` scales it off as the camera leaves the air,
  so the view from orbit keeps its contrast.
- **One extra sample toward the sun, per step.** `shadow_step` / `shadow_gain`
  read the body a hundred and eighty metres along the light and darken the step
  by what they find. This is what makes a marched cloud read as an object rather
  than as coloured smoke: the near face of a tower is lit and the far face is
  not, and the two are the same field a moment apart. One sample and not a second
  march — that would be four times the cost for a softer version of the answer —
  and it skips the fine octaves, because what shadows a cloud is its mass and the
  filigree on its edge shadows nothing. `shadow_floor` is not zero, because a
  cloud lit only from outside goes to a black core and a real one is glowing grey
  all the way through.
- **The cut is a bound, not a guess.** A step leaves after three octaves when the
  fine ones could not have made it cloud whichever way they landed, because they
  are centred on a half and scaled by `detail_relief`. Most steps of most rays
  leave at that line and it is what makes the march affordable at all.
- **`coverage` is a share of the volume, not of the sky.** It meant the second
  while the deck was a surface and it means the first now, and the two are a long
  way apart: a ray leaving the ground at a shallow angle crosses kilometres of
  slab and passes through several cloud cells, so the sky ends up perhaps twice
  as covered as the volume near the zenith and completely covered at the horizon.
  Anything much above a third closes the sky over and the deck is a lid again.
- **The floor is sharp and the roof is soft**, `deck_floor_soft` well under
  `deck_roof_soft`. A cumulus base is where the air hits the dew point and it is
  at the same altitude for miles; its top billows. Equal values give a lens,
  which reads as a lozenge of fog. `deck_taper` is what pinches a cloud in near
  both, so a tower narrows as it rises instead of being cut off flat.

### The arctic deck and the wall

Over the polar cap the deck is thicker, lower and denser, and around the rim of
the cap it becomes a wall standing on the ground. Both are `vivid_frost` acting
on the same three kinds of "more cloud", and each kind is needed because the
other two cannot stand in for it: `*_deepen` is extra slab depth, all of it added
below the roof because the roof is the shell the deck is drawn on and cannot
move; `*_coverage` lowers the level the density field is sliced at, which is what
actually fills the sky in; `*_density` thickens what is left so a crossing goes
opaque sooner. Coverage alone is a wide thin overcast, density alone is the same
few clouds turned to concrete.

The wall is the same three keyed to `deck_rim`, the parabola of the cap against
itself, which is 1 across the cap's edge and 0 on both sides of it. Taken that
way rather than from a second pair of cosines so that `frost_area` and
`frost_blend` carry the wall with them and the arctic keeps one owner. It is the
one place the deck's floor is deliberately put under the ground — fog rather than
weather, which is the point, and is why it is confined to a band about a
kilometre wide. `wall_deepen` has to be enough to put that floor below the
deepest sea bed or the wall ends in mid-air over the coast; past that the extra
is spent where the march never reaches.

What is *not* bought is the opacity. The band is over a kilometre thick and a ray
going in at eye level crosses all of it, which at ordinary cloud density is
twenty times the extinction it takes to go solid, so the two dials only have to
make sure there is cloud the whole way across. Both of the direct ways to force
it end in the same picture — coverage past where the field bottoms out makes
every point in the slab cloud, so the wall's face becomes the shell, which is a
sphere; density does it more quietly by turning the wisps on the approach opaque,
so the ray stops in a smooth fog ramp — and a smooth surface lit through the
iridescence comes back as concentric rainbow rings centred on the eye.

Which is the rule the wall exists to state:

> **Latitude may enter the gate and the extinction. It may not enter the field
> coordinate.**

The gate and the extinction decide where there is cloud and how solid it is, and
a smooth latitude ramp in either is just a wall fading in. The coordinate decides
what the cloud *looks like*, and the whole field is one radial number — its size
sets how fine the cells are across the sphere, its change with altitude sets how
layered the deck is. Anything latitude-dependent in it draws a contour of the
noise along every line of latitude in the band, and from beside at eye level
those close into ellipses centred on the viewer, because the planet curves away
and the far ones crowd together. The arctic comes back as ripples on a pond. The
radial term is therefore metres below the **roof** over the slab's *unswollen*
depth: dividing by the swollen depth, which is the obvious reading of "how far up
the slab is this", swept four turns of noise across the band on its own. Two
later attempts to break the rings up by adding *more* latitude terms — finer
cells in the ring, less layering in the ring — both made them finer and worse
before the shared cause showed. `arctic_wall` in the harness below is the shot
that says which.

The deck is `cull_disabled` so a fragment is generated from inside it as well as
outside, and **`depth_test_disabled`** with the march clipped against
`hint_depth_texture` instead. That pair has to be understood together: a volume's
depth is not its shell's, and from inside the shell every fragment carries the
depth of the far side of the sphere, so one test against that hides the entire
sky behind the first hill. The march is also clipped at the sea-level sphere,
without which a ray carries on through the planet and draws the weather over the
antipodes on top of the ground under the camera. Where Godot's own transparency
sort cannot help — all three shells share the planet's centre, while the sea's
origin is the patch of water under the viewer and so sorts nearest of the three
from orbit — `render_priority` states the order outright: sea 0, clouds 1, air 2.

`dev/_cloud_probe.tscn` photographs the deck from the five places it has to work
and comes back in fifteen seconds. A shell shader can be made to look right at
any one of them and wrong at the other four, and the failures differ in kind:
speckle from orbit, stair-stepping from just above, ripples under the bases.

## Environment settings

The shaders assume the environment they were tuned under, and three settings are
part of the look rather than incidental to it:

- **The sky is the ambient and reflection source.** Sun plus sky bounce is most of
  a stop brighter than a lone directional light, which is why `brightness` on the
  terrain sits at 0.6 and the sun at 1.05 rather than at 1.25.
- **ACES tonemapping with `tonemap_white` at 2.0**, so the sun's disc and the
  water's highlight have somewhere to go instead of clipping to flat white.
- **Glow with `glow_hdr_threshold` just under 1.0.** On the mobile renderer the
  colour buffer tops out near 2.0, so a threshold at 1.0 or above means nothing
  ever blooms.

`game/world.tscn` and `dev/_planet_test.gd` both set these; keep them in step.

## Verifying a change

```powershell
godot --path . dev/_planet_test.tscn -- --tour
```

Ten shots from 32 km down to standing on the ground, written to `dev/captures/`,
with chunk, triangle, draw and LOD numbers printed beside each. It is the only
honest way to judge a change here, because most of these decisions only go wrong
at one particular range: speckle shows from orbit, tiling shows at a grazing angle
along the ground, and the atmosphere rim only exists between the two.

For the sea specifically, `dev/_water_test.tscn` ends with three vantages — over
the shallows, standing on the bed nine metres under, and at eye level in open
water — and each is paired with the same frame taken with one uniform switched
off, so the caustics, the shafts and the swell each come back as a share of the
frame rather than as an opinion. Note that it places the **body**, whose origin is
its feet: the first run of the underwater shot asked for 1.6 m under and
photographed the sea from a metre in the air.

For the night side, `--night` instead of `--tour`. It pins the sun over the
equator and walks from noon through dusk to midnight under a light that does not
move, then photographs the same planet from both sides of it. The tour deliberately
swings the sun to face whatever it is shooting, which is the right thing for a
screenshot set and is exactly what hid a flipped sun for as long as it did: with
the light following the camera, the lit side and the side with the sun in its sky
are never seen apart.

Three numbers come out beside each frame, and each has a shape to expect:

- **brightest N deg off the sun.** Zero on `night_sun`, which is aimed at it. This
  is the sign check, and nothing else in the set means anything until it passes.
- **mean.** `night_day_orbit` should be most of an order brighter than
  `night_orbit`. They are the same planet from opposite sides.
- **stars, as a share of the sky.** Detected as points brighter than the sky a few
  pixels away, not by a threshold — a threshold calls all of a blue noon sky a star
  field. Around zero by day, a per cent or so at midnight.

Two things will masquerade as a sky that never got dark, so the mode guards
against both: standing in the sea, since the camera ends up metres under water and
the frame comes back navy with the stars dimmed out of it, and the pale HUD plate,
which is brighter than anything a night sky contains. `--noclouds` separates the
third, a deck thin enough to be hard to tell from haze.

For the arctic, `dev/_arctic_test.tscn`. Two of its shots are shader work:
`arctic_orbit`, paired with the same frame with the deck hidden, because the
polar cloud is doing what it was asked to and one picture cannot say whether the
ground under it came out white or was never built; and `arctic_wall`, taken from
three kilometres outside the rim and paired the same way, which reports the share
of the view the wall took. That number is the claim — a wall you can see through
moves a fraction of what a solid one does — and the picture beside it is what
catches rings, because rings measure as solid. The shot deliberately picks the
sunlit longitude of the rim rather than the nearest patch of land: the rim is a
circle of latitude, so where on it to stand is a choice of longitude and nothing
else, and taken any other way it lands on the night side about half the time,
where a wall of iridescent cloud photographs as a dark wall.

One trap that is not in any shader. Every harness here assigns `Planet.sun`
itself, so every harness publishes a correct `sun_direction` — and `world.tscn`
did not, for long enough that the game ran on the static fallback in
`project.godot` while all six of these reported healthy. Anything that reads
`sun_direction` should be checked at least once in the real scene.

## The pencil shader

`shaders/pencil/` is still in the repo and still works. Its UI half —
`pencil_ui.gdshader` and `ui/themes/pencil_surface.gd` — is **still in use** and
draws every menu, HUD plate and pause card. Only the 3D half was swapped out;
nothing in a scene points at `pencil_surface.gdshader` or `outline_passes.tres`
any more. Restoring the drawn look means repointing the materials back and
dropping the vivid environment settings above, since that shader disables ambient
light and supplies its own fill.
