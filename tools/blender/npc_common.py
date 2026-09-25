"""
Frontier Habitat 3.0 - ART-NPC shared library (V3_DESIGN.md section 3).  Blender 5.2, --background only.

What is here:
  * SKELETON  - the section 3.2 skeleton (names, parents, bind positions).  Identical in every variant.
  * SkinPart  - a Part (tools/blender/ext_common.py, read-only import) that also records a weight rule per
                vertex; weights are resolved after the build (smooth chain blends, max 4, normalised).
  * NPC_MATERIALS - suit / indoor material values (names are the contract names).
  * build_rig / build_skinned_mesh - armature + one skinned mesh object.
  * Pose solver - poses are authored as rotations about WORLD-ALIGNED axes in the parent's frame
                (X forward, Y left, Z up; so ry > 0 leans an upward bone forward), with 2-bone IK for the legs
                (ankle target + foot orientation) and optional IK for the arms (wrist target).
  * bake_clip - writes one Blender action (all bones, every frame, linear) and pushes it to an NLA track.
  * export_glb_skinned - atomic export (.tmp.glb, then rename) with every action.

Conventions: metres, Blender Z up, character faces +X, left = +Y, origin on the ground between the feet.
"""
import bpy
import os
import sys
import math
import json
import struct
from math import radians, degrees, sin, cos, sqrt, pi
from mathutils import Matrix, Vector, Quaternion, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ext_common as C                                     # noqa: E402  (read-only use; owned by ART-HAB)
from ext_common import Part, T, RX, RY, RZ, S              # noqa: E402,F401

ROOT = C.ROOT
MODEL_DIR = C.MODEL_DIR
ART_DIR = os.path.join(ROOT, "art", "npc")
FPS = 30

# --------------------------------------------------------------------------------------
# Skeleton (section 3.2).  Bind pose = A-pose, arms 30 deg from vertical, legs straight.
# --------------------------------------------------------------------------------------
_A = radians(30.0)
_UA = Vector((0.0, sin(_A), -cos(_A)))                     # left upper arm direction (bind)
_FA = Vector((0.07, sin(_A), -cos(_A))).normalized()       # left forearm direction (slightly forward)
SH_JOINT = Vector((-0.005, 0.215, 1.425))                  # left shoulder (upper_arm head)
EL_JOINT = SH_JOINT + _UA * 0.29
WR_JOINT = EL_JOINT + _FA * 0.265
HAND_TIP = WR_JOINT + _FA * 0.095
PALM_N = Vector((0.0, -cos(_A), -sin(_A)))                 # left palm normal (towards the body), bind
PALM_N = (PALM_N - _FA * PALM_N.dot(_FA)).normalized()
PROP_HEAD = WR_JOINT + _FA * 0.075 + PALM_N * 0.035

HIP_JOINT = Vector((0.0, 0.10, 0.935))
KNEE_JOINT = Vector((0.006, 0.105, 0.505))
ANKLE_JOINT = Vector((-0.012, 0.11, 0.10))
BALL_JOINT = Vector((0.12, 0.11, 0.035))
TOE_TIP = Vector((0.205, 0.11, 0.035))


def _mirror(v):
    return Vector((v.x, -v.y, v.z))


def _bones():
    b = [
        ("root", None, (0, 0, 0), (0, 0, 0.20)),
        ("hips", "root", (0, 0, 0.98), (0, 0, 1.08)),
        ("spine", "hips", (0, 0, 1.08), (0, 0, 1.22)),
        ("chest", "spine", (0, 0, 1.22), (0, 0, 1.47)),
        ("neck", "chest", (0.005, 0, 1.47), (0.015, 0, 1.57)),
        ("head", "neck", (0.015, 0, 1.57), (0.015, 0, 1.80)),
    ]
    for side, f in (("L", lambda v: Vector(v)), ("R", _mirror)):
        b += [
            ("shoulder." + side, "chest", tuple(f(Vector((0.0, 0.035, 1.43)))), tuple(f(Vector((-0.005, 0.195, 1.435))))),
            ("upper_arm." + side, "shoulder." + side, tuple(f(SH_JOINT)), tuple(f(EL_JOINT))),
            ("forearm." + side, "upper_arm." + side, tuple(f(EL_JOINT)), tuple(f(WR_JOINT))),
            ("hand." + side, "forearm." + side, tuple(f(WR_JOINT)), tuple(f(HAND_TIP))),
            ("prop." + side, "hand." + side, tuple(f(PROP_HEAD)), tuple(f(PROP_HEAD + _FA * 0.06))),
            ("thigh." + side, "hips", tuple(f(HIP_JOINT)), tuple(f(KNEE_JOINT))),
            ("shin." + side, "thigh." + side, tuple(f(KNEE_JOINT)), tuple(f(ANKLE_JOINT))),
            ("foot." + side, "shin." + side, tuple(f(ANKLE_JOINT)), tuple(f(BALL_JOINT))),
            ("toe." + side, "foot." + side, tuple(f(BALL_JOINT)), tuple(f(TOE_TIP))),
        ]
    return b


SKELETON = _bones()
BONE_NAMES = [b[0] for b in SKELETON]
PARENT = {b[0]: b[1] for b in SKELETON}
BIND_HEAD = {b[0]: Vector(b[2]) for b in SKELETON}
BIND_TAIL = {b[0]: Vector(b[3]) for b in SKELETON}
SIDES = ("L", "R")

# foot contact points in the bind pose (left side; mirror y for right).  The sole bottom is z = 0.
HEEL_PIVOT = Vector((-0.100, 0.11, 0.0))


