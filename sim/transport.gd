extends RefCounted
## Package transport (docs/V5_DESIGN.md section 18.5, end game).
##
## Research "Package Transport" (log_transport) unlocks two upgrades, made like the level upgrades (materials are
## carried to the structure, technicians work, upgrades.gd): a TRANSPORT HUB on a storage structure (a storehouse or
## cold storage: building.hub = true) and a TRANSPORT TUBE on a corridor (corridor.tube = true).
##
## ROUTING: a haul between two inventories of structures that both have a hub, or stand next to one (joined to a hub by
## a corridor with a tube), and that are joined by a path of working tubes, is not a task for a colonist: jobs._make_haul
## asks divert(task). The goods leave the store at once into a capsule (they stay in the ledger: the colony's transit
## inventory), fly through the tubes at capsule_speed, queue for the capacity of each tube (tube_units_per_s), and arrive
## at the destination, which reserved the room for them. A haul that would wait longer than max_wait_s for a tube is left to
## the colonists. A tube that is broken (the corridor is broken or has a breach) is not used; goods in flight wait where
## they are until it works again, and an alert says so.
##
## state.v5.transport = {any (a hub or a tube was ever built), inv (the transit inventory), capsules {id: capsule},
##   moved {item: units delivered}, recent [{t, res, qty, src, dst}], delivered (count)}
## capsule = {id, res, qty, src (structure id), dst (structure id), path [corridor ids], segs [{cid, p0, p1, t0, t1}],
##   t0 (tick it left), t1 (tick it arrives), hold_in (the destination's reserved room), stuck (bool)}
## building fields: hub (bool), tube (bool), tube_free (tick the tube can take the next capsule).
##
## Read: overview(), capsules_view(), info(structure id). Command: install_transport {id}.

var sim
var _stamp := -1
var _adj := {}       # structure id -> [[other id, corridor id]] over working tubes
var _hubs := {}      # structure id -> true (active hubs)
var _comp := {}      # structure id -> network id (a node of a working tube path that holds a hub)
var _near := {}      # structure id -> true (a hub, or joined to a hub by a working tube)
var _down: Array = []     # corridor ids of tubes that do not work
var _hub_defs: Array = []

func _init(s) -> void:
	sim = s

func reset() -> void:
	_stamp = -1
	_adj = {}
	_hubs = {}
	_comp = {}
	_near = {}
	_down = []

func cfg() -> Dictionary:
	return sim.bal["transport"]

func _w() -> Dictionary:
	var v: Dictionary = sim.people.v5w()
	if not v.has("transport"):
		v["transport"] = {"any": false, "inv": -1, "capsules": {}, "moved": {}, "recent": [], "delivered": 0}
	return v["transport"]

func _have() -> bool:
	return sim.state.has("v5") and (sim.state["v5"] as Dictionary).has("transport")

func any() -> bool:
	return _have() and bool(_w()["any"])

func hub_defs() -> Array:
	return cfg().get("hub_defs", ["storehouse", "cold_storage"])

# ---------------------------------------------------------------- the upgrades
## Called when an upgrade of a feature is finished (upgrades.gd).
func installed(b: Dictionary) -> void:
	_w()["any"] = true
	_stamp = -1

## {ok, code, feature, cost, research, work}. code: ok | unknown | locked_research | not_storage | not_corridor | have | not_active | busy | demolish.
func check(b: Dictionary) -> Dictionary:
	var res := {"ok": false, "code": "unknown", "feature": "", "cost": {}, "research": "log_transport", "work": 0.0}
	if b.is_empty() or not sim.state["buildings"].has(b.get("id", -1)):
		return res
	if b["kind"] == "link":
		res["feature"] = "tube"
		if b["def"] != "corridor":
			res["code"] = "not_corridor"
			return res
	else:
		res["feature"] = "hub"
		if not hub_defs().has(String(b["def"])):
			res["code"] = "not_storage"
			return res
	res["cost"] = cost_for(b, String(res["feature"]))
	res["work"] = work_for(b, String(res["feature"]))
	if bool(b.get("hub", false)) or bool(b.get("tube", false)):
		res["code"] = "have"
		return res
	if b["state"] != "active":
		res["code"] = "not_active"
		return res
	if bool(b.get("demolish", false)):
		res["code"] = "demolish"
		return res
	if not (b.get("upgrade", {}) as Dictionary).is_empty():
		res["code"] = "busy"
		return res
	if not sim.research.is_done("log_transport") and not sim.unlocked_all():
		res["code"] = "locked_research"
		return res
	res["ok"] = true
	res["code"] = "ok"
	return res

