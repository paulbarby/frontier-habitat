extends PanelContainer
## Bottom-left minimap, drawn from simulation data: terrain tint (height and ore), every
## structure in its category colour (plans hollow), corridors and cables, colonists, the
## Meridian, the camera's view on the ground, and detected hazards (version 3: a ring at the
## place, pulsing when it is under 30 s away). Click or drag to move the camera.
## Version 4: family icons on the rooms at the colony zoom, and rings on the structures marked from Find.
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
var _planner := {}       # planner overlay images, made once per map: "radiation", "sun"
var _legend: Label
const PLANNER := ["radiation", "sun", "resources", "explored", "range"]
const Fonts = preload("res://ui/theme/fonts.gd")
const V4 = preload("res://ui/v4_data.gd")
var _fog_rev := -1        # fog revision the fog image was made from
var _fog_img: Image       # unexplored cells darkened, at the texture size
var _fog_strong := false  # the fog image was made for the Explored overlay (darker)
var _zone_n := -1         # zones the radiation overlay image was made with

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
	_ov_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_ov_label)
	_zoom_btn = Kit.icon_button("search", func(): set_zoomed(not zoomed), "Zoom\nThe whole map, or the colony only.", "GhostButton", 13, 22)
	_zoom_btn.toggle_mode = true
	head.add_child(_zoom_btn)
	_map = MapView.new()
	_map.mm = self
	v.add_child(_map)
	_map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # the map stays square if the panel is wider
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
	# Version 4 planner overlays (V4_DESIGN §6): radiation, sun (share of the day in sunlight),
	# resources (deposits by tier), as small buttons in the map header, so the panel is no taller
	# than in version 3 and the alerts keep their room above it. The 3D layers are RENDER's.
	for spec in [["radiation", "radiation", "Radiation\nmSv per hour on the ground. Dark: safe. Red: dangerous for people outside."],
			["sun", "sun", "Sun\nThe share of the day in sunlight. Crater floors and slopes behind peaks get less: solar makes less there."],
			["resources", "ore", "Resources\nMineral deposits by tier: basic (grey), mid (cyan), high-end (gold). High-end lies far out, on dangerous ground."],
			["explored", "explored", "Explored area\nDark: not explored yet. Colonists outside, rovers, hoppers and the survey satellite explore. Points of interest show when they are found."],
			["range", "range", "Vehicle range\nA ring round each vehicle: how far it can go and come back on the charge or fuel it has now."]]:
		var name2: String = spec[0]
		var b2: Button = Kit.icon_button(spec[1], func(): _toggle(name2), spec[2], "GhostButton", 13, 22)
		b2.toggle_mode = true
		head.add_child(b2)
		head.move_child(b2, head.get_child_count() - 2)
		_ov[name2] = b2
	# Compact buttons: 3 px content margins, so the header and the overlay row stay low and the
	# alerts panel above keeps its room (the theme margins made them 38-40 px tall).
	(func():
		for b3 in _ov.values() + [_zoom_btn]:
			_compact(b3)).call_deferred()
	_legend = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	_legend.visible = false
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.custom_minimum_size.x = 196
	v.add_child(_legend)

