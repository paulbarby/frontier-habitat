extends Control
## Progress bar with a glow: a dark well, a gradient fill, a soft halo and a bright end cap.
## `target` (0..1, < 0 = none) draws a marker line, for "needed" levels.
## `segments` > 0 draws the fill as separate blocks (upgrade levels, pips).

var value := 0.0:
	set(v):
		if not is_equal_approx(v, value):
			value = v
			queue_redraw()
var color := Color("3EE0FF"):
	set(c):
		if c != color:
			color = c
			queue_redraw()
var target := -1.0:
	set(v):
		target = v
		queue_redraw()
var segments := 0
var show_glow := true
var track := Color(0.02, 0.04, 0.075, 0.9)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, track, true)
	draw_rect(r, Color(color.r, color.g, color.b, 0.18), false, 1.0)
	var v: float = clampf(value, 0.0, 1.0)
	if segments > 0:
		var gap := 3.0
		var w: float = (size.x - gap * float(segments - 1)) / float(segments)
		for i in segments:
			var sr := Rect2(float(i) * (w + gap), 0.0, w, size.y)
			var on: bool = float(i) + 0.5 < v * float(segments)
			if on:
				if show_glow:
					draw_rect(sr.grow(1.5), Color(color.r, color.g, color.b, 0.22), true)
				draw_rect(sr, color, true)
				draw_rect(Rect2(sr.position, Vector2(sr.size.x, 1.0)), Color(1, 1, 1, 0.35), true)
			else:
				draw_rect(sr, Color(color.r, color.g, color.b, 0.12), true)
		return
	if v > 0.0:
		var fr := Rect2(Vector2.ZERO, Vector2(maxf(2.0, size.x * v), size.y))
		if show_glow:
			draw_rect(fr.grow(2.0), Color(color.r, color.g, color.b, 0.14), true)
			draw_rect(fr.grow(1.0), Color(color.r, color.g, color.b, 0.2), true)
		var dark: Color = color.darkened(0.35)
		var pts := PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)])
		draw_polygon(pts, PackedColorArray([dark, color, color, dark]))
		draw_rect(Rect2(fr.position, Vector2(fr.size.x, maxf(1.0, size.y * 0.25))), Color(1, 1, 1, 0.22), true)
		draw_rect(Rect2(Vector2(fr.end.x - 2.0, 0.0), Vector2(2.0, size.y)), color.lightened(0.5), true)
	if target >= 0.0 and target <= 1.0:
		var x: float = size.x * target
		draw_line(Vector2(x, -2.0), Vector2(x, size.y + 2.0), Color(1, 1, 1, 0.85), 1.5)
