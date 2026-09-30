"""
Frontier Habitat 5.0 - ART-NPC: the contract uniforms for the MPFB people (V5 section 1), one coverall cut for every
department plus per-department add-ons.  Version 2 (2026-10-01, CRITIC round 40 people_outfits):

  * every open edge is a CLEAN cut: bmesh bisect planes (trouser hems, cuffs, neckline), never a vertex delete;
  * the department stripe is part of the coverall surface (bisected bands: chest round, both upper sleeves, both
    lower legs), not floating geometry; the zip and the pockets are bisected and extruded the same way;
  * straight trouser legs and loose sleeves (a cylinder from the knee / elbow down), a turn-down collar, rolled hems;
  * add-ons (separate small meshes, shown per role): toolbelt, apron (food), vest (security), labcoat (science),
    tunic (medical), jacket (command), rank1..rank3 (shoulder boards with 1..3 bars, on any uniform).

make_uniform(base, J) -> (shell, {addon_name: object}).  Every vertex keeps MakeHuman vertex groups (interpolated by
the bisects, copied by the extrusions), so people_mpfb.move_weights maps them to our skeleton like any garment.
Material slots are placeholders by name: UniformBase, SuitAccent, Zip, Leather, Metal, Apron, Armor, Rank, Coat
(people_mpfb.uniform_materials gives them the real materials).
"""
import bpy
import bmesh
from math import sin, cos, pi, atan2, sqrt
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OFF = dict(torso=0.022, arm=0.015, leg=0.018)
UV_REPEAT = 5.0
SHELL_TRIS = 3700                    # the coverall before the bands, pockets and rims (decimated body copy)

# department looks: base colour (UniformBase tint), add-ons.  prison: the same coverall, orange, no stripe colour of
# its own (accent = a light grey band, as prison overalls carry).
DEPARTMENTS = {
    "uniform_engineering": dict(base=(0.30, 0.34, 0.40), addons=["toolbelt"], who=["technician", "operator"],
                                look="slate coverall, amber reflective bands (chest, upper sleeves, lower legs), "
                                     "chest and thigh pockets, tool belt with pouches, work boots"),
    "uniform_science": dict(base=(0.52, 0.58, 0.66), addons=["labcoat"], who=["scientist"],
                            look="light slate coverall, blue bands, white knee-length lab coat with blue collar and "
                                 "sleeve bands"),
    "uniform_food": dict(base=(0.50, 0.58, 0.47), addons=["apron"], who=["grower", "kitchen", "venue staff"],
                         look="sage coverall, green bands, white bib apron with ties"),
    "uniform_medical": dict(base=(0.78, 0.86, 0.88), addons=["tunic"], who=["medic"],
                            look="pale scrubs coverall, white tunic with red collar and sleeve bands, red bands"),
    "uniform_security": dict(base=(0.10, 0.10, 0.12), addons=["vest", "toolbelt"], who=["security officer"],
                             look="black coverall, armoured vest with shoulder straps, red bands, duty belt"),
    "uniform_command": dict(base=(0.09, 0.13, 0.26), addons=["jacket", "rank3"], who=["commander", "captains"],
                            look="navy coverall, tailored hip-length jacket with a stand collar, shoulder boards with "
                                 "rank bars"),
    "prison": dict(base=(0.86, 0.36, 0.08), addons=[], who=["prisoner"], accent=(0.80, 0.80, 0.78),
                   look="orange coverall, light grey bands, no pockets used"),
}
RANK_ADDONS = ["rank1", "rank2", "rank3"]


# ------------------------------------------------------------------------------------------------------------------
# small geometry helpers
# ------------------------------------------------------------------------------------------------------------------
def _slot(ob, name):
    for i, m in enumerate(ob.data.materials):
        if m and m.name.split(".")[0] == name:
            return i
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    ob.data.materials.append(m)
    return len(ob.data.materials) - 1


def _seg_t(p, a, b):
    d = b - a
    L2 = d.length_squared
    t = (p - a).dot(d) / L2 if L2 > 0 else 0.0
    return t, (p - (a + d * max(0.0, min(1.0, t)))).length


def _classify(p, J, full=False):
    """'arm' / 'leg' / 'torso' region of a point; full: (region, segment 0 upper / 1 lower, t along it, side)."""
    best = ("torso", 9.0, 0.0, 0, "")
    for s in ("L", "R"):
        for part, seg, a, b in (("arm", 0, J["upper_arm." + s], J["forearm." + s]),
                                ("arm", 1, J["forearm." + s], J["hand." + s]),
                                ("leg", 0, J["thigh." + s], J["shin." + s]), ("leg", 1, J["shin." + s], J["foot." + s])):
            t, d = _seg_t(p, a, b)
            lim = 0.11 if part == "leg" else 0.10
            if 0.0 <= t <= 1.1 and d < lim and d < best[1]:
                best = (part, d, t, seg, s)
    if part_is_torso_override(p, J, best):
        best = ("torso", 9.0, 0.0, 0, "")
    return (best[0], best[3], best[2], best[4]) if full else best[0]


def part_is_torso_override(p, J, best):
    """Points above the crotch between the hip joints are torso (the pelvis), not the upper thigh."""
    if best[0] != "leg" or best[3] != 0:
        return False
    return best[2] < 0.12 and abs(p.y) < abs(J["thigh.L"].y) * 0.55


def _faces(bm, pred):
    return [f for f in bm.faces if pred(f)]


def _geom(faces):
    vs, es = set(), set()
    for f in faces:
        vs.update(f.verts)
        es.update(f.edges)
    return list(vs) + list(es) + list(faces)


def _cut(bm, faces, co, no, clear=True):
    """Bisect the given faces by the plane (co, no); clear=True deletes their part on the side `no` points to."""
    if not faces:
        return
    bmesh.ops.bisect_plane(bm, geom=_geom(faces), dist=1e-5, plane_co=co, plane_no=no, clear_outer=clear)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()


def _keep_largest(bm):
    bm.verts.ensure_lookup_table()
    seen, pieces = set(), []
    for v in bm.verts:
        if v in seen:
            continue
        stack, comp = [v], []
        seen.add(v)
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                o = e.other_vert(x)
                if o not in seen:
                    seen.add(o)
                    stack.append(o)
        pieces.append(comp)
    pieces.sort(key=len, reverse=True)
    for comp in pieces[1:]:
        bmesh.ops.delete(bm, geom=comp, context="VERTS")


def _drop_loose(bm):
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")


