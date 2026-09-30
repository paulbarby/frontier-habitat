extends SceneTree
## SIM probe: the parts of people.tick() on showcase_v5 (rank signature, the per-person update).
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(10.0)
	var t_sig := 0.0
	var t_upd := 0.0
	var t_sat := 0.0
	var t_home := 0.0
	var t_sum := 0.0
	var t_flags := 0.0
	var n_upd := 0
	var agents: Dictionary = sim.state["agents"]
	for i in 600:
		sim.step()
		var t0: int = Time.get_ticks_usec()
		sim.people._sig_tick = -1
		sim.people._refresh_ranks(true)
		t_sig += float(Time.get_ticks_usec() - t0)
		var ids: Array = agents.keys()
		var a: Dictionary = agents[ids[i % ids.size()]]
		if a["state"] != "alive":
			continue
		t0 = Time.get_ticks_usec()
		sim.people._satisfaction(a)
		t_sat += float(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		sim.people.home(a)
		t_home += float(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		sim.relations.summary(int(a["id"]))
		t_sum += float(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		sim.people._apply_flags(a, sim.people.rec_w(a))
		t_flags += float(Time.get_ticks_usec() - t0)
		t0 = Time.get_ticks_usec()
		sim.people._update(a)
		t_upd += float(Time.get_ticks_usec() - t0)
		n_upd += 1
	print("rank signature %.3f ms a call; update %.3f ms (satisfaction %.3f, home %.3f, relations summary %.3f, flags %.3f) a person" % [t_sig / 600000.0, t_upd / n_upd / 1000.0, t_sat / n_upd / 1000.0, t_home / n_upd / 1000.0, t_sum / n_upd / 1000.0, t_flags / n_upd / 1000.0])
	sim.dispose()
	quit(0)
