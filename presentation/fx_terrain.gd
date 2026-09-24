extends Node3D
## Terrain (RENDER): the playable heightfield from sim.world plus a far ring of hills to
## the horizon, the layered terrain shader, splat and ground textures, rocks, pebble
## scatter and footpaths that wear in where colonists really walk.
## Reads sim.world and sim.state only.
##
## 3.0: the map can be 810 m (V3_DESIGN §1). The heightfield is cut into 128 m CHUNKS with
## four levels of detail (2, 4, 8, 16 m vertex spacing) and skirts that hide the cracks
## between levels. Fine levels are built lazily, one mesh per frame, when the camera comes
## near. Pebbles are per chunk and show only on the finest level. The far ring is four
## strips round the map. Old 256 m saves give 2 x 2 chunks and look as before.

const Models = preload("res://presentation/models.gd")
const Rng = preload("res://sim/rng.gd")
const SHADER = preload("res://shaders/terrain.gdshader")
const TEX := "res://assets/textures/terrain/"
const CHUNK_Q := 64                    # quads per chunk side at the finest level (128 m at 2 m)
const LOD_STRIDE := [1, 2, 4, 8]       # vertex stride per level
const RING_STEPS := [2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0, 64.0, 96.0, 128.0, 160.0]

var sim
var inst                      # shared fx_instancer
var mat: ShaderMaterial
var mesh_inst: Node3D         # parent of every terrain mesh (the "terrain" toggle hides it)
var splat_img: Image
var splat_tex: ImageTexture
var splat_ppm := 2.0          # splat pixels per metre (2 on small maps, 1 on big maps)
var ground_data := PackedByteArray()   # RGBA8, GN x GN
var ground_img: Image
var ground_tex: ImageTexture
var hazard_tex: ImageTexture
var GN := 256
var quality := 2
var overlay_walk := false
var overlay_mode := 0         # 0 none, 1 walk, 2 hazard
var _wear := PackedFloat32Array()
var _active := {}             # cell index -> true (cells with wear)
var _last := {}               # agent id -> Vector2
var _clock := 0.0
var _dirty := false
var _pebbles: Array = []      # [{mm, mmi, xf: Array, chunk}]
var _peb_hidden := {}         # "k:i" -> true
var _peb_grid := {}           # cell key (x * 4096 + z, 8 m cells) -> [[k, i], ...]
var _contact_sig := ""
var _contact_rects: Array = []   # Rect2i stamped last time (cleared before the next stamp)
var _walk_rev := -1
var rock_handles: Array = []
var _tab := PackedFloat32Array()   # 256 x 256 random lattice for visual-only noise
var timings := {}
var _norms := PackedVector3Array() # full-resolution normals of the heightfield
var chunks: Array = []        # [{i0, j0, i1, j1, aabb, lods: [MeshInstance3D|null x4], cur, peb: []}]
var _lod_clock := 0.0
var _rock_grid := {}          # 8 m cell key -> [Vector2 centre, r]
var lod_counts := [0, 0, 0, 0]
# Structure pads (critic round 6): the terrain MESH never rises above a structure's base or a
# corridor's floor. Each pad: {"c": Vector2, "r": float, "y": float} (disc) or
# {"p0", "p1", "r", "y0", "y1"} (corridor capsule). The sim height field is not changed.
const PAD_DROP := 0.06      # terrain stays this far below the structure base
const PAD_SLOPE := 1.5      # metres of rise per metre outside the pad
var _pads: Array = []
var _pad_sig := ""
var _pad_grid := {}         # chunk index -> [pad indices]

