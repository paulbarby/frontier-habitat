"""Frontier Habitat 5.0 round 2 (coordinator 2026-10-02): the inner ceiling of every room.

In the follow view the roofs stay on (Paul), so the roof's underside fills half of every over-the-shoulder frame.  It
was the back of the outer shell: one bare grey surface (and the shell's outside paint bands).  This module adds, under
the roof, an object RoofCeil (RENDER's group_of puts it in the Roof group: hidden in the cutaway, drawn with the roof):

  liner       a panelled skin 5 cm under the roof (polar grid, two-tone panels), following any roof shape (dome, flat,
              gable, vault) by ray casts against the built Roof part; no liner under glass or lit roof faces
  ribs        radial ribs on every other panel line; four of them carry light strips; a ring rib
  cove        a light strip round the liner edge
  crown       a ring light under the crown
  sensors     smoke sensors and vents
  role piece  by room role (interior_roles.ROLE_OF): crane rail and hoist (industry, logistics), grow lights (farm),
              hanging signs, pendants and a mirror ball (bar), pot rack (kitchen), equipment rail (science), surgical
              lights (medical), ducts (life), copper pipes (distillery), banners (retail), a planet mobile
              (academy), camera domes (security), cage lamps (jail), cove and pendants (housing, comfort)

Rules (see docs/requests/ART-HAB-to-RENDER.md 2026-10-02):
  - every hanging face is at MIN_Z (2.45 m) or higher: RENDER's camera ceiling grid reads the lowest Roof face above
    1.6 m, and the follow eye is 1.8 m with a 0.5 m knee; the liner itself lies GAP (5 cm) under the roof wherever the
    roof is at LINER_MIN (2.20 m) or higher, so the grid moves by 5 cm (low decks of 2.32 m get a flush liner);
  - materials keep the Roof group at 6 surfaces or fewer (Mats picks from what the roof already uses);
  - signs are ORIGINAL parody text (V5_DESIGN 15.3).
"""
import random
from math import sin, cos, radians, hypot, pi, sqrt

from mathutils import Vector
from mathutils.bvhtree import BVHTree

import build_assets as BA
import rooms_kit as K
from rooms_kit import T, RZ, P
import interior_props as PR

MIN_Z = 2.45            # the lowest HANGING face (m, absolute)
LINER_MIN = 2.20        # the lowest liner (flush, GAP under the roof): low flat roofs (2.32 m decks) get a liner too
GAP = 0.05              # liner under the roof
NAME = "RoofCeil"
SKIP = ("apartment_block", "corridor")
NO_LINER = ("residence_tube",)     # critic 41: the vault with its lattice keeps its look (units have their own ceilings)
ALLOWANCE = (1900, 2600, 3200, 3800)     # triangle budget added per size (rooms_build): the ceiling
MAX_SURF = 5            # rooms_kit.MAX_SHELL_SURFACES is 6: one spare (parts added to the roof after this pass)


# --------------------------------------------------------------------------------------
# materials: the Roof group stays within MAX_SURF surfaces
# --------------------------------------------------------------------------------------
def _spec(nm):
    return BA.MATERIALS.get(nm, {})


def _target(nm):
    if nm in K.PALETTE_KEEP:
        return nm
    sp = _spec(nm)
    if sp.get("emit") or sp.get("alpha", 1.0) < 1.0:
        return "LightStrip" if nm == "Light" else nm
    return "PaletteMetal" if sp.get("metal", 0.0) >= 0.3 else "Palette"


def _emissive(nm):
    return bool(_spec(nm).get("emit")) or nm in ("Neon", "LightStrip", "Screen")


class Mats:
    """mat(name) -> a material the Roof group can take: its own surface if the roof has it or there is room, else the
    nearest surface the roof already has."""

    def __init__(self, roof, rm=None):
        # the surfaces the Roof group keeps: faces that interior_kit.split_decals moves to Decal parts later (outer-wall
        # decals in the doorway zone) do not count
        import interior_kit as IK_
        from math import hypot as _h
        keep = set()
        Rw = (rm.R - 0.32) if rm is not None else 1e9
        for idx, m in zip(roof.faces, roof.fmat):
            if rm is not None and m in IK_.DECAL_MATS:
                vs = [roof.verts[i] for i in idx]
                cx = sum(v.x for v in vs) / len(vs)
                cy = sum(v.y for v in vs) / len(vs)
                cz = sum(v.z for v in vs) / len(vs)
                if _h(cx, cy) >= Rw - 0.45 and 0.05 <= cz <= IK_.DECAL_ZMAX:
                    continue
            keep.add(_target(m))
        self.S = keep

    def __call__(self, nm):
        t = _target(nm)
        if t in self.S:
            return nm
        if len(self.S) < MAX_SURF:
            self.S.add(t)
            return nm
        if _emissive(nm):
            em = [m for m in self.S if _emissive(m)]
            if em:
                c = BA.hex_to_linear(_spec(nm).get("emit", _spec(nm).get("color", "#ffffff")))
                return min(em, key=lambda m: sum((a - b) ** 2 for a, b in zip(
                    c, BA.hex_to_linear(_spec(m).get("emit", _spec(m).get("color", "#ffffff"))))))
            return "Hull" if "Palette" in self.S else "Frame"
        if t == "PaletteMetal":
            return "HullDark"                 # into Palette
        if t == "Palette":
            return "Frame"                    # into PaletteMetal
        return "Hull"


# --------------------------------------------------------------------------------------
# the roof underside
# --------------------------------------------------------------------------------------
class Ceil:
    def __init__(self, rm):
        self.rm = rm
        roof = rm.roof
        o = roof.origin
        self.verts = [Vector(v) + o for v in roof.verts]
        self.faces = [list(f) for f in roof.faces]
        self.fmat = list(roof.fmat)
        self.bvh = BVHTree.FromPolygons(self.verts, self.faces, all_triangles=False) if self.faces else None
        self.cache = {}

    def hit(self, x, y):
        """(z, ok): the roof underside over (x, y); ok False under glass / lit faces or with no roof."""
        key = (round(x, 3), round(y, 3))
        if key in self.cache:
            return self.cache[key]
        out = (None, False)
        if self.bvh is not None:
            loc, nrm, idx, dist = self.bvh.ray_cast(Vector((x, y, 1.5)), Vector((0.0, 0.0, 1.0)), 30.0)
            if loc is not None:
                m = self.fmat[idx] if idx is not None and idx < len(self.fmat) else "Hull"
                ok = not (m in ("Glass", "Window", "CabinWindow") or _spec(m).get("alpha", 1.0) < 1.0
                          or (_emissive(m) and nrm.z < -0.2))
                out = (loc.z, ok)
        self.cache[key] = out
        return out

    def z(self, x, y, d=0.0, glass=True):
        """Conservative height at (x, y): the lowest roof over a small cross of radius d, minus GAP; None if any
        sample is missing (or, glass=False, under glass or a lit face: the liner leaves those clear)."""
        zs = []
        for dx, dy in ((0, 0), (d, 0), (-d, 0), (0, d), (0, -d), (0.7 * d, 0.7 * d), (-0.7 * d, 0.7 * d),
                       (0.7 * d, -0.7 * d), (-0.7 * d, -0.7 * d)) if d > 0 else ((0, 0),):
            z, ok = self.hit(x + dx, y + dy)
            if z is None or (not ok and not glass):
                return None
            zs.append(z)
        return min(zs) - GAP

    def zline(self, x0, y0, x1, y1, n=10, d=0.15):
        zs = [self.z(x0 + (x1 - x0) * t / n, y0 + (y1 - y0) * t / n, d) for t in range(n + 1)]
        if any(v is None for v in zs):
            return None
        return min(zs)


