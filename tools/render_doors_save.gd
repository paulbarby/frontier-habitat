extends SceneTree
## RENDER test save for Paul's links rule (S 4, M 6, L 7, XL 8 corridors per room): an XL
## habitat with 8 corridors and an S habitat with 4, each corridor to a junction, colonists in
## both rooms. Written to build/web_render/doors8.fhsave (used by render_path_check and
## render_cut_check).
##   node tools/godot.mjs script res://tools/render_doors_save.gd
const Sim = preload("res://sim/sim.gd")
var sim
var lines: Array = []

func _place(def_id: String, p: Vector2, rot: float, size: int = 1) -> int:
	p = sim.place.snap_pos(p)
	for k in 14:
		var q: Vector2 = p + Vector2(cos(k * 1.3), sin(k * 1.3)) * float(k) * 1.2
		if sim.place.check_building(def_id, q, rot, -1, size) == "ok":
			var b: Dictionary = sim.build.spawn_active(def_id, q, rot, size)
			sim.topo.mark_dirty()
			sim.topo.rebuild(true)
			return int(b["id"])
	lines.append("could not place %s near %s" % [def_id, str(p)])
	return -1

func _link(a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return false
	var r: Dictionary = sim.build.place_link("corridor", a, b)
	if not bool(r.get("ok", false)):
		lines.append("link %d-%d refused: %s" % [a, b, r.get("code", "?")])
		return false
	sim.build._commission(sim.state["buildings"][r["id"]], false)
	sim.topo.mark_dirty()
	sim.topo.rebuild(true)
	return true

## A room of `size` with `n` corridors to junctions, spread as evenly as the door sectors allow.
func _hub(def_id: String, size: int, c: Vector2, n: int) -> Dictionary:
	var rid: int = _place(def_id, c, 0.0, size)
	if rid < 0:
		return {"room": -1, "links": 0}
	var room: Dictionary = sim.state["buildings"][rid]
	var rr: float = float(room["radius"])
	var made := 0
	var tries := 0
	var k := 0
	while made < n and tries < 72:
		var ang: float = TAU * float(k) / float(n) + deg_to_rad(float(tries / n) * 7.0)
		k += 1
		tries += 1
		if not sim.place.link_angle_ok(room, ang):
			continue
		var j: int = _place("junction", c + Vector2(cos(ang), sin(ang)) * (rr + 14.0), 0.0, 1)
		if j < 0:
			continue
		if _link(rid, j):
			made += 1
	return {"room": rid, "links": made, "max": sim.place.max_links(room)}

func _init() -> void:
	sim = Sim.new()
	sim.new_game(1001)
	sim.state["flags"]["unlock_all"] = true
	var c: Vector2 = sim.world.center
	var xl: Dictionary = _hub("habitat", 3, c + Vector2(70, 60), 8)
	var s: Dictionary = _hub("habitat", 0, c + Vector2(-70, 60), 4)
	var roles := ["technician", "grower", "operator", "medic", "scientist"]
	var n := 0
	for h in [xl, s]:
		if int(h["room"]) < 0:
			continue
		var bb: Dictionary = sim.state["buildings"][int(h["room"])]
		for k in (8 if h == xl else 4):
			var ag: Dictionary = sim.agents.spawn(roles[n % roles.size()], sim.next_name(), bb["pos"], int(h["room"]))
			ag["bed"] = int(h["room"])
			n += 1
	sim.run_seconds(20.0)
	var f := FileAccess.open("res://build/web_render/doors8.fhsave", FileAccess.WRITE)
	f.store_buffer(sim.save_bytes())
	f.close()
	print("DOORS XL room %d: %d of %s links | S room %d: %d of %s links" % [int(xl["room"]), int(xl["links"]), str(xl.get("max")), int(s["room"]), int(s["links"]), str(s.get("max"))])
	for l in lines:
		print("  ", l)
	quit()
