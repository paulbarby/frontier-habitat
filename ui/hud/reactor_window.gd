extends PanelContainer
## Reactor controls (V4_DESIGN §4.2, SIM milestone 6): each fission reactor with its core heat, the
## meltdown sequence (normal → warning → critical → breach) and the time to the next stage, coolant,
## fuel rods, power, the blast radius and the radiation zone. Four actions, each with a confirm step:
## SCRAM (the fission stops after 12 s: no power; the core cools), Restart (after a SCRAM, only
## below the warning heat), Dump coolant (up to 4 units, 12 heat each), Evacuate (everyone within
## the zone goes to a safe room and stays until the core is safe). SIM's refusals show as they are.
## A window of the window manager; the meltdown banner (ui/hud/reactor_banner.gd) opens it.
## Data: ui/v4_data.gd reactors() (SIM sim.reactors.list()); commands through hud.v4.command.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const V4 = preload("res://ui/v4_data.gd")

const Quarter = preload("res://ui/wm/quarter.gd")
const WIDTH := 440.0
var _scroll: ScrollContainer
const PHASE_WORD := {"normal": "NORMAL", "warning": "WARNING", "critical": "CRITICAL", "breach": "BREACH"}

## Core heat gauge: the heat as a bar, with ticks at the warning and critical heat.
class HeatBar extends Control:
	var heat := 40.0
	var hmax := 100.0
	var warn := 60.0
	var crit := 85.0
	var col := Color.WHITE
	func _init() -> void:
		custom_minimum_size = Vector2(120, 12)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2(0, 3), Vector2(size.x, 6))
		draw_rect(r, Color(1, 1, 1, 0.08), true)
		draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(heat / hmax, 0.0, 1.0), r.size.y)), col, true)
		for pair in [[warn, P.AMBER], [crit, P.RED]]:
			var x: float = size.x * float(pair[0]) / hmax
			draw_line(Vector2(x, 0), Vector2(x, 12), pair[1], 2.0)

var hud
var _head: HBoxContainer
var _list: VBoxContainer
var _na: Label
var _sig := ""
var _t := 0.0
var last_result: Dictionary = {}   # the last command's result (tests)

static func phase_color(ph: String) -> Color:
	match ph:
		"warning": return P.AMBER
		"critical", "breach": return P.RED
	return P.GREEN

func _ready() -> void:
	var st = GlassFrame.new()
	st.kind = "window"
	st.header_h = 50.0
	st.content_margin_left = 20
	st.content_margin_right = 22
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	st.accent = Color(P.AMBER.r, P.AMBER.g, P.AMBER.b, 0.9)
	add_theme_stylebox_override("panel", st)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var v: VBoxContainer = Kit.vbox(8)
	add_child(v)
	_head = Kit.hbox(10)
	_head.custom_minimum_size.y = 30
	v.add_child(_head)
	_head.add_child(Kit.icon("reactor", 22, P.AMBER))
	var t: Label = Kit.head("REACTORS", P.TEXT, 16, "head_wide")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(t)
	var close_b: Button = Kit.icon_button("close", func(): visible = false, "Close\nEsc. The warnings stay on the banner.", "GhostButton", 16, 30)
	_head.add_child(close_b)
	Quarter.thin(close_b)
	v.add_child(Kit.gap(0, 6))
	_na = Kit.wrap("No reactor. A fission reactor needs the research Fission Reactor, uranium fuel rods and coolant.", 14, P.TEXT_2)
	_na.custom_minimum_size.x = 360
	v.add_child(_na)
	_list = Kit.vbox(10)
	_scroll = Kit.scroll(_list)   # a narrow window scrolls its cards
	_scroll.custom_minimum_size = Vector2(WIDTH - 42, 240)
	v.add_child(_scroll)
	visibility_changed.connect(func():
		if visible:
			refresh(true))

func register_window(wm) -> void:
	wm.register(self, "reactor", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y + 100.0))

func wm_close() -> void:
	visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	Quarter.fit(self, hud, "reactor", WIDTH, _scroll, _list, 42.0)
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		refresh()

func refresh(force: bool = false) -> void:
	if hud == null:
		return
	var rs: Array = hud.v4.reactors()
	_na.visible = rs.is_empty()
	var sig: String = ""
	for r in rs:
		sig += "%d:%s:%d:%d:%d:%d:%s:%s:%d|" % [int(r["id"]), r["phase"], int(float(r["heat"]) * 10.0), int(r["coolant"]), int(r["rods"]), int(r["next_phase_s"]),
			r["scram"], r["evac"], int(float(r.get("scram_left_s", 0.0)))]
	if sig == _sig and not force:
		return
	_sig = sig
	Kit.clear(_list)
	for r in rs:
		_list.add_child(_card(r))
	Kit.fit(self)

