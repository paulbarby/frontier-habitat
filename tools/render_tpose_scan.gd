extends SceneTree
## RENDER (debug, 2026-10-03): frames of every clip of every body library where the arms stand out straight
## (both hands within 0.15 m of shoulder height and over 0.55 m out from the spine): a T / bind pose in a clip.
const Npc = preload("res://presentation/fx_npc.gd")
var main
var f := 0
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		return false
	if f < 200:
		return false
	var hits := 0
	for k in main.view.npc.libs:
		var lib: Dictionary = main.view.npc.libs[k]
		if not bool(lib.get("ok", false)) or bool(lib.get("shared", false)) and String(k).ends_with("_lod1"):
			continue
		var names: Array = lib["names"]
		var ids := {}
		for bn in ["hand.L", "hand.R", "upper_arm.L", "upper_arm.R", "spine", "spine.003", "neck"]:
			ids[bn] = names.find(bn)
		if int(ids["hand.L"]) < 0 or int(ids["hand.R"]) < 0:
			print(k, ": no hand bones; names ", names.slice(0, 12))
			continue
		var sp: int = int(ids["spine.003"]) if int(ids["spine.003"]) >= 0 else int(ids["spine"])
		var ua: int = int(ids["upper_arm.L"])
		for c in (lib["clips"] as Dictionary):
			var d: Dictionary = lib["clips"][c]
			var bad: Array = []
			for fr in range(0, int(d["frames"]) + 1, 2):
				var row: int = int(d["row0"]) + fr
				var hl: Vector3 = Npc.bone_at(lib, row, int(ids["hand.L"])).origin
				var hr: Vector3 = Npc.bone_at(lib, row, int(ids["hand.R"])).origin
				var s: Vector3 = Npc.bone_at(lib, row, ua).origin if ua >= 0 else Npc.bone_at(lib, row, sp).origin
				var cy: float = s.y
				var mid: Vector3 = Npc.bone_at(lib, row, sp).origin if sp >= 0 else Vector3.ZERO
				if absf(hl.y - cy) < 0.15 and absf(hr.y - cy) < 0.15 and Vector2(hl.x - mid.x, hl.z - mid.z).length() > 0.55 and Vector2(hr.x - mid.x, hr.z - mid.z).length() > 0.55:
					bad.append(fr)
			if not bad.is_empty():
				hits += 1
				print("%-10s %-18s frames %d..%d of %d (%d frames)" % [k, c, int(bad[0]), int(bad[-1]), int(d["frames"]), bad.size()])
	print("TPOSE SCAN: %d clip(s) with straight-out arms" % hits)
	return true
