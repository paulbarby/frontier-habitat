"""
Frontier Habitat 4.0 - medium rover (V4_DESIGN section 5; critic round 16 steering). ART-B. Blender 5.2, --background.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/vehicle_rover_medium.py

Writes assets/models/vehicle_rover_medium.glb (contract: vehicle_common.py docstring).
Design: an 8-wheel, 6.7 m pressurised expedition rover. Off-white lofted hull with one accent band (logistics
purple #9B6BD6), graphite running gear (the small rover's wheel kit at 1.3x), 10 portholes, a wraparound windscreen,
a rear airlock hatch in the colony door-kit style (two leaves, window strip, chevrons at the seal, kick plate, green
status strip, hazard-striped frame) with a fold-up ramp, a roof rack for two Outpost Kits (the Cargo node), a
reactor pack with radiator fins, a high-gain dish, code MR-02. 6 seats inside (ART-NPC seat frame).
"""
import os
import sys
import math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vehicle_common as V                                 # noqa: E402
from vehicle_common import Node, Anchor, T, RX, RY, RZ, S, GRAPHITE, PLATE, SOLAR, LENS, INK   # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402
import ship_common as SC                                   # noqa: E402

VID = "rover_medium"
KIT = V.WheelKit(k=1.3, travel=(-0.15, 0.12), steer_max=20.0)
Y_KP = 0.95
Z_HUB = KIT.r
AXLES = [(2.25, 1), (0.75, 0), (-0.75, 0), (-2.25, -1)]    # (x, steer sign)
HULL_C = "Palette:#e6e3dc"                                 # off-white
FLOOR = 1.40                                               # cabin floor
X_TAIL = -3.05
DOOR_W, DOOR_Z0, DOOR_Z1 = 0.43, 1.42, 3.32                 # half width of the opening, sill, header
RAMP_HINGE = (-3.26, 0.0, 1.38)
RAMP_SLOPE, RAMP_LEN = 45.0, 1.81
SC.REG["rover_medium"] = "MR-02"

# critic round 19 fix 1: the lofted nose is gone; the hull ends at x 2.6 inside a faceted, framed cab (as the trader)
H = SC.LoftHull([(X_TAIL, 1.02, 3.42, 1.36, 2.15), (-2.90, 1.15, 3.50, 1.35, 2.15), (1.90, 1.15, 3.50, 1.35, 2.15),
                 (2.60, 1.10, 3.30, 1.38, 2.10)],
                n_top=2.4, n_bot=4.0)
XS = [X_TAIL, -2.97, -2.90, -2.3, -1.5, -0.75, 0.0, 0.75, 1.5, 1.9, 2.3, 2.6]
# fix 2: the band is t -2 ... +2 deg at the chine = 0.23 m high
TS = [0.0, 2.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0, 105.0, 120.0, 135.0, 150.0, 165.0, 178.0, 180.0, 182.0, 195.0,
      220.0, 245.0, 270.0, 295.0, 320.0, 345.0, 358.0]
BAND = "Palette:#8f7fae"          # logistics purple, desaturated (fix 2); Accent is now colony orange (fender lips)


def hull_mat(xa, xb, ta, tb):
    tm = (ta + tb) / 2
    xm = (xa + xb) / 2
    if tm >= 358.0 or tm <= 2.0 or 178.0 <= tm <= 182.0:
        return BAND                                        # the band at the chine, 0.23 m
    if 207.0 <= tm <= 333.0:
        return GRAPHITE                                    # belly
    if -2.3 <= xm <= 1.5 and (30.0 <= tm <= 60.0 or 120.0 <= tm <= 150.0):
        return SOLAR                                       # solar strips along the roof shoulders
    if -2.6 <= xm <= 1.9 and 60.0 <= tm <= 120.0:
        return "Palette:#c3c9d1"                           # roof walkway
    return HULL_C


def porthole(b, lights, x, t):
    p = H.pt(x, t)
    n = H.nrm(x, t)
    b.cyl(p - n * 0.02, p + n * 0.05, 0.19, seg=10, mat=GRAPHITE, cap0=False, cap1=True, cap_mat=GRAPHITE)
    V.lens(b, lights, p + n * 0.05, n, 0.15, housing=None, seg=10, lit="CabinWindow")      # fix 4: #FFD9A0 at 50 %
    # the day face of a porthole is dark glass, not a lamp lens: recolour the last disc
    b.fmat[-1] = SC.DGLASS