# --------------------------------------------------------------------------------------
# helpers on the part
# --------------------------------------------------------------------------------------
def hang_box(p, x0, x1, y0, y1, z0, z1, mat, bottom=None, top=False):
    """A box hanging from the ceiling (no top face unless top)."""
    mats = {"+z": None} if not top else {}
    if bottom:
        mats["-z"] = bottom
    p.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0), mat, mats=mats)


def cord(p, x, y, z0, z1, M, w=0.012):
    if z1 - z0 > 0.02:
        p.box((x, y, (z0 + z1) / 2), (w, w, z1 - z0), M("Frame"), mats={"+z": None, "-z": None})


def sign2(p, ctx, x, y, yaw, lines, h, ink, bg="HullDark", hang=0.30, frame="Frame"):
    """A double-sided hanging sign centred over (x, y), text along local +Y.  Returns True when it fits."""
    M = ctx.M
    w = max(PR.text_width(ln, h) for ln in lines) + 2.2 * h
    ht = len(lines) * h * 1.55 + 1.2 * h
    c, s = cos(radians(yaw)), sin(radians(yaw))
    ztop = ctx.c.zline(x - s * w / 2, y + c * w / 2, x + s * w / 2, y - c * w / 2, n=4)
    if ztop is None:
        return False
    zb = ztop - hang - ht
    if zb < MIN_Z:
        # a smaller sign closer to the ceiling
        hang = max(0.08, ztop - MIN_Z - ht)
        zb = ztop - hang - ht
        if zb < MIN_Z:
            return False
    zt = zb + ht
    with p.at(T(x, y, 0.0), RZ(yaw)):
        p.box((0.0, 0.0, (zb + zt) / 2), (0.05, w, ht), M(frame), mats={"+x": M(bg), "-x": M(bg)})
        for sy in (-1, 1):
            cord(p, 0.0, sy * (w / 2 - 0.08), zt, zt + hang, M)
        for rot in (0.0, 180.0):
            with p.at(RZ(rot)):
                zz = zt - 0.6 * h
                for ln in lines:
                    PR.text(p, ln, 0.0, zz - h / 2, h, M(ink), x=0.027)
                    zz -= h * 1.55
    return True


def pendant(p, ctx, x, y, shade="Accent", drop=0.55):
    M = ctx.M
    zc = ctx.c.z(x, y, 0.25)
    if zc is None:
        return False
    zb = max(MIN_Z, zc - drop)
    if zc - zb < 0.30:
        return False
    with p.at(T(x, y, 0.0)):
        p.lathe([(0.24, zb), (0.17, zb + 0.13), (0.05, zb + 0.20), (0.0, zb + 0.20)], M(shade), seg=10, smooth=True)
        p.lathe([(0.0, zb + 0.01), (0.20, zb + 0.01)], M(ctx.light), seg=10, smooth=False)
    cord(p, x, y, zb + 0.20, zc, M)
    return True


# --------------------------------------------------------------------------------------
# the liner, ribs, cove, crown, sensors
# --------------------------------------------------------------------------------------
def liner(ctx):
    p, c, M, rm = ctx.p, ctx.c, ctx.M, ctx.rm
    rmax = ctx.rmax
    # perf (2026-10-03, the indoor fps drop): a coarser liner - about half the faces of round 2
    NR = max(3, min(6, int(round(rmax / 1.9))))
    NS = 16 if rmax < 7.6 else 24
    ctx.NR, ctx.NS = NR, NS
    cell = rmax / NR
    Z = {}
    for k in range(NR + 1):
        rk = rmax * k / NR
        for j in range(NS if k else 1):
            a = radians(360.0 * j / NS)
            x, y = rk * cos(a), rk * sin(a)
            z = c.z(x, y, 0.45 * cell, glass=False)
            Z[(k, j)] = (x, y, z) if (z is not None and z >= LINER_MIN) else None

    def V(k, j):
        return Z.get((k, 0 if k == 0 else j % NS))
    ids = {}

    def vid(k, j):
        key = (k, 0 if k == 0 else j % NS)
        if key not in ids:
            ids[key] = p.v(V(*key))
        return ids[key]
    cells = []
    for k in range(NR):
        for j in range(NS):
            if k == 0:
                q = [(0, 0), (1, j), (1, j + 1)]
            else:
                q = [(k, j), (k + 1, j), (k + 1, j + 1), (k, j + 1)]
            if any(V(*v) is None for v in q):
                continue
            zq = [V(*v)[2] for v in q]
            if max(zq) - min(zq) > 0.6 or any(
                    ((V(*q[i])[0] - V(*q[i - 1])[0]) ** 2 + (V(*q[i])[1] - V(*q[i - 1])[1]) ** 2) ** 0.5 > 2.6
                    for i in range(len(q))):
                continue                  # critic 41: no steep shards, no huge triangles
            mat = M(ctx.panel[0]) if (k + j) % 2 else M(ctx.panel[1])
            # faces look down (into the room): reverse the counter-clockwise (from above) order
            p.f([vid(*v) for v in reversed(q)], mat)
            cells.append((k, j))
    ctx.cells = cells
    ctx.V = V
    ctx.edge = {}
    for (k, j) in cells:
        if k + 1 > ctx.edge.get(j, 0):
            ctx.edge[j] = k + 1
    return len(cells)


