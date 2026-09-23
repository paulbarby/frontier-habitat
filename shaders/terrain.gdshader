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

uniform vec2 map_size = vec2(256.0, 256.0);
uniform float tile_a = 5.0;      // sand + gravel
uniform float tile_b = 7.5;      // rock + ore
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec2 wind_dir = vec2(0.83, 0.55);
uniform float overlay = 0.0;
uniform float gravel_amount = 1.0;
uniform float detail = 1.0;      // quality: 0 drops the anti-tiling pass

varying vec3 wpos;
varying vec3 wnrm;

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
	vec4 gd = texture(ground, cuv) * inside;

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
	vec4 co = texture(alb_ore, ub);
	vec4 na = texture(nrm_a, ua);
	vec4 nb = texture(nrm_b, ub);

	// Layer weights.
	float crater = sp.a - 0.5;
	float w_g = smoothstep(0.5, 0.78, mA.g * 0.65 + mB.g * 0.45 + slope * 1.6 + max(crater, 0.0) * 1.5) * gravel_amount;
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

	// Large-scale variation, wind streaks, streaks behind rocks.
	alb *= 0.8 + 0.38 * mA.r;
	alb *= mix(vec3(1.0), vec3(1.06, 0.98, 0.93), mA.b * 0.7);
	// Low ground is redder and darker, rises are paler and dustier.
	float hv = clamp(wpos.y * 0.12, -1.0, 1.0);
	alb *= mix(vec3(0.93, 0.9, 0.9), vec3(1.05, 1.03, 1.0), hv * 0.5 + 0.5);
	alb *= 0.93 + 0.14 * streak * (1.0 - b.z);
	alb *= 1.0 + (sp.b - 0.5) * 0.5;

	// Craters: dark bowls, bright ejecta rims, and bent normals.
	float tx = 1.0 / 512.0;
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
	alb *= tint;

	// Walk overlay: crisp one-metre cells.
	if (overlay > 0.001 && inside > 0.5) {
		ivec2 cell = ivec2(floor(p));
		float ov = texelFetch(ground, clamp(cell, ivec2(0), ivec2(textureSize(ground, 0)) - 1), 0).g;
		vec2 f = fract(p);
		float grid = 1.0 - smoothstep(0.0, 0.07, min(min(f.x, f.y), min(1.0 - f.x, 1.0 - f.y)));
		vec3 oc = ov > 0.75 ? vec3(0.95, 0.25, 0.2) : vec3(0.25, 0.9, 0.45);
		float oa = ov > 0.75 ? 0.55 : (ov > 0.25 ? 0.22 + grid * 0.35 : 0.0);
		alb = mix(alb, oc, oa * overlay);
		EMISSION = oc * oa * overlay * 0.25;
	}

	vec3 t = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 bt = normalize(vec3(0.0, 0.0, 1.0) - n * n.z);
	float nz = sqrt(clamp(1.0 - dot(nxy, nxy), 0.0, 1.0));
	vec3 nw = normalize(t * nxy.x + bt * nxy.y + n * nz);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = alb;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	AO = ao;
	AO_LIGHT_AFFECT = 0.7;
}
