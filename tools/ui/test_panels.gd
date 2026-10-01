extends SceneTree
## The panel manager (docs/UI_PANELS.md; Paul, 2026-10-01), headless, on showcase_v5:
##   node tools/godot.mjs script res://tools/ui/test_panels.gd
## At 1920x1080 and 1280x720, interface scale 80, 100 and 140 %: every message type posted, a request,
## unrest (protest), a medal and a chapter. Asserts: nothing the manager shows (urgent line, pop-ups,
## dock) lies in the centre zone (the middle half of the width and of the height); all inside the
## view; the dock never over the minimap. Then the controls: dock minimise / close / pin, key L, a tab's
## mute, Settings modes (Badge only, Off), a card's minimise / close, and nothing lost while minimised
## (the News badge counts every message).

const PM = preload("res://ui/hud/panel_manager.gd")

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var _saved_modes := {}

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func q(c: Callable, frames: int = 4) -> void:
	_queue.append([c, frames])

func vp() -> Vector2:
	return main.hud.root.get_viewport_rect().size

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
		for t in _saved_modes:
			load("res://ui/settings.gd").set_value("notify_" + t, _saved_modes[t])
		load("res://ui/settings.gd").set_value("dock_open", true)
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func _post_all() -> void:
	var pm = main.hud.panels
	for t in PM.TYPES:
		pm.post(t, "Test message of type %s: a line long enough to wrap onto a second line in the dock." % t, "warning" if t in ["alert", "hazard"] else "info")
	main._on_cmd("award first_breath")
	main._on_cmd("chapter 2")

