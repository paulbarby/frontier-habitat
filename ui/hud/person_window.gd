extends PanelContainer
## Personnel file (V5_DESIGN §6.2, §10): one person. Tabs:
##   File     portrait, rank, role, home, skills (levels 1-5), satisfaction with its parts and reasons,
##            attitude with reasons, the last lines they said.
##   Social   the relationship web (a small graph round the person) and the list: partner, friends,
##            enemies; a crush shows only when it is known (from the Rag or the bubbles).
##   Review   write a review (Excellent .. Poor) and discipline or reward. Every action shows the
##            predicted effect on the person and on others, then asks to confirm.
## Buttons: Follow (the follow view), Show (camera). A window of the window manager.
## Data: ui/v5_data.gd (SIM sim.people / sim.social; predictions from SIM or the V5 §6.3 table).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const Icons = preload("res://ui/theme/icons.gd")
const RagPhoto = preload("res://ui/widgets/rag_photo.gd")
const V5 = preload("res://ui/v5_data.gd")

const WIDTH := 520.0
const COMP_NAME := {"needs": "Needs", "food": "Food", "housing": "Housing", "comfort": "Leisure", "social": "Friends", "work": "Work",
	"fairness": "Fairness", "safety": "Safety", "freedom": "Freedom"}
const MOOD := ["Very unhappy", "Unhappy", "So-so", "Content", "Happy"]

var hud
var agent_id := -1
var tab := "file"
var _head: HBoxContainer
var _title: Label
var _sub: Label
var _tabs: HBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _sig := ""
var _t := 0.0
var last_result: Dictionary = {}     # tests

func _ready() -> void:
	var st = GlassFrame.new()
	st.kind = "window"
	st.header_h = 58.0
	st.content_margin_left = 18
	st.content_margin_right = 20
	st.content_margin_top = 10
	st.content_margin_bottom = 14
	st.accent = Color(P.CYAN.r, P.CYAN.g, P.CYAN.b, 0.9)
	# Critic round 30, fix 1: the file is lists, tables and a graph: the darker reading glass (about 88 %).
	st.tint_top = Color(0.05, 0.09, 0.15, 0.86)
	st.tint_bottom = Color(0.03, 0.05, 0.09, 0.90)
	add_theme_stylebox_override("panel", st)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	_head = Kit.hbox(10)
	_head.custom_minimum_size.y = 38
	v.add_child(_head)
	_head.add_child(Kit.icon("colonists", 22, P.CYAN))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(tv)
	_title = Kit.head("PERSONNEL FILE", P.TEXT, 16, "head_wide")
	tv.add_child(_title)
	_sub = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	tv.add_child(_sub)
	_head.add_child(Kit.icon_button("follow", func(): hud.main.follow_person(agent_id), "Follow\nThe camera goes behind this person (key V). Esc ends it.", "GhostButton", 16, 30))
	_head.add_child(Kit.icon_button("target", func(): _show_person(), "Show\nMoves the camera to this person.", "GhostButton", 16, 30))
	_head.add_child(Kit.icon_button("close", func(): visible = false, "Close\nEsc.", "GhostButton", 16, 30))
	_tabs = Kit.hbox(4)
	v.add_child(_tabs)
	for t in [["file", "File"], ["social", "Social"], ["review", "Review"]]:
		var id: String = t[0]
		var b: Button = Kit.button(t[1], func(): set_tab(id), "%s\nShows this page of the personnel file." % t[1], "TabButton")
		b.toggle_mode = true
		b.set_meta("tab", id)
		_tabs.add_child(b)
	_body = Kit.vbox(10)
	_scroll = Kit.scroll(_body)
	_scroll.custom_minimum_size = Vector2(WIDTH - 40.0, 440)
	v.add_child(_scroll)

func register_window(wm) -> void:
	# Critic round 30, fix 2: the file opens in the inspector's place (top right); the inspector hides
	# while it shows (inspector.gd refresh), so one person has one window.
	wm.register(self, "person", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y))

func wm_close() -> void:
	visible = false

func open(id: int, t: String = "") -> void:
	agent_id = id
	if t != "":
		tab = t
	_sig = ""
	refresh(true)
	visible = true
	# The first layout can be wider than the content (wrapped labels settle a frame later): shrink
	# to the content, then place again, so the file sits exactly in the inspector's place.
	_settle.call_deferred()

