shader_type spatial;
// Painted pad. ALPHA=1.0 used to force the transparent pipeline and let
// distant geometry show through; keep this opaque and shaded so night
// matches the surrounding terrain while lamps still light the surface.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, depth_draw_opaque;

uniform sampler2D ground_map : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 map_span = vec2(400.0, 400.0);
uniform vec2 map_origin = vec2(0.0);
uniform sampler2D break_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 break_origin = vec2(0.0);
uniform vec2 break_span = vec2(1.0);
uniform float has_breaks = 0.0;
uniform sampler2D lamp_map : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float has_lamps = 0.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec2 city_uv;

void vertex() {
	city_uv = UV;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec3 base = texture(ground_map, city_uv).rgb;
	float lum = dot(base, vec3(0.30, 0.50, 0.20));
	vec2 metres = city_uv * map_span + map_origin;
	float grain = value_noise(metres * 3.4) * 0.65 + value_noise(metres * 11.0) * 0.35;
	float wear = value_noise(metres * 0.55);
	if (lum > 0.22) {
		base *= 0.88 + 0.18 * grain;
		base = mix(base, base * vec3(0.92, 0.90, 0.86), wear * 0.16);
	} else {
		base *= 0.94 + 0.08 * value_noise(metres * 6.0);
	}
	if (has_breaks > 0.5 && break_span.x > 0.5) {
		vec2 buv = (metres - break_origin) / break_span;
		float hole = 0.0;
		if (buv.x >= 0.0 && buv.y >= 0.0 && buv.x <= 1.0 && buv.y <= 1.0) {
			hole = texture(break_map, buv).r;
		}
		float jagged = value_noise(metres * 0.72);
		if (hole > 0.55) {
			discard;
		}
		if (hole > 0.18) {
			vec3 dirt = vec3(0.22, 0.16, 0.12);
			base = mix(dirt, dirt * (0.72 + 0.36 * jagged), hole);
		}
	}
	vec3 lamp = vec3(0.0);
	if (has_lamps > 0.5) {
		lamp = texture(lamp_map, city_uv).rgb;
	}
	float pool = clamp(dot(lamp, vec3(0.34, 0.50, 0.16)), 0.0, 1.0);
	ALBEDO = base * mix(1.0, mix(0.26, 0.62, pool), night);
	ROUGHNESS = 0.92;
	METALLIC = 0.03;
	SPECULAR = 0.16;
	// Mobile only applies a handful of OmniLights to this city-wide mesh, and
	// the pooled lights jump between posts. Baked pools stay on the painted
	// pad even when no real light is nearby.
	EMISSION = lamp * night * 4.4;
}
