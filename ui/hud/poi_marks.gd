extends Control
## Points of interest in the 3D view (SIM milestone 7): a tag over each FOUND point of interest,
## with its kind icon, its name and what a visit needs ("on foot", "a scientist"); a visited one is
## dim with a tick. The target one (from Find) pulses. Drawn in 2D from projected ground points
## (as ui/hud/find_marks.gd), redrawn only when the camera moves or the list changes.
## Data: ui/v4_data.gd pois() (SIM sim.explore.pois()).

const P = preload("res://ui/theme/palette.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Icons = preload("res://ui/theme/icons.gd")
const V4 = preload("res://ui/v4_data.gd")

var hud
var target := -1          # the point of interest picked in Find (pulses)
var shown := 0            # tags on screen at the last redraw (tests)
var _rows: Array = []
var _sig := ""
var _cam_xf := Transform3D()
var _t := 0.0
var _poll := 1.0          # first poll at once
var _frames := 0          # also every 20 frames (tests run fast frames)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Rasterise the point-of-interest icons now (tags 20 px, minimap 12 px), not in the frame that
	# finds the first one.
	for ic in V4.POI_ICON.values() + ["satellite", "check"]:
		Icons.tex(String(ic), 20)
		Icons.tex(String(ic), 12)

func _process(delta: float) -> void:
	if hud == null or hud.main == null or hud.main.sim == null or hud.v4 == null:
		return
	_poll += delta
	_frames += 1
	if _poll >= 0.5 or _frames >= 20:
		_poll = 0.0
		_frames = 0
		_rows = hud.v4.pois()
		var sig := ""
		for p in _rows:
			sig += "%d:%s|" % [int(p["id"]), p["visited"]]
		if sig != _sig:
			_sig = sig
			_redraw()
	if _rows.is_empty():
		return
	var cam: Camera3D = hud.main.rig.camera if hud.main.rig != null else null
	if target >= 0:
		_t += delta
		_redraw()
	elif cam != null and not cam.global_transform.is_equal_approx(_cam_xf):
		_cam_xf = cam.global_transform
		_redraw()

func _redraw() -> void:
	shown = _on_screen().size()
	queue_redraw()

## The tags on screen now: [{p: poi row, c: screen point}].
func _on_screen() -> Array:
	var out: Array = []
	var cam: Camera3D = hud.main.rig.camera if hud != null and hud.main != null and hud.main.rig != null else null
	if cam == null:
		return out
	var vp: Rect2 = get_viewport_rect().grow(-8.0)
	for p in _rows:
		var p3: Vector3 = hud.main.view.to3(p["pos"], 0.5)
		if cam.is_position_behind(p3):
			continue
		var c: Vector2 = cam.unproject_position(p3)
		if vp.has_point(c):
			out.append({"p": p, "c": c})
	return out

func _draw() -> void:
	var font: Font = Fonts.get_font("head")
	var small: Font = Fonts.get_font("body")
	for e in _on_screen():
		var p: Dictionary = e["p"]
		var c: Vector2 = e["c"]
		var col: Color = V4.POI_COLOR.get(String(p["kind"]), P.TEXT)
		var vis: bool = bool(p.get("visited", false))
		var a: float = 0.55 if vis else 1.0
		var name: String = String(p["name"]).to_upper()
		var sub: String = "visited" if vis else "needs " + String(p["need_short"])
		var tw: float = maxf(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(11)).x, small.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(11)).x)
		var box := Rect2(c + Vector2(-(tw + 34.0) * 0.5, -48.0), Vector2(tw + 34.0, 34.0))
		# Stem to the ground point and a ring on the ground.
		draw_line(c, Vector2(c.x, box.end.y), Color(col.r, col.g, col.b, 0.8 * a), 1.5)
		var pr: float = 5.0 + (3.0 * (0.5 + 0.5 * sin(_t * 4.0)) if int(p["id"]) == target else 0.0)
		draw_arc(c, pr, 0.0, TAU, 20, Color(col.r, col.g, col.b, a), 2.0, true)
		draw_rect(box, Color(0.03, 0.05, 0.09, 0.82 * a + 0.1), true)
		draw_rect(Rect2(box.position.x, box.end.y - 2.0, box.size.x, 2.0), Color(col.r, col.g, col.b, a), true)
		var tex: Texture2D = Icons.tex(String(V4.POI_ICON.get(String(p["kind"]), "star")), 20)
		if tex != null:
			draw_texture_rect(tex, Rect2(box.position + Vector2(6, 7), Vector2(18, 18)), false, Color(col.r, col.g, col.b, a))
		draw_string(font, box.position + Vector2(28, 14), name, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(11), Color(P.TEXT.r, P.TEXT.g, P.TEXT.b, a))
		draw_string(small, box.position + Vector2(28, 28), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, P.fs(11), P.GREEN if vis else P.TEXT_2)
