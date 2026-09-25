extends Button
const PG = preload("res://ui/poly_guard.gd")
## One building card of the build bar: thumbnail (assets/thumbs/<id>_<size>.png, then
## <id>.png, then the category icon), name, cost chips (red when the colony does not have
## them free), power and main output, and the S/M/L/XL size chips with per-size numbers.
## A lock covers a structure that research has not unlocked yet.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")
const Icons = preload("res://ui/theme/icons.gd")
const Fonts = preload("res://ui/theme/fonts.gd")
const Tip = preload("res://ui/widgets/tip.gd")
const Sfx = preload("res://ui/sfx.gd")

signal pick(def_id: String, size: int)

static var _thumbs := {}

## Glyph for structures without a thumbnail image.
const GLYPH := {
	"solar_array": "sun", "wind_turbine": "wind", "battery": "energy", "fusion_reactor": "radiation",
	"water_extractor": "water", "reservoir": "water_can", "oxygen_plant": "o2", "water_recycler": "rotate",
	"atmo_processor": "cat_life_support", "airlock": "door", "research_lab": "research", "mine": "ore",
	"refinery": "metal", "polymer_plant": "polymer", "workshop": "spare_parts", "glassworks": "glass",
	"electronics_fab": "electronics", "fabricator": "hull_plate", "regolith_harvester": "silicate",
	"fuel_refinery": "rocket_fuel", "deep_drill": "exotic", "comms_tower": "target", "landing_pad": "ship",
	"junction": "grid", "habitat": "cat_housing", "lounge": "cat_comfort", "cantina": "morale", "medical": "cat_medical",
	"bio_lab": "medicine", "storehouse": "inventory", "cold_storage": "crate", "greenhouse": "cat_food",
	"fungus_farm": "mushroom", "algae_bioreactor": "algae", "kitchen": "food",
}
var _has_thumb := false

var def_id := ""
var data
var size_sel := 1
var locked := false
var lock_text := ""
var _thumb: TextureRect
var _name: Label
var _costs: HBoxContainer
var _stat: HBoxContainer
var _chips: Array = []
var _cat := ""
var _col := P.CYAN
var _hover := false

