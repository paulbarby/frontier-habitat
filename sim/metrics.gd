extends RefCounted
## Forecasts, history, objectives, tutorial steps and the loss report (spec 3, 12).
## Progress comes from real simulation conditions, never from button clicks.

const Text = preload("res://sim/text.gd")

var sim

const TUTORIAL := [
	{"id": "power", "title": "Make power", "text": "Build a solar array and a battery. Join them with a utility cable. Carriers bring the materials from the lander."},
	{"id": "air", "title": "Water and oxygen", "text": "Build a water extractor, a reservoir and an oxygen plant. Join all three to the power network. The oxygen plant must make oxygen."},
	{"id": "shelter", "title": "Airlock and habitat", "text": "Build an airlock and a habitat. Join them and the oxygen plant with corridors so they share air."},
	{"id": "move", "title": "Move in", "text": "When the habitat has air, the residents take beds there. Wait until all of them have a habitat bed."},
	{"id": "food", "title": "Grow and cook", "text": "Build a greenhouse and a kitchen, joined to the base by corridors. Growers seed the trays. Operators cook the harvest."},
	{"id": "ore", "title": "Ore and metal", "text": "Build a mine on the mineral deposit and a refinery. Join both to the base. One metal must come out of the refinery."},
	{"id": "night", "title": "Survive a night", "text": "Keep everybody alive through a full night on the base's own air and power."},
	{"id": "settlers", "title": "First settlers", "text": "Reach the Stable outpost stage, then open Colony and admit new settlers."},
]

func _init(s) -> void:
	sim = s

# ---------------------------------------------------------------- forecast
## "meals" counts every edible unit: cooked dishes and emergency rations. "dishes" leaves
## out the rations. Computed once per tick (callers must not change the result).
var _fc := {}
var _fc_tick := -1

func forecast() -> Dictionary:
	var tick: int = int(sim.state["tick"])
	if tick == _fc_tick and not _fc.is_empty():
		return _fc
	_fc = _forecast()
	_fc_tick = tick
	return _fc

func _forecast() -> Dictionary:
	var bal: Dictionary = sim.bal
	var pop: int = sim.alive_count()
	var totals: Dictionary = sim.inv.totals()
	var meals := 0
	var rations: int = int(totals.get("meals", {}).get("total", 0))
	for d in sim.items.dishes():
		meals += int(totals.get(d, {}).get("total", 0))
	var water_units: float = float(int(totals.get("water", {}).get("total", 0)))
	var blds: Dictionary = sim.state["buildings"]
	var beds := 0
	var o2_make := 0.0
	var energy := 0.0
	var energy_cap := 0.0
	var critical_p := 0.0
	var wind_p := 0.0
	var o2_mult: float = 1.0 + sim.research.bonus("o2_mult")
	var batt_mult: float = 1.0 + sim.research.bonus("battery_mult")
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active" or b["kind"] == "link":
			continue
		var def: Dictionary = sim.bd(b)
		if b["def"] == "lander":
			if sim.util.lander_supplied(b):
				beds += int(def.get("beds", 0))
			continue
		beds += int(def.get("beds", 0))
		water_units += sim.util.units(int(b["water"]))
		if bool(b["enabled"]):
			if def.has("o2_out"):
				o2_make += float(def["o2_out"]) * o2_mult
			elif def.has("o2_bonus"):
				o2_make += float(def["o2_bonus"])
		if def.has("energy_cap"):
			energy += sim.util.units(int(b["energy"]))
			energy_cap += float(def["energy_cap"]) * batt_mult
		if def.get("power_class", "") == "life_support" and bool(b["enabled"]):
			critical_p += float(def.get("power", 0.0))
		if def.has("gen_wind"):
			wind_p += float(def["gen_wind"]) * float(sim.planet["wind_avg"]) * 0.5
		if def.has("gen_const") and bool(b["enabled"]):
			wind_p += float(def["gen_const"])
	var day_len: float = float(bal["day_length"])
	var night: float = day_len - float(sim.planet["daylight_seconds"])
	var night_need: float = maxf(0.0, critical_p - wind_p) * night / day_len
	var per_day_food: float = maxf(1.0, float(pop))
	var per_day_water: float = maxf(1.0, float(pop) * float(bal["drink_units"]))
	var f := {
		"pop": pop, "meals": meals, "meal_days": float(meals) / per_day_food,
		"dishes": meals - rations, "rations": rations,
		"water": water_units, "water_days": water_units / per_day_water,
		"beds": beds, "o2_make": o2_make, "o2_need": float(pop) * float(bal["oxygen_per_colonist"]),
		"energy": energy, "energy_cap": energy_cap, "night_need": night_need, "critical_p": critical_p,
	}
	f["need_meals"] = pop
	f["need_water"] = pop * int(bal["drink_units"])
	f["safe"] = pop > 0 and meals >= pop and water_units >= float(pop * int(bal["drink_units"])) and energy >= night_need and energy_cap > 0.0
	return f

