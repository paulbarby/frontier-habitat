extends RefCounted
## High-end danger (docs/V4_DESIGN.md section 4.2): the fission reactor and its meltdown, the
## unstable crystal refinery, the toxic chemical plant, radiation zones and the radiation dose
## of colonists. Everything is deterministic and visible in advance (forecast()).
## Numbers: content/balance.json "disasters".
##
## Reactor record: building.rx = {heat, fuel_s, scram (bool), scram_t, cool_acc, stage, evac}
##   heat 20..100: ambient 20, running floor 40. Stages: ok < warning (60) < critical (85) <
##   breach (100). Each second while running: + heat_run, + heat_damage x (1 - health / 100),
##   + heat_wear x wear / 100; cooling - cool_active while it has coolant, else - cool_passive.
##   After SCRAM (takes scram_s) the fission stops: + heat_decay while heat > 40.
##   A breach explodes: structures within blast_r are destroyed, people within it die, a
##   radiation zone of zone_r is left that halves every zone_half_days.
## state.zones = [{kind "rad" | "toxic", x, y, r, peak (mSv/h, rad) | dmg (health/day, toxic),
##   t0 (tick), half_s (rad) | until (tick, toxic), src}] (absent until the first zone)
## agent.dose (mSv, absent until the first dose): radiation load; halves slowly (decay_per_day).

const Text = preload("res://sim/text.gd")

var sim

func _init(s) -> void:
	sim = s

func cfg() -> Dictionary:
	return sim.bal["disasters"]

func rcfg() -> Dictionary:
	return cfg()["reactor"]

func zones() -> Array:
	return sim.state.get("zones", [])

func _zones_w() -> Array:
	if not sim.state.has("zones"):
		sim.state["zones"] = []
	return sim.state["zones"]

# ---------------------------------------------------------------- radiation at a place
## mSv/h at p: the ground (v4 map) plus radiation zones.
func rad_at(p: Vector2) -> float:
	var r := 0.0
	if sim.world != null and int(sim.world.version) >= 4:
		r = float(sim.world.rad_at(p.x, p.y))
	var zs = sim.state.get("zones")
	if zs != null:
		for z in zs:
			if z["kind"] == "rad":
				r += _zone_rad(z, p)
	return r

func _zone_rad(z: Dictionary, p: Vector2) -> float:
	var d: float = Vector2(float(z["x"]), float(z["y"])).distance_to(p)
	if d >= float(z["r"]):
		return 0.0
	var age: float = float(int(sim.state["tick"]) - int(z["t0"])) / float(sim.bal["tick_hz"])
	var f: float = 1.0 - d / float(z["r"])
	return float(z["peak"]) * pow(0.5, age / maxf(1.0, float(z["half_s"]))) * f * f

## Health damage per day from toxic ground at p (outside only).
func toxic_at(p: Vector2) -> float:
	var zs = sim.state.get("zones")
	if zs == null:
		return 0.0
	var dmg := 0.0
	for z in zs:
		if z["kind"] == "toxic" and Vector2(float(z["x"]), float(z["y"])).distance_to(p) < float(z["r"]):
			dmg += float(z["dmg"])
	return dmg

# ---------------------------------------------------------------- the reactor
func is_reactor(b: Dictionary) -> bool:
	return bool(sim.bdef(b["def"]).get("reactor", false))

func reactors() -> Array:
	var out: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] == "exterior" and (b["state"] == "active" or b["state"] == "broken") and is_reactor(b):
			out.append(b)
	return out

func rx(b: Dictionary) -> Dictionary:
	if not b.has("rx"):
		b["rx"] = {"heat": float(rcfg()["heat_ambient"]), "fuel_s": 0.0, "scram": false, "scram_t": 0.0, "cool_acc": 0.0, "stage": "ok", "evac": false}
	return b["rx"]

