extends RefCounted
## The version-4 planet (docs/V4_DESIGN.md section 1): 2,560 m x 2,560 m with mountain
## ranges (and passes), high plateaus (and ramps), deep craters (dark floors, cold traps),
## crevices, boulder fields, dunes, and the older canyons, ridges, craters and flats. Also
## the radiation field, the horizon (sun) map and the places of every material tier.
## Everything comes from the seed and content/terrain_v4.json; nothing is saved. The world
## object is sim/world_gen.gd: this file fills its fields (generate()).
##
## Speed (budget 4 s): the noise is summed on small lattices and upsampled once with cubic
## interpolation (Image.resize); features touch only their bounding boxes.

const Rng = preload("res://sim/rng.gd")

static func generate(w, seed_value: int, planet: Dictionary, bal: Dictionary, cfg: Dictionary) -> void:
	w.version = 4
	w.attempts = 1
	w.effective_seed = seed_value
	w._seed = seed_value
	w.v4 = cfg
	w.size = int(cfg.get("size", 2560))
	w.hstep = float(cfg.get("hstep", 4.0))
	w.hn = int(w.size / w.hstep) + 1
	w.center = Vector2(w.size * 0.5, w.size * 0.5)
	w.margin = int(cfg.get("margin", 16))
	var tm: Dictionary = {}
	var t0: int = Time.get_ticks_usec()
	_noise(w, seed_value, cfg)
	tm["noise"] = Time.get_ticks_usec() - t0
	var rng := {"w": Rng.stream_seed(seed_value, 41)}
	var claims: Array = []        # [Vector2 centre, radius]: big features keep apart
	var pr: float = float(cfg.get("plateau_blend", 210.0))
	claims.append([w.center, pr + 60.0])
	t0 = Time.get_ticks_usec()
	_deep_craters(w, rng, cfg, claims)
	_mountains(w, rng, cfg, claims)
	_plateaus(w, rng, cfg, claims)
	_dunes(w, rng, cfg, claims)
	_crevices(w, rng, cfg, claims)
	_ridges_canyons(w, rng, cfg, claims)
	_small_craters(w, rng, cfg)
	tm["features"] = Time.get_ticks_usec() - t0
	# The start plateau, after the features so that nothing digs into it.
	w._flatten(w.center, float(cfg.get("plateau_r", 125.0)), pr)
	t0 = Time.get_ticks_usec()
	_flats(w, rng, cfg, claims)
	# Ramps and passes last: they join heights the other features made.
	_apply_ramps(w)
	tm["ramps"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	_materials(w, rng, cfg, planet)
	# No spikes on the ranges (critic round 18): after the peak pads are cut.
	for bx in w.get_meta("mboxes", []):
		_limit_slopes(w, int(bx[0]), int(bx[1]), int(bx[2]), int(bx[3]), float(cfg["mountains"].get("max_slope", 1.4)), 16)
	w.remove_meta("mboxes")
	_boulders_and_rocks(w, rng, cfg)
	w.index_rocks()
	tm["places"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	w._steep_flags(bal)
	_crevice_flags(w)
	tm["steep"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	_horizon(w, cfg)
	tm["horizon"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	_radiation(w, cfg, planet)
	_hazard_zones(w)
	tm["fields"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	w._meridian_sites(bal)
	tm["meridian"] = Time.get_ticks_usec() - t0
	w.gen_parts = tm

static func _r(rng: Dictionary, lo: float, hi: float) -> float:
	return Rng.range_float(rng, "w", lo, hi)

static func _ri(rng: Dictionary, a: Array) -> int:
	return Rng.range_int(rng, "w", int(a[0]), int(a[1]))

static func _rf(rng: Dictionary, a: Array) -> float:
	return Rng.range_float(rng, "w", float(a[0]), float(a[1]))

## A point dmin..dmax from the centre, even over the ring's area.
static func _far(w, rng: Dictionary, dmin: float, dmax: float) -> Vector2:
	var a: float = _r(rng, 0.0, TAU)
	var u: float = Rng.next_float(rng, "w")
	var d: float = sqrt(u * (dmax * dmax - dmin * dmin) + dmin * dmin)
	return w.center + Vector2(cos(a), sin(a)) * d

static func _free(claims: Array, p: Vector2, r: float) -> bool:
	for c in claims:
		if p.distance_to(c[0]) < r + float(c[1]):
			return false
	return true

static func _poly_free(claims: Array, pts: Array, r: float) -> bool:
	for c in claims:
		var cp: Vector2 = c[0]
		for i in range(1, pts.size()):
			if Geometry2D.get_closest_point_to_segment(cp, pts[i - 1], pts[i]).distance_to(cp) < r + float(c[1]):
				return false
	return true

static func _poly_in_map(w, pts: Array, m: float) -> bool:
	for p in pts:
		if not w.in_map(p, m):
			return false
	return true

static func _poly_dist(q: Vector2, pts: Array) -> float:
	var d := 1e18
	for i in range(1, pts.size()):
		d = minf(d, Geometry2D.get_closest_point_to_segment(q, pts[i - 1], pts[i]).distance_to(q))
	return d

## Distance to a polyline and the arc position (0..1) of the nearest point.
static func _poly_near(q: Vector2, pts: Array, lens: Array, total: float) -> Vector2:
	var best := 1e18
	var at := 0.0
	var acc := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var cp: Vector2 = Geometry2D.get_closest_point_to_segment(q, a, b)
		var d: float = cp.distance_to(q)
		if d < best:
			best = d
			at = (acc + a.distance_to(cp)) / maxf(1.0, total)
		acc += float(lens[i - 1])
	return Vector2(best, at)

static func _bent_line(w, rng: Dictionary, start: Vector2, heading: Vector2, segs: int, total: float, bend: float) -> Array:
	var pts: Array = [start]
	var h: Vector2 = heading
	for k in segs:
		h = h.rotated(_r(rng, -bend, bend))
		pts.append((pts[pts.size() - 1] as Vector2) + h * (total / float(segs)))
	return pts

# ---------------------------------------------------------------- noise
## Octaves summed on lattices, coarse to fine: the sum is carried to each finer lattice with
## cubic interpolation, the finest is upsampled to the height grid. Linear, so the result is
## the sum of smooth octaves; C++ does the big resize.
static func _noise(w, seed_value: int, cfg: Dictionary) -> void:
	var oct: Array = cfg.get("noise", [[640, 18.0], [320, 10.0], [160, 5.0], [80, 2.4], [40, 1.1], [20, 0.5]])
	var acc: Image = null
	for k in oct.size():
		var cell: float = float(oct[k][0])
		var amp: float = float(oct[k][1])
		var n: int = int(ceil(float(w.size) / cell)) + 1
		var data := PackedFloat32Array()
		data.resize(n * n)
		var s: int = Rng.stream_seed(seed_value, 500 + k)
		for j in n:
			for i in n:
				data[j * n + i] = amp * (Rng.hash2(i, j, s) - 0.5)
		if acc != null:
			acc.resize(n, n, Image.INTERPOLATE_CUBIC)
			var prev: PackedFloat32Array = acc.get_data().to_float32_array()
			for q in n * n:
				data[q] += prev[q]
		acc = Image.create_from_data(n, n, false, Image.FORMAT_RF, data.to_byte_array())
	acc.resize(w.hn, w.hn, Image.INTERPOLATE_CUBIC)
	w.heights = acc.get_data().to_float32_array()

# ---------------------------------------------------------------- mountains
static func _mountains(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var m: Dictionary = cfg["mountains"]
	w.mountains = []
	var want: int = _ri(rng, m["count"])
	var guard := 0
	var reach: float = float(w.size) * 0.5 - 60.0
	while w.mountains.size() < want and guard < 80:
		guard += 1
		var total: float = _rf(rng, m["length"])
		var width: float = _rf(rng, m["width"])
		var height: float = _rf(rng, m["height"])
		# Later attempts make the range shorter, so a crowded map still gets its ranges.
		total *= maxf(0.45, 1.0 - float(guard) * 0.012)
		var start: Vector2 = _far(w, rng, 380.0, reach)
		var heading: Vector2 = Vector2.RIGHT.rotated(_r(rng, 0.0, TAU))
		var pts: Array = _bent_line(w, rng, start, heading, int(m.get("segments", 4)), total, 0.45)
		var span: float = width * 2.2
		if not _poly_in_map(w, pts, span * 0.5 + 20.0):
			continue
		if not _poly_free(claims, pts, span * 0.7):
			continue
		var lens: Array = []
		var tot := 0.0
		for i in range(1, pts.size()):
			var l: float = (pts[i] as Vector2).distance_to(pts[i - 1])
			lens.append(l)
			tot += l
		var passes: Array = []
		var np: int = _ri(rng, m["passes"])
		for k in np:
			passes.append((float(k) + 0.5) / float(np) * 0.7 + 0.15 + _r(rng, -0.06, 0.06))
		var pw: float = float(m.get("pass_width", 34.0)) / maxf(1.0, tot)
		var peak_s: float = _r(rng, 0.2, 0.8)
		var s1: int = Rng.stream_seed(w._seed, 900 + w.mountains.size())
		# Height: a Gaussian ridge; along the range it swells and falls (noise), tapers at the
		# ends, and drops to 10 % at each pass.
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var sx: Vector2i = w._span(lo.x - span, 0.0)
		var ex: Vector2i = w._span(hi.x + span, 0.0)
		var sy: Vector2i = w._span(lo.y - span, 0.0)
		var ey: Vector2i = w._span(hi.y + span, 0.0)
		var hs: float = w.hstep
		var hn: int = w.hn
		for y in range(sy.x, ey.y + 1):
			for x in range(sx.x, ex.y + 1):
				var q := Vector2(x * hs, y * hs)
				var dn: Vector2 = _poly_near(q, pts, lens, tot)
				if dn.x > span:
					continue
				var t: float = dn.y
				var taper: float = clampf(minf(t, 1.0 - t) * 6.0, 0.0, 1.0)
				taper = taper * taper * (3.0 - 2.0 * taper)
				var ft: float = t * 14.0
				var it: int = int(ft)
				var tf: float = ft - it
				tf = tf * tf * (3.0 - 2.0 * tf)
				var sw: float = 0.55 + 0.45 * lerpf(Rng.hash2(it, 3, s1), Rng.hash2(it + 1, 3, s1), tf) + 0.35 * exp(-pow((t - peak_s) / 0.12, 2.0))
				var dip := 1.0
				for ps in passes:
					var z: float = (t - float(ps)) / pw
					dip = minf(dip, 1.0 - 0.9 * exp(-z * z))
				var k: float = dn.x / width
				w.heights[y * hn + x] += height * sw * taper * dip * exp(-k * k)
		w.set_meta("mboxes", (w.get_meta("mboxes", []) as Array) + [[sx.x, ex.y, sy.x, ey.y]])
		var pass_pts: Array = []
		for ps in passes:
			pass_pts.append(_at_arc(pts, lens, tot, float(ps)))
		var peak: Vector2 = _at_arc(pts, lens, tot, peak_s)
		w.mountains.append({"pts": pts, "width": width, "height": height, "passes": pass_pts, "peak": peak})
		for p in pts:
			claims.append([p, span])

## Smooths height samples whose slope to a neighbour exceeds max_slope (3 x 3 mean), so no
## single cell stands out as a spike (critic round 18). Only inside the given box.
static func _limit_slopes(w, x0: int, x1: int, y0: int, y1: int, max_slope: float, passes: int) -> void:
	var hn: int = w.hn
	var lim: float = max_slope * w.hstep
	x0 = maxi(1, x0)
	y0 = maxi(1, y0)
	x1 = mini(hn - 2, x1)
	y1 = mini(hn - 2, y1)
	for p in passes:
		var src: PackedFloat32Array = w.heights
		var out: PackedFloat32Array = src.duplicate()
		var changed := 0
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var i: int = y * hn + x
				var h: float = src[i]
				var mx: float = maxf(maxf(absf(h - src[i - 1]), absf(h - src[i + 1])), maxf(absf(h - src[i - hn]), absf(h - src[i + hn])))
				if mx <= lim:
					continue
				var sum := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						sum += src[i + dy * hn + dx]
				out[i] = sum / 9.0
				changed += 1
		w.heights = out
		if changed == 0:
			break

static func _at_arc(pts: Array, lens: Array, total: float, t: float) -> Vector2:
	var want: float = t * total
	var acc := 0.0
	for i in range(1, pts.size()):
		var l: float = float(lens[i - 1])
		if acc + l >= want:
			return (pts[i - 1] as Vector2).lerp(pts[i], (want - acc) / maxf(1e-6, l))
		acc += l
	return pts[pts.size() - 1]

# ---------------------------------------------------------------- plateaus
static func _plateaus(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var c: Dictionary = cfg["plateaus"]
	w.plateaus = []
	var want: int = _ri(rng, c["count"])
	var guard := 0
	var reach: float = float(w.size) * 0.5 - 60.0
	var cliff: float = float(c.get("cliff", 14.0))
	var rl: float = float(c.get("ramp_len", 150.0))
	while w.plateaus.size() < want and guard < 120:
		guard += 1
		var r: float = _rf(rng, c["radius"]) * maxf(0.55, 1.0 - float(guard) * 0.008)
		var p: Vector2 = _far(w, rng, 330.0 + r * 0.5, reach - r)
		var ext: float = r + rl * 0.5 + 20.0
		if not w.in_map(p, ext) or not _free(claims, p, r + cliff + float(c.get("keep_away", 380.0)) * 0.2):
			continue
		var h: float = _rf(rng, c["height"])
		var hs: float = w.hstep
		var hn: int = w.hn
		var s1: int = Rng.stream_seed(w._seed, 1300 + w.plateaus.size())
		var sx: Vector2i = w._span(p.x, r + cliff * 3.0)
		var sy: Vector2i = w._span(p.y, r + cliff * 3.0)
		for y in range(sy.x, sy.y + 1):
			for x in range(sx.x, sx.y + 1):
				var q := Vector2(x * hs, y * hs)
				var off: Vector2 = q - p
				# A ragged edge: the radius wobbles with the angle.
				var ang: float = off.angle()
				var rr: float = r * (0.9 + 0.1 * Rng.hash2(int(fposmod(ang, TAU) * 6.0), 7, s1))
				var d: float = off.length()
				if d > rr + cliff:
					continue
				var k: float = clampf((d - rr) / cliff, 0.0, 1.0)
				w.heights[y * hn + x] += h * (1.0 - k * k * (3.0 - 2.0 * k))
		var ramps: Array = []
		var nr: int = _ri(rng, c["ramps"])
		var a0: float = _r(rng, 0.0, TAU)
		for k in nr:
			var a: float = a0 + TAU * float(k) / float(nr) + _r(rng, -0.3, 0.3)
			var u := Vector2(cos(a), sin(a))
			ramps.append({"x0": p.x + u.x * (r * 0.75), "y0": p.y + u.y * (r * 0.75), "x1": p.x + u.x * (r + rl), "y1": p.y + u.y * (r + rl), "w": float(c.get("ramp_width", 26.0))})
		w.plateaus.append({"x": p.x, "y": p.y, "r": r, "h": h, "ramps": ramps})
		claims.append([p, r + cliff])
		for rp in ramps:
			w._ramps.append(rp)

# ---------------------------------------------------------------- deep craters
## Smooth noise of an angle (period TAU), 0..1: n cells round the circle.
static func _ang_noise(a: float, n: float, s: int) -> float:
	var f: float = fposmod(a, TAU) / TAU * n
	var i: int = int(f)
	var t: float = f - i
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(Rng.hash2(i % int(n), 11, s), Rng.hash2((i + 1) % int(n), 11, s), t)

static func _deep_craters(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var c: Dictionary = cfg["deep_craters"]
	w.deep_craters = []
	var want: int = _ri(rng, c["count"])
	var guard := 0
	var reach: float = float(w.size) * 0.5 - 40.0
	var fl: float = float(c.get("floor", 0.5))
	var rim_k: float = float(c.get("rim", 0.12))
	while w.deep_craters.size() < want and guard < 150:
		guard += 1
		var r: float = _rf(rng, c["radius"]) * maxf(0.5, 1.0 - float(guard) * 0.01)
		var p: Vector2 = _far(w, rng, 380.0 + r * 0.6, reach - r * 1.1)
		if not w.in_map(p, r * 1.15 + 10.0) or not _free(claims, p, r * 1.25 + float(c.get("keep_away", 470.0)) * 0.08):
			continue
		var depth: float = clampf(r * _rf(rng, c["depth_ratio"]), float(c["depth"][0]), float(c["depth"][1]))
		var rim: float = depth * rim_k
		var hs: float = w.hstep
		var hn: int = w.hn
		var sx: Vector2i = w._span(p.x, r * 1.6)
		var sy: Vector2i = w._span(p.y, r * 1.6)
		var steps: int = int(c.get("terraces", 3))
		var s1: int = Rng.stream_seed(w._seed, 1500 + w.deep_craters.size())
		for y in range(sy.x, sy.y + 1):
			var dy: float = y * hs - p.y
			for x in range(sx.x, sx.y + 1):
				var dx: float = x * hs - p.x
				var d: float = sqrt(dx * dx + dy * dy)
				if d > r * 1.6:
					continue
				var q: float = d / r
				var v: float = 0.0
				var ang: float = atan2(dy, dx)
				# The rim wobbles a little round the crater (slumps).
				var wob: float = 1.0 + 0.04 * (_ang_noise(ang, 7.0, s1) - 0.5)
				var qq: float = q / wob
				if qq < 1.0:
					# Terraced inner wall: benches joined by steep risers, mixed with a smooth
					# wall so the steps are not perfectly even.
					var k: float = clampf((qq - fl) / (1.0 - fl), 0.0, 1.0)
					var tt: float = k * float(steps)
					var f0: float = floor(tt)
					var fr: float = tt - f0
					var riser: float = clampf((fr - 0.35) / 0.3, 0.0, 1.0)
					riser = riser * riser * (3.0 - 2.0 * riser)
					var kt: float = minf(1.0, (f0 + riser) / float(steps))
					var km: float = lerpf(k, kt, 0.7)
					v = -depth * (1.0 - km * km * (3.0 - 2.0 * km))
				# The rim lip: a sharp crest just inside r, falling steeply inside and gently
				# outside, then the debris apron with lumps out to 1.6 r.
				var e: float = qq - 1.0
				if e < 0.0:
					v += rim * exp(-pow(e / 0.06, 2.0))
				else:
					v += rim * exp(-pow(e / 0.14, 2.0))
					var lumps: float = 0.6 + 0.8 * Rng.hash2(int(x / 3), int(y / 3), s1)
					v += rim * 0.45 * exp(-e / 0.22) * lumps * clampf((1.6 - q) / 0.2, 0.0, 1.0)
				w.heights[y * hn + x] += v
		# One ramp down to the floor, long enough for a slope under about 0.45.
		var a: float = _r(rng, 0.0, TAU)
		var u := Vector2(cos(a), sin(a))
		var inner: float = r * fl * 0.8
		var outer: float = inner + (depth + rim) / 0.42
		var ramp := {"x0": p.x + u.x * inner, "y0": p.y + u.y * inner, "x1": p.x + u.x * outer, "y1": p.y + u.y * outer, "w": float(c.get("ramp_width", 24.0))}
		w._ramps.append(ramp)
		w.deep_craters.append({"x": p.x, "y": p.y, "r": r, "depth": depth, "floor_r": r * fl, "ramp": ramp})
		claims.append([p, r * 1.35])

# ---------------------------------------------------------------- crevices
static func _crevices(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var c: Dictionary = cfg["crevices"]
	w.crevices = []
	var want: int = _ri(rng, c["count"])
	var guard := 0
	var reach: float = float(w.size) * 0.5 - 40.0
	while w.crevices.size() < want and guard < 150:
		guard += 1
		var total: float = _rf(rng, c["length"])
		var start: Vector2 = _far(w, rng, 330.0, reach)
		var pts: Array = _bent_line(w, rng, start, Vector2.RIGHT.rotated(_r(rng, 0.0, TAU)), 5, total, 0.35)
		if not _poly_in_map(w, pts, 30.0) or not _poly_free(claims, pts, 20.0):
			continue
		var width: float = _rf(rng, c["width"])
		var depth: float = _rf(rng, c["depth"])
		# The heights show a narrow trench; walking uses the exact width (crevice_at).
		var vis_w: float = maxf(width * 0.5, 3.0)
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var reach_w: float = vis_w * 2.5 + 4.0
		var sx: Vector2i = w._span(lo.x - reach_w, 0.0)
		var ex: Vector2i = w._span(hi.x + reach_w, 0.0)
		var sy: Vector2i = w._span(lo.y - reach_w, 0.0)
		var ey: Vector2i = w._span(hi.y + reach_w, 0.0)
		var hs: float = w.hstep
		var hn: int = w.hn
		var first: Vector2 = pts[0]
		var last: Vector2 = pts[pts.size() - 1]
		for y in range(sy.x, ey.y + 1):
			for x in range(sx.x, ex.y + 1):
				var q := Vector2(x * hs, y * hs)
				var d: float = _poly_dist(q, pts)
				if d > reach_w:
					continue
				var taper: float = clampf(minf(q.distance_to(first), q.distance_to(last)) / 30.0, 0.0, 1.0)
				var k: float = d / vis_w
				w.heights[y * hn + x] -= depth * exp(-k * k * k * k) * taper
		w.crevices.append({"pts": pts, "w": width, "d": depth})
		for p in pts:
			claims.append([p, 25.0])

# ---------------------------------------------------------------- the older features, bigger
static func _ridges_canyons(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var rc: Dictionary = cfg["ridges"]
	w.ridges = []
	var reach: float = float(w.size) * 0.5 - 60.0
	var want: int = _ri(rng, rc["count"])
	var guard := 0
	while w.ridges.size() < want and guard < 120:
		guard += 1
		var m: Vector2 = _far(w, rng, 260.0, reach)
		var half: float = _rf(rng, rc["half"])
		var u := Vector2.RIGHT.rotated(_r(rng, 0.0, TAU))
		var p0: Vector2 = m - u * half
		var p1: Vector2 = m + u * half
		if not w.in_map(p0, 40.0) or not w.in_map(p1, 40.0) or not _poly_free(claims, [p0, p1], 40.0):
			continue
		var wd: float = _rf(rng, rc["width"])
		var h: float = _rf(rng, rc["height"])
		w.ridges.append({"x0": p0.x, "y0": p0.y, "x1": p1.x, "y1": p1.y, "w": wd, "h": h})
		w._ridge(p0, p1, wd, h)
		claims.append([m, half * 0.6])
	var cc: Dictionary = cfg["canyons"]
	w.canyons = []
	want = _ri(rng, cc["count"])
	guard = 0
	while w.canyons.size() < want and guard < 120:
		guard += 1
		var start: Vector2 = _far(w, rng, 300.0, reach)
		var pts: Array = [start]
		var hd: Vector2 = (start - w.center).normalized().orthogonal().rotated(_r(rng, -0.5, 0.5))
		for k in int(cc.get("segments", 4)):
			hd = hd.rotated(_r(rng, -0.6, 0.6))
			pts.append((pts[pts.size() - 1] as Vector2) + hd * _rf(rng, cc["seg_len"]))
		if not _poly_in_map(w, pts, 30.0) or not _poly_free(claims, pts, 30.0):
			continue
		var cw: float = _rf(rng, cc["width"])
		var cd: float = _rf(rng, cc["depth"])
		w.canyons.append({"pts": pts, "w": cw, "d": cd})
		w._canyon(pts, cw, cd)
		for p in pts:
			claims.append([p, 30.0])

static func _small_craters(w, rng: Dictionary, cfg: Dictionary) -> void:
	var c: Dictionary = cfg["small_craters"]
	w.craters = []
	var reach: float = float(w.size) * 0.5 - 40.0
	var pb: float = float(cfg.get("plateau_blend", 210.0))
	for f in int(c.get("fields", 8)):
		var fc: Vector2 = _far(w, rng, 230.0, reach)
		for k in _ri(rng, c["per_field"]):
			var cp: Vector2 = fc + Vector2(_r(rng, -60.0, 60.0), _r(rng, -60.0, 60.0))
			var cr: float = _rf(rng, c["radius"])
			if cp.distance_to(w.center) < pb + cr or not w.in_map(cp, cr + 20.0):
				continue
			w.craters.append({"x": cp.x, "y": cp.y, "r": cr})
			w._bowl(cp, cr, cr * 0.2, cr * 0.07)

static func _dunes(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var c: Dictionary = cfg["dunes"]
	w.dunes = []
	var want: int = _ri(rng, c["count"])
	var guard := 0
	var reach: float = float(w.size) * 0.5 - 60.0
	while w.dunes.size() < want and guard < 80:
		guard += 1
		var r: float = _rf(rng, c["radius"])
		var p: Vector2 = _far(w, rng, 300.0 + r, reach - r)
		if not w.in_map(p, r + 10.0) or not _free(claims, p, r):
			continue
		var wave: float = _rf(rng, c["wave"])
		var h: float = _rf(rng, c["height"])
		var dir := Vector2.RIGHT.rotated(_r(rng, 0.0, TAU))
		var hs: float = w.hstep
		var hn: int = w.hn
		var sx: Vector2i = w._span(p.x, r)
		var sy: Vector2i = w._span(p.y, r)
		for y in range(sy.x, sy.y + 1):
			for x in range(sx.x, sx.y + 1):
				var q := Vector2(x * hs, y * hs)
				var d: float = q.distance_to(p)
				if d > r:
					continue
				var fall: float = 1.0 - d / r
				fall = fall * fall * (3.0 - 2.0 * fall)
				# Asymmetric waves: a gentle windward side, a steeper lee.
				var ph: float = fposmod(q.dot(dir) / wave, 1.0)
				var v: float = (ph / 0.75) if ph < 0.75 else ((1.0 - ph) / 0.25)
				w.heights[y * hn + x] += h * fall * (v - 0.5)
		w.dunes.append({"x": p.x, "y": p.y, "r": r, "wave": wave, "h": h, "dir": dir.angle()})
		claims.append([p, r * 0.8])

static func _flats(w, rng: Dictionary, cfg: Dictionary, claims: Array) -> void:
	var c: Dictionary = cfg["flats"]
	w.flats = []
	var want: int = _ri(rng, c["count"])
	var guard := 0
	var reach: float = float(w.size) * 0.5 - 60.0
	var pb: float = float(cfg.get("plateau_blend", 210.0))
	while w.flats.size() < want and guard < 160:
		guard += 1
		var fr: float = _rf(rng, c["radius"])
		var p: Vector2 = _far(w, rng, pb + fr + 30.0, minf(reach - fr, 900.0))
		if not w.in_map(p, fr + 20.0) or not _free(claims, p, fr + 16.0):
			continue
		w.flats.append({"x": p.x, "y": p.y, "r": fr})
		w._flatten(p, fr, fr + 18.0)
		claims.append([p, fr + 16.0])

## A ramp: a straight corridor whose height runs linearly from one end to the other (the
## ends' heights after every other feature), blended into the ground at its sides.
static func _apply_ramps(w) -> void:
	var hs: float = w.hstep
	var hn: int = w.hn
	for rp in w._ramps:
		var p0 := Vector2(rp["x0"], rp["y0"])
		var p1 := Vector2(rp["x1"], rp["y1"])
		var h0: float = w.height_at(p0.x, p0.y)
		var h1: float = w.height_at(p1.x, p1.y)
		var half: float = float(rp["w"]) * 0.5
		var blend: float = 10.0
		var ax: Vector2 = p1 - p0
		var len2: float = maxf(1.0, ax.length_squared())
		var lo := Vector2(minf(p0.x, p1.x), minf(p0.y, p1.y)) - Vector2.ONE * (half + blend)
		var hi := Vector2(maxf(p0.x, p1.x), maxf(p0.y, p1.y)) + Vector2.ONE * (half + blend)
		var sx: Vector2i = w._span(lo.x, 0.0)
		var ex: Vector2i = w._span(hi.x, 0.0)
		var sy: Vector2i = w._span(lo.y, 0.0)
		var ey: Vector2i = w._span(hi.y, 0.0)
		for y in range(sy.x, ey.y + 1):
			for x in range(sx.x, ex.y + 1):
				var q := Vector2(x * hs, y * hs)
				var t: float = (q - p0).dot(ax) / len2
				if t < -0.02 or t > 1.02:
					continue
				var tc: float = clampf(t, 0.0, 1.0)
				var d: float = q.distance_to(p0 + ax * tc)
				if d > half + blend:
					continue
				var k: float = 1.0 if d <= half else 1.0 - (d - half) / blend
				k = k * k * (3.0 - 2.0 * k)
				var idx: int = y * hn + x
				w.heights[idx] = lerpf(w.heights[idx], lerpf(h0, h1, tc), k)

# ---------------------------------------------------------------- materials by tier
static func _materials(w, rng: Dictionary, cfg: Dictionary, planet: Dictionary) -> void:
	w.deposit_sites = []
	var mats: Dictionary = cfg.get("materials", {})
	var reach: float = float(w.size) * 0.5 - 40.0
	# The start deposit, as in versions 2 and 3: metal ore at the plateau's edge.
	var flat_r: float = float(planet["terrain"]["flat_radius"])
	var ang0: float = _r(rng, 0.0, TAU)
	var near: Vector2 = w.center + Vector2(cos(ang0), sin(ang0)) * _r(rng, flat_r * 0.72, flat_r * 0.95)
	w._flatten(near, 9.0, 17.0)
	w.deposit_sites.append({"x": near.x, "y": near.y, "r": 9.5, "ore": 900, "kind": "metal", "tier": 1})
	var keys: Array = mats.keys()
	keys.sort()
	for kind in keys:
		if String(kind).begins_with("_"):
			continue
		var m: Dictionary = mats[kind]
		var place: String = String(m.get("place", "plain"))
		var tier: int = int(m.get("tier", 1))
		match place:
			"plain", "radiation":
				var want: int = _ri(rng, m["count"])
				var have := 0
				var guard := 0
				while have < want and guard < 600:
					guard += 1
					var dmin: float = maxf(float(m["dist"][0]), 80.0)
					var p: Vector2 = _far(w, rng, dmin, minf(float(m["dist"][1]), reach - 30.0))
					if not _deposit_ok(w, p):
						continue
					if place == "radiation" and w.near_mountain(p) > 260.0 and _near_crater_rim(w, p) > 200.0 and p.distance_to(w.center) < 900.0:
						continue      # high-end ore lies out far or on the dangerous ground
					_add_deposit(w, rng, p, kind, tier, m)
					have += 1
			"plateau":
				var want2: int = _ri(rng, m["count"])
				var have2 := 0
				var guard2 := 0
				while have2 < want2 and guard2 < 200 and not w.plateaus.is_empty():
					guard2 += 1
					var pl: Dictionary = w.plateaus[Rng.range_int(rng, "w", 0, w.plateaus.size() - 1)]
					var p2: Vector2 = Vector2(pl["x"], pl["y"]) + Vector2.RIGHT.rotated(_r(rng, 0.0, TAU)) * _r(rng, 0.0, float(pl["r"]) * 0.6)
					if not _deposit_ok(w, p2, 0.2):
						continue
					_add_deposit(w, rng, p2, kind, tier, m)
					have2 += 1
			"crevice_edge", "crevice_floor":
				var per: int = 1 if place == "crevice_floor" else _ri(rng, m["count"])
				var n_done := 0
				for cv in w.crevices:
					if place == "crevice_edge" and n_done >= per:
						break
					var pts: Array = cv["pts"]
					for tries in 12:
						var i: int = Rng.range_int(rng, "w", 1, pts.size() - 1)
						var a: Vector2 = pts[i - 1]
						var b: Vector2 = pts[i]
						var c: Vector2 = a.lerp(b, _r(rng, 0.2, 0.8))
						var side: Vector2 = (b - a).normalized().orthogonal() * (1.0 if Rng.next_float(rng, "w") < 0.5 else -1.0)
						var off: float = float(cv["w"]) * 0.5 + (14.0 if place == "crevice_floor" else 28.0)
						var p3: Vector2 = c + side * off
						if not _deposit_ok(w, p3, 0.25, true):
							continue
						_add_deposit(w, rng, p3, kind, tier, m)
						n_done += 1
						break
			"crater_floor":
				for cr in w.deep_craters:
					var cp := Vector2(cr["x"], cr["y"])
					for tries in 16:
						var p4: Vector2 = cp + Vector2.RIGHT.rotated(_r(rng, 0.0, TAU)) * _r(rng, 0.0, float(cr["floor_r"]) * 0.7)
						if not _deposit_ok(w, p4, 0.2, true):
							continue
						_add_deposit(w, rng, p4, kind, tier, m)
						break
			"peak":
				for mt in w.mountains:
					var pk: Vector2 = mt["peak"]
					if not w.in_map(pk, 30.0):
						continue
					w._flatten(pk, 13.0, 26.0)
					_add_deposit(w, rng, pk, kind, tier, m, true)
			_:
				pass

static func _add_deposit(w, rng: Dictionary, p: Vector2, kind: String, tier: int, m: Dictionary, no_flatten: bool = false) -> void:
	var r: float = _rf(rng, m.get("radius", [8, 11]))
	if not no_flatten:
		w._flatten(p, r - 1.0, r + 7.0)
	var d := {"x": p.x, "y": p.y, "r": r, "ore": _ri(rng, m.get("amount", [400, 800])), "kind": kind, "tier": tier}
	if kind == "exotic":
		d["exotic"] = true
	w.deposit_sites.append(d)

static func _deposit_ok(w, p: Vector2, max_slope: float = 0.15, near_features: bool = false) -> bool:
	if not w.in_map(p, 40.0) or p.distance_to(w.center) < 70.0:
		return false
	for d in w.deposit_sites:
		if p.distance_to(Vector2(d["x"], d["y"])) < 45.0:
			return false
	if w.crevice_at(p, 12.0):
		return false
	if not near_features and w.near_mountain(p) < 20.0:
		return false
	return w.slope_over(p, 10.0) <= max_slope

static func _near_crater_rim(w, p: Vector2) -> float:
	var best := 1e9
	for cr in w.deep_craters:
		best = minf(best, absf(p.distance_to(Vector2(cr["x"], cr["y"])) - float(cr["r"])))
	return best

# ---------------------------------------------------------------- boulders and rocks
static func _boulders_and_rocks(w, rng: Dictionary, cfg: Dictionary) -> void:
	w.rocks = []
	w.boulder_fields = []
	var reach: float = float(w.size) * 0.5 - 30.0
	var bf: Dictionary = cfg["boulder_fields"]
	var want: int = _ri(rng, bf["count"])
	var guard := 0
	var pb: float = float(cfg.get("plateau_blend", 210.0))
	while w.boulder_fields.size() < want and guard < 120:
		guard += 1
		var r: float = _rf(rng, bf["radius"])
		var p: Vector2 = _far(w, rng, pb + r + 40.0, reach - r)
		if not w.in_map(p, r + 20.0) or w.near_mountain(p) < r:
			continue
		var clash := false
		for f in w.boulder_fields:
			if p.distance_to(Vector2(f["x"], f["y"])) < r + float(f["r"]) + float(bf.get("keep_away", 230.0)) * 0.3:
				clash = true
		if clash:
			continue
		w.boulder_fields.append({"x": p.x, "y": p.y, "r": r})
		for k in _ri(rng, bf["boulders"]):
			var q: Vector2 = p + Vector2.RIGHT.rotated(_r(rng, 0.0, TAU)) * r * sqrt(Rng.next_float(rng, "w"))
			var size: float = _rf(rng, bf["size"])
			_try_rock(w, rng, q, size * 0.5, 3)
	# Boulders on the crater floors (fallen from the walls), clear of the ramp.
	for cr in w.deep_craters:
		var cp := Vector2(cr["x"], cr["y"])
		var rp: Dictionary = cr["ramp"]
		for k in Rng.range_int(rng, "w", 6, 12):
			var q: Vector2 = cp + Vector2.RIGHT.rotated(_r(rng, 0.0, TAU)) * float(cr["floor_r"]) * (0.35 + 0.6 * sqrt(Rng.next_float(rng, "w")))
			var sz: float = _r(rng, 2.0, 6.0)
			if Geometry2D.get_closest_point_to_segment(q, Vector2(rp["x0"], rp["y0"]), Vector2(rp["x1"], rp["y1"])).distance_to(q) < float(rp["w"]) * 0.5 + sz + 4.0:
				continue
			_try_rock(w, rng, q, sz * 0.5, 3)
	var rk: Dictionary = cfg["rocks"]
	for i in int(rk.get("scattered", 1400)):
		var q2: Vector2 = _far(w, rng, 110.0, reach + 20.0)
		_try_rock(w, rng, q2, _rf(rng, rk["size"]), Rng.range_int(rng, "w", 0, 2))
	for rd in w.ridges:
		var q0 := Vector2(rd["x0"], rd["y0"])
		var q1 := Vector2(rd["x1"], rd["y1"])
		var side: Vector2 = (q1 - q0).normalized().orthogonal()
		for i in 8:
			_try_rock(w, rng, q0.lerp(q1, _r(rng, 0.1, 0.9)) + side * _r(rng, -float(rd["w"]), float(rd["w"])), _rf(rng, rk["size"]), Rng.range_int(rng, "w", 0, 2))
	for cr in w.craters:
		for i in 2:
			var ra: float = _r(rng, 0.0, TAU)
			_try_rock(w, rng, Vector2(cr["x"], cr["y"]) + Vector2(cos(ra), sin(ra)) * float(cr["r"]) * 1.08, _rf(rng, rk["size"]), Rng.range_int(rng, "w", 0, 2))

static func _try_rock(w, rng: Dictionary, p: Vector2, r: float, kind: int) -> void:
	var rot: float = _r(rng, 0.0, TAU)
	if not w.in_map(p, float(w.margin) + r + 2.0) or p.distance_to(w.center) < 105.0 + r:
		return
	for d in w.deposit_sites:
		if p.distance_to(Vector2(d["x"], d["y"])) < float(d["r"]) + r + 3.0:
			return
	if w.crevice_at(p, r + 1.0):
		return
	w.rocks.append({"x": p.x, "y": p.y, "r": r, "kind": kind, "rot": rot})

# ---------------------------------------------------------------- walking flags
## Crevice ground is steep (not walkable) on the height quads it crosses: the coarse walking
## map sees it; the fine map uses crevice_at() for the exact width.
static func _crevice_flags(w) -> void:
	var qn: int = w.hn - 1
	var hs: float = w.hstep
	for cv in w.crevices:
		var pts: Array = cv["pts"]
		var half: float = float(cv["w"]) * 0.5
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			var x0: int = maxi(0, int((minf(a.x, b.x) - half - hs) / hs))
			var x1: int = mini(qn - 1, int((maxf(a.x, b.x) + half + hs) / hs))
			var y0: int = maxi(0, int((minf(a.y, b.y) - half - hs) / hs))
			var y1: int = mini(qn - 1, int((maxf(a.y, b.y) + half + hs) / hs))
			for qy in range(y0, y1 + 1):
				for qx in range(x0, x1 + 1):
					var c := Vector2((qx + 0.5) * hs, (qy + 0.5) * hs)
					if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < half + hs * 0.5:
						w.steep[qy * qn + qx] = 1

# ---------------------------------------------------------------- horizon (sun) map
## For every cell (horizon.cell metres) and every sun bearing of the day (bins over the half
## circle the sun crosses), the elevation of the horizon in degrees. sun_vis() compares the
## sun's elevation with it. Heights are read from a 16 m copy of the height grid.
static func _horizon(w, cfg: Dictionary) -> void:
	var hc: Dictionary = cfg["horizon"]
	var sun: Dictionary = cfg["sun"]
	var cell: float = float(hc.get("cell", 32.0))
	var bins: int = int(hc.get("bins", 13))
	var steps: Array = hc.get("steps", [12, 24, 40, 64, 96, 140, 200, 280, 400, 560])
	var n: int = int(ceil(float(w.size) / cell)) + 1
	w.hz_cell = cell
	w.hz_bins = bins
	w.hz_side = n
	# A coarse copy of the heights (every 4th sample at 4 m = 16 m).
	var cs: float = 16.0
	var cn: int = int(ceil(float(w.size) / cs)) + 1
	var ch := PackedFloat32Array()
	ch.resize(cn * cn)
	for j in cn:
		for i in cn:
			ch[j * cn + i] = w.height_at(i * cs, j * cs)
	var az_off: float = deg_to_rad(float(sun.get("az_offset_deg", -40.0)))
	var dirs: Array = []
	for b in bins:
		var h_ang: float = PI * float(b) / float(bins - 1)
		dirs.append(Vector2(-cos(h_ang), sin(h_ang)).rotated(az_off))
	var out := PackedFloat32Array()
	out.resize(n * n * bins)
	var inv_cs: float = 1.0 / cs
	var lim: float = float(cn - 1)
	for j in n:
		for i in n:
			var px: float = i * cell
			var py: float = j * cell
			var gx0: int = clampi(int(px * inv_cs + 0.5), 0, cn - 1)
			var gy0: int = clampi(int(py * inv_cs + 0.5), 0, cn - 1)
			var h0: float = ch[gy0 * cn + gx0] + 1.5
			var base: int = (j * n + i) * bins
			for b in bins:
				var d: Vector2 = dirs[b]
				var best := -90.0
				for s in steps:
					var sd: float = float(s)
					var fx: float = (px + d.x * sd) * inv_cs
					var fy: float = (py + d.y * sd) * inv_cs
					if fx < 0.0 or fy < 0.0 or fx > lim or fy > lim:
						break
					var hh: float = ch[int(fy + 0.5) * cn + int(fx + 0.5)]
					var e: float = rad_to_deg(atan((hh - h0) / sd))
					if e > best:
						best = e
				out[base + b] = best
	w.horizon = out

# ---------------------------------------------------------------- radiation
static func _radiation(w, cfg: Dictionary, planet: Dictionary) -> void:
	var rc: Dictionary = cfg["radiation"]
	var cell: float = float(rc.get("cell", 16.0))
	var n: int = int(ceil(float(w.size) / cell)) + 1
	w.rad_cell = cell
	w.rad_side = n
	var mult: float = float(planet.get("radiation_mult", 1.0))
	var plain: float = float(rc.get("plain", 0.04))
	var per100: float = float(rc.get("per_100m", 0.12))
	var rim: float = float(rc.get("rim", 0.25))
	var peak_add: float = float(rc.get("peak", 0.35))
	var h_start: float = w.height_at(w.center.x, w.center.y)
	var hot: Array = []
	var s1: int = Rng.stream_seed(w._seed, 1777)
	var k := 0
	for d in w.deposit_sites:
		if d["kind"] == "uranium" or d["kind"] == "thorium":
			var pk: float = lerpf(float(rc["deposit_peak"][0]), float(rc["deposit_peak"][1]), Rng.hash2(k, 1, s1))
			var rr: float = lerpf(float(rc["deposit_radius"][0]), float(rc["deposit_radius"][1]), Rng.hash2(k, 2, s1))
			hot.append([Vector2(d["x"], d["y"]), pk, rr])
			k += 1
	var f := PackedFloat32Array()
	f.resize(n * n)
	for j in n:
		for i in n:
			var p := Vector2(i * cell, j * cell)
			var v: float = plain
			var h: float = w.height_at(p.x, p.y)
			v += per100 * maxf(0.0, (h - h_start) / 100.0)
			for cr in w.deep_craters:
				var dr: float = (p.distance_to(Vector2(cr["x"], cr["y"])) - float(cr["r"])) / (float(cr["r"]) * 0.18)
				v += rim * exp(-dr * dr)
			for mt in w.mountains:
				var dp: float = p.distance_to(mt["peak"]) / 90.0
				v += peak_add * exp(-dp * dp)
			for hs in hot:
				var dh: float = p.distance_to(hs[0]) / float(hs[2])
				v += float(hs[1]) * exp(-dh * dh)
			f[j * n + i] = v * mult
	w.rad = f

## Hazard zones as in version 3: the biggest deep crater is the meteor-prone basin, a fault
## line crosses the map away from the start, high ground and plateaus are windy.
static func _hazard_zones(w) -> void:
	var big := {}
	for cr in w.deep_craters:
		if big.is_empty() or float(cr["r"]) > float(big["r"]):
			big = cr
	if big.is_empty():
		big = {"x": w.center.x + 700.0, "y": w.center.y, "r": 150.0}
	w.basin = {"x": big["x"], "y": big["y"], "r": float(big["r"]) * 1.2}
	var fa: float = Rng.hash2(3, 5, w._seed) * TAU
	var fdir := Vector2(cos(fa), sin(fa))
	var fmid: Vector2 = w.center + fdir.orthogonal() * 520.0
	var f0: Vector2 = fmid - fdir * float(w.size)
	var f1: Vector2 = fmid + fdir * float(w.size)
	w.fault = {"x0": f0.x, "y0": f0.y, "x1": f1.x, "y1": f1.y}
	w._hazard_fields_v3()
