extends RefCounted
## Plays the documented reference layout as ordinary player commands. It stands in for a
## player in headless tests and in the in-game demo. It has no access to anything a player
## does not have: it only calls submit() and the same placement checks the interface uses.
##
## Terrain, rocks and deposits differ from seed to seed, so a coordinate in the layout file
## is a wish, not a guarantee. A place step that does not fit is slid to the nearest legal
## ring. A step may also name the structures it must be joined to ("joins"); the driver
## then keeps sliding until the corridor or cable is legal too, so the layout never leaves
## a room without a way in.
##
## Step fields (content/reference_layout.json):
##   t           earliest second of the game for the step
##   group       "" = the opening; other groups are played by the group "all"
##   need        conditions that must all hold first: "tech:<id>", "active:<alias>",
##               "chapter:<n>" (1-based chapter open), "pop:<n>", "stage:<n>", "day:<n>",
##               "ship:<stage>", "level:<alias>:<n>", "stock:<item>:<n>", "goal:<id>"
##   place/as/x/y/rot/size/joins/on/mid   a structure ("near": "ship" = x metres short of
##               the Meridian's hull on the line from the lander, y metres to the side;
##               "near": "ship_line" = x metres from the lander toward the Meridian)
##   link/a/b    a corridor or cable
##   admit/roles settlers
##   upgrade     alias of a structure to upgrade one level (waits until it is allowed)
##   cmd/payload any other command; "@alias" in the payload becomes the structure's id

const Ship = preload("res://sim/ship.gd")

var sim
var steps: Array = []
var alias := {}       # alias -> building id
var done := {}        # step index -> true
var ring := {}        # step index -> how many candidate places were tried
var group := ""
var failures: Array = []

const RINGS := [0.0, 3.0, 5.0, 7.0, 9.0, 12.0, 15.0, 19.0, 24.0]