def _bm_of(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.transform(ob.matrix_world)
    return bm


def _tree(ob_or_bm):
    if isinstance(ob_or_bm, bmesh.types.BMesh):
        return BVHTree.FromBMesh(ob_or_bm)
    bm = _bm_of(ob_or_bm)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def _obj(name, bm, base, mats=("UniformBase",)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for g in base.vertex_groups:
        if g.name not in ob.vertex_groups:
            ob.vertex_groups.new(name=g.name)
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    for m in mats:
        _slot(ob, m)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def _boundary_loops(bm):
    edges = {e for e in bm.edges if e.is_boundary}
    loops = []
    while edges:
        e = edges.pop()
        loop = [e.verts[0], e.verts[1]]
        closed = False
        while True:
            last = loop[-1]
            nxt = None
            for e2 in last.link_edges:
                if e2 in edges:
                    nxt = e2
                    break
            if nxt is None:
                break
            edges.discard(nxt)
            o = nxt.other_vert(last)
            if o is loop[0]:
                closed = True
                break
            loop.append(o)
        if closed and len(loop) >= 6:
            loops.append(loop)
    return loops


def _copy_deform(dst, src, dl, dl_src=None):
    for k_, w_ in src[dl_src or dl].items():
        dst[dl][k_] = w_


def _relax_loops(bm, it=3, z_only=False):
    """Even out every open edge along itself (after offsets and push-outs the edge vertices zigzag)."""
    for loop in _boundary_loops(bm):
        n_ = len(loop)
        for _ in range(it):
            pts = [v.co.copy() for v in loop]
            for i, v in enumerate(loop):
                q = pts[i] * 0.5 + (pts[i - 1] + pts[(i + 1) % n_]) * 0.25
                if z_only:
                    v.co.z = q.z
                else:
                    v.co = q


def _limb_band(bm, J, s, part, seg, t0, hh, mat_i, lift=0.0012):
    """A band round a limb segment: two bisect planes across the segment axis at t0 +- hh; the faces between them
    take material mat_i (clean straight edges)."""
    a_j, b_j = {("arm", 0): ("upper_arm.", "forearm."), ("arm", 1): ("forearm.", "hand."),
                ("leg", 0): ("thigh.", "shin."), ("leg", 1): ("shin.", "foot.")}[(part, seg)]
    a, b = J[a_j + s], J[b_j + s]
    ax = (b - a).normalized()
    m = a + (b - a) * t0

    def on(f):
        r = _classify(f.calc_center_median(), J, True)
        return r[0] == part and r[3] == s and abs((f.calc_center_median() - m).dot(ax)) < 0.08
    for dd in (-hh, hh):
        _cut(bm, _faces(bm, on), m + ax * dd, ax, clear=False)
    marked = [f for f in bm.faces if on(f) and abs((f.calc_center_median() - m).dot(ax)) < hh]
    for f in marked:
        f.material_index = mat_i
    for v in {v for f in marked for v in f.verts}:
        v.co += v.normal * lift
    return marked


def _smooth(bm, verts, it, fac=0.5):
    for _ in range(it):
        bmesh.ops.smooth_vert(bm, verts=verts, factor=fac, use_axis_x=True, use_axis_y=True, use_axis_z=True)


def _push_out_n(bm, tree, gap, it=3):
    """Along each vertex's OWN normal: out until it is `gap` outside the surface in `tree` (add-ons over the shell)."""
    for _ in range(it):
        bm.normal_update()
        for v in bm.verts:
            hit = tree.find_nearest(v.co, 0.06)
            if hit[0] is None:
                continue
            s = (v.co - hit[0]).dot(hit[1])
            if s < gap:
                v.co += v.normal * (gap - s) * 0.8


def _push_out(bm, tree, gap):
    """No vertex closer than `gap` to the surface in `tree` (smoothing shrinks)."""
    for v in bm.verts:
        hit = tree.find_nearest(v.co, 0.08)
        if hit[0] is not None and (v.co - hit[0]).dot(hit[1]) < gap:
            v.co = hit[0] + hit[1] * gap


# ------------------------------------------------------------------------------------------------------------------
# the coverall
# ------------------------------------------------------------------------------------------------------------------
def _levels(J):
    sh = J["upper_arm.L"].z
    return dict(shoulder=sh, hem=J["foot.L"].z + 0.080, waist=J["hips"].z + 0.075, band=sh - 0.135,
                neck=J["neck"].z, knee=J["shin.L"].z)


def body_copy(base, J):
    """The body minus head, hands and feet (generous margins), decimated to about SHELL_TRIS: the coverall's source."""
    bm = _bm_of(base)
    dl = bm.verts.layers.deform.active
    gi = {g.name: g.index for g in base.vertex_groups}
    body = gi.get("body")
    L = _levels(J)
    kill = set()
    for v in bm.verts:
        p = v.co
        if body is not None and v[dl].get(body, 0.0) < 0.5:
            kill.add(v)
            continue
        if p.z > L["neck"] + 0.06 or p.z < L["hem"] - 0.05:
            kill.add(v)
            continue
        for s in ("L", "R"):
            t, d = _seg_t(p, J["forearm." + s], J["hand." + s])
            if t > 1.04 and d < 0.14:
                kill.add(v)
    bmesh.ops.delete(bm, geom=list(kill), context="VERTS")
    _keep_largest(bm)
    for f in bm.faces:
        f.material_index = 0
    ob = _obj("npc_shell_tmp", bm, base)
    bm.free()
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > SHELL_TRIS:
        mod = ob.modifiers.new("Dec", "DECIMATE")
        mod.ratio = SHELL_TRIS / tris
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="Dec")
    return ob


def clean_cuts(bm, J):
    """Trouser hems, cuffs and the neckline as bisect planes (clean, level edges)."""
    L = _levels(J)
    _cut(bm, _faces(bm, lambda f: f.calc_center_median().z < L["hem"] + 0.06), Vector((0, 0, L["hem"])),
         Vector((0, 0, -1)))
    for s in ("L", "R"):
        a, b = J["forearm." + s], J["hand." + s]
        ax = (b - a).normalized()
        co = b - ax * 0.018
        _cut(bm, _faces(bm, lambda f: _seg_t(f.calc_center_median(), a, b)[0] > 0.7 and
                        (f.calc_center_median() - b).length < 0.22), co, ax)
    # neckline: a plane through the neck base, 18 deg lower at the front
    nc = Vector((J["neck"].x, 0.0, L["neck"] - 0.012))
    no = Vector((0.21, 0.0, 1.0)).normalized()
    _cut(bm, _faces(bm, lambda f: f.calc_center_median().z > L["shoulder"] - 0.08 and
                    Vector((f.calc_center_median().x - nc.x, f.calc_center_median().y, 0)).length < 0.13), nc, no)
    _drop_loose(bm)
    _keep_largest(bm)


def shape_cloth(bm, J, body_tree):
    """Offset from the body, straight trouser legs below the knee, loose sleeves, a belt-line cinch, smoothed."""
    L = _levels(J)
    bm.normal_update()
    info = {v: _classify(v.co, J, True) for v in bm.verts}
    new = {}
    for v in bm.verts:
        reg, seg, tt, s = info[v]
        off = OFF[reg]
        if reg == "leg":
            off += 0.004 + 0.006 * (tt if seg == 1 else 0.0)
        elif reg == "arm":
            off += 0.005 * (tt if seg == 1 else 0.0)
        if reg == "torso" and abs(v.co.z - L["waist"]) < 0.06:
            off *= 0.62 + 0.38 * abs(v.co.z - L["waist"]) / 0.06
        new[v] = v.co + v.normal * off
    for v, p in new.items():
        v.co = p
    # straight legs / loose sleeves: below the knee (elbow) the section becomes round, its radius the knee's (elbow's)
    for s in ("L", "R"):
        for part, a_j, b_j, grow in (("leg", "shin." + s, "foot." + s, 0.03), ("arm", "forearm." + s, "hand." + s, 0.02)):
            a, b = J[a_j], J[b_j]
            ax = (b - a).normalized()
            ring = [v for v in bm.verts if info[v][0] == part and info[v][3] == s and abs(_seg_t(v.co, a, b)[0]) < 0.04]
            if not ring:
                continue

            def rad(p):
                t = (p - a).dot(ax)
                c = a + ax * t
                return (p - c), t
            R0 = sorted(rad(v.co)[0].length for v in ring)[int(len(ring) * 0.6)]
            Lseg = (b - a).length
            for v in bm.verts:
                if info[v][0] != part or info[v][3] != s:
                    continue
                r, t = rad(v.co)
                u = t / Lseg
                if u <= 0.0:
                    continue
                w = min(1.0, u / 0.30)
                w = w * w * (3 - 2 * w)
                R = R0 * (1.0 + grow * u)
                if part == "arm" and u > 0.85:
                    R *= 1.0 - 0.10 * (u - 0.85) / 0.15          # the cuff gathers
                if r.length < 1e-6:
                    continue
                target = r.normalized() * max(R, r.length * 0.97)
                v.co = (a + ax * t) + r.lerp(target, w)
    boundary = {v for v in bm.verts if any(e.is_boundary for e in v.link_edges)}
    interior = [v for v in bm.verts if v not in boundary]
    _smooth(bm, interior, 10)
    torso = [v for v in interior if info.get(v, ("",))[0] == "torso"]
    _smooth(bm, torso, 14)
    _push_out(bm, body_tree, 0.008)
    _relax_loops(bm, 4)
    # soft folds: horizontal ripples at the elbows, behind the knees and above the boots (the trouser break)
    for v in interior:
        reg, seg, tt, s = info[v]
        if reg == "leg" and seg == 1 and v.co.z < L["hem"] + 0.07:
            v.co += (v.co - Vector((J["foot." + s].x, J["foot." + s].y, v.co.z))).normalized() * \
                0.0020 * sin(pi * (v.co.z - L["hem"]) / 0.035) ** 2
        for jn in ("forearm." + (s or "L"), "shin." + (s or "L")):
            dj = (v.co - J[jn]).length
            if reg != "torso" and dj < 0.07:
                v.co += v.normal * 0.0025 * sin(pi * dj / 0.024) ** 2 * (1.0 - dj / 0.07)
    bm.normal_update()


def _rings_on_loops(bm, dl, loops, J):
    """Rolled hems on the cuffs and trouser hems (three rings: out, down, in)."""
    L = _levels(J)
    faces = []
    for loop in loops:
        zc = sum(v.co.z for v in loop) / len(loop)
        if zc > L["shoulder"] - 0.10:
            continue                                      # the neckline: collar
        centre = sum((v.co for v in loop), Vector()) / len(loop)
        is_hem = zc < 0.5
        rings = []
        for v in loop:
            radial = v.co - centre
            if is_hem:
                radial.z = 0.0
            radial = radial.normalized() if radial.length > 1e-6 else Vector((1, 0, 0))
            a = bm.verts.new(v.co + radial * 0.0035 + (Vector((0, 0, 0.004)) if is_hem else Vector()))
            b = bm.verts.new(v.co + radial * 0.0035 + (Vector((0, 0, 0.022)) if is_hem else Vector()))
            c = bm.verts.new(v.co + (Vector((0, 0, 0.024)) if is_hem else Vector()))
            for nv in (a, b, c):
                _copy_deform(nv, v, dl)
            rings.append((v, a, b, c))
        n = len(rings)
        for i in range(n):
            v0, a0, b0, c0 = rings[i]
            v1, a1, b1, c1 = rings[(i + 1) % n]
            for q in ((v0, v1, a1, a0), (a0, a1, b1, b0), (b0, b1, c1, c0)):
                try:
                    faces.append(bm.faces.new(q))
                except ValueError:
                    pass
    return faces


def _cuff_bands(bm, J):
    """Cuffs as bands on the sleeve end (the sleeve's last 3 cm become a gathered band, bisected)."""
    for s in ("L", "R"):
        a, b = J["forearm." + s], J["hand." + s]
        ax = (b - a).normalized()
        co = b - ax * 0.050
        fs = _faces(bm, lambda f: _classify(f.calc_center_median(), J) == "arm" and
                    _seg_t(f.calc_center_median(), a, b)[0] > 0.6 and
                    (f.calc_center_median() - b).length < 0.16)
        _cut(bm, fs, co, ax, clear=False)


def turn_down_collar(bm, dl, J, style="turn"):
    """A shirt collar on the neckline loop: a 2.6 cm stand, a fold, a 3.4 cm fall onto the shoulders with points at
    the front, two layers (the inside is seen).  Open at the front (the zip)."""
    L = _levels(J)
    loops = [lp for lp in _boundary_loops(bm) if sum(v.co.z for v in lp) / len(lp) > L["shoulder"] - 0.10]
    if not loops:
        return []
    loop = max(loops, key=len)
    c = sum((v.co for v in loop), Vector()) / len(loop)
    # order the loop by angle round the neck, starting at the front
    ang = {v: atan2(v.co.y - c.y, v.co.x - c.x) for v in loop}
    faces = []
    prof = []
    for v in loop:
        a = ang[v]
        d = Vector((v.co.x - c.x, v.co.y - c.y, 0.0)).normalized()
        up = Vector((0, 0, 1))
        front = max(0.0, cos(a)) ** 3
        p0 = v.co.copy()
        if style == "stand":
            p1 = p0 + up * 0.030 - d * 0.007
            p2 = p1 + d * 0.0015 + up * 0.0015
            p3 = p2 + d * 0.0015 - up * 0.0015
        else:
            p1 = p0 + up * 0.016 - d * 0.003
            p2 = p1 + d * 0.008 + up * 0.002
            p3 = p2 + d * (0.027 + 0.008 * front) - up * (0.016 + 0.012 * front)
        th = 0.003
        q3 = p3 - d * th * 0.3 - up * th
        q2 = p2 - d * th
        q1 = p1 - d * th
        q0 = p0 - d * th + up * 0.002
        vs = [v]                               # the outer layer starts on the shell's own edge
        for p in (p1, p2, p3, q3, q2, q1, q0):
            nv = bm.verts.new(p)
            _copy_deform(nv, v, dl)
            vs.append(nv)
        prof.append((a, vs))
    n = len(prof)
    for i in range(n):
        a0, A = prof[i]
        a1, B = prof[(i + 1) % n]
        if abs(a0) < 0.20 and abs(a1) < 0.20:
            continue                           # the opening at the front
        if (a0 > 0) != (a1 > 0) and abs(a0) < 0.5:
            continue
        for k in range(len(A) - 1):
            try:
                faces.append(bm.faces.new((A[k], B[k], B[k + 1], A[k + 1])))
            except ValueError:
                pass
    # collar ends at the front opening: close the profile
    for i in range(n):
        a0, A = prof[i]
        a1, B = prof[(i + 1) % n]
        if (abs(a0) < 0.20) != (abs(a1) < 0.20) or ((a0 > 0) != (a1 > 0) and abs(a0) < 0.5):
            E = B if abs(a0) < 0.20 else A
            try:
                faces.append(bm.faces.new((E[0], E[1], E[6], E[7])))
                faces.append(bm.faces.new((E[1], E[2], E[5], E[6])))
                faces.append(bm.faces.new((E[2], E[3], E[4], E[5])))
            except ValueError:
                pass
    _drop_loose(bm)
    return faces


def _orient_out(bm, faces, centre_of):
    """Face normals away from the body axis (centre_of(p) gives the axis point for a face centre)."""
    for f in faces:
        if not f.is_valid:
            continue
        cc = f.calc_center_median()
        if f.normal.dot(cc - centre_of(cc)) < 0:
            f.normal_flip()


def _bands(bm, J, acc_i):
    """The department stripe (SuitAccent) as bisected bands on the coverall: chest round, upper sleeves, lower legs."""
    L = _levels(J)
    h = 0.018
    tf = lambda f: _classify(f.calc_center_median(), J) == "torso"        # noqa: E731
    fs = _faces(bm, lambda f: tf(f) and abs(f.calc_center_median().z - L["band"]) < 0.06)
    for dz in (-h, h):
        _cut(bm, fs, Vector((0, 0, L["band"] + dz)), Vector((0, 0, 1)), clear=False)
        fs = _faces(bm, lambda f: tf(f) and abs(f.calc_center_median().z - L["band"]) < 0.06)
    marked = [f for f in bm.faces if tf(f) and abs(f.calc_center_median().z - L["band"]) < h]
    for s in ("L", "R"):
        for part, seg, a_j, b_j, t0 in (("arm", 0, "upper_arm." + s, "forearm." + s, 0.40),
                                        ("leg", 1, "shin." + s, "foot." + s, 0.42)):
            a, b = J[a_j], J[b_j]
            ax = (b - a).normalized()
            m = a + (b - a) * t0

            def on(f, part=part, seg=seg, s=s):
                r = _classify(f.calc_center_median(), J, True)
                return r[0] == part and r[1] == seg and r[3] == s
            hh = h if part == "arm" else 0.022
            for dd in (-hh, hh):
                fs = _faces(bm, lambda f: on(f) and abs((f.calc_center_median() - m).dot(ax)) < 0.07)
                _cut(bm, fs, m + ax * dd, ax, clear=False)
            marked += [f for f in bm.faces if on(f) and abs((f.calc_center_median() - m).dot(ax)) < hh]
    for f in marked:
        f.material_index = acc_i
    vs = {v for f in marked for v in f.verts}
    for v in vs:
        v.co += v.normal * 0.0012
    return marked


def _zip(bm, J, zip_i):
    L = _levels(J)
    top = L["neck"] - 0.03
    bot = J["hips"].z - 0.07

    def front(f):
        c = f.calc_center_median()
        return c.x > J["hips"].x and f.normal.x > 0.25 and bot < c.z < top + 0.05 and abs(c.y) < 0.04
    for y in (-0.0065, 0.0065):
        _cut(bm, _faces(bm, front), Vector((0, y, 0)), Vector((0, 1, 0)), clear=False)
    _cut(bm, _faces(bm, front), Vector((0, 0, bot + 0.015)), Vector((0, 0, 1)), clear=False)
    zf = [f for f in bm.faces if front(f) and abs(f.calc_center_median().y) < 0.0065 and
          f.calc_center_median().z > bot + 0.015]
    for f in zf:
        f.material_index = zip_i
    for v in {v for f in zf for v in f.verts}:
        v.co += v.normal * 0.0015


def _pocket(bm, region, planes, depth=0.0035, flap=None):
    """A patch pocket: bisect the region by the 4 planes (co, no pairs: the inside is where no points AWAY), extrude
    the inside faces by depth along their mean normal.  flap: (co, no) of the flap line; the faces above it extrude
    again by 2 mm."""
    for co, no in planes + ([flap] if flap else []):
        _cut(bm, _faces(bm, region), co, no, clear=False)

    def inside(f):
        c = f.calc_center_median()
        return region(f) and all((c - co).dot(no) < 0 for co, no in planes)
    fs = [f for f in bm.faces if inside(f)]
    if not fs:
        return
    n = sum((f.normal for f in fs), Vector()).normalized()
    ret = bmesh.ops.extrude_face_region(bm, geom=fs)
    vs = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, verts=vs, vec=n * depth)
    if flap:
        co, no = flap
        top = [f for f in bm.faces if f.is_valid and all((f.calc_center_median() - co_).dot(no_) < 0.004
                                                          for co_, no_ in planes)
               and (f.calc_center_median() - co).dot(no) > 0 and f.normal.dot(n) > 0.7
               and (f.calc_center_median() - vs[0].co).length < 0.25]
        if top:
            ret2 = bmesh.ops.extrude_face_region(bm, geom=top)
            vs2 = [e for e in ret2["geom"] if isinstance(e, bmesh.types.BMVert)]
            bmesh.ops.translate(bm, verts=vs2, vec=n * 0.002 + Vector((0, 0, -0.004)))
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.is_valid and len(f.verts) < 3], context="FACES")


