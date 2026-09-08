shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 tint : source_color = vec4(0.18, 1.0, 0.22, 1.0);
uniform float phase : hint_range(0.0, 10000.0) = 0.0;
uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bubble(vec2 uv, vec2 center, float radius) {
	vec2 delta = (uv - center) * vec2(1.0, 2.35);
	float d = length(delta);
	float body = smoothstep(radius, radius * 0.42, d);
	vec2 shine_at = center + vec2(-radius * 0.18, -radius * 0.16);
	float shine = smoothstep(radius * 0.28, 0.0, length((uv - shine_at) * vec2(1.0, 2.1)));
	return body * (0.72 + shine * 0.55);
}

void fragment() {
	if (UV.x > fill + 0.002) {
		discard;
	}

	vec2 uv = UV;
	float slime = 0.42 + 0.22 * sin(uv.x * 18.0 - phase * 3.4 + sin(uv.y * 9.0 + phase * 1.6));
	slime += 0.16 * sin(uv.x * 31.0 + phase * 2.1);
	float meniscus = smoothstep(0.08, 0.62, uv.y + 0.14 * sin(uv.x * 14.0 - phase * 2.8));
	float goop = slime * (0.55 + meniscus * 0.55);

	for (int i = 0; i < 7; i++) {
		float id = float(i);
		float seed = hash(vec2(id * 3.7, 2.1));
		float along = fract(seed + phase * (0.11 + seed * 0.08) + id * 0.137);
		if (along > fill) {
			continue;
		}
		float rise = fract(seed * 5.3 + phase * (0.28 + seed * 0.18));
		float radius = 0.18 + 0.16 * hash(vec2(id, 9.2));
		float pop = smoothstep(0.92, 0.70, rise);
		goop += bubble(uv, vec2(along, rise), radius) * pop;
	}

	float lip = smoothstep(fill, fill - 0.018, uv.x);
	float edge = 1.0 - smoothstep(0.0, 0.22, uv.y) * 0.25;
	float cover = clamp(goop, 0.0, 1.35);
	vec3 color = mix(tint.rgb * 0.28, tint.rgb, cover);
	color += vec3(0.55, 1.0, 0.42) * smoothstep(0.78, 1.2, cover) * 0.55;
	float alpha = strength * (0.34 + cover * 0.52) * lip * edge;
	COLOR = vec4(color, alpha);
}
