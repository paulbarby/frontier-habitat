extends SceneTree
## RENDER: the anchor names of room models (Anchor_<name>), grouped by kind.
##   node tools/godot.mjs script res://tools/render_anchor_list.gd residence_tube_l jail_m
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	for id in OS.get_cmdline_user_args():
		var tpl: Dictionary = Models._template_from_file("res://assets/models/%s.glb" % id)
		var kinds := {}
		for a in tpl["anchors"]:
			var k: String = String(a).get_slice("_", 0)
			kinds[k] = kinds.get(k, []) + [String(a)]
		print(id)
		for k in kinds:
			print("  ", k, " ", (kinds[k] as Array).size(), ": ", ", ".join((kinds[k] as Array).slice(0, 12)))
	quit(0)
