extends SceneTree
## RENDER test scene for doorways, interiors and furniture use (not a playable save):
## an M habitat (rotated 17 deg) with corridors at odd angles to four rooms, a second
## habitat with one corridor, power, air and eight colonists inside. Written to
## build/web_render/scene_rooms.fhsave; load it in the web build with
## window.__fhr.cmd("loadurl scene_rooms.fhsave").
##   node tools/godot.mjs script res://tools/render_scene_save.gd

const Sim = preload("res://sim/sim.gd")

var sim

func _place(def_id: String, p: Vector2, rot: float, size: int = 1) -> int:
	p = sim.place.snap_pos(p)
	for k in 12:
		var q: Vector2 = p + Vector2(cos(k * 1.3), sin(k * 1.3)) * float(k) * 1.5
		var code: String = sim.place.check_building(def_id, q, rot, -1, size)
		if code == "ok":
			var b: Dictionary = sim.build.spawn_active(def_id, q, rot, size)
			sim.topo.mark_dirty()
			sim.topo.rebuild(true)
			return int(b["id"])
	print("could not place %s near %s" % [def_id, str(p)])
	return -1

func _link(kind: String, a: int, b: int) -> int:
	if a < 0 or b < 0:
		return -1
	var r: Dictionary = sim.build.place_link(kind, a, b)
	if not bool(r.get("ok", false)):
		print("link %s %d-%d refused: %s" % [kind, a, b, r.get("code", "?")])
		return -1
	var l: Dictionary = sim.state["buildings"][r["id"]]
	sim.build._commission(l, false)
	sim.topo.rebuild(true)
	return int(r["id"])

func _init() -> void:
	sim = Sim.new()
	sim.new_game(1001)
	var c: Vector2 = sim.world.center
	var hub: Vector2 = c + Vector2(30, -6)
	var hab: int = _place("habitat", hub, deg_to_rad(17.0), 1)
	var names := ["kitchen", "lounge", "research_lab", "oxygen_plant"]
	var angles := [17.0, 101.0, 199.0, 290.0]
	var rooms: Array = []
	for i in 4:
		var a: float = deg_to_rad(angles[i])
		var rid: int = _place(names[i], hub + Vector2(cos(a), sin(a)) * 15.5, deg_to_rad(angles[i] * 1.7), 1)
		rooms.append(rid)
		_link("corridor", hab, rid)
	# A second habitat with ONE corridor (at an odd angle) from the lounge.
	var lounge: Dictionary = sim.state["buildings"][rooms[1]] if rooms[1] >= 0 else {}
	if not lounge.is_empty():
		var a2: float = deg_to_rad(143.0)
		var hab2: int = _place("habitat", (lounge["pos"] as Vector2) + Vector2(cos(a2), sin(a2)) * 15.0, deg_to_rad(64.0), 1)
		_link("corridor", rooms[1], hab2)
		# A third habitat with two corridors.
		var hab3: int = _place("habitat", (lounge["pos"] as Vector2) + Vector2(cos(deg_to_rad(38.0)), sin(deg_to_rad(38.0))) * 15.0, deg_to_rad(-22.0), 1)
		_link("corridor", rooms[1], hab3)
		_link("corridor", hab3, rooms[0])
	# An airlock out of the oxygen plant, power and water.
	var ox: Dictionary = sim.state["buildings"].get(rooms[3], {})
	if not ox.is_empty():
		var al: int = _place("airlock", (ox["pos"] as Vector2) + Vector2(0, 12), 0.0, 1)
		_link("corridor", rooms[3], al)
	var sol: Array = []
	for k in 3:
		sol.append(_place("solar_array", hub + Vector2(-26 + k * 8, 26), 0.0, 1))
	var bat: int = _place("battery", hub + Vector2(-2, 28), 0.0, 1)
	for s in sol:
		_link("cable", s, bat)
	_link("cable", bat, hab)
	var wx: int = _place("water_extractor", hub + Vector2(24, 22), 0.0, 1)
	_link("cable", wx, bat)
	var res: int = _place("reservoir", hub + Vector2(14, 26), 0.0, 1)
	_link("cable", res, bat)
	_link("cable", wx, res)
	if not ox.is_empty():
		_link("cable", res, rooms[3])
	# Colonists in the first habitat.
	var roles := ["technician", "grower", "operator", "medic", "scientist", "technician", "operator", "scientist"]
	var hb: Dictionary = sim.state["buildings"][hab]
	for i in 8:
		var ag: Dictionary = sim.agents.spawn(roles[i], sim.next_name(), hb["pos"], hab)
		ag["bed"] = hab
	sim.topo.mark_dirty()
	sim.topo.rebuild(true)
	sim.run_seconds(40.0)
	var bytes: PackedByteArray = sim.save_bytes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/web_render"))
	var f := FileAccess.open("res://build/web_render/scene_rooms.fhsave", FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var n_links := 0
	for id in sim.state["buildings"]:
		if sim.state["buildings"][id]["kind"] == "link":
			n_links += 1
	print("scene_rooms: map %d, %d structures (%d links), %d colonists, habitat %d at %s, rooms %s" % [int(sim.world.size), sim.state["buildings"].size(), n_links, sim.state["agents"].size(), hab, str(hb["pos"]), str(rooms)])
	quit(0)
