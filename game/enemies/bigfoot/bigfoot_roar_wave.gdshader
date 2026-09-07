shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 wave_color = vec3(0.95, 0.55, 0.12);

void fragment() {
	// A view-dependent rim reads as a complete spherical pressure front from
	// every angle. The former local-Y test drew only an equatorial band.
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float shell = smoothstep(0.35, 0.95, edge);
	if (shell < 0.01) {
		discard;
	}
	float alpha = shell * (0.12 + strength * 0.28);
	ALBEDO = wave_color;
	ALPHA = alpha;
}