func _compact(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(st)
		if sb == null:
			continue
		var c: StyleBox = sb.clone() if sb.has_method("clone") else sb.duplicate()
		c.content_margin_left = 3
		c.content_margin_right = 3
		c.content_margin_top = 3
		c.content_margin_bottom = 3
		b.add_theme_stylebox_override(st, c)
	b.expand_icon = true   # the icon fits the button (the icon texture is drawn at twice its size)
	b.custom_minimum_size = Vector2(26, 24) if b.theme_type_variation == "GhostButton" else Vector2(37, 26)

func _toggle(name: String) -> void:
	hud.set_overlay("" if hud.main.view.overlay == name else name)

func overlay_changed() -> void:
	var cur: String = hud.main.view.overlay
	for n in _ov:
		(_ov[n] as Button).set_pressed_no_signal(n == cur)
	_ov_label.text = cur.to_upper() if cur != "" else ("COLONY" if zoomed else "")
	if _legend != null:
		_legend.visible = PLANNER.has(cur)
		match cur:
			"radiation": _legend.text = "Dark: under 0.5 mSv/h. Amber: 1 to 2. Red: over 3."
			"sun": _legend.text = "Bright: full sun. Dark: less than half the day in sunlight."
			"resources": _legend.text = "Grey: basic. Cyan: mid tier. Gold: high-end."
			"explored": _legend.text = _explored_legend()
			"range": _legend.text = _range_legend()
	# The exploration buttons show only on a map with fog (the 2,560 m planet).
	if _ov.has("explored"):
		(_ov["explored"] as Button).visible = hud.v4 != null and hud.v4.explore_active()
	if _ov.has("range"):
		(_ov["range"] as Button).visible = hud.v4 != null and hud.v4.live("vehicles")

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
	_planner = {}
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

const PLANET_PALETTE := {
	"dry": {"low": Color("8a5230"), "high": Color("e0a46a"), "dark": 0.12, "deposit": Color("3a2a26")},
	"cold": {"low": Color("8a96a8"), "high": Color("c9d3de"), "dark": 0.0, "frost": 0.7, "deposit": Color("3a4252")},
	"airless": {"low": Color("4a4a4e"), "high": Color("8c8c90"), "dark": 0.0, "deposit": Color("202024")},
}

## Terrain: height tint, deposits darker. Sampled so the image stays IMG_MAX pixels or less.
func _terrain_image() -> Image:
	var w = hud.main.sim.world
	var n: int = w.hn
	var stride: int = maxi(1, int(ceil(float(n) / 256.0)))
	var m: int = int(ceil(float(n) / float(stride)))
	var small := Image.create(m, m, false, Image.FORMAT_RGBA8)
	# The palette follows the planet (RENDER-to-UI 2026-10-02): dry = rust, cold = blue-white with frost
	# patches, airless = greys (crater floors dark).
	var pal: Dictionary = PLANET_PALETTE.get(String(hud.main.sim.state.get("planet", "dry")), PLANET_PALETTE["dry"])
	var low: Color = pal["low"]
	var high: Color = pal["high"]
	var frost: float = float(pal.get("frost", 0.0))
	for j in m:
		for i in m:
			var y: float = w.heights[mini(n - 1, j * stride) * n + mini(n - 1, i * stride)]
			var c0: Color = low.lerp(high, clampf((y + 4.0) / 9.0, 0.0, 1.0)).darkened(float(pal["dark"]))
			if frost > 0.0 and sin(float(i) * 0.37 + sin(float(j) * 0.21) * 2.0) * cos(float(j) * 0.29 + float(i) * 0.05) > 0.5:
				c0 = c0.lerp(Color("e4ebf3"), frost)
			small.set_pixel(i, j, c0)
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
					small.set_pixel(xx, yy, small.get_pixel(xx, yy).lerp(pal["deposit"], 0.55))
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

## Planner overlays on the terrain, made once per map on a coarse grid (ZONE_N a side):
## radiation from sim.world.rad_at, sun share from sim.world.sun_vis over 8 times of the day.
func _planner_image(kind: String) -> Image:
	var img: Image = _base.duplicate()
	var s = hud.main.sim
	var w = s.world
	var ws: float = float(w.size)
	var z := Image.create(ZONE_N, ZONE_N, false, Image.FORMAT_RGBA8)
	var day_len: float = float(s.bal["day_length"])
	var daylight: float = float(s.planet.get("daylight_seconds", day_len * 0.6))
	var suns: Array = []
	if kind == "sun" and w.has_method("sun_angles"):
		for k in 8:
			suns.append(w.sun_angles(daylight * (float(k) + 0.5) / 8.0, daylight, day_len))
	for j in ZONE_N:
		for i in ZONE_N:
			var p := Vector2((float(i) + 0.5) / ZONE_N * ws, (float(j) + 0.5) / ZONE_N * ws)
			var col := Color(0, 0, 0, 0)
			if kind == "radiation" and w.has_method("rad_at"):
				var r: float = float(hud.v4.rad_at(p)) if hud.v4 != null else float(w.rad_at(p.x, p.y))
				if r >= 3.0:
					col = Color(1.0, 0.35, 0.37, 0.8)
				elif r >= 1.0:
					col = Color(1.0, 0.71, 0.28, 0.35 + 0.2 * (r - 1.0))
				else:
					col = Color(0.02, 0.05, 0.1, 0.35 * (1.0 - r))
			elif kind == "sun" and not suns.is_empty():
				var tot := 0.0
				for sa in suns:
					tot += float(w.sun_vis(p, float(sa["elev_deg"]), float(sa["bearing"])))
				var share: float = tot / float(suns.size())
				col = Color(1.0, 0.85, 0.4, 0.45 * share) if share >= 0.5 else Color(0.02, 0.03, 0.08, 0.7 * (1.0 - share))
			z.set_pixel(i, j, col)
	z.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
	img.blend_rect(z, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
	return img

## Resources overlay: every deposit as a dot in its tier colour (live, over the map).
func _draw_resources(c: Control, sz: Vector2) -> void:
	var deps = hud.main.sim.state.get("deposits", [])
	var list: Array = deps.values() if typeof(deps) == TYPE_DICTIONARY else deps
	for d in list:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var p := Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		if d.has("pos") and typeof(d["pos"]) == TYPE_VECTOR2:
			p = d["pos"]
		var q: Vector2 = to_map(p, sz)
		if q.x < 0.0 or q.y < 0.0 or q.x > sz.x or q.y > sz.y:
			continue
		if not bool(d.get("surveyed", true)):
			continue   # not surveyed yet (fog): the player does not know it is there
		var tier: int = int(d.get("tier", 1))
		var col: Color = [Color("B0B6BE"), Color("3EE0FF"), Color("FFD166")][clampi(tier - 1, 0, 2)]
		c.draw_circle(q, 3.5, Color(0, 0, 0, 0.6))
		c.draw_circle(q, 2.5, col)

## Vehicle range legend: the rings, and each vehicle's reach there and back (a rover on a full
## charge reaches farther than the map: the legend says so, the ring is off the map then).
func _range_legend() -> String:
	var parts: Array = []
	var ws: float = float(hud.main.sim.world.size)
	for v in hud.v4.vehicles():
		var reach: float = float(v.get("range_left_m", 0.0)) * 0.5
		parts.append("%s %s" % [String(v["name"]), ("%.1f km" % (reach / 1000.0)) if reach < ws * 1.5 else "the whole map"])
		if parts.size() >= 3:
			break
	var txt: String = "Rings: how far each vehicle can go and come back. Cyan: rover. Gold: hopper."
	if not parts.is_empty():
		txt += " " + ", ".join(parts) + "."
	return txt

## Explored overlay legend: the share explored and the satellites' bands.
func _explored_legend() -> String:
	if hud.v4 == null or not hud.v4.explore_active():
		return "No fog on this map: all of it is known."
	var txt: String = "%d%% explored. Dark: not explored yet." % int(roundf(hud.v4.explored_share() * 100.0))
	for s in hud.v4.sats():
		txt += " %s: %d of %d bands%s." % [String(s["name"]), int(s["bands_done"]), int(s["bands"]), "" if bool(s["uplink"]) else ", no uplink (a comms tower with power)"]
	return txt

## Fog of war (SIM milestone 7): the unexplored cells darkened, made again only when the fog
## revision changes. strong: the Explored overlay (darker, so the edge is clear).
func _fog_image(w: int, strong: bool) -> Image:
	var fg: Dictionary = hud.v4.fog() if hud.v4 != null else {}
	if fg.is_empty():
		return null
	if _fog_img != null and _fog_rev == int(fg.get("rev", 0)) and _fog_strong == strong and _fog_img.get_width() == w:
		return _fog_img
	var n: int = int(fg["n"])
	var bits: PackedByteArray = fg["bits"]
	# One byte per cell (an LA8 image: grey 10, alpha dark or 0), made from SIM's bits in one pass of
	# byte writes; set_pixel on 25,600 cells cost several times more (POI-find frame, 2026-09-28).
	var a_dark: int = 219 if strong else 158
	var la := PackedByteArray()
	la.resize(n * n * 2)
	for k in n * n:
		la[k * 2] = 10
		la[k * 2 + 1] = 0 if bits[k] != 0 else a_dark
	var img := Image.create_from_data(n, n, false, Image.FORMAT_LA8, la)
	img.convert(Image.FORMAT_RGBA8)
	# The fog covers the whole world; the texture is world size x _k pixels.
	var ws: float = float(hud.main.sim.world.size)
	var cover: int = int(roundf(float(n) * float(fg["cell"]) * _k))
	img.resize(maxi(1, cover), maxi(1, cover), Image.INTERPOLATE_BILINEAR)
	if img.get_width() != w:
		var full := Image.create(w, w, false, Image.FORMAT_RGBA8)
		full.blit_rect(img, Rect2i(0, 0, mini(w, img.get_width()), mini(w, img.get_height())), Vector2i.ZERO)
		img = full
	_fog_img = img
	_fog_rev = int(fg.get("rev", 0))
	_fog_strong = strong
	return img

## Structures and links: one change key (count, states, breaches, the overlay).
func _structure_sig() -> String:
	var s = hud.main.sim
	var h := 0
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		h = hash([h, id, b["state"], bool(b.get("breach", false))])
	var fog_rev: int = int(hud.v4.fog().get("rev", -1)) if hud.v4 != null else -1
	var zn: int = hud.v4.zones().size() if hud.v4 != null else 0
	return "%d:%d:%s:%d:%d" % [s.state["buildings"].size(), h, hud.main.view.overlay, fog_rev, zn]

## Structures and links painted into one texture (one draw call). Colonists: _draw_people.
func _paint() -> void:
	var s = hud.main.sim
	var base: Image = _base
	if hud.main.view.overlay == "hazard":
		if _base_zone == null:
			_base_zone = _zone_image()
		base = _base_zone
	elif hud.main.view.overlay == "radiation" or hud.main.view.overlay == "sun":
		var ov: String = hud.main.view.overlay
		# Radiation includes the zones of reactor breaches (SIM reactors.rad_at): made again when they change.
		var zn: int = hud.v4.zones().size() if hud.v4 != null else 0
		if ov == "radiation" and zn != _zone_n:
			_planner.erase("radiation")
			_zone_n = zn
		if not _planner.has(ov):
			_planner[ov] = _planner_image(ov)
		base = _planner[ov]
	var img: Image = base.duplicate()
	var fog: Image = _fog_image(img.get_width(), hud.main.view.overlay == "explored")
	if fog != null:
		img.blend_rect(fog, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)
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
	if hud.main.view.overlay == "resources":
		_draw_resources(c, sz)
	_draw_icons(c, sz)
	_draw_zones(c, sz)
	if hud.main.view.overlay == "range":
		_draw_range(c, sz)
	_draw_v4(c, sz)
	_draw_explore(c, sz)
	_draw_people(c, sz)
	_draw_hazards(c, sz)
	_draw_view(c, sz)
	c.draw_rect(Rect2(Vector2.ZERO, sz), P.LINE, false, 1.0)

## Version 4 (V4_DESIGN §3.4): family icons on the rooms, when a room is at least 4 px across on
## the map (the colony zoom, or a small map), and a ring on each structure marked from Find.
func _draw_icons(c: Control, sz: Vector2) -> void:
	var s = hud.main.sim
	var ppm: float = sz.x / maxf(1.0, _vr.size.x)   # map pixels per metre
	var marked: String = hud.find_marks.def_id if hud.find_marks != null else ""
	for id in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][id]
		if String(b.get("kind", "")) == "link" or not b.has("pos"):
			continue
		var q: Vector2 = to_map(b["pos"], sz)
		if q.x < -8.0 or q.y < -8.0 or q.x > sz.x + 8.0 or q.y > sz.y + 8.0:
			continue
		var rpx: float = float(b.get("radius", 2.0)) * ppm
		if marked != "" and String(b["def"]) == marked:
			var col: Color = P.cat(String(s.bdef(b["def"]).get("category", "logistics")))
			c.draw_arc(q, maxf(rpx, 3.0) + 3.0, 0.0, TAU, 20, Color(0, 0, 0, 0.6), 3.0, true)
			c.draw_arc(q, maxf(rpx, 3.0) + 3.0, 0.0, TAU, 20, col, 1.5, true)
		if rpx < 4.0 or String(b.get("kind", "")) != "room" or b["state"] != "active":
			continue
		var cat: String = String(s.bdef(b["def"]).get("category", "logistics"))
		var isz: float = clampf(rpx * 1.3, 8.0, 16.0)
		var tex: Texture2D = Icons.tex(Icons.category(cat), 16)
		if tex != null:
			c.draw_texture_rect(tex, Rect2(q - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(0.04, 0.06, 0.1, 0.9))

## Version 4: vehicles (a cyan diamond each) and, for a reactor past normal, its blast radius.
func _draw_v4(c: Control, sz: Vector2) -> void:
	if hud.v4 == null:
		return
	var ppm: float = sz.x / maxf(1.0, _vr.size.x)
	for v in hud.v4.vehicles():
		if String(v["kind"]) == "satellite":
			continue
		var q: Vector2 = to_map(v["pos"], sz)
		var d := PackedVector2Array([q + Vector2(0, -4), q + Vector2(4, 0), q + Vector2(0, 4), q + Vector2(-4, 0)])
		c.draw_colored_polygon(d, Color(0, 0, 0, 0.6))
		c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -3), q + Vector2(3, 0), q + Vector2(0, 3), q + Vector2(-3, 0)]), P.CYAN)
	for r in hud.v4.reactors():
		if String(r["phase"]) == "normal":
			continue
		var col: Color = P.AMBER if String(r["phase"]) == "warning" else P.RED
		c.draw_arc(to_map(r["pos"], sz), maxf(4.0, float(r["blast_r"]) * ppm), 0.0, TAU, 32, col, 1.5, true)

