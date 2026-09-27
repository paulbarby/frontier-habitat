extends SceneTree
## Developer tool: the v4 world (2,560 m) of a seed: generation time per step, features,
## materials, radiation and sun numbers, and a few walks and drives.
##   node tools/godot.mjs script res://tests/dev/world_v4_probe.gd [seed]
const Sim = preload("res://sim/sim.gd")
const WorldGen = preload("res://sim/world_gen.gd")

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var sim = Sim.new()
	var t0: int = Time.get_ticks_msec()
	sim.new_game(seed_value, "frontier")
	var t_game: int = Time.get_ticks_msec() - t0
	var w = sim.world
	print("world %d m, version %d, hn %d, generation %d ms (new game total %d ms)" % [w.size, w.version, w.hn, w.gen_msec, t_game])
	var parts: Array = w.gen_parts.keys()
	for k in parts:
		print("   %-9s %6.0f ms" % [k, float(w.gen_parts[k]) / 1000.0])
	print("nav terrain layers %d ms" % sim.nav.base_msec)
	print("mountains %d, plateaus %d, deep craters %d, crevices %d, boulder fields %d, dunes %d, ridges %d, canyons %d, craters %d, flats %d, rocks %d" % [w.mountains.size(), w.plateaus.size(), w.deep_craters.size(), w.crevices.size(), w.boulder_fields.size(), w.dunes.size(), w.ridges.size(), w.canyons.size(), w.craters.size(), w.flats.size(), w.rocks.size()])
	var kinds := {}
	for d in w.deposit_sites:
		kinds[d["kind"]] = int(kinds.get(d["kind"], 0)) + 1
	print("deposits ", kinds)
	for d in w.deposit_sites:
		var p := Vector2(d["x"], d["y"])
		print("   %-10s tier %d at %4.0f m from start, rad %.2f mSv/h, ground %s" % [d["kind"], int(d["tier"]), p.distance_to(w.center), w.rad_at(p.x, p.y), w.terrain_at(p)])
	var steep := 0
	for v in w.steep:
		steep += int(v)
	print("steep quads %.1f %%" % (100.0 * steep / w.steep.size()))
	print("radiation: start %.3f" % w.rad_at(w.center.x, w.center.y))
	# Sun: fraction of daylight output on crater floors, plateaus, plain.
	var day: float = float(sim.bal["day_length"])
	var dl: float = float(sim.planet["daylight_seconds"])
	for cr in w.deep_craters:
		var cp := Vector2(cr["x"], cr["y"])
		print("   crater r %.0f depth %.0f: sun share floor %.2f, rim %.2f" % [float(cr["r"]), float(cr["depth"]), _share(w, cp, day, dl), _share(w, cp + Vector2(float(cr["r"]) * 1.3, 0), day, dl)])
	for pl in w.plateaus:
		print("   plateau h %.0f: sun share %.2f, height %.1f vs start %.1f" % [float(pl["h"]), _share(w, Vector2(pl["x"], pl["y"]), day, dl), w.height_at(pl["x"], pl["y"]), w.height_at(w.center.x, w.center.y)])
	print("   start plateau sun share %.2f" % _share(w, w.center, day, dl))
	# Walks and drives.
	var nav = sim.nav
	var t1: int = Time.get_ticks_usec()
	var r1: Dictionary = nav.path_out(w.center + Vector2(40, 0), w.center + Vector2(-90, 60))
	print("walk 150 m: ok %s len %.0f  (%d us, windows %d)" % [str(r1["ok"]), float(r1.get("len", 0)), Time.get_ticks_usec() - t1, nav.wins.size()])
	for cr in w.deep_craters:
		var cp := Vector2(cr["x"], cr["y"])
		t1 = Time.get_ticks_usec()
		var r2: Dictionary = nav.vehicle_path(w.center, cp, "rover")
		var t2: int = Time.get_ticks_usec() - t1
		t1 = Time.get_ticks_usec()
		var r3: Dictionary = nav.path_out(w.center, cp)
		print("   to crater floor at %.0f m: rover ok %s len %.0f (%d us); walk (coarse) ok %s len %.0f (%d us)" % [cp.distance_to(w.center), str(r2["ok"]), float(r2.get("len", 0)), t2, str(r3["ok"]), float(r3.get("len", 0)), Time.get_ticks_usec() - t1])
	for mt in w.mountains:
		var pk: Vector2 = mt["peak"]
		var r4: Dictionary = nav.vehicle_path(w.center, pk, "rover")
		var r5: Dictionary = nav.vehicle_path(w.center, pk, "hopper")
		print("   to peak: rover ok %s; hopper ok %s hops %d" % [str(r4["ok"]), str(r5["ok"]), int(r5.get("hops", 0))])
	print("colonists %d, lander at %s" % [sim.alive_count(), str(sim.state["buildings"][sim.state["lander_id"]]["pos"])])
	for i in 600:
		sim.step()
	print("60 s of play: tick %d, audit %s" % [int(sim.state["tick"]), str(sim.inv.audit())])
	quit(0)

func _share(w, p: Vector2, day: float, dl: float) -> float:
	var s := 0.0
	var n := 0
	var t := 0.0
	while t < dl:
		var sa: Dictionary = w.sun_angles(t, dl, day)
		var e: float = float(sa["elev_deg"])
		s += w.sun_vis(p, e, float(sa["bearing"])) * sin(deg_to_rad(maxf(0.0, e)))
		var open: float = sin(deg_to_rad(maxf(0.0, e)))
		n += 1
		t += dl / 60.0
	var s_open := 0.0
	t = 0.0
	while t < dl:
		var sa2: Dictionary = w.sun_angles(t, dl, day)
		s_open += sin(deg_to_rad(maxf(0.0, float(sa2["elev_deg"]))))
		t += dl / 60.0
	return s / maxf(1e-6, s_open)
