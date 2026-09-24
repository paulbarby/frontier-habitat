extends PanelContainer
## Left column, below the goals: incidents from sim.alerts.incidents(). Each card says
## what is failing (severity icon + word), why, how long is left, what to do, and hangs
## the consequences under the root cause. "Show" moves the camera to the cause.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

const MAX_CARDS := 4
var _max := MAX_CARDS

var hud
var _title: Label
var _summary: Label
var _icon: TextureRect
var _list: VBoxContainer
var _more: Label
var _sig := ""
var _cards: Array = []
var _open := {}          # issue key -> consequences expanded

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 8
	offset_top = 300
	custom_minimum_size.x = 334
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	var top: HBoxContainer = Kit.hbox(8)
	v.add_child(top)
	_icon = Kit.icon("sev_ok", 18, P.GREEN)
	top.add_child(_icon)
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	_title = Kit.head("Alerts", P.TEXT_3, 11)
	tv.add_child(_title)
	_summary = Kit.head("All systems normal", P.GREEN, 13, "head_wide")
	tv.add_child(_summary)
	_list = Kit.vbox(6)
	v.add_child(_list)
	_more = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	_more.visible = false
	v.add_child(_more)

func _process(_delta: float) -> void:
	# Sit under the goals tracker, whatever its height, and above the minimap: when the
	# cards do not fit, fewer are shown (the rest are counted).
	if hud == null or hud.goals == null:
		return
	Kit.fit(self)
	var g: Control = hud.goals
	position.y = g.position.y + g.size.y + 8.0
	var floor_y: float = hud.minimap.position.y - 8.0
	if position.y + size.y > floor_y and _max > 1 and _cards.size() > 1:
		_max -= 1
		_sig = ""
	elif position.y + size.y < floor_y - 170.0 and _max < MAX_CARDS:
		_max += 1
		_sig = ""
	visible = position.y + 40.0 < floor_y

func rebuild() -> void:
	_sig = ""
	_open = {}
	refresh()

func refresh() -> void:
	# The gate (ui/hud/alert_gate.gd) gives a steady list: a stable order, and an alert that
	# clears stays a short time as "cleared", so a key that goes on and off is one card.
	var inc: Array = hud.watchers.gate.display(hud.main.sim.alerts.incidents()) if hud.watchers != null else hud.main.sim.alerts.incidents()
	var live: Array = []
	for i in inc:
		if not bool(i.get("cleared", false)):
			live.append(i)
	var crit := 0
	var warn := 0
	for i in live:
		var sv: int = int(i["issue"]["severity"])
		if sv >= 3:
			crit += 1
		elif sv == 2:
			warn += 1
	if live.is_empty():
		_summary.text = "ALL SYSTEMS NORMAL"
		_summary.add_theme_color_override("font_color", P.GREEN)
		Kit.set_icon(_icon, "sev_ok", 18, P.GREEN)
	else:
		var parts: Array = []
		if crit > 0:
			parts.append("%d critical" % crit)
		if warn > 0:
			parts.append(Kit.plural(warn, "warning"))
		var notes: int = live.size() - crit - warn
		if notes > 0:
			parts.append(Kit.plural(notes, "notice"))
		_summary.text = "  ·  ".join(parts).to_upper()
		var worst: int = 3 if crit > 0 else (2 if warn > 0 else 1)
		_summary.add_theme_color_override("font_color", P.sev(worst))
		Kit.set_icon(_icon, P.sev_icon(worst), 18, P.sev(worst))
	var shown: Array = inc.slice(0, _max)
	var sig := ""
	for i in shown:
		sig += "%s:%d:%d:%s|" % [i["issue"]["key"], i["issue"]["severity"], (i["consequences"] as Array).size(), _open.has(i["issue"]["key"])]
	if sig != _sig:
		_sig = sig
		Kit.clear(_list)
		_cards = []
		for i in shown:
			var card: Dictionary = _make_card(i)
			_list.add_child(card["root"])
			_cards.append(card)
	for k in mini(_cards.size(), shown.size()):
		_update_card(_cards[k], shown[k])
	_more.visible = inc.size() > shown.size()
	_more.text = "%s not shown. The dashboard lists every one." % Kit.plural(inc.size() - shown.size(), "more alert")

