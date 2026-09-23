extends Control
## Title screen: the showcase colony at dusk behind the menu (presentation/main.gd loads
## it and orbits the camera). Logo, menu, the newest save, and the device profile.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Glass = preload("res://ui/widgets/glass.gd")
const Persistence = preload("res://sim/persistence.gd")
const Profile = preload("res://ui/profile.gd")

var hud
var host
var arg = null
var screen_name := "title"
var pauses := false
var closable := false
var _live: Label
var _t := 0.0
var _logo: Control

class Vignette extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var dark := Color(0.02, 0.03, 0.06, 0.88)
		var clear := Color(0.02, 0.03, 0.06, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.62, 0), Vector2(w * 0.62, h), Vector2(0, h)]),
			PackedColorArray([dark, clear, clear, dark]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.72), Vector2(w, h * 0.72), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.02, 0.03, 0.06, 0.6), Color(0.02, 0.03, 0.06, 0.6)]))
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.16), Vector2(0, h * 0.16)]),
			PackedColorArray([Color(0.02, 0.03, 0.06, 0.45), Color(0.02, 0.03, 0.06, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))

class Logo extends Control:
	var t := 0.0
	func _ready() -> void:
		custom_minimum_size = Vector2(620, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var big: Font = Fonts.get_font("display")
		var mono: Font = Fonts.get_font("mono_b")
		var head: Font = Fonts.get_font("head_wide")
		# Emblem: a hexagon ring with a planet arc and an orbit.
		var c := Vector2(58, 78)
		var pts := PackedVector2Array()
		for i in 7:
			var a: float = PI / 6.0 + TAU * float(i) / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * 50.0)
		draw_polyline(pts, P.CYAN, 2.5, true)
		var pts2 := PackedVector2Array()
		for i in 7:
			var a: float = PI / 6.0 + TAU * float(i) / 6.0
			pts2.append(c + Vector2(cos(a), sin(a)) * 42.0)
		draw_polyline(pts2, P.with_alpha(P.CYAN, 0.35), 1.0, true)
		draw_circle(c, 24.0, Color("E07A3A"))
		draw_circle(c + Vector2(-6, -6), 18.0, Color("F0A060"))
		draw_arc(c, 34.0, -0.4 + t * 0.3, 2.2 + t * 0.3, 32, P.CYAN, 2.0, true)
		draw_circle(c + Vector2(cos(2.2 + t * 0.3), sin(2.2 + t * 0.3)) * 34.0, 4.0, Color.WHITE)
		# Words
		draw_string(head, Vector2(128, 40), "COLONY MANAGEMENT  ·  FRONTIER SECTOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, P.with_alpha(P.CYAN, 0.9))
		draw_string(big, Vector2(124, 104), "FRONTIER", HORIZONTAL_ALIGNMENT_LEFT, -1, 64, P.TEXT)
		draw_string(big, Vector2(126, 160), "HABITAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, P.CYAN)
		var w: float = big.get_string_size("HABITAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x
		var bx: float = 126.0 + w + 16.0
		draw_rect(Rect2(bx, 122, 56, 30), P.with_alpha(P.GOLD, 0.14), true)
		draw_rect(Rect2(bx, 122, 56, 30), P.GOLD, false, 1.5)
		draw_string(mono, Vector2(bx, 144), "2.0", HORIZONTAL_ALIGNMENT_CENTER, 56, 18, P.GOLD)
		draw_line(Vector2(128, 178), Vector2(560, 178), P.with_alpha(P.CYAN, 0.5), 1.0)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vg = Vignette.new()
	vg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vg)
	var col: VBoxContainer = Kit.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = 90
	col.offset_top = 90
	col.offset_bottom = -60
	col.custom_minimum_size.x = 640
	add_child(col)
	_logo = Logo.new()
	col.add_child(_logo)
	var tag: Label = Kit.label("Plan the base. Keep the air, water, food and power flowing. Repair the Meridian.", "", 17, P.TEXT_2)
	tag.add_theme_constant_override("outline_size", 6)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	col.add_child(tag)
	col.add_child(Kit.gap(0, 34))
	var menu: VBoxContainer = Kit.vbox(8)
	menu.custom_minimum_size.x = 380
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(menu)
	var latest: String = hud.main.latest_slot()
	var cont_sub := "No saved colony yet: starts a new one."
	if latest != "":
		for s in Persistence.list_slots():
			if String(s["slot"]) == latest:
				cont_sub = "%s  ·  %s" % [latest.replace("_", " ").capitalize(), Time.get_datetime_string_from_unix_time(int(s["modified"]), true)]
	menu.add_child(_item("Continue", cont_sub, "play", func(): hud.main.continue_game(), true))
	menu.add_child(_item("New colony", "Planet, difficulty and seed.", "new_game", func(): hud.open_screen("newcolony"), false))
	menu.add_child(_item("Load", "Saves on this device, or a save file.", "load", func(): hud.open_screen("saveload"), false))
	menu.add_child(_item("Awards", "%d of %d medals earned on this device." % [Profile.award_count(), hud.data.awards_def().size()], "medal", func(): hud.open_screen("awards"), false))
	menu.add_child(_item("Settings", "Graphics, interface, camera, sound.", "settings", func(): hud.open_screen("settings"), false))
	menu.add_child(_item("How to play", "The rules on one page.", "info", func(): hud.open_screen("help"), false))
	col.add_child(Kit.spacer())
	_live = Kit.label("", "SmallLabel", 12, P.TEXT_3)
	col.add_child(_live)
	var foot: Label = Kit.label("Frontier Habitat 2.0  ·  Godot 4.4  ·  all models, code and text original", "SmallLabel", 11, P.TEXT_3)
	col.add_child(foot)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)

func _item(text: String, sub: String, icon: String, cb: Callable, primary: bool) -> Button:
	var b: Button = Kit.button("", cb, "", "PrimaryButton" if primary else "CardButton")
	b.custom_minimum_size = Vector2(380, 58)
	b.toggle_mode = false
	var h: HBoxContainer = Kit.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.offset_right = -12
	b.add_child(h)
	h.add_child(Kit.icon(icon, 22, P.TEXT_DARK if primary else P.CYAN))
	var v: VBoxContainer = Kit.vbox(-2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	v.add_child(Kit.label(text.to_upper(), "TitleLabel", 17, P.TEXT_DARK if primary else P.TEXT))
	v.add_child(Kit.label(sub, "SmallLabel", 12, Color(0.02, 0.1, 0.16, 0.85) if primary else P.TEXT_2))
	return b

func _process(delta: float) -> void:
	_t += delta
	if _logo != null:
		_logo.set("t", _t)
		_logo.queue_redraw()

func refresh() -> void:
	var s = hud.main.sim
	if s == null:
		return
	_live.text = "Behind this menu: a colony on day %d, %s, %s." % [s.util.day_number(), Kit.plural(s.alive_count(), "colonist"), Kit.plural(s.state["buildings"].size(), "structure")]

func on_close() -> void:
	pass
