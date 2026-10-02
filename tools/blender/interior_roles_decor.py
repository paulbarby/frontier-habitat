"""Frontier Habitat 5.0 free-standing role pieces (V5_DESIGN 15.3), part three of the shared prop kit.

Free-standing decor without anchors, built in the frame of interior_rooms.at(): +X is the front, z absolute.  Signature
(plan, x, y, yaw, k) -> the footprint radius, as in interior_families.DECOR.  The big-room filler
(interior_rooms.v4_decor) picks them by footprint; DECOR_KINDS says which categories get which pieces.

All names, slogans and art are ORIGINAL parodies (no real logos, brands, characters or lyrics).
"""
import random
from math import cos, sin, radians

from rooms_kit import T, RY
from interior_kit import F, bbox, plate_x
import interior_props as PR
from interior_props import text, text_lines, fit_h
import interior_roles as RO
from interior_roles import ZB, hat, disc_x, vending, whiteboard


def _at(n, x, y, yaw):
    from interior_rooms import at
    return at(n, x, y, yaw)


def d_snack(plan, x, y, yaw, k):
    """A snack corner: a vending machine, a round table with a mug and a stool."""
    n = plan.n
    with _at(n, x, y, yaw):
        with n.at(T(-0.22, -0.35, 0)):
            vending(n, 0.66, 0.4, k)
        n.vcyl(0.25, 0.30, F, F + 0.72, 0.03, seg=6, mat="Frame", cap0=False, cap1=False)
        n.vcyl(0.25, 0.30, F + 0.72, F + 0.75, 0.30, seg=10, mat="Hull")
        n.vcyl(0.25, 0.30, F, F + 0.02, 0.18, seg=8, mat="Frame")
        PR.mug(n, 0.20, 0.36, F + 0.75, mat=("Accent", "Hull", "Fabric")[k % 3], tall=k % 2 == 0)
        n.vcyl(0.56, 0.05, F, F + 0.42, 0.17, seg=8, mat="Cushion")
    return 0.95


def d_whiteboard(plan, x, y, yaw, k):
    """A whiteboard on a stand (a meeting nobody left)."""
    n = plan.n
    with _at(n, x, y, yaw):
        for sy in (-0.42, 0.42):
            bbox(n, -0.03, 0.03, sy - 0.02, sy + 0.02, F, ZB + 0.12, "Frame")
            bbox(n, -0.30, 0.05, sy - 0.025, sy + 0.025, F, F + 0.03, "Frame")
        whiteboard(n, 0.92, 0.1, k)
    return 0.62


def d_servercab(plan, x, y, yaw, k):
    """A server cabinet with rows of lights and a sign: MODEL-9 (DO NOT PET)."""
    n = plan.n
    with _at(n, x, y, yaw):
        bbox(n, -0.32, 0.30, -0.36, 0.36, F, F + 1.80, "HullDark", bevel=0.02)
        bbox(n, -0.325, 0.31, -0.40, -0.36, F, F + 1.80, "Frame")
        bbox(n, -0.325, 0.31, 0.36, 0.40, F, F + 1.80, "Frame")
        bbox(n, 0.30, 0.31, -0.33, 0.33, F + 1.66, F + 1.76, "Frame")
        rng = random.Random(k * 7 + 4)
        for r in range(11):
            z = F + 0.12 + 0.135 * r
            plate_x(n, 0.31, -0.31, 0.31, z, z + 0.105, "Rubber")
            for c in range(8):
                m = ("Glow", "Window", "L3Band", "Glow", "Glow", "BeaconAmber")[rng.randrange(6)]
                if rng.random() < 0.7:
                    plate_x(n, 0.312, -0.27 + 0.065 * c, -0.245 + 0.065 * c, z + 0.04, z + 0.06, m)
        plate_x(n, 0.311, -0.30, 0.30, F + 1.68, F + 1.74, "HullDark")
        text(n, "MODEL-9", 0.0, F + 1.71, 0.05, "Window", x=0.313)
        plate_x(n, 0.311, -0.20, 0.20, F + 0.02, F + 0.10, "Hazard")
        text(n, "DO NOT PET", 0.0, F + 0.06, 0.035, "HullDark", x=0.313)
        for sy in (-0.2, 0.2):
            with n.at(T(-0.322, sy, F + 1.45), RY(-90.0)):
                n.cap_disc(0.11, 0.0, "Frame", seg=10)
                n.cap_disc(0.025, 0.002, "Metal", seg=6)
    return 0.50


