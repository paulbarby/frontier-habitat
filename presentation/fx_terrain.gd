extends Node3D
## Terrain (RENDER): the playable heightfield from sim.world plus a far ring of hills to
## the horizon, the layered terrain shader, splat and ground textures, rocks, pebble
## scatter and footpaths that wear in where colonists really walk.
## Reads sim.world and sim.state only.

const Models = preload("res://presentation/models.gd")
const Rng = preload("res://sim/rng.gd")
const SHADER = preload("res://shaders/terrain.gdshader")
const TEX := "res://assets/textures/terrain/"

var sim
var inst                      # shared fx_instancer
var mat: ShaderMaterial
var mesh_inst: MeshInstance3D
var splat_img: Image
var splat_tex: ImageTexture
var ground_data := PackedByteArray()   # RGBA8, GN x GN
var ground_img: Image
var ground_tex: ImageTexture
var GN := 256
var quality := 2
var overlay_walk := false
var _wear := PackedFloat32Array()
var _active := {}             # cell index -> true (cells with wear)
var _last := {}               # agent id -> Vector2
var _clock := 0.0
var _dirty := false
var _pebbles: Array = []      # [{mm, mmi, xf: Array, cell: {}}]
var _peb_hidden := {}         # "k:i" -> true
var _peb_grid := {}           # cell key -> [[k, i], ...]
var _contact_sig := ""
var _walk_rev := -1
var rock_handles: Array = []
var _tab := PackedFloat32Array()   # 256 x 256 random lattice for visual-only noise
var timings := {}

func build(s, instancer, q: int) -> void:
	sim = s
	inst = instancer
	quality = q
	GN = int(sim.world.size)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.state.get("seed", 1001)) * 7919 + 17
	_tab.resize(65536)
	for i in 65536:
		_tab[i] = rng.randf()
	var t0: int = Time.get_ticks_usec()
	_build_mesh()
	var t1: int = Time.get_ticks_usec()
	_build_splat()
	var t2: int = Time.get_ticks_usec()
	_build_ground()
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	for n in ["sand", "gravel", "rock", "ore"]:
		mat.set_shader_parameter("alb_" + n, load(TEX + n + "_albedo.png"))
	mat.set_shader_parameter("nrm_a", load(TEX + "nrm_a.png"))
	mat.set_shader_parameter("nrm_b", load(TEX + "nrm_b.png"))
	mat.set_shader_parameter("macro", load(TEX + "macro.png"))
	mat.set_shader_parameter("splat", splat_tex)
	mat.set_shader_parameter("ground", ground_tex)
	mat.set_shader_parameter("map_size", Vector2(GN, GN))
	mat.set_shader_parameter("tint", _planet_tint())
	mesh_inst.material_override = mat
	var t3: int = Time.get_ticks_usec()
	_build_rocks()
	_build_pebbles()
	var t4: int = Time.get_ticks_usec()
	_preseed_paths()
	var t5: int = Time.get_ticks_usec()
	set_quality(q)
	timings = {"mesh_ms": (t1 - t0) / 1000.0, "splat_ms": (t2 - t1) / 1000.0, "rocks_ms": (t4 - t3) / 1000.0, "paths_ms": (t5 - t4) / 1000.0}

func _planet_tint() -> Color:
	match String(sim.state.get("planet", "dry")):
		"cold": return Color(0.78, 0.8, 0.86)
		"airless": return Color(0.62, 0.62, 0.64)
	return Color(1, 1, 1)

func set_quality(q: int) -> void:
	quality = q
	if mat != null:
		mat.set_shader_parameter("detail", 1.0 if q >= 2 else 0.0)
	var frac: float = [0.0, 0.35, 0.7, 1.0][clampi(q, 0, 3)]
	for p in _pebbles:
		var mm: MultiMesh = p["mm"]
		mm.visible_instance_count = int(round(mm.instance_count * frac))
		(p["mmi"] as MultiMeshInstance3D).visible = frac > 0.0

# ---------------------------------------------------------------- mesh
func _axis() -> PackedFloat32Array:
	var xs := PackedFloat32Array()
	var steps := [2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0, 64.0, 96.0, 128.0, 160.0]
	var neg: Array = []
	var x := 0.0
	for s in steps:
		x -= s
		neg.push_front(x)
	for v in neg:
		xs.append(v)
	var hstep: float = sim.world.hstep
	for i in sim.world.hn:
		xs.append(i * hstep)
	x = float(GN)
	for s in steps:
		x += s
		xs.append(x)
	return xs

