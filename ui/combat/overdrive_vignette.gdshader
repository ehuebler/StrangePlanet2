shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform float pulse : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 from_edge = min(UV, vec2(1.0) - UV);
	float dist = min(from_edge.x, from_edge.y);
	float band = 1.0 - smoothstep(0.0, 0.22, dist);
	float alpha = band * mix(0.10, 0.30, pulse);
	COLOR = vec4(tint.rgb, tint.a * alpha);
}