func _plan() -> void:
	var S = load("res://ui/settings.gd")
	for t in PM.TYPES:
		_saved_modes[t] = S.get_value("notify_" + t)
		S.set_value("notify_" + t, "popup")
	S.set_value("dock_open", true)
	main.boot["debug"] = "1"
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()   # the HUD shows, so the containers lay out (headless stays on the title after an import)
	var sim = main.sim
	# A request (SIM's shape) and a protest (the UI's debug view): the urgent line and the Events tab.
	var ids: Array = []
	for r in main.hud.v5.people():
		if String(r["kind"]) == "colonist":
			ids.append(int(r["id"]))
	sim.relations.add_request("shared_home", sim.state["agents"][ids[0]], sim.state["agents"][ids[1]], "Test pair want a shared home.")
	main._on_cmd("unrest protest")
	for sz in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		for sc in [0.8, 1.0, 1.4]:
			var szc: Vector2i = sz
			var scc: float = sc
			q(func():
				root.size = szc
				root.content_scale_size = Vector2i.ZERO
				main._on_cmd("uiscale %s" % str(scc))
				_post_all(), 12)
			for tab in ["goals", "alerts", "events", "traffic", "requests", "news"]:
				var tb: String = tab
				q(func(): main.hud.panels.open_tab(tb, true), 6)
				q(func():
					var v: Vector2 = vp()
					var centre := Rect2(v * 0.25, v * 0.5)
					var bad: Array = []
					var rects: Array = main.hud.panels.shown_rects()
					for r in rects:
						if (r as Rect2).grow(-0.5).intersects(centre):
							bad.append("%s in the centre %s" % [str(r), str(centre)])
						if not Rect2(Vector2.ZERO, v).grow(0.5).encloses(r):
							bad.append("%s outside the view %s" % [str(r), str(v)])
					var mm: Rect2 = main.hud.minimap.get_global_rect()
					if main.hud.panels._dock.get_global_rect().grow(-0.5).intersects(mm):
						bad.append("dock %s over the minimap %s" % [str(main.hud.panels._dock.get_global_rect()), str(mm)])
					if rects.size() < 2:
						bad.append("only %d rects shown" % rects.size())
					check("%dx%d at %d%%, tab %s: urgent line, pop-ups and dock outside the centre, inside the view, off the minimap" % [szc.x, szc.y, int(scc * 100.0), tb], bad.is_empty(), "; ".join(bad)), 1)
	q(func():
		root.size = Vector2i(1600, 900)
		main._on_cmd("uiscale 1"), 10)
	# The urgent line: the request (needs an answer) first; it opens the Requests tab.
	q(func():
		var pm = main.hud.panels
		check("urgent line: the request first", pm._urgent.visible and String(pm.urgent_now.get("tab", "")) == "requests" and String(pm.urgent_now.get("text", "")).begins_with("REQUEST"), str(pm.urgent_now))
		check("the Requests tab badge counts the request (needs an answer)", pm.tab_state("requests")["count"] >= 1 and pm.tab_state("requests")["priority"] == "needs-answer", str(pm.tab_state("requests")))
		check("the Events tab counts the protest", pm.tab_state("events")["count"] >= 1, str(pm.tab_state("events")))
		# Later: off the urgent line, still in the tab.
		var rq: Dictionary = main.hud.request_card.request
		main.hud.request_card.later[int(rq["id"])] = true, 24)
	q(func():
		var pm = main.hud.panels
		check("Later: the request leaves the urgent line, stays in the Requests tab", String(pm.urgent_now.get("tab", "")) != "requests" and pm.tab_state("requests")["count"] >= 1, str(pm.urgent_now))
		main.hud.request_card.later.clear()
		# Dock minimise: the tabs stay, the body goes; badges unchanged.
		pm.open_tab("news", true), 4)
	q(func():
		var pm = main.hud.panels
		pm.minimise_dock(true)
		for i in 3:
			pm.post("people", "Minimised test message %d." % i, "info"), 6)
	q(func():
		var pm = main.hud.panels
		check("dock minimise: tabs show, the body is hidden", pm._dock.visible and not pm._body.visible)
		check("nothing lost while minimised: the News badge counts the 3 new messages", int(pm.tab_state("news")["count"]) >= 3, str(pm.tab_state("news")))
		pm.minimise_dock(false)
		# Close and key L.
		pm.toggle_dock(false), 4)
	q(func():
		var pm = main.hud.panels
		check("dock close: only the urgent line and pop-ups stay", not pm._dock.visible and pm._urgent.visible)
		main._on_cmd("unrest off")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_L
		ev.pressed = true
		main._unhandled_input(ev), 4)
	q(func():
		check("key L opens the dock again", main.hud.panels._dock.visible)
		# A window over the dock folds it, unless the dock is pinned.
		main.hud.rag.visible = true
		main._on_cmd("drag rag 40 160"), 8)
	q(func():
		var pm = main.hud.panels
		var over: bool = main.hud.rag.get_global_rect().intersects(pm._dock.get_global_rect())
		check("a window over the dock folds it to its tabs", (not over) or pm.collapsed, "over=%s collapsed=%s" % [over, pm.collapsed])
		pm.pin_dock(true), 8)
	q(func():
		var pm = main.hud.panels
		check("a pinned dock does not fold under a window", not pm.collapsed and pm._body.visible)
		pm.pin_dock(false)
		main.hud.rag.visible = false
		main.hud.wm.forget("rag")
		# A tab's mute: its types to Badge only; a new message adds a badge, no pop-up.
		pm.open_tab("traffic", true), 6)
	q(func():
		var pm = main.hud.panels
		pm._toggle_mute()
		check("tab mute: Traffic to Badge only", pm.mode("traffic") == "badge")
		pm.post("traffic", "A muted traffic message.", "info"), 4)
	q(func():
		var pm = main.hud.panels
		check("muted type: no pop-up, the message is in News", not pm.popup_texts().has("A muted traffic message.") and pm.feed.any(func(e): return String(e["text"]) == "A muted traffic message."), str(pm.popup_texts()))
		pm._toggle_mute()
		check("tab mute again: Traffic pops up", pm.mode("traffic") == "popup")
		# Settings Off: no pop-up, no badge.
		pm.set_mode("people", "off")
		pm.open_tab("goals", true)
		for e in pm.feed:
			e["seen"] = true
		pm.post("people", "An off people message.", "info"), 4)
	q(func():
		var pm = main.hud.panels
		check("type Off: no pop-up and no badge", not pm.popup_texts().has("An off people message.") and int(pm.tab_state("news")["count"]) == 0, "%s %s" % [str(pm.popup_texts()), str(pm.tab_state("news"))])
		pm.set_mode("people", "popup")
		# A card: minimise and close.
		pm.open_tab("goals", true), 6)
	q(func():
		var pm = main.hud.panels
		var rec: Dictionary = {}
		for r in pm._cards:
			if r["host"] == main.hud.goals:
				rec = r
		pm._card_min(rec, true)
		pm._layout_card(rec)
		check("card minimise: its line stays, its body goes", (rec["root"] as Control).visible and not (rec["slot"] as Control).visible)
		pm._card_min(rec, false)
		pm._card_close(rec)
		pm._layout_card(rec)
		check("card close: hidden", not (rec["root"] as Control).visible)
		pm.open_tab("goals", true)
		pm._layout_card(rec)
		check("open the tab again: the card is back", (rec["root"] as Control).visible), 4)
	q(func():
		# Settings: the Notifications section lists every type.
		main.hud.open_screen("settings"), 8)
	q(func():
		var top = main.hud.screens.top_screen()
		var n := 0
		for t in PM.TYPES:
			if top.content.find_child("Notify_" + t, true, false) != null:
				n += 1
		check("Settings, Notifications: a choice for every type", n == PM.TYPES.size(), "%d of %d" % [n, PM.TYPES.size()])
		main.hud.close_modal(), 4)
