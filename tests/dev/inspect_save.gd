extends SceneTree
## Developer tool: prints a summary of a save file.
##   node tools/godot.mjs script res://tests/dev/inspect_save.gd res://content/saves/showcase_day9.fhsave

const Persistence = preload("res://sim/persistence.gd")

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://content/saves/showcase_day9.fhsave"
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var inp := StreamPeerBuffer.new()
	inp.data_array = bytes
	inp.seek(8)
	var schema: int = inp.get_u32()
	var raw_len: int = inp.get_u32()
	var raw: PackedByteArray = bytes.slice(16).decompress(raw_len, FileAccess.COMPRESSION_DEFLATE)
	var state = bytes_to_var(raw)
	print("file %s: %d bytes, schema %d, raw %d" % [path, bytes.size(), schema, raw_len])
	print("keys: ", state.keys())
	print("tick %d seed %d scenario %s planet %s next_id %d" % [state["tick"], state["seed"], state["scenario"], state["planet"], state["next_id"]])
	var defs := {}
	for id in state["buildings"]:
		var b: Dictionary = state["buildings"][id]
		defs[b["def"]] = int(defs.get(b["def"], 0)) + 1
	print("buildings: ", defs)
	var first: Dictionary = state["buildings"][state["buildings"].keys()[0]]
	print("building keys: ", first.keys())
	var roles := {}
	for aid in state["agents"]:
		var a: Dictionary = state["agents"][aid]
		roles[a["role"] + ":" + a["state"]] = int(roles.get(a["role"] + ":" + a["state"], 0)) + 1
	print("agents: ", roles)
	print("agent keys: ", state["agents"][state["agents"].keys()[0]].keys())
	print("ledger: ", state["ledger"])
	print("metrics keys: ", state["metrics"].keys())
	print("metrics.produced: ", state["metrics"]["produced"])
	print("progress: ", state["progress"])
	print("policies: ", state["policies"])
	print("flags: ", state["flags"])
	var roles_inv := {}
	for iid in state["inventories"]:
		var inv: Dictionary = state["inventories"][iid]
		roles_inv[inv["role"]] = int(roles_inv.get(inv["role"], 0)) + 1
	print("inventories by role: ", roles_inv)
	print("tasks: %d holds: %d" % [state["tasks"].size(), state["holds"].size()])
	var kinds := {}
	for tid in state["tasks"]:
		kinds[state["tasks"][tid]["kind"]] = int(kinds.get(state["tasks"][tid]["kind"], 0)) + 1
	print("task kinds: ", kinds)
	for id in state["buildings"]:
		var b: Dictionary = state["buildings"][id]
		if not (b["batch"] as Dictionary).is_empty():
			print("batch in %s: %s" % [b["name"], b["batch"]])
	quit(0)
