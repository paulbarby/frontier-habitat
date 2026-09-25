extends SceneTree
## Developer tool: a body outside that ends inside a structure. Runs the reference
## campaign ("all") and traces the first offender for 300 ticks before it.
##   node tools/godot.mjs script res://tests/dev/inside_dbg.gd <tick> <name>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")
const V31 = preload("res://tests/cases_v31.gd")

func _init() -> void:
	var target := 46120
	var who := "Sol Natarajan"
	var args: Array = OS.get_cmdline_user_args()
	if args.size() > 0:
		target = int(args[0])
	if args.size() > 1:
		who = String(args[1]).replace("_", " ")
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	var sim = g.sim
	while g.tick() < target - 300:
		g.step()
	while g.tick() <= target + 5:
		g.step()
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["name"] != who:
				continue
			var leg = ""
			var route: Dictionary = a.get("route", {})
			if not route.is_empty() and int(a["li"]) < (route.get("legs", []) as Array).size():
				var l: Dictionary = route["legs"][a["li"]]
				leg = "%s %s" % [l["m"], str(l.get("pts", l.get("b", "")))]
			print("t=%d where %s pos %s walk %s plan %s goal '%s' li %s pi %s leg %s" % [g.tick(), a["where"], str(a["pos"]), str(sim.nav.is_walkable(a["pos"])), a["plan_kind"], a["goal"], str(a.get("li")), str(a.get("pi")), leg])
		var pr: Array = V31.outside_problems(sim)
		if not pr.is_empty():
			print(pr)
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["name"] == "Storehouse 10":
			print("storehouse ", b["pos"], " state ", b["state"], " r ", b["radius"])
	quit(0)
