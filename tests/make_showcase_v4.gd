extends SceneTree
## Writes content/saves/showcase_v4.fhsave (docs/V4_DESIGN.md section 9) on the 2,560 m map:
## two bases (the landing base and "Crater camp"), a medium rover on a route between them, a
## fission reactor with fuel and coolant, an expedition rover with two people at a deep crater
## rim, and a survey satellite that has mapped five of sixteen bands.
##   node tools/godot.mjs script res://tests/make_showcase_v4.gd [seed] [day]
## The base is the v4 reference campaign; the rest is SET-UP with the debug commands (finished
## structures, vehicles), a kit pile for the outpost and the reactor's first rods and coolant
## (ledger reason "scenario"). Debug and unlock_all are off again in the save. The ledger stays {}.

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")

func _spot(sim, def_id: String, around: Vector2, rmin: float, rmax: float, size: int = 1) -> Vector2:
	var r: float = rmin
	while r <= rmax:
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(around + Vector2.RIGHT.rotated(k * TAU / 36.0) * r)
			if sim.place.check_building(def_id, p, 0.0, -1, size) == "ok":
				return p
		r += 6.0
	return Vector2(-1, -1)

func _cmd(sim, kind: String, p: Dictionary) -> Dictionary:
	var id: int = sim.submit(kind, p)
	sim.step()
	var r: Dictionary = sim.cmds.results.get(id, {"ok": false, "code": "not_applied"})
	if not bool(r.get("ok", false)):
		print("  %s refused: %s" % [kind, str(r)])
	return r

