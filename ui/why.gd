extends RefCounted
## "Why is this stopped?" (V4_DESIGN §6): a plain answer and the fix, for every structure and every
## colonist, from the simulation state only (read, never written).
##   Why.structure(hud, b) -> {stopped: bool, title, why: [lines], fix: [lines], color}
##   Why.agent(hud, a)     -> the same for a colonist
## The codes are SIM's (`b.block`, `b.state`, agent needs and goal); a code the UI does not know yet
## is shown by name, so nothing is ever silent.

const P = preload("res://ui/theme/palette.gd")

static func _res(hud, id: String) -> String:
	return hud.data.item_name(id).to_lower()

static func _role_name(hud, role: String) -> String:
	return String(hud.main.sim.bal.get("role_names", {}).get(role, role)).to_lower()

static func _missing_inputs(hud, b: Dictionary) -> Array:
	var s = hud.main.sim
	var out: Array = []
	if not ("prod" in s) or s.prod == null or not s.prod.has_method("recipe_of"):
		return out
	var rec: Dictionary = s.prod.recipe_of(b)
	var totals: Dictionary = hud.data.totals()
	for it in rec.get("inputs", {}):
		if hud.data.free_units(String(it), totals) < int(rec["inputs"][it]):
			out.append(_res(hud, String(it)))
	return out

## The deposit a mine stands on and what it gives (SIM sim.prod.deposit_info, milestone 5).
static func _deposit_info(hud, b: Dictionary) -> Dictionary:
	var s = hud.main.sim
	if not ("prod" in s) or s.prod == null or not s.prod.has_method("deposit_info") or not b.has("pos"):
		return {}
	for d in s.state.get("deposits", []):
		if typeof(d) == TYPE_DICTIONARY and Vector2(float(d["x"]), float(d["y"])).distance_to(b["pos"]) <= float(d.get("r", 0.0)) + float(b.get("radius", 0.0)):
			return s.prod.deposit_info(d)
	return {}

