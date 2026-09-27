extends RefCounted
## Vehicles (docs/V4_DESIGN.md section 5, content/vehicles.json): small and medium rovers and
## the hopper. A vehicle is built at a rover depot, moves only with a colonist aboard (the
## driver), uses charge (rovers) or rocket fuel (hopper), wears with distance, and is charged,
## refuelled and repaired while parked at a powered depot. Crew ride inside: a pressurised
## cabin has air, a small rover does not (suits). Cargo is an inventory (owner type "v").
## A medium rover can run a route between two bases (load at one, unload at the other).
##
## state.vehicles = {"list": {id: vehicle}, "next": n}
## vehicle = {id, kind, name, pos, rot, depot, state ("parked" | "driving" | "broken"),
##   charge, fuel, wear, cargo (inventory id), crew [agent ids], dest (Vector2 or null),
##   path [Vector2], pi, hop_wait, block ("" or a reason), route {} }

var sim

func _init(s) -> void:
	sim = s

static func fresh_state() -> Dictionary:
	return {"list": {}, "next": 1}

func vs() -> Dictionary:
	if not sim.state.has("vehicles"):
		sim.state["vehicles"] = fresh_state()
	return sim.state["vehicles"]

func cfg() -> Dictionary:
	return sim.content["vehicles"]

func kinds() -> Dictionary:
	return cfg()["kinds"]

func kind_of(v: Dictionary) -> Dictionary:
	return kinds().get(String(v["kind"]), {})

## Reads never add state.vehicles (a game without vehicles keeps its digest).
func _list() -> Dictionary:
	var st = sim.state.get("vehicles")
	return {} if st == null else st["list"]

func get_v(id: int) -> Dictionary:
	return _list().get(id, {})

func ids() -> Array:
	var out: Array = _list().keys()
	out.sort()
	return out

func count() -> int:
	return _list().size()

# ---------------------------------------------------------------- depots
func is_depot(b: Dictionary) -> bool:
	return bool(sim.bdef(b["def"]).get("depot", false))

func is_pad(b: Dictionary) -> bool:
	return bool(sim.bdef(b["def"]).get("launch", false))

## Depots and launch pads: the structures that take build orders (vorder).
func is_builder(b: Dictionary) -> bool:
	return is_depot(b) or is_pad(b)

func builders() -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "exterior" and b["state"] == "active" and is_builder(b):
			out.append(b)
	return out

func depots() -> Array:
	var out: Array = []
	# state.buildings keeps its order through a save, so this order is deterministic.
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "exterior" and b["state"] == "active" and is_depot(b):
			out.append(b)
	return out

## Parking places of a depot: ART-HAB's Anchor_Bay_<i> inside the hangar, the vehicle facing
## out through its door (content rover_depot.sizes.bay_anchors, model x/z turned with the record
## like the model: sim = pos + Vector2(x, z).rotated(rot) x radius / model radius).
## [{i, kind, pos, rot, exit}]: exit = on the apron in front of the bay door, outside the footprint.
func bays(d: Dictionary) -> Array:
	var def: Dictionary = sim.bd(d)
	var n_s: int = int(def.get("bays_small", 2))
	var n_m: int = int(def.get("bays_medium", 0))
	var anchors: Array = def.get("bay_anchors", [])
	var scale: float = float(d["radius"]) / maxf(0.1, float(def.get("radius", d["radius"])))
	var out: Array = []
	var rot: float = float(d["rot"])
	var n: int = n_s + n_m
	for i in n:
		var loc := Vector2(-2.0, (float(i) - float(n - 1) * 0.5) * -4.7)
		if i < anchors.size():
			loc = Vector2(float(anchors[i][0]), float(anchors[i][1]))
		var pos: Vector2 = (d["pos"] as Vector2) + (loc * scale).rotated(rot)
		var exit: Vector2 = (d["pos"] as Vector2) + (Vector2(float(d["radius"]) + 3.0, loc.y * scale)).rotated(rot)
		out.append({"i": i, "kind": "small" if i < n_s else "medium", "pos": pos, "rot": rot, "exit": exit})
	return out

## The bay record of a vehicle parked at a depot, else {}.
func bay_of(v: Dictionary) -> Dictionary:
	if int(v.get("bay", -1)) == -1:
		return {}
	var d: Dictionary = sim.state["buildings"].get(int(v.get("depot", -1)), {})
	if d.is_empty():
		return {}
	for b in bays(d):
		if int(b["i"]) == int(v["bay"]):
			return b
	return {}

## The bay whose parking place is at p (a drive's destination), else {}.
func bay_at(p: Vector2) -> Dictionary:
	for d in depots():
		for b in bays(d):
			if (b["pos"] as Vector2).distance_to(p) < 0.5:
				return b
	return {}

