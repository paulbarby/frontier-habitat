extends PanelContainer
## Bottom-left minimap, drawn from simulation data: terrain tint (height and ore), every
## structure in its category colour (plans hollow), corridors and cables, colonists, the
## Meridian, and the camera's view on the ground. Click or drag to move the camera.
## Overlay toggles sit under the map.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")

const MAP_PX := 196.0

var hud
var _map: Control
var _ov := {}
var _ov_label: Label
var _base: Image
var _tex: ImageTexture
var _tick := 0

class MapView extends Control:
	var mm
	var tex: ImageTexture
	var world_size := 256.0
	var dragging := false
	func _ready() -> void:
		custom_minimum_size = Vector2(196, 196)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		clip_contents = true
	func to_map(p: Vector2) -> Vector2:
		return p / world_size * size
	func to_world(q: Vector2) -> Vector2:
		return q / size * world_size
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				mm.jump(to_world(event.position))
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			mm.jump(to_world(event.position))
			accept_event()
	func _draw() -> void:
		mm.draw_map(self)

func _ready() -> void:
	theme_type_variation = "HudPanel"
	Glass.attach(self)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 8
	offset_bottom = -8
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v: VBoxContainer = Kit.vbox(6)
	add_child(v)
	var head: HBoxContainer = Kit.hbox(6)
	v.add_child(head)
	head.add_child(Kit.icon("map", 14, P.CYAN))
	head.add_child(Kit.head("Map", P.TEXT_2, 11))
	_ov_label = Kit.label("", "SmallLabel", 11, P.TEXT_3)
	_ov_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_ov_label)
	_map = MapView.new()
	_map.mm = self
	v.add_child(_map)
	var row: HBoxContainer = Kit.hbox(4)
	v.add_child(row)
	for spec in [["power", "power", "Power overlay\nWhich structures share a power network."], ["water", "water", "Water overlay\nWhich structures share water."],
			["air", "o2", "Air overlay\nWhich rooms share air, and their oxygen."], ["walk", "follow", "Walking overlay\nWhere colonists can walk."]]:
		var name: String = spec[0]
		var b: Button = Kit.icon_button(spec[1], func(): _toggle(name), spec[2], "SpeedButton", 16, 30)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(46, 28)
		row.add_child(b)
		_ov[name] = b

func _toggle(name: String) -> void:
	hud.set_overlay("" if hud.main.view.overlay == name else name)

func overlay_changed() -> void:
	var cur: String = hud.main.view.overlay
	for n in _ov:
		(_ov[n] as Button).set_pressed_no_signal(n == cur)
	_ov_label.text = ("OVERLAY: " + cur.to_upper()) if cur != "" else ""

func jump(p: Vector2) -> void:
	var m = hud.main
	m.rig.follow_fn = Callable()
	m.rig.jump_to(m.view.to3(p))

func rebuild() -> void:
	_base = _terrain_image()
	_map.world_size = float(hud.main.sim.world.size)
	_paint()
	overlay_changed()

func refresh() -> void:
	if _base == null:
		rebuild()
		return
	# Two times a second is enough for a map; the camera view is drawn every frame.
	_tick += 1
	if _tick % 2 == 0:
		_paint()
	overlay_changed()

func _process(_delta: float) -> void:
	if visible:
		_map.queue_redraw()

## Terrain at one pixel per metre: height tint, deposits darker.
func _terrain_image() -> Image:
	var w = hud.main.sim.world
	var size: int = int(w.size)
	var n: int = w.hn
	var small := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var low := Color("8a5230")
	var high := Color("e0a46a")
	var deps: Array = hud.main.sim.state.get("deposits", [])
	for j in n:
		for i in n:
			var y: float = w.heights[j * n + i]
			var c: Color = low.lerp(high, clampf((y + 4.0) / 9.0, 0.0, 1.0))
			var x: float = i * w.hstep
			var z: float = j * w.hstep
			for d in deps:
				if Vector2(x, z).distance_to(Vector2(d["x"], d["y"])) < float(d["r"]):
					c = c.lerp(Color("3a2a26"), 0.55)
			small.set_pixel(i, j, c.darkened(0.12))
	small.resize(size, size, Image.INTERPOLATE_BILINEAR)
	return small