func cost_for(b: Dictionary, feature: String) -> Dictionary:
	var c: Dictionary = cfg()
	var out := {}
	if feature == "hub":
		for r in c["hub_cost"]:
			out[r] = int(c["hub_cost"][r])
		return out
	var tens: int = int(ceil(float(b.get("length", 10.0)) / 10.0))
	for r in c["tube_cost_base"]:
		out[r] = int(c["tube_cost_base"][r])
	for r in c["tube_cost_per_10m"]:
		out[r] = int(out.get(r, 0)) + int(c["tube_cost_per_10m"][r]) * tens
	return out

func work_for(b: Dictionary, feature: String) -> float:
	var c: Dictionary = cfg()
	if feature == "hub":
		return float(c["hub_work"])
	return float(c["tube_work"]) * maxf(1.0, float(b.get("length", 10.0)) / 10.0)

## Command "install_transport" {id}: orders the hub or the tube upgrade.
func cmd_install(p: Dictionary) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(int(p.get("id", -1)), {})
	var chk: Dictionary = check(b)
	if not bool(chk["ok"]):
		return {"ok": false, "code": chk["code"], "feature": chk["feature"], "cost": chk["cost"]}
	return sim.upgrades.start_feature(b, String(chk["feature"]), chk["cost"], float(chk["work"]))

# ---------------------------------------------------------------- the network
func _ensure() -> void:
	var sec: int = int(sim.state["tick"]) / int(sim.bal["tick_hz"])
	if sec == _stamp:
		return
	_stamp = sec
	_rebuild()

func _rebuild() -> void:
	_adj = {}
	_hubs = {}
	_comp = {}
	_near = {}
	_down = []
	var blds: Dictionary = sim.state["buildings"]
	var all_adj := {}
	for id in blds:
		var b: Dictionary = blds[id]
		if bool(b.get("hub", false)) and b["state"] == "active":
			_hubs[int(id)] = true
		if b["kind"] != "link" or not bool(b.get("tube", false)):
			continue
		var a: int = int(b["a"])
		var z: int = int(b["b"])
		var up: bool = b["state"] == "active" and not bool(b.get("breach", false)) and blds.has(a) and blds.has(z) and blds[a]["state"] == "active" and blds[z]["state"] == "active"
		if not up:
			_down.append(int(id))
			continue
		if not _adj.has(a):
			_adj[a] = []
		if not _adj.has(z):
			_adj[z] = []
		_adj[a].append([z, int(id)])
		_adj[z].append([a, int(id)])
	var ids: Array = _hubs.keys()
	ids.sort()
	var net := 0
	for h in ids:
		if _comp.has(h):
			continue
		net += 1
		var stack: Array = [h]
		_comp[h] = net
		while not stack.is_empty():
			var x: int = stack.pop_back()
			for e in _adj.get(x, []):
				if not _comp.has(int(e[0])):
					_comp[int(e[0])] = net
					stack.append(int(e[0]))
	for h in ids:
		_near[h] = true
		for e in _adj.get(h, []):
			_near[int(e[0])] = true