func setup(d, id: String, size: int) -> void:
	data = d
	def_id = id
	size_sel = size
	var def: Dictionary = d.bdef(id)
	_cat = String(def.get("category", "logistics"))
	_col = P.cat(_cat)
	theme_type_variation = "CardButton"
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	custom_minimum_size = Vector2(122, 180)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = " "
	clip_contents = false
	var v: VBoxContainer = Kit.vbox(3)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -6
	add_child(v)
	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(110, 64)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_thumb)
	_name = Kit.label(String(def.get("name", id)), "BodyStrong", 12)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	_name.custom_minimum_size = Vector2(110, 30)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name)
	_costs = Kit.hbox(6, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(_costs)
	_stat = Kit.hbox(6, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(_stat)
	var chips: HBoxContainer = Kit.hbox(3, BoxContainer.ALIGNMENT_CENTER)
	v.add_child(chips)
	if d.has_sizes(id):
		for s in 4:
			var n: int = s
			var c: Button = Kit.button(d.SIZE_NAMES[s], func(): _chip(n), "", "ChipButton")
			c.custom_minimum_size = Vector2(24, 20)
			c.toggle_mode = true
			c.sound = "tick"
			chips.add_child(c)
			_chips.append(c)
	else:
		var one: Label = Kit.label("ONE SIZE", "SmallLabel", 10, P.TEXT_3)
		one.add_theme_font_override("font", Fonts.get_font("head"))
		chips.add_child(one)
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())
	pressed.connect(func(): pick.emit(def_id, size_sel))
	_set_thumb()

func _chip(n: int) -> void:
	if not bool(data.size_allowed(def_id, n).get("ok", false)):
		Sfx.play("error")
		return
	size_sel = n
	_set_thumb()
	refresh_numbers()
	pick.emit(def_id, n)

func _set_thumb() -> void:
	var t: Texture2D = thumb(def_id, size_sel)
	_has_thumb = t != null
	if t != null:
		_thumb.texture = t
		_thumb.modulate = Color.WHITE
	else:
		_thumb.texture = Icons.tex(String(GLYPH.get(def_id, Icons.category(_cat))), 40)
		_thumb.modulate = _col.lightened(0.25)
	queue_redraw()

static func thumb(id: String, size: int) -> Texture2D:
	var names := ["s", "m", "l", "xl"]
	var key := "%s:%d" % [id, size]
	if _thumbs.has(key):
		return _thumbs[key]
	var t: Texture2D = null
	for p in ["res://assets/thumbs/%s_%s.png" % [id, names[clampi(size, 0, 3)]], "res://assets/thumbs/%s.png" % id]:
		if ResourceLoader.exists(p):
			t = load(p) as Texture2D
			if t != null:
				break
	_thumbs[key] = t
	return t

## Lock state, affordability and the numbers of the selected size.
func refresh_state(totals: Dictionary) -> void:
	var u: Dictionary = data.building_unlocked(def_id)
	locked = not bool(u["ok"])
	lock_text = String(u.get("reason", ""))
	disabled = false
	modulate = Color(1, 1, 1, 0.55) if locked else Color.WHITE
	for s in _chips.size():
		var ok: bool = bool(data.size_allowed(def_id, s).get("ok", false))
		var c: Button = _chips[s]
		c.disabled = not ok
		c.set_pressed_no_signal(s == size_sel)
		c.tooltip_text = _size_tip(s, ok)
	_costs_update(totals)
	queue_redraw()

func refresh_numbers() -> void:
	_costs_update(data.totals())

func _costs_update(totals: Dictionary) -> void:
	var def: Dictionary = data.size_def(def_id, size_sel)
	Kit.clear(_costs)
	Kit.clear(_stat)
	var cost: Dictionary = def.get("cost", {})
	var n := 0
	for res in cost:
		if n >= 3:
			break
		var row: Dictionary = totals.get(res, {})
		var free: int = int(row.get("total", 0)) - int(row.get("reserved", 0)) - int(row.get("carried", 0))
		_costs.add_child(Kit.chip(Icons.item(String(res)), "%d" % int(cost[res]), data.item_color(String(res)), "", free >= int(cost[res]), 14))
		n += 1
	if cost.is_empty():
		_costs.add_child(Kit.label("free", "SmallLabel", 11, P.TEXT_3))
	var ks: Array = key_stat(data, def)
	if not ks.is_empty():
		_stat.add_child(Kit.chip(ks[0], ks[1], ks[2], "", true, 14))
	var pw: float = float(def.get("power", 0.0))
	if pw > 0.0:
		_stat.add_child(Kit.chip("power", "-" + Kit.fmt(pw), P.AMBER, "", true, 13))

## The main output of a structure: [icon, text, colour] (empty when it has none).
static func key_stat(d, def: Dictionary) -> Array:
	if def.has("gen_solar"):
		return ["sun", "+%s P" % Kit.fmt(float(def["gen_solar"])), P.GOLD]
	if def.has("gen_const"):
		return ["power", "+%s P" % Kit.fmt(float(def["gen_const"])), P.GOLD]
	if def.has("gen_wind"):
		return ["wind", "x%s wind" % Kit.fmt(float(def["gen_wind"])), P.GOLD]
	if def.has("energy_cap"):
		return ["energy", "%s E" % Kit.fmt(float(def["energy_cap"])), P.CATEGORY["utilities"]]
	if def.has("o2_out"):
		return ["o2", "%s/d" % Kit.fmt(float(def["o2_out"])), P.CATEGORY["life_support"]]
	if def.has("water_out"):
		return ["water", "%s/d" % Kit.fmt(float(def["water_out"])), Color("3AA0D8")]
	if def.has("water_cap"):
		return ["water", "%s" % Kit.fmt(float(def["water_cap"])), Color("3AA0D8")]
	if def.has("recycle_per_day"):
		return ["water", "%s/d" % Kit.fmt(float(def["recycle_per_day"])), Color("3AA0D8")]
	if def.has("beds") and String(def.get("id", "")) != "lander":
		return ["beds", "%d" % int(def["beds"]), P.CATEGORY["housing"]]
	if def.has("trays"):
		return ["cat_food", Kit.plural(int(def["trays"]), "tray"), P.CATEGORY["food"]]
	if def.has("algae_per_day"):
		return ["algae", "%s/d" % Kit.fmt(float(def["algae_per_day"])), P.CATEGORY["food"]]
	if def.has("silicate_per_day"):
		return ["silicate", "%s/d" % Kit.fmt(float(def["silicate_per_day"])), d.item_color("silicate")]
	if def.has("fuel_per_day"):
		return ["rocket_fuel", "%s/d" % Kit.fmt(float(def["fuel_per_day"])), d.item_color("rocket_fuel")]
	if def.has("exotic_per_day"):
		return ["exotic", "%s/d" % Kit.fmt(float(def["exotic_per_day"])), d.item_color("exotic")]
	if def.has("storage"):
		return ["inventory", "%d" % int(def["storage"]), P.CATEGORY["logistics"]]
	if def.has("recreation"):
		return ["morale", "%d" % int(def["recreation"]), P.CATEGORY["comfort"]]
	if def.has("treatment_beds"):
		return ["heart", "%d" % int(def["treatment_beds"]), P.CATEGORY["medical"]]
	if bool(def.get("research_lab", false)):
		return ["research", "RP", P.VIOLET]
	if bool(def.get("airlock", false)):
		return ["door", "2/10s", P.CATEGORY["life_support"]]
	if def.has("recipe"):
		var rec: Dictionary = d.recipes().get(String(def["recipe"]), {})
		for out in rec.get("outputs", {}):
			return [Icons.item(String(out)), d.item_name(String(out)).to_lower(), d.item_color(String(out))]
		if bool(rec.get("menu", false)):
			return ["food", "dishes", P.CATEGORY["food"]]
	return []

func _size_tip(s: int, ok: bool) -> String:
	var def: Dictionary = data.size_def(def_id, s)
	var lines: Array = ["Size %s" % data.SIZE_NAMES[s]]
	var body: Array = []
	body.append("Radius %s m." % Kit.fmt(float(def.get("radius", 0.0))))
	var ks: Array = key_stat(data, def)
	if not ks.is_empty():
		body.append("Output %s." % ks[1])
	if float(def.get("power", 0.0)) > 0.0:
		body.append("Uses %s P." % Kit.fmt(float(def["power"])))
	var parts: Array = []
	for res in def.get("cost", {}):
		parts.append("%d %s" % [int(def["cost"][res]), data.item_name(String(res)).to_lower()])
	body.append("Cost: %s." % (", ".join(parts) if not parts.is_empty() else "nothing"))
	if not ok:
		body.append(String(data.size_allowed(def_id, s).get("text", "Not available.")))
	return lines[0] + "\n" + " ".join(body)

func _make_custom_tooltip(_for_text: String) -> Object:
	var def: Dictionary = data.bdef(def_id)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size.x = 330
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = Icons.tex(Icons.category(_cat), 18)
	ic.modulate = _col
	ic.custom_minimum_size = Vector2(18, 18)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(ic)
	var t := Label.new()
	t.text = String(def.get("name", def_id)).to_upper()
	t.add_theme_font_override("font", Fonts.get_font("head"))
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", P.TEXT)
	h.add_child(t)
	v.add_child(h)
	var desc := Label.new()
	desc.text = String(def.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 330
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", P.TEXT_2)
	v.add_child(desc)
	if locked:
		var lk := Label.new()
		lk.text = "LOCKED. " + lock_text
		lk.add_theme_color_override("font_color", P.AMBER)
		lk.add_theme_font_size_override("font_size", 13)
		v.add_child(lk)
	var auto := Label.new()
	auto.text = "Works without staff." if bool(def.get("automatic", false)) else ("Needs a worker inside." if def.has("recipe") or bool(def.get("research_lab", false)) else "")
	auto.add_theme_font_size_override("font_size", 12)
	auto.add_theme_color_override("font_color", P.TEXT_2)
	if auto.text != "":
		v.add_child(auto)
	if data.has_sizes(def_id):
		var g := GridContainer.new()
		g.columns = 5
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 2)
		for head in ["", "S", "M", "L", "XL"]:
			var hl := Label.new()
			hl.text = head
			hl.add_theme_font_override("font", Fonts.get_font("head"))
			hl.add_theme_font_size_override("font_size", 11)
			hl.add_theme_color_override("font_color", P.CYAN)
			g.add_child(hl)
		var rows := [["Radius m", "radius"], ["Output", "output"], ["Power P", "power"], ["Steel", "metal"], ["Polymer", "polymer"]]
		for r in rows:
			var nl := Label.new()
			nl.text = String(r[0])
			nl.add_theme_font_size_override("font_size", 12)
			nl.add_theme_color_override("font_color", P.TEXT_2)
			g.add_child(nl)
			for s in 4:
				var vl := Label.new()
				vl.text = _cell(data.size_def(def_id, s), String(r[1]))
				vl.add_theme_font_override("font", Fonts.get_font("mono"))
				vl.add_theme_font_size_override("font_size", 12)
				vl.add_theme_color_override("font_color", P.TEXT if s == size_sel else P.TEXT_2)
				g.add_child(vl)
		v.add_child(g)
		var req := Label.new()
		var lt: Array = []
		for s in [2, 3]:
			var a: Dictionary = data.size_allowed(def_id, s)
			if not bool(a.get("ok", false)):
				lt.append("%s: %s" % [data.SIZE_NAMES[s], String(a.get("text", ""))])
		req.text = "  ".join(lt)
		req.add_theme_font_size_override("font_size", 12)
		req.add_theme_color_override("font_color", P.AMBER)
		if req.text != "":
			v.add_child(req)
	var keys := Label.new()
	keys.text = "Click to place. Z and X change the size, R turns it."
	keys.add_theme_font_size_override("font_size", 11)
	keys.add_theme_color_override("font_color", P.TEXT_3)
	v.add_child(keys)
	return v

func _cell(dd: Dictionary, key: String) -> String:
	match key:
		"radius":
			return Kit.fmt(float(dd.get("radius", 0.0)))
		"output":
			var ks: Array = key_stat(data, dd)
			return String(ks[1]) if not ks.is_empty() else "-"
		"power":
			return Kit.fmt(float(dd.get("power", 0.0))) if float(dd.get("power", 0.0)) > 0.0 else "-"
	return "%d" % int(dd.get("cost", {}).get(key, 0))

func _draw() -> void:
	# Category strip along the top, a plate behind a glyph, and the lock.
	draw_rect(Rect2(8, 2, size.x - 16, 2), P.with_alpha(_col, 0.9 if (_hover or button_pressed) else 0.5), true)
	if not _has_thumb and _thumb != null:
		var c: Vector2 = _thumb.position + (_thumb.get_parent() as Control).position + _thumb.size * 0.5
		var pts := PackedVector2Array()
		for i in 6:
			var a: float = TAU * float(i) / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * 31.0)
		if PG.ok(pts, "build_card.gd:354"):
			draw_colored_polygon(pts, Color(_col.r, _col.g, _col.b, 0.14))
		pts.append(pts[0])
		draw_polyline(pts, Color(_col.r, _col.g, _col.b, 0.5), 1.0, true)
	if locked:
		var c := Vector2(size.x - 18, 18)
		draw_circle(c, 11.0, Color(0.03, 0.05, 0.09, 0.95))
		draw_texture_rect(Icons.tex("lock", 14), Rect2(c - Vector2(7, 7), Vector2(14, 14)), false, P.AMBER)
