extends RefCounted
## Seeded terrain (spec 4). The heightfield, rocks and deposit positions are DERIVED data:
## they are rebuilt from the seed after a load and never saved. Only the ore left in each
## deposit is state. Noise uses integer hashing and plain arithmetic, so a seed gives the
## same terrain on desktop and in the browser.

const Rng = preload("res://sim/rng.gd")

var size: int = 256
var hstep: float = 2.0
var hn: int = 129
var heights := PackedFloat32Array()
var steep := PackedByteArray()      # per 2 m quad: 1 = too steep to walk
var rocks: Array = []               # [{x, y, r, kind}] block walking and building
var deposit_sites: Array = []       # [{x, y, r, ore}] initial deposits
var meridian_sites: Array = []      # [{x, y, rot, score, dist}] crash sites for the Meridian, best first
var center := Vector2(128, 128)
var effective_seed: int = 0
var attempts: int = 0
## Version 3 (docs/V3_DESIGN.md section 1). version 2 = the 256 m map of v2 saves, made
## exactly as before; version 3 = the 810 m map of new games.
var version: int = 2
var margin: int = 4                 # metres at the map edge where nothing is built or walked
var gen_msec: int = 0               # time the last generation took (for the budget report)
## Whole-map features (derived, for the view and the hazard fields). Empty on v2 maps.
var flats: Array = []               # [{x, y, r}] silicate flats (dust devils start here)
var craters: Array = []             # [{x, y, r}] crater bowls of the terrain
var ridges: Array = []              # [{x0, y0, x1, y1, w, h}] rock ridges
var canyons: Array = []             # [{pts: [Vector2], w, d}] canyons
var basin := {}                     # {x, y, r} the impact basin (meteor-prone)
var fault := {}                     # {x0, y0, x1, y1} the fault line (quake-prone)
## Hazard zone fields on a coarse grid (hz_step metres), multipliers 0.5..2.0.
var hz_step: float = 16.0
var hz_n: int = 0
var hz_meteor := PackedFloat32Array()
var hz_wind := PackedFloat32Array()
var hz_quake := PackedFloat32Array()

static var _cache := {}

static func get_world(seed_value: int, planet: Dictionary, bal: Dictionary, map_size: int):
	var key := "%d:%s:%d" % [seed_value, planet.get("name", ""), map_size]
	if _cache.has(key):
		return _cache[key]
	var w = new()
	var t0: int = Time.get_ticks_msec()
	if map_size <= 256:
		w.margin = int(bal.get("map_margin_v2", 4))
		w._generate_valid(seed_value, planet, bal, map_size)
		w._hazard_fields_v2()
	else:
		w.margin = int(bal.get("map_margin", 8))
		w._generate_v3(seed_value, planet, bal, map_size)
	w.gen_msec = Time.get_ticks_msec() - t0
	_cache[key] = w
	return w

func _generate_valid(seed_value: int, planet: Dictionary, bal: Dictionary, map_size: int) -> void:
	# Reject seeds that fail the start-area constraints (spec 4), then try the next one.
	var s: int = seed_value
	for i in 24:
		attempts = i + 1
		_generate(s, planet, bal, map_size)
		if _validate(bal):
			effective_seed = s
			return
		s = (s + 7919) & 0x7FFFFFFF
	effective_seed = s
	push_warning("world_gen: no valid seed found near %d; using the last attempt" % seed_value)

