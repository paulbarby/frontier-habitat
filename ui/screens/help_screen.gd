extends "res://ui/screens/screen.gd"
## How to play: the rules on one page, the controls, and the mission.

func _init() -> void:
	pauses = true
	icon = "info"
	title = "How to play"
	subtitle = "You plan. The colonists do the work by themselves."
	margins = Vector4(160, 50, 160, 50)
	tabs = [["rules", "Rules", "info"], ["people", "People", "colonists"], ["keys", "Controls", "keyboard"], ["mission", "Mission", "goals"]]

func _ready() -> void:
	if typeof(arg) == TYPE_STRING and String(arg) != "":
		tab = String(arg)
	super._ready()

func build_tab(id: String, box: VBoxContainer) -> void:
	var body: VBoxContainer = Kit.vbox(12)
	box.add_child(Kit.scroll(body))
	match id:
		"keys":
			# One list for How to play and Settings (ui/keys.gd); tools/ui/test_keys.gd checks it against the input code.
			var KeyList = load("res://ui/keys.gd")
			for grp in KeyList.GROUPS:
				body.add_child(Kit.head(String(grp), P.TEXT, 13))
				var g: GridContainer = Kit.grid(2, 24, 6)
				g.name = "Keys_" + String(grp)
				g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				body.add_child(g)
				for row in KeyList.ROWS:
					if String(row["g"]) != String(grp):
						continue
					var kl: Label = Kit.num(String(row["keys"]), 13, P.CYAN)
					kl.custom_minimum_size.x = 190
					g.add_child(kl)
					g.add_child(Kit.wrap(String(row["long"]), 14, P.TEXT))
		"people":
			# Version 5 (STE): one card for each topic, in groups; the same text is in the Codex, Guide tab.
			body.add_child(Kit.wrap("Version 5: the colonists are people. They have ranks, skills, friends, homes and moods. They talk, and the Rag prints what they do. They also bring security, a jail, families, shops, tourists and a super dome. Each planet has its own hazards.", 14, P.TEXT))
			var V5Help = load("res://ui/v5_help.gd")
			for cat in V5Help.CATEGORIES:
				var hd: Label = Kit.head(String(cat), P.CYAN, 13)
				hd.name = "Group_" + String(cat)
				body.add_child(hd)
				for tp in V5Help.TOPICS:
					if String(tp[3]) != String(cat):
						continue
					var row: HBoxContainer = Kit.hbox(14)
					row.add_child(Kit.icon(String(tp[2]), 26, P.CYAN))
					var v: VBoxContainer = Kit.vbox(2)
					v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					v.add_child(Kit.head(String(tp[1]), P.TEXT, 13))
					v.add_child(Kit.wrap(String(tp[4]), 14, P.TEXT_2))
					row.add_child(v)
					row.set_meta("topic", String(tp[0]))
					body.add_child(row)
		"mission":
			for ch in hud.data.chapters():
				var c: VBoxContainer = card(String(ch.get("name", "")), "chapter", P.CYAN)
				body.add_child(card_panel(c))
				c.add_child(Kit.wrap(String(ch.get("desc", "")), 14, P.TEXT))
				var names: Array = []
				for gl in ch.get("goals", []):
					names.append(String(gl["name"]))
				c.add_child(Kit.wrap("Goals: " + ", ".join(names) + ".", 13, P.TEXT_2))
			if hud.data.chapters().is_empty():
				body.add_child(Kit.wrap("The mission is not available yet.", 14, P.TEXT_2))
		_:
			var rules := [
				["Air", "o2", "People breathe only in rooms joined by corridors to a working oxygen plant. Outside, a suit holds %d seconds of air. It refills in an airlock that has air." % int(hud.data.bal().get("suit_air_seconds", 90))],
				["Joining", "corridor", "Corridors join rooms: people, power, water and air. Cables join outdoor structures: power and water only. A structure that is not joined gets nothing."],
				["Carrying", "crate", "A colonist carries %d units. Food and materials must be carried. Power, water and oxygen flow through the networks." % int(hud.data.bal().get("carry_human", 2))],
				["The lander", "home", "The lander air ends on day 3. Before then, build an airlock, a habitat and an oxygen plant, joined by corridors."],
				["Food", "food", "Greenhouses grow crops. A kitchen cooks them into dishes. One dish feeds one colonist for one day. Different dishes keep the diet balanced: protein, carbs, fat and vitamins."],
				["Research", "research", "A research lab with a scientist makes research points. Research unlocks structures, crops, sizes L and XL, and upgrade levels. Level 5 needs special research and exotic crystals."],
				["Sizes and levels", "size", "Most structures come in four sizes, S to XL, and five levels. A bigger size does more and costs more. An upgrade keeps the structure working while it is built."],
				["Alerts", "sev_warning", "Each alert says what failed, why, the time left and what to do. Show moves the camera to the cause."],
				["Goals and awards", "goals", "The mission has five chapters. Each goal done sends a supply pod to the lander. Medals mark what the colony achieves."],
			]
			for r in rules:
				var row: HBoxContainer = Kit.hbox(14)
				row.add_child(Kit.icon(r[1], 26, P.CYAN))
				var v: VBoxContainer = Kit.vbox(2)
				v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				v.add_child(Kit.head(r[0], P.TEXT, 13))
				v.add_child(Kit.wrap(r[2], 14, P.TEXT_2))
				row.add_child(v)
				body.add_child(row)
