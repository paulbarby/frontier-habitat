extends SceneTree
## Developer tool: digest of the reference campaign ("all") after N days WITHOUT the fields
## that version 4 added to every game (state.bases, the alerts' base field). Compares the
## game itself with an older build.
##   node tools/godot.mjs script res://tests/dev/digest_core.gd <days> [every_day]
const Sim = preload("res://sim/sim.gd")
const Reference = preload("res://sim/reference.gd")
const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var days: float = float(a[0])
	var every: bool = a.size() > 1
	var sim = Sim.new()
	sim.new_game(1001)
	var ref = Reference.new(sim, "all")
	var tick := 0
	while tick < int(days * 6000):
		if tick % 10 == 0:
			ref.drive()
		sim.step()
		tick = int(sim.state["tick"])
		if every and tick % 6000 == 0:
			print("day %d %s" % [tick / 6000, _core(sim)])
	print("core digest %s alive %d" % [_core(sim), sim.alive_count()])
	quit(0)

func _core(sim) -> String:
	var s: Dictionary = sim.state.duplicate(true)
	s.erase("bases")
	for k in s.get("issues", {}):
		s["issues"][k].erase("base")
	return Persistence.digest(s).substr(0, 16)
