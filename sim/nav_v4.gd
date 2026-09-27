extends "res://sim/nav.gd"
## Walking and driving on the 2,560 m map (docs/V4_DESIGN.md section 1): a hierarchical
## graph instead of one 1 m grid over the whole map (6.5 million cells).
##
##  - coarse: 8 m cells over the whole map. A cell is closed when any of its 4 m height quads
##    is too steep (mountain flanks, cliffs, crater walls, crevices), a boulder covers it or a
##    structure stands on it. Long walks use it.
##  - rover: 8 m cells like coarse, but boulders and steep ground are grown by one cell:
##    rovers are wide. vehicle_path() plans on it (hoppers jump, see vehicle_path).
##  - windows: fine 1 m grids of WIN x WIN metres (aligned to 64 m) made where people walk,
##    kept while used (at most MAX_WINDOWS; the least used one goes). Terrain, rocks,
##    crevices and structures are marked exactly as the v3 grid marks them.
## A walk whose two ends fit into one window is planned on that window's fine grid. A longer
## walk follows the coarse grid (rare: suit air limits a walk to about 150 m).
## Which windows exist never changes a result: a window gives the same cells whenever it is
## made, and the walking signature comes from the structures, not from the windows.

const COARSE := 8
const WIN := 320
const WIN_ALIGN := 64
const WIN_EDGE := 16          # a point this near a window's edge does not count as inside
const MAX_WINDOWS := 8
const FAR_WALK := 200.0        # a walk longer than this (either axis) uses the coarse grid
const ROVER_CLEAR := 4.0       # metres a rover keeps from a boulder
## Walkable areas of a window (V4 frame budget): a fill from a path's end cell stops after
## POCKET_CAP cells; a fill that ends sooner found a closed pocket, so a walk into or out of it
## fails at once instead of an A* search over the whole window (25 ms each; three of them in
## one colonist's choice of work made 76 ms ticks in showcase_v4).
const POCKET_CAP := 3000

var coarse: AStarGrid2D
var rover: AStarGrid2D
var cn: int = 0
var _cterrain := PackedByteArray()   # coarse cells closed by the terrain (1) or open (0)
var _cstruct := PackedInt32Array()   # coarse cells a structure closed (indices)
var _rstruct := PackedInt32Array()
var wins: Array = []                 # [{x0, y0, grid, b: PackedInt32Array, w: PackedInt32Array, paths, used}]
var _use := 0
var _world_v4 = null
var _cpaths := {}                    # coarse paths per pair of cells

func _init(s) -> void:
	super(s)

# ---------------------------------------------------------------- terrain layers
func _ensure_world() -> void:
	var world = sim.world
	if _world_v4 == world and coarse != null:
		return
	var t0: int = Time.get_ticks_msec()
	_world_v4 = world
	size = world.size
	wins = []
	_cpaths = {}
	cn = int(ceil(float(size) / COARSE))
	coarse = _new_grid(Rect2i(0, 0, cn, cn), Vector2(COARSE, COARSE))
	rover = _new_grid(Rect2i(0, 0, cn, cn), Vector2(COARSE, COARSE))
	_cterrain = PackedByteArray()
	_cterrain.resize(cn * cn)
	var qn: int = world.hn - 1
	var q_per: int = maxi(1, int(round(COARSE / world.hstep)))
	var st: PackedByteArray = world.steep
	var m: int = int(ceil(float(world.margin) / COARSE))
	for cy in cn:
		for cx in cn:
			var closed := false
			if cx < m or cy < m or cx >= cn - m or cy >= cn - m:
				closed = true
			else:
				for dy in q_per:
					for dx in q_per:
						var qx: int = mini(cx * q_per + dx, qn - 1)
						var qy: int = mini(cy * q_per + dy, qn - 1)
						if st[qy * qn + qx] == 1:
							closed = true
			if closed:
				_cterrain[cy * cn + cx] = 1
				coarse.set_point_solid(Vector2i(cx, cy), true)
	# The rover grid: the same terrain (a rover climbs what a walker climbs, slope 0.6).
	for cy in cn:
		for cx in cn:
			if _cterrain[cy * cn + cx] == 1:
				rover.set_point_solid(Vector2i(cx, cy), true)
	# Boulders close the cells they cover (big rocks only; small ones are stepped round);
	# for a rover they are grown by ROVER_CLEAR metres (a rover is wide).
	for r in world.rocks:
		var rr: float = float(r["r"])
		if rr < 2.5:
			continue
		_close_disc(coarse, Vector2(r["x"], r["y"]), rr, true)
		_close_disc(rover, Vector2(r["x"], r["y"]), rr + ROVER_CLEAR, false)
	base_msec = Time.get_ticks_msec() - t0

