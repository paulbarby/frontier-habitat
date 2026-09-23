extends SceneTree
## Plays the reference layout and writes the deliverable save file.
##   godot --headless --path . --script res://tests/make_reference_save.gd -- [seed] [days]
## Output: res://saves/reference_day<N>.fhsave  (load it in the game with Menu > Import save file)

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var days: float = float(args[1]) if args.size() > 1 else 3.1
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	for s in int(days * 600):
		ref.drive()
		sim.run_seconds(1.0)
	var bytes: PackedByteArray = sim.save_bytes()
	var check: Dictionary = Persistence.decode(bytes)
	var path := "res://saves/reference_day%d.fhsave" % sim.util.day_number()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var f2: Dictionary = sim.metrics.forecast()
	print("wrote %s: %d bytes, decodes %s, tick %d, %d colonists alive, %d deaths, meals %d, audit %s" % [
		ProjectSettings.globalize_path(path), bytes.size(), check["ok"], sim.state["tick"], f2["pop"], sim.state["progress"]["deaths"], f2["meals"], sim.inv.audit()])
	quit(0)