func _make_card(i: Dictionary) -> Dictionary:
	var issue: Dictionary = i["issue"]
	var sev: int = int(issue["severity"])
	var col: Color = P.sev(sev)
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(col.r, col.g, col.b, 0.07)
	st.border_color = Color(col.r, col.g, col.b, 0.9)
	st.border_width_left = 3
	st.content_margin_left = 9
	st.content_margin_right = 6
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var v: VBoxContainer = Kit.vbox(3)
	card.add_child(v)
	var top: HBoxContainer = Kit.hbox(6)
	v.add_child(top)
	top.add_child(Kit.icon(P.sev_icon(sev), 15, col))
	var word: Label = Kit.head(P.sev_word(sev), col, 11)
	top.add_child(word)
	var sp: Control = Kit.spacer()
	top.add_child(sp)
	var left: Label = Kit.num("", 12, col, true)
	top.add_child(left)
	var ents: Array = issue["entities"]
	if not ents.is_empty():
		var first: int = int(ents[0])
		var show: Button = Kit.icon_button("target", func(): _focus(first), "Show\nMoves the camera to the cause and selects it.", "GhostButton", 14, 24)
		top.add_child(show)
	var text: Label = Kit.wrap(String(issue["text"]), 13, P.TEXT)
	text.custom_minimum_size.x = 290
	v.add_child(text)
	var act: Label = Kit.wrap("Do: " + String(issue["action"]), 12, P.TEXT_2)
	act.custom_minimum_size.x = 290
	v.add_child(act)
	var cons: Array = i["consequences"]
	var cons_box: VBoxContainer = Kit.vbox(2)
	v.add_child(cons_box)
	var key: String = String(issue["key"])
	if not cons.is_empty():
		var tog: Button = Kit.button("%s %d consequence%s" % ["Hide" if _open.has(key) else "Show", cons.size(), "" if cons.size() == 1 else "s"],
			func(): _toggle(key), "", "GhostButton", "chevron_up" if _open.has(key) else "chevron_down", 12)
		tog.custom_minimum_size.y = 22
		tog.add_theme_font_size_override("font_size", 11)
		tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(tog)
		if _open.has(key):
			for c in cons.slice(0, 5):
				var row: HBoxContainer = Kit.hbox(5)
				row.add_child(Kit.icon("arrow_right", 11, P.sev(int(c["severity"]))))
				var cl: Label = Kit.wrap(String(c["text"]), 12, P.TEXT_2)
				cl.custom_minimum_size.x = 270
				row.add_child(cl)
				cons_box.add_child(row)
	return {"root": card, "left": left, "text": text}

func _update_card(c: Dictionary, i: Dictionary) -> void:
	var issue: Dictionary = i["issue"]
	var f: float = float(issue.get("forecast", -1.0))
	# cleared: held by the interface gate; live false: the simulation waits 30 s before it
	# removes an alert whose condition has ended (V3_DESIGN §2).
	var cleared: bool = bool(i.get("cleared", false)) or not bool(issue.get("live", true))
	if cleared:
		(c["left"] as Label).text = "CLEARED" if bool(i.get("cleared", false)) else "CLEARING"
	else:
		(c["left"] as Label).text = (Kit.clock(f) + " left") if f >= 0.0 else ""
	(c["text"] as Label).text = String(issue["text"])
	(c["root"] as Control).modulate.a = 0.5 if cleared else 1.0

func _toggle(key: String) -> void:
	if _open.has(key):
		_open.erase(key)
	else:
		_open[key] = true
	_sig = ""
	refresh()

func _focus(id: int) -> void:
	var st: Dictionary = hud.main.sim.state
	if st["buildings"].has(id):
		hud.main.focus_on(st["buildings"][id]["pos"])
		hud.main.select("building", id)
	elif st["agents"].has(id):
		hud.main.focus_on(st["agents"][id]["pos"])
		hud.main.select("agent", id)
