extends SceneTree
## Colonists window, Priorities tab (Paul, 2026-10-03), headless, on showcase_v5:
##   node tools/godot.mjs script res://tools/ui/test_priorities.gd
## Layout: the three tabs have one window size and the same row height; the table fits the view at
## 1920x1080 and 1280x720, interface scale 100 and 140 % (no sideways scroll, no cut header).
## Behaviour, by the player's path (a real mouse click on a cell): the value is stored in SIM (set_jobs),
## it is the colonist's own and overrides the colony default (which a gold cell changes through set_priority),
## the cell looks different from a cell that follows the colony, and Reset (set_jobs clear) goes back.
## SIM's score uses the own value first (jobs.score on a made-up task); the effect on job choice is SIM's test.

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var aid := -1
var bid := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 4) -> void:
	_queue.append([c, frames])

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		_plan()
	if _n < 7:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _queue.is_empty():
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func _top():
	return main.hud.screens.top_screen()

## The cell button of a colonist (agent id) or of the colony row (agent -1) for a job.
func _cell(agent: int, job: String) -> Button:
	var top = _top()
	if top == null:
		return null
	for b in top.content.find_children("*", "Button", true, false):
		if b.has_meta("job") and String(b.get_meta("job")) == job:
			if agent < 0 and not b.has_meta("agent"):
				return b
			if agent >= 0 and b.has_meta("agent") and int(b.get_meta("agent")) == agent:
				return b
	return null

## A real click: the mouse moves to the middle of the control, presses and releases.
func _click(c: Control) -> void:
	var pos: Vector2 = c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.position = pos
	dn.global_position = pos
	Input.parse_input_event(dn)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)

func _reset_button(agent: int) -> Button:
	var r: Dictionary = _top()._prows.get(agent, {})
	return r.get("reset", null)

func _plan() -> void:
	Input.use_accumulated_input = false
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = Vector2i.ZERO
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	q(func(): main._on_cmd("uiscale 1"), 6)
	q(func(): _sizes_loop(0), 6)

# ---------------------------------------------------------------- layout
const VIEWS := [[Vector2i(1920, 1080), 1.0], [Vector2i(1280, 720), 1.0], [Vector2i(1280, 720), 1.4], [Vector2i(1920, 1080), 1.4]]
var _frames := {}

func _sizes_loop(i: int) -> void:
	if i >= VIEWS.size():
		return
	var v: Array = VIEWS[i]
	root.size = v[0]
	main._on_cmd("closeall")
	main._on_cmd("uiscale %s" % str(v[1]))
	q(func(): main._on_cmd("open colonists"), 6)
	q(func(): _measure(i, "colonists"), 4)
	q(func(): _top().set_tab("priorities"), 8)
	q(func(): _measure(i, "priorities"), 4)
	q(func(): _top().set_tab("visitors"), 8)
	q(func(): _measure(i, "visitors"), 4)
	q(func(): _sizes_done(i), 4)

func _measure(i: int, tab: String) -> void:
	var top = _top()
	var fr: Rect2 = top.frame.get_global_rect()
	var vpz: Vector2 = root.get_viewport().get_visible_rect().size
	var rows := 0.0
	for b in top.content.find_children("*", "Button", true, false):
		if (b as Button).theme_type_variation == "ListButton":
			rows = (b as Button).size.y
			break
	var scroll: ScrollContainer = top._scroll
	var hbar: bool = scroll.get_h_scroll_bar().visible and scroll.get_h_scroll_bar().max_value > scroll.get_h_scroll_bar().page + 1.0
	_frames["%d_%s" % [i, tab]] = {"fr": fr, "rows": rows, "hbar": hbar, "vp": vpz, "cm": top.content.get_combined_minimum_size().x, "sw": scroll.size.x}

func _sizes_done(i: int) -> void:
	var a: Dictionary = _frames["%d_colonists" % i]
	var b: Dictionary = _frames["%d_priorities" % i]
	var c: Dictionary = _frames["%d_visitors" % i]
	var tag: String = "%dx%d %d%%" % [int(VIEWS[i][0].x), int(VIEWS[i][0].y), int(float(VIEWS[i][1]) * 100.0)]
	check("%s: the window has one size on the three tabs" % tag, (a["fr"] as Rect2).is_equal_approx(b["fr"]) and (c["fr"] as Rect2).is_equal_approx(b["fr"]), "%s | %s | %s" % [str(a["fr"]), str(b["fr"]), str(c["fr"])])
	check("%s: Priorities rows are as tall as the other tabs'" % tag, absf(float(b["rows"]) - float(a["rows"])) < 0.5 and float(b["rows"]) > 0.0, "%s vs %s" % [str(b["rows"]), str(a["rows"])])
	check("%s: Priorities is inside the view" % tag, Rect2(Vector2.ZERO, b["vp"]).grow(0.5).encloses(b["fr"]), "%s in %s" % [str(b["fr"]), str(b["vp"])])
	check("%s: Priorities needs no sideways scroll" % tag, not bool(b["hbar"]), "content %.0f in scroll %.0f" % [float(b["cm"]), float(b["sw"])])
	if i + 1 >= VIEWS.size():
		q(func(): _behaviour_open(), 4)
	else:
		q(func(): _sizes_loop(i + 1), 4)

# ---------------------------------------------------------------- behaviour
func _behaviour_open() -> void:
	root.size = Vector2i(1920, 1080)
	main._on_cmd("closeall")
	main._on_cmd("uiscale 1")
	main._on_cmd("open colonists")
	q(func(): _top().set_tab("priorities"), 8)
	q(func(): _pick(), 6)
	q(func(): _behaviour_a(), 6)