## Radiation zones (reactor breach) and toxic zones (chemical leak), SIM reactors.zones().
func _draw_zones(c: Control, sz: Vector2) -> void:
	if hud.v4 == null:
		return
	var ppm: float = sz.x / maxf(1.0, _vr.size.x)
	for z in hud.v4.zones():
		var q: Vector2 = to_map(Vector2(float(z["x"]), float(z["y"])), sz)
		var r: float = maxf(3.0, float(z["r"]) * ppm)
		var col: Color = P.RED if String(z["kind"]) == "rad" else P.GREEN
		c.draw_circle(q, r, P.with_alpha(col, 0.18))
		c.draw_arc(q, r, 0.0, TAU, 28, P.with_alpha(col, 0.9), 1.5, true)

## Vehicle range overlay: a ring round each vehicle, half the range it has left (there and back).
func _draw_range(c: Control, sz: Vector2) -> void:
	var ppm: float = sz.x / maxf(1.0, _vr.size.x)
	for v in hud.v4.vehicles():
		var hop: bool = String(v["kind"]) == "hopper"
		var col: Color = P.GOLD if hop else P.CYAN
		var r: float = float(v.get("range_left_m", 0.0)) * 0.5 * ppm
		var q: Vector2 = to_map(v["pos"], sz)
		if r < 2.0:
			continue
		c.draw_circle(q, r, P.with_alpha(col, 0.08))
		c.draw_arc(q, r, 0.0, TAU, 40, P.with_alpha(col, 0.85), 1.5, true)

