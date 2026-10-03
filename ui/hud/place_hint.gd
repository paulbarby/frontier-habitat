extends PanelContainer
## Placement hint above the build bar while a tool is active: what is being placed, its
## size and cost (red when storage lacks it), whether the spot is valid and why not, the
## suit-range warning, and the keys. Reads main.tool_info every frame.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

var hud
var _icon: TextureRect
var _name: Label
var _size: Label
var _costs: HBoxContainer
var _state_icon: TextureRect
var _state: Label
var _warn: Label
var _keys: Label
var _sig := ""
var pending := {}            # an inline question (remove a structure): {title, lines, on_yes, yes, danger}
var _main_box: VBoxContainer
var _confirm_box: VBoxContainer

func _ready() -> void:
	theme_type_variation = "HudPanel"
	var hst = load("res://ui/theme/ui_theme.gd").panel_style("hud")
	hst.content_margin_top = 6
	hst.content_margin_bottom = 6
	add_theme_stylebox_override("panel", hst)
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)   # placed by _place each frame: bottom edge, centred under the view
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var root_v: VBoxContainer = Kit.vbox(5)
	add_child(root_v)
	# The question comes in place of the rows (Paul, 2026-10-03: no window over the view while you build).
	_confirm_box = Kit.vbox(5)
	_confirm_box.name = "Confirm"
	_confirm_box.visible = false
	root_v.add_child(_confirm_box)
	var v: VBoxContainer = Kit.vbox(5)
	_main_box = v
	root_v.add_child(v)
	var top: HBoxContainer = Kit.hbox(8)
	v.add_child(top)
	_icon = Kit.icon("build", 18, P.CYAN)
	top.add_child(_icon)
	_name = Kit.head("", P.TEXT, 14, "head_wide")
	top.add_child(_name)
	_size = Kit.label("", "NumLabel", 12, P.CYAN)
	top.add_child(_size)
	top.add_child(Kit.gap(8))
	_costs = Kit.hbox(10)
	top.add_child(_costs)
	var st: HBoxContainer = Kit.hbox(6)
	v.add_child(st)
	_state_icon = Kit.icon("sev_ok", 16, P.GREEN)
	st.add_child(_state_icon)
	_state = Kit.label("", "BodyStrong", 14)
	st.add_child(_state)
	_warn = Kit.wrap("", 13, P.AMBER)
	_warn.custom_minimum_size.x = 700
	v.add_child(_warn)
	_keys = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	v.add_child(_keys)

func rebuild() -> void:
	_sig = ""

## A question in this panel (at the bottom edge, never over the view): a title, the consequences, Back and Yes.
## An information-only question (no on_yes) has one OK button.
func ask(title: String, lines: Array, on_yes: Callable, yes_text: String = "Yes", danger: bool = false) -> void:
	pending = {"title": title, "lines": lines, "on_yes": on_yes, "yes": yes_text, "danger": danger}
	Kit.clear(_confirm_box)
	var hd: HBoxContainer = Kit.hbox(8)
	_confirm_box.add_child(hd)
	hd.add_child(Kit.icon("sev_warning" if on_yes.is_valid() else "sev_info", 18, P.RED if danger else P.AMBER))
	var tl: Label = Kit.head(title, P.TEXT, 14, "head_wide")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(tl)
	var back: Button = Kit.button("Back" if on_yes.is_valid() else "OK", func(): cancel_pending(), "Back\nChanges nothing. Esc does the same.", "", "close", 13)
	back.custom_minimum_size.y = 26
	hd.add_child(back)
	if on_yes.is_valid():
		var yes: Button = Kit.button(yes_text, func():
			var cb: Callable = on_yes
			cancel_pending()
			cb.call(), "", "DangerButton" if danger else "ChipButton", "check", 13)
		yes.name = "ConfirmYes"
		yes.custom_minimum_size.y = 26
		hd.add_child(yes)
		_slim(yes)
	_slim(back)
	var full: String = " ".join(lines.map(func(x): return String(x)))
	var txt: Label = Kit.wrap(full, 12, P.TEXT_2)
	txt.custom_minimum_size.x = 800
	txt.max_lines_visible = 3          # a long list keeps three lines; the tooltip has all of it
	txt.custom_minimum_size.y = float(mini(3, int(ceil(float(full.length()) / 118.0)))) * 17.0   # (a trimmed autowrap label measures no height)
	txt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	txt.tooltip_text = full
	txt.mouse_filter = Control.MOUSE_FILTER_PASS
	_confirm_box.add_child(txt)
	Kit.fit(self)

