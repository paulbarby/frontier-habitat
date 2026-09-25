"""
Frontier Habitat 3.1 - ART-NPC: visitor looks (docs/V3_1_DESIGN.md section 6.4).

A visitor is the colonist body (same rig, same meshes, same clips) with
  1. new colours for the material groups (the game replaces the albedo per body, as it does for the role colour), and
  2. one small skinned attachment mesh `Vis_<kind>` (drawn only for visitors of that kind, like `Head_N`).
The attachments go to their own files, assets/models/astronaut_visitor_suit.glb and astronaut_visitor_indoor.glb
(the rig plus the five `Vis_<kind>` meshes, no clips: the skeleton is identical, so the suit's baked clips drive them).

Looks (index = the visitor look number in the game's look code, see LOOK_NOTE):
  0 trader     orange body, grey shells and pack; utility belt with pouches / graphite work vest with hi-vis
               band and straps
  1-3 tourist  white body, bright accent (cyan, lime, magenta) on the hard shells; camera, pack pennant /
               camera, bag, sunglasses, gaiters and boots in the accent colour
  4 medical    white body, red pack and accents; red crosses / crosses, arm band, stethoscope
  5 science    blue body, white shells and pack; sensor mast / white lab jacket over the blue jumpsuit
  6 inspector  black body, gold accents; gold helmet crest, badge, reflective gold bands on the legs and pack /
               epaulettes, gold cords, badge and a black peaked cap with a gold band.  Indoor has two versions:
               Vis_inspector_h023 (closed cap, heads 0, 2, 3) and Vis_inspector_h1 (the bun rises through the crown)
"""
import os
import sys
from math import radians, degrees, sin, cos, pi, sqrt, atan2

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import npc_common as N                                           # noqa: E402
from npc_common import (SkinPart, Chain, frame_from, side_vec, torso_rule, arm_rule, leg_rule, tube_path,  # noqa
                        SH_JOINT, EL_JOINT, WR_JOINT, _UA, _FA, HIP_JOINT, KNEE_JOINT, ANKLE_JOINT)
from ext_common import T, S                                      # noqa: E402
from mathutils import Vector, Matrix                             # noqa: E402
import npc_suit as SU                                            # noqa: E402
import npc_indoor as IN                                          # noqa: E402

KINDS = ["trader", "tourist", "medical", "science", "inspector"]

# sRGB colours per look and material group.  suit groups: SuitMain (soft suit), SuitHard (HUT and helmet shells),
# Pack (pack, gloves, boots, chest box), SuitAccent (stripes, patches: the role colour on colonists).
# indoor groups: Jumpsuit, SuitAccent (shoulder panels, collar, cuffs, patches).
LOOKS = [
    dict(kind="trader", set=0,
         suit=dict(SuitMain="#D9702B", SuitHard="#7B828C", Pack="#5B626C", SuitAccent="#3E434A"),
         indoor=dict(Jumpsuit="#D9702B", SuitAccent="#5B626C")),
    dict(kind="tourist", set=0,
         suit=dict(SuitMain="#F3F1EA", SuitHard="#19C3DE", Pack="#F3F1EA", SuitAccent="#19C3DE"),
         indoor=dict(Jumpsuit="#F1EFE8", SuitAccent="#19C3DE")),
    dict(kind="tourist", set=1,
         suit=dict(SuitMain="#F3F1EA", SuitHard="#9BD62B", Pack="#F3F1EA", SuitAccent="#9BD62B"),
         indoor=dict(Jumpsuit="#F1EFE8", SuitAccent="#9BD62B")),
    dict(kind="tourist", set=2,
         suit=dict(SuitMain="#F3F1EA", SuitHard="#F0428C", Pack="#F3F1EA", SuitAccent="#F0428C"),
         indoor=dict(Jumpsuit="#F1EFE8", SuitAccent="#F0428C")),
    dict(kind="medical", set=0,
         suit=dict(SuitMain="#F4F5F7", SuitHard="#F4F5F7", Pack="#C62434", SuitAccent="#D7263D"),
         indoor=dict(Jumpsuit="#EEF0F3", SuitAccent="#D7263D")),
    dict(kind="science", set=0,
         suit=dict(SuitMain="#2F6BD0", SuitHard="#EEF1F5", Pack="#EEF1F5", SuitAccent="#EEF1F5"),
         indoor=dict(Jumpsuit="#2F6BD0", SuitAccent="#EEF1F5")),
    dict(kind="inspector", set=0,
         suit=dict(SuitMain="#2A2C31", SuitHard="#2A2C31", Pack="#1D1F23", SuitAccent="#D9A93A"),
         indoor=dict(Jumpsuit="#1F2125", SuitAccent="#D9A93A")),
]

