extends Control
## Door sectors on the wall ring (docs/V3_1_DESIGN.md §3, coordinator item 2026-09-25):
## where a corridor may meet a room. Green arcs = a corridor may join there; red = blocked by
## room equipment (and an airlock's chamber and porch side).
## Shown while placing a room (on the ghost, turning with R) and while drawing a corridor
## (on the first room and on the room under the mouse, with a dot where the corridor meets the
## wall). Drawn in 2D: the ring points are projected from the ground to the screen, so it
## needs nothing from the 3D view. Hidden, with nothing drawn, in every other tool.
## Data: SIM's rule, hud.data.door_angle_free (sim.place.link_angle_ok_for), the same test
## that refuses a corridor with code door_blocked.

const P = preload("res://ui/theme/palette.gd")

const SEGMENTS := 96
const FREE := Color(0.37, 0.88, 0.48, 0.85)
const BLOCKED := Color(1.0, 0.35, 0.37, 0.95)

var hud
var _rings: Array = []    # [{c: Vector2, r: float, def, size, rot, mark: float or null}]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_d: float) -> void:
	if hud == null or hud.main == null or hud.main.sim == null:
		return
	var rings: Array = _collect()
	if rings.is_empty() and _rings.is_empty():
		return
	_rings = rings
	queue_redraw()

func _is_room(def_id: String) -> bool:
	return String(hud.data.bdef(def_id).get("kind", "")) == "room"

func _collect() -> Array:
	var m = hud.main
	var d = hud.data
	var out: Array = []
	if m.tool == "place" and _is_room(m.tool_def) and m.hover_point != null:
		var c: Vector2 = m.sim.place.snap_pos(m.hover_point)
		var r: float = float(d.size_def(m.tool_def, m.tool_size).get("radius", 4.0))
		out.append({"c": c, "r": r, "def": m.tool_def, "size": m.tool_size, "rot": m.tool_rot, "mark": null})
	elif m.tool == "link" and m.tool_def == "corridor":
		var blds: Dictionary = m.sim.state["buildings"]
		var from_id: int = m.link_from
		var to_id: int = int(m.hover_pick.get("id", -1)) if String(m.hover_pick.get("kind", "")) == "building" else -1
		for id in [from_id, to_id]:
			if id == -1 or not blds.has(id) or (id == to_id and to_id == from_id):
				continue
			var b: Dictionary = blds[id]
			if not _is_room(String(b["def"])):
				continue
			# The corridor meets this wall toward the other end.
			var other = null
			if id == from_id:
				other = blds[to_id]["pos"] if to_id != -1 and blds.has(to_id) and to_id != from_id else m.hover_point
			elif from_id != -1 and blds.has(from_id):
				other = blds[from_id]["pos"]
			var mark = null
			if other != null and (other as Vector2).distance_to(b["pos"]) > 0.5:
				mark = ((other as Vector2) - (b["pos"] as Vector2)).angle()
			out.append({"c": b["pos"], "r": float(b.get("radius", 4.0)), "def": String(b["def"]), "size": int(b.get("size", 1)), "rot": float(b.get("rot", 0.0)), "mark": mark})
	return out

func _screen(p: Vector2, cam: Camera3D):
	var p3: Vector3 = hud.main.view.to3(p, 0.15)
	if cam.is_position_behind(p3):
		return null
	return cam.unproject_position(p3)

func _draw() -> void:
	var cam: Camera3D = hud.main.rig.camera if hud.main.rig != null else null
	if cam == null:
		return
	var d = hud.data
	for ring in _rings:
		var c: Vector2 = ring["c"]
		var r: float = float(ring["r"]) + 0.35
		var prev = null
		var prev_free := true
		for i in SEGMENTS + 1:
			var ang: float = TAU * float(i) / float(SEGMENTS)
			var q = _screen(c + Vector2(r, 0).rotated(ang), cam)
			var free: bool = d.door_angle_free(String(ring["def"]), int(ring["size"]), float(ring["rot"]), ang + TAU * 0.5 / float(SEGMENTS))
			if prev != null and q != null:
				draw_line(prev, q, FREE if prev_free else BLOCKED, 3.0 if prev_free else 4.0, true)
			prev = q
			prev_free = free
		if ring["mark"] != null:
			var mk: float = float(ring["mark"])
			var ok: bool = d.door_angle_free(String(ring["def"]), int(ring["size"]), float(ring["rot"]), mk)
			var q2 = _screen(c + Vector2(r, 0).rotated(mk), cam)
			if q2 != null:
				draw_circle(q2, 7.0, Color(0, 0, 0, 0.55))
				draw_circle(q2, 5.0, FREE if ok else BLOCKED)
