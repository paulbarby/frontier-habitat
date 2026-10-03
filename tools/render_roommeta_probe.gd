extends SceneTree
## RENDER (debug): the baked room meta of named rooms (fx_nav.room_meta).
func _initialize() -> void:
	var Nav = load("res://presentation/fx_nav.gd")
	for id in OS.get_cmdline_user_args():
		var m: Dictionary = Nav.room_meta(id)
		print(id, ": shell ", m.get("shell", "-"), " upper_z ", m.get("upper_z", "-"), " keys ", m.keys())
	quit()