## A button with thin top and bottom margins (the question row stays one line high).
func _slim(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var st: StyleBox = b.get_theme_stylebox(state)
		if st != null:
			var d: StyleBox = st.duplicate()
			d.content_margin_top = 3.0
			d.content_margin_bottom = 3.0
			b.add_theme_stylebox_override(state, d)
	b.custom_minimum_size.y = 0.0

func has_pending() -> bool:
	return not pending.is_empty()

func cancel_pending() -> void:
	pending = {}
	Kit.clear(_confirm_box)

func refresh() -> void:
	pass

## Called every frame by the HUD.
func frame() -> void:
	var m = hud.main
	var info: Dictionary = m.tool_info if "tool_info" in m else {}
	var tool: String = String(info.get("tool", m.tool))
	visible = (tool != "select" or has_pending()) and hud.hud_visible()
	mouse_filter = Control.MOUSE_FILTER_STOP if has_pending() else Control.MOUSE_FILTER_IGNORE
	_confirm_box.visible = has_pending()
	_main_box.visible = not has_pending()
	if not visible:
		return
	var y: float = hud.build_bar.top_y() - 8.0
	var d = hud.data
	var sig := "%s:%s:%s" % [tool, info.get("def", ""), info.get("size", 1)]
	if sig != _sig:
		_sig = sig
		Kit.clear(_costs)
		var cost: Dictionary = info.get("cost", {})
		var totals: Dictionary = hud.kpi.get("totals", {})
		for res in cost:
			var row: Dictionary = totals.get(res, {})
			var free: int = int(row.get("total", 0)) - int(row.get("reserved", 0)) - int(row.get("carried", 0))
			_costs.add_child(Kit.chip(Icons.item(String(res)), "%d" % int(cost[res]), d.item_color(String(res)), "", free >= int(cost[res]), 16))
	match tool:
		"place":
			var def: Dictionary = d.bdef(String(info.get("def", "")))
			var cat: String = String(def.get("category", "logistics"))
			Kit.set_icon(_icon, Icons.category(cat), 18, P.cat(cat))
			_name.text = String(def.get("name", "")).to_upper()
			var sw: String = d.size_word(String(info.get("def", "")), int(info.get("size", 1)))
			_size.text = ("SIZE " + sw) if sw != "" else ""
			_keys.text = "Left click places  ·  R turns  ·  Z / X size  ·  Shift keeps the tool  ·  Right click or Esc cancels"
		"link":
			var kind: String = String(info.get("def", "corridor"))
			Kit.set_icon(_icon, kind, 18, P.CYAN)
			var l: float = float(info.get("length", 0.0))
			_name.text = ("CORRIDOR" if kind == "corridor" else "UTILITY CABLE") + ("  %d m" % int(l) if l > 0.0 else "")
			_size.text = ""
			_keys.text = "Click the first structure, then the second  ·  Shift keeps chaining  ·  Right click or Esc cancels"
		"demolish":
			Kit.set_icon(_icon, "demolish", 18, P.RED)
			_name.text = "REMOVE"
			_size.text = ""
			_keys.text = "Click a structure or a plan  ·  Right click or Esc cancels"
	Kit.fit(self)
	var ok: bool = bool(info.get("ok", false))
	var reason: String = String(info.get("reason", ""))
	if tool == "demolish":
		ok = true
		reason = "Plans are cancelled. Finished structures are taken down; half of the materials come back."
	elif ok and reason == "":
		reason = "Valid spot. Click to place." if tool == "place" else "Click to build."
	Kit.set_icon(_state_icon, "sev_ok" if ok else "sev_critical", 16, P.GREEN if ok else P.RED)
	_state.text = reason
	# A long reason (a lock with its requirements) wraps instead of widening the hint.
	_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if reason.length() > 70 else TextServer.AUTOWRAP_OFF
	_state.custom_minimum_size.x = 700.0 if reason.length() > 70 else 0.0
	_state.add_theme_color_override("font_color", P.GREEN if ok else P.RED)
	var w: String = String(info.get("warning", ""))
	_warn.visible = w != ""
	_warn.text = w
	_place(y)

## Bottom edge, centred between the map and the rail, 8 px above the tab row: one small panel, under the centre zone.
func _place(y: float) -> void:
	Kit.fit(self)
	var vr: Vector2 = get_viewport_rect().size
	var left: float = hud.minimap.get_global_rect().end.x + 8.0 if hud.minimap != null and hud.minimap.visible else 236.0
	var right: float = vr.x - 62.0
	var w: float = size.x
	position = Vector2(clampf((left + right) * 0.5 - w * 0.5, 8.0, maxf(8.0, vr.x - w - 8.0)), y - size.y)
