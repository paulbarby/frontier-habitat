extends "res://ui/screens/screen.gd"
## Settings: graphics quality (view.set_quality), interface scale, glass blur, camera
## (edge pan, speed), audio volumes per bus, and the key reference. Saved at once to
## user://settings.json and applied by presentation/main.gd.

const Settings = preload("res://ui/settings.gd")

func _init() -> void:
	compact = true
	compact_size = Vector2(760, 0)
	pauses = true
	icon = "settings"
	title = "Settings"
	subtitle = "Changes apply at once and are kept on this device."

func build() -> void:
	var cols: HBoxContainer = Kit.hbox(18)
	content.add_child(cols)
	var left: VBoxContainer = Kit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right: VBoxContainer = Kit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	# Graphics
	var g: VBoxContainer = card("Graphics", "graphics", P.CYAN)
	left.add_child(card_panel(g))
	var q: int = int(Settings.get_value("quality"))
	var qrow: HBoxContainer = Kit.hbox(4)
	g.add_child(Kit.dim("Quality", 13))
	g.add_child(qrow)
	var qnames := ["Low", "Medium", "High", "Ultra"]
	var qbtns: Array = []
	for i in 4:
		var n: int = i
		var b: Button = Kit.button(qnames[i], func():
			Settings.set_value("quality", n)
			hud.main.apply_settings()
			for k in qbtns.size():
				(qbtns[k] as Button).set_pressed_no_signal(k == n), "", "ChipButton")
		b.toggle_mode = true
		b.set_pressed_no_signal(i == q)
		b.custom_minimum_size = Vector2(76, 30)
		qrow.add_child(b)
		qbtns.append(b)
	if not hud.main.view.has_method("set_quality"):
		g.add_child(Kit.label("The 3D view does not support quality levels yet.", "SmallLabel", 11, P.TEXT_3))
	g.add_child(_toggle("Glass blur behind panels", "glass", "Blurs the world behind glass panels. Off is faster on slow graphics cards."))
	# Interface
	var ui: VBoxContainer = card("Interface", "ui_scale", P.CYAN)
	left.add_child(card_panel(ui))
	ui.add_child(_slider("Interface scale", "ui_scale", 0.8, 1.4, 0.05, func(v): return "%d%%" % int(roundf(v * 100.0))))
	ui.add_child(_toggle("Tips for new players", "tutorial_tips", "Shows a tip under each open goal in the mission tracker."))
	# Camera
	var cam: VBoxContainer = card("Camera", "camera", P.CYAN)
	left.add_child(card_panel(cam))
	cam.add_child(_toggle("Pan when the mouse touches the screen edge", "edge_pan", ""))
	cam.add_child(_slider("Camera speed", "camera_speed", 0.5, 2.0, 0.1, func(v): return "%d%%" % int(roundf(v * 100.0))))
	cam.add_child(_toggle("Camera shake", "camera_shake", "The camera shakes for quakes, impacts and landings. Off: it stays still."))
	# Audio
	var au: VBoxContainer = card("Sound", "volume", P.CYAN)
	right.add_child(card_panel(au))
	for spec in [["Master", "vol_master"], ["Music", "vol_music"], ["Effects", "vol_sfx"], ["Interface", "vol_ui"], ["Ambience", "vol_ambience"]]:
		au.add_child(_slider(spec[0], spec[1], 0.0, 1.0, 0.05, func(v): return "%d%%" % int(roundf(v * 100.0))))
	if hud.main.audio == null or not hud.main.audio.has_sounds():
		au.add_child(Kit.label("No sound files are installed. The game is silent.", "SmallLabel", 11, P.TEXT_3))
	# Keys
	var k: VBoxContainer = card("Keys", "keyboard", P.CYAN)
	right.add_child(card_panel(k))
	var grid: GridContainer = Kit.grid(2, 14, 3)
	k.add_child(grid)
	for pair in [["W A S D, arrows", "move the camera"], ["Mouse wheel", "zoom"], ["Middle drag, Q E", "turn"], ["Space; 1 2 3", "pause; speed 1x 2x 4x"],
			["R; Z X", "turn; size while placing"], ["Shift + click", "keep placing"], ["Esc; right click", "cancel; menu"], ["F", "follow a colonist"],
			["O", "overlay"], ["Delete", "remove the selection"], ["G T C I P V", "goals, research, colony, inventory, people, awards"], ["H", "hide the interface"]]:
		grid.add_child(Kit.num(pair[0], 12, P.CYAN))
		grid.add_child(Kit.label(pair[1], "", 12, P.TEXT_2))
	var btns: HBoxContainer = Kit.hbox(8, BoxContainer.ALIGNMENT_END)
	content.add_child(btns)
	btns.add_child(Kit.button("Back", func(): host.close(self), "", "PrimaryButton", "check", 14))

func _toggle(text: String, key: String, tip: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Settings.get_value(key))
	c.focus_mode = Control.FOCUS_NONE
	c.tooltip_text = tip
	c.toggled.connect(func(on):
		Settings.set_value(key, on)
		hud.main.apply_settings())
	return c

func _slider(text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> Control:
	var row: HBoxContainer = Kit.hbox(10)
	var l: Label = Kit.dim(text, 13)
	l.custom_minimum_size.x = 110
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(150, 24)
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v: Label = Kit.num(String(fmt.call(s.value)), 13, P.TEXT)
	v.custom_minimum_size.x = 48
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	# Interface scale applies when the drag ends, so the slider does not move under the mouse.
	if key == "ui_scale":
		s.value_changed.connect(func(x): v.text = String(fmt.call(x)))
		s.drag_ended.connect(func(_changed):
			Settings.set_value(key, s.value)
			hud.main.apply_settings())
	else:
		s.value_changed.connect(func(x):
			v.text = String(fmt.call(x))
			Settings.set_value(key, x)
			hud.main.apply_settings())
	return row