func height(x: float, z: float) -> float:
	var w = sim.world
	var inside: bool = x >= 0.0 and z >= 0.0 and x <= GN and z <= GN
	var hb: float = w.height_at(clampf(x, 0.0, GN), clampf(z, 0.0, GN))
	if inside:
		return hb
	var dx: float = maxf(maxf(-x, x - GN), 0.0)
	var dz: float = maxf(maxf(-z, z - GN), 0.0)
	var d: float = sqrt(dx * dx + dz * dz)
	var ramp: float = smoothstep(0.0, 160.0, d)
	var seed: int = int(sim.state.get("seed", 1001))
	var hills: float = _fbm(x / 170.0, z / 170.0, seed) * 46.0 + _fbm(x / 60.0, z / 60.0, seed + 7) * 9.0 - 12.0
	var mesa: float = smoothstep(0.62, 0.7, _fbm(x / 260.0, z / 260.0, seed + 13)) * 22.0
	return hb + (hills + mesa) * ramp + _fbm(x / 23.0, z / 23.0, seed + 3) * 2.0 * smoothstep(0.0, 30.0, d)

func _vnoise(x: float, y: float, seed: int) -> float:
	var ix: int = int(floor(x))
	var iy: int = int(floor(y))
	var fx: float = x - ix
	var fy: float = y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var o: int = seed * 97
	var a: float = _tab[((iy + o) & 255) * 256 + ((ix + o * 3) & 255)]
	var b: float = _tab[((iy + o) & 255) * 256 + ((ix + 1 + o * 3) & 255)]
	var c: float = _tab[((iy + 1 + o) & 255) * 256 + ((ix + o * 3) & 255)]
	var d: float = _tab[((iy + 1 + o) & 255) * 256 + ((ix + 1 + o * 3) & 255)]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)

func _fbm(x: float, y: float, seed: int) -> float:
	var s := 0.0
	var a := 0.5
	for o in 3:
		s += _vnoise(x, y, seed + o * 31) * a
		x *= 2.03
		y *= 2.03
		a *= 0.5
	return s / 0.875

func _build_mesh() -> void:
	var xs: PackedFloat32Array = _axis()
	var n: int = xs.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			var hv: float = height(xs[i], xs[j])
			hs[j * n + i] = hv
			verts[j * n + i] = Vector3(xs[i], hv, xs[j])
	for j in n:
		for i in n:
			var i0: int = maxi(0, i - 1)
			var i1: int = mini(n - 1, i + 1)
			var j0: int = maxi(0, j - 1)
			var j1: int = mini(n - 1, j + 1)
			var dx: float = (hs[j * n + i1] - hs[j * n + i0]) / maxf(0.01, xs[i1] - xs[i0])
			var dz: float = (hs[j1 * n + i] - hs[j0 * n + i]) / maxf(0.01, xs[j1] - xs[j0])
			norms[j * n + i] = Vector3(-dx, 1.0, -dz).normalized()
	for j in n - 1:
		for i in n - 1:
			var a: int = j * n + i
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.name = "Terrain"
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)