func avg_morale() -> float:
	var s := 0.0
	var n := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			s += float(a["morale"])
			n += 1
	return s / n if n > 0 else 0.0

## Groups of rooms that have their own oxygen plant, air and beds (stage 3 rule).
func supplied_districts() -> int:
	var n := 0
	var blds: Dictionary = sim.state["buildings"]
	for comp in sim.topo.atmo_members:
		if not sim.util.comp_supplied(comp):
			continue
		var plant := false
		var beds := 0
		for bid in sim.topo.atmo_members[comp]:
			var def: Dictionary = sim.bd(blds[bid])
			if (def.has("o2_out") or def.has("o2_bonus")) and blds[bid]["state"] == "active":
				plant = true
			if blds[bid]["def"] != "lander":
				beds += int(def.get("beds", 0))
		if plant and beds > 0:
			n += 1
	return n

# ---------------------------------------------------------------- per second
func tick_second() -> void:
	var st: Dictionary = sim.state
	var pr: Dictionary = st["progress"]
	var flags: Dictionary = st["flags"]
	var hz: int = int(sim.bal["tick_hz"])
	var day_ticks: int = int(sim.bal["day_length"]) * hz
	var tick: int = int(st["tick"])

	var base_air := false
	for comp in sim.util.atmo_stats:
		var a: Dictionary = sim.util.atmo_stats[comp]
		if not bool(a.get("lander", false)) and bool(a["supplied"]):
			base_air = true
	flags["base_air"] = base_air

	var f: Dictionary = forecast()
	if bool(f["safe"]):
		pr["safe_ticks"] = int(pr["safe_ticks"]) + hz
	else:
		pr["safe_ticks"] = 0
	_stage(pr, f, day_ticks, tick)
	_tutorial(pr, f)

	if int(f["pop"]) == 0 and not bool(pr["lost"]):
		pr["lost"] = true
		pr["lost_tick"] = tick
		sim.log_event("lost", "No living colonists remain.", [], 3)

	if tick % (int(sim.bal["history_sample_seconds"]) * hz) == 0:
		_sample(f)
	var sc: Dictionary = sim.bal["series"]
	if tick % (int(sc["sample_seconds"]) * hz) == 0:
		_sample_series(f)
	if tick % (int(sc["item_sample_seconds"]) * hz) == 0:
		_sample_items()
	if tick % day_ticks == 0:
		_day_rollover()

func _stage(pr: Dictionary, f: Dictionary, day_ticks: int, tick: int) -> void:
	var stage: int = int(pr["stage"])
	var since_death: float = 1e9
	if int(pr["last_death_tick"]) >= 0:
		since_death = float(tick - int(pr["last_death_tick"])) / float(day_ticks)
	else:
		since_death = float(tick) / float(day_ticks)
	var stages: Array = sim.bal["stages"]
	var next: int = stage + 1
	if next >= stages.size():
		return
	var s: Dictionary = stages[next]
	var ok: bool = int(f["pop"]) >= int(s.get("pop", 0))
	if s.has("safe_reserve_days"):
		ok = ok and int(pr["safe_ticks"]) >= int(float(s["safe_reserve_days"]) * day_ticks)
	if s.has("morale"):
		ok = ok and avg_morale() >= float(s["morale"])
	if s.has("no_death_days"):
		ok = ok and since_death >= float(s["no_death_days"])
	if s.has("districts"):
		ok = ok and supplied_districts() >= int(s["districts"])
	if s.has("meal_days"):
		ok = ok and float(f["meal_days"]) >= float(s["meal_days"])
	if next == stages.size() - 1:
		ok = ok and int(sim.state["metrics"].get("material_balance", 0)) > 0
	if ok:
		pr["stage"] = next
		sim.log_event("stage", "New stage: %s." % s["name"], [], 1)

