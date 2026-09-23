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
		row.add_child(Kit.icon("arrow_right", 12, accent))
		var l: Label = Kit.wrap(String(line), 14, P.TEXT)
		l.custom_minimum_size.x = 480
		row.add_child(l)
		content.add_child(row)
	content.add_child(Kit.gap(0, 8))
	var btns: HBoxContainer = Kit.hbox(10, BoxContainer.ALIGNMENT_END)
	content.add_child(btns)
	var on_yes: Callable = a.get("on_yes", Callable())
	btns.add_child(Kit.button("Back" if on_yes.is_valid() else "OK", func(): host.close(self), "", "", "close", 14))
	if on_yes.is_valid():
		var yes: Button = Kit.button(String(a.get("yes", "Yes")), func():
			host.close(self)
			on_yes.call(), "", "DangerButton" if bool(a.get("danger", false)) else "PrimaryButton", "check", 14)
		btns.add_child(yes)