## The bay a vehicle of this size may use at a depot (-1: none free). A small vehicle may
## use a medium bay.
func free_bay(d: Dictionary, bay_kind: String, except_id: int = -1) -> int:
	var used := {}
	for vid in ids():
		var v: Dictionary = get_v(vid)
		if int(v["id"]) != except_id and int(v.get("depot", -1)) == int(d["id"]) and int(v.get("bay", -1)) != -1:
			used[int(v["bay"])] = true
	for b in bays(d):
		if used.has(int(b["i"])):
			continue
		if bay_kind == "small" or b["kind"] == "medium":
			return int(b["i"])
	return -1

func bay_pos(d: Dictionary, i: int) -> Vector2:
	for b in bays(d):
		if int(b["i"]) == i:
			return b["pos"]
	return d["pos"]

## The depot a parked vehicle stands at (within dock_reach of its bay or the depot), else {}.
func depot_at(v: Dictionary) -> Dictionary:
	var reach: float = float(cfg().get("dock_reach", 25.0))
	for d in depots():
		if (d["pos"] as Vector2).distance_to(v["pos"]) <= float(d["radius"]) + reach:
			return d
	return {}

# ---------------------------------------------------------------- building
## "build_vehicle" {depot, kind}: carriers bring the parts to the depot (like upgrade
## materials); when all are there they are built in and technicians assemble the vehicle
## outside at the depot (suit range applies).
## depot.vorder = {} or {kind, cost{}, inv, progress, work_total, state ("deliver" | "work"), block}
func cmd_build(p: Dictionary) -> Dictionary:
	var d: Dictionary = sim.state["buildings"].get(int(p.get("depot", p.get("pad", -1))), {})
	if d.is_empty() or not is_builder(d):
		return {"ok": false, "code": "unknown"}
	if d["state"] != "active":
		return {"ok": false, "code": "not_active"}
	var kind: String = String(p.get("kind", ""))
	# V4 milestone 7: a launch pad builds survey satellites only; a depot builds vehicles.
	var pad: bool = is_pad(d)
	var k: Dictionary = cfg().get("satellite", {}) if (pad and kind == "satellite") else ({} if pad else kinds().get(kind, {}))
	if k.is_empty():
		return {"ok": false, "code": "invalid"}
	var tech: String = String(k.get("research", ""))
	if tech != "" and not sim.research.is_done(tech) and not sim.unlocked_all():
		return {"ok": false, "code": "locked_research"}
	if not (d.get("vorder", {}) as Dictionary).is_empty():
		return {"ok": false, "code": "busy"}
	if not pad and free_bay(d, String(k.get("bay", "small"))) == -1:
		return {"ok": false, "code": "no_bay"}
	var cost: Dictionary = k.get("cost", {})
	var units := 0
	for r in cost:
		units += int(cost[r])
	var inv: int = sim.inv.create_inv("b", int(d["id"]), "vbuild", maxi(1, units))
	d["vorder"] = {"kind": kind, "cost": cost.duplicate(), "inv": inv, "progress": 0.0,
		"work_total": float(k.get("build_work", 120.0)), "state": "deliver", "block": ""}
	sim.log_event("vehicle_order", "%s: %s ordered." % [d["name"], k["name"]], [int(d["id"])], 0)
	return {"ok": true, "code": "ok"}

## "cancel_vehicle" {depot}: delivered parts go on the ground; built-in parts come back by half.
func cmd_cancel(p: Dictionary) -> Dictionary:
	var d: Dictionary = sim.state["buildings"].get(int(p.get("depot", -1)), {})
	if d.is_empty() or (d.get("vorder", {}) as Dictionary).is_empty():
		return {"ok": false, "code": "invalid"}
	drop_order(d, true)
	return {"ok": true, "code": "ok"}

func drop_order(d: Dictionary, refund: bool) -> void:
	var o: Dictionary = d.get("vorder", {})
	if o.is_empty():
		return
	sim.jobs.cancel_upgrade_tasks(int(d["id"]), int(o.get("inv", -1)), "vbuild")
	var drop: Vector2 = sim.build.drop_point(d)
	if String(o.get("state", "")) == "work" and refund:
		var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, drop)
		for res in o["cost"]:
			var back: int = int(floor(int(o["cost"][res]) * float(sim.bal["demolish_refund_fraction"])))
			if back > 0:
				sim.inv.add_new_forced(pile, res, back, "salvage")
		sim.inv.remove_if_empty_pile(pile)
	if int(o.get("inv", -1)) != -1 and sim.inv.exists(int(o["inv"])):
		sim.inv.dissolve_to_pile(int(o["inv"]), drop)
	d["vorder"] = {}

