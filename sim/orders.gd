extends RefCounted
## Player orders to colonists (docs/V4_DESIGN.md section 5, "Orders"). An order overrides the
## colonist's own choice of work until it is done or cleared. Critical needs (thirst, hunger,
## exhaustion) still interrupt it; the order continues after them.
##
## agent.order (absent when there is none) = {kind, p (Vector2), b (room id or -1), v, site,
##   stay (bool), confirm (bool), t (tick given)}
##   kind: "go" | "stay" | "return" | "board" | "work_at" | "survey"
## agent.jobs (absent when there is none) = {category: 0..3}: this colonist's own job
##   priorities; 0 = not allowed. A category not in it uses the colony priority.
##
## The AI refuses an order that would kill the colonist (suit air, radiation) with a code and
## a reason; with confirm: true the order runs anyway and the colonist does not turn back for
## air while it runs.

var sim

func _init(s) -> void:
	sim = s

const KINDS := ["go", "stay", "return", "board", "work_at", "survey"]
const TEXT := {
	"ok": "",
	"unknown": "That colonist does not exist.",
	"not_colonist": "Only colonists take orders.",
	"dead": "That colonist is dead.",
	"invalid": "That order is not known.",
	"in_vehicle": "The colonist is in a vehicle. Get out first.",
	"in_airlock": "The colonist is in an airlock. Try again in a moment.",
	"no_path": "There is no way to that place.",
	"suit_range": "The suit air is not enough to go there and come back.",
	"exposed_stay": "The colonist cannot stay outside: the suit air ends.",
	"radiation": "The radiation there is too high.",
	"no_vehicle": "That vehicle does not exist.",
	"no_seat": "The vehicle has no free seat.",
	"no_building": "That structure does not exist or is not complete.",
	"no_site": "That site does not exist or is already surveyed.",
	"no_base": "The colonist has no base with air.",
}

func text_of(code: String) -> String:
	return String(TEXT.get(code, code))

func rad_limit() -> float:
	return float(sim.bal.get("order_rad_refuse", 1.0))

# ---------------------------------------------------------------- targets
## The room that contains p (a completed room with an air group), else -1.
func room_at(p: Vector2) -> int:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if (b["kind"] == "room" or b["kind"] == "special") and b["state"] == "active" and sim.topo.atmo_comp.has(id):
			if (b["pos"] as Vector2).distance_to(p) < float(b["radius"]) - 0.5:
				return int(id)
	return -1

## Where a "go" or "stay" order leads: {b, p}. In a room: a standing place in it.
func _target(a: Dictionary, p: Vector2) -> Dictionary:
	var rid: int = room_at(p)
	if rid != -1:
		return {"b": rid, "p": sim.nav.slot_pos(sim.state["buildings"][rid], int(a["id"]))}
	var q = sim.nav.nearest_walkable(p, 6)
	return {"b": -1, "p": q if q != null else p}

## The place a "return" order leads to: the core of the colonist's home base when it has
## air, else the nearest room with air of that base, else the nearest room with air.
func _home_target(a: Dictionary) -> Dictionary:
	var home: int = sim.bases.home_of(a)
	var core: Dictionary = sim.bases.core_of(home)
	if not core.is_empty() and sim.util.building_supplied(int(core["id"])):
		return {"b": int(core["id"]), "p": sim.nav.slot_pos(core, int(a["id"]))}
	var best := -1
	var best_d := 1e18
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "room" or b["state"] != "active" or not sim.util.building_supplied(int(id)):
			continue
		if home != -1 and sim.bases.base_of(int(id)) != home:
			continue
		var d: float = (b["pos"] as Vector2).distance_to(a["pos"])
		if d < best_d:
			best_d = d
			best = int(id)
	if best == -1:
		return {}
	return {"b": best, "p": sim.nav.slot_pos(blds[best], int(a["id"]))}

