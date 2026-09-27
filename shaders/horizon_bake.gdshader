// Horizon bake (RENDER, V4 1.1). Drawn ONCE into a SubViewport by terrain_v4.gd.
// Same layout as SIM's sim.world.horizon (world_v4.gd _horizon): the sun bearings of the day,
// bearing = PI * b / (bins - 1), direction (-cos, sin) rotated by az_off; horizon elevation in
// degrees seen from 1.5 m above the ground. Finer than SIM's (8 m cells, 36 steps to 900 m), so
// shadow edges on a crater floor are a few metres wide; SIM's own map drives the solar output.
// Output atlas: 4 tiles of side x side; tile t, channel c = bin 4t + c, stored as (deg + 10) / 100.
// Bin `bins` = mean horizon angle (>= 0) over 16 azimuths / 90 deg (how much sky is hidden).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D hmap : filter_linear, repeat_disable;
uniform float hn = 641.0;        // height samples per side
uniform float hstep = 4.0;       // metres per sample
uniform float side = 321.0;      // cells per side
uniform float cell = 8.0;        // metres per cell
uniform float bins = 13.0;
uniform float az_off = -0.698132;

float h_at(vec2 p) {
	return texture(hmap, (p / hstep + 0.5) / hn).r;
}

float horizon_deg(vec2 p, vec2 d, float h0) {
	float best = -10.0;
	float lim = (hn - 1.0) * hstep;
	for (int k = 0; k < 36; k++) {
		float s = 4.0 * pow(225.0, float(k) / 35.0);
		vec2 q = p + d * s;
		if (q.x < 0.0 || q.y < 0.0 || q.x > lim || q.y > lim) {
			break;
		}
		best = max(best, degrees(atan((h_at(q) - h0) / s)));
	}
	return best;
}

void fragment() {
	vec2 pix = floor(UV * vec2(side * 4.0, side));
	float tile = floor(pix.x / side);
	vec2 c = vec2(pix.x - tile * side, pix.y);
	vec2 p = c * cell;
	float h0 = h_at(p) + 1.5;
	vec4 outv = vec4(0.0);
	for (int k = 0; k < 4; k++) {
		float b = tile * 4.0 + float(k);
		float v = 0.0;
		if (b < bins - 0.5) {
			float ang = 3.14159265 * b / (bins - 1.0);
			vec2 d0 = vec2(-cos(ang), sin(ang));
			vec2 d = vec2(d0.x * cos(az_off) - d0.y * sin(az_off), d0.x * sin(az_off) + d0.y * cos(az_off));
			v = clamp((horizon_deg(p, d, h0) + 10.0) / 100.0, 0.0, 1.0);
		} else if (b < bins + 0.5) {
			float sum = 0.0;
			for (int a = 0; a < 16; a++) {
				float az = 6.2831853 * float(a) / 16.0;
				sum += max(horizon_deg(p, vec2(cos(az), sin(az)), h0), 0.0);
			}
			v = clamp(sum / 16.0 / 90.0, 0.0, 1.0);
		}
		if (k == 0) { outv.r = v; } else if (k == 1) { outv.g = v; } else if (k == 2) { outv.b = v; } else { outv.a = v; }
	}
	COLOR = outv;
}
