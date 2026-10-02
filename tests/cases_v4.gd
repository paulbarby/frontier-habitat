extends RefCounted
## Version 4 tests (docs/V4_DESIGN.md): the 2,560 m planet, radiation, horizon sun,
## hierarchical walking and driving, and (later milestones) bases, vehicles, orders,
## tiers, reactor, fog and save schema 5.
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")
const Pacer = preload("res://tests/pacer.gd")
const WorldGen = preload("res://sim/world_gen.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")

func tests() -> Array:
	return [
		["v4_world_generation", v4_world_generation],
		["v4_radiation_and_sun", v4_radiation_and_sun],
		["v4_nav_walk_drive_hop", v4_nav],
		["v4_solar_output_uses_horizon", v4_solar],
		["v4_frontier_game_plays", v4_frontier_plays],
		["v4_rover_reaches_high_end_ground", v4_rover_reach],
		["v4_room_and_corridor_scale", v4_room_and_corridor_scale],
		["v4_outpost_founds_a_base", v4_outpost_founds_a_base],
		["v4_outpost_content_and_migration", v4_outpost_content_and_migration],
		["v4_room_link_counts", v4_room_link_counts],
		["v4_vehicle_build_board_drive", v4_vehicle_build_board_drive],
		["v4_vehicle_rules", v4_vehicle_rules],
		["v4_vehicle_route", v4_vehicle_route],
		["v4_orders", v4_orders],
		["v4_debug_commands", v4_debug_commands],
		["v4_content_tree", v4_content_tree],
		["v4_materials_in_play", v4_materials_in_play],
		["v4_food_margin", v4_food_margin],
		["v4_depot_bays", v4_depot_bays],
		["v4_indoor_orders_need_no_air", v4_indoor_orders_need_no_air],
		["v4_reactor_meltdown", v4_reactor_meltdown],
		["v4_other_disasters", v4_other_disasters],
		["v4_fog_and_pois", v4_fog_and_pois],
		["v4_poi_visits", v4_poi_visits],
		["v4_satellite", v4_satellite],
		["v4_showcase", v4_showcase],
		["long_v4_perf_100_colonists_6_vehicles", long_v4_perf],
		["long_v4_tick_max", long_v4_tick_max],
		["v4_reactor_stage_debug", v4_reactor_stage_debug],
		["v4_rover_tubes_and_blocks", v4_rover_tubes_and_blocks],
		["v4_locks_explained", v4_locks_explained],
		["v4_inventory_contents", v4_inventory_contents],
		["v4_riders_come_home", v4_riders_come_home],
		["v4_exteriors_in_reach", v4_exteriors_in_reach],
	]

static func _fresh_world(sim, seed_value: int):
	var planet: Dictionary = sim.content["planets"]["dry"]
	WorldGen._cache.erase("%d:%s:%d" % [seed_value, planet.get("name", ""), 2560])
	return WorldGen.get_world(seed_value, planet, sim.bal, 2560, sim.content["terrain_v4"])

static func _hash_world(w) -> int:
	var parts: Array = [Array(w.heights).hash(), Array(w.steep).hash(), w.rocks.size(), Array(w.rad).hash(), Array(w.horizon).hash()]
	for d in w.deposit_sites:
		parts.append([d["kind"], snappedf(float(d["x"]), 0.01), snappedf(float(d["y"]), 0.01), int(d["ore"])])
	return parts.hash()

## Generation within 4 s, the same world from the same seed, every feature kind present,
## a flat start plateau, and each material tier where the design puts it.
func v4_world_generation(t) -> void:
	var sim = H.Sim.new()
	var cfg: Dictionary = sim.content["terrain_v4"]
	var worst := 0
	for seed_value in [1001, 1002, 1003]:
		var w = _fresh_world(sim, seed_value)
		worst = maxi(worst, int(w.gen_msec))
		t.eq(int(w.version), 4, "seed %d: version 4" % seed_value)
		t.eq(int(w.size), 2560, "seed %d: 2,560 m" % seed_value)
		t.check(w.mountains.size() >= 2 and w.deep_craters.size() >= 2 and w.plateaus.size() >= 2 and w.crevices.size() >= 3 and w.boulder_fields.size() >= 5,
			"seed %d: mountains %d, craters %d, plateaus %d, crevices %d, boulder fields %d" % [seed_value, w.mountains.size(), w.deep_craters.size(), w.plateaus.size(), w.crevices.size(), w.boulder_fields.size()])
		t.check(w.slope_over(w.center, 110.0) < 0.04, "seed %d: the start plateau is flat to 110 m (%.3f)" % [seed_value, w.slope_over(w.center, 110.0)])
		for cr in w.deep_craters:
			var wide: float = 2.0 * float(cr["r"])
			if wide < 199.0 or wide > 601.0 or float(cr["depth"]) < 39.0 or float(cr["depth"]) > 121.0:
				t.fail("seed %d: crater %.0f m wide, %.0f m deep" % [seed_value, wide, float(cr["depth"])])
		for pl in w.plateaus:
			var rise: float = w.height_at(pl["x"], pl["y"]) - w.height_at(w.center.x, w.center.y)
			if float(pl["h"]) < 19.0 or float(pl["h"]) > 61.0:
				t.fail("seed %d: plateau %.0f m high" % [seed_value, float(pl["h"])])
		for cv in w.crevices:
			if float(cv["w"]) < 3.0 or float(cv["w"]) > 15.0:
				t.fail("seed %d: crevice %.1f m wide" % [seed_value, float(cv["w"])])
		# Materials: basic near and safe, high-end only in dangerous or far places.
		var near_metal := 0
		for d in w.deposit_sites:
			var p := Vector2(d["x"], d["y"])
			if not w.in_map(p, 20.0):
				t.fail("seed %d: %s outside the map" % [seed_value, d["kind"]])
			if d["kind"] == "metal" and p.distance_to(w.center) < 520.0:
				near_metal += 1
			if int(d["tier"]) == 3:
				var ground: String = w.terrain_at(p)
				var danger: bool = w.rad_at(p.x, p.y) >= 0.5 or ground in ["deep crater", "mountain", "crater rim"] or w.crevice_at(p, 40.0) or p.distance_to(w.center) >= 700.0
				if not danger:
					t.fail("seed %d: %s (tier 3) on safe ground at %.0f m (%s, %.2f mSv/h)" % [seed_value, d["kind"], p.distance_to(w.center), ground, w.rad_at(p.x, p.y)])
		t.check(near_metal >= 3, "seed %d: metal ore near the start (%d within 520 m)" % [seed_value, near_metal])
		# No spikes on the mountain ranges (critic round 18): slope between neighbour samples.
		var hn: int = w.hn
		var worst_m := 0.0
		for y in range(1, hn - 1, 3):
			for x in range(1, hn - 1, 3):
				if w.near_mountain(Vector2(x * w.hstep, y * w.hstep)) > 0.0:
					continue
				var i: int = y * hn + x
				var h: float = w.heights[i]
				worst_m = maxf(worst_m, maxf(maxf(absf(h - w.heights[i - 1]), absf(h - w.heights[i + 1])), maxf(absf(h - w.heights[i - hn]), absf(h - w.heights[i + hn]))) / w.hstep)
		t.check(worst_m <= 2.6, "seed %d: no spikes on the mountains (steepest %.2f)" % [seed_value, worst_m])
		# Crater form: a raised rim lip above the ground outside.
		for cr in w.deep_craters:
			var c0 := Vector2(cr["x"], cr["y"])
			var raised := 0
			for k in 12:
				var u := Vector2.RIGHT.rotated(k * TAU / 12.0)
				var lip: float = w.height_at(c0.x + u.x * float(cr["r"]), c0.y + u.y * float(cr["r"]))
				var out: float = w.height_at(c0.x + u.x * float(cr["r"]) * 1.7, c0.y + u.y * float(cr["r"]) * 1.7)
				if lip > out:
					raised += 1
			if raised < 8:
				t.fail("seed %d: crater at %s: raised rim in only %d of 12 directions" % [seed_value, str(c0), raised])
	t.check(worst <= 4000, "world generation takes at most 4 s (worst %d ms)" % worst)
	var a: int = _hash_world(_fresh_world(sim, 1002))
	var b: int = _hash_world(_fresh_world(sim, 1002))
	t.eq(a, b, "the same seed gives the same world")
	t.check(_hash_world(_fresh_world(sim, 1003)) != a, "another seed gives another world")
	t.note("worst generation %d ms" % worst)
	sim.dispose()
	t.done()

static func _sun_share(w, p: Vector2, day: float, dl: float) -> float:
	var s := 0.0
	var s_open := 0.0
	var tt := 0.0
	while tt < dl:
		var sa: Dictionary = w.sun_angles(tt, dl, day)
		var e: float = float(sa["elev_deg"])
		var k: float = sin(deg_to_rad(maxf(0.0, e)))
		s += w.sun_vis(p, e, float(sa["bearing"])) * k
		s_open += k
		tt += dl / 48.0
	return s / maxf(1e-6, s_open)

## Radiation: low on the plain, high at uranium and thorium; the sun: deep crater floors get
## a fraction of the open ground's light, plateaus get all of it, the night none.
func v4_radiation_and_sun(t) -> void:
	var sim = H.Sim.new()
	sim.new_game(1001, "frontier")
	var w = sim.world
	var cfg: Dictionary = sim.content["terrain_v4"]
	var plain: float = float(cfg["radiation"]["plain"])
	t.near(w.rad_at(w.center.x, w.center.y), plain, 0.01, "the start has plain radiation")
	var hot := 0
	for d in w.deposit_sites:
		if d["kind"] == "uranium" or d["kind"] == "thorium":
			var r: float = w.rad_at(d["x"], d["y"])
			if r < 1.5:
				t.fail("%s field only %.2f mSv/h" % [d["kind"], r])
			hot += 1
	t.check(hot >= 2, "uranium and thorium fields exist (%d)" % hot)
	var day: float = float(sim.bal["day_length"])
	var dl: float = float(sim.planet["daylight_seconds"])
	var floors: Array = []
	for cr in w.deep_craters:
		floors.append(snappedf(_sun_share(w, Vector2(cr["x"], cr["y"]), day, dl), 0.01))
	var mean := 0.0
	for f in floors:
		mean += float(f)
	mean /= maxf(1.0, floors.size())
	t.check(mean <= 0.4, "deep crater floors get little sun (%s, mean %.2f)" % [str(floors), mean])
	t.check(_sun_share(w, w.center, day, dl) > 0.97, "the start plateau gets the full sun")
	var noon: Dictionary = w.sun_angles(dl * 0.5, dl, day)
	t.near(float(noon["elev_deg"]), float(cfg["sun"]["max_elev_deg"]), 0.01, "noon elevation from content")
	var night: Dictionary = w.sun_angles(dl + 30.0, dl, day)
	t.eq(w.sun_vis(w.center, float(night["elev_deg"]), float(night["bearing"])), 0.0, "no sun at night")
	t.eq(w.terrain_at(w.center), "start plateau", "terrain_at names the start")
	sim.dispose()
	t.done()

## Walking uses a fine window near people and the coarse grid far away; rovers stay off
## crevices and mountains; hoppers reach peaks.
func v4_nav(t) -> void:
	var sim = H.Sim.new()
	sim.new_game(1003, "frontier")
	var w = sim.world
	var nav = sim.nav
	t.check(nav.get("wins") != null, "the v4 map uses the hierarchical graph")
	var a: Vector2 = w.center + Vector2(40, 10)
	var b: Vector2 = w.center + Vector2(-110, 70)
	var r: Dictionary = nav.path_out(a, b)
	t.check(bool(r["ok"]) and not r.has("coarse"), "a 150 m walk is planned on a fine window")
	var bad := 0
	if bool(r["ok"]):
		for p in r["pts"]:
			if not nav.is_walkable(p):
				bad += 1
	t.eq(bad, 0, "every path point is walkable")
	t.check(nav.wins.size() <= nav.MAX_WINDOWS, "windows stay within the limit (%d)" % nav.wins.size())
	var reached := 0
	var crossed := 0
	for cr in w.deep_craters:
		var rv: Dictionary = nav.vehicle_path(w.center, Vector2(cr["x"], cr["y"]), "rover")
		if not bool(rv["ok"]):
			continue
		reached += 1
		var pts: Array = rv["pts"]
		for i in range(1, pts.size()):
			for k in 20:
				var q: Vector2 = (pts[i - 1] as Vector2).lerp(pts[i], float(k) / 20.0)
				if w.crevice_at(q):
					crossed += 1
	t.check(reached >= 1, "a rover reaches a deep crater floor by its ramp (%d of %d)" % [reached, w.deep_craters.size()])
	t.eq(crossed, 0, "a rover route never crosses a crevice")
	var peak_rover := 0
	var peak_hop := 0
	for mt in w.mountains:
		if bool(nav.vehicle_path(w.center, mt["peak"], "rover")["ok"]):
			peak_rover += 1
		if bool(nav.vehicle_path(w.center, mt["peak"], "hopper")["ok"]):
			peak_hop += 1
	t.eq(peak_hop, w.mountains.size(), "a hopper reaches every peak")
	t.check(peak_rover < w.mountains.size(), "rovers cannot drive up every peak (%d of %d)" % [peak_rover, w.mountains.size()])
	var far: Dictionary = nav.path_out(w.center, w.center + Vector2(600, 0))
	t.check(not bool(far["ok"]) or far.has("coarse"), "a long walk uses the coarse grid")
	sim.dispose()
	t.done()

## A solar array on a deep crater floor makes much less than one on the start plateau.
func v4_solar(t) -> void:
	var sim = H.Sim.new()
	sim.new_game(1001, "frontier")
	var w = sim.world
	sim.state["flags"]["unlock_all"] = true          # test set-up
	var cr: Dictionary = {}
	for c in w.deep_craters:
		if cr.is_empty() or float(c["depth"]) / float(c["r"]) > float(cr["depth"]) / float(cr["r"]):
			cr = c
	var errors: Array = []
	var open: Dictionary = H.spawn(sim, "solar_array", Vector2(-60, -60), 0.0, errors)
	var spot = null
	for k in 24:
		var q: Vector2 = Vector2(cr["x"], cr["y"]) + Vector2.RIGHT.rotated(k * TAU / 24.0) * float(cr["floor_r"]) * 0.3
		if sim.place.check_building("solar_array", sim.place.snap_pos(q), 0.0) == "ok":
			spot = sim.place.snap_pos(q)
			break
	if open.is_empty() or spot == null:
		t.fail("no place for the solar arrays: %s" % str(errors))
		sim.dispose()
		t.done()
		return
	var dark: Dictionary = sim.build.spawn_active("solar_array", spot, 0.0)   # test set-up
	g_run_to_noon(sim)
	sim.step()
	var g_open: int = int(_gen_of(sim, open))
	var g_dark: int = int(_gen_of(sim, dark))
	t.check(g_open > 0, "the open array makes power at noon (%d)" % g_open)
	t.check(g_dark < g_open * 0.6, "the crater-floor array makes much less (%d of %d)" % [g_dark, g_open])
	sim.dispose()
	t.done()

static func g_run_to_noon(sim) -> void:
	var dl: float = float(sim.planet["daylight_seconds"])
	H.set_clock(sim, 1, dl * 0.5)

static func _gen_of(sim, b: Dictionary) -> int:
	var comp = sim.topo.power_comp.get(int(b["id"]))
	if comp == null:
		return 0
	return int(sim.util.power_stats.get(comp, {}).get("gen", 0))

## The reference campaign plays on the v4 map: three days, no death, the ledgers hold.
func v4_frontier_plays(t) -> void:
	var sim = H.Sim.new()
	sim.new_game(1001, "frontier")
	var ref = Reference.new(sim, "all")
	var t0: int = Time.get_ticks_usec()
	for s in 3 * 600:
		ref.drive()
		sim.run_seconds(1.0)
	var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0 / (3 * 6000.0)
	t.eq(int(sim.state["progress"]["deaths"]), 0, "no deaths in three days")
	t.check(sim.state["buildings"].size() >= 30, "the base grew (%d structures)" % sim.state["buildings"].size())
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(H.refused_commands(sim), [], "every reference command was accepted")
	t.note("%.2f ms per tick, %d windows" % [ms, sim.nav.wins.size()])
	sim.dispose()
	t.done()

