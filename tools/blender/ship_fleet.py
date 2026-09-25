"""
Frontier Habitat 3.1 - the other five ships (V3_1 §6.2, critic round 9 fleet table): shuttle, liner, medical,
science, courier. Same fleet language as ship_trader (faceted cockpit with dark glass, panel insets, hazard
frames, rails, heavy legs, bells with glowing cones, nav lights, registration); a different plan and colour each.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ship_fleet.py -- [--only shuttle,liner]
Output: assets/models/ship_<kind>.glb (contract in tools/blender/ship_common.py).
"""
import os
import sys
from math import sin, cos, pi, radians, degrees, atan2, atan, sqrt, asin

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ship_common as SC                                   # noqa: E402
from ship_common import Part, Anchor, Anim, LoftHull, T, RX, RY, RZ, S, place_frame, panel, patch   # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402

HULL, DARK, GRAPH = "Palette:Hull", "Palette:HullDark", "Palette:Frame"
RUB, HAZ = "Palette:Rubber", "Palette:Hazard"
FRAME, METAL, TRIM = "PaletteMetal:Frame", "PaletteMetal:Metal", "PaletteMetal:Trim"


# ======================================================================================
# shared helpers for the fleet
# ======================================================================================
def matfn(seams=(), panel_xb=(), panel_tb=(0, 45, 90, 135, 180), zones=(), top=HULL, alt="Palette:#c8cdd4",
          belly=GRAPH, seam_mat=DARK):
    """zones: [(t0, t1, x0, x1, mat)] painted areas, first match wins"""
    def f(xa, xb, ta, tb):
        xm, tm = (xa + xb) / 2, (ta + tb) / 2
        if tm > 180:
            return belly
        for (t0, t1, x0, x1, m) in zones:
            if t0 <= tm <= t1 and x0 <= xm <= x1:
                return m
        for s in seams:
            if abs(xm - s) < 0.06 and 5 < tm < 175:
                return seam_mat
        i = sum(1 for b in panel_xb if xm > b)
        j = sum(1 for b in panel_tb if tm > b)
        return alt if (i * 7 + j * 3) % 3 == 0 else top
    return f


def rings_x(x0, x1, step, extra=()):
    n = max(2, int(round((x1 - x0) / step)))
    xs = [x0 + (x1 - x0) * k / n for k in range(n + 1)] + list(extra)
    for s in extra:
        xs += [s - 0.06, s + 0.06]
    return sorted(set(round(x, 3) for x in xs if x0 <= x <= x1))


def ribs(h, H, xs, ts):
    for xr in xs:
        rr = [[H.pt(xr + dx, t, off) for t in ts] for dx, off in ((-0.14, 0.0), (-0.1, 0.05), (0.1, 0.05), (0.14, 0.0))]
        h.loft(rr, lambda k, i: DARK if ts[i] < 180 else GRAPH, smooth=True, closed=True)


def window_band(h, lt, H, x0, x1, t0, t1, every=0.75, mat="CabinWindow"):
    """a continuous window row: dark glass by day, lit panes in Lights (CabinWindow; Window for a bridge), mullions"""
    panel(h, H, x0, x1, t0, t1, 0.03, SC.DGLASS, side=FRAME, nx=max(2, int((x1 - x0) / 1.5)), nt=1)
    n = max(1, int(round((x1 - x0) / every)))
    for k in range(n + 1):
        x = x0 + (x1 - x0) * k / n
        h.beam(H.pt(x, t0, 0.04), H.pt(x, t1, 0.04), 0.07, 0.05, FRAME, up=tuple(H.nrm(x, (t0 + t1) / 2)))
    for k in range(n):
        xa, xb = x0 + (x1 - x0) * k / n + 0.06, x0 + (x1 - x0) * (k + 1) / n - 0.06
        patch(lt, H, xa, xb, t0 + 0.6, t1 - 0.6, 0.05, mat, nx=1, nt=1, smooth=False)
    tw, xw = H.t_scale((x0 + x1) / 2, t0)
    for (ta, tb) in ((t0 - 0.06 / tw, t0), (t1, t1 + 0.06 / tw)):
        panel(h, H, x0 - 0.05, x1 + 0.05, ta, tb, 0.05, FRAME, side=FRAME, nx=2, nt=1)


def gull_door(name, h, H, x0, x1, zt, zb, side, open_deg=100.0):
    """top-hinged hatch on the flank (side -1 = -Y); opening patch + hazard frame on the hull"""
    xc = (x0 + x1) / 2
    y = side * (H.sec(xc)[0] + 0.02)
    a = Anim(name, place_frame(Vector((xc, y, zt)), 90.0 if side > 0 else -90.0), -open_deg)
    w, hh, t = x1 - x0, zt - zb, 0.08
    with a.at(RX(open_deg)):
        a.box((0, t / 2, -hh / 2), (w, t, hh), HULL, mats={"+y": DARK})
        a.box((0, -0.005, -hh * 0.5), (w * 0.94, 0.012, 0.1), "Accent")
        a.box((0, -0.006, -hh * 0.78), (w * 0.4, 0.012, 0.22), SC.DGLASS)
        for sx in (-1, 1):
            a.beam((sx * w * 0.42, 0.06, -0.05), (sx * w * 0.42, 0.45, -hh * 0.6), 0.04, 0.04, METAL)
    ta, tb = H.t_at_z(xc, zt, side), H.t_at_z(xc, zb, side)
    ta, tb = min(ta, tb), max(ta, tb)
    patch(h, H, x0 - 0.02, x1 + 0.02, ta, tb, 0.015, RUB, nx=1, nt=2)
    SC.hazard_frame(h, H, x0 - 0.02, x1 + 0.02, ta, tb, width=0.12, n=6, off=0.025)
    return a


