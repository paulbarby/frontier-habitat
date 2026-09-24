extends RefCounted
## Alerts with causality (spec 12, acceptance 11). Once per second every problem in the
## colony is found again as an "issue" with a stable key. An issue may name its cause
## (another issue key). The interface shows root issues as incidents and hangs the
## consequences under them, so one power loss is one incident, not five popups.
## Each issue answers: what is failing, why, how long is left, what can the player do.

const Text = preload("res://sim/text.gd")
const Hazards = preload("res://sim/hazards.gd")

var sim

func _init(s) -> void:
	sim = s

func tick_second() -> void:
	var found := {}
	_power_issues(found)
	_water_issues(found)
	_air_issues(found)
	_building_issues(found)
	_people_issues(found)
	_supply_issues(found)
	_nutrition_issues(found)
	_progress_issues(found)
	_hazard_issues(found)
	_merge(found)

func _add(found: Dictionary, key: String, code: String, severity: int, text: String, action: String, entities: Array, cause: String = "", forecast: float = -1.0, count: int = 1) -> void:
	found[key] = {"key": key, "code": code, "severity": severity, "text": text, "action": action,
		"entities": entities, "cause": cause, "forecast": forecast, "count": count}

## Hysteresis (docs/V3_DESIGN.md section 2). A condition must be true for raise_after
## seconds (by severity: notice 20, warning 5, critical 0) before its alert shows, and
## false for clear_after (30) seconds before the alert goes. Short gaps do not reset the
## wait. A kept alert keeps its first tick. state.alert_track = {key: {since, last}}:
## since = first tick of the current run of the condition, last = last tick it was true.
## Each shown issue has "live": false while its condition is off but not yet cleared.
func _merge(found: Dictionary) -> void:
	var issues: Dictionary = sim.state["issues"]
	if not sim.state.has("alert_track"):
		sim.state["alert_track"] = {}
	var track: Dictionary = sim.state["alert_track"]
	var tick: int = int(sim.state["tick"])
	var hz: int = int(sim.bal["tick_hz"])
	var cfg: Dictionary = sim.bal.get("alerts", {})
	var clear_ticks: int = int(float(cfg.get("clear_after", 30)) * hz)
	var raise_after: Array = cfg.get("raise_after", [20, 20, 5, 0])
	for key in found:
		var tr = track.get(key)
		if tr == null:
			track[key] = {"since": tick, "last": tick}
		else:
			tr["last"] = tick
	for key in track.keys():
		if found.has(key):
			continue
		if tick - int(track[key]["last"]) >= clear_ticks:
			track.erase(key)
			issues.erase(key)
	for key in issues.keys():
		if not track.has(key):
			issues.erase(key)
		elif not found.has(key):
			issues[key]["live"] = false
	for key in found:
		var f: Dictionary = found[key]
		f["live"] = true
		if issues.has(key):
			f["first_tick"] = issues[key]["first_tick"]
			f["ack"] = issues[key]["ack"]
			issues[key] = f
			continue
		var sev: int = clampi(int(f["severity"]), 0, raise_after.size() - 1)
		var since: int = int(track[key]["since"])
		if tick - since < int(float(raise_after[sev]) * hz):
			continue
		f["first_tick"] = since
		f["ack"] = false
		if int(f["severity"]) >= 2 and (f["cause"] == "" or not found.has(f["cause"])):
			sim.log_event("alert", f["text"], f["entities"], int(f["severity"]))
		issues[key] = f

func _bname(b: Dictionary) -> String:
	var def: Dictionary = sim.bdef(b["def"])
	return "%s %s" % [sim.topo.district_name(b["pos"]), String(def["name"]).to_lower()]