LOOK_NOTE = ("look code = (8 + v) * 64 + head * 8 + tone for a visitor with look v (index into looks); colonists keep "
             "role * 64 + head * 8 + tone with role 0..7.  So look / 64 >= 8 means a visitor, v = look / 64 - 8.  "
             "Colour groups: replace the albedo of every surface whose material name is a key of looks[v].suit "
             "(suit model) or looks[v].indoor (indoor model) with that colour (linear values given), as the shader "
             "already does for SuitAccent (mode 1) and Skin (mode 2); colonists (role < 8) are unchanged.  "
             "Attachments: assets/models/astronaut_visitor_<variant>.glb holds skinned meshes Vis_<kind> on the same "
             "skeleton; draw Vis_<kind> only for visitors whose looks[v].kind is that kind (like Head_N).  A name "
             "that ends in _h<digits> (Vis_inspector_h023, Vis_inspector_h1) is also limited to those head numbers. "
             "Vis materials (VisRed, VisGold, VisGrey, VisWhite, VisDark and the shared names) are plain except "
             "SuitAccent, which takes the visitor's accent colour.")


def hex_lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [round((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4, 4) for x in c]


def palette_json():
    looks = []
    for i, L in enumerate(LOOKS):
        looks.append(dict(index=i, kind=L["kind"], set=L["set"], mesh="Vis_%s" % L["kind"],
                          suit=L["suit"], indoor=L["indoor"],
                          suit_linear={k: hex_lin(v) for k, v in L["suit"].items()},
                          indoor_linear={k: hex_lin(v) for k, v in L["indoor"].items()}))
    return dict(kinds=KINDS, looks=looks, look_code=LOOK_NOTE,
                files=dict(suit="astronaut_visitor_suit.glb", indoor="astronaut_visitor_indoor.glb"),
                meshes=dict(suit=["Vis_%s" % k for k in KINDS],
                            indoor=["Vis_%s" % k for k in KINDS if k != "inspector"] +
                            ["Vis_inspector_h023", "Vis_inspector_h1"]),
                note="Colonists keep their looks.  Tourists: pick the set (0..2) from a hash of the visitor id.  "
                     "Every head can be used for every visitor.")


# --------------------------------------------------------------------------------------
# geometry helpers
# --------------------------------------------------------------------------------------
def ring_at(rings, z):
    """(af, ab, b, n, x0) of a torso ring table [(z, af, ab, b, n, x0, ...)] at height z (linear)."""
    if z <= rings[0][0]:
        return tuple(rings[0][1:6])
    for a, b in zip(rings[:-1], rings[1:]):
        if a[0] <= z <= b[0]:
            t = (z - a[0]) / max(1e-9, b[0] - a[0])
            return tuple(a[i] + (b[i] - a[i]) * t for i in range(1, 6))
    return tuple(rings[-1][1:6])


def se_pt(af, ab, b, n, t):
    c, s = cos(t), sin(t)
    e = 2.0 / n
    x = (abs(c) ** e) * (af if c >= 0 else ab) * (1 if c >= 0 else -1)
    y = (abs(s) ** e) * b * (1 if s >= 0 else -1)
    return x, y


def surf_x(rings, z, y, front=True):
    """x of the torso surface at height z and side offset y (front or back)."""
    af, ab, b, n, x0 = ring_at(rings, z)
    q = min(0.999, abs(y) / b)
    k = (1.0 - q ** n) ** (1.0 / n)
    return x0 + (af * k if front else -ab * k)


def surf_normal(rings, z, y, front=True):
    """Horizontal outward normal of the torso ring at (z, y) (the rings are nearly vertical)."""
    af, ab, b, n, x0 = ring_at(rings, z)
    a = af if front else ab
    x = surf_x(rings, z, y, front) - x0
    gx = n * (abs(x) / a) ** (n - 1) / a * (1 if x >= 0 else -1)
    gy = n * (abs(y) / b) ** (n - 1) / b * (1 if y >= 0 else -1)
    return Vector((gx, gy, 0.0)).normalized()


def frame_matrix(nrm, up):
    """4x4 rotation whose local x = nrm (outward), z = up made perpendicular, y = z x x."""
    x = Vector(nrm).normalized()
    z = Vector(up) - x * Vector(up).dot(x)
    z.normalize()
    y = z.cross(x).normalized()
    return Matrix((x, y, z)).transposed().to_4x4()


def cross_mark(p, c, nrm, up, size, arm, mat, depth=0.004):
    """Flat cross (two bars) standing `depth` off a surface at c, facing nrm."""
    cc = Vector(c) + Vector(nrm).normalized() * (depth / 2 + 0.001)
    with p.at(T(*cc), frame_matrix(nrm, up)):
        p.box((0.0, 0.0, 0.0), (depth, size, arm), mat, mats={"-x": None})
        p.box((0.0005, 0.0, 0.0), (depth + 0.001, arm, size), mat, mats={"-x": None})


def plate(p, c, nrm, up, sy, sz, mat, depth=0.005):
    cc = Vector(c) + Vector(nrm).normalized() * (depth / 2 + 0.001)
    with p.at(T(*cc), frame_matrix(nrm, up)):
        p.box((0.0, 0.0, 0.0), (depth, sy, sz), mat, mats={"-x": None})


def strap(p, pts, ups, w, h, mat):
    """Flat band along pts; ups[i] = the band's normal (thickness direction) at pts[i]."""
    pts = [Vector(q) for q in pts]
    rings = []
    for i, q in enumerate(pts):
        t_in = (q - pts[i - 1]) if i > 0 else (pts[1] - q)
        t_out = (pts[i + 1] - q) if i < len(pts) - 1 else t_in
        t = (t_in.normalized() + t_out.normalized()).normalized()
        nv = Vector(ups[i]).normalized()
        u = nv.cross(t).normalized()                   # across the band
        v = t.cross(u).normalized()                    # thickness
        rings.append([tuple(q + u * (sx * w / 2) + v * (sv * h / 2)) for sx, sv in ((1, 1), (-1, 1), (-1, -1), (1, -1))])
    p.loft(rings, mat, False, closed=True, cap0=False, cap1=False)


def open_shell(p, rings, zs, offs, opens, mat, seg=14, edge_mat=None, hem=True, top_edge=True):
    """Garment shell over a torso ring table: rings at heights zs, `offs[k]` metres outside the body, open at the
    front by +-opens[k] degrees (a jacket or vest front).  Adds a turned-in edge on the front opening, the hem and
    the top edge so the cloth has a visible thickness."""
    edge_mat = edge_mat or mat
    ids, inner = [], []
    for z, off, op in zip(zs, offs, opens):
        af, ab, b, n, x0 = ring_at(rings, z)
        row, row_in = [], []
        for i in range(seg):
            t = radians(op) + (2 * pi - 2 * radians(op)) * i / (seg - 1)
            x, y = se_pt(af + off, ab + off, b + off, n, t)
            xi, yi = se_pt(af + 0.002, ab + 0.002, b + 0.002, n, t)
            row.append(p.v((x0 + x, y, z)))
            row_in.append((x0 + xi, yi, z))
        ids.append(row)
        inner.append(row_in)
    for k in range(len(zs) - 1):
        for i in range(seg - 1):
            p.f([ids[k][i], ids[k][i + 1], ids[k + 1][i + 1], ids[k + 1][i]], mat, True)
    # front edges (turned in towards the body)
    for k in range(len(zs) - 1):
        for i, sgn in ((0, 1), (seg - 1, -1)):
            a, b = ids[k][i], ids[k + 1][i]
            ai = p.v(inner[k][i])
            bi = p.v(inner[k + 1][i])
            f = [a, b, bi, ai] if sgn > 0 else [a, ai, bi, b]
            p.f(f, edge_mat, False)
    for k, on in ((0, hem), (len(zs) - 1, top_edge)):
        if not on:
            continue
        iv = [p.v(q) for q in inner[k]]
        for i in range(seg - 1):
            f = [ids[k][i], iv[i], iv[i + 1], ids[k][i + 1]]
            p.f(f if k == 0 else list(reversed(f)), edge_mat, False)


def neck_chest_rule(pelvis_thigh=0.5):
    """Torso rule on the body, the collar's chest -> neck blend above the neck base."""
    tr = torso_rule(pelvis_thigh=pelvis_thigh)
    ch = Chain(["chest", "neck"], [((0, 0, 1.49), (0, 0, 1), 0.02)])

    def rule(p):
        if p.z < 1.445:
            return tr(p)
        return ch(p)
    return rule


def hug_front(rings, pts_yz, clear):
    return [Vector((surf_x(rings, z, y) + clear, y, z)) for y, z in pts_yz]


def hug_back(rings, pts_yz, clear):
    return [Vector((surf_x(rings, z, y, front=False) - clear, y, z)) for y, z in pts_yz]


def neck_loop(r, z, a0, a1, n, sgn=1):
    """Points round the neck at radius r and height z from angle a0 to a1 (degrees, 0 = front, +y = left)."""
    out = []
    for k in range(n + 1):
        a = radians(a0 + (a1 - a0) * k / n)
        out.append(Vector((r * cos(a), r * sin(a), z)))
    return out


# --------------------------------------------------------------------------------------
# suit attachments (the suit Body is 6,839 triangles; each Vis_ stays <= 160 so Body + Vis <= 7,000)
# --------------------------------------------------------------------------------------
SR = SU.TORSO_RINGS


def suit_trader(p):
    """Utility belt round the waist bellows with three pouches."""
    with p.w(torso_rule()):
        seg = 12
        prof = [(1.040, 0.004), (1.047, 0.013), (1.073, 0.013), (1.080, 0.004)]
        ids = []
        for z, off in prof:
            af, ab, b, n, x0 = ring_at(SR, z)
            ids.append([p.v((x0 + x, y, z)) for x, y in
                        [se_pt(af + off, ab + off, b + off, n, 2 * pi * i / seg) for i in range(seg)]])
        for k in range(len(prof) - 1):
            for i in range(seg):
                j = (i + 1) % seg
                p.f([ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]], "Rubber", True)
        # pouches: left hip, two on the front
        yb = ring_at(SR, 1.06)[2] + 0.013
        # flat (2.2 cm) so it stays above the ground in the dead pose, which lies on the left hip
        p.box((0.0, yb + 0.011, 1.058), (0.11, 0.022, 0.085), "VisGrey", mats={"-y": None})
        p.box((0.0, yb + 0.023, 1.080), (0.11, 0.003, 0.028), "Rubber", mats={"-y": None})
        for y in (0.085, -0.075):
            x = surf_x(SR, 1.06, y) + 0.013
            p.box((x + 0.020, y, 1.056), (0.040, 0.070, 0.070), "VisGrey", mats={"-x": None})


