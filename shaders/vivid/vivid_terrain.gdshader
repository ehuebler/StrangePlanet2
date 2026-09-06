// The planet's ground.
//
// Terrain arrives as bare vertex colour: PlanetShape decides the biome on the
// CPU and writes it per vertex, with the water depth in alpha. That is a few
// hundred metres between colour samples on a coarse chunk, so everything that
// makes the ground read as ground at walking distance has to be added here —
// grain, macro variation, slope, wetness and the bumps that catch light.
//
// Colour comes from three places that are deliberately kept apart:
//   the biome     what kind of ground this is, from the vertex colour
//   the region    where it sits on the planet's colour wheel, from vivid_lib
//   the light     which is Godot's own PBR, not a custom light() function
//
// Keeping the light real is what stops the vivid palette from reading as a
// cartoon: the hues are exaggerated, the shading underneath them is not.
//
// The look lives in vivid_terrain_core.gdshaderinc. This wrapper keeps
// back-face cull so the sphere does not draw its inner shell. District ramps
// use vivid_terrain_apron.gdshader instead — same photographs, no cull.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/vivid/vivid_terrain_core.gdshaderinc"
