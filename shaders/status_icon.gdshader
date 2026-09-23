// Status badges above structures (RENDER): one MultiMesh of camera-facing quads; each
// instance draws one of twelve signed-distance icons in a round badge. Constant size on
// screen. INSTANCE_CUSTOM: r = icon id, g = progress (0..1, icon 9), b = pulse, a = alpha.
// Instance colour (COLOR) = the accent colour of the badge.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform float px_size = 30.0;   // badge diameter in pixels at 1080p
varying vec4 custom;
varying vec4 tint;

void vertex() {
	vec3 center = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float dist = max(-center.z, 0.1);
	float s = px_size / VIEWPORT_SIZE.y * dist * 2.0 / PROJECTION_MATRIX[1][1];
	VERTEX = center + vec3(VERTEX.x, VERTEX.y, 0.0) * s;
	custom = INSTANCE_CUSTOM;
	tint = COLOR;
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	vec2 e0 = b - a, e1 = c - b, e2 = a - c;
	vec2 v0 = p - a, v1 = p - b, v2 = p - c;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}

float icon(int id, vec2 p, float prog) {
	if (id == 0) { // bolt: no power
		return min(sd_tri(p, vec2(0.1, 0.62), vec2(-0.32, -0.05), vec2(0.08, -0.05)), sd_tri(p, vec2(-0.08, 0.05), vec2(0.32, 0.05), vec2(-0.1, -0.62)));
	} else if (id == 1) { // drop: no water
		return min(length(p - vec2(0.0, -0.14)) - 0.3, sd_tri(p, vec2(0.0, 0.58), vec2(-0.27, -0.02), vec2(0.27, -0.02)));
	} else if (id == 2) { // bubbles: no air
		float a = abs(length(p - vec2(-0.1, -0.08)) - 0.3) - 0.07;
		float b = abs(length(p - vec2(0.28, 0.32)) - 0.13) - 0.06;
		return min(a, b);
	} else if (id == 3) { // wrench: broken
		float h = sd_seg(p, vec2(-0.38, -0.38), vec2(0.1, 0.1)) - 0.09;
		float r = abs(length(p - vec2(0.22, 0.22)) - 0.2) - 0.08;
		float cut = sd_box(p - vec2(0.36, 0.36), vec2(0.1, 0.1));
		return min(h, max(r, -cut));
	} else if (id == 4) { // box: output full
		float b = abs(sd_box(p - vec2(0.0, -0.08), vec2(0.4, 0.34))) - 0.07;
		float lid = sd_seg(p, vec2(-0.4, 0.12), vec2(0.4, 0.12)) - 0.06;
		return min(b, lid);
	} else if (id == 5) { // empty deposit: rock outline and a slash
		float m = abs(sd_tri(p, vec2(0.0, 0.45), vec2(-0.5, -0.35), vec2(0.5, -0.35))) - 0.06;
		float s = sd_seg(p, vec2(-0.5, 0.5), vec2(0.5, -0.5)) - 0.07;
		return min(m, s);
	} else if (id == 6) { // hourglass: waiting for materials
		float t1 = sd_tri(p, vec2(-0.35, 0.5), vec2(0.35, 0.5), vec2(0.0, 0.0));
		float t2 = sd_tri(p, vec2(-0.35, -0.5), vec2(0.35, -0.5), vec2(0.0, 0.0));
		return min(abs(t1) - 0.05, t2);
	} else if (id == 7) { // helmet: too far from an airlock
		float h = abs(length(p) - 0.42) - 0.08;
		float v = sd_box(p - vec2(0.05, 0.02), vec2(0.28, 0.14)) - 0.04;
		return min(h, v);
	} else if (id == 8) { // power button: switched off
		float arc = abs(length(p) - 0.38) - 0.08;
		float gap = sd_box(p - vec2(0.0, 0.4), vec2(0.16, 0.3));
		float line = sd_seg(p, vec2(0.0, 0.05), vec2(0.0, 0.55)) - 0.08;
		return min(max(arc, -gap), line);
	} else if (id == 9) { // progress ring: under construction
		float a = atan(p.x, p.y) / 6.28318 + 0.5;
		float ring = abs(length(p) - 0.42) - 0.1;
		return a <= prog ? ring : ring + 0.06 + step(0.0, -ring) * 1.0;
	} else if (id == 10) { // exclamation
		return min(sd_seg(p, vec2(0.0, 0.5), vec2(0.0, -0.1)) - 0.1, length(p - vec2(0.0, -0.42)) - 0.11);
	}
	// 11: cross (remove)
	return min(sd_seg(p, vec2(-0.4, -0.4), vec2(0.4, 0.4)), sd_seg(p, vec2(-0.4, 0.4), vec2(0.4, -0.4))) - 0.1;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * vec2(1.0, -1.0);
	float r = length(p);
	float aa = fwidth(r) * 1.2;
	float disc = 1.0 - smoothstep(0.92 - aa, 0.92 + aa, r);
	float rim = smoothstep(0.78 - aa, 0.78 + aa, r) * disc;
	float pulse = 0.75 + 0.25 * sin(TIME * 4.0) * custom.b;
	float d = icon(int(custom.r + 0.5), p / 0.62, custom.g);
	float ic = 1.0 - smoothstep(-aa * 1.6, aa * 1.6, d * 0.62);
	vec3 bg = vec3(0.043, 0.071, 0.125);
	vec3 col = mix(bg, tint.rgb, rim * pulse);
	col = mix(col, tint.rgb * 1.15 + 0.1, ic);
	ALBEDO = col;
	ALPHA = disc * custom.a * 0.94;
}
