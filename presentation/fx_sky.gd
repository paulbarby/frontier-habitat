extends Node3D
## Sky, sun, moonlight, ambient, fog, glow and night lamps (RENDER).
## The time of day is turned into a sun path and a set of colours ONCE per frame here;
## the sky shader (shaders/sky.gdshader) and the post grade only read the result.

const SKY_SHADER = preload("res://shaders/sky.gdshader")

var env: Environment
var we: WorldEnvironment
var key: DirectionalLight3D          # the sun by day, the planet-shine by night
var sky_mat: ShaderMaterial
var sun_dir := Vector3(0, 1, 0)      # toward the sun
var planet_dir := Vector3(0.078, 0.225, -0.97).normalized()
var elev := 45.0                     # sun elevation in degrees
var night := 0.0                     # 0 = day, 1 = full night (lamps, windows)
var storm := 0.0                     # 0..1 dust storm strength (state.events.storm)
var grade := {}                      # read by fx_post
var quality := 2
var planet_name := "dry"
var _lamps: Array = []               # OmniLight3D pool
var _sites: Array = []               # [{pos, color, energy, range}]
var _site_clock := 0.0
var _time := 0.0
var _sky_clock := 0.0
var _cam_dist := 60.0
var reserved := 0                    # real lights taken by interiors (fx_interior)
var aurora := 0.0                    # solar flare 0..1 (fx_hazards)

## Sun elevation keyframes (degrees) -> palette. Colours are sRGB.
const KEYS := [
	{"e": -90.0, "zen": Color("03050c"), "hor": Color("0d111d"), "glow": Color("140f1c"), "ga": 0.0, "sun": Color("ff7a40"), "se": 0.0, "amb": Color("4a5270"), "ae": 0.42, "haze": 0.25},
	{"e": -12.0, "zen": Color("04060f"), "hor": Color("111524"), "glow": Color("201826"), "ga": 0.08, "sun": Color("ff7a40"), "se": 0.0, "amb": Color("4c5472"), "ae": 0.42, "haze": 0.3},
	{"e": -5.0, "zen": Color("121a38"), "hor": Color("463954"), "glow": Color("b8503a"), "ga": 0.55, "sun": Color("ff6a30"), "se": 0.0, "amb": Color("56628c"), "ae": 0.38, "haze": 0.45},
	{"e": 0.0, "zen": Color("2b3356"), "hor": Color("d0805c"), "glow": Color("ff7a3c"), "ga": 1.0, "sun": Color("ff7a42"), "se": 0.3, "amb": Color("927f95"), "ae": 0.42, "haze": 0.6},
	{"e": 6.0, "zen": Color("5f5f78"), "hor": Color("eaa56a"), "glow": Color("ff9a52"), "ga": 0.65, "sun": Color("ffb070"), "se": 0.95, "amb": Color("bf9e8a"), "ae": 0.46, "haze": 0.7},
	{"e": 20.0, "zen": Color("8e7466"), "hor": Color("e6bb90"), "glow": Color("f8d9b0"), "ga": 0.25, "sun": Color("ffe0bc"), "se": 1.45, "amb": Color("bcaea6"), "ae": 0.5, "haze": 0.7},
	{"e": 90.0, "zen": Color("a27f63"), "hor": Color("eac69c"), "glow": Color("f6e6cc"), "ga": 0.1, "sun": Color("fff2df"), "se": 1.65, "amb": Color("c6b7ae"), "ae": 0.52, "haze": 0.65},
]

func build() -> void:
	we = WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8c1aa")
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("dcae88")
	env.fog_light_energy = 1.0
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.25
	we.environment = env
	add_child(we)
	key = DirectionalLight3D.new()
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 140.0
	key.directional_shadow_blend_splits = true
	key.shadow_bias = 0.04
	key.shadow_normal_bias = 1.2
	key.shadow_blur = 1.2
	key.light_angular_distance = 0.6
	add_child(key)
	for i in 8:
		var l := OmniLight3D.new()
		l.omni_range = 9.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		add_child(l)
		park(l)
		_lamps.append(l)
	set_quality(quality)

## V3.1 stall trace: a light that turns visible for the first time costs a 100-150 ms frame in
## the web build (the sunset lamps). Lights are never hidden: an unused one is "parked" (no
## energy, no range, far below the ground).
static func park(l: Light3D) -> void:
	l.light_energy = 0.0
	if l is OmniLight3D:
		(l as OmniLight3D).omni_range = 0.001
	elif l is SpotLight3D:
		(l as SpotLight3D).spot_range = 0.001
	l.position = Vector3(0, -500, 0)
	l.visible = true

static func parked(l: Light3D) -> bool:
	return l.position.y < -400.0

func set_planet(name: String) -> void:
	planet_name = name

