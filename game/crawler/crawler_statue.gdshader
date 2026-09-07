shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D albedo : source_color, filter_linear_mipmap;
uniform float fade = 1.0;

void fragment() {
	vec4 colour = texture(albedo, UV);
	if (colour.a < 0.08) {
		discard;
	}
	ALBEDO = colour.rgb;
	ALPHA = colour.a * fade;
}