func _generate(seed_value: int, planet: Dictionary, bal: Dictionary, map_size: int) -> void:
	size = map_size
	hn = int(size / hstep) + 1
	center = Vector2(size * 0.5, size * 0.5)
	heights = PackedFloat32Array()
	heights.resize(hn * hn)
	heights.fill(0.0)
	var t: Dictionary = planet["terrain"]
	var amp: float = float(t["amplitude"])
	var rough: float = float(t["roughness"])
	var cell := 64.0
	var a := amp
	for o in 4:
		_octave(Rng.stream_seed(seed_value, 100 + o), cell, a)
		cell *= 0.5
		a *= rough

	var rng := {"w": Rng.stream_seed(seed_value, 7)}
	var flat_r: float = float(t["flat_radius"])
	_flatten(center, flat_r * 0.78, flat_r * 1.4)

	# One guaranteed deposit near the start, the rest spread over the map.
	deposit_sites = []
	var ang: float = Rng.range_float(rng, "w", 0.0, TAU)
	var dist: float = Rng.range_float(rng, "w", flat_r * 0.72, flat_r * 0.95)
	var near := center + Vector2(cos(ang), sin(ang)) * dist
	_flatten(near, 9.0, 17.0)
	deposit_sites.append({"x": near.x, "y": near.y, "r": 9.5, "ore": 900})
	var want: int = int(t["deposits"])
	var guard := 0
	while deposit_sites.size() < want and guard < 400:
		guard += 1
		var p := Vector2(Rng.range_float(rng, "w", 30.0, size - 30.0), Rng.range_float(rng, "w", 30.0, size - 30.0))
		if p.distance_to(center) < flat_r * 1.5:
			continue
		var ok := true
		for d in deposit_sites:
			if p.distance_to(Vector2(d["x"], d["y"])) < 45.0:
				ok = false
		if ok:
			_flatten(p, 8.0, 15.0)
			deposit_sites.append({"x": p.x, "y": p.y, "r": Rng.range_float(rng, "w", 8.0, 11.0), "ore": Rng.range_int(rng, "w", 600, 1200)})

	# Rock obstacles away from the start area.
	rocks = []
	guard = 0
	while rocks.size() < 46 and guard < 600:
		guard += 1
		var p := Vector2(Rng.range_float(rng, "w", 8.0, size - 8.0), Rng.range_float(rng, "w", 8.0, size - 8.0))
		if p.distance_to(center) < flat_r * 0.95:
			continue
		var clear := true
		for d in deposit_sites:
			if p.distance_to(Vector2(d["x"], d["y"])) < float(d["r"]) + 4.0:
				clear = false
		if clear:
			rocks.append({"x": p.x, "y": p.y, "r": Rng.range_float(rng, "w", 0.9, 2.4), "kind": Rng.range_int(rng, "w", 0, 2), "rot": Rng.range_float(rng, "w", 0.0, TAU)})

	# Walk slope flags on the 2 m quads.
	var qn: int = hn - 1
	steep = PackedByteArray()
	steep.resize(qn * qn)
	var max_walk: float = float(bal["max_walk_slope"])
	for qy in qn:
		for qx in qn:
			var h00: float = heights[qy * hn + qx]
			var h10: float = heights[qy * hn + qx + 1]
			var h01: float = heights[(qy + 1) * hn + qx]
			var h11: float = heights[(qy + 1) * hn + qx + 1]
			var sx: float = absf((h10 + h11) - (h00 + h01)) * 0.5 / hstep
			var sy: float = absf((h01 + h11) - (h00 + h10)) * 0.5 / hstep
			steep[qy * qn + qx] = 1 if sqrt(sx * sx + sy * sy) > max_walk else 0
	_meridian_sites(bal)

# ---------------------------------------------------------------- version 3: the 810 m map
## Radius of the flat start plateau around the lander, and where it blends into the land.
const PLATEAU_R := 125.0
const PLATEAU_BLEND := 175.0

var _seed: int = 0

