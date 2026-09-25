"""
Frontier Habitat 3.1 - ship_trader: a boxy freighter with four cargo pods, a crane arm, spine containers and a
rear cargo ramp. Critic round 9 fixes 1-7 applied (faceted cockpit, hull language, heavier legs, engine bells,
night lights, spine containers, engines raised clear of the ramp).

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/ship_trader.py
Output: assets/models/ship_trader.glb (contract in tools/blender/ship_common.py).

Nodes: Hull, Lights; Leg_FL, Leg_FR, Leg_RL, Leg_RR; Ramp (rear); Door_Side (-Y gull-wing hatch);
Thruster_Main_L / _R (aft, flame -X), Thruster_Hover_FL / FR / RL / RR (belly, flame down);
Anchor_Ramp (ramp foot), Anchor_Cargo (top of the ramp).
"""
import os
import sys
from math import sin, cos, pi, radians, degrees, atan2, atan, sqrt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ship_common as SC                                   # noqa: E402
import ship_fleet as SF                                    # noqa: E402
from ship_common import Part, Anchor, Anim, LoftHull, T, RX, RY, RZ, S, place_frame, panel, patch   # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402

HULL, PANEL, DARK, GRAPH = "Palette:Hull", "Palette:#c8cdd4", "Palette:HullDark", "Palette:Frame"
RUB, HAZ = "Palette:Rubber", "Palette:Hazard"
FRAME, METAL, TRIM = "PaletteMetal:Frame", "PaletteMetal:Metal", "PaletteMetal:Trim"

KIND = "trader"
BELLY = 1.80
ENG_Z = 4.45
H = LoftHull([
    (-6.00, 1.50, 4.40, 2.70, 3.20),
    (-5.30, 1.95, 4.85, 2.25, 2.90),
    (-4.30, 2.10, 5.00, 1.80, 2.70),
    (2.90, 2.10, 5.00, 1.80, 2.70),
    (4.40, 1.95, 4.75, 1.85, 2.70),
    (5.50, 1.60, 4.20, 2.05, 2.70),
    (6.30, 1.05, 3.70, 2.40, 2.80),
    (6.65, 0.45, 3.35, 2.75, 2.90)], n_top=5.0, n_bot=7.0)

TS = [0, 7, 14, 18, 23, 32, 45, 58, 72, 90, 108, 122, 135, 148, 157, 162, 166, 173, 180, 190, 210, 240, 270, 300,
      330, 350]
SEAMS_X = (-4.35, -1.9, 0.9, 3.55)
PANEL_XB = (-4.35, -1.9, 0.9, 3.55)
PANEL_TB = (0, 23, 58, 90, 122, 157, 180)


def hull_mat(xa, xb, ta, tb):
    xm, tm = (xa + xb) / 2, (ta + tb) / 2
    if tm > 180:
        return GRAPH
    if (14 <= tm <= 18 or 162 <= tm <= 166) and -5.4 < xm < 6.0:
        return "Accent"
    for s in SEAMS_X:
        if abs(xm - s) < 0.06 and 5 < tm < 175:
            return DARK
    i = sum(1 for b in PANEL_XB if xm > b)
    j = sum(1 for b in PANEL_TB if tm > b)
    return PANEL if (i * 7 + j * 3) % 3 == 0 else HULL


def xs_rings():
    xs = [-6.0, -5.8, -5.5, -5.1, -4.6, -4.2, -3.2, -2.2, -1.2, 0.2, 1.4, 2.4, 3.2, 3.9, 4.4, 4.9, 5.3, 5.7, 6.0, 6.3,
          6.5, 6.65]
    for s in SEAMS_X:
        xs += [s - 0.06, s + 0.06]
    return sorted(set(round(x, 3) for x in xs))


