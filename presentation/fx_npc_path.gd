extends RefCounted
## Colonist paths (RENDER, V3_1 §4.1–4.3).
##
## A body moves between two places only through the structure graph:
##   its point -> free floor of its room -> the doorway centre line -> the corridor centre
##   line -> the next doorway -> free floor of the next room -> the target.
## Inside a room the path is an A* path over the room's free floor (fx_nav furniture grid,
## 0.2 m cells, furniture and walls + 0.30 m blocked), then string-pulled. Outside, the
## straight line is used when it crosses no structure, tube or pad; otherwise the
## simulation's own outdoor path (sim.nav.path_out, read only) is string-pulled.
## The corner rounding, speed ramp and turn limit are done by the walker in fx_npc.

const Nav = preload("res://presentation/fx_nav.gd")
const CELL := 0.2
const CLEAR := 0.30          # m: furniture clearance (V3_1 §4.1)
const CLEAR_TIGHT := 0.15    # m: a second grid for rooms whose aisles are narrower than 0.6 m
const DOOR_IN := 1.05        # m inside the wall line: the doorway's room-side point
const DOOR_OUT := 0.9        # m outside the wall: the doorway's corridor-side point
const TUBE_R := 1.15         # m: a point this close to a corridor centre line is in the tube

var npc
var view
var sim
static var _coarse := {}     # "tplkey|hbmask" -> {n, half, blk: PackedByteArray, astar: AStarGrid2D}
var _doors := {}             # room id -> [{in, out, dir, link}]
var _tube_grid := {}         # 8 m cell -> [link ids] (corridor segments, for region_of)
var _tube_sig := ""
var _door_sig := ""
var quality := 0            # worst leg of the last plan: 0 strict, 1 tight grid, 2 aisle fallback
var stats := {"plans": 0, "room_astar": 0, "out_paths": 0, "grids": 0, "fails": 0}

func _init(n) -> void:
	npc = n
	view = n.view
	sim = n.sim

# ---------------------------------------------------------------- doors (geometric)
## Every corridor end on a room is a doorway (whether or not the room model has one), and
## every airlock has its outer door on model +X.
func doors_of(rid: int) -> Array:
	var blds: Dictionary = sim.state["buildings"]
	var sig := "%d:%d" % [blds.size(), int(sim.state["rev"].get("walk", 0)) if sim.state.has("rev") else 0]
	if sig != _door_sig:
		_door_sig = sig
		_doors = {}
		for lid in blds:
			var l: Dictionary = blds[lid]
			if l["kind"] != "link" or l["def"] != "corridor" or l["state"] == "blueprint":
				continue
			for end in [["a", "p0"], ["b", "p1"]]:
				var r: int = int(l.get(end[0], -1))
				if not blds.has(r):
					continue
				_add_door(r, (l[end[1]] as Vector2) - (blds[r]["pos"] as Vector2), int(lid))
		for bid in blds:
			var ab: Dictionary = blds[bid]
			if String(ab["def"]) == "airlock" and view.bmeta.has(bid):
				var bx: Vector3 = (view.bmeta[bid]["xf"] as Transform3D).basis.x
				_add_door(int(bid), Vector2(bx.x, bx.z), -1)
	return _doors.get(rid, [])

func _add_door(rid: int, dv: Vector2, link: int) -> void:
	var b: Dictionary = sim.state["buildings"][rid]
	var dir: Vector2 = dv.normalized()
	var c: Vector2 = b["pos"]
	var rr: float = float(b["radius"])
	var fy: float = npc._floor_y(b)
	var pin: Vector2 = c + dir * maxf(0.5, rr - DOOR_IN)
	# The room-side point is the first free floor on the door centre line (furniture can
	# stand 0.8-1.0 m from a doorway, ART-HAB J3).
	if link >= 0 or String(b["def"]) == "airlock":
		var found := false
		for clr in [CLEAR, CLEAR_TIGHT]:
			var cg = coarse(rid, clr) if view.bmeta.has(rid) else null
			if cg == null or found:
				continue
			var dd: float = rr - 0.75
			while dd > maxf(0.5, rr - 2.6):
				var tp: Vector2 = c + dir * dd
				if not blocked_local(cg, _to_local(rid, Vector3(tp.x, fy, tp.y))):
					pin = tp
					found = true
					break
				dd -= 0.1
		var entry: Array = []
		if not found:
			# Furniture stands in front of this doorway: find the way in over free floor
			# (a search on the fine furniture grid from the opening, never through an item).
			entry = _entry_search(rid, c + dir * (rr - 0.45), fy)
			if not entry.is_empty():
				var last: Vector3 = entry[-1]
				pin = Vector2(last.x, last.z)
				entry.pop_back()
		var pout0: Vector2 = c + dir * (rr + DOOR_OUT)
		_push_door(rid, {"in": Vector3(pin.x, fy, pin.y), "out": Vector3(pout0.x, fy if link >= 0 else view.h(pout0.x, pout0.y), pout0.y), "dir": dir, "link": link, "room": rid, "entry": entry})
		return
	var pout: Vector2 = c + dir * (rr + DOOR_OUT)
	var oy: float = fy if link >= 0 else view.h(pout.x, pout.y)
	_push_door(rid, {"in": Vector3(pin.x, fy, pin.y), "out": Vector3(pout.x, oy, pout.y), "dir": dir, "link": link, "room": rid, "entry": []})

