extends PanelContainer
## Advisor window (V4_DESIGN §6): "what to do next". Three groups from ui/advisor.gd: the biggest
## problems, the next goal steps, unused potential. Each row says what to do; a Show button moves
## the camera to the structure it names. A window of the window manager (key A is taken by the
## camera, so: key N, or the nav rail button). It refreshes every 2 seconds while open and rebuilds
## only when the advice changes.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const Advisor = preload("res://ui/advisor.gd")

const WIDTH := 420.0
const GROUPS := [["problem", "Biggest problems", "sev_warning", P.AMBER], ["next", "Next steps", "goals", P.CYAN], ["unused", "Unused potential", "advisor", P.VIOLET]]

var hud
var _head: HBoxContainer
var _list: VBoxContainer
var _sig := ""
var _t := 0.0
var tips: Array = []     # the last advice shown (tests)

func _ready() -> void:
	var st = GlassFrame.new()
	st.kind = "window"
	st.header_h = 50.0
	st.content_margin_left = 20
	st.content_margin_right = 22
	st.content_margin_top = 12
	st.content_margin_bottom = 14
	st.accent = Color(P.VIOLET.r, P.VIOLET.g, P.VIOLET.b, 0.9)
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
	_head.add_child(Kit.icon("advisor", 22, P.VIOLET))
	var t: Label = Kit.head("ADVISOR", P.TEXT, 16, "head_wide")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(t)
	_head.add_child(Kit.icon_button("close", func(): visible = false, "Close\nEsc.", "GhostButton", 16, 30))
	v.add_child(Kit.gap(0, 6))
	var well: PanelContainer = Kit.panel("WellPanel", false)
	v.add_child(well)
	_list = Kit.seam_list(6)
	var sc: ScrollContainer = Kit.scroll(_list)
	sc.custom_minimum_size = Vector2(WIDTH - 42 - 18, 120)
	well.add_child(sc)
	set_meta("scroll", sc)
	visibility_changed.connect(func():
		if visible:
			_sig = ""
			refresh(true))

func register_window(wm) -> void:
	wm.register(self, "advisor", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.position.x + 340.0, wa.position.y + 20.0))

func wm_close() -> void:
	visible = false

func toggle() -> void:
	visible = not visible

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 2.0:
		_t = 0.0
		refresh()

func refresh(force: bool = false) -> void:
	if not visible and not force:
		return
	tips = Advisor.tips(hud)
	var sig := ""
	for tp in tips:
		sig += "%s|%s|%s;" % [tp["kind"], tp["title"], tp["text"]]
	if sig == _sig:
		return
	_sig = sig
	Kit.clear(_list)
	for g in GROUPS:
		var rows: Array = []
		for tp in tips:
			if String(tp["kind"]) == String(g[0]):
				rows.append(tp)
		var h: HBoxContainer = Kit.hbox(6)
		h.set_meta("no_seam", true)
		h.add_child(Kit.icon(String(g[2]), 14, g[3]))
		h.add_child(Kit.head(String(g[1]), g[3], 12))
		_list.add_child(h)
		if rows.is_empty():
			var none: Label = Kit.label("Nothing now." if String(g[0]) != "problem" else "No problem now.", "", 13, P.TEXT_2)
			none.set_meta("no_seam", true)
			_list.add_child(none)
		for tp in rows:
			_list.add_child(_row(tp))
		var gp: Control = Kit.gap(0, 4)
		gp.set_meta("no_seam", true)
		_list.add_child(gp)
	var sc: ScrollContainer = get_meta("scroll")
	sc.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y + 4.0, 120.0, 460.0)
	Kit.fit(self)

func _row(tp: Dictionary) -> Control:
	var h: HBoxContainer = Kit.hbox(8)
	h.add_child(Kit.icon(String(tp["icon"]), 16, tp["color"]))
	var tv: VBoxContainer = Kit.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	var t: Label = Kit.wrap(String(tp["title"]), 14, P.TEXT)
	t.custom_minimum_size.x = 250
	tv.add_child(t)
	if String(tp["text"]) != "":
		var d: Label = Kit.wrap(String(tp["text"]), 13, P.TEXT_2)
		d.custom_minimum_size.x = 250
		tv.add_child(d)
	var f = tp.get("focus")
	if f != null:
		h.add_child(Kit.icon_button("target", func(): _go(f), "Show\nMoves the camera there.", "GhostButton", 14, 26))
	return h

func _go(f) -> void:
	if typeof(f) == TYPE_INT and hud.main.sim.state["buildings"].has(f):
		hud.main.select("building", f)
		hud.main.focus_on(hud.main.sim.state["buildings"][f]["pos"])
	elif typeof(f) == TYPE_INT and hud.main.sim.state["agents"].has(f):
		hud.main.select("agent", f)
		hud.main.focus_on(hud.main.sim.state["agents"][f]["pos"])
	elif typeof(f) == TYPE_VECTOR2:
		hud.main.focus_on(f)
