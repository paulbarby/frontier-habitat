"""
Frontier Habitat 5.0 - ART-NPC: the contract uniform for the MPFB people (V5 section 1), one cut for every department.

make_uniform(base, J) builds, from the posed MPFB body (our axes, MakeHuman vertex groups still on it):
  * Outfit shell "uniform": a coverall offset from the body (arms to the wrist, legs to the boot top), smoothed so
    the body detail becomes cloth, soft folds at the elbows, knees and waist, a stand collar, rolled hems at the cuffs
    and ankles, a front zip, the department stripe (SuitAccent) round the chest and round both upper sleeves;
  * add-ons (separate small meshes, shown per role): toolbelt (belt, buckle, two pouches), apron (food), vest
    (security), rank (shoulder boards, command).
Every vertex keeps MakeHuman vertex groups (copied from the body vertex it came from, or a named MakeHuman bone), so
people_mpfb.move_weights maps them to our skeleton like any garment.  Material slots are named placeholders:
UniformBase, SuitAccent, Zip, Leather, Metal, Apron, Armor, Rank (people_mpfb gives them their textures).
"""
import bpy
import bmesh
from math import sin, cos, pi, radians, atan2
from mathutils import Vector
from mathutils.bvhtree import BVHTree

OFF = dict(torso=0.024, arm=0.016, leg=0.020)
UV_REPEAT = 6.0

# department looks: base colour (UniformBase tint), add-ons
DEPARTMENTS = {
    "uniform_engineering": dict(base=(0.33, 0.37, 0.42), addons=["toolbelt"], who=["technician", "operator"],
                                look="coverall, amber stripe on chest and sleeves, tool belt, work boots"),
    "uniform_science": dict(base=(0.86, 0.88, 0.90), addons=[], who=["scientist"],
                            look="light coverall, blue stripe on chest and sleeves"),
    "uniform_food": dict(base=(0.55, 0.62, 0.52), addons=["apron"], who=["grower", "kitchen", "venue staff"],
                         look="sage coverall, green stripe, white apron"),
    "uniform_medical": dict(base=(0.92, 0.93, 0.94), addons=[], who=["medic"],
                            look="white coverall (scrubs), red stripe"),
    "uniform_security": dict(base=(0.10, 0.10, 0.12), addons=["vest", "toolbelt"], who=["security officer"],
                             look="black coverall, armoured vest, red stripe, belt"),
    "uniform_command": dict(base=(0.09, 0.13, 0.26), addons=["rank"], who=["commander", "captains"],
                            look="navy coverall, shoulder boards with rank"),
}


def _slot(ob, name):
    for i, m in enumerate(ob.data.materials):
        if m.name.split(".")[0] == name:
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
    """'arm' / 'leg' / 'torso' region of a body point; full: (region, segment 0 upper / 1 lower, t along it)."""
    best = ("torso", 9.0, 0.0, 0)
    for s in ("L", "R"):
        for part, seg, a, b in (("arm", 0, J["upper_arm." + s], J["forearm." + s]),
                                ("arm", 1, J["forearm." + s], J["hand." + s]),
                                ("leg", 0, J["thigh." + s], J["shin." + s]), ("leg", 1, J["shin." + s], J["foot." + s])):
            t, d = _seg_t(p, a, b)
            if 0.0 <= t <= 1.05 and d < 0.11 and d < best[1]:
                best = (part, d, t, seg)
    return (best[0], best[3], best[2]) if full else best[0]


