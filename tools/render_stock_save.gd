extends SceneTree
## RENDER evidence: showcase_v4 with its storehouse (and cold storage) empty, half and full.
## Writes build/web_render/stock_{empty,half,full}.fhsave and prints the Stock split of the models.
##   node tools/godot.mjs script res://tools/render_stock_save.gd
const Models = preload("res://presentation/models.gd")
var main
var n := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	for f in ["storehouse_s", "storehouse_m", "storehouse_l", "storehouse_xl", "cold_storage_s", "cold_storage_m", "cold_storage_l", "cold_storage_xl"]:
		var tpl: Dictionary = Models._template_from_file("res://assets/models/%s.glb" % f)
		var line := ""
		for p in tpl["parts"]:
			if p["group"] in ["Stock", "Interior"]:
				var vc := 0
				for s in (p["mesh"] as Mesh).get_surface_count():
					vc += ((p["mesh"] as Mesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				line += " %s: %d surfaces %d verts%s |" % [p["group"], (p["mesh"] as Mesh).get_surface_count(), vc, (" crates %d" % int(p.get("stock_n", 0))) if p["group"] == "Stock" else ""]
		print("STOCK ", f, line)
	for mode in ["empty", "half", "full"]:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
		var sim = main.sim
		sim.state["options"]["debug"] = true
		# showcase_v4 has no cold storage: one placed finished (size M) near the first storehouse.
		var cold_id := -1
		for k in 40:
			var a: float = float(k) * 0.7
			var pp: Vector2 = Vector2(1322, 1260) + Vector2(cos(a), sin(a)) * (26.0 + k * 1.5)
			var r: Dictionary = sim.debug.run("place_finished", {"def": "cold_storage", "x": pp.x, "y": pp.y, "size": 1})
			if bool(r["ok"]):
				cold_id = int(r["id"])
				break
		var ids := []
		for b in sim.state["buildings"].values():
			if String(b["def"]) in ["storehouse", "cold_storage"] and int(b.get("inv_out", -1)) >= 0:
				var inv: Dictionary = sim.inv.get_inv(int(b["inv_out"]))
				var cap: int = int(inv["cap"])
				inv["items"] = {}
				var want: int = {"empty": 0, "half": cap / 2, "full": cap}[mode]
				if want > 0:
					inv["items"] = {"metal": want / 2, "polymer": want - want / 2} if b["def"] == "storehouse" else {"food": want}
				ids.append([int(b["id"]), String(b["def"]), b["pos"], cap])
		var fa := FileAccess.open("res://build/web_render/stock_%s.fhsave" % mode, FileAccess.WRITE)
		fa.store_buffer(sim.save_bytes())
		fa.close()
		print("SAVE ", mode, " cold ", cold_id, " ", ids)
	return true
