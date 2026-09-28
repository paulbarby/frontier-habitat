extends SceneTree
## Storage everywhere (Paul, 2026-09-28: "show if they are full … storage in all habitats needs to be
## shown, and what is stored"), headless, on content/saves/showcase_v4.fhsave:
##   node tools/godot.mjs script res://tools/ui/test_storage.gd
## Every structure that holds items shows a Storage section whose totals match SIM (used, capacity,
## items, FULL); storehouses open on Storage; a full machine says "Output n/n FULL"; the Inventory
## screen's By structure tab lists, sorts, filters and jumps; vehicle cargo shows its fill.

const Storage = preload("res://ui/storage.gd")

var main
var fails := 0
var _n := 0
var _step := 0
var todo: Array = []
var checked := 0
var bad: Array = []
var full_id := -1

func _init() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)

func check(name: String, ok: bool, detail: String = "") -> void:
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + detail) if detail != "" else ""])
	if not ok:
		fails += 1

func _texts(n: Node) -> String:
	var txt := ""
	for l in n.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree():
			txt += (l as Label).text + " | "
	return txt

func _process(_d: float) -> bool:
	_n += 1
	if _n < 8:
		return false
	var hud = main.hud
	var sim = main.sim
	match _step:
		0:
			root.size = Vector2i(1600, 900)
			main._import_bytes(FileAccess.get_file_as_bytes("res://content/saves/showcase_v4.fhsave"))
			main._on_cmd("speed 0")
			sim = main.sim
			# A machine with a full output buffer (test set-up).
			for id in sim.state["buildings"]:
				var b: Dictionary = sim.state["buildings"][id]
				if b["state"] == "active" and int(b.get("inv_out", -1)) != -1 and String(sim.inv.get_inv(int(b["inv_out"])).get("role", "")) == "out" and int(b.get("inv_in", -1)) != -1:
					var free: int = int(sim.inv.get_inv(int(b["inv_out"]))["cap"]) - sim.inv.total(int(b["inv_out"]))
					if free > 0:
						sim.inv.add_new_forced(int(b["inv_out"]), "metal", free, "test")
					full_id = int(id)
					break
			for id in sim.state["buildings"]:
				var b2: Dictionary = sim.state["buildings"][id]
				if b2["state"] == "active" and not Storage.holders(sim, b2).is_empty():
					todo.append(int(id))
			check("structures that hold items in the showcase", todo.size() >= 10, "%d" % todo.size())
			_step = 1
			_n = 6
		1:
			# One structure per two frames: select it, then read its inspector.
			if todo.is_empty():
				check("every structure that holds items shows a Storage section with SIM's totals", bad.is_empty(), "%d checked, bad %s" % [checked, str(bad.slice(0, 4))])
				main.select("building", full_id)
				_step = 3
				_n = 0
				return false
			var id: int = todo[0]
			if not has_meta("sel") or int(get_meta("sel")) != id:
				main.select("building", id)
				set_meta("sel", id)
				_n = 6
				return false
			todo.pop_front()
			checked += 1
			var b: Dictionary = sim.state["buildings"][id]
			var sec: Node = hud.inspector.find_child("StorageSection", true, false)
			if sec == null:
				bad.append("%s: no Storage section (tab %s)" % [b["def"], hud.inspector.tab])
			else:
				var cold: bool = Storage.is_cold(sim, b)
				var blocks: Array = sec.find_children("*", "VBoxContainer", true, false).filter(func(x): return x.has_meta("inv"))
				var hs: Array = Storage.holders(sim, b)
				if blocks.size() != hs.size():
					bad.append("%s: %d blocks for %d holders" % [b["def"], blocks.size(), hs.size()])
				for blk in blocks:
					var iid: int = int(blk.get_meta("inv"))
					var used: int = sim.inv.total(iid)
					var cap: int = int(sim.inv.get_inv(iid)["cap"])
					var lbl: Label = blk.find_child("Used", true, false)
					if lbl == null or not lbl.text.begins_with("%d / %d" % [used, cap]):
						bad.append("%s: shows %s, SIM %d/%d" % [b["def"], lbl.text if lbl != null else "?", used, cap])
					var fullb: Control = blk.find_child("Full", true, false)
					if fullb == null or fullb.visible != (cap > 0 and used >= cap):
						bad.append("%s: FULL %s, SIM %d/%d" % [b["def"], fullb.visible if fullb != null else "?", used, cap])
					var nitems := 0
					for r in sim.inv.get_inv(iid)["items"]:
						if int(sim.inv.get_inv(iid)["items"][r]) > 0:
							nitems += 1
					var rows: Array = blk.find_child("Items", true, false).get_children().filter(func(x): return x.has_meta("item"))
					if rows.size() != nitems:
						bad.append("%s: %d item lines for %d items" % [b["def"], rows.size(), nitems])
			if Storage.holders(sim, b).any(func(h): return String(h["role"]) == "store") and hud.inspector.tab != "storage":
				bad.append("%s: a store opens on %s, not Storage" % [b["def"], hud.inspector.tab])
			_n = 6
		3:
			var b: Dictionary = sim.state["buildings"][full_id]
			var oi: int = int(b["inv_out"])
			var cap: int = int(sim.inv.get_inv(oi)["cap"])
			var blk: Node = null
			var sec: Node = hud.inspector.find_child("StorageSection", true, false)
			if sec != null:
				for x in sec.find_children("*", "VBoxContainer", true, false):
					if x.has_meta("inv") and int(x.get_meta("inv")) == oi:
						blk = x
			var used_t: String = (blk.find_child("Used", true, false) as Label).text if blk != null else ""
			var fullv: bool = blk != null and (blk.find_child("Full", true, false) as Control).visible
			var badge := false
			for l in hud.inspector.find_children("*", "Label", true, false):
				if (l as Label).text == "FULL" and not sec.is_ancestor_of(l):
					badge = true
			check("a full machine: 'Output %d / %d (100%%)' with FULL, and FULL in the header" % [cap, cap], used_t.begins_with("%d / %d  (100%%)" % [cap, cap]) and fullv and badge, "%s: %s full %s header %s" % [b["def"], used_t, fullv, badge])
			main._on_cmd("open inventory")
			hud.screens.top_screen().set_tab("structures")
			_step = 4
			_n = 0
		4:
			var top = hud.screens.top_screen()
			check("By structure: the item rows of the last tab are dropped (freed labels; a web fault before)", (top._rows as Dictionary).is_empty())
			var rows: Array = top.st_rows
			var sorted := true
			for i in range(1, rows.size()):
				if float(rows[i]["frac"]) > float(rows[i - 1]["frac"]) + 0.0001:
					sorted = false
			var has_full := false
			for r in rows:
				if int(r["id"]) == full_id and bool(r["full"]):
					has_full = true
			check("By structure: every structure with stock, fullest first, the full machine flagged", rows.size() >= 5 and sorted and has_full, "%d rows" % rows.size())
			var bases: Array = sim.bases.list()
			if bases.size() > 1:
				top._st_base = int(bases[1]["id"])
				top._build_tab_content()
				var only := true
				for r in top.st_rows:
					if int(r["base"]) != int(bases[1]["id"]):
						only = false
				check("By structure: the base filter keeps one base", only and top.st_rows.size() < rows.size(), "%d rows at %s" % [top.st_rows.size(), bases[1]["name"]])
				top._st_base = -1
				top._build_tab_content()
			top._st_sort = "name"
			top._build_tab_content()
			var byname := true
			for i in range(1, top.st_rows.size()):
				if String(top.st_rows[i]["name"]).naturalnocasecmp_to(String(top.st_rows[i - 1]["name"])) < 0:
					byname = false
			check("By structure: sort by name", byname)
			# Click the first building row: the screen closes and the structure is selected.
			var target: Dictionary = {}
			for r in top.st_rows:
				if String(r["kind"]) == "building":
					target = r
					break
			var btn: Button = null
			for c in top.content.find_children("*", "Button", true, false):
				if (c as Button).tooltip_text.begins_with(String(target["name"]) + "\n"):
					btn = c
					break
			if btn != null:
				btn.pressed.emit()
			check("By structure: a click selects the structure", btn != null and main.view.selected_kind == "building" and main.view.selected_id == int(target.get("id", -1)), str(target.get("name", "")))
			main._on_cmd("closeall")
			main._on_cmd("open vehicles")
			_step = 5
			_n = 0
		5:
			var top = hud.screens.top_screen()
			check("vehicle cargo shows its fill", top.content.find_child("CargoStorage", true, false) != null)
			main._on_cmd("closeall")
			print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
			quit(1 if fails > 0 else 0)
	return false
