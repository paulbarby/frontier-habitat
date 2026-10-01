extends SceneTree
## Window bounds test (Paul, 2026-09-25: "info and UI windows can not open outside the view").
##   node tools/godot.mjs script res://tools/ui/test_window_bounds.gd
## For views 1920x1080, 1280x720 and 800x600: the HUD with every panel full (hazards, traffic,
## alerts, inspector on a structure and on a colonist, toasts, medal pop-up, chapter banner; since
## 2026-10-01 all of them in the panel manager, out of the centre of the view),
## then every screen and tab, one at a time. Asserts that every window rect the bounds keeper
## covers is inside the view (ui/hud/bounds_keeper.gd `outside`). Also: selections at the four
## corners of the colony, and a resize from 1920x1080 to 800x600 with screens open.
## Prints PASS/FAIL per case; exit 1 on any failure.

const SIZES := [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(800, 600)]
const SCREENS := [["menu", null], ["settings", null], ["saveload", null], ["help", null], ["newcolony", null],
	["research", null], ["research", "labs"], ["goals", null], ["awards", null], ["dashboard", null], ["dashboard", "hazards"],
	["dashboard", "industry"], ["inventory", null], ["colonists", null], ["colonists", "visitors"], ["shuttle", 9102], ["trade", null]]

var main
var fails := 0
var cases := 0
var _n := 0
var _queue: Array = []     # [[callable, frames to wait after]]
var _wait := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, bad: Array) -> void:
	cases += 1
	print("%s %s%s" % ["PASS" if bad.is_empty() else "FAIL", name, ("  -- " + "; ".join(bad)) if not bad.is_empty() else ""])
	if not bad.is_empty():
		fails += 1

func vp() -> Vector2:
	return main.hud.root.get_viewport_rect().size

func outside() -> Array:
	return main.hud.bounds.outside(vp())

func q(c: Callable, frames: int = 4) -> void:
	_queue.append([c, frames])

func set_size(s: Vector2i) -> void:
	root.size = s
	root.content_scale_size = Vector2i.ZERO

