extends RefCounted
## RENDER test fixture: a crude procedural astronaut built exactly to the V3_DESIGN §3.2
## skeleton and §3.3 clip names (Skeleton3D + skinned MeshInstance3D + AnimationPlayer, the
## same node types the glTF importer makes). It exists so the character pipeline, the pose
## state machine and tools/npc_check.gd can be tested before ART-NPC's GLBs arrive.
## It is NEVER shown in the game unless a test asks for it (window.__fhr.cmd("npc fixture"),
## npc_check.gd --fixture). It is not art.

const FPS := 30.0
## [name, parent, local rest offset] in Godot space: Y up, the body faces +X, left is -Z.
const SKELETON := [
	["root", "", Vector3(0, 0, 0)],
	["hips", "root", Vector3(0, 0.95, 0)],
	["spine", "hips", Vector3(0, 0.12, 0)],
	["chest", "spine", Vector3(0, 0.2, 0)],
	["neck", "chest", Vector3(0, 0.22, 0)],
	["head", "neck", Vector3(0, 0.1, 0)],
	["shoulder.L", "chest", Vector3(0, 0.16, -0.1)],
	["upper_arm.L", "shoulder.L", Vector3(0, 0, -0.1)],
	["forearm.L", "upper_arm.L", Vector3(0, -0.3, 0)],
	["hand.L", "forearm.L", Vector3(0, -0.27, 0)],
	["prop.L", "hand.L", Vector3(0.03, -0.08, 0)],
	["shoulder.R", "chest", Vector3(0, 0.16, 0.1)],
	["upper_arm.R", "shoulder.R", Vector3(0, 0, 0.1)],
	["forearm.R", "upper_arm.R", Vector3(0, -0.3, 0)],
	["hand.R", "forearm.R", Vector3(0, -0.27, 0)],
	["prop.R", "hand.R", Vector3(0.03, -0.08, 0)],
	["thigh.L", "hips", Vector3(0, -0.05, -0.1)],
	["shin.L", "thigh.L", Vector3(0, -0.43, 0)],
	["foot.L", "shin.L", Vector3(0, -0.4, 0)],
	["toe.L", "foot.L", Vector3(0.14, -0.05, 0)],
	["thigh.R", "hips", Vector3(0, -0.05, 0.1)],
	["shin.R", "thigh.R", Vector3(0, -0.43, 0)],
	["foot.R", "shin.R", Vector3(0, -0.4, 0)],
	["toe.R", "foot.R", Vector3(0.14, -0.05, 0)],
]
## [clip, length s, loop]
const CLIPS := [
	["idle", 4.0, true], ["idle_look", 6.0, true], ["walk", 1.0, true], ["run", 0.7, true],
	["carry_walk", 1.0, true], ["carry_idle", 3.0, true], ["work_console", 2.0, true], ["work_bench", 2.0, true],
	["talk", 3.0, true], ["kneel_enter", 1.0, false], ["repair_kneel", 2.0, true], ["kneel_exit", 1.0, false],
	["sit_enter", 1.2, false], ["sit_idle", 4.0, true], ["sit_eat", 3.0, true], ["sit_type", 2.0, true], ["sit_exit", 1.2, false],
	["lie_enter", 2.0, false], ["sleep", 4.0, true], ["lie_exit", 2.0, false], ["injured_walk", 1.3, true],
	["collapse", 1.5, false], ["dead", 1.0, true], ["cheer", 2.4, false],
]
const HIPS := Vector3(0, 0.95, 0)
const SIT_HIPS := Vector3(-0.30, 0.56, 0)
const KNEEL_HIPS := Vector3(0.0, 0.52, 0)
const LIE_HIPS := Vector3(-0.55, 0.66, 0)

