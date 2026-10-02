extends SceneTree
## Version 5 society UI on SIM's stored relations (sim/relations.gd), on showcase_v4:
##   node tools/godot.mjs script res://tools/ui/test_v5_social.gd
## 1. A request "leave with a ship" (SIM's shape, written into state.v5.requests as test set-up)
##    shows the request card; Refuse goes through the card to SIM (command answer_request); SIM's
##    answer is shown, the card hides, the person's record has the effect, and the personnel file
##    History shows it. Let go asks to confirm first; with no ship SIM refuses and says so.
## 2. The card sits under the unrest banner, inside the view, and does not overlap it.
## 3. Log events of people's lives (wedding, affair, break-up, request) make toasts.
## 4. Debug `request` shows the card (UI view only), `request off` hides it.
## 5. The help has the topics "love" and "requests".

var main
var fails := 0
var _n := 0
var _step := 0
var pid := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _texts(n: Node) -> String:
	var t := ""
	for l in n.find_children("*", "Label", true, false):
		t += (l as Label).text + " | "
	return t

## Presses the confirm dialog's yes button (the one that is not Back).
func yes() -> bool:
	var top = main.hud.screens.top_screen()
	if top == null or main.hud.screen_name() != "confirm":
		return false
	for b in top.find_children("*", "Button", true, false):
		var t: String = (b as Button).text
		if t != "" and t != "Back" and t != "OK":
			(b as Button).pressed.emit()
			return true
	return false

