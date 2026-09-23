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

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var v: VBoxContainer = Kit.vbox(5)
	add_child(v)
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
	_warn.custom_minimum_size.x = 520
	v.add_child(_warn)
	_keys = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	v.add_child(_keys)

func rebuild() -> void:
	_sig = ""

func refresh() -> void:
	pass

## Called every frame by the HUD.
func frame() -> void:
	var m = hud.main
	var info: Dictionary = m.tool_info if "tool_info" in m else {}
	var tool: String = String(info.get("tool", m.tool))
	visible = tool != "select" and hud.hud_visible()
	if not visible:
		return
	var y: float = hud.build_bar.top_y() - 8.0
	offset_bottom = y - get_viewport_rect().size.y
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
			_size.text = ("SIZE " + d.SIZE_NAMES[clampi(int(info.get("size", 1)), 0, 3)]) if d.has_sizes(String(info.get("def", ""))) else ""
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
	_state.add_theme_color_override("font_color", P.GREEN if ok else P.RED)
	var w: String = String(info.get("warning", ""))
	_warn.visible = w != ""
	_warn.text = w
