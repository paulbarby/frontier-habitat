"""
Frontier Habitat 2.0 - ART-A room builders: habitat family (domes and drums).
habitat, lounge, cantina, medical, bio_lab, storehouse, cold_storage.
Each builder gets a rooms_kit.Room (size index 0..3 = S, M, L, XL; radius from content/buildings.json).
"""
import math
import random
from math import sin, cos, radians, degrees, hypot, asin, atan2, sqrt
from mathutils import Vector

import rooms_kit as K
from rooms_kit import (T, RX, RY, RZ, S, polar, dome_profile, frame_m, columns, reg_angles, ang_diff, porthole, lamp,
                       antenna, vent_box, fan_unit, capsule, tank_v, pipe, screen, bolts_ring, rail_ring, rail_line,
                       ladder, dome_band, drum_band, crown_teeth, lv_module, lv_fins, lv_annex, lv_beacon, lv_emblem,
                       lv_collar_dome, levels_dome, levels_podium, bunk, bunk_double, locker, table_round,
                       table_rect, stool, chair, console, cabinet, crate, plant_pot, rug_disc, floor_ring_mark,
                       shelf_rack, workbench, radial_fit, tangent_fit, FLOOR_Z, WALL_TOP)

F = FLOOR_Z


def spread(n, skip=None, phase=0.5, gap=12.0):
    """n angles around the circle, skipping those near `skip` = (angle, half width)."""
    out = []
    for k in range(n):
        a = 360.0 * (k + phase) / n
        if skip is not None and ang_diff(a, skip[0]) < skip[1] + gap:
            continue
        out.append(a)
    return out


def wall_portholes(rm, n, r=0.17, z=0.62, phase=0.5):
    if getattr(rm, "v3", False):
        # 3.0: portholes at wall-segment centres, inside their segment (they hide with it)
        import interior_kit as IK
        ks = sorted({IK.seg_of(360.0 * (k + phase) / n) for k in range(n)})
        for k in ks:
            a = IK.seg_mid(k)
            porthole(rm.walls[k], Vector(polar(rm.Rw + 0.005, a, z)), Vector(polar(1.0, a, 0.0)), r, rim=0.06,
                     depth=0.05)
        return
    for a in spread(n, (0.0, rm.door_half), phase=phase, gap=8.0):
        porthole(rm.base, Vector(polar(rm.Rw + 0.005, a, z)), Vector(polar(1.0, a, 0.0)), r, rim=0.06, depth=0.05)


def dome_portholes(rm, t, n, r, phase=0.5, skip_door=True, part=None):
    for a in spread(n, (0.0, 14.0) if skip_door else None, phase=phase, gap=4.0):
        pos, nor = rm.dpt(t, a)
        porthole(part or rm.roof, pos, nor, r, rim=0.08, depth=0.08)


def roof_vent(p, x, y, z, r=0.16, cap="Accent"):
    p.vcyl(x, y, z - 0.2, z + 0.35, r, seg=6, mat="Frame", cap0=False, cap1=False)
    with p.at(T(x, y, z + 0.33)):
        p.lathe([(r * 1.9, 0.0), (r * 1.9, 0.05), (0.0, 0.17)], lambda k, i: "Frame" if k == 0 else cap, seg=6)
        p.cap_disc(r * 1.9, 0.0, "Frame", seg=6, up=False)


