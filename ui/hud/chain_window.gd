extends PanelContainer
## Show chain (V5_DESIGN §18.4; Paul, 2026-10-04: alerts must say what needs to be built, including how the chain works from mining
## to refining to processing, with a little explanation). A small window for one item: the chain diagram (ui/widgets/chain_view.gd),
## each step done or missing, one STE line each, and a Place button for a missing structure that is unlocked.
## Opened by the Show chain button of an alert (ui/hud/alerts_panel.gd) and by the codex. A window of the window manager in the
## right quarter (Quarter). Data: ui/v18_data.gd.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const GlassFrame = preload("res://ui/theme/glass_frame.gd")
const Quarter = preload("res://ui/wm/quarter.gd")
const ChainView = preload("res://ui/widgets/chain_view.gd")
const WIDTH := 400.0

var hud
var item := ""
var chain_now: Dictionary = {}     # the chain shown (tests)
var _head: HBoxContainer
var _title: Label
var _sum: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _sig := ""

func _ready() -> void:
	var st = GlassFrame.new()
	st.kind = "window"
	st.header_h = 50.0
	st.content_margin_left = 20
	st.content_margin_right = 22
	st.content_margin_top = 12
	st.content_margin_bottom = 14
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
	_head.add_child(Kit.icon("route", 22, P.CYAN))
	_title = Kit.head("PRODUCTION CHAIN", P.TEXT, 16, "head_wide")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_head.add_child(_title)
	var close_b: Button = Kit.icon_button("close", func(): visible = false, "Close\nEsc.", "GhostButton", 16, 30)
	_head.add_child(close_b)
	Quarter.thin(close_b)
	_sum = Kit.wrap("", 13, P.TEXT_2)
	v.add_child(_sum)
	_body = Kit.vbox(0)
	_scroll = Kit.scroll(_body)
	_scroll.custom_minimum_size = Vector2(WIDTH - 42, 260)
	v.add_child(_scroll)
	var codex_b: Button = Kit.button("All production chains", func(): hud.open_screen("codex", "chain:" + item), "Codex\nEvery production chain, from the raw resource to the item.", "GhostButton", "codex", 14)
	v.add_child(codex_b)

func register_window(wm) -> void:
	wm.register(self, "chain", _head, func(sz: Vector2, wa: Rect2): return Vector2(wa.end.x - sz.x, wa.position.y + 120.0))

func wm_close() -> void:
	visible = false

func open_item(it: String) -> void:
	item = it
	_sig = ""
	visible = true
	refresh(true)

func refresh(force: bool = false) -> void:
	if not visible:
		return
	Quarter.fit(self, hud, "chain", WIDTH, _scroll, _body, 42.0, 560.0)
	var c: Dictionary = hud.v18.chain_of(item)
	var sig: String = item
	for st in c.get("steps", []):
		sig += "|%s:%s" % [st["id"], st["state"]]
	if sig == _sig and not force:
		return
	_sig = sig
	chain_now = c
	_title.text = ("CHAIN: " + String(c.get("name", item))).to_upper()
	_sum.text = ChainView.summary(c)
	_sum.add_theme_color_override("font_color", P.GREEN if bool(c.get("ok", false)) else P.AMBER)
	Kit.clear(_body)
	_body.add_child(ChainView.build(hud, c, func(def_id: String):
		visible = false
		hud.main.start_place(def_id), func(_tech: String): hud.open_screen("research")))
	Kit.fit(self)
