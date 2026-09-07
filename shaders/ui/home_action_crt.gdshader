shader_type canvas_item;
render_mode unshaded, blend_mix;

// CRT type over a SubViewport raster of a Label/Button. Do not put this
// material on a Control that samples the font atlas — TEXTURE must be the
// rastered glyphs or each letter becomes a solid brick.
//
// Source RGB is kept so HUD ink, menu green, and warning red all survive.
// `glitch` is the tear / cell-shift / snow. HUD sets it to 0; menus keep 1.
// Chromatic aberration and scanlines stay on either way.

uniform vec4 red_tint : source_color = vec4(0.937, 0.082, 0.122, 1.0);
uniform float hover : hint_range(0.0, 1.0) = 0.0;
uniform float destructive : hint_range(0.0, 1.0) = 0.0;
uniform float disabled : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 1.0;


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


void fragment() {
	vec2 uv = UV;
	vec2 centered = uv * 2.0 - 1.0;
	centered *= 1.0 + dot(centered, centered) * mix(0.003, 0.008, glitch);
	uv = centered * 0.5 + 0.5;

	vec2 px = TEXTURE_PIXEL_SIZE;
	float live = 1.0 - disabled;
	float amp = live * glitch * (1.0 + hover * 0.55);

	float tear_tick = floor(TIME * 4.8);
	float jit_tick = floor(TIME * 18.0);
	float row = floor((uv.y / max(px.y, 0.0001)) * 0.5);
	float n_tear = hash21(vec2(row, tear_tick));
	float n_jit = hash21(vec2(row, jit_tick));
	float micro = (n_jit - 0.5) * 1.4 * px.x;
	float tearing = step(0.88, n_tear);
	float tear = tearing * (hash21(vec2(row, tear_tick + 1.7)) * 2.0 - 1.0) * 7.5 * px.x;

	vec2 cell = vec2(floor(uv.x * 13.0), floor(uv.y * 6.0));
	float n_cell = hash21(cell + vec2(tear_tick * 0.41, 2.1));
	float cell_hit = step(0.93, n_cell);
	float cell_x = cell_hit * (hash21(cell + 3.3) * 2.0 - 1.0) * 6.5 * px.x;
	float cell_y = step(0.96, n_cell) * (hash21(cell + 4.4) - 0.5) * 2.4 * px.y;

	uv.x += (micro + tear + cell_x) * amp;
	uv.y += cell_y * amp;

	float ca = (2.6 + glitch * 1.6 + hover * 2.4 + tearing * glitch * 1.8)
		* px.x * live;
	ca *= 1.0 + 0.28 * sin(TIME * 7.1 + row * 0.35) * mix(0.35, 1.0, glitch);
	vec4 red_ink = texture(TEXTURE, uv + vec2(ca, 0.0));
	vec4 mid_ink = texture(TEXTURE, uv);
	vec4 blu_ink = texture(TEXTURE, uv - vec2(ca * 0.92, ca * 0.18));
	float alpha = max(mid_ink.a, max(red_ink.a, blu_ink.a));
	vec3 rgb = vec3(0.0);
	if (alpha >= 0.01) {
		rgb = vec3(red_ink.r, mid_ink.g, blu_ink.b);
		rgb = mix(mid_ink.rgb, rgb, 0.72 + glitch * 0.20);
		float luma = dot(mid_ink.rgb, vec3(0.30, 0.59, 0.11));
		float lift = mix(0.90, 1.10, 1.0 - uv.y);
		rgb *= lift;
		vec3 red_ramp = mix(red_tint.rgb * 0.62, red_tint.rgb * 1.12, 1.0 - uv.y);
		rgb = mix(rgb, red_ramp * max(luma, alpha), destructive);
		float scan = mix(0.94, 0.90, glitch)
			+ mix(0.06, 0.10, glitch)
			* sin(uv.y / max(px.y, 0.0001) * 3.14159 + TIME * 7.0);
		rgb *= scan;
		float snow = hash21(uv * vec2(210.0, 380.0) + vec2(TIME * 17.0, jit_tick));
		rgb += (snow - 0.5) * 0.07 * alpha * glitch;
		rgb *= mix(1.0, 1.12, hover);
		rgb *= mix(1.0, 0.42, disabled);
	}
	COLOR = vec4(rgb, alpha);
}
