"""Frontier Habitat 5.0 (docs/V5_DESIGN.md section 7) - ART-HAB: the exteriors of the new structures.

residence_tube  a half-cylinder vault lying along model X on a low drum (the housing family's own silhouette): ribs,
                glazed end walls, a glazed porch with a sloped canopy at each end (model 0 and 180 deg, where the
                porch doors are), low decks over the side segments (side links).  Variant (rm.variant):
                  family     small windows in every other bay
                  executive  ribbon windows in every bay, a lit ridge skylight, larger end glazing
                The house badge lies on the vault crown, turned to the game camera.
The round wall (Wall_00..31, 0..1.40 m) is the standard v3 wall, so doorways and the cutaway work as in every room.
Interiors: interior_v5.py.
"""
from math import sin, cos, radians, degrees, atan2, sqrt, pi, hypot

from mathutils import Vector

import rooms_kit as K
from rooms_kit import T, RY, RZ, WALL_TOP, reg_angles, columns, col_mid_fn, ang_diff, lamp
import rooms_identity as RI

TUBE_D = 2.55          # drum top / side-deck height
TUBE_B = 0.48          # vault radius as a share of the wall radius Rw
N_ARC = 16             # vault cross-section segments (half circle)


def tube_dims(rm):
    """(D, B, a, Rc): deck height, vault radius, vault half length, inner coping radius.  The vault foot corners
    (+-a, +-B) lie on the coping circle Rc."""
    Rw = rm.Rw
    D = TUBE_D
    B = TUBE_B * Rw
    Rc = Rw - 0.14
    a = sqrt(Rc * Rc - B * B)
    return D, B, a, Rc


def _face(p, pts, mat, want=None, smooth=False):
    """A planar face; reversed when its normal points away from `want`."""
    ids = [p.v(q) for q in pts]
    if want is not None:
        v = [Vector(q) for q in pts]
        n = (v[1] - v[0]).cross(v[2] - v[0])
        if n.dot(Vector(want)) < 0:
            ids.reverse()
    p.f(ids, mat, smooth)


def _arc(r, a0, a1, step=7.5):
    n = max(2, int(abs(a1 - a0) / step + 0.999))
    return [(r * cos(radians(a0 + (a1 - a0) * k / n)), r * sin(radians(a0 + (a1 - a0) * k / n))) for k in range(n + 1)]


def _drum(rm, D, th_c, glaze):
    """The drum from the wall top to the deck: HullDark with the family band; at the ends (|angle| < th_c from
    0 / 180) the porch glazing with mullions."""
    Rw = rm.Rw
    ro = rm.roof
    seams = []
    for c in (0.0, 180.0):
        n = 4
        for k in range(n + 1):
            seams.append(c - th_c + 2.0 * th_c * k / n)
    cols, kind, _ = columns(rm.seg * 2, seams, seam_w=degrees(0.07 / Rw))
    mid = col_mid_fn(cols)
    prof = [(Rw, WALL_TOP - 0.02), (Rw, 1.55), (Rw, glaze), (Rw, glaze + 0.04), (Rw, glaze + 0.26), (Rw, D),
            (Rw + 0.04, D), (Rw + 0.04, D + 0.14), (Rw - 0.12, D + 0.14), (Rw - 0.12, D + 0.02)]
    mats = ("HullDark", "GLASS", "HullDark", "Accent", "HullDark", "Frame", "Frame", "Frame", "Frame")

    def wm(k, i):
        if mats[k] == "GLASS":
            end = min(ang_diff(mid(i), 0.0), ang_diff(mid(i), 180.0)) < th_c
            return ("Frame" if kind[i] == "s" else "Window") if end else "HullDark"
        return mats[k]
    ro.lathe_a(prof, cols, wm, smooth=False)


def _decks(rm, D, B, a, Rc, th_c):
    """Flat HullDark decks over the two side segments (the porches have their own canopies)."""
    ro = rm.roof
    z = D + 0.02
    for sg in (1, -1):
        pts = [(x, sg * y) for (x, y) in _arc(Rc, th_c, 180.0 - th_c)]
        _face(ro, [(x, y, z) for x, y in pts], "HullDark", want=(0, 0, 1))
        # a Frame walk strip along the vault foot
        ro.box0(0.0, sg * (B + 0.35), z, 2 * a - 0.6, 0.30, 0.03, "Frame", mats={"-z": None})