## One line on what happens next, in STE.
static func status_line(r: Dictionary) -> String:
	var ph: String = String(r["phase"])
	var cur: int = V4.PHASES.find(ph)
	var next_s: float = float(r.get("next_phase_s", -1.0))
	if ph == "breach" or String(r.get("state", "")) == "destroyed":
		return "BREACH: the blast is done. A radiation zone of %d m stays for days." % int(r["zone_r"])
	if bool(r.get("scram", false)):
		if float(r.get("scram_left_s", 0.0)) > 0.0:
			return "SCRAM: the fission stops in %d s." % int(ceilf(float(r["scram_left_s"])))
		if next_s >= 0.0 and cur < 3:
			return "SCRAM done, but the core still gets hotter: %s in %s. Dump coolant." % [String(PHASE_WORD[V4.PHASES[cur + 1]]).capitalize(), Kit.clock(next_s)]
		return "SCRAM done: no fission, no power. The core cools. Restart below heat %d." % int(r["warn_at"])
	if next_s >= 0.0 and cur < 3:
		return "%s in %s unless you act." % [String(PHASE_WORD[V4.PHASES[cur + 1]]).capitalize(), Kit.clock(next_s)]
	if float(r.get("rate", 0.0)) < -0.0001 and cur >= 1:
		return "Cooling down. It stays hot for a time: keep the coolant coming."
	if not bool(r.get("running", false)):
		return "Not running: it needs a fuel rod."
	return "Stable. Carriers keep %d fuel rods and %d coolant in it." % [int(r["rods_keep"]), int(r["coolant_keep"])]