def ribs(ctx):
    p, M, V = ctx.p, ctx.M, ctx.V
    NR, NS = ctx.NR, ctx.NS
    cellset = set(ctx.cells)
    w = 0.07

    def rib(A, B, mat_bottom):
        a, b = Vector(A), Vector(B)
        d = min(0.07, a.z - MIN_Z, b.z - MIN_Z)
        flush = d < 0.025                  # a low roof: a painted seam / light line 6 mm under the liner
        if flush:
            d = 0.006
        t = (b - a)
        t.z = 0.0
        if t.length < 1e-4:
            return
        t.normalize()
        u = Vector((-t.y, t.x, 0.0)) * (w / 2)
        a0, a1, b0, b1 = a + u, a - u, b + u, b - u
        dn = Vector((0, 0, -d))
        p.quad(b0 + dn, b1 + dn, a1 + dn, a0 + dn, mat_bottom)      # bottom (faces down)
        if not flush:
            p.quad(b0, b0 + dn, a0 + dn, a0, M("Frame"))
            p.quad(a1, a1 + dn, b1 + dn, b1, M("Frame"))
    lit = max(1, NS // 4)
    for j in range(0, NS, 4):
        for k in range(1, NR):
            if (k, j) in cellset or (k, j - 1) in cellset:
                A, B = V(k, j), V(k + 1, j)
                if A and B:
                    rib(A, B, M(ctx.light) if j % lit == 0 and k >= NR // 2 else M("Frame"))
    km = max(1, NR // 2)
    for j in range(NS):
        if (km, j) in cellset or (km - 1, j) in cellset:
            A, B = V(km, j), V(km, j + 1)
            if A and B:
                rib(A, B, M("Frame"))


def cove(ctx, wide=False):
    """A light strip down from the liner edge, facing the room centre (wide: a soffit and a broad strip)."""
    p, M, V = ctx.p, ctx.M, ctx.V
    for j in range(ctx.NS):
        k = min(ctx.edge.get(j, 0), ctx.edge.get((j + 1) % ctx.NS, 0))
        if k < 2:
            continue
        A, B = V(k, j), V(k, j + 1)
        if not (A and B):
            continue
        h = 0.16 if wide else 0.09
        h = min(h, min(A[2], B[2]) - LINER_MIN)       # (at the wall edge only: no camera stands there)
        if h < 0.04:
            continue
        a, b = Vector(A), Vector(B)
        # inward by 3 cm, so the strip stands proud of the edge
        ia = Vector((-a.x, -a.y, 0)).normalized() * 0.03
        ib = Vector((-b.x, -b.y, 0)).normalized() * 0.03
        dn = Vector((0, 0, -h))
        p.quad(b + ib, b + ib + dn, a + ia + dn, a + ia, M(ctx.light))
        if wide:
            p.quad(a + ia + dn, a + ia * 4 + dn, b + ib * 4 + dn, b + ib + dn, M("Frame"))


def crown(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    rc = max(0.45, min(1.2, 0.13 * ctx.rmax))
    zs = [c.z(rc * cos(radians(a)), rc * sin(radians(a)), 0.1) for a in range(0, 360, 45)]
    if any(v is None for v in zs):
        return False
    zt = min(zs) - 0.18
    zb = zt - 0.07
    w = 0.10
    if zb < MIN_Z:
        # a low roof: a flush light ring 6 mm under the liner
        z = min(zs) - 0.006
        p.lathe([(rc - w, z), (rc + w, z)], M(ctx.light), seg=20, smooth=False, caps=False)
        return True
    p.lathe([(rc - w, zt), (rc - w, zb), (rc + w, zb), (rc + w, zt)],
            lambda k, i: (M("Frame"), M(ctx.light), M("Frame"))[k], seg=20, smooth=False)
    for k in range(3):
        a = radians(120.0 * k + 30.0)
        cord(p, rc * cos(a), rc * sin(a), zt, min(zs) + 0.02, M)
    return True


def sensors(ctx, n=6):
    p, M, V = ctx.p, ctx.M, ctx.V
    rng = ctx.rng
    cells = [cl for cl in ctx.cells if cl[0] >= 1]
    rng.shuffle(cells)
    for (k, j) in cells[:n]:
        q = [V(k, j), V(k + 1, j), V(k + 1, j + 1), V(k, j + 1)]
        x = sum(v[0] for v in q) / 4
        y = sum(v[1] for v in q) / 4
        z = min(v[2] for v in q) - 0.012
        with p.at(T(x, y, 0.0)):
            if z - 0.03 < MIN_Z:
                p.cap_disc(0.06, z, M("Hull"), seg=8, up=False)          # flush under a low roof
            else:
                p.vcyl(0.0, 0.0, z - 0.03, z, 0.06, seg=8, mat=M("Hull"), cap1=False)
    for (k, j) in cells[n:n + 2]:
        q = [Vector(V(k, j)), Vector(V(k + 1, j)), Vector(V(k + 1, j + 1)), Vector(V(k, j + 1))]
        cen = sum(q, Vector()) / 4
        inset = [cen + (v - cen) * 0.45 - Vector((0, 0, 0.012)) for v in q]
        p.quad(*reversed(inset), M("HullDark"))
        for t in (0.25, 0.5, 0.75):
            a = inset[0].lerp(inset[3], t) - Vector((0, 0, 0.004))
            b = inset[1].lerp(inset[2], t) - Vector((0, 0, 0.004))
            off = (inset[3] - inset[0]).normalized() * 0.012
            p.quad(b - off, a - off, a + off, b + off, M("Frame"))


# --------------------------------------------------------------------------------------
# role pieces
# --------------------------------------------------------------------------------------
def chord(rmax, y, frac=0.85):
    return sqrt(max(0.0, (rmax * frac) ** 2 - y * y))


def _interior_top(rm, x0, x1, y0, y1):
    """The highest Interior vertex over the rectangle (the machine under a crane), or 0."""
    best = 0.0
    for v in rm.interior.verts:
        if x0 <= v.x <= x1 and y0 <= v.y <= y1 and v.z > best:
            best = v.z
    return best


def crane(ctx, small=False):
    """Two runway rails along X, a hazard bridge across them, a trolley, a hoist cable and hook.  The sizes follow the
    head room (a compact rail under a low flat roof); the bridge stands where the machine below leaves room."""
    p, c, M, rng = ctx.p, ctx.c, ctx.M, ctx.rng
    rmax = ctx.rmax
    yr = (0.30 if small else 0.42) * rmax
    hx = min(chord(rmax, yr, 0.75), chord(rmax, 0.0, 0.7))
    if hx < 1.5:
        return False
    zl = [c.zline(-hx, s * yr, hx, s * yr) for s in (-1, 1)]
    if None in zl:
        return False
    zr = min(zl)
    zt = zr - 0.02
    room = zt - MIN_Z
    if room >= 0.85:
        rail_h, br_h, tr_h = 0.16, 0.26, 0.20
    elif room >= 0.38:
        rail_h, br_h, tr_h = 0.08, 0.14, 0.08
    else:
        return False
    z1 = zt - rail_h
    z0 = z1 - br_h
    mx0 = ctx.machine[0] if ctx.machine else 0.0
    my = ctx.machine[1] if ctx.machine else 0.0
    my = max(-yr + 0.35, min(yr - 0.35, my))
    pick = None
    for dx in (0.0, -1.3, 1.3, -2.2, 2.2, -3.0, 3.0):
        mx = mx0 + dx
        if abs(mx) > hx - 0.4:
            continue
        bridge_top = _interior_top(ctx.rm, mx - 0.25, mx + 0.25, -yr - 0.15, yr + 0.15)
        if bridge_top > z0 - tr_h - 0.08:
            continue
        under = _interior_top(ctx.rm, mx - 0.35, mx + 0.35, my - 0.35, my + 0.35)
        zh = max(MIN_Z + 0.01, under + 0.35, z0 - tr_h - 1.0)
        if zh + 0.12 > z0 - tr_h:
            zh = None                      # no cable: the hook block sits under the trolley
        pick = (mx, zh)
        break
    if pick is None:
        return False
    mx, zh = pick
    for sy in (-1, 1):
        hang_box(p, -hx, hx, sy * yr - 0.07, sy * yr + 0.07, z1, zt, M("Frame"))
        for xx in (-hx * 0.7, 0.0, hx * 0.7):
            cord(p, xx, sy * yr, zt, zr + GAP, M, w=0.05)
    hang_box(p, mx - 0.13, mx + 0.13, -yr - 0.12, yr + 0.12, z0, z1, M("Hazard"), bottom=M("Hazard"))
    nst = 8                                   # hazard stripes on both faces of the bridge
    sh = min(0.04, br_h * 0.25)
    for k in range(nst):
        y0 = -yr + 2 * yr * k / nst
        if k % 2 == 0:
            for sx in (-1, 1):
                q = [(mx + sx * 0.131, y0, z0 + 0.015), (mx + sx * 0.131, y0 + yr / nst, z0 + 0.015),
                     (mx + sx * 0.131, y0 + yr / nst, z0 + 0.015 + sh), (mx + sx * 0.131, y0, z0 + 0.015 + sh)]
                p.quad(*(q if sx > 0 else list(reversed(q))), M("SecBlack"))
    txt = ("MAX LOAD: 1 INTERN", "LIFTS: MOSTLY", "HOIST.AI (BETA)")[rng.randrange(3)]
    th = min(0.10, (z1 - z0 - sh - 0.04) * 0.8, 2 * yr * 0.8 / max(1.0, (6 * len(txt) - 1) / 7.0))
    if th >= 0.05:
        for rot in (0.0, 180.0):
            with p.at(T(mx, 0.0, 0.0), RZ(rot)):
                PR.text(p, txt, 0.0, (z0 + 0.015 + sh + z1) / 2, th, M("Rubber"), x=0.132)
    hang_box(p, mx - 0.22, mx + 0.22, my - 0.18, my + 0.18, z0 - tr_h, z0, M("HullDark"), bottom=M("Frame"))
    if zh is not None:
        cord(p, mx - 0.05, my, zh + 0.12, z0 - tr_h, M, w=0.02)
        cord(p, mx + 0.05, my, zh + 0.12, z0 - tr_h, M, w=0.02)
        hang_box(p, mx - 0.12, mx + 0.12, my - 0.08, my + 0.08, zh + 0.05, zh + 0.12, M("Hazard"), bottom=M("Frame"),
                 top=True)
        hang_box(p, mx - 0.025, mx + 0.025, my - 0.06, my + 0.06, zh, zh + 0.05, M("Frame"), top=True)
    return True


def growlights(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    rmax = ctx.rmax
    n = max(3, min(6, int(rmax / 1.3)))
    put = 0
    for k in range(n):
        y = (k - (n - 1) / 2) * (1.6 * rmax / n)
        hx = chord(rmax, y, 0.80)
        if hx < 0.8:
            continue
        zl = c.zline(-hx, y, hx, y)
        if zl is None:
            continue
        zt = zl - 0.40
        zb = zt - 0.07
        if zb < MIN_Z:
            zt = zl - 0.06
            zb = zt - 0.07
            if zb < MIN_Z:
                continue
        hang_box(p, -hx, hx, y - 0.09, y + 0.09, zb, zt, M("Frame"), bottom=M("L4Band"))
        for xx in (-hx * 0.8, hx * 0.8):
            cord(p, xx, y, zt, zl + GAP, M)
        put += 1
    return put > 0


def ringrail(ctx, frac=0.45, pods=3, monitors=True):
    p, c, M, rng = ctx.p, ctx.c, ctx.M, ctx.rng
    r = frac * ctx.rmax
    pts = [(r * cos(radians(a)), r * sin(radians(a))) for a in range(0, 360, 24)]
    zs = [c.z(x, y, 0.2) for x, y in pts]
    if any(v is None for v in zs):
        return False
    zt = min(zs) - 0.30
    if zt - 0.06 - (0.45 if monitors else 0.2) < MIN_Z:
        zt = min(zs) - 0.06
        if zt - 0.06 - 0.3 < MIN_Z:
            return False
    ring = [(x, y, zt - 0.03) for x, y in pts] + [(pts[0][0], pts[0][1], zt - 0.03)]
    p.beam_path(ring, 0.06, 0.06, M("Frame"))
    for k in range(0, len(pts), 4):
        cord(p, pts[k][0], pts[k][1], zt, zs[k] + GAP, M)
    for k in range(pods):
        a = radians(360.0 * k / pods + 20.0)
        x, y = r * cos(a), r * sin(a)
        zp = zt - 0.06
        if monitors:
            # a hanging monitor facing the room centre, with a chart
            yaw = (360.0 * k / pods + 20.0) + 180.0
            hb = min(0.40, zp - 0.10 - MIN_Z)
            if hb < 0.2:
                continue
            with p.at(T(x, y, 0.0), RZ(yaw)):
                cord(p, 0.0, 0.0, zp - 0.10, zp, M, w=0.03)
                zm = zp - 0.10 - hb / 2
                p.box((0.0, 0.0, zm), (0.05, hb * 1.6, hb), M("HullDark"))
                for j in range(5):                      # a bar chart on the screen face
                    hb_ = hb * (0.15 + 0.13 * ((j * 3 + k) % 5))
                    y_ = -hb * 0.56 + hb * 0.28 * j
                    plate = [(0.026, y_ - hb * 0.09, zm - hb * 0.38), (0.026, y_ + hb * 0.09, zm - hb * 0.38),
                             (0.026, y_ + hb * 0.09, zm - hb * 0.38 + hb_), (0.026, y_ - hb * 0.09, zm - hb * 0.38 + hb_)]
                    p.quad(*plate, M("LightStrip") if j != 4 else M("Neon"))
        else:
            cord(p, x, y, zp - 0.12, zp, M, w=0.03)
            p.box((x, y, zp - 0.18), (0.16, 0.16, 0.12), M("Hull"), mats={"+z": None})
            p.vcyl(x, y, zp - 0.26, zp - 0.24, 0.05, seg=8, mat=M("HullDark"), cap1=False)
    return True


def surgical(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    put = 0
    for k in range(3):
        a = radians(120.0 * k + 10.0)
        x, y = 0.45 * ctx.rmax * cos(a), 0.45 * ctx.rmax * sin(a)
        zc = c.z(x, y, 0.35)
        if zc is None:
            continue
        zb = max(MIN_Z, zc - 0.55)
        if zc - zb < 0.25:
            continue
        with p.at(T(x, y, 0.0)):
            p.lathe([(0.0, zb), (0.34, zb), (0.32, zb + 0.08)], lambda kk, i: (M("LightStrip"), M("Hull"))[kk],
                    seg=12, smooth=False)
            p.lathe([(0.32, zb + 0.08), (0.0, zb + 0.14)], M("Hull"), seg=12, smooth=True)
        cord(p, x, y, zb + 0.13, zc, M, w=0.03)
        put += 1
    return put > 0


def truss(ctx):
    """Two open steel trusses across the room (top and bottom chords, diagonals), a cable tray between them."""
    p, c, M = ctx.p, ctx.c, ctx.M
    rmax = ctx.rmax
    put = 0
    for y in (0.30 * rmax, -0.30 * rmax):
        hx = chord(rmax, y, 0.80)
        zl = c.zline(-hx, y, hx, y)
        if zl is None:
            continue
        zt = zl - 0.04
        dh = min(0.45, zt - MIN_Z - 0.02)
        if dh < 0.18:
            continue
        zb = zt - dh
        for z in (zt, zb):
            p.beam((-hx, y, z), (hx, y, z), 0.07, 0.07, M("Hazard" if z == zb else "Frame"))
        nseg = max(3, int(2 * hx / 0.8))
        for k in range(nseg):
            x0 = -hx + 2 * hx * k / nseg
            x1 = -hx + 2 * hx * (k + 1) / nseg
            p.beam((x0, y, zb), (x0, y, zt), 0.04, 0.04, M("Frame"), caps=False)
            if k % 2 == 0:
                p.beam((x0, y, zb), (x1, y, zt), 0.035, 0.035, M("Frame"), caps=False)
            else:
                p.beam((x0, y, zt), (x1, y, zb), 0.035, 0.035, M("Frame"), caps=False)
        put += 1
    if put == 2:
        y0, y1 = -0.30 * rmax + 0.1, 0.30 * rmax - 0.1
        zl = c.zline(0.0, y0, 0.0, y1)
        if zl is not None and zl - 0.25 > MIN_Z:
            hang_box(p, -0.25, 0.25, y0, y1, zl - 0.25, zl - 0.18, M("Frame"))           # the cable tray
            for k in range(3):
                hang_box(p, -0.20 + 0.15 * k, -0.15 + 0.15 * k, y0, y1, zl - 0.18, zl - 0.15,
                         M(("Hazard", "WaterBlue", "SignalRed")[k]))
    return put > 0


def duct(ctx, cross=False):
    p, c, M = ctx.p, ctx.c, ctx.M
    rmax = ctx.rmax
    put = 0
    if cross:
        # the cross duct of the duct grid: along Y at x = 0, under the other two
        hy = chord(rmax, 0.0, 0.78)
        zl = c.zline(0.0, -hy, 0.0, hy)
        if zl is None:
            return False
        r = 0.16
        zc = zl - 0.10 - 0.44 - r
        if zc - r < MIN_Z:
            zc = zl - 0.06 - r
            if zc - r < MIN_Z:
                return False
        p.cyl((0.0, -hy, zc), (0.0, hy, zc), r, seg=8, mat=M("Metal"), smooth=True)
        for yy in (-hy * 0.5, hy * 0.5):
            cord(p, 0.0, yy, zc + r, zl + GAP, M, w=0.03)
        return True
    for y in (0.35 * rmax, -0.35 * rmax):
        hx = chord(rmax, y, 0.82)
        zl = c.zline(-hx, y, hx, y)
        if zl is None:
            continue
        r = 0.22
        zc = zl - 0.10 - r
        if zc - r < MIN_Z:
            r = 0.14
            zc = zl - 0.06 - r
            if zc - r < MIN_Z:
                continue
        p.cyl((-hx, y, zc), (hx, y, zc), r, seg=8, mat=M("Metal"), smooth=True)
        for xx in (-hx * 0.5, 0.0, hx * 0.5):
            p.cyl((xx - 0.03, y, zc), (xx + 0.03, y, zc), r + 0.03, seg=8, mat=M("Frame"), smooth=False)
            cord(p, xx, y, zc + r, zl + GAP, M, w=0.03)
        put += 1
    return put > 0


def pipes(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    rmax = ctx.rmax
    put = 0
    for k, y in enumerate((0.25 * rmax, 0.32 * rmax, -0.30 * rmax)):
        hx = chord(rmax, y, 0.8)
        zl = c.zline(-hx, y, hx, y)
        if zl is None:
            continue
        r = 0.07
        zc = zl - 0.18 - 0.08 * k
        if zc - r < MIN_Z:
            continue
        p.cyl((-hx, y, zc), (hx, y, zc), r, seg=6, mat=M("Copper"), smooth=True)
        for xx in (-hx * 0.6, hx * 0.6):
            cord(p, xx, y, zc + r, zl + GAP, M, w=0.02)
        put += 1
    return put > 0


def potrack(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    x, y = ctx.focus
    zc = c.z(x, y, 0.8)
    if zc is None:
        return False
    zr = zc - 0.55
    if zr - 0.32 < MIN_Z:
        zr = MIN_Z + 0.32
        if zc - zr < 0.15:
            return False
    hx, hy = 0.6, 0.3
    for sy in (-1, 1):
        hang_box(p, x - hx, x + hx, y + sy * hy - 0.02, y + sy * hy + 0.02, zr - 0.04, zr, M("Metal"), top=True)
    for sx in (-1, 1):
        hang_box(p, x + sx * hx - 0.02, x + sx * hx + 0.02, y - hy, y + hy, zr - 0.04, zr, M("Metal"), top=True)
        cord(p, x + sx * hx, y, zr, zc + GAP, M)
    for k, (dx, rr, mat) in enumerate(((-0.40, 0.11, "Copper"), (-0.12, 0.09, "Metal"), (0.15, 0.12, "Copper"),
                                       (0.42, 0.08, "HullDark"))):
        sy = (-1) ** k * hy
        cord(p, x + dx, y + sy, zr - 0.10, zr - 0.04, M, w=0.01)
        p.vcyl(x + dx, y + sy, zr - 0.10 - 0.18, zr - 0.10, rr, seg=8, mat=M(mat), cap1=False)
    return True


def mirrorball(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    zc = c.z(0.0, 0.0, 0.3)
    if zc is None:
        return False
    r = 0.22
    zb = max(MIN_Z, zc - 0.85)
    if zc - zb < 2 * r + 0.1:
        return False
    p.sphere((0.0, 0.0, zb + r), r, M("Metal"), seg=10, rings=6, smooth=False)
    cord(p, 0.0, 0.0, zb + 2 * r, zc, M)
    return True


def planets(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    zc = c.z(0.0, 0.0, 1.2)
    if zc is None:
        return False
    zr = zc - 0.35
    specs = ((1.0, 0.0, 0.22, "WaterBlue"), (-0.9, 0.5, 0.16, "SignalRed"), (0.1, -1.1, 0.26, "Hazard"),
             (-0.3, 1.0, 0.12, "Hull"))
    if zr - 0.5 - 0.26 < MIN_Z:
        zr = min(zc - 0.08, MIN_Z + 0.8)
        if zc - zr < 0.05:
            return False
    p.beam((-1.0, 0.0, zr), (1.0, 0.0, zr), 0.03, 0.03, M("Frame"))
    p.beam((0.0, -1.1, zr), (0.0, 1.1, zr), 0.03, 0.03, M("Frame"))
    cord(p, 0.0, 0.0, zr, zc + GAP, M)
    for k, (x, y, r, mat) in enumerate(specs):
        drop = 0.18 + 0.12 * k
        zs = zr - drop - r
        if zs - r < MIN_Z:
            zs = MIN_Z + r
            drop = zr - zs - r
            if drop < 0.02:
                continue
        cord(p, x, y, zs + r, zr, M, w=0.008)
        p.sphere((x, y, zs), r, M(mat), seg=8, rings=5)
        if k == 2:
            with p.at(T(x, y, zs)):
                p.torus(r * 1.6, 0.025, M("Frame"), seg=12, tseg=3)
    return True


def cameras(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    put = 0
    for k in range(4):
        a = radians(90.0 * k + 45.0)
        x, y = 0.62 * ctx.rmax * cos(a), 0.62 * ctx.rmax * sin(a)
        zc = c.z(x, y, 0.2)
        if zc is None or zc - 0.12 < MIN_Z:
            continue
        p.vcyl(x, y, zc - 0.03, zc, 0.12, seg=8, mat=M("SecBlack"), cap1=False)
        p.sphere((x, y, zc - 0.03), 0.09, M("HullDark"), seg=8, rings=4, scale=(1, 1, 0.9))
        put += 1
    return put > 0


def cagelamps(ctx):
    p, c, M = ctx.p, ctx.c, ctx.M
    put = 0
    for k in range(4):
        a = radians(90.0 * k)
        x, y = 0.45 * ctx.rmax * cos(a), 0.45 * ctx.rmax * sin(a)
        zc = c.z(x, y, 0.2)
        if zc is None:
            continue
        zb = max(MIN_Z, zc - 0.45)
        if zc - zb < 0.25:
            continue
        hang_box(p, x - 0.12, x + 0.12, y - 0.12, y + 0.12, zb + 0.04, zb + 0.16, M("Frame"), bottom=M(ctx.light))
        for sx in (-1, 1):
            for sy in (-1, 1):
                p.box((x + sx * 0.14, y + sy * 0.14, zb + 0.09), (0.015, 0.015, 0.18), M("PrisonOrange"),
                      mats={"+z": None, "-z": None})
        cord(p, x, y, zb + 0.16, zc, M)
        put += 1
    return put > 0


SIGNS = {
    "bar": (("LAST ORDERS:", "NEVER"), "Neon"),
    "kitchen": (("ORDER UP!",), "Neon"),
    "science": (("PEER REVIEW", "IN PROGRESS"), "LightStrip"),
    "medical": (("PLEASE WAIT:", "THE AI IS THINKING"), "LightStrip"),
    "life": (("BREATHE IN.", "WE CHECKED."), "LightStrip"),
    "logistics": (("DRONE LANE", "(LOOK UP)"), "Neon"),
    "retail": (("NOW WITH AI*",), "Neon"),
    "academy": (("THE CLOUD",), "LightStrip"),
    "security": (("SMILE: YOU ARE", "BEING SUMMARISED"), "SignalRedGlow"),
    "jail": (("NO WIFI.", "NO MERCY."), "PrisonOrangeGlow"),
    "links": (("YOU ARE HERE",), "Neon"),
    "comfort": (("CHILL.EXE", "IS RUNNING"), "Neon"),
    "housing": (("HOME SWEET POD",), "Neon"),
    "farm": (("PLANTS: HAPPY*",), "Glow"),
    "industry": (("WORK SMARTER", "NOT HUMANER"), "Neon"),
    "hr": (("THIS IS A", "SAFE SPACE*"), "Neon"),
    "distillery": (("SPIRITS UP",), "Neon"),
    "park": None,
}
RETAIL_BANNERS = (("SALE 50%*",), ("BUY NOW", "PAY LATER"), ("NOW WITH AI*",))


def role_piece(ctx, role):
    rmax = ctx.rmax
    put = []

    def sign_at(lines, ink, r=0.0, a=0.0, h=None):
        x, y = r * cos(radians(a)), r * sin(radians(a))
        hh = h or min(0.16, max(0.09, 0.022 * rmax))
        if sign2(ctx.p, ctx, x, y, a, lines, hh, ink):         # the face looks along the radius
            put.append("sign")
    big = ctx.size >= 2
    if role in ("industry", "distillery"):
        if role == "distillery":
            if pipes(ctx):
                put.append("pipes")
            if crane(ctx, small=True):
                put.append("crane")
        else:
            # critic 41: three ceiling variants, by type: a crane bay, a duct grid, an open truss
            var = sum(ord(ch) for ch in ctx.rm.tid) % 3
            done = False
            if var == 1:
                done = duct(ctx) and duct(ctx, cross=True)
                if done:
                    put.append("ductgrid")
            elif var == 2:
                done = truss(ctx)
                if done:
                    put.append("truss")
            if not done and crane(ctx):
                put.append("crane")
    elif role == "logistics":
        if crane(ctx, small=True):
            put.append("crane")
    elif role == "farm":
        if growlights(ctx):
            put.append("growlights")
    elif role == "bar":
        if mirrorball(ctx):
            put.append("mirrorball")
        for k in range(4 if big else 3):
            a = radians(90.0 * k + 30.0)
            if pendant(ctx.p, ctx, 0.55 * rmax * cos(a), 0.55 * rmax * sin(a), shade=("Neon", "Accent")[k % 2]):
                put.append("pendant")
    elif role == "kitchen":
        if potrack(ctx):
            put.append("potrack")
        for k in range(3):
            a = radians(120.0 * k + 200.0)
            if pendant(ctx.p, ctx, 0.5 * rmax * cos(a), 0.5 * rmax * sin(a), shade="Hull"):
                put.append("pendant")
    elif role == "science":
        if ringrail(ctx, monitors=True):
            put.append("rail")
    elif role == "medical":
        if surgical(ctx):
            put.append("surgical")
    elif role == "life":
        if duct(ctx):
            put.append("duct")
    elif role in ("housing", "comfort", "hr"):
        for k in range(3 if big else 2):
            a = radians(120.0 * k + 15.0)
            if pendant(ctx.p, ctx, 0.42 * rmax * cos(a), 0.42 * rmax * sin(a),
                       shade=("Wood", "Accent", "Hull")[k % 3]):
                put.append("pendant")
    elif role == "retail":
        for k, lines in enumerate(RETAIL_BANNERS[:3 if big else 2]):
            sign_at(lines, "Neon", 0.45 * rmax, 120.0 * k + 30.0)
    elif role == "academy":
        if planets(ctx):
            put.append("planets")
    elif role == "security":
        if cameras(ctx):
            put.append("cameras")
    elif role == "jail":
        if cagelamps(ctx):
            put.append("cagelamps")
    sg = SIGNS.get(role)
    if sg and role != "retail":
        # the hanging sign: off the centre (the crown light), turned so the follow camera meets it
        sign_at(sg[0], sg[1], 0.30 * rmax if rmax > 3.5 else 0.0, ctx.rng.uniform(0, 360))
    return put


# --------------------------------------------------------------------------------------
# the upper wall band (eye level in the follow view) and eye-level signs: parts Upper_<seg>_Band / Upper_<seg>_Sign,
# which RENDER's group_of puts in WallsUp (hidden per segment at a doorway, hidden in the cutaway, not in the camera's
# ceiling grid)
# --------------------------------------------------------------------------------------
EYE_SIGNS = {
    "industry": (("WORK SMARTER", "NOT HUMANER"), ("ROBOTS AT WORK", "HUMANS: ALSO"), ("0 DAYS SINCE", "LAST REBOOT"),
                 ("HARD HATS", "SOFT SKILLS")),
    "distillery": (("DRINK", "RESPONSIBLY*"), ("SPIRITS", "UP"), ("AGED 3 DAYS", "IN A BOT")),
    "bar": (("HAPPY HOUR", "24/7/365"), ("NO AGENTS", "AFTER 9PM"), ("TRY OUR", "PROMPT SOUR"),
            ("LIVE TONIGHT:", "DJ LATENCY")),
    "kitchen": (("TODAY:", "ALGAE AGAIN"), ("CHEF IS", "A KETTLE"), ("WASH HANDS", "(BOTH)")),
    "farm": (("PLANTS LIKE", "COMPLIMENTS"), ("NO TALKING", "TO THE KALE"), ("GROW UP", "(SLOWLY)")),
    "life": (("AIR: 21% O2", "VIBES: 100%"), ("DO NOT", "UNPLUG"), ("BREATHE IN", "WE CHECKED")),
    "logistics": (("LOST + FOUND", "MOSTLY LOST"), ("INVENTORY", "IS A VIBE"), ("DRONE LANE", "LOOK UP")),
    "medical": (("ASK A DOCTOR", "NOT A CHATBOT"), ("WAIT TIME:", "ESTIMATED"), ("WASH. SEAL.", "REPEAT.")),
    "science": (("PUBLISH", "OR PERISH"), ("HYPOTHESIS:", "IT WORKS"), ("DO NOT TOUCH", "THE MODEL")),
    "housing": (("HOME SWEET", "POD"), ("QUIET HOURS", "22:00"), ("SHOES OFF", "ROBOTS TOO")),
    "comfort": (("CHILL.EXE", "RUNNING"), ("NO WORK", "TALK"), ("TOUCH GRASS", "(FAKE)")),
    "links": (("SUIT UP", "OR SHUT UP"), ("MIND", "THE GAP"), ("YOU ARE", "HERE")),
    "retail": (("BUY 2 GET 1", "PROMPT FREE"), ("SALE*", "*TERMS APPLY"), ("NOW WITH", "MORE AI")),
    "academy": (("KNOWLEDGE", "IS POWER*"), ("NO PHONES", "IN CLASS"), ("SHOW YOUR", "PROMPTS")),
    "security": (("SMILE: YOU", "ARE ON CAM"), ("REPORT", "ROGUE AI"), ("WATCHING", "(POLITELY)")),
    "jail": (("TIME OUT", "ZONE"), ("NO WIFI", "NO MERCY"), ("GOOD", "BEHAVIOUR?")),
    "park": (("TOUCH", "GRASS"), ("KEEP OFF", "THE ROBOTS")),
    "hr": (("WE ARE", "LISTENING*"), ("CIRCLE", "BACK"), ("BREATHE IN", "BREATHE OUT"), ("YOUR CALL", "MATTERS*")),
}
EYE_INK = ("Neon", "LightStrip")


def band_part(ctx, k):
    """The one WallsUp object of segment k (band and sign together: fewer draw objects)."""
    d = ctx.__dict__.setdefault("bandparts", {})
    if k not in d:
        d[k] = P("Upper_%02d_Band" % k)
        ctx.rm.extra_parts = list(getattr(ctx.rm, "extra_parts", [])) + [d[k]]
    return d[k]


def _ray_r(c, a, z):
    """The roof's inner radius at angle a (deg) and height z (a horizontal ray from the axis), or None."""
    if c.bvh is None:
        return None
    loc, nrm, idx, dist = c.bvh.ray_cast(Vector((0.0, 0.0, z)), Vector((cos(radians(a)), sin(radians(a)), 0.0)), 40.0)
    return dist if loc is not None else None


def band(ctx):
    """Dome rooms: a panelled skin over the bare dome ring from the wall top (1.42 m) up to the liner edge."""
    rm, c = ctx.rm, ctx.c
    if not ctx.NS or rm.tid.startswith("airlock"):
        return 0                 # (the airlock's own cutaway rule keeps its upper wall: interior_airlock.CUT_VISIBLE)
    SEG = 360.0 / 32
    zs = (1.42, 2.00, 2.60, 3.20)              # perf 2026-10-03: four rows (round 2: six)
    put = 0
    for k in range(32):
        cols = []
        for a in (k * SEG, (k + 1) * SEG):
            je = int(round(a / (360.0 / ctx.NS))) % ctx.NS
            re = ctx.rmax * ctx.edge.get(je, 0) / max(1, ctx.NR)
            col = []
            ve = ctx.V(ctx.edge.get(je, 0), je) if ctx.edge.get(je, 0) else None
            ztop = (ve[2] - 0.01) if ve else None
            for z in zs:
                if ztop is not None and z >= ztop:
                    break
                r = _ray_r(c, a, z)
                if r is None or r - 0.05 < max(re, ctx.rmax * 0.4):
                    break
                col.append((r - 0.05, z))
            if ztop is not None and col and ztop > col[-1][1] + 0.03:
                r = _ray_r(c, a, ztop)               # up to the liner edge (podium rooms: their flat ceiling)
                if r is not None and r - 0.05 >= max(re, ctx.rmax * 0.4):
                    col.append((r - 0.05, ztop))
            cols.append(col)
        n = min(len(cols[0]), len(cols[1]))
        if n < 2:
            continue
        p = band_part(ctx, k)
        a0, a1 = radians(k * SEG), radians((k + 1) * SEG)
        V0 = [Vector((r * cos(a0), r * sin(a0), z)) for r, z in cols[0][:n]]
        V1 = [Vector((r * cos(a1), r * sin(a1), z)) for r, z in cols[1][:n]]
        for i in range(n - 1):
            p.quad(V0[i], V0[i + 1], V1[i + 1], V1[i], ctx.band[0])     # faces the room
        inn = Vector((-cos(a0), -sin(a0), 0.0)) * 0.012
        t_ = Vector((-sin(a0), cos(a0), 0.0)) * 0.012
        for i in range(n - 1 if k % 4 == 0 else 0):                      # a seam on every fourth segment edge
            a_, b_ = V0[i], V0[i + 1]
            p.quad(a_ + inn - t_, b_ + inn - t_, b_ + inn + t_, a_ + inn + t_, "Frame")
        for i in range(n - 1):                                           # an accent stripe at 1.95 m
            if V0[i].z <= 1.95 < V0[i + 1].z:
                t0 = (1.95 - V0[i].z) / (V0[i + 1].z - V0[i].z)
                q0, q1 = V0[i].lerp(V0[i + 1], t0), V1[i].lerp(V1[i + 1], t0)
                in0 = Vector((-cos(a0), -sin(a0), 0.0)) * 0.01
                in1 = Vector((-cos(a1), -sin(a1), 0.0)) * 0.01
                up = Vector((0, 0, 0.025))
                p.quad(q0 + in0 - up, q0 + in0 + up, q1 + in1 + up, q1 + in1 - up, ctx.band[1])
        put += 1
    return put


def eye_signs(ctx, role):
    """Big signs at eye level on the upper wall (1.50 - 2.33 m), one per chosen wall segment (masked with it)."""
    rm, c, rng = ctx.rm, ctx.c, ctx.rng
    lst = EYE_SIGNS.get(role)
    if not lst:
        return 0
    nsg = (2, 3, 4, 5)[min(3, ctx.size)]
    SEG = 360.0 / 32
    start = rng.randrange(32)
    put = 0
    for i in range(nsg):
        k = (start + i * (32 // nsg) + (i % 2)) % 32
        a = (k + 0.5) * SEG
        rs = [_ray_r(c, a + da, z) for da in (-SEG * 0.42, 0.0, SEG * 0.42) for z in (1.55, 1.9, 2.25)]
        if any(r is None for r in rs) or min(rs) < ctx.rmax * 0.6:
            continue
        r = min(rs) - 0.07
        w = 2.0 * r * sin(radians(SEG * 0.42)) - 0.06
        lines = lst[(i + start) % len(lst)]
        h = PR.fit_h(lines, w - 0.14, 0.15)
        if h < 0.06:
            continue
        ht = len(lines) * h * 1.55 + 1.0 * h
        z0 = max(1.50, 1.90 - ht / 2)
        z1 = z0 + ht
        if z1 > 2.33:
            continue
        p = band_part(ctx, k)                      # perf: the sign shares its segment's object
        ink = EYE_INK[(i + start) % 2]
        with p.at(RZ(a), T(r, 0.0, 0.0), RZ(180.0)):
            # local +X faces the room centre, text along local +Y
            p.box((-0.025, 0.0, (z0 + z1) / 2), (0.05, w, z1 - z0), "Frame", mats={"+x": "HullDark"})
            p.box((0.002, 0.0, z1 - 0.012), (0.01, w - 0.02, 0.012), "Accent")
            zz = z1 - 0.5 * h - 0.02
            for ln in lines:
                PR.text(p, ln, 0.0, zz - h / 2, h, ink, x=0.003)
                zz -= h * 1.55
        put += 1
    return put


# --------------------------------------------------------------------------------------
# entry
# --------------------------------------------------------------------------------------
class Ctx:
    pass


# critic 41 (light colour and identity per role): the light-strip colour, the two liner panel tones and the upper band
# (panel, stripe).  The light colour also goes to the build report (v3.ceiling.light) for RENDER's lights.
WARM, COOL, AMBER = "Window", "LightStrip", "BeaconAmber"
LIGHT_OF = {"bar": WARM, "kitchen": WARM, "comfort": WARM, "housing": WARM, "hr": WARM, "park": WARM,
            "science": COOL, "medical": COOL, "academy": COOL, "life": COOL, "links": COOL, "retail": "Neon",
            "industry": AMBER, "logistics": AMBER, "distillery": AMBER, "farm": "L4Band",
            "security": "SignalRedGlow", "jail": "PrisonOrangeGlow"}
LIGHT_HEX = {WARM: "#ffd27a", COOL: "#eaf6ff", AMBER: "#ffb020", "L4Band": "#a78bfa", "Neon": "category",
             "SignalRedGlow": "#d93a3a", "PrisonOrangeGlow": "#ff7a1a"}
PANEL_OF = {"bar": ("Hull", "Wood"), "comfort": ("Hull", "Wood"), "housing": ("Hull", "Wood"), "hr": ("Hull", "Wood"),
            "security": ("SecBlack", "HullDark"), "jail": ("HullDark", "Frame"),
            "industry": ("Hull", "HullDark"), "distillery": ("Hull", "Copper")}
BAND_OF = {"security": ("SecBlack", "SignalRed"), "jail": ("HullDark", "PrisonOrange")}


def build(rm):
    """Add RoofCeil to rm.extra_parts.  Returns the triangle count (also in interior_props.USED_TRIS['_ceiling'])."""
    import interior_roles as RO
    tid = getattr(rm, "tid", "")
    if tid in SKIP or not getattr(rm, "v3", False) or not rm.roof.faces:
        return 0
    ctx = Ctx()
    ctx.rm = rm
    ctx.c = Ceil(rm)
    ctx.M = Mats(rm.roof, rm)
    ctx.p = P(NAME)
    ctx.rmax = rm.Ri - 0.06
    ctx.size = 1 if getattr(rm, "single", False) else (getattr(rm, "size", 1) or 0)
    ctx.rng = random.Random(sum(ord(ch) for ch in tid) * 7 + ctx.size)
    role0 = RO.role_for(rm)
    ctx.light = LIGHT_OF.get(role0, COOL)
    ctx.panel = PANEL_OF.get(role0, ("Hull", "Cargo"))
    ctx.band = BAND_OF.get(role0, ("Hull", "Accent"))
    if role0 in ("industry", "distillery"):
        import interior_fam_ind as _IND          # critic 41: a type-coloured wall band in industry
        ctx.band = ("Hull", _IND.ZONE.get(tid, "Accent"))
    plan = getattr(rm, "plan", None)
    ctx.machine = None
    ctx.focus = (0.0, 0.0)
    if plan is not None:
        for (cx, cy, hx, hy, yaw, tag) in plan.rects:
            if tag == "machine":
                ctx.machine = (cx, cy)
                break
        for (cx, cy, hx, hy, yaw, tag) in plan.rects:
            if tag in ("counter", "bench", "table"):
                ctx.focus = (cx, cy)
                break
    n = liner(ctx) if tid not in NO_LINER else 0
    if n == 0:
        # no roof to line (glass): the role piece only
        ctx.cells, ctx.edge, ctx.NR, ctx.NS = [], {}, 0, 0
    else:
        ribs(ctx)
        role = RO.role_for(rm)
        cove(ctx, wide=role in ("housing", "comfort", "bar"))
        crown(ctx)
        sensors(ctx, n=2 + ctx.size)
    put = role_piece(ctx, RO.role_for(rm))
    ctx.band_tris = 0
    nb = band(ctx) if n else 0
    ns = eye_signs(ctx, RO.role_for(rm))
    if ns:
        put.append("eyesign x%d" % ns)
    ctx.p.origin = Vector((0.0, 0.0, 0.0))
    if ctx.p.faces:
        rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [ctx.p]
    ctx.band_tris = sum(sum(len(f) - 2 for f in q.faces) for q in getattr(ctx, "bandparts", {}).values())
    tris = sum(len(f) - 2 for f in ctx.p.faces) + ctx.band_tris
    PR.USED_TRIS["_ceiling"] = tris
    for k in put:
        PR.USED["c_" + k] = PR.USED.get("c_" + k, 0) + 1
    rm.ceiling_info = dict(cells=n, band_segments=nb, pieces=put, tris=tris, surfaces=sorted(ctx.M.S),
                           light=LIGHT_HEX.get(ctx.light, "#eaf6ff"), light_mat=ctx.light)
    return tris
