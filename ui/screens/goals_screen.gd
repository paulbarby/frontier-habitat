extends "res://ui/screens/screen.gd"
## Goals: the five chapters of the mission on the left; the chosen chapter's goal cards
## on the right, each with its progress, sustain timer, hint and reward. The victory line
## at the bottom.

var chapter := -1
var _list: VBoxContainer
var _grid: GridContainer
var _head: VBoxContainer
var _sig := ""
var _cards := {}
var _kinds := {}

func _init() -> void:
	icon = "goals"
	title = "Mission"
	subtitle = "Five chapters. Each goal done sends a supply pod to the lander."

func build() -> void:
	var d = hud.data
	if not d.goals_available() or d.chapters().is_empty():
		content.add_child(Kit.wrap("The mission is not available yet.", 15, P.TEXT_2))
		return
	for ch in d.chapters():
		for g in ch.get("goals", []):
			_kinds[String(g["id"])] = String(g.get("kind", ""))
	chapter = mini(d.chapter_index(), d.chapters().size() - 1)
	var body: HBoxContainer = Kit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_list = Kit.vbox(8)
	_list.custom_minimum_size.x = 300
	body.add_child(_list)
	var right: VBoxContainer = Kit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_head = Kit.vbox(6)
	right.add_child(_head)
	_grid = Kit.grid(2, 12, 12)
	right.add_child(Kit.scroll(_grid))
	var foot: PanelContainer = Kit.panel("WellPanel", false)
	content.add_child(foot)
	var fh: HBoxContainer = Kit.hbox(10)
	foot.add_child(fh)
	fh.add_child(Kit.icon("trophy", 20, P.GOLD))
	var vd: Dictionary = d.victory_def()
	fh.add_child(Kit.head("Victory: %s" % String(vd.get("name", "Frontier established")), P.GOLD, 13, "head_wide"))
	var vl: Label = Kit.label(("Achieved. " + String(vd.get("desc", ""))) if d.victory() else "Complete all five chapters to win. You can play on after the victory.", "DimLabel", 13, P.TEXT_2)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.clip_text = true
	fh.add_child(vl)
	_rebuild()

func _goals() -> Array:
	var d = hud.data
	if d.has_helper("goals", "list"):
		return hud.main.sim.goals.list()
	return hud.goals._goals()

func _rebuild() -> void:
	var d = hud.data
	var ci: int = d.chapter_index()
	var goals: Array = _goals()
	_sig = _signature(goals)
	Kit.clear(_list)
	var chs: Array = d.chapters()
	for i in chs.size():
		var ch: Dictionary = chs[i]
		var n := 0
		var done := 0
		for g in goals:
			if int(g.get("chapter", -1)) == i:
				n += 1
				if String(g.get("state", "")) == "done":
					done += 1
		var state: String = "done" if i < ci else ("active" if i == ci else "locked")
		var ii: int = i
		var b: Button = Kit.button("", func():
			chapter = ii
			_rebuild(), "", "CardButton")
		b.toggle_mode = true
		b.set_pressed_no_signal(i == chapter)
		b.custom_minimum_size = Vector2(300, 74)
		var h: HBoxContainer = Kit.hbox(12)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 14
		h.offset_right = -12
		b.add_child(h)
		var num: Label = Kit.label("%d" % (i + 1), "DisplayLabel", 30, P.GREEN if state == "done" else (P.CYAN if state == "active" else P.TEXT_3))
		num.custom_minimum_size.x = 30
		h.add_child(num)
		var v: VBoxContainer = Kit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(v)
		v.add_child(Kit.label(String(ch.get("name", "")).to_upper(), "TitleLabel", 15, P.TEXT if state != "locked" else P.TEXT_3))
		var bar = Kit.bar(float(done) / maxf(1.0, float(n)), P.GREEN if state == "done" else P.CYAN, 5.0)
		v.add_child(bar)
		v.add_child(Kit.label("%s  ·  %d of %d goals" % [{"done": "Complete", "active": "Open now", "locked": "Opens later"}[state], done, n], "SmallLabel", 11, P.TEXT_2))
		h.add_child(Kit.icon("sev_ok" if state == "done" else ("goals" if state == "active" else "lock"), 18, P.GREEN if state == "done" else (P.CYAN if state == "active" else P.TEXT_3)))
		_list.add_child(b)
	# Head of the chosen chapter
	Kit.clear(_head)
	var chd: Dictionary = chs[chapter]
	_head.add_child(Kit.head("Chapter %d of %d" % [chapter + 1, chs.size()], P.CYAN, 12))
	_head.add_child(Kit.label(String(chd.get("name", "")).to_upper(), "DisplayLabel", 34, P.TEXT))
	_head.add_child(Kit.wrap(String(chd.get("desc", "")), 15, P.TEXT_2))
	# Goal cards
	Kit.clear(_grid)
	_cards = {}
	for g in goals:
		if int(g.get("chapter", -1)) != chapter:
			continue
		var card: Dictionary = _card(g)
		_grid.add_child(card["root"])
		_cards[String(g["id"])] = card
	refresh()

