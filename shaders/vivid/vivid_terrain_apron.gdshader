// District slope: the same photographed ground as the planet, but the
// sheet has to stay visible from the downhill side and from grazing
// angles. A steep skirt's geometric normal is nearly horizontal, so the
// planet-up winding test used to flip at random and `cull_back` ate the
// face. Disabling cull keeps the dirt there from either side.
//
// `ground_lift` in the shared body pushes the sheet along planet-up so
// chunk interpolation cannot bury it. Vertex colour alpha is the lift
// weight (zero at the paved lid and at the planet) so the collider and
// the photograph meet the city deck. The collider stays on the authored
// mesh.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/vivid/vivid_terrain_core.gdshaderinc"
