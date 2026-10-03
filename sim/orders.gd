extends RefCounted
## Player orders to colonists (docs/V4_DESIGN.md section 5, "Orders"). An order overrides the
## colonist's own choice of work until it is done or cleared. Critical needs (thirst, hunger,
## exhaustion) still interrupt it; the order continues after them.
##
## agent.order (absent when there is none) = {kind, p (Vector2), b (room id or -1), v, site,
##   stay (bool), confirm (bool), t (tick given)}
##   kind: "go" | "stay" | "return" | "board" | "work_at" | "survey" | "repair" | "maintain" | "build" | "haul" | "task"
##   V5 section 18: repair / maintain {b}, build {b}, haul {res, left, b}, task {tid} (made by the work queue).
##   Also: text (what the colonist does for the order, for the person window), blocked ("" or a code),
##   missing {item, qty} (what a blocked order waits for), tid (the task that carries it out), team (a team order id).
##   An order interrupts every plan except one that answers an imminent death need (drive).
## agent.jobs (absent when there is none) = {category: 0..3}: this colonist's own job
##   priorities; 0 = not allowed. A category not in it uses the colony priority.
##
## The AI refuses an order that would kill the colonist (suit air, radiation) with a code and
## a reason; with confirm: true the order runs anyway and the colonist does not turn back for
## air while it runs.

var sim

func _init(s) -> void:
	sim = s

const KINDS := ["go", "stay", "return", "board", "work_at", "survey", "repair", "maintain", "build", "haul", "task"]
## Order kinds that a head of a department allocates to the team (docs/V5_DESIGN.md 18.2).
const TEAM_KINDS := ["repair", "maintain", "build", "haul", "work_at"]
## Orders that make a task for the colonist (_think_work).
const WORK_KINDS := ["repair", "maintain", "build", "haul", "task", "work_at"]
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
	"no_work": "That structure needs no repair.",
	"not_site": "That is not a site that is being built.",
	"no_item": "The colony has none of that item.",
	"no_task": "That work does not exist any more.",
	"no_head": "That colonist is not a head of a department.",
	"no_one": "Nobody is free to take the order.",
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
	if a["kind"] == "visitor" or a["kind"] == "child":
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
			# Work at a structure that has no work (no task, no wear, not a site): nothing to do.
			if b["state"] != "blueprint" and b["state"] != "building" and repair_need(b) == "" and sim.jobs.tasks_at(int(b["id"])) == 0:
				return "no_work"
		"repair", "maintain":
			var rb: Dictionary = sim.state["buildings"].get(int(p.get("b", -1)), {})
			if rb.is_empty() or (rb["state"] != "active" and rb["state"] != "broken"):
				return "no_building"
			# A "maintain" order is a standing one: it is accepted for any machine, even a sound one.
			if kind == "repair" and repair_need(rb) == "":
				return "no_work"
			if kind == "maintain" and repair_need(rb) == "" and not sim.hazards.is_machine(rb):
				return "no_work"
		"build":
			var sb: Dictionary = sim.state["buildings"].get(int(p.get("b", -1)), {})
			if sb.is_empty() or (sb["state"] != "blueprint" and sb["state"] != "building"):
				return "not_site"
		"haul":
			var hb: Dictionary = sim.state["buildings"].get(int(p.get("b", -1)), {})
			var hres: String = String(p.get("res", ""))
			if hb.is_empty() or sim.jobs.order_inv(hb) == -1:
				return "no_building"
			if not sim.content["items"].has(hres) or int(p.get("qty", 1)) < 1:
				return "invalid"
			if sim.jobs.find_source(hres, hb["pos"], sim.jobs.order_inv(hb), true) == -1:
				return "no_item"
		"task":
			var tk: Dictionary = sim.state["tasks"].get(int(p.get("tid", -1)), {})
			if tk.is_empty() or (int(tk["owner"]) != -1 and int(tk["owner"]) != int(a["id"])):
				return "no_task"
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
	# V5 section 18.2: a work order to a head of a department is a team order (the head allocates it).
	if not bool(p.get("direct", false)) and TEAM_KINDS.has(String(p.get("kind", ""))) and (p.get("agents", []) as Array).size() == 1:
		var head: Dictionary = sim.state["agents"].get(int((p["agents"] as Array)[0]), {})
		if not head.is_empty() and sim.workq.is_head(head):
			return sim.workq.team_order(head, p)
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
	var o := {"kind": kind, "confirm": bool(p.get("confirm", false)), "t": int(sim.state["tick"]), "blocked": "", "text": "", "tid": -1}
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
		"repair", "maintain", "build":
			o["b"] = int(p["b"])
			o["standing"] = kind == "maintain"
		"haul":
			o["b"] = int(p["b"])
			o["res"] = String(p["res"])
			o["left"] = int(p.get("qty", 1))
		"task":
			o["tid"] = int(p["tid"])
		"survey":
			if p.has("poi"):
				o["poi"] = int(p["poi"])
				o["site"] = -1
			else:
				o["site"] = int(p["site"])
				sim.hazards.hs()["sites"][int(p["site"])]["order"] = true
	if p.has("team"):
		o["team"] = int(p["team"])
	# A work order drops the colonist's plan when it has work to start (think); the others at once.
	if not WORK_KINDS.has(kind):
		sim.agents.abort_plan(a, "ordered")
	a["order"] = o
	o["text"] = goal_text(a)
	if not WORK_KINDS.has(kind):
		a["goal"] = String(o["text"])
	if kind == "maintain":
		sim.workq.standing_add(a, int(p["b"]))

