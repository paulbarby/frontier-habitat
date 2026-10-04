extends Control
## The package transport network on the map (V5_DESIGN §18.5: "an overlay showing the network and flows"). Overlay step "transport"
## of the key O cycle (the last one). A pneumatic tube is a line between its two ends (a transport hub or a room), a hub a square with
## its name, a capsule a small dot that moves along its tube (the colour of its item), a broken link a red cross. A busy tube is amber.
## Drawn in 2D from projected ground points (as ui/hud/find_marks.gd). Data: ui/v18_data.gd (SIM sim.transport).
## Nothing is drawn while the overlay is off or the colony has no network.

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

var hud
var on := false
var tubes_drawn := 0       # tubes, hubs and capsules drawn last frame (tests)
var hubs_drawn := 0
var capsules_drawn := 0
var _t := 0.0
var _net: Dictionary = {}
var _net_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_on(v: bool) -> void:
	on = v
	_net_t = 99.0
	queue_redraw()

func _process(delta: float) -> void:
	if not on:
		return
	_t += delta
	_net_t += delta
	if _net_t > 0.5:
		_net_t = 0.0
		_net = hud.v18.transport()
	queue_redraw()

func _screen(p: Vector2, cam: Camera3D):
	var p3: Vector3 = hud.main.view.to3(p, 0.6)
	if cam.is_position_behind(p3):
		return null
	return cam.unproject_position(p3)

func _draw() -> void:
	tubes_drawn = 0
	hubs_drawn = 0
	capsules_drawn = 0
	if not on or _net.is_empty() or not bool(_net.get("enabled", false)):
		return
	var cam: Camera3D = hud.main.rig.camera if hud.main.rig != null else null
	if cam == null:
		return
	for t in _net.get("tubes", []):
		var sa = _screen(t["p0"], cam)
		var sc = _screen(t["p1"], cam)
		if sa == null or sc == null:
			continue
		var bad: bool = not bool(t.get("ok", true))
		var busy: bool = float(t.get("busy_s", 0.0)) > 2.0
		var col: Color = P.RED if bad else (P.AMBER if busy else P.CYAN)
		draw_line(sa, sc, Color(0, 0, 0, 0.5), 7.0, true)
		draw_line(sa, sc, Color(col.r, col.g, col.b, 0.95), 4.0, true)
		tubes_drawn += 1
		if bad:
			var m: Vector2 = ((sa as Vector2) + (sc as Vector2)) * 0.5
			draw_line(m + Vector2(-8, -8), m + Vector2(8, 8), P.RED, 3.0, true)
			draw_line(m + Vector2(-8, 8), m + Vector2(8, -8), P.RED, 3.0, true)
	var font: Font = Fonts.get_font("head")
	for h in _net.get("hubs", []):
		var s = _screen(h["pos"], cam)
		if s == null:
			continue
		var ok: bool = bool(h.get("ok", true))
		var col2: Color = P.GOLD if ok else P.RED
		var r := Rect2((s as Vector2) - Vector2(9, 9), Vector2(18, 18))
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6), true)
		draw_rect(r, Color(col2.r, col2.g, col2.b, 0.9), true)
		draw_rect(r.grow(-5.0), Color(0.03, 0.05, 0.09, 0.9), true)
		var tag: String = String(h["name"]).to_upper()
		var tw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var tp: Vector2 = (s as Vector2) + Vector2(-tw * 0.5, -16.0)
		draw_rect(Rect2(tp + Vector2(-5, -11), Vector2(tw + 10, 15)), Color(0.03, 0.05, 0.09, 0.8), true)
		draw_string(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(10), P.TEXT)
		hubs_drawn += 1
	# Capsules: a dot with the colour of its item, where SIM says it is now (in a tube, or waiting in a hub).
	for c in hud.v18.capsules():
		var q = _screen(c["pos"], cam)
		if q == null:
			continue
		var ic: Color = hud.data.item_color(String(c["res"]))
		draw_circle(q, 7.0, Color(0, 0, 0, 0.7))
		draw_circle(q, 5.0, P.RED if bool(c["stuck"]) else ic)
		capsules_drawn += 1
