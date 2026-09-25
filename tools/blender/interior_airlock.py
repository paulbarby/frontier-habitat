"""
Frontier Habitat 3.1 - ART-HAB: the airlock (docs/V3_1_DESIGN.md section 5.1; critic round 10).  Blender 5.2,
--background only.

Three zones in a line along +X:
  suit room (inside the base: lockers, suit racks, a bench, air refill ports)
  -> INNER DOOR (the 3.1 door kit in a partition, three pressure lights over it)
  -> PRESSURE CHAMBER (floor grating, vent grilles, pump housings, a gauge panel, light strips, a window)
  -> OUTER DOOR (the door kit, recessed so its housing stays in the footprint, hazard stripes round it)
  -> PORCH outside (a flat grate with a striped lip, two bollards, a floodlight; object Porch).

Sizes (decision of 2026-09-25; the radii are proposed to SIM in docs/requests/ART-HAB-to-SIM.md):
  airlock.glb    R 2.8  (the current content size): 2 riders, compact chamber
  airlock_m.glb  R 3.4: 2 riders, chamber 2.4 m
  airlock_l.glb  R 4.0: 4 riders, chamber 3.6 m (two pairs)

Objects for the game (besides the room objects):
  InnerDoorL, InnerDoorLTop, InnerDoorR, InnerDoorRTop, InnerStatus, InnerLights  (local +X = into the chamber)
  PressureLight_0..2 (over the inner door, both faces; RENDER colours them per phase)
  OuterFrame, OuterFrameTop, OuterDoorL/R(+Top), OuterStatus, OuterLights            (local +X = outside)
  ChamberLight (strips in the chamber and a lamp; amber cycling, red outbound pump, green inbound done)
  Beacon (the amber beacon on the chamber block; RENDER drives it by phase)
  Porch
Everything above 1.40 m of the inner partition and the chamber walls is in Roof or in a "...Top" object, so the
cutaway shows them cut at 1.40 m with solid caps.
Anchors: Anchor_Chamber_<i> (riders), Anchor_Suit_<i>, Anchor_Porch_<i>, Stand, Light, Aisle, Beacon.
"""
import json
import os
from contextlib import ExitStack
from math import sin, cos, radians, degrees, hypot, sqrt, atan2, asin

import interior_kit as IK
import interior_furniture as FU
from rooms_kit import P, T, RX, RY, RZ, S, capsule, fan_unit, reg_angles, FLOOR_Z, WALL_TOP
from interior_kit import F, Plan, bbox, plate_x, plate_y, plate_z, furniture_of
from interior_rooms import at, wall_set, DEPTHS

CH_HW = 1.05                 # chamber inner half width (side walls at |y| 1.05 .. 1.15)
CH_TOP = 2.60                # chamber wall height (above 1.40 in Roof: hidden with the roof in the cutaway)
SUIT_MIN = 1.55              # the suit room keeps at least this depth behind the inner partition


def _links():
    import interior_links as L
    return L


def spec(rm):
    """(riders, chamber length, dome height) for this airlock's radius."""
    bal = json.load(open(os.path.join(IK.K.ROOT, "content", "balance.json"), encoding="utf-8"))
    base = int(bal.get("airlock_slots", 2))
    if rm.R >= 3.9:
        return 2 * base, 3.6, 3.9
    if rm.R >= 3.3:
        return base, 2.4, 3.6
    return base, None, 3.35


def layout(rm):
    """Door planes: XO (outer, recessed so the housing corners stay inside R - 0.10) and XI (inner)."""
    L = _links()
    riders, ch_len, _ = spec(rm)
    XO = sqrt((rm.R - 0.10) ** 2 - L.HY ** 2) - L.HX[1]
    ch_end = XO + L.HX[0]
    if ch_len is None:                                   # compact: as long as the suit room allows
        ch_len = max(1.4, ch_end - L.HX[1] - (-(rm.Ri) + SUIT_MIN - L.HX[0]))
    XI = ch_end - ch_len - L.HX[1]
    return XO, XI, ch_len, riders


