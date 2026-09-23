extends Control
## A medal: ribbon, rim and face in the tier colour (bronze, silver, gold, platinum), with
## the award's glyph in the centre. `earned` false draws a dim locked medal.
## `shine` 0..1 sweeps a highlight across the face (the pop-up animates it).

const P = preload("res://ui/theme/palette.gd")
const Icons = preload("res://ui/theme/icons.gd")

var tier := "bronze"
var earned := true
var glyph := "star"
var shine := -1.0
var spin := 0.0

const GLYPHS := {
	"first_breath": "o2", "green_thumb": "cat_food", "home_cook": "food", "iron_will": "metal", "eureka": "research",
	"tinkerer": "upgrade", "night_owl": "moon", "explorer": "ship", "hoarder": "inventory", "a_dozen": "people",
	"gourmet": "colony_feast", "balanced": "nutrition", "scholar": "flask", "architect": "build", "megastructure": "size",
	"grid_master": "power", "lifesaver": "heart", "happy_colony": "morale", "industrialist": "cat_industry", "survivor": "sev_ok",
	"twenty_strong": "colonists", "master_chef": "colony_feast", "polymath": "research", "pinnacle": "level", "ship_shape": "rocket_fuel",
	"full_supply": "check", "well_oiled": "settings", "zero_casualties": "heart", "tycoon": "trophy", "liftoff": "ship",
	"centurion": "people", "frontier": "planet",
}

static func glyph_for(id: String) -> String:
	return GLYPHS.get(id, "star")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var s: float = minf(size.x, size.y / 1.25)
	var c := Vector2(size.x * 0.5, size.y - s * 0.52)
	var r: float = s * 0.42
	var col: Color = P.TIER.get(tier, P.GOLD)
	if not earned:
		col = Color(0.32, 0.37, 0.44).lerp(col, 0.22)
	# Ribbon: two tails behind the medal.
	var rt: float = c.y - r * 0.4
	var rib_a: Color = col.darkened(0.35) if earned else Color(0.2, 0.24, 0.3)
	var rib_b: Color = P.CYAN.darkened(0.3) if earned else Color(0.16, 0.2, 0.26)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.72, rt - r * 1.1), Vector2(c.x - r * 0.18, rt - r * 1.1), Vector2(c.x + r * 0.1, rt), Vector2(c.x - r * 0.42, rt)]), rib_a)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x + r * 0.18, rt - r * 1.1), Vector2(c.x + r * 0.72, rt - r * 1.1), Vector2(c.x + r * 0.42, rt), Vector2(c.x - r * 0.1, rt)]), rib_b)
	# Glow behind an earned medal.
	if earned:
		for i in 4:
			draw_circle(c, r * (1.0 + 0.1 * float(i + 1)), Color(col.r, col.g, col.b, 0.07))
	# Rim with notches, then the face.
	var rim := PackedVector2Array()
	var n := 48
	for i in n:
		var a: float = TAU * float(i) / float(n) + spin
		var rr: float = r * (1.0 if i % 2 == 0 else 0.93)
		rim.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(rim, col.darkened(0.2))
	draw_circle(c, r * 0.84, col.darkened(0.45) if earned else Color(0.14, 0.17, 0.22))
	draw_circle(c, r * 0.78, col if earned else Color(0.22, 0.26, 0.32))
	draw_circle(c + Vector2(-r * 0.2, -r * 0.22), r * 0.5, Color(1, 1, 1, 0.12 if earned else 0.04))
	draw_arc(c, r * 0.68, 0.0, TAU, 40, Color(1, 1, 1, 0.25 if earned else 0.08), maxf(1.0, r * 0.03), true)
	# Glyph
	var gs: float = r * 0.9
	var tex: Texture2D = Icons.tex(glyph if earned else "lock", int(maxf(16.0, gs)))
	draw_texture_rect(tex, Rect2(c - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(0.08, 0.06, 0.03, 0.85) if earned else Color(0.45, 0.5, 0.58))
	# Shine sweep
	if shine >= 0.0 and shine <= 1.0 and earned:
		var x: float = lerpf(c.x - r * 1.2, c.x + r * 1.2, shine)
		for k in 6:
			var w: float = r * 0.08 * float(6 - k)
			var pts := PackedVector2Array()
			for i in 16:
				var a: float = TAU * float(i) / 16.0
				var p: Vector2 = c + Vector2(cos(a), sin(a)) * r * 0.78
				pts.append(p)
			var band := PackedVector2Array([Vector2(x - w, c.y - r), Vector2(x + w, c.y - r), Vector2(x + w - r * 0.4, c.y + r), Vector2(x - w - r * 0.4, c.y + r)])
			var clip: Array = Geometry2D.intersect_polygons(pts, band)
			for poly in clip:
				draw_colored_polygon(poly, Color(1, 1, 1, 0.06))