def _porch(rm, D, B, a, Rc, th_c, sg, exe):
    """The porch canopy over the end segment (x beyond +-a): a ruled roof from a crest on the end wall down to
    the coping, lamps under its edge."""
    ro = rm.roof
    zc = D + (1.05 if exe else 0.85)
    n = 10
    rim, crest = [], []
    for k in range(n + 1):
        t = k / n
        y = B * (1.0 - 2.0 * t)
        phi = th_c * (1.0 - 2.0 * t)
        zr = D + 0.16
        zcr = D + 0.16 + (zc - D - 0.16) * (1.0 - (y / B) ** 2)
        rim.append((sg * Rc * cos(radians(phi)), Rc * sin(radians(phi)), zr))
        crest.append((sg * (a + 0.02), y, zcr))
    for k in range(n):
        _face(ro, [rim[k], rim[k + 1], crest[k + 1], crest[k]], "Hull", want=(sg * 0.5, 0, 1))
    # the canopy's lit front edge (a Frame fascia) and two lamps
    for k in range(n):
        p0, p1 = Vector(rim[k]), Vector(rim[k + 1])
        _face(ro, [p0, p1, p1 - Vector((0, 0, 0.12)), p0 - Vector((0, 0, 0.12))], "Frame", want=(sg, 0, 0))
    for yy in (-0.28 * B, 0.28 * B):
        x = sg * (sqrt(max(0.0, Rc * Rc - yy * yy)) - 0.35)
        lamp(ro, rm.porch, (x, yy, D + 0.10), (0, 0, -1), up=(sg, 0, 0), w=0.42, h=0.14, d=0.08, lens="Light")   # 2026-10-03: above door top + 0.25


def _ribs(a, B, badge_r, sign_skip=False):
    n = max(4, int(round(2 * a / 1.9)))
    xs = [-a + 2 * a * k / n for k in range(n + 1)]
    return xs


