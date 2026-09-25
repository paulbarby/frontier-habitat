extends PanelContainer
## Bottom-left minimap, drawn from simulation data: terrain tint (height and ore), every
## structure in its category colour (plans hollow), corridors and cables, colonists, the
## Meridian, the camera's view on the ground, and detected hazards (version 3: a ring at the
## place, pulsing when it is under 30 s away). Click or drag to move the camera.
## Version 3 map (810 m): the painted image is at most IMG_MAX pixels a side, whatever the
## map size, and the Zoom button switches between the whole map and the colony (a third of
## the map around the lander). Overlay toggles sit under the map; "Hazard zones" tints the
## meteor, wind and quake fields (sim.hazards.zone_at) on the map too.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Icons = preload("res://ui/theme/icons.gd")

const MAP_PX := 196.0
const IMG_MAX := 360
const ZONE_N := 48

var hud
var zoomed := false
var _map: Control
var _ov := {}
var _ov_label: Label
var _zoom_btn: Button
var _base: Image
var _base_zone: Image
var _tex: ImageTexture
var _tick := 0
var _k := 1.0            # image pixels per metre
var _sig := ""           # structures signature: the texture is re-uploaded only when it changes
var _vr := Rect2()       # world rectangle the map shows

class MapView extends Control:
	var mm
	var tex: ImageTexture
	var dragging := false
	func _ready() -> void:
		custom_minimum_size = Vector2(196, 196)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		clip_contents = true
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if event.pressed:
				mm.jump(mm.to_world(event.position, size))
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			mm.jump(mm.to_world(event.position, size))
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
	_ov_label.clip_text = true
	head.add_child(_ov_label)
	_zoom_btn = Kit.icon_button("search", func(): set_zoomed(not zoomed), "Zoom\nThe whole map, or the colony only.", "GhostButton", 13, 22)
	_zoom_btn.toggle_mode = true
	head.add_child(_zoom_btn)
	_map = MapView.new()
	_map.mm = self
	v.add_child(_map)
	var row: HBoxContainer = Kit.hbox(3)
	v.add_child(row)
	for spec in [["power", "power", "Power overlay\nWhich structures share a power network."], ["water", "water", "Water overlay\nWhich structures share water."],
			["air", "o2", "Air overlay\nWhich rooms share air, and their oxygen."], ["walk", "follow", "Walking overlay\nWhere colonists can walk."],
			["hazard", "hazard", "Hazard zones\nWhere meteors, wind and quakes are more likely (meteor red, wind cyan, quake violet)."]]:
		var name: String = spec[0]
		var b: Button = Kit.icon_button(spec[1], func(): _toggle(name), spec[2], "SpeedButton", 15, 28)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(37, 28)
		row.add_child(b)
		_ov[name] = b

func _toggle(name: String) -> void:
	hud.set_overlay("" if hud.main.view.overlay == name else name)

func overlay_changed() -> void:
	var cur: String = hud.main.view.overlay
	for n in _ov:
		(_ov[n] as Button).set_pressed_no_signal(n == cur)
	_ov_label.text = ("OVERLAY: " + cur.to_upper()) if cur != "" else ("COLONY" if zoomed else "")

func set_zoomed(on: bool) -> void:
	zoomed = on
	_zoom_btn.set_pressed_no_signal(on)
	_update_rect()
	overlay_changed()
	_map.queue_redraw()

## The world rectangle on show: the whole map, or a third of it around the colony.
func _update_rect() -> void:
	var ws: float = float(hud.main.sim.world.size)
	if not zoomed or ws <= 300.0:
		_vr = Rect2(0, 0, ws, ws)
		return
	var side: float = maxf(160.0, ws / 3.0)
	var c: Vector2 = hud.data.colony_center()
	var o := Vector2(clampf(c.x - side * 0.5, 0.0, ws - side), clampf(c.y - side * 0.5, 0.0, ws - side))
	_vr = Rect2(o, Vector2(side, side))

func to_map(p: Vector2, sz: Vector2) -> Vector2:
	return (p - _vr.position) / _vr.size * sz

func to_world(q: Vector2, sz: Vector2) -> Vector2:
	return _vr.position + q / sz * _vr.size

func jump(p: Vector2) -> void:
	var m = hud.main
	m.rig.follow_fn = Callable()
	m.rig.jump_to(m.view.to3(p))

func rebuild() -> void:
	_sig = ""
	var ws: float = float(hud.main.sim.world.size)
	_k = float(mini(IMG_MAX, int(ws))) / ws
	_base = _terrain_image()
	_base_zone = null
	_zoom_btn.visible = ws > 300.0
	if not _zoom_btn.visible:
		zoomed = false
	_update_rect()
	_paint()
	overlay_changed()

func refresh() -> void:
	if _base == null:
		rebuild()
		return
	# The structure texture is re-uploaded only when a structure changes (fewer texture uploads);
	# colonists, the camera view and hazards are drawn live.
	_tick += 1
	if _tick % 2 == 0:
		if zoomed:
			_update_rect()
		var sig: String = _structure_sig()
		if sig != _sig:
			_sig = sig
			_paint()
	overlay_changed()

