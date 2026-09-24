extends SceneTree
## Developer tool: plays the full reference campaign (group "all") and prints one line a
## day: colonists, deaths, research, packs, hazards, breakdowns, breaches, chapter.
##   node tools/godot.mjs script res://tests/dev/v3_probe.gd [seed] [days] [hazards]

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var nums: Array = []
	var hz_set := "normal"
	for a in Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args()):
		if a.is_valid_int() and not nums.has(int(a)):
			nums.append(int(a))
		elif a in ["off", "mild", "normal", "hard"]:
			hz_set = a
	var seed_value: int = nums[0] if nums.size() > 0 else 1001
	var days: int = nums[1] if nums.size() > 1 else 10
	var sim = Sim.new()
	sim.new_game(seed_value, "tutorial", {"hazards": hz_set})
	var ref = Reference.new(sim, "all")
	var t0: int = Time.get_ticks_msec()
	var tick_us := 0
	var ticks := 0
	var logged := 0
	for d in days:
		for s in 600:
			if int(sim.state["tick"]) % 10 == 0:
				ref.drive()
			for k in 10:
				var u0: int = Time.get_ticks_usec()
				sim.step()
				tick_us += Time.get_ticks_usec() - u0
				ticks += 1
		var r: Dictionary = sim.state["research"]
		var h: Dictionary = sim.state["hazards"]
		print("day %d: pop %d deaths %d | chapter %d | techs %d active %s (%.0f/%s) | packs %s | hazards %s | breakdowns %d maint %d breaches %d | ship %d | audit %s | %.2f ms/tick" % [
			d + 1, sim.alive_count(), int(sim.state["progress"]["deaths"]), sim.goals.chapter() + 1, r["done"].size(), r["active"],
			float(r["progress"].get(r["active"], 0.0)), str(sim.content["techs"].get(r["active"], {}).get("cost", "-")),
			str(sim.research.pack_stock()), str(h["done_count"]), int(sim.state["stats"].get("breakdowns", 0)),
			int(sim.state["stats"].get("maintenance", 0)), int(sim.state["stats"].get("breaches_sealed", 0)),
			int(sim.state["ship"]["stage"]), str(sim.inv.audit()), float(tick_us) / 1000.0 / float(ticks)])
		tick_us = 0
		ticks = 0
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["def"] in ["research_assembler", "electronics_fab", "mine", "refinery", "workshop", "fabricator"]:
				print("    %s %s L%d block '%s' recipe %s in %s out %s" % [b["name"], b["state"], int(b.get("level", 1)), b["block"], sim.prod.recipe_id(b),
					str(sim.inv.get_inv(int(b["inv_in"])).get("items", {})), str(sim.inv.get_inv(int(b["inv_out"])).get("items", {}))])
		var o2 := []
		for comp in sim.util.atmo_stats:
			var st: Dictionary = sim.util.atmo_stats[comp]
			if bool(st.get("lander", false)):
				continue
			o2.append("comp %d: people %d make %.1f breathe %.1f stock %.1f/%.1f %s" % [comp, int(st["people"]), sim.util.to_rate(st["make"]), sim.util.to_rate(st["breathe"]), sim.util.units(st["stock"]), sim.util.units(st["cap"]), "ok" if bool(st["supplied"]) else "NO AIR"])
		print("    air: ", "; ".join(o2))
		var shed := 0
		var gen := 0.0
		var dem := 0.0
		for comp in sim.util.power_stats:
			shed += (sim.util.power_stats[comp]["shed"] as Array).size()
			gen += sim.util.to_rate(sim.util.power_stats[comp]["gen"])
			dem += sim.util.to_rate(sim.util.power_stats[comp]["demand"])
		var broken: Array = []
		var breached: Array = []
		for id in sim.state["buildings"]:
			var bb: Dictionary = sim.state["buildings"][id]
			if bb["state"] == "broken":
				broken.append(bb["name"])
			if bool(bb.get("breach", false)):
				breached.append(bb["name"])
		print("    power gen %.1f demand %.1f shed %d | broken %s | breached %s" % [gen, dem, shed, str(broken), str(breached)])
		var si: Dictionary = sim.ship.info()
		print("    ship stage %d %s phase %s progress %.0f/%.0f missing %s" % [int(si["stage"]), si["stage_name"], si["phase"], float(si["progress"]), float(si["work_total"]), str(si["missing"])])
		var roles := {}
		for aid in sim.state["agents"]:
			var ag: Dictionary = sim.state["agents"][aid]
			if ag["state"] == "alive" and ag["role"] == "technician":
				roles[ag["goal"]] = int(roles.get(ag["goal"], 0)) + 1
		print("    technicians: ", roles)
		var tot: Dictionary = sim.inv.totals()
		print("    metal produced %d consumed %d; ore produced %d; roles %s" % [int(sim.state["stats"]["produced"].get("metal", 0)), int(sim.state["stats"]["consumed"].get("metal", 0)), int(sim.state["stats"]["produced"].get("ore", 0)), str(_roles(sim))])
		print("    stock: electronics %d glass %d silicate %d metal %d spare_parts %d hull_plate %d" % [int(tot.get("electronics", {}).get("total", 0)), int(tot.get("glass", {}).get("total", 0)),
			int(tot.get("silicate", {}).get("total", 0)), int(tot.get("metal", {}).get("total", 0)), int(tot.get("spare_parts", {}).get("total", 0)), int(tot.get("hull_plate", {}).get("total", 0))])
		var log: Array = sim.state["log"]
		for e in log:
			if int(e["tick"]) <= logged:
				continue
			if e["code"] in ["death", "hazard_impact", "fault", "breach", "hazard_intercepted", "research", "chapter", "survey", "broken"]:
				print("    t=%d %s: %s" % [int(e["tick"]) / 10, e["code"], e["text"]])
		logged = int(sim.state["tick"])
	for c in sim.state["commands"]:
		if not c["ok"]:
			print("  REFUSED command: ", c["kind"], " ", c["payload"], " -> ", c["code"])
	for f in ref.failures:
		print("  REFERENCE: ", f)
	print("wall %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)

func _roles(sim) -> Dictionary:
	var r := {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			r[a["role"]] = int(r.get(a["role"], 0)) + 1
	return r
