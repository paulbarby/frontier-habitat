"""
Frontier Habitat 2.0 - ART-B level-part kit and small shared parts for the exterior structures.

Upgrade language (AAA_DESIGN.md section 1), the same on every levelled exterior:
  L2  steel trim ring on the ground round the structure + a whip antenna
  L3  cyan band (L3Band) round the main element + an extra module (a small cabinet with a cyan stripe)
  L4  violet band (L4Band) + a side annex with radiator fins
  L5  gold crown ring (L5Gold) on the top of the main element + a beacon + a glowing emblem
Each part stays inside the footprint and reads alone and with the others.
"""
from math import sin, cos, pi, radians
from mathutils import Vector
from ext_common import Part, T, RX, RY, RZ, S


def trim_ring(p, r, z=0.0, w=0.14, h=0.10, seg=28):
    p.lathe([(r + w / 2, z), (r + w / 2, z + h), (r - w / 2, z + h), (r - w / 2, z)], "Trim", seg=seg, smooth=False)
    for k in range(4):                                     # four stubby posts on the ring
        a = radians(45 + 90 * k)
        p.vcyl(r * cos(a), r * sin(a), z + h, z + h + 0.22, 0.05, seg=6, mat="Trim", cap0=False)
        p.sphere((r * cos(a), r * sin(a), z + h + 0.25), 0.06, "Frame", seg=6, rings=3)


def antenna(p, x, y, z, h):
    p.vcyl(x, y, z, z + 0.12, 0.09, seg=6, mat="Frame")
    p.vcyl(x, y, z + 0.12, z + h, 0.028, 0.018, seg=4, mat="Trim", smooth=False)
    p.beam((x - 0.22, y, z + h * 0.72), (x + 0.22, y, z + h * 0.72), 0.03, 0.03, "Trim")
    p.beam((x, y - 0.16, z + h * 0.84), (x, y + 0.16, z + h * 0.84), 0.025, 0.025, "Trim")
    p.sphere((x, y, z + h + 0.03), 0.045, "Trim", seg=6, rings=3)


def band(p, spec, mat, dz=0.0):
    """spec = ('cyl', x, y, z, r, h) or ('box', cx, cy, z, sx, sy, h): a band 12 mm proud of the element"""
    if spec[0] == "cyl":
        _, x, y, z, r, h = spec
        with p.at(T(x, y, z + dz)):
            p.lathe([(r + 0.025, 0.0), (r + 0.025, h), (r - 0.01, h + 0.001)], mat, seg=20, smooth=True)
            p.lathe([(r - 0.01, -0.001), (r + 0.025, 0.0)], mat, seg=20, smooth=False)
    elif spec[0] == "xcyl":                                # ring round a horizontal cylinder along X
        _, x, y, z, r, w = spec
        with p.at(T(x + dz, y, z), RY(90.0)):
            p.lathe([(r + 0.025, -w / 2), (r + 0.025, w / 2), (r - 0.01, w / 2 + 0.001)], mat, seg=20, smooth=True)
            p.lathe([(r - 0.01, -w / 2 - 0.001), (r + 0.025, -w / 2)], mat, seg=20, smooth=False)
    else:
        _, cx, cy, z, sx, sy, h = spec
        p.box((cx, cy, z + dz + h / 2), (sx + 0.05, sy + 0.05, h), mat, mats={"+z": None, "-z": None})


def module(p, x, y, z, rot=0.0, s=1.0, stripe="L3Band"):
    """L3 extra module: a small cabinet on a plinth with a cyan stripe, a vent and a stub antenna"""
    with p.at(T(x, y, z), RZ(rot), S(s)):
        p.box0(0, 0, 0.0, 0.70, 0.56, 0.10, "Frame")
        p.box0(0, 0, 0.10, 0.62, 0.50, 0.66, "Hull", bevel=0.04)
        p.box((0, 0, 0.60), (0.645, 0.525, 0.07), stripe, mats={"+z": None, "-z": None})
        p.box((0.315, 0, 0.36), (0.02, 0.32, 0.26), "Frame", mats={"-x": None})
        for k in range(3):
            p.box((0.328, 0, 0.27 + 0.09 * k), (0.012, 0.30, 0.03), "Metal", mats={"-x": None})
        p.box0(0, 0, 0.76, 0.66, 0.54, 0.05, "HullDark")
        p.vcyl(-0.18, 0.14, 0.81, 1.05, 0.02, seg=4, mat="Trim", smooth=False)


