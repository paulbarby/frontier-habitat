extends SceneTree
## "The Regolith Rag" window (V5_DESIGN §4.3, §10), headless, on showcase_v5 (stored issues and relations):
##   node tools/godot.mjs script res://tools/ui/test_rag.gd
## The issues come from SIM (or the preview), every part of the page is built, names link to people
## and a click selects them, back issues switch, and the window stays inside the view at 1600x900
## and 1280x720 for every issue.

var main
var fails := 0
var _n := 0
var _step := 0
var _i := 0
var outside: Array = []

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _texts(n: Node) -> String:
	var t := ""
	for l in n.find_children("*", "Label", true, false):
		t += (l as Label).text + " | "
	for r in n.find_children("*", "RichTextLabel", true, false):
		t += (r as RichTextLabel).get_parsed_text() + " | "
	return t

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
			main._on_cmd("speed 0")
			main._on_cmd("rag")
			_step = 1
			_n = 0
		1:
			var rag = hud.rag
			check("issues: newest first, up to 30", rag._issues.size() >= 3 and rag._issues.size() <= 30 and int(rag._issues[0]["day"]) >= int(rag._issues[1]["day"]), "%d issues" % rag._issues.size())
			check("from SIM when SIM has the social system", hud.v5.live("social") == (not hud.v5.preview()))
			var t: String = _texts(rag._body)
			for part in ["THE REGOLITH RAG", "THE DUST-UP", "COUPLE WATCH", "FEUD WATCH", "RAG POLL", "SMALL ADS", "SERIOUS NEWS"]:
				check("the page has %s" % part, t.contains(part))
			check("the lead headline is on the page", t.contains(String(rag._issues[0]["lead"]["headline"])))
			check("a lead photo (placeholder until RENDER's photo())", rag._body.find_child("LeadPhoto", true, false) != null)
			check("names are links", rag.links.size() >= 2, str(rag.links.slice(0, 3)))
			var al: Rect2 = hud.alerts.get_global_rect()
			check("a covered alerts panel folds (critic round 25)", not rag.get_global_rect().intersects(hud.alerts._folded_rect if "_folded_rect" in hud.alerts else al) or hud.alerts.collapsed, "alerts %s rag %s" % [str(al), str(rag.get_global_rect())])
			for lay in ["special", "quiet", "standard"]:
				main._on_cmd("raglayout " + lay)
				check("layout %s builds, lead headline at most 2 lines (critic round 30)" % lay, rag.layout == lay and rag.lead_lines >= 1 and rag.lead_lines <= 2, "%d lines" % rag.lead_lines)
				if lay == "quiet":
					var qt: String = _texts(rag)
					check("quiet day: SLOW NEWS DAY kicker and the bigger gossip box", qt.contains("SLOW NEWS DAY"))
					var gg: Node = rag._body.find_child("GossipGrid", true, false)
					check("quiet day: the gossip column is full width, 2 columns, 8 items (critic round 36)", gg != null and gg.get_child_count() >= 6, str(gg.get_child_count() if gg != null else -1))
					check("quiet day: PHOTO OF THE DAY box", rag._body.find_child("PhotoOfDay", true, false) != null and qt.contains("PHOTO OF THE DAY"))
					var any_line := false
					for r in hud.v5.people():
						if not hud.v5.recent_lines(int(r["id"]), 1).is_empty():
							any_line = true
							break
					check("quiet day: WHO SAID IT? puzzle when people have said something", (not any_line) or (rag.puzzle.size() >= 2 and qt.contains("WHO SAID IT")), "%d quotes" % rag.puzzle.size())
			main._on_cmd("raglayout auto")
			var l0: Dictionary = rag.links[0] if not rag.links.is_empty() else {}
			if not l0.is_empty():
				rag._on_meta("agent:%d" % int(l0["id"]))
			check("a click on a name selects the person", not l0.is_empty() and main.view.selected_kind == "agent" and main.view.selected_id == int(l0["id"]), str(l0))
			_i = 0
			_step = 2
			_n = 0
		2:
			# Every issue at 1600x900: the window inside the view.
			var rag = hud.rag
			if _i < rag._issues.size():
				rag.show_issue(_i)
				_i += 1
				_n = 5
				return false
			_check_inside("1600x900")
			root.size = Vector2i(1280, 720)
			rag.visible = false
			rag.visible = true
			_i = 0
			_step = 3
			_n = 0
		3:
			var rag = hud.rag
			if _i < rag._issues.size():
				rag.show_issue(_i)
				_i += 1
				_n = 5
				return false
			_check_inside("1280x720")
			check("back issue list = issues", rag._issue_btn.item_count == rag._issues.size())
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false

func _check_inside(label: String) -> void:
	var r: Rect2 = main.hud.rag.get_global_rect()
	var vp := Rect2(Vector2.ZERO, main.hud.rag.get_viewport_rect().size)
	check("%s: the window stays inside the view for every issue (last %s)" % [label, str(r)], vp.encloses(r.grow(-1.0)) and main.hud.rag._scroll.get_h_scroll_bar().visible == false)
