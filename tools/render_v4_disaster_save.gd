extends SceneTree
## RENDER evidence save: content/saves/showcase_v4.fhsave (debug on) with the three risky plants
## a few seconds from their SIM events, for web shots of the SIM-driven effects:
##   reactor 3830: heat 130 -> "reactor_breach" on the first sim second (60 m blast, 140 m zone);
##   a crystal refinery, unpowered with a batch, unstable_t = blow_s - 8 -> "unstable_blast";
##   a chemical plant at health 40 -> "toxic_leak" on the first second (30 m zone).
## (SIM's debug reactor_stage breach does not breach while the core has coolant: RENDER-to-SIM.)
## Writes build/web_render/disaster_v4.fhsave and prints the positions.
##   node tools/godot.mjs script res://tools/render_v4_disaster_save.gd
var main
var n := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
	var sim = main.sim
	sim.state["options"]["debug"] = true
	var rx_b: Dictionary = {}
	for b in sim.state["buildings"].values():
		if b["def"] == "fission_reactor":
			rx_b = b
	var rp: Vector2 = rx_b["pos"]
	var out := {"reactor": [int(rx_b["id"]), rp]}
	# The two plants: first free spot 170-320 m from the reactor (outside its blast), toward the base.
	var placed := {}
	for def_id in ["crystal_refinery", "chemical_plant"]:
		var done := false
		for ring in [170.0, 200.0, 240.0, 280.0, 320.0]:
			if done:
				break
			for k in 48:
				var a: float = PI + (k / 2) * 0.13 * (1 if k % 2 == 0 else -1)
				var p: Vector2 = rp + Vector2(cos(a), sin(a)) * ring
				var skip := false
				for q in placed.values():
					if (q as Vector2).distance_to(p) < 60.0:
						skip = true
				if skip:
					continue
				var r: Dictionary = sim.debug.run("place_finished", {"def": def_id, "x": p.x, "y": p.y})
				if bool(r["ok"]):
					var b: Dictionary = sim.state["buildings"][int(r["id"])]
					placed[def_id] = b["pos"]
					out[def_id] = [int(r["id"]), b["pos"], bool(b["powered"])]
					if def_id == "crystal_refinery":
						b["batch"] = {"recipe": "crystal_lattice", "t": 0.0}
						b["unstable_t"] = int(sim.reactors.cfg()["unstable"]["blow_s"]) - 8
					else:
						b["health"] = 40.0
					done = true
					break
	sim.reactors.rx(rx_b)["heat"] = 130.0
	var bytes: PackedByteArray = sim.save_bytes()
	var f := FileAccess.open("res://build/web_render/disaster_v4.fhsave", FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	print("DISASTER ", out, " bytes ", bytes.size())
	return true
