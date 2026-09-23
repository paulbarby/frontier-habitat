// Library material whose albedo is multiplied by the MultiMesh instance custom colour
// (suit accent per role, cargo per item). Used by presentation/fx_instancer.gd.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vc = false;
uniform int mode = 0;   // 0 multiply by INSTANCE_CUSTOM.rgb, 1 skin tone, 2 hair colour (both by INSTANCE_CUSTOM.a)

varying vec3 tint;

vec3 palette5(float v, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e) {
	float x = clamp(v, 0.0, 0.999) * 4.0;
	int i = int(x);
	float f = fract(x);
	vec3 p0 = i == 0 ? a : (i == 1 ? b : (i == 2 ? c : d));
	vec3 p1 = i == 0 ? b : (i == 1 ? c : (i == 2 ? d : e));
	return mix(p0, p1, f);
}

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	// Instances that never set custom data read zero: treat that as "no tint".
	if (dot(tint, tint) < 0.0001) {
		tint = vec3(1.0);
	}
	if (mode == 1) {
		// Linear skin tones, dark to light; albedo is replaced, not multiplied.
		tint = palette5(INSTANCE_CUSTOM.a, vec3(0.26, 0.09, 0.02), vec3(0.56, 0.24, 0.06), vec3(0.75, 0.42, 0.14), vec3(0.88, 0.55, 0.21), vec3(1.0, 0.71, 0.42)) / max(albedo.rgb, vec3(0.05));
	} else if (mode == 2) {
		tint = palette5(fract(INSTANCE_CUSTOM.a * 3.7), vec3(0.02, 0.012, 0.008), vec3(0.07, 0.03, 0.02), vec3(0.15, 0.06, 0.02), vec3(0.36, 0.19, 0.1), vec3(0.69, 0.53, 0.25)) / max(albedo.rgb, vec3(0.05));
	}
	if (use_vc) {
		tint *= COLOR.rgb;
	}
}

void fragment() {
	ALBEDO = albedo.rgb * tint;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
