extends SceneTree
## Every v5 window on real v5 data (SIM's content/saves/showcase_v5.fhsave: 132 people, children,
## couples, officers, a prisoner, students, a finished dome with open venues), headless:
##   node tools/godot.mjs script res://tools/ui/test_v5_showcase.gd
## Personnel file (Family, Adopt through SIM, a child's School), Crew (Security with officers and the
## prisoner, Academy with students, a lockdown through SIM with the banner and the time left),
## the dome's Venues tab (open venues, staff, goods, tourism, a staff order through SIM), the dashboard's
## Tourism card, SIM's response effects on the unrest banner, and the dome stage badge on RENDER's
## dome_v5_stage_3 save.

var main
var fails := 0
var _n := 0
var _step := 0
var dome := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _texts(n: Node) -> String:
	var t := ""
	if n == null:
		return t
	for l in n.find_children("*", "Label", true, false):
		t += (l as Label).text + " | "
	for b in n.find_children("*", "Button", true, false):
		t += (b as Button).text + " | "
	return t

## Presses the confirm dialog's yes button (the one that is not Back).
func yes() -> bool:
	var top = main.hud.screens.top_screen()
	if top == null or main.hud.screen_name() != "confirm":
		return false
	for b in top.find_children("*", "Button", true, false):
		var t: String = (b as Button).text
		if t != "" and t != "Back" and t != "OK":
			(b as Button).pressed.emit()
			return true
	return false

