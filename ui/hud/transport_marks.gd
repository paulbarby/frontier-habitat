extends Control
## The package transport network on the map (V5_DESIGN §18.5: "an overlay showing the network and flows"). Overlay step "transport"
## of the key O cycle (the last one). A pneumatic tube is a line between its two ends (a transport hub or a room), a hub a square with
## its name, a capsule a small dot that moves along its tube (the colour of its item), a broken link a red cross. A busy tube is amber.
## Drawn in 2D from projected ground points (as ui/hud/find_marks.gd). Data: ui/v18_data.gd transport() (SIM's sim.transport when it
## is there). Nothing is drawn while the overlay is off or the colony has no network.

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

func _pos_of(id: int):
	var b: Dictionary = hud.main.sim.state["buildings"].get(id, {})
	return b["pos"] if b.has("pos") else null

func _draw() -> void:
	tubes_drawn = 0
	hubs_drawn = 0
	capsules_drawn = 0
	if not on or _net.is_empty():
		return
	var cam: Camera3D = hud.main.rig.camera if hud.main.rig != null else null
	if cam == null:
		return
	var broken: Array = _net.get("broken", [])
	for t in _net.get("tubes", []):
		var pa = _pos_of(int(t["a"]))
		var pc = _pos_of(int(t["c"]))
		if pa == null or pc == null:
			continue
		var sa = _screen(pa, cam)
		var sc = _screen(pc, cam)
		if sa == null or sc == null:
			continue
		var bad: bool = not bool(t.get("ok", true)) or broken.has(int(t["b"]))
		var col: Color = P.RED if bad else (P.AMBER if float(t.get("load", 0.0)) >= 0.8 else P.CYAN)
		draw_line(sa, sc, Color(0, 0, 0, 0.5), 6.0, true)
		draw_line(sa, sc, Color(col.r, col.g, col.b, 0.95), 3.0, true)
		tubes_drawn += 1
		if bad:
			var m: Vector2 = ((sa as Vector2) + (sc as Vector2)) * 0.5
			draw_line(m + Vector2(-7, -7), m + Vector2(7, 7), P.RED, 3.0, true)
			draw_line(m + Vector2(-7, 7), m + Vector2(7, -7), P.RED, 3.0, true)
	var font: Font = Fonts.get_font("head")
	for h in _net.get("hubs", []):
		var ph = _pos_of(int(h["b"]))
		if ph == null:
			continue
		var s = _screen(ph, cam)
		if s == null:
			continue
		var ok: bool = bool(h.get("ok", true))
		var col2: Color = P.GOLD if ok else P.RED
		var r := Rect2((s as Vector2) - Vector2(9, 9), Vector2(18, 18))
		draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6), true)
		draw_rect(r, Color(col2.r, col2.g, col2.b, 0.9), true)
		draw_rect(r.grow(-5.0), Color(0.03, 0.05, 0.09, 0.9), true)
		var tag: String = String(hud.main.sim.state["buildings"].get(int(h["b"]), {}).get("name", "")).to_upper()
		var tw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var tp: Vector2 = (s as Vector2) + Vector2(-tw * 0.5, -16.0)
		draw_rect(Rect2(tp + Vector2(-5, -11), Vector2(tw + 10, 15)), Color(0.03, 0.05, 0.09, 0.8), true)
		draw_string(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(10), P.TEXT)
		hubs_drawn += 1
	# Capsules: a dot on its tube, moving with the time (t 0..1 from the first end to the second end of the flow).
	for c in _net.get("transit", []):
		var pf = _pos_of(int(c["from"]))
		var pt = _pos_of(int(c["to"]))
		if pf == null or pt == null:
			continue
		var f = _screen(pf, cam)
		var tt = _screen(pt, cam)
		if f == null or tt == null:
			continue
		var k: float = fposmod(float(c.get("t", 0.0)) + _t * 0.15, 1.0)
		var q: Vector2 = (f as Vector2).lerp(tt as Vector2, k)
		var ic: Color = hud.data.item_color(String(c["res"]))
		draw_circle(q, 6.0, Color(0, 0, 0, 0.7))
		draw_circle(q, 4.0, ic)
		capsules_drawn += 1