## Once a second: parts all delivered -> built in (state "work").
func _orders_second() -> void:
	for d in builders():
		var o: Dictionary = d.get("vorder", {})
		if o.is_empty() or o["state"] != "deliver":
			continue
		var all := true
		for r in o["cost"]:
			if sim.inv.count(int(o["inv"]), r) < int(o["cost"][r]):
				all = false
				break
		if all:
			for r in o["cost"]:
				sim.inv.consume(int(o["inv"]), r, int(o["cost"][r]), "built_into")
				sim.stat_add("consumed", r, int(o["cost"][r]))
			o["state"] = "work"
			o["block"] = ""

## Technician work on a depot's order. Returns true when the vehicle is finished.
func add_build_work(d: Dictionary, wp: float) -> bool:
	var o: Dictionary = d.get("vorder", {})
	if o.is_empty() or o["state"] != "work":
		return false
	o["progress"] = float(o["progress"]) + wp
	if float(o["progress"]) < float(o["work_total"]):
		return false
	if int(o.get("inv", -1)) != -1 and sim.inv.exists(int(o["inv"])):
		sim.inv.dissolve_to_pile(int(o["inv"]), sim.build.drop_point(d))
	if String(o["kind"]) == "satellite":
		d["vorder"] = {}
		sim.explore.launch(d)
		return true
	var k: Dictionary = kinds()[o["kind"]]
	var bay: int = free_bay(d, String(k.get("bay", "small")))
	var v: Dictionary = spawn(String(o["kind"]), bay_pos(d, bay) if bay != -1 else sim.build.drop_point(d), int(d["id"]))
	v["bay"] = bay
	v["rot"] = float(d["rot"]) + PI
	d["vorder"] = {}
	sim.log_event("vehicle_built", "%s is ready at %s." % [v["name"], d["name"]], [int(d["id"]), int(v["id"])], 1)
	return true

func spawn(kind: String, pos: Vector2, depot: int = -1) -> Dictionary:
	var k: Dictionary = kinds()[kind]
	var st: Dictionary = vs()
	var id: int = sim.new_id()
	var n: int = int(st["next"])
	st["next"] = n + 1
	var v := {"id": id, "kind": kind, "name": "%s %d" % [k["name"], n], "pos": pos, "rot": 0.0, "depot": depot, "bay": -1,
		"state": "parked", "charge": float(k.get("charge_cap", 0.0)), "fuel": float(k.get("fuel_cap", 0.0)), "wear": 0.0,
		"cargo": -1, "crew": [], "dest": null, "path": [], "pi": 0, "hop_wait": 0.0, "block": "", "route": {}, "odo": 0.0, "idle_s": 0}
	v["cargo"] = sim.inv.create_inv("v", id, "vcargo", int(k.get("cargo", 10)), pos)
	st["list"][id] = v
	return v

# ---------------------------------------------------------------- crew
func seats(v: Dictionary) -> int:
	return int(kind_of(v).get("seats", 2))

## Research bonuses (V4 milestone 5): veh_range, veh_repair, veh_hopper2.
func charge_cap(v: Dictionary) -> float:
	return float(kind_of(v).get("charge_cap", 0.0)) * (1.0 + sim.research.bonus("vehicle_charge_mult"))

func wear_mult() -> float:
	return maxf(0.0, 1.0 - sim.research.bonus("vehicle_wear_cut"))

func pressurised(v: Dictionary) -> bool:
	return bool(kind_of(v).get("pressurised", false)) and v["state"] != "broken"

## True when a rider breathes cabin air (a pressurised vehicle).
func cabin_air(a: Dictionary) -> bool:
	var v: Dictionary = get_v(int(a.get("veh", -1)))
	return not v.is_empty() and pressurised(v)

## Where a colonist stands to get in (the vehicle's side, on open ground).
## Where a colonist stands to get in: beside the vehicle; for a vehicle in a depot bay, on the
## apron in front of its bay door (the hangar floor is inside the depot's footprint).
func board_point(v: Dictionary) -> Vector2:
	var bay: Dictionary = bay_of(v)
	if not bay.is_empty():
		var q0 = sim.nav.nearest_walkable(bay["exit"], 8)
		return q0 if q0 != null else bay["exit"]
	var side: Vector2 = Vector2(cos(float(v["rot"])), sin(float(v["rot"]))).orthogonal() * 3.0
	var q = sim.nav.nearest_walkable((v["pos"] as Vector2) + side, 6)
	return q if q != null else v["pos"]

## A colonist next to the vehicle gets in. false when full, too far or not outside.
func board(a: Dictionary, vid: int) -> bool:
	var v: Dictionary = get_v(vid)
	if v.is_empty() or a["where"] != "out" or (v["crew"] as Array).size() >= seats(v):
		return false
	var reach: float = float(cfg().get("board_reach", 8.0))
	if (a["pos"] as Vector2).distance_to(v["pos"]) > reach and (a["pos"] as Vector2).distance_to(board_point(v)) > 2.0:
		return false
	sim.agents.abort_plan(a, "boarded")
	a["where"] = "vehicle"
	a["veh"] = vid
	a["bld"] = -1
	a["pos"] = v["pos"]
	a["goal"] = "Riding in %s" % v["name"]
	(v["crew"] as Array).append(int(a["id"]))
	v["idle_s"] = 0
	return true

