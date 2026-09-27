extends PanelContainer
## Meltdown warning (V4_DESIGN §4.2: "the player sees it coming"): a banner at the top centre while
## any reactor is past normal: the phase, the reactor, the time to the next phase and what to do.
## Critical pulses red. Click: the reactor window. Sits under the hazard banner when both show.
## Data: ui/v4_data.gd reactor_alarm() (SIM sim.reactors.list()). Nothing shows while every reactor is normal.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")

var hud
var _icon: TextureRect
var _text: Label
var _sub: Label
var _t := 0.0
var shown_phase := ""     # tests

func _ready() -> void:
	theme_type_variation = "ToastPanel"
	add_theme_stylebox_override("panel", load("res://ui/theme/ui_theme.gd").panel_style("toast"))   # own copy: the accent colour changes
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	offset_top = 76
	custom_minimum_size.x = 460
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "Reactor\nClick: the reactor controls (SCRAM, Restart, Dump coolant, Evacuate)."
	visible = false
	var h: HBoxContainer = Kit.hbox(10)
	add_child(h)
	_icon = Kit.icon("reactor", 24, P.AMBER)
	h.add_child(_icon)
	var v: VBoxContainer = Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	_text = Kit.head("", P.AMBER, 14, "head_wide")
	v.add_child(_text)
	_sub = Kit.label("", "", 13, P.TEXT)   # one line; the banner is 460 px wide or more
	v.add_child(_sub)
	gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			hud.reactor_win.visible = true)

func _process(delta: float) -> void:
	if hud == null or hud.v4 == null:
		return
	_t += delta
	var r: Dictionary = hud.v4.reactor_alarm()
	visible = not r.is_empty()
	if r.is_empty():
		shown_phase = ""
		return
	var ph: String = String(r["phase"])
	shown_phase = ph
	var col: Color = P.RED if ph != "warning" else P.AMBER
	var st = get_theme_stylebox("panel")
	if st != null and "accent_left" in st:
		st.accent_left = col
	_icon.modulate = col
	_text.add_theme_color_override("font_color", col)
	var next_s: float = float(r.get("next_phase_s", -1.0))
	_text.text = "REACTOR %s: %s" % [ph.to_upper(), String(r["name"]).to_upper()]
	if ph == "breach":
		_sub.text = "Breach. Keep everyone out of the %d m radiation zone." % int(r["zone_r"])
	elif bool(r.get("scram", false)) and next_s < 0.0:
		_sub.text = "SCRAM: no fission. The core cools; keep people out of %d m." % int(r["zone_r"])
	elif next_s >= 0.0:
		_sub.text = "%s in %s. SCRAM it and dump coolant; evacuate the %d m zone." % ["Breach" if ph == "critical" else "Critical", Kit.clock(next_s), int(r["zone_r"])]
	else:
		_sub.text = "Cooling down. Keep the coolant coming."
	modulate.a = (0.75 + 0.25 * sin(_t * 6.0)) if ph == "critical" else 1.0
	Kit.fit(self)   # shrink to the text (a wrapped line measured narrow first would leave it tall)
	position.x = floorf((get_viewport_rect().size.x - size.x) * 0.5)
	# Under the hazard banner when both show.
	if hud.hazard_banner != null and hud.hazard_banner.visible:
		offset_top = hud.hazard_banner.get_global_rect().end.y + 8.0
	else:
		offset_top = 76.0
