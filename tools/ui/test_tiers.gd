extends SceneTree
## SIM milestone 5 (items in three tiers, 82 projects, min_level, locked deposits), headless:
##   node tools/godot.mjs script res://tools/ui/test_tiers.gd
## Research tree (lanes, tiers, search), item and structure tiers, codex tiers, "why stopped?"
## for level_low and deposit_locked, and the build palette grouped by tier.

const Why = preload("res://ui/why.gd")
const Codex = preload("res://ui/codex.gd")
const Data = preload("res://ui/data.gd")

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

func _spot(sim, def_id: String, around: Vector2, rmin: float, rmax: float, size: int) -> Vector2:
	var r: float = rmin
	while r <= rmax:
		for k in 36:
			var p: Vector2 = sim.place.snap_pos(around + Vector2.RIGHT.rotated(k * TAU / 36.0) * r)
			if sim.place.check_building(def_id, p, 0.0, -1, size) == "ok":
				return p
		r += 6.0
	return Vector2(-1, -1)

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.start_new(1001, {"scenario": "frontier"})
			main._on_cmd("speed 0")
			main._on_cmd("open research")
			_step = 1
			_n = 0
		1:
			var d = hud.data
			var top = hud.screens.top_screen()
			check("the research screen opens", top != null and hud.screen_name() == "research")
			var techs: Dictionary = d.techs()
			check("all projects are in the tree", top._nodes.size() == techs.size() and techs.size() >= 82, "%d nodes, %d projects" % [top._nodes.size(), techs.size()])
			var br: Dictionary = d.branches()
			var no_lane: Array = []
			for t in techs:
				var b: String = String(techs[t].get("branch", ""))
				if not br.has(b) or String(br[b].get("name", "")) == "" or String(br[b].get("name", "")) == b:
					if not no_lane.has(b):
						no_lane.append(b)
			check("every branch has a named lane (new branches too)", no_lane.is_empty(), str(no_lane))
			var rows := {}
			for b in br:
				rows[int(br[b].get("row", 0))] = true
			check("every branch has its own row", rows.size() == br.size(), "%d rows, %d branches" % [rows.size(), br.size()])
			var overlap: Array = []
			var ids: Array = top._nodes.keys()
			for i in ids.size():
				var ra: Rect2 = Rect2(top._nodes[ids[i]].position, top._nodes[ids[i]].size)
				for j in range(i + 1, ids.size()):
					if ra.grow(-1.0).intersects(Rect2(top._nodes[ids[j]].position, top._nodes[ids[j]].size)):
						overlap.append("%s/%s" % [ids[i], ids[j]])
			check("no two project nodes overlap", overlap.is_empty(), str(overlap.slice(0, 4)))
			var col_ok := true
			for t in ids:
				var want: float = top.LABEL_W + float(int(techs[t].get("tier", 1)) - 1) * (top.NODE_W + top.COL_GAP)
				if absf(top._nodes[t].position.x - want) > 0.5:
					col_ok = false
			check("tiers are columns", col_ok)
			# Pack costs: the column heads name the packs, the nodes carry the pack chips.
			var tip_ok := false
			for c in top._canvas.get_children():
				if c is HBoxContainer and String(c.tooltip_text).begins_with("Tier 4") and String(c.tooltip_text).contains("use"):
					tip_ok = true
			check("the tier 4 column names the packs it uses", tip_ok)
			# Search
			top._search.text = "magnet"
			top.apply_search()
			var hit := false
			for t in top.matches:
				for x in techs[t].get("unlocks", {}).get("buildings", []):
					if String(x) == "magnet_works":
						hit = true
			check("search 'magnet' finds the project that unlocks the magnet works", hit, str(top.matches))
			var dim := 0
			for t in ids:
				if top._nodes[t].modulate.a < 0.5:
					dim += 1
			check("the others are dimmed, not hidden", dim == ids.size() - top.matches.size() and top.matches.size() >= 1, "%d dim" % dim)
			check("the bar counts the matches", top._match_label.text.contains("match"), top._match_label.text)
			top.goto_first_match()
			check("Enter selects the first match", top.selected == String(top.matches[0]), top.selected)
			var sc: ScrollContainer = top._tree_scroll
			check("the tree scrolls to it", sc.scroll_horizontal > 0 or top._nodes[top.selected].position.x < sc.size.x, "h %d" % sc.scroll_horizontal)
			top._search.text = "reactor"
			top.apply_search()
			check("search 'reactor' finds the fission and fusion projects", top.matches.size() >= 2, str(top.matches))
			top._search.text = "zzzz"
			top.apply_search()
			check("no match says so", top.matches.is_empty() and top._match_label.text == "No project matches.")
			top._search.text = ""
			top._only_open.button_pressed = true
			top.apply_search()
			var bad: Array = []
			for t in top.matches:
				if not (d.tech_state(String(t)) in ["available", "active", "queued"]):
					bad.append(t)
			check("'Can start now' keeps only projects that can start", not top.matches.is_empty() and bad.is_empty(), "%d, bad %s" % [top.matches.size(), str(bad)])
			top._only_open.button_pressed = false
			top.apply_search()
			check("clear search shows the count", top._match_label.text == "%d projects" % ids.size(), top._match_label.text)
			# ---- Tiers
			check("item tiers: ore basic, alloy mid, metamaterial high-end", d.item_tier("ore") == 1 and d.item_tier("alloy") == 2 and d.item_tier("metamaterial") == 3,
				"%d %d %d" % [d.item_tier("ore"), d.item_tier("alloy"), d.item_tier("metamaterial")])
			var hp_want: int = int(d.items().get("hull_plate", {}).get("tier", 1))   # SIM's tier when given, else the UI's (basic recipe)
			check("hull plate: SIM's tier, else basic from its basic recipe", d.item_tier("hull_plate") == hp_want, "%d want %d" % [d.item_tier("hull_plate"), hp_want])
			# SIM gives "tier" in items.json since 2026-09-27 (the UI's request): the UI then shows SIM's tier
			# for every item, crops too; without it, crops and dishes have none.
			var sim_tier: bool = d.items().get("potato", {}).has("tier")
			if sim_tier:
				var diff: Array = []
				for it in d.items():
					if d.items()[it].has("tier") and d.item_tier(String(it)) != int(d.items()[it]["tier"]):
						diff.append(it)
				check("the UI shows SIM's item tier (items.json tier)", diff.is_empty(), str(diff))
			else:
				check("crops and dishes have no tier", d.item_tier("potato") == 0 or not d.items().has("potato"))
			var untier: Array = []
			for it in d.items():
				var cat: String = d.item_cat(String(it))
				if not (cat in Data.UNTIERED_CATS) and d.item_tier(String(it)) == 0:
					untier.append(it)
			check("every material, component and pack has a tier", untier.is_empty(), str(untier))
			check("tier names", d.tier_name(1) == "Basic" and d.tier_name(2) == "Mid" and d.tier_name(3) == "High-end")
			check("structure tiers: mine basic, steel mill mid, metamaterial foundry high-end",
				d.building_tier("mine") == 1 and d.building_tier("steel_mill") == 2 and d.building_tier("metamaterial_foundry") == 3,
				"%d %d %d" % [d.building_tier("mine"), d.building_tier("steel_mill"), d.building_tier("metamaterial_foundry")])
			# ---- Codex
			var cx = Codex.new(hud)
			var ents: Array = cx.entries("item")
			var no_tag: Array = []
			var seen := {}
			for e in ents:
				seen[String(e["id"])] = true
				if int(e.get("tier", 0)) > 0 and not String(e["cat"]).contains(d.tier_name(int(e["tier"]))):
					no_tag.append(e["id"])
			var missing: Array = []
			for it in sim.content["items"]:
				if not seen.has(String(it)) and not String(it).begins_with("_"):
					missing.append(it)
			check("the codex lists every item", missing.is_empty(), str(missing))
			check("item entries name their tier", no_tag.is_empty(), str(no_tag))
			var lvl := false
			for m in cx.made_by("metamaterial"):
				if int(m.get("min_level", 1)) == 2:
					lvl = true
			check("the codex knows the metamaterial recipe needs level 2", lvl)
			var t3: Dictionary = cx.tree("metamaterial", 6)
			var leaves: Array = []
			var stack: Array = [t3]
			var depth := 0
			while not stack.is_empty():
				var nd: Dictionary = stack.pop_back()
				if (nd["children"] as Array).is_empty():
					leaves.append(String(nd["item"]))
				for ch in nd["children"]:
					stack.append(ch)
				depth += 1
			check("the metamaterial tree reaches raw materials", leaves.size() >= 2, str(leaves))
			main._on_cmd("close")
			_step = 2
			_n = 0
		2:
			var d = hud.data
			# ---- Why stopped? level_low and deposit_locked (display rows built from live rows)
			var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
			sim.state["flags"]["unlock_all"] = true                                               # test set-up
			var p: Vector2 = _spot(sim, "metamaterial_foundry", lander["pos"], 30.0, 120.0, 1)
			var fb: Dictionary = {}
			if p.x > 0.0:
				fb = sim.build.spawn_active("metamaterial_foundry", p, 0.0, 1)                     # test set-up
			check("a metamaterial foundry for the test", not fb.is_empty(), str(p))
			if not fb.is_empty():
				fb["recipe_sel"] = "metamaterial"
				fb["level"] = 1
				fb["powered"] = true
				fb["enabled"] = true
				var blk: String = sim.prod.machine_block(fb) if bool(fb.get("powered", false)) else "level_low"
				var row: Dictionary = fb.duplicate(true)
				row["block"] = "level_low"
				var w: Dictionary = Why.structure(hud, row)
				check("why: level_low names the level and the fix", String(w["title"]) == "Needs level 2" and String(w["why"][0]).contains("level 2") and String(w["fix"][0]).contains("Upgrade"),
					"%s | %s | sim block %s" % [w["title"], str(w["why"]), blk])
			var dep: Dictionary = {}
			for dd in sim.state.get("deposits", []):
				if String(dd.get("kind", "")) in ["titanium", "uranium", "rare_earth", "carbon", "helium3"]:
					dep = dd
					break
			check("a deposit that needs research", not dep.is_empty())
			if not dep.is_empty():
				var mine: Dictionary = {"id": 999999, "def": "mine", "name": "Mine", "state": "active", "enabled": true, "powered": true, "level": 1,
					"pos": Vector2(float(dep["x"]), float(dep["y"])), "radius": 7.5, "block": "deposit_locked", "recipe_sel": ""}
				var w2: Dictionary = Why.structure(hud, mine)
				var info: Dictionary = sim.prod.deposit_info(dep)
				check("why: deposit_locked names the material and the research", String(w2["title"]) == "Deposit locked" and String(w2["why"][0]).contains(d.item_name(String(info["item"])).to_lower())
					and String(w2["fix"][0]).contains(d.tech_name(String(info["research"]))), "%s | %s | %s" % [w2["title"], str(w2["why"]), str(w2["fix"])])
			# ---- Build palette grouped by tier
			hud.build_bar.toggle_tab("industry")
			_step = 3
			_n = 0
		3:
			var d = hud.data
			var bb = hud.build_bar
			var tiers: Array = bb.tier_rows.keys()
			tiers.sort()
			check("the industry drawer has Basic, Mid and High-end rows", tiers == [1, 2, 3], str(tiers))
			var wrong: Array = []
			var n := 0
			for tr in bb.tier_rows:
				for card in bb.tier_rows[tr].get_children():
					n += 1
					if d.building_tier(String(card.def_id)) != int(tr):
						wrong.append(card.def_id)
			check("every card is in the row of its tier", wrong.is_empty(), str(wrong))
			check("every industry structure is in the drawer", n == bb._defs_for("industry").size() and n >= 20, "%d" % n)
			var at: Dictionary = {}
			for tr in bb.tier_rows:
				for card in bb.tier_rows[tr].get_children():
					at[String(card.def_id)] = int(tr)
			check("mine basic, steel mill mid, foundry high-end in the drawer", at.get("mine") == 1 and at.get("steel_mill") == 2 and at.get("metamaterial_foundry") == 3, str(at))
			var r: Rect2 = bb._drawer.get_global_rect()
			var vr: Rect2 = bb.get_viewport_rect()
			check("the drawer fits in the view at 1600x900", r.position.y >= 0.0 and r.end.x <= vr.size.x + 0.5 and r.position.x >= 0.0, str(r))
			var clash: Array = []
			for pn in [hud.goals, hud.alerts, hud.minimap]:
				if pn != null and pn.is_visible_in_tree() and pn.get_global_rect().grow(-1.0).intersects(r):
					clash.append(pn.name)
			check("the tall drawer keeps clear of the goals, alerts and map panels", clash.is_empty(), str(clash) + " " + str(r))
			var long_ok := true
			for tr in bb.tier_rows:
				for card in bb.tier_rows[tr].get_children():
					if card.get_child(0).get_combined_minimum_size().x > card.size.x + 0.5:
						long_ok = false
			check("every card's content fits its card (long output names)", long_ok)
			bb.toggle_tab("food")
			_step = 4
			_n = 0
		4:
			var bb = hud.build_bar
			check("a one-tier tab has no tier tags", bb.tier_rows.size() == 1)
			var r: Rect2 = bb._drawer.get_global_rect()
			check("the drawer shrinks for a short tab", r.size.y < 300.0, str(r.size))
			bb.close_drawer()
			main._on_cmd("open codex item:metamaterial")
			_step = 5
			_n = 0
		5:
			var top = hud.screens.top_screen()
			check("the codex opens on metamaterial", top != null and top._sel == "metamaterial")
			var txt := ""
			for l in top._detail.find_children("*", "Label", true, false):
				txt += (l as Label).text + " "
			check("the entry shows its tier", txt.contains("HIGH-END"), txt.left(200))
			check("the entry says the recipe needs level 2", txt.contains("needs the structure at level 2"))
			var tr_ = top.crafting_tree
			var sc_: ScrollContainer = tr_.get_parent()
			check("the deep tree narrows its columns", tr_.col_w < tr_.COL_W and tr_.col_w >= tr_.COL_MIN, "%.0f" % tr_.col_w)
			check("the tree opens scrolled to the item (right end)", sc_.scroll_horizontal >= int(tr_.custom_minimum_size.x - sc_.size.x) - 2, "%d of %d" % [sc_.scroll_horizontal, int(tr_.custom_minimum_size.x - sc_.size.x)])
			main._on_cmd("codexwide 1")
			_step = 6
			_n = 0
		6:
			var top = hud.screens.top_screen()
			var tr_ = top.crafting_tree
			var sc_: ScrollContainer = tr_.get_parent()
			check("Wide view: the whole metamaterial tree fits", tr_.custom_minimum_size.x <= sc_.size.x + 0.5, "%.0f in %.0f" % [tr_.custom_minimum_size.x, sc_.size.x])
			main._on_cmd("codexwide 0")
			main._on_cmd("close")
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
