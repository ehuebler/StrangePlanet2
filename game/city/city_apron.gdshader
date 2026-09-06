shader_type spatial;
// Leftover homemade slope card. Runtime aprons use vivid_terrain_apron.gdshader
// so they photograph as planet ground. Kept as a reference for the lift and
// the cull_disabled render mode that sheet still needs.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, depth_draw_opaque;

#include "res://shaders/vivid/vivid_lib.gdshaderinc"

uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	// Push along planet-up, not the face normal. A slope normal can shove
	// the sheet into the terrain and hide it while the collider stays put.
	vec3 up = normalize(VERTEX);
	if (length(up) < 0.2) {
		up = NORMAL;
	}
	VERTEX += up * 0.28;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 up = vivid_up(world_pos);
	vec3 base = vivid_saturate(COLOR.rgb, 1.5) * 0.62;
	vec2 region = vivid_region(up);
	vec3 region_color = vivid_spectrum(region.x);
	float region_strength = 0.45 * mix(0.35, 1.0, region.y);
	base = mix(base, base * region_color * 2.0, region_strength);
	float grain = fract(sin(dot(COLOR.rg + FRAGCOORD.xy * 0.015, vec2(12.9898, 78.233))) * 43758.5453);
	base *= 0.90 + 0.14 * grain;
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0)) * mix(1.0, 0.24, night);
	ROUGHNESS = 0.94;
	METALLIC = 0.02;
	SPECULAR = 0.16;
	EMISSION = vec3(0.0);
}