## The 810 m map (V3_DESIGN section 1): a broad swell with finer detail, an impact basin,
## a fault line, rock ridges, canyons, crater fields, silicate flats, ore fields near and
## far, exotic fields at least 220 m out, and a flat start plateau of 125 m radius. Every
## place comes from the seed; no attempt is rejected, so the time is fixed.
func _generate_v3(seed_value: int, planet: Dictionary, bal: Dictionary, map_size: int) -> void:
	version = 3
	attempts = 1
	effective_seed = seed_value
	_seed = seed_value
	size = map_size
	hn = int(size / hstep) + 1
	center = Vector2(size * 0.5, size * 0.5)
	heights = PackedFloat32Array()
	heights.resize(hn * hn)
	heights.fill(0.0)
	var t: Dictionary = planet["terrain"]
	var amp: float = float(t["amplitude"])
	var rough: float = float(t["roughness"])
	var cell := 256.0
	var a := amp * 1.5
	for o in 5:
		_octave(Rng.stream_seed(seed_value, 300 + o), cell, a)
		cell *= 0.5
		a *= rough
	var rng := {"w": Rng.stream_seed(seed_value, 17)}
	var c: Vector2 = center
	var reach: float = float(size) * 0.5 - 40.0
	# 1. The impact basin: a wide, shallow bowl far from the lander.
	var ba: float = _r(rng, 0.0, TAU)
	var bd: float = _r(rng, 250.0, minf(330.0, reach - 100.0))
	var br: float = _r(rng, 90.0, 120.0)
	var bp: Vector2 = c + Vector2(cos(ba), sin(ba)) * bd
	basin = {"x": bp.x, "y": bp.y, "r": br}
	_bowl(bp, br, _r(rng, 5.0, 8.0), 2.5)
	# 2. The fault line: long and straight, 170..260 m from the lander, with a low step.
	var fa: float = _r(rng, 0.0, TAU)
	var fdir := Vector2(cos(fa), sin(fa))
	var fmid: Vector2 = c + fdir.orthogonal() * _r(rng, 170.0, 260.0)
	var f0: Vector2 = fmid - fdir * float(size)
	var f1: Vector2 = fmid + fdir * float(size)
	fault = {"x0": f0.x, "y0": f0.y, "x1": f1.x, "y1": f1.y}
	_scarp(f0, f1, 2.0, 16.0)
	# 3. Rock ridges (windy high ground).
	ridges = []
	var want_r: int = Rng.range_int(rng, "w", 2, 3)
	var guard := 0
	while ridges.size() < want_r and guard < 60:
		guard += 1
		var m: Vector2 = _far_point(rng, 190.0, reach - 40.0)
		var ang: float = _r(rng, 0.0, TAU)
		var half: float = _r(rng, 55.0, 110.0)
		var w: float = _r(rng, 9.0, 13.0)
		var h: float = _r(rng, 7.0, 11.0)
		var u := Vector2(cos(ang), sin(ang))
		var p0: Vector2 = m - u * half
		var p1: Vector2 = m + u * half
		if not in_map(p0, 30.0) or not in_map(p1, 30.0):
			continue
		if Geometry2D.get_closest_point_to_segment(c, p0, p1).distance_to(c) < PLATEAU_BLEND:
			continue
		var clash := false
		for rd in ridges:
			if _seg_dist(p0, p1, Vector2(rd["x0"], rd["y0"]), Vector2(rd["x1"], rd["y1"])) < 60.0:
				clash = true
		if clash:
			continue
		ridges.append({"x0": p0.x, "y0": p0.y, "x1": p1.x, "y1": p1.y, "w": w, "h": h})
		_ridge(p0, p1, w, h)
	# 4. Canyons.
	canyons = []
	var want_c: int = Rng.range_int(rng, "w", 1, 2)
	guard = 0
	while canyons.size() < want_c and guard < 60:
		guard += 1
		var start: Vector2 = _far_point(rng, 210.0, reach - 30.0)
		var heading: Vector2 = (start - c).normalized().orthogonal().rotated(_r(rng, -0.5, 0.5))
		if Rng.next_float(rng, "w") < 0.5:
			heading = -heading
		var pts: Array = [start]
		for k in 3:
			heading = heading.rotated(_r(rng, -0.6, 0.6))
			pts.append((pts[pts.size() - 1] as Vector2) + heading * _r(rng, 60.0, 90.0))
		var ok := true
		for i in pts.size():
			if not in_map(pts[i], 25.0):
				ok = false
			if i > 0 and Geometry2D.get_closest_point_to_segment(c, pts[i - 1], pts[i]).distance_to(c) < PLATEAU_BLEND:
				ok = false
		if not ok:
			continue
		var cw: float = _r(rng, 6.0, 8.0)
		var cd: float = _r(rng, 7.0, 10.0)
		canyons.append({"pts": pts, "w": cw, "d": cd})
		_canyon(pts, cw, cd)
	# 5. Crater fields.
	craters = []
	for f in 3:
		var fc: Vector2 = _far_point(rng, 170.0, reach - 30.0)
		var n: int = Rng.range_int(rng, "w", 3, 6)
		for k in n:
			var cp: Vector2 = fc + Vector2(_r(rng, -45.0, 45.0), _r(rng, -45.0, 45.0))
			var cr: float = _r(rng, 6.0, 18.0)
			if cp.distance_to(c) < PLATEAU_BLEND + cr or not in_map(cp, cr + 14.0):
				continue
			craters.append({"x": cp.x, "y": cp.y, "r": cr})
			_bowl(cp, cr, cr * 0.2, cr * 0.07)
	# 6. The start plateau, after the features so that nothing digs into it.
	_flatten(c, PLATEAU_R, PLATEAU_BLEND)
	# 7. Silicate flats.
	flats = []
	var want_f: int = Rng.range_int(rng, "w", 3, 5)
	guard = 0
	while flats.size() < want_f and guard < 80:
		guard += 1
		var p: Vector2 = _far_point(rng, 160.0, reach - 40.0)
		var fr: float = _r(rng, 26.0, 50.0)
		if p.distance_to(c) < PLATEAU_BLEND + fr + 16.0 or not in_map(p, fr + 12.0) or not _clear_of_features(p, fr + 8.0):
			continue
		var apart := true
		for fl in flats:
			if p.distance_to(Vector2(fl["x"], fl["y"])) < fr + float(fl["r"]) + 30.0:
				apart = false
		if not apart:
			continue
		flats.append({"x": p.x, "y": p.y, "r": fr})
		_flatten(p, fr, fr + 16.0)
	# 8. Deposits: the start one (as in version 2), ore fields near and far, exotic fields.
	deposit_sites = []
	var flat_r: float = float(t["flat_radius"])
	var ang0: float = _r(rng, 0.0, TAU)
	var dist0: float = _r(rng, flat_r * 0.72, flat_r * 0.95)
	var near: Vector2 = c + Vector2(cos(ang0), sin(ang0)) * dist0
	_flatten(near, 9.0, 17.0)
	deposit_sites.append({"x": near.x, "y": near.y, "r": 9.5, "ore": 900})
	var want_ore: int = int(t["deposits"]) * 3
	guard = 0
	while deposit_sites.size() < want_ore and guard < 900:
		guard += 1
		# Two more ore fields near the plateau (75..150 m), the rest spread to the edge.
		var near_field: bool = deposit_sites.size() < 3
		var p: Vector2 = _far_point(rng, 75.0 if near_field else 150.0, 150.0 if near_field else reach - 25.0)
		if not _deposit_ok(p):
			continue
		_flatten(p, 8.0, 15.0)
		deposit_sites.append({"x": p.x, "y": p.y, "r": _r(rng, 8.0, 11.0), "ore": Rng.range_int(rng, "w", 600, 1200)})
	var want_x := 3
	var have_x := 0
	guard = 0
	while have_x < want_x and guard < 900:
		guard += 1
		var p: Vector2 = _far_point(rng, 220.0, reach - 25.0)
		if not _deposit_ok(p):
			continue
		_flatten(p, 9.0, 16.0)
		deposit_sites.append({"x": p.x, "y": p.y, "r": _r(rng, 9.0, 12.0), "ore": Rng.range_int(rng, "w", 400, 800), "exotic": true})
		have_x += 1
	# 9. Rocks: scattered, on the ridges, on crater rims and in rock fields.
	rocks = []
	for i in 110:
		_try_rock(rng, _far_point(rng, 110.0, reach + 20.0))
	for rd in ridges:
		var q0 := Vector2(rd["x0"], rd["y0"])
		var q1 := Vector2(rd["x1"], rd["y1"])
		var side: Vector2 = (q1 - q0).normalized().orthogonal()
		for i in 8:
			_try_rock(rng, q0.lerp(q1, _r(rng, 0.1, 0.9)) + side * _r(rng, -float(rd["w"]), float(rd["w"])))
	for cr in craters:
		for i in 2:
			var ra: float = _r(rng, 0.0, TAU)
			_try_rock(rng, Vector2(cr["x"], cr["y"]) + Vector2(cos(ra), sin(ra)) * float(cr["r"]) * 1.08)
	for f in 4:
		var fc: Vector2 = _far_point(rng, 140.0, reach - 20.0)
		for i in 10:
			_try_rock(rng, fc + Vector2(_r(rng, -22.0, 22.0), _r(rng, -22.0, 22.0)))
	# 10. Walk slopes, crash sites for the Meridian, hazard zones.
	_steep_flags(bal)
	_meridian_sites(bal)
	_hazard_fields_v3()

