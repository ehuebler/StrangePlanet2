shader_type spatial;
// Pavement is unshaded vertex colour, so it stays bright in any light. Hulls
// used to be full PBR metal against a sky cubemap that is not rebuilt while
// walking — shade sides and chrome packs went black. Wrap the sun and add a
// pavement/sky bounce so the paint still reads.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.05;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float paving_wall : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D paint_tex : source_color, hint_default_white;
uniform float use_paint : hint_range(0.0, 1.0) = 0.0;
instance uniform float ruin = 0.0;

varying vec3 world_pos;
varying vec3 world_n;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = mat3(MODEL_MATRIX) * NORMAL;
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

vec2 wall_uv(vec3 pos, vec3 nrm) {
	vec3 up = normalize(pos);
	vec3 n = normalize(nrm);
	vec3 tangent = cross(up, n);
	if (length(tangent) < 0.12) {
		tangent = cross(up, vec3(1.0, 0.0, 0.0));
	}
	tangent = normalize(tangent);
	return vec2(dot(pos, tangent), dot(pos, up));
}

void fragment() {
	int style = int(round(COLOR.a * 20.0));
	vec3 base = COLOR.rgb;
	vec3 n = normalize(world_n);
	vec3 up = normalize(world_pos);
	float roof = abs(dot(n, up));
	vec2 uv = wall_uv(world_pos, n);
	vec4 paint = texture(paint_tex, UV);
	vec3 albedo = base;
	float rough = roughness_val;
	float metal = metallic_val;
	if (paving_wall > 0.5) {
		float grain = value_noise(uv * 0.16) * 0.62 + value_noise(uv * 0.55) * 0.38;
		albedo = mix(vec3(0.16, 0.16, 0.18), vec3(0.30, 0.30, 0.32), grain);
		rough = 0.94;
		metal = 0.02;
	} else if (style == 18) {
		albedo = base;
		rough = 0.18;
		metal = 0.10;
	} else if (use_paint > 0.5) {
		albedo = paint.rgb * mix(base, vec3(1.0), 0.35);
	} else if (style == 19 || roof > 0.72) {
		albedo *= 0.88 + 0.14 * value_noise(uv * 0.28);
		rough = mix(0.48, 0.62, float(style == 19));
		metal = mix(metal, 0.08, 0.45);
	} else if (style == 0) {
		vec2 brick = uv;
		brick.x += step(0.5, fract(uv.y * 0.78)) * 0.36;
		vec2 cell = vec2(0.78, 0.34);
		vec2 g = fract(brick / cell);
		if (g.x < 0.11 || g.y < 0.18) {
			albedo = mix(base * 0.62, vec3(0.52, 0.46, 0.40), 0.35);
		} else {
			albedo = base * (0.88 + 0.22 * hash21(floor(brick / cell)));
		}
	} else if (style == 1) {
		float grain = value_noise(vec2(uv.x * 0.18, uv.y * 2.2));
		float plank = step(0.08, fract(uv.x * 0.42));
		albedo = mix(base * 0.72, base * 1.18, grain) * mix(0.78, 1.0, plank);
		rough = 0.86;
		metal = 0.02;
	} else if (style == 2) {
		vec2 ashlar = uv;
		ashlar.x += step(0.5, fract(uv.y * 0.48)) * 0.52;
		vec2 cell = vec2(1.15, 0.52);
		vec2 g = fract(ashlar / cell);
		if (g.x < 0.10 || g.y < 0.16) {
			albedo = mix(base * 0.52, vec3(0.40, 0.38, 0.34), 0.45);
		} else {
			albedo = base * (0.84 + 0.22 * hash21(floor(ashlar / cell)));
		}
		rough = 0.88;
		metal = 0.03;
	} else if (style == 3 || style == 4 || style == 5) {
		float blot = value_noise(uv * 0.11) * 0.62 + value_noise(uv * 0.40) * 0.38;
		albedo = mix(base * 0.78, base * 1.18, blot);
	} else if (style == 10) {
		float fin = step(0.86, fract(uv.x * 0.16));
		float band = step(0.90, fract(uv.y * 0.12));
		albedo = mix(base * 1.05, base * 1.28, value_noise(uv * 0.07));
		albedo = mix(albedo, albedo * 0.78, max(fin, band) * 0.45);
		metal = 0.12;
		rough = 0.38;
	} else if (style == 11) {
		float streak = value_noise(vec2(uv.x * 0.42, uv.y * 0.035));
		vec3 chrome = vec3(0.82, 0.84, 0.88);
		albedo = mix(chrome, base, 0.38) * (0.94 + 0.16 * streak);
		metal = 0.28;
		rough = 0.22;
	} else if (style == 12) {
		float blot = value_noise(uv * 0.08) * 0.7 + value_noise(uv * 0.28) * 0.3;
		vec3 copper = vec3(0.86, 0.50, 0.28);
		vec3 verde = vec3(0.34, 0.64, 0.50);
		albedo = mix(mix(verde, copper, blot * blot), base, 0.32);
		metal = 0.16;
		rough = 0.42;
	} else if (style == 13) {
		float panel = step(0.05, fract(uv.x * 0.24)) * step(0.06, fract(uv.y * 0.18));
		albedo = mix(base * 0.88, base * 1.16, panel);
		albedo *= 0.96 + 0.10 * value_noise(uv * 0.10);
		metal = 0.06;
		rough = 0.58;
	} else {
		vec2 g = fract(uv / vec2(2.2, 3.15));
		if (g.x < 0.045 || g.y < 0.04) {
			albedo *= 0.88;
		}
		albedo *= 0.96 + 0.10 * value_noise(uv * 0.07);
	}
	if (ruin > 0.01) {
		float vein = value_noise(uv * 0.62);
		float crack = step(0.78, value_noise(uv * 1.55))
			* step(0.42, abs(sin(uv.x * 1.8 + uv.y * 0.35)));
		float soot = mix(0.45, 0.82, vein);
		albedo = mix(albedo, albedo * vec3(0.32, 0.26, 0.22), ruin * soot);
		albedo = mix(albedo, vec3(0.12, 0.10, 0.09), crack * ruin);
		rough = mix(rough, 0.94, ruin);
		metal *= 1.0 - ruin * 0.75;
	}
	// Paint atlases used to colour roofs the same as the walls. Keep the
	// hue and pull it darker and greyer so a pink house has a dusty pink top.
	if (style != 18 && paving_wall < 0.5 && roof > 0.58) {
		float luma = dot(albedo, vec3(0.22, 0.67, 0.11));
		albedo = mix(albedo, vec3(luma), 0.24);
		albedo *= mix(0.68, 0.76, value_noise(uv * 0.22));
		rough = max(rough, 0.70);
		metal *= 0.40;
	}
	float sky = clamp(0.5 + 0.5 * dot(n, up), 0.0, 1.0);
	// Night terrain is a dark cubemap; keep hulls in that exposure. Neon
	// trim (style 18) and window meshes still carry the city lights.
	float dim = mix(1.0, mix(0.16, 0.32, float(style == 18)), night);
	ALBEDO = albedo * dim;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.22, 0.45, metal);
	RIM = mix(0.28, 0.08, night);
	RIM_TINT = 0.42;
	vec3 glow = albedo * mix(0.12, 0.0, night) * mix(0.85, 1.2, sky);
	if (style == 18) {
		glow = base * mix(0.35, 6.8, night);
	}
	if (use_paint > 0.5) {
		glow += paint.rgb * paint.a * mix(0.06, 0.0, night);
	}
	EMISSION = glow;
}
