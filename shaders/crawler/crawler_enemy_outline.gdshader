shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.94, 0.08, 0.12, 1.0);
uniform float outline_width : hint_range(0.01, 0.24) = 0.045;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 1.65;
}
