extends Node3D
## GPU particles (RENDER). Each effect kind is ONE MultiMesh of camera-facing quads; each
## instance is one particle whose whole motion is computed in the vertex shader from its
## seed and the time (shaders/particles_inc.gdshaderinc). The CPU writes a slot once when
## an emitter starts, so smoke, steam, sparks and dust cost no per-frame script work.
## Kinds: smoke, smoke_dark, steam, spray, sparks, sparks_idle, dust, pulse, plume,
## dust_ring, site_sparks, site_dust; plus the camera dust field, the storm field and the
## lamp halos / beacons.

const MIX = preload("res://shaders/particles_mix.gdshader")
const ADD = preload("res://shaders/particles_add.gdshader")
const GLOW = preload("res://shaders/glow_sprite.gdshader")

const KINDS := {
	"smoke": {"add": false, "cap": 320, "per": 20, "life": 6.0, "dir": Vector3(0, 1, 0), "spread": 0.18, "speed": [0.5, 1.0], "gravity": Vector3(0, 0.12, 0), "size": [0.45, 2.8], "c0": Color(0.36, 0.33, 0.31, 0.5), "c1": Color(0.6, 0.55, 0.5, 0.0), "wind": 0.45, "r": 0.2},
	"smoke_dark": {"add": false, "cap": 160, "per": 18, "life": 5.0, "dir": Vector3(0, 1, 0), "spread": 0.25, "speed": [0.6, 1.2], "gravity": Vector3(0, 0.1, 0), "size": [0.6, 3.0], "c0": Color(0.12, 0.11, 0.1, 0.7), "c1": Color(0.3, 0.28, 0.27, 0.0), "wind": 0.5, "r": 0.4},
	"steam": {"add": false, "cap": 320, "per": 14, "life": 3.0, "dir": Vector3(0, 1, 0), "spread": 0.2, "speed": [0.9, 1.6], "gravity": Vector3(0, 0.2, 0), "size": [0.35, 1.9], "c0": Color(0.95, 0.95, 0.95, 0.42), "c1": Color(1, 1, 1, 0.0), "wind": 0.6, "r": 0.2},
	"spray": {"add": true, "cap": 256, "per": 40, "life": 1.3, "dir": Vector3(0, 1, 0), "spread": 0.35, "speed": [2.5, 4.5], "gravity": Vector3(0, -7.0, 0), "size": [0.09, 0.2], "c0": Color(0.55, 0.8, 1.0, 0.5), "c1": Color(0.7, 0.9, 1.0, 0.0), "wind": 0.2, "r": 0.25},
	"sparks": {"add": true, "cap": 512, "per": 0, "life": 0.9, "dir": Vector3(0, 0.8, 0), "spread": 0.9, "speed": [2.0, 5.5], "gravity": Vector3(0, -9.8, 0), "size": [0.06, 0.03], "c0": Color(1.0, 0.7, 0.3, 1.0), "c1": Color(1.0, 0.35, 0.1, 0.0), "wind": 0.0, "r": 0.3, "stretch": 1.2},
	"sparks_idle": {"add": true, "cap": 160, "per": 10, "life": 0.8, "dir": Vector3(0, 0.6, 0), "spread": 0.9, "speed": [1.5, 3.5], "gravity": Vector3(0, -9.8, 0), "size": [0.05, 0.02], "c0": Color(1.0, 0.75, 0.35, 1.0), "c1": Color(1.0, 0.4, 0.1, 0.0), "wind": 0.0, "r": 0.4, "stretch": 1.2},
	"dust": {"add": false, "cap": 400, "per": 0, "life": 2.8, "dir": Vector3(0, 0.25, 0), "spread": 1.0, "speed": [0.8, 2.6], "gravity": Vector3(0, -0.25, 0), "size": [0.5, 2.6], "c0": Color(0.66, 0.46, 0.32, 0.55), "c1": Color(0.72, 0.53, 0.38, 0.0), "wind": 0.5, "r": 0.8},
	"pulse": {"add": true, "cap": 24, "per": 3, "life": 1.8, "dir": Vector3(0, 1, 0), "spread": 0.0, "speed": [0.0, 0.0], "gravity": Vector3.ZERO, "size": [0.8, 3.6], "c0": Color(0.55, 0.85, 1.0, 0.9), "c1": Color(0.4, 0.7, 1.0, 0.0), "wind": 0.0, "r": 0.01},
	"plume": {"add": true, "cap": 160, "per": 36, "life": 0.55, "dir": Vector3(0, -1, 0), "spread": 0.08, "speed": [9.0, 15.0], "gravity": Vector3.ZERO, "size": [0.9, 2.4], "c0": Color(0.75, 0.9, 1.0, 0.9), "c1": Color(1.0, 0.55, 0.3, 0.0), "wind": 0.0, "r": 0.5},
	"dust_ring": {"add": false, "cap": 320, "per": 60, "life": 2.4, "dir": Vector3(0, 0.12, 0), "spread": 0.1, "speed": [0.2, 0.6], "gravity": Vector3(0, -0.1, 0), "size": [1.2, 4.5], "c0": Color(0.66, 0.47, 0.33, 0.6), "c1": Color(0.72, 0.55, 0.4, 0.0), "wind": 0.3, "r": 3.0, "spawn": 1, "radial": 9.0},
	"site_sparks": {"add": true, "cap": 400, "per": 14, "life": 0.7, "dir": Vector3(0, 0.7, 0), "spread": 0.9, "speed": [1.5, 3.5], "gravity": Vector3(0, -9.8, 0), "size": [0.05, 0.02], "c0": Color(1.0, 0.8, 0.4, 1.0), "c1": Color(1.0, 0.45, 0.15, 0.0), "wind": 0.0, "r": 1.0, "spawn": 1, "stretch": 1.2},
	# V3 hazards (fx_hazards.gd). "yaw": INSTANCE_CUSTOM.w turns the direction per emitter.
	"air_jet": {"add": false, "cap": 240, "per": 24, "life": 0.9, "dir": Vector3(1, 0.12, 0), "spread": 0.1, "speed": [6.0, 11.0], "gravity": Vector3(0, 0.4, 0), "size": [0.12, 1.7], "c0": Color(0.96, 0.98, 1.0, 0.7), "c1": Color(1, 1, 1, 0.0), "wind": 0.3, "r": 0.12, "yaw": 1},
	"debris": {"add": false, "cap": 480, "per": 0, "life": 2.4, "dir": Vector3(0, 1, 0), "spread": 0.85, "speed": [7.0, 21.0], "gravity": Vector3(0, -9.0, 0), "size": [0.3, 0.2], "c0": Color(0.16, 0.12, 0.1, 1.0), "c1": Color(0.24, 0.17, 0.13, 0.9), "wind": 0.0, "r": 1.0},
	"impact_dust": {"add": false, "cap": 420, "per": 0, "life": 7.0, "dir": Vector3(0, 0.3, 0), "spread": 1.0, "speed": [1.5, 7.0], "gravity": Vector3(0, -0.25, 0), "size": [1.5, 10.0], "c0": Color(0.6, 0.42, 0.29, 0.75), "c1": Color(0.7, 0.52, 0.38, 0.0), "wind": 0.6, "r": 2.0, "radial": 7.0},
	"fire": {"add": true, "cap": 240, "per": 0, "life": 0.8, "dir": Vector3(0, 1, 0), "spread": 1.0, "speed": [2.0, 9.0], "gravity": Vector3(0, 1.5, 0), "size": [1.4, 4.5], "c0": Color(1.0, 0.86, 0.55, 1.0), "c1": Color(1.0, 0.28, 0.05, 0.0), "wind": 0.0, "r": 1.0},
	"devil": {"add": false, "cap": 320, "per": 40, "life": 3.2, "dir": Vector3(0, 1, 0), "spread": 0.22, "speed": [3.0, 8.0], "gravity": Vector3(0, -0.4, 0), "size": [0.7, 4.0], "c0": Color(0.64, 0.46, 0.32, 0.42), "c1": Color(0.7, 0.52, 0.38, 0.0), "wind": 0.8, "r": 2.5},
	"site_dust": {"add": false, "cap": 240, "per": 8, "life": 3.2, "dir": Vector3(0, 0.3, 0), "spread": 0.6, "speed": [0.3, 0.9], "gravity": Vector3(0, -0.05, 0), "size": [0.5, 2.0], "c0": Color(0.66, 0.47, 0.33, 0.38), "c1": Color(0.72, 0.55, 0.4, 0.0), "wind": 0.5, "r": 1.0, "spawn": 1},
}

