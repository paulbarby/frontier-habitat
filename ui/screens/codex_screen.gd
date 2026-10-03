extends "res://ui/screens/screen.gd"
## Codex (V4_DESIGN §6, "Encyclopedia"): every structure, item, research project and hazard, with
## where it comes from and what uses it. Items show a crafting tree (ui/widgets/craft_tree.gd).
## Left: a search box and the list (a seam list in a dark well). Right: the entry. Every name in an
## entry is a link to its own entry. Key K, or the nav rail. arg: "item:steel", "structure:refinery", …
## Data: ui/codex.gd, built from the simulation's content (read only).

const Codex = preload("res://ui/codex.gd")
const CraftTree = preload("res://ui/widgets/craft_tree.gd")
const Icons2 = preload("res://ui/theme/icons.gd")

var _cx
var _filter := ""
var _sel := ""               # id of the open entry
# Wide view: list hidden. Kept on the HUD (hud.codex_wide) while the game runs. NOT a static var:
# a static var in a script that extends screen.gd made Godot 4.4.1 crash at exit (0xC0000005,
# 2026-09-28, after tools/check_scripts.gd loaded models.gd, screen.gd and this script in that order).
var wide := false
var _left: Control
var crafting_tree: Control   # the crafting tree now shown (tests)
var _list: VBoxContainer
var _detail: VBoxContainer
var _search: LineEdit
var shown_ids: Array = []    # ids in the list now (tests)

func _init() -> void:
	pauses = true
	icon = "codex"
	title = "Codex"
	subtitle = "Every structure, item, research project and hazard, and a guide to people, society and the planets."
	accent = P.CYAN
	tabs = [["item", "Items", "inventory"], ["structure", "Structures", "build"], ["chain", "Chains", "route"], ["tech", "Research", "research"], ["hazard", "Hazards", "hazard"], ["society", "Guide", "people"]]

func _ready() -> void:
	if typeof(arg) == TYPE_STRING and String(arg).contains(":"):
		tab = String(arg).get_slice(":", 0)
		_sel = String(arg).get_slice(":", 1)
	elif typeof(arg) == TYPE_STRING and String(arg) != "":
		tab = String(arg)
	super._ready()

func build() -> void:
	_cx = Codex.new(hud)
	wide = bool(hud.get("codex_wide")) if hud != null and hud.get("codex_wide") != null else false

func build_tab(id: String, box: VBoxContainer) -> void:
	var row: HBoxContainer = Kit.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var left: VBoxContainer = Kit.vbox(8)
	left.custom_minimum_size.x = 330
	left.visible = not wide
	_left = left
	row.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.clear_button_enabled = true
	_search.tooltip_text = "Search\nType part of a name or a category."
	_search.text = _filter
	_search.text_changed.connect(func(s: String):
		_filter = s
		_fill_list(id))
	left.add_child(_search)
	_list = Kit.seam_list(2)
	var w: PanelContainer = Kit.well_scroll(_list)
	left.add_child(w)
	var right_well: PanelContainer = Kit.panel("CardPanel", false)
	right_well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right_well)
	_detail = Kit.vbox(10)
	right_well.add_child(Kit.scroll(_detail))
	_fill_list(id)
	var es: Array = _cx.entries(id)
	var ok := false
	for e in es:
		if String(e["id"]) == _sel:
			ok = true
	if not ok and not es.is_empty():
		_sel = String(es[0]["id"])
	_show(id, _sel)

func _fill_list(kind: String) -> void:
	Kit.clear(_list)
	shown_ids = []
	var f: String = _filter.strip_edges().to_lower()
	for e in _cx.entries(kind):
		if f != "" and not (String(e["name"]) + " " + String(e["cat"])).to_lower().contains(f):
			continue
		shown_ids.append(String(e["id"]))
		var b: Button = Kit.button("", Callable(), "", "ListButton")
		b.custom_minimum_size.y = 38
		b.toggle_mode = true
		b.set_pressed_no_signal(String(e["id"]) == _sel)
		var eid: String = e["id"]
		b.pressed.connect(func(): _show(kind, eid))
		b.tooltip_text = "%s\n%s" % [String(e["name"]), String(e["desc"]) if String(e["desc"]) != "" else String(e["cat"])]
		var h: HBoxContainer = Kit.hbox(8)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 8
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		h.add_child(Kit.icon(_icon_of(e), 18, e["color"]))
		var tv: VBoxContainer = Kit.vbox(-2)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		tv.add_child(Kit.label(String(e["name"]), "", 14, P.TEXT))
		tv.add_child(Kit.label(String(e["cat"]), "SmallLabel", 12, P.TEXT_2))
		_list.add_child(b)

func _icon_of(e: Dictionary) -> String:
	return String(e["icon"]) if Icons2.has(String(e["icon"])) else String(e["fallback_icon"])