## The shortest path of working tubes between two structures: {nodes [ids], edges [corridor ids], length} or {}.
func _route(from: int, to: int) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	var dist := {from: 0.0}
	var prev := {}
	var todo: Array = [from]
	var done := {}
	while not todo.is_empty():
		var best_i := 0
		for i in todo.size():
			if float(dist[todo[i]]) < float(dist[todo[best_i]]) or (float(dist[todo[i]]) == float(dist[todo[best_i]]) and int(todo[i]) < int(todo[best_i])):
				best_i = i
		var x: int = todo[best_i]
		todo.remove_at(best_i)
		if done.has(x):
			continue
		done[x] = true
		if x == to:
			break
		for e in _adj.get(x, []):
			var y: int = int(e[0])
			var len: float = float(blds[int(e[1])].get("length", 10.0))
			var nd: float = float(dist[x]) + len
			if not dist.has(y) or nd < float(dist[y]) - 0.0001:
				dist[y] = nd
				prev[y] = [x, int(e[1])]
				todo.append(y)
	if not dist.has(to):
		return {}
	var nodes: Array = [to]
	var edges: Array = []
	var cur: int = to
	while cur != from:
		var pe: Array = prev[cur]
		edges.push_front(int(pe[1]))
		cur = int(pe[0])
		nodes.push_front(cur)
	return {"nodes": nodes, "edges": edges, "length": float(dist[to])}

# ---------------------------------------------------------------- routing a haul
## jobs._make_haul made a haul task with both holds: when the goods can go by tube, the task is dropped and a
## capsule carries them. Returns true when the haul was taken over.
func divert(t: Dictionary) -> bool:
	if not any():
		return false
	_ensure()
	if _hubs.is_empty():
		return false
	var invs: Dictionary = sim.state["inventories"]
	var si: Dictionary = invs.get(int(t["src"]), {})
	var di: Dictionary = invs.get(int(t["dst"]), {})
	if si.is_empty() or di.is_empty() or si["ot"] != "b" or di["ot"] != "b":
		return false
	var sb: int = int(si["oid"])
	var db: int = int(di["oid"])
	if sb == db or not _near.has(sb) or not _near.has(db):
		return false
	if int(_comp.get(sb, -1)) == -1 or int(_comp.get(sb, -1)) != int(_comp.get(db, -2)):
		return false
	var qty: int = int(t["qty"])
	if qty > int(cfg()["capsule_units"]):
		return false
	var route: Dictionary = _route(sb, db)
	if route.is_empty():
		return false
	var blds: Dictionary = sim.state["buildings"]
	var hz: int = int(sim.bal["tick_hz"])
	var now: int = int(sim.state["tick"])
	var speed: float = float(cfg()["capsule_speed"])
	var hub_t: int = int(round(float(cfg()["hub_seconds"]) * float(hz)))
	var hold_t: int = int(ceil(float(qty) / float(cfg()["tube_units_per_s"]) * float(hz)))
	var max_wait: int = int(float(cfg()["max_wait_s"]) * float(hz))
	# Plan the flight: each tube in turn, after the tube before, and after the capsules already in it.
	var cur: int = now + hub_t
	var segs: Array = []
	var frees := {}
	var node: int = sb
	for cid in route["edges"]:
		var c: Dictionary = blds[int(cid)]
		var start: int = maxi(cur, int(c.get("tube_free", 0)))
		if start - now > max_wait:
			return false
		var fwd: bool = int(c["a"]) == node
		var p0: Vector2 = c["p0"] if fwd else c["p1"]
		var p1: Vector2 = c["p1"] if fwd else c["p0"]
		var fly: int = maxi(1, int(round(float(c.get("length", 10.0)) / speed * float(hz))))
		segs.append({"cid": int(cid), "p0": p0, "p1": p1, "t0": start, "t1": start + fly})
		frees[int(cid)] = start + hold_t
		cur = start + fly
		node = int(c["b"]) if fwd else int(c["a"])
	var arrive: int = cur + hub_t
	# Commit: the goods leave the store now.
	var w: Dictionary = _w()
	if int(w["inv"]) == -1 or not sim.inv.exists(int(w["inv"])):
		w["inv"] = sim.inv.create_inv("t", 0, "transit", 100000000)
	if not sim.inv.take_held(int(t["hold_out"]), int(w["inv"])):
		return false
	for cid in frees:
		blds[int(cid)]["tube_free"] = int(frees[cid])
	var id: int = sim.new_id()
	w["capsules"][id] = {"id": id, "res": String(t["res"]), "qty": qty, "src": sb, "dst": db, "path": (route["edges"] as Array).duplicate(),
		"segs": segs, "t0": now, "t1": arrive, "hold_in": int(t["hold_in"]), "stuck": false}
	t["hold_out"] = -1
	t["hold_in"] = -1
	sim.state["tasks"].erase(int(t["id"]))
	return true

