extends SceneTree
## Developer tool (UI's test_ships_ui "pad active and powered"): showcase_v3_late, a landing pad
## 40+ m out, 400 s, a cable to the nearest powered structure, 200 s; prints why the pad is or is
## not powered.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))["state"], {"debug": true})
	var c0 := Vector2.ZERO
	var n := 0
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "room":
			c0 += b["pos"]
			n += 1
	c0 /= maxf(1, n)
	var spot := Vector2(374.5, 430.5)
	var rr := 400.0
	while rr < 260.0 and spot.x < 0.0:
		for k in 36:
			var q: Vector2 = sim.place.snap_pos(c0 + Vector2(rr, 0).rotated(TAU * float(k) / 36.0))
			if spot.x < 0.0 and sim.place.check_building("landing_pad", q, 0.0, -1, 1) == "ok":
				spot = q
		rr += 6.0
	print("spot ", spot, " stage ", sim.state["progress"]["stage"])
	var cid: int = sim.submit("place_building", {"def": "landing_pad", "x": spot.x, "y": spot.y, "rot": 0.0, "size": 1})
	sim.step()
	print("place ", sim.cmds.results.get(cid, {}))
	sim.run_seconds(400.0)
	var pad := {}
	for id in sim.state["buildings"]:
		if sim.state["buildings"][id]["def"] == "landing_pad":
			pad = sim.state["buildings"][id]
	print("pad state ", pad.get("state"), " block ", pad.get("block"), " progress ", pad.get("progress"))
	var best := -1
	var best_d := 1e9
	for oid in sim.state["buildings"]:
		var ob: Dictionary = sim.state["buildings"][oid]
		if oid == pad["id"] or String(ob.get("kind", "")) == "link" or ob["state"] != "active" or not sim.topo.power_comp.has(oid):
			continue
		var dd: float = (ob["pos"] as Vector2).distance_to(pad["pos"])
		var code: String = String(sim.place.check_link("cable", pad["id"], oid)["code"])
		if dd < best_d and code == "ok":
			best_d = dd
			best = oid
	print("cable to ", best, " ", best_d)
	best = 6507
	var ob2: Dictionary = sim.state["buildings"][6507]
	print("target 6507: ", ob2["def"], " ", ob2["state"], " powered ", ob2.get("powered"), " comp ", sim.topo.power_comp.get(6507))
	var lid: int = sim.submit("place_link", {"def": "cable", "a": pad["id"], "b": best})
	sim.step()
	var lr: Dictionary = sim.cmds.results.get(lid, {})
	print("link ", lr)
	sim.run_seconds(200.0)
	var l: Dictionary = sim.state["buildings"].get(int(lr.get("id", -1)), {})
	print("cable state ", l.get("state"), " block ", l.get("block"), " unreach ", l.get("unreach_rev"), "/", sim.state["rev"]["walk"])
	print("pad powered ", pad.get("powered"), " comp ", sim.topo.power_comp.get(pad["id"]), " 6507 comp ", sim.topo.power_comp.get(6507))
	var comp = sim.topo.power_comp.get(pad["id"])
	if comp != null:
		print("power stats ", sim.util.power_stats.get(comp))
		var ms: Array = []
		for m in sim.topo.power_members[comp]:
			ms.append(sim.state["buildings"][m]["def"])
		print("members ", ms)
	sim.dispose()
	quit(0)
