extends PanelContainer
## Ship traffic (docs/V3_1_DESIGN.md §6.5), under the hazard panel, right of the goals.
## One card per arrival that the player can see (forecast one day ahead) and per ship in orbit,
## landing, landed, boarding or taking off: kind icon, name, phase, countdown, SIM's one-line
## offer, what it brings and wants, and the choices: Grant / Deny (until it lands), Settlers
## (shuttle), Trade (landed trader or science ship). A click on a card with a pad moves the
## camera there. Hidden when there are no ships, so it costs no draw calls then.
## Cards are rebuilt only when the set of ships, their phases or answers change.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

const MAX_CARDS := 3
const WIDTH := 318.0

var hud
var collapsed := false
var _head: Label
var _sub: Label
var _chev: Button
var _list: VBoxContainer
var _more: Label
var _sig := ""
var _cards: Array = []
var rows_now: Array = []
var _notes := {}        # arrival id -> [notice texts] (SIM traffic notices, by ship kind)
var _loose: Label       # notices with no ship on show

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 282
	offset_top = 58
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(7)
	add_child(v)
	var head: HBoxContainer = Kit.hbox(7)
	v.add_child(head)
	head.add_child(Kit.icon("ship", 16, P.CATEGORY["space"]))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	_head = Kit.head("Traffic", P.TEXT_3, 11)
	tv.add_child(_head)
	_sub = Kit.head("", P.CYAN, 13, "head_wide")
	tv.add_child(_sub)
	_chev = Kit.icon_button("chevron_up", func(): _toggle(), "Hide or show the ship cards.", "GhostButton", 14, 26)
	head.add_child(_chev)
	_list = Kit.vbox(6)
	v.add_child(_list)
	_more = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	_more.visible = false
	v.add_child(_more)
	_loose = Kit.wrap("", 12, P.AMBER, WIDTH - 30.0)
	_loose.visible = false
	v.add_child(_loose)

func _process(_delta: float) -> void:
	if hud == null or hud.goals == null or not visible:
		return
	Kit.fit(self)
	var g: Control = hud.goals
	position.x = g.position.x + g.size.x + 10.0
	var hp: Control = hud.hazard
	position.y = (hp.position.y + hp.size.y + 8.0) if hp != null and hp.visible else 58.0

func rebuild() -> void:
	_sig = ""
	refresh()

func _toggle() -> void:
	collapsed = not collapsed
	_chev.icon = Icons.tex("chevron_down" if collapsed else "chevron_up", 14)
	_sig = ""
	refresh()

## Ships on the way down, on a pad or leaving first, then the forecast, soonest first.
func rows() -> Array:
	var d = hud.data
	var out: Array = []
	for r in d.traffic_ships():
		if not ["gone", "denied", "left"].has(String(r.get("phase", ""))):
			out.append(r)
	var fc: Array = d.traffic_forecast()
	fc.sort_custom(func(a, b): return float(a.get("eta_s", 0.0)) < float(b.get("eta_s", 0.0)))
	out.append_array(fc)
	return out