def suit_tourist(p):
    """Compact camera on the stomach, its strap running up under the chest box; pennant on the pack antenna."""
    with p.w("chest"):
        x0 = surf_x(SR, 1.095, 0.0) + 0.004
        p.box((x0 + 0.0225, 0.0, 1.095), (0.045, 0.105, 0.065), "VisDark", mats={"-x": None})
        p.cyl((x0 + 0.045, 0.030, 1.098), (x0 + 0.070, 0.030, 1.098), 0.021, seg=10, mat="Trim", cap0=False)
        p.box((x0 + 0.046, -0.030, 1.115), (0.004, 0.022, 0.014), "Screen", mats={"-x": None})    # viewfinder
        for sy in (1, -1):
            p.tube([(x0 + 0.030, sy * 0.045, 1.126), (x0 + 0.052, sy * 0.066, 1.192)], 0.006, seg=4,
                   mat="SuitAccent", caps=False)
        # pennant (the tour group's colour) on the pack antenna: two single-sided faces, flat shaded
        a, b, c = Vector((-0.332, -0.17, 1.694)), Vector((-0.332, -0.17, 1.600)), Vector((-0.455, -0.17, 1.652))
        for side in (0, 1):
            ids = [p.v(q) for q in (a, b, c)]
            p.f(ids if side == 0 else list(reversed(ids)), "SuitAccent", False)