## True while fission runs (fuel in, no SCRAM, not broken): the reactor then makes power.
func running(b: Dictionary) -> bool:
	if not b.has("rx"):
		return false
	var r: Dictionary = b["rx"]
	return float(r["fuel_s"]) > 0.0 and not (bool(r["scram"]) and float(r["scram_t"]) <= 0.0) and b["state"] == "active" and bool(b["enabled"])

func _wear(b: Dictionary) -> float:
	var w = sim.hazards.hs()["wear"].get(int(b["id"]))
	return 0.0 if w == null else float(w["w"])

func _has_coolant(b: Dictionary) -> bool:
	return int(b["inv_in"]) != -1 and sim.inv.available(int(b["inv_in"]), "coolant") > 0

## Heat change per second now (positive = rising) and its parts.
func heat_rate(b: Dictionary) -> float:
	var c: Dictionary = rcfg()
	var r: Dictionary = rx(b)
	var heat: float = float(r["heat"])
	var gain := 0.0
	if running(b):
		gain = float(c["heat_run"])
	elif heat > float(c["heat_floor"]):
		gain = float(c["heat_decay"])
	gain += float(c["heat_damage"]) * (1.0 - float(b["health"]) / 100.0)
	gain += float(c["heat_wear"]) * _wear(b) / 100.0
	var cool: float = float(c["cool_active"]) if _has_coolant(b) else float(c["cool_passive"])
	return gain - cool

func stage_of(heat: float) -> String:
	var c: Dictionary = rcfg()
	if heat >= float(c["stage_breach"]):
		return "breach"
	if heat >= float(c["stage_critical"]):
		return "critical"
	if heat >= float(c["stage_warning"]):
		return "warning"
	return "ok"

## The deterministic forecast: {heat, rate, stage, next_stage, next_s (-1 = not coming)}.
func forecast(b: Dictionary) -> Dictionary:
	var c: Dictionary = rcfg()
	var r: Dictionary = rx(b)
	var heat: float = float(r["heat"])
	var rate: float = heat_rate(b)
	var st: String = stage_of(heat)
	var nxt := ""
	var thr := 0.0
	match st:
		"ok":
			nxt = "warning"
			thr = float(c["stage_warning"])
		"warning":
			nxt = "critical"
			thr = float(c["stage_critical"])
		"critical":
			nxt = "breach"
			thr = float(c["stage_breach"])
	var secs := -1.0
	if nxt != "" and rate > 0.0:
		secs = (thr - heat) / rate
	return {"heat": heat, "rate": rate, "stage": st, "next_stage": nxt, "next_s": secs}

func _reactor_second(b: Dictionary) -> void:
	var c: Dictionary = rcfg()
	var r: Dictionary = rx(b)
	# SCRAM takes effect after scram_s (Reactor Safety halves it).
	if bool(r["scram"]) and float(r["scram_t"]) > 0.0:
		r["scram_t"] = maxf(0.0, float(r["scram_t"]) - 1.0)
	# Fuel: one rod runs rod_seconds.
	if not bool(r["scram"]) and b["state"] == "active" and bool(b["enabled"]):
		if float(r["fuel_s"]) <= 0.0 and int(b["inv_in"]) != -1 and sim.inv.available(int(b["inv_in"]), "fuel_rod") > 0:
			sim.inv.consume(int(b["inv_in"]), "fuel_rod", 1, "burned")
			sim.stat_add("consumed", "fuel_rod", 1)
			r["fuel_s"] = float(c["rod_seconds"])
		if float(r["fuel_s"]) > 0.0:
			r["fuel_s"] = float(r["fuel_s"]) - 1.0
	var rate: float = heat_rate(b)
	# Active cooling uses coolant.
	if _has_coolant(b):
		r["cool_acc"] = float(r["cool_acc"]) + 1.0 / float(c["coolant_per_unit_s"])
		if float(r["cool_acc"]) >= 1.0:
			r["cool_acc"] = float(r["cool_acc"]) - 1.0
			sim.inv.consume(int(b["inv_in"]), "coolant", 1, "cooling")
			sim.stat_add("consumed", "coolant", 1)
	var floor_h: float = float(c["heat_floor"]) if running(b) else float(c["heat_ambient"])
	var heat: float = float(r["heat"]) + rate
	if rate < 0.0:
		heat = maxf(minf(float(r["heat"]), floor_h), heat)
	# A running core warms up to its running heat first.
	if running(b) and heat < floor_h:
		heat = minf(floor_h, float(r["heat"]) + float(c.get("heat_warmup", 0.2)))
	r["heat"] = clampf(heat, float(c["heat_ambient"]), 200.0)
	_apply_stage(b, stage_of(float(r["heat"])))