## Exploration (SIM milestone 7): the found points of interest (an icon by kind; visited ones dim
## with a tick), the survey satellites (an orbit icon over the band it maps next) and their mapped
## bands (a cyan tick on the right edge of the map for each band).
func _draw_explore(c: Control, sz: Vector2) -> void:
	if hud.v4 == null or not hud.v4.live("explore"):
		return
	for p in hud.v4.pois():
		var q: Vector2 = to_map(p["pos"], sz)
		if q.x < -6.0 or q.y < -6.0 or q.x > sz.x + 6.0 or q.y > sz.y + 6.0:
			continue
		var col: Color = V4.POI_COLOR.get(String(p["kind"]), P.TEXT)
		var vis: bool = bool(p.get("visited", false))
		c.draw_circle(q, 6.0, Color(0, 0, 0, 0.65))
		var tex: Texture2D = Icons.tex(String(V4.POI_ICON.get(String(p["kind"]), "star")), 12)
		if tex != null:
			c.draw_texture_rect(tex, Rect2(q - Vector2(5, 5), Vector2(10, 10)), false, P.with_alpha(col, 0.45) if vis else col)
		if vis:
			c.draw_texture_rect(Icons.tex("check", 12), Rect2(q + Vector2(1, 1), Vector2(7, 7)), false, P.GREEN)
	var sats: Array = hud.v4.sats()
	if sats.is_empty():
		return
	var ws: float = float(hud.main.sim.world.size)
	var band_s: float = float(hud.main.sim.content.get("terrain_v4", {}).get("explore", {}).get("band_s", 60.0))
	for s in sats:
		var nb: int = maxi(1, int(s["bands"]))
		var bh: float = ws / float(nb)
		for b in s["mapped"]:
			var y0: float = to_map(Vector2(0, float(b) * bh), sz).y
			var y1: float = to_map(Vector2(0, float(b + 1) * bh), sz).y
			if y1 < 0.0 or y0 > sz.y:
				continue
			c.draw_rect(Rect2(Vector2(sz.x - 4.0, y0 + 0.5), Vector2(3.0, maxf(1.0, y1 - y0 - 1.0))), P.with_alpha(P.CYAN, 0.9), true)
			if hud.main.view.overlay == "explored":
				c.draw_rect(Rect2(Vector2(0, y0), Vector2(sz.x, y1 - y0)), P.with_alpha(P.CYAN, 0.35), false, 1.0)
		if int(s["bands_done"]) >= nb:
			continue
		# The satellite over the band it maps next; it crosses the map as the band fills.
		var yc: float = to_map(Vector2(0, (float(s["band"]) + 0.5) * bh), sz).y
		var prog: float = clampf(1.0 - float(s["next_s"]) / maxf(1.0, band_s), 0.0, 1.0)
		var q2 := Vector2(8.0 + prog * (sz.x - 20.0), clampf(yc, 8.0, sz.y - 8.0))
		var up: bool = bool(s.get("uplink", false))
		c.draw_circle(q2, 7.0, Color(0, 0, 0, 0.7))
		c.draw_texture_rect(Icons.tex("satellite", 14), Rect2(q2 - Vector2(6, 6), Vector2(12, 12)), false, P.CYAN if up else P.TEXT_3)
	var s0: Dictionary = sats[0]
	var font: Font = Fonts.get_font("mono")
	var txt: String = "%d/%d" % [int(s0["bands_done"]), int(s0["bands"])]
	c.draw_string(font, Vector2(sz.x - 55.0, 13.0), txt, HORIZONTAL_ALIGNMENT_RIGHT, 48.0, P.fs(11), Color(0, 0, 0, 0.8))
	c.draw_string(font, Vector2(sz.x - 56.0, 12.0), txt, HORIZONTAL_ALIGNMENT_RIGHT, 48.0, P.fs(11), P.CYAN)

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