def _pockets(bm, J):
    L = _levels(J)
    z1 = L["band"] - 0.034
    z0 = z1 - 0.125
    for s, sg in (("L", 1.0), ("R", -1.0)):
        yi, yo = 0.050, 0.050 + 0.105

        def reg(f, sg=sg):
            c = f.calc_center_median()
            return (_classify(c, J) == "torso" and f.normal.x > 0.2 and c.x > J["hips"].x and
                    z0 - 0.03 < c.z < z1 + 0.03 and yi - 0.03 < sg * c.y < yo + 0.03)
        planes = [(Vector((0, 0, z0)), Vector((0, 0, -1))), (Vector((0, 0, z1)), Vector((0, 0, 1))),
                  (Vector((0, sg * yi, 0)), Vector((0, -sg, 0))), (Vector((0, sg * yo, 0)), Vector((0, sg, 0)))]
        _pocket(bm, reg, planes, depth=0.0025)
        # thigh cargo pocket, on the outer side of the thigh
        k = J["shin." + s]
        th = J["thigh." + s]
        zt1 = th.z - 0.16
        zt0 = zt1 - 0.17
        xc = (k.x + th.x) / 2 + 0.005

        def reg2(f, s=s, sg=sg):
            c = f.calc_center_median()
            r = _classify(c, J, True)
            return r[0] == "leg" and r[3] == s and r[1] == 0 and sg * f.normal.y > 0.45 and zt0 - 0.03 < c.z < zt1 + 0.03
        planes2 = [(Vector((0, 0, zt0)), Vector((0, 0, -1))), (Vector((0, 0, zt1)), Vector((0, 0, 1))),
                   (Vector((xc - 0.075, 0, 0)), Vector((-1, 0, 0))), (Vector((xc + 0.075, 0, 0)), Vector((1, 0, 0)))]
        _pocket(bm, reg2, planes2, depth=0.003)