static func structure(hud, b: Dictionary) -> Dictionary:
	var s = hud.main.sim
	var def: Dictionary = s.bdef(b["def"])
	var name: String = String(b.get("name", def.get("name", "")))
	var st: String = String(b["state"])
	var blk: String = String(b.get("block", ""))
	var out := {"stopped": true, "title": "", "why": [], "fix": [], "color": P.AMBER}
	if bool(b.get("demolish", false)):
		out.title = "Being removed"
		out.why = ["A technician takes %s down. Half of its materials come back." % name]
		out.fix = ["To keep it, click Remove again on it to cancel."]
		out.color = P.RED
		return out
	if st == "blueprint":
		if blk.begins_with("materials:"):
			var item: String = blk.substr(10)
			out.title = "Waiting for " + _res(hud, item)
			out.why = ["No free %s in storage for the build. Other plans may have reserved it." % _res(hud, item)]
			out.fix = ["Make or unload %s, or cancel a plan that reserves it." % _res(hud, item)]
		elif blk == "unreachable":
			out.title = "Out of reach"
			out.why = ["No technician can walk to the site."]
			out.fix = ["Build a corridor or an airlock nearer to it."]
			out.color = P.RED
		elif blk == "suit_range":
			out.title = "Too far from an airlock"
			out.why = ["A suit runs out of air before a technician gets there and back."]
			out.fix = ["Build an airlock closer, or research longer suit air."]
			out.color = P.RED
		elif blk == "occupied":
			out.title = "Site not clear"
			out.why = ["Something stands on the site: a colonist or a pile of items."]
			out.fix = ["Building starts when the site is clear."]
		else:
			out.title = "Planned"
			out.why = ["It waits for a free technician."]
			out.fix = ["More technicians build faster. Plans build in their priority order."]
			out.color = P.CYAN
		return out
	if st == "building":
		out.title = "Under construction"
		out.why = ["%d%% done." % int(100.0 * float(b["progress"]) / maxf(1.0, float(b["work_total"])))]
		out.color = P.CYAN
		return out
	if st == "broken" or blk == "fault":
		var ww: Dictionary = hud.data.wear_of(b)
		out.title = "Broken"
		out.why = ["A fault stopped it%s." % ((" (" + String(ww.get("fault", "")).replace("_", " ") + ")") if String(ww.get("fault", "")) != "" else "")]
		out.fix = ["A technician repairs it with a spare part. Maintain machines before they fail."]
		out.color = P.RED
		return out
	if st != "active":
		out.title = st.capitalize()
		out.why = ["State: %s." % st]
		return out
	if not bool(b.get("enabled", true)) or blk == "disabled":
		out.title = "Switched off"
		out.why = ["It was switched off."]
		out.fix = ["Click Switch on."]
		out.color = P.TEXT_2
		return out
	if float(def.get("power", 0.0)) > 0.0 and not bool(b.get("powered", true)) or blk == "no_power":
		out.title = "No power"
		out.why = ["Its power network makes less than it uses, and the batteries are empty (or it has no cable)."]
		out.fix = ["Build solar, wind or batteries on its network, link it with a cable, or switch off a less important user."]
		out.color = P.RED
		return out
	if blk.begins_with("materials:"):
		var need: String = blk.substr(10)
		out.title = "Waiting for " + _res(hud, need)
		out.why = ["The next step (repair, upgrade or ship work) needs %s, and none is free in storage." % _res(hud, need)]
		out.fix = ["Make or unload %s, or buy it from a trader." % _res(hud, need)]
		return out
	match blk:
		"no_water":
			out.title = "No water"
			out.why = ["No water reaches it through its network."]
			out.fix = ["Link it to a reservoir with a pipe or cable network, and check the water extractors."]
			out.color = P.RED
		"no_reservoir":
			out.title = "No reservoir"
			out.why = ["It makes water, but no reservoir on its network can take it. The water is lost."]
			out.fix = ["Build a reservoir on the same network."]
		"no_input":
			var miss: Array = _missing_inputs(hud, b)
			out.title = "No input"
			out.why = ["It needs %s, and none is free in storage." % (", ".join(miss) if not miss.is_empty() else "its inputs")]
			out.fix = ["Make or buy the input. The inventory screen shows who makes it."]
		"output_blocked":
			out.title = "Output full"
			out.why = ["Its output buffer is full: nobody took the products away."]
			out.fix = ["Build storage, or free workers to carry items."]
		"storage_full":
			out.title = "Storage full"
			out.why = ["Every storehouse is full."]
			out.fix = ["Build a storehouse, or use or sell stock."]
		"stock_full":
			out.title = "Stock limit"
			out.why = ["The colony holds enough of its product. It waits until stock goes down."]
			out.fix = ["Nothing to do: it starts again by itself."]
			out.color = P.CYAN
			out.stopped = true
		"deposit_empty":
			out.title = "Deposit empty"
			out.why = ["The deposit under it has no ore left."]
			out.fix = ["Build a new mine on another deposit."]
			out.color = P.RED
		"no_staff":
			var role: String = String(def.get("role", ""))
			out.title = "No worker"
			out.why = ["No %s is free to work here, or none can reach it." % (_role_name(hud, role) if role != "" else "colonist")]
			out.fix = ["Bring more settlers of that role, or raise this structure's work priority."]
		"level_low":
			var need: int = 2
			if "prod" in s and s.prod != null and s.prod.has_method("recipe_of"):
				need = int(s.prod.recipe_of(b).get("min_level", 2))
			out.title = "Needs level %d" % need
			out.why = ["The recipe picked needs this structure at level %d; it is level %d." % [need, hud.data.level_of(b)]]
			out.fix = ["Upgrade it (Upgrade tab), or pick another recipe (Output tab)."]
		"deposit_locked":
			var info: Dictionary = _deposit_info(hud, b)
			var tech: String = String(info.get("research", ""))
			out.title = "Deposit locked"
			out.why = ["The deposit under it holds %s. Mining it needs research first." % (_res(hud, String(info["item"])) if info.has("item") else "a material")]
			out.fix = [("Research %s." % hud.data.tech_name(tech)) if tech != "" else "Do the research that unlocks this deposit."]
		"no_recipe":
			out.title = "No recipe"
			out.why = ["No recipe is picked."]
			out.fix = ["Pick a recipe in the Output tab."]
		"no_menu":
			out.title = "No dish"
			out.why = ["No dish on the menu can be cooked from the food in storage."]
			out.fix = ["Grow more crops, or change the menu."]
		"no_project":
			out.title = "No project"
			out.why = ["The lab has no research project."]
			out.fix = ["Pick a project on the research screen (T)."]
		"waiting_items", "no_packs":
			out.title = "No research packs"
			out.why = ["The project needs research packs, and the lab has none."]
			out.fix = ["Build a research assembler, or bring packs with a supply run."]
		"unreachable", "suit_range":
			out.title = "Out of reach"
			out.why = ["No worker can reach it with enough suit air."]
			out.fix = ["Link it with a corridor, or build an airlock nearer."]
			out.color = P.RED
		"occupied":
			out.title = "Waiting"
			out.why = ["It waits for its turn (another worker or a busy door)."]
			out.color = P.CYAN
		"":
			if String(b.get("kind", "")) == "room" and not s.util.building_supplied(b["id"]) and String(b["def"]) != "lander":
				out.title = "No air"
				out.why = ["No oxygen reaches this room."]
				out.fix = ["Link it by corridor to rooms with an oxygen plant. The air overlay (O) shows the air groups."]
				out.color = P.RED
			else:
				out.stopped = false
				out.title = "Working"
				out.color = P.GREEN
		_:
			out.title = blk.replace("_", " ").capitalize()
			out.why = ["The simulation reports \"%s\"." % blk]
	return out

