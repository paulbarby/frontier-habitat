extends SceneTree
## Probe (UI, 2026-10-03): what the rebuilt showcase_v5 holds of sections 16 and 17.
var main
var _n := 0
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	_n += 1
	if _n < 6:
		return false
	main.boot["debug"] = "1"
	main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
	main._on_cmd("speed 0")
	main.leave_title()
	var s = main.sim
	var kinds := {}
	for r in main.hud.v5.requests():
		kinds[String(r["kind"])] = int(kinds.get(String(r["kind"]), 0)) + 1
	print("requests ", kinds)
	print("parties ", s.party.parties().size(), " offers ", s.party.offers().size(), " events ", s.party.events(5).size(), " cheeky ", s.party.cheeky())
	print("hr offices ", s.hr.offices(-1), " officers ", s.hr.officers(-1), " active ", s.hr.active(-1), " complaints ", s.hr.complaints().size(), " transfers ", s.hr.transfers().size(), " survey ", not s.hr.survey(-1).is_empty())
	for id in s.hr.officers(-1):
		print("officer ", s.state["agents"][id]["name"], " ", s.hr.reputation(id))
	print("talks ", s.social.talks().size())
	quit(0)
	return true
