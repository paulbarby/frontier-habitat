extends Node3D
## Doorways where corridors meet rooms, and corridor ribs (RENDER, V3_DESIGN §7.2).
##
## For every corridor end on a room whose model has the 32 wall segments (Wall_00..31,
## merged by models.gd into the "Walls" group), the segments that touch the doorway's clear
## opening are hidden with the room's segment mask (shaders/wall_cut.gdshader) and
## assets/models/doorway.glb stands on the wall ring at the link's angle, +X out along the
## corridor. When the hidden segments leave a wider hole than the 2.2 m frame, the frame is
## widened to cover it. The leaves DoorL / DoorR (and their *Top parts) slide 0.75 m apart
## while a colonist is within 2 m, and close after. *Top parts (above the 1.4 m wall) hide
## with the room's roof in the cutaway. A room with no links shows its full wall; the
## airlock keeps its own outer door.
##
## Angles: a segment k spans [k, k+1) x 11.25 deg measured in the model's Blender plane
## (+X towards +Y). Blender +Y is Godot -Z, and a room with sim rotation r has rotation.y =
## -r, so a world content angle theta is Blender angle (r - theta).

const Models = preload("res://presentation/models.gd")
const Nav = preload("res://presentation/fx_nav.gd")
const OPEN_HALF := 0.80      # m: half the clear opening (1.5 m) plus a margin
const FRAME_HALF := 1.10     # m: half the frame width (2.2 m)
const NEAR := 1.6            # m: a body this close to the door centre opens it (V3_1 §3.4)
const CLOSE_AFTER := 0.8     # s after the last body leaves
const MOVE_T := 0.6          # s: leaf travel time, ease in-out
const HIDE_HW := 1.76        # m: wall segments hidden within beta +- asin(HIDE_HW / Rw) (ART-HAB D1)
const PATCH_HW := 1.70       # m: wall patches from asin(PATCH_HW / Rw) outward
const BAND_HW := 1.77        # m: plain patches inside, band patches and the band cap from here (R2)
const DECAL_GROUPS := ["DecalB", "DecalR", "DecalL2", "DecalL3", "DecalL4", "DecalL5"]
const DOOR_RADII := [250, 325, 400, 475, 550, 625, 700, 775, 850, 925]
const FLAT_SHELLS := ["podium", "drum", "setback"]
const SLIDE := 0.75          # m: leaf travel
const RIB_STEP := 2.5        # m between corridor ribs (ART-HAB)

var view
var sim
var doors: Array = []        # [{room, link, h, pos: Vector3, open, top, sz}]
var masks := {}              # room id -> int mask
var hb_masks := {}           # room id -> int mask of hidden headboards
var ribs := {}               # link id -> [handles]
var patches: Array = []      # wall_patch handles (close the hidden span beside a doorway)
## Paul 2026-09-26: patch pieces that stand above the 1.40 m cut (upper patches, upper band,
## upper band caps), by room: hidden whole while that room's roof is open.
var cut_patches := {}        # room id -> [handles]
var _cut_shown := {}         # room id -> true while its tall patches are drawn
const CUT_H := 1.42

func _flush_cut(rid: int, start: int) -> void:
	if not view.bmeta.has(rid):
		return
	var fy: float = (view.bmeta[rid]["xf"] as Transform3D).origin.y
	var list: Array = []
	for i in range(start, patches.size()):
		var h: int = patches[i]
		if not view.inst.handles.has(h):
			continue
		var e: Dictionary = view.inst.handles[h]
		var tpl: Dictionary = view.inst.batches[e["key"]]["tpl"]
		var top: float = ((e["xf"] as Transform3D) * (tpl["aabb"] as AABB)).end.y - fy
		if top > CUT_H:
			list.append(h)
	if not list.is_empty():
		cut_patches[rid] = list
		_cut_shown[rid] = true

func _sync_cut_patches() -> void:
	for rid in cut_patches:
		var rm = view.bmeta.get(rid)
		var show: bool = rm == null or float(rm["open"]) <= 0.0
		if show == bool(_cut_shown.get(rid, true)):
			continue
		_cut_shown[rid] = show
		for h in cut_patches[rid]:
			if not view.inst.handles.has(h):
				continue
			var e: Dictionary = view.inst.handles[h]
			for g in view.inst.batches[e["key"]]["tpl"].get("groups", {}):
				view.inst.set_hidden(h, g, not show)
