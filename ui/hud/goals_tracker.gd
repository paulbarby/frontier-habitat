extends PanelContainer
## Left column, top: the mission tracker. The open chapter, its goals with progress bars
## and sustain timers, and each goal's reward. Collapses to one line. Without the 2.0
## goals system it shows the version-1 tutorial step instead.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Metrics = preload("res://sim/metrics.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Settings = preload("res://ui/settings.gd")

var hud
var collapsed := false
var _head: Label
var _sub: Label
var _count: Label
var _chev: Button
var _list: VBoxContainer
var _chapter_bar
var _sig := ""
var _rows := {}

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 8
	offset_top = 76
	custom_minimum_size.x = 334
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	var top: HBoxContainer = Kit.hbox(8)
	v.add_child(top)
	top.add_child(Kit.icon("goals", 18, P.CYAN))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	_sub = Kit.head("Mission", P.TEXT_3, 11)
	tv.add_child(_sub)
	_head = Kit.head("", P.TEXT, 14, "head_wide")
	tv.add_child(_head)
	_count = Kit.num("", 13, P.TEXT_2)
	top.add_child(_count)
	_chev = Kit.icon_button("chevron_up", func(): _toggle(), "Collapse or expand", "GhostButton", 14, 26)
	top.add_child(_chev)
	_chapter_bar = Kit.bar(0.0, P.CYAN, 4.0)
	v.add_child(_chapter_bar)
	_list = Kit.vbox(9)
	v.add_child(_list)
	gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and ev.double_click:
			hud.open_screen("goals"))
	tooltip_text = "Double click: open the goals screen (G)."

func _toggle() -> void:
	collapsed = not collapsed
	_list.visible = not collapsed
	_chev.icon = Icons.tex("chevron_down" if collapsed else "chevron_up", 14)

func rebuild() -> void:
	_sig = ""
	refresh()

func _process(_delta: float) -> void:
	Kit.fit(self)

func refresh() -> void:
	var d = hud.data
	if not d.goals_available():
		_refresh_tutorial()
		return
	var ch: Array = d.chapters()
	var ci: int = d.chapter_index()
	var goals: Array = _goals()
	if ci >= ch.size():
		_sub.text = "MISSION COMPLETE"
		_head.text = String(d.victory_def().get("name", "Frontier established")).to_upper()
		_count.text = "%d/%d" % [ch.size(), ch.size()]
		_chapter_bar.value = 1.0
		_chapter_bar.color = P.GOLD
		_set_rows([])
		return
	var chapter: Dictionary = ch[ci]
	var mine: Array = []
	var done := 0
	for g in goals:
		if int(g.get("chapter", -1)) == ci:
			mine.append(g)
			if String(g.get("state", "")) == "done":
				done += 1
	_sub.text = "CHAPTER %d OF %d" % [ci + 1, ch.size()]
	_head.text = String(chapter.get("name", "")).to_upper()
	_count.text = "%d/%d" % [done, mine.size()]
	_chapter_bar.value = float(done) / maxf(1.0, float(mine.size()))
	_chapter_bar.color = P.CYAN
	_set_rows(mine)

func _goals() -> Array:
	var d = hud.data
	if d.has_helper("goals", "list"):
		return hud.main.sim.goals.list()
	# Derived from content + state.goals.status.
	var out: Array = []
	var ch: Array = d.chapters()
	var ci: int = d.chapter_index()
	for i in ch.size():
		for g in ch[i].get("goals", []):
			var s: Dictionary = d.goal_status(String(g["id"]))
			out.append({"id": g["id"], "name": g["name"], "desc": g.get("desc", ""), "hint": g.get("hint", ""), "chapter": i,
				"state": String(s.get("state", "active" if i == ci else ("done" if i < ci else "locked"))),
				"value": float(s.get("value", 0.0)), "target": float(s.get("target", 0.0)), "since": int(s.get("since", -1)),
				"sustain": float(g.get("sustain", 0)), "done_tick": int(s.get("done_tick", -1)), "reward": g.get("reward", {})})
	return out

func _set_rows(goals: Array) -> void:
	var sig := ""
	for g in goals:
		sig += String(g["id"]) + ","
	if sig != _sig:
		_sig = sig
		Kit.clear(_list)
		_rows = {}
		for g in goals:
			var row: Dictionary = _make_row(g)
			_list.add_child(row["root"])
			_rows[String(g["id"])] = row
	for g in goals:
		if _rows.has(String(g["id"])):
			_update_row(_rows[String(g["id"])], g)

