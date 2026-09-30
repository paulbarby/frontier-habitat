extends "res://ui/screens/screen.gd"
## Crew (V5_DESIGN §5, §7, §10). Tabs:
##   Org chart  the base commander at the top; one column per department with its captain, first
##              hands and crew. Drag a person onto a rank slot to appoint them (a confirm first). SIM's
##              suggested person for a slot is marked; the slot shows its entitlement (housing).
##   Housing    every home (dorm beds, residence units, apartments, penthouses) and who lives there;
##              quality against what the person's rank expects. Drag a person onto a unit to move them.
##   Academy    the academies (seats, teachers) and an enrolment form: a person, a skill, a step.
## One base at a time (the base picker in the header; the top bar filter picks the first one).
## Orders go to SIM through ui/v5_data.gd command(): appoint, set_home, enrol.
## Data: sim.people.list() / rank / home / skills, sim.floors.units(b), content/people.json.

const V5 = preload("res://ui/v5_data.gd")
const Fonts = preload("res://ui/theme/fonts.gd")

const DEPTS := ["industry", "science", "food", "maintenance", "security"]
const RANK_ORDER := {"commander": 0, "captain": 1, "first_hand": 2, "specialist": 3, "crew": 4, "trainee": 5}

var base_id := -2
var last_result: Dictionary = {}      # tests
var slots: Array = []                 # [{rank, department, holder}] of the org chart shown (tests)

## A draggable person card.
class PersonChip extends Button:
	var agent_id := -1
	var scr
	func _get_drag_data(_at: Vector2):
		var prev := Label.new()
		prev.text = text
		prev.add_theme_color_override("font_color", Color("3EE0FF"))
		set_drag_preview(prev)
		return {"agent": agent_id}

## Standard skill abbreviations (critic round 36); the header tooltip has the full name.
const SKILL_ABBR := {"engineering": "Eng", "mining": "Min", "fabrication": "Fab", "farming": "Frm", "cooking": "Cook", "medicine": "Med",
	"science": "Sci", "piloting": "Pil", "security": "Sec", "leadership": "Lead", "social": "Soc"}
const LEVEL_COL := [Color("8A97A6"), Color("B7C6D6"), Color("3EE0FF"), Color("5EE07A"), Color("FFD166")]

## A mood face (critic round 30, fix 6): very unhappy (red) .. happy (gold), from satisfaction.
static func mood_face(sv: float) -> TextureRect:
	var m: int = V5.mood(sv)
	var t: TextureRect = Kit.icon(V5.MOOD_ICON[m], 18, V5.MOOD_COL[m])
	t.tooltip_text = "Mood\n%s (satisfaction %d)." % [V5.MOOD_NAME[m], int(sv)]
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.name = "Mood"
	return t

## A slot that takes a dropped person: an org chart rank or a housing unit.
class DropSlot extends PanelContainer:
	var scr
	var spec := {}
	func _can_drop_data(_at: Vector2, data) -> bool:
		return typeof(data) == TYPE_DICTIONARY and (data as Dictionary).has("agent")
	func _drop_data(_at: Vector2, data) -> void:
		scr.dropped(int(data["agent"]), spec)

func _init() -> void:
	icon = "colonists"
	title = "Crew"
	subtitle = "Ranks, homes and training. Drag a person onto a slot."
	accent = P.CYAN
	tabs = [["org", "Org chart", "people"], ["housing", "Housing", "home"], ["academy", "Academy", "research"]]

func header_extra(row: HBoxContainer) -> void:
	var s = hud.main.sim
	var ids: Array = s.bases.ids() if s.get("bases") != null and s.bases.count() > 0 else []
	if base_id == -2:
		base_id = hud.base_filter if hud.base_filter >= 0 else (int(ids[0]) if not ids.is_empty() else -1)
	if ids.size() <= 1:
		return
	var ob := OptionButton.new()
	ob.tooltip_text = "Base\nThe crew of one base."
	for i in ids.size():
		ob.add_item(String(s.bases.name_of(int(ids[i]))), i)
		if int(ids[i]) == base_id:
			ob.select(i)
	ob.item_selected.connect(func(i: int):
		base_id = int(ids[i])
		_build_tab_content())
	row.add_child(ob)