def _vault(rm, D, B, a, xs, exe, badge):
    """Skin (Hull, smooth) split at the ribs; windows as skin faces; Frame ribs proud of the skin."""
    ro = rm.roof
    bx, bth, br = badge                       # badge centre: x, arc angle (rad), radius (m along the skin)
    th = [pi * k / N_ARC for k in range(N_ARC + 1)]

    def pt(x, t, off=0.0):
        return (x, (B + off) * cos(t), D + (B + off) * sin(t))

    def under_badge(x0, x1, t0, t1):
        # any corner or the middle of the skin quad within the badge (+ a margin), measured on the skin
        for xx in (x0, 0.5 * (x0 + x1), x1):
            for tt in (t0, 0.5 * (t0 + t1), t1):
                if hypot(xx - bx, (tt - bth) * B) < br + 0.30:
                    return True
        return False

    for j in range(len(xs) - 1):
        x0, x1 = xs[j], xs[j + 1]
        for k in range(N_ARC):
            t0, t1 = th[k], th[k + 1]
            side = min(k, N_ARC - 1 - k)          # 0 at the foot, 7 at the crown
            m = "HullDark" if side == 0 else "Hull"   # critic 27 fix 4: a darker base band
            if not under_badge(x0, x1, t0, t1):
                if exe:
                    if side in (2, 3):
                        m = "Window"
                    elif side == 7 and j not in (0, len(xs) - 2):
                        m = "Window"
                else:
                    if side == 2 and j % 2 == 1:
                        m = "Window"
            # outward normal: order (x0,t0) (x0,t1) (x1,t1) (x1,t0)
            if exe and side == 1 and m == "Hull":
                m = "L5Gold"                      # critic 27 fix 5: the executive's second accent
            ro.f([ro.v(pt(x0, t0)), ro.v(pt(x0, t1)), ro.v(pt(x1, t1)), ro.v(pt(x1, t0))], m,
                 smooth=(m == "Hull"))
    # seam lines along the vault between the ribs (critic 27 fix 4)
    for j in range(len(xs) - 1):
        x0, x1 = xs[j] + 0.08, xs[j + 1] - 0.08
        for kk in (4, 12) + (() if exe else (8,)):
            t = th[kk]
            if under_badge(x0, x1, t - 0.02, t + 0.02):
                continue
            ro.beam(pt(x0, t, 0.012), pt(x1, t, 0.012), 0.05, 0.025, "Frame", up=(0, cos(t), sin(t)))
    if exe:
        # the lit ridge strip over the skylight, in PorchTop (reads at 250 m by night)
        for j in range(1, len(xs) - 2):
            x0, x1 = xs[j] + 0.1, xs[j + 1] - 0.1
            if under_badge(x0, x1, pi / 2 - 0.1, pi / 2 + 0.1):
                continue
            rm.porch.box((0.5 * (x0 + x1), 0.0, D + B + 0.03), (x1 - x0, 0.30, 0.03), "Light", mats={"-z": None})
    # window mullions: a thin Frame strip at mid-bay over each window band (reads as panes)
    # ribs: rectangular section swept along the arc; the end ribs heavier (the end-wall frames)
    for j, x in enumerate(xs):
        end = j in (0, len(xs) - 1)
        w = 0.26 if end else 0.14
        off = 0.10 if end else 0.07
        pts = []
        for k in range(N_ARC + 1):
            t = th[k]
            if not end and hypot(x - bx, (t - bth) * B) < br + 0.25:
                if len(pts) >= 2:
                    ro.beam_path(pts, w, off, "Frame", up=(1, 0, 0))
                pts = []
                continue
            pts.append(pt(x, t, off / 2))
        if len(pts) >= 2:
            ro.beam_path(pts, w, off, "Frame", up=(1, 0, 0))
    # the foot curbs
    for sg in (1, -1):
        ro.box0(0.0, sg * B, D, 2 * a + 0.2, 0.22, 0.16, "Frame", mats={"-z": None})


def _end_wall(rm, D, B, a, sg, exe):
    """Flat end wall at x = sg * a: Hull outer ring, glazed centre with radial mullions."""
    ro = rm.roof
    x = sg * (a - 0.02)
    rg = (0.72 if exe else 0.60) * B
    th = [pi * k / N_ARC for k in range(N_ARC + 1)]
    c = (x, 0.0, D)
    for k in range(N_ARC):
        t0, t1 = th[k], th[k + 1]
        o0 = (x, B * cos(t0), D + B * sin(t0))
        o1 = (x, B * cos(t1), D + B * sin(t1))
        i0 = (x, rg * cos(t0), D + rg * sin(t0))
        i1 = (x, rg * cos(t1), D + rg * sin(t1))
        _face(ro, [i0, o0, o1, i1], "Hull", want=(sg, 0, 0))
        _face(ro, [c, i0, i1], "Window", want=(sg, 0, 0))
    # mullions: a ring and radial bars, proud of the glass
    xm = x + sg * 0.05
    ring = [(xm, rg * cos(t), D + rg * sin(t)) for t in th]
    ro.beam_path(ring, 0.10, 0.12, "Frame", up=(1, 0, 0))
    for deg in ((30.0, 60.0, 90.0, 120.0, 150.0) if exe else (45.0, 90.0, 135.0)):
        t = radians(deg)
        ro.beam((xm, 0.0, D + 0.05), (xm, rg * cos(t), D + rg * sin(t)), 0.08, 0.10, "Frame")
    ro.beam((xm, -rg, D + 0.06), (xm, rg, D + 0.06), 0.12, 0.10, "Frame")
    for yy in (-0.84 * B, 0.84 * B):
        lamp(ro, rm.porch, (x + sg * 0.01, yy, D + 0.45), (sg, 0, 0), up=(0, 0, 1), w=0.40, h=0.22, d=0.10,
             lens="Light")


