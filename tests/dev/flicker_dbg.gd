extends SceneTree
## Developer tool: watch a regolith harvester's block while its output is emptied.

const H = preload("res://tests/helpers.gd")
const C3 = preload("res://tests/cases_v3.gd")

func _init() -> void:
	var g = H.empty_game(1001)
	var sim = g.sim
	var res: Dictionary = H.layout(sim, H.CORE_STEPS + C3.BASE)
	print("layout errors: ", res["errors"])
	sim.state["flags"]["unlock_all"] = true
	var errors: Array = []
	var off: Vector2 = C3._spot(sim, "regolith_harvester", Vector2(-12, -26))
	var rh: Dictionary = H.spawn(sim, "regolith_harvester", off, 0.0, errors)
	H.link_now(sim, "cable", int(rh["id"]), int(res["ids"]["B1"]), errors)
	print("errors ", errors, " off ", off)
	H.set_clock(sim, 1, 30.0)
	g.run(2)
	H.fill_utilities(sim, 1.0, 0.7, true)
	rh["out_rate"] = 20.0
	for s in 40:
		g.run(10)
		var inv: Dictionary = sim.inv.get_inv(int(rh["inv_out"]))
		print("s %d block '%s' powered %s items %s held %s acc %s" % [s, rh["block"], rh["powered"], inv["items"], inv["held_out"], rh["acc"]])
	quit(0)