## Records a new stage (and logs the change); a breach explodes.
func _apply_stage(b: Dictionary, st: String) -> void:
	var c: Dictionary = rcfg()
	var r: Dictionary = rx(b)
	if st != String(r["stage"]):
		var old: String = r["stage"]
		r["stage"] = st
		match st:
			"warning":
				sim.log_event("reactor_warning", "%s: the core is too hot. Cool it or SCRAM it." % b["name"], [int(b["id"])], 2)
			"critical":
				sim.log_event("reactor_critical", "%s: CRITICAL. Meltdown is near. SCRAM, dump coolant and evacuate %d m." % [b["name"], int(c["zone_r"])], [int(b["id"])], 3)
			"ok":
				if old != "ok":
					sim.log_event("reactor_ok", "%s: the core is safe again." % b["name"], [int(b["id"])], 1)
				_end_evac(b)
	if st == "breach":
		_breach_reactor(b)

func _breach_reactor(b: Dictionary) -> void:
	var c: Dictionary = rcfg()
	var p: Vector2 = b["pos"]
	var name: String = b["name"]
	var bid: int = int(b["id"])
	var bdef_id: String = String(b["def"])
	var n: Dictionary = explode(p, float(c["blast_r"]), "the reactor explosion", bid)
	_zones_w().append({"kind": "rad", "x": p.x, "y": p.y, "r": float(c["zone_r"]), "peak": float(c["zone_peak"]),
		"t0": int(sim.state["tick"]), "half_s": float(c["zone_half_days"]) * float(sim.bal["day_length"]), "src": "reactor"})
	sim.stat_add("reactor_breaches", "", 1)
	sim.log_event("reactor_breach", "%s EXPLODED. %s destroyed, %s dead. The ground within %d m is radioactive." % [name,
		Text.n(int(n["structures"]), "structure"), Text.n(int(n["people"]), "person", "people"), int(c["zone_r"])], [bid], 3,
		{"pos": [p.x, p.y], "def": bdef_id, "blast_r": float(c["blast_r"]), "zone_r": float(c["zone_r"])})

## An explosion at p: structures within r are destroyed (specials: damaged to 0), people
## within r die, vehicles within r break. Returns {structures, people}.
func explode(p: Vector2, r: float, cause: String, src: int) -> Dictionary:
	var blds: Dictionary = sim.state["buildings"]
	var dead := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and (a["pos"] as Vector2).distance_to(p) <= r:
			sim.agents._die(a, cause)
			dead += 1
	for vid in sim.vehicles.ids():
		var v: Dictionary = sim.vehicles.get_v(vid)
		if (v["pos"] as Vector2).distance_to(p) <= r:
			v["wear"] = 100.0
			v["state"] = "broken"
			v["block"] = "broken"
			v["path"] = []
	var gone := 0
	var ids: Array = blds.keys()
	for id in ids:
		if not blds.has(id):
			continue
		var b: Dictionary = blds[id]
		if b["kind"] == "link":
			continue
		if (b["pos"] as Vector2).distance_to(p) - float(b.get("radius", 0.0)) > r and int(id) != src:
			continue
		if b["kind"] == "special":
			sim.hazards._damage(b, 100.0, cause, true)
			continue
		sim.build.destroy(b, cause)
		gone += 1
	return {"structures": gone, "people": dead}