def annex(p, x, y, z, rot=0.0, s=1.0, fins=5):
    """L4 side annex: a low cabinet with a violet stripe and a bank of radiator fins on top"""
    with p.at(T(x, y, z), RZ(rot), S(s)):
        p.box0(0, 0, 0.0, 0.92, 0.64, 0.08, "Frame")
        p.box0(0, 0, 0.08, 0.86, 0.58, 0.52, "HullDark", bevel=0.04)
        p.box((0, 0, 0.50), (0.885, 0.605, 0.06), "L4Band", mats={"+z": None, "-z": None})
        for k in range(fins):
            xk = -0.34 + 0.68 * k / max(1, fins - 1)
            p.box0(xk, 0, 0.60, 0.035, 0.54, 0.42, "Trim")
        p.box0(0, -0.26, 0.60, 0.80, 0.03, 0.08, "Frame")
        p.box0(0, 0.26, 0.60, 0.80, 0.03, 0.08, "Frame")


def fins(p, x, y, z, rot, n=5, length=0.8, height=0.5, gap=0.14):
    """a free-standing radiator fin bank (L4)"""
    with p.at(T(x, y, z), RZ(rot)):
        for k in range(n):
            yk = (k - (n - 1) / 2) * gap
            p.box0(0, yk, 0.0, length, 0.035, height, "Trim")
        p.box0(0, 0, height, length + 0.04, gap * (n - 1) + 0.08, 0.04, "Frame")


def crown(p, x, y, z, r, spikes=8, h=0.16):
    """L5 gold crown ring with small spikes"""
    with p.at(T(x, y, z)):
        p.lathe([(r + 0.05, 0.0), (r + 0.07, h * 0.5), (r + 0.05, h), (r - 0.03, h), (r - 0.03, 0.0)], "L5Gold", seg=24,
                smooth=False)
        for k in range(spikes):
            a = radians(360.0 * k / spikes + 22.5)
            c = Vector((r * cos(a), r * sin(a), h))
            w = 0.05 + r * 0.03
            pts = [c + Vector((w * cos(a + d), w * sin(a + d), 0.0)) for d in (0.0, pi / 2, pi, 3 * pi / 2)]
            tip = c + Vector((0, 0, 0.12 + r * 0.06))
            p.convex(pts + [tip], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)], "L5Gold")


def beacon(p, x, y, z, h=0.6):
    """L5 beacon: short mast, gold housing, white light dome"""
    p.vcyl(x, y, z, z + h, 0.035, seg=5, mat="Frame")
    p.vcyl(x, y, z + h, z + h + 0.10, 0.10, seg=10, mat="L5Gold")
    p.hemi((x, y, z + h + 0.10), 0.085, "Light", seg=10, rings=3)
    for k in range(3):
        a = radians(120 * k)
        p.beam((x, y, z + h + 0.10), (x + 0.11 * cos(a), y + 0.11 * sin(a), z + h + 0.22), 0.015, 0.015, "L5Gold")


def emblem(p, pos, normal, r=0.22):
    """L5 glowing emblem: a gold disc with a raised four-point star, facing `normal`"""
    n = Vector(normal).normalized()
    pos = Vector(pos)
    up = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    u = up.cross(n).normalized()
    v = n.cross(u).normalized()
    m = [[u.x, v.x, n.x, pos.x], [u.y, v.y, n.y, pos.y], [u.z, v.z, n.z, pos.z], [0, 0, 0, 1]]
    from mathutils import Matrix
    with p.at(Matrix(m)):
        p.cyl((0, 0, -0.02), (0, 0, 0.03), r, seg=12, mat="L5Gold", cap0=False)
        p.cyl((0, 0, 0.03), (0, 0, 0.045), r * 0.78, seg=12, mat="Frame", cap0=False)
        star = []
        for k in range(8):
            a = radians(45 * k)
            rr = r * (0.68 if k % 2 == 0 else 0.22)
            star.append((rr * cos(a), rr * sin(a)))
        p.prism(star, 0.045, 0.07, "L5Gold", cap0=False)