func _r(rng: Dictionary, lo: float, hi: float) -> float:
	return Rng.range_float(rng, "w", lo, hi)

## A point dmin..dmax metres from the lander, spread evenly over that ring's area.
func _far_point(rng: Dictionary, dmin: float, dmax: float) -> Vector2:
	var a: float = _r(rng, 0.0, TAU)
	var u: float = Rng.next_float(rng, "w")
	var d: float = sqrt(u * (dmax * dmax - dmin * dmin) + dmin * dmin)
	return center + Vector2(cos(a), sin(a)) * d

func _try_rock(rng: Dictionary, p: Vector2) -> void:
	var r: float = _r(rng, 0.9, 2.4)
	var kind: int = Rng.range_int(rng, "w", 0, 2)
	var rot: float = _r(rng, 0.0, TAU)
	if not in_map(p, float(margin) + 3.0) or p.distance_to(center) < 105.0:
		return
	for d in deposit_sites:
		if p.distance_to(Vector2(d["x"], d["y"])) < float(d["r"]) + 4.0:
			return
	rocks.append({"x": p.x, "y": p.y, "r": r, "kind": kind, "rot": rot})

func _deposit_ok(p: Vector2) -> bool:
	if not in_map(p, 30.0):
		return false
	for d in deposit_sites:
		if p.distance_to(Vector2(d["x"], d["y"])) < 45.0:
			return false
	if not _clear_of_features(p, 16.0):
		return false
	return slope_over(p, 12.0) <= 0.15

## True when a disc keeps clear of the ridges, canyons and craters.
func _clear_of_features(p: Vector2, r: float) -> bool:
	for rd in ridges:
		if Geometry2D.get_closest_point_to_segment(p, Vector2(rd["x0"], rd["y0"]), Vector2(rd["x1"], rd["y1"])).distance_to(p) < float(rd["w"]) * 2.5 + r:
			return false
	for cn in canyons:
		var pts: Array = cn["pts"]
		for i in range(1, pts.size()):
			if Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i]).distance_to(p) < float(cn["w"]) * 2.5 + r:
				return false
	for cr in craters:
		if p.distance_to(Vector2(cr["x"], cr["y"])) < float(cr["r"]) * 1.3 + r:
			return false
	return true

