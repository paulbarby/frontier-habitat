extends SceneTree
## Developer tool: digest of the reference campaign ("all") after N days (to prove that a
## speed change gives the same game).
##   node tools/godot.mjs script res://tests/dev/digest_run.gd <days>
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")

func _init() -> void:
	var days := float(OS.get_cmdline_user_args()[0])
	var g = H.Game.new(1001, false)
	g.ref = Reference.new(g.sim, "all")
	g.run_to_tick(int(days * 6000))
	print("digest ", H.digest(g.sim), " alive ", g.sim.alive_count())
	quit(0)