def suit_medical(p):
    """Red crosses: pack back, both helmet sides, right chest."""
    with p.w("chest"):
        cross_mark(p, (-0.4045, 0.0, 1.345), (-1, 0, 0), (0, 0, 1), 0.150, 0.046, "VisRed")
        z, y = 1.385, -0.112
        cross_mark(p, (surf_x(SR, z, y), y, z), surf_normal(SR, z, y), (0, 0, 1), 0.058, 0.019, "VisRed")
    with p.w("head"):
        for sy in (1, -1):
            az, lat = sy * 122.0, 20.0
            c = SU.helmet_pt(SU.HR, az, lat)
            a, l = radians(az), radians(lat)
            nrm = Vector((cos(l) * cos(a), cos(l) * sin(a) / 0.93, sin(l) / 1.10)).normalized()
            cross_mark(p, c, nrm, (0, 0, 1), 0.072, 0.024, "VisRed")


def suit_science(p):
    """Sensor mast on the pack: base, mast above the helmet, white sensor pod, green tip light."""
    with p.w("chest"):
        x, y = -0.270, 0.170
        p.cyl((x, y, 1.508), (x, y, 1.534), 0.018, seg=8, mat="Frame", cap0=False)
        p.cyl((x, y, 1.534), (x, y, 1.902), 0.007, seg=6, mat="Trim", cap0=False, cap1=False)
        p.sphere((x, y, 1.925), 0.028, "VisWhite", seg=8, rings=4, scale=(1.25, 1.0, 0.72))
        p.cyl((x, y, 1.942), (x, y, 1.958), 0.007, seg=6, mat="LightGreen", cap0=False)


def suit_inspector(p):
    """Gold crest along the helmet top, gold badge on the left chest; reflective gold bands round the thighs and
    shins and two stripes across the pack (they glow a little: the black suit reads at night)."""
    with p.w("head"):
        n = 6
        st = []
        for k in range(n + 1):
            lat = 46.0 + (150.0 - 46.0) * k / n
            az = 0.0 if lat <= 90.0 else 180.0
            ll = lat if lat <= 90.0 else 180.0 - lat
            base = SU.helmet_pt(SU.HR + 0.004, az, ll)
            rad = (base - SU.HC).normalized()
            hgt = 0.012 + 0.020 * sin(pi * k / n)
            st.append([p.v(base + Vector((0, sy * 0.0065, 0)) + rad * hh) for sy, hh in
                       ((1, 0.0), (1, hgt), (-1, hgt), (-1, 0.0))])
        for k in range(n):
            a, b = st[k], st[k + 1]
            p.f([a[0], b[0], b[1], a[1]], "VisGold", False)
            p.f([a[1], b[1], b[2], a[2]], "VisGold", False)
            p.f([a[2], b[2], b[3], a[3]], "VisGold", False)
        p.f([st[0][3], st[0][2], st[0][1], st[0][0]], "VisGold", False)
        p.f([st[-1][0], st[-1][1], st[-1][2], st[-1][3]], "VisGold", False)
    with p.w("chest"):
        z, y = 1.420, 0.078
        plate(p, (surf_x(SR, z, y), y, z), surf_normal(SR, z, y) + Vector((0, 0, 0.35)), (0, 0, 1), 0.040, 0.046,
              "VisGold", depth=0.006)
    with p.w("chest"):
        for z in (1.300, 1.035):
            plate(p, (-0.4045, 0.0, z), (-1, 0, 0), (0, 0, 1), 0.300, 0.024, "VisGoldReflect", depth=0.004)
    for s in ("L", "R"):
        hip, kn, an = side_vec(HIP_JOINT, s), side_vec(KNEE_JOINT, s), side_vec(ANKLE_JOINT, s)
        th, shd = (kn - hip).normalized(), (an - kn).normalized()
        with p.w(leg_rule(s)):
            for c, d, r in ((hip + th * 0.13 + Vector((-0.002, 0, 0)), th, 0.107),
                            (kn + shd * 0.14 + Vector((-0.007, 0, 0)), shd, 0.089)):
                p.cyl(tuple(c - d * 0.015), tuple(c + d * 0.015), r, seg=10, mat="VisGoldReflect", cap0=False,
                      cap1=False)


