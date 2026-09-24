extends RefCounted
## The focus selector of one research lab (docs/V3_DESIGN.md §5.2): a row "Focus [branch v]".
## A lab with a focus makes +25% RP for projects of that branch and -10% for the others.
## Sends the command set_focus {id, branch} ("" = no focus). Used by the inspector and the
## research screen.

const P = preload("res://ui/theme/palette.gd")
const Kit = preload("res://ui/kit.gd")

static func make(hud, lab_id: int, compact: bool = false) -> HBoxContainer:
	var d = hud.data
	var row: HBoxContainer = Kit.hbox(8)
	if not compact:
		var l: Label = Kit.dim("Focus", 13)
		l.custom_minimum_size.x = 60
		row.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(150, 28)
	ob.add_theme_font_size_override("font_size", 12)
	ob.tooltip_text = "Focus\nThis lab makes +25% research points for projects of the chosen branch, and -10% for the others."
	ob.add_item("No focus")
	ob.set_item_metadata(0, "")
	var cur: String = String(d.lab_info(lab_id).get("focus", ""))
	var branches: Dictionary = d.branches()
	var i := 1
	for b in branches:
		ob.add_item(String(branches[b].get("name", b)))
		ob.set_item_metadata(i, String(b))
		if String(b) == cur:
			ob.select(i)
		i += 1
	if cur == "":
		ob.select(0)
	ob.item_selected.connect(func(idx: int):
		var br: String = String(ob.get_item_metadata(idx))
		if d.mock.has("labs") and (d.mock["labs"] as Dictionary).has(lab_id):
			d.mock["labs"][lab_id]["focus"] = br
		else:
			hud.main.submit("set_focus", {"id": lab_id, "branch": br})
		Kit.sfx("select"))
	row.add_child(ob)
	return row
