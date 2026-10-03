extends RefCounted
## Chain of command and work queues (docs/V5_DESIGN.md sections 18.2 and 18.3).
##
## TEAM ORDERS: a work order (repair, maintain, build, haul, work_at) given to a head of a department (a Base
## Commander or a Captain) is allocated by the head to the best free people of the department, by skill and
## distance; the log says who ("Captain Asha assigned Bram and Lin to repair Solar Array 3"), and the team is
## listed in the queue until its members have finished. orders.gd calls is_head and team_order.
##
## QUEUES: one queue of open work for each department (maintenance, industry, food, science, logistics, security).
## A queue row is a task of the job board, a team order, a standing order, or a worn structure waiting for a part.
## The player moves rows (Top, Up, Down, Bottom), assigns them to a colonist (that colonist gets a "task" order),
## or cancels (holds) them. The order of a department queue is kept in state.v5.workq.pins and the job choice
## follows it (jobs.score), after orders and critical needs. Priorities (set_jobs, set_priority) still decide
## which kind of work a colonist serves.
##
## state.v5.workq = {next, teams {id: team}, standing {"agent:bld": {agent, b, since}}, pins {dept: [{k, low}]},
##   hold {key: until tick}, reports [{tick, text}]}   (made on first use)

var sim
## True while any pin or hold exists (jobs.score then asks adjust()).
var busy := false
var _rest := {}          # key -> pin value (derived from pins)
var _dirty := true

const DEPTS := ["maintenance", "industry", "food", "science", "logistics", "security"]
const DEPT_NAMES := {"maintenance": "Maintenance", "industry": "Industry", "food": "Food", "science": "Science", "logistics": "Logistics", "security": "Security"}
## The type of a row (spec 18.3.1): build, repair, maintain, haul, produce, research, security, medical.
const TYPE_OF := {"build": "build", "demolish": "build", "upgrade": "build", "vbuild": "build", "shipwork": "build",
	"repair": "repair", "patch": "repair", "clean": "repair", "maintain": "maintain", "haul": "haul",
	"operate": "produce", "tend": "produce", "research": "research", "survey": "research"}

func _init(s) -> void:
	sim = s

func reset() -> void:
	_rest = {}
	_dirty = true
	busy = false

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("workq"):
		v["workq"] = {"next": 1, "teams": {}, "standing": {}, "pins": {}, "hold": {}, "reports": []}
	return v["workq"]

func _have() -> bool:
	return sim.state.has("v5") and (sim.state["v5"] as Dictionary).has("workq")

# ---------------------------------------------------------------- the chain of command
## A head of a department: a Base Commander or a Captain (people.rank).
func is_head(a: Dictionary) -> bool:
	if a["state"] != "alive" or a["kind"] == "visitor" or a["kind"] == "child":
		return false
	var r: String = String(sim.people.rank(a).get("rank", ""))
	return r == "commander" or r == "captain"

func _skill_of(kind: String) -> String:
	return "engineering"

func _what(p: Dictionary) -> String:
	var bn: String = String(sim.state["buildings"].get(int(p.get("b", -1)), {}).get("name", "a structure"))
	match String(p.get("kind", "")):
		"repair": return "repair %s" % bn
		"maintain": return "keep %s in repair" % bn
		"build": return "build %s" % bn
		"haul": return "carry %s to %s" % [sim.items.name_of(String(p.get("res", ""))).to_lower(), bn]
		"work_at": return "work at %s" % bn
	return "do the work"

func _names_text(ids: Array) -> String:
	var names: Array = []
	for id in ids:
		names.append(String(sim.state["agents"][int(id)]["name"]).split(" ")[0])
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + names[names.size() - 1]

