extends SceneTree
## SIM probe: dead agents in a save (who, cause, when, where).
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	for path in (a if not a.is_empty() else ["res://content/saves/showcase_v4.fhsave", "res://content/saves/showcase_v5.fhsave"]):
		var st: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(path))["state"]
		print("%s: tick %d" % [path, int(st["tick"])])
		for id in st["agents"]:
			var ag: Dictionary = st["agents"][id]
			if ag["state"] == "dead":
				for bid in st["buildings"]:
					var b: Dictionary = st["buildings"][bid]
					if b["kind"] != "link" and (b["pos"] as Vector2).distance_to(ag["pos"]) < float(b["radius"]) + 8.0:
						print("    near %s %s r %.1f d %.1f created %d" % [b["def"], str(b["pos"]), float(b["radius"]), (b["pos"] as Vector2).distance_to(ag["pos"]), int(b["created"])])
				print("  %d %s role %s kind %s cause %s death_tick %s where %s bld %s pos %s born %s" % [int(id), ag["name"], ag["role"], ag.get("kind", ""), ag.get("cause", ""), str(ag.get("death_tick", "?")), ag["where"], str(ag["bld"]), str(ag["pos"]), str(ag.get("born", 0))])
		for e in st["log"]:
			if String(e["code"]) == "death":
				print("  log %d: %s" % [int(e["tick"]), e["text"]])
	quit(0)