var view
var quality := 2
var pools := {}          # kind -> {mm, mmi, mat, cap, free: [], burst_i, burst_lo, wind}
var emitters := {}       # key -> {kind, slots: [], pos, inten, radius, seeds}
var _now := 0.0
var _rng := RandomNumberGenerator.new()
var _field: MultiMeshInstance3D
var _field_mat: ShaderMaterial
var _storm: MultiMeshInstance3D
var _storm_mat: ShaderMaterial
var _glow: MultiMeshInstance3D
var _glow_mat: ShaderMaterial
var _lamp_sig := ""
var wind_storm := 0.0      # V3 wind storm 0..1 (fx_hazards): fast pale dust sheets
const HUGE_AABB := AABB(Vector3(-800, -100, -800), Vector3(2600, 500, 2600))

func setup(v) -> void:
	view = v
	_rng.seed = 90210
	_field = _make_field(900, Color(0.78, 0.6, 0.45, 0.35), 0.035, 0.06, 0.0)
	_field_mat = _field.material_override
	_storm = _make_field(1800, Color(0.72, 0.5, 0.34, 0.55), 0.1, 0.1, 6.0)
	_storm_mat = _storm.material_override
	_storm_mat.set_shader_parameter("field_size", Vector3(90, 24, 90))
	_glow = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = 0
	_glow.multimesh = mm
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = GLOW
	_glow.material_override = _glow_mat
	_glow.custom_aabb = HUGE_AABB
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_glow)
	set_quality(quality)