# ---------------------------------------------------------------- commands
func _reactor_cmd(p: Dictionary) -> Dictionary:
	var b: Dictionary = sim.state["buildings"].get(int(p.get("id", -1)), {})
	if b.is_empty() or not is_reactor(b):
		return {}
	return b

## "reactor_scram" {id}: the rods drop; fission stops after scram_s seconds.
func cmd_scram(p: Dictionary) -> Dictionary:
	var b: Dictionary = _reactor_cmd(p)
	if b.is_empty():
		return {"ok": false, "code": "unknown"}
	var r: Dictionary = rx(b)
	if bool(r["scram"]):
		return {"ok": false, "code": "done"}
	r["scram"] = true
	r["scram_t"] = float(rcfg()["scram_s"]) * (1.0 - sim.research.bonus("reactor_scram_mult"))
	sim.log_event("reactor_scram", "%s: SCRAM. The fission stops." % b["name"], [int(b["id"])], 2)
	return {"ok": true, "code": "ok"}

## "reactor_restart" {id}: after a SCRAM, only while the core is below the warning heat.
func cmd_restart(p: Dictionary) -> Dictionary:
	var b: Dictionary = _reactor_cmd(p)
	if b.is_empty():
		return {"ok": false, "code": "unknown"}
	var r: Dictionary = rx(b)
	if not bool(r["scram"]):
		return {"ok": false, "code": "running"}
	if float(r["heat"]) >= float(rcfg()["stage_warning"]):
		return {"ok": false, "code": "too_hot"}
	r["scram"] = false
	r["scram_t"] = 0.0
	return {"ok": true, "code": "ok"}

## "reactor_cool" {id}: an emergency coolant dump: up to cool_dump_units coolant from the reactor
## buffer, each takes cool_dump_heat off the core at once.
func cmd_cool(p: Dictionary) -> Dictionary:
	var b: Dictionary = _reactor_cmd(p)
	if b.is_empty():
		return {"ok": false, "code": "unknown"}
	var c: Dictionary = rcfg()
	var have: int = sim.inv.available(int(b["inv_in"]), "coolant") if int(b["inv_in"]) != -1 else 0
	var n: int = mini(have, int(c["cool_dump_units"]))
	if n <= 0:
		return {"ok": false, "code": "no_coolant"}
	sim.inv.consume(int(b["inv_in"]), "coolant", n, "dumped")
	sim.stat_add("consumed", "coolant", n)
	var r: Dictionary = rx(b)
	r["heat"] = maxf(float(c["heat_ambient"]), float(r["heat"]) - float(c["cool_dump_heat"]) * n)
	sim.log_event("reactor_cool", "%s: %d coolant dumped into the core." % [b["name"], n], [int(b["id"])], 1)
	return {"ok": true, "code": "ok", "used": n}

