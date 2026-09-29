extends SceneTree
## Version 5 people UI (V5_DESIGN §3, §5, §6, §7, §10), headless, on showcase_v4 (SIM v5 stubs):
##   node tools/godot.mjs script res://tools/ui/test_v5_people.gd
## Personnel file (three tabs, predictions, confirm, the order to SIM), follow HUD, Konami code and the
## egg in the codex, the Crew screen (org chart slots and a drop, housing, academy), the unrest meter and
## banner, the Civic palette with XXL / XXXXL labels and lock reasons, and every window inside the view.

const V5 = preload("res://ui/v5_data.gd")

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
	for b in n.find_children("*", "Button", true, false):
		t += (b as Button).text + " | "
	return t

func _inside(c: Control) -> bool:
	return Rect2(Vector2.ZERO, c.get_viewport_rect().size).encloses(c.get_global_rect().grow(-1.0))

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
			for r in hud.v5.people():
				if String(r["kind"]) == "colonist":
					pid = int(r["id"])
					break
			check("SIM people are live", hud.v5.live("people") and pid >= 0)
			main.select("agent", pid)
			hud.open_person(pid, "file")
			_step = 1
			_n = 0
		1:
			var t: String = _texts(hud.person)
			for part in ["SATISFACTION", "ATTITUDE", "SKILLS", "Rank", "Traits", "Home"]:
				check("file tab: %s" % part, t.contains(part))
			check("personnel file inside the view", _inside(hud.person), str(hud.person.get_global_rect()))
			var wa: Rect2 = hud.wm.work_area()
			var pr: Rect2 = hud.person.get_global_rect()
			check("the file opens in the inspector's place, top right (critic round 30)", absf(pr.end.x - wa.end.x) < 2.0 and absf(pr.position.y - wa.position.y) < 2.0, "%s in %s" % [str(pr), str(wa)])
			hud.inspector.refresh()
			check("the inspector hides while the file of its person shows", not hud.inspector.visible)
			var parts: Node = hud.person._body.find_child("SatParts", true, false)
			var vals: Array = []
			if parts != null:
				for r in parts.get_children():
					vals.append(float(r.get_meta("value")))
			var sorted_ok: bool = vals.size() == 9
			for i in range(1, vals.size()):
				if vals[i] < vals[i - 1]:
					sorted_ok = false
			check("satisfaction: 9 parts on one 0-100 track, worst first", sorted_ok, str(vals))
			hud.person.set_tab("social")
			_step = 2
			_n = 0
		2:
			check("social tab: the relationship web", hud.person._body.find_child("Web", true, false) != null)
			var hidden_ok := true
			for r in hud.v5.relations(pid, 10):
				if String(r["status"]) == "crush" and not bool(r.get("known", false)):
					for b in hud.person._body.find_children("*", "Button", true, false):
						if (b as Button).text == hud.v5.agent_name(int(r["other"])):
							hidden_ok = false
			check("an unknown crush is not shown", hidden_ok)
			hud.person.set_tab("review")
			_step = 3
			_n = 0
		3:
			var acts: Array = []
			for b in hud.person._body.find_children("*", "Button", true, false):
				if (b as Button).has_meta("action"):
					acts.append(String(b.get_meta("action")))
			check("review tab: every discipline action is a button", acts.size() == V5.ACTIONS.size(), str(acts))
			var all_pred := true
			for a in V5.ACTIONS + V5.REVIEWS:
				var p: Dictionary = hud.v5.predict(pid, String(a[0]))
				if not (p.has("attitude") and p.has("satisfaction")):
					all_pred = false
			check("every action and review has a predicted effect", all_pred)
			hud.person._ask("ration_cut", "Ration cut", "discipline")
			_step = 4
			_n = 0
		4:
			var top = hud.screens.top_screen()
			check("an action asks to confirm first, with the prediction", top != null and hud.screen_name() == "confirm" and _texts(top).contains("satisfaction"), hud.screen_name())
			var ct: String = _texts(top) if top != null else ""
			check("the confirm shows the effect on the person and on others", ct.contains("ON " + hud.v5.agent_name(pid).get_slice(" ", 0).to_upper()) and ct.contains("ON OTHERS"), ct.left(240))
			var fair_ok: bool = float(hud.v5.person(pid)["attitude"]["value"]) < 0.0 or ct.contains("UNFAIR")
			check("a punishment of a person with a fair or good attitude warns: UNFAIR", fair_ok, ct.left(300))
			if top != null and top.has_method("_yes"):
				top._yes()
			elif top != null:
				for b in top.find_children("*", "Button", true, false):
					if (b as Button).text == "Ration cut":
						(b as Button).pressed.emit()
			_step = 5
			_n = 0
		5:
			var lr: Dictionary = hud.person.last_result
			check("the order goes to SIM; SIM's answer (or 'not yet') is shown", not lr.is_empty() and (bool(lr.get("ok", false)) or String(lr.get("code", "")) == "not_yet"), str(lr))
			hud.person.visible = false
			main.select("agent", pid)
			# Follow HUD (the camera itself is RENDER's; headless has no drawn people, so the card is shown directly).
			hud.follow_changed(pid)
			_step = 6
			_n = 0
		6:
			var t: String = _texts(hud.follow_hud)
			check("follow HUD: name, satisfaction and the buttons", hud.follow_hud.visible and t.contains(hud.v5.agent_name(pid).to_upper()) and t.contains("Satisfaction") and t.contains("Exit") and t.contains("Next"), t.left(200))
			check("follow HUD dims the rest of the HUD", hud.minimap.modulate.a < 0.5 and hud.time_panel.modulate.a > 0.9)
			var nd: Node = hud.follow_hud.find_child("Needs", true, false)
			check("the follow card has the inspector's needs (health, fed, water, rested)", nd != null and nd.get_child_count() == 4)
			hud.toast("Test toast in the follow view.", "info")
			hud.toasts._process(0.0)
			check("toasts go to the top edge while following", absf(hud.toasts._box.offset_top - 8.0) < 0.5, str(hud.toasts._box.offset_top))
			hud.inspector.refresh()
			check("the inspector stays hidden in the follow view", not hud.inspector.visible)
			hud.follow_changed(-1)
			check("exit brings the HUD back", not hud.follow_hud.visible and hud.minimap.modulate.a > 0.99)
			# Konami code
			var ok := false
			for k in main.KONAMI:
				ok = main._konami_key(k)
			check("the Konami code is read (↑↑↓↓←→←→BA)", ok)
			hud.egg_found("dance", pid)
			var cx = load("res://ui/codex.gd").new(hud)
			var names: Array = cx.entries("society").map(func(e): return String(e["name"]))
			check("a found egg is in the codex (People tab), the others stay hidden", names.has("Dance Floor Director") and not names.has("The dev in the dome"), str(names))
			check("the codex has ranks, skills, discipline and unrest", names.has("Ranks") and names.has("Skills") and names.has("Reviews and discipline") and names.has("Unrest"))
			main._on_cmd("open crew")
			_step = 7
			_n = 0
		7:
			var top = hud.screens.top_screen()
			check("crew screen: org chart with the commander and 5 departments", hud.screen_name() == "crew" and top.slots.size() == 11, "%d slots" % top.slots.size())
			check("crew: a mood face per person", top.find_children("Mood", "", true, false).size() >= 5, "%d faces" % top.find_children("Mood", "", true, false).size())
			var cmdr: int = int(top.slots[0]["holder"])
			check("SIM's commander is in the commander slot", cmdr >= 0 and String(sim.people.rank(sim.state["agents"][cmdr])["rank"]) == "commander")
			top.dropped(pid, {"rank": "captain", "department": "food"})
			_step = 8
			_n = 0
		8:
			check("a drop on a slot asks to confirm", hud.screen_name() == "confirm" and _texts(hud.screens.top_screen()).contains("Captain of Food"))
			hud.close_modal()
			hud.screens.top_screen().set_tab("housing")
			_step = 9
			_n = 0
		9:
			var t: String = _texts(hud.screens.top_screen())
			check("housing tab: homes with beds", t.contains("beds") and (t.contains("DORM") or t.contains("UNIT")), t.left(200))
			hud.screens.top_screen().set_tab("academy")
			_step = 10
			_n = 0
		10:
			var t: String = _texts(hud.screens.top_screen())
			check("academy tab: the enrolment form", t.contains("Enrol"))
			check("academy tab: the crew's skill table", hud.screens.top_screen().find_child("SkillTable", true, false) != null)
			check("the crew screen stays inside the view", _inside(hud.screens.top_screen().frame))
			main._on_cmd("close")
			# Unrest: every colonist unhappy (test set-up) raises it; the meter and the banner follow.
			for aid in sim.state["agents"]:
				var a: Dictionary = sim.state["agents"][aid]
				a["morale"] = 0.0
				a["fatigue"] = 100.0
				a["health"] = 30.0
			hud.top_bar.refresh()
			hud.unrest_banner._update()
			var calm_stage: String = String(hud.v5.unrest(-1)["stage"])
			print("NOTE unrest from SIM with every colonist unhappy: ", hud.v5.unrest(-1))
			main._on_cmd("unrest riot")   # the banner at a loud stage (UI view only)
			_step = 11
			_n = 0
		11:
			var u: Dictionary = hud.v5.unrest(-1)
			check("unrest meter in the top bar", hud.top_bar._k["unrest"].visible)
			var loud: bool = String(u["stage"]) in ["protest", "strike", "riot"]
			check("the banner shows at protest and above (stage %s, %d)" % [u["stage"], int(u["value"])], hud.unrest_banner.visible == loud)
			if loud:
				var resp: Array = []
				for b in hud.unrest_banner.find_children("*", "Button", true, false):
					if (b as Button).has_meta("response"):
						resp.append(b.get_meta("response"))
				check("the banner has the 7 responses", resp.size() == 7)
				var effs: int = 0
				for l in hud.unrest_banner.find_children("*", "Label", true, false):
					if (l as Label).has_meta("effect") and (l as Label).text != "":
						effs += 1
				check("each response shows its effect (critic round 30)", effs == 7, "%d" % effs)
				check("a riot shows the damage and injuries line and a red frame", String(u["stage"]) != "riot" or (hud.unrest_banner._damage.visible and hud.unrest_banner._style.bg_color.r > hud.unrest_banner._style.bg_color.g * 3.0))
				check("the banner stays inside the view", _inside(hud.unrest_banner))
			# Palette
			hud.build_bar.toggle_tab("civic")
			_step = 12
			_n = 0
		12:
			var cards: Dictionary = hud.build_bar._cards
			check("Civic tab: security office, jail, super dome", cards.has("security_office") and cards.has("jail") and cards.has("super_dome"), str(cards.keys()))
			var t: String = _texts(cards.get("super_dome", Control.new()))
			check("super dome card: XXXXL label and its lock reason", t.contains("XXXXL") and cards["super_dome"].locked and String(cards["super_dome"].lock_text) != "", t.left(160))
			hud.build_bar.toggle_tab("habitat")
			_step = 13
			_n = 0
		13:
			var cards: Dictionary = hud.build_bar._cards
			check("apartment block card: XXL", cards.has("apartment_block") and _texts(cards["apartment_block"]).contains("XXL"))
			main._on_cmd("unrest off")
			var Profile = load("res://ui/profile.gd")
			Profile.data().erase("eggs")   # the test's egg does not stay on this device
			Profile._save()
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
