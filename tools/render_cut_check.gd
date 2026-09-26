extends SceneTree
## RENDER check (Paul, 2026-09-26): with every room's cutaway open, no drawn vertex of a room,
## its doorway kits or its wall patches above 1.45 m, apart from the groups meant to stand
## (world_view.CUT_ALLOWED: Interior, Tall). Every room type of the saves.
##   node tools/godot.mjs script res://tools/render_cut_check.gd [label]
## Writes build/web_render/cut_check_<label>.json; prints one line per room type.
const SAVES := ["res://content/saves/showcase_v3_late.fhsave", "res://content/saves/showcase_v31.fhsave", "res://content/saves/scene_final.fhsave"]
var main
var n := 0
var si := -1
var label := "run"
var res := {}

func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if not s.begins_with("--"):
			label = s
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	if si < 0 or n > 40:
		if si >= 0:
			var r: Dictionary = main.view._cut_check()
			for k in r:
				if not res.has(k):
					res[k] = r[k]
				else:
					res[k]["rooms"] = int(res[k]["rooms"]) + int(r[k]["rooms"])
					for kk in ["above_cut", "allowed"]:
						for g in r[k][kk]:
							res[k][kk][g] = maxf(float(res[k][kk].get(g, 0.0)), float(r[k][kk][g]))
		si += 1
		if si >= SAVES.size():
			_write()
			return true
		main._import_bytes(FileAccess.get_file_as_bytes(SAVES[si]))
		main.set_speed(0)
		main.view._force_open_all = true
		n = 3
		return false
	main.set_process(false)
	main._process(1.0 / 30.0)
	return false

func _write() -> void:
	var keys: Array = res.keys()
	keys.sort()
	var bad := 0
	for k in keys:
		var r: Dictionary = res[k]
		if not (r["above_cut"] as Dictionary).is_empty():
			bad += 1
		print("CUT %-26s rooms %d | above cut: %s | allowed: %s" % [k, int(r["rooms"]), str(r["above_cut"]) if not (r["above_cut"] as Dictionary).is_empty() else "none", str(r["allowed"])])
	print("CUT TOTAL %d room types, %d with a drawn part above 1.45 m" % [keys.size(), bad])
	var f := FileAccess.open("res://build/web_render/cut_check_%s.json" % label, FileAccess.WRITE)
	f.store_string(JSON.stringify({"label": label, "types": keys.size(), "types_above_cut": bad, "rooms": res}, "  "))
	f.close()
	quit(0)