func _signature(goals: Array) -> String:
	var s := "%d|" % hud.data.chapter_index()
	for g in goals:
		s += "%s:%s," % [g["id"], g.get("state", "")]
	return s

func _card(g: Dictionary) -> Dictionary:
	var p: PanelContainer = Kit.panel("CardPanel", false)
	p.custom_minimum_size = Vector2(430, 150)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v: VBoxContainer = Kit.vbox(6)
	p.add_child(v)
	var top: HBoxContainer = Kit.hbox(8)
	v.add_child(top)
	var ic: TextureRect = Kit.icon("sev_info", 20, P.CYAN)
	top.add_child(ic)
	var nm: Label = Kit.label(String(g["name"]).to_upper(), "TitleLabel", 16, P.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var badge_box: HBoxContainer = Kit.hbox(0)
	top.add_child(badge_box)
	v.add_child(Kit.wrap(String(g.get("desc", "")), 14, P.TEXT))
	var bar = Kit.bar(0.0, P.CYAN, 9.0)
	var row: HBoxContainer = Kit.hbox(10)
	row.add_child(bar)
	var val: Label = Kit.num("", 13, P.TEXT)
	val.custom_minimum_size.x = 110
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	v.add_child(row)
	var info: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	v.add_child(info)
	if String(g.get("hint", "")) != "":
		var hint: HBoxContainer = Kit.hbox(6)
		hint.add_child(Kit.icon("info", 13, P.TEXT_3))
		var hl: Label = Kit.wrap(String(g["hint"]), 12, P.TEXT_3)
		hint.add_child(hl)
		v.add_child(hint)
	var rw: Dictionary = g.get("reward", {})
	var rrow := HFlowContainer.new()
	rrow.add_theme_constant_override("h_separation", 10)
	rrow.add_child(Kit.head("Reward", P.GOLD, 11))
	for it in rw.get("items", {}):
		rrow.add_child(Kit.chip(Icons.item(String(it)), "%d" % int(rw["items"][it]), hud.data.item_color(String(it)), hud.data.item_name(String(it)), true, 16))
	if float(rw.get("rp", 0)) > 0.0:
		rrow.add_child(Kit.chip("research", "%d RP" % int(rw["rp"]), P.VIOLET, "Research points", true, 16))
	v.add_child(rrow)
	return {"root": p, "icon": ic, "bar": bar, "val": val, "info": info, "badge": badge_box, "name": nm}

func refresh() -> void:
	if _grid == null:
		return
	var goals: Array = _goals()
	if _signature(goals) != _sig:
		_rebuild()
		return
	var tick: int = int(hud.main.sim.state["tick"])
	var hz: float = float(hud.main.sim.bal["tick_hz"])
	for g in goals:
		var c: Dictionary = _cards.get(String(g["id"]), {})
		if c.is_empty():
			continue
		var state: String = String(g.get("state", "active"))
		var value: float = float(g.get("value", 0.0))
		var target: float = float(g.get("target", 0.0))
		var frac: float = clampf(value / target, 0.0, 1.0) if target > 0.0 else (1.0 if value > 0.0 else 0.0)
		var sustain: float = float(g.get("sustain", 0.0))
		var since: int = int(g.get("since", -1))
		var col: Color = P.CYAN
		var info := ""
		var word := "OPEN"
		if state == "done":
			col = P.GREEN
			frac = 1.0
			word = "DONE"
			var dt: int = int(g.get("done_tick", -1))
			info = ("Done on %s." % hud.data.tick_to_day(dt)) if dt >= 0 else "Done."
			Kit.set_icon(c["icon"], "sev_ok", 20, P.GREEN)
		elif state == "locked":
			col = P.TEXT_3
			word = "LATER"
			info = "Opens with this chapter."
			Kit.set_icon(c["icon"], "lock", 20, P.TEXT_3)
		else:
			if sustain > 0.0 and since >= 0:
				var held: float = float(tick - since) / hz
				info = "Holding for %s of %s. A break starts the timer again." % [Kit.clock(held), Kit.clock(sustain)]
				frac = clampf(held / sustain, 0.0, 1.0)
				col = P.GREEN
				word = "HOLDING"
				Kit.set_icon(c["icon"], "clock", 20, P.GREEN)
			else:
				info = ("Must hold for %s without a break." % Kit.clock(sustain)) if sustain > 0.0 else "In progress."
				Kit.set_icon(c["icon"], "goals", 20, P.CYAN)
		c["bar"].value = frac
		c["bar"].color = col
		(c["val"] as Label).text = hud.goals._value_text(value, target, String(_kinds.get(String(g["id"]), "")))
		(c["info"] as Label).text = info
		var bb: HBoxContainer = c["badge"]
		if bb.get_child_count() == 0 or String(bb.get_meta("word", "")) != word:
			for x in bb.get_children():
				x.queue_free()
			bb.add_child(Kit.badge(word, col))
			bb.set_meta("word", word)
