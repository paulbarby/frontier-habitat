extends Control
## Marks every structure of one type on the map (docs/V4_DESIGN.md §3.4 "highlight of all rooms of
## one type"), set from the Find window. A ring in the family colour round each one, pulsing
## slowly, and a small name tag; an arrow at the view edge for each one outside the view.
## Drawn in 2D from projected ground points (as ui/hud/sector_overlay.gd), so it needs nothing
## from the 3D view. Nothing is drawn while no type is marked.
## Also the optional label layer (set_labels): a name tag over every room, or over the rooms of one
## family; tags never overlap. It adds to the 3D view's own labels (important blocks only).

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

var hud
var def_id := ""
var labels := ""          # label layer: "" off, "all", or a family (category id)
var shown_labels := 0     # tags drawn last frame (tests read it)
var _t := 0.0
var marks: Array = []     # [{id, pos, r, name}] (tests read it)
var _cam_xf := Transform3D()
var _lab_t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_def(d: String) -> void:
	def_id = d
	_collect()
	queue_redraw()

func _collect() -> void:
	marks = []
	if def_id == "" or hud == null or hud.main == null or hud.main.sim == null:
		return
	var blds: Dictionary = hud.main.sim.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if String(b["def"]) == def_id and b.has("pos"):
			marks.append({"id": int(id), "pos": b["pos"], "r": float(b.get("radius", 4.0)), "name": String(b.get("name", ""))})

## Label layer (V4_DESIGN §3.4): the name of every room, or of one family, over the map.
func set_labels(which: String) -> void:
	labels = which
	queue_redraw()

func _process(delta: float) -> void:
	if labels != "" and def_id == "":
		# Labels only: redraw when the camera moves (or 4 times a second for new rooms), not every frame.
		_lab_t += delta
		var cam: Camera3D = hud.main.rig.camera if hud.main.rig != null else null
		if cam != null and (not cam.global_transform.is_equal_approx(_cam_xf) or _lab_t > 0.25):
			_cam_xf = cam.global_transform
			_lab_t = 0.0
			queue_redraw()
	if def_id == "":
		return
	_t += delta
	if int(_t * 4.0) != int((_t - delta) * 4.0):
		_collect()   # 4 Hz: new or removed structures
	queue_redraw()

func _screen(p: Vector2, cam: Camera3D):
	var p3: Vector3 = hud.main.view.to3(p, 0.2)
	if cam.is_position_behind(p3):
		return null
	return cam.unproject_position(p3)

func _draw() -> void:
	shown_labels = 0
	var cam: Camera3D = hud.main.rig.camera if hud.main.rig != null else null
	if cam == null:
		return
	if labels != "":
		_draw_labels(cam)
	if def_id == "" or marks.is_empty():
		return
	var col: Color = P.cat(String(hud.data.bdef(def_id).get("category", "logistics")))
	var pulse: float = 0.55 + 0.45 * sin(_t * 3.0)
	var font: Font = Fonts.get_font("head")
	var vp: Rect2 = get_viewport_rect()
	var inner: Rect2 = vp.grow(-28.0)
	for m in marks:
		var c = _screen(m["pos"], cam)
		if c == null:
			continue
		# Screen radius from a projected rim point.
		var e = _screen((m["pos"] as Vector2) + Vector2(float(m["r"]) + 1.0, 0.0), cam)
		var rr: float = clampf((e as Vector2).distance_to(c) if e != null else 18.0, 10.0, 220.0)
		if inner.has_point(c):
			draw_arc(c, rr + 4.0 * pulse, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 5.0, true)
			draw_arc(c, rr + 4.0 * pulse, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.95), 2.5, true)
			var tag: String = String(m["name"]).to_upper()
			var tw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var tp: Vector2 = c + Vector2(-tw * 0.5, -rr - 12.0)
			draw_rect(Rect2(tp + Vector2(-6, -12), Vector2(tw + 12, 17)), Color(0.03, 0.05, 0.09, 0.8), true)
			draw_rect(Rect2(tp + Vector2(-6, 4), Vector2(tw + 12, 1)), col, true)
			draw_string(font, tp, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(11), P.TEXT)
		else:
			# Off view: an arrow at the edge, pointing to it.
			var ctr: Vector2 = vp.get_center()
			var dir: Vector2 = ((c as Vector2) - ctr).normalized()
			var t: float = INF
			if absf(dir.x) > 0.001:
				t = minf(t, (inner.size.x * 0.5) / absf(dir.x))
			if absf(dir.y) > 0.001:
				t = minf(t, (inner.size.y * 0.5) / absf(dir.y))
			var q: Vector2 = ctr + dir * t
			var n := Vector2(-dir.y, dir.x)
			var tri := PackedVector2Array([q + dir * 12.0, q - dir * 6.0 + n * 8.0, q - dir * 6.0 - n * 8.0])
			draw_colored_polygon(tri, Color(col.r, col.g, col.b, 0.6 + 0.4 * pulse))

func _draw_labels(cam: Camera3D) -> void:
	var font: Font = Fonts.get_font("head")
	var vp: Rect2 = get_viewport_rect()
	var taken: Array = []
	var s = hud.main.sim
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		if String(b.get("kind", "")) != "room" or not b.has("pos"):
			continue
		var cat: String = String(s.bdef(b["def"]).get("category", "logistics"))
		if labels != "all" and cat != labels:
			continue
		var c = _screen(b["pos"], cam)
		if c == null or not vp.has_point(c):
			continue
		var tag: String = String(b.get("name", "")).to_upper()
		var tw: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var r := Rect2((c as Vector2) + Vector2(-tw * 0.5 - 6.0, -9.0), Vector2(tw + 12.0, 16.0))
		var clash := false
		for t in taken:
			if (t as Rect2).intersects(r):
				clash = true
				break
		if clash:
			continue   # never stack tags: the first one drawn keeps the place
		taken.append(r)
		var col: Color = P.cat(cat)
		draw_rect(r, Color(0.03, 0.05, 0.09, 0.78), true)
		draw_rect(Rect2(r.position.x, r.end.y - 2.0, r.size.x, 2.0), col, true)
		draw_string(font, r.position + Vector2(6, 11), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(10), P.TEXT)
		shown_labels += 1