func build(s, instancer, q: int) -> void:
	sim = s
	inst = instancer
	quality = q
	GN = int(sim.world.size)
	splat_ppm = 2.0 if GN <= 320 else 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.state.get("seed", 1001)) * 7919 + 17
	_tab.resize(65536)
	for i in 65536:
		_tab[i] = rng.randf()
	for r in sim.world.rocks:
		var key: int = int(float(r["x"]) / 8.0) * 4096 + int(float(r["y"]) / 8.0)
		if not _rock_grid.has(key):
			_rock_grid[key] = []
		(_rock_grid[key] as Array).append(r)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	var t0: int = Time.get_ticks_usec()
	_build_mesh()
	var t1: int = Time.get_ticks_usec()
	_build_splat()
	var t2: int = Time.get_ticks_usec()
	_build_ground()
	for n in ["sand", "gravel", "rock", "ore"]:
		mat.set_shader_parameter("alb_" + n, load(TEX + n + "_albedo.png"))
	mat.set_shader_parameter("nrm_a", load(TEX + "nrm_a.png"))
	mat.set_shader_parameter("nrm_b", load(TEX + "nrm_b.png"))
	mat.set_shader_parameter("macro", load(TEX + "macro.png"))
	mat.set_shader_parameter("splat", splat_tex)
	mat.set_shader_parameter("splat_texel", 1.0 / float(splat_img.get_width()))
	mat.set_shader_parameter("ground", ground_tex)
	mat.set_shader_parameter("map_size", Vector2(GN, GN))
	mat.set_shader_parameter("tint", _planet_tint())
	var t3: int = Time.get_ticks_usec()
	_build_rocks()
	_build_pebbles()
	var t4: int = Time.get_ticks_usec()
	_preseed_paths()
	var t5: int = Time.get_ticks_usec()
	set_quality(q)
	timings = {"mesh_ms": (t1 - t0) / 1000.0, "splat_ms": (t2 - t1) / 1000.0, "rocks_ms": (t4 - t3) / 1000.0, "paths_ms": (t5 - t4) / 1000.0, "chunks": chunks.size(), "map": GN}

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
	_lod_clock = 0.0

# ---------------------------------------------------------------- chunked heightfield
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
	mesh_inst = Node3D.new()
	mesh_inst.name = "TerrainChunks"
	add_child(mesh_inst)
	var w = sim.world
	var hn: int = w.hn
	var hs: float = w.hstep
	var hts: PackedFloat32Array = w.heights
	# Full-resolution normals once (every level uses them, so lighting does not pop).
	_norms.resize(hn * hn)
	for j in hn:
		var j0: int = maxi(0, j - 1)
		var j1: int = mini(hn - 1, j + 1)
		for i in hn:
			var i0: int = maxi(0, i - 1)
			var i1: int = mini(hn - 1, i + 1)
			var dx: float = (hts[j * hn + i1] - hts[j * hn + i0]) / ((i1 - i0) * hs)
			var dz: float = (hts[j1 * hn + i] - hts[j0 * hn + i]) / ((j1 - j0) * hs)
			_norms[j * hn + i] = Vector3(-dx, 1.0, -dz).normalized()
	var nq: int = hn - 1
	var cn: int = int(ceil(float(nq) / CHUNK_Q))
	for cj in cn:
		for ci in cn:
			var c := {"ci": chunks.size(), "i0": ci * CHUNK_Q, "j0": cj * CHUNK_Q, "i1": mini((ci + 1) * CHUNK_Q, nq), "j1": mini((cj + 1) * CHUNK_Q, nq),
				"lods": [null, null, null, null], "cur": -1, "peb": []}
			var lo := 1e9
			var hi := -1e9
			for j in range(c["j0"], c["j1"] + 1):
				for i in range(c["i0"], c["i1"] + 1):
					var hv: float = hts[j * hn + i]
					lo = minf(lo, hv)
					hi = maxf(hi, hv)
			c["aabb"] = AABB(Vector3(c["i0"] * hs, lo - 6.0, c["j0"] * hs), Vector3((c["i1"] - c["i0"]) * hs, hi - lo + 6.0, (c["j1"] - c["j0"]) * hs))
			chunks.append(c)
	# Coarse levels for every chunk now; fine levels on demand.
	for c in chunks:
		_chunk_lod(c, 3)
		_chunk_lod(c, 2)
	# On a small map build everything now (it is what v2 drew anyway).
	if chunks.size() <= 4:
		for c in chunks:
			_chunk_lod(c, 1)
			_chunk_lod(c, 0)
	for c in chunks:
		_show_lod(c, 0 if chunks.size() <= 4 else 2)
	_build_ring()