def airstair(h, lt, H, xc, side, sill_z, width, length, door_top):
    """side airstair = the Ramp node: stands up flush in the doorway when stowed (stow = slope + 90)"""
    y = side * (H.sec(xc)[0] + 0.03)
    hinge = Vector((xc, y, sill_z))
    drop = sill_z - 0.13
    slope = degrees(asin(min(0.95, drop / length)))
    a = Anim("Ramp", place_frame(hinge, 90.0 if side > 0 else -90.0), slope + 90.0)
    foot = SC.ramp_geometry(a, width, length, slope)
    # doorway on the hull with a hazard frame, a lit interior, a flood light above
    ta, tb = H.t_at_z(xc, door_top, side), H.t_at_z(xc, sill_z + 0.05, side)
    ta, tb = min(ta, tb), max(ta, tb)
    x0, x1 = xc - width / 2, xc + width / 2
    patch(h, H, x0, x1, ta, tb, 0.015, RUB, nx=1, nt=2)
    SC.hazard_frame(h, H, x0, x1, ta, tb, width=0.12, n=6, off=0.025)
    patch(lt, H, x0 + 0.12, x1 - 0.12, ta + 3, tb - 3, 0.03, "CabinWindow", nx=1, nt=1, smooth=False)
    tt = H.t_at_z(xc, door_top + 0.35, side)
    q = H.pt(xc, tt, 0.1)
    SC.flood(h, lt, q, (0, side * 0.7, -1))
    return a, Vector((xc, y + side * foot.y + side * 0.3, 0.0))


def rear_ramp(hinge, L, width, close_extra=20.0):
    drop = hinge.z - 0.13
    slope = degrees(atan2(drop, sqrt(max(0.01, L * L - drop * drop))))
    a = Anim("Ramp", place_frame(hinge, 180.0), slope + close_extra)
    foot = SC.ramp_geometry(a, width, L, slope)
    return a, Vector((hinge.x - foot.y - 0.3, hinge.y, 0.0))


def legs4(hx, hy, hz, lh, strut=0.26, foot_r=0.5, ld=None):
    out = []
    ld = hz - 0.02 if ld is None else ld
    for name, sx, sy in (("FL", 1, 1), ("FR", 1, -1), ("RL", -1, 1), ("RR", -1, -1)):
        stow = -(90.0 + degrees(atan(lh / ld)))
        a = Anim("Leg_" + name, place_frame(Vector((sx * hx, sy * hy, hz)), 0.0 if sx > 0 else 180.0), stow)
        SC.leg_geometry(a, lh, ld, foot_r=foot_r, strut=strut)
        out.append(a)
    return out


def hovers(h, H, pts):
    out = []
    for name, x, y in pts:
        e = SC.hover_thruster(h, x, y, H.sec(x)[2] + 0.12)
        out.append((Anchor("Thruster_Hover_" + name, e, forward=(0, 0, -1), up=(1, 0, 0)), {"role": "hover"}))
    return out


def mains(h, specs, r=0.62, L=2.0, ring="Accent"):
    out = []
    for name, origin in specs:
        e = SC.engine_bell(h, origin, -90.0, r=r, L=L, ring_mat=ring)
        out.append((Anchor("Thruster_Main_" + name, e, forward=(-1, 0, 0)), {"role": "main"}))
    return out


def roof_kit(h, H, rail_t, rail_x, ladder_x, vents=()):
    for t in rail_t:
        SC.rail(h, [H.pt(x, t) for x in rail_x], h=0.5)
    SC.hull_ladder(h, H, ladder_x, -1, 8, 60)
    for (x0, t0) in vents:
        panel(h, H, x0, x0 + 0.8, t0, t0 + 9, 0.035, RUB, side=FRAME, nx=1, nt=1)
        for k in range(3):
            xs_ = x0 + 0.8 * (k + 0.5) / 3
            panel(h, H, xs_ - 0.03, xs_ + 0.03, t0, t0 + 9, 0.06, FRAME, side=FRAME, nx=1, nt=1)


def rcs(h, H, spots):
    for (x, z) in spots:
        for sy in (-1, 1):
            t = H.t_at_z(x, z, sy)
            q, n = H.pt(x, t), H.nrm(x, t)
            h.box(tuple(q + n * 0.1), (0.4, 0.3, 0.26), DARK, bevel=0.03)
            h.cyl(q + n * 0.16, q + n * 0.3, 0.06, 0.08, seg=6, mat=FRAME, cap1=False)


