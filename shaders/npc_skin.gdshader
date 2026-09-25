// Astronaut GPU skinning for instanced characters (RENDER, V3_DESIGN §3.4).
// Every colonist of one model variant is ONE MultiMesh instance of one mesh: a few draw
// calls for all of them. The bone matrices of every clip frame are baked once into the
// `anim` texture (presentation/fx_npc.gd); each instance says which frames to use:
//   INSTANCE_CUSTOM.x = row of pose A (+ fraction to the next row: frame interpolation)
//   INSTANCE_CUSTOM.y = row of pose B + 0.998 x weight of B (cross-fade or run blend), -1 = none
//   INSTANCE_CUSTOM.z = look code: role * 64 + head * 8 + skin tone
//   INSTANCE_CUSTOM.w = row of the carry layer + 0.998 x its weight, -1 = none
// Row layout: slots 0..upper_start-1 hold full skin matrices (lower body and chest), slots
// upper_start.. hold matrices RELATIVE TO THE CHEST, and slot `chest_slot` holds the chest.
// So the carry layer re-parents the carry clip's upper body onto the walking chest.
// Vertex data: the imported mesh as it is: BONE_INDICES (skin bind indices, mapped to slots
// by `bind_slot`), BONE_WEIGHTS, COLOR = baked AO (instance colours are white).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D anim : filter_nearest, repeat_disable;
// Blended poses (cross-fades, walk/run mixes) are evaluated on the CPU with quaternion slerp
// of the local bone rotations and written to this small texture, one row per colonist; a
// row index >= dyn0 means "read the dynamic row" (V3 §3.4: never a matrix or basis lerp).
uniform sampler2D dyn : filter_nearest, repeat_disable;
uniform int dyn0 = 1000000;
// Per body (full float): row A + fraction, row B + weight, look, carry row + weight.
// INSTANCE_CUSTOM.x is the body index (MultiMesh custom data is half float in Compatibility).
uniform sampler2D bdata : filter_nearest, repeat_disable;
uniform int row_w = 75;
uniform int rows_per_col = 4096;
uniform int upper_start = 12;
uniform int chest_slot = 24;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform int mode = 0;          // 0 plain, 1 role colour, 2 skin tone, 3 hair colour, 4 visitor body colour
// V3.1 visitors (look code role >= 8, v = role - 8): this material's colour per visitor look;
// a negative colour = keep the material's own colour.
uniform vec4 vis_cols[7];
uniform vec4 roles[8];   // linear role colours
uniform float ao_amount = 1.0;
uniform int bind_slot[64];     // skin bind index -> matrix slot
uniform int head_id = -1;      // >= 0: this mesh is head variant n (only those instances draw it)

varying vec3 v_tint;
varying float v_ao;
varying float v_fade;   // INSTANCE_CUSTOM.y: 1 drawn .. 0 gone (dithered fade, V3_1 §4.3)

ivec2 tx(int row, int texel) {
	int col = row / rows_per_col;
	return ivec2(col * row_w + texel, row - col * rows_per_col);
}

void fetch3(int row, int slot, out vec4 r0, out vec4 r1, out vec4 r2) {
	int b = slot * 3;
	if (row >= dyn0) {
		int dr = row - dyn0;
		r0 = texelFetch(dyn, ivec2(b, dr), 0);
		r1 = texelFetch(dyn, ivec2(b + 1, dr), 0);
		r2 = texelFetch(dyn, ivec2(b + 2, dr), 0);
		return;
	}
	r0 = texelFetch(anim, tx(row, b), 0);
	r1 = texelFetch(anim, tx(row, b + 1), 0);
	r2 = texelFetch(anim, tx(row, b + 2), 0);
}

// Matrix rows of one slot, interpolated between two frame rows.
void slot_rows(int row, float f, int slot, out vec4 r0, out vec4 r1, out vec4 r2) {
	fetch3(row, slot, r0, r1, r2);
	if (f > 0.001) {
		vec4 s0; vec4 s1; vec4 s2;
		fetch3(row + 1, slot, s0, s1, s2);
		r0 = mix(r0, s0, f);
		r1 = mix(r1, s1, f);
		r2 = mix(r2, s2, f);
	}
}

vec3 xp(vec4 r0, vec4 r1, vec4 r2, vec3 p) {
	vec4 q = vec4(p, 1.0);
	return vec3(dot(r0, q), dot(r1, q), dot(r2, q));
}

vec3 xn(vec4 r0, vec4 r1, vec4 r2, vec3 n) {
	return vec3(dot(r0.xyz, n), dot(r1.xyz, n), dot(r2.xyz, n));
}

