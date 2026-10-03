extends PanelContainer
## The alerts: a card in the Alerts tab of the panel manager (ui/hud/panel_manager.gd places it; the tab
## body scrolls, so every card shows). Incidents from sim.alerts.incidents(). Each card says
## what is failing (severity icon + word), why, how long is left, what to do, and hangs
## the consequences under the root cause. "Show" moves the camera to the cause.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

const MAX_CARDS := 8   # the Alerts tab scrolls (panel manager); the rest are counted ("+ n more")
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
# Paul, 2026-09-28 ("Output blocked" popped in and out): the card count no longer follows the free height;
# the Alerts tab scrolls. max_changes stays for the steadiness test; hold_s is kept for old tests.
const HOLD_S := 6.0
var hold_s := HOLD_S
var max_changes := 0     # tests: how often the number of cards changed
var live_count := 0      # alerts now, for the Alerts tab badge (panel manager)
var worst_sev := 0

func _ready() -> void:
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

# Placement and fit: the panel manager (Paul, 2026-10-01). The old fit to the minimap (cards dropped and
# taken back with hysteresis) is gone: the Alerts tab scrolls.

## Folded by the window manager while a window covers the panel (V5 critic round 25): only the
## summary line shows ("2 critical · 1 warning"); it opens again when the window leaves.
var collapsed := false
func fold_set(on: bool) -> void:
	collapsed = on
	_list.visible = not on
	_more.visible = _more.visible and not on
	Kit.fit(self)

func rebuild() -> void:
	_sig = ""
	_open = {}
	refresh()

func refresh() -> void:
	# The gate (ui/hud/alert_gate.gd) gives a steady list: a stable order, and an alert that
	# clears stays a short time as "cleared", so a key that goes on and off is one card.
	var inc: Array = hud.watchers.gate.display(hud.main.sim.alerts.incidents()) if hud.watchers != null else hud.main.sim.alerts.incidents()
	# Version 4 base filter (top bar): one base shows its own alerts and the colony-wide ones (base -1).
	if hud.base_filter >= 0:
		var keep: Array = []
		for i in inc:
			var ib: int = int(i["issue"].get("base", -1))
			if ib == -1 or ib == hud.base_filter:
				keep.append(i)
		inc = keep
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
	live_count = live.size()
	worst_sev = 3 if crit > 0 else (2 if warn > 0 else (1 if not live.is_empty() else 0))
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
	_more.visible = inc.size() > shown.size() and not collapsed
	_more.text = "%s not shown. The dashboard lists every one." % Kit.plural(inc.size() - shown.size(), "more alert")

func _make_card(i: Dictionary) -> Dictionary:
	var issue: Dictionary = i["issue"]
	var sev: int = int(issue["severity"])
	var col: Color = P.sev(sev)
	var card := PanelContainer.new()
	var st = load("res://ui/theme/list_row.gd").make(col)   # v4 list row: signal bar + seam, no box
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
	v.add_child(text)
	var act: Label = Kit.wrap("Do: " + String(issue["action"]), 12, P.TEXT_2)
	v.add_child(act)
	# V5 §18.4: an alert about a missing item has Show chain: the chain from the raw resource to the item.
	var chain_item: String = hud.v18.issue_item(issue)
	if chain_item != "":
		var cb: Button = Kit.button("Show chain", func(): hud.open_chain(chain_item), "Show chain\nHow %s is made, step by step: what is done, what is missing and what to build." % hud.data.item_name(chain_item).to_lower(), "ChipButton", "route", 12)
		cb.custom_minimum_size.y = 24
		cb.set_meta("chain_item", chain_item)
		cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(cb)
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
				row.add_child(cl)
				cons_box.add_child(row)
	return {"root": card, "left": left, "text": text, "key": key, "act": act}

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