func refresh() -> void:
	var d = hud.data
	rows_now = rows()
	var show: bool = not rows_now.is_empty()
	if show != visible:
		visible = show
	if not show:
		_sig = ""
		return
	var landed := 0
	for r in rows_now:
		if String(r.get("phase", "")) == "landed":
			landed += 1
	_head.text = ("TRAFFIC  ·  %d landed  ·  %d coming" % [landed, rows_now.size() - landed]) if landed > 0 else ("TRAFFIC  ·  %d coming" % rows_now.size())
	var first: Dictionary = rows_now[0]
	_sub.text = ("%s  %s" % [String(first.get("name", "")), when_text(first)]).to_upper()
	# SIM notices (tourists with no bed, ...): under the first ship of their kind that stands on a pad
	# or is landing; if there is none, at the bottom of the panel.
	_notes = {}
	var loose: Array = []
	for n in d.traffic_notices():
		var kind: String = d.notice_kind(String(n.get("code", "")))
		var owner := -1
		for r in rows_now:
			if String(r.get("kind", "")) == kind and ["landing", "landed", "boarding"].has(String(r.get("phase", ""))):
				owner = int(r["id"])
				break
		if owner == -1:
			loose.append(String(n.get("text", "")))
		else:
			if not _notes.has(owner):
				_notes[owner] = []
			_notes[owner].append(String(n.get("text", "")))
	_loose.text = " ".join(loose)
	_loose.visible = not loose.is_empty() and not collapsed
	var shown: Array = [] if collapsed else rows_now.slice(0, MAX_CARDS)
	var sig := "%s|%s|" % [collapsed, str(_notes)]
	for r in shown:
		sig += "%s:%s:%s|" % [r.get("id"), r.get("phase"), r.get("answer")]
	if sig != _sig:
		_sig = sig
		Kit.clear(_list)
		_cards = []
		for r in shown:
			var c: Dictionary = _make_card(r)
			_list.add_child(c["root"])
			_cards.append(c)
	for k in mini(_cards.size(), shown.size()):
		(_cards[k]["when"] as Label).text = when_text(shown[k])
	_more.visible = not collapsed and rows_now.size() > shown.size()
	_more.text = "%s not shown." % Kit.plural(rows_now.size() - shown.size(), "more ship")

## "in 5:20", "lands 0:12", "leaves 2:10", "waits 2:30" (in orbit: time left before it goes).
func when_text(r: Dictionary) -> String:
	var ph: String = String(r.get("phase", ""))
	var t: float = float(r.get("t_s", 0.0))
	match ph:
		"forecast": return "in " + Kit.clock(float(r.get("eta_s", 0.0)))
		"orbit": return "waits " + Kit.clock(t if t > 0.0 else hud.data.orbit_left_s(r))   # SIM t_s; older SIM: computed
		"landing": return "lands " + Kit.clock(t)
		"landed": return "leaves " + Kit.clock(t)
		"boarding": return "boards " + Kit.clock(t)
		"takeoff": return "take-off"
	return ""