## Opens an entry (from the list or a link in another entry).
func open_entry(kind: String, id: String) -> void:
	if kind != tab:
		_sel = id
		_filter = ""
		set_tab(kind)
	else:
		_show(kind, id)

func _show(kind: String, id: String) -> void:
	_sel = id
	for b in _list.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(false)
	var idx: int = shown_ids.find(id)
	if idx >= 0 and idx < _list.get_child_count():
		(_list.get_child(idx) as Button).set_pressed_no_signal(true)
	Kit.clear(_detail)
	var e: Dictionary = {}
	for x in _cx.entries(kind):
		if String(x["id"]) == id:
			e = x
	if e.is_empty():
		return
	var h: HBoxContainer = Kit.hbox(12)
	_detail.add_child(h)
	h.add_child(Kit.icon(_icon_of(e), 36, e["color"]))
	var tv: VBoxContainer = Kit.vbox(0)
	h.add_child(tv)
	tv.add_child(Kit.label(String(e["name"]).to_upper(), "TitleLabel", 20, P.TEXT))
	tv.add_child(Kit.label(String(e["cat"]), "DimLabel", 13, P.TEXT_2))
	if int(e.get("tier", 0)) > 0:
		var D = load("res://ui/data.gd")
		h.add_child(Kit.badge(String(D.TIER_NAME[int(e["tier"])]).to_upper(), D.TIER_COLOR[int(e["tier"])]))
	if String(e["desc"]) != "":
		var d: Label = Kit.wrap(String(e["desc"]), 15, P.TEXT)
		d.custom_minimum_size.x = 420
		_detail.add_child(d)
	match kind:
		"item": _item(id)
		"structure": _structure(id)
		"tech": _tech(id)
		"chain": _chain(id)
		"hazard": pass

## Wide view: the entry list hides so the detail (and its crafting tree) gets the full width.
func set_wide(on: bool) -> void:
	wide = on
	if hud != null and hud.get("codex_wide") != null:
		hud.codex_wide = on
	if _left != null and is_instance_valid(_left):
		_left.visible = not on
	_show(tab, _sel)
	# Wide view is for the tree: bring its section to the top of the detail.
	if on:
		_scroll_to_tree.call_deferred()

func _scroll_to_tree() -> void:
	await get_tree().process_frame
	if crafting_tree == null or not is_instance_valid(crafting_tree):
		return
	var dsc: ScrollContainer = _detail.get_parent() as ScrollContainer
	if dsc != null:
		var sec: Control = crafting_tree.get_parent().get_parent()
		dsc.scroll_vertical = int(maxf(0.0, sec.position.y - 8.0))

func _section(t: String, icon_name: String = "") -> VBoxContainer:
	_detail.add_child(Kit.sep())
	var v: VBoxContainer = Kit.vbox(4)
	var hh: HBoxContainer = Kit.hbox(6)
	if icon_name != "":
		hh.add_child(Kit.icon(icon_name, 14, P.CYAN))
	hh.add_child(Kit.head(t, P.CYAN, 12))
	v.add_child(hh)
	_detail.add_child(v)
	return v

## A line of text followed by link buttons: [[label, kind, id], ...].
func _links(parent: Control, lead: String, links: Array) -> void:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 2)
	if lead != "":
		f.add_child(Kit.label(lead, "", 14, P.TEXT_2))
	for l in links:
		var k: String = l[1]
		var i: String = l[2]
		var b: Button = Kit.button(String(l[0]), func(): open_entry(k, i), "Open in the codex.", "GhostButton")
		b.add_theme_color_override("font_color", P.CYAN)
		f.add_child(b)
	parent.add_child(f)

func _item_links(d: Dictionary) -> Array:
	var out: Array = []
	for it in d:
		out.append(["%s %s" % [str(d[it]), hud.data.item_name(String(it)).to_lower()], "item", String(it)])
	return out