## The head allocates the order to the best free people of the department. Result: the cmd_order result plus
## {team, head, assigned [ids], report}.
func team_order(head: Dictionary, p: Dictionary) -> Dictionary:
	var kind: String = String(p.get("kind", ""))
	var rk: String = String(sim.people.rank(head).get("rank", ""))
	var dept: String = sim.people.department(head)
	var many: bool = sim.bases.count() > 1
	var base: int = sim.bases.base_of_agent(head) if many else -1
	var crit: float = float(sim.bal["need_critical"])
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var target: Vector2 = Vector2.ZERO
	var tb: Dictionary = sim.state["buildings"].get(int(p.get("b", -1)), {})
	if not tb.is_empty():
		target = tb["pos"]
	var skill: String = _skill_of(kind)
	var cands: Array = []
	var refused := {}
	var first := ""
	var members := 0
	for aid in ids:
		var m: Dictionary = sim.state["agents"][aid]
		if int(aid) == int(head["id"]) or m["state"] != "alive" or m["kind"] == "visitor" or m["kind"] == "child":
			continue
		if many and sim.bases.base_of_agent(m) != base:
			continue
		if rk == "captain" and sim.people.department(m) != dept:
			continue
		members += 1
		if m["where"] == "lock" or m["where"] == "vehicle" or m.has("order") or m.has("v5_hold") or m.has("jailed"):
			continue
		if float(m["thirst"]) >= crit or float(m["hunger"]) >= crit or float(m["fatigue"]) >= crit:
			continue
		var c: Dictionary = sim.orders.check(m, p)
		if not bool(c["ok"]):
			refused[int(aid)] = c
			if first == "":
				first = String(c["code"])
			continue
		var sk: float = float(sim.people.skills(m).get(skill, 0.0))
		var idle: float = 10.0 if (m["plan"] as Array).is_empty() else 0.0
		cands.append([sk + 30.0 + idle - (m["pos"] as Vector2).distance_to(target) / 4.0, int(aid)])
	cands.sort_custom(func(x, y): return x[0] > y[0] if x[0] != y[0] else x[1] < y[1])
	var n: int = clampi(int(p.get("count", 2)), 1, 8)
	var assigned: Array = []
	for c in cands:
		if assigned.size() >= n:
			break
		assigned.append(int(c[1]))
	# The head does it too when the department is small, or when nobody else is free.
	var head_in := false
	if assigned.size() < n or members < 2:
		var hc: Dictionary = sim.orders.check(head, p)
		if bool(hc["ok"]) and not head.has("order"):
			assigned.append(int(head["id"]))
			head_in = true
		elif first == "":
			first = String(hc["code"])
			refused[int(head["id"])] = hc
	if assigned.is_empty():
		var code: String = "no_one" if first == "" or first == "ok" else first
		return {"ok": false, "code": code, "text": sim.orders.text_of(code), "accepted": [], "refused": refused}
	var w: Dictionary = _w()
	var tid: int = int(w["next"])
	w["next"] = tid + 1
	var title: String = String(sim.people.rank(head).get("title", "Captain"))
	var left: int = int(p.get("qty", 1))
	var per: int = maxi(1, left / assigned.size()) if kind == "haul" else 1
	for i in assigned.size():
		var m2: Dictionary = sim.state["agents"][assigned[i]]
		var p2: Dictionary = p.duplicate()
		p2["agents"] = [assigned[i]]
		p2["team"] = tid
		if kind == "haul":
			p2["qty"] = per if i < assigned.size() - 1 else left - per * (assigned.size() - 1)
		sim.orders._give(m2, p2)
	var report: String = "%s %s assigned %s to %s." % [title, String(head["name"]).split(" ")[0], _names_text(assigned), _what(p)]
	if head_in and assigned.size() == 1:
		report = "%s %s does it: nobody else is free to %s." % [title, String(head["name"]).split(" ")[0], _what(p)]
	w["teams"][tid] = {"id": tid, "head": int(head["id"]), "dept": dept, "kind": kind, "b": int(p.get("b", -1)), "res": String(p.get("res", "")),
		"qty": int(p.get("qty", 1)), "assignees": assigned.duplicate(), "tick": int(sim.state["tick"]), "text": report, "p": p.duplicate(true)}
	sim.log_event("team_order", report, [int(head["id"])] + assigned, 1)
	return {"ok": true, "code": "ok", "text": report, "accepted": assigned, "refused": refused, "team": tid, "head": int(head["id"]), "assigned": assigned, "report": report}

