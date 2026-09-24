extends SceneTree
## RENDER test scene for the final critic round (not a playable save):
##  - junction A with 4 links (0, 60, 120, 180 deg) to S rooms, junction B with 3 links 56 deg
##    apart (SIM's minimum is 55);
##  - S habitat, S cantina, S oxygen plant with 2+ doorways each;
##  - one M room of every family in a chain (2 doorways each), an airlock, power,
##    a charged meteor turret, and colonists.
## Written to build/web_render/scene_final.fhsave; load it in the web build with
## window.__fhr.cmd("loadurl scene_final.fhsave").
##   node tools/godot.mjs script res://tools/render_final_save.gd

const Sim = preload("res://sim/sim.gd")

var sim
var log_lines: Array = []

func _place(def_id: String, p: Vector2, rot: float, size: int = 1, exact: bool = false) -> int:
	p = sim.place.snap_pos(p)
	for k in (1 if exact else 14):
		var q: Vector2 = p + Vector2(cos(k * 1.3), sin(k * 1.3)) * float(k) * 1.2
		var code: String = sim.place.check_building(def_id, q, rot, -1, size)
		if code == "ok":
			var b: Dictionary = sim.build.spawn_active(def_id, q, rot, size)
			sim.topo.mark_dirty()
			sim.topo.rebuild(true)
			return int(b["id"])
		if k == 0:
			log_lines.append("%s at %s: %s" % [def_id, str(q), code])
	log_lines.append("could not place %s near %s" % [def_id, str(p)])
	return -1

func _link(kind: String, a: int, b: int) -> int:
	if a < 0 or b < 0:
		return -1
	var r: Dictionary = sim.build.place_link(kind, a, b)
	if not bool(r.get("ok", false)):
		log_lines.append("link %s %d-%d refused: %s" % [kind, a, b, r.get("code", "?")])
		return -1
	var l: Dictionary = sim.state["buildings"][r["id"]]
	sim.build._commission(l, false)
	sim.topo.rebuild(true)
	return int(r["id"])

func _pos(id: int) -> Vector2:
	return sim.state["buildings"][id]["pos"] if id >= 0 else Vector2.ZERO

