extends SceneTree
## "OUT OF REACH" explains itself (Paul, 2026-09-29), headless:
##   node tools/godot.mjs script res://tools/ui/test_reach.gd
## A plan far from every airlock with air says the walk, the suit reach and "Build an airlock closer";
## one inside the reach but blocked says "no walking path" and "Clear the way"; the inspector badge
## and the Materials line carry the same numbers.

const Why = preload("res://ui/why.gd")

var main
var fails := 0
var _n := 0
var _step := 0
var far_id := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main.start_new(1001, {"scenario": "frontier"})
			main._on_cmd("speed 0")
			sim = main.sim
			var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
			var reach_m: float = sim.agents.suit_reach_metres()
			# A solar array plan well beyond the suit reach (a normal placement).
			var placed := false
			for rr in [reach_m + 120.0, reach_m + 200.0, reach_m + 300.0]:
				for k in 24:
					var p: Vector2 = sim.place.snap_pos((lander["pos"] as Vector2) + Vector2.RIGHT.rotated(k * TAU / 24.0) * rr)
					if sim.place.check_building("solar_array", p, 0.0, -1, 1) == "ok":
						var r: Dictionary = sim.build.place_building("solar_array", p, 0.0, 1)
						if bool(r.get("ok", false)):
							far_id = int(r.get("id", -1))
							placed = true
							break
				if placed:
					break
			check("a plan beyond the suit reach", far_id != -1, "reach %.0f m" % reach_m)
			for i in 30:
				sim.step()
			_step = 1
			_n = 0
		1:
			var b: Dictionary = sim.state["buildings"].get(far_id, {})
			var r: Dictionary = Why.reach(hud, b)
			var ri: Dictionary = sim.agents.reach_info(b)
			check("far plan (SIM reach_info too_far): 'Walk from <airlock>: N m, suit reach M m'", String(r.code) == "too_far" and String(r.short) == "Walk from %s: %d m, suit reach %d m" % [ri["lock_name"], int(roundf(float(ri["walk_m"]))), int(roundf(float(ri["reach_m"])))], str(r))
			check("far plan: the fix builds an airlock closer (and names the suit research)", String(r.fix[0]).begins_with("Build an airlock closer") and (r.fix.size() < 2 or String(r.fix[1]).begins_with("Or research")), str(r.fix))
			var w: Dictionary = Why.structure(hud, b)
			check("why stopped? for the plan uses the numbers (block %s)" % b.get("block", ""), String(b.get("block", "")) not in ["unreachable", "suit_range"] or String(w["why"][0]).begins_with("Walk from"), str(w["why"]))
			# Inside the reach but no path: a copy of a plan next to the lander, marked unreachable.
			var lander: Dictionary = sim.state["buildings"][int(sim.state["lander_id"])]
			var near: Dictionary = b.duplicate(true)
			near["pos"] = (lander["pos"] as Vector2) + Vector2(30, 0)
			near["block"] = "unreachable"
			var r2: Dictionary = Why.reach(hud, near)
			check("near (SIM says in reach): no airlock to build, the verdict is old", String(r2.code) == "ok" and String(r2.short).begins_with("In reach") and not String(r2.fix[0]).contains("airlock"), str(r2))
			# SIM's other verdicts, as rows (the mapping of the UI).
			var np: Dictionary = Why._reach_from_sim(hud, {"why": "no_path", "text": "No walking way from an airlock with air to it (60 m in a straight line).", "straight_m": 60.0, "reach_m": 141.0})
			check("no_path: SIM's text and 'Clear the way'", String(np.short) == "No walking path from any airlock with air" and String(np.why[0]).begins_with("No walking way") and String(np.fix[0]).begins_with("Clear the way"), str(np))
			var na: Dictionary = Why._reach_from_sim(hud, {"why": "no_air", "text": "No airlock has air: nobody can go out and come back."})
			check("no_air: 'No airlock has air' and a fix that gives an airlock air", String(na.short) == "No airlock has air" and String(na.fix[0]).begins_with("Join an airlock"), str(na))
			# The inspector: badge tooltip and the Materials line.
			b["block"] = "suit_range"   # test set-up: the verdict the inspector explains
			main.select("building", far_id)
			_step = 2
			_n = 0
		2:
			var tip_ok := false
			var line_ok := false
			for c in hud.inspector.find_children("*", "Control", true, false):
				if (c as Control).tooltip_text.contains("Walk from") and (c as Control).tooltip_text.contains("Fix: Build an airlock closer"):
					tip_ok = true
				if c is Label and (c as Label).text.begins_with("Walk from"):
					line_ok = true
			check("inspector: the OUT OF REACH badge tooltip has the walk, the reach and the fix", tip_ok)
			check("inspector: the Materials section line has the numbers", line_ok)
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
