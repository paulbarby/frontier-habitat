// Interior surfaces (RENDER, V3_DESIGN §7.3): the library material of everything inside a
// room (the Interior group, and interior-only materials such as Floor, Wood, Cushion,
// Fabric anywhere) plus a warm FILL light: the rooms' own lamps and cove strips lighting
// the whole room, which the web renderer cannot afford as real lights in every room.
// fill (0..1) is set by models.gd from the time of day; it is modulated by the baked AO so
// corners stay darker. mode 1 = Screen: an animated cyan UI pattern.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

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
uniform float fill = 0.0;
uniform float fill_gain = 1.0;   // floors get more: the lamps light the floor most
uniform int mode = 0;
// ART-HAB J4: the fill falls off towards the wall ring (about 25 % darker at the wall).
// room_r = outer wall radius in model units (set per model by fx_instancer); 0 = no fall-off.
instance uniform float room_r = 0.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_tex) {
		c *= texture(albedo_tex, UV).rgb;
	}
	vec3 ao = use_vc ? COLOR.rgb : vec3(1.0);
	c *= ao;
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = specular;
	vec3 e = emission.rgb * emission_energy;
	if (mode == 1) {
		// Screen: rows of text-like bars that scroll, a slow scan line, a soft frame.
		vec2 q = vec2(lpos.x + lpos.z, lpos.y) * 18.0;
		float row = floor(q.y);
		float bars = step(0.35, fract(q.y)) * step(fract(sin(row * 12.9898 + floor(q.x * 0.5 + TIME * 0.6) * 78.233) * 43758.5453), 0.62);
		float scan = smoothstep(0.0, 0.08, abs(fract(lpos.y * 1.7 - TIME * 0.35) - 0.5));
		vec3 ui = vec3(0.24, 0.88, 1.0);
		// Dark screen (the material colour) with thin glowing UI lines, not a flat slab.
		e = emission.rgb * max(emission_energy, 0.6) * (0.8 + 0.2 * scan) + vec3(0.24, 0.88, 1.0) * bars * 0.28 * scan;
	}
	float fall = 1.0;
	if (room_r > 0.5) {
		fall = 1.0 - 0.25 * smoothstep(room_r * 0.5, room_r * 0.92, length(lpos.xz));
	}
	EMISSION = e + c * fill_color * fill * fill_gain * fall;
}