func _settle() -> void:
	await get_tree().process_frame
	reset_size()
	if hud.wm != null and hud.wm.has_method("place"):
		hud.wm.place("person")

func set_tab(t: String) -> void:
	tab = t
	_sig = ""
	refresh(true)

func _show_person() -> void:
	var a: Dictionary = hud.v5.agent(agent_id)
	if not a.is_empty():
		hud.main.select("agent", agent_id)
		hud.main.focus_on(a["pos"])

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 1.0:
		_t = 0.0
		refresh()

func refresh(force: bool = false) -> void:
	var p: Dictionary = hud.v5.person(agent_id)
	for b in _tabs.get_children():
		(b as Button).set_pressed_no_signal(String(b.get_meta("tab")) == tab)
	if p.is_empty():
		Kit.clear(_body)
		_title.text = "PERSONNEL FILE"
		_sub.text = ""
		_body.add_child(Kit.wrap("No person. Select a colonist and open the file (the Personnel file button).", 14, P.TEXT_2))
		_fit()
		return
	var sig: String = "%s:%d:%d:%d:%s" % [tab, agent_id, int(p["satisfaction"]["value"]), int(p["attitude"]["value"]), p["activity"]]
	if sig == _sig and not force:
		return
	_sig = sig
	var idn: Dictionary = p["identity"]
	_title.text = String(p["name"]).to_upper()
	_sub.text = "%s  ·  %s  ·  age %d" % [String(p["rank"]["title"]), _role_name(String(p["role"])), int(idn["age"])]
	var keep: int = _scroll.scroll_vertical
	Kit.clear(_body)
	match tab:
		"social": _social(p)
		"review": _review(p)
		_: _file(p)
	_fit()
	_scroll.scroll_vertical = keep

func _fit() -> void:
	var room: float = hud.wm.work_area().size.y - 150.0 if hud.wm != null else 500.0
	_scroll.custom_minimum_size.y = clampf(_body.get_combined_minimum_size().y + 8.0, 120.0, maxf(160.0, room))
	Kit.fit(self)

func _role_name(r: String) -> String:
	return String(hud.main.sim.bal.get("role_names", {}).get(r, r.capitalize()))

