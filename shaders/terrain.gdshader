// Frontier Habitat terrain (RENDER). World-space XZ projection (the terrain has no
// cliffs), four height-blended layers: sand, gravel, rock, dark ore field.
//   splat  (map space, 0.5 m/px): R ore field, G rock outcrop, B wind streak (0.5 = none),
//          A crater height (0.5 = flat; the gradient bends the normal: rims and bowls)
//   ground (map space, 1 m/px):   R footpath wear, G walk overlay (0 none, .5 open, 1 blocked),
//          B contact shadow under structures, A disturbed ground around construction
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D alb_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb_gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D alb_ore : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_a : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_b : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro : filter_linear_mipmap, repeat_enable;
uniform sampler2D splat : filter_linear, repeat_disable;
uniform sampler2D ground : filter_linear, repeat_disable;
uniform sampler2D hazard : filter_linear, repeat_disable;
uniform float hazard_on = 0.0;
uniform float splat_texel = 0.001953125;

uniform vec2 map_size = vec2(256.0, 256.0);
uniform float tile_a = 5.0;      // sand + gravel
uniform float tile_b = 7.5;      // rock + ore
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// Planets (Paul 2026-10-01, V5 15.7): airless = grey regolith (desaturate), cold = frost and ice on the ground.
uniform float grey_k = 0.0;
uniform float frost = 0.0;
uniform float fog_rim = 0.22;   // the warm rim along the explored ground (0 on airless and cold: over grey regolith it
                                // read as a yellow-green patch, critic round 41)
uniform float streak_k = 1.0;   // wind-blown sand streaks (0 on the airless planet: no wind)
uniform vec2 wind_dir = vec2(0.83, 0.55);
uniform float overlay = 0.0;
uniform float gravel_amount = 1.0;
uniform float detail = 1.0;      // quality: 0 drops the anti-tiling pass

uniform vec2 ground_origin = vec2(0.0);   // ground texture window (v4: 1,024 m round the start)
uniform float ground_size = 256.0;

// V4 horizon (terrain_v4.gd bakes it on the GPU from sim.world.heights, in SIM's layout: the sun
// bearings of the day, b = bearing / PI * (bins - 1), horizon elevation in degrees). Atlas of 4
// tiles side x side; RGBA of tile t = bins 4t..4t+3; bin `bins` = mean horizon angle / 90 (sky).
uniform float hz_on = 0.0;
uniform sampler2D hz_tex : filter_linear, repeat_disable;
uniform float hz_side = 321.0;
uniform float hz_cell = 8.0;
uniform float hz_bins = 13.0;
uniform float sun_bin = 6.0;
uniform float sun_el_deg = 30.0;
uniform float sun_day = 1.0;     // 1 while the key light is the sun (the planet-shine has no horizon)
uniform float hz_soft = 1.5;     // degrees: a 2-4 m penumbra on a crater floor
uniform float key_comp = 1.0;    // 1 / the key-light factor world_view applies for objects in shadow
uniform float amb_comp = 1.0;
uniform float crack_cut = 0.0;
// V4 map layers (fx_terrain.set_layer): 1 radiation, 2 sun (share of the day in sunlight),
// 3 resources (colour + alpha painted per deposit tier), 4 explored area. Map space.
uniform int layer_mode = 0;
uniform sampler2D layer_tex : filter_linear, repeat_disable;
// Fog of war (SIM's explored cells): unexplored ground is dimmed, desaturated and hazed.
uniform float fog_on = 0.0;
uniform float fog_gain = 1.0;     // 255 when fog_tex holds SIM's 0/1 bits
uniform float fog_texel = 0.0;    // > 0: soften over +-1 fog cell (5 taps)
uniform sampler2D fog_tex : filter_linear, repeat_disable;   // V4: 1 = the terrain opens over SIM's crevices (their own mesh draws there)
uniform float bounce = 0.26;     // V4: light from the sunlit walls on a floor in horizon shadow (x lit)    // 1 / the ambient factor world_view applies in a deep crater

varying vec3 wpos;
varying vec3 wnrm;
varying float v_sun;             // horizon visibility of the key light (fragment -> light)

