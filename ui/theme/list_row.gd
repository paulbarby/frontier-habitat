extends StyleBox
## A row of a list in the version-4 style (critic round 15 rule "lists and tables: darker glass
## wells with seam separators, no box per row"): a faint dark wash, a 3 px signal bar on the left
## (the severity or kind colour, never the only sign: the row text says it too) and an engraved
## seam under the row. Used by the alerts, hazard and traffic panels.

const Rim = preload("res://ui/theme/rim.gd")

var bar := Color(0.24, 0.88, 1.0, 0.9)
var wash := Color(0.0, 0.02, 0.05, 0.22)
var seam := true

func _init() -> void:
	content_margin_left = 10
	content_margin_right = 6
	content_margin_top = 5
	content_margin_bottom = 7

static func make(col: Color) -> StyleBox:
	var s = load("res://ui/theme/list_row.gd").new()
	s.bar = Color(col.r, col.g, col.b, 0.9)
	return s

func _draw(ci: RID, rect: Rect2) -> void:
	if wash.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, rect, wash)
	RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position.x, rect.position.y + 2.0, 3.0, maxf(0.0, rect.size.y - 6.0)), bar)
	if seam:
		Rim.seam_h(ci, rect.position.x, rect.end.x, rect.end.y - 2.0, 0.9)