# ---------------------------------------------------------------- every second
func tick_second() -> void:
	if not any():
		return
	_ensure()
	_demo_feed()
	var w: Dictionary = _w()
	var caps: Dictionary = w["capsules"]
	if caps.is_empty():
		return
	var now: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var blds: Dictionary = sim.state["buildings"]
	var ids: Array = caps.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = caps[id]
		if int(c["t1"]) > now:
			continue
		var ok := true
		for cid in c["path"]:
			if _down.has(int(cid)) or not blds.has(int(cid)):
				ok = false
				break
		if not ok:
			c["stuck"] = true
			c["t1"] = now + hz
			continue
		c["stuck"] = false
		_deliver(c)
		caps.erase(id)

func _deliver(c: Dictionary) -> void:
	var w: Dictionary = _w()
	var transit: int = int(w["inv"])
	var res: String = String(c["res"])
	var qty: int = int(c["qty"])
	var done := false
	if sim.state["holds"].has(int(c["hold_in"])):
		done = sim.inv.put_held(int(c["hold_in"]), transit)
	if not done:
		# The destination is gone or has no room any more: the goods are put down at the destination, or where it was.
		var db: Dictionary = sim.state["buildings"].get(int(c["dst"]), {})
		var pos: Vector2 = db["pos"] if not db.is_empty() else (sim.state["buildings"].get(int(c["src"]), {}).get("pos", Vector2.ZERO))
		var pile: int = sim.inv.create_inv("g", int(c["dst"]) if not db.is_empty() and sim.topo.atmo_comp.has(int(c["dst"])) else 0, "pile", 100000, pos)
		sim.inv.move(transit, pile, res, qty)
		sim.inv.remove_if_empty_pile(pile)
		sim.log_event("transport_dropped", "A capsule of %s found no room at its destination and was emptied there." % sim.items.name_of(res).to_lower(), [int(c["dst"])], 1)
	var moved: Dictionary = w["moved"]
	moved[res] = int(moved.get(res, 0)) + qty
	w["delivered"] = int(w["delivered"]) + 1
	var rec: Array = w["recent"]
	rec.append({"t": int(sim.state["tick"]), "res": res, "qty": qty, "src": int(c["src"]), "dst": int(c["dst"])})
	while rec.size() > 200:
		rec.pop_front()

# ---------------------------------------------------------------- what the interface and the renderer read
## Capsules in flight now: [{id, res, qty, src, dst, segs [{cid, p0, p1, t0, t1}], t0, t1, stuck}] (positions along
## each tube from p0 at tick t0 to p1 at tick t1: interpolate with the tick).
func capsules_view() -> Array:
	var out: Array = []
	if not any():
		return out
	var caps: Dictionary = _w()["capsules"]
	var ids: Array = caps.keys()
	ids.sort()
	for id in ids:
		out.append((caps[id] as Dictionary).duplicate(true))
	return out

