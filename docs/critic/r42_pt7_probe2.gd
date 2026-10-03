extends SceneTree
## Critic r42 verify (PT-7), part 2: showcase_v5.fhsave from load to about day 21.8 (t+2100 s).
## Read only. (1) every agent the "starving" alert names: its hunger, plan and room every 5 s
## until it eats or dies; (2) at the first jams of Airlock 4: where the "Carrying ..." hauls of
## the queue go (task src -> dst); (3) deaths; (4) per-airlock use counts by direction.

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")

var _track := {}      # aid -> true while followed
var _flagged := {}    # aid -> first tick flagged

func _inv_name(sim, inv_id: int) -> String:
	if not sim.inv.exists(inv_id):
		return "inv%d(gone)" % inv_id
	var invs: Dictionary = sim.state["inventories"]
	var iv: Dictionary = invs.get(inv_id, {})
	if iv.is_empty():
		return "inv%d@%s" % [inv_id, str(sim.inv.position_of(inv_id))]
	if String(iv.get("ot", "")) == "b":
		var b: Dictionary = sim.state["buildings"].get(int(iv["oid"]), {})
		return "%s(%s)@(%.0f,%.0f)" % [String(b.get("name", "?")), String(b.get("def", "?")), b.get("pos", Vector2()).x, b.get("pos", Vector2()).y]
	var p: Vector2 = sim.inv.position_of(inv_id)
	return "%s:%s@(%.0f,%.0f)" % [String(iv.get("ot", "?")), str(iv.get("oid", "?")), p.x, p.y]

func _line(sim, aid) -> String:
	var a: Dictionary = sim.state["agents"][aid]
	var bname: String = String(sim.state["buildings"].get(int(a["bld"]), {}).get("name", "-"))
	return "id=%d %s kind=%s role=%s state=%s where=%s bld=%s plan=%s goal=%s hunger=%.0f health=%.0f sleeping=%s pos=(%.0f,%.0f)" % [
		int(aid), a["name"], a["kind"], a["role"], a["state"], a["where"], bname, String(a["plan_kind"]), String(a["goal"]),
		float(a["hunger"]), float(a["health"]), str(a["sleeping"]), a["pos"].x, a["pos"].y]

func _initialize() -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://showcase_v5.fhsave"))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	var hz: int = int(sim.bal["tick_hz"])
	print("state keys: ", str(sim.state.keys()))
	var dead := {}
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["state"] == "dead":
			dead[aid] = true
	var haul_printed := 0
	var starving_secs := 0
	var jam_secs := 0
	var t := 0
	while t < 2100:
		for i in 5 * hz:
			sim.step()
		t += 5
		var iss: Dictionary = sim.state["issues"]
		var tick: int = int(sim.state["tick"])
		var day: float = float(tick) / 6000.0
		if iss.has("starving"):
			starving_secs += 5
			for aid in iss["starving"].get("entities", []):
				if not _flagged.has(aid):
					_flagged[aid] = tick
					_track[aid] = true
					print("[t+%d day %.2f] STARVING FLAGGED live=%s '%s' meals=%d :: %s" % [t, day, str(iss["starving"].get("live", true)), String(iss["starving"]["text"]), int(sim.metrics.forecast()["meals"]), _line(sim, aid)])
		for k in iss:
			if String(k).begins_with("lockjam") and bool(iss[k].get("live", true)):
				jam_secs += 5
				if haul_printed < 3:
					haul_printed += 1
					var bid: int = int(String(k).split(":")[1])
					var lock: Dictionary = sim.state["buildings"][bid]["lock"]
					print("[t+%d day %.2f] JAM %s :: %s" % [t, day, k, String(iss[k]["text"])])
					for q in lock["queue"]:
						var qa: Dictionary = sim.state["agents"][q["a"]]
						var desc := ""
						if int(qa["task"]) != -1 and sim.state["tasks"].has(int(qa["task"])):
							var tk: Dictionary = sim.state["tasks"][int(qa["task"])]
							desc = "task=%s res=%s emergency=%s src=%s dst=%s" % [tk["kind"], String(tk.get("res", "")), str(tk.get("emergency", false)), _inv_name(sim, int(tk.get("src", -1))), _inv_name(sim, int(tk.get("dst", -1)))]
						print("    Q dir=%s %s %s | %s" % [q["dir"], qa["name"], qa["kind"], desc if desc != "" else String(qa["goal"])])
		for aid in _track.keys():
			var a: Dictionary = sim.state["agents"][aid]
			print("    [t+%d day %.2f] TRACK %s" % [t, day, _line(sim, aid)])
			if a["state"] != "alive" or float(a["hunger"]) < 40.0:
				_track.erase(aid)
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "dead" and not dead.has(aid):
				dead[aid] = true
				print("[t+%d day %.2f] DEATH id=%d %s kind=%s cause=%s" % [t, day, int(aid), a["name"], a["kind"], String(a["cause"])])
	print("SUMMARY to day %.2f: starving alert on %d s, Airlock jam live %d s, flagged=%s, deaths=%d" % [float(int(sim.state["tick"])) / 6000.0, starving_secs, jam_secs, str(_flagged.keys()), int(sim.state["progress"]["deaths"])])
	quit(0)