def door_kit(b):
    """rear airlock frame in the colony door-kit style (critic round 16: 'matches the airlock door kit')"""
    V.door_frame(b, X_TAIL, DOOR_W, DOOR_Z0, DOOR_Z1, HULL_C)


def hatch_leaf(side):
    """one leaf; side +1 = the left leaf (hinge at y +DOOR_W). Rest = open (swung out, pointing -X)."""
    return V.door_leaf("Door_Hatch" + ("L" if side > 0 else "R"), (X_TAIL - 0.14, side * DOOR_W, DOOR_Z0),
                       DOOR_W - 0.005, DOOR_Z1 - DOOR_Z0 - 0.01, side, HULL_C)


def ramp():
    r = Node("Ramp", SC.place_frame(RAMP_HINGE, 180.0), None, {"stow_deg": RAMP_SLOPE + 90.0})
    SC.ramp_geometry(r, 0.78, RAMP_LEN, RAMP_SLOPE, rails=False)
    return r


def body_parts(b, lights):
    # ---- chassis, skid plate, bumpers ------------------------------------------------------------
    b.prism_y([(-3.00, 0.72), (2.90, 0.72), (3.28, 0.95), (3.28, 1.38), (-3.02, 1.38)], -0.80, 0.80, GRAPHITE)
    b.box((0.0, 0, 0.66), (5.6, 1.30, 0.08), "Palette:#9aa3ad")
    b.beam((2.78, 0, 0.66), (3.24, 0, 0.88), 1.30, 0.08, "Palette:#9aa3ad", up=(-0.45, 0, 1))
    b.beam((3.40, -0.95, 1.00), (3.40, 0.95, 1.00), 0.14, 0.20, GRAPHITE)
    for sy in (-1, 1):
        b.beam((3.26, sy * 0.55, 1.00), (3.34, sy * 0.55, 1.00), 0.12, 0.12, GRAPHITE)
        b.box((3.475, sy * 0.66, 1.00), (0.012, 0.26, 0.14), "Palette:Hazard")
    b.box((3.475, 0, 1.00), (0.012, 0.26, 0.14), "Palette:Hazard")
    # winch on the bumper (fix 1): housing, orange drum, cable, hook
    b.box((3.56, 0, 1.00), (0.16, 0.50, 0.22), GRAPHITE)
    b.cyl((3.60, -0.20, 1.00), (3.60, 0.20, 1.00), 0.075, seg=10, mat="Accent")
    b.beam((3.66, 0, 1.00), (3.72, 0, 0.93), 0.02, 0.02, "Palette:#2c3036")
    b.box((3.735, 0, 0.90), (0.05, 0.03, 0.08), "Palette:Hazard")
    for sy in (-1, 1):                                                       # tow hooks
        b.box((3.49, sy * 0.85, 0.86), (0.08, 0.05, 0.10), "Palette:Hazard")
    for y in (-0.55, -0.36, 0.36, 0.55):                                   # headlights over the bumper
        V.lens(b, lights, (3.29, y, 1.22), (1, 0, 0), 0.06, housing=(0.05, 0.15, 0.12))
    # ---- pressure hull ------------------------------------------------------------------------------
    H.skin(b, XS, TS, hull_mat, cap_nose=True, cap_tail=True, nose_mat=HULL_C, tail_mat=HULL_C)
    # faceted, framed cab: body block 2.55-2.95, dark glass nose to 3.36 (lit copy in Lights = Window)
    SC.faceted_cockpit(b, lights, 2.55, 2.88, 3.36, w=1.12, zb=1.38, zt=3.36, c=0.34, front_top=2.72, front_w=0.94,
                       mull=GRAPHITE, body=HULL_C)
    for sy in (-1, 1):                                                              # band continues on the cab
        b.box((2.75, sy * 1.121, 2.10), (0.40, 0.006, 0.23), BAND)
    for x in (-1.55, -0.75, 0.05, 0.85, 1.65):
        porthole(b, lights, x, 20.0)
        porthole(b, lights, x, 160.0)
    SC.registration(b, H, "rover_medium", -2.52, 24.0, height=0.26, mat=INK, plate=HULL_C)
    # ---- rear airlock frame --------------------------------------------------------------------------
    door_kit(b)
    V.lens(b, lights, (X_TAIL - 0.15, 0, DOOR_Z1 + 0.22), (-1, 0, -1.0), 0.06, housing=(0.06, 0.18, 0.10))   # hatch flood
    for sy in (-1, 1):
        b.box((X_TAIL - 0.145, sy * (DOOR_W + 0.06), 1.62), (0.012, 0.10, 0.18), "LightRed")
        b.box((X_TAIL + 0.02, sy * 1.03, 2.15), (0.10, 0.04, 0.06), "BeaconAmber")       # rear corner markers
        b.box((2.90, sy * 1.125, 1.62), (0.12, 0.012, 0.06), "BeaconAmber")               # front corner markers
    # ---- roof: rack, reactor pack, dish, light bar, beacon, whips ------------------------------------
    for sy in (-1, 1):
        b.beam((-1.95, sy * 0.62, 3.64), (1.45, sy * 0.62, 3.64), 0.06, 0.05, GRAPHITE)
        for x in (-1.85, -0.25, 1.35):
            b.beam((x, sy * 0.62, 3.40), (x, sy * 0.62, 3.64), 0.05, 0.05, GRAPHITE)
    for x in (-1.85, -0.25, 1.35):
        b.beam((x, -0.62, 3.66), (x, 0.62, 3.66), 0.05, 0.04, GRAPHITE)
    b.box((-2.45, 0, 3.50), (0.95, 1.30, 0.12), GRAPHITE)                                 # reactor plinth
    b.cyl((-2.45, -0.52, 3.76), (-2.45, 0.52, 3.76), 0.21, seg=10, mat="Palette:#d9dde2")
    for y in (-0.30, 0.30):
        b.cyl((-2.45, y - 0.04, 3.76), (-2.45, y + 0.04, 3.76), 0.215, seg=10, mat="Palette:Hazard", cap0=False, cap1=False)
    for y in (-0.44, -0.15, 0.15, 0.44):                                           # radiator fins
        b.box((-2.45, y, 3.76), (0.90, 0.02, 0.56), GRAPHITE)
    b.vcyl(2.05, 0.0, 3.40, 3.72, 0.05, seg=6, mat=GRAPHITE)                              # dish mast
    with b.at(T(2.05, 0, 3.74), RY(-35.0)):
        b.lathe([(0.0, 0.0), (0.22, 0.03), (0.40, 0.11), (0.42, 0.13), (0.20, 0.06), (0.0, 0.03)],
                lambda k, i: "Palette:#eef0f2" if k < 3 else GRAPHITE, seg=12)
        b.cyl((0, 0, 0.03), (0, 0, 0.32), 0.015, seg=4, mat=GRAPHITE)
    b.box((2.80, 0, 3.42), (0.06, 1.10, 0.06), GRAPHITE)                                  # light bar on the cab roof
    for y in (-0.42, -0.14, 0.14, 0.42):
        V.lens(b, lights, (2.85, y, 3.42), (1, 0, -0.25), 0.05, housing=(0.05, 0.12, 0.09))
    b.vcyl(-2.05, -0.55, 3.56, 3.62, 0.07, seg=8, mat=GRAPHITE)
    b.vcyl(-2.05, -0.55, 3.62, 3.72, 0.055, 0.045, seg=8, mat="BeaconAmber")
    for y in (0.40, 0.55):
        b.vcyl(-2.10, y, 3.56, 4.30, 0.012, 0.008, seg=4, mat="Palette:#2c3036")
    # ---- strut tops ----------------------------------------------------------------------------------
    for x, st in AXLES:
        for sy in (-1, 1):
            KIT.strut_top(b, x, sy, Y_KP, Z_HUB)