# --------------------------------------------------------------------------------------
# Materials (contract names; values chosen for this model)
# --------------------------------------------------------------------------------------
NPC_MATERIALS = {
    "SuitMain":   dict(color="#e8eaed", rough=0.68),
    "SuitAccent": dict(color="#ff9f1c", rough=0.55),
    "Visor":      dict(color="#c9a14a", metal=0.95, rough=0.14),       # gold-tinted reflective visor
    "Pack":       dict(color="#8b939d", rough=0.55),
    "Frame":      dict(color="#4a5058", metal=0.60, rough=0.50),
    "Trim":       dict(color="#b8c2cc", metal=0.85, rough=0.30),
    "Rubber":     dict(color="#2b2d33", rough=0.90),
    "SuitHard":   dict(color="#e8eaed", rough=0.45),                    # hard shells: HUT, helmet (critic r1 #6)
    "Light":      dict(color="#fff4e0", rough=0.40, emit="#fff4e0", emit_strength=4.0),   # helmet lamp lenses
    "LightGreen": dict(color="#5ee07a", rough=0.40, emit="#5ee07a", emit_strength=4.0),   # pack status light
    "LightAmber": dict(color="#ffb547", rough=0.40, emit="#ffb547", emit_strength=4.0),   # pack status light
    # the same values as ART-HAB's (build_assets.py), so one library material serves both
    "Screen":     dict(color="#123c4c", rough=0.25, emit="#2fb8d8", emit_strength=0.45),
    "LightStrip": dict(color="#eaf6ff", rough=0.30, emit="#eaf6ff", emit_strength=2.5),
    # indoor variant
    "Jumpsuit":   dict(color="#243247", rough=0.80),
    "Skin":       dict(color="#d9a47e", rough=0.72),
    "Hair":       dict(color="#4a3326", rough=0.85),
    # visitor attachments (V3_1 section 6.4): fixed colours, not tinted by the game
    "VisRed":     dict(color="#d7263d", rough=0.50),
    "VisGold":    dict(color="#d9a93a", metal=0.75, rough=0.32),
    "VisGrey":    dict(color="#6b7280", rough=0.72),
    "VisWhite":   dict(color="#f2f3f5", rough=0.62),
    "VisDark":    dict(color="#1e2024", rough=0.50),
    "VisGraphite": dict(color="#3a3f47", rough=0.72),
    # retro-reflective trims: a weak emission keeps them readable at night (critic round 12)
    "VisHiVis":   dict(color="#e4f218", rough=0.45, emit="#e4f218", emit_strength=0.5),
    "VisGoldReflect": dict(color="#d9a93a", metal=0.30, rough=0.35, emit="#d9a93a", emit_strength=0.8),
}


class NpcMaterialSet(C.MaterialSet):
    def spec(self, name):
        if name in NPC_MATERIALS:
            return NPC_MATERIALS[name]
        return super().spec(name)


