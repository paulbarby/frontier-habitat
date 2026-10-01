extends SceneTree
## SIM probe: a debug liner on showcase_v5: its phases and result.
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"], {"debug": true})
	for s0 in 90:
		if sim.traffic.ships().is_empty():
			break
		sim.run_seconds(10.0)
	print("pads ", sim.traffic._pads(false), " powered ", sim.traffic._pads(true), " ships ", sim.traffic.ships().size())
	var id: int = sim.submit("traffic_now", {"kind": "liner", "in": 5.0})
	sim.step()
	print("cmd ", sim.cmds.results.get(id))
	var aid: int = int(sim.cmds.results.get(id, {}).get("id", -1))
	for s in 120:
		sim.run_seconds(2.0)
		var arr: Dictionary = sim.traffic.find(aid)
		if s % 10 == 0:
			print(s * 2, " ", arr.get("phase", "?"), " pad ", arr.get("pad", -1), " result ", arr.get("result", {}))
	sim.dispose()
	quit(0)