func _make_card(r: Dictionary) -> Dictionary:
	var d = hud.data
	var id: int = int(r.get("id", -1))
	var kind: String = String(r.get("kind", ""))
	var ph: String = String(r.get("phase", ""))
	var denied: bool = String(r.get("answer", "grant")) == "deny"
	var col: Color = P.TEXT_3 if denied else (P.GREEN if ph == "landed" else P.CYAN)
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(col.r, col.g, col.b, 0.07)
	st.border_color = Color(col.r, col.g, col.b, 0.9)
	st.border_width_left = 3
	st.content_margin_left = 9
	st.content_margin_right = 6
	st.content_margin_top = 5
	st.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", st)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if ["landing", "landed", "boarding", "takeoff"].has(ph) and typeof(r.get("pad_pos")) == TYPE_VECTOR2:
		var pp: Vector2 = r["pad_pos"]
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Click: the camera goes to the pad."
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				hud.main.focus_on(pp))
	var v: VBoxContainer = Kit.vbox(3)
	card.add_child(v)
	var top: HBoxContainer = Kit.hbox(6)
	v.add_child(top)
	top.add_child(Kit.icon(d.ship_icon(kind), 16, col))
	top.add_child(Kit.head(String(r.get("name", kind)), P.TEXT, 12))
	var bd: Control = Kit.badge("DENIED" if denied and ["forecast", "orbit"].has(ph) else String(d.SHIP_PHASE.get(ph, ph.to_upper())), col)
	bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(bd)
	top.add_child(Kit.spacer())
	var when: Label = Kit.num(when_text(r), 13, col, true)
	top.add_child(when)
	var offer0: Dictionary = r.get("offer", {}) if typeof(r.get("offer", {})) == TYPE_DICTIONARY else {}
	# A trader's sentence lists every item; the chips below show them, so it gets the short kind text.
	var line: String = String(d.ship_kind(kind).get("desc", "")) if offer0.has("sells") or offer0.has("buys") else String(r.get("text", ""))
	var txt: Label = Kit.wrap(line, 12, P.TEXT_2)
	txt.custom_minimum_size.x = WIDTH - 40.0
	v.add_child(txt)
	var offer: Dictionary = r.get("offer", {}) if typeof(r.get("offer", {})) == TYPE_DICTIONARY else {}
	if offer.has("sells"):
		v.add_child(_chips("Sells", offer["sells"]))
	if offer.has("buys"):
		v.add_child(_chips("Buys", offer["buys"]))
	if offer.has("roles"):
		var rr: HBoxContainer = Kit.hbox(4)
		rr.add_child(Kit.label("Brings", "SmallLabel", 11, P.TEXT_3))
		for role in offer["roles"]:
			rr.add_child(Kit.icon(Icons.role(String(role)), 15, P.ROLE.get(String(role), P.CYAN)))
		v.add_child(rr)
	elif offer.has("fee") or offer.has("people"):
		v.add_child(Kit.label("%s  ·  fee up to %d credits each" % [Kit.plural(int(offer.get("people", r.get("people", 0))), "visitor"), int(offer.get("fee", 0))],
			"SmallLabel", 12, P.GOLD))
	for note in _notes.get(id, []):
		var nr: HBoxContainer = Kit.hbox(5)
		nr.add_child(Kit.icon("sev_warning", 13, P.AMBER))
		nr.add_child(Kit.wrap(String(note), 12, P.AMBER, WIDTH - 60.0))
		v.add_child(nr)
	# Choices
	var row: HBoxContainer = Kit.hbox(5)
	v.add_child(row)
	if ["forecast", "orbit"].has(ph):
		var g: Button = _small("Grant", func(): hud.main.submit("traffic_answer", {"id": id, "grant": true}), "Grant\nThe ship may land. This is the default.", "sev_ok")
		g.toggle_mode = true
		g.set_pressed_no_signal(not denied)
		row.add_child(g)
		var dn: Button = _small("Deny", func(): hud.main.submit("traffic_answer", {"id": id, "grant": false}), "Deny\nThe ship does not land and goes away. You lose only its offer.", "close")
		dn.toggle_mode = true
		dn.set_pressed_no_signal(denied)
		row.add_child(dn)
		if kind == "shuttle":
			row.add_child(_small("Settlers", func(): hud.open_screen("shuttle", id), "Settlers\nChoose how many settlers may stay.", "people"))
	if ph == "landed" and (offer.has("sells") or offer.has("buys")):
		row.add_child(_small("Trade", func(): hud.open_screen("trade", id), "Trade\nBuy and sell with this ship.", "crate", "PrimaryButton"))
	return {"root": card, "when": when}

func _small(text: String, cb: Callable, tip: String, icon: String, variation: String = "ChipButton") -> Button:
	var b: Button = Kit.button(text, cb, tip, variation, icon, 12)
	b.custom_minimum_size.y = 24
	b.add_theme_font_size_override("font_size", 11)
	return b

## "Sells  [icon]6 [icon]4 ..." (units), at most 6 items.
func _chips(label: String, table: Dictionary) -> HBoxContainer:
	var d = hud.data
	var h: HBoxContainer = Kit.hbox(6)
	var l: Label = Kit.label(label, "SmallLabel", 11, P.TEXT_3)
	l.custom_minimum_size.x = 34
	h.add_child(l)
	var n := 0
	for it in table:
		if n >= 6:
			h.add_child(Kit.label("+%d" % (table.size() - 6), "SmallLabel", 11, P.TEXT_3))
			break
		var e = table[it]
		var units: int = int(e.get("units", 0)) if typeof(e) == TYPE_DICTIONARY else int(e)
		var price: int = int(e.get("price", 0)) if typeof(e) == TYPE_DICTIONARY else 0
		h.add_child(Kit.chip(Icons.item(String(it)), "%d" % units, d.item_color(String(it)), "%s: %d units at %d credits" % [d.item_name(String(it)), units, price], true, 14))
		n += 1
	return h
