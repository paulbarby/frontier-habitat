extends RefCounted
## Walking graph (spec 4): outdoor one-metre cells plus the indoor room-and-corridor
## graph, joined only through airlocks and the lander hatch. A valid path never implies
## breathable air: the agent code checks suit time separately.
## A route is a list of legs:
##   {"m":"out","pts":[...],"len":m}   walk outside (suit air is used)
##   {"m":"in","pts":[...],"len":m}    walk through rooms and corridors
##   {"m":"lock","b":id,"dir":"in"|"out"}  wait for and ride an airlock cycle

var sim
var grid: AStarGrid2D
var rooms: AStar2D
var size: int = 256
## Outdoor paths between two cells, smoothed (derived data, cleared by rebuild()). The
## same inputs always give the same path, so the cache never changes a result.
var _paths := {}

const Ship = preload("res://sim/ship.gd")
const PATH_CACHE_MAX := 4000

func _init(s) -> void:
	sim = s

func rebuild() -> void:
	_paths = {}
	var world = sim.world
	size = world.size
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, size, size)
	grid.cell_size = Vector2(1, 1)
	grid.offset = Vector2(0.5, 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var m: int = int(sim.bal["map_margin"])
	grid.fill_solid_region(Rect2i(0, 0, size, m), true)
	grid.fill_solid_region(Rect2i(0, size - m, size, m), true)
	grid.fill_solid_region(Rect2i(0, 0, m, size), true)
	grid.fill_solid_region(Rect2i(size - m, 0, m, size), true)
	var qn: int = world.hn - 1
	var step: int = int(world.hstep)
	for qy in qn:
		for qx in qn:
			if world.steep[qy * qn + qx] == 1:
				grid.fill_solid_region(Rect2i(qx * step, qy * step, step, step), true)
	for r in world.rocks:
		_solid_disc(Vector2(r["x"], r["y"]), float(r["r"]))
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		# A plan that is not started yet is only marked on the ground: people walk over it.
		if b["state"] == "blueprint":
			continue
		if b["kind"] == "link":
			if b["def"] == "corridor":
				_solid_capsule(b["p0"], b["p1"], 1.3)
		elif b["def"] == "meridian":
			var seg: Array = Ship.segment_of(b)
			_solid_capsule(seg[0], seg[1], float(b["radius"]) - 0.2)
		else:
			_solid_disc(b["pos"], float(b["radius"]) - 0.2)

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

func _solid_disc(c: Vector2, r: float) -> void:
	var x0: int = maxi(0, int(floor(c.x - r)))
	var x1: int = mini(size - 1, int(floor(c.x + r)))
	var y0: int = maxi(0, int(floor(c.y - r)))
	var y1: int = mini(size - 1, int(floor(c.y + r)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				grid.set_point_solid(Vector2i(x, y), true)

func _solid_capsule(p0: Vector2, p1: Vector2, r: float) -> void:
	var x0: int = maxi(0, int(floor(minf(p0.x, p1.x) - r)))
	var x1: int = mini(size - 1, int(floor(maxf(p0.x, p1.x) + r)))
	var y0: int = maxi(0, int(floor(minf(p0.y, p1.y) - r)))
	var y1: int = mini(size - 1, int(floor(maxf(p0.y, p1.y) + r)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2(x + 0.5, y + 0.5)
			if c.distance_to(Geometry2D.get_closest_point_to_segment(c, p0, p1)) <= r:
				grid.set_point_solid(Vector2i(x, y), true)

# ---------------------------------------------------------------- outdoor
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x)), 0, size - 1), clampi(int(floor(p.y)), 0, size - 1))

func is_walkable(p: Vector2) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= size or p.y >= size:
		return false
	return not grid.is_point_solid(cell_of(p))

func nearest_walkable(p: Vector2, max_r: int = 4):
	var c: Vector2i = cell_of(p)
	if not grid.is_point_solid(c):
		return p
	var best = null
	var best_d := 1e9
	for dy in range(-max_r, max_r + 1):
		for dx in range(-max_r, max_r + 1):
			var q := Vector2i(c.x + dx, c.y + dy)
			if q.x < 0 or q.y < 0 or q.x >= size or q.y >= size or grid.is_point_solid(q):
				continue
			var cp := Vector2(q.x + 0.5, q.y + 0.5)
			var d: float = cp.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = cp
	return best

func path_out(a: Vector2, b: Vector2) -> Dictionary:
	var sa = nearest_walkable(a)
	var sb = nearest_walkable(b)
	if sa == null or sb == null:
		return {"ok": false}
	var ca: Vector2i = cell_of(sa)
	var cb: Vector2i = cell_of(sb)
	var key: int = ((ca.x * size + ca.y) * size + cb.x) * size + cb.y
	var smooth = _paths.get(key)
	if smooth == null:
		var raw: PackedVector2Array = grid.get_point_path(ca, cb)
		if raw.is_empty():
			smooth = []
		else:
			smooth = _smooth(raw)
		if _paths.size() >= PATH_CACHE_MAX:
			_paths = {}
		_paths[key] = smooth
	if (smooth as Array).is_empty():
		return {"ok": false}
	var pts: Array = (smooth as Array).duplicate()
	pts[0] = a if is_walkable(a) else pts[0]
	if is_walkable(b):
		pts[pts.size() - 1] = b
	if pts.size() == 1:
		pts.append(pts[0])
	return {"ok": true, "pts": pts, "len": _length(pts)}

func _smooth(raw: PackedVector2Array) -> Array:
	var out: Array = [raw[0]]
	var i := 0
	var n: int = raw.size()
	while i < n - 1:
		var j: int = mini(n - 1, i + 14)
		while j > i + 1 and not _clear_line(raw[i], raw[j]):
			j -= 1
		out.append(raw[j])
		i = j
	return out

func _clear_line(a: Vector2, b: Vector2) -> bool:
	var d: float = a.distance_to(b)
	var steps: int = int(ceil(d / 0.45))
	var side: Vector2 = (b - a).normalized().orthogonal() * 0.35
	for s in range(1, steps):
		var p: Vector2 = a.lerp(b, float(s) / steps)
		if grid.is_point_solid(cell_of(p)) or grid.is_point_solid(cell_of(p + side)) or grid.is_point_solid(cell_of(p - side)):
			return false
	return true

static func _length(pts: Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += (pts[i] as Vector2).distance_to(pts[i - 1])
	return l

# ---------------------------------------------------------------- places
func door_pos(b: Dictionary) -> Vector2:
	var dirv := Vector2(cos(b["rot"]), sin(b["rot"]))
	return b["pos"] + dirv * (float(b["radius"]) + 1.3)

## Interior standing place number `slot` of a room: a ring at 0.6 of the radius.
func slot_pos(b: Dictionary, slot: int) -> Vector2:
	var def: Dictionary = sim.bd(b)
	var n: int = maxi(1, int(def.get("slots", 4)))
	var a: float = float(b["rot"]) + deg_to_rad(22.5) + TAU * float(slot % n) / float(n)
	return b["pos"] + Vector2(cos(a), sin(a)) * float(b["radius"]) * 0.6

## Outdoor access points of a structure or construction site that are walkable now.
func access_points(b: Dictionary) -> Array:
	var out: Array = []
	if b["kind"] == "link":
		var mid: Vector2 = (b["p0"] + b["p1"]) * 0.5
		var n: Vector2 = (b["p1"] - b["p0"]).normalized().orthogonal()
		var off: float = 2.4 if b["def"] == "corridor" else 1.0
		for s in [1.0, -1.0]:
			var p: Vector2 = mid + n * off * s
			if is_walkable(p):
				out.append(p)
		if out.is_empty():
			for e in [b["p0"], b["p1"]]:
				var q = nearest_walkable(e, 5)
				if q != null:
					out.append(q)
		return out
	if b["def"] == "meridian":
		for p in sim.ship.access_candidates(b):
			if is_walkable(p):
				out.append(p)
		return out
	var r: float = float(b["radius"]) + 1.1
	for k in 8:
		var a: float = float(b["rot"]) + k * TAU / 8.0 + 0.39
		var p: Vector2 = b["pos"] + Vector2(cos(a), sin(a)) * r
		if is_walkable(p):
			out.append(p)
	return out

func best_access(b: Dictionary, from: Vector2):
	var pts: Array = access_points(b)
	if pts.is_empty():
		return null
	var best: Vector2 = pts[0]
	for p in pts:
		if (p as Vector2).distance_squared_to(from) < best.distance_squared_to(from):
			best = p
	return best

# ---------------------------------------------------------------- indoor
func path_in(from_b: int, from_p: Vector2, to_b: int, to_p: Vector2) -> Dictionary:
	if not rooms.has_point(from_b) or not rooms.has_point(to_b):
		return {"ok": false}
	var pts: Array = [from_p]
	if from_b != to_b:
		var ids: PackedInt64Array = rooms.get_id_path(from_b, to_b)
		if ids.is_empty():
			return {"ok": false}
		var blds: Dictionary = sim.state["buildings"]
		for i in range(ids.size() - 1):
			var a: Dictionary = blds[ids[i]]
			var b: Dictionary = blds[ids[i + 1]]
			var u: Vector2 = (b["pos"] - a["pos"]).normalized()
			pts.append(a["pos"] + u * float(a["radius"]))
			pts.append(b["pos"] - u * float(b["radius"]))
			if i + 1 < ids.size() - 1:
				pts.append(b["pos"])
	pts.append(to_p)
	return {"ok": true, "pts": pts, "len": _length(pts)}

# ---------------------------------------------------------------- full route
## loc = {"b": building id or -1 for outdoors, "p": position}
func plan(from: Dictionary, to: Dictionary) -> Dictionary:
	var fb: int = int(from["b"])
	var tb: int = int(to["b"])
	var topo = sim.topo
	if fb == -1 and tb == -1:
		var r: Dictionary = path_out(from["p"], to["p"])
		if not r["ok"]:
			return {"ok": false, "reason": "no_path"}
		return _route([{"m": "out", "pts": r["pts"], "len": r["len"]}])
	if fb != -1 and tb != -1 and topo.same_atmo(fb, tb):
		var r: Dictionary = path_in(fb, from["p"], tb, to["p"])
		if not r["ok"]:
			return {"ok": false, "reason": "no_path"}
		return _route([{"m": "in", "pts": r["pts"], "len": r["len"], "b": tb}])
	if fb != -1 and not topo.atmo_comp.has(fb):
		return {"ok": false, "reason": "no_path"}
	if tb != -1 and not topo.atmo_comp.has(tb):
		return {"ok": false, "reason": "not_commissioned"}
	var exits: Array = [-1] if fb == -1 else _nearest_locks(topo.atmo_comp[fb], to["p"])
	var entries: Array = [-1] if tb == -1 else _nearest_locks(topo.atmo_comp[tb], from["p"])
	if exits.is_empty() or entries.is_empty():
		return {"ok": false, "reason": "no_airlock"}
	var best := {}
	var best_len := 1e12
	var blds: Dictionary = sim.state["buildings"]
	for ex in exits:
		for en in entries:
			var legs: Array = []
			var start_out: Vector2 = from["p"]
			var ok := true
			if ex != -1:
				var lb: Dictionary = blds[ex]
				var r1: Dictionary = path_in(fb, from["p"], ex, lb["pos"])
				if not r1["ok"]:
					continue
				if r1["len"] > 0.01:
					legs.append({"m": "in", "pts": r1["pts"], "len": r1["len"], "b": ex})
				legs.append({"m": "lock", "b": ex, "dir": "out"})
				start_out = door_pos(lb)
			var end_out: Vector2 = to["p"]
			if en != -1:
				end_out = door_pos(blds[en])
			var ro: Dictionary = path_out(start_out, end_out)
			if not ro["ok"]:
				continue
			legs.append({"m": "out", "pts": ro["pts"], "len": ro["len"]})
			if en != -1:
				var eb: Dictionary = blds[en]
				legs.append({"m": "lock", "b": en, "dir": "in"})
				var r2: Dictionary = path_in(en, eb["pos"], tb, to["p"])
				if not r2["ok"]:
					ok = false
				elif r2["len"] > 0.01:
					legs.append({"m": "in", "pts": r2["pts"], "len": r2["len"], "b": tb})
			if not ok:
				continue
			var route: Dictionary = _route(legs)
			if route["len"] < best_len:
				best_len = route["len"]
				best = route
	if best.is_empty():
		return {"ok": false, "reason": "no_path"}
	return best

func _nearest_locks(comp: int, toward: Vector2) -> Array:
	var locks: Array = sim.topo.locks_by_comp.get(comp, []).duplicate()
	var blds: Dictionary = sim.state["buildings"]
	locks.sort_custom(func(a, b):
		var da: float = (blds[a]["pos"] as Vector2).distance_squared_to(toward)
		var db: float = (blds[b]["pos"] as Vector2).distance_squared_to(toward)
		return da < db if da != db else a < b)
	if locks.size() > 2:
		locks.resize(2)
	return locks

func _route(legs: Array) -> Dictionary:
	var out_len := 0.0
	var in_len := 0.0
	var locks := 0
	for l in legs:
		if l["m"] == "out":
			out_len += float(l["len"])
		elif l["m"] == "in":
			in_len += float(l["len"])
		else:
			locks += 1
	var cyc: float = float(sim.bal["airlock_cycle_seconds"])
	return {"ok": true, "legs": legs, "out_len": out_len, "in_len": in_len, "locks": locks,
		"len": out_len + in_len + locks * cyc * 2.0,
		"seconds": out_len / sim.util.out_speed() + in_len / float(sim.bal["speed_indoor"]) + locks * cyc}

## Outdoor seconds from an outdoor point to the door of the nearest SUPPLIED airlock.
## Returns {"ok", "seconds", "lock"}; used for suit-air decisions (spec 8).
func nearest_supplied_lock(from_p: Vector2) -> Dictionary:
	var best := {"ok": false, "seconds": 1e9, "lock": -1}
	var blds: Dictionary = sim.state["buildings"]
	var cands: Array = []
	for comp in sim.topo.locks_by_comp:
		if not sim.util.comp_supplied(comp):
			continue
		for lid in sim.topo.locks_by_comp[comp]:
			cands.append(lid)
	cands.sort_custom(func(a, b):
		var da: float = (blds[a]["pos"] as Vector2).distance_squared_to(from_p)
		var db: float = (blds[b]["pos"] as Vector2).distance_squared_to(from_p)
		return da < db if da != db else a < b)
	var tried := 0
	for lid in cands:
		if tried >= 2:
			break
		tried += 1
		var r: Dictionary = path_out(from_p, door_pos(blds[lid]))
		if r["ok"]:
			var secs: float = float(r["len"]) / sim.util.out_speed()
			if secs < float(best["seconds"]):
				best = {"ok": true, "seconds": secs, "lock": lid}
	return best
