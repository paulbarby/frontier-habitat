extends RefCounted
## Guard for every polygon the interface draws. A polygon with fewer than 3 points, a near-zero
## area (all points on one line, or a control of 0 width or height) or a NaN makes the engine
## print "Invalid polygon data, triangulation failed." and draw nothing. ok() returns false for
## such a polygon, so the caller skips it, and counts it by caller tag in `bad` (tests print it).

static var bad := {}     # tag -> times skipped

static func ok(pts: PackedVector2Array, tag: String) -> bool:
	var n: int = pts.size()
	var good: bool = n >= 3
	if good:
		var a := 0.0
		for i in n:
			var p: Vector2 = pts[i]
			if is_nan(p.x) or is_nan(p.y) or is_inf(p.x) or is_inf(p.y):
				good = false
				break
			var q: Vector2 = pts[(i + 1) % n]
			a += p.x * q.y - q.x * p.y
		if good and absf(a) * 0.5 < 0.01:
			good = false
	if not good:
		bad[tag] = int(bad.get(tag, 0)) + 1
	return good
