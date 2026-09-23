extends SceneTree
## RENDER performance test data: a colony with about 150 structures and 60 colonists, for
## frame-rate measurement only (not a playable save). Writes
## build/web_render/perf_stress.fhsave (outside the game package; the web build loads it
## through the RENDER debug hook: window.__fhr.cmd("loadurl perf_stress.fhsave")).
##   node tools/godot.mjs script res://tools/render_stress_save.gd

const Sim = preload("res://sim/sim.gd")

func _init() -> void:
	var sim = Sim.new()
	sim.new_game(1001)
	var c: Vector2 = sim.world.center
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var rooms := ["habitat", "greenhouse", "kitchen", "oxygen_plant", "storehouse", "refinery", "workshop", "lounge",
		"medical", "research_lab", "polymer_plant", "glassworks", "water_recycler", "cantina", "cold_storage", "junction",
		"electronics_fab", "fabricator", "fungus_farm", "algae_bioreactor", "atmo_processor", "bio_lab"]
	var exts := ["solar_array", "solar_array", "wind_turbine", "battery", "water_extractor", "reservoir", "regolith_harvester", "fuel_refinery", "comms_tower", "landing_pad"]
	var placed: Array = []
	var k := 0
	# Rooms on rings round the lander, exteriors further out.
	for ring in range(1, 9):
		var rad: float = 13.0 * ring
		var n: int = int(TAU * rad / 13.5)
		for i in n:
			var a: float = TAU * i / n + ring * 0.37
			var p: Vector2 = sim.place.snap_pos(c + Vector2(cos(a), sin(a)) * rad)
			var def_id: String = rooms[k % rooms.size()] if ring <= 5 else exts[k % exts.size()]
			var size: int = rng.randi_range(0, 2)
			if not sim.content["buildings"].has(def_id):
				k += 1
				continue
			var code: String = sim.place.check_building(def_id, p, 0.0, -1, size)
			if code != "ok":
				size = 0
				code = sim.place.check_building(def_id, p, 0.0, -1, size)
			if code == "ok":
				var b: Dictionary = sim.build.spawn_active(def_id, p, snappedf(rng.randf() * TAU, PI / 12.0) if ring > 5 else 0.0, size)
				if bool(sim.bdef(def_id).get("levels", false)):
					b["level"] = rng.randi_range(1, 5)
				placed.append(b["id"])
				sim.topo.mark_dirty()
				sim.topo.rebuild(true)
			k += 1
	# Corridors between near rooms.
	var links := 0
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var a: Dictionary = sim.state["buildings"][placed[i]]
			var b: Dictionary = sim.state["buildings"][placed[j]]
			if a["kind"] != "room" or b["kind"] != "room":
				continue
			if (a["pos"] as Vector2).distance_to(b["pos"]) > 16.5:
				continue
			var r: Dictionary = sim.build.place_link("corridor", a["id"], b["id"])
			if bool(r.get("ok", false)):
				var l: Dictionary = sim.state["buildings"][r["id"]]
				sim.build._commission(l, false)
				links += 1
				sim.topo.rebuild(true)
	var roles := ["technician", "grower", "operator", "medic", "scientist"]
	var habs: Array = []
	for id in sim.state["buildings"]:
		if sim.state["buildings"][id]["def"] == "habitat":
			habs.append(id)
	var n_agents: int = sim.state["agents"].size()
	var guard := 0
	while n_agents < 60 and guard < 2000:
		guard += 1
		var p := c + Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
		var inside: bool = rng.randf() < 0.5 and not habs.is_empty()
		if inside:
			var hid: int = habs[rng.randi() % habs.size()]
			sim.agents.spawn(roles[n_agents % roles.size()], sim.next_name(), sim.state["buildings"][hid]["pos"], hid)
			n_agents += 1
		elif sim.nav.is_walkable(p):
			sim.agents.spawn(roles[n_agents % roles.size()], sim.next_name(), p, -1)
			n_agents += 1
	sim.topo.mark_dirty()
	sim.topo.rebuild(true)
	sim.run_seconds(30.0)
	var bytes: PackedByteArray = sim.save_bytes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/web_render"))
	var f := FileAccess.open("res://build/web_render/perf_stress.fhsave", FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	print("perf_stress: %d structures (%d corridors), %d colonists, %d bytes" % [sim.state["buildings"].size(), links, sim.state["agents"].size(), bytes.size()])
	quit(0)