## A colonist gets out next to the vehicle (outside, in its suit).
func alight(a: Dictionary) -> void:
	var v: Dictionary = get_v(int(a.get("veh", -1)))
	a["where"] = "out"
	a["bld"] = -1
	if not v.is_empty():
		(v["crew"] as Array).erase(int(a["id"]))
		a["pos"] = board_point(v)
	a.erase("veh")
	a["goal"] = "Idle"
	a["ret_c"] = {}

## True when a supplied airlock or hatch is within suit reach of the vehicle.
func near_air(v: Dictionary) -> bool:
	return sim.agents.nearest_air_metres(v["pos"]) <= sim.agents.suit_reach_metres()

## An open vehicle (suits only) turns back to a depot while the crew's air still covers the
## drive back (x1.3 + 20 s). The drive back uses the straight-line distance at full speed
## as its estimate; the path is longer, hence the margin.
func _air_guard(v: Dictionary) -> void:
	if pressurised(v) or (v["crew"] as Array).is_empty() or bool(v.get("returning", false)) or near_air(v):
		return
	var low := 1e9
	for aid in v["crew"]:
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		if not a.is_empty():
			low = minf(low, float(a["suit"]))
	var back: Vector2 = return_point(v)
	var secs: float = (v["pos"] as Vector2).distance_to(back) / maxf(0.1, float(kind_of(v).get("speed", 6.0)))
	if low > secs * 1.3 + 20.0:
		return
	v["route"] = {}
	v.erase("explore")
	if drive_to(v, back) == "ok":
		v["returning"] = true
		sim.log_event("vehicle_air", "%s turns back: the crew's suit air is low." % v["name"], [int(v["id"])], 2)

func alight_all(v: Dictionary) -> void:
	for aid in (v["crew"] as Array).duplicate():
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		if not a.is_empty():
			alight(a)
	v["crew"] = []

# ---------------------------------------------------------------- driving
## Sends a vehicle to a point along its own kind of route. Needs a driver aboard.
func drive_to(v: Dictionary, p: Vector2) -> String:
	if v["state"] == "broken":
		return "broken"
	if (v["crew"] as Array).is_empty():
		return "no_driver"
	if not sim.nav.has_method("vehicle_path"):
		return "no_route"            # vehicles drive on the v4 map only
	var k: Dictionary = kind_of(v)
	# V4: out of a bay and into a bay through its door (the hangar is inside the footprint).
	var from_bay: Dictionary = bay_of(v)
	var to_bay: Dictionary = bay_at(p)
	# A vehicle stops only on ground flatter than park_slope_deg (RENDER: a rover parked on a 30 deg
	# crater flank reads as tipping over).
	if to_bay.is_empty():
		p = park_spot(p)
	var a: Vector2 = from_bay["exit"] if not from_bay.is_empty() else v["pos"]
	var b: Vector2 = to_bay["exit"] if not to_bay.is_empty() else p
	var r: Dictionary = sim.nav.vehicle_path(a, b, String(k.get("move", "rover")), float(k.get("hop_m", 400.0)))
	if not bool(r["ok"]):
		return "no_route"
	var pts: Array = (r["pts"] as Array).duplicate()
	if not from_bay.is_empty():
		pts.push_front(v["pos"])
	if not to_bay.is_empty():
		pts.append(p)
	v["path"] = pts
	# Taxi segments (bay <-> apron) are driven slowly; a hopper does not fly them.
	v["taxi_a"] = 1 if not from_bay.is_empty() else 0
	v["taxi_b"] = pts.size() - 1 if not to_bay.is_empty() else -1
	v["pi"] = 1
	v["dest"] = p
	v["state"] = "driving"
	v["bay"] = -1
	v["block"] = ""
	v["hop_wait"] = 0.0
	return "ok"

## Every tick: moving vehicles and their crew.
func tick() -> void:
	if count() == 0:
		return
	var dt: float = 1.0 / float(sim.bal["tick_hz"])
	var agents: Dictionary = sim.state["agents"]
	for vid in ids():
		var v: Dictionary = get_v(vid)
		if v["state"] == "driving":
			_move(v, dt)
		for aid in v["crew"]:
			var a: Dictionary = agents.get(int(aid), {})
			if not a.is_empty():
				a["pos"] = v["pos"]