# ---------------------------------------------------------------- power
func _power_issues(found: Dictionary) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var night_left: float = sim.util.seconds_to_sunrise()
	var day_len: float = float(sim.bal["day_length"])
	var orphans: Array = []
	for comp in sim.util.power_stats:
		var ps: Dictionary = sim.util.power_stats[comp]
		var shed: Array = ps["shed"]
		if not blds.has(comp):
			continue
		var root: Dictionary = blds[comp]
		var district: String = sim.topo.district_name(root["pos"])
		var key := "power:%d" % comp
		if not shed.is_empty() and not bool(ps["has_source"]):
			# Finished but not joined to any generator: one shared notice, not one per structure.
			orphans.append_array(shed)
			continue
		if not shed.is_empty():
			var text: String = "%s district: power shortage. Demand %.1f P, supply %.1f P, %.1f E stored. %s %s off." % [
				district, sim.util.to_rate(ps["demand"]), sim.util.to_rate(ps["gen"]), sim.util.units(ps["stored"]), Text.n(shed.size(), "structure"), Text.be(shed.size())]
			var action := "Add generation or batteries, or switch off low-priority structures."
			var life := 0
			for bid in shed:
				if sim.bdef(blds[bid]["def"]).get("power_class", "") == "life_support":
					life += 1
			_add(found, key, "power_short", 3 if life > 0 else 2, text, action, shed.duplicate(), "", -1.0, shed.size())
		elif int(ps["cap"]) > 0 and int(ps["demand"]) > 0:
			# Forecast: will the batteries last until sunrise? (spec 12 example)
			var dark: float = night_left if night_left > 0.0 else float(day_len - float(sim.planet["daylight_seconds"]))
			var wind_now: int = 0
			for bid in sim.topo.power_members[comp]:
				var d: Dictionary = sim.bd(blds[bid])
				if d.has("gen_wind") and blds[bid]["state"] == "active":
					wind_now += sim.util.rt(float(d["gen_wind"]) * float(sim.planet["wind_avg"]) * 0.5)
				if d.has("gen_const") and blds[bid]["state"] == "active":
					wind_now += sim.util.rt(float(d["gen_const"]))
			var need_e: float = maxf(0.0, sim.util.to_rate(int(ps["critical"]) - wind_now)) * dark / day_len
			var have_e: float = sim.util.units(ps["stored"])
			var soon: bool = night_left > 0.0 or sim.util.seconds_to_sunset() < 90.0
			if soon and need_e > have_e + 0.05:
				_add(found, "forecast:%d" % comp, "power_forecast", 2,
					"%s district: %.1f E stored; %.1f E needed for life support before sunrise." % [district, have_e, need_e],
					"Build another battery, or add a wind turbine: it works at night.", [comp], "", night_left)
	if not orphans.is_empty():
		var people_inside := false
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "alive" and a["where"] != "out" and orphans.has(int(a["bld"])):
				people_inside = true
		_add(found, "power:orphans", "no_source", 3 if people_inside else 1,
			"%s %s no power source on %s network: %s." % [Text.n(orphans.size(), "finished structure"), Text.have(orphans.size()), "its" if orphans.size() == 1 else "their", _names(orphans)],
			"Join them to a solar array, wind turbine or battery with a cable or corridor.", orphans, "", -1.0, orphans.size())

func _names(ids: Array) -> String:
	var blds: Dictionary = sim.state["buildings"]
	var out: Array = []
	for id in ids.slice(0, 3):
		out.append(String(blds[id]["name"]))
	var s: String = ", ".join(out)
	if ids.size() > 3:
		s += " and %d more" % (ids.size() - 3)
	return s

# ---------------------------------------------------------------- water
func _water_issues(found: Dictionary) -> void:
	var blds: Dictionary = sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if b["state"] != "active":
			continue
		var def: Dictionary = sim.bdef(b["def"])
		if (def.has("water_out") or def.has("recycle_per_day")) and b["block"] == "no_reservoir":
			_add(found, "noreservoir:%d" % id, "no_reservoir", 2, "%s has no reservoir on its network. The water is lost." % _bname(b),
				"Join a reservoir to it with a cable.", [id])
		if b["block"] == "no_water":
			var cause := ""
			var comp: int = int(sim.topo.power_comp.get(id, -1))
			cause = _water_root(found, comp)
			if cause.begins_with("nowater:"):
				cause = ""
			var why: String = "its network has no water"
			if comp != -1 and sim.util._reservoirs(comp).is_empty():
				why = "no reservoir is joined to it"
			_add(found, "nowater:%d" % id, "no_water", 3 if def.has("o2_out") else 2,
				"%s stopped: %s." % [_bname(b), why], "Check the water extractor, its power and the cable to this structure.", [id], cause)

