extends RefCounted
## Upgrade levels 1..5 (docs/AAA_DESIGN.md section 2). An upgrade is ordered with the
## "upgrade" command. Carriers bring the materials to an upgrade inventory of the building
## (role "upg"); when all are there they are built in, and technicians do the work: rooms
## from inside, exterior structures from outside (suit range applies). The building keeps
## working the whole time. Level gates: L2 eng_1, L3 eng_2, L4 eng_3, L5 the tier-5
## special research of the building's family.
##
## building.upgrade = {} or {to, cost{}, inv, progress, work_total, state, block}
##   state: "deliver" (materials on their way) | "work" (materials built in)

var sim

func _init(s) -> void:
	sim = s

## {ok, code, to, cost, research}. code: ok | unknown | not_upgradable | max_level |
## not_active | demolish | busy | locked_research
func check(b: Dictionary) -> Dictionary:
	if b.is_empty() or not sim.state["buildings"].has(b.get("id", -1)):
		return {"ok": false, "code": "unknown", "to": 0, "cost": {}, "research": ""}
	var base: Dictionary = sim.bdef(b["def"])
	var level: int = int(b.get("level", 1))
	var mx: int = int(sim.bal["levels"]["max"])
	var to: int = mini(level + 1, mx)
	var res := {"ok": false, "code": "ok", "to": to, "cost": {}, "research": ""}
	if b["kind"] == "link" or not bool(base.get("levels", false)):
		res["code"] = "not_upgradable"
		return res
	if level >= mx:
		res["code"] = "max_level"
		return res
	res["cost"] = cost_for(b, to)
	res["research"] = sim.research.level_tech(b["def"], to)
	if b["state"] != "active":
		res["code"] = "not_active"
		return res
	if bool(b.get("demolish", false)):
		res["code"] = "demolish"
		return res
	if not (b.get("upgrade", {}) as Dictionary).is_empty():
		res["code"] = "busy"
		return res
	if String(res["research"]) != "" and not sim.research.is_done(res["research"]) and not sim.unlocked_all():
		res["code"] = "locked_research"
		return res
	res["ok"] = true
	return res

## Materials for an upgrade to level `to`: the building's own size cost times
## levels.cost_mult, plus levels.extra_cost (electronics, composite, exotic).
func cost_for(b: Dictionary, to: int) -> Dictionary:
	var lv: Dictionary = sim.bal["levels"]
	var d: Dictionary = sim.sizes.def_for(b["def"], int(b.get("size", 1)))
	var m: float = float(lv["cost_mult"][to - 1])
	var cost := {}
	for r in d.get("cost", {}):
		var n: int = int(round(float(d["cost"][r]) * m))
		if n > 0:
			cost[r] = n
	var extra: Dictionary = lv["extra_cost"][to - 1]
	for r in extra:
		cost[r] = int(cost.get(r, 0)) + int(extra[r])
	return cost

func work_for(b: Dictionary, to: int) -> float:
	var d: Dictionary = sim.sizes.def_for(b["def"], int(b.get("size", 1)))
	var units := 0
	for r in d.get("cost", {}):
		units += int(d["cost"][r])
	return maxf(10.0, float(units) * float(sim.bal["work_per_material"]) * float(d.get("work_mult", 1.0)) * float(sim.bal["levels"]["work_mult"][to - 1]))

## Command "upgrade".
func start(bid: int) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	var chk: Dictionary = check(b)
	if not bool(chk["ok"]):
		return {"ok": false, "code": chk["code"]}
	var units := 0
	for r in chk["cost"]:
		units += int(chk["cost"][r])
	var inv: int = sim.inv.create_inv("b", bid, "upg", maxi(1, units))
	b["upgrade"] = {"to": int(chk["to"]), "cost": chk["cost"].duplicate(), "inv": inv, "progress": 0.0,
		"work_total": work_for(b, int(chk["to"])), "state": "deliver", "block": ""}
	sim.log_event("upgrade_planned", "%s: upgrade to level %d planned." % [b["name"], int(chk["to"])], [bid], 0)
	return {"ok": true, "code": "ok"}

## Command "cancel_upgrade". Delivered materials stay on the ground; built-in materials
## come back by half, like a cancelled construction.
func cancel(bid: int) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(bid, {})
	if b.is_empty() or (b.get("upgrade", {}) as Dictionary).is_empty():
		return {"ok": false, "code": "invalid"}
	_drop(b, true)
	sim.log_event("upgrade_cancelled", "%s: the upgrade was cancelled." % b["name"], [bid], 0)
	return {"ok": true, "code": "ok"}