## Metadata in the same shape as assets/models/astronaut_anims.json.
static func meta() -> Dictionary:
	var clips := {}
	for c in CLIPS:
		var d := {"frames": int(round(float(c[1]) * FPS)) + 1, "loop": c[2], "kind": "loop" if c[2] else "oneshot"}
		if c[0] == "walk" or c[0] == "carry_walk":
			d["speed_mps"] = 1.4
			d["stride_m"] = 1.4
		elif c[0] == "run":
			d["speed_mps"] = 3.6
			d["stride_m"] = 2.52
		elif c[0] == "injured_walk":
			d["speed_mps"] = 0.8
			d["stride_m"] = 1.04
		clips[c[0]] = d
	for p in [["sit", "sit_enter", "sit_exit"], ["lie", "lie_enter", "lie_exit"], ["kneel", "kneel_enter", "kneel_exit"]]:
		clips[p[1]]["kind"] = "enter"
		clips[p[1]]["pose_from"] = "stand"
		clips[p[1]]["pose_to"] = p[0]
		clips[p[2]]["kind"] = "exit"
		clips[p[2]]["pose_from"] = p[0]
		clips[p[2]]["pose_to"] = "stand"
	return {"fps": FPS, "height": 1.8, "clips": clips,
		"furniture": {"seat_z": 0.46, "seat_back": 0.30, "bed_z": 0.55, "bed_back": 0.55, "console_z": 1.0, "console_ahead": 0.45, "bench_z": 0.9, "panel_ahead": 0.45, "panel_z": 0.4}}

## A scene root like an imported GLB: root/Skeleton3D/<meshes>, root/AnimationPlayer.
static func build(variant: String = "suit") -> Node3D:
	var root := Node3D.new()
	root.name = "astronaut_" + variant + "_fixture"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	for b in SKELETON:
		var i: int = sk.add_bone(b[0])
		if b[1] != "":
			sk.set_bone_parent(i, sk.find_bone(b[1]))
		sk.set_bone_rest(i, Transform3D(Basis(), b[2]))
		sk.set_bone_pose_position(i, b[2])
	var rest_g: Array = []
	for i in sk.get_bone_count():
		var p: int = sk.get_bone_parent(i)
		var l: Transform3D = sk.get_bone_rest(i)
		rest_g.append(l if p < 0 else (rest_g[p] as Transform3D) * l)
	var skin := Skin.new()
	for i in sk.get_bone_count():
		skin.add_bind(i, (rest_g[i] as Transform3D).affine_inverse())
	var mats := _materials(variant)
	var parts: Array = _parts(variant)
	# One mesh for the body and one per head variant (Head_0..Head_3 in the indoor model).
	var groups := {"Body": []}
	for pt in parts:
		var g: String = String(pt.get("obj", "Body"))
		if not groups.has(g):
			groups[g] = []
		groups[g].append(pt)
	for g in groups:
		var by_mat := {}
		for pt in groups[g]:
			var mn: String = pt["mat"]
			if not by_mat.has(mn):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(mats[mn])
				by_mat[mn] = st
			_add_prim(by_mat[mn], pt, rest_g, sk)
		var am := ArrayMesh.new()
		for mn in by_mat:
			(by_mat[mn] as SurfaceTool).index()
			(by_mat[mn] as SurfaceTool).commit(am)
		var mi := MeshInstance3D.new()
		mi.name = g
		mi.mesh = am
		mi.skin = skin
		sk.add_child(mi)
		mi.skeleton = NodePath("..")
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	for c in CLIPS:
		lib.add_animation(c[0], _clip(c[0], float(c[1]), bool(c[2]), sk))
	ap.add_animation_library("", lib)
	return root

static func _materials(variant: String) -> Dictionary:
	var out := {}
	var spec := {
		"SuitMain": [Color("e8e6e0"), 0.62, 0.0, 0.0], "SuitAccent": [Color("ffffff"), 0.55, 0.0, 0.0],
		"Visor": [Color("c9a24a"), 0.12, 0.9, 0.0], "Pack": [Color("7d858f"), 0.5, 0.3, 0.0],
		"Light": [Color("5ee07a"), 0.4, 0.0, 2.5], "Rubber": [Color("2b2f36"), 0.8, 0.0, 0.0],
		"Jumpsuit": [Color("243247"), 0.7, 0.0, 0.0], "Skin": [Color("c8966e"), 0.6, 0.0, 0.0],
		"Hair": [Color("3a2a1e"), 0.7, 0.0, 0.0],
	}
	for n in spec:
		var m := StandardMaterial3D.new()
		m.resource_name = n
		m.albedo_color = spec[n][0]
		m.roughness = spec[n][1]
		m.metallic = spec[n][2]
		if float(spec[n][3]) > 0.0:
			m.emission_enabled = true
			m.emission = spec[n][0]
			m.emission_energy_multiplier = spec[n][3]
		out[n] = m
	return out

