extends SceneTree
## Runs main.tscn headless (no window) for N frames with boot parameters, then runs
## automation commands, to find script errors and crashes outside the browser.
##   node tools/godot.mjs script res://tools/ui/run_main.gd --seed=1001 --title=0 --frames=120 --cmds="hudpart minimap off;fast 5"

var _main
var _frames := 120
var _cmds: Array = []
var _n := 0

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frames="):
			_frames = int(a.substr(9))
		elif a.begins_with("--cmds="):
			_cmds = Array(a.substr(7).split(";", false))
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	print("run_main: main added")

func _process(_delta: float) -> bool:
	_n += 1
	if _n == 5:
		for c in _cmds:
			print("cmd %s -> %s" % [c, _main._on_cmd(String(c))])
	if _n % 30 == 0:
		print("frame %d tick %d" % [_n, int(_main.sim.state["tick"])])
	if _n >= _frames:
		print("run_main: done, %d frames, world %d m, minimap image %s" % [_n, int(_main.sim.world.size), str(_main.hud.minimap._base.get_size()) if _main.hud.minimap._base != null else "none"])
		return true
	return false