func build_tab(id: String, box: VBoxContainer) -> void:
	if not hud.v5.live("people"):
		box.add_child(Kit.wrap("The crew is not available in this game.", 15, P.TEXT_2))
		return
	match id:
		"housing": _housing(box)
		"academy": _academy(box)
		_: _org(box)

func _rows() -> Array:
	var out: Array = []
	for r in hud.v5.people():
		if String(r["kind"]) != "colonist":
			continue
		if base_id >= 0 and int(r["base"]) != base_id and hud.main.sim.bases.count() > 1:
			continue
		out.append(r)
	return out

func _chip(r: Dictionary) -> PersonChip:
	var c := PersonChip.new()
	c.scr = self
	c.agent_id = int(r["id"])
	c.text = String(r["name"])
	c.theme_type_variation = "ChipButton"
	c.alignment = HORIZONTAL_ALIGNMENT_LEFT
	c.icon = Icons.tex(Icons.role(String(r["role"])), 16)
	c.add_theme_color_override("icon_normal_color", P.ROLE.get(r["role"], P.CYAN))
	var sv: float = float(r["satisfaction"])
	c.tooltip_text = "%s\n%s, %s. Satisfaction %d. Drag onto a slot to appoint or move. Double click: personnel file." % [r["name"], r["title"], String(r["role"]).capitalize(), int(sv)]
	c.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var id: int = int(r["id"])
	c.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.double_click:
			hud.open_person(id))
	c.custom_minimum_size = Vector2(0, 30)
	c.add_theme_font_override("font", Fonts.get_font("body"))
	c.add_theme_font_size_override("font_size", P.fs(13))
	c.clip_text = true
	c.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return c

