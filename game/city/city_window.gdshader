shader_type spatial;
// Window panes store their night colour in COLOR. Near-white office panes from
// older bakes are remapped to a hashed neon so downtown does not read as a
// wall of white. Dark placeholders still fall back to the material glow.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fallback_glow : source_color = vec3(1.0, 0.52, 0.16);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 hashed_neon(vec3 at) {
	float h = fract(sin(dot(floor(at * 0.35), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	if (h < 0.16) {
		return vec3(1.00, 0.18, 0.72);
	}
	if (h < 0.32) {
		return vec3(0.18, 0.92, 1.00);
	}
	if (h < 0.48) {
		return vec3(0.68, 0.22, 1.00);
	}
	if (h < 0.64) {
		return vec3(0.32, 1.00, 0.42);
	}
	if (h < 0.80) {
		return vec3(1.00, 0.52, 0.10);
	}
	return vec3(1.00, 0.78, 0.16);
}

void fragment() {
	vec3 tint = COLOR.rgb;
	float lum = dot(tint, vec3(0.22, 0.67, 0.11));
	float sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
	if (lum > 0.58 && sat < 0.22) {
		tint = hashed_neon(world_pos);
		sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
		lum = dot(tint, vec3(0.22, 0.67, 0.11));
	} else if (lum < 0.32 && sat < 0.08) {
		// Empty panes stay dark glass by day. Night is when they take the
		// fallback colour and actually glow.
		tint = mix(vec3(0.10, 0.11, 0.13), fallback_glow, night);
		sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
		lum = dot(tint, vec3(0.22, 0.67, 0.11));
	}
	float neon = smoothstep(0.16, 0.40, sat);
	float warm = smoothstep(0.22, 0.55, tint.r - tint.b);
	// Day: tinted glass lit by the sun. Night: dim albedo, colour from emission.
	ALBEDO = tint * mix(0.58, 0.10, night);
	ROUGHNESS = mix(0.22, 0.10, neon);
	METALLIC = mix(0.26, 0.06, neon);
	SPECULAR = 0.55;
	float lit = step(0.30, lum);
	float energy = mix(0.0, 0.03, neon) * (1.0 - night)
		+ night * lit * mix(mix(2.2, 3.1, warm), 2.7, neon);
	EMISSION = tint * energy;
}
