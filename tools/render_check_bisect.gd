extends SceneTree
## RENDER: which scripts make the check crash at exit. Loads the .gd files under one folder.
##   node tools/godot.mjs script res://tools/render_check_bisect.gd <res://folder> [from] [to]
func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var files: Array = []
	for d in a[0].split(","):
		_walk(d, files)
	files.sort()
	var head: String = files[0] if a.size() > 3 else ""
	if head != "":
		load(head)
	var lo: int = int(a[1]) if a.size() > 1 else 0
	var hi: int = int(a[2]) if a.size() > 2 else files.size()
	for i in range(lo, mini(hi, files.size())):
		load(files[i])
	print("loaded %d..%d of %d, last %s" % [lo, mini(hi, files.size()), files.size(), files[mini(hi, files.size()) - 1]])
	quit(0)

func _walk(dir: String, out: Array) -> void:
	if dir.ends_with(".gd"):
		out.append(dir)
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))