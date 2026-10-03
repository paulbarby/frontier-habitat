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

func _tab_check(szc: Vector2i, scc: float, tb: String, attempt: int) -> void:
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
	# Follow-up 2026-10-01: pop-ups fold into the dock before its body gets under about 200 px; the tab
	# names show when the dock is 340 px or wider; the tabs take at most 2 rows (2026-10-02: one column of six
	# named tabs squeezed the body at 1600x900).
	var pm = main.hud.panels
	var want: float = minf(pm._pages[tb].get_combined_minimum_size().y, pm.BODY_KEEP - 12.0)
	if pm._body.visible and pm._body.size.y < want - 0.5 and pm._pops.get_child_count() > 0:
		bad.append("body %.0f px with %d pop-ups" % [pm._body.size.y, pm._pops.get_child_count()])
	var named: bool = String((pm._tab_btn["goals"] as Button).text).begins_with("Goals")
	if named != pm.names_shown or named != (pm._width >= pm.NAMES_W):
		bad.append("tab names %s at width %.0f" % [named, pm._width])
	if pm._width >= 370.0 and not named:
		bad.append("no tab names at width %.0f" % pm._width)
	var rows: int = int(ceil(float(pm._tab_btn.size()) / float(maxi(1, pm._tabbar.columns))))
	if rows > 2:
		var ws: Array = []
		for id2 in pm._tab_btn:
			ws.append("%s %.0f '%s'" % [id2, (pm._tab_btn[id2] as Control).get_combined_minimum_size().x, (pm._tab_btn[id2] as Button).text])
		bad.append("tabs in %d rows (%d columns), width %.0f named %s: %s" % [rows, pm._tabbar.columns, pm._width, str(pm.names_shown), ", ".join(ws)])
	if rects.size() < 2:
		bad.append("only %d rects shown" % rects.size())
	# The layout can lag the change by a frame (a pop-up that expires): look again, up to three times.
	if not bad.is_empty() and attempt < 3:
		q(func(): _tab_check(szc, scc, tb, attempt + 1), 3)
		return
	check("%dx%d at %d%%, tab %s: outside the centre, inside the view, off the minimap; body room; tab names" % [szc.x, szc.y, int(scc * 100.0), tb], bad.is_empty(), "; ".join(bad))

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
				q(func(): _tab_check(szc, scc, tb, 0), 1)
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
		# (The showcase has requests of its own: all of them go to Later.)
		for rq in main.hud.v5.requests():
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
	# Over the shoulder: the follow card holds the top left; the urgent line, pop-ups and dock start under it.
	for sz in [Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		var szf: Vector2i = sz
		q(func():
			root.size = szf
			main.hud.panels.open_tab("alerts", true)
			var fids: Array = []
			for r in main.hud.v5.people():
				if String(r["kind"]) == "colonist":
					fids.append(int(r["id"]))
			main.select("agent", int(fids[0]))
			main.follow_person(int(fids[0])), 20)
		q(func():
			var pm = main.hud.panels
			var fh: Control = main.hud.follow_hud
			var bad: Array = []
			if not fh.visible:
				bad.append("the follow card is not shown")
			var card: Rect2 = fh.get_global_rect()
			for r in pm.shown_rects():
				if (r as Rect2).grow(-0.5).intersects(card):
					bad.append("%s over the follow card %s" % [str(r), str(card)])
			check("%dx%d over the shoulder: nothing of the manager lies under the follow card" % [szf.x, szf.y], bad.is_empty(), "; ".join(bad))
			main.follow_end(), 6)
	# The floor selector lies left of the inspector, not under it.
	for sz2 in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		var szg: Vector2i = sz2
		q(func():
			root.size = szg
			var bid: int = -1
			for id in main.sim.state["buildings"]:
				if String(main.sim.state["buildings"][id]["def"]) == "super_dome":
					bid = int(id)
					break
			main.select("building", bid), 16)
		q(func():
			var fs: Control = main.hud.floor_sel
			var insp: Control = main.hud.inspector
			var bad: Array = []
			if not fs.visible or not insp.visible:
				bad.append("floor selector %s inspector %s" % [str(fs.visible), str(insp.visible)])
			elif fs.get_global_rect().grow(-0.5).intersects(insp.get_global_rect()):
				bad.append("%s over the inspector %s" % [str(fs.get_global_rect()), str(insp.get_global_rect())])
			check("%dx%d: the floor selector is not under the inspector" % [szg.x, szg.y], bad.is_empty(), "; ".join(bad))
			main.select("", -1), 4)
	# ---- The build palette keeps the centre of the view free (Paul, 2026-10-03): every category open, and while placing.
	var BB = load("res://ui/hud/build_bar.gd")
	for sz3 in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		for sc3 in [0.8, 1.0, 1.4]:
			var szh: Vector2i = sz3
			var sch: float = sc3
			q(func():
				root.size = szh
				root.content_scale_size = Vector2i.ZERO
				main._on_cmd("uiscale %s" % str(sch))
				main.cancel_tool()
				main.hud.build_bar.close_drawer(), 14)
			for t3 in BB.TABS:
				var tid: String = t3[0]
				q(func(): main.hud.build_bar.toggle_tab(tid), 8)
				q(func():
					var bb = main.hud.build_bar
					var v: Vector2 = vp()
					var centre := Rect2(v * 0.25, v * 0.5)
					var r: Rect2 = bb._drawer.get_global_rect()
					var bad: Array = []
					if not bb._drawer.visible:
						bad.append("drawer not shown")
					if r.grow(-0.5).intersects(centre):
						bad.append("drawer %s in the centre %s" % [str(r), str(centre)])
					if not Rect2(Vector2.ZERO, v).grow(0.5).encloses(r):
						bad.append("drawer %s outside the view %s" % [str(r), str(v)])
					if r.grow(-0.5).intersects(bb._tab_panel.get_global_rect()):
						bad.append("drawer over the tab row")
					if r.grow(-0.5).intersects(main.hud.minimap.get_global_rect()):
						bad.append("drawer over the minimap")
					var cut := false
					for c in bb._cards.values():
						if (c as Control).size.y < (c as Control).get_combined_minimum_size().y - 0.5:
							cut = true
					if cut:
						bad.append("a card is cut off (the drawer is lower than its cards)")
					check("%dx%d at %d%%, palette %s: under the centre zone, in the view, off the tab row and the map" % [szh.x, szh.y, int(sch * 100.0), tid], bad.is_empty(), "; ".join(bad)), 1)
			# Placing: the drawer folds; the hint is a small panel at the bottom, under the centre.
			q(func():
				main.hud.build_bar.toggle_tab("habitat"), 8)
			q(func():
				main.start_place("habitat", 1), 10)
			q(func():
				var bb = main.hud.build_bar
				var v: Vector2 = vp()
				var centre := Rect2(v * 0.25, v * 0.5)
				var hint: Control = main.hud.hint
				var bad: Array = []
				if bb._drawer.visible:
					bad.append("the drawer stays open while placing")
				if not hint.visible:
					bad.append("no placement hint")
				elif hint.get_global_rect().grow(-0.5).intersects(centre):
					bad.append("hint %s in the centre %s" % [str(hint.get_global_rect()), str(centre)])
				elif not Rect2(Vector2.ZERO, v).grow(0.5).encloses(hint.get_global_rect()):
					bad.append("hint %s outside the view" % str(hint.get_global_rect()))
				elif hint.get_global_rect().has_point(v * 0.5):
					bad.append("hint over the middle of the view")
				check("%dx%d at %d%%, placing: the palette folds, the hint is a bottom panel under the centre" % [szh.x, szh.y, int(sch * 100.0)], bad.is_empty(), "; ".join(bad))
				# The link tool and remove: the same panel.
				main.start_link("corridor"), 8)
			q(func():
				var v: Vector2 = vp()
				var centre := Rect2(v * 0.25, v * 0.5)
				var hint: Control = main.hud.hint
				check("%dx%d at %d%%, corridor tool: palette folded, hint under the centre" % [szh.x, szh.y, int(sch * 100.0)], not main.hud.build_bar._drawer.visible and hint.visible and not hint.get_global_rect().grow(-0.5).intersects(centre), str(hint.get_global_rect()))
				main.start_demolish()
				# The remove question is in the hint too (no window over the view).
				var bid: int = -1
				for id in main.sim.state["buildings"]:
					if String(main.sim.state["buildings"][id]["def"]) == "habitat":
						bid = int(id)
						break
				main.hud.ask_demolish(bid), 8)
			q(func():
				var v: Vector2 = vp()
				var centre := Rect2(v * 0.25, v * 0.5)
				var hint: Control = main.hud.hint
				check("%dx%d at %d%%, remove question: in the hint under the centre, no modal window" % [szh.x, szh.y, int(sch * 100.0)], hint.has_pending() and hint.visible and not main.hud.is_modal_open() and not hint.get_global_rect().grow(-0.5).intersects(centre), "%s %s" % [str(hint.has_pending()), str(hint.get_global_rect())])
				# Esc: the question goes first, then the tool; the palette comes back.
				main._unhandled_input(_esc()), 6)
			q(func():
				check("Esc ends the question and keeps the tool", not main.hud.hint.has_pending() and main.tool == "demolish")
				main._unhandled_input(_esc()), 8)
			q(func():
				check("Esc ends the tool: the palette is back", main.tool == "select" and main.hud.build_bar._drawer.visible)
				main.cancel_tool()
				main.hud.build_bar.close_drawer(), 4)
	# The wheel moves the palette strip sideways.
	q(func():
		root.size = Vector2i(1280, 720)
		main._on_cmd("uiscale 1")
		main.hud.build_bar.close_drawer(), 10)
	q(func(): main.hud.build_bar.toggle_tab("industry"), 10)
	q(func():
		var sc: ScrollContainer = main.hud.build_bar._cards_scroll
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		var before: int = sc.scroll_horizontal
		sc.gui_input.emit(ev)
		check("the mouse wheel moves the palette strip sideways", sc.scroll_horizontal > before, "%d -> %d" % [before, sc.scroll_horizontal])
		main.hud.build_bar.close_drawer(), 4)
	# The inspector (the Upgrade tab and the others) keeps out of the centre zone: it is as wide as the right quarter
	# allows (Paul, 2026-10-03), at every size and scale, and it stays inside the work area (not over the top bar).
	for sz4 in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		for sc4 in [0.8, 1.0, 1.4]:
			for pick in [["research_lab", "upgrade"], ["kitchen", "menu"], ["super_dome", "venues"], ["super_dome", "party"], ["habitat", "stats"]]:
				var szi: Vector2i = sz4
				var sci: float = sc4
				var pk: Array = pick
				q(func():
					root.size = szi
					root.content_scale_size = Vector2i.ZERO
					main._on_cmd("uiscale %s" % str(sci))
					main._on_cmd("select %s %s" % [pk[0], pk[1]]), 14)
				q(func():
					var v: Vector2 = vp()
					var centre := Rect2(v * 0.25, v * 0.5)
					var ins: Control = main.hud.inspector
					var r: Rect2 = ins.get_global_rect()
					var wa: Rect2 = main.hud.wm.work_area()
					var bad: Array = []
					if not ins.visible:
						bad.append("not shown")
					if r.grow(-0.5).intersects(centre):
						bad.append("%s in the centre %s" % [str(r), str(centre)])
					if r.position.y < wa.position.y - 0.5 or r.end.y > wa.end.y + 0.5:
						bad.append("%s outside the work area %s (over the top bar or the build bar)" % [str(r), str(wa)])
					check("%dx%d at %d%%, inspector %s/%s: outside the centre zone, inside the work area" % [szi.x, szi.y, int(sci * 100.0), pk[0], pk[1]], bad.is_empty(), "; ".join(bad))
					main.select("", -1), 2)
	q(func():
		root.size = Vector2i(1600, 900)
		main._on_cmd("uiscale 1"), 6)

func _esc() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	return ev
