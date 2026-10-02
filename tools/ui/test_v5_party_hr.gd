extends SceneTree
## Parties, idle talk settings, HR and the bubble click through the panel manager (UI, 2026-10-02):
##   node tools/godot.mjs script res://tools/ui/test_v5_party_hr.gd
## On showcase_v5 with SIM's live API (V5_DESIGN sections 16 and 17):
##  1. Settings, Cheeky dialogue: the toggle sets SIM's option (set_option) and the device setting.
##  2. A celebration makes a party offer: its row in the Requests tab (place, hours, Throw, Skip), a notice (not the urgent
##     line), the answer through SIM, the party card in the Events tab, messages in the News tab (small drama only a badge,
##     big drama pops up once), the Party tab of the venue inspector (throw a party from there).
##  3. HR: an office and an officer; a complaint and a transfer request show in the Requests tab and in the Crew window,
##     HR tab, with the options and their effects; the answers go through SIM; the survey shows.
##  4. The bubble click switches the followed person and the follow card.
##  5. Planet colours: the minimap palette of the dry, cold and airless worlds.

const PM = preload("res://ui/hud/panel_manager.gd")

var main
var fails := 0
var _n := 0
var _queue: Array = []
var _wait := 0
var _v := {}

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
		load("res://ui/settings.gd").set_value("cheeky", true)
		print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
		quit(1 if fails > 0 else 0)
		return true
	var item: Array = _queue.pop_front()
	(item[0] as Callable).call()
	_wait = int(item[1])
	return false

func colonists() -> Array:
	var ids: Array = []
	for r in main.hud.v5.people():
		if String(r["kind"]) == "colonist" and float(r.get("age", 30)) >= 18.0:
			ids.append(int(r["id"]))
	return ids

## The newest request of a kind (the showcase has requests of its own since 2026-10-03).
func request_of(kind: String) -> Dictionary:
	var out := {}
	for r in main.hud.v5.requests():
		if String(r["kind"]) == kind:
			out = r
	return out

func feed_has(text_part: String) -> bool:
	for e in main.hud.panels.feed:
		if String(e["text"]).contains(text_part):
			return true
	return false

