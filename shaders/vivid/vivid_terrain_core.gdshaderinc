// Shared body of the planet ground shader. The two wrappers pick a cull mode:
// the sphere keeps back-face cull, district ramps disable it so a steep skirt
// is still there from the downhill side.
#include "res://shaders/vivid/vivid_lib.gdshaderinc"

group_uniforms Ground;
// Pushed past 1 on purpose. The biome colours are chosen to stay legible as a
// map; this is what makes them a place rather than a legend.
uniform float saturation : hint_range(0.0, 3.0) = 1.5;
// Held well below 1 because the sky is also the ambient light: sun plus sky
// bounce puts far more light on the ground here than the single directional
// light the old look was tuned against, and an albedo near 1 washes out before
// the tonemapper gets a say.
uniform float brightness : hint_range(0.0, 2.0) = 0.6;
uniform float ground_roughness : hint_range(0.0, 1.0) = 0.9;
// Ground reflects the sky as well as being lit by it, and at this roughness that
// reflection is a broad white sheen over the whole landscape rather than a
// highlight. Dirt is not shiny; the water below has its own value for this.
uniform float ground_specular : hint_range(0.0, 1.0) = 0.16;
// District ramps only. Chunk interpolation can sit above a single height
// sample; this push along planet-up keeps the sheet on top of the sphere
// without moving the collider. The planet wrappers leave it at zero.
uniform float ground_lift = 0.0;
group_uniforms;

group_uniforms Volcano;
// The height field centres this biome on the antipode of frost_axis. Keeping
// the radius in metres lets this mask use the same authored dimension without
// adding another global direction or restating which way south is.
uniform bool volcano_enabled = true;
uniform float volcano_radius = 1450.0;
uniform float volcano_cone_radius = 980.0;
uniform vec3 volcano_basalt : source_color = vec3(0.055, 0.045, 0.05);
uniform vec3 volcano_ash : source_color = vec3(0.18, 0.135, 0.11);
uniform vec3 volcano_ember : source_color = vec3(1.0, 0.12, 0.008);
uniform float volcano_crack_scale = 0.032;
uniform float volcano_crack_energy : hint_range(0.0, 8.0) = 1.7;
group_uniforms;

group_uniforms Detail;
// Cycles per metre. 0.35 puts one patch of variation every ~3 m, which is the
// scale a walking player reads as texture rather than as stains.
uniform float detail_scale = 0.35;
uniform float detail_amount : hint_range(0.0, 1.0) = 0.3;
// Tens of metres, so a hillside is not one flat wash of the same green.
uniform float macro_scale = 0.014;
uniform float macro_amount : hint_range(0.0, 1.0) = 0.4;
uniform float bump_scale = 0.9;
uniform float bump_strength : hint_range(0.0, 1.0) = 0.35;
// Detail costs three noise fields per pixel and aliases into shimmer once one
// bump is smaller than a pixel, so it is faded out with distance instead.
// Procedural noise has no mip chain to fall back on, which is why the fade has
// to be explicit and why the macro field needs one of its own: from orbit its
// 70 m blotches are smaller than a pixel and boil into speckle.
uniform float detail_near = 40.0;
uniform float detail_far = 260.0;
uniform float macro_near = 1500.0;
uniform float macro_far = 9000.0;
group_uniforms;

group_uniforms Ground_Patterns;
// A second, much broader layer than the photographed ground material. It keeps
// the terrain's authored biome colour and lays deliberate markings into it:
// stripes, dots, dark islands, rings and alien contour work. The pattern family
// and scale drift in coherent world-space fields, so a flat plain can change
// character without becoming a tiled decal sheet.
uniform float pattern_amount : hint_range(0.0, 1.0) = 0.68;
uniform float pattern_color : hint_range(0.0, 1.0) = 0.52;
// The coherent size field spans this range exponentially. One end gives
// metre-scale freckles and the other gives marks readable across a valley.
uniform float pattern_smallest : hint_range(0.5, 8.0) = 1.0;
uniform float pattern_largest : hint_range(40.0, 300.0) = 160.0;
// Pattern families occupy regions hundreds of metres across; size drifts more
// slowly so one motif does not breathe in and out every few steps.
uniform float pattern_region_scale = 0.0017;
uniform float pattern_size_scale = 0.00072;
// Patterns belong on the broad plains the user can read as canvases. Cliffs
// retain their photographed stone and slope shading.
uniform float pattern_flat_from : hint_range(0.0, 0.3) = 0.025;
uniform float pattern_flat_to : hint_range(0.02, 0.5) = 0.18;
// Large motifs can survive a high flight; after this, even they settle back to
// the base map so orbit does not turn into sub-pixel confetti.
uniform float pattern_near = 5000.0;
uniform float pattern_far = 12000.0;
group_uniforms;

group_uniforms Night_Ground_Glow;
// A low, terrain-level luminance. Three colours are blended in broad world-space
// fields, and NightGroundGlow replaces this palette each planetary day.
uniform vec3 night_ground_glow_color_a : source_color = vec3(0.12, 0.78, 0.36);
uniform vec3 night_ground_glow_color_b : source_color = vec3(0.18, 0.56, 1.0);
uniform vec3 night_ground_glow_color_c : source_color = vec3(0.78, 0.24, 1.0);
uniform float night_ground_glow_energy : hint_range(0.0, 1.0) = 0.16;
// One noise cell is about 260 m at this scale. Domain warping joins neighbouring
// cells into larger lobes, so these read as regions of land rather than spots.
uniform float night_ground_glow_scale : hint_range(0.0005, 0.02) = 0.0038;
uniform float night_ground_glow_threshold : hint_range(0.0, 1.0) = 0.53;
// A broad threshold band is the soft shoreline of each patch. It is intentionally
// much wider than an anti-aliasing fringe: the glow fades over metres of terrain.
uniform float night_ground_glow_softness : hint_range(0.01, 0.35) = 0.16;
// The field orbits through noise space instead of translating in one direction.
// That makes lobes stretch, split and rejoin like a lava lamp rather than making
// the planet look as though a texture is sliding over it.
uniform float night_ground_glow_speed : hint_range(0.0, 0.1) = 0.018;
uniform float night_ground_glow_flow : hint_range(0.0, 2.0) = 1.15;
uniform float night_ground_glow_palette_shift = 0.0;
// Published by NightGroundGlow so the shader field and its pooled real lights
// sample the same instant and both stop when single-player simulation pauses.
uniform float night_ground_glow_time = 0.0;
// The broad field survives ordinary flight, then leaves before its lobes become
// sub-pixel marks from orbit.
uniform float night_ground_glow_near = 3500.0;
uniform float night_ground_glow_far = 11000.0;
group_uniforms;

