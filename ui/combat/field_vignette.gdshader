// Interior wash: the same iridescent film as the planet clouds, dyed by
// the field or linger tint, instead of a flat screen color.
shader_type canvas_item;
render_mode unshaded, blend_mix;

#include "res://shaders/crawler/crawler_iris_lib.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.45, 0.82, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float phase : hint_range(0.0, 10000.0) = 0.0;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	float veil = 1.0 - smoothstep(0.08, 1.18, dist);

	vec3 world_p = vec3(UV * 5.2, phase * 0.13);
	float density;
	float ridges;
	vec3 film;
	iris_film(world_p, phase, tint.rgb, 1.05, density, ridges, film);

	float clouds = smoothstep(0.20, 0.82, density * 0.7 + ridges * 0.3);
	float veins = smoothstep(0.48, 0.9, ridges);
	float from_edge = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y));
	float frame = 1.0 - smoothstep(0.0, 0.28, from_edge);
	float cover = clouds * (0.42 + veil * 0.58) + veins * 0.18 + frame * 0.12;
	float a = strength * cover * 0.78;
	COLOR = vec4(film, a);
}
