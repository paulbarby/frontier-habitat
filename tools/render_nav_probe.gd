extends SceneTree
## RENDER debug: wall_r and half of the baked nav grids whose name contains the first argument.
func _init() -> void:
	var pat: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "airlock"
	var d := DirAccess.open("res://presentation/navgrid")
	for f in d.get_files():
		if f.contains(pat) and f.ends_with(".res"):
			var r: Resource = load("res://presentation/navgrid/" + f)
			var g: Dictionary = r.get_meta("nav", {})
			var occ: PackedByteArray = g.get("occ", PackedByteArray())
			var c := [0, 0, 0]
			for v in occ:
				c[mini(v, 2)] += 1
			print("%s wall_r %s half %s n %s free/furn/wall %s" % [f, g.get("wall_r"), g.get("half"), g.get("n"), str(c)])
	quit()
