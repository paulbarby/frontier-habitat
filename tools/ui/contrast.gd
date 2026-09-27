extends SceneTree
## Text contrast of the version-4 glass (critic round 15, fix 1: WCAG AA 4.5:1 for body text over
## the brightest scene).
##   node tools/godot.mjs script res://tools/ui/contrast.gd <scene_no_hud.png> <with_hud.png> x,y,w,h [x,y,w,h ...]
## 1. Worst case, computed: the brightest scene pixel (99.5th percentile of the HUD-off shot) put
##    through the glass layers exactly as the shaders and GlassFrame draw them (blur smoke 20%,
##    tint at its lightest (top), sheen at full). The blur averages, so a real panel is darker
##    than this bound.
## 2. Measured: in each rect of the HUD shot (a panel body), the background is the 90th percentile
##    of the pixels that are not text (luminance below the 85th percentile); contrast of the
##    theme text colours against it.

const TEXT := Color("E6EEF7")
const TEXT_2 := Color("A3B5CA")
const TEXT_3 := Color("9FAFC2")

static func lin(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)

static func lum(c: Color) -> float:
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)

static func ratio(a: Color, b: Color) -> float:
	var la: float = lum(a)
	var lb: float = lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

static func over(dst: Color, src: Color) -> Color:
	return Color(dst.r + (src.r - dst.r) * src.a, dst.g + (src.g - dst.g) * src.a, dst.b + (src.b - dst.b) * src.a, 1.0)

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 3:
		print("usage: contrast.gd <scene_no_hud.png> <with_hud.png> x,y,w,h ...")
		quit(2)
		return
	var scene := Image.load_from_file(a[0])
	var hud := Image.load_from_file(a[1])
	# 1. worst case
	var ls: Array = []
	var cols: Array = []
	for y in range(0, scene.get_height(), 2):
		for x in range(0, scene.get_width(), 2):
			var c: Color = scene.get_pixel(x, y)
			ls.append(lum(c))
			cols.append(c)
	var idx: Array = range(ls.size())
	idx.sort_custom(func(i, j): return ls[i] < ls[j])
	var bright: Color = cols[idx[int(idx.size() * 0.995)]]
	var g: Color = bright.lerp(Color(0.05, 0.09, 0.15), 0.20)                       # blur smoke
	g = over(g, Color(0.10, 0.17, 0.27, 0.50))                                      # hud tint, top
	var hud_bg: Color = over(g, Color(0.75, 0.9, 1.0, 0.10))                        # sheen at full
	var g2: Color = over(bright.lerp(Color(0.05, 0.09, 0.15), 0.20), Color(0.08, 0.13, 0.21, 0.66))
	var modal_bg: Color = over(g2, Color(0.75, 0.9, 1.0, 0.10))
	print("brightest scene pixel (p99.5): %s  L=%.3f" % [bright.to_html(false), lum(bright)])
	print("worst case HUD glass (top, full sheen): %s  TEXT %.2f:1  TEXT_2 %.2f:1  TEXT_3 %.2f:1" % [hud_bg.to_html(false), ratio(TEXT, hud_bg), ratio(TEXT_2, hud_bg), ratio(TEXT_3, hud_bg)])
	print("worst case window glass (top, full sheen): %s  TEXT %.2f:1  TEXT_2 %.2f:1  TEXT_3 %.2f:1" % [modal_bg.to_html(false), ratio(TEXT, modal_bg), ratio(TEXT_2, modal_bg), ratio(TEXT_3, modal_bg)])
	# 2. measured
	for k in range(2, a.size()):
		var p: PackedStringArray = a[k].split(",")
		var r := Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
		var l2: Array = []
		var c2: Array = []
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var c: Color = hud.get_pixel(x, y)
				l2.append(lum(c))
				c2.append(c)
		var id2: Array = range(l2.size())
		id2.sort_custom(func(i, j): return l2[i] < l2[j])
		var cut: int = int(id2.size() * 0.85)
		var bg: Color = c2[id2[int(cut * 0.90)]]
		print("rect %s: background p90 %s  TEXT %.2f:1  TEXT_2 %.2f:1  TEXT_3 %.2f:1" % [a[k], bg.to_html(false), ratio(TEXT, bg), ratio(TEXT_2, bg), ratio(TEXT_3, bg)])
	quit(0)
