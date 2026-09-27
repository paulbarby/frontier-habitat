extends SceneTree
## RENDER: the POIs, satellites and vehicles of a save (default showcase_v4).
##   node tools/godot.mjs script res://tools/render_poi_list.gd [res://save]
var main
var n := 0
func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	n += 1
	if n > 20:
		return true
	if n != 3:
		return false
	var ua: PackedStringArray = OS.get_cmdline_user_args()
	main._import_bytes(FileAccess.get_file_as_bytes(ua[0] if ua.size() > 0 else "res://content/saves/showcase_v4.fhsave"))
	var ex = main.sim.explore
	for p in ex.pois():
		print("POI ", p["id"], " ", p["kind"], " ", int(p["x"]), " ", int(p["y"]), " found=", p["found"], " visited=", p["visited"])
	print("SATS ", ex.sats(), " uplink ", ex.uplink(), " share ", ex.explored_share())
	var vs = main.sim.state.get("vehicles", {})
	for v in (vs.values() if vs is Dictionary else vs):
		print("VEH ", v.get("id"), " ", v.get("kind"), " ", v.get("pos"), " ", v.get("state", ""), " ", v.get("task", ""))
	for b in main.sim.state["buildings"].values():
		if String(b["def"]) in ["launch_pad", "comms_tower", "rover_depot", "fission_reactor", "outpost_core"]:
			print("B ", b["id"], " ", b["def"], " ", b["pos"], " powered=", b.get("powered"), " state=", b["state"])
	return true