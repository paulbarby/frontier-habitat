extends SceneTree
## RENDER evidence save: showcase_v4 (debug on) with a satellite order at the launch pad, parts
## built in and the work nearly done, so SIM launches it ("satellite_launched") seconds after load.
## Also prints how long the launch takes at speed 4. Writes build/web_render/launch_v4.fhsave.
##   node tools/godot.mjs script res://tools/render_v4_launch_save.gd
var main
var n := 0
var pad := {}
var t0 := 0

func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	var sim = main.sim
	if n == 3:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
		sim = main.sim
		sim.state["options"]["debug"] = true
		for b in sim.state["buildings"].values():
			if b["def"] == "launch_pad":
				pad = b
		var cfgs: Dictionary = sim.vehicles.cfg()["satellite"]
		pad["vorder"] = {"kind": "satellite", "cost": {}, "inv": -1, "progress": float(cfgs.get("build_work", 120.0)) - 2.0,
			"work_total": float(cfgs.get("build_work", 120.0)), "state": "work", "block": ""}
		var f := FileAccess.open("res://build/web_render/launch_v4.fhsave", FileAccess.WRITE)
		f.store_buffer(sim.save_bytes())
		f.close()
		print("LAUNCH save: pad ", pad["id"], " at ", pad["pos"], " sats ", sim.explore.sats().size())
		t0 = int(sim.state["tick"])
		main.set_speed(4)
		return false
	main.set_process(false)
	main._process(1.0 / 30.0)
	for e in sim.state["log"].slice(-5):
		if String(e["code"]) == "satellite_launched" and int(e["tick"]) > t0:
			print("LAUNCHED after %.1f game s: %s" % [float(int(e["tick"]) - t0) / float(sim.bal["tick_hz"]), e["text"] if e.has("text") else e])
			return true
	if n > 30 * 150:
		print("NO LAUNCH in 150 s; order ", pad.get("vorder"))
		return true
	return false