def d_toolcart(plan, x, y, yaw, k):
    """A tool trolley in hazard yellow with a hard hat, a thermos and a radio."""
    n = plan.n
    with _at(n, x, y, yaw):
        bbox(n, -0.30, 0.30, -0.45, 0.45, F + 0.12, F + 0.90, "Hazard", bevel=0.02)
        for j in range(4):
            plate_x(n, 0.301, -0.40, 0.40, F + 0.18 + 0.17 * j, F + 0.30 + 0.17 * j, "HullDark")
            bbox(n, 0.30, 0.325, -0.10, 0.10, F + 0.235 + 0.17 * j, F + 0.255 + 0.17 * j, "Metal")
        bbox(n, -0.33, 0.33, -0.48, 0.48, F + 0.90, F + 0.93, "Frame")
        for sx in (-0.24, 0.24):
            for sy in (-0.38, 0.38):
                n.vcyl(sx, sy, F, F + 0.12, 0.05, seg=6, mat="Frame")
        n.beam((-0.33, -0.45, F + 0.93), (-0.33, -0.45, F + 1.10), 0.025, 0.025, "Frame")
        n.beam((-0.33, 0.45, F + 0.93), (-0.33, 0.45, F + 1.10), 0.025, 0.025, "Frame")
        n.beam((-0.33, -0.45, F + 1.10), (-0.33, 0.45, F + 1.10), 0.025, 0.025, "Frame")
        hat(n, 0.0, 0.25, F + 0.93, ("Hull", "SignalRed", "WaterBlue")[k % 3])
        n.vcyl(0.0, -0.28, F + 0.93, F + 1.17, 0.045, seg=8, mat="Metal", cap0=False)        # thermos
        n.vcyl(0.0, -0.28, F + 1.17, F + 1.21, 0.047, seg=8, mat="SignalRed")
        bbox(n, -0.08, 0.08, -0.10, 0.10, F + 0.93, F + 1.05, "HullDark", bevel=0.01)          # a radio
        plate_x(n, 0.081, -0.07, 0.07, F + 0.96, F + 1.02, "Screen")
    return 0.55


def d_cratesart(plan, x, y, yaw, k):
    """Stacked crates with stencilled jokes."""
    n = plan.n
    with _at(n, x, y, yaw):
        bbox(n, -0.55, 0.55, -0.42, 0.42, F, F + 0.10, "Wood", mats={"-z": None})
        for (cx, cy, s, z, m) in ((-0.28, -0.12, 0.52, F + 0.10, "Cargo"), (0.28, 0.12, 0.52, F + 0.10, "Hull"),
                                  (-0.20, 0.0, 0.46, F + 0.62, "CushionLight")):
            bbox(n, cx - s / 2, cx + s / 2, cy - s / 2, cy + s / 2, z, z + s, m, bevel=0.015)
            bbox(n, cx - s / 2 - 0.01, cx + s / 2 + 0.01, cy - s / 2 - 0.01, cy + s / 2 + 0.01, z + s * 0.40,
                 z + s * 0.56, "Frame", mats={"-z": None, "+z": None})
        lab = (("THIS WAY", "UP*"), ("FRAGILE:", "AI INSIDE"), ("DO NOT", "ASK WHY"))[k % 3]
        xf = 0.28 + 0.26 + 0.012                                    # the +X face of the front crate (with its band)
        plate_x(n, xf, 0.12 - 0.20, 0.12 + 0.20, F + 0.14, F + 0.24, "Hazard")
        text_lines(n, lab, 0.12, F + 0.50, fit_h(lab, 0.40, 0.06), "HullDark", x=xf, gap=0.4)
    return 0.78


