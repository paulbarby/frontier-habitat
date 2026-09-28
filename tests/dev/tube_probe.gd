extends SceneTree
## Developer tool: a Frontier game with the reference campaign; stops at the first outside body in
## a corridor tube and prints the colonist's walking leg (points, length, which segment crosses).
##   node tools/godot.mjs script res://tests/dev/tube_probe.gd [days=3]
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var a0: Array = OS.get_cmdline_user_args()
	var days: float = float(a0[0]) if a0.size() > 0 else 3.0
	var g = H.Game.new(1001, false)
	var sim = g.sim
	var end_tick: int = int(days * 6000.0)
	if a0.size() > 1:
		sim.load_state(preload("res://sim/persistence.gd").decode(FileAccess.get_file_as_bytes(String(a0[1])))["state"])
		end_tick = g.tick() + int(days * 6000.0)
		sim.set_freeze_build(true)       # as RENDER's path check
	else:
		sim.new_game(1001, "frontier")
		g.ref = Reference.new(sim, "all")
	var found := 0
	while g.tick() < end_tick and found < 4:
		g.step()
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] != "alive" or a["where"] != "out":
				continue
			var p: Vector2 = a["pos"]
			for id in sim.state["buildings"]:
				var b: Dictionary = sim.state["buildings"][id]
				if b["kind"] == "link" and b["def"] == "corridor" and b["state"] != "blueprint" \
						and Geometry2D.get_closest_point_to_segment(p, b["p0"], b["p1"]).distance_to(p) < sim.corridor_r():
					found += 1
					print("tick %d: %s (%d) at %s in the tube of %s (%s, state %s) %s-%s" % [g.tick(), a["name"], int(aid), str(p), b["name"], str(id), b["state"], str(b["p0"]), str(b["p1"])])
					var rt: Dictionary = a.get("route", {})
					var li: int = int(a["li"])
					if not rt.is_empty() and li < (rt["legs"] as Array).size():
						var leg: Dictionary = rt["legs"][li]
						print("   leg %d mode %s len %.1f rev %s now %s, wi %d, pts %s" % [li, leg["m"], float(leg.get("len", 0.0)), str(rt.get("rev", -1)), str(sim.state["rev"]["walk"]), int(a["wi"]), str(leg.get("pts", []))])
						var pts: Array = leg.get("pts", [])
						for i in range(1, pts.size()):
							var hit: bool = Geometry2D.segment_intersects_segment(pts[i - 1], pts[i], b["p0"], b["p1"]) != null
							var dmin: float = 1e9
							for s in 20:
								var q: Vector2 = (pts[i - 1] as Vector2).lerp(pts[i], s / 19.0)
								dmin = minf(dmin, Geometry2D.get_closest_point_to_segment(q, b["p0"], b["p1"]).distance_to(q))
							if dmin < sim.corridor_r() + 0.3:
								print("     segment %d %s -> %s (%.1f m) comes %.2f m from the tube axis, cells walkable %s" % [i, str(pts[i - 1]), str(pts[i]), (pts[i - 1] as Vector2).distance_to(pts[i]), dmin, str(sim.nav.is_walkable((pts[i - 1] as Vector2).lerp(pts[i], 0.5)))])
					print("   corridor built at tick %d? state %s; walkable here: %s" % [int(b.get("commissioned", -1)), b["state"], str(sim.nav.is_walkable(p))])
					break
	print("done at tick %d" % g.tick())
	g.dispose()
	quit(0)
