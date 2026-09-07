// Compact film helpers for crawler clouds. Same hash, fBm, ridges, and
// cosine spectrum the planet deck uses, without pulling the rest of
// vivid_lib into a combat material.

float iris_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float iris_noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n000 = iris_hash13(cell);
	float n100 = iris_hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = iris_hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = iris_hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = iris_hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = iris_hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = iris_hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = iris_hash13(cell + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float iris_fbm3(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += iris_noise3(p) * amplitude;
		total += amplitude;
		p = p.yzx * 2.02 + vec3(17.3, 5.7, 31.1);
		amplitude *= 0.5;
	}
	return sum / max(total, 0.0001);
}

float iris_ridge3(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	for (int i = 0; i < octaves; i++) {
		float value = 1.0 - abs(iris_noise3(p) * 2.0 - 1.0);
		sum += value * value * amplitude;
		total += amplitude;
		p = p * 2.11 + vec3(9.2, 23.7, 3.5);
		amplitude *= 0.5;
	}
	return sum / max(total, 0.0001);
}

vec3 iris_spectrum(float t) {
	return 0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67)));
}

void iris_film(vec3 world_p, float time, vec3 tint, float iris,
		out float density, out float ridges, out vec3 film) {
	vec3 drift = vec3(time * 0.11, time * 0.07, -time * 0.05);
	vec3 warped = world_p * 0.38 + drift;
	warped += (vec3(
		iris_noise3(warped + 4.7),
		iris_noise3(warped.yzx - 9.1),
		iris_noise3(warped.zxy + 17.3)) - 0.5) * 0.55;
	density = iris_fbm3(warped, 5);
	ridges = iris_ridge3(warped * 1.55 + vec3(5.0), 4);
	float swirl = density * 0.62 + ridges * 0.38;
	float bands = fract(swirl * 11.0 + time * 0.03);
	vec3 spectrum = iris_spectrum(bands + swirl * 2.4);
	film = mix(tint, spectrum, clamp(iris * 0.78, 0.0, 0.92));
	film = mix(film, tint * 1.12, 0.18);
}