## Body parts: [bone, primitive, size, offset in the bone's rest frame, material].
static func _parts(variant: String) -> Array:
	var suit: bool = variant == "suit"
	var main: String = "SuitMain" if suit else "Jumpsuit"
	var out: Array = [
		{"bone": "hips", "prim": "box", "size": Vector3(0.24, 0.2, 0.34), "off": Vector3(0, -0.02, 0), "mat": main},
		{"bone": "spine", "prim": "box", "size": Vector3(0.24, 0.22, 0.34), "off": Vector3(0, 0.1, 0), "mat": main},
		{"bone": "chest", "prim": "box", "size": Vector3(0.28, 0.3, 0.42), "off": Vector3(0, 0.12, 0), "mat": main},
		{"bone": "upper_arm.L", "prim": "caps", "size": Vector3(0.07, 0.3, 0), "off": Vector3(0, -0.15, 0), "mat": "SuitAccent"},
		{"bone": "upper_arm.R", "prim": "caps", "size": Vector3(0.07, 0.3, 0), "off": Vector3(0, -0.15, 0), "mat": "SuitAccent"},
		{"bone": "forearm.L", "prim": "caps", "size": Vector3(0.06, 0.28, 0), "off": Vector3(0, -0.14, 0), "mat": main},
		{"bone": "forearm.R", "prim": "caps", "size": Vector3(0.06, 0.28, 0), "off": Vector3(0, -0.14, 0), "mat": main},
		{"bone": "hand.L", "prim": "box", "size": Vector3(0.08, 0.1, 0.05), "off": Vector3(0, -0.05, 0), "mat": "Rubber"},
		{"bone": "hand.R", "prim": "box", "size": Vector3(0.08, 0.1, 0.05), "off": Vector3(0, -0.05, 0), "mat": "Rubber"},
		{"bone": "thigh.L", "prim": "caps", "size": Vector3(0.085, 0.43, 0), "off": Vector3(0, -0.21, 0), "mat": main},
		{"bone": "thigh.R", "prim": "caps", "size": Vector3(0.085, 0.43, 0), "off": Vector3(0, -0.21, 0), "mat": main},
		{"bone": "shin.L", "prim": "caps", "size": Vector3(0.075, 0.4, 0), "off": Vector3(0, -0.2, 0), "mat": main},
		{"bone": "shin.R", "prim": "caps", "size": Vector3(0.075, 0.4, 0), "off": Vector3(0, -0.2, 0), "mat": main},
		{"bone": "foot.L", "prim": "box", "size": Vector3(0.26, 0.08, 0.11), "off": Vector3(0.05, -0.03, 0), "mat": "Rubber"},
		{"bone": "foot.R", "prim": "box", "size": Vector3(0.26, 0.08, 0.11), "off": Vector3(0.05, -0.03, 0), "mat": "Rubber"},
	]
	if suit:
		out.append({"bone": "head", "prim": "sphere", "size": Vector3(0.15, 0, 0), "off": Vector3(0, 0.1, 0), "mat": "SuitMain"})
		out.append({"bone": "head", "prim": "box", "size": Vector3(0.06, 0.12, 0.2), "off": Vector3(0.12, 0.1, 0), "mat": "Visor"})
		out.append({"bone": "chest", "prim": "box", "size": Vector3(0.18, 0.4, 0.34), "off": Vector3(-0.23, 0.1, 0), "mat": "Pack"})
		out.append({"bone": "chest", "prim": "box", "size": Vector3(0.03, 0.04, 0.04), "off": Vector3(-0.33, 0.2, -0.08), "mat": "Light"})
		out.append({"bone": "chest", "prim": "box", "size": Vector3(0.03, 0.04, 0.04), "off": Vector3(-0.33, 0.2, 0.08), "mat": "Light"})
	else:
		out.append({"bone": "neck", "prim": "caps", "size": Vector3(0.05, 0.12, 0), "off": Vector3(0, 0.05, 0), "mat": "Skin"})
		for h in 4:
			out.append({"bone": "head", "prim": "sphere", "size": Vector3(0.11, 0, 0), "off": Vector3(0.01, 0.1, 0), "mat": "Skin", "obj": "Head_%d" % h})
			var hair_size: Vector3 = [Vector3(0.12, 0, 0), Vector3(0.1, 0.06, 0.2), Vector3(0.13, 0.2, 0.2), Vector3(0.09, 0.05, 0.16)][h]
			var hair_off: Vector3 = [Vector3(-0.015, 0.14, 0), Vector3(-0.02, 0.19, 0), Vector3(-0.05, 0.1, 0), Vector3(-0.01, 0.2, 0)][h]
			out.append({"bone": "head", "prim": "sphere" if h == 0 else "box", "size": hair_size, "off": hair_off, "mat": "Hair", "obj": "Head_%d" % h})
	return out

