extends SceneTree
## RENDER evidence: showcase_v4 with a finished super dome (SIM's place_finished, debug) and 30 people
## moved inside it (evidence only: their positions are set in the save, SIM keeps them where they
## can walk). Also writes a save per build stage (the dome as a "building" at 9 progress points).
## Writes build/web_render/dome_v5.fhsave and dome_stage_<k>.fhsave; prints the dome id and position.
##   node tools/godot.mjs script res://tools/render_dome_save.gd
var main
var n := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	var ua: PackedStringArray = OS.get_cmdline_user_args()
	var src: String = ua[0] if ua.size() > 0 else "res://content/saves/showcase_v4.fhsave"
	var tag: String = ua[1] if ua.size() > 1 else "v5"
	main._import_bytes(FileAccess.get_file_as_bytes(src))
	var sim = main.sim
	sim.state["options"]["debug"] = true
	var c: Vector2 = Vector2(1262, 1290)
	var cn := 0
	var cs := Vector2.ZERO
	for bb in sim.state["buildings"].values():
		if bb["kind"] == "room":
			cs += bb["pos"]
			cn += 1
	if cn > 0:
		c = cs / cn
	var did := -1
	var at := Vector2.ZERO
	for ring in [110.0, 130.0, 150.0, 175.0, 200.0, 230.0, 260.0]:
		if did >= 0:
			break
		for k in 24:
			var a: float = TAU * float(k) / 24.0
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * ring
			var r: Dictionary = sim.debug.run("place_finished", {"def": "super_dome", "x": p.x, "y": p.y, "size": 1})
			if bool(r["ok"]):
				did = int(r["id"])
				at = sim.state["buildings"][did]["pos"]
				break
	if did < 0:
		print("DOME: no place found")
		return true
	var b: Dictionary = sim.state["buildings"][did]
	# 30 people inside: the living colonists first, spread over the atrium ring (evidence staging).
	var moved := 0
	for id in sim.state["agents"]:
		var ag: Dictionary = sim.state["agents"][id]
		if ag["state"] != "alive" or moved >= 30:
			continue
		var a2: float = float(moved) * 2.4
		ag["pos"] = at + Vector2(cos(a2), sin(a2)) * (8.0 + float(moved % 5) * 2.2)
		ag["where"] = "in"
		ag["bld"] = did
		moved += 1
	var f := FileAccess.open("res://build/web_render/dome_%s.fhsave" % tag, FileAccess.WRITE)
	f.store_buffer(sim.save_bytes())
	f.close()
	print("DOME id %d at %s, radius %.1f, people moved %d" % [did, str(at), float(b["radius"]), moved])
	for k in 9:
		b["state"] = "building"
		b["progress"] = (float(k) + 0.5) / 9.0 * float(b.get("work_total", 100.0))
		if float(b.get("work_total", 0.0)) <= 0.0:
			b["work_total"] = 100.0
			b["progress"] = (float(k) + 0.5) / 9.0 * 100.0
		var f2 := FileAccess.open("res://build/web_render/dome_%s_stage_%d.fhsave" % [tag, k], FileAccess.WRITE)
		f2.store_buffer(sim.save_bytes())
		f2.close()
	print("DOME stage saves 0..8")
	return true
