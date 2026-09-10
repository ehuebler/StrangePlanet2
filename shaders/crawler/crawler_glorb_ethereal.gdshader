shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Living violet-turquoise ink from the Ethereal Glorb blend. Pigment
// coordinates ride in UV / UV2 so they stick to the skin as it deforms.
// FLOW PHASE is a 4-second 2-pi loop, matching the 96-frame / 24 fps driver.

uniform vec4 rim_color : source_color = vec4(0.94, 0.08, 0.14, 1.0);
uniform float rim_power : hint_range(0.4, 6.0) = 2.15;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;

const float CYCLE_SECONDS = 4.0;
const float GLOW_STRENGTH = 1.15;
const float EYE_GLOW = 5.0;
const vec3 EYE_COLOR = vec3(1.0, 0.001, 0.003);
const vec3 ROTATE_CENTER = vec3(0.0, 0.0, 0.5);
const vec3 ROTATE_AXIS = vec3(0.2, 0.3, 1.0);

float eth_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float eth_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = eth_hash(cell);
	float n100 = eth_hash(cell + vec3(1.0, 0.0, 0.0));
	float n010 = eth_hash(cell + vec3(0.0, 1.0, 0.0));
	float n110 = eth_hash(cell + vec3(1.0, 0.0, 0.0));
	float n001 = eth_hash(cell + vec3(0.0, 0.0, 1.0));
	float n101 = eth_hash(cell + vec3(1.0, 0.0, 1.0));
	float n011 = eth_hash(cell + vec3(0.0, 1.0, 1.0));
	float n111 = eth_hash(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float eth_fbm(vec3 p, float w, int octaves, float roughness) {
	float sum = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	vec3 q = p + vec3(w * 0.37, w * 0.19, -w * 0.28);
	for (int i = 0; i < octaves; i++) {
		sum += eth_noise(q) * amplitude;
		total += amplitude;
		q = q.yzx * 2.0 + vec3(17.3, 5.7, 31.1);
		amplitude *= roughness;
	}
	return sum / max(total, 0.0001);
}

vec3 eth_fbm3(vec3 p, float w, int octaves, float roughness) {
	return vec3(
		eth_fbm(p, w, octaves, roughness),
		eth_fbm(p.yzx + 17.0, w, octaves, roughness),
		eth_fbm(p.zxy - 9.0, w, octaves, roughness));
}

vec3 rotate_axis_angle(vec3 v, vec3 center, vec3 axis, float angle) {
	vec3 p = v - center;
	axis = normalize(axis);
	float s = sin(angle);
	float c = cos(angle);
	return center + p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

float ease01(float x) {
	x = clamp(x, 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

float ease_span(float t, float a, float b) {
	return ease01((t - a) / max(b - a, 0.0001));
}

vec3 ethereal_palette(float t) {
	const vec3 c0 = vec3(0.25, 0.001, 0.75);
	const vec3 c1 = vec3(0.43, 0.004, 0.95);
	const vec3 c2 = vec3(0.07, 0.18, 0.72);
	const vec3 c3 = vec3(0.001, 0.82, 0.60);
	const vec3 c4 = vec3(0.015, 0.95, 0.80);
	if (t <= 0.26) {
		return c0;
	}
	if (t <= 0.43) {
		return mix(c0, c1, ease_span(t, 0.26, 0.43));
	}
	if (t <= 0.54) {
		return mix(c1, c2, ease_span(t, 0.43, 0.54));
	}
	if (t <= 0.61) {
		return mix(c2, c3, ease_span(t, 0.54, 0.61));
	}
	if (t <= 0.76) {
		return mix(c3, c4, ease_span(t, 0.61, 0.76));
	}
	return c4;
}

float voronoi_f1(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	float best = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 hashed = vec3(
					eth_hash(cell + offset),
					eth_hash(cell + offset + 19.7),
					eth_hash(cell + offset - 11.3));
				vec3 delta = offset + hashed - f;
				best = min(best, length(delta));
			}
		}
	}
	return best;
}

void fragment() {
	float phase = TIME * TAU / CYCLE_SECONDS;
	float ink_w = sin(phase);
	float twinkle_w = cos(phase);
	vec3 pigment = vec3(UV, UV2.x);
	// Authored eye masks were overwritten by a second UV unwrap, which
	// painted the whole body EYE_COLOR. Keep the living ink on the skin.
	float eyes = 0.0;
	vec3 rotated = rotate_axis_angle(pigment, ROTATE_CENTER, ROTATE_AXIS, phase);
	vec3 warped = rotated + eth_fbm3(rotated * 2.4, ink_w, 3, 0.67) * 0.45;
	vec3 paint = ethereal_palette(eth_fbm(warped * 3.2, twinkle_w, 3, 0.67));
	float pools = ease_span(eth_fbm(warped * 3.8, ink_w, 4, 0.67), 0.48, 0.60);
	float rings = 0.5 + 0.5 * sin(length(warped) * 3.7
		+ eth_fbm(warped * 2.2, ink_w, 3, 0.5) * 10.0);
	float tendrils = ease_span(rings, 0.84, 0.96);
	float ink = max(pools, tendrils);
	float spark_core = 1.0 - ease_span(voronoi_f1(pigment * 78.0), 0.055, 0.115);
	float glitter = ease_span(eth_fbm(pigment * 28.0, twinkle_w, 2, 0.67), 0.40, 0.61);
	float glow = spark_core * glitter * 22.0 + GLOW_STRENGTH;
	vec3 skin = mix(paint * glow, vec3(0.0), ink);
	vec3 body = mix(skin, EYE_COLOR * EYE_GLOW, eyes);
	ALBEDO = mix(body, vec3(1.0, 0.04, 0.06), flash);
	EMISSION = mix(body, vec3(1.0, 0.06, 0.07), flash) * (0.55 + flash * 3.4)
		+ vec3(1.0, 0.06, 0.07) * flash * 4.2;
}