## Ends an upgrade without finishing it (cancel or demolition). Nothing is lost silently.
func _drop(b: Dictionary, refund: bool) -> void:
	var u: Dictionary = b["upgrade"]
	sim.jobs.cancel_upgrade_tasks(b["id"], int(u.get("inv", -1)))
	var drop: Vector2 = sim.build.drop_point(b)
	if String(u.get("state", "")) == "work" and refund:
		var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, drop)
		for res in u["cost"]:
			var back: int = int(floor(int(u["cost"][res]) * float(sim.bal["demolish_refund_fraction"])))
			if back > 0:
				sim.inv.add_new_forced(pile, res, back, "salvage")
		sim.inv.remove_if_empty_pile(pile)
	if int(u.get("inv", -1)) != -1 and sim.inv.exists(u["inv"]):
		var pile2: int = sim.inv.dissolve_to_pile(u["inv"], drop)
		if pile2 != -1 and b["kind"] == "room" and sim.topo.atmo_comp.has(b["id"]):
			# Materials delivered inside a room stay inside it.
			sim.inv.get_inv(pile2)["oid"] = b["id"]
	b["upgrade"] = {}

## Called by the demolition code before a building is removed.
func drop_for_removal(b: Dictionary) -> void:
	if not (b.get("upgrade", {}) as Dictionary).is_empty():
		_drop(b, false)

func tick_second() -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		var u: Dictionary = b.get("upgrade", {})
		if u.is_empty():
			continue
		if u["state"] == "deliver":
			var all := true
			for r in u["cost"]:
				if sim.inv.count(u["inv"], r) < int(u["cost"][r]):
					all = false
					break
			if all:
				for r in u["cost"]:
					sim.inv.consume(u["inv"], r, int(u["cost"][r]), "built_into")
					sim.stat_add("consumed", r, int(u["cost"][r]))
				u["state"] = "work"
				u["block"] = ""
		elif u["state"] == "work" and float(u["progress"]) >= float(u["work_total"]) - 0.0001:
			_finish(b)

func add_work(b: Dictionary, work_points: float) -> void:
	var u: Dictionary = b.get("upgrade", {})
	if u.is_empty() or u["state"] != "work":
		return
	u["progress"] = minf(float(u["work_total"]), float(u["progress"]) + work_points)

func _finish(b: Dictionary) -> void:
	var u: Dictionary = b["upgrade"]
	var to: int = int(u["to"])
	if int(u.get("inv", -1)) != -1 and sim.inv.exists(u["inv"]):
		sim.inv.dissolve_to_pile(u["inv"], sim.build.drop_point(b))
	b["level"] = to
	b["upgrade"] = {}
	apply_capacities(b)
	sim.util.invalidate()
	sim.jobs.cancel_upgrade_tasks(b["id"], -1)
	sim.stat_add("upgrades", "", 1)
	sim.log_event("upgraded", "%s is now level %d." % [b["name"], to], [b["id"]], 1)

## Inventories follow the effective definition after a level or size change.
func apply_capacities(b: Dictionary) -> void:
	var d: Dictionary = sim.bd(b)
	if int(b.get("inv_out", -1)) != -1 and sim.inv.exists(b["inv_out"]):
		var inv: Dictionary = sim.inv.get_inv(b["inv_out"])
		if inv["role"] == "store" and d.has("storage"):
			inv["cap"] = maxi(int(inv["cap"]), int(d["storage"]))
		elif inv["role"] == "out":
			inv["cap"] = maxi(int(inv["cap"]), int(d.get("output_cap", inv["cap"])))
	if int(b.get("inv_in", -1)) != -1 and sim.inv.exists(b["inv_in"]):
		var inv_in: Dictionary = sim.inv.get_inv(b["inv_in"])
		inv_in["cap"] = maxi(int(inv_in["cap"]), int(d.get("input_cap", inv_in["cap"])))
	if int(b.get("inv_fill", -1)) != -1 and sim.inv.exists(b["inv_fill"]):
		var inv_f: Dictionary = sim.inv.get_inv(b["inv_fill"])
		inv_f["cap"] = maxi(int(inv_f["cap"]), int(d.get("fill_port", inv_f["cap"])))

## Upgrade materials still missing ({} when none).
func missing(b: Dictionary) -> Dictionary:
	var u: Dictionary = b.get("upgrade", {})
	var out := {}
	if u.is_empty() or u["state"] != "deliver":
		return out
	for r in u["cost"]:
		var need: int = int(u["cost"][r]) - sim.inv.count(u["inv"], r)
		if need > 0:
			out[r] = need
	return out
