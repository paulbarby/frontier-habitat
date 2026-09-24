extends SceneTree
## RENDER: checks the crate attachment (ART-NPC round 3). In carry_idle frame 0,
## prop.R (global) x carry.prop_R_offset must give the crate bottom centre
## (0.418, 0.802, 0.000) with a basis near identity.
##   node tools/godot.mjs script res://tools/render_crate_check.gd

const Npc = preload("res://presentation/fx_npc.gd")

func _init() -> void:
	for v in ["suit", "in"]:
		var lib: Dictionary = Npc.load_lib(v)
		if not bool(lib.get("ok", false)):
			print("%s: not loaded (%s)" % [v, lib.get("status", "")])
			continue
		var pr: int = int(lib["prop_r"])
		var d: Dictionary = lib["clips"].get("carry_idle", {})
		if pr < 0 or d.is_empty() or lib.get("crate_offset") == null:
			print("%s: prop_r %d, carry_idle %s, offset %s" % [v, pr, str(not d.is_empty()), str(lib.get("crate_offset"))])
			continue
		var g: Transform3D = Npc.bone_at(lib, int(d["row0"]), pr) * (lib["crate_offset"] as Transform3D)
		var q := Quaternion(g.basis.orthonormalized())
		var ang: float = rad_to_deg(q.get_angle())
		var err: float = g.origin.distance_to(Vector3(0.418, 0.802, 0.0))
		print("%s: crate origin %s (error %.3f m), basis %.1f deg from identity -> %s" % [v, str(g.origin.snappedf(0.001)), err, ang, "PASS" if err < 0.03 and ang < 8.0 else "FAIL"])
	quit()