def dish(h, pos, r, yaw, tilt, mat_face=HULL):
    with h.at(T(*pos), RZ(yaw), RY(tilt)):
        h.lathe([(0.0, 0.0), (r * 0.45, r * 0.08), (r, r * 0.3), (r * 1.05, r * 0.36), (r * 0.95, r * 0.36), (r * 0.42, r * 0.13),
                 (0.0, r * 0.08)], lambda k, i: mat_face if k < 2 else (FRAME if k < 4 else METAL), seg=16)
        for a in (0, 120, 240):
            h.cyl((r * 0.95 * cos(radians(a)), r * 0.95 * sin(radians(a)), r * 0.34), (0, 0, r * 0.9), 0.025, seg=4,
                  mat=FRAME, smooth=False)
        h.vcyl(0, 0, r * 0.85, r * 1.0, 0.07, seg=6, mat=FRAME)


def cross(p, c, normal, up, arm, thick, mat, depth=0.04):
    """a flat plus sign on a plane (medical)"""
    n, u = Vector(normal).normalized(), Vector(up).normalized()
    r = u.cross(n).normalized()
    c = Vector(c) + n * depth / 2
    p.beam(c - u * arm / 2, c + u * arm / 2, thick, depth, mat, up=tuple(n))
    p.beam(c - r * arm / 2, c + r * arm / 2, thick, depth, mat, up=tuple(n))


def nav_pair(h, lt, x, y_abs, z, r=0.1):
    SC.nav_light(h, lt, (x, y_abs, z), "LightRed", r=r)
    SC.nav_light(h, lt, (x, -y_abs, z), "LightGreen", r=r)


