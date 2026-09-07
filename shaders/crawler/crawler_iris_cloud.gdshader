// Iridescent combat cloud: planet-deck film in the volume, a crackling
// spectrum rim on the silhouette. Shared by field spheres and linger puffs.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque,
	shadows_disabled;

#include "res://shaders/crawler/crawler_iris_lib.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.48, 0.84, 1.0, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.55;
uniform float spark : hint_range(0.0, 2.0) = 1.0;
uniform float iris : hint_range(0.0, 2.0) = 1.0;
uniform float edge_width : hint_range(0.04, 0.7) = 0.22;

varying vec3 world_p;
varying vec3 world_n;

void vertex() {
	world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_p);
	float facing = clamp(abs(dot(view, normalize(world_n))), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 2.15);

	float density;
	float ridges;
	vec3 film;
	iris_film(world_p, TIME, tint.rgb, iris, density, ridges, film);

	float billow = smoothstep(0.16, 0.78, density);
	float veins = smoothstep(0.42, 0.88, ridges);
	float rim = smoothstep(1.0 - edge_width, 1.0, fresnel);
	float cracks = smoothstep(0.58, 0.94, ridges) * rim;
	float grain = iris_fbm3(world_p * 5.4 + vec3(TIME * 2.8), 3);
	float flicker = step(0.78, iris_hash13(floor(world_p * 18.0 + TIME * 11.0)));
	flicker *= step(0.48, grain);
	float sparks = spark * (cracks * 0.85 + flicker * rim * 1.55);

	vec3 rim_film = iris_spectrum(fract(density * 7.0 + ridges * 3.2 + TIME * 0.18));
	rim_film = mix(tint.rgb, rim_film, 0.82);
	vec3 color = film * (0.28 + billow * 0.52 + veins * 0.18);
	color += rim_film * (rim * 1.15 + sparks * 1.8);

	float a = alpha * (0.16 + billow * 0.38 + veins * 0.10 + rim * 0.72 + sparks * 0.55);
	ALBEDO = color;
	EMISSION = color * (0.35 + rim * 1.35 + sparks * 2.1);
	ALPHA = clamp(a, 0.0, 0.96);
}