## "order_clear" {agents}: the colonists go back to their own choices.
func cmd_clear(p: Dictionary) -> Dictionary:
	var n := 0
	for aid in p.get("agents", []):
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		if not a.is_empty():
			sim.workq.clear_standing(int(aid))
		if not a.is_empty() and a.has("order"):
			# The work the order started stops too (a repair walk is not left to finish by itself).
			if a["plan_kind"] == "task" and int(a["task"]) != -1 and int(a["task"]) == int(a["order"].get("tid", -2)):
				sim.agents.abort_plan(a, "order_cleared")
			sim.workq.order_ended(a, true)
			a.erase("order")
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
	sim.workq.order_ended(a, false)
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
		"repair", "maintain", "build", "haul", "task", "work_at":
			return _think_work(a, o)
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

# ---------------------------------------------------------------- V5 section 18.1: an order is obeyed at once
## What a repair order still has to do on structure b ("" = nothing): "repair" (broken or worn down),
## "patch" (a breach), "clean" (dust on a panel), "maintain" (the wear of a machine).
func repair_need(b: Dictionary) -> String:
	if b["state"] == "broken" or float(b["health"]) < 99.5:
		return "repair"
	if bool(b.get("breach", false)):
		return "patch"
	if bool(b.get("dust", false)) and b["state"] == "active":
		return "clean"
	if sim.hazards.is_machine(b):
		var rec: Dictionary = sim.hazards.hs()["wear"].get(int(b["id"]), {})
		if not rec.is_empty() and float(rec["w"]) >= 1.0:
			return "maintain"
	return ""

## True when the plan answers an imminent death need: the order waits for it and resumes right after.
func _imminent(a: Dictionary, kind: String) -> bool:
	if a.has("lift"):
		return true
	var crit: float = float(sim.bal["need_critical"])
	match kind:
		"safety":
			return true
		"drink":
			return float(a["thirst"]) >= crit * 0.5
		"eat":
			return float(a["hunger"]) >= crit * 0.5
		"sleep":
			return float(a["fatigue"]) >= crit
		"heal":
			return float(a["health"]) < 30.0
	return false

## Called at every think of a colonist who has an order (agents._think, after the critical needs). The plan that
## carries the order out keeps running; any other plan (a party, sleep, leisure, a talk, work, idle) is
## dropped at once. true = the colonist is busy with the order (or with an imminent need).
func drive(a: Dictionary) -> bool:
	var o: Dictionary = a["order"]
	var plan: Array = a["plan"]
	if not plan.is_empty():
		var kind: String = String(a["plan_kind"])
		var tid: int = int(a["task"])
		if kind == "order":
			return true
		if kind == "task" and tid != -1 and tid == int(o.get("tid", -2)):
			return true
		if kind == "task" and tid != -1 and sim.state["tasks"].has(tid) and o["kind"] == "survey" and allows(a, sim.state["tasks"][tid]):
			return true
		if _imminent(a, kind):
			return false
		# A work order decides first and drops the colonist's plan only when it has work to start (think does
		# it): an order that waits for a part leaves the colonist's own plan alone (no thrash).
		if WORK_KINDS.has(String(o["kind"])):
			return think(a)
		sim.agents.abort_plan(a, "ordered")
	return think(a)

