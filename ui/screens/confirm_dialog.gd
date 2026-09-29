extends "res://ui/screens/screen.gd"
## A yes/no dialog: a title, the consequences as a list, and two buttons.
## arg: {title, lines, on_yes (Callable, may be invalid = information only), yes, danger}

func _init() -> void:
	compact = true
	compact_size = Vector2(580, 0)
	dim = 0.35
	icon = "sev_warning"

func _ready() -> void:
	var a: Dictionary = arg if typeof(arg) == TYPE_DICTIONARY else {}
	title = String(a.get("title", "Are you sure?"))
	accent = P.RED if bool(a.get("danger", false)) else P.AMBER
	if not (a.get("on_yes", Callable()) as Callable).is_valid():
		icon = "sev_info"
		accent = P.CYAN
	super._ready()

func build() -> void:
	var a: Dictionary = arg if typeof(arg) == TYPE_DICTIONARY else {}
	for line in a.get("lines", []):
		var row: HBoxContainer = Kit.hbox(8)
		if typeof(line) == TYPE_DICTIONARY:
			# A headed line: {head, text, color, icon} (the discipline confirm: on the person, on others, unfair).
			var d: Dictionary = line
			var col: Color = d.get("color", accent)
			row.add_child(Kit.icon(String(d.get("icon", "arrow_right")), 16, col))
			var hv: VBoxContainer = Kit.vbox(0)
			hv.add_child(Kit.head(String(d.get("head", "")).to_upper(), col, 12))
			var dl: Label = Kit.wrap(String(d.get("text", "")), 14, P.TEXT)
			dl.custom_minimum_size.x = 470
			hv.add_child(dl)
			row.add_child(hv)
			content.add_child(row)
			continue
		row.add_child(Kit.icon("arrow_right", 12, accent))
		var l: Label = Kit.wrap(String(line), 14, P.TEXT)
		l.custom_minimum_size.x = 480
		row.add_child(l)
		content.add_child(row)
	content.add_child(Kit.gap(0, 8))
	var btns: HBoxContainer = Kit.hbox(10, BoxContainer.ALIGNMENT_END)
	content.add_child(btns)
	var on_yes: Callable = a.get("on_yes", Callable())
	btns.add_child(Kit.button("Back" if on_yes.is_valid() else "OK", func(): host.close(self), ("Back\nCloses this and changes nothing.") if on_yes.is_valid() else "OK\nCloses this message.", "", "close", 14))
	if on_yes.is_valid():
		var yes: Button = Kit.button(String(a.get("yes", "Yes")), func():
			host.close(self)
			on_yes.call(), "", "DangerButton" if bool(a.get("danger", false)) else "PrimaryButton", "check", 14)
		btns.add_child(yes)