func _process(_delta: float) -> void:
	if visible:
		_map.queue_redraw()

## Terrain: height tint, deposits darker. Sampled so the image stays IMG_MAX pixels or less.
func _terrain_image() -> Image:
	var w = hud.main.sim.world
	var n: int = w.hn
	var stride: int = maxi(1, int(ceil(float(n) / 256.0)))
	var m: int = int(ceil(float(n) / float(stride)))
	var small := Image.create(m, m, false, Image.FORMAT_RGBA8)
	var low := Color("8a5230")
	var high := Color("e0a46a")
	for j in m:
		for i in m:
			var y: float = w.heights[mini(n - 1, j * stride) * n + mini(n - 1, i * stride)]
			small.set_pixel(i, j, low.lerp(high, clampf((y + 4.0) / 9.0, 0.0, 1.0)).darkened(0.12))
	var px: int = int(roundf(float(w.size) * _k))
	small.resize(px, px, Image.INTERPOLATE_BILINEAR)
	# Deposits: darker discs.
	for d in hud.main.sim.state.get("deposits", []):
		var c := Vector2(float(d["x"]), float(d["y"])) * _k
		var r: float = float(d["r"]) * _k
		for yy in range(int(c.y - r), int(c.y + r) + 1):
			for xx in range(int(c.x - r), int(c.x + r) + 1):
				if xx < 0 or yy < 0 or xx >= px or yy >= px:
					continue
				if Vector2(xx, yy).distance_to(c) < r:
					small.set_pixel(xx, yy, small.get_pixel(xx, yy).lerp(Color("3a2a26"), 0.55))
	return small