## True when the order waits for something (an item, a way): the colonist then works as usual meanwhile.
func is_blocked(a: Dictionary) -> bool:
	var o = a.get("order")
	return o != null and String((o as Dictionary).get("blocked", "")) != ""

func _blocked(a: Dictionary, o: Dictionary, code: String, text: String, missing: Dictionary = {}) -> bool:
	o["blocked"] = code
	o["text"] = text
	o["missing"] = missing
	o["fails"] = int(o.get("fails", 0)) + 1
	# The order is looked at again in five seconds (not every second: it asks the stores each time).
	o["next"] = int(sim.state["tick"]) + 5 * int(sim.bal["tick_hz"])
	if (a["plan"] as Array).is_empty():
		a["goal"] = text
	# An order that cannot be carried out for want of a way (not for want of an item) ends after two minutes.
	if missing.is_empty() and int(o["fails"]) > 24:
		clear(a, text)
		return false
	if not missing.is_empty():
		sim.chains.report_missing(String(missing["item"]), int(missing.get("qty", 1)), "order", int(o.get("b", -1)), String(a["name"]), String(missing.get("reason", "none")))
	return false

func _ok(a: Dictionary, o: Dictionary, tid: int) -> bool:
	o["blocked"] = ""
	o["missing"] = {}
	o["fails"] = 0
	o["tid"] = tid
	o["text"] = String(a["goal"])
	return true

func _finished(a: Dictionary, o: Dictionary, text: String) -> bool:
	sim.log_event("order_done", "%s: %s" % [a["name"], text], [int(a["id"]), int(o.get("b", -1))], 1)
	if bool(o.get("standing", false)):
		sim.workq.standing_wait(a, o)
	clear(a, "")
	return false

func _why(reason: String) -> String:
	match reason:
		"no_path", "no_path_src", "no_path_here":
			return "there is no way to it"
		"suit_range":
			return "the suit air is not enough"
		"no_air":
			return "the room has no air"
		"shelter":
			return "everybody must stay inside"
	return reason

