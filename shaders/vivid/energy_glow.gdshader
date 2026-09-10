// Fiery energy on a plain sphere or cylinder.
//
// The mesh is only a hull. The camera-facing middle is a white-hot core; the
// rest is fire that crawls and flickers. Mobs pass fire_color and core_color.
// Invert swaps which colour sits in the hot centre.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never,
	shadows_disabled, fog_disabled;

uniform vec4 fire_color : source_color = vec4(1.0, 0.32, 0.22, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.94, 0.78, 1.0);
uniform float energy : hint_range(0.2, 16.0) = 3.4;
uniform float flicker : hint_range(0.0, 1.0) = 0.55;
uniform float core_size : hint_range(0.05, 0.85) = 0.30;
uniform float shape : hint_range(0.0, 1.0) = 0.0;
uniform float layer : hint_range(0.0, 1.0) = 1.0;
uniform float invert : hint_range(0.0, 1.0) = 0.0;
uniform float seed : hint_range(0.0, 64.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float fire_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float n00 = mix(n000, n100, f.x);
	float n10 = mix(n010, n110, f.x);
	float n01 = mix(n001, n101, f.x);
	float n11 = mix(n011, n111, f.x);
	return mix(mix(n00, n10, f.y), mix(n01, n11, f.y), f.z);
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float axis = length(obj_pos.xz);
	float along = mix(length(obj_pos), obj_pos.y, shape);
	vec3 drift = vec3(seed * 0.17, TIME * 2.8, TIME * 1.6 + seed);
	float n = fire_noise(vec3(obj_pos.x, along, axis) * mix(5.4, 7.2, shape) + drift);
	n = mix(n, fire_noise(obj_pos * 9.0 - drift.yxz), 0.45);
	float flame = mix(1.0, 0.58 + 0.42 * n, flicker);

	vec3 fire = fire_color.rgb;
	vec3 core = core_color.rgb;
	if (invert > 0.5) {
		vec3 swap = core;
		core = fire;
		fire = swap;
	}

	// Tight over-exposed centre; glow layer keeps a thinner hotspot.
	float hot_pow = mix(6.4, 3.6, shape) + layer * 1.8;
	float hot = pow(facing, hot_pow);
	hot *= smoothstep(0.12, 0.12 + core_size * 1.6, facing);

	// Mid fire and a crawling rim. Glow layer owns the sheath.
	float body = pow(facing, mix(1.25, 0.78, shape)) * (1.0 - hot * 0.62);
	float rim = pow(1.0 - facing, mix(1.15, 1.7, shape));
	float sheath = body * mix(0.28, 1.0, layer) + rim * layer * (0.55 + 0.45 * n);

	vec3 colour = core * hot * (2.4 - layer * 1.2) * energy;
	colour += fire * sheath * flame * energy;
	// Soft disk so the hull is light, not a painted ball.
	float mask = pow(facing, mix(0.55, 0.35, layer));
	float alpha = clamp((hot * 0.95 + sheath * 0.78) * mask, 0.0, 1.0);

	colour *= opacity;
	ALBEDO = colour;
	EMISSION = colour;
	ALPHA = alpha * opacity;
}
