extends SceneTree
## Developer tool: trace one agent in showcase_v3_late around a tick (indoor path check).
##   node tools/godot.mjs script res://tests/dev/indoor_dbg.gd <agent id> <tick>
const H = preload("res://tests/helpers.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: Array = OS.get_cmdline_user_args()
	var aid: int = int(args[0])
	var target: int = int(args[1])
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var sim = H.Sim.new()
	sim.load_state(dec["state"])
	var last := ""
	while int(sim.state["tick"]) < target + 3:
		sim.step()
		if not sim.state["agents"].has(aid):
			continue
		var a: Dictionary = sim.state["agents"][aid]
		if int(sim.state["tick"]) < target - 400:
			continue
		var r: Dictionary = a["route"]
		var leg := ""
		if not r.is_empty() and int(a["li"]) < (r["legs"] as Array).size():
			var l: Dictionary = r["legs"][a["li"]]
			leg = "%s b%s pts %s rooms %s" % [l["m"], str(l.get("b", "")), str(l.get("pts", "")), str(l.get("rooms", ""))]
		var key: String = "%s|%s|%s" % [a["goal"], leg, str(a.get("at", []).slice(0, 1) + a.get("at", []).slice(2))]
		if key != last:
			last = key
			print("t=%d %s where %s bld %d pos %s at %s goal '%s' li %d wi %d\n    leg %s" % [int(sim.state["tick"]), a["name"], a["where"], int(a["bld"]), str(a["pos"]), str(a.get("at")), a["goal"], int(a["li"]), int(a["wi"]), leg])
	quit(0)
