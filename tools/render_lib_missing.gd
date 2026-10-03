extends SceneTree
## RENDER (debug): clips missing per body library (fx_npc), after a save is loaded.
var main
var f := 0
func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	if main == null or main.sim == null:
		return false
	f += 1
	if f == 2:
		main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v3_late.fhsave"))
		return false
	if f < 200:
		return false
	for k in main.view.npc.libs:
		var lib: Dictionary = main.view.npc.libs[k]
		print("%-12s ok %s tris %s parts %d missing %s" % [k, str(lib.get("ok", false)), str(lib.get("tris", "")), (lib.get("parts", []) as Array).size(), str(lib.get("missing", [])).left(40)])
	return true