func _push_door(rid: int, d: Dictionary) -> void:
	if not _doors.has(rid):
		_doors[rid] = []
	(_doors[rid] as Array).append(d)
	if not (d["entry"] as Array).is_empty():
		stats["door_detours"] = int(stats.get("door_detours", 0)) + 1

## From a point just inside a doorway, a breadth-first search over the fine furniture grid
## (free cells only) to the nearest cell that is free floor in the tight walk grid. Returns
## the world points from the opening to that cell (string-pulled), or [] when none.
func _entry_search(rid: int, start: Vector2, fy: float) -> Array:
	if not view.bmeta.has(rid):
		return []
	var g: Dictionary = Nav.grid_of(view.bmeta[rid]["tpl"])
	var cg = coarse(rid, CLEAR_TIGHT)
	if g.is_empty() or cg == null:
		return []
	var hb: int = int(view.doors.hb_masks.get(rid, 0)) if view.doors != null else 0
	var wm: int = _wm(rid)
	_los_wm = wm
	var n: int = g["n"]
	var half: float = g["half"]
	var s: Vector2 = _to_local(rid, Vector3(start.x, fy, start.y))
	var si: int = int(floor((s.x + half) / Nav.CELL))
	var sj: int = int(floor((s.y + half) / Nav.CELL))
	if si < 0 or sj < 0 or si >= n or sj >= n:
		return []
	var prev := {}
	var queue: Array = [Vector2i(si, sj)]
	prev[Vector2i(si, sj)] = Vector2i(-1, -1)
	var goal := Vector2i(-1, -1)
	var qi := 0
	while qi < queue.size() and qi < 6000:
		var cell: Vector2i = queue[qi]
		qi += 1
		var q := Vector2((cell.x + 0.5) * Nav.CELL - half, (cell.y + 0.5) * Nav.CELL - half)
		if qi > 1 and not blocked_local(cg, q):
			goal = cell
			break
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = cell + dv
			if nc.x < 0 or nc.y < 0 or nc.x >= n or nc.y >= n or prev.has(nc):
				continue
			var nq := Vector2((nc.x + 0.5) * Nav.CELL - half, (nc.y + 0.5) * Nav.CELL - half)
			# The wall ring is passable only inside the opening (the first 0.3 m).
			var v: int = Nav.at(g, nq, hb, wm)
			if v == 1 or (v == 2 and nq.distance_to(s) > 0.35):
				continue
			# Keep off the wall (a body there would clip it), except at the opening itself.
			if nq.length() > float(g["wall_r"]) - 0.62 and nq.distance_to(s) > 0.6:
				continue
			prev[nc] = cell
			queue.append(nc)
	if goal.x < 0:
		return []
	var cells: Array = []
	var k: Vector2i = goal
	while k.x >= 0:
		cells.push_front(Vector2((k.x + 0.5) * Nav.CELL - half, (k.y + 0.5) * Nav.CELL - half))
		k = prev[k]
	# String-pull on the fine grid (free cells only).
	var out: Array = []
	var i := 0
	while i < cells.size() - 1:
		var j: int = cells.size() - 1
		while j > i + 1 and not _los_fine(g, hb, cells[i], cells[j]):
			j -= 1
		out.append(cells[j])
		i = j
	var w: Array = []
	for q in out:
		w.append(_to_world(rid, q, fy))
	return w

## The room's hidden wall segments (doorway spans): those wall cells are open floor.
func _wm(rid: int) -> int:
	return int(view.doors.masks.get(rid, 0)) if view.doors != null else 0