# ---------------------------------------------------------------- File
func _file(p: Dictionary) -> void:
	var idn: Dictionary = p["identity"]
	var top: HBoxContainer = Kit.hbox(14)
	_body.add_child(top)
	var ph = RagPhoto.new()
	ph.custom_minimum_size = Vector2(150, 150)
	ph.pose = "portrait"
	ph.texture = hud.v5.photo([agent_id], "portrait", "portrait")
	top.add_child(ph)
	var g: GridContainer = Kit.grid(2, 12, 4)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(g)
	var tr: Array = []
	for t in idn["traits"]:
		tr.append(String(t))
	var home: Dictionary = p["home"]
	for row in [["Rank", String(p["rank"]["title"])], ["Role", _role_name(String(p["role"]))], ["Department", String(p["rank"]["department"]).capitalize()],
			["Traits", ", ".join(tr)], ["Home", "%s (quality %d of 4)" % [String(home.get("kind", "none")).capitalize(), int(home.get("quality", 0))]],
			["Doing", String(p["activity"])], ["Wears", V5.outfit_name(String(p["outfit"]))]]:
		g.add_child(Kit.dim(row[0], 13))
		var l: Label = Kit.wrap(String(row[1]), 13, P.TEXT)
		l.custom_minimum_size.x = 200
		g.add_child(l)
	# Satisfaction
	var sat: Dictionary = p["satisfaction"]
	var sv: float = float(sat["value"])
	var sec: VBoxContainer = _section("Satisfaction", "morale")
	var sr: HBoxContainer = Kit.bar_row(MOOD[V5.mood(sv)], sv / 100.0, "%d" % int(sv), P.level(sv, 50.0, 30.0), 110.0)
	sec.add_child(sr)
	# The 9 parts on one 0-100 track each, worst first; the mark is 50 (neutral); the reason beside it
	# (critic round 30, fix 7).
	var why := {}
	for rs in sat.get("reasons", []):
		if rs.has("component") and not why.has(String(rs["component"])):
			why[String(rs["component"])] = String(rs["text"])
	var keys: Array = COMP_NAME.keys()
	keys.sort_custom(func(x, y): return float(sat["components"].get(x, 50.0)) < float(sat["components"].get(y, 50.0)))
	var parts: VBoxContainer = Kit.vbox(3)
	parts.name = "SatParts"
	sec.add_child(parts)
	for k in keys:
		var cv: float = float(sat["components"].get(k, 50.0))
		var r: HBoxContainer = Kit.bar_row(String(COMP_NAME[k]), cv / 100.0, "%d" % int(cv), P.level(cv, 50.0, 30.0), 80.0, 0.5)
		r.set_meta("part", k)
		r.set_meta("value", cv)
		r.tooltip_text = "%s: %d of 100\nThe mark is 50 (neutral). %s" % [COMP_NAME[k], int(cv), why.get(k, "")]
		var wl: Label = Kit.label(String(why.get(k, "")), "SmallLabel", 12, P.TEXT_2 if cv >= 50.0 else P.AMBER)
		wl.custom_minimum_size.x = 170
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # critic round 36: a reason is never cut
		wl.name = "Reason"
		r.add_child(wl)
		parts.add_child(r)
	# Attitude
	var att: Dictionary = p["attitude"]
	var av: float = float(att["value"])
	var sec2: VBoxContainer = _section("Attitude", "trend_up" if float(att.get("trend", 0.0)) >= 0.0 else "trend_down")
	var word: String = "Very bad" if av <= -70.0 else ("Bad" if av <= -30.0 else ("Fair" if av < 20.0 else "Good"))
	sec2.add_child(Kit.bar_row(word, (av + 100.0) / 200.0, "%+d" % int(av), P.level(av + 50.0, 50.0, 20.0), 110.0))
	if av <= -30.0:
		sec2.add_child(Kit.wrap("Bad attitude: slower work, long breaks, backtalk%s." % (", may start protests and fights" if av <= -70.0 else ""), 13, P.AMBER))
	for rs in (att.get("reasons", []) as Array).slice(0, 4):
		sec2.add_child(_reason(String(rs["text"]), float(rs["delta"])))
	# Skills
	var sec3: VBoxContainer = _section("Skills", "research")
	var sk: Dictionary = p["skills"]
	var names: Array = sk.keys()
	names.sort_custom(func(x, y): return float(sk[x]) > float(sk[y]))
	var sg: GridContainer = Kit.grid(2, 14, 3)
	sec3.add_child(sg)
	var s = hud.main.sim
	for n in names:
		var v: float = float(sk[n])
		var lv: int = int(s.people.level_of(v))
		var r2: HBoxContainer = Kit.bar_row(String(n).capitalize(), v / 100.0, "L%d %s" % [lv, String(s.people.level_name(v))], [P.TEXT_3, P.TEXT_2, P.CYAN, P.GREEN, P.GOLD][clampi(lv - 1, 0, 4)], 90.0)
		r2.custom_minimum_size.x = 225
		sg.add_child(r2)
	# What they said
	var lines: Array = hud.v5.recent_lines(agent_id, 3)
	if not lines.is_empty():
		var sec4: VBoxContainer = _section("Said lately", "info")
		for ln in lines:
			sec4.add_child(Kit.wrap("\"%s\"" % String(ln.get("text", "")), 13, P.TEXT_2))

func _reason(text: String, d: float) -> Control:
	var h: HBoxContainer = Kit.hbox(6)
	h.add_child(Kit.icon("trend_up" if d >= 0.0 else "trend_down", 12, P.GREEN if d >= 0.0 else P.AMBER))
	var l: Label = Kit.label(text, "", 13, P.TEXT_2)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(Kit.num("%+d" % int(roundf(d)), 12, P.GREEN if d >= 0.0 else P.AMBER))
	return h

func _section(title: String, icon: String) -> VBoxContainer:
	_body.add_child(Kit.sep())
	var v: VBoxContainer = Kit.vbox(4)
	var hh: HBoxContainer = Kit.hbox(6)
	hh.add_child(Kit.icon(icon, 14, P.CYAN))
	hh.add_child(Kit.head(title, P.CYAN, 12))
	v.add_child(hh)
	_body.add_child(v)
	return v