func _item(id: String) -> void:
	var made: Array = _cx.made_by(id)
	var s1: VBoxContainer = _section("Where it comes from", "inventory")
	if made.is_empty():
		s1.add_child(Kit.wrap("Not made in the colony: it comes with supply runs, traders or finds.", 14, P.TEXT_2))
	for m in made:
		var where: Array = []
		for w in m["where"]:
			if String(w) != "":
				where.append([String(hud.data.bdef(String(w)).get("name", w)), "structure", String(w)])
		var lead: String = String(m["name"])
		if bool(m.get("deposit", false)):
			lead += " (from a mineral deposit)"
		if int(m.get("min_level", 1)) > 1:
			lead += " (needs the structure at level %d)" % int(m["min_level"])
		if not (m["inputs"] as Dictionary).is_empty():
			_links(s1, lead + ": from", _item_links(m["inputs"]))
		else:
			s1.add_child(Kit.label(lead, "", 14, P.TEXT))
		if not where.is_empty():
			_links(s1, "at", where)
	var used: Array = _cx.used_by(id)
	var s2: VBoxContainer = _section("What uses it", "build")
	if used.is_empty():
		s2.add_child(Kit.wrap("Nothing in the colony uses it as an input.", 14, P.TEXT_2))
	var groups := {"recipe": [], "build": [], "research": [], "dish": []}
	for u in used:
		var k: String = String(u["how"])
		var kind: String = {"recipe": "item", "build": "structure", "research": "tech", "dish": "item"}[k]
		var target: String = String(u["id"])
		if k == "recipe":
			# Link to the first output of the recipe.
			var rec: Dictionary = hud.data.recipes().get(target, {})
			var outs: Array = (rec.get("outputs", {}) as Dictionary).keys()
			target = String(outs[0]) if not outs.is_empty() else target
		groups[k].append(["%s (%d)" % [String(u["name"]), int(u["amount"])], kind, target])
	for k in ["recipe", "build", "research", "dish"]:
		if not (groups[k] as Array).is_empty():
			_links(s2, {"recipe": "Recipes:", "build": "To build:", "research": "Research:", "dish": "Dishes:"}[k], groups[k])
	# Crafting tree: how one unit is made, raw materials on the left.
	var t: Dictionary = _cx.tree(id)
	if not (t["children"] as Array).is_empty():
		var s3: VBoxContainer = _section("Crafting tree (for one unit)", "grid")
		var tree = CraftTree.new()
		tree.hud = hud
		tree.set_tree(t)
		tree.picked.connect(func(it: String): open_entry("item", it))
		var sc: ScrollContainer = Kit.scroll(tree, true)
		sc.custom_minimum_size.y = minf(tree.custom_minimum_size.y + 16.0, 420.0)
		s3.add_child(sc)
		# Milestone 5: deep trees (high-end items) narrow their columns to fit the pane; when they
		# still do not fit, the tree opens scrolled to the item (right end) and "Wide view" hides
		# the list. Tier stripes: grey basic, cyan mid, gold high-end.
		var hh: HBoxContainer = s3.get_child(0)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(sp)
		for tr in [1, 2, 3]:
			var D = load("res://ui/data.gd")
			var sw := ColorRect.new()
			sw.color = D.TIER_COLOR[tr]
			sw.custom_minimum_size = Vector2(4, 12)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hh.add_child(sw)
			hh.add_child(Kit.label(String(D.TIER_NAME[tr]), "SmallLabel", 12, P.TEXT_2))
		var wb: Button = Kit.button("Wide view" if not wide else "Show the list", func(): set_wide(not wide), "Wide view\nHides the list so the crafting tree gets the full width. Click again to show the list.", "GhostButton", "expand" if not wide else "list", 14)
		hh.add_child(wb)
		crafting_tree = tree
		var fit := func():
			if is_instance_valid(tree) and is_instance_valid(sc):
				tree.fit_width(sc.size.x - 4.0)
				sc.custom_minimum_size.y = minf(tree.custom_minimum_size.y + 16.0, 700.0 if wide else 420.0)
				sc.scroll_horizontal = int(maxf(0.0, tree.custom_minimum_size.x - sc.size.x))
		sc.resized.connect(fit)
		fit.call_deferred()

## V5 §18.4: a production chain, from the raw resource to the item, with the state of each step in this colony.
func _chain(id: String) -> void:
	var c: Dictionary = hud.v18.chain_of(id)
	var sec: VBoxContainer = _section("The chain", "route")
	var ChainView = load("res://ui/widgets/chain_view.gd")
	var sl: Label = Kit.wrap(ChainView.summary(c), 14, P.GREEN if bool(c.get("ok", false)) else P.AMBER)
	sec.add_child(sl)
	sec.add_child(ChainView.build(hud, c, func(def_id: String):
		host.close(self)
		hud.main.start_place(def_id), func(_tech: String):
		host.close(self)
		hud.open_screen("research")))
	var s2: VBoxContainer = _section("The item", "inventory")
	_links(s2, "", [[hud.data.item_name(id), "item", id]])