# --------------------------------------------------------------------------------------
# Weight rules
# --------------------------------------------------------------------------------------
def sstep(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e0 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


class Chain:
    """Weight rule along a bone chain.  bones = [b0, b1, ..., bn]; joints = [(point, axis, half_width)] * n.
    Blend factor of joint j: s = (p - point) . axis; b_j = smoothstep(-w, +w, s) (axis points from b_{j} to b_{j+1}).
    w0 = 1-b1, w1 = b1(1-b2), ..., wn = b1 b2 ... bn.  Joints may be asymmetric: (point, axis, (w_minus, w_plus))."""

    def __init__(self, bones, joints, extra=None):
        self.bones = bones
        self.joints = [(Vector(p), Vector(a).normalized(), w) for p, a, w in joints]
        self.extra = extra          # optional fn(p, weights_dict) -> None (adds influences)

    def __call__(self, p):
        out = {}
        acc = 1.0
        for k, b in enumerate(self.bones):
            if k < len(self.joints):
                pt, ax, w = self.joints[k]
                wm, wp = (w, w) if not isinstance(w, tuple) else w
                bj = sstep(-wm, wp, (p - pt).dot(ax))
                out[b] = out.get(b, 0.0) + acc * (1.0 - bj)
                acc *= bj
            else:
                out[b] = out.get(b, 0.0) + acc
        if self.extra:
            self.extra(p, out)
        return out


def resolve_weights(spec, p):
    if spec is None:
        raise ValueError("vertex without a weight rule at %s" % (tuple(p),))
    if isinstance(spec, str):
        return {spec: 1.0}
    if isinstance(spec, dict):
        return dict(spec)
    return spec(p)


def limit_normalise(w, n=4, eps=0.004):
    items = sorted(((b, x) for b, x in w.items() if x > eps), key=lambda t: -t[1])[:n]
    s = sum(x for _, x in items)
    if s <= 0:
        raise ValueError("zero weights")
    return {b: x / s for b, x in items}


class SkinPart(Part):
    """Part that remembers the active weight rule for every vertex it creates."""

    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        super().__init__(name, origin)
        self.wrule = []
        self._w = [None]

    def v(self, p):
        i = super().v(p)
        self.wrule.append(self._w[-1])
        return i

    class _W:
        def __init__(self, part, rule):
            self.part, self.rule = part, rule

        def __enter__(self):
            self.part._w.append(self.rule)
            return self.part

        def __exit__(self, *a):
            self.part._w.pop()

    def w(self, rule):
        return SkinPart._W(self, rule)

    def weights(self):
        return [limit_normalise(resolve_weights(r, p)) for r, p in zip(self.wrule, self.verts)]


# --------------------------------------------------------------------------------------
# Geometry helpers for bodies
# --------------------------------------------------------------------------------------
def frame_from(w, ref):
    """Orthonormal (u, v, w): w = axis, u = ref made perpendicular to w, v = w x u."""
    w = Vector(w).normalized()
    u = Vector(ref) - w * Vector(ref).dot(w)
    if u.length < 1e-6:
        u = Vector((1, 0, 0)) - w * w.x
        if u.length < 1e-6:
            u = Vector((0, 1, 0)) - w * w.y
    u.normalize()
    v = w.cross(u).normalized()
    return u, v, w


def superellipse(a_pos, a_neg, b, n, seg, phase=0.0):
    """Points (x, y) of a super-ellipse, x half-depth a_pos (front) / a_neg (back), y half-width b."""
    pts = []
    e = 2.0 / n
    for i in range(seg):
        t = 2 * pi * i / seg + phase
        c, s = cos(t), sin(t)
        x = (abs(c) ** e) * (a_pos if c >= 0 else a_neg) * (1 if c >= 0 else -1)
        y = (abs(s) ** e) * b * (1 if s >= 0 else -1)
        pts.append((x, y))
    return pts


def tube_path(part, pts, stations, seg=12, ref=(1, 0, 0), cap0=False, cap1=False, cap_mat=None, phase=0.0,
              rule_at=None):
    """Loft along a polyline.  stations: [(s, ru, rv, mat, du, dv)] with s = arc length from pts[0], ru along the
    frame's u axis (ref direction), rv along v; du/dv offset the ring centre.  mat = material of the band from
    this station to the next.  Frames use the local path tangent (bisector at corners).  rule_at(s) -> weight rule
    for the ring at s (optional; otherwise the part's active rule is used)."""
    pts = [Vector(p) for p in pts]
    L = [0.0]
    for i in range(1, len(pts)):
        L.append(L[-1] + (pts[i] - pts[i - 1]).length)

    def at(s):
        s = max(0.0, min(L[-1], s))
        for i in range(1, len(pts)):
            if s <= L[i] + 1e-9:
                seglen = L[i] - L[i - 1]
                t = (s - L[i - 1]) / seglen if seglen > 0 else 0.0
                p = pts[i - 1].lerp(pts[i], t)
                d = (pts[i] - pts[i - 1]).normalized()
                # blend tangent near the corner (within 0.04 m)
                if i < len(pts) - 1 and L[i] - s < 0.04:
                    d2 = (pts[i + 1] - pts[i]).normalized()
                    k = 0.5 * (1.0 - (L[i] - s) / 0.04)
                    d = (d.lerp(d2, k)).normalized()
                if i > 1 and s - L[i - 1] < 0.04:
                    d0 = (pts[i - 1] - pts[i - 2]).normalized()
                    k = 0.5 * (1.0 - (s - L[i - 1]) / 0.04)
                    d = (d.lerp(d0, k)).normalized()
                return p, d
        return pts[-1], (pts[-1] - pts[-2]).normalized()

    rings, mats = [], []
    for st in stations:
        s, ru, rv, mat = st[:4]
        du = st[4] if len(st) > 4 else 0.0
        dv = st[5] if len(st) > 5 else 0.0
        p, d = at(s)
        u, v, w = frame_from(d, ref)
        c = p + u * du + v * dv
        ring = [tuple(c + u * (ru * cos(2 * pi * i / seg + phase)) + v * (rv * sin(2 * pi * i / seg + phase)))
                for i in range(seg)]
        rings.append((ring, s))
        mats.append(mat)
    idx = []
    for ring, s in rings:
        if rule_at:
            with part.w(rule_at(s)):
                idx.append([part.v(q) for q in ring])
        else:
            idx.append([part.v(q) for q in ring])
    for k in range(len(idx) - 1):
        A, B = idx[k], idx[k + 1]
        m = mats[k]
        if m is None:
            continue
        for i in range(seg):
            j = (i + 1) % seg
            part.f([A[i], A[j], B[j], B[i]], m, True)
    if cap0:
        part.f(list(reversed(idx[0])), cap_mat or mats[0], False)
    if cap1:
        part.f(list(idx[-1]), cap_mat or mats[-2], False)
    return idx


# --------------------------------------------------------------------------------------
# Rig and skinned mesh
# --------------------------------------------------------------------------------------
def build_rig(name="Rig"):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = {}
    for n, par, h, t in SKELETON:
        b = arm.edit_bones.new(n)
        b.head = h
        b.tail = t
        b.roll = 0.0
        b.use_deform = True
        if par:
            b.parent = eb[par]
            b.use_connect = False
        eb[n] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def build_skinned_mesh(part, rig, mset):
    ob = C.part_to_object(part, mset)
    ob.location = (0, 0, 0)
    ws = part.weights()
    groups = {n: ob.vertex_groups.new(name=n) for n in BONE_NAMES}
    for vi, w in enumerate(ws):
        for b, x in w.items():
            groups[b].add([vi], x, "REPLACE")
    ob.parent = rig
    md = ob.modifiers.new("Armature", "ARMATURE")
    md.object = rig
    return ob


def smooth_ao(ob, iterations=2, floor=None, name="AO", keep_corners_mats=("Frame", "Rubber", "Trim")):
    """Remove the speckle of the per-corner ray-cast AO: average the corners of each vertex, blur over the vertex
    neighbours, write back.  floor: {material: minimum AO}.  Corners on keep_corners_mats keep their own value
    (small hard parts want the crisp contact shadow)."""
    import numpy as np
    me = ob.data
    attr = me.color_attributes.get(name)
    if attr is None:
        return
    nl = len(me.loops)
    col = np.empty(nl * 4, dtype=np.float32)
    attr.data.foreach_get("color", col)
    val = col.reshape(-1, 4)[:, 0].astype(np.float64)
    lv = np.empty(nl, dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    nv = len(me.vertices)
    sums = np.bincount(lv, weights=val, minlength=nv)
    cnt = np.maximum(np.bincount(lv, minlength=nv), 1)
    v = sums / cnt
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    for _ in range(iterations):
        acc = v.copy()
        n = np.ones(nv)
        np.add.at(acc, ev[:, 0], v[ev[:, 1]])
        np.add.at(acc, ev[:, 1], v[ev[:, 0]])
        np.add.at(n, ev[:, 0], 1)
        np.add.at(n, ev[:, 1], 1)
        v = 0.5 * v + 0.5 * (acc / n)
    new = v[lv]
    # per-corner material
    pmat = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("material_index", pmat)
    ls = np.empty(len(me.polygons), dtype=np.int64)
    lt = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    cmat = np.repeat(pmat, lt)
    names = [m.name.split(".")[0] if m else "" for m in me.materials]
    for mi, nm in enumerate(names):
        sel = cmat == mi
        if nm in keep_corners_mats:
            new[sel] = val[sel]
        if floor and nm in floor:
            new[sel] = np.maximum(new[sel], floor[nm])
    out = np.repeat(new, 4).reshape(-1, 4).astype(np.float32)
    out[:, 3] = 1.0
    attr.data.foreach_set("color", out.ravel())
    me.update()


# --------------------------------------------------------------------------------------
# Pose solver
# --------------------------------------------------------------------------------------
def qeuler(rx=0.0, ry=0.0, rz=0.0):
    """World-axis rotation: X (roll) first, then Y (pitch), then Z (yaw).  Degrees."""
    return (Quaternion((0, 0, 1), radians(rz)) @ Quaternion((0, 1, 0), radians(ry)) @
            Quaternion((1, 0, 0), radians(rx)))


def q_from_frames(u0, w0, u1, w1):
    """Rotation that maps the orthonormal frame (u0, w0) onto (u1, w1)."""
    v0 = w0.cross(u0)
    v1 = w1.cross(u1)
    M0 = Matrix((u0, v0, w0)).transposed()
    M1 = Matrix((u1, v1, w1)).transposed()
    return (M1 @ M0.transposed()).to_quaternion()


FK_BONES = ["hips", "spine", "chest", "neck", "head"] + ["%s.%s" % (b, s) for s in SIDES for b in
                                                         ("shoulder", "upper_arm", "forearm", "hand")]


class Pose(dict):
    """Flat float parameters.  Missing keys are 0.
    <bone>.rx/.ry/.rz        rotation (deg) about world-aligned axes in the parent's frame (FK bones)
    hips.x/.y/.z             hips offset from the bind position (m)
    foot.S.x/.y/.z           ankle target in character space (m)  (S = L or R)
    foot.S.pitch/.yaw/.roll  foot orientation in character space (deg; pitch > 0 = toes down)
    toe.S.ry                 toe bend relative to the foot (deg; > 0 = toes down relative to the foot)
    knee.S.out               knee pole yaw added to the foot yaw (deg; > 0 = outward)
    arm.S.ik                 0..1 blend from FK arm to IK arm
    arm.S.x/.y/.z            wrist target in character space (m) for IK
    arm.S.pole               elbow pole direction: rotation (deg) of 'backward and outward' about the shoulder-wrist line
    hand.S.wx/.wy/.wz        hand orientation in character space, used with arm.S.ik (deg)
    """

    def g(self, k):
        return self.get(k, 0.0)


def mirror_key(k):
    """Parameter name and sign for the mirror image of a left-side parameter."""
    parts = k.split(".")
    if len(parts) < 3 or parts[1] not in SIDES:
        return None, 1.0
    side = "R" if parts[1] == "L" else "L"
    nk = ".".join([parts[0], side] + parts[2:])
    comp = parts[-1]
    sign = 1.0
    if comp in ("rx", "rz", "y", "yaw", "roll", "wx", "wz"):
        sign = -1.0
    return nk, sign


def sym(pose, **kw):
    """sym(p, **{'upper_arm.rx': -17}) sets upper_arm.L.rx = -17 and upper_arm.R.rx = +17 (mirrored)."""
    for k, val in kw.items():
        b, comp = k.rsplit(".", 1)
        lk = "%s.L.%s" % (b, comp)
        pose[lk] = val
        rk, sgn = mirror_key(lk)
        pose[rk] = val * sgn
    return pose


class Solver:
    def __init__(self):
        self.head = {n: BIND_HEAD[n].copy() for n in BONE_NAMES}
        self.tail = {n: BIND_TAIL[n].copy() for n in BONE_NAMES}
        self.rest_q = {}
        self.len = {n: (self.tail[n] - self.head[n]).length for n in BONE_NAMES}

    def set_rest_from_rig(self, rig):
        for b in rig.data.bones:
            self.rest_q[b.name] = b.matrix_local.to_3x3().to_quaternion()
            self.head[b.name] = b.head_local.copy()
            self.tail[b.name] = b.tail_local.copy()

    # --- core -------------------------------------------------------------------------
    def solve(self, P):
        """Returns (D: bone -> world delta quaternion, Q: bone -> local delta, pos: bone -> head position, hips_off)."""
        D, Q, pos = {}, {}, {}
        D["root"] = Quaternion()
        pos["root"] = self.head["root"].copy()
        hips_off = Vector((P.g("hips.x"), P.g("hips.y"), P.g("hips.z")))

        def fk(b, q):
            p = PARENT[b]
            Q[b] = q
            D[b] = D[p] @ q
            if b == "hips":
                pos[b] = self.head[b] + hips_off
            else:
                pos[b] = pos[p] + D[p] @ (self.head[b] - self.head[p])

        for b in ("hips", "spine", "chest", "neck", "head"):
            fk(b, qeuler(P.g(b + ".rx"), P.g(b + ".ry"), P.g(b + ".rz")))
        # optional head aim in character space: head.wx/wy/wz with weight head.aim
        aim = P.g("head.aim")
        if aim > 0:
            want = qeuler(P.g("head.wx"), P.g("head.wy"), P.g("head.wz"))
            cur = D["head"]
            tgt = cur.slerp(want, aim)
            Q["head"] = D["neck"].inverted() @ tgt
            D["head"] = tgt
        for s in SIDES:
            fk("shoulder." + s, qeuler(P.g("shoulder.%s.rx" % s), P.g("shoulder.%s.ry" % s), P.g("shoulder.%s.rz" % s)))
            self._arm(P, s, D, Q, pos, fk)
            self._leg(P, s, D, Q, pos)
        return D, Q, pos, hips_off

    def _arm(self, P, s, D, Q, pos, fk):
        ua, fa, hd, pr = "upper_arm." + s, "forearm." + s, "hand." + s, "prop." + s
        fk(ua, qeuler(P.g(ua + ".rx"), P.g(ua + ".ry"), P.g(ua + ".rz")))
        fk(fa, qeuler(P.g(fa + ".rx"), P.g(fa + ".ry"), P.g(fa + ".rz")))
        fk(hd, qeuler(P.g(hd + ".rx"), P.g(hd + ".ry"), P.g(hd + ".rz")))
        w = max(0.0, min(1.0, P.g("arm.%s.ik" % s)))
        if w > 1e-4:
            sgn = 1.0 if s == "L" else -1.0
            S_ = pos[ua]
            tgt = Vector((P.g("arm.%s.x" % s), P.g("arm.%s.y" % s), P.g("arm.%s.z" % s)))
            wc = max(0.0, min(1.0, P.g("arm.%s.chest" % s)))
            if wc > 0:
                # target given for the chest at rest; it rides with the chest (carrying)
                tgt = tgt.lerp(pos["chest"] + D["chest"] @ (tgt - self.head["chest"]), wc)
            l1 = (self.head[fa] - self.head[ua]).length
            l2 = (self.head[hd] - self.head[fa]).length
            d = tgt - S_
            dist = max(1e-4, min(d.length, (l1 + l2) * 0.995))
            dn = d.normalized()
            # pole: backward and outward, rotated about the shoulder-wrist line
            pole = D["chest"] @ Vector((-1.0, sgn * 0.55, -0.25))
            pole = Quaternion(dn, radians(P.g("arm.%s.pole" % s) * sgn)) @ pole
            pw = max(0.0, min(1.0, P.g("arm.%s.pw" % s)))
            if pw > 0:
                # elbow direction given in character space (lying and falling poses)
                wp = Vector((P.g("arm.%s.px" % s), P.g("arm.%s.py" % s), P.g("arm.%s.pz" % s)))
                if wp.length > 1e-6:
                    pole = pole.normalized().lerp(wp.normalized(), pw)
            pv = (pole - dn * pole.dot(dn)).normalized()
            a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
            h = sqrt(max(0.0, l1 * l1 - a * a))
            elbow = S_ + dn * a + pv * h
            wrist = S_ + dn * dist
            # FK directions for the blend
            y_ua_rest = (self.head[fa] - self.head[ua]).normalized()
            y_fa_rest = (self.head[hd] - self.head[fa]).normalized()
            Dp = D["shoulder." + s]
            # IK frames from the elbow's bend plane (independent of the FK arm: no flips when FK and IK point apart)
            y_ua = (elbow - S_).normalized()
            y_fa = (wrist - elbow).normalized()
            n0 = y_ua_rest.cross(y_fa_rest).normalized()
            nrm = y_ua.cross(y_fa)
            nrm = (nrm if nrm.length > 1e-6 else pv.cross(y_ua)).normalized()
            D_ua_ik = q_from_frames(n0, y_ua_rest, nrm, y_ua)
            D_fa_ik_frame = q_from_frames(n0, y_fa_rest, nrm, y_fa)
            D_ua = D[ua].slerp(D_ua_ik, w)
            Q[ua] = Dp.inverted() @ D_ua
            D[ua] = D_ua
            pos[fa] = pos[ua] + D[ua] @ (self.head[fa] - self.head[ua])
            D_fa_fk = D[ua] @ Q[fa]
            D_fa = D_fa_fk.slerp(D_fa_ik_frame, w)
            D_hd_w = qeuler(P.g("hand.%s.wx" % s), P.g("hand.%s.wy" % s), P.g("hand.%s.wz" % s))
            if wc > 0:
                D_hd_w = D_hd_w.slerp(D["chest"] @ D_hd_w, wc)
            # forearm pronation: move most of the hand's twist about the forearm axis into the forearm,
            # so the wrist only bends (a twisted wrist tears the glove gauntlet)
            ax = (D_fa @ y_fa_rest).normalized()
            pn0 = PALM_N.copy() if s == "L" else Vector((PALM_N.x, -PALM_N.y, PALM_N.z))
            p_cur = D_fa @ pn0
            p_des = D_hd_w @ pn0
            p_cur = p_cur - ax * p_cur.dot(ax)
            p_des = p_des - ax * p_des.dot(ax)
            if p_cur.length > 1e-4 and p_des.length > 1e-4:
                ang = math.atan2(ax.dot(p_cur.cross(p_des)), p_cur.dot(p_des))
                # the share fades to 0 at +/-180 deg, so the twist is continuous where atan2 wraps (no flips)
                # arm.S.stiff (0..1): the forearm takes all of the turn and the wrist keeps its FK bend, so the
                # hand's local rotation stays near the idle one (cross-fades between loops do not pop the wrist)
                stiff = max(0.0, min(1.0, P.g("arm.%s.stiff" % s)))
                k = (0.8 + 0.2 * stiff) * (1.0 - (abs(ang) / math.pi) ** 4)
                D_fa = Quaternion(ax, ang * k * w) @ D_fa
            Q[fa] = D[ua].inverted() @ D_fa
            D[fa] = D_fa
            pos[hd] = pos[fa] + D[fa] @ (self.head[hd] - self.head[fa])
            D_hd_fk = D[fa] @ Q[hd]
            D_hd = D_hd_fk.slerp(D_hd_w, w * (1.0 - stiff))
            Q[hd] = D[fa].inverted() @ D_hd
            D[hd] = D_hd
        Q[pr] = Quaternion()
        D[pr] = D[hd]
        pos[pr] = pos[hd] + D[hd] @ (self.head[pr] - self.head[hd])

    def _leg(self, P, s, D, Q, pos):
        th, sh, ft, to = "thigh." + s, "shin." + s, "foot." + s, "toe." + s
        hip = pos["hips"] + D["hips"] @ (self.head[th] - self.head["hips"])
        ankle = Vector((P.g("foot.%s.x" % s), P.g("foot.%s.y" % s), P.g("foot.%s.z" % s)))
        l1 = (self.head[sh] - self.head[th]).length
        l2 = (self.head[ft] - self.head[sh]).length
        d = ankle - hip
        L = l1 + l2
        dist = d.length
        dmax = L * 0.9995
        if dist > dmax:
            dist = dmax
        dn = d.normalized()
        yaw = P.g("foot.%s.yaw" % s) + P.g("knee.%s.out" % s)
        pole = Quaternion((0, 0, 1), radians(yaw)) @ Vector((1.0, 0.0, 0.0))
        wb = max(0.0, min(1.0, P.g("knee.%s.body" % s)))
        if wb > 0:
            # knee pole in the pelvis frame (lying, kneeling, falling): body forward turned by knee.out
            kb = D["hips"] @ (Quaternion((0, 0, 1), radians(P.g("knee.%s.out" % s))) @ Vector((1.0, 0.0, 0.0)))
            pole = pole.lerp(kb, wb)
        pv = pole - dn * pole.dot(dn)
        if pv.length < 1e-6:
            pv = Vector((1, 0, 0))
        pv.normalize()
        a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
        h = sqrt(max(0.0, l1 * l1 - a * a))
        knee = hip + dn * a + pv * h
        ank = hip + dn * dist
        # rest frames (knee faces +X at rest)
        y_th0 = (self.head[sh] - self.head[th]).normalized()
        y_sh0 = (self.head[ft] - self.head[sh]).normalized()
        x_ref0 = Vector((1, 0, 0))
        u_th0 = (x_ref0 - y_th0 * x_ref0.dot(y_th0)).normalized()
        u_sh0 = (x_ref0 - y_sh0 * x_ref0.dot(y_sh0)).normalized()
        y_th = (knee - hip).normalized()
        y_sh = (ank - knee).normalized()
        u_th = (pv - y_th * pv.dot(y_th)).normalized()
        u_sh = (pv - y_sh * pv.dot(y_sh)).normalized()
        D_th = q_from_frames(u_th0, y_th0, u_th, y_th)
        D_sh = q_from_frames(u_sh0, y_sh0, u_sh, y_sh)
        Q[th] = D["hips"].inverted() @ D_th
        D[th] = D_th
        pos[th] = hip
        Q[sh] = D_th.inverted() @ D_sh
        D[sh] = D_sh
        pos[sh] = hip + D_th @ (self.head[sh] - self.head[th])
        D_ft = qeuler(P.g("foot.%s.roll" % s), P.g("foot.%s.pitch" % s), P.g("foot.%s.yaw" % s))
        wr = max(0.0, min(1.0, P.g("foot.%s.rel" % s)))
        if wr > 0:
            # foot relative to the shin (ankle angle foot.S.rp, > 0 = pointed toes), for feet off the ground
            D_rel = D_sh @ qeuler(0.0, P.g("foot.%s.rp" % s), 0.0)
            D_ft = D_ft.slerp(D_rel, wr)
        Q[ft] = D_sh.inverted() @ D_ft
        D[ft] = D_ft
        pos[ft] = pos[sh] + D_sh @ (self.head[ft] - self.head[sh])
        q_toe = qeuler(0.0, P.g("toe.%s.ry" % s), 0.0)
        # toe bend about the foot's own lateral axis
        Q[to] = q_toe
        D[to] = D_ft @ q_toe
        pos[to] = pos[ft] + D_ft @ (self.head[to] - self.head[ft])

    # --- to Blender -------------------------------------------------------------------
    def basis(self, P):
        D, Q, pos, hips_off = self.solve(P)
        out = {}
        for b in BONE_NAMES:
            qr = self.rest_q[b]
            q = Q.get(b, Quaternion())
            out[b] = (qr.inverted() @ q @ qr).normalized()
        loc = self.rest_q["hips"].inverted() @ hips_off
        # prop bones: prop.S.w blends from riding on the hand to a pose in character space: origin at
        # (prop.S.x, .y, .z) and axes equal to the character axes (armature-space rotation = identity).
        plocs = {}
        for s in SIDES:
            pr, hd = "prop." + s, "hand." + s
            w = max(0.0, min(1.0, P.g("prop.%s.w" % s)))
            plocs[pr] = Vector((0.0, 0.0, 0.0))
            if w <= 0:
                continue
            qr = self.rest_q[pr]
            D_nom = D[pr]
            # armature-space rotation Rx(+90): the glTF exporter hands Godot the Blender bone axes unchanged, so this
            # is the identity basis (x forward, y up) in Godot's Y-up skeleton space (checked by art/npc/npc_probe.gd)
            want = Quaternion((1.0, 0.0, 0.0), radians(90.0)) @ qr.inverted()
            ptgt = Vector((P.g("prop.%s.x" % s), P.g("prop.%s.y" % s), P.g("prop.%s.z" % s)))
            wc = max(0.0, min(1.0, P.g("prop.%s.chest" % s)))
            if wc > 0:
                # crate pose given for the chest at rest; it rides with the chest
                ptgt = ptgt.lerp(pos["chest"] + D["chest"] @ (ptgt - self.head["chest"]), wc)
                want = want.slerp(D["chest"] @ want, wc)
            D_tgt = D_nom.slerp(want, w)
            Qp = D[hd].inverted() @ D_tgt
            out[pr] = (qr.inverted() @ Qp @ qr).normalized()
            nominal = pos[pr]
            tgt = nominal.lerp(ptgt, w)
            plocs[pr] = (D[hd] @ qr).inverted() @ (tgt - nominal)
            pos[pr] = tgt
            D[pr] = D_tgt
        self.last_prop_locs = plocs
        return out, loc, D, pos


# --------------------------------------------------------------------------------------
# Foot placement helpers (left side values; mirror with sym / mirror_key)
# --------------------------------------------------------------------------------------
def ankle_from_pivot(pivot_world, pivot_bind, pitch, yaw, ankle_bind=ANKLE_JOINT):
    """Ankle position that puts the foot point `pivot_bind` (bind pose) at `pivot_world`, for the foot orientation
    Rz(yaw) Ry(pitch)."""
    q = qeuler(0.0, pitch, yaw)
    return Vector(pivot_world) - q @ (Vector(pivot_bind) - ankle_bind)


def set_foot(P, s, ankle, pitch=0.0, yaw=0.0, roll=0.0, toe=0.0, knee_out=0.0):
    """Write the foot parameters for side s.  Values are given for the LEFT side and mirrored for 'R'."""
    sg = 1.0 if s == "L" else -1.0
    P["foot.%s.x" % s] = ankle[0]
    P["foot.%s.y" % s] = ankle[1] * sg
    P["foot.%s.z" % s] = ankle[2]
    P["foot.%s.pitch" % s] = pitch
    P["foot.%s.yaw" % s] = yaw * sg
    P["foot.%s.roll" % s] = roll * sg
    P["toe.%s.ry" % s] = toe
    P["knee.%s.out" % s] = knee_out * sg


# --------------------------------------------------------------------------------------
# Clip timeline: key poses + cubic Hermite (Catmull-Rom) with ease, lags per bone group
# --------------------------------------------------------------------------------------
def _keys_union(poses):
    ks = set()
    for p in poses:
        ks.update(p.keys())
    return sorted(ks)


def hermite(p0, p1, m0, m1, t):
    t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1


class Timeline:
    """keys: [(time_s, Pose, opts)] ; opts: {'hold': True} makes the key a stop (zero tangent).
    loop: periodic spline; otherwise the first and last keys ease in/out (zero tangents)."""

    def __init__(self, keys, loop=False, length=None):
        self.keys = sorted(keys, key=lambda k: k[0])
        self.loop = loop
        self.length = length if length is not None else self.keys[-1][0]
        self.names = _keys_union([k[1] for k in self.keys])

    def sample_key(self, name, t):
        ks = self.keys
        n = len(ks)
        if self.loop:
            t = t % self.length
            times = [k[0] for k in ks] + [ks[0][0] + self.length]
            vals = [k[1].g(name) for k in ks] + [ks[0][1].g(name)]
            holds = [k[2].get("hold", False) if len(k) > 2 else False for k in ks] + \
                    [ks[0][2].get("hold", False) if len(ks[0]) > 2 else False]
        else:
            t = max(ks[0][0], min(ks[-1][0], t))
            times = [k[0] for k in ks]
            vals = [k[1].g(name) for k in ks]
            holds = [k[2].get("hold", False) if len(k) > 2 else False for k in ks]
        m = len(times)
        i = 0
        while i < m - 2 and t > times[i + 1]:
            i += 1

        def tangent(j):
            if holds[j]:
                return 0.0
            if self.loop:
                jp = j - 1 if j > 0 else m - 2
                jn = j + 1 if j < m - 1 else 1
                tp = times[jp] - (self.length if j == 0 else 0.0)
                tn = times[jn] + (self.length if j == m - 1 else 0.0)
            else:
                if j == 0 or j == m - 1:
                    return 0.0
                jp, jn, tp, tn = j - 1, j + 1, times[j - 1], times[j + 1]
            # monotone (Fritsch-Butland) tangent: no overshoot past a key, zero at a turning point
            tj = times[j]
            if tj - tp <= 1e-9 or tn - tj <= 1e-9:
                return 0.0
            d0 = (vals[j] - vals[jp]) / (tj - tp)
            d1 = (vals[jn] - vals[j]) / (tn - tj)
            if d0 * d1 <= 0.0:
                return 0.0
            return 2.0 / (1.0 / d0 + 1.0 / d1)
        t0, t1 = times[i], times[i + 1]
        h = t1 - t0
        u = 0.0 if h <= 0 else (t - t0) / h
        return hermite(vals[i], vals[i + 1], tangent(i) * h, tangent(i + 1) * h, u)

    def sample(self, t, lags=None):
        P = Pose()
        for nm in self.names:
            lag = 0.0
            if lags:
                for prefix, lg in lags.items():
                    if nm.startswith(prefix):
                        lag = lg
                        break
            P[nm] = self.sample_key(nm, t - lag)
        # hand orientations: slerp between keys (eased), not three Euler splines (no gimbal swings)
        for s in SIDES:
            ks = ["hand.%s.w%s" % (s, c) for c in "xyz"]
            if not all(k in self.names for k in ks):
                continue
            lag = 0.0
            if lags:
                for prefix, lg in lags.items():
                    if ks[0].startswith(prefix):
                        lag = lg
                        break
            q = self._slerp_hand(ks, t - lag)
            e = q.to_euler("XYZ")
            P[ks[0]], P[ks[1]], P[ks[2]] = degrees(e.x), degrees(e.y), degrees(e.z)
        return P

    def _slerp_hand(self, ks, t):
        keys = self.keys
        if self.loop:
            t = t % self.length
            times = [k[0] for k in keys] + [keys[0][0] + self.length]
            poses = [k[1] for k in keys] + [keys[0][1]]
        else:
            t = max(keys[0][0], min(keys[-1][0], t))
            times = [k[0] for k in keys]
            poses = [k[1] for k in keys]
        i = 0
        while i < len(times) - 2 and t > times[i + 1]:
            i += 1
        h = times[i + 1] - times[i]
        u = 0.0 if h <= 0 else max(0.0, min(1.0, (t - times[i]) / h))
        u = u * u * (3.0 - 2.0 * u)
        q0 = qeuler(poses[i].g(ks[0]), poses[i].g(ks[1]), poses[i].g(ks[2]))
        q1 = qeuler(poses[i + 1].g(ks[0]), poses[i + 1].g(ks[1]), poses[i + 1].g(ks[2]))
        if q0.dot(q1) < 0:
            q1 = -q1
        return q0.slerp(q1, u)


# --------------------------------------------------------------------------------------
# Baking clips into Blender actions
# --------------------------------------------------------------------------------------
def bake_clip(rig, solver, name, pose_fn, frames, fix=None):
    """pose_fn(frame) -> Pose for frame 0..frames (inclusive).  Writes every bone's rotation and the hips and
    root locations for every frame (linear), then pushes the action onto its own NLA track."""
    ad = rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    slot = ad.action_slot
    data = {b: [] for b in BONE_NAMES}
    hips_loc = []
    prop_locs = {s_: [] for s_ in SIDES}
    prev = {}
    for f in range(frames + 1):
        P = pose_fn(f)
        if fix:
            P = fix(P)
        qb, loc, _, _ = solver.basis(P)
        for s_ in SIDES:
            prop_locs[s_].append(solver.last_prop_locs["prop." + s_].copy())
        for b in BONE_NAMES:
            q = qb[b]
            if b in prev:
                if prev[b].dot(q) < 0:              # continuity inside the clip
                    q = -q
            elif q.w < 0:                           # every clip starts in the w >= 0 hemisphere (clips blend safely)
                q = -q
            prev[b] = q
            data[b].append(q)
        hips_loc.append(loc)

    def put(path, idx, vals, group):
        fc = act.fcurve_ensure_for_datablock(rig, path, index=idx, group_name=group)
        fc.keyframe_points.clear()
        fc.keyframe_points.add(len(vals))
        co = []
        for f, v in enumerate(vals):
            co += [float(f), float(v)]
        fc.keyframe_points.foreach_set("co", co)
        fc.keyframe_points.foreach_set("interpolation", [1] * len(vals))   # LINEAR
        fc.update()

    for b in BONE_NAMES:
        path = 'pose.bones["%s"].rotation_quaternion' % b
        for i in range(4):
            put(path, i, [q[i] for q in data[b]], b)
    for i in range(3):
        put('pose.bones["hips"].location', i, [l[i] for l in hips_loc], "hips")
        put('pose.bones["root"].location', i, [0.0] * (frames + 1), "root")
        for s_ in SIDES:
            put('pose.bones["prop.%s"].location' % s_, i, [l[i] for l in prop_locs[s_]], "prop." + s_)
    act.frame_range = (0, frames)
    act.use_frame_range = True
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, 0, act)
    st.action_frame_start = 0
    st.action_frame_end = frames
    tr.mute = True
    ad.action = None
    return act


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)