var _los_wm := 0
func _los_fine(g: Dictionary, hb: int, a: Vector2, b: Vector2) -> bool:
	var d: float = a.distance_to(b)
	var steps: int = maxi(1, int(ceil(d / 0.05)))
	for s in range(1, steps):
		if Nav.at(g, a.lerp(b, float(s) / steps), hb, _los_wm) == 1:
			return false
	return true

# ---------------------------------------------------------------- regions
## {"k": "room", "id": rid} | {"k": "tube", "id": lid} | {"k": "out"}
func region_of(p: Vector3, inside_hint: bool) -> Dictionary:
	var rid: int = npc._room_at(Vector2(p.x, p.z))
	if rid >= 0:
		return {"k": "room", "id": rid}
	var q := Vector2(p.x, p.z)
	var best := -1
	var bd := TUBE_R
	_build_tube_grid()
	for lid in _tube_grid.get(int(floor(q.x / 8.0)) * 4096 + int(floor(q.y / 8.0)), []):
		var l: Dictionary = sim.state["buildings"].get(lid, {})
		if l.is_empty():
			continue
		var a: Vector2 = l["p0"]
		var ab: Vector2 = (l["p1"] as Vector2) - a
		var t: float = clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d: float = q.distance_to(a + ab * t)
		if d < bd:
			bd = d
			best = int(lid)
	if best >= 0 and (inside_hint or bd < 0.9):
		return {"k": "tube", "id": best}
	return {"k": "out"}

## Corridor segments by 8 m cell (rebuilt when the structures change).
func _build_tube_grid() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var sig := "%d" % blds.size()
	if sig == _tube_sig:
		return
	_tube_sig = sig
	_tube_grid = {}
	for lid in blds:
		var l: Dictionary = blds[lid]
		if l["kind"] != "link" or l["def"] != "corridor":
			continue
		var a: Vector2 = l["p0"]
		var b: Vector2 = l["p1"]
		var lo := Vector2(minf(a.x, b.x) - 1.6, minf(a.y, b.y) - 1.6)
		var hi := Vector2(maxf(a.x, b.x) + 1.6, maxf(a.y, b.y) + 1.6)
		for cx in range(int(floor(lo.x / 8.0)), int(floor(hi.x / 8.0)) + 1):
			for cy in range(int(floor(lo.y / 8.0)), int(floor(hi.y / 8.0)) + 1):
				var key: int = cx * 4096 + cy
				if not _tube_grid.has(key):
					_tube_grid[key] = []
				(_tube_grid[key] as Array).append(int(lid))

func _tube_doors(lid: int) -> Array:
	var out: Array = []
	var l: Dictionary = sim.state["buildings"][lid]
	for end in ["a", "b"]:
		var r: int = int(l.get(end, -1))
		for d in doors_of(r):
			if int(d["link"]) == lid:
				out.append(d)
	return out

# ---------------------------------------------------------------- room grids
func _grid_key(rid: int, clear: float) -> String:
	var meta: Dictionary = view.bmeta[rid]
	var hb: int = int(view.doors.hb_masks.get(rid, 0)) if view.doors != null else 0
	var wm: int = _wm(rid)
	return "%s|%d|%d|%.2f" % [String(meta["tpl"].get("key", "")).get_slice("@", 0), hb, wm, clear]

## The coarse walk grid of a room (built on first use): blocked = furniture or wall within
## `clear`, or outside the wall ring. null when the room model has no wall ring. One distance
## field per model and door set serves both clearances.
func coarse(rid: int, clear: float = CLEAR):
	if not view.bmeta.has(rid) or not view.bmeta[rid].has("tpl"):
		return null
	var key: String = _grid_key(rid, clear)
	if _coarse.has(key):
		return _coarse[key]
	var tg0: int = Time.get_ticks_usec()
	var base = _dist_field(rid)
	stats["dist_ms"] = float(stats.get("dist_ms", 0.0)) + (Time.get_ticks_usec() - tg0) / 1000.0
	if base == null:
		_coarse[key] = null
		return null
	var n: int = base["n"]
	var half: float = base["half"]
	var wr: float = base["wall_r"]
	var dist: PackedFloat32Array = base["dist"]
	var blk := PackedByteArray()
	blk.resize(n * n)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	var lim2: float = (wr - 0.55) * (wr - 0.55)
	for j in n:
		var cy: float = (j + 0.5) * CELL - half
		for i in n:
			var k: int = j * n + i
			var cx: float = (i + 0.5) * CELL - half
			if dist[k] < clear or cx * cx + cy * cy > lim2:
				blk[k] = 1
				astar.set_point_solid(Vector2i(i, j), true)
	var cg := {"n": n, "half": half, "blk": blk, "astar": astar, "wall_r": wr}
	_coarse[key] = cg
	stats["grids"] = int(stats["grids"]) + 1
	stats["grid_ms"] = float(stats.get("grid_ms", 0.0)) + (Time.get_ticks_usec() - tg0) / 1000.0
	return cg