# ---------------------------------------------------------------- splat (0.5 m per pixel)
func _build_splat() -> void:
	var sn: int = GN * 2
	var data := PackedByteArray()
	data.resize(sn * sn * 4)
	for i in sn * sn:
		data[i * 4 + 0] = 0
		data[i * 4 + 1] = 0
		data[i * 4 + 2] = 128
		data[i * 4 + 3] = 128
	var seed: int = int(sim.state.get("seed", 1001))
	var rng := {"c": Rng.stream_seed(seed, 9101)}
	var wind := Vector2(0.83, 0.55)
	# Ore fields.
	for d in sim.state["deposits"]:
		var c := Vector2(float(d["x"]), float(d["y"]))
		var r: float = float(d["r"])
		_paint(data, sn, c, r * 1.6, func(p: Vector2, px: Array):
			var t: float = p.distance_to(c) / r
			var nz: float = _vnoise(p.x * 0.35, p.y * 0.35, seed + 5) * 0.5
			var v: float = clampf(1.35 - t + nz - 0.25, 0.0, 1.0)
			px[0] = maxi(px[0], int(v * 255.0)))
	# Rocks: outcrop debris and wind streaks behind them.
	for rk in sim.world.rocks:
		var c := Vector2(float(rk["x"]), float(rk["y"]))
		var r: float = float(rk["r"])
		_paint(data, sn, c, r * 2.6, func(p: Vector2, px: Array):
			var t: float = p.distance_to(c) / r
			px[1] = maxi(px[1], int(clampf(1.6 - t * 0.6, 0.0, 1.0) * 200.0)))
		var len: float = r * (5.0 + Rng.next_float(rng, "c") * 4.0)
		var bright: bool = Rng.next_float(rng, "c") > 0.4
		_paint_streak(data, sn, c + wind * r * 0.8, wind, len, r * 0.9, 0.16 if bright else -0.12)
	# Craters: deterministic from the seed, away from the landing zone and the deposits.
	var center: Vector2 = sim.world.center
	var guard := 0
	var made := 0
	var want: int = 34
	while made < want and guard < 400:
		guard += 1
		var big: bool = made < 3
		var r: float = Rng.range_float(rng, "c", 14.0, 24.0) if big else Rng.range_float(rng, "c", 1.8, 7.5)
		var p := Vector2(Rng.range_float(rng, "c", 10.0, GN - 10.0), Rng.range_float(rng, "c", 10.0, GN - 10.0))
		if p.distance_to(center) < 40.0 + r:
			continue
		var ok := true
		for d in sim.state["deposits"]:
			if p.distance_to(Vector2(float(d["x"]), float(d["y"]))) < float(d["r"]) + r + 4.0:
				ok = false
		if not ok:
			continue
		made += 1
		var depth: float = 0.55 if not big else 0.28
		_paint(data, sn, p, r * 1.9, func(q: Vector2, px: Array):
			var t: float = q.distance_to(p) / r
			var hgt := 0.0
			if t < 1.0:
				hgt = -depth * (1.0 - t * t)
			hgt += 0.32 * exp(-pow((t - 1.0) / 0.22, 2.0))
			hgt += 0.06 * exp(-pow((t - 1.35) / 0.3, 2.0))
			var v: int = clampi(int(128.0 + hgt * 127.0), 0, 255)
			if absf(v - 128) > absf(px[3] - 128):
				px[3] = v
			if t > 0.9 and t < 1.7:
				px[1] = maxi(px[1], int(90.0 * (1.0 - absf(t - 1.2) / 0.5))))
		if not big:
			_paint_streak(data, sn, p + wind * r * 1.2, wind, r * 5.0, r * 0.8, 0.13)
	splat_img = Image.create_from_data(sn, sn, false, Image.FORMAT_RGBA8, data)
	splat_tex = ImageTexture.create_from_image(splat_img)

## Calls fn(point, px[4]) for every splat pixel within `rad` metres of c; px is read/write.
func _paint(data: PackedByteArray, sn: int, c: Vector2, rad: float, fn: Callable) -> void:
	var x0: int = maxi(0, int((c.x - rad) * 2.0))
	var x1: int = mini(sn - 1, int((c.x + rad) * 2.0) + 1)
	var y0: int = maxi(0, int((c.y - rad) * 2.0))
	var y1: int = mini(sn - 1, int((c.y + rad) * 2.0) + 1)
	var px := [0, 0, 0, 0]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2((x + 0.5) * 0.5, (y + 0.5) * 0.5)
			if p.distance_to(c) > rad:
				continue
			var k: int = (y * sn + x) * 4
			px[0] = data[k]
			px[1] = data[k + 1]
			px[2] = data[k + 2]
			px[3] = data[k + 3]
			fn.call(p, px)
			data[k] = px[0]
			data[k + 1] = px[1]
			data[k + 2] = px[2]
			data[k + 3] = px[3]

func _paint_streak(data: PackedByteArray, sn: int, start: Vector2, dir: Vector2, length: float, width: float, amount: float) -> void:
	var c: Vector2 = start + dir * length * 0.5
	var side := Vector2(-dir.y, dir.x)
	_paint(data, sn, c, length * 0.55 + width, func(p: Vector2, px: Array):
		var rel: Vector2 = p - start
		var along: float = rel.dot(dir) / length
		if along < 0.0 or along > 1.0:
			return
		var across: float = absf(rel.dot(side)) / (width * (1.0 - along * 0.8))
		if across > 1.0:
			return
		var v: float = amount * (1.0 - along) * (1.0 - across * across)
		px[2] = clampi(int(px[2] + v * 255.0), 0, 255))

