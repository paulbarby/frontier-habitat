extends SceneTree
## SIM probe: the long_v4_perf set-up; prints how and where anybody dies (exhaustion hunt).
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")
const C4 = preload("res://tests/cases_v4.gd")

func _init() -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	g.ref = Reference.new(sim, "all")
	g.run_to_tick(12 * 6000)
	sim.state["flags"]["unlock_all"] = true
	var guard := 0
	while sim.alive_count() < 100 and guard < 60:
		guard += 1
		g.cmd("admit_settlers", {"count": mini(6, 100 - sim.alive_count())})
		H.fill_utilities(sim, 1.0, 0.8, true)
		g.run(450)
	var f0: Dictionary = sim.metrics.forecast()
	var nobed := 0
	for x in sim.state["agents"].values():
		if x["state"] == "alive" and int(x["bed"]) == -1:
			nobed += 1
	print("BEDS %d pop %d nobed %d habitats %d" % [int(f0["beds"]), int(f0["pop"]), nobed, H.buildings_of(sim, "habitat").size()])
	var crew: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor" and crew.size() < 6:
			crew.append(a)
	var c: Vector2 = sim.world.center
	var legs := {}
	for k in 6:
		var kind: String = "hopper" if k == 5 else "medium_rover"
		var p = sim.nav.nearest_walkable(c + Vector2.RIGHT.rotated(k * TAU / 6.0) * 160.0, 10)
		var v: Dictionary = sim.vehicles.get_v(int(g.cmd("spawn_vehicle", {"kind": kind, "x": p.x, "y": p.y})["id"]))
		v["charge"] = 1e6
		v["fuel"] = 1e6
		crew[k]["fatigue"] = minf(float(crew[k]["fatigue"]), 50.0)
		crew[k]["hunger"] = minf(float(crew[k]["hunger"]), 50.0)
		crew[k]["thirst"] = minf(float(crew[k]["thirst"]), 50.0)
		H.put_outside(sim, crew[k], v["pos"] + Vector2(2, 0), sim.agents.suit_cap())
		sim.vehicles.board(crew[k], int(v["id"]))
		var far: Vector2 = C4._drive_target(sim, v["pos"], 450.0) if kind != "hopper" else v["pos"] + (c - v["pos"]).normalized() * 500.0
		if far.x < 0.0:
			far = C4._drive_target(sim, v["pos"], 250.0)
		legs[int(v["id"])] = [far, v["pos"]]
	for k2 in 6:
		var cc: Dictionary = crew[k2]
		print("CREW %d %s where %s veh %s plan %s fat %.0f" % [k2, cc["name"], cc["where"], str(cc.get("veh", -1)), cc["plan_kind"], float(cc["fatigue"])])
	g.run(60)
	for tk2 in 30:
		var ln2: Dictionary = sim.state["agents"][88]
		print("T2 %d where %s plan %s n %d pi %s act_t %s queued %s li %s route %s" % [tk2, ln2["where"], ln2["plan_kind"], (ln2["plan"] as Array).size(), str(ln2["pi"]), str(ln2["act_t"]), str(ln2["queued"]), str(ln2["li"]), str((ln2["route"] as Dictionary).keys())])
		g.run(1)
	for tk in 0:
		var lv: Dictionary = sim.vehicles.get_v(4985)
		var ln: Dictionary = sim.state["agents"][88]
		if tk % 3 == 0 or ln["where"] != "vehicle":
			print("TK %d Lin where %s plan %s goal %s | veh state %s block %s crew %s pos %s" % [tk, ln["where"], ln["plan_kind"], ln["goal"], lv["state"], str(lv.get("block", "")), str(lv["crew"]), str(lv["pos"])])
		if ln["where"] != "vehicle":
			break
		g.run(10)
	var dead_seen := {}
	for w in 24:
		if w % 10 == 0 or w % 10 == 5:
			H.fill_utilities(sim, 1.0, 0.8, true)
		for cw in crew:
			cw["fatigue"] = minf(float(cw["fatigue"]), 50.0)
			cw["hunger"] = minf(float(cw["hunger"]), 50.0)
			cw["thirst"] = minf(float(cw["thirst"]), 50.0)
		g.run(100)
		for vid in legs:
			var v2: Dictionary = sim.vehicles.get_v(vid)
			if v2["state"] == "parked":
				var l: Array = legs[vid]
				l.reverse()
				sim.vehicles.drive_to(v2, l[0])
		var la: Dictionary = sim.state["agents"][88]
		if w < 24:
			print("  w%d Lin where %s veh %s state %s plan %s goal %s suit %.0f grace %.1f hp %.0f" % [w, la["where"], str(la.get("veh", -1)), la["state"], la["plan_kind"], la["goal"], float(la["suit"]), float(la["o2_grace"]), float(la["health"])])
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "dead" and not dead_seen.has(aid):
				dead_seen[aid] = true
				print("DEAD %d %s cause %s where %s bld %s veh %s goal %s plan %s role %s hold %s jailed %s fat %.0f hun %.0f thi %.0f" % [int(aid), a["name"], a["cause"], a["where"], str(a["bld"]), str(a.get("veh", -1)), a["goal"], a["plan_kind"], a["role"], str(a.get("v5_hold", "")), str(a.has("jailed")), float(a["fatigue"]), float(a["hunger"]), float(a["thirst"])])
		for aid2 in sim.state["agents"]:
			var b: Dictionary = sim.state["agents"][aid2]
			if b["state"] == "alive" and float(b["fatigue"]) >= 99.0 and w % 3 == 0:
				print("  t%d tired %d where %s veh %s goal %s plan %s bed %s nowork %s role %s" % [w, int(aid2), b["where"], str(b.get("veh", -1)), b["goal"], b["plan_kind"], str(b["bed"]), str(b.has("v5_nowork")), b["role"]])
	print("done, dead %d" % dead_seen.size())
	quit(0)
