extends SceneTree
## Find window and marks (docs/V4_DESIGN.md §3.4), headless:
##   node tools/godot.mjs script res://tools/ui/test_find.gd

var main
var fails := 0
var _n := 0
var _step := 0

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func count_def(def_id: String) -> int:
	var n := 0
	for id in main.sim.state["buildings"]:
		if String(main.sim.state["buildings"][id]["def"]) == def_id:
			n += 1
	return n

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var f = main.hud.find
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.hud.wm.forget("find")
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
			main._on_cmd("speed 0")
			var r: String = main._on_cmd("find kitchen")
			check("find opens the window", f.visible, r)
			var all_k := true
			for x in f.results:
				all_k = all_k and (String(x["name"]) + " " + String(x["def"])).to_lower().contains("kitchen")
			check("\"kitchen\" lists only kitchens, at least one", f.results.size() >= 1 and all_k and f.results.size() == count_def("kitchen"), r)
			check("each result has district, status and a family", not f.results.is_empty() and String(f.results[0]["district"]) != "" and String(f.results[0]["status"]) != "" and String(f.results[0]["cat"]) != "")
			var r2: String = main._on_cmd("find science")
			check("a family word finds by family (science)", f.results.size() >= count_def("research_lab"), r2)
			var r3: String = main._on_cmd("find corridor")
			check("corridors and cables are not listed", f.results.is_empty(), r3)
			var r4: String = main._on_cmd("find zzqx")
			check("no match says so", f.results.is_empty() and String(f._count.text).begins_with("Nothing matches"), f._count.text)
			main._on_cmd("find kitchen")
			set_meta("want", int(f.results[0]["id"]))
			f._go_first()
			_step = 1
			_n = 0
		1:
			var want: int = get_meta("want")
			main.hud.find.refresh()
			check("Enter / click goes to the first result and selects it", main.view.selected_kind == "building" and main.view.selected_id == want, "%s %d" % [main.view.selected_kind, main.view.selected_id])
			var wa: Rect2 = main.hud.wm.work_area()
			var fr: Rect2 = f.get_global_rect()
			check("the Find window lies in the work area (clear of the nav rail)", wa.grow(0.5).encloses(fr), "%s in %s" % [str(fr), str(wa)])
			var widths: Array = []
			for ch in f.get_children():
				if ch is VBoxContainer:
					for k in ch.get_children():
						if k is Control:
							widths.append("%s:%d" % [k.get_class(), int((k as Control).get_combined_minimum_size().x)])
			check("the Find window keeps its width", fr.size.x <= 400.5, "%s rows %s" % [str(fr.size), str(widths)])
			var m: String = main._on_cmd("findmark research_lab")
			check("findmark marks every structure of the type", main.hud.find_marks.marks.size() == count_def("research_lab") and count_def("research_lab") > 0, m)
			main._on_cmd("findmark off")
			f._toggle_mark()
			check("Mark all marks the first result's type", main.hud.find_marks.def_id == "kitchen" and f._mark.button_pressed, main.hud.find_marks.def_id)
			f._toggle_mark()
			check("Mark all again clears the marks", main.hud.find_marks.def_id == "" and main.hud.find_marks.marks.is_empty())
			# Esc: Find is the top window (opened after the inspector? raise it) and closes first.
			main._on_cmd("findlabels all")
			set_meta("lab_on", main.hud.find_marks.labels == "all" and main.hud.find._labels.selected == 1)
			main.hud.wm.raise("find")
			main._on_cmd("esc")
			check("Esc closes the Find window first", not f.visible and main.hud.inspector.visible)
			check("the bounds keeper finds nothing outside", main.hud.bounds.outside(main.hud.root.get_viewport_rect().size).is_empty())
			check("the label layer turns on from the Find window (all rooms)", get_meta("lab_on"))
			main._on_cmd("findlabels food")
			check("the label layer can show one family", main.hud.find_marks.labels == "food")
			main._on_cmd("findlabels off")
			check("the label layer turns off", main.hud.find_marks.labels == "")
			main.hud.wm.forget("find")
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