# ---------------------------------------------------------------- ground (1 m per pixel)
func _build_ground() -> void:
	ground_data.resize(GN * GN * 4)
	ground_data.fill(0)
	_wear.resize(GN * GN)
	_wear.fill(0.0)
	ground_img = Image.create_from_data(GN, GN, false, Image.FORMAT_RGBA8, ground_data)
	ground_tex = ImageTexture.create_from_image(ground_img)

func _upload() -> void:
	ground_img.set_data(GN, GN, false, Image.FORMAT_RGBA8, ground_data)
	ground_tex.update(ground_img)

## Contact shadow (B) and churned ground (A) from the structures. Cheap enough to redo
## whenever a structure appears, changes state or goes.
func update_contact(blds: Dictionary) -> void:
	var sig := ""
	for id in blds:
		var b: Dictionary = blds[id]
		sig += "%d:%s;" % [id, b["state"]]
	if sig == _contact_sig:
		return
	_contact_sig = sig
	for i in GN * GN:
		ground_data[i * 4 + 2] = 0
		ground_data[i * 4 + 3] = 0
	for id in blds:
		var b: Dictionary = blds[id]
		var state: String = b["state"]
		var site: bool = state == "blueprint" or state == "building"
		if b["kind"] == "link":
			if b["def"] != "corridor":
				continue
			_stamp_capsule(b["p0"], b["p1"], 1.2, 2.2, 0.55 if not site else 0.2)
			continue
		var r: float = float(b["radius"])
		var ext: bool = b["kind"] == "exterior"
		var strength: float = 0.4 if ext else 0.72
		if b["def"] == "meridian":
			var dirv := Vector2(cos(float(b["rot"])), sin(float(b["rot"])))
			_stamp_capsule(b["pos"] - dirv * 16.0, b["pos"] + dirv * 16.0, 6.0, 5.0, 0.7)
			_stamp_dug(b["pos"], 20.0, 0.6)
			continue
		if not site:
			_stamp_disc(b["pos"], r * (0.55 if ext else 0.9), 2.4 if not ext else 1.8, strength)
		_stamp_dug(b["pos"], r + (4.0 if site else 1.2), 0.85 if site else 0.25)
	_dirty = true