def outpost_kits():
    """the Cargo node: two Outpost Kit crates on the roof rack"""
    c = Node("Cargo", None, None, {"role": "load", "item": "outpost_kit", "count": 2})
    for x in (-1.05, 0.55):
        z = 3.685
        c.box((x, 0, z + 0.28), (1.30, 1.00, 0.56), HULL_C, bevel=0.03)
        c.box((x, 0, z + 0.40), (1.32, 1.02, 0.08), BAND)
        for sx in (-1, 1):
            for sy in (-1, 1):
                c.box((x + sx * 0.58, sy * 0.505, z + 0.14), (0.12, 0.012, 0.20), "Palette:Hazard")
        c.box((x + 0.40, 0, z + 0.565), (0.10, 0.10, 0.012), "StatusGreen")
        c.beam((x, -0.53, z + 0.58), (x, 0.53, z + 0.58), 0.06, 0.012, GRAPHITE)
    return c


def build():
    b = Node("Body")
    lights = Node("Lights", None, None, {"role": "lamps"})
    body_parts(b, lights)
    out = [b]
    for n, (x, st) in enumerate(AXLES):
        for side, sy in (("L", 1), ("R", -1)):
            out += KIT.assembly("%d%s" % (n + 1, side), x, sy, st, Y_KP, Z_HUB)
    out += [hatch_leaf(1), hatch_leaf(-1), ramp(), outpost_kits(), lights]
    A = []
    seats = [(2.10, 0.45, "driver"), (2.10, -0.45, "passenger"), (0.95, 0.45, "passenger"), (0.95, -0.45, "passenger"),
             (-0.15, 0.45, "passenger"), (-0.15, -0.45, "passenger")]
    for i, (x, y, role) in enumerate(seats):
        A.append((Anchor("Seat_%d" % (i + 1), (x, y, FLOOR), forward=(1, 0, 0)),
                  {"role": role, "seat_top": round(FLOOR + 0.46, 3), "pressurised": True}, None))
    foot = Vector(RAMP_HINGE) + Vector((-RAMP_LEN * math.cos(math.radians(RAMP_SLOPE)), 0, -RAMP_HINGE[2]))
    A.append((Anchor("Anchor_Ramp", tuple(foot), forward=(1, 0, 0)), {"role": "walk-on point (ramp foot)"}, None))
    A.append((Anchor("Anchor_Hatch", (X_TAIL + 0.25, 0, FLOOR), forward=(1, 0, 0)), {"role": "fade point inside"}, None))
    A.append((Anchor("Anchor_Dock", (X_TAIL - 0.19, 0, FLOOR), forward=(-1, 0, 0)), {"role": "airlock docking face"}, None))
    A.append((Anchor("Anchor_Cargo", (-0.25, 0, 3.685), forward=(1, 0, 0)), {"role": "roof rack deck"}, None))
    for side, sy in (("L", 1), ("R", -1)):
        A.append((Anchor("Dust_" + side, (-2.25, sy * (Y_KP + KIT.off), 0.03), forward=(-1, 0, 0.35)), {"role": "dust"}, None))
    for y, nm in ((0.455, "HeadL"), (-0.455, "HeadR")):
        A.append(V.light_anchor("Light_" + nm, (3.31, y, 1.22), (1, 0, -0.08), "head", cone=45.0, rng=35.0))
    for y, nm in ((0.28, "WorkL"), (-0.28, "WorkR")):
        A.append(V.light_anchor("Light_" + nm, (2.88, y, 3.42), (1, 0, -0.35), "work", cone=70.0, rng=18.0))
    A.append(V.light_anchor("Light_Hatch", (X_TAIL - 0.17, 0, DOOR_Z1 + 0.20), (-1, 0, -1.0), "hatch", cone=80.0, rng=8.0))
    for y, nm in ((DOOR_W + 0.06, "TailL"), (-(DOOR_W + 0.06), "TailR")):
        A.append(V.light_anchor("Light_" + nm, (X_TAIL - 0.16, y, 1.62), (-1, 0, 0), "tail", colour="#ff3b30",
                                cone=90.0, rng=3.0))
    A.append(V.light_anchor("Light_Beacon", (-2.05, -0.55, 3.70), (0, 0, 1), "beacon", colour="#ffb020", cone=360.0, rng=8.0))
    return out + A


def main():
    req = ("Body", "Wheel_*", "Susp_*", "Steer_*", "Seat_1", "Seat_6", "Cargo", "Light_*", "Lights", "Door_HatchL",
           "Door_HatchR", "Ramp", "Anchor_Ramp", "Anchor_Dock")
    V.build_vehicle(VID, build, ao_dist=0.9, required=req)


if __name__ == "__main__":
    main()