def door_kit(rm, x, lo, hi, prefix, sill_x1=None):
    """A flat 3.1 door kit at (x, 0), local +X along +X: housing into lo/hi, leaves and lights into new parts."""
    L = _links()
    names = ("DoorL", "DoorLTop", "DoorR", "DoorRTop", "Lights", "Status", "FrameCap")
    parts = {nm: P(prefix + nm) for nm in names}
    with ExitStack() as st:
        for p in [lo, hi] + list(parts.values()):
            st.enter_context(p.at(T(x, 0, 0)))
        L.housing(lo, hi, None, cap=parts["FrameCap"])        # critic round 13: <prefix>FrameCap at 1.40 m
        L.threshold(lo, sill_x1)
        L.leaf31(parts["DoorL"], parts["DoorLTop"], -1)
        L.leaf31(parts["DoorR"], parts["DoorRTop"], 1)
        L.tunnel_lights(parts["Lights"])
        L.status_light(parts["Status"], None)
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + list(parts.values())
    return parts


# --------------------------------------------------------------------------------------
# Exterior (called from rooms_links.build_airlock in 3.0/3.1 mode)
# --------------------------------------------------------------------------------------
def exterior(rm):
    L = _links()
    Rw = rm.Rw
    XO, XI, ch_len, riders = layout(rm)
    _, _, dome_h = spec(rm)
    rm.build_door = lambda *a, **k: None          # no v2 service door: the 3.1 outer door kit replaces it
    rm.keep_door = True
    rm.name_sign_deg = 135.0                       # the name sign on the suit-room side, clear of the outer door
    a_wall = degrees(asin(min(0.99, L.HY / Rw)))  # the drum wall starts where it meets the housing ends
    door_w = 2.0 * (Rw * sin(radians(a_wall - 1.0)) - 0.3)
    rm.build_base(door_w=door_w, lamps=(135.0, 225.0), bolts=True, band="Hazard", kick="HullDark")
    rm.build_dome(dome_h, crown="hatch", seams=8, seam_phase=22.5)
    ro = rm.roof
    x0b, x1b = XI + L.HX[1], XO + L.HX[1]         # the chamber block
    hw = 1.62
    # cut the dome where the chamber block and the outer door stand (no dome hood over the door)
    keep_f, keep_m, keep_s = [], [], []
    for idx, mat, sm in zip(ro.faces, ro.fmat, ro.fsmooth):
        vs = [ro.verts[i] for i in idx]
        cx, cy = sum(v.x for v in vs) / len(vs), sum(v.y for v in vs) / len(vs)
        if cx > x0b + 0.10 and abs(cy) < hw + 0.02:
            continue
        keep_f.append(idx)
        keep_m.append(mat)
        keep_s.append(sm)
    ro.faces, ro.fmat, ro.fsmooth = keep_f, keep_m, keep_s
    # the outer door kit (own objects), hazard stripes round the opening on the outside face
    of, oft = P("OuterFrame"), P("OuterFrameTop")
    door_kit(rm, XO, of, oft, "Outer", sill_x1=L.HX[1] + 0.12)
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [of, oft]
    xo = XO + L.HX[1] + 0.006
    for sy in (-1, 1):
        y0, y1 = sorted((sy * (L.OPEN_HW + 0.10), sy * (L.HY - 0.12)))
        for k in range(7):
            z0 = 0.18 + 0.30 * k
            if z0 < WALL_TOP < z0 + 0.30:
                continue
            m = "Hazard" if k % 2 == 0 else "Rubber"
            part = of if z0 + 0.30 <= WALL_TOP else oft
            part.quad((xo, y0, z0), (xo, y1, z0 + 0.12), (xo, y1, z0 + 0.30), (xo, y0, z0 + 0.18), m)
    # the chamber block: armoured, through the dome, with pumps, a fan and the amber beacon; faired into the dome
    # the block top clears the door housings and meets the dome along its edges (no hole, no step)
    edge = [rm.dome_z(x0b + (x1b - x0b) * t / 10.0, hw) for t in range(11)] + [rm.dome_z(x0b, 0.0)]
    zt = max(3.05, L.HT + 0.45, max(edge) + 0.05)
    ro.box0(0.5 * (x0b + x1b), 0.0, CH_TOP, x1b - x0b, 2 * hw + 0.06, zt - CH_TOP, "Hull", bevel=0.04,
            mats={"-z": None})
    for sy in (-1, 1):
        ro.box0(0.5 * (x0b + x1b), sy * (hw + 0.04), WALL_TOP + 0.02, x1b - x0b, 0.06, zt - WALL_TOP - 0.02, "Hull",
                mats={"-z": None})
        ro.box((0.5 * (x0b + x1b), sy * (hw + 0.075), zt - 0.22), (x1b - x0b - 0.1, 0.012, 0.12), "Hazard",
               mats={"-y" if sy > 0 else "+y": None})
        # fairing: a sloped shoulder from the block side down onto the dome (no step)
        n = 8
        for k in range(n):
            xa = x0b + (x1b - x0b) * k / n
            xb = x0b + (x1b - x0b) * (k + 1) / n
            ya = sy * (hw + 0.07)
            ra = max(hw + 0.07, min(hw + 0.55, sqrt(max(0.0, (Rw - 0.08) ** 2 - xa * xa))))
            rb = max(hw + 0.07, min(hw + 0.55, sqrt(max(0.0, (Rw - 0.08) ** 2 - xb * xb))))
            za = zb = zt - 0.30
            da = rm.dome_z(xa, ra) + 0.02
            db = rm.dome_z(xb, rb) + 0.02
            q = [(xa, ya, za), (xb, ya, zb), (xb, sy * rb, db), (xa, sy * ra, da)]
            if sy < 0:
                q.reverse()
            ro.quad(*q, "Hull", smooth=True)
    ro.box0(0.5 * (x0b + x1b), 0.0, zt, x1b - x0b - 0.2, 2 * hw - 0.2, 0.06, "Frame", mats={"-z": None})
    for sy in (-0.50, 0.50):
        capsule(ro, (x0b + 0.35, sy, zt + 0.28), (x1b - 0.55, sy, zt + 0.28), 0.18, mat="Metal", seg=8, rings=2)
        for x in (x0b + 0.5, x1b - 0.7):
            ro.box0(x, sy, zt + 0.06, 0.10, 0.34, 0.10, "Frame", mats={"-z": None})
    fan_unit(ro, x0b + 0.40, 0.0, zt + 0.06, 0.22)
    bc = P("Beacon")
    bx = x1b - 0.30
    bc.vcyl(bx, 0.0, zt + 0.06, zt + 0.20, 0.14, seg=10, mat="Frame")
    bc.vcyl(bx, 0.0, zt + 0.20, zt + 0.34, 0.11, seg=10, mat="BeaconAmber", cap0=False)
    bc.lathe([(0.11, zt + 0.34), (0.08, zt + 0.42), (0.0, zt + 0.45)], "BeaconAmber", seg=10)
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [bc]
    rm.anchor("Beacon", (bx, 0.0, zt + 0.40))
    rm.top_z = max(rm.top_z, zt + 0.8)
    porch(rm, XO)