# --------------------------------------------------------------------------------------
# indoor attachments (one colonist shows Body 3,356 + one head <= 708; each Vis_ stays <= 600)
# --------------------------------------------------------------------------------------
IR = IN.TORSO


def indoor_trader(p):
    """Grey work vest (open front, turned-in edges), shoulder straps, two lower pockets."""
    with p.w(torso_rule(pelvis_thigh=0.5)):
        zs = [1.035, 1.090, 1.170, 1.260, 1.330]
        open_shell(p, IR, zs, [0.008, 0.012, 0.013, 0.013, 0.012], [9, 9, 10, 12, 14], "VisGraphite", seg=16)
        # hi-vis band round the vest (critic round 12: the trader must not read as an orange-role colonist)
        open_shell(p, IR, [1.150, 1.205], [0.0165, 0.0165], [10, 11], "VisHiVis", seg=16)
        for sy in (1, -1):
            y = sy * 0.112
            front = hug_front(IR, [(y, 1.326), (y, 1.380), (y, 1.425)], 0.013)
            back = hug_back(IR, [(y, 1.425), (y, 1.380), (y, 1.326)], 0.013)
            top = [Vector((0.035, y, 1.466)), Vector((-0.035, y, 1.466))]
            pts = front + top + back
            ups = [surf_normal(IR, q.z, y, q.x > 0) if q.z < 1.44 else Vector((0.0, 0.0, 1.0)) for q in pts]
            ups = [(u + Vector((0, 0, 0.6 if q.z > 1.40 else 0.0))).normalized() for u, q in zip(ups, pts)]
            strap(p, pts, ups, 0.032, 0.006, "VisHiVis")
        for y in (0.085, -0.085):
            z = 1.095
            x = surf_x(IR, z, y) + 0.012
            p.box((x + 0.010, y, z), (0.020, 0.075, 0.080), "VisDark", mats={"-x": None})
            p.box((x + 0.021, y, z + 0.034), (0.004, 0.077, 0.018), "VisGraphite", mats={"-x": None})


def indoor_tourist(p):
    """Camera on a bright neck strap, a bag on the right hip with a strap across the body, sunglasses."""
    with p.w("chest"):
        x0 = surf_x(IR, 1.160, 0.0) + 0.006
        p.box((x0 + 0.0225, 0.0, 1.160), (0.045, 0.100, 0.062), "VisDark", mats={"-x": None})
        p.cyl((x0 + 0.045, 0.028, 1.162), (x0 + 0.068, 0.028, 1.162), 0.020, seg=10, mat="Trim", cap0=False)
    with p.w(neck_chest_rule()):
        yl = [0.046, 0.066, 0.078, 0.086]
        zl = [1.190, 1.280, 1.360, 1.420]
        left = hug_front(IR, list(zip(yl, zl)), 0.010)
        right = hug_front(IR, list(zip([-y for y in reversed(yl)], list(reversed(zl)))), 0.010)
        loop = neck_loop(0.096, 1.468, 40.0, 320.0, 7)
        pts = [Vector((x0 + 0.030, 0.046, 1.180))] + left + loop + right + [Vector((x0 + 0.030, -0.046, 1.180))]
        p.tube(pts, 0.006, seg=4, mat="SuitAccent", caps=False)
    with p.w(torso_rule(pelvis_thigh=0.5)):
        # bag on the right hip
        yb = -(ring_at(IR, 0.97)[2] + 0.004)
        p.box((0.020, yb - 0.026, 0.955), (0.110, 0.050, 0.105), "SuitAccent", mats={"+y": None})
        p.box((0.020, yb - 0.052, 0.985), (0.112, 0.004, 0.050), "VisDark", mats={"+y": None})
        # bag strap: from the bag over the chest to the left shoulder and down the back
        f = hug_front(IR, [(-0.150, 1.040), (-0.100, 1.110), (-0.020, 1.220), (0.050, 1.320), (0.110, 1.400)], 0.012)
        top = [Vector((0.060, 0.132, 1.452)), Vector((0.000, 0.140, 1.466)), Vector((-0.060, 0.132, 1.452))]
        b = hug_back(IR, [(0.110, 1.400), (0.050, 1.320), (-0.030, 1.210), (-0.100, 1.110), (-0.150, 1.040)], 0.012)
        pts = [Vector((0.050, -0.172, 1.005))] + f + top + b + [Vector((-0.020, -0.172, 1.005))]
        p.tube(pts, 0.007, seg=4, mat="VisDark", caps=False)
    for s in ("L", "R"):
        tourist_legs(p, s)
    with p.w(IN.head_rule()):
        for sy in (1, -1):
            c = IN.head_pt(3.0, sy * 25.0, 1.075)
            p.sphere(tuple(c), 0.021, "VisDark", seg=8, rings=3, scale=(0.30, 1.05, 0.72))
        a, b = IN.head_pt(4.5, 12.0, 1.07), IN.head_pt(4.5, -12.0, 1.07)
        p.beam(tuple(a), tuple(b), 0.004, 0.004, "VisDark", up=(1, 0, 0), caps=False)
        for sy in (1, -1):
            a, b = IN.head_pt(4.0, sy * 36.0, 1.06), IN.head_pt(5.0, sy * 78.0, 1.03)
            p.beam(tuple(a), tuple(b), 0.004, 0.004, "VisDark", up=(0, 0, 1), caps=False)