func _init(s, only_group: String = "") -> void:
	sim = s
	group = only_group
	var f := FileAccess.open("res://content/reference_layout.json", FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	steps = data["steps"]

func finished() -> bool:
	return done.size() >= _wanted().size()

## Steps of the selected group. Group "" is the opening layout; "all" plays everything.
func _wanted() -> Array:
	var out: Array = []
	for i in steps.size():
		if group == "all" or String(steps[i].get("group", "")) == group:
			out.append(i)
	return out

## Places and corridors submitted during this drive() call: the commands apply on the next
## tick, so later steps of the same call must keep clear of them. [pos, radius] or [p0, p1].
var _pending_places: Array = []
var _pending_links: Array = []
var _pending_ends := {}     # building ids that got a corridor ordered this call
## The driver may also put an airlock next to a plan that stays out of suit range (off:
## the documented layout places its airlocks itself).
var rescue_far := false

## Call once per simulated second.
func drive() -> void:
	_pending_places = []
	_pending_links = []
	_pending_ends = {}
	_resolve()
	_rescue_isolated_rooms()
	if group != "" and rescue_far:
		_rescue_far_sites()
	var now: float = sim.seconds()
	for i in _wanted():
		if done.has(i):
			continue
		var st: Dictionary = steps[i]
		if now < float(st["t"]):
			continue
		if not _needs_met(st):
			continue
		if st.has("place"):
			_do_place(i, st)
		elif st.has("link"):
			if String(st["a"]) == "*nearest":
				_pick_nearest(i, st)
				continue
			if alias.has(st["a"]) and alias.has(st["b"]):
				var chk: Dictionary = sim.place.check_link(st["link"], alias[st["a"]], alias[st["b"]])
				if chk["code"] == "ok" and not _link_hits_pending(st["link"], chk):
					sim.submit("place_link", {"def": st["link"], "a": alias[st["a"]], "b": alias[st["b"]]})
					if st["link"] == "corridor":
						_pending_links.append([chk["p0"], chk["p1"]])
						_pending_ends[int(alias[st["a"]])] = true
						_pending_ends[int(alias[st["b"]])] = true
					done[i] = true
				elif chk["code"] == "ok":
					pass    # a structure ordered this second may be in the way: try next second
				elif chk["code"] == "duplicate":
					done[i] = true
				else:
					_nudge_for_link(i, st, chk["code"])
		elif st.has("admit"):
			sim.submit("admit_settlers", {"count": int(st["admit"]), "roles": st.get("roles", [])})
			done[i] = true
		elif st.has("upgrade"):
			_do_upgrade(i, st)
		elif st.has("cmd"):
			var p = _subst(st.get("payload", {}))
			if p != null:
				sim.submit(String(st["cmd"]), p)
				done[i] = true

## "a": "*nearest" joins b to the nearest finished room that takes a corridor toward it
## (the corridor may still be too long: then the usual junction split follows).
func _pick_nearest(i: int, st: Dictionary) -> void:
	if not alias.has(st["b"]):
		return
	var blds: Dictionary = sim.state["buildings"]
	var target: Dictionary = blds.get(alias[st["b"]], {})
	if target.is_empty():
		return
	var best := -1
	var best_d := 1e18
	for id in blds:
		var o: Dictionary = blds[id]
		if o["kind"] != "room" or o["state"] != "active" or id == target["id"]:
			continue
		var code: String = String(sim.place.check_link(st["link"], id, target["id"])["code"])
		if code != "ok" and code != "too_far":
			continue
		var d: float = (o["pos"] as Vector2).distance_to(target["pos"])
		if d < best_d:
			best_d = d
			best = id
	if best == -1:
		return
	var key := "N%d" % i
	alias[key] = best
	st["a"] = key

## All "need" conditions of a step hold now.
func _needs_met(st: Dictionary) -> bool:
	for n in st.get("need", []):
		var w: PackedStringArray = String(n).split(":")
		match w[0]:
			"tech":
				if not sim.research.is_done(w[1]):
					return false
			"active":
				if not alias.has(w[1]) or String(sim.state["buildings"].get(alias[w[1]], {}).get("state", "")) != "active":
					return false
			"chapter":
				if sim.goals.chapter() + 1 < int(w[1]):
					return false
			"pop":
				if sim.alive_count() < int(w[1]):
					return false
			"stage":
				if int(sim.state["progress"]["stage"]) < int(w[1]):
					return false
			"day":
				if sim.util.days_elapsed() + 1.0 < float(w[1]):
					return false
			"ship":
				if int(sim.state["ship"]["stage"]) < int(w[1]):
					return false
			"level":
				if not alias.has(w[1]) or int(sim.state["buildings"].get(alias[w[1]], {}).get("level", 0)) < int(w[2]):
					return false
			"stock":
				if int(sim.inv.totals().get(w[1], {}).get("total", 0)) < int(w[2]):
					return false
			"goal":
				if not sim.goals.is_done(w[1]):
					return false
			"beds":
				var f: Dictionary = sim.metrics.forecast()
				if int(f["beds"]) - int(f["pop"]) < int(w[1]):
					return false
	return true

## "@alias" in a payload becomes the structure's id. Returns null while an alias is unknown.
func _subst(v):
	match typeof(v):
		TYPE_STRING:
			if String(v).begins_with("@"):
				var key: String = String(v).substr(1)
				return int(alias[key]) if alias.has(key) else null
			return v
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				var x = _subst(v[k])
				if x == null:
					return null
				out[k] = x
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for x in v:
				var y = _subst(x)
				if y == null:
					return null
				arr.append(y)
			return arr
	return v

func _do_upgrade(i: int, st: Dictionary) -> void:
	var key: String = String(st["upgrade"])
	if not alias.has(key):
		return
	var b: Dictionary = sim.state["buildings"].get(alias[key], {})
	if b.is_empty():
		failures.append("upgrade %s: the structure is gone" % key)
		done[i] = true
		return
	var want: int = int(st.get("to", int(b.get("level", 1)) + 1))
	if int(b.get("level", 1)) >= want:
		done[i] = true
		return
	var chk: Dictionary = sim.upgrades.check(b)
	match String(chk["code"]):
		"ok":
			if int(chk["to"]) == want:
				sim.submit("upgrade", {"id": int(b["id"])})
				done[i] = true
		"max_level", "not_upgradable":
			failures.append("upgrade %s refused: %s" % [key, chk["code"]])
			done[i] = true

## A plan out of suit range waits for an airlock nearer to it (the alert says so). Do what
## a player does: put an airlock between the nearest room and the plan, its door toward
## the plan, and join it to that room. One airlock per plan, checked every 20 seconds.
var _rescued := {}

func _rescue_far_sites() -> void:
	if int(sim.state["tick"]) % 200 != 0:
		return
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "link" or b["state"] != "blueprint" or String(b["block"]) != "suit_range" or _rescued.has(id):
			continue
		_rescued[id] = true
		var best := -1
		var best_d := 1e18
		for rid in blds:
			var r: Dictionary = blds[rid]
			if r["kind"] != "room" or r["state"] != "active":
				continue
			var d: float = (r["pos"] as Vector2).distance_to(b["pos"])
			if d < best_d:
				best_d = d
				best = rid
		if best == -1:
			continue
		var room: Dictionary = blds[best]
		var dir: Vector2 = ((b["pos"] as Vector2) - room["pos"]).normalized()
		var rot: float = sim.place.snap_rot(dir.angle())
		var spot = null
		for dist in [8.0, 11.0, 6.0, 14.0]:
			for side in [0.0, 3.0, -3.0, 6.0, -6.0]:
				var p: Vector2 = (room["pos"] as Vector2) + dir * (float(room["radius"]) + float(sim.bdef("airlock")["radius"]) + dist) + dir.orthogonal() * side
				if sim.place.check_building("airlock", sim.place.snap_pos(p), sim.place.snap_rot(rot)) == "ok":
					spot = p
					break
			if spot != null:
				break
		if spot == null:
			failures.append("no place for an airlock toward %s" % b["name"])
			continue
		var c: Vector2 = sim.world.center
		var g: String = group if group != "all" else "rescue"
		var ra := "RA%d" % int(id)
		var rr := "RR%d" % int(id)
		alias[rr] = best
		steps.append({"t": 0, "group": g, "place": "airlock", "as": ra, "x": (spot as Vector2).x - c.x, "y": (spot as Vector2).y - c.y, "rot": rot})
		steps.append({"t": 0, "group": g, "link": "corridor", "a": rr, "b": ra})
		return

## A room with no corridor has no air and no walking route, so nobody can work in it.
## Whatever the layout intended, join it to the nearest room that accepts a corridor.
## This is the same repair a player makes when a planned junction does not fit.
func _rescue_isolated_rooms() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "room" or int(sim.state["tick"]) - int(b["created"]) < 200:
			continue
		if not sim.topo.links_of.get(id, []).is_empty() or _pending_ends.has(id):
			continue
		var best := -1
		var best_d := 1e18
		for other in blds:
			if other == id or blds[other]["kind"] == "link":
				continue
			if sim.place.check_link("corridor", id, other)["code"] != "ok":
				continue
			var d: float = (blds[other]["pos"] as Vector2).distance_to(b["pos"])
			if d < best_d:
				best_d = d
				best = other
		if best != -1:
			var chk: Dictionary = sim.place.check_link("corridor", best, id)
			if _link_hits_pending("corridor", chk):
				continue
			sim.submit("place_link", {"def": "corridor", "a": best, "b": id})
			_pending_links.append([chk["p0"], chk["p1"]])
			_pending_ends[id] = true
			_pending_ends[best] = true

## The structure an "around" step stands next to ({} while it is not known yet).
func _around_anchor(st: Dictionary) -> Dictionary:
	return sim.state["buildings"].get(alias.get(String(st["around"]), -1), {})

func _do_place(i: int, st: Dictionary) -> void:
	if st.has("around") and _around_anchor(st).is_empty():
		return      # the structure to stand next to is not there yet: wait for it
	var rot: float = _rot_of(st)
	var p = _candidate(st, int(ring.get(i, 0)))
	if p == null:
		# Nothing in any ring fits. Say so once instead of trying again every second.
		failures.append("no legal place for %s (%s)" % [st["place"], st.get("as", "")])
		done[i] = true
		return
	var size: int = int(st.get("size", 1))
	rot = _door_rot(st, p, rot, size)
	sim.submit("place_building", {"def": st["place"], "x": p.x, "y": p.y, "rot": rot, "size": size})
	_pending_places.append([sim.place.snap_pos(p), float(sim.sizes.def_for(st["place"], size)["radius"])])
	done[i] = true

## V3.1 door clearance: a room turns (15-degree steps, the smallest turn first) until the
## corridor to the room it joins leaves through a free side (placement.link_angle_ok_for),
## as a player turns the ghost. An airlock keeps a turn only where it is still legal.
func _door_rot(st: Dictionary, p: Vector2, rot: float, size: int) -> float:
	if not st.has("joins") or not alias.has(st["joins"]):
		return rot
	var partner: Dictionary = sim.state["buildings"].get(alias[st["joins"]], {})
	if partner.is_empty():
		return rot
	var def_id: String = st["place"]
	var toward: float = ((partner["pos"] as Vector2) - sim.place.snap_pos(p)).angle()
	for k in range(0, 13):
		for sgn in ([1] if k == 0 or k == 12 else [1, -1]):
			var r2: float = sim.place.snap_rot(rot + deg_to_rad(15.0 * k * sgn))
			if not sim.place.link_angle_ok_for(def_id, size, r2, toward):
				continue
			if r2 != rot and not _legal(def_id, p, r2, size):
				continue
			return r2
	return rot

## The rotation of a step, on the 15-degree grid. "face": "ship" turns a door toward the
## Meridian.
func _rot_of(st: Dictionary) -> float:
	if String(st.get("face", "")) == "ship":
		var ship: Dictionary = sim.ship.record()
		var p = _place_point(st)
		if not ship.is_empty() and p != null:
			return sim.place.snap_rot(((ship["pos"] as Vector2) - (p as Vector2)).angle())
	return sim.place.snap_rot(float(st.get("rot", 0.0)))

## A legal place that keeps clear of what this drive() call already ordered.
func _legal(def_id: String, p: Vector2, rot: float, size: int) -> bool:
	var q: Vector2 = sim.place.snap_pos(p)
	if sim.place.check_building(def_id, q, rot, -1, size) != "ok":
		return false
	return not _hits_pending(q, float(sim.sizes.def_for(def_id, size)["radius"]))

## True when a place overlaps something ordered earlier in this drive() call.
func _hits_pending(pos: Vector2, r: float) -> bool:
	for pp in _pending_places:
		if (pp[0] as Vector2).distance_to(pos) < r + float(pp[1]) + 0.6:
			return true
	for pl in _pending_links:
		if Geometry2D.get_closest_point_to_segment(pos, pl[0], pl[1]).distance_to(pos) < r + 1.5:
			return true
	return false

func _link_hits_pending(def_id: String, chk: Dictionary) -> bool:
	for pp in _pending_places:
		if Geometry2D.get_closest_point_to_segment(pp[0], chk["p0"], chk["p1"]).distance_to(pp[0]) < float(pp[1]) + 1.5:
			return true
	if def_id == "corridor":
		for pl in _pending_links:
			if sim.place._segment_distance(chk["p0"], chk["p1"], pl[0], pl[1]) < 2.6:
				return true
	return false

## The wanted point for candidate number n: n = 0 is the point in the layout file, the
## rest are rings around it. Returns null when nothing in that ring is legal.
func _candidate(st: Dictionary, n: int):
	var rot: float = _rot_of(st)
	var size: int = int(st.get("size", 1))
	# A mine must stand on a mineral deposit. Deposits differ per seed, so try each one,
	# nearest first, and search inside it.
	if st.get("on", "") == "deposit":
		# The nearest legal spot to the structure it must be joined to: a mine that no
		# corridor can reach has no air, and nobody can work in it.
		var aim: Vector2 = sim.world.center
		if st.has("joins") and alias.has(st["joins"]):
			aim = sim.state["buildings"][alias[st["joins"]]]["pos"]
		var best = null
		var best_d := 1e18
		for d in sim.state["deposits"]:
			var mid := Vector2(d["x"], d["y"])
			# The mine's centre must be on the deposit (placement rule), anywhere inside it.
			var span: float = float(d["r"])
			for r in [0.0, span * 0.3, span * 0.6, span * 0.9]:
				var tries: int = 1 if r < 0.2 else 16
				for j in tries:
					var p: Vector2 = mid + Vector2(r, 0).rotated(j * TAU / float(tries))
					if not _legal(st["place"], p, rot, size):
						continue
					var dist: float = p.distance_to(aim)
					if dist < best_d:
						best_d = dist
						best = p
		return best
	# A junction between two structures: scan along the line and a little to each side, so
	# a rock or a slope at the exact midpoint does not leave the pair unjoined.
	if st.has("mid"):
		var a_id: int = int(alias.get(st["mid"][0], -1))
		var b_id: int = int(alias.get(st["mid"][1], -1))
		if a_id == -1 or b_id == -1:
			return null
		var pa: Vector2 = sim.state["buildings"][a_id]["pos"]
		var pb: Vector2 = sim.state["buildings"][b_id]["pos"]
		var side: Vector2 = (pb - pa).normalized().orthogonal()
		# Points where neither corridor leg meets a rock, a structure or a corridor come
		# first (a player looks at the ground before placing the junction), then any legal
		# point. Try n (after n refusals) takes the next one in that order.
		var good: Array = []
		var fair: Array = []
		for f in [0.5, 0.45, 0.55, 0.4, 0.6, 0.35, 0.65, 0.3, 0.7]:
			for off in [0.0, 4.0, -4.0, 8.0, -8.0, 13.0, -13.0, 18.0, -18.0]:
				var p: Vector2 = pa.lerp(pb, f) + side * off
				if not _legal(st["place"], p, rot, size):
					continue
				if _legs_clear(pa, p, pb, a_id, b_id):
					good.append(p)
				elif absf(off) <= 13.0:
					fair.append(p)
		var all_p: Array = good + fair
		return all_p[n] if n < all_p.size() else null
	# "around": a structure next to another one (a refinery next to the mine), on rings
	# around it, the place nearest to the lander first.
	if st.has("around"):
		var anchor: Dictionary = _around_anchor(st)
		if anchor.is_empty():
			return null
		var rad: float = float(sim.sizes.def_for(st["place"], size)["radius"])
		var aim: Vector2 = sim.world.center
		for gap in [3.0, 5.0, 8.0, 11.0, 15.0, 20.0]:
			var best = null
			var best_d := 1e18
			for j in 24:
				var p: Vector2 = (anchor["pos"] as Vector2) + Vector2(float(anchor["radius"]) + rad + gap, 0).rotated(j * TAU / 24.0)
				if not _legal(st["place"], p, rot, size):
					continue
				var d: float = p.distance_to(aim)
				if d < best_d:
					best_d = d
					best = p
			if best != null:
				return best
		return null
	var want = _place_point(st)
	if want == null:
		return null
	# A room that must be joined to another one is slid toward its partner, never away:
	# a corridor is limited in length, and a room with no corridor cannot be reached.
	var toward = null
	if st.has("joins") and alias.has(st["joins"]):
		toward = sim.state["buildings"][alias[st["joins"]]]["pos"]
	for k in range(n, RINGS.size()):
		var r: float = RINGS[k]
		var tries: int = 1 if r == 0.0 else 16
		var best = null
		var best_d := 1e18
		for j in tries:
			var p: Vector2 = want + Vector2(r, 0).rotated(j * TAU / float(tries))
			if not _legal(st["place"], p, rot, size):
				continue
			var d: float = 0.0 if toward == null else (p as Vector2).distance_to(toward)
			if d < best_d:
				best_d = d
				best = p
		if best != null:
			return best
	return null

## Both straight legs a-p and p-b keep clear of every rock (the margin check_link uses,
## plus room for the rooms' radii not being known here).
func _legs_clear(pa: Vector2, p: Vector2, pb: Vector2, a_id: int = -1, b_id: int = -1) -> bool:
	for rock in sim.world.rocks:
		var rp := Vector2(rock["x"], rock["y"])
		var lim: float = float(rock["r"]) + 1.9
		if Geometry2D.get_closest_point_to_segment(rp, pa, p).distance_to(rp) < lim:
			return false
		if Geometry2D.get_closest_point_to_segment(rp, p, pb).distance_to(rp) < lim:
			return false
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		if id == a_id or id == b_id:
			continue
		var o: Dictionary = blds[id]
		if o["kind"] == "link":
			if o["def"] == "corridor":
				if Geometry2D.segment_intersects_segment(pa, p, o["p0"], o["p1"]) != null or Geometry2D.segment_intersects_segment(p, pb, o["p0"], o["p1"]) != null:
					return false
			continue
		if o["def"] == "meridian":
			continue
		var op: Vector2 = o["pos"]
		var lim2: float = float(o["radius"]) + 2.0
		if Geometry2D.get_closest_point_to_segment(op, pa, p).distance_to(op) < lim2:
			return false
		if Geometry2D.get_closest_point_to_segment(op, p, pb).distance_to(op) < lim2:
			return false
	return true

## A link was refused. Move the structure that can move and try again, so the layout never
## leaves a room with no corridor: an isolated room is unreachable and nobody can work in it.
func _nudge_for_link(link_step: int, st: Dictionary, code: String) -> void:
	# Too far apart for one corridor: put a junction between them and use two, exactly as a
	# player would. The new steps join the same group and are played on the next second.
	if code == "too_far" and st["link"] == "corridor" and int(st.get("split", 0)) < 2:
		var j := "J%d" % link_step
		var g: String = String(st.get("group", ""))
		steps.append({"t": st["t"], "group": g, "place": "junction", "as": j, "x": 0, "y": 0, "rot": 0, "mid": [st["a"], st["b"]]})
		var depth: int = int(st.get("split", 0)) + 1
		steps.append({"t": st["t"], "group": g, "link": "corridor", "a": st["a"], "b": j, "split": depth})
		steps.append({"t": st["t"], "group": g, "link": "corridor", "a": j, "b": st["b"], "split": depth})
		done[link_step] = true
		return
	# The wanted partner has no free port, or its door is in the way. Join the nearest other
	# room that does accept the link, which is what a player does.
	if code == "ports_full" or code == "blocked_entrance" or code == "door_blocked":
		var moving: int = int(alias[st["b"]])
		var blds: Dictionary = sim.state["buildings"]
		var best := -1
		var best_d := 1e18
		for id in blds:
			if id == moving or blds[id]["kind"] == "link":
				continue
			if sim.place.check_link(st["link"], moving, id)["code"] != "ok":
				continue
			var d: float = (blds[id]["pos"] as Vector2).distance_to(blds[moving]["pos"])
			if d < best_d:
				best_d = d
				best = id
		if best != -1:
			sim.submit("place_link", {"def": st["link"], "a": best, "b": moving})
			done[link_step] = true
			return
	for key in ["b", "a"]:
		var step_i: int = _step_of(st[key])
		if step_i == -1:
			continue
		var bid: int = int(alias[st[key]])
		var b: Dictionary = sim.state["buildings"].get(bid, {})
		if b.is_empty() or b["state"] != "blueprint":
			continue
		if _pending_ends.has(bid):
			return      # a corridor to it was ordered this second: move it next second
		ring[step_i] = int(ring.get(step_i, 0)) + 1
		if int(ring[step_i]) >= RINGS.size():
			continue
		sim.submit("cancel", {"id": bid})
		alias.erase(st[key])
		done.erase(step_i)
		return
	failures.append("link %s %s-%s refused: %s" % [st["link"], st["a"], st["b"], code])
	done[link_step] = true

func _step_of(alias_name: String) -> int:
	for i in steps.size():
		if steps[i].get("as", "") == alias_name:
			return i
	return -1

## Where a step goes when it is not a plain offset from the lander.
##   "on": "deposit"  -> the nearest mineral deposit to the lander
##   "mid": [a, b]    -> halfway between two already-placed structures
##   "near": "ship"   -> x metres short of the Meridian's hull on the line from the lander,
##                       y metres to the side
##   "near": "ship_line" -> x metres from the lander toward the Meridian, y to the side
func _place_point(st: Dictionary):
	var c: Vector2 = sim.world.center
	if st.get("on", "") == "deposit":
		var best = null
		var best_d := 1e18
		for d in sim.state["deposits"]:
			var p := Vector2(d["x"], d["y"])
			if p.distance_to(c) < best_d:
				best_d = p.distance_to(c)
				best = p
		return best
	if st.has("mid"):
		var a: int = int(alias.get(st["mid"][0], -1))
		var b: int = int(alias.get(st["mid"][1], -1))
		if a == -1 or b == -1:
			return null
		return ((sim.state["buildings"][a]["pos"] as Vector2) + sim.state["buildings"][b]["pos"]) * 0.5
	if st.has("around"):
		var anc: Dictionary = _around_anchor(st)
		if anc.is_empty():
			return null
		return anc["pos"]
	if String(st.get("near", "")) == "ship_line":
		var shp: Dictionary = sim.ship.record()
		if shp.is_empty():
			return null
		var dir: Vector2 = ((shp["pos"] as Vector2) - c).normalized()
		return c + dir * float(st["x"]) + dir.orthogonal() * float(st["y"])
	if String(st.get("near", "")) == "ship":
		var ship: Dictionary = sim.ship.record()
		if ship.is_empty():
			return null
		var u: Vector2 = ((ship["pos"] as Vector2) - c).normalized()
		# Distance from the lander to the hull along u.
		var along: float = (ship["pos"] as Vector2).distance_to(c)
		var t := 0.0
		while t < along:
			if Ship.surface_distance(ship, c + u * t) <= 0.0:
				break
			t += 0.5
		return c + u * (t - float(st["x"])) + u.orthogonal() * float(st["y"])
	return c + Vector2(float(st["x"]), float(st["y"]))

func _resolve() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var taken: Array = alias.values()
	# Structures by type, made once per call (the same ids in the same order as a scan).
	var by_def := {}
	for id in blds:
		var d: String = blds[id]["def"]
		if not by_def.has(d):
			by_def[d] = []
		by_def[d].append(id)
	for i in steps.size():
		var st: Dictionary = steps[i]
		if not st.has("place") or alias.has(st["as"]):
			continue
		if group != "all" and String(st.get("group", "")) != group:
			continue
		var p = _place_point(st)
		if p == null:
			continue
		# The driver may have slid the structure, so match the nearest one of that type
		# that no other alias owns yet.
		var best := -1
		var best_d := 40.0
		if String(st.get("on", "")) == "deposit":
			# A mine goes to whichever deposit fits, which can be far from the layout
			# point: any mine that no alias owns is this one.
			best_d = 1e9
		for id in by_def.get(String(st["place"]), []):
			var b: Dictionary = blds[id]
			if taken.has(id):
				continue
			if sim.bdef(b["def"]).has("sizes") and int(b.get("size", 1)) != int(st.get("size", 1)):
				continue
			var d: float = (b["pos"] as Vector2).distance_to(p)
			if d < best_d:
				best_d = d
				best = id
		if best != -1:
			alias[st["as"]] = best
			taken.append(best)
