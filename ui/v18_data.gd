extends RefCounted
## Version-5 section 18 data (Paul, 2026-10-04): orders that are obeyed, the chain of command, work queues, missing-capability
## chains and package transport, behind ONE adapter. SIM's modules: sim.orders (the order kinds repair, maintain, build, haul, task;
## check, repair_need), sim.workq (rows, summary, urgent_count; commands workq_move, workq_assign, workq_cancel, workq_release),
## sim.chains (chain_for, all_chains; the alerts "chain:<item>" and the chain on "materials:<item>"), sim.transport (overview, info,
## capsules_view, position_of; command install_transport; alert transport:<corridor>) for the package transport (18.5).

## Nothing here writes to sim.state; commands go through main.submit.

const P = preload("res://ui/theme/palette.gd")

var hud

func _init(h) -> void:
	hud = h

func _sim():
	return hud.main.sim

func _obj(name: String):
	var s = _sim()
	return s.get(name) if s != null else null

## True when SIM has the system ("work", "chains", "transport").
func live(system: String) -> bool:
	match system:
		"work":
			var w = _obj("workq")
			return w != null and (w as Object).has_method("rows")
		"chains":
			var c = _obj("chains")
			return c != null and (c as Object).has_method("chain_for")
		"transport":
			var t = _obj("transport")
			return t != null and (t as Object).has_method("overview")
	return false

## The result of a command at once (the game is paused) or "submitted": {ok, code, cid, result}.
func submit(kind: String, payload: Dictionary) -> Dictionary:
	return hud.v4._submit(kind, payload)

# ---------------------------------------------------------------- repair orders and the chain of command (18.1, 18.2)
## What a structure needs now (SIM orders.repair_need): "repair", "patch", "clean", "maintain" or "".
func repair_need(b: Dictionary) -> String:
	return String(_sim().orders.repair_need(b))

## {state: "broken" | "worn" | "", wear, fail_at, need}. WORN: wear at the sim risk fraction of the failure point (hazards.risk_frac), or health under the repair
## trigger; BROKEN: state broken. `need` is SIM's repair_need ("" = nothing to do, no Repair now button).
func wear_state(b: Dictionary) -> Dictionary:
	if String(b.get("kind", "")) == "link" or String(b.get("kind", "")) == "special":
		return {"state": "", "wear": 0.0, "fail_at": 100.0, "need": ""}
	var need: String = repair_need(b) if String(b.get("state", "")) in ["active", "broken"] else ""
	if String(b.get("state", "")) == "broken":
		return {"state": "broken", "wear": 100.0, "fail_at": 100.0, "need": need}
	var w: Dictionary = hud.data.wear_of(b)
	var wear := 0.0
	var fa := 100.0
	var worn := false
	if bool(w.get("known", false)):
		wear = float(w.get("wear", 0.0))
		fa = maxf(1.0, float(w.get("fail_at", 100.0)))
		worn = wear >= float(_sim().hazards.risk_frac()) * fa   # the sim threshold (research can move it)
	if float(b.get("health", 100.0)) < float(_sim().bal.get("repair_trigger_health", 70.0)) or bool(b.get("breach", false)):
		worn = true
	return {"state": "worn" if worn and need != "" else "", "wear": wear, "fail_at": fa, "need": need}