def make_shell(base, J, name="Outfit_uniform"):
    src = body_copy(base, J)
    bm = _bm_of(src)
    groups = [g.name for g in src.vertex_groups]
    bpy.data.objects.remove(src)
    dl = bm.verts.layers.deform.active
    clean_cuts(bm, J)
    btree = _tree(base)
    shape_cloth(bm, J, btree)
    clean = bm.copy()                                   # the add-ons start from the plain shell
    _cuff_bands(bm, J)
    _pockets(bm, J)
    bm.normal_update()
    ob_tmp_mats = ["UniformBase", "SuitAccent", "Zip"]
    marked = _bands(bm, J, 1)
    _zip(bm, J, 2)
    loops = _boundary_loops(bm)
    rim = _rings_on_loops(bm, dl, loops, J)
    col = turn_down_collar(bm, dl, J)
    L = _levels(J)
    nc = Vector((J["neck"].x, 0, 0))
    _orient_out(bm, col, lambda p: Vector((nc.x, 0, p.z)))

    def axis_of(p):
        r = _classify(p, J, True)
        if r[0] == "leg":
            a, b = (J["thigh." + r[3]], J["shin." + r[3]]) if r[1] == 0 else (J["shin." + r[3]], J["foot." + r[3]])
        elif r[0] == "arm":
            a, b = (J["upper_arm." + r[3]], J["forearm." + r[3]]) if r[1] == 0 else (J["forearm." + r[3]], J["hand." + r[3]])
        else:
            return Vector((J["chest"].x, 0, p.z))
        t = max(0.0, min(1.0, _seg_t(p, a, b)[0]))
        return a + (b - a) * t
    _orient_out(bm, rim, axis_of)
    ob = _obj(name, bm, base, ob_tmp_mats)
    bm.free()
    uv = ob.data.uv_layers.active
    for d in uv.data:
        d.uv = (d.uv[0] * UV_REPEAT, d.uv[1] * UV_REPEAT)
    return ob, clean, groups


