extends RefCounted
## Version-4 SIM data for the orders, vehicle, reactor and exploration screens (V4_DESIGN §4.2, §5),
## behind ONE adapter. Every system is SIM's live one (milestones 3 to 7); the UI mock is gone.
## When SIM does not have a system (an older save or map), the screens say "not available".
## Rows (normalised here for the screens):
##   vehicle  sim.vehicles.list() + charge / fuel 0..1, range_m (full), range_left_m, cargo_cap, route, base
##   reactor  sim.reactors.list() + phase (normal|warning|critical|breach), heat_max, warn_at, crit_at,
##            power_out, rods_keep, coolant_keep, dump_units, dump_heat
##   poi      sim.explore.pois() + pos, name, desc, finds, rp, deposit, need_text, need_short (found ones)
## Commands go through main.submit; when the game is paused the result is read at once (_submit).

const ORDER_NAME := {"goto": "Go to", "board": "Board vehicle", "drive": "Drive to", "explore": "Explore area", "survey": "Survey", "repair": "Repair", "maintain": "Maintain", "build": "Help build", "haul": "Haul",
	"work_at": "Work at", "stay": "Stay", "return": "Return to base"}
const VEHICLE_NAME := {"small_rover": "Small rover", "medium_rover": "Medium rover", "hopper": "Hopper", "satellite": "Satellite"}
const PHASES := ["normal", "warning", "critical", "breach"]
const NEED_TEXT := {"any": "Anyone can visit it, on foot or in a vehicle.", "on_foot": "Somebody must walk in: a vehicle alone is not enough.",
	"scientist": "A scientist must visit it."}
const NEED_SHORT := {"any": "anyone", "on_foot": "on foot", "scientist": "a scientist"}

var hud

func _init(h) -> void:
	hud = h

func _sim():
	return hud.main.sim

## SIM systems and the method that proves each one is there.
const LIVE_SYSTEMS := {"vehicles": "list", "orders": "check", "reactors": "list", "explore": "pois"}

## True when SIM has the named system with the published API.
func live(system: String) -> bool:
	if not LIVE_SYSTEMS.has(system):
		return false
	var s = _sim()
	var o = s.get(system) if s != null else null
	return o != null and o is Object and (o as Object).has_method(String(LIVE_SYSTEMS[system]))

func available(system: String) -> bool:
	return live(system)

# ---------------------------------------------------------------- vehicles
## SIM vehicles are LIVE (SIM-to-UI 2026-09-27, milestone 3). Rows are normalised for the screens:
## charge and fuel as 0..1 (the raw values stay in charge_units / fuel_units), range_m = the range on
## a full charge or tank, cargo_cap from the kind, route = null or {from, to, load, back, trips}.
func vehicles() -> Array:
	if live("vehicles"):
		var out: Array = []
		for v in _sim().vehicles.list():
			out.append(_norm(v))
		return out
	return []

func kinds() -> Dictionary:
	if live("vehicles"):
		return _sim().vehicles.kinds()
	return {}

func _norm(v: Dictionary) -> Dictionary:
	var n: Dictionary = v.duplicate()
	var k: Dictionary = kinds().get(String(v["kind"]), {})
	n["charge_units"] = float(v.get("charge", 0.0))
	n["fuel_units"] = float(v.get("fuel", 0.0))
	n["charge"] = float(v.get("charge", 0.0)) / float(v["charge_cap"]) if float(v.get("charge_cap", 0.0)) > 0.0 else 0.0
	n["fuel"] = float(v.get("fuel", 0.0)) / float(v["fuel_cap"]) if float(v.get("fuel_cap", 0.0)) > 0.0 else 0.0
	if String(k.get("move", "")) == "hopper":
		n["range_m"] = float(k.get("fuel_cap", 0.0)) / maxf(0.001, float(k.get("fuel_per_hop", 1.0))) * float(k.get("hop_m", 0.0))
	else:
		n["range_m"] = float(k.get("charge_cap", 0.0)) / maxf(0.001, float(k.get("charge_per_km", 1.0))) * 1000.0
	n["cargo_cap"] = int(k.get("cargo", 0))
	n["range_left_m"] = float(n["range_m"]) * (float(n["fuel"]) if String(k.get("move", "")) == "hopper" else float(n["charge"]))
	var r: Dictionary = v.get("route", {})
	n["route"] = null if r.is_empty() else {"from": int(r.get("a", -1)), "to": int(r.get("b", -1)), "load": r.get("load", {}), "back": r.get("back", {}), "trips": int(r.get("trips", 0))}
	var s = _sim()
	n["base"] = int(s.bases.base_at(v["pos"])) if "bases" in s and s.bases != null and s.bases.has_method("base_at") else 1
	return n