func _move(v: Dictionary, dt: float) -> void:
	var k: Dictionary = kind_of(v)
	var crew: Array = v["crew"]
	if crew.is_empty():
		_stop(v, "no_driver")
		return
	var hopper: bool = String(k.get("move", "rover")) == "hopper"
	if float(v["hop_wait"]) > 0.0:
		v["hop_wait"] = float(v["hop_wait"]) - dt
		return
	var pts: Array = v["path"]
	var i: int = int(v["pi"])
	if i >= pts.size():
		_arrive(v)
		return
	var speed: float = float(k.get("speed", 6.0))
	var taxi: bool = (i == 1 and int(v.get("taxi_a", 0)) == 1) or i == int(v.get("taxi_b", -1))
	if taxi:
		speed = minf(speed, float(cfg().get("taxi_speed", 3.0)))
	elif not hopper:
		speed *= float(sim.state["env"].get("speed_mult", 1.0))
	var target: Vector2 = pts[i]
	var pos: Vector2 = v["pos"]
	if hopper and not taxi and pos.is_equal_approx(pts[i - 1]):
		# A hop starts: it takes its fuel now.
		var need: float = float(k.get("fuel_per_hop", 3.0)) * (1.0 - sim.research.bonus("hopper_fuel_cut"))
		if float(v["fuel"]) < need:
			_stop(v, "no_fuel")
			return
		v["fuel"] = float(v["fuel"]) - need
		v["wear"] = float(v["wear"]) + float(k.get("wear_per_hop", 2.0)) * wear_mult()
	var step: float = speed * dt
	var d: float = pos.distance_to(target)
	var moved: float = minf(step, d)
	if not hopper and not taxi:
		var use: float = moved / 1000.0 * float(k.get("charge_per_km", 10.0))
		if float(v["charge"]) < use:
			_stop(v, "no_charge")
			return
		v["charge"] = float(v["charge"]) - use
		v["wear"] = float(v["wear"]) + moved / 1000.0 * float(k.get("wear_per_km", 1.0)) * wear_mult()
	if d > 0.001:
		v["rot"] = (target - pos).angle()
	v["pos"] = pos.move_toward(target, moved)
	v["odo"] = float(v["odo"]) + moved
	if moved >= d - 0.0001:
		v["pos"] = target
		v["pi"] = i + 1
		var next_taxi: bool = i + 1 == int(v.get("taxi_b", -1))
		if hopper and not taxi and not next_taxi and i + 1 < pts.size():
			v["hop_wait"] = 3.0          # landed between hops
		if i + 1 >= pts.size():
			v["hop_wait"] = 0.0
	if float(v["wear"]) >= 100.0:
		v["wear"] = 100.0
		v["state"] = "broken"
		v["block"] = "broken"
		sim.log_event("vehicle_broken", "%s broke down. It needs spare parts." % v["name"], [], 2)

func _stop(v: Dictionary, why: String) -> void:
	v["returning"] = false
	v["state"] = "parked"
	v["block"] = why
	v["path"] = []
	v["dest"] = null
	sim.log_event("vehicle_stopped", "%s stopped: %s." % [v["name"], _why_text(why)], [], 1)

static func _why_text(why: String) -> String:
	match why:
		"no_charge": return "the battery is empty"
		"no_fuel": return "out of rocket fuel"
		"no_driver": return "nobody drives it"
		"broken": return "broken"
	return why

func _arrive(v: Dictionary) -> void:
	v["returning"] = false
	v["state"] = "parked"
	v["path"] = []
	v["dest"] = null
	v["block"] = ""
	var d: Dictionary = depot_at(v)
	if not d.is_empty():
		var used := {}
		for vid in ids():
			var o: Dictionary = get_v(vid)
			if int(o["id"]) != int(v["id"]) and int(o.get("depot", -1)) == int(d["id"]) and int(o.get("bay", -1)) != -1:
				used[int(o["bay"])] = true
		for b in bays(d):
			if not used.has(int(b["i"])) and (b["pos"] as Vector2).distance_to(v["pos"]) < 1.5:
				v["bay"] = int(b["i"])
				v["depot"] = int(d["id"])
				v["rot"] = float(b["rot"])      # parked facing out through the door
				break

## Slope of the ground at p in degrees (height differences 2 m either side).
func slope_deg(p: Vector2) -> float:
	var w = sim.world
	if w == null or int(w.version) < 4:
		return 0.0
	var d := 2.0
	var hx: float = (float(w.height_at(p.x + d, p.y)) - float(w.height_at(p.x - d, p.y))) / (2.0 * d)
	var hy: float = (float(w.height_at(p.x, p.y + d)) - float(w.height_at(p.x, p.y - d))) / (2.0 * d)
	return rad_to_deg(atan(sqrt(hx * hx + hy * hy)))

