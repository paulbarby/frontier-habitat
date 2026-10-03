extends SceneTree
## Critic r42 verify (PT-14), part 2: read only. Lists non-active structures in the v4 showcase
## save that make_showcase_v5.gd starts from, to see where Habitat 8 and Corridors 19/20 come from.

const Persistence = preload("res://sim/persistence.gd")

func _initialize() -> void:
	for path in ["res://content/saves/showcase_v4.fhsave"]:
		var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))
		if not dec.get("ok", false):
			print("%s decode failed" % path)
			continue
		var st: Dictionary = dec["state"]
		print("%s tick=%d day=%.2f buildings=%d" % [path, int(st["tick"]), float(int(st["tick"])) / 6000.0, (st["buildings"] as Dictionary).size()])
		for id in st["buildings"]:
			var b: Dictionary = st["buildings"][id]
			if b["state"] != "active":
				print("  id=%d name='%s' def=%s state=%s block='%s' pos=(%.0f,%.0f)" % [int(id), String(b.get("name", "?")), String(b.get("def", "?")), String(b["state"]), String(b.get("block", "")), b.get("pos", Vector2()).x, b.get("pos", Vector2()).y])
			elif int(id) == 2197 or int(id) == 2238 or int(id) == 2240:
				print("  (active) id=%d name='%s'" % [int(id), String(b.get("name", "?"))])
	quit(0)