# --------------------------------------------------------------------------------------
# stepped dome: lower dome + a second-deck drum ring + an upper dome with a skylight (Roof)
# --------------------------------------------------------------------------------------
def stepped_dome(rm, He, T1, drum_h, setback=0.25, up_ratio=0.42, windows=True, win_mat="Window", sky=True,
                 seams=8, hseams=(20.0,), up_seams=8):
    rm.build_dome(He, ts=[t for t in (0, 8, 17, 27, 36) if t < T1 - 3] + [T1], crown="open", seams=seams,
                  hseams=hseams)
    r1, z1 = rm.dome_rz(T1)
    rd = r1 - setback
    z2 = z1 + drum_h
    ro = rm.roof
    seg = rm.seg
    wz0, wz1 = z1 + 0.30, z1 + drum_h - 0.30
    nwin = max(10, int(2 * math.pi * rd / 1.9))
    cols, kind, _ = columns(seg, [360.0 * (k + 0.5) / nwin for k in range(nwin)] if windows else [],
                            seam_w=degrees(0.09 / rd))
    prof = [(r1 + 0.02, z1 - 0.02), (rd, z1 - 0.02), (rd, wz0), (rd, wz1), (rd, z2), (rd + 0.10, z2 + 0.06),
            (rd - 0.02, z2 + 0.16)]
    mats = ["Frame", "Hull", "WIN", "Hull", "Accent", "Frame"]

    def m(k, i):
        mm = mats[k]
        if mm == "WIN":
            return "Frame" if kind[i] == "s" else win_mat
        return mm
    ro.lathe_a(prof, cols, m)
    # upper dome with meridian seams
    b = rd * up_ratio
    zc = z2 + 0.16
    tcrown = 70.0 if sky else 88.0
    ts = [0, 20, 40, tcrown]
    ucols, ukind, _ = columns(max(16, seg * 3 // 4 // 4 * 4), [22.5 + 360.0 * k / up_seams for k in range(up_seams)],
                              seam_w=1.4)
    uprof = [((rd - 0.02) * cos(radians(t)), zc + b * sin(radians(t))) for t in ts]
    ro.lathe_a(uprof, ucols, lambda k, i: "HullDark" if ukind[i] == "s" else "Hull")
    rc, zt = uprof[-1]
    top = zt
    if sky:
        cs = max(12, seg // 2 // 4 * 4)
        ro.lathe([(rc + 0.08, zt - 0.10), (rc + 0.08, zt + 0.12), (rc - 0.08, zt + 0.15)], "Frame", seg=cs)
        rr = rc - 0.08
        with ro.at(T(0, 0, zt + 0.05)):
            ro.lathe([(rr, 0.10), (rr * 0.7, rr * 0.36), (0.0, rr * 0.48)], "Glass", seg=cs)
        for k in range(2):
            with ro.at(RZ(90.0 * k)):
                pts = [Vector((-rr, 0, zt + 0.15)), Vector((-rr * 0.55, 0, zt + 0.05 + rr * 0.40)),
                       Vector((0.0, 0, zt + 0.06 + rr * 0.48)), Vector((rr * 0.55, 0, zt + 0.05 + rr * 0.40)),
                       Vector((rr, 0, zt + 0.15))]
                ro.beam_path(pts, 0.05, 0.05, "Frame")
        top = zt + 0.06 + rr * 0.48
    rm.top_z = max(rm.top_z, top)
    rm.rooms_hi.append((lambda x, y, rd=rd: hypot(x, y) < rd - 0.05, z2 - 0.05))
    return dict(r1=r1, z1=z1, rd=rd, z2=z2, zc=zc, b=b, rc=rc, zt=zt, top=top)


def upper_dome_point(info, t, a, off=0.0):
    rd, b, zc = info["rd"] - 0.02, info["b"], info["zc"]
    tr, ar = radians(t), radians(a)
    p = Vector((rd * cos(tr) * cos(ar), rd * cos(tr) * sin(ar), zc + b * sin(tr)))
    n = Vector((b * cos(tr) * cos(ar), b * cos(tr) * sin(ar), rd * sin(tr))).normalized()
    return p + n * off, n


def mezzanine(rm, r0, r1, zm, posts=8, ladder_a=None):
    """Ring deck inside (Interior) with a rail on the inner edge, posts and a ladder."""
    n = rm.interior
    ang = reg_angles(max(16, rm.seg * 3 // 4 // 4 * 4))
    n.lathe_a([(r1, zm - 0.14), (r1, zm), (r0, zm), (r0, zm - 0.14)], ang,
              lambda k, i: ("Frame", "HullDark", "Frame")[k], smooth=False)
    rail_ring(n, r0 + 0.06, zm, h=0.95, seg=len(ang), posts=max(8, len(ang) // 3), mat="Frame")
    for k in range(posts):
        a = 360.0 * (k + 0.5) / posts
        x, y, _ = polar(r0 + 0.25, a)
        n.box0(x, y, F, 0.14, 0.14, zm - 0.14 - F, "Frame", mats={"-z": None, "+z": None})
    if ladder_a is not None:
        with n.at(RZ(ladder_a)):
            ladder(n, r0 - 0.10, 0.0, F, zm + 0.9, yaw=0.0, w=0.5, mat="Metal")
            n.box0(r0 - 0.40, 0.0, F, 0.6, 0.9, 0.012, "Hazard", mats={"-z": None})


def water_tap(n, a, Ri):
    x = tangent_fit(Ri, 0.2, 0.25, 0.05)
    with n.at(RZ(a), T(x, 0, 0)):
        n.box0(0, 0, F, 0.4, 0.5, 1.05, "Hull", mats={"-z": None})
        n.vcyl(-0.05, 0, F + 1.05, F + 1.42, 0.13, seg=8, mat="WaterBlue", cap0=False)
        n.box((-0.21, 0, F + 0.85), (0.04, 0.08, 0.05), "Metal", mats={"+x": None})


# --------------------------------------------------------------------------------------
# HABITAT: dome with portholes; L and XL add a second deck ring and a skylight
# --------------------------------------------------------------------------------------
def build_habitat(rm):
    s = rm.size
    R, Rw, Ri = rm.R, rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0) if s else (), bolts=s >= 2)
    wall_portholes(rm, (4, 7, 7, 9)[s])
    n = rm.interior
    rb = radial_fit(Ri, 1.08, 0.46)
    if s <= 1:
        H = (3.6, 4.5)[s]
        rm.build_dome(H, crown="hatch", seams=8, hseams=() if s == 0 else None)
        dome_portholes(rm, 32.0, (5, 7)[s], (0.30, 0.36)[s])
        rm.door_hood(depth=0.9 if s == 0 else 1.1)
        if s == 1:
            for a in (150.0, 210.0):
                pos, _ = rm.dpt(58.0, a)
                roof_vent(rm.roof, pos.x, pos.y, pos.z)
        levels_dome(rm, dict(band3=(41.0, 44.0), band4=(14.0, 17.0), mod3=(58.0, -62.0), fins4=(45.0, 120.0),
                             annex4=(20.0, -80.0) if s else (21.0, -95.0), ant=(55.0, -125.0, 1.3),
                             emblem5=(50.0, -8.0)))
        # ---- interior: radial beds, lockers, table, tap ----------------------------------
        nb = (4, 8)[s]
        angs = [360.0 * (k + 0.5) / nb + (22.5 if nb == 4 else 0.0) for k in range(nb)]
        for a in angs:
            with n.at(RZ(a), T(rb, 0, 0)):
                bunk(n)
        xl = tangent_fit(Ri, 0.23, 0.31, 0.05)
        for k, a in enumerate(angs):
            a2 = a + 180.0 / nb
            if ang_diff(a2, 0.0) < 16 or (nb == 4 and k == 3):
                continue
            with n.at(RZ(a2), T(xl, 0, 0)):
                locker(n, w=0.6, d=0.45, h=1.75)
        table_round(n, 0.0, 0.0, (0.62, 0.8)[s], 0.74)
        for k in range((4, 6)[s]):
            x, y, _ = polar((0.95, 1.18)[s], 360.0 * k / (4, 6)[s] + 30.0)
            stool(n, x, y)
        rug_disc(n, (1.35, 1.75)[s], mat="Fabric")
        water_tap(n, -26.0 if s else -30.0, Ri)
        if s == 1:
            plant_pot(n, *polar(Ri - 0.45, 26.0)[:2], r=0.3)
    else:
        He = (5.1, 5.7)[s - 2]
        T1 = 41.0
        info = stepped_dome(rm, He, T1, (1.35, 1.5)[s - 2], setback=0.28, up_ratio=0.40, sky=True, seams=8,
                            hseams=(18.0,))
        dome_portholes(rm, 27.0, (7, 9)[s - 2], (0.36, 0.40)[s - 2], phase=0.5)
        rm.door_hood(depth=1.3)
        rd, z1, z2 = info["rd"], info["z1"], info["z2"]
        if s == 3:
            for a in (135.0, 225.0):
                x, y, _ = polar(info["rd"] + 0.14, a)
                roof_vent(rm.roof, x, y, z1 + 0.15)
        # levels
        L = rm.L
        lv_collar_dome(rm, 3.0, 10.0, bolts=s == 3)
        pos, _ = rm.dpt(34.0, -130.0)
        antenna(L[2], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, 1.6)
        dome_band(rm, L[3], 12.0, 15.0, 0.02, "L3Band", top_edge=False)
        pos, _ = rm.dpt(33.0, -52.0)
        lv_module(L[3], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, yaw=-52.0 + 90.0, w=1.5, d=1.0, h=0.6)
        drum_band(L[4], rd, z1 + 1.02, z1 + 1.10, 0.02, "L4Band", seg=rm.seg, top_edge=False)
        pos, _ = rm.dpt(31.0, 120.0)
        lv_fins(L[4], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, yaw=120.0, n=6, h=1.0, length=1.0)
        pos, _ = rm.dpt(19.0, -88.0)
        lv_annex(L[4], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.05, yaw=2.0, L=2.2, r=0.5)
        drum_band(L[5], rd + 0.10, z2 + 0.02, z2 + 0.14, 0.08, "L5Gold", seg=rm.seg)
        crown_teeth(L[5], rd + 0.16, z2 + 0.12, n=12, h=0.28)
        pb, _ = upper_dome_point(info, 52.0, -45.0)
        lv_beacon(rm, L[5], pb.x, pb.y, pb.z - 0.05, h=0.9)
        pe, ne = upper_dome_point(info, 26.0, -18.0, off=0.03)
        lv_emblem(L[5], pe, ne, size=1.3, xdir=(0, 0, 1))
        # ---- interior: bunks on the ground ring, beds on the mezzanine, table under the skylight ----
        zm = 2.55
        r_in = (1.9, 2.2)[s - 2]
        mezzanine(rm, r_in, rd - 0.08, zm, posts=(8, 10)[s - 2], ladder_a=205.0)
        ng = (5, 7)[s - 2]
        angs = spread(ng + 1, (0.0, rm.door_half), gap=6.0)[:ng]
        for a in angs:
            with n.at(RZ(a), T(rb, 0, 0)):
                bunk_double(n)
        nmz = (4, 8)[s - 2]
        for k in range(nmz):
            a = 360.0 * (k + 0.5) / nmz + 10.0
            if ang_diff(a, 205.0) < 25.0:
                a += 30.0
            with n.at(RZ(a), T(rd - 1.2, 0, zm - F)):
                bunk(n)
        xl = tangent_fit(Ri, 0.23, 0.31, 0.05)
        for k, a in enumerate(angs):
            a2 = a + 360.0 / (ng + 1) / 2.0
            if ang_diff(a2, 0.0) < 16:
                continue
            with n.at(RZ(a2), T(xl, 0, 0)):
                locker(n, w=0.6, d=0.45, h=1.75)
        table_round(n, 0.0, 0.0, 0.9, 0.74)
        for k in range(6):
            x, y, _ = polar(1.3, 60.0 * k + 30.0)
            stool(n, x, y)
        rug_disc(n, r_in - 0.15, mat="Fabric")
        water_tap(n, -24.0, Ri)
        x, y, _ = polar(r_in + 0.9, 80.0)
        plant_pot(n, x, y, r=0.32)


def sofa_arc(n, r_out, a0, a1, seg=5, fabric="Fabric", arm="HullDark"):
    """Curved sofa facing the centre, between angles a0 and a1 (outer radius r_out)."""
    ri = r_out - 0.85
    prof = [(r_out, F), (r_out, F + 0.82), (r_out - 0.26, F + 0.82), (r_out - 0.26, F + 0.44), (ri, F + 0.44), (ri, F)]
    n.lathe(prof, fabric, seg=seg, a0=a0, a1=a1, smooth=False, cap_mat=arm)


def bar_arc(n, r_out, a0, a1, h=1.05, top="Metal", body="HullDark", stripe="Neon", seg=6):
    prof = [(r_out, F), (r_out, F + h), (r_out - 0.62, F + h), (r_out - 0.62, F)]
    n.lathe(prof, lambda k, i: body if k != 1 else top, seg=seg, a0=a0, a1=a1, smooth=False, cap_mat=body)
    n.lathe([(r_out - 0.63, F + h * 0.80), (r_out - 0.63, F + h * 0.72)], stripe, seg=seg, a0=a0, a1=a1,
            smooth=False, caps=False)


# --------------------------------------------------------------------------------------
# LOUNGE: panorama glass dome with curved sofas and planters
# --------------------------------------------------------------------------------------
def build_lounge(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0) if s else (), bolts=s >= 2)
    H = (3.5, 4.1, 4.7, 5.3)[s]

    def dm(t, a):
        if 4.0 < t < (50.0 if s < 2 else 46.0) and ang_diff(a, 0.0) > 15.0:
            return "Glass"
        return "Hull"
    rm.build_dome(H, crown="skylight" if s >= 2 else "hatch", seams=(8, 10, 12, 14)[s], seam_mat="Frame",
                  hseams=(27.0,) if s < 2 else (25.0, 46.0), mat=dm, inset=-0.025,
                  crown_t=(79.0, 78.0, 70.0, 68.0)[s])
    rm.door_hood(depth=0.9)
    # a painted accent ring on the solid cap
    dome_band(rm, rm.roof, 56.0, 58.0, 0.012, "Accent", top_edge=False)
    levels_dome(rm, dict(collar=(2.0, 3.5), band3=(60.0, 62.0), band4=(52.0, 54.0), mod3=(64.0, -70.0),
                         fins4=(62.0, 120.0), annex4=(63.0, 200.0), ant=(64.0, 160.0, 1.2),
                         crown5=(71.0, 74.0) if s < 2 else (63.0, 66.0), emblem5=(62.0, -20.0),
                         mod_size=(0.9 + 0.2 * s, 0.7, 0.45), annex_len=1.3 + 0.2 * s,
                         beacon5="top" if s < 2 else (rm.crown_r * 0.707, -rm.crown_r * 0.707, rm.crown_z + 0.10)))
    n = rm.interior
    rug_disc(n, (1.4, 1.8, 2.2, 2.6)[s], mat="Accent")
    rug_disc(n, (1.1, 1.45, 1.8, 2.15)[s], mat="Fabric")
    if s < 3:
        table_round(n, 0, 0, (0.45, 0.55, 0.65, 0.7)[s], 0.42, top="Hull")
    else:
        # water feature: basin + column
        n.vcyl(0, 0, F, F + 0.45, 1.0, seg=16, mat="HullDark", cap1=False)
        n.cap_disc(0.9, F + 0.40, "WaterBlue", seg=16)
        n.lathe([(1.0, F + 0.45), (0.9, F + 0.45), (0.9, F + 0.40)], "Frame", seg=16, smooth=False)
        n.vcyl(0, 0, F + 0.40, F + 1.3, 0.12, seg=8, mat="Metal")
        n.cap_disc(0.35, F + 1.3, "WaterBlue", seg=8)
    ns = (2, 3, 4, 4)[s]
    r_s = (2.05, 2.6, 3.1, 3.7)[s]
    span = (110.0, 88.0, 66.0, 70.0)[s]
    for k in range(ns):
        c = 360.0 * (k + 0.5) / ns + (0.0 if s != 1 else 60.0)
        sofa_arc(n, r_s, c - span / 2, c + span / 2, seg=4 if s < 2 else 5)
    npl = (2, 3, 4, 6)[s]
    xr = Ri - 0.64
    for k in range(npl):
        a = 360.0 * k / npl + 180.0 / npl + (15.0 if s == 1 else 0.0)
        if ang_diff(a, 0.0) < 20:
            a += 25.0
        x, y, _ = polar(xr, a)
        plant_pot(n, x, y, r=(0.30, 0.34, 0.38, 0.40)[s], big=s >= 1)
    if s >= 1:
        bar_arc(n, Ri - 0.08, 150.0, 150.0 + (34.0, 30.0, 34.0)[s - 1], seg=4)
        for k in range(2 + (s >= 2)):
            a = 156.0 + 11.0 * k
            x, y, _ = polar(Ri - 1.05, a)
            stool(n, x, y, top="Accent")
    if s >= 2:
        screen(n, *polar(tangent_fit(Ri, 0.05, 0.9, 0.06), 270.0)[:2], F + 1.25, 1.8, 0.9, yaw=90.0, glow="Neon")


# --------------------------------------------------------------------------------------
# CANTINA: dome with a neon sign, a terrace canopy on the roof and a bar counter inside
# --------------------------------------------------------------------------------------
def neon_sign(p, x, y, z, yaw, w=1.6, h=1.0, posts=True):
    """Abstract neon sign (ringed planet + two bars, no text) on a dark board, facing local +X."""
    with p.at(T(x, y, z), RZ(yaw)):
        if posts:
            for sy in (-1, 1):
                p.box0(-0.05, sy * (w / 2 - 0.08), -h * 0.9, 0.08, 0.08, h * 0.9 + 0.05, "Frame", mats={"-z": None})
        p.box((0, 0, h / 2), (0.10, w, h), "Frame")
        p.box((0.055, 0, h - 0.04), (0.012, w, 0.05), "Accent", mats={"-x": None})
        with p.at(T(0.07, -w * 0.18, h * 0.55), RY(90.0)):
            p.torus(h * 0.24, 0.028, "Neon", seg=10, tseg=3)
        with p.at(T(0.08, -w * 0.18, h * 0.55), RX(-20.0), RY(90.0), S(1.0, 1.9, 1.0)):
            p.torus(h * 0.24, 0.022, "Neon", seg=10, tseg=3)
        for k, zz in enumerate((h * 0.62, h * 0.40)):
            p.box((0.07, w * 0.22, zz), (0.03, w * (0.34 - 0.08 * k), 0.05), "Neon")


def build_cantina(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(windows=(0.52, 0.84) if s else None, win_seams=(8, 12, 14, 16)[s], lamps=(150.0, 210.0),
                  bolts=s >= 2)
    H = (3.9, 4.4, 5.0, 5.6)[s]
    tcut = (48.0, 48.0, 46.0, 45.0)[s]
    rm.build_dome(H, ts=[t for t in (0, 10, 22, 35) if t < tcut - 3] + [tcut], crown="open", seams=8,
                  hseams=(20.0,))
    rc, zc = rm.dome_rz(tcut)
    ro = rm.roof
    # terrace deck with an edge rail
    ro.lathe_a([(rc + 0.02, zc - 0.02), (rc + 0.02, zc + 0.06), (0.0, zc + 0.06)], reg_angles(max(16, rm.seg * 2 // 3 // 4 * 4)),
               lambda k, i: "Frame" if k == 0 else "HullDark", smooth=False)
    rail_ring(ro, rc - 0.06, zc + 0.06, h=0.9, seg=max(16, rm.seg * 2 // 3 // 4 * 4), posts=10, mat="Frame")
    rm.top_z = max(rm.top_z, zc + 1.0)
    zt = zc + 0.06
    # canopy (fabric sail on posts) and terrace tables
    ncan = 1 if s < 2 else 2
    for c in range(ncan):
        cx, cy = ((0.0, 0.0),) [0] if ncan == 1 else ((0.0, -rc * 0.42), (0.0, rc * 0.42))[c]
        hw = rc * (0.55 if ncan == 1 else 0.42)
        hd = rc * (0.55 if ncan == 1 else 0.36)
        pz = zt + 2.1
        corners = [(cx - hw, cy - hd), (cx + hw, cy - hd), (cx + hw, cy + hd), (cx - hw, cy + hd)]
        for (px, py) in corners:
            ro.box0(px, py, zt, 0.08, 0.08, 2.05 if (px > cx) else 1.85, "Frame", mats={"-z": None})
        zs = [pz - 0.02, pz - 0.2, pz - 0.2, pz - 0.02]
        zs = [zt + 2.05, zt + 2.05, zt + 1.85, zt + 1.85]
        ro.quad((corners[0][0], corners[0][1], zt + 1.85), (corners[1][0], corners[1][1], zt + 2.05),
                (corners[2][0], corners[2][1], zt + 2.05), (corners[3][0], corners[3][1], zt + 1.85), "Fabric")
        ro.quad((corners[3][0], corners[3][1], zt + 1.83), (corners[2][0], corners[2][1], zt + 2.03),
                (corners[1][0], corners[1][1], zt + 2.03), (corners[0][0], corners[0][1], zt + 1.83), "Accent")
        nt = (1, 3, 2, 3)[s]
        for k in range(nt):
            tx = cx - hw * 0.5 + hw * 1.0 * k / max(1, nt - 1) if nt > 1 else cx
            ty = cy
            ro.vcyl(tx, ty, zt, zt + 0.72, 0.05, seg=4, mat="Frame", cap0=False, cap1=False)
            ro.vcyl(tx, ty, zt + 0.70, zt + 0.74, 0.38, seg=8, mat="Hull")
            for sy in (-1, 1):
                ro.vcyl(tx, ty + sy * 0.6, zt, zt + 0.45, 0.14, seg=6, mat="Accent")
    rm.top_z = max(rm.top_z, zt + 2.1)
    # neon sign on the front of the terrace, second sign for XL
    neon_sign(ro, rc * 0.62, -rc * 0.35, zt + 0.95, -30.0, w=1.2 + 0.2 * s, h=0.8 + 0.1 * s)
    rm.top_z = max(rm.top_z, zt + 1.9 + 0.1 * s)
    if s == 3:
        neon_sign(ro, -rc * 0.7, 0.0, zt + 0.95, 180.0, w=1.6, h=1.0)
    rm.door_hood(depth=0.9)
    # levels: dome bands below the terrace, parts on the terrace
    lv_collar_dome(rm, 3.0, 9.0)
    pos, _ = rm.dpt(tcut - 12.0, 140.0)
    antenna(rm.L[2], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, 1.2 + 0.2 * s)
    dome_band(rm, rm.L[3], 30.0, 32.5, 0.02, "L3Band", top_edge=False)
    pos, _ = rm.dpt(tcut - 14.0, -110.0)
    lv_module(rm.L[3], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, yaw=-20.0, w=0.9 + 0.15 * s, d=0.7, h=0.45)
    dome_band(rm, rm.L[4], 14.0, 16.5, 0.02, "L4Band", top_edge=False)
    pos, _ = rm.dpt(tcut - 14.0, 100.0)
    lv_fins(rm.L[4], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.02, yaw=100.0, n=4 + (s >= 2), h=0.7, length=0.8)
    pos, _ = rm.dpt(27.0, 215.0)
    lv_annex(rm.L[4], pos.x, pos.y, rm.dome_z(pos.x, pos.y) - 0.05, yaw=305.0, L=1.4 + 0.2 * s, r=0.4)
    drum_band(rm.L[5], rc - 0.02, zc - 0.10, zc + 0.08, 0.06, "L5Gold", seg=max(16, rm.seg * 2 // 3 // 4 * 4))
    crown_teeth(rm.L[5], rc + 0.02, zc + 0.07, n=8 + 4 * (s >= 2), h=0.2 + 0.04 * s)
    lv_beacon(rm, rm.L[5], -rc * 0.55, -rc * 0.55, zt, h=0.8 + 0.1 * s)
    pos, nor = rm.dpt(28.0, -40.0, off=0.02)
    lv_emblem(rm.L[5], pos, nor, size=0.8 + 0.15 * s, xdir=(0, 0, 1))
    # interior: bar counter, stools, tables, chairs, a stage ring
    n = rm.interior
    bar_arc(n, Ri - 0.10, 120.0, 120.0 + (50.0, 60.0, 64.0, 70.0)[s], seg=(4, 5, 6, 6)[s])
    nb = (3, 4, 5, 6)[s]
    for k in range(nb):
        a = 124.0 + (50.0, 60.0, 64.0, 70.0)[s] * (k + 0.5) / nb - 4.0
        x, y, _ = polar(Ri - 1.0, a)
        stool(n, x, y)
    with n.at(RZ(145.0 + (50.0, 60.0, 64.0, 70.0)[s] / 2 - 25), T(tangent_fit(Ri, 0.2, 0.9, 0.04), 0, 0)):
        n.box0(0, 0, F, 0.35, 1.8, 1.9, "HullDark", mats={"-z": None})
        for zz in (0.9, 1.35):
            n.box((-0.19, 0, F + zz), (0.02, 1.6, 0.05), "Neon", mats={"+x": None})
    ntab = (2, 4, 6, 8)[s]
    rt = (1.35, 1.8, 2.3, 2.9)[s]
    for k in range(ntab):
        a = 360.0 * (k + 0.5) / ntab + (30.0 if s == 0 else 0.0)
        if ang_diff(a, 150.0) < 40.0:
            continue
        x, y, _ = polar(rt, a)
        table_round(n, x, y, 0.42, 0.74, top="Hull", seg=8)
        for q in (0, 1):
            cx, cy, _ = polar(0.62, a + 90.0 + 180.0 * q)
            chair(n, x + cx, y + cy, yaw=a + 270.0 + 180.0 * q)
    floor_ring_mark(n, 0.55, 0.75, mat="Neon", seg=16)


# --------------------------------------------------------------------------------------
# MEDICAL: white dome, large red cross on the roof, scanner arch inside
# --------------------------------------------------------------------------------------
def med_bed(n):
    """Treatment bed along local X (head at +X), 2.1 x 0.85, monitor at the head.  About 70 triangles."""
    n.box0(0, 0, F, 0.5, 0.5, 0.45, "Frame", mats={"-z": None})
    n.box0(0, 0, F + 0.45, 2.1, 0.85, 0.12, "HullDark", mats={"-z": None})
    n.box0(0.02, 0, F + 0.57, 2.0, 0.78, 0.10, "Hull", mats={"-z": None})
    n.box0(-0.32, 0, F + 0.57, 1.0, 0.80, 0.12, "Accent", mats={"-z": None})
    n.box0(0.78, 0, F + 0.66, 0.32, 0.52, 0.07, "Hull", mats={"-z": None})
    n.box0(1.20, 0.30, F, 0.06, 0.06, 1.45, "Metal", mats={"-z": None})
    n.box((1.20, 0.30, F + 1.55), (0.06, 0.46, 0.34), "Frame")
    n.box((1.165, 0.30, F + 1.55), (0.012, 0.40, 0.28), "Window", mats={"+x": None})


def scanner_arch(n):
    """Half ring over the bed (axis along local X)."""
    axis_x = RY(90.0)
    with n.at(T(0.35, 0, F + 0.45), RY(90.0), RZ(90.0)):
        n.lathe([(0.98, -0.28), (0.98, 0.28), (0.76, 0.28), (0.76, -0.28)],
                lambda k, i: ("Hull", "Hull", "HullDark", "Hull")[k], seg=8, a0=0.0, a1=180.0, smooth=True,
                caps=True, cap_mat="Hull")
        n.lathe([(0.99, -0.07), (0.99, 0.07)], "Neon", seg=8, a0=0.0, a1=180.0, caps=False)
    for sy in (-1, 1):
        n.box0(0.35, sy * 0.87, F, 0.60, 0.24, 0.47, "HullDark", mats={"-z": None})


def blister(p, rm, t, a, rb=1.0, h=0.7, mat="Hull", win="Window"):
    """Small dome pod on the main dome flank (isolation room)."""
    pos, nor = rm.dpt(t, a)
    m = frame_m(pos - Vector((0, 0, 0.25)), (0, 0, 1), (cos(radians(a)), sin(radians(a)), 0))
    with p.at(m):
        p.lathe([(rb, -0.1), (rb, 0.35), (rb * 0.85, 0.35 + h * 0.5), (rb * 0.45, 0.35 + h * 0.9), (0.0, 0.35 + h)],
                mat, seg=10)
        p.box((rb * 0.72, 0, 0.45), (0.40, 0.75, 0.30), win)


def build_medical(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(windows=(0.50, 0.82), win_mat="Frost", win_seams=(10, 12, 14, 16)[s], lamps=(160.0, 200.0),
                  bolts=s >= 2, accent_floor=False)
    H = (3.5, 4.0, 4.6, 5.2)[s]
    rm.build_dome(H, crown="apex", seams=8, hseams=(22.0,) if s < 2 else (20.0, 46.0))
    rm.door_hood(depth=0.9)
    ro = rm.roof
    L_arm, W = 0.58 * Rw, 0.15 * Rw
    ro.drape(-L_arm, L_arm, -W, W, rm.dome_z, "Accent", nx=10 + 2 * s, ny=2, offset=0.035)
    ro.drape(-W, W, W, L_arm, rm.dome_z, "Accent", nx=2, ny=4 + s, offset=0.035)
    ro.drape(-W, W, -L_arm, -W, rm.dome_z, "Accent", nx=2, ny=4 + s, offset=0.035)
    if s >= 2:
        rb = (0.85, 0.95)[s - 2]
        tb = rm.t_at_r(Rw - rb - 0.12)
        for a in ((45.0, 225.0) if s == 2 else (45.0, 135.0, 225.0, 315.0)):
            blister(ro, rm, tb, a, rb=rb, h=0.8)
    levels_dome(rm, dict(band3=(33.0, 35.0), band4=(12.0, 14.0), mod3=(52.0, -45.0 if s < 2 else -20.0),
                         fins4=(48.0, 135.0 if s != 2 else 110.0), annex4=(22.0, -100.0 if s < 2 else -90.0),
                         ant=(50.0, 225.0, 1.2), crown5=(44.0, 47.0), emblem5=(40.0, -60.0 if s < 2 else -45.0),
                         beacon5=(0.0, 0.0, rm.dome_z(0, 0) + 0.02)))
    n = rm.interior
    nb = (1, 2, 4, 6)[s]
    rb_ = radial_fit(Ri, 1.28, 0.45) - 0.05
    angs = [180.0] if nb == 1 else [360.0 * (k + 0.5) / nb + 90.0 for k in range(nb)]
    for k, a in enumerate(angs):
        with n.at(RZ(a), T(rb_, 0, 0)):
            med_bed(n)
            if k == 0 and s >= 1:
                scanner_arch(n)
    if s == 0:
        with n.at(RZ(0.0), T(0.1, 0, 0)):
            scanner_arch(n)
    xc = tangent_fit(Ri, 0.3, 0.95, 0.05)
    for a in ((270.0,) if s == 0 else (60.0, 300.0) if s == 1 else (0.0 + 40.0, 320.0, 180.0)):
        with n.at(RZ(a), T(xc, 0, 0)):
            cabinet(n, w=1.8 if s else 1.4, d=0.55, h=1.7, stripe="Accent")
    with n.at(RZ(125.0 if s else 110.0), T(tangent_fit(Ri, 0.27, 0.55, 0.05), 0, 0)):
        n.box0(0, 0, F, 0.55, 1.0, 0.85, "Hull", mats={"-z": None})
        n.box((0, 0, F + 0.86), (0.36, 0.62, 0.02), "WaterBlue")
    if s >= 1:
        with n.at(T(0.0, 0.0, 0.0), RZ(-90.0)):
            console(n, w=1.0, glow="Window")
    n.box((0, 0, F + 0.006), (1.1, 0.34, 0.012), "Accent", mats={"-z": None})
    n.box((0, 0, F + 0.007), (0.34, 1.1, 0.012), "Accent", mats={"-z": None})


# --------------------------------------------------------------------------------------
# BIO-LAB: cluster of white pods on the round base, green cross, fume stack
# --------------------------------------------------------------------------------------
def pod(p, cx, cy, z0, rp, wall_h=0.65, mat="Hull", band="Accent", win="Window", seg=12, flat_top=False,
        ports=(40.0, 160.0, 280.0)):
    prof = [(rp, z0), (rp, z0 + wall_h * 0.45), (rp + 0.03, z0 + wall_h * 0.5), (rp + 0.03, z0 + wall_h * 0.7),
            (rp, z0 + wall_h * 0.75), (rp, z0 + wall_h)]
    mats = [mat, band, band, band, mat]
    ts = (25.0, 50.0, 72.0)
    for t in ts:
        prof.append((rp * cos(radians(t)), z0 + wall_h + rp * 0.72 * sin(radians(t))))
        mats.append(mat)
    top = z0 + wall_h + rp * 0.72 * sin(radians(72.0))
    if flat_top:
        prof.append((0.0, top))
        mats.append("HullDark")
    else:
        prof.append((0.0, z0 + wall_h + rp * 0.72))
        mats.append(mat)
        top = z0 + wall_h + rp * 0.72
    with p.at(T(cx, cy, 0)):
        p.lathe_a(prof, reg_angles(seg), lambda k, i: mats[k])
    for a in ports:
        pos = Vector((cx, cy, 0)) + Vector(polar(rp, a, z0 + wall_h * 0.25))
        porthole(p, pos, Vector(polar(1.0, a, 0.0)), 0.16, rim=0.05, depth=0.05, seg=6)
    return top


def build_bio_lab(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0), bolts=s >= 2)
    D = 2.25
    rm.build_podium(D, ribs=(6, 10, 12, 14)[s], band=None, parapet=0.10, deck="HullDark")
    ro = rm.roof
    # pods: (dist, angle, radius)
    rp = (1.35, 1.55, 1.75, 1.9)[s]
    layout = {0: [(1.3, 90.0), (1.3, 270.0)], 1: [(1.75, 90.0), (1.75, 210.0), (1.75, 330.0)],
              2: [(2.55, 60.0), (2.55, 180.0), (2.55, 300.0), (0.0, 0.0)],
              3: [(3.2, 45.0), (3.2, 135.0), (3.2, 225.0), (3.2, 315.0), (0.0, 0.0)]}[s]
    tops = []
    for k, (d, a) in enumerate(layout):
        x, y, _ = polar(d, a)
        main = (k == len(layout) - 1) if s >= 2 else (k == 0)
        wh = 0.65 + (0.55 if main else 0.0)
        rr = rp * (1.08 if main else 1.0)
        tops.append((x, y, pod(ro, x, y, D + 0.02, rr, wall_h=wh, flat_top=main, seg=10 if s == 0 else 12,
                               ports=(300.0, 40.0) if s == 0 else (40.0, 160.0, 280.0)), main))
        # the pods are open to the room below: extra head room under each pod
        rm.rooms_hi.append((lambda qx, qy, x=x, y=y, rr=rr: hypot(qx - x, qy - y) < rr - 0.1, D + wh))
    # green cross on the main pod (flat top) + fume stack
    mx, my, mt, _ = next(t for t in tops if t[3])
    with ro.at(T(mx, my, mt)):
        arm = rp * 0.55
        ro.prism([(-arm, -0.16), (arm, -0.16), (arm, 0.16), (-arm, 0.16)], 0.0, 0.07, "Glow", cap0=False)
        ro.prism([(-0.16, -arm), (0.16, -arm), (0.16, arm), (-0.16, arm)], 0.0, 0.075, "Glow", cap0=False)
    fx, fy, _ = polar(Rw - 0.55, 155.0 if s != 1 else 150.0)
    zf = D + 2.6 + 0.4 * s
    ro.vcyl(fx, fy, D, zf, 0.20, seg=8, mat="Metal", cap0=False, cap1=False)
    ro.vcyl(fx, fy, zf - 0.6, zf - 0.4, 0.23, seg=8, mat="Accent", cap0=False, cap1=False)
    with ro.at(T(fx, fy, zf)):
        ro.lathe([(0.24, -0.02), (0.36, 0.14), (0.0, 0.30)], "Frame", seg=8)
    ro.box0(fx, fy, D, 0.6, 0.6, 0.4, "HullDark", mats={"-z": None})
    rm.anchor("Fume", (fx, fy, zf + 0.3))
    rm.top_z = max(rm.top_z, zf + 0.3, max(t[2] for t in tops))
    # pipes between pods at deck level
    for i in range(len(tops) - 1):
        a, b = tops[i], tops[i + 1]
        pipe(ro, [(a[0], a[1], D + 0.18), (b[0], b[1], D + 0.18)], r=0.08, seg=6, fillet=0.0)
    # levels on the deck
    cfg = {0: dict(ant=(-1.2, -1.6, 1.0), mod3=(1.3, -1.3, 45.0), fins4=(-2.0, 0.6, 90.0), annex4=(1.8, 1.1, 150.0),
                   beacon5=(0.6, -2.2, D), emblem5=(-1.6, -1.0, D + 0.1, 0, 0, 1)),
           1: dict(ant=(-2.4, 1.0, 1.1), mod3=(2.2, -1.9, 45.0), fins4=(-2.6, -0.4, 90.0), annex4=(1.0, 2.6, 180.0),
                   beacon5=(2.9, 0.2, D), emblem5=(0.2, -2.9, D + 0.1, 0, 0, 1)),
           2: dict(ant=(-3.8, 1.2, 1.2), mod3=(3.3, -2.4, 45.0), fins4=(-3.6, -1.3, 90.0), annex4=(2.4, 3.3, 180.0),
                   beacon5=(4.1, 0.4, D), emblem5=(0.6, -3.9, D + 0.1, 0, 0, 1)),
           3: dict(ant=(-5.2, 0.3, 1.3), mod3=(4.8, -1.6, 90.0), fins4=(-0.3, -5.2, 0.0), annex4=(0.2, 5.1, 0.0),
                   beacon5=(5.3, 1.2, D), emblem5=(-2.0, -1.4, D + 0.1, 0, 0, 1))}[s]
    cfg["emblem_size"] = 0.8 + 0.12 * s
    levels_podium(rm, cfg)
    # interior: lab benches with glassware, fume hood, reactor, herb trays, fridge, console
    n = rm.interior
    nbench = (2, 3, 4, 6)[s]
    xb = tangent_fit(Ri, 0.38, 0.9, 0.05)
    for k in range(nbench):
        a = 360.0 * (k + 0.5) / nbench + 40.0
        if ang_diff(a, 0.0) < 22:
            a += 30.0
        with n.at(RZ(a), T(xb, 0, 0)):
            workbench(n, w=1.8, d=0.75, stripe="Accent")
            for j in range(3):
                n.vcyl(-0.1, -0.5 + 0.35 * j, F + 0.87, F + 1.12, 0.07, seg=6, mat="Glass" if j != 1 else "Glow")
    with n.at(RZ(200.0), T(tangent_fit(Ri, 0.4, 0.7, 0.05), 0, 0)):
        n.box0(0, 0, F, 0.8, 1.3, 2.0, "Hull", mats={"-z": None})
        n.box((-0.41, 0, F + 1.25), (0.012, 1.1, 0.7), "Glass", mats={"+x": None})
        n.box((-0.41, 0, F + 0.85), (0.012, 1.1, 0.06), "Accent", mats={"+x": None})
    tank_v(n, 0.0, 0.0, F, 1.1 + 0.2 * s, 0.45 + 0.08 * s, mat="Metal", band="Accent", cap="dome", seg=10, legs=True)
    if s >= 1:
        for k in range(1 + (s >= 2)):
            a = 250.0 + 45.0 * k
            with n.at(RZ(a), T(tangent_fit(Ri, 0.35, 0.75, 0.05), 0, 0)):
                n.box0(0, 0, F, 0.7, 1.5, 0.7, "HullDark", mats={"-z": None})
                n.box0(0, 0, F + 0.7, 0.62, 1.42, 0.06, "Soil")
                for j in range(4):
                    n.sphere((0.0, -0.54 + 0.36 * j, F + 0.92), 0.17, "Plant", seg=5, rings=2, smooth=False)


# --------------------------------------------------------------------------------------
# STOREHOUSE: wide low drum with a loading hatch; L and XL add silos around it
# --------------------------------------------------------------------------------------
def silo(p, x, y, z0, r, h, mat="Hull", band="Accent", seg=10):
    top = tank_v(p, x, y, z0, h, r, mat=mat, band=band, cap="dome", seg=seg, band_z=0.72, band_h=0.26)
    p.vcyl(x, y, top - 0.05, top + 0.12, r * 0.28, seg=6, mat="Frame")
    ladder(p, x + r + 0.05, y, z0 + 0.1, z0 + h, yaw=0.0, w=0.36)
    return top + 0.12


def forklift(n, x, y, yaw):
    with n.at(T(x, y, 0), RZ(yaw)):
        n.box0(0, 0, F + 0.16, 1.4, 0.9, 0.55, "Hazard", mats={"-z": None})
        n.box0(-0.35, 0, F + 0.71, 0.6, 0.8, 0.04, "Frame")
        for sy in (-1, 1):
            n.box0(-0.35, sy * 0.38, F + 0.71, 0.05, 0.05, 1.0, "Frame", mats={"-z": None})
        n.box0(0.78, 0, F + 0.16, 0.10, 0.75, 1.9, "Frame", mats={"-z": None})
        for sy in (-0.25, 0.25):
            n.box0(1.2, sy, F + 0.05, 0.8, 0.10, 0.05, "Metal")
        for sx in (-0.45, 0.45):
            n.cyl((sx, -0.47, F + 0.16), (sx, 0.47, F + 0.16), 0.16, seg=6, mat="Rubber")


def build_storehouse(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(pilasters=(10, 14, 16, 20)[s], lamps=(160.0, 200.0), bolts=s >= 2, door_w=1.8, floor="grate",
                  floor_mat="HullDark")
    D = (2.7, 2.9, 3.1, 3.3)[s]
    rm.build_podium(D, ribs=(10, 14, 16, 20)[s], band="Accent", band_z=D - 0.6, parapet=0.14)
    ro = rm.roof
    # roller shutter look on the door (v2 only: 3.0 rooms have no fake door)
    for k in range(6 if hasattr(rm, "door_x") else 0):
        rm.base.box((rm.Rw + 0.075, 0, 0.25 + 0.18 * k), (0.012, 1.7, 0.025), "Frame", mats={"-x": None})
    # big square cargo hatch
    hs = (1.8, 2.4, 2.8, 3.0)[s]
    hx = 0.0 if s < 2 else -0.3
    ro.box0(hx, 0, D, hs + 0.3, hs + 0.3, 0.22, "Frame", mats={"-z": None})
    for sy in (-1, 1):
        ro.box0(hx, sy * hs / 4, D + 0.22, hs, hs / 2 - 0.04, 0.08, "Accent", mats={"-z": None})
    for sx in (-1, 1):
        for sy in (-1, 1):
            ro.box((hx + sx * (hs / 2 + 0.02), sy * (hs / 2 + 0.02), D + 0.24), (0.30, 0.30, 0.06), "Hazard",
                   mats={"-z": None})
    # davit crane
    cx, cy = hx + hs / 2 + 0.55, -(hs / 2 + 0.55)
    ro.vcyl(cx, cy, D, D + 2.2, 0.12, seg=6, mat="Hazard", cap0=False)
    ro.beam((cx, cy, D + 2.1), (hx + 0.2, cy + hs * 0.55, D + 2.1), 0.12, 0.16, "Hazard")
    ro.vcyl(hx + 0.2, cy + hs * 0.55, D + 1.2, D + 2.05, 0.02, seg=4, mat="Rubber", cap0=False, cap1=False)
    ro.box((hx + 0.2, cy + hs * 0.55, D + 1.15), (0.18, 0.12, 0.14), "Frame")
    rm.top_z = max(rm.top_z, D + 2.3)
    ntop = D + 0.3
    if s >= 2:
        rsi = (0.85, 0.95)[s - 2]
        nsil = (3, 5)[s - 2]
        dist = Rw - rsi - 0.35
        for k in range(nsil):
            a = 180.0 + (360.0 / nsil) * (k - (nsil - 1) / 2.0) * (0.55 if s == 2 else 0.62)
            x, y, _ = polar(dist, a)
            ntop = max(ntop, silo(ro, x, y, D + 0.02, rsi, (2.4, 2.9)[s - 2]))
        rm.top_z = max(rm.top_z, ntop)
    rm.anchor("Hatch", (hx, 0.0, D + 0.3))
    # levels on the deck
    cfg = {0: dict(ant=(-2.4, -1.4, 1.0), mod3=(-2.2, 1.2, 90.0), fins4=(1.8, 1.8, 45.0), annex4=(-0.2, 2.6, 0.0),
                   beacon5=(1.6, -2.3, D), emblem5=(-1.6, -2.0, D + 0.03, 0, 0, 1)),
           1: dict(ant=(-3.8, -1.6, 1.1), mod3=(-3.4, 1.6, 90.0), fins4=(2.6, 2.6, 45.0), annex4=(-0.4, 3.9, 0.0),
                   beacon5=(2.5, -3.3, D), emblem5=(-2.1, -3.3, D + 0.03, 0, 0, 1)),
           2: dict(ant=(3.9, 3.4, 1.2), mod3=(4.4, -2.6, 60.0), fins4=(2.6, 4.6, 30.0), annex4=(0.6, -5.4, 0.0),
                   beacon5=(5.4, 0.9, D), emblem5=(2.2, -3.8, D + 0.03, 0, 0, 1)),
           3: dict(ant=(5.2, 3.6, 1.3), mod3=(5.6, -2.8, 60.0), fins4=(3.0, 5.8, 30.0), annex4=(1.4, -6.6, 0.0),
                   beacon5=(6.6, 1.0, D), emblem5=(3.0, -4.6, D + 0.03, 0, 0, 1))}[s]
    cfg["emblem_size"] = 0.9 + 0.15 * s
    levels_podium(rm, cfg)
    # interior: racks along the wall, crates on pallets, forklift
    n = rm.interior
    nr = (4, 6, 8, 10)[s]
    xr = tangent_fit(Ri, 0.28, 0.95, 0.05)
    for k in range(nr):
        a = 360.0 * (k + 0.5) / nr + 180.0 / nr
        if ang_diff(a, 0.0) < 22:
            continue
        with n.at(RZ(a), T(xr, 0, 0)):
            shelf_rack(n, w=1.8, d=0.55, h=min(2.0, D - 0.45), levels=4, fill=0.7, seed=k + 3 * s)
    rng = random.Random(21 + s)
    npal = (2, 4, 6, 8)[s]
    for k in range(npal):
        a = 360.0 * (k + 0.5) / npal + 20.0
        rr = (1.4, 2.2, 2.9, 3.6)[s] * (0.8 + 0.2 * (k % 2))
        x, y, _ = polar(rr, a)
        with n.at(T(x, y, 0), RZ(a)):
            n.box0(0, 0, F, 1.2, 1.0, 0.12, "Frame", mats={"-z": None})
            crate(n, -0.28, -0.22, s=0.5, z=F + 0.12, mat=rng.choice(("Cargo", "Hull")), band="Accent")
            crate(n, 0.28, 0.2, s=0.5, z=F + 0.12, band="Frame")
            if k % 2 == 0:
                crate(n, 0.0, 0.0, s=0.45, z=F + 0.62, mat="Cargo", band="Accent")
    if s >= 1:
        forklift(n, 0.6, -0.9, 30.0)


# --------------------------------------------------------------------------------------
# COLD STORAGE: frosted drum with radiator fins and a heavy insulated door
# --------------------------------------------------------------------------------------
def build_cold_storage(rm):
    s = rm.size
    Rw, Ri = rm.Rw, rm.Ri
    rm.build_base(lamps=(160.0, 200.0), bolts=s >= 2, door_w=1.6, floor_mat="Frost", accent_floor=True)
    # insulated door: frost padding and heavy hinges over the standard slab
    b = rm.base
    if hasattr(rm, "door_x"):
        x1 = rm.door_x[1]
        b.box((x1 - 0.02, 0, 0.72), (0.06, 1.46, 1.16), "Frost", mats={"-x": None})
        for sy in (-1, 1):
            for zz in (0.45, 1.05):
                b.box((x1 + 0.01, sy * 0.66, zz), (0.08, 0.10, 0.16), "Metal", mats={"-x": None})
    D = (2.5, 2.7, 3.0, 3.2)[s]
    rm.build_podium(D, wall="Frost", ribs=(10, 12, 16, 18)[s], rib_mat="Trim", band="Accent", band_z=D - 0.55,
                    parapet=0.12, deck="HullDark")
    ro = rm.roof
    # radiator fin ring on the deck edge
    nf = (8, 14, 18, 22)[s]
    for k in range(nf):
        a = 360.0 * (k + 0.5) / nf
        if ang_diff(a, 0.0) < 18:
            continue
        with ro.at(RZ(a), T(Rw - 0.55, 0, D)):
            ro.box0(0, 0, 0, 0.7, 0.05, 0.9, "Metal", mats={"-z": None})
    ro.lathe_a([(Rw - 0.2, D + 0.9), (Rw - 0.2, D + 0.98), (Rw - 0.9, D + 0.98), (Rw - 0.9, D + 0.9)],
               reg_angles(max(16, rm.seg * 2 // 3 // 4 * 4)), "Frame", smooth=False)
    # compressor fans (and an upper drum on L / XL)
    if s >= 2:
        r2 = Rw * 0.5
        z2 = D + 1.3
        ro.lathe_a([(r2, D), (r2, z2), (r2 + 0.06, z2), (r2 + 0.06, z2 + 0.12), (0.0, z2 + 0.12)],
                   reg_angles(max(16, rm.seg // 2 // 4 * 4)), lambda k, i: ("Frost", "Frame", "Frame", "HullDark")[k])
        for k in range(4 if s == 2 else 6):
            a = 360.0 * (k + 0.5) / (4 if s == 2 else 6)
            with ro.at(RZ(a), T(r2 - 0.02, 0, D + 0.1)):
                ro.box0(0.04, 0, 0, 0.1, 0.5, 1.1, "Trim", mats={"-z": None, "-x": None})
        for k in range(2 if s == 2 else 3):
            x, y, _ = polar(r2 * 0.5, 120.0 * k + 30.0)
            fan_unit(ro, x, y, z2 + 0.12, 0.45 if s == 2 else 0.5)
        rm.top_z = max(rm.top_z, z2 + 0.4)
    else:
        for k in range(2):
            x, y, _ = polar(Rw * 0.36, 90.0 + 180.0 * k)
            ro.box0(x, y, D, 1.1, 1.1, 0.35, "HullDark", mats={"-z": None})
            fan_unit(ro, x, y, D + 0.35, 0.42)
        rm.top_z = max(rm.top_z, D + 0.6)
    cfg = {0: dict(ant=(-1.6, -1.2, 1.0), mod3=(0.3, -1.5, 0.0), fins4=(-1.5, 0.9, 90.0), annex4=(0.3, 1.8, 0.0),
                   beacon5=(1.5, 0.0, D), emblem5=(-0.2, 0.0, D + 0.03, 0, 0, 1)),
           1: dict(ant=(-2.4, -1.4, 1.1), mod3=(0.4, -2.3, 0.0), fins4=(-2.2, 1.2, 90.0), annex4=(0.4, 2.5, 0.0),
                   beacon5=(2.3, 0.0, D), emblem5=(-0.3, 0.0, D + 0.03, 0, 0, 1)),
           2: dict(ant=(-3.6, -1.4, 1.2), mod3=(1.2, -3.4, 0.0), fins4=(-3.2, 1.6, 90.0), annex4=(1.0, 3.5, 0.0),
                   beacon5=(0.0, 0.0, D + 1.42), emblem5=(3.4, 0.9, D + 0.03, 0, 0, 1)),
           3: dict(ant=(-4.4, -1.7, 1.3), mod3=(1.6, -4.2, 0.0), fins4=(-4.1, 1.9, 90.0), annex4=(1.3, 4.3, 0.0),
                   beacon5=(0.0, 0.0, D + 1.42), emblem5=(4.3, 1.1, D + 0.03, 0, 0, 1))}[s]
    cfg["emblem_size"] = 0.8 + 0.12 * s
    levels_podium(rm, cfg)
    # interior: frosted racks, freezer cabinets, crates
    n = rm.interior
    nr = (3, 6, 7, 9)[s]
    xr = tangent_fit(Ri, 0.28, 0.9, 0.05)
    for k in range(nr):
        a = 360.0 * (k + 0.5) / nr + 180.0 / nr
        if ang_diff(a, 0.0) < 22:
            continue
        with n.at(RZ(a), T(xr, 0, 0)):
            shelf_rack(n, w=1.7, d=0.55, h=1.8, levels=4, fill=0.8, seed=11 + k,
                       mats=("Frost", "Cargo", "Frost", "Accent"))
    for k in range((1, 2, 3, 4)[s]):
        a = 90.0 * k + 45.0
        x, y, _ = polar((0.9, 1.3, 1.8, 2.2)[s], a)
        with n.at(T(x, y, 0), RZ(a)):
            n.box0(0, 0, F, 1.4, 0.8, 0.9, "Frost", mats={"-z": None})
            n.box0(0, 0, F + 0.9, 1.3, 0.7, 0.05, "Glass")
            n.box((0, -0.41, F + 0.7), (1.2, 0.012, 0.06), "Accent", mats={"+y": None})


BUILDERS = {
    "habitat": build_habitat,
    "lounge": build_lounge,
    "cantina": build_cantina,
    "medical": build_medical,
    "bio_lab": build_bio_lab,
    "storehouse": build_storehouse,
    "cold_storage": build_cold_storage,
}
