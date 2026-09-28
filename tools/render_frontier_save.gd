extends SceneTree
## RENDER: a Frontier (v4 map) game for the path check - SIM's reference campaign ("all") on a new
## "frontier" game, run for [days] game days. Writes build/web_render/frontier_game.fhsave.
##   node tools/godot.mjs script res://tools/render_frontier_save.gd [days] [seed]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var days: int = int(a[0]) if a.size() > 0 else 2
	var seed_value: int = int(a[1]) if a.size() > 1 else 1001
	var sim = Sim.new()
	sim.new_game(seed_value, "frontier")
	var ref = Reference.new(sim, "all")
	for d in days:
		for s in 600:
			ref.drive()
			sim.run_seconds(1.0)
	var rooms := 0
	for b in sim.state["buildings"].values():
		if b["kind"] == "room" and b["state"] == "active":
			rooms += 1
	var f := FileAccess.open("res://build/web_render/frontier_game.fhsave", FileAccess.WRITE)
	f.store_buffer(sim.save_bytes())
	f.close()
	print("FRONTIER save: day %d, pop %d, structures %d, rooms %d" % [days, sim.alive_count(), sim.state["buildings"].size(), rooms])
	quit(0)