static var _dists := {}
## Distance (m, chamfer) from every coarse cell centre to the nearest furniture or wall.
func _dist_field(rid: int):
	var dkey: String = _grid_key(rid, -1.0)
	if _dists.has(dkey):
		return _dists[dkey]
	var tn0: int = Time.get_ticks_usec()
	var g: Dictionary = Nav.grid_of(view.bmeta[rid]["tpl"])
	stats["navload_ms"] = float(stats.get("navload_ms", 0.0)) + (Time.get_ticks_usec() - tn0) / 1000.0
	if g.is_empty():
		_dists[dkey] = null
		return null
	var hb: int = int(view.doors.hb_masks.get(rid, 0)) if view.doors != null else 0
	var wm: int = _wm(rid)
	var half: float = g["half"]
	var n: int = int(ceil(2.0 * half / CELL))
	var fn: int = g["n"]
	var focc: PackedByteArray = g["occ"]
	var ftall: PackedInt32Array = g["tall"]
	var fws: PackedByteArray = g.get("wseg", PackedByteArray())
	var has_w: bool = fws.size() == focc.size()
	var big := 1e6
	var dist := PackedFloat32Array()
	dist.resize(n * n)
	dist.fill(big)
	var ratio: float = Nav.CELL / CELL
	for fj in fn:
		var cj: int = mini(n - 1, int(fj * ratio))
		var row: int = fj * fn
		for fi in fn:
			var k: int = row + fi
			var o: int = focc[k]
			if o == 0:
				var ws: int = fws[k] if has_w else 0
				var wall_blk: bool = ws > 0 and (wm & (1 << (ws - 1))) == 0
				var ts: int = ftall[k]
				if not wall_blk and (ts == 0 or (hb & (1 << (ts - 1))) != 0):
					continue
			dist[cj * n + mini(n - 1, int(fi * ratio))] = 0.0
	var d1: float = CELL
	var d2: float = CELL * 1.4142
	for j in n:
		for i in n:
			var k: int = j * n + i
			var v: float = dist[k]
			if v == 0.0:
				continue
			if i > 0: v = minf(v, dist[k - 1] + d1)
			if j > 0:
				v = minf(v, dist[k - n] + d1)
				if i > 0: v = minf(v, dist[k - n - 1] + d2)
				if i < n - 1: v = minf(v, dist[k - n + 1] + d2)
			dist[k] = v
	for j in range(n - 1, -1, -1):
		for i in range(n - 1, -1, -1):
			var k: int = j * n + i
			var v: float = dist[k]
			if v == 0.0:
				continue
			if i < n - 1: v = minf(v, dist[k + 1] + d1)
			if j < n - 1:
				v = minf(v, dist[k + n] + d1)
				if i < n - 1: v = minf(v, dist[k + n + 1] + d2)
				if i > 0: v = minf(v, dist[k + n - 1] + d2)
			dist[k] = v
	var base := {"n": n, "half": half, "wall_r": float(g["wall_r"]), "dist": dist}
	_dists[dkey] = base
	return base
func _to_local(rid: int, p: Vector3) -> Vector2:
	var meta: Dictionary = view.bmeta[rid]
	var s: float = float(meta["tpl"].get("scale", 1.0))
	var l: Vector3 = (meta["xf"] as Transform3D).affine_inverse() * p
	return Vector2(l.x, l.z) / maxf(s, 0.001)

func _to_world(rid: int, q: Vector2, y: float) -> Vector3:
	var meta: Dictionary = view.bmeta[rid]
	var s: float = float(meta["tpl"].get("scale", 1.0))
	var w: Vector3 = (meta["xf"] as Transform3D) * Vector3(q.x * s, 0.0, q.y * s)
	return Vector3(w.x, y, w.z)

func _cell(cg: Dictionary, q: Vector2) -> Vector2i:
	var half: float = cg["half"]
	return Vector2i(int(floor((q.x + half) / CELL)), int(floor((q.y + half) / CELL)))

func blocked_local(cg: Dictionary, q: Vector2) -> bool:
	var c: Vector2i = _cell(cg, q)
	var n: int = cg["n"]
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return true
	return (cg["blk"] as PackedByteArray)[c.y * n + c.x] == 1