## Every seed: a rover reaches at least one crater floor with helium-3 or deep ice, and at
## least one uranium field (coordinator rule, milestone 1). A blocked crater is allowed.
func v4_rover_reach(t) -> void:
	for seed_value in [1001, 1002, 1003, 1004, 1005]:
		var sim = H.Sim.new()
		sim.new_game(seed_value, "frontier")
		var w = sim.world
		var cold := 0
		var uranium := 0
		for d in w.deposit_sites:
			var k: String = d["kind"]
			if k != "helium3" and k != "deep_ice" and k != "uranium":
				continue
			if bool(sim.nav.vehicle_path(w.center, Vector2(d["x"], d["y"]), "rover")["ok"]):
				if k == "uranium":
					uranium += 1
				else:
					cold += 1
		t.check(cold >= 1, "seed %d: a rover reaches a crater floor with helium-3 or deep ice (%d deposits)" % [seed_value, cold])
		t.check(uranium >= 1, "seed %d: a rover reaches a uranium field (%d)" % [seed_value, uranium])
		sim.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 2: bases and scale
## Since V4 new rooms are 1.5 x the v3 radius on every map (ART-HAB built the models that
## way), except the airlock and the junction; old saves keep the radius they were built with.
func v4_room_and_corridor_scale(t) -> void:
	var s3 = H.Sim.new()
	s3.new_game(1001)
	var s4 = H.Sim.new()
	s4.new_game(1001, "frontier")
	var v3 := {"habitat": [4.0, 5.5, 7.0, 8.5], "kitchen": [3.6, 4.6, 6.0, 7.4], "greenhouse": [4.3, 6.0, 7.8, 9.6], "oxygen_plant": [2.8, 3.6, 4.8, 6.0]}
	for def_id in v3:
		for size in 4:
			var want: float = float(v3[def_id][size]) * 1.5
			t.near(float(s3.sizes.def_for(def_id, size)["radius"]), want, 0.001, "%s %s: %.2f m" % [def_id, s3.sizes.size_name(size), want])
			t.near(float(s4.sizes.def_for(def_id, size)["radius"]), want, 0.001, "the same on the v4 map")
	t.near(float(s3.sizes.def_for("airlock", 1)["radius"]), 3.4, 0.001, "the airlock keeps 3.4 m")
	t.near(float(s3.sizes.def_for("junction", 1)["radius"]), 2.5, 0.001, "the junction keeps 2.5 m")
	t.eq(float(s4.sizes.def_for("solar_array", 1)["radius"]), float(s3.sizes.def_for("solar_array", 1)["radius"]), "exterior structures keep their size")
	t.near(s4.corridor_r(), 1.2, 0.001, "corridors stay 1.2 m until the wider tubes go live")
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var old = H.Sim.new()
	old.load_state(dec["state"])
	var small := 0
	for id in old.state["buildings"]:
		var b: Dictionary = old.state["buildings"][id]
		if b["def"] == "habitat" and int(b.get("size", 1)) == 1 and absf(float(b["radius"]) - 5.5) < 0.001:
			small += 1
	t.check(small > 0, "an old save keeps its habitats at 5.5 m (%d)" % small)
	old.dispose()
	s3.dispose()
	s4.dispose()
	t.done()

static func _outpost_spot(sim, dmin: float) -> Vector2:
	var w = sim.world
	for r in [dmin, dmin + 60.0, dmin + 120.0, dmin + 200.0]:
		for k in 24:
			var p: Vector2 = sim.place.snap_pos(w.center + Vector2.RIGHT.rotated(k * TAU / 24.0) * r)
			if sim.bases.check_outpost(p, 0.0) == "ok":
				return p
	return Vector2(-1, -1)

## An Outpost Kit founds a second base: its core has its own air for three days, the base
## has a name, structures and colonists belong to it, alerts and stocks filter by it, and
## a colonist at one base does not take work at the other.
func v4_outpost_founds_a_base(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	sim.state["flags"]["unlock_all"] = true           # test set-up
	t.eq(sim.bases.count(), 1, "a new game has one base")
	t.eq(sim.bases.name_of(1), "Landing base", "named round the lander")
	var spot: Vector2 = _outpost_spot(sim, 420.0)
	if not t.check(spot.x > 0.0, "a place for the outpost"):
		g.dispose()
		t.done()
		return
	t.check(sim.bases.check_outpost(sim.world.center + Vector2(120, 0), 0.0) != "ok", "not next to the landing base")
	var far_pile: int = sim.inv.create_inv("g", 0, "pile", 100000, spot + Vector2(80, 0))   # test set-up
	sim.inv.add_new_forced(far_pile, "outpost_kit", 1, "test")
	t.eq(g.cmd("deploy_outpost", {"x": spot.x, "y": spot.y, "rot": 0.0, "inv": far_pile})["code"], "kit_far", "the kit must be near")
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, spot + Vector2(12, 0))        # test set-up
	sim.inv.add_new_forced(pile, "outpost_kit", 1, "test")
	var r: Dictionary = g.cmd("deploy_outpost", {"x": spot.x, "y": spot.y, "rot": 0.0, "inv": pile, "name": "Crater camp"})
	t.check(bool(r["ok"]), "the outpost is deployed: %s" % r["code"])
	if not bool(r["ok"]):
		g.dispose()
		t.done()
		return
	var bid: int = int(r["id"])
	var core: Dictionary = sim.state["buildings"][int(r["core"])]
	t.eq(sim.bases.count(), 2, "two bases")
	t.eq(sim.bases.name_of(bid), "Crater camp", "the outpost has its name")
	t.eq(sim.bases.base_of(int(core["id"])), bid, "the core belongs to the new base")
	t.eq(sim.bases.base_of(int(sim.state["lander_id"])), 1, "the lander stays in the first base")
	t.eq(sim.inv.count(pile, "outpost_kit"), 0, "the kit was used")
	t.check(sim.util.lander_supplied(core), "the core has air")
	t.near(sim.util.lander_seconds_left(int(core["id"])), 3.0 * float(sim.bal["day_length"]), 1.0, "air for three days")
	t.eq(g.cmd("rename_base", {"id": bid, "name": "Rim camp"})["ok"], true, "rename")
	t.eq(sim.bases.name_of(bid), "Rim camp", "renamed")
	t.eq(g.cmd("deploy_outpost", {"x": spot.x + 40.0, "y": spot.y, "rot": 0.0, "inv": pile})["code"], "no_kit", "no second kit")
	# Two colonists move in (test set-up) and sleep in the core, not at the landing base.
	var movers: Array = []
	for aid in sim.state["agents"]:
		if movers.size() < 2:
			var a: Dictionary = sim.state["agents"][aid]
			H.put_inside(sim, a, int(core["id"]))                                             # test set-up
			a["bed"] = -1
			movers.append(aid)
	for aid in movers:
		t.eq(sim.agents._assign_bed(sim.state["agents"][aid]), int(core["id"]), "a colonist at the outpost sleeps in its core")
	var rows: Array = sim.bases.list()
	t.eq(rows.size(), 2, "list() has both bases")
	t.eq(int(rows[1]["colonists"]), 2, "two colonists live at the outpost")
	# Stocks by base.
	sim.inv.add_new_forced(int(core["inv_out"]), "metal", 7, "test")                           # test set-up
	t.eq(int(sim.bases.totals(bid).get("metal", {}).get("total", 0)), 7, "the outpost's stock")
	t.check(int(sim.bases.totals(1).get("metal", {}).get("total", 0)) >= 100, "the landing base's stock is apart")
	# Work stays local: a plan at the landing base is not taken by the outpost people.
	g.cmd("place_building", {"def": "solar_array", "x": sim.world.center.x - 40.0, "y": sim.world.center.y - 40.0, "rot": 0.0})
	g.run(600)
	var far_task := 0
	for aid in movers:
		var a2: Dictionary = sim.state["agents"][aid]
		var tid: int = int(a2["task"])
		if tid != -1 and sim.state["tasks"].has(tid) and sim.jobs.task_base(sim.state["tasks"][tid]) == 1:
			far_task += 1
	t.eq(far_task, 0, "outpost colonists do not take work at the landing base")
	# The core's air runs low: the alert names the outpost.
	core["air_until"] = int(sim.state["tick"]) + 200                                          # test set-up
	g.run(60)
	var found := false
	for k in sim.state["issues"]:
		var iss: Dictionary = sim.state["issues"][k]
		if String(iss["code"]) == "core_expiry":
			found = true
			t.eq(int(iss["base"]), bid, "the alert is about the outpost")
			t.check(String(iss["text"]).begins_with("Rim camp:"), "the alert names it: %s" % iss["text"])
	t.check(found, "the core air alert is raised")
	# A save with two bases continues exactly.
	var cl: Dictionary = H.clone_by_save(sim)
	var sim2 = cl["sim"]
	for i in 600:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "a game with two bases continues exactly after a load")
	t.eq(sim.inv.audit(), {}, "ledger")
	sim2.dispose()
	g.dispose()
	t.done()

## Content: the Outpost Kit is made at the fabricator; an old (v3) save gets its first base.
func v4_outpost_content_and_migration(t) -> void:
	var sim = H.Sim.new()
	t.check(sim.content["recipes"].has("outpost_kit"), "a recipe makes the Outpost Kit")
	t.check((sim.content["buildings"]["fabricator"]["recipes"] as Array).has("outpost_kit"), "at the fabricator")
	t.check(bool(sim.content["buildings"]["outpost_core"]["core"]), "the outpost core is a core")
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var s2 = H.Sim.new()
	s2.load_state(dec["state"])
	t.eq(s2.bases.count(), 1, "an old save has one base after loading")
	var first: int = int(s2.bases.ids()[0])
	t.eq(s2.bases.base_of(int(s2.state["lander_id"])), first, "round its lander")
	var n_other := 0
	for id in s2.state["buildings"]:
		if s2.bases.base_of(int(id)) != first:
			n_other += 1
	t.eq(n_other, 0, "all its structures belong to it")
	s2.dispose()
	sim.dispose()
	t.done()