def d_dronedock(plan, x, y, yaw, k):
    """A delivery drone on a pad, on a pole, with a sign."""
    n = plan.n
    with _at(n, x, y, yaw):
        n.vcyl(0.0, 0.0, F, F + 0.03, 0.30, seg=10, mat="Frame")
        n.vcyl(0.0, 0.0, F + 0.03, F + 1.00, 0.04, seg=6, mat="Metal", cap0=False, cap1=False)
        n.vcyl(0.0, 0.0, F + 1.00, F + 1.05, 0.30, seg=10, mat="HullDark")
        zd = F + 1.05
        bbox(n, -0.09, 0.09, -0.09, 0.09, zd + 0.04, zd + 0.11, "Hull", bevel=0.02)
        plate_x(n, 0.091, -0.04, 0.04, zd + 0.06, zd + 0.09, "Glow")
        for ang in (45, 135, 225, 315):
            a = radians(ang)
            n.beam((0.07 * cos(a), 0.07 * sin(a), zd + 0.09), (0.20 * cos(a), 0.20 * sin(a), zd + 0.10), 0.02, 0.012,
                   "Frame")
            with n.at(T(0.20 * cos(a), 0.20 * sin(a), zd + 0.115)):
                n.cap_disc(0.095, 0.0, "Rubber", seg=10)
        bbox(n, -0.06, 0.06, -0.06, 0.06, zd, zd + 0.04, "Hazard")                                   # a parcel
        bbox(n, 0.0, 0.03, -0.45, 0.45, F + 1.30, F + 1.58, "Frame")
        plate_x(n, 0.031, -0.43, 0.43, F + 1.32, F + 1.56, "HullDark")
        text_lines(n, ("DRONE ETA", "5 MIN"), 0.0, F + 1.55, 0.06, "Window", x=0.032, gap=0.4)
        n.vcyl(0.0, -0.40, F + 1.0, F + 1.30, 0.012, seg=4, mat="Frame", cap0=False)
        n.vcyl(0.0, 0.40, F + 1.0, F + 1.30, 0.012, seg=4, mat="Frame", cap0=False)
    return 0.50


def d_gnome(plan, x, y, yaw, k):
    """A garden gnome in a VR headset, on a stump (the farm mascot)."""
    n = plan.n
    with _at(n, x, y, yaw):
        n.vcyl(0.0, 0.0, F, F + 0.22, 0.14, 0.12, seg=8, mat="Wood", cap0=False)
        n.lathe([(0.10, F + 0.22), (0.11, F + 0.34), (0.08, F + 0.46), (0.0, F + 0.47)], "CushionLight", seg=8)
        n.sphere((0.04, 0.0, F + 0.50), 0.055, "Fabric", seg=8, rings=4)
        n.lathe([(0.07, F + 0.54), (0.04, F + 0.66), (0.0, F + 0.80)], "SignalRed", seg=8)
        n.lathe([(0.06, F + 0.40), (0.07, F + 0.31), (0.0, F + 0.29)], "Hull", seg=8)               # the beard
        bbox(n, 0.07, 0.11, -0.065, 0.065, F + 0.51, F + 0.57, "HullDark", bevel=0.008)             # the headset
        plate_x(n, 0.111, -0.055, 0.055, F + 0.52, F + 0.56, "Screen")
        bbox(n, -0.02, 0.0, -0.07, 0.07, F + 0.53, F + 0.545, "Frame")
        n.cyl((0.0, -0.10, F + 0.34), (0.08, -0.15, F + 0.40), 0.018, seg=5, mat="Fabric")
        n.cyl((0.0, 0.10, F + 0.34), (0.08, 0.15, F + 0.40), 0.018, seg=5, mat="Fabric")
    return 0.28


