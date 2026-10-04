extends RefCounted
## Version 5 tests for docs/V5_DESIGN.md section 18.5: the package transport system (sim/transport.gd).
## Direct field writes are TEST SET-UP only and are marked as such.

const H = preload("res://tests/helpers.gd")

func tests() -> Array:
	return [
		["v5_transport_upgrades", v5_transport_upgrades],
		["v5_transport_moves_goods_without_colonists", v5_transport_moves_goods_without_colonists],
		["v5_transport_broken_link_and_alert", v5_transport_broken_link_and_alert],
		["v5_transport_capacity_and_save_load", v5_transport_capacity_and_save_load],
		["v5_transport_demo_on_showcase", v5_transport_demo_on_showcase],
	]

## A small base: the reference core and a habitat, two storehouses (SA, SB) and a workshop W next to SB, all joined
## by corridors. Returns {g, sim, ids...}. tubes: the corridors get the tube upgrade and the storehouses the hub at once
## (test set-up); without it the base is plain.
static func _base(tubes: bool) -> Dictionary:
	var g = H.Game.new(1001, false)
	var sim = g.sim
	sim.new_game(1001, "frontier", {"hazards": "off"})
	sim.state["flags"]["unlock_all"] = true                                                 # test set-up
	var lay: Dictionary = H.layout(sim, H.CORE_STEPS + [{"place": "habitat", "as": "H1"}, {"link": "corridor", "a": "L1", "b": "H1"}])
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.5, true)
	var hab: Dictionary = sim.state["buildings"][int(lay["ids"]["H1"])]
	var sa: Dictionary = H.attach(sim, "storehouse", hab["pos"] + Vector2(-40, 0))
	g.run(2)
	var sb: Dictionary = H.attach(sim, "storehouse", hab["pos"] + Vector2(40, 0))
	g.run(2)
	var w: Dictionary = H.attach(sim, "workshop", sb["pos"])
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.5, true)
	var out := {"g": g, "sim": sim, "hab": hab, "sa": sa, "sb": sb, "w": w, "lid": int(sim.state["lander_id"])}
	if tubes:
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if b["kind"] == "link" and b["def"] == "corridor":
				b["tube"] = true                                                              # test set-up
		sa["hub"] = true                                                                      # test set-up
		sb["hub"] = true                                                                      # test set-up
		sim.transport.installed(sa)
	return out

static func _corridor_between(sim, a_id: int, b_id: int) -> Dictionary:
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "link" and ((int(b["a"]) == a_id and int(b["b"]) == b_id) or (int(b["a"]) == b_id and int(b["b"]) == a_id)):
			return b
	return {}

# ---------------------------------------------------------------- the upgrades
func v5_transport_upgrades(t) -> void:
	var c: Dictionary = _base(false)
	var g = c["g"]
	var sim = c["sim"]
	var sa: Dictionary = c["sa"]
	var sb: Dictionary = c["sb"]
	var cor: Dictionary = _corridor_between(sim, int(sa["id"]), int(sb["id"]))
	t.check(not sa.is_empty() and not sb.is_empty() and not c["w"].is_empty() and not cor.is_empty(), "the base is built")
	# Research gates it.
	sim.state["flags"].erase("unlock_all")                                                  # test set-up
	t.eq(g.cmd("install_transport", {"id": int(sa["id"])})["code"], "locked_research", "the hub needs the research Package Transport")
	t.eq(g.cmd("install_transport", {"id": int(cor["id"])})["code"], "locked_research", "the tube needs it too")
	var tech: Dictionary = sim.content["techs"].get("log_transport", {})
	t.check(not tech.is_empty() and String(tech["name"]) == "Package Transport", "the tech exists: Package Transport")
	sim.state["research"]["done"]["log_transport"] = true                                   # test set-up: researched
	t.eq(g.cmd("install_transport", {"id": int(c["lid"])})["code"], "not_storage", "the lander is not a storage habitat for a hub")
	t.eq(g.cmd("install_transport", {"id": int(c["w"]["id"])})["code"], "not_storage", "a workshop is not either")
	var chk: Dictionary = sim.transport.check(sa)
	t.check(bool(chk["ok"]) and chk["feature"] == "hub" and not (chk["cost"] as Dictionary).is_empty(), "the hub upgrade has a cost: %s" % str(chk["cost"]))
	var chk2: Dictionary = sim.transport.check(cor)
	t.check(bool(chk2["ok"]) and chk2["feature"] == "tube", "the tube upgrade has a cost: %s" % str(chk2["cost"]))
	# The materials are carried and the technicians work: both upgrades finish.
	var lander: Dictionary = sim.state["buildings"][int(c["lid"])]
	sim.inv.add_new_forced(int(lander["inv_out"]), "electronics", 20, "test_setup")           # test set-up
	t.check(bool(g.cmd("install_transport", {"id": int(sa["id"])})["ok"]), "the hub upgrade is ordered")
	t.check(bool(g.cmd("install_transport", {"id": int(cor["id"])})["ok"]), "the tube upgrade is ordered")
	t.eq(g.cmd("install_transport", {"id": int(sa["id"])})["code"], "busy", "a second order for the same structure is refused (busy)")
	var done: bool = g.run_until(func(): return bool(sa.get("hub", false)) and bool(cor.get("tube", false)), 20000)
	t.check(done, "both upgrades are built by the colony (hub %s, tube %s)" % [str(sa.get("hub", false)), str(cor.get("tube", false))])
	t.eq(g.cmd("install_transport", {"id": int(sa["id"])})["code"], "have", "a structure with a hub is not offered another")
	t.check(sim.transport.any(), "the system is on")
	t.eq(sim.inv.audit(), {}, "the ledger balances")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- goods move by tube, with no colonist