func _tutorial(pr: Dictionary, f: Dictionary) -> void:
	var step: int = int(pr["tutorial_step"])
	if step >= TUTORIAL.size():
		return
	var done := false
	var blds: Dictionary = sim.state["buildings"]
	match TUTORIAL[step]["id"]:
		"power":
			for comp in sim.topo.power_members:
				var solar := false
				var batt := false
				for bid in sim.topo.power_members[comp]:
					if blds[bid]["state"] == "active":
						solar = solar or blds[bid]["def"] == "solar_array" or blds[bid]["def"] == "wind_turbine"
						batt = batt or blds[bid]["def"] == "battery"
				done = done or (solar and batt)
		"air":
			for comp in sim.util.atmo_stats:
				var a: Dictionary = sim.util.atmo_stats[comp]
				if not bool(a.get("lander", false)) and int(a["stock"]) > 0:
					done = true
		"shelter":
			for comp in sim.topo.atmo_members:
				if not sim.util.comp_supplied(comp):
					continue
				var lock := false
				var hab := false
				for bid in sim.topo.atmo_members[comp]:
					lock = lock or blds[bid]["def"] == "airlock"
					hab = hab or blds[bid]["def"] == "habitat"
				done = done or (lock and hab)
		"move":
			done = int(f["pop"]) > 0
			for aid in sim.state["agents"]:
				var ag: Dictionary = sim.state["agents"][aid]
				if ag["state"] == "alive":
					var bed: Dictionary = blds.get(ag["bed"], {})
					if bed.is_empty() or bed["def"] == "lander":
						done = false
		"food":
			done = int(sim.state["stats"].get("cooked_total", 0)) >= 2
		"ore":
			done = int(sim.state["metrics"]["produced"].get("metal", 0)) >= 1
		"night":
			if bool(sim.state["flags"].get("base_air", false)) and sim.util.is_night():
				pr["night_seen"] = true
			done = bool(pr.get("night_seen", false)) and not sim.util.is_night() and int(pr["deaths"]) == 0
		"settlers":
			done = int(sim.state["metrics"].get("settlers_admitted", 0)) > 0
	if done:
		pr["tutorial_step"] = step + 1
		sim.log_event("tutorial", "Tutorial step complete: %s." % TUTORIAL[step]["title"], [], 1)

func _sample(f: Dictionary) -> void:
	var m: Dictionary = sim.state["metrics"]
	var totals: Dictionary = sim.inv.totals()
	var o2 := 0.0
	for comp in sim.util.atmo_stats:
		o2 += sim.util.units(int(sim.util.atmo_stats[comp]["stock"]))
	var gen := 0.0
	var dem := 0.0
	for comp in sim.util.power_stats:
		gen += sim.util.to_rate(sim.util.power_stats[comp]["gen"])
		dem += sim.util.to_rate(sim.util.power_stats[comp]["demand"])
	var h: Array = m["history"]
	h.append([int(sim.state["tick"]), int(f["pop"]), int(f["meals"]), snappedf(float(f["water"]), 0.1), snappedf(o2, 0.01),
		snappedf(float(f["energy"]), 0.01), int(totals.get("metal", {}).get("total", 0)), int(totals.get("polymer", {}).get("total", 0)),
		snappedf(avg_morale(), 0.1), snappedf(gen, 0.1), snappedf(dem, 0.1)])
	while h.size() > int(sim.bal["history_max_samples"]):
		h.pop_front()

func _day_rollover() -> void:
	var m: Dictionary = sim.state["metrics"]
	var totals: Dictionary = sim.inv.totals()
	var mat: int = int(totals.get("metal", {}).get("total", 0)) + int(totals.get("polymer", {}).get("total", 0))
	m["material_balance"] = mat - int(m.get("material_prev", mat))
	m["material_prev"] = mat
	_daily_row()
	_spoil_summary()
	sim.log_event("day", "Day %d begins." % sim.util.day_number(), [], 0)

# ---------------------------------------------------------------- chart data
## Ring buffers for the charts (design section 10): state.metrics.series[name] =
## [[tick, value], ...], at most series.max_points each. Sampled every 10 s; item totals
## ("item:<id>") every 60 s.
func series(name: String) -> Array:
	return sim.state["metrics"].get("series", {}).get(name, [])

func series_names() -> Array:
	var out: Array = sim.state["metrics"].get("series", {}).keys()
	out.sort()
	return out

func _push(name: String, value: float) -> void:
	var m: Dictionary = sim.state["metrics"]
	if not m.has("series"):
		m["series"] = {}
	var all: Dictionary = m["series"]
	if not all.has(name):
		all[name] = []
	var arr: Array = all[name]
	arr.append([int(sim.state["tick"]), snappedf(value, 0.01)])
	var cap: int = int(sim.bal["series"]["max_points"])
	while arr.size() > cap:
		arr.pop_front()