# ---------------------------------------------------------------- air
func _air_issues(found: Dictionary) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var day_len: float = float(sim.bal["day_length"])
	for comp in sim.util.atmo_stats:
		var st: Dictionary = sim.util.atmo_stats[comp]
		if bool(st.get("lander", false)):
			continue
		if not blds.has(comp):
			continue
		var root: Dictionary = blds[comp]
		var district: String = sim.topo.district_name(root["pos"])
		var make: float = sim.util.to_rate(st["make"])
		var use: float = sim.util.to_rate(st["breathe"])
		if int(st["people"]) > 0 and not bool(st["supplied"]):
			var cause := ""
			for bid in sim.topo.atmo_members[comp]:
				if found.has("nowater:%d" % bid):
					cause = "nowater:%d" % bid
			if cause == "" and found.has("power:%d" % int(sim.topo.power_comp.get(comp, -1))):
				cause = "power:%d" % int(sim.topo.power_comp.get(comp, -1))
			_add(found, "noair:%d" % comp, "no_air", 3, "%s district: no oxygen. %s %s on suit air." % [district, Text.n(int(st["people"]), "person", "people"), Text.be(int(st["people"]))],
				"Get an oxygen plant running on this group of rooms, or move people to supplied rooms.", sim.topo.atmo_members[comp].duplicate(), cause, -1.0, int(st["people"]))
		elif int(st["people"]) > 0 and use > make and int(st["cap"]) > 0:
			var secs: float = sim.util.units(st["stock"]) / maxf(0.001, use - make) * day_len
			if secs < 240.0:
				_add(found, "lowair:%d" % comp, "low_air", 2, "%s district: oxygen falls. %s %s %.1f per day, plants make %.1f." % [district, Text.n(int(st["people"]), "person", "people"), Text.s(int(st["people"]), "breathe"), use, make],
					"Add an oxygen plant, or check its power and water.", sim.topo.atmo_members[comp].duplicate(), "", secs, int(st["people"]))
	var left: float = sim.util.lander_seconds_left()
	var lid: int = int(sim.state["lander_id"])
	if blds.has(lid) and left < day_len * 1.5:
		var inside := 0
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "alive" and (int(a["bed"]) == lid or int(a["bed"]) == -1):
				inside += 1
		if inside > 0 or left > 0.0:
			var sev: int = 3 if left < day_len * 0.5 else 2
			var text: String = "The lander air ends in %s. %s still %s there." % [_clock(left), Text.n(inside, "person", "people"), Text.s(inside, "sleep")]
			if left <= 0.0:
				text = "The lander air has ended. %s %s no other bed." % [Text.n(inside, "person", "people"), Text.have(inside)]
			if inside > 0:
				_add(found, "lander_expiry", "lander_expiry", sev, text, "Finish an airlock, a habitat and an oxygen plant, joined by corridors.", [lid], "", left, inside)

