extends SceneTree
## Writes content/saves/showcase_v31.fhsave (docs/V3_1_DESIGN.md section 7): the v3 late colony
## (showcase_v3_late) plus SET-UP: two landing pads placed finished and cabled, then a trader
## and a tourist liner called with the debug command (debug is off again in the save). The
## save is taken when the trader stands on a pad, tourists are in the cantina and an airlock
## is in the middle of a cycle.
##   node tools/godot.mjs script res://tests/make_showcase_v31.gd

const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
const H = preload("res://tests/helpers.gd")

func _init() -> void:
	var dec: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
	var sim = Sim.new()
	sim.load_state(dec["state"])
	var was: bool = bool(sim.state["flags"].get("unlock_all", false))
	sim.state["flags"]["unlock_all"] = true
	var pads: Array = []
	for near in [Vector2(-50, 40), Vector2(-60, 5), Vector2(-45, -70), Vector2(40, -60)]:
		if pads.size() >= 2:
			break
		var p: Dictionary = _pad(sim, near)
		if not p.is_empty():
			pads.append(p)
	sim.state["flags"]["unlock_all"] = was
	# SET-UP: 600 starting credits (a migrated colony has 0), so the save can show a purchase.
	# Booked like a new game's start credits, so credits_audit() stays {}.
	sim.traffic.earn(600, "start")
	print("pads: ", pads.map(func(x): return x["name"]))
	sim.state["options"]["debug"] = true
	var tr: int = -1
	var ln: int = -1
	sim.submit("traffic_now", {"kind": "trader", "in": 5})
	sim.submit("traffic_now", {"kind": "liner", "in": 8})
	sim.step()
	for arr in sim.state["traffic"]["queue"]:
		if arr["kind"] == "trader":
			tr = int(arr["id"])
		if arr["kind"] == "liner":
			ln = int(arr["id"])
	sim.state["options"]["debug"] = false
	var ok := false
	for s in 4000:
		sim.run_seconds(1.0)
		var t_ph: String = String(sim.traffic.find(tr).get("phase", ""))
		var l_ph: String = String(sim.traffic.find(ln).get("phase", ""))
		if t_ph != "landed" or l_ph != "landed":
			continue
		var in_cantina := 0
		for aid in sim.state["agents"]:
			var a: Dictionary = sim.state["agents"][aid]
			if a["state"] == "alive" and a["kind"] == "visitor" and a["where"] == "in" and String(sim.state["buildings"].get(int(a["bld"]), {}).get("def", "")) == "cantina":
				in_cantina += 1
		if in_cantina < 2:
			continue
		for k in 20:
			var cyc := false
			for id in sim.state["buildings"]:
				var info: Dictionary = sim.agents.lock_info(int(id))
				if not info.is_empty() and String(info.get("phase", "")) == "pump" and sim.state["buildings"][id]["def"] == "airlock":
					cyc = true
			if cyc:
				ok = true
				break
			sim.step()
		if ok:
			print("tourists in the cantina: %d" % in_cantina)
			break
	if not ok:
		print("FAILED to reach the wanted moment; saving anyway")
	var bytes: PackedByteArray = sim.save_bytes()
	var tmp := "res://content/saves/showcase_v31.tmp.fhsave"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var chk: Dictionary = Persistence.decode(FileAccess.get_file_as_bytes(tmp))
	var final_abs: String = ProjectSettings.globalize_path("res://content/saves/showcase_v31.fhsave")
	if chk["ok"]:
		if FileAccess.file_exists("res://content/saves/showcase_v31.fhsave"):
			DirAccess.remove_absolute(final_abs)
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), final_abs)
	print("wrote %s: day %.2f, %d bytes, %d colonists, %d visitors, credits %d, ships %s, audit %s, credits %s" % [final_abs,
		sim.util.days_elapsed() + 1.0, bytes.size(), sim.alive_count(), _visitors(sim), sim.traffic.credits(),
		str(sim.traffic.ships().map(func(x): return "%s:%s" % [x["kind"], x["phase"]])), str(sim.inv.audit()), str(sim.traffic.credits_audit())])
	quit(0)

func _visitors(sim) -> int:
	var n := 0
	for aid in sim.state["agents"]:
		if sim.state["agents"][aid]["kind"] == "visitor" and sim.state["agents"][aid]["state"] == "alive":
			n += 1
	return n

## A finished landing pad near a spot, cabled to the nearest battery or powered structure.
func _pad(sim, near: Vector2) -> Dictionary:
	for r in range(0, 40, 4):
		for k in (1 if r == 0 else 16):
			var p: Vector2 = sim.place.snap_pos(sim.world.center + near + Vector2(float(r), 0).rotated(k * TAU / 16.0))
			if sim.place.check_building("landing_pad", p, 0.0) != "ok":
				continue
			var b: Dictionary = sim.build.spawn_active("landing_pad", p, 0.0)
			var best := -1
			var best_d := 1e18
			for id in sim.state["buildings"]:
				var o: Dictionary = sim.state["buildings"][id]
				if int(id) == int(b["id"]) or o["kind"] == "link" or o["state"] != "active" or not sim.topo.power_comp.has(int(id)) or o["def"] == "meridian":
					continue
				var d: float = (o["pos"] as Vector2).distance_to(p)
				if d < best_d and sim.place.check_link("cable", int(id), int(b["id"]))["code"] == "ok":
					best_d = d
					best = int(id)
			if best == -1:
				b["demolish"] = true
				b["progress"] = sim.build.demolish_work_total(b)
				sim.build._try_finish_demolition(b)
				continue
			var errors: Array = []
			H.link_now(sim, "cable", best, int(b["id"]), errors)
			return b
	return {}
