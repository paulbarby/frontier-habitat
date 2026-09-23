extends RefCounted
## Boot parameters and the automation hook (docs/AAA_DESIGN.md §14).
##
## The same parameters come from the URL query in the browser (?seed=1001&demo=1)
## or from user arguments on the desktop (-- --seed=1001 --demo=1).
## In the browser, window.__fh = {ready, tick, day, last, fps, title, cmd(text)} lets
## tools/shoot.mjs wait for the game and drive it without any window on the desktop.
## title = the open screen ("" in play, "title" on the title screen); fps = frames per second.

static func params() -> Dictionary:
	var out := {}
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search || ''", true)
		if typeof(q) == TYPE_STRING:
			for pair in String(q).trim_prefix("?").split("&", false):
				var kv: PackedStringArray = pair.split("=", true, 1)
				out[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else "1"
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out

static func has(p: Dictionary, key: String) -> bool:
	return p.has(key) and String(p[key]) != "0" and String(p[key]) != ""

## window.__fh with a cmd() function. `handler` is Callable(text: String) -> String.
## Keep the returned object alive (store it), or the callback is freed.
static func install_js_hook(handler: Callable):
	if not OS.has_feature("web"):
		return null
	JavaScriptBridge.eval("window.__fh = window.__fh || {ready:false, tick:0, day:0, last:'', fps:0, title:''};", true)
	var fh = JavaScriptBridge.get_interface("__fh")
	var cb = JavaScriptBridge.create_callback(func(args: Array):
		var text: String = String(args[0]) if args.size() > 0 else ""
		fh.last = String(handler.call(text)))
	fh.cmd = cb
	return {"fh": fh, "cb": cb}

static func set_state(hook, ready: bool, tick: int, day: int) -> void:
	if hook == null:
		return
	hook["fh"].ready = ready
	hook["fh"].tick = tick
	hook["fh"].day = day

static func set_extra(hook, fps: float, screen: String) -> void:
	if hook == null:
		return
	hook["fh"].fps = snappedf(fps, 0.1)
	hook["fh"].title = screen