## Vehicle commands with SIM's real names. kind: drive (target), return, stop,
## alight, board (agents), cargo (load, unload), route (from, to, load, back), route_stop,
## deploy (x, y, name). Returns {ok, code, cid}.
func vehicle_cmd(kind: String, id: int, p: Dictionary = {}) -> Dictionary:
	if not live("vehicles"):
		return {"ok": false, "code": "not_available"}
	match kind:
		"drive":
			var t: Vector2 = p["target"]
			return _submit("vehicle_drive", {"id": id, "x": t.x, "y": t.y})
		"explore":
			var te: Vector2 = p["target"]
			return _submit("vehicle_explore", {"id": id, "x": te.x, "y": te.y, "r": float(p.get("r", 150.0))})
		"return": return _submit("vehicle_return", {"id": id})
		"stop": return _submit("vehicle_stop", {"id": id})
		"alight": return _submit("vehicle_alight", {"id": id})
		"board": return _submit("vehicle_board", {"id": id, "agents": p.get("agents", [])})
		"cargo": return _submit("vehicle_cargo", {"id": id, "load": p.get("load", {}), "unload": bool(p.get("unload", false))})
		"route": return _submit("vehicle_route", {"id": id, "a": int(p["from"]), "b": int(p["to"]), "load": p.get("load", {}), "back": p.get("back", {})})
		"route_stop": return _submit("vehicle_route", {"id": id, "stop": true})
		"deploy":
			var v: Dictionary = vehicle(id)
			var dp: Dictionary = {"x": float(p["x"]), "y": float(p["y"]), "rot": 0.0, "inv": int(v.get("cargo_inv", -1))}
			if String(p.get("name", "")) != "":
				dp["name"] = p["name"]
			return _submit("deploy_outpost", dp)
	return {"ok": false, "code": "unknown_command"}

## Builds a vehicle at a rover depot (live only: SIM `build_vehicle`, `cancel_vehicle`).
func build_vehicle(depot: int, kind: String) -> Dictionary:
	return _submit("build_vehicle", {"depot": depot, "kind": kind})

func cancel_vehicle(depot: int) -> Dictionary:
	return _submit("cancel_vehicle", {"depot": depot})

## Sends a SIM command; when the game is paused it is applied at once and its result is read here.
func _submit(kind: String, payload: Dictionary) -> Dictionary:
	var cid = hud.main.submit(kind, payload)
	var res: Dictionary = _sim().cmds.results
	if res.has(cid):
		var r: Dictionary = res[cid]
		return {"ok": bool(r.get("ok", false)), "code": String(r.get("code", "")), "cid": cid, "result": r}
	return {"ok": true, "code": "submitted", "cid": cid}

func vehicle(id: int) -> Dictionary:
	for v in vehicles():
		if int(v["id"]) == id:
			return v
	return {}

func vehicle_name(kind: String) -> String:
	return String(VEHICLE_NAME.get(kind, kind.replace("_", " ").capitalize()))

