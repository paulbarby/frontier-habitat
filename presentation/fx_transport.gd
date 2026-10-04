extends Node3D
## Package transport (V5 §18.5): ART-HAB's models on the upgraded structures and SIM's capsules in the tubes.
##   building.hub (storehouse / cold storage) -> transport_hub_<size>.glb at Anchor_Hub, and transport_port.glb at each
##     of the room's doorways (PortTop hides in the cutaway like the door's FrameTop);
##   building.tube (corridor) -> transport_tube.glb with the corridor's own transform, a transport_bracket.glb with
##     every corridor rib; a junction joined by tubes -> transport_junction.glb plus a short tube from each tube mouth;
##   sim.transport.capsules_view() -> a capsule (one MultiMesh, item colour) moving in each tube.
## The tube, the brackets and the junction piece are `Roof` group parts: they follow the corridor's (junction's) roof
## in the cutaway, and a capsule is not drawn where its tube is cut away.

const Models = preload("res://presentation/models.gd")
const TUBE_Y := 2.305         # m: the tube's centre over the ground in the corridor frame (ART-HAB)
const CAP_R := 0.06
const CAP_LEN := 0.30

var view
var sim
var _key := ""
var _parts := {}              # building id -> [[handle, mirror handle, group]]
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _clock := 0.0
var stats := {"hubs": 0, "tubes": 0, "capsules": 0}

func setup(v) -> void:
	view = v
	sim = v.sim
	name = "Transport"
	var cm := CapsuleMesh.new()
	cm.radius = CAP_R
	cm.height = CAP_LEN
	cm.radial_segments = 8
	cm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35
	mat.metallic = 0.3
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.25, 0.25)
	cm.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = cm
	_mm.instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(3000, 600, 3000))
	add_child(_mmi)

func sync(delta: float) -> void:
	if sim.get("transport") == null:
		return
	_clock -= delta
	if _clock <= 0.0:
		_clock = 1.0
		_rebuild_if_changed()
	_mirror_roofs()
	_capsules()

## The upgraded structures as a key: rebuild the placed parts only when it changes.
func _rebuild_if_changed() -> void:
	var blds: Dictionary = sim.state["buildings"]
	var k := PackedStringArray()
	for id in blds:
		var b: Dictionary = blds[id]
		if bool(b.get("hub", false)) or bool(b.get("tube", false)):
			k.append("%d%s%s%s" % [int(id), "h" if bool(b.get("hub", false)) else "", "t" if bool(b.get("tube", false)) else "", String(b.get("state", ""))])
	k.append(str(view.doors.doors.size()) if view.doors != null else "0")
	var key: String = ",".join(k)
	if key == _key:
		return
	_key = key
	_clear()
	var nh := 0
	var nt := 0
	var tube_by_junction := {}
	for id in blds:
		var b: Dictionary = blds[id]
		if String(b.get("state", "")) == "blueprint" or not view.bmeta.has(id):
			continue
		var meta: Dictionary = view.bmeta[id]
		if bool(b.get("tube", false)) and String(b.get("def", "")) == "corridor" and int(meta.get("h", -1)) >= 0:
			nt += 1
			var lst: Array = []
			var tt: Dictionary = Models.prop(["transport_tube"], 1.2, "room", "logistics")
			if not tt.is_empty() and Models.has_model("transport_tube"):
				lst.append([view.inst.add(tt, meta["xf"]), int(meta["h"]), "Roof"])
			var bt: Dictionary = Models.prop(["transport_bracket"], 1.2, "room", "logistics")
			if Models.has_model("transport_bracket") and view.doors != null:
				for rh in (view.doors.ribs.get(int(id), []) as Array):
					if view.inst.handles.has(rh):
						var rx: Transform3D = view.inst.handles[rh]["xf"]
						lst.append([view.inst.add(bt, Transform3D(rx.basis.orthonormalized(), rx.origin)), int(meta["h"]), "Roof"])
			_parts[int(id)] = lst
			for end in [["a", "p0"], ["b", "p1"]]:
				var jid: int = int(b.get(end[0], -1))
				if blds.has(jid) and String(blds[jid].get("def", "")) == "junction":
					(tube_by_junction.get_or_add(jid, []) as Array).append(b[end[1]])
		if bool(b.get("hub", false)):
			nh += 1
			var lst2: Array = []
			var size: int = int(b.get("size", 1))
			var hid: String = "transport_hub_%s" % Models.SIZE_SUFFIX[clampi(size, 0, 3)]
			if not Models.has_model(hid):
				hid = "transport_hub_m"
			var an: Dictionary = meta.get("anchors", {})
			if an.has("Hub") and Models.has_model(hid):
				var hx: Transform3D = an["Hub"]
				lst2.append([view.inst.add(Models.prop([hid], 1.2, "room", "logistics"), Transform3D(hx.basis.orthonormalized(), hx.origin)), int(meta.get("h", -1)), "Interior"])
			if Models.has_model("transport_port") and view.doors != null:
				var pt: Dictionary = Models.prop(["transport_port"], 1.2, "room", "logistics")
				for d in view.doors.doors:
					if int(d["room"]) == int(id) and view.inst.handles.has(int(d["h"])):
						lst2.append([view.inst.add(pt, view.inst.handles[int(d["h"])]["xf"]), int(d["h"]), "FrameTop:PortTop"])
			_parts[int(id)] = (_parts.get(int(id), []) as Array) + lst2
	# junctions with tube corridors: the manifold and a short tube from each mouth to it
	if Models.has_model("transport_junction"):
		for jid in tube_by_junction:
			if not view.bmeta.has(jid):
				continue
			var jm: Dictionary = view.bmeta[jid]
			var jx: Transform3D = jm["xf"]
			var lst3: Array = [[view.inst.add(Models.prop(["transport_junction"], 1.2, "room", "logistics"), jx), int(jm.get("h", -1)), "Roof"]]
			var jc: Vector2 = blds[jid]["pos"]
			var rw: float = float(blds[jid]["radius"])
			var tt2: Dictionary = Models.prop(["transport_tube"], 1.2, "room", "logistics")
			for pend in tube_by_junction[jid]:
				var dirv: Vector2 = ((pend as Vector2) - jc).normalized()
				var a2: Vector2 = jc + dirv * 0.31
				var b2: Vector2 = jc + dirv * rw
				var mid: Vector2 = (a2 + b2) * 0.5
				var ln: float = a2.distance_to(b2)
				var yaw: float = -atan2(dirv.y, dirv.x)
				var bx := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(ln, 1.0, 1.0))
				lst3.append([view.inst.add(tt2, Transform3D(bx, Vector3(mid.x, jx.origin.y + 0.05, mid.y))), int(jm.get("h", -1)), "Roof"])
			_parts[int(jid)] = (_parts.get(int(jid), []) as Array) + lst3
	stats["hubs"] = nh
	stats["tubes"] = nt

