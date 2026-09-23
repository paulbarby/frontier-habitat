extends SceneTree
## Developer tool: plays the campaign to a day and prints the task board and what every
## colonist does, a few times.
##   node tools/godot.mjs script res://tests/dev/tasks.gd -- [seed] [day] [samples]

const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seed_value: int = int(args[0]) if args.size() > 0 else 1001
	var day: float = float(args[1]) if args.size() > 1 else 14.0
	var samples: int = int(args[2]) if args.size() > 2 else 3
	var sim = Sim.new()
	sim.new_game(seed_value)
	var ref = Reference.new(sim, "all")
	for s in int((day - 1.0) * 600):
		ref.drive()
		sim.run_seconds(1.0)
	for k in samples:
		for s in 20:
			ref.drive()
			sim.run_seconds(1.0)
		print("---- t=%d" % int(sim.seconds()))
		var kinds := {}
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			var dst_name := ""
			if int(t["dst"]) != -1:
				var inv: Dictionary = sim.inv.get_inv(t["dst"])
				dst_name = String(sim.state["buildings"].get(inv.get("oid", -1), {}).get("def", inv.get("role", "")))
			var key := "%s/%s/%s/%s->%s %s" % [t["kind"], t["cat"], t["res"], "owned" if int(t["owner"]) != -1 else ("rest" if int(t["retry"]) > int(sim.state["tick"]) else "open"), dst_name, t["reason"]]
			kinds[key] = int(kinds.get(key, 0)) + 1
		var keys: Array = kinds.keys()
		keys.sort()
		for key in keys:
			print("  %3d %s" % [kinds[key], key])
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "alive":
				print("   %-10s %-12s %s" % [a["role"], a["plan_kind"], a["goal"]])
		for tid in sim.state["tasks"]:
			var t: Dictionary = sim.state["tasks"][tid]
			if t["kind"] != "haul" or t["res"] != "ore" or int(t["owner"]) != -1:
				continue
			var src: Dictionary = sim.inv.get_inv(t["src"])
			var dst: Dictionary = sim.inv.get_inv(t["dst"])
			print("  ORE task %d src %s(%s of %s) dst %s(%s) created %d retry %d reason '%s' emergency %d" % [tid, src.get("role", "?"), str(src.get("ot", "")), String(sim.state["buildings"].get(src.get("oid", -1), {}).get("name", "ground")), dst.get("role", "?"), String(sim.state["buildings"].get(dst.get("oid", -1), {}).get("name", "?")), int(t["created"]) / 10, int(t["retry"]) / 10, t["reason"], int(t["emergency"])])
			var n := 0
			for aid in sim.state["agents"]:
				var a: Dictionary = sim.state["agents"][aid]
				if a["state"] != "alive" or n >= 4:
					continue
				n += 1
				var plan: Dictionary = sim.agents._plan_for_task(a, t)
				print("     %s (%s, %s) score %.0f plan %s %s backoff %s" % [a["name"], a["role"], a["where"], sim.jobs.score(t, a), str(plan["ok"]), plan.get("reason", ""), str(a["backoff"].has(tid))])
	quit(0)
