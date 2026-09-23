extends SceneTree
## Plays the reference campaign and writes the showcase saves for the title screen and
## the screenshots (docs/AAA_DESIGN.md, SIM item 11):
##   content/saves/showcase_early.fhsave   about day 3: the base has its own air
##   content/saves/showcase_mid.fhsave     about day 12: research lab, industry, several
##                                         dishes, a level-3 structure, an L or XL structure
##   content/saves/showcase_late.fhsave    the Meridian under repair (or flown)
##   node tools/godot.mjs script res://tests/make_showcase_saves.gd [seed] [late_day_max]
## Each file is written to a temporary name, checked by decoding it, then renamed.

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var late_max: float = float(args[1]) if args.size() > 1 else 34.0
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	var wrote := {}
	var s := 0
	while true:
		ref.drive()
		sim.run_seconds(1.0)
		s += 1
		var day: float = sim.util.days_elapsed() + 1.0
		if not wrote.has("early") and day >= 3.35 and (_calm(sim) or day >= 4.0):
			wrote["early"] = _write(sim, "showcase_early")
		if not wrote.has("mid") and day >= 12.0 and _mid_ready(sim):
			wrote["mid"] = _write(sim, "showcase_mid")
		if not wrote.has("mid") and day >= 16.0:
			wrote["mid"] = _write(sim, "showcase_mid")
		var stage: int = int(sim.state["ship"]["stage"])
		if not wrote.has("late") and ((stage >= 2 and day >= 18.0 and _calm(sim)) or day >= late_max):
			wrote["late"] = _write(sim, "showcase_late")
		if wrote.size() >= 3:
			break
	print("audit: ", sim.inv.audit())
	quit(0)

## The mid save wants every feature of the middle game on screen.
func _mid_ready(sim) -> bool:
	var labs := false
	var industry := false
	var l3 := false
	var big := false
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["state"] != "active":
			continue
		labs = labs or b["def"] == "research_lab"
		industry = industry or b["def"] in ["glassworks", "electronics_fab", "fabricator", "regolith_harvester"]
		l3 = l3 or int(b.get("level", 1)) >= 3
		big = big or (int(b.get("size", 1)) >= 2 and sim.bdef(b["def"]).has("sizes"))
	var dishes: int = (sim.state["stats"].get("cooked", {}) as Dictionary).size()
	return labs and industry and l3 and big and dishes >= 3 and _calm(sim)

## No critical alert (severity 3) at this moment: a showcase must not open on an emergency.
static func _calm(sim) -> bool:
	for k in sim.state["issues"]:
		if int(sim.state["issues"][k]["severity"]) >= 3:
			return false
	return true

func _write(sim, name: String) -> bool:
	var bytes: PackedByteArray = sim.save_bytes()
	var path := "res://content/saves/%s.fhsave" % name
	var tmp := "res://content/saves/%s.tmp.fhsave" % name
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		print("FAILED to write ", tmp)
		return false
	f.store_buffer(bytes)
	f.close()
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(tmp))
	if not dec["ok"]:
		print("FAILED to verify ", tmp, ": ", dec["error"])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	var final_abs: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(final_abs)
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), final_abs)
	var f2: Dictionary = sim.metrics.forecast()
	var lv := 1
	var big := 1
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		lv = maxi(lv, int(b.get("level", 1)))
		if sim.bdef(b["def"]).has("sizes"):
			big = maxi(big, int(b.get("size", 1)))
	print("wrote %s: day %.2f, %d bytes, %d alive, %d deaths, %d structures, chapter %d, techs %d, dishes cooked %s, max level %d, max size %d, ship stage %d, audit %s" % [
		final_abs, sim.util.days_elapsed() + 1.0, bytes.size(), f2["pop"], int(sim.state["progress"]["deaths"]),
		sim.state["buildings"].size(), sim.goals.chapter() + 1, sim.research.done_count(),
		str((sim.state["stats"].get("cooked", {}) as Dictionary).keys()), lv, big, int(sim.state["ship"]["stage"]), str(sim.inv.audit())])
	return true