## Heads that can take a team order for a structure (a Base Commander or a Captain of its base):
## [{id, name, dept, dept_name, title, size}]. size = the people the head can give the work to.
func heads(bid: int) -> Array:
	var s = _sim()
	var out: Array = []
	var b: Dictionary = s.state["buildings"].get(bid, {})
	var many: bool = s.bases.count() > 1
	var base: int = s.bases.base_at(b["pos"]) if (not b.is_empty() and many) else -1
	var deps: Dictionary = s.content["people"]["departments"]
	var ids: Array = s.state["agents"].keys()
	ids.sort()
	for aid in ids:
		var a: Dictionary = s.state["agents"][aid]
		if not s.workq.is_head(a):
			continue
		if many and base != -1 and s.bases.base_of_agent(a) != base:
			continue
		var rk: Dictionary = s.people.rank(a)
		var dep: String = s.people.department(a) if String(rk.get("rank", "")) == "captain" else "command"
		var n := 0
		for oid in ids:
			var m: Dictionary = s.state["agents"][oid]
			if int(oid) == int(aid) or m["state"] != "alive" or m["kind"] == "visitor" or m["kind"] == "child":
				continue
			if many and s.bases.base_of_agent(m) != s.bases.base_of_agent(a):
				continue
			if dep != "command" and s.people.department(m) != dep:
				continue
			n += 1
		out.append({"id": int(aid), "name": String(a["name"]), "dept": dep, "dept_name": "All departments" if dep == "command" else String(deps.get(dep, {}).get("name", dep.capitalize())),
			"title": String(rk.get("title", "Head")), "size": n})
	out.sort_custom(func(x, y):
		if (String(x["dept"]) == "command") != (String(y["dept"]) == "command"):
			return String(x["dept"]) == "command"
		return String(x["dept_name"]) < String(y["dept_name"]))
	return out

## Colonists that can take an order for a structure, the maintenance department first, then by distance:
## [{id, name, role, role_name, dist, goal, dept, order}] (at most `limit`). Heads are in the other list.
func candidates(bid: int, limit: int = 40, skip_heads: bool = false) -> Array:
	var s = _sim()
	var b: Dictionary = s.state["buildings"].get(bid, {})
	var pos: Vector2 = b.get("pos", Vector2.ZERO)
	var rows: Array = []
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		if a["state"] != "alive" or hud.data.is_visitor(a) or String(a.get("kind", "colonist")) == "child":
			continue
		if skip_heads and s.workq.is_head(a):
			continue
		var role: String = String(a.get("role", ""))
		rows.append({"id": int(aid), "name": String(a["name"]), "role": role, "role_name": String(s.bal["role_names"].get(role, role)),
			"dist": (a["pos"] as Vector2).distance_to(pos), "goal": String(a.get("goal", "")), "dept": s.people.department(a), "order": a.has("order")})
	rows.sort_custom(func(x, y):
		var mx: bool = String(x["dept"]) == "maintenance"
		var my: bool = String(y["dept"]) == "maintenance"
		if mx != my:
			return mx
		return float(x["dist"]) < float(y["dist"]))
	return rows.slice(0, limit)

## An order to one colonist or, when `aid` is a head of a department, a team order (SIM allocates it).
## kind: "repair" (fix it now) or "maintain" (a standing order: keep it in repair). Returns {ok, code, text, assigned, team}.
func repair_order(aid: int, bid: int, standing: bool = false) -> Dictionary:
	var s = _sim()
	var a: Dictionary = s.state["agents"].get(aid, {})
	var b: Dictionary = s.state["buildings"].get(bid, {})
	if a.is_empty() or b.is_empty():
		return {"ok": false, "code": "unknown", "text": "That structure or colonist is gone.", "assigned": []}
	var kind: String = "maintain" if standing else "repair"
	var p := {"agents": [aid], "kind": kind, "b": bid}
	if not s.workq.is_head(a):
		var chk: Dictionary = s.orders.check(a, p)
		if not bool(chk.get("ok", false)):
			return {"ok": false, "code": String(chk.get("code", "")), "text": String(chk.get("text", "")), "assigned": []}
	var r: Dictionary = submit("order", p)
	var res: Dictionary = r.get("result", {})
	if r.get("code", "") == "submitted":
		# The game runs: the command waits for the next tick. The colonist's own name says what was sent.
		return {"ok": true, "code": "submitted", "text": "%s: order sent." % String(a["name"]).get_slice(" ", 0), "assigned": [aid]}
	if not bool(res.get("ok", r.get("ok", false))):
		var code: String = String(res.get("code", r.get("code", "")))
		return {"ok": false, "code": code, "text": String(res.get("text", s.orders.text_of(code))), "assigned": []}
	var acc: Array = res.get("assigned", res.get("accepted", [aid]))
	var text: String = String(res.get("report", ""))
	if text == "":
		text = "%s %s %s." % [String(a["name"]).get_slice(" ", 0), "keeps" if standing else "repairs", String(b["name"]) + (" in repair" if standing else "")]
	return {"ok": true, "code": "ok", "text": text, "assigned": acc, "team": int(res.get("team", -1))}