static func _add_prim(st: SurfaceTool, pt: Dictionary, rest_g: Array, sk: Skeleton3D) -> void:
	var bi: int = sk.find_bone(pt["bone"])
	var sz: Vector3 = pt["size"]
	var arrays: Array
	match String(pt["prim"]):
		"box":
			var bm := BoxMesh.new()
			bm.size = sz
			arrays = bm.get_mesh_arrays()
		"caps":
			var cm := CapsuleMesh.new()
			cm.radius = sz.x
			cm.height = maxf(sz.y, sz.x * 2.0 + 0.01)
			cm.radial_segments = 10
			cm.rings = 3
			arrays = cm.get_mesh_arrays()
		_:
			var sm := SphereMesh.new()
			sm.radius = sz.x
			sm.height = sz.x * 2.0
			sm.radial_segments = 14
			sm.rings = 8
			arrays = sm.get_mesh_arrays()
	var xf: Transform3D = (rest_g[bi] as Transform3D) * Transform3D(Basis(), pt["off"])
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for k in idx:
		st.set_normal(xf.basis * n[k])
		st.set_uv(Vector2.ZERO)
		st.set_color(Color(1, 1, 1, 1))
		st.set_bones(PackedInt32Array([bi, 0, 0, 0]))
		st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		st.add_vertex(xf * v[k])

# ---------------------------------------------------------------- clips
static func _q(deg: Vector3) -> Quaternion:
	return Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))

## Pose shapes. Each returns {bone: Quaternion, "@hips": position}.
static func _stand() -> Dictionary:
	return {"@hips": HIPS}

static func _sit() -> Dictionary:
	return {"@hips": SIT_HIPS, "thigh.L": _q(Vector3(0, 0, 90)), "thigh.R": _q(Vector3(0, 0, 90)),
		"shin.L": _q(Vector3(0, 0, -90)), "shin.R": _q(Vector3(0, 0, -90)), "spine": _q(Vector3(0, 0, -4)),
		"upper_arm.L": _q(Vector3(0, 0, 18)), "upper_arm.R": _q(Vector3(0, 0, 18)), "forearm.L": _q(Vector3(0, 0, 45)), "forearm.R": _q(Vector3(0, 0, 45))}

static func _kneel() -> Dictionary:
	return {"@hips": KNEEL_HIPS, "thigh.L": _q(Vector3(0, 0, 88)), "shin.L": _q(Vector3(0, 0, -88)),
		"thigh.R": _q(Vector3(0, 0, 4)), "shin.R": _q(Vector3(0, 0, -96)), "foot.R": _q(Vector3(0, 0, 40)),
		"spine": _q(Vector3(0, 0, -18)), "chest": _q(Vector3(0, 0, -10)),
		"upper_arm.L": _q(Vector3(0, 0, 55)), "upper_arm.R": _q(Vector3(0, 0, 55)), "forearm.L": _q(Vector3(0, 0, 30)), "forearm.R": _q(Vector3(0, 0, 30))}