func set_quality(q: int) -> void:
	quality = q
	var amount: float = [0.25, 0.5, 0.8, 1.0][clampi(q, 0, 3)]
	if _field_mat != null:
		_field_mat.set_shader_parameter("field_amount", amount * 0.6)
		_storm_mat.set_shader_parameter("field_amount", amount)

func _mult() -> float:
	return [0.35, 0.6, 0.85, 1.0][clampi(quality, 0, 3)]

func _make_field(n: int, col: Color, s0: float, s1: float, stretch: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3.ZERO))
		mm.set_instance_custom_data(i, Color(float(i) / n, 1.0, -1.0, 0.0))
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = MIX
	m.set_shader_parameter("field", 1.0)
	m.set_shader_parameter("size0", s0)
	m.set_shader_parameter("size1", s1)
	m.set_shader_parameter("color0", col)
	m.set_shader_parameter("color1", col)
	m.set_shader_parameter("stretch", stretch)
	m.set_shader_parameter("light_amt", 0.0)
	mmi.material_override = m
	mmi.custom_aabb = HUGE_AABB
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func _pool(kind: String) -> Dictionary:
	if pools.has(kind):
		return pools[kind]
	var k: Dictionary = KINDS[kind]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	var cap: int = int(k["cap"])
	mm.instance_count = cap
	for i in cap:
		mm.set_instance_transform(i, _off())
		mm.set_instance_custom_data(i, Color(0, 0, -1, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = HUGE_AABB
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = ADD if bool(k["add"]) else MIX
	m.set_shader_parameter("life", k["life"])
	m.set_shader_parameter("dir", k["dir"])
	m.set_shader_parameter("spread", k["spread"])
	m.set_shader_parameter("speed_min", k["speed"][0])
	m.set_shader_parameter("speed_max", k["speed"][1])
	m.set_shader_parameter("gravity", k["gravity"])
	m.set_shader_parameter("size0", k["size"][0])
	m.set_shader_parameter("size1", k["size"][1])
	m.set_shader_parameter("color0", k["c0"])
	m.set_shader_parameter("color1", k["c1"])
	m.set_shader_parameter("spawn", int(k.get("spawn", 0)))
	m.set_shader_parameter("stretch", float(k.get("stretch", 0.0)))
	m.set_shader_parameter("radial", float(k.get("radial", 0.0)))
	m.set_shader_parameter("yaw_dir", int(k.get("yaw", 0)))
	m.render_priority = 3
	mmi.material_override = m
	add_child(mmi)
	# Continuous emitters take slots from the bottom; the top quarter is a ring buffer
	# for bursts (all of it for burst-only kinds).
	var cont: int = cap - cap / 4 if int(k["per"]) > 0 else 0
	var free: Array = []
	for i in range(cont - 1, -1, -1):
		free.append(i)
	pools[kind] = {"mm": mm, "mmi": mmi, "mat": m, "cap": cap, "free": free, "burst_i": cont, "burst_lo": cont, "wind": float(k["wind"])}
	return pools[kind]

func _off() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), Vector3(0, -500, 0))

