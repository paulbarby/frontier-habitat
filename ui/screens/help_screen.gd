extends "res://ui/screens/screen.gd"
## How to play: the rules on one page, the controls, and the mission.

func _init() -> void:
	pauses = true
	icon = "info"
	title = "How to play"
	subtitle = "You plan. The colonists do the work by themselves."
	margins = Vector4(160, 50, 160, 50)
	tabs = [["rules", "Rules", "info"], ["keys", "Controls", "keyboard"], ["mission", "Mission", "goals"]]

func _ready() -> void:
	if typeof(arg) == TYPE_STRING and String(arg) != "":
		tab = String(arg)
	super._ready()

func build_tab(id: String, box: VBoxContainer) -> void:
	var body: VBoxContainer = Kit.vbox(12)
	box.add_child(Kit.scroll(body))
	match id:
		"keys":
			var g: GridContainer = Kit.grid(2, 24, 6)
			body.add_child(g)
			for pair in [["W A S D or arrows", "Move the camera. Screen-edge pan can be switched on in Settings."], ["Mouse wheel", "Zoom."],
					["Middle mouse drag, Q and E", "Turn the camera."], ["Left click", "Select a structure or a colonist."], ["Right click, Esc", "Cancel the tool or clear the selection. Esc opens the menu."],
					["Space", "Pause. You can plan while paused."], ["1, 2, 3", "Speed 1x, 2x, 4x."], ["R, Shift+R", "Turn the structure you place by 15 degrees."],
					["Z and X", "Smaller or bigger size while placing (S, M, L, XL)."], ["Shift + click", "Place more than one, or chain corridors."], ["Delete", "Remove the selected structure."],
					["F", "Follow the selected colonist."], ["O", "Step through the overlays: power, water, air, walking."], ["G", "Goals."], ["T", "Research."], ["C", "Colony dashboard."],
					["I", "Inventory."], ["P", "Colonists."], ["V", "Awards."], ["H", "Hide or show the interface."]]:
				g.add_child(Kit.num(pair[0], 13, P.CYAN))
				g.add_child(Kit.wrap(pair[1], 14, P.TEXT))
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
				["Air", "o2", "People breathe only in rooms joined by corridors to a working oxygen plant. Outside, a suit holds 90 seconds of air. It refills in an airlock that has air."],
				["Joining", "corridor", "Corridors join rooms: people, power, water and air. Cables join outdoor structures: power and water only. A structure that is not joined gets nothing."],
				["Carrying", "crate", "A colonist carries two units. Food and materials must be carried. Power, water and oxygen flow through the networks."],
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