static func _lie() -> Dictionary:
	# On the back, head toward -Z (Blender +Y), face up.
	var b := Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
	return {"@hips": LIE_HIPS, "hips": b.get_rotation_quaternion(), "upper_arm.L": _q(Vector3(0, 0, 8)), "upper_arm.R": _q(Vector3(0, 0, 8))}

static func _collapsed() -> Dictionary:
	var b := Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
	return {"@hips": Vector3(-0.6, 0.16, 0), "hips": b.get_rotation_quaternion(), "upper_arm.L": _q(Vector3(-10, 0, 30)), "upper_arm.R": _q(Vector3(10, 0, 50)), "thigh.L": _q(Vector3(0, 0, 12))}

static func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	var e: float = t * t * (3.0 - 2.0 * t)
	for k in a.keys() + b.keys():
		if out.has(k):
			continue
		if k == "@hips":
			out[k] = (a.get(k, HIPS) as Vector3).lerp(b.get(k, HIPS), e)
		else:
			out[k] = (a.get(k, Quaternion()) as Quaternion).slerp(b.get(k, Quaternion()), e)
	return out

static func _add(p: Dictionary, bone: String, deg: Vector3) -> void:
	p[bone] = (p.get(bone, Quaternion()) as Quaternion) * _q(deg)