group_uniforms Ground_Texture;
// Four ground materials — grass, sand, stone, ice — as two texture arrays, in
// the layer order `build_ground_textures.py` stacks them in. The constants below
// are that order written down, and the two files have to agree with it.
//
// Photographs, but not colour. The albedo layers are stored normalised to a mean
// of 0.5 with most of their hue taken out, and are *multiplied* into the ground's
// own colour rather than replacing it, which is what keeps light green grass
// light green and lets one grass serve every green biome on the planet. See the
// script for how they are made.
//
// Only two of the four are ever read, chosen per pixel. See where the claims are
// worked out below.
const float GROUND_GRASS = 0.0;
const float GROUND_SAND = 1.0;
const float GROUND_STONE = 2.0;
const float GROUND_ICE = 3.0;
// Neither of these is `source_color`, and the albedo one is the surprise. It
// holds no colour: it is a field of light and shade about a mean of 0.5 that
// gets *multiplied* into the ground, and multiplication belongs in linear space.
// Asking for the sRGB decode would take that mean to 0.21, so the doubling below
// would darken every biome on the planet by half and the fix would be a magic
// 4.6 somewhere. Stored linear, the mean really is 0.5 and doubling it really is
// no change.
uniform sampler2DArray ground_albedo : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray ground_surface : filter_linear_mipmap_anisotropic, repeat_enable;
// Cycles per metre: 0.6 repeats every 1.7 m, which is the scale a walking player
// reads as ground rather than as wallpaper. What keeps that repeat from being a
// grid is `texture_scatter` below, which moves the repeat itself; the macro
// field above only varies the light on it, and on its own it hides a lattice
// about as well as clouds hide a chessboard.
uniform float texture_scale = 0.6;
uniform float texture_blend : hint_range(0.0, 1.0) = 0.85;
// How far each cell of ground is allowed to slide the texture it reads, as a
// share of one repeat. This is what stops the tiling being a grid — see
// `vivid_scatter_cells` — and full strength is the useful setting; the dial is
// here to be turned to zero, which takes the ground back to one read per
// projection if the extra two ever cost more than the grid does.
uniform float texture_scatter : hint_range(0.0, 1.0) = 1.0;
// And how far each cell may turn what it reads, as a share of a full circle.
//
// Sliding alone leaves every copy of the texture facing the same way, so
// anything with a direction in it — the lie of grass, the grain in rock, the
// wind lines in sand — still runs one way across the whole planet. That is a
// second pattern underneath the grid and it survives the scatter untouched.
// Turning the cells as well as sliding them is what finally has no direction in
// which the ground repeats.
uniform float texture_spin : hint_range(0.0, 1.0) = 1.0;
// How big one scatter cell is, in texture repeats, and how much of it is a
// blend between neighbours.
//
// Softness at one spreads each blend right across its cell; larger numbers pull
// it into a narrow band at the cell edges. The cube is kept because it was
// measured: spreading the blend out was tried, on the theory that the lattice
// was showing as a grid, and it cost a great deal of crispness — the ground's
// correlation with itself rose from 0.36 to 0.86, which is a photograph turning
// into a wash — while removing none of the blotches it was aimed at, because
// those turned out to be the terrain mesh and not the texture at all.
//
// Powers of two for the size, because the wrap inside vivid_ground_material is
// 64 repeats and a cell that does not divide it puts a step in the lattice
// where it comes round.
uniform float texture_cell = 2.0;
uniform float texture_softness : hint_range(1.0, 6.0) = 3.0;
// How much of every blend is settled by which surface is standing proudest,
// rather than by the weights alone. See vivid_height_weights: this is the
// height blending of terrain splatting. Its real work is at the boundaries
// between materials, where a shoreline used to be a wide band of half sand and
// half grass and is now sand lying in the hollows of the grass. Zero is off.
uniform float splat_depth : hint_range(0.0, 0.6) = 0.25;
// Ground one pixel has to cover before that interlocking is given up and the
// blend goes back to a plain average, in metres.
//
// Height blending decides the handover from detail a few millimetres across. It
// can only do that while a pixel is smaller than the detail; past that the mip
// chain has averaged the occlusion away and what is left is a coin toss that
// re-lands every time the eye moves. So it is faded out on the same principle
// as every other fine thing in this shader.
uniform float splat_resolve = 0.35;
// How hard the two projections separate on a slope. Lower than the old triplanar
// 4 on purpose: the biplanar weights are already rescaled so the dropped axis
// leaves at zero, and squaring on top of that is enough.
uniform float texture_sharpness : hint_range(0.5, 8.0) = 2.0;
uniform float texture_bump : hint_range(0.0, 3.0) = 1.0;
// How much wider than one pixel the ground textures are filtered over.
//
// The gradients handed to `textureGrad` below are the true footprint of a
// pixel, which is the right answer for reading one texture once and the wrong
// one here. Every pixel of this ground is three scattered taps of an albedo
// blended together, three of a surface map, twice over for the two biplanar
// projections, and the blend of several offset copies of a texture has finer
// detail in it than any one copy does. Filtered as though it were a single tap
// it is undersampled, and undersampling is not a blur — it is a different
// answer per pixel that changes whenever the camera moves at all.
//
// So the footprint is widened before it is used. Costs a little sharpness
// underfoot and buys a ground that stops boiling.
//
// How much widening is a measured number and not a taste one. Standing on the
// grass at the ship, the frame-to-frame change in the ground is 1.35 shipped at
// two, 0.79 at four, 0.58 at five and 0.44 at eight, against a floor of 0.11
// with the photograph taken out of the ground altogether. Everything else that
// was suspected of this measures nothing: the map's relief, the procedural
// bumps and the occlusion each move the number by under four percent, and
// turning the scatter off makes it *worse*. It is the colour, and the colour is
// only ever fixed by filtering it wider.
//
// Five rather than eight because past about five the middle distance goes flat
// — the near ground keeps its grain either way, but the band from ten metres
// out to the horizon stops being grass and starts being paint.
uniform float texture_footprint : hint_range(1.0, 8.0) = 1.0;
// Ground a pixel covers, in metres, at which the map's own relief is fully
// given up. The photographs behind this are a couple of millimetres a texel, so
// the bumps in them are gone long before the colour is: past this the mip chain
// is handing back an average that the unpack stretches back out to full tilt in
// whatever direction the averaging happened to leave it, and that direction is
// re-rolled by the smallest camera movement.
uniform float texture_detail_range : hint_range(0.02, 4.0) = 0.4;
// Ground a pixel covers, in metres, at which the scatter's cell weights finish
// relaxing from cubed to flat. Measured against the real footprint rather than
// the widened one, so `texture_footprint` moves how blurred the ground is
// without moving where this happens.
// How much wider again the surface map is filtered than the colour. This is the
// dial that took the sparkle out of this ground; see `vivid_ground_material`
// for why the two maps are not filtered together.
uniform float texture_bump_footprint : hint_range(1.0, 8.0) = 3.0;
uniform float texture_occlusion : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms Motion;
// How fast the eye is crossing the ground, in metres a second. Written by
// Planet from the same smoothed velocity its detail lead is built on, and the
// one thing in this shader that is not derivable from the pixel being drawn.
//
// It has to be told to us, and that is the whole point. Every other guard here
// is built on `footprint`, the ground a pixel covers, which is worked out from
// screen derivatives — a purely spatial measure. It answers "is this detail
// smaller than a pixel", and where it says yes the detail is faded. But the
// other way to alias is temporal: detail comfortably larger than a pixel, held
// at a sample point that moves several metres between one frame and the next.
// Spatially there is nothing wrong with those pixels at all, so no derivative
// can see it, and the ground boils anyway.
//
// Measured, at ninety metres a second: taking the procedural relief out drops
// the frame-to-frame noise by sixty percent and nothing else comes close — the
// grain, the macro field, the occlusion and the sun's shadows each move it by
// under two percent. That is what this fades, and it is not a coincidence that
// it is the one input with no mip chain anywhere in it.
uniform float eye_speed = 0.0;
// Above a sprint, so nothing done on foot is touched. The ground at walking
// pace was quietened by filtering rather than by giving anything up, and that
// tuning is not to be reached by something the player triggers by running.
uniform float motion_calm_from = 22.0;
uniform float motion_calm_to = 90.0;
// What is left of the procedural relief at full speed. Not zero: ground that
// snaps from lit relief to flat shading is a worse artefact than the shimmer,
// and this is small enough that what remains cannot alias loudly.
uniform float motion_relief_keep : hint_range(0.0, 1.0) = 0.12;
// And how wide the photographed colour is filtered once moving, this being the
// second loudest term at speed and one that does have a mip chain to reach for.
uniform float motion_footprint : hint_range(1.0, 32.0) = 14.0;
group_uniforms;

group_uniforms Flora_Glow;
// The night-flowering fields, drawn by the ground once they are too far off to
// be drawn by themselves.
//
// Blooms at the landing site emit in vivid_plant, and that emission is streamed
// cover: a few hundred metres out there are no instances left, so from orbit
// the dark side of this planet is blank where it ought to carry a small violet
// smudge. Nothing is wrong up close and nothing can be fixed up close either —
// the only surface still on screen from out there is the ground, so the ground
// has to carry it.
//
// Written by FlowerTreeField rather than authored here, because the field
// already knows where it is and what radius it planted, and a direction typed
// into a material is a direction that goes stale the first time the colony
// moves. Zero radius disables the whole term.
// Temporary master switch. Plant emission and nearby real lights do not pass
// through this branch, so turning it off removes only the aerial terrain wash.
uniform bool flora_aerial_glow_enabled = false;
uniform vec3 flora_glow_direction = vec3(0.0, 1.0, 0.0);
// Tree radius also defines the square covered by the runtime mask. The mask is
// built from FlowerTreeField's actual generated transforms, so every pink point
// is rooted where a crown really stands rather than being a second unrelated
// scatter pattern.
uniform float flora_glow_radius = 0.0;
// --- The two laws -------------------------------------------------------
//
// Every lit field on this planet glows by one of two rules, and which rule it
// follows is a property of what is growing rather than of where it grows. Add a
// new luminous flower anywhere and it obeys the first; add a new luminous tree
// and it obeys the second. Nothing below is written per-field.
//
//   a wash    Undergrowth. Individually a bloom is centimetres across and there
//             are thousands of them, so from any height at all what reaches the
//             eye is not the blooms but the light off the whole meadow. Drawing
//             them as points is wrong at every altitude: too far apart and it is
//             a dotted pattern, close enough together and it is a wash anyway,
//             and in between it aliases. So it is a wash from the start.
//
//   points    Canopy. A crown is metres across and there are hundreds, far
//             enough apart to be told apart, so these stay individual — and
//             being individual is the whole reason they read as trees and not
//             as more meadow. They are points with a falloff, though, not
//             discs: a light source seen through air has no edge.
//
// Both classes fade in at their own altitude and then fade back down together
// as the climb continues, because a field subtends less and less of the view
// the higher you go and light that did not dim with it would end up as the
// brightest thing on a night side seen from space.
uniform sampler2D flora_tree_glow_mask
	: hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 flora_tree_glow_color : source_color = vec3(1.0, 0.10, 0.42);
uniform float flora_tree_glow_energy : hint_range(0.0, 8.0) = 0.34;
// Higher than the flowers below. Crowns are still being drawn as real meshes at
// this height and their own emission is doing the job; coming in under it would
// lay a second, flatter copy of the canopy over the first.
uniform float flora_tree_glow_begin = 80.0;
uniform float flora_tree_glow_full = 240.0;
// Undergrowth is still a wash, but its footprint is no longer a radius with
// unrelated noise laid over it. GroundCover replays its own seeded scatter once
// and bakes the accepted instance origins into this mask, after every patch,
// terrain, slope, water and clearance rule has had its say. It is therefore
// bright where luminous plants really grow and black where they do not.
uniform float flora_flower_glow_radius = 430.0;
uniform sampler2D flora_flower_glow_mask
	: hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec3 flora_flower_glow_color : source_color = vec3(0.22, 0.015, 0.58);
uniform float flora_flower_glow_energy : hint_range(0.0, 2.0) = 0.28;
// Low, because the blooms are gone from the streamed cover early and the ground
// has to pick the meadow up almost immediately or there is a dark band between
// the two.
uniform float flora_flower_glow_begin = 40.0;
uniform float flora_flower_glow_full = 140.0;
// Where the climb has taken the light back down to `flora_glow_remainder` of
// what it was. It keeps that share above this rather than going out, so the
// fields are still faintly there from orbit.
uniform float flora_glow_ceiling = 5000.0;
uniform float flora_glow_remainder : hint_range(0.0, 1.0) = 0.3;
// Planet-wide counterparts built from every luminous global GroundCover
// species. RGB is already the species' mixed light colour; separate atlases
// preserve the 40 m undergrowth and 80 m canopy handoff laws.
uniform sampler2D global_flora_understory_glow_mask
	: hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D global_flora_canopy_glow_mask
	: hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float global_flora_understory_glow_energy : hint_range(0.0, 2.0) = 0.0;
