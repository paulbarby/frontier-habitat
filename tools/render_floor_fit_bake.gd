extends SceneTree
## RENDER: bakes the raised floor plates of multi-storey buildings (the super dome's fit-out floors stand 12-17 mm over
## the level top in rings and venues; people walked 12 mm into them, ground check 2026-10-03) into
## presentation/navgrid/floor_fit.res. Per template key and level: a grid of 0.5 m cells in model space, each the
## drawn floor's height over the level top in mm (0..45; furniture, holes and stairs read 0 = no change). Rays down
## against the physics shapes of every structure copy (fx_cam_phys).
##   node tools/godot.mjs script res://tools/render_floor_fit_bake.gd [save=res://content/saves/showcase_v5.fhsave]
const CamPhys = preload("res://presentation/fx_cam_phys.gd")
const Models = preload("res://presentation/models.gd")
const Npc = preload("res://presentation/fx_npc.gd")
const OUT := "res://presentation/navgrid/floor_fit.res"
const CELL := 0.5
var main
var f := 0
var save := "res://content/saves/showcase_v5.fhsave"
var cp

func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if s.begins_with("save="):
			save = s.substr(5)
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes(save))
		return false
	if f < 200:
		return false
	if cp == null:
		cp = CamPhys.new(main.view.inst, main.view.get_world_3d())
		cp.sync_all()
		return false
	if f < 203:
		return false
	var fit := {}
	if ResourceLoader.exists(OUT):
		var old = load(OUT)
		if old is Resource and (old as Resource).has_meta("fit"):
			fit = (old as Resource).get_meta("fit")
	for bid in main.sim.state["buildings"]:
		var b: Dictionary = main.sim.state["buildings"][bid]
		var nf: int = int(main.sim.bdef(b["def"]).get("floors", 1))
		if nf <= 1 or not main.view.bmeta.has(bid):
			continue
		var meta: Dictionary = main.view.bmeta[bid]
		var tpl: Dictionary = meta.get("tpl", {})
		var key: String = String(tpl.get("key", ""))
		var tops: Array = Npc._floor_tops(meta, nf)
		if key == "" or tops.is_empty():
			continue
		var xf: Transform3D = meta["xf"]
		var xs := Transform3D(xf.basis * Basis.from_scale(Models.scale3(tpl)), xf.origin)
		var sc: Vector3 = Models.scale3(tpl)
		var rad: float = float(b["radius"]) / maxf(sc.x, 0.001)
		var n: int = int(ceil(rad / CELL)) * 2 + 1
		var levels: Array = []
		var t0: int = Time.get_ticks_msec()
		var stats: Array = []
		for li in tops.size():
			var top: float = float(tops[li])
			var ly: float = xf.origin.y + top * sc.y
			var g := PackedByteArray()
			g.resize(n * n)
			var hist := {}
			for iz in n:
				for ix in n:
					var mx: float = (ix - (n - 1) / 2) * CELL
					var mz: float = (iz - (n - 1) / 2) * CELL
					var v := 0
					if Vector2(mx, mz).length() <= rad:
						var w: Vector3 = xs * Vector3(mx, top, mz)
						var a := Vector3(w.x, ly + 0.30, w.z)
						var d: float = cp.ray(a, Vector3(w.x, ly - 0.10, w.z))
						if d != INF:
							var off: float = (a.y - d) - ly
							if off >= 0.004 and off <= 0.045:
								v = int(round(off * 1000.0))
					g[iz * n + ix] = v
					if v > 0:
						hist[v] = int(hist.get(v, 0)) + 1
			levels.append(g)
			stats.append("L%d %s" % [li, str(hist)])
		fit[key] = {"cell": CELL, "n": n, "levels": levels, "tops": tops.duplicate()}
		print("floor fit %s (%s, %d levels, %d x %d cells, %d ms): %s" % [key, b["def"], tops.size(), n, n, Time.get_ticks_msec() - t0, " | ".join(stats)])
	var r := Resource.new()
	r.set_meta("fit", fit)
	var err: int = ResourceSaver.save(r, OUT)
	print("saved %s (%d templates) err %d" % [OUT, fit.size(), err])
	return true
