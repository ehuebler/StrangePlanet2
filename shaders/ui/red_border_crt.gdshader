shader_type canvas_item;
render_mode unshaded, blend_mix;

// Procedural CRT rim for RedGlowPanel. TEXTURE is a white quad covering
// the pane plus glow pad; UV is that padded rect, not the font atlas.
// Tear / cell-shift / snow match home_action_crt. Fill stays optional so
// a stable pane can sit under a crawling red edge.

uniform vec4 fill_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform vec4 border_color : source_color = vec4(1.0, 0.055, 0.11, 0.95);
uniform float border_width = 1.75;
uniform float glow_intensity = 1.0;
uniform float glow_spread = 10.0;
uniform float glow_layers = 4.0;
uniform float draw_fill : hint_range(0.0, 1.0) = 0.0;
uniform float glitch : hint_range(0.0, 1.0) = 1.0;
uniform float chromatic : hint_range(0.0, 1.0) = 1.0;
uniform float clock = 0.0;
uniform vec2 panel_size = vec2(100.0, 100.0);
uniform float pad = 10.0;


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float box_sd(vec2 p, vec2 size) {
	vec2 half_size = max(size * 0.5, vec2(0.01));
	vec2 d = abs(p - half_size) - half_size;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}


float stroke(float sd, float half_w, float px) {
	return 1.0 - smoothstep(half_w, half_w + px, abs(sd));
}


vec4 ink_at(vec2 uv, float px) {
	vec2 padded = panel_size + vec2(pad * 2.0);
	vec2 local = uv * padded - vec2(pad);
	float shortest = min(panel_size.x, panel_size.y);
	float inset = min(max(border_width * 0.5, 0.5), max(shortest * 0.5 - 0.01, 0.0));
	vec2 inner = panel_size - vec2(inset * 2.0);
	float sd = box_sd(local - vec2(inset), inner);

	float fill_a = 0.0;
	if (draw_fill > 0.5 && sd < 0.0) {
		fill_a = fill_color.a * (1.0 - smoothstep(-px, 0.0, sd));
	}

	float glow_a = 0.0;
	if (glow_intensity > 0.0 && glow_spread > 0.0 && border_color.a > 0.0) {
		float layers = max(glow_layers, 1.0);
		for (int i = 4; i >= 1; i--) {
			if (float(i) > layers) {
				continue;
			}
			float fraction = float(i) / layers;
			float half_w = (border_width + glow_spread * 2.0 * fraction) * 0.5;
			float falloff = 1.0 - fraction * 0.72;
			glow_a = max(glow_a, stroke(sd, half_w, px)
				* border_color.a * glow_intensity * 0.11 * falloff * falloff);
		}
	}

	float rim_a = 0.0;
	if (border_width > 0.0 && border_color.a > 0.0) {
		rim_a = stroke(sd, border_width * 0.5, px) * border_color.a;
	}

	float alpha = max(fill_a, max(glow_a, rim_a));
	vec3 rgb = fill_color.rgb;
	if (alpha >= 0.01) {
		float rim_mix = clamp((glow_a + rim_a) / max(alpha, 0.001), 0.0, 1.0);
		rgb = mix(fill_color.rgb, border_color.rgb, rim_mix);
	}
	return vec4(rgb, alpha);
}


void fragment() {
	vec2 uv = UV;
	vec2 centered = uv * 2.0 - 1.0;
	centered *= 1.0 + dot(centered, centered) * mix(0.003, 0.008, glitch);
	uv = centered * 0.5 + 0.5;

	vec2 padded = panel_size + vec2(pad * 2.0);
	vec2 px2 = 1.0 / max(padded, vec2(1.0));
	float px = max(px2.x, px2.y) * 1.35;
	float amp = glitch;

	float tear_tick = floor(clock * 4.8);
	float jit_tick = floor(clock * 18.0);
	float row = floor((uv.y / max(px2.y, 0.0001)) * 0.5);
	float n_tear = hash21(vec2(row, tear_tick));
	float n_jit = hash21(vec2(row, jit_tick));
	float micro = (n_jit - 0.5) * 1.4 * px2.x;
	float tearing = step(0.88, n_tear);
	float tear = tearing * (hash21(vec2(row, tear_tick + 1.7)) * 2.0 - 1.0)
		* 7.5 * px2.x;

	vec2 cell = vec2(floor(uv.x * 13.0), floor(uv.y * 6.0));
	float n_cell = hash21(cell + vec2(tear_tick * 0.41, 2.1));
	float cell_hit = step(0.93, n_cell);
	float cell_x = cell_hit * (hash21(cell + 3.3) * 2.0 - 1.0) * 6.5 * px2.x;
	float cell_y = step(0.96, n_cell) * (hash21(cell + 4.4) - 0.5) * 2.4 * px2.y;

	uv.x += (micro + tear + cell_x) * amp;
	uv.y += cell_y * amp;

	float ca = (2.6 + glitch * 1.6 + tearing * glitch * 1.8)
		* px2.x * chromatic;
	ca *= 1.0 + 0.28 * sin(clock * 7.1 + row * 0.35) * mix(0.35, 1.0, glitch);

	vec4 mid_ink = ink_at(uv, px);
	vec4 red_ink = mid_ink;
	vec4 blu_ink = mid_ink;
	if (ca > 0.0001) {
		red_ink = ink_at(uv + vec2(ca, 0.0), px);
		blu_ink = ink_at(uv - vec2(ca * 0.92, ca * 0.18), px);
	}
	float alpha = max(mid_ink.a, max(red_ink.a, blu_ink.a));
	vec3 rgb = vec3(0.0);
	if (alpha >= 0.01) {
		rgb = vec3(red_ink.r, mid_ink.g, blu_ink.b);
		rgb = mix(mid_ink.rgb, rgb, 0.72 + glitch * 0.20);
		float lift = mix(0.90, 1.10, 1.0 - uv.y);
		rgb *= lift;
		float scan = mix(0.94, 0.90, glitch)
			+ mix(0.06, 0.10, glitch)
			* sin(uv.y / max(px2.y, 0.0001) * 3.14159 + clock * 7.0);
		rgb *= scan;
		float snow = hash21(uv * vec2(210.0, 380.0) + vec2(clock * 17.0, jit_tick));
		rgb += (snow - 0.5) * 0.07 * alpha * glitch;
	}
	COLOR = vec4(rgb, alpha);
}
