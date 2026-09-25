extends SceneTree
## Prints facts about a save: day, structures of given defs (id, state, pos).
##   node tools/godot.mjs script res://tools/ui/save_info.gd res://content/saves/showcase_v3_late.fhsave landing_pad

const Persistence = preload("res://sim/persistence.gd")
const Sim = preload("res://sim/sim.gd")

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var res: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(a[0]))
	if not res["ok"]:
		print("load failed: ", res.get("error", ""))
		quit(1)
		return
	var sim = Sim.new()
	sim.load_state(res["state"])
	print("day %d, map %d m, credits %s" % [sim.util.day_number(), int(sim.world.size), str(sim.state.get("credits", {}))])
	for i in range(1, a.size()):
		for id in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][id]
			if String(b["def"]) == a[i]:
				print("%s %d %s pos=%s powered=%s" % [a[i], id, b["state"], str(b["pos"]), str(b.get("powered", ""))])
	quit()