func _structure(id: String) -> void:
	var b: Dictionary = hud.data.bdef(id)
	var s1: VBoxContainer = _section("Build", "build")
	_links(s1, "Cost:", _item_links(b.get("cost", {})))
	var facts: Array = []
	if float(b.get("power", 0.0)) > 0.0:
		facts.append("uses %s power" % str(b["power"]))
	if float(b.get("power_out", b.get("gen", 0.0))) > 0.0:
		facts.append("makes %s power" % str(b.get("power_out", b.get("gen"))))
	if String(b.get("role", "")) != "":
		facts.append("worked by a %s" % String(hud.main.sim.bal.get("role_names", {}).get(String(b["role"]), b["role"])).to_lower())
	if bool(b.get("automatic", false)):
		facts.append("works by itself")
	facts.append({"room": "pressurised room", "exterior": "outdoor structure", "special": "special structure", "link": "link"}.get(String(b.get("kind", "")), String(b.get("kind", ""))))
	s1.add_child(Kit.wrap(", ".join(facts).capitalize() + ".", 14, P.TEXT))
	# How to unlock (Paul, 2026-09-28): the colony stage with its conditions and progress, and the
	# research with a link. Both gates as SIM placement (stage first, then research).
	var tech: String = String(b.get("research", ""))
	var stage: int = int(b.get("stage", 0))
	var su: VBoxContainer = _section("How to unlock", "unlock")
	var li: Dictionary = hud.data.lock_info(id, 1)
	var stages: Array = hud.main.sim.bal.get("stages", [])
	var cur: int = int(hud.main.sim.state.get("progress", {}).get("stage", 0))
	if stage > 0 and stage < stages.size():
		var sname: String = String(stages[stage]["name"])
		if stage <= cur:
			su.add_child(Kit.label("Colony stage %s: reached." % sname, "", 14, P.GREEN))
		else:
			su.add_child(Kit.label("Colony stage %s (the colony is at %s)." % [sname, String(stages[cur]["name"])], "", 14, P.AMBER))
			var conds: Array = hud.data.stage_conditions(cur + 1)
			if stage > cur + 1:
				su.add_child(Kit.label("Next stage, %s, needs:" % String(stages[cur + 1]["name"]), "", 13, P.TEXT_2))
			for c in conds:
				var row: HBoxContainer = Kit.hbox(6)
				row.add_child(Kit.icon("check" if bool(c["ok"]) else "arrow_right", 12, P.GREEN if bool(c["ok"]) else P.AMBER))
				row.add_child(Kit.label(String(c["text"]), "", 13, P.TEXT if not bool(c["ok"]) else P.TEXT_2))
				su.add_child(row)
	if tech != "":
		var done: bool = hud.data.tech_done(tech)
		_links(su, "Research (done):" if done else "Research:", [[hud.data.tech_name(tech), "tech", tech]])
	if stage <= 0 and tech == "":
		su.add_child(Kit.label("Available from the start.", "", 14, P.TEXT_2))
	elif bool(li.get("ok", true)):
		su.add_child(Kit.label("Unlocked: you can build it.", "", 13, P.GREEN))
	var r = b.get("recipes", b.get("recipe", null))
	var list: Array = r if typeof(r) == TYPE_ARRAY else ([r] if typeof(r) == TYPE_STRING else [])
	if not list.is_empty():
		var s2: VBoxContainer = _section("Makes", "inventory")
		for rid in list:
			var rec: Dictionary = hud.data.recipes().get(rid, {})
			if not (rec.get("outputs", {}) as Dictionary).is_empty():
				_links(s2, String(rec.get("name", rid)) + ":", _item_links(rec["outputs"]))
			else:
				s2.add_child(Kit.label(String(rec.get("name", rid)), "", 14, P.TEXT))

func _tech(id: String) -> void:
	var t: Dictionary = hud.data.techs().get(id, {})
	var s1: VBoxContainer = _section("Research", "research")
	s1.add_child(Kit.label("%d RP. %s" % [int(t.get("cost", 0)), {"done": "Done.", "active": "In progress.", "available": "Can start now.", "locked": "Locked: needs the projects below."}.get(hud.data.tech_state(id), "")], "", 14, P.TEXT))
	var req: Array = []
	for r in t.get("requires", []):
		req.append([hud.data.tech_name(String(r)), "tech", String(r)])
	if not req.is_empty():
		_links(s1, "Needs:", req)
	if not (t.get("packs", {}) as Dictionary).is_empty():
		_links(s1, "Research packs:", _item_links(t["packs"]))
	var un: Dictionary = t.get("unlocks", {})
	if not un.is_empty():
		var s2: VBoxContainer = _section("Unlocks", "build")
		var bl: Array = []
		for bid in un.get("buildings", []):
			bl.append([String(hud.data.bdef(String(bid)).get("name", bid)), "structure", String(bid)])
		if not bl.is_empty():
			_links(s2, "Structures:", bl)
		var other: Array = []
		for k in un:
			if k == "buildings":
				continue
			other.append("%s %s" % [k, ", ".join((un[k] as Array).map(func(x): return str(x)))])
		if not other.is_empty():
			s2.add_child(Kit.wrap("; ".join(other).capitalize() + ".", 14, P.TEXT_2))
	var later: Array = []
	for tid in hud.data.techs():
		if (hud.data.techs()[tid].get("requires", []) as Array).has(id):
			later.append([hud.data.tech_name(String(tid)), "tech", String(tid)])
	if not later.is_empty():
		_links(s1, "Leads to:", later)
