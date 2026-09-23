extends SceneTree
## Developer tool: plays the full reference campaign (group "all") and prints one line per
## day, plus the day each goal and chapter completes.
##   node tools/godot.mjs script res://tests/dev/campaign.gd [seed] [days] [every_s]

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var days: float = float(args[1]) if args.size() > 1 else 25.0
	var every: int = int(args[2]) if args.size() > 2 else 600
	var t0: int = Time.get_ticks_msec()
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	var total: int = int(days * 600)
	var seen_goals := {}
	var seen_awards := {}
	var seen_tech := {}
	var chapter_days := {}
	for s in total:
		ref.drive()
		sim.run_seconds(1.0)
		for id in sim.state["goals"]["status"]:
			var gs: Dictionary = sim.state["goals"]["status"][id]
			if gs["state"] == "done" and not seen_goals.has(id):
				seen_goals[id] = true
				print("   GOAL %-16s day %.2f" % [id, float(int(gs["done_tick"])) / 6000.0 + 1.0])
		if not chapter_days.has(sim.goals.chapter()):
			chapter_days[sim.goals.chapter()] = sim.util.days_elapsed() + 1.0
			print("   CHAPTER %d opens day %.2f" % [sim.goals.chapter() + 1, sim.util.days_elapsed() + 1.0])
		for id in sim.state["research"]["done"]:
			if not seen_tech.has(id):
				seen_tech[id] = true
				print("   TECH %-10s day %.2f" % [id, sim.util.days_elapsed() + 1.0])
		for id in sim.state["awards"]:
			if not seen_awards.has(id):
				seen_awards[id] = true
		if (s + 1) % every == 0:
			_report(sim)
	for e in sim.state["log"]:
		if e["code"] in ["death", "crop_lost", "broken", "unreachable"]:
			print("  LOG t=%d %s" % [int(e["tick"]) / 10, e["text"]])
	for f in ref.failures:
		print("  REF FAILURE: ", f)
	for c in sim.state["commands"]:
		if not c["ok"]:
			print("  REFUSED: ", c["kind"], " ", c["payload"], " -> ", c["code"])
	print("awards: ", seen_awards.keys())
	print("audit: ", sim.inv.audit())
	var ms: int = Time.get_ticks_msec() - t0
	print("wall %d ms, %.3f ms/tick, %d buildings, %d alive" % [ms, float(ms) / float(total * 10), sim.state["buildings"].size(), sim.alive_count()])
	quit(0)