# ------------------------------------------------------------------------------------------------------------------
# add-ons
# ------------------------------------------------------------------------------------------------------------------
def _ring_on(tree, centre, z, n=40, out=0.004):
    pts = []
    for k in range(n):
        a = 2 * pi * k / n
        d = Vector((cos(a), sin(a), 0.0))
        o = Vector((centre.x, centre.y, z))
        hit = tree.ray_cast(o, d, 0.5)
        pts.append((hit[0] + d * out) if hit[0] is not None else (o + d * 0.18))
    return pts


def _box(bm, dl, grp, c, sx, sy, sz, rot_z=0.0, bevel=0.0):
    cs, sn = cos(rot_z), sin(rot_z)
    vs = []
    for dx in (-sx / 2, sx / 2):
        for dy in (-sy / 2, sy / 2):
            for dz in (-sz / 2, sz / 2):
                x, y = dx * cs - dy * sn, dx * sn + dy * cs
                v = bm.verts.new(c + Vector((x, y, dz)))
                if grp is not None:
                    v[dl][grp] = 1.0
                vs.append(v)
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    fs = [bm.faces.new([vs[i] for i in q]) for q in idx]
    if bevel > 0:
        es = list({e for f in fs for e in f.edges})
        bmesh.ops.bevel(bm, geom=es + vs, offset=bevel, segments=1, affect="EDGES", profile=0.5)
    return fs


def _new_obj(name, base, bm):
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = _obj(name, bm, base, ())
    bm.free()
    return ob


def make_toolbelt(shell_tree, base, J):
    gi = {g.name: g.index for g in base.vertex_groups}
    grp = gi.get("spine05", gi.get("pelvis.L", 0))
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    z = _levels(J)["waist"]
    centre = Vector((J["hips"].x, 0.0, z))
    lo = _ring_on(shell_tree, centre, z - 0.022)
    hi = _ring_on(shell_tree, centre, z + 0.022)
    n = len(lo)
    rings = [[bm.verts.new(p) for p in r] for r in (lo, hi)]
    inner = [[bm.verts.new(p - (p - Vector((centre.x, centre.y, p.z))).normalized() * 0.006) for p in r] for r in (lo, hi)]
    for r in rings + inner:
        for v in r:
            v[dl][grp] = 1.0
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i])))
        faces.append(bm.faces.new((rings[1][i], rings[1][j], inner[1][j], inner[1][i])))
        faces.append(bm.faces.new((inner[0][j], inner[0][i], rings[0][i], rings[0][j])))
    n_leather = len(faces)
    front = hi[0] * 0.5 + lo[0] * 0.5
    buckle = _box(bm, dl, grp, front + Vector((0.008, 0, 0)), 0.010, 0.056, 0.046, bevel=0.002)
    pouches = []
    for k, (w, h) in ((int(n * 0.17), (0.075, 0.095)), (int(n * 0.83), (0.075, 0.095)), (int(n * 0.30), (0.05, 0.13))):
        p = (hi[k] + lo[k]) * 0.5
        a = atan2(p.y - centre.y, p.x - centre.x)
        d = Vector((cos(a), sin(a), 0))
        pouches += _box(bm, dl, grp, p + d * 0.024 + Vector((0, 0, -0.035)), 0.040, w, h, rot_z=a, bevel=0.006)
    ob = _new_obj("Addon_toolbelt", base, bm)
    li, mi = _slot(ob, "Leather"), _slot(ob, "Metal")
    nb = len(buckle)
    for k, f in enumerate(ob.data.polygons):
        f.material_index = mi if n_leather <= k < n_leather + nb * 3 and k < n_leather + 40 else li
    return ob