func _button(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
			main._on_cmd("speed 0")
			check("showcase_v5: 100 or more people, children, couples", hud.v5.people().size() >= 100 and not sim.relations.pairs_with(["married", "partners"]).is_empty(), "%d people" % hud.v5.people().size())
			# 1. A married parent: Family (children, Adopt).
			var pr: Dictionary = sim.relations.pairs_with(["married", "partners"])[0]
			var par: int = int(pr["a"])
			for c in sim.relations.pairs_with(["married", "partners"]):
				if not sim.families.children_of(int(c["a"])).is_empty():
					par = int(c["a"])
					break
			main.select("agent", par)
			hud.open_person(par, "social")
			_step = 1
			_n = 0
		1:
			var fam: Node = hud.person._body.find_child("Family", true, false)
			var t: String = _texts(fam)
			check("personnel file, Social: Family with the children", fam != null and t.contains("Children"), t.left(300))
			var ab: Button = _button(hud.person._body, "Adopt a child")
			check("personnel file: Adopt a child for a married couple", ab != null)
			if ab != null:
				ab.pressed.emit()
				check("adopt: confirm first", yes())
			_step = 2
			_n = 0
		2:
			var lr: Dictionary = hud.person.last_result
			check("adopt: SIM answers (ok, or its reason)", lr.has("code") and String(lr.get("code", "")) != "not_yet" and String(lr.get("text", "")) != "", str(lr))
			# 2. A child's School.
			var kid := -1
			for aid in sim.state["agents"]:
				var a: Dictionary = sim.state["agents"][aid]
				if a["state"] == "alive" and String(a.get("kind", "")) == "child":
					kid = int(aid)
					break
			hud.open_person(kid, "file")
			_step = 3
			_n = 0
		3:
			var sc: Node = hud.person._body.find_child("School", true, false)
			var t: String = _texts(sc)
			check("child's file: School with points by subject, the academy, grows up in", sc != null and t.contains("points") and t.contains("Grows up in"), t.left(300))
			hud.person.visible = false
			# 3. Crew: Security at the base of the jail.
			hud.open_screen("crew")
			_step = 4
			_n = 0
		4:
			var top = hud.screens.top_screen()
			var jb: int = int(sim.security.jails(-1)[0]) if not sim.security.jails(-1).is_empty() else -1
			top.base_id = sim.bases.base_of(jb) if sim.bases.count() > 1 and jb >= 0 else -1
			top.set_tab("security")
			_step = 5
			_n = 0
		5:
			var top = hud.screens.top_screen()
			var t: String = _texts(top.content)
			var pris: Array = []
			for j in sim.security.jails(top.base_id):
				pris.append_array(sim.security.prisoners_in(int(j)))
			check("crew Security: officers listed (chips)", top.content.find_children("*", "Button", true, false).size() > 3 and not t.contains("No security officer"), t.left(200))
			check("crew Security: the prisoner by name with time left", not pris.is_empty() and t.contains(hud.v5.agent_name(int(pris[0]))) and t.contains("left"), "%s | %s" % [str(pris), t.left(400)])
			var lb: Button = _button(top.content, "Lock down this base")
			check("crew Security: Lock down this base (SIM's effect beside it)", lb != null and t.contains("Doors close"), t.left(300))
			if lb != null:
				lb.pressed.emit()
				check("lock down: confirm first", yes())
			_step = 6
			_n = 0
		6:
			var top = hud.screens.top_screen()
			check("lock down: SIM answers ok", bool(top.last_result.get("ok", false)), str(top.last_result))
			hud.unrest_banner._update()
			var ub = hud.unrest_banner
			check("lockdown banner: shows with the doors-open time", ub.visible and ub.shown_stage in ["lockdown", "protest", "strike", "riot"] and String(ub._lock.text).contains("DOORS OPEN IN"), "%s %s" % [ub.shown_stage, ub._lock.text])
			var t2: String = _texts(top.content.find_child("LockRow", true, false))
			check("crew Security: LOCKDOWN and the time left", t2.contains("LOCKDOWN") and t2.contains("DOORS OPEN IN"), t2)
			top.set_tab("academy")
			_step = 7
			_n = 0
		7:
			var top = hud.screens.top_screen()
			var t: String = _texts(top.content)
			var st: Array = []
			for bid in sim.state["buildings"]:
				if String(sim.state["buildings"][bid]["def"]) == "academy":
					st.append_array(sim.education.students(int(bid)))
			check("crew Academy: the students by name and skill", not st.is_empty() and t.contains(hud.v5.agent_name(int(st[0]["agent"]))), "%d students | %s" % [st.size(), t.left(300)])
			hud.close_modal()
			# 4. The dome: Venues tab.
			for bid in sim.state["buildings"]:
				if String(sim.state["buildings"][bid]["def"]) == "super_dome":
					dome = int(bid)
			main.select("building", dome)
			hud.inspector.set_tab("venues")
			_step = 8
			_n = 0
		8:
			var vs: Node = hud.inspector.find_child("Venues", true, false)
			var t: String = _texts(vs)
			var rows: int = vs.find_children("Venue_*", "", true, false).size() if vs != null else 0
			check("dome Venues: every venue a row, open ones marked", rows == sim.leisure.venues(sim.state["buildings"][dome]).size() and t.contains("OPEN"), "%d rows" % rows)
			check("dome Venues: staff names and tourist prices", t.contains("Staff 1 of 1: ") and t.contains("Tourists pay"), t.left(300))
			check("dome Venues: tourism line (visitors, earned, balance)", t.contains("Visitors now") and t.contains("tourism earned"), t.left(200))
			var ob: OptionButton = vs.find_child("Staff_grocery", true, false) if vs != null else null
			check("dome Venues: a staff choice per venue", ob != null and ob.item_count > 3)
			if ob != null:
				ob.select(3)
				ob.item_selected.emit(3)
			_step = 9
			_n = 0
		9:
			check("staff order: SIM answers ok", bool(hud.inspector.last_staff.get("ok", false)), str(hud.inspector.last_staff))
			var ds: Dictionary = sim.leisure.dome_stage(sim.state["buildings"][dome])
			check("finished dome: no stage badge", String(ds.get("id", "")) == "done" and not _texts(hud.inspector._badges).contains("STAGE"), _texts(hud.inspector._badges))
			# 5. Dashboard, People: Tourism.
			main._on_cmd("select none")
			hud.open_screen("dashboard", "population")
			_step = 10
			_n = 0
		10:
			if _n < 25:
				return false
			var top = hud.screens.top_screen()
			var tp: Node = top.content.find_child("Tourism", true, false)
			var t: String = _texts(tp)
			check("dashboard People: Tourism card with visitors and credits", tp != null and t.contains("credits") and t.contains("Visitors now"), t)
			hud.close_modal()
			# 6. SIM's response effects on the unrest banner.
			main._on_cmd("unrest protest")
			_step = 11
			_n = 0
		11:
			var el: Label = hud.unrest_banner._eff.get("party")
			check("unrest banner: SIM's effect for the party (stock it uses)", el != null and el.text.contains("Uses"), el.text if el != null else "")
			main._on_cmd("unrest off")
			# 7. The dome stage badge on RENDER's stage save.
			var path: String = ProjectSettings.globalize_path("res://build/web_render/dome_v5_stage_3.fhsave")
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
			check("RENDER's dome_v5_stage_3 save is there", bytes.size() > 0, path)
			if bytes.size() > 0:
				main._import_bytes(bytes)
				main._on_cmd("speed 0")
			_step = 12
			_n = 0
		12:
			var d2 := -1
			for bid in sim.state["buildings"]:
				if String(sim.state["buildings"][bid]["def"]) == "super_dome":
					d2 = int(bid)
			if d2 >= 0:
				main.select("building", d2)
			_step = 13
			_n = 0
		13:
			var t: String = _texts(hud.inspector._badges)
			var ds: Dictionary = main.sim.leisure.dome_stage(main.sim.state["buildings"].get(hud.inspector._id, {})) if hud.inspector._id >= 0 else {}
			check("dome under construction: STAGE n OF 9 badge", t.contains("OF 9") and t.contains("STAGE %d" % (int(ds.get("index", -2)) + 1)), "%s %s" % [t, str(ds)])
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
			return true
	return false