## "reactor_evacuate" {id}: every colonist within zone_r goes to a room with air outside it
## and stays there (a stay order) until the core is safe again. Result {moved, stuck}.
func cmd_evacuate(p: Dictionary) -> Dictionary:
	var b: Dictionary = _reactor_cmd(p)
	if b.is_empty():
		return {"ok": false, "code": "unknown"}
	var zr: float = float(rcfg()["zone_r"])
	var c: Vector2 = b["pos"]
	var safe: Array = []
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var rb: Dictionary = blds[id]
		if (rb["kind"] == "room" or rb["kind"] == "special") and rb["state"] == "active" and sim.topo.atmo_comp.has(id) \
				and (rb["pos"] as Vector2).distance_to(c) > zr + float(rb["radius"]) and sim.util.building_supplied(int(id)):
			safe.append(rb)
	var moved := 0
	var stuck := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive" or a["kind"] == "visitor" or (a["pos"] as Vector2).distance_to(c) > zr:
			continue
		var best := {}
		var best_d := 1e18
		for rb in safe:
			var d: float = (rb["pos"] as Vector2).distance_to(a["pos"])
			if d < best_d:
				best_d = d
				best = rb
		if best.is_empty():
			stuck += 1
			continue
		var res: Dictionary = sim.orders.cmd_order({"agents": [int(aid)], "kind": "stay", "x": (best["pos"] as Vector2).x, "y": (best["pos"] as Vector2).y, "confirm": true})
		if bool(res["ok"]):
			a["order"]["evac"] = int(b["id"])
			moved += 1
		else:
			stuck += 1
	rx(b)["evac"] = true
	sim.log_event("reactor_evacuate", "%s: evacuation. %s leave the %d m zone." % [b["name"], Text.n(moved, "colonist"), int(zr)], [int(b["id"])], 2)
	return {"ok": true, "code": "ok", "moved": moved, "stuck": stuck}

func _end_evac(b: Dictionary) -> void:
	var r: Dictionary = rx(b)
	if not bool(r["evac"]):
		return
	r["evac"] = false
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		var o = a.get("order")
		if o != null and int(o.get("evac", -1)) == int(b["id"]):
			sim.orders.clear(a, "")

## Debug: "reactor_stage" {id, stage}: the stage it names, at once (with its log): the core heat
## is set 2 points over that stage's threshold (so one second of cooling does not undo it).
## "breach" explodes at once, with or without coolant.
func debug_stage(p: Dictionary) -> Dictionary:
	var b: Dictionary = _reactor_cmd(p)
	if b.is_empty():
		return {"ok": false, "code": "unknown"}
	var c: Dictionary = rcfg()
	var h := 0.0
	match String(p.get("stage", "")):
		"ok": h = float(c["heat_floor"])
		"warning": h = float(c["stage_warning"]) + 2.0
		"critical": h = float(c["stage_critical"]) + 2.0
		"breach":
			rx(b)["heat"] = float(c["stage_breach"]) + 2.0
			_apply_stage(b, "breach")
			return {"ok": true, "code": "ok"}
		_: return {"ok": false, "code": "invalid"}
	rx(b)["heat"] = h
	_apply_stage(b, String(p["stage"]))
	return {"ok": true, "code": "ok"}

# ---------------------------------------------------------------- the other risky plants
func _unstable_second(b: Dictionary) -> void:
	var c: Dictionary = cfg()["unstable"]
	var t: int = int(b.get("unstable_t", 0))
	if sim.prod.has_batch(b) and not bool(b["powered"]):
		t += 1
		if t == int(c["warn_s"]):
			sim.log_event("unstable_warning", "%s: no power with a batch inside. It explodes in %d s unless power returns." % [b["name"], int(c["blow_s"]) - t], [int(b["id"])], 3)
		if t >= int(c["blow_s"]):
			var p: Vector2 = b["pos"]
			var nm: String = b["name"]
			var bid: int = int(b["id"])
			var bdef_id: String = String(b["def"])
			var n: Dictionary = explode(p, float(c["blast_r"]), "an explosion", bid)
			sim.log_event("unstable_blast", "%s exploded. %s destroyed, %s dead." % [nm, Text.n(int(n["structures"]), "structure"), Text.n(int(n["people"]), "person", "people")], [bid], 3,
				{"pos": [p.x, p.y], "def": bdef_id, "blast_r": float(c["blast_r"])})
			return
	else:
		t = 0
	if t == 0:
		b.erase("unstable_t")
	else:
		b["unstable_t"] = t