def wrap_badge(ro, family, bx, bth, br, D, Rr):
    """The family badge drawn flat (rooms_identity.badge) and wrapped onto the vault skin: flat x stays x, flat y is
    the arc length (toward -theta), flat z lifts off the skin."""
    tmp = K.P("tmp")
    RI.badge(tmp, family, 0.0, 0.0, br, lambda x, y: 0.0, lift=0.0)
    ids = []
    for v in tmp.verts:
        r = Rr + v.z
        t = bth - v.y / Rr
        ids.append(ro.v((bx + v.x, r * cos(t), D + r * sin(t))))
    for f, m in zip(tmp.faces, tmp.fmat):
        ro.f([ids[i] for i in f], m)


def _deck_details(rm, D, B, a, Rc, exe):
    """Family: skylights and vent units on the side decks.  Executive: a roof terrace on the -Y deck (wood deck,
    planters, loungers, a rail) and skylights on the +Y deck."""
    ro = rm.roof
    z = D + 0.02
    ym = 0.5 * (B + Rc)                            # middle of the side deck
    half = sqrt(max(0.0, Rc * Rc - (ym + 1.2) ** 2)) - 0.8
    for sg in (1, -1):
        if exe and sg < 0:
            _terrace(rm, D, B, Rc, z)
            continue
        # skylights (and on the family roof, vent units)
        n = max(2, int(2 * half / 3.4))
        for k in range(n):
            xx = -half + 2 * half * (k + 0.5) / n
            yy = sg * ym
            ro.box0(xx, yy, z, 1.5, 1.0, 0.22, "Frame", mats={"-z": None})
            ro.box0(xx, yy, z + 0.22, 1.3, 0.8, 0.02, "Window", mats={"-z": None})
            if k % 2 == 0 and not exe:
                ro.box0(xx + 1.35, yy + sg * 0.9, z, 0.6, 0.6, 0.45, "Hull", bevel=0.02)
                with ro.at(T(xx + 1.35, yy + sg * 0.9, 0.0)):
                    ro.cap_disc(0.2, z + 0.455, "HullDark", seg=10)