func _stamp_disc(c: Vector2, r: float, fall: float, strength: float) -> void:
	var x0: int = maxi(0, int(c.x - r - fall))
	var x1: int = mini(GN - 1, int(c.x + r + fall) + 1)
	var y0: int = maxi(0, int(c.y - r - fall))
	var y1: int = mini(GN - 1, int(c.y + r + fall) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var v: float = strength * (1.0 - smoothstep(r, r + fall, d))
			var k: int = (y * GN + x) * 4 + 2
			ground_data[k] = maxi(ground_data[k], int(v * 255.0))

func _stamp_capsule(p0: Vector2, p1: Vector2, r: float, fall: float, strength: float) -> void:
	var x0: int = maxi(0, int(minf(p0.x, p1.x) - r - fall))
	var x1: int = mini(GN - 1, int(maxf(p0.x, p1.x) + r + fall) + 1)
	var y0: int = maxi(0, int(minf(p0.y, p1.y) - r - fall))
	var y1: int = mini(GN - 1, int(maxf(p0.y, p1.y) + r + fall) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2(x + 0.5, y + 0.5)
			var d: float = c.distance_to(Geometry2D.get_closest_point_to_segment(c, p0, p1))
			var v: float = strength * (1.0 - smoothstep(r * 0.6, r + fall, d))
			var k: int = (y * GN + x) * 4 + 2
			ground_data[k] = maxi(ground_data[k], int(v * 255.0))

func _stamp_dug(c: Vector2, r: float, strength: float) -> void:
	var x0: int = maxi(0, int(c.x - r))
	var x1: int = mini(GN - 1, int(c.x + r) + 1)
	var y0: int = maxi(0, int(c.y - r))
	var y1: int = mini(GN - 1, int(c.y + r) + 1)
	var seed: int = int(sim.state.get("seed", 1001))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if d > 1.0:
				continue
			var nz: float = _tab[((y + seed) & 255) * 256 + (x & 255)]
			var v: float = strength * (1.0 - d * d) * (0.55 + 0.45 * nz)
			var k: int = (y * GN + x) * 4 + 3
			ground_data[k] = maxi(ground_data[k], int(v * 255.0))

## Walk overlay: the navigation grid, one cell per metre.
func set_walk_overlay(on: bool) -> void:
	overlay_walk = on
	if mat != null:
		mat.set_shader_parameter("overlay", 1.0 if on else 0.0)
	if on:
		_fill_walk()

func _fill_walk() -> void:
	var rev: int = int(sim.state["rev"]["walk"])
	if rev == _walk_rev:
		return
	_walk_rev = rev
	var grid: AStarGrid2D = sim.nav.grid
	if grid == null:
		return
	for y in GN:
		for x in GN:
			ground_data[(y * GN + x) * 4 + 1] = 255 if grid.is_point_solid(Vector2i(x, y)) else 128
	_dirty = true

# ---------------------------------------------------------------- footpaths
## Colonists outside wear the ground where they walk; unused paths fade over two days.
func update_paths(sim_dt: float) -> void:
	_clock += sim_dt
	if overlay_walk:
		_fill_walk()
	if _clock >= 1.0:
		var dt: float = _clock
		_clock = 0.0
		var agents: Dictionary = sim.state["agents"]
		for id in agents:
			var a: Dictionary = agents[id]
			if a["state"] != "alive" or a["where"] != "out":
				_last.erase(id)
				continue
			var p: Vector2 = a["pos"]
			if _last.has(id):
				var lp: Vector2 = _last[id]
				var d: float = lp.distance_to(p)
				if d > 0.25 and d < 14.0:
					_stamp_line(lp, p, 0.045)
			_last[id] = p
		var decay: float = exp(-dt / 1300.0)
		var gone: Array = []
		for k in _active:
			var w: float = _wear[k] * decay
			_wear[k] = w
			if w < 0.012:
				gone.append(k)
				w = 0.0
			ground_data[k * 4] = int(minf(w, 1.0) * 255.0)
		for k in gone:
			_active.erase(k)
		_dirty = true
	if _dirty:
		_dirty = false
		_upload()

func _stamp_line(a: Vector2, b: Vector2, amount: float) -> void:
	var steps: int = maxi(1, int(ceil(a.distance_to(b))))
	for i in steps + 1:
		var p: Vector2 = a.lerp(b, float(i) / steps)
		_add_wear(int(p.x), int(p.y), amount)
		_add_wear(int(p.x) + 1, int(p.y), amount * 0.25)
		_add_wear(int(p.x) - 1, int(p.y), amount * 0.25)
		_add_wear(int(p.x), int(p.y) + 1, amount * 0.25)
		_add_wear(int(p.x), int(p.y) - 1, amount * 0.25)

func _add_wear(x: int, y: int, amount: float) -> void:
	if x < 0 or y < 0 or x >= GN or y >= GN:
		return
	var k: int = y * GN + x
	_wear[k] = minf(1.0, _wear[k] + amount)
	_active[k] = true

## A loaded colony has walked for days already: lay down the routes from every airlock to
## the exterior structures it serves, so the paths are there on the first frame.
func _preseed_paths() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var doors: Array = []
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active":
			continue
		if bool(sim.bdef(b["def"]).get("airlock", false)) or b["def"] == "lander":
			doors.append(sim.nav.door_pos(b) if b["def"] != "lander" else b["pos"] + Vector2(7.0, 0.0))
	if doors.is_empty():
		return
	var n := 0
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "exterior" or b["state"] != "active" or n >= 40:
			continue
		var best: Vector2 = doors[0]
		for d in doors:
			if (d as Vector2).distance_to(b["pos"]) < best.distance_to(b["pos"]):
				best = d
		if best.distance_to(b["pos"]) > 95.0:
			continue
		var r: Dictionary = sim.nav.path_out(best, b["pos"])
		if not bool(r.get("ok", false)):
			continue
		n += 1
		var pts: Array = r["pts"]
		for i in range(1, pts.size()):
			_stamp_line(pts[i - 1], pts[i], 0.6)
	for k in _active:
		ground_data[k * 4] = int(minf(_wear[k], 1.0) * 255.0)
	_dirty = true

# ---------------------------------------------------------------- rocks and pebbles
func _build_rocks() -> void:
	var i := 0
	for r in sim.world.rocks:
		# Scenery variety (ART-B): some rocks become shelves (rock_d) or pillars (rock_e).
		var v: float = _tab[(i * 37) & 65535]
		i += 1
		var ids: Array = ["rock_%s" % ["a", "b", "c"][int(r["kind"])]]
		if v < 0.18:
			ids.push_front("rock_d")
		elif v < 0.3:
			ids.push_front("rock_e")
		var tpl: Dictionary = Models.prop(ids, float(r["r"]))
		var s: float = float(r["r"]) / 1.1
		var p := Vector2(float(r["x"]), float(r["y"]))
		var xf := Transform3D(Basis(Vector3.UP, float(r["rot"])).scaled(Vector3(s, s * 0.9, s)), Vector3(p.x, height(p.x, p.y) - 0.12 * s, p.y))
		rock_handles.append(inst.add(tpl, xf))
	var rng := {"c": 4242}
	for d in sim.state["deposits"]:
		for k in 9:
			var a: float = Rng.next_float(rng, "c") * TAU
			var rr: float = sqrt(Rng.next_float(rng, "c")) * float(d["r"]) * 0.95
			var p := Vector2(d["x"], d["y"]) + Vector2(cos(a), sin(a)) * rr
			var tpl: Dictionary = Models.prop(["rock_f", "rock_%s" % ["a", "b", "c"][k % 3]] if k % 3 == 0 else ["rock_%s" % ["a", "b", "c"][k % 3]], 1.0)
			var s: float = 0.3 + Rng.next_float(rng, "c") * 0.35
			var xf := Transform3D(Basis(Vector3.UP, a).scaled(Vector3(s, s * 0.8, s)), Vector3(p.x, height(p.x, p.y) - 0.2 * s, p.y))
			rock_handles.append(inst.add(tpl, xf))

func _build_pebbles() -> void:
	var seed: int = int(sim.state.get("seed", 1001))
	var rng := {"c": Rng.stream_seed(seed, 9202)}
	var count: int = 4500
	var per: Array = [[], [], []]
	var center: Vector2 = sim.world.center
	for i in count:
		var p := Vector2(Rng.range_float(rng, "c", 2.0, GN - 2.0), Rng.range_float(rng, "c", 2.0, GN - 2.0))
		var k: int = Rng.range_int(rng, "c", 0, 2)
		var near_rock := false
		for r in sim.world.rocks:
			if p.distance_squared_to(Vector2(r["x"], r["y"])) < 49.0:
				near_rock = true
				break
		# Sparser on the flattened landing zone, denser around rocks.
		var keep: float = 0.35 if p.distance_to(center) < 40.0 else 0.8
		if near_rock:
			keep = 1.0
		if Rng.next_float(rng, "c") > keep:
			continue
		var s: float = 0.05 + pow(Rng.next_float(rng, "c"), 3.0) * (0.35 if near_rock else 0.22)
		var yaw: float = Rng.next_float(rng, "c") * TAU
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, Rng.range_float(rng, "c", -0.4, 0.4))
		var xf := Transform3D(b.scaled(Vector3(s, s * 0.7, s)), Vector3(p.x, height(p.x, p.y) - s * 0.25, p.y))
		(per[k] as Array).append(xf)
	# Stone patches (ART-B "pebbles", 2 x 2 m) round rocks, craters and at random.
	var patches: Array = []
	if Models.has_model("pebbles"):
		var guard := 0
		while patches.size() < 320 and guard < 3000:
			guard += 1
			var p := Vector2(Rng.range_float(rng, "c", 4.0, GN - 4.0), Rng.range_float(rng, "c", 4.0, GN - 4.0))
			var near := false
			for r in sim.world.rocks:
				if p.distance_squared_to(Vector2(r["x"], r["y"])) < 100.0:
					near = true
					break
			if not near and Rng.next_float(rng, "c") > 0.35:
				continue
			if p.distance_to(center) < 30.0 and Rng.next_float(rng, "c") > 0.3:
				continue
			var s: float = Rng.range_float(rng, "c", 0.6, 1.3)
			var b := Basis(Vector3.UP, Rng.next_float(rng, "c") * TAU)
			patches.append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(p.x, height(p.x, p.y) - 0.02, p.y)))
	per.append(patches)
	for k in 4:
		var tpl: Dictionary = Models.prop(["pebbles"], 1.0) if k == 3 else Models.prop(["rock_%s" % ["a", "b", "c"][k]], 1.0)
		if (tpl["parts"] as Array).is_empty() or (per[k] as Array).is_empty():
			continue
		var mesh: Mesh = tpl["parts"][0]["mesh"]
		var pxf: Transform3D = tpl["parts"][0]["xf"]
		if k < 3:
			# Small pebbles: a 20-triangle faceted stone with the rock material, not the
			# 150-triangle rock model (4 500 of them).
			var pm := StandardMaterial3D.new()
			pm.resource_name = "Pebble"
			pm.albedo_color = [Color(0.4, 0.27, 0.2), Color(0.31, 0.23, 0.19), Color(0.5, 0.36, 0.26)][k]
			pm.roughness = 0.92
			mesh = _pebble_mesh(k, pm)
			pxf = Transform3D.IDENTITY
		var xfs: Array = per[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, (xfs[i] as Transform3D) * pxf)
			var key := "%d:%d" % [int((xfs[i] as Transform3D).origin.x / 8.0), int((xfs[i] as Transform3D).origin.z / 8.0)]
			if not _peb_grid.has(key):
				_peb_grid[key] = []
			(_peb_grid[key] as Array).append([_pebbles.size(), i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Pebbles%d" % k
		if k == 3:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_pebbles.append({"mm": mm, "mmi": mmi, "xf": xfs})

## A jittered icosahedron, flat shaded: 12 vertices, 20 faces, about 1 m across.
func _pebble_mesh(k: int, mat: Material) -> ArrayMesh:
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var v: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001 + k * 31
	for i in v.size():
		var p: Vector3 = (v[i] as Vector3).normalized() * rng.randf_range(0.75, 1.15)
		v[i] = Vector3(p.x * 0.55, maxf(p.y * 0.36, -0.12), p.z * 0.5 * rng.randf_range(0.8, 1.2))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var n: Vector3 = (b - a).cross(c - a).normalized()
		if n.dot((a + b + c) / 3.0) < 0.0:
			n = -n
			var tmp: Vector3 = b
			b = c
			c = tmp
		for q in [a, c, b]:
			st.set_normal(n)
			st.add_vertex(q)
	if mat != null:
		st.set_material(mat)
	return st.commit()

## Pebbles under a structure or a corridor would poke through the floor: hide them.
func hide_pebbles_under(blds: Dictionary) -> void:
	for id in blds:
		var b: Dictionary = blds[id]
		var shapes: Array = []
		if b["kind"] == "link":
			if b["def"] == "corridor":
				shapes.append([b["p0"], b["p1"], 1.6])
		elif b["def"] == "meridian":
			var dirv := Vector2(cos(float(b["rot"])), sin(float(b["rot"])))
			shapes.append([b["pos"] - dirv * 18.0, b["pos"] + dirv * 18.0, 8.0])
		else:
			shapes.append([b["pos"], b["pos"], float(b["radius"]) + 0.6])
		for sh in shapes:
			var p0: Vector2 = sh[0]
			var p1: Vector2 = sh[1]
			var r: float = sh[2]
			for cx in range(int((minf(p0.x, p1.x) - r) / 8.0) - 1, int((maxf(p0.x, p1.x) + r) / 8.0) + 1):
				for cz in range(int((minf(p0.y, p1.y) - r) / 8.0) - 1, int((maxf(p0.y, p1.y) + r) / 8.0) + 1):
					var key := "%d:%d" % [cx, cz]
					if not _peb_grid.has(key):
						continue
					for e in _peb_grid[key]:
						var hk := "%d:%d" % [e[0], e[1]]
						if _peb_hidden.has(hk):
							continue
						var o: Vector3 = (_pebbles[e[0]]["xf"][e[1]] as Transform3D).origin
						var q := Vector2(o.x, o.z)
						if q.distance_to(Geometry2D.get_closest_point_to_segment(q, p0, p1)) < r:
							_peb_hidden[hk] = true
							(_pebbles[e[0]]["mm"] as MultiMesh).set_instance_transform(e[1], Transform3D(Basis.from_scale(Vector3(0.0001, 0.0001, 0.0001)), o))