static func _seg_dist(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	var d: float = Geometry2D.get_closest_point_to_segment(a0, b0, b1).distance_to(a0)
	d = minf(d, Geometry2D.get_closest_point_to_segment(a1, b0, b1).distance_to(a1))
	d = minf(d, Geometry2D.get_closest_point_to_segment(b0, a0, a1).distance_to(b0))
	return minf(d, Geometry2D.get_closest_point_to_segment(b1, a0, a1).distance_to(b1))

## Grid index range [i0, i1] of the height samples within `r` of a coordinate.
func _span(v: float, r: float) -> Vector2i:
	return Vector2i(maxi(0, int((v - r) / hstep)), mini(hn - 1, int((v + r) / hstep) + 1))

## A crater bowl: depth at the centre, a raised rim at the edge.
func _bowl(p: Vector2, r: float, depth: float, rim: float) -> void:
	var sx: Vector2i = _span(p.x, r * 1.6)
	var sy: Vector2i = _span(p.y, r * 1.6)
	var rw: float = r * 0.3
	for y in range(sy.x, sy.y + 1):
		var dy: float = y * hstep - p.y
		for x in range(sx.x, sx.y + 1):
			var dx: float = x * hstep - p.x
			var d: float = sqrt(dx * dx + dy * dy)
			if d > r * 1.6:
				continue
			var k: float = (d - r) / rw
			var v: float = rim * exp(-k * k)
			if d < r:
				var q: float = d / r
				v -= depth * (1.0 - q * q)
			heights[y * hn + x] += v

## A ridge along a segment: a Gaussian profile of width w, tapered at both ends.
func _ridge(p0: Vector2, p1: Vector2, w: float, h: float) -> void:
	var reach: float = w * 3.0
	var sx: Vector2i = _span(minf(p0.x, p1.x) - reach, 0.0)
	var ex: Vector2i = _span(maxf(p0.x, p1.x) + reach, 0.0)
	var sy: Vector2i = _span(minf(p0.y, p1.y) - reach, 0.0)
	var ey: Vector2i = _span(maxf(p0.y, p1.y) + reach, 0.0)
	var ax: Vector2 = p1 - p0
	var len2: float = maxf(1e-6, ax.length_squared())
	for y in range(sy.x, ey.y + 1):
		for x in range(sx.x, ex.y + 1):
			var q := Vector2(x * hstep, y * hstep)
			var tt: float = clampf((q - p0).dot(ax) / len2, 0.0, 1.0)
			var d: float = q.distance_to(p0 + ax * tt)
			if d > reach:
				continue
			var taper: float = clampf(minf(tt, 1.0 - tt) * 5.0, 0.0, 1.0)
			taper = taper * taper * (3.0 - 2.0 * taper)
			var k: float = d / w
			heights[y * hn + x] += h * exp(-k * k) * taper

## A canyon along a polyline: a Gaussian trench of width w and depth d.
func _canyon(pts: Array, w: float, depth: float) -> void:
	var reach: float = w * 3.0
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var sx: Vector2i = _span(lo.x - reach, 0.0)
	var ex: Vector2i = _span(hi.x + reach, 0.0)
	var sy: Vector2i = _span(lo.y - reach, 0.0)
	var ey: Vector2i = _span(hi.y + reach, 0.0)
	var first: Vector2 = pts[0]
	var last: Vector2 = pts[pts.size() - 1]
	for y in range(sy.x, ey.y + 1):
		for x in range(sx.x, ex.y + 1):
			var q := Vector2(x * hstep, y * hstep)
			var d := 1e9
			for i in range(1, pts.size()):
				d = minf(d, Geometry2D.get_closest_point_to_segment(q, pts[i - 1], pts[i]).distance_to(q))
			if d > reach:
				continue
			var taper: float = clampf(minf(q.distance_to(first), q.distance_to(last)) / 25.0, 0.0, 1.0)
			var k: float = d / w
			heights[y * hn + x] -= depth * exp(-k * k) * taper

## A low step along the fault line: the ground on one side is `h` higher.
func _scarp(f0: Vector2, f1: Vector2, h: float, w: float) -> void:
	var n: Vector2 = (f1 - f0).normalized().orthogonal()
	var off: float = n.dot(f0)
	for y in hn:
		var py: float = y * hstep
		for x in hn:
			var s: float = n.x * x * hstep + n.y * py - off
			if s <= -w:
				continue
			var k: float = clampf((s + w) / (2.0 * w), 0.0, 1.0)
			heights[y * hn + x] += h * k * k * (3.0 - 2.0 * k)

func _steep_flags(bal: Dictionary) -> void:
	var qn: int = hn - 1
	steep = PackedByteArray()
	steep.resize(qn * qn)
	var lim: float = float(bal["max_walk_slope"]) * hstep * 2.0
	var lim2: float = lim * lim
	for qy in qn:
		var r0: int = qy * hn
		var r1: int = r0 + hn
		for qx in qn:
			var h00: float = heights[r0 + qx]
			var h10: float = heights[r0 + qx + 1]
			var h01: float = heights[r1 + qx]
			var h11: float = heights[r1 + qx + 1]
			var sx: float = (h10 + h11) - (h00 + h01)
			var sy: float = (h01 + h11) - (h00 + h10)
			steep[qy * qn + qx] = 1 if sx * sx + sy * sy > lim2 else 0

# ---------------------------------------------------------------- hazard zones
## Three smooth fields, multipliers 0.5..2.0 (V3_DESIGN section 1): the impact basin is
## meteor-prone, the fault line quake-prone, high ground and ridges windy.
func _hazard_fields_v3() -> void:
	hz_n = int(ceil(float(size) / hz_step)) + 1
	hz_meteor = PackedFloat32Array()
	hz_wind = PackedFloat32Array()
	hz_quake = PackedFloat32Array()
	hz_meteor.resize(hz_n * hz_n)
	hz_wind.resize(hz_n * hz_n)
	hz_quake.resize(hz_n * hz_n)
	var bp := Vector2(basin["x"], basin["y"])
	var br: float = float(basin["r"])
	var f0 := Vector2(fault["x0"], fault["y0"])
	var f1 := Vector2(fault["x1"], fault["y1"])
	var lo := 1e9
	var hi := -1e9
	var hs := PackedFloat32Array()
	hs.resize(hz_n * hz_n)
	for j in hz_n:
		for i in hz_n:
			var h: float = height_at(i * hz_step, j * hz_step)
			hs[j * hz_n + i] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var span: float = maxf(1.0, hi - lo)
	for j in hz_n:
		for i in hz_n:
			var p := Vector2(i * hz_step, j * hz_step)
			var k: int = j * hz_n + i
			var nm: float = Rng.hash2(i, j, _seed ^ 0x51ED) * 0.2
			var db: float = p.distance_to(bp) / (br * 1.4)
			hz_meteor[k] = clampf(0.7 + nm + 1.3 * exp(-db * db), 0.5, 2.0)
			var nq: float = Rng.hash2(i, j, _seed ^ 0x2A7B) * 0.2
			var df: float = Geometry2D.get_closest_point_to_segment(p, f0, f1).distance_to(p) / 70.0
			hz_quake[k] = clampf(0.6 + nq + 1.4 * exp(-df * df), 0.5, 2.0)
			var rb := 0.0
			for rd in ridges:
				var dr: float = Geometry2D.get_closest_point_to_segment(p, Vector2(rd["x0"], rd["y0"]), Vector2(rd["x1"], rd["y1"])).distance_to(p) / (float(rd["w"]) * 3.0)
				rb = maxf(rb, exp(-dr * dr))
			hz_wind[k] = clampf(0.6 + 1.0 * (hs[k] - lo) / span + 0.5 * rb, 0.5, 2.0)

## Version-2 maps have no features: wind follows the height, meteors and quakes are even.
func _hazard_fields_v2() -> void:
	hz_n = int(ceil(float(size) / hz_step)) + 1
	hz_meteor = PackedFloat32Array()
	hz_wind = PackedFloat32Array()
	hz_quake = PackedFloat32Array()
	hz_meteor.resize(hz_n * hz_n)
	hz_wind.resize(hz_n * hz_n)
	hz_quake.resize(hz_n * hz_n)
	hz_meteor.fill(1.0)
	hz_quake.fill(1.0)
	var lo := 1e9
	var hi := -1e9
	for j in hz_n:
		for i in hz_n:
			var h: float = height_at(i * hz_step, j * hz_step)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var span: float = maxf(1.0, hi - lo)
	for j in hz_n:
		for i in hz_n:
			hz_wind[j * hz_n + i] = 0.7 + 0.6 * (height_at(i * hz_step, j * hz_step) - lo) / span

## {meteor, wind, quake} at a point: the hazard zone multipliers, 0.5..2.0.
func hazard_at(p: Vector2) -> Dictionary:
	if hz_n <= 1:
		return {"meteor": 1.0, "wind": 1.0, "quake": 1.0}
	return {"meteor": _field(hz_meteor, p), "wind": _field(hz_wind, p), "quake": _field(hz_quake, p)}

func _field(f: PackedFloat32Array, p: Vector2) -> float:
	var fx: float = clampf(p.x / hz_step, 0.0, hz_n - 1.001)
	var fy: float = clampf(p.y / hz_step, 0.0, hz_n - 1.001)
	var i0: int = int(fx)
	var j0: int = int(fy)
	var tx: float = fx - i0
	var ty: float = fy - j0
	var a: float = f[j0 * hz_n + i0]
	var b: float = f[j0 * hz_n + i0 + 1]
	var c: float = f[(j0 + 1) * hz_n + i0]
	var d: float = f[(j0 + 1) * hz_n + i0 + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

## Crash sites for the Meridian (docs/AAA_DESIGN.md section 9): 55..75 m from the lander,
## flat, clear of rocks and deposits, in the direction with the fewest rocks. The wreck
## prefers the side away from the lander hatch (+x), where the base grows. The list is
## ordered best first; the simulation takes the first site no structure overlaps. No
## random numbers are drawn, so the rest of the world is the same as before.
func _meridian_sites(bal: Dictionary) -> void:
	meridian_sites = []
	var ship: Dictionary = bal.get("ship", {})
	var dmin: float = float(ship.get("distance_min", 55.0))
	var dmax: float = float(ship.get("distance_max", 75.0))
	var length: float = float(ship.get("capsule_length", 44.0))
	var rad: float = float(ship.get("capsule_radius", 7.0))
	var half: float = length * 0.5 - rad
	var dirs := 16
	for ai in dirs:
		var a: float = ai * TAU / dirs
		var u := Vector2(cos(a), sin(a))
		var sector := 0
		for rock in rocks:
			var rp: Vector2 = Vector2(rock["x"], rock["y"]) - center
			var dist: float = rp.length()
			if dist < 30.0 or dist > 105.0:
				continue
			if absf(angle_difference(a, rp.angle())) <= PI / dirs * 1.5:
				sector += 1
		var d: float = dmin
		while d <= dmax + 0.01:
			for tangential in [true, false]:
				var rot: float = a + PI * 0.5 if tangential else a
				var mid: Vector2 = center + u * d
				var ax := Vector2(cos(rot), sin(rot))
				var p0: Vector2 = mid - ax * half
				var p1: Vector2 = mid + ax * half
				if not _site_ok(p0, p1, rad):
					continue
				var flat: float = _site_flatness(p0, p1, rad)
				if flat > 0.12:
					continue
				var score: float = float(sector) * 2.0 + (u.x + 1.0) * 3.0 + flat * 40.0 + absf(d - 67.5) * 0.05 + (0.0 if tangential else 0.4)
				meridian_sites.append({"x": mid.x, "y": mid.y, "rot": fposmod(rot, TAU), "score": score, "dist": d, "dir": ai})
			d += 5.0
	meridian_sites.sort_custom(func(x, y):
		if float(x["score"]) != float(y["score"]):
			return float(x["score"]) < float(y["score"])
		if int(x["dir"]) != int(y["dir"]):
			return int(x["dir"]) < int(y["dir"])
		return float(x["dist"]) < float(y["dist"]))

func _site_ok(p0: Vector2, p1: Vector2, rad: float) -> bool:
	var margin: float = rad + 10.0
	for e in [p0, p1]:
		if not in_map(e, margin):
			return false
	for rock in rocks:
		var rp := Vector2(rock["x"], rock["y"])
		if Geometry2D.get_closest_point_to_segment(rp, p0, p1).distance_to(rp) < rad + float(rock["r"]) + 1.5:
			return false
	for dep in deposit_sites:
		var dp := Vector2(dep["x"], dep["y"])
		if Geometry2D.get_closest_point_to_segment(dp, p0, p1).distance_to(dp) < rad + float(dep["r"]) + 4.0:
			return false
	# Nothing steep under the hull or on the walkway around it.
	var ax: Vector2 = (p1 - p0).normalized()
	var side: Vector2 = ax.orthogonal()
	for i in 9:
		var c: Vector2 = p0.lerp(p1, float(i) / 8.0)
		for off in [-rad - 2.0, -rad * 0.5, 0.0, rad * 0.5, rad + 2.0]:
			var q: Vector2 = c + side * off
			if is_steep_cell(int(q.x), int(q.y)):
				return false
	return true

## Height range under the hull divided by its length (0 = flat).
func _site_flatness(p0: Vector2, p1: Vector2, rad: float) -> float:
	var side: Vector2 = (p1 - p0).normalized().orthogonal()
	var lo := 1e9
	var hi := -1e9
	for i in 9:
		var c: Vector2 = p0.lerp(p1, float(i) / 8.0)
		for off in [-rad, 0.0, rad]:
			var q: Vector2 = c + side * off
			var h: float = height_at(q.x, q.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return (hi - lo) / maxf(1.0, p0.distance_to(p1) + 2.0 * rad)

func _octave(seed_value: int, cell: float, amp: float) -> void:
	var lw: int = int(ceil(size / cell)) + 2
	var lat := PackedFloat32Array()
	lat.resize(lw * lw)
	for j in lw:
		for i in lw:
			lat[j * lw + i] = Rng.hash2(i, j, seed_value)
	for sy in hn:
		var fy: float = sy * hstep / cell
		var j0: int = int(fy)
		var ty: float = fy - j0
		ty = ty * ty * (3.0 - 2.0 * ty)
		var row0: int = j0 * lw
		var row1: int = (j0 + 1) * lw
		for sx in hn:
			var fx: float = sx * hstep / cell
			var i0: int = int(fx)
			var tx: float = fx - i0
			tx = tx * tx * (3.0 - 2.0 * tx)
			var top: float = lat[row0 + i0] + (lat[row0 + i0 + 1] - lat[row0 + i0]) * tx
			var bot: float = lat[row1 + i0] + (lat[row1 + i0 + 1] - lat[row1 + i0]) * tx
			heights[sy * hn + sx] += amp * ((top + (bot - top) * ty) - 0.5)

func _flatten(p: Vector2, r_in: float, r_out: float) -> void:
	var x0: int = maxi(0, int((p.x - r_out) / hstep))
	var x1: int = mini(hn - 1, int((p.x + r_out) / hstep) + 1)
	var y0: int = maxi(0, int((p.y - r_out) / hstep))
	var y1: int = mini(hn - 1, int((p.y + r_out) / hstep) + 1)
	var sum := 0.0
	var n := 0
	for sy in range(y0, y1 + 1):
		for sx in range(x0, x1 + 1):
			if Vector2(sx * hstep, sy * hstep).distance_to(p) <= r_in:
				sum += heights[sy * hn + sx]
				n += 1
	if n == 0:
		return
	var level: float = sum / n
	for sy in range(y0, y1 + 1):
		for sx in range(x0, x1 + 1):
			var d: float = Vector2(sx * hstep, sy * hstep).distance_to(p)
			if d >= r_out:
				continue
			var w: float = clampf((d - r_in) / (r_out - r_in), 0.0, 1.0)
			w = w * w * (3.0 - 2.0 * w)
			var idx: int = sy * hn + sx
			heights[idx] = level + (heights[idx] - level) * w

func _validate(bal: Dictionary) -> bool:
	# 1. The start area is nearly level. 2. A deposit is near. 3. The near deposit can hold a mine.
	if slope_over(center, 36.0) > 0.06:
		return false
	if deposit_sites.is_empty():
		return false
	var d: Dictionary = deposit_sites[0]
	if slope_over(Vector2(d["x"], d["y"]), 5.0) > float(bal["max_slope_rooms"]):
		return false
	return true

# ---------------------------------------------------------------- queries
func height_at(x: float, y: float) -> float:
	var fx: float = clampf(x / hstep, 0.0, hn - 1.001)
	var fy: float = clampf(y / hstep, 0.0, hn - 1.001)
	var i0: int = int(fx)
	var j0: int = int(fy)
	var tx: float = fx - i0
	var ty: float = fy - j0
	var a: float = heights[j0 * hn + i0]
	var b: float = heights[j0 * hn + i0 + 1]
	var c: float = heights[(j0 + 1) * hn + i0]
	var d: float = heights[(j0 + 1) * hn + i0 + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

## (max - min) height over the diameter of a disc: the placement slope measure.
func slope_over(p: Vector2, r: float) -> float:
	var lo: float = height_at(p.x, p.y)
	var hi: float = lo
	for k in 8:
		var a: float = k * TAU / 8.0
		var h: float = height_at(p.x + cos(a) * r, p.y + sin(a) * r)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		var h2: float = height_at(p.x + cos(a) * r * 0.5, p.y + sin(a) * r * 0.5)
		lo = minf(lo, h2)
		hi = maxf(hi, h2)
	return (hi - lo) / maxf(1.0, 2.0 * r)

func is_steep_cell(cx: int, cy: int) -> bool:
	var qn: int = hn - 1
	var qx: int = clampi(int(cx / hstep), 0, qn - 1)
	var qy: int = clampi(int(cy / hstep), 0, qn - 1)
	return steep[qy * qn + qx] == 1

func in_map(p: Vector2, margin: float) -> bool:
	return p.x >= margin and p.y >= margin and p.x <= size - margin and p.y <= size - margin