func _new_grid(region: Rect2i, cell: Vector2) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = region
	g.cell_size = cell
	g.offset = cell * 0.5
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.jumping_enabled = false
	g.update()
	return g

func _close_disc(g: AStarGrid2D, c: Vector2, r: float, terrain: bool) -> void:
	var x0: int = maxi(0, int(floor((c.x - r) / COARSE)))
	var x1: int = mini(cn - 1, int(floor((c.x + r) / COARSE)))
	var y0: int = maxi(0, int(floor((c.y - r) / COARSE)))
	var y1: int = mini(cn - 1, int(floor((c.y + r) / COARSE)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cc := Vector2((x + 0.5) * COARSE, (y + 0.5) * COARSE)
			if cc.distance_to(c) <= r:
				g.set_point_solid(Vector2i(x, y), true)
				if terrain:
					_cterrain[y * cn + x] = 1

# ---------------------------------------------------------------- fine windows
## The window that holds both points (at least WIN_EDGE from its edges), made if needed.
## null when the two points are too far apart for one window.
func _window_for(a: Vector2, b: Vector2):
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	for w in wins:
		if lo.x >= w["x0"] + WIN_EDGE and lo.y >= w["y0"] + WIN_EDGE and hi.x <= w["x0"] + WIN - WIN_EDGE and hi.y <= w["y0"] + WIN - WIN_EDGE:
			_use += 1
			w["used"] = _use
			return w
	var mid: Vector2 = (lo + hi) * 0.5
	var x0: int = clampi(int(floor((mid.x - WIN * 0.5) / WIN_ALIGN)) * WIN_ALIGN, 0, maxi(0, size - WIN))
	var y0: int = clampi(int(floor((mid.y - WIN * 0.5) / WIN_ALIGN)) * WIN_ALIGN, 0, maxi(0, size - WIN))
	if lo.x < x0 + WIN_EDGE or lo.y < y0 + WIN_EDGE or hi.x > x0 + WIN - WIN_EDGE or hi.y > y0 + WIN - WIN_EDGE:
		# Near the map edge the edge margin does not apply.
		if lo.x < x0 or lo.y < y0 or hi.x > x0 + WIN or hi.y > y0 + WIN:
			return null
	return _make_window(x0, y0)

func _make_window(x0: int, y0: int) -> Dictionary:
	for w in wins:
		if int(w["x0"]) == x0 and int(w["y0"]) == y0:
			return w
	if wins.size() >= MAX_WINDOWS:
		var old := 0
		for i in wins.size():
			if int(wins[i]["used"]) < int(wins[old]["used"]):
				old = i
		wins.remove_at(old)
	var world = sim.world
	var g := AStarGrid2D.new()
	g.region = Rect2i(x0, y0, WIN, WIN)
	g.cell_size = Vector2(1, 1)
	g.offset = Vector2(0.5, 0.5)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.jumping_enabled = false
	g.update()
	# Map edge.
	var m: int = int(world.margin)
	var rect := Rect2i(x0, y0, WIN, WIN)
	for band in [Rect2i(0, 0, size, m), Rect2i(0, size - m, size, m), Rect2i(0, 0, m, size), Rect2i(size - m, 0, m, size)]:
		var cut: Rect2i = rect.intersection(band)
		if cut.has_area():
			g.fill_solid_region(cut, true)
	# Steep height quads.
	var step: int = int(world.hstep)
	var qn: int = world.hn - 1
	var st: PackedByteArray = world.steep
	for qy in range(int(y0 / step), mini(qn, int((y0 + WIN) / step) + 1)):
		for qx in range(int(x0 / step), mini(qn, int((x0 + WIN) / step) + 1)):
			if st[qy * qn + qx] == 1:
				var cut2: Rect2i = rect.intersection(Rect2i(qx * step, qy * step, step, step))
				if cut2.has_area():
					g.fill_solid_region(cut2, true)
	# Rocks and boulders (the same discs as the v3 grid).
	var saved = grid
	grid = g
	var centre := Vector2(x0 + WIN * 0.5, y0 + WIN * 0.5)
	for r in world.rocks_near(centre, WIN * 0.75):
		_solid_disc_terrain(Vector2(r["x"], r["y"]), float(r["r"]), rect)
	# Crevices at their exact width, grown by the body radius.
	for cv in world.crevices:
		var pts: Array = cv["pts"]
		var half: float = float(cv["w"]) * 0.5 + BODY_R
		for i in range(1, pts.size()):
			_solid_capsule_terrain(pts[i - 1], pts[i], half, rect)
	grid = saved
	var w := {"x0": x0, "y0": y0, "grid": g, "b": PackedInt32Array(), "w": PackedInt32Array(), "paths": {}, "used": 0}
	_use += 1
	w["used"] = _use
	wins.append(w)
	_mark_window(w)
	return w

func _solid_disc_terrain(c: Vector2, r: float, rect: Rect2i) -> void:
	var x0: int = maxi(rect.position.x, int(floor(c.x - r)))
	var x1: int = mini(rect.end.x - 1, int(floor(c.x + r)))
	var y0: int = maxi(rect.position.y, int(floor(c.y - r)))
	var y1: int = mini(rect.end.y - 1, int(floor(c.y + r)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				grid.set_point_solid(Vector2i(x, y), true)

func _solid_capsule_terrain(p0: Vector2, p1: Vector2, r: float, rect: Rect2i) -> void:
	var x0: int = maxi(rect.position.x, int(floor(minf(p0.x, p1.x) - r)))
	var x1: int = mini(rect.end.x - 1, int(floor(maxf(p0.x, p1.x) + r)))
	var y0: int = maxi(rect.position.y, int(floor(minf(p0.y, p1.y) - r)))
	var y1: int = mini(rect.end.y - 1, int(floor(maxf(p0.y, p1.y) + r)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2(x + 0.5, y + 0.5)
			if c.distance_to(Geometry2D.get_closest_point_to_segment(c, p0, p1)) <= r:
				grid.set_point_solid(Vector2i(x, y), true)

## Marks the structures of one window (the same passes as nav.gd rebuild()).
func _mark_window(w: Dictionary) -> void:
	# The walkable areas are found again after any change of the cells.
	w["cc"] = PackedInt32Array()
	w["cc_up"] = [0]
	w["cc_pocket"] = {}
	var g: AStarGrid2D = w["grid"]
	grid = g
	for k in w["b"]:
		g.set_point_solid(Vector2i(k % size, k / size), false)
	for k in w["w"]:
		g.set_point_weight_scale(Vector2i(k % size, k / size), 1.0)
	_bcells = PackedInt32Array()
	_wcells = PackedInt32Array()
	var x0: float = float(w["x0"])
	var y0: float = float(w["y0"])
	var lim := Rect2(x0 - 30.0, y0 - 30.0, WIN + 60.0, WIN + 60.0)
	var clear: float = float(sim.bal.get("nav_clearance", 0.6))
	var cw: float = float(sim.bal.get("nav_clearance_weight", 8.0))
	var pw: float = float(sim.bal.get("porch_weight", 12.0))
	var blds: Dictionary = sim.state["buildings"]
	var touched: Array = []
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] == "blueprint":
			continue
		if b["kind"] == "link":
			if b["def"] == "corridor" and (lim.has_point(b["p0"]) or lim.has_point(b["p1"])):
				touched.append(b)
		elif lim.grow(float(b["radius"]) + 30.0).has_point(b["pos"]):
			touched.append(b)
	for b in touched:
		if b["kind"] == "link":
			_solid_capsule(b["p0"], b["p1"], sim.corridor_r() + BODY_R)
		elif b["def"] == "meridian":
			var seg: Array = Ship.segment_of(b)
			_solid_capsule(seg[0], seg[1], float(b["radius"]) + BODY_R)
		else:
			_solid_disc(b["pos"], float(b["radius"]) + BODY_R)
	for b in touched:
		if b["kind"] == "link":
			_weight_capsule(b["p0"], b["p1"], sim.corridor_r() + BODY_R + clear, cw)
		elif b["def"] == "meridian":
			var seg2: Array = Ship.segment_of(b)
			_weight_capsule(seg2[0], seg2[1], float(b["radius"]) + BODY_R + clear, cw)
		else:
			_weight_disc(b["pos"], float(b["radius"]) + BODY_R + clear, cw)
			if bool(sim.bdef(b["def"]).get("airlock", false)):
				var dirv := Vector2(cos(float(b["rot"])), sin(float(b["rot"])))
				var s0: Vector2 = (b["pos"] as Vector2) + dirv * float(b["radius"])
				var s1: Vector2 = s0 + dirv * float(sim.bal.get("porch_length", 2.5))
				_weight_capsule(s0, s1, float(sim.bal.get("porch_half_width", 1.6)), pw)
	var changed: bool = _bcells != w["b"] or _wcells != w["w"]
	w["b"] = _bcells
	w["w"] = _wcells
	if changed:
		w["paths"] = {}

func _mark(x: int, y: int) -> void:
	var p := Vector2i(x, y)
	if not grid.region.has_point(p):
		return
	if not grid.is_point_solid(p):
		grid.set_point_solid(p, true)
		_bcells.append(y * size + x)

func _markw(x: int, y: int, w: float) -> void:
	var p := Vector2i(x, y)
	if not grid.region.has_point(p) or grid.is_point_solid(p):
		return
	var cur: float = grid.get_point_weight_scale(p)
	if cur >= w:
		return
	if cur <= 1.0:
		_wcells.append(y * size + x)
	grid.set_point_weight_scale(p, w)

# ---------------------------------------------------------------- rebuild (structures)
## Makes the fine windows round every base core now (at a load or a new game), so the first
## walks after it do not build a window inside a tick (8 ms each). Which windows exist never
## changes a result.
func prewarm() -> void:
	_ensure_world()
	for bid in sim.bases.ids():
		var core: Dictionary = sim.bases.core_of(int(bid))
		if not core.is_empty():
			_window_for(core["pos"], core["pos"])
	grid = null

func rebuild() -> void:
	_ensure_world()
	for w in wins:
		_mark_window(w)
	grid = null
	# Structures close coarse and rover cells too (long walks and vehicles go round).
	for k in _cstruct:
		if _cterrain[k] == 0:
			coarse.set_point_solid(Vector2i(k % cn, k / cn), false)
	for k in _rstruct:
		rover.set_point_solid(Vector2i(k % cn, k / cn), false)
	_cstruct = PackedInt32Array()
	_rstruct = PackedInt32Array()
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] == "blueprint" or b["kind"] == "link":
			continue
		var r: float = float(b["radius"]) + 2.0
		var c: Vector2 = b["pos"]
		var x0: int = maxi(0, int(floor((c.x - r) / COARSE)))
		var x1: int = mini(cn - 1, int(floor((c.x + r) / COARSE)))
		var y0: int = maxi(0, int(floor((c.y - r) / COARSE)))
		var y1: int = mini(cn - 1, int(floor((c.y + r) / COARSE)))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var cc := Vector2((x + 0.5) * COARSE, (y + 0.5) * COARSE)
				if cc.distance_to(c) <= r:
					var q := Vector2i(x, y)
					if not coarse.is_point_solid(q):
						coarse.set_point_solid(q, true)
						_cstruct.append(y * cn + x)
					if not rover.is_point_solid(q):
						rover.set_point_solid(q, true)
						_rstruct.append(y * cn + x)
	_cpaths = {}
	rooms = AStar2D.new()
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "link" and sim.topo.atmo_comp.has(id):
			rooms.add_point(id, b["pos"])
	for id in blds:
		var l: Dictionary = blds[id]
		if l["kind"] == "link" and l["def"] == "corridor" and l["state"] == "active":
			if rooms.has_point(l["a"]) and rooms.has_point(l["b"]):
				rooms.connect_points(l["a"], l["b"], true)

## What walking depends on: the started structures (and their shape) and the room graph.
## Independent of which windows exist, so a loaded game walks like the saved one.
func signature() -> int:
	var parts: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] == "blueprint":
			continue
		if b["kind"] == "link":
			if b["def"] == "corridor":
				parts.append([int(id), b["p0"], b["p1"]])
		else:
			parts.append([int(id), b["pos"], float(b["radius"]), float(b["rot"])])
	var ids: PackedInt64Array = rooms.get_point_ids()
	for id in ids:
		parts.append(int(id))
		var cl: Array = Array(rooms.get_point_connections(id))
		cl.sort()
		parts.append(cl.hash())
	return parts.hash()

# ---------------------------------------------------------------- queries
func is_walkable(p: Vector2) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= size or p.y >= size:
		return false
	var w = _window_for(p, p)
	if w == null:
		return not coarse.is_point_solid(Vector2i(int(p.x / COARSE), int(p.y / COARSE)))
	return not (w["grid"] as AStarGrid2D).is_point_solid(cell_of(p))

func is_weighted(p: Vector2) -> bool:
	var w = _window_for(p, p)
	if w == null:
		return false
	return (w["grid"] as AStarGrid2D).get_point_weight_scale(cell_of(p)) > 1.0

func nearest_walkable(p: Vector2, max_r: int = 4):
	var w = _window_for(p, p)
	if w == null:
		return null
	return _nearest_in(w, p, max_r)

func _nearest_in(w: Dictionary, p: Vector2, max_r: int):
	var g: AStarGrid2D = w["grid"]
	var c: Vector2i = cell_of(p)
	if g.region.has_point(c) and not g.is_point_solid(c):
		return p
	var best = null
	var best_d := 1e9
	for dy in range(-max_r, max_r + 1):
		for dx in range(-max_r, max_r + 1):
			var q := Vector2i(c.x + dx, c.y + dy)
			if not g.region.has_point(q) or g.is_point_solid(q):
				continue
			var cp := Vector2(q.x + 0.5, q.y + 0.5)
			var d: float = cp.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = cp
	return best

func path_out(a: Vector2, b: Vector2) -> Dictionary:
	_ensure_world()
	if absf(a.x - b.x) > FAR_WALK or absf(a.y - b.y) > FAR_WALK:
		return _coarse_path(coarse, a, b)
	var w = _window_for(a, b)
	if w == null:
		return _coarse_path(coarse, a, b)
	grid = w["grid"]
	var sa = _nearest_in(w, a, 4)
	var sb = _nearest_in(w, b, 4)
	if sa == null or sb == null:
		grid = null
		return {"ok": false}
	var ca: Vector2i = cell_of(sa)
	var cb: Vector2i = cell_of(sb)
	var key: int = ((ca.x * size + ca.y) * size + cb.x) * size + cb.y
	var cache: Dictionary = w["paths"]
	var smooth = cache.get(key)
	if smooth == null:
		# A closed pocket at either end: no search (the same answer A* gives, found cheaply).
		var ra: int = _area_of(w, ca)
		var rb: int = _area_of(w, cb)
		if ra != rb and ((w["cc_pocket"] as Dictionary).has(ra) or (w["cc_pocket"] as Dictionary).has(rb)):
			smooth = []
		else:
			var raw: PackedVector2Array = grid.get_point_path(ca, cb)
			smooth = [] if raw.is_empty() else _smooth(raw)
		if cache.size() >= PATH_CACHE_MAX:
			cache.clear()
		cache[key] = smooth
	grid = null
	if (smooth as Array).is_empty():
		return {"ok": false}
	var pts: Array = (smooth as Array).duplicate()
	if (w["grid"] as AStarGrid2D).region.has_point(cell_of(a)) and not (w["grid"] as AStarGrid2D).is_point_solid(cell_of(a)):
		pts[0] = a
	if (w["grid"] as AStarGrid2D).region.has_point(cell_of(b)) and not (w["grid"] as AStarGrid2D).is_point_solid(cell_of(b)):
		pts[pts.size() - 1] = b
	if pts.size() == 1:
		pts.append(pts[0])
	return {"ok": true, "pts": pts, "len": _length(pts)}

## The walkable area (a union-find root id) of window cell c. Unknown cells are filled from c
## (4 neighbours: diagonal steps need both sides open, so this is A*'s connectivity) until
## POCKET_CAP cells; a fill that meets a known area joins it. A fill that ends before the cap
## without meeting another area has found the whole area: a pocket.
func _area_of(w: Dictionary, c: Vector2i) -> int:
	var x0: int = int(w["x0"])
	var y0: int = int(w["y0"])
	var cc: PackedInt32Array = w["cc"]
	if cc.is_empty():
		cc.resize(WIN * WIN)
	var idx: int = (c.y - y0) * WIN + (c.x - x0)
	if cc[idx] != 0:
		return _area_root(w, cc[idx])
	var up: Array = w["cc_up"]
	var id: int = up.size()
	up.append(id)
	var g: AStarGrid2D = w["grid"]
	var q := PackedInt32Array([idx])
	cc[idx] = id
	var head := 0
	var met := false
	while head < q.size():
		if q.size() >= POCKET_CAP:
			met = true
			break
		var k: int = q[head]
		head += 1
		var x: int = k % WIN
		var y: int = k / WIN
		for d in 4:
			var nx: int = x + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny: int = y + (1 if d == 2 else (-1 if d == 3 else 0))
			if nx < 0 or ny < 0 or nx >= WIN or ny >= WIN:
				continue
			var nk: int = ny * WIN + nx
			var m: int = cc[nk]
			if m == id:
				continue
			if m != 0:
				met = true
				var r1: int = _area_root(w, id)
				var r2: int = _area_root(w, m)
				if r1 != r2:
					up[maxi(r1, r2)] = mini(r1, r2)
				continue
			if g.is_point_solid(Vector2i(x0 + nx, y0 + ny)):
				continue
			cc[nk] = id
			q.append(nk)
	w["cc"] = cc
	var root: int = _area_root(w, id)
	if not met:
		(w["cc_pocket"] as Dictionary)[root] = true
	return root

func _area_root(w: Dictionary, id: int) -> int:
	var up: Array = w["cc_up"]
	var r: int = id
	while int(up[r]) != r:
		r = int(up[r])
	while int(up[id]) != r:
		var nxt: int = int(up[id])
		up[id] = r
		id = nxt
	return r

## A path on an 8 m grid (walking far, or driving): cell centres, straightened where the
## line stays on open cells, with the exact end points.
func _coarse_path(g: AStarGrid2D, a: Vector2, b: Vector2) -> Dictionary:
	var ca = _coarse_open(g, a)
	var cb = _coarse_open(g, b)
	if ca == null or cb == null:
		return {"ok": false}
	var key: int = ((int(ca.x) * cn + int(ca.y)) * cn + int(cb.x)) * cn + int(cb.y) + (0 if g == coarse else 1 << 40)
	var smooth = _cpaths.get(key)
	if smooth == null:
		var raw: PackedVector2Array = g.get_point_path(ca, cb)
		smooth = [] if raw.is_empty() else _coarse_smooth(g, raw)
		if _cpaths.size() >= 2000:
			_cpaths = {}
		_cpaths[key] = smooth
	if (smooth as Array).is_empty():
		return {"ok": false}
	var pts: Array = (smooth as Array).duplicate()
	pts[0] = a
	pts[pts.size() - 1] = b
	if pts.size() == 1:
		pts.append(pts[0])
	return {"ok": true, "pts": pts, "len": _length(pts), "coarse": true}

func _coarse_open(g: AStarGrid2D, p: Vector2, reach: int = 3):
	var c := Vector2i(clampi(int(p.x / COARSE), 0, cn - 1), clampi(int(p.y / COARSE), 0, cn - 1))
	if not g.is_point_solid(c):
		return c
	for r in range(1, reach + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := Vector2i(c.x + dx, c.y + dy)
				if q.x >= 0 and q.y >= 0 and q.x < cn and q.y < cn and not g.is_point_solid(q):
					return q
	return null

func _coarse_smooth(g: AStarGrid2D, raw: PackedVector2Array) -> Array:
	var out: Array = [raw[0]]
	var i := 0
	var n: int = raw.size()
	while i < n - 1:
		var j: int = mini(n - 1, i + 12)
		while j > i + 1 and not _coarse_line(g, raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	return out

func _coarse_line(g: AStarGrid2D, a: Vector2, b: Vector2) -> bool:
	var steps: int = int(ceil(a.distance_to(b) / (COARSE * 0.5)))
	for s in range(1, steps):
		var p: Vector2 = a.lerp(b, float(s) / steps)
		if g.is_point_solid(Vector2i(clampi(int(p.x / COARSE), 0, cn - 1), clampi(int(p.y / COARSE), 0, cn - 1))):
			return false
	return true

# ---------------------------------------------------------------- vehicles (V4 section 5)
## A route for a vehicle: {"ok", "pts", "len", "hops"?}. kind "rover" drives on the rover
## grid (no slope over 0.6, no crevice, round boulders and structures). kind "hopper" flies
## straight when the hop is within range (hop_m), else chains hops over open coarse cells.
func vehicle_path(a: Vector2, b: Vector2, kind: String = "rover", hop_m: float = 400.0) -> Dictionary:
	_ensure_world()
	if kind == "hopper":
		var d: float = a.distance_to(b)
		var n: int = maxi(1, int(ceil(d / maxf(1.0, hop_m))))
		var pts: Array = [a]
		for k in range(1, n):
			# A landing place within 80 m of the straight line's step.
			var q = _coarse_open(coarse, a.lerp(b, float(k) / n), 10)
			if q == null:
				return {"ok": false}
			pts.append(Vector2((q.x + 0.5) * COARSE, (q.y + 0.5) * COARSE))
		pts.append(b)
		return {"ok": true, "pts": pts, "len": _length(pts), "hops": n}
	return _coarse_path(rover, a, b)

## True when a rover can stand at p (an open rover cell).
func rover_ok(p: Vector2) -> bool:
	_ensure_world()
	if p.x < 0 or p.y < 0 or p.x >= size or p.y >= size:
		return false
	return not rover.is_point_solid(Vector2i(int(p.x / COARSE), int(p.y / COARSE)))

## For the view's walk overlay: 1 = closed, 0 = open, on the coarse grid (8 m cells).
func coarse_open_at(p: Vector2) -> bool:
	_ensure_world()
	return not coarse.is_point_solid(Vector2i(clampi(int(p.x / COARSE), 0, cn - 1), clampi(int(p.y / COARSE), 0, cn - 1)))

# ---------------------------------------------------------------- straight lines in a window
func _clear_line(a: Vector2, b: Vector2) -> bool:
	var d: float = a.distance_to(b)
	var steps: int = int(ceil(d / 0.45))
	var side: Vector2 = (b - a).normalized().orthogonal() * 0.35
	var reg: Rect2i = grid.region
	var wa: bool = _wt(cell_of(a), reg) > 1.0
	var wb: bool = _wt(cell_of(b), reg) > 1.0
	for s in range(1, steps):
		var p: Vector2 = a.lerp(b, float(s) / steps)
		if _closed(cell_of(p), reg) or _closed(cell_of(p + side), reg) or _closed(cell_of(p - side), reg):
			return false
		var cp: Vector2i = cell_of(p)
		if _wt(cp, reg) > 1.0:
			if not (wa or wb):
				return false
			if _solid_near(cp):
				return false
	return true

func _closed(c: Vector2i, reg: Rect2i) -> bool:
	return not reg.has_point(c) or grid.is_point_solid(c)

func _wt(c: Vector2i, reg: Rect2i) -> float:
	return grid.get_point_weight_scale(c) if reg.has_point(c) else 1.0

func _solid_near(c: Vector2i) -> bool:
	var reg: Rect2i = grid.region
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _closed(c + d, reg):
			return true
	return false
