extends VBoxContainer
## A list of rows with an engraved seam between each two rows (critic round 15 rule "lists and
## tables: darker glass wells with seam separators, no box per row"). Put it in Kit.well_scroll()
## for the darker well behind it. Section headings (children with meta "no_seam") get no seam.

const Rim = preload("res://ui/theme/rim.gd")

func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS
	sort_children.connect(queue_redraw)

func _draw() -> void:
	var sep: float = float(get_theme_constant("separation"))
	var kids: Array = []
	for c in get_children():
		if c is Control and (c as Control).visible:
			kids.append(c)
	for i in range(kids.size() - 1):
		var a: Control = kids[i]
		var b: Control = kids[i + 1]
		if a.has_meta("no_seam") or b.has_meta("no_seam"):
			continue
		var y: float = floorf(a.position.y + a.size.y + sep * 0.5) - 1.0
		Rim.seam_h(get_canvas_item(), 0.0, size.x, y, 0.8)