// Crevice walls (critic round 22): rough rock noise on the lofted wall mesh (crevice_mat only).
uniform float wall_rough = 0.0;
float h3(vec3 q) {
	return fract(sin(dot(q, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float hz_fetch(vec2 cuv, float b) {
	float tile = floor(b / 4.0);
	float ch = b - tile * 4.0;
	vec4 v = texture(hz_tex, vec2((tile + cuv.x) * 0.25, cuv.y));
	return ch < 0.5 ? v.r : (ch < 1.5 ? v.g : (ch < 2.5 ? v.b : v.a));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;

	vec4 mA = texture(macro, p * (1.0 / 197.0));
	vec4 mB = texture(macro, p * (1.0 / 47.0) + vec2(0.31, 0.77));
	vec2 wd = normalize(wind_dir);
	vec2 q = vec2(dot(p, wd), dot(p, vec2(-wd.y, wd.x)));
	float streak = texture(macro, q * vec2(1.0 / 160.0, 1.0 / 23.0)).a;

	vec2 suv = p / map_size;
	float inside = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
	vec2 cuv = clamp(suv, vec2(0.0), vec2(1.0));
	vec4 sp = mix(vec4(0.0, 0.0, 0.5, 0.5), texture(splat, cuv), inside);
	vec2 guv = (p - ground_origin) / ground_size;
	float gin = step(0.0, guv.x) * step(guv.x, 1.0) * step(0.0, guv.y) * step(guv.y, 1.0);
	vec4 gd = texture(ground, clamp(guv, vec2(0.0), vec2(1.0))) * gin;

	vec2 ua = p / tile_a;
	vec2 ub = (p + vec2(0.0, wpos.y * 0.7)) / tile_b;
	vec4 cs = texture(alb_sand, ua);
	if (detail > 0.5) {
		// Anti-tiling: a second, rotated and larger sand sample, mixed by macro noise.
		vec2 ua2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p / (tile_a * 2.7);
		vec4 cs2 = texture(alb_sand, ua2 + vec2(0.13, 0.71));
		cs = mix(cs, cs2, smoothstep(0.35, 0.65, mB.r));
	}
	vec4 cg = texture(alb_gravel, ua);
	vec4 cr = texture(alb_rock, ub);
	// V4 cliffs (crater walls, mountains, crevices): triplanar rock, no stretched texture.
	if (slope > 0.3) {
		vec3 tw = pow(abs(n), vec3(4.0));
		tw /= (tw.x + tw.y + tw.z);
		vec4 rx = texture(alb_rock, wpos.zy / tile_b);
		vec4 rz = texture(alb_rock, wpos.xy / tile_b + vec2(0.37, 0.11));
		cr = mix(cr, rx * tw.x + rz * tw.z + cr * tw.y, smoothstep(0.3, 0.5, slope));
	}
	vec4 co = texture(alb_ore, ub);
	vec4 na = texture(nrm_a, ua);
	vec4 nb = texture(nrm_b, ub);

	// Layer weights.
	float crater = sp.a - 0.5;
	// (critic round 20: the 47 m macro repeat read as a honeycomb; a rotated 83 m sample and a
	// 610 m sample break it)
	vec4 mD = texture(macro, mat2(vec2(0.28, 0.96), vec2(-0.96, 0.28)) * p * (1.0 / 83.0) + vec2(0.61, 0.37));
	float mE = texture(macro, p * (1.0 / 610.0) + vec2(0.23, 0.81)).g;
	float gdrive = mA.g * 0.55 + mix(mB.g, mD.g, 0.55) * 0.42 + (mE - 0.5) * 0.35;
	float w_g = smoothstep(0.5, 0.78, gdrive + slope * 1.6 + max(crater, 0.0) * 1.5) * gravel_amount;
	w_g = max(w_g, sp.g * 0.8);
	float shelf = smoothstep(0.6, 0.82, mB.b) * smoothstep(0.03, 0.09, slope);
	float w_r = smoothstep(0.11, 0.24, slope + (mA.b - 0.5) * 0.1) + shelf + sp.g * smoothstep(0.25, 0.6, mB.g);
	float w_o = smoothstep(0.25, 0.75, sp.r + (mB.g - 0.5) * 0.5);
	float wear = gd.r;
	float dug = gd.a;
	w_g = mix(w_g, 0.1, smoothstep(0.04, 0.6, wear) * 0.8);
	w_g = max(w_g, dug * 0.9);

	vec4 hw = vec4(cs.a * 0.5 + 0.55, cg.a * 0.7 + w_g * 1.1 - 0.35, cr.a * 0.6 + w_r * 1.2 - 0.5, co.a * 0.5 + w_o * 1.4 - 0.4);
	float mx = max(max(hw.x, hw.y), max(hw.z, hw.w)) - 0.18;
	vec4 b = max(hw - vec4(mx), vec4(0.0));
	b /= max(b.x + b.y + b.z + b.w, 1e-4);

	vec3 alb = cs.rgb * b.x + cg.rgb * b.y + cr.rgb * b.z + co.rgb * b.w;
	vec2 nxy = (na.rg * 2.0 - 1.0) * b.x + (na.ba * 2.0 - 1.0) * b.y + (nb.rg * 2.0 - 1.0) * b.z + (nb.ba * 2.0 - 1.0) * b.w;
	float rough = 0.93 * b.x + 0.86 * b.y + 0.8 * b.z + mix(0.62, 0.3, smoothstep(0.45, 0.6, co.g)) * b.w;

	// Large-scale variation, wind streaks, streaks behind rocks. Far away (the v4 overview) the
	// 197 m and 47 m macro repeats would show as a pattern: a 1.3 km rotated sample takes over.
	float far = smoothstep(260.0, 900.0, length(wpos - CAMERA_POSITION_WORLD));
	vec4 mC = texture(macro, mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * p * (1.0 / 1310.0) + vec2(0.52, 0.18));
	mA = mix(mA, vec4(mC.r, mA.g, mC.b, mA.a), far * 0.8);
	alb = mix(alb, (cs.rgb * 0.6 + cg.rgb * 0.4) * (0.85 + 0.3 * mC.g), far * 0.55 * (1.0 - b.z));
	alb *= 0.8 + 0.38 * mA.r;
	alb *= mix(vec3(1.0), vec3(1.06, 0.98, 0.93), mA.b * 0.7);
	// Low ground is redder and darker, rises are paler and dustier.
	float hv = clamp(wpos.y * 0.12, -1.0, 1.0);
	alb *= mix(vec3(0.93, 0.9, 0.9), vec3(1.05, 1.03, 1.0), hv * 0.5 + 0.5);
	alb *= mix(0.965, 0.93 + 0.14 * streak * (1.0 - b.z), streak_k);
	alb *= 1.0 + clamp(sp.b - 0.5, -0.2, 0.5) * 0.5 * streak_k;

	// Craters: dark bowls, bright ejecta rims, and bent normals.
	float tx = splat_texel;
	float cxh = texture(splat, clamp(suv + vec2(tx, 0.0), vec2(0.0), vec2(1.0))).a;
	float czh = texture(splat, clamp(suv + vec2(0.0, tx), vec2(0.0), vec2(1.0))).a;
	vec2 cgrad = vec2(cxh - sp.a, czh - sp.a) * inside;
	nxy -= cgrad * 9.0;
	alb *= 1.0 + clamp(crater, -0.5, 0.5) * 0.55;

	// Footpaths: compacted, darker, smoother. Construction: churned ground.
	float wr = smoothstep(0.04, 0.6, wear);
	alb *= mix(vec3(1.0), vec3(0.7, 0.62, 0.58), wr);
	nxy *= 1.0 - wr * 0.7;
	rough = mix(rough, 0.78, wr);
	alb *= mix(vec3(1.0), vec3(0.86, 0.8, 0.76), dug);

	// Contact shadow under and around structures (the web renderer has no SSAO).
	float ao = 1.0 - gd.b * 0.78;

	// V4 horizon: sun visibility for the key light, and how much sky a point sees (deep crater
	// floors: little sky, a cold grey tint, darker ambient).
	v_sun = 1.0;
	// Crevice mesh (wall_rough): the 4 m horizon cells alternate inside / outside the trench along a
	// wall and drew vertical light and dark stripes (critic round 22, "picket fence"). The wall and
	// floor take the sun from the shadow map only, and a fixed dimming for the narrow sky.
	if (wall_rough > 0.5) {
		ao *= 0.72;
	}
	if (hz_on > 0.5 && wall_rough < 0.5) {
		vec2 cuv2 = clamp((p / hz_cell + 0.5) / hz_side, vec2(0.5 / hz_side), vec2(1.0 - 0.5 / hz_side));
		float b0 = clamp(floor(sun_bin), 0.0, hz_bins - 2.0);
		float hz_deg = mix(hz_fetch(cuv2, b0), hz_fetch(cuv2, b0 + 1.0), clamp(sun_bin - b0, 0.0, 1.0)) * 100.0 - 10.0;
		float vis = clamp((sun_el_deg - hz_deg) / hz_soft + 0.5, 0.0, 1.0);
		v_sun = mix(1.0, vis, sun_day);
		float occl = hz_fetch(cuv2, hz_bins);
		float sky_open = clamp(1.0 - occl * 2.2, 0.12, 1.0);
		ao = min(ao * mix(1.0, max(sky_open, 0.45), 0.9) * amb_comp, 1.0);
		// Cold traps: grey-blue regolith where the floor sees little sky (critic round 20: the
		// floor keeps 12-18 % of the lit brightness, cool, not black).
		float cold = smoothstep(0.85, 0.2, sky_open);
		alb *= mix(vec3(1.0), vec3(0.8, 0.84, 0.94), cold * 0.8);
		// Ground in the horizon shadow reads cold: a blue-grey cast (critic round 18).
		float shd = (1.0 - v_sun) * sun_day;
		vec3 grey = vec3(dot(alb, vec3(0.3, 0.59, 0.11)));
		alb = mix(alb, grey * vec3(0.9, 0.97, 1.12), shd * 0.45);
	}
	// Cliffs (v4 mountains, crater walls): rock strata and more relief on steep ground.
	if (slope > 0.4) {
		float st = smoothstep(0.4, 0.7, slope);
		float band = sin(wpos.y * 1.9 + mA.r * 7.0 + mB.g * 3.0);
		alb *= 1.0 + band * 0.09 * st * (1.0 - wall_rough * 0.6);
		nxy += vec2(0.0, band * 0.22 * st * (1.0 - wall_rough * 0.6));
	}
	if (wall_rough > 0.0) {
		float rn = vnoise3(wpos * 0.42) * 0.55 + vnoise3(wpos * 1.5) * 0.3 + vnoise3(wpos * 4.1) * 0.15;
		alb *= mix(1.0, 0.68 + 0.6 * rn, wall_rough);
		vec2 bump = vec2(vnoise3(wpos * 0.8 + vec3(3.1, 0.0, 1.7)), vnoise3(wpos * 0.8 + vec3(7.7, 2.3, 0.0))) - 0.5;
		bump += (vec2(vnoise3(wpos * 2.6 + vec3(1.3)), vnoise3(wpos * 2.6 + vec3(5.9))) - 0.5) * 0.5;
		// The ground's normal maps are sampled in plan (xz): on a vertical wall they smear into
		// vertical stripes. The wall uses the rock bump only.
		nxy = bump * 1.1;
	}
	// Crevices (splat B near 0): a dark crack from SIM's crevice lines.
	float crack = smoothstep(0.1, 0.015, sp.b) * inside;
	if (crack_cut > 0.5 && sp.b < 0.03 && inside > 0.5) {
		discard;
	}
	alb *= mix(1.0, 0.07, crack * (1.0 - crack_cut));
	alb *= tint;
	if (grey_k > 0.0) {
		float gl = dot(alb, vec3(0.3, 0.59, 0.11));
		alb = mix(alb, vec3(gl) * vec3(0.98, 0.99, 1.02), grey_k);
	}
	if (frost > 0.0) {
		// Critic round 41: a smooth frost cover over a grey-blue base, not a blotchy camouflage over pink. The
		// base first goes grey-blue (cold regolith); the frost is a broad, soft cover (low-frequency noise,
		// wide edges) on the up-facing ground, thin in places, bare rock on the steep faces.
		vec3 gb = vec3(dot(alb, vec3(0.3, 0.59, 0.11))) * vec3(0.86, 0.92, 1.02);
		alb = mix(alb, gb, clamp(frost * 1.4, 0.0, 0.9));
		float fup = smoothstep(0.55, 0.9, n.y);
		float fn = vnoise3(wpos * 0.045) * 0.6 + vnoise3(wpos * 0.17) * 0.3 + vnoise3(wpos * 0.9) * 0.1;
		float fk = fup * mix(0.45, 1.0, smoothstep(0.25, 0.75, fn)) * clamp(frost * 1.4, 0.0, 1.0);
		alb = mix(alb, vec3(0.84, 0.89, 0.95), clamp(fk, 0.0, 0.85));
		rough = mix(rough, 0.45, fk * 0.6);
		nxy *= 1.0 - fk * 0.5;
	}

	// Walk overlay: crisp one-metre cells.
	if (overlay > 0.001 && inside > 0.5) {
		ivec2 cell = ivec2(floor(p - ground_origin));
		float ov = texelFetch(ground, clamp(cell, ivec2(0), ivec2(textureSize(ground, 0)) - 1), 0).g;
		vec2 f = fract(p);
		float grid = 1.0 - smoothstep(0.0, 0.07, min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)));
		vec3 oc = ov > 0.75 ? vec3(0.95, 0.25, 0.2) : vec3(0.25, 0.9, 0.45);
		float oa = ov > 0.75 ? 0.55 : (ov > 0.25 ? 0.22 + grid * 0.35 : 0.0);
		alb = mix(alb, oc, oa * overlay);
		EMISSION = oc * oa * overlay * 0.25;
	}

	// V4 map layers: false colour over the ground with contour lines (the ground stays readable).
	if (layer_mode > 0 && inside > 0.5) {
		vec4 lv = texture(layer_tex, cuv);
		vec3 lc = vec3(0.0);
		float la = 0.0;
		float fwl = 0.0;
		float line = 0.0;
		if (layer_mode == 1) {
			// radiation: value = log scale 0.02 .. 10 mSv/h; green safe, amber, red dangerous
			float v = lv.r;
			lc = v < 0.45 ? mix(vec3(0.15, 0.55, 0.35), vec3(0.95, 0.8, 0.2), v / 0.45) : mix(vec3(0.95, 0.8, 0.2), vec3(1.0, 0.18, 0.12), clamp((v - 0.45) / 0.35, 0.0, 1.0));
			la = mix(0.18, 0.62, smoothstep(0.1, 0.8, v));
			fwl = fwidth(v) * 1.5 + 1e-4;
			line = (1.0 - smoothstep(0.0, fwl, abs(v - 0.45))) + (1.0 - smoothstep(0.0, fwl, abs(v - 0.65)));
		} else if (layer_mode == 2) {
			// sun: 0 = never lit (deep crater floor) .. 1 = lit all day; blue to warm yellow
			float v = lv.r;
			lc = mix(vec3(0.12, 0.2, 0.55), vec3(1.0, 0.86, 0.35), v);
			la = 0.5;
			fwl = fwidth(v) * 1.5 + 1e-4;
			line = (1.0 - smoothstep(0.0, fwl, abs(v - 0.25))) + (1.0 - smoothstep(0.0, fwl, abs(v - 0.5))) + (1.0 - smoothstep(0.0, fwl, abs(v - 0.75)));
		} else if (layer_mode == 3) {
			lc = lv.rgb;
			la = lv.a * 0.85;
			fwl = fwidth(lv.a) * 1.5 + 1e-4;
			line = 1.0 - smoothstep(0.0, fwl, abs(lv.a - 0.5));
		} else if (layer_mode == 4) {
			float v = lv.r;
			lc = mix(vec3(0.2, 0.22, 0.3), vec3(0.3, 0.85, 1.0), v);
			la = mix(0.55, 0.12, v);
			fwl = fwidth(v) * 1.5 + 1e-4;
			line = 1.0 - smoothstep(0.0, fwl, abs(v - 0.5));
		}
		alb = mix(alb * 0.8, lc, la);
		alb = mix(alb, vec3(1.0), clamp(line, 0.0, 1.0) * 0.45);
		EMISSION = lc * la * 0.22 + vec3(clamp(line, 0.0, 1.0) * 0.18);
	}
	// Fog of war: unexplored ground dim, grey and hazed; explored ground as it is.
	if (fog_on > 0.5 && inside > 0.5) {
		float ex = texture(fog_tex, cuv).r;
		if (fog_texel > 0.0) {
			// Critic round 22: blur over 2-3 cells (13 taps), so the 16 m cells do not show as steps.
			float s = ex * 4.0;
			for (int i = 0; i < 4; i++) {
				float an = float(i) * 1.5707963;
				vec2 d1 = vec2(cos(an), sin(an)) * fog_texel * 1.2;
				vec2 d2 = vec2(cos(an + 0.785398), sin(an + 0.785398)) * fog_texel * 1.9;
				vec2 d3 = vec2(cos(an), sin(an)) * fog_texel * 2.6;
				s += texture(fog_tex, cuv + d1).r * 2.0 + texture(fog_tex, cuv + d2).r * 1.2 + texture(fog_tex, cuv + d3).r * 0.8;
			}
			ex = s / 20.0;
		}
		ex = min(ex * fog_gain, 1.0);
		vec3 g = vec3(dot(alb, vec3(0.3, 0.59, 0.11)));
		// Unexplored: grey and dim, but the relief still reads (0.62, was 0.45).
		vec3 fogged = mix(g, vec3(0.34, 0.33, 0.38), 0.3) * 0.62;
		float ek = smoothstep(0.1, 0.9, ex);
		alb = mix(fogged, alb, ek);
		// A warm rim along the edge of the explored ground.
		float rim = smoothstep(0.08, 0.45, ex) * (1.0 - smoothstep(0.45, 0.85, ex));
		alb += vec3(1.0, 0.58, 0.28) * rim * fog_rim;
	}

	// Hazard zones (V3 1): meteor red, wind cyan, quake violet; only above-average risk
	// is coloured, with contour lines at x1.25 and x1.5.
	if (hazard_on > 0.5 && inside > 0.5) {
		vec3 hz = texture(hazard, cuv).rgb * 1.5 + 0.5;
		vec3 risk = clamp((hz - 1.0) / 0.8, 0.0, 1.0);
		vec3 hc = vec3(1.0, 0.36, 0.22) * risk.r + vec3(0.25, 0.85, 1.0) * risk.g + vec3(0.7, 0.45, 1.0) * risk.b;
		float ha = clamp(max(max(risk.r, risk.g), risk.b), 0.0, 1.0);
		hc /= max(risk.r + risk.g + risk.b, 1e-3);
		float mh = max(max(hz.r, hz.g), hz.b);
		float fw = fwidth(mh) * 1.5 + 1e-4;
		float line = (1.0 - smoothstep(0.0, fw, abs(mh - 1.25))) + (1.0 - smoothstep(0.0, fw, abs(mh - 1.5)));
		alb = mix(alb * 0.72, hc, ha * 0.62);
		alb = mix(alb, vec3(1.0), clamp(line, 0.0, 1.0) * 0.5);
		EMISSION = hc * (ha * 0.18 + line * 0.25);
	}

	vec3 t = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 bt = normalize(vec3(0.0, 0.0, 1.0) - n * n.z);
	if (wall_rough > 0.5 && abs(n.y) < 0.8) {
		t = normalize(cross(vec3(0.0, 1.0, 0.0), n));
		bt = normalize(cross(n, t));
	}
	float nz = sqrt(clamp(1.0 - dot(nxy, nxy), 0.0, 1.0));
	vec3 nw = normalize(t * nxy.x + bt * nxy.y + n * nz);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	AO = ao;
	AO_LIGHT_AFFECT = 0.7;
}

// Godot's own Burley diffuse and Schlick-GGX specular (the render modes above), with the
// horizon visibility applied to the key light only (V4 1.1). key_comp restores the terrain's
// sun where world_view dims the key light for objects in a shadowed crater.
float schlick_f(float u) {
	float m = clamp(1.0 - u, 0.0, 1.0);
	float m2 = m * m;
	return m2 * m2 * m;
}

void light() {
	float vis = LIGHT_IS_DIRECTIONAL ? v_sun * key_comp : 1.0;
	vec3 H = normalize(VIEW + LIGHT);
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 1e-4, 1.0);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float ldh = clamp(dot(LIGHT, H), 0.0, 1.0);
	float fd90m1 = 2.0 * ldh * ldh * ROUGHNESS - 0.5;
	float fdv = 1.0 + fd90m1 * schlick_f(ndv);
	float fdl = 1.0 + fd90m1 * schlick_f(ndl);
	vec3 lc = LIGHT_COLOR * ATTENUATION * vis;
	DIFFUSE_LIGHT += lc * (fdv * fdl * ndl / PI);
	// Bounce from the sunlit crater walls onto ground in horizon shadow: cool, even, weak.
	if (LIGHT_IS_DIRECTIONAL && sun_day > 0.5) {
		DIFFUSE_LIGHT += LIGHT_COLOR * key_comp * (1.0 - v_sun) * bounce * vec3(0.78, 0.86, 1.0) / PI;
	}
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * dd * dd);
	float G = 0.5 / mix(2.0 * ndl * ndv, ndl + ndv, a);
	float f0 = 0.16 * 0.35 * 0.35;
	float F = f0 + (0.97 - f0) * schlick_f(ldh);
	SPECULAR_LIGHT += lc * (ndl * D * F * G) * SPECULAR_AMOUNT;
}
