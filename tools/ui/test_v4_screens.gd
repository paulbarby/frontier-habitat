extends SceneTree
## Vehicles (SIM live, milestone 3), the rover depot panel, the Outpost Kit from a vehicle's cargo,
## and the orders, job priorities and reactor controls (all SIM live; the reactor itself: test_v4_live.gd), headless:
##   node tools/godot.mjs script res://tools/ui/test_v4_screens.gd
## Set-up as SIM's own test (_depot_game): a Frontier game, unlock_all, a size L depot spawned active,
## parts in the lander store, a medium rover and a small rover spawned in bays. All test set-up; the
## checks go through the UI and SIM's real commands.

var main
var fails := 0
var _n := 0
var _step := 0
var did := -1
var med := -1
var small := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _spot(sim, def_id: String, around: Vector2, rmin: float, rmax: float, size: int) -> Vector2:
	var r: float = rmin
	while r <= rmax:
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(around + Vector2.RIGHT.rotated(k * TAU / 36.0) * r)
			if sim.place.check_building(def_id, p, 0.0, -1, size) == "ok":
				return p
		r += 6.0
	return Vector2(-1, -1)

func _labels(root_node: Node) -> String:
	var txt := ""
	for l in root_node.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	for b in root_node.find_children("*", "Button", true, false):
		txt += (b as Button).text + " "
	return txt

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var v4 = hud.v4
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.start_new(1001, {"scenario": "frontier"})
			main._on_cmd("speed 0")
			sim = main.sim
			sim.state["flags"]["unlock_all"] = true                                           # test set-up
			var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
			var p: Vector2 = _spot(sim, "rover_depot", lander["pos"], 30.0, 70.0, 2)
			check("a place for the depot", p.x > 0.0, str(p))
			var d: Dictionary = sim.build.spawn_active("rover_depot", p, 0.0, 2)              # test set-up
			did = int(d["id"])
			for r in {"metal": 80, "polymer": 30, "electronics": 30, "composite": 12, "spare_parts": 12}:
				sim.inv.add_new_forced(int(lander["inv_out"]), r, 30, "test")                  # test set-up
			med = int(sim.vehicles.spawn("medium_rover", sim.vehicles.bay_pos(d, 2), did)["id"])   # test set-up
			small = int(sim.vehicles.spawn("small_rover", sim.vehicles.bay_pos(d, 0), did)["id"])  # test set-up
			_step = 1
			_n = 0
		1:
			check("vehicles come from SIM (live)", v4.live("vehicles") and v4.vehicles().size() == 2, str(v4.vehicles().size()))
			var v: Dictionary = v4.vehicle(med)
			check("rows are normalised: charge 0..1, full range, cargo 40", float(v["charge"]) >= 0.0 and float(v["charge"]) <= 1.0 and float(v["range_m"]) > 1000.0 and int(v["cargo_cap"]) == 40,
				"charge %.2f range %d cargo %d" % [float(v["charge"]), int(v["range_m"]), int(v["cargo_cap"])])
			main._on_cmd("open vehicles")
			_step = 2
			_n = 0
		2:
			var top = hud.screens.top_screen()
			top._show(med)
			var txt: String = _labels(top._detail)
			check("the vehicle screen lists both and shows charge, range, cargo, crew, wear and the orders",
				top.rows.size() == 2 and txt.contains("Charge") and txt.contains("Range now") and txt.contains("of 40") and txt.contains("seats") and txt.contains("Wear") and txt.contains("Drive to") and txt.contains("Get out") and txt.contains("Unload all"), txt.substr(txt.find("Bay"), 200))
			var r: Dictionary = v4.vehicle_cmd("cargo", med, {"load": {"metal": 5}})
			check("Load (vehicle_cargo) moves stock into the cargo", bool(r["ok"]) and int(v4.vehicle(med)["cargo"].get("metal", 0)) == 5, "%s %s" % [r["code"], str(v4.vehicle(med)["cargo"])])
			var r2: Dictionary = v4.vehicle_cmd("cargo", med, {"unload": true})
			check("Unload all (vehicle_cargo unload) empties it", bool(r2["ok"]) and int(v4.vehicle(med)["cargo"].get("metal", 0)) == 0, r2["code"])
			var r3: Dictionary = v4.vehicle_cmd("drive", med, {"target": v4.vehicle(med)["pos"] + Vector2(40, 0)})
			check("Drive with nobody aboard: refused no_driver, with the reason", not bool(r3["ok"]) and String(r3["code"]) == "no_driver" and v4.refusal_text("no_driver").contains("drive"), r3["code"])
			var aid: int = -1
			for id in sim.state["agents"]:
				if String(sim.state["agents"][id].get("state", "")) == "alive":
					aid = int(id)
					break
			var r4: Dictionary = v4.vehicle_cmd("board", med, {"agents": [aid]})
			check("Board (vehicle_board) sends a colonist", bool(r4["ok"]), r4["code"])
			# Outpost Kit from the cargo: the command goes to SIM with the vehicle's cargo inventory.
			sim.inv.add_new_forced(int(v4.vehicle(med)["cargo_inv"]), "outpost_kit", 1, "test")   # test set-up
			top._show(med)
			check("with an Outpost Kit aboard, the Deploy button shows", _labels(top._detail).contains("Deploy Outpost Kit"))
			var pos: Vector2 = v4.vehicle(med)["pos"]
			var r5: Dictionary = v4.vehicle_cmd("deploy", med, {"x": pos.x + 10.0, "y": pos.y})
			check("deploy from the cargo reaches SIM (next to the landing base: too_close_base)", not bool(r5["ok"]) and ["too_close_base", "blocked", "no_support", "overlap"].has(String(r5["code"])) or String(r5["code"]).begins_with("too"), r5["code"])
			top.set_tab("routes")
			_step = 3
			_n = 0
		3:
			var top = hud.screens.top_screen()
			check("routes with one base: the builder says a second base is needed", _labels(top.content).contains("needs two bases"))
			check("no sideways scroll bar on the vehicles screen", not top._scroll.get_h_scroll_bar().visible)
			main._on_cmd("close")
			main.select("building", did)
			_step = 4
			_n = 0
		4:
			hud.inspector.set_tab("vehicles")
			_step = 5
			_n = 0
		5:
			var txt: String = _labels(hud.inspector._body)
			if not txt.contains("Build a vehicle"):
				print("  (tab now: %s)" % hud.inspector.tab)
			check("the depot has a Vehicles tab: bays, and a Build button per kind", txt.contains("Bay 1, small: Small rover") and txt.contains("Bay 3, medium: Medium rover") and txt.to_lower().contains("build a vehicle") and txt.contains("Medium rover") and txt.contains("Hopper"), txt.substr(txt.find("Bay"), 200))
			var r: Dictionary = v4.build_vehicle(did, "small_rover")
			check("Build (build_vehicle) orders a small rover", bool(r["ok"]) and typeof(sim.state["buildings"][did].get("vorder")) == TYPE_DICTIONARY, r["code"])
			var r2: Dictionary = v4.build_vehicle(did, "hopper")
			check("a second order is refused: busy (one at a time)", not bool(r2["ok"]) and String(r2["code"]) == "busy", r2["code"])
			hud.inspector.refresh()
			var ob_text: String = _labels(hud.inspector._body)
			check("the Building section shows the order and Cancel", ob_text.contains("Small rover: carriers bring the parts") and ob_text.contains("Cancel the build"), ob_text.left(200))
			var r3: Dictionary = v4.cancel_vehicle(did)
			check("Cancel (cancel_vehicle)", bool(r3["ok"]), r3["code"])
			# ---- orders and boarding (live) from the orders window
			var aid: int = -1
			for id in sim.state["agents"]:
				if String(sim.state["agents"][id].get("state", "")) == "alive" and String(sim.state["agents"][id].get("where", "")) != "vehicle":
					aid = int(id)
			main.select("agent", aid)
			set_meta("aid", aid)
			main._on_cmd("speed 1")   # a few ticks: the topology (air groups) is built for the new structures
			_step = 6
			_n = 0
		6:
			main._on_cmd("speed 0")
			var aid: int = get_meta("aid")
			check("orders and reactors are live (SIM milestones 4 and 6)", v4.live("orders") and v4.live("reactors"))
			hud.orders.open_for_selected()
			check("Orders opens with the selected colonist", hud.orders.visible and hud.orders.group.has(aid))
			hud.orders._send("stay", [aid], null)
			var st_ok: bool = String(sim.state["agents"][aid].get("order", {}).get("kind", "")) == "stay"
			check("Stay here: SIM order stay is given, or SIM's refusal text is shown", st_ok or (hud.orders.last_refused == [aid] and hud.orders._msg.text.contains(String((hud.orders._reasons.get(aid, {}) as Dictionary).get("text", "~")))), hud.orders._msg.text)
			if not st_ok:
				print("  NOTE for SIM: stay in the lander refused: %s" % hud.orders._msg.text)
			var far: Vector2 = sim.state["agents"][aid]["pos"] + Vector2(900, 0)
			hud.orders._send("goto", [aid], far)
			var rs: Dictionary = hud.orders._reasons.get(aid, {})
			check("a deadly order is refused with SIM's reason, and it can be confirmed", hud.orders.last_refused == [aid] and ["suit_range", "radiation", "no_path"].has(String(rs.get("code", ""))) and hud.orders._msg.text.contains(String(rs.get("text", "~"))),
				"%s | %s" % [str(rs), hud.orders._msg.text])
			if bool(rs.get("confirmable", false)):
				var r2: Dictionary = v4.command("order_give", {"agents": [aid], "kind": "goto", "target": far, "force": true})
				check("confirmed, it is given with confirm: true", bool(r2["ok"]) and String(v4.order_of(aid).get("kind", "")) == "goto" and bool(v4.order_of(aid).get("confirm", false)), str(v4.order_of(aid)))
			hud.orders._cancel()
			check("Cancel (order_clear) ends it", v4.order_of(aid).is_empty() and not sim.state["agents"][aid].has("order"))
			var ex: Dictionary = v4.vehicle_cmd("explore", med, {"target": v4.vehicle(med)["pos"] + Vector2(150, 0)})
			check("vehicle Explore area reaches SIM (vehicle_explore)", bool(ex["ok"]) or ["no_driver", "no_route"].has(String(ex["code"])), ex["code"])
			main._on_cmd("closeall")
			main._on_cmd("open colonists")
			_step = 7
			_n = 0
		7:
			hud.screens.top_screen().set_tab("priorities")
			_step = 8
			_n = 0
		8:
			var aid: int = get_meta("aid")
			var cats: Array = v4.job_categories()
			check("priorities use SIM's five categories", cats.size() == 5 and cats.has("construction") and cats.has("repair"), str(cats))
			var before: int = v4.priority(aid, "construction")
			var cell: Button = null
			var reset: Button = null
			for b in hud.screens.top_screen().content.find_children("*", "Button", true, false):
				if (b as Button).tooltip_text.begins_with(String(sim.state["agents"][aid]["name"]) + ": Construction"):
					cell = b
			if cell != null:
				cell.pressed.emit()
			var want: int = {3: 2, 2: 1, 1: 0, 0: 3}.get(before, 2)
			check("a click sets the colonist's own value (set_jobs)", cell != null and v4.priority(aid, "construction") == want and v4.is_own(aid, "construction") and cell.text == ({3: "3 First", 2: "2 Normal", 1: "1 Last", 0: "– Never"}[want]),
				"before %d after %d own %s" % [before, v4.priority(aid, "construction"), v4.is_own(aid, "construction")])
			v4.command("reset_priority", {"agent": aid})
			check("Colony (set_jobs clear) goes back to the colony priorities", not v4.is_own(aid, "construction") and not sim.state["agents"][aid].has("jobs"))
			main._on_cmd("close")
			main._on_cmd("reactor")
			_step = 9
			_n = 0
		9:
			# The reactor is SIM's now (milestone 6): tools/ui/test_v4_live.gd tests it on showcase_v4.
			check("no reactor here: the window says so, no banner", hud.reactor_win.visible and hud.reactor_win._na.visible and not hud.reactor_banner.visible)
			check("the bounds keeper finds nothing outside", hud.bounds.outside(hud.root.get_viewport_rect().size).is_empty(), str(hud.bounds.outside(hud.root.get_viewport_rect().size)))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
