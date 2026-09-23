extends "res://ui/screens/screen.gd"
## The loss report (spec acceptance 14): the causes of death and the events that led to
## them, in order, then ways back in.

const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	pauses = true
	closable = false
	icon = "sev_critical"
	accent = P.RED
	title = "The colony is lost"
	margins = Vector4(200, 60, 200, 60)

func build() -> void:
	var rep: Dictionary = hud.main.sim.metrics.failure_report()
	set_subtitle("No living colonists remain. Day %d." % int(rep["day"]))
	var causes: Array = []
	for c in rep["causes"]:
		causes.append("%d of %s" % [int(rep["causes"][c]), c])
	content.add_child(Kit.wrap("Deaths: " + ", ".join(causes) + ".", 15, P.TEXT))
	content.add_child(Kit.head("What happened, in order", P.AMBER, 12))
	var list: VBoxContainer = Kit.vbox(4)
	content.add_child(Kit.scroll(list))
	var day_ticks: int = int(hud.main.sim.bal["day_length"]) * int(hud.main.sim.bal["tick_hz"])
	for e in rep["events"]:
		var row: HBoxContainer = Kit.hbox(10)
		row.add_child(Kit.num("Day %d %s" % [int(e["tick"]) / day_ticks + 1, Kit.clock(float(int(e["tick"]) % day_ticks) / 10.0)], 12, P.TEXT_3))
		row.add_child(Kit.icon(P.sev_icon(int(e["sev"])), 14, P.sev(int(e["sev"]))))
		row.add_child(Kit.wrap(String(e["text"]), 13, P.TEXT))
		list.add_child(row)
	var btns: HBoxContainer = Kit.hbox(10, BoxContainer.ALIGNMENT_END)
	content.add_child(btns)
	btns.add_child(Kit.button("Load a save", func(): hud.open_screen("saveload"), "", "", "load", 16))
	btns.add_child(Kit.button("New colony", func(): hud.open_screen("newcolony"), "", "", "new_game", 16))
	btns.add_child(Kit.button("Same seed again", func(): hud.main.start_new(int(hud.main.sim.state["seed"]), hud.main.sim.state.get("options", {})), "", "PrimaryButton", "rotate", 16))