func _request(id: int, agent: int) -> void:
	# Test set-up: SIM's request shape (sim/relations.gd _fling_day), ship -1 (no ship).
	var reqs: Dictionary = main.sim.relations._w()["requests"]
	reqs[id] = {"id": id, "kind": "leave_with_ship", "agent": agent, "other": -1, "ship": -1, "tick": int(main.sim.state["tick"]),
		"text": "%s wants to leave with a visitor on the ship. Let them go?" % main.hud.v5.agent_name(agent)}

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
			main._on_cmd("speed 0")
			main.leave_title()   # the HUD shows (headless stays on the title after an import)
			for r in hud.v5.people():
				if String(r["kind"]) == "colonist":
					pid = int(r["id"])
					break
			check("SIM takes the order 'answer_request' (sim.relations.cmd_answer_request)", hud.v5.live_command("answer_request"))
			# (The showcase has party offers and HR requests of its own since 2026-10-03: the card shows exactly when a request is open.)
			hud.request_card.update()
			check("the request card shows exactly when a request is open", hud.request_card.visible == (hud.v5.requests().size() > 0))
			_request(1, pid)
			hud.request_card.update()
			hud.panels.open_tab("requests", true)   # 2026-10-01: requests live in the dock's Requests tab
			_step = 1
			_n = 0
		1:
			var rc = hud.request_card
			var t: String = _texts(rc)
			check("a request shows the card: kind, name, SIM's text, the refuse effect", rc.visible and t.contains("LEAVE WITH A SHIP") and t.contains(hud.v5.agent_name(pid).to_upper()) and t.contains("wants to leave") and t.contains("fall for 3 days"), t.left(300))
			var r: Rect2 = rc.get_global_rect()
			check("the card is inside the view", Rect2(Vector2.ZERO, hud.root.get_viewport_rect().size).grow(0.5).encloses(r), str(r))
			rc._answer("refuse")
			_step = 2
			_n = 0
		2:
			var rc = hud.request_card
			check("refuse: SIM answers ok (they stay)", bool(rc.last_result.get("ok", false)) and String(rc.last_result.get("text", "")).contains("stays"), str(rc.last_result))
			check("refuse: the request is gone and the card hides", hud.v5.requests().is_empty() and not rc.visible)
			var mods: Array = hud.v5.record(pid).get("mods", [])
			check("refuse: SIM's effect on the person (Not allowed to leave)", mods.any(func(m): return String(m.get("text", "")) == "Not allowed to leave"), str(mods))
			hud.open_person(pid, "file")
			_step = 3
			_n = 0
		3:
			var hs: Node = hud.person._body.find_child("History", true, false)
			var t: String = _texts(hs) if hs != null else ""
			check("personnel file: History shows the effect with its numbers and the time left", hs != null and t.contains("Not allowed to leave") and t.contains("satisfaction -20") and t.contains("left"), t.left(300))
			check("personnel file: History shows the history line", t.contains("Was not allowed to leave with the ship."), t.left(300))
			hud.person.visible = false
			# Let go: confirm first; with no ship SIM refuses and the card says so.
			_request(2, pid)
			hud.request_card.update()
			hud.request_card._ask_allow()
			check("let go asks to confirm first", hud.screen_name() == "confirm")
			check("confirm: yes", yes())
			_step = 4
			_n = 0
		4:
			var rc = hud.request_card
			check("let go without a ship: SIM refuses (The ship has gone.) and the card shows it", not bool(rc.last_result.get("ok", true)) and String(rc.last_result.get("text", "")).contains("ship has gone"), str(rc.last_result))
			check("the person is still a colonist", String(sim.state["agents"][pid].get("kind", "")) != "visitor")
			# The card under the unrest banner (protest), no overlap.
			_request(3, pid)
			main._on_cmd("unrest protest")
			hud.request_card.update()
			_step = 5
			_n = 0
		5:
			# 2026-10-01 (docs/UI_PANELS.md): both are cards in the left dock; the urgent line names the request.
			var v: Vector2 = hud.root.get_viewport_rect().size
			var centre := Rect2(v * 0.25, v * 0.5)
			check("a request and a protest: the urgent line shows the request first", String(hud.panels.urgent_now.get("tab", "")) == "requests" or String(hud.panels.urgent().get("tab", "")) == "requests", str(hud.panels.urgent()))
			check("a request and a protest: the Events and Requests tabs count them", int(hud.panels.tab_state("events")["count"]) >= 1 and int(hud.panels.tab_state("requests")["count"]) >= 1)
			var ok := true
			for r in hud.panels.shown_rects():
				ok = ok and not (r as Rect2).grow(-0.5).intersects(centre)
			check("a request and a protest: nothing in the centre of the view", ok, str(hud.panels.shown_rects()))
			main._on_cmd("unrest off")
			sim.relations._w()["requests"].clear()
			hud.request_card.update()
			# Toasts for the moments of people's lives (test set-up: the grace time after a load is over, not on the title).
			hud.watchers._grace_tick = 0
			main.on_title = false   # headless: the title flag stays on after an import (it silences toasts)
			var ids: Array = [pid, int(hud.v5.people()[1]["id"])]
			for c in [["wedding", "Test couple got married!"], ["affair", "Scandal! Test cheat was seen."], ["breakup", "Test pair broke up."], ["defect_request", "Test asks to leave."]]:
				sim.log_event(c[0], c[1], ids, 1)
			_step = 6
			_n = 0
		6:
			if _n < 40:
				return false
			var t: String = _texts(hud.toasts)
			var ft: String = " | ".join(hud.panels.feed.map(func(x): return String(x["text"])))
			for c in ["got married", "Scandal!", "broke up", "asks to leave"]:
				check("a message for '%s' (News; the newest 3 pop up)" % c, ft.contains(c), ft.left(200))
			var r1: String = main._on_cmd("request")
			check("debug request shows the card", hud.request_card.visible and r1.begins_with("request for"), r1)
			main._on_cmd("request off")
			# (A real party offer or HR request can show the card now: only the debug rows must be gone.)
			check("debug request off hides it", hud.v5.request_override.is_empty() and not hud.v5.requests().any(func(q): return String(q.get("kind", "")) == "leave_with_ship" and int(q.get("id", -1)) == 0) and (not hud.request_card.visible or hud.v5.requests().size() > 0))
			var ids2: Array = []
			for tp in load("res://ui/v5_help.gd").TOPICS:
				ids2.append(String(tp[0]))
			check("help: topics love, requests, families, venues", ids2.has("love") and ids2.has("requests") and ids2.has("families") and ids2.has("venues"), str(ids2))
			# 6. A shared-home request: its own words; Try again needs no confirm; Keep apart.
			var other: int = int(hud.v5.people()[1]["id"])
			sim.relations.add_request("shared_home", sim.state["agents"][pid], sim.state["agents"][other], "Test pair want a shared home.")
			hud.request_card.update()
			var t2: String = _texts(hud.request_card)
			check("shared home: the card says A HOME FOR TWO, Try again, Keep apart", t2.contains("A HOME FOR TWO") and hud.request_card._allow.text == "Try again" and hud.request_card._refuse.text == "Keep apart", t2.left(300))
			hud.request_card._answer("refuse")
			check("shared home, keep apart: SIM answers (they stay apart)", String(hud.request_card.last_result.get("text", "")).contains("apart"), str(hud.request_card.last_result))
			# 7. Crew window, Security tab.
			hud.open_screen("crew")
			_step = 7
			_n = 0
		7:
			var top = hud.screens.top_screen()
			top.set_tab("security")
			_step = 8
			_n = 0
		8:
			var top = hud.screens.top_screen()
			var sm: Node = top.content.find_child("SecuritySummary", true, false)
			var t: String = _texts(top.content)
			check("crew security tab: officers against the target, cells, fights, prisoners", sm != null and t.contains("wanted") and t.contains("FIGHTS NOW") and t.contains("PRISONERS"), t.left(300))
			# Change job to security officer: SIM's answer (refused without the skill, or ok).
			var who: OptionButton = top.content.find_child("JobWho", true, false)
			check("crew security tab: the job change form", who != null and top.content.find_child("JobRole", true, false) != null)
			for b in top.content.find_children("*", "Button", true, false):
				if (b as Button).text == "Change job":
					(b as Button).pressed.emit()
			check("change job: confirm first", yes())
			_step = 9
			_n = 0
		9:
			var lr: Dictionary = hud.screens.top_screen().last_result
			check("change job: SIM answers (set_role)", lr.has("code") and String(lr.get("code", "")) != "not_yet" and String(lr.get("text", "")) != "", str(lr))
			hud.close_modal()
			# 8. A retail module (test set-up: SIM's debug place_finished) shows the Venues tab.
			sim.state["options"]["debug"] = true
			var sp: String = main._on_cmd("findspot retail 1 40")
			var ok := false
			if sp != "none":
				var xy: PackedStringArray = sp.split(" ")
				var r: Dictionary = sim.debug.run("place_finished", {"def": "retail", "x": float(xy[0]), "y": float(xy[1]), "size": 1})
				ok = bool(r.get("ok", false))
				if ok:
					main.select("building", int(r["id"]))
					hud.inspector.set_tab("venues")
			check("test set-up: a finished retail module", ok, sp)
			_step = 10
			_n = 0
		10:
			var vs: Node = hud.inspector.find_child("Venues", true, false)
			var t: String = _texts(hud.inspector)
			check("inspector: the Venues tab lists each venue, open or closed with the reason", vs != null and (t.contains("CLOSED") or t.contains("OPEN")), t.left(400))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
			return true
	return false