# ======================================================================================
# SHUTTLE: shorter and taller, graphite + white, two window rows, side airstair, no pods
# ======================================================================================
def build_shuttle():
    h, lt = Part("Hull"), Part("Lights")
    H = LoftHull([(-4.8, 1.7, 5.6, 2.8, 3.6), (-4.2, 2.2, 6.3, 2.2, 3.4), (-3.2, 2.3, 6.6, 1.95, 3.3),
                  (2.6, 2.3, 6.6, 1.95, 3.3), (3.8, 2.15, 6.2, 2.0, 3.3), (4.6, 1.75, 5.4, 2.25, 3.3),
                  (5.05, 1.0, 4.7, 2.65, 3.4)], n_top=4.0, n_bot=6.0)
    GR = "Palette:#3d434b"
    ts = [0, 8, 16, 24, 30, 36, 44, 52, 62, 76, 86, 90, 94, 104, 118, 128, 136, 144, 150, 156, 164, 172, 180, 192, 215,
          245, 270, 295, 325, 348]
    seams = (-3.25, -0.4, 2.2)
    # round 11 fix 1: graphite roof with a yellow centre stripe; white upper flanks; graphite lower flanks
    f = matfn(seams=seams, panel_xb=seams, zones=[(86, 94, -4.6, 4.3, "Accent"), (62, 118, -9, 9, GR),
                                                  (0, 30, -9, 9, GR), (150, 180, -9, 9, GR),
                                                  (30, 36, -4.4, 4.6, "Accent"), (144, 150, -4.4, 4.6, "Accent")])
    H.skin(h, rings_x(-4.8, 5.05, 0.45, seams), ts, f, nose_mat=GR, tail_mat=GRAPH)
    ribs(h, H, (-3.25, 2.2), ts)
    # round 11 fix 3: a wide bus windscreen across the nose (no bridge block)
    window_band(h, lt, H, 4.05, 4.75, 38, 142, every=0.35, mat="Window")
    panel(h, H, 3.75, 4.05, 40, 140, 0.06, GR, side=FRAME, nx=1, nt=6)             # brow over the windscreen
    for sy in (-1, 1):                                    # two continuous window rows
        for z in (5.35, 4.1):
            t0, t1 = H.t_at_z(0.0, z + 0.3, sy), H.t_at_z(0.0, z - 0.3, sy)
            if z > 5:
                window_band(h, lt, H, -3.0, 2.4, min(t0, t1), max(t0, t1), every=0.7)
            elif sy < 0:
                window_band(h, lt, H, -2.9, -0.35, min(t0, t1), max(t0, t1), every=0.7)
                window_band(h, lt, H, 1.35, 2.4, min(t0, t1), max(t0, t1), every=0.55)
            else:
                window_band(h, lt, H, -2.9, 2.4, min(t0, t1), max(t0, t1), every=0.7)
    # raised passenger deck along the rear two thirds of the roof, 0.6 m high, with its own window strip
    x0, x1, zb, zt, hw = -4.1, 1.9, 6.45, 7.2, 1.45
    rings = []
    for x, s_ in ((x0, 0.82), (x0 + 0.5, 1.0), (x1 - 0.6, 1.0), (x1, 0.78)):
        ww = hw * s_
        ztop = zb + (zt - zb) * (1.0 if 0.9 < s_ else 0.75)
        rings.append([(x, ww, zb), (x, ww, ztop - 0.18), (x, ww - 0.2, ztop), (x, -(ww - 0.2), ztop), (x, -ww, ztop - 0.18),
                      (x, -ww, zb)])
    h.loft(rings, GR, smooth=False, closed=True, cap0=True, cap1=True, cap_mat=GR)
    h.box(((x0 + x1) / 2 - 0.1, 0, zt + 0.012), (x1 - x0 - 0.9, 0.36, 0.024), "Accent", mats={"-z": None})   # yellow stripe
    for sy in (-1, 1):
        h.box(((x0 + x1) / 2, sy * (hw + 0.005), 6.88), (x1 - x0 - 1.4, 0.02, 0.22), SC.DGLASS)
        lt.box(((x0 + x1) / 2, sy * (hw + 0.02), 6.88), (x1 - x0 - 1.5, 0.012, 0.16), "CabinWindow")
        for k in range(8):
            xx = x0 + 0.7 + (x1 - x0 - 1.4) * k / 7
            h.box((xx, sy * (hw + 0.02), 6.88), (0.05, 0.03, 0.26), FRAME)
    for k in range(5):                                    # deck-top radiator slats and a hatch
        h.box((-3.4 + 0.25 * k, 0.75, zt + 0.03), (0.06, 0.8, 0.06), TRIM)
    h.box((0.9, 0, zt + 0.02), (0.7, 0.9, 0.06), DARK)
    for sy in (-1, 1):                                    # round 11 fix 8: flank insets (lower graphite flank)
        t = H.t_at_z(-1.5, 2.55, sy)
        spans = ((-3.9, -2.2), (-1.9, -0.4), (1.5, 2.7)) if sy < 0 else ((-3.9, -2.7), (-0.6, 0.8), (1.5, 2.7))
        for (a, b) in spans:
            SC.inset_panel(h, H, a, b, t - 4, t + 4, mat="Palette:#4b525b", border="Palette:#2b2f35")
    SC.registration(h, H, "shuttle", 3.0, H.t_at_z(3.0, 3.3, 1), height=0.36, plate="Palette:#e8eaed")
    roof_kit(h, H, (64, 116), [-4.0, -2.6, -1.2, 0.2, 1.6, 2.6], -3.9, vents=((2.2, 82),))
    rcs(h, H, ((4.3, 4.3), (-4.4, 4.2)))
    h.vcyl(2.6, 0.5, 6.55, 7.6, 0.03, seg=4, mat=FRAME, smooth=False)
    dish(h, (2.95, -0.55, 6.6), 0.45, -60, -40)
    thr = mains(h, [("L", (-4.1, 1.45, 5.5)), ("R", (-4.1, -1.45, 5.5))], r=0.66, L=2.05)
    thr += hovers(h, H, [("FL", 3.6, 1.05), ("FR", 3.6, -1.05), ("RL", -3.9, 1.2), ("RR", -3.9, -1.2)])
    nav_pair(h, lt, -4.75, 1.72, 4.6)
    SC.nav_light(h, lt, (-2.4, 0.0, 7.3), "Light", r=0.1)
    for sy in (-1, 1):
        q = H.pt(4.5, 255 if sy < 0 else 285)
        SC.flood(h, lt, q + Vector((0.05, 0, -0.08)), (0.6, 0, -1))
    rp, foot = airstair(h, lt, H, 0.45, -1, 1.95, 1.2, 3.0, 4.0)
    door = gull_door("Door_Cargo", h, H, -2.4, -0.9, 3.6, 2.25, 1)
    anchors = [(Anchor("Anchor_Ramp", foot, forward=(0, -1, 0)), {})]
    return [h, lt, rp, door] + legs4(3.0, 1.9, 1.96, 1.15, strut=0.27) + thr + anchors


