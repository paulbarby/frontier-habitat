"""Frontier Habitat 5.0 (docs/V5_DESIGN.md section 7) - ART-HAB: the apartment block exterior (XXL, 3 storeys).

A stepped round block (radius 20): floor 0 fills the footprint, floor 1 steps in to R1 (a garden terrace on the
floor-0 roof), floor 2 (two penthouses) steps in to R2 under a flat roof, with a glass-roofed terrace ring on the
floor-1 roof.  The lift and stair core in the middle rises through the roof as a round crown with the house badge.

Plan (every floor, radii in m): core r < R_CORE; lift lobby ring R_CORE..R_LOBBY; floors 0 and 1: shared rooms
R_LOBBY..R_INNER between five spokes, a round street R_INNER..R_STREET, five units R_STREET..R_UNIT between the
spokes; floor 0 also: unit yards R_UNIT..r_max.  Floor 2: two penthouses R_LOBBY..R2.

Object names (docs/requests/ART-HAB-to-RENDER.md, v5): floor 0 uses the v3 room names (Wall_00..31, Upper_*,
Interior, Base, Roof ...); floor k >= 1 uses F<k>_Slab, F<k>_Wall (up to k * 3.6 + 1.40), F<k>_WallTop (above the
cut), F<k>_Interior, F<k>_Terrace.  To show floor k: hide Roof, every F<n>_* with n > k and F<k>_*Top.
Interiors: interior_v5apt.py.
"""
from math import sin, cos, radians, degrees, atan2, sqrt, pi, asin

import rooms_kit as K
from rooms_kit import T, RY, RZ, WALL_TOP, reg_angles, columns, col_mid_fn, ang_diff, lamp, FLOOR_Z
import rooms_identity as RI

F = FLOOR_Z
H = 3.6                     # floor height (content floor_height)
R_CORE, R_LOBBY, R_INNER, R_STREET, R_UNIT = 2.8, 4.4, 8.0, 9.6, 15.2
R1, R2 = 15.4, 11.0         # wall radius of floor 1 and floor 2
SPOKES = (18.0, 90.0, 162.0, 234.0, 306.0)
SPOKE_HW = 0.8
PORTS = (18.0, 90.0, 162.0, 234.0, 306.0, 270.0)       # 6 link ports (content max_links 6)
PH_CENTRES = (0.0, 180.0)   # the two penthouses


def spoke_delta(r):
    """Half angle (deg) of a spoke corridor at radius r (radial walls, 1.6 m at the ring's middle)."""
    return degrees(asin(min(0.99, SPOKE_HW / r)))


D_INNER = spoke_delta(0.5 * (R_LOBBY + R_INNER))
D_UNIT = spoke_delta(0.5 * (R_STREET + R_UNIT))


def unit_rooms(k):
    """Angles (deg) of unit k's rooms (the unit between spoke k and k + 1): dict name -> (a_lo, a_hi)."""
    a0 = SPOKES[k] + D_UNIT
    a1 = SPOKES[k] + 72.0 - D_UNIT
    return dict(unit=(a0, a1), bedA=(a0, a0 + 18.0), hall=(a0 + 18.0, a0 + 30.0), living=(a0 + 30.0, a1 - 12.0),
                bedB=(a1 - 12.0, a1), door_out=a1 - 16.0)


def ph_rooms(p):
    """Angles (deg) of penthouse p's rooms (relative -90..90 around its centre)."""
    c = PH_CENTRES[p]
    return dict(unit=(c - 90.0, c + 90.0), bath=(c - 90.0, c - 70.0), master=(c - 70.0, c - 32.0),
                living=(c - 32.0, c + 38.0), bed2=(c + 38.0, c + 64.0), bed3=(c + 64.0, c + 90.0),
                terrace_door=c - 20.0, entry=c)


