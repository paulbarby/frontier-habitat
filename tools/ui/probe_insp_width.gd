extends SceneTree
## Finds what makes the inspector wider than its design width: prints the deepest controls whose
## minimum width is more than the content width, per selected type and tab.
##   node tools/godot.mjs script res://tools/ui/probe_insp_width.gd

var main
var _n := 0
var _i := 0
const PICKS := ["research_lab", "kitchen", "habitat", "oxygen_plant", "landing_pad", "super_dome", "retail", "cantina", "hr_office", "agent"]

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _walk(c: Node, limit: float, depth: int, out: Array) -> void:
	if not (c is Control) or not (c as Control).visible:
		return
	var ctl: Control = c
	var w: float = ctl.get_combined_minimum_size().x
	if w <= limit:
		return
	var deeper := false
	for k in c.get_children():
		if k is Control and (k as Control).visible and (k as Control).get_combined_minimum_size().x > limit:
			deeper = true
			_walk(k, limit, depth + 1, out)
	if not deeper:
		if ctl is Label:
			var lb: Label = ctl
			out.append("  [label wrap %d clip %s custom %s parent %s flags %d]" % [lb.autowrap_mode, str(lb.clip_text), str(lb.custom_minimum_size), lb.get_parent().get_class(), lb.size_flags_horizontal])
		var txt := ""
		if ctl is Label:
			txt = (ctl as Label).text
		elif ctl is Button:
			txt = (ctl as Button).text
		out.append("%s %s w=%d '%s'" % [ctl.get_class(), ctl.name, int(w), txt.left(60)])

func _process(_d: float) -> bool:
	_n += 1
	if _n == 6:
		# The view size comes from the first user argument: "1300x731" (the inspector keeps to the right quarter).
		var wh: PackedStringArray = (OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "1600x900").split("x")
		root.size = Vector2i(int(wh[0]), int(wh[1]))
		root.content_scale_size = Vector2i.ZERO
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
	if _n > 10 and _n % 6 == 0:
		if _i >= PICKS.size() * 2:
			quit(0)
			return false
		var pick: String = PICKS[_i / 2]
		if _i % 2 == 0:
			print(main._on_cmd("select " + pick) if pick != "agent" else main._on_cmd("select agent"))
		else:
			var insp: Control = main.hud.inspector
			var tabs: Array = insp._tabs.get_children()
			print("== %s size %s width %d tabs %d view %s wa %s rect %s" % [pick, str(insp.size), int(insp.width), tabs.size(), str(main.hud.root.get_viewport_rect().size), str(main.hud.wm.work_area()), str(insp.get_global_rect())])
			for tb in [null] + tabs:
				if tb != null:
					(tb as Button).pressed.emit()
					insp.refresh()
				var out: Array = []
				_walk(insp, insp.width - 42.0, 0, out)
				print("  tab %s: %s" % [(tb as Button).text if tb != null else "-", str(out)])
		_i += 1
	return false
