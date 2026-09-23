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

static var _cache := {}

static func get_world(seed_value: int, planet: Dictionary, bal: Dictionary, map_size: int):
	var key := "%d:%s:%d" % [seed_value, planet.get("name", ""), map_size]
	if _cache.has(key):
		return _cache[key]
	var w = new()
	w._generate_valid(seed_value, planet, bal, map_size)
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