# ---------------------------------------------------------------- structures
func _building_issues(found: Dictionary) -> void:
	var blds: Dictionary = sim.state["buildings"]
	var names: Dictionary = sim.bal["resource_names"]
	var far: Array = []
	var full: Array = []
	for id in blds:
		var b: Dictionary = blds[id]
		var block: String = b["block"]
		if block == "suit_range":
			far.append(id)
		if b["state"] == "active" and block == "output_blocked":
			full.append(id)
		if (b["state"] == "blueprint" or b["def"] == "meridian") and block.begins_with("materials:"):
			var res: String = block.substr(10)
			_add(found, "materials:%s" % res, "materials", 1, "Construction waits for %s. None is free in storage." % String(names.get(res, res)).to_lower(),
				"Produce or unload more, or cancel a plan to free its reserved stock.", [id])
		var u: Dictionary = b.get("upgrade", {})
		if not u.is_empty() and String(u.get("block", "")).begins_with("materials:"):
			var ures: String = String(u["block"]).substr(10)
			_add(found, "materials:%s" % ures, "materials", 1, "An upgrade waits for %s. None is free in storage." % String(names.get(ures, ures)).to_lower(),
				"Produce more, or cancel the upgrade.", [id])
		elif block == "unreachable":
			_add(found, "unreachable:%d" % id, "unreachable", 2, "%s cannot be reached on foot within suit range." % b["name"],
				"Build closer to an airlock, or clear the route.", [id])
		elif b["state"] == "broken":
			var item: String = sim.hazards.repair_item(b)
			var wr: Dictionary = sim.hazards.hs()["wear"].get(int(id), {})
			var why: String = " (%s fault)" % wr["fault"] if bool(wr.get("broken", false)) else ""
			_add(found, "broken:%d" % id, "broken", 3 if sim.bdef(b["def"]).get("category", "") == "life_support" else 2,
				"%s is broken%s." % [_bname(b), why],
				("A technician repairs it with %s." % sim.items.amount(item, 1)) if block != "no_spares" else ("No %s is free. Make or buy some." % sim.items.name_of(item).to_lower()), [id])
		if b["state"] == "active" and not (b["trays"] as Array).is_empty() and (block == "no_power" or block == "no_water"):
			var secs: float = sim.prod.crop_risk_seconds(b)
			if secs >= 0.0:
				var growing := 0
				for tray in b["trays"]:
					if tray["state"] == "growing":
						growing += 1
				var cause := ""
				var comp: int = int(sim.topo.power_comp.get(id, -1))
				if block == "no_power" and found.has("power:%d" % comp):
					cause = "power:%d" % comp
				elif block == "no_power" and found.has("power:orphans") and (found["power:orphans"]["entities"] as Array).has(id):
					cause = "power:orphans"
				elif block == "no_water":
					cause = _water_root(found, comp)
				var why: String = "no power" if block == "no_power" else ("no water connection" if comp == -1 or sim.util._reservoirs(comp).is_empty() else "no water")
				_add(found, "crop:%d" % id, "crop_risk", 2, "%s stopped: %s. %s at risk in %s." % [_bname(b), why, Text.n(growing, "tray"), Text.n(int(secs), "second")],
					"Restore supply before the timer ends and the crop lives.", [id], cause, secs, growing)
	_range_and_storage(found, far, full)

func _range_and_storage(found: Dictionary, far: Array, full: Array) -> void:
	if not far.is_empty():
		var reach: int = int(sim.agents.suit_reach_metres())
		_add(found, "range", "suit_range", 2,
			"%s %s too far from an airlock with air: %s. Nobody can work there and walk back on one suit." % [Text.n(far.size(), "planned structure"), Text.be(far.size()), _names(far)],
			"Build an airlock nearer to them (within about %d m on foot), joined by corridors to rooms with air. The lander hatch stops counting when its air ends." % reach,
			far, "", -1.0, far.size())
	if not full.is_empty():
		# One alert for every machine whose output buffer is full (V3_DESIGN section 2).
		# The key does not change when machines join or leave the list.
		_add(found, "output_blocked", "output_blocked", 1,
			"Output blocked at %s: %s. %s output %s full." % [Text.n(full.size(), "machine"), _names(full), "Its" if full.size() == 1 else "Their", "buffer is" if full.size() == 1 else "buffers are"],
			"Build a storehouse or free some carriers.", full.duplicate(), "", -1.0, full.size())
		var free := 0
		var stores := 0
		for inv_id in sim.state["inventories"]:
			var inv: Dictionary = sim.state["inventories"][inv_id]
			if inv["role"] == "store" and inv["ot"] == "b" and int(inv["oid"]) != int(sim.state["lander_id"]):
				stores += 1
				free += sim.inv.free_space(inv_id)
		if stores == 0 or free <= 2:
			_add(found, "storage_full", "storage_full", 2,
				"Storage is full (%s). %s cannot put %s output anywhere: %s." % [Text.n(stores, "storehouse"), Text.n(full.size(), "machine"), "its" if full.size() == 1 else "their", _names(full)],
				"Build another storehouse and join it to the base with a corridor.", full, "", -1.0, full.size())

