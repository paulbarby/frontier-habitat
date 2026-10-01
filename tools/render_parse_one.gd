extends SceneTree
## RENDER scratch: load one script and print whether it compiles (the engine prints the parse error
## with its line). node tools/godot.mjs script res://tools/render_parse_one.gd res://presentation/x.gd
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://presentation/world_view.gd"
	var s = load(path)
	print("PARSE %s -> %s" % [path, "ok" if (s is GDScript and (s as GDScript).can_instantiate()) else "FAILED"])
	quit()
