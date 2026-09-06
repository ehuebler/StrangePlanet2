shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform vec4 albedo : source_color = vec4(0.12, 0.05, 0.06, 1.0);
uniform vec4 rim_color : source_color = vec4(0.94, 0.08, 0.14, 1.0);
uniform float rim_power : hint_range(0.4, 6.0) = 2.2;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.85;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D paint : source_color, hint_default_white;
uniform float paint_mix : hint_range(0.0, 1.0) = 0.0;
uniform float vertex_mix : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec4 painted = texture(paint, UV);
	vec3 base = mix(albedo.rgb, painted.rgb, paint_mix);
	base = mix(base, COLOR.rgb, vertex_mix * paint_mix);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
		rim_power);
	vec3 ink = mix(base, vec3(1.0, 0.04, 0.06), flash);
	vec3 rim = rim_color.rgb * fresnel * rim_strength;
	ALBEDO = ink + rim;
	EMISSION = rim * (0.55 + flash * 3.4)
		+ painted.rgb * painted.a * paint_mix * 0.45 * (1.0 - flash)
		+ vec3(1.0, 0.06, 0.07) * flash * 4.2;
}