static func agent(hud, a: Dictionary) -> Dictionary:
	var out := {"stopped": false, "title": "", "why": [], "fix": [], "color": P.GREEN}
	if String(a.get("state", "")) == "dead":
		out.stopped = true
		out.title = "Dead"
		out.why = ["Cause: %s." % String(a.get("cause", "unknown")).replace("_", " ")]
		out.color = P.RED
		return out
	var goal: String = String(a.get("goal", ""))
	out.title = goal if goal != "" else "Idle"
	if String(a.get("where", "")) == "vehicle":
		var vv: Dictionary = hud.v4.vehicle(int(a.get("veh", -1))) if hud.v4 != null else {}
		out.title = "Riding in " + String(vv.get("name", "a vehicle"))
		if String(vv.get("block", "")) != "":
			out.why.append("The vehicle is stopped: %s" % hud.v4.refusal_text(String(vv["block"])))
			out.color = P.AMBER
	var needs: Array = []
	if float(a.get("hunger", 0.0)) >= 70.0:
		needs.append("hungry")
	if float(a.get("thirst", 0.0)) >= 70.0:
		needs.append("thirsty")
	if float(a.get("fatigue", 0.0)) >= 80.0:
		needs.append("tired")
	if float(a.get("health", 100.0)) < 40.0:
		needs.append("hurt")
	if not needs.is_empty():
		out.why.append("Needs first: %s." % ", ".join(needs))
	if String(a.get("where", "")) == "out":
		var cap: float = maxf(1.0, float(hud.main.sim.agents.suit_cap())) if "agents" in hud.main.sim else 1.0
		if float(a.get("suit", cap)) < cap * 0.3:
			out.why.append("Suit air low: going back inside.")
			out.color = P.AMBER
	if goal == "Idle" or goal == "":
		out.stopped = true
		out.color = P.AMBER
		var fails: int = (a.get("backoff", {}) as Dictionary).size()
		out.why.append("No job for a %s now." % _role_name(hud, String(a.get("role", ""))))
		if fails > 0:
			out.why.append("%d job(s) it could not reach; it tries again soon." % fails)
			out.fix.append("Check corridors and airlocks between it and its work.")
		out.fix.append("Build work for this role, or change the priorities of structures.")
	if float(a.get("morale", 100.0)) < 30.0:
		out.why.append("Morale is low: it works slower.")
		out.fix.append("Comfort rooms, varied dishes and rest raise morale.")
	return out