# ======================================================================================
# LINER: the longest, a dart; 2.5 m tapered nose, swept delta wings, pink band on the roof spine and flanks
# ======================================================================================
def build_liner():
    h, lt = Part("Hull"), Part("Lights")
    H = LoftHull([(-7.1, 1.0, 3.95, 2.9, 3.2), (-6.3, 1.5, 4.35, 2.3, 3.0), (-4.8, 1.65, 4.55, 1.95, 2.9),
                  (2.2, 1.65, 4.55, 1.95, 2.9), (4.9, 1.35, 4.25, 2.1, 2.9), (6.2, 0.72, 3.7, 2.45, 2.95),
                  (7.0, 0.28, 3.3, 2.75, 3.0), (7.4, 0.05, 3.06, 2.95, 3.0)], n_top=2.6, n_bot=3.5)
    ts = [0, 8, 14, 20, 30, 34, 48, 62, 76, 82, 90, 98, 104, 118, 132, 146, 150, 160, 166, 172, 180, 195, 220, 250, 270,
          290, 320, 345]
    seams = (-4.8, -2.2, 0.6, 3.4)
    f = matfn(seams=seams, panel_xb=seams, zones=[(14, 30, -7.1, 7.2, "Accent"), (150, 166, -7.1, 7.2, "Accent"),
                                                  (82, 98, -7.0, 7.3, "Accent")], alt="Palette:#d0d5dc")
    H.skin(h, rings_x(-7.1, 7.4, 0.45, seams + (5.5, 6.6)), ts, f, nose_mat=HULL, tail_mat=GRAPH)
    ribs(h, H, (-4.8, 3.4), ts)
    # round 11 fix 3: a wraparound cockpit band round the tapered nose
    window_band(h, lt, H, 4.5, 5.75, 32, 148, every=0.42, mat="Window")
    for sy in (-1, 1):                                    # panoramic passenger band
        window_band(h, lt, H, -4.4, 3.4, 36 if sy > 0 else 116, 60 if sy > 0 else 144, every=1.1)
    # observation blister on the roof, midship (the pink roof band runs under it)
    with h.at(T(-0.9, 0, 4.45), S(1.9, 1.0, 0.62)):
        h.lathe([(1.05, 0.0), (0.98, 0.35), (0.78, 0.7), (0.45, 0.95), (0.0, 1.05)], SC.DGLASS, seg=20)
    with lt.at(T(-0.9, 0, 4.47), S(1.9, 1.0, 0.62)):
        lt.lathe([(0.9, 0.3), (0.72, 0.66), (0.4, 0.9)], "CabinWindow", seg=20)
    for k in range(4):
        x = -0.9 + (k - 1.5) * 0.85
        f_ = sqrt(max(0.0, 1 - ((x + 0.9) / 1.995) ** 2))
        pts = [Vector((x, 1.05 * f_ * cos(radians(a)), 4.47 + 0.65 * f_ * sin(radians(a)))) for a in range(0, 181, 30)]
        h.beam_path(pts, 0.07, 0.07, FRAME)
    with h.at(T(-0.9, 0, 4.42), S(1.9, 1.0, 1.0)):
        h.lathe([(1.1, 0.0), (1.1, 0.07), (1.0, 0.09)], FRAME, seg=20)
    # round 11 fix 2: swept delta wings (seen from above) with pink leading edges and winglets
    for sy in (-1, 1):
        root_l, tip_l, tip_t, root_t = (-1.4, 1.45), (-5.6, 3.3), (-6.55, 3.3), (-6.7, 1.3)
        poly = [(x, sy * y) for x, y in (root_l, tip_l, tip_t, root_t)]
        h.prism(poly, 2.72, 2.9, HULL, cap_mat=HULL)
        edge = [(x, sy * y) for x, y in ((-1.4, 1.45), (-5.6, 3.3), (-5.85, 3.3), (-1.9, 1.45))]
        h.prism(edge, 2.9, 2.93, "Accent", cap0=False)
        h.prism([(x, sy * y) for x, y in ((-5.7, 3.18), (-6.55, 3.18), (-6.55, 3.3), (-5.7, 3.3))], 2.9, 3.9, HULL,
                cap_mat="Accent")
        SC.nav_light(h, lt, (-6.1, sy * 3.24, 4.0), "LightRed" if sy > 0 else "LightGreen", r=0.1)
    h.prism_y([(-4.6, 4.5), (-5.9, 5.8), (-6.6, 5.85), (-6.5, 4.0)], -0.08, 0.08, HULL)
    h.prism_y([(-5.75, 5.65), (-6.6, 5.85), (-6.58, 5.55), (-5.8, 5.45)], -0.1, 0.1, "Accent")
    SC.nav_light(h, lt, (-6.4, 0.0, 5.95), "Light", r=0.1)
    SC.registration(h, H, "liner", 3.3, H.t_at_z(3.3, 3.0, 1), height=0.3)
    roof_kit(h, H, (70, 110), [0.9, 1.9, 2.9], -5.3, vents=((1.3, 104), (-4.4, 104)))
    rcs(h, H, ((5.6, 3.1), (-6.2, 3.3)))
    thr = mains(h, [("C", (-5.85, 0.0, 3.55)), ("L", (-5.6, 1.22, 3.1)), ("R", (-5.6, -1.22, 3.1))], r=0.5, L=1.45)
    thr += hovers(h, H, [("FL", 4.6, 0.8), ("FR", 4.6, -0.8), ("RL", -5.9, 0.75), ("RR", -5.9, -0.75)])
    for sy in (-1, 1):
        q = H.pt(5.6, 255 if sy < 0 else 285)
        SC.flood(h, lt, q + Vector((0.05, 0, -0.08)), (0.6, 0, -1))
    rp, foot = airstair(h, lt, H, 1.3, -1, 2.0, 1.4, 3.3, 3.95)
    door = gull_door("Door_Service", h, H, 0.6, 1.8, 3.6, 2.3, 1)
    anchors = [(Anchor("Anchor_Ramp", foot, forward=(0, -1, 0)), {})]
    return [h, lt, rp, door] + legs4(4.4, 1.3, 2.0, 1.1, strut=0.26) + thr + anchors


