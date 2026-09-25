extends SceneTree
## Prints project settings named on the command line (with their feature overrides if set).
##   node tools/godot.mjs script res://tools/ui/print_setting.gd audio/driver/output_latency
func _init() -> void:
	for k in OS.get_cmdline_user_args():
		print("%s = %s   .web = %s" % [k, str(ProjectSettings.get_setting(k)), str(ProjectSettings.get_setting(k + ".web", "(unset)"))])
	quit()