_NGROUPS = [0]


def _decimate_bm(bm, target):
    """Collapse-decimate a bmesh in place to about `target` triangles (open edges protected)."""
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    if tris <= target:
        return bm
    me = bpy.data.meshes.new("npc_dec_tmp")
    bm.to_mesh(me)
    ob = bpy.data.objects.new("npc_dec_tmp", me)
    bpy.context.scene.collection.objects.link(ob)
    for k in range(_NGROUPS[0]):                       # the MakeHuman groups keep their indices
        ob.vertex_groups.new(name="g%d" % k)
    g = ob.vertex_groups.new(name="npc_keep")
    gk = g.index
    edge = set()
    for e in me.edges:
        pass
    bmb = bmesh.new()
    bmb.from_mesh(me)
    for v in bmb.verts:
        if any(e.is_boundary for e in v.link_edges):
            edge.add(v.index)
    bmb.free()
    g.add([i for i in range(len(me.vertices)) if i not in edge], 1.0, "REPLACE")
    if edge:
        g.add(list(edge), 0.0, "REPLACE")
    mod = ob.modifiers.new("Dec", "DECIMATE")
    mod.ratio = target / tris
    mod.vertex_group = "npc_keep"
    mod.vertex_group_factor = 10.0
    mod.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="Dec")
    bm.clear()
    bm.from_mesh(ob.data)
    dl = bm.verts.layers.deform.active
    if dl is not None:
        for v in bm.verts:
            if gk in v[dl]:
                del v[dl][gk]
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    return bm


def _region_copy(clean, faces_pred, cuts, off, smooth_it=8, solid=0.0, over=None, gap=0.008, target=None):
    """A copy of the plain shell: keep the faces faces_pred(f), cut by planes [(faces_pred2, co, no)], offset
    outwards by off (vertex normals), smoothed (the edges stay), optionally solidified."""
    bm = clean.copy()
    for f in bm.faces:
        f.material_index = 0
    kill = [f for f in bm.faces if not faces_pred(f)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    _drop_loose(bm)
    if target:
        _decimate_bm(bm, target)
    for pred, co, no in cuts:
        _cut(bm, _faces(bm, pred), co, no, clear=True)
    _drop_loose(bm)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * off
    boundary = {v for v in bm.verts if any(e.is_boundary for e in v.link_edges)}
    _smooth(bm, [v for v in bm.verts if v not in boundary], smooth_it)
    if over is not None:
        _push_out_n(bm, over, gap)
    _relax_loops(bm, 4)
    bm.normal_update()
    if solid > 0:
        bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=solid)
    return bm


def make_vest(clean, base, J, over):
    """An armoured vest: a torso band from under the arms to the belt (clean top and bottom edges), two shoulder
    straps over the shoulders, 1 cm thick."""
    L = _levels(J)
    top, bot = L["shoulder"] - 0.090, L["waist"] + 0.035
    tor = lambda f: _classify(f.calc_center_median(), J) == "torso"          # noqa: E731

    def keep(f):
        c = f.calc_center_median()
        return tor(f) and bot - 0.04 < c.z < top + 0.04
    cuts = [(lambda f: True, Vector((0, 0, bot)), Vector((0, 0, -1))),
            (lambda f: True, Vector((0, 0, top)), Vector((0, 0, 1)))]
    bm = _region_copy(clean, keep, cuts, 0.014, smooth_it=12, over=over, gap=0.012)
    dl = bm.verts.layers.deform.active
    # the straps: an arc over each shoulder, front top edge -> back top edge, 5 cm wide
    from mathutils.kdtree import KDTree
    kd = KDTree(len(clean.verts))
    clean.verts.ensure_lookup_table()
    for v in clean.verts:
        kd.insert(v.co, v.index)
    kd.balance()
    for sg in (1.0, -1.0):
        y = sg * 0.100
        cx = J["neck"].x - 0.01
        rows = []
        for k in range(15):
            ang = pi * k / 14
            d = Vector((cos(ang), 0.0, sin(ang)))
            o = Vector((cx, y, top)) + d * 0.45
            hit = over.ray_cast(o, -d, 0.6)
            if hit[0] is None:
                continue
            p = hit[0] + d * 0.016
            row = []
            for dy in (-0.025, 0.025):
                nv = bm.verts.new(p + Vector((0, dy, 0)))
                _, i, _ = kd.find(hit[0])
                _copy_deform(nv, clean.verts[i], dl, clean.verts.layers.deform.active)
                row.append(nv)
            rows.append(row)
        for i in range(len(rows) - 1):
            bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
    bm.normal_update()
    _orient_out(bm, bm.faces[:], lambda p: Vector((J["chest"].x, 0, min(p.z, top - 0.10))))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.010)
    ob = _new_obj("Addon_vest", base, bm)
    _slot(ob, "Armor")
    return ob