## The standing or one-off order of a colonist for the personnel file and the follow card:
## {has, kind, name, target, text, blocked, missing {item, qty} or {}, team, head (agent id or -1), standing}.
func order_info(aid: int) -> Dictionary:
	var s = _sim()
	var a: Dictionary = s.state["agents"].get(aid, {})
	var o = a.get("order", null)
	if a.is_empty() or typeof(o) != TYPE_DICTIONARY:
		return {"has": false}
	var kind: String = String(o.get("kind", ""))
	var bid: int = int(o.get("b", -1))
	var tname: String = String(s.state["buildings"].get(bid, {}).get("name", "")) if bid >= 0 else ""
	var names := {"go": "Go to a place", "stay": "Stay", "return": "Return to base", "board": "Board a vehicle", "work_at": "Work at", "survey": "Survey",
		"repair": "Repair", "maintain": "Keep in repair", "build": "Help build", "haul": "Haul", "task": "Do assigned work"}
	var miss = o.get("missing", {})
	var tm: int = int(o.get("team", -1))
	return {"has": true, "kind": kind, "name": String(names.get(kind, kind.capitalize())), "target": tname, "text": String(o.get("text", "")),
		"blocked": String(o.get("blocked", "")), "missing": miss if typeof(miss) == TYPE_DICTIONARY else {}, "team": tm, "head": team_head(tm), "standing": bool(o.get("standing", false))}

## The head who gave team order `team` (-1 when it is not a team order).
func team_head(team: int) -> int:
	if team < 0 or not live("work"):
		return -1
	for r in _sim().workq.rows("maintenance"):
		if int(r["team"]) == team:
			return int(r["assignee"])
	return -1

# ---------------------------------------------------------------- the work queue (18.3)
const TYPE_NAME := {"build": "Build", "repair": "Repair", "maintain": "Maintain", "haul": "Haul", "produce": "Produce", "research": "Research", "security": "Security", "medical": "Medical"}
const TYPE_ICON := {"build": "build", "repair": "wrench", "maintain": "wrench", "haul": "cat_logistics", "produce": "cat_industry", "research": "research", "security": "lock", "medical": "cat_medical"}

## [[key, name], ...]: All and the departments of SIM's queues.
func work_depts() -> Array:
	var out: Array = [["all", "All"]]
	var w = _sim().workq
	for d in w.DEPTS:
		out.append([String(d), String(w.DEPT_NAMES.get(d, String(d).capitalize()))])
	return out

## The rows of a department ("all" = every department) in queue order (SIM workq.rows) plus `icon`.
func work_items(dept: String) -> Array:
	var rows: Array = _sim().workq.rows("" if dept == "all" else dept)
	for r in rows:
		r["icon"] = String(TYPE_ICON.get(String(r.get("type", "")), "orders"))
	return rows

## Urgent rows nobody has: the dock count.
func urgent_unassigned() -> int:
	return int(_sim().workq.urgent_count())

func summary() -> Dictionary:
	return _sim().workq.summary()

## Moves a row: how = top | up | down | bottom (the row's department).
func work_move(row: Dictionary, how: String) -> Dictionary:
	var r: Dictionary = submit("workq_move", {"key": String(row["key"]), "dept": String(row["dept"]), "how": how})
	return _answer(r)