func _water_root(found: Dictionary, comp: int) -> String:
	if comp == -1:
		return ""
	var blds: Dictionary = sim.state["buildings"]
	for key in ["power:%d" % comp, "power:orphans"]:
		if not found.has(key):
			continue
		for sid in found[key]["entities"]:
			if sim.bdef(blds[sid]["def"]).has("water_out") and int(sim.topo.power_comp.get(sid, -2)) == comp:
				return key
	for bid in sim.topo.power_members.get(comp, []):
		if found.has("nowater:%d" % bid):
			return "nowater:%d" % bid
	return ""

# ---------------------------------------------------------------- people
func _people_issues(found: Dictionary) -> void:
	var crit: float = float(sim.bal["need_critical"])
	var hungry: Array = []
	var thirsty: Array = []
	var rescue: Array = []
	var hurt: Array = []
	# A colonist who is on the way to food or water, or drinking first, is being served:
	# only one who stays critical without such a plan for about 12 s is reported.
	var grace: float = 2.0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var kind: String = String(a["plan_kind"])
		var busy_need: bool = kind == "eat" or kind == "drink" or kind == "safety"
		if float(a["hunger"]) >= crit + grace and not busy_need:
			hungry.append(aid)
		if float(a["thirst"]) >= crit + grace and not busy_need:
			thirsty.append(aid)
		if bool(a["rescue"]):
			rescue.append(aid)
		if float(a["health"]) < 50.0:
			hurt.append(aid)
	if not rescue.is_empty():
		var a: Dictionary = sim.state["agents"][rescue[0]]
		_add(found, "rescue", "rescue", 3, "%s cannot reach any room with air. Suit air: %s." % [a["name"], Text.n(int(a["suit"]), "second")],
			"Every route to a supplied airlock failed. Restore oxygen or build an airlock in reach.", rescue, "", float(a["suit"]), rescue.size())
	if not hungry.is_empty():
		var meals: int = int(sim.metrics.forecast()["meals"])
		var text: String = "%s %s starving." % [Text.n(hungry.size(), "colonist"), Text.be(hungry.size())]
		var action := "Cook dishes: a kitchen needs crops, power and an operator."
		if meals > 0:
			text += " %s of food %s, but %s cannot reach it." % [Text.n(meals, "unit"), "exists" if meals == 1 else "exist", "this colonist" if hungry.size() == 1 else "they"]
			action = "Check that food is in a room with air that people can walk to."
		_add(found, "starving", "starving", 3, text, action, hungry, "", -1.0, hungry.size())
	if not thirsty.is_empty():
		_add(found, "thirsty", "thirsty", 3, "%s %s no water to drink." % [Text.n(thirsty.size(), "colonist"), Text.have(thirsty.size())],
			"A habitat or kitchen tap needs a reservoir with water on its network.", thirsty, "", -1.0, thirsty.size())
	if not hurt.is_empty():
		_add(found, "hurt", "hurt", 2, "%s %s badly hurt." % [Text.n(hurt.size(), "colonist"), Text.be(hurt.size())], "Build a medical bay. Remove the cause first.", hurt, "", -1.0, hurt.size())
	var blds: Dictionary = sim.state["buildings"]
	var unsafe: float = float(sim.bal["airlock_unsafe_wait_seconds"])
	for id in blds:
		var lock: Dictionary = blds[id]["lock"]
		if lock.is_empty():
			continue
		var outside := 0
		var worst := 1e9
		for q in lock["queue"]:
			if q["dir"] == "in":
				outside += 1
				worst = minf(worst, float(sim.state["agents"][q["a"]]["suit"]))
		var wait: float = ceil(float(outside) / float(sim.bal["airlock_slots"])) * float(sim.bal["airlock_cycle_seconds"])
		if outside > 2 and (wait > unsafe or worst < wait + 5.0):
			_add(found, "lockjam:%d" % id, "airlock_congestion", 3 if worst < wait else 2,
				"%s: %s wait outside. The last one waits about %s; the lowest suit has %s of air." % [blds[id]["name"], Text.n(outside, "person", "people"), Text.n(int(wait), "second"), Text.n(int(worst), "second")],
				"Build a second airlock on this group of rooms.", [id], "", worst, outside)