// Skins one vertex with the pose of `row` (+ f), the carry layer (crow, cw) on the upper body.
void skin(int row, float f, int crow, float cw, vec3 p, vec3 n, ivec4 bi, vec4 bw, out vec3 po, out vec3 no) {
	vec4 c0; vec4 c1; vec4 c2;
	slot_rows(row, f, chest_slot, c0, c1, c2);
	po = vec3(0.0);
	no = vec3(0.0);
	for (int k = 0; k < 4; k++) {
		float w = bw[k];
		if (w <= 0.0) {
			continue;
		}
		int s = bi[k];
		vec4 r0; vec4 r1; vec4 r2;
		slot_rows(row, f, s, r0, r1, r2);
		vec3 pk = xp(r0, r1, r2, p);
		vec3 nk = xn(r0, r1, r2, n);
		if (s >= upper_start) {
			if (cw > 0.001) {
				vec4 q0; vec4 q1; vec4 q2;
				fetch3(crow, s, q0, q1, q2);
				pk = mix(pk, xp(q0, q1, q2, p), cw);
				nk = mix(nk, xn(q0, q1, q2, n), cw);
			}
			pk = xp(c0, c1, c2, pk);
			nk = xn(c0, c1, c2, nk);
		}
		po += pk * w;
		no += nk * w;
	}
}

vec3 palette6(float v, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 g) {
	int i = int(clamp(v, 0.0, 5.0) + 0.5);
	return i == 0 ? a : (i == 1 ? b : (i == 2 ? c : (i == 3 ? d : (i == 4 ? e : g))));
}

void vertex() {
	vec4 ic = texelFetch(bdata, ivec2(0, int(INSTANCE_CUSTOM.x + 0.5)), 0);
	v_fade = INSTANCE_CUSTOM.y;
	int look = int(ic.z + 0.5);
	int role = look / 64;
	int head = (look / 8) % 8;
	int tone = look % 8;
	v_ao = mix(1.0, COLOR.r, ao_amount);
	if (head_id >= 0 && head_id != head) {
		// Another head variant: collapse the vertex (nothing is drawn).
		VERTEX = vec3(0.0);
	} else {
		ivec4 bi = ivec4(bind_slot[int(BONE_INDICES.x)], bind_slot[int(BONE_INDICES.y)], bind_slot[int(BONE_INDICES.z)], bind_slot[int(BONE_INDICES.w)]);
		vec4 bw = BONE_WEIGHTS;
		float ra = floor(ic.x);
		float fa = ic.x - ra;
		int crow = -1;
		float cw = 0.0;
		if (ic.w >= 0.0) {
			crow = int(floor(ic.w));
			cw = clamp((ic.w - float(crow)) / 0.998, 0.0, 1.0);
		}
		vec3 pa; vec3 na;
		skin(int(ra), fa, crow, cw, VERTEX, NORMAL, bi, bw, pa, na);
		if (ic.y >= 0.0) {
			int rb = int(floor(ic.y));
			float wb = clamp((ic.y - float(rb)) / 0.998, 0.0, 1.0);
			if (wb > 0.001) {
				vec3 pb; vec3 nb;
				skin(rb, 0.0, crow, cw, VERTEX, NORMAL, bi, bw, pb, nb);
				pa = mix(pa, pb, wb);
				na = mix(na, nb, wb);
			}
		}
		VERTEX = pa;
		NORMAL = normalize(na);
	}
	v_tint = vec3(1.0);
	if ((mode == 1 || mode == 4) && role >= 8) {
		vec4 vc = vis_cols[clamp(role - 8, 0, 6)];
		v_tint = vc.r >= 0.0 ? vc.rgb / max(albedo.rgb, vec3(0.04)) : vec3(1.0);
	} else if (mode == 1) {
		v_tint = roles[clamp(role, 0, 7)].rgb / max(albedo.rgb, vec3(0.04));
	} else if (mode == 2) {
		// Six skin tones (linear), dark to light: replace the albedo.
		v_tint = palette6(float(tone), vec3(0.21, 0.09, 0.04), vec3(0.37, 0.17, 0.07), vec3(0.55, 0.3, 0.15), vec3(0.72, 0.44, 0.26), vec3(0.85, 0.57, 0.38), vec3(0.91, 0.60, 0.42)) / max(albedo.rgb, vec3(0.04));
	} else if (mode == 3) {
		// Four hair colours (linear): black, dark brown, auburn, dark blonde. Critic round 8: auburn
		// (sRGB about #9E4C22) and dark blonde (#C7AA73) made clearly different from the browns.
		int hc = (tone + head * 3) % 4;
		vec3 hair = hc == 0 ? vec3(0.010, 0.008, 0.007) : (hc == 1 ? vec3(0.075, 0.035, 0.015) : (hc == 2 ? vec3(0.34, 0.075, 0.018) : vec3(0.58, 0.40, 0.17)));
		v_tint = hair / max(albedo.rgb, vec3(0.04));
	}
}

void fragment() {
	if (v_fade < 0.999) {
		float hh = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
		if (hh > v_fade) {
			discard;
		}
	}
	vec3 base = albedo.rgb;
	if (use_tex) {
		base *= texture(albedo_tex, UV).rgb;
	}
	ALBEDO = base * v_tint * v_ao;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission.rgb * emission_energy;
}
