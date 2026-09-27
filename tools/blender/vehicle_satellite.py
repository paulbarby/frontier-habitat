"""
Frontier Habitat 4.0 - satellite, launch pad and launch rocket (V4_DESIGN section 5). ART-B. Blender 5.2, --background.

Run (Git Bash):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup \
      --python tools/blender/vehicle_satellite.py [-- --only satellite|launch_pad]

assets/models/satellite.glb  (map and orbit icon; origin = bus centre)
  +X = flight direction, -Z = nadir (towards the planet), wings along +-Y.
  Body            bus (gold foil = Accent #C9A54A), radiator, RCS, scanner, whips, nav lights
  Wing_L / Wing_R solar wings. Origin at the boom root; rotation about local X (= the boom axis) tracks the sun.
  Dish            high-gain dish on the nadir face; rotation about local X points it (+-30 deg)
  Lights          scanner glow + nav light lenses (always on in orbit)
  Anchor_Scan     scanner aperture; local +X = the scan direction (nadir): where RENDER starts the reveal band
assets/models/launch_pad.glb (origin = pad centre on the ground; the rocket stands at the centre)
  Body            octagonal deck (r 6.0, 0.5 m), flame trench, launch mount, service tower (12.5 m), fuel skid,
                  flood masts, edge lights
  Arm_Upper / Arm_Lower  service arms. Origin on the tower hinge; rotation about local X (vertical);
                  rest = connected to the rocket, stow_deg = swung clear (before launch)
  Rocket          the launch rocket (10.6 m, fairing holds the satellite). Origin at its base on the mount.
                  Launch = translate the node up along its local Z (and fade); child empty Thruster_Main (local +X = flame)
  Lights          flood lenses, aviation light
  Light_Flood_<i>, Light_Aviation, Anchor_Service, Anchor_Rocket
"""
import os
import sys
import math
from math import radians, cos, sin

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vehicle_common as V                                 # noqa: E402
from vehicle_common import Node, Anchor, T, RX, RY, RZ, S, GRAPHITE, SOLAR, INK   # noqa: E402
from mathutils import Vector, Matrix                       # noqa: E402
import ship_common as SC                                   # noqa: E402

WHITE = "Palette:#e6e3dc"