## Drag and drop: the row `key` goes before the row `before` (both in `rows`, the order shown now). SIM moves a row one place
## or to an end, so a drag is a few moves.
func work_drop(rows: Array, key: String, before: String) -> Dictionary:
	var keys: Array = []
	var dept := ""
	var di := -1
	var bi := -1
	for i in rows.size():
		keys.append(String(rows[i]["key"]))
		if String(rows[i]["key"]) == key:
			di = i
			dept = String(rows[i]["dept"])
		if String(rows[i]["key"]) == before:
			bi = i
	if di < 0 or bi < 0 or di == bi - 1 or di == bi:
		return {"ok": true, "code": "ok", "text": ""}
	if String(rows[bi]["dept"]) != dept:
		return {"ok": false, "code": "dept", "text": "Drop it on a row of the same department."}
	var steps: int = (di - bi) if bi < di else (bi - di - 1)
	var how: String = "up" if bi < di else "down"
	var last: Dictionary = {"ok": true, "code": "ok", "text": ""}
	for i in steps:
		last = work_move(rows[di], how)
		if not bool(last["ok"]):
			break
	return last

## Assign a row to colonists. A task row: one colonist gets a task order. A team row (state "team"): the team is these colonists.
func work_assign(row: Dictionary, agents: Array) -> Dictionary:
	var p := {"key": String(row["key"]), "agents": agents}
	if int(row.get("id", -1)) != -1:
		p["tid"] = int(row["id"])
	var r: Dictionary = submit("workq_assign", p)
	var res: Dictionary = r.get("result", {})
	var a: Array = res.get("accepted", [])
	if r.get("code", "") == "submitted":
		return {"ok": true, "code": "submitted", "text": "Order sent."}
	if not bool(res.get("ok", r.get("ok", false))):
		var code: String = String(res.get("code", r.get("code", "")))
		var why: String = ""
		for id in res.get("refused", {}):
			why = String(res["refused"][id].get("text", ""))
			break
		return {"ok": false, "code": code, "text": why if why != "" else String(res.get("text", _sim().orders.text_of(code)))}
	var names: Array = []
	for id in a:
		names.append(String(_sim().state["agents"].get(int(id), {}).get("name", "")).get_slice(" ", 0))
	return {"ok": true, "code": "ok", "text": "%s takes: %s." % [" and ".join(names), String(row["text"])]}

func work_cancel(row: Dictionary) -> Dictionary:
	return _answer(submit("workq_cancel", {"key": String(row["key"])}))

func work_release(row: Dictionary) -> Dictionary:
	return _answer(submit("workq_release", {"key": String(row["key"])}))

func _answer(r: Dictionary) -> Dictionary:
	var res: Dictionary = r.get("result", {})
	if r.get("code", "") == "submitted":
		return {"ok": true, "code": "submitted", "text": ""}
	var ok: bool = bool(res.get("ok", r.get("ok", false)))
	return {"ok": ok, "code": String(res.get("code", r.get("code", ""))), "text": String(res.get("text", ""))}

# ---------------------------------------------------------------- production chains (18.4)
## The item of an alert issue, "" when it is not about a missing item. SIM's alerts "chain:<item>" carry `item`;
## "materials:<item>" carries `chain`.
func issue_item(issue: Dictionary) -> String:
	if String(issue.get("item", "")) != "":
		return String(issue["item"])
	var key: String = String(issue.get("key", ""))
	if key.begins_with("materials:") or key.begins_with("chain:"):
		return key.get_slice(":", 1)
	return ""

## SIM's chain of an item, made ready for the diagram (ui/widgets/chain_view.gd): {item, name, ok, text, steps}. Each step of SIM
## (a structure that makes an item) shows as two cards: the structure, then the item it makes.
## Display step: {kind ("building" | "item"), id, name, state (SIM status: done, missing, building, broken, unpowered, no_worker,
## needs_research), text, def, tech, can_place, depth}.
func chain_of(item: String) -> Dictionary:
	return normalize(_sim().chains.chain_for(item))