# ======================================================================================
# MEDICAL: compact and wide, white + red, big crosses on the roof and flanks, wide stretcher ramp and door
# ======================================================================================
def build_medical():
    h, lt = Part("Hull"), Part("Lights")
    H = LoftHull([(-4.2, 1.9, 4.6, 2.35, 3.0), (-3.6, 2.5, 5.2, 1.75, 2.8), (2.8, 2.5, 5.2, 1.75, 2.8),
                  (3.8, 2.3, 4.9, 1.8, 2.8), (4.4, 1.7, 4.3, 2.1, 2.9), (4.72, 0.9, 3.8, 2.5, 3.0)], n_top=5.5, n_bot=7.0)
    ts = [0, 8, 12, 24, 30, 42, 56, 72, 90, 108, 124, 138, 150, 156, 168, 172, 180, 195, 225, 270, 315, 345]
    seams = (-2.2, 0.4, 2.3)
    f = matfn(seams=seams, panel_xb=seams, zones=[(12, 24, -4.1, 4.5, "Accent"), (156, 168, -4.1, 4.5, "Accent")],
              alt="Palette:#e4e7ea", top="Palette:#f2f3f5", belly="Palette:#6b727b")
    H.skin(h, rings_x(-4.2, 4.72, 0.45, seams), ts, f, nose_mat="Palette:#f2f3f5", tail_mat=GRAPH)
    ribs(h, H, (-2.2, 2.3), ts)
    SC.faceted_cockpit(h, lt, 2.7, 3.55, 4.55, w=1.6, zb=3.9, zt=5.45, c=0.38, front_top=4.4, front_w=1.1,
                       body="Palette:#f2f3f5")
    # red crosses: roof (top-down read) and both flanks
    cross(h, (-0.6, 0.0, 5.2), (0, 0, 1), (1, 0, 0), 3.4, 1.0, "Accent", depth=0.05)
    for sy in (-1, 1):
        t = H.t_at_z(-0.9, 3.75, sy)
        q, n = H.pt(-0.9, t), H.nrm(-0.9, t)
        panel(h, H, -1.75, -0.05, t - 12, t + 12, 0.02, "Palette:#ffffff", side="Palette:#ffffff", nx=1, nt=2)
        cross(h, q + n * 0.03, n, (0, 0, 1), 1.3, 0.38, "Accent", depth=0.04)
    for sy in (-1, 1):
        window_band(h, lt, H, 0.4, 2.2, 44 if sy > 0 else 118, 62 if sy > 0 else 136, every=0.6)
        for (a, b, t0, t1) in ((-3.4, -2.25, 30, 42), (-3.4, -2.25, 4, 13), (2.55, 3.6, 34, 44)):   # round 11 fix 8
            SC.inset_panel(h, H, a, b, *((t0, t1) if sy > 0 else (180 - t1, 180 - t0)), mat="Palette:#e3e6ea")
    SC.registration(h, H, "medical", 3.3, H.t_at_z(3.3, 3.05, 1), height=0.3)
    roof_kit(h, H, (60, 120), [-3.2, -2.0, 1.2, 2.3], -3.6, vents=((1.3, 84),))
    rcs(h, H, ((4.1, 3.6), (-3.9, 3.8)))
    for sy in (-1, 1):                                    # red / white light bars on the roof corners
        h.box((2.2, sy * 1.3, 5.3), (0.5, 0.22, 0.14), FRAME, bevel=0.03)
        lt.box((2.2, sy * 1.3, 5.39), (0.46, 0.18, 0.06), "LightRed" if sy > 0 else "Light")
    thr = mains(h, [("L", (-3.7, 1.95, 4.45)), ("R", (-3.7, -1.95, 4.45))], r=0.6, L=1.9)
    thr += hovers(h, H, [("FL", 3.7, 1.2), ("FR", 3.7, -1.2), ("RL", -3.8, 1.55), ("RR", -3.8, -1.55)])
    nav_pair(h, lt, -3.9, 2.35, 3.4)
    for sy in (-1, 1):
        q = H.pt(4.2, 255 if sy < 0 else 285)
        SC.flood(h, lt, q + Vector((0.05, 0, -0.08)), (0.6, 0, -1))
        SC.flood(h, lt, Vector((-3.75, sy * 1.2, 1.7)), (-0.5, 0, -1))
    rp, foot = rear_ramp(Vector((-3.55, 0.0, 1.75)), 2.7, 2.8)
    patch(h, H, -4.15, -3.6, 236, 304, 0.02, RUB, nx=1, nt=3)
    SC.hazard_frame(h, H, -4.15, -3.6, 236, 304, width=0.1, n=6, off=0.028)
    door = gull_door("Door_Stretcher", h, H, 0.6, 2.4, 3.9, 2.05, -1)
    anchors = [(Anchor("Anchor_Ramp", foot, forward=(-1, 0, 0)), {})]
    return [h, lt, rp, door] + legs4(3.1, 2.1, 1.8, 1.05, strut=0.27) + thr + anchors


