extends PanelContainer
## Hazard forecast (docs/V3_DESIGN.md §8), top left, right of the goals tracker.
## One card per detected event: icon, name, severity (1..3 as dots and a word), time to it
## (or "NOW" and the time left), the place (click the card: the camera goes there),
## "COVERED" or "NOT COVERED", and one line of advice. A solar flare card has a Shelter
## button. Under the cards: machines near failure, with a link to the maintenance page.
## Hidden when there is nothing to show, so it costs no draw calls then.
## Cards are rebuilt only when the set of events changes; the times update in place.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

const MAX_CARDS := 3
const WIDTH := 318.0

var hud
var collapsed := false
var _head_count: Label
var _head_next: Label
var _chev: Button
var _list: VBoxContainer
var _more: Label
var _risk: Button
var _sig := ""
var _cards: Array = []       # [{root, eta, ev_id}]
var _rows: Array = []
var _risk_n := 0

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
	head.add_child(Kit.icon("meteor", 16, P.AMBER))
	var tv: VBoxContainer = Kit.vbox(-2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	_head_count = Kit.head("Hazards", P.TEXT_3, 11)
	tv.add_child(_head_count)
	_head_next = Kit.head("", P.AMBER, 13, "head_wide")
	tv.add_child(_head_next)
	_chev = Kit.icon_button("chevron_up", func(): _toggle(), "Hide or show the hazard cards.", "GhostButton", 14, 26)
	head.add_child(_chev)
	_list = Kit.vbox(6)
	v.add_child(_list)
	_more = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	_more.visible = false
	v.add_child(_more)
	_risk = Kit.button("", func(): hud.open_screen("dashboard", "hazards"), "Maintenance\nMachines near failure, with Maintain now.", "GhostButton", "wrench", 14)
	_risk.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_risk.custom_minimum_size.y = 26
	_risk.add_theme_font_size_override("font_size", 12)
	_risk.visible = false
	v.add_child(_risk)

func _process(_delta: float) -> void:
	if hud == null or hud.goals == null or not visible:
		return
	Kit.fit(self)
	var g: Control = hud.goals
	position.x = g.position.x + g.size.x + 10.0

func rebuild() -> void:
	_sig = ""
	refresh()

func _toggle() -> void:
	collapsed = not collapsed
	_chev.icon = Icons.tex("chevron_down" if collapsed else "chevron_up", 14)
	_sig = ""
	refresh()

## The rows the panel shows: active events first, then the forecast, soonest first.
func rows() -> Array:
	var d = hud.data
	var out: Array = d.hazard_active()
	out.append_array(d.hazard_forecast())
	return out

func refresh() -> void:
	var d = hud.data
	_rows = rows()
	var risk: Array = d.at_risk()
	_risk_n = risk.size()
	var show: bool = not _rows.is_empty() or _risk_n > 0
	if show != visible:
		visible = show
	if not show:
		_sig = ""
		return
	# Header: count and the next event.
	var n_act := 0
	for r in _rows:
		if bool(r["active"]):
			n_act += 1
	var parts: Array = []
	if n_act > 0:
		parts.append("%d now" % n_act)
	if _rows.size() - n_act > 0:
		parts.append("%d forecast" % (_rows.size() - n_act))
	_head_count.text = ("HAZARDS  ·  " + "  ·  ".join(parts)).to_upper() if not parts.is_empty() else "HAZARDS"
	if _rows.is_empty():
		_head_next.text = "NO EVENT DETECTED"
		_head_next.add_theme_color_override("font_color", P.GREEN)
	else:
		var first: Dictionary = _rows[0]
		_head_next.text = ("%s NOW" % first["name"]).to_upper() if bool(first["active"]) else ("%s IN %s" % [first["name"], Kit.clock(first["eta_s"])]).to_upper()
		_head_next.add_theme_color_override("font_color", _col(first))
	var shown: Array = [] if collapsed else _rows.slice(0, MAX_CARDS)
	var sig := "%s|%s|" % [collapsed, d.shelter_on()]
	for r in shown:
		sig += "%s:%s:%s:%d|" % [r["id"], r["active"], r["countered"], r["severity"]]
	if sig != _sig:
		_sig = sig
		Kit.clear(_list)
		_cards = []
		for r in shown:
			var c: Dictionary = _make_card(r)
			_list.add_child(c["root"])
			_cards.append(c)
	for k in mini(_cards.size(), shown.size()):
		_update_card(_cards[k], shown[k])
	_more.visible = not collapsed and _rows.size() > shown.size()
	_more.text = "%s not shown. The Hazards page lists every one." % Kit.plural(_rows.size() - shown.size(), "more event")
	_risk.visible = _risk_n > 0
	_risk.text = "%s near failure. Open maintenance." % Kit.plural(_risk_n, "machine")

## Colour: going on now = red (amber at severity 1); coming and covered = cyan; coming and
## not covered = amber (red at severity 3). The words say the same.
static func _col(r: Dictionary) -> Color:
	var sv: int = int(r["severity"])
	if bool(r["active"]):
		return P.RED if sv >= 2 else P.AMBER
	if bool(r["countered"]):
		return P.CYAN
	return P.RED if sv >= 3 else P.AMBER

func _make_card(r: Dictionary) -> Dictionary:
	var d = hud.data
	var col: Color = _col(r)
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
	var pos = r["pos"]
	if pos != null:
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Click: the camera goes to the place."
		card.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_go(pos))
	var v: VBoxContainer = Kit.vbox(2)
	card.add_child(v)
	var top: HBoxContainer = Kit.hbox(6)
	v.add_child(top)
	top.add_child(Kit.icon(d.hazard_icon(String(r["kind"])), 16, col))
	var nm: Label = Kit.head(String(r["name"]), P.TEXT, 12)
	top.add_child(nm)
	top.add_child(_pips(int(r["severity"]), col))
	top.add_child(Kit.spacer())
	var eta: Label = Kit.num("", 14, col, true)
	top.add_child(eta)
	var place: Label = Kit.label(d.place_text(pos), "SmallLabel", 12, P.TEXT_2)
	place.clip_text = true
	v.add_child(place)
	var row: HBoxContainer = Kit.hbox(6)
	v.add_child(row)
	var cov: bool = bool(r["countered"])
	for bd in [Kit.badge("COVERED" if cov else "NOT COVERED", P.GREEN if cov else P.AMBER), Kit.badge("SEVERITY %d" % int(r["severity"]), P.sev(int(r["severity"])))]:
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bd)
	if String(r["kind"]) == "solar_flare":
		row.add_child(Kit.spacer())
		row.add_child(shelter_button(hud))
	var adv: Label = Kit.wrap(String(r["advice"]), 12, P.TEXT_2)
	adv.custom_minimum_size.x = WIDTH - 40.0
	v.add_child(adv)
	return {"root": card, "eta": eta}