def add_levels(parts, LV):
    """LV: dict of anchors (see the module doc). Returns [L2, L3, L4, L5]."""
    L2, L3, L4, L5 = Part("L2"), Part("L3"), Part("L4"), Part("L5")
    if LV.get("ring"):
        r = LV["ring"]
        trim_ring(L2, r if not isinstance(r, tuple) else r[0], z=0.0 if not isinstance(r, tuple) else r[1])
    x, y, z, h = LV["antenna"]
    antenna(L2, x, y, z, h)
    band(L3, LV["band3"], "L3Band")
    for m in LV.get("modules", []):
        module(L3, *m)
    band(L4, LV["band4"], "L4Band")
    for a in LV.get("annex", []):
        annex(L4, *a)
    for f in LV.get("fins", []):
        fins(L4, *f)
    cx, cy, cz, cr = LV["crown"]
    crown(L5, cx, cy, cz, cr)
    bx, by, bz, bh = LV["beacon"]
    beacon(L5, bx, by, bz, bh)
    epos, enrm, er = LV["emblem"]
    emblem(L5, epos, enrm, er)
    return [L2, L3, L4, L5]


# ---------------------------------------------------------------------------------------------
# small shared parts
# ---------------------------------------------------------------------------------------------
def kiosk(p, x, y, z=0.0, rot=0.0, w=0.8, d=0.6, h=1.1, window=True, accent=True):
    """service / control cabinet: plinth, body, accent band, door, roof cap, status light"""
    with p.at(T(x, y, z), RZ(rot)):
        p.box0(0, 0, 0.0, w + 0.1, d + 0.1, 0.10, "Frame")
        p.box0(0, 0, 0.10, w, d, h, "Hull", bevel=0.05)
        if accent:
            p.box((0, 0, 0.10 + h * 0.78), (w + 0.025, d + 0.025, 0.12), "Accent", mats={"+z": None, "-z": None})
        p.box((w / 2 + 0.006, 0.0, 0.10 + h * 0.40), (0.012, d * 0.62, h * 0.62), "HullDark", mats={"-x": None})
        if window:
            p.box((w / 2 + 0.012, 0.0, 0.10 + h * 0.58), (0.012, d * 0.40, h * 0.14), "Window", mats={"-x": None})
        p.box0(0, 0, 0.10 + h, w + 0.06, d + 0.06, 0.06, "HullDark")
        p.box((w / 2 + 0.02, d * 0.36, 0.10 + h * 0.9), (0.04, 0.06, 0.05), "Light")


def pad(p, r, z=0.0, h=0.12, seg=24, mat="HullDark", edge="Frame", hazard=False):
    """round foundation pad"""
    p.lathe([(r, z - 0.05), (r, z + h - 0.03), (r - 0.04, z + h), (0.0, z + h)],
            lambda k, i: (edge if k < 2 else mat) if not (hazard and k == 0 and i % 2 == 0) else "Hazard", seg=seg,
            smooth=False)


def rect_pad(p, sx, sy, z=0.0, h=0.12, mat="HullDark", edge="Frame"):
    p.box0(0, 0, z - 0.05, sx, sy, h + 0.05, mat, mats={"-z": None, "+x": edge, "-x": edge, "+y": edge, "-y": edge})


def pipe_run(p, pts, r, mat="Metal", flange="Frame", fillet=0.15, seg=8):
    p.tube(pts, r, seg=seg, mat=mat, fillet=fillet)
    for q in (pts[0], pts[-1]):
        pass


def ladder(p, x, y, z0, z1, rot=0.0, w=0.44, mat="Hazard", rung="Metal"):
    with p.at(T(x, y, 0), RZ(rot)):
        for dy in (-w / 2, w / 2):
            p.beam((0, dy, z0), (0, dy, z1), 0.04, 0.04, mat)
        n = int((z1 - z0) / 0.32)
        for k in range(n):
            z = z0 + 0.25 + 0.32 * k
            p.beam((0, -w / 2, z), (0, w / 2, z), 0.03, 0.03, rung)


def railing(p, pts, h=0.9, post_every=1.0, mat="Hazard", post="Frame"):
    """handrail along a polyline (z of each point = walking level)"""
    tops = []
    pts = [Vector(q) for q in pts]
    for a, b in zip(pts[:-1], pts[1:]):
        L = (b - a).length
        n = max(1, int(L / post_every))
        for k in range(n):
            q = a.lerp(b, k / n)
            p.beam(q, q + Vector((0, 0, h)), 0.04, 0.04, post)
    p.beam(pts[-1], pts[-1] + Vector((0, 0, h)), 0.04, 0.04, post)
    p.beam_path([q + Vector((0, 0, h)) for q in pts], 0.04, 0.04, mat)