# ======================================================================================
# satellite
# ======================================================================================
def wing(side):
    """side +1 = Wing_L (+Y). Local X = boom axis (outward), local Z = the sun face normal (+Z at rest)"""
    # both wings: local X = world +Y, so one angle turns both the same way; the right wing is built mirrored
    Mx = Matrix(((0, -1, 0, 0), (1, 0, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))    # X=(0,1,0) Y=(-1,0,0) Z=(0,0,1)
    w = Node("Wing_" + ("L" if side > 0 else "R"), Matrix.Translation((0, side * 0.62, 0.1)) @ Mx, None,
             {"axis": "local X (world +Y for both wings)", "track": "sun"})
    w._stack[-1] = S(side, 1, 1)
    w._flip = side < 0
    w.cyl((0, 0, 0), (0.55, 0, 0), 0.04, seg=6, mat=GRAPHITE)
    for k in range(3):
        x0 = 0.55 + k * 1.05
        w.box((x0 + 0.5, 0, 0), (1.0, 1.15, 0.03), GRAPHITE, mats={"+z": SOLAR})
        for yy in (-0.19, 0.19):
            w.box((x0 + 0.5, yy, 0.018), (0.96, 0.012, 0.004), "Palette:#8a929c")
        w.box((x0 + 0.5, 0, 0.018), (0.012, 1.1, 0.004), "Palette:#8a929c")
    w.box((3.72, 0, 0), (0.06, 1.20, 0.05), GRAPHITE)
    w.box((3.76, 0, 0.03), (0.04, 0.06, 0.04), "LightRed" if side < 0 else "LightGreen")
    return w


def dish():
    Mx = Matrix(((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
    d = Node("Dish", Matrix.Translation((0.25, 0, -0.80)) @ Mx, None, {"axis": "local X", "range_deg": 30.0})
    d.cyl((0, 0, 0.05), (0, 0, -0.25), 0.04, seg=6, mat=GRAPHITE)
    with d.at(T(0, 0, -0.25), RX(180)):
        d.lathe([(0.0, 0.0), (0.25, 0.03), (0.52, 0.13), (0.54, 0.15), (0.26, 0.06), (0.0, 0.03)],
                lambda k, i: "Palette:#eef0f2" if k < 3 else GRAPHITE, seg=14)
        d.cyl((0, 0, 0.03), (0, 0, 0.40), 0.015, seg=4, mat=GRAPHITE)
    return d


def build_satellite():
    b = Node("Body")
    lights = Node("Lights", None, None, {"role": "lamps"})
    b.box((0, 0, 0), (1.2, 1.2, 1.5), "Accent", bevel=0.05)                         # gold foil bus
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((sx * 0.6, sy * 0.6, 0), (0.05, 0.05, 1.52), GRAPHITE)
    b.box((0, 0, 0.77), (1.0, 1.0, 0.04), WHITE)                                   # radiator
    for x in (-0.3, 0.0, 0.3):
        b.box((x, 0, 0.795), (0.02, 0.96, 0.01), "Palette:#8a929c")
    b.box((-0.35, 0.3, -0.80), (0.3, 0.3, 0.12), GRAPHITE)                         # scanner housing
    b.cyl((-0.35, 0.3, -0.86), (-0.35, 0.3, -0.92), 0.10, seg=10, mat=GRAPHITE)
    V.lens(b, lights, (-0.35, 0.3, -0.925), (0, 0, -1), 0.08, housing=None, seg=10)
    for sx in (-1, 1):                                                             # RCS pods
        for sy in (-1, 1):
            b.box((sx * 0.62, sy * 0.62, 0.72), (0.08, 0.08, 0.08), "Palette:#8a929c")
    for y in (-0.35, 0.35):
        b.cyl((-0.55, y, 0.75), (-0.55, y, 1.55), 0.01, seg=4, mat=GRAPHITE)
    b.box((0.605, 0, 0.3), (0.012, 0.8, 0.14), WHITE)
    SC.stencil(b, "SAT-1", (0.612, -0.36, 0.25), (0, 1, 0), (0, 0, 1), 0.10, INK, (1, 0, 0), depth=0.008)
    out = [b, wing(1), wing(-1), dish(), lights]
    A = [(Anchor("Anchor_Scan", (-0.35, 0.3, -0.93), forward=(0, 0, -1), up=(1, 0, 0)), {"role": "scanner"}, None)]
    return out + A


# ======================================================================================
# launch pad + rocket
# ======================================================================================
DECK = 0.50
MOUNT = 1.40                 # rocket base height (on the launch mount)
TOWER = (0.0, 3.4)           # tower centre (x, y)
TOWER_H = 12.5


def arm(name, z, length):
    """service arm: hinge on the tower face, reaching to the rocket (-Y). Local X = vertical hinge axis."""
    hinge = Vector((TOWER[0], TOWER[1] - 0.65, z))
    Mx = Matrix(((0, 0, 1, 0), (0, -1, 0, 0), (1, 0, 0, 0), (0, 0, 0, 1)))    # X=(0,0,1) Y=(0,-1,0) Z=(1,0,0)
    a = Node(name, Matrix.Translation(hinge) @ Mx, None, {"stow_deg": 90.0})
    # local: X up, Y along the arm, Z sideways
    a.box((0.0, length / 2, 0), (0.08, length, 0.60), "Palette:#6b7078")                     # walkway
    for sz in (-1, 1):
        a.beam((0.02, 0, sz * 0.30), (0.02, length, sz * 0.30), 0.30, 0.05, "Accent", up=(0, 0, 1))    # side trusses
        a.beam((0.45, 0, sz * 0.30), (0.45, length, sz * 0.30), 0.05, 0.05, GRAPHITE)                  # rails
    a.box((0.0, length + 0.02, 0), (0.50, 0.06, 0.66), GRAPHITE)                              # clamp pad
    return a


def rocket():
    r = Node("Rocket", Matrix.Translation((0, 0, MOUNT)), None, {"launch": "translate local Z", "height_m": 10.6})
    r.lathe([(0.46, -0.72), (0.30, -0.35), (0.22, 0.0)], "Palette:#6b7078", seg=12, caps=False)   # engine bell
    r.lathe([(0.22, 0.0), (0.30, -0.35), (0.44, -0.70)], "Palette:#23262c", seg=12, caps=False)   # bell inside
    r.lathe([(0.0, 0.0), (0.60, 0.0), (0.60, 5.5), (0.60, 6.1), (0.55, 6.1), (0.55, 7.9), (0.62, 8.0), (0.62, 8.6),
             (0.50, 9.4), (0.28, 10.1), (0.0, 10.6)],
            lambda k, i: {0: GRAPHITE, 2: GRAPHITE, 3: GRAPHITE, 6: "Accent"}.get(k, WHITE), seg=16)
    for k, z in enumerate((1.2, 3.8)):
        r.cyl((0, 0, z), (0, 0, z + 0.25), 0.605, seg=16, mat="Accent" if k else GRAPHITE, cap0=False, cap1=False)
    for ang in (45.0, 135.0, 225.0, 315.0):                                        # fins
        with r.at(RZ(ang)):
            r.beam((0.60, 0, 0.1), (1.05, 0, 0.05), 0.06, 0.06, GRAPHITE)
            r.poly([Vector((0.60, 0, 0.05)), Vector((1.08, 0, 0.0)), Vector((1.08, 0, 0.45)), Vector((0.60, 0, 1.45))], GRAPHITE)
            r.poly([Vector((0.60, 0, 1.45)), Vector((1.08, 0, 0.45)), Vector((1.08, 0, 0.0)), Vector((0.60, 0, 0.05))], GRAPHITE)
    for ang in (90.0, 270.0):                                                      # code on both sides
        a = radians(ang)
        n = Vector((cos(a), sin(a), 0))
        right = (-n).cross(Vector((0, 0, 1)))
        o = n * 0.612 - right * 0.40 + Vector((0, 0, 4.4))
        SC.stencil(r, "LP-01", o, right, (0, 0, 1), 0.26, INK, n, depth=0.01)
    return r


def build_launch_pad():
    b = Node("Body")
    lights = Node("Lights", None, None, {"role": "lamps"})
    oct_ = [(6.0 * cos(radians(22.5 + 45 * k)), 6.0 * sin(radians(22.5 + 45 * k))) for k in range(8)]
    b.prism(oct_, 0.0, DECK, "Palette:#8a929c", cap_mat="Palette:#9aa3ad")
    ring_o = [(5.6 * cos(radians(22.5 + 45 * k)), 5.6 * sin(radians(22.5 + 45 * k))) for k in range(8)]
    b.prism(ring_o, DECK, DECK + 0.01, "Palette:Hazard", cap0=False)
    b.prism([(x * 0.96, y * 0.96) for x, y in ring_o], DECK + 0.005, DECK + 0.015, "Palette:#9aa3ad", cap0=False)
    b.box((0, -1.6, DECK + 0.017), (2.0, 5.6, 0.01), "Palette:#1f2226")                        # flame trench
    for y in (-3.6, -2.4, -1.2):
        b.box((0, y, DECK + 0.02), (2.1, 0.12, 0.01), "Palette:Hazard")
    for k in range(8):                                                                 # edge lights
        a = radians(45 * k)
        b.box((5.8 * cos(a), 5.8 * sin(a), DECK + 0.06), (0.12, 0.12, 0.12), "BeaconAmber")
    # launch mount: 4 posts + a ring the rocket stands on
    for k in range(4):
        a = radians(45 + 90 * k)
        b.box((0.95 * cos(a), 0.95 * sin(a), (DECK + MOUNT) / 2), (0.30, 0.30, MOUNT - DECK), "Accent")
    ring = [(1.15 * cos(radians(22.5 + 45 * k)), 1.15 * sin(radians(22.5 + 45 * k))) for k in range(8)]
    inner = [(0.70 * cos(radians(22.5 + 45 * k)), 0.70 * sin(radians(22.5 + 45 * k))) for k in range(8)]
    for k in range(8):                                                                 # an octagonal frame (8 beams)
        p0, p1 = ring[k], ring[(k + 1) % 8]
        b.beam((p0[0], p0[1], MOUNT - 0.08), (p1[0], p1[1], MOUNT - 0.08), 0.35, 0.16, GRAPHITE)
    # service tower: 4 posts, rings, diagonals on the three outer faces
    tx, ty = TOWER
    cs = [(tx - 0.65, ty - 0.65), (tx + 0.65, ty - 0.65), (tx + 0.65, ty + 0.65), (tx - 0.65, ty + 0.65)]
    for (x, y) in cs:
        b.beam((x, y, DECK), (x, y, TOWER_H), 0.14, 0.14, "Accent", caps=False)
    levels = [DECK + 1.5 * k for k in range(1, 9)]
    for z in levels:
        for k in range(4):
            (x0, y0), (x1, y1) = cs[k], cs[(k + 1) % 4]
            b.beam((x0, y0, z), (x1, y1, z), 0.07, 0.07, GRAPHITE, caps=False)
    for z0, z1 in zip([DECK] + levels[:-1], levels):
        for k in (1, 2, 3):                                                          # skip the rocket-side face (k=0)
            (x0, y0), (x1, y1) = cs[k], cs[(k + 1) % 4]
            b.beam((x0, y0, z0), (x1, y1, z1), 0.05, 0.05, GRAPHITE, caps=False)
    for z in (MOUNT + 5.1, MOUNT + 8.4):                                              # platforms at the arms
        b.box((tx, ty, z - 0.06), (1.5, 1.5, 0.08), "Palette:#6b7078")
    b.box((tx, ty, TOWER_H + 0.05), (1.5, 1.5, 0.10), GRAPHITE)
    b.cyl((tx + 0.6, ty + 0.6, TOWER_H + 0.1), (tx + 0.6, ty + 0.6, TOWER_H + 1.6), 0.03, seg=4, mat=GRAPHITE)   # rod
    b.vcyl(tx - 0.55, ty + 0.55, TOWER_H + 0.1, TOWER_H + 0.25, 0.07, seg=8, mat="LightRed")      # aviation light
    # fuel skid with a pipe to the tower
    for y in (1.8, 2.5):
        b.cyl((-4.8, y, DECK + 0.45), (-3.2, y, DECK + 0.45), 0.32, seg=10, mat=WHITE)
        b.cyl((-4.2, y, DECK + 0.45), (-4.1, y, DECK + 0.45), 0.325, seg=10, mat="Accent", cap0=False, cap1=False)
    b.box((-4.0, 2.15, DECK + 0.06), (1.9, 1.5, 0.12), GRAPHITE)
    b.beam((-3.2, 2.15, DECK + 0.30), (tx - 0.65, 2.95, DECK + 0.30), 0.10, 0.10, GRAPHITE)
    # flood masts aimed at the rocket
    floods = []
    for k, (x, y) in enumerate(((-4.3, -3.6), (4.3, -3.6))):
        b.beam((x, y, DECK), (x, y, 7.0), 0.16, 0.16, GRAPHITE)
        b.box((x, y, 7.05), (0.5, 0.2, 0.3), GRAPHITE)
        aim = (Vector((0, 0, 6.0)) - Vector((x, y, 7.0))).normalized()
        V.lens(b, lights, Vector((x, y, 7.05)) + aim * 0.12, aim, 0.12, housing=None, seg=8)
        floods.append((Vector((x, y, 7.05)) + aim * 0.14, aim))
    out = [b, arm("Arm_Lower", MOUNT + 5.1, TOWER[1] - 0.65 - 0.58), arm("Arm_Upper", MOUNT + 8.4, TOWER[1] - 0.65 - 0.64),
           rocket(), lights]
    A = []
    for k, (p, aim) in enumerate(floods):
        A.append(V.light_anchor("Light_Flood_%d" % (k + 1), tuple(p), tuple(aim), "flood", cone=40.0, rng=20.0))
    A.append(V.light_anchor("Light_Aviation", (tx - 0.55, ty + 0.55, TOWER_H + 0.2), (0, 0, 1), "aviation",
                            colour="#ff3b30", cone=360.0, rng=4.0))
    A.append((Anchor("Anchor_Rocket", (0, 0, MOUNT), forward=(1, 0, 0)), {"role": "rocket base"}, None))
    A.append((Anchor("Anchor_Service", (-3.0, 0.4, DECK), forward=(1, 0, 0)), {"role": "crew work point"}, None))
    A.append((Anchor("Thruster_Main", (0, 0, MOUNT - 0.72), forward=(0, 0, -1), up=(1, 0, 0)), {"role": "main"}, "Rocket"))
    return out + A


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else ["satellite", "launch_pad"]
    if "satellite" in only:
        V.build_vehicle("satellite", build_satellite, ao_dist=0.6, fname="satellite.glb", ground=False,
                        required=("Body", "Wing_L", "Wing_R", "Dish", "Anchor_Scan"))
    if "launch_pad" in only:
        V.build_vehicle("launch_pad", build_launch_pad, ao_dist=1.4, fname="launch_pad.glb", ao_samples=24,
                        required=("Body", "Arm_Upper", "Arm_Lower", "Rocket", "Thruster_Main", "Light_*"))


if __name__ == "__main__":
    main()