def tourist_legs(p, s):
    """Gaiters from below the knee pad over the ankle, and hiking boots, in the tour colour (SuitAccent): at 30 px
    the tourist then differs from the scientist (critic round 12)."""
    hip, kn, an = side_vec(HIP_JOINT, s), side_vec(KNEE_JOINT, s), side_vec(ANKLE_JOINT, s)
    s_kn = (kn - hip).length
    s_an = s_kn + (an - kn).length
    st = [
        (s_kn + 0.118, 0.058, 0.058, "SuitAccent"),
        (s_kn + 0.126, 0.071, 0.071, "SuitAccent"),
        (s_kn + 0.220, 0.064, 0.064, "SuitAccent"),
        (s_an - 0.090, 0.069, 0.069, "SuitAccent"),
        (s_an - 0.030, 0.076, 0.076, "SuitAccent"),
        (s_an - 0.012, 0.075, 0.075, "SuitAccent"),
    ]
    with p.w(leg_rule(s)):
        tube_path(p, [hip, kn, an], st, seg=10, ref=(1, 0, 0))
    boot_cover(p, s)


def boot_cover(p, s, k=1.035, scale_w=0.84, top_scale=0.78):
    """The upper of the indoor boot (npc_suit.build_boot sections), 3.5 % larger round the ankle, in the tour colour.
    Weights are taken at the unscaled point, so the cover bends exactly like the boot under it."""
    sy = 1.0 if s == "L" else -1.0
    y0 = ANKLE_JOINT.y * sy
    cx = ANKLE_JOINT.x + 0.05
    lr = leg_rule(s)

    def rule(q):
        return lr(Vector((cx + (q.x - cx) / k, y0 + (q.y - y0) / k, q.z / k)))

    def sc(q):
        return (cx + (q[0] - cx) * k, y0 + (q[1] - y0) * k, q[2] * k)
    sec = [(-0.100, 0.050, 0.175), (-0.070, 0.058, 0.205), (-0.020, 0.062, 0.215), (0.030, 0.063, 0.170),
           (0.080, 0.066, 0.130), (0.120, 0.066, 0.108), (0.160, 0.060, 0.092), (0.190, 0.048, 0.078),
           (0.207, 0.030, 0.064)]
    n = 8
    with p.w(rule):
        ids = []
        for (x, hw, top) in sec:
            top = 0.046 + (top - 0.046) * top_scale
            ids.append([p.v(sc((x, y0 + cos(pi * i / n) * hw * scale_w * sy, 0.046 + sin(pi * i / n) * (top - 0.046))))
                        for i in range(n + 1)])
        for kk in range(len(ids) - 1):
            for i in range(n):
                f = [ids[kk][i], ids[kk][i + 1], ids[kk + 1][i + 1], ids[kk + 1][i]]
                p.f(f if sy > 0 else list(reversed(f)), "SuitAccent", True)
        capf, capt = list(reversed(ids[0])), list(ids[-1])
        if sy < 0:
            capf.reverse()
            capt.reverse()
        p.f(capf, "SuitAccent", False)
        p.f(capt, "SuitAccent", False)