func _process(_d: float) -> bool:
	_n += 1
	if _n == 5:
		_plan()
	if _n < 6:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		print("POLYGONS SKIPPED (degenerate, by caller): %s" % str(load("res://ui/poly_guard.gd").bad))
		print("RESULT %s (%d of %d cases failed)" % ["PASS" if fails == 0 else "FAIL", fails, cases])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func _plan() -> void:
	main.boot["debug"] = "1"
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	main._on_cmd("speed 0")
	main._on_cmd("uimock all")
	for s in SIZES:
		var sz: Vector2i = s
		var tag := "%dx%d" % [sz.x, sz.y]
		q(func(): set_size(sz), 6)
		q(func(): print("  view %s (logical %s)" % [tag, str(vp())]), 1)
		# HUD with everything open.
		q(func():
			main._on_cmd("select research_lab")
			for i in 4:
				main.hud.toast("Toast number %d: a long line of text to fill the toast box and wrap onto a second line." % i, "warn")
			main._on_cmd("award first_breath")
			main._on_cmd("chapter 2"), 8)
		q(func(): check("%s HUD: panels, inspector on a structure, toasts, medal, banner" % tag, outside()), 1)
		# Paul, 2026-10-01: nothing the game shows by itself covers the centre (the middle half of the width
		# and of the height): the panel manager's urgent line, pop-ups and dock (docs/UI_PANELS.md).
		if sz.x >= 1280:
			q(func():
				var v: Vector2 = vp()
				var centre := Rect2(v * 0.25, v * 0.5)
				var bad: Array = []
				for r in main.hud.panels.shown_rects():
					if (r as Rect2).grow(-0.5).intersects(centre):
						bad.append("%s in the centre %s" % [str(r), str(centre)])
				check("%s HUD: alerts, events, messages, medal and chapter keep out of the centre" % tag, bad), 1)
		q(func(): main._on_cmd("idof agent 0"); main._on_cmd("follow " + String(main._on_cmd("idof agent 0"))), 6)
		q(func(): check("%s HUD: inspector on a colonist" % tag, outside()), 1)
		for spec in SCREENS:
			var name: String = spec[0]
			var arg = spec[1]
			q(func(): main.hud.open_screen(name, arg), 6)
			q(func():
				var bad: Array = outside()
				# The screen must really be open (a screen that fails to load has no rect to test).
				var top = main.hud.screens.top_screen()
				if top == null or String(top.get("screen_name")) != name or top.get("frame") == null:
					bad.append("screen did not open (now: %s)" % main.hud.screen_name())
				check("%s screen %s%s" % [tag, name, (" " + str(arg)) if arg != null else ""], bad)
				main.hud.close_modal(), 3)
		q(func(): main.hud.confirm("Remove Research Lab 1?", ["Half of its materials come back. Stock inside is put on the ground.", "A second line of warning text."], Callable(), "Remove", true), 6)
		q(func(): check("%s confirm dialog" % tag, outside()); main.hud.close_modal(), 3)
	# Selections at the four corners of the colony (the inspector opens for each).
	q(func(): set_size(Vector2i(800, 600)), 6)
	var corners: Array = _corner_buildings()
	for i in corners.size():
		var bid: int = corners[i]
		q(func(): main.select("building", bid); main.focus_on(main.sim.state["buildings"][bid]["pos"]), 6)
		q(func(): check("800x600 corner %d: inspector on %s" % [i, main.sim.state["buildings"][bid]["name"]], outside()), 1)
	# Paul, 2026-10-01: at 80 % scale the Settings Back button sat past a side scroll. For each
	# interface scale, no window's content is wider than its scroll area (nothing hidden sideways).
	for scv in [0.8, 1.0, 1.4]:
		var sc: float = scv
		q(func(): set_size(Vector2i(1920, 1080)); main._on_cmd("uiscale %s" % str(sc)), 12)
		for spec in SCREENS:
			var name: String = spec[0]
			var arg = spec[1]
			q(func(): main.hud.open_screen(name, arg), 8)
			q(func():
				var bad: Array = outside()
				var top = main.hud.screens.top_screen()
				if top == null or top.get("_scroll") == null:
					bad.append("screen did not open")
				else:
					var scr: ScrollContainer = top._scroll
					var cw: float = top.content.get_combined_minimum_size().x
					if cw > scr.size.x + 0.5:
						bad.append("content %.0f px wider than its area %.0f px" % [cw, scr.size.x])
					# The header too: title, every tab and the extras inside its clip area (the tabs wrap).
					var hr: Control = top.get("_hdr_row")
					if hr != null:
						var clip: Rect2 = (hr.get_parent() as Control).get_global_rect()
						if hr.get_combined_minimum_size().x > clip.size.x + 0.5:
							bad.append("header %.0f px wider than its clip area %.0f px" % [hr.get_combined_minimum_size().x, clip.size.x])
						for b in top._tab_buttons.values():
							if not clip.grow(0.5).encloses((b as Control).get_global_rect()):
								bad.append("tab %s cut off" % (b as Button).text)
				check("scale %d%% screen %s%s: content and header fit their width" % [int(sc * 100.0), name, (" " + str(arg)) if arg != null else ""], bad)
				main.hud.close_modal(), 3)
	# Resize with windows open.
	for name in ["dashboard", "newcolony", "research", "settings"]:
		var nm: String = name
		q(func(): set_size(Vector2i(1920, 1080)), 4)
		q(func(): main.hud.open_screen(nm), 6)
		q(func(): set_size(Vector2i(800, 600)), 6)
		q(func(): check("resize 1920x1080 -> 800x600 with %s open" % nm, outside()); main.hud.close_modal(), 3)
	# Critic round 21, fix 1: the bottom row (minimap, build bar) never overlaps, at every
	# interface scale, in a 1600x900 and a 1280x720 view.
	for sz2 in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		for sc in [0.8, 1.0, 1.25, 1.4]:
			var szc: Vector2i = sz2
			var scc: float = sc
			q(func(): set_size(szc); main._on_cmd("uiscale %s" % str(scc)), 20)
			q(func():
				var bad: Array = []
				var mm: Rect2 = main.hud.minimap.get_global_rect()
				var bb: Rect2 = main.hud.build_bar._tab_panel.get_global_rect()
				if mm.grow(-0.5).intersects(bb):
					bad.append("build bar %s overlaps the minimap %s" % [str(bb), str(mm)])
				var al: Control = main.hud.panels._dock   # 2026-10-01: the alerts are in the panel manager's dock
				if al.visible and al.get_global_rect().grow(-0.5).intersects(mm):
					bad.append("dock %s overlaps the minimap %s" % [str(al.get_global_rect()), str(mm)])
				var tb: Rect2 = main.hud.top_bar.get_global_rect()
				if tb.grow(-0.5).intersects(main.hud.time_panel.get_global_rect()):
					bad.append("top bar %s overlaps the time panel %s in view %s, factor %.2f" % [str(tb), str(main.hud.time_panel.get_global_rect()), str(vp()), root.content_scale_factor])
				if not Rect2(Vector2.ZERO, vp()).grow(0.5).encloses(bb):
					bad.append("build bar %s outside the view %s" % [str(bb), str(vp())])
				check("%dx%d scale %d%%: bottom and top rows do not overlap%s" % [szc.x, szc.y, int(scc * 100.0), " (names hidden)" if main.hud.build_bar.compact else ""], bad), 1)
	q(func(): main._on_cmd("uiscale 1"); set_size(Vector2i(1600, 900)), 8)
	# Critic round 21, fix 2: a window dragged low ends fully inside the work area, off the build bar.
	for target in [Vector2(500, 880), Vector2(1500, 890), Vector2(-300, 870)]:
		var tg: Vector2 = target
		q(func(): main._on_cmd("select research_lab"), 6)
		q(func(): main._on_cmd("drag inspector %d %d" % [int(tg.x), int(tg.y)]), 3)
		q(func():
			var bad: Array = []
			var r: Rect2 = main.hud.inspector.get_global_rect()
			var wa: Rect2 = main.hud.wm.work_area()
			if not wa.grow(0.5).encloses(r) and r.size.y <= wa.size.y:
				bad.append("window %s not inside the work area %s" % [str(r), str(wa)])
			if r.intersects(main.hud.build_bar._tab_panel.get_global_rect().grow(-0.5)):
				bad.append("window %s over the build bar" % str(r))
			check("drag low to %s: window inside the work area" % str(tg), bad)
			main.hud.wm.forget("inspector"), 1)

## The structures farthest north-west, north-east, south-west and south-east.
func _corner_buildings() -> Array:
	var best := [-1, -1, -1, -1]
	var score := [-1e9, -1e9, -1e9, -1e9]
	for id in main.sim.state["buildings"]:
		var b: Dictionary = main.sim.state["buildings"][id]
		if String(b.get("kind", "")) == "link":
			continue
		var p: Vector2 = b["pos"]
		var s := [-p.x - p.y, p.x - p.y, -p.x + p.y, p.x + p.y]
		for k in 4:
			if s[k] > score[k]:
				score[k] = s[k]
				best[k] = id
	return best
