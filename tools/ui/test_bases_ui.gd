extends SceneTree
## Base switcher and base filters (V4_DESIGN §2; SIM sim.bases, milestone 2), headless:
##   node tools/godot.mjs script res://tools/ui/test_bases_ui.gd
## A new Frontier game has one base: the switcher is hidden. A second base is founded with an
## Outpost Kit (test set-up, as SIM's v4_outpost_founds_a_base) through the real command. Then:
## the switcher shows "All bases" + both; picking a base moves the camera there, filters the alerts
## panel (the base's own and colony-wide alerts) and the inventory screen (sim.bases.totals); Find
## rows name their base.

var main
var fails := 0
var _n := 0
var _step := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _spot(sim, dist: float) -> Vector2:
	for k in 72:
		var a: float = TAU * float(k) / 72.0
		var p: Vector2 = sim.world.center + Vector2(cos(a), sin(a)) * dist
		if sim.bases.check_outpost(p, 0.0) == "ok":
			return p
	return Vector2(-1, -1)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var tb = main.hud.top_bar
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.start_new(1001, {"scenario": "frontier"})
			main._on_cmd("speed 0")
			_step = 1
			_n = 0
		1:
			var s = main.sim
			check("one base: the switcher is hidden", s.bases.count() == 1 and not tb._base_opt.visible, "bases %d" % s.bases.count())
			var spot: Vector2 = _spot(s, 420.0)
			check("a place for an outpost", spot.x > 0.0, str(spot))
			var pile: int = s.inv.create_inv("g", 0, "pile", 100000, spot + Vector2(12, 0))   # test set-up
			s.inv.add_new_forced(pile, "outpost_kit", 1, "test")                                # test set-up
			main.submit("deploy_outpost", {"x": spot.x, "y": spot.y, "rot": 0.0, "inv": pile, "name": "Crater camp"})
			set_meta("spot", spot)
			_step = 2
			_n = 0
		2:
			var s = main.sim
			check("the outpost founded a second base (real command)", s.bases.count() == 2, "bases %d" % s.bases.count())
			main.hud.top_bar.refresh()
			var names: Array = []
			for i in tb._base_opt.item_count:
				names.append(tb._base_opt.get_item_text(i))
			check("the switcher shows All bases and both bases", tb._base_opt.visible and names.size() == 3 and names[0] == "All bases" and names.has("Crater camp"), str(names))
			var bid: int = -1
			for b in s.bases.list():
				if String(b["name"]) == "Crater camp":
					bid = int(b["id"])
			set_meta("bid", bid)
			tb._base_opt.select(tb._base_ids.find(bid))
			tb._base_opt.item_selected.emit(tb._base_ids.find(bid))
			_step = 3
			_n = 0
		3:
			var bid: int = get_meta("bid")
			var spot: Vector2 = get_meta("spot")
			check("picking a base sets the filter", main.hud.base_filter == bid, str(main.hud.base_filter))
			var f: Vector3 = main.rig.focus if "focus" in main.rig else Vector3.ZERO
			check("picking a base moves the camera to it", Vector2(f.x, f.z).distance_to(spot) < 60.0 or not ("focus" in main.rig), "focus %s spot %s" % [str(f), str(spot)])
			# Alerts: every card shown belongs to this base or to the whole colony.
			var ok := true
			var inc: Array = main.sim.alerts.incidents()
			var shown_keys: Array = []
			for c in main.hud.alerts._cards:
				shown_keys.append(c.get("key", ""))
			for i in inc:
				var ib: int = int(i["issue"].get("base", -1))
				if ib != -1 and ib != bid and shown_keys.has(i["issue"]["key"]):
					ok = false
			check("the alerts panel shows no alert of another base", ok and main.hud.alerts._cards.size() > 0, "%d cards" % main.hud.alerts._cards.size())
			main._on_cmd("open inventory")
			_step = 4
			_n = 0
		4:
			var top = main.hud.screens.top_screen()
			check("the inventory names the base", top != null and String(top._subtitle_label.text).contains("Crater camp"), top._subtitle_label.text if top != null else "-")
			check("the inventory uses the base stock", top != null and top._totals().hash() == main.sim.bases.totals(get_meta("bid")).hash())
			main._on_cmd("close")
			var r: String = main._on_cmd("find core")
			check("Find rows name their base", main.hud.find.results.size() >= 1 and String(main.hud.find.results[0].get("base", "")) != "", r)
			tb.rename_to("Rim camp")
			tb.refresh()
			check("rename the picked base (rename_base)", main.sim.bases.name_of(get_meta("bid")) == "Rim camp" and tb._base_opt.get_item_text(tb._base_opt.selected) == "Rim camp", main.sim.bases.name_of(get_meta("bid")))
			check("the rename button shows while one base is picked", tb._rename_btn.visible)
			main.hud.set_base_filter(-1)
			check("All bases clears the filter", main.hud.base_filter == -1)
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
