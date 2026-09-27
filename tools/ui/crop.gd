extends SceneTree
## Crops a PNG and scales it up (nearest), for close-ups of the frame, rivets and seams.
##   node tools/godot.mjs script res://tools/ui/crop.gd <in.png> <out.png> x,y,w,h [scale=3]

func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	var p: PackedStringArray = a[2].split(",")
	var r := Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
	var s: int = int(a[3]) if a.size() > 3 else 3
	var out := img.get_region(r)
	out.resize(r.size.x * s, r.size.y * s, Image.INTERPOLATE_NEAREST)
	out.save_png(a[1])
	print("crop %s -> %s" % [a[2], a[1]])
	quit(0)
