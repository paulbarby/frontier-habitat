extends SceneTree
## Contact sheet: every PNG in a folder whose name starts with a prefix, as a grid of thumbnails.
##   node tools/godot.mjs script res://tools/ui/contact_sheet.gd <dir> <prefix> <out.png> [cols=4] [thumb_w=480]

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 3:
		print("usage: contact_sheet.gd <dir> <prefix> <out.png> [cols] [thumb_w]")
		quit(2)
		return
	var dir: String = a[0]
	var prefix: String = a[1]
	var cols: int = int(a[3]) if a.size() > 3 else 4
	var tw: int = int(a[4]) if a.size() > 4 else 480
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(prefix) and f.ends_with(".png"):
			files.append(f)
	files.sort()
	if files.is_empty():
		print("no files")
		quit(1)
		return
	var first := Image.load_from_file(dir.path_join(files[0]))
	var th: int = int(float(tw) * float(first.get_height()) / float(first.get_width()))
	var rows: int = int(ceil(float(files.size()) / float(cols)))
	var sheet := Image.create(cols * (tw + 6) + 6, rows * (th + 6) + 6, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.12))
	for i in files.size():
		var img := Image.load_from_file(dir.path_join(files[i]))
		img.convert(Image.FORMAT_RGB8)
		img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i(6 + (i % cols) * (tw + 6), 6 + (i / cols) * (th + 6)))
	sheet.save_png(a[2])
	print("sheet %s: %d shots" % [a[2], files.size()])
	for f in files:
		print("  " + f)
	quit(0)