## An order for a whole department ("maintain now"): its head allocates it (a team order). A department with no
## head gives it to its best free colonist, who allocates it the same way.
func assign_department(dept: String, base: int, p: Dictionary) -> Dictionary:
	var head: int = sim.people.captain_of(dept, base)
	if head != -1 and sim.state["agents"].has(head) and sim.state["agents"][head]["state"] == "alive":
		var q: Dictionary = p.duplicate()
		q["agents"] = [head]
		return team_order(sim.state["agents"][head], q)
	var ids: Array = sim.state["agents"].keys()
	ids.sort()
	var many: bool = sim.bases.count() > 1
	for aid in ids:
		var m: Dictionary = sim.state["agents"][aid]
		if m["state"] != "alive" or m["kind"] == "visitor" or m["kind"] == "child" or sim.people.department(m) != dept:
			continue
		if many and base != -1 and sim.bases.base_of_agent(m) != base:
			continue
		var q2: Dictionary = p.duplicate()
		q2["agents"] = [int(aid)]
		return team_order(m, q2)
	return {"ok": false, "code": "no_one", "text": sim.orders.text_of("no_one"), "accepted": [], "refused": {}}

## An order of a colonist ended (done, refused, or cleared by the player). A team order is finished when its last
## member's order is gone: the head reports back in the log.
## The player cleared the orders of a colonist: a standing order of that colonist ends too, and the colonist
## goes back to routine.
func clear_standing(aid: int) -> void:
	if not _have():
		return
	var st: Dictionary = _w()["standing"]
	for key in st.keys():
		if int(st[key]["agent"]) == aid:
			st.erase(key)

func order_ended(a: Dictionary, cleared: bool) -> void:
	if not _have():
		return
	var o: Dictionary = a.get("order", {})
	if o.is_empty():
		return
	var w: Dictionary = _w()
	if cleared and bool(o.get("standing", false)):
		w["standing"].erase("%d:%d" % [int(a["id"]), int(o.get("b", -1))])
	if not o.has("team"):
		return
	var team: Dictionary = w["teams"].get(int(o["team"]), {})
	if team.is_empty():
		return
	for aid in team["assignees"]:
		var m: Dictionary = sim.state["agents"].get(int(aid), {})
		if m.is_empty() or int(aid) == int(a["id"]):
			continue
		var mo: Dictionary = m.get("order", {})
		if not mo.is_empty() and int(mo.get("team", -1)) == int(team["id"]):
			return
	var head: Dictionary = sim.state["agents"].get(int(team["head"]), {})
	var hn: String = String(head.get("name", "The head")).split(" ")[0]
	var text: String = "%s reports: %s." % [hn, _done_text(team, cleared)]
	w["teams"].erase(int(team["id"]))
	var rep: Array = w["reports"]
	rep.append({"tick": int(sim.state["tick"]), "text": text})
	while rep.size() > 10:
		rep.pop_front()
	sim.log_event("team_done", text, [int(team["head"])], 1)

func _done_text(team: Dictionary, cleared: bool) -> String:
	var what: String = _what(team["p"])
	if cleared:
		return "the order to %s was cancelled" % what
	return "the team has finished: %s" % what

# ---------------------------------------------------------------- standing orders (maintain)
func standing_add(a: Dictionary, bid: int) -> void:
	var w: Dictionary = _w()
	w["standing"]["%d:%d" % [int(a["id"]), bid]] = {"agent": int(a["id"]), "b": bid, "since": int(sim.state["tick"])}

func standing_wait(a: Dictionary, o: Dictionary) -> void:
	standing_add(a, int(o.get("b", -1)))

