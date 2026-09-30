extends SceneTree
## RENDER evidence: showcase_v4 with ART-HAB's v5 buildings placed finished (SIM debug command):
## apartment block, residence tubes (family L, executive L), retail, park, academy, security office,
## jail. A few colonists are put in the block (floor from SIM's floors stub) and in the tube.
## Writes build/web_render/civic_v5.fhsave; prints ids, positions, floors.
##   node tools/godot.mjs script res://tools/render_civic_save.gd
var main
var n := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _place(sim, def_id: String, size: int, c: Vector2, r0: float, extra: Dictionary = {}) -> int:
	for ring in [r0, r0 + 25.0, r0 + 50.0, r0 + 80.0, r0 + 120.0]:
		for k in 36:
			var a: float = TAU * float(k) / 36.0 + ring * 0.01
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * ring
			var q := {"def": def_id, "x": p.x, "y": p.y, "size": size}
			q.merge(extra)
			var r: Dictionary = sim.debug.run("place_finished", q)
			if bool(r["ok"]):
				var b: Dictionary = sim.state["buildings"][int(r["id"])]
				for key in extra:
					b[key] = extra[key]
				return int(r["id"])
	return -1

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = main.sim
	sim.state["options"]["debug"] = true
	var c := Vector2(1262, 1290)
	var out := {}
	out["apartment_block"] = _place(sim, "apartment_block", 1, c, 90.0)
	out["residence_family"] = _place(sim, "residence_tube", 2, c, 70.0, {"variant": "family"})
	out["residence_exec"] = _place(sim, "residence_tube", 2, c, 70.0, {"variant": "executive"})
	var r0 := 60.0
	for d in ["retail", "park", "academy", "security_office", "jail"]:
		out[d] = _place(sim, d, 1, c + Vector2(-140.0, 40.0), r0)
		r0 += 30.0
	var line := ""
	for k in out:
		var id: int = out[k]
		if id >= 0:
			var b: Dictionary = sim.state["buildings"][id]
			line += "%s=%d@(%.0f,%.0f) r%.1f; " % [k, id, (b["pos"] as Vector2).x, (b["pos"] as Vector2).y, float(b["radius"])]
		else:
			line += "%s=FAILED; " % k
	print("CIVIC ", line)
	# People: 6 into the block (spread), 3 into the family tube.
	var moved := 0
	for id in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][id]
		if ag["state"] != "alive" or moved >= 9:
			continue
		var tgt: int = out["apartment_block"] if moved < 6 else out["residence_family"]
		if tgt < 0:
			continue
		var b2: Dictionary = sim.state["buildings"][tgt]
		ag["pos"] = (b2["pos"] as Vector2) + Vector2(cos(moved * 1.1), sin(moved * 1.1)) * (4.0 + moved % 3)
		ag["where"] = "in"
		ag["bld"] = tgt
		moved += 1
		var fa: Dictionary = sim.floors.agent_floor(ag)
		print("PERSON ", int(id), " in ", tgt, " floor ", fa)
	var f := FileAccess.open("res://build/web_render/civic_v5.fhsave", FileAccess.WRITE)
	f.store_buffer(sim.save_bytes())
	f.close()
	return true