## The thinking of the work orders (repair, maintain, build, haul, task, work_at). Called when the colonist has no
## plan that carries the order out. It decides first: only an order that has a plan to start drops the
## colonist's own plan (agents.begin_task); an order that waits keeps the colonist's plan and is looked at again
## every five seconds.
func _think_work(a: Dictionary, o: Dictionary) -> bool:
	var tick: int = int(sim.state["tick"])
	if String(o.get("blocked", "")) != "" and tick < int(o.get("next", 0)):
		return false
	var blds: Dictionary = sim.state["buildings"]
	var kind: String = String(o["kind"])
	if kind == "task":
		var t0: Dictionary = sim.state["tasks"].get(int(o["tid"]), {})
		if t0.is_empty() or (int(t0["owner"]) != -1 and int(t0["owner"]) != int(a["id"])):
			return _finished(a, o, "the assigned work is done or gone.")
		return _start(a, o, t0, "the assigned work")
	var b: Dictionary = blds.get(int(o["b"]), {})
	if b.is_empty():
		clear(a, "the structure is gone")
		return false
	var nm: String = String(b["name"])
	if kind == "work_at":
		# Work at a structure: a site is built, a worn structure is repaired, else the open work there is done.
		if b["state"] == "blueprint" or b["state"] == "building":
			kind = "build"
		elif repair_need(b) != "":
			kind = "repair"
		else:
			var wt: Dictionary = sim.jobs.best_task_at(int(o["b"]), a)
			if wt.is_empty():
				return _finished(a, o, "there is no more work at %s." % nm)
			return _start(a, o, wt, nm)
	match kind:
		"repair", "maintain":
			if b["state"] != "active" and b["state"] != "broken":
				clear(a, "the structure is gone")
				return false
			var need: String = repair_need(b)
			if need == "":
				return _finished(a, o, "%s is in repair." % nm)
			var r: Dictionary = sim.jobs.order_task(int(o["b"]), need, int(a["id"]))
			if r.has("missing"):
				var item: String = String(r["missing"])
				var why: String = String(r.get("reason", "none"))
				var text: String = "Waiting for %s to repair %s (order)" % [sim.items.name_of(item).to_lower(), nm]
				if why == "unreachable":
					text = "The %s for %s lies where nobody can reach it (order)" % [sim.items.name_of(item).to_lower(), nm]
				elif why == "elsewhere":
					text = "The %s for %s is at another base (order)" % [sim.items.name_of(item).to_lower(), nm]
				return _blocked(a, o, "no_item", text, {"item": item, "qty": int(r.get("qty", 1)), "reason": why})
			if r.has("busy"):
				return _blocked(a, o, "busy", "Another colonist is already on %s (order)" % nm)
			return _start(a, o, r["task"], "repair %s" % nm)
		"build":
			if b["state"] == "active":
				return _finished(a, o, "%s is built." % nm)
			if b["state"] == "blueprint":
				var blk: String = String(b.get("block", ""))
				if blk.begins_with("materials:"):
					var mi: String = blk.substr(10)
					return _blocked(a, o, "no_item", "Waiting for %s to build %s (order)" % [sim.items.name_of(mi).to_lower(), nm], {"item": mi, "qty": 1, "reason": "none"})
				var h: Dictionary = sim.jobs.open_task_at(int(o["b"]), "haul")
				if h.is_empty():
					return _blocked(a, o, "wait", "Waiting for the materials of %s (order)" % nm)
				return _start(a, o, h, "carry materials to %s" % nm)
			if b["state"] == "building":
				var bt: Dictionary = sim.jobs.open_task_at(int(o["b"]), "build")
				if bt.is_empty():
					return _blocked(a, o, "wait", "All the places at %s are taken (order)" % nm)
				return _start(a, o, bt, "build %s" % nm)
			clear(a, "the site is gone")
			return false
		"haul":
			var res: String = String(o["res"])
			if int(o["left"]) <= 0:
				return _finished(a, o, "%s delivered to %s." % [sim.items.name_of(res), nm])
			var hr: Dictionary = sim.jobs.order_haul(res, int(o["left"]), int(o["b"]))
			if hr.has("missing"):
				return _blocked(a, o, "no_item", "Waiting for %s to carry to %s (order)" % [sim.items.name_of(res).to_lower(), nm], {"item": res, "qty": int(o["left"]), "reason": String(hr.get("reason", "none"))})
			if hr.has("full"):
				return _blocked(a, o, "full", "%s has no room for %s (order)" % [nm, sim.items.name_of(res).to_lower()])
			var ht: Dictionary = hr["task"]
			var plan: Dictionary = sim.agents.plan_task_for(a, ht)
			if not bool(plan["ok"]):
				sim.jobs.fail(int(ht["id"]), "order_failed")
				return _blocked(a, o, String(plan["reason"]), "Cannot carry %s: %s (order)" % [sim.items.name_of(res).to_lower(), _why(String(plan["reason"]))])
			sim.agents.begin_task(a, ht, plan)
			return _ok(a, o, int(ht["id"]))
	return false

## Plans task t for the colonist; when the plan is possible the colonist starts it (and drops its own plan).
func _start(a: Dictionary, o: Dictionary, t: Dictionary, what: String) -> bool:
	t["retry"] = 0
	var plan: Dictionary = sim.agents.plan_task_for(a, t)
	if not bool(plan["ok"]):
		return _blocked(a, o, String(plan["reason"]), "Cannot %s: %s (order)" % [what, _why(String(plan["reason"]))])
	sim.agents.begin_task(a, t, plan)
	return _ok(a, o, int(t["id"]))

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
		"repair": return "Going to repair %s (order)" % _bname(o)
		"maintain": return "Going to maintain %s (order)" % _bname(o)
		"build": return "Going to build %s (order)" % _bname(o)
		"haul": return "Going to fetch %s for %s (order)" % [sim.items.name_of(String(o["res"])).to_lower(), _bname(o)]
		"task": return "Doing the work that was assigned (order)"
	return String(a["goal"])

func _bname(o: Dictionary) -> String:
	return String(sim.state["buildings"].get(int(o.get("b", -1)), {}).get("name", "a structure"))