def _terrace(rm, D, B, Rc, z):
    """Executive roof terrace on the -Y deck (the side the game camera sees): wood deck to the coping, a pergola
    with slats over the middle, cushioned loungers, planters along the vault foot, bollard lamps, a rail.
    Everything in PorchTop: it hides with the roof in the cutaway and keeps the Roof group at <= 6 surfaces."""
    q = rm.porch
    y0, y1 = -(B + 0.30), -(Rc - 0.40)
    hx = sqrt(max(0.0, (Rc - 0.25) ** 2 - y1 * y1)) - 0.15
    hx0 = sqrt(max(0.0, (Rc - 0.25) ** 2 - y0 * y0)) - 0.6
    ym = 0.5 * (y0 + y1)
    # the deck: a trapezoid (wide at the vault foot, narrower at the coping), boards as Frame lines
    _face(q, [(-hx0, y0, z + 0.06), (hx0, y0, z + 0.06), (hx, y1, z + 0.06), (-hx, y1, z + 0.06)], "Wood",
          want=(0, 0, 1))
    nb = int(2 * hx0 / 0.55)
    for k in range(1, nb):
        xx = -hx0 + 2 * hx0 * k / nb
        xe_ = xx * (hx / hx0)
        _face(q, [(xx - 0.015, y0, z + 0.064), (xx + 0.015, y0, z + 0.064), (xe_ + 0.015, y1, z + 0.064),
                  (xe_ - 0.015, y1, z + 0.064)], "Frame", want=(0, 0, 1))
    # rail along the coping
    q.box0(0.0, y1, z + 0.06, 2 * hx, 0.05, 0.05, "Frame")
    q.box0(0.0, y1, z + 0.95, 2 * hx, 0.07, 0.05, "Frame")
    npost = int(2 * hx / 1.2) + 1
    for k in range(npost + 1):
        q.box0(-hx + 2 * hx * k / npost, y1, z + 0.06, 0.05, 0.05, 0.9, "Frame")
    # pergola over the middle
    pw, pd, ph = min(4.8, 1.2 * hx), abs(y1 - y0) - 0.9, 2.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            q.box0(sx * pw / 2, ym + sy * pd / 2, z + 0.06, 0.12, 0.12, ph, "Frame")
    for sy in (-1, 1):
        q.box0(0.0, ym + sy * pd / 2, z + ph - 0.06, pw + 0.3, 0.12, 0.16, "Frame")
    ns = int(pw / 0.35)
    for k in range(ns + 1):
        q.box0(-pw / 2 + pw * k / ns, ym, z + ph + 0.10, 0.06, pd + 0.4, 0.08, "Wood")
    # loungers under and beside the pergola, facing out; a low table
    for k, xx in enumerate((-pw / 2 - 1.1, -0.45, 0.45, pw / 2 + 1.1)):
        if abs(xx) + 0.4 > hx - 0.3:
            continue
        with q.at(T(xx, ym + 0.1, z + 0.06), RZ(90.0)):
            q.box0(0.0, 0.0, 0.0, 1.8, 0.64, 0.24, "Frame", bevel=0.02)
            q.box0(-0.10, 0.0, 0.24, 1.50, 0.58, 0.10, "Cushion", bevel=0.03)
            with q.at(T(0.62, 0.0, 0.30), RY(-35.0)):
                q.box0(0.0, 0.0, 0.0, 0.10, 0.58, 0.55, "Cushion", bevel=0.03)
    q.box0(0.0, ym - 1.0, z + 0.06, 0.8, 0.5, 0.40, "Wood", bevel=0.02)
    # planters along the vault foot
    np_ = max(2, int(2 * hx0 / 3.0))
    for k in range(np_):
        xx = -hx0 + 2 * hx0 * (k + 0.5) / np_
        q.box0(xx, y0 - 0.30, z + 0.06, 1.5, 0.50, 0.45, "Hull", bevel=0.02)
        for j in range(3):
            q.sphere((xx - 0.45 + 0.45 * j, y0 - 0.30, z + 0.60), 0.25, "Plant", seg=6, rings=3, smooth=False,
                     scale=(1, 1, 0.8))
    # bollard lamps along the rail
    for k in range(npost):
        xx = -hx + 2 * hx * (k + 0.5) / npost
        q.vcyl(xx, y1 + 0.25, z + 0.06, z + 0.62, 0.07, seg=8, mat="Frame")
        q.vcyl(xx, y1 + 0.25, z + 0.62, z + 0.72, 0.075, seg=8, mat="Light")


def build_residence_tube(rm):
    exe = getattr(rm, "variant", "family") == "executive"
    rm.levels = False
    rm.no_extras = True
    rm.build_base(lamps=(), bolts=rm.size >= 2)
    D, B, a, Rc = tube_dims(rm)
    th_c = degrees(atan2(B, a))
    rm.shell = "podium"
    rm.D = D
    rm.tube = dict(D=D, B=B, a=a, Rc=Rc)
    rm.porch = K.P("PorchTop")        # lamps, the lit ridge, the terrace: hidden with the roof in the cutaway
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [rm.porch]
    _drum(rm, D, th_c, glaze=2.16)
    _decks(rm, D, B, a, Rc, th_c)
    _deck_details(rm, D, B, a, Rc, exe)
    for sg in (1, -1):
        _porch(rm, D, B, a, Rc, th_c, sg, exe)
        _end_wall(rm, D, B, a, sg, exe)
    xs = _ribs(a, B, 0.0)
    # the badge on the crown, turned a little toward the game camera (-Y), wrapped round the vault without stretch
    br = min(0.30 * rm.Rw, 0.64 * B)
    bth = radians(90.0 + 16.0)
    _vault(rm, D, B, a, xs, exe, (0.0, bth, br))
    wrap_badge(rm.roof, "housing", 0.0, bth, br, D, B + 0.03)
    rm.badge_done = True
    # head room: the vault strip is tall inside
    rm.rooms_hi.append((lambda x, y, a=a, B=B: abs(x) < a - 0.2 and abs(y) < B - 0.4, D + 0.6 * B))
    rm.top_z = max(rm.top_z, D + B + 0.12)


BUILDERS = {
    "residence_tube": build_residence_tube,
}