## Once a second (sim.step, phase 2): a colonist with a standing "keep it in repair" order whose structure needs
## repair or maintenance (the same thresholds as the job board) gets the order again.
func tick_second() -> void:
	if not _have():
		return
	var w: Dictionary = _w()
	var st: Dictionary = w["standing"]
	if st.is_empty():
		return
	var crit: float = float(sim.bal["need_critical"])
	var trig: float = float(sim.bal["repair_trigger_health"])
	for key in st.keys():
		var e: Dictionary = st[key]
		var a: Dictionary = sim.state["agents"].get(int(e["agent"]), {})
		var b: Dictionary = sim.state["buildings"].get(int(e["b"]), {})
		if a.is_empty() or a["state"] != "alive" or b.is_empty():
			st.erase(key)
			continue
		if a.has("order") or a["where"] == "lock" or a["where"] == "vehicle":
			continue
		if b["state"] != "active" and b["state"] != "broken":
			continue
		var due: bool = b["state"] == "broken" or float(b["health"]) < trig or bool(b.get("breach", false)) or sim.hazards.wants_maintenance(b)
		if not due:
			continue
		if float(a["thirst"]) >= crit or float(a["hunger"]) >= crit or float(a["fatigue"]) >= crit:
			continue
		var p := {"kind": "maintain", "b": int(e["b"]), "agents": [int(a["id"])]}
		if bool(sim.orders.check(a, p)["ok"]):
			sim.orders._give(a, p)

# ---------------------------------------------------------------- the queue
func dept_of(t: Dictionary) -> String:
	match String(t["kind"]):
		"build", "demolish", "upgrade", "vbuild", "shipwork", "repair", "patch", "clean", "maintain":
			return "maintenance"
		"haul":
			return "logistics"
		"tend":
			return "food"
		"operate":
			return "food" if String(t["cat"]) == "food" else "industry"
		"research", "survey":
			return "science"
	return "industry"

func key_of(t: Dictionary) -> String:
	var k: String = "%s:%d" % [t["kind"], int(t["bld"])]
	match String(t["kind"]):
		"tend":
			k += ":%d" % int(t["tray"])
		"haul":
			k += ":%s" % t["res"]
		"survey":
			k += ":%d" % int(t.get("site", -1))
	return k

func _build_rest() -> void:
	_rest = {}
	var w: Dictionary = _w()
	for dept in w["pins"]:
		var list: Array = w["pins"][dept]
		for i in list.size():
			var e: Dictionary = list[i]
			_rest[String(e["k"])] = (-99.0 + 0.01 * i) if bool(e["low"]) else (99.0 - 0.01 * i)
	busy = not _rest.is_empty() or not (w["hold"] as Dictionary).is_empty()
	_dirty = false

## jobs.score asks when busy: s is the score so far; base is the part from priority and emergency. A held task is
## not offered; a pinned one ranks by its place in the queue among the tasks of its priority.
func adjust(t: Dictionary, s: float, base: float) -> float:
	if _dirty:
		_build_rest()
	var k: String = key_of(t)
	var hold: Dictionary = _w()["hold"]
	if hold.has(k) and int(hold[k]) > int(sim.state["tick"]):
		return -1e9
	if _rest.has(k):
		return base + float(_rest[k])
	return s

func _text_of(t: Dictionary) -> String:
	var b: Dictionary = sim.state["buildings"].get(int(t["bld"]), {})
	var bn: String = String(b.get("name", ""))
	match String(t["kind"]):
		"build": return "Build %s" % bn
		"demolish": return "Take down %s" % bn
		"upgrade": return "Upgrade %s" % bn
		"vbuild": return "Build a vehicle at %s" % bn
		"shipwork": return "Work on the Meridian"
		"repair": return "Repair %s" % bn
		"maintain": return "Maintain %s" % bn
		"patch": return "Seal a breach in %s" % bn
		"clean": return "Clean %s" % bn
		"haul": return "Carry %d %s to %s" % [int(t["qty"]), sim.items.name_of(String(t["res"])).to_lower(), bn]
		"operate": return "Operate %s" % bn
		"tend": return ("Seed " if t["op"] == "seed" else "Harvest ") + "at %s" % bn
		"research": return "Research at %s" % bn
		"survey": return "Survey a fragment site"
	return String(t["kind"])

