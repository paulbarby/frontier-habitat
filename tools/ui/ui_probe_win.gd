extends SceneTree
## Probe (UI, 2026-10-03): the controls that make a window wider than the right quarter allows.
##   node tools/godot.mjs script res://tools/ui/ui_probe_win.gd -- <person|reactor|orders|follow> 1280x720
var main
var _n := 0
var _name := "person"
func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
func _walk(c: Node, limit: float, out: Array) -> void:
	if not (c is Control) or not (c as Control).visible:
		return
	var ctl: Control = c
	if ctl.get_combined_minimum_size().x <= limit:
		return
	var deeper := false
	for k in c.get_children():
		if k is Control and (k as Control).visible and (k as Control).get_combined_minimum_size().x > limit:
			deeper = true
			_walk(k, limit, out)
	if not deeper:
		var txt := ""
		if ctl is Label:
			txt = "'%s' wrap %d clip %s" % [(ctl as Label).text.left(40), (ctl as Label).autowrap_mode, str((ctl as Label).clip_text)]
		elif ctl is Button:
			txt = "'%s'" % (ctl as Button).text.left(30)
		out.append("%s %s w=%d custom=%s parent=%s %s" % [ctl.get_class(), ctl.name, int(ctl.get_combined_minimum_size().x), str(ctl.custom_minimum_size.x), ctl.get_parent().get_class(), txt])
func _process(_d: float) -> bool:
	_n += 1
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if _n == 6:
		_name = args[0] if args.size() > 0 else "person"
		var wh: PackedStringArray = (args[1] if args.size() > 1 else "1280x720").split("x")
		root.size = Vector2i(int(wh[0]), int(wh[1]))
		root.content_scale_size = Vector2i.ZERO
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))
		main._on_cmd("speed 0")
		main.leave_title()
		if args.size() > 2:
			main._on_cmd("uiscale %s" % args[2])
	if _n == 20:
		var hud = main.hud
		var ids: Array = []
		for r in hud.v5.people():
			if String(r["kind"]) == "colonist":
				ids.append(int(r["id"]))
		match _name:
			"person": hud.open_person(int(ids[0]), "file")
			"reactor": hud.reactor_win.visible = true
			"orders": hud.orders.visible = true
			"follow":
				for i in ids:
					if main.follow_person(int(i)):
						break
	if _n == 50:
		var c: Control = {"person": main.hud.person, "reactor": main.hud.reactor_win, "orders": main.hud.orders, "follow": main.hud.follow_hud}[_name]
		var vp: Vector2 = main.hud.root.get_viewport_rect().size
		var allow: float = c.get_global_rect().size.x
		print("WIN ", _name, " rect ", c.get_global_rect(), " min ", c.get_combined_minimum_size(), " zone right x ", vp.x * 0.75)
		var out: Array = []
		_walk(c, maxf(100.0, (vp.x * 0.25 - 80.0) - 40.0), out)
		for o in out:
			print("  ", o)
		quit(0)
		return true
	return false