## True when p (world) stands on free floor of room rid (furniture + clearance excluded).
func free_in_room(rid: int, p: Vector3) -> bool:
	var cg = coarse(rid)
	if cg == null:
		return true
	return not blocked_local(cg, _to_local(rid, p))

## The nearest point on free floor of room rid to p (p itself when free).
func snap_free(rid: int, p: Vector3) -> Vector3:
	var cg = coarse(rid)
	if cg == null:
		return p
	var lq: Vector2 = _to_local(rid, p)
	if not blocked_local(cg, lq):
		return p
	var c: Vector2i = _nearest_free(cg, _cell(cg, lq))
	var half: float = cg["half"]
	return _to_world(rid, Vector2((c.x + 0.5) * CELL - half, (c.y + 0.5) * CELL - half), p.y)

func _nearest_free(cg: Dictionary, c: Vector2i) -> Vector2i:
	var n: int = cg["n"]
	var blk: PackedByteArray = cg["blk"]
	for r in range(0, 12):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := Vector2i(c.x + di, c.y + dj)
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and blk[q.y * n + q.x] == 0:
					return q
	return c

func _los(cg: Dictionary, a: Vector2, b: Vector2) -> bool:
	var d: float = a.distance_to(b)
	var steps: int = maxi(1, int(ceil(d / 0.12)))
	var n: int = cg["n"]
	var half: float = cg["half"]
	var blk: PackedByteArray = cg["blk"]
	for s in range(1, steps):
		var q: Vector2 = a.lerp(b, float(s) / steps)
		var i: int = int(floor((q.x + half) / CELL))
		var j: int = int(floor((q.y + half) / CELL))
		if i < 0 or j < 0 or i >= n or j >= n or blk[j * n + i] == 1:
			return false
	return true

## A path inside one room from a to b (world), around furniture: A*, then string-pulled.
## The end points themselves may be on blocked floor (a seat, a bed side): the path leaves
## and joins them by the nearest free cells.
func room_path(rid: int, a: Vector3, b: Vector3) -> Array:
	# Old-save airlocks: a doorway beside the chamber leads round the inner door housing.
	if view.get("airlock") != null:
		var wr = view.airlock.walkway_route(rid, a, b, self)
		if wr != null:
			return wr
	var r: Array = _room_path(rid, a, b, CLEAR)
	if r.is_empty():
		r = _room_path(rid, a, b, CLEAR_TIGHT)
		quality = maxi(quality, 1)
	if r.is_empty():
		quality = maxi(quality, 2)
		stats["fails"] = int(stats["fails"]) + 1
		# Last resort: the room's own aisle graph (ART-HAB's walking network).
		var meta: Dictionary = view.bmeta[rid]
		var ai: Array = npc._aisles_of(meta)
		return npc._aisle_route(ai, a, b) if not ai.is_empty() else [b]
	return r