def indoor_medical(p):
    """Red cross on the back and the right chest, red arm band (left), stethoscope round the neck."""
    with p.w(torso_rule(pelvis_thigh=0.5)):
        z = 1.285
        cross_mark(p, (surf_x(IR, z, 0.0, front=False), 0.0, z), (-1, 0, 0), (0, 0, 1), 0.130, 0.042, "VisRed")
        z, y = 1.345, -0.085
        cross_mark(p, (surf_x(IR, z, y), y, z), surf_normal(IR, z, y), (0, 0, 1), 0.052, 0.017, "VisRed")
    s = "L"
    sh = side_vec(SH_JOINT, s)
    ua = side_vec(_UA, s)
    with p.w(arm_rule(s)):
        p.cyl(tuple(sh + ua * 0.105), tuple(sh + ua * 0.160), 0.0725, 0.0685, seg=10, mat="VisRed", cap0=False,
              cap1=False)
    with p.w(neck_chest_rule()):
        yl = [0.060, 0.072, 0.080]
        zl = [1.300, 1.370, 1.425]
        left = hug_front(IR, list(zip(yl, zl)), 0.009)
        right = hug_front(IR, list(zip([-y for y in reversed(yl)], list(reversed(zl)))), 0.009)
        loop = neck_loop(0.095, 1.470, 42.0, 318.0, 7)
        p.tube(left[::-1][::-1] + loop + right, 0.0055, seg=4, mat="Frame", caps=False)
    with p.w(torso_rule(pelvis_thigh=0.5)):
        z, y = 1.290, -0.060
        c = Vector((surf_x(IR, z, y), y, z))
        nrm = surf_normal(IR, z, y)
        p.cyl(tuple(c + nrm * 0.001), tuple(c + nrm * 0.012), 0.017, seg=10, mat="Trim", cap0=False)


def indoor_science(p):
    """White lab jacket over the blue jumpsuit: open V front, sleeves to above the wrist unit, chest pocket with
    two pens, badge."""
    with p.w(torso_rule(pelvis_thigh=0.5)):
        zs = [0.955, 1.000, 1.090, 1.170, 1.260, 1.340, 1.400, 1.440, 1.466]
        offs = [0.014, 0.020, 0.015, 0.016, 0.016, 0.016, 0.014, 0.012, 0.010]
        opens = [7, 7, 7, 8, 11, 16, 24, 34, 44]
        open_shell(p, IR, zs, offs, opens, "VisWhite", seg=14, top_edge=False)
        z, y = 1.245, 0.088
        x = surf_x(IR, z, y) + 0.016
        nrm = surf_normal(IR, z, y)
        plate(p, (x, y, z), nrm, (0, 0, 1), 0.066, 0.070, "VisWhite", depth=0.006)
        for dy in (0.012, 0.026):
            a = Vector((x + 0.009, y + dy, z + 0.020))
            p.beam(tuple(a), tuple(a + Vector((0, 0, 0.040))), 0.006, 0.006, "Frame" if dy < 0.02 else "SuitAccent",
                   caps=True)
        z, y = 1.300, -0.090
        plate(p, (surf_x(IR, z, y) + 0.016, y, z), surf_normal(IR, z, y), (0, 0, 1), 0.040, 0.050, "Screen",
              depth=0.004)
    for s in ("L", "R"):
        sh, el, wr = side_vec(SH_JOINT, s), side_vec(EL_JOINT, s), side_vec(WR_JOINT, s)
        ua = side_vec(_UA, s)
        pts = [sh - ua * 0.05, sh, el, wr]
        s0 = 0.05
        s_el = s0 + (el - sh).length
        s_wr = s_el + (wr - el).length
        d = 0.012
        st = [
            (0.030, 0.050 + d, 0.052 + d, "VisWhite"),
            (s0 + 0.010, 0.072 + d, 0.074 + d, "VisWhite"),
            (s0 + 0.070, 0.066 + d, 0.068 + d, "VisWhite"),
            (s0 + 0.170, 0.057 + d, 0.059 + d, "VisWhite"),
            (s_el - 0.030, 0.051 + d, 0.052 + d, "VisWhite"),
            (s_el + 0.010, 0.050 + d, 0.050 + d, "VisWhite"),
            (s_el + 0.070, 0.051 + d, 0.050 + d, "VisWhite"),
            (s_wr - 0.118, 0.047 + d, 0.047 + d, "VisWhite"),
            (s_wr - 0.112, 0.047, 0.047, "VisWhite"),
        ]
        with p.w(arm_rule(s)):
            tube_path(p, pts, st, seg=8, ref=(1, 0, 0))


def indoor_inspector(p):
    """Epaulettes (black boards, gold bars and fringe), gold cords from the right shoulder, gold badge."""
    with p.w(torso_rule(pelvis_thigh=0.5)):
        for sy in (1, -1):
            yc = 0.132
            ang = radians(20.7)
            slope = Vector((0.0, sy * cos(ang), -sin(ang)))
            nrm = Vector((0.0, sy * sin(ang), cos(ang)))
            c = Vector((0.0, sy * yc, 1.462)) + nrm * 0.006
            M = Matrix((Vector((1, 0, 0)), slope, nrm)).transposed().to_4x4()
            with p.at(T(*c), M):
                p.box((0.0, 0.0, 0.0), (0.085, 0.068, 0.010), "VisDark", mats={"-z": None})
                for dx in (-0.018, 0.018):
                    p.box((dx, 0.004, 0.0065), (0.010, 0.050, 0.003), "VisGold", mats={"-z": None})
                p.box((0.0, 0.036, -0.010), (0.085, 0.006, 0.024), "VisGold", mats={"-y": None})
        for k, (yy, zz) in enumerate(((-0.040, 1.268), (-0.020, 1.228))):
            f = hug_front(IR, [(-0.122, 1.452), (-0.118, 1.400), (-0.100, 1.335), (-0.070, zz + 0.020), (yy, zz)],
                          0.010 + 0.003 * k)
            f[0] = Vector((0.050, -0.122, 1.462))
            p.tube(f, 0.0042, seg=4, mat="VisGold", caps=False)
        z, y = 1.335, 0.090
        plate(p, (surf_x(IR, z, y), y, z), surf_normal(IR, z, y), (0, 0, 1), 0.036, 0.042, "VisGold", depth=0.006)
    with p.w(IN.head_rule()):
        service_cap(p, bun=getattr(p, "bun", False))