# ---------------------------------------------------------------- supplies
func _supply_issues(found: Dictionary) -> void:
	var pop: int = sim.alive_count()
	if pop == 0:
		return
	var f: Dictionary = sim.metrics.forecast()
	if float(f["meal_days"]) < 1.0:
		_add(found, "meals_low", "meals_low", 2 if float(f["meal_days"]) > 0.4 else 3,
			"Food for %.1f days remains (%s, %s)." % [f["meal_days"], Text.n(int(f["meals"]), "dish", "dishes"), Text.n(pop, "person", "people")],
			"Grow crops in a greenhouse and cook them in a kitchen.", [], "", float(f["meal_days"]) * float(sim.bal["day_length"]))
	if float(f["water_days"]) < 0.75:
		_add(found, "water_low", "water_low", 2 if float(f["water_days"]) > 0.3 else 3,
			"Drinking water for %.1f days remains." % f["water_days"],
			"Run a water extractor with power, joined to a reservoir.", [], "", float(f["water_days"]) * float(sim.bal["day_length"]))
	# Early material deadlock (spec 17): the stock of a building material is gone and the
	# colony has no way to make more. The player must see this before everything stops.
	var totals: Dictionary = sim.inv.totals()
	var blds: Dictionary = sim.state["buildings"]
	for res in ["metal", "polymer"]:
		var have: int = int(totals.get(res, {}).get("total", 0))
		if have > 2:
			continue
		var maker := ""
		var chain := ""
		for id in blds:
			var rec: Dictionary = sim.prod.recipe_of(blds[id])
			if not rec.is_empty() and rec["outputs"].has(res):
				maker = String(blds[id]["state"])
		if res == "metal":
			chain = "A mine on a mineral deposit makes ore; a refinery turns 2 ore into 1 metal."
		else:
			chain = "A greenhouse makes biomass with its harvest; a polymer plant turns 2 biomass into 1 polymer."
		if maker == "":
			_add(found, "deadlock:%s" % res, "material_deadlock", 3 if have == 0 else 2,
				"%s is down to %d and nothing in the colony makes it. Every plan that needs it stops." % [String(sim.bal["resource_names"][res]), have],
				chain + " Build it before the last units are used.", [])
		elif maker != "active" and have == 0:
			_add(found, "deadlock:%s" % res, "material_deadlock", 2,
				"%s has run out. The plant that makes it is not finished yet." % String(sim.bal["resource_names"][res]),
				"Finish it first, or cancel a plan to get its reserved materials back.", [])
	if int(f["beds"]) < pop:
		_add(found, "beds_short", "beds_short", 1, "%s for %s." % [Text.n(int(f["beds"]), "bed"), Text.n(pop, "person", "people")], "Build a habitat.", [])

# ---------------------------------------------------------------- nutrition
const NUTRIENT_HINTS := {
	"protein": "Protein: soy stew, tofu stir-fry and algae bars. Soybeans need Crop Genetics.",
	"carbs": "Carbs: mashed potatoes, flatbread and pasta.",
	"fat": "Fat: soy stew, tofu stir-fry, veggie pizza.",
	"vitamins": "Vitamins: garden salad and greens. Tomatoes need Crop Genetics.",
}

