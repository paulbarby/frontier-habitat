extends PanelContainer
## Meltdown warning (V4_DESIGN §4.2: "the player sees it coming"), while any reactor is past normal: the
## phase, the reactor, the time to the next phase and what to do. Critical pulses. Click: the reactor
## window. A card in the Events tab, and the urgent line, of the panel manager (it places it).
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
	_sub = Kit.wrap("", 13, P.TEXT)
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