var dirty := true
var tpl := {}
var have_doorway := false
## Test staging only (__fhr "doors <room> red"): that room's doors show the red (locked) state.
var force_red := {}
var slide := {"DoorL": Vector3(0, 0, 1), "DoorR": Vector3(0, 0, -1)}
var stats := {"doors": 0, "rooms_cut": 0, "ribs": 0}
var tall_stats := {}          # "<def>_<size>" -> "n of m hidden" (Tall_* near doorways, P5)
var force_open := {}         # test staging only (__fhr "doors"): room id -> true
var _t := 0.0
var _door_tpls := {}         # file id -> template (status-tinted, accent-tinted, no shadow)
var sign_rot := {}           # room id -> NameSign rotation (rad) applied

func setup(v) -> void:
	view = v
	sim = v.sim
	doors = []
	masks = {}
	ribs = {}
	dirty = true
	have_doorway = Models.has_model("doorway")
	if have_doorway:
		tpl = Models.no_shadow(Models.accent_tinted(Models.prop(["doorway"], 1.2, "room", "logistics")))
		# Each leaf slides away from the middle of the opening (from its own bounds).
		for p in tpl["parts"]:
			var g: String = p["group"]
			if g == "DoorL" or g == "DoorR":
				var c: Vector3 = ((p["xf"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()).get_center()
				if absf(c.z) > 0.05:
					slide[g] = Vector3(0, 0, signf(c.z))

## The door kit whose wall radius is nearest to rw (ART-HAB R1); the flat-lid kit on
## flat-roofed shells (F1).
func door_tpl(rw: float, flat: bool) -> Dictionary:
	var best: int = DOOR_RADII[0]
	for r in DOOR_RADII:
		if absf(float(r) / 100.0 - rw) < absf(float(best) / 100.0 - rw):
			best = r
	var id: String = ("doorway_flat_r%d" if flat else "doorway_r%d") % best
	if not Models.has_model(id):
		id = "doorway_r%d" % best
	if not Models.has_model(id):
		id = "doorway"
	if _door_tpls.has(id):
		return _door_tpls[id]
	var tp: Dictionary = Models.no_shadow(Models.accent_tinted(Models.status_tinted(Models.prop([id], 1.2, "room", "logistics"))))
	_door_tpls[id] = tp
	return tp

func _room_id(meta: Dictionary) -> String:
	return String(meta["tpl"].get("key", "")).get_slice("@", 0).get_file().get_basename()

func mark_dirty() -> void:
	dirty = true

func _group_part(meta: Dictionary, g: String) -> Dictionary:
	var t: Dictionary = meta.get("tpl", {})
	if t.is_empty() or not (t["groups"] as Dictionary).has(g):
		return {}
	for p in t["parts"]:
		if p["group"] == g and not bool(p.get("shadow_only", false)):
			return p
	return {}

func _walls_part(meta: Dictionary) -> Dictionary:
	var t: Dictionary = meta.get("tpl", {})
	if t.is_empty() or not (t["groups"] as Dictionary).has("Walls"):
		return {}
	for p in t["parts"]:
		if p["group"] == "Walls":
			return p
	return {}

func _clear() -> void:
	var inst = view.inst
	for d in doors:
		inst.remove(d["h"])
	doors = []
	for lid in ribs:
		for hh in ribs[lid]:
			inst.remove(hh)
	ribs = {}
	for hh in patches:
		inst.remove(hh)
	patches = []
	for rid in masks:
		if view.bmeta.has(rid) and int(view.bmeta[rid]["h"]) != -1:
			inst.set_group_custom(view.bmeta[rid]["h"], "Walls", Color(0, 0, 0, 0))
			inst.set_group_custom(view.bmeta[rid]["h"], "WallsIn", Color(0, 0, 0, 0))
			inst.set_group_custom(view.bmeta[rid]["h"], "WallsUp", Color(0, 0, 0, 0))
			inst.set_group_custom(view.bmeta[rid]["h"], "Tall", Color(0, 0, 0, 0))
			for g in DECAL_GROUPS:
				inst.set_group_custom(view.bmeta[rid]["h"], g, Color(0, 0, 0, 0))
	masks = {}
	hb_masks = {}

func _rebuild() -> void:
	dirty = false
	stats["rebuilds"] = int(stats.get("rebuilds", 0)) + 1
	stats["junctions"] = 0
	stats["junction_posts"] = 0
	tall_stats = {}
	_clear()
	var inst = view.inst
	var blds: Dictionary = sim.state["buildings"]
	var seg: float = TAU / float(Models.WALL_SEGMENTS)
	var rib_tpl: Dictionary = Models.no_shadow(Models.prop(["corridor_rib"], 1.2, "room", "logistics")) if Models.has_model("corridor_rib") else {}
	var patch_tpl: Dictionary = Models.no_shadow(Models.accent_tinted(Models.prop(["wall_patch"], 1.0, "room", "logistics"))) if Models.has_model("wall_patch") else {}
	# Doors per room first (two links close together share one hidden span).
	var per_room := {}
	for lid in blds:
		var l: Dictionary = blds[lid]
		if l["def"] != "corridor" or l["state"] == "blueprint":
			continue
		for end in [["a", "p0"], ["b", "p1"]]:
			var rid: int = int(l.get(end[0], -1))
			if not blds.has(rid) or not view.bmeta.has(rid):
				continue
			var meta: Dictionary = view.bmeta[rid]
			if meta["mode"] != "inst" or _walls_part(meta).is_empty():
				continue
			var room: Dictionary = blds[rid]
			var theta: float = ((l[end[1]] as Vector2) - (room["pos"] as Vector2)).angle()
			# Model angle (ART-HAB rule): beta = rot - theta (the model frame is mirrored).
			var beta: float = fposmod(float(room["rot"]) - theta, TAU)
			if not per_room.has(rid):
				per_room[rid] = []
			(per_room[rid] as Array).append({"beta": beta, "link": int(lid)})
		# Ribs along the corridor, never scaled: first 1.25 m from the start, every 2.5 m,
		# none within 0.6 m of an end.
		if not rib_tpl.is_empty():
			var p0: Vector2 = l["p0"]
			var p1: Vector2 = l["p1"]
			var ln: float = p0.distance_to(p1)
			var y0: float = view.h(p0.x, p0.y)
			var y1: float = view.h(p1.x, p1.y)
			var tilt: float = atan2(y1 - y0, maxf(0.5, ln))
			var list: Array = []
			var s0 := 1.25
			while s0 <= ln - 0.6:
				var t: float = s0 / ln
				var p: Vector2 = p0.lerp(p1, t)
				var basis := Basis(Vector3.UP, -float(l["rot"])) * Basis(Vector3(0, 0, 1), tilt)
				list.append(inst.add(rib_tpl, Transform3D(basis, Vector3(p.x, lerpf(y0, y1, t) + 0.05, p.y))))
				s0 += RIB_STEP
			ribs[int(lid)] = list
	cut_patches = {}
	var prev_rid := -1
	var prev_start := 0
	for rid in per_room:
		if prev_rid >= 0:
			_flush_cut(prev_rid, prev_start)
		prev_rid = rid
		prev_start = patches.size()
		var meta: Dictionary = view.bmeta[rid]
		var room: Dictionary = blds[rid]
		var s: float = float(meta["tpl"].get("scale", 1.0))
		if String(room["def"]) == "junction" and Models.has_model("junction_post"):
			_junction(rid, meta, room, per_room[rid], seg, patch_tpl)
			continue
		var rw: float = maxf(1.5, float(room["radius"]) - 0.32 * s)
		# ART-HAB D1/R1: the housing reaches +-1.72 m; segments within HIDE_HW go.
		var phi: float = asin(minf(0.99, HIDE_HW / rw))
		var phi2: float = asin(clampf(PATCH_HW / rw, 0.0, 0.99))
		var phib: float = asin(clampf(BAND_HW / rw, 0.0, 0.99))
		var rmeta: Dictionary = Nav.room_meta(_room_id(meta))
		var has_upper: bool = rmeta.get("upper_z") != null or bool(meta["tpl"].get("has_upper", false))
		var flat: bool = String(rmeta.get("shell", "")) in FLAT_SHELLS or has_upper
		var dtpl: Dictionary = door_tpl(rw, flat) if have_doorway else {}
		var room_xf: Transform3D = meta["xf"]
		var accent: Color = (Models.CATEGORY_COLOR.get(String(sim.bdef(room["def"]).get("category", "logistics")), Color(0.8, 0.8, 0.8)) as Color).srgb_to_linear()
		var hidden := {}
		for d in per_room[rid]:
			var beta: float = d["beta"]
			var k0: int = int(floor((beta - phi) / seg))
			var k1: int = int(floor((beta + phi) / seg))
			for k in range(k0, k1 + 1):
				hidden[posmod(k, Models.WALL_SEGMENTS)] = true
			if have_doorway:
				var local := Transform3D(Basis(Vector3.UP, beta), Vector3(rw * cos(beta), 0.0, -rw * sin(beta)))
				var xf: Transform3D = room_xf * local
				var h: int = inst.add(dtpl, xf, accent)
				doors.append({"room": rid, "link": d["link"], "h": h, "pos": xf.origin, "open": 0.0, "top": false, "near_t": -99.0, "want": 0.0, "status": ""})
		var mask := 0
		for k in hidden:
			mask |= 1 << int(k)
		masks[rid] = mask
		# Tall_* parts (headboards, screens, racks, signs) whose floor origin is within 2.2 m
		# of a doorway origin are hidden, day and night (ART-HAB P5).
		var hb: Dictionary = _group_part(meta, "Tall")
		if not hb.is_empty():
			var hmask := 0
			for sk in hb.get("seg_pos", {}):
				var sp: Vector3 = hb["seg_pos"][sk]
				for d in per_room[rid]:
					var beta: float = d["beta"]
					var dl := Vector3(rw * cos(beta), sp.y, -rw * sin(beta)) / maxf(s, 0.001)
					if Vector2(sp.x - dl.x, sp.z - dl.z).length() * s < 2.2:
						hmask |= 1 << int(sk)
			hb_masks[rid] = hmask
			var nh := 0
			for sk in hb.get("seg_pos", {}):
				if hmask & (1 << int(sk)):
					nh += 1
			var tk: String = "%s_%d" % [room["def"], int(room.get("size", 1))]
			tall_stats[tk] = "%d of %d hidden" % [nh, (hb.get("seg_pos", {}) as Dictionary).size()]
		# Patches: the hidden runs of segments minus every doorway's [beta +- phi2].
		if patch_tpl.is_empty() or not have_doorway:
			continue
		var cuts: Array = []
		for d in per_room[rid]:
			cuts.append([float(d["beta"]) - phi2, float(d["beta"]) + phi2])
		var plain_tpl: Dictionary = _plain_patch_tpl()
		var upper_tpl: Dictionary = _prop_tpl("wall_patch_upper", false)
		var cap_tpl: Dictionary = _prop_tpl("band_cap", true)
		var uband_tpl: Dictionary = _prop_tpl("upper_band", true)
		var uz = rmeta.get("upper_z")
		var deck: float = float(uz[1]) if uz is Array and (uz as Array).size() > 1 else float(meta["tpl"].get("upper_deck", 0.0))
		var setback: bool = String(rmeta.get("shell", "")) == "setback"
		var ub = rmeta.get("upper_band")
		# Band caps where the wall band ends beside each housing (R2, F2).
		for d in per_room[rid]:
			for sgn in [-1.0, 1.0]:
				var ca: float = float(d["beta"]) + sgn * phib
				if _in_patch_span(ca, hidden, seg, cuts) and not cap_tpl.is_empty():
					var cxf := Transform3D(Basis(Vector3.UP, ca), Vector3(rw * cos(ca), 0.0, -rw * sin(ca)))
					patches.append(inst.add(cap_tpl, room_xf * cxf, accent))
					if ub is Array and (ub as Array).size() > 1:
						var cz: float = 0.5 * (float(ub[0]) + float(ub[1])) - 1.03
						patches.append(inst.add(cap_tpl, room_xf * Transform3D(cxf.basis, cxf.origin + Vector3(0, cz, 0)), accent))
			# The upper patch over the housing (R3/F2): from 2.24 m to the deck.
			if has_upper and not setback and deck > 2.24 and not upper_tpl.is_empty():
				var hb0: float = float(d["beta"]) - phi2
				var hb1: float = float(d["beta"]) + phi2
				_patch_pieces(hb0, hb1, rw, func(mid: float, ch: float, r: float):
					patches.append(inst.add(upper_tpl, room_xf * Transform3D(Basis(Vector3.UP, mid) * Basis.from_scale(Vector3(1, deck - 2.24, ch)), Vector3(r * cos(mid), 2.24, -r * sin(mid))), accent)))
		for run in _runs(hidden):
			var a0: float = float(run[0]) * seg
			var a1: float = float(run[1] + 1) * seg
			var parts: Array = [[a0, a1]]
			for c in cuts:
				for shift in [-TAU, 0.0, TAU]:
					var c0: float = c[0] + shift
					var c1: float = c[1] + shift
					var nxt: Array = []
					for iv in parts:
						if c1 <= iv[0] or c0 >= iv[1]:
							nxt.append(iv)
							continue
						if c0 > iv[0]:
							nxt.append([iv[0], c0])
						if c1 < iv[1]:
							nxt.append([c1, iv[1]])
					parts = nxt
			for iv in parts:
				# Split at every band boundary (beta +- phib): plain patch inside, band patch outside.
				var cutsb: Array = [float(iv[0]), float(iv[1])]
				for d in per_room[rid]:
					for sgn in [-1.0, 1.0]:
						for shift in [-TAU, 0.0, TAU]:
							var ca: float = float(d["beta"]) + sgn * phib + shift
							if ca > float(iv[0]) and ca < float(iv[1]):
								cutsb.append(ca)
				cutsb.sort()
				for ci in range(cutsb.size() - 1):
					var s0: float = cutsb[ci]
					var s1: float = cutsb[ci + 1]
					var near_door := false
					for d in per_room[rid]:
						var mm: float = absf(angle_difference(float(d["beta"]), (s0 + s1) * 0.5))
						if mm < phib:
							near_door = true
					var ptpl: Dictionary = plain_tpl if near_door and not plain_tpl.is_empty() else patch_tpl
					_patch_pieces(s0, s1, rw, func(mid: float, ch: float, r: float):
						patches.append(inst.add(ptpl, room_xf * Transform3D(Basis(Vector3.UP, mid) * Basis.from_scale(Vector3(1, 1, ch)), Vector3(r * cos(mid), 0.0, -r * sin(mid))), accent))
						if has_upper and not setback and deck > 1.40 and not upper_tpl.is_empty():
							patches.append(inst.add(upper_tpl, room_xf * Transform3D(Basis(Vector3.UP, mid) * Basis.from_scale(Vector3(1, deck - 1.40, ch)), Vector3(r * cos(mid), 1.40, -r * sin(mid))), accent))
						if not near_door and ub is Array and (ub as Array).size() > 1 and not uband_tpl.is_empty():
							patches.append(inst.add(uband_tpl, room_xf * Transform3D(Basis(Vector3.UP, mid) * Basis.from_scale(Vector3(1, float(ub[1]) - float(ub[0]), ch)), Vector3(r * cos(mid), float(ub[0]), -r * sin(mid))), accent)))
	if prev_rid >= 0:
		_flush_cut(prev_rid, prev_start)
	for rid in masks:
		var m: int = masks[rid]
		var mc := Color(float(m & 0xFFFF), float((m >> 16) & 0xFFFF), 0, 0)
		inst.set_group_custom(view.bmeta[rid]["h"], "Walls", mc)
		inst.set_group_custom(view.bmeta[rid]["h"], "WallsIn", mc)
		inst.set_group_custom(view.bmeta[rid]["h"], "WallsUp", mc)
		# Decals hide with the wall segments (ART-HAB D2: the doorway opening + 0.4 m lies
		# inside the hidden span; the patches carry the band there).
		for g in DECAL_GROUPS:
			inst.set_group_custom(view.bmeta[rid]["h"], g, mc)
		_place_sign(rid, m)
	for rid in hb_masks:
		var m2: int = hb_masks[rid]
		inst.set_group_custom(view.bmeta[rid]["h"], "Tall", Color(float(m2 & 0xFFFF), float((m2 >> 16) & 0xFFFF), 0, 0))
	var jn: int = int(stats.get("junctions", 0))
	var jp: int = int(stats.get("junction_posts", 0))
	stats = {"doors": doors.size(), "rooms_cut": masks.size(), "ribs": ribs.size(), "patches": patches.size(), "junctions": jn, "junction_posts": jp, "rebuilds": int(stats.get("rebuilds", 0)), "tall": tall_stats}

## ART-HAB J1: a junction has no doorway.glb. Each link opens a mouth of half angle
## asin(1.20 / Rw); mouths closer than 8 deg merge into one open span; every wall segment a
## span touches is hidden; junction_post.glb stands at each span end (and at the bisector of
## two links of one span that are >= 58 deg apart); junction_sill.glb covers each span in
## pieces of <= 0.45 m chord; wall_patch.glb fills the rest of the hidden segments. No leaves.
func _junction(rid: int, meta: Dictionary, room: Dictionary, links: Array, seg: float, patch_tpl: Dictionary) -> void:
	var inst = view.inst
	var s: float = float(meta["tpl"].get("scale", 1.0))
	var rw: float = maxf(1.0, float(room["radius"]) - 0.32 * s)
	var hm: float = asin(minf(0.99, 1.20 / rw))
	var merge: float = deg_to_rad(8.0)
	var room_xf: Transform3D = meta["xf"]
	var accent: Color = (Models.CATEGORY_COLOR.get(String(sim.bdef(room["def"]).get("category", "logistics")), Color(0.8, 0.8, 0.8)) as Color).srgb_to_linear()
	var post_tpl: Dictionary = Models.no_shadow(Models.accent_tinted(Models.prop(["junction_post"], 1.0, "room", "logistics")))
	var sill_tpl: Dictionary = Models.no_shadow(Models.accent_tinted(Models.prop(["junction_sill"], 1.0, "room", "logistics"))) if Models.has_model("junction_sill") else {}
	var betas: Array = []
	for d in links:
		betas.append(float(d["beta"]))
	betas.sort()
	# Spans [s0, s1, [link angles]], merged in angle order, then across the wrap.
	var spans: Array = []
	for b in betas:
		if not spans.is_empty() and b - hm - float(spans[-1][1]) < merge:
			spans[-1][1] = b + hm
			(spans[-1][2] as Array).append(b)
		else:
			spans.append([b - hm, b + hm, [b]])
	if spans.size() > 1 and float(spans[0][0]) + TAU - float(spans[-1][1]) < merge:
		var first: Array = spans.pop_front()
		spans[-1][1] = float(first[1]) + TAU
		for b in first[2]:
			(spans[-1][2] as Array).append(float(b) + TAU)
	var full: bool = spans.size() == 1 and float(spans[0][1]) - float(spans[0][0]) >= deg_to_rad(352.0)
	var hidden := {}
	var posts: Array = []
	for sp in spans:
		var s0: float = sp[0]
		var s1: float = sp[1]
		if full:
			for k in Models.WALL_SEGMENTS:
				hidden[k] = true
		else:
			for k in range(int(floor(s0 / seg)), int(floor((s1 - 0.0001) / seg)) + 1):
				hidden[posmod(k, Models.WALL_SEGMENTS)] = true
			posts.append(s0)
			posts.append(s1)
		var ls: Array = sp[2]
		for i in ls.size():
			var a: float = ls[i]
			var b: float = ls[(i + 1) % ls.size()] if (i + 1 < ls.size() or full) else INF
			if b == INF:
				continue
			if b <= a:
				b += TAU
			if b - a >= deg_to_rad(58.0):
				posts.append((a + b) * 0.5)
		# Sills over the open span.
		if not sill_tpl.is_empty():
			var a0: float = s0 if not full else 0.0
			var a1: float = s1 if not full else TAU
			var span: float = a1 - a0
			var n: int = maxi(1, int(ceil(2.0 * rw * sin(minf(span, PI) * 0.5) / 0.45)))
			if full:
				n = maxi(n, int(ceil(TAU * rw / 0.45)))
			for i in n:
				var b0: float = a0 + span * i / n
				var b1: float = a0 + span * (i + 1) / n
				var mid: float = (b0 + b1) * 0.5
				var dd: float = b1 - b0
				var ch: float = 2.0 * rw * sin(dd * 0.5) + 0.01
				var r: float = rw * cos(dd * 0.5)
				patches.append(inst.add(sill_tpl, room_xf * Transform3D(Basis(Vector3.UP, mid) * Basis.from_scale(Vector3(1, 1, ch)), Vector3(r * cos(mid), 0.0, -r * sin(mid))), accent))
	for a in posts:
		patches.append(inst.add(post_tpl, room_xf * Transform3D(Basis(Vector3.UP, a), Vector3(rw * cos(a), 0.0, -rw * sin(a))), accent))
	# Patches: the hidden segments outside the open spans.
	if not full and not patch_tpl.is_empty():
		for sp in spans:
			var s0: float = sp[0]
			var s1: float = sp[1]
			for iv in [[floor(s0 / seg) * seg, s0], [s1, (floor((s1 - 0.0001) / seg) + 1.0) * seg]]:
				var span: float = float(iv[1]) - float(iv[0])
				if span * rw < 0.02:
					continue
				var n: int = maxi(1, int(ceil(2.0 * rw * sin(span * 0.5) / 0.45)))
				for i in n:
					var b0: float = float(iv[0]) + span * i / n
					var b1: float = float(iv[0]) + span * (i + 1) / n
					var mid: float = (b0 + b1) * 0.5
					var dd: float = b1 - b0
					var ch: float = 2.0 * rw * sin(dd * 0.5) + 0.01
					var r: float = rw * cos(dd * 0.5)
					patches.append(inst.add(patch_tpl, room_xf * Transform3D(Basis(Vector3.UP, mid) * Basis.from_scale(Vector3(1, 1, ch)), Vector3(r * cos(mid), 0.0, -r * sin(mid))), accent))
	var mask := 0
	for k in hidden:
		mask |= 1 << int(k)
	masks[rid] = mask
	stats["junctions"] = int(stats.get("junctions", 0)) + 1
	stats["junction_posts"] = int(stats.get("junction_posts", 0)) + posts.size()

static var _plain_cache := {}
func _plain_patch_tpl() -> Dictionary:
	return _prop_tpl("wall_patch_plain", true)

func _prop_tpl(id: String, accent: bool) -> Dictionary:
	if not Models.has_model(id):
		return {}
	var key := "%s|%s" % [id, str(accent)]
	if _plain_cache.has(key):
		return _plain_cache[key]
	var tp: Dictionary = Models.prop([id], 1.0, "room", "logistics")
	tp = Models.no_shadow(Models.accent_tinted(tp) if accent else tp)
	_plain_cache[key] = tp
	return tp

## Patch pieces of <= 0.45 m chord over [a0, a1]; fn(mid, chord, radius).
func _patch_pieces(a0: float, a1: float, rw: float, fn: Callable) -> void:
	var span: float = a1 - a0
	if span * rw < 0.02:
		return
	var n: int = maxi(1, int(ceil(2.0 * rw * sin(span * 0.5) / 0.45)))
	for i in n:
		var b0: float = a0 + span * i / n
		var b1: float = a0 + span * (i + 1) / n
		var dd: float = b1 - b0
		fn.call((b0 + b1) * 0.5, 2.0 * rw * sin(dd * 0.5) + 0.01, rw * cos(dd * 0.5))

## True when model angle a lies in a hidden wall run outside every doorway cut.
func _in_patch_span(a: float, hidden: Dictionary, seg: float, cuts: Array) -> bool:
	if not hidden.has(posmod(int(floor(a / seg)), Models.WALL_SEGMENTS)):
		return false
	for c in cuts:
		for shift in [-TAU, 0.0, TAU]:
			if a > float(c[0]) + shift and a < float(c[1]) + shift:
				return false
	return true

## The room-name sign on the free wall segment nearest its default angle (ART-HAB D2).
func _place_sign(rid: int, mask: int) -> void:
	var meta: Dictionary = view.bmeta[rid]
	var sp: Dictionary = _group_part(meta, "NameSign")
	if sp.is_empty():
		return
	var rmeta: Dictionary = Nav.room_meta(_room_id(meta))
	var a0: float
	if rmeta.has("name_sign_deg"):
		a0 = deg_to_rad(float(rmeta["name_sign_deg"]))
	else:
		var c: Vector3 = ((sp["xf"] as Transform3D) * (sp["mesh"] as Mesh).get_aabb()).get_center()
		a0 = atan2(-c.z, c.x)
	var seg: float = TAU / float(Models.WALL_SEGMENTS)
	var best := 0.0
	for step in 33:
		var off: float = seg * float((step + 1) / 2) * (1.0 if step % 2 == 1 else -1.0) if step > 0 else 0.0
		var a: float = a0 + off
		# The plate spans about 0.6 m either side; it needs free segments there.
		var ok := true
		for dk in [-1, 0, 1]:
			if mask & (1 << posmod(int(floor(a / seg)) + dk, Models.WALL_SEGMENTS)):
				ok = false
		if ok:
			best = off
			break
	if absf(best - float(sign_rot.get(rid, 0.0))) > 0.001 or not sign_rot.has(rid):
		sign_rot[rid] = best
		if absf(best) < 0.001:
			view.inst.clear_extra(meta["h"], "NameSign")
		else:
			view.inst.set_extra(meta["h"], "NameSign", Transform3D(Basis(Vector3.UP, best), Vector3.ZERO))

## Contiguous runs [first, last] of hidden segments (a run may wrap past segment 31: then
## last > 31 and is taken mod 32 by the caller's angles).
func _runs(hidden: Dictionary) -> Array:
	var n: int = Models.WALL_SEGMENTS
	if hidden.size() >= n:
		return [[0, n - 1]]
	var out: Array = []
	var start: int = -1
	# Start scanning just after a gap, so no run is split at segment 0.
	var gap: int = 0
	while hidden.has(gap):
		gap += 1
	var i: int = gap + 1
	var count := 0
	while count < n:
		var k: int = posmod(i, n)
		if hidden.has(k):
			if start < 0:
				start = i
		elif start >= 0:
			out.append([start, i - 1])
			start = -1
		i += 1
		count += 1
	if start >= 0:
		out.append([start, i - 1])
	return out
## Door leaves slide open near a colonist; *Top parts follow the room's cutaway.
func sync(delta: float, bodies: Array) -> void:
	_t += delta
	if dirty:
		_rebuild()
	if doors.is_empty() and ribs.is_empty():
		return
	var inst = view.inst
	var grid := {}
	for b in bodies:
		var q: Vector3 = b
		var key: int = int(floor(q.x / 4.0)) * 4096 + int(floor(q.z / 4.0))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(q)
	for d in doors:
		var p: Vector3 = d["pos"]
		var near := false
		var cx: int = int(floor(p.x / 4.0))
		var cz: int = int(floor(p.z / 4.0))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for q in grid.get((cx + dx) * 4096 + cz + dz, []):
					var v: Vector3 = q
					if Vector2(v.x - p.x, v.z - p.z).length() < NEAR and absf(v.y - p.y) < 2.5:
						near = true
						break
		var o: float = float(d["open"])
		if near or force_open.has(int(d["room"])):
			d["near_t"] = _t
		var want: float = 1.0 if _t - float(d["near_t"]) < CLOSE_AFTER else 0.0
		if want != float(d.get("want", 0.0)):
			d["want"] = want
			view.world_sound("door_slide", d["pos"])
		if o != want:
			o = move_toward(o, want, delta / MOVE_T)
			d["open"] = o
			var e: float = o * o * (3.0 - 2.0 * o) * SLIDE
			for g in ["DoorL", "DoorLTop"]:
				inst.set_extra(d["h"], g, Transform3D(Basis(), slide["DoorL"] * e))
			for g in ["DoorR", "DoorRTop"]:
				inst.set_extra(d["h"], g, Transform3D(Basis(), slide["DoorR"] * e))
		var rm = view.bmeta.get(int(d["room"]))
		var top: bool = rm != null and float(rm["open"]) > 0.5
		# ART-HAB J2: an open door's upper leaves stand outside the entry hood: hidden while
		# the door is open (at all), and with the roof in the cutaway.
		# V3.1 (ART-HAB D1): a leaf is never hidden; in the cutaway everything above 1.40 m
		# goes (…Top, Status, Sign).
		if top != bool(d["top"]):
			d["top"] = top
			for g in ["FrameTop", "DoorLTop", "DoorRTop", "Status", "Sign"]:
				inst.set_hidden(d["h"], g, top)
		# Status light: red locked (breach in the room or its corridor, a shelter order),
		# amber while the leaves move, green free.
		var st := "green"
		var blds2: Dictionary = sim.state["buildings"]
		if force_red.has(int(d["room"])) or bool(blds2.get(int(d["room"]), {}).get("breach", false)) or bool(blds2.get(int(d["link"]), {}).get("breach", false)) or bool(sim.state.get("shelter", false)):
			st = "red"
		elif o > 0.001 and o < 0.999:
			st = "amber"
		if st != String(d.get("status", "")):
			d["status"] = st
			var sc: Color = Models.STATUS_RED if st == "red" else (Models.STATUS_AMBER if st == "amber" else Models.STATUS_GREEN)
			inst.set_group_custom(d["h"], "Status", sc)
			inst.set_group_custom(d["h"], "Lights", sc)
	_sync_cut_patches()
	for lid in ribs:
		var lm = view.bmeta.get(int(lid))
		var open: bool = lm != null and float(lm["open"]) > 0.5
		for hh in ribs[lid]:
			inst.set_hidden(hh, "Roof", open)