def d_plantbot(plan, x, y, yaw, k):
    """A pot plant with a chat screen on a stake: 'I AM THIRSTY'."""
    n = plan.n
    import interior_furniture as FU
    with _at(n, x, y, yaw):
        FU.pot_plant(n, 0.0, 0.0, r=0.20, h=0.40, s=0.9, seed=k + 3)
        n.vcyl(0.26, 0.0, F, F + 0.62, 0.012, seg=4, mat="Frame", cap0=False)
        bbox(n, 0.24, 0.27, -0.13, 0.13, F + 0.52, F + 0.72, "HullDark", bevel=0.005)
        plate_x(n, 0.271, -0.115, 0.115, F + 0.535, F + 0.705, "Screen")
        text_lines(n, (("I AM", "THIRSTY"), ("I AM", "FINE*"), ("PLEASE", "TALK TO ME"))[k % 3], 0.0, F + 0.69, 0.038,
                   "LightStrip", x=0.272, gap=0.4)
    return 0.36


def d_ringlight(plan, x, y, yaw, k):
    """A ring light on a tripod with a phone in the middle (everybody is a creator)."""
    n = plan.n
    with _at(n, x, y, yaw):
        for ang in (0, 120, 240):
            a = radians(ang)
            n.beam((0.0, 0.0, F + 1.05), (0.30 * cos(a), 0.30 * sin(a), F), 0.02, 0.02, "Frame")
        n.vcyl(0.0, 0.0, F + 0.60, F + 1.50, 0.016, seg=6, mat="Metal", cap0=False, cap1=False)
        zr = F + 1.52
        with n.at(T(0.0, 0.0, zr), RY(-90.0)):
            n.lathe([(0.15, -0.014), (0.21, -0.014), (0.21, 0.014), (0.15, 0.014)], "LightStrip", seg=18, smooth=False,
                    caps=False)
        bbox(n, 0.02, 0.05, -0.04, 0.04, zr - 0.07, zr + 0.07, "HullDark", bevel=0.008)             # the phone
        plate_x(n, 0.051, -0.032, 0.032, zr - 0.06, zr + 0.06, "Screen")
        disc_x(n, 0.052, 0.0, zr + 0.045, 0.008, "SignalRedGlow", seg=6)
    return 0.40


def d_bins(plan, x, y, yaw, k):
    """Three bins in a row: recycling, compost and 'AI DATA'."""
    n = plan.n
    with _at(n, x, y, yaw):
        for j, (lab, m) in enumerate((("RECYCLE", "WaterBlue"), ("COMPOST", "Plant"), ("AI DATA", "HullDark"))):
            yy = (j - 1) * 0.40
            n.vcyl(0.0, yy, F, F + 0.70, 0.16, 0.18, seg=10, mat=m, cap0=False)
            n.vcyl(0.0, yy, F + 0.70, F + 0.74, 0.19, seg=10, mat="Frame")
            plate_x(n, 0.179, yy - 0.075, yy + 0.075, F + 0.30, F + 0.46, "Hull")
            text(n, lab, yy, F + 0.38, fit_h([lab], 0.14, 0.022), "HullDark", x=0.1795)
            bbox(n, 0.0, 0.12, yy - 0.03, yy + 0.03, F + 0.74, F + 0.77, "Frame")
    return 0.55


def d_kiosk(plan, x, y, yaw, k):
    """An information kiosk: 'ASK ME ANYTHING (I WILL TRY)'."""
    n = plan.n
    with _at(n, x, y, yaw):
        bbox(n, -0.18, 0.18, -0.30, 0.30, F, F + 0.10, "Frame", bevel=0.01)
        bbox(n, -0.10, 0.10, -0.22, 0.22, F + 0.10, F + 1.55, "Hull", bevel=0.02)
        with n.at(T(0.10, 0.0, F + 1.12), RY(-12.0)):
            bbox(n, 0.0, 0.03, -0.20, 0.20, -0.20, 0.22, "HullDark", bevel=0.006)
            plate_x(n, 0.031, -0.18, 0.18, -0.18, 0.20, "Screen")
            text_lines(n, ("ASK ME", "ANYTHING", "(I WILL TRY)"), 0.0, 0.18, 0.045, "LightStrip", x=0.032, gap=0.45)
        plate_x(n, 0.101, -0.17, 0.17, F + 0.40, F + 0.66, "HullDark")
        for r_ in range(2):
            for c_ in range(4):
                plate_x(n, 0.102, -0.14 + 0.07 * c_, -0.09 + 0.07 * c_, F + 0.46 + 0.11 * r_, F + 0.52 + 0.11 * r_,
                        ("Neon", "LightStrip")[(r_ + c_) % 2])
        disc_x(n, 0.101, 0.0, F + 1.40, 0.02, "Glow", seg=8)
    return 0.45


