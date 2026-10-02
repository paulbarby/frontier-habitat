extends SceneTree
const Sim = preload("res://sim/sim.gd")
const Persistence = preload("res://sim/persistence.gd")
func _init() -> void:
	var sim = Sim.new()
	sim.load_state(Persistence.decode(FileAccess.get_file_as_bytes("res://content/saves/showcase_v5.fhsave"))["state"])
	sim.run_seconds(20.0)
	var st = sim.state
	print("holds %d tasks %d buildings %d inventories %d" % [st["holds"].size(), st["tasks"].size(), st["buildings"].size(), st["inventories"].size()])
	var t0: int = Time.get_ticks_usec()
	for i in 200:
		sim.jobs._index()
	print("_index %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200000.0))
	t0 = Time.get_ticks_usec()
	for i in 200:
		var _inb := {}
		for hid in st["holds"]:
			var h: Dictionary = st["holds"][hid]
			if h["dir"] == "in":
				var k := "%d:%s" % [h["inv"], h["res"]]
				_inb[k] = int(_inb.get(k, 0)) + int(h["qty"])
	print("  holds %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200000.0))
	t0 = Time.get_ticks_usec()
	for i in 200:
		var cnt := {}
		var bb := {}
		for tid in st["tasks"]:
			var t: Dictionary = st["tasks"][tid]
			var key := "%s:%d" % [t["kind"], t["bld"]]
			if t["kind"] == "tend":
				key += ":%d" % t["tray"]
			cnt[key] = int(cnt.get(key, 0)) + 1
			if int(t["bld"]) != -1:
				if not bb.has(t["bld"]):
					bb[t["bld"]] = []
				bb[t["bld"]].append(t)
	print("  tasks %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200000.0))
	t0 = Time.get_ticks_usec()
	for i in 200:
		var cold := {}
		for id in st["buildings"]:
			var b: Dictionary = st["buildings"][id]
			if b["state"] == "active" and int(b["inv_out"]) != -1 and bool(sim.bdef(b["def"]).get("cold", false)):
				cold[int(b["inv_out"])] = true
	print("  cold %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200000.0))
	t0 = Time.get_ticks_usec()
	for i in 200:
		var si := {}
		for inv_id in st["inventories"]:
			var inv: Dictionary = st["inventories"][inv_id]
			var role: String = inv["role"]
			if role != "pile" and role != "out" and role != "store":
				continue
			for r in inv["items"]:
				if not si.has(r):
					si[r] = []
				si[r].append(inv_id)
	print("  src %.3f ms" % (float(Time.get_ticks_usec() - t0) / 200000.0))
	quit(0)