func _reason_of(t: Dictionary) -> String:
	var r: String = String(t.get("reason", ""))
	if r != "":
		return r
	if int(t["emergency"]) >= 3:
		return "urgent"
	return ""

func _row_of_task(t: Dictionary, now: int, hz: float) -> Dictionary:
	var owner: int = int(t["owner"])
	var a: Dictionary = sim.state["agents"].get(owner, {}) if owner != -1 else {}
	var k: String = key_of(t)
	var hold: Dictionary = _w()["hold"]
	var held: bool = hold.has(k) and int(hold[k]) > now
	var state := "open"
	if owner != -1:
		state = "working" if t["state"] == "working" else "assigned"
	if held:
		state = "held"
	var prio: int = int(sim.state["policies"]["priority"].get(t["cat"], 1))
	return {"key": k, "id": int(t["id"]), "kind": String(t["kind"]), "type": String(TYPE_OF.get(String(t["kind"]), "produce")), "dept": dept_of(t), "b": int(t["bld"]),
		"text": _text_of(t), "prio": prio, "emergency": int(t["emergency"]), "assignee": owner, "assignee_name": String(a.get("name", "")),
		"waiting_s": float(now - int(t["created"])) / hz, "state": state, "reason": _reason_of(t), "urgent": int(t["emergency"]) >= 3, "team": -1, "res": String(t.get("res", ""))}

## The rows of one department queue (dept "" = all), in the order the job choice follows: pinned rows first (top
## to bottom), then the rest by priority and urgency, then rows pinned to the bottom. Each row: {key, id (the
## task id, -1 for others), kind, type, dept, b, text, prio, emergency, assignee, assignee_name, waiting_s, state
## ("open" | "assigned" | "working" | "held" | "blocked" | "team" | "standing"), reason, urgent, team, pinned, low}.
func rows(dept: String = "") -> Array:
	var now: int = int(sim.state["tick"])
	var hz: float = float(sim.bal["tick_hz"])
	var out: Array = []
	var seen := {}
	for tid in sim.state["tasks"]:
		var t: Dictionary = sim.state["tasks"][tid]
		if dept != "" and dept_of(t) != dept:
			continue
		var r: Dictionary = _row_of_task(t, now, hz)
		seen[r["key"]] = true
		out.append(r)
	# Worn or broken structures that wait for a part (no task yet): the maintenance queue shows them too.
	if dept == "" or dept == "maintenance":
		var trig: float = float(sim.bal["repair_trigger_health"])
		for bid in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][bid]
			if b["kind"] == "special" or bool(b["demolish"]) or (b["state"] != "active" and b["state"] != "broken"):
				continue
			if float(b["health"]) >= trig and b["state"] != "broken":
				continue
			var k: String = "repair:%d" % int(bid)
			if seen.has(k):
				continue
			var item: String = sim.hazards.repair_item(b)
			out.append({"key": k, "id": -1, "kind": "repair", "type": "repair", "dept": "maintenance", "b": int(bid), "text": "Repair %s" % b["name"], "prio": int(sim.state["policies"]["priority"].get("repair", 1)),
				"emergency": 3 if b["state"] == "broken" else 0, "assignee": -1, "assignee_name": "", "waiting_s": 0.0, "state": "blocked",
				"reason": "no %s in store" % sim.items.name_of(item).to_lower(), "urgent": b["state"] == "broken", "team": -1, "res": item})
	var w: Dictionary = _w()
	if dept == "" or dept == "maintenance":
		for tid in w["teams"]:
			var tm: Dictionary = w["teams"][tid]
			out.append({"key": "team:%d" % int(tid), "id": -1, "kind": String(tm["kind"]), "type": String(TYPE_OF.get(String(tm["kind"]), "repair")), "dept": "maintenance", "b": int(tm["b"]),
				"text": String(tm["text"]), "prio": 3, "emergency": 0, "assignee": int(tm["head"]), "assignee_name": _names_text(tm["assignees"]), "waiting_s": float(now - int(tm["tick"])) / hz,
				"state": "team", "reason": "team order", "urgent": false, "team": int(tid), "res": String(tm["res"])})
		for key in w["standing"]:
			var e: Dictionary = w["standing"][key]
			var sa: Dictionary = sim.state["agents"].get(int(e["agent"]), {})
			var sb: Dictionary = sim.state["buildings"].get(int(e["b"]), {})
			out.append({"key": "standing:%s" % key, "id": -1, "kind": "maintain", "type": "maintain", "dept": "maintenance", "b": int(e["b"]),
				"text": "Keep %s in repair" % String(sb.get("name", "?")), "prio": 2, "emergency": 0, "assignee": int(e["agent"]), "assignee_name": String(sa.get("name", "")),
				"waiting_s": float(now - int(e["since"])) / hz, "state": "standing", "reason": "standing order", "urgent": false, "team": -1, "res": ""})
	_order_rows(out, dept)
	return out