func _sample_series(f: Dictionary) -> void:
	var u = sim.util
	var o2_stock := 0.0
	var o2_make := 0
	var o2_use := 0
	for comp in u.atmo_stats:
		var a: Dictionary = u.atmo_stats[comp]
		o2_stock += u.units(int(a["stock"]))
		o2_make += int(a["make"])
		o2_use += int(a["breathe"])
	var w_stock := 0.0
	var w_in := 0
	var w_out := 0
	for comp in u.water_stats:
		var w: Dictionary = u.water_stats[comp]
		w_stock += u.units(int(w["stock"]))
		w_in += int(w["in"])
		w_out += int(w["out"])
	var gen := 0
	var use := 0
	for comp in u.power_stats:
		gen += int(u.power_stats[comp]["gen"])
		use += int(u.power_stats[comp]["served"])
	_push("pop", float(f["pop"]))
	_push("morale", avg_morale())
	_push("nutrition", float(sim.nutrition.colony()["score"]))
	_push("o2_stock", o2_stock)
	_push("o2_make", u.to_rate(o2_make))
	_push("o2_use", u.to_rate(o2_use))
	_push("water_stock", w_stock)
	_push("water_in", u.to_rate(w_in))
	_push("water_out", u.to_rate(w_out))
	_push("power_gen", u.to_rate(gen))
	_push("power_use", u.to_rate(use))
	_push("energy", float(f["energy"]))
	_push("food_days", float(f["meal_days"]))
	_push("rp_rate", sim.research.rp_rate())
	_push("ship_readiness", float(sim.state["ship"].get("readiness", 0.0)))

## Every item the colony has ever had gets a series of its total stock.
func _sample_items() -> void:
	var totals: Dictionary = sim.inv.totals()
	var ids: Array = sim.state["ledger"].keys()
	ids.sort()
	for id in ids:
		_push("item:%s" % id, float(totals.get(id, {}).get("total", 0)))

## One row per day: what was made, used and lost that day (from the lifetime counters).
func _daily_row() -> void:
	var m: Dictionary = sim.state["metrics"]
	var st: Dictionary = sim.state["stats"]
	var prev: Dictionary = m.get("daily_prev", {"produced": {}, "consumed": {}, "spoiled": {}})
	var row := {"day": sim.util.day_number() - 1, "pop": sim.alive_count(), "deaths": int(sim.state["progress"]["deaths"])}
	for key in ["produced", "consumed", "spoiled"]:
		var d := {}
		var cur: Dictionary = st.get(key, {})
		var old: Dictionary = prev.get(key, {})
		for k in cur:
			var n: int = int(cur[k]) - int(old.get(k, 0))
			if n != 0:
				d[k] = n
		row[key] = d
	if not m.has("daily"):
		m["daily"] = []
	var daily: Array = m["daily"]
	daily.append(row)
	while daily.size() > 120:
		daily.pop_front()
	m["daily_prev"] = {"produced": (st.get("produced", {}) as Dictionary).duplicate(),
		"consumed": (st.get("consumed", {}) as Dictionary).duplicate(),
		"spoiled": (st.get("spoiled", {}) as Dictionary).duplicate()}

## Spoilage is summed up once per day in the log, not unit by unit.
func _spoil_summary() -> void:
	var st: Dictionary = sim.state["stats"]
	var today: Dictionary = st.get("spoiled_today", {})
	st["spoiled_yesterday"] = today.duplicate()
	if today.is_empty():
		return
	var total := 0
	for k in today:
		total += int(today[k])
	var text: String = "%s spoiled yesterday: %s." % [Text.n(total, "unit"), sim.items.list_text(today)]
	if not sim.research.is_done("log_1"):
		text += " Research Cold Chain for cold storage."
	else:
		text += " Cold storage keeps food fresh."
	sim.log_event("spoiled", text, [], 1)
	st["spoiled_today"] = {}

## The causal history shown when the colony is lost (spec 3, acceptance 14).
func failure_report() -> Dictionary:
	var lines: Array = []
	for e in sim.state["log"]:
		if int(e["sev"]) >= 2 or e["code"] == "death":
			lines.append(e)
	if lines.size() > 40:
		lines = lines.slice(lines.size() - 40)
	var causes := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "dead":
			causes[a["cause"]] = int(causes.get(a["cause"], 0)) + 1
	return {"day": sim.util.day_number(), "causes": causes, "events": lines}