## A parking place at or near p (rings of 4 m, up to 48 m) on open rover ground flatter than
## park_slope_deg; p itself when none is found.
func park_spot(p: Vector2) -> Vector2:
	var lim: float = float(cfg().get("park_slope_deg", 10.0))
	if not sim.nav.has_method("rover_ok"):
		return p
	if slope_deg(p) <= lim and sim.nav.rover_ok(p):
		return p
	for ring in range(1, 13):
		var r: float = 4.0 * ring
		var n: int = 8 + ring * 4
		for k in n:
			var q: Vector2 = p + Vector2.RIGHT.rotated(k * TAU / n) * r
			if sim.nav.rover_ok(q) and slope_deg(q) <= lim:
				return q
	return p

## "vehicle_return" target: the bay of its depot (or of the nearest depot with a free bay).
func return_point(v: Dictionary) -> Vector2:
	var best := {}
	var best_d := 1e18
	for d in depots():
		var bay: int = free_bay(d, String(kind_of(v).get("bay", "small")), int(v["id"]))
		if bay == -1:
			continue
		var dd: float = (d["pos"] as Vector2).distance_to(v["pos"]) - (1e6 if int(d["id"]) == int(v.get("depot", -1)) else 0.0)
		if dd < best_d:
			best_d = dd
			best = {"d": d, "bay": bay}
	if best.is_empty():
		return v["pos"]
	return bay_pos(best["d"], int(best["bay"]))

# ---------------------------------------------------------------- once a second
func tick_second() -> void:
	_orders_second()
	if count() == 0:
		return
	var c: Dictionary = cfg()
	for vid in ids():
		var v: Dictionary = get_v(vid)
		if v["state"] == "driving":
			v["idle_s"] = 0
			_air_guard(v)
			continue
		_air_guard(v)
		if v["state"] == "driving":
			continue
		# Crew of a parked vehicle without a route get out after two minutes when air is near
		# (5 s in an open vehicle). Far from air they stay aboard until ordered.
		if (v["route"] as Dictionary).is_empty() and not v.has("explore") and not (v["crew"] as Array).is_empty() and near_air(v):
			v["idle_s"] = int(v.get("idle_s", 0)) + 1
			var wait: int = int(c.get("crew_idle_s", 120)) if pressurised(v) else 5
			if int(v["idle_s"]) >= wait:
				alight_all(v)
				v["idle_s"] = 0
		var d: Dictionary = depot_at(v)
		if not d.is_empty():
			var k: Dictionary = kind_of(v)
			# Charging needs a powered depot; fuel and repairs need only its store.
			if float(k.get("charge_cap", 0.0)) > 0.0 and bool(d["powered"]):
				v["charge"] = minf(charge_cap(v), float(v["charge"]) + float(c.get("charge_per_s", 1.0)))
			var store: int = int(d.get("inv_out", -1))
			if store != -1:
				var per: float = float(c.get("fuel_per_item", 3.0))
				if float(k.get("fuel_cap", 0.0)) - float(v["fuel"]) >= per and sim.inv.available(store, String(c.get("refuel_item", "rocket_fuel"))) > 0:
					sim.inv.consume(store, String(c.get("refuel_item", "rocket_fuel")), 1, "vehicle_fuel")
					sim.stat_add("consumed", String(c.get("refuel_item", "rocket_fuel")), 1)
					v["fuel"] = float(v["fuel"]) + per
				var rep: float = float(c.get("repair_per_spare", 25.0))
				if float(v["wear"]) >= rep and sim.inv.available(store, "spare_parts") > 0:
					sim.inv.consume(store, "spare_parts", 1, "vehicle_repair")
					sim.stat_add("consumed", "spare_parts", 1)
					v["wear"] = maxf(0.0, float(v["wear"]) - rep)
					if v["state"] == "broken":
						v["state"] = "parked"
						v["block"] = ""
		if not (v["route"] as Dictionary).is_empty():
			_route_second(v)
		elif v.has("explore") and v["state"] == "parked":
			_explore_next(v)

# ---------------------------------------------------------------- routes
## "vehicle_route" {id, a, b, load: {item: n}, back: {item: n}}: the vehicle loads at base a,
## drives to base b, unloads, loads `back`, drives to a, unloads, and so on, while it has a
## driver. {id} alone ends the route.
func _route_second(v: Dictionary) -> void:
	var r: Dictionary = v["route"]
	var leg: String = String(r.get("leg", "load_a"))
	match leg:
		"load_a", "load_b":
			var at: int = int(r["a"]) if leg == "load_a" else int(r["b"])
			var want: Dictionary = r.get("load", {}) if leg == "load_a" else r.get("back", {})
			_unload_at(v, at)
			_load_at(v, at, want)
			var to: int = int(r["b"]) if leg == "load_a" else int(r["a"])
			var dest: Vector2 = dock_point(to, v)
			if drive_to(v, dest) == "ok":
				r["leg"] = "to_b" if leg == "load_a" else "to_a"
			else:
				v["block"] = "route: " + ("no driver" if (v["crew"] as Array).is_empty() else "no route")
		"to_a", "to_b":
			if v["state"] == "parked":
				r["leg"] = "load_b" if leg == "to_b" else "load_a"
				r["trips"] = int(r.get("trips", 0)) + (1 if leg == "to_b" else 0)