# ---------------------------------------------------------------- orders and priorities
## UI order kinds -> SIM kinds (SIM-to-UI 2026-09-27, milestone 4).
const SIM_KIND := {"goto": "go", "stay": "stay", "return": "return", "board": "board", "work_at": "work_at", "survey": "survey", "repair": "repair", "maintain": "maintain", "build": "build", "haul": "haul"}
const UI_KIND := {"go": "goto", "stay": "stay", "return": "return", "board": "board", "work_at": "work_at", "survey": "survey", "repair": "repair", "maintain": "maintain", "build": "build", "haul": "haul"}
const CAT_NAME := {"construction": "Construction", "food": "Food", "industry": "Industry", "logistics": "Logistics", "repair": "Repair"}

## The order a colonist is carrying out now: {kind (UI kind), target, status, reason, since}, or {}.
func order_of(aid: int) -> Dictionary:
	if live("orders"):
		var a: Dictionary = _sim().state["agents"].get(aid, {})
		var o = a.get("order", null)
		if typeof(o) != TYPE_DICTIONARY:
			return {}
		return {"kind": String(UI_KIND.get(String(o.get("kind", "")), o.get("kind", ""))), "target": o.get("p"), "status": "active",
			"reason": "", "since": int(o.get("t", 0)), "confirm": bool(o.get("confirm", false))}
	return {}

## Job categories: SIM's five (construction, food, industry, logistics, repair).
func job_categories() -> Array:
	if live("orders"):
		return _sim().orders.job_categories()
	return []

func job_name(cat: String) -> String:
	return String(CAT_NAME.get(cat, cat.capitalize()))

## A colonist's priority for a category, 0..3 (0 = not allowed). Live: the colonist's own value, else
## the colony priority (is_own tells which).
func priority(aid: int, job: String) -> int:
	if live("orders"):
		var a: Dictionary = _sim().state["agents"].get(aid, {})
		var j = a.get("jobs", null)
		if typeof(j) == TYPE_DICTIONARY and (j as Dictionary).has(job):
			return int(j[job])
		return int(_sim().state["policies"]["priority"].get(job, 2))
	return 2

func is_own(aid: int, job: String) -> bool:
	if live("orders"):
		var j = _sim().state["agents"].get(aid, {}).get("jobs", null)
		return typeof(j) == TYPE_DICTIONARY and (j as Dictionary).has(job)
	return false

## SIM order payload for a UI order (target: Vector2, a vehicle / structure / site id, or null).
func _order_payload(kind: String, agents: Array, target, confirm: bool) -> Dictionary:
	var p := {"agents": agents, "kind": String(SIM_KIND.get(kind, kind))}
	match kind:
		"goto", "stay":
			if typeof(target) == TYPE_VECTOR2:
				p["x"] = (target as Vector2).x
				p["y"] = (target as Vector2).y
		"board": p["v"] = int(target)
		"work_at", "repair", "maintain", "build": p["b"] = int(target)
		"haul":
			# V5 section 18: {b: structure, res: item, qty: units}
			if typeof(target) == TYPE_DICTIONARY:
				p["b"] = int(target["b"])
				p["res"] = String(target["res"])
				p["qty"] = int(target.get("qty", 1))
		"survey":
			# A point of interest (milestone 7) or a hazard site: {"poi": id} / {"site": id} / an int (site).
			if typeof(target) == TYPE_DICTIONARY and (target as Dictionary).has("poi"):
				p["poi"] = int(target["poi"])
			elif typeof(target) == TYPE_DICTIONARY and (target as Dictionary).has("site"):
				p["site"] = int(target["site"])
			else:
				p["site"] = int(target)
	if confirm:
		p["confirm"] = true
	return p