## Sets the structure pads (from world_view when structures change). Rebuilds the chunks
## whose pads changed. `list` as described at `_pads`.
func set_pads(list: Array) -> void:
	var sig: String = str(list).md5_text()
	if sig == _pad_sig:
		return
	_pad_sig = sig
	var old_grid: Dictionary = _pad_grid
	_pads = list
	_pad_grid = {}
	var hs: float = sim.world.hstep
	for pi in _pads.size():
		var pd: Dictionary = _pads[pi]
		var lo: Vector2
		var hi: Vector2
		var m: float = float(pd["r"]) + 16.0 * hs * 0.5 + 4.0
		if pd.has("c"):
			lo = (pd["c"] as Vector2) - Vector2(m, m)
			hi = (pd["c"] as Vector2) + Vector2(m, m)
		else:
			lo = Vector2(minf(pd["p0"].x, pd["p1"].x), minf(pd["p0"].y, pd["p1"].y)) - Vector2(m, m)
			hi = Vector2(maxf(pd["p0"].x, pd["p1"].x), maxf(pd["p0"].y, pd["p1"].y)) + Vector2(m, m)
		for ci in chunks.size():
			var ab: AABB = chunks[ci]["aabb"]
			if hi.x < ab.position.x or lo.x > ab.end.x or hi.y < ab.position.z or lo.y > ab.end.z:
				continue
			if not _pad_grid.has(ci):
				_pad_grid[ci] = []
			(_pad_grid[ci] as Array).append(pi)
	# Rebuild every chunk that had or has pads (their meshes are made again on demand).
	var touched := {}
	for k in old_grid:
		touched[k] = true
	for k in _pad_grid:
		touched[k] = true
	for ci in touched:
		var c: Dictionary = chunks[ci]
		var cur: int = int(c["cur"])
		for k in 4:
			if c["lods"][k] != null:
				(c["lods"][k] as MeshInstance3D).queue_free()
				c["lods"][k] = null
		c["cur"] = -1
		_chunk_lod(c, 3)
		_chunk_lod(c, 2)
		if cur >= 0 and cur < 2:
			_chunk_lod(c, cur)
		_show_lod(c, maxi(cur, 0) if cur >= 0 and c["lods"][maxi(cur, 0)] != null else 2)
	stats_pads = {"pads": _pads.size(), "chunks": _pad_grid.size(), "rebuilt": touched.size()}

var stats_pads := {}

## Highest the terrain mesh may be at (x, z) for the pads in `plist`. `grow` widens every pad
## by one vertex spacing on coarse levels, so interpolation between vertices cannot rise
## into a floor.
func _pad_limit(x: float, z: float, plist: Array, grow: float) -> float:
	var lim := INF
	var q := Vector2(x, z)
	for pi in plist:
		var pd: Dictionary = _pads[pi]
		var d: float
		var y: float
		if pd.has("c"):
			d = q.distance_to(pd["c"]) - float(pd["r"])
			y = float(pd["y"])
		else:
			var a: Vector2 = pd["p0"]
			var ab: Vector2 = (pd["p1"] as Vector2) - a
			var tt: float = clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			d = q.distance_to(a + ab * tt) - float(pd["r"])
			y = lerpf(float(pd["y0"]), float(pd["y1"]), tt)
		lim = minf(lim, y - PAD_DROP + maxf(0.0, d - grow) * PAD_SLOPE)
	return lim