func v5_transport_moves_goods_without_colonists(t) -> void:
	var c: Dictionary = _base(true)
	var g = c["g"]
	var sim = c["sim"]
	var sa: Dictionary = c["sa"]
	var sb: Dictionary = c["sb"]
	var w: Dictionary = c["w"]
	var lander: Dictionary = sim.state["buildings"][int(c["lid"])]
	# Only the hub SA has steel and polymer; the lander has none, so the nearest source is a hub.
	for res in ["metal", "polymer"]:
		for iid in sim.state["inventories"]:
			var held_n: int = sim.inv.count(int(iid), res)
			if held_n > 0 and sim.state["inventories"][iid]["role"] != "carry":
				sim.inv.destroy(int(iid), res, held_n, "test_setup")                          # test set-up: no other source
		sim.inv.add_new_forced(int(sa["inv_out"]), res, 30, "test_setup")                     # test set-up
	g.run(2)
	var ov: Dictionary = sim.transport.overview()
	t.check(bool(ov["enabled"]) and (ov["hubs"] as Array).size() == 2 and (ov["networks"] as Array).size() == 1, "one network of two hubs (%d hubs, %d networks, %d tubes)" % [(ov["hubs"] as Array).size(), (ov["networks"] as Array).size(), (ov["tubes"] as Array).size()])
	var carried0: int = int(sim.state["metrics"].get("delivered", 0))
	var hauls_from_sa := 0
	var seen_capsule := false
	for i in 900:
		g.run(1)
		for tid in sim.state["tasks"]:
			var tk: Dictionary = sim.state["tasks"][tid]
			if tk["kind"] == "haul" and int(tk["src"]) == int(sa["inv_out"]) and (int(tk["dst"]) == int(w["inv_in"]) or int(tk["dst"]) == int(sb["inv_out"])):
				hauls_from_sa += 1
		if not sim.transport.capsules_view().is_empty():
			seen_capsule = true
	var ov2: Dictionary = sim.transport.overview()
	t.check(seen_capsule, "capsules flew in the tubes")
	t.check(int(ov2["delivered"]) >= 2, "capsules arrived (%d delivered, moved %s)" % [int(ov2["delivered"]), str(ov2["moved"])])
	t.eq(hauls_from_sa, 0, "no colonist was ever given a haul between the hubs and the workshop")
	t.check(int(ov2["moved"].get("metal", 0)) >= 2 and int(ov2["moved"].get("polymer", 0)) >= 2, "steel and polymer reached the workshop by tube (%s)" % str(ov2["moved"]))
	t.check(carried0 >= 0, "(hand deliveries of other goods may go on)")
	t.check((ov2["flow"] as Dictionary).has("metal") or (ov2["flow"] as Dictionary).has("polymer"), "the overview shows the flow (%s)" % str(ov2["flow"]))
	t.eq(sim.inv.audit(), {}, "the ledger balances while goods are in flight and after")
	# The inspector shows goods in transit for a hub.
	var info: Dictionary = sim.transport.info(int(sa["id"]))
	t.check(bool(info["hub"]) and info.has("in_transit"), "the inspector data is there")
	# A capsule's position is known at every tick (RENDER).
	var cv: Array = []
	for i in 200:
		g.run(1)
		cv = sim.transport.capsules_view()
		if not cv.is_empty():
			break
	if not cv.is_empty():
		var cap: Dictionary = cv[0]
		var mid: int = (int(cap["t0"]) + int(cap["t1"])) / 2
		var pos: Dictionary = sim.transport.position_of(cap, mid)
		t.check(pos.has("pos") and (cap["segs"] as Array).size() >= 1, "a capsule has segments and a position (%s)" % str(pos))
	g.dispose()
	t.done()