def porch(rm, XO):
    """Porch outside the outer door (object Porch, outside the footprint): a flat grate deck with a hazard-striped
    lip, two bollards at the front corners, a floodlight on a pole."""
    L = _links()
    p = P("Porch")
    x0 = XO + L.HX[1] + 0.12
    x1 = x0 + 1.50
    hw = 1.00
    zt = 0.10
    bbox(p, x0, x1, -hw, hw, 0.0, zt, "FloorDark", mats={"-z": None})
    for j in range(int((x1 - x0 - 0.2) / 0.10)):                  # grate bars across the deck
        x = x0 + 0.12 + 0.10 * j
        bbox(p, x - 0.02, x + 0.02, -hw + 0.10, hw - 0.10, zt, zt + 0.012, "Frame", mats={"-z": None})
    # the striped lip on the three open sides
    for (xa, xb, ya, yb) in ((x1 - 0.08, x1, -hw, hw), (x0, x1, -hw, -hw + 0.08), (x0, x1, hw - 0.08, hw)):
        long_x = (xb - xa) > (yb - ya)
        L_ = (xb - xa) if long_x else (yb - ya)
        nseg = max(2, int(L_ / 0.20))
        for k in range(nseg):
            if long_x:
                a0, a1 = xa + (xb - xa) * k / nseg, xa + (xb - xa) * (k + 1) / nseg
                plate_z(p, zt + 0.014, a0, a1, ya, yb, "Hazard" if k % 2 == 0 else "Rubber")
            else:
                a0, a1 = ya + (yb - ya) * k / nseg, ya + (yb - ya) * (k + 1) / nseg
                plate_z(p, zt + 0.014, xa, xb, a0, a1, "Hazard" if k % 2 == 0 else "Rubber")
    for sy in (-1, 1):                                           # two bollards at the front corners
        bx, by = x1 - 0.20, sy * (hw - 0.20)
        p.vcyl(bx, by, zt, zt + 0.80, 0.10, seg=8, mat="Hull", cap0=False)
        p.vcyl(bx, by, zt + 0.55, zt + 0.68, 0.105, seg=8, mat="Hazard", cap0=False, cap1=False)
        p.vcyl(bx, by, zt + 0.80, zt + 0.88, 0.07, seg=8, mat="BeaconAmber")
    fx, fy = x0 + 0.30, -(hw + 0.20)                             # floodlight on a pole
    p.vcyl(fx, fy, 0.0, 0.08, 0.14, seg=8, mat="Frame")
    # critic round 13: the pole ends at 1.40 m; the upper pole and the lamp are PorchTop (hidden in the
    # cutaway with every "...Top" group)
    p.vcyl(fx, fy, 0.08, WALL_TOP, 0.04, seg=6, mat="Metal", cap0=False)
    # (object PorchTop: RENDER adds "PorchTop" to presentation/models.gd GROUPS, docs/requests/ART-HAB-to-RENDER.md)
    pt = P("PorchTop")
    pt.overhang = True                                           # the porch stands outside the footprint
    pt.vcyl(fx, fy, WALL_TOP, 2.35, 0.04, seg=6, mat="Metal", cap0=False)
    with pt.at(T(fx, fy, 2.35), RY(-25.0)):
        bbox(pt, -0.08, 0.20, -0.14, 0.14, -0.08, 0.06, "HullDark")
        plate_x(pt, 0.201, -0.11, 0.11, -0.06, 0.04, "Light")
    pt.overhang = False
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [p, pt]
    rm.anchor("Porch_0", (x0 + 0.85, -0.40, zt), 180.0)
    rm.anchor("Porch_1", (x0 + 0.85, 0.40, zt), 180.0)


