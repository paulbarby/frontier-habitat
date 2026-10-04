extends RefCounted
## V5 19.1: every corridor site whose materials are delivered is built (Paul: "supplies delivered, never built").
## Corridors are planned between pairs of rooms in a dense base (showcase_v5) and in a new colony; all must be
## finished within 15 game minutes. Before the fix some had no way to them from outside (a pocket between
## structures) and were parked as unreachable for ever; they are now worked from inside, at the mouth of an end room.

const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func tests() -> Array:
	return [
		["v5_corridor_sites_get_built_showcase", v5_showcase],
		["v5_corridor_sites_get_built_new_colony", v5_new_colony],
		["v5_multi_crop_farms", v5_multi_crop_farms],
		["v5_vehicle_status_and_guide", v5_vehicle_status_and_guide],
	]

static func _pairs(sim, n: int) -> Array:
	var rooms: Array = []
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] == "active" and b["kind"] == "room" and b["def"] != "lander":
			rooms.append(int(id))
	rooms.sort()
	var out: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if sim.place.check_link("corridor", rooms[i], rooms[j])["code"] == "ok":
				out.append([rooms[i], rooms[j]])
				if out.size() >= n:
					return out
	return out

func _check(t, sim, step: Callable, label: String) -> void:
	var ids: Array = []
	for p in _pairs(sim, 8):
		var r: Dictionary = sim.build.place_link("corridor", p[0], p[1])
		if bool(r["ok"]):
			ids.append(int(r["id"]))
	t.check(ids.size() >= 2, "%s: %d corridor sites are planned" % [label, ids.size()])
	for m in 15:
		step.call()
		var all := true
		for id in ids:
			if sim.state["buildings"][id]["state"] != "active":
				all = false
		if all:
			break
	var open: Array = []
	for id in ids:
		var b: Dictionary = sim.state["buildings"][id]
		# A plan that waits for want of a suit-range airlock is another matter (an alert says so); a site whose materials are
		# delivered must be built.
		if b["state"] != "active" and not (b["state"] == "blueprint" and String(b["block"]) == "suit_range"):
			open.append("%s %s (%s)" % [b["name"], b["state"], b["block"]])
	t.eq(open, [], "%s: every corridor site is finished within 15 game minutes (unless it waits for an airlock in suit range)" % label)
	t.eq(sim.inv.audit(), {}, "%s: ledger" % label)

func v5_showcase(t) -> void:
	var sim = H.Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	_check(t, sim, func(): sim.run_seconds(60.0), "showcase_v5")
	sim.dispose()
	t.done()

func v5_new_colony(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"hazards": "off"})
	sim.state["flags"]["unlock_all"] = true                                                  # test set-up
	var lay: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"}])
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.5, true)
	var hab: Dictionary = sim.state["buildings"][int(lay["ids"]["H1"])]
	for k in 4:
		H.attach(sim, "storehouse" if k % 2 == 0 else "habitat", hab["pos"] + Vector2(-40 + 27 * k, -30 + 20 * k))
		g.run(2)
	H.fill_utilities(sim, 1.0, 0.5, true)
	_check(t, sim, func(): g.run(600), "new colony")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 19.2 several crops in one farm