# ======================================================================================
# SCIENCE: medium, the one tall ship; blue deck, sensor dish on a mast, antenna array, belly instrument pods
# ======================================================================================
def build_science():
    h, lt = Part("Hull"), Part("Lights")
    H = LoftHull([(-5.2, 1.5, 4.5, 2.6, 3.2), (-4.4, 2.1, 5.2, 2.05, 3.0), (2.6, 2.1, 5.3, 1.9, 3.0),
                  (4.0, 1.85, 5.0, 2.0, 3.0), (5.0, 1.3, 4.4, 2.3, 3.0), (5.5, 0.6, 3.9, 2.7, 3.1)], n_top=3.2, n_bot=5.0)
    ts = [0, 8, 14, 20, 30, 45, 60, 70, 80, 90, 100, 110, 120, 135, 150, 160, 166, 172, 180, 195, 225, 270, 315, 345]
    seams = (-2.6, 0.2, 2.6)
    f = matfn(seams=seams, panel_xb=seams, zones=[(70, 110, -4.9, 3.8, "Accent"), (14, 20, -5.0, 5.2, "Accent"),
                                                  (160, 166, -5.0, 5.2, "Accent")], alt="Palette:#cfd5e2")
    H.skin(h, rings_x(-5.2, 5.5, 0.45, seams), ts, f, nose_mat=HULL, tail_mat=GRAPH)
    ribs(h, H, (-2.6, 2.6), ts)
    SC.faceted_cockpit(h, lt, 2.9, 3.85, 5.0, w=1.35, zb=3.9, zt=5.55, c=0.36, front_top=4.4, front_w=0.9)
    for sy in (-1, 1):
        window_band(h, lt, H, -1.9, 1.9, 34 if sy > 0 else 128, 48 if sy > 0 else 146, every=0.65)
        for (a, b, t0, t1) in ((-4.0, -2.75, 28, 40), (-4.0, -2.75, 4, 13), (2.1, 2.75, 28, 42)):    # round 11 fix 8
            SC.inset_panel(h, H, a, b, *((t0, t1) if sy > 0 else (180 - t1, 180 - t0)))
    # sensor mast with a big dish, the tallest ship in the fleet
    mx, mz = -0.4, 5.25
    h.vcyl(mx, 0, mz - 0.1, mz + 0.4, 0.55, seg=12, mat="Accent")
    tops = []
    for k in range(3):
        a = radians(90 + 120 * k)
        f0 = Vector((mx + 0.42 * cos(a), 0.42 * sin(a), mz + 0.4))
        t1 = Vector((mx + 0.16 * cos(a), 0.16 * sin(a), 11.4))
        h.beam(f0, t1, 0.08, 0.08, FRAME)
        tops.append((f0, t1))
    for j in range(1, 7):
        q = j / 7
        pts = [f0 + (t1 - f0) * q for f0, t1 in tops]
        for i in range(3):
            h.beam(pts[i], pts[(i + 1) % 3], 0.045, 0.045, FRAME if j % 2 else "Accent")
    h.vcyl(mx, 0, 11.3, 11.7, 0.3, seg=10, mat=FRAME)
    dish(h, (mx, 0, 11.75), 1.45, -35, -50)
    SC.nav_light(h, lt, (mx, 0.0, 12.9), "LightRed", r=0.1)
    SC.nav_light(h, lt, (mx + 0.2, 0.2, 8.4), "Light", r=0.08)
    # antenna array on a boom over the tail, a small radome
    h.beam((-2.2, 0, 5.35), (-4.4, 0, 5.2), 0.14, 0.12, FRAME)
    for k in range(6):
        x = -2.4 - 0.38 * k
        h.vcyl(x, 0, 5.2, 6.4 + 0.25 * (k % 2), 0.025, seg=4, mat=TRIM, smooth=False)
        h.box((x, 0, 6.0), (0.05, 0.5, 0.04), FRAME)
    h.hemi((1.9, 0.0, 5.25), 0.42, HULL, seg=12, rings=3)
    # belly instrument pods between the legs
    for (x, r) in ((1.3, 0.42), (-1.5, 0.38)):
        h.vcyl(x, 0, 1.45, 1.95, 0.12, seg=6, mat=FRAME)
        h.sphere((x, 0, 1.35), r, "Accent" if x > 0 else HULL, seg=12, rings=6)
    h.cyl((-0.2, 0, 1.55), (-0.2, 0, 0.9), 0.08, seg=6, mat=METAL)
    h.box((-0.2, 0, 0.85), (0.3, 0.3, 0.16), FRAME, bevel=0.03)
    SC.registration(h, H, "science", 3.2, H.t_at_z(3.2, 3.2, 1), height=0.32)
    roof_kit(h, H, (62, 118), [1.0, 2.0, 3.0], -4.2, vents=((0.6, 84),))
    rcs(h, H, ((4.8, 3.2), (-4.9, 3.9)))
    thr = mains(h, [("L", (-4.4, 1.75, 4.2)), ("R", (-4.4, -1.75, 4.2))], r=0.62, L=2.0)
    thr += hovers(h, H, [("FL", 4.1, 1.05), ("FR", 4.1, -1.05), ("RL", -4.3, 1.3), ("RR", -4.3, -1.3)])
    nav_pair(h, lt, -4.9, 1.6, 3.4)
    for sy in (-1, 1):
        q = H.pt(4.7, 255 if sy < 0 else 285)
        SC.flood(h, lt, q + Vector((0.05, 0, -0.08)), (0.6, 0, -1))
        SC.flood(h, lt, Vector((-4.2, sy * 0.95, 1.8)), (-0.5, 0, -1))
    rp, foot = rear_ramp(Vector((-4.05, 0.0, 1.9)), 2.9, 1.9)
    patch(h, H, -5.15, -4.1, 236, 304, 0.02, RUB, nx=1, nt=3)
    SC.hazard_frame(h, H, -5.15, -4.1, 236, 304, width=0.1, n=6, off=0.028)
    door = gull_door("Door_Lab", h, H, -1.3, 0.1, 3.4, 2.1, -1)
    anchors = [(Anchor("Anchor_Ramp", foot, forward=(-1, 0, 0)), {})]
    return [h, lt, rp, door] + legs4(3.3, 1.9, 1.92, 1.15, strut=0.26) + thr + anchors


