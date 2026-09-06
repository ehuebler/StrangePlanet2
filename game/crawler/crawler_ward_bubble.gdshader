shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 shield_color : source_color = vec4(0.82, 0.94, 1.0, 0.08);
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float pop : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - ndv, 1.55);
	float sweep = UV.x * 6.28318 + UV.y * 5.1 + TIME * 1.55;
	float iri = 0.5 + 0.5 * sin(ndv * 11.0 + sweep);
	vec3 sheen = vec3(
		0.62 + 0.38 * sin(iri * 6.28318),
		0.88 + 0.12 * sin(iri * 6.28318 + 2.094),
		0.78 + 0.22 * sin(iri * 6.28318 + 4.189)
	);
	vec3 ice = mix(shield_color.rgb, sheen, 0.42);
	float film = 0.10 + rim * 0.42
		+ 0.03 * (0.5 + 0.5 * sin(TIME * 2.6 + UV.y * 14.0));
	float fade = 1.0 - pop;
	ALBEDO = ice;
	EMISSION = ice * (0.08 + rim * 0.36 + pulse * 0.12);
	ALPHA = clamp(shield_color.a * film * fade * (1.0 + pulse * 0.18), 0.0, 0.16);
}