func _init() -> void:
	sim = Sim.new()
	sim.new_game(1001)
	# Every building type is unlocked for this test scene (as SIM's showcase maker does).
	sim.state["flags"]["unlock_all"] = true
	var c: Vector2 = sim.world.center
	var out := {}
	# Junction A: 4 links to S rooms at 18 m.
	var ja: int = _place("junction", c + Vector2(34, -30), 0.0, 1)
	out["junction_a"] = ja
	var sa: Array = []
	var defs_a := ["habitat", "cantina", "oxygen_plant", "kitchen"]
	var angs_a := [0.0, 60.0, 120.0, 180.0]
	for i in 4:
		var a: float = deg_to_rad(angs_a[i])
		var rid: int = _place(defs_a[i], _pos(ja) + Vector2(cos(a), sin(a)) * 18.0, deg_to_rad(23.0 * i + 11.0), 0)
		sa.append(rid)
		_link("corridor", ja, rid)
	# Second doorways on the S rooms: habitat-cantina, cantina-oxygen plant.
	_link("corridor", sa[0], sa[1])
	_link("corridor", sa[1], sa[2])
	out["s_rooms"] = sa
	# Junction B: 3 links at 55 deg (SIM's minimum).
	var jb: int = _place("junction", c + Vector2(-38, -32), 0.0, 1)
	out["junction_b"] = jb
	var sb: Array = []
	var defs_b := ["storehouse", "workshop", "medical"]
	for i in 3:
		var a2: float = deg_to_rad(-90.0 + 56.0 * i)
		var rid2: int = _place(defs_b[i], _pos(jb) + Vector2(cos(a2), sin(a2)) * 18.0, deg_to_rad(40.0 * i), 0, true)
		sb.append(rid2)
		_link("corridor", jb, rid2)
	out["b_rooms"] = sb
	# Every family, M size, in two rows linked as a chain (two doorways each).
	var fam := ["habitat", "kitchen", "lounge", "cantina", "greenhouse", "fungus_farm", "algae_bioreactor", "bio_lab",
		"research_lab", "research_assembler", "medical", "cold_storage", "oxygen_plant", "atmo_processor",
		"water_recycler", "storehouse", "refinery", "workshop"]
	var chain: Array = []
	for i in fam.size():
		var row: int = i / 9
		var col: int = i % 9
		var x: float = -60.0 + col * 17.0 if row == 0 else 76.0 - col * 17.0
		var p: Vector2 = c + Vector2(x, 46.0 + row * 22.0)
		var rid3: int = _place(fam[i], p, deg_to_rad(float(i) * 37.0), 1)
		chain.append(rid3)
		if i > 0:
			_link("corridor", chain[i - 1], rid3)
	out["family"] = {}
	for i in fam.size():
		out["family"][fam[i]] = chain[i]
	# An airlock off the family chain.
	var al: int = _place("airlock", _pos(chain[8]) + Vector2(0, -15), 0.0, 1)
	_link("corridor", chain[8], al)
	out["airlock"] = al
	# Power: solar, battery, cables to the rooms (corridors carry nothing).
	var bat: int = _place("battery", c + Vector2(-60, 30), 0.0, 1)
	for k in 4:
		var sol: int = _place("solar_array", c + Vector2(-84 + k * 9, 22), 0.0, 1)
		_link("cable", sol, bat)
	# Cables room to room along the chain and round each junction (short runs only).
	var prev: int = bat
	for rid4 in chain:
		if rid4 >= 0:
			_link("cable", prev, rid4)
			prev = rid4
	_link("cable", chain[8] if chain[8] >= 0 else prev, al)
	var bat2: int = _place("battery", _pos(ja) + Vector2(0, 12), 0.0, 1)
	for k in 3:
		var sol2: int = _place("solar_array", _pos(ja) + Vector2(-9 + k * 9, 22), 0.0, 1)
		_link("cable", sol2, bat2)
	for rid6 in [ja] + sa:
		_link("cable", bat2, rid6)
	var bat3: int = _place("battery", _pos(jb) + Vector2(0, 12), 0.0, 1)
	for k in 3:
		var sol3: int = _place("solar_array", _pos(jb) + Vector2(-9 + k * 9, 22), 0.0, 1)
		_link("cable", sol3, bat3)
	for rid7 in [jb] + sb:
		_link("cable", bat3, rid7)
	# A meteor turret with a charge, near junction A.
	var tur: int = _place("meteor_turret", _pos(ja) + Vector2(16, 16), 0.0, 1)
	_link("cable", bat2, tur)
	if tur >= 0:
		var tb: Dictionary = sim.state["buildings"][tur]
		tb["charge"] = float(sim.bd(tb).get("charge_cap", 100.0))
	out["turret"] = tur
	# Colonists: two in most family rooms, three in the S habitat.
	var roles := ["technician", "grower", "operator", "medic", "scientist"]
	var n := 0
	for rid5 in chain + sa:
		if rid5 < 0:
			continue
		for k in (3 if rid5 == sa[0] else 2):
			var bb: Dictionary = sim.state["buildings"][rid5]
			var ag: Dictionary = sim.agents.spawn(roles[n % roles.size()], sim.next_name(), bb["pos"], rid5)
			ag["bed"] = chain[0] if chain[0] >= 0 else rid5
			n += 1
	# Crops at mid growth in every tray room (critic round 8: rooms were shot with empty beds).
	for id in sim.state["buildings"]:
		var tb2: Dictionary = sim.state["buildings"][id]
		var trays: Array = tb2.get("trays", [])
		for ti in trays.size():
			sim.prod.finish_seed(tb2, ti)
			var cyc: float = float(sim.prod.crop_info(String(trays[ti]["grow"]))["cycle_seconds"])
			trays[ti]["growth"] = cyc * (0.4 + 0.1 * float(ti % 3))
	sim.topo.mark_dirty()
	sim.topo.rebuild(true)
	sim.run_seconds(30.0)
	var bytes: PackedByteArray = sim.save_bytes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/web_render"))
	var f := FileAccess.open("res://build/web_render/scene_final.fhsave", FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	# Report: every room with its position, and each junction's link angles.
	var rep := {}
	for id in sim.state["buildings"]:
		var b: Dictionary = sim.state["buildings"][id]
		if b["kind"] == "room":
			rep[id] = "%s s%d (%.0f,%.0f)" % [b["def"], int(b.get("size", 1)), b["pos"].x, b["pos"].y]
	for j in [ja, jb]:
		var angs: Array = []
		for lid in sim.state["buildings"]:
			var l: Dictionary = sim.state["buildings"][lid]
			if l["kind"] == "link" and l["def"] == "corridor" and (int(l.get("a", -1)) == j or int(l.get("b", -1)) == j):
				var other: Vector2 = l["p1"] if int(l.get("a", -1)) == j else l["p0"]
				angs.append(snappedf(rad_to_deg((other - _pos(j)).angle()), 1.0))
		print("junction %d links at %s" % [j, str(angs)])
	for line in log_lines:
		print(line)
	print("scene_final: %d structures, %d colonists" % [sim.state["buildings"].size(), sim.state["agents"].size()])
	print(JSON.stringify(out))
	print(JSON.stringify(rep))
	quit(0)
