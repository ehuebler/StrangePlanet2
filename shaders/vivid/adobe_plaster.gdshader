// Procedural adobe plaster. The Blender assets store grain in world-space
// noise, not UVs, so a GLB arrives as three flat colours. This puts that
// clay, sand, and pore bump back on the mesh and keeps the palette as a
// single albedo the site can recolor.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/vivid/vivid_lib.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.8, 0.025, 0.035, 1.0);
uniform float roughness : hint_range(0.4, 1.0) = 0.88;
uniform float clay_scale = 3.1;
uniform float grain_scale = 48.0;
uniform float pore_scale = 37.0;
uniform float clay_bump : hint_range(0.0, 1.0) = 0.24;
uniform float grain_bump : hint_range(0.0, 1.0) = 0.30;
uniform float pore_bump : hint_range(0.0, 1.0) = 0.17;

varying vec3 world_p;

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float adobe_pore(vec3 p) {
	vec3 cell = floor(p);
	float best = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 corner = cell + vec3(float(x), float(y), float(z));
				best = min(best, length(corner + vivid_hash33(corner) - p));
			}
		}
	}
	return best;
}

float adobe_height(vec3 p) {
	float clay = vivid_noise3(p * clay_scale);
	float grain = vivid_noise3(p * grain_scale);
	float pore = 1.0 - smoothstep(0.07, 0.23, adobe_pore(p * pore_scale));
	return clay * 0.52 + grain * 0.33 + pore * 0.15;
}

void fragment() {
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 tangent = normalize(cross(world_n,
			abs(world_n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 bitangent = cross(world_n, tangent);
	float step_size = 0.012;
	float h = adobe_height(world_p);
	float hx = adobe_height(world_p + tangent * step_size);
	float hy = adobe_height(world_p + bitangent * step_size);
	float gain = clay_bump * 1.6 + grain_bump * 0.7 + pore_bump * 0.45;
	vec3 bumped = normalize(world_n + (h - hx) * tangent * gain + (h - hy) * bitangent * gain);
	NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);

	float grain = vivid_noise3(world_p * grain_scale);
	float clay = vivid_noise3(world_p * clay_scale);
	float shade = 0.86 + clay * 0.10 + grain * 0.08;
	ALBEDO = albedo.rgb * shade;
	ROUGHNESS = clamp(mix(0.80, 0.96, grain) * (roughness / 0.88), 0.45, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.22;
}