func _chunk_lod(c: Dictionary, lod: int) -> MeshInstance3D:
	if c["lods"][lod] != null:
		return c["lods"][lod]
	var w = sim.world
	var hn: int = w.hn
	var hs: float = w.hstep
	var hts: PackedFloat32Array = w.heights
	var s: int = LOD_STRIDE[lod]
	var ii: Array = []
	var i: int = c["i0"]
	while i < int(c["i1"]):
		ii.append(i)
		i += s
	ii.append(c["i1"])
	var jj: Array = []
	var j: int = c["j0"]
	while j < int(c["j1"]):
		jj.append(j)
		j += s
	jj.append(c["j1"])
	var nx: int = ii.size()
	var nz: int = jj.size()
	var plist: Array = _pad_grid.get(int(c["ci"]), [])
	var grow: float = 0.0 if s == 1 else float(s) * hs
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	for b in nz:
		var vj: int = jj[b]
		for a in nx:
			var vi: int = ii[a]
			var k: int = vj * hn + vi
			var hv: float = hts[k]
			if not plist.is_empty():
				hv = minf(hv, _pad_limit(vi * hs, vj * hs, plist, grow))
			verts[b * nx + a] = Vector3(vi * hs, hv, vj * hs)
			norms[b * nx + a] = _norms[k]
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var t := 0
	for b in nz - 1:
		for a in nx - 1:
			var q: int = b * nx + a
			idx[t] = q
			idx[t + 1] = q + 1
			idx[t + 2] = q + nx
			idx[t + 3] = q + 1
			idx[t + 4] = q + nx + 1
			idx[t + 5] = q + nx
			t += 6
	# Skirts: a strip hanging below each edge hides cracks against a coarser neighbour.
	var depth: float = 0.8 + s * hs * 0.45
	var edges: Array = [[], [], [], []]
	for a in nx:
		edges[0].append(a)
		edges[1].append((nz - 1) * nx + (nx - 1 - a))
	for b in nz:
		edges[2].append((nz - 1 - b) * nx)
		edges[3].append(b * nx + nx - 1)
	for e in edges:
		var base: int = verts.size()
		for q in e:
			verts.append(verts[q] - Vector3(0, depth, 0))
			norms.append(norms[q])
		for m in (e as Array).size() - 1:
			var top0: int = e[m]
			var top1: int = e[m + 1]
			var bot0: int = base + m
			var bot1: int = base + m + 1
			idx.append_array([top0, bot0, top1, top1, bot0, bot1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	mi.name = "Chunk_%d_%d_L%d" % [c["i0"], c["j0"], lod]
	mesh_inst.add_child(mi)
	c["lods"][lod] = mi
	return mi

func _show_lod(c: Dictionary, lod: int) -> void:
	if int(c["cur"]) == lod:
		return
	for k in 4:
		if c["lods"][k] != null:
			(c["lods"][k] as MeshInstance3D).visible = k == lod
	c["cur"] = lod
	for p in c["peb"]:
		(p as MultiMeshInstance3D).visible = lod == 0 and quality >= 1

## Picks each chunk's level from the camera distance (5 times a second). A level that is not
## built yet shows the next coarser one; at most one mesh is built per frame.
func update_lod(delta: float, cam: Camera3D) -> void:
	if cam == null or chunks.size() <= 4:
		return
	_lod_clock -= delta
	var built := false
	if _lod_clock > 0.0:
		return
	_lod_clock = 0.2
	var eye: Vector3 = cam.global_position
	var near: Array = [95.0, 200.0, 420.0] if quality >= 2 else [70.0, 150.0, 340.0]
	lod_counts = [0, 0, 0, 0]
	for c in chunks:
		var ab: AABB = c["aabb"]
		var cp := Vector3(clampf(eye.x, ab.position.x, ab.end.x), clampf(eye.y, ab.position.y, ab.end.y), clampf(eye.z, ab.position.z, ab.end.z))
		var d: float = cp.distance_to(eye)
		var want: int = 0 if d < near[0] else (1 if d < near[1] else (2 if d < near[2] else 3))
		# Hysteresis: keep the finer level a little longer.
		var cur: int = int(c["cur"])
		if cur >= 0 and cur < want and d < near[mini(cur, 2)] * 1.12:
			want = cur
		var show: int = want
		while c["lods"][show] == null:
			if not built:
				_chunk_lod(c, show)
				built = true
				_lod_clock = 0.0   # come back next frame for the next mesh
				break
			show += 1
		_show_lod(c, show)
		lod_counts[show] += 1

## Four strips of hills and mesas round the map, to the horizon. The inner edge samples the
## map edge every 8 m; the chunk skirts hide the small steps.
func _build_ring() -> void:
	var outer_neg: Array = []
	var x := 0.0
	for s in RING_STEPS:
		x -= s
		outer_neg.push_front(x)
	outer_neg.append(0.0)
	var outer_pos: Array = [float(GN)]
	x = float(GN)
	for s in RING_STEPS:
		x += s
		outer_pos.append(x)
	var inner: Array = []
	var n: int = maxi(2, int(ceil(GN / 8.0)))
	for i in n + 1:
		inner.append(GN * float(i) / n)
	var full: Array = outer_neg.slice(0, outer_neg.size() - 1) + inner + outer_pos.slice(1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring_strip(st, outer_neg, full)                # -x side (with corners)
	_ring_strip(st, outer_pos, full)                # +x side (with corners)
	_ring_strip(st, inner, outer_neg)               # -z side
	_ring_strip(st, inner, outer_pos)               # +z side
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Ring"
	mesh_inst.add_child(mi)

func _ring_strip(st: SurfaceTool, xs: Array, zs: Array) -> void:
	var nx: int = xs.size()
	var nz: int = zs.size()
	var hv := PackedFloat32Array()
	hv.resize(nx * nz)
	for b in nz:
		for a in nx:
			hv[b * nx + a] = height(xs[a], zs[b])
	var nrm := PackedVector3Array()
	nrm.resize(nx * nz)
	for b in nz:
		for a in nx:
			var a0: int = maxi(0, a - 1)
			var a1: int = mini(nx - 1, a + 1)
			var b0: int = maxi(0, b - 1)
			var b1: int = mini(nz - 1, b + 1)
			var dx: float = (hv[b * nx + a1] - hv[b * nx + a0]) / maxf(0.01, float(xs[a1]) - float(xs[a0]))
			var dz: float = (hv[b1 * nx + a] - hv[b0 * nx + a]) / maxf(0.01, float(zs[b1]) - float(zs[b0]))
			nrm[b * nx + a] = Vector3(-dx, 1.0, -dz).normalized()
	for b in nz - 1:
		for a in nx - 1:
			for q in [[a, b], [a + 1, b], [a, b + 1], [a + 1, b], [a + 1, b + 1], [a, b + 1]]:
				var k: int = int(q[1]) * nx + int(q[0])
				st.set_normal(nrm[k])
				st.add_vertex(Vector3(xs[q[0]], hv[k], zs[q[1]]))

# ---------------------------------------------------------------- splat (2 or 1 px per metre)
func _build_splat() -> void:
	var sn: int = int(GN * splat_ppm)
	var img := Image.create(sn, sn, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 128.0 / 255.0, 128.0 / 255.0))
	var data: PackedByteArray = img.get_data()
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
	# The count grows with the map area (34 on 256 m, capped on big maps).
	var center: Vector2 = sim.world.center
	var guard := 0
	var made := 0
	var area_k: float = float(GN * GN) / 65536.0
	var want: int = mini(220, int(round(34.0 * area_k)))
	var bigs: int = mini(12, int(round(3.0 * area_k)))
	while made < want and guard < want * 12:
		guard += 1
		var big: bool = made < bigs
		var r: float = Rng.range_float(rng, "c", 14.0, 24.0 if GN <= 320 else 34.0) if big else Rng.range_float(rng, "c", 1.8, 7.5)
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
		_paint_crater(data, sn, p, r, 0.28 if big else 0.55)
		if not big:
			_paint_streak(data, sn, p + wind * r * 1.2, wind, r * 5.0, r * 0.8, 0.13)
	splat_img = Image.create_from_data(sn, sn, false, Image.FORMAT_RGBA8, data)
	splat_tex = ImageTexture.create_from_image(splat_img)

func _paint_crater(data: PackedByteArray, sn: int, p: Vector2, r: float, depth: float) -> void:
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

## A fresh crater (meteor impact, fx_hazards): stamped into the live splat texture.
func add_crater(p: Vector2, r: float) -> void:
	if splat_img == null:
		return
	var sn: int = splat_img.get_width()
	var data: PackedByteArray = splat_img.get_data()
	_paint_crater(data, sn, p, r, 0.6)
	_paint(data, sn, p, r * 2.4, func(q: Vector2, px: Array):
		var t: float = q.distance_to(p) / r
		px[1] = maxi(px[1], int(clampf(1.4 - t * 0.5, 0.0, 1.0) * 160.0)))
	splat_img.set_data(sn, sn, false, Image.FORMAT_RGBA8, data)
	splat_tex.update(splat_img)

## Many craters at once (a loaded game): one texture upload.
func add_craters(list: Array) -> void:
	if splat_img == null or list.is_empty():
		return
	var sn: int = splat_img.get_width()
	var data: PackedByteArray = splat_img.get_data()
	for c in list:
		var p := Vector2(float(c["x"]), float(c["y"]))
		var r: float = float(c["r"])
		_paint_crater(data, sn, p, r, 0.6)
		_paint(data, sn, p, r * 2.4, func(q: Vector2, px: Array):
			var t: float = q.distance_to(p) / r
			px[1] = maxi(px[1], int(clampf(1.4 - t * 0.5, 0.0, 1.0) * 160.0)))
	splat_img.set_data(sn, sn, false, Image.FORMAT_RGBA8, data)
	splat_tex.update(splat_img)

## Calls fn(point, px[4]) for every splat pixel within `rad` metres of c; px is read/write.
func _paint(data: PackedByteArray, sn: int, c: Vector2, rad: float, fn: Callable) -> void:
	var k_ppm: float = float(sn) / float(GN)
	var x0: int = maxi(0, int((c.x - rad) * k_ppm))
	var x1: int = mini(sn - 1, int((c.x + rad) * k_ppm) + 1)
	var y0: int = maxi(0, int((c.y - rad) * k_ppm))
	var y1: int = mini(sn - 1, int((c.y + rad) * k_ppm) + 1)
	var px := [0, 0, 0, 0]
	var inv: float = 1.0 / k_ppm
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2((x + 0.5) * inv, (y + 0.5) * inv)
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

## Contact shadow (B) and churned ground (A) from the structures. Only the rectangles that
## were stamped last time are cleared (the map can be 810 x 810 cells).
func update_contact(blds: Dictionary) -> void:
	var sig := ""
	for id in blds:
		var b: Dictionary = blds[id]
		sig += "%d:%s;" % [id, b["state"]]
	if sig == _contact_sig:
		return
	_contact_sig = sig
	for rc in _contact_rects:
		var r: Rect2i = rc
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var k: int = (y * GN + x) * 4
				ground_data[k + 2] = 0
				ground_data[k + 3] = 0
	_contact_rects = []
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

func _rect(x0: int, y0: int, x1: int, y1: int) -> void:
	if x1 >= x0 and y1 >= y0:
		_contact_rects.append(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))

func _stamp_disc(c: Vector2, r: float, fall: float, strength: float) -> void:
	var x0: int = maxi(0, int(c.x - r - fall))
	var x1: int = mini(GN - 1, int(c.x + r + fall) + 1)
	var y0: int = maxi(0, int(c.y - r - fall))
	var y1: int = mini(GN - 1, int(c.y + r + fall) + 1)
	_rect(x0, y0, x1, y1)
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
	_rect(x0, y0, x1, y1)
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
	_rect(x0, y0, x1, y1)
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
	_set_overlay_mode(1 if on else (2 if overlay_mode == 2 else 0))
	if on:
		_fill_walk()

## Hazard overlay (V3 §1): the three hazard zone fields, 8 m per texel.
## `fn` returns {meteor, wind, quake} (multipliers 0.5..2.0) for a map position.
func set_hazard_overlay(on: bool, fn: Callable) -> bool:
	if on:
		if hazard_tex == null:
			if not fn.is_valid():
				return false
			var n: int = maxi(8, int(ceil(GN / 8.0)))
			var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
			for y in n:
				for x in n:
					var z: Dictionary = fn.call(Vector2((x + 0.5) * GN / n, (y + 0.5) * GN / n))
					var m: float = clampf((float(z.get("meteor", 1.0)) - 0.5) / 1.5, 0.0, 1.0)
					var wv: float = clampf((float(z.get("wind", 1.0)) - 0.5) / 1.5, 0.0, 1.0)
					var q: float = clampf((float(z.get("quake", 1.0)) - 0.5) / 1.5, 0.0, 1.0)
					img.set_pixel(x, y, Color(m, wv, q, 1.0))
			hazard_tex = ImageTexture.create_from_image(img)
			mat.set_shader_parameter("hazard", hazard_tex)
		_set_overlay_mode(2)
	elif overlay_mode == 2:
		_set_overlay_mode(1 if overlay_walk else 0)
	return true

func _set_overlay_mode(m: int) -> void:
	overlay_mode = m
	if mat != null:
		mat.set_shader_parameter("overlay", 1.0 if m == 1 else 0.0)
		mat.set_shader_parameter("hazard_on", 1.0 if m == 2 else 0.0)

func _fill_walk() -> void:
	var rev: int = int(sim.state["rev"]["walk"])
	if rev == _walk_rev:
		return
	_walk_rev = rev
	var grid: AStarGrid2D = sim.nav.grid
	if grid == null:
		return
	var n: int = mini(GN, grid.region.size.x)
	for y in n:
		for x in n:
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
		var ids: Array = ["rock_%s" % ["a", "b", "c"][int(r["kind"]) % 3]]
		if v < 0.18:
			ids.push_front("rock_d")
		elif v < 0.3:
			ids.push_front("rock_e")
		var tpl: Dictionary = Models.prop(ids, float(r["r"]))
		var s: float = float(r["r"]) / 1.1
		var p := Vector2(float(r["x"]), float(r["y"]))
		var xf := Transform3D(Basis(Vector3.UP, float(r.get("rot", 0.0))).scaled(Vector3(s, s * 0.9, s)), Vector3(p.x, height(p.x, p.y) - 0.12 * s, p.y))
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

func _near_rock(p: Vector2, r2: float) -> bool:
	var cx: int = int(p.x / 8.0)
	var cy: int = int(p.y / 8.0)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var key: int = (cx + dx) * 4096 + cy + dy
			if not _rock_grid.has(key):
				continue
			for r in _rock_grid[key]:
				if p.distance_squared_to(Vector2(r["x"], r["y"])) < r2:
					return true
	return false

func _chunk_of(p: Vector2) -> int:
	var hs: float = sim.world.hstep
	var cn: int = int(ceil(float(sim.world.hn - 1) / CHUNK_Q))
	var ci: int = clampi(int(p.x / (CHUNK_Q * hs)), 0, cn - 1)
	var cj: int = clampi(int(p.y / (CHUNK_Q * hs)), 0, cn - 1)
	return cj * cn + ci

func _build_pebbles() -> void:
	var seed: int = int(sim.state.get("seed", 1001))
	var rng := {"c": Rng.stream_seed(seed, 9202)}
	# Same density as v2 on the start map; 70 % of it on big maps (pebbles only show near the camera).
	var count: int = int(round(4500.0 * float(GN * GN) / 65536.0 * (1.0 if GN <= 320 else 0.7)))
	var nch: int = chunks.size()
	var per: Array = []           # [chunk][kind] -> Array of Transform3D
	for c in nch:
		per.append([[], [], [], []])
	var center: Vector2 = sim.world.center
	for i in count:
		var p := Vector2(Rng.range_float(rng, "c", 2.0, GN - 2.0), Rng.range_float(rng, "c", 2.0, GN - 2.0))
		var k: int = Rng.range_int(rng, "c", 0, 2)
		var near_rock: bool = _near_rock(p, 49.0)
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
		(per[_chunk_of(p)][k] as Array).append(xf)
	# Stone patches (ART-B "pebbles", 2 x 2 m) round rocks, craters and at random.
	if Models.has_model("pebbles"):
		var guard := 0
		var want: int = int(round(320.0 * float(GN * GN) / 65536.0))
		var made := 0
		while made < want and guard < want * 10:
			guard += 1
			var p := Vector2(Rng.range_float(rng, "c", 4.0, GN - 4.0), Rng.range_float(rng, "c", 4.0, GN - 4.0))
			var near: bool = _near_rock(p, 100.0)
			if not near and Rng.next_float(rng, "c") > 0.35:
				continue
			if p.distance_to(center) < 30.0 and Rng.next_float(rng, "c") > 0.3:
				continue
			var s: float = Rng.range_float(rng, "c", 0.6, 1.3)
			var b := Basis(Vector3.UP, Rng.next_float(rng, "c") * TAU)
			(per[_chunk_of(p)][3] as Array).append(Transform3D(b.scaled(Vector3(s, s, s)), Vector3(p.x, height(p.x, p.y) - 0.02, p.y)))
			made += 1
	var meshes: Array = []
	for k in 4:
		var tpl: Dictionary = Models.prop(["pebbles"], 1.0) if k == 3 else Models.prop(["rock_%s" % ["a", "b", "c"][k]], 1.0)
		if (tpl["parts"] as Array).is_empty():
			meshes.append(null)
			continue
		var mesh: Mesh = tpl["parts"][0]["mesh"]
		var pxf: Transform3D = tpl["parts"][0]["xf"]
		if k < 3:
			# Small pebbles: a 20-triangle faceted stone with the rock material, not the
			# 150-triangle rock model.
			var pm := StandardMaterial3D.new()
			pm.resource_name = "Pebble"
			pm.albedo_color = [Color(0.4, 0.27, 0.2), Color(0.31, 0.23, 0.19), Color(0.5, 0.36, 0.26)][k]
			pm.roughness = 0.92
			mesh = _pebble_mesh(k, pm)
			pxf = Transform3D.IDENTITY
		elif (tpl["key"] as String).begins_with("fallback"):
			meshes.append(null)
			continue
		meshes.append([mesh, pxf])
	for ci in nch:
		for k in 4:
			var xfs: Array = per[ci][k]
			if meshes[k] == null or xfs.is_empty():
				continue
			var mesh: Mesh = meshes[k][0]
			var pxf: Transform3D = meshes[k][1]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, (xfs[i] as Transform3D) * pxf)
				var key: int = int((xfs[i] as Transform3D).origin.x / 8.0) * 4096 + int((xfs[i] as Transform3D).origin.z / 8.0)
				if not _peb_grid.has(key):
					_peb_grid[key] = []
				(_peb_grid[key] as Array).append([_pebbles.size(), i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.name = "Pebbles_%d_%d" % [ci, k]
			mmi.visible = int(chunks[ci]["cur"]) == 0
			add_child(mmi)
			_pebbles.append({"mm": mm, "mmi": mmi, "xf": xfs, "chunk": ci})
			(chunks[ci]["peb"] as Array).append(mmi)

## A jittered icosahedron, flat shaded: 12 vertices, 20 faces, about 1 m across.
func _pebble_mesh(k: int, pmat: Material) -> ArrayMesh:
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
	if pmat != null:
		st.set_material(pmat)
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
					var key: int = cx * 4096 + cz
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
