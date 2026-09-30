extends SceneTree
## Probe (UI agent, 2026-10-01): the v5 data in showcase_v5 for the UI tests and shots.
##   node tools/godot.mjs script res://tools/ui/ui_probe_v5.gd [save]
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		var a: PackedStringArray = OS.get_cmdline_user_args()
		var t0 := Time.get_ticks_msec()
		main._import_bytes(FileAccess.get_file_as_bytes(a[0] if a.size() > 0 else "res://content/saves/showcase_v5.fhsave"))
		print("import ms ", Time.get_ticks_msec() - t0)
		main._on_cmd("speed 0")
	if _n == 12:
		var s = main.sim
		var v5 = main.hud.v5
		print("people ", v5.people().size())
		var kinds := {}
		for r in v5.people():
			kinds[String(r["kind"])] = int(kinds.get(String(r["kind"]), 0)) + 1
		print("kinds ", kinds)
		for pr in s.relations.pairs_with(["partners", "married", "dating", "affair"]):
			print("pair ", pr)
		var kids := 0
		for aid in s.state["agents"]:
			var ag: Dictionary = s.state["agents"][aid]
			if ag["state"] == "alive" and String(ag.get("kind", "")) == "child":
				kids += 1
				if kids <= 3:
					print("child ", aid, " ", ag["name"], " parents ", ag.get("parents", []), " school ", s.state.get("v5", {}).get("school", {}).get(aid, {}))
		print("children ", kids)
		print("security ", s.security.info(-1), " fights ", s.security.fights().size())
		for j in s.security.jails(-1):
			print("jail ", j, " prisoners ", s.security.prisoners_in(j))
		for bid in s.state["buildings"]:
			var b: Dictionary = s.state["buildings"][bid]
			if String(b["def"]) in ["super_dome", "retail", "park", "academy", "jail", "security_office"]:
				print("bld ", b["def"], " ", bid, " ", b["state"], " stage ", s.leisure.dome_stage(b))
				if String(b["def"]) == "academy":
					print("  students ", s.education.students(int(bid)), " seated ", s.education.seated(int(bid)) if s.education.has_method("seated") else "-")
				if String(b["def"]) == "super_dome":
					var op := 0
					for v in s.leisure.venues(b):
						op += 1 if v["open"] else 0
					print("  venues ", s.leisure.venues(b).size(), " open ", op, " first ", str(s.leisure.venues(b)[0]).left(300))
		print("unrest ", s.unrest.info(-1).keys(), " lock ", s.unrest.lock_info(-1) if s.unrest.has_method("lock_info") else "-")
		print("requests ", s.relations.requests())
		print("ledger keys ", (s.state.get("ledger", {}) as Dictionary).keys())
		print("credits ", main.hud.data.credits())
		print("bases ", s.bases.ids())
		quit(0)
		return true
	return false
