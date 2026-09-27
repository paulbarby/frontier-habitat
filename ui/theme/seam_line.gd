extends StyleBox
## An engraved seam (critic round 15, fix 8 and the list rule): a dark hairline and a light one
## beside it, as a cut in the glass. The theme uses it for HSeparator and VSeparator, so every
## separator in the interface is a seam.

const Rim = preload("res://ui/theme/rim.gd")

var vertical := false
var alpha := 1.0

func _init() -> void:
	content_margin_top = 1
	content_margin_bottom = 1
	content_margin_left = 1
	content_margin_right = 1

func _draw(ci: RID, rect: Rect2) -> void:
	if vertical:
		Rim.seam_v(ci, floorf(rect.get_center().x) - 1.0, rect.position.y, rect.end.y, alpha)
	else:
		Rim.seam_h(ci, rect.position.x, rect.end.x, floorf(rect.get_center().y) - 1.0, alpha)
