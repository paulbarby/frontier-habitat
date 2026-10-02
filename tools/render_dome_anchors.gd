extends SceneTree
const Models = preload("res://presentation/models.gd")
func _init() -> void:
	var tpl: Dictionary = Models.dome_template(true)
	var kinds := {}
	for a in tpl["anchors"]:
		var k: String = String(a).get_slice("_", 0)
		kinds[k] = kinds.get(k, []) + [String(a)]
	for k in kinds:
		print(k, " ", (kinds[k] as Array).size(), ": ", ", ".join((kinds[k] as Array).slice(0, 14)))
	var ys := {}
	for a in tpl["anchors"]:
		var y: float = snappedf((tpl["anchors"][a] as Transform3D).origin.y, 0.05)
		ys[y] = int(ys.get(y, 0)) + 1
	var ks: Array = ys.keys()
	ks.sort()
	var line := ""
	for k in ks:
		line += "%.2f:%d " % [k, ys[k]]
	print("ANCHOR Y ", line)
	quit(0)