func _slot(spec: Dictionary, title_text: String, col: Color, sub: String) -> DropSlot:
	var s := DropSlot.new()
	s.scr = self
	s.spec = spec
	var st := StyleBoxFlat.new()
	st.bg_color = Color(col.r, col.g, col.b, 0.08)
	st.border_color = Color(col.r, col.g, col.b, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 5
	st.content_margin_bottom = 6
	s.add_theme_stylebox_override("panel", st)
	var v: VBoxContainer = Kit.vbox(3)
	s.add_child(v)
	var h: HBoxContainer = Kit.hbox(6)
	v.add_child(h)
	var t: Label = Kit.head(title_text, col, 11)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if sub != "":
		h.add_child(Kit.label(sub, "SmallLabel", 11, P.TEXT_3))
	s.set_meta("list", v)
	return s

# ---------------------------------------------------------------- org chart
func _org(box: VBoxContainer) -> void:
	var rows: Array = _rows()
	slots = []
	var cfg: Dictionary = hud.main.sim.content.get("people", {})
	var ranks_cfg: Dictionary = cfg.get("ranks", {})
	var deps: Dictionary = cfg.get("departments", {})
	box.add_child(Kit.wrap("Drag a person onto a rank to appoint them. The simulation's choice for each rank has a star. Ranks expect a home: captains and the commander an executive unit; a rank without it makes the person unhappy, and entitlements others see as unfair raise unrest.", 13, P.TEXT_2, 1100.0))
	# Commander
	var cmd: Array = rows.filter(func(r): return String(r["rank"]) == "commander")
	var top: HBoxContainer = Kit.hbox(0)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(top)
	var cs: DropSlot = _slot({"rank": "commander", "department": "command"}, "BASE COMMANDER", P.GOLD, "expects: %s" % String(ranks_cfg.get("commander", {}).get("entitlement", "executive")))
	cs.custom_minimum_size.x = 320
	top.add_child(cs)
	for r in cmd:
		(cs.get_meta("list") as VBoxContainer).add_child(_holder(r, true))
	slots.append({"rank": "commander", "department": "command", "holder": int(cmd[0]["id"]) if not cmd.is_empty() else -1})
	# Departments
	var cols: HBoxContainer = Kit.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(cols)
	for dep in DEPTS:
		var dd: Dictionary = deps.get(dep, {"name": dep.capitalize()})
		var members: Array = rows.filter(func(r): return String(r["department"]) == dep)
		members.sort_custom(func(x, y): return int(RANK_ORDER.get(String(x["rank"]), 9)) < int(RANK_ORDER.get(String(y["rank"]), 9)))
		var col: VBoxContainer = Kit.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.custom_minimum_size.x = 200
		cols.add_child(col)
		var hd: HBoxContainer = Kit.hbox(6)
		hd.add_child(Kit.head(String(dd.get("name", dep)).to_upper(), P.CYAN, 13, "head_wide"))
		hd.add_child(Kit.label("%d" % members.size(), "SmallLabel", 12, P.TEXT_3))
		col.add_child(hd)
		var cap: DropSlot = _slot({"rank": "captain", "department": dep}, "CAPTAIN", P.GOLD, "expects: executive")
		col.add_child(cap)
		var caps: Array = members.filter(func(r): return String(r["rank"]) == "captain")
		for r in caps:
			(cap.get_meta("list") as VBoxContainer).add_child(_holder(r, true))
		if caps.is_empty():
			(cap.get_meta("list") as VBoxContainer).add_child(Kit.label("Empty: drag a person here.", "SmallLabel", 12, P.TEXT_3))
		slots.append({"rank": "captain", "department": dep, "holder": int(caps[0]["id"]) if not caps.is_empty() else -1})
		var fh: DropSlot = _slot({"rank": "first_hand", "department": dep}, "FIRST HANDS", P.VIOLET, "up to %d" % int(ranks_cfg.get("first_hand", {}).get("per_department", 2)))
		col.add_child(fh)
		var fhs: Array = members.filter(func(r): return String(r["rank"]) == "first_hand")
		for r in fhs:
			(fh.get_meta("list") as VBoxContainer).add_child(_holder(r, true))
		if fhs.is_empty():
			(fh.get_meta("list") as VBoxContainer).add_child(Kit.label("None.", "SmallLabel", 12, P.TEXT_3))
		slots.append({"rank": "first_hand", "department": dep, "holder": int(fhs[0]["id"]) if not fhs.is_empty() else -1})
		var crew: DropSlot = _slot({"rank": "crew", "department": dep}, "CREW", P.TEXT_2, "")
		crew.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(crew)
		var rest: Array = members.filter(func(r): return not (String(r["rank"]) in ["captain", "first_hand", "commander"]))
		for r in rest:
			(crew.get_meta("list") as VBoxContainer).add_child(_holder(r, false))
		if rest.is_empty():
			(crew.get_meta("list") as VBoxContainer).add_child(Kit.label("Nobody.", "SmallLabel", 12, P.TEXT_3))

## A holder line: the person chip, their rank word and skill level; a star when SIM chose them.
func _holder(r: Dictionary, starred: bool) -> Control:
	var h: HBoxContainer = Kit.hbox(4)
	if starred:
		var st: TextureRect = Kit.icon("star", 12, P.GOLD)
		st.tooltip_text = "The simulation's choice\nThe best skill and leadership for this rank."
		st.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(st)
	h.add_child(mood_face(float(r["satisfaction"])))
	var c: PersonChip = _chip(r)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	if not starred:
		h.add_child(Kit.label(String(r["rank"]).capitalize(), "SmallLabel", 11, P.TEXT_3))
	# Critic round 36: the columns carry each person's two best skills (who is good at what).
	var v: VBoxContainer = Kit.vbox(1)
	v.add_child(h)
	var a: Dictionary = hud.v5.agent(int(r["id"]))
	if not a.is_empty():
		var s = hud.main.sim
		var sk: Dictionary = s.people.skills(a)
		var names: Array = sk.keys()
		names.sort_custom(func(x, y): return float(sk[x]) > float(sk[y]))
		var parts: Array = []
		for n in names.slice(0, 2):
			parts.append("%s L%d" % [String(n).capitalize(), int(s.people.level_of(float(sk[n])))])
		var sl: Label = Kit.label("    " + "  ·  ".join(parts), "SmallLabel", 12, P.TEXT_2)
		sl.name = "TopSkills"
		v.add_child(sl)
	return v

## A person dropped on a slot: the confirm, then the order.
func dropped(agent: int, spec: Dictionary) -> void:
	var nm: String = hud.v5.agent_name(agent)
	if spec.has("unit"):
		var what: String = "Move %s to %s, unit %d?" % [nm, String(spec["building_name"]), int(spec["unit"]) + 1]
		hud.confirm(what, ["Partners share a unit. A family needs a family unit.", "A home below what the rank expects makes the person unhappy."], func():
			last_result = hud.v5.command("set_home", {"agent": agent, "building": int(spec["building"]), "unit": int(spec["unit"])})
			hud.toast("Move: " + String(last_result["text"]), "info" if bool(last_result["ok"]) else "warn", "home")
			_build_tab_content(), "Move")
		return
	var rk: String = String(spec["rank"])
	var dep: String = String(spec["department"])
	var title_s: String = {"commander": "Base Commander", "captain": "Captain of %s" % dep.capitalize(), "first_hand": "First Hand of %s" % dep.capitalize(), "crew": "Crew of %s" % dep.capitalize()}.get(rk, rk)
	var lines: Array = ["%s becomes %s." % [nm, title_s]]
	if rk in ["commander", "captain"]:
		lines.append("The rank expects an executive home. Without it, %s is unhappy." % nm.get_slice(" ", 0))
		lines.append("The person who held the rank steps down: unhappy, and may become a rival.")
	elif rk == "crew":
		lines.append("A demotion if %s had a rank: satisfaction and attitude fall." % nm.get_slice(" ", 0))
	hud.confirm("Appoint %s?" % nm, lines, func():
		last_result = hud.v5.command("appoint", {"agent": agent, "rank": rk, "department": dep, "base": base_id})
		hud.toast("Appoint: " + String(last_result["text"]), "info" if bool(last_result["ok"]) else "warn", "people")
		_build_tab_content(), "Appoint")

# ---------------------------------------------------------------- housing
const QUAL := {"none": 0, "dorm": 1, "family": 2, "executive": 3, "penthouse": 4}

func _housing(box: VBoxContainer) -> void:
	var s = hud.main.sim
	var rows: Array = _rows()
	var by_home := {}
	var homeless: Array = []
	for r in rows:
		var h: Dictionary = r["home"]
		if int(h.get("building", -1)) < 0:
			homeless.append(r)
			continue
		var k: String = "%d:%d" % [int(h["building"]), int(h.get("unit", -1))]
		if not by_home.has(k):
			by_home[k] = []
		by_home[k].append(r)
	var ent: Dictionary = s.content.get("people", {}).get("ranks", {})
	box.add_child(Kit.wrap("Every home and who lives there. Quality: dorm 1, family unit 2, executive unit 3, penthouse 4. Red: below what the rank expects. Drag a person onto a unit to move them.", 13, P.TEXT_2, 1100.0))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var bids: Array = s.state["buildings"].keys()
	bids.sort()
	var n := 0
	for bid in bids:
		var b: Dictionary = s.state["buildings"][bid]
		if String(b.get("state", "")) != "active":
			continue
		if base_id >= 0 and s.bases.count() > 1 and int(s.bases.base_of(int(bid))) != base_id:
			continue
		var units: Array = s.floors.units(b) if s.get("floors") != null else []
		var beds: int = int(s.bd(b).get("beds", 0))
		if units.is_empty() and beds <= 0:
			continue
		var list: Array = units if not units.is_empty() else [{"index": -1, "floor": 0, "quality": "dorm", "beds": beds}]
		for u in list:
			var k: String = "%d:%d" % [int(bid), int(u["index"])]
			var who: Array = by_home.get(k, [])
			if u["index"] == -1:
				who = []
				for kk in by_home:
					if String(kk).begins_with("%d:" % int(bid)):
						who.append_array(by_home[kk])
			var q: int = int(QUAL.get(String(u["quality"]), 1))
			var title_s: String = String(b["name"]) + ((" · unit %d" % (int(u["index"]) + 1)) if int(u["index"]) >= 0 else " · dorm")
			var sl: DropSlot = _slot({"unit": int(u["index"]), "building": int(bid), "building_name": String(b["name"])}, title_s.to_upper(), P.CYAN, "%s · %d/%d beds" % [String(u["quality"]).capitalize(), who.size(), int(u["beds"])])
			sl.custom_minimum_size.x = 260
			var lv: VBoxContainer = sl.get_meta("list")
			if int(u.get("floor", 0)) > 0:
				lv.add_child(Kit.label("Floor %d" % (int(u["floor"]) + 1), "SmallLabel", 11, P.TEXT_3))
			for r in who:
				var want: String = String(ent.get(String(r["rank"]), {}).get("entitlement", "dorm"))
				var low: bool = int(QUAL.get(want, 1)) > q
				var hh: HBoxContainer = Kit.hbox(4)
				hh.add_child(mood_face(float(r["satisfaction"])))
				var c: PersonChip = _chip(r)
				c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hh.add_child(c)
				if low:
					var w: Label = Kit.label("wants %s" % want, "SmallLabel", 11, P.RED)
					w.tooltip_text = "Below the rank\n%s expects a %s home. This lowers their satisfaction." % [r["title"], want]
					w.mouse_filter = Control.MOUSE_FILTER_PASS
					hh.add_child(w)
				lv.add_child(hh)
			if who.is_empty():
				lv.add_child(Kit.label("Free.", "SmallLabel", 12, P.GREEN))
			grid.add_child(sl)
			n += 1
	if not homeless.is_empty():
		var hs: DropSlot = _slot({"unit": -1, "building": -1, "building_name": "no home"}, "NO HOME", P.RED, "%d people" % homeless.size())
		for r in homeless:
			(hs.get_meta("list") as VBoxContainer).add_child(_chip(r))
		grid.add_child(hs)
	if n == 0:
		box.add_child(Kit.wrap("No homes yet. Build a habitat, a residence tube or an apartment block.", 14, P.TEXT_2))
		return
	_housing_summary(box, rows, ent)

## Beds by home quality, and who waits for a better home (critic round 30, fix 6: use the height).
func _housing_summary(box: VBoxContainer, rows: Array, ent: Dictionary) -> void:
	var s = hud.main.sim
	box.add_child(Kit.sep())
	var row: HBoxContainer = Kit.hbox(24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	var left: VBoxContainer = Kit.vbox(4)
	left.custom_minimum_size.x = 420
	row.add_child(left)
	left.add_child(Kit.head("Beds by home quality", P.CYAN, 12))
	var tot := {}
	for bid in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][bid]
		if String(b.get("state", "")) != "active":
			continue
		if base_id >= 0 and s.bases.count() > 1 and int(s.bases.base_of(int(bid))) != base_id:
			continue
		var units: Array = s.floors.units(b) if s.get("floors") != null else []
		if units.is_empty() and int(s.bd(b).get("beds", 0)) > 0:
			units = [{"quality": "dorm", "beds": int(s.bd(b).get("beds", 0))}]
		for u in units:
			var q: String = String(u["quality"])
			tot[q] = int(tot.get(q, 0)) + int(u["beds"])
	var used := {}
	for r in rows:
		var q2: String = String(r["home"].get("kind", "none"))
		used[q2] = int(used.get(q2, 0)) + 1
	var g: GridContainer = Kit.grid(4, 18, 4)
	left.add_child(g)
	for hdr in ["Quality", "Beds", "Used", "Free"]:
		g.add_child(Kit.dim(hdr, 12))
	for q in ["dorm", "family", "executive", "penthouse"]:
		if not tot.has(q):
			continue
		g.add_child(Kit.label(q.capitalize(), "", 13, P.TEXT))
		g.add_child(Kit.num("%d" % int(tot[q]), 13, P.TEXT))
		g.add_child(Kit.num("%d" % int(used.get(q, 0)), 13, P.TEXT))
		var fr: int = int(tot[q]) - int(used.get(q, 0))
		g.add_child(Kit.num("%d" % fr, 13, P.GREEN if fr > 0 else P.RED))
	var right: VBoxContainer = Kit.vbox(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var wait: Array = []
	for r in rows:
		var want: String = String(ent.get(String(r["rank"]), {}).get("entitlement", "dorm"))
		if int(QUAL.get(want, 1)) > int(QUAL.get(String(r["home"].get("kind", "none")), 0)):
			wait.append([r, want])
	right.add_child(Kit.head("Waiting for a better home: %d" % wait.size(), P.RED if not wait.is_empty() else P.GREEN, 12))
	if wait.is_empty():
		right.add_child(Kit.label("Everyone has the home their rank expects.", "", 13, P.TEXT_2))
	var wf := HFlowContainer.new()
	wf.add_theme_constant_override("h_separation", 12)
	wf.add_theme_constant_override("v_separation", 4)
	right.add_child(wf)
	for w in wait:
		var hh: HBoxContainer = Kit.hbox(4)
		hh.add_child(mood_face(float(w[0]["satisfaction"])))
		hh.add_child(Kit.label("%s (%s, wants %s)" % [w[0]["name"], w[0]["title"], w[1]], "", 13, P.TEXT))
		wf.add_child(hh)

# ---------------------------------------------------------------- academy
func _academy(box: VBoxContainer) -> void:
	var s = hud.main.sim
	var acs: Array = []
	for bid in s.state["buildings"]:
		var b: Dictionary = s.state["buildings"][bid]
		if String(b["def"]) == "academy":
			acs.append(b)
	box.add_child(Kit.wrap("A course teaches one skill one level up. Students leave their work for the lessons. A teacher needs skill 60 or more in that skill; the instructor console teaches up to level 3 without one.", 13, P.TEXT_2, 1100.0))
	if acs.is_empty():
		box.add_child(Kit.wrap("No academy. Build one (Science tab of the build bar) to train people and to school children.", 14, P.AMBER))
	for b in acs:
		var def: Dictionary = s.bd(b)
		var seats: int = int(def.get("seats_class", 4))
		var sec: VBoxContainer = Kit.vbox(4)
		box.add_child(sec)
		sec.add_child(Kit.head("%s  ·  %d seats  ·  %s" % [String(b["name"]).to_upper(), seats, String(b.get("state", "")).capitalize()], P.CYAN, 12))
		var students: Array = []
		if s.get("education") != null and s.education.has_method("students"):
			students = s.education.students(int(b["id"]))
		if students.is_empty():
			sec.add_child(Kit.label("No course now.", "SmallLabel", 12, P.TEXT_3))
		for st in students:
			sec.add_child(Kit.bar_row("%s: %s" % [hud.v5.agent_name(int(st["agent"])), String(st.get("skill", "")).capitalize()], float(st.get("progress", 0.0)), "%d%%" % int(float(st.get("progress", 0.0)) * 100.0), P.CYAN, 260.0))
	# Enrolment form
	box.add_child(Kit.sep())
	box.add_child(Kit.head("Enrol a person", P.CYAN, 12))
	var row: HBoxContainer = Kit.hbox(8)
	box.add_child(row)
	var who := OptionButton.new()
	var ids: Array = []
	for r in _rows():
		who.add_item(String(r["name"]))
		ids.append(int(r["id"]))
	who.tooltip_text = "Person\nWho goes to the course."
	row.add_child(who)
	var sk := OptionButton.new()
	var skills: Array = s.content.get("people", {}).get("skills", [])
	for k in skills:
		sk.add_item(String(k).capitalize())
	sk.tooltip_text = "Skill\nThe skill the course teaches (one level up)."
	row.add_child(sk)
	var note: Label = Kit.label("", "SmallLabel", 12, P.TEXT_2)
	var upd := func():
		if ids.is_empty() or skills.is_empty():
			return
		var a: Dictionary = hud.v5.agent(int(ids[who.selected]))
		var v: float = float(s.people.skills(a).get(String(skills[sk.selected]), 0.0))
		note.text = "Now level %d (%s). The course takes them to level %d." % [s.people.level_of(v), s.people.level_name(v), mini(5, s.people.level_of(v) + 1)]
	who.item_selected.connect(func(_i): upd.call())
	sk.item_selected.connect(func(_i): upd.call())
	upd.call()
	row.add_child(Kit.button("Enrol", func():
		if ids.is_empty() or acs.is_empty():
			hud.toast("Enrol: build an academy first.", "warn", "research")
			return
		var aid: int = int(ids[who.selected])
		var skill: String = String(skills[sk.selected])
		hud.confirm("Enrol %s in %s?" % [hud.v5.agent_name(aid), skill.capitalize()], ["%s leaves work for the lessons during the shift." % hud.v5.agent_name(aid).get_slice(" ", 0), "The skill goes up one level when the course ends."], func():
			last_result = hud.v5.command("enrol", {"agent": aid, "skill": skill, "building": int(acs[0]["id"])})
			hud.toast("Enrol: " + String(last_result["text"]), "info" if bool(last_result["ok"]) else "warn", "research")
			_build_tab_content(), "Enrol"), "Enrol\nSends the person to the next course of this skill.", "PrimaryButton", "check", 14))
	box.add_child(note)
	_skill_table(box, skills)

## Every person's skill levels 1-5 (critic round 30, fix 6: the lower half is a table, not empty).
func _skill_table(box: VBoxContainer, skills: Array) -> void:
	var s = hud.main.sim
	box.add_child(Kit.sep())
	box.add_child(Kit.head("Skill levels of the crew (1 Novice .. 5 Master)", P.CYAN, 12))
	var g: GridContainer = Kit.grid(skills.size() + 2, 6, 4)
	g.name = "SkillTable"
	var well: PanelContainer = Kit.well_scroll(g, true)
	box.add_child(well)
	g.add_child(Kit.dim("", 12))
	g.add_child(Kit.dim("Person", 12))
	for k in skills:
		var h: Label = Kit.head(String(SKILL_ABBR.get(String(k), String(k).left(3))).to_upper(), P.TEXT_2, 12)
		h.tooltip_text = "%s\nLevel 1 Novice .. 5 Master." % String(k).capitalize()
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size.x = 56
		g.add_child(h)
	var cols := LEVEL_COL
	for r in _rows():
		var a: Dictionary = hud.v5.agent(int(r["id"]))
		if a.is_empty():
			continue
		var sk: Dictionary = s.people.skills(a)
		g.add_child(mood_face(float(r["satisfaction"])))
		var nl: Label = Kit.label(String(r["name"]), "", 13, P.TEXT)
		nl.custom_minimum_size.x = 150
		g.add_child(nl)
		for k in skills:
			var val: float = float(sk.get(String(k), 0.0))
			var lv: int = int(s.people.level_of(val))
			var col: Color = cols[clampi(lv - 1, 0, 4)]
			# A chip coloured by level (critic round 36): the number on a tint of the level colour.
			var chip := PanelContainer.new()
			var st := StyleBoxFlat.new()
			st.bg_color = Color(col.r, col.g, col.b, 0.10 + 0.07 * float(lv))
			st.set_corner_radius_all(3)
			st.content_margin_top = 1
			st.content_margin_bottom = 1
			chip.add_theme_stylebox_override("panel", st)
			chip.custom_minimum_size.x = 56
			chip.tooltip_text = "%s: %s\nLevel %d, %s (skill %d)." % [String(r["name"]), String(k).capitalize(), lv, String(s.people.level_name(val)), int(val)]
			chip.mouse_filter = Control.MOUSE_FILTER_PASS
			var c: Label = Kit.label("%d" % lv, "", 13, col.lightened(0.15))
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.add_child(c)
			g.add_child(chip)