# --------------------------------------------------------------------------------------
# Interior
# --------------------------------------------------------------------------------------
def chamber_wall(lo, hi, y0, y1, x0, x1, window=None):
    """A side wall of the chamber, split at WALL_TOP (lo gets a solid cap); window = (xa, xb, za, zb) of a glass
    opening to the suit room."""
    def seg(xa, xb, za, zb):
        cut = za < WALL_TOP < zb
        if za < WALL_TOP:
            bbox(lo, xa, xb, y0, y1, za, min(zb, WALL_TOP), "Hull", mats={"+z": None} if cut else None)
            if cut:                                   # critic round 14: cut-wall cap, frame colour with a light edge
                _links().cap_top(lo, xa, xb, y0, y1, WALL_TOP)
        if zb > WALL_TOP:
            bbox(hi, xa, xb, y0, y1, max(za, WALL_TOP), zb, "Hull", mats={"-z": None} if cut else None)
    if window is None:
        seg(x0, x1, 0.0, CH_TOP)
        return
    xa, xb, za, zb = window
    seg(x0, xa, 0.0, CH_TOP)
    seg(xb, x1, 0.0, CH_TOP)
    seg(xa, xb, 0.0, za)
    seg(xa, xb, zb, CH_TOP)
    ym = 0.5 * (y0 + y1)
    for zz0, zz1, part in ((za, min(zb, WALL_TOP), lo), (max(za, WALL_TOP), zb, hi)):
        if zz1 > zz0:
            plate_y(part, ym + 0.004, xa, xb, zz0, zz1, "Glass", facing=1)
            plate_y(part, ym - 0.004, xa, xb, zz0, zz1, "Glass", facing=-1)