func _toxic_second(b: Dictionary) -> void:
	var c: Dictionary = cfg()["toxic"]
	if float(b["health"]) >= float(c["leak_health"]) and b["state"] == "active":
		return
	var tick: int = int(sim.state["tick"])
	for z in zones():
		if z["kind"] == "toxic" and int(z.get("src_id", -1)) == int(b["id"]) and int(z["until"]) > tick:
			return
	_zones_w().append({"kind": "toxic", "x": (b["pos"] as Vector2).x, "y": (b["pos"] as Vector2).y, "r": float(c["zone_r"]), "dmg": float(c["damage_per_day"]),
		"t0": tick, "until": tick + int(float(c["days"]) * float(sim.bal["day_length"]) * float(sim.bal["tick_hz"])), "src": "chemical", "src_id": int(b["id"])})
	sim.log_event("toxic_leak", "%s leaks. The ground within %d m is toxic for %s days: keep people away and repair it." % [b["name"], int(c["zone_r"]), str(c["days"])], [int(b["id"])], 3)

# ---------------------------------------------------------------- once a second
func tick_second() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var list: Array = []
	for id in blds:
		var b: Dictionary = blds[id]
		if b["kind"] != "exterior" or (b["state"] != "active" and b["state"] != "broken"):
			continue
		var d: Dictionary = sim.bdef(b["def"])
		if bool(d.get("reactor", false)) or bool(d.get("unstable", false)) or bool(d.get("toxic", false)):
			list.append(b)
	for b in list:
		if not blds.has(b["id"]):
			continue
		var d2: Dictionary = sim.bdef(b["def"])
		if bool(d2.get("reactor", false)):
			_reactor_second(b)
		elif bool(d2.get("unstable", false)):
			_unstable_second(b)
		elif bool(d2.get("toxic", false)):
			_toxic_second(b)
	_zones_second()
	_dose_second()

func _zones_second() -> void:
	var zs = sim.state.get("zones")
	if zs == null or (zs as Array).is_empty():
		return
	var tick: int = int(sim.state["tick"])
	for i in range((zs as Array).size() - 1, -1, -1):
		var z: Dictionary = zs[i]
		if z["kind"] == "toxic" and int(z["until"]) <= tick:
			zs.remove_at(i)
		elif z["kind"] == "rad" and _zone_rad(z, Vector2(float(z["x"]), float(z["y"]))) < 0.05:
			zs.remove_at(i)
	# Toxic ground hurts people outside in it.
	var day: float = float(sim.bal["day_length"])
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["where"] == "out":
			var t: float = toxic_at(a["pos"])
			if t > 0.0:
				sim.agents._hurt(a, t / day, "toxic chemicals")

## Each colonist's radiation load (mSv): rad_at x shielding x research, in game hours; it
## halves slowly; above `sick` it hurts.
func _dose_second() -> void:
	var v4: bool = sim.world != null and int(sim.world.version) >= 4
	if not v4 and zones().is_empty():
		return
	var c: Dictionary = cfg()["dose"]
	var day: float = float(sim.bal["day_length"])
	var hours: float = float(c["hours_per_day"]) / day
	var cut: float = 1.0 - clampf(sim.research.bonus("rad_dose_cut"), 0.0, 0.9)
	var decay: float = float(c["decay_per_day"]) + (float(c["decay_heal"]) if sim.research.bonus("rad_heal") > 0.0 else 0.0)
	var keep: float = pow(1.0 - clampf(decay, 0.0, 0.99), 1.0 / day)
	var sick: float = float(c["sick"])
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var shield := 1.0
		match String(a["where"]):
			"in", "lock":
				shield = float(c["shield_room"])
			"vehicle":
				shield = float(c["shield_vehicle"]) if sim.vehicles.cabin_air(a) else 1.0
		var rate: float = rad_at(a["pos"]) * shield * cut
		var dose: float = float(a.get("dose", 0.0)) * keep + rate * hours
		if dose < 0.01 and not a.has("dose"):
			continue
		a["dose"] = dose
		if dose > sick:
			sim.agents._hurt(a, float(c["damage_per_day_per_sv"]) * (dose - sick) / 1000.0 / day, "radiation sickness")

