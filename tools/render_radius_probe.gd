extends SceneTree
## RENDER debug: buildings whose record radius differs from their def's size radius.
var main
var n := 0
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	for save in ["res://content/saves/scene_final.fhsave", "res://content/saves/showcase_v3_late.fhsave"]:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		var sim = main.sim
		var hist := {}
		for bid in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][bid]
			if b["kind"] == "link":
				continue
			var def: Dictionary = sim.bdef(b["def"])
			var sr: float = float(def.get("radius", 0))
			var sz: int = int(b.get("size", 1))
			if def.has("sizes") and (def["sizes"] as Dictionary).has("radius"):
				var arr: Array = def["sizes"]["radius"]
				sr = float(arr[clampi(sz, 0, arr.size() - 1)])
			if absf(sr - float(b["radius"])) > 0.05:
				var k: String = "%s size %d rec %.2f def %.2f" % [b["def"], sz, float(b["radius"]), sr]
				hist[k] = int(hist.get(k, 0)) + 1
		print("%s: %s" % [save.get_file(), str(hist)])
		for bid in sim.state["buildings"]:
			var b: Dictionary = sim.state["buildings"][bid]
			if String(b["def"]) != "airlock" or float(b["radius"]) >= 3.0:
				continue
			var angs: Array = []
			for lid in sim.state["buildings"]:
				var l: Dictionary = sim.state["buildings"][lid]
				if l["kind"] != "link" or l["def"] != "corridor":
					continue
				for end in [["a", "p0"], ["b", "p1"]]:
					if int(l.get(end[0], -1)) == int(bid):
						var dv: Vector2 = (l[end[1]] as Vector2) - (b["pos"] as Vector2)
						angs.append(snappedf(sim.place.model_angle(float(b["rot"]), dv.angle()), 0.5))
			print("  airlock %d r %.2f rot %.3f corridor model angles %s" % [int(bid), float(b["radius"]), float(b["rot"]), str(angs)])
	quit(0)
	return true