func _nutrition_issues(found: Dictionary) -> void:
	var counts: Dictionary = sim.nutrition.shortage_counts()
	var starved := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and sim.nutrition.starved(a):
			starved += 1
	for k in sim.nutrition.nutrients():
		var n: int = int(counts.get(k, 0))
		if n <= 0:
			continue
		var sev: int = 3 if starved > 0 else 2
		var text: String = "Low %s: %s. %s work is 10%% slower and %s morale falls." % [k, Text.n(n, "colonist"), "Their" if n != 1 else "The colonist's", "their" if n != 1 else "the"]
		if starved > 0:
			text += " %s health." % [Text.n(starved, "colonist") + " " + Text.s(starved, "lose")]
		_add(found, "low_%s" % k, "low_nutrient", sev, text, String(NUTRIENT_HINTS.get(k, "Cook different dishes.")), [], "", -1.0, n)
	# Variety: most colonists eat the same dish again and again.
	var mono := 0
	var pop := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		pop += 1
		var diet: Array = a.get("diet", [])
		if diet.size() >= 3:
			var seen := {}
			for d in diet:
				seen[d] = true
			if seen.size() == 1:
				mono += 1
	if pop > 0 and mono * 2 > pop:
		_add(found, "variety", "food_variety", 1, "%s %s the same dish every time. Morale falls." % [Text.n(mono, "colonist"), Text.s(mono, "eat")],
			"Grow more kinds of crops. The kitchen cooks what its ingredients allow.", [], "", -1.0, mono)
	var yesterday: Dictionary = sim.state["stats"].get("spoiled_yesterday", {})
	if not yesterday.is_empty():
		var total := 0
		for k in yesterday:
			total += int(yesterday[k])
		_add(found, "spoiled", "spoilage", 1, "%s of food spoiled yesterday." % Text.n(total, "unit"),
			"Cold storage keeps food fresh. Cook or eat crops soon after harvest.", [], "", -1.0, total)

# ---------------------------------------------------------------- research and the ship
func _progress_issues(found: Dictionary) -> void:
	var labs := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active" and bool(sim.bdef(b["def"]).get("research_lab", false)):
			labs += 1
	if labs > 0:
		var r: Dictionary = sim.state["research"]
		if String(r["active"]) == "":
			_add(found, "research_idle", "research_idle", 1, "No research project is active. The labs are idle.",
				"Open Research and pick a project.", [])
		else:
			var need: Dictionary = sim.research.items_needed()
			if not need.is_empty():
				_add(found, "research_items", "research_items", 1, "%s needs %s at a research lab first." % [sim.content["techs"][r["active"]]["name"], sim.items.list_text(need)],
					"Exotic crystals come from a deep core drill and from supply runs.", [])
	var s: Dictionary = sim.state["ship"]
	if int(s.get("stage", 0)) >= 5 and bool(s.get("auto_runs", true)) and sim.ship.runs_unlocked() and not bool(s.get("away", false)):
		var why: String = sim.ship.run_block()
		if why == "no_comms":
			_add(found, "ship_comms", "ship_comms", 1, "The Meridian cannot fly supply runs: no comms tower works.", "Build a comms tower and give it power.", [int(s["id"])])
		elif why == "no_fuel":
			_add(found, "ship_fuel", "ship_fuel", 1, "The Meridian waits for rocket fuel before its next supply run.", "Run a fuel refinery. Carriers bring the fuel to the ship.", [int(s["id"])])
	if int(s.get("stage", 0)) >= 5 and float(s.get("readiness", 0.0)) < 50.0:
		_add(found, "ship_readiness", "ship_readiness", 2, "The Meridian's readiness is %d%%." % int(s["readiness"]),
			"Maintenance needs a technician, rocket fuel and spare parts at the ship.", [int(s["id"])])