## Continuous emitter. Same key again only moves it or changes its strength.
func emitter_set(key: String, kind: String, pos: Vector3, intensity: float, yaw: float = 0.0) -> void:
	if not KINDS.has(kind):
		return
	if emitters.has(key):
		var e: Dictionary = emitters[key]
		if e["kind"] == kind:
			if (e["pos"] as Vector3).distance_squared_to(pos) > 0.0004 or absf(float(e["inten"]) - intensity) > 0.05 or absf(float(e.get("yaw", 0.0)) - yaw) > 0.01:
				e["pos"] = pos
				e["inten"] = intensity
				e["yaw"] = yaw
				_write_emitter(e)
			return
		emitter_stop(key)
	var pool: Dictionary = _pool(kind)
	var n: int = maxi(1, int(round(float(KINDS[kind]["per"]) * _mult())))
	var slots: Array = []
	for i in n:
		if (pool["free"] as Array).is_empty():
			break
		slots.append((pool["free"] as Array).pop_back())
	var e2 := {"kind": kind, "slots": slots, "pos": pos, "inten": intensity, "radius": float(KINDS[kind]["r"]), "seeds": [], "yaw": yaw}
	for i in slots.size():
		e2["seeds"].append(_rng.randf())
	emitters[key] = e2
	_write_emitter(e2)

func _write_emitter(e: Dictionary) -> void:
	var pool: Dictionary = pools[e["kind"]]
	var mm: MultiMesh = pool["mm"]
	var r: float = maxf(0.01, float(e["radius"]))
	var xf := Transform3D(Basis.from_scale(Vector3(r, r, r)), e["pos"])
	for i in (e["slots"] as Array).size():
		var slot: int = e["slots"][i]
		mm.set_instance_transform(slot, xf)
		mm.set_instance_custom_data(slot, Color(e["seeds"][i], e["inten"], -1.0, float(e.get("yaw", 0.0))))

func emitter_radius(key: String, r: float) -> void:
	if emitters.has(key) and absf(float(emitters[key]["radius"]) - r) > 0.01:
		emitters[key]["radius"] = r
		_write_emitter(emitters[key])

func emitter_stop(key: String) -> void:
	if not emitters.has(key):
		return
	var e: Dictionary = emitters[key]
	var pool: Dictionary = pools[e["kind"]]
	for slot in e["slots"]:
		(pool["mm"] as MultiMesh).set_instance_transform(slot, _off())
		(pool["free"] as Array).append(slot)
	emitters.erase(key)

## One-shot particles (dust puff, sparks shower).
func burst(kind: String, pos: Vector3, n: int, radius: float = -1.0, yaw: float = 0.0) -> void:
	if not KINDS.has(kind):
		return
	var pool: Dictionary = _pool(kind)
	var mm: MultiMesh = pool["mm"]
	var lo: int = pool["burst_lo"]
	var cap: int = pool["cap"]
	var r: float = float(KINDS[kind]["r"]) if radius < 0.0 else radius
	var xf := Transform3D(Basis.from_scale(Vector3(r, r, r)), pos)
	for i in int(n * _mult()):
		var slot: int = pool["burst_i"]
		pool["burst_i"] = lo + ((slot - lo + 1) % maxi(1, cap - lo))
		mm.set_instance_transform(slot, xf)
		mm.set_instance_custom_data(slot, Color(_rng.randf(), 1.0, _now - _rng.randf() * 0.1, yaw))

## Construction sites: sparks at the build line, dust at the base.
func site_start(id: int, origin: Vector3, radius: float) -> void:
	emitter_set("site%d_d" % id, "site_dust", origin + Vector3(0, 0.2, 0), 1.0)
	emitter_radius("site%d_d" % id, radius + 0.8)