## Position of a capsule at a tick: {pos, cid, in_tube (false while it waits in a hub)}.
func position_of(c: Dictionary, tick: int) -> Dictionary:
	var segs: Array = c["segs"]
	if segs.is_empty():
		return {"pos": Vector2.ZERO, "cid": -1, "in_tube": false}
	for s in segs:
		if tick < int(s["t0"]):
			return {"pos": s["p0"], "cid": -1, "in_tube": false}
		if tick <= int(s["t1"]):
			var f: float = float(tick - int(s["t0"])) / maxf(1.0, float(int(s["t1"]) - int(s["t0"])))
			return {"pos": (s["p0"] as Vector2).lerp(s["p1"], f), "cid": int(s["cid"]), "in_tube": true}
	return {"pos": segs[segs.size() - 1]["p1"], "cid": -1, "in_tube": false}

## The network for the overlay: {enabled, hubs [{id, name, pos, ok, to (units on their way to it), from}], tubes [{id, a, b, p0, p1, length, ok, busy_s}],
## networks [{id, hubs [ids], tubes [ids]}], capsules, stuck, moved {item: units}, flow {item: units in the last 5 minutes}, delivered}.
func overview() -> Dictionary:
	var out := {"enabled": any(), "hubs": [], "tubes": [], "networks": [], "capsules": 0, "stuck": 0, "moved": {}, "flow": {}, "delivered": 0}
	if not any():
		return out
	_ensure()
	var blds: Dictionary = sim.state["buildings"]
	var w: Dictionary = _w()
	var to_n := {}
	var from_n := {}
	for id in w["capsules"]:
		var c: Dictionary = w["capsules"][id]
		to_n[int(c["dst"])] = int(to_n.get(int(c["dst"]), 0)) + int(c["qty"])
		from_n[int(c["src"])] = int(from_n.get(int(c["src"]), 0)) + int(c["qty"])
		out["capsules"] += 1
		if bool(c["stuck"]):
			out["stuck"] += 1
	var now: int = int(sim.state["tick"])
	var hz: float = float(sim.bal["tick_hz"])
	var ids: Array = blds.keys()
	ids.sort()
	var nets := {}
	for id in ids:
		var b: Dictionary = blds[id]
		if bool(b.get("hub", false)):
			var ok: bool = b["state"] == "active"
			out["hubs"].append({"id": int(id), "name": String(b["name"]), "pos": b["pos"], "ok": ok, "to": int(to_n.get(int(id), 0)), "from": int(from_n.get(int(id), 0)), "net": int(_comp.get(int(id), -1))})
			if ok and _comp.has(int(id)):
				var n: int = int(_comp[int(id)])
				if not nets.has(n):
					nets[n] = {"id": n, "hubs": [], "tubes": []}
				nets[n]["hubs"].append(int(id))
		elif b["kind"] == "link" and bool(b.get("tube", false)):
			var up: bool = not _down.has(int(id))
			out["tubes"].append({"id": int(id), "a": int(b["a"]), "b": int(b["b"]), "p0": b["p0"], "p1": b["p1"], "length": float(b.get("length", 10.0)), "ok": up,
				"busy_s": maxf(0.0, float(int(b.get("tube_free", 0)) - now) / hz)})
			if up and _comp.has(int(b["a"])):
				var n2: int = int(_comp[int(b["a"])])
				if nets.has(n2):
					nets[n2]["tubes"].append(int(id))
				else:
					nets[n2] = {"id": n2, "hubs": [], "tubes": [int(id)]}
	var keys: Array = nets.keys()
	keys.sort()
	for k in keys:
		out["networks"].append(nets[k])
	out["moved"] = (w["moved"] as Dictionary).duplicate()
	out["delivered"] = int(w["delivered"])
	var flow: Dictionary = out["flow"]
	for r in w["recent"]:
		if now - int(r["t"]) <= 300 * int(hz):
			flow[String(r["res"])] = int(flow.get(String(r["res"]), 0)) + int(r["qty"])
	return out