def _ring_wall(part, r, z0, z1, cut, mats_fn, seg=96, thick=0.20, gaps=()):
    """A round wall of radius r from z0 to z1: outside face, a closed top at z1, inside face.  mats_fn(z_lo, z_hi)
    names the outside material of each band; gaps [(angle, width_m)] leave the columns open (door openings)."""
    step = 360.0 / seg
    angs = [step * (k + 0.5) for k in range(seg)]
    open_cols = set()
    for (ga, gw) in gaps:
        hw = degrees(gw / 2.0 / r)
        for i, a in enumerate(angs):
            nxt = angs[(i + 1) % seg] + (360.0 if i == seg - 1 else 0.0)
            mid = 0.5 * (a + nxt)
            if ang_diff(mid, ga) < hw:
                open_cols.add(i)
    ro_, ri_ = r + thick / 2, r - thick / 2
    prof = [(ro_, z) for z in cut] + [(ri_, z1), (ri_, z0)]
    mats = []
    for j in range(len(cut) - 1):
        mats.append(mats_fn(cut[j], cut[j + 1]))
    mats += ["Frame", "Hull"]

    def mf(k, i):
        if i in open_cols:
            return None
        return mats[k]
    part.lathe_a(prof, angs, mf, smooth=False)
    # jambs at the openings
    for (ga, gw) in gaps:
        hw = degrees(gw / 2.0 / r)
        for s_ in (-1, 1):
            a = radians(ga + s_ * hw)
            with part.at(T(r * cos(a), r * sin(a), 0.0), RZ(degrees(a))):
                part.box0(0.0, 0.0, z0, thick + 0.06, 0.10, z1 - z0, "Frame", mats={"-z": None})


def _slab(part, z0, r_in, r_out, inside="Floor", outside="HullDark", edge="Frame"):
    """A floor slab: top at z0 + F; inside r < r_in: floor panels (rings with seams, radial seams); r_in..r_out:
    the terrace deck in `outside`; a fascia at r_out."""
    zt = z0 + F
    part.lathe_a([(r_out + 0.02, z0), (r_out + 0.02, zt), (r_in, zt)], reg_angles(96),
                 lambda k, i: (edge, outside)[k], smooth=False)
    prof, mats = [(r_in, zt)], []
    r = r_in
    while r - 1.6 > 1.0:
        prof.append((r - 0.05, zt))
        mats.append("FloorDark")
        prof.append((r - 1.6, zt))
        mats.append(inside)
        r -= 1.6
    prof.append((0.0, zt))
    mats.append(inside)
    part.lathe_a(prof, reg_angles(96), lambda k, i: mats[k], smooth=False)
    # critic 41: the slab's underside, facing down (the floor below sees a ceiling, not the furniture above), with two
    # light rings
    part.lathe_a([(0.0, z0 + 0.01), (r_out + 0.02, z0 + 0.01)], reg_angles(48), lambda k, i: "Hull", smooth=False)
    for rr in (0.45 * r_out, 0.75 * r_out):
        part.lathe_a([(rr - 0.05, z0 + 0.005), (rr + 0.05, z0 + 0.005)], reg_angles(48), lambda k, i: "LightStrip",
                     smooth=False)
    for k in range(16):
        a = radians(360.0 * k / 16 + 5.625)
        c_, s_ = cos(a), sin(a)
        n_ = (-s_ * 0.025, c_ * 0.025)
        p0, p1 = (1.2 * c_, 1.2 * s_), ((r_in - 0.1) * c_, (r_in - 0.1) * s_)
        part.quad((p0[0] - n_[0], p0[1] - n_[1], zt + 0.002), (p1[0] - n_[0], p1[1] - n_[1], zt + 0.002),
                  (p1[0] + n_[0], p1[1] + n_[1], zt + 0.002), (p0[0] + n_[0], p0[1] + n_[1], zt + 0.002),
                  "FloorDark")


