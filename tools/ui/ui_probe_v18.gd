extends SceneTree
## Probe (UI, 2026-10-04): what the section 18 adapter gives on showcase_v5.
##   node tools/godot.mjs script res://tools/ui/ui_probe_v18.gd
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		root.size = Vector2i(1920, 1080)
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
	if _n == 30:
		var hud = main.hud
		var s = main.sim
		var v18 = hud.v18
		print("live work=%s chains=%s transport=%s" % [v18.live("work"), v18.live("chains"), v18.live("transport")])
		print("tasks ", s.state["tasks"].size(), " summary ", v18.summary())
		for d in v18.work_depts():
			print("dept ", d, " rows ", v18.work_items(String(d[0])).size())
		var items: Array = v18.work_items("all")
		for i in mini(4, items.size()):
			print("row ", items[i])
		var bid := -1
		for id in s.state["buildings"]:
			var b: Dictionary = s.state["buildings"][id]
			if String(b["state"]) == "active" and bool(hud.data.wear_of(b).get("known", false)):
				bid = int(id)
				break
		print("wear building ", bid, " ", s.state["buildings"].get(bid, {}).get("name", ""), " ", v18.wear_state(s.state["buildings"][bid]))
		print("heads ", v18.heads(bid))
		print("candidates ", v18.candidates(bid, 3, true))
		var ch: Dictionary = v18.chain_of("spare_parts")
		print("chain ", ch["name"], " ok ", ch["ok"], " | ", ch["text"])
		for st in ch["steps"]:
			print("  ", st["depth"], " ", st["kind"], " ", st["name"], " ", st["state"], " | ", st["text"], " place=", st["can_place"])
		print("chains ", v18.all_chains().size())
		quit(0)
	return false
