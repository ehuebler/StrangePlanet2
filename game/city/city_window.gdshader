shader_type spatial;
// Window panes store their night colour in COLOR. Dark placeholders from older
// bakes still fall back to the material glow so houses keep a warm interior
// and towers keep a white office light.
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 fallback_glow : source_color = vec3(1.0, 0.52, 0.16);

void fragment() {
	vec3 tint = COLOR.rgb;
	float lum = dot(tint, vec3(0.22, 0.67, 0.11));
	float sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
	if (lum < 0.32 && sat < 0.08) {
		tint = fallback_glow;
		tint = fallback_glow;
		sat = max(tint.r, max(tint.g, tint.b)) - min(tint.r, min(tint.g, tint.b));
		lum = dot(tint, vec3(0.22, 0.67, 0.11));
	}
	float neon = smoothstep(0.16, 0.40, sat);
	float warm = smoothstep(0.22, 0.55, tint.r - tint.b);
	ALBEDO = tint * mix(0.20, 0.78, night);
	ROUGHNESS = mix(0.22, 0.10, neon);
	METALLIC = mix(0.26, 0.06, neon);
	SPECULAR = 0.55;
	float lit = step(0.30, lum);
	float energy = mix(0.10, 0.26, neon) + night * lit * mix(mix(5.6, 8.4, warm), 7.2, neon);
	EMISSION = tint * energy;
}
