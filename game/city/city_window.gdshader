shader_type spatial;
// Window panes store their night colour in COLOR. Near-white office panes from
// older bakes are remapped to a hashed neon so downtown does not read as a
// wall of white. Dark placeholders still fall back to the material glow.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fallback_glow : source_color = vec3(1.0, 0.52, 0.16);
uniform float warm_only : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 saturate_peak(vec3 c) {
	float peak = max(c.r, max(c.g, c.b));
	if (peak < 0.08) {
		return c;
	}
	return c / peak;
}

vec3 hashed_warm(vec3 at) {
	float h = fract(sin(dot(floor(at * 0.41), vec3(19.19, 73.13, 11.47))) * 43758.5453);
	if (h < 0.34) {
		return vec3(1.00, 0.38, 0.05);
	}
	if (h < 0.67) {
		return vec3(1.00, 0.48, 0.07);
	}
	return vec3(1.00, 0.28, 0.04);
}

vec3 hashed_neon(vec3 at) {
	float h = fract(sin(dot(floor(at * 0.35), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	if (h < 0.16) {
		return vec3(1.00, 0.04, 0.72);
	}
	if (h < 0.32) {
		return vec3(0.02, 0.95, 1.00);
	}
	if (h < 0.48) {
		return vec3(0.68, 0.02, 1.00);
	}
	if (h < 0.64) {
		return vec3(0.08, 1.00, 0.22);
	}
	if (h < 0.80) {
		return vec3(1.00, 0.38, 0.04);
	}
	return vec3(1.00, 0.72, 0.05);
}

void fragment() {
	vec3 tint = COLOR.rgb;
	float lum = dot(tint, vec3(0.22, 0.67, 0.11));
	float sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
	if (lum > 0.58 && sat < 0.22) {
		tint = mix(hashed_neon(world_pos), hashed_warm(world_pos), warm_only);
		sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
		lum = dot(tint, vec3(0.22, 0.67, 0.11));
	} else if (lum < 0.32 && sat < 0.08) {
		// Empty panes stay dark glass by day. Night is when they take the
		// fallback colour and actually glow.
		tint = mix(vec3(0.10, 0.11, 0.13), fallback_glow, night);
		sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
		lum = dot(tint, vec3(0.22, 0.67, 0.11));
	}
	if (night > 0.01 && sat > 0.10) {
		if (warm_only > 0.5) {
			tint = mix(vec3(1.00, 0.42, 0.06), hashed_warm(world_pos), 0.28);
		}
		tint = saturate_peak(tint);
		sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
	}
	float neon = smoothstep(0.16, 0.40, sat);
	float warm = smoothstep(0.22, 0.55, tint.r - tint.b);
	// Day: tinted glass lit by the sun. Night: dim albedo, colour from emission.
	ALBEDO = tint * mix(0.58, 0.08, night);
	ROUGHNESS = mix(0.22, 0.10, neon);
	METALLIC = mix(0.26, 0.06, neon);
	SPECULAR = 0.55;
	float lit = step(0.30, lum);
	float energy = mix(0.0, 0.03, neon) * (1.0 - night)
		+ night * lit * mix(mix(3.4, 3.8, warm), 5.6, neon);
	EMISSION = tint * energy;
}