def gauge_panel(n, x, y, face):
    """Pressure gauge panel on a chamber wall: three dials and a status bar."""
    with n.at(T(x, y, 0), RZ(90.0 if face > 0 else -90.0)):
        bbox(n, 0.0, 0.05, -0.30, 0.30, F + 0.95, F + 1.22, "HullDark")
        for j, yy in enumerate((-0.18, 0.0, 0.18)):
            with n.at(T(0.052, yy, F + 1.10), RY(90.0)):
                n.cap_disc(0.07, 0.0, "Screen", seg=10)
        plate_x(n, 0.053, -0.24, 0.24, F + 0.99, F + 1.02, "StatusGreen")


def vent_grille(n, x, y, z, face, w=0.50, h=0.30):
    with n.at(T(x, y, 0), RZ(90.0 if face > 0 else -90.0)):
        bbox(n, 0.0, 0.03, -w / 2, w / 2, z, z + h, "HullDark")
        for j in range(5):
            zz = z + 0.04 + (h - 0.08) * j / 4
            plate_x(n, 0.032, -w / 2 + 0.04, w / 2 - 0.04, zz, zz + 0.02, "Frame")


def pump_housing(n, x, y, face):
    with n.at(T(x, y, 0), RZ(90.0 if face > 0 else -90.0)):
        bbox(n, 0.0, 0.22, -0.28, 0.28, F, F + 0.62, "HullDark", bevel=0.02)
        capsule(n, (0.14, -0.20, F + 0.40), (0.14, 0.20, F + 0.40), 0.12, mat="Metal", seg=8, rings=2)
        plate_x(n, 0.221, -0.20, 0.20, F + 0.12, F + 0.18, "Hazard")


def wall_bench(p, w=1.0, d=0.36):
    """Wall item: a bench on two wall brackets (seat 0.44 m), a helmet crate on it."""
    bbox(p, 0.0, d, -w / 2, w / 2, F + 0.38, F + 0.46, "Hull", bevel=0.02)
    for sy in (-w / 2 + 0.10, w / 2 - 0.10):
        bbox(p, 0.0, d - 0.04, sy - 0.04, sy + 0.04, F + 0.30, F + 0.38, "Frame")
        bbox(p, 0.0, 0.05, sy - 0.04, sy + 0.04, F + 0.05, F + 0.38, "Frame")
    FU.crate(p, d * 0.5, w * 0.25, s=0.22, z=F + 0.46, mat="Accent")


def refill_port(p, w=0.70, d=0.20, seed=0):
    """Wall item: an air refill port (panel, two hose reels, a gauge)."""
    bbox(p, 0.0, 0.06, -w / 2, w / 2, F + 0.60, F + 1.30, "HullDark")
    rr = min(0.13, w * 0.17)
    for sy in (-w * 0.24, w * 0.24):
        with p.at(T(0.10, sy, F + 1.00), RY(90.0)):
            p.vcyl(0, 0, -0.04, 0.04, rr, seg=10, mat="Accent")
            p.vcyl(0, 0, 0.04, 0.06, rr * 0.4, seg=6, mat="Frame")
    with p.at(T(0.062, 0.0, F + 1.20), RY(90.0)):
        p.cap_disc(0.05, 0.0, "Screen", seg=8)


def pressure_lights(rm, XI):
    """Three pressure lights over the inner door on both faces: 8 cm lamps (objects PressureLight_0..2, StatusGreen)
    on a dark plate (object PressurePlateTop: the "...Top" rule hides it with the roof in the cutaway)."""
    L = _links()
    zc = L.DOOR_TOP + 0.22
    ro = P("PressurePlateTop")
    for (xf, fc) in ((XI + L.HX[0], -1), (XI + L.HX[1], 1)):
        x0, x1 = sorted((xf, xf + fc * 0.02))
        bbox(ro, x0, x1, -0.26, 0.26, zc - 0.07, zc + 0.07, "Rubber")
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [ro]
    for i, yy in enumerate((-0.16, 0.0, 0.16)):
        p = P("PressureLight_%d" % i)
        for (xf, fc) in ((XI + L.HX[0], -1), (XI + L.HX[1], 1)):
            with p.at(T(xf + fc * 0.02, yy, zc), RY(90.0 * fc)):
                p.vcyl(0, 0, 0.0, 0.03, 0.04, seg=10, mat="StatusGreen", cap0=False)
        rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [p]