def build_apartment_block(rm):
    rm.levels = False
    rm.no_extras = True
    rm.build_base(lamps=(), bolts=True)
    Rw = rm.Rw
    rm.shell = "podium"
    rm.D = H
    ro = rm.roof
    parts = {}

    def part(name):
        if name not in parts:
            parts[name] = K.P(name)
            rm.extra_parts = list(getattr(rm, "extra_parts", [])) + [parts[name]]
        return parts[name]
    rm.fpart = part

    # ---- floor 0: the drum above the cut (1.40 .. 3.6) with a window band and the family band (-> Upper_*)
    seams = [360.0 * (k + 0.5) / 40 for k in range(40)]
    cols, kind, _ = columns(rm.seg * 2, seams, seam_w=degrees(0.08 / Rw))
    prof = [(Rw, WALL_TOP - 0.02), (Rw, 1.70), (Rw, 2.95), (Rw, 3.05), (Rw, 3.30), (Rw, H - 0.1), (Rw, H),
            (Rw + 0.04, H), (Rw + 0.04, H + F), (Rw - 0.12, H + F)]
    mats = ("Hull", "WIN", "Hull", "Accent", "Hull", "LightStrip", "Frame", "Frame", "Frame")
    ro.lathe_a(prof, cols, lambda k, i: ("Frame" if kind[i] == "s" else "Window") if mats[k] == "WIN" else mats[k],
               smooth=False)

    # ---- floor 1: slab (terrace ring R1..Rw), wall with terrace doors at every living room
    doors1 = [(unit_rooms(k)["door_out"], 1.2) for k in range(5)] + [(a, 1.2) for a in SPOKES]
    _slab(part("F1_Slab"), H, R1, Rw - 0.12, outside="HullDark")
    z0 = H
    _ring_wall(part("F1_Wall"), R1, z0 + F, z0 + WALL_TOP,
               [z0 + F, z0 + 0.40, z0 + 0.88, z0 + 1.26, z0 + WALL_TOP],
               lambda a, b: "HullDark" if b <= z0 + 0.41 else ("Accent" if a >= z0 + 0.87 and b <= z0 + 1.27 else "Hull"),
               gaps=doors1)
    _ring_wall(part("F1_WallTop"), R1, z0 + WALL_TOP, 2 * H,
               [z0 + WALL_TOP, z0 + 1.60, z0 + 2.95, z0 + 3.20, 2 * H],
               lambda a, b: "Window" if a >= z0 + 1.59 and b <= z0 + 2.96 else
               ("LightStrip" if a >= z0 + 2.94 and b <= z0 + 3.21 else "Hull"))
    # ---- floor 2: slab (glass-roofed terrace R2..R1), penthouse wall with a terrace door each
    doors2 = [(ph_rooms(p)["terrace_door"], 1.4) for p in range(2)]
    _slab(part("F2_Slab"), 2 * H, R2, R1 + 0.25, outside="Wood")
    z0 = 2 * H
    _ring_wall(part("F2_Wall"), R2, z0 + F, z0 + WALL_TOP,
               [z0 + F, z0 + 0.40, z0 + 0.88, z0 + 1.26, z0 + WALL_TOP],
               lambda a, b: "HullDark" if b <= z0 + 0.41 else ("Accent" if a >= z0 + 0.87 and b <= z0 + 1.27 else "Window"),
               gaps=doors2)
    _ring_wall(part("F2_WallTop"), R2, z0 + WALL_TOP, 3 * H,
               [z0 + WALL_TOP, z0 + 3.10, z0 + 3.35, 3 * H],
               lambda a, b: "Window" if b <= z0 + 3.11 else ("L5Gold" if b <= z0 + 3.36 else "Hull"))
    # mullions on the penthouse glazing
    wt = parts["F2_WallTop"]
    for k in range(48):
        a = radians(7.5 * k + 3.75)
        if any(ang_diff(7.5 * k + 3.75, d[0]) < 4.5 for d in doors2):
            continue
        with wt.at(T((R2 + 0.12) * cos(a), (R2 + 0.12) * sin(a), 0.0), RZ(degrees(a))):
            wt.box0(0.0, 0.0, z0 + WALL_TOP, 0.06, 0.08, 3.10 - WALL_TOP, "Frame", mats={"-z": None})

    # ---- roof: penthouse roof, glass canopy over the terrace, the core crown with the badge
    zr = 3 * H
    ro.lathe_a([(R2 + 0.22, zr), (R2 + 0.22, zr + 0.30), (R2 - 0.10, zr + 0.30), (R2 - 0.10, zr + 0.05),
                (0.0, zr + 0.05)], reg_angles(96), lambda k, i: ("Frame", "Frame", "Frame", "HullDark")[k], smooth=False)
    # glass canopy: a cone from the penthouse wall (z 10.5) down to posts at R1 (z 9.7)
    g_in, g_out = (R2 + 0.12, zr - 0.30), (R1 + 0.15, 2 * H + 2.45)
    ro.lathe_a([g_out, g_in], reg_angles(96), lambda k, i: "Glass", smooth=False)
    ro.lathe_a([g_in, g_out], reg_angles(96), lambda k, i: "Glass", smooth=False)   # both faces (Glass is BLEND)
    for k in range(36):
        a = radians(10.0 * k)
        c_, s_ = cos(a), sin(a)
        ro.beam((g_in[0] * c_, g_in[0] * s_, g_in[1] + 0.05), (g_out[0] * c_, g_out[0] * s_, g_out[1] + 0.05),
                0.08, 0.08, "Frame")
        ro.vcyl(R1 * c_, R1 * s_, 2 * H + F, g_out[1], 0.07, seg=6, mat="Frame")
    ro.lathe_a([(g_out[0] + 0.05, g_out[1] - 0.12), (g_out[0] + 0.05, g_out[1] + 0.06),
                (g_out[0] - 0.25, g_out[1] + 0.10)], reg_angles(96), lambda k, i: "Frame", smooth=False)
    # the core crown: machine room / stair head, a lit band, the badge on its roof
    rc, zc = 5.2, zr + 2.4
    ro.lathe_a([(rc, zr + 0.05), (rc, zr + 0.55), (rc, zr + 1.55), (rc, zr + 1.80), (rc, zc),
                (rc + 0.25, zc), (rc + 0.25, zc + 0.20), (0.0, zc + 0.20)], reg_angles(64),
               lambda k, i: ("HullDark", "Window" if i % 4 else "Frame", "Accent", "Hull", "Frame", "Frame",
                             "HullDark")[k], smooth=False)
    RI.badge(ro, "housing", 0.0, 0.0, rc - 0.25, lambda x, y: zc + 0.20, lift=0.015)
    rm.badge_done = True
    # a mast with a beacon on the crown edge
    ro.vcyl(rc * 0.62, rc * 0.62, zc + 0.2, zc + 2.6, 0.06, seg=6, mat="Frame")
    rm.fpart("PorchTop").sphere((rc * 0.62, rc * 0.62, zc + 2.68), 0.14, "Light", seg=8, rings=4)
    # roof dressing round the crown: solar-look panels (HullDark with Frame) and vents
    for k in range(10):
        a = radians(36.0 * k + 18.0)
        x, y = 8.1 * cos(a), 8.1 * sin(a)
        with ro.at(T(x, y, zr + 0.05), RZ(degrees(a))):
            ro.box0(0.0, 0.0, 0.0, 1.8, 2.6, 0.16, "Frame")
            with ro.at(T(0.0, 0.0, 0.16), RY(-18.0)):
                ro.box0(0.0, 0.0, 0.0, 1.7, 2.5, 0.05, "HullDark")
    rm.top_z = max(rm.top_z, zc + 2.8)
    # head room of floor 0: under the floor-1 slab
    rm.rooms_hi.append((lambda x, y: True, H - 0.02))


BUILDERS = {
    "apartment_block": build_apartment_block,
}
