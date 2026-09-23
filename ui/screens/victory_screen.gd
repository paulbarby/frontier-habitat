extends "res://ui/screens/screen.gd"
## Victory: every chapter is complete. The numbers of the colony, then keep playing.

const Profile = preload("res://ui/profile.gd")
const Medal = preload("res://ui/widgets/medal.gd")

func _init() -> void:
	pauses = true
	icon = "trophy"
	accent = P.GOLD
	title = "Victory"
	margins = Vector4(220, 70, 220, 70)

func build() -> void:
	var d = hud.data
	var s = hud.main.sim
	var vd: Dictionary = d.victory_def()
	set_subtitle("Every chapter of the mission is complete.")
	var hero: VBoxContainer = Kit.vbox(4)
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(hero)
	var m = Medal.new()
	m.tier = "gold"
	m.glyph = "planet"
	m.custom_minimum_size = Vector2(120, 140)
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hero.add_child(m)
	var t: Label = Kit.label(String(vd.get("name", "Frontier established")).to_upper(), "DisplayLabel", 48, P.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(t)
	var sub: Label = Kit.wrap(String(vd.get("desc", "")), 16, P.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(sub)
	var g: GridContainer = Kit.grid(4, 12, 12)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(g)
	var produced := 0
	for k in d.stats().get("produced", {}):
		produced += int(d.stats()["produced"][k])
	var stats := [
		["calendar", "Days", "%d" % s.util.day_number()], ["people", "Colonists", "%d" % s.alive_count()],
		["build", "Structures", "%d" % s.state["buildings"].size()], ["research", "Research done", "%d" % d.research().get("done", {}).size()],
		["medal", "Awards", "%d of %d" % [d.awards_state().size(), d.awards_def().size()]], ["cat_industry", "Items made", Kit.fmt(float(produced))],
		["sev_critical", "Deaths", "%d" % int(s.state["progress"].get("deaths", 0))], ["ship", "Supply runs", "%d" % int(d.ship().get("runs", 0))],
	]
	for st in stats:
		var p: PanelContainer = Kit.panel("CardPanel", false)
		p.custom_minimum_size = Vector2(190, 76)
		var v: VBoxContainer = Kit.vbox(2)
		p.add_child(v)
		var h: HBoxContainer = Kit.hbox(6)
		h.add_child(Kit.icon(st[0], 16, P.GOLD))
		h.add_child(Kit.head(st[1], P.TEXT_2, 11))
		v.add_child(h)
		v.add_child(Kit.num(st[2], 24, P.TEXT, true))
		g.add_child(p)
	content.add_child(Kit.spacer())
	var btns: HBoxContainer = Kit.hbox(10, BoxContainer.ALIGNMENT_CENTER)
	content.add_child(btns)
	btns.add_child(Kit.button("Awards", func(): hud.open_screen("awards"), "", "", "medal", 16))
	btns.add_child(Kit.button("Save", func(): hud.open_screen("saveload", "save"), "", "", "save", 16))
	var keep: Button = Kit.button("Keep playing", func(): host.close(self), "The colony goes on. Goals are complete; awards can still be earned.", "PrimaryButton", "play", 16)
	keep.custom_minimum_size = Vector2(220, 44)
	btns.add_child(keep)