func all_chains() -> Array:
	var out: Array = []
	for c in _sim().chains.all_chains():
		out.append(c)
	return out

func normalize(c: Dictionary) -> Dictionary:
	var s = _sim()
	var raw: Array = c.get("steps", [])
	var depth := {}
	if not raw.is_empty():
		depth[String(raw[raw.size() - 1]["item"])] = 0
		for i in range(raw.size() - 1, -1, -1):
			var st: Dictionary = raw[i]
			var d: int = int(depth.get(String(st["item"]), 0))
			for inp in st.get("inputs", []):
				depth[String(inp)] = maxi(int(depth.get(String(inp), 0)), d + 1)
	var tot: Dictionary = s.inv.totals()
	var steps: Array = []
	for st in raw:
		var d2: int = int(depth.get(String(st["item"]), 0))
		var have: int = int(tot.get(String(st["item"]), {}).get("total", 0))
		if String(st.get("building", "")) != "":
			steps.append({"kind": "building", "id": String(st["building"]), "name": String(st["building_name"]), "state": String(st["status"]), "text": String(st["text"]),
				"def": String(st["building"]), "tech": String(st.get("tech", "")), "tech_name": String(st.get("tech_name", "")), "can_place": bool(st.get("place", false)), "depth": d2})
		steps.append({"kind": "item", "id": String(st["item"]), "name": String(st["item_name"]),
			"state": "done" if have > 0 or (String(st["status"]) == "done" and String(st.get("building", "")) != "") else ("missing" if String(st.get("building", "")) == "" and have == 0 else String(st["status"])),
			"text": ("%d in storage." % have) if have > 0 else ("None in storage." if String(st.get("building", "")) != "" else String(st["text"])),
			"def": "", "tech": "", "tech_name": "", "can_place": false, "depth": d2})
	return {"item": String(c.get("item", "")), "name": String(c.get("name", "")), "ok": bool(c.get("ok", false)), "text": String(c.get("text", "")), "steps": steps}

# ---------------------------------------------------------------- package transport (18.5)
## SIM's sim.transport (sim/transport.gd). overview(): {enabled, hubs [{id, name, pos, ok, to, from, net}], tubes [{id, a, b, p0, p1, length, ok, busy_s}],
## networks, capsules, stuck, moved, flow {item: units in 5 minutes}, delivered}. info(id): {hub, tube, check, ok, in_transit [{res, qty, dir, eta_s, stuck}]}.
func transport_live() -> bool:
	return live("transport")

func transport() -> Dictionary:
	if transport_live():
		return _sim().transport.overview()
	return {"enabled": false, "hubs": [], "tubes": [], "networks": [], "capsules": 0, "stuck": 0, "moved": {}, "flow": {}, "delivered": 0}

## Capsules in flight with their position now: [{res, qty, pos (Vector2), in_tube, stuck}].
func capsules() -> Array:
	var out: Array = []
	if not transport_live():
		return out
	var tick: int = int(_sim().state["tick"])
	for c in _sim().transport.capsules_view():
		var p: Dictionary = _sim().transport.position_of(c, tick)
		out.append({"res": String(c["res"]), "qty": int(c["qty"]), "pos": p["pos"], "in_tube": bool(p["in_tube"]), "stuck": bool(c["stuck"])})
	return out

func transport_info(bid: int) -> Dictionary:
	return _sim().transport.info(bid) if transport_live() else {"hub": false, "tube": false, "ok": true, "in_transit": [], "check": {}}

func is_hub(bid: int) -> bool:
	return bool(_sim().state["buildings"].get(bid, {}).get("hub", false))

func is_tube(bid: int) -> bool:
	return bool(_sim().state["buildings"].get(bid, {}).get("tube", false))