# ======================================================================================
# COURIER: the smallest (plan radius about 4 m), a black-and-gold wedge with one engine
# ======================================================================================
def build_courier():
    h, lt = Part("Hull"), Part("Lights")
    H = LoftHull([(-3.3, 2.45, 2.55, 1.4, 1.85), (-2.6, 2.6, 2.8, 1.28, 1.78), (-0.5, 2.1, 2.85, 1.22, 1.72),
                  (1.5, 1.4, 2.6, 1.26, 1.72), (3.0, 0.7, 2.25, 1.42, 1.72), (3.75, 0.12, 1.92, 1.62, 1.72)],
                 n_top=3.5, n_bot=6.0)
    BLK, BLK2 = "Palette:#2b2e35", "Palette:#3b3f47"
    ts = [0, 6, 12, 18, 26, 40, 56, 72, 90, 108, 124, 140, 154, 162, 168, 174, 180, 200, 240, 270, 300, 340]
    seams = (-1.6, 0.6)
    f = matfn(seams=seams, panel_xb=seams, top=BLK, alt=BLK2, belly="Palette:#1f2126", seam_mat="Palette:#15171b",
              zones=[(12, 18, -3.2, 3.6, "Accent"), (162, 168, -3.2, 3.6, "Accent")])
    H.skin(h, rings_x(-3.3, 3.75, 0.35, seams), ts, f, nose_mat=BLK, tail_mat="Palette:#1f2126")
    SC.bubble_canopy(h, lt, (0.8, 0.0, 2.66), 1.25, 0.66, 0.6)                      # round 11 fix 3: a canopy
    for sy in (-1, 1):                                    # gold chevrons on the top deck
        for k in range(3):
            x = -2.3 + 0.55 * k
            h.beam((x, sy * 0.25, 2.86), (x - 0.5, sy * 1.45, 2.78), 0.14, 0.03, "Accent", up=(0, 0, 1))
    SC.registration(h, H, "courier", -1.9, H.t_at_z(-1.9, 1.95, 1), height=0.24, mat="Accent", plate=BLK2)
    SC.rail(h, [H.pt(x, 66) for x in (-2.6, -1.8, -1.0)], h=0.4)
    SC.rail(h, [H.pt(x, 114) for x in (-2.6, -1.8, -1.0)], h=0.4)
    rcs(h, H, ((2.6, 1.9), (-2.9, 2.1)))
    for sy in (-1, 1):                                    # side strakes
        h.prism_x([(sy * 2.25, 1.62), (sy * 2.9, 1.7), (sy * 2.9, 1.78), (sy * 2.25, 1.92)], -3.2, -0.9, BLK2)
        h.box((-2.0, sy * 2.88, 1.74), (2.2, 0.06, 0.08), "Accent")
    thr = mains(h, [("C", (-2.7, 0.0, 2.05))], r=0.78, L=1.7, ring="Accent")
    thr += hovers(h, H, [("FL", 2.2, 0.55), ("FR", 2.2, -0.55), ("RL", -2.2, 1.45), ("RR", -2.2, -1.45)])
    nav_pair(h, lt, -2.4, 2.92, 1.8, r=0.09)
    SC.nav_light(h, lt, (-0.9, 0.0, 2.9), "Light", r=0.08)
    q = H.pt(3.0, 270)
    SC.flood(h, lt, q + Vector((0.0, 0, -0.08)), (0.6, 0, -1))
    rp, foot = airstair(h, lt, H, -0.8, -1, 1.25, 0.95, 1.75, 2.4)
    door = gull_door("Door_Hatch", h, H, 0.4, 1.2, 2.45, 1.55, 1, open_deg=95.0)
    anchors = [(Anchor("Anchor_Ramp", foot, forward=(0, -1, 0)), {})]
    return [h, lt, rp, door] + legs4(1.9, 1.35, 1.28, 0.7, strut=0.2, foot_r=0.38) + thr + anchors


BUILDERS = dict(shuttle=build_shuttle, liner=build_liner, medical=build_medical, science=build_science,
                courier=build_courier)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(BUILDERS)
    for kind in only:
        SC.build_ship(kind, BUILDERS[kind], ao_dist=1.0 if kind != "courier" else 0.7)


if __name__ == "__main__":
    main()