func _pick() -> void:
	var sim = main.sim
	var ids: Array = []
	for k in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][k]
		if String(a["state"]) == "alive" and not main.hud.data.is_visitor(a):
			ids.append(int(k))
	ids.sort()
	aid = ids[0]
	bid = ids[1]
	# A clean start: no own values for the two, the colony default of construction is 2.
	sim.state["agents"][aid].erase("jobs")
	sim.state["agents"][bid].erase("jobs")
	sim.state["policies"]["priority"]["construction"] = 2
	_top()._prio_update()

func _behaviour_a() -> void:
	var v4 = main.hud.v4
	var sim = main.sim
	check("the table has a cell for each colonist and job, and a colony row", _cell(aid, "construction") != null and _cell(-1, "construction") != null and _top()._prows.size() >= 2)
	var cell: Button = _cell(aid, "construction")
	check("a colonist without own values follows the colony default (cell shows it)", not v4.is_own(aid, "construction") and cell.text == "2 Normal", cell.text)
	var tip_before: String = cell.tooltip_text
	var style_before: StyleBox = cell.get_theme_stylebox("normal")
	check("Reset is off while there is no own value", _reset_button(aid).disabled)
	_click(cell)
	q(func(): _after_click(tip_before, style_before), 4)

func _after_click(tip_before: String, style_before: StyleBox) -> void:
	var v4 = main.hud.v4
	var sim = main.sim
	var cell: Button = _cell(aid, "construction")
	var jobs: Dictionary = sim.state["agents"][aid].get("jobs", {})
	check("a click on the cell stores the own value in SIM (3 -> set_jobs)", int(jobs.get("construction", -1)) == 1 and jobs.size() == 1, str(jobs))
	check("the colony default is unchanged by it", int(sim.state["policies"]["priority"]["construction"]) == 2)
	check("v4.priority and is_own report it; the cell shows it", v4.priority(aid, "construction") == 1 and v4.is_own(aid, "construction") and cell.text == "1 Last", cell.text)
	var st: StyleBox = cell.get_theme_stylebox("normal")
	check("an own cell looks different from a cell that follows the colony (frame)", st is StyleBoxFlat and (st as StyleBoxFlat).border_width_left > 0 and not (_cell(aid, "food").get_theme_stylebox("normal") as StyleBoxFlat).border_width_left > 0)
	check("the tooltip says it is the own value", cell.tooltip_text.contains("Own value") and cell.tooltip_text != tip_before, cell.tooltip_text)
	check("another colonist's cell is unchanged", not v4.is_own(bid, "construction") and _cell(bid, "construction").text == "2 Normal")
	check("Reset turns on", not _reset_button(aid).disabled)
	# Click again: 1 -> never (0), then the colony default changes through a gold cell.
	_click(cell)
	q(func(): _after_second(), 4)

func _after_second() -> void:
	var v4 = main.hud.v4
	var sim = main.sim
	check("a second click steps on (1 -> never)", int(sim.state["agents"][aid]["jobs"]["construction"]) == 0 and _cell(aid, "construction").text == "– Never", str(sim.state["agents"][aid].get("jobs")))
	# SIM's score: an own 0 refuses the job whatever the colony says; an own 3 beats an own 1.
	var t := {"cat": "construction", "kind": "build", "bld": -1, "created": int(sim.state["tick"]), "role": "", "emergency": 0, "src": -1, "dst": -1, "picked": false}
	var s_never: float = sim.jobs.score(t, sim.state["agents"][aid])
	check("SIM: own never refuses the task although the colony default is 2", s_never <= -1e8, str(s_never))
	_click(_cell(aid, "construction"))
	q(func(): _after_third(t), 4)

func _after_third(t: Dictionary) -> void:
	var v4 = main.hud.v4
	var sim = main.sim
	check("a third click goes round to 3 first", int(sim.state["agents"][aid]["jobs"]["construction"]) == 3 and _cell(aid, "construction").text == "3 First")
	var s3: float = sim.jobs.score(t, sim.state["agents"][aid])
	var s2: float = sim.jobs.score(t, sim.state["agents"][bid])
	check("SIM: own 3 scores above the colony default 2 (the own value overrides)", s3 > s2 and s2 > 0.0, "%s vs %s" % [str(s3), str(s2)])
	# The colony default: a gold cell, by click. The own value stays; the follower shows the new value.
	var colony: Button = _cell(-1, "construction")
	_click(colony)
	q(func(): _after_colony(), 4)

func _after_colony() -> void:
	var v4 = main.hud.v4
	var sim = main.sim
	check("a gold cell changes the colony default (2 -> 1) in SIM", int(sim.state["policies"]["priority"]["construction"]) == 1, str(sim.state["policies"]["priority"]))
	check("the own value stays when the colony default changes", v4.priority(aid, "construction") == 3 and v4.is_own(aid, "construction"))
	check("a colonist who follows the colony shows the new default", v4.priority(bid, "construction") == 1 and not v4.is_own(bid, "construction") and _cell(bid, "construction").text == "1 Last", _cell(bid, "construction").text)
	_click(_reset_button(aid))
	q(func(): _after_reset(), 4)

func _after_reset() -> void:
	var v4 = main.hud.v4
	var sim = main.sim
	check("Reset (set_jobs clear) removes the own values", not sim.state["agents"][aid].has("jobs") and not v4.is_own(aid, "construction"))
	check("after Reset the cell follows the colony default again", v4.priority(aid, "construction") == 1 and _cell(aid, "construction").text == "1 Last")
	check("Reset is off again", _reset_button(aid).disabled)
	sim.state["policies"]["priority"]["construction"] = 2   # test set-up undone

