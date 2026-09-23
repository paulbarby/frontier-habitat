extends SceneTree
## Developer tool: nutrition and alerts in a save file.
##   node tools/godot.mjs script res://tests/dev/save_nutrition.gd res://content/saves/showcase_late.fhsave
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://content/saves/showcase_late.fhsave"
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	sim.run_seconds(2.0)
	var col: Dictionary = sim.nutrition.colony()
	var n_def := 0
	var n_fed := 0
	for aid in sim.state["agents"]:
		var a: Dictionary = sim.state["agents"][aid]
		if a["state"] == "alive":
			n_def += 1 if not sim.nutrition.deficient(a).is_empty() else 0
			n_fed += 1 if sim.nutrition.well_fed(a) else 0
	print("%s: score %.1f P%.0f C%.0f F%.0f V%.0f, %d deficient, %d well fed, %d alive" % [path.get_file(), float(col["score"]), float(col["protein"]), float(col["carbs"]), float(col["fat"]), float(col["vitamins"]), n_def, n_fed, int(col["people"])])
	for k in sim.state["issues"]:
		var i: Dictionary = sim.state["issues"][k]
		print("  alert sev %d: %s" % [int(i["severity"]), String(i["text"]).left(110)])
	quit(0)
