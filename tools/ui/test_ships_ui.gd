extends SceneTree
## Headless test of the version 3.1 ship interface (docs/V3_1_DESIGN.md §6.5), on the real
## simulation through the automation commands (the same as window.__fh.cmd).
##   node tools/godot.mjs script res://tools/ui/test_ships_ui.gd
## Loads showcase_v3_late with debug, builds and powers a landing pad, schedules a trader,
## a shuttle and a liner, and checks: the traffic panel shows them, the shuttle and trade
## screens open with content, a sale is accepted, credits show in the top bar, visitors
## appear in the Visitors tab and have an inspector card. Prints PASS/FAIL; exit 1 on a failure.

var main
var fails := 0
var _n := 0
var _step := 0
var _wait := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func cmd(t: String) -> String:
	var r: String = String(main._on_cmd(t))
	print("  cmd %s -> %s" % [t, r])
	return r

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func screen_ok(name: String) -> bool:
	var top = main.hud.screens.top_screen()
	if top == null or String(top.get("screen_name")) != name or top.content == null or top.content.get_child_count() == 0:
		return false
	# The frame must be on the screen (a compact dialog once stood 827 px above it).
	var vr: Rect2 = Rect2(Vector2.ZERO, root.get_visible_rect().size)
	return vr.encloses(top.frame.get_global_rect().grow(-1.0))