DECOR_ROLE = {
    "snack": (d_snack, 0.95), "wboard": (d_whiteboard, 0.62), "servercab": (d_servercab, 0.50),
    "toolcart": (d_toolcart, 0.55), "cratesart": (d_cratesart, 0.78), "dronedock": (d_dronedock, 0.50),
    "gnome": (d_gnome, 0.28), "plantbot": (d_plantbot, 0.36), "ringlight": (d_ringlight, 0.40), "bins": (d_bins, 0.55),
    "kiosk": (d_kiosk, 0.45),
}
# category -> the role decor appended to interior_rooms.V4_KINDS (the big-room filler picks by footprint)
DECOR_KINDS = {
    "housing": ["ringlight", "bins", "plantbot", "kiosk"],
    "comfort": ["ringlight", "snack", "kiosk", "bins", "plantbot"],
    "food": ["gnome", "plantbot", "snack", "bins"],
    "industry": ["toolcart", "cratesart", "snack", "wboard", "servercab"],
    "science": ["wboard", "servercab", "snack", "kiosk"],
    "medical": ["kiosk", "snack", "bins", "plantbot"],
    "life_support": ["toolcart", "wboard", "bins", "snack"],
    "logistics": ["dronedock", "cratesart", "snack", "kiosk"],
    "civic": ["kiosk", "snack", "bins", "wboard"],
}
SATIRE_DECOR = {"d_snack", "d_servercab", "d_cratesart", "d_dronedock", "d_gnome", "d_plantbot", "d_ringlight",
                "d_bins", "d_kiosk", "d_whiteboard", "d_toolcart"}


DECOR_CAP = {"snack": 1, "bins": 1, "kiosk": 1, "wboard": 1, "servercab": 1, "toolcart": 1, "cratesart": 1,
             "dronedock": 1, "gnome": 1, "plantbot": 2, "ringlight": 1}      # 2026-10-02: once per room (variety, pck)


def cap_for(kind, rm):
    """How many of a role decor kind one room gets: once (plants, gnomes and crates twice in XL)."""
    s = getattr(rm, "size", 1) or 0
    base = DECOR_CAP.get(kind)
    if base is None:
        # the older filler kinds: a few of each (variety), the small ones without limit
        return 99 if kind in ("plant", "light", "cart") else 3 + s
    return base + (1 if s >= 3 and kind in ("plantbot", "gnome", "cratesart") else 0)


def register_decor(DECOR, NEED, V4_KINDS):
    """Add the role decor to the family decor registry and to the filler lists of every category."""
    for name, (fn, need) in DECOR_ROLE.items():
        def wrapped(plan, x, y, yaw, k, fn=fn):
            key = "d_" + fn.__name__[2:]
            PR.USED[key] = PR.USED.get(key, 0) + 1
            f0 = len(plan.n.faces)
            out = fn(plan, x, y, yaw, k)
            PR.USED_TRIS[key] = PR.USED_TRIS.get(key, 0) + sum(len(f_) - 2 for f_ in plan.n.faces[f0:])
            return out
        DECOR.setdefault(name, wrapped)
        NEED.setdefault(name, need)
    for cat, kinds in DECOR_KINDS.items():
        cur = V4_KINDS.setdefault(cat, [])
        for kd in kinds:
            if kd not in cur:
                cur.append(kd)
