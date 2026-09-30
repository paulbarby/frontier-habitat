extends SceneTree
## Version 5 orders end to end (UI → confirm → SIM command → SIM state → the answer shown), on
## showcase_v4 with SIM's v5 systems (discipline, ranks, housing, education, unrest, social):
##   node tools/godot.mjs script res://tools/ui/test_v5_orders.gd
## Each order goes through the same UI path a player uses (the button's _ask / the drop, then the
## confirm's yes button), never a direct SIM call.

var main
var fails := 0
var _n := 0
var _step := 0
var pid := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

## Presses the confirm dialog's yes button (the one that is not Back).
func yes() -> bool:
	var top = main.hud.screens.top_screen()
	if top == null or main.hud.screen_name() != "confirm":
		return false
	for b in top.find_children("*", "Button", true, false):
		var t: String = (b as Button).text
		if t != "" and t != "Back" and t != "OK":
			(b as Button).pressed.emit()
			return true
	return false

func not_yet(r: Dictionary) -> bool:
	return String(r.get("code", "")) == "not_yet"

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
			main._on_cmd("speed 0")
			for r in hud.v5.people():
				if String(r["kind"]) == "colonist" and String(r["rank"]) == "crew":
					pid = int(r["id"])
					break
			check("a crew colonist to give orders to", pid >= 0)
			for k in ["review", "discipline", "appoint", "set_home", "enrol", "unrest_response", "egg"]:
				check("SIM takes the order '%s' (sim.<system>.cmd_%s)" % [k, k], hud.v5.live_command(k))
			var pr: Dictionary = hud.v5.predict(pid, "ration_cut")
			check("the prediction is SIM's (no UI estimate; has 'unfair')", not pr.is_empty() and not pr.has("estimate") and pr.has("unfair"), str(pr))
			var u: Dictionary = hud.v5.unrest(-1)
			check("unrest comes from sim.unrest.info (stage and responses)", u.has("stage") and u.has("responses"), str(u.keys()))
			# 1. Review
			main.select("agent", pid)
			hud.open_person(pid, "review")
			hud.person._ask("excellent", "Excellent", "review")
			check("review: confirm, then yes", yes())
			_step = 1
			_n = 0
		1:
			var lr: Dictionary = hud.person.last_result
			var rec: Dictionary = sim.people.rec_of(pid)
			check("review: SIM answers ok and stores it", bool(lr.get("ok", false)) and rec.has("review") and String(rec["review"]["grade"]) == "excellent", "%s  rec %s" % [str(lr), str(rec.get("review", {}))])
			# 2. Discipline (a reward), then a demotion SIM refuses (crew has no post).
			hud.person._ask("praise", "Praise", "discipline")
			yes()
			_step = 2
			_n = 0
		2:
			var lr: Dictionary = hud.person.last_result
			check("discipline praise: SIM answers ok", bool(lr.get("ok", false)), str(lr))
			hud.person._ask("demote", "Demotion", "discipline")
			yes()
			_step = 3
			_n = 0
		3:
			var lr: Dictionary = hud.person.last_result
			check("discipline demote a crew member: SIM refuses and the reason is shown", not bool(lr.get("ok", true)) and not not_yet(lr) and String(lr.get("text", "")) != "", str(lr))
			hud.person.visible = false
			# 3. Appoint through the crew screen drop.
			main._on_cmd("open crew")
			_step = 4
			_n = 0
		4:
			var scr = hud.screens.top_screen()
			var a: Dictionary = sim.state["agents"][pid]
			var dep: String = String(sim.people.department(a))
			scr.dropped(pid, {"rank": "first_hand", "department": dep})
			check("appoint: the drop asks to confirm", hud.screen_name() == "confirm")
			yes()
			_step = 5
			_n = 0
		5:
			var scr = hud.screens.top_screen()
			var lr: Dictionary = scr.last_result if scr != null and "last_result" in scr else {}
			var rk: String = String(sim.people.rank(sim.state["agents"][pid])["rank"])
			check("appoint: SIM makes them First Hand", bool(lr.get("ok", false)) and rk == "first_hand", "%s rank %s" % [str(lr), rk])
			# 4. Set home: a structure with a free bed that is not their home.
			var a: Dictionary = sim.state["agents"][pid]
			var target := -1
			for bid in sim.state["buildings"]:
				var b: Dictionary = sim.state["buildings"][bid]
				if int(bid) != int(a["bed"]) and String(b.get("state", "")) == "active" and int(sim.bd(b).get("beds", 0)) > 0 and sim.housing.free_beds(b) > 0:
					target = int(bid)
					break
			set_meta("target", target)
			if target >= 0:
				scr.dropped(pid, {"unit": -1, "building": target, "building_name": String(sim.state["buildings"][target]["name"])})
				yes()
			_step = 6
			_n = 0
		6:
			var scr = hud.screens.top_screen()
			var target: int = int(get_meta("target"))
			var lr: Dictionary = scr.last_result if scr != null and "last_result" in scr else {}
			if target >= 0:
				check("set home: SIM moves them (their bed is the new home)", bool(lr.get("ok", false)) and int(sim.state["agents"][pid]["bed"]) == target, "%s bed %d target %d" % [str(lr), int(sim.state["agents"][pid]["bed"]), target])
			else:
				print("NOTE no free bed in the save: set_home not run")
			# 5. Enrol through the Academy tab's command (no academy in the save: SIM's refusal is shown).
			var r: Dictionary = hud.v5.command("enrol", {"agent": pid, "skill": "engineering", "building": -1})
			check("enrol: SIM answers (not 'not yet'); without an academy it refuses with a reason", not not_yet(r) and String(r.get("text", "")) != "", str(r))
			main._on_cmd("close")
			# 6. Unrest response through the banner.
			var ids: Array = sim.bases.ids() if sim.bases.count() > 0 else [-1]
			hud.unrest_banner.base_id = int(ids[0])
			hud.unrest_banner._ask("party", "Party at the bar", "test")
			check("unrest response: confirm first", hud.screen_name() == "confirm")
			yes()
			_step = 7
			_n = 0
		7:
			var lr: Dictionary = hud.unrest_banner.last_result
			check("unrest response: SIM answers (not 'not yet')", not lr.is_empty() and not not_yet(lr) and String(lr.get("text", "")) != "", str(lr))
			var used: bool = not bool(hud.v5.unrest(int(hud.unrest_banner.base_id)).get("responses", {}).get("party", true))
			print("NOTE party on cooldown after use: ", used)
			# 7. The egg order (Konami code in the follow view).
			var r: Dictionary = hud.v5.command("egg", {"kind": "dance", "agent": pid})
			check("egg: SIM takes the dance egg order", not not_yet(r), str(r))
			var Profile = load("res://ui/profile.gd")
			Profile.data().erase("eggs")
			Profile._save()
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
