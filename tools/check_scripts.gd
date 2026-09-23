extends SceneTree
## Loads every .gd file under res:// (except tools/) so that parse errors show at once.
##   node tools/godot.mjs check

func _init() -> void:
	var files: Array = []
	_walk("res://", files)
	var bad := 0
	for f in files:
		var s = load(f)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			print("FAILED ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	quit(1 if bad > 0 else 0)

func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub in ["tools", "build", "saves", "docs", "assets"]:
			continue
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
