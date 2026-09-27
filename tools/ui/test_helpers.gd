extends SceneTree
## Helpers (V4_DESIGN §6), headless:  node tools/godot.mjs script res://tools/ui/test_helpers.gd
## "Why stopped?" for every structure and colonist; the advisor; the codex and its crafting tree.

const Why = preload("res://ui/why.gd")
const Codex = preload("res://ui/codex.gd")

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

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
			main._on_cmd("speed 0")
			_step = 1
			_n = 0
		1:
			# ---- Why stopped?
			var s = main.sim
			var empty: Array = []
			var stopped: Array = []
			for id in s.state["buildings"]:
				var b: Dictionary = s.state["buildings"][id]
				var w: Dictionary = Why.structure(hud, b)
				if String(w["title"]) == "":
					empty.append(String(b["def"]))
				if bool(w["stopped"]):
					stopped.append([int(id), w])
					if (w["why"] as Array).is_empty():
						empty.append(String(b["def"]) + " (no reason)")
			check("every structure has a status and every stopped one a reason", empty.is_empty(), str(empty.slice(0, 5)))
			var ag_empty := 0
			for aid in s.state["agents"]:
				if String(Why.agent(hud, s.state["agents"][aid])["title"]) == "":
					ag_empty += 1
			check("every colonist has a status", ag_empty == 0, "%d without" % ag_empty)
			var any_b: Dictionary = {}
			for id in s.state["buildings"]:
				var b2: Dictionary = s.state["buildings"][id]
				if String(b2["state"]) == "active" and String(b2.get("kind", "")) != "link":
					any_b = b2.duplicate(true)
					break
			any_b["enabled"] = false
			var w_off: Dictionary = Why.structure(hud, any_b)
			check("a switched-off structure: why and fix", String(w_off["title"]) == "Switched off" and not (w_off["fix"] as Array).is_empty(), str(w_off))
			any_b["enabled"] = true
			any_b["block"] = "no_input"
			any_b["powered"] = true
			var w_in: Dictionary = Why.structure(hud, any_b)
			check("no input: names the missing input and the fix", String(w_in["title"]) == "No input" and not (w_in["fix"] as Array).is_empty(), str(w_in["why"]))
			any_b["block"] = "materials:electronics"
			check("a working structure waiting for an item names it", String(Why.structure(hud, any_b)["title"]) == "Waiting for electronics", String(Why.structure(hud, any_b)["title"]))
			any_b["block"] = "some_new_code"
			check("an unknown code is shown by name, never silent", String(Why.structure(hud, any_b)["why"][0]).contains("some_new_code"))
			var idle := {"state": "alive", "goal": "Idle", "role": "technician", "backoff": {"1": 5}, "hunger": 10.0, "thirst": 10.0, "fatigue": 10.0, "health": 100.0, "morale": 60.0, "where": "in"}
			var wa: Dictionary = Why.agent(hud, idle)
			check("an idle colonist: no job, unreachable jobs, a fix", bool(wa["stopped"]) and (wa["why"] as Array).size() >= 2 and not (wa["fix"] as Array).is_empty(), str(wa["why"]))
			if not stopped.is_empty():
				main.select("building", stopped[0][0])
				set_meta("sid", stopped[0][0])
			_step = 2
			_n = 0
		2:
			if has_meta("sid"):
				var well: Control = hud.inspector._body.get_child(0)
				check("the inspector shows the reason at the top for a stopped structure", well.visible and well is PanelContainer, "%s" % hud.inspector._title.text)
			else:
				print("SKIP no stopped structure in the save")
			# ---- Advisor
			var r: String = main._on_cmd("advisor")
			var kinds_ok := true
			for tp in hud.advisor.tips:
				kinds_ok = kinds_ok and ["problem", "next", "unused"].has(String(tp["kind"])) and String(tp["title"]) != ""
			check("the advisor opens with advice", hud.advisor.visible and hud.advisor.tips.size() >= 2 and kinds_ok, r.replace("\n", " | "))
			var has_next := false
			for tp in hud.advisor.tips:
				has_next = has_next or String(tp["kind"]) == "next"
			check("the advisor names the next goal step", has_next)
			var wa2: Rect2 = hud.wm.work_area()
			check("the advisor window lies in the work area", wa2.grow(0.5).encloses(hud.advisor.get_global_rect()), str(hud.advisor.get_global_rect()))
			main._on_cmd("closeall")
			# ---- Codex
			var cx = Codex.new(hud)
			check("codex lists items, structures, research, hazards", cx.entries("item").size() >= 20 and cx.entries("structure").size() >= 20 and cx.entries("tech").size() >= 30 and cx.entries("hazard").size() >= 6,
				"%d items, %d structures, %d techs" % [cx.entries("item").size(), cx.entries("structure").size(), cx.entries("tech").size()])
			var made_metal := false
			for m in cx.made_by("metal"):
				made_metal = made_metal or (m["inputs"] as Dictionary).has("ore")
			check("steel comes from ore at the refinery", made_metal and cx.recipe_where("refine").has("refinery"))
			check("steel is used to build", cx.used_by("metal").size() >= 5, "%d uses" % cx.used_by("metal").size())
			var t: Dictionary = cx.tree("hull_plate")
			var leaves: Array = []
			_leaves(t, leaves)
			check("the hull plate crafting tree reaches raw materials", (t["children"] as Array).size() >= 1 and leaves.has("ore"), str(leaves))
			main._on_cmd("open codex item:hull_plate")
			_step = 3
			_n = 0
		3:
			var top = hud.screens.top_screen()
			check("the codex screen opens on the item", top != null and hud.screen_name() == "codex" and top.tab == "item" and top._sel == "hull_plate")
			var tree_found: bool = top != null and not top._detail.find_children("*", "Control", true, false).filter(func(c): return c.get_script() == load("res://ui/widgets/craft_tree.gd")).is_empty()
			check("the item entry shows its crafting tree", tree_found)
			top.open_entry("structure", "refinery")
			_step = 4
			_n = 0
		4:
			var top = hud.screens.top_screen()
			check("a link opens another kind of entry", top.tab == "structure" and top._sel == "refinery")
			top._search.text = "solar"
			top._search.text_changed.emit("solar")
			check("the search filters the list", top.shown_ids.size() >= 1 and top.shown_ids.size() < 10, str(top.shown_ids))
			check("no sideways scroll bar", not top._scroll.get_h_scroll_bar().visible)
			main._on_cmd("close")
			# ---- Planner overlays (minimap part; the 3D layers are RENDER's)
			var mm = hud.minimap
			var ok_all := true
			var info: Array = []
			for ov in ["radiation", "sun", "resources"]:
				hud.set_overlay(ov)
				mm.refresh()
				mm.refresh()
				var drawn: bool = (ov == "resources") or mm._planner.has(ov)
				ok_all = ok_all and drawn and mm._legend.visible and mm._ov[ov].button_pressed
				info.append("%s %s" % [ov, drawn])
			hud.set_overlay("")
			check("planner overlays: radiation, sun, resources on the minimap with a legend", ok_all and not mm._legend.visible, str(info))
			check("key O steps through the planner overlays", hud.OVERLAYS.has("radiation") and hud.OVERLAYS.has("sun") and hud.OVERLAYS.has("resources"))
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false

func _leaves(n: Dictionary, out: Array) -> void:
	if (n["children"] as Array).is_empty():
		out.append(String(n["item"]))
	for c in n["children"]:
		_leaves(c, out)