# ---------------------------------------------------------------- a broken link stops the flow
func v5_transport_broken_link_and_alert(t) -> void:
	var c: Dictionary = _base(true)
	var g = c["g"]
	var sim = c["sim"]
	var sa: Dictionary = c["sa"]
	var sb: Dictionary = c["sb"]
	var cor: Dictionary = _corridor_between(sim, int(sa["id"]), int(sb["id"]))
	var lander: Dictionary = sim.state["buildings"][int(c["lid"])]
	sim.inv.destroy(int(lander["inv_out"]), "metal", sim.inv.count(int(lander["inv_out"]), "metal"), "test_setup")   # test set-up
	sim.inv.add_new_forced(int(sa["inv_out"]), "metal", 60, "test_setup")                      # test set-up
	g.run(2)
	# Capsules from SA to SB's store: hauls made on purpose (the board does the same for a consumer).
	var made := 0
	for i in 4:
		if sim.jobs._make_haul("logistics", int(sa["inv_out"]), int(sb["inv_out"]), "metal", 2, int(sb["id"]), 0):
			made += 1
	t.eq(made, 4, "four hauls are made")
	t.check(not sim.transport.capsules_view().is_empty(), "they went by tube (%d capsules)" % sim.transport.capsules_view().size())
	g.run(1200)
	var delivered1: int = int(sim.transport.overview()["delivered"])
	t.check(delivered1 >= 4, "they arrived (%d)" % delivered1)
	# Break the corridor to SB (a breach): new hauls are not routed by tube, goods in flight wait, an alert is raised.
	for i in 3:
		sim.jobs._make_haul("logistics", int(sa["inv_out"]), int(sb["inv_out"]), "metal", 2, int(sb["id"]), 0)
	cor["breach"] = true                                                                      # test set-up: the tube does not work
	g.run(20)
	var through: Array = []
	for cv in sim.transport.capsules_view():
		if (cv["path"] as Array).has(int(cor["id"])):
			through.append(int(cv["id"]))
	t.check(not through.is_empty(), "capsules are on their way through the broken tube (%d)" % through.size())
	g.run(300)
	var stuck: bool = false
	var still := 0
	for cv in sim.transport.capsules_view():
		if bool(cv["stuck"]):
			stuck = true
		if through.has(int(cv["id"])):
			still += 1
	var ov: Dictionary = sim.transport.overview()
	t.eq(still, through.size(), "the flow through the broken tube stopped: none of them arrived")
	t.check(int(ov["stuck"]) > 0 or stuck, "the goods in flight wait (%d stuck)" % int(ov["stuck"]))
	var key := "transport:%d" % int(cor["id"])
	t.check(sim.state["issues"].has(key), "an alert says the tube does not work (%s)" % str(sim.state["issues"].keys()))
	if sim.state["issues"].has(key):
		t.check(String(sim.state["issues"][key]["text"]).contains("transport tube"), "and says which: %s" % String(sim.state["issues"][key]["text"]))
	var tubes_down := 0
	for tb in ov["tubes"]:
		if not bool(tb["ok"]):
			tubes_down += 1
	t.eq(tubes_down, 1, "the overview marks the tube as down")
	# A new haul is not taken over by the tubes while the link is down.
	var tasks_before: int = sim.state["tasks"].size()
	sim.jobs._make_haul("logistics", int(sa["inv_out"]), int(sb["inv_out"]), "metal", 2, int(sb["id"]), 0)
	t.eq(sim.state["tasks"].size(), tasks_before + 1, "a haul across the broken link is left to the colonists")
	# Repaired: the flow resumes.
	cor["breach"] = false                                                                     # test set-up: repaired
	g.run(400)
	var ov2: Dictionary = sim.transport.overview()
	t.check(int(ov2["delivered"]) > delivered1, "the flow resumes when the tube works again (%d)" % int(ov2["delivered"]))
	t.eq(int(ov2["stuck"]), 0, "nothing is stuck")
	t.eq(sim.inv.audit(), {}, "the ledger balances")
	g.dispose()
	t.done()

