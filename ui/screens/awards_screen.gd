extends "res://ui/screens/screen.gd"
## Awards gallery: every medal by tier, earned or locked. "This colony" shows the medals of
## the running game with the day each was earned and the progress of the others;
## "This device" shows every medal ever earned here (user://profile.json).

const Profile = preload("res://ui/profile.gd")
const Medal = preload("res://ui/widgets/medal.gd")

const TIER_ORDER := ["bronze", "silver", "gold", "platinum"]

var _list := {}

func _init() -> void:
	icon = "medal"
	accent = P.GOLD
	title = "Awards"
	tabs = [["colony", "This colony", "home"], ["device", "This device", "trophy"]]

func _ready() -> void:
	if hud.main.on_title:
		tab = "device"
	super._ready()
	if hud.watchers.has_method("clear_unseen"):
		hud.watchers.clear_unseen()

func _award_list() -> Array:
	var d = hud.data
	if d.has_helper("awards", "list") and not hud.main.on_title:
		return hud.main.sim.awards.list()
	var out: Array = []
	var st: Dictionary = d.awards_state()
	for id in d.awards_def():
		var a: Dictionary = d.awards_def()[id]
		out.append({"id": id, "name": a.get("name", id), "tier": a.get("tier", "bronze"), "desc": a.get("desc", ""),
			"earned": int(st.get(id, -1)) if not hud.main.on_title else -1, "value": 0.0, "target": 0.0})
	return out

func build_tab(id: String, box: VBoxContainer) -> void:
	var d = hud.data
	var list: Array = _award_list()
	var tiers: Dictionary = d.award_tiers()
	# Summary
	var earned := 0
	var points := 0
	var total_points := 0
	for a in list:
		var tp: int = int(tiers.get(String(a["tier"]), {}).get("points", 0))
		total_points += tp
		var got: bool = int(a["earned"]) >= 0 if id == "colony" else not Profile.award(String(a["id"])).is_empty()
		if got:
			earned += 1
			points += tp
	set_subtitle(("%d of %d medals in this colony  ·  %d of %d points" if id == "colony" else "%d of %d medals earned on this device  ·  %d of %d points") % [earned, list.size(), points, total_points])
	var body: VBoxContainer = Kit.vbox(14)
	box.add_child(Kit.scroll(body))
	for tier in TIER_ORDER:
		var row: Array = []
		for a in list:
			if String(a["tier"]) == tier:
				row.append(a)
		if row.is_empty():
			continue
		var col: Color = P.TIER.get(tier, P.GOLD)
		var h: HBoxContainer = Kit.hbox(8)
		h.add_child(Kit.head(String(tiers.get(tier, {}).get("name", tier.capitalize())), col, 13, "head_wide"))
		h.add_child(Kit.label("%d points each" % int(tiers.get(tier, {}).get("points", 0)), "SmallLabel", 11, P.TEXT_3))
		body.add_child(h)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 10)
		body.add_child(flow)
		for a in row:
			flow.add_child(_tile(a, id, col))

func _progress_text(kind: String, v: float, t: float) -> String:
	match kind:
		"ship_stage":
			return "Stage %d of %d" % [int(v), int(t)]
		"max_level":
			return "Highest level %d of %d" % [int(v), int(t)]
		"size_built":
			var names: Array = hud.data.SIZE_NAMES
			return "Largest size %s, needs %s" % [names[clampi(int(v), 0, 3)], names[clampi(int(t), 0, 3)]]
		"power_gen":
			return "%s of %s P" % [Kit.fmt(minf(v, t)), Kit.fmt(t)]
		"no_death_days":
			return "%s of %s days" % [Kit.fmt(minf(v, t)), Kit.fmt(t)]
	if t <= 1.0:
		return "Not yet"
	return "%s of %s" % [Kit.fmt(minf(v, t)), Kit.fmt(t)]

func _tile(a: Dictionary, mode: String, col: Color) -> Control:
	var d = hud.data
	var prof: Dictionary = Profile.award(String(a["id"]))
	var got: bool = int(a["earned"]) >= 0 if mode == "colony" else not prof.is_empty()
	var p: PanelContainer = Kit.panel("CardPanel", false)
	p.custom_minimum_size = Vector2(172, 206)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var v: VBoxContainer = Kit.vbox(3)
	p.add_child(v)
	var m = Medal.new()
	m.tier = String(a["tier"])
	m.earned = got
	m.glyph = Medal.glyph_for(String(a["id"]))
	m.custom_minimum_size = Vector2(150, 92)
	v.add_child(m)
	var n: Label = Kit.label(String(a["name"]).to_upper(), "TitleLabel", 13, P.TEXT if got else P.TEXT_3)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var ds: Label = Kit.wrap(String(a.get("desc", "")), 11, P.TEXT_2 if got else P.TEXT_3)
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ds.custom_minimum_size.x = 150
	v.add_child(ds)
	var status := ""
	var sc: Color = P.TEXT_3
	if mode == "colony":
		if got:
			status = "Earned %s" % d.tick_to_day(int(a["earned"]))
			sc = col
		elif float(a.get("target", 0.0)) > 0.0:
			var tv: float = float(a["target"])
			var vv: float = float(a.get("value", 0.0))
			status = _progress_text(String(d.awards_def().get(String(a["id"]), {}).get("kind", "")), vv, tv)
			var bar = Kit.bar(clampf(vv / tv, 0.0, 1.0), P.with_alpha(col, 0.8), 4.0)
			v.add_child(bar)
		else:
			status = "Not yet"
	else:
		if got:
			var when: String = Time.get_date_string_from_unix_time(int(prof.get("first", 0)))
			status = "First earned %s" % when
			if int(prof.get("count", 1)) > 1:
				status += ", %d times" % int(prof["count"])
			sc = col
		else:
			status = "Not earned on this device"
	var sl: Label = Kit.label(status, "SmallLabel", 11, sc)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	p.tooltip_text = "%s\n%s %s." % [a["name"], a.get("desc", ""), status]
	return p