func _init() -> void:
	var nums: Array = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			nums.append(float(a))
	var seed_value: int = int(nums[0]) if nums.size() > 0 else 1001
	var day: float = nums[1] if nums.size() > 1 else 12.0
	var sim = Sim.new()
	sim.new_game(seed_value, "frontier", {"hazards": "normal", "debug": true})
	var ref = Reference.new(sim, "all")
	while sim.seconds() < day * 600.0:
		if int(sim.state["tick"]) % 10 == 0:
			ref.drive()
		sim.step()
	print("day %.1f: %d colonists, %d structures" % [day, sim.alive_count(), sim.state["buildings"].size()])
	sim.state["flags"]["unlock_all"] = true
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	# Beds for everybody (the day-12 reference base has 16 beds for 20 colonists, and the
	# lander air has ended): a size L habitat joined by a corridor to the nearest room.
	var errs0: Array = []
	var hab_ok := false
	for id in sim.state["buildings"].keys():
		var rb: Dictionary = sim.state["buildings"][id]
		if hab_ok or rb["def"] != "habitat" or rb["state"] != "active":
			continue
		for k in 24:
			if hab_ok:
				break
			var hp: Vector2 = sim.place.snap_pos((rb["pos"] as Vector2) + Vector2.RIGHT.rotated(k * TAU / 24.0) * (float(rb["radius"]) + 10.5 + 16.0))
			if sim.place.check_building("habitat", hp, 0.0, -1, 2) != "ok":
				continue
			var hb: Dictionary = sim.build.spawn_active("habitat", hp, 0.0, 2)
			var l: Dictionary = H.link_now(sim, "corridor", int(rb["id"]), int(hb["id"]), errs0)
			if l.is_empty():
				sim.build._remove_record(hb)          # no link: take it away again (nothing logged)
				errs0.clear()
				continue
			hab_ok = true
	print("extra habitat: %s" % str(hab_ok))
	var lp: Vector2 = lander["pos"]
	# Rover depot (L).
	var dp: Vector2 = _spot(sim, "rover_depot", lp, 40.0, 110.0, 2)
	var depot: int = int(_cmd(sim, "place_finished", {"def": "rover_depot", "x": dp.x, "y": dp.y, "size": 2}).get("id", -1))
	# The outpost.
	var op := Vector2(-1, -1)
	for r in [440.0, 500.0, 560.0, 620.0]:
		for k in 24:
			var p: Vector2 = sim.place.snap_pos(lp + Vector2.RIGHT.rotated(k * TAU / 24.0) * r)
			if op.x < 0.0 and sim.bases.check_outpost(p, 0.0) == "ok" and bool(sim.nav.vehicle_path(lp, p, "rover")["ok"]):
				op = p
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, op + Vector2(12, 0))
	sim.inv.add_new_forced(pile, "outpost_kit", 1, "scenario")
	var ob: Dictionary = _cmd(sim, "deploy_outpost", {"x": op.x, "y": op.y, "rot": 0.0, "inv": pile, "name": "Crater camp"})
	var camp: int = int(ob.get("id", -1))
	var core: Dictionary = sim.state["buildings"].get(int(ob.get("core", -1)), {})
	if not core.is_empty():
		var sp: Vector2 = _spot(sim, "solar_array", core["pos"], 16.0, 40.0)
		_cmd(sim, "place_finished", {"def": "solar_array", "x": sp.x, "y": sp.y})
	# Colonists for the vehicles.
	var people: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor" and people.size() < 3:
			people.append(a)
	# The route rover.
	var rv: Dictionary = _cmd(sim, "spawn_vehicle", {"kind": "medium_rover", "depot": depot})
	var route_v: Dictionary = sim.vehicles.get_v(int(rv.get("id", -1)))
	H.put_outside(sim, people[0], sim.vehicles.board_point(route_v), sim.agents.suit_cap())
	sim.vehicles.board(people[0], int(route_v["id"]))
	_cmd(sim, "vehicle_route", {"id": int(route_v["id"]), "a": 1, "b": camp, "load": {"metal": 10}, "back": {}})
	# The expedition rover at a deep crater rim.
	var rim := Vector2(-1, -1)
	for cr in sim.world.deep_craters:
		var cc := Vector2(cr["x"], cr["y"])
		for k in 16:
			var q: Vector2 = cc + Vector2.RIGHT.rotated((lp - cc).angle() + k * TAU / 16.0) * float(cr["r"]) * 1.08
			if rim.x < 0.0 and sim.nav.rover_ok(q) and bool(sim.nav.vehicle_path(lp, q, "rover")["ok"]):
				rim = q
	var ex: Dictionary = _cmd(sim, "spawn_vehicle", {"kind": "medium_rover", "x": rim.x, "y": rim.y})
	var ex_v: Dictionary = sim.vehicles.get_v(int(ex.get("id", -1)))
	for a in [people[1], people[2]]:
		H.put_outside(sim, a, ex_v["pos"] + Vector2(2, 0), sim.agents.suit_cap())
		sim.vehicles.board(a, int(ex_v["id"]))
	ex_v["name"] = "Expedition rover"
	# The reactor.
	var rp: Vector2 = _spot(sim, "fission_reactor", lp, 170.0, 280.0)
	var rr: Dictionary = _cmd(sim, "place_finished", {"def": "fission_reactor", "x": rp.x, "y": rp.y})
	var reactor: Dictionary = sim.state["buildings"].get(int(rr.get("id", -1)), {})
	if not reactor.is_empty():
		sim.inv.add_new_forced(int(reactor["inv_in"]), "fuel_rod", 2, "scenario")
		sim.inv.add_new_forced(int(reactor["inv_in"]), "coolant", 8, "scenario")
	# Satellite: launch pad, comms tower, battery; five bands mapped.
	var pp: Vector2 = _spot(sim, "launch_pad", lp, 60.0, 140.0)
	var pad: Dictionary = sim.state["buildings"].get(int(_cmd(sim, "place_finished", {"def": "launch_pad", "x": pp.x, "y": pp.y}).get("id", -1)), {})
	var tp: Vector2 = _spot(sim, "comms_tower", pp, 12.0, 40.0)
	var tower: int = int(_cmd(sim, "place_finished", {"def": "comms_tower", "x": tp.x, "y": tp.y}).get("id", -1))
	var bp: Vector2 = _spot(sim, "battery", tp, 6.0, 30.0)
	var bat: int = int(_cmd(sim, "place_finished", {"def": "battery", "x": bp.x, "y": bp.y}).get("id", -1))
	var errs: Array = []
	# A small power grid of its own: two solar arrays and two batteries (charged), cabled to
	# the tower and the pad (UI integration: they had no power in the first showcase).
	var sa1: Vector2 = _spot(sim, "solar_array", tp, 8.0, 40.0)
	var s1: int = int(_cmd(sim, "place_finished", {"def": "solar_array", "x": sa1.x, "y": sa1.y}).get("id", -1))
	var sa2: Vector2 = _spot(sim, "solar_array", sa1, 8.0, 40.0)
	var s2: int = int(_cmd(sim, "place_finished", {"def": "solar_array", "x": sa2.x, "y": sa2.y}).get("id", -1))
	var bp2: Vector2 = _spot(sim, "battery", bp, 4.0, 30.0)
	var bat2: int = int(_cmd(sim, "place_finished", {"def": "battery", "x": bp2.x, "y": bp2.y}).get("id", -1))
	H.link_now(sim, "cable", tower, bat, errs)
	H.link_now(sim, "cable", bat, bat2, errs)
	H.link_now(sim, "cable", bat, s1, errs)
	H.link_now(sim, "cable", s1, s2, errs)
	if not pad.is_empty():
		H.link_now(sim, "cable", int(pad["id"]), tower, errs)
	for bid in [bat, bat2]:
		var bb: Dictionary = sim.state["buildings"].get(bid, {})
		if not bb.is_empty():
			bb["energy"] = int(sim.util.energy_cap_of(bb))
	if not pad.is_empty():
		var sat: Dictionary = sim.explore.launch(pad)
		for b in 5:
			sim.explore.reveal_band(int(sat["band"]), false)
			sat["band"] = (int(sat["band"]) + 1) % 16
			sat["bands"] = int(sat["bands"]) + 1
	for i in 600:
		if i % 10 == 0:
			ref.drive()
		sim.step()
	sim.state["flags"]["unlock_all"] = false
	sim.state["options"]["debug"] = false
	var bytes: PackedByteArray = sim.save_bytes()
	var tmp := "res://content/saves/showcase_v4.tmp.fhsave"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var chk: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(tmp))
	var final_abs: String = ProjectSettings.globalize_path("res://content/saves/showcase_v4.fhsave")
	if chk["ok"]:
		if FileAccess.file_exists("res://content/saves/showcase_v4.fhsave"):
			DirAccess.remove_absolute(final_abs)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), final_abs)
	var tw: Dictionary = sim.state["buildings"].get(tower, {})
	var crit: Array = []
	for k in sim.state["issues"]:
		if int(sim.state["issues"][k]["severity"]) >= 3:
			crit.append(String(sim.state["issues"][k]["text"]))
	print("tower powered %s, pad powered %s, critical alerts %s" % [str(tw.get("powered", false)), str(pad.get("powered", false)), str(crit)])
	print("wrote %s: %d bytes, %d colonists, %d bases, %d vehicles, reactors %d, fog %.0f %%, sats %s, audit %s, errors %s" % [final_abs,
		bytes.size(), sim.alive_count(), sim.bases.count(), sim.vehicles.count(), sim.reactors.list().size(), sim.explore.explored_share() * 100.0,
		str(sim.explore.sats().map(func(x): return x["bands_done"])), str(sim.inv.audit()), str(errs)])
	ref = null
	sim.dispose()
	quit(0)