# --------------------------------------------------------------------------------------
# Export
# --------------------------------------------------------------------------------------
def export_glb_skinned(path, animations=True, only=None):
    """only: objects to export (the rig must be among them); None = the whole scene."""
    tmp = path[:-4] + ".tmp.glb"
    if os.path.exists(tmp):
        os.remove(tmp)
    sc = bpy.context.scene
    if only is not None:
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for o in only:
            o.select_set(True)
    sc.render.fps = FPS
    sc.render.fps_base = 1.0
    bpy.ops.export_scene.gltf(
        filepath=tmp,
        export_format="GLB",
        use_selection=only is not None,
        export_apply=False,
        export_yup=True,
        export_animations=animations,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_frame_step=1,
        export_optimize_animation_size=True,
        export_optimize_animation_keep_anim_armature=False,
        export_optimize_animation_keep_anim_object=False,
        export_anim_slide_to_zero=False,
        export_bake_animation=False,
        export_skins=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_influence_nb=4,
        export_all_influences=False,
        export_rest_position_armature=True,
        export_cameras=False,
        export_lights=False,
        export_morph=False,
        export_extras=False,
        export_materials="EXPORT",
        export_normals=True,
        export_tangents=False,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True,
    )
    os.replace(tmp, path)


def read_glb(path):
    return C.read_glb(path)