func set_quality(q: int) -> void:
	quality = q
	if key == null:
		return
	key.shadow_enabled = q >= 1
	match q:
		1:
			key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
		2:
			key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
		3:
			key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW if q <= 1 else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	env.glow_enabled = q >= 1
	var n: int = [0, 4, 6, 8][clampi(q, 0, 3)]
	for i in _lamps.size():
		if i >= n:
			park(_lamps[i])

## Lamp positions near which real OmniLights may be placed at night.
func set_sites(sites: Array) -> void:
	_sites = sites

## `t` = second of the day, `day_len` and `daylight` from the planet; `focus` = the
## camera target; `cam_dist` its distance.
func update(t: float, day_len: float, daylight: float, delta: float, focus: Vector3, cam_dist: float, wind: float) -> void:
	_time += delta
	_cam_dist = cam_dist
	# --- sun path -------------------------------------------------------------
	var az_off := deg_to_rad(-40.0)
	var h_ang: float
	var e_deg: float
	if t < daylight:
		var s: float = t / daylight
		h_ang = PI * s
		e_deg = 64.0 * sin(PI * s)
		# A little lift at the ends so the sun meets the horizon exactly at sunrise/sunset.
	else:
		var n: float = (t - daylight) / maxf(1.0, day_len - daylight)
		h_ang = PI + PI * n
		e_deg = -28.0 * sin(PI * n)
	elev = e_deg
	var e: float = deg_to_rad(e_deg)
	var hx: float = -cos(h_ang)
	var hz: float = sin(h_ang)
	var hv := Vector2(hx, hz).rotated(az_off)
	sun_dir = Vector3(hv.x * cos(e), sin(e), hv.y * cos(e)).normalized()
	# --- palette --------------------------------------------------------------
	var k: Dictionary = _palette(e_deg)
	night = clampf(1.0 - smoothstep(-7.0, 5.0, e_deg), 0.0, 1.0)
	var st: float = storm
	var zen: Color = k["zen"]
	var hor: Color = k["hor"]
	if st > 0.0:
		var dust := Color("b87a4a").lerp(Color("3a2418"), night)
		zen = zen.lerp(dust.darkened(0.2), st * 0.9)
		hor = hor.lerp(dust, st * 0.9)
	# The sky (and its reflection map) is redrawn at most 15 times a second.
	_sky_clock -= delta
	var sky_now: bool = _sky_clock <= 0.0
	if sky_now:
		_sky_clock = 1.0 / 15.0
	if sky_now:
		_set_sky(k, zen, hor, st)
	# --- key light: sun by day, planet-shine by night -------------------------
	_set_light(k, e_deg, st, cam_dist)
	# --- ambient, fog, glow, exposure ----------------------------------------
	_set_env(k, zen, hor, st, e_deg)
	# --- night lamps near the camera -------------------------------------------
	_update_lamps(delta, focus, cam_dist)

func _set_sky(k: Dictionary, zen: Color, hor: Color, st: float) -> void:
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("sun_col", k["sun"])
	sky_mat.set_shader_parameter("zenith_col", zen)
	sky_mat.set_shader_parameter("horizon_col", hor)
	sky_mat.set_shader_parameter("glow_col", k["glow"])
	sky_mat.set_shader_parameter("glow_amount", k["ga"])
	sky_mat.set_shader_parameter("ground_col", hor.darkened(0.45))
	sky_mat.set_shader_parameter("planet_dir", planet_dir)
	# The planet is lit from the viewer's upper right: a pale gibbous disc at any hour.
	var right: Vector3 = planet_dir.cross(Vector3.UP).normalized()
	sky_mat.set_shader_parameter("planet_light", (-planet_dir * 0.55 + right * 0.7 + Vector3.UP * 0.45).normalized())
	sky_mat.set_shader_parameter("planet_vis", lerpf(0.35, 1.0, clampf(night * 1.4, 0.0, 1.0)) * (1.0 - st))
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("haze", k["haze"])
	sky_mat.set_shader_parameter("storm", st)
	sky_mat.set_shader_parameter("time", _time)
	sky_mat.set_shader_parameter("sun_disc", 1.0 - st)
	sky_mat.set_shader_parameter("aurora", aurora)

func _set_light(k: Dictionary, e_deg: float, st: float, cam_dist: float) -> void:
	var sun_e: float = float(k["se"]) * (1.0 - st * 0.75)
	var moon_e: float = 0.56 * smoothstep(-2.0, -9.0, e_deg) * (1.0 - st * 0.6)
	var dir: Vector3
	var col: Color
	var energy: float
	if sun_e >= moon_e:
		dir = sun_dir
		col = k["sun"]
		energy = sun_e
	else:
		dir = planet_dir
		col = Color("b8c3e0")
		energy = moon_e
	if dir.y < 0.06:
		dir = Vector3(dir.x, 0.06, dir.z).normalized()
	key.look_at_from_position(Vector3.ZERO, -dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD)
	key.light_color = col
	key.light_energy = energy
	# Never hidden (V3.1 stall trace): a frame with no directional light is another shader
	# variant for every material; at the sunset dip (energy about 0) that was one 108-150 ms
	# compile frame. The light stays on with (almost) no energy instead.
	key.visible = true
	key.light_energy = maxf(energy, 0.002)
	key.directional_shadow_max_distance = clampf(cam_dist * (2.0 if quality < 3 else 2.4), 45.0, 520.0)