# ---------------------------------------------------------------- checks
## Would this order be accepted for this colonist? {ok, code, text, confirmable}.
## confirmable: the player may give it anyway with confirm: true.
func check(a: Dictionary, p: Dictionary) -> Dictionary:
	var code: String = _check(a, p)
	var conf: bool = code == "suit_range" or code == "exposed_stay" or code == "radiation"
	if conf and bool(p.get("confirm", false)):
		code = "ok"
	var txt: String = text_of(code)
	if code == "radiation":
		txt = "The radiation there is too high (%.1f mSv/h)." % _rad(p)
	return {"ok": code == "ok", "code": code, "text": txt, "confirmable": conf}

func _rad(p: Dictionary) -> float:
	return sim.reactors.rad_at(Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))

## True when a route never goes outside (no open-ground leg, no airlock).
static func indoors_only(legs: Array) -> bool:
	for leg in legs:
		if leg["m"] == "out" or leg["m"] == "lock":
			return false
	return true

func _check(a: Dictionary, p: Dictionary) -> String:
	if a.is_empty():
		return "unknown"
	if a["state"] != "alive":
		return "dead"
	if a["kind"] == "visitor":
		return "not_colonist"
	var kind: String = String(p.get("kind", ""))
	if not KINDS.has(kind):
		return "invalid"
	if a["where"] == "lock":
		return "in_airlock"
	if a["where"] == "vehicle" and kind != "work_at":
		return "in_vehicle"
	match kind:
		"go", "stay":
			var to: Dictionary = _target(a, Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
			var r: Dictionary = sim.nav.plan(sim.agents.loc_of(a), to)
			if not r["ok"]:
				return "no_path"
			# A walk that never leaves the pressurised rooms needs no suit air (coordinator rule).
			if int(to["b"]) != -1 and indoors_only(r["legs"]):
				return "ok"
			if int(to["b"]) == -1:
				if _rad(p) > rad_limit():
					return "radiation"
				if kind == "stay":
					return "exposed_stay"
				if not sim.agents._air_ok(a, r["legs"], 0.0, -1, to["p"]):
					return "suit_range"
			elif not sim.util.building_supplied(int(to["b"])) and not sim.agents._air_ok(a, r["legs"], 0.0, int(to["b"]), to["p"]):
				return "suit_range"
		"return":
			var h: Dictionary = _home_target(a)
			if h.is_empty():
				return "no_base"
			if not bool(sim.nav.plan(sim.agents.loc_of(a), h)["ok"]):
				return "no_path"
		"board":
			var v: Dictionary = sim.vehicles.get_v(int(p.get("v", -1)))
			if v.is_empty():
				return "no_vehicle"
			if (v["crew"] as Array).size() >= sim.vehicles.seats(v):
				return "no_seat"
			var bp: Vector2 = sim.vehicles.board_point(v)
			var r2: Dictionary = sim.nav.plan(sim.agents.loc_of(a), {"b": -1, "p": bp})
			if not r2["ok"]:
				return "no_path"
			if not sim.vehicles.near_air(v) and not sim.vehicles.pressurised(v):
				if not sim.agents._air_ok(a, r2["legs"], 0.0, -1, bp):
					return "suit_range"
		"work_at":
			var b: Dictionary = sim.state["buildings"].get(int(p.get("b", -1)), {})
			if b.is_empty() or b["kind"] == "link":
				return "no_building"
		"survey":
			if p.has("poi"):
				# V4 milestone 7: visit a point of interest (on foot).
				var poi: Dictionary = sim.explore.poi(int(p["poi"]))
				if poi.is_empty() or bool(poi["visited"]) or not bool(poi["found"]):
					return "no_site"
				var pp := Vector2(poi["x"], poi["y"])
				var q = sim.nav.nearest_walkable(pp, 10)
				if q == null:
					return "no_path"
				var r4: Dictionary = sim.nav.plan(sim.agents.loc_of(a), {"b": -1, "p": q})
				if not r4["ok"]:
					return "no_path"
				if _rad({"x": pp.x, "y": pp.y}) > rad_limit():
					return "radiation"
				if not sim.agents._air_ok(a, r4["legs"], 0.0, -1, q):
					return "suit_range"
				return "ok"
			var site: Dictionary = sim.hazards.hs()["sites"].get(int(p.get("site", -1)), {})
			if site.is_empty() or bool(site.get("surveyed", false)):
				return "no_site"
			var r3: Dictionary = sim.nav.plan(sim.agents.loc_of(a), {"b": -1, "p": site["pos"]})
			if not r3["ok"]:
				return "no_path"
			if _rad({"x": (site["pos"] as Vector2).x, "y": (site["pos"] as Vector2).y}) > rad_limit():
				return "radiation"
			if not sim.agents._air_ok(a, r3["legs"], float(sim.bal["exterior_work_chunk_seconds"]), -1, site["pos"]):
				return "suit_range"
	return "ok"

# ---------------------------------------------------------------- commands
## "order" {agents: [ids], kind, x?, y?, v?, b?, site?, poi?, stay?, confirm?}
## (survey takes a hazard site id "site" or, since V4 milestone 7, a point of interest "poi")
## Result: {ok (any accepted), code (of the first refusal, or ok), text, accepted [ids],
## refused {id: {code, text, confirmable}}}.
func cmd_order(p: Dictionary) -> Dictionary:
	var acc: Array = []
	var ref := {}
	var first := ""
	for aid in p.get("agents", []):
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		var c: Dictionary = check(a, p)
		if not bool(c["ok"]):
			ref[int(aid)] = c
			if first == "":
				first = String(c["code"])
			continue
		_give(a, p)
		acc.append(int(aid))
	var code: String = "ok" if not acc.is_empty() else (first if first != "" else "invalid")
	return {"ok": not acc.is_empty(), "code": code, "text": text_of(code), "accepted": acc, "refused": ref}

func _give(a: Dictionary, p: Dictionary) -> void:
	var kind: String = String(p["kind"])
	var o := {"kind": kind, "confirm": bool(p.get("confirm", false)), "t": int(sim.state["tick"])}
	match kind:
		"go", "stay":
			var to: Dictionary = _target(a, Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
			o["p"] = to["p"]
			o["b"] = int(to["b"])
			o["stay"] = kind == "stay" or bool(p.get("stay", false))
		"board":
			o["v"] = int(p["v"])
		"work_at":
			o["b"] = int(p["b"])
		"survey":
			if p.has("poi"):
				o["poi"] = int(p["poi"])
				o["site"] = -1
			else:
				o["site"] = int(p["site"])
				sim.hazards.hs()["sites"][int(p["site"])]["order"] = true
	if kind != "work_at":
		sim.agents.abort_plan(a, "ordered")
	a["order"] = o
	a["goal"] = goal_text(a)

## "order_clear" {agents}: the colonists go back to their own choices.
func cmd_clear(p: Dictionary) -> Dictionary:
	var n := 0
	for aid in p.get("agents", []):
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		if not a.is_empty() and a.has("order"):
			clear(a, "")
			n += 1
	return {"ok": true, "code": "ok", "cleared": n}

## "set_jobs" {agent, jobs: {category: 0..3}} or {agent, clear: true}.
func cmd_jobs(p: Dictionary) -> Dictionary:
	var a: Dictionary = sim.state["agents"].get(int(p.get("agent", -1)), {})
	if a.is_empty() or a["kind"] == "visitor":
		return {"ok": false, "code": "unknown"}
	if bool(p.get("clear", false)):
		a.erase("jobs")
		return {"ok": true, "code": "ok"}
	var cats: Array = job_categories()
	var j: Dictionary = (a.get("jobs", {}) as Dictionary).duplicate()
	var jobs: Dictionary = p.get("jobs", {})
	for c in jobs:
		if not cats.has(String(c)):
			return {"ok": false, "code": "invalid"}
		j[String(c)] = clampi(int(jobs[c]), 0, 3)
	a["jobs"] = j
	return {"ok": true, "code": "ok"}

## The job categories a colonist can have priorities for: the colony priority keys (every
## task has one of them: construction, food, industry, logistics, repair).
func job_categories() -> Array:
	var out: Array = (sim.state["policies"]["priority"] as Dictionary).keys()
	out.sort()
	return out

func clear(a: Dictionary, why: String) -> void:
	a.erase("order")
	if why != "":
		sim.log_event("order_ended", "%s: the order ended (%s)." % [a["name"], why], [int(a["id"])], 1)

# ---------------------------------------------------------------- the colonist's side
## True while an order the player confirmed is running: the colonist does not turn back for air.
func confirmed(a: Dictionary) -> bool:
	var o = a.get("order")
	return o != null and bool(o["confirm"])

## Task filter for _try_work: work_at keeps a colonist to one structure, survey to one site.
## Returns true when the colonist may take this task.
func allows(a: Dictionary, t: Dictionary) -> bool:
	var o: Dictionary = a["order"]
	match String(o["kind"]):
		"work_at":
			return int(t["bld"]) == int(o["b"])
		"survey":
			return not o.has("poi") and t["kind"] == "survey" and int(t.get("site", -1)) == int(o["site"])
	return false

## Called from _think when the colonist has no plan. true = the order made a plan (or holds).
func think(a: Dictionary) -> bool:
	var o: Dictionary = a["order"]
	match String(o["kind"]):
		"go", "stay":
			var p: Vector2 = o["p"]
			var here: bool = (a["pos"] as Vector2).distance_to(p) < 1.0 and (int(o["b"]) == -1 or (a["where"] == "in" and int(a["bld"]) == int(o["b"])))
			if here:
				if not bool(o["stay"]):
					clear(a, "")
					return false
				sim.agents._start_plan(a, "order", [{"op": "wait", "t": 30.0}], "Staying here (order)")
				return true
			return _walk(a, {"b": int(o["b"]), "p": p}, "Going to the ordered place")
		"return":
			var h: Dictionary = _home_target(a)
			if h.is_empty():
				clear(a, "no base with air")
				return false
			if a["where"] == "in" and sim.bases.base_of(int(a["bld"])) == sim.bases.home_of(a) and sim.util.building_supplied(int(a["bld"])):
				clear(a, "")
				return false
			return _walk(a, h, "Returning to base (order)")
		"board":
			var v: Dictionary = sim.vehicles.get_v(int(o["v"]))
			if v.is_empty() or (v["crew"] as Array).size() >= sim.vehicles.seats(v):
				clear(a, "no seat")
				return false
			if a["where"] == "vehicle":
				clear(a, "")
				return true
			if sim.agents.order_board(a, int(o["v"])):
				a.erase("order")      # the plan carries it to the seat
				return true
			clear(a, "no way to the vehicle")
			return false
		"work_at":
			if not sim.state["buildings"].has(int(o["b"])):
				clear(a, "the structure is gone")
			return false
		"survey":
			if o.has("poi"):
				var poi: Dictionary = sim.explore.poi(int(o["poi"]))
				if poi.is_empty() or bool(poi["visited"]):
					clear(a, "")
					return false
				var q = sim.nav.nearest_walkable(Vector2(poi["x"], poi["y"]), 10)
				if q == null:
					clear(a, "no way there")
					return false
				if (a["pos"] as Vector2).distance_to(q) < 1.0:
					sim.agents._start_plan(a, "order", [{"op": "wait", "t": 3.0}], "Surveying (order)")
					return true
				return _walk(a, {"b": -1, "p": q}, "Going to survey (order)")
			var site: Dictionary = sim.hazards.hs()["sites"].get(int(o["site"]), {})
			if site.is_empty() or bool(site.get("surveyed", false)):
				clear(a, "")
			return false
	return false

func _walk(a: Dictionary, to: Dictionary, goal: String) -> bool:
	var r: Dictionary = sim.nav.plan(sim.agents.loc_of(a), to)
	if not r["ok"]:
		clear(a, "no way there")
		return false
	sim.agents._start_plan(a, "order", [{"op": "go", "to": to, "route": r, "rev": int(sim.state["rev"]["walk"])}, {"op": "wait", "t": 0.5}], goal)
	return true

func goal_text(a: Dictionary) -> String:
	var o = a.get("order")
	if o == null:
		return String(a["goal"])
	match String(o["kind"]):
		"go": return "Going to the ordered place"
		"stay": return "Staying here (order)"
		"return": return "Returning to base (order)"
		"board": return "Going to the vehicle (order)"
		"work_at": return "Working at %s (order)" % String(sim.state["buildings"].get(int(o["b"]), {}).get("name", "?"))
		"survey": return "Survey (order)"
	return String(a["goal"])