def glb_accessor(g, binary, idx):
    """numpy array for accessor idx."""
    import numpy as np
    acc = g["accessors"][idx]
    bv = g["bufferViews"][acc["bufferView"]]
    comp = {5126: np.float32, 5123: np.uint16, 5121: np.uint8, 5125: np.uint32, 5122: np.int16, 5120: np.int8}[acc["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    itemsize = np.dtype(comp).itemsize * n
    if stride and stride != itemsize:
        raw = np.frombuffer(binary, dtype=np.uint8, count=stride * acc["count"], offset=off).reshape(acc["count"], stride)
        arr = raw[:, :itemsize].copy().view(comp).reshape(acc["count"], n)
    else:
        arr = np.frombuffer(binary, dtype=comp, count=acc["count"] * n, offset=off).reshape(acc["count"], n).copy()
    if acc.get("normalized"):
        arr = arr.astype(np.float32) / float(np.iinfo(comp).max)
    return arr


# --------------------------------------------------------------------------------------
# Weight rules shared by both variants (the joints are the same, so the blends are the same)
# --------------------------------------------------------------------------------------
def side_vec(v, s):
    v = Vector(v)
    return v if s == "L" else Vector((v.x, -v.y, v.z))


def torso_rule(pelvis_thigh=0.55, low=0.99, shoulder_z=(1.33, 1.43)):
    """hips -> spine -> chest along Z; the low pelvis follows the thighs a little, the shoulder caps the clavicles."""
    def extra(p, out):
        if p.z < low and abs(p.y) > 0.005:
            s = "L" if p.y > 0 else "R"
            t = sstep(low, low - 0.15, p.z) * sstep(0.0, 0.08, abs(p.y)) * pelvis_thigh
            for k in list(out):
                out[k] *= (1.0 - t)
            out["thigh." + s] = out.get("thigh." + s, 0.0) + t
        if p.z > shoulder_z[0] and abs(p.y) > 0.09:
            s = "L" if p.y > 0 else "R"
            t = sstep(shoulder_z[0], shoulder_z[1], p.z) * sstep(0.09, 0.20, abs(p.y)) * 0.5
            for k in list(out):
                out[k] *= (1.0 - t)
            out["shoulder." + s] = out.get("shoulder." + s, 0.0) + t
    return Chain(["hips", "spine", "chest"],
                 [((0, 0, 1.055), (0, 0, 1), 0.035), ((0, 0, 1.165), (0, 0, 1), 0.03)], extra)


def arm_rule(s):
    sh, el, wr = side_vec(SH_JOINT, s), side_vec(EL_JOINT, s), side_vec(WR_JOINT, s)
    ua, fa = side_vec(_UA, s), side_vec(_FA, s)
    elbow_axis = (ua + fa).normalized()
    return Chain(["shoulder." + s, "upper_arm." + s, "forearm." + s, "hand." + s],
                 [(sh + ua * 0.02, ua, (0.03, 0.05)), (el, elbow_axis, 0.05), (wr - fa * 0.01, fa, 0.022)])


def leg_rule(s):
    hip, kn, an, ball = side_vec(HIP_JOINT, s), side_vec(KNEE_JOINT, s), side_vec(ANKLE_JOINT, s), side_vec(BALL_JOINT, s)
    th = (kn - hip).normalized()
    shd = (an - kn).normalized()
    return Chain(["hips", "thigh." + s, "shin." + s, "foot." + s, "toe." + s],
                 [(hip, th, (0.02, 0.10)), (kn, (th + shd).normalized(), 0.055), (an + Vector((0, 0, 0.005)), (0, 0, -1), 0.03),
                  (ball, (1, 0, 0), 0.018)])


def ribs(center, r, count=3, pitch=0.026, height=0.009, half=0.007, rib_mat="Trim", base_mat="SuitMain", du=0.0):
    """Tube stations for `count` bellows ribs centred on arc length `center` (for tube_path)."""
    out = []
    s0 = center - pitch * (count - 1) / 2.0
    for k in range(count):
        c = s0 + pitch * k
        out += [(c - half, r, r, rib_mat, du), (c, r + height, r + height, rib_mat, du), (c + half, r, r, base_mat, du)]
    return out


def hand_frame(s):
    """Local frame of the hand in the bind pose: x = thumb side (forward), y = palm side, z = along the hand."""
    wr = side_vec(WR_JOINT, s)
    fa = side_vec(_FA, s)
    pn = side_vec(PALM_N, s)
    w = fa
    v = (pn - w * pn.dot(w)).normalized()
    u = v.cross(w).normalized()
    if u.x < 0:
        u = -u
    return wr, fa, Matrix((u, v, w)).transposed().to_4x4()


def build_hand(p, s, mat="Pack", palm_mat="Rubber", tip_mat=None, scale=1.0, cuff=True, cuff_mat="Pack",
               cuff_r=(0.056, 0.059, 0.058, 0.052), ring_mat="Frame", finger_seg=8):
    """Glove or bare hand on the hand bone: palm block, four 8-sided fingers in two pairs, rounded tips, thumb."""
    wr, fa, M = hand_frame(s)
    k = scale
    if cuff:
        hand_rule = Chain(["forearm." + s, "hand." + s], [(wr + fa * 0.012, fa, 0.024)])
        with p.w(hand_rule):
            with p.at(T(*wr), M):
                a, b, c, d = cuff_r
                if ring_mat:      # a raised ring band at the cuff opening, then the gauntlet
                    prof = [(a, -0.036), (b + 0.005, -0.010), (b + 0.005, 0.002), (c, 0.022), (d, 0.040)]
                    p.lathe(prof, lambda kk, ii: ring_mat if kk == 1 else cuff_mat, seg=12, smooth=True)
                else:
                    p.lathe([(a, -0.036), (b, -0.004), (c, 0.022), (d, 0.040)], cuff_mat, seg=12, smooth=True)
    tip_mat = tip_mat or mat
    with p.w("hand." + s):
        with p.at(T(*wr), M, S(k, k, k)):
            p.box((0.0, 0.0, 0.072), (0.088, 0.046, 0.080), mat, bevel=0.016, mats={"+y": palm_mat})
            xs = (-0.0320, -0.0112, 0.0098, 0.0345)            # little, ring, middle together; the index apart
            for i, x in enumerate(xs):
                ln = (0.041, 0.050, 0.053, 0.047)[i]
                curl = 0.0 if i == 3 else 1.0                  # the three together curl 20 deg more
                b0 = Vector((x, 0.002, 0.104))
                b1 = b0 + Vector((0.0, 0.010 + 0.012 * curl, ln * 0.58))
                b2 = b1 + Vector((0.0, 0.020 + 0.014 * curl, ln * (0.34 - 0.06 * curl)))
                d = (b2 - b1).normalized()
                p.tube([b0, b1, b2], 0.0118, seg=finger_seg, mat=mat, caps=False)
                t1 = b2 + d * 0.006
                t2 = b2 + d * 0.0115
                p.cyl(tuple(b2), tuple(t1), 0.0118, 0.0092, seg=finger_seg, mat=tip_mat, cap0=False, cap1=False)
                p.cyl(tuple(t1), tuple(t2), 0.0092, 0.0, seg=finger_seg, mat=tip_mat, cap0=False, cap1=False)
            t0 = Vector((0.036, 0.012, 0.046))
            t1 = t0 + Vector((0.016, 0.020, 0.030))              # thumb 15 deg further in
            t2 = t1 + Vector((-0.003, 0.022, 0.022))
            d = (t2 - t1).normalized()
            p.tube([t0, t1, t2], 0.0132, seg=finger_seg, mat=mat, caps=False)
            p.cyl(tuple(t2), tuple(t2 + d * 0.007), 0.0132, 0.0100, seg=finger_seg, mat=tip_mat, cap0=False, cap1=False)
            p.cyl(tuple(t2 + d * 0.007), tuple(t2 + d * 0.013), 0.0100, 0.0, seg=finger_seg, mat=tip_mat, cap0=False, cap1=False)
