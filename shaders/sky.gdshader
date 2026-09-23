// Frontier Habitat sky (RENDER). Day gradient, sun disc and glow, warm sunset band,
// dust haze on the horizon, a large pale ringed planet, stars and a faint galaxy band.
// Every colour comes from presentation/fx_sky.gd, which evaluates the time of day once
// per frame on the CPU, so this shader has no branches on time.
shader_type sky;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.75);
uniform float sun_disc = 1.0;
uniform vec3 zenith_col : source_color = vec3(0.6, 0.45, 0.35);
uniform vec3 horizon_col : source_color = vec3(0.9, 0.7, 0.5);
uniform vec3 glow_col : source_color = vec3(1.0, 0.55, 0.3);
uniform float glow_amount = 0.0;
uniform vec3 ground_col : source_color = vec3(0.35, 0.22, 0.15);
uniform vec3 planet_dir = vec3(0.078, 0.225, -0.97);
uniform vec3 planet_light = vec3(0.6, 0.45, 0.66);
uniform float planet_radius = 0.16;
uniform vec3 planet_col : source_color = vec3(0.86, 0.84, 0.8);
uniform float planet_vis = 1.0;
uniform float night = 0.0;
uniform float haze = 0.6;
uniform float storm = 0.0;
uniform float time = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(i);
	float b = hash13(i + vec3(1, 0, 0));
	float c = hash13(i + vec3(0, 1, 0));
	float d = hash13(i + vec3(1, 1, 0));
	float e = hash13(i + vec3(0, 0, 1));
	float g = hash13(i + vec3(1, 0, 1));
	float h = hash13(i + vec3(0, 1, 1));
	float k = hash13(i + vec3(1, 1, 1));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

float star_layer(vec3 d, float scale, float density) {
	vec3 p = d * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < density) {
		return 0.0;
	}
	vec3 c = cell + 0.5 + (hash33(cell) - 0.5) * 0.7;
	float dist = length(p - c);
	float bright = (h - density) / (1.0 - density);
	float tw = 0.75 + 0.25 * sin(time * (1.5 + h * 5.0) + h * 40.0);
	return smoothstep(0.32, 0.0, dist) * bright * tw;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	float upc = clamp(up, 0.0, 1.0);

	// Base gradient: most of the change happens near the horizon.
	float hz = pow(1.0 - upc, 3.2);
	vec3 col = mix(zenith_col, horizon_col, hz);

	// Sunset band and sun glow, weighted toward the sun's azimuth.
	float cs = dot(d, sun_dir);
	vec2 dh = normalize(d.xz + vec2(1e-5));
	vec2 sh = normalize(sun_dir.xz + vec2(1e-5));
	float az = dot(dh, sh) * 0.5 + 0.5;
	float band = exp(-max(up + 0.02, 0.0) * 7.0) * pow(az, 2.5);
	float halo = pow(max(cs, 0.0), 6.0) * 0.35 + pow(max(cs, 0.0), 48.0) * 0.55 + pow(max(cs, 0.0), 600.0) * 1.2;
	col += glow_col * band * glow_amount;
	col += sun_col * halo * (0.35 + 0.65 * glow_amount) * step(-0.25, sun_dir.y);

	// Dust haze: a bright band that sits on the horizon.
	col = mix(col, horizon_col * 1.04, exp(-abs(up) * 14.0) * haze * 0.55);

	if (!AT_CUBEMAP_PASS) {
		// Stars and galaxy band (night only).
		if (night > 0.01 && up > -0.1) {
			float fade = night * smoothstep(-0.05, 0.25, up) * (1.0 - storm);
			vec3 gn = normalize(vec3(0.35, 0.82, 0.45));
			float gb = exp(-pow(dot(d, gn) * 5.5, 2.0));
			float gnoise = fbm(d * 7.0 + vec3(3.1, 1.7, 0.4));
			vec3 galaxy = vec3(0.55, 0.6, 0.85) * gb * (0.35 + 0.9 * gnoise * gnoise) * 0.18;
			galaxy += vec3(0.9, 0.75, 0.6) * gb * pow(gnoise, 4.0) * 0.12;
			float st = star_layer(d, 150.0, 0.93) * 1.4 + star_layer(d, 320.0, 0.965) * 0.9 + star_layer(d, 90.0, 0.985) * 2.2;
			st *= 1.0 + gb * 1.5;
			vec3 star_col = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.88, 0.75), hash13(floor(d * 150.0)));
			col += (galaxy + star_col * st) * fade;
		}

		// The planet: a large pale disc with bands, lit by the sun, and a thin ring.
		if (planet_vis > 0.001) {
			vec3 pd = normalize(planet_dir);
			vec3 t = normalize(cross(pd, vec3(0.0, 1.0, 0.0)));
			vec3 b = normalize(cross(t, pd));
			float cp = dot(d, pd);
			vec2 q = vec2(dot(d, t), dot(d, b)) / planet_radius;
			float r2 = dot(q, q);
			// Ring: an ellipse in the planet's tilted equatorial plane.
			vec2 rq = vec2(q.x * 0.96 + q.y * 0.28, (q.y * 0.96 - q.x * 0.28) * 4.2);
			float rr = length(rq);
			float ring = smoothstep(1.55, 1.6, rr) * smoothstep(2.25, 2.1, rr) * (0.55 + 0.45 * sin(rr * 38.0));
			float behind = step(0.0, rq.y); // lower half of the ring passes in front of the disc
			vec3 ring_col = planet_col * vec3(0.95, 0.9, 0.82) * 0.75;
			if (cp > 0.0 && r2 < 1.0) {
				float z = sqrt(1.0 - r2);
				vec3 n = normalize(q.x * t + q.y * b - z * pd);
				float lat = dot(n, normalize(b + t * 0.28));
				float bands = 0.82 + 0.1 * sin(lat * 23.0 + fbm(n * 3.0) * 4.0) + 0.08 * fbm(n * 9.0);
				float lit = max(dot(n, normalize(planet_light)), 0.0);
				float rim = pow(1.0 - z, 3.0);
				vec3 pc = planet_col * bands * (0.16 + 0.95 * lit) + vec3(0.5, 0.65, 0.9) * rim * 0.3;
				float edge = smoothstep(1.0, 0.97, r2);
				col = mix(col, pc, edge * planet_vis);
				if (behind < 0.5) {
					col = mix(col, ring_col, ring * planet_vis * 0.85);
				}
			} else if (cp > 0.0) {
				col += planet_col * 0.08 * exp(-(sqrt(r2) - 1.0) * 9.0) * planet_vis;
				col = mix(col, ring_col, ring * planet_vis * 0.75);
			}
		}

		// Sun disc.
		float disc = smoothstep(0.99955, 0.99975, cs) * sun_disc;
		col += sun_col * disc * 18.0 * smoothstep(-0.03, 0.01, up);
	}

	// Storm: flatten everything into orange dust.
	col = mix(col, horizon_col * 0.9, storm * 0.85);

	// Below the horizon the far ground takes over (mostly hidden by the terrain).
	col = mix(col, ground_col, smoothstep(-0.01, -0.12, up));
	COLOR = col;
}
