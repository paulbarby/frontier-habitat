extends SceneTree
## RENDER check (Paul, 2026-09-26): with every room's cutaway open, no drawn vertex of a room,
## its doorway kits or its wall patches above 1.45 m, apart from the groups meant to stand
## (world_view.CUT_ALLOWED: Interior, Tall). Every room type of the saves.
##   node tools/godot.mjs script res://tools/render_cut_check.gd [label]
## Writes build/web_render/cut_check_<label>.json; prints one line per room type.
const SAVES := ["res://content/saves/showcase_v3_late.fhsave", "res://content/saves/showcase_v31.fhsave", "res://build/web_render/scene_final.fhsave", "res://build/web_render/doors8.fhsave"]
var doors_rep: Array = []
var main
var n := 0
var si := -1
var label := "run"
var res := {}

func _initialize() -> void:
	for s in OS.get_cmdline_user_args():
		if not s.begins_with("--"):
			label = s
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func _process(_d: float) -> bool:
	n += 1
	if n < 3:
		return false
	if si < 0 or n > 40:
		if si >= 0:
			var r: Dictionary = main.view._cut_check()
			_doors(SAVES[si].get_file())
			for k in r:
				if not res.has(k):
					res[k] = r[k]
				else:
					res[k]["rooms"] = int(res[k]["rooms"]) + int(r[k]["rooms"])
					for kk in ["above_cut", "allowed"]:
						for g in r[k][kk]:
							res[k][kk][g] = maxf(float(res[k][kk].get(g, 0.0)), float(r[k][kk][g]))
		si += 1
		if si >= SAVES.size():
			_write()
			return true
		main._import_bytes(FileAccess.get_file_as_bytes(SAVES[si]))
		main.set_speed(0)
		main.view._force_open_all = true
		n = 3
		return false
	main.set_process(false)
	main._process(1.0 / 30.0)
	return false

func _write() -> void:
	var keys: Array = res.keys()
	keys.sort()
	var bad := 0
	for k in keys:
		var r: Dictionary = res[k]
		if not (r["above_cut"] as Dictionary).is_empty():
			bad += 1
		print("CUT %-26s rooms %d | above cut: %s | allowed: %s" % [k, int(r["rooms"]), str(r["above_cut"]) if not (r["above_cut"] as Dictionary).is_empty() else "none", str(r["allowed"])])
	print("CUT TOTAL %d room types, %d with a drawn part above 1.45 m" % [keys.size(), bad])
	var dbad := 0
	for d in doors_rep:
		if not bool(d["ok"]):
			dbad += 1
		if int(d["links"]) >= 4:
			print("DOORS %s %s size %d: links %d, door kits %d, closest kits %.1f deg (housing %.1f deg), hidden wall segments %d%s" % [d["save"], d["def"], d["size"], d["links"], d["kits"], d["gap"], d["need"], d["segs"], "" if d["ok"] else "  <-- FAIL"])
	var leg: int = doors_rep.filter(func(x): return bool(x["legacy"])).size()
	print("DOORS TOTAL %d rooms, %d with a missing or overlapping door kit; %d old-save rooms with links closer than the new rule (kept by SIM)" % [doors_rep.size(), dbad, leg])
	var f := FileAccess.open("res://build/web_render/cut_check_%s.json" % label, FileAccess.WRITE)
	f.store_string(JSON.stringify({"label": label, "types": keys.size(), "types_above_cut": bad, "rooms": res, "doors": doors_rep}, "  "))
	f.close()
	quit(0)

## Paul's links rule (S 4, M 6, L 7, XL 8): every corridor of a room has its door kit, no two kits
## closer than the housing (3.44 m + 0.3 m at radius - 0.32), and the wall mask hides a span for each.
func _doors(save: String) -> void:
	var v = main.view
	var blds: Dictionary = main.sim.state["buildings"]
	for rid in v.bmeta:
		var b: Dictionary = blds.get(rid, {})
		if b.is_empty() or String(b["kind"]) != "room" or String(b["def"]) in ["airlock", "junction"]:
			continue
		var links := 0
		for lid in blds:
			var l: Dictionary = blds[lid]
			if String(l["kind"]) == "link" and String(l["def"]) == "corridor" and (int(l.get("a", -1)) == int(rid) or int(l.get("b", -1)) == int(rid)):
				links += 1
		var angs: Array = []
		for d in v.doors.doors:
			if int(d["room"]) == int(rid):
				var q: Vector3 = d["pos"]
				angs.append(atan2(q.z - (b["pos"] as Vector2).y, q.x - (b["pos"] as Vector2).x))
		var gap := 360.0
		for i in angs.size():
			for j in range(i + 1, angs.size()):
				gap = minf(gap, rad_to_deg(absf(wrapf(float(angs[i]) - float(angs[j]), -PI, PI))))
		var wr: float = float(b["radius"]) - 0.32
		var need: float = rad_to_deg(2.0 * asin(clampf((3.44 + 0.3) * 0.5 / wr, 0.0, 1.0)))
		var mask: int = int(v.doors.masks.get(rid, 0))
		var segs := 0
		while mask != 0:
			segs += mask & 1
			mask >>= 1
		# Links made before Paul's rule are kept by SIM (old saves): a spacing under the rule there is
		# reported as "legacy", not a failure; the doors8 save is built under the rule.
		var spaced: bool = angs.size() < 2 or gap >= need - 0.5
		var ok: bool = angs.size() == links and (spaced or save != "doors8.fhsave")
		doors_rep.append({"save": save, "room": int(rid), "def": String(b["def"]), "size": int(b.get("size", 1)), "links": links, "kits": angs.size(), "gap": snappedf(gap, 0.1), "need": snappedf(need, 0.1), "segs": segs, "ok": ok, "legacy": not spaced and save != "doors8.fhsave"})
