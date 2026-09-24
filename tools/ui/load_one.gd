extends SceneTree
## Loads the scripts named on the command line and prints the engine's parse errors.
##   node tools/godot.mjs script res://tools/ui/load_one.gd res://ui/hud/alerts_panel.gd

func _init() -> void:
	for p in OS.get_cmdline_user_args():
		var s = load(p)
		print("%s %s" % ["OK" if s != null and (s as GDScript).can_instantiate() else "FAILED", p])
	quit()