func _room_path(rid: int, a: Vector3, b: Vector3, clear: float) -> Array:
	var cg = coarse(rid, clear)
	var fy: float = b.y
	if cg == null:
		return []
	var la: Vector2 = _to_local(rid, a)
	var lb: Vector2 = _to_local(rid, b)
	if _los(cg, la, lb):
		return [b]
	var ca: Vector2i = _nearest_free(cg, _cell(cg, la))
	var cb: Vector2i = _nearest_free(cg, _cell(cg, lb))
	var astar: AStarGrid2D = cg["astar"]
	stats["room_astar"] = int(stats["room_astar"]) + 1
	var raw: PackedVector2Array = astar.get_point_path(ca, cb)
	if raw.is_empty():
		return []
	var half: float = cg["half"]
	var pts: Array = [la]
	for v in raw:
		pts.append(Vector2((v.x + 0.5) * CELL - half, (v.y + 0.5) * CELL - half))
	pts.append(lb)
	# String pulling: from each kept point, the farthest point in sight.
	var out: Array = []
	var i := 0
	while i < pts.size() - 1:
		var j: int = pts.size() - 1
		while j > i + 1 and not _los(cg, pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	var w: Array = []
	for q in out:
		w.append(_to_world(rid, q, fy))
	return w

# ---------------------------------------------------------------- outside
func _blocked_out(q: Vector2, skip_a: Vector2, skip_b: Vector2) -> bool:
	_build_tube_grid()
	for lid in _tube_grid.get(int(floor(q.x / 8.0)) * 4096 + int(floor(q.y / 8.0)), []):
		var l: Dictionary = sim.state["buildings"].get(lid, {})
		if l.is_empty():
			continue
		var a: Vector2 = l["p0"]
		var ab: Vector2 = (l["p1"] as Vector2) - a
		var t: float = clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if q.distance_to(a + ab * t) < 1.45:
			return true
	for bid in _near_structures(q):
		var b: Dictionary = sim.state["buildings"].get(bid, {})
		if b.is_empty():
			continue
		var c: Vector2 = b["pos"]
		var lim: float = float(b["radius"]) * (0.8 if b["kind"] == "exterior" else 1.0) + 0.3
		if q.distance_to(c) < lim and skip_a.distance_to(c) >= lim and skip_b.distance_to(c) >= lim:
			return true
	return false

func _los_out(a: Vector2, b: Vector2) -> bool:
	var d: float = a.distance_to(b)
	var steps: int = maxi(1, int(ceil(d / 0.5)))
	for s in range(1, steps):
		if _blocked_out(a.lerp(b, float(s) / steps), a, b):
			return false
	return true

func out_path(a: Vector3, b: Vector3) -> Array:
	var qa := Vector2(a.x, a.z)
	var qb := Vector2(b.x, b.z)
	if _los_out(qa, qb):
		return [b]
	stats["out_paths"] = int(stats["out_paths"]) + 1
	var r: Dictionary = sim.nav.path_out(qa, qb) if sim.get("nav") != null else {"ok": false}
	if not bool(r.get("ok", false)):
		return [b]
	var pts: Array = [qa]
	for v in r["pts"]:
		pts.append(v)
	pts.append(qb)
	var out: Array = []
	var i := 0
	while i < pts.size() - 1:
		var j: int = pts.size() - 1
		while j > i + 1 and not _los_out(pts[i], pts[j]):
			j -= 1
		out.append(pts[j])
		i = j
	var w: Array = []
	for q in out:
		w.append(Vector3(q.x, view.h(q.x, q.y), q.y))
	w[-1] = b
	return w

## True when a and b (world) are in the same region and b is in straight sight of a there.
func same_leg(a: Vector3, b: Vector3, inside: bool) -> bool:
	var ra: Dictionary = region_of(a, inside)
	var rb: Dictionary = region_of(b, inside)
	if ra["k"] != rb["k"] or ra.get("id", -1) != rb.get("id", -1):
		return false
	match String(ra["k"]):
		"room":
			var cg = coarse(int(ra["id"]))
			return cg == null or _los(cg, _to_local(int(ra["id"]), a), _to_local(int(ra["id"]), b))
		"out":
			return _los_out(Vector2(a.x, a.z), Vector2(b.x, b.z))
	return true

## For an outdoor target inside a structure footprint (an outdoor route through a
## structure, V3_1 §4.2): the nearest point just outside that footprint.
var _bgrid := {}
var _bgrid_sig := ""
## Structures (not links) by 16 m cell, for the outdoor checks.
func _near_structures(q: Vector2) -> Array:
	var blds: Dictionary = sim.state["buildings"]
	var sig := "%d" % blds.size()
	if sig != _bgrid_sig:
		_bgrid_sig = sig
		_bgrid = {}
		for bid in blds:
			var b: Dictionary = blds[bid]
			if b["kind"] == "link":
				continue
			var c: Vector2 = b["pos"]
			var r: float = float(b["radius"]) + 1.0
			for cx in range(int(floor((c.x - r) / 16.0)), int(floor((c.x + r) / 16.0)) + 1):
				for cy in range(int(floor((c.y - r) / 16.0)), int(floor((c.y + r) / 16.0)) + 1):
					var key: int = cx * 4096 + cy
					if not _bgrid.has(key):
						_bgrid[key] = []
					(_bgrid[key] as Array).append(int(bid))
	return _bgrid.get(int(floor(q.x / 16.0)) * 4096 + int(floor(q.y / 16.0)), [])

## An indoor target that is neither in a room nor in a tube (the simulation walks rooms at
## their wall points): the nearest doorway point (room side or corridor side) within 4 m.
## A room whose wall p lies just outside of (within 1.5 m): its id, else -1. The simulation
## puts some indoor bodies on the wall circle of the room they are in.
func room_near(p: Vector3) -> int:
	var q := Vector2(p.x, p.z)
	var best := -1
	var bd := 1.5
	for rid in _near_structures(q):
		var b: Dictionary = sim.state["buildings"][int(rid)]
		if b["kind"] == "link" or doors_of(int(rid)).is_empty():
			continue
		var d: float = (q - (b["pos"] as Vector2)).length() - float(b["radius"])
		if d < bd:
			bd = d
			best = int(rid)
	return best

## p pulled on the radius into room rid, 0.65 m inside its wall line (the walk grid keeps
## 0.55 m of the model off the wall ring).
func pull_in(rid: int, p: Vector3) -> Vector3:
	var b: Dictionary = sim.state["buildings"][rid]
	var c: Vector2 = b["pos"]
	var v := Vector2(p.x, p.z) - c
	var lim: float = float(b["radius"]) - 0.2 - 0.65
	if v.length() > lim:
		v = v.normalized() * lim
	return Vector3(c.x + v.x, p.y, c.y + v.y)

## (V3.1 milestone 4) An indoor body the simulation walks across open ground (a straight
## line between two corridors): the nearest corridor centre-line point within 14 m, else the
## nearest doorway point within 4 m. Never a target outdoors for an indoor body.
func indoor_snap(p: Vector3) -> Vector3:
	var best: Vector3 = p
	var bd := 4.0
	_build_tube_grid()
	var q := Vector2(p.x, p.z)
	var bt := 14.0
	var seen := {}
	var cx0: int = int(floor(q.x / 8.0))
	var cy0: int = int(floor(q.y / 8.0))
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			for lid in _tube_grid.get((cx0 + dx) * 4096 + cy0 + dy, []):
				if seen.has(lid):
					continue
				seen[lid] = true
				var l: Dictionary = sim.state["buildings"].get(lid, {})
				if l.is_empty():
					continue
				var a: Vector2 = l["p0"]
				var ab: Vector2 = (l["p1"] as Vector2) - a
				var tq: float = clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.05, 0.95)
				var cp: Vector2 = a + ab * tq
				var dd0: float = q.distance_to(cp)
				if dd0 < bt:
					bt = dd0
					best = Vector3(cp.x, p.y, cp.y)
	if bt < 14.0:
		bd = minf(bd, bt)
	for rid in _near_structures(Vector2(p.x, p.z)):
		for d in doors_of(int(rid)):
			for key in ["in", "out"]:
				var dp: Vector3 = d[key]
				var dd: float = Vector2(dp.x - p.x, dp.z - p.z).length()
				if dd < bd:
					bd = dd
					best = dp
	return best