# ======================================================================================
def build_hull(h, lt):
    H.skin(h, xs_rings(), TS, hull_mat, nose_mat=HULL, tail_mat=GRAPH)
    for xr in (-4.35, 3.55):                                               # ribs
        rings = [[H.pt(xr + dx, t, off) for t in TS] for dx, off in ((-0.16, 0.0), (-0.12, 0.06), (0.12, 0.06), (0.16, 0.0))]
        h.loft(rings, lambda k, i: DARK if TS[i] < 180 else GRAPH, smooth=True, closed=True)
    # faceted bridge on the nose (fix 1)
    SC.faceted_cockpit(h, lt, 3.55, 4.55, 5.85, w=1.45, zb=3.3, zt=5.35, c=0.38, front_top=4.2, front_w=1.05)
    for sx in (-1, 1):                                                      # leg bays
        for sy in (-1, 1):
            x0, x1 = (1.6, 3.95) if sx > 0 else (-3.45, -1.1)
            t0 = 322 if sy > 0 else 202
            patch(h, H, x0, x1, t0, t0 + 16, 0.015, DARK, nx=2, nt=1, smooth=True)
    # upper-flank inset panels (fix 2)
    for (x0, x1) in ((-4.1, -2.1), (-1.7, 0.7), (1.1, 3.35)):
        SC.inset_panel(h, H, x0, x1, 40, 54)
        SC.inset_panel(h, H, x0, x1, 126, 140)
    # roof: service hatch with a handrail, vents, spine handrails, a flank ladder (fix 2)
    panel(h, H, 1.3, 2.3, 80, 100, 0.05, DARK, side=FRAME, nx=1, nt=2)
    for (x0, t0) in ((-1.3, 66), (-1.3, 104), (-4.0, 72), (-4.0, 98)):
        panel(h, H, x0, x0 + 0.9, t0, t0 + 10, 0.035, RUB, side=FRAME, nx=1, nt=1)
        for k in range(4):
            xs_ = x0 + 0.9 * (k + 0.5) / 4
            panel(h, H, xs_ - 0.03, xs_ + 0.03, t0, t0 + 10, 0.06, FRAME, side=FRAME, nx=1, nt=1)
    for t in (62, 118):
        SC.rail(h, [H.pt(x, t) for x in (-3.9, -2.6, -1.3, 0.0, 1.3, 2.6, 3.3)], h=0.5)
    SC.hull_ladder(h, H, 4.0, -1, 8, 64)
    # vents and RCS blocks on the flanks, antennas, dish
    for sy in (-1, 1):
        for (x, z) in ((5.9, 3.2), (-5.5, 3.6)):
            t = H.t_at_z(x, z, sy)
            q, n = H.pt(x, t), H.nrm(x, t)
            h.box(tuple(q + n * 0.12), (0.45, 0.34, 0.3), DARK, bevel=0.03)
            h.cyl(q + n * 0.2, q + n * 0.34, 0.07, 0.09, seg=6, mat=FRAME, cap1=False)
    h.vcyl(4.2, 1.0, 5.3, 6.3, 0.03, seg=4, mat=FRAME, smooth=False)
    h.vcyl(3.9, -0.9, 5.3, 6.0, 0.03, seg=4, mat=FRAME, smooth=False)
    with h.at(T(3.2, 0.9, 5.05), RZ(-50), RY(-35)):
        h.lathe([(0.0, 0.0), (0.35, 0.07), (0.55, 0.22), (0.5, 0.25), (0.0, 0.08)],
                lambda k, i: HULL if k < 2 else FRAME, seg=12)
        h.vcyl(0, 0, -0.35, 0.02, 0.07, seg=6, mat=FRAME)
    # night: tail beacon, landing lights under the nose, belly floods over the ramp (fix 5)
    SC.nav_light(h, lt, (-5.95, 0.0, 4.5), "Light", r=0.08)
    for sy in (-1, 1):
        q = H.pt(5.6, 255 if sy < 0 else 285)
        SC.flood(h, lt, q + Vector((0.05, 0, -0.08)), (0.6, 0, -1))


def hover(h, x, y):
    return SC.hover_thruster(h, x, y, H.sec(x)[2] + 0.12)