func v5_multi_crop_farms(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"hazards": "off"})
	sim.state["flags"]["unlock_all"] = true                                                  # test set-up
	var lay: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"}])
	g.run(2)
	H.fill_utilities(sim, 1.0, 1.0, true)
	var hab: Dictionary = sim.state["buildings"][int(lay["ids"]["H1"])]
	var gh: Dictionary = H.attach(sim, "greenhouse", hab["pos"] + Vector2(40, 0))
	g.run(2)
	var ff: Dictionary = H.attach(sim, "fungus_farm", hab["pos"] + Vector2(-40, 0))
	g.run(2)
	H.fill_utilities(sim, 1.0, 1.0, true)
	t.check(not gh.is_empty() and not ff.is_empty(), "a greenhouse and a fungus farm are built")
	var beds: int = (gh["trays"] as Array).size()
	var menu: Dictionary = sim.prod.farm_menu(gh)
	t.check(beds >= 4 and menu["beds"] == beds, "the greenhouse has %d beds" % beds)
	t.check((menu["allowed"] as Array).has("potato") and (menu["allowed"] as Array).has("greens"), "it may grow several crops: %s" % str(menu["allowed"]))
	t.eq((menu["crops"] as Array).size(), 1, "an old greenhouse grows one crop in all beds (migration: every bed keeps the building's crop)")
	# Bad shares are refused; good shares are planted bed by bed.
	t.eq(g.cmd("set_crops", {"id": int(gh["id"]), "beds": {"potato": 1}})["code"], "invalid", "shares must add up to the number of beds")
	t.eq(g.cmd("set_crops", {"id": int(gh["id"]), "beds": {"mushroom": beds}})["code"], "invalid", "a crop of another farm is refused")
	var shares := {"potato": 1, "greens": 1, "wheat": 1}
	shares["potato"] = beds - 2
	t.check(bool(g.cmd("set_crops", {"id": int(gh["id"]), "beds": shares})["ok"]), "set_crops is accepted")
	var m2: Dictionary = sim.prod.farm_menu(gh)
	t.eq((m2["crops"] as Array).size(), 3, "the menu lists three crops")
	var total := 0.0
	for c in m2["crops"]:
		total += float(c["share"])
		t.check(float(c["yield_per_day"]) > 0.0 and String(c["name"]) != "", "%s: a share (%.2f), a yield a day (%.1f)" % [c["crop"], float(c["share"]), float(c["yield_per_day"])])
	t.check(absf(total - 1.0) < 0.001, "the shares add up to 1")
	# Per-bed set_crop still works, and a growing bed keeps its crop.
	for i in beds:
		sim.prod.finish_seed(gh, i)
	t.eq(String(gh["trays"][0]["grow"]), "greens", "bed 0 grows the first crop in the order of the names (greens)")
	var last: int = beds - 1
	t.check(String(gh["trays"][last]["grow"]) != String(gh["trays"][0]["grow"]), "the last bed grows another crop (%s)" % String(gh["trays"][last]["grow"]))
	var before: String = String(gh["trays"][0]["grow"])
	sim.prod.set_crop(gh, "wheat", 0)
	t.eq(String(gh["trays"][0]["grow"]), before, "a growing bed keeps its crop; the new plan comes at the next seeding")
	# Each bed grows at its own speed: greens (180 s) are ready before potatoes (300 s).
	g.run(2000)
	var ready_by := {}
	for tr in gh["trays"]:
		ready_by[String(tr["grow"])] = String(tr["state"])
	t.eq(ready_by.get("greens", ""), "ready", "greens are ready after 200 s")
	t.eq(ready_by.get("potato", ""), "growing", "while the potatoes still grow")
	# Each crop gives its own yield when harvested.
	var greens_bed := -1
	for i in beds:
		if String(gh["trays"][i]["grow"]) == "greens":
			greens_bed = i
	var out_before: Dictionary = (sim.inv.get_inv(int(gh["inv_out"]))["items"] as Dictionary).duplicate()
	t.check(sim.prod.finish_harvest(gh, greens_bed), "the greens bed is harvested")
	var out_after: Dictionary = sim.inv.get_inv(int(gh["inv_out"]))["items"]
	t.eq(int(out_after.get("greens", 0)) - int(out_before.get("greens", 0)), int(sim.prod.harvest_units("greens").get("greens", 0)), "and gives the yield of greens")
	# The fungus farm takes herbs next to mushrooms (and no potatoes).
	var fm: Dictionary = sim.prod.farm_menu(ff)
	t.check((fm["allowed"] as Array).has("mushroom") and (fm["allowed"] as Array).has("herbs") and not (fm["allowed"] as Array).has("potato"), "the fungus farm grows mushrooms and herbs (%s)" % str(fm["allowed"]))
	var fbeds: int = (ff["trays"] as Array).size()
	t.check(bool(g.cmd("set_crops", {"id": int(ff["id"]), "beds": {"mushroom": fbeds - 1, "herbs": 1}})["ok"]), "mixed beds in the fungus farm")
	# Save and load keep each bed's crop.
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.eq(sim2.state["buildings"][int(gh["id"])]["trays"], gh["trays"], "every bed is the same after the load")
		sim2.dispose()
	t.eq(sim.inv.audit(), {}, "ledger")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- 19.3 vehicles: what next, why it waits