func outside_of_structures(p: Vector3) -> Vector3:
	var q := Vector2(p.x, p.z)
	for bid in _near_structures(q):
		var b: Dictionary = sim.state["buildings"].get(bid, {})
		if b.is_empty():
			continue
		var c: Vector2 = b["pos"]
		var lim: float = float(b["radius"]) * (0.8 if b["kind"] == "exterior" else 1.0) + 0.35
		if q.distance_to(c) < lim:
			var dq: Vector2 = (q - c).normalized() if q.distance_to(c) > 0.01 else Vector2.RIGHT
			q = c + dq * lim
			return Vector3(q.x, view.h(q.x, q.y), q.y)
	return p

# ---------------------------------------------------------------- whole path
## The polyline (world points, the start excluded) from a to b. `inside` = the body is
## indoors (a corridor point counts as tube, not outdoors).
func plan(a: Vector3, b: Vector3, inside: bool) -> Array:
	var tp0: int = Time.get_ticks_usec()
	# Through an airlock (V3_1 §5.3): suit room -> inner door -> chamber -> outer door -> porch.
	var ar = view.airlock.route(a, b, inside, self) if view.get("airlock") != null else null
	var r: Array = ar if ar != null else _plan(a, b, inside)
	stats["plan_ms"] = float(stats.get("plan_ms", 0.0)) + (Time.get_ticks_usec() - tp0) / 1000.0
	return r