func _update_card(c: Dictionary, r: Dictionary) -> void:
	var l: Label = c["eta"]
	if bool(r["active"]):
		l.text = ("NOW  " + Kit.clock(r["left_s"])) if float(r["left_s"]) >= 0.0 else "NOW"
	else:
		l.text = Kit.clock(r["eta_s"])

## Three dots, `n` of them lit.
static func _pips(n: int, col: Color) -> HBoxContainer:
	var h: HBoxContainer = Kit.hbox(2)
	h.tooltip_text = "Severity %d of 3" % n
	for i in 3:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(5, 5)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = col if i < n else P.with_alpha(P.TEXT_3, 0.5)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(dot)
	return h

func _go(pos: Vector2) -> void:
	hud.main.focus_on(pos)
	Kit.sfx("click")

## The Shelter order button (also used by the banner): everyone goes inside while it is on.
static func shelter_button(h) -> Button:
	var on: bool = h.data.shelter_on()
	var b: Button = Kit.button("End shelter" if on else "Shelter", func(): toggle_shelter(h),
		"Shelter\nEveryone goes inside and stays there. Outside work stops. Order it before a solar flare." if not on else "End shelter\nColonists go back to work outside.",
		"DangerButton" if not on else "", "shelter", 14)
	b.custom_minimum_size.y = 24
	b.add_theme_font_size_override("font_size", 11)
	return b

static func toggle_shelter(h) -> void:
	var on: bool = not h.data.shelter_on()
	if h.data.mock.has("shelter"):
		h.data.mock["shelter"] = on
	else:
		h.main.submit("shelter", {"on": on})
	if h.data.mock.has("shelter"):
		h.toast("Shelter ordered. Everyone goes inside." if on else "Shelter ended. Outside work starts again.", "warn" if on else "info", "shelter")
	# With the simulation, its "shelter" log entry toasts (ui/hud/watchers.gd).