def make_shell(base, J, name="Outfit_uniform"):
    bm = bmesh.new()
    bm.from_mesh(base.data)
    bm.transform(base.matrix_world)
    dl = bm.verts.layers.deform.active
    uvl = bm.loops.layers.uv.active
    gi = {g.name: g.index for g in base.vertex_groups}
    body = gi.get("body")
    collar_z = J["upper_arm.L"].z + 0.055
    neck_c = Vector((J["neck"].x + 0.008, 0.0, 0.0))
    neck_r = 0.066
    shoulder_z = J["upper_arm.L"].z
    hem_z = J["foot.L"].z + 0.075
    kill = set()
    for v in bm.verts:
        p = v.co
        if body is not None and v[dl].get(body, 0.0) < 0.5:
            kill.add(v)
            continue
        dn = ((p.x - neck_c.x) ** 2 + p.y ** 2) ** 0.5
        if p.z > J["neck"].z - 0.01 or (p.z > shoulder_z - 0.03 and dn < neck_r) or p.z < hem_z:
            kill.add(v)
            continue
        for s in ("L", "R"):                                  # hands: beyond 1.5 cm before the wrist joint
            t, d = _seg_t(p, J["forearm." + s], J["hand." + s])
            if t > 1.0 - 0.015 / max(1e-3, (J["hand." + s] - J["forearm." + s]).length) and d < 0.13:
                kill.add(v)
    bmesh.ops.delete(bm, geom=list(kill), context="VERTS")
    # keep the biggest connected piece (drop loose islands: nipples, navel helpers)
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
    bm.normal_update()
    # offset along the normals, by region; folds near elbows / knees; tighter at the belt line
    belt_z = J["hips"].z + 0.07
    for v in bm.verts:
        p = v.co.copy()
        reg, seg, tt = _classify(p, J, True)
        off = OFF[reg]
        if reg == "leg":
            off += 0.012 * (tt if seg == 1 else 0.0) + (0.006 if seg == 1 else 0.004)     # straight trouser legs
        elif reg == "arm":
            off += 0.006 * (tt if seg == 1 else 0.0)                                       # sleeves wider at the cuff
        for s in ("L", "R"):
            for jn in ("forearm." + s, "shin." + s):
                dj = (p - J[jn]).length
                if dj < 0.075:
                    off += 0.0045 * sin(pi * dj / 0.025) ** 2 * (1.0 - dj / 0.075)
        if reg == "torso" and abs(p.z - belt_z) < 0.05:
            off *= 0.65 + 0.35 * abs(p.z - belt_z) / 0.05
        v.co = p + v.normal * off
    boundary = [v for v in bm.verts if any(e.is_boundary for e in v.link_edges)]
    interior = [v for v in bm.verts if v not in set(boundary)]
    for _ in range(12):                                       # cloth, not muscles
        bmesh.ops.smooth_vert(bm, verts=interior, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    torso = [v for v in interior if _classify(v.co, J) == "torso"]
    for _ in range(20):                                       # the torso smoother still (no body detail through it)
        bmesh.ops.smooth_vert(bm, verts=torso, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # never closer than 8 mm to the body (smoothing shrinks)
    bmb = bmesh.new()
    bmb.from_mesh(base.data)
    bmb.transform(base.matrix_world)
    btree = BVHTree.FromBMesh(bmb)
    bmb.free()
    for v in bm.verts:
        hit = btree.find_nearest(v.co, 0.05)
        if hit[0] is not None and (v.co - hit[0]).dot(hit[1]) < 0.008:
            v.co = hit[0] + hit[1] * 0.008
    bm.normal_update()
    # collar and hems: a rolled edge on every opening (the collar also stands up 3 cm)
    loops = _boundary_loops(bm)
    for loop in loops:
        zc = sum(v.co.z for v in loop) / len(loop)
        if zc > shoulder_z - 0.06:                            # the collar: onto the neck cylinder (it slopes)
            for v in loop:
                d = Vector((v.co.x - neck_c.x, v.co.y, 0.0))
                if d.length > 1e-6:
                    d = d.normalized() * neck_r
                    v.co.x, v.co.y = neck_c.x + d.x, d.y
        elif zc < 0.5:                                        # trouser hems: one height
            for v in loop:
                v.co.z = hem_z + 0.004
        else:                                                 # cuffs: onto the plane across the forearm
            c = sum((v.co for v in loop), Vector()) / len(loop)
            s_ = "L" if c.y > 0 else "R"
            ax = (J["hand." + s_] - J["forearm." + s_]).normalized()
            plane = J["hand." + s_] - ax * 0.015
            for v in loop:
                v.co -= ax * (v.co - plane).dot(ax)
    for _ in range(2):                                        # even out each open edge along itself
        for loop in loops:
            n_ = len(loop)
            pts = [v.co.copy() for v in loop]
            for i, v in enumerate(loop):
                v.co = pts[i] * 0.5 + (pts[i - 1] + pts[(i + 1) % n_]) * 0.25
    bm.normal_update()
    new_faces = []
    for loop in loops:
        zc = sum(v.co.z for v in loop) / len(loop)
        is_collar = zc > shoulder_z - 0.06
        centre = sum((v.co for v in loop), Vector()) / len(loop)
        ring_out, ring_in = [], []
        for v in loop:
            radial = v.co - centre
            radial.z = 0.0 if is_collar else radial.z
            radial = radial.normalized() if radial.length > 1e-6 else Vector((1, 0, 0))
            if is_collar:
                a = bm.verts.new(v.co + Vector((0, 0, 0.020)) + radial * 0.002)
                b = bm.verts.new(v.co + Vector((0, 0, 0.020)) - radial * 0.005)
                c = bm.verts.new(v.co - radial * 0.006)
            else:
                along = (v.co - centre)
                a = bm.verts.new(v.co + v.normal * 0.003)
                b = bm.verts.new(v.co - v.normal * 0.004)
                c = bm.verts.new(v.co - v.normal * 0.008 + (Vector((0, 0, 0.012)) if zc < 0.5 else Vector()))
            for nv in (a, b, c):
                for k_, w_ in v[dl].items():
                    nv[dl][k_] = w_
            ring_out.append((v, a, b, c))
        n = len(ring_out)
        for i in range(n):
            v0, a0, b0, c0 = ring_out[i]
            v1, a1, b1, c1 = ring_out[(i + 1) % n]
            for q in ((v0, v1, a1, a0), (a0, a1, b1, b0), (b0, b1, c1, c0)):
                try:
                    new_faces.append(bm.faces.new(q))
                except ValueError:
                    pass
    bm.normal_update()
    # outward normals for the new rim faces
    bmesh.ops.recalc_face_normals(bm, faces=new_faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for g in base.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    # UVs: the body UVs, repeated for the canvas; new rim faces: a strip
    uv = me.uv_layers.active
    if uv is not None:
        for d in uv.data:
            d.uv = (d.uv[0] * UV_REPEAT, d.uv[1] * UV_REPEAT)
    # materials by region: base, stripe (chest band all round + upper sleeve bands), zip
    base_i = _slot(ob, "UniformBase")
    for f in me.polygons:
        f.material_index = base_i
        f.use_smooth = True
    add_trims(ob, base, J, collar_z)
    return ob


def _copy_weights_from(dst, src):
    """Every vertex of dst takes the vertex groups of the nearest vertex of src (same group names)."""
    from mathutils.kdtree import KDTree
    kd = KDTree(len(src.data.vertices))
    for v in src.data.vertices:
        kd.insert(src.matrix_world @ v.co, v.index)
    kd.balance()
    names = {g.index: g.name for g in src.vertex_groups}
    for g in src.vertex_groups:
        if g.name not in dst.vertex_groups:
            dst.vertex_groups.new(name=g.name)
    for v in dst.data.vertices:
        _, i, _ = kd.find(dst.matrix_world @ v.co)
        for g in src.data.vertices[i].groups:
            dst.vertex_groups[names[g.group]].add([v.index], g.weight, "REPLACE")


def _band(bm, *rings):
    """Quads between consecutive rings (closed round)."""
    vr = [[bm.verts.new(p) for p in r] for r in rings]
    n = len(vr[0])
    for a, b in zip(vr, vr[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))


def _ring_around(tree, centre, axis, n=36, out=0.009, reach=0.4):
    """Points on the shell round an axis through centre (rays outwards, perpendicular to the axis)."""
    axis = axis.normalized()
    u = axis.orthogonal().normalized()
    w = axis.cross(u).normalized()
    pts = []
    for k in range(n):
        a = 2 * pi * k / n
        d = u * cos(a) + w * sin(a)
        hit = tree.ray_cast(centre, d, reach)
        pts.append(hit[0] + hit[1] * out if hit[0] is not None else None)
    good = [i for i, p_ in enumerate(pts) if p_ is not None]
    if not good:
        return [centre + (u * cos(2 * pi * k / n) + w * sin(2 * pi * k / n)) * 0.1 for k in range(n)]
    for i, p_ in enumerate(pts):                              # a miss takes the nearest hit (armpits)
        if p_ is None:
            j = min(good, key=lambda g: min(abs(g - i), n - abs(g - i)))
            pts[i] = pts[j]
    return pts


def add_trims(shell, base, J, collar_z):
    """The department stripe (a band round the chest and one round each upper sleeve, 3.5 cm) and the front zip:
    clean separate geometry laid 3 mm over the shell, joined into it."""
    bm_s = bmesh.new()
    bm_s.from_mesh(shell.data)
    tree = BVHTree.FromBMesh(bm_s)
    bm_s.free()
    bm = bmesh.new()
    chest_z = J["upper_arm.L"].z - 0.125
    c = Vector((J["chest"].x, 0.0, chest_z))
    _band(bm, *[_ring_around(tree, c + Vector((0, 0, dz)), Vector((0, 0, 1)))
                for dz in (-0.0175, -0.00875, 0.0, 0.00875, 0.0175)])
    n_stripe = len(bm.faces)
    for s_ in ("L", "R"):
        a, b = J["upper_arm." + s_], J["forearm." + s_]
        ax = (b - a).normalized()
        m = a + (b - a) * 0.36
        _band(bm, *[_ring_around(tree, m + ax * dd, ax, n=24, reach=0.15) for dd in (-0.0175, 0.0, 0.0175)])
    n_stripe = len(bm.faces)
    # zip: a 1.2 cm strip down the front midline, collar to crotch
    zs = [collar_z - 0.005 - k * 0.02 for k in range(int((collar_z - (J["hips"].z - 0.06)) / 0.02))]
    left, right = [], []
    for z in zs:
        for dy, lst in ((0.006, left), (-0.006, right)):
            o = Vector((J["hips"].x + 0.4, dy, z))
            hit = tree.ray_cast(o, Vector((-1, 0, 0)), 0.6)
            lst.append(bm.verts.new(hit[0] + hit[1] * 0.0035 if hit[0] is not None else o))
    for i in range(len(zs) - 1):
        bm.faces.new((left[i], left[i + 1], right[i + 1], right[i]))
    me = bpy.data.meshes.new("trims")
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    tr = bpy.data.objects.new("trims", me)
    bpy.context.scene.collection.objects.link(tr)
    for f in me.polygons:
        f.use_smooth = True
    # outward normals (the rings are built facing either way)
    bm = bmesh.new()
    bm.from_mesh(me)
    for f in bm.faces:
        hit = tree.find_nearest(f.calc_center_median())
        if hit[0] is not None and f.normal.dot(hit[1]) < 0:
            f.normal_flip()
    bm.to_mesh(me)
    bm.free()
    uv = me.uv_layers.new(name=shell.data.uv_layers.active.name if shell.data.uv_layers.active else "UVMap")
    for d in uv.data:
        d.uv = (0.5, 0.5)
    _copy_weights_from(tr, shell)
    si, zi = _slot(tr, "SuitAccent"), _slot(tr, "Zip")
    for k, f in enumerate(me.polygons):
        f.material_index = si if k < n_stripe else zi
    bpy.ops.object.select_all(action="DESELECT")
    tr.select_set(True)
    shell.select_set(True)
    bpy.context.view_layer.objects.active = shell
    bpy.ops.object.join()


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


# ------------------------------------------------------------------------------------------------------------------
# add-ons
# ------------------------------------------------------------------------------------------------------------------
def _ring_on(shell, centre, z, n=40, out=0.004):
    """Points round the shell at height z (rays from the body axis outwards)."""
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    pts = []
    for k in range(n):
        a = 2 * pi * k / n
        d = Vector((cos(a), sin(a), 0.0))
        o = Vector((centre.x, centre.y, z))
        hit = tree.ray_cast(o, d, 0.5)
        pts.append((hit[0] + d * out) if hit[0] is not None else (o + d * 0.18))
    return pts


def _box(bm, dl, grp, c, sx, sy, sz, rot_z=0.0):
    cs, sn = cos(rot_z), sin(rot_z)
    vs = []
    for dx in (-sx / 2, sx / 2):
        for dy in (-sy / 2, sy / 2):
            for dz in (-sz / 2, sz / 2):
                x, y = dx * cs - dy * sn, dx * sn + dy * cs
                v = bm.verts.new(c + Vector((x, y, dz)))
                v[dl][grp] = 1.0
                vs.append(v)
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return [bm.faces.new([vs[i] for i in q]) for q in idx]


def _new_obj(name, base, bm):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for g in base.vertex_groups:
        ob.vertex_groups.new(name=g.name)
    me.uv_layers.new(name="UVMap")
    return ob


def make_toolbelt(shell, base, J):
    gi = {g.name: g.index for g in base.vertex_groups}
    grp = gi.get("spine05", gi.get("pelvis.L", 0))
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    z = J["hips"].z + 0.07
    centre = Vector((J["hips"].x, 0.0, z))
    lo = _ring_on(shell, centre, z - 0.022)
    hi = _ring_on(shell, centre, z + 0.022)
    n = len(lo)
    outer_lo = [bm.verts.new(p) for p in lo]
    outer_hi = [bm.verts.new(p) for p in hi]
    inner_lo = [bm.verts.new(p - (p - Vector((centre.x, centre.y, p.z))).normalized() * 0.006) for p in lo]
    inner_hi = [bm.verts.new(p - (p - Vector((centre.x, centre.y, p.z))).normalized() * 0.006) for p in hi]
    for v in outer_lo + outer_hi + inner_lo + inner_hi:
        v[dl][grp] = 1.0
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((outer_lo[i], outer_lo[j], outer_hi[j], outer_hi[i])))
        faces.append(bm.faces.new((outer_hi[i], outer_hi[j], inner_hi[j], inner_hi[i])))
        faces.append(bm.faces.new((inner_lo[j], inner_lo[i], outer_lo[i], outer_lo[j])))
    leather = faces[:]
    front = hi[0] * 0.5 + lo[0] * 0.5
    buckle = _box(bm, dl, grp, front + Vector((0.008, 0, 0)), 0.012, 0.060, 0.050)
    pouches = []
    for k in (int(n * 0.18), int(n * 0.82)):
        p = (hi[k] + lo[k]) * 0.5
        a = atan2(p.y - centre.y, p.x - centre.x)
        d = Vector((cos(a), sin(a), 0))
        pouches += _box(bm, dl, grp, p + d * 0.026 + Vector((0, 0, -0.03)), 0.045, 0.085, 0.100, rot_z=a)
    ob = _new_obj("Addon_toolbelt", base, bm)
    li, mi = _slot(ob, "Leather"), _slot(ob, "Metal")
    nb = len(buckle)
    for k, f in enumerate(ob.data.polygons):
        f.material_index = mi if len(leather) <= k < len(leather) + nb else li
    return ob


def _grid_obj(name, base, shell, rows, mat, thick=0.004):
    """rows: list of point lists (equal length) on the shell: a quad grid, solidified, weights from the shell."""
    bm = bmesh.new()
    vs = [[bm.verts.new(p) for p in r] for r in rows]
    for i in range(len(vs) - 1):
        for j in range(len(vs[i]) - 1):
            bm.faces.new((vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j]))
    bm.normal_update()
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=-thick)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.uv_layers.new(name="UVMap")
    for f in me.polygons:
        f.use_smooth = True
    _copy_weights_from(ob, shell)
    _slot(ob, mat)
    return ob