def pod(h, lt, x0, x1, sy, nav=False):
    """cylindrical cargo container along X with clamp rings, pylons and (front pods) a nav light"""
    y, z, r = sy * 3.05, 3.30, 0.88
    L = x1 - x0
    with h.at(T(x0, y, z), RY(90.0)):
        prof = [(0.0, -0.32), (0.55, -0.27), (0.82, -0.12), (r, 0.0), (r, 0.18), (r, L * 0.5 - 0.1), (r, L * 0.5 + 0.1),
                (r, L - 0.18), (r, L), (0.82, L + 0.12), (0.55, L + 0.27), (0.0, L + 0.32)]
        mats = [FRAME, FRAME, "Accent", HAZ, "Accent", DARK, "Accent", HAZ, "Accent", FRAME, FRAME]
        h.lathe(prof, lambda k, i: mats[k] if not (mats[k] == HAZ and i % 2) else RUB, seg=14)
        for dz in (0.35, L - 0.35):
            h.lathe([(r + 0.06, dz - 0.07), (r + 0.06, dz + 0.07), (r - 0.02, dz + 0.08), (r - 0.02, dz - 0.08)], FRAME,
                    seg=14, smooth=False, wrap=True)
    for xx in (x0 + 0.35, x1 - 0.35):
        t = H.t_at_z(xx, z, sy)
        q = H.pt(xx, t)
        h.beam(q - Vector((0, sy * 0.1, 0)), Vector((xx, y - sy * (r - 0.02), z)), 0.22, 0.26, FRAME)
    if nav:                                            # port (+Y) red, starboard (-Y) green
        SC.nav_light(h, lt, (x1 + 0.33, y, z + 0.1), "LightRed" if sy > 0 else "LightGreen")
        # registration on the outer face of the front pods
        right = Vector((-1, 0, 0)) if sy > 0 else Vector((1, 0, 0))
        n = Vector((0, sy, 0))
        code_len = (len(SC.REG[KIND]) * 1.55 - 0.55) * 0.42 / 2
        o = Vector(((x0 + x1) / 2, y + sy * (r + 0.005), z - 0.21)) - right * (code_len / 2)
        SC.stencil(h, SC.REG[KIND], o, right, (0, 0, 1), 0.42, "Palette:#23262c", n, depth=0.04)


def crane(h, lt):
    """slewing crane on the spine, boom folded forward into a cradle, strobe on the mast"""
    px, pz = -2.4, 5.0
    h.vcyl(px, 0, pz - 0.1, pz + 0.3, 0.62, seg=14, mat="Accent")
    h.vcyl(px, 0, pz + 0.3, pz + 0.38, 0.66, seg=14, mat=FRAME)
    h.box((px, 0, pz + 0.62), (1.1, 0.8, 0.48), HULL, bevel=0.05)
    h.box((px - 0.3, 0, pz + 0.62), (0.52, 0.84, 0.3), DARK)
    h.vcyl(px - 0.35, 0.3, pz + 0.86, pz + 1.7, 0.04, seg=5, mat=FRAME)
    SC.nav_light(h, lt, (px - 0.35, 0.3, pz + 1.75), "Light", r=0.08)
    piv = Vector((px + 0.35, 0, pz + 0.8))
    tip = Vector((3.35, 0, pz + 0.72))
    for sy in (-1, 1):
        h.beam(piv + Vector((0, sy * 0.2, 0.12)), tip + Vector((0, sy * 0.16, 0.1)), 0.1, 0.1, "Accent")
        h.beam(piv + Vector((0, sy * 0.2, -0.12)), tip + Vector((0, sy * 0.16, -0.06)), 0.09, 0.09, "Accent")
    n = 7
    for k in range(n + 1):
        a = piv.lerp(tip, k / n)
        h.beam(a + Vector((0, -0.18, 0.1)), a + Vector((0, 0.18, 0.1)), 0.05, 0.05, FRAME)
        if k < n:
            b = piv.lerp(tip, (k + 1) / n)
            h.beam(a + Vector((0, (-0.19 if k % 2 else 0.19), -0.08)), b + Vector((0, (0.19 if k % 2 else -0.19), 0.1)),
                   0.04, 0.04, FRAME)
    h.box(tuple(tip + Vector((0.18, 0, 0.02))), (0.36, 0.42, 0.34), HAZ)
    h.cyl(tip + Vector((0.25, -0.2, 0.0)), tip + Vector((0.25, 0.2, 0.0)), 0.2, seg=10, mat=METAL)
    h.beam((tip.x + 0.3, 0, tip.z - 0.2), (tip.x + 0.3, 0, tip.z - 0.55), 0.02, 0.02, METAL)
    h.box((tip.x + 0.3, 0, tip.z - 0.68), (0.26, 0.2, 0.26), HAZ, bevel=0.03)
    h.box((3.45, 0, 5.05), (0.18, 0.7, 0.9), FRAME)
    h.cyl((px + 0.5, 0, pz + 0.45), piv.lerp(tip, 0.35) - Vector((0, 0, 0.12)), 0.08, seg=6, mat=METAL)
    # ribbed containers on the spine beside the boom (fix 6)
    SC.ribbed_container(h, (0.9, 1.08, 4.97), (2.3, 0.95, 0.85), colour="Accent")
    SC.ribbed_container(h, (-0.6, -1.08, 4.97), (2.0, 0.95, 0.85), colour="Palette:#8c949e")