## Where a vehicle stops at a base: a free depot bay of that base, else beside its core.
func dock_point(base_id: int, v: Dictionary) -> Vector2:
	for d in depots():
		if sim.bases.base_of(int(d["id"])) != base_id:
			continue
		var bay: int = free_bay(d, String(kind_of(v).get("bay", "small")), int(v["id"]))
		if bay != -1:
			return bay_pos(d, bay)
	var core: Dictionary = sim.bases.core_of(base_id)
	if core.is_empty():
		return v["pos"]
	var q = sim.nav.nearest_walkable((core["pos"] as Vector2) + Vector2(float(core["radius"]) + 10.0, 0).rotated(float(core["rot"]) + PI * 0.5), 8)
	return q if q != null else core["pos"]

## Stores of a base a docked vehicle reaches (store and output inventories of structures of
## that base within dock_reach + 60 m).
func _base_stores(base_id: int, near: Vector2) -> Array:
	var out: Array = []
	var invs: Dictionary = sim.state["inventories"]
	var ids2: Array = invs.keys()
	ids2.sort()
	for inv_id in ids2:
		var inv: Dictionary = invs[inv_id]
		if inv["ot"] != "b" or (inv["role"] != "store" and inv["role"] != "out"):
			continue
		var b: Dictionary = sim.state["buildings"].get(int(inv["oid"]), {})
		if b.is_empty() or b["state"] != "active" or sim.bases.base_of(int(b["id"])) != base_id:
			continue
		if (b["pos"] as Vector2).distance_to(near) > float(cfg().get("dock_reach", 25.0)) + 60.0:
			continue
		out.append(int(inv_id))
	return out

func _load_at(v: Dictionary, base_id: int, want: Dictionary) -> int:
	var moved := 0
	var keys: Array = want.keys()
	keys.sort()
	for res in keys:
		var need: int = int(want[res]) - sim.inv.count(int(v["cargo"]), res)
		for inv_id in _base_stores(base_id, v["pos"]):
			if need <= 0:
				break
			var n: int = sim.inv.move(inv_id, int(v["cargo"]), res, need)
			need -= n
			moved += n
	return moved

func _unload_at(v: Dictionary, base_id: int) -> int:
	var moved := 0
	var cargo: Dictionary = sim.inv.get_inv(int(v["cargo"]))
	var keys: Array = (cargo["items"] as Dictionary).keys()
	keys.sort()
	for res in keys:
		if res == "outpost_kit":
			continue
		var left: int = int(cargo["items"].get(res, 0))
		for inv_id in _base_stores(base_id, v["pos"]):
			if left <= 0:
				break
			if sim.inv.get_inv(inv_id)["role"] != "store":
				continue
			var n: int = sim.inv.move(int(v["cargo"]), inv_id, res, left)
			left -= n
			moved += n
	return moved

# ---------------------------------------------------------------- commands
func _cmd_vehicle(p: Dictionary) -> Dictionary:
	return get_v(int(p.get("id", -1)))

## "vehicle_board" {id, agents: [ids]}: those colonists walk to the vehicle and get in.
func cmd_board(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	var free: int = seats(v) - (v["crew"] as Array).size()
	var sent := 0
	for aid in p.get("agents", []):
		var a: Dictionary = sim.state["agents"].get(int(aid), {})
		if a.is_empty() or a["state"] != "alive" or a["kind"] == "visitor" or a["where"] == "vehicle":
			continue
		if sent >= free:
			break
		if sim.agents.order_board(a, int(v["id"])):
			sent += 1
	if sent == 0:
		return {"ok": false, "code": "no_seat" if free <= 0 else "no_path"}
	return {"ok": true, "code": "ok", "sent": sent}

## "vehicle_drive" {id, x, y}: the driver takes it there.
func cmd_drive(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	v["route"] = {}
	v.erase("explore")
	var code: String = drive_to(v, Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0))))
	return {"ok": code == "ok", "code": code}