func _order_rows(out: Array, dept: String) -> void:
	var w: Dictionary = _w()
	var pins: Dictionary = w["pins"]
	var pos := {}      # key -> [low, index]
	for d in pins:
		var list: Array = pins[d]
		for i in list.size():
			pos[String(list[i]["k"])] = [bool(list[i]["low"]), i]
	for r in out:
		var pe = pos.get(String(r["key"]))
		r["pinned"] = pe != null
		r["low"] = pe != null and bool(pe[0])
		# The sort key: high pins, then the automatic order, then low pins.
		var grp: int = 1
		var idx: float = 0.0
		if pe != null:
			grp = 2 if bool(pe[0]) else 0
			idx = float(pe[1])
		else:
			idx = -(100.0 * float(r["prio"]) + 50.0 * float(r["emergency"]) + 0.1 * float(r["waiting_s"]))
		r["_s"] = [grp, idx, int(r["id"])]
	out.sort_custom(func(x, y):
		var a: Array = x["_s"]
		var b: Array = y["_s"]
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	for r in out:
		r.erase("_s")

## Urgent rows that nobody has: the number the dock shows.
func urgent_count() -> int:
	var n := 0
	for r in rows(""):
		if bool(r["urgent"]) and int(r["assignee"]) == -1 and r["state"] != "held":
			n += 1
	return n

# ---------------------------------------------------------------- queue commands
## "workq_move" {key, dept, how: "top" | "up" | "down" | "bottom"}: the rows of the department are frozen in
## their order now, the row moves, and the job choice follows that order.
func cmd_move(p: Dictionary) -> Dictionary:
	var dept: String = String(p.get("dept", ""))
	if not DEPTS.has(dept):
		return {"ok": false, "code": "invalid", "text": "Choose a department."}
	var key: String = String(p.get("key", ""))
	var list: Array = rows(dept)
	var keys: Array = []
	var low := {}
	for r in list:
		keys.append(String(r["key"]))
		if bool(r["low"]):
			low[String(r["key"])] = true
	var i: int = keys.find(key)
	if i == -1:
		return {"ok": false, "code": "no_task", "text": "That row is not in the queue."}
	var how: String = String(p.get("how", ""))
	match how:
		"top":
			keys.remove_at(i)
			keys.insert(0, key)
			low.erase(key)
		"bottom":
			keys.remove_at(i)
			keys.append(key)
			low[key] = true
		"up":
			# The row takes the place (and the group, high or low) of the row it passes.
			if i > 0:
				var passed: String = String(keys[i - 1])
				keys.remove_at(i)
				keys.insert(i - 1, key)
				if low.has(passed):
					low[key] = true
				else:
					low.erase(key)
		"down":
			if i < keys.size() - 1:
				var passed2: String = String(keys[i + 1])
				keys.remove_at(i)
				keys.insert(i + 1, key)
				if low.has(passed2):
					low[key] = true
				else:
					low.erase(key)
		_:
			return {"ok": false, "code": "invalid", "text": "Choose top, up, down or bottom."}
	var w: Dictionary = _w()
	var out: Array = []
	for k in keys:
		out.append({"k": k, "low": low.has(k)})
	w["pins"][dept] = out
	_dirty = true
	return {"ok": true, "code": "ok", "text": ""}

## "workq_assign" {tid or key, agents: [ids]}: the colonists get an order to do that work (a task order). A team
## order takes new members the same way.
func cmd_assign(p: Dictionary) -> Dictionary:
	var ids: Array = p.get("agents", [])
	if ids.is_empty():
		return {"ok": false, "code": "invalid", "text": "Choose a colonist."}
	var w: Dictionary = _w()
	var key: String = String(p.get("key", ""))
	if key.begins_with("team:"):
		var team: Dictionary = w["teams"].get(int(key.substr(5)), {})
		if team.is_empty():
			return {"ok": false, "code": "no_task", "text": sim.orders.text_of("no_task")}
		for aid in team["assignees"]:
			var old: Dictionary = sim.state["agents"].get(int(aid), {})
			if not old.is_empty() and old.has("order") and int(old["order"].get("team", -1)) == int(team["id"]):
				cmd_cancel_order(old)
		var acc: Array = []
		var ref := {}
		for aid in ids:
			var m: Dictionary = sim.state["agents"].get(int(aid), {})
			var p2: Dictionary = (team["p"] as Dictionary).duplicate()
			p2["agents"] = [int(aid)]
			p2["team"] = int(team["id"])
			var c: Dictionary = sim.orders.check(m, p2)
			if bool(c["ok"]):
				sim.orders._give(m, p2)
				acc.append(int(aid))
			else:
				ref[int(aid)] = c
		team["assignees"] = acc.duplicate()
		team["text"] = "%s was reassigned to %s." % [_what(team["p"]), _names_text(acc)] if not acc.is_empty() else String(team["text"])
		if acc.is_empty():
			w["teams"].erase(int(team["id"]))
		return {"ok": not acc.is_empty(), "code": "ok" if not acc.is_empty() else "no_one", "text": "", "accepted": acc, "refused": ref}
	var tid: int = int(p.get("tid", -1))
	if tid == -1 and key != "":
		for r in rows(""):
			if String(r["key"]) == key and int(r["id"]) != -1:
				tid = int(r["id"])
				break
	var t: Dictionary = sim.state["tasks"].get(tid, {})
	if t.is_empty():
		# A worn structure that waits for a part has no task yet: the order makes it (and reports what is missing).
		if key.begins_with("repair:"):
			var bid: int = int(key.substr(7))
			var acc2: Array = []
			var ref2 := {}
			for aid in ids:
				var m2: Dictionary = sim.state["agents"].get(int(aid), {})
				var p3 := {"kind": "repair", "b": bid, "agents": [int(aid)]}
				var c2: Dictionary = sim.orders.check(m2, p3)
				if bool(c2["ok"]):
					sim.orders._give(m2, p3)
					acc2.append(int(aid))
				else:
					ref2[int(aid)] = c2
			return {"ok": not acc2.is_empty(), "code": "ok" if not acc2.is_empty() else "no_work", "text": "", "accepted": acc2, "refused": ref2}
		return {"ok": false, "code": "no_task", "text": sim.orders.text_of("no_task")}
	var acc3: Array = []
	var ref3 := {}
	for aid in ids:
		var m3: Dictionary = sim.state["agents"].get(int(aid), {})
		var p4 := {"kind": "task", "tid": tid, "agents": [int(aid)]}
		# Another colonist who has only started to walk to it gives it up.
		var owner: int = int(t["owner"])
		if owner != -1 and owner != int(aid) and not bool(t["picked"]):
			var other: Dictionary = sim.state["agents"].get(owner, {})
			if not other.is_empty():
				sim.agents.abort_plan(other, "reassigned")
		var c3: Dictionary = sim.orders.check(m3, p4)
		if bool(c3["ok"]):
			sim.orders._give(m3, p4)
			acc3.append(int(aid))
		else:
			ref3[int(aid)] = c3
		break      # one task: one colonist
	return {"ok": not acc3.is_empty(), "code": "ok" if not acc3.is_empty() else "no_task", "text": "", "accepted": acc3, "refused": ref3}

func cmd_cancel_order(a: Dictionary) -> void:
	if a.has("order"):
		if a["plan_kind"] == "task" and int(a["task"]) != -1 and int(a["task"]) == int(a["order"].get("tid", -2)):
			sim.agents.abort_plan(a, "order_cleared")
		order_ended(a, true)
		a.erase("order")

## "workq_cancel" {key}: a task is held (not offered to anybody) for ten minutes; a team order or a standing order
## ends. "workq_release" {key} lifts the hold.
func cmd_cancel(p: Dictionary) -> Dictionary:
	var key: String = String(p.get("key", ""))
	var w: Dictionary = _w()
	if key.begins_with("team:"):
		var team: Dictionary = w["teams"].get(int(key.substr(5)), {})
		if team.is_empty():
			return {"ok": false, "code": "no_task", "text": sim.orders.text_of("no_task")}
		for aid in team["assignees"].duplicate():
			var m: Dictionary = sim.state["agents"].get(int(aid), {})
			if not m.is_empty():
				cmd_cancel_order(m)
		w["teams"].erase(int(team["id"]))
		return {"ok": true, "code": "ok", "text": ""}
	if key.begins_with("standing:"):
		var sk: String = key.substr(9)
		var e: Dictionary = w["standing"].get(sk, {})
		if e.is_empty():
			return {"ok": false, "code": "no_task", "text": sim.orders.text_of("no_task")}
		var sa: Dictionary = sim.state["agents"].get(int(e["agent"]), {})
		if not sa.is_empty() and sa.has("order") and bool(sa["order"].get("standing", false)):
			cmd_cancel_order(sa)
		w["standing"].erase(sk)
		return {"ok": true, "code": "ok", "text": ""}
	var found := false
	for tid in sim.state["tasks"].keys():
		var t: Dictionary = sim.state["tasks"][tid]
		if key_of(t) != key:
			continue
		found = true
		var owner: int = int(t["owner"])
		if owner != -1:
			var oa: Dictionary = sim.state["agents"].get(owner, {})
			if not oa.is_empty():
				if oa.has("order") and int(oa["order"].get("tid", -2)) == int(tid):
					cmd_cancel_order(oa)
				else:
					sim.agents.abort_plan(oa, "cancelled")
	if not found and not key.begins_with("repair:"):
		return {"ok": false, "code": "no_task", "text": sim.orders.text_of("no_task")}
	w["hold"][key] = int(sim.state["tick"]) + 600 * int(sim.bal["tick_hz"])
	_dirty = true
	return {"ok": true, "code": "ok", "text": ""}

func cmd_release(p: Dictionary) -> Dictionary:
	var w: Dictionary = _w()
	w["hold"].erase(String(p.get("key", "")))
	_dirty = true
	return {"ok": true, "code": "ok", "text": ""}

## What the interface shows in the dock and the Work window: counts and the last team reports.
func summary() -> Dictionary:
	var w: Dictionary = _w()
	var by := {}
	for d in DEPTS:
		by[d] = 0
	for r in rows(""):
		by[r["dept"]] = int(by.get(r["dept"], 0)) + 1
	return {"urgent": urgent_count(), "by_dept": by, "teams": w["teams"].size(), "standing": w["standing"].size(), "reports": (w["reports"] as Array).duplicate(true)}