def legs():
    out = []
    for name, sx, sy in (("FL", 1, 1), ("FR", 1, -1), ("RL", -1, 1), ("RR", -1, -1)):
        hinge = Vector((sx * (3.9 if sx > 0 else 3.4), sy * 1.85, 1.86))
        lh, ld = 1.2, 1.84
        stow = -(90.0 + degrees(atan(lh / ld)))
        a = Anim("Leg_" + name, place_frame(hinge, 0.0 if sx > 0 else 180.0), stow)
        SC.leg_geometry(a, lh, ld, foot_r=0.5, strut=0.28)
        out.append(a)
    return out


def ramp():
    hinge = Vector((-4.30, 0.0, BELLY))
    L = 3.0
    drop = BELLY - 0.13
    slope = degrees(atan2(drop, sqrt(L * L - drop * drop)))
    a = Anim("Ramp", place_frame(hinge, 180.0), slope + 20.0)
    foot = SC.ramp_geometry(a, 2.0, L, slope)
    return a, hinge + Vector((-foot.y, 0, foot.z))


def side_door(h):
    """gull-wing hatch on -Y between the pods, hinged at its top edge, open 100 deg; hazard frame on the hull"""
    x0, x1, zt, zb = -0.95, 0.55, 3.85, 2.2
    y = -H.sec(-0.2)[0] - 0.02
    a = Anim("Door_Side", place_frame(Vector(((x0 + x1) / 2, y, zt)), -90.0), -100.0)
    w, hh, t = x1 - x0, zt - zb, 0.08
    with a.at(RX(100.0)):
        a.box((0, t / 2, -hh / 2), (w, t, hh), HULL, mats={"+y": DARK})
        a.box((0, -0.005, -hh * 0.5), (w * 0.94, 0.012, 0.1), "Accent")
        a.box((0, -0.006, -hh * 0.78), (w * 0.4, 0.012, 0.22), SC.DGLASS)
        for sx in (-1, 1):
            a.beam((sx * w * 0.42, 0.06, -0.05), (sx * w * 0.42, 0.45, -hh * 0.6), 0.04, 0.04, METAL)
    t0, t1 = H.t_at_z(-0.2, zt, -1), H.t_at_z(-0.2, zb, -1)
    t0, t1 = min(t0, t1), max(t0, t1)
    patch(h, H, x0 - 0.02, x1 + 0.02, t0, t1, 0.015, RUB, nx=1, nt=2)
    SC.hazard_frame(h, H, x0 - 0.02, x1 + 0.02, t0, t1, width=0.12, n=6, off=0.025)
    return a


def build():
    h, lt = Part("Hull"), Part("Lights")
    build_hull(h, lt)
    exits = {}
    for name, sy in (("L", 1), ("R", -1)):
        exits[name] = SC.engine_bell(h, (-4.7, sy * 1.72, ENG_Z), -90.0, r=0.74, L=2.3)
        pod(h, lt, -3.9, -1.05, sy)
        pod(h, lt, 0.65, 3.45, sy, nav=True)
    crane(h, lt)
    thr = []
    for name, x, y in (("FL", 4.55, 1.05), ("FR", 4.55, -1.05), ("RL", -5.55, 1.0), ("RR", -5.55, -1.0)):
        thr.append((Anchor("Thruster_Hover_" + name, hover(h, x, y), forward=(0, 0, -1), up=(1, 0, 0)), {"role": "hover"}))
    for name in ("L", "R"):
        thr.append((Anchor("Thruster_Main_" + name, exits[name], forward=(-1, 0, 0)), {"role": "main"}))
    # round 11 fix 6: the cargo ramp leaves from the -Y side of the tail, clear of the engine bells
    rp, foot = SF.airstair(h, lt, H, -5.0, -1, 2.15, 1.4, 3.1, 3.55)
    door = side_door(h)
    anchors = [(Anchor("Anchor_Ramp", foot, forward=(0, -1, 0)), {}),
               (Anchor("Anchor_Cargo", (-5.0, -H.sec(-5.0)[0] + 0.3, 2.15), forward=(0, -1, 0)), {})]
    return [h, lt, rp, door] + legs() + thr + anchors


def main():
    SC.build_ship(KIND, build, ao_dist=1.2)


if __name__ == "__main__":
    main()