# ---------------------------------------------------------------- Social
const STATUS_COLOR := {"best_friend": Color("6EE7A8"), "friend": Color("4FC3F7"), "acquaintance": Color("9AA7B4"), "rival": Color("FFB547"),
	"enemy": Color("FF5A5F"), "crush": Color("F472B6"), "dating": Color("F472B6"), "partners": Color("F472B6"), "married": Color("FFD166"), "ex": Color("8B7F9E"), "affair": Color("E11D48")}

class Web extends Control:
	var rows: Array = []
	var names := {}
	var center_name := ""
	var colors := {}
	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var font: Font = get_theme_default_font()
		var n: int = rows.size()
		for i in n:
			var r: Dictionary = rows[i]
			var ang: float = -PI * 0.5 + TAU * float(i) / float(maxi(1, n))
			var dist: float = minf(size.x, size.y) * 0.5 - 26.0
			var q: Vector2 = c + Vector2(cos(ang), sin(ang)) * dist * (1.0 - clampf(absf(float(r["affinity"])) / 250.0, 0.0, 0.35))
			var col: Color = colors.get(String(r["status"]), Color("9AA7B4"))
			draw_line(c, q, Color(col.r, col.g, col.b, 0.75), 1.0 + absf(float(r["affinity"])) / 30.0, true)
			draw_circle(q, 7.0, Color(0.05, 0.08, 0.12, 0.95))
			draw_arc(q, 7.0, 0.0, TAU, 20, col, 2.0, true)
			var nm: String = String(names.get(int(r["other"]), "?"))
			var w: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var tp: Vector2 = q + Vector2(-w * 0.5, 22.0 if q.y >= c.y else -12.0)
			draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 1.0))
		draw_circle(c, 11.0, Color(0.10, 0.34, 0.44))
		draw_arc(c, 11.0, 0.0, TAU, 24, Color("3EE0FF"), 2.0, true)
		var w0: float = font.get_string_size(center_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, c + Vector2(-w0 * 0.5, 30.0), center_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

func _social(p: Dictionary) -> void:
	var rel: Array = hud.v5.relations(agent_id, 10)
	var shown: Array = []
	for r in rel:
		if String(r["status"]) == "crush" and not bool(r.get("known", false)):
			continue   # a crush is secret until the Rag or a bubble tells (V5 §10)
		shown.append(r)
	var web := Web.new()
	web.custom_minimum_size = Vector2(WIDTH - 60.0, 260)
	web.rows = shown
	web.colors = STATUS_COLOR
	web.center_name = String(p["name"]).get_slice(" ", 0)
	for r in shown:
		web.names[int(r["other"])] = hud.v5.agent_name(int(r["other"])).get_slice(" ", 0)
	web.name = "Web"
	_body.add_child(web)
	if shown.is_empty():
		_body.add_child(Kit.wrap("Knows nobody well yet. People meet at meals, at work and in leisure places.", 14, P.TEXT_2))
		return
	var sec: VBoxContainer = _section("Relationships", "people")
	for r in shown:
		var h: HBoxContainer = Kit.hbox(8)
		var st: String = String(r["status"])
		h.add_child(Kit.badge(String(V5.STATUS_NAME.get(st, st)).to_upper(), STATUS_COLOR.get(st, P.TEXT_2)))
		var oid: int = int(r["other"])
		var b: Button = Kit.button(hud.v5.agent_name(oid), func(): open(oid), "%s\nOpens their personnel file." % hud.v5.agent_name(oid), "GhostButton")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(b)
		h.add_child(Kit.num("%+d" % int(r["affinity"]), 12, P.GREEN if float(r["affinity"]) >= 0.0 else P.AMBER))
		h.tooltip_text = "Affinity %+d of 100%s" % [int(r["affinity"]), (". Attraction %d" % int(r["attraction"])) if float(r.get("attraction", 0.0)) > 0.0 and bool(r.get("known", true)) else ""]
		sec.add_child(h)
	var hidden: int = rel.size() - shown.size()
	if hidden > 0:
		_body.add_child(Kit.wrap("Some feelings are secret. The Rag and what people say tell you more.", 12, P.TEXT_3))

# ---------------------------------------------------------------- Review and discipline
func _review(p: Dictionary) -> void:
	var sec: VBoxContainer = _section("Write a review", "edit")
	sec.add_child(Kit.wrap("A review changes how %s feels about the work. It depends on their traits." % String(p["name"]).get_slice(" ", 0), 13, P.TEXT_2))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	sec.add_child(row)
	for rv in V5.REVIEWS:
		var k: String = rv[0]
		var nm: String = rv[1]
		row.add_child(Kit.button(nm, func(): _ask(k, nm, "review"), _pred_tip(k, nm), "", "", 14))
	var sec2: VBoxContainer = _section("Discipline and rewards", "orders")
	sec2.add_child(Kit.wrap("Punishment works now and costs later: friends see it, and unfair punishment raises unrest.", 13, P.TEXT_2))
	for ac in V5.ACTIONS:
		var k2: String = ac[0]
		var nm2: String = ac[1]
		var h: HBoxContainer = Kit.hbox(8)
		var pr: Dictionary = hud.v5.predict(agent_id, k2)
		var good: bool = int(pr.get("satisfaction", 0)) >= 0
		var b: Button = Kit.button(nm2, func(): _ask(k2, nm2, "discipline"), _pred_tip(k2, nm2), "" if good else "DangerButton", "", 14)
		b.custom_minimum_size.x = 170
		b.set_meta("action", k2)
		h.add_child(b)
		# Two lines: what it is, then the predicted effect (green: satisfaction up, red: down).
		var lv: VBoxContainer = Kit.vbox(0)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l: Label = Kit.label(String(ac[2]), "SmallLabel", 12, P.TEXT_2)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lv.add_child(l)
		var l2: Label = Kit.label("attitude %+d, satisfaction %+d%s" % [int(pr.get("attitude", 0)), int(pr.get("satisfaction", 0)), "  (estimate)" if bool(pr.get("estimate", false)) else ""], "SmallLabel", 12, P.GREEN if good else P.RED)
		l2.clip_text = true
		lv.add_child(l2)
		h.add_child(lv)
		sec2.add_child(h)

func _pred_tip(k: String, nm: String) -> String:
	var pr: Dictionary = hud.v5.predict(agent_id, k)
	var t: Array = []
	for d in _pred_lines(pr, k):
		t.append("%s: %s" % [String(d["head"]), String(d["text"])])
	return "%s\n%s" % [nm, "\n".join(t)]

## The confirm's lines (critic round 30, fix 3): the effect on the person, on others (who sees it),
## the risk, and the "unfair" warning.
func _pred_lines(pr: Dictionary, k: String = "") -> Array:
	var first: String = hud.v5.agent_name(agent_id).get_slice(" ", 0)
	var sat: int = int(pr.get("satisfaction", 0))
	var out: Array = [{"head": "On %s" % first, "text": "Attitude %+d, satisfaction %+d.%s" % [int(pr.get("attitude", 0)), sat, "  (An estimate from their traits.)" if bool(pr.get("estimate", false)) else ""],
		"color": P.GREEN if sat >= 0 else P.RED, "icon": "colonists"}]
	var seen: Array = hud.v5.witnesses(agent_id)
	var oth: String = String(pr.get("others", ""))
	if oth == "" or oth == "None.":
		oth = "No effect."
	if not seen.is_empty():
		oth += " Who sees it: %s." % ", ".join(seen)
	out.append({"head": "On others", "text": oth, "color": P.CYAN, "icon": "people"})
	if String(pr.get("risk", "")) != "":
		out.append({"head": "Risk", "text": String(pr["risk"]), "color": P.AMBER, "icon": "sev_warning"})
	var uf: String = hud.v5.unfair(agent_id, k, pr)
	if uf != "":
		out.append({"head": "Unfair", "text": uf, "color": P.RED, "icon": "sev_critical"})
	return out

## The predicted effect, then a confirm; then the order to SIM.
func _ask(k: String, nm: String, cmd: String) -> void:
	var pr: Dictionary = hud.v5.predict(agent_id, k)
	var who: String = hud.v5.agent_name(agent_id)
	var danger: bool = int(pr.get("satisfaction", 0)) < 0
	hud.confirm("%s: %s?" % [nm, who], _pred_lines(pr, k), func():
		var payload := {"agent": agent_id}
		if cmd == "review":
			payload["grade"] = k
		else:
			payload["action"] = k
		last_result = hud.v5.command(cmd, payload)
		hud.toast("%s: %s" % [nm, String(last_result.get("text", ""))], "info" if bool(last_result.get("ok", false)) else "warn", "colonists")
		_sig = "", nm, danger)