def airlock(rm):
    fu = furniture_of(rm)
    L = _links()
    XO, XI, ch_len, riders = layout(rm)
    plan = Plan(rm, clear=0.40, item_depth=0.40)
    IK.build_floor_v3(rm, "panel", "grid", grid=0.8)
    n = plan.n
    ro = rm.roof
    Rw, Ri = rm.Rw, rm.Ri
    xa, xb = XI + L.HX[1], XO + L.HX[0]               # the chamber floor
    # ---- the inner door kit in its partition, the pressure lights over it
    door_kit(rm, XI, n, ro, "Inner")
    pressure_lights(rm, XI)
    plan.rect(XI - 0.26, 0.0, 0.30, L.HY, 0.0, tag="partition")
    # ---- chamber side walls (a window on +Y to the suit room), grating, vents, pumps, a gauge panel
    for sy in (-1, 1):
        y0, y1 = sorted((sy * CH_HW, sy * (CH_HW + 0.10)))
        chamber_wall(n, ro, y0, y1, xa, xb, window=(xa + 0.55, xa + 1.25, 0.95, 1.75) if sy > 0 else None)
        plan.rect(0.5 * (xa + xb), sy * (CH_HW + 0.05), 0.5 * (xb - xa), 0.07, 0.0, tag="chamber")
    bbox(n, xa, xb, -CH_HW, CH_HW, F - 0.02, F + 0.004, "FloorDark", mats={"-z": None})
    for j in range(int((xb - xa) / 0.12)):
        x = xa + 0.06 + 0.12 * j
        bbox(n, x - 0.015, x + 0.015, -CH_HW + 0.04, CH_HW - 0.04, F + 0.004, F + 0.02, "Frame", mats={"-z": None})
    for sy in (-1, 1):
        FU.floor_line(n, xa + 0.05, sy * (CH_HW - 0.06), xb - 0.05, sy * (CH_HW - 0.06), w=0.06, mat="Hazard",
                      z=F + 0.022)
        for xv in ([xa + 0.45, xb - 0.45] + ([0.5 * (xa + xb)] if ch_len > 3.0 else [])):
            vent_grille(n, xv, sy * CH_HW, F + 0.20, -sy)
        # pumps outside the chamber, in the suit room beside it, where they fit
        px = xb - 0.35
        if hypot(px, CH_HW + 0.45) < Ri - 0.05:
            pump_housing(n, px, sy * (CH_HW + 0.10), sy)
            plan.rect(px, sy * (CH_HW + 0.21), 0.30, 0.13, 0.0, tag="pump")
    gauge_panel(n, xa + 0.30, -CH_HW, 1)
    # ---- the chamber light (object ChamberLight): strips at 1.2 m and a lamp on the wall
    cl = P("ChamberLight")
    for sy in (-1, 1):
        plate_y(cl, sy * (CH_HW - 0.004), xa + 0.10, xb - 0.10, F + 1.18, F + 1.23, "StatusGreen", facing=-sy)
    cl.vcyl(0.5 * (xa + xb), -(CH_HW + 0.05), WALL_TOP - 0.18, WALL_TOP - 0.02, 0.07, seg=8, mat="BeaconAmber")
    rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [cl]
    # ---- rider places in the chamber, 0.8 m apart, facing the outer door
    xs = 0.5 * (xa + xb)
    if riders <= 2:
        pts = [(xs - 0.40, 0.0), (xs + 0.40, 0.0)][:riders]
    else:
        pts = [(xs - 0.60, -0.40), (xs - 0.60, 0.40), (xs + 0.60, -0.40), (xs + 0.60, 0.40)][:riders]
    for (x, y) in pts:
        plan.anchor("Chamber", x, y, 0.0)
    plan.rect(xs, 0.0, 0.5 * (xb - xa), CH_HW, 0.0, tag="chamberfloor")
    # ---- suit room: suit racks (Tall) on the -X wall, a bench, refill ports and lockers on the wall
    nr = max(3, riders + 1)
    span = 50.0 if nr <= 3 else 72.0
    racks = [(180.0 - span / 2 + span * k / (nr - 1), k) for k in range(nr)]
    for a, k in racks:
        r = Ri - 0.30
        x, y = r * cos(radians(a)), r * sin(radians(a))
        tp = plan.tall(x, y)
        with at(tp, x, y, a + 180.0):
            with tp.at(T(-0.26, 0, 0)):
                FU.wi_suitrack(tp, w=0.7)
        plan.rect(x, y, 0.25, 0.36, a, tag="suit")
        if k < riders:
            sx_, sy_ = (r - 0.75) * cos(radians(a)), (r - 0.75) * sin(radians(a))
            plan.anchor("Suit", sx_, sy_, a)
    # (RENDER 2026-09-25) the bench is a WALL item now (0.36 m deep, hides with its wall segment at a doorway):
    # the free-standing bench stood in the door lanes of the suit room
    def near_housing_end(k):
        # critic round 13 (airlock 49, 259.5 deg): no wall item beside the ends of the inner door housing, so a
        # body from a doorway there walks round the housing end into the suit room on free floor
        am = radians(IK.seg_mid(k))
        wx, wy = Ri * cos(am), Ri * sin(am)
        return min(hypot(wx - (XI - 0.26), wy - sy * L.HY) for sy in (-1, 1)) < 1.15
    ws = wall_set(plan, {"refill": lambda p, w, d, k: refill_port(p, w=w, seed=k),
                         "bench": lambda p, w, d, k: wall_bench(p, w=min(w, 1.1), d=min(d, 0.36))})
    a_door = degrees(asin(min(0.99, L.HY / Rw))) + 6.0
    lo_rack, hi_rack = 180.0 - span / 2 - 12.0, 180.0 + span / 2 + 12.0
    plan.wall_items(["bench", "refill", "lockers", "refill", "panel", "lockers"], ws, open_every=0, seed=171,
                    depth_of=dict(DEPTHS, refill=0.20, bench=0.36),
                    skip=[k for k in range(32) if IK.seg_mid(k) < a_door + 30.0 or IK.seg_mid(k) > 330.0 - a_door
                          or lo_rack < IK.seg_mid(k) < hi_rack or near_housing_end(k)])
    plan.stands(fu["stands"], [(XI - 0.95, 0.9, 0.0), (XI - 1.0, 0.0, 0.0), (XI - 1.1, -0.6, 0.0)])
    plan.lights([(XI - 1.0, 0.0), (xs, 0.0)], z=2.2)
    # the aisle graph (join points closer than 1.75 m): outer door - chamber - inner door - suit room ring
    pts = [(xb - 0.35, 0.0), (xs, 0.0), (xa + 0.35, 0.0), (XI - 0.85, 0.0), (XI - 1.35, 0.75), (XI - 1.45, -0.55),
           (XI - 0.6, 1.5), (XI - 0.6, -1.6)]
    for k in range(1, 6):
        x = XI + (xb - XI) * k / 6.0
        for sy in (-1, 1):
            y = sy * (CH_HW + 0.55)
            pts.append((x, y))
    for (x, y) in pts:
        if plan.dist(x, y) >= 0.20 and hypot(x, y) < Ri - 0.30:
            plan.anchor("Aisle", x, y, degrees(atan2(y, x)) + 90.0)
    clamp_cutaway(rm)


CUT_VISIBLE = ("Interior", "Tall_")


def clamp_cutaway(rm):
    """Critic round 13: nothing of the airlock that the game's cutaway shows may stand above WALL_TOP.  Wall items,
    Tall parts and Interior pieces that reach a few cm over 1.40 m (suit racks, refill ports) are pressed down to
    1.40 m (vertex z clamp; the tops stay flat)."""
    parts = list(rm.walls) + [q for q in getattr(rm, "extra_parts", []) if q.name.startswith(CUT_VISIBLE)] +         [rm.interior]
    for q in parts:
        for v in q.verts:
            if v.z > WALL_TOP:
                v.z = WALL_TOP