def make_apron(clean, base, J, over):
    """A bib apron: the bib on the shell front (clean edges), a skirt hanging from the waist to below the knee, a
    neck strap on each side and waist ties."""
    L = _levels(J)
    top, waist = L["band"] + 0.02, L["waist"] - 0.01
    half_bib = 0.105

    def keep(f):
        c = f.calc_center_median()
        return (_classify(c, J) == "torso" and f.normal.x > 0.15 and c.x > J["hips"].x and waist - 0.03 < c.z < top + 0.04
                and abs(c.y) < half_bib + 0.04)
    cuts = [(lambda f: True, Vector((0, 0, top)), Vector((0, 0, 1))),
            (lambda f: True, Vector((0, 0, waist)), Vector((0, 0, -1))),
            (lambda f: True, Vector((0, half_bib, 0)), Vector((0, 1, 0))),
            (lambda f: True, Vector((0, -half_bib, 0)), Vector((0, -1, 0)))]
    bm = _region_copy(clean, keep, cuts, 0.009, smooth_it=10, over=over, gap=0.007)
    dl = bm.verts.layers.deform.active
    gi = {g.name: g.index for g in base.vertex_groups}
    # the skirt: from the waist line, wider, straight down to 10 cm below the knee, clear of the thighs
    ctree = over
    zk = L["knee"] - 0.10
    half = abs(J["thigh.L"].y) + 0.075
    cols = 13
    rows = 9
    grid = []
    for i in range(rows + 1):
        z = waist - (waist - zk) * i / rows
        row = []
        for j in range(cols):
            y = -half + 2 * half * j / (cols - 1)
            o = Vector((J["hips"].x + 0.5, y, z if i == 0 else min(z, waist - 0.03)))
            hit = ctree.ray_cast(o, Vector((-1, 0, 0)), 1.0)
            x = hit[0].x + 0.012 if hit[0] is not None else J["hips"].x + 0.10
            row.append(x)
        grid.append(row)
    for i in range(1, rows + 1):                           # hang: never behind the row above (no tuck between legs)
        for j in range(cols):
            grid[i][j] = max(grid[i][j], grid[i - 1][j] - 0.004)
    xs_front = max(max(r) for r in grid[1:]) + 0.022
    vs = []
    for i in range(rows + 1):
        z = waist - (waist - zk) * i / rows
        u = i / rows
        row = []
        for j in range(cols):
            y = (-half + 2 * half * j / (cols - 1)) * (1.0 + 0.10 * u)
            w_ = min(1.0, i / 2.0)
            x = grid[i][j] * (1 - w_) + xs_front * w_ if i > 0 else grid[0][j]
            v = bm.verts.new(Vector((x + 0.004 * sin(3 * pi * j / (cols - 1)) * u, y, z)))
            side = "L" if y > 0 else "R"
            wl = min(1.0, abs(y) / half) * 0.45 * u
            for gname, w in (("spine05", 1.0 - wl), ("upperleg01." + side, wl)):
                if gname in gi:
                    v[dl][gi[gname]] = w
            row.append(v)
        vs.append(row)
    skirt = []
    for i in range(rows):
        for j in range(cols - 1):
            skirt.append(bm.faces.new((vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j])))
    # neck straps (from the bib's top corners up to the collar) and the waist ties round the back
    for sg in (1.0, -1.0):
        for k in range(1):
            y0 = sg * (half_bib - 0.012)
            p0 = Vector((0, y0, top))
            hit = ctree.ray_cast(p0 + Vector((0.5, 0, 0)), Vector((-1, 0, 0)), 1.0)
            if hit[0] is None:
                continue
            a = hit[0] + Vector((0.009, 0, 0))
            b = Vector((J["neck"].x + 0.02, sg * 0.058, L["neck"] - 0.005))
            w = Vector((0, 0.011, 0))
            q = [bm.verts.new(a - w), bm.verts.new(a + w), bm.verts.new(b + w * 0.8), bm.verts.new(b - w * 0.8)]
            for v in q:
                v[dl][gi.get("spine01", 0)] = 1.0
            bm.faces.new(q)
    ring = _ring_on(ctree, Vector((J["hips"].x, 0, waist)), waist - 0.010, n=36, out=0.010)
    ring2 = _ring_on(ctree, Vector((J["hips"].x, 0, waist)), waist + 0.010, n=36, out=0.010)
    r0 = [bm.verts.new(p) for p in ring]
    r1 = [bm.verts.new(p) for p in ring2]
    for v in r0 + r1:
        v[dl][gi.get("spine05", 0)] = 1.0
    for i in range(36):
        j = (i + 1) % 36
        bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    bm.normal_update()
    _orient_out(bm, bm.faces[:], lambda p: Vector((J["hips"].x - 0.05, 0, p.z)))
    # the back of the skirt: reversed twins 3 mm behind (the inside shows at the edges and when the legs move)
    twins = {}
    for f in skirt:
        nq = []
        for v in reversed(f.verts):
            if v not in twins:
                nv = bm.verts.new(v.co - Vector((0.003, 0, 0)))
                _copy_deform(nv, v, dl)
                twins[v] = nv
            nq.append(twins[v])
        bm.faces.new(nq)
    bm.normal_update()
    ob = _obj("Addon_apron", bm, base, ("Apron",))
    bm.free()
    return ob


def make_coat(clean, base, J, over, name, length, open_front, mats=("Coat", "SuitAccent", "Zip"), collar="turn"):
    """A coat over the coverall (lab coat, tunic, jacket): torso and sleeves offset from the shell, a skirt from the
    hips to `length` (m below the hips), open at the front below the waist if open_front.  The collar and the sleeve
    bands take slot 1 (SuitAccent)."""
    L = _levels(J)
    zc = J["hips"].z - 0.02

    def keep(f):
        return f.calc_center_median().z > zc - 0.03 or _classify(f.calc_center_median(), J) == "arm"
    cuts = [(lambda f: _classify(f.calc_center_median(), J) != "arm", Vector((0, 0, zc)), Vector((0, 0, -1)))]
    for s in ("L", "R"):
        a, b = J["forearm." + s], J["hand." + s]
        ax = (b - a).normalized()
        cuts.append((lambda f, a=a, b=b: _seg_t(f.calc_center_median(), a, b)[0] > 0.6, b - ax * 0.040, ax))
    bm = _region_copy(clean, keep, cuts, 0.012, smooth_it=14, over=over, gap=0.010, target=1250)
    dl = bm.verts.layers.deform.active
    gi = {g.name: g.index for g in base.vertex_groups}
    ctree = over
    for s in ("L", "R"):                          # a band near each sleeve end (slot 1: SuitAccent)
        _limb_band(bm, J, s, "arm", 1, 0.70, 0.016, 1, lift=0.0)
    # the skirt from the hip loop
    loops = [lp for lp in _boundary_loops(bm) if abs(sum(v.co.z for v in lp) / len(lp) - zc) < 0.03]
    faces_skirt = []
    if loops and length > 0.02:
        loop = max(loops, key=len)
        c = Vector((J["hips"].x, 0, zc))
        loop.sort(key=lambda v: atan2(v.co.y, v.co.x - c.x))
        K = max(2, int(length / 0.07))
        rows = [loop]
        prev_r = [Vector((v.co.x - c.x, v.co.y, 0)).length for v in loop]
        for k in range(1, K + 1):
            z = zc - length * k / K
            row = []
            rs = []
            for i, v in enumerate(loop):
                a = atan2(v.co.y, v.co.x - c.x)
                d = Vector((cos(a), sin(a), 0))
                hit = ctree.ray_cast(Vector((c.x, 0, z)), d, 0.5)
                need = (hit[0] - Vector((c.x, 0, z))).length + 0.030 if hit[0] is not None else 0.0
                rs.append(max(prev_r[i] + 0.004, need))
            n = len(rs)
            for _ in range(3):
                rs = [0.25 * rs[i - 1] + 0.5 * rs[i] + 0.25 * rs[(i + 1) % n] for i in range(n)]
            for i, v in enumerate(loop):
                a = atan2(v.co.y, v.co.x - c.x)
                nv = bm.verts.new(Vector((c.x + cos(a) * rs[i], sin(a) * rs[i], z)))
                u = k / K
                side = "L" if sin(a) > 0 else "R"
                wl = 0.40 * u * min(1.0, abs(sin(a)) * 1.6)
                if "spine05" in gi:
                    nv[dl][gi["spine05"]] = 1.0 - wl
                if "upperleg01." + side in gi:
                    nv[dl][gi["upperleg01." + side]] = wl
                row.append(nv)
            prev_r = rs
            rows.append(row)
        n = len(loop)
        for k in range(K):
            for i in range(n):
                j = (i + 1) % n
                a0 = atan2(loop[i].co.y, loop[i].co.x - c.x)
                a1 = atan2(loop[j].co.y, loop[j].co.x - c.x)
                if open_front and (abs(a0) < 0.07 or abs(a1) < 0.07 or (a0 > 0) != (a1 > 0) and abs(a0) < 1.0):
                    continue
                if (a0 > 0) != (a1 > 0) and abs(a0) > 2.5:       # the back seam wraps round +-pi: keep
                    pass
                try:
                    faces_skirt.append(bm.faces.new((rows[k][i], rows[k][j], rows[k + 1][j], rows[k + 1][i])))
                except ValueError:
                    pass
    bm.normal_update()
    _orient_out(bm, bm.faces[:], lambda p: _coat_axis(p, J))
    if faces_skirt:
        # the inside of the skirt (seen through the front opening and from below): reversed twins 3 mm in
        c = Vector((J["hips"].x, 0, zc))
        twins = {}
        for f in faces_skirt:
            nq = []
            for v in reversed(f.verts):
                if v not in twins:
                    nv = bm.verts.new(v.co - Vector((v.co.x - c.x, v.co.y, 0)).normalized() * 0.003)
                    _copy_deform(nv, v, dl)
                    twins[v] = nv
                nq.append(twins[v])
            try:
                bm.faces.new(nq)
            except ValueError:
                pass
    bm.normal_update()
    # the front closure: a 1.6 cm placket line from the collar to the hem (slot 2)
    Lz = _levels(J)

    def fr(f):
        c_ = f.calc_center_median()
        return c_.x > J["hips"].x and f.normal.x > 0.3 and abs(c_.y) < 0.04 and c_.z > zc - length - 0.01
    col = turn_down_collar(bm, dl, J, collar)
    _orient_out(bm, col, lambda p: Vector((J["neck"].x, 0, p.z)))
    for f in col:
        if f.is_valid:
            f.material_index = 1
    ob = _obj(name, bm, base, mats)
    bm.free()
    return ob