func site_update(id: int, build_y: float, active: bool) -> void:
	var key := "site%d_s" % id
	if not active:
		emitter_stop(key)
		return
	var d: Dictionary = emitters.get("site%d_d" % id, {})
	if d.is_empty():
		return
	var o: Vector3 = d["pos"]
	emitter_set(key, "site_sparks", Vector3(o.x, build_y, o.z), 1.0)
	emitter_radius(key, maxf(0.6, float(d["radius"]) - 1.3))

func site_stop(id: int) -> void:
	emitter_stop("site%d_d" % id)
	emitter_stop("site%d_s" % id)

## Lamp halos (steady) and beacons (blinking). Rebuilt only when the list changes.
func set_lamps(glows: Array, beacons: Array) -> void:
	var sig := "%d:%d" % [glows.size(), beacons.size()]
	for g in glows:
		sig += "%.1f,%.1f;" % [g["pos"].x, g["pos"].z]
	for g in beacons:
		sig += "%.1f,%.1f,%.1f;" % [g["pos"].x, g["pos"].z, g["rate"]]
	if sig == _lamp_sig:
		return
	_lamp_sig = sig
	var mm: MultiMesh = _glow.multimesh
	mm.instance_count = glows.size() + beacons.size()
	var i := 0
	for g in glows:
		mm.set_instance_transform(i, Transform3D(Basis(), g["pos"]))
		mm.set_instance_color(i, g["color"])
		mm.set_instance_custom_data(i, Color(0.0, 0.0, float(g.get("size", 1.0)), 1.0))
		i += 1
	for g in beacons:
		mm.set_instance_transform(i, Transform3D(Basis(), g["pos"]))
		mm.set_instance_color(i, g["color"])
		mm.set_instance_custom_data(i, Color(_rng.randf(), float(g.get("rate", 1.0)), float(g.get("size", 1.0)), 1.4))
		i += 1

func sync(delta: float, sim_dt: float, cam: Camera3D, focus: Vector3, wind: float, night: float, storm: float, sun_dir: Vector3) -> void:
	_now += delta
	var wv := Vector3(0.83, 0.0, 0.55) * (0.4 + wind * 0.35)
	var light := Color(1.0, 0.92, 0.82).lerp(Color(0.32, 0.36, 0.5), night)
	for kind in pools:
		var m: ShaderMaterial = pools[kind]["mat"]
		m.set_shader_parameter("now", _now)
		m.set_shader_parameter("wind", wv * float(pools[kind]["wind"]))
		if not bool(KINDS[kind]["add"]):
			m.set_shader_parameter("light_col", light)
	# Camera dust: a few motes drift through the air near the focus; many in a storm.
	var center: Vector3 = focus + Vector3(0, 4.0, 0)
	_field_mat.set_shader_parameter("now", _now)
	_field_mat.set_shader_parameter("wind", wv * 1.4)
	_field_mat.set_shader_parameter("field_center", center)
	_field_mat.set_shader_parameter("field_size", Vector3(70, 12, 70))
	_field_mat.set_shader_parameter("color0", Color(0.8, 0.62, 0.46, 0.28 * (1.0 - night * 0.6)))
	_field.visible = quality >= 1
	var st2: float = maxf(storm, wind_storm)
	_storm.visible = st2 > 0.02
	if _storm.visible:
		# A wind storm: paler, thinner sheets that race by; a dust storm: thick orange dust.
		var ws: float = wind_storm / maxf(st2, 0.001) if wind_storm > storm else 0.0
		_storm_mat.set_shader_parameter("now", _now)
		_storm_mat.set_shader_parameter("wind", Vector3(0.83, -0.05, 0.55) * lerpf(14.0, 26.0, ws))
		_storm_mat.set_shader_parameter("field_center", center)
		var c0: Color = Color(0.74, 0.52, 0.36, 0.5 * st2).lerp(Color(0.86, 0.72, 0.58, 0.32 * st2), ws)
		_storm_mat.set_shader_parameter("color0", c0.lerp(Color(0.2, 0.16, 0.14, c0.a), night))
		_storm_mat.set_shader_parameter("field_amount", st2 * lerpf(1.0, 0.7, ws) * [0.25, 0.5, 0.8, 1.0][clampi(quality, 0, 3)])
	_glow_mat.set_shader_parameter("now", _now)
	_glow_mat.set_shader_parameter("night", night)
