extends SceneTree
## Probe (UI agent, 2026-10-01): what the Rag gets from SIM on showcase_v4.
##   node tools/godot.mjs script res://tools/ui/ui_probe_rag.gd
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
		main._on_cmd("rag")
	if _n == 20:
		var hud = main.hud
		var v5 = hud.v5
		var sim = main.sim
		print("preview=", v5.preview(), " live social=", v5.live("social"))
		print("people=", v5.people().size(), " colonists=", v5.people().filter(func(r): return String(r["kind"]) == "colonist").size())
		var nrel := 0
		var sts := {}
		for r in v5.people():
			for rel in v5.relations(int(r["id"]), 4):
				nrel += 1
				sts[String(rel["status"])] = int(sts.get(String(rel["status"]), 0)) + 1
		print("relations (top 4 each)=", nrel, " statuses=", sts)
		var tab: Dictionary = sim.content.get("tabloid", {})
		print("content.tabloid keys=", tab.keys(), " columns=", (tab.get("columns", {}) as Dictionary).keys())
		for c in tab.get("columns", {}):
			print("  column ", c, ": ", (tab["columns"][c] as Array).size())
		var iss: Dictionary = hud.rag._issues[0]
		print("issue keys=", iss.keys())
		print("lead=", JSON.stringify(iss.get("lead", {})).left(400))
		for k in ["gossip", "couples", "feuds", "stories", "serious"]:
			print(k, "=", JSON.stringify(iss.get(k, null)).left(600))
		print("links=", hud.rag.links)
		if sim.has_method("get") and sim.get("social") != null:
			print("sim.social methods: ", sim.social.get_script().get_script_method_list().map(func(m): return m["name"]).slice(0, 60))
		quit(0)
		return true
	return false