## Structures, links and colonists painted into one texture (one draw call).
func _paint() -> void:
	var s = hud.main.sim
	var img: Image = _base.duplicate()
	var sz: int = img.get_width()
	var blds: Dictionary = s.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if String(b.get("kind", "")) != "link":
			continue
		var col: Color = Color(0.85, 0.9, 0.95) if b["def"] == "corridor" else Color(0.95, 0.75, 0.3)
		if b["state"] != "active":
			col = col.darkened(0.4)
		_line(img, b["p0"], b["p1"], col, 1 if b["def"] == "corridor" else 0)
	for id in blds:
		var b: Dictionary = blds[id]
		if String(b.get("kind", "")) == "link":
			continue
		var def: Dictionary = s.bdef(b["def"])
		var col: Color = P.cat(String(def.get("category", "logistics")))
		if b["def"] == "lander":
			col = Color("FFD166")
		if b["def"] == "meridian":
			var rot: float = float(b.get("rot", 0.0))
			var half: float = float(b.get("length", def.get("shape", {}).get("capsule_length", 40.0))) * 0.5
			var ax := Vector2(cos(rot), sin(rot)) * half
			var rr: int = int(float(def.get("shape", {}).get("capsule_radius", 7.0)))
			for k in 21:
				_disc(img, (b["pos"] as Vector2) - ax + ax * 2.0 * float(k) / 20.0, rr, Color("C9D3E0"), true)
			continue
		var r: float = maxf(2.0, float(b.get("radius", 2.0)))
		var solid: bool = b["state"] == "active" or b["state"] == "broken"
		_disc(img, b["pos"], int(r), col if b["state"] != "broken" else P.RED, solid)
	for aid in s.state["agents"]:
		var a: Dictionary = s.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var p: Vector2 = a["pos"]
		img.fill_rect(Rect2i(int(p.x) - 1, int(p.y) - 1, 3, 3), Color.WHITE if a["where"] == "out" else Color(0.85, 0.85, 0.85))
	if _tex == null or _tex.get_width() != sz:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	_map.tex = _tex

static func _disc(img: Image, c: Vector2, r: int, col: Color, solid: bool) -> void:
	# One span per row: fast enough to repaint every structure each second.
	var edge: Color = col.lightened(0.35)
	for dy in range(-r, r + 1):
		var y: int = int(c.y) + dy
		if y < 0 or y >= img.get_height():
			continue
		var half: int = int(sqrt(maxf(0.0, float(r * r - dy * dy))))
		var x0: int = int(c.x) - half
		if solid:
			img.fill_rect(Rect2i(x0, y, half * 2 + 1, 1), col)
		img.fill_rect(Rect2i(x0, y, 1, 1), edge)
		img.fill_rect(Rect2i(int(c.x) + half, y, 1, 1), edge)

static func _line(img: Image, a: Vector2, b: Vector2, col: Color, half: int) -> void:
	var n: int = int(maxf(1.0, a.distance_to(b)))
	var w: int = img.get_width()
	for i in n + 1:
		var p: Vector2 = a.lerp(b, float(i) / float(n))
		for oy in range(-half, half + 1):
			for ox in range(-half, half + 1):
				var x: int = int(p.x) + ox
				var y: int = int(p.y) + oy
				if x >= 0 and y >= 0 and x < w and y < w:
					img.set_pixel(x, y, col)

func draw_map(c: Control) -> void:
	var s = hud.main.sim
	var sz: Vector2 = c.size
	if _map.tex != null:
		c.draw_texture_rect(_map.tex, Rect2(Vector2.ZERO, sz), false)
	_draw_view(c, sz.x / float(s.world.size))
	c.draw_rect(Rect2(Vector2.ZERO, sz), P.LINE, false, 1.0)

## The part of the ground the camera sees, as a quadrilateral.
func _draw_view(c: Control, k: float) -> void:
	var m = hud.main
	var cam: Camera3D = m.rig.camera
	if cam == null:
		return
	var vp: Vector2 = c.get_viewport_rect().size
	var ground_y: float = m.rig.focus.y
	var pts := PackedVector2Array()
	for sp in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]:
		var from: Vector3 = cam.project_ray_origin(sp)
		var dir: Vector3 = cam.project_ray_normal(sp)
		var hit: Vector3
		if dir.y < -0.02:
			hit = from + dir * ((ground_y - from.y) / dir.y)
			var flat := Vector2(hit.x - from.x, hit.z - from.z)
			if flat.length() > 320.0:
				hit = from + Vector3(flat.normalized().x, 0, flat.normalized().y) * 320.0
		else:
			var fl := Vector2(dir.x, dir.z).normalized()
			hit = from + Vector3(fl.x, 0, fl.y) * 320.0
		pts.append(Vector2(hit.x, hit.z) * k)
	pts.append(pts[0])
	c.draw_polyline(pts, P.with_alpha(P.CYAN, 0.9), 1.5, true)
	var f: Vector3 = m.rig.focus
	c.draw_circle(Vector2(f.x, f.z) * k, 2.5, P.CYAN)
