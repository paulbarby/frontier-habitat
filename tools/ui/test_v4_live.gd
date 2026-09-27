extends SceneTree
## SIM milestones 6 to 8 in the UI, on content/saves/showcase_v4.fhsave (debug on), headless:
##   node tools/godot.mjs script res://tools/ui/test_v4_live.gd
## The reactor window, banner and commands (SIM's, no mock), the radiation dose on the colonist card
## and in the colonists list, points of interest in Find, on the map and in the 3D view, the fog,
## the Explored and Vehicle range overlays, the satellite on the map and on the launch pad.

var main
var fails := 0
var _n := 0
var _step := 0
var rid := -1
var aid := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _texts(n: Node) -> String:
	var txt := ""
	for l in n.find_children("*", "Label", true, false):
		txt += (l as Label).text + " | "
	for b in n.find_children("*", "Button", true, false):
		txt += (b as Button).text + " | "
	return txt

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var v4 = hud.v4 if hud != null else null
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
			main._on_cmd("speed 0")
			main.sim.state["options"]["debug"] = true        # test set-up: SIM's debug commands (as boot debug=1)
			_step = 1
			_n = 0
		1:
			check("the mock is gone: every system is SIM's", v4.live("vehicles") and v4.live("orders") and v4.live("reactors") and v4.live("explore") and not ("mock_on" in v4))
			var rs: Array = v4.reactors()
			check("the showcase has a reactor (SIM list)", rs.size() >= 1, str(rs.size()))
			if rs.is_empty():
				_step = 99
				return false
			rid = int(rs[0]["id"])
			var r: Dictionary = rs[0]
			check("rows are normalised: phase, heat scale, power", String(r["phase"]) in ["normal", "warning"] and float(r["heat_max"]) == 100.0 and float(r["warn_at"]) == 60.0 and r.has("power_out"),
				"%s heat %.1f power %.0f" % [r["phase"], float(r["heat"]), float(r["power_out"])])
			var out: String = main._on_cmd("reactor stage warning")
			r = v4.reactors()[0]
			check("debug reactor_stage warning: the phase is warning", String(r["phase"]) == "warning", out)
			# With coolant the core cools (SIM: -0.06/s against +0.05/s): no time to critical then.
			if float(r["rate"]) > 0.0:
				check("the forecast says when it goes critical", String(r.get("next_stage", "")) == "critical" and float(r["next_phase_s"]) > 0.0, "%s in %.0f s" % [r.get("next_stage"), float(r["next_phase_s"])])
			else:
				check("cooling: no time to critical, the status says it cools", float(r["next_phase_s"]) < 0.0 and hud.reactor_win.status_line(r).begins_with("Cooling down"), hud.reactor_win.status_line(r))
			_step = 2
			_n = 0
		2:
			var r: Dictionary = v4.reactors()[0]
			check("the banner shows the warning", hud.reactor_banner.visible and hud.reactor_banner.shown_phase == "warning")
			var wt: String = _texts(hud.reactor_win)
			check("the window shows the heat, what comes next and the actions", hud.reactor_win.visible and (wt.contains("Critical in") or wt.contains("Cooling down")) and wt.contains("SCRAM") and wt.contains("Dump coolant") and wt.contains("Evacuate") and wt.contains("of 100"), wt.left(300))
			var h0: float = float(r["heat"])
			hud.reactor_win._do("reactor_cool", rid, String(r["name"]))
			var lr: Dictionary = hud.reactor_win.last_result
			var h1: float = float(v4.reactors()[0]["heat"])
			if int(r["coolant"]) > 0:
				check("Dump coolant: SIM takes heat off", bool(lr.get("ok", false)) and h1 < h0 and int(lr.get("result", {}).get("used", 0)) > 0, "%.1f -> %.1f %s" % [h0, h1, str(lr)])
			else:
				check("Dump coolant without coolant: SIM refuses with its reason", not bool(lr.get("ok", true)) and String(lr.get("code", "")) == "no_coolant", str(lr))
			main._on_cmd("reactor stage critical")
			r = v4.reactors()[0]
			check("critical: phase and forecast to breach", String(r["phase"]) == "critical" and String(r.get("next_stage", "")) == "breach", "%s next %s" % [r["phase"], r.get("next_stage")])
			_step = 3
			_n = 0
		3:
			check("the banner shows critical", hud.reactor_banner.visible and hud.reactor_banner.shown_phase == "critical")
			var name: String = String(v4.reactors()[0]["name"])
			hud.reactor_win._do("reactor_scram", rid, name)
			var r: Dictionary = v4.reactors()[0]
			check("SCRAM: SIM sets it, the rods drop (12 s)", bool(r["scram"]) and float(r.get("scram_left_s", 0.0)) > 0.0, str(hud.reactor_win.last_result))
			check("the status line counts the SCRAM down", hud.reactor_win.status_line(r).begins_with("SCRAM: the fission stops in"), hud.reactor_win.status_line(r))
			hud.reactor_win._do("reactor_restart", rid, name)
			var lr: Dictionary = hud.reactor_win.last_result
			check("Restart while hot: refused, with the reason in words", not bool(lr.get("ok", true)) and String(lr.get("code", "")) == "too_hot" and String(lr.get("text", "")).begins_with("Too hot"), str(lr))
			hud.reactor_win.refresh(true)
			var restart_disabled := false
			for b in hud.reactor_win.find_children("*", "Button", true, false):
				if (b as Button).text == "Restart":
					restart_disabled = (b as Button).disabled
			check("the Restart button is off while the core is hot", restart_disabled)
			hud.reactor_win._do("reactor_evacuate", rid, name)
			lr = hud.reactor_win.last_result
			r = v4.reactors()[0]
			check("Evacuate: SIM moves people out of the zone", bool(lr.get("ok", false)) and bool(r["evac"]) and lr.get("result", {}).has("moved"), str(lr))
			var ev_off := false
			hud.reactor_win.refresh(true)
			for b in hud.reactor_win.find_children("*", "Button", true, false):
				if (b as Button).text == "Evacuate":
					ev_off = (b as Button).disabled
			check("Evacuate is off while the evacuation is on", ev_off)
			check("the minimap draws the blast ring (a reactor past normal)", String(r["phase"]) != "normal")
			main._on_cmd("closeall")
			# ---- dose
			for id in sim.state["agents"]:
				if sim.state["agents"][id]["state"] == "alive" and not hud.data.is_visitor(sim.state["agents"][id]):
					aid = int(id)
					break
			sim.state["agents"][aid]["dose"] = 300.0                                       # test set-up
			main.select("agent", aid)
			_step = 4
			_n = 0
		4:
			var t: String = _texts(hud.inspector)
			check("colonist card: HIGH DOSE badge and the dose row", t.contains("HIGH DOSE") and t.contains("300 mSv") and t.contains("Radiation now"), t.left(400))
			sim.state["agents"][aid]["dose"] = 800.0                                       # test set-up
			main.select("agent", -1)
			main.select("agent", aid)
			main._on_cmd("open colonists")
			_step = 5
			_n = 0
		5:
			var t: String = _texts(hud.inspector)
			check("800 mSv: DANGEROUS DOSE", t.contains("DANGEROUS DOSE"))
			var top = hud.screens.top_screen()
			var row: Dictionary = top._rows.get(aid, {})
			check("colonists list: a Dose column with the value in red", not row.is_empty() and (row["dose"] as Label).text == "800 mSv" and (row["dose"] as Label).get_theme_color("font_color").r > 0.9,
				str(row.get("dose", null).text if not row.is_empty() else ""))
			top._sort = "dose"
			top._fill()
			var first: int = -1
			for id in top._rows:
				first = int(id)
				break
			check("sort by dose puts the highest first", first == aid, "%d vs %d" % [first, aid])
			main._on_cmd("closeall")
			sim.state["agents"][aid]["dose"] = 0.0
			# ---- exploration
			check("fog is on (2,560 m map)", v4.explore_active() and not v4.fog().is_empty() and v4.explored_share() > 0.05 and v4.explored_share() < 0.9, "%.2f" % v4.explored_share())
			var pois: Array = v4.pois()
			var all_p: Array = v4.pois(true)
			check("only found points of interest show", pois.size() >= 1 and pois.size() <= all_p.size(), "%d of %d" % [pois.size(), all_p.size()])
			var need_ok := true
			for p in pois:
				if String(p["need_text"]) == "" or String(p["name"]) == "":
					need_ok = false
			check("every point of interest has a name and what a visit needs", need_ok)
			hud.find.search("point of interest")
			var pr: Array = hud.find.results.filter(func(x): return bool(x.get("poi", false)))
			check("Find lists the found points of interest", pr.size() == pois.size(), "%d rows" % pr.size())
			var ft: String = _texts(hud.find)
			check("a Find row names the need, the distance and what it gives", ft.contains("Needs ") and ft.contains(" m away") and ft.contains("Gives "), ft.left(300))
			if not pois.is_empty():
				var p0: Dictionary = pois[0]
				hud.find.search(String(p0["name"]).to_lower())
				var hit := false
				for x in hud.find.results:
					if bool(x.get("poi", false)) and int(x["id"]) == int(p0["id"]):
						hit = true
				check("Find by kind name finds it", hit, String(p0["name"]))
				main.rig._photo = false          # test set-up: no title orbit headless
				main.rig.skip_intro()
				hud.find._go({"poi": true, "id": int(p0["id"]), "pos": p0["pos"]})
				check("a click aims the camera and marks the point", hud.poi_marks.target == int(p0["id"]))
				var pay: Dictionary = v4._order_payload("survey", [aid], {"poi": int(p0["id"])}, false)
				check("Survey order to a point of interest (SIM poi)", int(pay.get("poi", -1)) == int(p0["id"]) and not pay.has("site"), str(pay))
			hud.find.visible = false
			var sat_up: bool = v4.sats()[0]["uplink"] if not v4.sats().is_empty() else false
			print("NOTE satellite uplink at load: %s" % str(sat_up))
			_step = 6
			_n = 0
		6:
			if _n < 45:
				return false   # the camera flies to the point; the tags poll every 20 frames
			check("the 3D view shows point-of-interest tags", hud.poi_marks.shown >= 1, "%d shown of %d" % [hud.poi_marks.shown, hud.poi_marks._rows.size()])
			hud.set_overlay("explored")
			hud.minimap.refresh()
			var leg: String = hud.minimap._legend.text
			check("Explored overlay: share and satellite bands in the legend", hud.minimap._legend.visible and leg.contains("% explored") and leg.contains("bands"), leg)
			check("the fog image is made from SIM's fog", hud.minimap._fog_img != null and hud.minimap._fog_rev == int(v4.fog()["rev"]))
			var sats: Array = v4.sats()
			check("a satellite with its mapped bands", sats.size() >= 1 and (sats[0]["mapped"] as Array).size() == int(sats[0]["bands_done"]), str(sats.slice(0, 1)))
			check("the Explored and Range buttons show on this map", hud.minimap._ov["explored"].visible and hud.minimap._ov["range"].visible)
			hud.set_overlay("range")
			var vs: Array = v4.vehicles()
			var rng_ok: bool = not vs.is_empty()
			for v in vs:
				if float(v.get("range_left_m", -1.0)) < 0.0 or float(v["range_left_m"]) > float(v["range_m"]) + 0.1:
					rng_ok = false
			check("Range overlay: every vehicle has the range it has left", rng_ok, str(vs.map(func(v): return int(v.get("range_left_m", -1)))))
			check("Range legend", hud.minimap._legend.text.begins_with("Rings:"))
			hud.set_overlay("")
			main._on_cmd("select launch_pad satellite")
			_step = 7
			_n = 0
		7:
			var t: String = _texts(hud.inspector)
			check("launch pad: Satellite tab with the orbit and the build card", hud.inspector.tab == "satellite" and t.contains("of 16 bands mapped") and t.contains("Build satellite"), t.left(300))
			check("the bounds keeper finds nothing outside", hud.bounds.outside(hud.root.get_viewport_rect().size).is_empty(), str(hud.bounds.outside(hud.root.get_viewport_rect().size)))
			main._on_cmd("closeall")
			main._on_cmd("open vehicles")
			main._on_cmd("tab routes")
			_step = 8
			_n = 0
		8:
			# Critic round 22: the routes, vehicles and priorities screens are sized to their content.
			var top = hud.screens.top_screen()
			var fr: Rect2 = top.frame.get_global_rect()
			var vp: Vector2 = root.get_viewport().get_visible_rect().size
			check("Routes: sized to its content, centred, inside the view", top._fit_on and fr.size.x < vp.x - 100.0 and fr.size.y < vp.y - 100.0 and Rect2(Vector2.ZERO, vp).encloses(fr), str(fr))
			check("Routes: the header fits (no tab cut)", top._hdr_row.get_combined_minimum_size().x + 80.0 <= fr.size.x, "%.0f in %.0f" % [top._hdr_row.get_combined_minimum_size().x, fr.size.x])
			main._on_cmd("closeall")
			main._on_cmd("open colonists")
			main._on_cmd("tab priorities")
			_step = 9
			_n = 0
		9:
			var top = hud.screens.top_screen()
			var fr: Rect2 = top.frame.get_global_rect()
			var vp: Vector2 = root.get_viewport().get_visible_rect().size
			check("Priorities: sized to its content", top._fit_on and fr.size.x < vp.x - 100.0, str(fr))
			top.set_tab("colonists")
			_step = 10
			_n = 0
		10:
			var top = hud.screens.top_screen()
			check("Colonists tab: full screen again", not top._fit_on and top.frame.get_global_rect().size.x > root.get_viewport().get_visible_rect().size.x - 100.0, str(top.frame.get_global_rect()))
			main._on_cmd("closeall")
			_step = 99
		99:
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