## Live orders: a preview with sim.orders.check for each colonist (so the reasons show at once),
## then the order. "Stay" without a place is sent per colonist at its own position.
func _live_order(payload: Dictionary) -> Dictionary:
	var s = _sim()
	var kind: String = String(payload["kind"])
	var force: bool = bool(payload.get("force", false))
	var refused: Array = []
	var reasons := {}
	var sent := 0
	for aid in payload.get("agents", []):
		var a: Dictionary = s.state["agents"].get(int(aid), {})
		var tgt = payload.get("target")
		if kind == "stay" and tgt == null and not a.is_empty():
			# "Stay here": inside, the room it is in (SIM room_at takes its centre); outside, its place.
			var bid: int = int(a.get("bld", -1))
			tgt = s.state["buildings"][bid]["pos"] if String(a.get("where", "")) == "in" and s.state["buildings"].has(bid) else a["pos"]
		var p: Dictionary = _order_payload(kind, [int(aid)], tgt, force)
		var chk: Dictionary = s.orders.check(a, p) if not a.is_empty() else {"ok": false, "code": "unknown", "text": "", "confirmable": false}
		if bool(chk.get("ok", false)) or (force and bool(chk.get("confirmable", false))):
			_submit("order", p)
			sent += 1
		else:
			refused.append(int(aid))
			reasons[int(aid)] = {"code": String(chk.get("code", "")), "text": String(chk.get("text", "")), "confirmable": bool(chk.get("confirmable", false))}
	return {"ok": refused.is_empty(), "code": "" if refused.is_empty() else "refused", "refused": refused, "reasons": reasons, "sent": sent}

const REFUSAL_TEXT := {"radiation": "Radiation there is dangerous (3 mSv/h or more).", "no_air": "Too far: the suit air ends on the way.",
	"no_seat": "No free seat in the vehicle.", "no_path": "No way to get there.", "no_driver": "Nobody aboard can drive.",
	"broken": "Broken: it needs spare parts at a depot.", "no_route": "No way through: slopes, crevices or boulders.", "moving": "It is moving: stop it first.",
	"no_store": "No store within 85 m.", "no_charge": "No charge left.", "no_fuel": "No fuel left.", "no_kit": "No Outpost Kit in the cargo.",
	"kit_far": "The kit must be within 30 m of the place: drive there first.", "too_close_base": "Closer than 300 m to another base.",
	"locked_research": "Needs research first.", "depot_busy": "The depot is already building a vehicle.", "no_bay": "No free bay of that size.", "not_active": "The depot is not finished or not working.", "out_of_range": "Out of range: not enough charge or fuel to get there and back.", "wrong_vehicle": "Only a medium rover can run a route.", "busy": "Busy with a task that cannot stop.", "not_in_base": "Not at a base.",
	"too_hot": "Too hot to restart: wait until the core is below the warning heat.", "no_coolant": "No coolant in the reactor. Carriers bring it; a chemical plant makes it.",
	"done": "Already done.", "running": "It is running: SCRAM it first.", "unknown": "Not found."}

func refusal_text(code: String) -> String:
	return String(REFUSAL_TEXT.get(code, code.replace("_", " ").capitalize() + "."))

## Orders, priorities and reactor controls. Returns {ok, code, refused, text}.
func command(kind: String, payload: Dictionary) -> Dictionary:
	if live("orders"):
		match kind:
			"order_give":
				return _live_order(payload)
			"order_cancel":
				var r: Dictionary = _submit("order_clear", {"agents": payload.get("agents", [])})
				r["refused"] = []
				return r
			"set_priority":
				var r2: Dictionary = _submit("set_jobs", {"agent": int(payload["agent"]), "jobs": {String(payload["job"]): int(payload["value"])}})
				r2["refused"] = []
				return r2
			"reset_priority":
				var r3: Dictionary = _submit("set_jobs", {"agent": int(payload["agent"]), "clear": true})
				r3["refused"] = []
				return r3
	if kind in ["reactor_scram", "reactor_restart", "reactor_cool", "reactor_evacuate"] and live("reactors"):
		var r4: Dictionary = _submit(kind, {"id": int(payload["id"])})
		r4["refused"] = []
		if not bool(r4["ok"]):
			r4["text"] = refusal_text(String(r4["code"]))
		return r4
	return {"ok": false, "code": "not_available", "refused": [], "text": "Not available in this game."}