# ---------------------------------------------------------------- what is on a structure, and stock (the pending state)
## Who has work on a structure now: [{agent, name, via ("order" | "task"), kind, text, state ("going" | "working" | "waiting")}].
## From the colonists' orders (sim.orders) and the owned tasks of the job board. A part that is missing says so in the text.
func work_on(bid: int) -> Array:
	var s = _sim()
	var out: Array = []
	var seen := {}
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		var o = a.get("order", null)
		if typeof(o) != TYPE_DICTIONARY or int(o.get("b", -1)) != bid or a["state"] != "alive":
			continue
		seen[int(aid)] = true
		var blocked: String = String(o.get("blocked", ""))
		var miss: Dictionary = o.get("missing", {}) if typeof(o.get("missing", {})) == TYPE_DICTIONARY else {}
		var st := "going"
		if blocked != "":
			st = "waiting"
		elif int(o.get("tid", -1)) != -1 and String(a.get("plan_kind", "")) in ["task", "repair", "maintain", "work"]:
			st = "working"
		var text: String = String(o.get("text", ""))
		if not miss.is_empty():
			text = "Waiting for %s." % hud.data.item_name(String(miss.get("item", ""))).to_lower()
		out.append({"agent": int(aid), "name": String(a["name"]), "via": "order", "kind": String(o.get("kind", "")), "text": text, "state": st})
	for tid in s.state["tasks"]:
		var t: Dictionary = s.state["tasks"][tid]
		if int(t.get("bld", -1)) != bid or int(t.get("owner", -1)) == -1 or seen.has(int(t["owner"])):
			continue
		if not (String(t["kind"]) in ["repair", "maintain", "patch", "clean"]):
			continue
		var ow: Dictionary = s.state["agents"].get(int(t["owner"]), {})
		if ow.is_empty():
			continue
		out.append({"agent": int(t["owner"]), "name": String(ow["name"]), "via": "task", "kind": String(t["kind"]), "text": String(ow.get("goal", "")),
			"state": "working" if String(t.get("state", "")) == "working" else "going"})
	return out

## Stock of an item as a repair at structure `bid` sees it: {total, free (not reserved, not carried), reserved, carried, reachable}.
## reachable: a free unit that a colonist can walk to (SIM jobs.find_source from the structure).
func stock(item: String, bid: int) -> Dictionary:
	var s = _sim()
	var row: Dictionary = s.inv.totals().get(item, {})
	var total: int = int(row.get("total", 0))
	var reserved: int = int(row.get("reserved", 0))
	var carried: int = int(row.get("carried", 0))
	var free: int = maxi(0, total - reserved - carried)
	var b: Dictionary = s.state["buildings"].get(bid, {})
	var reach: bool = free > 0 and not b.is_empty() and int(s.jobs.find_source(item, b["pos"])) != -1
	return {"total": total, "free": free, "reserved": reserved, "carried": carried, "reachable": reach}

## The rows of the dashboard card Maintenance: SIM's machines near failure (hazards.at_risk) and every broken machine
## ({id, wear, fail_at, eta_s, fault, broken}).
func maintenance_rows() -> Array:
	var s = _sim()
	var rows: Array = []
	var seen := {}
	for r in hud.data.at_risk():
		var rr: Dictionary = r.duplicate()
		rr["broken"] = false
		rows.append(rr)
		seen[int(r.get("id", -1))] = true
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		if String(b["state"]) != "broken" or seen.has(int(id)) or String(b["kind"]) == "link":
			continue
		var w: Dictionary = hud.data.wear_of(b)
		rows.append({"id": int(id), "wear": 100.0, "fail_at": 100.0, "eta_s": 0.0, "fault": String(w.get("fault", b.get("fault", ""))), "broken": true})
	rows.sort_custom(func(x, y):
		if bool(x["broken"]) != bool(y["broken"]):
			return bool(x["broken"])
		return float(x.get("eta_s", 1e9)) < float(y.get("eta_s", 1e9)))
	return rows