func _set_env(k: Dictionary, zen: Color, hor: Color, st: float, e_deg: float) -> void:
	env.ambient_light_color = k["amb"] if st <= 0.0 else (k["amb"] as Color).lerp(Color("c08a5e"), st * 0.6)
	env.ambient_light_energy = k["ae"]
	env.fog_light_color = hor.lerp(zen, 0.18).darkened(0.05)
	var fog_d: float = lerpf(0.0026, 0.0019, night)
	# 0.009 at full storm: about half fog at a normal camera distance, so the base stays readable.
	# Zoomed far out over the big map the haze thins, so the whole map stays readable.
	env.fog_density = lerpf(fog_d, 0.009, st) * clampf(120.0 / maxf(_cam_dist, 120.0), 0.22, 1.0)
	env.fog_sun_scatter = lerpf(0.28, 0.0, night)
	env.glow_intensity = lerpf(0.4, 0.95, night)
	env.tonemap_exposure = lerpf(1.0, 1.25, night)
	# --- grade for the post pass ------------------------------------------------
	var dusk: float = clampf(1.0 - absf(e_deg - 1.0) / 12.0, 0.0, 1.0)
	grade = {
		"warm": Color(1.035, 1.0, 0.95).lerp(Color(1.09, 0.98, 0.88), dusk).lerp(Color(0.95, 0.98, 1.06), night),
		"cool": Color(0.95, 0.985, 1.05).lerp(Color(0.9, 0.95, 1.1), dusk).lerp(Color(0.86, 0.93, 1.12), night),
		"contrast": lerpf(1.07, 1.1, night),
		"saturation": lerpf(1.06, 0.92, night) * (1.0 - st * 0.25),
		"vignette": lerpf(0.2, 0.32, night) + st * 0.1,
		"grain": lerpf(0.012, 0.022, night),
		"storm": st,
	}

func _palette(e_deg: float) -> Dictionary:
	var a: Dictionary = KEYS[0]
	var b: Dictionary = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if e_deg >= float(KEYS[i]["e"]) and e_deg <= float(KEYS[i + 1]["e"]):
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var f: float = 0.0
	if float(b["e"]) > float(a["e"]):
		f = clampf((e_deg - float(a["e"])) / (float(b["e"]) - float(a["e"])), 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var out := {}
	for k in a:
		if a[k] is Color:
			out[k] = (a[k] as Color).lerp(b[k], f)
		else:
			out[k] = lerpf(float(a[k]), float(b[k]), f)
	return out

func _update_lamps(delta: float, focus: Vector3, cam_dist: float) -> void:
	var n: int = maxi(0, [0, 4, 6, 8][clampi(quality, 0, 3)] - reserved)
	# (lit by day too, at almost no energy: a lamp that comes into use at dusk costs a 140 ms
	# frame in the web build, V3.1 stall trace)
	if n == 0 or _sites.is_empty():
		for l in _lamps:
			if not parked(l):
				park(l)
		return
	_site_clock -= delta
	if _site_clock <= 0.0:
		_site_clock = 0.25
		var reach: float = clampf(cam_dist * 1.2, 30.0, 110.0)
		var cand: Array = []
		for s in _sites:
			var d: float = (s["pos"] as Vector3).distance_to(focus)
			if d < reach:
				cand.append([d, s])
		cand.sort_custom(func(x, y): return x[0] < y[0])
		for i in n:
			var l: OmniLight3D = _lamps[i]
			if i < cand.size():
				var s: Dictionary = cand[i][1]
				var fade: float = 1.0 - smoothstep(reach * 0.6, reach, float(cand[i][0]))
				l.visible = true
				if parked(l):
					l.light_energy = 0.0
				l.position = s["pos"]
				l.light_color = s["color"]
				l.omni_range = float(s.get("range", 8.0))
				l.set_meta("target", float(s.get("energy", 1.2)) * fade)
			else:
				park(l)
				l.set_meta("target", 0.0)
	for i in n:
		var l: OmniLight3D = _lamps[i]
		if not parked(l):
			var tgt: float = maxf(float(l.get_meta("target", 0.0)) * night, 0.0005)
			l.light_energy = lerpf(l.light_energy, tgt, 1.0 - exp(-delta * 6.0))
