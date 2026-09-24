extends SceneTree
## RENDER: checks CPU-blended poses for NaN / zero-scale bones (a body drawn from such a row
## is invisible). Walk/run blends with and without the carry layer, both variants.
##   node tools/godot.mjs script res://tools/render_pose_nan.gd

const Npc = preload("res://presentation/fx_npc.gd")

func _init() -> void:
	var bad := 0
	var total := 0
	for v in ["suit", "in"]:
		var lib: Dictionary = Npc.load_lib(v)
		if not bool(lib.get("ok", false)):
			continue
		for wb in [0.0, 0.05, 0.5, 0.95]:
			for wc in [0.0, 0.5, 1.0]:
				for t in [0.0, 0.1, 0.3, 0.5]:
					var pz := {"a": "walk", "ta": t, "b": "run" if wb > 0.0 else "", "tb": t * 0.6, "wb": wb, "c": "carry_walk" if wc > 0.0 else "", "tc": t, "wc": wc}
					var g: Array = Npc.pose_globals(lib, pz)
					total += 1
					var why := ""
					for bi in g.size():
						var x: Transform3D = g[bi]
						if is_nan(x.origin.x) or is_nan(x.basis.x.x) or is_nan(x.basis.y.y):
							why = "NaN at bone %d" % bi
							break
						if absf(x.basis.determinant()) < 0.01:
							why = "zero scale at bone %d" % bi
							break
					if why != "":
						bad += 1
						if bad <= 12:
							print("%s wb=%.2f wc=%.1f t=%.1f: %s" % [v, wb, wc, t, why])
	print("render_pose_nan: %d of %d poses bad" % [bad, total])
	quit()