func _card(r: Dictionary) -> Control:
	var ph: String = String(r["phase"])
	var col: Color = phase_color(ph)
	var card: PanelContainer = Kit.panel("WellPanel", false)
	var v: VBoxContainer = Kit.vbox(6)
	card.add_child(v)
	var h: HBoxContainer = Kit.hbox(8)
	v.add_child(h)
	var nm: Label = Kit.label(String(r["name"]), "BodyStrong", 15, P.TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	h.add_child(Kit.badge(PHASE_WORD.get(ph, ph.to_upper()), col))
	if bool(r.get("scram", false)):
		h.add_child(Kit.badge("SCRAM", P.CYAN))
	h.add_child(Kit.icon_button("target", func(): hud.main.focus_on(r["pos"]), "Show\nMoves the camera to the reactor.", "GhostButton", 14, 26))
	# Meltdown sequence: four steps, the current one lit.
	var seq: HBoxContainer = Kit.hbox(4)
	v.add_child(seq)
	var cur: int = V4.PHASES.find(ph)
	for i in V4.PHASES.size():
		var step: Label = Kit.label(PHASE_WORD[V4.PHASES[i]], "SmallLabel", 12, phase_color(V4.PHASES[i]) if i <= cur else P.TEXT_2)
		step.add_theme_font_override("font", load("res://ui/theme/fonts.gd").get_font("head"))
		seq.add_child(step)
		if i < V4.PHASES.size() - 1:
			seq.add_child(Kit.label("→", "SmallLabel", 12, P.TEXT_2))
	var ll: Label = Kit.wrap(status_line(r), 14, col if ph != "normal" else P.TEXT_2)
	ll.custom_minimum_size.x = 360
	v.add_child(ll)
	# Heat gauge with the warning and critical ticks.
	var hb := HeatBar.new()
	hb.heat = float(r["heat"])
	hb.hmax = float(r["heat_max"])
	hb.warn = float(r["warn_at"])
	hb.crit = float(r["crit_at"])
	hb.col = col
	var hrow: HBoxContainer = Kit.hbox(8)
	hrow.add_child(Kit.dim("Core heat", 13))
	hrow.add_child(hb)
	hrow.tooltip_text = "Core heat\n40 when it runs. Warning at %d, critical at %d, breach at %d." % [int(r["warn_at"]), int(r["crit_at"]), int(r["heat_max"])]
	v.add_child(hrow)
	var g: GridContainer = Kit.grid(2, 16, 3)
	v.add_child(g)
	var rate: float = float(r.get("rate", 0.0))
	_fact(g, "Heat", "%.1f of %d" % [float(r["heat"]), int(r["heat_max"])], col if ph != "normal" else P.TEXT)
	_fact(g, "Change", ("+%.2f per s" % rate) if rate > 0.0001 else (("%.2f per s" % rate) if rate < -0.0001 else "steady"), P.AMBER if rate > 0.0001 else P.GREEN)
	_fact(g, "Coolant", "%d units (keeps %d)" % [int(r["coolant"]), int(r["coolant_keep"])], P.level(100.0 * float(r["coolant"]) / maxf(1.0, float(r["coolant_keep"])), 50.0, 20.0))
	var rod_left: float = float(r.get("fuel_s", 0.0))
	_fact(g, "Fuel rods", "%d + %s in this rod" % [int(r["rods"]), Kit.clock(rod_left)] if rod_left > 0.0 else "%d" % int(r["rods"]), P.level(100.0 * float(r["rods"]) / maxf(1.0, float(r["rods_keep"])), 50.0, 1.0))
	_fact(g, "Power", "%s P" % Kit.fmt(float(r["power_out"])), P.TEXT if float(r["power_out"]) > 0.0 else P.TEXT_3)
	_fact(g, "Blast radius", "%d m" % int(r["blast_r"]), P.AMBER)
	_fact(g, "Radiation zone", "%d m" % int(r["zone_r"]), P.AMBER)
	if bool(r.get("evac", false)):
		_fact(g, "Evacuation", "on: people stay out", P.AMBER)
	if ph == "breach" or String(r.get("state", "")) == "destroyed":
		return card
	# Two columns: a grid measures its height before layout (a flow container did not, and the
	# buttons fell out of the card).
	var act: GridContainer = Kit.grid(2, 8, 6)
	v.add_child(act)
	var id: int = int(r["id"])
	var nme: String = String(r["name"])
	if not bool(r.get("scram", false)):
		act.add_child(_wide(Kit.button("SCRAM", func(): hud.confirm("SCRAM %s?" % nme, ["The rods drop. The fission stops after 12 s.", "No power from it until you restart it. Its heat then falls slowly."], func(): _do("reactor_scram", id, nme), "SCRAM", true),
			"SCRAM\nStops the fission (12 s). Safe, but the reactor makes no power.", "DangerButton", "scram", 15)))
	else:
		var rb: Button = Kit.button("Restart", func(): hud.confirm("Restart %s?" % nme, ["The fission starts again and makes power.", "The core heats up again: keep coolant in it."], func(): _do("reactor_restart", id, nme), "Restart"),
			"Restart\nOnly when the core is below heat %d." % int(r["warn_at"]), "", "power", 15)
		rb.disabled = float(r["heat"]) >= float(r["warn_at"])
		act.add_child(_wide(rb))
	var cb: Button = Kit.button("Dump coolant", func(): hud.confirm("Dump coolant into %s?" % nme, ["Up to %d coolant from its store go into the core at once." % int(r["dump_units"]), "Each unit takes %d heat off." % int(r["dump_heat"])], func(): _do("reactor_cool", id, nme), "Dump"),
		"Dump coolant\nUp to %d units from its store, %d heat off each. It has %d." % [int(r["dump_units"]), int(r["dump_heat"]), int(r["coolant"])], "", "coolant", 15)
	cb.disabled = int(r["coolant"]) <= 0
	act.add_child(_wide(cb))
	var eb: Button = Kit.button("Evacuate", func(): hud.confirm("Evacuate the %d m zone round %s?" % [int(r["zone_r"]), nme], ["Everyone within %d m goes to a room with air outside the zone." % int(r["zone_r"]), "They stay there until the core is safe again."], func(): _do("reactor_evacuate", id, nme), "Evacuate", true),
		"Evacuate\nEveryone within %d m goes to a safe room and stays there." % int(r["zone_r"]), "", "evacuate", 15)
	eb.disabled = bool(r.get("evac", false))
	act.add_child(_wide(eb))
	return card

static func _wide(b: Button) -> Button:
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## Sends a reactor command and reports SIM's answer.
func _do(kind: String, id: int, nme: String) -> void:
	var res: Dictionary = hud.v4.command(kind, {"id": id})
	last_result = res
	if not bool(res.get("ok", false)):
		hud.toast("%s: %s" % [nme, String(res.get("text", res.get("code", "")))], "warn", "reactor")
	elif kind == "reactor_evacuate" and res.has("result"):
		var rr: Dictionary = res["result"]
		var moved: int = int(rr.get("moved", 0))
		var stuck: int = int(rr.get("stuck", 0))
		hud.toast("Evacuation: %s leave the zone.%s" % [Kit.plural(moved, "colonist"), (" %d cannot: no safe room with air." % stuck) if stuck > 0 else ""], "warn" if stuck > 0 else "info", "evacuate")
	elif kind == "reactor_cool" and res.has("result"):
		hud.toast("%s: %d coolant dumped into the core." % [nme, int(res["result"].get("used", 0))], "info", "coolant")
	refresh(true)

func _fact(g: GridContainer, name: String, value: String, col: Color) -> void:
	g.add_child(Kit.dim(name, 13))
	var l: Label = Kit.num(value, 13, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(l)
