extends SceneTree
## Developer tool: watches one alert key in a Frontier reference game (or a save): when it is
## raised, when it goes live / not live, when it clears, and its text.
##   node tools/godot.mjs script res://tests/dev/alert_watch.gd <key> <days> [save]
const H = preload("res://tests/helpers.gd")
const Reference = preload("res://sim/reference.gd")
func _init() -> void:
	var a: Array = OS.get_cmdline_user_args()
	var key: String = String(a[0]) if a.size() > 0 else "output_blocked"
	var days: float = float(a[1]) if a.size() > 1 else 3.0
	var g = H.Game.new(1001, false)
	var sim = g.sim
	if a.size() > 2:
		sim.load_state(preload("res://sim/persistence.gd").decode(FileAccess.get_file_as_bytes(String(a[2])))["state"])
	else:
		sim.new_game(1001, "frontier")
		g.ref = Reference.new(sim, "all")
	var end_t: int = g.tick() + int(days * 6000.0)
	var on := false
	var live := false
	var n_on := 0
	var n_live := 0
	var text := ""
	while g.tick() < end_t:
		g.step()
		if g.tick() % 10 != 0:
			continue
		var iss = sim.state["issues"].get(key)
		var now_on: bool = iss != null
		var now_live: bool = now_on and bool(iss.get("live", true))
		if now_on != on:
			n_on += 1
			print("t %d: %s %s" % [g.tick(), "RAISED" if now_on else "CLEARED", String(iss["text"]) if now_on else ""])
		elif now_on and now_live != live:
			n_live += 1
			if n_live <= 12:
				print("t %d: live %s | %s" % [g.tick(), str(now_live), String(iss["text"])])
		if now_on and String(iss["text"]) != text:
			text = String(iss["text"])
		on = now_on
		live = now_live
	print("raise/clear changes %d, live changes %d" % [n_on, n_live])
	g.dispose()
	quit(0)
