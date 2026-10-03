extends VBoxContainer
## The dock card of the work queue (V5_DESIGN §18.3: the dock shows a count of urgent unassigned items). Hosted by the
## panel manager in the Alerts tab. It shows the open work and the urgent items nobody has; Open shows the Work window (key M).

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")

var hud
var urgent := 0          # urgent items with nobody on them (tests, the nav rail badge)
var open_items := 0
var _line: Label
var _open: Button

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_line = Kit.wrap("", 13, P.TEXT)
	add_child(_line)
	_open = Kit.button("Open the Work window", func(): hud.work.open_tab("all"), "Work\nThe queues of every department: change the order, assign, cancel. Key M.", "GhostButton", "queue", 14)
	_open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_open)
	visible = false

func refresh() -> void:
	var sum: Dictionary = hud.v18.summary()
	open_items = 0
	for d in sum["by_dept"]:
		open_items += int(sum["by_dept"][d])
	urgent = int(sum["urgent"])
	visible = open_items > 0
	_line.text = "%s  ·  %s" % [Kit.plural(open_items, "open item"), ("%d urgent and not assigned" % urgent) if urgent > 0 else "none urgent without a person"]
	_line.add_theme_color_override("font_color", P.AMBER if urgent > 0 else P.TEXT_2)
