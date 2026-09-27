extends SceneTree
## RENDER check: every building def in content has a model file the view can draw (per size),
## and the model's wall ring against the content radius (rooms).
##   node tools/godot.mjs script res://tools/render_defs_probe.gd
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	var b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/buildings.json"))
	var missing := []
	var odd := []
	var n := 0
	for id in b:
		if String(id).begins_with("_"):
			continue
		var d: Dictionary = b[id]
		if String(d.get("kind", "")) == "link":
			continue
		var sizes: Array = [-1]
		if d.has("sizes"):
			sizes = d.get("size_list", [0, 1, 2, 3])
		for s in sizes:
			n += 1
			var r: Dictionary = Models.resolve(id, int(s))
			if String(r["path"]) == "":
				missing.append("%s/%d" % [id, int(s)])
				continue
			if String(d.get("kind", "")) == "room":
				var tpl: Dictionary = Models._template_from_file(r["path"])
				var wr := 0.0
				for p in tpl["parts"]:
					wr = maxf(wr, float(p.get("wall_r", 0.0)))
				var cr: float = float(d.get("radius", 3.0))
				if int(s) >= 0 and d.has("sizes") and (d["sizes"] as Dictionary).has("radius"):
					cr = float(d["sizes"]["radius"][int(s)])
				if wr > 0.0 and absf(wr / cr - 0.97) > 0.08:
					odd.append("%s/%d wall %.2f content %.2f" % [id, int(s), wr, cr])
	print("DEFS %d def-sizes, %d without a model: %s" % [n, missing.size(), str(missing)])
	print("DEFS rooms whose wall ring is off the content radius: %s" % str(odd))
	quit()