def _shell_tree(shell):
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    t = BVHTree.FromBMesh(bm)
    bm.free()
    return t


def make_apron(shell, base, J):
    """A bib apron: a front panel from the upper chest to the knee, ray-cast onto the shell front."""
    tree = _shell_tree(shell)
    top, bottom = J["upper_arm.L"].z - 0.07, J["shin.L"].z + 0.06
    half = abs(J["thigh.L"].y) + 0.09
    rows = []
    waist = J["hips"].z + 0.02
    front = None
    for i in range(9):
        z = top + (bottom - top) * i / 8
        w = half * (0.62 if z > J["hips"].z + 0.10 else 1.0)          # a narrower bib above the waist
        row = []
        for j in range(9):
            y = -w + 2 * w * j / 8
            if z >= waist or front is None:
                o = Vector((J["hips"].x + 0.5, y, max(z, waist)))
                hit = tree.ray_cast(o, Vector((-1, 0, 0)), 1.0)
                p_ = hit[0] + hit[1] * 0.008 if hit[0] is not None else Vector((J["hips"].x + 0.12, y, z))
                row.append(Vector((p_.x, p_.y, z)))
            else:                                                     # below the waist it hangs flat
                row.append(Vector((front + 0.012 * (waist - z) / max(1e-3, waist - bottom), y, z)))
        if z >= waist:
            front = max(p_.x for p_ in row)
        rows.append(row)
    return _grid_obj("Addon_apron", base, shell, rows, "Apron")


