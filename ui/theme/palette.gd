extends RefCounted
## The interface palette (docs/AAA_DESIGN.md §1). Every colour of the interface comes from
## here. A status is never shown by colour alone: the text always says it too.

# Glass panels
const BG := Color(0.043, 0.071, 0.125, 0.86)          # #0B1220 at 86%
const BG_TOP := Color(0.075, 0.118, 0.196, 0.88)      # lighter top of the gradient
const BG_DEEP := Color(0.027, 0.047, 0.086, 0.94)     # wells, chart backgrounds
const BG_SOLID := Color("0B1220")
const HEADER := Color(0.098, 0.157, 0.259, 0.92)      # header strip
const LINE := Color(0.243, 0.878, 1.0, 0.30)          # #3EE0FF at 30%
const LINE_SOFT := Color(0.243, 0.878, 1.0, 0.14)
const LINE_STRONG := Color(0.243, 0.878, 1.0, 0.65)
const GRID := Color(0.62, 0.72, 0.84, 0.10)

# Signal colours
const CYAN := Color("3EE0FF")
const AMBER := Color("FFB547")
const RED := Color("FF5A5F")
const GREEN := Color("5EE07A")
const VIOLET := Color("A78BFA")
const GOLD := Color("FFD166")
const BLUE := Color("4A90D9")

# Text
const TEXT := Color("E6EEF7")
const TEXT_2 := Color("A3B5CA")
const TEXT_3 := Color("6A7F97")
const TEXT_DARK := Color("06101C")

const CATEGORY := {
	"life_support": Color("29B6C6"), "food": Color("6ABF4B"), "housing": Color("F2C14E"),
	"industry": Color("E07A3A"), "logistics": Color("9B6BD6"), "utilities": Color("4A90D9"),
	"medical": Color("E85D75"), "comfort": Color("F08FC0"), "science": Color("7C8CFF"),
	"space": Color("C9D3E0"),
}
const CATEGORY_NAME := {
	"life_support": "Life support", "food": "Food", "housing": "Housing", "industry": "Industry",
	"logistics": "Logistics", "utilities": "Power", "medical": "Medical", "comfort": "Comfort",
	"science": "Science", "space": "Space",
}
const ROLE := {
	"technician": Color("FF9F1C"), "grower": Color("5AC85A"), "operator": Color("4A90D9"),
	"medic": Color("E85D75"), "scientist": Color("A78BFA"),
}
const TIER := {
	"bronze": Color("CD8B5A"), "silver": Color("C9D3E0"), "gold": Color("FFD166"), "platinum": Color("9FF3FF"),
}
const NUTRIENT := {
	"protein": Color("F2795C"), "carbs": Color("F2C14E"), "fat": Color("FF9F43"), "vitamins": Color("6FE08A"),
}
const NUTRIENT_NAME := {"protein": "Protein", "carbs": "Carbs", "fat": "Fat", "vitamins": "Vitamins"}

## Severity 0..3 (sim alerts). 3 = critical.
static func sev(level: int) -> Color:
	match level:
		3: return RED
		2: return AMBER
	return CYAN

static func sev_word(level: int) -> String:
	match level:
		3: return "CRITICAL"
		2: return "WARNING"
	return "NOTICE"

static func sev_icon(level: int) -> String:
	match level:
		3: return "sev_critical"
		2: return "sev_warning"
	return "sev_info"

static func cat(category: String) -> Color:
	return CATEGORY.get(category, Color("B0B6BE"))

## Good/bad colour for a 0..100 value where high is good.
static func level(v: float, warn: float = 50.0, bad: float = 25.0) -> Color:
	if v < bad:
		return RED
	if v < warn:
		return AMBER
	return GREEN

static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Opaque colour of `top` at `a` over the panel colour (for crisp strokes on glass).
static func over_panel(top: Color, a: float) -> Color:
	var base := Color(0.055, 0.086, 0.145)
	return Color(base.r + (top.r - base.r) * a, base.g + (top.g - base.g) * a, base.b + (top.b - base.b) * a, 1.0)
