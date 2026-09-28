extends SceneTree
## Every lock explained (Paul, 2026-09-28: "This structure is not unlocked yet." with no hint), headless:
##   node tools/godot.mjs script res://tools/ui/test_locks.gd
## Every locked build card shows a one-line reason and a full tooltip text; the UI agrees with SIM's
## placement check; the placement hint, the codex ("How to unlock") and the advisor (a needed item
## whose maker is locked) say how to unlock.

const Advisor = preload("res://ui/advisor.gd")

var main
var fails := 0
var _n := 0
var _step := 0
var _tab := 0
var _cards := 0
var _locked := 0
var _bad: Array = []

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _texts(n: Node) -> String:
	var txt := ""
	for l in n.find_children("*", "Label", true, false):
		txt += (l as Label).text + " | "
	return txt

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	var BB = load("res://ui/hud/build_bar.gd")
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.start_new(1001, {"scenario": "frontier"})
			main._on_cmd("speed 0")
			_step = 1
			_n = 0
		1:
			# Every tab of the build bar, every card.
			if _tab < BB.TABS.size():
				hud.build_bar.toggle_tab(String(BB.TABS[_tab][0]))
				hud.build_bar.refresh()
				var lander: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
				for id in hud.build_bar._cards:
					var card = hud.build_bar._cards[id]
					_cards += 1
					var code: String = sim.place.check_building(String(id), lander + Vector2(400, 400), 0.0, -1, 1)
					var sim_locked: bool = code in ["locked", "locked_research"]
					if sim_locked != bool(card.locked):
						_bad.append("%s: SIM %s, card locked %s" % [id, code, card.locked])
					if card.locked:
						_locked += 1
						if String(card.lock_text).strip_edges() == "" or not card._reason.visible or String(card._reason.text).strip_edges() == "" or String(card.lock_full).strip_edges() == "":
							_bad.append("%s: no reason (%s | %s)" % [id, card.lock_text, card.lock_full])
				hud.build_bar.close_drawer()
				_tab += 1
				_n = 6
				return false
			check("every locked build card shows a one-line reason and a full text", _bad.is_empty() and _locked >= 5, "%d cards, %d locked, bad %s" % [_cards, _locked, str(_bad.slice(0, 4))])
			# A stage gate: the landing pad (stage 1, Stable outpost).
			var li: Dictionary = hud.data.lock_info("landing_pad", 1)
			var conds: Array = hud.data.stage_conditions(1)
			var unmet := ""
			for c in conds:
				if not bool(c["ok"]):
					unmet = String(c["text"])
					break
			check("stage gate: 'Needs stage Stable outpost (<first unmet condition>)'", not bool(li["ok"]) and String(li["short"]) == "Needs stage Stable outpost (%s)" % unmet and unmet != "", String(li["short"]))
			check("stage conditions: colonists n/8 with the value now", not conds.is_empty() and String(conds[0]["text"]) == "%d/8 colonists" % int(sim.metrics.forecast()["pop"]), str(conds))
			check("stage gate: the full text has the progress", String(li["full"]).contains("now"), String(li["full"]))
			# A research gate.
			var rdef := ""
			for id in sim.content["buildings"]:
				var bd: Dictionary = sim.content["buildings"][id]
				if int(bd.get("stage", 0)) == 0 and String(bd.get("research", "")) != "" and not hud.data.tech_done(String(bd["research"])) and bool(bd.get("buildable", true)):
					rdef = String(id)
					break
			var lr: Dictionary = hud.data.lock_info(rdef, 1)
			check("research gate: 'Needs research: <tech>'", not bool(lr["ok"]) and String(lr["short"]) == "Needs research: %s" % hud.data.tech_name(String(lr["tech"])), "%s: %s" % [rdef, lr["short"]])
			# The placement hint.
			main.start_place("landing_pad", 1)
			var lander2: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
			main._on_cmd("hover %d %d" % [int(lander2.x + 60.0), int(lander2.y)])
			_step = 2
			_n = 0
		2:
			var info: Dictionary = main.tool_info
			check("placement hint: the full requirement, not the bare 'not unlocked yet'", String(info.get("reason", "")).contains("Stable outpost") and not String(info.get("reason", "")).begins_with("This structure is not unlocked"), String(info.get("reason", "")))
			check("the hint panel shows it", String(hud.hint._state.text).contains("Stable outpost"), hud.hint._state.text)
			main._on_cmd("hover")
			main.cancel_tool() if main.has_method("cancel_tool") else main._on_cmd("esc")
			main._on_cmd("open codex structure:landing_pad")
			_step = 3
			_n = 0
		3:
			var t: String = _texts(hud.screens.top_screen()._detail)
			check("codex: How to unlock with the stage and its conditions", t.contains("HOW TO UNLOCK") and t.contains("Stable outpost") and t.contains("colonists"), t.left(300))
			main._on_cmd("close")
			# Advisor: a machine needs spare parts, none in the colony, and the maker is locked.
			var mach: Dictionary = {}
			var lp: Vector2 = sim.state["buildings"][int(sim.state["lander_id"])]["pos"]
			for k in 36:
				var p: Vector2 = sim.place.snap_pos(lp + Vector2.RIGHT.rotated(k * TAU / 36.0) * 45.0)
				if sim.place.check_building("refinery", p, 0.0, -1, 1) == "ok":
					sim.build.spawn_active("refinery", p, 0.0, 1)                               # test set-up: a machine
					break
			for id in sim.state["buildings"]:
				var b: Dictionary = sim.state["buildings"][id]
				if b["state"] == "active" and sim.hazards.is_machine(b):
					mach = b
					break
			check("a machine for the advisor test", not mach.is_empty())
			if not mach.is_empty():
				mach["state"] = "broken"                                                    # test set-up
				for iid in sim.state["inventories"]:
					var n: int = sim.inv.count(int(iid), "spare_parts")
					if n > 0:
						sim.inv.consume(int(iid), "spare_parts", n, "test")                 # test set-up
				var ws_stage: int = int(sim.content["buildings"]["workshop"].get("stage", 0))
				sim.content["buildings"]["workshop"]["stage"] = 2                            # test set-up: a locked maker
				var tips: Array = Advisor.needed_but_locked(hud)
				var tip: Dictionary = {}
				for tp in tips:
					if String(tp["title"]).contains("spare parts"):
						tip = tp
				check("advisor: no spare parts, the workshop is locked, how to unlock it and other ways",
					not tip.is_empty() and String(tip["title"]).contains("locked") and String(tip["text"]).begins_with("To unlock it:") and String(tip["text"]).contains("Growing settlement") and String(tip["text"]).contains("trader"), str(tip))
				sim.content["buildings"]["workshop"]["stage"] = ws_stage
				tips = Advisor.needed_but_locked(hud)
				tip = {}
				for tp in tips:
					if String(tp["title"]).contains("spare parts"):
						tip = tp
				check("advisor: maker unlocked but not built: build one", not tip.is_empty() and String(tip["text"]).contains("build a workshop"), str(tip))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
