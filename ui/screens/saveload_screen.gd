extends "res://ui/screens/screen.gd"
## Save and load: three manual slots, the rotating autosaves, export to a .fhsave file and
## import one (validated before anything is replaced). Version-1 behaviour is kept.

const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	compact = true
	compact_size = Vector2(720, 0)
	pauses = true
	icon = "save"
	title = "Save and load"

func build() -> void:
	var in_game: bool = not bool(hud.main.on_title)
	set_subtitle("The game also saves itself every five minutes of play." if in_game else "Load a colony, or import a save file.")
	if hud.main.persist_warning != "":
		content.add_child(Kit.wrap(hud.main.persist_warning, 13, P.AMBER))
	if in_game:
		var sv: VBoxContainer = card("Save this colony", "save", P.CYAN)
		content.add_child(card_panel(sv))
		var row: HBoxContainer = Kit.hbox(8)
		sv.add_child(row)
		for n in [1, 2, 3]:
			var slot := "manual_%d" % n
			row.add_child(Kit.button("Slot %d" % n, func():
				hud.main.save_game(slot)
				host.close(self), "Save to slot %d\nReplaces what is in the slot." % n, "", "save", 16))
		row.add_child(Kit.spacer())
		row.add_child(Kit.button("Export file", func(): hud.main.export_save(), "Export\nWrites a versioned .fhsave file you can keep or move to another computer.", "", "export", 16))
	var ld: VBoxContainer = card("Load", "load", P.CYAN)
	content.add_child(card_panel(ld))
	var slots: Array = Persistence.list_slots()
	if slots.is_empty():
		ld.add_child(Kit.label("No saves on this device yet.", "SmallLabel", 12, P.TEXT_3))
	for s in slots:
		var slot: String = s["slot"]
		var row2: HBoxContainer = Kit.hbox(10)
		row2.add_child(Kit.icon("history" if slot.begins_with("auto") else "save", 18, P.TEXT_2))
		var nm: Label = Kit.label(slot.replace("_", " ").capitalize(), "BodyStrong", 14)
		nm.custom_minimum_size.x = 140
		row2.add_child(nm)
		row2.add_child(Kit.num(Time.get_datetime_string_from_unix_time(int(s["modified"]), true), 13, P.TEXT_2))
		row2.add_child(Kit.spacer())
		row2.add_child(Kit.button("Load", func():
			if in_game:
				hud.confirm("Load %s?" % slot.replace("_", " "), ["The current colony is lost unless you saved it."], func(): hud.main.load_game(slot), "Load")
			else:
				hud.main.load_game(slot), "", "", "load", 14))
		ld.add_child(row2)
	var imp: HBoxContainer = Kit.hbox(8)
	ld.add_child(imp)
	imp.add_child(Kit.button("Import a save file", func(): hud.main.import_save(), "Import\nLoads a .fhsave file. The file is checked before anything is replaced.", "", "import", 16))
	var btns: HBoxContainer = Kit.hbox(8, BoxContainer.ALIGNMENT_END)
	content.add_child(btns)
	btns.add_child(Kit.button("Back", func(): host.close(self), "", "", "close", 14))
