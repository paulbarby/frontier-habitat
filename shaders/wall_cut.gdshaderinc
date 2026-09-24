// Room wall segments (RENDER, V3_DESIGN §7.2). The 32 objects Wall_00..Wall_31 of a room
// are merged into ONE mesh (presentation/models.gd); UV2.x = segment index + 1. Each room
// instance hides the segments in its doorways with a 32-bit mask in INSTANCE_CUSTOM
// (x = segments 0..15, y = segments 16..31): a hidden segment collapses in the vertex
// shader, so it draws nothing and casts no shadow. Otherwise this is the library material.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform bool use_vc = true;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform vec3 fill_color : source_color = vec3(1.0, 0.86, 0.7);
uniform float fill = 0.0;      // interior fill light on faces that look into the room
uniform int mode = 0;          // 1 = Screen (animated UI pattern)

varying vec3 lpos;
varying float inner;

void vertex() {
	lpos = VERTEX;
	// Faces that look into the room (towards the axis) get the fill; the outer hull does not.
	vec2 radial = length(VERTEX.xz) > 0.01 ? normalize(VERTEX.xz) : vec2(0.0);
	inner = smoothstep(-0.45, 0.05, -dot(radial, NORMAL.xz));
	int seg = int(UV2.x + 0.5) - 1;
	if (seg >= 0) {
		float word = seg < 16 ? INSTANCE_CUSTOM.x : INSTANCE_CUSTOM.y;
		int bit = seg < 16 ? seg : seg - 16;
		if (((int(word + 0.5) >> bit) & 1) == 1) {
			VERTEX = vec3(0.0);
		}
	}
}

void fragment() {
	vec3 c = albedo.rgb;
	float a = albedo.a;
	if (use_tex) {
		vec4 t = texture(albedo_tex, UV);
		c *= t.rgb;
		a *= t.a;
	}
	if (use_vc) {
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	vec3 e = emission.rgb * emission_energy;
	if (mode == 1) {
		vec2 q = vec2(lpos.x + lpos.z, lpos.y) * 18.0;
		float row = floor(q.y);
		float bars = step(0.35, fract(q.y)) * step(fract(sin(row * 12.9898 + floor(q.x * 0.5 + TIME * 0.6) * 78.233) * 43758.5453), 0.62);
		float scan = smoothstep(0.0, 0.08, abs(fract(lpos.y * 1.7 - TIME * 0.35) - 0.5));
		// Dark screen (the material colour) with thin glowing UI lines, not a flat slab.
		e = emission.rgb * max(emission_energy, 0.6) * (0.8 + 0.2 * scan) + vec3(0.24, 0.88, 1.0) * bars * 0.28 * scan;
	}
	EMISSION = e + c * fill_color * fill * inner;
#ifdef WALL_ALPHA
	ALPHA = a;
#endif
}