def _coat_axis(p, J):
    r = _classify(p, J, True)
    if r[0] == "arm":
        a, b = (J["upper_arm." + r[3]], J["forearm." + r[3]]) if r[1] == 0 else (J["forearm." + r[3]], J["hand." + r[3]])
        t = max(0.0, min(1.0, _seg_t(p, a, b)[0]))
        return a + (b - a) * t
    return Vector((J["hips"].x, 0, p.z))


def make_rank(over, base, J, bars, tops=()):
    """Shoulder boards (UniformBase: the uniform's own colour) with `bars` gold bars (Rank) at the outer end."""
    L = _levels(J)
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    gi = {g.name: g.index for g in base.vertex_groups}
    tree = over
    n_board = 0
    board_faces = []
    for s, sg in (("L", 1.0), ("R", -1.0)):
        ua = J["upper_arm." + s]
        y0, y1 = 0.075, abs(ua.y) + 0.010
        xs = J["neck"].x - 0.004
        rows = []
        for i in range(7):
            y = sg * (y0 + (y1 - y0) * i / 6)
            row = []
            for dx in (-0.026, 0.026):
                o = Vector((xs + dx, y, L["shoulder"] + 0.30))
                hit = tree.ray_cast(o, Vector((0, 0, -1)), 0.6)
                p = hit[0] + Vector((0, 0, 0.001)) if hit[0] is not None else Vector((xs + dx, y, L["shoulder"] + 0.06))
                hz = p.z + 0.015
                for tt in tops:                         # the board top clears any coat or jacket on the shoulder
                    h2 = tt.ray_cast(o, Vector((0, 0, -1)), 0.6)
                    if h2[0] is not None:
                        hz = max(hz, h2[0].z + 0.004)
                row.append((p, hz))
            rows.append(row)
        grp = gi.get("clavicle." + s, gi.get("shoulder01." + s, 0))
        top, bot = [], []
        for row in rows:
            # a padded board: its top clears a jacket or coat on the shoulder (1.6 cm)
            t_ = [bm.verts.new(Vector((p.x, p.y, hz))) for p, hz in row]
            b_ = [bm.verts.new(p) for p, hz in row]
            for v in t_ + b_:
                v[dl][grp] = 1.0
            top.append(t_)
            bot.append(b_)
        for i in range(len(rows) - 1):
            board_faces.append(bm.faces.new((top[i][0], top[i][1], top[i + 1][1], top[i + 1][0])))
            board_faces.append(bm.faces.new((bot[i][1], bot[i][0], bot[i + 1][0], bot[i + 1][1])))
            board_faces.append(bm.faces.new((top[i][0], top[i + 1][0], bot[i + 1][0], bot[i][0])))
            board_faces.append(bm.faces.new((top[i][1], bot[i][1], bot[i + 1][1], top[i + 1][1])))
        board_faces.append(bm.faces.new((top[0][0], bot[0][0], bot[0][1], top[0][1])))
        board_faces.append(bm.faces.new((top[-1][1], bot[-1][1], bot[-1][0], top[-1][0])))
        n_board = len(board_faces)
        for k in range(bars):
            i = 5 - k
            p = Vector(((rows[i][0][0].x + rows[i][1][0].x) / 2, (rows[i][0][0].y + rows[i][1][0].y) / 2,
                        (rows[i][0][1] + rows[i][1][1]) / 2 + 0.0025))
            _box(bm, dl, grp, p, 0.046, 0.007, 0.003)
    ob = _new_obj("Addon_rank%d" % bars, base, bm)
    bi, ri = _slot(ob, "UniformBase"), _slot(ob, "Rank")
    nb = len(board_faces)
    for k, f in enumerate(ob.data.polygons):
        f.material_index = bi if k < nb else ri
    return ob


def make_uniform(base, J):
    _NGROUPS[0] = len(base.vertex_groups)
    shell, clean, _ = make_shell(base, J)
    st = _tree(shell)
    addons = {
        "toolbelt": make_toolbelt(st, base, J),
        "apron": make_apron(clean, base, J, st),
        "vest": make_vest(clean, base, J, st),
        "labcoat": make_coat(clean, base, J, st, "Addon_labcoat", length=0.44, open_front=True),
        "tunic": make_coat(clean, base, J, st, "Addon_tunic", length=0.20, open_front=False),
        "jacket": make_coat(clean, base, J, st, "Addon_jacket", length=0.09, open_front=False,
                            mats=("UniformBase", "SuitAccent", "Zip"), collar="stand"),
    }
    tops = [_tree(addons[c]) for c in ("labcoat", "tunic", "jacket")]
    for k in (1, 2, 3):
        addons["rank%d" % k] = make_rank(st, base, J, k, tops)
    clean.free()
    return shell, addons