## The inspector of a structure: {hub, tube, feature check, in_transit [{res, qty, dir ("in"|"out"), eta_s, stuck}]}.
func info(bid: int) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	var out := {"hub": bool(b.get("hub", false)), "tube": bool(b.get("tube", false)), "check": check(b), "in_transit": [], "ok": true}
	if b.is_empty() or not any():
		return out
	_ensure()
	var now: int = int(sim.state["tick"])
	var hz: float = float(sim.bal["tick_hz"])
	var caps: Dictionary = _w()["capsules"]
	var ids: Array = caps.keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = caps[id]
		if int(c["dst"]) == bid or int(c["src"]) == bid:
			out["in_transit"].append({"res": String(c["res"]), "qty": int(c["qty"]), "dir": "in" if int(c["dst"]) == bid else "out", "eta_s": maxf(0.0, float(int(c["t1"]) - now) / hz), "stuck": bool(c["stuck"])})
		elif b["kind"] == "link" and (c["path"] as Array).has(bid):
			out["in_transit"].append({"res": String(c["res"]), "qty": int(c["qty"]), "dir": "through", "eta_s": maxf(0.0, float(int(c["t1"]) - now) / hz), "stuck": bool(c["stuck"])})
	if b["kind"] == "link" and bool(b.get("tube", false)):
		out["ok"] = not _down.has(bid)
	elif bool(b.get("hub", false)):
		out["ok"] = b["state"] == "active"
	return out

## Alerts (alerts.tick_second): a tube that does not work, with the capsules that wait for it.
func issues(found: Dictionary, alerts) -> void:
	if not any():
		return
	_ensure()
	if _down.is_empty():
		return
	var blds: Dictionary = sim.state["buildings"]
	var w: Dictionary = _w()
	var waiting := {}
	for id in w["capsules"]:
		var c: Dictionary = w["capsules"][id]
		if bool(c["stuck"]):
			for cid in c["path"]:
				if _down.has(int(cid)):
					waiting[int(cid)] = int(waiting.get(int(cid), 0)) + 1
	var down: Array = _down.duplicate()
	down.sort()
	for cid in down:
		var c2: Dictionary = blds.get(int(cid), {})
		if c2.is_empty():
			continue
		var an: String = String(blds.get(int(c2["a"]), {}).get("name", "?"))
		var bn: String = String(blds.get(int(c2["b"]), {}).get("name", "?"))
		var n: int = int(waiting.get(int(cid), 0))
		var text: String = "The transport tube between %s and %s does not work." % [an, bn]
		if n > 0:
			text += " %d capsule%s wait%s for it." % [n, "" if n == 1 else "s", "s" if n == 1 else ""]
		alerts._add(found, "transport:%d" % int(cid), "transport_down", 2, text, "Repair the corridor. The goods go by hand until it works.", [int(cid)], "", -1.0, maxi(1, n))