# ---------------------------------------------------------------- reactors (milestone 6)
## SIM reactor rows, normalised: phase normal|warning|critical|breach (SIM stage ok -> normal), the
## heat scale (SIM: 20 cold, 40 running; warning 60, critical 85, breach 100) and the power it makes now.
func reactors() -> Array:
	if not live("reactors"):
		return []
	var s = _sim()
	var c: Dictionary = s.bal.get("disasters", {}).get("reactor", {})
	var out: Array = []
	for r in s.reactors.list():
		var n: Dictionary = r.duplicate()
		var st: String = String(r.get("stage", "ok"))
		n["phase"] = "normal" if st == "ok" else st
		n["heat_max"] = float(c.get("stage_breach", 100.0))
		n["warn_at"] = float(c.get("stage_warning", 60.0))
		n["crit_at"] = float(c.get("stage_critical", 85.0))
		n["rods_keep"] = int(c.get("rods_keep", 2))
		n["coolant_keep"] = int(c.get("coolant_keep", 8))
		n["dump_units"] = int(c.get("cool_dump_units", 4))
		n["dump_heat"] = float(c.get("cool_dump_heat", 12.0))
		var b: Dictionary = s.state["buildings"].get(int(r["id"]), {})
		n["power_out"] = float(s.bdef(String(b.get("def", "fission_reactor"))).get("gen_const", 0.0)) if bool(r.get("running", false)) and not bool(r.get("scram", false)) else 0.0
		n["state"] = String(b.get("state", ""))
		out.append(n)
	return out

## The worst reactor past normal (for the banner), or {}.
func reactor_alarm() -> Dictionary:
	var worst: Dictionary = {}
	for r in reactors():
		var i: int = PHASES.find(String(r["phase"]))
		if i >= 1 and (worst.is_empty() or i > PHASES.find(String(worst["phase"]))):
			worst = r
	return worst

# ---------------------------------------------------------------- exploration (milestone 7)
func explore_active() -> bool:
	return live("explore") and _sim().explore.active()

## Found points of interest (all: also the ones not found yet, for tests), with their name,
## description, finds and what a visit needs.
func pois(all: bool = false) -> Array:
	if not live("explore"):
		return []
	var s = _sim()
	var kinds: Dictionary = s.content.get("terrain_v4", {}).get("explore", {}).get("pois", {})
	var out: Array = []
	for p in s.explore.pois():
		if not all and not bool(p.get("found", false)):
			continue
		var kc: Dictionary = kinds.get(String(p["kind"]), {})
		var n: Dictionary = p.duplicate()
		n["pos"] = Vector2(float(p["x"]), float(p["y"]))
		n["name"] = String(kc.get("name", String(p["kind"]).capitalize()))
		n["desc"] = String(kc.get("desc", ""))
		n["finds"] = kc.get("finds", {})
		n["rp"] = int(kc.get("rp", 0))
		n["deposit"] = kc.has("deposit")
		n["need_text"] = String(NEED_TEXT.get(String(p.get("need", "any")), ""))
		n["need_short"] = String(NEED_SHORT.get(String(p.get("need", "any")), "anyone"))
		out.append(n)
	return out

func poi(id: int) -> Dictionary:
	for p in pois(true):
		if int(p["id"]) == id:
			return p
	return {}

## What a visit gives, in words: "3 derelict parts, 1 data core" (+ research points, a deposit).
func poi_finds_text(p: Dictionary) -> String:
	var parts: Array = []
	var f: Dictionary = p.get("finds", {})
	var keys: Array = f.keys()
	keys.sort()
	for it in keys:
		parts.append("%d %s" % [int(f[it]), hud.data.item_name(String(it)).to_lower()])
	if int(p.get("rp", 0)) > 0:
		parts.append("%d research points" % int(p["rp"]))
	if bool(p.get("deposit", false)):
		parts.append("a rich deposit")
	return ", ".join(parts) if not parts.is_empty() else "nothing known"

## The fog record {cell, n, bits, rev, count} or {}.
func fog() -> Dictionary:
	return _sim().explore.fog() if explore_active() else {}