func _clear() -> void:
	for id in _parts:
		for e in _parts[id]:
			view.inst.remove(int(e[0]))
	_parts = {}

## Each placed part hides with its owner's group: a tube / bracket / manifold with the corridor's (junction's) Roof,
## a hub with the room's Interior, a port's PortTop with the door's FrameTop.
func _mirror_roofs() -> void:
	for id in _parts:
		for e in _parts[id]:
			var h: int = int(e[0])
			var oh: int = int(e[1])
			if not view.inst.handles.has(h) or not view.inst.handles.has(oh):
				continue
			var g: String = String(e[2])
			var src: String = g.get_slice(":", 0)
			var dst: String = g.get_slice(":", 1) if g.contains(":") else g
			var hid: bool = (view.inst.handles[oh]["hidden"] as Dictionary).has(src) or bool(view.inst.handles[oh].get("supp", false))
			view.inst.set_hidden(h, dst, hid)

func _capsules() -> void:
	var caps: Array = sim.transport.capsules_view()
	var n := 0
	var blds: Dictionary = sim.state["buildings"]
	var tick: int = int(sim.state["tick"])
	var buf := PackedFloat32Array()
	for c in caps:
		var pp: Dictionary = sim.transport.position_of(c, tick)
		if not bool(pp.get("in_tube", false)):
			continue
		var cid: int = int(pp["cid"])
		if not blds.has(cid) or not view.bmeta.has(cid):
			continue
		var meta: Dictionary = view.bmeta[cid]
		var ch: int = int(meta.get("h", -1))
		if ch >= 0 and view.inst.handles.has(ch) and (view.inst.handles[ch]["hidden"] as Dictionary).has("Roof"):
			continue
		var l: Dictionary = blds[cid]
		var p: Vector2 = pp["pos"]
		var a: Vector2 = l["p0"]
		var b: Vector2 = l["p1"]
		var t: float = clampf((p - a).dot(b - a) / maxf((b - a).length_squared(), 0.0001), 0.0, 1.0)
		var y: float = lerpf(view.h(a.x, a.y), view.h(b.x, b.y), t) + 0.05 + TUBE_Y
		var dirv: Vector2 = (b - a).normalized()
		# the capsule's long axis (Y of CapsuleMesh) along the tube
		var ax := Vector3(dirv.x, 0.0, dirv.y)
		var bxv: Vector3 = ax.cross(Vector3.UP).normalized()
		var bs := Basis(bxv, ax, bxv.cross(ax))
		var col := Color(String(sim.content["items"].get(String(c.get("res", "")), {}).get("color", "#c8c8c8")))
		buf.append_array([bs.x.x, bs.y.x, bs.z.x, p.x, bs.x.y, bs.y.y, bs.z.y, y, bs.x.z, bs.y.z, bs.z.z, p.y, col.r, col.g, col.b, 1.0])
		n += 1
	if _mm.instance_count != n:
		_mm.instance_count = n
	if n > 0:
		_mm.buffer = buf
	stats["capsules"] = n