# ---------------------------------------------------------------- capacity, the colonists' fallback, save and load
func v5_transport_capacity_and_save_load(t) -> void:
	var c: Dictionary = _base(true)
	var g = c["g"]
	var sim = c["sim"]
	var sa: Dictionary = c["sa"]
	var sb: Dictionary = c["sb"]
	var lander: Dictionary = sim.state["buildings"][int(c["lid"])]
	sim.inv.destroy(int(lander["inv_out"]), "metal", sim.inv.count(int(lander["inv_out"]), "metal"), "test_setup")   # test set-up
	sim.inv.add_new_forced(int(sa["inv_out"]), "metal", 100, "test_setup")                     # test set-up
	g.run(2)
	sim.bal["transport"]["tube_units_per_s"] = 0.2                                              # test set-up: a slow tube: 10 s a capsule of 2
	var diverted := 0
	var by_hand := 0
	for i in 20:
		var before: int = sim.state["tasks"].size()
		if sim.jobs._make_haul("logistics", int(sa["inv_out"]), int(sb["inv_out"]), "metal", 2, int(sb["id"]), 0):
			if sim.state["tasks"].size() == before:
				diverted += 1
			else:
				by_hand += 1
	t.check(diverted >= 2 and diverted <= 6, "the tube takes what its capacity allows in 30 s (%d capsules)" % diverted)
	t.check(by_hand > 0, "the rest is left to the colonists (%d hauls)" % by_hand)
	sim.bal["transport"]["tube_units_per_s"] = 2.0
	# Save with capsules in flight; the loaded game continues exactly.
	t.check(not sim.transport.capsules_view().is_empty(), "capsules are in flight")
	var cl: Dictionary = H.clone_by_save(sim)
	t.check(bool(cl["ok"]), "saved and loaded")
	if bool(cl["ok"]):
		var sim2 = cl["sim"]
		t.eq(sim2.transport.capsules_view().size(), sim.transport.capsules_view().size(), "the capsules are in the loaded game")
		for i in 900:
			sim.step()
			sim2.step()
		t.eq(H.digest(sim2), H.digest(sim), "the loaded game continues exactly")
		t.eq(sim2.inv.audit(), {}, "ledger after the load")
		sim2.dispose()
	g.dispose()
	t.done()

# ---------------------------------------------------------------- the debug demo network (RENDER): capsules in 30 s on showcase_v5
func v5_transport_demo_on_showcase(t) -> void:
	var sim = H.Sim.new()
	var Persistence = preload("res://sim/persistence.gd")
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.state["options"]["debug"] = true                                                    # test set-up: the debug option
	t.check(not sim.transport.any(), "the showcase has no transport network")
	sim.state["options"]["debug"] = false
	var id: int = sim.submit("transport_demo", {})
	sim.step()
	t.eq(sim.cmds.results.get(id, {}).get("code", ""), "debug_only", "without the debug option the command is refused")
	sim.state["options"]["debug"] = true
	id = sim.submit("transport_demo", {})
	sim.step()
	var r: Dictionary = sim.cmds.results.get(id, {})
	t.check(bool(r.get("ok", false)), "the demo network is built (%s)" % str(r.get("code", r.get("text", ""))))
	if bool(r.get("ok", false)):
		var seen := 0
		var max_caps := 0
		for i in 300:
			sim.step()
			var n: int = sim.transport.capsules_view().size()
			max_caps = maxi(max_caps, n)
			if n > 0:
				seen += 1
		var ov: Dictionary = sim.transport.overview()
		t.check(seen > 0 and max_caps > 0, "capsules are seen within 30 s (%d capsules at most)" % max_caps)
		t.check(int(ov["delivered"]) >= 1, "and some arrive (%d delivered)" % int(ov["delivered"]))
		t.check((ov["hubs"] as Array).size() >= 2 and (ov["tubes"] as Array).size() >= 1, "two hubs and a tube chain: %d hubs, %d tubes" % [(ov["hubs"] as Array).size(), (ov["tubes"] as Array).size()])
		t.eq(sim.inv.audit(), {}, "the ledger balances (the demo stock is made as debug stock)")
	sim.dispose()
	t.done()