func _process(_d: float) -> bool:
	_n += 1
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			if _n < 5:
				return false
			# The late save with debug (hazard_now, traffic_now allowed).
			main.boot["debug"] = "1"
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
			cmd("speed 0")
			var spot: String = cmd("findspot landing_pad 1 40")
			check("a place for a landing pad", spot != "none", spot)
			cmd("place landing_pad 1 " + spot)
			set_meta("spot", spot)
			cmd("fast 400")
			var pad: String = cmd("idof landing_pad")
			cmd("cable " + pad)
			cmd("fast 200")
			var tr: String = cmd("traffic")
			check("pad active and powered", tr.contains(":active:powered=true"), tr)
			check("ship <kind> refused without debug is not the case here", cmd("ship trader 30") == "submitted")
			cmd("ship shuttle 90")
			cmd("ship liner 150")
			main.hud.traffic.refresh()
			check("traffic panel shows 3 or more ships", main.hud.traffic.visible and main.hud.traffic.rows_now.size() >= 3, str(main.hud.traffic.rows_now.size()))
			cmd("open shuttle")
			_step = 1
			_wait = 3
		1:
			var ts = main.hud.screens.top_screen()
			var shuttle_ok: bool = screen_ok("shuttle")
			# Pick settler 1 only (by person) and confirm: SIM keeps accept_idx [0].
			var shs = main.hud.screens.top_screen()
			var sid0: int = int(shs.ship_id)
			check("shuttle dialog lists one check box per settler", shs._boxes.size() == (shs._roles as Array).size() and shs._boxes.size() > 0, "%d boxes" % shs._boxes.size())
			check("shuttle dialog shows a countdown", String(shs._when.text).begins_with("Arrives in") or String(shs._when.text).begins_with("In orbit"), shs._when.text)
			shs._pick_first(1)
			shs._confirm()
			var srow: Dictionary = main.hud.data.traffic_row(sid0)
			check("confirm sends accept_idx by person", str(srow.get("accept_idx", [])) == "[0]" and int(srow.get("accept", -1)) == 1, "accept_idx %s accept %s" % [str(srow.get("accept_idx", "none")), str(srow.get("accept", ""))])
			# 60 game seconds in 1 s slices with a world-sound check after each (like play at
			# speed 1, where the check runs 5 times a second), the camera at the pad.
			cmd("goto " + String(get_meta("spot")))
			# Close over the pad: local sounds are heard only zoomed in (<= 35 m) and within 25 m.
			main.rig.distance = 15.0
			main.rig.target_distance = 15.0
			main.rig.focus = main.view.to3(main.hud.data.traffic_row(-1).get("pad_pos", Vector2(float(String(get_meta("spot")).split(" ")[0]), float(String(get_meta("spot")).split(" ")[1]))))
			main.hud.watchers.world.reset()
			for sec in 60:
				for k in int(main.sim.bal["tick_hz"]):
					main.sim.step()
				main.hud.watchers.world.check(false)
			check("shuttle screen opens with content", shuttle_ok, "%s frame %s min %s alpha %.2f/%.2f visible %s" % [main.hud.screen_name(), str(ts.frame.get_global_rect()) if ts != null else "-", str(ts.frame.get_combined_minimum_size()) if ts != null else "-", ts.modulate.a if ts != null else -1.0, ts.frame.modulate.a if ts != null else -1.0, ts.frame.is_visible_in_tree() if ts != null else false])
			var tr2: String = cmd("traffic")
			check("the trader has landed", tr2.contains("trader landed"), tr2)
			var sid: String = tr2.split("| ")[1].split(" ")[0] if tr2.contains("| ") else "-1"
			var before: int = main.hud.data.credits()
			# Sell 1 unit of the first item the ship buys that the colony has free.
			var row: Dictionary = main.hud.data.traffic_row(int(sid))
			var item := ""
			for it in row.get("offer", {}).get("buys", {}):
				if main.hud.data.free_units(String(it)) > 0:
					item = String(it)
					break
			var r: String = cmd("trade %s sell %s 1" % [sid, item])
			check("a sale to the trader is accepted", r.begins_with("ok"), r)
			cmd("trade")
			_step = 2
			_wait = 3
			set_meta("before", before)
		2:
			check("trade screen opens with content", screen_ok("trade"), main.hud.screen_name())
			cmd("close")
			cmd("fast 120")
			main.hud.top_bar.refresh()
			var kc = main.hud.top_bar._k.get("credits")
			check("credits in the top bar", kc != null and kc.visible, "credits %d (before the sale %d)" % [main.hud.data.credits(), int(get_meta("before"))])
			cmd("fast 200")
			var v: String = cmd("idof visitor 0")
			check("visitors from the liner are in the colony", v != "not found", cmd("traffic"))
			if v != "not found":
				cmd("follow " + v)
			# SIM traffic notices (tourists with no bed): under the liner card, never in the alert list.
			main.hud.traffic.refresh()
			var notes: Array = main.hud.data.traffic_notices()
			var in_alerts := false
			for inc in main.sim.alerts.incidents():
				if String(inc["issue"].get("text", "")).contains("tourist"):
					in_alerts = true
			var attached := 0
			for k in main.hud.traffic._notes:
				attached += (main.hud.traffic._notes[k] as Array).size()
			# The same with a notice for sure (mock rows: a landed liner and "3 tourists have no bed").
			main.hud.data.mock = load("res://ui/mock.gd").build(main.sim, "traffic")
			main.hud.traffic.refresh()
			var mine: Array = main.hud.traffic._notes.get(9100, [])
			check("a notice shows on its ship card (mock liner)", mine.size() == 1 and String(mine[0]).contains("tourists have no bed") and not main.hud.traffic._loose.visible, str(main.hud.traffic._notes))
			main.hud.data.mock = {}
			main.hud.traffic.refresh()
			check("traffic notices sit under their ship, not in the alerts", not in_alerts and attached + (1 if main.hud.traffic._loose.visible else 0) >= mini(1, notes.size()),
				"notices %s, under ships %s" % [str(notes), str(main.hud.traffic._notes)])
			cmd("open visitors")
			_step = 3
			_wait = 3
		3:
			check("visitors tab opens", screen_ok("colonists") and String(main.hud.screens.top_screen().tab) == "visitors", main.hud.screen_name())
			cmd("close")
			main.hud.inspector.refresh()
			var vid: String = cmd("idof visitor 0")
			if vid != "not found":
				check("visitor inspector card", main.hud.inspector.visible and String(main.hud.inspector._title.text).length() > 0 and main.hud.inspector._badges.get_child_count() > 0, main.hud.inspector._title.text)
			var pl: Dictionary = main.audio.played
			check("world sounds from the simulation played close over the pad (ship landing)", pl.has("ship_touchdown") and pl.has("ship_descent"), str(pl))
			# door_slide is RENDER's (fx_doors.gd, fx_airlock.gd): the UI's world sounds must not play it.
			check("the UI plays no door_slide (RENDER plays the doors)", not FileAccess.get_file_as_string("res://ui/hud/world_sounds.gd").contains("world(\"door_slide\""), "RENDER played it %d times" % int(pl.get("door_slide", 0)))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