## Hazard zones (meteor red, wind cyan, quake violet, as the 3D overlay) blended on the terrain; made once.
func _zone_image() -> Image:
	var img: Image = _base.duplicate()
	var s = hud.main.sim
	if not (s.get("hazards") != null and s.hazards.has_method("zone_at")):
		return img
	var ws: float = float(s.world.size)
	var z := Image.create(ZONE_N, ZONE_N, false, Image.FORMAT_RGBA8)
	for j in ZONE_N:
		for i in ZONE_N:
			var r = s.hazards.zone_at(Vector2((float(i) + 0.5) / ZONE_N * ws, (float(j) + 0.5) / ZONE_N * ws))
			if typeof(r) != TYPE_DICTIONARY:
				continue
			# Fields are 0.5..2.0: only the part above 1 tints.
			var met: float = clampf(float(r.get("meteor", 1.0)) - 1.0, 0.0, 1.0)
			var win: float = clampf(float(r.get("wind", 1.0)) - 1.0, 0.0, 1.0)
			var qk: float = clampf(float(r.get("quake", 1.0)) - 1.0, 0.0, 1.0)
			var col := Color(0, 0, 0, 0)
			var a: float = maxf(met, maxf(win, qk))
			if a > 0.0:
				col = (Color("FF5A5F") * met + Color("3EE0FF") * win + Color("A78BFA") * qk) / maxf(0.001, met + win + qk)
				col.a = a * 0.75
			z.set_pixel(i, j, col)
	z.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
	img.blend_rect(z, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	return img

## Structures and links: one change key (count, states, breaches, the overlay).
func _structure_sig() -> String:
	var s = hud.main.sim
	var h := 0
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		h = hash([h, id, b["state"], bool(b.get("breach", false))])
	return "%d:%d:%s" % [s.state["buildings"].size(), h, hud.main.view.overlay == "hazard"]

## Structures and links painted into one texture (one draw call). Colonists: _draw_people.
func _paint() -> void:
	var s = hud.main.sim
	var base: Image = _base
	if hud.main.view.overlay == "hazard":
		if _base_zone == null:
			_base_zone = _zone_image()
		base = _base_zone
	var img: Image = base.duplicate()
	var sz: int = img.get_width()
	var k: float = _k
	var blds: Dictionary = s.state["buildings"]
	for id in blds:
		var b: Dictionary = blds[id]
		if String(b.get("kind", "")) != "link":
			continue
		var col: Color = Color(0.85, 0.9, 0.95) if b["def"] == "corridor" else Color(0.95, 0.75, 0.3)
		if b["state"] != "active":
			col = col.darkened(0.4)
		_line(img, (b["p0"] as Vector2) * k, (b["p1"] as Vector2) * k, col, 1 if b["def"] == "corridor" and k >= 0.8 else 0)
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
			var rr: int = maxi(1, int(float(def.get("shape", {}).get("capsule_radius", 7.0)) * k))
			for q in 21:
				_disc(img, ((b["pos"] as Vector2) - ax + ax * 2.0 * float(q) / 20.0) * k, rr, Color("C9D3E0"), true)
			continue
		var r: float = maxf(1.0, float(b.get("radius", 2.0)) * k)
		var solid: bool = b["state"] == "active" or b["state"] == "broken"
		var bc: Color = col
		if b["state"] == "broken" or not hud.data.breach_of(b).is_empty():
			bc = P.RED
		_disc(img, (b["pos"] as Vector2) * k, int(roundf(r)), bc, solid)
	if _tex == null or _tex.get_width() != sz:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	_map.tex = _tex

static func _disc(img: Image, c: Vector2, r: int, col: Color, solid: bool) -> void:
	# One span per row: fast enough to repaint every structure each second.
	var edge: Color = col.lightened(0.35)
	if r <= 1:
		img.fill_rect(Rect2i(int(c.x) - 1, int(c.y) - 1, 2, 2), col if solid else edge)
		return
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
	var sz: Vector2 = c.size
	if _map.tex != null:
		c.draw_texture_rect_region(_map.tex, Rect2(Vector2.ZERO, sz), Rect2(_vr.position * _k, _vr.size * _k))
	_draw_people(c, sz)
	_draw_hazards(c, sz)
	_draw_view(c, sz)
	c.draw_rect(Rect2(Vector2.ZERO, sz), P.LINE, false, 1.0)

## Colonists: one short line each, two draw calls in all (outside white, inside grey).
func _draw_people(c: Control, sz: Vector2) -> void:
	var outp := PackedVector2Array()
	var inp := PackedVector2Array()
	for aid in hud.main.sim.state["agents"]:
		var a: Dictionary = hud.main.sim.state["agents"][aid]
		if a["state"] != "alive":
			continue
		var q: Vector2 = to_map(a["pos"], sz)
		var arr: PackedVector2Array = outp if a["where"] == "out" else inp
		arr.append(q - Vector2(1.0, 0.0))
		arr.append(q + Vector2(1.0, 0.0))
	if not outp.is_empty():
		c.draw_multiline(outp, Color.WHITE, 2.0)
	if not inp.is_empty():
		c.draw_multiline(inp, Color(0.85, 0.85, 0.85), 2.0)

## Detected hazards: a ring at the place (its radius, at least 4 px), pulsing when it is
## under 30 s away; going on now: filled. Whole-map events tint the map edge.
func _draw_hazards(c: Control, sz: Vector2) -> void:
	if hud.hazard == null:
		return
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	var edge := false
	for r in hud.hazard._rows:
		var col: Color = hud.hazard._col(r)
		if r["pos"] == null:
			edge = edge or bool(r["active"]) or float(r["eta_s"]) < 30.0
			continue
		var q: Vector2 = to_map(r["pos"], sz)
		var rad: float = maxf(4.0, float(r["radius"]) / _vr.size.x * sz.x)
		var soon: bool = not bool(r["active"]) and float(r["eta_s"]) < 30.0
		var a: float = 0.55 + 0.45 * sin(t * 6.0) if soon else 1.0
		if bool(r["active"]):
			c.draw_circle(q, rad, P.with_alpha(col, 0.35))
		c.draw_arc(q, rad, 0.0, TAU, 20, P.with_alpha(col, a), 1.5, true)
		c.draw_line(q + Vector2(-2, 0), q + Vector2(2, 0), col, 1.0)
		c.draw_line(q + Vector2(0, -2), q + Vector2(0, 2), col, 1.0)
	if edge:
		c.draw_rect(Rect2(Vector2.ONE, sz - Vector2(2, 2)), P.with_alpha(P.AMBER, 0.5 + 0.4 * sin(t * 5.0)), false, 2.0)

## The part of the ground the camera sees, as a quadrilateral.
func _draw_view(c: Control, sz: Vector2) -> void:
	var m = hud.main
	var cam: Camera3D = m.rig.camera
	if cam == null:
		return
	var vp: Vector2 = c.get_viewport_rect().size
	var ground_y: float = m.rig.focus.y
	var far: float = maxf(320.0, float(m.sim.world.size) * 0.9)
	var pts := PackedVector2Array()
	for sp in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]:
		var from: Vector3 = cam.project_ray_origin(sp)
		var dir: Vector3 = cam.project_ray_normal(sp)
		var hit: Vector3
		if dir.y < -0.02:
			hit = from + dir * ((ground_y - from.y) / dir.y)
			var flat := Vector2(hit.x - from.x, hit.z - from.z)
			if flat.length() > far:
				hit = from + Vector3(flat.normalized().x, 0, flat.normalized().y) * far
		else:
			var fl := Vector2(dir.x, dir.z).normalized()
			hit = from + Vector3(fl.x, 0, fl.y) * far
		pts.append(to_map(Vector2(hit.x, hit.z), sz))
	pts.append(pts[0])
	c.draw_polyline(pts, P.with_alpha(P.CYAN, 0.9), 1.5, true)
	var f: Vector3 = m.rig.focus
	c.draw_circle(to_map(Vector2(f.x, f.z), sz), 2.5, P.CYAN)