static func _pose(clip: String, t: float, len: float) -> Dictionary:
	var ph: float = t / len
	var s: float = sin(TAU * ph)
	var c: float = cos(TAU * ph)
	match clip:
		"idle":
			var p := _stand()
			_add(p, "spine", Vector3(0, 0, 1.2 * s))
			_add(p, "chest", Vector3(0.8 * c, 0, 0.6 * s))
			p["@hips"] = HIPS + Vector3(0, 0, 0.012 * s)
			return p
		"idle_look":
			var p := _stand()
			_add(p, "neck", Vector3(0, 30.0 * s, 0))
			_add(p, "head", Vector3(0, 15.0 * s, 4.0 * (1.0 - c) * 0.5))
			return p
		"walk", "carry_walk", "run", "injured_walk":
			var amp: float = 26.0 if clip != "run" else 38.0
			var p := _stand()
			var lim: float = 0.55 if clip == "injured_walk" else 1.0
			_add(p, "thigh.L", Vector3(0, 0, amp * s))
			_add(p, "thigh.R", Vector3(0, 0, -amp * s * lim))
			_add(p, "shin.L", Vector3(0, 0, -(22.0 + 22.0 * c) * (1.3 if clip == "run" else 1.0)))
			_add(p, "shin.R", Vector3(0, 0, -(22.0 - 22.0 * c) * (1.3 if clip == "run" else 1.0) * lim))
			p["@hips"] = HIPS + Vector3(0, -0.025 * absf(c) - (0.06 if clip == "run" else 0.0), 0)
			if clip == "carry_walk":
				_add(p, "upper_arm.L", Vector3(0, 0, 55))
				_add(p, "upper_arm.R", Vector3(0, 0, 55))
				_add(p, "forearm.L", Vector3(0, 0, 40))
				_add(p, "forearm.R", Vector3(0, 0, 40))
			else:
				_add(p, "upper_arm.L", Vector3(0, 0, -amp * 0.8 * s))
				_add(p, "upper_arm.R", Vector3(0, 0, amp * 0.8 * s))
				_add(p, "forearm.L", Vector3(0, 0, 15 + (20.0 if clip == "run" else 0.0)))
				_add(p, "forearm.R", Vector3(0, 0, 15 + (20.0 if clip == "run" else 0.0)))
			if clip == "run":
				_add(p, "spine", Vector3(0, 0, -8))
			return p
		"carry_idle":
			var p := _stand()
			_add(p, "upper_arm.L", Vector3(0, 0, 55))
			_add(p, "upper_arm.R", Vector3(0, 0, 55))
			_add(p, "forearm.L", Vector3(0, 0, 40 + 2.0 * s))
			_add(p, "forearm.R", Vector3(0, 0, 40 + 2.0 * s))
			_add(p, "spine", Vector3(0, 0, 1.0 * s))
			return p
		"work_console", "work_bench":
			var p := _stand()
			var bend: float = 12.0 if clip == "work_bench" else 3.0
			_add(p, "spine", Vector3(0, 0, -bend))
			_add(p, "upper_arm.L", Vector3(0, 0, 38))
			_add(p, "upper_arm.R", Vector3(0, 0, 38))
			_add(p, "forearm.L", Vector3(0, 0, 48 + 6.0 * sin(TAU * ph * 3.0)))
			_add(p, "forearm.R", Vector3(0, 0, 48 - 6.0 * sin(TAU * ph * 3.0)))
			return p
		"talk":
			var p := _stand()
			_add(p, "upper_arm.R", Vector3(-10.0 * (1.0 - c), 0, 25.0 * (1.0 - c) * 0.5))
			_add(p, "forearm.R", Vector3(0, 0, 50.0 * (1.0 - c) * 0.5))
			_add(p, "head", Vector3(0, 8.0 * s, 0))
			return p
		"kneel_enter":
			return _mix(_stand(), _kneel(), ph)
		"kneel_exit":
			return _mix(_kneel(), _stand(), ph)
		"repair_kneel":
			var p := _kneel()
			_add(p, "forearm.R", Vector3(0, 0, 14.0 * (1.0 - c) * 0.5))
			_add(p, "forearm.L", Vector3(0, 0, 8.0 * (1.0 - c) * 0.5))
			return p
		"sit_enter":
			return _mix(_stand(), _sit(), ph)
		"sit_exit":
			return _mix(_sit(), _stand(), ph)
		"sit_idle":
			var p := _sit()
			_add(p, "chest", Vector3(0, 0, 1.0 * s))
			return p
		"sit_eat":
			var p := _sit()
			_add(p, "upper_arm.R", Vector3(0, 0, 30.0 * (1.0 - c) * 0.5))
			_add(p, "forearm.R", Vector3(0, 0, 70.0 * (1.0 - c) * 0.5))
			return p
		"sit_type":
			var p := _sit()
			_add(p, "upper_arm.L", Vector3(0, 0, 18))
			_add(p, "upper_arm.R", Vector3(0, 0, 18))
			_add(p, "forearm.L", Vector3(0, 0, 8.0 * (1.0 - cos(TAU * ph * 2.0)) * 0.5))
			_add(p, "forearm.R", Vector3(0, 0, 8.0 * (1.0 + cos(TAU * ph * 2.0 + PI)) * 0.5))
			return p
		"lie_enter":
			if ph < 0.5:
				return _mix(_stand(), _sit(), ph * 2.0)
			return _mix(_sit(), _lie(), (ph - 0.5) * 2.0)
		"lie_exit":
			if ph < 0.5:
				return _mix(_lie(), _sit(), ph * 2.0)
			return _mix(_sit(), _stand(), (ph - 0.5) * 2.0)
		"sleep":
			var p := _lie()
			_add(p, "chest", Vector3(1.0 * s, 0, 0))
			return p
		"collapse":
			return _mix(_stand(), _collapsed(), ph)
		"dead":
			return _collapsed()
		"cheer":
			var p := _stand()
			var up: float = sin(PI * ph)
			_add(p, "upper_arm.L", Vector3(150.0 * up, 0, 0))
			_add(p, "upper_arm.R", Vector3(-150.0 * up, 0, 0))
			return p
	return _stand()

static func _clip(name: String, len: float, loop: bool, sk: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = len
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for b in SKELETON:
		var t: int = a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:" + String(b[0])))
		tracks[b[0]] = t
	var hp: int = a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(hp, NodePath("Skeleton3D:hips"))
	var n: int = int(round(len * 15.0))
	for f in n + 1:
		var tt: float = len * float(f) / n
		var p: Dictionary = _pose(name, tt, len)
		for b in SKELETON:
			a.rotation_track_insert_key(tracks[b[0]], tt, p.get(b[0], Quaternion()))
		a.position_track_insert_key(hp, tt, p.get("@hips", HIPS))
	return a