# ---------------------------------------------------------------- hazards (v3)
func _hazard_issues(found: Dictionary) -> void:
	var hz = sim.hazards
	# Events under warning that the colony does not cover.
	for ev in hz.hs()["queue"]:
		if String(ev["phase"]) != "warning" or bool(ev["countered"]):
			continue
		var eta: int = maxi(0, int(ceil(float(int(ev["at"]) - int(sim.state["tick"])) / float(sim.bal["tick_hz"]))))
		var sev: int = 2
		if ev["kind"] == "solar_flare" and not hz.sheltered():
			sev = 3
		var place: String = "" if Hazards.WHOLE_MAP.has(String(ev["kind"])) else " near %s" % hz._place_name(ev["pos"])
		_add(found, "hazard:%d" % int(ev["id"]), "hazard", sev, "%s in %s%s." % [Hazards.NAMES[ev["kind"]], Text.n(eta, "second"), place],
			hz.advice(ev), [], "", float(eta))
	for ev in hz.hs()["active"]:
		if ev["kind"] == "solar_flare" and not hz.sheltered() and hz._people_outside() > 0:
			_add(found, "hazard:%d" % int(ev["id"]), "hazard", 3, "Solar flare: %s outside take radiation." % Text.n(hz._people_outside(), "colonist"),
				"Order Shelter: everyone goes inside.", [], "", float(int(ev["end"]) - int(sim.state["tick"])) / float(sim.bal["tick_hz"]))
	# Hull breaches: one alert for all of them.
	var blds: Dictionary = sim.state["buildings"]
	var breached: Array = []
	var inside := 0
	for id in blds:
		var b: Dictionary = blds[id]
		if bool(b.get("breach", false)) and b["state"] != "blueprint":
			breached.append(id)
	if not breached.is_empty():
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "alive" and a["where"] == "in" and breached.has(int(a["bld"])):
				inside += 1
		_add(found, "breach", "breach", 3 if inside > 0 else 2,
			"Hull breach in %s: %s. Air leaks." % [Text.n(breached.size(), "structure"), _names(breached)],
			"A technician seals a breach with 1 hull plate or 2 steel.", breached, "", -1.0, breached.size())
	# Machines near their breakdown.
	var risk: Array = hz.at_risk()
	if not risk.is_empty():
		var ids: Array = []
		for r in risk:
			ids.append(int(r["id"]))
		_add(found, "maintenance", "maintenance", 1,
			"%s %s maintenance soon: %s." % [Text.n(ids.size(), "machine"), "needs" if ids.size() == 1 else "need", _names(ids)],
			"Technicians do it with spare parts, electronics or polymer. Use Maintain now to put one first.", ids, "", float(risk[0]["eta_s"]), ids.size())
	# Dust on solar panels.
	var dusty: Array = []
	for id in blds:
		if bool(blds[id].get("dust", false)) and blds[id]["state"] == "active":
			dusty.append(id)
	if not dusty.is_empty():
		_add(found, "solar_dust", "solar_dust", 1, "Dust covers %s: half power until cleaned." % Text.n(dusty.size(), "solar array"),
			"A colonist cleans each panel. It takes a few seconds outside.", dusty, "", -1.0, dusty.size())
	if hz.sheltered():
		_add(found, "shelter", "shelter", 1, "Shelter order: everyone stays inside.", "The order ends when no flare or meteor shower is near.", [])

static func _clock(seconds: float) -> String:
	var s: int = int(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]

## Root incidents with their consequences, most severe first. Read by the interface.
func incidents() -> Array:
	var issues: Dictionary = sim.state["issues"]
	var roots: Array = []
	var children := {}
	for key in issues:
		var i: Dictionary = issues[key]
		if i["cause"] != "" and issues.has(i["cause"]):
			if not children.has(i["cause"]):
				children[i["cause"]] = []
			children[i["cause"]].append(i)
		else:
			roots.append(i)
	roots.sort_custom(func(x, y):
		if int(x["severity"]) != int(y["severity"]):
			return int(x["severity"]) > int(y["severity"])
		if int(x["first_tick"]) != int(y["first_tick"]):
			return int(x["first_tick"]) < int(y["first_tick"])
		return String(x["key"]) < String(y["key"]))
	var out: Array = []
	for r in roots:
		out.append({"issue": r, "consequences": _collect(r["key"], children)})
	return out

func _collect(key: String, children: Dictionary) -> Array:
	var out: Array = []
	for c in children.get(key, []):
		out.append(c)
		out.append_array(_collect(c["key"], children))
	return out