func explored_share() -> float:
	return float(_sim().explore.explored_share()) if explore_active() else 1.0

## Satellites with the bands they have mapped: [{id, name, bands_done, bands, next_s, band, uplink,
## mapped: [band ids]}]. A satellite maps bands in order (SIM explore.gd); `band` is the next one, so
## the mapped ones are the bands_done before it.
func sats() -> Array:
	if not live("explore"):
		return []
	var out: Array = []
	for s in _sim().explore.sats():
		var n: Dictionary = s.duplicate()
		var nb: int = maxi(1, int(s["bands"]))
		var mapped: Array = []
		for k in mini(int(s["bands_done"]), nb):
			mapped.append(posmod(int(s["band"]) - 1 - k, nb))
		n["mapped"] = mapped
		out.append(n)
	return out

## Radiation on the ground at p, mSv/h (SIM: the map plus the zones of breaches).
func rad_at(p: Vector2) -> float:
	var s = _sim()
	if live("reactors") and s.reactors.has_method("rad_at"):
		return float(s.reactors.rad_at(p))
	return float(s.world.rad_at(p.x, p.y)) if s.world.has_method("rad_at") else 0.0

## Radiation and toxic zones: [{kind "rad"|"toxic", x, y, r, ...}].
func zones() -> Array:
	return _sim().reactors.zones() if live("reactors") and _sim().reactors.has_method("zones") else []

# ---------------------------------------------------------------- radiation dose (milestone 6)
## Dose limits in mSv: {warn 250, critical 750, sick 1000} (SIM balance disasters.dose).
func dose_limits() -> Dictionary:
	var c: Dictionary = _sim().bal.get("disasters", {}).get("dose", {})
	return {"warn": float(c.get("warn", 250.0)), "critical": float(c.get("critical", 750.0)), "sick": float(c.get("sick", 1000.0))}

## A colonist's dose in mSv (SIM agent.dose; absent = 0).
static func dose_of(a: Dictionary) -> float:
	return float(a.get("dose", 0.0))

## The dose rate the colonist takes now, mSv/h: the ground rate x the shield (a room 0.1, a
## pressurised cabin 0.3) x the research cut (Dosimetry, Shielded Suits). As SIM reactors.gd.
func dose_rate(a: Dictionary) -> float:
	var s = _sim()
	var c: Dictionary = s.bal.get("disasters", {}).get("dose", {})
	var shield := 1.0
	match String(a.get("where", "")):
		"in", "lock":
			shield = float(c.get("shield_room", 0.1))
		"vehicle":
			shield = float(c.get("shield_vehicle", 0.3))
	var cut: float = 1.0 - clampf(float(s.research.bonus("rad_dose_cut")) if s.research.has_method("bonus") else 0.0, 0.0, 0.9)
	return rad_at(a["pos"]) * shield * cut

## Word and colour for a dose: ["", colour] under the warning, "HIGH", "DANGEROUS", "SICK".
func dose_level(d: float) -> Array:
	var lim: Dictionary = dose_limits()
	if d > float(lim["sick"]):
		return ["RADIATION SICK", Color("FF5A5F")]
	if d >= float(lim["critical"]):
		return ["DANGEROUS DOSE", Color("FF5A5F")]
	if d >= float(lim["warn"]):
		return ["HIGH DOSE", Color("FFB547")]
	return ["", Color("B0B6BE")]

# ---------------------------------------------------------------- points of interest: look
const POI_ICON := {"wreck": "poi_wreck", "derelict_probe": "poi_probe", "meteorite_field": "poi_meteorite", "cave": "poi_cave",
	"anomaly": "poi_anomaly", "rich_deposit": "poi_deposit"}
const POI_COLOR := {"wreck": Color("C9D3E0"), "derelict_probe": Color("7C8CFF"), "meteorite_field": Color("FF7A59"), "cave": Color("D9A066"),
	"anomaly": Color("C792EA"), "rich_deposit": Color("FFD166")}
