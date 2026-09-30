extends SceneTree
## Probe (UI agent, 2026-10-01): the relation store after loading showcase_v4.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 8:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
		main._on_cmd("speed 0")
	if _n == 10 and OS.get_cmdline_user_args().size() > 0:
		main._on_cmd("fast " + OS.get_cmdline_user_args()[0])
	if _n == 12:
		var v: Dictionary = main.sim.state.get("v5", {})
		print("v5 keys=", v.keys())
		var rel: Dictionary = v.get("rel", {})
		print("rel size=", rel.size(), " rel_rev=", v.get("rel_rev", null))
		var ks: Array = rel.keys().slice(0, 3)
		for k in ks:
			print("key ", k, " type ", typeof(k), " -> ", JSON.stringify(rel[k]).left(300))
		var ag: Array = main.sim.state["agents"].keys().slice(0, 3)
		print("agent ids ", ag, " type ", typeof(ag[0]))
		print("keys_of first agent=", main.sim.relations._keys_of(int(ag[0])).size())
		quit(0)
		return true
	return false