def make_vest(shell, base, J):
    """An armoured vest: a closed band round the torso from the waist to the upper chest."""
    tree = _shell_tree(shell)
    top, bottom = J["upper_arm.L"].z - 0.06, J["hips"].z + 0.05
    rows = []
    for i in range(6):
        z = top + (bottom - top) * i / 5
        c = Vector((J["chest"].x, 0.0, z))
        ring = _ring_around(tree, c, Vector((0, 0, 1)), n=32, out=0.012, reach=0.25)
        rows.append(ring + [ring[0]])
    return _grid_obj("Addon_vest", base, shell, rows, "Armor", thick=0.008)


RANK_TREE = []


def make_rank(base, J):
    gi = {g.name: g.index for g in base.vertex_groups}
    bm = bmesh.new()
    dl = bm.verts.layers.deform.verify()
    for s, mh in (("L", "clavicle.L"), ("R", "clavicle.R")):
        p = J["upper_arm." + s]
        o = Vector((p.x - 0.005, p.y * 0.72, p.z + 0.30))
        hit = RANK_TREE[0].ray_cast(o, Vector((0, 0, -1)), 0.5) if RANK_TREE else (None,)
        c = (hit[0] + Vector((0, 0, 0.007))) if hit[0] is not None else Vector((p.x - 0.005, p.y * 0.72, p.z + 0.06))
        _box(bm, dl, gi.get(mh, 0), c, 0.055, 0.10, 0.010)
    ob = _new_obj("Addon_rank", base, bm)
    _slot(ob, "Rank")
    return ob


def make_uniform(base, J):
    shell = make_shell(base, J)
    chest_top = J["upper_arm.L"].z - 0.05
    knee_z = J["shin.L"].z
    waist_z = J["hips"].z + 0.03
    hip_w = abs(J["thigh.L"].y) + 0.12
    addons = {
        "toolbelt": make_toolbelt(shell, base, J),
        "apron": make_apron(shell, base, J),
        "vest": make_vest(shell, base, J),
        "rank": (RANK_TREE.clear(), RANK_TREE.append(_shell_tree(shell)), make_rank(base, J))[2],
    }
    return shell, addons