# ---------------------------------------------------------------- debug demo (RENDER, UI, showcase)
## Command "transport_demo" (debug only): builds a working network in the colony at once and keeps it busy for two
## minutes, so that capsules are seen in the first seconds: the two storage structures (storehouse or cold storage)
## that are joined by the shortest chain of corridors get hubs, every corridor of that chain gets a tube (the research
## and the materials are skipped), steel and polymer are put into the first hub (made from nothing: a debug stock), and
## every 3 s a haul of 2 units goes from one hub to the other (it is routed by tube like any haul). Result:
## {ok, code, hubs [ids], tubes [ids], text}. A second call renews the two minutes.
func cmd_demo(p: Dictionary) -> Dictionary:
	if not bool(sim.state.get("options", {}).get("debug", false)):
		return {"ok": false, "code": "debug_only", "text": "Debug only."}
	var blds: Dictionary = sim.state["buildings"]
	var stores: Array = []
	var ids: Array = blds.keys()
	ids.sort()
	for id in ids:
		var b: Dictionary = blds[id]
		if b["state"] == "active" and b["kind"] == "room" and hub_defs().has(String(b["def"])) and int(b["inv_out"]) != -1:
			stores.append(int(id))
	if stores.size() < 2:
		return {"ok": false, "code": "no_stores", "text": "Fewer than two storehouses or cold stores."}
	# Corridor graph over every corridor (built or not tubed), shortest chain between two stores.
	var adj := {}
	for id in ids:
		var c: Dictionary = blds[id]
		if c["kind"] == "link" and c["def"] == "corridor" and c["state"] == "active":
			var a: int = int(c["a"])
			var z: int = int(c["b"])
			if not adj.has(a):
				adj[a] = []
			if not adj.has(z):
				adj[z] = []
			adj[a].append([z, int(id)])
			adj[z].append([a, int(id)])
	var best: Array = []
	for s in stores:
		var prev := {s: [-1, -1]}
		var q: Array = [s]
		var qi := 0
		while qi < q.size():
			var x: int = q[qi]
			qi += 1
			for e in adj.get(x, []):
				if not prev.has(int(e[0])):
					prev[int(e[0])] = [x, int(e[1])]
					q.append(int(e[0]))
		for o in stores:
			if o == s or not prev.has(o):
				continue
			var chain: Array = []
			var cur: int = o
			while cur != s:
				chain.push_front(int(prev[cur][1]))
				cur = int(prev[cur][0])
			if best.is_empty() or chain.size() < (best[2] as Array).size():
				best = [s, o, chain]
	if best.is_empty():
		return {"ok": false, "code": "no_path", "text": "No two stores are joined by corridors."}
	var a_id: int = best[0]
	var b_id: int = best[1]
	blds[a_id]["hub"] = true
	blds[b_id]["hub"] = true
	for cid in best[2]:
		blds[int(cid)]["tube"] = true
	installed(blds[a_id])
	_ensure()
	var w: Dictionary = _w()
	w["demo"] = {"a": a_id, "b": b_id, "until": int(sim.state["tick"]) + 120 * int(sim.bal["tick_hz"]), "n": 0}
	# Room for the goods in both stores (a full store takes none: debug only).
	for sid in [a_id, b_id]:
		var sinv: Dictionary = sim.inv.get_inv(int(blds[sid]["inv_out"]))
		if sim.inv.free_space(int(blds[sid]["inv_out"])) < 60:
			sinv["cap"] = int(sinv["cap"]) + 60 - sim.inv.free_space(int(blds[sid]["inv_out"]))
	sim.inv.add_new_forced(int(blds[a_id]["inv_out"]), "metal", 24, "debug")
	sim.inv.add_new_forced(int(blds[a_id]["inv_out"]), "polymer", 12, "debug")
	_demo_feed()
	return {"ok": true, "code": "ok", "hubs": [a_id, b_id], "tubes": (best[2] as Array).duplicate(), "text": "%d hubs, %d tubes." % [2, (best[2] as Array).size()]}

## Called every second: one haul from hub to hub every 3 s while the demo runs.
func _demo_feed() -> void:
	var w: Dictionary = _w()
	var d: Dictionary = w.get("demo", {})
	if d.is_empty():
		return
	var now: int = int(sim.state["tick"])
	if now > int(d["until"]):
		w.erase("demo")
		return
	var hz: int = int(sim.bal["tick_hz"])
	if int(d["n"]) > 0 and (now / hz) % 3 != 0:
		return
	d["n"] = int(d["n"]) + 1
	var blds: Dictionary = sim.state["buildings"]
	var from: int = int(d["a"]) if int(d["n"]) % 2 == 1 else int(d["b"])
	var to: int = int(d["b"]) if from == int(d["a"]) else int(d["a"])
	if not blds.has(from) or not blds.has(to):
		w.erase("demo")
		return
	_ensure()
	var res: String = "metal" if (int(d["n"]) / 2) % 2 == 0 else "polymer"
	if sim.inv.available(int(blds[from]["inv_out"]), res) < 2:
		sim.inv.add_new_forced(int(blds[from]["inv_out"]), res, 6, "debug")
	sim.jobs._make_haul("logistics", int(blds[from]["inv_out"]), int(blds[to]["inv_out"]), res, 2, to, 0)
