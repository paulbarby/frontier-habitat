// Shared GPU particle logic (RENDER). One MultiMesh per effect kind; every instance is
// one particle. Instance transform: origin = emitter position, basis scale X = spawn
// radius (0.0001 = slot unused). INSTANCE_CUSTOM: x seed, y intensity, z burst start
// time (continuous when < 0), w spare. The CPU writes a slot once; motion is all here.
uniform float now = 0.0;
uniform float life = 2.0;
uniform vec3 dir = vec3(0.0, 1.0, 0.0);
uniform float spread = 0.3;
uniform float speed_min = 0.5;
uniform float speed_max = 1.5;
uniform vec3 gravity = vec3(0.0);
uniform vec3 wind = vec3(0.0);
uniform float size0 = 0.3;
uniform float size1 = 1.0;
uniform vec4 color0 : source_color = vec4(1.0);
uniform vec4 color1 : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform int spawn = 0;          // 0 disc, 1 ring
uniform float stretch = 0.0;    // velocity streaks (sparks, storm)
uniform float fade_in = 0.1;
uniform float field = 0.0;      // 1 = wrap around field_center (camera dust)
uniform vec3 field_center = vec3(0.0);
uniform vec3 field_size = vec3(60.0, 14.0, 60.0);
uniform float field_amount = 1.0;
uniform float radial = 0.0;       // outward speed from the emitter centre (dust rings)

varying vec4 v_col;
varying vec2 v_uv;

float h11(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void particle_vertex(inout vec3 vtx, vec2 uv, mat4 model, vec4 custom, mat4 view_m, out vec4 col) {
	vec3 origin = model[3].xyz;
	float rad = length(model[0].xyz);
	float seed = custom.x;
	float inten = custom.y;
	float age;
	if (custom.z < 0.0) {
		age = fract((now + seed * 17.31 * life) / life);
	} else {
		age = (now - custom.z) / life;
	}
	float alive = step(0.0, age) * step(age, 1.0) * step(0.001, rad);
	float t = age * life;
	vec3 r3 = vec3(h11(seed * 3.1 + 0.7), h11(seed * 5.7 + 1.3), h11(seed * 9.2 + 2.1));
	vec3 p;
	if (field > 0.5) {
		vec3 base = r3 * field_size + wind * now * (0.6 + r3.y * 0.8);
		p = field_center + mod(base - field_center + field_size * 0.5, field_size) - field_size * 0.5;
		p.y = field_center.y + (r3.y - 0.35) * field_size.y + sin(now * 0.7 + seed * 40.0) * 0.4;
		alive = step(seed, field_amount);
		age = 0.5;
	} else {
		float ang = r3.x * 6.2831;
		float rr = spawn == 1 ? rad : rad * sqrt(r3.y);
		vec3 off = vec3(cos(ang) * rr, 0.0, sin(ang) * rr);
		vec3 d = normalize(dir + (r3 - 0.5) * 2.0 * spread);
		float sp = mix(speed_min, speed_max, r3.z);
		vec3 vel = d * sp + (rr > 0.001 ? normalize(off) : vec3(0.0)) * radial * (0.6 + 0.4 * r3.z);
		p = origin + off + vel * t + 0.5 * gravity * t * t + wind * t * (0.4 + r3.y * 0.6);
	}
	float size = mix(size0, size1, age) * (0.7 + 0.6 * r3.z) * max(inten, 0.2);
	col = mix(color0, color1, age);
	col.a *= smoothstep(0.0, fade_in, age) * alive * clamp(inten, 0.0, 1.5);
	vec3 vp = (view_m * vec4(p, 1.0)).xyz;
	vec2 corner = (uv - 0.5) * 2.0;
	if (stretch > 0.0) {
		vec3 vel_v = (view_m * vec4(field > 0.5 ? wind : (dir * mix(speed_min, speed_max, r3.z) + gravity * t), 0.0)).xyz;
		vec2 sd = vel_v.xy;
		float l = length(sd);
		vec2 ax = l > 0.001 ? sd / l : vec2(0.0, 1.0);
		vec2 ay = vec2(-ax.y, ax.x);
		vp += vec3(ax * corner.y * size * (1.0 + stretch * l * 0.25) + ay * corner.x * size * 0.35, 0.0);
	} else {
		vp += vec3(corner * size, 0.0);
	}
	vtx = alive > 0.5 ? vp : vec3(0.0, 0.0, 1.0e6);
}