func _plan(a: Vector3, b: Vector3, inside: bool) -> Array:
	stats["plans"] = int(stats["plans"]) + 1
	quality = 0
	var ra: Dictionary = region_of(a, inside)
	var rb: Dictionary = region_of(b, inside)
	if ra["k"] == rb["k"] and ra.get("id", -1) == rb.get("id", -1):
		match String(ra["k"]):
			"room":
				return room_path(int(ra["id"]), a, b)
			"out":
				return out_path(a, b)
			_:
				return [b]
	# Door graph (cached, AStar3D): nodes are the doorway ends ("in" room side, "out" corridor
	# or porch side). Start and goal join it for this query only.
	_build_graph()
	var nodes: Array = _gnodes
	var idx: Dictionary = _gidx
	var nn: int = nodes.size()
	var S: int = nn
	var G: int = nn + 1
	_astar.add_point(S, a)
	_astar.add_point(G, b)
	for pair in [[S, ra, a], [G, rb, b]]:
		var src: int = pair[0]
		var rg: Dictionary = pair[1]
		match String(rg["k"]):
			"room":
				for d in doors_of(int(rg["id"])):
					_astar.connect_points(src, idx["%d:%d:in:%s" % [int(rg["id"]), int(d["link"]), str(d["dir"])]])
			"tube":
				for d in _tube_doors(int(rg["id"])):
					_astar.connect_points(src, idx["%d:%d:out:%s" % [int(d["room"]), int(d["link"]), str(d["dir"])]])
			_:
				for k2 in _gouter:
					_astar.connect_points(src, k2)
	var ids: PackedInt64Array = _astar.get_id_path(S, G)
	_astar.remove_point(S)
	_astar.remove_point(G)
	if ids.is_empty():
		stats["fails"] = int(stats["fails"]) + 1
		stats["graph_fails"] = int(stats.get("graph_fails", 0)) + 1
		return [b]
	var chain: Array = []
	for i in range(1, ids.size()):
		chain.append(int(ids[i]))
	# Expand: room legs by room_path, doorway and corridor legs straight, outdoor legs by out_path.
	var out: Array = []
	var cur: Vector3 = a
	var cur_reg: Dictionary = ra
	var prev_c := S
	for c in chain:
		var target: Vector3 = b if c == G else nodes[c][0]
		var treg: Dictionary = rb if c == G else _node_reg(nodes[c])
		# Through a doorway: the entry points between the opening and the room-side point.
		if prev_c != S and c != G and nodes[prev_c][1] == nodes[c][1] and not (nodes[c][1]["entry"] as Array).is_empty():
			var en: Array = (nodes[c][1]["entry"] as Array).duplicate()
			if nodes[c][2] == "out":
				en.reverse()
			out.append_array(en)
		prev_c = c
		if cur_reg["k"] == "room" and treg["k"] == "room" and int(cur_reg["id"]) == int(treg["id"]):
			out.append_array(room_path(int(cur_reg["id"]), cur, target))
		elif cur_reg["k"] == "out" and treg["k"] == "out":
			out.append_array(out_path(cur, target))
		else:
			out.append(target)
		cur = target
		cur_reg = treg
		if c == G:
			break
	return out

var _graph_sig := ""
var _gnodes: Array = []
var _gidx := {}
var _gouter: Array = []
var _astar: AStar3D

func _build_graph() -> void:
	# doors_of() refreshes the door cache; the graph follows its signature.
	doors_of(-1)
	if _graph_sig == _door_sig and _astar != null:
		return
	_graph_sig = _door_sig
	_gnodes = []
	_gidx = {}
	_gouter = []
	_astar = AStar3D.new()
	for r in _doors:
		for d in _doors[r]:
			for end in ["in", "out"]:
				var key: String = "%d:%d:%s:%s" % [int(d["room"]), int(d["link"]), end, str(d["dir"])]
				if _gidx.has(key):
					continue
				_gnodes.append([d[end], d, end])
				_gidx[key] = _gnodes.size() - 1
				_astar.add_point(_gnodes.size() - 1, d[end])
	for r in _doors:
		var ds: Array = _doors[r]
		for i in ds.size():
			var ui: int = _gidx["%d:%d:in:%s" % [int(r), int(ds[i]["link"]), str(ds[i]["dir"])]]
			var uo: int = _gidx["%d:%d:out:%s" % [int(r), int(ds[i]["link"]), str(ds[i]["dir"])]]
			_astar.connect_points(ui, uo)
			for j in range(i + 1, ds.size()):
				_astar.connect_points(ui, _gidx["%d:%d:in:%s" % [int(r), int(ds[j]["link"]), str(ds[j]["dir"])]])
	for k in _gnodes.size():
		var d: Dictionary = _gnodes[k][1]
		if _gnodes[k][2] != "out":
			continue
		if int(d["link"]) < 0:
			_gouter.append(k)
			continue
		for k2 in range(k + 1, _gnodes.size()):
			if _gnodes[k2][2] == "out" and int(_gnodes[k2][1]["link"]) == int(d["link"]):
				_astar.connect_points(k, k2)
	for i in _gouter.size():
		for j in range(i + 1, _gouter.size()):
			_astar.connect_points(_gouter[i], _gouter[j])

func _node_reg(node: Array) -> Dictionary:
	if node[2] == "in":
		return {"k": "room", "id": int(node[1]["room"])}
	if int(node[1]["link"]) < 0:
		return {"k": "out"}
	return {"k": "edge"}