uniform float global_flora_canopy_glow_energy : hint_range(0.0, 2.0) = 0.0;
// Where the textures stop being read at all. Unlike the noise above this fades
// for cost rather than for aliasing — mipmaps handle the aliasing — and it can
// fade to nothing without a visible edge precisely because the albedo averages
// 0.5: by the time a layer is this far away its mip *is* its own mean, and its
// mean is no tint at all.
uniform float texture_near = 90.0;
uniform float texture_far = 400.0;
// How much of the noise grain survives underneath the textures.
//
// The two are nearly the same effect — a field multiplied into the ground's
// colour — and the obvious saving is to let the photograph replace the three
// octaves of noise entirely. What that misses is that the noise does not repeat
// and the texture does, every 1.7 m, and a repeat that size reads as a grid
// across a hillside. The noise is the cheapest thing available that is coarser
// than the tile and lines up with nothing, so a good part of it is kept and its
// job is now breaking up the tiling rather than being the grain itself.
uniform float grain_under_texture : hint_range(0.0, 1.0) = 0.6;
group_uniforms;

group_uniforms Ground_Materials;
// Which of the four a pixel is standing on, read off the biome colour the vertex
// carries and the ground under it. Colour first, because that is the map: the
// green parts of the planet grow grass, the red parts are sand and the grey
// parts are rock, and reading it that way means a new biome gets a material
// without anything here being told about it.
//
// How sharply a biome colour has to lean before it counts as green, red or grey.
uniform float hue_reach : hint_range(1.0, 20.0) = 7.0;
// What grass holds before any of the others speak, so bare ground has something.
uniform float grass_claim : hint_range(0.0, 1.0) = 0.3;
// Metres above sea level that sand reaches up the beach. Below the waterline it
// carries on down, which is what puts sand on the sea bed.
uniform float shore_height : hint_range(0.0, 60.0) = 7.0;
// A grey biome brighter than this is snow rather than rock.
uniform float snow_above : hint_range(0.0, 1.0) = 0.7;
uniform float cliff_claim : hint_range(0.0, 2.0) = 1.1;
uniform float frost_claim : hint_range(0.0, 2.0) = 1.3;
group_uniforms;

group_uniforms Cliffs;
uniform vec3 cliff_color : source_color = vec3(0.42, 0.35, 0.34);
uniform float cliff_start : hint_range(0.0, 1.0) = 0.22;
uniform float cliff_end : hint_range(0.0, 1.0) = 0.55;
uniform float cliff_roughness : hint_range(0.0, 1.0) = 0.95;
group_uniforms;

group_uniforms Water;
// Water is the one surface here that is smooth, and a smooth surface is where
// the sun and the region's colour actually get to reflect off something.
uniform float water_roughness : hint_range(0.0, 1.0) = 0.06;
uniform float water_specular : hint_range(0.0, 1.0) = 0.9;
uniform vec3 water_deep_tint : source_color = vec3(0.05, 0.32, 0.62);
// The sea bed as a diver sees it, which is not what the vertex colour under the
// waterline says — see where these are used. Sand to silt over [code]bed_reach[/code]
// metres of depth.
// Held near neutral. Everything downstream of it pushes chroma — `saturation` at
// 1.5, then the region's own hue at nearly half strength — and a sand written as
// sand comes out of the pair of them as lime.
uniform vec3 bed_shallow : source_color = vec3(0.70, 0.68, 0.59);
uniform vec3 bed_deep : source_color = vec3(0.30, 0.33, 0.32);
uniform float bed_reach : hint_range(10.0, 500.0) = 170.0;
// Share of the ground's metre-scale bump the bed keeps. Silt and sand are the
// smoothest ground on the planet, and shading them like scree is what the sea bed
// used to be: a flat plain lit at a grazing angle, where a bump that size does not
// read as texture but as broad plates with the light terminator running along their
// edges. Its albedo grain and the slope under it carry the shape instead.
uniform float bed_bump : hint_range(0.0, 1.0) = 0.3;
uniform float wave_scale = 1.6;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.16;
uniform float wave_speed = 0.09;
group_uniforms;

group_uniforms Caustics;
// The net of light on the sea bed, and the shafts of it hanging in the water
// above. Both come out of `vivid_caustic`, which is also what the sea's own
// surface twinkles with — one field, read from three places, so the web on the
// sand is the web glittering on the water over it. Do not retune the scale here
// alone: it has a twin in `planet_water.tres` and they have to agree.
uniform vec3 caustic_color : source_color = vec3(0.62, 0.95, 1.0);
uniform float caustic_scale = 0.25;
uniform float caustic_speed : hint_range(0.0, 4.0) = 0.6;
uniform float caustic_strength : hint_range(0.0, 4.0) = 0.7;
// Depth the net gives out at, in metres. Focused light is what makes it, and a
// surface only stays a lens for as long as its bends have not spread past each
// other — which on real water is about a dozen metres.
uniform float caustic_depth : hint_range(1.0, 80.0) = 14.0;
uniform float caustic_near = 60.0;
uniform float caustic_far = 700.0;
// Shafts, and they are only paid for when the camera is under the water: above
// it there is nothing between the eye and the bed to light up. Metres of the
// view ray marched, and the depth the shafts fade out at.
uniform float shaft_strength : hint_range(0.0, 4.0) = 0.8;
uniform float shaft_reach = 90.0;
uniform float shaft_depth : hint_range(1.0, 200.0) = 40.0;
// The water itself, seen from inside it, comes from the murk globals in
// `vivid_lib` — one set for every surface the sea stands in front of. Without it
// the sea has no body: the bed is as crisp at six hundred metres as at six, and
// shafts drawn through nothing are just a second net laid over the first. It is
// also what a shaft is *made* of, which is why the shafts below are weighted by
// it.
//
// Applied as an emissive fog rather than as a tint on the albedo, because a tint
// would be shaded: ground in shadow would look through clear water and ground in
// the sun through murk.
//
// What the fog takes from the bed is contrast, and contrast is the only thing a
// shape is made of: a bed with a hundred metres of sea in front of it keeps under
// half of its own colour and the wash supplies the rest as one flat sheet, so its
// grain and its slopes arrive at under half strength. This is how much of that
// the ground's own variation is stretched back up by, as a share, and how far the
// stretch is allowed to go.
//
// An eye and not a photon, and worth being honest about. A diver is adapted to
// the wash they are looking through and read what varies against it; a camera at
// a fixed exposure records the wash and loses the rest, and this shader is a
// camera. Only the variation is stretched and never the level, so the bed still
// fades into the water at the distance it did and a trench is still a trench.
uniform float murk_relief : hint_range(0.0, 1.0) = 0.85;
uniform float murk_relief_limit : hint_range(1.0, 4.0) = 3.0;
group_uniforms;

group_uniforms Region;
// How much of the region's hue is mixed into the ground's own colour. This is
// the honest half of the effect and carries most of it: ground really is a
// different colour there.
//
// Set against the sky, which takes its hue from the same wheel at close to full
// strength. The ground cannot go that far — the biome colours are what say sea
// from shore from grass from snow, and past about half they stop saying it — so
// the two do not match, and are not meant to. The sky states the region and the
// ground agrees with it.
uniform float region_albedo : hint_range(0.0, 1.0) = 0.45;
// A grazing-angle sheen in the region's hue. The showy half, and the one that
// has to be kept small: a landscape running to the horizon is nearly all
// grazing angle, so anything generous here is a wash over the whole frame
// rather than a highlight on the edge of a hill.
uniform float region_sheen : hint_range(0.0, 2.0) = 0.18;
// Concentrates that sheen onto true silhouettes. Below about 6 it starts
// reaching the middle distance and reads as fog.
uniform float sheen_falloff : hint_range(1.0, 12.0) = 8.0;
// Off by default, and worth understanding before turning up. Godot's rim is a
// grazing-angle term, and on a landscape running to the horizon almost every
// pixel is a grazing angle — it is a white wash over the whole frame here, not
// the highlight along an edge that it is on a prop.
uniform float region_rim : hint_range(0.0, 1.0) = 0.0;
// What is left of the wheel inside the polar cap. Snow is white, and white is
// the one biome colour that has nothing to spare: the wheel at full strength
// turns a whole ice sheet into a pastel one and the arctic stops reading as
// arctic. A little is kept so the pole still belongs to the same planet.
uniform float region_polar : hint_range(0.0, 1.0) = 0.22;
group_uniforms;

varying vec3 v_world_position;
varying vec3 v_world_normal;