## "vehicle_return" {id}: back to a depot bay.
func cmd_return(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	v["route"] = {}
	v.erase("explore")
	var code: String = drive_to(v, return_point(v))
	return {"ok": code == "ok", "code": code}

## "vehicle_stop" {id}: stops where it is (crew stay aboard; a route ends).
func cmd_stop(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	v["route"] = {}
	v.erase("explore")
	if v["state"] == "driving":
		v["state"] = "parked"
		v["path"] = []
		v["dest"] = null
	return {"ok": true, "code": "ok"}

## "vehicle_alight" {id}: everyone gets out (the vehicle stops).
func cmd_alight(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	if v["state"] == "driving":
		_stop(v, "no_driver")
	alight_all(v)
	return {"ok": true, "code": "ok"}

## "vehicle_cargo" {id, load: {item: n}, unload: true}: at a base, from and to its stores.
func cmd_cargo(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	if v["state"] == "driving":
		return {"ok": false, "code": "moving"}
	var base_id: int = sim.bases.base_at(v["pos"])
	if _base_stores(base_id, v["pos"]).is_empty():
		return {"ok": false, "code": "no_store"}
	var out := 0
	var got := 0
	if bool(p.get("unload", false)):
		out = _unload_at(v, base_id)
	got = _load_at(v, base_id, p.get("load", {}))
	return {"ok": true, "code": "ok", "loaded": got, "unloaded": out}

## "vehicle_route" {id, a, b, load, back}: run between two bases; {id, stop: true} ends it.
func cmd_route(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	if bool(p.get("stop", false)):
		v["route"] = {}
		return {"ok": true, "code": "ok"}
	if not sim.research.is_done("logi_routes") and not sim.unlocked_all():
		return {"ok": false, "code": "locked_research"}
	var a: int = int(p.get("a", -1))
	var b: int = int(p.get("b", -1))
	if sim.bases.get_base(a).is_empty() or sim.bases.get_base(b).is_empty() or a == b:
		return {"ok": false, "code": "invalid"}
	v["route"] = {"a": a, "b": b, "load": (p.get("load", {}) as Dictionary).duplicate(), "back": (p.get("back", {}) as Dictionary).duplicate(), "leg": "load_a", "trips": 0}
	return {"ok": true, "code": "ok"}

## "vehicle_explore" {id, x, y, r}: the driver takes the vehicle round an area: eight points
## on a circle of radius r (50..600 m) round (x, y), in turn; a point it cannot reach is left
## out. Then it stops at the last point. (Milestone 7: the drive reveals the fog.)
func cmd_explore(p: Dictionary) -> Dictionary:
	var v: Dictionary = _cmd_vehicle(p)
	if v.is_empty():
		return {"ok": false, "code": "unknown"}
	if v["state"] == "broken":
		return {"ok": false, "code": "broken"}
	if (v["crew"] as Array).is_empty():
		return {"ok": false, "code": "no_driver"}
	var c := Vector2(float(p.get("x", 0.0)), float(p.get("y", 0.0)))
	var r: float = clampf(float(p.get("r", 150.0)), 50.0, 600.0)
	var pts: Array = []
	var a0: float = (v["pos"] as Vector2).angle_to_point(c) + PI
	for k in 8:
		pts.append(c + Vector2.RIGHT.rotated(a0 + k * TAU / 8.0) * r)
	v["route"] = {}
	v["explore"] = {"pts": pts, "i": 0, "c": c, "r": r}
	if not _explore_next(v):
		return {"ok": false, "code": "no_route"}
	return {"ok": true, "code": "ok"}

## Drives to the next reachable point of the explore loop. false when none is left.
func _explore_next(v: Dictionary) -> bool:
	var e: Dictionary = v["explore"]
	var pts: Array = e["pts"]
	while int(e["i"]) < pts.size():
		var q: Vector2 = pts[int(e["i"])]
		e["i"] = int(e["i"]) + 1
		if drive_to(v, q) == "ok":
			return true
		if (v["crew"] as Array).is_empty() or v["state"] == "broken":
			break
	v.erase("explore")
	return false

# ---------------------------------------------------------------- reads
## Rows for the view and the interface.
func list() -> Array:
	var out: Array = []
	for vid in ids():
		var v: Dictionary = get_v(vid)
		var k: Dictionary = kind_of(v)
		out.append({"id": int(v["id"]), "kind": v["kind"], "name": v["name"], "pos": v["pos"], "rot": float(v["rot"]),
			"state": v["state"], "block": v["block"], "charge": float(v["charge"]), "charge_cap": charge_cap(v),
			"fuel": float(v["fuel"]), "fuel_cap": float(k.get("fuel_cap", 0.0)), "wear": float(v["wear"]),
			"crew": (v["crew"] as Array).duplicate(), "seats": seats(v), "cargo": (sim.inv.get_inv(int(v["cargo"])).get("items", {}) as Dictionary).duplicate(),
			"cargo_inv": int(v["cargo"]), "dest": v["dest"], "path": (v["path"] as Array).duplicate(), "pi": int(v["pi"]),
			"hopping": String(k.get("move", "")) == "hopper" and v["state"] == "driving" and float(v["hop_wait"]) <= 0.0,
			"depot": int(v.get("depot", -1)), "bay": int(v.get("bay", -1)), "route": (v["route"] as Dictionary).duplicate(),
			"explore": (v.get("explore", {}) as Dictionary).duplicate(true)})
	return out