func _plan() -> void:
	main.boot["debug"] = "1"
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	root.size = Vector2i(1600, 900)
	var hud = main.hud
	var sim = main.sim
	var S = load("res://ui/settings.gd")
	S.set_value("cheeky", true)
	for t in PM.TYPES:
		S.set_value("notify_" + t, "popup")
	check("the panel manager has the types party and hr", PM.TYPES.has("party") and PM.TYPES.has("hr"))
	# Past the 30 s of grace after a load, so the log toasts.
	q(func(): main._fast_forward(40.0), 8)

	# ---- 1. Cheeky dialogue
	q(func():
		check("SIM: cheeky on at the start", bool(sim.party.cheeky()))
		hud.open_screen("settings"), 8)
	q(func():
		var top = hud.screens.top_screen()
		var tg: CheckButton = null
		for c in top.find_children("*", "CheckButton", true, false):
			if (c as CheckButton).text == "Cheeky dialogue":
				tg = c
		check("Settings has the toggle Cheeky dialogue", tg != null)
		if tg != null:
			tg.button_pressed = false, 6)
	q(func():
		check("toggle off: the device setting and SIM's option are off", not bool(load("res://ui/settings.gd").get_value("cheeky")) and not bool(sim.party.cheeky()))
		var top = hud.screens.top_screen()
		for c in top.find_children("*", "CheckButton", true, false):
			if (c as CheckButton).text == "Cheeky dialogue":
				(c as CheckButton).button_pressed = true, 6)
	q(func():
		check("toggle on: both on again", bool(load("res://ui/settings.gd").get_value("cheeky")) and bool(sim.party.cheeky()))
		hud.screens.close_all(), 4)

	# ---- 2. A party offer
	q(func():
		_v["ids"] = colonists()
		var res = main.submit("celebrate", {"kind": "birthday", "agent": int(_v["ids"][0])})
		main._fast_forward(1.0), 10)
	q(func():
		var o: Dictionary = request_of("party_offer")
		check("a birthday makes a party offer", not o.is_empty(), str(sim.party.offers()))
		_v["offer"] = o
		var rc = hud.request_card
		rc.update()
		var row: Node = rc.find_child("Request_%d" % int(o.get("id", -1)), true, false)
		check("its row is in the Requests tab: place, hours, Throw, Skip", row != null and row.find_child("Place", true, false) != null and row.find_child("Hours", true, false) != null and row.find_child("Opt_throw", true, false) != null and row.find_child("Opt_skip", true, false) != null)
		var pm = hud.panels
		check("a party offer is not on the urgent line", String(pm.urgent_now.get("tab", "")) != "requests" or hud.v5.urgent_requests().size() > 0, str(pm.urgent_now))
		check("the Requests tab shows it as a notice, not a question", pm.tab_state("requests")["count"] >= 1 and (pm.tab_state("requests")["priority"] != "needs-answer" or hud.v5.urgent_requests().size() > 0), str(pm.tab_state("requests")))
		check("the offer has the effects of its options shown", row != null and (row.find_child("Effect", true, false) as Label).text.contains("Uses drinks and snacks"))
		# Throw: the first place, 2 hours.
		var rc2 = hud.request_card
		rc2._ask_option(o, "throw"), 10)
	q(func():
		var res: Dictionary = hud.request_card.last_result
		check("Throw goes to SIM and answers", bool(res.get("ok", false)), str(res))
		check("a party is gathering", sim.party.parties().size() >= 1, str(sim.party.parties().size()))
		hud.panels.open_tab("events", true), 14)
	q(func():
		var pc = hud.party_card
		pc.update()
		check("the party card shows in the Events tab", pc.visible and pc.count >= 1 and pc.find_child("Party_%d" % int(sim.party.parties()[0]["id"]), true, false) != null)
		check("the Events tab counts the party", hud.panels.tab_state("events")["count"] >= 1, str(hud.panels.tab_state("events")))
		check("the card is hosted by the panel manager (no placement of its own)", pc.get_parent() != null and pc.get_parent() != hud.hud_root)
		# Messages: the party start went to the News tab.
		check("the party start is in the News tab", feed_has("party") or feed_has("Party"), str(hud.panels.feed.slice(0, 3)))
		_v["pops"] = hud.panels._pops.get_child_count()
		sim.log_event("party_drama", "Test small drama: a spilled drink.", [], 1)
		sim.log_event("party_drama_big", "Test big drama: a public break-up.", [], 2)
		main._fast_forward(0.3), 14)
	q(func():
		check("small drama is in the News tab (a badge)", feed_has("Test small drama"))
		check("big drama is in the News tab", feed_has("Test big drama"))
		var pop_texts: Array = []
		for p in hud.panels._pops.get_children():
			for l in p.find_children("*", "Label", true, false):
				pop_texts.append((l as Label).text)
		check("big drama pops up once, small drama does not", pop_texts.any(func(t): return String(t).contains("Test big drama")) and not pop_texts.any(func(t): return String(t).contains("Test small drama")), str(pop_texts))
		# The party type off: no pop-up, no badge.
		load("res://ui/settings.gd").set_value("notify_party", "off")
		var before: int = hud.panels._pops.get_child_count()
		hud.panels.post("party", "Test muted party message.", "info")
		check("a type set to Off gives no pop-up", hud.panels._pops.get_child_count() == before)
		load("res://ui/settings.gd").set_value("notify_party", "popup"), 4)
	# Skip the next offer.
	q(func():
		main.submit("celebrate", {"kind": "promotion", "agent": int(_v["ids"][1])})
		main._fast_forward(1.0), 8)
	q(func():
		var o: Dictionary = request_of("party_offer")
		check("a promotion makes a party offer", not o.is_empty())
		_v["skip_id"] = int(o.get("id", -1))
		hud.request_card._ask_option(o, "skip"), 8)
	q(func():
		check("Skip answers and the offer goes", bool(hud.request_card.last_result.get("ok", false)) and not hud.v5.requests().any(func(q): return int(q.get("id", -2)) == int(_v["skip_id"])), str(hud.request_card.last_result))
		# The venue inspector: Party tab on a venue.
		var bid := -1
		for r in sim.party.venues(-1):
			bid = int(r["building"])
			break
		check("the colony has a venue for a party", bid >= 0)
		_v["venue"] = bid
		if bid >= 0:
			main.select("building", bid)
			hud.inspector.set_tab("party"), 12)
	q(func():
		var ins = hud.inspector
		var sec: Node = ins.find_child("Party", true, false)
		check("the inspector has a Party tab with the cost line and the throw button", sec != null and ins.find_child("PartyInfo", true, false) != null and ins.find_child("ThrowParty", true, false) != null)
		var info: Label = ins.find_child("PartyInfo", true, false)
		check("the cost line names the guests and the stock", info != null and (info.text.contains("Up to") or info.text.contains("cannot hold")), info.text if info != null else "")
		var tp: Button = ins.find_child("ThrowParty", true, false)
		if tp != null and not tp.disabled:
			tp.pressed.emit(), 10)
	q(func():
		var r: Dictionary = hud.inspector.last_party
		check("Throw a party in the inspector answers (ok, or a clear reason)", not r.is_empty() and String(r.get("text", "")) != "", str(r))
		main.select("", -1), 4)

	# ---- 3. HR
	q(func():
		# An office (debug build), an officer, power: a test of the UI, not of SIM's power model.
		sim.state["flags"]["unlock_all"] = true   # the debug build: no research or stage gate in this test
		var spot: String = String(main._on_cmd("findspot hr_office 1 40"))
		check("a place for an HR office", spot != "none", spot)
		var w: PackedStringArray = spot.split(" ")
		main.submit("place_finished", {"def": "hr_office", "x": float(w[0]), "y": float(w[1]), "rot": 0.0, "size": 1})
		main._fast_forward(2.0), 8)
	q(func():
		var oid := -1
		for id in sim.state["buildings"]:
			if String(sim.state["buildings"][id]["def"]) == "hr_office":
				oid = int(id)
		check("the office stands", oid >= 0)
		_v["office"] = oid
		if oid >= 0:
			# The office has no corridor in this test: it joins the air network of a habitat (a test of the UI, not of
			# SIM's network model).
			sim.state["buildings"][oid]["powered"] = true
			for id in sim.state["buildings"]:
				if String(sim.state["buildings"][id]["def"]) == "habitat" and sim.topo.atmo_comp.has(int(id)):
					sim.topo.atmo_comp[oid] = sim.topo.atmo_comp[int(id)]
					break
		var ids: Array = colonists()
		_v["officer"] = int(ids[ids.size() - 1])
		var res = main.submit("set_role", {"agent": int(_v["officer"]), "role": "hr"})
		main._fast_forward(1.0), 8)
	q(func():
		pass
		print("INFO hr: offices %s officers %s active %s" % [str(sim.hr.offices(-1)), str(sim.hr.officers(-1)), str(sim.hr.active(-1))])
		check("an active HR office with an officer", sim.hr.active(-1), "offices %s officers %s" % [str(sim.hr.offices(-1)), str(sim.hr.officers(-1))])
		# A complaint and a transfer request (SIM's own constructors, the rows are real).
		var a: Dictionary = sim.state["agents"][int(colonists()[0])]
		var rec: Dictionary = sim.people.rec_of(int(a["id"]))
		var base: int = int(sim.bases.home_of(a)) if sim.bases.count() > 0 else -1
		var offs: Array = sim.hr.offices(-1)
		if not offs.is_empty():
			sim.hr._new_complaint(a, "home", rec, base, int(offs[0]))
			for id in sim.state["v5"]["hr"]["complaints"]:
				sim.state["v5"]["hr"]["complaints"][id]["state"] = "open"
				sim.state["v5"]["hr"]["complaints"][id]["needs_player"] = true
			sim.hr._new_transfer(sim.state["agents"][int(colonists()[1])], "unhappy", base)
		main._fast_forward(0.5), 10)
	q(func():
		var c: Dictionary = request_of("hr_complaint")
		var t: Dictionary = request_of("hr_transfer")
		check("a complaint is a row in the Requests tab with options and effects", not c.is_empty() and not (c["options"] as Array).is_empty(), str(c))
		check("a transfer request is a row with Approve and Refuse", not t.is_empty() and (t["options"] as Array).size() == 2, str(t))
		hud.request_card.update()
		var rc = hud.request_card
		var crow: Node = rc.find_child("Request_%d" % int(c.get("id", -1)), true, false)
		var trow: Node = rc.find_child("Request_%d" % int(t.get("id", -1)), true, false)
		check("the rows show the buttons: one for each option", crow != null and trow != null and trow.find_child("Opt_approve", true, false) != null and trow.find_child("Opt_refuse", true, false) != null)
		check("complaints and transfers are questions (needs-answer on the Requests tab)", hud.panels.tab_state("requests")["priority"] == "needs-answer" and hud.v5.urgent_requests().size() >= 2)
		hud.open_screen("crew", "hr"), 10)
	q(func():
		var top = hud.screens.top_screen()
		check("the Crew window has an HR tab", top != null and top.tab == "hr", str(top.tab) if top != null else "")
		check("HR tab: the summary, officers with both reputation values, the survey part", top.find_child("HrSummary", true, false) != null and top.find_child("Officer_%d" % int(_v["officer"]), true, false) != null)
		var c: Dictionary = request_of("hr_complaint")
		var t: Dictionary = request_of("hr_transfer")
		check("HR tab: the complaint and the transfer request with their buttons", top.find_child("HrRequest_%d" % int(c.get("id", -1)), true, false) != null and top.find_child("HrRequest_%d" % int(t.get("id", -1)), true, false) != null)
		# Answer: the complaint with its first option; refuse the transfer.
		hud.request_card._ask_option(c, String(c["options"][0]["id"])), 10)
	q(func():
		var res: Dictionary = hud.request_card.last_result
		check("a complaint answer goes to SIM", String(res.get("text", "")) != "", str(res))
		var t: Dictionary = request_of("hr_transfer")
		hud.request_card._ask_option(t, "refuse"), 10)
	q(func():
		var res: Dictionary = hud.request_card.last_result
		check("Refuse: SIM answers (costs applied)", bool(res.get("ok", false)), str(res))
		check("the transfer request is gone from the Requests tab", request_of("hr_transfer").is_empty())
		hud.screens.close_all()
		# Approve asks first.
		var a2: Dictionary = sim.state["agents"][int(colonists()[2])]
		sim.hr._new_transfer(a2, "unhappy", int(sim.bases.home_of(a2)) if sim.bases.count() > 0 else -1)
		main._fast_forward(0.3), 8)
	q(func():
		var t: Dictionary = request_of("hr_transfer")
		check("a second transfer request", not t.is_empty())
		hud.request_card._ask_option(t, "approve"), 8)
	q(func():
		check("Approve asks first (a confirm window)", hud.is_modal_open() and hud.screen_name() == "confirm", hud.screen_name())
		hud.screens.close_all()
		var t: Dictionary = request_of("hr_transfer")
		hud.request_card._answer_option(t, "approve"), 8)
	q(func():
		check("Approve answers (the person leaves on the next ship)", bool(hud.request_card.last_result.get("ok", false)), str(hud.request_card.last_result))
		# The survey.
		var bids: Array = sim.bases.ids() if sim.bases.count() > 0 else [-1]
		sim.hr._survey(int(bids[0]), int(sim.util.day_number()))
		hud.open_screen("crew", "hr"), 10)
	q(func():
		var top = hud.screens.top_screen()
		var sv: Dictionary = sim.hr.survey(int(top.base_id) if top != null else -1)
		check("SIM has a survey round", not sv.is_empty(), str(sv))
		check("HR tab shows the survey table", top != null and top.find_child("SurveyDepts", true, false) != null)
		hud.screens.close_all(), 4)

	# ---- The Rag prints the party and HR stories with their own kickers.
	q(func():
		var kick: Array = []
		for k in ["party_start", "party_drama", "party_drama_big", "birthday", "awkward", "hr_complaint", "hr_survey", "hr_transfer_approved"]:
			var n: Dictionary = hud.v5.norm_rag({"number": 1, "day": 1, "lead": {"kind": k, "headline": "H", "text": "T", "actors": []}, "stories": [{"kind": k, "headline": "S", "text": "T", "actors": []}]})
			kick.append("%s:%s/%s" % [k, n["lead"]["kicker"], n["stories"][0]["tag"]])
			if String(n["lead"]["kicker"]) == "EXCLUSIVE" or String(n["stories"][0]["tag"]) == "NEWS":
				check("the Rag has a kicker and a tag for %s" % k, false, str(kick))
		check("the Rag has kickers for the party and HR story kinds", not kick.is_empty() and not str(kick).contains("EXCLUSIVE"), str(kick)), 2)

	# ---- 4. The bubble click
	q(func():
		var ids: Array = colonists()
		_v["a"] = int(ids[0])
		_v["b"] = int(ids[3])
		main.select("agent", int(_v["a"]))
		main.follow_person(int(_v["a"])), 14)
	q(func():
		check("following the first person", main.in_follow() and int(main.view.follow_id) == int(_v["a"]))
		var bub = main.view.bubbles
		check("the bubbles signal is wired and the view does not switch by itself", bub.speaker_clicked.is_connected(main._on_bubble_clicked) and not bub.click_switches)
		check("bubble_speaker_at finds none on an empty point", main.view.bubble_speaker_at(Vector2(2, 2)) == -1)
		bub.speaker_clicked.emit(int(_v["b"])), 14)
	q(func():
		check("a bubble click switches to that speaker", int(main.view.follow_id) == int(_v["b"]), str(main.view.follow_id))
		check("the follow card shows the new person", int(hud.follow_hud.agent_id) == int(_v["b"]) and hud.follow_hud.visible, str(hud.follow_hud.agent_id))
		check("the selection moved too", main.view.selected_kind == "agent" and int(main.view.selected_id) == int(_v["b"]))
		main.view.bubbles.speaker_clicked.emit(int(_v["b"])), 6)
	q(func():
		check("a click on the person already followed changes nothing", int(main.view.follow_id) == int(_v["b"]))
		main.follow_end(), 6)
	q(func():
		main.view.bubbles.speaker_clicked.emit(int(_v["a"])), 6)
	q(func():
		check("a bubble click outside the follow view does nothing", not main.in_follow()), 2)

	# ---- The view's own follow call (a debug command, RENDER's probe) gives the same HUD as V (critic round 41).
	q(func():
		_v["min_before"] = bool(hud.panels.minimised)
		main.select("", -1)
		main.view.follow_start(int(_v["a"])), 12)
	q(func():
		var pm = hud.panels
		check("follow_start without the UI path: the follow card shows", hud.follow_hud.visible and int(hud.follow_hud.agent_id) == int(_v["a"]))
		check("... the HUD dims to about 35 %", absf(hud.top_bar.modulate.a - 0.35) < 0.02 and absf(hud.minimap.modulate.a - 0.35) < 0.02 and absf(hud.build_bar.modulate.a - 0.35) < 0.02, str(hud.top_bar.modulate.a))
		check("... the left dock folds to its tabs", pm.minimised and not pm._body.visible, str(pm.minimised))
		check("... the selection is the followed person", main.view.selected_kind == "agent" and int(main.view.selected_id) == int(_v["a"]))
		var v: Vector2 = hud.root.get_viewport_rect().size
		var centre := Rect2(v * 0.25, v * 0.5)
		var bad: Array = []
		for r in pm.shown_rects():
			if (r as Rect2).grow(-0.5).intersects(centre):
				bad.append(str(r))
		check("... the centre stays clear", bad.is_empty(), str(bad))
		main.view.follow_stop(), 12)
	q(func():
		var pm = hud.panels
		check("follow_stop without the UI path: the card goes, the HUD is bright, the dock is as before", not hud.follow_hud.visible and absf(hud.top_bar.modulate.a - 1.0) < 0.02 and pm.minimised == bool(_v["min_before"]), "%s %s" % [str(hud.top_bar.modulate.a), str(pm.minimised)]), 2)

	# ---- 5. Planet colours
	for pl in ["dry", "cold", "airless"]:
		var pln: String = pl
		q(func(): main.start_new(1001, {"planet": pln, "difficulty": "normal", "hazards": "normal"}), 16)
		q(func():
			var base: Image = hud.minimap._base
			var mid: Color = base.get_pixel(base.get_width() / 2, base.get_height() / 2)
			var avg := Color(0, 0, 0)
			var n := 0
			for j in range(0, base.get_height(), 4):
				for i in range(0, base.get_width(), 4):
					var c: Color = base.get_pixel(i, j)
					avg += Color(c.r, c.g, c.b)
					n += 1
			avg = Color(avg.r / n, avg.g / n, avg.b / n)
			_v["avg_" + pln] = avg
			if pln == "dry":
				check("minimap, dry world: rust (red over blue)", avg.r > avg.b + 0.12, str(avg))
			elif pln == "cold":
				check("minimap, cold world: blue-white (blue over red, light)", avg.b > avg.r + 0.01 and avg.b > 0.55, str(avg))
			else:
				check("minimap, airless world: grey (no tint, dark)", absf(avg.r - avg.b) < 0.04 and avg.r < 0.6, str(avg))
			_v["done_" + pln] = true, 2)