def service_cap(p, bun=False):
    """Black peaked cap with a gold band and badge: the inspector's head reads apart from a colonist at 30 px.
    bun=False: closed crown (clears the crop, the bob and the ponytail, heads 0, 2, 3).  bun=True: the crown top is
    a ring round the high bun of head 1, which rises through it (with a turned-down lip)."""
    c = IN.HCI
    seg = 14
    rings = [(0.028, 0.119, 0.107), (0.056, 0.122, 0.108), (0.110, 0.136, 0.122), (0.146, 0.138, 0.124)]

    def ring(dz, a, b, grow=0.0):
        return [p.v(c + Vector(((a + grow) * cos(2 * pi * i / seg), (b + grow) * sin(2 * pi * i / seg), dz)))
                for i in range(seg)]
    ids = [ring(*r) for r in rings]
    for k in range(len(ids) - 1):
        for i in range(seg):
            j = (i + 1) % seg
            p.f([ids[k][i], ids[k][j], ids[k + 1][j], ids[k + 1][i]], "VisDark", True)
    if not bun:
        top = p.v(c + Vector((0.0, 0.0, 0.152)))
        for i in range(seg):
            j = (i + 1) % seg
            p.f([ids[-1][i], ids[-1][j], top], "VisDark", True)
    else:
        bc = IN.head_pt(74, 180, 1.0) + Vector((0.012, 0.0, 0.055)) - c        # bun centre, head 1
        hole = [p.v(c + Vector((bc.x + 0.060 * cos(2 * pi * i / seg), 0.060 * sin(2 * pi * i / seg), 0.150)))
                for i in range(seg)]
        lip = [p.v(c + Vector((bc.x + 0.057 * cos(2 * pi * i / seg), 0.057 * sin(2 * pi * i / seg), 0.138)))
               for i in range(seg)]
        for i in range(seg):
            j = (i + 1) % seg
            p.f([ids[-1][i], ids[-1][j], hole[j], hole[i]], "VisDark", True)
            p.f([hole[i], hole[j], lip[j], lip[i]], "VisDark", True)
    # gold band over the lower crown
    b0, b1 = ring(0.034, 0.1195, 0.1075, 0.003), ring(0.052, 0.1215, 0.108, 0.003)
    for i in range(seg):
        j = (i + 1) % seg
        p.f([b0[i], b0[j], b1[j], b1[i]], "VisGold", True)
    # peak: a curved plate in front, both sides
    n = 6
    inner, outer = [], []
    for k in range(n + 1):
        a = radians(-68.0 + 136.0 * k / n)
        d = Vector((cos(a), sin(a), 0.0))
        inner.append(c + Vector((0.119 * cos(a), 0.107 * sin(a), 0.026)))
        outer.append(c + Vector((0.119 * cos(a), 0.107 * sin(a), 0.026)) + d * (0.058 * cos(a) ** 0.5) +
                     Vector((0, 0, -0.014 * cos(a))))
    for side in (0, 1):
        vi = [p.v(q + Vector((0, 0, 0.002 if side == 0 else -0.002))) for q in inner]
        vo = [p.v(q + Vector((0, 0, 0.002 if side == 0 else -0.002))) for q in outer]
        for k in range(n):
            f = [vi[k], vo[k], vo[k + 1], vi[k + 1]]
            p.f(f if side == 1 else list(reversed(f)), "VisDark", False)
    # badge on the front of the crown
    a = c + Vector((0.130, 0.0, 0.085))
    with p.at(T(*a), frame_matrix((0.97, 0.0, 0.25), (0, 0, 1))):
        p.box((0.0, 0.0, 0.0), (0.006, 0.030, 0.026), "VisGold", mats={"-x": None})


SUIT_BUILD = dict(trader=suit_trader, tourist=suit_tourist, medical=suit_medical, science=suit_science,
                  inspector=suit_inspector)
INDOOR_BUILD = dict(trader=indoor_trader, tourist=indoor_tourist, medical=indoor_medical, science=indoor_science,
                    inspector=indoor_inspector)


def build_visitor_parts(variant):
    table = SUIT_BUILD if variant == "suit" else INDOOR_BUILD
    parts = []
    for k in KINDS:
        if variant == "indoor" and k == "inspector":
            for name, bun in (("Vis_inspector_h023", False), ("Vis_inspector_h1", True)):
                p = SkinPart(name)
                p.bun = bun
                table[k](p)
                parts.append(p)
            continue
        p = SkinPart("Vis_%s" % k)
        table[k](p)
        parts.append(p)
    print("    visitor attachments:", {p.name: sum(len(f) - 2 for f in p.faces) for p in parts})
    return parts