func v5_vehicle_status_and_guide(t) -> void:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"hazards": "off"})
	sim.state["flags"]["unlock_all"] = true                                                  # test set-up
	g.run(3)
	t.eq(sim.vehicles.guide()["step"], "depot", "no depot: the first step is to build one")
	var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
	var dp: Vector2 = sim.place.snap_pos((lander["pos"] as Vector2) + Vector2(0, 45))
	var depot: Dictionary = sim.build.spawn_active("rover_depot", dp, 0.0)                    # test set-up
	g.run(2)
	var ds: Dictionary = sim.vehicles.depot_status(int(depot["id"]))
	t.check(String(ds["headline"]).begins_with("Empty depot") and int(ds["bays"]) > 0, "an empty depot says so: %s" % String(ds["headline"]))
	t.eq(String(ds["next_step"]["id"]), "order", "and the next step is to order a rover")
	t.eq(sim.vehicles.guide()["step"], "vehicle", "with a depot, the next step is a vehicle")
	t.check(bool(g.cmd("build_vehicle", {"depot": int(depot["id"]), "kind": "small_rover"})["ok"]), "a rover is ordered")
	var ds2: Dictionary = sim.vehicles.depot_status(int(depot["id"]))
	t.check(String(ds2["headline"]).contains("Small rover") and (ds2["order"] as Dictionary).has("missing"), "the order says what it waits for: %s / %s" % [String(ds2["headline"]), String(ds2["why_waiting"])])
	t.check(String(ds2["why_waiting"]) != "" and String(ds2["next_step"]["text"]) != "", "it says why it waits and what to do")
	var v: Dictionary = sim.vehicles.spawn("small_rover", sim.vehicles.bay_pos(depot, 0), int(depot["id"]))      # test set-up
	v["bay"] = 0
	var s1: Dictionary = sim.vehicles.status(int(v["id"]))
	t.check(String(s1["why_waiting"]).contains("Nobody is aboard") and s1["next_step"]["id"] == "board", "no crew: %s -> %s" % [String(s1["why_waiting"]), String(s1["next_step"]["text"])])
	var btn := {}
	for b in s1["buttons"]:
		btn[String(b["id"])] = b
	t.check(not bool(btn["drive"]["enabled"]) and String(btn["drive"]["why"]) != "" and bool(btn["board"]["enabled"]), "Drive is off with a reason, Board is on")
	t.eq(sim.vehicles.guide()["step"], "crew", "with a vehicle, the next step is a crew")
	var aid: int = int(sim.state["agents"].keys()[0])
	v["crew"] = [aid]                                                                         # test set-up
	var s2: Dictionary = sim.vehicles.status(int(v["id"]))
	t.check(String(s2["headline"]).begins_with("Ready") and s2["next_step"]["id"] == "destination", "with a crew it is ready: %s" % String(s2["headline"]))
	v["charge"] = 5.0                                                                         # test set-up
	var s3: Dictionary = sim.vehicles.status(int(v["id"]))
	t.check(bool(s3["low_charge"]) and String(s3["why_waiting"]) != "", "a low battery is explained: %s" % String(s3["why_waiting"]))
	v["charge"] = 100.0
	v["block"] = "no_route"                                                                   # test set-up
	t.check(String(sim.vehicles.status(int(v["id"]))["why_waiting"]).contains("blocked"), "a blocked way is explained")
	v["block"] = ""
	v["state"] = "broken"                                                                     # test set-up
	t.check(String(sim.vehicles.status(int(v["id"]))["headline"]).begins_with("Broken"), "a broken vehicle says so")
	v["state"] = "driving"                                                                    # test set-up
	v["dest"] = (v["pos"] as Vector2) + Vector2(100, 0)
	t.check(String(sim.vehicles.status(int(v["id"]))["headline"]).begins_with("Driving"), "a driving vehicle says where")
	g.dispose()
	t.done()
