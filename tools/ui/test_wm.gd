extends SceneTree
## Window manager test (docs/V4_DESIGN.md §7), headless, on the inspector window.
##   node tools/godot.mjs script res://tools/ui/test_wm.gd
## Default place in the work area (top right, below the top bar, above the build bar), drag,
## snap to a work-area edge, the remembered place after close and reopen (and after a resize),
## Esc closes the last window, close-all, a drag cannot take the title bar out of the view.
## Critic round 15: the window keeps clear of the nav rail (default place and after a drag into
## the rail strip); the goals panel folds while the window covers it and opens again after.

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

func insp() -> Control:
	return main.hud.inspector

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var wm = main.hud.wm
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			wm.forget("inspector")
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
			main._on_cmd("speed 0")
			main._on_cmd("select research_lab")
			_step = 1
			_n = 0
		1:
			var r: Rect2 = insp().get_global_rect()
			var wa: Rect2 = wm.work_area()
			check("opens at its default place: top right of the work area", insp().visible and absf(r.end.x - wa.end.x) < 2.0 and absf(r.position.y - wa.position.y) < 2.0, "%s in %s" % [str(r), str(wa)])
			# Drag near the left work-area edge: it snaps onto the edge.
			main._on_cmd("drag inspector %d 300" % int(wa.position.x + 9.0))
			r = insp().get_global_rect()
			check("snaps to a work-area edge within 14 px", absf(r.position.x - wa.position.x) < 0.5 and absf(r.position.y - 300.0) < 0.5, str(r))
			main._on_cmd("drag inspector 500 260")
			var placed: Vector2 = insp().global_position
			check("Esc closes the last window", main._on_cmd("esc") == "window" and not insp().visible and wm.open_ids().is_empty())
			main._on_cmd("select kitchen")
			set_meta("placed", placed)
			_step = 2
			_n = 0
		2:
			var placed: Vector2 = get_meta("placed")
			check("long lines wrap: the inspector keeps its 392 px width (critic round 15, fix 7)", insp().size.x <= 392.5, str(insp().size))
			check("reopens where it was left", insp().visible and insp().global_position.distance_to(placed) < 2.0, "%s vs %s" % [str(insp().global_position), str(placed)])
			# The title bar cannot leave the view.
			main._on_cmd("drag inspector -2000 -500")
			var r2: Rect2 = insp().get_global_rect()
			check("a drag cannot take the title bar out of the view", r2.position.y >= 8.0 - 0.5 and r2.end.x >= 80.0 - 0.5, str(r2))
			main._on_cmd("drag inspector 500 260")
			check("close all closes every window", int(main._on_cmd("closeall")) >= 1 and not insp().visible)
			main._on_cmd("select kitchen")
			_step = 4
			_n = 0
		4:
			var nav: Rect2 = main.hud.nav.get_global_rect()
			var r4: Rect2 = insp().get_global_rect()
			check("the window is clear of the nav rail", insp().visible and r4.end.x <= nav.position.x - 7.5, "%s vs rail %s" % [str(r4), str(nav)])
			var vp4: Vector2 = main.hud.root.get_viewport_rect().size
			main._on_cmd("drag inspector %d 300" % int(vp4.x - r4.size.x * 0.5))
			_step = 5
			_n = 0
		5:
			var nav5: Rect2 = main.hud.nav.get_global_rect()
			var r5: Rect2 = insp().get_global_rect()
			check("a drag into the rail strip ends clear of the rail", r5.end.x <= nav5.position.x - 7.5, "%s vs rail %s" % [str(r5), str(nav5)])
			var g: Control = main.hud.panels._dock   # 2026-10-01: the panel manager's dock (docs/UI_PANELS.md)
			main.hud.panels.pin_dock(false)
			set_meta("goals_h", g.size.y)
			main._on_cmd("drag inspector %d %d" % [int(g.global_position.x + 30.0), int(g.global_position.y + 20.0)])
			_step = 6
			_n = 0
		6:
			var g6 = main.hud.panels
			check("the dock folds to its tabs while the window covers it", g6.collapsed and main.hud.wm.folded_names().size() >= 1, "collapsed=%s folded=%s" % [g6.collapsed, str(main.hud.wm.folded_names())])
			main._on_cmd("drag inspector 700 260")
			_step = 7
			_n = 0
		7:
			var g7 = main.hud.panels
			check("the dock opens again when the window leaves", not g7.collapsed and main.hud.wm.folded_names().is_empty(), "collapsed=%s" % g7.collapsed)
			root.size = Vector2i(1280, 720)
			_step = 3
			_n = 0
		3:
			var vp: Vector2 = main.hud.root.get_viewport_rect().size
			var r3: Rect2 = insp().get_global_rect()
			check("after a resize to 1280x720 the window is inside the view", insp().visible and Rect2(Vector2.ZERO, vp).encloses(r3.grow(-0.5)), "%s in %s" % [str(r3), str(vp)])
			check("the bounds keeper finds nothing outside", main.hud.bounds.outside(vp).is_empty(), str(main.hud.bounds.outside(vp)))
			main.hud.wm.forget("inspector")
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