# ---------------------------------------------------------------- corridors per room (Paul)
## S 4, M 6, L 7, XL 8 corridors per room; airlocks 4, junctions 6. An XL room takes 8, the
## 9th is refused with its own reason; two corridors on one room are never closer than a door
## housing needs; an old save keeps its corridors.
func v4_room_link_counts(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	sim.state["flags"]["unlock_all"] = true                                    # test set-up
	# A spot where the XL room and nine junctions round it all fit.
	var xl: Dictionary = {}
	var r_xl: float = float(sim.sizes.def_for("storehouse", 3)["radius"])
	for gy in range(-6, 7):
		for gx in range(-6, 7):
			if not xl.is_empty():
				break
			var p: Vector2 = sim.place.snap_pos(sim.world.center + Vector2(gx, gy) * 45.0)
			if p.distance_to(sim.world.center) < 60.0 or sim.place.check_building("storehouse", p, 0.0, -1, 3) != "ok":
				continue
			var all_ok := true
			for k in 9:
				var q: Vector2 = sim.place.snap_pos(p + Vector2.RIGHT.rotated(k * TAU / 9.0) * (r_xl + 12.0))
				if sim.place.check_building("junction", q, 0.0) != "ok":
					all_ok = false
					break
			if all_ok:
				xl = sim.build.spawn_active("storehouse", p, 0.0, 3)                  # test set-up
	if not t.check(not xl.is_empty(), "an XL storehouse stands"):
		g.dispose()
		t.done()
		return
	for size_i in 4:
		var probe := {"def": "habitat", "size": size_i, "radius": float(sim.sizes.def_for("habitat", size_i)["radius"]), "id": -1}
		t.eq(sim.place.max_links(probe), [4, 6, 7, 8][size_i], "habitat %s takes %d corridors" % [sim.sizes.size_name(size_i), [4, 6, 7, 8][size_i]])
	t.eq(sim.place.max_links({"def": "airlock", "size": 1, "radius": 3.4, "id": -1}), 4, "an airlock keeps 4")
	t.eq(sim.place.max_links({"def": "junction", "size": 1, "radius": 2.5, "id": -1}), 6, "a junction keeps 6")
	var min_a: float = sim.place.link_min_angle(xl)
	t.check(min_a >= 28.0 and min_a >= sim.place.door_angle(float(xl["radius"])) - 0.001, "minimum angle %.1f covers the door housing (%.1f) and 28" % [min_a, sim.place.door_angle(float(xl["radius"]))])
	# Nine junctions round it, 40 degrees apart.
	var linked := 0
	var codes: Array = []
	var rr: float = float(xl["radius"]) + 12.0
	for k in 9:
		var q: Vector2 = sim.place.snap_pos((xl["pos"] as Vector2) + Vector2.RIGHT.rotated(k * TAU / 9.0) * rr)
		var j: Dictionary = {}
		if sim.place.check_building("junction", q, 0.0) == "ok":
			j = sim.build.spawn_active("junction", q, 0.0)                               # test set-up
		if j.is_empty():
			codes.append("no junction %d" % k)
			continue
		var r: Dictionary = sim.build.place_link("corridor", int(xl["id"]), int(j["id"]))
		if bool(r["ok"]):
			linked += 1
		else:
			codes.append(r["code"])
	t.eq(linked, 8, "the XL room took 8 corridors")
	t.eq(codes, ["links_full"], "the 9th is refused: links_full")
	t.check(sim.place.reason_text("links_full").begins_with("This room has all the corridors"), "with a clear reason")
	var dirs: Array = sim.place._corridor_dirs(int(xl["id"]))
	var worst := 360.0
	for i in dirs.size():
		for k in range(i + 1, dirs.size()):
			worst = minf(worst, rad_to_deg(absf((dirs[i] as Vector2).angle_to(dirs[k]))))
	t.check(worst >= sim.place.door_angle(float(xl["radius"])) - 0.01, "no two door housings overlap (closest %.1f deg)" % worst)
	# An old save keeps its corridors (the rule is for new links only).
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var old = H.Sim.new()
	old.load_state(dec["state"])
	var n0 := 0
	for id in old.state["buildings"]:
		if old.state["buildings"][id]["kind"] == "link":
			n0 += 1
	old.run_seconds(30.0)
	var n1 := 0
	for id in old.state["buildings"]:
		if old.state["buildings"][id]["kind"] == "link":
			n1 += 1
	t.eq(n1, n0, "an old save keeps its corridors")
	old.dispose()
	g.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 3: vehicles
## A free place for a structure at rmin..rmax metres from `around` (test set-up search).
static func _spot(sim, def_id: String, around: Vector2, rmin: float, rmax: float, size: int = 1) -> Vector2:
	var r: float = rmin
	while r <= rmax:
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(around + Vector2.RIGHT.rotated(k * TAU / 36.0) * r)
			if sim.place.check_building(def_id, p, 0.0, -1, size) == "ok":
				return p
		r += 6.0
	return Vector2(-1, -1)

## A point a rover reaches, dist metres from p (test set-up search).
static func _drive_target(sim, p: Vector2, dist: float) -> Vector2:
	for k in 24:
		var q: Vector2 = p + Vector2.RIGHT.rotated(k * TAU / 24.0) * dist
		if sim.nav.rover_ok(q) and bool(sim.nav.vehicle_path(p, q, "rover")["ok"]):
			return q
	return Vector2(-1, -1)

static func _depot_game(t, sim) -> Dictionary:
	sim.new_game(1001, "frontier")
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var p: Vector2 = _spot(sim, "rover_depot", lander["pos"], 30.0, 70.0, 2)
	if not t.check(p.x > 0.0, "a place for the depot"):
		return {}
	var d: Dictionary = sim.build.spawn_active("rover_depot", p, 0.0, 2)                 # test set-up
	var parts := {"metal": 60, "polymer": 30, "electronics": 30, "composite": 12, "spare_parts": 12}
	for r in parts:
		sim.inv.add_new_forced(int(lander["inv_out"]), r, parts[r], "test")               # test set-up
	return d

## A depot builds a medium rover from carried parts and technician work; two colonists walk
## to it and get in; it drives on the rover grid using charge and wearing; the cabin keeps
## the crew breathing; it returns to its bay, the crew get out near air; cargo loads from
## and unloads to the base stores; a save with a moving vehicle continues exactly.
func v4_vehicle_build_board_drive(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	var d: Dictionary = _depot_game(t, sim)
	if d.is_empty():
		g.dispose()
		t.done()
		return
	var did: int = int(d["id"])
	t.eq(sim.vehicles.bays(d).size(), 3, "a size L depot has three bays")
	t.eq(g.cmd("build_vehicle", {"depot": did, "kind": "tank"})["code"], "invalid", "unknown kind refused")
	t.eq(g.cmd("build_vehicle", {"depot": int(sim.state["lander_id"]), "kind": "small_rover"})["code"], "unknown", "only a depot builds vehicles")
	t.check(bool(g.cmd("build_vehicle", {"depot": did, "kind": "medium_rover"})["ok"]), "medium rover ordered")
	t.eq(g.cmd("build_vehicle", {"depot": did, "kind": "small_rover"})["code"], "busy", "one order at a time")
	var built: bool = g.run_until(func(): return sim.vehicles.count() == 1, 2 * 600 * 10)
	if not t.check(built, "the rover is built within two days (%s)" % str(d.get("vorder", {}))):
		g.dispose()
		t.done()
		return
	t.note("built at day %.2f" % (float(sim.state["tick"]) / 6000.0))
	var row: Dictionary = sim.vehicles.list()[0]
	var vid: int = int(row["id"])
	var v: Dictionary = sim.vehicles.get_v(vid)
	t.eq(row["kind"], "medium_rover", "kind")
	t.eq(int(row["seats"]), 6, "six seats")
	t.eq(int(row["bay"]), 2, "parked in the medium bay")
	t.near(float(row["charge"]), 300.0, 0.001, "full charge")
	t.check((v["pos"] as Vector2).distance_to(sim.vehicles.bay_pos(d, 2)) < 0.01, "at the bay")
	t.eq(sim.inv.position_of(int(row["cargo_inv"])), v["pos"], "the cargo is where the vehicle is")
	t.eq(d.get("vorder", {}), {}, "the order is done")
	t.eq(sim.inv.audit(), {}, "ledger after the build")
	# Board.
	var crew: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and crew.size() < 2:
			crew.append(int(aid))
			# Test set-up: rested, fed and inside the lander, so no need overrides the order.
			H.put_inside(sim, a, int(sim.state["lander_id"]))
			a["fatigue"] = 0.0
			a["hunger"] = 0.0
			a["thirst"] = 0.0
			a["suit"] = sim.agents.suit_cap()
	t.eq(g.cmd("vehicle_drive", {"id": vid, "x": v["pos"].x + 50.0, "y": v["pos"].y})["code"], "no_driver", "no driver, no drive")
	t.check(bool(g.cmd("vehicle_board", {"id": vid, "agents": crew})["ok"]), "board order")
	var aboard: bool = g.run_until(func(): return (v["crew"] as Array).size() == 2, 3000)
	if not t.check(aboard, "both colonists got in (%s)" % str([sim.state["agents"][crew[0]]["goal"], sim.state["agents"][crew[1]]["goal"]])):
		g.dispose()
		t.done()
		return
	for aid in crew:
		t.eq(sim.state["agents"][aid]["where"], "vehicle", "a rider is in the vehicle")
	# Drive 500 m.
	var goal: Vector2 = _drive_target(sim, v["pos"], 500.0)
	if not t.check(goal.x > 0.0, "a rover target 500 m out"):
		g.dispose()
		t.done()
		return
	var suit0: float = float(sim.state["agents"][crew[0]]["suit"])
	t.check(bool(g.cmd("vehicle_drive", {"id": vid, "x": goal.x, "y": goal.y})["ok"]), "drive order")
	t.eq(int(v["bay"]), -1, "it left its bay")
	# A save with a moving vehicle continues exactly.
	var cl: Dictionary = H.clone_by_save(sim)
	var sim2 = cl["sim"]
	for i in 300:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "a game with a moving vehicle continues exactly after a load")
	sim2.dispose()
	var there: bool = g.run_until(func(): return v["state"] == "parked", 3000)
	t.check(there, "it arrives (%s)" % v["block"])
	t.check((v["pos"] as Vector2).distance_to(sim.vehicles.park_spot(goal)) < 0.01, "at the target (its parking place)")
	t.check(sim.vehicles.slope_deg(v["pos"]) <= 10.0, "parked on ground of 10 deg or less")
	var odo: float = float(v["odo"])
	t.check(odo >= 500.0, "drove %.0f m" % odo)
	# The slow taxi out of the bay (bay -> apron) uses no charge and causes no wear.
	var taxi: float = (sim.vehicles.bays(d)[2]["pos"] as Vector2).distance_to(sim.vehicles.bays(d)[2]["exit"])
	t.near(float(v["charge"]), 300.0 - (odo - taxi) / 1000.0 * 12.0, 0.05, "charge used: 12 per km")
	t.near(float(v["wear"]), (odo - taxi) / 1000.0 * 1.0, 0.01, "wear: 1 per km")
	for aid in crew:
		t.eq(sim.state["agents"][aid]["pos"], v["pos"], "the crew rides with it")
		t.check(float(sim.state["agents"][aid]["suit"]) >= suit0 - 0.001, "the cabin keeps the suits full")
	g.run(700)
	t.eq((v["crew"] as Array).size(), 2, "far from air the crew stays aboard")
	# Back to the bay; the crew gets out after a minute and goes in.
	t.check(bool(g.cmd("vehicle_return", {"id": vid})["ok"]), "return order")
	t.check(g.run_until(func(): return v["state"] == "parked", 3000), "back")
	t.eq(int(v["bay"]), 2, "in its bay again")
	t.eq(int(v["depot"]), did, "at its depot")
	t.check(g.run_until(func(): return (v["crew"] as Array).is_empty(), 900), "the crew gets out near air")
	for aid in crew:
		var a: Dictionary = sim.state["agents"][aid]
		t.check(a["where"] != "vehicle" and a["state"] == "alive" and not a.has("veh"), "%s is out and alive" % a["name"])
	# Cargo from and to the base stores.
	var lander_inv: int = int(sim.state["buildings"][int(sim.state["lander_id"])]["inv_out"])
	var m0: int = H.world_count(sim, "metal")
	var r: Dictionary = g.cmd("vehicle_cargo", {"id": vid, "load": {"metal": 10}})
	t.eq(int(r.get("loaded", 0)), 10, "ten metal loaded: %s" % str(r))
	t.eq(sim.inv.count(int(v["cargo"]), "metal"), 10, "in the cargo")
	r = g.cmd("vehicle_cargo", {"id": vid, "unload": true})
	t.eq(sim.inv.count(int(v["cargo"]), "metal"), 0, "unloaded")
	t.check(sim.inv.count(lander_inv, "metal") > 0, "back in a store")
	t.eq(H.world_count(sim, "metal"), m0, "nothing lost")
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(int(sim.state["progress"]["deaths"]), 0, "no deaths")
	g.dispose()
	t.done()

## The other vehicle rules: a hopper flies hops over the terrain and pays fuel per hop; an
## open rover turns back when the crew's suit air runs low; wear breaks a vehicle; a depot
## repairs it with spare parts and refuels a hopper with rocket fuel; vehicles do not drive
## on the old maps.
func v4_vehicle_rules(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	var d: Dictionary = _depot_game(t, sim)
	if d.is_empty():
		g.dispose()
		t.done()
		return
	var pilot: Dictionary = {}
	for aid in sim.state["agents"]:
		if pilot.is_empty():
			pilot = sim.state["agents"][aid]
	# Hopper: 900 m in three hops of 3 fuel.
	var hp: Vector2 = sim.vehicles.bay_pos(d, 0)
	var hop: Dictionary = sim.vehicles.spawn("hopper", hp, int(d["id"]))                 # test set-up
	hop["bay"] = 0                                                                        # test set-up: parked in bay 0
	H.put_outside(sim, pilot, hp + Vector2(2, 0), sim.agents.suit_cap())               # test set-up
	t.check(sim.vehicles.board(pilot, int(hop["id"])), "the pilot gets in")
	var far: Vector2 = hp + Vector2(900, 0)
	t.check(bool(g.cmd("vehicle_drive", {"id": int(hop["id"]), "x": far.x, "y": far.y})["ok"]), "hop order")
	t.eq((hop["path"] as Array).size(), 5, "out of the bay, then three hops")
	t.check(g.run_until(func(): return hop["state"] == "parked", 2000), "the hopper lands at the target")
	t.near(float(hop["fuel"]), 30.0 - 9.0, 0.001, "three hops used 9 fuel")
	t.near(float(hop["wear"]), 6.0, 0.001, "wear 2 per hop")
	# Back at the depot: refuel from rocket fuel in the depot store (1 item = 3 fuel).
	sim.inv.add_new_forced(int(d["inv_out"]), "rocket_fuel", 7, "test")                 # test set-up
	t.check(bool(g.cmd("vehicle_return", {"id": int(hop["id"])})["ok"]), "hopper return")
	t.check(g.run_until(func(): return hop["state"] == "parked", 2000), "back at the depot")
	g.run(80)
	t.near(float(hop["fuel"]), 30.0, 0.001, "refuelled to full with six items")
	t.eq(sim.inv.count(int(d["inv_out"]), "rocket_fuel"), 1, "one item left")
	sim.vehicles.alight_all(hop)
	# An open rover far out with low suit air turns back by itself.
	var rover: Dictionary = sim.vehicles.spawn("small_rover", _drive_target(sim, hp, 400.0), -1)   # test set-up
	H.put_outside(sim, pilot, rover["pos"] + Vector2(2, 0), 90.0)                         # test set-up
	t.check(sim.vehicles.board(pilot, int(rover["id"])), "the driver gets in")
	g.run(20)
	t.eq(rover["state"], "driving", "the open rover turns back")
	t.check(bool(rover.get("returning", false)), "marked as returning")
	t.check(g.run_until(func(): return rover["state"] == "parked", 2000), "it reaches the depot")
	t.check(not sim.vehicles.depot_at(rover).is_empty(), "at the depot")
	g.run(100)
	t.eq(pilot["state"], "alive", "the driver lives")
	t.check(pilot["where"] != "vehicle", "the driver got out near air")
	# Wear breaks a vehicle; spare parts at the depot repair it.
	rover["wear"] = 99.99                                                                # test set-up
	H.put_outside(sim, pilot, rover["pos"] + Vector2(2, 0), sim.agents.suit_cap())      # test set-up
	sim.vehicles.board(pilot, int(rover["id"]))
	var near: Vector2 = _drive_target(sim, rover["pos"], 60.0)
	g.cmd("vehicle_drive", {"id": int(rover["id"]), "x": near.x, "y": near.y})
	g.run(100)
	t.eq(rover["state"], "broken", "it broke down")
	t.eq(g.cmd("vehicle_drive", {"id": int(rover["id"]), "x": near.x, "y": near.y})["code"], "broken", "a broken vehicle does not drive")
	sim.vehicles.alight_all(rover)
	sim.inv.add_new_forced(int(d["inv_out"]), "spare_parts", 2, "test")                 # test set-up
	rover["pos"] = sim.vehicles.bay_pos(d, 1)                                            # test set-up: towed home
	g.run(20)
	t.eq(rover["state"], "parked", "repaired with spare parts")
	t.check(float(rover["wear"]) <= 75.0, "wear down to %.1f" % float(rover["wear"]))
	t.eq(sim.inv.audit(), {}, "ledger")
	# Old maps: no driving.
	var old = H.Sim.new()
	old.new_game(1001)
	var ov: Dictionary = old.vehicles.spawn("small_rover", old.world.center + Vector2(30, 0), -1)   # test set-up
	var oa: Dictionary = {}
	for aid in old.state["agents"]:
		oa = old.state["agents"][aid]
	H.put_outside(old, oa, ov["pos"] + Vector2(2, 0), 90.0)                               # test set-up
	old.vehicles.board(oa, int(ov["id"]))
	t.eq(old.vehicles.drive_to(ov, ov["pos"] + Vector2(40, 0)), "no_route", "vehicles do not drive on the old maps")
	old.dispose()
	g.dispose()
	t.done()

## A medium rover on a route carries goods from the landing base to an outpost and comes
## back; the driver stays aboard for the whole route.
func v4_vehicle_route(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	var d: Dictionary = _depot_game(t, sim)
	if d.is_empty():
		g.dispose()
		t.done()
		return
	var spot: Vector2 = _outpost_spot(sim, 420.0)
	if not t.check(spot.x > 0.0, "a place for the outpost"):
		g.dispose()
		t.done()
		return
	var pile: int = sim.inv.create_inv("g", 0, "pile", 100000, spot + Vector2(12, 0))        # test set-up
	sim.inv.add_new_forced(pile, "outpost_kit", 1, "test")
	var r: Dictionary = g.cmd("deploy_outpost", {"x": spot.x, "y": spot.y, "rot": 0.0, "inv": pile, "name": "Far camp"})
	if not t.check(bool(r["ok"]), "outpost deployed: %s" % r["code"]):
		g.dispose()
		t.done()
		return
	var bid: int = int(r["id"])
	var core: Dictionary = sim.state["buildings"][int(r["core"])]
	var v: Dictionary = sim.vehicles.spawn("medium_rover", sim.vehicles.bay_pos(d, 2), int(d["id"]))   # test set-up
	v["bay"] = 2
	var drv: Dictionary = {}
	for aid in sim.state["agents"]:
		if drv.is_empty():
			drv = sim.state["agents"][aid]
	H.put_outside(sim, drv, v["pos"] + Vector2(2, 0), sim.agents.suit_cap())             # test set-up
	t.check(sim.vehicles.board(drv, int(v["id"])), "the driver gets in")
	t.eq(g.cmd("vehicle_route", {"id": int(v["id"]), "a": 1, "b": 1})["code"], "invalid", "a route needs two bases")
	t.check(bool(g.cmd("vehicle_route", {"id": int(v["id"]), "a": 1, "b": bid, "load": {"metal": 20}})["ok"]), "route set")
	var m_core0: int = sim.inv.count(int(core["inv_out"]), "metal")
	var ok: bool = g.run_until(func(): return int(v["route"].get("trips", 0)) >= 1 and v["route"].get("leg", "") == "to_a", 6000)
	t.check(ok, "one trip done (%s, %s)" % [str(v["route"]), v["block"]])
	t.eq(sim.inv.count(int(core["inv_out"]), "metal") - m_core0, 20, "twenty metal reached the outpost")
	t.eq(sim.inv.count(int(v["cargo"]), "metal"), 0, "the cargo is empty on the way back")
	t.eq((v["crew"] as Array).size(), 1, "the driver stays aboard on a route")
	t.check(g.run_until(func(): return v["route"].get("leg", "") == "to_b", 6000), "the second trip starts")
	t.check(bool(g.cmd("vehicle_route", {"id": int(v["id"]), "stop": true})["ok"]), "route ended")
	t.eq(v["route"], {}, "no route")
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(int(sim.state["progress"]["deaths"]), 0, "no deaths")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 4: orders
static func _rested(sim, a: Dictionary, bid: int) -> void:
	# Test set-up: fed, rested, full suit, inside a room, so no need overrides an order.
	H.put_inside(sim, a, bid)
	a["fatigue"] = 0.0
	a["hunger"] = 0.0
	a["thirst"] = 0.0
	a["suit"] = sim.agents.suit_cap()

## Orders: go, stay, return, board, work_at and per-colonist job priorities; refusals with a
## reason (suit air, radiation, no way), confirm to override; a save with orders continues
## exactly; a vehicle explores an area.
func v4_orders(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lid: int = int(sim.state["lander_id"])
	var lander: Dictionary = sim.state["buildings"][lid]
	var ids: Array = []
	for aid in sim.state["agents"]:
		ids.append(int(aid))
	var a: Dictionary = sim.state["agents"][ids[0]]
	var b: Dictionary = sim.state["agents"][ids[1]]
	var c: Dictionary = sim.state["agents"][ids[2]]
	for x in [a, b, c]:
		_rested(sim, x, lid)
	# Refusals.
	t.eq(g.cmd("order", {"agents": [999999], "kind": "go", "x": 0, "y": 0})["code"], "unknown", "unknown colonist")
	t.eq(g.cmd("order", {"agents": [ids[0]], "kind": "dance"})["code"], "invalid", "unknown order")
	var far: Vector2 = _drive_target(sim, lander["pos"], 700.0)
	var r: Dictionary = g.cmd("order", {"agents": [ids[0]], "kind": "go", "x": far.x, "y": far.y})
	t.eq(r["code"], "suit_range", "700 m on foot is refused: %s" % r["text"])
	t.check(bool(r["refused"][ids[0]]["confirmable"]), "the player may confirm it")
	t.check(String(r["text"]).length() > 10, "with a reason")
	r = g.cmd("order", {"agents": [ids[0]], "kind": "go", "x": far.x, "y": far.y, "confirm": true})
	t.check(bool(r["ok"]), "confirmed, it is given")
	t.check(sim.orders.confirmed(a), "the order is marked confirmed")
	g.cmd("order_clear", {"agents": [ids[0]]})
	t.check(not a.has("order"), "order cleared")
	_rested(sim, a, lid)
	var near_out: Vector2 = lander["pos"] + Vector2(0, 30)
	t.eq(g.cmd("order", {"agents": [ids[0]], "kind": "stay", "x": near_out.x, "y": near_out.y})["code"], "exposed_stay", "staying outside is refused")
	var hot := Vector2(-1, -1)
	for d in sim.world.deposit_sites:
		if d["kind"] == "uranium" and float(sim.world.rad_at(float(d["x"]), float(d["y"]))) > 1.0:
			hot = Vector2(d["x"], d["y"])
			break
	if hot.x > 0.0:
		var hc: Dictionary = sim.orders.check(a, {"kind": "go", "x": hot.x, "y": hot.y})
		t.check(hc["code"] == "radiation" or hc["code"] == "no_path", "a uranium field is refused for radiation: %s" % hc["text"])
	# Go outside, 30 m: arrives, the order ends.
	r = g.cmd("order", {"agents": [ids[0]], "kind": "go", "x": near_out.x, "y": near_out.y})
	t.check(bool(r["ok"]), "go accepted")
	t.eq(a["goal"], "Going to the ordered place", "the goal says so")
	t.check(g.run_until(func(): return not a.has("order"), 1200), "arrived, the order ended")
	t.check((a["pos"] as Vector2).distance_to(near_out) < 3.0, "at the place (%.1f m)" % (a["pos"] as Vector2).distance_to(near_out))
	# Return to base.
	t.check(bool(g.cmd("order", {"agents": [ids[0]], "kind": "return"})["ok"]), "return accepted")
	t.check(g.run_until(func(): return not a.has("order"), 1500), "back at base, the order ended")
	t.eq(a["where"], "in", "inside")
	t.eq(sim.bases.base_of(int(a["bld"])), 1, "in the home base")
	# Stay in the lander for a minute though there is work.
	_rested(sim, b, lid)
	r = g.cmd("order", {"agents": [ids[1]], "kind": "stay", "x": lander["pos"].x, "y": lander["pos"].y})
	t.check(bool(r["ok"]), "stay in the lander accepted")
	var left := false
	for i in 60:
		g.run(10)
		if b["where"] != "in" or int(b["bld"]) != lid:
			left = true
	t.check(not left, "the colonist stays in the lander for a minute")
	t.check(b.has("order") and b["goal"] == "Staying here (order)", "on the order")
	# A save with orders continues exactly.
	var cl: Dictionary = H.clone_by_save(sim)
	var sim2 = cl["sim"]
	for i in 300:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "a game with orders continues exactly after a load")
	sim2.dispose()
	g.cmd("order_clear", {"agents": [ids[1]]})
	# Work at one structure.
	var sp: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 60.0)
	var pb: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": sp.x, "y": sp.y, "rot": 0.0})
	t.check(bool(pb["ok"]), "a solar array is planned")
	var site_id: int = int(pb.get("id", -1))
	_rested(sim, b, lid)
	# The others may not build (their own job priorities), so the work is left for this one.
	for oid in ids:
		if oid != ids[1]:
			g.cmd("set_jobs", {"agent": oid, "jobs": {"construction": 0}})
	t.check(bool(g.cmd("order", {"agents": [ids[1]], "kind": "work_at", "b": site_id})["ok"]), "work_at accepted")
	var other := false
	var took := false
	for i in 90:
		g.run(10)
		var tid: int = int(b["task"])
		if tid != -1 and sim.state["tasks"].has(tid):
			took = true
			if int(sim.state["tasks"][tid]["bld"]) != site_id:
				other = true
	t.check(took, "the colonist works on the ordered structure")
	t.check(not other, "and on nothing else")
	g.cmd("order_clear", {"agents": [ids[1]]})
	for oid in ids:
		g.cmd("set_jobs", {"agent": oid, "clear": true})
	# Own job priorities.
	t.eq(g.cmd("set_jobs", {"agent": ids[2], "jobs": {"juggling": 2}})["code"], "invalid", "unknown category")
	var off := {}
	for cat in sim.orders.job_categories():
		off[cat] = 0
	off["logistics"] = 3
	t.check(bool(g.cmd("set_jobs", {"agent": ids[2], "jobs": off})["ok"]), "set_jobs")
	_rested(sim, c, lid)
	var wrong := 0
	var wrong_cats := {}
	for i in 120:
		g.run(10)
		var tid2: int = int(c["task"])
		if tid2 != -1 and sim.state["tasks"].has(tid2) and String(sim.state["tasks"][tid2]["cat"]) != "logistics":
			wrong += 1
			wrong_cats[String(sim.state["tasks"][tid2]["kind"]) + ":" + String(sim.state["tasks"][tid2]["cat"])] = true
	t.eq(wrong, 0, "a colonist with only logistics allowed takes no other work %s" % str(wrong_cats.keys()))
	t.check(bool(g.cmd("set_jobs", {"agent": ids[2], "clear": true})["ok"]) and not c.has("jobs"), "own priorities cleared")
	# Board by order, then explore an area.
	var rp: Vector2 = _spot(sim, "solar_array", lander["pos"], 30.0, 60.0)
	var rv: Dictionary = sim.vehicles.spawn("medium_rover", rp, -1)                         # test set-up
	_rested(sim, a, lid)
	t.check(bool(g.cmd("order", {"agents": [ids[0]], "kind": "board", "v": int(rv["id"])})["ok"]), "board order")
	t.check(g.run_until(func(): return (rv["crew"] as Array).size() == 1, 1500), "the colonist got in")
	t.eq(sim.orders.check(a, {"kind": "go", "x": 0, "y": 0})["code"], "in_vehicle", "a rider must get out first")
	var ex: Dictionary = g.cmd("vehicle_explore", {"id": int(rv["id"]), "x": rv["pos"].x, "y": rv["pos"].y, "r": 120.0})
	t.check(bool(ex["ok"]), "explore order: %s" % ex["code"])
	t.check(g.run_until(func(): return not rv.has("explore") and rv["state"] == "parked", 6000), "the loop is done")
	t.check(float(rv["odo"]) > 500.0, "drove the loop (%.0f m)" % float(rv["odo"]))
	t.eq(sim.inv.audit(), {}, "ledger")
	t.eq(int(sim.state["progress"]["deaths"]), 0, "no deaths")
	g.dispose()
	t.done()

## Debug-only commands for screenshots (UI request): refused without debug; with debug a
## finished structure, a vehicle (free place or a depot bay) and an instant completion.
func v4_debug_commands(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	t.eq(g.cmd("spawn_vehicle", {"kind": "small_rover"})["code"], "debug_only", "refused without debug")
	t.eq(g.cmd("finish_building", {"id": 1})["code"], "debug_only", "finish refused without debug")
	sim.new_game(1001, "frontier", {"debug": true})
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var r: Dictionary = g.cmd("spawn_vehicle", {"kind": "medium_rover"})
	t.check(bool(r["ok"]), "a rover beside the lander: %s" % r["code"])
	t.eq(sim.vehicles.count(), 1, "one vehicle")
	t.eq(g.cmd("spawn_vehicle", {"kind": "tank"})["code"], "invalid", "unknown kind")
	var p: Vector2 = _spot(sim, "rover_depot", lander["pos"], 30.0, 70.0, 2)
	r = g.cmd("place_finished", {"def": "rover_depot", "x": p.x, "y": p.y, "rot": 0.0, "size": 2})
	t.check(bool(r["ok"]), "a finished depot: %s" % r["code"])
	var did: int = int(r.get("id", -1))
	t.eq(sim.state["buildings"].get(did, {}).get("state", ""), "active", "it is active")
	r = g.cmd("spawn_vehicle", {"kind": "hopper", "depot": did})
	t.check(bool(r["ok"]), "a hopper in a bay")
	t.eq(int(sim.vehicles.get_v(int(r["id"]))["bay"]), 0, "in bay 0")
	var sp: Vector2 = _spot(sim, "solar_array", lander["pos"], 25.0, 70.0)
	var pb: Dictionary = g.cmd("place_building", {"def": "solar_array", "x": sp.x, "y": sp.y, "rot": 0.0})
	g.run(300)
	r = g.cmd("finish_building", {"id": int(pb["id"])})
	t.check(bool(r["ok"]), "finish a plan at once")
	t.eq(sim.state["buildings"][int(pb["id"])]["state"], "active", "the plan is complete")
	t.eq(g.cmd("finish_building", {"id": int(pb["id"])})["code"], "not_building", "twice: refused")
	g.run(100)
	t.eq(sim.inv.audit(), {}, "ledger")
	t.check(H.log_entries(sim, "debug").size() >= 4, "each debug command is in the log")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 5: materials, crafting, tech tree
const HIGH_END := ["fuel_rod", "he3_fuel", "magnet", "superconductor", "graphene", "crystal_lattice", "metamaterial"]

## Steps from raw goods to an item (1 = made from raw goods only). Raw: no recipe makes it.
static func _depth(item: String, makers: Dictionary, seen: Dictionary) -> int:
	if not makers.has(item) or seen.has(item):
		return 0
	seen[item] = true
	var best := 99
	for rec in makers[item]:
		var d := 0
		for inp in rec["inputs"]:
			d = maxi(d, _depth(String(inp), makers, seen))
		best = mini(best, d + 1)
	seen.erase(item)
	return best

## The whole content graph holds together: sizes of the tree, every name exists, every item can
## be made or found, every tech's packs can be made without that tech, high-end chains have at
## least three steps, and ART-HAB's industry rooms have their furniture counts.
func v4_content_tree(t) -> void:
	var sim = H.Sim.new()
	var c: Dictionary = sim.content
	var items: Dictionary = c["items"]
	var recipes: Dictionary = {}
	for rid in c["recipes"]:
		if not String(rid).begins_with("_") and not bool(c["recipes"][rid].get("menu", false)):
			recipes[rid] = c["recipes"][rid]
	var techs: Dictionary = c["techs"]
	t.check(items.size() >= 60, "at least 60 items (%d)" % items.size())
	t.check(recipes.size() >= 40, "at least 40 recipes (%d)" % recipes.size())
	t.check(techs.size() >= 80, "at least 80 techs (%d)" % techs.size())
	var bad: Array = []
	var makers := {}
	for rid in recipes:
		var r: Dictionary = recipes[rid]
		for k in ["inputs", "outputs"]:
			for it in r[k]:
				if not items.has(it):
					bad.append("%s: %s" % [rid, it])
		for it in r["outputs"]:
			if not makers.has(it):
				makers[it] = []
			makers[it].append(r)
	t.eq(bad, [], "every recipe names real items")
	var no_tier: Array = []
	for it in items:
		var tr: int = int(items[it].get("tier", 0))
		if tr < 1 or tr > 3 or String(items[it].get("tier_name", "")) != ["", "basic", "mid", "high"][tr]:
			no_tier.append(it)
	t.eq(no_tier, [], "every item has a tier (1 basic, 2 mid, 3 high) and its name")
	var branches := {}
	for tid in techs:
		branches[String(techs[tid]["branch"])] = true
	var raw_b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/research.json"))["branches"]
	var unnamed: Array = []
	for br in branches:
		if not raw_b.has(br) or String(raw_b[br].get("name", "")) == "":
			unnamed.append(br)
	t.eq(unnamed, [], "every research branch has a name (%d branches)" % branches.size())
	# Recipes used by buildings, and every building recipe exists.
	var used := {}
	var bad_b: Array = []
	for bid in c["buildings"]:
		var d: Dictionary = c["buildings"][bid]
		for rid in d.get("recipes", []):
			used[rid] = true
			if not c["recipes"].has(rid):
				bad_b.append("%s: %s" % [bid, rid])
			elif bool(c["recipes"][rid].get("auto", false)) != bool(d.get("auto_recipe", false)):
				bad_b.append("%s: %s auto mismatch" % [bid, rid])
		if String(d.get("research", "")) != "" and not techs.has(String(d["research"])):
			bad_b.append("%s: research %s" % [bid, d["research"]])
	var unused: Array = []
	for rid in recipes:
		if not used.has(rid) and rid != "mine":
			unused.append(rid)
	t.eq(bad_b, [], "every building recipe exists, auto matches, research exists")
	t.eq(unused, [], "every recipe has a building")
	# Every item comes from somewhere.
	var sources := {"exotic": true, "silicate": true, "rocket_fuel": true, "algae": true, "water": true, "ore": true, "meals": true, "biomass": true}
	for k in c["terrain_v4"]["deposit_items"]:
		sources[String(c["terrain_v4"]["deposit_items"][k]["item"])] = true
	for cr in c["crops"]:
		sources[cr] = true
	for ds in c["dishes"]:
		sources[ds] = true
	var orphan: Array = []
	for it in items:
		if not makers.has(it) and not sources.has(it) and String(items[it]["category"]) != "find":
			orphan.append(it)
	t.eq(orphan, [], "every item is made, mined, grown, cooked or found")
	# Techs: requirements exist, no cycles, deposits known, packs can be made without the tech.
	var bad_t: Array = []
	var rec_tech := {}
	for tid in techs:
		for rid in techs[tid].get("unlocks", {}).get("recipes", []):
			rec_tech[rid] = tid
			if not c["recipes"].has(rid):
				bad_t.append("%s unlocks %s" % [tid, rid])
		for req in techs[tid].get("requires", []):
			if not techs.has(req):
				bad_t.append("%s requires %s" % [tid, req])
		for dk in techs[tid].get("unlocks", {}).get("deposits", []):
			if not c["terrain_v4"]["deposit_items"].has(dk):
				bad_t.append("%s deposit %s" % [tid, dk])
	t.eq(bad_t, [], "tech names are real")
	var cyc: Array = []
	for tid in techs:
		if _needs(techs, tid, tid, {}):
			cyc.append(tid)
	t.eq(cyc, [], "no tech needs itself")
	var dead: Array = []
	for tid in techs:
		for pk in techs[tid].get("packs", {}):
			var ok := false
			for r2 in makers.get(pk, []):
				var rid2: String = ""
				for k2 in recipes:
					if recipes[k2] == r2:
						rid2 = k2
				var gate: String = String(rec_tech.get(rid2, ""))
				if gate == "" or (gate != tid and not _needs(techs, gate, tid, {})):
					ok = true
			if not ok:
				dead.append("%s needs %s" % [tid, pk])
	t.eq(dead, [], "every tech's packs can be made before that tech is done")
	for hi in HIGH_END:
		var dpt: int = _depth(hi, makers, {})
		t.check(dpt >= 2 and dpt + 1 >= 3, "%s has a chain of at least 3 steps from the ground (%d recipe steps after mining)" % [hi, dpt])
	# ART-HAB's industry rooms.
	for rid in ["steel_mill", "titanium_smelter", "ceramics_kiln", "carbon_works", "battery_plant", "parts_works", "magnet_works", "superconductor_lab", "metamaterial_foundry"]:
		var d2: Dictionary = c["buildings"].get(rid, {})
		t.eq(d2.get("sizes", {}).get("radius", []), [6.0, 7.5, 9.6, 11.7], "%s radii" % rid)
		t.eq(d2.get("furniture", {}).get("work_slots", []), [1.0, 1.0, 2.0, 3.0], "%s work places" % rid)
		t.eq(d2.get("furniture", {}).get("stands", []), [1.0, 2.0, 2.0, 3.0], "%s stands" % rid)
	for rid in ["fuel_rod_plant", "he3_separator", "graphene_reactor", "chemical_plant", "crystal_refinery"]:
		var d3: Dictionary = c["buildings"].get(rid, {})
		t.check(d3.get("kind", "") == "exterior" and int(d3.get("stage", 9)) == 0 and bool(d3.get("auto_recipe", false)), "%s is a placeable automatic exterior" % rid)
	sim.dispose()
	t.done()

static func _needs(techs: Dictionary, from: String, target: String, seen: Dictionary) -> bool:
	for req in techs[from].get("requires", []):
		if req == target:
			return true
		if seen.has(req):
			continue
		seen[req] = true
		if techs.has(req) and _needs(techs, req, target, seen):
			return true
	return false

## Materials in play: a mine gives what its deposit holds and waits for the research; the steel
## mill makes alloy steel with slag left over; a recipe that needs level 2 is refused at level 1;
## old maps still mine iron ore.
func v4_materials_in_play(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	var dep: Dictionary = {}
	for d in sim.state["deposits"]:
		if String(d.get("kind", "")) == "titanium":
			dep = d
			break
	if t.check(not dep.is_empty(), "a titanium deposit"):
		t.eq(sim.prod.deposit_info(dep)["item"], "titanium_ore", "it gives titanium ore")
		t.check(sim.prod.deposit_locked(dep), "locked until Titanium Metallurgy")
		var m: Dictionary = sim.build.spawn_active("mine", Vector2(dep["x"], dep["y"]), 0.0)   # test set-up
		m["powered"] = true                                                                   # test set-up
		t.eq(sim.prod.machine_block(m), "deposit_locked", "the mine says why it waits")
		sim.state["research"]["done"]["ind_ti"] = int(sim.state["tick"])                     # test set-up
		t.eq(sim.prod.machine_block(m), "", "after the research it can work")
		t.check(sim.prod.start_batch(m), "a batch starts")
		t.eq(m["batch"]["outputs"], {"titanium_ore": 2}, "the batch makes titanium ore")
		sim.prod.work_batch(m, 1000.0)
		t.eq(sim.inv.count(int(m["inv_out"]), "titanium_ore"), 2, "titanium ore made")
	var old = H.Sim.new()
	old.new_game(1001)
	t.eq(old.prod.deposit_info(old.state["deposits"][0])["item"], "ore", "old maps: iron ore")
	old.dispose()
	# The steel mill on the old map (a complete little base).
	var g2 = H.empty_game(1001)
	var s2 = g2.sim
	s2.state["flags"]["unlock_all"] = true                                                  # test set-up
	var res: Dictionary = H.layout(s2, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"},
		{"place": "steel_mill", "as": "F1", "at": "S1"}, {"link": "corridor", "a": "H1", "b": "F1"}])
	t.eq(res["errors"], [], "layout")
	if res["errors"].is_empty():
		g2.run(2)
		H.fill_utilities(s2, 1.0, 0.5, true)
		var store: int = s2.state["buildings"][s2.state["lander_id"]]["inv_out"]
		s2.inv.add_new_forced(store, "ore", 8, "test")                                        # test set-up
		s2.inv.add_new_forced(store, "carbon_ore", 4, "test")
		var ok: bool = g2.run_until(func(): return int(s2.state["metrics"]["produced"].get("alloy", 0)) >= 2, 12000)
		t.check(ok, "the steel mill makes alloy steel")
		t.check(int(s2.state["metrics"]["produced"].get("slag", 0)) >= 2, "slag is left over")
		var fab: Dictionary = s2.build.spawn_active("fabricator", s2.place.snap_pos(s2.world.center + Vector2(-60, 60)), 0.0)   # test set-up
		t.eq(s2.prod.set_recipe(fab, "hull_plate_ti")["code"], "level_low", "a level 2 recipe is refused at level 1")
		fab["level"] = 2                                                                     # test set-up
		t.eq(s2.prod.set_recipe(fab, "hull_plate_ti")["code"], "ok", "accepted at level 2")
		t.eq(s2.inv.audit(), {}, "ledger")
	g2.dispose()
	g.dispose()
	t.done()

## Food margin (coordinator): in new games each settler lands with 8 ration meals; saves from
## before V4 keep the old rule (none).
func v4_food_margin(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	sim.state["flags"]["unlock_all"] = true                                             # test set-up
	var m0: int = H.world_count(sim, "meals")
	t.check(bool(g.cmd("admit_settlers", {"count": 4})["ok"]), "four settlers land")
	t.eq(H.world_count(sim, "meals") - m0, 32, "they bring 32 ration meals")
	t.eq(H.log_entries(sim, "settler_supplies").size(), 1, "the log says so")
	t.eq(sim.inv.audit(), {}, "ledger")
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var old = H.Sim.new()
	old.load_state(dec["state"])
	t.eq(int(old.bal.get("settler_meals", -1)), 0, "an old save: no settler meals")
	t.check(not bool(old.bal.get("packs_yield_to_sites", true)), "an old save: packs keep their old rule")
	old.dispose()
	g.dispose()
	t.done()

## Depot bays at ART-HAB's Anchor_Bay_<i> (RENDER request): inside the hangar, turned with the
## depot; the colonist boards on the apron in front of the bay door; a vehicle leaves and comes
## back through the door and parks facing out.
func v4_depot_bays(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var p: Vector2 = _spot(sim, "rover_depot", lander["pos"], 30.0, 70.0, 2)
	var d: Dictionary = sim.build.spawn_active("rover_depot", p, 0.7, 2)                 # test set-up
	var bays: Array = sim.vehicles.bays(d)
	t.eq(bays.size(), 3, "size L: three bays")
	var want := [Vector2(-1.85, 5.0), Vector2(-1.85, 0.3), Vector2(-1.85, -4.7)]
	for i in 3:
		var exp: Vector2 = p + want[i].rotated(0.7)
		t.check((bays[i]["pos"] as Vector2).distance_to(exp) < 0.001, "bay %d at the model anchor" % i)
		t.check((bays[i]["pos"] as Vector2).distance_to(p) < float(d["radius"]), "bay %d is inside the hangar" % i)
		t.check((bays[i]["exit"] as Vector2).distance_to(p) > float(d["radius"]), "its exit is on the apron")
	var pm: Vector2 = _spot(sim, "rover_depot", lander["pos"], 80.0, 140.0, 1)
	var bm: Array = sim.vehicles.bays(sim.build.spawn_active("rover_depot", pm, 0.0, 1))        # test set-up
	t.eq(bm.size(), 2, "size M: two bays")
	if bm.size() == 2:
		t.check((bm[0]["pos"] as Vector2).distance_to(pm + Vector2(-2.0, 2.35)) < 0.001 and (bm[1]["pos"] as Vector2).distance_to(pm + Vector2(-2.0, -2.35)) < 0.001, "size M bays at its anchors")
	var r: Dictionary = g.cmd("spawn_vehicle", {"kind": "medium_rover", "depot": int(d["id"])})
	var v: Dictionary = sim.vehicles.get_v(int(r["id"]))
	t.eq(int(v["bay"]), 2, "the medium rover takes the medium bay")
	var bp: Vector2 = sim.vehicles.board_point(v)
	t.check(sim.nav.is_walkable(bp), "the board point is walkable")
	t.check(bp.distance_to(bays[2]["exit"]) < 6.0, "in front of the bay door (%.1f m)" % bp.distance_to(bays[2]["exit"]))
	var a: Dictionary = {}
	for aid in sim.state["agents"]:
		if a.is_empty():
			a = sim.state["agents"][aid]
	_rested(sim, a, int(lander["id"]))
	t.check(bool(g.cmd("vehicle_board", {"id": int(v["id"]), "agents": [int(a["id"])]})["ok"]), "board order")
	t.check(g.run_until(func(): return (v["crew"] as Array).size() == 1, 1500), "the colonist gets in at the door")
	var goal: Vector2 = _drive_target(sim, bays[2]["exit"], 200.0)
	t.check(bool(g.cmd("vehicle_drive", {"id": int(v["id"]), "x": goal.x, "y": goal.y})["ok"]), "drive out")
	t.check((v["path"][1] as Vector2).distance_to(bays[2]["exit"]) < 0.01, "out through the bay door first")
	t.check(g.run_until(func(): return v["state"] == "parked", 3000), "arrives")
	t.check(bool(g.cmd("vehicle_return", {"id": int(v["id"])})["ok"]), "return")
	var path: Array = v["path"]
	t.check((path[path.size() - 2] as Vector2).distance_to(bays[2]["exit"]) < 0.01, "back in through the door")
	t.check(g.run_until(func(): return v["state"] == "parked", 3000), "parked")
	t.eq(int(v["bay"]), 2, "in its bay")
	t.check((v["pos"] as Vector2).distance_to(bays[2]["pos"]) < 0.01, "on the anchor")
	t.near(float(v["rot"]), 0.7, 0.001, "facing out through the door")
	g.dispose()
	t.done()

## Coordinator rule: an order whose walk stays indoors never checks suit air (UI finding: "stay"
## at the lander for a colonist in the lander was refused for suit air).
func v4_indoor_orders_need_no_air(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	g.run(3)
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var a: Dictionary = {}
	for aid in sim.state["agents"]:
		if a.is_empty():
			a = sim.state["agents"][aid]
	H.put_inside(sim, a, int(lander["id"]))                                              # test set-up
	a["suit"] = 0.0                                                                      # test set-up: an empty suit
	var c: Dictionary = sim.orders.check(a, {"kind": "stay", "x": lander["pos"].x, "y": lander["pos"].y})
	t.eq(c["code"], "ok", "stay in the lander, empty suit: accepted (%s)" % c["text"])
	c = sim.orders.check(a, {"kind": "go", "x": lander["pos"].x, "y": lander["pos"].y})
	t.eq(c["code"], "ok", "go within the lander: accepted")
	# Outside, the hatch fills the suit: a far walk is still refused for suit air.
	var far: Vector2 = _drive_target(sim, lander["pos"], 700.0)
	c = sim.orders.check(a, {"kind": "go", "x": far.x, "y": far.y})
	t.eq(c["code"], "suit_range", "a walk of 700 m outside is still refused")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 6: reactor and disasters
## The fission reactor: runs cool with coolant; without coolant it heats on a forecast the
## player can see; SCRAM, a coolant dump and an evacuation work; a breach destroys what is in
## the blast, kills the people in it and leaves a radiation zone that doses the people round it.
func v4_reactor_meltdown(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var rp: Vector2 = _spot(sim, "fission_reactor", lander["pos"], 220.0, 320.0)
	if not t.check(rp.x > 0.0, "a place for the reactor"):
		g.dispose()
		t.done()
		return
	var r: Dictionary = g.cmd("place_finished", {"def": "fission_reactor", "x": rp.x, "y": rp.y})
	var rid: int = int(r["id"])
	var rb: Dictionary = sim.state["buildings"][rid]
	var sp: Vector2 = _spot(sim, "solar_array", rp, 24.0, 45.0)
	var solar: int = int(g.cmd("place_finished", {"def": "solar_array", "x": sp.x, "y": sp.y})["id"])
	t.check(int(rb["inv_in"]) != -1, "the reactor has a fuel and coolant buffer")
	sim.inv.add_new_forced(int(rb["inv_in"]), "fuel_rod", 2, "test")                    # test set-up
	sim.inv.add_new_forced(int(rb["inv_in"]), "coolant", 8, "test")
	g.run(2000)
	var row: Dictionary = sim.reactors.list()[0]
	t.check(bool(row["running"]), "it runs on a fuel rod")
	t.eq(row["stage"], "ok", "with coolant it stays cool")
	t.near(float(row["heat"]), 40.0, 0.001, "at its running heat")
	t.eq(float(row["next_phase_s"]), -1.0, "no stage coming")
	# Coolant gone: a forecast, then the warning on time.
	sim.inv.consume(int(rb["inv_in"]), "coolant", sim.inv.count(int(rb["inv_in"]), "coolant"), "test")   # test set-up
	sim.state["policies"]["priority"]["industry"] = 0                                    # test set-up: nobody brings more
	var f: Dictionary = sim.reactors.forecast(rb)
	t.near(float(f["rate"]), 0.04, 0.0001, "it heats 0.04 per second")
	t.near(float(f["next_s"]), 500.0, 0.01, "warning in 500 s")
	g.run(5100)
	t.eq(rb["rx"]["stage"], "warning", "the warning came")
	t.eq(H.issues_with_code(sim, "reactor_warning").size(), 1, "an alert")
	# SCRAM: fission stops after 12 s, the core still warms slowly without coolant.
	t.check(bool(g.cmd("reactor_scram", {"id": rid})["ok"]), "SCRAM")
	g.run(130)
	t.check(not sim.reactors.running(rb), "fission stopped")
	t.check(sim.reactors.heat_rate(rb) >= 0.01 and sim.reactors.heat_rate(rb) < 0.02, "decay heat (and wear) still warm it a little (%.4f)" % sim.reactors.heat_rate(rb))
	# A coolant dump brings it back.
	t.eq(g.cmd("reactor_cool", {"id": rid})["code"], "no_coolant", "no coolant, no dump")
	sim.inv.add_new_forced(int(rb["inv_in"]), "coolant", 4, "test")                    # test set-up
	t.check(bool(g.cmd("reactor_cool", {"id": rid})["ok"]), "coolant dumped")
	g.run(10)
	t.eq(rb["rx"]["stage"], "ok", "safe again")
	# Evacuation: colonists in the zone go to rooms with air outside it.
	var ids: Array = []
	for aid in sim.state["agents"]:
		ids.append(int(aid))
	var near: Dictionary = sim.state["agents"][ids[0]]
	var mid: Dictionary = sim.state["agents"][ids[1]]
	g.cmd("reactor_stage", {"id": rid, "stage": "critical"})
	g.run(10)
	H.put_outside(sim, near, sim.nav.nearest_walkable(rp + Vector2(0, -30).rotated(0.3), 8), sim.agents.suit_cap())   # test set-up
	H.put_outside(sim, mid, sim.nav.nearest_walkable(rp + (lander["pos"] - rp).normalized() * 100.0, 8), sim.agents.suit_cap())
	var ev: Dictionary = g.cmd("reactor_evacuate", {"id": rid})
	t.check(bool(ev["ok"]) and int(ev["moved"]) >= 2, "two colonists evacuate (%s)" % str(ev))
	t.eq(int(mid.get("order", {}).get("evac", -1)), rid, "with an evacuation order")
	g.cmd("reactor_stage", {"id": rid, "stage": "ok"})
	g.run(20)
	t.check(not mid.has("order"), "safe again: the evacuation order ends")
	# Breach.
	H.put_outside(sim, near, sim.nav.nearest_walkable(rp + Vector2(0, -30).rotated(0.3), 8), sim.agents.suit_cap())   # test set-up
	H.put_outside(sim, mid, sim.nav.nearest_walkable(rp + (lander["pos"] - rp).normalized() * 100.0, 8), sim.agents.suit_cap())
	near["order"] = {"kind": "stay", "p": near["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}   # test set-up: they stay put
	mid["order"] = {"kind": "stay", "p": mid["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}
	g.cmd("reactor_stage", {"id": rid, "stage": "breach"})
	g.run(20)
	t.check(not sim.state["buildings"].has(rid), "the reactor is gone")
	t.check(not sim.state["buildings"].has(solar), "the solar array 45 m away is destroyed")
	t.eq(near["state"], "dead", "a colonist 30 m away died")
	t.eq(mid["state"], "alive", "a colonist 100 m away lives")
	t.eq(H.log_entries(sim, "reactor_breach").size(), 1, "the log tells it")
	var rb_log: Dictionary = H.log_entries(sim, "reactor_breach")[0]
	t.eq(rb_log["ents"], [rid], "the log names the reactor")
	t.check(Vector2(rb_log["pos"][0], rb_log["pos"][1]).distance_to(rp) < 0.01 and rb_log["def"] == "fission_reactor", "and its place")
	t.check(sim.reactors.rad_at(rp) > 50.0, "the ground is radioactive (%.1f mSv/h)" % sim.reactors.rad_at(rp))
	var d0: float = float(mid.get("dose", 0.0))
	g.run(600)
	t.check(float(mid.get("dose", 0.0)) > d0 + 1.0, "the colonist in the zone takes a dose (%.1f mSv)" % float(mid.get("dose", 0.0)))
	t.eq(sim.orders.check(mid, {"kind": "go", "x": rp.x, "y": rp.y})["code"], "radiation", "an order into the zone is refused")
	t.eq(sim.inv.audit(), {}, "ledger (destroyed goods are booked)")
	g.dispose()
	t.done()

## The other risky plants: a crystal refinery without power while a batch runs explodes after a
## warning; a damaged chemical plant leaks and the toxic ground hurts people outside in it.
## Radiation dose: inside a room a colonist takes a tenth of the dose outside.
func v4_other_disasters(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var cp: Vector2 = _spot(sim, "crystal_refinery", lander["pos"], 150.0, 260.0)
	var cr: Dictionary = sim.state["buildings"][int(g.cmd("place_finished", {"def": "crystal_refinery", "x": cp.x, "y": cp.y})["id"])]
	cr["batch"] = {"recipe": "crystal_lattice", "progress": 0.0, "work": 90.0, "hold": -1, "outputs": {"crystal_lattice": 1}}   # test set-up
	g.run(150)
	t.eq(H.issues_with_code(sim, "unstable_power").size(), 1, "the warning with a countdown")
	g.run(400)
	t.check(not sim.state["buildings"].has(int(cr["id"])), "without power it exploded")
	t.eq(H.log_entries(sim, "unstable_blast").size(), 1, "logged")
	var tp: Vector2 = _spot(sim, "chemical_plant", lander["pos"], 150.0, 260.0)
	var ch: Dictionary = sim.state["buildings"][int(g.cmd("place_finished", {"def": "chemical_plant", "x": tp.x, "y": tp.y})["id"])]
	ch["health"] = 40.0                                                                  # test set-up: damaged
	g.run(20)
	t.eq(sim.reactors.zones().size(), 1, "a toxic zone")
	var ub: Array = H.log_entries(sim, "unstable_blast")
	t.check(not ub.is_empty() and (ub[0]["ents"] as Array).size() == 1 and ub[0].has("pos"), "the blast log names the structure and the place")
	var a: Dictionary = {}
	for aid in sim.state["agents"]:
		if a.is_empty():
			a = sim.state["agents"][aid]
	H.put_outside(sim, a, sim.nav.nearest_walkable(tp + Vector2(14, 0), 6), sim.agents.suit_cap())   # test set-up
	a["order"] = {"kind": "stay", "p": a["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}
	var h0: float = float(a["health"])
	g.run(300)
	t.check(float(a["health"]) < h0 - 1.0, "the toxic ground hurts (%.1f -> %.1f)" % [h0, float(a["health"])])
	# Dose shielding: the same place, inside and outside.
	var b: Dictionary = {}
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid] != a and b.is_empty():
			b = sim.state["agents"][aid]
	sim.reactors._zones_w().append({"kind": "rad", "x": lander["pos"].x, "y": lander["pos"].y, "r": 400.0, "peak": 20.0, "t0": int(sim.state["tick"]), "half_s": 1e9})   # test set-up
	H.put_inside(sim, b, int(lander["id"]))
	b["dose"] = 0.0
	var p_in: Vector2 = b["pos"]
	var rate: float = sim.reactors.rad_at(p_in)
	g.run(10)
	var per_s: float = rate * 24.0 / 600.0
	t.near(float(b["dose"]), per_s * 0.1, per_s * 0.02, "inside the lander: a tenth of the dose")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 7: fog, POIs, finds, satellite
static func _first_poi(sim, kind: String) -> Dictionary:
	for p in sim.explore.pois():
		if p["kind"] == kind:
			return p
	return {}

## Fog of war: the landing area is known, the rest is not; walking reveals ground and surveys
## deposits; POIs of every kind are placed and found by revealing; old maps have no fog; a
## save with fog continues exactly; a v4 save from before the fog gets one.
func v4_fog_and_pois(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	var c: Vector2 = sim.world.center
	t.check(sim.explore.active(), "a v4 game has fog")
	t.check(sim.explore.explored(c), "the landing is explored")
	t.check(not sim.explore.explored(c + Vector2(600, 0)), "600 m out is not")
	var share: float = sim.explore.explored_share()
	t.check(share > 0.03 and share < 0.06, "about 4 % of the map is known (%.3f)" % share)
	var kinds := {}
	for p in sim.explore.pois():
		kinds[p["kind"]] = int(kinds.get(p["kind"], 0)) + 1
	t.eq(kinds.size(), 6, "every kind of POI is placed: %s" % str(kinds))
	t.check(sim.explore.pois().size() >= 18, "at least 18 POIs (%d)" % sim.explore.pois().size())
	var unfound := 0
	for p in sim.explore.pois():
		if not bool(p["found"]):
			unfound += 1
	t.eq(unfound, sim.explore.pois().size(), "no POI is known at the start")
	# A walk reveals ground and surveys a deposit there.
	var dep: Dictionary = {}
	for d in sim.state["deposits"]:
		if not bool(d["surveyed"]) and Vector2(d["x"], d["y"]).distance_to(c) < 700.0:
			dep = d
			break
	if t.check(not dep.is_empty(), "an unsurveyed deposit"):
		var a: Dictionary = {}
		for aid in sim.state["agents"]:
			if a.is_empty():
				a = sim.state["agents"][aid]
		var dp := Vector2(dep["x"], dep["y"])
		H.put_outside(sim, a, sim.nav.nearest_walkable(dp + Vector2(12, 0), 8), sim.agents.suit_cap())   # test set-up
		a["order"] = {"kind": "stay", "p": a["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}
		var rev0: int = int(sim.explore.fog()["rev"])
		g.run(20)
		t.check(bool(dep["surveyed"]), "a colonist there surveys it")
		t.check(int(sim.explore.fog()["rev"]) > rev0, "the fog revision counter moved")
		t.check(H.log_entries(sim, "deposit_found").size() >= 1, "logged")
		g.cmd("order_clear", {"agents": [int(a["id"])]})
	var w: Dictionary = _first_poi(sim, "wreck")
	t.eq(g.cmd("reveal", {"x": w["x"], "y": w["y"], "r": 60.0})["ok"], true, "debug reveal")
	t.check(bool(w["found"]), "revealing a POI finds it")
	# A save with fog continues exactly.
	var cl: Dictionary = H.clone_by_save(sim)
	var sim2 = cl["sim"]
	for i in 300:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "a game with fog continues exactly after a load")
	t.eq((sim2.explore.fog()["bits"] as PackedByteArray), (sim.explore.fog()["bits"] as PackedByteArray), "the fog is saved")
	sim2.dispose()
	# A v4 save from before the fog.
	var old4: Dictionary = sim.state.duplicate(true)
	old4.erase("fog")
	old4.erase("pois")
	old4.erase("sats")
	var s3 = H.Sim.new()
	s3.load_state(Persistence.decode(Persistence.encode(old4))["state"])
	t.check(s3.explore.active() and s3.explore.explored(c), "an older v4 save gets fog with its base known")
	t.eq(s3.explore.pois().size(), sim.explore.pois().size(), "and the same POIs")
	s3.dispose()
	var v3 = H.Sim.new()
	v3.new_game(1001)
	t.check(not v3.explore.active() and v3.explore.explored(v3.world.center + Vector2(300, 300)), "old maps: no fog")
	v3.dispose()
	g.dispose()
	t.done()

## Visiting POIs: finds go into the vehicle there; a cave needs somebody on foot; an anomaly
## needs a scientist and gives research points; a rich deposit adds a deposit.
func v4_poi_visits(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	var ags: Array = []
	for aid in sim.state["agents"]:
		ags.append(sim.state["agents"][aid])
	var sci: Dictionary = {}
	var other: Dictionary = {}
	for a in ags:
		if a["role"] == "scientist" and sci.is_empty():
			sci = a
		elif a["role"] != "scientist" and other.is_empty():
			other = a
	# Wreck by rover: the finds go into its cargo.
	var w: Dictionary = _first_poi(sim, "wreck")
	var wp := Vector2(w["x"], w["y"])
	g.cmd("reveal", {"x": wp.x, "y": wp.y, "r": 60.0})
	var rv: Dictionary = sim.vehicles.spawn("medium_rover", sim.nav.nearest_walkable(wp + Vector2(8, 0), 8), -1)   # test set-up
	H.put_outside(sim, other, rv["pos"] + Vector2(2, 0), sim.agents.suit_cap())
	sim.vehicles.board(other, int(rv["id"]))
	g.run(20)
	t.check(bool(w["visited"]), "the wreck is visited")
	t.eq(sim.inv.count(int(rv["cargo"]), "derelict_parts"), 3, "3 derelict parts in the rover")
	t.eq(sim.inv.count(int(rv["cargo"]), "data_core"), 1, "and a data core")
	sim.vehicles.alight_all(rv)
	# Cave: not from inside a vehicle.
	var cv: Dictionary = _first_poi(sim, "cave")
	if t.check(not cv.is_empty(), "a cave"):
		var cp := Vector2(cv["x"], cv["y"])
		g.cmd("reveal", {"x": cp.x, "y": cp.y, "r": 60.0})
		var q = sim.nav.nearest_walkable(cp, 10)
		rv["pos"] = q if q != null else cp                                               # test set-up: the rover drove there
		H.put_outside(sim, other, rv["pos"] + Vector2(2, 0), sim.agents.suit_cap())
		sim.vehicles.board(other, int(rv["id"]))
		g.run(20)
		t.check(not bool(cv["visited"]), "a cave is not visited from a rover")
		sim.vehicles.alight_all(rv)
		other["order"] = {"kind": "stay", "p": other["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}   # test set-up
		g.run(20)
		t.check(bool(cv["visited"]), "somebody on foot visits it")
		t.check(H.world_count(sim, "exotic") >= 2, "exotic crystal on the ground")
		other.erase("order")
	# Anomaly: a scientist is needed.
	var an: Dictionary = _first_poi(sim, "anomaly")
	if t.check(not an.is_empty() and not sci.is_empty(), "an anomaly and a scientist"):
		var ap := Vector2(an["x"], an["y"])
		g.cmd("reveal", {"x": ap.x, "y": ap.y, "r": 60.0})
		var q2 = sim.nav.nearest_walkable(ap, 10)
		H.put_outside(sim, other, q2 if q2 != null else ap, sim.agents.suit_cap())      # test set-up
		other["order"] = {"kind": "stay", "p": other["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}
		g.run(20)
		t.check(not bool(an["visited"]), "not without a scientist")
		var rp0: float = float(sim.state["research"]["bank"]) + float(sim.state["research"]["rp_total"])
		H.put_outside(sim, sci, other["pos"] + Vector2(1, 0), sim.agents.suit_cap())
		sci["order"] = {"kind": "stay", "p": sci["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}
		g.run(20)
		t.check(bool(an["visited"]), "a scientist visits it")
		t.check(float(sim.state["research"]["bank"]) + float(sim.state["research"]["rp_total"]) >= rp0 + 199.0, "200 research points")
		other.erase("order")
		sci.erase("order")
	# Rich deposit.
	var rd: Dictionary = _first_poi(sim, "rich_deposit")
	var n0: int = sim.state["deposits"].size()
	var rp2 := Vector2(rd["x"], rd["y"])
	g.cmd("reveal", {"x": rp2.x, "y": rp2.y, "r": 60.0})
	H.put_outside(sim, other, sim.nav.nearest_walkable(rp2 + Vector2(5, 0), 8), sim.agents.suit_cap())   # test set-up
	other["order"] = {"kind": "stay", "p": other["pos"], "b": -1, "stay": true, "confirm": true, "t": 0}
	g.run(20)
	t.eq(sim.state["deposits"].size(), n0 + 1, "a rich deposit is added")
	t.check(bool(sim.state["deposits"].back().get("rich", false)) and int(sim.state["deposits"].back()["ore"]) == 1500, "rich: 1500 units")
	# A survey order to a found POI.
	var mf: Dictionary = _first_poi(sim, "meteorite_field")
	g.cmd("reveal", {"x": mf["x"], "y": mf["y"], "r": 60.0})
	var sc: String = sim.orders.check(other, {"kind": "survey", "poi": int(mf["id"])})["code"]
	t.check(sc in ["ok", "suit_range", "radiation", "no_path"], "a survey order to a POI is understood (%s)" % sc)
	t.eq(sim.orders.check(other, {"kind": "survey", "poi": int(w["id"])})["code"], "no_site", "a visited POI: no survey")
	other.erase("order")
	var mp := Vector2(mf["x"], mf["y"])
	H.put_outside(sim, other, sim.nav.nearest_walkable(mp + Vector2(40, 0), 10), sim.agents.suit_cap())   # test set-up: 40 m away
	t.eq(sim.orders.check(other, {"kind": "survey", "poi": int(mf["id"])})["code"], "suit_range", "far from air: refused for suit air")
	var so: Dictionary = g.cmd("order", {"agents": [int(other["id"])], "kind": "survey", "poi": int(mf["id"]), "confirm": true})
	t.check(bool(so["ok"]), "confirmed survey order to the meteorite field: %s" % so["code"])
	t.check(g.run_until(func(): return bool(mf["visited"]), 600), "the colonist walks there and it is visited")
	t.check(g.run_until(func(): return not other.has("order"), 200), "the order ends")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

## A survey satellite: built at a launch pad, it maps a band every minute while a comms tower
## has power; the bands it maps find the POIs there.
func v4_satellite(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var lp: Vector2 = _spot(sim, "launch_pad", lander["pos"], 30.0, 60.0)
	var pad: int = int(g.cmd("place_finished", {"def": "launch_pad", "x": lp.x, "y": lp.y})["id"])
	var store: int = int(lander["inv_out"])
	for r in {"metal": 20, "electronics": 16, "composite": 8, "rocket_fuel": 24, "battery_cell": 4}.keys():
		sim.inv.add_new_forced(store, r, {"metal": 20, "electronics": 16, "composite": 8, "rocket_fuel": 24, "battery_cell": 4}[r], "test")   # test set-up
	t.eq(g.cmd("build_vehicle", {"depot": pad, "kind": "small_rover"})["code"], "invalid", "a pad builds no rovers")
	t.check(bool(g.cmd("build_satellite", {"pad": pad})["ok"]), "satellite ordered")
	t.check(g.run_until(func(): return sim.explore.sats().size() == 1, 12000), "built and launched")
	var share0: float = sim.explore.explored_share()
	g.run(700)
	t.eq(sim.explore.explored_share(), share0, "without an uplink it maps nothing")
	var tp: Vector2 = _spot(sim, "comms_tower", lp, 12.0, 40.0)
	var tower: int = int(g.cmd("place_finished", {"def": "comms_tower", "x": tp.x, "y": tp.y})["id"])
	var bp: Vector2 = _spot(sim, "battery", tp, 6.0, 30.0)
	var bat: int = int(g.cmd("place_finished", {"def": "battery", "x": bp.x, "y": bp.y})["id"])
	var errs: Array = []
	H.link_now(sim, "cable", tower, bat, errs)
	t.eq(errs, [], "cable")
	H.fill_utilities(sim, 1.0, 0.8, true)
	g.run(20)
	t.check(sim.explore.uplink(), "the powered tower is an uplink")
	g.run(1250)
	var s: Dictionary = sim.explore.sats()[0]
	t.check(int(s["bands_done"]) >= 2, "bands mapped (%d)" % int(s["bands_done"]))
	t.check(sim.explore.explored_share() > share0 + 0.1, "the map is more explored (%.2f -> %.2f)" % [share0, sim.explore.explored_share()])
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- milestone 8: perf, saves, showcase
## V4 budget: a tick takes at most 2.5 ms with 100 colonists and 6 vehicles on the move on the
## 2,560 m map (fog, dose, zones, POIs all running). The reference base of day 12 is too small
## for 100 people, so the air is topped up before each window (test set-up) and the settlers
## come fast; the colony must still have 95 people while it is measured.
func long_v4_perf(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	g.ref = Reference.new(sim, "all")
	g.run_to_tick(12 * 6000)
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var guard := 0
	while sim.alive_count() < 100 and guard < 60:
		guard += 1
		g.cmd("admit_settlers", {"count": mini(6, 100 - sim.alive_count())})
		H.fill_utilities(sim, 1.0, 0.8, true)                                            # test set-up: air for 100
		g.run(450)
	var crew: Array = []
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["kind"] != "visitor" and crew.size() < 6:
			crew.append(a)
	var c: Vector2 = sim.world.center
	var legs := {}
	for k in 6:
		# Pressurised vehicles (an open rover's crew get out whenever it stops near air).
		var kind: String = "hopper" if k == 5 else "medium_rover"
		var p = sim.nav.nearest_walkable(c + Vector2.RIGHT.rotated(k * TAU / 6.0) * 160.0, 10)
		var v: Dictionary = sim.vehicles.get_v(int(g.cmd("spawn_vehicle", {"kind": kind, "x": p.x, "y": p.y})["id"]))
		v["charge"] = 1e6                                                                  # test set-up: no stop for charge
		v["fuel"] = 1e6
		H.put_outside(sim, crew[k], v["pos"] + Vector2(2, 0), sim.agents.suit_cap())
		sim.vehicles.board(crew[k], int(v["id"]))
		var far: Vector2 = _drive_target(sim, v["pos"], 450.0) if kind != "hopper" else v["pos"] + (c - v["pos"]).normalized() * 500.0
		if far.x < 0.0:
			far = _drive_target(sim, v["pos"], 250.0)
		legs[int(v["id"])] = [far, v["pos"]]
	var drive := func() -> int:
		var n := 0
		for vid in legs:
			var v2: Dictionary = sim.vehicles.get_v(vid)
			if v2["state"] == "parked":
				var l: Array = legs[vid]
				l.reverse()
				sim.vehicles.drive_to(v2, l[0])
			if v2["state"] == "driving":
				n += 1
		return n
	var wins: Array = []
	var raw_w: Array = []
	var pc = Pacer.new(true)
	pc.start()
	var driving := 0
	var low := 999
	for w in 3:
		H.fill_utilities(sim, 1.0, 0.8, true)                                            # test set-up: air for 100
		for s in 10:
			var t0: int = Time.get_ticks_usec()
			g.run(100)
			driving += drive.call()
			var el: float = float(Time.get_ticks_usec() - t0) / 1000.0
			if s == 5:
				H.fill_utilities(sim, 1.0, 0.8, true)
			pc.block(el, 100)
		wins.append(pc.per_tick(w * 10, w * 10 + 10))
		raw_w.append(pc.raw_per_tick(w * 10, w * 10 + 10))
		low = mini(low, sim.alive_count())
	var factor: float = pc.mean_factor()
	var cal: String = pc.reading_text()
	var causes := {}
	for aid in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][aid]
		if ag["state"] == "dead":
			causes[ag["cause"]] = int(causes.get(ag["cause"], 0)) + 1
	var vst: Array = []
	for vid in legs:
		vst.append("%s:%s" % [sim.vehicles.get_v(vid)["kind"], sim.vehicles.get_v(vid)["block"]])
	t.note("deaths %s, vehicles %s" % [str(causes), str(vst)])
	var vlog: Array = []
	for e in sim.state["log"]:
		if ["death", "vehicle_broken", "vehicle_stopped", "vehicle_needs", "hazard_impact"].has(String(e["code"])):
			vlog.append("%d %s: %s" % [int(e["tick"]), String(e["code"]), String(e["text"]).substr(0, 80)])
	t.note("log: %s" % str(vlog.slice(maxi(0, vlog.size() - 8))))
	for aid in sim.state["agents"]:
		var dg: Dictionary = sim.state["agents"][aid]
		if dg["state"] == "dead":
			t.note("dead: %s %s cause %s where %s bld %s fatigue %.0f bed %s plan %s kind %s" % [dg["name"], dg["role"], dg["cause"], dg["where"], str(dg["bld"]), float(dg["fatigue"]), str(dg["bed"]), str(dg["plan_kind"]), str(dg.get("kind", ""))])
	var un: Dictionary = sim.unrest.info(-1)
	t.note("unrest %.1f %s (target %.1f)" % [float(un["value"]), un["stage"], float(un["target"])])
	var sorted_w: Array = wins.duplicate()
	sorted_w.sort()
	var ms: float = float(sorted_w[1])
	t.check(low >= 95, "95 or more colonists while it is measured (%d)" % low)
	t.check(float(driving) / 30.0 >= 5.0, "5 or more vehicles driving on average (%.1f)" % (float(driving) / 30.0))
	t.check(ms <= 2.5, "a tick takes at most 2.5 ms (scaled median %.3f ms of %s; raw %s, calibration %s, mean factor %.3f)" % [ms, str(wins), str(raw_w), cal, factor])
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("%.3f ms per tick scaled (windows %.3f / %.3f / %.3f; raw %.3f / %.3f / %.3f; calibration %s, mean factor %.3f), %d colonists, %d structures, 6 vehicles, fog %.0f %% (%s)" % [ms, wins[0], wins[1], wins[2], raw_w[0], raw_w[1], raw_w[2], cal, factor,
		sim.alive_count(), sim.state["buildings"].size(), sim.explore.explored_share() * 100.0, OS.get_processor_name()])
	g.dispose()
	t.done()

## showcase_v4.fhsave (tests/make_showcase_v4.gd): schema 5 on the 2,560 m map with two bases,
## a rover route, a reactor, an expedition rover at a crater rim and a satellite part way; it
## loads, runs a minute cleanly and continues exactly after a save.
func v4_showcase(t) -> void:
	var path := "res://content/saves/showcase_v4.fhsave"
	if not t.check(FileAccess.file_exists(path), "showcase_v4 exists"):
		t.done()
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var raw := StreamPeerBuffer.new()
	raw.data_array = bytes
	raw.seek(8)
	t.eq(raw.get_u32(), 5, "schema 5")
	var dec: Dictionary = Persistence.decode(bytes)
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	t.eq(int(sim.world.size), 2560, "the 2,560 m map")
	t.eq(int(sim.state.get("rules", 3)), 4, "V4 rules")
	t.eq(sim.bases.count(), 2, "two bases")
	var routed := 0
	var at_rim := 0
	for row in sim.vehicles.list():
		if not (row["route"] as Dictionary).is_empty():
			routed += 1
		if sim.world.terrain_at(row["pos"]) == "crater rim" or (row["crew"] as Array).size() == 2:
			at_rim += 1
	t.eq(routed, 1, "a rover on a route")
	for row in sim.vehicles.list():
		if row["state"] != "driving" and int(row["bay"]) == -1:
			t.check(sim.vehicles.slope_deg(row["pos"]) <= 10.0, "%s is parked on ground of 10 deg or less (%.1f)" % [row["name"], sim.vehicles.slope_deg(row["pos"])])
	t.check(at_rim >= 1, "an expedition rover with its crew")
	t.eq(sim.reactors.list().size(), 1, "a reactor")
	var sats: Array = sim.explore.sats()
	t.check(sats.size() == 1 and int(sats[0]["bands_done"]) > 0 and int(sats[0]["bands_done"]) < 16, "a satellite part way")
	var share: float = sim.explore.explored_share()
	t.check(share > 0.2 and share < 0.8, "part of the map explored (%.2f)" % share)
	t.check(not bool(sim.state["options"].get("debug", false)), "debug is off in the save")
	# UI integration: the uplink has power, the satellite maps new bands, no false critical alert.
	sim.run_seconds(2.0)
	var crit: Array = []
	for k in sim.state["issues"]:
		if int(sim.state["issues"][k]["severity"]) >= 3:
			crit.append(String(sim.state["issues"][k]["text"]))
	t.eq(crit, [], "no critical alert at load")
	t.check(sim.explore.uplink(), "the comms tower has power: an uplink")
	for id in sim.state["buildings"]:
		var lb: Dictionary = sim.state["buildings"][id]
		if lb["def"] == "launch_pad" or lb["def"] == "comms_tower":
			t.check(bool(lb["powered"]), "%s has power" % lb["name"])
	var bands0: int = int(sim.explore.sats()[0]["bands_done"])
	var alive0: int = sim.alive_count()
	sim.run_seconds(130.0)
	t.check(int(sim.explore.sats()[0]["bands_done"]) >= bands0 + 2, "the satellite maps new bands (%d -> %d)" % [bands0, int(sim.explore.sats()[0]["bands_done"])])
	for row in sim.vehicles.list():
		if not (row["route"] as Dictionary).is_empty():
			t.check(String(row["block"]) != "no_route" and (int(row["route"].get("trips", 0)) >= 1 or row["state"] == "driving"), "the route rover drives its route (no closed-in bay): %s" % str(row["route"]))
	t.eq(sim.inv.audit(), {}, "ledger after a minute")
	t.eq(sim.alive_count(), alive0, "nobody died in the minute")
	var cl: Dictionary = H.clone_by_save(sim)
	var sim2 = cl["sim"]
	for i in 300:
		sim.step()
		sim2.step()
	t.eq(H.digest(sim2), H.digest(sim), "it continues exactly after a save")
	t.note("%d colonists, %d structures, %d vehicles, fog %.0f %%, %d bytes" % [alive0, sim.state["buildings"].size(), sim.vehicles.count(), share * 100.0, bytes.size()])
	sim2.dispose()
	sim.dispose()
	t.done()

## Frame budget (RENDER measured frame stalls): 900 s of showcase_v4, no single tick over
## 30 ms (the target is 20 ms; 30 leaves room for other programs on this PC). The long ticks
## were colonists whose choice of work searched a whole 320 m window for a walk into a closed
## pocket (25 ms per search), and window builds inside a tick.
func long_v4_tick_max(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"], {"debug": true})
	var worst := 0.0
	var worst_tick := -1
	var total := 0.0
	var bands0: int = int(sim.explore.sats()[0]["bands_done"])
	var reveal_ms := 0.0
	for i in 9000:
		# UI measured a long frame after a debug reveal that found a POI: one big reveal here.
		if i == 4500:
			for poi in sim.explore.pois():
				if not bool(poi["found"]):
					sim.submit("reveal", {"x": poi["x"], "y": poi["y"], "r": 1000.0})
					break
		var t0: int = Time.get_ticks_usec()
		sim.step()
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		if i == 4500:
			reveal_ms = ms
		if ms > worst:
			worst = ms
			worst_tick = int(sim.state["tick"])
	t.check(worst <= 30.0, "no tick over 30 ms in 900 s (worst %.1f ms at tick %d)" % [worst, worst_tick])
	t.check(reveal_ms <= 30.0, "the tick of a 1,000 m debug reveal that finds a POI: %.1f ms" % reveal_ms)
	t.check(int(sim.explore.sats()[0]["bands_done"]) > bands0, "satellite bands were mapped during the run (%d -> %d)" % [bands0, int(sim.explore.sats()[0]["bands_done"])])
	t.eq(sim.inv.audit(), {}, "ledger")
	t.note("worst tick %.1f ms at tick %d, reveal tick %.1f ms, mean %.3f ms (%s)" % [worst, worst_tick, reveal_ms, total / 9000.0, OS.get_processor_name()])
	sim.dispose()
	t.done()

## Debug reactor_stage sets exactly the stage it names, at once (critic round 22), on the
## showcase: warning, critical, ok, and from normal straight to breach in one command.
func v4_reactor_stage_debug(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.load_state(dec["state"], {"debug": true})
	var row: Dictionary = sim.reactors.list()[0]
	var rid: int = int(row["id"])
	t.eq(row["stage"], "ok", "the showcase reactor starts normal")
	for st in ["warning", "critical", "ok"]:
		t.check(bool(g.cmd("reactor_stage", {"id": rid, "stage": st})["ok"]), "reactor_stage %s" % st)
		var b: Dictionary = sim.state["buildings"][rid]
		t.eq(sim.reactors.list()[0]["stage"], st, "%s at once (the row)" % st)
		t.eq(b["rx"]["stage"], st, "%s at once (the record)" % st)
		g.run(30)
		t.eq(sim.reactors.list()[0]["stage"], st, "%s still after 3 s" % st)
	t.eq(H.log_entries(sim, "reactor_warning").size(), 1, "the warning is logged")
	t.eq(H.log_entries(sim, "reactor_critical").size(), 1, "the critical stage is logged")
	t.check(bool(g.cmd("reactor_stage", {"id": rid, "stage": "breach"})["ok"]), "normal -> breach in one command")
	t.check(not sim.state["buildings"].has(rid), "the reactor exploded in the same tick")
	t.eq(sim.reactors.list().size(), 0, "no reactor row after the breach")
	t.eq(H.log_entries(sim, "reactor_breach").size(), 1, "the breach is logged")
	t.eq(H.log_entries(sim, "reactor_warning").size(), 1, "no warning after the breach")
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

## Rovers never drive through a built corridor tube (Paul: bodies through structures); a
## placement that would close a depot's bays in is refused; a drive with no way stops at once
## with its reason (no long search); a depot already closed in (an old save) says "no route" and
## the game goes on.
func v4_rover_tubes_and_blocks(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"debug": true})
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var dp: Vector2 = _spot(sim, "rover_depot", lander["pos"], 60.0, 120.0, 2)
	var did: int = int(g.cmd("place_finished", {"def": "rover_depot", "x": dp.x, "y": dp.y, "size": 2})["id"])
	var d: Dictionary = sim.state["buildings"][did]
	var v: Dictionary = sim.vehicles.get_v(int(g.cmd("spawn_vehicle", {"kind": "medium_rover", "depot": did})["id"]))
	var drv: Dictionary = {}
	for aid in sim.state["agents"]:
		if drv.is_empty():
			drv = sim.state["agents"][aid]
	H.put_outside(sim, drv, sim.vehicles.board_point(v), sim.agents.suit_cap())          # test set-up
	t.check(sim.vehicles.board(drv, int(v["id"])), "the driver gets in")
	# A corridor across the straight way out: two habitats either side of the line, joined.
	var ex: Vector2 = sim.vehicles.bays(d)[2]["exit"]
	var goal: Vector2 = _drive_target(sim, ex + Vector2(160, 0), 1.0)
	if goal.x < 0.0:
		goal = _drive_target(sim, ex, 160.0)
	var mid: Vector2 = ex.lerp(goal, 0.5)
	var side: Vector2 = (goal - ex).normalized().orthogonal()
	var errs: Array = []
	var h1: Dictionary = H.spawn(sim, "habitat", mid + side * 17.0 - sim.world.center, 0.0, errs)
	var h2: Dictionary = H.spawn(sim, "habitat", mid - side * 17.0 - sim.world.center, 0.0, errs)
	var tube: Dictionary = {}
	if errs.is_empty():
		tube = H.link_now(sim, "corridor", int(h1["id"]), int(h2["id"]), errs)
	if not t.check(errs.is_empty() and not tube.is_empty(), "a corridor across the way (%s)" % str(errs)):
		g.dispose()
		t.done()
		return
	g.run(2)
	t.check(bool(g.cmd("vehicle_drive", {"id": int(v["id"]), "x": goal.x, "y": goal.y})["ok"]), "drive past it")
	var worst := 1e9
	var steps := 0
	while v["state"] == "driving" and steps < 4000:
		g.step()
		steps += 1
		worst = minf(worst, Geometry2D.get_closest_point_to_segment(v["pos"], tube["p0"], tube["p1"]).distance_to(v["pos"]))
	t.eq(v["state"], "parked", "it arrived")
	t.check(worst > sim.corridor_r() + 1.0, "it never came into the tube (closest %.1f m from its axis)" % worst)
	# No way: a mountain inside; the drive is refused at once with the reason, the rover stays.
	var peak := Vector2(-1, -1)
	for mt in sim.world.mountains:
		for q in mt["pts"]:
			if peak.x < 0.0 and not sim.nav.rover_ok(q) and sim.nav._rover_end(q) == null:
				peak = q
	if t.check(peak.x > 0.0, "a closed mountain point"):
		var p0: Vector2 = v["pos"]
		var t0: int = Time.get_ticks_usec()
		var r: Dictionary = g.cmd("vehicle_drive", {"id": int(v["id"]), "x": peak.x, "y": peak.y})
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		t.eq(r["code"], "no_route", "no route")
		t.eq(sim.vehicles.list()[0]["block_text"], "No route: the way is blocked", "with the reason")
		t.check((v["pos"] as Vector2) == p0 and v["state"] == "parked", "the rover does not move")
		t.check(ms < 20.0, "the refusal is quick (%.1f ms)" % ms)
	# Placement: a corridor right across all bay doors is refused.
	var hp1: Vector2 = dp + Vector2(float(d["radius"]) + 3.0, 18.0).rotated(float(d["rot"]))
	var hp2: Vector2 = dp + Vector2(float(d["radius"]) + 3.0, -18.0).rotated(float(d["rot"]))
	var e2: Array = []
	var a1: Dictionary = H.spawn(sim, "junction", hp1 - sim.world.center, 0.0, e2)
	var a2: Dictionary = H.spawn(sim, "junction", hp2 - sim.world.center, 0.0, e2)
	if t.check(e2.is_empty(), "two junctions beside the depot doors (%s)" % str(e2)):
		t.eq(sim.place.check_link("corridor", int(a1["id"]), int(a2["id"]))["code"], "depot_blocked", "a corridor across the bay doors is refused")
		t.eq(sim.place.REASONS["depot_blocked"], "This would block the rover depot.", "with its text")
	# An old save with a closed-in depot: the corridor was there first, the depot was added
	# without the check (test set-up); the rover says "no route" and the game goes on.
	var dp2: Vector2 = _spot(sim, "rover_depot", lander["pos"], 150.0, 260.0, 1)
	var j1: Dictionary = H.spawn(sim, "junction", dp2 + Vector2(12.0, 17.0) - sim.world.center, 0.0, e2)
	var j2: Dictionary = H.spawn(sim, "junction", dp2 + Vector2(12.0, -17.0) - sim.world.center, 0.0, e2)
	var tb2: Dictionary = {}
	if e2.is_empty():
		tb2 = H.link_now(sim, "corridor", int(j1["id"]), int(j2["id"]), e2)
	if t.check(e2.is_empty() and not tb2.is_empty(), "a corridor where the doors will be (%s)" % str(e2)):
		var d2: Dictionary = sim.build.spawn_active("rover_depot", dp2, 0.0, 1)            # test set-up: bypasses placement
		sim.topo.mark_dirty()
		g.run(2)
		t.check(not sim.nav._apron_open({"pos": dp2, "bays": sim.vehicles.bays(d2)}), "the depot is closed in")
		t.eq(sim.place.check_building("solar_array", sim.place.snap_pos(dp2 + Vector2(-40, 0)), 0.0), "ok", "building near a depot that was closed in before is still allowed")
		sim.vehicles.alight_all(v)
		var bay2: Dictionary = sim.vehicles.bays(d2)[0]
		v["pos"] = bay2["pos"]                                                                # test set-up: parked in its bay
		v["bay"] = 0
		v["depot"] = int(d2["id"])
		H.put_outside(sim, drv, sim.vehicles.board_point(v), sim.agents.suit_cap())
		sim.vehicles.board(drv, int(v["id"]))
		t.eq(g.cmd("vehicle_drive", {"id": int(v["id"]), "x": goal.x, "y": goal.y})["code"], "no_route", "a closed-in depot: no route")
		t.eq(String(v["block"]), "no_route", "it says why")
		g.run(600)
		t.eq(v["pos"], bay2["pos"], "it stayed in its bay")
	t.eq(sim.inv.audit(), {}, "the game goes on (ledger)")
	g.dispose()
	t.done()

## Paul was stuck (no spare parts): the workshop is buildable from the landing; and every lock
## says what it needs and the progress now, in the refusal text too.
func v4_locks_explained(t) -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	t.eq(int(sim.state["progress"]["stage"]), 0, "a new game is at stage Landing")
	var spot := Vector2(-1, -1)
	for r in [30.0, 40.0, 50.0, 60.0]:
		for k in 24:
			var p: Vector2 = sim.place.snap_pos(sim.world.center + Vector2.RIGHT.rotated(k * TAU / 24.0) * r)
			if spot.x < 0.0 and sim.place.check_building("workshop", p, 0.0) == "ok":
				spot = p
	t.check(spot.x > 0.0, "a workshop can be placed at stage Landing")
	t.check(sim.research.recipe_unlocked("spares"), "and it makes spare parts at once")
	# Every lock of every structure and size names its requirement.
	var bad: Array = []
	var kinds := {}
	for def_id in sim.content["buildings"]:
		var base: Dictionary = sim.content["buildings"][def_id]
		if base.get("kind", "") == "link" or not bool(base.get("buildable", true)):
			continue
		for size in [0, 1, 2, 3]:
			var li: Dictionary = sim.place.lock_info(def_id, size)
			if not bool(li["locked"]):
				continue
			kinds[li["kind"]] = true
			var txt: String = String(li["text"])
			if txt == "" or not (txt.begins_with("Unlocks at stage") or txt.begins_with("Research ") or txt.begins_with("This structure is not made in size") or txt.contains("later version")):
				bad.append("%s %d: '%s'" % [def_id, size, txt])
			if li["kind"] == "research" and not txt.contains(String(sim.content["techs"][li["tech"]]["name"])):
				bad.append("%s: the tech is not named" % def_id)
	t.eq(bad, [], "every lock has a text that names its requirement")
	t.check(kinds.has("stage") and kinds.has("research") and kinds.has("size"), "stage, research and size locks all seen: %s" % str(kinds.keys()))
	var lp: Dictionary = sim.place.lock_info("landing_pad", 1)
	t.eq(lp["kind"], "stage", "the landing pad waits for a stage")
	t.check(String(lp["text"]).contains("Stable outpost") and String(lp["text"]).contains("8 colonists (now 8)"), "with the stage name and the progress: %s" % lp["text"])
	var ro: Dictionary = sim.place.lock_info("parts_works", 1)
	t.eq(ro["text"], "Research Rover Parts first.", "a research lock names the tech")
	# The refusal text of a command and of the preview.
	var r: Dictionary = g.cmd("place_building", {"def": "landing_pad", "x": spot.x, "y": spot.y, "rot": 0.0})
	t.eq(r["code"], "locked", "placing the landing pad is refused")
	t.eq(r.get("text", ""), lp["text"], "the refusal carries the explanation")
	sim.place.check_building("parts_works", spot, 0.0)
	t.eq(sim.place.reason_text("locked_research"), "Research Rover Parts first.", "the preview text names the tech")
	g.dispose()
	t.done()

## Storage on every structure (Paul): sim.inventory.contents(x) for stores, cores, the depot,
## machine buffers, kitchens, labs and vehicle cargo; sim.inventory.by_structure(base) for the
## list; all rows together are exactly the colony's stock by the ledger.
func v4_inventory_contents(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	sim.run_seconds(30.0)
	var rows: Array = sim.inventory.by_structure(-1)
	var sum := {}
	for row in rows:
		for r in row["items"]:
			sum[r] = int(sum.get(r, 0)) + int(row["items"][r])
	var ledger := {}
	for r in sim.state["ledger"]:
		var l: Dictionary = sim.state["ledger"][r]
		var n: int = int(l["created"]) - int(l["consumed"]) - int(l["destroyed"])
		if n != 0:
			ledger[r] = n
	var diff: Array = []
	for r in ledger:
		if int(sum.get(r, 0)) != int(ledger[r]):
			diff.append("%s: rows %d, ledger %d" % [r, int(sum.get(r, 0)), int(ledger[r])])
	for r in sum:
		if int(sum[r]) != 0 and not ledger.has(r):
			diff.append("%s: rows %d, ledger 0" % [r, int(sum[r])])
	t.eq(diff, [], "the rows add up to the colony stock by the ledger")
	t.eq(sim.inv.audit(), {}, "and the ledger balances")
	# Each kind of structure.
	var seen := {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		var c: Dictionary = sim.inventory.contents(b)
		var key: String = String(b["def"])
		if key in ["storehouse", "cold_storage", "lander", "outpost_core", "rover_depot"]:
			if c["capacity"] > 0 and c["used"] <= c["capacity"] and c["full"] == (c["used"] >= c["capacity"]):
				seen[key] = true
		elif key == "kitchen" and (c["buffers"]["in_cap"] > 0 or c["buffers"]["out_cap"] > 0):
			seen[key] = true
		elif key == "research_assembler" and c["buffers"]["out_cap"] > 0:
			seen[key] = true
		elif key == "refinery" and c["buffers"]["in_cap"] > 0 and c["buffers"]["out_cap"] > 0:
			seen[key] = true
		for row in rows:
			if row["kind"] == "structure" and int(row["id"]) == int(id):
				if row["items"] != c["all"]:
					seen["mismatch"] = "%s %s %s" % [b["name"], str(row["items"]), str(c["all"])]
	for key in ["storehouse", "lander", "outpost_core", "rover_depot", "kitchen", "research_assembler", "refinery"]:
		t.check(seen.has(key), "contents() works for %s" % key)
	t.check(not seen.has("mismatch"), "each row equals its structure's contents: %s" % str(seen.get("mismatch", "")))
	var v: Dictionary = sim.vehicles.get_v(int(sim.vehicles.list()[0]["id"]))
	var vc: Dictionary = sim.inventory.contents(v)
	t.eq(int(vc["capacity"]), int(sim.vehicles.kind_of(v)["cargo"]), "a vehicle's cargo capacity")
	var lc: Dictionary = sim.inventory.contents(sim.state["buildings"][int(sim.state["lander_id"])])
	t.check(lc["items"].has("meals") and float(lc["spoil"].get("meals", -1.0)) != -1.0 or not lc["items"].has("meals"), "spoilage times where food spoils")
	# One base only.
	var camp: Array = sim.inventory.by_structure(2)
	var ok := true
	for row in camp:
		if row["kind"] == "structure" and sim.bases.base_of(int(row["id"])) != 2:
			ok = false
	t.check(ok and camp.size() >= 1, "by_structure(2) lists only the camp's structures (%d rows)" % camp.size())
	sim.dispose()
	t.done()

## Paul: a plan 30-50 m from an airlock with air showed "OUT OF REACH". Every exterior type within
## 60 m of a working airlock is in reach (reach_info and in play); one 300 m out is not; and a
## colonist outside with a part-used suit does not mark a task "too far" for everybody.
func v4_exteriors_in_reach(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier")
	sim.state["flags"]["unlock_all"] = true                                              # test set-up
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"}])
	t.eq(res["errors"], [], "the test base")
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.8, true)
	var lock: Dictionary = sim.state["buildings"][res["ids"]["L1"]]
	var door: Vector2 = sim.nav.door_pos(lock)
	var plans := {}
	var k := 0
	for def_id in sim.content["buildings"]:
		var d: Dictionary = sim.content["buildings"][def_id]
		if d.get("kind", "") != "exterior" or bool(d.get("needs_deposit", false)) or int(d.get("stage", 0)) > 0:
			continue
		k += 1
		var sz: int = int((sim.sizes.sizes_of(def_id) as Array)[0]) if not (sim.sizes.sizes_of(def_id) as Array).is_empty() else 1
		var done := false
		for r in [30.0, 38.0, 46.0, 54.0]:
			for j in 36:
				var p: Vector2 = sim.place.snap_pos(door + Vector2.RIGHT.rotated(float(j * 7 + k * 11) * TAU / 36.0) * r)
				if not done and sim.place.check_building(def_id, p, 0.0, -1, sz) == "ok":
					var cr: Dictionary = g.cmd("place_building", {"def": def_id, "x": p.x, "y": p.y, "rot": 0.0, "size": sz})
					if bool(cr["ok"]):
						plans[int(cr["id"])] = def_id
						done = true
		t.check(done, "%s placed within 60 m" % def_id)
	var far: Vector2 = Vector2(-1, -1)
	for j in 36:
		var q: Vector2 = sim.place.snap_pos(door + Vector2.RIGHT.rotated(j * TAU / 36.0) * 300.0)
		if far.x < 0.0 and sim.place.check_building("solar_array", q, 0.0) == "ok":
			far = q
	var far_id: int = int(g.cmd("place_building", {"def": "solar_array", "x": far.x, "y": far.y, "rot": 0.0}).get("id", -1))
	var bad: Array = []
	for id in plans:
		var ri: Dictionary = sim.agents.reach_info(sim.state["buildings"][id])
		if not bool(ri["ok"]):
			bad.append("%s: %s" % [plans[id], ri["text"]])
	t.eq(bad, [], "reach_info: every plan within 60 m is in reach")
	var rf: Dictionary = sim.agents.reach_info(sim.state["buildings"][far_id])
	t.check(not bool(rf["ok"]) and (rf["why"] == "too_far" or rf["why"] == "no_path"), "300 m out is not: %s" % rf["text"])
	t.check(float(rf["reach_m"]) > 100.0 and int(rf["lock"]) != -1 or rf["why"] == "no_path", "with the numbers (reach %.0f m, walk %.0f m)" % [float(rf["reach_m"]), float(rf["walk_m"])])
	# A colonist outside with a part-used suit refuses a task for itself only.
	var a: Dictionary = {}
	for aid in sim.state["agents"]:
		if a.is_empty():
			a = sim.state["agents"][aid]
	g.run(20)
	var site_id := -1
	for tid in sim.state["tasks"]:
		var tk0: Dictionary = sim.state["tasks"][tid]
		if site_id == -1 and plans.has(int(tk0["bld"])) and int(tk0["owner"]) == -1 and tk0["state"] == "open":
			site_id = int(tk0["bld"])
	var site: Dictionary = sim.state["buildings"].get(site_id, {})
	var site_tasks := 0
	var reset: Array = []
	for tid in sim.state["tasks"]:
		var tk: Dictionary = sim.state["tasks"][tid]
		if int(tk["bld"]) == site_id and int(tk["owner"]) == -1 and tk["state"] == "open":
			site_tasks += 1
			tk["reason"] = ""
			tk["retry"] = 0
			reset.append(tid)
		else:
			a["backoff"][tid] = int(sim.state["tick"]) + 100000                             # test set-up: only the site's tasks
	H.put_outside(sim, a, sim.nav.best_access(site, door) + Vector2(1, 0), 12.0)            # test set-up: 12 s of suit left
	var refused: bool = not sim.agents._try_work(a)
	var poisoned := 0
	for tid in reset:
		var tk2: Dictionary = sim.state["tasks"].get(tid, {})
		if not tk2.is_empty() and (String(tk2["reason"]) == "suit_range" or int(tk2["retry"]) > int(sim.state["tick"])):
			poisoned += 1
	t.check(site_tasks > 0 and refused, "the colonist with 12 s of air refuses the site's %d tasks" % site_tasks)
	t.eq(poisoned, 0, "a part-used suit outside does not mark the site too far for everybody")
	# UI's hypothesis: path failures from where colonists stood must not mark a reachable plan, and
	# a mark never outlives its cause (at most 120 s without a map change).
	var ft: Dictionary = {}
	for tid in sim.state["tasks"]:
		var tk3: Dictionary = sim.state["tasks"][tid]
		if int(tk3["bld"]) == site_id and ft.is_empty():
			ft = tk3
	if t.check(not ft.is_empty(), "a task of the plan"):
		for i in int(sim.bal["task_max_path_fails"]):
			if sim.state["tasks"].has(int(ft["id"])):
				sim.jobs.path_failed(ft)
		t.note("site %s %s block %s fails %d rev %d/%d kind %s" % [site["def"], site["state"], site["block"], int(ft["fails"]), int(site["unreach_rev"]), int(sim.state["rev"]["walk"]), ft["kind"]])
		g.run(10)
		t.check(String(site["block"]) != "unreachable", "failed walks from odd places do not mark a reachable plan out of reach (state %s, fails %d, rev %d/%d)" % [site["state"], int(ft["fails"]), int(site["unreach_rev"]), int(sim.state["rev"]["walk"])])
	site["unreach_rev"] = int(sim.state["rev"]["walk"])                                   # test set-up: an old mark
	site["unreach_tick"] = int(sim.state["tick"])
	g.run(20)
	t.eq(String(site["block"]), "unreachable", "a mark shows")
	g.run(1250)
	t.check(String(site["block"]) != "unreachable", "and clears within 120 s (block now '%s')" % site["block"])
	# In play: half a day, nothing near is ever "too far" or "out of reach".
	var lander_inv: int = int(sim.state["buildings"][sim.state["lander_id"]]["inv_out"])
	for r2 in ["metal", "polymer", "electronics", "composite"]:
		sim.inv.add_new_forced(lander_inv, r2, 200, "test")                             # test set-up
	var marked := {}
	for s in 30:
		g.run(100)
		H.fill_utilities(sim, 1.0, 0.8, true)
		for id in plans:
			var b: Dictionary = sim.state["buildings"].get(id, {})
			if not b.is_empty() and (String(b["block"]) == "suit_range" or String(b["block"]) == "unreachable"):
				marked[plans[id]] = String(b["block"])
	t.eq(marked, {}, "no plan within 60 m is shown too far or out of reach in play")
	g.dispose()
	t.done()


## Riders are never left to die (SIM 2026-09-30): a vehicle far from air drives back when a rider has
## a critical need (before: the crew of the parked expedition rover in showcase_v4 died of thirst and
## exhaustion aboard), and a rider set down on closed ground (a depot footprint) still finds the way
## to an airlock (before: "rescue" for ever, idle outside until the suit ran out).
func v4_riders_come_home(t) -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	var rider: Dictionary = {}
	var veh: Dictionary = {}
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive" and a["where"] == "vehicle":
			var v: Dictionary = sim.vehicles.get_v(int(a.get("veh", -1)))
			if not v.is_empty() and not sim.vehicles.near_air(v):
				rider = a
				veh = v
				break
	t.check(not rider.is_empty(), "a rider far from air in showcase_v4")
	if rider.is_empty():
		sim.dispose()
		t.done()
		return
	rider["thirst"] = 90.0                                                                 # test set-up: a critical need
	sim.run_seconds(2.0)
	t.check(bool(veh.get("returning", false)) and veh["state"] == "driving", "the vehicle turns back for the rider (%s, %s)" % [veh["state"], str(veh.get("returning"))])
	var logged := false
	for e in sim.state["log"]:
		if String(e["code"]) == "vehicle_needs":
			logged = true
	t.check(logged, "the player is told (vehicle_needs)")
	var home := false
	for s in 60:
		sim.run_seconds(10.0)
		if rider["state"] != "alive":
			break
		if rider["where"] == "in":
			home = true
			break
	t.check(home, "the rider is inside again within 10 minutes (%s, %s, health %.0f)" % [rider["state"], rider["where"], float(rider["health"])])
	# A rider set down on a closed cell: the depot centre.
	var depot := {}
	for bid in sim.state["buildings"]:
		if String(sim.state["buildings"][bid]["def"]) == "rover_depot":
			depot = sim.state["buildings"][bid]
			break
	if not depot.is_empty():
		var p: Vector2 = depot["pos"]
		t.check(not sim.nav.is_walkable(p), "the depot centre is closed ground")
		var r: Dictionary = sim.nav.nearest_supplied_lock(p)
		t.check(bool(r["ok"]), "the way to air is found from closed ground (%s)" % str(r))
	t.eq(sim.inv.audit(), {}, "ledger")
	sim.dispose()
	t.done()