func _report(sim) -> void:
	var f: Dictionary = sim.metrics.forecast()
	var tot: Dictionary = sim.inv.totals()
	var nut: Dictionary = sim.nutrition.colony()
	var roles := {}
	var hp := 0.0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			roles[a["role"].substr(0, 3)] = int(roles.get(a["role"].substr(0, 3), 0)) + 1
			hp += float(a["health"])
	var food: Array = []
	for d in sim.items.dishes():
		var n: int = int(tot.get(d, {}).get("total", 0))
		if n > 0:
			food.append("%s %d" % [d.substr(0, 6), n])
	var crops: Array = []
	for c in sim.items.crops():
		var n2: int = int(tot.get(c, {}).get("total", 0))
		if n2 > 0:
			crops.append("%s %d" % [c.substr(0, 4), n2])
	var mats: Array = []
	for m in ["metal", "polymer", "ore", "silicate", "glass", "electronics", "hull_plate", "composite", "rocket_fuel", "spare_parts", "biomass", "exotic", "medicine"]:
		var n3: int = int(tot.get(m, {}).get("total", 0))
		if n3 > 0:
			mats.append("%s %d" % [m.substr(0, 5), n3])
	var pr: Dictionary = sim.state["stats"]["produced"]
	print("d%.1f pop %d hp %.0f mor %.0f | nut P%.0f C%.0f F%.0f V%.0f s%.0f | ch %d stage %d | rp %s %.0f/d | ship %d | water %.0f | E %.1f/%.0f" % [
		sim.util.days_elapsed() + 1.0, f["pop"], hp / maxf(1.0, float(f["pop"])), sim.metrics.avg_morale(),
		nut["protein"], nut["carbs"], nut["fat"], nut["vitamins"], nut["score"], sim.goals.chapter() + 1,
		int(sim.state["progress"]["stage"]), sim.state["research"]["active"], sim.research.rp_rate(),
		int(sim.state["ship"]["stage"]), f["water"], f["energy"], f["energy_cap"]])
	print("      roles %s | food %s | crops %s" % [roles, ", ".join(food), ", ".join(crops)])
	print("      mats %s | made metal %d elec %d hull %d | spoiled %s" % [", ".join(mats), int(pr.get("metal", 0)), int(pr.get("electronics", 0)), int(pr.get("hull_plate", 0)), sim.state["stats"]["spoiled"]])
	var inc: Array = sim.alerts.incidents()
	var texts: Array = []
	for i in inc:
		if int(i["issue"]["severity"]) >= 2:
			texts.append(String(i["issue"]["text"]).substr(0, 90))
	if not texts.is_empty():
		print("      ALERTS: ", " || ".join(texts.slice(0, 4)))
	var plans: Array = []
	var ups: Array = []
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "link":
			continue
		if b["state"] != "active":
			plans.append("%s[%s %s]" % [b["name"], b["state"].substr(0, 5), b["block"]])
		elif not (b.get("upgrade", {}) as Dictionary).is_empty():
			ups.append("%s->L%d %s %s" % [b["name"], int(b["upgrade"]["to"]), b["upgrade"]["state"], b["upgrade"].get("block", "")])
	if not plans.is_empty():
		print("      PLANS: ", ", ".join(plans))
	if not ups.is_empty():
		print("      UPGRADES: ", ", ".join(ups))
	var air: Array = []
	for comp in sim.util.atmo_stats:
		var a: Dictionary = sim.util.atmo_stats[comp]
		if bool(a.get("lander", false)):
			continue
		air.append("%s: %s %.1f/%.1f +%.1f -%.1f n%d" % [sim.topo.district_name(sim.state["buildings"][comp]["pos"]), "ok" if a["supplied"] else "NO", sim.util.units(a["stock"]), sim.util.units(a["cap"]), sim.util.to_rate(a["make"]), sim.util.to_rate(a["breathe"]), int(a["people"])])
	var pw: Array = []
	for comp in sim.util.power_stats:
		var p: Dictionary = sim.util.power_stats[comp]
		pw.append("%s: gen %.0f dem %.0f E %.1f/%.0f shed %d" % [sim.topo.district_name(sim.state["buildings"][comp]["pos"]), sim.util.to_rate(p["gen"]), sim.util.to_rate(p["demand"]), sim.util.units(p["stored"]), sim.util.units(p["cap"]), (p["shed"] as Array).size()])
	print("      AIR ", " | ".join(air), "   POWER ", " | ".join(pw))
	var doing := {}
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "alive":
			var gl: String = String(ag["goal"]).split(" ")[0]
			doing[gl] = int(doing.get(gl, 0)) + 1
	print("      DOING ", doing)
	var si: Dictionary = sim.ship.info()
	print("      SHIP stage %d %s phase %s prog %.0f/%.0f program %s delivered %s missing %s block '%s'" % [si["stage"], si["stage_name"], si["phase"], si["progress"], si["work_total"], si["program"], str(si["delivered"]), str(si["missing"]), String(sim.ship.record().get("block", ""))])
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["def"] in ["mine", "refinery", "polymer_plant", "glassworks", "electronics_fab", "fabricator", "workshop", "regolith_harvester", "research_lab"] and b["state"] == "active":
			var inv_in: Dictionary = sim.inv.get_inv(b["inv_in"]).get("items", {}) if int(b["inv_in"]) != -1 else {}
			var inv_out: Dictionary = sim.inv.get_inv(b["inv_out"]).get("items", {}) if int(b["inv_out"]) != -1 else {}
			var workers := 0
			for aid in sim.state["agents"]:
				var ag: Dictionary = sim.state["agents"][aid]
				if ag["state"] == "alive" and int(ag["task"]) != -1 and sim.state["tasks"].has(int(ag["task"])) and int(sim.state["tasks"][int(ag["task"])]["bld"]) == int(id) and sim.state["tasks"][int(ag["task"])]["kind"] in ["operate", "research"]:
					workers += 1
			print("      MACHINE %s L%d block '%s' pow %s batch %.0f/%.0f in %s out %s workers %d" % [b["name"], int(b["level"]), b["block"], str(b["powered"]), float(b["batch"].get("progress", 0)), float(b["batch"].get("work", 0)), str(inv_in), str(inv_out), workers])
		if b["def"] == "kitchen" and b["state"] == "active":
			print("      KITCHEN %s L%d block '%s' batch %s in %s out %s" % [b["name"], int(b["level"]), b["block"], str(b["batch"].get("dish", "-")), str(sim.inv.get_inv(b["inv_in"])["items"]), str(sim.inv.get_inv(b["inv_out"])["items"])])
		if (b["def"] == "greenhouse" or b["def"] == "fungus_farm") and b["state"] == "active":
			var trays: Array = []
			for tr in b["trays"]:
				trays.append("%s:%s" % [String(tr.get("grow", "")).substr(0, 4) if tr["state"] != "empty" else String(tr.get("crop", "")).substr(0, 4) + "?", tr["state"].substr(0, 4)])
			print("      GREENHOUSE %s S%d %s block '%s' out %s" % [b["name"], int(b["size"]), " ".join(trays), b["block"], str(sim.inv.get_inv(b["inv_out"])["items"])])