# ---------------------------------------------------------------- alerts and reads
func issues(found: Dictionary, al) -> void:
	for b in reactors():
		var r: Dictionary = rx(b)
		var f: Dictionary = forecast(b)
		if f["stage"] == "warning" or f["stage"] == "critical":
			var sev: int = 3 if f["stage"] == "critical" else 2
			var txt: String = "%s: core %s (%d)." % [b["name"], "CRITICAL" if sev == 3 else "too hot", int(f["heat"])]
			if float(f["next_s"]) >= 0.0:
				txt += " %s in %d s." % ["Meltdown" if f["next_stage"] == "breach" else "Critical", int(f["next_s"])]
			al._add(found, "reactor:%d" % int(b["id"]), "reactor_" + String(f["stage"]), sev, txt, "SCRAM, dump coolant, bring coolant, evacuate.", [int(b["id"])], "", float(f["next_s"]))
		elif not bool(r["scram"]) and b["state"] == "active" and float(r["fuel_s"]) <= 0.0:
			al._add(found, "reactor_fuel:%d" % int(b["id"]), "reactor_fuel", 1, "%s has no fuel rods." % b["name"], "Make fuel rods.", [int(b["id"])])
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var ub: Dictionary = blds[id]
		if int(ub.get("unstable_t", 0)) > 0:
			var left: int = int(cfg()["unstable"]["blow_s"]) - int(ub["unstable_t"])
			al._add(found, "unstable:%d" % int(id), "unstable_power", 3, "%s has no power with a batch inside: it explodes in %d s." % [ub["name"], left], "Restore its power.", [int(id)], "", float(left))
	for z in zones():
		if z["kind"] == "toxic":
			al._add(found, "toxic:%d" % int(z["t0"]), "toxic_leak", 2, "Toxic ground (%d m) near %s." % [int(z["r"]), String(blds.get(int(z.get("src_id", -1)), {}).get("name", "a chemical plant"))], "Keep people away. Repair the plant.", [int(z.get("src_id", -1))])
	var c: Dictionary = cfg()["dose"]
	var hi := 0
	var crit := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor" and a.has("dose"):
			if float(a["dose"]) >= float(c["critical"]):
				crit += 1
			elif float(a["dose"]) >= float(c["warn"]):
				hi += 1
	if crit > 0:
		al._add(found, "rad_dose_critical", "rad_dose", 3, "%s %s a dangerous radiation dose." % [Text.n(crit, "colonist"), Text.have(crit)], "Keep them inside, away from radiation.", [], "", -1.0, crit)
	elif hi > 0:
		al._add(found, "rad_dose", "rad_dose", 2, "%s %s a high radiation dose." % [Text.n(hi, "colonist"), Text.have(hi)], "Keep them away from radiation for a few days.", [], "", -1.0, hi)

## Rows for the view and the interface.
func list() -> Array:
	var out: Array = []
	var c: Dictionary = rcfg()
	for b in reactors():
		var r: Dictionary = rx(b)
		var f: Dictionary = forecast(b)
		out.append({"id": int(b["id"]), "name": b["name"], "pos": b["pos"], "heat": float(r["heat"]), "stage": f["stage"],
			"rate": float(f["rate"]), "next_stage": f["next_stage"], "next_phase_s": float(f["next_s"]), "running": running(b),
			"scram": bool(r["scram"]), "scram_left_s": float(r["scram_t"]), "evac": bool(r["evac"]),
			"fuel_s": float(r["fuel_s"]), "rods": sim.inv.count(int(b["inv_in"]), "fuel_rod") if int(b["inv_in"]) != -1 else 0,
			"coolant": sim.inv.count(int(b["inv_in"]), "coolant") if int(b["inv_in"]) != -1 else 0,
			"blast_r": float(c["blast_r"]), "zone_r": float(c["zone_r"])})
	return out
