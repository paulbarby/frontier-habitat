extends SceneTree
## Window bounds test (Paul, 2026-09-25: "info and UI windows can not open outside the view").
##   node tools/godot.mjs script res://tools/ui/test_window_bounds.gd
## For views 1920x1080, 1280x720 and 800x600: the HUD with every panel full (hazards, traffic,
## alerts, inspector on a structure and on a colonist, toasts, medal pop-up, chapter banner),
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
	# Resize with windows open.
	for name in ["dashboard", "newcolony", "research", "settings"]:
		var nm: String = name
		q(func(): set_size(Vector2i(1920, 1080)), 4)
		q(func(): main.hud.open_screen(nm), 6)
		q(func(): set_size(Vector2i(800, 600)), 6)
		q(func(): check("resize 1920x1080 -> 800x600 with %s open" % nm, outside()); main.hud.close_modal(), 3)

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