func _make_row(g: Dictionary) -> Dictionary:
	var root: VBoxContainer = Kit.vbox(3)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	var top: HBoxContainer = Kit.hbox(7)
	root.add_child(top)
	var icon: TextureRect = Kit.icon("sev_info", 16, P.TEXT_3)
	top.add_child(icon)
	var name: Label = Kit.label(String(g["name"]), "BodyStrong", 14)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	top.add_child(name)
	var val: Label = Kit.num("", 12, P.TEXT_2)
	top.add_child(val)
	var bar = Kit.bar(0.0, P.CYAN, 5.0)
	var bar_row: HBoxContainer = Kit.hbox(0)
	bar_row.custom_minimum_size.x = 300
	bar_row.add_child(Kit.gap(23))
	bar_row.add_child(bar)
	root.add_child(bar_row)
	var info: Label = Kit.label("", "SmallLabel", 11, P.TEXT_2)
	info.clip_text = true
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info_row: HBoxContainer = Kit.hbox(0)
	info_row.add_child(Kit.gap(23))
	info_row.add_child(info)
	root.add_child(info_row)
	var tip: String = "%s\n%s" % [g["name"], g.get("desc", "")]
	if String(g.get("hint", "")) != "":
		tip += "\nHint: " + String(g["hint"])
	var rw: String = _reward_text(g.get("reward", {}))
	if rw != "":
		tip += "\nReward: " + rw
	root.tooltip_text = tip
	return {"root": root, "icon": icon, "name": name, "val": val, "bar": bar, "info": info}

func _update_row(r: Dictionary, g: Dictionary) -> void:
	var state: String = String(g.get("state", "active"))
	var value: float = float(g.get("value", 0.0))
	var target: float = float(g.get("target", 0.0))
	var frac: float = clampf(value / target, 0.0, 1.0) if target > 0.0 else (1.0 if value > 0.0 else 0.0)
	var sustain: float = float(g.get("sustain", 0.0))
	var since: int = int(g.get("since", -1))
	var info := ""
	var col: Color = P.CYAN
	if state == "done":
		Kit.set_icon(r["icon"], "sev_ok", 16, P.GREEN)
		(r["name"] as Label).add_theme_color_override("font_color", P.TEXT_2)
		frac = 1.0
		col = P.GREEN
		info = "Done. " + _reward_text(g.get("reward", {}))
	else:
		(r["name"] as Label).add_theme_color_override("font_color", P.TEXT)
		if sustain > 0.0 and since >= 0:
			var held: float = float(int(hud.main.sim.state["tick"]) - since) / float(hud.main.sim.bal["tick_hz"])
			info = "Holding %s of %s" % [Kit.clock(held), Kit.clock(sustain)]
			frac = clampf(held / sustain, 0.0, 1.0)
			col = P.GREEN
			Kit.set_icon(r["icon"], "clock", 16, P.GREEN)
		else:
			Kit.set_icon(r["icon"], "sev_info" if frac < 1.0 else "clock", 16, P.CYAN if frac > 0.0 else P.TEXT_3)
			info = String(g.get("desc", ""))
			if bool(Settings.get_value("tutorial_tips")) and String(g.get("hint", "")) != "":
				info = "Tip: " + String(g["hint"])
			if sustain > 0.0:
				info = "Needs %s without a break." % Kit.clock(sustain)
	(r["val"] as Label).text = _value_text(value, target, _kind(String(g["id"])))
	r["bar"].value = frac
	r["bar"].color = col
	(r["info"] as Label).text = info

var _kinds := {}

func _kind(id: String) -> String:
	if _kinds.is_empty():
		for ch in hud.data.chapters():
			for g in ch.get("goals", []):
				_kinds[String(g["id"])] = String(g.get("kind", ""))
	return String(_kinds.get(id, ""))

## Goal values in the words of their kind: ratios as %, supplies in days, flags as yes/no.
func _value_text(v: float, t: float, kind: String = "") -> String:
	if t <= 0.0:
		return ""
	match kind:
		"o2_ratio":
			return "%d%% / %d%%" % [int(roundf(v * 100.0)), int(roundf(t * 100.0))]
		"water_days", "dish_days":
			return "%.1f / %.1f d" % [v, t]
		"ship_readiness":
			return "%d%% / %d%%" % [int(v), int(t)]
	if absf(t - 1.0) < 0.001 and v <= 1.0:
		return "yes" if v >= t else "no"
	return "%s / %s" % [Kit.fmt(v), Kit.fmt(t)]

func _reward_text(rw: Dictionary) -> String:
	var parts: Array = []
	for it in rw.get("items", {}):
		parts.append("%d %s" % [int(rw["items"][it]), hud.data.item_name(String(it)).to_lower()])
	if float(rw.get("rp", 0)) > 0.0:
		parts.append("%d RP" % int(rw["rp"]))
	return ", ".join(parts)

# ---------------------------------------------------------------- version 1 fallback
func _refresh_tutorial() -> void:
	var step: int = int(hud.main.sim.state["progress"]["tutorial_step"])
	var steps: Array = Metrics.TUTORIAL
	_sub.text = "GETTING STARTED"
	_chapter_bar.value = float(step) / float(steps.size())
	_count.text = "%d/%d" % [mini(step, steps.size()), steps.size()]
	var sig := "tut:%d" % step
	if sig == _sig:
		return
	_sig = sig
	Kit.clear(_list)
	_rows = {}
	if step >= steps.size():
		_head.text = "TUTORIAL COMPLETE"
		_list.add_child(Kit.wrap("The outpost is yours. Open the colony dashboard (C) for the next stage.", 13))
		return
	_head.text = String(steps[step]["title"]).to_upper()
	_list.add_child(Kit.wrap(String(steps[step]["text"]), 13, P.TEXT))