void vertex() {
	if (ground_lift > 0.001) {
		// Vertices are already planet-centred. Lift along the local radial
		// so a steep skirt cannot sink under chunk interpolation. Avoid
		// inverse(MODEL_MATRIX): that path buried the sheet on some parents.
		// COLOR.a is the ramp's lift weight on district aprons (0 at the
		// paved lid and at the planet, 1 mid-slope) so the sheet cannot
		// hover over the city deck.
		float len = length(VERTEX);
		if (len > 0.2) {
			VERTEX += VERTEX * (ground_lift * COLOR.a / len);
		}
	}
	v_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// How much of a class's light has arrived at this height, and how much the
// climb has since taken back off it. One curve, two sets of numbers — this is
// the law both flora classes are held to, and a new luminous field gets its
// behaviour by choosing a pair of altitudes rather than by adding any code.
//
// [param away] is height above the field, growing sideways once past its edge;
// see where it is worked out below.
float vivid_flora_lift(float away, float begin, float full) {
	float risen = smoothstep(begin, full, away);
	if (risen <= 0.0) {
		return 0.0;
	}
	// Down to the remainder by the ceiling, and no further. A field subtends
	// less of the view the higher you get, so light that did not come down with
	// the climb would end up the brightest thing on the night side — but taking
	// it all the way out leaves a planet with glowing meadows on it looking,
	// from orbit, exactly like one without.
	float spent = mix(1.0, flora_glow_remainder,
		smoothstep(full, max(flora_glow_ceiling, full + 1.0), away));
	return risen * spent;
}

// The night-flowering fields as the ground has to draw them. See the Flora_Glow
// uniforms for why the ground is the one drawing them, and for the two laws it
// draws them by.
// [param eye] is passed in rather than read here: Godot's fragment built-ins,
// CAMERA_POSITION_WORLD among them, exist only inside fragment() itself and are
// not in scope in a function it calls.
vec3 vivid_flora_glow(vec3 up, vec3 eye, float dry) {
	if (!flora_aerial_glow_enabled) {
		return vec3(0.0);
	}
	bool has_trees = flora_glow_radius > 0.0 && flora_tree_glow_energy > 0.0;
	bool has_flowers = flora_flower_glow_radius > 0.0
		&& flora_flower_glow_energy > 0.0;
	if (!has_trees && !has_flowers) {
		return vec3(0.0);
	}
	vec3 anchor = normalize(flora_glow_direction);
	// How far the *eye* is from the nearest part of the planted field, and
	// deliberately not how far this pixel is. Within the field this is simply
	// altitude, which makes a vertical flight crossfade continuously from the
	// real plants into this stand-in. On the ground it remains zero anywhere
	// inside the 900 m field, rather than treating somebody at its edge as
	// already far away merely because the anchor is at its centre.
	vec3 eye_from_centre = eye - planet_center;
	vec3 eye_up = normalize(eye_from_centre);
	float eye_altitude = max(length(eye_from_centre) - planet_radius, 0.0);
	float eye_across = acos(clamp(dot(eye_up, anchor), -1.0, 1.0))
		* planet_radius;
	// Each class on its own curve, so the meadow can come up at forty metres
	// while the canopy waits for eighty. Their extents are separate as well:
	// leaving the smaller flower field must not keep using the trees' 900 m
	// radius and pretend the eye is still over undergrowth.
	float tree_lift = 0.0;
	if (has_trees) {
		float tree_outside = max(eye_across - flora_glow_radius, 0.0);
		tree_lift = vivid_flora_lift(
			length(vec2(eye_altitude, tree_outside)),
			flora_tree_glow_begin, flora_tree_glow_full);
	}
	float flower_lift = 0.0;
	if (has_flowers) {
		float flower_outside = max(
			eye_across - flora_flower_glow_radius, 0.0);
		flower_lift = vivid_flora_lift(
			length(vec2(eye_altitude, flower_outside)),
			flora_flower_glow_begin, flora_flower_glow_full);
	}
	if (tree_lift <= 0.0 && flower_lift <= 0.0) {
		return vec3(0.0);
	}
	// Measured over the ground rather than straight through the planet, and
	// inverted into the same tangent coordinates FlowerTreeField used to build
	// the runtime mask. The quotient exactly reverses its normalized
	// `centre + tangent / radius` placement rather than merely approximating it
	// with a chord.
	float across = acos(clamp(dot(up, anchor), -1.0, 1.0)) * planet_radius;
	if (across >= flora_glow_radius
			&& across >= flora_flower_glow_radius) {
		return vec3(0.0);
	}
	vec3 east = normalize(cross(anchor,
		abs(anchor.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 north = normalize(cross(anchor, east));
	float anchor_share = max(dot(up, anchor), 0.0001);
	vec2 field_position = vec2(dot(up, east), dot(up, north))
		* planet_radius / anchor_share;

	// Points, per the canopy law. The mask carries the falloff with it — each
	// mark was drawn as a light rather than as a disc — so there is nothing to
	// shape here, and shaping it was what flattened them into discs before. Its
	// mip chain merges sub-pixel crowns as orbit gets more distant while the
	// black between them stays black, so the canopy never becomes a second
	// meadow.
	vec2 tree_uv = field_position / (2.0 * flora_glow_radius) + 0.5;
	float tree = 0.0;
	if (tree_lift > 0.0 && across < flora_glow_radius) {
		tree = max(textureGrad(flora_tree_glow_mask, tree_uv,
			dFdx(tree_uv), dFdy(tree_uv)).r, 0.0);
	}

	// A wash, per the undergrowth law, but a wash of the generated plants rather
	// than of the circle they were allowed to grow inside. GroundCover has
	// already pooled individual sub-pixel blooms over a few metres and generated
	// mipmaps; sampling that density directly preserves disconnected patches,
	// clearings, shorelines and terrain rejections all the way to orbit.
	float flowers = 0.0;
	if (flower_lift > 0.0 && across < flora_flower_glow_radius) {
		vec2 flower_uv = field_position
			/ (2.0 * flora_flower_glow_radius) + 0.5;
		flowers = max(textureGrad(flora_flower_glow_mask, flower_uv,
			dFdx(flower_uv), dFdy(flower_uv)).r, 0.0);
	}
	// The same sunset the blooms themselves wake at, so this arrives as the
	// last of them goes out of range rather than at a second dusk of its own.
	float night = 1.0 - smoothstep(-0.16, 0.12,
		dot(up, normalize(-sun_direction)));
	// Summed, not chosen between: inside the meadow the crowns stand in their
	// own light, and pink over violet is the point of putting them there.
	// Dry, because nothing planted grows out into the bay beside it.
	return (flora_tree_glow_color * flora_tree_glow_energy * tree * tree_lift
			+ flora_flower_glow_color * flora_flower_glow_energy * flowers
				* flower_lift)
		* night * dry;
}

// The global population atlas is equirectangular: cheap to generate, naturally
// mipmapped and independent of terrain chunk/cube-face seams. The x coordinate
// repeats so the longitude seam joins back onto itself.
vec3 vivid_global_flora_glow(vec3 up, vec3 eye, float water) {
	if (!flora_aerial_glow_enabled) {
		return vec3(0.0);
	}
	if (global_flora_understory_glow_energy <= 0.0
			&& global_flora_canopy_glow_energy <= 0.0) {
		return vec3(0.0);
	}
	float altitude = max(length(eye - planet_center) - planet_radius, 0.0);
	float under_lift = vivid_flora_lift(
		altitude, flora_flower_glow_begin, flora_flower_glow_full);
	float canopy_lift = vivid_flora_lift(
		altitude, flora_tree_glow_begin, flora_tree_glow_full);
	if (under_lift <= 0.0 && canopy_lift <= 0.0) {
		return vec3(0.0);
	}
	vec2 uv = vec2(
		atan(up.x, up.z) / TAU + 0.5,
		0.5 - asin(clamp(up.y, -1.0, 1.0)) / PI);
	// Clamp only the gradients, not the coordinate. At the longitude seam atan
	// jumps by one whole texture even though adjacent texels are neighbours;
	// passing that jump as a gradient would ask for the coarsest mip in a thin
	// vertical line.
	vec2 dx = clamp(dFdx(uv), vec2(-0.04), vec2(0.04));
	vec2 dy = clamp(dFdy(uv), vec2(-0.04), vec2(0.04));
	vec3 under = textureGrad(
		global_flora_understory_glow_mask, uv, dx, dy).rgb;
	vec3 canopy = textureGrad(
		global_flora_canopy_glow_mask, uv, dx, dy).rgb;
	float night = 1.0 - smoothstep(-0.16, 0.12,
		dot(up, normalize(-sun_direction)));
	// Underwater populations are seen through the sea rather than cut out by
	// it. Their atlas contribution is dimmed, leaving the water's own absorption
	// in charge of the rest.
	float through_water = mix(1.0, 0.35, water);
	return (under * global_flora_understory_glow_energy * under_lift
			+ canopy * global_flora_canopy_glow_energy * canopy_lift)
		* night * through_water;
}


// A fixed orthonormal-ish frame turns the pattern lattice away from world axes.
// It is a 3D frame rather than tangent UVs, so there are no cube-face, longitude
// or polar seams anywhere on the sphere.
vec3 vivid_pattern_frame(vec3 point) {
	return vec3(
		dot(point, vec3(0.8138, 0.3420, 0.4698)),
		dot(point, vec3(-0.5127, 0.8397, 0.1830)),
		dot(point, vec3(-0.3319, -0.3899, 0.8591)));
}


vec3 vivid_pattern_colour(vec3 base, float wheel, float amount) {
	vec3 colour = vivid_spectrum(wheel);
	float base_value = max(max(base.r, base.g), base.b);
	colour *= base_value / max(max(max(colour.r, colour.g), colour.b), 0.001);
	return mix(base, colour, amount);
}


vec3 vivid_night_ground_palette(float selector) {
	float band = fract(selector) * 3.0;
	float blend = smoothstep(0.08, 0.92, fract(band));
	if (band < 1.0) {
		return mix(night_ground_glow_color_a, night_ground_glow_color_b, blend);
	}
	if (band < 2.0) {
		return mix(night_ground_glow_color_b, night_ground_glow_color_c, blend);
	}
	return mix(night_ground_glow_color_c, night_ground_glow_color_a, blend);
}


// Large, living patches of faint land emission. Three-dimensional world-space
// noise keeps this continuous over every terrain chunk, cube face and pole.
vec3 vivid_night_ground_glow(
		vec3 world_position, vec3 up, float away, float land) {
	if (night_ground_glow_energy <= 0.0 || land <= 0.0) {
		return vec3(0.0);
	}
	float night = 1.0 - smoothstep(-0.16, 0.12,
		dot(up, normalize(-sun_direction)));
	float range_fade = 1.0 - smoothstep(
		night_ground_glow_near,
		max(night_ground_glow_far, night_ground_glow_near + 1.0),
		away);
	if (night <= 0.0 || range_fade <= 0.0) {
		return vec3(0.0);
	}

	vec3 point = vivid_pattern_frame(world_position - planet_center)
		* night_ground_glow_scale;
	float phase = night_ground_glow_time * night_ground_glow_speed;
	// Closed, differently paced orbits make the warp change shape instead of
	// dragging one rigid texture in a single direction across the ground.
	vec3 drift_a = vec3(
		sin(phase * 0.73),
		cos(phase * 0.61),
		sin(phase * 0.47 + 1.7)) * 0.78;
	vec3 drift_b = vec3(
		cos(phase * 0.53 + 2.4),
		sin(phase * 0.67 + 0.8),
		cos(phase * 0.41)) * 0.72;
	float warp_a = vivid_noise3(point * 0.48 + drift_a + vec3(11.3, 29.1, 5.7));
	float warp_b = vivid_noise3(
		point.zxy * 0.43 + drift_b + vec3(37.2, 3.9, 17.6));
	vec3 warp = vec3(
		warp_a - 0.5,
		warp_b - 0.5,
		warp_a - warp_b) * night_ground_glow_flow;

	float body = vivid_noise3(point + warp + drift_a * 0.24);
	float companion = vivid_noise3(
		point.yzx * 0.64 - warp.zxy * 0.38 - drift_b * 0.21
			+ vec3(23.4, 7.1, 41.8));
	float field = mix(body, companion, 0.28);
	float softness = max(night_ground_glow_softness, 0.001);
	float patch = smoothstep(
		night_ground_glow_threshold - softness,
		night_ground_glow_threshold + softness,
		field);

	// The warp is already a broad field, so it can choose colours without adding
	// another eight hash reads to every terrain pixel. Its palette shift changes
	// each night, reassigning even recurring lobes instead of merely recolouring
	// the whole planet as one flat wash.
	float colour_field = fract(
		warp_a * 0.58 + warp_b * 0.42 + night_ground_glow_palette_shift);
	vec3 colour = vivid_night_ground_palette(colour_field);
	return colour * night_ground_glow_energy * patch
		* night * night * range_fade * land;
}


// Returns target RGB plus the share of the base colour to replace.
//
// Only one family is evaluated at a pixel. The family selector fades to zero
// before changing integer band, so the branch cannot draw a hard border where
// tiger country gives way to crop-circle country. Anti-aliasing is based on the
// real ground footprint passed by fragment(), never on screen-space hash or
// camera position, which keeps every mark motion-stable.
vec4 vivid_ground_pattern(
		vec3 world_position, vec3 up, float footprint, vec3 base) {
	vec3 surface = world_position - planet_center;
	vec3 point = vivid_pattern_frame(surface);
	vec3 pattern_up = normalize(vivid_pattern_frame(up));

	float family_seed = vivid_noise3(
		surface * pattern_region_scale + vec3(17.3, 41.7, 9.2));
	// Value noise naturally spends most of its area around 0.5, which would
	// otherwise make blotches and circles common but tiger/contour regions
	// needlessly rare. Folding a gentle oblique ramp through it distributes all
	// six families around the planet. The wrap itself is invisible because both
	// sides land in the quiet family-transition lane below.
	float family_field = fract(
		family_seed * 2.731
		+ dot(surface, vec3(0.00031, -0.00027, 0.00019)) + 0.37);
	float family_position = clamp(family_field, 0.0, 0.9999) * 6.0;
	float family = floor(family_position);
	float within_family = fract(family_position);
	// A broad quiet lane between families makes every transition authored rather
	// than a discontinuous switch between unrelated equations.
	float family_fade = smoothstep(
		0.035, 0.16, min(within_family, 1.0 - within_family));

	float size_field = vivid_noise3(
		surface * pattern_size_scale + vec3(73.1, 5.4, 29.8));
	float low_size = log2(max(pattern_smallest, 0.5));
	float high_size = log2(max(pattern_largest, pattern_smallest + 0.5));
	float scale = exp2(mix(low_size, high_size, size_field));

	float mask = 0.0;
	float replace = 0.0;
	vec3 target = base;

	if (family < 1.0) {
		// Curved tiger/zebra ribbons. A low-frequency 3D warp keeps them from
		// becoming parallel survey lines over a whole plain.
		float warp = vivid_noise3(
			point / max(scale * 2.8, 1.0) + vec3(11.0, 3.0, 19.0)) - 0.5;
		float phase = (
			point.x * 0.78 + point.y * 0.23 + point.z * 0.57)
			/ max(scale, 0.5) * TAU + warp * 3.4
			+ sin((point.y - point.z) / max(scale * 2.1, 1.0)) * 1.2;
		float stripe = sin(phase) + 0.27 * sin(phase * 0.47 + 1.6);
		float aa = clamp(footprint / max(scale, 0.5) * 5.0, 0.01, 0.42);
		mask = smoothstep(0.30 - aa, 0.66 + aa, stripe);
		target = mix(base * 0.24,
			vivid_pattern_colour(base, 0.08, pattern_color * 0.32), 0.22);
		replace = 0.82;
	} else if (family < 2.0) {
		// Polka-dot / constellation clearings. Spheres intersect the planet as
		// round marks without needing a UV seam; every cell chooses its own size
		// and hue while leaving ample base colour between dots.
		float cell_size = max(scale * 1.55, 1.4);
		vec3 lattice = point / cell_size;
		vec3 cell = floor(lattice);
		vec3 local = fract(lattice) - 0.5;
		vec3 random = vivid_hash33(cell + vec3(31.0, 7.0, 53.0));
		vec3 centre = (random - 0.5) * 0.20;
		float radius = mix(0.12, 0.31,
			vivid_hash13(cell + vec3(5.0, 67.0, 13.0)));
		float distance_to_dot = length(local - centre) - radius;
		float aa = clamp(footprint / cell_size * 1.5, 0.003, 0.24);
		mask = 1.0 - smoothstep(-aa, aa, distance_to_dot);
		target = vivid_pattern_colour(
			base, vivid_hash13(cell + vec3(91.0, 17.0, 2.0)), pattern_color);
		replace = 0.72;
	} else if (family < 3.0) {
		// Broad near-black lichen/ink islands. The threshold is deliberately
		// soft enough to read as a blotch and not a binary noise texture.
		float field = vivid_fbm3(
			point / max(scale * 1.45, 1.0) + vec3(4.0, 23.0, 8.0), 3);
		float aa = clamp(footprint / max(scale, 0.5) * 1.8, 0.01, 0.22);
		mask = smoothstep(0.60 - aa, 0.72 + aa, field);
		target = base * 0.035;
		replace = 0.94;
	} else if (family < 4.0) {
		// Crop circles: several rings, a central disc and a faint cross of
		// radial lanes. They appear only at the larger end of the size field.
		float cell_size = max(scale * 1.75, 72.0);
		vec3 lattice = point / cell_size;
		vec3 cell = floor(lattice);
		vec3 local = fract(lattice) - 0.5;
		vec3 jitter = (vivid_hash33(cell + vec3(8.0, 37.0, 61.0)) - 0.5) * 0.12;
		vec3 delta = (local - jitter) * cell_size;
		delta -= pattern_up * dot(delta, pattern_up);
		float radial = length(delta);
		float ring_step = cell_size * mix(0.052, 0.085,
			vivid_hash13(cell + vec3(19.0, 2.0, 79.0)));
		float line_distance = abs(fract(radial / ring_step + 0.5) - 0.5);
		float aa = clamp(footprint / ring_step, 0.004, 0.25);
		float rings = 1.0 - smoothstep(0.075 - aa, 0.15 + aa, line_distance);

		vec3 reference = abs(pattern_up.z) < 0.84
			? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		vec3 tangent = normalize(cross(reference, pattern_up));
		vec3 bitangent = cross(pattern_up, tangent);
		vec2 planar = vec2(dot(delta, tangent), dot(delta, bitangent));
		float spoke_distance = min(abs(planar.x), abs(planar.y)) / ring_step;
		float spokes = 1.0 - smoothstep(
			0.055 - aa, 0.13 + aa, spoke_distance);
		float centre = 1.0 - smoothstep(
			ring_step * 0.18 - footprint,
			ring_step * 0.42 + footprint, radial);
		float envelope = 1.0 - smoothstep(
			cell_size * 0.30, cell_size * 0.40, radial);
		float site = smoothstep(0.30, 0.48,
			vivid_hash13(cell + vec3(43.0, 11.0, 97.0)));
		mask = max(rings, max(spokes * 0.62, centre)) * envelope * site;
		float alternate = step(0.5, fract(radial / (ring_step * 2.0)));
		target = mix(base * 0.38, min(base * 1.48, vec3(1.0)), alternate);
		replace = 0.76;
	} else if (family < 5.0) {
		// Alien labyrinths: three rotated standing waves intersect into curved,
		// branching contour paths rather than a rectilinear checkerboard.
		vec3 maze_at = point / max(scale * 0.72, 0.7);
		float maze = (
			sin(maze_at.x * TAU)
			+ sin(maze_at.y * TAU * 0.93 + 1.1)
			+ sin(maze_at.z * TAU * 1.07 + 2.4)) / 3.0;
		float aa = clamp(footprint / max(scale, 0.5) * 3.5, 0.01, 0.32);
		mask = 1.0 - smoothstep(0.075 - aa, 0.20 + aa, abs(maze));
		target = vivid_pattern_colour(
			base, vivid_hash13(floor(point / max(scale * 4.0, 2.0))),
			pattern_color * 0.82);
		replace = 0.68;
	} else {
		// Terraced topographic bands. Unlike the tiger family these follow a
		// coherent scalar field, producing nested islands and contour-map veins.
		float field = vivid_fbm3(
			point / max(scale * 2.0, 1.0) + vec3(37.0, 14.0, 6.0), 2);
		float contour = abs(fract(field * 7.0 + 0.5) - 0.5);
		float aa = clamp(footprint / max(scale, 0.5) * 2.2, 0.008, 0.28);
		mask = 1.0 - smoothstep(0.07 - aa, 0.17 + aa, contour);
		float terrace = step(0.5, fract(field * 3.5));
		target = mix(base * 0.50,
			vivid_pattern_colour(base, 0.58 + field * 0.18,
				pattern_color * 0.55), terrace);
		replace = 0.70;
	}

	return vec4(target, clamp(mask * replace * family_fade, 0.0, 1.0));
}


void fragment() {
	vec3 position = v_world_position;
	vec3 normal = normalize(v_world_normal);
	vec3 up = vivid_up(position);
	vec3 view = normalize(CAMERA_POSITION_WORLD - position);
	vec3 volcanic_light = vec3(0.0);
	// Alpha is how wet the ground is, and all this asks of it is whether it is wet
	// at all — the ripples and the sheen that belong on a wet surface. How deep the
	// water runs is measured from the geometry below rather than read off here,
	// because a vertex knows the depth under itself and not the depth a pixel is
	// looking through.
	float wetness = COLOR.a;
	if (ground_lift > 0.001) {
		wetness = 0.0;
	}
	float water = smoothstep(0.0, 0.16, wetness);
	float range = length(CAMERA_POSITION_WORLD - position);
	float detail_fade = 1.0 - smoothstep(detail_near, detail_far, range);
	float macro_fade = 1.0 - smoothstep(macro_near, macro_far, range);

	// Metres of sea between the eye and this point, and how much of the view that
	// column costs, per channel. Everything the water does to this fragment is
	// worked out from this and from the depth of water over the point itself; both
	// are used further down, and why they are lengths rather than a submerged flag
	// is written there.
	float wet_path = vivid_sea_path(CAMERA_POSITION_WORLD, position);
	vec3 haze = vec3(1.0) - exp(-vec3(wet_path) / (murk_visibility * murk_channels));
	bool submerged = vivid_altitude(CAMERA_POSITION_WORLD) < 0.0;
	// How far under the sea this ground is. Used three times below — for the colour
	// of the bed, the daylight reaching it, and the net drawn on it — and read off
	// the geometry rather than off the vertex alpha for the reason given there.
	float under = -vivid_altitude(position);

	// Wet ground is drawn as the sea's own surface — smooth, and with no grain,
	// rock or slope shading of its own — because from outside the water that is
	// what it stands in for. From inside the water it is the sea bed, and the sea
	// bed is ground: it has sand, it has rock where it is steep, and it catches
	// light on its bumps like everything else does. Masking all of that with the
	// wetness alone is what left a diver looking at a floor of flat blue with no
	// shape anywhere in it.
	//
	// So the mirror reading and the ground reading are one switch, and it turns on
	// the eye rather than on the paint. Above the water `sheen` is `water` to the
	// last decimal, which is what it was.
	float sheen = water * (submerged ? 0.0 : 1.0);
	float dry = 1.0 - sheen;
	// The other half of that switch: wet ground with the eye in the water is a sea
	// bed, and it is the one thing here that needs a colour of its own.
	float bed = water - sheen;
	// How much the ground's own variation is stretched to stand against the wash in
	// front of it — see where the two uniforms are declared for why it is stretched
	// at all. Zero above the water, where the fog is a tint on the sea rather than
	// the air the eye is in, and where `dry` has the detail switched off anyway.
	float relief = submerged
		? min(mix(1.0, 1.0 / max(1.0 - haze.g, 0.05), murk_relief), murk_relief_limit)
		: 1.0;

	// How much of the ground's photographed material is being read here, and what
	// is therefore left for the noise to do.
	//
	// The bump is not part of this bargain and is deliberately left alone. It
	// works at a bit over a metre and the textures work at a few centimetres, so
	// they are different bands of the same surface: cancelling the bump under
	// them takes the relief out of a hillside and leaves fine grain painted on a
	// flat plane, which is exactly what it looked like.
	// How arctic this is, which three things below need and which is a dot
	// product and a smoothstep, so it is taken once.
	float frozen = vivid_frost(up);
	// Pack ice is the exception to `dry`, and it is not a small one — it is the
	// largest sheet of ice on the planet. PlanetShape writes it wet on purpose,
	// so that it gets the smooth specular shading the sea gets, which is what ice
	// wants too. But wet here also means "drawn as the surface of the sea", and
	// the sea has no material on it, so gating the textures on `dry` alone left
	// the whole arctic as a blank glossy sheet with nothing in it. Ice is the one
	// surface that is both: shaded like water and made of something.
	//
	// Only inside the cap, because everywhere else wet ground really is water.
	float ground_fade = (1.0 - smoothstep(texture_near, texture_far, range))
		* max(dry, sheen * frozen);
	float noise_detail = 1.0 - (1.0 - grain_under_texture) * texture_blend * ground_fade;
	float surface_rough = ground_roughness;

	vec3 albedo = vivid_saturate(COLOR.rgb, saturation) * brightness;

	// The sea bed's own colour, for the eye that is down there with it.
	//
	// Under the waterline the vertex colour is the sea as a *map* draws it: two
	// blues, chosen by depth and chosen to be told apart from orbit. That is the
	// right answer from outside the water and the wrong one from a metre away — it
	// puts a diver on a floor whose only variation is the noise laid over it, and
	// noise over flat blue reads as flat blue with noise on it, which is precisely
	// the missing topography this is here for. Sand where the light still reaches,
	// silt where it does not, and the slope test below still finds rock on anything
	// steep.
	//
	// Swapped here and not in PlanetShape.color_at, because that colour is what the
	// sea is drawn as from every vantage outside it, up to and including orbit, and
	// a sandy shelf seen from the air is a beach.
	vec3 floor_color = mix(bed_shallow, bed_deep, smoothstep(0.0, bed_reach, under));
	albedo = mix(albedo, vivid_saturate(floor_color, saturation) * brightness, bed);

	// Slope against the planet's own up, not against world up: on a sphere those
	// are the same thing only at one point.
	float slope = 1.0 - clamp(dot(normal, up), 0.0, 1.0);
	// Widened by however much the slope itself changes across one pixel, which
	// is the difference between a threshold and an edge.
	//
	// This number decides which material is painted, and out in the middle
	// distance the normal it is read from swings by a lot from one pixel to the
	// next — the triangles are getting small and their normals are not going
	// quietly. A step function sampled once per pixel over a field like that
	// does not come back as an edge, it comes back as a scatter of pixels that
	// each landed on a different side of it, and since the two sides here are
	// two different photographs, that scatter is two textures interleaved. Then
	// the eye moves a centimetre and it is a different scatter.
	//
	// Spreading the step over the pixel is the standard answer and it costs
	// nothing up close, where the slope is near enough constant across a pixel
	// and this widens by near enough nothing.
	float slope_edge = fwidth(slope);
	float cliff = smoothstep(cliff_start - slope_edge, cliff_end + slope_edge, slope) * dry;
	albedo = mix(albedo, vivid_saturate(cliff_color, saturation), cliff);

	// Two scales of breakup. The macro field is the one that matters at range —
	// without it a hillside is a single flat wash whatever the detail does.
	// Floored, because `relief` can push either amount past 1 and a mix past 1 is
	// an extrapolation: at a strong enough stretch the dark half of a field would
	// otherwise cross zero and start brightening the ground again.
	float macro = vivid_fbm3(position * macro_scale, 4);
	albedo *= max(mix(1.0, 0.6 + 0.8 * macro,
		macro_amount * dry * macro_fade * relief), 0.0);
	float grain = vivid_fbm3(position * detail_scale, 3);
	albedo *= max(mix(1.0, 0.65 + 0.7 * grain,
		detail_amount * dry * detail_fade * relief * noise_detail), 0.0);

	// The ground's own material, photographed. What it contributes is grain,
	// occlusion, roughness and bumps; the colour stays the biome's.
	//
	// The four are ranked and only the best two are read. Which two varies from
	// pixel to pixel and the ranking changes along every boundary, so the third
	// place is subtracted from both before they are weighed against each other:
	// at the moment two materials swap rank they are worth the same, so the one
	// being dropped is worth exactly nothing as it goes and nothing pops. Without
	// that subtraction a shoreline flickers between sand and grass along its
	// whole length.
	//
	// Gradients are taken here, at the top level, and handed down. Inside
	// `vivid_ground_material` the choice of projection differs between
	// neighbouring pixels, and a derivative taken there would be differencing
	// pixels that went the other way.
	//
	// They are differenced in view space and rotated out, rather than
	// differenced in world space. A world position on this planet is a couple of
	// thousand metres from the origin, where a 32-bit float has about a quarter
	// of a millimetre left in it — a good fraction of the ground one pixel
	// covers underfoot. The difference of two such numbers is mostly
	// quantisation, and the mip level chosen from it crawls and sparkles as the
	// camera moves. VERTEX is metres from the eye and differences cleanly.
	mat3 into_world = mat3(INV_VIEW_MATRIX);
	vec3 texture_at = position * texture_scale;
	vec3 pixel_dx = into_world * dFdx(VERTEX);
	vec3 pixel_dy = into_world * dFdy(VERTEX);
	// See the Motion block. Widening the filter is worth far less here than
	// calming the relief is, but it is nearly free and it is the right lever for
	// the colour, which is the only other term that moves at speed.
	float rushing = smoothstep(motion_calm_from,
		max(motion_calm_to, motion_calm_from + 1.0), eye_speed);
	float wide = mix(texture_footprint,
		max(motion_footprint, texture_footprint), rushing);
	vec3 texture_dx = pixel_dx * texture_scale * wide;
	vec3 texture_dy = pixel_dy * texture_scale * wide;
	// Ground one pixel covers, in metres. Distance is the obvious stand-in for
	// this and is badly wrong at a grazing angle, which is most of the ground
	// most of the time: stood up with the eye a metre and a half off the floor,
	// a pixel a hundred metres out spans several metres of it while `range`
	// still reads a hundred. That is why the fades below are written against
	// this and not against distance.
	float footprint = max(length(pixel_dx), length(pixel_dy));
	vec3 ground_normal = normal;
	if (texture_blend > 0.0 && ground_fade > 0.0) {
		vec3 biome = COLOR.rgb;
		float brightest = max(max(biome.r, biome.g), biome.b);
		float chroma = brightest - min(min(biome.r, biome.g), biome.b);
		float green = clamp((biome.g - max(biome.r, biome.b)) * hue_reach, 0.0, 1.0);
		float red = clamp((biome.r - max(biome.g, biome.b)) * hue_reach, 0.0, 1.0);
		float grey = 1.0 - clamp(chroma * hue_reach, 0.0, 1.0);
		// Anything bright that is not warm. Dark grey is rock and bright grey is
		// snow, which is the only thing separating an ice sheet from a scree
		// slope in a colour with no hue to read — but grey alone is not enough,
		// because PlanetShape paints pack ice a deliberate blue to tell it from
		// the snow beside it, and that blue is far too saturated to pass a grey
		// test. Being cool counts as well as being colourless.
		float cool = clamp((biome.b - biome.r) * hue_reach, 0.0, 1.0);
		float pale = max(grey, cool)
			* clamp((brightest - snow_above) * hue_reach, 0.0, 1.0);
		// Sand runs from `shore_height` down, so one number covers the beach and
		// the sea bed under it — they are the same material and the waterline is
		// not a boundary between them.
		//
		// Widened across the pixel for the same reason the cliff test above is.
		// Height runs away from the eye far faster than slope does: at a grazing
		// angle a pixel in the middle distance spans metres of ground and so
		// several metres of rise, which is the whole of this test.
		float height = vivid_altitude(position);
		float height_edge = fwidth(height);
		float shore = 1.0 - smoothstep(-height_edge, shore_height + height_edge, height);

		// Ice is settled first, because the other three have to know about it. A
		// frozen shore is not a beach, and pack ice sits at sea level, so the
		// beach rule fires on the whole arctic coast unless it is told not to.
		float ice = max(pale, frozen * frost_claim);
		float sand = (red + shore) * (1.0 - min(ice, 1.0));
		float stone = max(grey - pale, 0.0) + cliff * cliff_claim;
		// Grass is the fallback and not a competitor, which is the whole reason
		// it is written as a subtraction. As a flat floor it was quietly in
		// second place on every pixel of the planet that was not already green —
		// and second place is not free here, it is the other half of the blend,
		// so snow came out a third grass, rock a third grass, and desert a
		// quarter. What it means now is that grass holds any ground the other
		// three have not spoken for.
		float grass = max(green, grass_claim - max(max(sand, stone), ice));

		// In the layer order at the top of the file.
		vec4 claim = vec4(grass, sand, stone, ice);

		// A four-element sorting network, carrying each material's layer along
		// with its claim.
		vec2 first = vec2(claim.x, GROUND_GRASS);
		vec2 second = vec2(claim.y, GROUND_SAND);
		vec2 third = vec2(claim.z, GROUND_STONE);
		vec2 fourth = vec2(claim.w, GROUND_ICE);
		vec2 swap;
		if (second.x > first.x) { swap = first; first = second; second = swap; }
		if (fourth.x > third.x) { swap = third; third = fourth; fourth = swap; }
		if (third.x > first.x) { swap = first; first = third; third = swap; }
		if (fourth.x > second.x) { swap = second; second = fourth; fourth = swap; }
		if (third.x > second.x) { swap = second; second = third; third = swap; }
		float runner_up = (second.x - third.x)
			/ max((first.x - third.x) + (second.x - third.x), 0.0001);

		vec4 near_albedo;
		vec4 far_albedo;
		float near_rough;
		float far_rough;
		vec3 near_lean;
		vec3 far_lean;
		// Handed down in the units the footprint inside is measured in: repeats
		// of the texture, widened by the same factor the gradients were. Stated
		// in metres of ground up here and converted once here, so neither the
		// texture's scale nor how far it is over-filtered changes where the
		// fade lands.
		float detail_span = texture_detail_range * texture_scale * wide;
		// One depth for both blends, opened up as the pixel outgrows the relief
		// that would otherwise be deciding them. Zero means off rather than
		// meaning an infinitely hard pick, so that turning it off is a way back
		// to plain averaging and not a way to a worse artefact than it fixes.
		float splat_now = 0.0;
		if (splat_depth > 0.0) {
			splat_now = mix(splat_depth, 1.0,
				clamp(footprint / max(splat_resolve, 0.0001), 0.0, 1.0));
		}
		vivid_ground_material(ground_albedo, ground_surface, first.y, texture_at,
			texture_dx, texture_dy, normal, texture_sharpness, texture_bump,
			texture_scatter, texture_spin, texture_cell, texture_softness,
			splat_now, detail_span, texture_bump_footprint,
			near_albedo, near_rough, near_lean);
		vivid_ground_material(ground_albedo, ground_surface, second.y, texture_at,
			texture_dx, texture_dy, normal, texture_sharpness, texture_bump,
			texture_scatter, texture_spin, texture_cell, texture_softness,
			splat_now, detail_span, texture_bump_footprint,
			far_albedo, far_rough, far_lean);
		// And the same again one level up, between the two materials competing
		// for this pixel. This is where splatting usually shows its seam: the
		// claims either side of a shoreline or a scree line cross over slowly,
		// so a wide band of ground is a half-and-half average of sand and grass
		// and looks like neither. Letting the occlusion decide it puts sand in
		// the hollows of the grass instead.
		float toward_far = runner_up;
		if (splat_now > 0.0) {
			toward_far = vivid_height_toward(near_albedo.a, far_albedo.a,
				runner_up, splat_now);
		}
		vec4 material = mix(near_albedo, far_albedo, toward_far);

		float strength = texture_blend * ground_fade;
		// Shaped by the same amount it is painted by. The tilt used to be
		// applied at full strength however far off the ground was, so a
		// hillside that had already faded back to flat biome colour was still
		// being lit as though it carried every millimetre of the texture's
		// relief. Fading the two together is what stops the far field being
		// covered in relief belonging to a texture that is no longer there.
		vec3 leaned = mix(near_lean, far_lean, toward_far);
		ground_normal = normalize(normal + (leaned - normal) * strength);
		// Doubled because the layer is stored about a mean of 0.5, so an average
		// patch of it multiplies the biome by one and leaves it alone. Occlusion
		// is separate and only ever darkens.
		vec3 painted = albedo * material.rgb * 2.0
			* mix(1.0, material.a, texture_occlusion);
		albedo = mix(albedo, painted, strength);
		surface_rough = mix(surface_rough, mix(near_rough, far_rough, toward_far), strength);
	}

	// Deliberate macro markings sit over the material grain but under the
	// planet-wide region tint. They therefore inherit the local biome and sky
	// palette instead of looking like decals pasted over it.
	float pattern_flat = 1.0 - smoothstep(
		pattern_flat_from, max(pattern_flat_to, pattern_flat_from + 0.001), slope);
	float pattern_distance = 1.0 - smoothstep(
		pattern_near, max(pattern_far, pattern_near + 1.0), range);
	float pattern_ground = max(dry, sheen * frozen);
	if (pattern_amount > 0.0 && pattern_flat > 0.0
			&& pattern_distance > 0.0 && pattern_ground > 0.0) {
		vec4 marking = vivid_ground_pattern(position, up, footprint, albedo);
		albedo = mix(albedo, marking.rgb, marking.a * pattern_amount
			* pattern_flat * pattern_distance * pattern_ground);
	}

	// Cooled basalt and broad ember fissures across the south-pole island. The
	// height field's vertex colour already names this as stone; this pass adds
	// the specifically volcanic read at a frequency broad enough to remain
	// stable in motion. The liquid itself is a separate animated mesh.
	if (volcano_enabled && volcano_radius > 0.0) {
		float south = dot(up, -normalize(frost_axis));
		float volcanic = smoothstep(
			cos(volcano_radius / max(planet_radius, 1.0)),
			cos(volcano_radius * 0.82 / max(planet_radius, 1.0)), south) * dry;
		if (volcanic > 0.0) {
			float cone = smoothstep(
				cos(volcano_cone_radius / max(planet_radius, 1.0)),
				cos(volcano_cone_radius * 0.58 / max(planet_radius, 1.0)), south);
			float ash = vivid_fbm3(position * 0.009 + vec3(19.0, 7.0, 31.0), 2);
			vec3 cooled = mix(volcano_basalt, volcano_ash, 0.22 + ash * 0.52);
			albedo = mix(albedo, cooled, volcanic * 0.38);

			float ridge = vivid_ridge3(
				position * volcano_crack_scale + vec3(5.0, 23.0, 11.0), 2);
			float edge = fwidth(ridge) * 1.6;
			float crack = smoothstep(0.78 - edge, 0.91 + edge, ridge);
			float resolved = 1.0 - smoothstep(
				0.22, 0.9, footprint * volcano_crack_scale);
			float hot = crack * volcanic * resolved * (0.22 + cone * 0.78);
			albedo = mix(albedo, volcano_ember * 0.16, hot * 0.48);
			volcanic_light = volcano_ember * volcano_crack_energy * hot;
		}
	}

	// What daylight is left this far down. Light going down a column is spent at
	// much the same sort of rate as sight along one, so a bed four hundred metres
	// under is not sunlit sand a long way off: it is unlit. Applied here, before the
	// water in front of it — that order is the whole of it, because the tint below
	// stands for the sea itself, and the sea is as bright as its own surface however
	// dark the bed under it is. The other way round turns deep ocean seen from the
	// air black.
	float sunk = vivid_daylight(under, murk_daylight);
	albedo *= sunk;

	// Water looked into from outside it. The more of it stands in front of the bed,
	// the less of the bed's own colour survives and the more of the sea's is left,
	// so a lagoon reads as sand under glass and a trench reads as sea.
	//
	// Measured off the column rather than lerped from the painted depth in the
	// vertex alpha, which is what this was. Same intent, but the alpha is a map of
	// how deep the water is under a *vertex* while the column is how much of it a
	// *pixel* is looking through — so the painted version tinted a bay by the same
	// amount from directly overhead as from a kilometre away along the surface, and
	// looking down into shallow water got no water in the way at all. The result
	// was ground in a slightly odd colour, which is exactly what it looked like.
	vec3 shoal = submerged ? vec3(0.0) : haze;
	albedo = mix(albedo, vivid_saturate(water_deep_tint, saturation), shoal);

	vec2 region = vivid_region(up);
	vec3 region_color = vivid_spectrum(region.x);
	// The spectrum averages 0.5 a channel, so doubling it swings the hue while
	// leaving the ground about as bright as it was. Saturating the result again
	// on top of that is what turned the first pass of this into fluorescent
	// paint; the hue shift is enough on its own.
	float region_strength = region_albedo * mix(0.35, 1.0, region.y)
		* mix(1.0, region_polar, frozen);
	albedo = mix(albedo, albedo * region_color * 2.0, region_strength);

	// Normals: waves on the water, ground grain on the land. Both are worth more
	// than any amount of albedo detail, because they are what makes light move
	// across the surface as the camera does.
	// How much of one bump a pixel covers. Procedural noise has no mip chain to
	// fall back on, so once a pixel is wider than the cell it is reading, the
	// value it gets is a lottery — and next frame's is a different one. The
	// distance fade above was meant to cover this and cannot: at two hundred
	// metres it is still letting a fifth of the relief through while a pixel
	// out there spans several cells of it. Zero here also skips the noise
	// entirely, which is three fields of it not evaluated.
	float bump_resolved = 1.0 - smoothstep(VIVID_DETAIL_KEEP, VIVID_DETAIL_GONE,
		footprint * bump_scale);
	float wave_resolved = 1.0 - smoothstep(VIVID_DETAIL_KEEP, VIVID_DETAIL_GONE,
		footprint * wave_scale);

	// The temporal guard, beside the two spatial ones above. `bump_resolved`
	// asks whether a bump is smaller than a pixel and this asks whether it is
	// standing still long enough to be worth drawing; a bump can pass the first
	// and fail the second, and at flying speed most of them do.
	float bump_now = bump_strength * mix(1.0, motion_relief_keep, rushing);

	vec3 shaped = ground_normal;
	if (bump_now > 0.0 && detail_fade > 0.0 && bump_resolved > 0.0) {
		// Not stretched by `relief`. That number is a contrast, and a bump is not:
		// tilting the normal harder does not scale the ground's variation about its
		// own mean, it drives `normalize` toward the noise gradient's own direction,
		// which is near enough constant across a cell. At three times the strength
		// the bed came out as a plaid of flat facets one noise cell wide — more
		// shape in the numbers and less of it in the picture.
		//
		// `bump_resolved` gates this and no longer scales it. It is one number
		// for a field of three octaves, so used as a strength it took the metre
		// swells away at the distance the centimetre grain stopped resolving —
		// the flicker went and the ground went flat with it. The field is told
		// the pixel instead and drops its own octaves as each stops being
		// resolvable, which leaves the swells lit at ranges the single fade had
		// been switching them off at.
		shaped = vivid_bump_normal(position, shaped, bump_scale,
			bump_now * dry * detail_fade * mix(1.0, bed_bump, bed),
			footprint * bump_scale);
	}
	float wave_now = wave_strength * mix(1.0, motion_relief_keep, rushing);
	if (wave_now > 0.0 && sheen > 0.0 && detail_fade > 0.0
			&& wave_resolved > 0.0) {
		vec3 drift = vec3(TIME * wave_speed, TIME * wave_speed * 0.63, 0.0);
		shaped = vivid_bump_normal(position + drift, shaped, wave_scale,
			wave_now * sheen * detail_fade, footprint * wave_scale);
	}

	// The water column, read the other way. Inside the sea it is fog around the eye:
	// it takes the ground away and puts a lit wash in its place. From outside it is
	// the sea's own colour over the bed, which is the `shoal` mix further up. One
	// length, two readings, never both at once.
	//
	// That length is the whole reason looking down into a bay reads as water rather
	// than as oddly blue grass. It used to be a test of whether the *camera* was
	// under the surface, which is cheap and wrong in the common case: from a beach
	// or from the air every metre of sea between the eye and the bed counted for
	// nothing, so a lagoon and a trench were drawn with the same clarity and the
	// only thing marking either as wet was a sheen on it.
	//
	// Neither reading is masked by `water`: where the ground sits relative to sea
	// level is a fact, and what colour it was painted is not part of it.
	//
	// Caustics and the shafts feeding them are light rather than paint, so they go
	// into emission and are scaled by how high the sun is — a net on the bed at
	// midnight is a glowing sea floor, which is the one thing worse than no net at
	// all — and the net fades out as the column thickens, because a bed nobody can
	// see cannot have a pattern on it.
	vec3 caustic_light = vec3(0.0);
	vec3 murk = submerged ? haze : vec3(0.0);
	// The scalar reading of it, for the three things that are one number rather
	// than three: how rough the fog is, how much specular is left behind it, and
	// how much water a shaft has to be scattered out of. Green, because green is
	// the channel the single-rate version was written as.
	float murk_dim = murk.g;
	// The wash is lit by the water standing between the eye and here — but not by
	// all of it evenly. What is seen of a column is almost entirely its near end,
	// because the far end is behind the rest of it, so the depth it is lit at is
	// the depth about a visibility along the ray and not the depth halfway to a bed
	// four hundred metres off. The midpoint of the whole run was the first go at
	// this and it read every downward view in deep water as unlit black.
	//
	// It is still what puts a gradient in a view under the sea: the water toward
	// the surface is lit from shallower than the eye and the water toward the bed
	// from deeper, so a diver has an up before anything in the frame has a shape.
	float toward = 0.5 * min(murk_visibility, wet_path) / max(wet_path, 0.001);
	float column = vivid_daylight(
		mix(-vivid_altitude(CAMERA_POSITION_WORLD), under, toward), murk_daylight);
	float noon = smoothstep(-0.05, 0.35, dot(up, normalize(-sun_direction)));
	// Shafts stay a thing seen from *inside* the water, unlike everything else here.
	// You see a shaft because you are in the medium doing the scattering and are
	// looking along it; from above there is nothing to look along, and the honest
	// version of the view — sunlight going in, and coming back only where it has a
	// bed to bounce off — is the blue column and the net, which are already here.
	// Marching them from above put a bright net over a five-hundred-metre trench,
	// which read as a reef in water a few feet deep, and charged six noise samples
	// for every ocean pixel on the planet to do it.
	if (murk_dim > 0.0 && shaft_strength > 0.0 && noon > 0.0) {
		// Weighted by the murk, because a shaft is the light scattered out of the
		// water in its path and there is exactly as much of that as there is water.
		// It also puts the shafts where they read: over the far bed, which the fog
		// has taken down to a flat wash.
		//
		// And by the daylight in that water, for the same reason the wash is: a
		// shaft is one part of the light in the column and cannot be brighter than
		// the column it is in. Without it the shafts held full strength at any
		// depth and became the whole of the picture down there — bright swirls
		// painted across a flat panel, which is the one thing a deep dive is not.
		caustic_light += caustic_color * shaft_strength * noon * murk_dim * column
			* vivid_sea_shafts(CAMERA_POSITION_WORLD, position,
				caustic_scale, caustic_speed, shaft_reach, shaft_depth);
	}
	if (under > 0.0 && noon > 0.0 && caustic_strength > 0.0) {
		float web_fade = (1.0 - smoothstep(caustic_near, caustic_far, range))
			* (1.0 - smoothstep(0.0, caustic_depth, under)) * (1.0 - haze.g);
		if (web_fade > 0.0) {
			caustic_light += caustic_color * caustic_strength * noon * web_fade
				* vivid_caustic(position, caustic_scale, caustic_speed);
		}
	}

	float fresnel = pow(1.0 - clamp(dot(shaped, view), 0.0, 1.0), sheen_falloff);

	// Fogging in two halves: the ground is taken away and the water is put in its
	// place. Killing the albedo is what stops the fog being lit — the shading
	// still runs, but there is nothing left for it to shade.
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0)) * (1.0 - murk);
	NORMAL = vivid_to_view(VIEW_MATRIX, shaped);
	// Under water, the sea bed is sand and not a mirror.
	//
	// Wet ground is written as smooth and specular so that an ocean seen from
	// above has a sheen on it at the ranges the sea's own ripples have faded out
	// at. From inside the water that reading is simply wrong — the mirror is the
	// surface overhead, which is drawn separately — and it costs the whole view:
	// a bed at 0.9 specular and 0.06 roughness returns the sky whatever is put in
	// front of it, so the murk took the albedo down to nothing and the bottom
	// stayed as bright as an unfogged one, with the sun burnt into it.
	//
	// This one really is about the eye and not about the column: the mirror is a
	// reading of the surface, and from below there is no surface here to read. It
	// is the same switch the ground detail above is gated on.
	ROUGHNESS = mix(mix(mix(surface_rough, cliff_roughness, cliff),
		water_roughness, sheen), 1.0, murk_dim);
	SPECULAR = mix(ground_specular, water_specular, sheen) * (1.0 - murk_dim);
	METALLIC = 0.0;
	// Godot's rim is lit by the real lights, so it reads as the sun catching the
	// edge of a hill. The emission beside it is not, which is what keeps a
	// gleaming region visible on the night side as a faint aurora.
	RIM = region_rim * mix(0.4, 1.0, region.y) * (1.0 - murk_dim);
	RIM_TINT = 0.35;
	EMISSION = region_color * fresnel * region_sheen * region.y * mix(0.35, 1.0, water + 0.35)
		* (1.0 - murk_dim)
		+ murk_color * murk * mix(0.06, 1.0, noon) * column
		+ caustic_light
		+ volcanic_light
		+ vivid_night_ground_glow(
			position, up, range, 1.0 - water) * (1.0 - murk_dim)
		+ vivid_flora_glow(up, CAMERA_POSITION_WORLD, dry)
		+ vivid_global_flora_glow(up, CAMERA_POSITION_WORLD, water);
}
