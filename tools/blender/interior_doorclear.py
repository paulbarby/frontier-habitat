"""Frontier Habitat 5.0 - ART-HAB: doorway head-room check (Paul 2026-10-03, follow view).

Paul: "walking into corridors, the habitat's roof section is so low it overlaps the door entries, so you have beams
at every door entrance."  Rule (coordinator, Paul's choice): every roof, ceiling, rib, ring and band part stays at
or above the door opening top + 0.25 m (DOOR_TOP 2.24 + 0.25 = 2.49 m) near the wall, all round the room.

check(objs, Rw, blocked) looks, for every free door angle (1 deg steps, the blocked spans of door_blocked.json
left out), at the door opening volume extended into the room:
    along the door axis   s in [Rw - 0.38 - 1.50, Rw + 0.06]   (inner jamb face + 1.5 m .. the wall's outer face)
    across                |t| <= 0.75                          (the clear opening half width)
    height                z in [ZLO, 2.49)                      (ZLO = WALL_TOP + 0.02; roof groups from the floor)
Groups checked: Roof, CeilTop (RoofCeil), L2..L5, PorchTop, WallsUp, Decal*, Lights above the wall top.  Geometry the
game hides at a doorway is left out: Upper_<seg>_* (WallsUp) and Decal_<seg>_* on the segments fx_doors.gd hides
(beta +- asin(1.76 / Rw); junction mouths asin(1.20 / Rw)).  Furniture (Interior, Tall) is the door-lane rule's.  Points are sampled on every triangle (<= 8 cm apart), so a large dome panel that crosses the volume
without a vertex in it still counts.
"""
from math import asin, acos, atan2, ceil, degrees, floor, hypot, sqrt

FLOOR_Z = 0.14
WALL_TOP = 1.40
DOOR_TOP = FLOOR_Z + 2.10
CLEAR = 0.25
Z_CLEAR = DOOR_TOP + CLEAR          # 2.49
IN_FROM_WALL = 0.38 + 1.50          # the inner jamb face + 1.5 m
OUT_FROM_WALL = 0.06
HALF_W = 0.75
HIDE_HW = 1.76                      # fx_doors.gd
JUNCTION_HW = 1.20
NSEG = 32
SEG = 360.0 / NSEG
STEP = 0.08

ROOF_GROUPS = ("Roof", "CeilTop", "L2", "L3", "L4", "L5", "DecalR", "PorchTop")


def _group(nm):
    import rooms_kit as K
    if nm.startswith("RoofCeil") or nm.startswith("CeilTop"):
        return "CeilTop"
    if nm.startswith("PorchTop_Part") or nm.startswith("PartTop"):
        return "PartTop"
    if K.floor_of(nm):
        return None                  # upper floors (doors are on the ground floor)
    return K.game_group(nm)


def _seg_of(nm, g):
    if g == "WallsUp":
        return int(nm[6:8])
    if g.startswith("Decal"):
        return int(nm[6:8])
    return None


def _free_angles(blocked):
    out = []
    for a in range(360):
        ok = True
        for a0, a1 in blocked or ():
            d0 = (a - a0) % 360.0
            if d0 <= (a1 - a0):
                ok = False
                break
        if ok:
            out.append(a)
    return out


def _hidden(beta, phi):
    k0 = int(floor((beta - phi) / SEG))
    k1 = int(floor((beta + phi) / SEG))
    return {k % NSEG for k in range(k0, k1 + 1)}


def _samples(tris):
    """tris: list of (a, b, c) 3-tuples; yields points <= STEP apart on each triangle."""
    for a, b, c in tris:
        e = max(hypot(hypot(a[0] - b[0], a[1] - b[1]), a[2] - b[2]),
                hypot(hypot(b[0] - c[0], b[1] - c[1]), b[2] - c[2]),
                hypot(hypot(c[0] - a[0], c[1] - a[1]), c[2] - a[2]))
        n = max(1, int(ceil(e / STEP)))
        for i in range(n + 1):
            for j in range(n + 1 - i):
                u, v = i / n, j / n
                w = 1.0 - u - v
                yield (a[0] * w + b[0] * u + c[0] * v, a[1] * w + b[1] * u + c[1] * v,
                       a[2] * w + b[2] * u + c[2] * v)


def check(objs, Rw, blocked=None, junction=False, z_clear=Z_CLEAR):
    """objs: {name: blender object} (world transforms applied through matrix_world).
    Returns (flags, info): info = {object: [hit points, min z, door angles hit]}."""
    s_lo, s_hi = Rw - IN_FROM_WALL, Rw + OUT_FROM_WALL
    phi = degrees(asin(min(0.99, (JUNCTION_HW if junction else HIDE_HW) / Rw)))
    free = set(_free_angles(blocked))
    hid = {b: _hidden(b, phi) for b in free}
    info = {}
    for nm, o in objs.items():
        if o.type != "MESH":
            continue
        if nm.startswith("RoofChamber"):
            continue                 # the airlock chamber walls (structure, door lanes)
        g = _group(nm)
        if g is None or not (g in ROOF_GROUPS or g in ("WallsUp", "Lights") or g.startswith("Decal")):
            continue                 # roof, ceiling, band and their lights only (furniture: door lanes, SIM)
        zlo = FLOOR_Z + 0.10 if g in ROOF_GROUPS else WALL_TOP + 0.02
        seg = _seg_of(nm, g)
        mw = o.matrix_world
        me = o.data
        me.calc_loop_triangles()
        vs = [tuple(mw @ v.co) for v in me.vertices]
        tris = []
        for lt in me.loop_triangles:
            p = [vs[i] for i in lt.vertices]
            if min(q[2] for q in p) >= z_clear or max(q[2] for q in p) < zlo:
                continue
            if max(hypot(q[0], q[1]) for q in p) < s_lo - 0.05:
                continue
            tris.append(p)
        if not tris:
            continue
        n_hit, zmin, angs = 0, 9.0, set()
        for x, y, z in _samples(tris):
            if z < zlo or z >= z_clear:
                continue
            r = hypot(x, y)
            if r < s_lo or r > s_hi:
                continue
            d1 = degrees(asin(min(1.0, HALF_W / r)))
            d2 = degrees(acos(min(1.0, s_lo / r)))
            dm = min(d1, d2)
            a = degrees(atan2(y, x)) % 360.0
            hit = False
            for b in range(int(floor(a - dm)), int(ceil(a + dm)) + 1):
                bb = b % 360
                if bb not in free:
                    continue
                dd = (a - bb + 180.0) % 360.0 - 180.0
                if abs(dd) > dm:
                    continue
                if seg is not None and seg in hid[bb]:
                    continue
                hit = True
                angs.add(bb)
            if hit:
                n_hit += 1
                zmin = min(zmin, z)
        if n_hit:
            info[nm] = [n_hit, round(zmin, 3), len(angs)]
    flags = []
    if info:
        worst = sorted(info.items(), key=lambda kv: kv[1][1])[:6]
        flags.append("doorway head room: %d objects below %.2f m in a door opening (+1.5 m): %s" %
                     (len(info), z_clear, ["%s z%.2f %ddeg" % (k, v[1], v[2]) for k, v in worst]))
    return flags, info
